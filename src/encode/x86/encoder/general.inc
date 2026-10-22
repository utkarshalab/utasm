; ============================================================================
; File        : src/encode/x86/encoder/general.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : movzx / movsx / movsxd, lea, test, unary, shifts, imul, cmovcc / setcc, enter, int, system, in / out, x87, SSE crypto
; ============================================================================


;*
; * [amd64_encode_movx]
; * MOVZX / MOVSX: 0F B6/B7 (zero-extend) or 0F BE/BF (sign-extend).
; * Input: r13 = base opcode (0xB6 or 0xBE); the source width picks base or base+1.
; ;
amd64_encode_movx:
    prologue
    lea     r10, [r12 + INST_op0]  ; dest register
    lea     r11, [r12 + INST_op1]  ; source: register or memory

    ; "movzx bx, r9d", "movzx rbx, dword [x]": mov's load form, 8B /r
    ; with the destination's size (mode.s amd64_shape_forms, NASM 3's)
    extern  amd64_movzx_mov
    cmp     byte [rel amd64_movzx_mov], 0
    je      .not_mov
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10
    mov     rdx, r11
    call    amd64_emit_prefixes
    mov     al, 0x8B
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    jmp     .modrm
.not_mov:

    ; VALIDATION: MOVZX/MOVSX widen an 8- or 16-bit source only. No form takes
    ; a 32-bit source -- a plain 32-bit MOV already zero-extends, and MOVSXD
    ; covers the signed case. The general operand-size check in the dispatcher
    ; deliberately skips these mnemonics, so without this they would encode a
    ; dword source as if it were a byte one.
    IF byte [r11 + OPERAND_size], e, 8
        jmp .size_ok
        ENDIF
    IF byte [r11 + OPERAND_size], e, 16
        jmp .size_ok
        ENDIF
    jmp     .error

.size_ok:
    ; The destination at least as wide as the source (r16, r/m16: 66 0F
    ; B7 / BF, as NASM 3 writes "movzx ax, dx")
    mov     al, [r10 + OPERAND_size]
    cmp     al, [r11 + OPERAND_size]
    jb      .error

    ; Width of the destination drives REX.W / 0x66
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10               ; dest -> ModRM.reg (REX.R)
    mov     rdx, r11               ; src  -> ModRM.rm  (REX.B/X)
    call    amd64_emit_prefixes

    mov     al, 0x0F
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     rax, r13
    IF byte [r11 + OPERAND_size], e, 16
        inc     al                 ; word source: 0xB7 / 0xBF
        ENDIF
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
.modrm:
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov     al, 0xC0
        mov     cl, [r10 + OPERAND_reg]
        and     cl, 0x07
        shl     cl, 3
        or      al, cl
        mov     cl, [r11 + OPERAND_reg]
        and     cl, 0x07
        or      al, cl
        call    amd64_emit_byte
        ELSE
        mov     al, [r10 + OPERAND_reg]
        mov     rdi, r11
        call    amd64_emit_modrm_sib
        ENDIF
    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_INVALID_OPERAND
.done:
    epilogue

;*
; * [amd64_encode_movsxd]
; * MOVSXD r64, r/m32 — opcode 0x63 /r.
; ;
amd64_encode_movsxd:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]

    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10
    mov     rdx, r11
    call    amd64_emit_prefixes

    mov     al, 0x63
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov     al, 0xC0
        mov     cl, [r10 + OPERAND_reg]
        and     cl, 0x07
        shl     cl, 3
        or      al, cl
        mov     cl, [r11 + OPERAND_reg]
        and     cl, 0x07
        or      al, cl
        call    amd64_emit_byte
        ELSE
        mov     al, [r10 + OPERAND_reg]
        mov     rdi, r11
        call    amd64_emit_modrm_sib
        ENDIF
    xor     rax, rax
    epilogue

;*
; * [amd64_encode_lea]
; ;
amd64_encode_lea:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]


    ; REX.B/REX.X come from the address operand, so it has to go through
    ; emit_prefixes rather than a hand-built REX.W.
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10               ; ModRM.reg = destination register
    mov     rdx, r11               ; r/m = the address being formed
    call    amd64_emit_prefixes

    mov     al, 0x8D               ; Opcode LEA
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]  ; the calls above clobber r10/r11
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_lea_address]
; * Purpose: lea takes a register and an address, as NASM reads them:
; *   "lea rax, x" is the address x ([x]; RIP-relative under default rel
; *   when x is a label) - it was encoded as [rax+rax+x]; "lea rax, rbx" is
; *   no combination.
; * Input  : R12 = INST (lea, two operands)
; * Output : RAX = OK or EXIT_ENCODE_FAIL
; ;
amd64_lea_address:
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    cmp     byte [r10 + OPERAND_kind], OP_REG
    jne     .bad
    movzx   eax, byte [r11 + OPERAND_kind]
    cmp     eax, OP_MEM
    je      .ok
    cmp     eax, OP_IMM
    je      .as_address
    cmp     eax, OP_SYMBOL
    jne     .bad
.as_address:
    mov     byte [r11 + OPERAND_kind], OP_MEM
    mov     byte [r11 + OPERAND_base], 0xFF
    mov     byte [r11 + OPERAND_index], 0xFF
    mov     byte [r11 + OPERAND_scale], 1
    extern  global_ctx
    test    dword [rel global_ctx + ASMCTX_flags], CTX_FLAG_DEFAULT_REL
    jz      .ok
    mov     rax, [r11 + OPERAND_sym]
    test    rax, rax
    jz      .absolute                      ; a number: an absolute address
    cmp     byte [rax], TAG_SYMBOL
    jne     .rip                           ; a label not defined yet
    cmp     byte [rax + SYMBOL_kind], SYM_CONSTANT
    je      .absolute
    cmp     byte [rax + SYMBOL_kind], SYM_STRUCT_FIELD
    je      .absolute
    cmp     word [rax + SYMBOL_section], SHN_ABS
    je      .absolute
.rip:
    or      byte [r11 + OPERAND_flags], OP_FLAG_REL
    mov     byte [r11 + OPERAND_base], REG_RIP
.absolute:
    ; under default rel: NASM's warning (not in a trial encoding)
    extern  reloc_quiet, warn_begin, warn_text, warn_end
    cmp     byte [rel reloc_quiet], 0
    jne     .ok
    ; a name defined later: not known in pass 1 (a label, which is no
    ; number, or a constant the second pass knows - src/core/known.s)
    extern  known_active
    cmp     byte [r11 + OPERAND_fwd], 0
    je      .warn
    cmp     byte [rel known_active], 0
    je      .ok
.warn:
    mov     edi, WC_EA_ABSOLUTE
    call    warn_begin
    test    eax, eax
    jz      .ok
    lea     rsi, [rel lea_ea_absolute]
    call    warn_text
    call    warn_end
.ok:
    xor     eax, eax
    ret
.bad:
    mov     eax, EXIT_ENCODE_FAIL
    ret

[SECTION .rodata]
amd64_abs_target: db RELOC_ABS_MARK, 0   ; a branch to a number (amd64_emit_branch_disp)
lea_ea_absolute: db "absolute address can not be RIP-relative", 0
s_ea_dispsize:  db "displacement size ignored on absolute address", 0
s_disp_bounds:  db "dword data exceeds bounds", 0
[SECTION .text]

;*
; * [amd64_encode_test]
; ;
amd64_encode_test:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]

    IF byte [r11 + OPERAND_kind], e, OP_IMM
        jmp .imm_form
        ENDIF

    ; TEST r/m, reg  ->  85 /r (84 /r for byte operands). TEST is
    ; symmetric: "test reg, [mem]" is the same instruction with the memory
    ; in r/m, as NASM encodes it. The register gives the size.
    IF byte [r11 + OPERAND_kind], e, OP_MEM
        xchg    r10, r11
        ENDIF
    push    r10                    ; r/m
    push    r11                    ; ModRM.reg
    mov     al, [r11 + OPERAND_size]
    mov     rsi, r11
    mov     rdx, r10
    call    amd64_emit_prefixes

    mov     r11, [rsp]
    mov     rax, r13               ; 0x85, one below for 8-bit
    IF byte [r11 + OPERAND_size], e, 8
        dec al
        ENDIF
    call    amd64_emit_byte

    pop     r11
    pop     r10
    mov     al, [r11 + OPERAND_reg]
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done

.imm_form:
    ; TEST r/m, imm -> F7 /0 id (F6 /0 ib for bytes). The accumulator has the
    ; shorter A8/A9 form, which is what NASM picks.
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes

    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], ne, OP_REG
        jmp .imm_modrm
        ENDIF
    IF byte [r10 + OPERAND_reg], ne, REG_RAX
        jmp .imm_modrm
        ENDIF

    ; A8 ib / A9 id
    mov     al, 0xA9
    IF byte [r10 + OPERAND_size], e, 8
        mov al, 0xA8
        ENDIF
    call    amd64_emit_byte
    jmp     .imm_value

.imm_modrm:
    lea     r10, [r12 + INST_op0]
    mov     al, 0xF7
    IF byte [r10 + OPERAND_size], e, 8
        mov al, 0xF6
        ENDIF
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    mov     al, 0                  ; /0
    mov     rdi, r10
    call    amd64_emit_modrm_sib

.imm_value:
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    IF byte [r10 + OPERAND_size], e, 8
        mov     rax, [r11 + OPERAND_imm]
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_size], e, 16
        mov     rdi, [r11 + OPERAND_imm]
        call    amd64_emit_word
        jmp     .done
        ENDIF
    mov     rdi, [r11 + OPERAND_imm]
    call    amd64_emit_dword

.done:
    epilogue

;*
; * [amd64_encode_unary]
; * INC/DEC/NEG/NOT
; ;
amd64_encode_unary:
    prologue
    lea     r10, [r12 + INST_op0]

    ; Prefixes: REX.W / 0x66 / extended-register bits
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    lea     r10, [r12 + INST_op0]

    ; 0xFF for INC/DEC (/0,/1), 0xF7 for NOT/NEG/MUL/IMUL/DIV/IDIV (/2../7)
    mov     al, 0xFF
    IF r14b, ge, 2
        mov al, 0xF7
        ENDIF
    IF byte [r10 + OPERAND_size], e, 8
        dec al             ; 8-bit forms are 0xFE / 0xF6
        ENDIF
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]

    IF byte [r10 + OPERAND_kind], e, OP_REG
        ; Register form: ModRM mod=11, reg = extension digit, rm = register
        mov     al, 0xC0
        mov     cl, r14b
        and     cl, 0x07
        shl     cl, 3
        or      al, cl
        mov     cl, [r10 + OPERAND_reg]
        and     cl, 0x07
        or      al, cl
        call    amd64_emit_byte
        ELSE
        mov     al, r14b       ; Extension Digit
        mov     rdi, r10
        call    amd64_emit_modrm_sib
        ENDIF
.done:
    epilogue

;*
; * [amd64_encode_shift]
; * SHL/SHR/SAR/ROL/ROR
; ;
amd64_encode_shift:
    prologue
    lea     r10, [r12 + INST_op0]

    ; Prefixes come from the destination alone: the count is either CL or an
    ; imm8 and never contributes REX.W or a size override.
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes

    ; r15 = opcode bias: the 8-bit forms are D0/D2/C0, one below the rest
    lea     r10, [r12 + INST_op0]
    xor     r15, r15
    IF byte [r10 + OPERAND_size], e, 8
        mov r15, 1
        ENDIF

    ; A bare "shl reg" and "shl reg, 1" both use the by-one opcode (D1)
    lea     r11, [r12 + INST_op1]
    IF byte [r12 + INST_nops], e, 1
        jmp .by_one
        ENDIF
    IF byte [r11 + OPERAND_kind], e, OP_IMM
        IF qword [r11 + OPERAND_imm], e, 1
            jmp .by_one
            ENDIF

        ; C1 /digit ib
        mov     al, 0xC1
        sub     al, r15b
        call    amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov     al, r14b
        mov     rdi, r10
        call    amd64_emit_modrm_sib
        lea     r11, [r12 + INST_op1]
        mov     rax, [r11 + OPERAND_imm]
        call    amd64_emit_byte
        jmp     .done
        ENDIF

    ; Register count: CL is the only encodable one (D3 /digit)
    IF byte [r11 + OPERAND_kind], ne, OP_REG
        jmp .error
        ENDIF
    IF byte [r11 + OPERAND_size], ne, 8
        jmp .error
        ENDIF
    IF byte [r11 + OPERAND_reg], ne, REG_RCX
        jmp .error
        ENDIF
    mov     al, 0xD3
    sub     al, r15b
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     al, r14b
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done

.by_one:
    mov     al, 0xD1
    sub     al, r15b
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     al, r14b
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done

.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_imul]
; ;
amd64_encode_imul:
    prologue

    ; 1-Operand: IMUL r/m (F7 /5)
    cmp     byte [r12 + INST_nops], 1
    IF e
        mov     r14, 5
        call    amd64_encode_unary_math   ; has its own frame: call, never jmp
        jmp     .done
        ENDIF

    ; 2-Operand with an immediate is the 3-operand form with the destination
    ; doubling as the source: "imul rcx, 56" == "imul rcx, rcx, 56"
    cmp     byte [r12 + INST_nops], 2
    IF e
        lea     r11, [r12 + INST_op1]
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            lea     rdi, [r12 + INST_op2]
            lea     rsi, [r12 + INST_op1]
            mov     rcx, (OPERAND_SIZE / 8)
            rep movsq                      ; op2 = the immediate
            lea     rdi, [r12 + INST_op1]
            lea     rsi, [r12 + INST_op0]
            mov     rcx, (OPERAND_SIZE / 8)
            rep movsq                      ; op1 = the destination
            mov     byte [r12 + INST_nops], 3
            ENDIF
        ENDIF

    ; 2-Operand: IMUL reg, r/m (0F AF /r)
    cmp     byte [r12 + INST_nops], 2
    IF e
        lea     r10, [r12 + INST_op0]
        lea     r11, [r12 + INST_op1]
        mov     al, [r10 + OPERAND_size]
        mov     rsi, r10
        mov     rdx, r11
        call    amd64_emit_prefixes

        mov     al, 0x0F
        call    amd64_emit_byte
        mov     al, 0xAF
        call    amd64_emit_byte

        ; the calls above clobber r10/r11, so take the operands again
        lea     r10, [r12 + INST_op0]
        lea     r11, [r12 + INST_op1]
        mov     al, [r10 + OPERAND_reg]
        mov     rdi, r11
        call    amd64_emit_modrm_sib
        jmp     .done
        ENDIF

    ; 3-Operand: IMUL reg, r/m, imm (6B /r ib when the immediate fits, else 69 /r id)
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10
    mov     rdx, r11
    call    amd64_emit_prefixes

    ; the form amd64_imm_canon chose, else 6B for a signed byte
    cmp     byte [rel amd64_imm_sb], 2
    je      .imm_full
    cmp     byte [rel amd64_imm_sb], 1
    je      .imm_byte
    lea     r10, [r12 + INST_op2]
    mov     rax, [r10 + OPERAND_imm]
    cmp     rax, -128
    jl      .imm_full
    cmp     rax, 127
    jg      .imm_full
.imm_byte:
    mov     al, 0x6B
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib

    lea     r10, [r12 + INST_op2]
    mov     rax, [r10 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done

.imm_full:
    mov     al, 0x69
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib

    ; the immediate has the operation's width: imm16 for a 16-bit one
    lea     r10, [r12 + INST_op2]
    mov     rdi, [r10 + OPERAND_imm]
    cmp     byte [r12 + INST_op0 + OPERAND_size], 16
    jne     .imm32
    call    amd64_emit_word
    jmp     .done
.imm32:
    call    amd64_emit_dword

.done:
    epilogue

;*
; * [amd64_encode_unary_math]
; * MUL/DIV/IDIV/etc.
; ;
amd64_encode_unary_math:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; Smart Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    lea     r10, [r12 + INST_op0]      ; emit_prefixes clobbers r10

    ; Opcode is 0xF6 (8-bit) or 0xF7 (16/32/64-bit)
    mov     al, 0xF6
    IF byte [r10 + OPERAND_size], ne, 8
        inc al
        ENDIF
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]

    mov     al, r14b       ; Digit (4=MUL, 6=DIV, 7=IDIV)
    mov     rdi, r10
    call    amd64_emit_modrm_sib
.done:
    epilogue

;*
; * [amd64_encode_cmovcc]
; ;
amd64_encode_cmovcc:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 4000
    and     rax, 0x0F
    mov     r14, rax           ; Condition Code
    
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]

    ; Operand-size and REX prefixes from the operands, as for BT/SETcc:
    ; 0x66 for 16-bit, REX.W only for 64-bit, REX.R/X/B as needed. (A
    ; hard-coded 0x48 made every CMOVcc 64-bit: cmovne eax, ecx was
    ; emitted as cmovne rax, rcx.)
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10                   ; ModRM.reg operand (destination)
    mov     rdx, r11                   ; ModRM.rm operand (source)
    call    amd64_emit_prefixes

    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x40
    add     al, r14b
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]      ; the calls above clobber r10/r11
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_setcc]
; ;
amd64_encode_setcc:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 4016
    and     rax, 0x0F
    mov     r14, rax
    
    lea     r10, [r12 + INST_op0]

    ; SETcc always writes a byte. Go through emit_prefixes so R8B-R15B get
    ; REX.B and SPL/BPL/SIL/DIL get the bare REX they require -- without it
    ; those four encode as AH/CH/DH/BH instead.
    mov     al, 8
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes

    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x90
    add     al, r14b
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]  ; the calls above clobber r10
    xor     al, al             ; Reg field 0
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_enter]
; ;
amd64_encode_enter:
    prologue
    mov     al, 0xC8
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    mov     ax, [r10 + OPERAND_imm]
    call    amd64_emit_byte    ; Enter uses word, then byte
    mov     al, ah
    call    amd64_emit_byte
    
    lea     r11, [r12 + INST_op1]
    mov     al, [r11 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_emit_branch_rel8]
; ;
amd64_emit_branch_rel8:
    call    amd64_emit_byte
    xor     al, al             ; rel8 placeholder
    call    amd64_emit_byte
    ret

    xor     al, al             ; rel8 placeholder
    call    amd64_emit_byte
    ret

;*
; * [amd64_encode_int]
; ;
amd64_encode_int:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0xCD
    call    amd64_emit_byte
    mov     rax, [r10 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_system_m]
; * LGDT/LIDT
; ;
amd64_encode_system_m:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x01
    call    amd64_emit_byte
    
    mov     al, r14b           ; Digit 2 for LGDT, 3 for LIDT
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_system_00]
; * R14 = Digit
; ;
amd64_encode_system_00:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x00
    call amd64_emit_byte
    mov     al, r14b
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_in]
; ;
amd64_encode_in:
    prologue
    ; in al/ax/eax, dx  ->  EC / ED;   in al/ax/eax, imm8  ->  E4 / E5 ib
    lea     r10, [r12 + INST_op0]          ; the accumulator
    lea     r11, [r12 + INST_op1]          ; the port
    mov     r13d, 0xEC
    IF byte [r11 + OPERAND_kind], ne, OP_REG
        mov     r13d, 0xE4
        ENDIF
    call    amd64_encode_io
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_out]
; ;
amd64_encode_out:
    prologue
    ; out dx, al/ax/eax  ->  EE / EF;   out imm8, al/ax/eax  ->  E6 / E7 ib
    lea     r10, [r12 + INST_op1]          ; the accumulator
    lea     r11, [r12 + INST_op0]          ; the port
    mov     r13d, 0xEE
    IF byte [r11 + OPERAND_kind], ne, OP_REG
        mov     r13d, 0xE6
        ENDIF
    call    amd64_encode_io
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_io]
; * IN / OUT: R10 = the accumulator operand, R11 = the port (DX or an
; * imm8), R13 = the byte-sized opcode. The accumulator must be AL, AX or
; * EAX and a register port DX.
; ;
amd64_encode_io:
    push    r14
    push    r15
    mov     r14, r10
    mov     r15, r11
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .bad
    cmp     byte [r14 + OPERAND_reg], REG_RAX
    jne     .bad
    movzx   eax, byte [r14 + OPERAND_size]
    cmp     eax, 64
    je      .bad
    cmp     byte [r15 + OPERAND_kind], OP_REG
    jne     .size
    cmp     byte [r15 + OPERAND_reg], REG_RDX
    jne     .bad
    cmp     byte [r15 + OPERAND_size], 16
    jne     .bad
.size:
    call    amd64_osz66                    ; ax: 66 (eax in bits 16)
    test    eax, eax
    jz      .no_osz
    call    amd64_emit_osz_prefix
.no_osz:
    mov     eax, r13d
    cmp     byte [r14 + OPERAND_size], 8
    je      .opcode
    inc     eax                            ; the 16/32-bit form
.opcode:
    call    amd64_emit_byte
    cmp     byte [r15 + OPERAND_kind], OP_REG
    je      .ok
    mov     rax, [r15 + OPERAND_imm]
    call    amd64_emit_byte
.ok:
    xor     eax, eax
    pop     r15
    pop     r14
    ret
.bad:
    mov     eax, EXIT_ENCODE_FAIL
    pop     r15
    pop     r14
    ret

;*
; * [amd64_encode_fpu]
; * FLD/FST/FADD/etc.
; ;
amd64_encode_fpu:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; x87 doesn't use REX
    mov     rax, r13           ; Base Opcode (e.g. 0xD8)
    call    amd64_emit_byte
    
    ; ModRM extension
    mov     al, r14b           ; Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

    mov     al, r14b           ; Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done

;*
; * [amd64_encode_sse]
; * R13 = Opcode
; * R14 = Format (0=0F, 1=66 0F, 2=0F 38, 3=0F 3A)
; ;
;*
; * [amd64_encode_sse_crypto]
; * R13 = Opcode
; * R14 = Map (1=0F, 2=0F 38, 3=0F 3A)
; * R15 = Mandatory Prefix (0=None, 0x66, 0xF2, 0xF3)
; ;
amd64_encode_sse_crypto:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; Mandatory Prefix
    IF r15, ne, 0
        mov rax, r15
        call amd64_emit_byte
        ENDIF
    
    ; REX if using R8-R15 or XMM8-XMM31
    xor     rax, rax
    IF byte [r10 + OPERAND_reg], ge, 8
        or al, 0x44
    ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or al, 0x41
    ENDIF
    IF al, ne, 0
        call amd64_emit_byte
    ENDIF
    
    ; Opcode Escape
    mov     al, 0x0F
    call amd64_emit_byte
    IF r14b, e, 2
        mov al, 0x38
        call amd64_emit_byte
    ELSEIF r14b, e, 3
        mov al, 0x3A
        call amd64_emit_byte
        ENDIF
    
    mov     al, r13b
    call amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    
    ; If Map 3 (0F 3A), emit immediate byte if present
    IF r14b, e, 3
        lea r11, [r12 + INST_op2]
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            mov rax, [r11 + OPERAND_imm]
            call amd64_emit_byte
            ENDIF
            ENDIF
    jmp     .done
.done:
    epilogue
