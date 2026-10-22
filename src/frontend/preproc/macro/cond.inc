; ============================================================================
; File        : src/frontend/preproc/macro/cond.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : entering and branching conditionals, %ifidn / %ifidni, %elif, %error; constant text substitution, file pasting
; ============================================================================

; ---- prep_subst_const_text --------------
;
; prep_subst_const_text
; If the token names a %assign / %define constant, replace its text with the
; constant's value in decimal. Pasting joins text, and "%assign i 7" makes i
; a numeric macro: ".lbl_ %+ i" has to produce ".lbl_7", not ".lbl_i". A
; %define of one token, with no parameters, stands for that token ("%define
; P ab": "P %+ cd" is abcd, as NASM expands before it pastes), and so on
; down a chain of them.
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (rewritten in place)
;
prep_subst_const_text:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8                         ; (alignment)
    mov     rbx, rdi
    mov     r12, rsi
    ; "start_ %+ n:": a label's name is substituted the same way, and it
    ; stays a label (the join is a label definition)
    movzx   r14d, byte [r12 + TOKEN_kind]
    cmp     r14d, TOK_LABEL
    jne     .not_label
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
.not_label:

    mov     r13d, 32                       ; (a %define naming itself)
.lookup:
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .done

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .one_token_define
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .done
    mov     r13, [rdx + SYMBOL_value]

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .done

    mov     rdi, rdx
    mov     [r12 + TOKEN_value], rdx
    mov     rsi, r13
    call    str_int_to_str
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    jmp     .done

.one_token_define:
    mov     rax, [rdx + SYMBOL_value]      ; MACRO*
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .done
    cmp     word [rax + MACRO_max_params], 0
    jne     .done
    cmp     dword [rax + MACRO_ntokens], 0
    jne     .one_token
    ; "%define gpr_q" (empty): "r0 %+ gpr_q" is r0
    lea     rax, [rel s_fn_empty]
    mov     [r12 + TOKEN_value], rax
    jmp     .done
.one_token:
    cmp     dword [rax + MACRO_ntokens], 1
    jne     .done
    mov     rax, [rax + MACRO_tokens]
    mov     cl, [rax + TOKEN_kind]
    cmp     cl, TOK_IDENT
    je      .define_text
    cmp     cl, TOK_NUMBER
    jne     .done
.define_text:
    mov     [r12 + TOKEN_kind], cl
    mov     rax, [rax + TOKEN_value]
    mov     [r12 + TOKEN_value], rax
    dec     r13d
    jnz     .lookup

.done:
    cmp     r14d, TOK_LABEL
    jne     .kind_kept
    mov     byte [r12 + TOKEN_kind], TOK_LABEL
.kind_kept:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_file_paste --------------------
;
; "P %+ cd" in the source itself (a body's %+ is joined as the body is
; served, prep_expand_next): the token just read, r12, joined with the one
; after the %+ - each first as the constant or one-token %define it names
; (prep_subst_const_text) - and again for "a %+ b %+ c". prep_internal_next
; then looks the result up like any token ("abcd" can be a %define).
; The %+ is found by reading the source bytes, not by lexing ahead: the
; lexer's line must not move past this line (%line relies on it).
; Input    : rbx = PrepState, r12 = the token just read from the lexer
; Output   : rax = EXIT_OK or an error
;
prep_file_paste:
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .pasteable
    cmp     eax, TOK_NUMBER
    jne     .none
.pasteable:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .none
    ; a %define body keeps its %+ until it is expanded ("%define J(a,b)
    ; a %+ b" joins the arguments, not a and b)
    cmp     byte [rel prep_noexpand], 0
    jne     .none
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE
    mov     r13, [rbx + PREP_lexer]
.again:
    cmp     byte [r13 + LEXER_has_peek], TRUE
    jne     .scan
    cmp     byte [r13 + LEXER_peek + TOKEN_kind], TOK_CONCAT
    jne     .ok
    jmp     .paste
.scan:
    mov     rsi, [r13 + LEXER_pos]
    mov     rdi, [r13 + LEXER_end]
.blank:
    cmp     rsi, rdi
    jae     .ok
    mov     al, [rsi]
    cmp     al, ' '
    je      .blank_next
    cmp     al, 9
    jne     .blank_done
.blank_next:
    inc     rsi
    jmp     .blank
.blank_done:
    cmp     al, '%'
    jne     .ok
    lea     rax, [rsi + 1]
    cmp     rax, rdi
    jae     .ok
    cmp     byte [rsi + 1], '+'
    jne     .ok
.paste:
    mov     rdi, r13
    mov     rsi, rsp
    call    lexer_next                     ; the %+
    test    rax, rax
    jnz     .out
    mov     rdi, r13
    mov     rsi, rsp
    call    lexer_next                     ; what it joins on
    test    rax, rax
    jnz     .out
    movzx   eax, byte [rsp + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .join
    cmp     eax, TOK_NUMBER
    je      .join
    cmp     eax, TOK_LABEL
    je      .join
    cmp     eax, TOK_LOCAL_LABEL
    je      .join
    ; nothing to join ("x %+" at the end of the line): NASM's error; what
    ; followed is read next
    lea     rdi, [r13 + LEXER_peek]
    mov     rsi, rsp
    copy_token
    mov     byte [r13 + LEXER_has_peek], TRUE
    mov     eax, EXIT_INVALID_EXPR
    jmp     .out
.join:
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_subst_const_text
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_subst_const_text
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MAX_TOKEN
    call    arena_alloc
    test    rax, rax
    jnz     .out
    mov     r14, rdx
    mov     byte [r14], 0
    mov     rdi, r14
    mov     rsi, [r12 + TOKEN_value]
    call    str_concat
    mov     rdi, r14
    mov     rsi, [rsp + TOKEN_value]
    call    str_concat
    ; a label when the right piece carried the ':'; a number when it
    ; starts with a digit ("1 %+ 2")
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    mov     cl, [rsp + TOKEN_kind]
    cmp     cl, TOK_LABEL
    je      .label
    cmp     cl, TOK_LOCAL_LABEL
    je      .label
    movzx   eax, byte [r14]
    sub     eax, '0'
    cmp     eax, 9
    ja      .kind_set
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    jmp     .kind_set
.label:
    mov     byte [r12 + TOKEN_kind], TOK_LABEL
    cmp     byte [r14], '.'
    jne     .kind_set
    mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
.kind_set:
    mov     [r12 + TOKEN_value], r14
    mov     rdi, r14
    call    str_len
    mov     [r12 + TOKEN_len], ax
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    je      .again                         ; "a %+ b %+ c"
    cmp     byte [r12 + TOKEN_kind], TOK_NUMBER
    je      .again
.ok:
    xor     eax, eax
.out:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    ret
.none:
    xor     eax, eax
    ret

; ---- conditional level bookkeeping ------
;
; PREP_depth counts open conditionals and PREP_skip_depth counts how many of
; them are currently suppressing output. cond_taken[level] records whether a
; branch at that level has already fired, which is what makes %elif chains
; behave: once one branch is taken, every later branch stays skipped.
;
; prep_cond_enter : rdi = PrepState, sil = 1 when the condition holds
;
prep_cond_enter:
    movzx   eax, word [rdi + PREP_depth]
    cmp     eax, PREP_COND_MAX
    jae     .overflow

    cmp     word [rdi + PREP_skip_depth], 0
    jne     .outer_skipping

    test    sil, sil
    jz      .not_taken
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.not_taken:
    mov     byte [rdi + PREP_cond_taken + rax], 0
    inc     word [rdi + PREP_skip_depth]
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.outer_skipping:
    ; an enclosing level is suppressing: mark taken so %else cannot revive it
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     word [rdi + PREP_skip_depth]
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.overflow:
    mov     rax, EXIT_COND_DEPTH
    ret

;
; prep_cond_never : rdi = PrepState. A %elif whose condition NASM cannot
;                   work out (a name not defined, a label, no macro name):
;                   it skips, and so does every later branch of the level
;                   (NASM's COND_NEVER, with no message)
;
prep_cond_never:
    push    rdi
    xor     esi, esi
    call    prep_cond_branch
    pop     rdi
    test    rax, rax
    jnz     .ret
    movzx   ecx, word [rdi + PREP_depth]
    test    ecx, ecx
    jz      .ret
    or      byte [rdi + PREP_cond_taken + rcx - 1], 1
.ret:
    ret

;
; prep_cond_branch : rdi = PrepState, sil = 1 when this branch's condition
;                    holds (%else passes 1). Handles %else / %elif / %elifidni.
;
prep_cond_branch:
    movzx   eax, word [rdi + PREP_depth]
    test    eax, eax
    jz      .no_if
    dec     eax

    movzx   ecx, word [rdi + PREP_skip_depth]
    cmp     ecx, 1
    ja      .unchanged             ; an outer level is skipping

    ; after this level's %else (bit 1): NASM's warning, the content skipped,
    ; the level dead from then on (bit 2: NASM's COND_NEVER, which keeps
    ; the next such warnings quiet)
    test    byte [rdi + PREP_cond_taken + rax], 2
    jz      .no_else_yet
    test    byte [rdi + PREP_cond_taken + rax], 4
    jnz     .no_else_yet
    or      byte [rdi + PREP_cond_taken + rax], 4
    push    rdi
    push    rax
    mov     edi, WC_PP_ELSE_ELIF
    lea     rsi, [rel s_elif_after_else]
    cmp     byte [rel cond_is_else], 0
    je      .after_else_warn
    mov     edi, WC_PP_ELSE_ELSE
    lea     rsi, [rel s_else_after_else]
.after_else_warn:
    push    rsi
    call    warn_begin
    pop     rsi
    call    warn_text
    call    warn_end
    pop     rax
    pop     rdi
.no_else_yet:

    cmp     byte [rdi + PREP_cond_taken + rax], 0
    jne     .force_skip

    test    sil, sil
    jz      .stay_skipping
    mov     byte [rdi + PREP_cond_taken + rax], 1
    mov     word [rdi + PREP_skip_depth], 0
    xor     rax, rax
    ret

.stay_skipping:
    mov     word [rdi + PREP_skip_depth], 1
    xor     rax, rax
    ret

.force_skip:
    mov     word [rdi + PREP_skip_depth], 1
.unchanged:
    xor     rax, rax
    ret

.no_if:
    mov     rax, EXIT_ERROR
    ret

; ---- prep_str_cmp_ci --------------------
;
; Case-insensitive comparison of two NUL-terminated strings.
; Input  : rdi, rsi = strings
; Output : rax = 0 when equal
;
prep_str_cmp_ci:
.loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]

    cmp     al, 'A'
    jb      .a_ready
    cmp     al, 'Z'
    ja      .a_ready
    add     al, 32
.a_ready:
    cmp     cl, 'A'
    jb      .b_ready
    cmp     cl, 'Z'
    ja      .b_ready
    add     cl, 32
.b_ready:
    cmp     al, cl
    jne     .differ
    test    al, al
    jz      .equal
    inc     rdi
    inc     rsi
    jmp     .loop

.equal:
    xor     rax, rax
    ret
.differ:
    mov     rax, 1
    ret

; ---- prep_read_idn_pair -----------------
;
; Reads "A, B" from the directive line and reports whether the two token
; sequences are the same, as NASM's %ifidn compares them: token by token,
; each side up to the comma / the end of the line. idn_case selects the
; comparison (1: exact, 0: ignoring case). Macros in the operands are
; expanded first, so "%ifidn __SECT__, [section .text]" works.
;
; Input  : rdi = PrepState
; Output : rax = EXIT_OK, rdx = 1 when they match
;
prep_read_idn_pair:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi

    ; The operands belong to this directive and must be read even inside a
    ; skipped block; with skipping active the token reader would swallow the
    ; rest of the file instead of handing them back.
    movzx   r14d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0

    mov     rdi, rbx
    call    prep_drop_stale_newline

    lea     rdi, [rel idn_left]
    mov     esi, 1                 ; up to the comma
    call    prep_idn_collect
    test    rax, rax
    jnz     .fail
    mov     r12, rdx               ; the left text
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .have_right
    mov     rdi, rbx
    call    preprocessor_next_token
.have_right:
    lea     rdi, [rel idn_right]
    xor     esi, esi               ; up to the end of the line
    call    prep_idn_collect
    test    rax, rax
    jnz     .fail
    mov     r13, rdx               ; the right text

    mov     rdi, r12
    mov     rsi, r13
    cmp     byte [rel idn_case], 0
    jne     .case_sensitive
    call    prep_str_cmp_ci
    jmp     .compared
.case_sensitive:
    call    str_cmp                    ; %ifidn / %ifnidn
.compared:
    test    rax, rax
    jnz     .not_equal

    xor     rax, rax
    mov     rdx, 1
    jmp     .done

.not_equal:
    xor     rax, rax
    xor     rdx, rdx
    jmp     .done

.fail:
    xor     rdx, rdx

.done:
    mov     [rbx + PREP_skip_depth], r14w   ; restore the skip state
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;
; prep_idn_collect
; The text of the tokens up to the end of the line (or a comma), one space
; between them, into a buffer that grows: its descriptor holds the pointer
; and the capacity, and a full buffer is replaced by one twice the size
; (kept for the next use).
; Input  : rbx = PrepState, rdi = the buffer's descriptor (idn_left ...),
;          esi = bit 0: stop at a comma, bit 1: blanks only where the source
;          has them (%defstr), bit 2: stop at a ")" (a function's argument;
;          parentheses nest, and a comma inside them does not stop it)
; Output : rax = EXIT_OK or error, rdx = the text
;
prep_idn_collect:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13d, esi
    xor     r14d, r14d                 ; bytes written
    mov     dword [rel idn_depth], 0
    mov     rax, [r12]
    mov     byte [rax], 0
.token:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .end
    cmp     eax, TOK_EOF
    je      .end
    test    r13d, 4
    jz      .no_paren
    ; a function's argument: up to its ")", parentheses nesting
    cmp     eax, TOK_LPAREN
    jne     .not_open
    inc     dword [rel idn_depth]
    jmp     .take
.not_open:
    cmp     eax, TOK_RPAREN
    jne     .no_paren
    cmp     dword [rel idn_depth], 0
    je      .end
    dec     dword [rel idn_depth]
    jmp     .take
.no_paren:
    test    r13d, 1
    jz      .take
    cmp     eax, TOK_COMMA
    jne     .take
    cmp     dword [rel idn_depth], 0
    je      .end
.take:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    test    r14d, r14d
    jz      .no_sep
    test    r13d, 2
    jz      .sep
    ; the source's spacing: a blank only where the source had one - an
    ; argument's first token has its parameter's (NASM's)
    test    byte [r15 + TOKEN_flags], TOK_FLAG_SPACE
    jz      .no_sep
.sep:
    mov     eax, ' '
    call    .put
    test    rax, rax
    jnz     .ret
.no_sep:
    ; %defstr: a string keeps its quotes, as written
    xor     eax, eax
    test    r13d, 2
    jz      .unquoted
    movzx   ecx, byte [r15 + TOKEN_kind]
    cmp     ecx, TOK_STRING
    je      .quoted
    cmp     ecx, TOK_CHAR
    jne     .unquoted
.quoted:
    movzx   eax, byte [r15 + TOKEN_quote]
    test    eax, eax
    jnz     .unquoted
    mov     eax, 0x27
.unquoted:
    mov     [rel idn_quote], al
    test    eax, eax
    jz      .text
    call    .put
    test    rax, rax
    jnz     .ret
.text:
    mov     rdx, r15
    call    prep_idn_text
    mov     r15, rax
.copy:
    movzx   eax, byte [r15]
    test    eax, eax
    jz      .copied
    call    .put
    test    rax, rax
    jnz     .ret
    inc     r15
    jmp     .copy
.copied:
    movzx   eax, byte [rel idn_quote]
    test    eax, eax
    jz      .token
    call    .put                           ; the closing quote
    test    rax, rax
    jnz     .ret
    jmp     .token
.end:
    mov     rdx, [r12]
    mov     byte [rdx + r14], 0
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; .put: the byte al at the end of the text (the buffer twice the size when
; it is full). rax = OK or an error; clobbers rcx, rdx, rdi, rsi, r8-r11.
.put:
    lea     rcx, [r14 + 2]                 ; the byte and the NUL
    cmp     rcx, [r12 + 8]
    jbe     .put_room
    push    rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [r12 + 8]
    shl     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .put_fail
    mov     rdi, rdx
    mov     rsi, [r12]
    mov     ecx, r14d
    rep movsb
    mov     [r12], rdx
    shl     qword [r12 + 8], 1
    pop     rax
.put_room:
    mov     rcx, [r12]
    mov     [rcx + r14], al
    inc     r14d
    xor     eax, eax
    ret
.put_fail:
    add     rsp, 8                         ; (the byte)
    ret

;
; prep_idn_text : rax = a token's text (rdx = token, rbx = PrepState)
;
prep_idn_text:
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_CHAR
    je      prep_token_text
    cmp     eax, TOK_EQUAL                 ; "=" and "==" are one kind
    jne     .not_assign
    cmp     word [rdx + TOKEN_len], 1
    jne     .not_assign
    lea     rax, [rel idn_assign]
    ret
.not_assign:
    lea     rcx, [rel idn_punct]
.punct:
    cmp     byte [rcx], 0
    je      .word
    cmp     al, [rcx]
    je      .punct_hit
    add     rcx, 4
    jmp     .punct
.punct_hit:
    lea     rax, [rcx + 1]
    ret
.word:
    mov     rax, [rdx + TOKEN_value]
    test    rax, rax
    jnz     .ret
    lea     rax, [rel idn_unknown]
.ret:
    ret

; ---- prep_handle_ifidni -----------------
prep_handle_ifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_enter

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elifidni ---------------
prep_handle_elifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_branch

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elif -------------------
prep_handle_elif:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    ; %elifn: taken here, for the evaluation below if there is one
    mov     al, [rel cond_negate]
    mov     [rel elif_negate], al
    mov     byte [rel cond_negate], 0

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; Only evaluate when this level could still take a branch
    movzx   eax, word [rbx + PREP_depth]
    test    eax, eax
    jz      .no_if
    dec     eax
    movzx   ecx, word [rbx + PREP_skip_depth]
    cmp     ecx, 1
    ja      .no_eval
    cmp     byte [rbx + PREP_cond_taken + rax], 0
    jne     .no_eval

    ; The condition is this directive's own operand: read it with skipping
    ; suspended, or the token reader discards it along with the skipped block.
    movzx   r12d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0

    mov     qword [rel expr_undef_uses], 0
    mov     rdi, rbx
    call    parser_evaluate_pp
    mov     word [rbx + PREP_skip_depth], r12w
    test    rax, rax
    jnz     .done
    ; a name not defined, a label: no message, and no branch of this %if
    ; is taken any more (NASM's COND_NEVER)
    push    rdx
    lea     rdi, [rel s_cn_if]
    call    prep_const_check
    pop     rdx
    test    rax, rax
    jnz     .never
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    xor     sil, [rel elif_negate]
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done
.never:
    mov     rdi, rbx
    call    prep_cond_never
    jmp     .done

.no_eval:
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done

.no_if:
    mov     rax, EXIT_ERROR

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_error ------------------
;
; "%error message" — reported only when the line is actually reached.
;
prep_handle_error:
    prologue
    push    rbx
    mov     rbx, rdi

    ; While skipping there is nothing to report and nothing to drain: the
    ; skip loop consumes the rest of the line itself. Peeking here would run
    ; the preprocessor over the following %endif and swallow it.
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done

    ; "file:line: error: message"; the assembly goes on to report any
    ; further errors, but fails at the end
    extern  print_str
    mov     rdi, rbx
    mov     esi, 2
    call    prep_handle_message

.done:
    xor     rax, rax
    pop     rbx
    epilogue
