; ============================================================================
; File        : src/encode/x86/encoder/jmp_call.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : jmp, call, xbegin, far widths, push / pop forms, MPX, nop, words and qwords
; ============================================================================


;*
; * [amd64_encode_jmp]
; ;
amd64_encode_jmp:
    prologue
    lea     r10, [r12 + INST_op0]
    ; A register or memory operand is always the indirect form (FF /4),
    ; even when its displacement names a symbol: in `jmp [rbx + FIELD]`
    ; OPERAND_sym is FIELD, but it is not a jump target.
    cmp     byte [r10 + OPERAND_kind], OP_MEM
    je      .indirect
    cmp     byte [r10 + OPERAND_kind], OP_REG
    je      .indirect
    cmp     qword [r10 + OPERAND_sym], 0
    jne     .direct
    ; a number is an address to jump to (E9), not one to jump through
    cmp     byte [r10 + OPERAND_kind], OP_IMM
    jne     .indirect
    test    byte [r10 + OPERAND_flags], OP_FLAG_FAR
    jnz     .indirect
.direct:

    ; Pick the 2-byte form (EB rel8) or the 5-byte form (E9 rel32), with
    ; the same rules as amd64_encode_jcc: explicit short / near / strict
    ; win; otherwise rel8 when a backward local target is within reach.
    test    byte [r10 + OPERAND_flags], OP_FLAG_SHORT
    jnz     .short
    test    byte [r10 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .near
    ; "jmp word x" / "jmp near x": GNU's syntax keeps it near; NASM 3
    ; makes it short where it reaches, its 66 kept
    call    amd64_branch_size_first
    jnz     .near_emit
    ; "bnd jmp" (F2): near, kept so - a short jmp does not keep the
    ; bound registers (NASM shortens it and drops the bnd it was asked for)
    cmp     byte [r12 + INST_prefixes], 0xF2
    je      .near_emit
    cmp     byte [r12 + INST_prefixes + 1], 0xF2
    je      .near_emit
    cmp     byte [r12 + INST_prefixes + 2], 0xF2
    je      .near_emit
    cmp     byte [r12 + INST_prefixes + 3], 0xF2
    je      .near_emit
    mov     rsi, [r10 + OPERAND_sym]
    call    amd64_branch_fits_rel8
    test    eax, eax
    jz      .near
.short:
    call    amd64_branch_osize_once        ; (66 for "jmp word x" in bits 32)
    mov     byte [rel amd64_branch_width], 0   ; (rel8 all the same)
    mov     r13, 0xEB
    call    amd64_encode_branch_short
    jmp     .done

.near:
    ; A rel32 jmp to a label not yet defined may be shortened later by
    ; src/optimize/jump.s - unless the user wrote near/strict.
    test    byte [r10 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .near_emit
    mov     byte [rel amd64_relax_kind], RELAX_JMP
.near_emit:
    call    amd64_branch_osize_once        ; (66 for "jmp word x" in bits 32)
    mov     al, 0xE9                       ; jmp rel32 <label>
    call amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 4
    mov     al, RELOC_REL32
    call    amd64_emit_branch_disp
    jmp     .done

.indirect:
    ; FF /4 with ModRM for the register or memory operand. Encoded here
    ; directly: amd64_encode_unary ignores the opcode in r13 and always
    ; emits F7, which turned `jmp rax` into `mul rax`.
    ; Size 32 = no REX.W and no 0x66 (the operand is always 64-bit in long
    ; mode); REX.B/X are still added for r8-r15.
    mov     al, 32
    test    byte [r10 + OPERAND_flags], OP_FLAG_FAR
    jz      .far_width
    call    amd64_far_width
    jmp     .width_ok
.far_width:
    mov     ecx, 1                         ; jmp: a word takes its 66
    call    amd64_near_indirect_size
    test    eax, eax
    jnz     .bad_size
    mov     al, 32
.width_ok:
    lea     r10, [r12 + INST_op0]
    xor     rsi, rsi                       ; no ModRM.reg operand
    mov     rdx, r10                       ; ModRM.rm operand
    call    amd64_emit_prefixes
    mov     al, 0xFF
    call    amd64_emit_byte
    lea     rdi, [r12 + INST_op0]          ; the calls above clobber r10
    mov     al, 4
    test    byte [rdi + OPERAND_flags], OP_FLAG_FAR
    jz      .jmp_near
    mov     al, 5                          ; jmp far [m16:32]
.jmp_near:
    call    amd64_emit_modrm_sib
.done:
    epilogue
.bad_size:
    mov     rax, EXIT_ENCODE_FAIL
    epilogue

; amd64_near_indirect_size: in 64-bit code a near indirect jmp / call
; (FF /4, /2) is 64-bit: a word operand only for jmp (ecx = 1), with its
; 66 written here ("jmp ax" is 66 FF E0, as NASM's); a dword, or a word
; for call, no form (NASM's error) - they were jmp rax / call rax.
; Output: eax = 0 or EXIT_ENCODE_FAIL. Clobbers rax, rdx.
amd64_near_indirect_size:
    xor     eax, eax
    cmp     byte [rel asm_bits], 64
    jne     .nis_ret
    movzx   edx, byte [r12 + INST_op0 + OPERAND_size]
    test    edx, edx
    jz      .nis_ret
    cmp     edx, 64
    je      .nis_ret
    cmp     edx, 16
    jne     .nis_bad
    test    ecx, ecx
    jz      .nis_bad
    mov     al, 0x66
    call    amd64_emit_byte
    xor     eax, eax
.nis_ret:
    ret
.nis_bad:
    mov     eax, EXIT_ENCODE_FAIL
    ret

; amd64_warn_class: warning class edi with the text at rsi (the
; registers the encoder keeps are saved)
amd64_warn_class:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    rsi
    extern  warn_begin, warn_text, warn_end
    call    warn_begin
    pop     rsi
    call    warn_text
    call    warn_end
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; amd64_far_width: al = the width of "jmp / call far [m]" (r10): m16:64
; (REX.W) as NASM writes it, m16:32 for "far dword", m16:16 for "far word"
amd64_far_width:
    mov     al, [r10 + OPERAND_size]
    cmp     al, 16
    je      .ret
    cmp     al, 32
    je      .ret
    mov     al, 64
.ret:
    ret

;*
; * [amd64_encode_xbegin]
; * C7 F8 rel32 (rel16 in bits 16): the abort handler's address, a label or
; * a number ("xbegin $+6") as a near branch's
; ;
amd64_encode_xbegin:
    prologue
    lea     r10, [r12 + INST_op0]
    cmp     byte [r10 + OPERAND_kind], OP_SYMBOL
    je      .target
    cmp     byte [r10 + OPERAND_kind], OP_IMM
    jne     .bad
    test    byte [r10 + OPERAND_flags], OP_FLAG_FAR
    jnz     .bad
.target:
    call    amd64_branch_osize             ; (66 for "xbegin word x" in bits 32)
    mov     al, 0xC7
    call    amd64_emit_byte
    mov     al, 0xF8
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 4
    mov     al, RELOC_REL32
    call    amd64_emit_branch_disp         ; (its error, if any)
    epilogue
.bad:
    mov     rax, EXIT_INVALID_OPERAND
    epilogue

;*
; * [amd64_encode_call]
; ;
amd64_encode_call:
    prologue
    lea     r10, [r12 + INST_op0]
    ; A register or memory operand is always the indirect form (FF /2),
    ; even when its displacement names a symbol: in `call [rbx + FIELD]`
    ; OPERAND_sym is FIELD, but it is not a call target. Treating it as
    ; one emitted `call FIELD` - a direct call to a small constant.
    cmp     byte [r10 + OPERAND_kind], OP_MEM
    je      .indirect
    cmp     byte [r10 + OPERAND_kind], OP_REG
    je      .indirect
    cmp     qword [r10 + OPERAND_sym], 0
    jne     .direct
    ; a number is an address to call (E8), not one to call through
    cmp     byte [r10 + OPERAND_kind], OP_IMM
    jne     .indirect
    test    byte [r10 + OPERAND_flags], OP_FLAG_FAR
    jnz     .indirect
.direct:

    call    amd64_branch_osize             ; (66 for "call word x" in bits 32)
    mov     al, 0xE8                       ; call rel32 <label>
    call amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 4
    mov     al, RELOC_REL32
    call    amd64_emit_branch_disp
    jmp     .done

.indirect:
    ; FF /2 with ModRM for the register or memory operand. Encoded here
    ; directly: amd64_encode_unary ignores the opcode in r13 and always
    ; emits F7, which turned `call rax` into `not rax`.
    ; Size 32 = no REX.W and no 0x66 (the operand is always 64-bit in long
    ; mode); REX.B/X are still added for r8-r15.
    mov     al, 32
    test    byte [r10 + OPERAND_flags], OP_FLAG_FAR
    jz      .far_width
    call    amd64_far_width
    jmp     .width_ok
.far_width:
    xor     ecx, ecx                       ; call: no word form
    call    amd64_near_indirect_size
    test    eax, eax
    jnz     .bad_size
    mov     al, 32
.width_ok:
    lea     r10, [r12 + INST_op0]
    xor     rsi, rsi                       ; no ModRM.reg operand
    mov     rdx, r10                       ; ModRM.rm operand
    call    amd64_emit_prefixes
    mov     al, 0xFF
    call    amd64_emit_byte
    lea     rdi, [r12 + INST_op0]          ; the calls above clobber r10
    mov     al, 2
    test    byte [rdi + OPERAND_flags], OP_FLAG_FAR
    jz      .call_near
    mov     al, 3                          ; call far [m16:32]
.call_near:
    call    amd64_emit_modrm_sib
.done:
    epilogue
.bad_size:
    mov     rax, EXIT_ENCODE_FAIL
    epilogue

;*
; * [amd64_encode_jcc]
; ;

;*
; * [amd64_encode_ret]
; ;

;*
; * [amd64_encode_push_pop]
; * r13 = base opcode (0x50 for PUSH, 0x58 for POP)
; * r14 = extended opcode (0xFF /6 for PUSH, 0x8F /0 for POP)
; * r15 = reg field for ModRM
; ;
amd64_encode_push_pop:
    ; push of an immediate or a label: amd64_encode_push
    cmp     r13, 0x50
    jne     .reg_mem
    movzx   eax, byte [r12 + INST_op0 + OPERAND_kind]
    cmp     eax, OP_IMM
    je      amd64_encode_push
    cmp     eax, OP_SYMBOL
    je      amd64_encode_push
.reg_mem:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, [r10 + OPERAND_size]
        IF al, e, 16
            mov al, 0x66
            call amd64_emit_byte
            ENDIF
        ; REX.B for r8-r15, REX2 for r16-r31 (mode.s amd64_rex_out)
        lea     r10, [r12 + INST_op0]
        mov     al, [r10 + OPERAND_reg]
        IF al, ge, 8
            mov     al, 0x40
            xor     esi, esi
            mov     rdx, r10
            extern  amd64_rex_out
            call    amd64_rex_out
            test    eax, eax
            jnz     .pp_fail
            ENDIF
        ; The opcode is built last: amd64_emit_byte scratches RDX/R10, so it
        ; cannot be held across the prefix emission above.
        lea     r10, [r12 + INST_op0]
        mov     al, [r10 + OPERAND_reg]
        and     al, 7
        add     al, r13b
        call    amd64_emit_byte
        ELSE
        ; MEM
        mov     al, [r10 + OPERAND_size]
        IF al, e, 16
            mov al, 0x66
            call amd64_emit_byte
            ENDIF
        lea     r10, [r12 + INST_op0]
        mov     al, 0
        xor     rsi, rsi
        mov     rdx, r10           ; base/index supply REX.B and REX.X
        call    amd64_emit_prefixes
        mov     al, r14b
        call    amd64_emit_byte
        lea     r10, [r12 + INST_op0]  ; the calls above clobber r10
        mov     al, r15b
        mov     rdi, r10
        call    amd64_emit_modrm_sib
        ENDIF
    epilogue
.pp_fail:
    mov     rax, EXIT_ENCODE_FAIL
    epilogue

;*
; * [amd64_encode_shift]
; * r14 = extension (4 for SHL, 5 for SHR, 7 for SAR)
; ;

;*
; * [amd64_encode_imul]
; ;

;*
; * [amd64_encode_cmovcc]
; ;

;*
; * [amd64_encode_setcc]
; ;

;*
; * [amd64_encode_mpx]
; * Handles BNDMK, BNDCL, BNDCU, BNDCN, BNDMOV, BNDLDX, BNDSTX
; ;
amd64_encode_mpx:
    prologue
    mov     ax, [r12 + INST_op_id]
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    IF ax, e, 1047 ; BNDMK: F3 0F 1B /r
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1043 ; BNDCL: F3 0F 1A /r
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1045 ; BNDCU: F2 0F 1A /r
        mov     al, 0xF2
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1044 ; BNDCN: F2 0F 1B /r
        mov     al, 0xF2
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1048 ; BNDMOV
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        IF byte [r10 + OPERAND_kind], e, OP_MEM
            mov al, 0x1B
            call amd64_emit_byte
            mov al, [r11 + OPERAND_reg]
            mov rdi, r10
            call amd64_emit_modrm_sib
            ELSE
            mov al, 0x1A
            call amd64_emit_byte
            mov al, [r10 + OPERAND_reg]
            mov rdi, r11
            call amd64_emit_modrm_sib
            ENDIF
    ELSEIF ax, e, 1046 ; BNDLDX: 0F 1A /r
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1049 ; BNDSTX: 0F 1B /r
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r11 + OPERAND_reg]
        mov rdi, r10
        call amd64_emit_modrm_sib
        ENDIF
    epilogue

;*
; * [amd64_emit_nop]
; * Purpose: Emits an optimal NOP sequence of length RAX.
; * Maximum supported in one call: 9 bytes.
; ;
amd64_emit_nop:
    prologue
    IF rax, e, 1
        mov al, 0x90
        call amd64_emit_byte
    ELSEIF rax, e, 2
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x90
        call amd64_emit_byte
    ELSEIF rax, e, 3
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 4
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x40
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 5
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x44
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 6
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x44
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 7
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x80
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
    ELSEIF rax, e, 8
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x84
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
    ELSEIF rax, e, 9
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x84
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        ENDIF
    epilogue

;*
; * [amd64_emit_word]
; ;
global amd64_emit_word
amd64_emit_word:
    push    rax
    push    rcx
    push    rdi                    ; amd64_emit_byte clobbers rdi/rcx
    mov     rcx, 2
.loopw:
    mov     rdi, [rsp]
    mov     al, dil
    push    rcx
    call    amd64_emit_byte
    pop     rcx
    shr     qword [rsp], 8
    dec     rcx
    jnz     .loopw
    pop     rdi
    pop     rcx
    pop     rax
    ret

;*
; * [amd64_emit_dword]
; ;

;*
; * [amd64_emit_qword]
; ;
global amd64_emit_qword
amd64_emit_qword:
    push    rax
    push    rcx
    push    rdi                    ; amd64_emit_byte clobbers rdi/rcx
    mov     rcx, 8
.loopq:
    mov     rdi, [rsp]
    mov     al, dil
    push    rcx
    call    amd64_emit_byte
    pop     rcx
    shr     qword [rsp], 8
    dec     rcx
    jnz     .loopq
    pop     rdi
    pop     rcx
    pop     rax
    ret
