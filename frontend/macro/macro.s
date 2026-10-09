;
; ============================================
; File     : src/core/preprocessor.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

%define IDN_BUF 512
%define CAP_SIZE (1 << 30)              ; the capture area (reserved, committed as used)
%define IFT_NUM     1
%define IFT_STR     2
%define IFT_ID      3
%define IFT_EMPTY   4
%define IFT_MACRO   5
%define IFT_DEF     6                      ; %ifdef: a single-line macro
%define IFT_CTX     7                      ; %ifctx: the innermost context's name
%define IFT_ENV     8                      ; %ifenv: an environment variable
%define IFT_TOKEN   9                      ; %iftoken: exactly one token
; ml_state: where the token being read stands in its line - a multi-line
; macro is called at ML_START or ML_COLON only
%define ML_START    0                      ; the first word
%define ML_LABEL    1                      ; after a first word (a label?)
%define ML_COLON    2                      ; after "label:"
%define ML_NONE     3                      ; anywhere else
%define STK_TEXT    4096                   ; %arg / %local text for one line
extern asm_bits
extern user_sect_name

DEFAULT REL

extern error_new_from_errno
extern symbol_add
extern str_len
extern arena_alloc_string
extern str_int_to_str
extern arena_alloc
extern lexer_next
extern lexer_peek
extern lexer_init
extern io_open
extern io_file_size
extern io_mmap
extern io_close
extern str_cmp
extern str_to_int
extern symbol_find
extern print_str
extern print_num

; ============================================================================
; PREPROCESSOR
; ============================================================================
; Processes assembler directives and manages the token stream.
; Handles file inclusions, macro expansions, and conditional assembly.
;
; All functions return error codes in rax and results in rdx.
; Follows standard utasm calling convention (AMD64).
; ============================================================================

[SECTION .text]

; ---- prep_init --------------------------
;
; prep_init
; Initialises the preprocessor state.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to initial LexerState
;             rdx = pointer to AsmCtx
;             rcx = pointer to Arena
; Output   : rax = EXIT_OK
; Clobbers : none
;
global prep_init
prep_init:
    mov     byte [rdi + PREP_tag], TAG_PREPROCESSOR
    mov     word [rdi + PREP_depth], 0
    mov     word [rdi + PREP_skip_depth], 0
    mov     byte [rdi + PREP_has_peek], FALSE
    mov     word [rdi + PREP_mac_depth], 0 ; (A83)
    mov     [rdi + PREP_lexer], rsi
    mov     [rdi + PREP_ctx], rdx
    mov     [rdi + PREP_arena], rcx
    xor     rax, rax
    ret

extern error_track_token
extern error_set_subject
global preprocessor_next_token
global prep_internal_next
global prep_handle_directive
preprocessor_next_token:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Handle peek slot
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_peek
    
    ; Stable allocation for the peeked token
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    
    mov     byte [rbx + PREP_has_peek], FALSE

    mov     rdi, r12
    lea     rsi, [rbx + PREP_peek]
    copy_token

    ; a token queued behind the one just taken moves up
    cmp     byte [rel has_putback_next], TRUE
    jne     .peek_taken
    lea     rdi, [rbx + PREP_peek]
    lea     rsi, [rel putback_next]
    copy_token
    mov     byte [rbx + PREP_has_peek], TRUE
    mov     byte [rel has_putback_next], FALSE
.peek_taken:
    
    mov     rdx, r12
    xor     rax, rax
    jmp     .done
    
 .no_peek:
    ; 2. Allocate token in arena for the result
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = pointer to new token

    mov     rdi, rbx
    mov     rsi, r12
    call    prep_internal_next
    test    rax, rax
    jnz     .error
    
    mov     rdx, r12
.done:
    test    rax, rax
    jnz     .unrecorded
    call    prep_rec_note                  ; (an expression being recorded)
.unrecorded:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

.error:
    call    prep_error_note
    lea     rdx, [rel prep_error_token]
    jmp     .done


; ---- prep_error_note --------------------
;
; An error from preprocessor_next_token / _peek_token, whose callers do not
; all look at rax: they get an end of line in place of the token (never a
; null pointer), and the first such error is kept, with its subject, for
; the main loop to report (prep_error_take).
; Input    : rax = the error
; Preserves every register.
;
prep_error_note:
    cmp     dword [rel prep_error], 0
    jne     .ret
    mov     [rel prep_error], eax
    push    rax
    extern  error_subject
    mov     rax, [rel error_subject]
    mov     [rel prep_error_subj], rax
    pop     rax
.ret:
    ret

; ---- prep_error_take --------------------
;
; prep_error_take
; The error kept by prep_error_note, if any, taken (and its subject set
; again): what went wrong first in the statement just read.
; Output   : eax = the error, or 0
; Preserves the others.
;
global prep_error_take
prep_error_take:
    mov     eax, [rel prep_error]
    test    eax, eax
    jz      .ret
    mov     dword [rel prep_error], 0
    push    rdi
    push    rax
    mov     rdi, [rel prep_error_subj]
    call    error_set_subject
    pop     rax
    pop     rdi
.ret:
    ret


; ---- preprocessor_unread_token ----------
;
; Like preprocessor_putback_token, for a token read *before* the one now
; waiting in the peek slot: the peeked token stays queued behind it instead
; of being replaced ("db 'a'+1" reads 'a', peeks '+', then hands 'a' back).
; putback keeps replacing the peek slot, which the operand parser relies on.
;
; Input    : rdi = PrepState, rsi = token
;
global preprocessor_unread_token
preprocessor_unread_token:
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     preprocessor_putback_token
    push    rdi
    push    rsi
    lea     rsi, [rdi + PREP_peek]
    lea     rdi, [rel putback_next]
    copy_token
    mov     byte [rel has_putback_next], TRUE
    pop     rsi
    pop     rdi
    jmp     preprocessor_putback_token

global preprocessor_putback_token
preprocessor_putback_token:
    call    prep_rec_unnote
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rdi = PrepState
    mov     r12, rsi               ; rsi = TOKEN*

    ; Copy token into peek slot
    lea     rdi, [rbx + PREP_peek]
    mov     rsi, r12
    copy_token
    
    mov     byte [rbx + PREP_has_peek], TRUE
    
    pop     r12
    pop     rbx
    epilogue

; ---- preprocessor_peek_token ------------
global preprocessor_peek_token
preprocessor_peek_token:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    mov     rbx, rdi
    
    cmp     byte [rbx + PREP_has_peek], TRUE
    je      .done
    
    ; Allocate token in arena
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_internal_next
    test    rax, rax
    jnz     .error

    
    ; Success - token in r12
    mov     byte [rbx + PREP_has_peek], TRUE
    lea     rdi, [rbx + PREP_peek]
    mov     rsi, r12
    copy_token
    
.done:
    lea     rdx, [rbx + PREP_peek]
    xor     rax, rax
.exit:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

.error:
    call    prep_error_note
    lea     rdx, [rel prep_error_token]
    jmp     .exit



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
    call    symbol_find
    test    rax, rax
    jnz     .try_icase             ; not found or error

    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_macro_call
    jmp     .macro_found

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
    call    symbol_find
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
    jnz     .call_macro
    cmp     byte [rel ml_state], ML_START
    je      .ml_call
    cmp     byte [rel ml_state], ML_COLON
    jne     .not_macro_call
.ml_call:
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
    mov     rdi, rbx
    mov     rsi, [rdx + SYMBOL_value] ; rsi = pointer to MACRO struct
    call    prep_expand_start
    test    rax, rax
    jnz     .done                  ; error starting expansion
    jmp     .next                  ; get first token of expansion

.not_macro_call:
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
    
    ; 3. Pop include context
    mov     r11, [r9 + INCLUDECTX_parent]
    mov     [r8 + ASMCTX_inc_ctx], r11
    
    ; 4. Try getting next token from parent
    jmp     .next

.done:
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_dump --------------------------
;
; prep_dump
; Runs the preprocessor over the rest of the source and writes what it
; produces as text (-E): macros expanded, conditionals resolved, includes
; read, one output line per line. Tokens are separated by a blank where the
; source had one; strings are written back in quotes that read back to the
; same bytes. With fd -1 nothing is written (-M only needs the includes
; read).
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
.token:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    movzx   eax, byte [r14 + TOKEN_kind]
    cmp     eax, TOK_EOF
    je      .ok
    cmp     eax, TOK_NEWLINE
    jne     .text
    lea     rsi, [rel dump_newline]
    mov     edx, 1
    call    .write
    xor     r13d, r13d
    jmp     .token

.text:
    test    r13d, r13d
    jz      .first
    ; no blank before , ) ] or after ( [; else a blank where the source
    ; had one
    movzx   eax, byte [r14 + TOKEN_kind]
    cmp     eax, TOK_COMMA
    je      .first
    cmp     eax, TOK_RPAREN
    je      .first
    cmp     eax, TOK_RBRACKET
    je      .first
    movzx   eax, byte [rel dump_prev_kind]
    cmp     eax, TOK_LPAREN
    je      .first
    cmp     eax, TOK_LBRACKET
    je      .first
    mov     eax, [r14 + TOKEN_line]
    cmp     eax, [rel dump_prev_line]
    jne     .blank
    movzx   eax, word [r14 + TOKEN_col]
    cmp     eax, [rel dump_prev_end]
    jbe     .first
.blank:
    lea     rsi, [rel dump_blank]
    mov     edx, 1
    call    .write
.first:
    mov     r13d, 1
    movzx   eax, byte [r14 + TOKEN_kind]
    mov     [rel dump_prev_kind], al
    mov     eax, [r14 + TOKEN_line]
    mov     [rel dump_prev_line], eax
    movzx   eax, word [r14 + TOKEN_col]
    movzx   ecx, word [r14 + TOKEN_len]
    add     eax, ecx
    mov     [rel dump_prev_end], eax

    movzx   eax, byte [r14 + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .string
    cmp     eax, TOK_CHAR
    je      .char
    mov     rdx, r14
    call    prep_idn_text
    mov     rsi, rax
    call    .write_str
    cmp     byte [r14 + TOKEN_kind], TOK_LABEL
    jne     .token
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
    ; "..." when every byte is printable and none is ", else '...' when
    ; none is ', else `...` with escapes
    mov     r8d, 34                        ; "
    mov     r9d, 39                        ; '
    xor     edx, edx
.scan:
    cmp     edx, ecx
    jae     .scanned
    movzx   eax, byte [r15 + rdx]
    inc     edx
    cmp     eax, 32
    jb      .backquote
    cmp     eax, 126
    ja      .backquote
    cmp     eax, 34
    jne     .not_dq
    xor     r8d, r8d
.not_dq:
    cmp     eax, 39
    jne     .scan
    xor     r9d, r9d
    jmp     .scan
.scanned:
    test    r8d, r8d
    jnz     .plain
    mov     r8d, r9d
    test    r8d, r8d
    jz      .backquote
.plain:
    mov     rsi, r15
    mov     edx, ecx
    call    .quoted
    jmp     .token
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
    cmp     eax, 32
    jb      .bq_hex
    cmp     eax, 126
    ja      .bq_hex
    cmp     eax, '`'
    je      .bq_hex
    cmp     eax, 92                        ; backslash
    je      .bq_hex
    mov     [rel dump_hex], al
    lea     rsi, [rel dump_hex]
    mov     edx, 1
    call    .write
    jmp     .bq_next
.bq_hex:
    ; \xHH
    mov     ecx, eax
    shr     ecx, 4
    lea     rdi, [rel dump_digits]
    mov     cl, [rdi + rcx]
    mov     [rel dump_hex + 2], cl
    and     eax, 15
    mov     al, [rdi + rax]
    mov     [rel dump_hex + 3], al
    mov     byte [rel dump_hex], 92
    mov     byte [rel dump_hex + 1], 'x'
    lea     rsi, [rel dump_hex]
    mov     edx, 4
    call    .write
.bq_next:
    pop     rdx
    pop     rcx
    jmp     .bq_byte
.bq_end:
    lea     rsi, [rel dump_bq]
    mov     edx, 1
    call    .write
    jmp     .token

.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
; .write: rsi = bytes, edx = count, to fd r12d (nothing for -1)
.write:
    test    r12d, r12d
    js      .write_none
    test    edx, edx
    jz      .write_none
    mov     edi, r12d
    extern  io_write
    jmp     io_write
.write_none:
    ret

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
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_expand_start ------------------
;
; prep_expand_start
; Starts expanding a macro.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to MACRO struct
; Output   : rax = EXIT_OK or error code
;
global prep_expand_start
prep_expand_start:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = MACRO struct
    inc     dword [rel rec_suspend]        ; (the arguments: not an expression's)

    ; 0. Check recursion depth (A99)
    inc     word [rbx + PREP_mac_depth]
    cmp     word [rbx + PREP_mac_depth], MAX_MACRO_DEPTH
    jbe     .depth_ok
    
    mov rax, EXIT_MACRO_RECURSION
    jmp .error

.depth_ok:
    ; a number for each call of a multi-line macro (%%locals: NASM's
    ; ..@N.name) - not for a %define, a %rep body or a times line, which
    ; NASM does not count either
    mov     r8, [rbx + PREP_ctx]
    cmp     qword [r12 + MACRO_name], 0
    je      .no_new_id
    test    byte [r12 + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
    jnz     .no_new_id
    inc     dword [r8 + ASMCTX_mac_exp_id]
.no_new_id:

    ; 1. Allocate MACROEXP struct
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACROEXP_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r13, rdx               ; r13 = MACROEXP struct

    mov     byte [r13 + MACROEXP_tag], TAG_MACRO_EXP
    mov     [r13 + MACROEXP_macro], r12
    mov     dword [r13 + MACROEXP_rep_count], 1 ; Default: expand once

    ; %%locals are unique per *macro* expansion. A %rep body is an anonymous
    ; macro running inside one, so it must reuse the enclosing id or the
    ; %%names inside the loop would not match those outside it.
    mov     r8, [rbx + PREP_ctx]
    mov     eax, [r8 + ASMCTX_mac_exp_id]
    cmp     qword [r12 + MACRO_name], 0
    jne     .own_exp_id
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .own_exp_id
    mov     eax, [r9 + MACROEXP_exp_id]
.own_exp_id:
    mov     [r13 + MACROEXP_exp_id], eax
    ; Check arity
    movzx   rax, word [r12 + MACRO_min_params]
    movzx   rdx, word [r12 + MACRO_max_params]
    ; A parameterless macro (every %define) needs no argument buffers
    test    edx, edx
    jnz     .has_params
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .has_params
    cmp     qword [r12 + MACRO_next], 0
    jne     .has_params                    ; an overload may take some
    xor     r15, r15
    jmp     .done_params
.has_params:

    ; params[] and arglens[] for 4 arguments to start with; they double
    ; when a call has more (.grow_params)
    mov     r14, 4
    mov     [r13 + MACROEXP_pcap], r14d

.alloc_params:
    ; params[] : pointer to the first token of each argument
    mov     rsi, r14
    imul    rsi, 8
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx               ; r14 = param array

    ; arglens[] : token count per argument (dwords)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 4 * 4
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_arglens], rdx

    ; Every argument token, one after the other, in the capture area; they
    ; are copied out at their size once the call is read (.dflt_done)
    call    prep_cap_base
    check_err
    mov     [r13 + MACROEXP_pend_ptr], rdx     ; scratch: next free slot
    mov     dword [r13 + MACROEXP_pend_cnt], 0 ; scratch: slots used
    mov     [r13 + MACROEXP_body], rdx         ; the capture's base, until then

    xor     r15, r15               ; r15 = argument index
    mov     dword [rel fn_depth], 0
    mov     dword [rel brace_depth], 0
    mov     byte [rel brace_dropped], 0

    ; A function-like %define takes its arguments in parentheses: NAME(a, b)
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .line_args
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .error_too_few_args
    jmp     .arg_loop
.line_args:

    ; A macro that declares no parameters consumes nothing from the line
    ; (unless an overload of it takes some).
    movzx   rax, word [r12 + MACRO_max_params]
    test    eax, eax
    jnz     .arg_loop
    cmp     qword [r12 + MACRO_next], 0
    je      .args_done

.arg_loop:
    cmp     r15, MACRO_PARAMS_MAX
    jae     .error_too_many_args
    cmp     r15d, [r13 + MACROEXP_pcap]
    jb      .arg_slot
    call    .grow_params
    test    rax, rax
    jnz     .error
.arg_slot:

    ; Start a new argument at the current cursor with a zero token count
    mov     rax, [r13 + MACROEXP_pend_ptr]
    mov     [r14 + r15 * 8], rax
    mov     rcx, [r13 + MACROEXP_arglens]
    mov     dword [rcx + r15 * 4], 0

.arg_token:
    ; the slot at pend_ptr, the capture area's top moved past it (a capture
    ; made while the token is read goes above)
    mov     rdi, [r13 + MACROEXP_body]
    mov     esi, [r13 + MACROEXP_pend_cnt]
    call    prep_cap_slot
    test    rax, rax
    jnz     .error

    ; Read through the preprocessor rather than the raw lexer: a macro
    ; called from inside another macro's body takes its arguments from
    ; the expansion, and %N arguments must already be substituted when
    ; they are captured.
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    mov     rsi, rdx
    mov     rdi, [r13 + MACROEXP_pend_ptr]
    copy_token

    mov     rsi, [r13 + MACROEXP_pend_ptr]
    movzx   eax, byte [rsi + TOKEN_kind]
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .arg_line_kinds
    ; inside parentheses: nested ( ) belong to the argument, the closing )
    ; ends the call, a comma at depth 0 separates arguments
    cmp     al, TOK_LPAREN
    jne     .fn_not_open
    inc     dword [rel fn_depth]
    jmp     .arg_keep
.fn_not_open:
    cmp     al, TOK_RPAREN
    jne     .fn_not_close
    cmp     dword [rel fn_depth], 0
    je      .arg_end_all
    dec     dword [rel fn_depth]
    jmp     .arg_keep
.fn_not_close:
    cmp     al, TOK_NEWLINE
    je      .error_too_few_args            ; no closing parenthesis
    cmp     al, TOK_EOF
    je      .error_too_few_args
    cmp     al, TOK_COMMA
    jne     .arg_keep
    cmp     dword [rel fn_depth], 0
    je      .arg_end_one
    jmp     .arg_keep
.arg_line_kinds:
    cmp     al, TOK_NEWLINE
    je      .arg_end_all
    cmp     al, TOK_EOF
    je      .arg_end_all
    ; {a, b} is one argument, commas and all; the braces go
    cmp     al, TOK_LBRACE
    jne     .not_lbrace
    inc     dword [rel brace_depth]
    cmp     dword [rel brace_depth], 1
    jne     .arg_keep
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     dword [rcx + r15 * 4], 0
    jne     .arg_keep                      ; a brace inside an argument stays
    mov     byte [rel brace_dropped], 1
    jmp     .arg_token
.not_lbrace:
    cmp     al, TOK_RBRACE
    jne     .not_rbrace
    cmp     dword [rel brace_depth], 0
    je      .arg_keep
    dec     dword [rel brace_depth]
    jnz     .arg_keep
    cmp     byte [rel brace_dropped], 0
    je      .arg_keep
    mov     byte [rel brace_dropped], 0
    jmp     .arg_token
.not_rbrace:
    cmp     dword [rel brace_depth], 0
    jne     .arg_keep                      ; commas inside braces stay
    cmp     al, TOK_COMMA
    je      .arg_comma

    ; Keep this token as part of the current argument
.arg_keep:
    add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
    inc     dword [r13 + MACROEXP_pend_cnt]
    mov     rcx, [r13 + MACROEXP_arglens]
    inc     dword [rcx + r15 * 4]
    jmp     .arg_token

.arg_comma:
    ; the last parameter of a "+" macro keeps its commas
    test    byte [r12 + MACRO_flags], MACRO_FLAG_GREEDY
    jz      .arg_end_one
    movzx   ecx, word [r12 + MACRO_max_params]
    dec     ecx
    cmp     r15d, ecx
    jae     .arg_keep
.arg_end_one:
    ; A top-level comma ends this argument; the comma slot gets reused
    inc     r15
    jmp     .arg_loop

.arg_end_all:
    ; Newline or EOF ends the invocation. A trailing empty argument (the
    ; macro was invoked with no arguments at all) does not count.
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     dword [rcx + r15 * 4], 0
    je      .args_done
    inc     r15

.args_done:
    ; With overloads, the one whose parameter range takes this many
    mov     rax, r12
.pick:
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     r15d, ecx
    jb      .pick_next
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     ecx, MACRO_VARIADIC
    je      .picked
    cmp     r15d, ecx
    jbe     .picked
.pick_next:
    mov     rax, [rax + MACRO_next]
    test    rax, rax
    jnz     .pick
    mov     rax, r12                       ; none: the checks below report it
.picked:
    mov     r12, rax
    mov     [r13 + MACROEXP_macro], r12

    ; Arity checks
    movzx   eax, word [r12 + MACRO_min_params]
    cmp     r15d, eax
    jb      .error_too_few_args
    movzx   eax, word [r12 + MACRO_max_params]
    cmp     eax, MACRO_VARIADIC
    je      .arity_ok
    cmp     r15d, eax
    ja      .error_too_many_args
.arity_ok:

    ; Optional parameters not given take their defaults: default d is the
    ; d-th comma-separated piece of the list, for parameter min + d
    cmp     dword [r12 + MACRO_ndefaults], 0
    je      .dflt_done
    cmp     word [r12 + MACRO_max_params], MACRO_VARIADIC
    je      .dflt_done
.dflt_next:
    movzx   eax, word [r12 + MACRO_max_params]
    cmp     r15d, eax
    jae     .dflt_done
    cmp     r15d, [r13 + MACROEXP_pcap]
    jb      .dflt_slot
    call    .grow_params
    test    rax, rax
    jnz     .error
.dflt_slot:
    movzx   ecx, word [r12 + MACRO_min_params]
    mov     edx, r15d
    sub     edx, ecx                       ; d
    mov     r8, [r12 + MACRO_defaults]
    mov     r9d, [r12 + MACRO_ndefaults]   ; tokens left
.dflt_seek:
    test    edx, edx
    jz      .dflt_piece
.dflt_seek_tok:
    test    r9d, r9d
    jz      .dflt_piece                    ; past the list: empty
    movzx   eax, byte [r8 + TOKEN_kind]
    add     r8, TOKEN_SIZE
    dec     r9d
    cmp     eax, TOK_COMMA
    jne     .dflt_seek_tok
    dec     edx
    jmp     .dflt_seek
.dflt_piece:
    mov     [r14 + r15 * 8], r8
    xor     ecx, ecx
.dflt_len:
    cmp     ecx, r9d
    jae     .dflt_len_done
    imul    rax, rcx, TOKEN_SIZE
    cmp     byte [r8 + rax + TOKEN_kind], TOK_COMMA
    je      .dflt_len_done
    inc     ecx
    jmp     .dflt_len
.dflt_len_done:
    mov     rax, [r13 + MACROEXP_arglens]
    mov     [rax + r15 * 4], ecx
    inc     r15
    jmp     .dflt_next
.dflt_done:
    ; The argument tokens at their size, out of the capture area; params[]
    ; pointing into it moves with them (a default points at the macro's own
    ; list)
    mov     rdi, rbx
    mov     rsi, [r13 + MACROEXP_body]
    mov     edx, [r13 + MACROEXP_pend_cnt]
    call    prep_cap_take
    test    rax, rax
    jnz     .error
    mov     rsi, [r13 + MACROEXP_body]     ; the old base
    mov     r8, rdx
    sub     r8, rsi                        ; how far they moved
    mov     ecx, [r13 + MACROEXP_pend_cnt]
    imul    rcx, rcx, TOKEN_SIZE
    add     rcx, rsi                       ; the old end
    xor     r9d, r9d
.rebase:
    cmp     r9, r15
    jae     .rebased
    mov     rax, [r14 + r9 * 8]
    cmp     rax, rsi
    jb      .rebase_next
    cmp     rax, rcx
    ja      .rebase_next
    add     rax, r8
    mov     [r14 + r9 * 8], rax
.rebase_next:
    inc     r9
    jmp     .rebase
.rebased:
    mov     qword [r13 + MACROEXP_body], 0 ; the body starts at its first token

    ; Release the collection scratch: these fields drive substitution now
    mov     qword [r13 + MACROEXP_pend_ptr], 0
    mov     dword [r13 + MACROEXP_pend_cnt], 0
    jmp     .done_params

; .grow_params: params[] and arglens[] twice the size, the entries so far
; copied over; r14 = the new params[]. rax = OK or an error.
.grow_params:
    mov     rdi, [rbx + PREP_arena]
    mov     esi, [r13 + MACROEXP_pcap]
    shl     rsi, 4                         ; twice, 8 bytes each
    call    arena_alloc
    test    rax, rax
    jnz     .gp_ret
    mov     rdi, rdx
    mov     rsi, [r13 + MACROEXP_params]
    mov     ecx, [r13 + MACROEXP_pcap]
    rep movsq
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx
    mov     rdi, [rbx + PREP_arena]
    mov     esi, [r13 + MACROEXP_pcap]
    shl     rsi, 3                         ; twice, 4 bytes each
    call    arena_alloc
    test    rax, rax
    jnz     .gp_ret
    mov     rdi, rdx
    mov     rsi, [r13 + MACROEXP_arglens]
    mov     ecx, [r13 + MACROEXP_pcap]
    rep movsd
    mov     [r13 + MACROEXP_arglens], rdx
    shl     dword [r13 + MACROEXP_pcap], 1
    xor     eax, eax
.gp_ret:
    ret

.error_too_few_args:
.error_too_many_args:
    mov     rax, [r13 + MACROEXP_body]     ; the capture area back
    test    rax, rax
    jz      .arity_report
    mov     [rel cap_top], rax
.arity_report:
    mov     rdi, [r13 + MACROEXP_macro]    ; "multi-line macro `m' does not
    mov     rdi, [rdi + MACRO_name]        ;  take this number of parameters"
    call    error_set_subject
    mov     rax, EXIT_MACRO_ARITY_FAIL
    jmp     .error

.done_params:
    mov     [r13 + MACROEXP_nparams], r15w
    
    ; 3. Link to previous
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    mov     [r13 + MACROEXP_parent], r9
    mov     [r8 + ASMCTX_mac_exp], r13

    ; the listing's <N> (error_track_token): the macro and %rep expansions
    ; open around this one, from its parent's - counting them per token
    ; walked every open expansion
    xor     eax, eax
    xor     ecx, ecx
    xor     edx, edx
    test    r9, r9
    jz      .nest_own
    mov     eax, [r9 + MACROEXP_lst_depth]
    mov     rcx, [r9 + MACROEXP_lst_first]
    mov     rdx, [r9 + MACROEXP_lst_second]
.nest_own:
    mov     r10, [r13 + MACROEXP_macro]
    test    byte [r10 + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
    jnz     .nest_set
    inc     eax
    mov     rdx, rcx
    mov     rcx, r13
.nest_set:
    mov     [r13 + MACROEXP_lst_depth], eax
    mov     [r13 + MACROEXP_lst_first], rcx
    mov     [r13 + MACROEXP_lst_second], rdx

    xor     rax, rax
    mov     rdx, r13               ; Return expansion struct in RDX (A99)
    jmp     .done

.error_pop_token:
    add     rsp, TOKEN_SIZE
    jmp     .error

.error_expected_comma:
    add     rsp, TOKEN_SIZE
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .done

.done:
    dec     dword [rel rec_suspend]
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

.error:
    jmp     .done

; ---- prep_expand_next -------------------
;
; prep_expand_next
; Serves the next token from the current macro expansion.
; Handles parameter substitution.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (destination)
; Output   : rax = 0 (produced token) or non-zero (finished)
;
prep_expand_next:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token dest

    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp] ; r13 = current expansion
    test    r13, r13
    jz      .finished

    ; 0. An argument spanning several tokens is served one token per call
    mov     eax, [r13 + MACROEXP_pend_cnt]
    test    eax, eax
    jz      .no_pending
        mov     rsi, [r13 + MACROEXP_pend_ptr]
        mov     rdi, r12
        copy_token
        add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
        dec     dword [r13 + MACROEXP_pend_cnt]
        jmp     .produced
.no_pending:

.retry_body:
    ; 1. Get current token index
    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .expansion_end

    ; 2. Copy token from macro body
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = source token

    ; copy to dest
    mov     rdi, r12
    mov     rsi, r10
    copy_token

    ; increment body pos
    inc     qword [r13 + MACROEXP_body]

    ; 2.5 Handle Stringification (#) (A67)
    cmp     byte [r12 + TOKEN_kind], TOK_HASH
    jne     .not_hash
        ; Peek at NEXT token in macro body
        mov     rax, [r13 + MACROEXP_body]
        mov     r9, [r13 + MACROEXP_macro]
        cmp     eax, [r9 + MACRO_ntokens]
        jge     .produced              ; Nothing after #
        
        mov     r10, [r9 + MACRO_tokens]
        imul    rax, TOKEN_SIZE
        add     r10, rax               ; r10 = potential parameter ref
        
        cmp     byte [r10 + TOKEN_kind], TOK_DIRECTIVE
        jne     .not_hash
            ; Check if it's %1-%9
            mov     rdi, [r10 + TOKEN_value]
            movzx   rax, byte [rdi]
            sub     al, '0'
            cmp     al, 1
            jl      .not_hash
            cmp     al, 9
            jg      .not_hash
                ; Yes, it's stringification!
                ; 1. Consume the directive token
                inc     qword [r13 + MACROEXP_body]
                
                ; 2. Get the parameter token
                dec     al
                movzx   rax, al
                mov     r11, [r13 + MACROEXP_params]
                mov     rsi, [r11 + rax * 8]   ; rsi = param token
                
                ; 3. Stringify it (Create a TOK_STRING)
                mov     byte [r12 + TOKEN_kind], TOK_STRING
                
                ; Use TOKEN_value or name string? 
                ; For TOK_IDENT, use value. For others, we need a helper.
                ; Simple implementation: use the value directly if it's already a string.
                mov     rax, [rsi + TOKEN_value]
                mov     [r12 + TOKEN_value], rax
                
                jmp     .produced
.not_hash:

    ; 3. Handle parameter substitution
    ; Macro parameters are TOK_DIRECTIVE with value like "0", "1", "2"...
    ; A %%local is not a directive, so send it on to CASE 4 rather than
    ; letting it pass through unresolved.
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    je      .not_case3
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .produced

    mov     rdi, [r12 + TOKEN_value]
    movzx   rax, byte [rdi]

    ; CASE 0: %? / %??, the name of the macro being expanded (as called,
    ; as defined: the same, names keeping their case)
    cmp     al, '?'
    jne     .not_case0
    cmp     byte [rdi + 1], 0
    je      .case0
    cmp     byte [rdi + 1], '?'
    jne     .not_case0
    cmp     byte [rdi + 2], 0
    jne     .not_case0
.case0:
        mov     r11, r13
.name_owner:
        mov     rax, [r11 + MACROEXP_macro]
        test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE | MACRO_FLAG_TIMES
        jnz     .name_up
        mov     rax, [rax + MACRO_name]
        test    rax, rax
        jnz     .name_found
.name_up:
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .name_owner
        jmp     .retry_body
.name_found:
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], rax
        jmp     .produced
.not_case0:

    ; CASE 1: %0 (Parameter Count)
    cmp     al, '0'
    jne     .not_case1
        ; Allocate space for the number string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .expansion_end ; or other error
        
        mov     rdi, rdx       ; dst
        movzx   rsi, word [r13 + MACROEXP_nparams]
        extern  str_int_to_str
        call    str_int_to_str
        
        mov     byte [r12 + TOKEN_kind], TOK_NUMBER
        mov     [r12 + TOKEN_value], rdx ; pointer to formatted string
        jmp     .produced
.not_case1:

    ; CASE 2: %1, %2, ... %32 (Parameter Reference), also %{2}
    xor     eax, eax
    mov     rsi, rdi
    cmp     byte [rsi], '{'                ; the lexer keeps the text after it
    jne     .pnum
    inc     rsi
.pnum:
    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .pnum_done
    cmp     ecx, '}'
    je      .pnum_done
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .not_case2
    imul    eax, eax, 10
    add     eax, ecx
    cmp     eax, MACRO_PARAMS_MAX
    ja      .not_case2
    inc     rsi
    jmp     .pnum
.pnum_done:
    test    eax, eax
    jz      .not_case2
        ; it's a param ref! (1-9)
        ; A %rep body running inside a macro has no parameters of its own,
        ; so walk out to the nearest expansion that does.
        mov     r11, r13
.param_owner_loop:
        cmp     word [r11 + MACROEXP_nparams], 0
        jne     .param_owner_found
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .param_owner_loop
        jmp     .retry_body
.param_owner_found:

        ; check if it is within nparams
        movzx   ecx, word [r11 + MACROEXP_nparams]
        cmp     eax, ecx
        ja      .retry_body            ; optional parameter not supplied:
                                       ; substitute nothing rather than leaking
                                       ; "%4" out as a stray directive token

        ; Substitute the argument. An argument may span several tokens: emit
        ; the first here and leave the rest pending for the next calls.
        dec     eax                    ; 0-indexed (rax: eax zero-extended)
        mov     r10, r11               ; r10 = expansion owning the parameters
        mov     r11, [r10 + MACROEXP_arglens]
        mov     ecx, [r11 + rax * 4]   ; rcx = token count of this argument
        test    rcx, rcx
        jz      .retry_body            ; empty argument: substitute nothing

        mov     r11, [r10 + MACROEXP_params]
        mov     rsi, [r11 + rax * 8]   ; rsi = first token of the argument

        dec     rcx
        mov     [r13 + MACROEXP_pend_cnt], ecx
        lea     rax, [rsi + TOKEN_SIZE]
        mov     [r13 + MACROEXP_pend_ptr], rax

        mov     rdi, r12
        copy_token
        jmp     .produced
.not_case2:

    ; CASE 3a: %{a:b}, the arguments a to b (b < a: in reverse; a negative
    ; one counts from the last), separated by commas
    mov     rsi, rdi
.rng_colon:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .not_range
    cmp     eax, ':'
    je      .range
    inc     rsi
    jmp     .rng_colon
.range:
    cmp     byte [rdi], '{'            ; the lexer keeps the text after it
    jne     .range_open
    inc     rdi
.range_open:
    call    .parse_sint
    cmp     byte [rdi], ':'
    jne     .not_range
    mov     [rel rng_a], rax
    inc     rdi
    call    .parse_sint
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .range_closed
    cmp     ecx, '}'
    jne     .not_range
.range_closed:
    mov     [rel rng_b], rax
    mov     r11, r13
.rng_owner:
    cmp     word [r11 + MACROEXP_nparams], 0
    jne     .rng_found
    mov     r11, [r11 + MACROEXP_parent]
    test    r11, r11
    jnz     .rng_owner
    jmp     .retry_body
.rng_found:
    mov     [rel rng_owner], r11
    movzx   ecx, word [r11 + MACROEXP_nparams]
    mov     rax, [rel rng_a]
    test    rax, rax
    jns     .rng_a_ok
    lea     rax, [rcx + rax + 1]
    mov     [rel rng_a], rax
.rng_a_ok:
    cmp     rax, 1
    jl      .retry_body
    cmp     rax, rcx
    jg      .retry_body
    mov     rax, [rel rng_b]
    test    rax, rax
    jns     .rng_b_ok
    lea     rax, [rcx + rax + 1]
    mov     [rel rng_b], rax
.rng_b_ok:
    cmp     rax, 1
    jl      .retry_body
    cmp     rax, rcx
    jg      .retry_body
    ; tokens: the arguments and a comma between each two
    mov     r9, [rel rng_a]
    xor     r8d, r8d
.rng_count:
    mov     r11, [rel rng_owner]
    mov     r10, [r11 + MACROEXP_arglens]
    mov     eax, [r10 + r9 * 4 - 4]
    add     r8, rax
    cmp     r9, [rel rng_b]
    je      .rng_counted
    inc     r8                             ; the comma
    call    .rng_step
    jmp     .rng_count
.rng_counted:
    test    r8, r8
    jz      .retry_body
    mov     [rel rng_total], r8
    mov     rdi, [rbx + PREP_arena]
    imul    rsi, r8, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .retry_body
    mov     [rel rng_buf], rdx
    mov     r8, rdx                        ; where the next token goes
    mov     r9, [rel rng_a]
.rng_fill:
    mov     r11, [rel rng_owner]
    mov     r10, [r11 + MACROEXP_arglens]
    mov     ecx, [r10 + r9 * 4 - 4]
    imul    ecx, ecx, TOKEN_SIZE
    mov     r10, [r11 + MACROEXP_params]
    mov     rsi, [r10 + r9 * 8 - 8]
    mov     rdi, r8
    rep movsb
    mov     r8, rdi
    cmp     r9, [rel rng_b]
    je      .rng_filled
    mov     rdi, r8
    mov     rsi, r12                       ; the use's line and column
    copy_token
    mov     byte [r8 + TOKEN_kind], TOK_COMMA
    mov     qword [r8 + TOKEN_value], 0
    mov     byte [r8 + TOKEN_flags], 0
    add     r8, TOKEN_SIZE
    call    .rng_step
    jmp     .rng_fill
.rng_filled:
    ; the first token now, the rest pending
    mov     rsi, [rel rng_buf]
    mov     rcx, [rel rng_total]
    dec     rcx
    mov     [r13 + MACROEXP_pend_cnt], ecx
    lea     rax, [rsi + TOKEN_SIZE]
    mov     [r13 + MACROEXP_pend_ptr], rax
    mov     rdi, r12
    copy_token
    jmp     .produced

; r9 one step from rng_a toward rng_b
.rng_step:
    cmp     r9, [rel rng_b]
    jl      .rng_up
    dec     r9
    ret
.rng_up:
    inc     r9
    ret

; rax = the signed decimal at rdi; rdi past it
.parse_sint:
    xor     eax, eax
    xor     edx, edx
    cmp     byte [rdi], '-'
    jne     .ps_digit
    mov     edx, 1
    inc     rdi
.ps_digit:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .ps_end
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .ps_digit
.ps_end:
    test    edx, edx
    jz      .ps_ret
    neg     rax
.ps_ret:
    ret

.not_range:
    mov     rdi, [r12 + TOKEN_value]

    ; CASE 3: Variadic Expansion %{n..} (A69)
    cmp     byte [rdi], '{'
    jne     .not_case3
        ; parse braced parameter ref like "{1..}"
        inc     rdi                    ; skip {
        
        ; simple parser for digit
        movzx   rax, byte [rdi]
        sub     al, '0'
        cmp     al, 1
        jl      .not_case3
        cmp     al, 9
        jg      .not_case3
            ; r14 = starting index (1-based)
            movzx   r14, al
            
            ; check for ".." suffix
            cmp     byte [rdi + 1], '.'
            jne     .not_case3
            cmp     byte [rdi + 2], '.'
            jne     .not_case3
                ; It's %{n..}!
                ; We need to expand all params from r14 to nparams.
                ; This is complex for a single prep_expand_next call 
                ; because it returns one token.
                ; For now, we'll implement it by expanding the FIRST 
                ; param in the range and setting a flag to expand 
                ; the rest in subsequent calls? 
                
                ; Better: if nparams > r14, we expand r14 and then 
                ; we'd need to inject commas.
                ; To keep it simple for now, we'll support %{n..} as a 
                ; way to get ALL arguments from n onwards as a single 
                ; space-separated sequence if captured greedy.
                
                ; If the parameter was captured via prep_capture_greedy, 
                ; it is ALREADY a single string.
                movzx   ecx, word [r13 + MACROEXP_nparams]
                cmp     r14d, ecx
                ja      .produced      ; Out of range
                
                dec     r14b           ; 0-indexed
                mov     r11, [r13 + MACROEXP_params]
                movzx   rax, r14b
                mov     rsi, [r11 + rax * 8]
                
                mov     rdi, r12
                copy_token
                jmp     .produced
.not_case3:

    ; CASE 4: Macro Local Label %% (A70)
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    jne     .not_case4
        ; Expand to ..@ID_label
        mov     r14d, dword [r13 + MACROEXP_exp_id]
        
        ; 1. Allocate buffer for ID string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r15, rdx               ; r15 = ID string buffer
        
        mov     rdi, r15
        mov     rsi, r14               ; value
        extern  str_int_to_str
        call    str_int_to_str
        
        ; 2. Allocate the label: "..@" + ID + "." + name + NUL. Only what it
        ;    needs: compile_time_hash expands its %%names once per character,
        ;    so a MAX_TOKEN buffer each time used up the arena on large tables.
        mov     rdi, r15
        call    str_len
        mov     r14, rax
        mov     rdi, [r12 + TOKEN_value]
        call    str_len
        lea     rsi, [r14 + rax + 5]
        mov     rdi, [rbx + PREP_arena]
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r14, rdx               ; r14 = final label buffer
        
        ; 3. Construct "..@ID.label", as NASM names it
        mov     byte [r14], '.'
        mov     byte [r14+1], '.'
        mov     byte [r14+2], '@'
        mov     byte [r14+3], 0
        
        mov     rdi, r14
        mov     rsi, r15               ; ID string
        extern  str_concat
        call    str_concat
        mov     rdi, r14
        lea     rsi, [rel s_dot]
        call    str_concat
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value] ; original label name
        call    str_concat
        
        ; Update token
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], r14
        jmp     .produced
.not_case4:

.produced:
    ; ---- A68: Token Concatenation (##) ----
.check_concat:
    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp]
    test    r13, r13
    jz      .done_concat

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .done_concat
    
    ; Peek at next token
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = next token in body
    
    IF byte [r10 + TOKEN_kind], e, TOK_CONCAT
        ; 1. Consume ##
        inc     qword [r13 + MACROEXP_body]
        
        ; 2. Get the NEXT operand (A ## B)
        ; We need to produce the next token into a temp buffer
        sub     rsp, TOKEN_SIZE
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_expand_next
        IF rax, ne, 0
            ; Error or expansion end (unexpected)
            add     rsp, TOKEN_SIZE
            jmp     .done_concat
            ENDIF
        
        ; 2.5 Both operands may still carry %[...] or %$ text: resolve them
        ;     before joining, so ".if_ %+ %$uid" pastes the context's value.
        test    byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_lhs_ready
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_resolve_interp
.concat_lhs_ready:
        test    byte [rsp + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_rhs_ready
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_resolve_interp
.concat_rhs_ready:
        ; %assign / %define names paste as their value
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_subst_const_text
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_subst_const_text

        ; 3. Concatenate r12 (merged so far) and rsp (next token)
        ; Allocate space for combined string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, MAX_TOKEN
        extern  arena_alloc
        call    arena_alloc
        test    rax, rax
        jnz     .done_concat           ; OOM or error
        
        mov     r14, rdx               ; r14 = concat buffer
        mov     byte [r14], 0          ; null-terminate before str_concat
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value]
        extern  str_concat
        call    str_concat
        
        mov     rdi, r14
        mov     rsi, [rsp + TOKEN_value]
        call    str_concat
        
        ; 4. Update r12 to be the merged token. When the right-hand piece
        ;    carried the ':' (".lbl_ %+ id %+ _end:"), the join is still a
        ;    label definition, not a plain identifier.
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     cl, [rsp + TOKEN_kind]
        cmp     cl, TOK_LABEL
        je      .concat_is_label
        cmp     cl, TOK_LOCAL_LABEL
        jne     .concat_kind_set
.concat_is_label:
        mov     byte [r12 + TOKEN_kind], TOK_LABEL
        cmp     byte [r14], '.'
        jne     .concat_kind_set
        mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
.concat_kind_set:
        mov     [r12 + TOKEN_value], r14
        
        add     rsp, TOKEN_SIZE
        jmp     .check_concat          ; Chain: allow A ## B ## C
        ENDIF

.done_concat:
    xor     rax, rax
    jmp     .done

.expansion_end:
    ; Check for %rep loop
    cmp     dword [r13 + MACROEXP_rep_count], 1
    jle     .do_pop
    
    dec     dword [r13 + MACROEXP_rep_count]
    mov     qword [r13 + MACROEXP_body], 0
    mov     rax, 1                 ; try again (retry expansion from start of loop)
    jmp     .done

.do_pop:
    mov     rdi, rbx
    call    prep_expand_pop
    ; we finished this expansion, but there might be a parent
    ; we return non-zero to tell caller to try again (which will check mac_exp again)
    mov     rax, 1
    jmp     .done

.finished:
    mov     rax, 1

.done:
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

global prep_expand_pop
prep_expand_pop:
    prologue
    push    rbx
    push    r12                    ; Alignment padding
    mov     rbx, rdi
    
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .done
    
    ; Decrease depth
    dec     word [rbx + PREP_mac_depth]
    
    ; Pop from expansion stack
    mov     rax, [r9 + MACROEXP_parent]
    mov     [r8 + ASMCTX_mac_exp], rax
    
.done:
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_handle_directive --------------
;
; prep_handle_directive
; Processes a directive starting with %.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to % Token
; Output   : rax = EXIT_OK or error code
; Clobbers : ...
;
prep_handle_directive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14                    ; r14 = stack cleanup flag
    mov     r14, 0                 ; initialize flag early
    mov     rbx, rdi               ; rbx = PrepState
    mov     r13, rsi               ; r13 = the token triggering the directive (% or %name)
    
    ; check if we already have the identifier
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    je      .have_ident
    
    ; next token should be the directive identifier
    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, TOKEN_SIZE        ; space for temp token
    mov     r14, 1                 ; stack cleanup flag: YES
    mov     r12, rsp               ; r12 = temp token dest
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error_pop_rsp

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .expected_ident_pop_rsp
    
    jmp     .start_match

.have_ident:
    mov     r12, r13               ; use the directive token as the ident token
    mov     r14, 0                 ; stack cleanup flag: NO

.start_match:
    ; check which directive it is
    mov     rdi, [r12 + TOKEN_value] ; directive name
    lea     rsi, [dir_inc]
    call    str_cmp
    test    rax, rax
    jz      .do_inc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_def]
    call    str_cmp
    test    rax, rax
    jz      .do_def

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_assign]
    call    str_cmp
    test    rax, rax
    jz      .do_assign

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_push]
    call    str_cmp
    test    rax, rax
    jz      .do_push

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_pop]
    call    str_cmp
    test    rax, rax
    jz      .do_pop

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifctx]
    call    str_cmp
    test    rax, rax
    jz      .do_ifctx

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifidni]
    call    str_cmp
    test    rax, rax
    jz      .do_ifidni

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_elifidni]
    call    str_cmp
    test    rax, rax
    jz      .do_elifidni

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_elif]
    call    str_cmp
    test    rax, rax
    jz      .do_elif

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_error]
    call    str_cmp
    test    rax, rax
    jz      .do_error

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_strlen]
    call    str_cmp
    test    rax, rax
    jz      .do_strlen

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_substr]
    call    str_cmp
    test    rax, rax
    jz      .do_substr

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rotate]
    call    str_cmp
    test    rax, rax
    jz      .do_rotate

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_def_short]
    call    str_cmp
    test    rax, rax
    jz      .do_def

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_xdefine]
    call    str_cmp
    test    rax, rax
    jz      .do_xdefine

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_idefine]
    call    str_cmp
    test    rax, rax
    jz      .do_idefine

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_inc_short]
    call    str_cmp
    test    rax, rax
    jz      .do_inc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_undef]
    call    str_cmp
    test    rax, rax
    jz      .do_undef

    ; the names below dispatch through dir_more (name, handler, 16 bytes)
    lea     r8, [rel dir_more]
.more:
    cmp     byte [r8], 0
    je      .more_done
    push    r8
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r8
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .more_hit
    add     r8, 16
    jmp     .more
.more_hit:
    movzx   eax, byte [r8 + 15]            ; handler number
    cmp     eax, 64
    jae     .m_iftest                      ; %ifnum family: also while skipping
    cmp     eax, 20
    je      .m_ifn                         ; conditionals: also while skipping
    cmp     eax, 21
    je      .m_elifn
    cmp     eax, 23
    je      .m_rmacro                      ; skipping handled like %macro
    cmp     eax, 24
    je      .m_irmacro
    cmp     eax, 10
    je      .m_imacro                      ; skipping handled like %macro
    cmp     eax, 4
    jb      .more_cond                     ; %ifidn family: also while skipping
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
.more_cond:
    lea     rcx, [rel .more_table]
    jmp     [rcx + rax*8]
.more_table:
    dq      .m_ifidn, .m_ifnidn, .m_ifnidni, .m_elifidn
    dq      .m_warning, .m_fatal, .m_exitrep, .m_strcat, .m_deftok
    dq      .m_defstr, .m_imacro, .m_exitmacro, .m_repl, .m_line, .m_use
    dq      .m_pragma, .m_clear, .m_iassign, .m_defalias, .m_idefstr
    dq      .m_ifn, .m_elifn, .m_ixdefine, .m_rmacro, .m_irmacro
    dq      .m_depend, .m_pathsearch, .m_stacksize, .m_arg, .m_local
.m_stacksize:
    mov     rdi, rbx
    call    prep_handle_stacksize
    jmp     .done_cleanup
.m_arg:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_frame
    jmp     .done_cleanup
.m_local:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_frame
    jmp     .done_cleanup
.m_ifn:
    mov     byte [rel cond_negate], 1      ; %ifn: %if, the other way
    mov     rdi, rbx
    call    prep_handle_if
    jmp     .done_cleanup
.m_elifn:
    mov     byte [rel cond_negate], 1
    mov     rdi, rbx
    call    prep_handle_elif
    jmp     .done_cleanup
.m_ixdefine:
    mov     byte [rel def_icase], 1        ; %ixdefine: both
    mov     byte [rel def_eager], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup
.m_irmacro:
    mov     eax, 10                        ; %irmacro is %imacro (recursion
    jmp     .m_imacro                      ; is allowed, up to a depth)
.m_rmacro:
    jmp     .do_macro                      ; %rmacro is %macro
.m_depend:
    mov     rdi, rbx
    call    prep_handle_depend
    jmp     .done_cleanup
.m_pathsearch:
    mov     rdi, rbx
    call    prep_handle_pathsearch
    jmp     .done_cleanup
.m_iftest:
    sub     eax, 64
    mov     edx, eax
    and     edx, 3                         ; negate / elif
    shr     eax, 2
    mov     esi, eax                       ; IFT_*
    mov     rdi, rbx
    call    prep_handle_iftest
    jmp     .done_cleanup
.m_defstr:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_defstr
    jmp     .done_cleanup
.m_idefstr:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_defstr
    jmp     .done_cleanup
.m_imacro:
    mov     byte [rel mdef_icase], 1
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_macro_normal
    mov     byte [rel mdef_icase], 0
    jmp     .do_macro
.m_exitmacro:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_exit
    jmp     .done_cleanup
.m_repl:
    mov     rdi, rbx
    call    prep_handle_repl
    jmp     .done_cleanup
.m_line:
    mov     rdi, rbx
    call    prep_handle_line
    jmp     .done_cleanup
.m_use:
    mov     rdi, rbx
    call    prep_handle_use
    jmp     .done_cleanup
.m_pragma:
    mov     rdi, rbx
    call    prep_drain_line
    xor     eax, eax
    jmp     .done_cleanup
.m_clear:
    mov     rdi, rbx
    call    prep_handle_clear
    jmp     .done_cleanup
.m_iassign:
    mov     rdi, rbx
    call    prep_handle_iassign
    jmp     .done_cleanup
.m_defalias:
    mov     rdi, rbx                       ; an alias reads as its target
    call    prep_handle_def
    jmp     .done_cleanup
.m_ifidn:
    mov     rdi, rbx
    call    prep_handle_ifidn
    jmp     .done_cleanup
.m_ifnidn:
    mov     rdi, rbx
    call    prep_handle_ifnidn
    jmp     .done_cleanup
.m_ifnidni:
    mov     rdi, rbx
    call    prep_handle_ifnidni
    jmp     .done_cleanup
.m_elifidn:
    mov     rdi, rbx
    call    prep_handle_elifidn
    jmp     .done_cleanup
.m_warning:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_message
    jmp     .done_cleanup
.m_fatal:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_message
    jmp     .done_cleanup
.m_exitrep:
    mov     rdi, rbx
    call    prep_handle_exitrep
    jmp     .done_cleanup
.m_strcat:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_strtok
    jmp     .done_cleanup
.m_deftok:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_strtok
    jmp     .done_cleanup
.more_done:

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_if]
    call    str_cmp
    test    rax, rax
    jz      .do_if

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifdef]
    call    str_cmp
    test    rax, rax
    jz      .do_ifdef

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifndef]
    call    str_cmp
    test    rax, rax
    jz      .do_ifndef

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_else]
    call    str_cmp
    test    rax, rax
    jz      .do_else

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endif]
    call    str_cmp
    test    rax, rax
    jz      .do_endif

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .do_macro

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_struc]
    call    str_cmp
    test    rax, rax
    jz      .do_struc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_unmacro]
    call    str_cmp
    test    rax, rax
    jz      .do_unmacro

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_unimacro]
    call    str_cmp
    test    rax, rax
    jz      .do_unmacro

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .do_rep

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .do_endrep

    jmp     .discard_unknown

.do_struc:
    ; TODO: implement %struc
    ; call prep_handle_struc
    jmp     .done_cleanup

.do_inc:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_inc
    jmp     .done_cleanup

.do_def:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_assign:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_assign
    jmp     .done_cleanup

.do_push:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_push
    jmp     .done_cleanup

.do_pop:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_pop
    jmp     .done_cleanup

.do_ifctx:
    mov     rdi, rbx
    mov     esi, IFT_CTX
    xor     edx, edx
    call    prep_handle_iftest
    jmp     .done_cleanup

.do_ifidni:
    mov     rdi, rbx
    call    prep_handle_ifidni
    jmp     .done_cleanup

.do_elifidni:
    mov     rdi, rbx
    call    prep_handle_elifidni
    jmp     .done_cleanup

.do_elif:
    mov     rdi, rbx
    call    prep_handle_elif
    jmp     .done_cleanup

.do_error:
    mov     rdi, rbx
    call    prep_handle_error
    jmp     .done_cleanup

.do_strlen:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_strlen
    jmp     .done_cleanup

.do_substr:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_substr
    jmp     .done_cleanup

.do_idefine:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_icase], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_xdefine:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_eager], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_undef:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_undef
    jmp     .done_cleanup

.do_rotate:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    extern  prep_handle_rotate
    call    prep_handle_rotate             ; frontend/macro/rotate.s
    jmp     .done_cleanup




.do_if:
    mov     rdi, rbx
    call    prep_handle_if
    jmp     .done_cleanup

.do_ifdef:
    mov     rdi, rbx
    mov     esi, IFT_DEF
    xor     edx, edx
    call    prep_handle_iftest
    jmp     .done_cleanup

.do_ifndef:
    mov     rdi, rbx
    mov     esi, IFT_DEF
    mov     edx, 1                         ; negated
    call    prep_handle_iftest
    jmp     .done_cleanup

.do_else:
    mov     rdi, rbx
    call    prep_handle_else
    jmp     .done_cleanup

.do_endif:
    mov     rdi, rbx
    call    prep_handle_endif
    jmp     .done_cleanup

.do_macro:
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_macro_normal
    mov     rdi, rbx
    call    prep_skip_macro_block
    jmp     .done_cleanup
.do_macro_normal:
    mov     rax, [r12 + TOKEN_value]       ; macro / imacro / rmacro: messages
    mov     [rel mdef_dir], rax
    mov     rdi, rbx
    call    macro_handle_def
    jmp     .done_cleanup

.do_unmacro:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup          ; inside a skipped block: ignore entirely
    mov     rdi, rbx
    call    prep_handle_unmacro
    jmp     .done_cleanup

.do_rep:
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_rep_normal
    mov     rdi, rbx
    call    prep_skip_rep_block
    jmp     .done_cleanup
.do_rep_normal:
    mov     rdi, rbx
    call    prep_handle_rep
    jmp     .done_cleanup

.do_endrep:
    mov     rax, EXIT_NO_REP               ; no %rep is being read
    jmp     .done_cleanup

.error_pop_rsp:
    mov     rax, EXIT_ERROR
    jmp     .done_cleanup

.expected_ident_pop_rsp:
    mov     rax, EXIT_ERROR
    jmp     .done_cleanup

.discard_unknown:
    ; A misspelt directive must not vanish silently. Inside a skipped %if
    ; branch nothing is checked, and names that do not start with a letter
    ; (%1, %{1..}) are macro parameter forms, left as before.
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .discard_quietly
    ; %endmacro / %endm with no %macro being read
    mov     rdi, [r12 + TOKEN_value]
    call    prep_is_macro_end
    jnz     .not_macro_end
    mov     rdi, [r12 + TOKEN_value]
    call    error_set_subject
    mov     rax, EXIT_NOT_DEFINING
    jmp     .done_cleanup
.not_macro_end:
    mov     rax, [r12 + TOKEN_value]
    test    rax, rax
    jz      .discard_quietly
    movzx   eax, byte [rax]
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 25
    ja      .discard_quietly
    mov     rdi, [r12 + TOKEN_value]
    call    error_set_subject
    mov     rax, EXIT_UNKNOWN_DIRECTIVE
    jmp     .done_cleanup
.discard_quietly:
    sub     rsp, TOKEN_SIZE
.discard_unknown_loop:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .discard_unknown_done
    cmp     byte [rsp + TOKEN_kind], TOK_NEWLINE
    je      .discard_unknown_done
    cmp     byte [rsp + TOKEN_kind], TOK_EOF
    je      .discard_unknown_done
    jmp     .discard_unknown_loop
.discard_unknown_done:
    add     rsp, TOKEN_SIZE
    xor     rax, rax
    jmp     .done_cleanup

.done_cleanup:
    test    r14, r14
    jz      .done
    add     rsp, TOKEN_SIZE

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_handle_inc --------------------
;
; prep_handle_inc
; Handles the %include directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_inc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi

    ; Allocate stack space for:
    ; [rsp + 0]  : temporary TOKEN (32 bytes)
    ; [rsp + 32] : new_lexer pointer (8 bytes)
    ; [rsp + 40] : saved depth (8 bytes)
    sub     rsp, 64                ; 32 (token) + 8 (IncludeCtx) + 8 (new_lexer) + 8 (depth) + 8 (padding) = 64
    
    ; 1. Get filename token
    mov     rdi, [rbx + PREP_lexer]
    lea     r12, [rsp]             ; r12 = temporary token buffer
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    je      .name_string
    ; 'file.inc': eight characters or fewer lex as a character constant
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    jne     .error_expected_string
    mov     rdx, r12
    call    prep_token_text
    mov     r12, rax                 ; r12 = filename string
    jmp     .name_done
.name_string:
    mov     r12, [r12 + TOKEN_value] ; r12 = filename string
.name_done:

    ; 2. Check include depth
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    xor     r14, r14               ; r14 = depth
    test    r9, r9
    jz      .depth_ok
    movzx   r14, word [r9 + INCLUDECTX_depth]
    inc     r14
    cmp     r14, MAX_INCLUDES
    jge     .error_too_deep
.depth_ok:
    mov     [rsp + 56], r14         ; save depth at [rsp+56]

    ; 3. Open file: as named, then in each -I directory
    mov     rdi, r12
    extern  incpath_open
    call    incpath_open
    test    rax, rax
    jnz     .error_open
    mov     r12, rcx               ; the name it was found under
    mov     r13, rdx               ; r13 = fd

    ; 4. Get file size
    mov     rdi, r13
    call    io_file_size
    test    rax, rax
    jnz     .error_size
    mov     r14, rdx               ; r14 = size

    ; 5. Map file into memory
    xor     rdi, rdi               ; addr = NULL
    mov     rsi, r14               ; length
    mov     rdx, PROT_READ         ; prot
    mov     rcx, MAP_PRIVATE       ; flags
    mov     r8, r13                ; fd
    xor     r9, r9                 ; offset = 0
    call    io_mmap
    test    rax, rax
    jnz     .error_mmap
    mov     r15, rdx               ; r15 = buffer

    ; 6. Create new LexerState
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error_oom
    mov     rcx, rdx                ; rcx = new lexer (using rcx temp)

    ; initialize new lexer
    ; We need to save new_lexer somewhere safe while calling lexer_init
    ; Let's use the 16-byte aligned stack space we already have
    mov     [rsp + 48], rcx         ; save new_lexer at [rsp+48]
    
    mov     rdi, rcx
    mov     rsi, r15               ; buf
    mov     rdx, r14               ; size
    mov     r11, r12               ; filename string (save to r11)
    mov     rcx, r11
    mov     r8, [rbx + PREP_ctx]   ; r8 = AsmCtx
    mov     r9, [rbx + PREP_arena] ; r9 = Arena
    call    lexer_init
    test    rax, rax
    jnz     .error_open            ; check for init failure

    ; 7. Save state in IncludeCtx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, INCLUDECTX_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error_oom
    mov     r9, rdx                ; r9 = new IncludeCtx
    mov     [rsp + 40], r9         ; save IncludeCtx ptr at [rsp+40]

    mov     byte [r9 + INCLUDECTX_tag], TAG_INCLUDE_CTX
    
    mov     r10, [rbx + PREP_ctx]
    mov     r11, [r10 + ASMCTX_inc_ctx]
    mov     [r9 + INCLUDECTX_parent], r11 ; link to previous
    mov     [r10 + ASMCTX_inc_ctx], r9    ; update current in AsmCtx
    
    mov     [r9 + INCLUDECTX_buf], r15
    mov     [r9 + INCLUDECTX_size], r14
    
    mov     r9, [rsp + 40]         ; restore IncludeCtx ptr
    
    mov     rax, [rbx + PREP_lexer]
    mov     [r9 + INCLUDECTX_lexer], rax
    movzx   rax, word [rsp + 56]   ; depth
    mov     word [r9 + INCLUDECTX_depth], ax
    
    mov     r8, [rsp + 48]         ; restore new_lexer
    mov     [rbx + PREP_lexer], r8 ; Switch to new lexer

    ; 8. Close the fd
    mov     rdi, r13
    call    io_close

    xor     rax, rax
    jmp     .done

.error_oom:
    mov     rax, EXIT_OOM
    jmp     .done

.error_expected_string:
    mov     rax, EXIT_INC_NAME
    jmp     .done

.error_too_deep:
    mov     rax, EXIT_INC_DEPTH
    jmp     .done

.error_open:
    mov     rdi, r12                   ; "unable to open include file `x'"
    call    error_set_subject
    mov     rax, EXIT_INC_NOT_FOUND
    jmp     .done

.error_size:
.error_mmap:
    mov     rdi, r12
    call    error_set_subject
    mov     rax, EXIT_FILE_READ
    jmp     .done

.error:
    jmp     .done                      ; the lexer's own code

.done:
    add     rsp, 64                ; Clean up our stack frame
    pop     rcx                    ; Alignment padding
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret
    ret


[SECTION .rodata]
s_dot:          db ".", 0             ; (..@N.name)
dir_inc:    db "include", 0
dir_def:    db "define", 0
dir_assign: db "assign", 0
dir_push:   db "push", 0
dir_pop:    db "pop", 0
dir_ifctx:  db "ifctx", 0
dir_ifidni:   db "ifidni", 0
dir_elifidni: db "elifidni", 0
dir_elif:     db "elif", 0
dir_error:    db "error", 0
dir_strlen:   db "strlen", 0
dir_substr:   db "substr", 0
dir_rotate:   db "rotate", 0
dir_def_short: db "def", 0          ; utasm short forms: %def, %inc
dir_inc_short: db "inc", 0
dir_xdefine:  db "xdefine", 0       ; %define is already expanded eagerly
dir_rmacro:   db "rmacro", 0
dir_imacro:   db "imacro", 0
dir_irmacro:  db "irmacro", 0
[SECTION .data]
align 8
; prep_idn_collect's buffers: pointer, capacity (they grow)
idn_left:      dq idn_left_buf, IDN_BUF
idn_right:     dq idn_right_buf, IDN_BUF
[SECTION .data]
align 8
def_toks:      dq def_scratch      ; a %define's tokens: def_scratch, or an
                                   ; arena array once it outgrows it
[SECTION .data]
align 8
stk_reg:      dq stk_modes + 10      ; %stacksize: flat until set
stk_size:     dd 4
stk_arg:      dd 8
stk_local:    dd 0
[SECTION .rodata]
dir_arg:      db "arg", 0
dir_local:    db "local", 0
stk_define:   db "%define ", 0
stk_assign:   db "%assign %$localsize %$localsize+", 0
; %stacksize: name (8), slot size, first argument, frame register (6)
stk_modes:    db "flat", 0, 0, 0, 0, 4, 8, "ebp", 0, 0, 0
              db "flat64", 0, 0, 8, 16, "rbp", 0, 0, 0
              db "large", 0, 0, 0, 2, 4, "bp", 0, 0, 0, 0
              db "small", 0, 0, 0, 2, 6, "bp", 0, 0, 0, 0
              db 0
; %arg / %local types: name (7), size
stk_types:    db "byte", 0, 0, 0, 1
              db "word", 0, 0, 0, 2
              db "dword", 0, 0, 4
              db "qword", 0, 0, 8
              db "tword", 0, 0, 10
              db 0
dir_undef:    db "undef", 0
dir_idefine:  db "idefine", 0       ; treated as %define
; more directives: 15-byte name + handler number (see .more_table)
dir_more:     db "ifidn", 0, 0,0,0,0,0,0,0,0,0, 0
              db "ifnidn", 0, 0,0,0,0,0,0,0,0, 1
              db "ifnidni", 0, 0,0,0,0,0,0,0, 2
              db "elifidn", 0, 0,0,0,0,0,0,0, 3
              db "warning", 0, 0,0,0,0,0,0,0, 4
              db "fatal", 0, 0,0,0,0,0,0,0,0,0, 5
              db "exitrep", 0, 0,0,0,0,0,0,0, 6
              db "strcat", 0, 0,0,0,0,0,0,0,0, 7
              db "deftok", 0, 0,0,0,0,0,0,0,0, 8
              db "defstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 9
              db "imacro", 0, 0, 0, 0, 0, 0, 0, 0, 0, 10
              db "exitmacro", 0, 0, 0, 0, 0, 0, 11
              db "repl", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12
              db "line", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13
              db "use", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14
              db "pragma", 0, 0, 0, 0, 0, 0, 0, 0, 0, 15
              db "clear", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16
              db "iassign", 0, 0, 0, 0, 0, 0, 0, 0, 17
              db "defalias", 0, 0, 0, 0, 0, 0, 0, 18
              db "idefstr", 0, 0, 0, 0, 0, 0, 0, 0, 19
              db "ifnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68
              db "ifnnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 69
              db "elifnum", 0, 0, 0, 0, 0, 0, 0, 0, 70
              db "elifnnum", 0, 0, 0, 0, 0, 0, 0, 71
              db "ifstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 72
              db "ifnstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 73
              db "elifstr", 0, 0, 0, 0, 0, 0, 0, 0, 74
              db "elifnstr", 0, 0, 0, 0, 0, 0, 0, 75
              db "ifid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 76
              db "ifnid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 77
              db "elifid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 78
              db "elifnid", 0, 0, 0, 0, 0, 0, 0, 0, 79
              db "ifempty", 0, 0, 0, 0, 0, 0, 0, 0, 80
              db "ifnempty", 0, 0, 0, 0, 0, 0, 0, 81
              db "elifempty", 0, 0, 0, 0, 0, 0, 82
              db "elifnempty", 0, 0, 0, 0, 0, 83
              db "ifmacro", 0, 0, 0, 0, 0, 0, 0, 0, 84
              db "ifnmacro", 0, 0, 0, 0, 0, 0, 0, 85
              db "elifmacro", 0, 0, 0, 0, 0, 0, 86
              db "elifnmacro", 0, 0, 0, 0, 0, 87
              db "elifdef", 0, 0, 0, 0, 0, 0, 0, 0, 90
              db "elifndef", 0, 0, 0, 0, 0, 0, 0, 91
              db "ifnctx", 0, 0, 0, 0, 0, 0, 0, 0, 0, 93
              db "elifctx", 0, 0, 0, 0, 0, 0, 0, 0, 94
              db "elifnctx", 0, 0, 0, 0, 0, 0, 0, 95
              db "ifenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 96
              db "ifnenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 97
              db "elifenv", 0, 0, 0, 0, 0, 0, 0, 0, 98
              db "elifnenv", 0, 0, 0, 0, 0, 0, 0, 99
              db "iftoken", 0, 0, 0, 0, 0, 0, 0, 0, 100
              db "ifntoken", 0, 0, 0, 0, 0, 0, 0, 101
              db "eliftoken", 0, 0, 0, 0, 0, 0, 102
              db "elifntoken", 0, 0, 0, 0, 0, 103
              db "ifn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20
              db "elifn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21
              db "ixdefine", 0, 0, 0, 0, 0, 0, 0, 22
              db "rmacro", 0, 0, 0, 0, 0, 0, 0, 0, 0, 23
              db "irmacro", 0, 0, 0, 0, 0, 0, 0, 0, 24
              db "depend", 0, 0, 0, 0, 0, 0, 0, 0, 0, 25
              db "pathsearch", 0, 0, 0, 0, 0, 26
              db "stacksize", 0, 0, 0, 0, 0, 0, 27
              db "arg", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 28
              db "local", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29
db 0
; ---- predefined macro names ---------------
%define DYN_LINE    1
%define DYN_FILE    2
%define DYN_BITS    3
%define DYN_PASS    4
%define DYN_FORMAT  5
%define DYN_SECT    6
pd_major:    db "__NASM_MAJOR__", 0
pd_major_q:  db "__?NASM_MAJOR?__", 0
pd_minor:    db "__NASM_MINOR__", 0
pd_minor_q:  db "__?NASM_MINOR?__", 0
pd_sub:      db "__NASM_SUBMINOR__", 0
pd_patch:    db "__NASM_PATCHLEVEL__", 0
pd_verid:    db "__NASM_VERSION_ID__", 0
pd_ver:      db "__NASM_VER__", 0
pd_ver_q:    db "__?NASM_VER?__", 0
pd_utasm:    db "__UTASM__", 0
; the time of assembly (lib/time.s)
pt_date:      db "__DATE__", 0
pt_date_q:    db "__?DATE?__", 0
pt_time:      db "__TIME__", 0
pt_time_q:    db "__?TIME?__", 0
pt_date_num:  db "__DATE_NUM__", 0
pt_date_num_q: db "__?DATE_NUM?__", 0
pt_time_num:  db "__TIME_NUM__", 0
pt_time_num_q: db "__?TIME_NUM?__", 0
pt_utc_date:  db "__UTC_DATE__", 0
pt_utc_date_q: db "__?UTC_DATE?__", 0
pt_utc_time:  db "__UTC_TIME__", 0
pt_utc_time_q: db "__?UTC_TIME?__", 0
pt_utc_date_num: db "__UTC_DATE_NUM__", 0
pt_utc_date_num_q: db "__?UTC_DATE_NUM?__", 0
pt_utc_time_num: db "__UTC_TIME_NUM__", 0
pt_utc_time_num_q: db "__?UTC_TIME_NUM?__", 0
pt_posix_time: db "__POSIX_TIME__", 0
pt_posix_time_q: db "__?POSIX_TIME?__", 0
pv_2:        db "2", 0
pv_16:       db "16", 0
pv_3:        db "3", 0
pv_0:        db "0", 0
pv_1:        db "1", 0
pv_verid:    db "0x02100300", 0
pv_ver:      db "2.16.03", 0
dn_line:     db "__LINE__", 0
dn_line_q:   db "__?LINE?__", 0
dn_file:     db "__FILE__", 0
dn_file_q:   db "__?FILE?__", 0
dn_bits:     db "__BITS__", 0
dn_bits_q:   db "__?BITS?__", 0
dn_pass:     db "__PASS__", 0
dn_pass_q:   db "__?PASS?__", 0
dn_fmt:      db "__OUTPUT_FORMAT__", 0
dn_fmt_q:    db "__?OUTPUT_FORMAT?__", 0
dyn_sect_name: db "__SECT__", 0
dn_sect_q:   db "__?SECT?__", 0
dyn_fmt_bin: db "bin", 0
dyn_fmt_elf64: db "elf64", 0
dyn_fmt_elf32: db "elf32", 0
dyn_section_word: db "section", 0
dyn_no_file: db 0
use_altreg:  db "altreg", 0
use_fp:      db "fp", 0
; NASM's fp package; the leading newline ends the %use line first
use_smartalign: db "smartalign", 0
use_smartalign_text: db 10
             db "%define __?USE_SMARTALIGN?__", 10
             db "%define __USE_SMARTALIGN__", 10
use_smartalign_text_len equ $ - use_smartalign_text
use_fp_text: db 10
             db "%define __?USE_FP?__", 10
             db "%define __USE_FP__", 10
db "%define float16(x) __float16__(x)", 10
             db "%define float32(x) __float32__(x)", 10
             db "%define float64(x) __float64__(x)", 10
             db "%define float80m(x) __float80m__(x)", 10
             db "%define float80e(x) __float80e__(x)", 10
             db "%define float128l(x) __float128l__(x)", 10
             db "%define float128h(x) __float128h__(x)", 10
             db "%define Inf __Infinity__", 10
             db "%define NaN __QNaN__", 10
             db "%define QNaN __QNaN__", 10
             db "%define SNaN __SNaN__", 10
use_fp_text_len equ $ - use_fp_text
alt_n0: db "r0", 0
alt_v0: db "rax", 0
alt_n1: db "r0d", 0
alt_v1: db "eax", 0
alt_n2: db "r0w", 0
alt_v2: db "ax", 0
alt_n3: db "r0b", 0
alt_v3: db "al", 0
alt_n4: db "r0l", 0
alt_v4: db "al", 0
alt_n5: db "r1", 0
alt_v5: db "rcx", 0
alt_n6: db "r1d", 0
alt_v6: db "ecx", 0
alt_n7: db "r1w", 0
alt_v7: db "cx", 0
alt_n8: db "r1b", 0
alt_v8: db "cl", 0
alt_n9: db "r1l", 0
alt_v9: db "cl", 0
alt_n10: db "r2", 0
alt_v10: db "rdx", 0
alt_n11: db "r2d", 0
alt_v11: db "edx", 0
alt_n12: db "r2w", 0
alt_v12: db "dx", 0
alt_n13: db "r2b", 0
alt_v13: db "dl", 0
alt_n14: db "r2l", 0
alt_v14: db "dl", 0
alt_n15: db "r3", 0
alt_v15: db "rbx", 0
alt_n16: db "r3d", 0
alt_v16: db "ebx", 0
alt_n17: db "r3w", 0
alt_v17: db "bx", 0
alt_n18: db "r3b", 0
alt_v18: db "bl", 0
alt_n19: db "r3l", 0
alt_v19: db "bl", 0
alt_n20: db "r4", 0
alt_v20: db "rsp", 0
alt_n21: db "r4d", 0
alt_v21: db "esp", 0
alt_n22: db "r4w", 0
alt_v22: db "sp", 0
alt_n23: db "r4b", 0
alt_v23: db "spl", 0
alt_n24: db "r4l", 0
alt_v24: db "spl", 0
alt_n25: db "r5", 0
alt_v25: db "rbp", 0
alt_n26: db "r5d", 0
alt_v26: db "ebp", 0
alt_n27: db "r5w", 0
alt_v27: db "bp", 0
alt_n28: db "r5b", 0
alt_v28: db "bpl", 0
alt_n29: db "r5l", 0
alt_v29: db "bpl", 0
alt_n30: db "r6", 0
alt_v30: db "rsi", 0
alt_n31: db "r6d", 0
alt_v31: db "esi", 0
alt_n32: db "r6w", 0
alt_v32: db "si", 0
alt_n33: db "r6b", 0
alt_v33: db "sil", 0
alt_n34: db "r6l", 0
alt_v34: db "sil", 0
alt_n35: db "r7", 0
alt_v35: db "rdi", 0
alt_n36: db "r7d", 0
alt_v36: db "edi", 0
alt_n37: db "r7w", 0
alt_v37: db "di", 0
alt_n38: db "r7b", 0
alt_v38: db "dil", 0
alt_n39: db "r7l", 0
alt_v39: db "dil", 0
alt_n40: db "r0h", 0
alt_v40: db "ah", 0
alt_n41: db "r1h", 0
alt_v41: db "ch", 0
alt_n42: db "r2h", 0
alt_v42: db "dh", 0
alt_n43: db "r3h", 0
alt_v43: db "bh", 0
idn_unknown: db "?", 0
; token kinds without text: kind, text (NUL-terminated, 4 bytes a row)
idn_punct:
    db TOK_LBRACKET, "[", 0, 0
    db TOK_RBRACKET, "]", 0, 0
    db TOK_LPAREN, "(", 0, 0
    db TOK_RPAREN, ")", 0, 0
    db TOK_COMMA, ",", 0, 0
    db TOK_COLON, ":", 0, 0
    db TOK_PLUS, "+", 0, 0
    db TOK_MINUS, "-", 0, 0
    db TOK_STAR, "*", 0, 0
    db TOK_SLASH, "/", 0, 0
    db TOK_PERCENT, "%", 0, 0
    db TOK_AMPERSAND, "&", 0, 0
    db TOK_PIPE, "|", 0, 0
    db TOK_CARET, "^", 0, 0
    db TOK_TILDE, "~", 0, 0
    db TOK_LSHIFT, "<<", 0
    db TOK_RSHIFT, ">>", 0
    db TOK_EQUAL, "==", 0
    db TOK_NEQUAL, "!=", 0
    db TOK_LT, "<", 0, 0
    db TOK_GT, ">", 0, 0
    db TOK_LE, "<=", 0
    db TOK_GE, ">=", 0
    db TOK_DOLLAR, "$", 0, 0
    db TOK_LBRACE, "{", 0, 0
    db TOK_RBRACE, "}", 0, 0
    db TOK_QUESTION, "?", 0, 0
    db TOK_NOT, "!", 0, 0
    db 0
align 8
; name, value, token kind (0: an empty definition)
predef_table:
    dq pd_major, pv_2, TOK_NUMBER
    dq pd_major_q, pv_2, TOK_NUMBER
    dq pd_minor, pv_16, TOK_NUMBER
    dq pd_minor_q, pv_16, TOK_NUMBER
    dq pd_sub, pv_3, TOK_NUMBER
    dq pd_patch, pv_0, TOK_NUMBER
    dq pd_verid, pv_verid, TOK_NUMBER
    dq pd_ver, pv_ver, TOK_STRING
    dq pd_ver_q, pv_ver, TOK_STRING
    dq pd_utasm, pv_1, TOK_NUMBER
    dq pt_date, time_local, TOK_STRING
    dq pt_date_q, time_local, TOK_STRING
    dq pt_time, time_local + 16, TOK_STRING
    dq pt_time_q, time_local + 16, TOK_STRING
    dq pt_date_num, time_local + 32, TOK_NUMBER
    dq pt_date_num_q, time_local + 32, TOK_NUMBER
    dq pt_time_num, time_local + 48, TOK_NUMBER
    dq pt_time_num_q, time_local + 48, TOK_NUMBER
    dq pt_utc_date, time_utc, TOK_STRING
    dq pt_utc_date_q, time_utc, TOK_STRING
    dq pt_utc_time, time_utc + 16, TOK_STRING
    dq pt_utc_time_q, time_utc + 16, TOK_STRING
    dq pt_utc_date_num, time_utc + 32, TOK_NUMBER
    dq pt_utc_date_num_q, time_utc + 32, TOK_NUMBER
    dq pt_utc_time_num, time_utc + 48, TOK_NUMBER
    dq pt_utc_time_num_q, time_utc + 48, TOK_NUMBER
    dq pt_posix_time, time_posix, TOK_NUMBER
    dq pt_posix_time_q, time_posix, TOK_NUMBER
dq dn_line, 0, 0
    dq dn_file, 0, 0
    dq dn_bits, 0, 0
    dq dn_pass, 0, 0
    dq dn_fmt, 0, 0
    dq dyn_sect_name, 0, 0
    dq 0
; %use altreg: name, register
altreg_table:
    dq alt_n0, alt_v0
    dq alt_n1, alt_v1
    dq alt_n2, alt_v2
    dq alt_n3, alt_v3
    dq alt_n4, alt_v4
    dq alt_n5, alt_v5
    dq alt_n6, alt_v6
    dq alt_n7, alt_v7
    dq alt_n8, alt_v8
    dq alt_n9, alt_v9
    dq alt_n10, alt_v10
    dq alt_n11, alt_v11
    dq alt_n12, alt_v12
    dq alt_n13, alt_v13
    dq alt_n14, alt_v14
    dq alt_n15, alt_v15
    dq alt_n16, alt_v16
    dq alt_n17, alt_v17
    dq alt_n18, alt_v18
    dq alt_n19, alt_v19
    dq alt_n20, alt_v20
    dq alt_n21, alt_v21
    dq alt_n22, alt_v22
    dq alt_n23, alt_v23
    dq alt_n24, alt_v24
    dq alt_n25, alt_v25
    dq alt_n26, alt_v26
    dq alt_n27, alt_v27
    dq alt_n28, alt_v28
    dq alt_n29, alt_v29
    dq alt_n30, alt_v30
    dq alt_n31, alt_v31
    dq alt_n32, alt_v32
    dq alt_n33, alt_v33
    dq alt_n34, alt_v34
    dq alt_n35, alt_v35
    dq alt_n36, alt_v36
    dq alt_n37, alt_v37
    dq alt_n38, alt_v38
    dq alt_n39, alt_v39
    dq alt_n40, alt_v40
    dq alt_n41, alt_v41
    dq alt_n42, alt_v42
    dq alt_n43, alt_v43
    dq 0
; the ones with a value of the moment: name, DYN_*
dyn_table:
    dq dn_line, DYN_LINE
    dq dn_line_q, DYN_LINE
    dq dn_file, DYN_FILE
    dq dn_file_q, DYN_FILE
    dq dn_bits, DYN_BITS
    dq dn_bits_q, DYN_BITS
    dq dn_pass, DYN_PASS
    dq dn_pass_q, DYN_PASS
    dq dn_fmt, DYN_FORMAT
    dq dn_fmt_q, DYN_FORMAT
    dq dyn_sect_name, DYN_SECT
    dq dn_sect_q, DYN_SECT
    dq 0
str_nolist:   db ".nolist", 0
msg_space:    db " ", 0
; "0".."9" for the %N references of a function-like %define
def_digits:   db "0", 0, "1", 0, "2", 0, "3", 0, "4", 0, "5", 0, "6", 0, "7", 0, "8", 0, "9", 0
undef_name:   db 0                  ; the name of an %undef'd entry
dir_if:     db "if", 0
dir_ifdef:  db "ifdef", 0
dir_ifndef: db "ifndef", 0
dir_else:   db "else", 0
dir_endif:  db "endif", 0
dir_rep:    db "rep", 0
dir_endrep: db "endrep", 0
dir_macro:  db "macro", 0
dir_endm:   db "endmacro", 0
dir_endm_short: db "endm", 0
s_macro_defaults: db "too many default macro parameters in macro `", 0
s_quote_end: db "'", 0
s_unmacro:  db "unmacro", 0
dir_struc:  db "struc", 0
dir_endstruc: db "endstruc", 0
dir_unmacro:  db "unmacro", 0
dir_unimacro: db "unimacro", 0

msg_preprocessor_dir_trace: db "[+] PREP: Directive: ", 0
msg_newline:                db 10, 0

dbg_msg1:     db "prep_handle_directive: kind=", 0
dbg_msg2:     db " value=", 0
dbg_msg3:     db " (not directive)", 0
dbg_msg_null: db "<null>", 0
dbg_newline:  db 10, 0
[SECTION .data]

; ---- prep_handle_struc ------------------
;
[SECTION .text]
; prep_handle_struc
    push    rbx
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Lex the struct name
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    
    ; 2. Dispatch to parser
    mov     rdi, rbx               ; rdi = PrepState
    mov     rsi, rdx               ; rsi = Name Token
    extern  parser_parse_struc
    call    parser_parse_struc
    
.error:
    pop     rbx
    ret
; ---- prep_subst_const_text --------------
;
; prep_subst_const_text
; If the token names a %assign / %define constant, replace its text with the
; constant's value in decimal. Pasting joins text, and "%assign i 7" makes i
; a numeric macro: ".lbl_ %+ i" has to produce ".lbl_7", not ".lbl_i". A
; %define of one token, with no parameters, stands for that token ("%define
; P ab": "P %+ cd" is abcd, as NASM expands before it pastes), and so on
; down a chain of them.
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (rewritten in place)
;
prep_subst_const_text:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    mov     r13d, 32                       ; (a %define naming itself)
.lookup:
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .done

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .one_token_define
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .done
    mov     r13, [rdx + SYMBOL_value]

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .done

    mov     rdi, rdx
    mov     [r12 + TOKEN_value], rdx
    mov     rsi, r13
    call    str_int_to_str
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    jmp     .done

.one_token_define:
    mov     rax, [rdx + SYMBOL_value]      ; MACRO*
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .done
    cmp     word [rax + MACRO_max_params], 0
    jne     .done
    cmp     dword [rax + MACRO_ntokens], 1
    jne     .done
    mov     rax, [rax + MACRO_tokens]
    mov     cl, [rax + TOKEN_kind]
    cmp     cl, TOK_IDENT
    je      .define_text
    cmp     cl, TOK_NUMBER
    jne     .done
.define_text:
    mov     [r12 + TOKEN_kind], cl
    mov     rax, [rax + TOKEN_value]
    mov     [r12 + TOKEN_value], rax
    dec     r13d
    jnz     .lookup

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_file_paste --------------------
;
; "P %+ cd" in the source itself (a body's %+ is joined as the body is
; served, prep_expand_next): the token just read, r12, joined with the one
; after the %+ - each first as the constant or one-token %define it names
; (prep_subst_const_text) - and again for "a %+ b %+ c". prep_internal_next
; then looks the result up like any token ("abcd" can be a %define).
; The %+ is found by reading the source bytes, not by lexing ahead: the
; lexer's line must not move past this line (%line relies on it).
; Input    : rbx = PrepState, r12 = the token just read from the lexer
; Output   : rax = EXIT_OK or an error
;
prep_file_paste:
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .pasteable
    cmp     eax, TOK_NUMBER
    jne     .none
.pasteable:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .none
    ; a %define body keeps its %+ until it is expanded ("%define J(a,b)
    ; a %+ b" joins the arguments, not a and b)
    cmp     byte [rel prep_noexpand], 0
    jne     .none
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE
    mov     r13, [rbx + PREP_lexer]
.again:
    cmp     byte [r13 + LEXER_has_peek], TRUE
    jne     .scan
    cmp     byte [r13 + LEXER_peek + TOKEN_kind], TOK_CONCAT
    jne     .ok
    jmp     .paste
.scan:
    mov     rsi, [r13 + LEXER_pos]
    mov     rdi, [r13 + LEXER_end]
.blank:
    cmp     rsi, rdi
    jae     .ok
    mov     al, [rsi]
    cmp     al, ' '
    je      .blank_next
    cmp     al, 9
    jne     .blank_done
.blank_next:
    inc     rsi
    jmp     .blank
.blank_done:
    cmp     al, '%'
    jne     .ok
    lea     rax, [rsi + 1]
    cmp     rax, rdi
    jae     .ok
    cmp     byte [rsi + 1], '+'
    jne     .ok
.paste:
    mov     rdi, r13
    mov     rsi, rsp
    call    lexer_next                     ; the %+
    test    rax, rax
    jnz     .out
    mov     rdi, r13
    mov     rsi, rsp
    call    lexer_next                     ; what it joins on
    test    rax, rax
    jnz     .out
    movzx   eax, byte [rsp + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .join
    cmp     eax, TOK_NUMBER
    je      .join
    cmp     eax, TOK_LABEL
    je      .join
    cmp     eax, TOK_LOCAL_LABEL
    je      .join
    ; nothing to join ("x %+" at the end of the line): NASM's error; what
    ; followed is read next
    lea     rdi, [r13 + LEXER_peek]
    mov     rsi, rsp
    copy_token
    mov     byte [r13 + LEXER_has_peek], TRUE
    mov     eax, EXIT_INVALID_EXPR
    jmp     .out
.join:
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_subst_const_text
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_subst_const_text
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MAX_TOKEN
    call    arena_alloc
    test    rax, rax
    jnz     .out
    mov     r14, rdx
    mov     byte [r14], 0
    mov     rdi, r14
    mov     rsi, [r12 + TOKEN_value]
    call    str_concat
    mov     rdi, r14
    mov     rsi, [rsp + TOKEN_value]
    call    str_concat
    ; a label when the right piece carried the ':'; a number when it
    ; starts with a digit ("1 %+ 2")
    mov     byte [r12 + TOKEN_kind], TOK_IDENT
    mov     cl, [rsp + TOKEN_kind]
    cmp     cl, TOK_LABEL
    je      .label
    cmp     cl, TOK_LOCAL_LABEL
    je      .label
    movzx   eax, byte [r14]
    sub     eax, '0'
    cmp     eax, 9
    ja      .kind_set
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
    jmp     .kind_set
.label:
    mov     byte [r12 + TOKEN_kind], TOK_LABEL
    cmp     byte [r14], '.'
    jne     .kind_set
    mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
.kind_set:
    mov     [r12 + TOKEN_value], r14
    mov     rdi, r14
    call    str_len
    mov     [r12 + TOKEN_len], ax
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    je      .again                         ; "a %+ b %+ c"
    cmp     byte [r12 + TOKEN_kind], TOK_NUMBER
    je      .again
.ok:
    xor     eax, eax
.out:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    ret
.none:
    xor     eax, eax
    ret

; ---- conditional level bookkeeping ------
;
; PREP_depth counts open conditionals and PREP_skip_depth counts how many of
; them are currently suppressing output. cond_taken[level] records whether a
; branch at that level has already fired, which is what makes %elif chains
; behave: once one branch is taken, every later branch stays skipped.
;
; prep_cond_enter : rdi = PrepState, sil = 1 when the condition holds
;
prep_cond_enter:
    movzx   eax, word [rdi + PREP_depth]
    cmp     eax, PREP_COND_MAX
    jae     .overflow

    cmp     word [rdi + PREP_skip_depth], 0
    jne     .outer_skipping

    test    sil, sil
    jz      .not_taken
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.not_taken:
    mov     byte [rdi + PREP_cond_taken + rax], 0
    inc     word [rdi + PREP_skip_depth]
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.outer_skipping:
    ; an enclosing level is suppressing: mark taken so %else cannot revive it
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     word [rdi + PREP_skip_depth]
    inc     word [rdi + PREP_depth]
    xor     rax, rax
    ret

.overflow:
    mov     rax, EXIT_COND_DEPTH
    ret

;
; prep_cond_branch : rdi = PrepState, sil = 1 when this branch's condition
;                    holds (%else passes 1). Handles %else / %elif / %elifidni.
;
prep_cond_branch:
    movzx   eax, word [rdi + PREP_depth]
    test    al, al
    jz      .no_if
    dec     eax

    movzx   ecx, word [rdi + PREP_skip_depth]
    cmp     cl, 1
    jg      .unchanged             ; an outer level is skipping

    cmp     byte [rdi + PREP_cond_taken + rax], 0
    jne     .force_skip

    test    sil, sil
    jz      .stay_skipping
    mov     byte [rdi + PREP_cond_taken + rax], 1
    mov     word [rdi + PREP_skip_depth], 0
    xor     rax, rax
    ret

.stay_skipping:
    mov     word [rdi + PREP_skip_depth], 1
    xor     rax, rax
    ret

.force_skip:
    mov     word [rdi + PREP_skip_depth], 1
.unchanged:
    xor     rax, rax
    ret

.no_if:
    mov     rax, EXIT_ERROR
    ret

; ---- prep_str_cmp_ci --------------------
;
; Case-insensitive comparison of two NUL-terminated strings.
; Input  : rdi, rsi = strings
; Output : rax = 0 when equal
;
prep_str_cmp_ci:
.loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]

    cmp     al, 'A'
    jb      .a_ready
    cmp     al, 'Z'
    ja      .a_ready
    add     al, 32
.a_ready:
    cmp     cl, 'A'
    jb      .b_ready
    cmp     cl, 'Z'
    ja      .b_ready
    add     cl, 32
.b_ready:
    cmp     al, cl
    jne     .differ
    test    al, al
    jz      .equal
    inc     rdi
    inc     rsi
    jmp     .loop

.equal:
    xor     rax, rax
    ret
.differ:
    mov     rax, 1
    ret

; ---- prep_read_idn_pair -----------------
;
; Reads "A, B" from the directive line and reports whether the two token
; sequences are the same, as NASM's %ifidn compares them: token by token,
; each side up to the comma / the end of the line. idn_case selects the
; comparison (1: exact, 0: ignoring case). Macros in the operands are
; expanded first, so "%ifidn __SECT__, [section .text]" works.
;
; Input  : rdi = PrepState
; Output : rax = EXIT_OK, rdx = 1 when they match
;
prep_read_idn_pair:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi

    ; The operands belong to this directive and must be read even inside a
    ; skipped block; with skipping active the token reader would swallow the
    ; rest of the file instead of handing them back.
    movzx   r14d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0

    mov     rdi, rbx
    call    prep_drop_stale_newline

    lea     rdi, [rel idn_left]
    mov     esi, 1                 ; up to the comma
    call    prep_idn_collect
    test    rax, rax
    jnz     .fail
    mov     r12, rdx               ; the left text
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .have_right
    mov     rdi, rbx
    call    preprocessor_next_token
.have_right:
    lea     rdi, [rel idn_right]
    xor     esi, esi               ; up to the end of the line
    call    prep_idn_collect
    test    rax, rax
    jnz     .fail
    mov     r13, rdx               ; the right text

    mov     rdi, r12
    mov     rsi, r13
    cmp     byte [rel idn_case], 0
    jne     .case_sensitive
    call    prep_str_cmp_ci
    jmp     .compared
.case_sensitive:
    call    str_cmp                    ; %ifidn / %ifnidn
.compared:
    test    rax, rax
    jnz     .not_equal

    xor     rax, rax
    mov     rdx, 1
    jmp     .done

.not_equal:
    xor     rax, rax
    xor     rdx, rdx
    jmp     .done

.fail:
    xor     rdx, rdx

.done:
    mov     [rbx + PREP_skip_depth], r14w   ; restore the skip state
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;
; prep_idn_collect
; The text of the tokens up to the end of the line (or a comma), one space
; between them, into a buffer that grows: its descriptor holds the pointer
; and the capacity, and a full buffer is replaced by one twice the size
; (kept for the next use).
; Input  : rbx = PrepState, rdi = the buffer's descriptor (idn_left ...),
;          esi = bit 0: stop at a comma, bit 1: blanks only where the source
;          has them (%defstr)
; Output : rax = EXIT_OK or error, rdx = the text
;
prep_idn_collect:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13d, esi
    xor     r14d, r14d                 ; bytes written
    mov     rax, [r12]
    mov     byte [rax], 0
.token:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .end
    cmp     eax, TOK_EOF
    je      .end
    test    r13d, 1
    jz      .take
    cmp     eax, TOK_COMMA
    je      .end
.take:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    test    r14d, r14d
    jz      .no_sep
    test    r13d, 2
    jz      .sep
    ; the source's spacing: a blank only where the source had one
    mov     eax, [r15 + TOKEN_line]
    cmp     eax, [rel idn_prev_line]
    jne     .sep
    movzx   eax, word [r15 + TOKEN_col]
    cmp     eax, [rel idn_prev_end]
    jbe     .no_sep
.sep:
    mov     eax, ' '
    call    .put
    test    rax, rax
    jnz     .ret
.no_sep:
    mov     eax, [r15 + TOKEN_line]
    mov     [rel idn_prev_line], eax
    movzx   eax, word [r15 + TOKEN_col]
    movzx   ecx, word [r15 + TOKEN_len]
    add     eax, ecx
    mov     [rel idn_prev_end], eax
    mov     rdx, r15
    call    prep_idn_text
    mov     r15, rax
.copy:
    movzx   eax, byte [r15]
    test    eax, eax
    jz      .token
    call    .put
    test    rax, rax
    jnz     .ret
    inc     r15
    jmp     .copy
.end:
    mov     rdx, [r12]
    mov     byte [rdx + r14], 0
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; .put: the byte al at the end of the text (the buffer twice the size when
; it is full). rax = OK or an error; clobbers rcx, rdx, rdi, rsi, r8-r11.
.put:
    lea     rcx, [r14 + 2]                 ; the byte and the NUL
    cmp     rcx, [r12 + 8]
    jbe     .put_room
    push    rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [r12 + 8]
    shl     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .put_fail
    mov     rdi, rdx
    mov     rsi, [r12]
    mov     ecx, r14d
    rep movsb
    mov     [r12], rdx
    shl     qword [r12 + 8], 1
    pop     rax
.put_room:
    mov     rcx, [r12]
    mov     [rcx + r14], al
    inc     r14d
    xor     eax, eax
    ret
.put_fail:
    add     rsp, 8                         ; (the byte)
    ret

;
; prep_idn_text : rax = a token's text (rdx = token, rbx = PrepState)
;
prep_idn_text:
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_CHAR
    je      prep_token_text
    lea     rcx, [rel idn_punct]
.punct:
    cmp     byte [rcx], 0
    je      .word
    cmp     al, [rcx]
    je      .punct_hit
    add     rcx, 4
    jmp     .punct
.punct_hit:
    lea     rax, [rcx + 1]
    ret
.word:
    mov     rax, [rdx + TOKEN_value]
    test    rax, rax
    jnz     .ret
    lea     rax, [rel idn_unknown]
.ret:
    ret

; ---- prep_handle_ifidni -----------------
prep_handle_ifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_enter

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elifidni ---------------
prep_handle_elifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_branch

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elif -------------------
prep_handle_elif:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    ; %elifn: taken here, for the evaluation below if there is one
    mov     al, [rel cond_negate]
    mov     [rel elif_negate], al
    mov     byte [rel cond_negate], 0

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; Only evaluate when this level could still take a branch
    movzx   eax, word [rbx + PREP_depth]
    test    al, al
    jz      .no_if
    dec     eax
    movzx   ecx, word [rbx + PREP_skip_depth]
    cmp     cl, 1
    jg      .no_eval
    cmp     byte [rbx + PREP_cond_taken + rax], 0
    jne     .no_eval

    ; The condition is this directive's own operand: read it with skipping
    ; suspended, or the token reader discards it along with the skipped block.
    movzx   r12d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0

    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     word [rbx + PREP_skip_depth], r12w
    test    rax, rax
    jnz     .done
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    xor     sil, [rel elif_negate]
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done

.no_eval:
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done

.no_if:
    mov     rax, EXIT_ERROR

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_error ------------------
;
; "%error message" — reported only when the line is actually reached.
;
prep_handle_error:
    prologue
    push    rbx
    mov     rbx, rdi

    ; While skipping there is nothing to report and nothing to drain: the
    ; skip loop consumes the rest of the line itself. Peeking here would run
    ; the preprocessor over the following %endif and swallow it.
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done

    ; "file:line: error: message"; the assembly goes on to report any
    ; further errors, but fails at the end
    extern  print_str
    mov     rdi, rbx
    mov     esi, 2
    call    prep_handle_message

.done:
    xor     rax, rax
    pop     rbx
    epilogue

; ---- prep_raw_next ----------------------
;
; Reads the next token without expanding or interpreting it: from the active
; macro/%rep body when one is running, otherwise from the file. %rep captures
; its body with this, so a %rep written inside a macro copies the macro's
; tokens instead of running off into the source file.
;
; Input  : rdi = PrepState, rsi = destination Token
; Output : rax = EXIT_OK or error
;
prep_raw_next:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    mov     rax, [rbx + PREP_ctx]
    mov     r13, [rax + ASMCTX_mac_exp]
    test    r13, r13
    jz      .from_lexer

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .from_lexer                ; body exhausted: continue in the file

    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax
    mov     rdi, r12
    mov     rsi, r10
    copy_token
    inc     qword [r13 + MACROEXP_body]
    xor     rax, rax
    jmp     .done

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_raw_peek ----------------------
;
; prep_raw_peek
; Like prep_raw_next, without consuming the token: the next one of the
; current macro expansion, else of the file.
; Input    : rdi = PrepState, rsi = token to fill
; Output   : rax = EXIT_OK or error
;
prep_raw_peek:
    mov     rax, [rdi + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .from_lexer
    mov     rcx, [rax + MACROEXP_body]
    mov     r9, [rax + MACROEXP_macro]
    cmp     ecx, [r9 + MACRO_ntokens]
    jge     .from_lexer
    imul    rcx, TOKEN_SIZE
    add     rcx, [r9 + MACRO_tokens]
    push    rdi
    push    rsi
    mov     rdi, rsi
    mov     rsi, rcx
    copy_token
    pop     rsi
    pop     rdi
    xor     eax, eax
    ret
.from_lexer:
    mov     rdi, [rdi + PREP_lexer]
    jmp     lexer_peek

; ---- prep_handle_unmacro ----------------
;
; prep_handle_unmacro
; "%unmacro name nparams" (and the case-insensitive "%unimacro") removes a
; previously defined multi-line macro. The symbol table has no delete, so the
; entry is retired in place by clearing its kind -- the macro-call lookup in
; prep_internal_next only fires on SYM_MACRO, so an entry of any other kind is
; inert. Removing a name that is not a macro is not an error, matching NASM.
;
; The parameter count is required, and removes the overload with exactly
; that count ("%unmacro s 1" leaves "s 0" and "s 1+"), as in NASM.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_unmacro:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE        ; scratch token
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; 1. Macro name, taken straight from the lexer. Reading it through the
    ;    preprocessor would recognise the name as a macro *call* and expand
    ;    it, which is exactly what %macro avoids for the same reason.
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .done
    cmp     byte [rsp + TOKEN_kind], TOK_IDENT
    je      .named
    lea     rdi, [rel s_unmacro]           ; "`%unmacro' expects a macro name"
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_NAME
    jmp     .done
.named:
    mov     r12, [rsp + TOKEN_value]

    ; 2. The parameter count of the overload to remove
    lea     rdi, [rel s_unmacro]
    call    prep_parse_count
    test    rax, rax
    jnz     .done
    mov     r13, rcx
    mov     r14, rdx

    ; 3. Unlink that overload (a %define of the name stays)
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    extern  symbol_find
    call    symbol_find
    test    rax, rax
    jnz     .drain
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .drain
    mov     r8, rdx                        ; the SYMBOL
    lea     r9, [rdx + SYMBOL_value]       ; where the current one is linked
.find:
    mov     r10, [r9]
    test    r10, r10
    jz      .drain                         ; no overload with that count
    test    byte [r10 + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .drain
    movzx   eax, word [r10 + MACRO_min_params]
    cmp     rax, r13
    jne     .next
    movzx   eax, word [r10 + MACRO_max_params]
    cmp     rax, r14
    jne     .next
    mov     al, [r10 + MACRO_flags]
    and     al, MACRO_FLAG_GREEDY
    cmp     al, [rel mdef_greedy]
    jne     .next
    mov     rax, [r10 + MACRO_next]
    mov     [r9], rax
    cmp     qword [r8 + SYMBOL_value], 0
    jne     .drain
    mov     byte [r8 + SYMBOL_kind], SYM_UNKNOWN   ; the last overload
    jmp     .drain
.next:
    lea     r9, [r10 + MACRO_next]
    jmp     .find

.drain:
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_drain_line --------------------
;
; Consumes what is left of the current directive's line, including the
; terminating newline, so the next directive starts on a clean stream.
; Directives that evaluate an expression stop *on* the newline and leave it
; in the peek slot instead; those use prep_drop_stale_newline.
;
; Input : rdi = PrepState
;
prep_drain_line:
    prologue
    push    rbx
    mov     rbx, rdi

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .eat_newline
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .loop

.eat_newline:
    mov     rdi, rbx
    call    preprocessor_next_token

.done:
    xor     rax, rax
    pop     rbx
    epilogue

; ---- prep_define_const ------------------
;
; Defines or re-defines a numeric constant, the way %assign does.
; Input : rdi = PrepState, rsi = name string, rdx = value
;
prep_define_const:
    prologue
    push    rbx
    push    r12
    push    r13
    sub     rsp, SYMBOL_SIZE
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .create
    mov     [rdx + SYMBOL_value], r13
    xor     rax, rax
    jmp     .done

.create:
    mov     rdi, rsp
    mov     rcx, (SYMBOL_SIZE / 8)
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rdi + SYMBOL_pflags], SYMF_ASSIGN
    mov     [rdi + SYMBOL_name], r12
    mov     [rdi + SYMBOL_value], r13

    mov     rsi, rdi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_add

.done:
    add     rsp, SYMBOL_SIZE
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_strlen -----------------
;
; "%strlen NAME "text"" defines NAME as the length of the string.
;
prep_handle_strlen:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     eax, EXIT_DEFINE           ; "%strlen" with no name (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     eax, EXIT_DEFINE           ; "%strlen x": no string (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    call    prep_token_text            ; 'hello' is a packed character constant
    mov     rdi, rax                   ; string contents
    test    rdi, rdi
    jz      .empty
    call    str_len
    jmp     .define
.empty:
    xor     rax, rax

.define:
    mov     rdx, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_define_const
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_substr -----------------
;
; "%substr NAME "text" index" defines NAME as the character at the 1-based
; index. NASM yields a one-character string there; utasm stores the character
; code directly, which is how compile_time_hash consumes it.
;
prep_handle_substr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; %substr NAME string, start [, length]  (the commas may be left out)
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    mov     eax, EXIT_DEFINE           ; "%substr" with no name (NASM's error)
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ret
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    call    prep_token_text
    mov     r13, rax                   ; string contents
    test    r13, r13
    jnz     .have_text
    lea     r13, [rel dyn_no_file]     ; ""
.have_text:
    call    .skip_comma
    mov     rdi, rbx
    call    parser_evaluate_expression ; 1-based start
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    mov     r15, 1                     ; length: one character
    call    .skip_comma_peek
    test    eax, eax
    jz      .have_len
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
.have_len:
    mov     rdi, r13
    call    str_len                    ; rax = L
    ; a start below 1 is 1 (as NASM 2.16 does)
    test    r14, r14
    jg      .start_ok
    mov     r14d, 1
.start_ok:
    dec     r14                        ; 0-based
    ; a negative length ends that far from the end (-1: at the end)
    test    r15, r15
    jns     .len_ok
    mov     rcx, rax
    sub     rcx, r14
    lea     r15, [rcx + r15 + 1]
.len_ok:
    test    r14, r14
    jns     .clip
    add     r15, r14
    xor     r14d, r14d
.clip:
    cmp     r14, rax
    jb      .clip_len
    xor     r15d, r15d
    jmp     .build
.clip_len:
    mov     rcx, rax
    sub     rcx, r14
    cmp     r15, rcx
    jle     .nonneg
    mov     r15, rcx
.nonneg:
    test    r15, r15
    jns     .build
    xor     r15d, r15d
.build:
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r15 + 1]
    call    arena_alloc                ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    lea     rsi, [r13 + r14]
    mov     rcx, r15
    push    rdx
    rep movsb
    pop     rdx
    mov     rsi, rdx
    mov     rcx, r15
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; eax = 1 when an operand follows (after an optional comma)
.skip_comma_peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .no_more
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .no_more
    cmp     eax, TOK_EOF
    je      .no_more
    cmp     eax, TOK_COMMA
    jne     .more
    mov     rdi, rbx
    call    preprocessor_next_token
.more:
    mov     eax, 1
    ret
.no_more:
    xor     eax, eax
    ret
.skip_comma:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .sc_ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .sc_ret
    mov     rdi, rbx
    call    preprocessor_next_token
.sc_ret:
    ret

; ---- prep_token_text ------------------
;
; prep_token_text
; The text of a quoted token as a NUL-terminated string. A "..." string (or a
; '...' one longer than eight characters) already is one; a short '...' is a
; character constant whose characters are packed into TOKEN_value, so they
; are unpacked into an arena buffer.
; Input    : rdx = token, rbx = PrepState
; Output   : rax = the text (0 if none)
;
prep_token_text:
    cmp     byte [rdx + TOKEN_kind], TOK_CHAR
    je      .char
    mov     rax, [rdx + TOKEN_value]
    ret
.char:
    push    r12
    push    r13
    mov     r12, [rdx + TOKEN_value]
    movzx   r13d, word [rdx + TOKEN_len]
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 16
    call    arena_alloc                ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .none
    xor     ecx, ecx
.byte:
    cmp     ecx, r13d
    jae     .done
    cmp     ecx, 8
    jae     .done
    mov     [rdx + rcx], r12b
    shr     r12, 8
    inc     ecx
    jmp     .byte
.done:
    mov     rax, rdx
    pop     r13
    pop     r12
    ret
.none:
    xor     eax, eax
    pop     r13
    pop     r12
    ret

; ---- prep_drop_stale_newline ------------
;
; prep_drop_stale_newline
; Directives that evaluate an expression stop on the terminating NEWLINE and
; leave it in the peek slot. It belongs to the finished line, so the next
; directive that reads operands must not see it.
;
; Input    : rdi = pointer to PrepState
;
prep_drop_stale_newline:
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     .done
    cmp     byte [rdi + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .done
    mov     byte [rdi + PREP_has_peek], FALSE
.done:
    ret

; ---- prep_handle_push -------------------
;
; prep_handle_push
; "%push name" opens a context. Each context gets a unique id, which is what
; makes %$local names unique per IF/ENDIF pair.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_push:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     eax, [rbx + PREP_ctx_depth]
    cmp     eax, PREP_CTX_MAX
    jge     .overflow

    ; the context name is optional
    xor     r12, r12
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .store
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .store
    mov     r12, [rdx + TOKEN_value]

.store:
    mov     eax, [rbx + PREP_ctx_depth]
    mov     ecx, [rbx + PREP_ctx_next_id]
    inc     ecx
    mov     [rbx + PREP_ctx_next_id], ecx
    mov     [rbx + PREP_ctx_ids + rax * 4], ecx
    lea     rdx, [rbx + PREP_ctx_names]
    mov     [rdx + rax * 8], r12
    inc     eax
    mov     [rbx + PREP_ctx_depth], eax

    xor     rax, rax
    jmp     .done

.overflow:
    mov     rax, EXIT_CTX_DEPTH

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_pop --------------------
;
; prep_handle_pop
; "%pop [name]" closes the innermost context.
;
prep_handle_pop:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; an optional context name may follow; it is not verified
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .drop
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .drop
    mov     rdi, rbx
    call    preprocessor_next_token

.drop:
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .underflow
    dec     eax
    mov     [rbx + PREP_ctx_depth], eax
    xor     rax, rax
    jmp     .done

.underflow:
    mov     rax, EXIT_MACRO_DEF

.done:
    pop     rbx
    epilogue

; ---- prep_resolve_interp ----------------
;
; prep_resolve_interp
; Rewrites a token's text, replacing every "%[NAME]" with the decimal value
; of NAME. A name that is not defined contributes nothing, matching how the
; tables in include/arch/*.inc are built.
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (text is replaced in place)
; Output   : rax = EXIT_OK or error code
;
prep_resolve_interp:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEX_INTERP_BUF
    call    arena_alloc
    test    rax, rax
    jnz     .done
    mov     r14, rdx               ; r14 = output buffer (it grows: .ensure)
    mov     qword [rel interp_cap], LEX_INTERP_BUF
    xor     r15, r15               ; r15 = output length
    mov     r13, [r12 + TOKEN_value] ; r13 = source cursor

.scan:
    call    .ensure                ; room for what one step writes
    jc      .finish
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish

    cmp     al, '%'
    jne     .copy_char
    cmp     byte [r13 + 1], '$'
    je      .ctx_local
    ; a macro's parameter or local pasted into a name: isr_%1, %%x_%1
    cmp     byte [r13 + 1], '%'
    je      .mac_local
    cmp     byte [r13 + 1], '{'
    je      .param_brace
    movzx   eax, byte [r13 + 1]
    sub     eax, '0'
    cmp     eax, 9
    jbe     .param
    cmp     byte [r13 + 1], '['
    jne     .copy_char

    ; "%[" : read the name up to ']'
    add     r13, 2
    mov     r9, r13
.name_loop:
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish
    cmp     al, ']'
    je      .name_done
    inc     r13
    jmp     .name_loop

.name_done:
    mov     r10, r13
    sub     r10, r9                ; name length
    inc     r13                    ; step over ']'

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r9
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .done
    mov     r9, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r9
    call    symbol_find
    test    rax, rax
    jnz     .scan                  ; undefined: contributes nothing

    ; a %define gives its text, an %assign / equ its value
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .interp_number
    mov     rax, [rdx + SYMBOL_value]
    push    r13
    push    r12
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
.interp_tok:
    test    r13d, r13d
    jz      .interp_tok_done
    mov     rdx, r12
    call    prep_idn_text
.interp_chr:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .interp_next_tok
    call    .ensure
    jc      .interp_next_tok
    mov     [r14 + r15], cl
    inc     r15
    inc     rax
    jmp     .interp_chr
.interp_next_tok:
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .interp_tok
.interp_tok_done:
    pop     r12
    pop     r13
    jmp     .scan
.interp_number:
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan

.ctx_local:
    ; "%$name" is local to the innermost %push context: rewrite it as the
    ; ordinary symbol "__ctxN$name", which makes each IF/ENDIF pair unique.
    ; "%$$name" is the context around it, one more '$' one more level out.
    add     r13, 2
    mov     eax, [rbx + PREP_ctx_depth]
.ctx_outer:
    cmp     byte [r13], '$'
    jne     .ctx_level
    inc     r13
    dec     eax
    jmp     .ctx_outer
.ctx_level:
    test    eax, eax
    jle     .ctx_id_zero
    dec     eax
    mov     eax, [rbx + PREP_ctx_ids + rax * 4]
    jmp     .ctx_id_ready
.ctx_id_zero:
    xor     eax, eax
.ctx_id_ready:
    mov     byte [r14 + r15], '_'
    mov     byte [r14 + r15 + 1], '_'
    mov     byte [r14 + r15 + 2], 'c'
    mov     byte [r14 + r15 + 3], 't'
    mov     byte [r14 + r15 + 4], 'x'
    add     r15, 5
    mov     rsi, rax
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    mov     byte [r14 + r15], '$'
    inc     r15
    jmp     .scan

.copy_char:
    mov     [r14 + r15], al
    inc     r15
    inc     r13
    jmp     .scan

.param_brace:
    ; "%{N}": as %N
    add     r13, 2
    xor     eax, eax
.brace_digit:
    movzx   ecx, byte [r13]
    test    ecx, ecx
    jz      .param_n
    inc     r13
    cmp     ecx, '}'
    je      .param_n
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .brace_digit
    imul    eax, eax, 10
    add     eax, ecx
    jmp     .brace_digit
.param:
    ; "%N": the text of argument N of the macro being expanded (%0: how
    ; many there are)
    inc     r13
    xor     eax, eax
.param_digit:
    movzx   ecx, byte [r13]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .param_n
    imul    eax, eax, 10
    add     eax, ecx
    inc     r13
    jmp     .param_digit
.param_n:
    ; the expansion with the parameters (a %rep body has none)
    mov     rdx, [rbx + PREP_ctx]
    mov     rdx, [rdx + ASMCTX_mac_exp]
.param_owner:
    test    rdx, rdx
    jz      .scan
    cmp     word [rdx + MACROEXP_nparams], 0
    jne     .param_found
    mov     rdx, [rdx + MACROEXP_parent]
    jmp     .param_owner
.param_found:
    movzx   ecx, word [rdx + MACROEXP_nparams]
    test    eax, eax
    jnz     .param_arg
    mov     rsi, rcx                       ; %0
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan
.param_arg:
    cmp     eax, ecx
    ja      .scan                          ; not given: nothing
    dec     eax
    mov     rcx, [rdx + MACROEXP_arglens]
    mov     ecx, [rcx + rax * 4]
    mov     rdx, [rdx + MACROEXP_params]
    mov     rdx, [rdx + rax * 8]           ; its first token
    push    r13
    push    r12
    mov     r12, rdx
    mov     r13d, ecx
    ; their texts; a name that is a %define / %assign gives its own, as
    ; NASM expands the arguments of a macro call
.arg_tok:
    test    r13d, r13d
    jz      .arg_done
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .arg_raw
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .arg_raw
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    je      .arg_assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .arg_raw
    mov     rax, [rdx + SYMBOL_value]
    cmp     word [rax + MACRO_max_params], 0
    jne     .arg_raw                       ; a function-like one: as written
    push    r12
    push    r13
    mov     r12, [rax + MACRO_tokens]
    mov     r13d, [rax + MACRO_ntokens]
.def_tok:
    test    r13d, r13d
    jz      .def_done
    mov     rdx, r12
    call    prep_idn_text
    call    .append
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .def_tok
.def_done:
    pop     r13
    pop     r12
    jmp     .arg_next
.arg_assign:
    ; an %assign: its value in decimal
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jz      .arg_raw
    call    .ensure
    jc      .arg_next
    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .arg_next
.arg_raw:
    mov     rdx, r12
    call    prep_idn_text
    call    .append
.arg_next:
    add     r12, TOKEN_SIZE
    dec     r13d
    jmp     .arg_tok
.arg_done:
    pop     r12
    pop     r13
    jmp     .scan

; .append: the text at rax onto the output (r14 + r15)
.append:
    movzx   ecx, byte [rax]
    test    ecx, ecx
    jz      .append_end
    call    .ensure
    jc      .append_end
    mov     [r14 + r15], cl
    inc     r15
    inc     rax
    jmp     .append
.append_end:
    ret

; .ensure: room for 40 more bytes at r14 + r15 (a number, "__ctxN$" or
; "..@N", and the NUL), the buffer twice the size when there is not. CF
; set when there is no memory. Preserves rax, rcx; clobbers rdx, rsi, rdi,
; r8-r11.
.ensure:
    lea     rdx, [r15 + 40]
    cmp     rdx, [rel interp_cap]
    jbe     .ens_ok
    push    rax
    push    rcx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel interp_cap]
    shl     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .ens_fail
    mov     rdi, rdx
    mov     rsi, r14
    mov     rcx, r15
    rep movsb
    mov     r14, rdx
    shl     qword [rel interp_cap], 1
    pop     rcx
    pop     rax
.ens_ok:
    clc
    ret
.ens_fail:
    pop     rcx
    pop     rax
    stc
    ret

.mac_local:
    ; "%%name": "..@" and the expansion's number, then the name
    add     r13, 2
    mov     rdx, [rbx + PREP_ctx]
    mov     rdx, [rdx + ASMCTX_mac_exp]
    test    rdx, rdx
    jz      .scan
    mov     byte [r14 + r15], '.'
    mov     byte [r14 + r15 + 1], '.'
    mov     byte [r14 + r15 + 2], '@'
    add     r15, 3
    mov     esi, [rdx + MACROEXP_exp_id]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    mov     byte [r14 + r15], '.'          ; ..@N.name, as NASM
    inc     r15
    jmp     .scan

.finish:
    mov     byte [r14 + r15], 0
    mov     [r12 + TOKEN_value], r14
    mov     word [r12 + TOKEN_len], r15w
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_INTERP
    ; "0x%1", "%1h": a number once pasted
    movzx   eax, byte [r14]
    sub     eax, '0'
    cmp     eax, 9
    ja      .finish_kind
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .finish_kind
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER
.finish_kind:
    xor     rax, rax

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

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
    mov     rdi, rbx
    extern  parser_evaluate_expression
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .error
    mov     r14, rdx               ; r14 = value

    ; 3. Re-assign in place when the name already exists (it may have been
    ;    a %define: it is a number now)
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
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
    call    symbol_add
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
    call    symbol_find
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
    extern  elf32_enabled
    cmp     byte [rel elf32_enabled], 0
    je      .format_class
    lea     rax, [rel dyn_fmt_elf32]
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
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .text
    cmp     eax, TOK_STRING
    je      .text
    cmp     eax, TOK_CHAR
    je      .text
    cmp     eax, TOK_NUMBER
    jne     .word
    mov     rsi, [rdx + TOKEN_value]       ; a number: as written
    push    rsi
    call    .space
    pop     rsi
    call    .out
    inc     r12d
    jmp     .word
.text:
    call    prep_token_text
    test    rax, rax
    jz      .word
    push    rax
    test    r12d, r12d
    jz      .no_space
    lea     rsi, [rel msg_space]
    call    .out
.no_space:
    pop     rsi
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

; ---- %ifnum / %ifstr / %ifid / %ifempty / %ifmacro / %ifdef ----
;
; prep_handle_iftest
; What the operand is: a number, a string, an identifier, nothing, the
; name of a multi-line macro, or the name of a single-line one (%ifdef:
; %define, %assign and the like, and the dynamic __LINE__, __FILE__, ...;
; a label is not). The rest of the line belongs to the directive.
; Input    : rdi = PrepState, esi = IFT_*, edx = bit 0 negate, bit 1 %elif
;
prep_handle_iftest:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    movzx   r14d, word [rbx + PREP_skip_depth]
    mov     word [rbx + PREP_skip_depth], 0    ; read it even when skipping
    mov     rdi, rbx
    call    prep_drop_stale_newline
    cmp     r12d, IFT_MACRO
    jb      .peek
    mov     byte [rel prep_noexpand], 1        ; a name, not its expansion
.peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .restore
    xor     r15d, r15d
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     r12d, IFT_TOKEN
    jne     .t_empty
    ; one token, then the end of the line
    cmp     eax, TOK_NEWLINE
    je      .decided
    cmp     eax, TOK_EOF
    je      .decided
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .restore
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .true
    cmp     eax, TOK_EOF
    je      .true
    jmp     .decided
.t_empty:
    cmp     r12d, IFT_EMPTY
    jne     .t_num
    cmp     eax, TOK_NEWLINE
    je      .true
    cmp     eax, TOK_EOF
    je      .true
    jmp     .decided
.t_num:
    cmp     r12d, IFT_NUM
    jne     .t_str
    cmp     eax, TOK_NUMBER
    je      .true
    jmp     .decided
.t_str:
    cmp     r12d, IFT_STR
    jne     .t_id
    cmp     eax, TOK_STRING
    je      .true
    cmp     eax, TOK_CHAR
    je      .true
    jmp     .decided
.t_id:
    cmp     r12d, IFT_ID
    jne     .t_macro
    cmp     eax, TOK_IDENT
    je      .true
    jmp     .decided
.t_macro:
    cmp     r12d, IFT_DEF
    je      .t_def
    cmp     r12d, IFT_CTX
    je      .t_ctx
    cmp     r12d, IFT_ENV
    je      .t_env
    cmp     eax, TOK_IDENT
    jne     .decided
    mov     rsi, [rdx + TOKEN_value]
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .decided
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .decided
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .decided
    ; "%ifmacro m 2", "m 1-3", "m 1-*": one of that name taking such a
    ; count (overloads by MACRO_next); with no count, any
    push    rax                            ; [rsp + 16] the macro
    push    0                              ; [rsp + 8] the count from
    push    MACRO_VARIADIC                 ; [rsp] ... to
    mov     rdi, rbx
    call    preprocessor_next_token        ; the name
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .tm_check
    mov     rdi, [rdx + TOKEN_value]       ; (its text)
    call    str_to_int
    test    rax, rax
    jnz     .tm_check
    mov     [rsp + 8], rdx
    mov     [rsp], rdx
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    jne     .tm_check
    mov     rdi, rbx
    call    preprocessor_next_token        ; the '-'
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tm_check
    cmp     byte [rdx + TOKEN_kind], TOK_STAR
    je      .tm_any
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .tm_check
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    test    rax, rax
    jnz     .tm_check
    mov     [rsp], rdx
    jmp     .tm_take
.tm_any:
    mov     qword [rsp], MACRO_VARIADIC
.tm_take:
    mov     rdi, rbx
    call    preprocessor_next_token
.tm_check:
    mov     rax, [rsp + 16]
.tm_macro:
    test    rax, rax
    jz      .tm_none
    movzx   ecx, word [rax + MACRO_min_params]
    cmp     rcx, [rsp]
    ja      .tm_next                       ; takes more than asked
    movzx   ecx, word [rax + MACRO_max_params]
    cmp     rcx, [rsp + 8]
    jb      .tm_next                       ; takes fewer
    add     rsp, 24
    jmp     .true
.tm_next:
    mov     rax, [rax + MACRO_next]
    jmp     .tm_macro
.tm_none:
    add     rsp, 24
    jmp     .decided
.t_def:
    cmp     eax, TOK_IDENT
    jne     .decided
    push    rdx
    mov     rsi, [rdx + TOKEN_value]
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .t_dynamic
    pop     rax
    test    byte [rdx + SYMBOL_pflags], SYMF_ASSIGN
    jnz     .true                          ; %assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .decided
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .true
    jmp     .decided
.t_env:
    ; "%ifenv NAME" / "%ifenv 'NAME'": set in the environment
    cmp     eax, TOK_IDENT
    je      .t_env_name
    cmp     eax, TOK_STRING
    jne     .decided
.t_env_name:
    mov     rdi, [rdx + TOKEN_value]
    call    prep_getenv
    test    rax, rax
    jnz     .true
    jmp     .decided
.t_ctx:
    ; the name of the innermost %push context
    cmp     eax, TOK_IDENT
    jne     .decided
    mov     ecx, [rbx + PREP_ctx_depth]
    test    ecx, ecx
    jz      .decided
    dec     ecx
    lea     rax, [rbx + PREP_ctx_names]
    mov     rsi, [rax + rcx * 8]
    test    rsi, rsi
    jz      .decided
    mov     rdi, [rdx + TOKEN_value]
    call    str_cmp
    test    rax, rax
    jz      .true
    jmp     .decided
.t_dynamic:
    ; __LINE__, __FILE__, __BITS__ ...: made up as they are used
    lea     r8, [rel dyn_table]
.t_dyn_name:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .t_dyn_none
    mov     rdi, [rsp]
    mov     rdi, [rdi + TOKEN_value]
    push    r8
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .t_dyn_hit
    add     r8, 16
    jmp     .t_dyn_name
.t_dyn_hit:
    pop     rdx
    jmp     .true
.t_dyn_none:
    pop     rdx
    jmp     .decided
.true:
    mov     r15d, 1
.decided:
.drain:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .restore
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .drained
    cmp     eax, TOK_EOF
    je      .drained
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .drain
.drained:
    mov     [rbx + PREP_skip_depth], r14w
    test    r13d, 1
    jz      .enter
    xor     r15d, 1
.enter:
    mov     esi, r15d
    mov     rdi, rbx
    test    r13d, 2
    jnz     .elif
    call    prep_cond_enter
    jmp     .ret
.elif:
    call    prep_cond_branch
    jmp     .ret
.restore:
    mov     [rbx + PREP_skip_depth], r14w
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; prep_icase_key
; The key a case-insensitive name is stored under, in the arena; from now
; on lookups also try it (idefine_count).
; Input    : rbx = PrepState, rsi = name
; Output   : rax = EXIT_OK or error, rdx = the key
;
prep_icase_key:
    call    prep_icase_buf
    test    rax, rax
    jnz     .bad
    lea     rdi, [rel icase_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rdi, rdx
    lea     rsi, [rel icase_buf]
    call    str_concat
    pop     rdx
    inc     dword [rel idefine_count]
    xor     eax, eax
.ret:
    ret
.bad:
    mov     rax, EXIT_DEFINE
    ret

; ---- %defstr / %idefstr ------------------
;
; "%defstr NAME text" defines NAME as the string of the rest of the line
; (spaced as in the source).
; Input    : rdi = PrepState, esi = 1 for %idefstr
;
prep_handle_defstr:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     r13d, esi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    test    r13d, r13d
    jz      .have_name
    mov     rsi, r12
    call    prep_icase_key
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
.have_name:
    lea     rdi, [rel idn_left]
    mov     esi, 2                         ; the source's spacing
    call    prep_idn_collect
    test    rax, rax
    jnz     .ret
    push    rdx                            ; the text
    mov     rdi, rdx
    call    str_len
    mov     r13, rax
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, rdx
    call    str_concat
    mov     rsi, r15
    mov     rcx, r13
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    jmp     .ret
.bad:
    mov     rax, EXIT_DEFINE
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- %iassign ---------------------------
;
; "%iassign NAME expr": %assign whose name matches in any case (stored as
; a case-insensitive single-line macro holding the value).
;
prep_handle_iassign:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    prep_icase_key
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, rdx
    mov     rsi, r13
    call    str_int_to_str
    lea     rdi, [rel def_scratch]
    mov     ecx, TOKEN_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rel def_scratch + TOKEN_tag], TAG_TOKEN
    mov     byte [rel def_scratch + TOKEN_kind], TOK_NUMBER
    mov     [rel def_scratch + TOKEN_value], r15
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    jmp     .ret
.bad:
    mov     rax, EXIT_DEFINE
.ret:
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- %repl ------------------------------
;
; "%repl name" renames the innermost context.
;
prep_handle_repl:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    prep_drop_stale_newline
    xor     r12d, r12d
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, [rdx + TOKEN_value]
.store:
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .bad
    dec     eax
    lea     rdx, [rbx + PREP_ctx_names]
    mov     [rdx + rax * 8], r12
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret
.bad:
    mov     rax, EXIT_MACRO_DEF
    jmp     .ret

; ---- prep_getenv ------------------------
;
; prep_getenv
; Input    : rdi = a variable's name
; Output   : rax = its value (after the '='), 0 when it is not set
;
prep_getenv:
    push    rbx
    push    r12
    extern  utasm_envp
    mov     rbx, [rel utasm_envp]
    test    rbx, rbx
    jz      .none
.var:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .none
    mov     r12, rdi
.cmp:
    movzx   eax, byte [r12]
    test    eax, eax
    jz      .name_end
    cmp     al, [rsi]
    jne     .next
    inc     r12
    inc     rsi
    jmp     .cmp
.name_end:
    cmp     byte [rsi], '='
    jne     .next
    lea     rax, [rsi + 1]
    jmp     .ret
.next:
    add     rbx, 8
    jmp     .var
.none:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret

; ---- %stacksize / %arg / %local ---------
;
; NASM's stack frame helpers. "%stacksize flat | flat64 | large | small"
; sets the frame register, the slot size and where arguments start:
;
;   flat    ebp, 4, [ebp+8]       large   bp, 2, [bp+4]
;   flat64  rbp, 8, [rbp+16]      small   bp, 2, [bp+6]
;
; (flat until one is given). "%arg a:dword, b:word" defines each name as
; the next argument's address, "ebp+8", "ebp+12"; "%local x:dword" as the
; next local's, "ebp-4", and adds its size to %$localsize (NASM writes
; "(ebp+8)": utasm's addresses take no registers in parentheses). A
; type (byte, word, dword, qword, tword) takes at least one slot. The
; definitions are read as text, after the line.
;
prep_handle_stacksize:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    lea     r8, [rel stk_modes]
.mode:
    cmp     byte [r8], 0
    je      .bad
    push    r8
    mov     rdi, r12
    mov     rsi, r8
    call    prep_str_cmp_ci
    pop     r8
    test    rax, rax
    jz      .hit
    add     r8, 16
    jmp     .mode
.hit:
    movzx   eax, byte [r8 + 8]
    mov     [rel stk_size], eax
    movzx   eax, byte [r8 + 9]
    mov     [rel stk_arg], eax
    mov     dword [rel stk_local], 0
    lea     rax, [r8 + 10]
    mov     [rel stk_reg], rax
    mov     rdi, rbx
    call    prep_drain_line
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r12
    pop     rbx
    ret

; esi = 0 %arg, 1 %local
prep_handle_frame:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r14d, esi
    lea     r15, [rel stk_text]
    mov     byte [r15], 10                 ; ends the directive's line
    inc     r15
.item:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     r12, [rdx + TOKEN_value]       ; the name
    cmp     eax, TOK_LABEL                 ; "a:dword"
    je      .type
    cmp     eax, TOK_IDENT                 ; "a : dword"
    jne     .bad
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .bad
.type:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r13, [rdx + TOKEN_value]
    lea     r8, [rel stk_types]
.size:
    cmp     byte [r8], 0
    je      .bad
    push    r8
    mov     rdi, r13
    mov     rsi, r8
    call    prep_str_cmp_ci
    pop     r8
    test    rax, rax
    jz      .sized
    add     r8, 8
    jmp     .size
.sized:
    movzx   r13d, byte [r8 + 7]
    cmp     r13d, [rel stk_size]
    jae     .slot
    mov     r13d, [rel stk_size]           ; at least one slot
.slot:
    lea     rax, [rel stk_text + STK_TEXT - 192]
    cmp     r15, rax
    jae     .bad                           ; too many on one line
    ; "%define NAME REG+OFFSET" / "REG-OFFSET"
    lea     rsi, [rel stk_define]
    call    .put
    mov     rsi, r12
    call    .put
    mov     byte [r15], ' '
    inc     r15
    mov     rsi, [rel stk_reg]
    call    .put
    test    r14d, r14d
    jnz     .local
    mov     byte [r15], '+'
    inc     r15
    mov     eax, [rel stk_arg]
    add     [rel stk_arg], r13d
    call    .num
    mov     byte [r15], 10
    inc     r15
    jmp     .next
.local:
    mov     byte [r15], '-'
    inc     r15
    add     [rel stk_local], r13d
    mov     eax, [rel stk_local]
    call    .num
    mov     byte [r15], 10
    inc     r15
    lea     rsi, [rel stk_assign]          ; %$localsize grows with it
    call    .put
    mov     eax, r13d
    call    .num
    mov     byte [r15], 10
    inc     r15
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .end
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .item
.end:
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .push
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    jne     .bad
.push:
    mov     rdi, rbx
    lea     rsi, [rel stk_text]
    mov     rdx, r15
    sub     rdx, rsi
    lea     rcx, [rel dir_arg]
    test    r14d, r14d
    jz      .named
    lea     rcx, [rel dir_local]
.named:
    call    prep_push_buffer
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

    ; appends the string rsi
.put:
    mov     al, [rsi]
    test    al, al
    jz      .put_end
    mov     [r15], al
    inc     rsi
    inc     r15
    jmp     .put
.put_end:
    ret

    ; appends eax in decimal
.num:
    sub     rsp, 16
    lea     r8, [rsp + 15]
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    mov     [r8], dl
    dec     r8
    test    eax, eax
    jnz     .digit
.copy:
    inc     r8
    lea     rax, [rsp + 16]
    cmp     r8, rax
    jae     .num_end
    mov     al, [r8]
    mov     [r15], al
    inc     r15
    jmp     .copy
.num_end:
    add     rsp, 16
    ret

; ---- prep_is_macro_open ----------------
;
; ZF set when the directive name rdi opens a macro definition other than
; %macro itself: %rmacro, %imacro, %irmacro (the nesting scans count them).
;
prep_is_macro_open:
    push    rdi
    lea     rsi, [rel dir_rmacro]
    call    str_cmp
    test    rax, rax
    jz      .ret
    mov     rdi, [rsp]
    lea     rsi, [rel dir_imacro]
    call    str_cmp
    test    rax, rax
    jz      .ret
    mov     rdi, [rsp]
    lea     rsi, [rel dir_irmacro]
    call    str_cmp
    test    rax, rax
.ret:
    pop     rdi
    ret

; ---- prep_define_string -----------------
;
; prep_define_string
; Defines a single-line macro as a quoted string (%pathsearch, as %defstr
; would).
; Input    : rdi = PrepState, rsi = name, rdx = the string
; Output   : rax = EXIT_OK or error
;
prep_define_string:
    push    rbx
    push    r12
    push    r13
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     rdi, r13
    call    str_len
    mov     rcx, rax
    mov     rsi, r13
    call    prep_scratch_string
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     r15d, 1
    call    prep_define_store
    pop     r15
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_interp_standalone ----------------
;
; prep_interp_standalone
; "%[...]" written on its own: NASM reads the tokens inside, macros
; expanded there and then - in a %define's body or a %rep line, the value
; of the moment. They are lexed from the text inside the brackets; a name
; that is a %define with no parameters gives its tokens, an %assign its
; value (one level: what they give expands as it is read). The first takes
; the place of the token, the others come right after it (an anonymous,
; %define-like expansion that reads nothing of the line).
; Input    : rbx = PrepState, rsi = the token ("%[...]" in TOKEN_value)
; Output   : rax = EXIT_OK or an error; edx = 1 when there is no token
;            (the token is to be dropped)
;
prep_interp_standalone:
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    mov     r12, rsi
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_INTERP
    ; the text inside: past "%[", up to the last ']'
    mov     r13, [r12 + TOKEN_value]
    add     r13, 2
    mov     rdi, r13
    call    str_len
    mov     rdx, rax
    test    rdx, rdx
    jz      .lexed_none
    cmp     byte [r13 + rdx - 1], ']'
    jne     .text_len
    dec     rdx
.text_len:
    ; its own lexer
    push    rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; r14 = the lexer
    mov     rdi, r14
    mov     rsi, r13
    mov     rdx, rcx
    mov     rcx, [r12 + TOKEN_file]
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [rbx + PREP_arena]
    call    lexer_init
    test    rax, rax
    jnz     .ret
    ; the output (it grows)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE * 16
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; r13 = the output
    mov     qword [rel relex_cap], 16
    xor     r15d, r15d                     ; r15 = how many
.token:
    lea     rsi, [rel relex_tok]
    mov     rdi, r14
    call    lexer_next
    test    rax, rax
    jnz     .ret
    lea     rbp, [rel relex_tok]           ; rbp = the token read
    movzx   eax, byte [rbp + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .lexed
    cmp     eax, TOK_EOF
    je      .lexed
    ; where the %[...] was written (messages, the listing)
    mov     eax, [r12 + TOKEN_line]
    mov     [rbp + TOKEN_line], eax
    mov     ax, [r12 + TOKEN_col]
    mov     [rbp + TOKEN_col], ax
    mov     rax, [r12 + TOKEN_file]
    mov     [rbp + TOKEN_file], rax
    cmp     byte [rbp + TOKEN_kind], TOK_IDENT
    jne     .put_it
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rbp + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .put_it
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    je      .assign
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .put_it
    mov     rax, [rdx + SYMBOL_value]
    test    byte [rax + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .put_it
    test    byte [rax + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .put_it
    ; a %define: its tokens
    mov     r8, [rax + MACRO_tokens]
    mov     r9d, [rax + MACRO_ntokens]
.body:
    test    r9d, r9d
    jz      .token
    push    r8
    push    r9
    mov     rbp, r8
    call    .append
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .ret
    add     r8, TOKEN_SIZE
    dec     r9d
    jmp     .body
.assign:
    ; an %assign: its value, a number
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    push    rdx
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rdi, rdx
    mov     rsi, [rcx + SYMBOL_value]
    call    str_int_to_str
    pop     rdx
    mov     byte [rbp + TOKEN_kind], TOK_NUMBER
    mov     [rbp + TOKEN_value], rdx
.put_it:
    call    .append
    test    rax, rax
    jnz     .ret
    jmp     .token
.lexed:
    xor     eax, eax
    test    r15, r15
    jnz     .some
.lexed_none:
    xor     eax, eax
    mov     edx, 1                         ; nothing: the token goes
    jmp     .out
.some:
    ; the first in its place
    mov     rdi, r12
    mov     rsi, r13
    copy_token
    cmp     r15, 1
    je      .one
    ; the others after it
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_DEFINE
    mov     qword [rdx + MACRO_name], 0
    lea     rax, [r13 + TOKEN_SIZE]
    mov     [rdx + MACRO_tokens], rax
    lea     eax, [r15d - 1]
    mov     [rdx + MACRO_ntokens], eax
    mov     rdi, rbx
    mov     rsi, rdx
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
.one:
    xor     eax, eax
.ret:
    xor     edx, edx
.out:
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
; .append: the token at rbp onto the output (r13, r15). rax = 0 or an
; error. Clobbers rcx, rdx, rsi, rdi, r8-r11
.append:
    cmp     r15, [rel relex_cap]
    jb      .append_room
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel relex_cap]
    shl     rsi, 1
    imul    rsi, rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .append_ret
    mov     rdi, rdx
    mov     rsi, r13
    imul    rcx, r15, TOKEN_SIZE
    rep movsb
    mov     r13, rdx
    shl     qword [rel relex_cap], 1
.append_room:
    imul    rdi, r15, TOKEN_SIZE
    add     rdi, r13
    mov     rsi, rbp
    copy_token
    inc     r15
    xor     eax, eax
.append_ret:
    ret

; ---- prep_list_label (internal) -----------
; "lab: m" with -l: "lab: " listed as the first line of m's expansion, at
; the call's line (lst_label_line) - unless m takes the label itself
; (%00 in its body), as NASM. rbx = PrepState; preserves r12-r15.
prep_list_label:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .ret
    mov     rax, [rax + MACROEXP_macro]
    mov     rsi, [rax + MACRO_tokens]
    mov     ecx, [rax + MACRO_ntokens]
.scan_00:
    test    ecx, ecx
    jz      .no_00
    cmp     byte [rsi + TOKEN_kind], TOK_DIRECTIVE
    jne     .scan_next
    mov     rdx, [rsi + TOKEN_value]
    cmp     word [rdx], '00'
    jne     .scan_next
    cmp     byte [rdx + 2], 0
    je      .ret                           ; %00: the macro takes it
.scan_next:
    add     rsi, TOKEN_SIZE
    dec     ecx
    jmp     .scan_00
.no_00:
    mov     rdi, [rel ml_label]
    test    rdi, rdi
    jz      .ret
    call    str_len
    push    rax
    lea     rsi, [rax + 3]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, [rel ml_label]
    push    rdx
    rep movsb
    mov     word [rdi], ': '
    mov     byte [rdi + 2], 0
    pop     rcx                            ; the text
    extern  error_loc_file, error_loc_line, lst_label_line
    mov     rdi, [rel error_loc_file]
    mov     esi, [rel error_loc_line]
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    xor     edx, edx
    test    rax, rax
    jz      .depth
    mov     edx, [rax + MACROEXP_lst_depth]
.depth:
    call    lst_label_line
.ret:
    ret

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
; r0l, r0h-r3h), case-insensitively, as NASM's package does. Other
; packages (smartalign, fp, ifunc, ...) are accepted: utasm has what they
; would add or does not need it.
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
    ; %use smartalign: align pads code with long NOPs (optimizer/align.s),
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

; ---- prep_handle_def ------------------
;
; prep_handle_def
; "%define NAME body": NAME stands for the rest of the line, expanded where
; NAME is used (as in NASM, where a %define is text). The body is kept as a
; parameterless macro, so the expansion machinery that serves %macro calls
; serves it too. "%define NAME(a, b) body", with the parenthesis right
; after the name, takes arguments: NAME(1, 2); the parameter names in the
; body become %1, %2.
;
; The body is read with %1 / %%local substituted (inside a macro) but other
; macros left unexpanded, so it is expanded when used; %xdefine (def_eager)
; expands it now. A redefinition replaces the earlier body.
;
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_def:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    ; An expression-evaluating directive can leave the terminating NEWLINE
    ; in the peek slot; it does not belong to this definition.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_stale_peek
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .no_stale_peek
    mov     byte [rbx + PREP_has_peek], FALSE
.no_stale_peek:

    ; 1. The name, never expanded: redefining must not expand the old body
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; r12 = name
    movzx   r13d, word [rdx + TOKEN_col]
    movzx   eax, word [rdx + TOKEN_len]
    add     r13d, eax                      ; the column right after the name
    mov     r14d, [rdx + TOKEN_line]

    ; %idefine: stored under a case-insensitive key
    cmp     byte [rel def_icase], 0
    je      .name_ready
    mov     rsi, r12
    call    prep_icase_buf
    test    rax, rax
    jnz     .bad
    lea     rdi, [rel icase_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r12, rdx
    mov     rdi, rdx
    lea     rsi, [rel icase_buf]
    call    str_concat
    inc     dword [rel idefine_count]
.name_ready:

    ; the body is expanded now only for %xdefine; that has to hold from the
    ; first peek on, which may already read the body's first token
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al

    ; 2. Parameters: "NAME(a, b)" with no blank before the parenthesis
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .body
    cmp     [rdx + TOKEN_line], r14d
    jne     .body
    cmp     [rdx + TOKEN_col], r13w
    jne     .body
    mov     byte [rel def_func], MACRO_FLAG_FUNC
    mov     rdi, rbx
    call    preprocessor_next_token        ; "("
.param:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_RPAREN
    je      .body
    cmp     eax, TOK_COMMA
    je      .param
    cmp     eax, TOK_IDENT
    jne     .bad
    movzx   ecx, byte [rel def_nparams]
    cmp     ecx, 9
    jae     .bad                           ; %1-%9
    mov     rax, [rdx + TOKEN_value]
    lea     r8, [rel def_pnames]
    mov     [r8 + rcx*8], rax
    inc     byte [rel def_nparams]
    jmp     .param

    ; 3. The body: the rest of the line
.body:
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al        ; %xdefine expands now
    xor     r15d, r15d                     ; tokens captured
    lea     rax, [rel def_scratch]
    mov     [rel def_toks], rax
    mov     qword [rel def_cap], DEFINE_MAX_TOKENS
.btok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .store
    cmp     eax, TOK_EOF
    je      .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     r15, [rel def_cap]
    jb      .def_room
    ; full: twice the size (the token just read is in the peek slot rdx
    ; points at, which the copy does not touch)
    push    rdx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel def_toks]
    mov     edx, r15d
    mov     rcx, [rel def_cap]
    call    prep_tokbuf_grow
    mov     rdi, rdx
    pop     rdx
    test    rax, rax
    jnz     .fail
    mov     [rel def_toks], rdi
    mov     [rel def_cap], rcx
.def_room:
    mov     eax, r15d
    imul    eax, eax, TOKEN_SIZE
    mov     rdi, [rel def_toks]
    add     rdi, rax
    mov     r8, rdi                        ; r8 = the captured token
    mov     rsi, rdx
    copy_token
    inc     r15d
    ; a parameter name becomes a %N reference
    cmp     byte [r8 + TOKEN_kind], TOK_IDENT
    jne     .btok
    xor     r14d, r14d
.pname:
    movzx   eax, byte [rel def_nparams]
    cmp     r14d, eax
    jae     .btok
    push    r8
    mov     rdi, [r8 + TOKEN_value]
    lea     rax, [rel def_pnames]
    mov     rsi, [rax + r14*8]
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .is_param
    inc     r14d
    jmp     .pname
.is_param:
    mov     byte [r8 + TOKEN_kind], TOK_DIRECTIVE
    lea     rax, [rel def_digits]
    lea     rax, [rax + r14*2 + 2]         ; "1".."9"
    mov     [r8 + TOKEN_value], rax
    jmp     .btok

    ; 4. A MACRO with the captured tokens, under NAME
.store:
    mov     byte [rel prep_noexpand], 0
    call    prep_define_store
    jmp     .ret

.bad:
    mov     rax, EXIT_DEFINE
.fail:
    mov     byte [rel prep_noexpand], 0
.ret:
    lea     rcx, [rel def_scratch]
    mov     [rel def_toks], rcx            ; for the one-token definitions
    mov     byte [rel def_eager], 0
    mov     byte [rel def_icase], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- prep_define_store ------------------
;
; prep_define_store
; Stores a %define: a MACRO holding the tokens in def_toks, under the
; name. A redefinition replaces the earlier body.
; Input    : rbx = PrepState, r12 = name, r15d = token count;
;            def_nparams / def_func describe the parameters
; Output   : rax = EXIT_OK or error
;
prep_define_store:
    push    r13
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r13, rdx
    mov     byte [r13 + MACRO_tag], TAG_MACRO
    movzx   eax, byte [rel def_nparams]
    mov     [r13 + MACRO_min_params], ax
    mov     [r13 + MACRO_max_params], ax
    movzx   eax, byte [rel def_func]
    or      eax, MACRO_FLAG_DEFINE
    mov     [r13 + MACRO_flags], al
    mov     [r13 + MACRO_name], r12
    mov     [r13 + MACRO_ntokens], r15d
    mov     eax, r15d
    inc     eax
    imul    esi, eax, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     [r13 + MACRO_tokens], rdx
    mov     rdi, rdx
    mov     rsi, [rel def_toks]            ; def_scratch, or a bigger array
    mov     eax, r15d
    imul    ecx, eax, TOKEN_SIZE / 8
    rep movsq

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .create
    ; "X equ 2" then "%define X 2": a macro and a symbol are apart in NASM;
    ; the entry becomes the macro and keeps the constant's value for after
    ; the preprocessor (prep_unshadow)
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .redefine
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .redefine
    mov     rax, [rdx + SYMBOL_value]
    mov     [rdx + SYMBOL_size], rax
    or      byte [rdx + SYMBOL_pflags], SYMF_SHADOW
.redefine:
    mov     byte [rdx + SYMBOL_kind], SYM_MACRO    ; a redefinition
    mov     [rdx + SYMBOL_value], r13
    xor     eax, eax
    jmp     .ret
.create:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    mov     rcx, SYMBOL_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_MACRO
    mov     [rsp + SYMBOL_name], r12
    mov     [rsp + SYMBOL_value], r13
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
.fail:
.ret:
    pop     r13
    ret

; ---- prep_handle_if ---------------------
;
; prep_handle_if
; Handles the %if directive by evaluating a mathematical expression.
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_if:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. If we are already skipping, just increment depth
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .already_skipping

    ; 2. Evaluate expression
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     rdi, rbx
    extern  parser_evaluate_expression
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .done

    ; 3. Push the level with the result (%ifn: the other way)
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    xor     sil, [rel cond_negate]
    mov     byte [rel cond_negate], 0
    mov     rdi, rbx
    call    prep_cond_enter
    jmp     .done

.already_skipping:
    mov     byte [rel cond_negate], 0
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_enter

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_else -------------------
prep_handle_else:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     ax, [rbx + PREP_depth]
    test    ax, ax
    jz      .error                 ; %else without %if

    ; 1. If we are currently skipping at THIS depth ONLY, we toggle.
    ; If skip_depth == 1, it means the current level is the only one skipping.
    ; If skip_depth > 1, an outer level is skipping, so %else doesn't matter.
    ; If skip_depth == 0, the current level was taken, so now we skip.
    
    mov     rdi, rbx
    mov     esi, 1                 ; %else always "matches" if nothing did yet
    call    prep_cond_branch

.done:
    xor     rax, rax
    pop     rbx
    epilogue

.error:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue

; ---- prep_handle_endif ------------------
prep_handle_endif:
    prologue
    push    rbx
    mov     rbx, rdi

    ; 1. If we are skipping, decrement skip depth
    cmp     word [rbx + PREP_skip_depth], 0
    je      .not_skipping
    dec     word [rbx + PREP_skip_depth]

.not_skipping:
    ; 2. Decrement total depth (guard against underflow)
    cmp     word [rbx + PREP_depth], 0
    je      .done
    dec     word [rbx + PREP_depth]

.done:
    xor     rax, rax
    pop     rbx
    epilogue

.error_no_if:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue

; ---- prep_skip_macro_block & prep_skip_rep_block ----
global prep_skip_macro_block
prep_skip_macro_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %macro)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, rbx                   ; the expansion first, then the file
    mov     rsi, r13
    call    prep_raw_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "macro"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    mov     rdi, [r13 + TOKEN_value]
    call    prep_is_macro_open             ; %rmacro, %imacro, %irmacro
    jz      .nest_in
    
    ; Compare with "endmacro" (or "endm")
    mov     rdi, [r13 + TOKEN_value]
    call    prep_is_macro_end
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

global prep_skip_rep_block
prep_skip_rep_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %rep)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r13
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "rep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    
    ; Compare with "endrep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- macro_handle_def -------------------
;
; macro_handle_def
; Handles the %macro directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
; ---- prep_parse_count -------------------
;
; prep_parse_count
; The parameter count of %macro / %unmacro: "N", "N-M" or "N-*", then "+"
; (the last parameter takes the rest of the line) and ".nolist", as NASM
; reads them, with its errors.
; Input    : rbx = PrepState, rdi = the directive's name (for the messages)
; Output   : rax = OK or an error; rcx = the minimum, rdx = the maximum
;            (MACRO_VARIADIC for "*"); mdef_greedy = MACRO_FLAG_GREEDY for "+"
;
prep_parse_count:
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE
    mov     r12, rdi
    mov     byte [rel mdef_greedy], 0
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    test    rax, rax
    jnz     .ret
    cmp     byte [rsp + TOKEN_kind], TOK_NUMBER
    jne     .no_count
    mov     rdi, [rsp + TOKEN_value]
    call    str_to_int
    mov     r13, rdx                       ; the minimum
    mov     r14, rdx                       ; the maximum, unless "-M"
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    cmp     byte [rsp + TOKEN_kind], TOK_MINUS
    jne     .range
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next                  ; '-'
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    cmp     byte [rsp + TOKEN_kind], TOK_NUMBER
    jne     .max_star
    mov     rdi, [rsp + TOKEN_value]
    call    str_to_int
    mov     r14, rdx
    jmp     .range
.max_star:
    cmp     byte [rsp + TOKEN_kind], TOK_STAR
    jne     .no_max
    mov     r14, MACRO_VARIADIC
.range:
    ; up to MACRO_PARAMS_MAX parameters (the counts are words)
    mov     eax, EXIT_MACRO_DEF
    cmp     r13, MACRO_PARAMS_MAX
    ja      .ret
    cmp     r14, MACRO_VARIADIC
    je      .tail
    cmp     r14, MACRO_PARAMS_MAX
    ja      .ret
    mov     eax, EXIT_MACRO_MINMAX
    cmp     r13, r14
    ja      .ret
.tail:
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_peek
    movzx   eax, byte [rsp + TOKEN_kind]
    cmp     eax, TOK_PLUS
    jne     .not_plus
    mov     byte [rel mdef_greedy], MACRO_FLAG_GREEDY
    jmp     .tail_eat
.not_plus:
    cmp     eax, TOK_IDENT
    jne     .counted
    mov     rdi, [rsp + TOKEN_value]
    lea     rsi, [rel str_nolist]
    call    str_cmp
    test    rax, rax
    jnz     .counted
.tail_eat:
    mov     rdi, rbx
    mov     rsi, rsp
    call    prep_raw_next
    jmp     .tail
.counted:
    xor     eax, eax
    mov     rcx, r13
    mov     rdx, r14
    jmp     .ret
.no_count:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_COUNT
    jmp     .ret
.no_max:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_MACRO_NO_MAX
.ret:
    add     rsp, TOKEN_SIZE
    pop     r14
    pop     r13
    pop     r12
    ret

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
    ; commas): NASM's warning
    cmp     r15, MACRO_VARIADIC
    je      .defaults_fit
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
    or      [r15 + MACRO_flags], al
    mov     rax, [rel mdef_defaults]
    mov     [r15 + MACRO_defaults], rax
    mov     eax, [rel mdef_ndefaults]
    mov     [r15 + MACRO_ndefaults], eax

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
    call    symbol_find
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
    call    symbol_add
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

;*
; * [prep_handle_rep]
; * Input: RDI = PrepState
; ;
prep_handle_rep:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    sub     rsp, 16                ; [rbp - 56]: total token count, [rbp - 64]: temp slot
    
    mov     rbx, rdi               ; rbx = PREP state

    ; 1. Get repeat count. It is an expression, not just a literal:
    ;    "%rep %%len" drives compile_time_hash.
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .error
    mov     r14, rdx               ; r14 = count

    ; 2. Allocate anonymous MACRO struct
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r15, rdx               ; r15 = Macro struct
    mov     byte [r15 + MACRO_tag], TAG_MACRO
    mov     qword [r15 + MACRO_name], 0
    mov     word [r15 + MACRO_min_params], 0
    mov     word [r15 + MACRO_max_params], 0
    
    ; 3. Capture tokens until %endrep
    mov     qword [rbp - 56], 0    ; Total token count = 0
    xor     r13, r13               ; Nesting depth = 0

    ; Reserve the body as one contiguous block: lexer_next allocates token
    ; value strings from this same arena, so slots taken one at a time would
    ; be interleaved with those strings.
    call    prep_cap_base                  ; (copied out at its size below)
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx      ; the capture's base, until then

.capture:

    ; Point at the next slot in the capture area
    mov     rdi, [r15 + MACRO_tokens]
    mov     rsi, [rbp - 56]
    call    prep_cap_slot
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = current token slot

    mov     rdi, rbx
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .error_eof

    ; Check for % directive
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .store_token

    ; It's a TOK_DIRECTIVE. Check for "rep" or "endrep"
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out

    jmp     .store_token

.nest_in:
    inc     r13                    ; found nested %rep
    inc     qword [rbp - 56]
    jmp     .capture

.nest_out:
    test    r13, r13
    jz      .captured              ; outermost %endrep found!
    
    dec     r13
    inc     qword [rbp - 56]
    jmp     .capture

.store_token:
    inc     qword [rbp - 56]
    jmp     .capture

.captured:
    mov     rax, [rbp - 56]
    mov     [r15 + MACRO_ntokens], eax
    mov     rdi, rbx
    mov     rsi, [r15 + MACRO_tokens]
    mov     rdx, rax
    call    prep_cap_take                  ; the body at its size
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx
    
    ; 4. Start expansion
    mov     rdi, rbx
    mov     rsi, r15
    call    prep_expand_start
    test    rax, rax
    jnz     .error
    mov     dword [rdx + MACROEXP_rep_count], r14d ; set repetition count
    
    xor     rax, rax               ; success
    jmp     .done

.error_eof:
.error:
    mov     rax, 1                 ; error
    jmp     .done

.done:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

[SECTION .bss]
ml_state:      resb 1              ; ML_*: where the token read stands
ml_called_at:  resb 1              ; ml_state where a multi-line macro was called
alignb 8
relex_cap:     resq 1              ; prep_interp_relex: its array's room
ml_label:      resq 1              ; the line's first word (a label?)
relex_tok:     resb TOKEN_SIZE     ; ... the token just read
global prep_noexpand
prep_noexpand: resb 1              ; 1: identifiers are not macro calls (a directive reads a name)
def_eager:     resb 1              ; 1: %xdefine, expand the body now
def_func:      resb 1              ; MACRO_FLAG_FUNC for NAME(a, b)
def_nparams:   resb 1
fn_depth:      resd 1              ; parenthesis depth in a function-like call
def_pnames:    resq 9              ; parameter names of a function-like %define
def_scratch:   resb DEFINE_MAX_TOKENS * TOKEN_SIZE
alignb 8
def_cap:       resq 1              ; their capacity
rec_base:      resq 1              ; prep_rec_begin: the tokens recorded
rec_n:         resq 1              ; ... how many
rec_suspend:   resd 1              ; > 0 while a macro call reads its arguments
rec_on:        resb 1              ; recording
rec_overflow:  resb 1              ; the capture area filled
cap_top:       resq 1              ; the capture area: its top (prep_cap_base)
cap_end:       resq 1              ; ... and its end
def_icase:     resb 1              ; 1: %idefine
idefine_count: resd 1              ; %idefine names so far
icase_buf:     resb 256            ; a name's case-insensitive key
idn_case:      resb 1              ; 1: %ifidn compares case-sensitively
exit_open:     resb 1              ; %if blocks %exitrep has to close
mdef_dir:       resq 1                  ; the directive's name (macro, imacro ...)
mdef_defaults:resq 1              ; %macro header: default argument tokens
mdef_ndefaults: resd 1             ; ... and how many
mdef_greedy:   resb 1              ; ... MACRO_FLAG_GREEDY after a "+"
putback_next:  resb TOKEN_SIZE     ; a token queued behind the peek slot
has_putback_next: resb 1
interp_cap:    resq 1              ; prep_resolve_interp: its buffer's size
idn_left_buf:  resb IDN_BUF; %ifidn operands as text (to start with)
idn_right_buf: resb IDN_BUF
idn_prev_line: resd 1              ; prep_idn_collect: where the last token ended
idn_prev_end:  resd 1
brace_depth:   resd 1              ; {..} nesting in a macro argument
brace_dropped: resb 1              ; the argument's opening brace was dropped
mdef_icase:    resb 1              ; %imacro: the name is case-insensitive
rng_a:         resq 1              ; %{a:b}
rng_b:         resq 1
rng_owner:     resq 1
rng_total:     resq 1
rng_buf:       resq 1

[SECTION .data]
; what a caller gets for a token when the preprocessor fails (prep_error_note)
align 8
prep_error_token:
    db TAG_TOKEN, TOK_NEWLINE, 0, 0, 0, 0, 0, 0
    dq prep_error_text
    dd 0
    dw 0, 0
    dq 0
prep_error_text: db 0
dump_newline:   db 10
dump_colon:     db ":"
dump_blank:     db " "
dump_bq:        db "`"
dump_quote:     db 0
dump_hex:       db 0, 0, 0, 0
dump_digits:    db "0123456789abcdef"

[SECTION .bss]
alignb 8
prep_error_subj: resq 1                 ; prep_error's subject
prep_error:     resd 1                  ; the first error a caller got, or 0
cond_negate:    resb 1                  ; %ifn / %elifn: the result inverted
stk_text:       resb STK_TEXT               ; %arg / %local definitions
elif_negate:    resb 1
alignb 4
dump_prev_line: resd 1                  ; line and end column of the token
dump_prev_end:  resd 1                  ; written last (-E spacing)
dump_prev_kind: resb 1                  ; ... and its kind
