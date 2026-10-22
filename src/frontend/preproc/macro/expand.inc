; ============================================================================
; File        : src/frontend/preproc/macro/expand.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : multi-line macro expansion: starting, the next token, popping
; ============================================================================


; ---- prep_expand_start ------------------
;
; prep_expand_start
; Starts expanding a macro.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to MACRO struct
; Output   : rax = EXIT_OK or error code
;
global prep_expand_start
prep_expand_start:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = MACRO struct
    inc     dword [rel rec_suspend]        ; (the arguments: not an expression's)

    ; 0. Check recursion depth (A99)
    inc     word [rbx + PREP_mac_depth]
    cmp     word [rbx + PREP_mac_depth], MAX_MACRO_DEPTH
    jbe     .depth_ok
    
    mov rax, EXIT_MACRO_RECURSION
    jmp .error

.depth_ok:
    ; a number for each call of a multi-line macro (%%locals: NASM's
    ; ..@N.name) - not for a %define, a %rep body or a times line, which
    ; NASM does not count either. ASMCTX_mac_exp_id is the next number,
    ; from 0: NASM's one counter, which %push contexts and the directives
    ; NASM makes standard macros (section, global, align ...) take from
    ; too (prep_handle_push, parser_handle_pseudo_op)
    mov     r8, [rbx + PREP_ctx]
    cmp     qword [r12 + MACRO_name], 0
    je      .no_new_id
    test    byte [r12 + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
    jnz     .no_new_id
    inc     dword [r8 + ASMCTX_mac_exp_id]
.no_new_id:

    ; 1. Allocate MACROEXP struct
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACROEXP_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r13, rdx               ; r13 = MACROEXP struct

    mov     byte [r13 + MACROEXP_tag], TAG_MACRO_EXP
    mov     rax, [rel ml_pending00]        ; "f proc": f, for %00
    mov     [r13 + MACROEXP_label00], rax
    mov     qword [rel ml_pending00], 0
    mov     [r13 + MACROEXP_macro], r12
    mov     dword [r13 + MACROEXP_rep_count], 1 ; Default: expand once
    movzx   eax, byte [rel exp_lead]       ; a %define's name's blank
    mov     [r13 + MACROEXP_lead], al
    mov     byte [rel exp_lead], 0
    mov     eax, [rel exp_call_line]       ; ... and its line
    mov     [r13 + MACROEXP_line], eax
    mov     rax, [rel exp_call_file]
    mov     [r13 + MACROEXP_call_file], rax
    mov     dword [rel exp_call_line], 0
    mov     qword [rel exp_call_file], 0

    ; %%locals are unique per *macro* expansion. A %rep body is an anonymous
    ; macro running inside one, so it must reuse the enclosing id or the
    ; %%names inside the loop would not match those outside it.
    mov     r8, [rbx + PREP_ctx]
    mov     eax, [r8 + ASMCTX_mac_exp_id]
    dec     eax                            ; (the one just taken)
    cmp     qword [r12 + MACRO_name], 0
    jne     .own_exp_id
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .own_exp_id
    mov     eax, [r9 + MACROEXP_exp_id]
.own_exp_id:
    mov     [r13 + MACROEXP_exp_id], eax
    ; Check arity
    movzx   rax, word [r12 + MACRO_min_params]
    movzx   rdx, word [r12 + MACRO_max_params]
    ; A parameterless macro (every %define) needs no argument buffers
    test    edx, edx
    jnz     .has_params
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .has_params
    cmp     qword [r12 + MACRO_next], 0
    jne     .has_params                    ; an overload may take some
    xor     r15, r15
    ; "%macro m 0+": what follows the call is dropped, %0 is 0 (NASM's)
    test    byte [r12 + MACRO_flags], MACRO_FLAG_GREEDY
    jz      .done_params
    test    byte [r12 + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .done_params
.drop_args:
    sub     rsp, TOKEN_SIZE
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    movzx   ecx, byte [rsp + TOKEN_kind]
    add     rsp, TOKEN_SIZE
    test    rax, rax
    jnz     .done_params
    cmp     ecx, TOK_NEWLINE
    je      .done_params
    cmp     ecx, TOK_EOF
    je      .done_params
    sub     rsp, TOKEN_SIZE
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    add     rsp, TOKEN_SIZE
    jmp     .drop_args
.has_params:

    ; params[] and arglens[] for 4 arguments to start with; they double
    ; when a call has more (.grow_params)
    mov     r14, 4
    mov     [r13 + MACROEXP_pcap], r14d

.alloc_params:
    ; params[] : pointer to the first token of each argument
    mov     rsi, r14
    imul    rsi, 8
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx               ; r14 = param array

    ; arglens[] : token count per argument (dwords)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 4 * 4
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_arglens], rdx

    ; Every argument token, one after the other, in the capture area; they
    ; are copied out at their size once the call is read (.dflt_done)
    call    prep_cap_base
    check_err
    mov     [r13 + MACROEXP_pend_ptr], rdx     ; scratch: next free slot
    mov     dword [r13 + MACROEXP_pend_cnt], 0 ; scratch: slots used
    mov     [r13 + MACROEXP_body], rdx         ; the capture's base, until then

    xor     r15, r15               ; r15 = argument index
    mov     dword [rel fn_depth], 0
    mov     dword [rel brace_depth], 0
    mov     byte [rel brace_dropped], 0

    ; the argument from which a top-level comma no longer ends one: the
    ; greedy parameter's - for a %define, of any of its overloads, the
    ; one called chosen by the count after
    mov     dword [r13 + MACROEXP_greedy_at], -1
    mov     rax, r12
.greedy_walk:
    test    byte [rax + MACRO_flags], MACRO_FLAG_GREEDY
    jz      .greedy_next
    movzx   ecx, word [rax + MACRO_max_params]
    dec     ecx
    cmp     ecx, [r13 + MACROEXP_greedy_at]
    jae     .greedy_next
    mov     [r13 + MACROEXP_greedy_at], ecx
.greedy_next:
    test    byte [r12 + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .greedy_done                   ; a %macro: its own
    mov     rax, [rax + MACRO_next]
    test    rax, rax
    jnz     .greedy_walk
.greedy_done:

    ; A function-like %define takes its arguments in parentheses: NAME(a, b)
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .line_args
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .error_too_few_args
    jmp     .arg_loop
.line_args:

    ; A macro that declares no parameters consumes nothing from the line
    ; (unless an overload of it takes some).
    movzx   rax, word [r12 + MACRO_max_params]
    test    eax, eax
    jnz     .arg_loop
    cmp     qword [r12 + MACRO_next], 0
    je      .args_done

.arg_loop:
    cmp     r15, MACRO_PARAMS_MAX
    jae     .error_too_many_args
    cmp     r15d, [r13 + MACROEXP_pcap]
    jb      .arg_slot
    call    .grow_params
    test    rax, rax
    jnz     .error
.arg_slot:

    ; Start a new argument at the current cursor with a zero token count
    mov     rax, [r13 + MACROEXP_pend_ptr]
    mov     [r14 + r15 * 8], rax
    mov     rcx, [r13 + MACROEXP_arglens]
    mov     dword [rcx + r15 * 4], 0

.arg_token:
    ; the slot at pend_ptr, the capture area's top moved past it (a capture
    ; made while the token is read goes above)
    mov     rdi, [r13 + MACROEXP_body]
    mov     esi, [r13 + MACROEXP_pend_cnt]
    call    prep_cap_slot
    test    rax, rax
    jnz     .error

    ; Read through the preprocessor rather than the raw lexer: a macro
    ; called from inside another macro's body takes its arguments from
    ; the expansion, and %N arguments must already be substituted when
    ; they are captured.
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    mov     rsi, rdx
    mov     rdi, [r13 + MACROEXP_pend_ptr]
    copy_token

    mov     rsi, [r13 + MACROEXP_pend_ptr]
    movzx   eax, byte [rsi + TOKEN_kind]
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .arg_line_kinds
    ; "label(%??, _1)": %? / %?? in a single-line macro's arguments are its
    ; name (NASM's br3392711: label_1)
    cmp     al, TOK_DIRECTIVE
    jne     .fn_not_qq
    mov     rcx, [rsi + TOKEN_value]
    test    rcx, rcx
    jz      .fn_not_qq
    cmp     byte [rcx], '?'
    jne     .fn_not_qq
    cmp     byte [rcx + 1], 0
    je      .fn_qq
    cmp     byte [rcx + 1], '?'
    jne     .fn_not_qq
    cmp     byte [rcx + 2], 0
    jne     .fn_not_qq
.fn_qq:
    mov     rcx, [r12 + MACRO_name]
    test    rcx, rcx
    jz      .fn_not_qq
    mov     byte [rsi + TOKEN_kind], TOK_IDENT
    mov     [rsi + TOKEN_value], rcx
    mov     al, TOK_IDENT
.fn_not_qq:
    ; inside parentheses: nested ( ) belong to the argument, the closing )
    ; ends the call, a comma at depth 0 separates arguments
    cmp     al, TOK_LPAREN
    jne     .fn_not_open
    inc     dword [rel fn_depth]
    jmp     .arg_keep
.fn_not_open:
    cmp     al, TOK_RPAREN
    jne     .fn_not_close
    cmp     dword [rel fn_depth], 0
    je      .fn_end
    dec     dword [rel fn_depth]
    jmp     .arg_keep
.fn_end:
    inc     r15                            ; the last, empty or not: "f()" passes one
    jmp     .args_done
.fn_not_close:
    cmp     al, TOK_NEWLINE
    je      .error_too_few_args            ; no closing parenthesis
    cmp     al, TOK_EOF
    je      .error_too_few_args
    cmp     al, TOK_COMMA
    jne     .arg_keep
    cmp     dword [rel fn_depth], 0
    je      .arg_comma
    jmp     .arg_keep
.arg_line_kinds:
    cmp     al, TOK_NEWLINE
    je      .arg_end_all
    cmp     al, TOK_EOF
    je      .arg_end_all
    ; {a, b} is one argument, commas and all; the braces go
    cmp     al, TOK_LBRACE
    jne     .not_lbrace
    inc     dword [rel brace_depth]
    cmp     dword [rel brace_depth], 1
    jne     .arg_keep
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     dword [rcx + r15 * 4], 0
    jne     .arg_keep                      ; a brace inside an argument stays
    mov     byte [rel brace_dropped], 1
    jmp     .arg_token
.not_lbrace:
    cmp     al, TOK_RBRACE
    jne     .not_rbrace
    cmp     dword [rel brace_depth], 0
    je      .arg_keep
    dec     dword [rel brace_depth]
    jnz     .arg_keep
    cmp     byte [rel brace_dropped], 0
    je      .arg_keep
    mov     byte [rel brace_dropped], 0
    jmp     .arg_token
.not_rbrace:
    cmp     dword [rel brace_depth], 0
    jne     .arg_keep                      ; commas inside braces stay
    cmp     al, TOK_COMMA
    je      .arg_comma

    ; Keep this token as part of the current argument
.arg_keep:
    add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
    inc     dword [r13 + MACROEXP_pend_cnt]
    mov     rcx, [r13 + MACROEXP_arglens]
    inc     dword [rcx + r15 * 4]
    jmp     .arg_token

.arg_comma:
    ; the last parameter of a "+" macro keeps its commas
    cmp     r15d, [r13 + MACROEXP_greedy_at]
    jae     .arg_keep
.arg_end_one:
    ; A top-level comma ends this argument; the comma slot gets reused
    inc     r15
    jmp     .arg_loop

.arg_end_all:
    ; Newline or EOF ends the invocation. A trailing empty argument (the
    ; macro was invoked with no arguments at all) does not count.
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     dword [rcx + r15 * 4], 0
    je      .args_done
    inc     r15

.args_done:
    ; With overloads, the one whose parameter range takes this many
    mov     rax, r12
.pick:
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     r15d, ecx
    jb      .pick_next
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     ecx, MACRO_VARIADIC
    je      .picked
    cmp     r15d, ecx
    jbe     .picked
.pick_next:
    mov     rax, [rax + MACRO_next]
    test    rax, rax
    jnz     .pick
    mov     rax, r12                       ; none: the checks below report it
.picked:
    mov     r12, rax
    mov     [r13 + MACROEXP_macro], r12

    ; Arity checks
    movzx   eax, word [r12 + MACRO_min_params]
    cmp     r15d, eax
    jb      .error_too_few_args
    movzx   eax, word [r12 + MACRO_max_params]
    cmp     eax, MACRO_VARIADIC
    je      .arity_ok
    cmp     r15d, eax
    ja      .error_too_many_args
.arity_ok:

    ; Optional parameters not given take their defaults: default d is the
    ; d-th comma-separated piece of the list, for parameter min + d - as
    ; many as the list has, as NASM counts them: "%macro m 1 a" called with
    ; one sees %0 = 2, "0-* a,b" with none sees a and b; with "+" the
    ; last parameter takes the rest of the list ("1-2+ a,b": %2 is a,b)
    cmp     dword [r12 + MACRO_ndefaults], 0
    je      .dflt_done
    mov     rax, [r12 + MACRO_defaults]
    mov     ecx, [r12 + MACRO_ndefaults]
    mov     edx, 1                         ; the pieces
.dflt_count:
    cmp     byte [rax + TOKEN_kind], TOK_COMMA
    jne     .dflt_count_next
    inc     edx
.dflt_count_next:
    add     rax, TOKEN_SIZE
    dec     ecx
    jnz     .dflt_count
    movzx   eax, word [r12 + MACRO_min_params]
    add     edx, eax                       ; the parameters they make up
    test    byte [r12 + MACRO_flags], MACRO_FLAG_GREEDY
    jz      .dflt_target
    movzx   eax, word [r12 + MACRO_max_params]
    cmp     eax, MACRO_VARIADIC
    je      .dflt_target
    cmp     edx, eax
    jbe     .dflt_target
    mov     edx, eax                       ; "+": no more than its count
.dflt_target:
    mov     [rel dflt_target], edx
.dflt_next:
    cmp     r15d, [rel dflt_target]
    jae     .dflt_done
    cmp     r15d, [r13 + MACROEXP_pcap]
    jb      .dflt_slot
    call    .grow_params
    test    rax, rax
    jnz     .error
.dflt_slot:
    movzx   ecx, word [r12 + MACRO_min_params]
    mov     edx, r15d
    sub     edx, ecx                       ; d
    mov     r8, [r12 + MACRO_defaults]
    mov     r9d, [r12 + MACRO_ndefaults]   ; tokens left
.dflt_seek:
    test    edx, edx
    jz      .dflt_piece
.dflt_seek_tok:
    test    r9d, r9d
    jz      .dflt_piece                    ; past the list: empty
    movzx   eax, byte [r8 + TOKEN_kind]
    add     r8, TOKEN_SIZE
    dec     r9d
    cmp     eax, TOK_COMMA
    jne     .dflt_seek_tok
    dec     edx
    jmp     .dflt_seek
.dflt_piece:
    mov     [r14 + r15 * 8], r8
    ; the greedy last parameter: the rest of the list, commas and all
    test    byte [r12 + MACRO_flags], MACRO_FLAG_GREEDY
    jz      .dflt_one
    movzx   eax, word [r12 + MACRO_max_params]
    dec     eax
    cmp     r15d, eax
    jne     .dflt_one
    mov     ecx, r9d
    jmp     .dflt_len_done
.dflt_one:
    xor     ecx, ecx
.dflt_len:
    cmp     ecx, r9d
    jae     .dflt_len_done
    imul    rax, rcx, TOKEN_SIZE
    cmp     byte [r8 + rax + TOKEN_kind], TOK_COMMA
    je      .dflt_len_done
    inc     ecx
    jmp     .dflt_len
.dflt_len_done:
    mov     rax, [r13 + MACROEXP_arglens]
    mov     [rax + r15 * 4], ecx
    inc     r15
    jmp     .dflt_next
.dflt_done:
    ; The argument tokens at their size, out of the capture area; params[]
    ; pointing into it moves with them (a default points at the macro's own
    ; list)
    mov     rdi, rbx
    mov     rsi, [r13 + MACROEXP_body]
    mov     edx, [r13 + MACROEXP_pend_cnt]
    call    prep_cap_take
    test    rax, rax
    jnz     .error
    ; the tokens in the arguments of every call open, at most NASM's
    ; macro-tokens: past it a macro calls itself with a longer argument
    ; each time ("r %1-1": quadratic - 2 GB and seconds by 10,000 levels)
    mov     eax, [r13 + MACROEXP_pend_cnt]
    mov     [r13 + MACROEXP_argtoks], rax
    add     rax, [rel prep_mac_args]
    mov     [rel prep_mac_args], rax
    cmp     rax, MAX_MACRO_ARGS_TOKENS
    jbe     .args_ok
    mov     eax, EXIT_MACRO_RECURSION      ; "runaway recursion?" (fatal)
    jmp     .error
.args_ok:
    mov     rsi, [r13 + MACROEXP_body]     ; the old base
    mov     r8, rdx
    sub     r8, rsi                        ; how far they moved
    mov     ecx, [r13 + MACROEXP_pend_cnt]
    imul    rcx, rcx, TOKEN_SIZE
    add     rcx, rsi                       ; the old end
    xor     r9d, r9d
.rebase:
    cmp     r9, r15
    jae     .rebased
    mov     rax, [r14 + r9 * 8]
    cmp     rax, rsi
    jb      .rebase_next
    cmp     rax, rcx
    ja      .rebase_next
    add     rax, r8
    mov     [r14 + r9 * 8], rax
.rebase_next:
    inc     r9
    jmp     .rebase
.rebased:
    mov     qword [r13 + MACROEXP_body], 0 ; the body starts at its first token

    ; Release the collection scratch: these fields drive substitution now
    mov     qword [r13 + MACROEXP_pend_ptr], 0
    mov     dword [r13 + MACROEXP_pend_cnt], 0
    jmp     .done_params

; .grow_params: params[] and arglens[] twice the size, the entries so far
; copied over; r14 = the new params[]. rax = OK or an error.
.grow_params:
    mov     rdi, [rbx + PREP_arena]
    mov     esi, [r13 + MACROEXP_pcap]
    shl     rsi, 4                         ; twice, 8 bytes each
    call    arena_alloc
    test    rax, rax
    jnz     .gp_ret
    mov     rdi, rdx
    mov     rsi, [r13 + MACROEXP_params]
    mov     ecx, [r13 + MACROEXP_pcap]
    rep movsq
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx
    mov     rdi, [rbx + PREP_arena]
    mov     esi, [r13 + MACROEXP_pcap]
    shl     rsi, 3                         ; twice, 4 bytes each
    call    arena_alloc
    test    rax, rax
    jnz     .gp_ret
    mov     rdi, rdx
    mov     rsi, [r13 + MACROEXP_arglens]
    mov     ecx, [r13 + MACROEXP_pcap]
    rep movsd
    mov     [r13 + MACROEXP_arglens], rdx
    shl     dword [r13 + MACROEXP_pcap], 1
    xor     eax, eax
.gp_ret:
    ret

.error_too_few_args:
.error_too_many_args:
    mov     rax, [r13 + MACROEXP_body]     ; the capture area back
    test    rax, rax
    jz      .arity_report
    mov     [rel cap_top], rax
.arity_report:
    mov     rdi, [r13 + MACROEXP_macro]    ; "multi-line macro `m' does not
    mov     rdi, [rdi + MACRO_name]        ;  take this number of parameters"
    call    error_set_subject
    mov     rax, EXIT_MACRO_ARITY_FAIL
    jmp     .error

.done_params:
    mov     [r13 + MACROEXP_nparams], r15w
    
    ; 3. Link to previous
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    mov     [r13 + MACROEXP_parent], r9
    mov     [r8 + ASMCTX_mac_exp], r13

    ; not listed: a .nolist macro's expansion, and any inside one
    ; (error_track_token)
    xor     eax, eax
    test    byte [r12 + MACRO_flags], MACRO_FLAG_NOLIST
    setnz   al
    test    r9, r9
    jz      .nolist_set
    or      al, [r9 + MACROEXP_nolist]
    ; inside a .nolist one everything is on the line it was called on
    ; (-E), a %rep's too
    cmp     byte [r9 + MACROEXP_nolist], 0
    je      .nolist_set
    mov     rcx, [r9 + MACROEXP_call_file]
    mov     [r13 + MACROEXP_call_file], rcx
    mov     ecx, [r9 + MACROEXP_line]
    mov     [r13 + MACROEXP_line], ecx
.nolist_set:
    mov     [r13 + MACROEXP_nolist], al

    ; the listing's <N> (error_track_token): the macro and %rep expansions
    ; open around this one, from its parent's - counting them per token
    ; walked every open expansion
    xor     eax, eax
    xor     ecx, ecx
    xor     edx, edx
    test    r9, r9
    jz      .nest_own
    mov     eax, [r9 + MACROEXP_lst_depth]
    mov     rcx, [r9 + MACROEXP_lst_first]
    mov     rdx, [r9 + MACROEXP_lst_second]
.nest_own:
    mov     r10, [r13 + MACROEXP_macro]
    test    byte [r10 + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
    jnz     .nest_set
    inc     eax
    mov     rdx, rcx
    mov     rcx, r13
.nest_set:
    mov     [r13 + MACROEXP_lst_depth], eax
    mov     [r13 + MACROEXP_lst_first], rcx
    mov     [r13 + MACROEXP_lst_second], rdx

    xor     rax, rax
    mov     rdx, r13               ; Return expansion struct in RDX (A99)
    jmp     .done

.error_pop_token:
    add     rsp, TOKEN_SIZE
    jmp     .error

.error_expected_comma:
    add     rsp, TOKEN_SIZE
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .done

.done:
    dec     dword [rel rec_suspend]
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

.error:
    jmp     .done

; ---- prep_expand_next -------------------
;
; prep_expand_next
; Serves the next token from the current macro expansion.
; Handles parameter substitution.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (destination)
; Output   : rax = 0 (produced token) or non-zero (finished)
;
prep_expand_next:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token dest

    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp] ; r13 = current expansion
    test    r13, r13
    jz      .finished

    ; 0. An argument spanning several tokens is served one token per call
    mov     eax, [r13 + MACROEXP_pend_cnt]
    test    eax, eax
    jz      .no_pending
        mov     rsi, [r13 + MACROEXP_pend_ptr]
        mov     rdi, r12
        copy_token
        add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
        dec     dword [r13 + MACROEXP_pend_cnt]
        jmp     .produced
.no_pending:

.retry_body:
    ; 1. Get current token index
    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .expansion_end

    ; 2. Copy token from macro body
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = source token

    ; copy to dest
    mov     rdi, r12
    mov     rsi, r10
    copy_token

    ; increment body pos
    inc     qword [r13 + MACROEXP_body]

    ; 2.4 "%,": NASM's conditional comma - a comma unless the body ends
    ; after it, or what follows is a parameter given empty
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .not_cond_comma
    mov     rax, [r12 + TOKEN_value]
    cmp     word [rax], ','
    jne     .not_cond_comma
    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .retry_body                    ; the end: nothing
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax                       ; the token after it
    cmp     byte [r10 + TOKEN_kind], TOK_DIRECTIVE
    jne     .cond_comma_put
    mov     rdi, [r10 + TOKEN_value]
    movzx   eax, byte [rdi]
    sub     eax, '1'
    cmp     eax, 8
    ja      .cond_comma_put
    cmp     byte [rdi + 1], 0
    jne     .cond_comma_put                ; not %1 .. %9
    movzx   ecx, word [r13 + MACROEXP_nparams]
    cmp     eax, ecx
    jae     .retry_body                    ; a parameter not given: empty
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     dword [rcx + rax * 4], 0
    je      .retry_body                    ; given empty
.cond_comma_put:
    mov     byte [r12 + TOKEN_kind], TOK_COMMA
    mov     qword [r12 + TOKEN_value], 0
    mov     word [r12 + TOKEN_len], 1
    jmp     .produced
.not_cond_comma:

    ; 2.5 Handle Stringification (#) (A67)
    cmp     byte [r12 + TOKEN_kind], TOK_HASH
    jne     .not_hash
        ; Peek at NEXT token in macro body
        mov     rax, [r13 + MACROEXP_body]
        mov     r9, [r13 + MACROEXP_macro]
        cmp     eax, [r9 + MACRO_ntokens]
        jge     .produced              ; Nothing after #
        
        mov     r10, [r9 + MACRO_tokens]
        imul    rax, TOKEN_SIZE
        add     r10, rax               ; r10 = potential parameter ref
        
        cmp     byte [r10 + TOKEN_kind], TOK_DIRECTIVE
        jne     .not_hash
            ; Check if it's %1-%9
            mov     rdi, [r10 + TOKEN_value]
            movzx   rax, byte [rdi]
            sub     al, '0'
            cmp     al, 1
            jl      .not_hash
            cmp     al, 9
            jg      .not_hash
                ; Yes, it's stringification!
                ; 1. Consume the directive token
                inc     qword [r13 + MACROEXP_body]
                
                ; 2. Get the parameter token
                dec     al
                movzx   rax, al
                mov     r11, [r13 + MACROEXP_params]
                mov     rsi, [r11 + rax * 8]   ; rsi = param token
                
                ; 3. Stringify it (Create a TOK_STRING)
                mov     byte [r12 + TOKEN_kind], TOK_STRING
                
                ; Use TOKEN_value or name string? 
                ; For TOK_IDENT, use value. For others, we need a helper.
                ; Simple implementation: use the value directly if it's already a string.
                mov     rax, [rsi + TOKEN_value]
                mov     [r12 + TOKEN_value], rax
                
                jmp     .produced
.not_hash:

    ; 3. Handle parameter substitution
    ; Macro parameters are TOK_DIRECTIVE with value like "0", "1", "2"...
    ; A %%local is not a directive, so send it on to CASE 4 rather than
    ; letting it pass through unresolved.
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    je      .not_case3
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .produced

    mov     rdi, [r12 + TOKEN_value]
    movzx   rax, byte [rdi]

    ; CASE 0: %? / %??, the name of the macro being expanded (as called,
    ; as defined: the same, names keeping their case)
    cmp     al, '?'
    jne     .not_case0
    cmp     byte [rdi + 1], 0
    je      .case0
    cmp     byte [rdi + 1], '?'
    jne     .not_case0
    cmp     byte [rdi + 2], 0
    jne     .not_case0
.case0:
        mov     r11, r13
        xor     r10d, r10d                 ; the nearest single-line macro's name
.name_owner:
        mov     rax, [r11 + MACROEXP_macro]
        test    byte [rax + MACRO_flags], MACRO_FLAG_TIMES
        jnz     .name_up
        test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
        jz      .name_multi
        test    r10, r10
        jnz     .name_up
        mov     r10, [rax + MACRO_name]
        jmp     .name_up
.name_multi:
        mov     rax, [rax + MACRO_name]
        test    rax, rax
        jnz     .name_found
.name_up:
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .name_owner
        ; no multi-line macro around it: a single-line one's, as NASM's
        ; "%define label(p, s) p %+ s" / "label(%??, _1)" is label_1
        mov     rax, r10
        test    rax, rax
        jnz     .name_found
        jmp     .retry_body
.name_found:
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], rax
        jmp     .produced
.not_case0:

    ; CASE 00: %00, the label written before the call ("f proc"), or
    ; nothing; a %rep body inside takes its macro's
    cmp     al, '0'
    jne     .not_case00
    cmp     byte [rdi + 1], '0'
    jne     .not_case00
    cmp     byte [rdi + 2], 0
    jne     .not_case00
        mov     r11, r13
.l00_owner:
        mov     rax, [r11 + MACROEXP_label00]
        test    rax, rax
        jnz     .l00_found
        mov     rax, [r11 + MACROEXP_macro]
        cmp     qword [rax + MACRO_name], 0
        jne     .l00_none                  ; a macro called with none
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .l00_owner
.l00_none:
        ; nothing, and "%00:" no empty label: its colon goes too
        mov     rax, [r13 + MACROEXP_body]
        mov     r9, [r13 + MACROEXP_macro]
        cmp     eax, [r9 + MACRO_ntokens]
        jge     .retry_body
        imul    rax, TOKEN_SIZE
        add     rax, [r9 + MACRO_tokens]
        cmp     byte [rax + TOKEN_kind], TOK_COLON
        jne     .retry_body
        inc     qword [r13 + MACROEXP_body]
        jmp     .retry_body
.l00_found:
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], rax
        jmp     .produced
.not_case00:

    ; CASE 1: %0 (Parameter Count)
    cmp     al, '0'
    jne     .not_case1
        ; Allocate space for the number string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .expansion_end ; or other error
        
        mov     rdi, rdx       ; dst
        movzx   rsi, word [r13 + MACROEXP_nparams]
        extern  str_int_to_str
        call    str_int_to_str
        
        mov     byte [r12 + TOKEN_kind], TOK_NUMBER
        mov     [r12 + TOKEN_value], rdx ; pointer to formatted string
        jmp     .produced
.not_case1:

    ; CASE 2: %1, %2, ... %32 (Parameter Reference), also %{2}
    xor     eax, eax
    mov     rsi, rdi
    cmp     byte [rsi], '{'                ; the lexer keeps the text after it
    jne     .pnum
    inc     rsi
.pnum:
    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .pnum_done
    cmp     ecx, '}'
    je      .pnum_done
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .not_case2
    imul    eax, eax, 10
    add     eax, ecx
    cmp     eax, MACRO_PARAMS_MAX
    ja      .not_case2
    inc     rsi
    jmp     .pnum
.pnum_done:
    test    eax, eax
    jz      .not_case2
        ; it's a param ref! (1-9)
        ; A %rep body running inside a macro has no parameters of its own,
        ; so walk out to the nearest expansion that does.
        mov     r11, r13
.param_owner_loop:
        cmp     word [r11 + MACROEXP_nparams], 0
        jne     .param_owner_found
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .param_owner_loop
        jmp     .retry_body
.param_owner_found:

        ; check if it is within nparams
        movzx   ecx, word [r11 + MACROEXP_nparams]
        cmp     eax, ecx
        ja      .retry_body            ; optional parameter not supplied:
                                       ; substitute nothing rather than leaking
                                       ; "%4" out as a stray directive token

        ; Substitute the argument. An argument may span several tokens: emit
        ; the first here and leave the rest pending for the next calls.
        dec     eax                    ; 0-indexed (rax: eax zero-extended)
        mov     r10, r11               ; r10 = expansion owning the parameters
        mov     r11, [r10 + MACROEXP_arglens]
        mov     ecx, [r11 + rax * 4]   ; rcx = token count of this argument
        test    rcx, rcx
        jz      .retry_body            ; empty argument: substitute nothing

        mov     r11, [r10 + MACROEXP_params]
        mov     rsi, [r11 + rax * 8]   ; rsi = first token of the argument

        dec     rcx
        mov     [r13 + MACROEXP_pend_cnt], ecx
        lea     rax, [rsi + TOKEN_SIZE]
        mov     [r13 + MACROEXP_pend_ptr], rax

        movzx   r8d, byte [r12 + TOKEN_flags]
        mov     r9d, [r12 + TOKEN_line]
        mov     r10, [r12 + TOKEN_file]
        mov     rdi, r12
        copy_token
        call    .param_at
        jmp     .produced
.not_case2:

    ; CASE 3a: %{a:b}, the arguments a to b (b < a: in reverse; a negative
    ; one counts from the last), separated by commas
    mov     rsi, rdi
.rng_colon:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .not_range
    cmp     eax, ':'
    je      .range
    inc     rsi
    jmp     .rng_colon
.range:
    cmp     byte [rdi], '{'            ; the lexer keeps the text after it
    jne     .range_open
    inc     rdi
.range_open:
    call    .parse_sint
    cmp     byte [rdi], ':'
    jne     .not_range
    mov     [rel rng_a], rax
    inc     rdi
    call    .parse_sint
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .range_closed
    cmp     ecx, '}'
    jne     .not_range
.range_closed:
    mov     [rel rng_b], rax
    mov     r11, r13
.rng_owner:
    cmp     word [r11 + MACROEXP_nparams], 0
    jne     .rng_found
    mov     r11, [r11 + MACROEXP_parent]
    test    r11, r11
    jnz     .rng_owner
    jmp     .retry_body
.rng_found:
    mov     [rel rng_owner], r11
    movzx   ecx, word [r11 + MACROEXP_nparams]
    mov     rax, [rel rng_a]
    test    rax, rax
    jns     .rng_a_ok
    lea     rax, [rcx + rax + 1]
    mov     [rel rng_a], rax
.rng_a_ok:
    cmp     rax, 1
    jl      .retry_body
    cmp     rax, rcx
    jg      .retry_body
    mov     rax, [rel rng_b]
    test    rax, rax
    jns     .rng_b_ok
    lea     rax, [rcx + rax + 1]
    mov     [rel rng_b], rax
.rng_b_ok:
    cmp     rax, 1
    jl      .retry_body
    cmp     rax, rcx
    jg      .retry_body
    ; tokens: the arguments and a comma between each two
    mov     r9, [rel rng_a]
    xor     r8d, r8d
.rng_count:
    mov     r11, [rel rng_owner]
    mov     r10, [r11 + MACROEXP_arglens]
    mov     eax, [r10 + r9 * 4 - 4]
    add     r8, rax
    cmp     r9, [rel rng_b]
    je      .rng_counted
    inc     r8                             ; the comma
    call    .rng_step
    jmp     .rng_count
.rng_counted:
    test    r8, r8
    jz      .retry_body
    mov     [rel rng_total], r8
    mov     rdi, [rbx + PREP_arena]
    imul    rsi, r8, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .retry_body
    mov     [rel rng_buf], rdx
    mov     r8, rdx                        ; where the next token goes
    mov     r9, [rel rng_a]
.rng_fill:
    mov     r11, [rel rng_owner]
    mov     r10, [r11 + MACROEXP_arglens]
    mov     ecx, [r10 + r9 * 4 - 4]
    imul    ecx, ecx, TOKEN_SIZE
    mov     r10, [r11 + MACROEXP_params]
    mov     rsi, [r10 + r9 * 8 - 8]
    mov     rdi, r8
    rep movsb
    mov     r8, rdi
    cmp     r9, [rel rng_b]
    je      .rng_filled
    mov     rdi, r8
    mov     rsi, r12                       ; the use's line and column
    copy_token
    mov     byte [r8 + TOKEN_kind], TOK_COMMA
    mov     qword [r8 + TOKEN_value], 0
    mov     byte [r8 + TOKEN_flags], 0
    add     r8, TOKEN_SIZE
    call    .rng_step
    jmp     .rng_fill
.rng_filled:
    ; the first token now, the rest pending
    mov     rsi, [rel rng_buf]
    mov     rcx, [rel rng_total]
    dec     rcx
    mov     [r13 + MACROEXP_pend_cnt], ecx
    lea     rax, [rsi + TOKEN_SIZE]
    mov     [r13 + MACROEXP_pend_ptr], rax
    movzx   r8d, byte [r12 + TOKEN_flags]
    mov     r9d, [r12 + TOKEN_line]
    mov     r10, [r12 + TOKEN_file]
    mov     rdi, r12
    copy_token
    call    .param_at
    jmp     .produced

; .param_at: the token put in place of a parameter (r8b, r9d, r10: the
; parameter's flags, line, file) has its blank (.lead_of) and, for -E, its
; line: a body's line that starts with "%1" is the body's, as NASM's
.param_at:
    cmp     byte [rel lexer_mark_lone], 0
    je      .lead_of
    mov     [r12 + TOKEN_line], r9d
    mov     [r12 + TOKEN_file], r10
; .lead_of: the token put in place of a parameter has its blank before it
; (r8b: the parameter's flags), not the argument's own, as NASM trims it
.lead_of:
    and     r8d, TOK_FLAG_SPACE
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_SPACE
    or      [r12 + TOKEN_flags], r8b
    ret

; r9 one step from rng_a toward rng_b
.rng_step:
    cmp     r9, [rel rng_b]
    jl      .rng_up
    dec     r9
    ret
.rng_up:
    inc     r9
    ret

; rax = the signed decimal at rdi; rdi past it
.parse_sint:
    xor     eax, eax
    xor     edx, edx
.ps_lead:
    cmp     byte [rdi], ' '                ; "%{2: 3}": blanks around it
    je      .ps_skip
    cmp     byte [rdi], 9
    jne     .ps_sign
.ps_skip:
    inc     rdi
    jmp     .ps_lead
.ps_sign:
    cmp     byte [rdi], '-'
    jne     .ps_digit
    mov     edx, 1
    inc     rdi
.ps_digit:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .ps_end
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .ps_digit
.ps_end:
    cmp     byte [rdi], ' '
    je      .ps_trail
    cmp     byte [rdi], 9
    jne     .ps_sign_done
.ps_trail:
    inc     rdi
    jmp     .ps_end
.ps_sign_done:
    test    edx, edx
    jz      .ps_ret
    neg     rax
.ps_ret:
    ret

.not_range:
    mov     rdi, [r12 + TOKEN_value]

    ; CASE 3: Variadic Expansion %{n..} (A69)
    cmp     byte [rdi], '{'
    jne     .not_case3
        ; parse braced parameter ref like "{1..}"
        inc     rdi                    ; skip {
        
        ; simple parser for digit
        movzx   rax, byte [rdi]
        sub     al, '0'
        cmp     al, 1
        jl      .not_case3
        cmp     al, 9
        jg      .not_case3
            ; r14 = starting index (1-based)
            movzx   r14, al
            
            ; check for ".." suffix
            cmp     byte [rdi + 1], '.'
            jne     .not_case3
            cmp     byte [rdi + 2], '.'
            jne     .not_case3
                ; It's %{n..}!
                ; We need to expand all params from r14 to nparams.
                ; This is complex for a single prep_expand_next call 
                ; because it returns one token.
                ; For now, we'll implement it by expanding the FIRST 
                ; param in the range and setting a flag to expand 
                ; the rest in subsequent calls? 
                
                ; Better: if nparams > r14, we expand r14 and then 
                ; we'd need to inject commas.
                ; To keep it simple for now, we'll support %{n..} as a 
                ; way to get ALL arguments from n onwards as a single 
                ; space-separated sequence if captured greedy.
                
                ; If the parameter was captured via prep_capture_greedy, 
                ; it is ALREADY a single string.
                movzx   ecx, word [r13 + MACROEXP_nparams]
                cmp     r14d, ecx
                ja      .produced      ; Out of range
                
                dec     r14b           ; 0-indexed
                mov     r11, [r13 + MACROEXP_params]
                movzx   rax, r14b
                mov     rsi, [r11 + rax * 8]
                
                mov     rdi, r12
                copy_token
                jmp     .produced
.not_case3:

    ; CASE 4: Macro Local Label %% (A70)
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    jne     .not_case4
        ; Expand to ..@ID_label
        mov     r14d, dword [r13 + MACROEXP_exp_id]
        
        ; 1. Allocate buffer for ID string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r15, rdx               ; r15 = ID string buffer
        
        mov     rdi, r15
        mov     rsi, r14               ; value
        extern  str_int_to_str
        call    str_int_to_str
        
        ; 2. Allocate the label: "..@" + ID + "." + name + NUL. Only what it
        ;    needs: compile_time_hash expands its %%names once per character,
        ;    so a MAX_TOKEN buffer each time used up the arena on large tables.
        mov     rdi, r15
        call    str_len
        mov     r14, rax
        mov     rdi, [r12 + TOKEN_value]
        call    str_len
        lea     rsi, [r14 + rax + 5]
        mov     rdi, [rbx + PREP_arena]
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r14, rdx               ; r14 = final label buffer
        
        ; 3. Construct "..@ID.label", as NASM names it
        mov     byte [r14], '.'
        mov     byte [r14+1], '.'
        mov     byte [r14+2], '@'
        mov     byte [r14+3], 0
        
        mov     rdi, r14
        mov     rsi, r15               ; ID string
        extern  str_concat
        call    str_concat
        mov     rdi, r14
        lea     rsi, [rel s_dot]
        call    str_concat
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value] ; original label name
        call    str_concat
        
        ; Update token
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], r14
        jmp     .produced
.not_case4:

.produced:
    ; a %define's first token: the blank its name had (MACROEXP_lead)
    mov     r8, [rbx + PREP_ctx]
    mov     r8, [r8 + ASMCTX_mac_exp]
    test    r8, r8
    jz      .lead_done
    ; -E: what a %define gives is on the line it was used on, as NASM
    ; writes it ("%line" before it); so is what a .nolist macro gives, and
    ; everything called inside it (NASM's noline)
    cmp     byte [rel lexer_mark_lone], 0
    je      .line_kept
    mov     rax, [r8 + MACROEXP_call_file]
    test    rax, rax
    jz      .line_kept
    cmp     byte [r8 + MACROEXP_nolist], 0
    jne     .line_call
    mov     rcx, [r8 + MACROEXP_macro]
    test    byte [rcx + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .line_kept
.line_call:
    mov     [r12 + TOKEN_file], rax
    mov     eax, [r8 + MACROEXP_line]
    mov     [r12 + TOKEN_line], eax
.line_kept:
    movzx   eax, byte [r8 + MACROEXP_lead]
    test    eax, eax
    jz      .lead_done
    mov     byte [r8 + MACROEXP_lead], 0
    mov     r8d, eax
    call    .lead_of
.lead_done:
    ; ---- A68: Token Concatenation (##) ----
.check_concat:
    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp]
    test    r13, r13
    jz      .done_concat

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .done_concat
    
    ; Peek at next token
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = next token in body
    
    IF byte [r10 + TOKEN_kind], e, TOK_CONCAT
        ; 1. Consume ##
        inc     qword [r13 + MACROEXP_body]
        
        ; 2. Get the NEXT operand (A ## B)
        ; We need to produce the next token into a temp buffer
        sub     rsp, TOKEN_SIZE
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_expand_next
        IF rax, ne, 0
            ; Error or expansion end (unexpected)
            add     rsp, TOKEN_SIZE
            jmp     .done_concat
            ENDIF
        
        ; 2.5 Both operands may still carry %[...] or %$ text: resolve them
        ;     before joining, so ".if_ %+ %$uid" pastes the context's value.
        test    byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_lhs_ready
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_resolve_interp
.concat_lhs_ready:
        test    byte [rsp + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_rhs_ready
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_resolve_interp
.concat_rhs_ready:
        ; %assign / %define names paste as their value
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_subst_const_text
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_subst_const_text

        ; 3. Concatenate r12 (merged so far) and rsp (next token)
        ; Allocate space for combined string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, MAX_TOKEN
        extern  arena_alloc
        call    arena_alloc
        test    rax, rax
        jnz     .done_concat           ; OOM or error
        
        mov     r14, rdx               ; r14 = concat buffer
        mov     byte [r14], 0          ; null-terminate before str_concat
        
        ; the pieces' text - an operator's too ("1e %+ + %+ 5" is 1e+5)
        mov     rdx, r12
        call    prep_idn_text
        mov     rdi, r14
        mov     rsi, rax
        extern  str_concat
        call    str_concat

        mov     rdx, rsp
        call    prep_idn_text
        mov     rdi, r14
        mov     rsi, rax
        call    str_concat
        
        ; 4. Update r12 to be the merged token. When the right-hand piece
        ;    carried the ':' (".lbl_ %+ id %+ _end:"), the join is still a
        ;    label definition, not a plain identifier.
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     cl, [rsp + TOKEN_kind]
        cmp     cl, TOK_LABEL
        je      .concat_is_label
        cmp     cl, TOK_LOCAL_LABEL
        jne     .concat_kind_set
.concat_is_label:
        mov     byte [r12 + TOKEN_kind], TOK_LABEL
        cmp     byte [r14], '.'
        jne     .concat_kind_set
        mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
.concat_kind_set:
        mov     [r12 + TOKEN_value], r14
        ; a join that is more than one token (1e+5): read again, as NASM's
        ; scanner reads the pasted line (preprocessor_next_token)
        mov     rsi, r14
        call    prep_text_splits
        test    eax, eax
        jz      .concat_one
        or      byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
.concat_one:

        add     rsp, TOKEN_SIZE
        jmp     .check_concat          ; Chain: allow A ## B ## C
        ENDIF

.done_concat:
    xor     rax, rax
    jmp     .done

.expansion_end:
    ; Check for %rep loop
    cmp     dword [r13 + MACROEXP_rep_count], 1
    jle     .do_pop
    
    dec     dword [r13 + MACROEXP_rep_count]
    mov     qword [r13 + MACROEXP_body], 0
    mov     rax, 1                 ; try again (retry expansion from start of loop)
    jmp     .done

.do_pop:
    mov     rdi, rbx
    call    prep_expand_pop
    ; we finished this expansion, but there might be a parent
    ; we return non-zero to tell caller to try again (which will check mac_exp again)
    mov     rax, 1
    jmp     .done

.finished:
    mov     rax, 1

.done:
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

[SECTION .bss]
prep_mac_args:  resq 1              ; the tokens of the open calls' arguments
[SECTION .text]

global prep_expand_pop
prep_expand_pop:
    prologue
    push    rbx
    push    r12                    ; Alignment padding
    mov     rbx, rdi
    
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .done
    
    ; Decrease depth, and the arguments' tokens
    dec     word [rbx + PREP_mac_depth]
    mov     rax, [r9 + MACROEXP_argtoks]
    sub     [rel prep_mac_args], rax
    
    ; Pop from expansion stack
    mov     rax, [r9 + MACROEXP_parent]
    mov     [r8 + ASMCTX_mac_exp], rax
    
.done:
    pop     r12
    pop     rbx
    epilogue
    ret
