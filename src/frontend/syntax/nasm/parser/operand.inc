; ============================================================================
; File        : src/frontend/syntax/nasm/parser/operand.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : one operand: register, immediate, memory or far pointer (parser_parse_operand), a register's size and kind
; ============================================================================


;*
; * [parser_parse_operand]
; * Purpose: Parses an operand using the current architectural register table.
; ;
parser_parse_operand:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     qword [rel mem_struc], 0       ; (none left by an operand in error)
    
    ; one of OPERAND_RING, cleared: the caller copies it into its INST
    mov     eax, [rel opnd_ring_next]
    lea     ecx, [eax + 1]
    and     ecx, OPERAND_RING - 1
    mov     [rel opnd_ring_next], ecx
    imul    eax, eax, OPERAND_SIZE
    lea     rdx, [rel opnd_ring]
    add     rdx, rax
    mov     rdi, rdx
    mov     ecx, OPERAND_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     r12, rdx
    mov     byte [r12 + OPERAND_tag], TAG_OPERAND
    mov     byte [rel opnd_to], 0
    mov     byte [rel opnd_wrap], 0
    mov     byte [rel masm_no_var], 0

.fetch_operand_token:
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r13, rdx

    ; %use masm (src/frontend/syntax/masm/masm.s): OFFSET X is X's address; a typed
    ; variable ("x DWORD 5") is a memory operand of its type ("mov eax, x")
    cmp     byte [rel masm_hl], 0
    je      .masm_done
    cmp     byte [r13 + TOKEN_kind], TOK_IDENT
    jne     .masm_done
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [rel str_masm_offset]
    call    str_cmp
    test    rax, rax
    jnz     .masm_var
    mov     byte [rel masm_no_var], 1
    jmp     .fetch_operand_token
.masm_var:
    cmp     byte [rel masm_no_var], 0
    jne     .masm_done
    mov     rdi, [r13 + TOKEN_value]
    extern  masm_var_size
    call    masm_var_size
    test    eax, eax
    jz      .masm_done
    shl     eax, 3                         ; (bits)
    mov     [r12 + OPERAND_size], al
    mov     [r12 + OPERAND_xsize], ax
    mov     byte [rel far_colon], 0
    jmp     .open_mem
.masm_done:

    ; "OFFSET FLAT:x" (%use masm, GNU's Intel syntax): an address is flat,
    ; the "flat:" says nothing
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    je      .flat_word
    cmp     byte [r13 + TOKEN_kind], TOK_IDENT
    jne     .not_flat_word
.flat_word:
    mov     rsi, [r13 + TOKEN_value]
    call    parser_seg_override_flat
    jnz     .not_flat_word
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    je      .fetch_operand_token           ; ("FLAT:" one token)
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .not_flat_word
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .fetch_operand_token
.not_flat_word:

    ; Branch-distance modifiers, recorded on the operand for the encoder:
    ; "short" forces the rel8 form; "strict" forces rel32, so the encoder
    ; never shortens it; "near" is only not short or far - NASM 3 makes it
    ; short where it reaches (OPERAND_near: -O0 keeps it long)
    IF byte [r13 + TOKEN_kind], e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_strict]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_STRICT
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_near]
        call    str_cmp_kw
        IF rax, e, 0
            mov     byte [r12 + OPERAND_near], 1
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_short]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_SHORT
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_far]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_FAR
            jmp .fetch_operand_token
            ENDIF
        ; "fadd to st1": the x87 forms that write st(i) (NASM's "to"), when
        ; an st register follows - else "to" is a name
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_to]
        call    str_cmp_kw
        test    rax, rax
        jnz     .not_to
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_IDENT
        jne     .not_to
        mov     rax, [rdx + TOKEN_value]
        movzx   ecx, word [rax]
        or      ecx, 0x2020
        cmp     ecx, 't' << 8 | 's'
        jne     .not_to
        mov     byte [rel opnd_to], 1
        jmp     .fetch_operand_token
.not_to:
        ENDIF

    ; "jmp SEL:offset": a name right before the colon lexes as a label;
    ; it is the far pointer's segment, the colon is noted for
    ; parser_parse_instruction
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    jne     .not_far_label
    mov     byte [r13 + TOKEN_kind], TOK_IDENT
    mov     byte [rel far_colon], 1
.not_far_label:
    mov     al, [r13 + TOKEN_kind]

    ; APX's "{dfv=of,zf}" before ccmp's / ctest's operands: the flags it
    ; sets when its condition is false (INST_dfv)
    cmp     al, TOK_LBRACE
    jne     .not_dfv
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .not_dfv_al
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_dfv]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_dfv_al
    call    parser_parse_dfv
    check_err
    jmp     .fetch_operand_token
.not_dfv_al:
    mov     al, [r13 + TOKEN_kind]
.not_dfv:

    ; 0. AVX-512 rounding operand: {rn-sae}, {rd-sae}, {ru-sae}, {rz-sae}, {sae}
    IF al, e, TOK_LBRACE
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
        je      .not_rounding
        call    parser_parse_decorator
        check_err
        cmp     byte [r12 + OPERAND_kind], OP_ROUNDING
        je      .success
        cmp     byte [r12 + OPERAND_kind], OP_SAE
        je      .success
        mov     rax, EXIT_INVALID_EXPR     ; {k1}/{z}/{1toN} must follow an operand
        jmp     .error
.not_rounding:
        mov     al, [r13 + TOKEN_kind]
        ENDIF

    ; 1. Memory Operands [base + index*scale + disp]
    IF al, e, TOK_LBRACKET
        ; GNU's Intel syntax: "call [QWORD PTR 80[rax]]" (GCC's indirect
        ; call) - the sized operand inside, its bracket closed after it
        extern  att_on, gas_names
        cmp     byte [rel gas_names], 0
        je      .not_wrapped
        cmp     byte [rel att_on], 0
        jne     .not_wrapped
        cmp     byte [rel opnd_wrap], 0
        jne     .not_wrapped
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_IDENT
        jne     .not_wrapped
        mov     rdi, [rdx + TOKEN_value]
        call    parser_parse_size_specifier_string
        test    rax, rax
        jz      .not_wrapped
        mov     byte [rel opnd_wrap], 1
        jmp     .fetch_operand_token
.not_wrapped:
        call    parser_parse_mem_operand
        check_err
        call    parser_masm_field          ; ("[rbx].POINT.y", %use masm)
        check_err
        jmp     .success
        ENDIF

    ; 2. Registers or Size Specifiers (handled via ident lookup)
    IF al, e, TOK_IDENT
        ; %use masm: "ptr [x]", "ptr x" with no size
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_masm_ptr]
        call    str_cmp
        test    rax, rax
        jnz     .not_bare_ptr
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     r13, rdx
        cmp     byte [r13 + TOKEN_kind], TOK_LBRACKET
        je      .sized_mem
        jmp     .open_mem
.not_bare_ptr:
        mov     rdi, [r13 + TOKEN_value]
        call    parser_parse_size_specifier_string
        test    rax, rax
        jz      .try_register
        
        ; Size specifier logic
        mov     [r12 + OPERAND_size], al
        mov     [r12 + OPERAND_xsize], ax      ; yword/zword need 16 bits
        
        ; Peek next token. "ptr" (MASM's) is taken, with NASM's warning;
        ; under %use masm (__?masm_ptr?__) what follows is a memory
        ; operand, in brackets or not ("dword ptr x", "dword ptr fs:[x]")
        mov     byte [rel masm_mem], 0
        mov     rdi, rbx
        call    preprocessor_peek_token
        mov     rcx, rdx
        IF byte [rcx + TOKEN_kind], e, TOK_IDENT
            mov     rdi, [rcx + TOKEN_value]
            lea     rsi, [rel str_masm_ptr]
            call    str_cmp
            test    rax, rax
            jnz     .not_masm_ptr
            mov     byte [rel masm_mem], 1
            jmp     .take_ptr
.not_masm_ptr:
            mov     rdi, rbx
            call    preprocessor_peek_token
            mov     rdi, [rdx + TOKEN_value]
            lea     rsi, [rel str_ptr]
            call    str_cmp_kw
            test    rax, rax
            jnz     .no_ptr
            mov     rdi, rbx
            call    preprocessor_peek_token
            mov     rdi, [rdx + TOKEN_value]
            call    parser_ptr_warn
.take_ptr:
            mov     rdi, rbx
            call    preprocessor_next_token ; consume "ptr"
            ; MASM's cast over a typed name: "dword ptr n", n a PROC's
            ; "qword [rbp - 8]" (masm.s) - the ptr's size wins, the other
            ; dropped
            cmp     byte [rel masm_mem], 0
            je      .ptr_cast_done
            push    rdx
            mov     rdi, rbx
            call    preprocessor_peek_token
            cmp     byte [rdx + TOKEN_kind], TOK_IDENT
            jne     .ptr_cast_pop
            mov     rdi, [rdx + TOKEN_value]
            call    parser_parse_size_specifier_string
            test    rax, rax
            jz      .ptr_cast_pop
            mov     rdi, rbx
            call    preprocessor_next_token
.ptr_cast_pop:
            pop     rdx
.ptr_cast_done:
            ; "dword ptr" with nothing after it: the label ptr, sized
            push    rdx
            mov     rdi, rbx
            call    preprocessor_peek_token
            pop     rsi
            movzx   eax, byte [rdx + TOKEN_kind]
            cmp     eax, TOK_NEWLINE
            je      .ptr_symbol
            cmp     eax, TOK_EOF
            je      .ptr_symbol
            cmp     eax, TOK_COMMA
            jne     .no_ptr
.ptr_symbol:
            mov     byte [rel masm_mem], 0
            mov     rdx, rsi               ; the sized operand is ptr itself
            jmp     .sized_token
.no_ptr:
            ENDIF

        mov     rdi, rbx
        call    preprocessor_next_token
.sized_token:
        mov     r13, rdx
        cmp     byte [r13 + TOKEN_kind], TOK_LBRACKET
        je      .sized_mem
        ; "call qword far [rax]": far after the size
        cmp     byte [r13 + TOKEN_kind], TOK_IDENT
        jne     .sized_not_far
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_far]
        call    str_cmp_kw
        test    rax, rax
        jnz     .sized_not_far
        or      byte [r12 + OPERAND_flags], OP_FLAG_FAR
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .sized_token
.sized_not_far:
        ; "qword gs:[rbx]": "gs:" lexed as a label, as at the start
        cmp     byte [r13 + TOKEN_kind], TOK_LABEL
        jne     .sized_not_label
        mov     byte [r13 + TOKEN_kind], TOK_IDENT
        mov     byte [rel far_colon], 1
.sized_not_label:
        cmp     byte [rel masm_mem], 0
        jne     .open_mem
        ; A register with its size written out ("movzx r9d, byte al"): the
        ; size must be the register's. Anything else is a sized immediate.
        cmp     byte [r13 + TOKEN_kind], TOK_IDENT
        jne     .expression
        movzx   eax, word [r12 + OPERAND_xsize]
        push    rax
        call    parser_get_arch_tables
        mov     rdi, rdx
        mov     rsi, [r13 + TOKEN_value]
        call    parser_parse_reg_info
        pop     rcx
        cmp     rax, ERR
        je      .expression                ; a symbol: "dword SIZE_CONST"
        ; a segment register's size is ignored, as NASM does ("push dword
        ; fs" is push fs)
        movzx   eax, byte [r12 + OPERAND_reg]
        sub     eax, REG_CS
        cmp     eax, 5
        mov     [rel opnd_kw_size], cx     ; ("qword gs:[rbx]": the size)
        jbe     .reg_or_seg
        ; a mask register takes any size: NASM's "kmov byte k1, k2" picks
        ; kmovb by it
        movzx   eax, byte [r12 + OPERAND_reg]
        cmp     eax, 72
        jb      .sized_check
        cmp     eax, 79
        ja      .sized_check
        mov     [r12 + OPERAND_size], cl
        mov     [r12 + OPERAND_xsize], cx
        jmp     .sized_reg
.sized_check:
        cmp     cx, [r12 + OPERAND_xsize]
        je      .sized_reg
        ; "insertps xmm0, dword xmm1": on a vector register, a smaller size
        ; is the operand's as memory (the encoder takes the form with it)
        cmp     word [r12 + OPERAND_xsize], 128
        jb      .sized_bad
        cmp     cx, [r12 + OPERAND_xsize]
        ja      .sized_bad
        mov     [r12 + OPERAND_dispsize], cl
.sized_reg:
        mov     byte [r12 + OPERAND_kind], OP_REG
        jmp     .success
.sized_bad:
        mov     rax, EXIT_REG_SIZE         ; the size does not match the register
        jmp     .error
.sized_mem:
        call    parser_parse_mem_operand
        check_err
        jmp     .success
.open_mem:
        ; %use masm: "ptr x", "ptr fs:[x]": a memory operand with no
        ; bracket of its own (parser_parse_mem_operand ends it at a comma
        ; or the end of the line)
        ; "qword ptr gs:foo": "gs:" lexed as a label, its colon read
        cmp     byte [rel far_colon], 0
        je      .open_putback
        mov     byte [rel far_colon], 0
        mov     rsi, [r13 + TOKEN_value]
        call    parser_seg_override
        check_err
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_LBRACKET
        jne     .open_parse
        mov     rdi, rbx
        call    preprocessor_next_token
        call    parser_parse_mem_operand
        check_err
        jmp     .success
.open_putback:
        mov     rdi, rbx
        mov     rsi, r13
        call    preprocessor_putback_token
.open_parse:
        mov     byte [rel mem_open], 1
        call    parser_parse_mem_operand
        mov     byte [rel mem_open], 0
        check_err
        jmp     .success

.try_register:
        call    parser_get_arch_tables
        mov     rdi, rdx                ; RDI = Register Table Pointer
        mov     rsi, [r13 + TOKEN_value]
        call    parser_parse_reg_info
        IF rax, ne, ERR
            mov     word [rel opnd_kw_size], 0
            jmp     .reg_or_seg
            ENDIF

        ; Not a register, fall through to expression (it's a symbol)
        ; BUT FIRST: check for AArch64 shift keywords
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
        jne     .not_shift
        
        mov     rdi, [r13 + TOKEN_value]
        call    parser_check_aarch64_shift
        IF rax, ne, ERR
            ; It's a shift! (RAX = SHIFT_*)
            mov     [r12 + OPERAND_shift_type], al
            ; Expect TOK_HASH or just expression
            mov     rdi, rbx
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_HASH
                mov     rdi, rbx
                call    preprocessor_next_token
                ENDIF
            mov     rdi, rbx
            call    parser_evaluate_expression
            check_err
            mov     [r12 + OPERAND_shift_imm], dl
            ; This shift applies to the PREVIOUS register operand if this was just "lsl #1"
            ; But usually it's "x2, lsl #1". The parser sees "x2" as op2, then "lsl" as op3.
            ; Wait, our parser handles operands separated by commas.
            ; "add x0, x1, x2, lsl #1" => 4 operands.
            ; The encoder for ADD expects 3 operands, where op2 might have a shift.
            ; So I should actually "merge" this shift into the previous operand.
            movzx   rax, byte [r15 + INST_nops]
            IF al, g, 0
                dec al
                imul rax, OPERAND_SIZE
                lea  rdi, [r15 + INST_op0 + rax]
                mov  cl, [r12 + OPERAND_shift_type]
                mov  [rdi + OPERAND_shift_type], cl
                mov  cl, [r12 + OPERAND_shift_imm]
                mov  [rdi + OPERAND_shift_imm], cl
                
                ; Discard this temporary operand: no operand for the
                ; caller (rdx = 0); it returned the shift amount there, which
                ; the caller copied an operand from, and skipped restoring
                ; the registers it saved
                xor     eax, eax
                xor     edx, edx
                pop     r13
                pop     r12
                pop     rbx
                epilogue
                ENDIF
                ENDIF

.not_shift:
        ENDIF

    ; 3. Expressions (Numbers, Symbols, Math)
.expression:
    mov     rdi, rbx
    mov     rsi, r13
    call    preprocessor_putback_token

    push    qword [rel known_fwd_uses]
    mov     byte [rel expr_pcrel_ok], 1    ; ("mov eax, x - $", x elsewhere)
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_pcrel_ok], 0
    pop     r8
    cmp     r8, [rel known_fwd_uses]
    je      .not_fwd
    mov     byte [r12 + OPERAND_fwd], 1    ; (encoder.s: NASM's pass 1)
.not_fwd:
    test    rax, rax
    IF z
        ; "bar[rbx]", "4[rbx]": MASM's displacement before the brackets,
        ; which NASM takes as [bar + rbx]
        push    rdx
        push    rcx
        push    r11
        mov     rdi, rbx
        call    preprocessor_peek_token
        pop     r11
        pop     rcx
        cmp     byte [rdx + TOKEN_kind], TOK_LBRACKET
        pop     rdx
        je      .disp_before_mem
        mov     byte [r12 + OPERAND_kind], OP_IMM
        mov     [r12 + OPERAND_imm], rdx
        ; If the expression involved symbols, we mark it.
        ; rcx = forward reference (raw name), r11 = already-defined SYMBOL*.
        IF rcx, ne, 0
             mov     byte [r12 + OPERAND_kind], OP_SYMBOL
             mov     [r12 + OPERAND_sym], rcx
             mov     al, [rel expr_pcrel]
             mov     [r12 + OPERAND_pcrel], al
        ELSEIF r11, ne, 0
             ; Already-defined symbol: the value is usable as an immediate,
             ; but record the symbol so branches can still emit a relocation.
             mov     [r12 + OPERAND_sym], r11
             ENDIF
        jmp     .success
        ENDIF

    ; not an operand: the expression evaluator's code says why
    jmp     .error

.reg_or_seg:
    ; "gs:[rbx]", "fs:0x28", "es:[di]": a segment register and a colon
    ; make the operand memory with that segment (not for jmp / call,
    ; where "cs:foo" is no far pointer: NASM's error)
    ; (the register table's ids: cs ds es fs gs ss are 64-69,
    ; src/include/arch/amd64.inc)
    movzx   eax, byte [r12 + OPERAND_reg]
    sub     eax, REG_CS
    cmp     eax, 5
    ja      .is_reg
    movzx   ecx, word [r15 + INST_op_id]
    cmp     ecx, 1298                      ; JMP
    je      .is_reg
    cmp     ecx, 1059                      ; CALL
    je      .is_reg
    ; "gs:" lexes as a label: the colon is already read (far_colon)
    cmp     byte [rel far_colon], 0
    je      .seg_colon_peek
    mov     byte [rel far_colon], 0
    lea     rcx, [rel seg_prefix_bytes]
    movzx   eax, byte [rcx + rax]
    push    rax
    jmp     .seg_after_colon
.seg_colon_peek:
    push    rax
    mov     rdi, rbx
    call    preprocessor_peek_token
    pop     rax
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .is_reg
    lea     rcx, [rel seg_prefix_bytes]
    movzx   eax, byte [rcx + rax]
    push    rax
    mov     rdi, rbx
    call    preprocessor_next_token        ; the colon
.seg_after_colon:
    mov     rdi, rbx
    call    preprocessor_peek_token
    pop     rax
    mov     [r12 + OPERAND_segment], al
    mov     byte [r12 + OPERAND_reg], 0
    ; the size: the one written before it, not the segment register's
    movzx   eax, word [rel opnd_kw_size]
    mov     [r12 + OPERAND_size], al
    mov     [r12 + OPERAND_xsize], ax
    cmp     byte [rdx + TOKEN_kind], TOK_LBRACKET
    jne     .seg_open
    mov     rdi, rbx
    call    preprocessor_next_token        ; the [
    call    parser_parse_mem_operand
    check_err
    jmp     .success
.seg_open:
    mov     byte [rel mem_open], 1
    call    parser_parse_mem_operand
    mov     byte [rel mem_open], 0
    check_err
    jmp     .success
.is_reg:
    mov     byte [r12 + OPERAND_kind], OP_REG
    jmp     .success

.disp_before_mem:
    ; the displacement first, then what the brackets add to it (as the
    ; displacement of [table + rax + FIELD] is gathered)
    mov     [r12 + OPERAND_imm], rdx
    mov     qword [r12 + OPERAND_sym], 0
    test    r11, r11
    jz      .disp_sym_name
    mov     [r12 + OPERAND_sym], r11
    jmp     .disp_sym_done
.disp_sym_name:
    mov     [r12 + OPERAND_sym], rcx
.disp_sym_done:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the [
    call    parser_parse_mem_operand
    check_err
    jmp     .success

.success:
    ; "[rbx:PACKET].len", sized or not: the field after the bracket
    call    parser_typed_field
    check_err
    ; AVX-512 decorators after a register or memory operand: {k1} {z} {1to16}
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
    je      .decorated
    ; "zmm1+3": a block of four registers (v4fmaddps, NASM's rs4), the
    ; first named; "+0" as well
    cmp     byte [r12 + OPERAND_kind], OP_REG
    jne     .decorator
    cmp     word [r12 + OPERAND_xsize], 512
    jne     .decorator
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_PLUS
    jne     .decorator
    mov     rdi, rbx
    call    preprocessor_next_token        ; '+'
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     rax, EXIT_INVALID_REG
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .error
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    test    rax, rax
    mov     rax, EXIT_INVALID_REG
    jnz     .error
    test    rdx, rdx
    jz      .decorator
    cmp     rdx, 3
    jne     .error
.decorator:
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_LBRACE
    jne     .decorated
    mov     rdi, rbx
    call    preprocessor_next_token        ; consume '{'
    call    parser_parse_decorator
    check_err
    jmp     .decorator
.decorated:
    ; "to st1": marked on the register (te_classify: C_ST, te_high 2)
    cmp     byte [rel opnd_to], 0
    je      .no_to
    mov     byte [rel opnd_to], 0
    cmp     byte [r12 + OPERAND_kind], OP_REG
    jne     .no_to
    movzx   eax, byte [r12 + OPERAND_reg]
    sub     eax, 112
    cmp     eax, 7
    ja      .no_to
    mov     byte [r12 + OPERAND_is_high], 2
.no_to:
    ; "[QWORD PTR x]": the wrapping bracket's close
    cmp     byte [rel opnd_wrap], 0
    je      .unwrapped
    mov     byte [rel opnd_wrap], 0
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     rax, EXIT_INVALID_EXPR
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACKET
    jne     .error
.unwrapped:
    mov     rdx, r12
    mov     rax, OK
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_parse_reg_info]
; * Input: RSI = Name String, RDI = Table Pointer, R12 = OPERAND Pointer
; * Output: AL = Reg ID, RAX = ERR if not found
; ;
parser_parse_reg_info:
    prologue
    ; GNU's syntax: "st(1)" is st1 and "st" alone st0, as GNU as writes
    ; them in its Intel syntax
    cmp     byte [rel gas_names], 0
    je      .not_gas_st
    movzx   eax, word [rsi]
    or      eax, 0x2020
    cmp     ax, 'st'
    jne     .not_gas_st
    cmp     byte [rsi + 2], 0
    jne     .not_gas_st
    push    rdi
    mov     dword [rel gas_st_name], 'st0'
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .gas_st_named
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .gas_st_named
    mov     rdi, rbx
    call    preprocessor_next_token        ; "("
    mov     rdi, rbx
    call    preprocessor_next_token        ; N
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .gas_st_bad
    mov     rax, [rdx + TOKEN_value]
    movzx   ecx, byte [rax]
    cmp     byte [rax + 1], 0
    jne     .gas_st_bad
    sub     ecx, '0'
    cmp     ecx, 7
    ja      .gas_st_bad
    add     ecx, '0'
    mov     [rel gas_st_name + 2], cl
    mov     rdi, rbx
    call    preprocessor_next_token        ; ")"
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .gas_st_bad
.gas_st_named:
    pop     rdi
    lea     rsi, [rel gas_st_name]
    jmp     .not_gas_st
.gas_st_bad:
    pop     rdi
    mov     rax, ERR
    epilogue
.not_gas_st:
    push    rdi
    call    parser_is_register
    pop     rdi
    IF rax, e, ERR
        epilogue
        ENDIF
    
    ; RAX: bit 16 = is_high, bits 8-15 = size_in_bytes, bits 0-7 = reg_id
    mov     [r12 + OPERAND_reg], al
    
    mov     rcx, rax
    shr     rcx, 8
    and     ecx, 0x7F           ; Size in bytes
    shl     ecx, 3              ; Convert to bits
    mov     [r12 + OPERAND_size], cl
    mov     [r12 + OPERAND_xsize], cx      ; ymm/zmm: 256/512 need 16 bits
    
    shr     rax, 16
    and     al, 1
    mov     [r12 + OPERAND_is_high], al
    
    mov     rax, OK
    epilogue

;*
; * [parser_evaluate_additive]
; * Purpose: Additive level (+ -)
; ;
%define EXPR_COEFF_LIMIT (1 << 20)
%define EXPR_NONLINEAR   (1 << 40)      ; a value not linear in $
