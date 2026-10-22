; ============================================================================
; File        : src/frontend/preproc/macro/contexts.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : raw tokens, macro labels, %unmacro, %strlen, %substr, %push / %pop
; ============================================================================


; ---- prep_raw_next ----------------------
;
; Reads the next token without expanding or interpreting it: from the active
; macro/%rep body when one is running, otherwise from the file. %rep captures
; its body with this, so a %rep written inside a macro copies the macro's
; tokens instead of running off into the source file.
;
; Input  : rdi = PrepState, rsi = destination Token
; Output : rax = EXIT_OK or error
;
prep_raw_next:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    mov     rax, [rbx + PREP_ctx]
    mov     r13, [rax + ASMCTX_mac_exp]
    test    r13, r13
    jz      .from_lexer

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .from_lexer                ; body exhausted: continue in the file

    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax
    mov     rdi, r12
    mov     rsi, r10
    copy_token
    inc     qword [r13 + MACROEXP_body]
    xor     rax, rax
    jmp     .done

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_label_macro ---------------------
;
; Is the token after the first word of a line (rsi) a multi-line macro's
; name? Then the word is a label: 2 when the macro's body has %00, which
; takes it (ml_pending00), 1 when it is defined where it stands; 0: no.
; Input    : rdi = PrepState, rsi = the first word's token
; Output   : eax
;
prep_label_macro:
    push    rbx
    push    r12
    push    r13
    sub     rsp, TOKEN_SIZE + 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    test    rax, rax
    jnz     .no
    cmp     byte [rsp + TOKEN_kind], TOK_IDENT
    jne     .no
    mov     rsi, [rsp + TOKEN_value]
    test    rsi, rsi
    jz      .no
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    test    rax, rax
    jz      .found
    cmp     dword [rel idefine_count], 0   ; %imacro: any case
    je      .no
    mov     rsi, [rsp + TOKEN_value]
    call    prep_icase_buf
    test    rax, rax
    jnz     .no
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel icase_buf]
    call    prep_symbol_find
    test    rax, rax
    jnz     .no
.found:
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .no
    mov     r13, [rdx + SYMBOL_value]
    test    r13, r13
    jz      .no
    test    byte [r13 + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
    jnz     .no
    ; does its body have %00?
    mov     rsi, [r13 + MACRO_tokens]
    mov     ecx, [r13 + MACRO_ntokens]
.scan:
    test    ecx, ecx
    jz      .defined_here
    cmp     byte [rsi + TOKEN_kind], TOK_DIRECTIVE
    jne     .scan_next
    mov     rdx, [rsi + TOKEN_value]
    test    rdx, rdx
    jz      .scan_next
    cmp     word [rdx], '00'
    jne     .scan_next
    cmp     byte [rdx + 2], 0
    je      .taken
.scan_next:
    add     rsi, TOKEN_SIZE
    dec     ecx
    jmp     .scan
.taken:
    mov     rax, [r12 + TOKEN_value]
    mov     [rel ml_pending00], rax
    mov     eax, 2
    jmp     .ret
.defined_here:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, TOKEN_SIZE + 8
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_raw_peek ----------------------
;
; prep_raw_peek
; Like prep_raw_next, without consuming the token: the next one of the
; current macro expansion, else of the file.
; Input    : rdi = PrepState, rsi = token to fill
; Output   : rax = EXIT_OK or error
;
prep_raw_peek:
    mov     rax, [rdi + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .from_lexer
    mov     rcx, [rax + MACROEXP_body]
    mov     r9, [rax + MACROEXP_macro]
    cmp     ecx, [r9 + MACRO_ntokens]
    jge     .from_lexer
    imul    rcx, TOKEN_SIZE
    add     rcx, [r9 + MACRO_tokens]
    push    rdi
    push    rsi
    mov     rdi, rsi
    mov     rsi, rcx
    copy_token
    pop     rsi
    pop     rdi
    xor     eax, eax
    ret
.from_lexer:
    mov     rdi, [rdi + PREP_lexer]
    jmp     lexer_peek

; ---- prep_handle_unmacro ----------------
;
; prep_handle_unmacro
; "%unmacro name nparams" (and the case-insensitive "%unimacro") removes a
; previously defined multi-line macro. The symbol table has no delete, so the
; entry is retired in place by clearing its kind -- the macro-call lookup in
; prep_internal_next only fires on SYM_MACRO, so an entry of any other kind is
; inert. Removing a name that is not a macro is not an error, matching NASM.
;
; The parameter count is required, and removes the overload with exactly
; that count ("%unmacro s 1" leaves "s 0" and "s 1+"), as in NASM.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_unmacro:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE        ; scratch token
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; 1. Macro name, taken straight from the lexer. Reading it through the
    ;    preprocessor would recognise the name as a macro *call* and expand
    ;    it, which is exactly what %macro avoids for the same reason.
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .done
    cmp     byte [rsp + TOKEN_kind], TOK_IDENT
    je      .named
    lea     rdi, [rel s_unmacro]           ; "`%unmacro' expects a macro name"
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_NAME
    jmp     .done
.named:
    mov     r12, [rsp + TOKEN_value]

    ; 2. The parameter count of the overload to remove
    lea     rdi, [rel s_unmacro]
    call    prep_parse_count
    test    rax, rax
    jnz     .done
    mov     r13, rcx
    mov     r14, rdx

    ; 3. Unlink that overload (a %define of the name stays)
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    extern  symbol_find
    call    prep_symbol_find
    test    rax, rax
    jnz     .drain
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .drain
    mov     r8, rdx                        ; the SYMBOL
    lea     r9, [rdx + SYMBOL_value]       ; where the current one is linked
.find:
    mov     r10, [r9]
    test    r10, r10
    jz      .drain                         ; no overload with that count
    test    byte [r10 + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .drain
    movzx   eax, word [r10 + MACRO_min_params]
    cmp     rax, r13
    jne     .next
    movzx   eax, word [r10 + MACRO_max_params]
    cmp     rax, r14
    jne     .next
    mov     al, [r10 + MACRO_flags]
    and     al, MACRO_FLAG_GREEDY
    cmp     al, [rel mdef_greedy]
    jne     .next
    mov     rax, [r10 + MACRO_next]
    mov     [r9], rax
    cmp     qword [r8 + SYMBOL_value], 0
    jne     .drain
    mov     byte [r8 + SYMBOL_kind], SYM_UNKNOWN   ; the last overload
    jmp     .drain
.next:
    lea     r9, [r10 + MACRO_next]
    jmp     .find

.drain:
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_drain_line --------------------
;
; Consumes what is left of the current directive's line, including the
; terminating newline, so the next directive starts on a clean stream.
; Directives that evaluate an expression stop *on* the newline and leave it
; in the peek slot instead; those use prep_drop_stale_newline.
;
; Input : rdi = PrepState
;
prep_drain_line:
    prologue
    push    rbx
    mov     rbx, rdi

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .eat_newline
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .loop

.eat_newline:
    mov     rdi, rbx
    call    preprocessor_next_token

.done:
    xor     rax, rax
    pop     rbx
    epilogue

; ---- prep_define_const ------------------
;
; Defines or re-defines a numeric constant, the way %assign does.
; Input : rdi = PrepState, rsi = name string, rdx = value
;
prep_define_const:
    prologue
    push    rbx
    push    r12
    push    r13
    sub     rsp, SYMBOL_SIZE
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    prep_symbol_find
    test    rax, rax
    jnz     .create
    mov     [rdx + SYMBOL_value], r13
    xor     rax, rax
    jmp     .done

.create:
    mov     rdi, rsp
    mov     rcx, (SYMBOL_SIZE / 8)
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rdi + SYMBOL_pflags], SYMF_ASSIGN
    mov     [rdi + SYMBOL_name], r12
    mov     [rdi + SYMBOL_value], r13

    mov     rsi, rdi
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_add

.done:
    add     rsp, SYMBOL_SIZE
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_strlen -----------------
;
; "%strlen NAME "text"" defines NAME as the length of the string.
;
prep_handle_strlen:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     eax, EXIT_DEFINE           ; "%strlen" with no name (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     eax, EXIT_DEFINE           ; "%strlen x": no string (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    call    prep_token_text            ; 'hello' is a packed character constant
    mov     rdi, rax                   ; string contents
    test    rdi, rdi
    jz      .empty
    call    str_len
    jmp     .define
.empty:
    xor     rax, rax

.define:
    mov     rdx, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_define_const
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_substr -----------------
;
; "%substr NAME "text" index" defines NAME as the character at the 1-based
; index. NASM yields a one-character string there; utasm stores the character
; code directly, which is how compile_time_hash consumes it.
;
prep_handle_substr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; %substr NAME string, start [, length]  (the commas may be left out)
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    mov     eax, EXIT_DEFINE           ; "%substr" with no name (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ret
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_token_text
    mov     r13, rax                   ; string contents
    test    r13, r13
    jnz     .have_text
    lea     r13, [rel dyn_no_file]     ; ""
.have_text:
    call    .skip_comma
    mov     rdi, rbx
    call    parser_evaluate_pp ; 1-based start
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    mov     r15, 1                     ; length: one character
    call    .skip_comma_peek
    test    eax, eax
    jz      .have_len
    mov     rdi, rbx
    call    parser_evaluate_pp
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
.have_len:
    mov     rdi, r13
    call    str_len                    ; rax = L
    ; a start below 1 is 1 (as NASM 2.16 does)
    test    r14, r14
    jg      .start_ok
    mov     r14d, 1
.start_ok:
    dec     r14                        ; 0-based
    ; a negative length ends that far from the end (-1: at the end)
    test    r15, r15
    jns     .len_ok
    mov     rcx, rax
    sub     rcx, r14
    lea     r15, [rcx + r15 + 1]
.len_ok:
    test    r14, r14
    jns     .clip
    add     r15, r14
    xor     r14d, r14d
.clip:
    cmp     r14, rax
    jb      .clip_len
    xor     r15d, r15d
    jmp     .build
.clip_len:
    mov     rcx, rax
    sub     rcx, r14
    cmp     r15, rcx
    jle     .nonneg
    mov     r15, rcx
.nonneg:
    test    r15, r15
    jns     .build
    xor     r15d, r15d
.build:
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r15 + 1]
    call    arena_alloc                ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    lea     rsi, [r13 + r14]
    mov     rcx, r15
    push    rdx
    rep movsb
    pop     rdx
    mov     rsi, rdx
    mov     rcx, r15
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; eax = 1 when an operand follows (after an optional comma)
.skip_comma_peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .no_more
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .no_more
    cmp     eax, TOK_EOF
    je      .no_more
    cmp     eax, TOK_COMMA
    jne     .more
    mov     rdi, rbx
    call    preprocessor_next_token
.more:
    mov     eax, 1
    ret
.no_more:
    xor     eax, eax
    ret
.skip_comma:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .sc_ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .sc_ret
    mov     rdi, rbx
    call    preprocessor_next_token
.sc_ret:
    ret

; ---- prep_token_text ------------------
;
; prep_token_text
; The text of a quoted token as a NUL-terminated string. A "..." string (or a
; '...' one longer than eight characters) already is one; a short '...' is a
; character constant whose characters are packed into TOKEN_value, so they
; are unpacked into an arena buffer.
; Input    : rdx = token, rbx = PrepState
; Output   : rax = the text (0 if none)
;
prep_token_text:
    cmp     byte [rdx + TOKEN_kind], TOK_CHAR
    je      .char
    mov     rax, [rdx + TOKEN_value]
    ret
.char:
    push    r12
    push    r13
    mov     r12, [rdx + TOKEN_value]
    movzx   r13d, word [rdx + TOKEN_len]
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 16
    call    arena_alloc                ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .none
    xor     ecx, ecx
.byte:
    cmp     ecx, r13d
    jae     .done
    cmp     ecx, 8
    jae     .done
    mov     [rdx + rcx], r12b
    shr     r12, 8
    inc     ecx
    jmp     .byte
.done:
    mov     rax, rdx
    pop     r13
    pop     r12
    ret
.none:
    xor     eax, eax
    pop     r13
    pop     r12
    ret

; ---- prep_drop_stale_newline ------------
;
; prep_drop_stale_newline
; Directives that evaluate an expression stop on the terminating NEWLINE and
; leave it in the peek slot. It belongs to the finished line, so the next
; directive that reads operands must not see it.
;
; Input    : rdi = pointer to PrepState
;
prep_drop_stale_newline:
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     .done
    cmp     byte [rdi + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .done
    mov     byte [rdi + PREP_has_peek], FALSE
.done:
    ret

; ---- prep_handle_push -------------------
;
; prep_handle_push
; "%push name" opens a context. Each context gets a unique id, which is what
; makes %$local names unique per IF/ENDIF pair.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_push:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     eax, [rbx + PREP_ctx_depth]
    cmp     eax, PREP_CTX_MAX
    jge     .overflow

    ; the context name is optional
    xor     r12, r12
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .store
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .store
    mov     r12, [rdx + TOKEN_value]

.store:
    ; its number from the macro calls' counter, as NASM numbers both
    mov     eax, [rbx + PREP_ctx_depth]
    mov     rdx, [rbx + PREP_ctx]
    mov     ecx, [rdx + ASMCTX_mac_exp_id]
    inc     dword [rdx + ASMCTX_mac_exp_id]
    mov     [rbx + PREP_ctx_ids + rax * 4], ecx
    lea     rdx, [rbx + PREP_ctx_names]
    mov     [rdx + rax * 8], r12
    inc     eax
    mov     [rbx + PREP_ctx_depth], eax

    xor     rax, rax
    jmp     .done

.overflow:
    mov     rax, EXIT_CTX_DEPTH

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_pop --------------------
;
; prep_handle_pop
; "%pop [name]" closes the innermost context.
;
prep_handle_pop:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; an optional context name may follow; it is not verified
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .drop
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .drop
    mov     rdi, rbx
    call    preprocessor_next_token

.drop:
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .underflow
    dec     eax
    mov     [rbx + PREP_ctx_depth], eax
    xor     rax, rax
    jmp     .done

.underflow:
    mov     rax, EXIT_MACRO_DEF

.done:
    pop     rbx
    epilogue
