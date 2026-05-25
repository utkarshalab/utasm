;
; ============================================================================
; File        : src/linker/reloc.s
; Project     : utasm
; Description : Relocation engine for the utasm linker.
;                Records, resolves, and applies x86_64 relocations across
;                all output formats (ELF64 .o and flat binary).
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
%include "include/elf.s"

; --- External Symbols ---
extern  mem_zero
extern  symbol_find
extern  arena_alloc

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
    mov     [rdx + RELOC_offset], r12
    mov     [rdx + RELOC_sym],    r13
    mov     [rdx + RELOC_addend], r14
    mov     [rdx + RELOC_type],   r8d

    ; Increment count
    inc     dword [rbx + ASMCTX_nrelocs]

    xor     rax, rax
    jmp     .done

.oom:
    mov     rax, EXIT_OOM

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
    mov     r12, rsi               ; output buffer base
    mov     r13, rdx               ; base_addr (ORG / load VA)

    mov     r14, [rbx + ASMCTX_relocs]
    mov     r15d, [rbx + ASMCTX_nrelocs]
    xor     ecx, ecx               ; index

.loop:
    cmp     ecx, r15d
    jge     .done

    mov     r11, rcx
    imul    r11, RELOC_SIZE
    add     r11, r14                       ; r11 = RELOC*

    ; Resolve symbol
    mov     rdi, rbx
    mov     rdx, [r11 + RELOC_sym]         ; sym name ptr
    call    symbol_find
    test    rax, rax
    jnz     .check_undef
    mov     r10, rdx                       ; r10 = SYMBOL*
    
    ; Check if symbol is undefined
    movzx   eax, word [r10 + SYMBOL_section]
    IF ax, e, 0                            ; SHN_UNDEF
        ; Only error if we are in binary mode
        mov     rax, [rbx + ASMCTX_flags]
        test    rax, CTX_FLAG_FORMAT_BIN
        jnz     .undef
        jmp     .next                      ; Skip patching, keep for .rela
        ENDIF
    
    ; Check for special sections
    IF ax, e, 0xFFFF ; SHN_ABS
        mov     rax, [r10 + SYMBOL_value]
        jmp     .calc_patch_va
        ENDIF
    IF ax, ge, MAX_SECTIONS
        mov     rax, EXIT_INVALID_SECTION
        jmp     .ret
        ENDIF

    mov     rdi, [rbx + ASMCTX_sections]
    mov     r8, [rdi + rax * 8]              ; r8 = SECTION*
    test    r8, r8
    jz      .undef
    
    mov     r9, [r8 + SECTION_addr]          ; r9 = section VA
    mov     rax, [r10 + SYMBOL_value]
    add     rax, r9                          ; rax = sym_va

.calc_patch_va:
    push    rax                              ; Preserve sym_va

    ; patch_offset = reloc.offset
    mov     r8, [r11 + RELOC_offset]

    ; patch_ptr = output_buffer + patch_offset
    mov     r9, r12
    add     r9, r8                           ; r9 = patch_ptr

    ; patch_va = reloc.section.addr + patch_offset
    mov     rax, [r11 + RELOC_section]       ; rax = SECTION*
    mov     r10, [rax + SECTION_addr]
    add     r10, r8                          ; r10 = patch_va

    ; Apply the relocation via unified helper
    mov     rdi, r11                       ; RELOC*
    pop     rsi                            ; rsi = sym_va (restored)
    mov     rdx, r9                        ; rdx = patch_ptr
    mov     rcx, r10                       ; rcx = patch_va
    call    reloc_apply_one
    check_err

.next:
    inc     ecx
    jmp     .loop

.done:
    xor     rax, rax
    jmp     .ret

.check_undef:
    mov     rax, [rbx + ASMCTX_flags]
    test    rax, CTX_FLAG_FORMAT_BIN
    jnz     .undef
    jmp     .next

.undef:
    ; Report undefined symbol
    mov     rdi, rbx               ; AsmCtx
    xor     rsi, rsi               ; no filename
    xor     rdx, rdx               ; no line
    xor     rcx, rcx               ; no col
    mov     r8, [r11 + RELOC_sym]  ; symbol name
    extern  error_emit
    call    error_emit
    
    mov     rax, EXIT_UNDEF_REF
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

    ; Default: PC-relative (x86_64 PC32, etc)
    sub     rax, r9                ; Target - Patch_VA
    movsx   r10, dword [rbx + RELOC_pc_adjust]
    sub     rax, r10               ; Adjust for PC (e.g. 4 for x86_64)
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

.abs64:
    add     rax, r10
    mov     [r8], rax
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
