;
; ============================================
; File     : src/frontend/preproc/macro.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

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
%define IFT_ALIAS   10                     ; %ifdefalias: a name %defalias made
%define ALIAS_MAX   256
%define NEST_BUF    1024                   ; prep_resolve_interp's spliced text
; ml_state: where the token being read stands in its line - a multi-line
; macro is called at ML_START or ML_COLON only
%define ML_START    0                      ; the first word
%define ML_LABEL    1                      ; after a first word (a label?)
%define ML_COLON    2                      ; after "label:"
%define ML_NONE     3                      ; anywhere else
%define STK_TEXT    4096                   ; %arg / %local text for one line
extern asm_bits
extern warn_begin, warn_text, warn_end
extern user_sect_name

DEFAULT REL

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
extern str_cmp_kw
extern str_is_ident_char
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
extern error_set_location
global preprocessor_next_token
global prep_internal_next
global prep_handle_directive
preprocessor_next_token:
    ; The fast path: a token peeked is taken without a frame (r8 - r11 kept,
    ; as the slow path's peek branch keeps them)
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     .slow
    call    prep_token_slot                ; rdx = its slot
    mov     byte [rdi + PREP_has_peek], FALSE
    movdqu  xmm0, [rdi + PREP_peek]
    movdqu  xmm1, [rdi + PREP_peek + 16]
    movdqu  [rdx], xmm0
    movdqu  [rdx + 16], xmm1
    ; a token queued behind the one just taken moves up
    cmp     byte [rel has_putback_next], TRUE
    jne     .fast_taken
    movdqu  xmm0, [rel putback_next]
    movdqu  xmm1, [rel putback_next + 16]
    movdqu  [rdi + PREP_peek], xmm0
    movdqu  [rdi + PREP_peek + 16], xmm1
    mov     byte [rdi + PREP_has_peek], TRUE
    mov     byte [rel has_putback_next], FALSE
.fast_taken:
    xor     ecx, ecx
    xor     eax, eax
    jmp     prep_rec_note                  ; (an expression being recorded)

.slow:
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
    
    ; A slot for the peeked token (prep_token_slot)
    call    prep_token_slot
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
    ; 2. A slot for the result (prep_token_slot)
    call    prep_token_slot
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


; ---- prep_label_define ------------------
;
; A label ("foo:") whose name is a %define with no parameters and whose
; body ends in a name ("%define foo bar", "%define L lab_ %+ 3"): its
; body, the last name the label, expanded in its place - NASM expands the
; macros of a label too. Not inside its own expansion.
; Input    : rbx = PrepState, r12 = the label token
; Output   : rax = 0 none, 1 the expansion started, else an error
;
prep_label_define:
    push    r13
    push    r14
    push    r15
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    prep_symbol_find
    test    rax, rax
    jnz     .no
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .no
    mov     r13, [rdx + SYMBOL_value]
    test    r13, r13
    jz      .no
    test    byte [r13 + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .no
    test    byte [r13 + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .no
    mov     ecx, [r13 + MACRO_ntokens]
    test    ecx, ecx
    jz      .no
    lea     eax, [rcx - 1]
    imul    rax, rax, TOKEN_SIZE
    add     rax, [r13 + MACRO_tokens]
    cmp     byte [rax + TOKEN_kind], TOK_IDENT
    je      .last_name
    ; "%define L lab_ %+ 3": a number joined on is the name's end too
    cmp     byte [rax + TOKEN_kind], TOK_NUMBER
    jne     .no
    cmp     ecx, 2
    jb      .no
    cmp     byte [rax - TOKEN_SIZE + TOKEN_kind], TOK_CONCAT
    jne     .no
.last_name:
    ; inside its own expansion: the name stays
    mov     rcx, [rbx + PREP_ctx]
    mov     rcx, [rcx + ASMCTX_mac_exp]
.painted:
    test    rcx, rcx
    jz      .copy
    mov     r8, [rcx + MACROEXP_macro]
    test    byte [r8 + MACRO_flags], MACRO_FLAG_DEFINE
    jz      .copy
    mov     r9, [r8 + MACRO_name]
    cmp     r9, [r13 + MACRO_name]
    je      .no
    mov     rcx, [rcx + MACROEXP_parent]
    jmp     .painted
.copy:
    ; a copy of the macro (its name too), the last token the label
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    mov     rdi, r14
    mov     rsi, r13
    mov     ecx, MACRO_SIZE
    rep movsb
    mov     eax, [r13 + MACRO_ntokens]
    imul    rsi, rax, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    mov     rdi, r15
    mov     rsi, [r13 + MACRO_tokens]
    mov     eax, [r13 + MACRO_ntokens]
    imul    rcx, rax, TOKEN_SIZE
    rep movsb
    mov     [r14 + MACRO_tokens], r15
    mov     eax, [r13 + MACRO_ntokens]
    dec     eax
    imul    rax, rax, TOKEN_SIZE
    add     rax, r15
    mov     byte [rax + TOKEN_kind], TOK_LABEL
    mov     rcx, [rax + TOKEN_value]
    cmp     byte [rcx], '.'
    jne     .labelled
    mov     byte [rax + TOKEN_kind], TOK_LOCAL_LABEL
.labelled:
    mov     rdi, rbx
    mov     rsi, r14
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    ret

; ---- prep_handle_pragma -----------------
;
; "%pragma NS gprefix TEXT" (gpostfix, lprefix, lpostfix): the text the
; output puts before / after the names of global symbols (and externs,
; commons) or of local ones, as NASM's. NS is "output" or the output's own
; ("elf", "elf64" / "elf32", "win", "win64", "coff", "bin"); the first one
; given for each wins ("%pragma elf gprefix" with no text: none, even
; with "%pragma output gprefix _" after it). Other pragmas: ignored.
; "[pragma ...]" is the same (pragma_bracket: the parser's, up to "]");
; -E writes a %pragma on as one, as NASM does (pragma_queue).
; Input: rbx = PrepState. The rest of the line is left (drained after).
;
global pragma_affix
global prep_handle_pragma, pragma_bracket
prep_handle_pragma:
    push    r12
    push    r13
    push    r14
    cmp     byte [rel lexer_mark_lone], 0
    jne     .dump
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token        ; the namespace
    test    rax, rax
    jnz     .out
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .out
    mov     r12, [rdx + TOKEN_value]
    mov     rdi, r12
    call    prep_pragma_ns
    test    eax, eax
    jz      .out
    mov     rdi, rbx
    call    preprocessor_next_token        ; the directive
    test    rax, rax
    jnz     .out
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .out
    mov     r13, [rdx + TOKEN_value]
    lea     r14, [rel pragma_words]
    xor     ecx, ecx
.word:
    cmp     byte [r14], 0
    je      .out
    mov     rdi, r13
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .hit
    inc     ecx
.skip:
    inc     r14
    cmp     byte [r14 - 1], 0
    jne     .skip
    jmp     .word
.hit:
    lea     r14, [rel pragma_affix]
    lea     r14, [r14 + rcx * 8]
    cmp     qword [r14], 0
    jne     .out                           ; the first one wins
    ; the text: the line's tokens up to its end, joined
    lea     rdi, [rel pragma_buf]
    mov     byte [rdi], 0
.text:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .text_done
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .text_done
    cmp     eax, TOK_EOF
    je      .text_done
    cmp     eax, TOK_RBRACKET
    jne     .text_take
    cmp     byte [rel pragma_bracket], 0
    jne     .text_done                     ; "[pragma ...]"'s end
.text_take:
    mov     rdi, rbx
    call    preprocessor_next_token
    call    prep_idn_text
    mov     rsi, rax
    mov     rdi, rsi
    call    str_len
    mov     r13, rax
    lea     rdi, [rel pragma_buf]
    call    str_len
    add     rax, r13
    cmp     rax, 120
    jae     .text
    lea     rdi, [rel pragma_buf]
    call    str_concat
    jmp     .text
.text_done:
    lea     rdi, [rel pragma_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .out
    mov     [r14], rdx                     ; (an empty text: set all the same)
    mov     rdi, rdx
    lea     rsi, [rel pragma_buf]
    call    str_concat
.out:
    mov     byte [rel prep_noexpand], 0
    pop     r14
    pop     r13
    pop     r12
    ret

.dump:
    ; -E: the line's text, for prep_dump to write as "[pragma ...]" - not
    ; the preprocessor's own ("%pragma preproc ..."), nor one with no name
    ; first. Queued: the directives up to the next line's token are all
    ; read before prep_dump sees it. An entry: file, line, the text
    mov     eax, [rel pragma_qlen]
    cmp     eax, PRAGMA_QUEUE - PRAGMA_ENTRY
    ja      .out                           ; (no room: left out)
    lea     rcx, [rel pragma_queue]
    add     rcx, rax
    mov     [rel pragma_entry], rcx
    mov     byte [rcx + 12], 0
    xor     r12d, r12d                     ; tokens read
.dump_token:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .out
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .dump_done
    cmp     eax, TOK_EOF
    je      .dump_done
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .out
    mov     r13, rdx
    test    r12d, r12d
    jnz     .dump_blank
    ; the first: where the line is, and its namespace
    cmp     byte [r13 + TOKEN_kind], TOK_IDENT
    jne     .out
    mov     rcx, [rel pragma_entry]
    mov     rax, [r13 + TOKEN_file]
    mov     [rcx], rax
    mov     eax, [r13 + TOKEN_line]
    mov     [rcx + 8], eax
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [rel s_pns_preproc]
    call    str_cmp_kw
    test    eax, eax
    jz      .out
    jmp     .dump_text
.dump_blank:
    test    byte [r13 + TOKEN_flags], TOK_FLAG_SPACE
    jz      .dump_text
    lea     rsi, [rel s_blank_text]
    call    .dump_append
.dump_text:
    inc     r12d
    mov     rdx, r13
    call    prep_idn_text
    mov     rsi, rax
    call    .dump_append
    jmp     .dump_token
.dump_done:
    test    r12d, r12d
    jz      .out
    mov     rdi, [rel pragma_entry]
    add     rdi, 12
    call    str_len
    add     eax, 12 + 1
    add     [rel pragma_qlen], eax         ; queued
    jmp     .out
; .dump_append: rsi's text after the entry's, as it fits
.dump_append:
    mov     r14, rsi
    mov     rdi, rsi
    call    str_len
    push    rax
    mov     rdi, [rel pragma_entry]
    add     rdi, 12
    call    str_len
    pop     rcx
    add     rax, rcx
    cmp     rax, PRAGMA_ENTRY - 12 - 1
    jae     .appended
    mov     rdi, [rel pragma_entry]
    add     rdi, 12
    mov     rsi, r14
    call    str_concat
.appended:
    ret

; prep_pragma_ns: eax = 1 when the namespace rdi applies to this output
prep_pragma_ns:
    push    r12
    mov     r12, rdi
    lea     rsi, [rel s_pns_output]
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
    extern  coff_enabled, elf32_enabled, global_ctx
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    jne     .not_bin
    lea     rsi, [rel s_pns_bin]
    jmp     .one
.not_bin:
    cmp     byte [rax + ASMCTX_fmt], FMT_ELF64
    jne     .no
    cmp     byte [rel coff_enabled], 0
    je      .elf
    mov     rdi, r12
    lea     rsi, [rel s_pns_win]
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
    mov     rdi, r12
    lea     rsi, [rel s_pns_win64]
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
    lea     rsi, [rel s_pns_coff]
    jmp     .one
.elf:
    mov     rdi, r12
    lea     rsi, [rel s_pns_elf]
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
    lea     rsi, [rel s_pns_elf64]
    cmp     byte [rel elf32_enabled], 0
    je      .one
    lea     rsi, [rel s_pns_elf32]
.one:
    mov     rdi, r12
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
.no:
    xor     eax, eax
    pop     r12
    ret
.yes:
    mov     eax, 1
    pop     r12
    ret

[SECTION .rodata]
pragma_words:   db "gprefix", 0, "gpostfix", 0, "lprefix", 0, "lpostfix", 0, 0
s_pns_output:   db "output", 0
s_pns_bin:      db "bin", 0
s_pns_elf:      db "elf", 0
s_pns_elf64:    db "elf64", 0
s_pns_elf32:    db "elf32", 0
s_pns_win:      db "win", 0
s_pns_win64:    db "win64", 0
s_pns_coff:     db "coff", 0
s_pns_preproc:  db "preproc", 0
s_blank_text:   db " ", 0
[SECTION .bss]
alignb 8
pragma_affix:   resq 4              ; gprefix, gpostfix, lprefix, lpostfix (0: none given)
pragma_buf:     resb 128
PRAGMA_ENTRY equ 12 + 256
PRAGMA_QUEUE equ 8192
pragma_queue:   resb PRAGMA_QUEUE   ; -E: %pragmas for prep_dump to write:
pragma_qlen:    resd 1              ; the file, the line, the text of each
pragma_entry:   resq 1              ; (the one being read)
pragma_where:   resb TOKEN_SIZE     ; (prep_dump: its line, as a token's)
pragma_bracket: resb 1              ; 1: the parser's "[pragma ...]"
[SECTION .text]

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


; ---- prep_token_slot ----------
;
; The token preprocessor_next_token / _peek_token hand out lives in one of
; TOKEN_RING slots, used in turn: the last TOKEN_RING tokens stay as they
; were (a caller keeps one while it reads a few more), the rest are reused
; - a fresh arena token for each was 32 bytes a token for the whole run.
; What has to last longer is copied (copy_token), as macro bodies and
; arguments are.
; Output   : rdx = the slot. Preserves everything else.
;
prep_token_slot:
    push    rax
    mov     eax, [rel token_ring_next]
    lea     edx, [eax + 1]
    and     edx, TOKEN_RING - 1
    mov     [rel token_ring_next], edx
    shl     eax, 5                         ; * TOKEN_SIZE
    lea     rdx, [rel token_ring]
    add     rdx, rax
    pop     rax
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
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     .slow
    lea     rdx, [rdi + PREP_peek]         ; (peeked already)
    xor     eax, eax
    ret
.slow:
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

    ; a slot to read it into (it is copied to PREP_peek)
    call    prep_token_slot
    mov     r12, rdx
    
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_internal_next
    test    rax, rax
    jnz     .error

    
    ; Success - token in r12. Making it peeked a token after it (the "%,"
    ; of prep_function looks past itself): that one queues behind it.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .peek_put
    lea     rdi, [rel putback_next]
    lea     rsi, [rbx + PREP_peek]
    copy_token
    mov     byte [rel has_putback_next], TRUE
.peek_put:
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

; the rest is in src/frontend/preproc/macro/, in this order:
%include "src/frontend/preproc/macro/tokens.inc"
%include "src/frontend/preproc/macro/expand.inc"
%include "src/frontend/preproc/macro/directives.inc"
%include "src/frontend/preproc/macro/tables.inc"
%include "src/frontend/preproc/macro/cond.inc"
%include "src/frontend/preproc/macro/contexts.inc"
%include "src/frontend/preproc/macro/interp.inc"
%include "src/frontend/preproc/macro/assign.inc"
%include "src/frontend/preproc/macro/tests.inc"
%include "src/frontend/preproc/macro/functions.inc"
%include "src/frontend/preproc/macro/files.inc"
%include "src/frontend/preproc/macro/define.inc"
%include "src/frontend/preproc/macro/cond_if.inc"
%include "src/frontend/preproc/macro/macro_def.inc"
%include "src/frontend/preproc/macro/rep_state.inc"
