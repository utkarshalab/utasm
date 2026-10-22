; ============================================================================
; File        : src/frontend/preproc/macro/files.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %depend, %pathsearch, %line, %use, %clear, %strtok
; ============================================================================

[SECTION .text]

; ---- prep_quoted_text ---------------------
; The text of a quoted token: "file", `file`, or 'file' (eight characters
; or fewer lex as a character constant, its characters packed).
; Input : rdx = token, rbx = PrepState. Output: rax = the text, or 0 when
; the token is not quoted.
prep_quoted_text:
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .not_string
    mov     rax, [rdx + TOKEN_value]
    ret
.not_string:
    cmp     byte [rdx + TOKEN_kind], TOK_CHAR
    je      prep_token_text
    xor     eax, eax
    ret

; ---- %depend / %pathsearch ---------------
;
; "%depend 'file'": the file is a dependency (-M) without being read.
; "%pathsearch NAME 'file'": NAME is the file's path as %include would find
; it (in the -I directories), or the name as written when it is nowhere.
;
prep_handle_depend:
    push    rbx
    mov     rbx, rdi
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_quoted_text
    test    rax, rax
    jz      .bad
    mov     rdi, rax
    extern  deps_add
    call    deps_add
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     rbx
    ret

prep_handle_pathsearch:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; NAME
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_quoted_text
    test    rax, rax
    jz      .bad
    mov     r13, rax                       ; the file
    mov     rdi, r13
    extern  incpath_find
    call    incpath_find                   ; rax = its path, or 0
    test    rax, rax
    jz      .as_written
    mov     r13, rax
.as_written:
    ; NAME is defined as that string, as %defstr would
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    prep_define_string
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- %line ------------------------------
;
; "%line N [file]": the lines after this one are numbered from there, in
; that file (for __LINE__, __FILE__ and messages), exactly as NASM does.
;
prep_handle_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    ; "%line N[+M] [file]": N, then the step M (1 when left out) - read
    ; apart, not as the sum the expression N+M would be
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .bad
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    test    rax, rax
    jnz     .ret
    mov     r12, rdx                       ; N
    mov     r14d, 1                        ; M
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_PLUS
    jne     .stepped
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .bad
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
.stepped:
    extern  lexer_line_step
    mov     [rel lexer_line_step], r14d
    xor     r13d, r13d
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .file
    cmp     eax, TOK_STRING
    jne     .set
.file:
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r13, [rdx + TOKEN_value]
    mov     rdi, rbx
    call    preprocessor_peek_token        ; the newline, read with this line's number
.set:
    ; this line is N, as NASM numbers it: the next one N + M - already,
    ; when the lexer has read past this line's end
    mov     rax, [rbx + PREP_lexer]
    mov     ecx, r12d
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .store
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .store
    add     ecx, r14d
.store:
    mov     [rax + LEXER_line], ecx
    extern  lst_line_lexer
    mov     [rel lst_line_lexer], rax      ; (listing.s: the lines' own text)
    test    r13, r13
    jz      .ok
    mov     [rax + LEXER_file], r13
.ok:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret

; ---- %use -------------------------------
;
; "%use altreg" names the first eight registers r0-r7 (r0d, r0w, r0b /
; r0l, r0h-r3h), case-insensitively, as NASM's package does; smartalign,
; fp, ifunc and masm are NASM's too (their texts above).
;
prep_handle_use:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_token_text
    test    rax, rax
    jz      .done
    ; %use fp: NASM's float macros (float32(x), Inf, NaN ...), read as
    ; definitions ahead of the next line
    push    rax
    mov     rdi, rax
    lea     rsi, [rel use_fp]
    call    prep_str_cmp_ci
    test    rax, rax
    pop     rax
    jnz     .not_fp
    mov     rdi, rbx
    lea     rsi, [rel use_fp_text]
    mov     edx, use_fp_text_len
    lea     rcx, [rel use_fp]
    call    prep_push_buffer
    jmp     .ret
.not_fp:
    ; %use ifunc: ilog2() & co
    push    rax
    mov     rdi, rax
    lea     rsi, [rel use_ifunc]
    call    prep_str_cmp_ci
    test    rax, rax
    pop     rax
    jnz     .not_ifunc
    mov     rdi, rbx
    lea     rsi, [rel use_ifunc_text]
    mov     edx, use_ifunc_text_len
    lea     rcx, [rel use_ifunc]
    call    prep_push_buffer
    jmp     .ret
.not_ifunc:
    ; %use masm: MASM's forms (once; "flat:" and a bare "ptr x" known to
    ; the parser from here on: masm_enabled)
    push    rax
    mov     rdi, rax
    lea     rsi, [rel use_masm]
    call    prep_str_cmp_ci
    test    rax, rax
    pop     rax
    jnz     .not_masm
    extern  masm_enabled, masm_hl
    cmp     byte [rel masm_enabled], 0
    jne     .done
    mov     byte [rel masm_enabled], 1
    ; PROC / ENDP / LOCAL / INVOKE / .IF & co (src/frontend/syntax/masm/masm.s)
    mov     byte [rel masm_hl], 1
    mov     rdi, rbx
    lea     rsi, [rel use_masm_text]
    mov     edx, use_masm_text_len
    lea     rcx, [rel use_masm]
    call    prep_push_buffer
    jmp     .ret
.not_masm:
    ; %use smartalign: align pads code with long NOPs (src/optimize/align.s),
    ; "alignmode generic" to start with
    push    rax
    mov     rdi, rax
    lea     rsi, [rel use_smartalign]
    call    prep_str_cmp_ci
    test    rax, rax
    pop     rax
    jnz     .not_smartalign
    extern  smartalign_mode, smartalign_jmp
    mov     byte [rel smartalign_mode], 2  ; SA_GENERIC
    mov     dword [rel smartalign_jmp], 8
    mov     rdi, rbx
    lea     rsi, [rel use_smartalign_text]
    mov     edx, use_smartalign_text_len
    lea     rcx, [rel use_smartalign]
    call    prep_push_buffer
    jmp     .ret
.not_smartalign:
    push    rax
    mov     rdi, rax
    lea     rsi, [rel use_altreg]
    call    prep_str_cmp_ci
    test    rax, rax
    pop     rdi
    jz      .altreg
    ; anything else is not a package utasm has
    call    error_set_subject
    mov     eax, EXIT_USE_PACKAGE
    jmp     .ret
.altreg:
    lea     r13, [rel altreg_table]
.reg:
    mov     rsi, [r13]
    test    rsi, rsi
    jz      .done
    call    prep_icase_key
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     byte [rel def_scratch + TOKEN_kind], TOK_IDENT
    mov     rax, [r13 + 8]
    mov     [rel def_scratch + TOKEN_value], rax
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    test    rax, rax
    jnz     .ret
    add     r13, 16
    jmp     .reg
.done:
    mov     rdi, rbx
    call    prep_drain_line
    xor     eax, eax
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_unshadow ---------------------
;
; prep_unshadow
; After the source is read: an equ constant a %define took the name of is
; the constant again, for the relocations that refer to it.
; Input    : rdi = AsmCtx
;
global prep_unshadow
prep_unshadow:
    mov     rdx, [rdi + ASMCTX_symtab]
    mov     ecx, [rdi + ASMCTX_symcount]
.sym:
    test    ecx, ecx
    jz      .done
    test    byte [rdx + SYMBOL_pflags], SYMF_SHADOW
    jz      .next
    and     byte [rdx + SYMBOL_pflags], ~SYMF_SHADOW
    mov     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    mov     rax, [rdx + SYMBOL_size]
    mov     [rdx + SYMBOL_value], rax
.next:
    add     rdx, SYMBOL_SIZE
    dec     ecx
    jmp     .sym
.done:
    ret

; ---- %clear -----------------------------
;
; Forgets every macro, single- and multi-line (the predefined ones too).
;
prep_handle_clear:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drain_line
    mov     rax, [rbx + PREP_ctx]
    mov     r8, [rax + ASMCTX_symtab]
    mov     r9d, [rax + ASMCTX_symcount]
    xor     ecx, ecx
    lea     rdx, [rel undef_name]
.sym:
    cmp     ecx, r9d
    jae     .done
    imul    r10, rcx, SYMBOL_SIZE
    cmp     byte [r8 + r10 + SYMBOL_kind], SYM_MACRO
    jne     .next
    mov     [r8 + r10 + SYMBOL_name], rdx
.next:
    inc     ecx
    jmp     .sym
.done:
    mov     dword [rel idefine_count], 0
    xor     eax, eax
    pop     rbx
    ret

; ---- prep_scratch_string ----------------
;
; def_scratch = the one token of a string of RCX bytes at RSI: up to eight
; bytes a character constant, usable in an expression as NASM's quoted
; strings are ("%substr c 'abc' 2" then "%assign h h ^ c"); longer, a string.
;
prep_scratch_string:
    push    rsi
    push    rcx
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    pop     rcx
    pop     rsi
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     [rel def_scratch + TOKEN_len], cx
    ; the quote it would be written with (%defstr): one the text does not
    ; hold - ' then " then `
    xor     edx, edx                       ; bit 0: a ', bit 1: a "
    xor     eax, eax
.quote_scan:
    cmp     rax, rcx
    jae     .quote_pick
    cmp     byte [rsi + rax], 0x27
    jne     .quote_dq
    or      edx, 1
.quote_dq:
    cmp     byte [rsi + rax], '"'
    jne     .quote_next
    or      edx, 2
.quote_next:
    inc     rax
    jmp     .quote_scan
.quote_pick:
    mov     al, 0x27
    test    edx, 1
    jz      .quote_set
    mov     al, '"'
    test    edx, 2
    jz      .quote_set
    mov     al, 0x60
.quote_set:
    mov     [rel def_scratch + TOKEN_quote], al
    cmp     rcx, 8
    ja      .string
    xor     eax, eax                       ; packed, first byte lowest
    mov     rdx, rcx
.pack:
    test    rdx, rdx
    jz      .packed
    dec     rdx
    shl     rax, 8
    mov     al, [rsi + rdx]
    jmp     .pack
.packed:
    mov     byte [rel def_scratch + TOKEN_kind], TOK_CHAR
    mov     [rel def_scratch + TOKEN_value], rax
    ret
.string:
    mov     byte [rel def_scratch + TOKEN_kind], TOK_STRING
    mov     [rel def_scratch + TOKEN_value], rsi
    or      byte [rel def_scratch + TOKEN_flags], TOK_FLAG_COUNTED
    ret

; ---- %strcat / %deftok ------------------
;
; "%strcat NAME 'ab', "cd"" defines NAME as the string "abcd";
; "%deftok NAME 'text'" defines NAME as the token the text spells (an
; identifier or a number).
; Input    : rdi = PrepState, esi = 0 strcat / 1 deftok
;
prep_handle_strtok:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r14d, esi
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; name
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 1024
    call    arena_alloc                    ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; the text
.part:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .built
    cmp     eax, TOK_EOF
    je      .built
    cmp     eax, TOK_COMMA
    je      .part
    cmp     eax, TOK_STRING
    je      .str_part
    cmp     eax, TOK_CHAR
    jne     .bad
.str_part:
    call    prep_token_text
    test    rax, rax
    jz      .bad
    mov     rdi, r13
    mov     rsi, rax
    call    str_concat                     ; the parts, one after the other
    jmp     .part
.built:
    ; one token: a string (%strcat) or what the text spells (%deftok)
    test    r14d, r14d
    jnz     .deftok_token
    mov     rdi, r13
    call    str_len
    mov     rsi, r13
    mov     rcx, rax
    call    prep_scratch_string
    jmp     .store
.deftok_token:
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     byte [rel def_scratch + TOKEN_kind], TOK_STRING
    mov     [rel def_scratch + TOKEN_value], r13
    mov     rdi, r13
    call    str_len
    mov     [rel def_scratch + TOKEN_len], ax
    test    r14d, r14d
    jz      .store
    mov     byte [rel def_scratch + TOKEN_kind], TOK_IDENT
    movzx   eax, byte [r13]
    sub     eax, '0'
    cmp     eax, 9
    ja      .store
    mov     byte [rel def_scratch + TOKEN_kind], TOK_NUMBER  ; kept as text
.store:
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    jmp     .ret
.bad:
    mov     rax, EXIT_DEFINE
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
