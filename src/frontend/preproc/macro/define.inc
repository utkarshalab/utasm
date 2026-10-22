; ============================================================================
; File        : src/frontend/preproc/macro/define.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %define / %xdefine: parameters, marks, storing
; ============================================================================


; ---- prep_handle_def ------------------
;
; prep_handle_def
; "%define NAME body": NAME stands for the rest of the line, expanded where
; NAME is used (as in NASM, where a %define is text). The body is kept as a
; parameterless macro, so the expansion machinery that serves %macro calls
; serves it too. "%define NAME(a, b) body", with the parenthesis right
; after the name, takes arguments: NAME(1, 2); the parameter names in the
; body become %1, %2.
;
; The body is read with %1 / %%local substituted (inside a macro) but other
; macros left unexpanded, so it is expanded when used; %xdefine (def_eager)
; expands it now. A redefinition replaces the earlier body.
;
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_def:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    ; its body's directives are text, from the first token peeked on (the
    ; "(" of a function-like name is looked for before the body)
    mov     byte [rel def_capturing], 1

    ; An expression-evaluating directive can leave the terminating NEWLINE
    ; in the peek slot; it does not belong to this definition.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_stale_peek
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .no_stale_peek
    mov     byte [rbx + PREP_has_peek], FALSE
.no_stale_peek:

    ; 1. The name, never expanded: redefining must not expand the old body
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; r12 = name
    movzx   r13d, word [rdx + TOKEN_col]
    movzx   eax, word [rdx + TOKEN_len]
    add     r13d, eax                      ; the column right after the name
    mov     r14d, [rdx + TOKEN_line]

    ; %idefine: stored under a case-insensitive key
    cmp     byte [rel def_icase], 0
    je      .name_ready
    mov     rsi, r12
    call    prep_icase_buf
    test    rax, rax
    jnz     .bad
    lea     rdi, [rel icase_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r12, rdx
    mov     rdi, rdx
    lea     rsi, [rel icase_buf]
    call    str_concat
    inc     dword [rel idefine_count]
.name_ready:

    ; the body is expanded now only for %xdefine; that has to hold from the
    ; first peek on, which may already read the body's first token
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al

    ; 2. Parameters: "NAME(a, b)" with no blank before the parenthesis
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .body
    cmp     [rdx + TOKEN_line], r14d
    jne     .body
    cmp     [rdx + TOKEN_col], r13w
    jne     .body
    mov     byte [rel def_func], MACRO_FLAG_FUNC
    mov     rdi, rbx
    call    preprocessor_next_token        ; "("
    ; Each parameter may be empty ("ereg(foo,)", "myreg()") and marked
    ; (NASM 2.15): =x evaluated as a number (=x/u unsigned, =x/x hex ...),
    ; &x made a quoted string, &&x one unless it is one already, !x its
    ; braces kept, x+ greedy (the last, taking the commas after it)
.param_new:
    xor     r14d, r14d                     ; its marks (PF_*)
    mov     qword [rel def_pcur], 0        ; its name
    mov     byte [rel def_pcur_radix], 0
    mov     byte [rel def_radix_next], 0
.param:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_RPAREN
    je      .param_end
    cmp     eax, TOK_COMMA
    je      .param_end
    test    r14d, PF_GREEDY
    jnz     .bad                           ; "+" ends the parameter
    cmp     eax, TOK_IDENT
    je      .param_ident
    cmp     eax, TOK_EQUAL
    je      .param_eval
    cmp     eax, TOK_AMPERSAND
    je      .param_str
    cmp     eax, TOK_AND
    je      .param_condstr
    cmp     eax, TOK_NOT
    je      .param                         ; braces kept: they are anyway
    cmp     eax, TOK_PLUS
    je      .param_greedy
    cmp     eax, TOK_SLASH
    jne     .bad
    test    r14d, PF_EVAL
    jz      .bad                           ; a radix for a parameter without =
    mov     byte [rel def_radix_next], 1
    jmp     .param
.param_eval:
    or      r14d, PF_EVAL
    jmp     .param
.param_str:
    or      r14d, PF_STR
    jmp     .param
.param_condstr:
    or      r14d, PF_STR | PF_CONDSTR
    jmp     .param
.param_greedy:
    or      r14d, PF_GREEDY
    jmp     .param
.param_ident:
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rel def_radix_next], 0
    jne     .param_radix
    cmp     qword [rel def_pcur], 0
    jne     .bad                           ; two names
    mov     [rel def_pcur], rsi
    jmp     .param
.param_radix:
    ; "/x", "/ux", "/u": NASM's radix letters, u unsigned, s signed
    mov     byte [rel def_radix_next], 0
.radix_char:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .param
    inc     rsi
    mov     ecx, eax
    or      ecx, 0x20
    cmp     ecx, 'u'
    je      .radix_u
    cmp     ecx, 's'
    je      .radix_s
    lea     rdi, [rel def_radix_letters]
.radix_find:
    cmp     byte [rdi], 0
    je      .bad
    cmp     [rdi], cl
    je      .radix_ok
    inc     rdi
    jmp     .radix_find
.radix_ok:
    mov     [rel def_pcur_radix], al       ; as written: upper case, upper digits
    jmp     .radix_char
.radix_u:
    or      r14d, PF_UNSIGNED
    jmp     .radix_char
.radix_s:
    and     r14d, ~PF_UNSIGNED
    jmp     .radix_char
.param_end:
    movzx   ecx, byte [rel def_nparams]
    cmp     ecx, 9
    jae     .bad                           ; %1-%9
    mov     rsi, [rel def_pcur]
    lea     r8, [rel def_pnames]
    mov     [r8 + rcx*8], rsi              ; 0: an empty one, never named
    lea     r8, [rel def_pflags]
    mov     [r8 + rcx], r14b
    movzx   esi, byte [rel def_pcur_radix]
    lea     r8, [rel def_pradix]
    mov     [r8 + rcx], sil
    inc     byte [rel def_nparams]
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    je      .params_done
    test    r14d, PF_GREEDY
    jnz     .bad                           ; a greedy parameter must be last
    jmp     .param_new
.params_done:
    test    r14d, PF_GREEDY
    jz      .body
    or      byte [rel def_func], MACRO_FLAG_GREEDY

    ; 3. The body: the rest of the line
.body:
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al        ; %xdefine expands now
    mov     byte [rel def_capturing], 1    ; (its directives kept as text)
    xor     r15d, r15d                     ; tokens captured
    lea     rax, [rel def_scratch]
    mov     [rel def_toks], rax
    mov     qword [rel def_cap], DEFINE_MAX_TOKENS
.btok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .store
    cmp     eax, TOK_EOF
    je      .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     r15, [rel def_cap]
    jb      .def_room
    ; full: twice the size (the token just read is in the peek slot rdx
    ; points at, which the copy does not touch)
    push    rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel def_toks]
    mov     edx, r15d
    mov     rcx, [rel def_cap]
    call    prep_tokbuf_grow
    mov     rdi, rdx
    pop     rdx
    test    rax, rax
    jnz     .fail
    mov     [rel def_toks], rdi
    mov     [rel def_cap], rcx
.def_room:
    mov     eax, r15d
    imul    eax, eax, TOKEN_SIZE
    mov     rdi, [rel def_toks]
    add     rdi, rax
    mov     r8, rdi                        ; r8 = the captured token
    mov     rsi, rdx
    copy_token
    inc     r15d
    ; a parameter name becomes a %N reference
    cmp     byte [r8 + TOKEN_kind], TOK_IDENT
    jne     .btok
    xor     r14d, r14d
.pname:
    movzx   eax, byte [rel def_nparams]
    cmp     r14d, eax
    jae     .btok
    lea     rax, [rel def_pnames]
    mov     rsi, [rax + r14*8]
    test    rsi, rsi
    jz      .pname_next                    ; an empty parameter: never used
    push    r8
    mov     rdi, [r8 + TOKEN_value]
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .is_param
.pname_next:
    inc     r14d
    jmp     .pname
.is_param:
    mov     byte [r8 + TOKEN_kind], TOK_DIRECTIVE
    lea     rax, [rel def_digits]
    lea     rax, [rax + r14*2 + 2]         ; "1".."9"
    mov     [r8 + TOKEN_value], rax
    jmp     .btok

    ; 4. A MACRO with the captured tokens, under NAME
.store:
    mov     byte [rel prep_noexpand], 0
    mov     byte [rel def_capturing], 0
    call    prep_def_marks
    test    rax, rax
    jnz     .fail
    call    prep_define_store
    jmp     .ret

.bad:
    mov     rax, EXIT_DEFINE
.fail:
    mov     byte [rel prep_noexpand], 0
    mov     byte [rel def_capturing], 0
.ret:
    mov     byte [rel def_capturing], 0
    lea     rcx, [rel def_scratch]
    mov     [rel def_toks], rcx            ; for the one-token definitions
    mov     byte [rel def_eager], 0
    mov     byte [rel def_icase], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_def_marks ------------------
;
; prep_def_marks
; A %define's marked parameters (=x, &x, &&x): each reference to one in
; the body becomes a call of the function doing that to the argument,
; evaluated when the macro is: %eval(%N) (or %=(%N) for a radix or
; unsigned, the marks in def_pflags / def_pradix of the parameter),
; %str(%N), %strcat(%N) - NASM's evaluation, quoting, and quoting unless
; it is a string already.
; Input    : rbx = PrepState, r15d = the body's tokens (def_toks)
; Output   : rax = EXIT_OK or error; def_toks / r15d the new body
;
prep_def_marks:
    push    r12
    push    r13
    push    r14
    ; any marked parameter?
    movzx   ecx, byte [rel def_nparams]
    lea     rdx, [rel def_pflags]
.any:
    test    ecx, ecx
    jz      .none
    dec     ecx
    test    byte [rdx + rcx], PF_EVAL | PF_STR
    jz      .any
    ; room for the worst: each token a reference wrapped in two calls
    lea     esi, [r15d * 8 + 8]
    imul    esi, esi, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r12, rdx                       ; r12 = the new body
    xor     r13d, r13d                     ; r13 = its tokens
    xor     r14d, r14d                     ; r14 = the old body's index
.tok:
    cmp     r14d, r15d
    jae     .done
    mov     eax, r14d
    imul    eax, eax, TOKEN_SIZE
    mov     rsi, [rel def_toks]
    add     rsi, rax                       ; rsi = the token
    inc     r14d
    ; a parameter reference: a directive whose text is one of def_digits
    cmp     byte [rsi + TOKEN_kind], TOK_DIRECTIVE
    jne     .copy
    mov     rax, [rsi + TOKEN_value]
    lea     rcx, [rel def_digits + 2]
    sub     rax, rcx
    cmp     rax, 18
    jae     .copy
    shr     eax, 1                         ; the parameter
    lea     rcx, [rel def_pflags]
    movzx   r8d, byte [rcx + rax]
    test    r8d, PF_EVAL | PF_STR
    jz      .copy
    lea     rcx, [rel def_pradix]
    movzx   r9d, byte [rcx + rax]
    ; the calls, outermost first: the string one, then the evaluation
    xor     r10d, r10d                     ; ")" to close
    test    r8d, PF_STR
    jz      .no_str
    lea     rax, [rel s_fn_str]
    test    r8d, PF_CONDSTR
    jz      .str_call
    lea     rax, [rel s_fn_condstr]
.str_call:
    call    .call_open
    inc     r10d
.no_str:
    test    r8d, PF_EVAL
    jz      .ref
    lea     rax, [rel s_fn_eval]
    test    r9d, r9d
    jnz     .radix_call
    test    r8d, PF_UNSIGNED
    jz      .eval_call
.radix_call:
    ; %=(%N): prep_function reads the radix and sign from its name
    lea     rax, [rel s_fn_radix]
    test    r9d, r9d
    jnz     .radix_letter
    mov     r9d, '-'                       ; decimal, no prefix
.radix_letter:
    mov     [rax + 1], r9b
    mov     byte [rax + 2], 's'
    test    r8d, PF_UNSIGNED
    jz      .radix_name
    mov     byte [rax + 2], 'u'
.radix_name:
    push    rsi
    push    r8
    push    r9
    push    r10
    mov     rdi, [rbx + PREP_arena]
    mov     esi, 4
    call    arena_alloc
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     eax, [rel s_fn_radix]
    mov     [rdx], eax
    mov     rax, rdx
.eval_call:
    call    .call_open
    inc     r10d
.ref:
    call    .put
.close:
    test    r10d, r10d
    jz      .tok
    mov     al, TOK_RPAREN
    call    .put_punct
    dec     r10d
    jmp     .close
.copy:
    call    .put
    jmp     .tok
.done:
    mov     [rel def_toks], r12
    mov     r15d, r13d
.none:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; .put: the token rsi, appended (rsi kept)
.put:
    mov     eax, r13d
    imul    eax, eax, TOKEN_SIZE
    lea     rdi, [r12 + rax]
    push    rsi
    copy_token
    pop     rsi
    inc     r13d
    ret
; .call_open: "%name(" - the directive rax and a "(", placed as rsi is
.call_open:
    push    rax
    call    .put
    pop     rax
    mov     ecx, r13d
    dec     ecx
    imul    ecx, ecx, TOKEN_SIZE
    mov     [r12 + rcx + TOKEN_value], rax
    mov     byte [r12 + rcx + TOKEN_kind], TOK_DIRECTIVE
    mov     al, TOK_LPAREN
; .put_punct: a punctuation token al, placed as rsi is
.put_punct:
    push    rax
    call    .put
    pop     rax
    mov     ecx, r13d
    dec     ecx
    imul    ecx, ecx, TOKEN_SIZE
    mov     [r12 + rcx + TOKEN_kind], al
    mov     qword [r12 + rcx + TOKEN_value], 0
    mov     word [r12 + rcx + TOKEN_len], 1
    ret

; ---- prep_define_store ------------------
;
; prep_define_store
; Stores a %define: a MACRO holding the tokens in def_toks, under the
; name. A redefinition replaces the earlier body.
; Input    : rbx = PrepState, r12 = name, r15d = token count;
;            def_nparams / def_func describe the parameters
; Output   : rax = EXIT_OK or error
;
prep_define_store:
    push    r13
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r13, rdx
    mov     byte [r13 + MACRO_tag], TAG_MACRO
    movzx   eax, byte [rel def_nparams]
    mov     [r13 + MACRO_max_params], ax
    test    byte [rel def_func], MACRO_FLAG_GREEDY
    jz      .min_set
    dec     eax                            ; "c+": may be left out
.min_set:
    mov     [r13 + MACRO_min_params], ax
    movzx   eax, byte [rel def_func]
    or      eax, MACRO_FLAG_DEFINE
    mov     [r13 + MACRO_flags], al
    mov     [r13 + MACRO_name], r12
    mov     [r13 + MACRO_ntokens], r15d
    mov     eax, r15d
    inc     eax
    imul    esi, eax, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     [r13 + MACRO_tokens], rdx
    mov     rdi, rdx
    mov     rsi, [rel def_toks]            ; def_scratch, or a bigger array
    mov     eax, r15d
    imul    ecx, eax, TOKEN_SIZE / 8
    rep movsq

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    prep_symbol_find
    test    rax, rax
    jnz     .create
    ; "X equ 2" then "%define X 2": a macro and a symbol are apart in NASM;
    ; the entry becomes the macro and keeps the constant's value for after
    ; the preprocessor (prep_unshadow)
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .overload
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .redefine
    mov     rax, [rdx + SYMBOL_value]
    mov     [rdx + SYMBOL_size], rax
    or      byte [rdx + SYMBOL_pflags], SYMF_SHADOW
    jmp     .redefine
.overload:
    ; "%define f(x)" then "%define f(x, y)": both, chosen by the argument
    ; count when called; one taking as many as the new one is replaced
    mov     rcx, [rdx + SYMBOL_value]
    test    rcx, rcx
    jz      .redefine
    test    byte [rcx + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .redefine
    test    byte [rcx + MACRO_flags], MACRO_FLAG_FUNC
    jz      .redefine
    test    byte [r13 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .redefine
    lea     r8, [rdx + SYMBOL_value]       ; r8 = the link to rcx
.ov_walk:
    mov     ax, [rcx + MACRO_min_params]
    cmp     ax, [r13 + MACRO_min_params]
    jne     .ov_next
    mov     ax, [rcx + MACRO_max_params]
    cmp     ax, [r13 + MACRO_max_params]
    jne     .ov_next
    mov     rax, [rcx + MACRO_next]        ; the same arity: in its place
    mov     [r13 + MACRO_next], rax
    mov     [r8], r13
    xor     eax, eax
    jmp     .ret
.ov_next:
    lea     r8, [rcx + MACRO_next]
    mov     rcx, [rcx + MACRO_next]
    test    rcx, rcx
    jnz     .ov_walk
    mov     rax, [rdx + SYMBOL_value]      ; a new arity: first in the chain
    mov     [r13 + MACRO_next], rax
    mov     [rdx + SYMBOL_value], r13
    xor     eax, eax
    jmp     .ret
.redefine:
    mov     byte [rdx + SYMBOL_kind], SYM_MACRO    ; a redefinition
    mov     [rdx + SYMBOL_value], r13
    xor     eax, eax
    jmp     .ret
.create:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    mov     rcx, SYMBOL_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_MACRO
    mov     [rsp + SYMBOL_name], r12
    mov     [rsp + SYMBOL_value], r13
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    prep_symbol_add
    add     rsp, SYMBOL_SIZE
.fail:
.ret:
    pop     r13
    ret
