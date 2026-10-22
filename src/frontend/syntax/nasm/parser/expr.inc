; ============================================================================
; File        : src/frontend/syntax/nasm/parser/expr.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : the expression evaluator: the precedence levels, terms and factors, values deferred to a later pass, symbol classes
; ============================================================================

parser_evaluate_additive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                ; [rsp] = the position coefficient
    mov     qword [rsp + 8], 0     ; [rsp + 8] = a label held (expr_plus_names)

    mov     rbx, rdi               ; RBX = PrepState

    mov     rdi, rbx
    call    parser_evaluate_term
    check_err
    mov     r13, rdx               ; R13 = current running total
    mov     r14, rcx               ; R14 = deferred symbol name (optional)
    mov     r15, r11               ; R15 = resolved SYMBOL* (optional)
    mov     rax, [rel expr_coeff]
    mov     [rsp], rax

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]

    IF al, e, TOK_PLUS
        mov     rdi, rbx
        call    preprocessor_next_token

        ; A register name is never a term in an expression. It appears here
        ; only in an address like [table + rcx], where it belongs to the
        ; memory operand, so stop and leave it for the caller to consume.
        mov     rdi, rbx
        call    preprocessor_peek_token
        IF byte [rdx + TOKEN_kind], e, TOK_IDENT
            mov     r12, [rdx + TOKEN_value]
            call    parser_get_arch_tables
            mov     rdi, rdx               ; register table
            mov     rsi, r12
            call    parser_is_register
            IF rax, ne, ERR
                jmp .stop
                ENDIF
            ENDIF

        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        add     r13, rdx
        jo      .overflow
        mov     rdi, [rsp]
        mov     rsi, [rel expr_coeff]
        call    expr_coeff_sum
        mov     [rsp], rax
        call    expr_plus_names            ; (one of two names not known yet)
        test    rax, rax
        jz      .plus_named
        ; "_GLOBAL_OFFSET_TABLE_ + $$ - .getgot": a label added to an
        ; address is held until a label of its section is taken away - the
        ; two a distance, a number (NASM's PIC idiom); else "label + label"
        cmp     rax, EXIT_NOT_SIMPLE
        jne     .error
        cmp     qword [rsp + 8], 0
        jne     .error
        test    rcx, rcx
        jnz     .error
        test    r11, r11
        jz      .error
        movzx   edx, word [r11 + SYMBOL_section]
        test    edx, edx
        jz      .error
        cmp     edx, 0xFF00
        jae     .error
        mov     [rsp + 8], r11
        jmp     .loop
.plus_named:
        ; "1 + label", "CONST + label": the label is the right-hand term's
        test    r14, r14
        jnz     .loop
        test    r15, r15
        jz      .plus_adopt
        cmp     word [r15 + SYMBOL_section], SHN_ABS
        jne     .loop
.plus_adopt:
        mov     rax, rcx
        or      rax, r11
        jz      .loop                      ; a number: the left one stays
        mov     r14, rcx
        mov     r15, r11
        jmp     .loop
    ELSEIF al, e, TOK_MINUS
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        mov     rsi, [rel expr_coeff]
        neg     rsi
        mov     rdi, [rsp]
        call    expr_coeff_sum
        mov     [rsp], rax

        sub     r13, rdx
        jo      .overflow

        ; the right operand a number ("label - 4", "x - CONST"): the left
        ; one's symbol stays
        test    rcx, rcx
        jnz     .minus_symbol
        test    r11, r11
        jz      .loop
        cmp     word [r11 + SYMBOL_section], SHN_ABS
        je      .loop
.minus_symbol:
        ; the label held after a "+" and one of its section: a distance
        ; (a number), the code between keeping its size
        mov     rax, [rsp + 8]
        test    rax, rax
        jz      .minus_unheld
        test    rcx, rcx
        jnz     .minus_unheld
        movzx   edx, word [rax + SYMBOL_section]
        cmp     dx, [r11 + SYMBOL_section]
        jne     .minus_unheld
        mov     qword [rsp + 8], 0
        push    rdi
        push    rsi
        mov     rsi, [rax + SYMBOL_value]
        mov     rdi, [rbx + PREP_ctx]
        mov     rdi, [rdi + ASMCTX_sections]
        mov     rdi, [rdi + rdx*8 - 8]     ; (the index is 1-based)
        mov     rdx, [r11 + SYMBOL_value]
        call    relax_freeze_range
        pop     rsi
        pop     rdi
        jmp     .loop
.minus_unheld:

        ; "later - $$", "end - start" with a label not defined yet: the
        ; distance is only known at the end. It is recorded under a name
        ; holding both labels (RELOC_OFFSET_MARK, parser_offset_name) and
        ; the relocation pass writes it in place, after jumps are
        ; shortened - so nothing has to keep its size for it.
        mov     rax, r14
        or      rax, rcx
        jnz     .offset_names
        ; "global x" before "x:": an entry with no section yet is not defined
        ; yet either
        push    rdi
        mov     rdi, r15
        call    expr_sym_class
        cmp     eax, 2
        je      .offset_undef
        mov     rdi, r11
        call    expr_sym_class
        cmp     eax, 2
        je      .offset_undef
        pop     rdi
        ; both defined: a number now - but in GNU's syntax "b - a" of code
        ; in data (or a LEB128) is worked out as GNU as does, once the jumps
        ; are relaxed: a distance too, so nothing keeps its size for it
        ; (GCC's -g: ".quad .LFE1-.LFB1", ".uleb128 .LVL3-.LVL2")
        cmp     byte [rel gas_names], 0
        je      .not_offset
        cmp     byte [rel expr_deferring], 0
        jne     .not_offset                ; (one kept, being worked out)
        mov     al, [rel expr_in_data]
        or      al, [rel expr_late_diff]
        jz      .not_offset
        test    r15, r15
        jz      .not_offset
        test    r11, r11
        jz      .not_offset
        cmp     byte [r15 + SYMBOL_kind], SYM_LABEL
        jne     .not_offset
        cmp     byte [r11 + SYMBOL_kind], SYM_LABEL
        jne     .not_offset
        movzx   eax, word [r15 + SYMBOL_section]
        cmp     ax, [r11 + SYMBOL_section]
        jne     .not_offset
        test    eax, eax
        jz      .not_offset
        cmp     eax, 0xFF00
        jae     .not_offset
        mov     rdx, [rbx + PREP_ctx]
        movzx   r8d, word [rdx + ASMCTX_seccount]
        cmp     eax, r8d
        ja      .not_offset
        mov     rdx, [rdx + ASMCTX_sections]
        mov     rdx, [rdx + rax*8 - 8]     ; the index is 1-based
        test    word [rdx + SECTION_flags], SHF_EXECINSTR
        jz      .not_offset
        jmp     .offset_names
.offset_undef:
        pop     rdi
.offset_names:
        test    r14, r14
        jz      .off_left_sym
        cmp     byte [r14], RELOC_OFFSET_MARK
        je      .not_offset                ; already a distance
        mov     rdi, r14                   ; A: not defined yet
        jmp     .off_right
.off_left_sym:
        test    r15, r15
        jz      .not_offset
        cmp     word [r15 + SYMBOL_section], SHN_ABS
        je      .not_offset
        mov     rdi, [r15 + SYMBOL_name]   ; A: defined; its value leaves
        sub     r13, [r15 + SYMBOL_value]  ; the constant part
.off_right:
        test    rcx, rcx
        jz      .off_right_sym
        cmp     byte [rcx], RELOC_OFFSET_MARK
        je      .not_offset
        mov     rsi, rcx                   ; B: not defined yet
        jmp     .off_name
.off_right_sym:
        mov     rsi, [r11 + SYMBOL_name]   ; B: defined
        add     r13, [r11 + SYMBOL_value]
.off_name:
        call    parser_offset_name
        test    rax, rax
        jnz     .error
        mov     r14, rdx
        xor     r15d, r15d
        jmp     .loop
.not_offset:
        ; a label not defined yet that cannot be a distance here ("5 - later",
        ; or one side a distance already), or "5 - label" (the label's
        ; address): worked out at the end, keeping nothing from moving
        mov     rax, r14
        or      rax, rcx
        jnz     .minus_lost
        push    rdi
        push    rsi
        mov     rdi, r15
        call    expr_sym_class
        mov     esi, eax                   ; the left one
        mov     rdi, r11
        call    expr_sym_class             ; the right one
        cmp     esi, 1
        je      .minus_known               ; "label_b - label_a"
        test    eax, eax
        jz      .minus_known               ; "5 - CONST"
        pop     rsi
        pop     rdi
        jmp     .minus_lost
.minus_known:
        pop     rsi
        pop     rdi
        jmp     .not_lost
.minus_lost:
        mov     byte [rel expr_lost], 1
        jmp     .diff_number
.not_lost:

        ; "b - a", both labels of one section: the distance is a number now,
        ; so the code between them must keep its size (a frozen range,
        ; src/optimize/jump.s). Anything else freezes the sections involved.
        test    r14, r14
        jnz     .diff_other
        test    rcx, rcx
        jnz     .diff_other
        test    r15, r15
        jz      .diff_other
        test    r11, r11
        jz      .diff_other
        movzx   eax, word [r15 + SYMBOL_section]
        cmp     ax, [r11 + SYMBOL_section]
        jne     .diff_other
        test    eax, eax
        jz      .diff_other                ; not defined
        cmp     eax, 0xFF00
        jae     .diff_other                ; SHN_ABS, SHN_COMMON ...
        mov     rdx, [rbx + PREP_ctx]
        movzx   r8d, word [rdx + ASMCTX_seccount]
        cmp     eax, r8d
        ja      .diff_other
        mov     rdx, [rdx + ASMCTX_sections]
        mov     rdi, [rdx + rax*8 - 8]     ; the index is 1-based
        mov     rsi, [r15 + SYMBOL_value]
        mov     rdx, [r11 + SYMBOL_value]
        ; in a preprocessor expression ("%if $ - $$ > 510"): the distance
        ; with the jumps between shortened, as NASM's last pass gives it,
        ; and nothing is kept from moving (src/core/known.s)
        cmp     byte [rel expr_pp], 0
        je      .diff_keep_range
        extern  known_pp_diff
        call    known_pp_diff
        test    eax, eax
        jz      .diff_keep_range
        add     r13, rdx                   ; (that distance less this one)
        jmp     .diff_number
.diff_keep_range:
        call    relax_freeze_range
        extern  known_note_diff
        call    known_note_diff            ; (src/core/known.s: "len equ $ - msg")
        jmp     .diff_number
.diff_other:
        ; labels of two sections, or an extern ("dd func - $", "dd e - x"):
        ; with the right one in the section being written, a PC-relative
        ; reference to the left one, as NASM makes it. Where the writer
        ; takes one (expr_pcrel_ok: data, an immediate) the left one's name
        ; comes back, the rest of the value its addend, and expr_pcrel says
        ; so; anywhere else no relocation can say it: NASM's "not simple or
        ; relocatable". It was the difference of the two offsets, silently.
        ; A flat binary or an executable has its sections placed: worked
        ; out at the end. (Both in one section: a number, above.)
        test    r14, r14
        jnz     .diff_freeze
        test    rcx, rcx
        jnz     .diff_freeze
        test    r15, r15
        jz      .diff_freeze
        test    r11, r11
        jz      .diff_freeze
        push    rdi
        push    rsi
        mov     rdi, r15
        call    expr_sym_class
        mov     r8d, eax
        mov     rdi, r11
        call    expr_sym_class
        cmp     r8d, 1
        jne     .diff_back                     ; (a number on either side)
        cmp     eax, 1
        jne     .diff_back
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_fmt], FMT_BIN
        je      .diff_xsec
        cmp     byte [rax + ASMCTX_standalone], 0
        jne     .diff_xsec
        mov     r8, [rax + ASMCTX_curr_sec]
        test    r8, r8
        jz      .diff_not_simple
        movzx   eax, word [r11 + SYMBOL_section]
        cmp     ax, [r8 + SECTION_index]
        jne     .diff_not_simple
        cmp     byte [rel expr_pcrel_ok], 0
        je      .diff_not_simple
        ; the distance from the right one to here is in the addend: the
        ; code between keeps its size
        mov     rdi, r8
        mov     rsi, [r11 + SYMBOL_value]
        mov     rdx, [r8 + SECTION_size]
        call    relax_freeze_range
        pop     rsi
        pop     rdi
        mov     byte [rel expr_pcrel], 1
        sub     r13, [r15 + SYMBOL_value]      ; (an extern's is 0)
        mov     r14, [r15 + SYMBOL_name]
        xor     r15d, r15d
        jmp     .loop
.diff_xsec:
        mov     byte [rel expr_xsec], 1        ; (no RIP-relative address)
.diff_lost:
        pop     rsi
        pop     rdi
        jmp     .minus_lost
.diff_not_simple:
        pop     rsi
        pop     rdi
        mov     rax, EXIT_NOT_SIMPLE
        jmp     .error
.diff_back:
        pop     rsi
        pop     rdi
.diff_freeze:
        push    rdi
        push    rsi
        mov     rdi, r11
        mov     rsi, rcx
        call    relax_freeze_symref
        mov     rdi, r15
        mov     rsi, r14
        call    relax_freeze_symref
        pop     rsi
        pop     rdi
.diff_number:
        ; "label_b - label_a" is an absolute constant: the two references
        ; cancel out. Carrying a symbol onward would make the encoder emit a
        ; relocation that overwrites the difference we just computed.
        xor     r14, r14
        xor     r15, r15
        jmp     .loop
        ENDIF

.stop:
    ; a label still held: two addresses added ("label + label")
    mov     rax, EXIT_NOT_SIMPLE
    cmp     qword [rsp + 8], 0
    jne     .error
    mov     rdx, r13
    xor     rax, rax

.done:
.error:
    mov     rcx, [rsp]
    mov     [rel expr_coeff], rcx  ; how the value moves with $
    mov     rcx, r14               ; carry the symbol info to the caller
    mov     r11, r15
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.overflow:
    mov     rax, EXIT_IMM_RANGE
    jmp     .error

; expr_plus_names: a sum of two names (r14 / r15 the left one's, rcx / r11
; the right one's). Two labels are not an address (NASM: "not simple"); one
; not defined yet with another name: only one name can go on, so the sum is
; worked out at the end (expr_lost).
; Output: rax = OK or EXIT_NOT_SIMPLE. Preserves the others.
expr_plus_names:
    push    rdi
    push    rsi
    ; the left one: esi = 0 none, 1 an address, 2 not known yet
    xor     esi, esi
    test    r14, r14
    jz      .left_sym
    mov     esi, 2
    jmp     .right
.left_sym:
    mov     rdi, r15
    call    expr_sym_class
    mov     esi, eax
.right:
    test    rcx, rcx
    jz      .right_sym
    mov     eax, 2
    jmp     .both
.right_sym:
    mov     rdi, r11
    call    expr_sym_class
.both:
    test    esi, esi
    jz      .ok
    test    eax, eax
    jz      .ok
    cmp     esi, 1
    jne     .lost
    cmp     eax, 1
    jne     .lost
    mov     eax, EXIT_NOT_SIMPLE           ; two addresses
    jmp     .ret
.lost:
    mov     byte [rel expr_lost], 1
.ok:
    xor     eax, eax
.ret:
    pop     rsi
    pop     rdi
    ret

;*
; * [expr_coeff_sum]
; * Purpose: Adds two position coefficients (expr_coeff): how much a value
; *   grows when $ grows by one. Past +-2^20 a value is not linear in $
; *   (EXPR_NONLINEAR), and stays so.
; * Input  : RDI, RSI. Output: RAX. Clobbers nothing else.
; ;
expr_coeff_sum:
    mov     rax, rdi
    add     rax, EXPR_COEFF_LIMIT
    cmp     rax, 2 * EXPR_COEFF_LIMIT
    ja      .nonlinear
    mov     rax, rsi
    add     rax, EXPR_COEFF_LIMIT
    cmp     rax, 2 * EXPR_COEFF_LIMIT
    ja      .nonlinear
    lea     rax, [rdi + rsi]
    ret
.nonlinear:
    mov     rax, EXPR_NONLINEAR
    ret

;*
; * [expr_combine]
; * Purpose: Two operands joined by an operator other than + and - (* / %
; *   << >> & | ^ comparisons): the result is a plain number. A label in
; *   either is a position used as a number, which freezes its section;
; *   the coefficient is 0, or EXPR_NONLINEAR when either depended on $.
; *   A label not defined yet in either: the value is worked out at the end
; *   (expr_lost, parser_evaluate_expression).
; * Input  : RDI = left SYMBOL* (or 0), RSI = left deferred name (or 0),
; *          R8 = left coefficient; right: R11, RCX, expr_coeff
; * Output : expr_coeff, RAX = the new coefficient. Preserves the others.
; ;
expr_combine:
    test    rsi, rsi
    jnz     .lost
    test    rcx, rcx
    jnz     .lost
    push    rax
    call    expr_sym_class                 ; (rdi: the left SYMBOL*)
    cmp     eax, 2
    je      .lost_pop
    push    rdi
    mov     rdi, r11
    call    expr_sym_class
    pop     rdi
    cmp     eax, 2
    je      .lost_pop
    pop     rax
    jmp     .freeze
.lost_pop:
    pop     rax
.lost:
    mov     byte [rel expr_lost], 1
.freeze:
    ; worked out at the end, an expression keeps nothing from moving
    cmp     byte [rel expr_lost], 0
    jne     .coeff
    push    r8
    push    rdi
    push    rsi
    call    relax_freeze_symref
    mov     rdi, r11
    mov     rsi, rcx
    call    relax_freeze_symref
    pop     rsi
    pop     rdi
    pop     r8
.coeff:
    xor     eax, eax
    test    r8, r8
    jnz     .nonlinear
    cmp     qword [rel expr_coeff], 0
    je      .set
.nonlinear:
    mov     rax, EXPR_NONLINEAR
.set:
    mov     [rel expr_coeff], rax
    ret

; expr_unary_lost: - ~ ! of a label not defined yet (rcx, or r11 an entry
; with no section yet), or - of a label (its address, known at the end):
; worked out at the end (expr_lost). Preserves every register.
expr_unary_lost:
    test    rcx, rcx
    jnz     .lost
    push    rax
    push    rdi
    mov     rdi, r11
    call    expr_sym_class
    pop     rdi
    test    eax, eax
    pop     rax
    jz      .ret
.lost:
    mov     byte [rel expr_lost], 1
.ret:
    ret

; expr_coeff_taint: after ~ or !, a value that depended on $ no longer
; does so linearly. Preserves every register.
expr_coeff_taint:
    cmp     qword [rel expr_coeff], 0
    je      .ret
    push    rax
    mov     rax, EXPR_NONLINEAR
    mov     [rel expr_coeff], rax
    pop     rax
.ret:
    ret

;*
; * [parser_disp_size_word]
; * Purpose: byte / word / dword / qword inside brackets, in any case.
; * Input  : RDI = word
; * Output : EAX = 8, 16, 32, 64, or 0 when it is none of them
; ;
parser_disp_size_word:
    push    r12
    mov     r12, rdi
    lea     rsi, [rel str_byte]
    call    str_cmp_kw
    mov     edx, 8
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_word]
    call    str_cmp_kw
    mov     edx, 16
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_dword]
    call    str_cmp_kw
    mov     edx, 32
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_qword]
    call    str_cmp_kw
    mov     edx, 64
    test    rax, rax
    jz      .hit
    xor     edx, edx
.hit:
    mov     eax, edx
    pop     r12
    ret

;*
; * [parser_offset_name]
; * Purpose: The name an "A - B" distance is recorded under when A or B is
; *   not defined yet: RELOC_OFFSET_MARK, A, RELOC_OFFSET_MARK, B (reloc.s
; *   resolves it once both are).
; * Input  : RDI = A's name, RSI = B's name, RBX = PrepState
; * Output : RAX = OK or error, RDX = the marked name
; ;
parser_offset_name:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r14, rsi
    call    str_len
    mov     r13, rax
    mov     rdi, r14
    call    str_len
    mov     r15, rax
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r13 + r15 + 3]
    call    arena_alloc                    ; zeroed: the NUL is there
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     byte [rdi], RELOC_OFFSET_MARK
    inc     rdi
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    mov     byte [rdi], RELOC_OFFSET_MARK
    inc     rdi
    mov     rsi, r14
    mov     rcx, r15
    rep movsb
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_evaluate_expression]
; * Purpose: Evaluates an expression (parser_eval_expr_body). At the
; *   outermost level its tokens are recorded. When a label not defined yet
; *   went into arithmetic ("dd (end - start) / 4", "-later"), utasm, which
; *   reads the source once, cannot know the value here: the expression
; *   comes back as a deferred name (RELOC_EXPR_MARK) - a forward reference
; *   to every caller, which gives it its full width and a relocation - and
; *   the relocation pass works it out once every label is placed
; *   (parser_deferred_value). It was written as 0 before.
; * Input  : RDI = PrepState
; * Output : RAX = OK or an error, RDX = value, RCX = deferred name (0 if
; *          none), R11 = resolved SYMBOL* (0 if none)
; ;
global parser_evaluate_pp
; parser_evaluate_pp: parser_evaluate_expression for the preprocessor (%if,
; %assign, %rep ...), whose value is taken before the code is laid out: a
; "b - a" over code that can shrink comes from the layout (known_pp_diff)
parser_evaluate_pp:
    inc     byte [rel expr_pp]
    call    parser_evaluate_expression
    dec     byte [rel expr_pp]
    ret

global parser_evaluate_expression
parser_evaluate_expression:
    inc     dword [rel expr_level]
    cmp     dword [rel expr_level], 1
    jne     .inner
    mov     dword [rel expr_terms], 0      ; (a deferred one's count too)
    cmp     byte [rel expr_deferring], 0
    jne     .inner                         ; (one kept, being worked out)
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     byte [rel expr_lost], 0
    mov     byte [rel expr_xsec], 0
    mov     byte [rel expr_pcrel], 0
    mov     qword [rel expr_last_record], 0
    mov     qword [rel expr_undef_uses], 0
    extern  prep_rec_begin
    extern  prep_rec_end
    extern  prep_rec_drop
    call    prep_rec_begin
    test    rax, rax
    jnz     .top_ret
    mov     rdi, rbx
    call    parser_eval_expr_body
    mov     r12, rax
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r11
    call    prep_rec_end                   ; rdx = tokens, rcx = count
    test    r12, r12
    jnz     .top_drop
    cmp     byte [rel expr_lost], 0
    jne     .top_lost
    ; "end - start" of labels not defined yet, kept as a distance
    ; (RELOC_OFFSET_MARK): a record too, for a second pass (src/core/known.s)
    test    r14, r14
    jz      .top_named
    cmp     byte [r14], RELOC_OFFSET_MARK
    jne     .top_plain
    test    eax, eax
    jnz     .top_drop
    push    r14
    mov     rdi, rbx
    mov     rsi, rdx
    mov     rdx, rcx
    call    parser_defer_record
    pop     rcx                            ; the distance's name
    test    rax, rax
    jnz     .top_out                       ; (as it was: no record)
    mov     [rel expr_last_record], rdx
    mov     r14, rcx
    cmp     byte [rel known_active], 0
    je      .top_out
    cmp     byte [rdx + DEFER_DATA], 0
    jne     .top_out
    mov     rsi, [rdx + DEFER_KEY]
    test    rsi, rsi
    jz      .top_out
    push    rdx
    call    known_lookup
    pop     rdi                            ; the record
    test    eax, eax
    jz      .top_out
    mov     r13, rdx                       ; the value, a number now
    mov     rsi, rdx
    call    known_note_verify
    xor     r14d, r14d
    xor     r15d, r15d
    jmp     .top_out
.top_named:
    ; a name referred to before but not defined yet went in as 0 ("a equ
    ; b" with b used above): an equ keeps that too, as below
    cmp     qword [rel expr_undef_uses], 0
    jne     .top_plain
.top_quiet:
    ; every name known: an equ asks for a record all the same, not handed
    ; on (parser_handle_equ hands it on when the value measures code that
    ; jumps may shorten)
    cmp     byte [rel expr_keep_quiet], 0
    je      .top_drop
    test    eax, eax
    jnz     .top_drop
    movzx   r8d, byte [rel expr_in_data]
    push    r8
    mov     byte [rel expr_in_data], 1     ; (a record not handed on)
    mov     rdi, rbx
    mov     rsi, rdx
    mov     rdx, rcx
    call    parser_defer_record
    pop     r8
    mov     [rel expr_in_data], r8b
    test    rax, rax
    jnz     .top_quiet_none
    mov     [rel expr_last_record], rdx
.top_quiet_none:
    xor     eax, eax
    jmp     .top_out
.top_plain:
    ; a name not defined yet, alone: an equ keeps it as well (its value is
    ; worked out once the code is laid out: parser_late_equs)
    cmp     byte [rel expr_keep_forward], 0
    je      .top_drop
    test    eax, eax
    jnz     .top_drop
    jmp     .top_keep
.top_lost:
    test    eax, eax
    jnz     .top_too_long
.top_keep:
    ; kept: a record of its own, under the deferred name
    mov     rdi, rbx
    mov     rsi, rdx
    mov     rdx, rcx
    call    parser_defer_record
    test    rax, rax
    jnz     .top_fail
    mov     r14, rdx                       ; the deferred name
    mov     [rel expr_last_record], rdx
    xor     r13d, r13d
    xor     r15d, r15d
    ; pass 2: the value pass 1 found for an instruction's (src/core/known.s) -
    ; a number now, checked once the code is laid out (known_verify)
    cmp     byte [rel known_active], 0
    je      .top_out
    cmp     byte [r14 + DEFER_DATA], 0
    jne     .top_out
    mov     rsi, [r14 + DEFER_KEY]
    test    rsi, rsi
    jz      .top_out
    call    known_lookup
    test    eax, eax
    jz      .top_out
    mov     r13, rdx                       ; the value
    mov     rdi, r14
    mov     rsi, rdx
    call    known_note_verify
    xor     r14d, r14d                     ; no deferred name
    jmp     .top_out
.top_too_long:
    mov     r12, EXIT_EXPR_TOO_DEEP        ; (the capture area could not hold it)
    jmp     .top_drop
.top_fail:
    mov     r12, rax
.top_drop:
    call    prep_rec_drop
.top_out:
    mov     rax, r12
    mov     rdx, r13
    mov     rcx, r14
    mov     r11, r15
.top_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    dec     dword [rel expr_level]
    ret
.inner:
    call    parser_eval_expr_body
    dec     dword [rel expr_level]
    ret

;*
; * [parser_defer_record]
; * Purpose: The record a kept expression is known by: its first byte is
; *   RELOC_EXPR_MARK (as a name: "\x1e"), then its text (for messages) and
; *   its tokens, ended by a newline, out of the capture area.
; *     +0 RELOC_EXPR_MARK, 0   +8 text   +16 tokens   +24 count (dword)
; * Input  : RDI = PrepState, RSI = the recorded tokens, RDX = how many
; * Output : RAX = OK or an error, RDX = the record
; ;
parser_defer_record:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    extern  prep_tokens_text
    call    prep_tokens_text
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; the text
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    extern  prep_cap_take
    call    prep_cap_take                  ; (one slot more: the newline)
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    imul    rax, r13, TOKEN_SIZE
    lea     rdi, [r12 + rax]               ; slot N: the last token, as a newline
    lea     rsi, [rdi - TOKEN_SIZE]
    copy_token
    mov     byte [rdi - TOKEN_SIZE + TOKEN_kind], TOK_NEWLINE
    mov     qword [rdi - TOKEN_SIZE + TOKEN_value], 0
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, DEFER_SIZE
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     byte [rdx], RELOC_EXPR_MARK
    mov     [rdx + 8], r14
    mov     [rdx + 16], r12
    lea     eax, [r13d + 1]
    mov     [rdx + 24], eax
    ; its name across the passes (src/core/known.s), and pass 1 hands an
    ; instruction's on: a second pass can give it its short form
    mov     r12, rdx
    mov     rdi, r14
    extern  error_loc_line
    mov     esi, [rel error_loc_line]
    extern  known_defer_key
    call    known_defer_key
    mov     [r12 + DEFER_KEY], rax
    movzx   eax, byte [rel expr_in_data]
    mov     [r12 + DEFER_DATA], al
    test    eax, eax
    jnz     .noted
    cmp     qword [r12 + DEFER_KEY], 0
    je      .noted
    mov     rdi, r12
    extern  known_note_defer
    call    known_note_defer
.noted:
    mov     rdx, r12
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [parser_deferred_value]
; * Purpose: The value of an expression parser_evaluate_expression kept,
; *   now that every label is placed: its tokens are read again, through an
; *   expansion of their own, with no macro expanded and nothing recorded.
; * Input  : RDI = the record
; * Output : RAX = OK or an error, RDX = the value, R11 = a SYMBOL* still in
; *          it (an address, not a number, in an object file)
; ;
global parser_deferred_value
parser_deferred_value:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, TOKEN_SIZE + 16           ; the peek slot set aside, its flag
    mov     r12, rdi
    extern  global_prep
    lea     rbx, [rel global_prep]
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    mov     [rsp + TOKEN_SIZE + 8], rax    ; the expansions there are now
    ; the token waiting in the peek slot (the end of the file) kept aside
    mov     al, [rbx + PREP_has_peek]
    mov     [rsp + TOKEN_SIZE], al
    lea     rsi, [rbx + PREP_peek]
    mov     rdi, rsp
    copy_token
    mov     byte [rbx + PREP_has_peek], FALSE
    ; an anonymous macro holding the tokens, expanded once
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .restore
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_TIMES
    mov     rax, [r12 + 16]
    mov     [rdx + MACRO_tokens], rax
    mov     eax, [r12 + 24]
    mov     [rdx + MACRO_ntokens], eax
    mov     rdi, rbx
    mov     rsi, rdx
    extern  prep_expand_start
    call    prep_expand_start
    test    rax, rax
    jnz     .restore
    mov     byte [rel expr_deferring], 1
    extern  prep_noexpand
    mov     byte [rel prep_noexpand], 1
    mov     qword [rel expr_undef_uses], 0
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel prep_noexpand], 0
    mov     byte [rel expr_deferring], 0
    mov     r13, rax
    mov     r14, rdx
    mov     r15, r11
    test    rax, rax
    jnz     .drain
    ; a name still not defined: the error an undefined symbol gets
    test    rcx, rcx
    jz      .all_defined
    mov     rdi, rcx
    call    error_set_subject
    mov     r13, EXIT_UNDEF_SYMBOL
    jmp     .drain
.all_defined:
    ; one referred to before but never defined went into arithmetic as 0
    ; ("dd 2 * nothere"): the same error
    cmp     qword [rel expr_undef_uses], 0
    je      .ends
    mov     rdi, [rel expr_undef_name]
    call    error_set_subject
    mov     r13, EXIT_UNDEF_SYMBOL
    jmp     .drain
.ends:
    ; the whole of it read: the newline next
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .drain
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .drain
    mov     r13, EXIT_INVALID_EXPR
.drain:
    ; the expansion done with, whatever was left of it
    mov     byte [rbx + PREP_has_peek], FALSE
.pop:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    cmp     rax, [rsp + TOKEN_SIZE + 8]
    je      .popped
    test    rax, rax
    jz      .popped
    mov     rdi, rbx
    extern  prep_expand_pop
    call    prep_expand_pop
    jmp     .pop
.popped:
    mov     rax, r13
    mov     rdx, r14
    mov     r11, r15
.restore:
    push    rax
    push    rdx
    lea     rsi, [rsp + 16]
    lea     rdi, [rbx + PREP_peek]
    copy_token
    mov     cl, [rsp + 16 + TOKEN_SIZE]
    mov     [rbx + PREP_has_peek], cl
    pop     rdx
    pop     rax
    add     rsp, TOKEN_SIZE + 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [parser_eval_expr_body]
; * Purpose: An expression: the binary levels (parser_eval_level), then
; *   cond ? a : b.
; ;
parser_eval_expr_body:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r10, [rbx + PREP_ctx]
    inc     dword [r10 + ASMCTX_expr_depth]
    cmp     dword [r10 + ASMCTX_expr_depth], EXPR_MAX_DEPTH
    jg      .too_deep
    mov     rdi, rbx
    xor     esi, esi
    call    parser_eval_level
    mov     r10, [rbx + PREP_ctx]
    dec     dword [r10 + ASMCTX_expr_depth]
    check_err_to .done
    mov     r13, rdx               ; R13 = accumulated value
    mov     r12, rcx               ; R12 = deferred symbol name (optional)
    mov     r14, r11               ; R14 = resolved SYMBOL* (optional)

    ; "sym wrt ..plt" (..gotpcrel, ..got, ..gotoff, ..tlsie, ..sym): the
    ; relocation the reference gets
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ternary
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_wrt]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ternary
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    ; "..imagebase" (-f win64): the address less the image's base
    push    qword [rdx + TOKEN_value]
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_imagebase]
    call    str_cmp
    pop     rdi
    test    rax, rax
    jnz     .wrt_table
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .wrt_unknown
    mov     byte [rel reloc_wrt], WRT_IMAGEBASE
    jmp     .ternary
.wrt_table:
    push    rdi
    lea     rsi, [rel wrt_words]
    call    parser_word_index
    pop     rdi
    test    eax, eax
    jz      .wrt_unknown
    imul    eax, eax, 12
    lea     rcx, [rel wrt_words]
    movzx   eax, byte [rcx + rax - 1]      ; the row's WRT_*
    mov     [rel reloc_wrt], al
    jmp     .ternary
.wrt_unknown:
    ; "wrt ..name" with no such special symbol (..imagebase outside
    ; -f win64): NASM's "symbol `..name' not defined"
    test    rdi, rdi
    jz      .wrt_bad
    cmp     word [rdi], '..'
    jne     .wrt_bad
    call    error_set_subject
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .done
.wrt_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .done
.too_deep:
    dec     dword [r10 + ASMCTX_expr_depth]
    mov     rax, EXIT_EXPR_TOO_DEEP
    jmp     .done
.ternary:


    ; cond ? a : b, the lowest precedence as in NASM
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_QUESTION
    jne     .no_ternary
    mov     rdi, rbx
    call    preprocessor_next_token
    test    r12, r12
    jnz     .cond_lost
    mov     rdi, r14
    call    expr_sym_class
    cmp     eax, 2
    je      .cond_lost
    test    eax, eax
    jz      .cond_known
    mov     rax, EXIT_NONSCALAR_COND       ; NASM: "label ? a : b"
    jmp     .done
.cond_lost:
    mov     byte [rel expr_lost], 1        ; a condition not known yet
.cond_known:
    mov     rdi, rbx
    call    parser_evaluate_expression     ; the "then" value
    check_err_to .done
    push    rdx
    push    rcx
    push    r11
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .ternary_bad
    mov     rdi, rbx
    call    parser_evaluate_expression     ; the "else" value
    test    rax, rax
    jnz     .ternary_err
    test    r13, r13
    jz      .ternary_else
    pop     r11
    pop     rcx
    pop     rdx
    xor     rax, rax
    jmp     .done
.ternary_else:
    add     rsp, 24
    xor     rax, rax
    jmp     .done
.ternary_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN     ; "?" without its ":"
.ternary_err:
    add     rsp, 24
    jmp     .done

.no_ternary:
    mov     rdx, r13
    mov     rcx, r12
    mov     r11, r14
    xor     rax, rax

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

%define EVAL_LAST_LEVEL 7
%define EOP_LOR   1
%define EOP_LXOR  2
%define EOP_LAND  3
%define EOP_EQ    4
%define EOP_NE    5
%define EOP_LT    6
%define EOP_LE    7
%define EOP_GT    8
%define EOP_GE    9
%define EOP_CMP3  10
%define EOP_OR    11
%define EOP_XOR   12
%define EOP_AND   13
%define EOP_SHL   14
%define EOP_SHR   15
%define EOP_SAR   16
%define EXP_MUL   17              ; (expr_scalar) * , / // % %% , ~ , !
%define EXP_DIV   18
%define EXP_NOT   19
%define EXP_LNOT  20
%define MEM_SCALED_MAX 4          ; "4*rcx" registers in one memory operand

;*
; * [expr_sym_class]
; * Purpose: What a resolved symbol is to an operator, as NASM sees it.
; * Input  : RDI = SYMBOL* or 0
; * Output : EAX = 0 a number (none, a constant), 1 an address (a label,
; *          data, an extern - not a scalar), 2 not defined yet (an entry
; *          with no section yet, "global x" before "x:")
; * Preserves the others.
; ;
global expr_sym_class
expr_sym_class:
    xor     eax, eax
    test    rdi, rdi
    jz      .ret
    push    rcx
    movzx   ecx, byte [rdi + SYMBOL_kind]
    cmp     ecx, SYM_EXTERN
    je      .address
    cmp     ecx, SYM_COMMON
    je      .address
    ; the kinds a label has (an entry made before its definition: unknown)
    cmp     ecx, SYM_UNKNOWN
    je      .label
    cmp     ecx, SYM_LABEL
    je      .label
    cmp     ecx, SYM_DATA
    je      .label
    cmp     ecx, SYM_FORWARD
    je      .label
    cmp     ecx, SYM_PROC
    je      .label
    cmp     ecx, SYM_LOCAL_LABEL
    je      .label
    jmp     .out                           ; a constant, %assign, equ, field
.label:
    movzx   ecx, word [rdi + SYMBOL_section]
    cmp     ecx, SHN_ABS
    je      .out                           ; (an absolute one is a number)
    mov     eax, 2
    test    ecx, ecx
    jz      .out                           ; no section yet
.address:
    mov     eax, 1
.out:
    pop     rcx
.ret:
    ret

; expr_deferred_addr: rdx = the value of label r15; when a kept expression
; is worked out in a flat binary or an executable, the label's address:
; its section's address added (sections are placed by then). Preserves the
; others.
expr_deferred_addr:
    cmp     byte [rel expr_deferring], 0
    je      .ret
    push    rax
    push    rcx
    extern  global_ctx
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    je      .placed
    cmp     byte [rax + ASMCTX_standalone], 0
    je      .out
.placed:
    movzx   ecx, word [r15 + SYMBOL_section]
    test    ecx, ecx
    jz      .out
    cmp     ecx, 0xFF00
    jae     .out
    cmp     cx, [rax + ASMCTX_seccount]
    ja      .out
    mov     rax, [rax + ASMCTX_sections]
    mov     rax, [rax + rcx * 8 - 8]
    test    rax, rax
    jz      .out
    add     rdx, [rax + SECTION_addr]
.out:
    pop     rcx
    pop     rax
.ret:
    ret

;*
; * [expr_scalar]
; * Purpose: NASM's rule for an operator other than + and -: a label is an
; *   address, not a scalar. Its error, or 0.
; * Input  : EDI = what the operator is: EOP_* (parser_eval_level), or
; *          EXP_MUL / EXP_DIV (* and / // % %%), EXP_NOT / EXP_LNOT (~ !);
; *          RSI = the left operand's SYMBOL* (0 for a unary one), R11 = the
; *          right one's
; * Output : RAX = OK or the error (its subject the operator's text)
; * Preserves the others.
; ;
expr_scalar:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     edx, edi                       ; the operator
    mov     rdi, rsi
    call    expr_sym_class
    mov     ecx, eax                       ; left: 1 an address
    mov     rdi, r11
    call    expr_sym_class                 ; right
    cmp     ecx, 2
    je      .ok                            ; (not defined yet: at the end)
    cmp     eax, 2
    je      .ok
    cmp     ecx, 1
    je      .some
    cmp     eax, 1
    jne     .ok
.some:
    ; comparisons: of two labels in one section, the distance (a scalar)
    cmp     edx, EOP_EQ
    jb      .not_cmp
    cmp     edx, EOP_CMP3
    ja      .not_cmp
    cmp     ecx, eax
    jne     .cmp_bad
    movzx   eax, word [rsi + SYMBOL_section]
    cmp     ax, [r11 + SYMBOL_section]
    je      .ok
.cmp_bad:
    lea     rcx, [rel eop_texts]
    mov     rdi, [rcx + rdx * 8]
    call    error_set_subject
    mov     eax, EXIT_NONSCALAR_CMP
    jmp     .ret
.not_cmp:
    mov     eax, EXIT_NOT_SIMPLE
    cmp     edx, EXP_MUL
    je      .ret
    mov     eax, EXIT_NONSCALAR_DIV
    cmp     edx, EXP_DIV
    je      .ret
    cmp     edx, EOP_SHL
    jb      .op_text
    cmp     edx, EOP_SAR
    ja      .op_text
    mov     eax, EXIT_NONSCALAR_SHIFT      ; << >> >>> <<<
    jmp     .ret
.op_text:
    lea     rcx, [rel eop_texts]
    mov     rdi, [rcx + rdx * 8]
    call    error_set_subject
    mov     eax, EXIT_NONSCALAR_OP
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret


;*
; * [parser_eval_level]
; * Purpose: The binary operators of NASM's precedence from a level up,
; *   lowest first:
; *     0 ||    1 ^^    2 &&    3 = == != <> < <= > >= <=>
; *     4 |     5 ^     6 &     7 << >> <<< >>>
; *   then + - (parser_evaluate_additive), * / % %% (parser_evaluate_term)
; *   and the unary operators (parser_evaluate_factor). Left-associative.
; *   By precedence climbing: the operand + - reads, then each operator of
; *   the level or above with its right side read from the level above
; *   the operator's (one frame and one table look-up a token, not one a
; *   level). A value that went through an operator here is a plain
; *   number; one that did not keeps its symbol for the caller.
; * Input  : RDI = PrepState, ESI = level
; * Output : RAX = OK or an error, RDX = value, RCX / R11 = symbol info
; ;
parser_eval_level:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32                ; [rsp] = level, [rsp + 8] = SYMBOL*,
                                   ; [rsp + 16] = position coefficient
    mov     rbx, rdi
    mov     eax, esi
    mov     [rsp], rax
    cmp     byte [rel eval_ops_ready], 0
    jne     .ready
    call    eval_ops_build
.ready:
    mov     rdi, rbx
    call    parser_evaluate_additive
    test    rax, rax
    jnz     .ret
    mov     r12, rdx               ; running value
    mov     r13, rcx               ; deferred symbol name
    mov     [rsp + 8], r11         ; resolved SYMBOL*
    mov     r8, [rel expr_coeff]
    mov     [rsp + 16], r8
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    lea     r8, [rel eval_op_by_kind]
    movzx   ecx, byte [r8 + rax * 2]       ; its level + 1 (0: no operator)
    test    ecx, ecx
    jz      .no_op
    dec     ecx
    cmp     rcx, [rsp]
    jb      .no_op                         ; (a lower level's: the caller's)
    mov     [rsp + 24], rcx
    movzx   r15d, byte [r8 + rax * 2 + 1]  ; the operation
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    mov     rsi, [rsp + 24]
    call    parser_eval_next               ; its right side: the level above
    test    rax, rax
    jnz     .ret
    ; NASM: a label is an address, not a scalar, for these operators
    mov     edi, r15d
    mov     rsi, [rsp + 8]
    call    expr_scalar
    test    rax, rax
    jnz     .ret
    ; a plain number now; a label in it was a position used as a number
    mov     r8, [rsp + 16]
    mov     rdi, [rsp + 8]
    mov     rsi, r13
    call    expr_combine
    mov     [rsp + 16], rax
    xor     eax, eax
    xor     ecx, ecx
    cmp     r15d, EOP_LOR
    je      .lor
    cmp     r15d, EOP_LXOR
    je      .lxor
    cmp     r15d, EOP_LAND
    je      .land
    cmp     r15d, EOP_EQ
    je      .eq
    cmp     r15d, EOP_NE
    je      .ne
    cmp     r15d, EOP_LT
    je      .lt
    cmp     r15d, EOP_LE
    je      .le
    cmp     r15d, EOP_GT
    je      .gt
    cmp     r15d, EOP_GE
    je      .ge
    cmp     r15d, EOP_CMP3
    je      .cmp3
    cmp     r15d, EOP_OR
    je      .bor
    cmp     r15d, EOP_XOR
    je      .bxor
    cmp     r15d, EOP_AND
    je      .band
    mov     rcx, rdx
    and     ecx, 63                ; shift count
    cmp     r15d, EOP_SHL
    je      .shl
    cmp     r15d, EOP_SHR
    je      .shr
    sar     r12, cl                ; EOP_SAR
    jmp     .applied
.lor:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    or      al, cl
    jmp     .bool
.lxor:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    xor     al, cl
    jmp     .bool
.land:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    and     al, cl
    jmp     .bool
.eq:
    cmp     r12, rdx
    sete    al
    jmp     .bool
.ne:
    cmp     r12, rdx
    setne   al
    jmp     .bool
.lt:
    cmp     r12, rdx
    setl    al
    jmp     .bool
.le:
    cmp     r12, rdx
    setle   al
    jmp     .bool
.gt:
    cmp     r12, rdx
    setg    al
    jmp     .bool
.ge:
    cmp     r12, rdx
    setge   al
    jmp     .bool
.cmp3:
    cmp     r12, rdx
    setg    al
    setl    cl
    sub     al, cl                 ; -1, 0 or 1
    movsx   r12, al
    jmp     .applied
.bool:
    movzx   r12d, al
    jmp     .applied
.bor:
    or      r12, rdx
    jmp     .applied
.bxor:
    xor     r12, rdx
    jmp     .applied
.band:
    and     r12, rdx
    jmp     .applied
.shl:
    shl     r12, cl
    jmp     .applied
.shr:
    shr     r12, cl
.applied:
    xor     r13d, r13d             ; a plain number now
    mov     qword [rsp + 8], 0
    jmp     .loop
.no_op:
    mov     rdx, r12
    mov     rcx, r13
    mov     r11, [rsp + 8]
    mov     r8, [rsp + 16]
    mov     [rel expr_coeff], r8
    xor     eax, eax
.ret:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; The level above ESI: the next binary level, or + - after the last one.
parser_eval_next:
    cmp     esi, EVAL_LAST_LEVEL
    jae     parser_evaluate_additive
    inc     esi
    jmp     parser_eval_level

; eval_op_by_kind from eval_level_ops: a token kind's (level + 1, operation)
eval_ops_build:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    lea     rsi, [rel eval_level_ops]
    lea     rdx, [rel eval_op_by_kind]
    xor     ecx, ecx                       ; the level
.level:
    mov     rax, rcx
    shl     rax, 4
    add     rax, rsi
.pair:
    push    rcx
    movzx   ecx, byte [rax]
    test    ecx, ecx
    pop     rcx
    jz      .next
    push    rdi
    movzx   edi, byte [rax]
    mov     [rdx + rdi * 2], cl
    inc     byte [rdx + rdi * 2]
    push    rcx
    mov     cl, [rax + 1]
    mov     [rdx + rdi * 2 + 1], cl
    pop     rcx
    pop     rdi
    add     rax, 2
    jmp     .pair
.next:
    inc     ecx
    cmp     ecx, EVAL_LAST_LEVEL
    jbe     .level
    mov     byte [rel eval_ops_ready], 1
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

[SECTION .bss]
eval_op_by_kind:    resb 512
eval_ops_ready:     resb 1


[SECTION .rodata]
; per level, 16 bytes: (token kind, operation) pairs ending in 0
eval_level_ops:
    db TOK_OR, EOP_LOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_LXOR, EOP_LXOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_AND, EOP_LAND, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_EQUAL, EOP_EQ, TOK_NEQUAL, EOP_NE, TOK_LT, EOP_LT, TOK_LE, EOP_LE
    db TOK_GT, EOP_GT, TOK_GE, EOP_GE, TOK_CMP3, EOP_CMP3, 0, 0
    db TOK_PIPE, EOP_OR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_CARET, EOP_XOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_AMPERSAND, EOP_AND, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_LSHIFT, EOP_SHL, TOK_RSHIFT, EOP_SHR, TOK_SAR, EOP_SAR, 0, 0,0,0,0,0,0,0,0,0
[SECTION .text]

;*
; * [parser_evaluate_term]
; * Purpose: Multiplicative level: * / % (unsigned, as in NASM) and %%
; *   (signed modulo). utasm reads "//" as a comment, so NASM's signed
; *   division operator is not available.
; ;
parser_evaluate_term:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                ; [rsp] = resolved SYMBOL* of the left operand
    mov     rbx, rdi               ; RBX = PrepState

    mov     rdi, rbx
    call    parser_evaluate_factor
    check_err
    mov     r12, rdx               ; R12 = running total
    mov     r15, rcx               ; R15 = deferred symbol name (optional)
    mov     [rsp], r11             ; resolved SYMBOL* (optional)
    mov     rax, [rel expr_coeff]
    mov     [rsp + 8], rax         ; position coefficient

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    mov     r13, rdx               ; R13 = peeked token pointer
    mov     al, [r13 + TOKEN_kind]
    
    IF al, e, TOK_STAR
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        ; "[rbx + 4*rcx]": in a memory operand a number times a register is
        ; the register scaled. The operand takes it (mem_scaled_*); the term
        ; adds nothing to the displacement. (rcx went in as an unknown
        ; name: [2*rbx] was [0], [rbx+4*rcx+16] was [rbx+16].)
        cmp     byte [rel mem_scaling], 0
        je      .star_value
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_IDENT
        jne     .star_value
        mov     r14, rdx
        call    parser_get_arch_tables
        mov     rdi, rdx
        mov     rsi, [r14 + TOKEN_value]
        call    parser_is_register
        cmp     rax, ERR
        je      .star_value
        test    r15, r15
        jnz     .scaled_bad                ; a label times a register
        mov     rdi, [rsp]
        call    expr_sym_class
        test    eax, eax
        jnz     .scaled_bad
        cmp     dword [rel mem_scaled_n], MEM_SCALED_MAX
        jae     .scaled_bad
        mov     rdi, rbx
        call    preprocessor_next_token    ; the register
        check_err
        mov     ecx, [rel mem_scaled_n]
        lea     rax, [rel mem_scaled_tok]
        mov     [rax + rcx * 8], rdx
        inc     dword [rel mem_scaled_n]
.scaled_more:
        ; "2*rbx*2": the factors after it scale it too
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_STAR
        jne     .scaled_done
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        test    rcx, rcx
        jnz     .scaled_bad
        mov     rdi, r11
        call    expr_sym_class
        test    eax, eax
        jnz     .scaled_bad
        imul    r12, rdx
        jmp     .scaled_more
.scaled_done:
        mov     ecx, [rel mem_scaled_n]
        lea     rax, [rel mem_scaled_coef]
        mov     [rax + rcx * 8 - 8], r12
        xor     r12d, r12d
        mov     qword [rsp], 0
        jmp     .loop
.scaled_bad:
        mov     eax, EXIT_INVALID_ADDR
        jmp     .done
.star_value:
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     edi, EXP_MUL
        call    .combine
        test    rax, rax
        jnz     .done
        ; Multiplication wraps modulo 2^64 rather than erroring: hash
        ; constructions such as FNV-1a rely on it, including the
        ; compile_time_hash tables in src/encode/*.s.
        imul    r12, rdx
        jmp     .loop
    ELSEIF al, e, TOK_SLASH
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     edi, EXP_DIV
        call    .combine
        test    rax, rax
        jnz     .done
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx           ; R14 = divisor
        mov     rax, r12           ; RAX = dividend
        xor     edx, edx           ; unsigned, as NASM's /
        div     r14
        mov     r12, rax
        jmp     .loop
    ELSEIF al, e, TOK_DPERCENT
        ; %% : signed modulo
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     edi, EXP_DIV
        call    .combine
        test    rax, rax
        jnz     .done
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx
        mov     rax, r12
        cqo
        idiv    r14
        mov     r12, rdx
        jmp     .loop
    ELSEIF al, e, TOK_PERCENT
        ; modulo, unsigned as NASM's %
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     edi, EXP_DIV
        call    .combine
        test    rax, rax
        jnz     .done
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx
        mov     rax, r12
        xor     edx, edx
        div     r14
        mov     r12, rdx
        jmp     .loop
        ENDIF
    
    mov     rdx, r12
    xor     rax, rax
    jmp     .done

; the operands of * / % %% (edi: EXP_MUL / EXP_DIV): a plain number from
; here on. rax = OK, or NASM's error for a label in it.
.combine:
    mov     rsi, [rsp + 8]
    call    expr_scalar
    test    rax, rax
    jnz     .combine_ret
    mov     r8, [rsp + 16]
    mov     rdi, [rsp + 8]
    mov     rsi, r15
    call    expr_combine
    mov     [rsp + 16], rax
    mov     qword [rsp + 8], 0
    xor     r15d, r15d
    xor     eax, eax
.combine_ret:
    ret

.error:
    ; RAX already has the error code from check_err
.done:
    push    rax
    mov     rax, [rsp + 16]
    mov     [rel expr_coeff], rax
    pop     rax
    mov     rcx, r15               ; carry the symbol info to the caller
    mov     r11, [rsp]
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.overflow:
    mov     rax, EXIT_IMM_RANGE
    jmp     .done

.div_zero:
    ; a divisor not known yet (a label defined later): the expression is
    ; worked out at the end
    cmp     byte [rel expr_lost], 0
    jne     .loop
    mov     rax, EXIT_INVALID_IMM
    jmp     .done

;*
; * [parser_evaluate_factor]
; * Purpose: Primary level (Numbers, Symbols, Parens)
; ;
parser_evaluate_factor:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; RBX = PrepState

    ; Symbol outputs default to "none"; only the identifier path sets them.
    ; They live in preserved registers so the calls below cannot corrupt them.
    xor     r14, r14               ; deferred symbol name -> rcx
    xor     r15, r15               ; resolved SYMBOL*    -> r11
    mov     qword [rel expr_coeff], 0      ; independent of $ (but $ itself)

    ; NASM's limit on an expression's terms (its eval.c "deadman"): "%if
    ; %1 > 0" in a macro calling itself with "%1-1" read 1, 2 ... 10,000
    ; terms - seconds of work - before the macros' own limit stopped it
    inc     dword [rel expr_terms]
    mov     eax, [rel expr_terms]
    cmp     rax, [rel eval_limit]
    jbe     .terms_ok
    mov     eax, EXIT_EXPR_TOO_LONG
    jmp     .error
.terms_ok:

    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_MINUS
        ; "-1.5" in a data directive: a negative floating-point constant
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_FLOAT
        jne     .negate
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     r12, rdx
        mov     esi, 1
        jmp     .float
.negate:
        ; whether the operand is a float: its own (a float item before, "dd 1.5",
        ; left the mark, and "%substr s s 2,-1" negated -1 as one)
        mov     byte [rel float_seen], 0
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        ; "-__Infinity__": a float's sign, not an integer's (it was
        ; 0x80800000 for dd, NASM's is 0xFF800000)
        cmp     byte [rel float_seen], 0
        jne     .negate_float
        call    expr_unary_lost
        neg     rdx
        neg     qword [rel expr_coeff]
        xor     rax, rax
        jmp     .done
.negate_float:
        movzx   eax, byte [rel float_fmt]
        cmp     eax, FLT_BYTE
        jne     .neg_half
        xor     edx, 0x80
        jmp     .negated
.neg_half:
        cmp     eax, FLT_BF16
        je      .neg_16
        cmp     eax, FLT_HALF
        jne     .neg_single
.neg_16:
        xor     edx, 0x8000
        jmp     .negated
.neg_single:
        cmp     eax, FLT_SINGLE
        jne     .neg_double
        xor     edx, 0x80000000
        jmp     .negated
.neg_double:
        cmp     eax, FLT_DOUBLE
        jne     .neg_ext
        btc     rdx, 63
        jmp     .negated
.neg_ext:
        cmp     eax, FLT_EXT
        jne     .neg_quad
        xor     qword [rel float_hi], 0x8000   ; sign and exponent word
        jmp     .negated
.neg_quad:
        btc     qword [rel float_hi], 63       ; the high half
.negated:
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_TILDE
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        push    rdx
        mov     edi, EXP_NOT                ; ~ of a label: an error, as in NASM
        xor     esi, esi
        call    expr_scalar
        pop     rdx
        test    rax, rax
        jnz     .done
        call    expr_unary_lost
        not     rdx
        call    expr_coeff_taint
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_PLUS
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     r14, rcx               ; +x keeps x's symbol
        mov     r15, r11
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_NOT
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        push    rdx
        mov     edi, EXP_LNOT               ; ! of a label: an error, as in NASM
        xor     esi, esi
        call    expr_scalar
        pop     rdx
        test    rax, rax
        jnz     .done
        call    expr_unary_lost
        call    expr_coeff_taint
        test    rdx, rdx
        sete    dl
        movzx   edx, dl
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_QUESTION
        ; "db ?": an uninitialised item, zero here (parser_item_end)
        mov     byte [rel expr_question], 1
        xor     edx, edx
        xor     rax, rax
        jmp     .done
        ENDIF

    ; "seg x": x's segment - which no format here has (NASM's "binary
    ; output format does not support segment base references"), and a
    ; number none at all
    cmp     al, TOK_IDENT
    jne     .not_seg
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_seg_op]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_seg_word
    mov     rdi, rbx
    call    parser_evaluate_factor
    check_err
    test    rcx, rcx
    jnz     .seg_base                      ; a name not defined yet
    cmp     qword [rel expr_coeff], 0
    jne     .seg_base                      ; $
    mov     rdi, r11
    call    expr_sym_class
    test    eax, eax
    jnz     .seg_base                      ; a label, an extern
    mov     eax, EXIT_SEG_NOT_RELOC
    jmp     .done
.seg_base:
    extern  amd64_seg_base_error
    call    amd64_seg_base_error
    jmp     .done
.not_seg_word:
    mov     al, [r12 + TOKEN_kind]
.not_seg:

    ; A floating-point constant, in the format float_fmt names (dw/dd/dq/dt
    ; or __floatNN__ set it); anywhere else it is an error, as in NASM
    cmp     al, TOK_FLOAT
    jne     .not_float
    xor     esi, esi
.float:
    movzx   edx, byte [rel float_fmt]
    test    edx, edx
    jz      .float_bad
    ; "dt 123p" lexes as a float (p is a hex float's exponent): packed BCD
    cmp     edx, FLT_EXT
    jne     .float_encode
    push    rsi                            ; ("-456p": the sign)
    mov     rdi, [r12 + TOKEN_value]
    call    parser_bcd
    pop     rsi
    test    eax, eax
    jnz     .float_ext
    test    esi, esi
    jz      .bcd_sign
    or      ecx, 0x8000
.bcd_sign:
    mov     [rel float_hi], rcx
    mov     byte [rel float_seen], 1
    xor     eax, eax
    jmp     .done
.float_ext:
    movzx   edx, byte [rel float_fmt]
.float_encode:
    mov     rdi, [r12 + TOKEN_value]
    call    float_encode
    check_err
    mov     [rel float_hi], rcx
    mov     byte [rel float_seen], 1
    ; "dd 1.0e50": infinity, with NASM's warning
    extern  float_overflow
    cmp     byte [rel float_overflow], 0
    je      .float_ok
    push    rdx
    push    rcx
    mov     edi, WC_FLOAT_OVERFLOW
    call    warn_begin
    lea     rsi, [rel s_float_overflow]
    call    warn_text
    call    warn_end
    pop     rcx
    pop     rdx
.float_ok:
    xor     eax, eax
    jmp     .done
.float_bad:
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .done
.not_float:
    ; __float16__(x) / __float32__(x) / __float64__(x): the bits as a number
    cmp     al, TOK_IDENT
    jne     .not_float_fn
    ; __Infinity__, __QNaN__, __SNaN__: floats, where one goes
    cmp     byte [rel float_fmt], 0
    je      .not_special
    mov     rdi, [r12 + TOKEN_value]
    call    parser_float_special
    test    eax, eax
    jz      .not_special
    lea     esi, [rax - 1]
    movzx   edx, byte [rel float_fmt]
    extern  float_special
    call    float_special
    mov     [rel float_hi], rcx
    mov     byte [rel float_seen], 1
    xor     eax, eax
    jmp     .done
.not_special:
    ; "mov ax, __utf16__(`a`)": a string function in an expression is its
    ; first bytes as a number, the first the lowest (as 'ab' is)
    mov     rdi, [r12 + TOKEN_value]
    call    parser_utf_kind
    test    eax, eax
    jz      .not_utf_value
    mov     r13d, eax
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .utf_value_bad
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    movzx   r14d, word [r12 + TOKEN_len]
    lea     r15, [rel utf_value_chars]
    mov     rax, [r12 + TOKEN_value]
    mov     [r15], rax
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    je      .utf_value_close
    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    jne     .utf_value_bad
    mov     r15, [r12 + TOKEN_value]
    test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .utf_value_close
    mov     rdi, r15
    call    str_len
    mov     r14, rax
.utf_value_close:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .utf_value_bad
    mov     rdi, r15
    mov     rsi, r14
    mov     edx, r13d
    call    parser_utf_encode
    check_err
    ; the first eight bytes at most, little-endian
    mov     rcx, rdx
    cmp     rcx, 8
    jbe     .utf_value_len
    mov     ecx, 8
.utf_value_len:
    mov     rsi, [rel ds_utf_buf]
    xor     edx, edx
.utf_value_byte:
    test    ecx, ecx
    jz      .utf_value_done
    dec     ecx
    shl     rdx, 8
    movzx   eax, byte [rsi + rcx]
    or      rdx, rax
    jmp     .utf_value_byte
.utf_value_done:
    xor     r14d, r14d                     ; (no symbol in it)
    xor     r15d, r15d
    xor     eax, eax
    jmp     .done
.utf_value_bad:
    xor     r14d, r14d
    xor     r15d, r15d
    mov     eax, EXIT_INVALID_EXPR
    jmp     .done
.not_utf_value:
    ; __?ilog2e?__(x) & co (NASM's, which %use ifunc names ilog2e(x) ...):
    ; log2 of x as an unsigned number, exact, warned, floor or ceiling
    mov     rdi, [r12 + TOKEN_value]
    call    parser_ilog2_func
    test    eax, eax
    jnz     .ilog2
    mov     rdi, [r12 + TOKEN_value]
    call    parser_float_func
    test    eax, eax
    jz      .not_float_fn_ident
    movzx   r13d, byte [rel float_fmt]     ; the enclosing directive's
    mov     [rel float_part], al           ; FLT_HIGH: the high part
    and     al, 0x7F
    mov     [rel float_fmt], al
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .float_fn_end
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .float_fn_bad
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .float_fn_end
    mov     [rel float_fn_val], rdx
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .float_fn_end
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .float_fn_bad
    mov     rdx, [rel float_fn_val]
    test    byte [rel float_part], FLT_HIGH
    jz      .float_fn_low
    mov     rdx, [rel float_hi]            ; __float80e__ / __float128h__
.float_fn_low:
    mov     byte [rel float_seen], 0       ; a plain number from here on
    xor     eax, eax
    jmp     .float_fn_end
.float_fn_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.float_fn_end:
    mov     [rel float_fmt], r13b
    jmp     .done
.ilog2:
    push    rax                            ; 1 exact, 2 warned, 3 floor, 4 ceiling
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ilog2_out1
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .ilog2_bad1
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ilog2_out1
    push    rdx                            ; x
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ilog2_out2
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .ilog2_bad2
    pop     rcx                            ; x
    pop     rax                            ; the kind
    xor     edx, edx                       ; floor(log2 x), 0 for 0
    test    rcx, rcx
    jz      .ilog2_floor
    bsr     rdx, rcx
.ilog2_floor:
    cmp     eax, 4
    jne     .ilog2_not_ceil
    xor     edx, edx                       ; ceiling: 0 for 0 and 1
    cmp     rcx, 1
    jbe     .ilog2_ok
    lea     r8, [rcx - 1]
    bsr     rdx, r8
    inc     edx
    jmp     .ilog2_ok
.ilog2_not_ceil:
    cmp     eax, 3
    je      .ilog2_ok
    ; exact or warned: x a power of two
    test    rcx, rcx
    jz      .ilog2_not_pow2
    lea     r8, [rcx - 1]
    test    rcx, r8
    jz      .ilog2_ok
.ilog2_not_pow2:
    cmp     eax, 1
    jne     .ilog2_warn
    mov     rax, EXIT_ILOG2
    jmp     .done
.ilog2_warn:
    push    rdx
    mov     edi, WC_OTHER
    extern  warn_begin, warn_end
    call    warn_begin
    test    eax, eax
    jz      .ilog2_quiet
    lea     rsi, [rel str_ilog2_warn]
    call    warn_text
    call    warn_end
.ilog2_quiet:
    pop     rdx
.ilog2_ok:
    xor     eax, eax
    jmp     .done
.ilog2_bad2:
    pop     rcx
.ilog2_bad1:
    pop     rcx
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .done
.ilog2_out2:
    pop     rcx
.ilog2_out1:
    pop     rcx
    jmp     .done
.not_float_fn_ident:
    mov     al, TOK_IDENT
.not_float_fn:
    ; %use masm's OFFSET X in a value: X (its address)
    cmp     al, TOK_IDENT
    jne     .not_masm_offset
    mov     rcx, [r12 + TOKEN_value]
    cmp     byte [rcx], '_'
    jne     .not_masm_offset
    mov     rdi, rcx
    lea     rsi, [rel str_masm_offset]
    call    str_cmp
    test    rax, rax
    jnz     .not_masm_offset_word
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    jmp     .not_float_fn
.not_masm_offset_word:
    mov     al, TOK_IDENT
.not_masm_offset:
    ; %use masm's SIZEOF / LENGTHOF / TYPE X (src/frontend/syntax/masm/masm.s)
    cmp     byte [rel masm_hl], 0
    je      .not_size_op
    cmp     al, TOK_IDENT
    jne     .not_size_op
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_sizeof]
    call    str_cmp_kw
    xor     esi, esi
    test    rax, rax
    jz      .size_op
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_lengthof]
    call    str_cmp_kw
    mov     esi, 1
    test    rax, rax
    jz      .size_op
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_type_op]
    call    str_cmp_kw
    mov     esi, 2
    test    rax, rax
    jnz     .not_size_kw
.size_op:
    push    rsi
    mov     rdi, rbx
    call    preprocessor_peek_token
    pop     rsi
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .size_go
    cmp     eax, TOK_LPAREN
    jne     .not_size_kw
.size_go:
    mov     rdi, rbx
    extern  masm_size_op
    call    masm_size_op
    check_err
    xor     eax, eax
    jmp     .done
.not_size_kw:
    mov     al, TOK_IDENT
.not_size_op:
    ; GNU's syntax: "name" (GCC 16's -masm=intel quotes every name) and
    ; name@PLT, "name"@GOTPCREL ... (parser_gas_symbol)
    extern  gas_names
    cmp     byte [rel gas_names], 0
    je      .not_gas_symbol
    call    parser_gas_symbol
.not_gas_symbol:
    ; GNU's "." alone: the location, $
    cmp     al, TOK_IDENT
    jne     .not_gas_dot
    mov     rcx, [r12 + TOKEN_value]
    cmp     word [rcx], '.'
    jne     .not_gas_dot
    mov     al, TOK_DOLLAR
.not_gas_dot:
    ; FASM's "defined NAME" / "defined(NAME)": 1 or 0 (src/frontend/syntax/
    ; fasm.s) - "defined" alone is a name
    cmp     al, TOK_IDENT
    jne     .not_defined_op
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_defined]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_defined_kw
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .defined_op
    cmp     eax, TOK_LPAREN
    jne     .not_defined_kw
.defined_op:
    mov     rdi, rbx
    extern  fasm_defined
    call    fasm_defined
    check_err
    xor     eax, eax
    jmp     .done
.not_defined_kw:
    mov     al, TOK_IDENT
.not_defined_op:

    IF al, e, TOK_NUMBER
        ; "1f" / "1b": a numeric label reference, looked up like a symbol
        mov     rdi, [r12 + TOKEN_value]
        call    parser_numlabel_ref
        test    rsi, rsi
        jnz     .do_sym_lookup
        ; "dt 123p", "dt 0p123": packed BCD, the 80-bit item a float is
        cmp     byte [rel float_fmt], FLT_EXT
        jne     .not_bcd
        mov     rdi, [r12 + TOKEN_value]
        call    parser_bcd
        test    eax, eax
        jnz     .not_bcd
        mov     [rel float_hi], rcx
        mov     byte [rel float_seen], 1
        xor     eax, eax
        jmp     .done
.not_bcd:
        ; "1e" "+" "36" (a macro's "%1e+%2"): NASM reads the pasted line
        ; again, and "1e+36" is a float - where one is taken
        cmp     byte [rel float_fmt], 0
        je      .not_split_float
        mov     rdi, [r12 + TOKEN_value]
        call    parser_split_float
        test    eax, eax
        jnz     .not_split_float
        mov     [r12 + TOKEN_value], rdx
        xor     esi, esi
        jmp     .float
.not_split_float:
        mov     rdi, [r12 + TOKEN_value]
        call    str_to_int
        check_err
        ; past 64 bits: the low 64, with NASM's warning
        extern  str_int_wrapped
        cmp     byte [rel str_int_wrapped], 0
        je      .number_fits
        push    rdx
        mov     edi, WC_NUMBER_OVERFLOW
        call    warn_begin
        test    eax, eax
        jz      .number_warned
        lea     rsi, [rel s_num_wide_a]
        call    warn_text
        mov     rsi, [r12 + TOKEN_value]
        call    warn_text
        lea     rsi, [rel s_num_wide_b]
        call    warn_text
        call    warn_end
.number_warned:
        pop     rdx
.number_fits:
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_CHAR
        mov     rdx, [r12 + TOKEN_value]
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_STRING
        ; a double- or back-quoted string in an expression: a character
        ; constant, as a single-quoted one is in NASM - its bytes, the
        ; first the lowest (a double-quoted quote was a syntax error)
        mov     rsi, [r12 + TOKEN_value]
        movzx   ecx, word [r12 + TOKEN_len]
        test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
        jnz     .str_counted
        xor     ecx, ecx
.str_nul:
        cmp     byte [rsi + rcx], 0
        je      .str_counted
        inc     ecx
        jmp     .str_nul
.str_counted:
        cmp     ecx, 8
        jbe     .str_fits
        mov     ecx, 8
.str_fits:
        xor     edx, edx
.str_pack:
        test    ecx, ecx
        jz      .str_packed
        dec     ecx
        shl     rdx, 8
        mov     dl, [rsi + rcx]
        jmp     .str_pack
.str_packed:
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_DOLLAR
        ; Current location counter ($) or the section's start ($$): a label
        ; at that point. Used as a number only in a difference ("$ - $$"),
        ; which freezes the code between them, or in arithmetic that
        ; freezes the section (expr_combine).
        mov     rax, [rbx + PREP_ctx]
        mov     rax, [rax + ASMCTX_curr_sec]
        IF rax, e, 0
            ; If no section, return 0 (or error?)
            xor rax, rax
            jmp     .done
            ENDIF
        ; "$$" arrives as two '$' tokens
        xor     r13d, r13d
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_DOLLAR
        jne     .pos_label
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     r13d, 1
.pos_label:
        mov     edi, r13d
        call    parser_pos_label
        check_err
        mov     r15, rdx                   ; a defined label, as for an identifier
        lea     edi, [r13d + 1]            ; recorded as that label ("$$": two
        mov     rsi, [rdx + SYMBOL_name]   ; tokens), for an expression kept
        extern  prep_rec_rename
        call    prep_rec_rename
        mov     rdx, [rdx + SYMBOL_value]
        test    r13d, r13d
        jnz     .pos_start
        mov     qword [rel expr_coeff], 1  ; $ moves with itself
.pos_start:
        inc     qword [rel known_pos_uses]  ; a position (src/core/known.s)
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_IDENT
        ; Check if local label reference (starts with '.')
        mov     rsi, [r12 + TOKEN_value]
        mov     r10, [rbx + PREP_ctx]
        cmp     byte [rsi], '.'
        jne     .do_sym_lookup
        cmp     byte [rsi + 1], '.'
        je      .do_sym_lookup         ; "..@N_x" is a macro-local, not a local label
        mov     r13, [r10 + ASMCTX_last_global]
        test    r13, r13
        jz      .do_sym_lookup
        push    r14                    ; r14 carries the deferred symbol name
        mov     r14, r13               ; concat_local_name takes the global in r14
        call    parser_concat_local_name
        pop     r14
        mov     rsi, rdx               ; namespaced name

.do_sym_lookup:
        mov     rdi, rsi
        call    parser_ptr_warn                ; "ptr": NASM's warning
        ; %use masm's ptr / flat in a value: NASM's syntax error
        push    rsi
        mov     rdi, rsi
        lea     rsi, [rel str_masm_flat]
        call    str_cmp
        mov     rdi, [rsp]
        test    rax, rax
        jz      .masm_word
        lea     rsi, [rel str_masm_ptr]
        call    str_cmp
        test    rax, rax
        jnz     .not_masm_word
.masm_word:
        pop     rsi
        mov     rax, EXIT_INVALID_EXPR
        jmp     .done
.not_masm_word:
        pop     rsi
        ; inside namespaces: the innermost's that has it (namespace.s)
        extern  ns_ref
        call    ns_ref
        ; recorded under the name it resolved to (".x" under its global
        ; label, "1f" as the label it means), for an expression kept
        mov     edi, 1
        call    prep_rec_rename
        ; Symbol lookup
        mov     rdi, [rbx + PREP_ctx]
        extern  symbol_find
        call    symbol_find
        ; a macro's name is no symbol: "db 1, m" with m a multi-line macro
        ; is NASM's "symbol `m' not defined"
        test    rax, rax
        jnz     .looked_up
        cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
        jne     .looked_up
        mov     eax, 1
.looked_up:
        IF rax, e, OK
            ; an entry not defined yet (named by global, or by a reference
            ; before): the second pass may know it as a constant
            cmp     word [rdx + SYMBOL_section], 0
            jne     .sym_defined
            push    rdx
            inc     qword [rel known_fwd_uses]
            call    known_lookup
            test    rax, rax
            jz      .sym_unknown
            add     rsp, 8
            xor     r15d, r15d             ; a plain number
            xor     r14d, r14d
            xor     eax, eax
            jmp     .done
.sym_unknown:
            call    known_note_forward     ; (pass 1: noted)
            call    expr_note_undef
            pop     rdx
.sym_defined:
            mov     r15, rdx               ; return SYMBOL* in r11 (A78)
            ; a position (a label, or an equ derived from one) in an equ
            ; makes it depend on the layout (src/core/known.s)
            cmp     word [rdx + SYMBOL_section], SHN_ABS
            jne     .pos_use
            test    byte [rdx + SYMBOL_pflags], SYMF_POSDEP
            jz      .pos_none
.pos_use:
            extern  known_pos_uses
            inc     qword [rel known_pos_uses]
.pos_none:
            mov     rdx, [rdx + SYMBOL_value]
            call    expr_deferred_addr     ; (r15: the SYMBOL)
            xor     rax, rax
            ELSE
            ; not defined yet: the second pass knows it if it is a
            ; constant (src/core/known.s), the first notes it
            extern  known_lookup, known_note_forward
            inc     qword [rel known_fwd_uses]     ; (NASM: unknown in pass 1)
            call    known_lookup
            test    rax, rax
            jz      .unknown_yet
            xor     r15d, r15d             ; a plain number
            xor     r14d, r14d
            xor     eax, eax
            jmp     .done
.unknown_yet:
            call    known_note_forward
            call    expr_note_undef
            inc     qword [rel known_pos_uses]
            ; Deferred symbol (R_ABS64 reloc)
            mov     rdx, 0
            xor     r15, r15               ; no symbol metadata yet
            mov     r14, rsi               ; return namespaced symbol name in RCX
            xor     rax, rax
            ENDIF
        jmp     .done
    ELSEIF al, e, TOK_LPAREN
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
        mov     r14, rcx               ; carry the inner symbol info outward
        mov     r15, r11
        mov     r13, rdx
        mov     rdi, rbx
        call    preprocessor_next_token
        IF byte [rdx + TOKEN_kind], ne, TOK_RPAREN
            mov rax, EXIT_UNEXPECTED_TOKEN
            jmp     .done
            ENDIF
        mov     rdx, r13
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_COLON
        ; ":lo12:sym" is AArch64's; elsewhere a colon is no operand
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
        mov     eax, EXIT_INVALID_EXPR
        jne     .error
        mov     rdi, rbx
        call    parser_handle_reloc_modifier
        check_err_to .error
        IF rax, ne, OK
            jmp .error
        ENDIF
        jmp     .done
        ENDIF
    
    mov     rax, EXIT_INVALID_EXPR
    jmp     .error

.error:
.done:
    mov     rcx, r14               ; deferred symbol name (0 if none)
    mov     r11, r15               ; resolved SYMBOL*     (0 if none)
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
