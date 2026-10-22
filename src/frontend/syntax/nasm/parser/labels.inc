; ============================================================================
; File        : src/frontend/syntax/nasm/parser/labels.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : numeric labels (1:, 1b, 1f), positional labels, GNU symbol names, .size
; ============================================================================


;*
; * [parser_numlabel_def]
; * Input : RDI = number text of an "N:" label, RBX = PrepState
; * Output: RAX = OK and RSI = the instance's label name, or an error
; ;
parser_numlabel_def:
    call    parser_numlabel_n
    cmp     eax, -1
    je      .bad
    cmp     byte [rdi], 0
    jne     .bad                           ; "1f:" is not a numeric label
    lea     rcx, [rel numlbl_count]
    mov     esi, [rcx + rax*4]
    inc     dword [rcx + rax*4]
    mov     edi, eax
    call    parser_numlabel_name
    mov     rax, OK
    ret
.bad:
    mov     rax, EXIT_INVALID_EXPR
    ret

;*
; * [parser_numlabel_ref]
; * Input : RDI = number token text, RBX = PrepState
; * Output: RSI = the label name "Nf" / "Nb" refers to, or 0 for a number
; ;
parser_numlabel_ref:
    call    parser_numlabel_n
    cmp     eax, -1
    je      .none
    movzx   ecx, byte [rdi]
    cmp     byte [rdi + 1], 0
    jne     .none
    lea     rdx, [rel numlbl_count]
    mov     esi, [rdx + rax*4]             ; definitions so far
    cmp     ecx, 'f'
    je      .name
    cmp     ecx, 'b'
    jne     .none
    test    esi, esi
    jz      .none                          ; no "N:" yet: 1b is binary one
    dec     esi
.name:
    mov     edi, eax
    jmp     parser_numlabel_name
.none:
    xor     esi, esi
    ret

; eax = the decimal number at rdi (rdi left after its digits), or -1 when
; the text does not start with a digit or the number is NUMLBL_MAX or more
parser_numlabel_n:
    xor     eax, eax
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .no
.digit:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .end
    imul    eax, eax, 10
    add     eax, ecx
    cmp     eax, NUMLBL_MAX
    jae     .no
    inc     rdi
    jmp     .digit
.end:
    ret
.no:
    mov     eax, -1
    ret

; rsi = "L@num.<edi>.<esi>", allocated in the preprocessor arena
parser_numlabel_name:
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 40
    call    arena_alloc
    mov     r14, rdx
    mov     rdi, r14
    lea     rsi, [rel numlbl_prefix]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     esi, r12d
    extern  str_int_to_str
    call    str_int_to_str
    mov     rdi, r14
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rdi, r14
    lea     rsi, [rel numlbl_dot]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     esi, r13d
    call    str_int_to_str
    mov     rdi, r14
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rsi, r14
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_pos_label]
; * Purpose: "$" and "$$" as labels. Each use becomes a hidden label
; *          ("L@here.N", which no source can spell) at the current
; *          position, or at offset 0 of the current section for "$$", so
; *          branches, data relocations and label differences treat them
; *          like any other label: "jmp $", "loop $", "dq $", "$-start".
; * Input  : EDI = 0 for "$", 1 for "$$"; RBX = PrepState
; * Output : RAX = OK and RDX = the SYMBOL*, or an error
; ;
global parser_pos_label
parser_pos_label:
    push    r12
    push    r13
    mov     r12d, edi
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, r13
    lea     rsi, [rel pos_prefix]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     rsi, [rel pos_count]
    inc     qword [rel pos_count]
    call    str_int_to_str
    mov     rdi, r13
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rsi, r13
    call    parser_define_label
    test    rax, rax
    jnz     .ret
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .ret
    test    r12d, r12d
    jz      .ret
    mov     qword [rdx + SYMBOL_value], 0  ; "$$": the start of the section
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_gas_symbol]
; * Purpose: GNU's syntax (gas_names): a symbol as GNU as writes one.
; *   "name" quoted (GCC 16's -masm=intel quotes every name: "main":,
; *   call "puts"@PLT, "cmp"[rip]) is the name; name@PLT (@GOTPCREL, @GOT,
; *   @GOTOFF, @GOTPC, @TPOFF, @NTPOFF, @GOTTPOFF, @INDNTPOFF, @TLSGD,
; *   @TLSLD, @DTPOFF), or "name"@PLT, is the name, the relocation the one
; *   "wrt ..plt" asks for (reloc_wrt). The token is made an identifier
; *   of the name. A single-quoted one stays a character.
; * Input  : RBX = PrepState, R12 = the token
; * Output : AL = its kind now. Preserves rbx, r12-r15.
; ;
global parser_gas_symbol
parser_gas_symbol:
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     byte [rel gas_names], 0
    je      .gs_ret
    cmp     eax, TOK_STRING
    jne     .gs_ident
    cmp     byte [r12 + TOKEN_quote], '"'
    jne     .gs_ret
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    mov     rdi, [r12 + TOKEN_value]
    call    str_len
    mov     [r12 + TOKEN_len], ax
    ; "name"@SUFFIX
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .gs_named
    cmp     byte [rdx + TOKEN_kind], TOK_AT
    jne     .gs_named
    mov     rdi, rbx
    call    preprocessor_next_token        ; "@"
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .gs_named
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .gs_named
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, [rdx + TOKEN_value]
    call    .gs_suffix
    test    eax, eax
    jz      .gs_named
    mov     [rel reloc_wrt], al
    jmp     .gs_named
.gs_ident:
    cmp     eax, TOK_IDENT
    jne     .gs_ret
    ; name@SUFFIX, the "@" not first
    mov     rsi, [r12 + TOKEN_value]
    mov     ecx, 1
    cmp     byte [rsi], 0
    je      .gs_named
.gs_scan:
    movzx   eax, byte [rsi + rcx]
    test    eax, eax
    jz      .gs_named
    cmp     eax, '@'
    je      .gs_at
    inc     ecx
    jmp     .gs_scan
.gs_at:
    push    rcx
    push    rsi
    lea     rsi, [rsi + rcx + 1]
    call    .gs_suffix
    pop     rsi
    pop     rcx
    test    eax, eax
    jz      .gs_named                      ; (not one: a name with @ in it)
    mov     [rel reloc_wrt], al
    ; the name before it
    push    rcx
    push    rsi
    lea     rsi, [rcx + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rsi
    pop     rcx
    test    rax, rax
    jnz     .gs_named
    mov     [r12 + TOKEN_value], rdx
    mov     [r12 + TOKEN_len], cx
    mov     rdi, rdx
    rep     movsb
    mov     byte [rdi], 0
.gs_named:
    mov     eax, TOK_IDENT
.gs_ret:
    ret
; .gs_suffix: rsi = a relocation's name after "@" -> eax = its WRT_* (0:
; none of them)
.gs_suffix:
    push    r12
    mov     r12, rsi
    lea     r8, [rel gas_wrt_words]
.gs_word:
    movzx   eax, byte [r8]
    test    eax, eax
    jz      .gs_none
    push    r8
    mov     rdi, r12
    lea     rsi, [r8 + 1]
    call    str_cmp_kw
    pop     r8
    test    rax, rax
    jz      .gs_hit
    lea     r8, [r8 + 1]
.gs_skip:
    inc     r8
    cmp     byte [r8 - 1], 0
    jne     .gs_skip
    jmp     .gs_word
.gs_hit:
    movzx   eax, byte [r8]
    pop     r12
    ret
.gs_none:
    xor     eax, eax
    pop     r12
    ret

;*
; * [parser_size_late]
; * Purpose: GNU's ".size NAME, EXPR" (src/frontend/syntax/gas/gas.s): EXPR kept
; *   and worked out once jumps are made short (parser_sizes, after
; *   relax_run). ".-f" taken when it is read froze the code it spans -
; *   GCC writes one after every function, so no jump in any was made
; *   short. "." in it is where the directive is: a hidden label
; *   (parser_pos_label), which moves with the code.
; * Input  : RBX = PrepState, RSI = NAME (the expression is read next)
; * Output : RAX = OK or an error
; ;
global parser_size_late
parser_size_late:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi                       ; NAME
    ; "." here: a hidden label "L@here.eN" - an end, which relaxation keeps
    ; before padding that grows from none there (the next function's
    ; alignment: GCC writes .size after .cfi_endproc)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, r13
    lea     rsi, [rel pos_end_prefix]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     rsi, [rel pos_count]
    inc     qword [rel pos_count]
    call    str_int_to_str
    mov     rdi, r13
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rsi, r13
    call    parser_define_label
    test    rax, rax
    jnz     .ret
    call    prep_rec_begin
    test    rax, rax
    jnz     .ret
.tok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .drop
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .read
    cmp     eax, TOK_EOF
    je      .read
    cmp     eax, TOK_COMMENT
    je      .read
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .drop
    jmp     .tok
.read:
    call    prep_rec_end                   ; rdx = tokens, rcx = how many
    test    rax, rax
    jnz     .too_long
    test    rcx, rcx
    jz      .empty
    movzx   r14d, byte [rel expr_in_data]
    mov     byte [rel expr_in_data], 1     ; (a record not handed on)
    mov     rdi, rbx
    mov     rsi, rdx
    mov     rdx, rcx
    call    parser_defer_record
    mov     [rel expr_in_data], r14b
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; the record
    ; "." is the hidden label
    mov     rdi, r13
    call    str_len
    mov     r15, rax
    mov     rsi, [r14 + 16]                ; its tokens
    mov     ecx, [r14 + 24]                ; (with its newline)
.dot:
    test    ecx, ecx
    jz      .keep
    cmp     byte [rsi + TOKEN_kind], TOK_IDENT
    jne     .dot_next
    mov     rax, [rsi + TOKEN_value]
    cmp     word [rax], '.'
    jne     .dot_next
    mov     [rsi + TOKEN_value], r13
    mov     [rsi + TOKEN_len], r15w
.dot_next:
    add     rsi, TOKEN_SIZE
    dec     ecx
    jmp     .dot
.keep:
    mov     rax, [rel size_list]
    test    rax, rax
    jnz     .have
    mov     rsi, SIZE_LATE_CAP * 16
    extern  mem_reserve
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    mov     [rel size_list], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel size_n]
    cmp     rcx, SIZE_LATE_CAP
    jae     .full
    shl     rcx, 4
    mov     [rax + rcx], r12
    mov     [rax + rcx + 8], r14
    inc     qword [rel size_n]
.full:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
.drop:
    push    rax
    extern  prep_rec_drop
    call    prep_rec_drop
    pop     rax
    jmp     .ret
.too_long:
    call    prep_rec_drop
    mov     eax, EXIT_EXPR_TOO_DEEP
    jmp     .ret
.empty:
    call    prep_rec_drop
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret

;*
; * [parser_sizes]
; * Purpose: The sizes parser_size_late kept, from the code as it is once
; *   jumps are made short (src/link/linker.s, after relax_run).
; * Output : RAX = OK or an error
; ;
global parser_sizes
parser_sizes:
    push    r12
    push    r13
    xor     r12d, r12d
.s_next:
    cmp     r12, [rel size_n]
    jae     .s_done
    mov     r13, r12
    shl     r13, 4
    add     r13, [rel size_list]
    inc     r12
    mov     rdi, [r13 + 8]
    call    parser_deferred_value
    test    rax, rax
    jnz     .s_ret
    push    rdx
    lea     rdi, [rel global_ctx]
    mov     rsi, [r13]
    call    symbol_find
    pop     rcx
    test    rax, rax
    jnz     .s_next                        ; (no such name: no size)
    mov     [rdx + SYMBOL_size], rcx
    jmp     .s_next
.s_done:
    ; GNU's aliases (".set f.localalias, f"): their labels' types and sizes
    extern  gas_alias_finish
    call    gas_alias_finish
    ; GNU's syntax and a GOT or TLS relocation: _GLOBAL_OFFSET_TABLE_, as
    ; GNU as has it (undefined, global)
    extern  gas_got_wanted
    cmp     byte [rel gas_got_wanted], 0
    je      .s_ok
    lea     rdi, [rel global_ctx]
    lea     rsi, [rel s_got_name]
    call    symbol_find
    test    rax, rax
    jz      .s_ok
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_EXTERN
    mov     byte [rsp + SYMBOL_vis], VIS_GLOBAL
    mov     byte [rsp + SYMBOL_pflags], SYMF_USED
    lea     rax, [rel s_got_name]
    mov     [rsp + SYMBOL_name], rax
    lea     rdi, [rel global_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
.s_ok:
    xor     eax, eax
.s_ret:
    pop     r13
    pop     r12
    ret
