;
; ============================================
; File     : src/core/lexer.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

DEFAULT REL

extern arena_alloc
extern arena_alloc_string
extern error_emit
extern mem_copy
extern mem_zero
extern str_is_hex_digit
extern str_is_ident_char
extern str_utf8_decode

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
    mov     rdx, TOKEN_SIZE
    call    mem_copy
    test    rax, rax
    jnz     .fail

    ; clear peek slot
    mov     byte [rbx + LEXER_has_peek], FALSE

    xor     rax, rax
    mov     rdx, r12
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

    cmp     rcx, '%'               ; directive
    je      .lex_directive

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

    ; unknown character â€” emit error and skip
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
    inc     dword [rbx + LEXER_line]
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
    jmp     .advance_single

.emit_single_pipe:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_PIPE
    jmp     .advance_single

.emit_single_caret:
    call    .token_begin
    mov     byte [r12 + TOKEN_kind], TOK_CARET
    jmp     .advance_single

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
    ; check next char â€” must have at least 2 bytes remaining (pos + 1 < end)
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10                    ; r10 = end - 1
    cmp     r13, r10
    jge     .single_lt_not_supported
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '<'
    jne     .single_lt_not_supported
    mov     byte [r12 + TOKEN_kind], TOK_LSHIFT
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col],  2
    mov     word  [r12 + TOKEN_len],  2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.single_lt_not_supported:
    jmp     .unknown_char

.lex_rshift:
    call    .token_begin
    mov     r13, [rbx + LEXER_pos]
    mov     r10, [rbx + LEXER_end]
    dec     r10                    ; r10 = end - 1
    cmp     r13, r10
    jge     .single_gt_not_supported
    movzx   rcx, byte [r13 + 1]
    cmp     rcx, '>'
    jne     .single_gt_not_supported
    mov     byte [r12 + TOKEN_kind], TOK_RSHIFT
    add     qword [rbx + LEXER_pos], 2
    add     word  [rbx + LEXER_col],  2
    mov     word  [r12 + TOKEN_len],  2
    xor     rax, rax
    mov     rdx, r12
    jmp     .done

.single_gt_not_supported:
    jmp     .unknown_char

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
    
    ; signs can appear after e/p
    cmp     rdi, '+'
    je      .lex_number_advance
    cmp     rdi, '-'
    je      .lex_number_advance
    
    jmp     .lex_number_done

.is_float:
    mov     r14, 1
    jmp     .lex_number_advance

.lex_number_advance:
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_number_loop

.lex_number_done:
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13                   ; length

    ; copy raw number string into arena
    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

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
.lex_string:
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

    cmp     rcx, '"'               ; closing quote
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
        inc     dword [rbx + LEXER_line]
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
            inc     dword [rbx + LEXER_line]
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
    cmp     rcx, '0'
    je      .esc_null
    cmp     rcx, 'x'
    je      .esc_hex

    ; unknown escape â€” store literally
    mov     byte [r13 + r10], cl
    inc     r10
    jmp     .lex_string_loop

.esc_hex:
    ; Parse 2 hex digits
    xor     r14, r14               ; r14 = resulting byte
    
    ; First Digit
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_string_unterminated
    movzx   rcx, byte [r11]
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    
    call    .hex_digit_to_val
    IF rax, e, ERR
        jmp .lex_string_loop
    ENDIF
    shl     rax, 4
    mov     r14, rax
    
    ; Second Digit
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_string_unterminated
    movzx   rcx, byte [r11]
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    
    call    .hex_digit_to_val
    IF rax, e, ERR
        jmp .lex_string_loop
    ENDIF
    or      r14, rax
    
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

    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_char_unterminated

    movzx   rcx, byte [r11]
    cmp     rcx, '\'               ; escape?
    je      .lex_char_escape

    ; regular character
    mov     r13, rcx
    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]
    jmp     .lex_char_closing

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
    mov     r13, rcx               ; literal
    jmp     .lex_char_closing

.char_esc_n:
    mov     r13, 10
    jmp     .lex_char_closing
.char_esc_t:
    mov     r13, 9
    jmp     .lex_char_closing
.char_esc_0:
    xor     r13, r13
    jmp     .lex_char_closing

.lex_char_closing:
    ; expect closing '
    mov     r11, [rbx + LEXER_pos]
    cmp     r11, [rbx + LEXER_end]
    jge     .lex_char_unterminated
    movzx   rcx, byte [r11]
    cmp     rcx, 0x27
    jne     .lex_char_unterminated

    inc     qword [rbx + LEXER_pos]
    inc     word  [rbx + LEXER_col]

    mov     byte [r12 + TOKEN_kind], TOK_CHAR
    mov     [r12 + TOKEN_value], r13
    mov     word [r12 + TOKEN_len], 1
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
    jmp     .lex_directive_done

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
    mov     r10, [rbx + LEXER_pos]
    sub     r10, r13               ; length

    mov     rdi, [rbx + LEXER_arena]
    mov     rsi, r13
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .fail

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
    mov     rdx, TOKEN_SIZE
    call    mem_copy
    test    rax, rax
    jnz     .fail

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
    mov     rdx, TOKEN_SIZE
    call    mem_copy
    test    rax, rax
    jnz     .fail

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

