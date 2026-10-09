;
; ============================================
; File     : src/core/lexer.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern arena_alloc
extern arena_alloc_string
extern error_emit
extern mem_copy
extern mem_zero
extern str_is_hex_digit
extern str_is_ident_char
extern str_utf8_decode
extern str_len
extern str_int_to_str
extern symbol_find

; ============================================================================
; LEXER
; ============================================================================
; Converts a raw source file buffer into a stream of Token structs.
; One LexerState per source file. Nested includes get their own LexerState.
;
; Token stream flow:
;   lexer_init â†’ lexer_next (repeated) â†’ lexer_peek â†’ lexer_destroy
;
; Character classification:
;   whitespace     space, tab, CR â€” skipped silently
;   newline        LF â€” emitted as TOK_NEWLINE
;   comments       ; and ; ; â€” discarded entirely
;   identifiers    [a-zA-Z_.][a-zA-Z0-9_.]*
;   labels         identifier followed immediately by :
;   local labels   identifier starting with .
;   numbers        decimal, 0x hex, 0b binary, 0o octal
;   strings        "..." with escape sequences
;   chars          '.' single character literal
;   directives     % followed by identifier
;   registers      detected by parser â€” lexer emits as TOK_IDENT
;
; Error handling:
;   on unknown character â†’ error_emit + skip + continue
;   on unterminated string â†’ error_emit + EXIT_UNEXPECTED_EOF
;   all errors go through AsmCtx error reporter
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result
;   callee saved: rbx, r12-r15, rbp

[SECTION .text]

; ---- lexer_next_line ---------------------
;
; The next source line: the line number goes up by lexer_line_step (1, or
; what "%line N+step" set). Preserves every register and the flags but CF.
; Input    : rbx = LexerState
;
global lexer_line_step
lexer_next_line:
    push    rax
    mov     eax, [rel lexer_line_step]
    add     [rbx + LEXER_line], eax
    pop     rax
    ret

[SECTION .data]
lexer_line_step: dd 1

[SECTION .text]

; ---- lexer_init -------------------------
;
; lexer_init
; Initialises a LexerState for a source buffer.
; Must be called before any other lexer function.
; Input    : rdi = pointer to LexerState (allocated by caller)
;             rsi = pointer to source file buffer
;             rdx = size of source buffer in bytes
;             rcx = pointer to filename string
;             r8  = pointer to AsmCtx
;             r9  = pointer to Arena
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : r10, r11
;
global lexer_init
lexer_init:
    ; validate all pointers
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr
    test    r8, r8
    jz      .null_ptr
    test    r9, r9
    jz      .null_ptr

    ; write tag
    mov     byte [rdi + LEXER_tag], TAG_LEXER

    ; store buffer pointer and end pointer
    mov     [rdi + LEXER_buf], rsi
    mov     [rdi + LEXER_pos], rsi      ; pos starts at buf start

    ; end = buf + size
    mov     r10, rsi
    add     r10, rdx
    mov     [rdi + LEXER_end], r10

    ; store filename
    mov     [rdi + LEXER_file], rcx

    ; line = 1, col = 1
    mov     dword [rdi + LEXER_line], 1
    mov     word  [rdi + LEXER_col],  1

    ; no peek yet
    mov     byte [rdi + LEXER_has_peek], FALSE

    ; store ctx and arena
    mov     [rdi + LEXER_ctx],   r8
    mov     [rdi + LEXER_arena], r9

    xor     rax, rax
    ret

.null_ptr:
    mov     rax, EXIT_INTERNAL
    ret

; ---- lexer_next -------------------------
;
; lexer_next
; Reads and returns the next token from the source buffer.
; If a peeked token exists, returns and clears it instead.
; Skips whitespace and comments automatically.
; Input    : rdi = pointer to LexerState
;             rsi = pointer to Token struct to fill
; Output   : rax = EXIT_OK or error code
;              rdx = pointer to filled Token (same as rsi)
; Clobbers : rcx, r8, r9, r10, r11
;
global lexer_next
lexer_next:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi               ; save LexerState
    test    rbx, rbx
    jz      .bad_lexer

    mov     r12, rsi               ; save Token output pointer

    ; validate tag
    cmp     byte [rbx + LEXER_tag], TAG_LEXER
    jne     .bad_lexer

    ; if peek slot is valid â€” return peek token
    cmp     byte [rbx + LEXER_has_peek], TRUE
    jne     .no_peek

    ; copy inline peek token to output
    lea     rsi, [rbx + LEXER_peek]
    mov     rdi, r12
    copy_token                     ; (mem_copy, for 32 bytes)

    ; clear peek slot
    mov     byte [rbx + LEXER_has_peek], FALSE

    xor     rax, rax
    mov     rdx, r12
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.no_peek:
    ; skip whitespace and comments
    call    .skip_ignored
    test    rax, rax
    jnz     .fail

    ; check for EOF
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    cmp     r13, r10
    jge     .emit_eof

    ; read current character
    movzx   rcx, byte [r13]

    ; check for UTF-8 (high bit set)
    cmp     rcx, 128
    jae     .lex_utf8_start

    ; dispatch on character
    cmp     rcx, 10                ; LF newline
    je      .emit_newline

    cmp     rcx, '"'               ; string literal
    je      .lex_string

    cmp     rcx, 0x27              ; ' char literal
    je      .lex_char

    cmp     rcx, 0x60              ; ` string with escapes
    je      .lex_bquote

    cmp     rcx, '%'               ; directive
    jne     .not_percent
    mov     r10, [rbx + LEXER_pos]
    lea     r11, [r10 + 1]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_directive
    ; "%" before a blank is the modulo operator (7 % 3); directives, %1 and
    ; %%local never have a blank there
    cmp     byte [r11], ' '
    je      .emit_single_percent
    cmp     byte [r11], 9
    je      .emit_single_percent
    ; "%%" before a blank is signed modulo (-7 %% 2); %%local has none
    cmp     byte [r11], '%'
    jne     .not_dpercent
    lea     rax, [r11 + 1]
    cmp     rax, [rbx + LEXER_end]
    jge     .not_dpercent
    cmp     byte [rax], ' '
    je      .emit_dpercent
    cmp     byte [rax], 9
    je      .emit_dpercent
.not_dpercent:
    ; "%[NAME]" is a value, "%+" pastes tokens, "%$name" is a context local
    cmp     byte [r11], '['
    je      .lex_interp_value
    cmp     byte [r11], '+'
    je      .lex_paste
    cmp     byte [r11], '$'
    je      .lex_ctx_local
    jmp     .lex_directive
.not_percent:

    ; a non-ASCII byte starts a UTF-8 identifier (or is malformed UTF-8)
    cmp     rcx, 0x80
    jae     .lex_utf8_start

    ; identifier, label, or number
    movzx   eax, byte [lexer_char_props + rcx]
    test    al, CHAR_IS_IDENT_START
    jnz     .lex_ident
    test    al, CHAR_IS_DIGIT
    jnz     .lex_number

    ; single character tokens
    cmp     rcx, ','
    je      .emit_single_comma
    cmp     rcx, ':'
    je      .emit_single_colon
    cmp     rcx, '['
    je      .emit_single_lbracket
    cmp     rcx, ']'
    je      .emit_single_rbracket
    cmp     rcx, '{'
    je      .emit_single_lbrace
    cmp     rcx, '}'
    je      .emit_single_rbrace
    cmp     rcx, '('
    je      .emit_single_lparen
    cmp     rcx, ')'
    je      .emit_single_rparen
    cmp     rcx, '+'
    je      .emit_single_plus
    cmp     rcx, '-'
    je      .emit_single_minus
    cmp     rcx, '*'
    je      .emit_single_star
    cmp     rcx, '/'
    je      .emit_single_slash
    cmp     rcx, '&'
    je      .emit_single_amp
    cmp     rcx, '|'
    je      .emit_single_pipe
    cmp     rcx, '^'
    je      .emit_single_caret
    cmp     rcx, '~'
    je      .emit_single_tilde
    cmp     rcx, '#'
    je      .emit_single_hash
    cmp     rcx, '@'
    je      .emit_single_at
    cmp     rcx, '<'
    je      .lex_lshift
    cmp     rcx, '>'
    je      .lex_rshift
    cmp     rcx, '$'
    je      .emit_single_dollar
    cmp     rcx, '='
    je      .lex_equal
    cmp     rcx, '!'
    je      .lex_excl
    cmp     rcx, '?'
    je      .emit_single_question

    ; unknown character — emit error and skip
    jmp     .unknown_char

; ---- UTF-8 Handling ---------------------
.lex_utf8_start:
    mov     rdi, [rbx + LEXER_pos]
    mov     rsi, [rbx + LEXER_end]
    call    str_utf8_decode
    test    rax, rax
    jz      .malformed_utf8

    ; rdx = codepoint, rax = length
    ; Sanitization: block control characters and dangerous non-printables
    cmp     rdx, 0x20
    jbe     .unknown_char
    cmp     rdx, 0x7F
    je      .unknown_char
    cmp     rdx, 0x9F
    jbe     .unknown_char          ; Latin-1 control chars

    ; Is it a valid identifier start?
    ; For now, we allow any non-control Unicode codepoint > 0x7F as an identifier start.
    jmp     .lex_ident

.malformed_utf8:
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_malformed_utf8]
    call    error_emit
    
    ; skip one byte and try again
    mov     rdi, rbx
    sub     rsp, TOKEN_SIZE
    mov     r12, rsp
    mov     rsi, r12
    call    lexer_next

; ---- EOF --------------------------------
.emit_eof:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_EOF
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- newline ----------------------------
.emit_newline:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_NEWLINE
    ; advance past LF
    inc     qword [rbx + LEXER_pos]
    ; increment line, reset col
    call    lexer_next_line
    mov     word  [rbx + LEXER_col], 1
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- single character tokens ------------
.emit_single_comma:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_COMMA
    jmp     .advance_single

.emit_single_colon:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_COLON
    jmp     .advance_single

.emit_single_lbracket:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_LBRACKET
    jmp     .advance_single

.emit_single_rbracket:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_RBRACKET
    jmp     .advance_single

.emit_single_lbrace:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_LBRACE
    jmp     .advance_single

.emit_single_rbrace:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_RBRACE
    jmp     .advance_single

.emit_single_lparen:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_LPAREN
    jmp     .advance_single

.emit_single_percent:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_PERCENT
    jmp     .advance_single

.emit_dpercent:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_DPERCENT
    mov     ecx, 2
    jmp     .advance_n

; advance past a token of ECX characters
.advance_n:
    add     qword [rbx + LEXER_pos], rcx
    add     word  [rbx + LEXER_col], cx
    mov     word  [r12 + TOKEN_len], cx
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_single_question:
    ; "?" followed by a name character starts an identifier (?x, __?x?__
    ; are names); alone it is "db ?" or the conditional operator
    mov     r10, [rbx + LEXER_pos]
    lea     r11, [r10 + 1]
    cmp     r11, [rbx + LEXER_end]
    jge     .question_alone
    movzx   edi, byte [r11]
    call    str_is_ident_char
    cmp     rax, TRUE
    je      .lex_ident
.question_alone:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_QUESTION
    jmp     .advance_single

.emit_single_rparen:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_RPAREN
    jmp     .advance_single

.emit_single_plus:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_PLUS
    jmp     .advance_single

.emit_single_minus:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_MINUS
    jmp     .advance_single

.emit_single_star:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_STAR
    jmp     .advance_single

.emit_single_slash:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_SLASH
    jmp     .advance_single

.emit_single_amp:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_AMPERSAND
    mov     cl, '&'
    mov     r14b, TOK_AND
    jmp     .maybe_doubled

.emit_single_pipe:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_PIPE
    mov     cl, '|'
    mov     r14b, TOK_OR

; A doubled '&' or '|' is the logical operator. CL holds the character and
; R14B the token kind to emit for the pair.
.maybe_doubled:
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10
    cmp     r13, r10
    jge     .advance_single
    cmp     byte [r13 + 1], cl
    jne     .advance_single

    mov     byte [r12 + TOKEN_kind], r14b
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col],  2
    mov     word  [r12 + TOKEN_len],  2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_single_caret:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_CARET
    mov     cl, '^'
    mov     r14b, TOK_LXOR                 ; ^^
    jmp     .maybe_doubled

.emit_single_tilde:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_TILDE
    jmp     .advance_single

.emit_single_hash:
    call    .token_begin
    ; Check for ## (A68)
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10                    ; r10 = end - 1
    cmp     r13, r10
    jge     .emit_just_hash
    
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '#'
    jne     .emit_just_hash
    
    ; It's ##
    mov     byte [r12 + TOKEN_kind], TOK_CONCAT
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    mov     word  [r12 + TOKEN_len], 2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_just_hash:
    mov     byte [r12 + TOKEN_kind], TOK_HASH
    jmp     .advance_single

.emit_single_at:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_AT
    jmp     .advance_single

.emit_single_dollar:
    ; "$0ff": a hex number, the $ a prefix before a digit
    mov     r10, [rbx + LEXER_pos]
    lea     r11, [r10 + 1]
    cmp     r11, [rbx + LEXER_end]
    jge     .dollar_alone
    ; "$name": a name even when it is a register or a keyword ($eax: is a
    ; label); the symbol table drops the $ (middle/symtable)
    movzx   eax, byte [r11]
    cmp     al, '?'
    je      .lex_ident
    test    byte [lexer_char_props + rax], CHAR_IS_IDENT_START
    jnz     .lex_ident
    sub     eax, '0'
    cmp     eax, 9
    ja      .dollar_alone
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]     ; the number's text starts at the $
    xor     r14, r14
    xor     r15, r15
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_number_loop
.dollar_alone:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_DOLLAR
    jmp     .advance_single

.advance_single:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    mov     word  [r12 + TOKEN_len], 1
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- << and >> --------------------------
.lex_lshift:
    call    .token_begin
    ; check next char — must have at least 2 bytes remaining (pos + 1 < end)
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10                    ; r10 = end - 1
    cmp     r13, r10
    jge     .emit_single_lt
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '<'
    jne     .check_le

    ; It is << (or <<<, the same shift)
    mov     byte [r12 + TOKEN_kind], TOK_LSHIFT
    mov     ecx, 2
    call    .third_is
    cmp     al, '<'
    jne     .advance_n
    mov     ecx, 3
    jmp     .advance_n

.check_le:
    cmp     rcx, '>'
    jne     .check_le_eq
    ; <> is !=
    mov     byte [r12 + TOKEN_kind], TOK_NEQUAL
    mov     ecx, 2
    jmp     .advance_n
.check_le_eq:
    cmp     rcx, '='
    jne     .emit_single_lt

    ; It is <= (or <=>, the three-way comparison)
    mov     byte [r12 + TOKEN_kind], TOK_LE
    mov     ecx, 2
    call    .third_is
    cmp     al, '>'
    jne     .advance_n
    mov     byte [r12 + TOKEN_kind], TOK_CMP3
    mov     ecx, 3
    jmp     .advance_n

; al = the character two after the current one (0 past the end)
.third_is:
    xor     eax, eax
    mov     r13, [rbx + LEXER_pos]
    add     r13, 2
    cmp     r13, [rbx + LEXER_end]
    jge     .third_ret
    mov     al, [r13]
.third_ret:
    ret

.emit_single_lt:
    mov     byte [r12 + TOKEN_kind], TOK_LT
    jmp     .advance_single

.lex_rshift:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10                    ; r10 = end - 1
    cmp     r13, r10
    jge     .emit_single_gt
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '>'
    jne     .check_ge

    ; It is >> (or >>>, the arithmetic shift)
    mov     byte [r12 + TOKEN_kind], TOK_RSHIFT
    mov     ecx, 2
    call    .third_is
    cmp     al, '>'
    jne     .advance_n
    mov     byte [r12 + TOKEN_kind], TOK_SAR
    mov     ecx, 3
    jmp     .advance_n

.check_ge:
    cmp     rcx, '='
    jne     .emit_single_gt

    ; It is >=
    mov     byte [r12 + TOKEN_kind], TOK_GE
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col],  2
    mov     word  [r12 + TOKEN_len],  2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_single_gt:
    mov     byte [r12 + TOKEN_kind], TOK_GT
    jmp     .advance_single

; ---- = / == and != -----------------------
.lex_equal:
    call    .token_begin
    ; Check if next char is '='
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10
    cmp     r13, r10
    jge     .emit_single_equal
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '='
    jne     .emit_single_equal
    
    ; It is ==
    mov     byte [r12 + TOKEN_kind], TOK_EQUAL
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    mov     word  [r12 + TOKEN_len], 2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_single_equal:
    mov     byte [r12 + TOKEN_kind], TOK_EQUAL
    jmp     .advance_single

.lex_excl:
    call    .token_begin
    ; Check if next char is '='
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10
    cmp     r13, r10
    jge     .emit_not
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '='
    jne     .emit_not
    
    ; It is !=
    mov     byte [r12 + TOKEN_kind], TOK_NEQUAL
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    mov     word  [r12 + TOKEN_len], 2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.emit_not:
    mov     byte [r12 + TOKEN_kind], TOK_NOT   ; ! logical not
    jmp     .advance_single

; ---- identifier / label -----------------
;
; Reads [a-zA-Z_.][a-zA-Z0-9_.]* into arena.
; If followed by : emits TOK_LABEL or TOK_LOCAL_LABEL.
; Otherwise emits TOK_IDENT.
;
.lex_ident:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]     ; start of identifier

    ; scan while ident chars
.lex_ident_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_ident_done
    movzx   rdi, byte [r10]

    ; UTF-8 check
    cmp     rdi, 128
    jae     .lex_ident_utf8

    call    str_is_ident_char
    cmp     rax, TRUE
    jne     .lex_ident_done
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_ident_loop

.lex_ident_utf8:
    mov     rdi, [rbx + LEXER_pos]
    mov     rsi, [rbx + LEXER_end]
    call    str_utf8_decode
    test    rax, rax
    jz      .malformed_utf8_in_ident

    ; rdx = codepoint, rax = length
    ; Sanitization: block control chars and dangerous non-printables
    cmp     rdx, 0x9F
    jbe     .lex_ident_done        ; Stop at Latin-1 control chars or lower
    
    ; allow codepoint as part of identifier
    add     [rbx + LEXER_pos], rax
    inc     word [rbx + LEXER_col]  ; 1 col per codepoint
    jmp     .lex_ident_loop

.malformed_utf8_in_ident:
    ; We already have a malformed handler, jump to it
    jmp     .malformed_utf8

.lex_ident_done:
    ; An identifier run that stops at "%[" continues through interpolation,
    ; e.g. REG_ZMM%[i] is one identifier whose text depends on i; so does
    ; one glued to a macro parameter or local, isr_%1, x_%{2}, a%%b, which
    ; NASM pastes into one name.
    mov     r10, [rbx + LEXER_pos]
    call    .glue_follows
    je      .lex_ident_interp

.lex_ident_plain:
    ; length = pos - start
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13                   ; r10 = length

    ; copy into arena
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    ; store value pointer and length
    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w

    ; check if followed by : (label)
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_ident_not_label
    movzx   rcx, byte [r10]
    cmp     rcx, ':'
    jne     .lex_ident_not_label

    ; consume the colon
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; check if local label (starts with .)
    movzx   rcx, byte [r13]
    cmp     rcx, '.'
    je      .lex_local_label

    mov     byte [r12 + TOKEN_kind], TOK_LABEL
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_local_label:
    mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_ident_not_label:
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- %+ token paste -------------------------
;
; Emitted as its own token; the preprocessor joins the tokens either side of
; it while serving a macro body.
;
.lex_paste:
    call    .token_begin
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    mov     byte [r12 + TOKEN_kind], TOK_CONCAT
    mov     qword [r12 + TOKEN_value], 0
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- %$name context local -------------------
;
; Kept as raw text and rewritten to "..@N.name" when the token is served,
; because which context is innermost depends on the expansion, not the file.
;
.lex_ctx_local:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]         ; text starts at '%'
    add     qword [rbx + LEXER_pos], 2     ; skip "%$"
    add     word  [rbx + LEXER_col], 2

.ctx_local_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .ctx_local_done
    movzx   rdi, byte [r10]
    call    str_is_ident_char
    cmp     rax, TRUE
    jne     .ctx_local_done
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .ctx_local_loop

.ctx_local_done:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    or      byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- standalone %[NAME] value ----------------
;
; Produces a token holding the raw "%[NAME]" text. The value is substituted
; during expansion, not here: a %rep body is lexed once but replayed many
; times, and the named symbol usually changes between iterations.
;
.lex_interp_value:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]         ; text starts at '%'
    add     qword [rbx + LEXER_pos], 2     ; skip "%["
    add     word  [rbx + LEXER_col], 2

.interp_val_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_val_done
    cmp     byte [r10], ']'
    je      .interp_val_close
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_val_loop

.interp_val_close:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

.interp_val_done:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    or      byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- identifier with %[...] interpolation ----
;
; Scans a name such as REG_ZMM%[i] as a single identifier and keeps the raw
; text; the preprocessor substitutes each %[...] when the token is served.
;
.lex_ident_interp:
.interp_scan:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_finish
    movzx   rdi, byte [r10]

    cmp     dil, '%'
    je      .interp_maybe_open

    call    str_is_ident_char
    cmp     rax, TRUE
    jne     .interp_finish
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_scan

.interp_maybe_open:
    lea     r11, [r10 + 1]
    cmp     r11, [rbx + LEXER_end]
    jge     .interp_finish
    ; %1 / %{1} / %%name / %$name: the preprocessor substitutes them
    movzx   eax, byte [r11]
    cmp     al, '{'
    je      .interp_brace
    cmp     al, '%'
    je      .interp_two
    cmp     al, '$'
    je      .interp_two
    sub     eax, '0'
    cmp     eax, 9
    jbe     .interp_digits
    cmp     byte [r11], '['
    jne     .interp_finish

    ; consume "%[" ... "]"
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
.interp_name_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_finish
    cmp     byte [r10], ']'
    je      .interp_name_done
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_name_loop

.interp_name_done:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_scan

.interp_two:
    ; "%%" / "%$": the name that follows is scanned on
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    jmp     .interp_scan
.interp_digits:
    ; "%12": the parameter's digits (the scan takes them on anyway)
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_scan
.interp_brace:
    ; "%{1}": up to the brace
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
.interp_brace_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_finish
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    cmp     byte [r10], '}'
    jne     .interp_brace_loop
    jmp     .interp_scan

; .glue_follows: ZF set when the text at r10 continues a name by
; interpolation: %[...], %N, %{...}, %%name. Clobbers rax, r11.
.glue_follows:
    cmp     r10, [rbx + LEXER_end]
    jae     .glue_no
    cmp     byte [r10], '%'
    jne     .glue_no
    lea     r11, [r10 + 1]
    cmp     r11, [rbx + LEXER_end]
    jae     .glue_no
    movzx   eax, byte [r11]
    cmp     al, '['
    je      .glue_yes
    cmp     al, '{'
    je      .glue_yes
    cmp     al, '%'
    je      .glue_local
    sub     eax, '0'
    cmp     eax, 9
    ja      .glue_no
.glue_yes:
    cmp     eax, eax
    ret
.glue_local:
    ; "%%" then a name (not the "%%" modulo operator)
    lea     r11, [r10 + 2]
    cmp     r11, [rbx + LEXER_end]
    jae     .glue_no
    push    rdi
    movzx   edi, byte [r11]
    call    str_is_ident_char
    pop     rdi
    cmp     rax, TRUE
    ret
.glue_no:
    test    rsp, rsp                       ; ZF clear
    ret

.interp_finish:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13                       ; raw text length
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    or      byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- number -----------------------------
;
; Reads numeric literal into arena string.
; Supports: decimal, 0x hex, 0b binary, 0o octal.
; Stores raw string in TOKEN_value for str_to_int later.
;
.lex_number:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]     ; start of number
    xor     r14, r14                   ; r14 = float flag (0=int, 1=float)
    xor     r15, r15                   ; end of digits, when a suffix follows

.lex_number_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_number_done
    movzx   rdi, byte [r10]

    ; accept hex digits
    call    str_is_hex_digit
    cmp     rax, TRUE
    je      .lex_number_advance

    ; accept prefixes and scientific markers
    movzx   rdi, byte [r10]
    cmp     rdi, 'x'
    je      .lex_number_advance
    cmp     rdi, 'X'
    je      .lex_number_advance
    cmp     rdi, 'b'
    je      .lex_number_advance
    cmp     rdi, 'B'
    je      .lex_number_advance
    cmp     rdi, 'o'
    je      .lex_number_advance
    cmp     rdi, 'O'
    je      .lex_number_advance
    ; NASM's other radix letters (ffh, 777q, 1010y, 0t100) and 1_000
    cmp     rdi, 'h'
    je      .lex_number_advance
    cmp     rdi, 'H'
    je      .lex_number_advance
    cmp     rdi, 'q'
    je      .lex_number_advance
    cmp     rdi, 'Q'
    je      .lex_number_advance
    cmp     rdi, 'y'
    je      .lex_number_advance
    cmp     rdi, 'Y'
    je      .lex_number_advance
    cmp     rdi, 't'
    je      .lex_number_advance
    cmp     rdi, 'T'
    je      .lex_number_advance
    cmp     rdi, '_'
    je      .lex_number_advance
    
    ; Float markers
    cmp     rdi, '.'
    je      .is_float
    cmp     rdi, 'e'
    je      .is_float
    cmp     rdi, 'E'
    je      .is_float
    cmp     rdi, 'p'
    je      .is_float
    cmp     rdi, 'P'
    je      .is_float
    
    ; signs can appear after e/p, and only there: otherwise "4+8" would lex
    ; as a single number token
    ; integer size suffixes (1ULL, 32u, 5L) are consumed but are not part
    ; of the numeric text handed to str_to_int
    cmp     rdi, 'u'
    je      .lex_number_suffix
    cmp     rdi, 'U'
    je      .lex_number_suffix
    cmp     rdi, 'l'
    je      .lex_number_suffix
    cmp     rdi, 'L'
    je      .lex_number_suffix

    cmp     rdi, '+'
    je      .lex_number_sign
    cmp     rdi, '-'
    je      .lex_number_sign

    jmp     .lex_number_done

.lex_number_sign:
    cmp     r10, r13               ; need a preceding character
    jbe     .lex_number_done
    movzx   rax, byte [r10 - 1]
    cmp     al, 'e'
    je      .lex_number_advance
    cmp     al, 'E'
    je      .lex_number_advance
    cmp     al, 'p'
    je      .lex_number_advance
    cmp     al, 'P'
    je      .lex_number_advance
    jmp     .lex_number_done

.is_float:
    mov     r14, 1
    jmp     .lex_number_advance

.lex_number_advance:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_number_loop

.lex_number_suffix:
    ; remember where the digits stopped, then swallow the suffix letters
    test    r15, r15
    jnz     .lex_number_suffix_go
    mov     r15, [rbx + LEXER_pos]
.lex_number_suffix_go:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_number_loop

.lex_number_done:
    ; "0x%1": the parameter's digits are pasted on
    test    r15, r15
    jnz     .number_unglued
    mov     r10, [rbx + LEXER_pos]
    call    .glue_follows
    je      .lex_ident_interp
.number_unglued:
    mov     r10, [rbx + LEXER_pos]
    test    r15, r15
    jz      .lex_number_len
    mov     r10, r15                   ; text ends before the suffix
.lex_number_len:
    sub     r10, r13                   ; length

    ; copy raw number string into arena
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    ; "1e3", "25E-2": decimal digits with an exponent are a float too
    test    r14, r14
    jnz     .set_kind
    mov     rsi, rdx
.fe_digits:
    movzx   eax, byte [rsi]
    sub     eax, '0'
    cmp     eax, 9
    ja      .fe_e
    inc     rsi
    jmp     .fe_digits
.fe_e:
    cmp     rsi, rdx
    je      .set_kind
    movzx   eax, byte [rsi]
    or      eax, 0x20
    cmp     eax, 'e'
    jne     .set_kind
    inc     rsi
    movzx   eax, byte [rsi]
    cmp     eax, '+'
    je      .fe_sign
    cmp     eax, '-'
    jne     .fe_exp
.fe_sign:
    inc     rsi
.fe_exp:
    movzx   eax, byte [rsi]
    sub     eax, '0'
    cmp     eax, 9
    ja      .set_kind
.fe_exp_digits:
    inc     rsi
    movzx   eax, byte [rsi]
    sub     eax, '0'
    cmp     eax, 9
    jbe     .fe_exp_digits
    cmp     byte [rsi], 0
    jne     .set_kind
    mov     r14, 1
.set_kind:
    ; Set token kind based on float flag
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    test    r14, r14
    jz      .set_val
    mov     byte [r12 + TOKEN_kind], TOK_FLOAT

.set_val:
    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- string literal ---------------------
;
; Reads "..." handling escape sequences:
;   \n  newline
;   \t  tab
;   \r  carriage return
;   \\  backslash
;   \"  double quote
;   \0  null byte
;
.lex_bquote:
    mov     byte [rel lex_quote], 0x60
    jmp     .lex_quoted
.lex_string:
    mov     byte [rel lex_quote], '"'
.lex_quoted:
    call    .token_begin
    ; skip opening "
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; allocate string buffer in arena
    ; max length is remaining buffer size
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, MAX_LINE
    call    arena_alloc
    test    rax, rax
    jnz     .fail

    mov     r13, rdx               ; r13 = string output buffer
    xor     r10, r10               ; r10 = output length

.lex_string_loop:
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_string_unterminated

    movzx   rcx, byte [r11]

    cmp     cl, [rel lex_quote]    ; closing quote
    je      .lex_string_done

    cmp     rcx, 10                ; unexpected newline
    je      .lex_string_unterminated

    cmp     rcx, '\'               ; escape sequence
    je      .lex_string_escape

    ; normal character
    ; check buffer limit
    cmp     r10, MAX_LINE - 1
    jge     .lex_string_too_long

    mov     byte [r13 + r10], cl
    inc     r10
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_string_loop

.lex_string_too_long:
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_string_too_long]
    call    error_emit
    mov     rax, EXIT_INTERNAL
    jmp     .fail

.lex_string_escape:
    ; "..." is verbatim, as in NASM: only `...` has escapes. A backslash
    ; that ends the line still continues it.
    cmp     byte [rel lex_quote], 0x60
    je      .escape_on
    mov     r11, [rbx + LEXER_pos]
    lea     rax, [r11 + 1]
    cmp     rax, [rbx + LEXER_end]
    jge     .literal_backslash
    movzx   eax, byte [r11 + 1]
    cmp     eax, 10
    je      .escape_on
    cmp     eax, 13
    je      .escape_on
.literal_backslash:
    mov     byte [r13 + r10], '\'
    inc     r10
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_string_loop
.escape_on:
    ; skip backslash
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_string_unterminated

    movzx   rcx, byte [r11]
    
    ; Check for line continuation (A66)
    IF rcx, e, 10
        inc     qword [rbx + LEXER_pos]
        call    lexer_next_line
        mov     word  [rbx + LEXER_col], 1
        jmp     .lex_string_loop
    ELSEIF rcx, e, 13
        ; Check for CR+LF
        mov     rax, [rbx + LEXER_pos]
        inc     rax
        cmp     rax, [rbx + LEXER_end]
        jge     .lex_string_loop       ; Just ignore CR at EOF
        
        IF byte [rax], e, 10
            add     qword [rbx + LEXER_pos], 2
            call    lexer_next_line
            mov     word  [rbx + LEXER_col], 1
            jmp     .lex_string_loop
            ENDIF
            ENDIF

    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    cmp     rcx, 'n'
    je      .esc_newline
    cmp     rcx, 't'
    je      .esc_tab
    cmp     rcx, 'r'
    je      .esc_cr
    cmp     rcx, 'a'
    je      .esc_alert
    cmp     rcx, 'b'
    je      .esc_backspace
    cmp     rcx, 'f'
    je      .esc_formfeed
    cmp     rcx, 'v'
    je      .esc_vtab
    cmp     rcx, 'e'
    je      .esc_escape
    cmp     rcx, '\'
    je      .esc_backslash
    cmp     rcx, '"'
    je      .esc_quote
    cmp     rcx, 'x'
    je      .esc_hex
    cmp     rcx, 'u'
    je      .esc_u4
    cmp     rcx, 'U'
    je      .esc_u8
    cmp     rcx, '0'
    jb      .esc_other
    cmp     rcx, '7'
    jbe     .esc_octal
.esc_other:

    ; unknown escape â€” store literally
    mov     byte [r13 + r10], cl
    inc     r10
    jmp     .lex_string_loop

.esc_hex:
    mov     r9d, 2                         ; \xHH: one or two digits
    jmp     .esc_hex_digits
.esc_u4:
    mov     r9d, 4                         ; \uXXXX
    jmp     .esc_hex_digits
.esc_u8:
    mov     r9d, 8                         ; \UXXXXXXXX
.esc_hex_digits:
    xor     r14, r14
    xor     r8d, r8d                       ; digits read
.esc_hex_next:
    cmp     r8d, r9d
    jae     .esc_hex_end
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .esc_hex_end
    movzx   rcx, byte [r11]
    call    .hex_digit_to_val
    cmp     rax, ERR
    je      .esc_hex_end
    shl     r14, 4
    or      r14, rax
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    inc     r8d
    jmp     .esc_hex_next
.esc_hex_end:
    test    r8d, r8d
    jnz     .esc_have_digits
    ; "\x" without digits is the letter itself
    mov     al, 'x'
    cmp     r9d, 2
    je      .esc_letter
    mov     al, 'u'
    cmp     r9d, 4
    je      .esc_letter
    mov     al, 'U'
.esc_letter:
    mov     byte [r13 + r10], al
    inc     r10
    jmp     .lex_string_loop
.esc_have_digits:
    cmp     r9d, 2
    ja      .esc_utf8
    mov     byte [r13 + r10], r14b
    inc     r10
    jmp     .lex_string_loop

    ; \u / \U: the code point in UTF-8
.esc_utf8:
    cmp     r14, 0x80
    jae     .utf8_2
    mov     byte [r13 + r10], r14b
    inc     r10
    jmp     .lex_string_loop
.utf8_2:
    cmp     r14, 0x800
    jae     .utf8_3
    mov     rax, r14
    shr     eax, 6
    or      al, 0xC0
    mov     byte [r13 + r10], al
    inc     r10
    jmp     .utf8_last1
.utf8_3:
    cmp     r14, 0x10000
    jae     .utf8_4
    mov     rax, r14
    shr     eax, 12
    or      al, 0xE0
    mov     byte [r13 + r10], al
    inc     r10
    jmp     .utf8_last2
.utf8_4:
    mov     rax, r14
    shr     eax, 18
    and     al, 0x07
    or      al, 0xF0
    mov     byte [r13 + r10], al
    inc     r10
    mov     rax, r14
    shr     eax, 12
    and     al, 0x3F
    or      al, 0x80
    mov     byte [r13 + r10], al
    inc     r10
.utf8_last2:
    mov     rax, r14
    shr     eax, 6
    and     al, 0x3F
    or      al, 0x80
    mov     byte [r13 + r10], al
    inc     r10
.utf8_last1:
    mov     rax, r14
    and     al, 0x3F
    or      al, 0x80
    mov     byte [r13 + r10], al
    inc     r10
    jmp     .lex_string_loop

    ; \NNN: up to three octal digits (the first already read, in rcx)
.esc_octal:
    lea     r14, [rcx - '0']
    mov     r8d, 1
.esc_octal_next:
    cmp     r8d, 3
    jae     .esc_octal_end
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .esc_octal_end
    movzx   rcx, byte [r11]
    cmp     rcx, '0'
    jb      .esc_octal_end
    cmp     rcx, '7'
    ja      .esc_octal_end
    shl     r14, 3
    add     r14, rcx
    sub     r14, '0'
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    inc     r8d
    jmp     .esc_octal_next
.esc_octal_end:
    mov     byte [r13 + r10], r14b
    inc     r10
    jmp     .lex_string_loop

.hex_digit_to_val:
    ; rcx = char, rax = val
    IF rcx, ge, '0'
        IF rcx, le, '9'
            lea rax, [rcx - '0']
            ret
            ENDIF
            ENDIF
    IF rcx, ge, 'a'
        IF rcx, le, 'f'
            lea rax, [rcx - 'a' + 10]
            ret
            ENDIF
            ENDIF
    IF rcx, ge, 'A'
        IF rcx, le, 'F'
            lea rax, [rcx - 'A' + 10]
            ret
            ENDIF
            ENDIF
    mov     rax, ERR
    ret

.esc_newline:
    mov     byte [r13 + r10], 10
    inc     r10
    jmp     .lex_string_loop

.esc_tab:
    mov     byte [r13 + r10], 9
    inc     r10
    jmp     .lex_string_loop

.esc_cr:
    mov     byte [r13 + r10], 13
    inc     r10
    jmp     .lex_string_loop

.esc_alert:
    mov     byte [r13 + r10], 7
    inc     r10
    jmp     .lex_string_loop

.esc_backspace:
    mov     byte [r13 + r10], 8
    inc     r10
    jmp     .lex_string_loop

.esc_formfeed:
    mov     byte [r13 + r10], 12
    inc     r10
    jmp     .lex_string_loop

.esc_vtab:
    mov     byte [r13 + r10], 11
    inc     r10
    jmp     .lex_string_loop

.esc_escape:
    mov     byte [r13 + r10], 27
    inc     r10
    jmp     .lex_string_loop

.esc_backslash:
    mov     byte [r13 + r10], '\'
    inc     r10
    jmp     .lex_string_loop

.esc_quote:
    mov     byte [r13 + r10], '"'
    inc     r10
    jmp     .lex_string_loop

.esc_null:
    mov     byte [r13 + r10], 0
    inc     r10
    jmp     .lex_string_loop

.lex_string_done:
    ; skip closing "
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; null terminate
    mov     byte [r13 + r10], 0

    mov     byte [r12 + TOKEN_kind], TOK_STRING
    mov     [r12 + TOKEN_value], r13
    mov     word [r12 + TOKEN_len], r10w
    or      byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED  ; may hold NULs
    mov     al, [rel lex_quote]
    mov     [r12 + TOKEN_quote], al        ; " or `, for %defstr
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_string_unterminated:
    ; emit error
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_unterminated_string]
    call    error_emit

    mov     rax, EXIT_UNEXPECTED_EOF
    jmp     .fail

; ---- char literal -----------------------
;
; Reads 'x' or '\n' single character literal.
; Stores integer value in TOKEN_value directly.
;
.lex_char:
    call    .token_begin
    ; skip opening '
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; A character constant may hold up to eight characters. NASM packs them
    ; little-endian, so 'abcd' == 0x64636261 and the first one is the LSB.
    xor     r13, r13               ; accumulated value
    xor     r9, r9                 ; bit offset of the next character
    mov     rax, [rbx + LEXER_pos]
    mov     [rel lex_char_start], rax
    mov     qword [rel lex_char_count], 0

.lex_char_next:
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_char_unterminated

    movzx   rcx, byte [r11]
    cmp     rcx, 0x27              ; closing quote ends the literal
    je      .lex_char_closing

    cmp     rcx, '\'               ; escape?
    jne     .lex_char_regular

    ; '\' is a literal backslash: only treat it as an escape when another
    ; character follows it before the closing quote.
    lea     r10, [r11 + 1]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_char_escape
    cmp     byte [r10], 0x27       ; next char is the closing quote?
    jne     .lex_char_escape

.lex_char_regular:
    ; regular character
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_char_accum

.lex_char_escape:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_char_unterminated

    movzx   rcx, byte [r11]
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    cmp     rcx, 'n'
    je      .char_esc_n
    cmp     rcx, 't'
    je      .char_esc_t
    cmp     rcx, '0'
    je      .char_esc_0
    jmp     .lex_char_accum        ; literal

.char_esc_n:
    mov     rcx, 10
    jmp     .lex_char_accum
.char_esc_t:
    mov     rcx, 9
    jmp     .lex_char_accum
.char_esc_0:
    xor     rcx, rcx

.lex_char_accum:
    inc     qword [rel lex_char_count]
    mov     r10, rcx
    and     r10, 0xFF
    cmp     r9, 64
    jge     .lex_char_next         ; anything past eight characters is dropped
    mov     rcx, r9
    shl     r10, cl
    or      r13, r10
    add     r9, 8
    jmp     .lex_char_next

.lex_char_closing:
    ; More than eight characters is a string ('Hello, World!' in db),
    ; taken verbatim like NASM's single-quoted strings
    cmp     qword [rel lex_char_count], 8
    ja      .lex_char_string
    ; consume the closing '
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    mov     byte [r12 + TOKEN_kind], TOK_CHAR
    mov     byte [r12 + TOKEN_quote], 0x27
    mov     [r12 + TOKEN_value], r13
    mov     rax, [rel lex_char_count]
    mov     word [r12 + TOKEN_len], ax     ; characters: db emits them all
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_char_string:
    mov     rsi, [rbx + LEXER_pos]
    sub     rsi, [rel lex_char_start]      ; raw length between the quotes
    push    rsi
    inc     rsi
    mov     rdi, [rbx + LEXER_arena]
    call    arena_alloc                    ; zeroed: the copy ends in NUL
    pop     rcx
    test    rax, rax
    jnz     .fail
    mov     rdi, rdx
    mov     rsi, [rel lex_char_start]
    push    rdx
    rep movsb
    pop     rdx
    inc     qword [rbx + LEXER_pos]        ; the closing '
    inc     word  [rbx + LEXER_col]
    mov     byte [r12 + TOKEN_kind], TOK_STRING
    mov     byte [r12 + TOKEN_quote], 0x27
    mov     [r12 + TOKEN_value], rdx
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_char_unterminated:
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_unterminated_char]
    call    error_emit
    mov     rax, EXIT_UNEXPECTED_EOF
    jmp     .fail

; ---- directive --------------------------
;
; Reads %identifier â€” preprocessor directive.
; Emits TOK_DIRECTIVE with value pointing to
; the identifier string (without the % prefix).
;
.lex_directive:
    call    .token_begin
    ; skip %
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; Check for macro-local label %% (A70)
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_directive_standard
    movzx   rdi, byte [r10]
    cmp     dil, '%'
    jne     .lex_directive_standard
    
    ; It's %%
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    mov     r13, [rbx + LEXER_pos] ; start of identifier
    
.lex_macro_local_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_macro_local_done
    movzx   rdi, byte [r10]
    call    str_is_ident_char
    cmp     rax, TRUE
    jne     .lex_macro_local_done
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_macro_local_loop

.lex_macro_local_done:
    ; "%%x_%1": the parameter is pasted on (the preprocessor resolves both)
    mov     r10, [rbx + LEXER_pos]
    call    .glue_follows
    jne     .lex_macro_local_plain
    sub     r13, 2                         ; the text starts at the %%
    jmp     .lex_ident_interp
.lex_macro_local_plain:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13               ; length
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    mov     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_directive_standard:
    mov     r13, [rbx + LEXER_pos] ; start of directive name

    ; Check for braced directive %{...} (A69)
    movzx   rdi, byte [r13]
    cmp     dil, '{'
    je      .lex_braced_directive

.lex_directive_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_directive_done
    movzx   rdi, byte [r10]
    
    ; UTF-8 check
    cmp     rdi, 128
    jae     .lex_directive_utf8

    call    str_is_ident_char
    cmp     rax, TRUE
    jne     .lex_directive_done
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_directive_loop

.lex_directive_utf8:
    mov     rdi, [rbx + LEXER_pos]
    mov     rsi, [rbx + LEXER_end]
    call    str_utf8_decode
    test    rax, rax
    jz      .malformed_utf8_in_ident ; reuse same handler
    
    cmp     rdx, 0x9F
    jbe     .lex_directive_done
    
    add     [rbx + LEXER_pos], rax
    inc     word [rbx + LEXER_col]
    jmp     .lex_directive_loop

.lex_braced_directive:
    inc     qword [rbx + LEXER_pos] ; skip {
    inc     word  [rbx + LEXER_col]
    mov     r13, [rbx + LEXER_pos]  ; start of content

.lex_braced_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_braced_unterminated
    
    movzx   rdi, byte [r10]
    cmp     dil, '}'
    je      .lex_braced_done
    
    ; allow anything inside braces except newline? 
    ; actually, NASM allows many things. We'll allow anything but } and EOL.
    cmp     dil, 10
    je      .lex_braced_unterminated
    
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_braced_loop

.lex_braced_done:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13               ; length
    inc     qword [rbx + LEXER_pos] ; skip }
    inc     word  [rbx + LEXER_col]
    jmp     .dir_name               ; (not a parameter with a name glued on)

.lex_braced_unterminated:
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_unterminated_brace]
    call    error_emit
    mov     rax, EXIT_UNEXPECTED_EOF
    jmp     .fail

.lex_directive_done:
    ; a parameter with a name or another reference glued on (%1_end, %1h,
    ; %1%2): one interpolated name, from the %
    movzx   eax, byte [r13]
    sub     eax, '0'
    cmp     eax, 9
    ja      .dir_name                      ; a directive, not a parameter
    mov     r10, r13
.dir_digit:
    cmp     r10, [rbx + LEXER_pos]
    jae     .dir_digits_only
    movzx   eax, byte [r10]
    sub     eax, '0'
    cmp     eax, 9
    ja      .dir_glued                     ; name characters after the digits
    inc     r10
    jmp     .dir_digit
.dir_digits_only:
    mov     r10, [rbx + LEXER_pos]
    call    .glue_follows
    jne     .dir_name
.dir_glued:
    dec     r13                            ; the text starts at the %
    jmp     .lex_ident_interp
.dir_name:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13               ; length

    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

    ; directive names in any letter case: %DEFINE is %define
    xor     ecx, ecx
.directive_lc:
    cmp     rcx, r10
    jae     .directive_lc_done
    mov     al, [rdx + rcx]
    cmp     al, 'A'
    jb      .directive_lc_next
    cmp     al, 'Z'
    ja      .directive_lc_next
    or      byte [rdx + rcx], 0x20
.directive_lc_next:
    inc     rcx
    jmp     .directive_lc
.directive_lc_done:
    mov     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    mov     [r12 + TOKEN_value], rdx
    mov     word [r12 + TOKEN_len], r10w
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- unknown character ------------------
.unknown_char:
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_unknown_char]
    call    error_emit

    ; skip the bad character and continue
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    ; retry â€” tail call back to lexer_next
    mov     rdi, rbx
    mov     rsi, r12
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    jmp     lexer_next


; ---- shared helpers ---------------------

;
; .token_begin (internal)
; Initialises the output Token struct with tag, file, line, col.
; Uses rbx=LexerState, r12=Token output.
;
.token_begin:
    mov     byte [r12 + TOKEN_tag],   TAG_TOKEN
    mov     byte [r12 + TOKEN_kind],  TOK_UNKNOWN
    mov     byte [r12 + TOKEN_flags], 0
    mov     qword [r12 + TOKEN_value], 0

    ; copy line and col from lexer state
    mov     eax, dword [rbx + LEXER_line]
    mov     dword [r12 + TOKEN_line], eax
    movzx   eax, word [rbx + LEXER_col]
    mov     word [r12 + TOKEN_col], ax

    ; copy filename pointer
    mov     rax, [rbx + LEXER_file]
    mov     [r12 + TOKEN_file], rax

    mov     word [r12 + TOKEN_len], 0
    ret

;
; .skip_ignored (internal)
; Skips whitespace (space, tab, CR) and comments (; and ; *\/).
; Emits no tokens. Updates line and col counters.
; Uses rbx=LexerState.
;
.skip_ignored:
.skip_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .skip_done

    movzx   rcx, byte [r10]

    ; skip whitespace (Space, Tab, CR)
    test    byte [lexer_char_props + rcx], CHAR_IS_WHITESPACE
    jnz     .skip_ws

    ; a backslash with only blanks after it continues the line on the next
    ; one: both become one statement (db "a", \ <newline> "b")
    cmp     rcx, 0x5C                  ; backslash
    jne     .not_continuation
    lea     r11, [r10 + 1]
.cont_scan:
    cmp     r11, [rbx + LEXER_end]
    jge     .not_continuation
    movzx   eax, byte [r11]
    cmp     eax, 10
    je      .cont_join
    test    byte [lexer_char_props + rax], CHAR_IS_WHITESPACE
    jz      .not_continuation
    inc     r11
    jmp     .cont_scan
.cont_join:
    lea     rax, [r11 + 1]
    mov     [rbx + LEXER_pos], rax
    call    lexer_next_line
    mov     word [rbx + LEXER_col], 1
    jmp     .skip_loop
.not_continuation:

    ; check for ; comment
    cmp     rcx, ';'
    je      .skip_line_comment

    ; check for // comment
    cmp     rcx, '/'
    jne     .skip_check_block

    ; peek next char
    mov     r11, r10
    inc     r11
    cmp     r11, [rbx + LEXER_end]
    jge     .skip_done
    movzx   r11, byte [r11]
    cmp     r11, '/'
    jne     .skip_check_block
    call    lexer_slash_check              ; NASM's signed division?

.skip_line_comment:
    ; skip until LF
    inc     qword [rbx + LEXER_pos]
.skip_line_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .skip_done
    movzx   rcx, byte [r10]
    cmp     rcx, 10             ; LF â€” stop, don't consume
    je      .skip_loop
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .skip_line_loop

.skip_check_block:
    ; check for ; block comment
    cmp     rcx, '/'
    jne     .skip_done

    mov     r11, r10
    inc     r11
    cmp     r11, [rbx + LEXER_end]
    jge     .skip_done
    movzx   r11, byte [r11]
    cmp     r11, '*'
    jne     .skip_done

    ; skip block comment until ;
    add     qword [rbx + LEXER_pos], 2
.skip_block_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .skip_block_unterminated
    
    movzx   rcx, byte [r10]
    IF rcx, e, 10
        inc dword [rbx + LEXER_line]
        mov word [rbx + LEXER_col], 1
        ELSE
        inc word [rbx + LEXER_col]
        ENDIF

    cmp     rcx, '*'
    jne     .skip_block_next
    
    ; peek for /
    mov     r11, r10
    inc     r11
    cmp     r11, [rbx + LEXER_end]
    jge     .skip_block_unterminated
    movzx   r11, byte [r11]
    cmp     r11, '/'
    je      .skip_block_done

.skip_block_next:
    inc     qword [rbx + LEXER_pos]
    jmp     .skip_block_loop

.skip_block_done:
    add     qword [rbx + LEXER_pos], 2 ; skip ;
    add     word [rbx + LEXER_col], 2
    jmp     .skip_loop

.skip_block_unterminated:
    ; unterminated block comment â€” emit error
    mov     rdi, [rbx + LEXER_ctx]
    mov     rsi, [rbx + LEXER_file]
    mov     edx, dword [rbx + LEXER_line]
    movzx   rcx, word  [rbx + LEXER_col]
    lea     r8,  [msg_unterminated_comment]
    call    error_emit
    mov     rax, EXIT_UNEXPECTED_EOF
    jmp     .skip_done

.skip_ws:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .skip_loop

.skip_done:
    xor     rax, rax
    ret

.fail:
    mov     rax, EXIT_ERROR
    jmp     .cleanup

.bad_lexer:
    mov     rax, EXIT_INTERNAL
    jmp     .cleanup

.done:
.cleanup:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret


; ---- lexer_peek -------------------------
;
; lexer_peek
; Returns the next token without consuming it.
; Subsequent calls to lexer_peek return the same token.
; Subsequent calls to lexer_next consume and return it.
; Input    : rdi = pointer to LexerState
;             rsi = pointer to Token struct to fill
; Output   : rax = EXIT_OK or error code
;              rdx = pointer to filled Token (same as rsi)
; Clobbers : rcx, r8, r9, r10, r11
;
global lexer_peek
lexer_peek:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15


    mov     rbx, rdi
    mov     r12, rsi

    ; if peek slot already valid â€” copy it out
    cmp     byte [rbx + LEXER_has_peek], TRUE
    jne     .do_peek

    lea     rsi, [rbx + LEXER_peek]
    mov     rdi, r12
    copy_token                     ; (mem_copy, for 32 bytes)

    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.do_peek:
    ; lex into the inline peek slot
    mov     rdi, rbx
    lea     rsi, [rbx + LEXER_peek]
    call    lexer_next
    test    rax, rax
    jnz     .fail

    ; mark peek valid
    mov     byte [rbx + LEXER_has_peek], TRUE

    ; copy to caller output
    lea     rsi, [rbx + LEXER_peek]
    mov     rdi, r12
    copy_token                     ; (mem_copy, for 32 bytes)

    xor     rax, rax
    mov     rdx, r12

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.fail:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret


; ---- lexer_expect -----------------------
;
; lexer_expect
; Reads the next token and verifies it matches the expected kind.
; Emits an error if it does not match.
; Input    : rdi = pointer to LexerState
;             rsi = pointer to Token struct to fill
;             rdx = expected TOK_* kind value
; Output   : rax = EXIT_OK or EXIT_UNEXPECTED_TOKEN
;              rdx = pointer to filled Token
; Clobbers : rcx, r8, r9, r10, r11
;
global lexer_expect
lexer_expect:
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi               ; R12 = LexerState
    mov     r13, rdx               ; R13 = expected kind

    call    lexer_next
    test    rax, rax
    jnz     .fail

    ; check kind matches
    ; RDX = pointer to returned token
    movzx   rcx, byte [rdx + TOKEN_kind]
    cmp     rcx, r13
    je      .match

    ; mismatch â€” emit error
    mov     rbx, rdx               ; RBX = Token pointer
    mov     rdi, [r12 + LEXER_ctx]
    mov     rsi, [rbx + TOKEN_file]
    mov     edx, dword [rbx + TOKEN_line]
    movzx   rcx, word  [rbx + TOKEN_col]
    lea     r8,  [msg_unexpected_token]
    call    error_emit

    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .fail

.match:
    xor     rax, rax

.fail:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- lexer_destroy ----------------------
;
; lexer_destroy
; Clears a LexerState struct. Does not free the source buffer
; (caller owns it) or the arena (shared with whole pass).
; Input    : rdi = pointer to LexerState
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : rcx, rdx
;
global lexer_destroy
lexer_destroy:
    cmp     byte [rdi + LEXER_tag], TAG_LEXER
    jne     .bad_lexer

    mov     rsi, LEXER_SIZE
    call    mem_zero

    xor     rax, rax
    ret

.bad_lexer:
    mov     rax, EXIT_INTERNAL
    ret

; ============================================================================
; DATA
; ============================================================================

[SECTION .data]

msg_unterminated_string:
    db      "unterminated string literal", 0

msg_unterminated_char:
    db      "unterminated character literal", 0

msg_unterminated_comment:
    db      "unterminated block comment", 0

msg_unknown_char:
    db      "unknown character in source", 0

msg_unexpected_token:
    db      "unexpected token", 0
msg_string_too_long:
    db      "string literal too long", 0
msg_malformed_utf8:
    db      "malformed UTF-8 sequence", 0
msg_unterminated_brace:
    db      "unterminated braced directive", 0

; ============================================================================
; CHARACTER PROPERTIES LOOKUP TABLE (LUT)
; ============================================================================

global lexer_char_props
lexer_char_props:
    %assign i 0
    %rep 256
    %assign mask 0
    %if i >= '0' && i <= '9'
    %assign mask mask | CHAR_IS_DIGIT | CHAR_IS_IDENT_PART | CHAR_IS_HEX
    %elif (i >= 'a' && i <= 'f') || (i >= 'A' && i <= 'F')
    %assign mask mask | CHAR_IS_IDENT_START | CHAR_IS_IDENT_PART | CHAR_IS_HEX
    %elif (i >= 'g' && i <= 'z') || (i >= 'G' && i <= 'Z') || i == '_' || i == '.'
    %assign mask mask | CHAR_IS_IDENT_START | CHAR_IS_IDENT_PART
    %elif i == ' ' || i == 9 || i == 13
    %assign mask mask | CHAR_IS_WHITESPACE
    %endif
        db mask
    %assign i i+1
    %endrep

[SECTION .text]

; ---- lexer_slash_check (internal) --------
; A "//" at r10 begins a comment in utasm; NASM reads "x // 2" as a signed
; division. When an operand ends just before it and only a number, or an
; expression in parentheses, follows it on the line ("mov eax, -7 // 2",
; "dd n // (k + 1)"), the code means something else to NASM: a warning
; (slash-comment). A comment in words ("// 2 bytes", "// done") gets none.
; Input: rbx = LEXER, r10 = the first '/'. Preserves every register.
lexer_slash_check:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    ; before it, past blanks: the end of an operand
    mov     rsi, r10
.back:
    cmp     rsi, [rbx + LEXER_buf]
    jbe     .out
    dec     rsi
    movzx   edi, byte [rsi]
    cmp     edi, ' '
    je      .back
    cmp     edi, 9
    je      .back
    cmp     edi, ')'
    je      .after
    call    str_is_ident_char
    test    rax, rax
    jz      .out
.after:
    ; after it, past blanks (and a minus sign): a number alone, or (...)
    lea     rsi, [r10 + 2]
    mov     rdx, [rbx + LEXER_end]
    call    .blanks
    cmp     rsi, rdx
    jae     .out
    cmp     byte [rsi], '-'
    jne     .operand
    inc     rsi
    call    .blanks
    cmp     rsi, rdx
    jae     .out
.operand:
    movzx   eax, byte [rsi]
    cmp     eax, '('
    je      .paren
    sub     eax, '0'
    cmp     eax, 9
    ja      .out
.number:
    ; 2, 0x10, 10h, 1_000: letters, digits and underscores
    inc     rsi
    cmp     rsi, rdx
    jae     .warn
    movzx   edi, byte [rsi]
    cmp     edi, '_'
    je      .number
    cmp     edi, '.'
    je      .out                           ; 2.5: not an integer division
    call    str_is_ident_char
    test    rax, rax
    jnz     .number
    jmp     .rest
.paren:
    ; the last character on the line, past blanks, closes it
    mov     r8, rsi
.eol:
    cmp     r8, rdx
    jae     .eol_found
    cmp     byte [r8], 10
    je      .eol_found
    inc     r8
    jmp     .eol
.eol_found:
    cmp     r8, rsi
    jbe     .out
    dec     r8
    movzx   eax, byte [r8]
    cmp     eax, ' '
    je      .eol_found
    cmp     eax, 9
    je      .eol_found
    cmp     eax, 13
    je      .eol_found
    cmp     eax, ')'
    jne     .out
    jmp     .warn
.rest:
    ; nothing else on the line
    call    .blanks
    cmp     rsi, rdx
    jae     .warn
    movzx   eax, byte [rsi]
    cmp     eax, 13
    je      .warn
    cmp     eax, 10
    jne     .out
.warn:
    mov     edi, WC_SLASH_COMMENT
    extern  warn_begin, warn_text, warn_end
    call    warn_begin
    lea     rsi, [rel s_slash_comment]
    call    warn_text
    call    warn_end
.out:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret
; .blanks: rsi past spaces and tabs (rdx = the end)
.blanks:
    cmp     rsi, rdx
    jae     .blanks_done
    cmp     byte [rsi], ' '
    je      .blank
    cmp     byte [rsi], 9
    jne     .blanks_done
.blank:
    inc     rsi
    jmp     .blanks
.blanks_done:
    ret

[SECTION .rodata]
s_slash_comment: db "`//' starts a comment here; NASM reads it as a signed division", 0

[SECTION .bss]
lex_char_start: resq 1              ; first character of a quoted literal
lex_char_count: resq 1              ; its characters so far
lex_quote:     resb 1              ; the quote a string literal ends with
