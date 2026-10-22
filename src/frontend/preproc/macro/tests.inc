; ============================================================================
; File        : src/frontend/preproc/macro/tests.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %ifdef-style tests, %defstr, %iassign, %repl, %getenv, %stacksize, %arg / %local frames, condition-code inverses
; ============================================================================


; ---- %ifnum / %ifstr / %ifid / %ifempty / %ifmacro / %ifdef ----
;
; prep_handle_iftest
; What the operand is: a number, a string, an identifier, nothing, the
; name of a multi-line macro, or the name of a single-line one (%ifdef:
; %define, %assign and the like, and the dynamic __LINE__, __FILE__, ...;
; a label is not). The rest of the line belongs to the directive.
; Input    : rdi = PrepState, esi = IFT_*, edx = bit 0 negate, bit 1 %elif
;
prep_handle_iftest:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    movzx   r14d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0    ; read it even when skipping
    mov     rdi, rbx
    call    prep_drop_stale_newline
    cmp     r12d, IFT_MACRO
    jb      .peek
    cmp     r12d, IFT_TOKEN                    ; (%iftoken: the expansion, as NASM -
    je      .peek                              ;  an empty %define is no token)
    mov     byte [rel prep_noexpand], 1        ; a name, not its expansion
.peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .restore
    xor     r15d, r15d
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     r12d, IFT_TOKEN
    jne     .t_empty
    ; one token, then the end of the line
    cmp     eax, TOK_NEWLINE
    je      .decided
    cmp     eax, TOK_EOF
    je      .decided
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .restore
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .true
    cmp     eax, TOK_EOF
    je      .true
    jmp     .decided
.t_empty:
    cmp     r12d, IFT_EMPTY
    jne     .t_num
    cmp     eax, TOK_NEWLINE
    je      .true
    cmp     eax, TOK_EOF
    je      .true
    jmp     .decided
.t_num:
    cmp     r12d, IFT_NUM
    jne     .t_str
    cmp     eax, TOK_NUMBER
    je      .true
    jmp     .decided
.t_str:
    cmp     r12d, IFT_STR
    jne     .t_id
    cmp     eax, TOK_STRING
    je      .true
    cmp     eax, TOK_CHAR
    je      .true
    jmp     .decided
.t_id:
    cmp     r12d, IFT_ID
    jne     .t_macro
    cmp     eax, TOK_IDENT
    je      .true
    jmp     .decided
.t_macro:
    cmp     r12d, IFT_ALIAS
    je      .t_alias
    cmp     r12d, IFT_DEF
    je      .t_def
    cmp     r12d, IFT_CTX
    je      .t_ctx
    cmp     r12d, IFT_ENV
    je      .t_env
    cmp     eax, TOK_IDENT
    je      .t_macro_name
    ; "%ifmacro" with no name (or a number, a string): "`%ifmacro' expects
    ; a macro name", as NASM; %elifmacro takes it as false, and so does a
    ; branch being skipped
    test    r13d, 2
    jz      .t_macro_if
    mov     byte [rel cond_never_pending], 1   ; %elifmacro: COND_NEVER
    jmp     .decided
.t_macro_if:
    test    r14d, r14d
    jnz     .decided
    lea     rdi, [rel s_ifmacro]
    test    r13d, 1
    jz      .t_macro_subject
    lea     rdi, [rel s_ifnmacro]
.t_macro_subject:
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_NAME
    jmp     .restore
.t_macro_name:
    mov     rsi, [rdx + TOKEN_value]
    push    rsi
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    pop     rsi
    test    rax, rax
    jnz     .t_builtin
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .t_builtin
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .tm_found
.t_builtin:
    ; none of the source's: NASM's directives that are macros of its own
    ; ("%ifmacro org" is true in -f bin)
    mov     rdi, rbx
    call    prep_builtin_macro
    test    eax, eax
    jz      .decided
    mov     [rel builtin_min], cx
    mov     [rel builtin_max], dx
    mov     eax, 1                         ; (not a MACRO*: builtin_min / max)
.tm_found:
    ; "%ifmacro m 2", "m 1-3", "m 1-*": one of that name taking such a
    ; count (overloads by MACRO_next); with no count, any
    push    rax                            ; [rsp + 16] the macro
    push    0                              ; [rsp + 8] the count from
    push    MACRO_VARIADIC                 ; [rsp] ... to
    mov     rdi, rbx
    call    preprocessor_next_token        ; the name
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .tm_check
    mov     rdi, [rdx + TOKEN_value]       ; (its text)
    call    str_to_int
    test    rax, rax
    jnz     .tm_check
    mov     [rsp + 8], rdx
    mov     [rsp], rdx
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_PLUS
    je      .tm_plus                       ; "m 1+": 1 or more, as NASM
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    jne     .tm_check
    mov     rdi, rbx
    call    preprocessor_next_token        ; the '-'
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_STAR
    je      .tm_any
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .tm_check
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    test    rax, rax
    jnz     .tm_check
    mov     [rsp], rdx
    jmp     .tm_take
.tm_plus:
.tm_any:
    mov     qword [rsp], MACRO_VARIADIC
.tm_take:
    mov     rdi, rbx
    call    preprocessor_next_token
.tm_check:
    mov     rax, [rsp + 16]
.tm_macro:
    test    rax, rax
    jz      .tm_none
    cmp     rax, 1
    je      .tm_builtin
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     rcx, [rsp]
    ja      .tm_next                       ; takes more than asked
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     rcx, [rsp + 8]
    jb      .tm_next                       ; takes fewer
    add     rsp, 24
    jmp     .true
.tm_next:
    mov     rax, [rax + MACRO_next]
    jmp     .tm_macro
.tm_builtin:
    movzx   ecx, word [rel builtin_min]
    cmp     rcx, [rsp]
    ja      .tm_none
    movzx   ecx, word [rel builtin_max]
    cmp     rcx, [rsp + 8]
    jb      .tm_none
    add     rsp, 24
    jmp     .true
.tm_none:
    add     rsp, 24
    jmp     .decided
.t_def:
    cmp     eax, TOK_IDENT
    jne     .decided
    push    rdx
    mov     rsi, [rdx + TOKEN_value]
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    test    rax, rax
    jnz     .t_dynamic
    pop     rax
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jnz     .true                          ; %assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .decided
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .true
    jmp     .decided
.t_alias:
    cmp     eax, TOK_IDENT
    jne     .decided
    mov     rsi, [rdx + TOKEN_value]
    call    alias_slot
    cmp     eax, -1
    jne     .true
    jmp     .decided
.t_env:
    ; "%ifenv NAME" / "%ifenv 'NAME'": set in the environment
    cmp     eax, TOK_IDENT
    je      .t_env_name
    cmp     eax, TOK_STRING
    jne     .decided
.t_env_name:
    mov     rdi, [rdx + TOKEN_value]
    call    prep_getenv
    test    rax, rax
    jnz     .true
    jmp     .decided
.t_ctx:
    ; the name of the innermost %push context
    cmp     eax, TOK_IDENT
    jne     .decided
    mov     ecx, [rbx + PREP_ctx_depth]
    test    ecx, ecx
    jz      .decided
    dec     ecx
    lea     rax, [rbx + PREP_ctx_names]
    mov     rsi, [rax + rcx * 8]
    test    rsi, rsi
    jz      .decided
    mov     rdi, [rdx + TOKEN_value]
    call    str_cmp
    test    rax, rax
    jz      .true
    jmp     .decided
.t_dynamic:
    ; __LINE__, __FILE__, __BITS__ ...: made up as they are used
    lea     r8, [rel dyn_table]
.t_dyn_name:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .t_dyn_none
    mov     rdi, [rsp]
    mov     rdi, [rdi + TOKEN_value]
    push    r8
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .t_dyn_hit
    add     r8, 16
    jmp     .t_dyn_name
.t_dyn_hit:
    pop     rdx
    jmp     .true
.t_dyn_none:
    pop     rdx
    jmp     .decided
.true:
    mov     r15d, 1
.decided:
.drain:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .restore
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .drained
    cmp     eax, TOK_EOF
    je      .drained
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .drain
.drained:
    mov     [rbx + PREP_skip_depth], r14w
    test    r13d, 1
    jz      .enter
    xor     r15d, 1
.enter:
    mov     esi, r15d
    mov     rdi, rbx
    test    r13d, 2
    jnz     .elif
    call    prep_cond_enter
    jmp     .ret
.elif:
    cmp     byte [rel cond_never_pending], 0
    jne     .elif_never
    call    prep_cond_branch
    jmp     .ret
.elif_never:
    mov     byte [rel cond_never_pending], 0
    call    prep_cond_never
    jmp     .ret
.restore:
    mov     [rbx + PREP_skip_depth], r14w
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; prep_icase_key
; The key a case-insensitive name is stored under, in the arena; from now
; on lookups also try it (idefine_count).
; Input    : rbx = PrepState, rsi = name
; Output   : rax = EXIT_OK or error, rdx = the key
;
prep_icase_key:
    call    prep_icase_buf
    test    rax, rax
    jnz     .bad
    lea     rdi, [rel icase_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rdi, rdx
    lea     rsi, [rel icase_buf]
    call    str_concat
    pop     rdx
    inc     dword [rel idefine_count]
    xor     eax, eax
.ret:
    ret
.bad:
    mov     rax, EXIT_DEFINE
    ret

; ---- %defstr / %idefstr ------------------
;
; "%defstr NAME text" defines NAME as the string of the rest of the line
; (spaced as in the source).
; Input    : rdi = PrepState, esi = 1 for %idefstr
;
prep_handle_defstr:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     r13d, esi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    test    r13d, r13d
    jz      .have_name
    mov     rsi, r12
    call    prep_icase_key
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
.have_name:
    lea     rdi, [rel idn_left]
    mov     esi, 2                         ; the source's spacing
    call    prep_idn_collect
    test    rax, rax
    jnz     .ret
    push    rdx                            ; the text
    mov     rdi, rdx
    call    str_len
    mov     r13, rax
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, rdx
    call    str_concat
    mov     rsi, r15
    mov     rcx, r13
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    jmp     .ret
.bad:
    mov     rax, EXIT_DEFINE
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- %iassign ---------------------------
;
; "%iassign NAME expr": %assign whose name matches in any case (stored as
; a case-insensitive single-line macro holding the value).
;
prep_handle_iassign:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    prep_icase_key
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    mov     rdi, rbx
    call    parser_evaluate_pp
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, rdx
    mov     rsi, r13
    call    str_int_to_str
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     byte [rel def_scratch + TOKEN_kind], TOK_NUMBER
    mov     [rel def_scratch + TOKEN_value], r15
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    jmp     .ret
.bad:
    mov     rax, EXIT_DEFINE
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- %repl ------------------------------
;
; "%repl name" renames the innermost context.
;
prep_handle_repl:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    xor     r12d, r12d
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, [rdx + TOKEN_value]
.store:
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .bad
    dec     eax
    lea     rdx, [rbx + PREP_ctx_names]
    mov     [rdx + rax * 8], r12
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret
.bad:
    mov     rax, EXIT_MACRO_DEF
    jmp     .ret

; ---- prep_getenv ------------------------
;
; prep_getenv
; Input    : rdi = a variable's name
; Output   : rax = its value (after the '='), 0 when it is not set
;
prep_getenv:
    push    rbx
    push    r12
    extern  utasm_envp
    mov     rbx, [rel utasm_envp]
    test    rbx, rbx
    jz      .none
.var:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .none
    mov     r12, rdi
.cmp:
    movzx   eax, byte [r12]
    test    eax, eax
    jz      .name_end
    cmp     al, [rsi]
    jne     .next
    inc     r12
    inc     rsi
    jmp     .cmp
.name_end:
    cmp     byte [rsi], '='
    jne     .next
    lea     rax, [rsi + 1]
    jmp     .ret
.next:
    add     rbx, 8
    jmp     .var
.none:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret

; ---- %stacksize / %arg / %local ---------
;
; NASM's stack frame helpers. "%stacksize flat | flat64 | large | small"
; sets the frame register, the slot size and where arguments start:
;
;   flat    ebp, 4, [ebp+8]       large   bp, 2, [bp+4]
;   flat64  rbp, 8, [rbp+16]      small   bp, 2, [bp+6]
;
; (flat until one is given). "%arg a:dword, b:word" defines each name as
; the next argument's address, "ebp+8", "ebp+12"; "%local x:dword" as the
; next local's, "ebp-4", and adds its size to %$localsize (NASM writes
; "(ebp+8)": utasm's addresses take no registers in parentheses). A
; type (byte, word, dword, qword, tword) takes at least one slot. The
; definitions are read as text, after the line.
;
prep_handle_stacksize:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    lea     r8, [rel stk_modes]
.mode:
    cmp     byte [r8], 0
    je      .bad
    push    r8
    mov     rdi, r12
    mov     rsi, r8
    call    prep_str_cmp_ci
    pop     r8
    test    rax, rax
    jz      .hit
    add     r8, 16
    jmp     .mode
.hit:
    movzx   eax, byte [r8 + 8]
    mov     [rel stk_size], eax
    movzx   eax, byte [r8 + 9]
    mov     [rel stk_arg], eax
    mov     dword [rel stk_local], 0
    lea     rax, [r8 + 10]
    mov     [rel stk_reg], rax
    mov     rdi, rbx
    call    prep_drain_line
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r12
    pop     rbx
    ret

; esi = 0 %arg, 1 %local
prep_handle_frame:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r14d, esi
    lea     r15, [rel stk_text]
    mov     byte [r15], 10                 ; ends the directive's line
    inc     r15
.item:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     r12, [rdx + TOKEN_value]       ; the name
    cmp     eax, TOK_LABEL                 ; "a:dword"
    je      .type
    cmp     eax, TOK_IDENT                 ; "a : dword"
    jne     .bad
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .bad
.type:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r13, [rdx + TOKEN_value]
    lea     r8, [rel stk_types]
.size:
    cmp     byte [r8], 0
    je      .bad
    push    r8
    mov     rdi, r13
    mov     rsi, r8
    call    prep_str_cmp_ci
    pop     r8
    test    rax, rax
    jz      .sized
    add     r8, 8
    jmp     .size
.sized:
    movzx   r13d, byte [r8 + 7]
    cmp     r13d, [rel stk_size]
    jae     .slot
    mov     r13d, [rel stk_size]           ; at least one slot
.slot:
    lea     rax, [rel stk_text + STK_TEXT - 192]
    cmp     r15, rax
    jae     .bad                           ; too many on one line
    ; "%define NAME REG+OFFSET" / "REG-OFFSET"
    lea     rsi, [rel stk_define]
    call    .put
    mov     rsi, r12
    call    .put
    mov     byte [r15], ' '
    inc     r15
    mov     rsi, [rel stk_reg]
    call    .put
    test    r14d, r14d
    jnz     .local
    mov     byte [r15], '+'
    inc     r15
    mov     eax, [rel stk_arg]
    add     [rel stk_arg], r13d
    call    .num
    mov     byte [r15], 10
    inc     r15
    jmp     .next
.local:
    mov     byte [r15], '-'
    inc     r15
    add     [rel stk_local], r13d
    mov     eax, [rel stk_local]
    call    .num
    mov     byte [r15], 10
    inc     r15
    lea     rsi, [rel stk_assign]          ; %$localsize grows with it
    call    .put
    mov     eax, r13d
    call    .num
    mov     byte [r15], 10
    inc     r15
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .end
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .item
.end:
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .push
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    jne     .bad
.push:
    mov     rdi, rbx
    lea     rsi, [rel stk_text]
    mov     rdx, r15
    sub     rdx, rsi
    lea     rcx, [rel dir_arg]
    test    r14d, r14d
    jz      .named
    lea     rcx, [rel dir_local]
.named:
    call    prep_push_buffer
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

    ; appends the string rsi
.put:
    mov     al, [rsi]
    test    al, al
    jz      .put_end
    mov     [r15], al
    inc     rsi
    inc     r15
    jmp     .put
.put_end:
    ret

    ; appends eax in decimal
.num:
    sub     rsp, 16
    lea     r8, [rsp + 15]
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    mov     [r8], dl
    dec     r8
    test    eax, eax
    jnz     .digit
.copy:
    inc     r8
    lea     rax, [rsp + 16]
    cmp     r8, rax
    jae     .num_end
    mov     al, [r8]
    mov     [r15], al
    inc     r15
    jmp     .copy
.num_end:
    add     rsp, 16
    ret

; ---- prep_is_macro_open ----------------
;
; ZF set when the directive name rdi opens a macro definition other than
; %macro itself: %rmacro, %imacro, %irmacro (the nesting scans count them).
;
prep_is_macro_open:
    push    rdi
    lea     rsi, [rel dir_rmacro]
    call    str_cmp
    test    rax, rax
    jz      .ret
    mov     rdi, [rsp]
    lea     rsi, [rel dir_imacro]
    call    str_cmp
    test    rax, rax
    jz      .ret
    mov     rdi, [rsp]
    lea     rsi, [rel dir_irmacro]
    call    str_cmp
    test    rax, rax
.ret:
    pop     rdi
    ret

; ---- prep_define_string -----------------
;
; prep_define_string
; Defines a single-line macro as a quoted string (%pathsearch, as %defstr
; would).
; Input    : rdi = PrepState, rsi = name, rdx = the string
; Output   : rax = EXIT_OK or error
;
prep_define_string:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     rdi, r13
    call    str_len
    mov     rcx, rax
    mov     rsi, r13
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_cc_inverse ----------------------
; The condition code that is the other way of the one at rdi (NASM's
; %-1: z gives nz, a gives be), or rax = 0 when it is none.
prep_cc_inverse:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel cc_inverses]
.next:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    mov     rdi, r13
    push    rax
    call    str_len
    lea     r13, [r13 + rax + 1]           ; its inverse
    pop     rax
    test    rax, rax
    jz      .found
    mov     rdi, r13
    call    str_len
    lea     r13, [r13 + rax + 1]
    jmp     .next
.found:
    mov     rax, r13
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
; condition codes and the other way of each (name, 0, inverse, 0)
cc_inverses:
    db "a", 0, "be", 0
    db "ae", 0, "b", 0
    db "b", 0, "ae", 0
    db "be", 0, "a", 0
    db "c", 0, "nc", 0
    db "e", 0, "ne", 0
    db "g", 0, "le", 0
    db "ge", 0, "l", 0
    db "l", 0, "ge", 0
    db "le", 0, "g", 0
    db "na", 0, "a", 0
    db "nae", 0, "ae", 0
    db "nb", 0, "b", 0
    db "nbe", 0, "be", 0
    db "nc", 0, "c", 0
    db "ne", 0, "e", 0
    db "ng", 0, "g", 0
    db "nge", 0, "ge", 0
    db "nl", 0, "l", 0
    db "nle", 0, "le", 0
    db "no", 0, "o", 0
    db "np", 0, "p", 0
    db "ns", 0, "s", 0
    db "nz", 0, "z", 0
    db "o", 0, "no", 0
    db "p", 0, "np", 0
    db "pe", 0, "po", 0
    db "po", 0, "pe", 0
    db "s", 0, "ns", 0
    db "z", 0, "nz", 0
    db 0
[SECTION .text]

; ---- prep_interp_standalone ----------------
;
; prep_interp_standalone
; "%[...]" written on its own: NASM reads the tokens inside, macros
; expanded there and then - in a %define's body or a %rep line, the value
; of the moment. They are lexed from the text inside the brackets; a name
; that is a %define with no parameters gives its tokens, an %assign its
; value (one level: what they give expands as it is read). The first takes
; the place of the token, the others come right after it (an anonymous,
; %define-like expansion that reads nothing of the line).
; Input    : rbx = PrepState, rsi = the token ("%[...]" in TOKEN_value)
; Output   : rax = EXIT_OK or an error; edx = 1 when there is no token
;            (the token is to be dropped)
;
prep_interp_standalone:
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    mov     r12, rsi
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_INTERP
    ; the text inside: past "%[", up to the last ']'
    mov     r13, [r12 + TOKEN_value]
    add     r13, 2
    mov     rdi, r13
    call    str_len
    mov     rdx, rax
    test    rdx, rdx
    jz      .lexed_none
    cmp     byte [r13 + rdx - 1], ']'
    jne     .text_len
    dec     rdx
.text_len:
    ; its own lexer
    push    rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; r14 = the lexer
    mov     rdi, r14
    mov     rsi, r13
    mov     rdx, rcx
    mov     rcx, [r12 + TOKEN_file]
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [rbx + PREP_arena]
    call    lexer_init
    test    rax, rax
    jnz     .ret
    ; the output (it grows)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE * 16
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; r13 = the output
    mov     qword [rel relex_cap], 16
    xor     r15d, r15d                     ; r15 = how many
.token:
    lea     rsi, [rel relex_tok]
    mov     rdi, r14
    call    lexer_next
    test    rax, rax
    jnz     .ret
    lea     rbp, [rel relex_tok]           ; rbp = the token read
    movzx   eax, byte [rbp + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .lexed
    cmp     eax, TOK_EOF
    je      .lexed
    ; where the %[...] was written (messages, the listing)
    mov     eax, [r12 + TOKEN_line]
    mov     [rbp + TOKEN_line], eax
    mov     ax, [r12 + TOKEN_col]
    mov     [rbp + TOKEN_col], ax
    mov     rax, [r12 + TOKEN_file]
    mov     [rbp + TOKEN_file], rax
    cmp     byte [rbp + TOKEN_kind], TOK_IDENT
    jne     .put_it
    ; "%[foo%[foo3]bar]": the name inside is pasted first (foo33bar)
    test    byte [rbp + TOKEN_flags], TOK_FLAG_INTERP
    jz      .name_plain
    and     byte [rbp + TOKEN_flags], ~TOK_FLAG_INTERP
    mov     rdi, rbx
    mov     rsi, rbp
    call    prep_resolve_interp
    test    rax, rax
    jnz     .ret
.name_plain:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rbp + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .put_it
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    je      .assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .put_it
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .put_it
    test    byte [rax + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .put_it
    ; a %define: its tokens
    mov     r8, [rax + MACRO_tokens]
    mov     r9d, [rax + MACRO_ntokens]
.body:
    test    r9d, r9d
    jz      .token
    push    r8
    push    r9
    mov     rbp, r8
    call    .append
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .ret
    add     r8, TOKEN_SIZE
    dec     r9d
    jmp     .body
.assign:
    ; an %assign: its value, a number
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    push    rdx
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rdi, rdx
    mov     rsi, [rcx + SYMBOL_value]
    call    str_int_to_str
    pop     rdx
    mov     byte [rbp + TOKEN_kind], TOK_NUMBER
    mov     [rbp + TOKEN_value], rdx
.put_it:
    call    .append
    test    rax, rax
    jnz     .ret
    jmp     .token
.lexed:
    xor     eax, eax
    test    r15, r15
    jnz     .some
.lexed_none:
    xor     eax, eax
    mov     edx, 1                         ; nothing: the token goes
    jmp     .out
.some:
    ; the first in its place, when it is the only one, with the token's
    ; blank before it (-E, %str)
    movzx   r8d, byte [r12 + TOKEN_flags]
    and     r8d, TOK_FLAG_SPACE
    mov     rdi, r12
    mov     rsi, r13
    copy_token
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_SPACE
    or      [r12 + TOKEN_flags], r8b
    or      r8d, 0x80
    mov     [rel exp_lead], r8b            ; (the expansion's first, else)
    cmp     r15, 1
    je      .one
    ; else all of them as an expansion of their own, so "%[r %+ %2]" is
    ; pasted as a body's "%+" is (.check_concat), the token dropped
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_DEFINE
    mov     qword [rdx + MACRO_name], 0
    mov     [rdx + MACRO_tokens], r13
    mov     [rdx + MACRO_ntokens], r15d
    mov     rdi, rbx
    mov     rsi, rdx
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
    mov     edx, 1                         ; (they follow; this token goes)
    jmp     .out
.one:
    mov     byte [rel exp_lead], 0
    xor     eax, eax
.ret:
    xor     edx, edx
.out:
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
; .append: the token at rbp onto the output (r13, r15). rax = 0 or an
; error. Clobbers rcx, rdx, rsi, rdi, r8-r11
.append:
    cmp     r15, [rel relex_cap]
    jb      .append_room
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel relex_cap]
    shl     rsi, 1
    imul    rsi, rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .append_ret
    mov     rdi, rdx
    mov     rsi, r13
    imul    rcx, r15, TOKEN_SIZE
    rep movsb
    mov     r13, rdx
    shl     qword [rel relex_cap], 1
.append_room:
    imul    rdi, r15, TOKEN_SIZE
    add     rdi, r13
    mov     rsi, rbp
    copy_token
    inc     r15
    xor     eax, eax
.append_ret:
    ret

; ---- prep_list_label (internal) -----------
; "lab: m" with -l: "lab: " listed as the first line of m's expansion, at
; the call's line (lst_label_line) - unless m takes the label itself
; (%00 in its body), as NASM. rbx = PrepState; preserves r12-r15.
prep_list_label:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .ret
    mov     rax, [rax + MACROEXP_macro]
    mov     rsi, [rax + MACRO_tokens]
    mov     ecx, [rax + MACRO_ntokens]
.scan_00:
    test    ecx, ecx
    jz      .no_00
    cmp     byte [rsi + TOKEN_kind], TOK_DIRECTIVE
    jne     .scan_next
    mov     rdx, [rsi + TOKEN_value]
    cmp     word [rdx], '00'
    jne     .scan_next
    cmp     byte [rdx + 2], 0
    je      .ret                           ; %00: the macro takes it
.scan_next:
    add     rsi, TOKEN_SIZE
    dec     ecx
    jmp     .scan_00
.no_00:
    mov     rdi, [rel ml_label]
    test    rdi, rdi
    jz      .ret
    call    str_len
    push    rax
    lea     rsi, [rax + 3]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, [rel ml_label]
    push    rdx
    rep movsb
    mov     word [rdi], ': '
    cmp     byte [rel ml_nocolon], 0
    je      .colon_put
    mov     word [rdi], ' :'               ; "lab2 m": NASM's "lab2 :"
    mov     byte [rel ml_nocolon], 0
.colon_put:
    mov     byte [rdi + 2], 0
    pop     rcx                            ; the text
    extern  error_loc_file, error_loc_line, lst_label_line
    mov     rdi, [rel error_loc_file]
    mov     esi, [rel error_loc_line]
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    xor     edx, edx
    test    rax, rax
    jz      .depth
    mov     edx, [rax + MACROEXP_lst_depth]
.depth:
    call    lst_label_line
.ret:
    ret

%define FN_RADIX 0x19                      ; %=(x) (fn_table has the others)
%define FN_CONDSTR 0x1A                    ; %&&(x)
