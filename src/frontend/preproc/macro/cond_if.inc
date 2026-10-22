; ============================================================================
; File        : src/frontend/preproc/macro/cond_if.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %if / %else / %endif, skipping macro and %rep blocks, counts
; ============================================================================


; ---- prep_handle_if ---------------------
;
; prep_handle_if
; Handles the %if directive by evaluating a mathematical expression.
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_if:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. If we are already skipping, just increment depth
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .already_skipping

    ; 2. Evaluate expression
    mov     rdi, rbx
    call    prep_drop_stale_newline
    extern  expr_undef_uses
    mov     qword [rel expr_undef_uses], 0
    mov     rdi, rbx
    extern  parser_evaluate_pp
    call    parser_evaluate_pp
    test    rax, rax
    jnz     .done
    lea     rdi, [rel s_cn_if]
    cmp     byte [rel cond_negate], 0
    je      .if_named
    lea     rdi, [rel s_cn_ifn]
.if_named:
    call    prep_const_check
    test    rax, rax
    jnz     .done
    mov     esi, 1
    call    prep_trailing_expr             ; "%if 1 x": the x ignored

    ; 3. Push the level with the result (%ifn: the other way)
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    xor     sil, [rel cond_negate]
    mov     byte [rel cond_negate], 0
    mov     rdi, rbx
    call    prep_cond_enter
    jmp     .done

.already_skipping:
    mov     byte [rel cond_negate], 0
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_enter

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_const_check -------------------
;
; The value of a %if or %assign must be a number now: a name not defined
; yet is "symbol `foo' not defined before use" (the first one; NASM's
; preprocessor reads the line once, a label further on is not known to
; it), a label or an extern "non-constant value given to `%if'".
; Input    : rbx = PrepState, rdi = the directive's name (no %), rcx /
;            r11 as parser_evaluate_expression left them
; Output   : rax = 0 or the error (its subject set); rdx kept when 0
;
prep_const_check:
    xor     eax, eax
    cmp     qword [rel expr_undef_uses], 0
    jne     .undef
    test    rcx, rcx
    jnz     .nonconst                      ; a kept expression of labels
    push    rdi
    mov     rdi, r11
    extern  expr_sym_class
    call    expr_sym_class
    pop     rdi
    test    eax, eax
    jnz     .nonconst_set
    ret
.nonconst_set:
    xor     eax, eax
.nonconst:
    call    error_set_subject
    mov     eax, EXIT_PP_NONCONST
    ret
.undef:
    ; an extern has no section either: not a number, but declared
    push    rdi
    extern  expr_undef_first
    mov     rsi, [rel expr_undef_first]
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    pop     rdi
    test    rax, rax
    jnz     .undef_named
    movzx   eax, byte [rdx + SYMBOL_kind]
    cmp     eax, SYM_EXTERN
    je      .nonconst_set
    cmp     eax, SYM_COMMON
    je      .nonconst_set
.undef_named:
    mov     rdi, [rel expr_undef_first]
    call    error_set_subject
    mov     eax, EXIT_UNDEF_BEFORE
    ret

[SECTION .rodata]
s_cn_if:     db "if", 0
s_cn_ifn:    db "ifn", 0
s_cn_assign: db "assign", 0
[SECTION .text]

; ---- prep_handle_else -------------------
prep_handle_else:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     ax, [rbx + PREP_depth]
    test    ax, ax
    jz      .error                 ; %else without %if
    movzx   r12d, word [rbx + PREP_skip_depth]   ; > 1: an outer level skips
    movzx   eax, word [rbx + PREP_depth]
    dec     eax
    test    byte [rbx + PREP_cond_taken + rax], 4
    jz      .else_live
    mov     r12d, 2                        ; a dead level: no warning either
.else_live:

    ; 1. If we are currently skipping at THIS depth ONLY, we toggle.
    ; If skip_depth == 1, it means the current level is the only one skipping.
    ; If skip_depth > 1, an outer level is skipping, so %else doesn't matter.
    ; If skip_depth == 0, the current level was taken, so now we skip.
    
    mov     rdi, rbx
    mov     esi, 1                 ; %else always "matches" if nothing did yet
    mov     byte [rel cond_is_else], 1
    call    prep_cond_branch
    mov     byte [rel cond_is_else], 0
    ; this level has had its %else: a %else or %elif after it is skipped
    movzx   eax, word [rbx + PREP_depth]
    dec     eax
    or      byte [rbx + PREP_cond_taken + rax], 2
    cmp     r12d, 1
    ja      .done
    lea     rsi, [rel s_dir_else]
    call    prep_trailing

.done:
    xor     rax, rax
    pop     r12
    pop     rbx
    epilogue

.error:
    mov     rax, EXIT_ERROR
    pop     r12
    pop     rbx
    epilogue

; ---- prep_trailing ----------------------
; What is left of a %else / %endif line: NASM's warning, and it goes
; (prep_trailing_quiet: no warning).
; Input: rbx = PrepState, rsi = the directive's name ("%else")
prep_trailing_quiet:
    xor     esi, esi
prep_trailing:
    push    r12
    push    r13
    mov     r12, rsi
    xor     r13d, r13d                     ; tokens dropped
    sub     rsp, TOKEN_SIZE
.peek:
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    test    rax, rax
    jnz     .done
    movzx   eax, byte [rsp + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .done
    cmp     eax, TOK_EOF
    je      .done
    ; a line after it (a %rep body cut short by %exitrep: the enclosing
    ; body's next line): not its
    mov     eax, [rsp + TOKEN_line]
    cmp     eax, [rel dir_line]
    jne     .done
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    inc     r13d
    jmp     .peek
.done:
    add     rsp, TOKEN_SIZE
    test    r13d, r13d
    jz      .ret
    test    r12, r12
    jz      .ret                           ; (quiet)
    mov     edi, WC_PP_TRAILING
    call    warn_begin
    lea     rsi, [rel s_trailing_after]
    call    warn_text
    mov     rsi, r12
    call    warn_text
    lea     rsi, [rel s_trailing_ignored]
    call    warn_text
    call    warn_end
.ret:
    pop     r13
    pop     r12
    ret

; ---- prep_finish ------------------------
;
; The source read: a %if still open is NASM's "expected `%endif' before
; end of file", at the line after the main file's last (it was let go).
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or EXIT_PP_NO_ENDIF (its place set)
;
global prep_finish
prep_finish:
    xor     eax, eax
    cmp     word [rdi + PREP_depth], 0
    je      .ret
    mov     rcx, [rdi + PREP_lexer]        ; the main file's, at its end
    mov     rdi, [rcx + LEXER_file]
    mov     esi, [rcx + LEXER_line]
    call    error_set_location
    mov     eax, EXIT_PP_NO_ENDIF
.ret:
    ret

; ---- prep_trailing_expr -----------------
; What is left of a line after its expression - %if, %ifn, %assign, %rep,
; and %elif quietly, as NASM: "trailing garbage after expression ignored",
; and it goes. (It went on to the assembler as a statement: "%if 1 x"
; defined a label x, "%rep 2 x" put an x in the body.) The tokens are the
; preprocessor's: the expression's reader has peeked the first.
; Input: rbx = PrepState, esi = 1 to warn, 0 not. Keeps rdx.
prep_trailing_expr:
    push    rdx
    push    r12
    push    r13
    mov     r12d, esi
    xor     r13d, r13d                     ; tokens dropped
.peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .done
    cmp     eax, TOK_EOF
    je      .done
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [rel dir_line]
    jne     .done                          ; (the next line's)
    mov     rdi, rbx
    call    preprocessor_next_token
    inc     r13d
    jmp     .peek
.done:
    test    r13d, r13d
    jz      .ret
    test    r12d, r12d
    jz      .ret
    mov     edi, WC_PP_TRAILING
    call    warn_begin
    lea     rsi, [rel s_trailing_expr]
    call    warn_text
    call    warn_end
.ret:
    pop     r13
    pop     r12
    pop     rdx
    ret

; ---- prep_handle_endif ------------------
prep_handle_endif:
    prologue
    push    rbx
    mov     rbx, rdi

    ; "%endif x": NASM's warning, unless the level is dead (an outer one
    ; skips it, or it had a second %else)
    cmp     word [rbx + PREP_skip_depth], 1
    ja      .no_trailing
    movzx   eax, word [rbx + PREP_depth]
    test    eax, eax
    jz      .endif_live
    dec     eax
    test    byte [rbx + PREP_cond_taken + rax], 4
    jnz     .no_trailing_drop
.endif_live:
    lea     rsi, [rel s_dir_endif]
    call    prep_trailing
    jmp     .no_trailing
.no_trailing_drop:
    call    prep_trailing_quiet
.no_trailing:

    ; 1. If we are skipping, decrement skip depth
    cmp     word [rbx + PREP_skip_depth], 0
    je      .not_skipping
    dec     word [rbx + PREP_skip_depth]

.not_skipping:
    ; 2. Decrement total depth (guard against underflow)
    cmp     word [rbx + PREP_depth], 0
    je      .done
    dec     word [rbx + PREP_depth]

.done:
    xor     rax, rax
    pop     rbx
    epilogue

.error_no_if:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue

; ---- prep_skip_macro_block & prep_skip_rep_block ----
global prep_skip_macro_block
prep_skip_macro_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %macro)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, rbx                   ; the expansion first, then the file
    mov     rsi, r13
    call    prep_raw_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "macro"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    mov     rdi, [r13 + TOKEN_value]
    call    prep_is_macro_open             ; %rmacro, %imacro, %irmacro
    jz      .nest_in
    
    ; Compare with "endmacro" (or "endm")
    mov     rdi, [r13 + TOKEN_value]
    call    prep_is_macro_end
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

global prep_skip_rep_block
prep_skip_rep_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %rep)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r13
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "rep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    
    ; Compare with "endrep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- macro_handle_def -------------------
;
; macro_handle_def
; Handles the %macro directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
; ---- prep_parse_count -------------------
;
; prep_parse_count
; The parameter count of %macro / %unmacro: "N", "N-M" or "N-*", then "+"
; (the last parameter takes the rest of the line) and ".nolist", as NASM
; reads them, with its errors.
; Input    : rbx = PrepState, rdi = the directive's name (for the messages)
; Output   : rax = OK or an error; rcx = the minimum, rdx = the maximum
;            (MACRO_VARIADIC for "*"); mdef_greedy = MACRO_FLAG_GREEDY for "+"
;
prep_parse_count:
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE
    mov     r12, rdi
    mov     byte [rel mdef_greedy], 0
    mov     byte [rel mdef_nolist], 0
    mov     byte [rel mdef_dot], 0
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    test    rax, rax
    jnz     .ret
    cmp     byte [rsp + TOKEN_kind], TOK_NUMBER
    je      .count_number
    ; "0.nolist": "0." lexes as a number with a point (NASM's packages
    ; write it so); the count, then ".nolist" with its point taken
    cmp     byte [rsp + TOKEN_kind], TOK_FLOAT
    jne     .no_count
    xor     r9d, r9d                       ; the minimum's
.dot_count:
    mov     rsi, [rsp + TOKEN_value]
    test    rsi, rsi
    jz      .no_count
    xor     ecx, ecx
.dot_digits:
    movzx   eax, byte [rsi + rcx]
    cmp     al, '.'
    je      .dot_found
    sub     al, '0'
    cmp     al, 9
    ja      .no_count
    inc     ecx
    jmp     .dot_digits
.dot_found:
    test    ecx, ecx
    jz      .no_count
    cmp     byte [rsi + rcx + 1], 0
    jne     .no_count
    xor     edx, edx                       ; the digits' value
    xor     r8d, r8d
.dot_value:
    cmp     r8d, ecx
    jae     .dot_valued
    movzx   eax, byte [rsi + r8]
    sub     eax, '0'
    imul    rdx, rdx, 10
    add     rdx, rax
    inc     r8d
    jmp     .dot_value
.dot_valued:
    mov     byte [rel mdef_dot], 1
    mov     r14, rdx
    test    r9d, r9d
    jnz     .range                         ; "0-1.nolist": the maximum's
    mov     r13, rdx
    jmp     .range
.count_number:
    mov     rdi, [rsp + TOKEN_value]
    call    str_to_int
    mov     r13, rdx                       ; the minimum
    mov     r14, rdx                       ; the maximum, unless "-M"
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    cmp     byte [rsp + TOKEN_kind], TOK_MINUS
    jne     .range
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next                  ; '-'
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    cmp     byte [rsp + TOKEN_kind], TOK_NUMBER
    jne     .max_dot
    mov     rdi, [rsp + TOKEN_value]
    call    str_to_int
    mov     r14, rdx
    jmp     .range
.max_dot:
    mov     r9d, 1
    cmp     byte [rsp + TOKEN_kind], TOK_FLOAT
    je      .dot_count
.max_star:
    cmp     byte [rsp + TOKEN_kind], TOK_STAR
    jne     .no_max
    mov     r14, MACRO_VARIADIC
.range:
    ; up to MACRO_PARAMS_MAX parameters (the counts are words)
    mov     eax, EXIT_MACRO_DEF
    cmp     r13, MACRO_PARAMS_MAX
    ja      .ret
    cmp     r14, MACRO_VARIADIC
    je      .tail
    cmp     r14, MACRO_PARAMS_MAX
    ja      .ret
    mov     eax, EXIT_MACRO_MINMAX
    cmp     r13, r14
    ja      .ret
.tail:
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    movzx   eax, byte [rsp + TOKEN_kind]
    cmp     eax, TOK_PLUS
    jne     .not_plus
    mov     byte [rel mdef_greedy], MACRO_FLAG_GREEDY
    jmp     .tail_eat
.not_plus:
    cmp     eax, TOK_IDENT
    jne     .counted
    mov     rdi, [rsp + TOKEN_value]
    lea     rsi, [rel str_nolist]
    call    str_cmp
    test    rax, rax
    jz      .nolist
    ; after "0.": "nolist" without its point
    cmp     byte [rel mdef_dot], 0
    je      .counted
    mov     byte [rel mdef_dot], 0
    mov     rdi, [rsp + TOKEN_value]
    lea     rsi, [rel str_nolist + 1]
    call    str_cmp
    test    rax, rax
    jnz     .counted
.nolist:
    mov     byte [rel mdef_nolist], MACRO_FLAG_NOLIST
.tail_eat:
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    jmp     .tail
.counted:
    xor     eax, eax
    mov     rcx, r13
    mov     rdx, r14
    jmp     .ret
.no_count:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_COUNT
    jmp     .ret
.no_max:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_MAX
.ret:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    pop     r12
    ret
