; ============================================================================
; File        : src/frontend/preproc/macro/macro_def.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %macro definitions: recording bodies, capture slots, token buffers
; ============================================================================


; prep_is_macro_end: ZF set when rdi names %endmacro or its short form %endm
prep_is_macro_end:
    push    rdi
    lea     rsi, [rel dir_endm]
    call    str_cmp
    pop     rdi
    test    rax, rax
    jz      .ret
    lea     rsi, [rel dir_endm_short]
    call    str_cmp
    test    rax, rax
.ret:
    ret

macro_handle_def:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState

    ; Allocate: 3 Tokens = 96 bytes (Multiple of 16)
    sub     rsp, 96
    
    ; 1. Lex the macro name
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     r12, [rsp]             ; r12 = name token
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .error_expected_ident

    ; %imacro: stored under the name's case-insensitive key
    cmp     byte [rel mdef_icase], 0
    je      .name_ready
    mov     byte [rel mdef_icase], 0
    mov     rsi, [r12 + TOKEN_value]
    call    prep_icase_key
    test    rax, rax
    jnz     .error
    mov     [r12 + TOKEN_value], rdx
.name_ready:

    ; 2. The parameter count: N, N-M, N-*, then "+" and ".nolist"
    mov     rdi, [rel mdef_dir]
    call    prep_parse_count
    test    rax, rax
    jnz     .done
    mov     r14, rcx               ; min_params
    mov     r15, rdx               ; max_params
    mov     qword [rel mdef_defaults], 0
    mov     dword [rel mdef_ndefaults], 0
    mov     rdi, rbx
    lea     rsi, [rsp + 64]
    call    prep_raw_peek
.defaults:
    movzx   eax, byte [rsp + 64 + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .body_start
    cmp     eax, TOK_EOF
    je      .body_start
    ; read into the capture area, copied out at .body_start
    call    prep_cap_base
    test    rax, rax
    jnz     .error
    mov     [rel mdef_defaults], rdx
.default_tok:
    mov     rdi, rbx
    lea     rsi, [rsp + 64]
    call    prep_raw_peek
    movzx   eax, byte [rsp + 64 + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .body_start
    cmp     eax, TOK_EOF
    je      .body_start
    mov     rdi, [rel mdef_defaults]
    mov     esi, [rel mdef_ndefaults]
    call    prep_cap_slot
    test    rax, rax
    jnz     .error
    mov     rsi, rdx
    mov     rdi, rbx
    call    prep_raw_next
    test    rax, rax
    jnz     .error
    inc     dword [rel mdef_ndefaults]
    jmp     .default_tok

.body_start:
    ; the defaults at their size, out of the capture area
    mov     rsi, [rel mdef_defaults]
    test    rsi, rsi
    jz      .defaults_taken
    mov     rdi, rbx
    mov     edx, [rel mdef_ndefaults]
    call    prep_cap_take
    test    rax, rax
    jnz     .error
    mov     [rel mdef_defaults], rdx
.defaults_taken:
    ; more defaults than optional parameters (they are counted by their
    ; commas): NASM's warning - not with "+", whose last takes the rest
    cmp     r15, MACRO_VARIADIC
    je      .defaults_fit
    cmp     byte [rel mdef_greedy], 0
    jne     .defaults_fit
    mov     ecx, [rel mdef_ndefaults]
    test    ecx, ecx
    jz      .defaults_fit
    mov     rsi, [rel mdef_defaults]
    mov     eax, 1
.default_comma:
    cmp     byte [rsi + TOKEN_kind], TOK_COMMA
    jne     .default_next
    inc     eax
.default_next:
    add     rsi, TOKEN_SIZE
    dec     ecx
    jnz     .default_comma
    mov     rdx, r15
    sub     rdx, r14
    cmp     rax, rdx
    jbe     .defaults_fit
    mov     edi, WC_PP_MACRO_DEFAULTS
    extern  warn_begin, warn_text, warn_end
    call    warn_begin
    lea     rsi, [rel s_macro_defaults]
    call    warn_text
    mov     rsi, [r12 + TOKEN_value]
    call    warn_text
    lea     rsi, [rel s_quote_end]
    call    warn_text
    call    warn_end
.defaults_fit:

    ; 3. Allocate MACRO struct in arena
    ; We need to save r14 (min) and r15 (max) while we use r15 for the struct pointer
    ; Let's use the stack or other registers.
    ; [rsp + 64] = min_params (8 bytes)
    ; [rsp + 72] = max_params (8 bytes)
    mov     [rsp + 64], r14
    mov     [rsp + 72], r15

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r15, rdx               ; r15 = pointer to MACRO struct

    mov     byte [r15 + MACRO_tag], TAG_MACRO
    mov     rax, [r12 + TOKEN_value]
    mov     [r15 + MACRO_name], rax
    
    mov     rax, [rsp + 64]
    mov     [r15 + MACRO_min_params], ax
    mov     rax, [rsp + 72]
    mov     [r15 + MACRO_max_params], ax
    movzx   eax, byte [rel mdef_greedy]
    or      al, [rel mdef_nolist]          ; .nolist (src/diag/codes.s: unlisted)
    or      [r15 + MACRO_flags], al
    ; %rmacro / %irmacro: the one kind that may call itself
    mov     rdi, [rel mdef_dir]
    lea     rsi, [rel dir_rmacro]
    call    str_cmp_kw
    test    rax, rax
    jz      .recursive
    mov     rdi, [rel mdef_dir]
    lea     rsi, [rel dir_irmacro]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_recursive
.recursive:
    or      byte [r15 + MACRO_flags], MACRO_FLAG_RECURSIVE
.not_recursive:
    mov     rax, [rel mdef_defaults]
    mov     [r15 + MACRO_defaults], rax
    mov     eax, [rel mdef_ndefaults]
    mov     [r15 + MACRO_ndefaults], eax

    ; a multi-line macro of this name and parameter range already: it is
    ; replaced at %endmacro, with NASM's warning here, at its %macro line
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r15 + MACRO_name]
    call    prep_symbol_find
    test    rax, rax
    jnz     .not_redef
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_redef
    mov     rax, [rdx + SYMBOL_value]
    test    rax, rax
    jz      .not_redef
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .not_redef
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     cx, [r15 + MACRO_min_params]
    jne     .not_redef
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     cx, [r15 + MACRO_max_params]
    jne     .not_redef
    mov     edi, WC_PP_MACRO_REDEF_MULTI
    call    warn_begin
    test    eax, eax
    jz      .not_redef
    lea     rsi, [rel s_macro_redef]
    call    warn_text
    mov     rsi, [r15 + MACRO_name]
    call    warn_text
    lea     rsi, [rel s_quote_end]
    call    warn_text
    call    warn_end
.not_redef:

    ; 4. Capture tokens until %endmacro: one contiguous array, read into
    ; the capture area (lexer_next allocates token value strings from the
    ; arena, so slots taken there one at a time would interleave with them)
    ; and copied out at its size at %endmacro
    call    prep_cap_base
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx      ; the capture's base, until then
    xor     r14, r14               ; r14 = token count
    mov     r13, 1                 ; r13 = nesting depth

.capture_loop:
    mov     rdi, [r15 + MACRO_tokens]
    mov     rsi, r14
    call    prep_cap_slot
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = current token slot

    mov     rdi, rbx                   ; the expansion first, then the file
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .error_eof

    ; defined by a macro (or a %rep body): the definition's lines are
    ; listed with the expansion, as NASM lists them
    cmp     byte [rel lst_enabled], 0
    je      .def_unlisted
    mov     rax, [rbx + PREP_ctx]
    mov     rsi, [rax + ASMCTX_mac_exp]
    test    rsi, rsi
    jz      .def_unlisted
    mov     rdi, r12
    call    error_track_token
.def_unlisted:

    ; Check for % directive
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .store_token

    ; It's a TOK_DIRECTIVE. Check for "macro" or "endmacro"
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    mov     rdi, [r12 + TOKEN_value]
    call    prep_is_macro_open             ; %rmacro, %imacro, %irmacro
    jz      .nest_in

    mov     rdi, [r12 + TOKEN_value]
    call    prep_is_macro_end              ; %endmacro or %endm
    jz      .nest_out

    jmp     .store_token

.nest_in:
    inc     r13                    ; found nested %macro
    inc     r14
    jmp     .capture_loop

.nest_out:
    dec     r13
    test    r13, r13
    jz      .found_endmacro        ; Outermost %endmacro found!
    
    inc     r14
    jmp     .capture_loop

.store_token:
    inc     r14
    jmp     .capture_loop

.found_endmacro:
    mov     [r15 + MACRO_ntokens], r14d
    mov     rdi, rbx
    mov     rsi, [r15 + MACRO_tokens]
    mov     rdx, r14
    call    prep_cap_take                  ; the body at its size
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx

    ; An earlier multi-line macro of this name: a new parameter range makes
    ; an overload (a call picks by its argument count); the same range
    ; replaces it. A %define of the name is replaced.
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r15 + MACRO_name]
    call    prep_symbol_find
    test    rax, rax
    jnz     .register
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .register
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .replace
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     cx, [r15 + MACRO_min_params]
    jne     .overload
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     cx, [r15 + MACRO_max_params]
    jne     .overload
    mov     rcx, [rax + MACRO_next]
    mov     [r15 + MACRO_next], rcx
    jmp     .replace
.overload:
    mov     [r15 + MACRO_next], rax
.replace:
    mov     [rdx + SYMBOL_value], r15
    xor     eax, eax
    jmp     .done
.register:

    ; 5. Register in symbol table
    ; Use stack for temp symbol
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    
    ; zero out (all of it: 48 bytes left the rest as stack garbage)
    mov     rcx, SYMBOL_SIZE / 8
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_MACRO
    mov     rax, [r15 + MACRO_name]
    mov     [rdi + SYMBOL_name], rax
    mov     [rdi + SYMBOL_value], r15

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    prep_symbol_add
    test    rax, rax
    jnz     .error_add_sym
    
    add     rsp, SYMBOL_SIZE
    xor     rax, rax
    jmp     .done

.error_add_sym:
    add     rsp, SYMBOL_SIZE
.error:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_macro_def:
    mov     rax, EXIT_MACRO_DEF
    jmp     .done

.error_expected_ident:
    mov     rdi, [rel mdef_dir]            ; "`%macro' expects a macro name"
    call    error_set_subject
    mov     rax, EXIT_MACRO_NO_NAME
    jmp     .done

.error_eof:
    ; at the end of the file, as NASM reports it
    mov     eax, [r12 + TOKEN_line]
    test    eax, eax
    jz      .eof_line
    cmp     word [r12 + TOKEN_col], 1
    jbe     .eof_at_line
    inc     eax                            ; (no newline at the end: the next)
.eof_at_line:
    extern  error_loc_line
    mov     [rel error_loc_line], eax
.eof_line:
    mov     rdi, [r15 + MACRO_name]        ; "end of file while still
    call    error_set_subject              ;  defining macro `s'"
    mov     rax, EXIT_MACRO_EOF
    jmp     .done

.done:
    add     rsp, 96                ; token buffers
    pop     rcx                    ; Alignment
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

;*
; * [prep_cap_base]
; * Purpose: Where a token capture starts: the top of the capture area, a
; *   region reserved once and committed as it is used. %macro / %rep / times
; *   bodies and macro arguments are read there, then copied out at their
; *   exact size (prep_cap_take), which hands the space back: a body held in
; *   a block reserved for the largest one cost every %rep pass 8KB and every
; *   %macro 32KB. A capture made while another is under way (an argument
; *   that calls a function-like %define) starts above it and is done first.
; * Output : RAX = OK or an error, RDX = the base
; * Clobbers: RCX, RSI, RDI, R8-R11
; ;
global prep_cap_base
extern  mem_reserve
prep_cap_base:
    mov     rdx, [rel cap_top]
    test    rdx, rdx
    jnz     .ok
    mov     rsi, CAP_SIZE
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    mov     [rel cap_top], rdx
    lea     rax, [rdx + CAP_SIZE]
    mov     [rel cap_end], rax
.ok:
    xor     eax, eax
.ret:
    ret

;*
; * [prep_cap_slot]
; * Purpose: The slot for token N of a capture, the area's top moved past
; *   it (a capture started while that token is read goes above).
; * Input  : RDI = the capture's base, RSI = N
; * Output : RAX = OK or EXIT_OOM (the area is full), RDX = the slot
; * Clobbers: nothing else
; ;
global prep_cap_slot
prep_cap_slot:
    imul    rdx, rsi, TOKEN_SIZE
    add     rdx, rdi
    lea     rax, [rdx + TOKEN_SIZE]
    cmp     rax, [rel cap_end]
    ja      .full
    mov     [rel cap_top], rax
    xor     eax, eax
    ret
.full:
    mov     eax, EXIT_OOM
    ret

;*
; * [prep_cap_take]
; * Purpose: The N tokens captured at BASE as an arena array of their own,
; *   with one slot more (times adds its newline there); the area's top goes
; *   back to BASE.
; * Input  : RDI = PrepState, RSI = base, RDX = N
; * Output : RAX = OK or an error, RDX = the array
; * Clobbers: RCX, RSI, RDI, R8-R11
; ;
global prep_cap_take
prep_cap_take:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    mov     [rel cap_top], rsi
    lea     rsi, [rdx + 1]
    imul    rsi, rsi, TOKEN_SIZE
    mov     rdi, [rdi + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, r12
    imul    rcx, r13, TOKEN_SIZE / 8
    rep movsq
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [prep_rec_begin]
; * Purpose: Start recording the tokens preprocessor_next_token hands out,
; *   into the capture area: parser_evaluate_expression keeps an expression
; *   it cannot work out yet, to work it out at the end. Tokens read for a
; *   macro call's arguments are not recorded (the expansion's are).
; * Output : RAX = OK or an error
; * Clobbers: RCX, RDX, RSI, RDI, R8-R11
; ;
global prep_rec_begin
prep_rec_begin:
    call    prep_cap_base
    test    rax, rax
    jnz     .ret
    mov     [rel rec_base], rdx
    mov     qword [rel rec_n], 0
    mov     byte [rel rec_on], 1
    mov     byte [rel rec_overflow], 0
.ret:
    ret

;*
; * [prep_rec_end]
; * Purpose: Stop recording. The tokens stay in the capture area until
; *   prep_cap_take copies them out or prep_rec_drop lets them go.
; * Output : RDX = the tokens, RCX = how many, RAX = 1 when the capture
; *          area filled (some are missing), else 0
; ;
global prep_rec_end
prep_rec_end:
    mov     byte [rel rec_on], 0
    mov     rdx, [rel rec_base]
    mov     rcx, [rel rec_n]
    movzx   eax, byte [rel rec_overflow]
    ret

; prep_rec_drop: the recorded tokens let go (the capture area's top back to
; where they began). Preserves every register.
global prep_rec_drop
prep_rec_drop:
    push    rax
    mov     rax, [rel rec_base]
    mov     [rel cap_top], rax
    pop     rax
    ret

; prep_rec_note: rdx = a token handed out; recorded when a recording is on
; and no macro call is reading its arguments. Preserves every register.
prep_rec_note:
    cmp     byte [rel rec_on], 0
    je      .ret
    cmp     dword [rel rec_suspend], 0
    jne     .ret
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    mov     rdi, [rel rec_base]
    mov     rsi, [rel rec_n]
    call    prep_cap_slot
    test    rax, rax
    jnz     .full
    mov     rdi, rdx
    mov     rsi, [rsp + 16]                ; the token
    copy_token
    inc     qword [rel rec_n]
    jmp     .done
.full:
    mov     byte [rel rec_on], 0           ; too long to keep
    mov     byte [rel rec_overflow], 1
.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

; prep_rec_unnote: rsi = a token handed back (putback): when it is the last
; one recorded, it is not part of the expression any more (it is handed out
; again). Preserves every register.
prep_rec_unnote:
    cmp     byte [rel rec_on], 0
    je      .ret
    cmp     dword [rel rec_suspend], 0
    jne     .ret
    push    rax
    push    rcx
    push    rdx
    mov     rax, [rel rec_n]
    test    rax, rax
    jz      .done
    dec     rax
    imul    rcx, rax, TOKEN_SIZE
    add     rcx, [rel rec_base]
    mov     dl, [rcx + TOKEN_kind]
    cmp     dl, [rsi + TOKEN_kind]
    jne     .done
    mov     rdx, [rcx + TOKEN_value]
    cmp     rdx, [rsi + TOKEN_value]
    jne     .done
    mov     [rel rec_n], rax
    mov     [rel cap_top], rcx
.done:
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

;*
; * [prep_rec_rename]
; * Purpose: The last COUNT tokens recorded become one name: "$" / "$$" the
; *   label they stand for, ".x" its full name, "1f" the label it means - so
; *   a kept expression means the same at the end.
; * Input  : RDI = COUNT, RSI = the name
; * Preserves every register.
; ;
global prep_rec_rename
prep_rec_rename:
    cmp     byte [rel rec_on], 0
    je      .ret
    cmp     dword [rel rec_suspend], 0
    jne     .ret
    push    rax
    push    rcx
    mov     rax, [rel rec_n]
    cmp     rax, rdi
    jb      .done                          ; (not all of them recorded)
    sub     rax, rdi
    imul    rcx, rax, TOKEN_SIZE
    add     rcx, [rel rec_base]            ; the first of them stays, renamed
    mov     byte [rcx + TOKEN_kind], TOK_IDENT
    mov     [rcx + TOKEN_value], rsi
    mov     byte [rcx + TOKEN_flags], 0
    inc     rax
    mov     [rel rec_n], rax
    add     rcx, TOKEN_SIZE
    mov     [rel cap_top], rcx
.done:
    pop     rcx
    pop     rax
.ret:
    ret

;*
; * [prep_tokens_text]
; * Purpose: The text of N tokens, a blank between each two (a kept
; *   expression's, for messages).
; * Input  : RDI = PrepState, RSI = tokens, RDX = N
; * Output : RAX = OK or an error, RDX = the text
; ;
global prep_tokens_text
prep_tokens_text:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    xor     r14d, r14d                     ; the length
    xor     r15d, r15d
.len:
    cmp     r15, r13
    jae     .alloc
    imul    rdx, r15, TOKEN_SIZE
    add     rdx, r12
    call    prep_idn_text
    mov     rdi, rax
    call    str_len
    lea     r14, [r14 + rax + 1]
    inc     r15
    jmp     .len
.alloc:
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r14 + 1]
    call    arena_alloc                    ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     r14, rdx                       ; where the next text goes
    xor     r15d, r15d
.put:
    cmp     r15, r13
    jae     .put_done
    test    r15, r15
    jz      .no_blank
    mov     byte [r14], ' '
    inc     r14
.no_blank:
    imul    rdx, r15, TOKEN_SIZE
    add     rdx, r12
    call    prep_idn_text
.copy:
    mov     cl, [rax]
    test    cl, cl
    jz      .copied
    mov     [r14], cl
    inc     r14
    inc     rax
    jmp     .copy
.copied:
    inc     r15
    jmp     .put
.put_done:
    pop     rdx
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [prep_tokbuf_grow]
; * Purpose: A token array twice the size, the tokens so far copied over.
; *   Bodies are single arrays reserved in one block (the lexer allocates
; *   token strings from the same arena, so an array cannot be extended in
; *   place); a full one is replaced by this.
; * Input  : RDI = arena, RSI = the array, RDX = tokens in it, RCX = its
; *          capacity in tokens
; * Output : RAX = OK or an error, RDX = the new array, RCX = its capacity
; * Clobbers: RDI, RSI, R8-R11
; ;
global prep_tokbuf_grow
prep_tokbuf_grow:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    lea     rbx, [rcx * 2]
    imul    rsi, rbx, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, r12
    imul    rcx, r13, TOKEN_SIZE / 8
    rep movsq
    mov     rcx, rbx
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
