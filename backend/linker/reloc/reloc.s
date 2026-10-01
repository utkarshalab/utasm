;
; ============================================================================
; File        : src/linker/reloc.s
; Project     : utasm
; Description : Relocation engine for the utasm linker.
;                Records, resolves, and applies x86_64 relocations across
;                all output formats (ELF64 .o and flat binary).
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"
%include "include/elf.inc"

; --- External Symbols ---
extern  mem_zero
extern  symbol_find
extern  arena_alloc

%define RELOC_DELETED_TYPE 0xFFFFFFFF   ; a relocation written in place

[SECTION .bss]
resolved_here:  resb 1                  ; some were written in place

[SECTION .text]

; ============================================================================
; reloc_record
; ============================================================================
;
; reloc_record
; Adds one relocation entry to the AsmCtx reloc table.
; Called by the encoder whenever it emits a symbol reference that cannot
; be resolved at encode time (forward references, extern labels).

; Input  : rdi = AsmCtx*
;            rsi = byte offset within .text of the patch site
;            rdx = pointer to symbol name string (null-terminated)
;            rcx = addend (signed 64-bit, usually -4 for PC32)
;            r8  = relocation type (R_X86_64_* constant)
; Output : rax = EXIT_OK or EXIT_OOM
;
global reloc_record
reloc_record:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi               ; AsmCtx
    mov     r12, rsi               ; offset
    mov     r13, rdx               ; sym name ptr
    mov     r14, rcx               ; addend
    ; r8 = reloc type (held in r8 throughout)

    ; "sym wrt ..plt" and friends: the statement asked for another type
    xor     r9d, r9d                       ; RELOC_flags
    movzx   eax, byte [rel reloc_wrt]
    test    eax, eax
    jz      .wrt_done
    mov     byte [rel reloc_wrt], 0
    cmp     eax, WRT_SYM
    jne     .wrt_type
    mov     r9d, RELOC_FLAG_SYM
    jmp     .wrt_done
.wrt_type:
    mov     ecx, R_X86_64_PLT32
    cmp     eax, WRT_PLT
    je      .wrt_set
    mov     ecx, R_X86_64_GOTPCREL
    cmp     eax, WRT_GOTPCREL
    je      .wrt_set
    mov     ecx, R_X86_64_GOTOFF64
    cmp     eax, WRT_GOTOFF
    je      .wrt_set
    mov     ecx, R_X86_64_GOTTPOFF
    cmp     eax, WRT_TLSIE
    je      .wrt_set
    mov     ecx, R_X86_64_GOT32            ; WRT_GOT
    cmp     r8d, R_X86_64_64
    jne     .wrt_set
    mov     ecx, 27                        ; R_X86_64_GOT64 for a 64-bit field
.wrt_set:
    mov     r8d, ecx
.wrt_done:

    ; Check capacity
    mov     eax, [rbx + ASMCTX_nrelocs]
    cmp     eax, MAX_RELOC
    jge     .oom

    ; Get slot pointer: reloctab + count * RELOC_SIZE
    mov     rcx, rax
    imul    rcx, RELOC_SIZE
    mov     rdx, [rbx + ASMCTX_relocs]
    add     rdx, rcx               ; rdx = pointer to new slot

    ; Zero the slot
    push    rdx
    mov     rdi, rdx
    mov     rsi, RELOC_SIZE
    call    mem_zero
    pop     rdx

    ; Fill fields
    mov     byte [rdx + RELOC_tag], TAG_RELOC
    mov     [rdx + RELOC_offset], r12
    mov     [rdx + RELOC_sym],    r13
    mov     [rdx + RELOC_addend], r14
    mov     [rdx + RELOC_type],   r8d
    mov     [rdx + RELOC_flags],  r9b
    extern  error_loc_file, error_loc_line
    mov     eax, [rel error_loc_line]      ; where it came from, for errors
    mov     [rdx + RELOC_line], eax
    mov     rax, [rel error_loc_file]
    mov     [rdx + RELOC_file], rax

    ; Target section: the one currently being emitted into
    mov     rcx, [rbx + ASMCTX_curr_sec]
    test    rcx, rcx
    jnz     .have_target_sec
    mov     rcx, [rbx + ASMCTX_sections]
    test    rcx, rcx
    jz      .no_target_sec
    mov     rcx, [rcx]             ; fall back to the first section
    test    rcx, rcx
    jz      .no_target_sec
.have_target_sec:
    mov     [rdx + RELOC_section], rcx

    ; Increment count
    inc     dword [rbx + ASMCTX_nrelocs]

    xor     rax, rax
    jmp     .done

.oom:
    mov     rax, EXIT_OOM
    jmp     .done

.no_target_sec:
    mov     rax, EXIT_INTERNAL

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ============================================================================
; reloc_resolve_all
; ============================================================================
;
; reloc_resolve_all
; Second-pass resolver: walks every recorded relocation, looks up the
; symbol in the symbol table, computes the final patch value, and writes
; it into the in-memory output buffer.

; Supports the following relocation types:
;   R_X86_64_PC32    â€” 32-bit PC-relative (call/jmp to near symbols)
;   R_X86_64_64      â€” 64-bit absolute address
;   R_X86_64_32      â€” 32-bit zero-extended absolute
;   R_X86_64_32S     â€” 32-bit sign-extended absolute
;   R_X86_64_PLT32   â€” Same as PC32 for direct call resolution

; Input  : rdi = AsmCtx*
;            rsi = pointer to output buffer base (virtual address 0 = file offset 0)
;            rdx = base virtual address (load address / ORG)
; Output : rax = EXIT_OK or EXIT_UNDEF_REF / EXIT_OFFSET_RANGE
;
global reloc_resolve_all
reloc_resolve_all:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi               ; AsmCtx
    ; rsi/rdx (output buffer, base VA) are unused: patching targets each
    ; relocation own section data buffer.

    ; A relocatable object (not bin, not --standalone) leaves every field
    ; to the linker, which reads the addend from .rela: the fields stay
    ; zero, as NASM writes them.
    cmp     byte [rbx + ASMCTX_fmt], FMT_BIN
    je      .patch
    cmp     byte [rbx + ASMCTX_standalone], 1
    je      .patch

    ; A relocatable object is not patched, but what it refers to must
    ; still be defined here or declared extern (or common), as in NASM:
    ; "symbol `x' not defined".
    mov     r14, [rbx + ASMCTX_relocs]
    mov     r15d, [rbx + ASMCTX_nrelocs]
    xor     r12d, r12d
    mov     byte [rel resolved_here], 0
.check_next:
    cmp     r12d, r15d
    jge     .check_done
    mov     r13, r12
    imul    r13, RELOC_SIZE
    add     r13, r14
    inc     r12d
    test    byte [r13 + RELOC_flags], RELOC_FLAG_SECTION
    jnz     .check_next                    ; against a section: always there
    mov     rsi, [r13 + RELOC_sym]
    test    rsi, rsi
    jz      .check_next
    mov     rdi, rbx
    call    symbol_find
    test    rax, rax
    jnz     .undef
    cmp     word [rdx + SYMBOL_section], 0
    jne     .check_local
    cmp     byte [rdx + SYMBOL_kind], SYM_EXTERN
    je      .check_next
    cmp     byte [rdx + SYMBOL_kind], SYM_COMMON
    je      .check_next
    jmp     .undef

.check_local:
    ; A constant used before its "equ" ("mov ecx, len"): its value, written
    ; in place, as NASM (which reads the source more than once) has it
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .check_pcrel
    mov     eax, [r13 + RELOC_type]
    mov     ecx, 8
    cmp     eax, R_X86_64_64
    je      .abs_width
    mov     ecx, 4
    cmp     eax, R_X86_64_32
    je      .abs_width
    cmp     eax, R_X86_64_32S
    je      .abs_width
    mov     ecx, 2
    cmp     eax, 12                        ; R_X86_64_16
    je      .abs_width
    mov     ecx, 1
    cmp     eax, 14                        ; R_X86_64_8
    jne     .check_next
.abs_width:
    mov     r8, [r13 + RELOC_section]
    test    r8, r8
    jz      .check_next
    mov     r9, [r8 + SECTION_data]
    test    r9, r9
    jz      .check_next
    add     r9, [r13 + RELOC_offset]
    mov     rax, [rdx + SYMBOL_value]
    add     rax, [r13 + RELOC_addend]
    cmp     ecx, 8
    jne     .abs_narrow
    mov     [r9], rax
    jmp     .local_done
.abs_narrow:
    cmp     ecx, 4
    jne     .abs_16
    ; 32: zero-extended (R_X86_64_32) or sign-extended (32S) must hold it
    mov     r10d, eax
    cmp     dword [r13 + RELOC_type], R_X86_64_32S
    jne     .abs_32_check
    movsxd  r10, eax
.abs_32_check:
    cmp     r10, rax
    jne     .local_range
    mov     [r9], eax
    jmp     .local_done
.abs_16:
    mov     r10, rax                       ; 16 / 8: either signedness
    sar     r10, 15
    cmp     ecx, 2
    je      .abs_check_small
    mov     r10, rax
    sar     r10, 7
.abs_check_small:
    inc     r10
    cmp     r10, 1
    jbe     .abs_small_ok
    ; or as unsigned
    mov     r10, rax
    shl     ecx, 3
    shr     r10, cl
    shr     ecx, 3
    test    r10, r10
    jnz     .local_range
.abs_small_ok:
    cmp     ecx, 2
    jne     .abs_byte
    mov     [r9], ax
    jmp     .local_done
.abs_byte:
    mov     [r9], al
    jmp     .local_done

.check_pcrel:
    ; A PC-relative reference to a symbol of its own section is a fixed
    ; distance: NASM writes it in place and leaves no relocation ("call f",
    ; "jmp l", "[rel x]", global or not). So does utasm.
    mov     eax, [r13 + RELOC_type]
    mov     ecx, 4
    cmp     eax, R_X86_64_PC32
    je      .local_width
    mov     ecx, 1
    cmp     eax, R_X86_64_PC8
    je      .local_width
    mov     ecx, 2
    cmp     eax, 13                        ; R_X86_64_PC16
    jne     .check_next
.local_width:
    mov     r8, [r13 + RELOC_section]
    test    r8, r8
    jz      .check_next
    movzx   eax, word [rdx + SYMBOL_section]
    cmp     eax, [r8 + SECTION_index]
    jne     .check_next
    ; S + A - P, written in the code
    mov     rax, [rdx + SYMBOL_value]
    add     rax, [r13 + RELOC_addend]
    sub     rax, [r13 + RELOC_offset]
    mov     r9, [r8 + SECTION_data]
    test    r9, r9
    jz      .check_next
    add     r9, [r13 + RELOC_offset]
    cmp     ecx, 4
    jne     .local_narrow
    movsxd  r10, eax
    cmp     r10, rax
    jne     .local_range
    mov     [r9], eax
    jmp     .local_done
.local_narrow:
    cmp     ecx, 2
    jne     .local_byte
    movsx   r10, ax
    cmp     r10, rax
    jne     .local_range
    mov     [r9], ax
    jmp     .local_done
.local_byte:
    movsx   r10, al
    cmp     r10, rax
    jne     .local_range
    mov     [r9], al
.local_done:
    mov     dword [r13 + RELOC_type], RELOC_DELETED_TYPE
    mov     byte [rel resolved_here], 1
    jmp     .check_next
.local_range:
    mov     rdi, [r13 + RELOC_file]        ; "jmp short" too far, at its line
    mov     esi, [r13 + RELOC_line]
    extern  error_set_location
    call    error_set_location
    mov     rax, EXIT_OFFSET_RANGE
    jmp     .ret

.check_done:
    ; drop the relocations written in place, keeping the others in order
    cmp     byte [rel resolved_here], 0
    je      .done
    xor     ecx, ecx                       ; read index
    xor     edx, edx                       ; write index
.compact:
    cmp     ecx, [rbx + ASMCTX_nrelocs]
    jae     .compacted
    imul    rsi, rcx, RELOC_SIZE
    add     rsi, r14
    inc     ecx
    cmp     dword [rsi + RELOC_type], RELOC_DELETED_TYPE
    je      .compact
    imul    rdi, rdx, RELOC_SIZE
    add     rdi, r14
    inc     edx
    cmp     rdi, rsi
    je      .compact
    push    rcx
    mov     ecx, RELOC_SIZE
    cld
    rep     movsb
    pop     rcx
    jmp     .compact
.compacted:
    mov     [rbx + ASMCTX_nrelocs], edx
    jmp     .done

.patch:

    mov     r14, [rbx + ASMCTX_relocs]
    mov     r15d, [rbx + ASMCTX_nrelocs]
    xor     r12d, r12d             ; index — must survive the calls below

.loop:
    cmp     r12d, r15d
    jge     .done

    mov     r13, r12
    imul    r13, RELOC_SIZE
    add     r13, r14                       ; r13 = RELOC* (survives calls)

    ; Resolve symbol
    mov     rdi, rbx
    mov     rsi, [r13 + RELOC_sym]         ; sym name ptr (symbol_find takes rsi)
    call    symbol_find
    test    rax, rax
    jnz     .check_undef
    mov     r10, rdx                       ; r10 = SYMBOL*
    
    ; Check if symbol is undefined
    movzx   eax, word [r10 + SYMBOL_section]
    IF ax, e, 0                            ; SHN_UNDEF
        ; Only error if we are in flat-binary mode. ASMCTX_fmt is the
        ; authoritative output selection; compatibility flag bits can no
        ; longer become stale after repeated -f options.
        cmp     byte [rbx + ASMCTX_fmt], FMT_BIN
        je      .undef
        cmp     byte [r10 + SYMBOL_kind], SYM_EXTERN
        jne     .undef                     ; neither defined nor extern
        jmp     .next                      ; Skip patching, keep for .rela
        ENDIF
    
    ; Check for special sections
    IF ax, e, SHN_ABS
        mov     rax, [r10 + SYMBOL_value]
        jmp     .calc_patch_va
        ENDIF
    IF ax, ae, MAX_SECTIONS        ; unsigned: 0xFF00-0xFFFF are reserved
        mov     rax, EXIT_INVALID_SECTION
        jmp     .ret
        ENDIF

    mov     rdi, [rbx + ASMCTX_sections]
    dec     eax                              ; ELF index is 1-based; array is 0-based
    mov     r8, [rdi + rax * 8]              ; r8 = SECTION*
    test    r8, r8
    jz      .undef
    
    mov     r9, [r8 + SECTION_addr]          ; r9 = section VA
    mov     rax, [r10 + SYMBOL_value]
    add     rax, r9                          ; rax = sym_va

.calc_patch_va:
    push    rax                              ; Preserve sym_va

    ; patch_offset = reloc.offset
    mov     r8, [r13 + RELOC_offset]

    ; patch_ptr = section data + patch_offset
    ; (the section buffer is what gets written to the output file)
    mov     r9, [r13 + RELOC_section]
    mov     r9, [r9 + SECTION_data]
    add     r9, r8                           ; r9 = patch_ptr

    ; patch_va = reloc.section.addr + patch_offset
    mov     rax, [r13 + RELOC_section]       ; rax = SECTION*
    mov     r10, [rax + SECTION_addr]
    add     r10, r8                          ; r10 = patch_va

    ; Apply the relocation via unified helper
    mov     rdi, r13                       ; RELOC*
    pop     rsi                            ; rsi = sym_va (restored)
    mov     rdx, r9                        ; rdx = patch_ptr
    mov     rcx, r10                       ; rcx = patch_va
    call    reloc_apply_one
    check_err

.next:
    inc     r12d
    jmp     .loop

.done:
    xor     rax, rax
    jmp     .ret

.check_undef:
.undef:
    ; "file:line: error: symbol `x' not defined" at the statement that
    ; used it, then "did you mean" (utasm.s prints both)
    mov     rdi, [r13 + RELOC_file]
    mov     esi, [r13 + RELOC_line]
    extern  error_set_location
    call    error_set_location
    mov     rdi, [r13 + RELOC_sym]
    extern  error_set_subject
    call    error_set_subject
    mov     rdi, rbx
    mov     rsi, [r13 + RELOC_sym]
    extern  error_hint_symbol
    call    error_hint_symbol
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .ret

.range_err:
    mov     rax, EXIT_OFFSET_RANGE

.error:
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [reloc_apply_one]
; * Purpose: Unified relocation applier for all targets.
; ;
global reloc_apply_one
reloc_apply_one:
    prologue
    push    rbx
    mov     rbx, rdi               ; RELOC*
    mov     rax, rsi               ; sym_va
    mov     r8, rdx                ; patch_ptr
    mov     r9, rcx                ; patch_va
    
    mov     r11d, [rbx + RELOC_type]
    mov     r10, [rbx + RELOC_addend]

    ; ---- Dispatch ----
    cmp     r11d, R_X86_64_64
    je      .abs64
    cmp     r11d, R_X86_64_32
    je      .abs32
    cmp     r11d, R_X86_64_32S
    je      .abs32
    cmp     r11d, R_X86_64_16
    je      .abs16
    cmp     r11d, R_X86_64_8
    je      .abs8
    cmp     r11d, R_AARCH64_ADR_PREL_PG_HI21
    je      .aarch64_adrp
    cmp     r11d, R_AARCH64_ADD_ABS_LO12_NC
    je      .aarch64_lo12
    cmp     r11d, R_AARCH64_LDST64_ABS_LO12_NC
    je      .aarch64_ldst64
    cmp     r11d, R_AARCH64_LDST32_ABS_LO12_NC
    je      .aarch64_ldst32
    cmp     r11d, R_AARCH64_LDST16_ABS_LO12_NC
    je      .aarch64_ldst16
    cmp     r11d, R_AARCH64_LDST8_ABS_LO12_NC
    je      .aarch64_ldst8

    cmp     r11d, R_AARCH64_JMP26
    je      .aarch64_jmp26
    cmp     r11d, R_AARCH64_CALL26
    je      .aarch64_jmp26

    cmp     r11d, R_RISCV_HI20
    je      .riscv_hi20
    cmp     r11d, R_RISCV_PCREL_LO12_I
    je      .riscv_lo12_i
    cmp     r11d, R_RISCV_PCREL_LO12_S
    je      .riscv_lo12_s

    cmp     r11d, R_X86_64_PC8
    je      .pc8

    ; Default: PC-relative (x86_64 PC32, etc)
    ; The addend already carries -pc_adjust (see amd64_emit_reloc).
    sub     rax, r9                ; Target - Patch_VA
    mov     r10, [rbx + RELOC_addend]
    add     rax, r10
    
    ; RANGE CHECK: Must fit in signed 32-bit
    mov     rcx, rax
    movsxd  rdx, eax
    cmp     rcx, rdx
    jne     .range_err
    
    mov     [r8], eax
    jmp     .done_patch

.range_err:
    mov     rax, EXIT_OFFSET_RANGE
    jmp     .ret

.pc8:
    ; `jmp/jcc short` to a forward label: a 1-byte PC-relative field.
    ; Previously this fell into the PC32 path, which wrote 4 bytes (over
    ; the next instruction) and never range-checked the value.
    sub     rax, r9                ; Target - Patch_VA
    add     rax, r10               ; + addend (-1: the field ends the jump)
    movsx   rcx, al
    cmp     rcx, rax
    jne     .range_err             ; target out of short-jump reach
    mov     [r8], al
    jmp     .done_patch

.abs64:
    add     rax, r10
    mov     [r8], rax
    jmp     .done_patch

.abs32:
    add     rax, r10               ; symbol value + addend
    mov     [r8], eax
    jmp     .done_patch

.abs16:
    add     rax, r10               ; dw label (a boot sector's org)
    mov     [r8], ax
    jmp     .done_patch

.abs8:
    add     rax, r10
    mov     [r8], al
    jmp     .done_patch

.aarch64_jmp26:
    sub     rax, r9
    sar     rax, 2
    and     eax, 0x03FFFFFF
    mov     edx, [r8]
    and     edx, 0xFC000000
    or      edx, eax
    mov     [r8], edx
    jmp     .done_patch

.aarch64_adrp:
    add     rax, r10               ; S + A
    and     rax, -4096             ; Page(S + A)
    mov     rcx, r9
    and     rcx, -4096             ; Page(P)
    sub     rax, rcx               ; Page(S + A) - Page(P)
    sar     rax, 12                ; Delta in pages
    
    mov     edx, [r8]              ; original instruction
    and     edx, 0x9F00001F        ; clear imm bits
    
    mov     ecx, eax
    and     ecx, 0x03              ; immlo
    shl     ecx, 29
    or      edx, ecx
    
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 0x7FFFF           ; immhi
    shl     ecx, 5
    or      edx, ecx
    
    mov     [r8], edx
    jmp     .done_patch

.aarch64_lo12:
    add     rax, r10               ; S + A
    and     eax, 0xFFF             ; LO12
    shl     eax, 10
    mov     edx, [r8]
    and     edx, 0xFFC003FF        ; clear imm12 [21:10]
    or      edx, eax
    mov     [r8], edx
    jmp     .done_patch

.aarch64_ldst64:
    add     rax, r10
    and     eax, 0xFFF
    shr     eax, 3
    jmp     .aarch64_ldst_finish
.aarch64_ldst32:
    add     rax, r10
    and     eax, 0xFFF
    shr     eax, 2
    jmp     .aarch64_ldst_finish
.aarch64_ldst16:
    add     rax, r10
    and     eax, 0xFFF
    shr     eax, 1
    jmp     .aarch64_ldst_finish
.aarch64_ldst8:
    add     rax, r10
    and     eax, 0xFFF
.aarch64_ldst_finish:
    shl     eax, 10
    mov     edx, [r8]
    and     edx, 0xFFC003FF
    or      edx, eax
    mov     [r8], edx
    jmp     .done_patch

.riscv_hi20:
    add     rax, r10               ; S + A
    sub     rax, r9                ; S + A - P
    add     rax, 0x800             ; handle sign-extension of lo12
    shr     rax, 12                ; extract bits [31:12]
    and     eax, 0xFFFFF
    shl     eax, 12
    mov     edx, [r8]
    and     edx, 0x00000FFF        ; clear hi20
    or      edx, eax
    mov     [r8], edx
    jmp     .done_patch

.riscv_lo12_i:
    add     rax, r10
    sub     rax, r9
    and     eax, 0xFFF             ; [11:0]
    shl     eax, 20
    mov     edx, [r8]
    and     edx, 0x000FFFFF        ; clear imm[31:20]
    or      edx, eax
    mov     [r8], edx
    jmp     .done_patch

.riscv_lo12_s:
    add     rax, r10
    sub     rax, r9
    and     eax, 0xFFF
    
    mov     ecx, eax
    and     ecx, 0x1F              ; [4:0]
    shl     ecx, 7
    mov     edx, [r8]
    and     edx, 0xFFFFF07F        ; clear imm[4:0]
    or      edx, ecx
    
    mov     ecx, eax
    shr     ecx, 5
    and     ecx, 0x7F              ; [11:5]
    shl     ecx, 25
    and     edx, 0x01FFFFFF        ; clear imm[11:5]
    or      edx, ecx
    
    mov     [r8], edx
    jmp     .done_patch

.done_patch:
    xor     rax, rax
    pop     rbx
    epilogue

.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ============================================================================
; reloc_init
; ============================================================================
;
; reloc_init
; Allocates the relocation table inside the AsmCtx arena.
; Must be called once after arena_init and before any encoding begins.

; Input  : rdi = AsmCtx*
; Output : rax = EXIT_OK or EXIT_OOM
;
global reloc_init
reloc_init:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, [rbx + ASMCTX_arena]
    mov     rsi, RELOC_SIZE
    imul    rsi, MAX_RELOC
    call    arena_alloc
    check_err

    mov     [rbx + ASMCTX_relocs],   rdx
    mov     dword [rbx + ASMCTX_nrelocs], 0
    xor     rax, rax

.error:
    pop     rbx
    epilogue

[SECTION .bss]
global reloc_wrt
reloc_wrt:      resb 1              ; WRT_*: set by "wrt ..name", used once
