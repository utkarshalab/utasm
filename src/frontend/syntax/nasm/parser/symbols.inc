; ============================================================================
; File        : src/frontend/syntax/nasm/parser/symbols.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : resb .., extern, default, section / segment, global / weak / visibility, common, parser_finish; the directive word tables (cpu_levels)
; ============================================================================


;*
; * [parser_handle_res]
; * Purpose: RESB/RESW/RESD/RESQ — reserve uninitialised space in the
; *          current section (no bytes are emitted, the section just grows).
; * Input:
; *   RDI: PrepState*
; *   RSI: element size in bytes (1, 2, 4 or 8)
; * Output: RAX = EXIT_OK or error code
; ;
parser_handle_res:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = element size
    ; "times N" before it (parser_handle_times): N times the count
    mov     rax, [rel times_res_mul]
    mov     qword [rel times_res_mul], 0
    mov     [rel res_mul], rax

    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err
    call    parser_count_known     ; a count not known yet: as for times
    jz      .count_known
    mov     edi, EXIT_RES_NONCONST
    call    known_defer_error
    test    eax, eax
    jnz     .res_unknown
    xor     edx, edx
.count_known:
    ; a negative count, or bytes past 4 GiB: errors (NASM panicked on the
    ; one, ran for ever on the other; utasm faulted)
    test    rdx, rdx
    js      .negative
    imul    rdx, r12               ; total bytes to reserve
    jo      .too_large
    mov     rcx, [rel res_mul]
    test    rcx, rcx
    jz      .one
    imul    rdx, rcx
    jo      .too_large
.one:

    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .no_section
    cmp     dword [rax + SECTION_elf_type], SHT_NOBITS
    je      .size_ok                       ; (no bytes: any size)
    mov     rcx, [rax + SECTION_size]
    add     rcx, rdx
    jc      .too_large
    mov     r8d, 0xFFFFFFFF
    cmp     rcx, r8
    ja      .too_large
.size_ok:
    ; outside .bss, zeros: NASM's warning, and "??" in the listing
    cmp     dword [rax + SECTION_elf_type], SHT_NOBITS
    je      .reserve
    test    rdx, rdx
    jz      .reserve
    push    rax
    push    rdx
    mov     rdi, [rax + SECTION_size]
    lea     rsi, [rdi + rdx]
    call    lst_uninit
    cmp     qword [rel res_mul], 0
    je      .listed
    mov     edi, 4                         ; LK_RES: times N resb K, listed whole
    call    lst_mark
.listed:
    mov     rdi, [rsp + 8]
    call    parser_warn_zeroing
    pop     rdx
    pop     rax
.reserve:
    ; a struc's field (".len: resd 1"): the label just before it takes its
    ; element width and size - "[rbx:PACKET].len" is sized by them
    cmp     byte [rax + SECTION_type], SEC_ABSOLUTE
    jne     .not_field
    push    rax
    mov     rcx, [rax + SECTION_size]
    mov     r8, r12
    call    parser_field_width
    pop     rax
.not_field:
    add     [rax + SECTION_size], rdx
    mov     rdi, rax
    extern  asm_ctx_fit
    call    asm_ctx_fit                    ; (its bytes, past the buffer)
    jmp     .done
.negative:
    mov     rax, EXIT_RES_NEGATIVE
    jmp     .done
.too_large:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .too_large_code
    mov     rdi, [rax + SECTION_name]
    call    error_set_subject
.too_large_code:
    mov     rax, EXIT_SECTION_SIZE
    jmp     .done

.no_section:
    mov     rax, EXIT_INTERNAL
    jmp     .done

.res_unknown:
    ; the last pass: a name never defined in the count is NASM's "symbol
    ; `x' not defined" ("resb 2 * nothere")
    cmp     qword [rel expr_undef_uses], 0
    je      .error
    mov     rdi, [rel expr_undef_name]
    call    error_set_subject
    mov     eax, EXIT_UNDEF_SYMBOL
.error:
.done:
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_handle_extern]
; * Input: None (reads from preprocessor)
; ;
parser_handle_extern:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; rbx = PrepState
.loop:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .done
    mov     r12, rdx               ; r12 = token (name)
    xor     r14d, r14d             ; the ELF type
    xor     r15d, r15d             ; bit 9: weak; low byte: visibility
    mov     r13d, VIS_GLOBAL
    ; "extern f:function hidden", "extern w:weak": as for global
    cmp     byte [r12 + TOKEN_kind], TOK_LABEL
    je      .attrs
    IF byte [r12 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    jmp     .declare
.attrs:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err_to .done
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .declare
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel sym_attr_words]
    call    parser_word_index
    test    eax, eax
    jz      .declare
    imul    eax, eax, 12
    lea     rcx, [rel sym_attr_words]
    movzx   ecx, byte [rcx + rax - 1]
    cmp     ecx, 0x20
    jb      .attr_vis
    mov     r13d, VIS_GLOBAL
    cmp     ecx, 0x20
    jne     .attr_taken
    mov     r13d, VIS_WEAK
    jmp     .attr_taken
.attr_vis:
    cmp     ecx, 0x10
    jb      .attr_type
    and     ecx, 0x0F
    mov     r15b, cl
    jmp     .attr_taken
.attr_type:
    mov     r14d, ecx
.attr_taken:
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .attrs

.declare:
    ; -f win64: no visibility or weak binding, as for global
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .special_ok
    mov     rax, EXIT_COFF_SPECIAL
    test    r15b, r15b
    jnz     .done
    cmp     r13d, VIS_WEAK
    je      .done
.special_ok:
    ; Create symbol with SYM_EXTERN kind
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq

    mov     r11, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_EXTERN
    mov     [rsi + SYMBOL_vis], r13b
    mov     [rsi + SYMBOL_etype], r14b
    mov     [rsi + SYMBOL_eother], r15b
    mov     rax, [r12 + TOKEN_value]
    mov     [rsi + SYMBOL_name], rax

    mov     rdi, r11               ; rdi = AsmCtx
    extern  symbol_add
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    ; Re-declaring an extern is legal and idempotent; a type or binding
    ; given again applies
    IF rax, e, EXIT_DUP_SYMBOL
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, [r12 + TOKEN_value]
        call    symbol_find
        test    rax, rax
        jnz     .redeclared
        cmp     byte [rdx + SYMBOL_kind], SYM_EXTERN
        jne     .redeclared
        mov     [rdx + SYMBOL_vis], r13b
        test    r14b, r14b
        jz      .redeclared_type
        mov     [rdx + SYMBOL_etype], r14b
.redeclared_type:
        test    r15b, r15b
        jz      .redeclared
        mov     [rdx + SYMBOL_eother], r15b
.redeclared:
        xor     rax, rax
        ENDIF
    check_err
    ; "required": named in the object whether used or not
    cmp     byte [rel extern_required], 0
    je      .not_required
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .not_required
    or      byte [rdx + SYMBOL_pflags], SYMF_USED
.not_required:

    ; Check for comma (extern name1, name2)
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    jmp     .done

;*
; * [parser_handle_default]
; * Stub for 'default' directive (e.g. default rel)
; ;
parser_handle_default:
    ; DEFAULT REL  - [label] with no base/index register is RIP-relative
    ; DEFAULT ABS  - back to absolute addressing (the initial state)
    ; Other words on the line (e.g. NASM's BND/NOBND) are accepted and
    ; ignored. The setting applies to the rest of the file.
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_NEWLINE
        jmp .done
        ENDIF
    IF byte [rdx + TOKEN_kind], e, TOK_EOF
        jmp .done
        ENDIF
    IF byte [rdx + TOKEN_kind], e, TOK_RBRACKET
        jmp .done                  ; [default rel]
        ENDIF
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, rdx               ; r12 = consumed token
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .loop

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_rel]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_rel
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_rel_upper]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_rel
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_abs]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_abs
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_abs_upper]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_abs
    jmp     .loop

.set_rel:
    mov     rax, [rbx + PREP_ctx]
    or      dword [rax + ASMCTX_flags], CTX_FLAG_DEFAULT_REL
    mov     byte [rel default_given], 1    ; (memory.inc: implicit-abs-deprecated)
    jmp     .loop
.set_abs:
    mov     rax, [rbx + PREP_ctx]
    and     dword [rax + ASMCTX_flags], ~CTX_FLAG_DEFAULT_REL
    mov     byte [rel default_given], 1
    jmp     .loop

.done:
    pop     r12
    pop     rbx
    epilogue

[SECTION .rodata]
str_default_rel:        db "rel", 0
str_default_rel_upper:  db "REL", 0
str_default_abs:        db "abs", 0
str_default_abs_upper:  db "ABS", 0
[SECTION .text]

;*
; * [parser_default_section]
; * Purpose: Select .text before the first statement, as NASM does: code and
; *          data written before any "section" directive belong there (they
; *          were dropped), and org has a section to apply to.
; * Input  : RDI = AsmCtx
; * Output : RAX = OK or an error
; ;
global parser_default_section
parser_default_section:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rel str_text]
    call    asmctx_find_section
    test    rax, rax
    jz      .select
    mov     rdi, rbx
    lea     rsi, [rel str_text]
    mov     rdx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     word [rdx + SECTION_flags], (SHF_ALLOC | SHF_EXECINSTR)
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     byte [rdx + SECTION_type], SEC_TEXT
    mov     byte [rdx + SECTION_implicit], 1   ; placed as NASM would (elf64_order_text)
    cmp     byte [rbx + ASMCTX_fmt], FMT_BIN
    je      .select
    mov     qword [rdx + SECTION_align], 16    ; NASM's ELF default
.select:
    mov     [rbx + ASMCTX_curr_sec], rdx
    xor     eax, eax
.ret:
    pop     rbx
    ret

;*
; * [parser_handle_section_directive]
; * Input: RBX = PrepState (reads from preprocessor)
; ;
global parser_handle_section_directive
parser_handle_section_directive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    ; Get section name token
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx               ; r12 = token (.text, .data, etc)

    ; "[section]" with no name: nothing changes, as in NASM (it made a
    ; section with no name, which the ELF writer could not write)
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .no_name
    cmp     eax, TOK_EOF
    je      .no_name
    cmp     eax, TOK_RBRACKET
    jne     .name_text
.no_name:
    mov     rdi, rbx
    mov     rsi, r12
    call    preprocessor_putback_token
    xor     eax, eax
    jmp     .done

.name_text:
    ; "section 'bc'": a character constant's value is its characters
    ; packed, not a pointer to them (utasm crashed): their text
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    jne     .name_not_char
    mov     rdx, r12
    extern  prep_token_text
    call    prep_token_text
    test    rax, rax
    jz      .name_written
    mov     [r12 + TOKEN_value], rax
    mov     byte [r12 + TOKEN_kind], TOK_STRING
    jmp     .name_piece
.name_not_char:
    ; "section 5": a number's value is no pointer either - as written
    cmp     byte [r12 + TOKEN_kind], TOK_NUMBER
    je      .name_written
    cmp     byte [r12 + TOKEN_kind], TOK_FLOAT
    je      .name_written
    ; "section /": any word names a section in NASM; a token with no text
    ; of its own (an operator) is named by what was written (it made a
    ; section with no name, which the ELF writer could not write)
    cmp     qword [r12 + TOKEN_value], 0
    jne     .name_piece
.name_written:
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, 1
    extern  prep_tokens_text
    call    prep_tokens_text
    check_err
    mov     [r12 + TOKEN_value], rdx

    ; ".note.GNU-stack", "__LD,__compact_unwind": a name with '-' or ','
    ; in it lexes as several tokens; join the ones written together (NASM
    ; takes the name up to a blank)
.name_piece:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    mov     byte [rel sect_sep], '-'
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    je      .name_sep
    mov     byte [rel sect_sep], ','
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .name_done
.name_sep:
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [r12 + TOKEN_line]
    jne     .name_done
    movzx   eax, word [r12 + TOKEN_col]
    movzx   ecx, word [r12 + TOKEN_len]
    add     eax, ecx
    cmp     ax, [rdx + TOKEN_col]
    jne     .name_done
    mov     rdi, rbx
    call    preprocessor_next_token        ; the '-' / ','
    ; a copy of it, to put back: the peek below may reuse its slot (after
    ; ".note.GNU-stack" it did, and the "," of ',"",@progbits' came back
    ; as something else - a stray label "progbits")
    lea     rdi, [rel sect_sep_tok]
    mov     rsi, rdx
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    lea     r13, [rel sect_sep_tok]
    ; the next piece right after it ("a,b"; in "a, \"awx\"" a list goes on)
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [r13 + TOKEN_line]
    jne     .sep_back
    movzx   eax, word [r13 + TOKEN_col]
    inc     eax
    cmp     ax, [rdx + TOKEN_col]
    jne     .sep_back
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .sep_piece
    cmp     eax, TOK_NUMBER
    jne     .sep_back
.sep_piece:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the next piece
    check_err
    mov     r13, rdx
    mov     rdi, [r12 + TOKEN_value]
    call    str_len
    mov     r14, rax
    mov     rdi, [r13 + TOKEN_value]
    call    str_len
    lea     rsi, [r14 + rax + 2]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     r15, rdx
    mov     rdi, rdx
    mov     rsi, [r12 + TOKEN_value]
    call    str_concat
    mov     al, [rel sect_sep]
    mov     [r15 + r14], al
    mov     rdi, r15
    mov     rsi, [r13 + TOKEN_value]
    call    str_concat
    mov     [r12 + TOKEN_value], r15
    mov     rdi, r15
    call    str_len
    mov     [r12 + TOKEN_len], ax
    jmp     .name_piece
    jmp     .name_done
.sep_back:
    ; not a name's: the separator read again after it
    mov     rdi, rbx
    mov     rsi, r13
    extern  preprocessor_unread_token
    call    preprocessor_unread_token
.name_done:
    
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    extern  asmctx_find_section
    call    asmctx_find_section
    mov     r15, rax               ; r15 = find_section result
    
    IF r15, e, OK
        mov     r13, rdx               ; r13 = existing section
        ELSE
        ; Create new section
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, [r12 + TOKEN_value]
        mov     rdx, SEC_CUSTOM
        extern  asm_ctx_create_section
        call    asm_ctx_create_section
        check_err
        mov     r13, rdx
        ENDIF

    ; Set active section in AsmCtx (the one left: GNU's .previous)
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    cmp     rax, r13
    je      .prev_kept
    extern  sec_previous
    mov     [rel sec_previous], rax
.prev_kept:
    mov     [rdi + ASMCTX_curr_sec], r13
    ; the default .text takes its place among the sections where the
    ; source first names it, as in NASM
    cmp     byte [r13 + SECTION_implicit], 0
    je      .named
    cmp     dword [r13 + SECTION_named_at], 0
    jne     .named
    movzx   eax, word [rdi + ASMCTX_seccount]
    mov     [r13 + SECTION_named_at], eax
.named:
    ; __SECT__ names the section a plain "section" line chose; the
    ; primitive [section ...] form leaves it, as in NASM
    cmp     byte [rel stmt_bracketed], 0
    jne     .sect_noted
    mov     rax, [r12 + TOKEN_value]
    mov     [rel user_sect_name], rax
.sect_noted:

    ; -f win64: NASM's COFF defaults by name (parser_coff_section)
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .elf_defaults
    cmp     r15, OK
    je      .default_align_done            ; an existing one: as it is
    mov     rdi, [r12 + TOKEN_value]
    call    parser_coff_section
    jmp     .default_align_done
.elf_defaults:

    ; 2. Auto-assign flags and type for standard sections if new
    IF r15, ne, OK
        mov     rdi, [r12 + TOKEN_value]
        mov     dword [r13 + SECTION_elf_type], SHT_PROGBITS ; Default
        mov     word [r13 + SECTION_flags], SHF_ALLOC  ; NASM's for other names
        ; .tdata / .tbss (TLS), .init_array & co (their own types: the
        ; linker runs what they hold by those), .note, .comment, .ldata ...
        call    .known_name
        mov     rdi, [r12 + TOKEN_value]
        
        ; .text -> AX
        lea     rsi, [str_text]
        call    str_cmp
        IF rax, e, OK
            mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_EXECINSTR)
            mov byte [r13 + SECTION_type], SEC_TEXT
            ELSE
            ; .data -> AW
            mov     rdi, [r12 + TOKEN_value]   ; str_cmp advances rdi
            lea     rsi, [str_data]
            call    str_cmp
            IF rax, e, OK
                mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                mov byte [r13 + SECTION_type], SEC_DATA
                ELSE
                ; .bss -> AW, NOBITS
                mov     rdi, [r12 + TOKEN_value]
                lea     rsi, [str_bss]
                call    str_cmp
                IF rax, e, OK
                    mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                    mov dword [r13 + SECTION_elf_type], SHT_NOBITS
                    mov byte [r13 + SECTION_type], SEC_BSS
                    ELSE
                    ; .rodata -> A
                    mov     rdi, [r12 + TOKEN_value]
                    lea     rsi, [str_rodata]
                    call    str_cmp
                    IF rax, e, OK
                        mov word [r13 + SECTION_flags], SHF_ALLOC
                        mov byte [r13 + SECTION_type], SEC_RODATA
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF

    ; NASM's default alignments for the standard ELF sections: .text 16,
    ; .data / .rodata / .bss 4 (attributes below may change them)
    cmp     r15, OK
    je      .default_align_done
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    je      .default_align_done
    movzx   eax, byte [r13 + SECTION_type]
    mov     ecx, 16
    cmp     eax, SEC_TEXT
    je      .set_default_align
    mov     ecx, 4
    cmp     eax, SEC_DATA
    je      .set_default_align
    cmp     eax, SEC_BSS
    je      .set_default_align
    cmp     eax, SEC_RODATA
    jne     .default_align_done
.set_default_align:
    mov     [r13 + SECTION_align], rcx
.default_align_done:

    ; GNU's '.section NAME, "awx", @nobits' (gas.s): a new section's flags
    ; and type, in place of its name's
    extern  gas_sec_set, gas_sec_flags, gas_sec_type, gas_sec_entsize
    cmp     byte [rel gas_sec_set], 0
    je      .gas_flags_done
    mov     byte [rel gas_sec_set], 0
    cmp     r15, OK
    je      .gas_flags_done
    mov     ax, [rel gas_sec_flags]
    mov     [r13 + SECTION_flags], ax
    mov     al, [rel gas_sec_entsize]
    mov     [r13 + SECTION_entsize], al
    mov     qword [r13 + SECTION_align], 1     ; GNU's (alignment raises it)
    mov     eax, [rel gas_sec_type]
    mov     [r13 + SECTION_elf_type], eax
.gas_flags_done:

    ; 3. NASM attributes: progbits, nobits, alloc, exec, write, align=N
    mov     word [rel attr_seen], 0
    mov     rax, [r13 + SECTION_align]
    mov     [rel sec_prev_align], rax
    call    parser_section_attrs
    check_err
    ; a new section declared with attributes and no align=: aligned to 1,
    ; whatever its name's default (NASM's: "section .text progbits") -
    ; .text too, which utasm makes before the source names it, while it
    ; is still empty and not named before
    cmp     r15, OK
    jne     .attrs_not_old
    cmp     byte [rel text_declared], 0
    jne     .attrs_existing
    cmp     qword [r13 + SECTION_size], 0
    jne     .attrs_existing
    cmp     byte [r13 + SECTION_type], SEC_TEXT
    je      .attrs_not_old                 ; (.text, not named yet: as new)
.attrs_existing:
    ; a section declared again keeps the largest alignment asked for:
    ; "section .text align=64" then "section .text align=32" is 64, what
    ; the code placed under the first relies on (as NASM)
    mov     rax, [rel sec_prev_align]
    cmp     rax, [r13 + SECTION_align]
    jbe     .attrs_applied
    mov     [r13 + SECTION_align], rax
    jmp     .attrs_applied
.attrs_not_old:
    cmp     byte [rel coff_enabled], 0
    jne     .attrs_applied                 ; (ELF's rule, below)
.attrs_new:
    cmp     byte [rel attr_seen], 0
    je      .attrs_applied
    cmp     byte [rel attr_seen + 1], 0
    jne     .attrs_applied
    mov     qword [r13 + SECTION_align], 1
.attrs_applied:
    cmp     byte [r13 + SECTION_type], SEC_TEXT
    jne     .text_noted
    mov     byte [rel text_declared], 1
.text_noted:

    ; Reset last_global on section change (Removed to support local labels after section directives)
    
    
    ; 3. Check for attributes (comma + string)
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     r14, rdx               ; r14 = attribute token
        IF byte [r14 + TOKEN_kind], e, TOK_STRING
            mov     rsi, [r14 + TOKEN_value]
            xor     rax, rax           ; flags accumulator
        .flag_loop:
            mov     cl, [rsi]
            test    cl, cl
            jz      .flag_done
            IF cl, e, 'a'
                or ax, SHF_ALLOC
            ENDIF 
            IF cl, e, 'w'
                or ax, SHF_WRITE
            ENDIF 
            IF cl, e, 'x'
                or ax, SHF_EXECINSTR
            ENDIF 
            IF cl, e, 'M'
                or ax, SHF_MERGE
            ENDIF 
            IF cl, e, 'S'
                or ax, SHF_STRINGS
            ENDIF 
            IF cl, e, 'G'
                or ax, SHF_GROUP
            ENDIF 
            inc     rsi
            jmp     .flag_loop
        .flag_done:
            ; A90: Enforce W^X security policy (Write XOR Execute)
            mov     ecx, (SHF_WRITE | SHF_EXECINSTR)
            mov     edx, eax
            and     edx, ecx
            IF edx, e, ecx
                mov     rax, EXIT_LD_SCRIPT_PARSE
                jmp     .done
                ENDIF
            
            ; A92: Validate flag consistency for duplicate declarations; a
            ; new section takes the flags over the defaults for its name
            movzx   ecx, word [r13 + SECTION_flags]
            cmp     r15, OK
            je      .check_flags
            xor     ecx, ecx
        .check_flags:
            IF ecx, ne, 0
                IF ecx, ne, eax
                    mov     rax, EXIT_INVALID_SECTION_FLAGS
                    jmp     .done
                    ENDIF
                    ELSE
                mov     [r13 + SECTION_flags], ax
                ENDIF
            
            ; 3.1 Handle Group Signature if 'G' flag is set
            test    ax, SHF_GROUP
            jz      .no_group
            
            ; Expect comma, then signature name
            mov     rdi, rbx
            call    preprocessor_next_token
            IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
                mov     rax, EXIT_UNEXPECTED_TOKEN
                jmp     .done
                ENDIF
            mov     rdi, rbx
            call    preprocessor_next_token
            IF byte [rdx + TOKEN_kind], ne, TOK_IDENT
                mov     rax, EXIT_UNEXPECTED_TOKEN
                jmp     .done
                ENDIF
            
            mov     r14, rdx               ; r14 = signature token
            mov     rdi, [rbx + PREP_ctx]
            mov     rsi, [r14 + TOKEN_value]
            extern  symbol_find
            call    symbol_find
            IF rax, ne, OK
                ; Create UNDEF symbol as signature
                sub     rsp, SYMBOL_SIZE
                mov     rdi, rsp
                xor     rax, rax
                mov     rcx, 6
                rep stosq
                mov     rdi, [rbx + PREP_ctx]
                mov     rsi, rsp
                mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
                mov     [rsi + SYMBOL_name], r12 ; use r12 from caller context or r14? 
                ; Wait, r14 holds signature token
                mov     rax, [r14 + TOKEN_value]
                mov     [rsi + SYMBOL_name], rax
                mov     byte [rsi + SYMBOL_vis], VIS_GLOBAL
                call    symbol_add
                add     rsp, SYMBOL_SIZE
                ENDIF
            mov     [r13 + SECTION_group_sig], rdx
            
            ; 3.1.1 Check if this signature is already used in another group
            ; If not, increment group_count
            mov     r14, rdx               ; r14 = signature symbol
            mov     rdi, [rbx + PREP_ctx]
            xor     rcx, rcx               ; i = 0
        .sig_check_loop:
            cmp     cx, word [rdi + ASMCTX_seccount]
            jge     .sig_unique
            
            mov     rax, [rdi + ASMCTX_sections]
            mov     rax, [rax + rcx * 8]
            cmp     rax, r13               ; Skip current section
            je      .sig_next
            
            cmp     [rax + SECTION_group_sig], r14
            je      .sig_duplicate
        .sig_next:
            inc     rcx
            jmp     .sig_check_loop
            
        .sig_duplicate:
            jmp     .parse_comdat
            
        .sig_unique:
            inc     dword [rdi + ASMCTX_group_count]

        .parse_comdat:
            ; 3.2 Optional COMDAT keyword
            mov     rdi, rbx
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_COMMA
                mov     rdi, rbx
                call    preprocessor_next_token
                mov     rdi, rbx
                call    preprocessor_next_token
                mov     rdi, [rdx + TOKEN_value]
                lea     rsi, [str_comdat]
                call    str_cmp_kw
                IF rax, e, 0
                    mov dword [r13 + SECTION_group_flags], GRP_COMDAT
                    ENDIF
                    ENDIF
            
        .no_group:
        ENDIF

        ; 4. Optional: Type (@progbits, etc)
        mov     rdi, rbx
        call    preprocessor_peek_token
        IF byte [rdx + TOKEN_kind], e, TOK_COMMA
            mov     rdi, rbx
            call    preprocessor_next_token
            mov     rdi, rbx
            call    preprocessor_next_token
            ; Check for @progbits, @nobits, etc
            ; For now, support @ progbits as separate or joined
            ENDIF
            ENDIF
    
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; .known_name: a new section named as one of sec_known gets its type,
; flags and alignment (r12 = the name's token, r13 = the SECTION).
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
.known_name:
    lea     r8, [rel sec_known]
.known_next:
    cmp     byte [r8], 0
    je      .known_ret
    push    r8
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r8
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .known_hit
    add     r8, 24
    jmp     .known_next
.known_hit:
    mov     eax, [r8 + 16]
    mov     [r13 + SECTION_elf_type], eax
    mov     ax, [r8 + 20]
    mov     [r13 + SECTION_flags], ax
    movzx   eax, word [r8 + 22]
    mov     [r13 + SECTION_align], rax
.known_ret:
    ret

;*
; * [parser_handle_visibility]
; * RSI = Target visibility (SYM_GLOBAL, SYM_WEAK)
; ;
parser_handle_visibility:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi               ; r12 = visibility

    ; global NAME[:type [visibility] [size]] [, NAME...]
.name:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r13, rdx               ; r13 = token
    xor     r14d, r14d             ; the declared ELF type
    xor     r15d, r15d             ; bit 8: typed, bit 9: weak; low byte:
                                   ; visibility
    ; GNU's syntax: ".globl \"main\"" (GCC 16's quoted names)
    cmp     byte [r13 + TOKEN_kind], TOK_STRING
    jne     .not_quoted
    cmp     byte [rel gas_names], 0
    je      .not_quoted
    cmp     byte [r13 + TOKEN_quote], '"'
    jne     .not_quoted
    mov     byte [r13 + TOKEN_kind], TOK_IDENT
.not_quoted:
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    je      .typed                 ; "f:function": the colon made a label
    IF byte [r13 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    jmp     .have_name
.typed:
    or      r15d, 0x100
.type_word:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .have_name
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel sym_attr_words]
    call    parser_word_index      ; eax = row + 1, 0 if none
    test    eax, eax
    jz      .have_name
    imul    eax, eax, 12
    lea     rcx, [rel sym_attr_words]
    movzx   ecx, byte [rcx + rax - 1]      ; the row's value byte
    cmp     ecx, 0x20
    jb      .not_binding
    ; "global f:function weak": its binding
    and     r15d, ~0x200
    cmp     ecx, 0x20
    jne     .attr_used                     ; strong
    or      r15d, 0x200
    jmp     .attr_used
.not_binding:
    cmp     ecx, 0x10
    jb      .is_type
    and     ecx, 0x0F
    mov     r15b, cl               ; default / internal / hidden / protected
    jmp     .attr_used
.is_type:
    mov     r14d, ecx
.attr_used:
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .type_word
.have_name:
    ; -f win64: a visibility or a weak binding has no COFF form (NASM's
    ; error); a type does - a function's is written
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .special_ok
    test    r15d, 0x2FF
    jz      .special_ok
    mov     rax, EXIT_COFF_SPECIAL
    jmp     .error
.special_ok:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r13 + TOKEN_value]
    extern  symbol_find
    call    symbol_find

    IF rax, e, OK
        ; A91: Audit symbol binding visibility conflicts
        movzx   eax, byte [rdx + SYMBOL_vis]
        ; A global or weak symbol is already visible to the linker: demoting
        ; it to local is a conflict (the global branch used to be empty, so
        ; only weak symbols were checked)
        cmp     r12b, VIS_LOCAL
        jne     .vis_ok
        cmp     al, VIS_GLOBAL
        je      .vis_conflict
        cmp     al, VIS_WEAK
        jne     .vis_ok
.vis_conflict:
        mov     rax, EXIT_SYMBOL_RANGE
        jmp     .error
.vis_ok:
        mov     byte [rdx + SYMBOL_vis], r12b
        test    r15d, 0x200
        jz      .vis_set
        mov     byte [rdx + SYMBOL_vis], VIS_WEAK   ; "global g:weak"
.vis_set:
        test    r15d, 0x100
        jz      .next_name
        mov     [rdx + SYMBOL_etype], r14b
        mov     [rdx + SYMBOL_eother], r15b
        ELSE
        ; Symbol doesn't exist, create it as UNDEFINED for now
        sub     rsp, SYMBOL_SIZE
        mov     rdi, rsp
        xor     rax, rax
        mov     rcx, SYMBOL_SIZE / 8           ; the whole record (was 48 bytes)
        rep stosq
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rsp
        mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
        mov     rax, [r13 + TOKEN_value]
        mov     [rsi + SYMBOL_name], rax
        mov     byte [rsi + SYMBOL_vis], r12b
        test    r15d, 0x200
        jz      .new_vis_set
        mov     byte [rsi + SYMBOL_vis], VIS_WEAK
.new_vis_set:
        mov     [rsi + SYMBOL_etype], r14b
        mov     [rsi + SYMBOL_eother], r15b
        call    symbol_add
        add     rsp, SYMBOL_SIZE
        ENDIF

.next_name:
    ; "global f:function (f.end - f)": the size names labels that come
    ; later, so its tokens are kept and evaluated when the whole source
    ; has been read (parser_finish)
    test    r15d, 0x100
    jz      .rest
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .rest
    cmp     eax, TOK_EOF
    je      .rest
    cmp     eax, TOK_COMMA
    je      .rest
    mov     eax, [rel gsize_count]
    cmp     eax, GSIZE_MAX
    jae     .rest
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, (GSIZE_TOKENS + 1) * TOKEN_SIZE
    call    arena_alloc
    check_err
    mov     r14, rdx                       ; the tokens
    xor     r15d, r15d                     ; how many
.size_tok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .size_kept
    cmp     eax, TOK_EOF
    je      .size_kept
    cmp     eax, TOK_COMMA
    je      .size_kept
    cmp     r15d, GSIZE_TOKENS
    jae     .size_kept
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, rdx
    imul    rdi, r15, TOKEN_SIZE
    add     rdi, r14
    copy_token
    inc     r15d
    jmp     .size_tok
.size_kept:
    test    r15d, r15d
    jz      .rest
    mov     eax, [rel gsize_count]
    lea     rcx, [rel gsize_names]
    mov     rdx, [r13 + TOKEN_value]
    mov     [rcx + rax * 8], rdx
    lea     rcx, [rel gsize_toks]
    mov     [rcx + rax * 8], r14
    lea     rcx, [rel gsize_ntok]
    mov     [rcx + rax * 4], r15d
    inc     dword [rel gsize_count]
.rest:
    ; the rest up to a comma or the end of the line
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .ok
    cmp     eax, TOK_EOF
    je      .ok
    cmp     eax, TOK_RBRACKET
    je      .ok
    push    rax
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rax
    cmp     eax, TOK_COMMA
    je      .name
    jmp     .next_name
.ok:
    mov     rax, OK
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_finish]
; * Purpose: Work that needs the whole source read. The sizes written with
; *   "global f:function (f.end - f)" name labels defined later, so their
; *   tokens were kept (parser_handle_visibility) and are evaluated now,
; *   replayed through the preprocessor like a %rep body.
; * Input  : RDI = PrepState
; * Output : RAX = OK
; ;
global parser_finish
parser_finish:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    xor     r12d, r12d
.next:
    cmp     r12d, [rel gsize_count]
    jae     .done
    ; the tokens and a newline ending them
    lea     rax, [rel gsize_toks]
    mov     r13, [rax + r12 * 8]
    lea     rax, [rel gsize_ntok]
    mov     r14d, [rax + r12 * 4]
    imul    rdi, r14, TOKEN_SIZE
    add     rdi, r13
    lea     rsi, [rdi - TOKEN_SIZE]
    copy_token
    imul    rax, r14, TOKEN_SIZE
    mov     byte [r13 + rax + TOKEN_kind], TOK_NEWLINE
    inc     r14d
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .skip
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     [rdx + MACRO_ntokens], r14d
    mov     [rdx + MACRO_tokens], r13
    mov     byte [rbx + PREP_has_peek], FALSE    ; the end of the file
    mov     rdi, rbx
    mov     rsi, rdx
    extern  prep_expand_start
    call    prep_expand_start
    test    rax, rax
    jnz     .skip
    ; the code between the labels is not frozen (its jumps shorten as
    ; NASM's do): the size moves with its end when they do (src/optimize/
    ; jump.s), as "f.end - f" then measures
    extern  relax_no_freeze
    mov     byte [rel relax_no_freeze], 1
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel relax_no_freeze], 0
    push    rax
    push    rdx
    mov     rdi, rbx
    call    parser_drain_line              ; what is left, and the newline
    pop     rdx
    pop     rax
    test    rax, rax
    jnz     .skip
    mov     r14, rdx                       ; the size
    lea     rax, [rel gsize_names]
    mov     rsi, [rax + r12 * 8]
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .skip
    mov     [rdx + SYMBOL_size], r14
.skip:
    inc     r12d
    jmp     .next
.done:
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
gsize_count:   resd 1              ; "global f:function (size)" waiting
gsize_names:   resq GSIZE_MAX
gsize_toks:    resq GSIZE_MAX
gsize_ntok:    resd GSIZE_MAX
[SECTION .text]

;*
; * [parser_word_index]
; * Purpose: Which row of a word table (12-byte rows: the word, NUL-padded
; *   to 11 bytes, then a value byte; a 0 byte ends it) matches a word.
; * Input  : RDI = word, RSI = table
; * Output : EAX = row + 1, or 0
; ;
parser_word_index:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    xor     r14d, r14d
.row:
    cmp     byte [r13], 0
    je      .none
    inc     r14d
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 12
    jmp     .row
.hit:
    mov     eax, r14d
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_handle_common]
; * Purpose: NASM's "common NAME SIZE[:ALIGN]": an uninitialised common
; *   block, merged by the linker (SHN_COMMON, value = alignment).
; * Input  : RBX = PrepState
; ;
parser_handle_common:
    push    r12
    push    r13
    push    r14
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; size
    xor     r14d, r14d                     ; alignment (none given: 0, NASM's)
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .define
    ; -f bin: no symbol types, nor common blocks
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    mov     eax, EXIT_BIN_SPECIAL
    je      .ret
    ; -f win64: a common block has no alignment there (NASM's error)
    extern  coff_enabled
    mov     rax, EXIT_COFF_SPECIAL
    cmp     byte [rel coff_enabled], 0
    jne     .ret
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
.define:
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    mov     eax, EXIT_BIN_COMMON
    je      .ret
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jz      .fill
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     [rsp + SYMBOL_name], r12
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    test    rax, rax
    jnz     .ret
.fill:
    mov     byte [rdx + SYMBOL_kind], SYM_COMMON
    mov     byte [rdx + SYMBOL_vis], VIS_GLOBAL
    mov     byte [rdx + SYMBOL_etype], ETYPE_NOTYPE
    mov     word [rdx + SYMBOL_section], SHN_COMMON
    mov     [rdx + SYMBOL_value], r14
    mov     [rdx + SYMBOL_size], r13
    xor     eax, eax
    jmp     .ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
; "global f:type visibility": word (11 bytes) + value (< 0x10: an ELF
; type, 0x10 + n: a visibility)
sym_attr_words:
    db "function", 0, 0, 0, ETYPE_FUNC
    db "func", 0, 0,0,0,0,0,0, ETYPE_FUNC
    db "data", 0, 0,0,0,0,0,0, ETYPE_OBJECT
    db "object", 0, 0,0,0,0, ETYPE_OBJECT
    db "notype", 0, 0,0,0,0, ETYPE_NOTYPE
    db "tls", 0, 0,0,0,0,0,0,0, ETYPE_TLS
    db "tls_object", 0, ETYPE_TLS
    db "default", 0, 0,0,0, 0x10
    db "internal", 0, 0, 0, 0x11
    db "hidden", 0, 0,0,0,0, 0x12
    db "protected", 0, 0, 0x13
    db "weak", 0, 0,0,0,0,0,0, 0x20        ; the binding
    db "strong", 0, 0,0,0,0, 0x21
    db 0
str_common_d:  db "common", 0
str_static_d:  db "static", 0
str_wrt:       db "wrt", 0
str_imagebase: db "..imagebase", 0
; "wrt ..name": word (11 bytes) + WRT_*
wrt_words:
    db "..plt", 0, 0,0,0,0,0, WRT_PLT
    db "..gotpcrel", 0, WRT_GOTPCREL
    db "..got", 0, 0,0,0,0,0, WRT_GOT
    db "..gotoff", 0, 0, 0, WRT_GOTOFF
    db "..tlsie", 0, 0,0,0, WRT_TLSIE
    db "..sym", 0, 0,0,0,0,0, WRT_SYM
    db "..gotpc", 0, 0,0,0, WRT_GOTPC
    db "..tlsgd", 0, 0,0,0, WRT_TLSGD
    db "..tlsld", 0, 0,0,0, WRT_TLSLD
    db "..dtpoff", 0, 0, 0, WRT_DTPOFF
    db "..tpoff", 0, 0,0,0, WRT_TPOFF
    db "..gottpoff", 0, WRT_TLSIE
    db 0
[SECTION .text]

[SECTION .rodata]
str_global:    db "global", 0
str_weak:      db "weak", 0
str_local:     db "local", 0
str_align:     db "align", 0
str_p2align:   db "p2align", 0
str_section:   db "section", 0
str_segment:   db "segment", 0
str_cpu:       db "cpu", 0
str_8086:      db "8086", 0
; "cpu" words: 10-byte name, the CPUF_* bits kept (and), set (or)
cpu_words:
    db "default", 0, 0, 0, 0, 0
    db "latevex", 0, 0, 0, ~CPUF_LATEVEX & 0xFF, CPUF_LATEVEX
    db "nolatevex", 0, ~CPUF_LATEVEX & 0xFF, 0
    db "vex", 0, 0, 0, 0, 0, 0, 0, ~CPUF_NOVEX & 0xFF, 0
    db "novex", 0, 0, 0, 0, 0, 0xFF, CPUF_NOVEX
    db "evex", 0, 0, 0, 0, 0, 0, ~CPUF_NOEVEX & 0xFF, 0
    db "noevex", 0, 0, 0, 0, 0xFF, CPUF_NOEVEX
    db 0
; parser_cpu_num: a level's name, its number (cpu_num)
s_got_name: db "_GLOBAL_OFFSET_TABLE_", 0
; parser_gas_symbol: GNU's sym@NAME - WRT_*, then NAME
gas_wrt_words:
    db WRT_PLT, "plt", 0, WRT_GOTPCREL, "gotpcrel", 0, WRT_GOTOFF, "gotoff", 0
    db WRT_GOTPC, "gotpc", 0, WRT_TLSIE, "gottpoff", 0, WRT_TLSIE, "gotntpoff", 0
    db WRT_TLSIE, "indntpoff", 0, WRT_GOT, "got", 0, WRT_TPOFF, "tpoff", 0
    db WRT_TPOFF, "ntpoff", 0, WRT_TLSGD, "tlsgd", 0, WRT_TLSLD, "tlsld", 0
    db WRT_DTPOFF, "dtpoff", 0, 0
cpu_levels:
    db "8086", 0, 1, "186", 0, 2, "286", 0, 3, "386", 0, 4, "486", 0, 5
    db "586", 0, 6, "pentium", 0, 6, "pentiummmx", 0, 6, "686", 0, 7
    db "p6", 0, 7, "ppro", 0, 7, "pentiumpro", 0, 7, "p2", 0, 7
    db "pentiumii", 0, 7, "p3", 0, 8, "katmai", 0, 8, "p4", 0, 9
    db "willamette", 0, 9, "prescott", 0, 10, "x64", 0, 11, "nehalem", 0, 12
    db "westmere", 0, 13, "sandybridge", 0, 14, "ivybridge", 0, 15
    ; (IA-64's x86 mode: Prescott's level, as NASM 3 has it)
    db "ia64", 0, 10, "itanium", 0, 10, "itanic", 0, 10, "merced", 0, 10
    db "any", 0, 0, "all", 0, 0, "default", 0, 0
    db 0
str_cpu_x86:   db "x86", 0             ; "x86-64"
str_cpu_ia:    db "ia", 0              ; "ia-64"
; words that make the name before them a label without its colon
stmt_words:    db "db", 0, "dw", 0, "dd", 0, "dq", 0, "dt", 0, "resb", 0, "resw", 0
               db "resd", 0, "resq", 0, "rest", 0, "times", 0, "incbin", 0
               db "do", 0, "dy", 0, "dz", 0, "reso", 0, "resy", 0, "resz", 0, 0
attr_progbits: db "progbits", 0
attr_nobits:   db "nobits", 0
attr_align:    db "align", 0
; alloc/noalloc, exec/noexec, write/nowrite: 8 bytes each, even = set
attr_flag_names: db "alloc", 0, 0, 0, "noalloc", 0, "exec", 0, 0, 0, 0
               db "noexec", 0, 0, "write", 0, 0, 0, "nowrite", 0
               db "tls", 0, 0, 0, 0, 0, "notls", 0, 0, 0
attr_flag_bits: dw SHF_ALLOC, SHF_ALLOC, SHF_EXECINSTR, SHF_EXECINSTR, SHF_WRITE, SHF_WRITE
               dw SHF_TLS, SHF_TLS
str_section_upper: db "SECTION", 0
str_times:     db "times", 0
res_words:     db "resb", 0, "resw", 0, "resd", 0, "resq", 0, "rest", 0
               db "reso", 0, "resy", 0, "resz", 0, 0
str_struc:     db "struc", 0
str_endstruc:  db "endstruc", 0
str_strucstart: db ".strucstart", 0
str_cfi_simple: db "simple", 0
; .cfi_ directives: name after ".cfi_" (30 bytes), CFI_*, the arguments:
; 0 none, 1 register, 2 offset, 3 register and offset, 4 two registers,
; 5 [simple], 6 bytes, 7 nothing recorded
cfi_words:
    db "startproc", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_START, 5
    db "endproc", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_END, 0
    db "def_cfa", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_DEF_CFA, 3
    db "def_cfa_register", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_DEF_CFA_REG, 1
    db "def_cfa_offset", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_DEF_CFA_OFF, 2
    db "adjust_cfa_offset", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_ADJUST, 2
    db "offset", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_OFFSET, 3
    db "rel_offset", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_REL_OFFSET, 3
    db "restore", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_RESTORE, 1
    db "undefined", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_UNDEFINED, 1
    db "same_value", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_SAME, 1
    db "register", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_REGISTER, 4
    db "remember_state", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_REMEMBER, 0
    db "restore_state", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_RESTORE_STATE, 0
    db "signal_frame", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_SIGNAL, 0
    db "escape", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, CFI_ESCAPE, 6
    db "sections", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7
    db 0
; the directives NASM makes standard macros, word (11 bytes) + the numbers
; of its %% counter each takes (parser_handle_pseudo_op): one for the
; macro, one more for a context it opens (struc, istruc) or a macro it
; calls (align, alignb, incbin); endstruc counts at parser_parse_struc
std_macro_words:
    db "section", 0, 0,0,0, 1
    db "segment", 0, 0,0,0, 1
    db "absolute", 0, 0,0, 1
    db "global", 0, 0,0,0,0, 1
    db "extern", 0, 0,0,0,0, 1
    db "common", 0, 0,0,0,0, 1
    db "static", 0, 0,0,0,0, 1
    db "required", 0, 0,0, 1
    db "bits", 0, 0,0,0,0,0,0, 1
    db "use16", 0, 0,0,0,0,0, 1
    db "use32", 0, 0,0,0,0,0, 1
    db "use64", 0, 0,0,0,0,0, 1
    db "default", 0, 0,0,0, 1
    db "cpu", 0, 0,0,0,0,0,0,0, 1
    db "float", 0, 0,0,0,0,0, 1
    db "sectalign", 0, 0, 1
    db "align", 0, 0,0,0,0,0, 2
    db "alignb", 0, 0,0,0,0, 2
    db "incbin", 0, 0,0,0,0, 2
    db "struc", 0, 0,0,0,0,0, 2
    db "istruc", 0, 0,0,0,0, 1             ; (its context: parser_istruc)
    db "at", 0, 0,0,0,0,0,0,0,0, 1
    db "iend", 0, 0,0,0,0,0,0, 1
    db 0
str_field:     db "field", 0
    ; str_rel (Defined at line 759)
str_lsl:       db "lsl", 0
str_lsr:       db "lsr", 0
str_asr:       db "asr", 0
str_ror:       db "ror", 0
str_comdat:    db "comdat", 0
str_org:       db "org", 0
str_required:  db "required", 0
s_num_wide_a:  db "numeric constant ", 0
s_num_wide_b:  db " does not fit in 64 bits", 0
s_dollar_hex:  db "$ prefix for hexadecimal is deprecated", 0
; one-byte instructions a "times K-($-$$)" pads with: name, then the byte
fill_insns:    db "nop", 0, 0, 0x90
               db "int3", 0, 0xCC
               db "hlt", 0, 0, 0xF4
               db 0
str_seg_op:    db "seg", 0
; the words a [ ] statement takes (NASM's directives; org and map the flat
; formats', osabi ELF's)
bracket_words: db "absolute", 0, "bits", 0, "common", 0, "cpu", 0, "debug", 0
               db "default", 0, "extern", 0, "float", 0, "global", 0
               db "static", 0, "list", 0, "section", 0, "segment", 0
               db "warning", 0, "sectalign", 0, "pragma", 0, "required", 0
               db "org", 0, "map", 0, "osabi", 0, "gprefix", 0, "gpostfix", 0
               db "lprefix", 0, "lpostfix", 0, "dollarhex", 0, 0
str_map:       db "map", 0
str_pragma:    db "pragma", 0
str_text:      db ".text", 0
str_db:        db "db", 0
str_data:      db ".data", 0
; NASM's defaults for other known names: 16-byte name, sh_type, flags, align
sec_known:
               db ".tdata", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               dd 1
               dw SHF_ALLOC | SHF_WRITE | SHF_TLS, 4
               db ".tbss", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               dd 8
               dw SHF_ALLOC | SHF_WRITE | SHF_TLS, 4
               db ".init_array", 0, 0, 0, 0, 0
               dd 14
               dw SHF_ALLOC, 8
               db ".fini_array", 0, 0, 0, 0, 0
               dd 15
               dw SHF_ALLOC, 8
               db ".preinit_array", 0, 0
               dd 16
               dw SHF_ALLOC, 8
               db ".comment", 0, 0, 0, 0, 0, 0, 0, 0
               dd 1
               dw 0, 1
               db ".note", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               dd 7
               dw 0, 4
               db ".lrodata", 0, 0, 0, 0, 0, 0, 0, 0
               dd 1
               dw SHF_ALLOC, 4
               db ".ldata", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               dd 1
               dw SHF_ALLOC | SHF_WRITE, 4
               db ".lbss", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               dd 8
               dw SHF_ALLOC | SHF_WRITE, 4
               db 0
str_bss:       db ".bss", 0
str_rodata:    db ".rodata", 0
str_extern:    db "extern", 0
str_default:   db "default", 0
str_default_upper: db "DEFAULT", 0
str_bits:      db "bits", 0
msg_debug_pseudo: db "DEBUG: Pseudo-op: ", 0
msg_newline:      db 10, 0
msg_debug_token:   db "DEBUG: Token: ", 0
msg_parser_entry: db "DEBUG: Parser entry", 10, 0
msg_debug_lookup: db "DEBUG: Mnemonic lookup finished", 10, 0
msg_debug_null:   db "(null)", 0

str_byte:  db "byte", 0
str_word:  db "word", 0
str_dword: db "dword", 0
str_qword: db "qword", 0
str_tword: db "tword", 0
str_tbyte:     db "tbyte", 0
str_oword: db "oword", 0
str_yword: db "yword", 0
str_zword: db "zword", 0
str_ptr:   db "ptr", 0
str_strict: db "strict", 0
str_nosplit: db "nosplit", 0
str_near:   db "near", 0
str_short:  db "short", 0
str_far:    db "far", 0
; NASM's encoding prefixes: 7-byte word, its INSTF_* bit
enc_prefix_words:
    db "rex", 0, 0, 0, 0, INSTF_REX
    db "vex", 0, 0, 0, 0, INSTF_VEX
    db "vex2", 0, 0, 0, INSTF_VEX
    db "vex3", 0, 0, 0, INSTF_VEX | INSTF_VEX3
    db "evex", 0, 0, 0, INSTF_EVEX
    db "disp8", 0, 0, INSTF_DISP8
    db "disp32", 0, INSTF_DISP32
    db 0
; APX's: 3-byte word, its APX_* bit (INST_apx)
apx_prefix_words:
    db "nf", 0, APX_NF
    db "zu", 0, APX_ZU
    db 0
str_dfv:    db "dfv", 0
; {dfv=...}: a flag's name (2 bytes, as written in lower case) and its bit
dfv_words:  db "of", 8, "sf", 4, "zf", 2, "cf", 1, 0
str_to:     db "to", 0
msg_debug_token_kind: db "Debug token kind: ", 0
msg_size_spec_bracket: db "Size specifier expected '[' but got kind: ", 0

[SECTION .text]
global parser_parse_size_specifier_string
%define SIZE_WORD_LETTERS 0x349400a            ; b d o q t w y z (a = bit 0)
parser_parse_size_specifier_string:
    prologue
    push    rbx                     ; Preserve rbx
    mov     rbx, rdi                ; rbx = input string

    ; 0. Only a word starting as a size word does (b d o q t w y z): every
    ;    operand comes here
    test    rbx, rbx
    jz      .not_size
    movzx   eax, byte [rbx]
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 25
    ja      .not_size
    mov     esi, SIZE_WORD_LETTERS
    bt      esi, eax
    jnc     .not_size

    ; 1. Check "byte" -> 8
    mov     rdi, rbx
    lea     rsi, [rel str_byte]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_byte

    ; 2. Check "word" -> 16
    mov     rdi, rbx
    lea     rsi, [rel str_word]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_word

    ; 3. Check "dword" -> 32
    mov     rdi, rbx
    lea     rsi, [rel str_dword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_dword

    ; 4. Check "qword" -> 64
    mov     rdi, rbx
    lea     rsi, [rel str_qword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_qword

    ; 5. Check "tword" -> 80 (and "tbyte", the MASM/GAS spelling)
    mov     rdi, rbx
    lea     rsi, [rel str_tword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_tword
    mov     rdi, rbx
    lea     rsi, [rel str_tbyte]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_tword

    ; 6. Check "oword" -> 128
    mov     rdi, rbx
    lea     rsi, [rel str_oword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_oword

    ; 7. Check "yword" -> 256
    mov     rdi, rbx
    lea     rsi, [rel str_yword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_yword

    ; 8. Check "zword" -> 512
    mov     rdi, rbx
    lea     rsi, [rel str_zword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_zword

    ; Not a size specifier
.not_size:
    mov     rdi, rbx
    lea     rsi, [rel str_zword]
    xor     rax, rax
    jmp     .done

.is_byte:
    mov     rax, 8
    jmp     .done
.is_word:
    mov     rax, 16
    jmp     .done
.is_dword:
    mov     rax, 32
    jmp     .done
.is_qword:
    mov     rax, 64
    jmp     .done
.is_tword:
    mov     rax, 80
    jmp     .done
.is_oword:
    mov     rax, 128
    jmp     .done
.is_yword:
    mov     rax, 256
    jmp     .done
.is_zword:
    mov     rax, 512
    jmp     .done

.done:
    pop     rbx
    epilogue

[SECTION .bss]
utf_value_chars: resq 1            ; a character constant's bytes (__utf16__('a'))
[SECTION .text]
