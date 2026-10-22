; ============================================================================
; File        : src/frontend/syntax/nasm/parser/data.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : db / dw / dd / dq: item lists, dup, sizes, symbols, field widths, the zeroing warnings
; ============================================================================


[SECTION .text]

parser_emit_data_8:
    prologue
    push    r13
    push    r14
.loop:
    call    parser_item_begin
    mov     esi, 1
    call    parser_data_ext
    check_err
    test    edx, edx
    jnz     .next_item
    mov     esi, 1
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next_item
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_CHAR
        ; a quoted literal on its own is a string: db 'abc' is 3 bytes
        mov     rdi, rbx
        call    preprocessor_peek_token
        movzx   eax, byte [rdx + TOKEN_kind]
        cmp     eax, TOK_COMMA
        je      .char_bytes
        cmp     eax, TOK_RPAREN
        je      .char_bytes                ; the last of a list: %('a')
        cmp     eax, TOK_NEWLINE
        je      .char_bytes
        cmp     eax, TOK_EOF
        je      .char_bytes
        mov     al, TOK_CHAR               ; part of an expression ('a'+1)
        jmp     .not_char
.char_bytes:
        movzx   r13d, word [r12 + TOKEN_len]
        mov     r14, [r12 + TOKEN_value]
.char_byte:
        test    r13d, r13d
        jz      .next_item
        mov     rdi, [rbx + PREP_ctx]
        movzx   esi, r14b
        call    asmctx_emit_byte
        shr     r14, 8
        dec     r13d
        jmp     .char_byte
        ENDIF
.not_char:
    IF al, e, TOK_STRING
        mov     rsi, [r12 + TOKEN_value]
        mov     rdi, [rbx + PREP_ctx]
        extern  asmctx_emit_string
        call    asmctx_emit_string
        ELSE
        mov     rdi, rbx
        mov     rsi, r12
        call    preprocessor_unread_token  ; 'a'+1: the '+' is peeked
        mov     byte [rel float_fmt], FLT_BYTE ; "db 1.5": NASM's 8-bit float
        mov     byte [rel expr_pcrel_ok], 1
        mov     rdi, rbx
        call    parser_evaluate_expression
        mov     byte [rel expr_pcrel_ok], 0
        mov     byte [rel float_fmt], 0
        check_err
        mov     esi, 1
        call    parser_data_dup
        check_err
        test    r8d, r8d
        jnz     .next_item
        ; a label in it is relocated, as dw / dd do it: "db later - $$",
        ; "db end - start" with labels not defined yet were written as 0
        mov     r10, rdx
        mov     r8, r11
        mov     r9, rcx
        call    parser_data_symbol
        test    rsi, rsi
        jz      .plain8
        mov     rdx, rsi               ; name
        mov     rcx, rdi               ; addend
        mov     rdi, [rbx + PREP_ctx]
        mov     rax, [rdi + ASMCTX_curr_sec]
        mov     rsi, [rax + SECTION_size]
        mov     r8, R_X86_64_8
        cmp     byte [rel expr_pcrel], 0
        je      .abs8
        mov     r8, R_X86_64_PC8       ; "db x - $": PC-relative
        add     rcx, rsi
.abs8:
        extern  reloc_record
        call    reloc_record
        check_err
        xor     r10d, r10d
.plain8:
        mov     rdi, r10                   ; "db 256": NASM's warning
        mov     esi, 1
        push    r10
        call    warn_data_bounds
        pop     r10
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, r10
        extern  asmctx_emit_byte
        call    asmctx_emit_byte
        ENDIF

.next_item:
    call    parser_item_end
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        call    parser_data_more           ; ("db 1," ends there, as in NASM)
        test    eax, eax
        jnz     .loop
        ENDIF
    pop     r14
    pop     r13
    epilogue

.error:
    pop     r14
    pop     r13
    epilogue

parser_emit_data_16:
    prologue
.loop:
    call    parser_item_begin
    mov     esi, 2
    call    parser_data_ext
    check_err
    test    edx, edx
    jnz     .next
    mov     esi, 2
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_HALF
    mov     byte [rel expr_pcrel_ok], 1
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_pcrel_ok], 0
    mov     byte [rel float_fmt], 0
    check_err
    mov     esi, 2
    call    parser_data_dup
    check_err
    test    r8d, r8d
    jnz     .next
    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain16
    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_16
    cmp     byte [rel expr_pcrel], 0
    je      .abs16
    mov     r8, R_X86_64_PC16      ; "dw x - $": PC-relative
    add     rcx, rsi
.abs16:
    call    reloc_record
    check_err
    xor     esi, esi
    jmp     .emit16
.plain16:
    mov     rdi, r10                       ; "dw 65536": NASM's warning
    mov     esi, 2
    push    r10
    call    warn_data_bounds
    pop     r10
    mov     rsi, r10
.emit16:
    mov     rdi, [rbx + PREP_ctx]
    extern  asmctx_emit_word
    call    asmctx_emit_word
.next:
    call    parser_item_end
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        call    parser_data_more           ; ("db 1," ends there, as in NASM)
        test    eax, eax
        jnz     .loop
        ENDIF
    epilogue

.error:
    epilogue

;*
; * [parser_data_ext]
; * Purpose: NASM 2.15's data items besides a value (its MASM-like ones):
; *   "%(a, b)" (a list), and a size word
; *   before a list, a "?" or a value ("byte ('PQR')", "word ?", "dword 5"),
; *   which are of that size. "N dup (...)" is parser_data_dup's, once the
; *   count is read.
; * Input  : RBX = PrepState, ESI = the unit in bytes
; * Output : RAX = OK or an error, EDX = 1 when an item was taken
; ;
parser_data_ext:
    push    rsi                            ; [rsp] = the unit
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_PERCENT               ; (a plain "?" is the expression's)
    je      .percent
    cmp     eax, TOK_IDENT
    jne     .not
    mov     rdi, [rdx + TOKEN_value]
    call    parser_data_size_word
    test    eax, eax
    jz      .not
    mov     [rsp], rax                     ; that size, for what follows
    mov     rdi, rbx
    call    preprocessor_next_token        ; the size word
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_QUESTION
    je      .uninit
    cmp     eax, TOK_PERCENT
    je      .percent
    cmp     eax, TOK_LPAREN
    je      .list
    ; "dword 5": one value of that size
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     rsi, rdx
    mov     ecx, [rsp]
    call    parser_data_bytes
    jmp     .took
.uninit:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the "?"
    test    rax, rax
    jnz     .ret
    xor     esi, esi
    mov     ecx, [rsp]
    call    parser_data_bytes
    mov     byte [rel expr_question], 1    ; listed and warned as "?" is
    jmp     .took
.percent:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the "%" of "%(...)"
    test    rax, rax
    jnz     .ret
.list:
    mov     esi, [rsp]
    call    parser_data_list
    test    rax, rax
    jnz     .ret
.took:
    xor     eax, eax
    mov     edx, 1
    jmp     .ret
.not:
    xor     eax, eax
    xor     edx, edx
.ret:
    pop     rsi
    ret

;*
; * [parser_data_list]
; * Purpose: "(a, b, ...)": the items, of ESI bytes each, up to the ")"
; * Input  : RBX = PrepState, ESI = the unit
; * Output : RAX = OK or an error
; ;
parser_data_list:
    push    rsi
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .bad
    ; that size's own reader takes the items, up to the token after the
    ; last one (no comma)
    mov     esi, [rsp]
    call    parser_emit_data_size
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    je      .ret
.bad:
    mov     eax, EXIT_INVALID_EXPR
.ret:
    pop     rsi
    ret

;*
; * [parser_data_dup]
; * Purpose: "N dup [size] [%](...)" after a data item's value N: the list
; *   written N times (once, its bytes then copied).
; * Input  : RBX = PrepState, RDX = N (the value just read), ESI = the unit
; * Output : RAX = OK or an error, R8D = 1 when it was a dup (else RDX,
; *          RCX and R11 are as they were)
; ;
parser_data_dup:
    push    rdx
    push    rcx
    push    r11
    push    rdx                            ; [rsp+8] = N
    push    rsi                            ; [rsp] = the unit
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .not
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_dup]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not
    cmp     qword [rsp + 8], 0
    jl      .bad                           ; a negative count
    mov     rdi, rbx
    call    preprocessor_next_token        ; "dup"
    test    rax, rax
    jnz     .ret
    ; a size word, and "%", may come before the list
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .no_size
    mov     rdi, [rdx + TOKEN_value]
    call    parser_data_size_word
    test    eax, eax
    jz      .no_size
    mov     [rsp], rax
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
.no_size:
    cmp     byte [rdx + TOKEN_kind], TOK_PERCENT
    jne     .list
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
.list:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    push    qword [rax + SECTION_size]     ; [rsp] = where it starts
    mov     esi, [rsp + 8]
    call    parser_data_list
    pop     rcx
    test    rax, rax
    jnz     .ret
    ; the copies after the first: its bytes again (the section's buffer
    ; may move as it grows, so each is read from where it is now)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     r9, [rax + SECTION_size]
    sub     r9, rcx                        ; r9 = the list's bytes
    mov     r10, [rsp + 8]                 ; N
    test    r10, r10
    jnz     .copies
    mov     [rax + SECTION_size], rcx      ; "0 dup (...)": nothing
    jmp     .done
.copies:
    dec     r10
    imul    r10, r9                        ; the bytes still to write
    xor     r8d, r8d                       ; how many of them so far
.copy:
    cmp     r8, r10
    jae     .done
    mov     rax, r8
    xor     edx, edx
    div     r9                             ; rdx = the byte of the list
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     rax, [rax + SECTION_data]
    add     rax, rcx
    movzx   esi, byte [rax + rdx]
    push    rcx
    push    r8
    push    r9
    push    r10
    mov     rdi, [rbx + PREP_ctx]
    call    asmctx_emit_byte
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    test    rax, rax
    jnz     .ret
    inc     r8
    jmp     .copy
.done:
    xor     eax, eax
    mov     r8d, 1
    add     rsp, 16
    pop     r11
    pop     rcx
    add     rsp, 8                         ; (rdx: not kept)
    ret
.bad:
    mov     eax, EXIT_INVALID_EXPR
    jmp     .ret
.not:
    xor     eax, eax
.ret:
    xor     r8d, r8d
    add     rsp, 16
    pop     r11
    pop     rcx
    pop     rdx
    ret

;*
; * [parser_emit_data_size]
; * Purpose: the data items of ESI bytes each (db .. dz's own readers)
; ;
parser_emit_data_size:
    mov     rdi, rbx
    cmp     esi, 1
    je      parser_emit_data_8
    cmp     esi, 2
    je      parser_emit_data_16
    cmp     esi, 4
    je      parser_emit_data_32
    cmp     esi, 8
    je      parser_emit_data_64
    jmp     parser_emit_data_wide

;*
; * [parser_data_bytes]
; * Purpose: ECX bytes of the value RSI, little-endian (zeros past 8)
; ;
parser_data_bytes:
    test    ecx, ecx
    jz      .ret
    push    rsi
    push    rcx
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, sil
    call    asmctx_emit_byte
    pop     rcx
    pop     rsi
    test    rax, rax
    jnz     .ret
    shr     rsi, 8
    dec     ecx
    jmp     parser_data_bytes
.ret:
    ret

;*
; * [parser_data_size_word]
; * Purpose: the bytes of a size word (byte 1 ... zword 64), or 0
; * Input  : RDI = the word
; ;
parser_data_size_word:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel data_size_words]
.next:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .found
    add     r13, 8
    jmp     .next
.found:
    movzx   eax, byte [r13 + 7]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
str_dup:    db "dup", 0
; 7-byte name, its size in bytes
data_size_words:
    db "byte", 0, 0, 0, 1
    db "word", 0, 0, 0, 2
    db "dword", 0, 0, 4
    db "qword", 0, 0, 8
    db "tword", 0, 0, 10
    db "oword", 0, 0, 16
    db "yword", 0, 0, 32
    db "zword", 0, 0, 64
    db 0
[SECTION .text]

;*
; * [parser_data_symbol]
; * Purpose: Decide whether an initialised data word refers to an address the
; *   linker has to fill in, and with what name and addend. "dq label" must
; *   be relocated: emitting the section-relative value in place leaves a
; *   table of offsets rather than pointers, which faults on first use.
; *   Constants and struct fields are plain numbers and never relocate.
; * Input:
; *   R8  = resolved SYMBOL* (0 if none)
; *   R9  = deferred name string (0 if none, for a forward reference)
; *   R10 = the evaluated value
; * Output:
; *   RSI = name to relocate against, or 0 for a plain number
; *   RDI = addend to record
; ;
parser_data_symbol:
    xor     rsi, rsi
    mov     rdi, r10
    test    r8, r8
    jz      .try_deferred

    ; A resolved symbol carries an address when it is a label, data, an
    ; extern - or a name only declared so far ("global foo" before "foo:":
    ; it was written as a number, 0, with no relocation)
    push    rdi
    mov     rdi, r8
    call    expr_sym_class
    pop     rdi
    test    eax, eax
    jnz     .use_symbol
    ret                            ; constant / struct / macro: a number

.use_symbol:
    mov     rsi, [r8 + SYMBOL_name]
    mov     rdi, r10
    sub     rdi, [r8 + SYMBOL_value]   ; addend = whatever was added to it
    ret

.try_deferred:
    test    r9, r9
    jz      .done
    mov     rsi, r9                ; forward reference: the value is the addend
    mov     rdi, r10
.done:
    ret

parser_emit_data_32:
    prologue
.loop:
    call    parser_item_begin
    mov     esi, 4
    call    parser_data_ext
    check_err
    test    edx, edx
    jnz     .next
    mov     esi, 4
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_SINGLE
    mov     byte [rel expr_pcrel_ok], 1
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_pcrel_ok], 0
    mov     byte [rel float_fmt], 0
    check_err
    mov     esi, 4
    call    parser_data_dup
    check_err
    test    r8d, r8d
    jnz     .next

    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain

    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_32
    cmp     byte [rel expr_pcrel], 0
    je      .abs32
    mov     r8, R_X86_64_PC32      ; "dd func - $": PC-relative, the field's
    add     rcx, rsi               ; place in the addend
.abs32:
    extern  reloc_record
    call    reloc_record
    check_err
    mov     rdi, [rbx + PREP_ctx]
    xor     rsi, rsi
    extern  asmctx_emit_dword
    call    asmctx_emit_dword
    jmp     .next

.plain:
    mov     rdi, r10                       ; "dd 0x100000000": NASM's warning
    mov     esi, 4
    push    r10
    call    warn_data_bounds
    pop     r10
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r10
    call    asmctx_emit_dword

.next:
    call    parser_item_end
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        call    parser_data_more           ; ("db 1," ends there, as in NASM)
        test    eax, eax
        jnz     .loop
        ENDIF
    xor     rax, rax
    epilogue

.error:
    epilogue

parser_emit_data_64:
    prologue
.loop:
    call    parser_item_begin
    mov     esi, 8
    call    parser_data_ext
    check_err
    test    edx, edx
    jnz     .next
    mov     esi, 8
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_DOUBLE
    mov     byte [rel expr_pcrel_ok], 1
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_pcrel_ok], 0
    mov     byte [rel float_fmt], 0
    check_err
    mov     esi, 8
    call    parser_data_dup
    check_err
    test    r8d, r8d
    jnz     .next

    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain

    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_64
    cmp     byte [rel expr_pcrel], 0
    je      .abs64
    mov     r8, R_X86_64_PC64      ; "dq x - $": PC-relative
    add     rcx, rsi
.abs64:
    call    reloc_record
    check_err
    mov     rdi, [rbx + PREP_ctx]
    xor     rsi, rsi
    extern  asmctx_emit_qword
    call    asmctx_emit_qword
    jmp     .next

.plain:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r10
    call    asmctx_emit_qword

.next:
    call    parser_item_end
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        call    parser_data_more           ; ("db 1," ends there, as in NASM)
        test    eax, eax
        jnz     .loop
        ENDIF
    xor     rax, rax
    epilogue

.error:
    epilogue

; expr_note_undef: name rsi met, not defined yet. Preserves all but flags.
expr_note_undef:
    cmp     qword [rel expr_undef_uses], 0
    jne     .counted
    mov     [rel expr_undef_first], rsi
.counted:
    inc     qword [rel expr_undef_uses]
    mov     [rel expr_undef_name], rsi
    ret

; parser_count_known: ZF set when the count just evaluated(rcx / r11) is a
; number: no name not defined yet, no address. Preserves every register.
parser_count_known:
    push    rax
    push    rdi
    test    rcx, rcx
    jnz     .not
    mov     rdi, r11
    call    expr_sym_class
    test    eax, eax
    jmp     .ret
.not:
    or      eax, 1                         ; ZF clear
.ret:
    pop     rdi
    pop     rax
    ret

; parser_data_more: after a data directive's comma: eax = 1 when an item
; follows, 0 at the end of the line ("db 1," is db 1, as in NASM)
parser_data_more:
    mov     rdi, rbx
    call    preprocessor_peek_token
    movzx   ecx, byte [rdx + TOKEN_kind]
    xor     eax, eax
    cmp     ecx, TOK_NEWLINE
    je      .end
    cmp     ecx, TOK_EOF
    je      .end
    inc     eax
.end:
    ret

; parser_item_begin / parser_item_end: around one item of a data
; directive: when it was "?", its bytes are uninitialised - "??" in the
; listing, and outside .bss NASM's warning (they are zeros). rbx =
; PrepState. Preserve rbx and r12-r15.
parser_item_begin:
    mov     byte [rel expr_question], 0
    xor     eax, eax
    mov     rcx, [rbx + PREP_ctx]
    mov     rcx, [rcx + ASMCTX_curr_sec]
    test    rcx, rcx
    jz      .start
    mov     rax, [rcx + SECTION_size]
.start:
    mov     [rel item_start], rax
    ret

parser_item_end:
    cmp     byte [rel expr_question], 0
    je      .ret
    mov     byte [rel expr_question], 0
    push    r12
    mov     rax, [rbx + PREP_ctx]
    mov     r12, [rax + ASMCTX_curr_sec]
    test    r12, r12
    jz      .out
    mov     rdi, [rel item_start]
    mov     rsi, [r12 + SECTION_size]
    call    lst_uninit
    cmp     byte [rel zero_warned], 0
    jne     .out                           ; this line's warning is given
    mov     byte [rel zero_warned], 1
    mov     rdi, r12
    call    parser_warn_zeroing
.out:
    pop     r12
.ret:
    ret

; parser_warn_zeroing: "uninitialized space declared in non-BSS section
; `.text': zeroing [-w+zeroing]" for section rdi, unless it is .bss
parser_warn_zeroing:
    cmp     dword [rdi + SECTION_elf_type], SHT_NOBITS
    je      .ret
    push    r12
    push    r13
    mov     r12, rdi
    ; NASM's words are its output format's: "in .text section" (bin),
    ; "in non-BSS section `.text'" (elf), "uninitialised ..." (win64)
    extern  global_ctx
    lea     r13, [rel zeroing_elf]
    lea     rax, [rel global_ctx]
    movzx   eax, byte [rax + ASMCTX_fmt]
    cmp     eax, FMT_BIN
    jne     .not_bin
    lea     r13, [rel zeroing_bin]
.not_bin:
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .words
    lea     r13, [rel zeroing_coff]
.words:
    mov     edi, WC_ZEROING
    call    warn_begin
    mov     rsi, [r13]
    call    warn_text
    mov     rsi, [r12 + SECTION_name]
    call    warn_text
    mov     rsi, [r13 + 8]
    call    warn_text
    call    warn_end
    pop     r13
    pop     r12
.ret:
    ret

[SECTION .rodata]
s_zeroing_a:   db "uninitialized space declared in non-BSS section `", 0
s_zeroing_b:   db "': zeroing", 0
s_zeroing_coff: db "uninitialised space declared in non-BSS section `", 0
s_zeroing_bin_a: db "uninitialized space declared in ", 0
s_zeroing_bin_b: db " section: zeroing", 0
alignb 8
zeroing_elf:   dq s_zeroing_a, s_zeroing_b
zeroing_bin:   dq s_zeroing_bin_a, s_zeroing_bin_b
zeroing_coff:  dq s_zeroing_coff, s_zeroing_b
s_attr_a:      db "unknown section attribute '", 0
s_attr_b:      db "' ignored on declaration of section `", 0
s_attr_c:      db "'", 0
s_attr_bin:    db 'ignoring unknown section attribute: "', 0
s_attr_eq:     db "=", 0
s_attr_q:      db '"', 0
[SECTION .bss]
alignb 8
attr_value:    resq 1              ; an unknown section attribute's value text
sec_prev_align: resq 1             ; a redeclared section's alignment before
attr_seen:     resb 2              ; parser_section_attrs: an attribute, align=
align_hex:     resb 24             ; "0x..." for an alignment's error
struc_open:    resq 1              ; a struc a section line left (its name)
last_label_name: resq 1             ; the last label parser_define_label made
last_label_off: resq 1              ; ... at this section offset (-1: none)
mem_struc:      resq 1              ; "[rbx:PACKET]": the struc (its name), 0: none
mem_typed_next: resb 1              ; "rbx:" read: the struc's name comes next
struc_size_buf: resb 136            ; NAME_size, for parser_is_struc
global masm_enabled
masm_enabled:  resb 1              ; %use masm: "flat:", a bare "ptr x" known
masm_mem:      resb 1              ; the operand's ptr was masm's
mem_open:      resb 1              ; a memory operand with no bracket (masm)
text_declared: resb 1              ; "section .text" was read
attr_depth:    resq 1              ; ... the parentheses open in it
[SECTION .rodata]
s_bits64:      db "64", 0
s_bits32:      db "32", 0
s_bits16:      db "16", 0
s_rel_regs:    db "indirect address displacements cannot be RIP-relative", 0
s_db_empty:    db "no operand for data declaration", 0
s_orphan:      db "label `", 0
s_orphan_tail: db "' alone on a line without a colon might be in error", 0
s_lbracket:    db "[", 0                ; "x: [bits 32]": found `['
s_space:       db " ", 0                ; "found `mvo eax'"
data_letters:  db "bwdqtoyz", 0
[SECTION .bss]
alignb 8
item_start:    resq 1                  ; parser_item_begin: the item's offset
expr_question: resb 1                  ; "?" was read (an uninitialised item)
zero_warned:   resb 1                  ; this data line has warned (zeroing)
alignb 8
times_res_mul: resq 1                  ; "times N resb K": N, for the resb
res_mul:       resq 1                  ; (taken by parser_handle_res)
expr_in_data:  resb 1                  ; a data directive is being read
alignb 8
size_list:     resq 1                  ; parser_size_late: {NAME, record}
gas_st_name:   resb 4                  ; "stN" (parser_parse_reg_info)
size_n:        resq 1
[SECTION .text]

; parser_field_width: a res* of R8 bytes each, RDX in all, at offset RCX of
; a struc - the field labelled just before it (last_label_*) is that wide
; ("[rbx:PACKET].len" takes its size from it). Preserves rdx, rbx, r12-r15.
parser_field_width:
    cmp     rcx, [rel last_label_off]
    jne     .fw_ret
    cmp     qword [rel last_label_name], 0
    je      .fw_ret                        ; no label yet ("struc s / resd 1": it
                                           ; looked a null name up, and crashed)
    mov     qword [rel last_label_off], -1
    push    rdx
    push    r8
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rel last_label_name]
    call    symbol_find
    mov     rcx, rdx
    pop     r8
    pop     rdx
    test    rax, rax
    jnz     .fw_ret
    mov     [rcx + SYMBOL_fwidth], r8b
    mov     [rcx + SYMBOL_size], rdx
.fw_ret:
    ret
