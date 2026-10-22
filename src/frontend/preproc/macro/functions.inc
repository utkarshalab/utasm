; ============================================================================
; File        : src/frontend/preproc/macro/functions.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : the preprocessor functions (%sel, %cond, %eval, %str, %num, %hex ...): fn_*
; ============================================================================


; ---- prep_function -------------------------
;
; prep_function
; NASM 2.16's preprocessor functions: "%name(" anywhere on a line - the
; arguments read (macros expanded in them), the result put in place of the
; call: %abs %cond %count %eval %hex %num %sel %str %strcat %strlen
; %substr %tok %map, and the %is family(%is, %isdef, %isnum, %isstr, %isid,
; %isempty, %istoken, %ismacro, %isidn, %isidni, %isenv, %isctx; %isn...
; the other way), 1 or 0. A name of these not followed by "(" is the
; directive (%strcat NAME ..., %substr NAME ...) or nothing of this.
; Input    : rbx = PrepState, rsi = the directive token
; Output   : rax = EXIT_OK or an error; edx = 0 not a function call, 1 the
;            token is the result's first one (the others follow it), 2 the
;            result is nothing (the token goes), 3 a call left as written
;            (names not expanded: prep_noexpand)
;
prep_function:
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    mov     r12, rsi
    ; %=(x): a %define's =x/x parameter (prep_def_marks), its radix and
    ; sign in the name - no name a source can spell
    mov     rax, [r12 + TOKEN_value]
    cmp     word [rax], ','
    je      .cond_comma
    mov     r14d, FN_CONDSTR               ; %&&(x): a &&x parameter
    cmp     word [rax], '&&'
    jne     .not_condstr
    cmp     byte [rax + 2], 0
    je      .found_id
.not_condstr:
    cmp     byte [rax], '='
    jne     .names
    movzx   ecx, byte [rax + 1]
    cmp     ecx, '-'
    jne     .radix_named
    xor     ecx, ecx                       ; decimal
.radix_named:
    cmp     byte [rax + 2], 'u'
    jne     .radix_signed
    or      ecx, 0x100
.radix_signed:
    mov     [rel fn_radix], cx
    mov     r14d, FN_RADIX
    jmp     .found_id
.cond_comma:
    ; "%,": a comma, unless nothing follows it ("a %, b" with b empty) -
    ; the end of the line, a ")" or another comma next. In a %define's
    ; body being read it stays, for when the body is expanded.
    cmp     byte [rel prep_noexpand], 0
    je      .cond_now
    xor     eax, eax
    mov     edx, 3
    jmp     .out
.cond_now:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .nothing
    cmp     eax, TOK_EOF
    je      .nothing
    cmp     eax, TOK_RPAREN
    je      .nothing
    cmp     eax, TOK_COMMA
    je      .nothing
    mov     byte [r12 + TOKEN_kind], TOK_COMMA
    mov     qword [r12 + TOKEN_value], 0
    jmp     .one
.names:
    ; %mapi / %mapn: NASM 2.16 leaves them as they are (its tests pass them
    ; to %map): an identifier spelled "%mapi"
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel s_fn_mapi]
    call    str_cmp
    lea     rcx, [rel s_tok_mapi]
    test    rax, rax
    jz      .map_marker
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel s_fn_mapn]
    call    str_cmp
    lea     rcx, [rel s_tok_mapn]
    test    rax, rax
    jnz     .not_map_marker
.map_marker:
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    mov     [r12 + TOKEN_value], rcx
    jmp     .one
.not_map_marker:
    ; one of the names?
    lea     r13, [rel fn_table]
.find:
    cmp     byte [r13], 0
    je      .not_fn
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .found
    add     r13, 16
    jmp     .find
.found:
    movzx   r14d, byte [r13 + 15]          ; FN_*, bit 7: the other way
.found_id:
    ; "(" next (its name not expanded meanwhile, should it be a directive)
    movzx   r15d, byte [rel prep_noexpand]
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     [rel prep_noexpand], r15b
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .not_fn
    ; while names are not expanded (a %define's body being read) a call
    ; stays as written, run when the body is: its tokens as they are
    test    r15d, r15d
    jz      .call_now
    xor     eax, eax
    mov     edx, 3
    jmp     .out
.call_now:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the "("
    test    rax, rax
    jnz     .ret
    ; an output of its own: a call in an argument ("%eval(%count(1, 2))")
    ; runs while this one is being read
    push    qword [rel fn_out]
    push    qword [rel fn_n]
    push    qword [rel fn_cap]
    push    qword [rel fn_col]
    mov     qword [rel fn_out], 0
    mov     qword [rel fn_n], 0
    movzx   eax, word [r12 + TOKEN_col]
    mov     [rel fn_col], rax
    mov     eax, r14d
    and     eax, 0x7F
    lea     rcx, [rel .handlers]
    call    [rcx + rax * 8]
    mov     r13, [rel fn_out]              ; r13 = the result, r15 = its count
    mov     r15, [rel fn_n]
    pop     qword [rel fn_col]
    pop     qword [rel fn_cap]
    pop     qword [rel fn_n]
    pop     qword [rel fn_out]
    test    rax, rax
    jnz     .ret
    ; the result in place of the call, with its blank before it
    test    r15, r15
    jz      .nothing
    movzx   r8d, byte [r12 + TOKEN_flags]
    and     r8d, TOK_FLAG_SPACE
    mov     rdi, r12
    mov     rsi, r13
    copy_token
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_SPACE
    or      [r12 + TOKEN_flags], r8b
    cmp     r15, 1
    je      .one
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_DEFINE
    mov     qword [rdx + MACRO_name], 0
    lea     rax, [r13 + TOKEN_SIZE]
    mov     [rdx + MACRO_tokens], rax
    lea     eax, [r15d - 1]
    mov     [rdx + MACRO_ntokens], eax
    mov     rdi, rbx
    mov     rsi, rdx
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
.one:
    xor     eax, eax
    mov     edx, 1
    jmp     .out
.nothing:
    xor     eax, eax
    mov     edx, 2
    jmp     .out
.not_fn:
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

.handlers:
    dq      .f_abs, .f_cond, .f_count, .f_eval, .f_hex, .f_num, .f_sel
    dq      .f_str, .f_strcat, .f_strlen, .f_substr, .f_tok, .f_is, .f_isdef
    dq      .f_isnum, .f_isstr, .f_isid, .f_isempty, .f_istoken, .f_ismacro
    dq      .f_isidn, .f_isidni, .f_isenv, .f_isctx, .f_map, .f_radix, .f_condstr

; ---- the functions: each reads its arguments up to ")" and puts its
; ---- result (fn_put_*); rax = 0 or an error. r14 bit 7: %isn...
.f_radix:
    ; %=(x): x evaluated, written in the radix fn_radix says
    movzx   ebp, word [rel fn_radix]
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    mov     rax, rdx
    mov     ecx, ebp
    jmp     fn_put_radix
.f_condstr:
    ; %&&(x): a quoted string stays as it is, anything else as %str makes it
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .f_ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .condstr_quoted
    cmp     eax, TOK_CHAR
    jne     .f_str
.condstr_quoted:
    mov     rdi, rbx
    call    preprocessor_next_token        ; its own copy
    test    rax, rax
    jnz     .f_ret
    push    rdx
    call    fn_sep
    pop     rsi
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many                    ; "x" then more: not one string
    jmp     fn_put_token
.f_abs:
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    mov     rax, rdx
    test    rax, rax
    jns     .abs_pos
    neg     rax
.abs_pos:
    jmp     fn_put_signed
.f_eval:
    xor     ebp, ebp                       ; 0: decimal
    jmp     .eval_next
.f_hex:
    mov     ebp, 1                         ; 1: 0x...
.eval_next:
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    push    rcx
    mov     rax, rdx
    test    ebp, ebp
    jnz     .eval_hex
    call    fn_put_signed
    jmp     .eval_put
.eval_hex:
    call    fn_put_hex
.eval_put:
    pop     rcx
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jz      .f_ok
    mov     eax, TOK_COMMA
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .f_ret
    jmp     .eval_next
.f_num:
    ; %num(value [, digits [, base]]): a string
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    mov     rbp, rdx                       ; the value
    mov     r13, -1                        ; digits: as many as it takes
    mov     r15d, 10                       ; base
    test    ecx, ecx
    jz      .num_put
    call    fn_expr_or_empty
    test    rax, rax
    jnz     .f_ret
    test    edi, edi
    jnz     .num_digits_dflt
    mov     r13, rdx
.num_digits_dflt:
    test    ecx, ecx
    jz      .num_put
    call    fn_expr_or_empty
    test    rax, rax
    jnz     .f_ret
    test    edi, edi
    jnz     .num_base_dflt
    mov     r15, rdx
.num_base_dflt:
    test    ecx, ecx
    jnz     .f_too_many
.num_put:
    cmp     r15, 2
    jb      .f_bad
    cmp     r15, 36
    ja      .f_bad
    ; digits: N > 0 exactly N, the low ones ("%num(x,3)" of 1844...696 is
    ; 696), N < 0 at least -N, as NASM
    mov     rdx, r13
    test    rdx, rdx
    jle     .num_least
    mov     byte [rel fn_exact], 1
    jmp     .num_digits_set
.num_least:
    neg     rdx
.num_digits_set:
    mov     rax, rbp
    mov     rcx, r15
    call    fn_utoa                        ; rdx = text, rcx = length
    mov     byte [rel fn_exact], 0
    test    rax, rax
    jnz     .f_ret
    mov     rsi, rdx
    jmp     fn_put_string
.f_count:
    ; how many arguments (one, empty, at least)
    xor     ebp, ebp
.count_next:
    inc     ebp
    call    fn_skip_arg
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .count_next
    mov     eax, ebp
    jmp     fn_put_signed
.f_sel:
    ; %sel(n, a, b, ...): the n-th of them
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jz      .f_ok                          ; nothing to choose from
    mov     r13, rdx                       ; n
    mov     rbp, rdx                       ; (counted down)
    xor     r15d, r15d                     ; how many there are
.sel_next:
    inc     r15
    dec     rbp
    jz      .sel_take
    call    fn_skip_arg
    jmp     .sel_after
.sel_take:
    call    fn_copy_arg
.sel_after:
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .sel_next
    ; none of them: NASM's warnings
    lea     rsi, [rel s_sel_invalid]
    test    r13, r13
    jle     .sel_warn
    cmp     r13, r15
    jbe     .f_ok
    lea     rsi, [rel s_sel_exceeds]
.sel_warn:
    push    rsi
    mov     edi, WC_PP_SEL_RANGE
    call    warn_begin
    lea     rsi, [rel s_sel_open]
    call    warn_text
    mov     rax, r13
    lea     rdi, [rel fn_num_buf]
    test    rax, rax
    jns     .sel_num
    mov     byte [rdi], '-'
    inc     rdi
    neg     rax
.sel_num:
    mov     rsi, rax
    call    str_int_to_str
    lea     rsi, [rel fn_num_buf]
    call    warn_text
    pop     rsi
    call    warn_text
    call    warn_end
    jmp     .f_ok
.f_cond:
    ; %cond(c, a [, b]): a when c is not 0, else b
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jz      .f_ok
    mov     rbp, rdx
    test    rbp, rbp
    jz      .cond_skip_a
    call    fn_copy_arg
    jmp     .cond_b
.cond_skip_a:
    call    fn_skip_arg
.cond_b:
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jz      .f_ok
    test    rbp, rbp
    jnz     .cond_skip_b
    call    fn_copy_arg
    jmp     .cond_end
.cond_skip_b:
    call    fn_skip_arg
.cond_end:
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    jmp     .f_ok
.f_str:
    ; %str(...): the text of the tokens, as %defstr makes it
    lea     rdi, [rel idn_left]
    mov     esi, 2 | 4                     ; the source's spacing, up to ")"
    call    prep_idn_collect
    test    rax, rax
    jnz     .f_ret
    push    rdx
    call    fn_close
    pop     rsi
    test    rax, rax
    jnz     .f_ret
    jmp     fn_put_string_copy
.f_strcat:
    ; %strcat('a', "b", ...): one string
    lea     rdi, [rel idn_left]
    mov     rax, [rdi]
    mov     byte [rax], 0
    xor     ebp, ebp                       ; its length
.strcat_next:
    call    fn_string
    test    rax, rax
    jnz     .f_ret
    push    rcx
    mov     rdi, rdx
    call    fn_append_left
    pop     rcx
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .strcat_next
    mov     rsi, [rel idn_left]
    jmp     fn_put_string_copy
.f_strlen:
    call    fn_string
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    mov     rdi, rdx
    call    str_len
    jmp     fn_put_signed
.f_substr:
    ; %substr(s, start [, length]): the rest when no length
    call    fn_string
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jz      .f_bad
    mov     rbp, rdx                       ; the text
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    mov     r13, rdx                       ; start (1-based)
    mov     r15, -1                        ; length: the rest
    test    ecx, ecx
    jz      .substr_cut
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    mov     r15, rdx
.substr_cut:
    mov     rdi, rbp
    call    str_len                        ; rax = L
    mov     r8, r13
    test    r8, r8
    jg      .substr_start
    mov     r8d, 1
.substr_start:
    dec     r8                             ; 0-based
    mov     r9, r15
    test    r9, r9
    jns     .substr_len
    ; a negative length ends that far from the end (-1: at the end)
    mov     rcx, rax
    sub     rcx, r8
    lea     r9, [rcx + r9 + 1]
.substr_len:
    cmp     r8, rax
    jb      .substr_clip
    xor     r9d, r9d
    xor     r8d, r8d
    jmp     .substr_put
.substr_clip:
    mov     rcx, rax
    sub     rcx, r8
    cmp     r9, rcx
    jle     .substr_pos
    mov     r9, rcx
.substr_pos:
    test    r9, r9
    jns     .substr_put
    xor     r9d, r9d
.substr_put:
    mov     rsi, rbp
    add     rsi, r8
    mov     rcx, r9
    jmp     fn_put_string_n
.f_tok:
    ; %tok('text'): the tokens the text spells
    call    fn_string
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    mov     rsi, rdx
    jmp     fn_put_lexed
.f_is:
    call    fn_expr
    test    rax, rax
    jnz     .f_ret
    test    ecx, ecx
    jnz     .f_too_many
    xor     eax, eax
    test    rdx, rdx
    setnz   al
    jmp     .f_truth
.f_isdef:
    ; a %define or an %assign of that name
    call    fn_name
    test    rax, rax
    jnz     .f_ret
    xor     ebp, ebp
    test    rdx, rdx
    jz      .isdef_done
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    call    prep_symbol_find
    test    rax, rax
    jnz     .isdef_done
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jnz     .isdef_yes
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .isdef_done
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .isdef_done
.isdef_yes:
    mov     ebp, 1
.isdef_done:
    call    fn_close
    test    rax, rax
    jnz     .f_ret
    mov     eax, ebp
    jmp     .f_truth
.f_ismacro:
    ; a multi-line macro of that name
    call    fn_name
    test    rax, rax
    jnz     .f_ret
    xor     ebp, ebp
    test    rdx, rdx
    jz      .ismacro_done
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    call    prep_symbol_find
    test    rax, rax
    jnz     .ismacro_done
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .ismacro_done
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .ismacro_done
    mov     ebp, 1
.ismacro_done:
    call    fn_skip_rest
    test    rax, rax
    jnz     .f_ret
    mov     eax, ebp
    jmp     .f_truth
.f_isenv:
    call    fn_name_or_string
    test    rax, rax
    jnz     .f_ret
    xor     ebp, ebp
    test    rdx, rdx
    jz      .isenv_done
    mov     rdi, rdx
    call    prep_getenv
    test    rax, rax
    setnz   bpl
.isenv_done:
    call    fn_close
    test    rax, rax
    jnz     .f_ret
    mov     eax, ebp
    jmp     .f_truth
.f_isctx:
    ; the name of the innermost %push context
    call    fn_name
    test    rax, rax
    jnz     .f_ret
    xor     ebp, ebp
    test    rdx, rdx
    jz      .isctx_done
    mov     ecx, [rbx + PREP_ctx_depth]
    test    ecx, ecx
    jz      .isctx_done
    dec     ecx
    lea     rax, [rbx + PREP_ctx_names]
    mov     rsi, [rax + rcx * 8]
    test    rsi, rsi
    jz      .isctx_done
    mov     rdi, rdx
    call    str_cmp
    test    rax, rax
    jnz     .isctx_done
    mov     ebp, 1
.isctx_done:
    call    fn_close
    test    rax, rax
    jnz     .f_ret
    mov     eax, ebp
    jmp     .f_truth
.f_isnum:
    mov     ebp, 1                         ; one number
    jmp     .one_kind
.f_isstr:
    mov     ebp, 2                         ; one string
    jmp     .one_kind
.f_isid:
    mov     ebp, 3                         ; one identifier
    jmp     .one_kind
.f_istoken:
    mov     ebp, 4                         ; one token
    jmp     .one_kind
.f_isempty:
    xor     ebp, ebp                       ; none
.one_kind:
    call    fn_arg_kinds                   ; eax = how many, ecx = the first's kind
    test    rax, rax
    js      .f_ret_neg
    test    ebp, ebp
    jnz     .kind_one
    test    eax, eax
    setz    al
    movzx   eax, al
    jmp     .f_truth
.kind_one:
    cmp     eax, 1
    jne     .kind_no
    cmp     ebp, 4
    je      .kind_yes
    cmp     ebp, 1
    jne     .kind_str
    cmp     ecx, TOK_NUMBER
    je      .kind_yes
    jmp     .kind_no
.kind_str:
    cmp     ebp, 2
    jne     .kind_id
    cmp     ecx, TOK_STRING
    je      .kind_yes
    cmp     ecx, TOK_CHAR
    je      .kind_yes
    jmp     .kind_no
.kind_id:
    cmp     ecx, TOK_IDENT
    je      .kind_yes
.kind_no:
    xor     eax, eax
    jmp     .f_truth
.kind_yes:
    mov     eax, 1
    jmp     .f_truth
.f_ret_neg:
    neg     rax
    ret
.f_isidn:
    xor     ebp, ebp                       ; letter case counts
    jmp     .idn
.f_isidni:
    mov     ebp, 1
.idn:
    lea     rdi, [rel idn_left]
    mov     esi, 1 | 2 | 4                 ; up to "," or ")"
    call    prep_idn_collect
    test    rax, rax
    jnz     .f_ret
    mov     rdi, rbx
    call    preprocessor_next_token        ; the ","
    test    rax, rax
    jnz     .f_ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .f_bad
    lea     rdi, [rel idn_right]
    mov     esi, 2 | 4
    call    prep_idn_collect
    test    rax, rax
    jnz     .f_ret
    call    fn_close
    test    rax, rax
    jnz     .f_ret
    mov     rdi, [rel idn_left]
    mov     rsi, [rel idn_right]
    mov     edx, ebp
    call    fn_text_equal
    jmp     .f_truth
.f_truth:
    ; 1 or 0, %isn...: the other way
    test    r14d, 0x80
    jz      .truth_put
    xor     eax, 1
.truth_put:
    jmp     fn_put_signed
.f_map:
    ; %map(F, a, b): F(a),F(b) - %map(F:(x), a): F(x,a) - %map(F::2, a, b,
    ; c, d): F(a,b),F(c,d), the arguments in groups. Locals:[rsp] the arguments read, [rsp+8] their tokens, [rsp+16] the
    ; calls, [rsp+24] this call, [rsp+32] the next argument token
    sub     rsp, 40
    xor     r13d, r13d                     ; the fixed arguments: none
    xor     r15d, r15d
    mov     r14d, 1                        ; the group: one each
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .map_out
    cmp     byte [rdx + TOKEN_kind], TOK_LABEL
    jne     .map_name
    ; "F:" lexes as a label: the name, its colon read
    mov     rbp, [rdx + TOKEN_value]
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .map_out
    jmp     .map_colon
.map_name:
    call    fn_name
    test    rax, rax
    jnz     .map_out
    test    rdx, rdx
    jz      .map_bad
    mov     rbp, rdx                       ; the macro's name
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .map_out
    cmp     byte [rdx + TOKEN_kind], TOK_COLONCOLON
    je      .map_group
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .map_sep
.map_colon:
    ; ":(...)": the arguments before each one, set aside; ":N" after the
    ; name's colon or after them: the group size
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .map_out
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    je      .map_group
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .map_bad
.map_fixed:
    call    fn_copy_arg
    test    rax, rax
    jnz     .map_out
    test    ecx, ecx
    jz      .map_fixed_done
    mov     eax, TOK_COMMA
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .map_out
    jmp     .map_fixed
.map_fixed_done:
    mov     r13, [rel fn_out]
    mov     r15, [rel fn_n]
    mov     qword [rel fn_out], 0          ; (kept: the output starts anew)
    mov     qword [rel fn_n], 0
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .map_out
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .map_sep
.map_group:
    call    fn_expr                        ; N, then "," or ")"
    test    rax, rax
    jnz     .map_out
    mov     r14, rdx
    test    r14, r14
    jle     .map_bad
    test    ecx, ecx
    jz      .map_ok                        ; no arguments: nothing
    jmp     .map_collect
.map_sep:
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    je      .map_ok                        ; no arguments: nothing
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .map_bad
.map_collect:
    ; every argument read first (the calls counted), a TOK_UNKNOWN after each
    mov     qword [rel fn_out], 0
    mov     qword [rel fn_n], 0
    mov     qword [rsp + 16], 0            ; (counted here)
.map_read:
    call    fn_copy_arg
    test    rax, rax
    jnz     .map_out
    inc     qword [rsp + 16]
    push    rcx
    mov     eax, TOK_UNKNOWN
    mov     ecx, 1
    call    fn_put_punct
    pop     rcx
    test    rax, rax
    jnz     .map_out
    test    ecx, ecx
    jnz     .map_read
    mov     rax, [rel fn_out]
    mov     [rsp], rax
    mov     rax, [rel fn_n]
    mov     [rsp + 8], rax
    mov     qword [rel fn_out], 0
    mov     qword [rel fn_n], 0
    ; calls: the arguments over the group size, rounded up
    mov     rax, [rsp + 16]
    add     rax, r14
    dec     rax
    xor     edx, edx
    div     r14
    mov     [rsp + 16], rax
    mov     qword [rsp + 24], 0
    mov     qword [rsp + 32], 0
.map_call:
    mov     rax, [rsp + 24]
    cmp     rax, [rsp + 16]
    jae     .map_ok
    test    rax, rax
    jz      .map_head
    mov     eax, TOK_COMMA
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .map_out
.map_head:
    ; NAME ( fixed , group )
    lea     rdi, [rel fn_tok]
    xor     eax, eax
    mov     ecx, TOKEN_SIZE / 8
    rep stosq
    mov     byte [rel fn_tok + TOKEN_tag], TAG_TOKEN
    mov     byte [rel fn_tok + TOKEN_kind], TOK_IDENT
    mov     [rel fn_tok + TOKEN_value], rbp
    mov     rdi, rbp
    call    str_len
    mov     [rel fn_tok + TOKEN_len], ax
    lea     rsi, [rel fn_tok]
    call    fn_put_token
    test    rax, rax
    jnz     .map_out
    mov     eax, TOK_LPAREN
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .map_out
    xor     ecx, ecx
.map_put_fixed:
    cmp     rcx, r15
    jae     .map_fixed_put
    imul    rsi, rcx, TOKEN_SIZE
    add     rsi, r13
    push    rcx
    call    fn_put_token
    pop     rcx
    test    rax, rax
    jnz     .map_out
    inc     rcx
    jmp     .map_put_fixed
.map_fixed_put:
    test    r15, r15
    jz      .map_own
    mov     eax, TOK_COMMA
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .map_out
.map_own:
    xor     ecx, ecx                       ; the group's arguments so far
.map_own_arg:
    cmp     rcx, r14
    jae     .map_close
    mov     rax, [rsp + 32]
    cmp     rax, [rsp + 8]
    jae     .map_close                     ; no more: a short last group
    test    rcx, rcx
    jz      .map_arg_tokens
    push    rcx
    mov     eax, TOK_COMMA
    mov     ecx, 1
    call    fn_put_punct
    pop     rcx
    test    rax, rax
    jnz     .map_out
.map_arg_tokens:
    mov     rax, [rsp + 32]
    inc     qword [rsp + 32]
    imul    rsi, rax, TOKEN_SIZE
    add     rsi, [rsp]
    cmp     byte [rsi + TOKEN_kind], TOK_UNKNOWN
    je      .map_arg_end
    push    rcx
    call    fn_put_token
    pop     rcx
    test    rax, rax
    jnz     .map_out
    jmp     .map_arg_tokens
.map_arg_end:
    inc     rcx
    jmp     .map_own_arg
.map_close:
    mov     eax, TOK_RPAREN
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .map_out
    inc     qword [rsp + 24]
    jmp     .map_call
.map_bad:
    mov     eax, EXIT_INVALID_EXPR
    jmp     .map_out
.map_ok:
    xor     eax, eax
.map_out:
    add     rsp, 40
    ret
.f_too_many:
.f_bad:
    mov     eax, EXIT_INVALID_EXPR
    ret
.f_ok:
    xor     eax, eax
.f_ret:
    ret

; ---- the arguments ------------------------
; fn_sep: the token after an argument: rax = 0 and ecx = 1 for ",", 0 for
; ")", or an error.
fn_sep:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    xor     ecx, ecx
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    je      .ret
    inc     ecx
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    je      .ret
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    ret

; fn_close: the ")" ending the arguments
fn_close:
    call    fn_sep
    test    rax, rax
    jnz     .ret
    test    ecx, ecx
    jz      .ret
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    ret

; fn_expr: an expression, a number: rdx; then fn_sep (ecx)
fn_expr:
    mov     rdi, rbx
    call    parser_evaluate_pp
    test    rax, rax
    jnz     .ret
    test    rcx, rcx
    jz      .number
    mov     eax, EXIT_INVALID_EXPR         ; not known here
    ret
.number:
    push    rdx
    call    fn_sep
    pop     rdx
.ret:
    ret

; fn_expr_or_empty: as fn_expr; edi = 1 when the argument was left out
; ("%num(255,,2)")
fn_expr_or_empty:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_COMMA
    je      .empty
    cmp     eax, TOK_RPAREN
    je      .empty
    call    fn_expr
    xor     edi, edi
    ret
.empty:
    call    fn_sep
    mov     edi, 1
.ret:
    ret

; fn_string: a quoted argument: rdx = its text; then fn_sep (ecx)
fn_string:
    ; an empty one is "" ("%strcat('a', )": a %map giving nothing)
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    je      .empty
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    je      .empty
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_quoted_text
    test    rax, rax
    jz      .bad
    push    rax
    call    fn_sep
    pop     rdx
.ret:
    ret
.empty:
    call    fn_sep
    lea     rdx, [rel s_fn_empty]
    ret
.bad:
    mov     eax, EXIT_INVALID_EXPR
    ret

; fn_name: a name, not expanded: rdx = it (0 when the argument is no
; identifier); the ")" is left to the caller
fn_name:
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rax, [rdx + TOKEN_value]
    push    rax
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rdx
    ret
.none:
    xor     eax, eax
    xor     edx, edx
.ret:
    ret

; fn_name_or_string: a name or a quoted one
fn_name_or_string:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    je      fn_name
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_quoted_text
    mov     rdx, rax
    xor     eax, eax
.ret:
    ret

; fn_skip_arg / fn_copy_arg: an argument's tokens, up to the "," or ")"
; that ends it (parentheses nest), left out or put in the output; then
; ecx as fn_sep
fn_skip_arg:
    xor     eax, eax
    jmp     fn_arg_tokens
fn_copy_arg:
    mov     eax, 1
fn_arg_tokens:
    push    r15
    push    r13
    mov     r13d, eax                      ; 1: put them
    xor     r15d, r15d                     ; depth
.token:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .unclosed
    cmp     eax, TOK_EOF
    je      .unclosed
    cmp     eax, TOK_LPAREN
    jne     .not_open
    inc     r15d
    jmp     .take
.not_open:
    cmp     eax, TOK_RPAREN
    jne     .not_close
    test    r15d, r15d
    jz      .end_paren
    dec     r15d
    jmp     .take
.not_close:
    cmp     eax, TOK_COMMA
    jne     .take
    test    r15d, r15d
    jz      .end_comma
.take:
    test    r13d, r13d
    jz      .token
    mov     rsi, rdx
    call    fn_put_token
    test    rax, rax
    jnz     .ret
    jmp     .token
.end_paren:
    xor     eax, eax
    xor     ecx, ecx
    jmp     .ret
.end_comma:
    xor     eax, eax
    mov     ecx, 1
    jmp     .ret
.unclosed:
    mov     eax, EXIT_UNEXPECTED_EOF
.ret:
    pop     r13
    pop     r15
    ret

; fn_skip_rest: the tokens up to the ")" (parentheses nest)
fn_skip_rest:
    call    fn_skip_arg
    test    rax, rax
    jnz     .ret
    test    ecx, ecx
    jnz     fn_skip_rest
.ret:
    ret

; fn_arg_kinds: the one argument up to ")": eax = how many tokens (rax
; negative: minus an error), ecx = the first one's kind
fn_arg_kinds:
    push    r13
    push    r15
    xor     r13d, r13d                     ; how many
    xor     r15d, r15d                     ; the first's kind
.token:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_RPAREN
    je      .done
    cmp     eax, TOK_NEWLINE
    je      .unclosed
    cmp     eax, TOK_EOF
    je      .unclosed
    test    r13d, r13d
    jnz     .counted
    mov     r15d, eax
.counted:
    inc     r13d
    jmp     .token
.done:
    mov     eax, r13d
    mov     ecx, r15d
    pop     r15
    pop     r13
    ret
.unclosed:
    mov     eax, EXIT_UNEXPECTED_EOF
.error:
    neg     rax
    pop     r15
    pop     r13
    ret

; fn_append_left: the text rdi onto idn_left's (a growing buffer; ebp its
; length). rax = 0 or an error
fn_append_left:
    push    r12
    mov     r12, rdi
.byte:
    movzx   eax, byte [r12]
    test    eax, eax
    jz      .done
    lea     rcx, [rbp + 2]
    cmp     rcx, [rel idn_left + 8]
    jbe     .room
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel idn_left + 8]
    shl     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, [rel idn_left]
    mov     ecx, ebp
    rep movsb
    mov     [rel idn_left], rdx
    shl     qword [rel idn_left + 8], 1
    movzx   eax, byte [r12]
.room:
    mov     rdx, [rel idn_left]
    mov     [rdx + rbp], al
    mov     byte [rdx + rbp + 1], 0
    inc     ebp
    inc     r12
    jmp     .byte
.done:
    xor     eax, eax
.ret:
    pop     r12
    ret

; fn_text_equal: eax = 1 when the texts rdi and rsi are the same (edx = 1:
; in any letter case)
fn_text_equal:
.byte:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    test    edx, edx
    jz      .compare
    lea     r8d, [eax - 'A']
    cmp     r8d, 25
    ja      .lower_b
    add     eax, 32
.lower_b:
    lea     r8d, [ecx - 'A']
    cmp     r8d, 25
    ja      .compare
    add     ecx, 32
.compare:
    cmp     eax, ecx
    jne     .no
    test    eax, eax
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .byte
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- the output ---------------------------
; fn_put_token: the token rsi onto the output (a copy, placed after the
; ones before it on the call's line). rax = 0 or an error. Clobbers rcx,
; rdx, rsi, rdi, r8-r11
fn_put_token:
    mov     rax, [rel fn_out]
    test    rax, rax
    jz      .grow
    mov     rax, [rel fn_n]
    cmp     rax, [rel fn_cap]
    jb      .room
.grow:
    push    rsi
    mov     rax, [rel fn_cap]
    cmp     qword [rel fn_out], 0
    jne     .double
    mov     eax, 8
    jmp     .alloc
.double:
    shl     rax, 1
.alloc:
    mov     [rel fn_cap], rax
    imul    rsi, rax, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rsi
    test    rax, rax
    jnz     .ret
    push    rsi
    mov     rdi, rdx
    mov     rsi, [rel fn_out]
    imul    rcx, [rel fn_n], TOKEN_SIZE
    test    rsi, rsi
    jz      .copied
    rep movsb
.copied:
    pop     rsi
    mov     [rel fn_out], rdx
.room:
    imul    rdi, [rel fn_n], TOKEN_SIZE
    add     rdi, [rel fn_out]
    push    rdi
    copy_token
    pop     rdi
    mov     eax, [r12 + TOKEN_line]
    mov     [rdi + TOKEN_line], eax
    mov     rax, [r12 + TOKEN_file]
    mov     [rdi + TOKEN_file], rax
    mov     eax, [rel fn_col]
    mov     [rdi + TOKEN_col], ax
    movzx   ecx, word [rdi + TOKEN_len]
    test    ecx, ecx
    jnz     .len
    mov     ecx, 1
.len:
    add     [rel fn_col], ecx
    inc     qword [rel fn_n]
    xor     eax, eax
.ret:
    ret

; fn_put_punct: a punctuation token of kind eax (ecx = its length)
fn_put_punct:
    lea     rdi, [rel fn_tok]
    push    rax
    push    rcx
    xor     eax, eax
    mov     ecx, TOKEN_SIZE / 8
    rep stosq
    pop     rcx
    pop     rax
    mov     byte [rel fn_tok + TOKEN_tag], TAG_TOKEN
    mov     [rel fn_tok + TOKEN_kind], al
    mov     [rel fn_tok + TOKEN_len], cx
    lea     rsi, [rel fn_tok]
    jmp     fn_put_token

; fn_put_number_text: a number token, its text rdx
fn_put_number_text:
    push    rdx
    lea     rdi, [rel fn_tok]
    xor     eax, eax
    mov     ecx, TOKEN_SIZE / 8
    rep stosq
    pop     rdx
    mov     byte [rel fn_tok + TOKEN_tag], TAG_TOKEN
    mov     byte [rel fn_tok + TOKEN_kind], TOK_NUMBER
    mov     [rel fn_tok + TOKEN_value], rdx
    mov     rdi, rdx
    call    str_len
    mov     [rel fn_tok + TOKEN_len], ax
    lea     rsi, [rel fn_tok]
    jmp     fn_put_token

; fn_put_signed: the number rax, in decimal ("-3": a minus, then 3)
fn_put_signed:
    test    rax, rax
    jns     .plain
    push    rax
    mov     eax, TOK_MINUS
    mov     ecx, 1
    call    fn_put_punct
    pop     rdx
    test    rax, rax
    jnz     .ret
    mov     rax, rdx
    neg     rax
.plain:
    mov     ecx, 10
    mov     rdx, -1
    call    fn_utoa
    test    rax, rax
    jnz     .ret
    jmp     fn_put_number_text
.ret:
    ret

; fn_put_hex: the number rax as 0x... (two's complement, 64 bits)
fn_put_hex:
    mov     ecx, 16
    mov     rdx, -1
    mov     byte [rel fn_prefix], 1
    call    fn_utoa
    mov     byte [rel fn_prefix], 0
    test    rax, rax
    jnz     .ret
    jmp     fn_put_number_text
.ret:
    ret

; fn_put_radix: the number rax as NASM writes a =x/r parameter: ecx = the
; radix letter (0: decimal, no prefix; upper case: upper-case digits) |
; 0x100 unsigned. Signed and negative: a minus, then the magnitude.
fn_put_radix:
    push    r14
    push    r15
    mov     r14, rax
    mov     r15d, ecx
    test    r15d, 0x100
    jnz     .magnitude
    test    r14, r14
    jns     .magnitude
    mov     eax, TOK_MINUS
    mov     ecx, 1
    call    fn_put_punct
    test    rax, rax
    jnz     .ret
    neg     r14
.magnitude:
    movzx   eax, r15b
    or      eax, 0x20
    mov     ecx, 2
    cmp     eax, 'b'
    je      .base
    cmp     eax, 'y'
    je      .base
    mov     ecx, 8
    cmp     eax, 'o'
    je      .base
    cmp     eax, 'q'
    je      .base
    mov     ecx, 16
    cmp     eax, 'h'
    je      .base
    cmp     eax, 'x'
    je      .base
    mov     ecx, 10
.base:
    mov     rax, r14
    mov     rdx, -1
    call    fn_utoa                        ; rdx = the digits, rcx = how many
    test    rax, rax
    jnz     .ret
    test    r15b, r15b
    jz      .put                           ; no radix: plain decimal
    ; "0x" + digits, the letter as written; upper-case digits for "X"
    push    rdx
    push    rcx
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rcx + 3]
    call    arena_alloc
    pop     rcx
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     byte [rdx], '0'
    mov     [rdx + 1], r15b
    lea     rdi, [rdx + 2]
.digit:
    test    ecx, ecx
    jz      .put
    lodsb
    test    r15b, 0x20
    jnz     .digit_put
    cmp     al, 'a'
    jb      .digit_put
    sub     al, 0x20
.digit_put:
    stosb
    dec     ecx
    jmp     .digit
.put:
    pop     r15
    pop     r14
    jmp     fn_put_number_text
.ret:
    pop     r15
    pop     r14
    ret

; fn_put_string / fn_put_string_n / fn_put_string_copy: a string token of
; the text rsi (rcx bytes; _copy: NUL-ended, copied first)
fn_put_string_copy:
    mov     rdi, rsi
    push    rsi
    call    str_len
    pop     rsi
    mov     rcx, rax
fn_put_string_n:
    push    rsi
    push    rcx
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rcx + 1]
    call    arena_alloc                    ; zeroed: NUL-ended
    pop     rcx
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    push    rdx
    push    rcx
    rep movsb
    pop     rcx
    pop     rsi
    jmp     fn_put_string
.ret:
    ret
fn_put_string:
    ; rsi = the text (kept), rcx = its length
    call    prep_scratch_string
    lea     rsi, [rel def_scratch]
    jmp     fn_put_token

; fn_put_lexed: the tokens the text rsi spells (%tok)
fn_put_lexed:
    push    r13
    push    r15
    mov     r13, rsi
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, r13
    call    str_len
    mov     rdi, r15
    mov     rsi, r13
    mov     rdx, rax
    mov     rcx, [r12 + TOKEN_file]
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [rbx + PREP_arena]
    call    lexer_init
    test    rax, rax
    jnz     .ret
.token:
    mov     rdi, r15
    lea     rsi, [rel relex_tok]
    call    lexer_next
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .done
    cmp     eax, TOK_EOF
    je      .done
    lea     rsi, [rel relex_tok]
    call    fn_put_token
    test    rax, rax
    jnz     .ret
    jmp     .token
.done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r13
    ret

; fn_utoa: rax in base ecx (2-36), at least rdx digits (-1: as many as it
; takes; 0x before it when fn_prefix): rdx = the text, rcx = its length;
; rax = 0 or an error
fn_utoa:
    push    r12
    push    r13
    mov     r12, rax
    mov     r8d, ecx
    mov     r13, rdx                       ; the digits asked for
    lea     rdi, [rel fn_num_buf + 80]
    mov     byte [rdi], 0
    xor     ecx, ecx                       ; digits written
.digit:
    xor     edx, edx
    mov     rax, r12
    div     r8
    mov     r12, rax
    cmp     edx, 10
    jb      .dec_digit
    add     edx, 'a' - 10 - '0'
.dec_digit:
    add     edx, '0'
    dec     rdi
    mov     [rdi], dl
    inc     ecx
    test    r12, r12
    jnz     .digit
    ; exactly that many (fn_exact): the low digits only
    cmp     byte [rel fn_exact], 0
    je      .pad
    cmp     rcx, r13
    jbe     .pad
    sub     rcx, r13
    add     rdi, rcx
    mov     rcx, r13
.pad:
    cmp     r13, 0
    jle     .padded
    cmp     rcx, r13
    jae     .padded
    cmp     ecx, 72
    jae     .padded
    dec     rdi
    mov     byte [rdi], '0'
    inc     ecx
    jmp     .pad
.padded:
    cmp     byte [rel fn_prefix], 0
    je      .copy
    sub     rdi, 2
    mov     word [rdi], 'x' << 8 | '0'
    add     ecx, 2
.copy:
    push    rcx
    push    rdi
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rcx + 1]
    call    arena_alloc
    pop     rsi
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    push    rcx
    rep movsb
    pop     rcx
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
s_sel_open:    db "%sel(", 0
s_sel_invalid: db ") is not a valid selector", 0
s_sel_exceeds: db ") exceeds the number of arguments", 0
; the functions: 15-byte name + FN id (bit 7: %isn..., the other way)
fn_table:
    db "abs", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00
    db "cond", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01
    db "count", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02
    db "eval", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x03
    db "hex", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x04
    db "num", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x05
    db "sel", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x06
    db "str", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x07
    db "strcat", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x08
    db "strlen", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x09
    db "substr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0A
    db "tok", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0B
    db "is", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0C
    db "isn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8C
    db "isdef", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0D
    db "isndef", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8D
    db "isnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0E
    db "isnnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8E
    db "isstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0F
    db "isnstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8F
    db "isid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10
    db "isnid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90
    db "isempty", 0, 0, 0, 0, 0, 0, 0, 0, 0x11
    db "isnempty", 0, 0, 0, 0, 0, 0, 0, 0x91
    db "istoken", 0, 0, 0, 0, 0, 0, 0, 0, 0x12
    db "isntoken", 0, 0, 0, 0, 0, 0, 0, 0x92
    db "ismacro", 0, 0, 0, 0, 0, 0, 0, 0, 0x13
    db "isnmacro", 0, 0, 0, 0, 0, 0, 0, 0x93
    db "isidn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x14
    db "isnidn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x94
    db "isidni", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x15
    db "isnidni", 0, 0, 0, 0, 0, 0, 0, 0, 0x95
    db "isenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x16
    db "isnenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x96
    db "isctx", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x17
    db "isnctx", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x97
    db "map", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x18
    db 0
