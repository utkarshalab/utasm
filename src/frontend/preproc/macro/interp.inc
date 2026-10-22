; ============================================================================
; File        : src/frontend/preproc/macro/interp.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : prep_resolve_interp: %[...], %+, context-local and parameter interpolation
; ============================================================================


; ---- prep_resolve_interp ----------------
;
; prep_resolve_interp
; Rewrites a token's text, replacing every "%[NAME]" with the decimal value
; of NAME. A name that is not defined contributes nothing, matching how the
; tables in src/include/arch/*.inc are built.
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (text is replaced in place)
; Output   : rax = EXIT_OK or error code
;
prep_resolve_interp:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token

    ; "foo%[foo%[n]]": a %[...] inside another is worked out first, the
    ; innermost one at a time (NASM's ppindirect), its text put in place
.nest:
    mov     r13, [r12 + TOKEN_value]
    test    r13, r13
    jz      .nest_done
    xor     ecx, ecx                       ; brackets open
    mov     r14, -1                        ; a "%[" inside another
    xor     edx, edx
.nest_scan:
    movzx   eax, byte [r13 + rdx]
    test    eax, eax
    jz      .nest_done
    cmp     eax, '%'
    jne     .nest_close
    cmp     byte [r13 + rdx + 1], '['
    jne     .nest_step
    test    ecx, ecx
    jz      .nest_open
    mov     r14, rdx
.nest_open:
    inc     ecx
    add     rdx, 2
    jmp     .nest_scan
.nest_close:
    cmp     eax, ']'
    jne     .nest_step
    test    ecx, ecx
    jz      .nest_step
    cmp     r14, -1
    jne     .nest_found
    dec     ecx
.nest_step:
    inc     rdx
    jmp     .nest_scan
.nest_found:
    ; r14 .. rdx: the innermost "%[x]"; its value, by a token of its own
    lea     r15, [rdx + 1]                 ; past its ']'
    sub     rsp, TOKEN_SIZE
    mov     rdi, rsp
    mov     rsi, r12
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r13 + r14]
    mov     rdx, r15
    sub     rdx, r14
    call    arena_alloc_string
    test    rax, rax
    jnz     .nest_fail
    mov     [rsp + TOKEN_value], rdx
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_resolve_interp
    test    rax, rax
    jnz     .nest_fail
    ; before it, its value, after it: the new text
    lea     rdi, [rel nest_buf]
    xor     ecx, ecx
.nest_pre:
    cmp     rcx, r14
    jae     .nest_mid
    mov     al, [r13 + rcx]
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .nest_pre
.nest_mid:
    mov     rsi, [rsp + TOKEN_value]
.nest_mid_ch:
    mov     al, [rsi]
    test    al, al
    jz      .nest_post
    cmp     rcx, NEST_BUF - 1
    jae     .nest_post
    mov     [rdi + rcx], al
    inc     rcx
    inc     rsi
    jmp     .nest_mid_ch
.nest_post:
    mov     al, [r13 + r15]
    test    al, al
    jz      .nest_built
    cmp     rcx, NEST_BUF - 1
    jae     .nest_built
    mov     [rdi + rcx], al
    inc     rcx
    inc     r15
    jmp     .nest_post
.nest_built:
    mov     rdx, rcx
    mov     rsi, rdi
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc_string
    test    rax, rax
    jnz     .nest_fail
    mov     [r12 + TOKEN_value], rdx
    add     rsp, TOKEN_SIZE
    jmp     .nest
.nest_fail:
    add     rsp, TOKEN_SIZE
    jmp     .done
.nest_done:

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEX_INTERP_BUF
    call    arena_alloc
    test    rax, rax
    jnz     .done
    mov     r14, rdx               ; r14 = output buffer (it grows: .ensure)
    mov     qword [rel interp_cap], LEX_INTERP_BUF
    xor     r15, r15               ; r15 = output length
    mov     r13, [r12 + TOKEN_value] ; r13 = source cursor

.scan:
    call    .ensure                ; room for what one step writes
    jc      .finish
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish

    cmp     al, '%'
    jne     .copy_char
    cmp     byte [r13 + 1], '$'
    je      .ctx_local
    ; a macro's parameter or local pasted into a name: isr_%1, %%x_%1
    cmp     byte [r13 + 1], '%'
    je      .mac_local
    cmp     byte [r13 + 1], '{'
    je      .param_brace
    movzx   eax, byte [r13 + 1]
    sub     eax, '0'
    cmp     eax, 9
    jbe     .param
    ; "%+1": the parameter as a condition code, "%-1" its inverse ("jnz"
    ; for z), as NASM
    movzx   eax, byte [r13 + 1]
    cmp     eax, '+'
    je      .param_cc
    cmp     eax, '-'
    jne     .not_cc
.param_cc:
    movzx   ecx, byte [r13 + 2]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .not_cc
    cmp     eax, '-'
    sete    byte [rel interp_ccneg]
    mov     [rel interp_ccstart], r15
    inc     r13                            ; at the sign: .param steps over it
    jmp     .param
.not_cc:
    cmp     byte [r13 + 1], '['
    jne     .copy_char

    ; "%[" : read the name up to ']'
    add     r13, 2
    mov     r9, r13
.name_loop:
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish
    cmp     al, ']'
    je      .name_done
    inc     r13
    jmp     .name_loop

.name_done:
    mov     r10, r13
    sub     r10, r9                ; name length
    inc     r13                    ; step over ']'

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r9
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .done
    mov     r9, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r9
    call    prep_symbol_find
    test    rax, rax
    jnz     .interp_text           ; undefined: contributes nothing

    ; a %define gives its text, an %assign / equ its value
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .interp_number
    mov     rax, [rdx + SYMBOL_value]
    push    r13
    push    r12
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
.interp_tok:
    test    r13d, r13d
    jz      .interp_tok_done
    mov     rdx, r12
    call    prep_idn_text
.interp_chr:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .interp_next_tok
    call    .ensure
    jc      .interp_next_tok
    mov     [r14 + r15], cl
    inc     r15
    inc     rax
    jmp     .interp_chr
.interp_next_tok:
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .interp_tok
.interp_tok_done:
    pop     r12
    pop     r13
    jmp     .scan
.interp_number:
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan

.interp_text:
    ; "%[i+1]": no one name - each name in it replaced by its %define's
    ; text or its value, the rest kept ("3+1"), as NASM expands it; one
    ; name not defined gives nothing
    mov     rsi, r9
.it_any:
    movzx   edi, byte [rsi]
    test    edi, edi
    jz      .scan
    push    rsi
    call    str_is_ident_char
    pop     rsi
    inc     rsi
    test    rax, rax
    jnz     .it_any
    push    r13
    mov     r13, r9
.it_loop:
    call    .ensure
    jc      .it_done
    movzx   edi, byte [r13]
    test    edi, edi
    jz      .it_done
    call    str_is_ident_char
    test    rax, rax
    jnz     .it_name
    mov     [r14 + r15], dil
    inc     r15
    inc     r13
    jmp     .it_loop
.it_name:
    mov     rsi, r13
.it_end:
    inc     rsi
    movzx   edi, byte [rsi]
    test    edi, edi
    jz      .it_have
    push    rsi
    call    str_is_ident_char
    pop     rsi
    test    rax, rax
    jnz     .it_end
.it_have:
    push    rsi                            ; the name's end
    mov     rdx, rsi
    sub     rdx, r13
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r13
    call    arena_alloc_string
    test    rax, rax
    jnz     .it_copy
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    call    prep_symbol_find
    test    rax, rax
    jnz     .it_copy
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    je      .it_value
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .it_copy
    mov     rax, [rdx + SYMBOL_value]
    test    rax, rax
    jz      .it_copy
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .it_copy
    ; a %define: its tokens' text
    push    r12
    push    r13
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
.it_tok:
    test    r13d, r13d
    jz      .it_tok_done
    mov     rdx, r12
    call    prep_idn_text
.it_chr:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .it_next_tok
    call    .ensure
    jc      .it_next_tok
    mov     [r14 + r15], cl
    inc     r15
    inc     rax
    jmp     .it_chr
.it_next_tok:
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .it_tok
.it_tok_done:
    pop     r13
    pop     r12
    pop     r13                            ; on past the name
    jmp     .it_loop
.it_value:
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    pop     r13
    jmp     .it_loop
.it_copy:
    ; not a macro: the name as written
    pop     rsi
.it_copy_ch:
    cmp     r13, rsi
    jae     .it_loop
    push    rsi
    call    .ensure
    pop     rsi
    jc      .it_done
    mov     al, [r13]
    mov     [r14 + r15], al
    inc     r15
    inc     r13
    jmp     .it_copy_ch
.it_done:
    pop     r13
    jmp     .scan

.ctx_local:
    ; "%$name" is local to the innermost %push context: rewrite it as
    ; "..@N.name", N the context's number, as NASM names it (which makes
    ; each IF/ENDIF pair unique). "%$$name" is the context around it, one
    ; more '$' one more level out.
    add     r13, 2
    mov     eax, [rbx + PREP_ctx_depth]
.ctx_outer:
    cmp     byte [r13], '$'
    jne     .ctx_level
    inc     r13
    dec     eax
    jmp     .ctx_outer
.ctx_level:
    test    eax, eax
    jle     .ctx_id_zero
    dec     eax
    mov     eax, [rbx + PREP_ctx_ids + rax * 4]
    jmp     .ctx_id_ready
.ctx_id_zero:
    xor     eax, eax
.ctx_id_ready:
    push    r15                            ; where "..@N.name" starts
    mov     byte [r14 + r15], '.'
    mov     byte [r14 + r15 + 1], '.'
    mov     byte [r14 + r15 + 2], '@'
    add     r15, 3
    mov     rsi, rax
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    mov     byte [r14 + r15], '.'
    inc     r15
    ; the name itself, here, so a %define of it can stand for it
.ctx_name:
    call    .ensure
    jc      .ctx_named
    movzx   edi, byte [r13]
    test    edi, edi
    jz      .ctx_named
    push    rdi
    call    str_is_ident_char
    pop     rdi
    cmp     rax, TRUE
    jne     .ctx_named
    mov     [r14 + r15], dil
    inc     r15
    inc     r13
    jmp     .ctx_name
.ctx_named:
    cmp     byte [rel interp_brace_ctx], 0
    je      .ctx_unbraced
    mov     byte [rel interp_brace_ctx], 0
    cmp     byte [r13], '}'
    jne     .ctx_unbraced
    inc     r13
.ctx_unbraced:
    ; "x_%$name" with "%define %$name abc": x_abc, as NASM pastes ("%$x%$n"
    ; with "%assign %$n 3": ..@N.x3) - but a directive's name that is only
    ; "%$n" stays the name ("%assign %$n %$n+1")
    ; A token that is only "%$n" stays the name: its %define is expanded
    ; as one is, its tokens as they are (a string stays a string)
    cmp     qword [rsp], 0
    jne     .ctx_lookup                    ; pasted onto what comes before
    cmp     byte [r13], 0
    je      .ctx_kept                      ; the whole token
.ctx_lookup:
    mov     byte [r14 + r15], 0
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rsp]
    add     rsi, r14
    call    prep_symbol_find
    test    rax, rax
    jnz     .ctx_kept
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .ctx_define
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .ctx_kept
    pop     r15                            ; the name goes: the value instead
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan
.ctx_define:
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .ctx_kept
    mov     rax, [rdx + SYMBOL_value]
    test    rax, rax
    jz      .ctx_kept
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .ctx_kept
    test    byte [rax + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .ctx_kept
    pop     r15                            ; the name goes: its text instead
    push    r13
    push    r12
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
    jmp     .interp_tok
.ctx_kept:
    add     rsp, 8
    jmp     .scan

.copy_char:
    mov     [r14 + r15], al
    inc     r15
    inc     r13
    jmp     .scan

.param_brace:
    ; "%{$name}": as %$name (its %define's text, if it has one)
    cmp     byte [r13 + 2], '$'
    jne     .param_brace_n
    mov     byte [rel interp_brace_ctx], 1
    inc     r13                            ; (.ctx_local steps over "{$")
    jmp     .ctx_local
.param_brace_n:
    ; "%{N}": as %N
    test    r15, r15
    setz    byte [rel interp_lead]
    add     r13, 2
    xor     eax, eax
.brace_digit:
    movzx   ecx, byte [r13]
    test    ecx, ecx
    jz      .param_n
    inc     r13
    cmp     ecx, '}'
    je      .param_n
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .brace_digit
    imul    eax, eax, 10
    add     eax, ecx
    jmp     .brace_digit
.param:
    ; "%N": the text of argument N of the macro being expanded (%0: how
    ; many there are)
    test    r15, r15
    setz    byte [rel interp_lead]         ; it starts the token
    inc     r13
    xor     eax, eax
.param_digit:
    movzx   ecx, byte [r13]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .param_n
    imul    eax, eax, 10
    add     eax, ecx
    inc     r13
    jmp     .param_digit
.param_n:
    ; the expansion with the parameters (a %rep body has none)
    mov     rdx, [rbx + PREP_ctx]
    mov     rdx, [rdx + ASMCTX_mac_exp]
.param_owner:
    test    rdx, rdx
    jz      .scan
    cmp     word [rdx + MACROEXP_nparams], 0
    jne     .param_found
    mov     rdx, [rdx + MACROEXP_parent]
    jmp     .param_owner
.param_found:
    movzx   ecx, word [rdx + MACROEXP_nparams]
    test    eax, eax
    jnz     .param_arg
    mov     rsi, rcx                       ; %0
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan
.param_arg:
    cmp     eax, ecx
    ja      .param_none                    ; not given: nothing
    dec     eax
    mov     rcx, [rdx + MACROEXP_arglens]
    mov     ecx, [rcx + rax * 4]
    mov     rdx, [rdx + MACROEXP_params]
    mov     rdx, [rdx + rax * 8]           ; its first token
    push    r13
    push    r12
    mov     r12, rdx
    mov     r13d, ecx
    ; their texts; a name that is a %define / %assign gives its own, as
    ; NASM expands the arguments of a macro call
.arg_tok:
    test    r13d, r13d
    jz      .arg_done
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .arg_raw
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .arg_raw
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    je      .arg_assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .arg_raw
    mov     rax, [rdx + SYMBOL_value]
    cmp     word [rax + MACRO_max_params], 0
    jne     .arg_raw                       ; a function-like one: as written
    push    r12
    push    r13
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
.def_tok:
    test    r13d, r13d
    jz      .def_done
    mov     rdx, r12
    call    prep_idn_text
    call    .append
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .def_tok
.def_done:
    pop     r13
    pop     r12
    jmp     .arg_next
.arg_assign:
    ; an %assign: its value in decimal
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .arg_raw
    push    rdx                            ; (.ensure takes it)
    call    .ensure
    pop     rdx
    jc      .arg_next
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .arg_next
.arg_raw:
    mov     rdx, r12
    call    prep_idn_text
    call    .append
.arg_next:
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .arg_tok
.arg_done:
    pop     r12
    pop     r13
    ; "%{1}v" with %1 a number: NASM pastes no number with a name after
    ; it - the name is expanded on its own, its text after the number
    ; ("%define v 9": 19); "x%{1}v" stays x1v
    cmp     byte [rel interp_lead], 0
    je      .lead_done
    mov     byte [rel interp_lead], 0
    test    r15, r15
    jz      .lead_done
    movzx   eax, byte [r14]
    sub     eax, '0'
    cmp     eax, 9
    ja      .lead_done
    push    r15                            ; where the name starts
.lead_name:
    call    .ensure
    jc      .lead_named
    movzx   edi, byte [r13]
    test    edi, edi
    jz      .lead_named
    push    rdi
    call    str_is_ident_char
    pop     rdi
    cmp     rax, TRUE
    jne     .lead_named
    mov     [r14 + r15], dil
    inc     r15
    inc     r13
    jmp     .lead_name
.lead_named:
    mov     rsi, [rsp]
    cmp     rsi, r15
    je      .lead_kept                     ; no name after it
    mov     byte [r14 + r15], 0
    add     rsi, r14
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    test    rax, rax
    jnz     .lead_kept
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .lead_define
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .lead_kept
    pop     r15
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .lead_done
.lead_define:
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .lead_kept
    mov     rax, [rdx + SYMBOL_value]
    test    rax, rax
    jz      .lead_kept
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .lead_kept
    test    byte [rax + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .lead_kept
    pop     r15
    push    r13
    push    r12
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
    jmp     .interp_tok
.lead_kept:
    add     rsp, 8
.lead_done:
    ; "%-1": the condition code just written, the other way
    cmp     byte [rel interp_ccneg], 0
    je      .scan
    mov     byte [rel interp_ccneg], 0
    mov     byte [r14 + r15], 0
    mov     rdi, [rel interp_ccstart]
    add     rdi, r14
    call    prep_cc_inverse
    test    rax, rax
    jz      .scan                          ; not a condition code: as it is
    mov     r15, [rel interp_ccstart]
    call    .append
    jmp     .scan
.param_none:
    mov     byte [rel interp_ccneg], 0
    jmp     .scan

; .append: the text at rax onto the output (r14 + r15)
.append:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .append_end
    call    .ensure
    jc      .append_end
    mov     [r14 + r15], cl
    inc     r15
    inc     rax
    jmp     .append
.append_end:
    ret

; .ensure: room for 40 more bytes at r14 + r15 (a number, "..@N." or
; "..@N", and the NUL), the buffer twice the size when there is not. CF
; set when there is no memory. Preserves rax, rcx; clobbers rdx, rsi, rdi,
; r8-r11.
.ensure:
    lea     rdx, [r15 + 40]
    cmp     rdx, [rel interp_cap]
    jbe     .ens_ok
    push    rax
    push    rcx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel interp_cap]
    shl     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .ens_fail
    mov     rdi, rdx
    mov     rsi, r14
    mov     rcx, r15
    rep movsb
    mov     r14, rdx
    shl     qword [rel interp_cap], 1
    pop     rcx
    pop     rax
.ens_ok:
    clc
    ret
.ens_fail:
    pop     rcx
    pop     rax
    stc
    ret

.mac_local:
    ; "%%name": "..@" and the expansion's number, then the name
    add     r13, 2
    mov     rdx, [rbx + PREP_ctx]
    mov     rdx, [rdx + ASMCTX_mac_exp]
    test    rdx, rdx
    jz      .scan
    mov     byte [r14 + r15], '.'
    mov     byte [r14 + r15 + 1], '.'
    mov     byte [r14 + r15 + 2], '@'
    add     r15, 3
    mov     esi, [rdx + MACROEXP_exp_id]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    mov     byte [r14 + r15], '.'          ; ..@N.name, as NASM
    inc     r15
    jmp     .scan

.finish:
    mov     byte [r14 + r15], 0
    mov     [r12 + TOKEN_value], r14
    mov     word [r12 + TOKEN_len], r15w
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_INTERP
    ; "0x%1", "%1h": a number once pasted
    movzx   eax, byte [r14]
    sub     eax, '0'
    cmp     eax, 9
    ja      .finish_kind
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .finish_kind
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
.finish_kind:
    xor     rax, rax

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
