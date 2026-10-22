; ============================================================================
; File        : src/encode/x86/encoder/emit.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : relocations, prefixes, ModRM / SIB, bytes and dwords; the SGX leaves
; ============================================================================

[SECTION .text]

global amd64_emit_reloc
amd64_emit_reloc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    movzx   r12d, al           ; r12 = type
    mov     r13, rsi           ; r13 = symbol
    mov     r14d, edx          ; r14 = pc_adjust

    ; Callers may hold either a SYMBOL* (symbol already defined) or the raw
    ; name string (forward reference); relocations record the name.
    test    r13, r13
    jz      .sym_normalized
    cmp     byte [r13], TAG_SYMBOL
    jne     .sym_normalized
    mov     r13, [r13 + SYMBOL_name]
.sym_normalized:
    ; utasm's "pie" warning, as for reloc_record
    test    r13, r13
    jz      .pie_checked
    mov     r8d, r12d
    extern  reloc_warn_pie
    call    reloc_warn_pie
.pie_checked:

    ; 1. Check capacity
    mov     eax, [rbx + ASMCTX_nrelocs]
    cmp     eax, MAX_RELOC
    jge     .error_capacity

    ; 2. Get slot pointer: relocs + nrelocs * RELOC_SIZE
    mov     rcx, rax
    imul    rcx, RELOC_SIZE
    mov     rdx, [rbx + ASMCTX_relocs]
    test    rdx, rdx
    jz      .error_no_reloc_table
    add     rdx, rcx           ; rdx = RELOC*

    ; 3. Get current active section
    mov     r15, [rbx + ASMCTX_curr_sec]
    test    r15, r15
    jnz     .have_sec
    mov     r15, [rbx + ASMCTX_sections]
    test    r15, r15
    jz      .error_no_sections_ptr
    mov     r15, [r15]
    test    r15, r15
    jz      .error_no_first_section
.have_sec:

    ; 4. Populate slot fields
    mov     qword [rdx], 0     ; zero tag/type/pad0 first
    mov     byte [rdx + RELOC_tag], TAG_RELOC
    mov     [rdx + RELOC_type], r12d
    
    mov     rax, [r15 + SECTION_size]
    mov     [rdx + RELOC_offset], rax

    ; PC-relative relocations carry the site->end-of-instruction distance in
    ; the addend, so a RELA consumer computes S + A - P correctly.
    mov     qword [rdx + RELOC_addend], 0
    IF r12d, e, R_X86_64_PC32
        movsxd  rax, r14d
        neg     rax
        mov     [rdx + RELOC_addend], rax
        ENDIF
    IF r12d, e, R_X86_64_PC8               ; jmp/jcc short to a forward label
        movsxd  rax, r14d
        neg     rax
        mov     [rdx + RELOC_addend], rax
        ENDIF
    IF r12d, e, 13                         ; R_X86_64_PC16: bits 16 near branch
        movsxd  rax, r14d
        neg     rax
        mov     [rdx + RELOC_addend], rax
        ENDIF
    mov     [rdx + RELOC_sym], r13
    mov     [rdx + RELOC_section], r15
    mov     [rdx + RELOC_pc_adjust], r14d
    extern  error_loc_file, error_loc_line
    mov     eax, [rel error_loc_line]      ; where it came from, for errors
    mov     [rdx + RELOC_line], eax
    mov     rax, [rel error_loc_file]
    mov     [rdx + RELOC_file], rax

    ; "sym wrt ..plt" and friends (reloc_wrt): the type the statement asked
    ; for; the PC-relative addend above stays the same
    extern  reloc_wrt
    movzx   eax, byte [rel reloc_wrt]
    test    eax, eax
    jz      .wrt_done
    mov     byte [rel reloc_wrt], 0
    cmp     eax, WRT_SYM
    jne     .wrt_type
    mov     byte [rdx + RELOC_flags], RELOC_FLAG_SYM
    jmp     .wrt_done
.wrt_type:
    ; "wrt ..imagebase" (-f win64): the COFF converter's type
    cmp     eax, WRT_IMAGEBASE
    jne     .wrt_not_imagebase
    mov     ecx, R_UTASM_IMAGEBASE
    cmp     dword [rdx + RELOC_type], R_X86_64_64
    jne     .wrt_set
    mov     ecx, R_UTASM_IMAGEBASE64
    jmp     .wrt_set
.wrt_not_imagebase:
    mov     ecx, R_X86_64_PLT32
    cmp     eax, WRT_PLT
    je      .wrt_set
    mov     ecx, R_X86_64_GOTPCREL
    cmp     eax, WRT_GOTPCREL
    je      .wrt_set
    cmp     eax, WRT_TLSIE
    jb      .wrt_not_tls
    cmp     eax, WRT_TPOFF
    ja      .wrt_not_tls
    cmp     eax, WRT_TLSIE
    je      .wrt_tls
    cmp     eax, WRT_TLSGD
    jae     .wrt_tls
.wrt_not_tls:
    cmp     eax, WRT_GOTOFF
    jne     .wrt_not_gotoff
    ; R_X86_64_GOTOFF64 writes 8 bytes: only a qword field takes it (ELF32:
    ; R_386_GOTOFF, 32-bit); else NASM's error - it was written over the
    ; next 4 bytes
    mov     ecx, R_X86_64_GOTOFF64
    cmp     dword [rdx + RELOC_type], R_X86_64_64
    je      .wrt_set
    extern  elf32_enabled
    cmp     byte [rel elf32_enabled], 0
    jne     .wrt_set
    mov     dword [rel amd64_reloc_err], EXIT_GOTOFF_QWORD
    cmp     dword [rdx + RELOC_type], R_X86_64_PC32
    jne     .wrt_set
    mov     dword [rel amd64_reloc_err], EXIT_GOTOFF_QWORD_ABS   ; (RIP-relative)
    jmp     .wrt_set
.wrt_not_gotoff:
    cmp     eax, WRT_GOTPC
    jne     .wrt_got
    ; "_GLOBAL_OFFSET_TABLE_ wrt ..gotpc": the GOT's distance from the
    ; section's start, as NASM gives it - the field's offset in the addend;
    ; RIP-relative ("[rel _GLOBAL_OFFSET_TABLE_ wrt ..gotpc]") the GOT's
    ; address, as GNU as (NASM makes it GOTPCREL: a GOT slot's)
    mov     ecx, 26                        ; R_X86_64_GOTPC32
    cmp     dword [rdx + RELOC_type], R_X86_64_PC32
    je      .wrt_set
    mov     rax, [rdx + RELOC_offset]
    add     [rdx + RELOC_addend], rax
    jmp     .wrt_set
.wrt_tls:
    ; thread-local storage, against the symbol itself (GNU as: a local one
    ; too, not its section). ..tlsie / ..tlsgd / ..tlsld are PC-relative in
    ; ELF64 ("[rel x wrt ..tlsgd]"), absolute in ELF32 (elf32.s maps them)
    or      byte [rdx + RELOC_flags], RELOC_FLAG_SYM
    mov     ecx, R_X86_64_GOTTPOFF
    cmp     eax, WRT_TLSIE
    je      .tls_pc
    mov     ecx, 19                        ; R_X86_64_TLSGD
    cmp     eax, WRT_TLSGD
    je      .tls_pc
    mov     ecx, 20                        ; R_X86_64_TLSLD
    cmp     eax, WRT_TLSLD
    je      .tls_pc
    ; ..dtpoff / ..tpoff: the offset, 32-bit or a qword
    cmp     eax, WRT_DTPOFF
    jne     .tls_tpoff
    mov     ecx, 21                        ; R_X86_64_DTPOFF32
    cmp     dword [rdx + RELOC_type], R_X86_64_64
    jne     .wrt_set
    mov     ecx, 17                        ; R_X86_64_DTPOFF64
    jmp     .wrt_set
.tls_tpoff:
    mov     ecx, 23                        ; R_X86_64_TPOFF32
    cmp     dword [rdx + RELOC_type], R_X86_64_64
    jne     .wrt_set
    mov     ecx, 18                        ; R_X86_64_TPOFF64
    jmp     .wrt_set
.tls_pc:
    cmp     byte [rel elf32_enabled], 0
    jne     .wrt_set
    cmp     dword [rdx + RELOC_type], R_X86_64_PC32
    je      .wrt_set
    ; GOTTPOFF / TLSGD / TLSLD over an absolute field: no such thing in
    ; ELF64 (NASM's error) - it was taken as PC-relative there
    mov     dword [rel amd64_reloc_err], EXIT_WRT_UNSUPPORTED
    jmp     .wrt_set
.wrt_got:
    ; the GOT entry: RIP-relative ("[rel x wrt ..got]") its address
    ; (GOTPCREL, as NASM) - GOT32 there was the entry's offset taken as a
    ; displacement; a qword field GOT64; else GOT32
    mov     ecx, R_X86_64_GOTPCREL
    cmp     dword [rdx + RELOC_type], R_X86_64_PC32
    je      .wrt_set
    mov     ecx, 27                        ; R_X86_64_GOT64
    cmp     dword [rdx + RELOC_type], R_X86_64_64
    je      .wrt_set
    mov     ecx, R_X86_64_GOT32
.wrt_set:
    mov     [rdx + RELOC_type], ecx
.wrt_done:

    ; 5. Increment relocation count
    inc     dword [rbx + ASMCTX_nrelocs]
    xor     rax, rax
    jmp     .done

.error_capacity:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_cap_err]
    extern  print_str
    call    print_str
    pop     rax
    jmp     .error

.error_no_reloc_table:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_table_err]
    call    print_str
    pop     rax
    jmp     .error

.error_no_sections_ptr:
.error_no_first_section:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_sec_err]
    call    print_str
    pop     rax
    jmp     .error

.error:
    mov     rax, EXIT_RELOC_ERROR
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [amd64_emit_prefixes]
; * Input:
; *   AL: Operation Size (8, 16, 32, 64)
; *   RSI: Pointer to Op0 (Dest)
; *   RDX: Pointer to Op1 (Src/Index)
; ;
amd64_emit_prefixes:
    prologue
    push    rax
    push    rsi
    push    rdx
    
    ; 1. Operand-size override: a 16-bit operation (32-bit in bits 16)
    extern  amd64_osz66
    push    rax
    call    amd64_osz66
    test    eax, eax
    pop     rax
    jz      .no_osz
    extern  amd64_emit_osz_prefix
    call    amd64_emit_osz_prefix          ; (before a 67, as NASM orders them)
.no_osz:
    
    ; 2. Address-Size Override (0x67)
    ;    Not emitted from OPERAND_size: for a memory operand that is the
    ;    access width, not the width of the address registers.

    ; 3. REX Calculation
    xor     r11, r11
    pop     rdx
    pop     rsi
    pop     rax
    
    IF al, e, 64
        or  r11, 0x48           ; REX.W
        ELSE
        ; Even for non-64-bit, we need REX if using R8-R15
        ; or if using SIL/DIL/BPL/SPL in 8-bit mode
        xor r10, r10

        ; SPL/BPL/SIL/DIL only exist with a REX prefix present; the same
        ; encodings without one name AH/CH/DH/BH instead. This turns on the
        ; operand's own width, not the operation width: "movzx eax, dil" is a
        ; 32-bit operation whose source register still needs REX.
        IF rsi, ne, 0
        IF byte [rsi + OPERAND_kind], e, OP_REG
        IF byte [rsi + OPERAND_size], e, 8
        IF byte [rsi + OPERAND_is_high], e, 0
        IF byte [rsi + OPERAND_reg], ge, 4
        IF byte [rsi + OPERAND_reg], le, 7
            or r10, 1
            ENDIF
            ENDIF
            ENDIF
            ENDIF
            ENDIF
            ENDIF
        IF rdx, ne, 0
        IF byte [rdx + OPERAND_kind], e, OP_REG
        IF byte [rdx + OPERAND_size], e, 8
        IF byte [rdx + OPERAND_is_high], e, 0
        IF byte [rdx + OPERAND_reg], ge, 4
        IF byte [rdx + OPERAND_reg], le, 7
            or r10, 1
            ENDIF
            ENDIF
            ENDIF
            ENDIF
            ENDIF
            ENDIF

        IF rsi, ne, 0
            IF byte [rsi + OPERAND_kind], e, OP_REG
            IF byte [rsi + OPERAND_reg], ge, 8
                or r10, 1
            ENDIF
            ENDIF
            IF byte [rsi + OPERAND_kind], e, OP_MEM
            IF byte [rsi + OPERAND_base], ge, 8
                or r10, 1
            ENDIF
            IF byte [rsi + OPERAND_index], ge, 8
                or r10, 1
            ENDIF
            ENDIF
            ENDIF
        IF rdx, ne, 0
            IF byte [rdx + OPERAND_kind], e, OP_REG
            IF byte [rdx + OPERAND_reg], ge, 8
                or r10, 1
            ENDIF
            ENDIF
            IF byte [rdx + OPERAND_kind], e, OP_MEM
            IF byte [rdx + OPERAND_base], ge, 8
                or r10, 1
            ENDIF
            IF byte [rdx + OPERAND_index], ge, 8
                or r10, 1
            ENDIF
            ENDIF
            ENDIF
        IF r10, ne, 0
            mov r11, 0x40
            ENDIF
            ENDIF
    
    test    r11, r11
    jz      .done
    
    ; REX.R (from op0/src reg). OPERAND_reg only means anything for a register
    ; operand; on a memory operand it holds parser leftovers.
    IF rsi, ne, 0
        IF byte [rsi + OPERAND_kind], e, OP_REG
            mov cl, [rsi + OPERAND_reg]
            IF cl, ge, 8
                or r11, 0x04
            ENDIF
            ENDIF
        ENDIF

    ; REX.B (dest register or memory base) and REX.X (memory index)
    IF rdx, ne, 0
        IF byte [rdx + OPERAND_kind], e, OP_REG
            mov cl, [rdx + OPERAND_reg]
            IF cl, ge, 8
                or r11, 0x01
            ENDIF
            ENDIF
        IF byte [rdx + OPERAND_kind], e, OP_MEM
            mov cl, [rdx + OPERAND_base]
            IF cl, ge, 8
                or r11, 0x01
            ENDIF
            mov cl, [rdx + OPERAND_index]
            IF cl, ge, 8
                or r11, 0x02
            ENDIF
            ENDIF
        ENDIF

    IF r11, ne, 0
        ; VALIDATION: REX vs High-Byte (AH/CH/DH/BH)
        ; Architectural constraint: Cannot use REX with legacy 8-bit high regs.
        IF rsi, ne, 0
            IF byte [rsi + OPERAND_is_high], e, 1
                jmp .error
            ENDIF
            ENDIF
        IF rdx, ne, 0
            IF byte [rdx + OPERAND_is_high], e, 1
                jmp .error
            ENDIF
            ENDIF

        ; REX, or APX's REX2 for r16-r31 (mode.s amd64_rex_out)
        mov     rax, r11
        extern  amd64_rex_out
        call    amd64_rex_out
        test    eax, eax
        jnz     .error
        ENDIF

.done:
    epilogue

.error:
    mov     rax, EXIT_ENCODE_FAIL
    epilogue

;*
; * [amd64_emit_modrm_sib]
; * Emits ModR/M, SIB, and Displacement.
; * Input:
; *   AL  = Reg field value (3 bits)
; *   RDI = Pointer to memory OPERAND
; ;
global amd64_emit_modrm_sib
amd64_emit_modrm_sib:
    push    rbx
    push    rcx
    push    rdx
    push    r13
    push    r14
    
    mov     r13, rdi            ; Operand
    movzx   r14, al             ; Reg field
    and     r14b, 0x07          ; low 3 bits only; REX.R carries bit 3

    ; 0. A register operand is encoded directly as mod=11
    IF byte [r13 + OPERAND_kind], e, OP_REG
        mov     al, 0xC0
        mov     cl, r14b
        shl     cl, 3
        or      al, cl
        mov     cl, [r13 + OPERAND_reg]
        and     cl, 0x07
        or      al, cl
        call    amd64_emit_byte
        jmp     .done_sib
        ENDIF

    ; 0.5 16-bit addressing: [bx+si], [bp+di+4], [si], [bx], [1234h]
    test    byte [r13 + OPERAND_flags], OP_FLAG_ADDR16
    jnz     .addr16

    ; 1. Check for RIP-Relative addressing
    mov     r8b, [r13 + OPERAND_base]
    IF r8b, e, REG_RIP
        ; Mod=00, R/M=101
        shl     r14b, 3
        mov     al, r14b
        or      al, 0x05
        call    amd64_emit_byte
        
        ; Emit Relocation for Symbol.
        ; OPERAND_sym holds a SYMBOL* once the symbol is defined, or the raw
        ; name string for a forward reference; emit_reloc wants the name.
        mov     rsi, [r13 + OPERAND_sym]
        IF rsi, e, 0
            ; No symbol: emit the displacement as-is
            mov     rdi, [r13 + OPERAND_imm]
            call    amd64_emit_dword
            jmp     .done_sib
            ENDIF
        IF byte [rsi], e, TAG_SYMBOL
            mov     rsi, [rsi + SYMBOL_name]
            ENDIF
        mov     edx, 4                 ; provisional: corrected at the end
        mov     al, RELOC_REL32
        call    amd64_emit_reloc
        ; Remember this relocation. Its addend must be -(distance from the
        ; displacement to the end of the instruction), which is 4 only when
        ; no immediate follows (cmp byte [rel x], 5 needs -5). That is only
        ; known once the whole instruction is out: amd64_fix_rip_addend.
        IF rax, e, 0
            mov     eax, [rbx + ASMCTX_nrelocs]      ; = index + 1
            mov     [rel amd64_rip_pending], eax
            ; The written offset (the +8 in [rel x + 8]). The parser adds
            ; the whole expression into OPERAND_imm, which for an already
            ; defined label includes the label's own value; the relocation
            ; supplies that, so take it back out.
            mov     rax, [r13 + OPERAND_imm]
            mov     rcx, [r13 + OPERAND_sym]
            IF byte [rcx], e, TAG_SYMBOL
                sub     rax, [rcx + SYMBOL_value]
                ENDIF
            mov     [rel amd64_rip_disp], rax
            ; (rax is the result: an offset of 40 read as EXIT_ENCODE_FAIL
            ; made "[rel x + 40]" no form of any instruction)
            xor     eax, eax
            ENDIF

        ; Emit 4-byte zero placeholder
        xor     rdi, rdi
        call    amd64_emit_dword
        jmp     .done_sib
        ENDIF
    
    mov     cl, [r13 + OPERAND_index]
    IF cl, e, 4
        ; rsp as an index: the instruction fails (amd64_reloc_err), this
        ; returns as any call does - the jump to the driver's .error from
        ; here skipped every pop between, and the driver's caller got
        ; rbx / r12-r15 back wrong
        mov     dword [rel amd64_reloc_err], EXIT_ENCODE_FAIL
        jmp     .done_sib
        ENDIF

    ; 1.5 No base and no index: absolute [disp32]
    ;     ModRM mod=00 rm=100, SIB index=100 (none) base=101 (disp32 follows)
    cmp     r8b, 0xFF
    jne     .have_base
    cmp     cl, 0xFF
    jne     .no_base_index

    ; outside 64-bit mode mod=00 rm=101 is the absolute address itself
    ; (there is no RIP-relative form to keep it apart from): disp32 in
    ; bits 32, disp16 (rm=110) in bits 16
    extern  asm_bits
    cmp     byte [rel asm_bits], 64
    jne     .abs_legacy

    ; "add eax, [qword 0x10]", "mov cl, [byte 0x12345678]": an absolute
    ; ModRM address is 32 bits (only mov's A0-A3 take 64), NASM's warning
    movzx   eax, byte [r13 + OPERAND_dispsize]
    test    eax, eax
    jz      .abs_disp_ok
    cmp     eax, 32
    je      .abs_disp_ok
    extern  reloc_quiet
    cmp     byte [rel reloc_quiet], 0
    jne     .abs_disp_ok
    mov     edi, WC_EA_DISPSIZE
    lea     rsi, [rel s_ea_dispsize]
    call    amd64_warn_class
.abs_disp_ok:

    mov     al, r14b
    shl     al, 3
    or      al, 4
    call    amd64_emit_byte
    mov     al, 0x25
    call    amd64_emit_byte

    call    .reloc_name
    test    rsi, rsi
    jz      .abs_no_sym
    xor     edx, edx               ; absolute: no PC adjustment
    ; a 32-bit address (a32: 67) is zero-extended, a 64-bit one's disp32
    ; sign-extended
    mov     al, R_X86_64_32S
    cmp     byte [r12 + INST_asize], 32
    jne     .abs_sym_reloc
    mov     al, R_X86_64_32
.abs_sym_reloc:
    cmp     byte [r13 + OPERAND_pcrel], 0
    je      .abs_sym_type
    mov     al, R_X86_64_PC32              ; "[rod1 - $$]": PC-relative
.abs_sym_type:
    call    amd64_emit_reloc
    call    .disp_addend           ; [label + 4]: the 4
    ; meant RIP-relative (default rel, rel) and kept for later: worked out,
    ; a self-relative value is NASM's error (src/link/reloc/reloc.s)
    cmp     byte [r13 + OPERAND_relnum], 0
    je      .abs_kept
    mov     edx, [rbx + ASMCTX_nrelocs]
    test    edx, edx
    jz      .abs_kept
    dec     edx
    imul    rdx, rdx, RELOC_SIZE
    add     rdx, [rbx + ASMCTX_relocs]
    or      byte [rdx + RELOC_flags], RELOC_FLAG_NORIP
.abs_kept:
    xor     rdi, rdi
    call    amd64_emit_dword
    jmp     .done_sib

.abs_no_sym:
    ; an absolute address that is no sign-extended disp32 ("[0x80000000]"
    ; in 64-bit code): cut, with NASM 3's "dword displacement exceeds
    ; bounds"
    mov     rdi, [r13 + OPERAND_imm]
    movsxd  rcx, edi                       ; (rcx: saved on entry; rax is
    cmp     rcx, rdi                       ;  the status the caller reads)
    je      .abs_put
    cmp     byte [rel reloc_quiet], 0
    jne     .abs_put
    push    rax
    push    rdi
    mov     edi, WC_NUMBER_OVERFLOW
    lea     rsi, [rel s_disp_bounds]
    call    amd64_warn_class
    pop     rdi
    pop     rax
.abs_put:
    call    amd64_emit_dword
    jmp     .done_sib

.abs_legacy:
    mov     al, r14b
    shl     al, 3
    mov     r9d, 5                         ; bits 32: rm=101, disp32
    test    byte [r13 + OPERAND_flags], OP_FLAG_ADDR32
    jnz     .abs_rm                        ; [dword x] in bits 16
    cmp     byte [rel asm_bits], 16
    jne     .abs_rm
    mov     r9d, 6                         ; bits 16: rm=110, disp16
.abs_rm:
    or      al, r9b
    push    r9
    call    amd64_emit_byte
    pop     r9
    mov     ecx, 4
    cmp     r9d, 6
    jne     .abs_disp
    mov     ecx, 2
.abs_disp:
    jmp     .disp_n                        ; ecx = width

; ---- 16-bit addressing ----
.addr16:
    movzx   eax, byte [r13 + OPERAND_base]
    movzx   edx, byte [r13 + OPERAND_index]
    cmp     edx, 0xFF
    je      .a16_one
    cmp     eax, 0xFF
    je      .a16_index_only
    cmp     byte [r13 + OPERAND_scale], 1
    ja      .a16_bad
    ; two registers, either order: bx or bp, and si or di
    cmp     eax, 6
    jb      .a16_pair
    xchg    eax, edx
.a16_pair:
    xor     r9d, r9d
    cmp     eax, 3                         ; bx
    je      .a16_second
    mov     r9d, 2
    cmp     eax, 5                         ; bp
    jne     .a16_bad
.a16_second:
    cmp     edx, 6                         ; si
    je      .a16_rm
    inc     r9d
    cmp     edx, 7                         ; di
    jne     .a16_bad
    jmp     .a16_rm
.a16_index_only:
    cmp     byte [r13 + OPERAND_scale], 1
    ja      .a16_bad
    mov     eax, edx
.a16_one:
    cmp     eax, 0xFF
    je      .a16_direct                    ; no register: [word 0x10]
    mov     r9d, 4
    cmp     eax, 6                         ; si
    je      .a16_rm
    mov     r9d, 5
    cmp     eax, 7                         ; di
    je      .a16_rm
    mov     r9d, 6
    cmp     eax, 5                         ; bp
    je      .a16_rm
    mov     r9d, 7
    cmp     eax, 3                         ; bx
    jne     .a16_bad
.a16_rm:
    ; mod: a label takes a disp16; else none (but [bp] needs a disp8 0),
    ; a disp8 or a disp16
    call    .reloc_name
    mov     edx, 2
    test    rsi, rsi
    jnz     .a16_modrm
    cmp     byte [r13 + OPERAND_dispsize], 16
    je      .a16_modrm                     ; [word bx+4]: a disp16
    mov     rax, [r13 + OPERAND_imm]
    ; 16 bits, sign-extended: "[di + 0xffff]" is [di - 1] (a disp8)
    movsx   rax, ax
    mov     [r13 + OPERAND_imm], rax
    cmp     byte [r13 + OPERAND_dispsize], 8
    je      .a16_disp_size                 ; [byte bx+4]: a disp8 if it fits
    xor     edx, edx
    test    rax, rax
    jnz     .a16_disp_size
    cmp     r9d, 6
    jne     .a16_modrm
.a16_disp_size:
    ; EVEX: a disp8 counts in units of N (compressed displacement), as in
    ; 32/64-bit addressing: a multiple of N only, else a disp16 - "[bp-2]"
    ; was disp8 FE, read as bp - 2*N
    mov     [rel amd64_disp_emit], rax     ; the disp8 written
    mov     rcx, rax
    movzx   r9d, r9b                       ; (the r/m, kept)
    push    r9
    movzx   r9d, byte [rel amd64_disp8n]
    cmp     r9d, 1
    jbe     .a16_disp8
    push    rax
    cqo
    idiv    r9
    mov     rcx, rax
    pop     rax
    mov     [rel amd64_disp_emit], rcx
    test    rdx, rdx
    jnz     .a16_disp16
.a16_disp8:
    mov     edx, 1
    movsx   r9, cl
    cmp     r9, rcx
    je      .a16_disp_picked
    ; [byte bx + 0x1ff]: the byte written, cut, with NASM's "byte
    ; displacement exceeds bounds" (it became a disp16), as 32/64-bit's
    cmp     byte [r13 + OPERAND_dispsize], 8
    jne     .a16_disp16
    cmp     byte [rel reloc_quiet], 0
    jne     .a16_disp_picked
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r10
    push    r11
    lea     rsi, [rel s_disp8_bounds]
    extern  warn_number
    call    warn_number
    pop     r11
    pop     r10
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    jmp     .a16_disp_picked
.a16_disp16:
    mov     edx, 2
.a16_disp_picked:
    pop     r9
.a16_modrm:
    mov     eax, edx
    shl     eax, 6
    mov     cl, r14b
    shl     cl, 3
    or      al, cl
    or      al, r9b
    push    rdx
    call    amd64_emit_byte
    pop     rdx
    test    edx, edx
    jz      .done_sib
    mov     ecx, 1
    cmp     edx, 1
    je      .disp_n
    mov     ecx, 2
    jmp     .disp_n
.a16_bad:
    ; no 16-bit form ("[r ax]" in bits 64: utasm crashed): failed, returning
    mov     dword [rel amd64_reloc_err], EXIT_ENCODE_FAIL
    jmp     .done_sib
.a16_direct:
    ; [disp16]: mod 00, r/m 110 ("a16 add eax, [0x10]" in 32-bit code)
    mov     cl, r14b
    shl     cl, 3
    mov     al, cl
    or      al, 6
    call    amd64_emit_byte
    mov     ecx, 2
    jmp     .disp_n

; .disp_n: the displacement, ecx bytes (1, 2 or 4): a label's is relocated
; (its offset in the addend), a number's written as is
.disp_n:
    push    rcx
    call    .reloc_name
    pop     rcx
    test    rsi, rsi
    jz      .disp_n_plain
    cmp     ecx, 1
    je      .disp_n_plain                  ; never: a label takes 16/32 bits
    push    rcx
    xor     edx, edx
    mov     al, R_X86_64_32
    cmp     ecx, 2
    jne     .disp_n_rel
    mov     al, 12                         ; R_X86_64_16
.disp_n_rel:
    call    amd64_emit_reloc
    pop     rcx
    ; the addend: the offset written after the label
    mov     edx, [rbx + ASMCTX_nrelocs]
    dec     edx
    imul    rdx, rdx, RELOC_SIZE
    add     rdx, [rbx + ASMCTX_relocs]
    mov     rax, [r13 + OPERAND_imm]
    mov     rsi, [r13 + OPERAND_sym]
    cmp     byte [rsi], TAG_SYMBOL
    jne     .disp_n_addend
    sub     rax, [rsi + SYMBOL_value]
.disp_n_addend:
    mov     [rdx + RELOC_addend], rax
    xor     edi, edi
    jmp     .disp_n_out
.disp_n_plain:
    mov     rdi, [r13 + OPERAND_imm]
.disp_n_out:
    cmp     ecx, 1
    je      .disp_n_byte
    cmp     ecx, 2
    je      .disp_n_word
    call    amd64_emit_dword
    jmp     .done_sib
.disp_n_word:
    call    amd64_emit_word
    jmp     .done_sib
.disp_n_byte:
    mov     rax, [rel amd64_disp_emit]     ; (16-bit addressing: scaled for EVEX)
    call    amd64_emit_byte
    jmp     .done_sib

    ; 1.6 Index but no base: ModRM mod=00 rm=100, SIB base=101, then disp32
.no_base_index:
    mov     r8b, 5              ; SIB base=101 means "no base register"
    xor     rdx, rdx            ; Mod 00
    jmp     .emit_start

.have_base:
    xor     rdx, rdx            ; Mod field

    ; A relocatable symbol in the displacement always needs a full disp32
    call    .reloc_name
    test    rsi, rsi
    jz      .plain_disp
    mov     dl, 2
    jmp     .emit_start

.plain_disp:
    mov     rdi, [r13 + OPERAND_imm] ; Displacement
    ; the displacement is 32 bits, sign-extended: "[eax + 0xffffffff]" is
    ; [eax - 1] (the address wraps), a disp8 - as NASM; one with more
    ; than 32 bits loses them, silently as NASM 3 (2.16 warned)
    movsxd  rax, edi
    cmp     rax, rdi
    je      .disp_canon
    mov     rdi, rax
    mov     [r13 + OPERAND_imm], rdi
.disp_canon:
    mov     [rel amd64_disp_emit], rdi

    ; [dword ebx+4] / [byte ebx+4]: the size written
    cmp     byte [r13 + OPERAND_dispsize], 32
    je      .mod32
    cmp     byte [r13 + OPERAND_dispsize], 8
    je      .disp8_forced

    ; Determine Mod based on Displacement
    test    rdi, rdi
    jz      .mod00
    ; EVEX: a disp8 counts in units of N (compressed displacement), so it
    ; must be a multiple of N; otherwise the displacement takes 32 bits
    movzx   r9d, byte [rel amd64_disp8n]
    cmp     r9d, 1
    jbe     .disp8_check
    mov     rax, rdi
    cqo
    idiv    r9
    test    rdx, rdx
    jnz     .mod32
    mov     rdi, rax
    mov     [rel amd64_disp_emit], rax
.disp8_check:
    ; Check if fits in 8 bits
    cmp     rdi, -128
    jl      .mod32
    cmp     rdi, 127
    jg      .mod32
    mov     dl, 1               ; Mod 01 (8-bit disp)
    jmp     .emit_start
.mod32:
    mov     dl, 2               ; Mod 10 (32-bit disp)
    jmp     .emit_start
.disp8_forced:
    ; [byte rsp+0xFF]: the byte all the same, cut - NASM's "byte
    ; displacement exceeds bounds" for a value that is not a signed byte
    cmp     rdi, -128
    jl      .disp8_warn
    cmp     rdi, 127
    jle     .disp8_put
.disp8_warn:
    push    rax
    push    rcx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    extern  warn_number
    lea     rsi, [rel s_disp8_bounds]
    call    warn_number
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rax
.disp8_put:
    mov     dl, 1
    jmp     .emit_start
.mod00:
    xor     dl, dl              ; Mod 00 (no disp)
    ; Special case: if base is RBP/R13, we MUST use Mod 01 with disp 0
    mov     al, r8b
    and     al, 0x07
    cmp     al, 5
    jne     .emit_start
    mov     dl, 1
    
.emit_start:
    ; SIB Logic
    ; If index != 0xFF or base == 4 (RSP), use SIB
    cmp     cl, 0xFF
    jne     .use_sib
    mov     al, r8b
    and     al, 0x07
    cmp     al, 4               ; RSP/R12
    je      .use_sib
    cmp     byte [rel amd64_force_sib], 0
    jne     .use_sib            ; tileloadd, bndldx: always a SIB (dispatch.s)

    ; No SIB
    mov     al, dl              ; Mod
    shl     al, 6
    shl     r14b, 3             ; Reg
    or      al, r14b
    mov     cl, r8b              ; R/M (Base)
    and     cl, 0x07
    or      al, cl
    push    rdx                 ; emit_byte clobbers rdx; dl holds Mod
    call    amd64_emit_byte
    pop     rdx
    jmp     .disp
    
.use_sib:
    ; Emit ModRM with R/M = 100b (4)
    mov     al, dl
    shl     al, 6
    shl     r14b, 3
    or      al, r14b
    or      al, 4               ; R/M = 4 (SIB follows)
    push    rdx                 ; emit_byte clobbers rdx; dl holds Mod
    call    amd64_emit_byte
    pop     rdx
    
    ; Emit SIB
    ; Scale (2 bits)
    ; Index (3 bits)
    ; Base (3 bits)
    mov     al, [r13 + OPERAND_scale]
    ; Map scale 1,2,4,8 to 0,1,2,3
    xor     cl, cl
    cmp     al, 2
    je      .s1
    cmp     al, 4
    je      .s2
    cmp     al, 8
    je      .s3
    jmp     .s0
.s1: mov cl, 1
    jmp .s0
.s2: mov cl, 2
    jmp .s0
.s3: mov cl, 3
.s0:
    shl     cl, 6
    mov     al, [r13 + OPERAND_index]
    cmp     al, 0xFF
    jne     .idx_ok
    mov     al, 4               ; Index 4 with SIB = no index
.idx_ok:
    and     al, 0x07
    shl     al, 3
    or      cl, al
    mov     al, r8b              ; Base
    and     al, 0x07
    or      cl, al
    mov     al, cl
    push    rdx                 ; emit_byte clobbers rdx; dl holds Mod
    call    amd64_emit_byte
    pop     rdx

.disp:
    ; A relocatable displacement is a disp32 the linker fills in
    push    rdx
    call    .reloc_name
    pop     rdx
    test    rsi, rsi
    jz      .disp_plain
    xor     edx, edx               ; absolute: no PC adjustment
    mov     al, R_X86_64_32S
    cmp     byte [r13 + OPERAND_pcrel], 0
    je      .disp_type
    mov     al, R_X86_64_PC32              ; "[rdi + rod1 - $$]": PC-relative
.disp_type:
    call    amd64_emit_reloc
    call    .disp_addend           ; [rbx + label + 4]: the 4
    xor     rdi, rdi
    call    amd64_emit_dword
    jmp     .done_sib

.disp_plain:
    ; The no-base SIB form always carries a disp32
    IF byte [r13 + OPERAND_base], e, 0xFF
        mov     rdi, [r13 + OPERAND_imm]
        call    amd64_emit_dword
        jmp     .done_sib
        ENDIF

    ; Emit Displacement
    IF dl, e, 1
        mov     rax, [rel amd64_disp_emit]
        call    amd64_emit_byte
    ELSEIF dl, e, 2
        mov     rdi, [r13 + OPERAND_imm]
        call    amd64_emit_dword
        ENDIF
    jmp     .done_sib

;
; The relocation just emitted for the displacement: its addend is what
; was written after the label (OPERAND_imm holds the whole value, the
; label's own included once it is defined).
;
.disp_addend:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    mov     edx, [rbx + ASMCTX_nrelocs]
    dec     edx
    imul    rdx, rdx, RELOC_SIZE
    add     rdx, [rbx + ASMCTX_relocs]
    mov     rax, [r13 + OPERAND_imm]
    mov     rsi, [r13 + OPERAND_sym]
    cmp     byte [rsi], TAG_SYMBOL
    jne     .da_set
    sub     rax, [rsi + SYMBOL_value]
.da_set:
    ; PC-relative ("x - $$", x elsewhere): the field's place too
    cmp     byte [r13 + OPERAND_pcrel], 0
    je      .da_put
    add     rax, [rdx + RELOC_offset]
.da_put:
    mov     [rdx + RELOC_addend], rax
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

;
; Returns RSI = the symbol name to relocate against, or 0 when the
; displacement is a plain number. Constants and struct fields resolve to
; numbers, not addresses, so they must never produce a relocation.
;
.reloc_name:
    mov     rsi, [r13 + OPERAND_sym]
    test    rsi, rsi
    jz      .rn_none
    cmp     byte [rsi], TAG_SYMBOL
    jne     .rn_done               ; a raw name string: forward reference
    cmp     word [rsi + SYMBOL_section], SHN_ABS
    je      .rn_none               ; "x equ 56": a number
    movzx   eax, byte [rsi + SYMBOL_kind]
    cmp     al, SYM_CONSTANT
    je      .rn_none
    cmp     al, SYM_STRUCT_FIELD
    je      .rn_none
    cmp     al, SYM_STRUCT
    je      .rn_none
    mov     rsi, [rsi + SYMBOL_name]
.rn_done:
    ret
.rn_none:
    xor     rsi, rsi
    ret

.done_sib:
    pop     r14
    pop     r13
    pop     rdx
    pop     rcx
    pop     rbx
    ret

;*
; * [amd64_emit_byte]
; ;
amd64_emit_byte:
    extern asm_ctx_emit_byte
    push    rax
    
    ; Check architectural limit (15 bytes)
    mov     eax, [rbx + ASMCTX_inst_len]
    IF eax, ge, 15
        ; past 15 bytes: the instruction fails, the byte is not written
        pop rax
        mov     dword [rel amd64_reloc_err], EXIT_ENCODE_FAIL
        ret
        ENDIF
    inc     dword [rbx + ASMCTX_inst_len]
    
    pop     rax
    ; the section's buffer grows by system calls now and then, which
    ; clobber r10 / r11 (and rdx): the encoders keep operands there ("int
    ; 0x21" read its vector through r10 after the CD - a fault, once the
    ; buffer had just grown)
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    mov     rdi, rbx
    movzx   rsi, al
    call    asm_ctx_emit_byte
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    ret

;*
; * [amd64_emit_dword]
; * Input: RDI = 32-bit value
; ;
global amd64_emit_dword
amd64_emit_dword:
    push    rax
    push    rcx
    push    rdi                    ; amd64_emit_byte clobbers rdi/rcx
    mov     rcx, 4
.loop:
    mov     rdi, [rsp]
    mov     al, dil
    push    rcx
    call    amd64_emit_byte
    pop     rcx
    shr     qword [rsp], 8
    dec     rcx
    jnz     .loop
    pop     rdi
    pop     rcx
    pop     rax
    ret

; amd64_sgx_leaf: the SGX leaf mnemonics (r12 = INST, ids 5700 - 5706):
; B8 leaf (mov eax, leaf; 66 first in bits 16), then ENCLS or ENCLU.
; rax = OK, or EXIT_ENCODE_FAIL with operands
sgx_leaves:     db 1, 0xCF, 9, 0xCF, 0, 0xCF, 2, 0xCF, 2, 0xD7, 3, 0xD7, 1, 0xD7
amd64_sgx_leaf:
    cmp     byte [r12 + INST_nops], 0
    jne     .bad
    movzx   eax, word [r12 + INST_op_id]
    sub     eax, 5700
    lea     rcx, [rel sgx_leaves]
    push    r15
    lea     r15, [rcx + rax*2]
    cmp     byte [rel asm_bits], 16
    jne     .mov
    mov     al, 0x66
    call    amd64_emit_byte
.mov:
    mov     al, 0xB8
    call    amd64_emit_byte
    movzx   edi, byte [r15]
    call    amd64_emit_dword
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x01
    call    amd64_emit_byte
    mov     al, [r15 + 1]
    call    amd64_emit_byte
    pop     r15
    xor     eax, eax
    ret
.bad:
    mov     eax, EXIT_ENCODE_FAIL
    ret
