;
; ============================================
; File     : src/frontend/lexer/lexer.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

DEFAULT REL

extern arena_alloc
extern att_on                   ; src/frontend/syntax/gas/att.s: AT&T syntax on
extern arena_alloc_string
extern error_report_line
extern mem_copy
extern mem_zero
extern str_is_hex_digit
extern str_is_ident_char
extern str_ident_chars
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
;   lexer_init â†’ lexer_next (repeated) â†’ lexer_peek
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
; Error handling: a byte no token starts with, bytes that are not UTF-8,
;   a string, character constant or %{ with no closing quote or } on its
;   line, a /* with no */, a string over LEX_STR_MAX bytes - each reported
;   at its line by error_report_line (diag/codes.s) and counted; lexing
;   goes on (the byte skipped, the literal ended at the line's end), and
;   the assembly fails at its end. lexer_next itself fails only when the
;   arena is out of memory.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result
;   callee saved: rbx, r12-r15, rbp

extern  str_cmp

%define LEX_STR_FIRST  64              ; a string buffer's first size, doubled as it fills
%define LEX_STR_MAX    65535           ; the longest string (TOKEN_len is 16 bits)
%define LEX_STR_ROOM   (LEX_STR_MAX + 6) ; its buffer then: a step's 4 bytes and the NUL

[SECTION .rodata]
gas_str_words: db ".ascii", 0, ".asciz", 0, ".string", 0, 0

[SECTION .bss]
lex_gas_str:    resb 1          ; 1: the line is a GNU string directive's
global lexer_mark_lone
lexer_mark_lone: resb 1         ; 1: TOK_FLAG_LONE on newlines (-E, prep_dump)

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
    mov     byte [rdi + LEXER_pushed], 0

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
    call    .att_active
    jne     .pct_nasm
    call    .att_register              ; "%eax", "%st", "%fs": a name
    je      .lex_att_reg
.pct_nasm:
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
    ; ... or the end of its line ("%iftoken %": one token, NASM's iftoken)
    cmp     byte [r11], 10
    je      .emit_single_percent
    cmp     byte [r11], 13
    je      .emit_single_percent
    ; "%(": a data list's percent (db %(1, 2)); no directive is named so
    cmp     byte [r11], '('
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

    ; AT&T: "$" before an immediate is a token of its own ($10 is ten, not
    ; NASM's hex), ";" ends a statement as a line does
    cmp     rcx, '$'
    je      .att_dollar
    cmp     rcx, ';'
    je      .att_separator
.not_att_char:

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
    mov     edi, EXIT_LEX_BAD_UTF8
    xor     ecx, ecx
    mov     byte [rel lex_bad_utf8], 1
    jmp     .bad_byte

; ---- EOF --------------------------------
.emit_eof:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_EOF
    cmp     byte [rel lexer_mark_lone], 0
    je      .eof_marked
    ; -E: a last line with no newline after it, of nothing but blanks or a
    ; comment, is written too
    call    .line_blank
    test    eax, eax
    jz      .eof_marked
    test    edx, edx
    jz      .eof_marked
    or      byte [r12 + TOKEN_flags], TOK_FLAG_LONE
.eof_marked:
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

; ---- newline ----------------------------
.emit_newline:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_NEWLINE
    mov     byte [rel lex_gas_str], 0
    cmp     byte [rel lexer_mark_lone], 0
    je      .newline_marked
    cmp     byte [rbx + LEXER_pushed], 0
    jne     .newline_marked
    ; -E: a line of nothing but blanks or a comment is written (NASM's
    ; empty line); a directive's is not
    call    .line_blank
    test    eax, eax
    jz      .newline_marked
    or      byte [r12 + TOKEN_flags], TOK_FLAG_LONE
.newline_marked:
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
    ; "::x": the name x outside every namespace, one identifier
    mov     r10, [rbx + LEXER_pos]
    call    .ns_colons
    jne     .single_colon
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]
    add     qword [rbx + LEXER_pos], 2
    add     word [rbx + LEXER_col], 2
    jmp     .lex_ident_loop
.single_colon:
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

; ---- AT&T syntax (src/frontend/syntax/gas/att.s) --
.att_dollar:
    call    .att_active
    jne     .not_att_char
    jmp     .dollar_alone
.att_separator:
    ; (skip_ignored took ";" for a comment when not AT&T)
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_NEWLINE
    mov     byte [rel lex_gas_str], 0
    jmp     .advance_single
.lex_att_reg:
    ; the name with its "%": the translation knows a register by it
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_ident_loop

; .att_active: ZF = 1 when this text is read as AT&T (.att_syntax or --att,
; and not text utasm made in its own syntax). Preserves all but the flags.
.att_active:
    cmp     byte [rel att_on], 0
    je      .att_off
    cmp     byte [rbx + LEXER_intel], 0
    ret
.att_off:
    cmp     byte [rel att_on], 1
    ret

; .att_register: ZF = 1 when the "%" at LEXER_pos starts a register: a
; letter after it, and not the first thing on its line (a directive there:
; %define, %include). Preserves all but the flags.
.att_register:
    push    rax
    push    r10
    mov     r10, [rbx + LEXER_pos]
    lea     rax, [r10 + 1]
    cmp     rax, [rbx + LEXER_end]
    jae     .attr_no
    movzx   eax, byte [r10 + 1]
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 25
    ja      .attr_no
.attr_back:
    cmp     r10, [rbx + LEXER_buf]
    jbe     .attr_no                       ; the buffer's start: a directive
    movzx   eax, byte [r10 - 1]
    cmp     eax, 10
    je      .attr_no
    cmp     eax, ' '
    je      .attr_blank
    cmp     eax, 9
    je      .attr_blank
    cmp     eax, 13
    jne     .attr_yes
.attr_blank:
    dec     r10
    jmp     .attr_back
.attr_yes:
    xor     eax, eax                       ; ZF = 1
    pop     r10
    pop     rax
    ret
.attr_no:
    or      eax, 1                         ; ZF = 0
    pop     r10
    pop     rax
    ret

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
; .ns_colons: ZF = 1 when r10 is at "::" and a name's first character
; (not '.'). Preserves all but rax, rdi
.ns_colons:
    lea     rax, [r10 + 3]
    cmp     rax, [rbx + LEXER_end]
    ja      .ns_no
    cmp     word [r10], '::'
    jne     .ns_ret
    movzx   edi, byte [r10 + 2]
    cmp     edi, '.'
    je      .ns_no
    test    byte [lexer_char_props + rdi], CHAR_IS_IDENT_START
    jz      .ns_no
    cmp     eax, eax
.ns_ret:
    ret
.ns_no:
    test    esp, esp
    ret

.lex_ident:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]     ; start of identifier

    ; scan while ident chars (str_is_ident_char's table), the position in
    ; a register: one column a byte
.lex_ident_loop:
    mov     r10, [rbx + LEXER_pos]
.lex_ident_scan:
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_ident_at
    movzx   edi, byte [r10]
    cmp     byte [str_ident_chars + rdi], 0
    je      .lex_ident_ns
    inc     r10
    jmp     .lex_ident_scan
.lex_ident_ns:
    ; "net::send": a namespace's name goes on through "::" and a name
    ; (src/semantic/namespace.s)
    call    .ns_colons
    jne     .lex_ident_at
    add     r10, 2
    jmp     .lex_ident_scan
.lex_ident_at:
    mov     rax, r10
    sub     rax, [rbx + LEXER_pos]
    add     [rbx + LEXER_col], ax
    mov     [rbx + LEXER_pos], r10
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_ident_done
    ; UTF-8 check
    cmp     byte [r10], 128
    jae     .lex_ident_utf8
    jmp     .lex_ident_done

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
    ; GNU's .ascii / .asciz / .string: their "..." strings keep \" and \\
    ; as written, to the end of the line (src/frontend/syntax/gas/gas.s reads the
    ; escapes) - "\"" does not end one
    mov     rdi, [r12 + TOKEN_value]
    cmp     byte [rdi], '.'
    jne     .ident_out
    lea     rsi, [rel gas_str_words]
.ident_gas_word:
    cmp     byte [rsi], 0
    je      .ident_out
    mov     rdi, [r12 + TOKEN_value]
    call    str_cmp
    test    rax, rax
    jz      .ident_gas_str
.ident_gas_next:
    inc     rsi
    cmp     byte [rsi - 1], 0
    jne     .ident_gas_next
    jmp     .ident_gas_word
.ident_gas_str:
    mov     byte [rel lex_gas_str], 1
.ident_out:
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
    ; "%$_ur%$_uses", "%$x_%1": what follows is pasted on - one name
    mov     r10, [rbx + LEXER_pos]
    call    .glue_follows
    je      .lex_ident_interp              ; (r13: the text from the %)
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
    push    r11
    xor     r11d, r11d                     ; "%[foo%[foo3]bar]": brackets inside

.interp_val_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_val_end
    cmp     byte [r10], '['
    jne     .interp_val_rb
    inc     r11d
    jmp     .interp_val_next
.interp_val_rb:
    cmp     byte [r10], ']'
    jne     .interp_val_next
    test    r11d, r11d
    jz      .interp_val_close
    dec     r11d
.interp_val_next:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_val_loop

.interp_val_close:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
.interp_val_end:
    pop     r11

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
    cmp     al, '+'
    je      .interp_cc
    cmp     al, '-'
    je      .interp_cc
    sub     eax, '0'
    cmp     eax, 9
    jbe     .interp_digits
    cmp     byte [r11], '['
    jne     .interp_finish

    ; consume "%[" ... "]", a "%[" ... "]" inside it included
    ; ("foo%[foo%[n]]", NASM's ppindirect)
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    push    r11
    xor     r11d, r11d                     ; brackets open inside
.interp_name_loop:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jge     .interp_name_end
    cmp     byte [r10], '['
    jne     .interp_name_close
    inc     r11d
    jmp     .interp_name_next
.interp_name_close:
    cmp     byte [r10], ']'
    jne     .interp_name_next
    test    r11d, r11d
    jz      .interp_name_done
    dec     r11d
.interp_name_next:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_name_loop
.interp_name_end:
    pop     r11
    jmp     .interp_finish

.interp_name_done:
    pop     r11
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .interp_scan

.interp_two:
    ; "%%" / "%$": the name that follows is scanned on
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    jmp     .interp_scan
.interp_cc:
    ; "%+1" / "%-1": a condition code parameter, if a digit follows
    lea     r11, [r10 + 2]
    cmp     r11, [rbx + LEXER_end]
    jge     .interp_finish
    movzx   eax, byte [r11]
    sub     eax, '0'
    cmp     eax, 9
    ja      .interp_finish
    jmp     .interp_two
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
; interpolation: %[...], %N, %{...}, %%name, %$name. Clobbers rax, r11.
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
    cmp     al, '$'
    je      .glue_local                    ; "x_%$name" (and %$$name)
    cmp     al, '+'
    je      .glue_cc
    cmp     al, '-'
    je      .glue_cc
    sub     eax, '0'
    cmp     eax, 9
    ja      .glue_no
.glue_yes:
    cmp     eax, eax
    ret
.glue_local:
    ; "%%" / "%$" then a name (not the "%%" modulo operator)
    lea     r11, [r10 + 2]
    cmp     r11, [rbx + LEXER_end]
    jae     .glue_no
    cmp     byte [r11], '$'
    je      .glue_yes                      ; %$$name
    push    rdi
    movzx   edi, byte [r11]
    call    str_is_ident_char
    pop     rdi
    cmp     rax, TRUE
    ret
.glue_cc:
    ; "j%-1": a parameter as a condition code (%+1), or its inverse (%-1)
    lea     r11, [r10 + 2]
    cmp     r11, [rbx + LEXER_end]
    jae     .glue_no
    movzx   eax, byte [r11]
    sub     eax, '0'
    cmp     eax, 9
    ja      .glue_no
    cmp     eax, eax
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

; what a byte is in a number (lexer_num_class)
%define NUM_DIGIT   1                  ; a digit, a radix letter, _
%define NUM_FLOAT   2                  ; . p P
%define NUM_SUFFIX  3                  ; u U l L
%define NUM_SIGN    4                  ; + -
.lex_number_loop:
    ; the run of digits and radix letters (hex digits, x b o h q y t, _)
    ; scanned with the position in a register (lexer_num_class)
    mov     r10, [rbx + LEXER_pos]
    lea     rdi, [rel lexer_num_class]
.lex_number_scan:
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_number_at
    movzx   eax, byte [r10]
    movzx   eax, byte [rdi + rax]
    cmp     eax, NUM_DIGIT
    jne     .lex_number_at
    inc     r10
    jmp     .lex_number_scan
.lex_number_at:
    mov     rcx, r10
    sub     rcx, [rbx + LEXER_pos]
    add     [rbx + LEXER_col], cx
    mov     [rbx + LEXER_pos], r10
    cmp     r10, [rbx + LEXER_end]
    jge     .lex_number_done

    ; float markers (. p P; e E are hex digits - "1e3" is read after)
    cmp     eax, NUM_FLOAT
    je      .is_float
    ; signs can appear after e/p, and only there: otherwise "4+8" would lex
    ; as a single number token
    ; integer size suffixes (1ULL, 32u, 5L) are consumed but are not part
    ; of the numeric text handed to str_to_int
    cmp     eax, NUM_SUFFIX
    je      .lex_number_suffix
    cmp     eax, NUM_SIGN
    je      .lex_number_sign
    jmp     .lex_number_done

.lex_number_sign:
    cmp     r10, r13               ; need a preceding character
    jbe     .lex_number_done
    movzx   rax, byte [r10 - 1]
    cmp     al, 'e'
    je      .lex_number_e_sign
    cmp     al, 'E'
    je      .lex_number_e_sign
    cmp     al, 'p'
    je      .lex_number_advance
    cmp     al, 'P'
    je      .lex_number_advance
    jmp     .lex_number_done
.lex_number_e_sign:
    ; in a hex number "e" is a digit: "$1e+16" is $1e plus 16 (NASM's)
    cmp     byte [r13], '$'
    je      .lex_number_done
    cmp     byte [r13], '0'
    jne     .lex_number_advance
    movzx   eax, byte [r13 + 1]
    or      eax, 0x20
    cmp     eax, 'x'
    je      .lex_number_done
    cmp     eax, 'h'
    je      .lex_number_done
    jmp     .lex_number_advance

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
    cmp     eax, '_'
    je      .fe_digit                      ; "1_0e16"
    sub     eax, '0'
    cmp     eax, 9
    ja      .fe_e
.fe_digit:
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
    cmp     eax, '_'
    je      .fe_exp_digits                 ; "1e1_6"
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

    ; the string's bytes: a buffer that doubles as it fills (it was
    ; MAX_LINE, which a long string overran), up to the longest a token
    ; holds - TOKEN_len is 16 bits
    mov     rdi, [rbx + LEXER_arena]
    mov     esi, LEX_STR_FIRST
    mov     [rel lex_str_cap], rsi
    call    arena_alloc
    test    rax, rax
    jnz     .fail

    mov     r13, rdx               ; r13 = string output buffer
    xor     r10, r10               ; r10 = output length
    mov     byte [rel lex_str_over], 0

.lex_string_loop:
    cmp     r10, LEX_STR_MAX
    ja      .lex_string_too_long
    lea     rax, [r10 + 5]         ; a step writes at most 4 bytes (\U), then the NUL
    cmp     rax, [rel lex_str_cap]
    ja      .lex_string_grow
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
    mov     byte [r13 + r10], cl
inc     r10
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_string_loop

.lex_string_grow:
    mov     rsi, [rel lex_str_cap]
    add     rsi, rsi
    cmp     rsi, LEX_STR_ROOM
    jbe     .grow_size
    mov     esi, LEX_STR_ROOM
.grow_size:
    mov     [rel lex_str_cap], rsi
    push    r10
    mov     rdi, [rbx + LEXER_arena]
    call    arena_alloc
    pop     r10
    test    rax, rax
    jnz     .fail
    mov     rdi, rdx               ; (the old buffer stays in the arena)
    mov     rsi, r13
    mov     rcx, r10
    mov     r13, rdx
    rep movsb
    jmp     .lex_string_loop

.lex_string_too_long:
    ; said once; the rest is read and dropped (the assembly fails, what
    ; the token holds no longer matters)
    cmp     byte [rel lex_str_over], 0
    jne     .string_over
    mov     byte [rel lex_str_over], 1
    mov     edi, EXIT_LEX_STRING_LONG
    mov     rsi, [rbx + LEXER_file]
    mov     edx, [rbx + LEXER_line]
    xor     ecx, ecx
    call    error_report_line
.string_over:
    xor     r10d, r10d
    jmp     .lex_string_loop

.lex_string_escape:
    ; "..." is verbatim, as in NASM: only `...` has escapes. A backslash
    ; that ends the line still continues it.
    cmp     byte [rel lex_quote], 0x60
    je      .escape_on
    ; a GNU string (lex_gas_str): \" and \\ kept, the pair as written
    cmp     byte [rel lex_gas_str], 0
    je      .nasm_backslash
    mov     r11, [rbx + LEXER_pos]
    lea     rax, [r11 + 1]
    cmp     rax, [rbx + LEXER_end]
    jge     .nasm_backslash
    movzx   eax, byte [r11 + 1]
    cmp     eax, '"'
    je      .gas_pair
    cmp     eax, '\'
    jne     .nasm_backslash
.gas_pair:
    mov     byte [r13 + r10], '\'
mov     [r13 + r10 + 1], al
    add     r10, 2
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col], 2
    jmp     .lex_string_loop
.nasm_backslash:
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
    call    .close_quote

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
    ; no closing quote on its line: the string is what is there (as NASM
    ; reads it), the error counted
    mov     al, [rel lex_quote]
    call    .open_quote
    jmp     .lex_string_done

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
    cmp     rcx, 10                ; and the line's end, unclosed (it ran on
    je      .lex_char_unterminated ; into the next line, to its first ')

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
    call    .close_quote

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
    call    .close_quote
mov     byte [r12 + TOKEN_kind], TOK_STRING
    mov     byte [r12 + TOKEN_quote], 0x27
    mov     [r12 + TOKEN_value], rdx
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.lex_char_unterminated:
    mov     al, 0x27
    call    .open_quote
    jmp     .lex_char_closing

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
    ; "%,": NASM's conditional comma (the preprocessor's prep_function)
    cmp     dil, ','
    jne     .lex_directive_loop
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .dir_name

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
    call    .close_quote           ; the }
; "%{1}0", "%{1}_end", "%{1}%{2}": a parameter with what follows it
    ; pasted on, as NASM pastes it - one interpolated name, from the %
    test    r10, r10
    jz      .dir_name
    ; "%{$name}", "%{$name}%1": a context-local, a name of its own (its
    ; %define's text when it has one: prep_resolve_interp)
    cmp     byte [r13], '$'
    jne     .braced_number
    sub     r13, 2                         ; the text starts at the %
    jmp     .lex_ident_interp
.braced_number:
    xor     ecx, ecx
.braced_digit:
    movzx   eax, byte [r13 + rcx]
    sub     eax, '0'
    cmp     eax, 9
    ja      .dir_name                      ; not a parameter's number
    inc     ecx
    cmp     rcx, r10
    jb      .braced_digit
    push    r10
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jae     .braced_plain
    call    .glue_follows
    je      .braced_glued
    movzx   edi, byte [r10]
    call    str_is_ident_char
    cmp     rax, TRUE
    je      .braced_glued
.braced_plain:
    pop     r10
    jmp     .dir_name
.braced_glued:
    pop     r10
    sub     r13, 2                         ; the text starts at the %
    jmp     .lex_ident_interp

.lex_braced_unterminated:
    ; the name is what there is to the line's end
    push    r13
    mov     edi, EXIT_LEX_OPEN_BRACE
    mov     rsi, [rbx + LEXER_file]
    mov     edx, [rbx + LEXER_line]
    xor     ecx, ecx
    call    error_report_line
    pop     r13
    mov     byte [rel lex_open], 1
    jmp     .lex_braced_done

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
    ; a byte no token starts with: "invalid character `\' in the source",
    ; a control character by its value, "(byte 0x01)"
    mov     r10, [rbx + LEXER_pos]
    movzx   eax, byte [r10]
    lea     rcx, [rel lex_byte_text]
    cmp     eax, 0x21
    jb      .bad_hex
    cmp     eax, 0x7E
    ja      .bad_hex
    mov     byte [rcx], 0x60
    mov     [rcx + 1], al
    mov     byte [rcx + 2], 0x27
    mov     byte [rcx + 3], 0
    jmp     .bad_named
.bad_hex:
    mov     rdx, '(byte 0x'
    mov     [rcx], rdx
    lea     r8, [rel lex_hex]
    mov     edx, eax
    shr     edx, 4
    mov     dl, [r8 + rdx]
    mov     [rcx + 8], dl
    and     eax, 15
    mov     al, [r8 + rax]
    mov     [rcx + 9], al
    mov     word [rcx + 10], ')'
.bad_named:
    mov     edi, EXIT_LEX_BAD_CHAR
    mov     byte [rel lex_bad_utf8], 0
.bad_byte:
    ; reported and counted (the assembly fails at its end), and skipped
    ; with the run of bad bytes after it - one error a run: after bytes
    ; that are not UTF-8, every byte >= 0x80; after a control character,
    ; the control characters (not tab, LF, CR) and continuation bytes
    mov     rsi, [rbx + LEXER_file]
    mov     edx, [rbx + LEXER_line]
    call    error_report_line
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
.bad_byte_more:
    mov     r10, [rbx + LEXER_pos]
    cmp     r10, [rbx + LEXER_end]
    jae     .bad_byte_skipped
    movzx   eax, byte [r10]
    cmp     byte [rel lex_bad_utf8], 0
    je      .bad_ctl
    cmp     eax, 0x80
    jae     .bad_byte_next
    jmp     .bad_byte_skipped
.bad_ctl:
    cmp     eax, 0x7F
    je      .bad_byte_next
    mov     ecx, eax
    and     ecx, 0xC0
    cmp     ecx, 0x80
    je      .bad_byte_next                 ; (a continuation byte)
    cmp     eax, 0x20
    jae     .bad_byte_skipped
    cmp     eax, 9
    je      .bad_byte_skipped
    cmp     eax, 10
    je      .bad_byte_skipped
    cmp     eax, 13
    je      .bad_byte_skipped
.bad_byte_next:
    inc     qword [rbx + LEXER_pos]
    jmp     .bad_byte_more
.bad_byte_skipped:

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
    ; where it starts in the buffer
    mov     rax, [rbx + LEXER_pos]
    sub     rax, [rbx + LEXER_buf]
    mov     [r12 + TOKEN_offset], eax
    ; a blank before it (-E, %str)
    jz      .begin_flat
    add     rax, [rbx + LEXER_buf]
    movzx   eax, byte [rax - 1]
    cmp     eax, ' '
    je      .begin_space
    cmp     eax, 9
    jne     .begin_flat
.begin_space:
    mov     byte [r12 + TOKEN_flags], TOK_FLAG_SPACE
.begin_flat:

    mov     word [r12 + TOKEN_len], 0
    ret

;
; .line_blank (internal): eax = 1 when the line the lexer is at the end of
; holds nothing but blanks or a comment (its first character not a blank
; is none or ";"), edx = how many characters it has. Clobbers rcx, rsi
;
.line_blank:
    mov     rcx, [rbx + LEXER_pos]
    xor     eax, eax
    xor     edx, edx
.blank_back:
    cmp     rcx, [rbx + LEXER_buf]
    jbe     .blank_start
    dec     rcx
    movzx   esi, byte [rcx]
    cmp     esi, 10
    je      .blank_start
    inc     edx
    cmp     esi, ' '
    je      .blank_back
    cmp     esi, 9
    je      .blank_back
    cmp     esi, 13
    je      .blank_back
    mov     eax, esi
    jmp     .blank_back
.blank_start:
    test    eax, eax
    jz      .blank_yes
    cmp     eax, ';'
    jne     .blank_no
.blank_yes:
    mov     eax, 1
    ret
.blank_no:
    xor     eax, eax
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

    ; check for ; comment (AT&T: a statement's end; # a comment anywhere)
    cmp     rcx, ';'
    jne     .not_semicolon
    call    .att_active
    je      .skip_done
    jmp     .skip_line_comment
.not_semicolon:
    cmp     rcx, '#'
    jne     .not_att_hash
    call    .att_active
    je      .skip_line_comment
.not_att_hash:

    ; GNU's "# ..." comment line (x86 only: a "#" first on its line - NASM
    ; takes none there; GCC's "# 1 \"a.c\"" markers too). Elsewhere on a
    ; line "#" is a token (stringizing in a macro body); AArch64 and RISC-V
    ; write immediates so.
    cmp     rcx, '#'
    jne     .not_hash_line
    mov     rax, [rbx + LEXER_ctx]
    test    rax, rax
    jz      .not_hash_line
    cmp     byte [rax + ASMCTX_target], TARGET_AMD64
    jne     .not_hash_line
    mov     r11, r10
.hash_back:
    cmp     r11, [rbx + LEXER_buf]
    jbe     .skip_line_comment
    movzx   eax, byte [r11 - 1]
    cmp     eax, 10
    je      .skip_line_comment
    cmp     eax, ' '
    je      .hash_prev
    cmp     eax, 9
    je      .hash_prev
    cmp     eax, 13
    jne     .not_hash_line
.hash_prev:
    dec     r11
    jmp     .hash_back
.not_hash_line:

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
    mov     eax, [rbx + LEXER_line]
    mov     [rel lex_comment_line], eax    ; (an unterminated one is said here)
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
    ; at the line it starts on; the rest of the file is the comment
    mov     edi, EXIT_LEX_OPEN_COMMENT
    mov     rsi, [rbx + LEXER_file]
    mov     edx, [rel lex_comment_line]
    xor     ecx, ecx
    call    error_report_line
    mov     rax, [rbx + LEXER_end]
    mov     [rbx + LEXER_pos], rax
    jmp     .skip_done

.skip_ws:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .skip_loop

.skip_done:
    xor     rax, rax
    ret

; .open_quote: a quoted literal with no closing quote on its line (al = the
; quote): "unterminated string (missing `"')", counted; lex_open makes
; .close_quote skip nothing. .close_quote: past the closing quote (or }).
; Both keep r10 and r13.
.open_quote:
    push    r10
    push    r13
    mov     [rel lex_quote_text], al
    mov     edi, EXIT_LEX_OPEN_STRING
    mov     rsi, [rbx + LEXER_file]
    mov     edx, [rbx + LEXER_line]
    lea     rcx, [rel lex_quote_text]
    call    error_report_line
    mov     byte [rel lex_open], 1
    pop     r13
    pop     r10
    ret
.close_quote:
    cmp     byte [rel lex_open], 0
    jne     .close_open
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    ret
.close_open:
    mov     byte [rel lex_open], 0
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

; ============================================================================
; DATA
; ============================================================================

[SECTION .data]

lex_byte_text:  times 12 db 0       ; a bad byte, for its error (.unknown_char)
lex_quote_text: db 0, 0             ; the missing quote, for its error

[SECTION .rodata]
lex_hex:        db "0123456789abcdef"

; ============================================================================
; CHARACTER PROPERTIES LOOKUP TABLE (LUT)
; ============================================================================

global lexer_char_props
; what a byte is in a number (.lex_number_loop: NUM_*)
lexer_num_class:
    %assign i 0
    %rep 256
    %if (i >= '0' && i <= '9') || (i >= 'a' && i <= 'f') || (i >= 'A' && i <= 'F') || i == 'x' || i == 'X' || i == 'o' || i == 'O' || i == 'h' || i == 'H' || i == 'q' || i == 'Q' || i == 'y' || i == 'Y' || i == 't' || i == 'T' || i == '_'
        db NUM_DIGIT
    %elif i == '.' || i == 'p' || i == 'P'
        db NUM_FLOAT
    %elif i == 'u' || i == 'U' || i == 'l' || i == 'L'
        db NUM_SUFFIX
    %elif i == '+' || i == '-'
        db NUM_SIGN
    %else
        db 0
    %endif
    %assign i i+1
    %endrep

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
lex_open:      resb 1              ; 1: it has none on its line (.close_quote)
lex_str_over:  resb 1              ; 1: the string is too long, said
lex_bad_utf8:  resb 1              ; 1: the bad byte skipped is not UTF-8 (.bad_byte)
lex_str_cap:   resq 1              ; the string buffer's size
lex_comment_line: resd 1           ; where the /* being skipped started
