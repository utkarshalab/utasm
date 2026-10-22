; ============================================================================
; File        : src/frontend/preproc/macro/tokens.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : prep_internal_next: the token loop (expansion, directives, single-line macros), the input buffers
; ============================================================================




; ---- prep_internal_next -----------------
prep_internal_next:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token dest

.next:
    ; 1. Check if we are expanding a macro
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .from_lexer

    ; Get token from expansion body
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_expand_next
    test    rax, rax
    jz      .from_body             ; produced a token: process it like any other
    ; if expansion finished, try again (checks for parent or falls to lexer)
    jmp     .next

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; lexer error

    ; handle EOF
    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .handle_eof

    ; where the statement comes from, for error messages
    mov     rdi, r12
    xor     esi, esi
    call    error_track_token
    ; "P %+ cd" in the source itself (in a body, prep_expand_next joins)
    call    prep_file_paste
    test    rax, rax
    jnz     .done
    jmp     .check_token

.from_body:
    mov     rdi, r12
    mov     rsi, [rbx + PREP_ctx]
    mov     rsi, [rsi + ASMCTX_mac_exp]
    call    error_track_token

.check_token:
    ; Tokens from a macro or %rep body get the same treatment as file tokens:
    ; conditional skipping, nested macro calls and % directives all apply.

    ; Resolve any %[NAME] in the token text first: the same body token can be
    ; replayed with different symbol values on each %rep iteration.
    test    byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
    jz      .no_interp
    ; "%[...]" standing alone (the lexer makes it a TOK_NUMBER): the tokens
    ; inside, expanded now ("%[X]*2", X a %define of 2+3, is 2+3*2)
    cmp     byte [r12 + TOKEN_kind], TOK_NUMBER
    jne     .interp_text
    mov     rsi, r12
    call    prep_interp_standalone
    test    rax, rax
    jnz     .done
    test    edx, edx
    jnz     .next                          ; it was nothing ("%[EMPTY]")
    jmp     .no_interp
.interp_text:
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_resolve_interp
    test    rax, rax
    jnz     .done
    ; pasted text NASM's scanner reads as more than one token: "%1e+%2"
    ; with 1, 36 is the float 1e+36, "%1%2" with xyzzy, 1e+10 is xyzzy1e
    ; + 10 - read again, as %[...] is
    mov     rsi, [r12 + TOKEN_value]
    call    prep_text_splits
    test    eax, eax
    jz      .no_interp
    mov     rsi, [r12 + TOKEN_value]
    call    prep_bracket_text
    test    rax, rax
    jnz     .done
    mov     [r12 + TOKEN_value], rdx
    mov     rsi, r12
    call    prep_interp_standalone
    test    rax, rax
    jnz     .done
    test    edx, edx
    jnz     .next
.no_interp:

    ; check if skipping
    cmp     word [rbx + PREP_skip_depth], 0
    je      .not_skipping

    ; we are skipping. only care about % directives (a lone TOK_PERCENT is
    ; the modulo operator: the lexer makes directives TOK_DIRECTIVE)
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .next                  ; consume everything else

    ; handle directive even when skipping
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_handle_directive
    mov     rdi, rbx
    call    prep_drop_stale_newline
    jmp     .next

.not_skipping:
    ; check if it's a macro call (not while a directive reads a name: a
    ; %define being redefined must not expand its old body)
    cmp     byte [rel prep_noexpand], 0
    jne     .not_macro_call
    ; "foo:" with "%define foo bar": the label bar, as NASM expands it
    cmp     byte [r12 + TOKEN_kind], TOK_LABEL
    jne     .not_label_define
    call    prep_label_define
    cmp     rax, 1
    je      .next
    test    rax, rax
    jnz     .done
    jmp     .not_macro_call
.not_label_define:
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_macro_call
    
    ; __LINE__, __FILE__, __BITS__, __SECT__ ...: the value of the moment
    mov     rsi, [r12 + TOKEN_value]
    cmp     word [rsi], '__'
    jne     .not_dynamic
    call    prep_dynamic_macro
    test    rax, rax
    jnz     .done
    cmp     edx, 1
    je      .not_macro_call        ; the token itself holds the value
    cmp     edx, 2
    je      .next                  ; its tokens follow
.not_dynamic:

    ; look up in symtab
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .try_icase             ; not found or error

    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .macro_found
    ; an %assign (%strlen, %substr's numbers ...) is a macro of its value,
    ; as in NASM: the number in its place, so %defstr, %ifidn and -E see
    ; it ("%assign b1 1" / "%defstr s b1" is '1')
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .not_macro_call
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .not_macro_call
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [rel assign_num]
    call    str_int_to_str
    lea     rdi, [rel assign_num]
    call    str_len
    mov     rdx, rax
    mov     word [r12 + TOKEN_len], ax
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rel assign_num]
    call    arena_alloc_string
    test    rax, rax
    jnz     .done
    mov     [r12 + TOKEN_value], rdx
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    xor     eax, eax
    jmp     .not_macro_call

    ; a %idefine matches in any case (only looked for once one exists)
.try_icase:
    cmp     dword [rel idefine_count], 0
    je      .not_macro_call
    mov     rsi, [r12 + TOKEN_value]
    call    prep_icase_buf
    test    rax, rax
    jnz     .not_macro_call
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel icase_buf]
    call    prep_symbol_find
    test    rax, rax
    jnz     .not_macro_call
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_macro_call

.macro_found:
    ; Found a macro call! A multi-line macro is called only as the first
    ; word of a line or after "label:", as in NASM - "db 1, m" is the
    ; symbol m. (NASM also tries the second word after a label with no
    ; colon, when its parameters fit; "db m" in a body would then call m.)
    ; A %define expands anywhere.
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .ml_word
    ; a %define is not expanded inside its own expansion ("%define foo
    ; foo", "a" -> b -> a, "f(f(1))" is f(1)+1): the name stays, as in NASM
    ; (it was "macros nested too deeply"). The expansions around the token,
    ; out to the first that is no %define
    mov     rcx, [rbx + PREP_ctx]
    mov     rcx, [rcx + ASMCTX_mac_exp]
.painted:
    test    rcx, rcx
    jz      .not_painted
    mov     r8, [rcx + MACROEXP_macro]
    mov     r9, [r8 + MACRO_name]
    cmp     r9, [rax + MACRO_name]         ; (a label's copy: prep_label_define)
    je      .not_macro_call
    test    byte [r8 + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .not_painted
    mov     rcx, [rcx + MACROEXP_parent]
    jmp     .painted
.not_painted:
    ; "%define f(x)": f with no "(" after it is the name f, as in NASM
    ; ("bar equ 8" after "%define bar(x)")
    test    byte [rax + MACRO_flags], MACRO_FLAG_FUNC
    jz      .call_macro
    push    rdx
    sub     rsp, TOKEN_SIZE
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    movzx   ecx, byte [rsp + TOKEN_kind]
    add     rsp, TOKEN_SIZE
    pop     rdx
    test    rax, rax
    jnz     .not_macro_call
    cmp     ecx, TOK_LPAREN
    je      .call_macro
    jmp     .not_macro_call
.ml_word:
    cmp     byte [rel ml_state], ML_START
    je      .ml_call
    cmp     byte [rel ml_state], ML_COLON
    jne     .not_macro_call
.ml_call:
    ; a %macro inside its own expansion is no call (only %rmacro's is),
    ; as NASM: the line is read as written ("f" a label) - it recursed to
    ; the depth limit
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_RECURSIVE
    jnz     .ml_may_call
    mov     rcx, [rbx + PREP_ctx]
    mov     rcx, [rcx + ASMCTX_mac_exp]
.ml_in_own:
    test    rcx, rcx
    jz      .ml_may_call
    mov     r8, [rcx + MACROEXP_macro]
    mov     r9, [r8 + MACRO_name]
    test    r9, r9
    jz      .ml_outer
    push    rcx
    push    rdx
    mov     rdi, r9
    mov     rsi, [rax + MACRO_name]
    call    str_cmp
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .not_macro_call
    mov     rax, [rdx + SYMBOL_value]
.ml_outer:
    mov     rcx, [rcx + MACROEXP_parent]
    jmp     .ml_in_own
.ml_may_call:
    ; the line it is called on: a .nolist one's lines are on it (-E)
    mov     eax, [r12 + TOKEN_line]
    mov     [rel exp_call_line], eax
    mov     rax, [r12 + TOKEN_file]
    mov     [rel exp_call_file], rax
    ; its arguments call no multi-line macro; its body is lines of its own
    movzx   eax, byte [rel ml_state]
    mov     [rel ml_called_at], al
    mov     byte [rel ml_state], ML_NONE
    mov     rdi, rbx
    mov     rsi, [rdx + SYMBOL_value] ; rsi = pointer to MACRO struct
    call    prep_expand_start
    mov     byte [rel ml_state], ML_START
    test    rax, rax
    jnz     .done                  ; error starting expansion
    ; "lab: m": the listing shows "lab: " as the expansion's first line
    cmp     byte [rel ml_called_at], ML_COLON
    jne     .next
    extern  lst_enabled
    cmp     byte [rel lst_enabled], 0
    je      .next
    call    prep_list_label
    jmp     .next                  ; get first token of expansion
.call_macro:
    ; a blank before the name is one before what it stands for; it stands
    ; on the name's line (-E)
    movzx   eax, byte [r12 + TOKEN_flags]
    and     eax, TOK_FLAG_SPACE
    or      eax, 0x80
    mov     [rel exp_lead], al
    mov     eax, [r12 + TOKEN_line]
    mov     [rel exp_call_line], eax
    mov     rax, [r12 + TOKEN_file]
    mov     [rel exp_call_file], rax
    mov     rdi, rbx
    mov     rsi, [rdx + SYMBOL_value] ; rsi = pointer to MACRO struct
    call    prep_expand_start
    test    rax, rax
    jnz     .done                  ; error starting expansion
    jmp     .next                  ; get first token of expansion

.not_macro_call:
    ; a first word with a multi-line macro after it ("f proc", "lab: m",
    ; even "push m"): a label, as NASM reads it, which the macro takes as
    ; %00 when its body has one (and defines itself), else defined here
    cmp     byte [rel ml_state], ML_START
    jne     .ml_plain
    cmp     byte [rel prep_noexpand], 0
    jne     .ml_plain
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .ml_plain
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_LABEL
    je      .ml_first
    cmp     eax, TOK_IDENT
    jne     .ml_plain
    mov     rax, [r12 + TOKEN_value]
    test    rax, rax
    jz      .ml_plain
    cmp     byte [rax], '.'
    jne     .ml_first
    cmp     word [rax + 1], '.@'           ; "%$x m": its ..@N.x, a label too
    jne     .ml_plain
.ml_first:
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_label_macro               ; eax: 0 no, 1 a label, 2 %00's
    test    eax, eax
    jz      .ml_plain
    mov     rcx, [r12 + TOKEN_value]
    mov     [rel ml_label], rcx
    mov     byte [rel ml_state], ML_COLON
    cmp     eax, 2
    je      .next                          ; the macro takes it
    ; (listed "lab2 :" when written with no colon, as NASM lists it)
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    sete    byte [rel ml_nocolon]
    mov     byte [r12 + TOKEN_kind], TOK_LABEL
    xor     eax, eax
    jmp     .done
.ml_plain:
    ; where the next token stands in its line (ml_state)
    movzx   eax, byte [r12 + TOKEN_kind]
    mov     cl, ML_NONE
    cmp     eax, TOK_NEWLINE
    je      .ml_start
    cmp     eax, TOK_EOF
    je      .ml_start
    cmp     eax, TOK_IDENT
    je      .ml_ident
    cmp     eax, TOK_COLON
    je      .ml_colon
    cmp     eax, TOK_LABEL
    je      .ml_label
    cmp     eax, TOK_LOCAL_LABEL
    je      .ml_label
    jmp     .ml_set
.ml_start:
    mov     cl, ML_START
    jmp     .ml_set
.ml_ident:
    cmp     byte [rel ml_state], ML_START
    jne     .ml_set
    mov     cl, ML_LABEL                   ; perhaps a label
    mov     rax, [r12 + TOKEN_value]
    mov     [rel ml_label], rax
    jmp     .ml_set
.ml_colon:
    cmp     byte [rel ml_state], ML_LABEL
    jne     .ml_set
    mov     cl, ML_COLON
    jmp     .ml_set
.ml_label:
    cmp     byte [rel ml_state], ML_START
    jne     .ml_set
    mov     cl, ML_COLON
    mov     rax, [r12 + TOKEN_value]
    mov     [rel ml_label], rax
.ml_set:
    mov     [rel ml_state], cl
    xor     rax, rax
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    je      .is_directive
    jmp     .done                  ; normal token

.is_directive:
    ; "%eval(...)" and NASM 2.16's other functions: the result in its place
    mov     rsi, r12
    call    prep_function
    test    rax, rax
    jnz     .done
    cmp     edx, 1
    je      .check_token                   ; r12: the result's first token
    cmp     edx, 2
    je      .next                          ; it gave nothing
    cmp     edx, 3
    je      .done                          ; a call kept as written
    ; "%rbp": GAS's spelling of a register (".cfi_offset %rbp, -16"), no
    ; directive - the register
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_target], TARGET_AMD64
    jne     .not_gas_reg
    mov     rsi, [r12 + TOKEN_value]
    test    rsi, rsi
    jz      .not_gas_reg
    extern  parser_is_register, amd64_register_table
    lea     rdi, [rel amd64_register_table]
    call    parser_is_register
    cmp     rax, ERR
    je      .not_gas_reg
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    xor     eax, eax
    jmp     .done
.not_gas_reg:
    ; "%?" / "%??" outside a macro body - "label(%??, _1)": an argument of
    ; a single-line macro, whose name they become in its body (CASE 0)
    mov     rax, [r12 + TOKEN_value]
    test    rax, rax
    jz      .not_qq
    cmp     byte [rax], '?'
    jne     .not_qq
    cmp     byte [rax + 1], 0
    je      .qq_token
    cmp     byte [rax + 1], '?'
    jne     .not_qq
    cmp     byte [rax + 2], 0
    jne     .not_qq
.qq_token:
    xor     eax, eax
    jmp     .done
.not_qq:
    ; a %define's body being read: its directives are its text, not run
    ; now ("%define IFNDEF %ifndef" ran %ifndef there)
    cmp     byte [rel def_capturing], 0
    je      .not_capturing
    xor     eax, eax
    jmp     .done
.not_capturing:
    ; a %define's body gives no directive: "%define IFNDEF %ifndef" /
    ; "IFNDEF foo" is NASM's "label or instruction expected", the line
    ; dropped (br3200749)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .directive
    mov     rax, [rax + MACROEXP_macro]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .directive
    lea     rsi, [rel s_not_instruction]
    call    prep_error_line
    lea     rsi, [rel s_empty_text]
    call    prep_error_more
.drop_line:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .next
    cmp     eax, TOK_EOF
    je      .next
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .drop_line
.directive:
    ; it's a directive. handle it.
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_handle_directive
    test    rax, rax
    jnz     .done                  ; error handling directive

    ; A directive owns its whole line. Its operand reader stops on the
    ; terminating NEWLINE and leaves it in the peek slot, but .next reads
    ; straight from the lexer and would never consume it, so the next macro
    ; call would collect that newline as its first argument token.
    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; if the directive didn't produce a token, get next
    jmp     .next

.handle_eof:
    ; check if we have a parent include context
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    test    r9, r9
    jz      .done                  ; real EOF (main file)

    ; 1. Unmap the current file buffer
    mov     rdi, [r9 + INCLUDECTX_buf]
    mov     rsi, [r9 + INCLUDECTX_size]
    extern  io_munmap
    call    io_munmap
    
    ; 2. Restore previous lexer (reloading volatile r8 and r9 from callee-saved rbx)
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    mov     r10, [r9 + INCLUDECTX_lexer]
    mov     [rbx + PREP_lexer], r10
    
    ; 3. Pop include context, and go on with the body it came from
    mov     r11, [r9 + INCLUDECTX_parent]
    mov     [r8 + ASMCTX_inc_ctx], r11
    mov     r11, [r9 + INCLUDECTX_mac_exp]
    mov     [r8 + ASMCTX_mac_exp], r11
    
    ; 4. Try getting next token from parent
    jmp     .next

.done:
    pop     r12
    pop     rbx
    epilogue
    ret

DUMP_BUF equ 16384

; ---- prep_dump --------------------------
;
; prep_dump
; Runs the preprocessor over the rest of the source and writes what it
; produces as text (-E), as NASM does: macros expanded, conditionals
; resolved, includes read, one output line per line. A directive's line is
; not written; a line of nothing but blanks or a comment is, empty. A
; blank goes where the source had blanks. "%line N+step file" goes before
; a line that is not the one after the last (an empty line instead when
; one line was left out; step 0 while a macro's lines come again), so what
; reads it back reports the source's lines. Strings are written back in
; quotes that read back to the same bytes. With fd -1 nothing is written
; (-M only needs the includes read).
; Input    : rdi = PrepState, esi = fd, or -1
; Output   : rax = EXIT_OK or the preprocessor's error
;
global prep_dump
prep_dump:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12d, esi
    xor     r13d, r13d                     ; 1: the line has a token already
    extern  lexer_mark_lone
    mov     byte [rel lexer_mark_lone], 1
    mov     qword [rel dump_file], 0
    mov     dword [rel dump_linnum], 0
    mov     dword [rel dump_lineinc], 0
    mov     dword [rel dump_fill], 0
    mov     byte [rel dump_eof], 0
    mov     byte [rel dump_close], 0
    mov     byte [rel dump_after_word], 0
.token:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    cmp     dword [rel pragma_qlen], 0
    je      .no_pragma
    call    .pragma_out
.no_pragma:
    movzx   eax, byte [r14 + TOKEN_kind]
    cmp     eax, TOK_EOF
    jne     .not_eof
    mov     byte [rel dump_eof], 1         ; a last line with no newline
    jmp     .newline                       ; ends as the others
.not_eof:
    cmp     eax, TOK_NEWLINE
    jne     .text
.newline:
    test    r13d, r13d
    jnz     .line_end
    ; nothing on the line: written when the source's was empty
    test    byte [r14 + TOKEN_flags], TOK_FLAG_LONE
    jz      .line_done
    mov     ecx, 1
    call    .where
    jc      .line_done
.line_end:
    cmp     byte [rel dump_close], 0
    je      .closed
    mov     byte [rel dump_close], 0
    lea     rsi, [rel dump_shut]
    mov     edx, 1
    call    .write
.closed:
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
    xor     r13d, r13d
.line_done:
    cmp     byte [rel dump_eof], 0
    jne     .ok
    jmp     .token

.text:
    test    r13d, r13d
    jnz     .placed_line
    xor     ecx, ecx
    call    .where
    mov     r13d, 1
    ; a directive NASM makes a macro of is written as what it gives:
    ; "bits 64" is "[bits 64]", "use32" "[bits 32]", "extern a, b" is
    ; "[extern a]" and "[extern b]" (dump_dir_words)
    cmp     byte [r14 + TOKEN_kind], TOK_IDENT
    jne     .placed_line
    call    .directive_word
    test    eax, eax
    jz      .placed_line
    mov     [rel dump_close], al
    mov     [rel dump_word], rsi
    call    .open_word
    jmp     .token
.placed_line:
    cmp     byte [rel dump_close], 2
    jne     .not_split
    cmp     byte [r14 + TOKEN_kind], TOK_COMMA
    jne     .not_split
    lea     rsi, [rel dump_shut]           ; a name done: the next on a
    mov     edx, 1                         ; line of its own, as NASM's
    call    .write                         ; %rep writes them
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
    xor     ecx, ecx
    call    .where
    call    .open_word
    jmp     .token
.not_split:
    cmp     byte [rel dump_after_word], 0
    je      .own_blank
    mov     byte [rel dump_after_word], 0
    jmp     .blank_now                     ; "[bits" and one blank
.own_blank:
    test    byte [r14 + TOKEN_flags], TOK_FLAG_SPACE
    jz      .first
.blank_now:
    lea     rsi, [rel dump_blank]
    mov     edx, 1
    call    .write
.first:
    movzx   eax, byte [r14 + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .string
    cmp     eax, TOK_CHAR
    je      .char
    cmp     eax, TOK_IDENT
    jne     .as_text
    ; a name %assign (or %strlen ...) gave a value: that value, as NASM
    ; writes it ("%assign v 5" / "db v" is "db 5")
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r14 + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .as_text
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .as_text
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .as_text
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [rel dump_num]
    test    rsi, rsi
    jns     .num_digits
    mov     byte [rdi], '-'
    inc     rdi
    neg     rsi
.num_digits:
    mov     edx, 10
    call    int_to_str
    lea     rsi, [rel dump_num]
    call    .write_str
    jmp     .token
.as_text:
    mov     rdx, r14
    call    prep_idn_text
    mov     rsi, rax
    call    .write_str
    cmp     byte [r14 + TOKEN_kind], TOK_LABEL
    je      .colon
    cmp     byte [r14 + TOKEN_kind], TOK_LOCAL_LABEL
    jne     .token
.colon:
    lea     rsi, [rel dump_colon]          ; "name:" comes as one token
    mov     edx, 1
    call    .write
    jmp     .token

.char:
    ; 'ab': the bytes of the constant, in single quotes
    mov     rdx, r14
    call    prep_token_text
    test    rax, rax
    jz      .token
    mov     r15, rax
    movzx   ecx, word [r14 + TOKEN_len]
    mov     rsi, r15
    mov     edx, ecx
    mov     r8d, 39                        ; '
    call    .quoted
    jmp     .token

.string:
    mov     r15, [r14 + TOKEN_value]
    movzx   ecx, word [r14 + TOKEN_len]
    test    byte [r14 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .string_len
    mov     rdi, r15
    call    str_len
    mov     ecx, eax
.string_len:
    movzx   r9d, byte [r14 + TOKEN_quote]
    call    .requote
    jmp     .token

; .requote: r15 = bytes, ecx = count, r9d = the quote the source wrote
; them in, or 0. In that quote when it reads back the same bytes, else as
; NASM's nasm_quote: '...', else "...", else `...` with escapes
.requote:
    cmp     r9d, '`'
    je      .backquote
    mov     r8d, 1                         ; '...' can hold them
    mov     r10d, 1                        ; "..." can
    xor     edx, edx
.scan:
    cmp     edx, ecx
    jae     .scanned
    movzx   eax, byte [r15 + rdx]
    inc     edx
    cmp     eax, 39
    jne     .not_sq
    xor     r8d, r8d
.not_sq:
    cmp     eax, '"'
    jne     .not_dq
    xor     r10d, r10d
.not_dq:
    cmp     eax, ' '
    jb      .unprintable
    cmp     eax, '~'
    jbe     .scan
.unprintable:
    xor     r8d, r8d
    xor     r10d, r10d
    jmp     .scan
.scanned:
    cmp     r9d, '"'
    jne     .pick
    test    r10d, r10d
    jnz     .in_dq
.pick:
    test    r8d, r8d
    jnz     .in_sq
    test    r10d, r10d
    jz      .backquote
.in_dq:
    mov     r8d, '"'
    jmp     .plain
.in_sq:
    mov     r8d, 39
.plain:
    mov     rsi, r15
    mov     edx, ecx
    jmp     .quoted
.backquote:
    push    rcx
    lea     rsi, [rel dump_bq]
    mov     edx, 1
    call    .write
    pop     rcx
    xor     edx, edx
.bq_byte:
    cmp     edx, ecx
    jae     .bq_end
    movzx   eax, byte [r15 + rdx]
    inc     edx
    push    rcx
    push    rdx
    lea     rdi, [rel dump_hex]
    mov     byte [rdi], 92                 ; backslash
    cmp     eax, '`'
    je      .bq_escaped
    cmp     eax, 92
    je      .bq_escaped
    cmp     eax, 27
    je      .bq_esc_e
    lea     r8d, [rax - 7]
    cmp     r8d, 6
    ja      .bq_other
    lea     r10, [rel dump_named]          ; \a \b \t \n \v \f \r
    movzx   eax, byte [r10 + r8]
    jmp     .bq_escaped
.bq_esc_e:
    mov     eax, 'e'
.bq_escaped:
    mov     [rdi + 1], al
    mov     edx, 2
    jmp     .bq_put
.bq_other:
    cmp     eax, ' '
    jb      .bq_octal
    cmp     eax, '~'
    ja      .bq_octal
    mov     [rdi], al
    mov     edx, 1
    jmp     .bq_put
.bq_octal:
    ; the fewest octal digits, all three when a digit 0-7 comes next
    mov     r9d, eax
    cmp     edx, ecx
    jae     .oct_digits
    movzx   r10d, byte [r15 + rdx]
    sub     r10d, '0'
    cmp     r10d, 7
    ja      .oct_digits
    mov     r9d, 0xFF
.oct_digits:
    lea     rsi, [rdi + 1]
    cmp     r9d, 63
    jbe     .oct_two
    mov     r10d, eax
    shr     r10d, 6
    add     r10d, '0'
    mov     [rsi], r10b
    inc     rsi
.oct_two:
    cmp     r9d, 7
    jbe     .oct_one
    mov     r10d, eax
    shr     r10d, 3
    and     r10d, 7
    add     r10d, '0'
    mov     [rsi], r10b
    inc     rsi
.oct_one:
    and     eax, 7
    add     eax, '0'
    mov     [rsi], al
    inc     rsi
    mov     rdx, rsi
    sub     rdx, rdi
.bq_put:
    lea     rsi, [rel dump_hex]
    call    .write
    pop     rdx
    pop     rcx
    jmp     .bq_byte
.bq_end:
    lea     rsi, [rel dump_bq]
    mov     edx, 1
    jmp     .write

.ok:
    xor     eax, eax
.ret:
    push    rax
    call    .flush
    pop     rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .directive_word: r14's name in dump_dir_words (any letter case): eax =
; its kind there, rsi = what follows "[" (its name, or what it stands
; for); eax = 0 when it is none of them
.directive_word:
    mov     rdi, [r14 + TOKEN_value]
    test    rdi, rdi
    jz      .word_none
    lea     rsi, [rel dump_dir_words]
.word_next:
    movzx   r8d, byte [rsi]
    test    r8d, r8d
    jz      .word_none
    inc     rsi
    call    str_cmp_kw
    test    eax, eax
    jz      .word_found
    call    .past_nul
    cmp     r8d, 3
    jne     .word_next
    call    .past_nul                      ; (and what it stands for)
    jmp     .word_next
.word_found:
    mov     eax, r8d
    cmp     eax, 3
    jne     .word_ret
    call    .past_nul
.word_ret:
    ret
.word_none:
    xor     eax, eax
    ret
.past_nul:
    inc     rsi
    cmp     byte [rsi - 1], 0
    jne     .past_nul
    ret

; .pragma_out: the %pragmas the preprocessor read (pragma_queue), as NASM
; writes them: "[pragma ...]", each a line of its own
.pragma_out:
    push    r14
    lea     rax, [rel pragma_queue]
    mov     [rel pragma_entry], rax        ; (the one being written)
.pragma_next:
    mov     eax, [rel pragma_qlen]
    lea     rcx, [rel pragma_queue]
    add     rcx, rax
    mov     rax, [rel pragma_entry]
    cmp     rax, rcx
    jae     .pragmas_out
    lea     r14, [rel pragma_where]
    mov     rcx, [rax]
    mov     [r14 + TOKEN_file], rcx
    mov     ecx, [rax + 8]
    mov     [r14 + TOKEN_line], ecx
    xor     ecx, ecx
    call    .where
    lea     rsi, [rel dump_pragma]
    call    .write_str
    mov     rsi, [rel pragma_entry]
    add     rsi, 12
    call    .write_str
    lea     rsi, [rel dump_shut]
    mov     edx, 1
    call    .write
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
    mov     rdi, [rel pragma_entry]
    add     rdi, 12
    call    str_len
    lea     rax, [rax + 12 + 1]
    add     [rel pragma_entry], rax
    jmp     .pragma_next
.pragmas_out:
    mov     dword [rel pragma_qlen], 0
    pop     r14
    ret

; .open_word: "[" and dump_word; the token after it gets one blank
.open_word:
    lea     rsi, [rel dump_open]
    mov     edx, 1
    call    .write
    mov     rsi, [rel dump_word]
    call    .write_str
    mov     byte [rel dump_after_word], 1
    ret

; .where: a line starts, on r14's token's; ecx = 1 when it is empty.
; NASM's -E: the empty line or "%line" that puts it at its place. CF = 1:
; leave the empty line out (a "%line" comes before the next anyway)
.where:
    push    rcx
    mov     edx, [r14 + TOKEN_line]
    mov     rsi, [r14 + TOKEN_file]
    ; text utasm read in (a %use package): on the line that read it
    mov     ecx, [rel push_count]
    lea     r8, [rel push_where]
.unpushed:
    test    ecx, ecx
    jz      .pushed_done
    cmp     rsi, [r8]
    jne     .pushed_next
    mov     rsi, [r8 + 8]
    mov     edx, [r8 + 16]
    jmp     .pushed_done
.pushed_next:
    add     r8, 24
    dec     ecx
    jmp     .unpushed
.pushed_done:
    mov     [rel dump_at], edx
    mov     rdi, [rel dump_file]
    cmp     rsi, rdi
    je      .same_file
    test    rsi, rsi
    jz      .new_file
    test    rdi, rdi
    jz      .new_file
    push    rsi
    call    str_cmp
    pop     rsi
    test    rax, rax
    jz      .same_file
.new_file:
    mov     [rel dump_file], rsi
    mov     dword [rel dump_linnum], -1    ; a "%line" now
    xor     eax, eax
    test    rsi, rsi
    setnz   al
    mov     [rel dump_lineinc], eax
    jmp     .placed
.same_file:
    mov     eax, [rel dump_linnum]
    mov     ecx, [rel dump_lineinc]
    mov     edx, [rel dump_at]
    test    ecx, ecx
    jz      .step_zero
    lea     r8d, [rax + rcx]
    cmp     r8d, edx
    jne     .not_next
    ; one line on: an empty line for the one left out
    mov     [rel dump_linnum], r8d
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
    jmp     .placed
.not_next:
    sub     eax, ecx
    cmp     eax, edx
    jne     .placed
    mov     dword [rel dump_lineinc], 0    ; the same line again: a macro's
    jmp     .placed
.step_zero:
    inc     eax
    cmp     eax, edx
    jne     .placed
    mov     dword [rel dump_lineinc], 1
.placed:
    pop     rcx
    cmp     dword [rel dump_linnum], -1
    jne     .mark
    test    ecx, ecx
    jz      .mark
    stc
    ret
.mark:
    mov     eax, [rel dump_at]
    cmp     eax, [rel dump_linnum]
    je      .marked
    lea     rsi, [rel dump_line_dir]       ; "%line "
    call    .write_str
    mov     esi, [rel dump_at]
    call    .write_num
    lea     rsi, [rel dump_plus]
    mov     edx, 1
    call    .write
    mov     esi, [rel dump_lineinc]
    call    .write_num
    lea     rsi, [rel dump_blank]
    mov     edx, 1
    call    .write
    call    .write_file
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
.marked:
    mov     eax, [rel dump_at]
    add     eax, [rel dump_lineinc]
    mov     [rel dump_linnum], eax
    clc
    ret

; .write_num: esi, in decimal
.write_num:
    lea     rdi, [rel dump_num]
    mov     edx, 10
    call    int_to_str
    lea     rsi, [rel dump_num]
    jmp     .write_str

; .write_file: dump_file's name, in quotes only when it needs them, as
; NASM: empty, a control character, two blanks running, or a blank or a
; quote first or last
.write_file:
    mov     r15, [rel dump_file]
    test    r15, r15
    jz      .file_empty
    mov     rdi, r15
    call    str_len
    mov     ecx, eax
    test    ecx, ecx
    jz      .file_quote
    movzx   eax, byte [r15]
    call    .file_edge
    jbe     .file_quote
    movzx   eax, byte [r15 + rcx - 1]
    call    .file_edge
    jbe     .file_quote
    xor     edx, edx
    mov     r8d, ' '                       ; below it: quoted
.file_scan:
    movzx   eax, byte [r15 + rdx]
    cmp     eax, r8d
    jb      .file_quote
    mov     r8d, ' '
    cmp     eax, ' '
    jne     .file_next
    mov     r8d, ' ' + 1
.file_next:
    inc     edx
    cmp     edx, ecx
    jb      .file_scan
    mov     rsi, r15
    mov     edx, ecx
    jmp     .write
.file_quote:
    xor     r9d, r9d
    jmp     .requote
.file_empty:
    lea     rsi, [rel dump_no_file]
    mov     edx, 2
    jmp     .write
; .file_edge: eax = a first or last character; "below or equal" (CF or
; ZF) when it is a blank, a control character or a quote
.file_edge:
    cmp     eax, '"'
    je      .edge_is
    cmp     eax, 39
    je      .edge_is
    cmp     eax, '`'
    je      .edge_is
    cmp     eax, ' '
    ret
.edge_is:
    cmp     eax, eax
    ret

; .quoted: rsi = bytes, edx = count, r8b = the quote around them
.quoted:
    push    rsi
    push    rdx
    mov     [rel dump_quote], r8b
    lea     rsi, [rel dump_quote]
    mov     edx, 1
    call    .write
    pop     rdx
    pop     rsi
    call    .write
    lea     rsi, [rel dump_quote]
    mov     edx, 1
    jmp     .write

; .write_str: the NUL-terminated rsi
.write_str:
    push    rsi
    mov     rdi, rsi
    call    str_len
    pop     rsi
    mov     edx, eax
; .write: rsi = bytes, edx = count, to fd r12d (nothing for -1), through
; dump_buf
.write:
    test    r12d, r12d
    js      .write_none
    test    edx, edx
    jz      .write_none
    mov     eax, [rel dump_fill]
    lea     ecx, [rax + rdx]
    cmp     ecx, DUMP_BUF
    jbe     .buffer
    push    rsi
    push    rdx
    call    .flush
    pop     rdx
    pop     rsi
    cmp     edx, DUMP_BUF
    jbe     .buffer
    mov     edi, r12d
    extern  io_write
    jmp     io_write
.buffer:
    mov     ecx, edx
    mov     eax, [rel dump_fill]
    lea     rdi, [rel dump_buf]
    add     rdi, rax
    add     [rel dump_fill], edx
    rep movsb
.write_none:
    ret
; .flush: what dump_buf holds, out
.flush:
    test    r12d, r12d
    js      .write_none
    mov     edx, [rel dump_fill]
    test    edx, edx
    jz      .write_none
    mov     dword [rel dump_fill], 0
    lea     rsi, [rel dump_buf]
    mov     edi, r12d
    jmp     io_write

; ---- prep_push_buffer -------------------
;
; prep_push_buffer
; Reads the given text next, as if a file holding it were %included at
; this point: the command line's -D, -U and -p (cli_prelude) come in this
; way, ahead of the source. The text is copied into its own mapping, since
; the end of an included file unmaps its buffer.
; Input    : rdi = PrepState, rsi = text, rdx = length, rcx = the name it
;            is reported under
; Output   : rax = EXIT_OK or error
;
global prep_push_buffer
prep_push_buffer:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r13, rsi
    mov     r14, rdx
    mov     r12, rcx
    test    r14, r14
    jz      .ok

    ; where it is read in (-E writes its lines there, as NASM's packages)
    mov     eax, [rel push_count]
    cmp     eax, PUSH_MAX
    jae     .where_full
    mov     rcx, [rbx + PREP_lexer]
    test    rcx, rcx
    jz      .where_full
    imul    eax, eax, 24
    lea     rdx, [rel push_where]
    add     rdx, rax
    mov     [rdx], r12
    mov     rax, [rcx + LEXER_file]
    mov     [rdx + 8], rax
    mov     eax, [rcx + LEXER_line]
    mov     [rdx + 16], eax
    inc     dword [rel push_count]
.where_full:

    xor     edi, edi
    mov     rsi, r14
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    extern  io_mmap
    call    io_mmap
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, r15
    mov     rsi, r13
    mov     rcx, r14
    rep movsb

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; r13 = the new lexer
    mov     rdi, r13
    mov     rsi, r15
    mov     rdx, r14
    mov     rcx, r12
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [rbx + PREP_arena]
    call    lexer_init
    test    rax, rax
    jnz     .ret

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, INCLUDECTX_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + INCLUDECTX_tag], TAG_INCLUDE_CTX
    mov     r10, [rbx + PREP_ctx]
    mov     r11, [r10 + ASMCTX_inc_ctx]
    mov     [rdx + INCLUDECTX_parent], r11
    mov     [r10 + ASMCTX_inc_ctx], rdx
    mov     r11, [r10 + ASMCTX_mac_exp]    ; (as for %include)
    mov     [rdx + INCLUDECTX_mac_exp], r11
    mov     qword [r10 + ASMCTX_mac_exp], 0
    mov     [rdx + INCLUDECTX_buf], r15
    mov     [rdx + INCLUDECTX_size], r14
    mov     rax, [rbx + PREP_lexer]
    mov     [rdx + INCLUDECTX_lexer], rax
    xor     eax, eax                       ; depth: one below the parent's
    test    r11, r11
    jz      .depth
    movzx   eax, word [r11 + INCLUDECTX_depth]
    inc     eax
.depth:
    mov     [rdx + INCLUDECTX_depth], ax
    mov     [rbx + PREP_lexer], r13
    mov     byte [r13 + LEXER_pushed], 1
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
