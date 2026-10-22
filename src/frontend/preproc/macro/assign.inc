; ============================================================================
; File        : src/frontend/preproc/macro/assign.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %assign, %undef, predefined and dynamic macros (__LINE__ ...), %ifnidn, %warning, %exitrep, %exitmacro, built-in macros
; ============================================================================


; ---- prep_handle_assign -----------------
;
; prep_handle_assign
; Handles "%assign NAME <expression>". Unlike %define, the value is an
; integer expression evaluated immediately, and re-assignment is allowed
; (that is what makes counters like "%assign i i+1" work).
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_assign:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE + SYMBOL_SIZE
    mov     rbx, rdi               ; rbx = PrepState

    ; A previous expression-evaluating directive can leave the terminating
    ; NEWLINE in the peek slot. The name below is lexed straight from the
    ; lexer, which does not consult that slot, so drop it first.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_stale_peek
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .no_stale_peek
    mov     byte [rbx + PREP_has_peek], FALSE
.no_stale_peek:

    ; 1. Read the name through the preprocessor, not the raw lexer: inside a
    ;    %rep or %macro body the tokens come from the expansion, not the file.
    ;    Not expanded: a name that is also a %define stays the name.
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .error_ident
    mov     r13, [r12 + TOKEN_value]

    ; 2. Evaluate the value (same evaluator %if uses)
    mov     qword [rel expr_undef_uses], 0
    mov     rdi, rbx
    extern  parser_evaluate_pp
    call    parser_evaluate_pp
    test    rax, rax
    jnz     .error
    mov     r14, rdx               ; r14 = value
    lea     rdi, [rel s_cn_assign]
    call    prep_const_check
    test    rax, rax
    jnz     .done

    ; 3. Re-assign in place when the name already exists (it may have been
    ;    a %define: it is a number now)
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    prep_symbol_find
    test    rax, rax
    jnz     .create
    mov     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    or      byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    mov     [rdx + SYMBOL_value], r14
    xor     rax, rax
    jmp     .done

.create:
    lea     rdi, [rsp + TOKEN_SIZE]
    mov     rcx, (SYMBOL_SIZE / 8)
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rdi + SYMBOL_pflags], SYMF_ASSIGN
    mov     [rdi + SYMBOL_name], r13
    mov     [rdi + SYMBOL_value], r14

    mov     rsi, rdi
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_add
    test    rax, rax
    jnz     .error
    xor     rax, rax
    jmp     .done

.error_ident:
    mov     rax, EXIT_DEFINE
    jmp     .done

.error:
    test    rax, rax
    jnz     .done
    mov     rax, EXIT_DEFINE

.done:
    add     rsp, TOKEN_SIZE + SYMBOL_SIZE
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_undef ------------------
;
; prep_handle_undef
; "%undef NAME" removes a %define. The symbol entry stays in the table (its
; slot keeps later probes working) but gets an empty name, which no lookup
; matches; a later %define NAME creates a fresh entry.
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_undef:
    push    rbx
    mov     rbx, rdi
    mov     byte [rel prep_noexpand], 1    ; the name, not its body
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    mov     rdi, [rbx + PREP_ctx]
    call    prep_symbol_find
    test    rax, rax
    jnz     .ok                            ; not defined: nothing to remove
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .remove                        ; a %define
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .ok                            ; only %define/%assign names
.remove:
    lea     rax, [rel undef_name]
    mov     [rdx + SYMBOL_name], rax
.ok:
    xor     eax, eax
.ret:
    pop     rbx
    ret
.bad:
    mov     rax, EXIT_DEFINE
    jmp     .ret

; ---- predefined macros ------------------
;
; prep_predefine
; NASM's standard single-line macros that hold a fixed value, defined
; before the source is read (__NASM_MAJOR__, __NASM_VER__, __DATE__ ...). The ones
; whose value changes -- __LINE__, __FILE__, __BITS__, __SECT__, __PASS__,
; __OUTPUT_FORMAT__ -- are defined too, empty, so %ifdef sees them; their
; value comes from prep_dynamic_macro wherever they are used.
; Input    : rdi = PrepState
;
global prep_predefine
prep_predefine:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    extern  time_init, time_local, time_utc, time_posix
    call    time_init                      ; __DATE__, __TIME__ ...
    lea     r13, [rel predef_table]
.next:
    mov     r12, [r13]
    test    r12, r12
    jz      .done
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     rax, [r13 + 16]
    mov     [rel def_scratch + TOKEN_kind], al
    mov     rdi, [r13 + 8]
    mov     [rel def_scratch + TOKEN_value], rdi
    xor     r15d, r15d
    test    eax, eax
    jz      .store                         ; empty
    mov     r15d, 1
    cmp     eax, TOK_STRING
    jne     .store
    call    str_len
    mov     [rel def_scratch + TOKEN_len], ax
    or      byte [rel def_scratch + TOKEN_flags], TOK_FLAG_COUNTED
.store:
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    call    prep_define_store
    add     r13, 24
    jmp     .next
.done:
    xor     eax, eax
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; prep_dynamic_macro
; __LINE__ (the line), __FILE__ (the file name), __BITS__ (16/32/64),
; __PASS__ (2: utasm reads the source once, as NASM's final pass),
; __OUTPUT_FORMAT__ (bin / elf64) and __SECT__ ([section NAME] for the
; section a plain "section" line last chose), also as __?LINE?__ etc.
; Input    : rbx = PrepState, r12 = an identifier token
; Output   : rax = EXIT_OK or error; rdx = 0 not one of them, 1 the token
;            now holds the value, 2 an expansion of its tokens started
;
prep_dynamic_macro:
    push    r13
    push    r14
    mov     r13, [r12 + TOKEN_value]
    lea     r14, [rel dyn_table]
.name:
    mov     rsi, [r14]
    test    rsi, rsi
    jz      .none
    mov     rdi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r14, 16
    jmp     .name
.none:
    xor     eax, eax
    xor     edx, edx
    jmp     .ret
.hit:
    mov     rax, [r14 + 8]
    cmp     eax, DYN_LINE
    je      .line
    cmp     eax, DYN_BITS
    je      .bits
    cmp     eax, DYN_PASS
    je      .pass
    cmp     eax, DYN_FILE
    je      .file
    cmp     eax, DYN_FORMAT
    je      .format
    jmp     .sect
.line:
    mov     eax, [r12 + TOKEN_line]
    jmp     .number
.bits:
    movzx   eax, byte [rel asm_bits]
    jmp     .number
.pass:
    mov     eax, 2
.number:
    mov     r13, rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 24
    call    arena_alloc                    ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .ret
    lea     rdi, [rdx + 22]
    mov     rax, r13
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    mov     [rdi], dl
    dec     rdi
    test    rax, rax
    jnz     .digit
    inc     rdi
    mov     [r12 + TOKEN_value], rdi
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    jmp     .as_token
.file:
    mov     rdi, [r12 + TOKEN_file]
    test    rdi, rdi
    jnz     .have_file
    lea     rdi, [rel dyn_no_file]
.have_file:
    mov     [r12 + TOKEN_value], rdi
    mov     byte [r12 + TOKEN_kind], TOK_STRING
    call    str_len
    mov     [r12 + TOKEN_len], ax
    or      byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jmp     .as_token
.format:
    lea     rax, [rel dyn_fmt_elf64]
    extern  elf32_enabled, coff_enabled
    cmp     byte [rel elf32_enabled], 0
    je      .format_coff
    lea     rax, [rel dyn_fmt_elf32]
.format_coff:
    cmp     byte [rel coff_enabled], 0
    je      .format_class
    lea     rax, [rel dyn_fmt_win64]
.format_class:
    mov     rcx, [rbx + PREP_ctx]
    cmp     byte [rcx + ASMCTX_fmt], FMT_BIN
    jne     .have_format
    lea     rax, [rel dyn_fmt_bin]
.have_format:
    mov     [r12 + TOKEN_value], rax
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
.as_token:
    xor     eax, eax
    mov     edx, 1
    jmp     .ret

    ; __SECT__: the four tokens [ section NAME ], expanded like a macro
.sect:
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 4 * TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    xor     ecx, ecx
.copy_tok:
    cmp     ecx, 4
    jae     .fill
    push    rcx
    imul    rdi, rcx, TOKEN_SIZE
    add     rdi, r14
    mov     rsi, r12                       ; line, column, file of the use
    copy_token
    pop     rcx
    imul    rax, rcx, TOKEN_SIZE
    mov     byte [r14 + rax + TOKEN_flags], 0
    mov     word [r14 + rax + TOKEN_len], 0
    inc     ecx
    jmp     .copy_tok
.fill:
    mov     byte [r14 + TOKEN_kind], TOK_LBRACKET
    mov     qword [r14 + TOKEN_value], 0
    mov     byte [r14 + TOKEN_SIZE + TOKEN_kind], TOK_IDENT
    lea     rax, [rel dyn_section_word]
    mov     [r14 + TOKEN_SIZE + TOKEN_value], rax
    mov     byte [r14 + 2 * TOKEN_SIZE + TOKEN_kind], TOK_IDENT
    mov     rax, [rel user_sect_name]
    mov     [r14 + 2 * TOKEN_SIZE + TOKEN_value], rax
    mov     byte [r14 + 3 * TOKEN_SIZE + TOKEN_kind], TOK_RBRACKET
    mov     qword [r14 + 3 * TOKEN_SIZE + TOKEN_value], 0
    mov     byte [r13 + MACRO_tag], TAG_MACRO
    lea     rax, [rel dyn_sect_name]
    mov     [r13 + MACRO_name], rax
    mov     dword [r13 + MACRO_ntokens], 4
    mov     [r13 + MACRO_tokens], r14
    mov     rdi, rbx
    mov     rsi, r13
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
    mov     edx, 2
.ret:
    pop     r14
    pop     r13
    ret

; ---- prep_icase_buf ---------------------
;
; prep_icase_buf
; The key a %idefine name is stored under: 0x01 followed by the name in
; lower case (no source text can spell it), written to icase_buf.
; Input    : rsi = name
; Output   : rax = 0, or 1 when the name is too long for the buffer
;
prep_icase_buf:
    lea     rdi, [rel icase_buf]
    mov     byte [rdi], 1
    inc     rdi
    xor     ecx, ecx
.copy:
    movzx   eax, byte [rsi + rcx]
    cmp     eax, 'A'
    jb      .put
    cmp     eax, 'Z'
    ja      .put
    or      eax, 0x20
.put:
    mov     [rdi + rcx], al
    test    eax, eax
    jz      .ok
    inc     ecx
    cmp     ecx, 250
    jb      .copy
    mov     eax, 1
    ret
.ok:
    xor     eax, eax
    ret

; ---- %ifidn family ----------------------
;
; %ifidn / %ifnidn compare their two operands as text, case-sensitively;
; %ifidni / %ifnidni ignore case. prep_read_idn_pair reads the pair
; (idn_case selects the comparison) and returns RDX = 1 when they match.
;
prep_handle_ifidn:
    mov     byte [rel idn_case], 1
    push    rbx
    mov     rbx, rdi
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_enter
.done:
    mov     byte [rel idn_case], 0
    pop     rbx
    ret

prep_handle_ifnidn:
    mov     byte [rel idn_case], 1
    jmp     prep_ifnidn_common
prep_handle_ifnidni:
    mov     byte [rel idn_case], 0
prep_ifnidn_common:
    push    rbx
    mov     rbx, rdi
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done
    xor     esi, esi
    test    rdx, rdx
    sete    sil                            ; the negation
    mov     rdi, rbx
    call    prep_cond_enter
.done:
    mov     byte [rel idn_case], 0
    pop     rbx
    ret

prep_handle_elifidn:
    mov     byte [rel idn_case], 1
    push    rbx
    mov     rbx, rdi
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_branch
.done:
    mov     byte [rel idn_case], 0
    pop     rbx
    ret

; ---- %warning / %error / %fatal ---------
;
; Print the rest of the line as a message on stderr, at the line it is on:
; "file:line: warning: ..." and go on (%warning), "file:line: error: ..."
; and go on but fail at the end (%error), or "file:line: fatal: ..." and
; stop (%fatal).
; Input    : rdi = PrepState, esi = 0 warning / 1 fatal / 2 error
;
prep_handle_message:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r13d, esi
    ; %error / %fatal in a run whose "$ - $$" the layout is still to give
    ; (src/core/known.s): the next run, which has it, says whether they hold
    cmp     r13d, 1
    jb      .reported
    extern  known_tentative, known_defer_error
    cmp     byte [rel known_tentative], 0
    je      .reported
    mov     edi, EXIT_FATAL                ; (if there is no next run after all)
    call    known_defer_error
.skip:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .skipped
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .skipped
    cmp     eax, TOK_EOF
    je      .skipped
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .skip
.skipped:
    xor     eax, eax
    jmp     .ret
.reported:
    mov     edi, 2                         ; severity: fatal
    cmp     r13d, 1
    je      .head
    mov     edi, 1                         ; error
    ja      .head
    ; %warning: a warning of class "user" ([-w+user], -w-user, the listing)
    mov     edi, WC_USER
    extern  warn_begin, warn_text, warn_end
    call    warn_begin
    jmp     .words
.head:
    extern  error_report_text
    call    error_report_text
.words:
    xor     r12d, r12d                     ; words printed
.word:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .end
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .end
    cmp     eax, TOK_EOF
    je      .end
    mov     rdi, rbx
    call    preprocessor_next_token
    ; every token as written ("a,b" too), a blank where the source had
    ; one, as NASM gives the line
    test    r12d, r12d
    jz      .placed
    test    byte [rdx + TOKEN_flags], TOK_FLAG_SPACE
    jz      .placed                        ; right after it in the source
.blank:
    push    rdx
    push    rcx
    push    r8
    push    r9
    lea     rsi, [rel msg_space]
    call    .out
    pop     r9
    pop     r8
    pop     rcx
    pop     rdx
.placed:
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .text
    cmp     eax, TOK_CHAR
    je      .text
    call    prep_idn_text                  ; names, numbers, punctuation
    jmp     .put
.text:
    call    prep_token_text
    test    rax, rax
    jz      .word
.put:
    mov     rsi, rax
    call    .out
    inc     r12d
    jmp     .word
.end:
    test    r13d, r13d
    jnz     .end_report
    call    warn_end
    jmp     .ended
.end_report:
    extern  error_report_end
    call    error_report_end
.ended:
    xor     eax, eax
    cmp     r13d, 1
    jb      .ret
    ja      .counted
    mov     rax, EXIT_FATAL                ; %fatal stops the assembly
    jmp     .ret
.counted:
    extern  error_deferred
    inc     dword [rel error_deferred]     ; %error fails the assembly later
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; a space before every word but the first
.space:
    test    r12d, r12d
    jz      .space_done
    lea     rsi, [rel msg_space]
    call    .out
.space_done:
    ret

; .out: the text at rsi: into the warning (%warning), or on stderr
.out:
    test    r13d, r13d
    jz      warn_text
    mov     rdi, 2
    jmp     print_str

; ---- %exitrep ---------------------------
;
; Leave the innermost %rep: this pass is its last, and the rest of its body
; is skipped. The %if blocks the rest of the body would have closed are
; closed now, so the conditional stack stays balanced.
; Input    : rdi = PrepState
;
prep_handle_exitrep:
    xor     esi, esi
    jmp     prep_handle_exit

;
; prep_handle_exit
; %exitrep (esi = 0) leaves the innermost %rep, %exitmacro (esi = 1) the
; innermost multi-line macro: every expansion from the innermost one up to
; that one ends after this line. The %if blocks the rest of their bodies
; would have closed are closed now, so the conditional stack stays
; balanced.
; Input    : rdi = PrepState, esi = 0 / 1
;
prep_handle_exit:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r15d, esi
    mov     rdi, rbx
    call    prep_drain_line                ; the line ends before the skip
    mov     rax, [rbx + PREP_ctx]
    mov     r12, [rax + ASMCTX_mac_exp]
    mov     r13, r12
.find:
    test    r13, r13
    jz      .none
    mov     rax, [r13 + MACROEXP_macro]
    test    r15d, r15d
    jnz     .want_macro
    cmp     qword [rax + MACRO_name], 0    ; a %rep body is an anonymous macro
    je      .found
    jmp     .up
.want_macro:
    cmp     qword [rax + MACRO_name], 0
    je      .up
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .found
.up:
    mov     r13, [r13 + MACROEXP_parent]
    jmp     .find
.found:
    mov     byte [rel exit_open], 0
.each:
    ; count the %endif lines left in this body without their %if
    mov     rcx, [r12 + MACROEXP_body]
    xor     r14d, r14d                     ; open %ifs met in the rest
.scan:
    mov     rax, [r12 + MACROEXP_macro]
    cmp     ecx, [rax + MACRO_ntokens]
    jae     .scanned
    mov     rdx, rcx
    imul    rdx, rdx, TOKEN_SIZE
    add     rdx, [rax + MACRO_tokens]
    inc     rcx
    ; %exitrep: NASM lists the rest of the body (nothing assembled)
    test    r15d, r15d
    jnz     .unlisted
    extern  lst_enabled
    cmp     byte [rel lst_enabled], 0
    je      .unlisted
    mov     rdi, rdx
    mov     rsi, r12
    call    error_track_token              ; (preserves every register)
.unlisted:
    cmp     byte [rdx + TOKEN_kind], TOK_DIRECTIVE
    jne     .scan
    mov     rdi, [rdx + TOKEN_value]
    test    rdi, rdi
    jz      .scan
    cmp     byte [rdi], 'i'
    jne     .not_if
    cmp     byte [rdi + 1], 'f'
    jne     .not_if
    inc     r14d                           ; %if, %ifdef, %ifidn, ...
    jmp     .scan
.not_if:
    push    rcx
    lea     rsi, [rel dir_endif]
    call    str_cmp
    pop     rcx
    test    rax, rax
    jnz     .scan
    test    r14d, r14d
    jz      .unmatched
    dec     r14d
    jmp     .scan
.unmatched:
    inc     byte [rel exit_open]
    jmp     .scan
.scanned:
    mov     dword [r12 + MACROEXP_rep_count], 1
    mov     rax, [r12 + MACROEXP_macro]
    mov     eax, [rax + MACRO_ntokens]
    mov     [r12 + MACROEXP_body], rax
    cmp     r12, r13
    je      .close
    mov     r12, [r12 + MACROEXP_parent]
    jmp     .each
.close:
    movzx   r14d, byte [rel exit_open]
.close_one:
    test    r14d, r14d
    jz      .ok
    mov     rdi, rbx
    call    prep_handle_endif
    dec     r14d
    jmp     .close_one
.ok:
    xor     eax, eax
    jmp     .ret
.none:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_builtin_macro -------------------
;
; prep_builtin_macro
; Is rsi one of NASM's own multi-line macros (builtin_macros), in this
; output format? As written: "%ifmacro ORG" is false in NASM too.
; Input    : rdi = PrepState, rsi = the name
; Output   : eax = 1, ecx = its least count, edx = its most (MACRO_VARIADIC:
;            any); or eax = 0
; Clobbers : r8-r10
;
prep_builtin_macro:
    push    rbx
    lea     r8, [rel builtin_macros]
    ; the format: 1 bin, 2 ELF, 3 COFF
    mov     rax, [rdi + PREP_ctx]
    mov     r10d, 1
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    je      .entry
    extern  coff_enabled
    mov     r10d, 3
    cmp     byte [rel coff_enabled], 0
    jne     .entry
    mov     r10d, 2
.entry:
    cmp     byte [r8], 0
    je      .none
    xor     ecx, ecx
.char:
    movzx   eax, byte [rsi + rcx]
    movzx   ebx, byte [r8 + rcx]
    cmp     eax, ebx
    jne     .skip
    inc     ecx
    test    eax, eax
    jnz     .char
    ; the name: its counts and formats after the NUL
    lea     r9, [r8 + rcx]
    movzx   eax, byte [r9 + 2]
    test    eax, eax
    jz      .found
    cmp     eax, r10d
    jne     .none                          ; (another format's)
.found:
    movzx   ecx, byte [r9]
    movzx   edx, byte [r9 + 1]
    cmp     edx, 0xFF
    jne     .counted
    mov     edx, MACRO_VARIADIC
.counted:
    mov     eax, 1
    pop     rbx
    ret
.skip:
    ; to the next entry: past the name's NUL and its three bytes
.skip_name:
    cmp     byte [r8], 0
    je      .skipped
    inc     r8
    jmp     .skip_name
.skipped:
    add     r8, 4
    jmp     .entry
.none:
    xor     eax, eax
    pop     rbx
    ret
