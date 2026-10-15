;
; ============================================
; File     : frontend/parser/gas_macro.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ============================================================================
; GNU AS MACROS, REPETITIONS AND CONDITIONALS
; ============================================================================
; GNU as's text macros, beside NASM's %macro:
;
;   .macro NAME [P1[=DEFAULT|:req|:vararg][,] P2 ...]  ...  .endm
;   NAME A1, A2 ... / NAME P2=A2 ...    a call: \P1 \P2 in the body are the
;                                 arguments' text, \@ the count of macros
;                                 run before, \() nothing (\P\()x)
;   .exitm, .purgem NAME
;   .rept N ... .endr             N copies
;   .irp S, V1, V2 ... .endr      one copy for each V, \S that V
;   .irpc S, CHARS ... .endr      one copy for each character
;   .if E (.ifne) .ifeq .ifgt .ifge .iflt .ifle, .ifdef / .ifndef S,
;   .ifb / .ifnb TEXT, .ifc / .ifnc A, B, .ifeqs / .ifnes "A", "B",
;   .elseif E, .else, .endif
;
; A body is the raw source text between its line and its .endm / .endr
; (nested ones counted), copied when it is defined; a call or a repetition
; puts its copies, arguments in place, in front of the rest of the source
; (prep_push_buffer), each after a %line naming the body's own line - an
; error in it points there. Raw text is only there when the tokens come
; from a source buffer: not inside a NASM macro or %rep (EXIT_GAS_RAW).
; A conditional's false part is read as tokens and dropped, line by line,
; up to its .else / .elseif / .endif.

extern  preprocessor_peek_token
extern  preprocessor_next_token
extern  preprocessor_putback_token
extern  prep_push_buffer
extern  parser_evaluate_expression
extern  parser_gas_name
extern  symbol_find
extern  arena_alloc
extern  mem_reserve
extern  str_len
extern  error_set_subject
extern  error_loc_file, error_loc_line
extern  has_putback_next

%define GM_HASH      256
%define GM_MAXP      64             ; parameters of one macro
%define GM_MAXA      1024           ; arguments / values of one call
%define GM_MAXF      1024           ; expansions in progress (nested)
%define GM_MAXC      1024           ; conditionals open
%define GM_BUF_CAP   (1 << 26)      ; one expansion's text

; a macro
%define MAC_next     0
%define MAC_name     8              ; lower case, NUL-terminated
%define MAC_nparams  16
%define MAC_params   24             ; PARAM array
%define MAC_body     32
%define MAC_blen     40
%define MAC_file     48
%define MAC_line     56             ; its body's first line
%define MAC_SIZE     64
; a parameter
%define P_name       0              ; NUL-terminated
%define P_nlen       8
%define P_flags      16             ; 1 :req, 2 :vararg
%define P_def        24
%define P_dlen       32
%define P_SIZE       40
%define PF_REQ       1
%define PF_VARARG    2
; an expansion in progress
%define F_lexer      0
%define F_cond       8
%define F_type       12             ; 1 macro, 2 repetition
%define F_SIZE       16

[SECTION .rodata]
w_macro:    db ".macro", 0
w_endm:     db ".endm", 0
w_rept:     db ".rept", 0
w_irp:      db ".irp", 0
w_irpc:     db ".irpc", 0
w_endr:     db ".endr", 0
w_endif:    db ".endif", 0
w_else:     db ".else", 0
w_elseif:   db ".elseif", 0
w_exitm:    db ".exitm", 0
w_req:      db "req", 0
w_vararg:   db "vararg", 0
s_line:     db "%line ", 0
s_line_q:   db ' "', 0

[SECTION .bss]
alignb 8
global gm_defined
gm_defined:     resq 1              ; macros defined (0: no call to look for)
gm_counter:     resq 1              ; \@
gm_table:       resq GM_HASH
gm_buf:         resq 1              ; the expansion being built
gm_len:         resq 1
gm_over:        resb 1              ; it did not fit
alignb 8
gm_frames:      resb GM_MAXF * F_SIZE
gm_frames_n:    resq 1
gm_cond_n:      resq 1
gm_cond_file:   resq GM_MAXC
gm_cond_line:   resd GM_MAXC
gm_ptmp:        resb GM_MAXP * P_SIZE   ; a definition's parameters, read
gm_vals:        resq GM_MAXP * 2        ; a call's values: text, length
gm_vset:        resb GM_MAXP
alignb 8
gm_args_s:      resq GM_MAXA            ; split text: each piece's start ...
gm_args_l:      resq GM_MAXA            ; ... and length
gm_args_n:      resq 1
gm_one:         resb P_SIZE             ; .irp's parameter
alignb 8
gm_one_val:     resq 2
gm_word:        resb 64                 ; a word, for a message / a compare

[SECTION .text]

; ============================================================================
; RAW TEXT
; ============================================================================

; gm_lexer: the lexer the tokens come from, when its raw text is theirs
; (no NASM macro or %rep being expanded, nothing handed back)
; Input rbx = PrepState. Output rax = the lexer, or 0
gm_lexer:
    mov     rax, [rbx + PREP_ctx]
    cmp     qword [rax + ASMCTX_mac_exp], 0
    jne     .no
    cmp     byte [rel has_putback_next], 0
    jne     .no
    mov     rax, [rbx + PREP_lexer]
    test    rax, rax
    jz      .no
    cmp     byte [rax + LEXER_has_peek], 0
    jne     .no
    ret
.no:
    xor     eax, eax
    ret

; gm_rest: the rest of the line, raw, from the token peeked, and the line
; given up to its newline (the lexer there, the peeked token dropped); a
; ";" comment and trailing blanks cut
; Input rbx = PrepState. Output rax = OK or error, rsi = text, rcx = length
gm_rest:
    push    r12
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    call    gm_lexer
    test    rax, rax
    jz      .raw
    mov     r8, rax
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .empty
    cmp     eax, TOK_EOF
    je      .empty
    cmp     eax, TOK_COMMENT
    je      .empty
    mov     rax, [r12 + TOKEN_file]
    cmp     rax, [r8 + LEXER_file]
    jne     .raw
    mov     eax, [r12 + TOKEN_offset]
    mov     rsi, [r8 + LEXER_buf]
    add     rsi, rax
    cmp     rsi, [r8 + LEXER_end]
    jae     .raw
    mov     rdi, rsi
.scan:
    cmp     rdi, [r8 + LEXER_end]
    jae     .eol
    cmp     byte [rdi], 10
    je      .eol
    inc     rdi
    jmp     .scan
.eol:
    mov     [r8 + LEXER_pos], rdi
    mov     byte [rbx + PREP_has_peek], FALSE
    mov     rcx, rdi
    sub     rcx, rsi
    call    gm_cut
    xor     eax, eax
    jmp     .ret
.empty:
    mov     rsi, [r8 + LEXER_pos]
    xor     ecx, ecx
    xor     eax, eax
    jmp     .ret
.raw:
    mov     eax, EXIT_GAS_RAW
.ret:
    pop     r12
    ret

; gm_cut: rsi/rcx cut at a ";" outside quotes, then its trailing blanks
; (and a \r); leading blanks skipped
gm_cut:
    xor     edx, edx                       ; the quote open, or 0
    xor     eax, eax
.c_next:
    cmp     rax, rcx
    jae     .c_trim
    movzx   r9d, byte [rsi + rax]
    test    edx, edx
    jz      .c_out
    cmp     r9d, edx
    jne     .c_step
    xor     edx, edx
    jmp     .c_step
.c_out:
    cmp     r9d, ';'
    je      .c_cut
    cmp     r9d, '"'
    je      .c_open
    cmp     r9d, "'"
    je      .c_open
    cmp     r9d, '`'
    jne     .c_step
.c_open:
    mov     edx, r9d
.c_step:
    inc     rax
    jmp     .c_next
.c_cut:
    mov     rcx, rax
.c_trim:
    test    rcx, rcx
    jz      .c_lead
    movzx   eax, byte [rsi + rcx - 1]
    cmp     eax, ' '
    je      .c_drop
    cmp     eax, 9
    je      .c_drop
    cmp     eax, 13
    jne     .c_lead
.c_drop:
    dec     rcx
    jmp     .c_trim
.c_lead:
    test    rcx, rcx
    jz      .c_ret
    movzx   eax, byte [rsi]
    cmp     eax, ' '
    je      .c_skip
    cmp     eax, 9
    jne     .c_ret
.c_skip:
    inc     rsi
    dec     rcx
    jmp     .c_lead
.c_ret:
    ret

; gm_body: the raw lines after a directive's line up to its .endm / .endr
; (nested ones counted), given up as read: the lexer at the end line's
; newline, its line number that line's
; Input rbx = PrepState (the directive's operands read), esi = 0: .macro,
;       1: .rept / .irp / .irpc
; Output rax = OK or error, rsi = body, rcx = length, rdx = file, r8d = the
;       body's first line
gm_body:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15d, esi
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    jne     .junk
    call    gm_lexer
    test    rax, rax
    jz      .raw
    mov     r12, rax
    mov     r13, [r12 + LEXER_pos]         ; the body
    cmp     r13, [r12 + LEXER_buf]
    jbe     .raw
    cmp     byte [r13 - 1], 10
    jne     .raw
    xor     r14d, r14d                     ; nesting
    xor     r9d, r9d                       ; lines crossed
    mov     r10, r13                       ; a line's start
.line:
    cmp     r10, [r12 + LEXER_end]
    jae     .eof
    mov     rdi, r10
    call    gm_line_word                   ; gm_word: its first word
    lea     rdi, [rel gm_word]
    test    r15d, r15d
    jnz     .rept_words
    lea     rsi, [rel w_macro]
    call    gm_streq
    je      .deeper
    lea     rsi, [rel w_endm]
    call    gm_streq
    je      .end_word
    jmp     .next_line
.rept_words:
    lea     rsi, [rel w_rept]
    call    gm_streq
    je      .deeper
    lea     rsi, [rel w_irp]
    call    gm_streq
    je      .deeper
    lea     rsi, [rel w_irpc]
    call    gm_streq
    je      .deeper
    lea     rsi, [rel w_endr]
    call    gm_streq
    je      .end_word
    jmp     .next_line
.deeper:
    inc     r14d
    jmp     .next_line
.end_word:
    test    r14d, r14d
    jz      .found
    dec     r14d
.next_line:
    cmp     r10, [r12 + LEXER_end]
    jae     .eof
    cmp     byte [r10], 10
    je      .crossed
    inc     r10
    jmp     .next_line
.crossed:
    inc     r10
    inc     r9d
    jmp     .line
.found:
    ; the end line: the lexer at its newline
    mov     rcx, r10
    sub     rcx, r13                       ; the body's length
    mov     rdi, r10
.end_eol:
    cmp     rdi, [r12 + LEXER_end]
    jae     .end_set
    cmp     byte [rdi], 10
    je      .end_set
    inc     rdi
    jmp     .end_eol
.end_set:
    mov     [r12 + LEXER_pos], rdi
    mov     r8d, [r12 + LEXER_line]
    add     [r12 + LEXER_line], r9d
    mov     rsi, r13
    mov     rdx, [r12 + LEXER_file]
    xor     eax, eax
    jmp     .ret
.eof:
    ; no end: the rest of the file is the body (not read as code)
    mov     rax, [r12 + LEXER_end]
    mov     [r12 + LEXER_pos], rax
    add     [r12 + LEXER_line], r9d
    mov     eax, EXIT_GAS_NO_ENDM
    test    r15d, r15d
    jz      .ret
    mov     eax, EXIT_GAS_NO_ENDR
    jmp     .ret
.junk:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret
.raw:
    mov     eax, EXIT_GAS_RAW
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; gm_line_word: the first word of the line at rdi, in lower case, into
; gm_word ("" when there is none). Preserves r8-r15.
gm_line_word:
    lea     rsi, [rel gm_word]
    xor     ecx, ecx
.lw_blank:
    mov     rax, [r12 + LEXER_end]
    cmp     rdi, rax
    jae     .lw_done
    movzx   eax, byte [rdi]
    cmp     eax, ' '
    je      .lw_skip
    cmp     eax, 9
    jne     .lw_word
.lw_skip:
    inc     rdi
    jmp     .lw_blank
.lw_word:
    cmp     rdi, [r12 + LEXER_end]
    jae     .lw_done
    movzx   eax, byte [rdi]
    call    gm_ident_char
    jne     .lw_done
    cmp     ecx, 62
    jae     .lw_done
    cmp     eax, 'A'
    jb      .lw_put
    cmp     eax, 'Z'
    ja      .lw_put
    or      eax, 0x20
.lw_put:
    mov     [rsi + rcx], al
    inc     ecx
    inc     rdi
    jmp     .lw_word
.lw_done:
    mov     byte [rsi + rcx], 0
    ret

; gm_ident_char: is eax a name's character (letters, digits, _ . $)? ZF
gm_ident_char:
    cmp     eax, '_'
    je      .ic_yes
    cmp     eax, '.'
    je      .ic_yes
    cmp     eax, '$'
    je      .ic_yes
    cmp     eax, '0'
    jb      .ic_no
    cmp     eax, '9'
    jbe     .ic_yes
    push    rax
    or      eax, 0x20
    cmp     eax, 'a'
    jb      .ic_no_pop
    cmp     eax, 'z'
    ja      .ic_no_pop
    pop     rax
.ic_yes:
    cmp     eax, eax
    ret
.ic_no_pop:
    pop     rax
.ic_no:
    test    esp, esp                       ; (ZF clear)
    ret

; gm_streq: the NUL-terminated rdi and rsi the same? ZF. Preserves rdi.
gm_streq:
    push    rdi
.se_next:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .se_ret
    test    al, al
    jz      .se_ret
    inc     rdi
    inc     rsi
    jmp     .se_next
.se_ret:
    pop     rdi
    ret

; gm_memeq: rsi/rcx and rdi/rdx the same text? ZF
gm_memeq:
    cmp     rcx, rdx
    jne     .me_ret
    push    rsi
    push    rdi
    push    rcx
    repe cmpsb
    pop     rcx
    pop     rdi
    pop     rsi
.me_ret:
    ret

; ============================================================================
; THE EXPANSION BEING BUILT
; ============================================================================

; gm_begin: an empty one
gm_begin:
    mov     qword [rel gm_len], 0
    mov     byte [rel gm_over], 0
    cmp     qword [rel gm_buf], 0
    jne     .ret
    push    rsi
    mov     rsi, GM_BUF_CAP
    call    mem_reserve
    pop     rsi
    test    rax, rax
    jnz     .none
    mov     [rel gm_buf], rdx
.ret:
    xor     eax, eax
    ret
.none:
    mov     byte [rel gm_over], 1
    ret

; gm_put: rsi/rcx after it. Preserves all but rax.
gm_put:
    test    rcx, rcx
    jz      .p_ret
    push    rdi
    push    rsi
    push    rcx
    mov     rax, [rel gm_len]
    add     rax, rcx
    cmp     rax, GM_BUF_CAP
    ja      .p_over
    cmp     qword [rel gm_buf], 0
    je      .p_over
    mov     rdi, [rel gm_buf]
    add     rdi, [rel gm_len]
    mov     [rel gm_len], rax
    rep movsb
    jmp     .p_done
.p_over:
    mov     byte [rel gm_over], 1
.p_done:
    pop     rcx
    pop     rsi
    pop     rdi
.p_ret:
    ret

; gm_putc: the byte al. Preserves all.
gm_putc:
    push    rax
    push    rsi
    push    rcx
    sub     rsp, 8
    mov     [rsp], al
    mov     rsi, rsp
    mov     ecx, 1
    call    gm_put
    add     rsp, 8
    pop     rcx
    pop     rsi
    pop     rax
    ret

; gm_putz: the NUL-terminated rsi. Preserves all but rax.
gm_putz:
    push    rcx
    push    rdi
    mov     rdi, rsi
    call    str_len
    mov     rcx, rax
    call    gm_put
    pop     rdi
    pop     rcx
    ret

; gm_putnum: rax in decimal. Preserves all.
gm_putnum:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    sub     rsp, 32
    lea     rsi, [rsp + 31]
    xor     ecx, ecx
.n_digit:
    xor     edx, edx
    push    rcx
    mov     ecx, 10
    div     rcx
    pop     rcx
    add     dl, '0'
    mov     [rsi], dl
    dec     rsi
    inc     ecx
    test    rax, rax
    jnz     .n_digit
    inc     rsi
    call    gm_put
    add     rsp, 32
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; gm_putline: '%line LINE-1 "FILE"' and a newline: the next line is LINE
; of FILE. Input rdx = file, r8d = line.
gm_putline:
    push    rsi
    lea     rsi, [rel s_line]
    call    gm_putz
    mov     eax, r8d
    dec     eax
    call    gm_putnum
    lea     rsi, [rel s_line_q]
    call    gm_putz
    mov     rsi, rdx
    call    gm_putz
    mov     al, '"'
    call    gm_putc
    mov     al, 10
    call    gm_putc
    pop     rsi
    ret

; gm_subst: the text rsi/rcx with \NAME (rdx = the PARAM array, r8 = how
; many, r9 = their values: text, length), \@ (gm_counter) and \() worked
; out
gm_subst:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi
    lea     r13, [rsi + rcx]               ; the end
    mov     r14, rdx
    mov     r15, r9
    mov     rbx, r8
.s_next:
    ; the run up to a backslash
    mov     rsi, r12
.s_run:
    cmp     r12, r13
    jae     .s_flush
    cmp     byte [r12], '\'
    je      .s_flush
    inc     r12
    jmp     .s_run
.s_flush:
    mov     rcx, r12
    sub     rcx, rsi
    call    gm_put
    cmp     r12, r13
    jae     .s_done
    ; a backslash: what follows
    lea     rax, [r12 + 1]
    cmp     rax, r13
    jae     .s_lone
    movzx   eax, byte [r12 + 1]
    cmp     eax, '@'
    je      .s_count
    cmp     eax, '('
    jne     .s_name
    lea     rcx, [r12 + 2]
    cmp     rcx, r13
    jae     .s_lone
    cmp     byte [r12 + 2], ')'
    jne     .s_lone
    add     r12, 3                         ; \(): nothing
    jmp     .s_next
.s_count:
    mov     rax, [rel gm_counter]
    call    gm_putnum
    add     r12, 2
    jmp     .s_next
.s_name:
    call    gm_ident_char
    jne     .s_lone
    cmp     eax, '.'
    je      .s_lone                        ; (a name does not start so)
    lea     rsi, [r12 + 1]
    mov     rdi, rsi
.s_name_end:
    cmp     rdi, r13
    jae     .s_named
    movzx   eax, byte [rdi]
    call    gm_ident_char
    jne     .s_named
    cmp     eax, '.'
    je      .s_named                       ; (\x.y: \x then .y)
    inc     rdi
    jmp     .s_name_end
.s_named:
    mov     rcx, rdi
    sub     rcx, rsi                       ; the name: rsi/rcx
    xor     r8d, r8d
.s_param:
    cmp     r8, rbx
    jae     .s_lone
    imul    r9, r8, P_SIZE
    add     r9, r14
    push    rdi
    mov     rdi, [r9 + P_name]
    mov     rdx, [r9 + P_nlen]
    call    gm_memeq
    pop     rdi
    je      .s_value
    inc     r8
    jmp     .s_param
.s_value:
    mov     r12, rdi
    shl     r8, 4
    mov     rsi, [r15 + r8]
    mov     rcx, [r15 + r8 + 8]
    call    gm_put
    jmp     .s_next
.s_lone:
    mov     al, '\'
    call    gm_putc
    inc     r12
    jmp     .s_next
.s_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; gm_push: the expansion built, read next (as an %include of it), and
; noted as in progress. Input rbx = PrepState, rsi = the name messages
; give it (the body's file), edx = 1 macro, 2 repetition.
; Output rax = OK or error
gm_push:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13d, edx
    mov     eax, EXIT_OOM
    cmp     byte [rel gm_over], 0
    jne     .ret
    mov     rdi, rbx
    mov     rsi, [rel gm_buf]
    mov     rdx, [rel gm_len]
    mov     rcx, r12
    call    prep_push_buffer
    test    rax, rax
    jnz     .ret
    mov     rax, [rbx + PREP_lexer]
    mov     byte [rax + LEXER_nolist], 1   ; (listed as the calling line)
    mov     rax, [rel gm_frames_n]
    cmp     rax, GM_MAXF
    jae     .deep
    imul    rax, rax, F_SIZE
    lea     rcx, [rel gm_frames]
    add     rcx, rax
    mov     rax, [rbx + PREP_lexer]
    mov     [rcx + F_lexer], rax
    mov     eax, [rel gm_cond_n]
    mov     [rcx + F_cond], eax
    mov     [rcx + F_type], r13d
    inc     qword [rel gm_frames_n]
    xor     eax, eax
    jmp     .ret
.deep:
    mov     eax, EXIT_MACRO_RECURSION
.ret:
    pop     r13
    pop     r12
    ret

; gm_prune: the expansions no longer being read dropped (their lexer is
; not the current one nor one an %include waits on)
gm_prune:
.pr_top:
    mov     rax, [rel gm_frames_n]
    test    rax, rax
    jz      .pr_ret
    dec     rax
    imul    rax, rax, F_SIZE
    lea     rcx, [rel gm_frames]
    mov     rdx, [rcx + rax + F_lexer]
    cmp     rdx, [rbx + PREP_lexer]
    je      .pr_ret
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_inc_ctx]
.pr_chain:
    test    rax, rax
    jz      .pr_drop
    cmp     rdx, [rax + INCLUDECTX_lexer]
    je      .pr_ret
    mov     rax, [rax + INCLUDECTX_parent]
    jmp     .pr_chain
.pr_drop:
    dec     qword [rel gm_frames_n]
    jmp     .pr_top
.pr_ret:
    ret

; gm_arena_copy: rsi/rcx copied into the arena, NUL-terminated (lower
; case when edx is 1). Output rax = OK or error, rdx = the copy
gm_arena_copy:
    push    r12
    push    r13
    push    r14
    mov     r12, rsi
    mov     r13, rcx
    mov     r14d, edx
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r13 + 1]
    call    arena_alloc
    test    rax, rax
    jnz     .ac_ret
    xor     ecx, ecx
.ac_byte:
    cmp     rcx, r13
    jae     .ac_end
    movzx   eax, byte [r12 + rcx]
    test    r14d, r14d
    jz      .ac_put
    cmp     eax, 'A'
    jb      .ac_put
    cmp     eax, 'Z'
    ja      .ac_put
    or      eax, 0x20
.ac_put:
    mov     [rdx + rcx], al
    inc     rcx
    jmp     .ac_byte
.ac_end:
    mov     byte [rdx + rcx], 0
    xor     eax, eax
.ac_ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; gm_hash: the bucket of the name rsi/rcx (any case): rax = its slot
gm_hash:
    mov     eax, 2166136261
    xor     edx, edx
.h_byte:
    cmp     rdx, rcx
    jae     .h_done
    movzx   r8d, byte [rsi + rdx]
    cmp     r8d, 'A'
    jb      .h_mix
    cmp     r8d, 'Z'
    ja      .h_mix
    or      r8d, 0x20
.h_mix:
    xor     eax, r8d
    imul    eax, eax, 16777619
    inc     rdx
    jmp     .h_byte
.h_done:
    and     eax, GM_HASH - 1
    lea     rdx, [rel gm_table]
    lea     rax, [rdx + rax * 8]
    ret

; gm_find: the macro named rsi/rcx (any case): rax = it or 0, rdx = the
; slot that points at it
gm_find:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rcx
    call    gm_hash
    mov     rdx, rax                       ; the slot
.f_next:
    mov     rax, [rdx]
    test    rax, rax
    jz      .f_ret
    mov     rdi, [rax + MAC_name]
    xor     ecx, ecx
.f_cmp:
    cmp     rcx, r13
    jae     .f_end
    movzx   r8d, byte [r12 + rcx]
    cmp     r8d, 'A'
    jb      .f_low
    cmp     r8d, 'Z'
    ja      .f_low
    or      r8d, 0x20
.f_low:
    cmp     r8b, [rdi + rcx]
    jne     .f_other
    inc     rcx
    jmp     .f_cmp
.f_end:
    cmp     byte [rdi + rcx], 0
    je      .f_ret
.f_other:
    lea     rdx, [rax + MAC_next]
    jmp     .f_next
.f_ret:
    pop     r13
    pop     r12
    ret

; gm_name_at: a name at rsi (up to rcx bytes): rax = its length (0: none)
gm_name_at:
    xor     edx, edx
.na_next:
    cmp     rdx, rcx
    jae     .na_ret
    movzx   eax, byte [rsi + rdx]
    call    gm_ident_char
    jne     .na_ret
    inc     rdx
    jmp     .na_next
.na_ret:
    mov     rax, rdx
    ret

; gm_blanks: rsi/rcx past blanks (and one comma when edx is 1)
gm_blanks:
.b_next:
    test    rcx, rcx
    jz      .b_ret
    movzx   eax, byte [rsi]
    cmp     eax, ' '
    je      .b_skip
    cmp     eax, 9
    je      .b_skip
    cmp     eax, ','
    jne     .b_ret
    test    edx, edx
    jz      .b_ret
    xor     edx, edx
.b_skip:
    inc     rsi
    dec     rcx
    jmp     .b_next
.b_ret:
    ret

; gm_split: the text rsi/rcx in pieces at its commas outside quotes and
; brackets - or, with none and edx = 1, at its blanks - each without the
; blanks around it, into gm_args_s / gm_args_l / gm_args_n
gm_split:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     qword [rel gm_args_n], 0
    mov     r15d, edx                      ; (gm_cut takes edx)
    call    gm_cut                         ; (the blanks around it)
    test    rcx, rcx
    jz      .sp_ret
    mov     r12, rsi
    lea     r13, [rsi + rcx]
    ; a comma at the top level?
    test    r15d, r15d
    mov     r15d, ','
    jz      .sp_go
    mov     rdi, r12
    call    gm_top_scan
    test    eax, eax
    jnz     .sp_go
    mov     r15d, ' '                      ; (blanks)
.sp_go:
    mov     r14, r12                       ; a piece's start
    mov     rdi, r12
.sp_piece:
    ; to the next separator at the top level
    xor     r8d, r8d                       ; the quote open
    xor     r9d, r9d                       ; brackets
.sp_char:
    cmp     rdi, r13
    jae     .sp_end
    movzx   eax, byte [rdi]
    test    r8d, r8d
    jz      .sp_open
    cmp     eax, r8d
    jne     .sp_step
    xor     r8d, r8d
    jmp     .sp_step
.sp_open:
    cmp     eax, '"'
    je      .sp_quote
    cmp     eax, "'"
    je      .sp_quote
    cmp     eax, '('
    je      .sp_in
    cmp     eax, '['
    je      .sp_in
    cmp     eax, ')'
    je      .sp_out
    cmp     eax, ']'
    je      .sp_out
    test    r9d, r9d
    jnz     .sp_step
    cmp     r15d, ','
    jne     .sp_blank
    cmp     eax, ','
    je      .sp_end
    jmp     .sp_step
.sp_blank:
    cmp     eax, ' '
    je      .sp_end
    cmp     eax, 9
    je      .sp_end
    jmp     .sp_step
.sp_quote:
    mov     r8d, eax
    jmp     .sp_step
.sp_in:
    inc     r9d
    jmp     .sp_step
.sp_out:
    test    r9d, r9d
    jz      .sp_step
    dec     r9d
.sp_step:
    inc     rdi
    jmp     .sp_char
.sp_end:
    ; the piece r14 .. rdi, without its blanks
    mov     rax, [rel gm_args_n]
    cmp     rax, GM_MAXA
    jae     .sp_ret
    mov     rsi, r14
    mov     rcx, rdi
    sub     rcx, r14
    push    rdi
    call    gm_cut
    pop     rdi
    mov     rax, [rel gm_args_n]
    lea     rdx, [rel gm_args_s]
    mov     [rdx + rax * 8], rsi
    lea     rdx, [rel gm_args_l]
    mov     [rdx + rax * 8], rcx
    inc     qword [rel gm_args_n]
    cmp     rdi, r13
    jae     .sp_ret
    inc     rdi                            ; past the separator
    cmp     r15d, ' '
    jne     .sp_next
.sp_more_blanks:
    cmp     rdi, r13
    jae     .sp_ret
    cmp     byte [rdi], ' '
    je      .sp_blank_skip
    cmp     byte [rdi], 9
    jne     .sp_next
.sp_blank_skip:
    inc     rdi
    jmp     .sp_more_blanks
.sp_next:
    mov     r14, rdi
    jmp     .sp_piece
.sp_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; gm_top_scan: a comma outside quotes and brackets in rdi .. r13? eax = 1
gm_top_scan:
    xor     r8d, r8d
    xor     r9d, r9d
.ts_char:
    cmp     rdi, r13
    jae     .ts_no
    movzx   eax, byte [rdi]
    inc     rdi
    test    r8d, r8d
    jz      .ts_open
    cmp     eax, r8d
    jne     .ts_char
    xor     r8d, r8d
    jmp     .ts_char
.ts_open:
    cmp     eax, '"'
    je      .ts_quote
    cmp     eax, "'"
    je      .ts_quote
    cmp     eax, '('
    je      .ts_in
    cmp     eax, '['
    je      .ts_in
    cmp     eax, ')'
    je      .ts_out
    cmp     eax, ']'
    je      .ts_out
    cmp     eax, ','
    jne     .ts_char
    test    r9d, r9d
    jnz     .ts_char
    mov     eax, 1
    ret
.ts_quote:
    mov     r8d, eax
    jmp     .ts_char
.ts_in:
    inc     r9d
    jmp     .ts_char
.ts_out:
    test    r9d, r9d
    jz      .ts_char
    dec     r9d
    jmp     .ts_char
.ts_no:
    xor     eax, eax
    ret

; gm_subject: rsi/rcx (at most 63 bytes) as the subject of the error to come
gm_subject:
    lea     rdi, [rel gm_word]
    cmp     rcx, 63
    jbe     .sj_copy
    mov     ecx, 63
.sj_copy:
    push    rdi
    rep movsb
    mov     byte [rdi], 0
    pop     rdi
    jmp     error_set_subject

; ============================================================================
; .macro / a call / .purgem / .exitm
; ============================================================================

; ---- gas_macro_define ---------------------
;
; gas_macro_define
; ".macro NAME P1, P2=D, P3:req, P4:vararg" (blanks or commas between
; them) and its body, to the .endm.
; Input    : rdi = PrepState (the operands next)
; Output   : rax = OK or an error
;
global gas_macro_define
gas_macro_define:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    call    gm_rest
    test    rax, rax
    jnz     .ret
    mov     r12, rsi                       ; the operands
    mov     r13, rcx
    call    gm_name_at
    test    rax, rax
    jz      .bad
    mov     r14, rax                       ; the name: r12 / r14
    lea     rsi, [r12 + r14]
    mov     rcx, r13
    sub     rcx, r14
    xor     r15d, r15d                     ; parameters
.param:
    mov     edx, 1
    call    gm_blanks
    test    rcx, rcx
    jz      .params_done
    cmp     r15, GM_MAXP
    jae     .bad
    push    rsi
    push    rcx
    call    gm_name_at
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .bad
    imul    rdi, r15, P_SIZE
    lea     r8, [rel gm_ptmp]
    add     r8, rdi
    mov     [r8 + P_name], rsi
    mov     [r8 + P_nlen], rax
    mov     qword [r8 + P_flags], 0
    mov     qword [r8 + P_def], 0
    mov     qword [r8 + P_dlen], 0
    add     rsi, rax
    sub     rcx, rax
    inc     r15
    ; :req / :vararg
    test    rcx, rcx
    jz      .params_done
    cmp     byte [rsi], ':'
    jne     .no_qual
    inc     rsi
    dec     rcx
    push    rsi
    push    rcx
    call    gm_name_at
    pop     rcx
    pop     rsi
    mov     rdx, rax
    push    rsi
    push    rcx
    mov     rcx, rdx
    lea     rdi, [rel w_req]
    mov     edx, 3
    call    gm_memeq
    pop     rcx
    pop     rsi
    jne     .qual_vararg
    or      qword [r8 + P_flags], PF_REQ
    add     rsi, 3
    sub     rcx, 3
    jmp     .no_qual
.qual_vararg:
    push    rsi
    push    rcx
    push    rax
    mov     rcx, rax
    lea     rdi, [rel w_vararg]
    mov     edx, 6
    call    gm_memeq
    pop     rax
    pop     rcx
    pop     rsi
    jne     .bad
    or      qword [r8 + P_flags], PF_VARARG
    add     rsi, 6
    sub     rcx, 6
.no_qual:
    ; =DEFAULT
    xor     edx, edx
    call    gm_blanks
    test    rcx, rcx
    jz      .params_done
    cmp     byte [rsi], '='
    jne     .param
    inc     rsi
    dec     rcx
    xor     edx, edx
    call    gm_blanks
    mov     [r8 + P_def], rsi
    xor     eax, eax
    test    rcx, rcx
    jz      .def_end
    cmp     byte [rsi], '"'
    jne     .def_word
    ; "..." whole
    inc     eax
.def_quoted:
    cmp     rax, rcx
    jae     .def_end
    cmp     byte [rsi + rax], '"'
    je      .def_close
    inc     rax
    jmp     .def_quoted
.def_close:
    inc     rax
    jmp     .def_end
.def_word:
    cmp     rax, rcx
    jae     .def_end
    movzx   edx, byte [rsi + rax]
    cmp     edx, ','
    je      .def_end
    cmp     edx, ' '
    je      .def_end
    cmp     edx, 9
    je      .def_end
    inc     rax
    jmp     .def_word
.def_end:
    mov     [r8 + P_dlen], rax
    add     rsi, rax
    sub     rcx, rax
    jmp     .param
.params_done:
    ; the body (the lexer at the line's end: its newline next)
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    xor     esi, esi
    call    gm_body
    test    rax, rax
    jz      .have_body
    cmp     rax, EXIT_GAS_NO_ENDM
    jne     .ret
    push    rax
    mov     rsi, r12
    mov     rcx, r14
    call    gm_subject
    pop     rax
    jmp     .ret
.have_body:
    ; kept: the macro, its parameters, their defaults, its body - copied
    push    rsi
    push    rcx
    push    rdx
    push    r8
    mov     rdi, [rbx + PREP_arena]
    mov     esi, MAC_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .drop4
    mov     r13, rdx                       ; the macro
    pop     r8
    pop     rdx
    mov     [r13 + MAC_file], rdx
    mov     [r13 + MAC_line], r8d
    pop     rcx
    pop     rsi
    mov     [r13 + MAC_blen], rcx
    xor     edx, edx
    call    gm_arena_copy
    test    rax, rax
    jnz     .ret
    mov     [r13 + MAC_body], rdx
    mov     rsi, r12
    mov     rcx, r14
    mov     edx, 1
    call    gm_arena_copy
    test    rax, rax
    jnz     .ret
    mov     [r13 + MAC_name], rdx
    mov     [r13 + MAC_nparams], r15
    mov     rdi, [rbx + PREP_arena]
    imul    rsi, r15, P_SIZE
    add     rsi, 8
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [r13 + MAC_params], rdx
    xor     r12d, r12d
.copy_param:
    cmp     r12, r15
    jae     .insert
    imul    r14, r12, P_SIZE
    lea     rax, [rel gm_ptmp]
    add     r14, rax                       ; read
    mov     rsi, [r14 + P_name]
    mov     rcx, [r14 + P_nlen]
    xor     edx, edx
    call    gm_arena_copy
    test    rax, rax
    jnz     .ret
    imul    rdi, r12, P_SIZE
    add     rdi, [r13 + MAC_params]        ; kept
    mov     [rdi + P_name], rdx
    mov     rax, [r14 + P_nlen]
    mov     [rdi + P_nlen], rax
    mov     rax, [r14 + P_flags]
    mov     [rdi + P_flags], rax
    mov     rax, [r14 + P_dlen]
    mov     [rdi + P_dlen], rax
    mov     qword [rdi + P_def], 0
    test    rax, rax
    jz      .param_kept
    push    rdi
    mov     rsi, [r14 + P_def]
    mov     rcx, rax
    xor     edx, edx
    call    gm_arena_copy
    pop     rdi
    test    rax, rax
    jnz     .ret
    mov     [rdi + P_def], rdx
.param_kept:
    inc     r12
    jmp     .copy_param
.insert:
    ; in its bucket (one of the same name is replaced)
    mov     rdi, [r13 + MAC_name]
    call    str_len
    mov     rcx, rax
    mov     rsi, [r13 + MAC_name]
    call    gm_find
    test    rax, rax
    jz      .new
    mov     rcx, [rax + MAC_next]
    mov     [r13 + MAC_next], rcx
    mov     [rdx], r13
    xor     eax, eax
    jmp     .ret
.new:
    mov     rsi, [r13 + MAC_name]
    mov     rdi, rsi
    call    str_len
    mov     rcx, rax
    call    gm_hash
    mov     rcx, [rax]
    mov     [r13 + MAC_next], rcx
    mov     [rax], r13
    inc     qword [rel gm_defined]
    xor     eax, eax
    jmp     .ret
.drop4:
    add     rsp, 32
    jmp     .ret
.bad:
    ; the body still taken, not read as code
    mov     rdi, rbx
    call    preprocessor_peek_token
    xor     esi, esi
    call    gm_body
    mov     eax, EXIT_GAS_PARAMS
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- gas_macro_call -----------------------
;
; gas_macro_call
; A statement word that may name a GNU macro: its call, the arguments the
; rest of the line.
; Input    : rdi = PrepState (the token after the word peeked), rsi = the
;            word
; Output   : eax = 0: no macro of that name; 1: called, rdx = OK or error
;
global gas_macro_call
gas_macro_call:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rsi
    call    str_len
    mov     rcx, rax
    mov     rsi, r12
    call    gm_find
    test    rax, rax
    jz      .none
    mov     r15, rax                       ; the macro
    call    gm_rest
    test    rax, rax
    jnz     .done_rax
    ; the values: the defaults, then the arguments
    mov     r13, rsi
    mov     r14, rcx
    xor     ecx, ecx
.defaults:
    cmp     rcx, [r15 + MAC_nparams]
    jae     .split
    imul    rax, rcx, P_SIZE
    add     rax, [r15 + MAC_params]
    lea     rdx, [rel gm_vals]
    mov     r8, rcx
    shl     r8, 4
    mov     r9, [rax + P_def]
    mov     [rdx + r8], r9
    mov     r9, [rax + P_dlen]
    mov     [rdx + r8 + 8], r9
    lea     rdx, [rel gm_vset]
    mov     byte [rdx + rcx], 0
    inc     rcx
    jmp     .defaults
.split:
    mov     rsi, r13
    mov     rcx, r14
    xor     edx, edx
    cmp     qword [r15 + MAC_nparams], 2
    jb      .split_go
    mov     edx, 1
.split_go:
    call    gm_split
    xor     r12d, r12d                     ; the argument
    xor     r13d, r13d                     ; the next positional parameter
.arg:
    cmp     r12, [rel gm_args_n]
    jae     .bound
    lea     rax, [rel gm_args_s]
    mov     rsi, [rax + r12 * 8]
    lea     rax, [rel gm_args_l]
    mov     rcx, [rax + r12 * 8]
    ; NAME=VALUE
    push    rsi
    push    rcx
    call    gm_name_at
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .positional
    mov     r8, rax
    lea     rdx, [rsi + r8]
.named_blank:
    lea     r9, [rsi + rcx]
    cmp     rdx, r9
    jae     .positional
    cmp     byte [rdx], ' '
    jne     .named_eq
    inc     rdx
    jmp     .named_blank
.named_eq:
    cmp     byte [rdx], '='
    jne     .positional
    lea     r9, [rsi + rcx]
    lea     rax, [rdx + 1]
    cmp     rax, r9
    jae     .named_find
    cmp     byte [rdx + 1], '='
    je      .positional                    ; ("a==b")
.named_find:
    ; the parameter of that name
    push    rdx
    xor     r10d, r10d
.named_param:
    cmp     r10, [r15 + MAC_nparams]
    jae     .named_none
    imul    rax, r10, P_SIZE
    add     rax, [r15 + MAC_params]
    push    rsi
    push    rcx
    mov     rcx, r8
    mov     rdi, [rax + P_name]
    mov     rdx, [rax + P_nlen]
    call    gm_memeq
    pop     rcx
    pop     rsi
    je      .named_hit
    inc     r10
    jmp     .named_param
.named_none:
    pop     rdx
    mov     rcx, r8
    call    gm_subject
    mov     eax, EXIT_GAS_ARG_NAME
    jmp     .done_rax
.named_hit:
    pop     rdx
    inc     rdx                            ; past '='
    lea     rcx, [rsi + rcx]
    sub     rcx, rdx
    mov     rsi, rdx
    call    gm_cut
    mov     rax, r10
    jmp     .store
.positional:
    cmp     r13, [r15 + MAC_nparams]
    jae     .too_many
    imul    rax, r13, P_SIZE
    add     rax, [r15 + MAC_params]
    test    qword [rax + P_flags], PF_VARARG
    jz      .positional_one
    ; :vararg: the rest of the line, from here
    lea     rcx, [r13 + r14]               ; (the text's end: r13 is reused)
    mov     rax, r13
    lea     rdx, [rel gm_args_s]
    mov     rsi, [rdx + r12 * 8]
    mov     rdx, [rel gm_args_n]
    dec     rdx
    lea     r8, [rel gm_args_s]
    mov     rcx, [r8 + rdx * 8]
    lea     r8, [rel gm_args_l]
    add     rcx, [r8 + rdx * 8]
    sub     rcx, rsi
    mov     r12, [rel gm_args_n]           ; (all taken)
    jmp     .store_pos
.positional_one:
    mov     rax, r13
.store_pos:
    inc     r13
.store:
    ; parameter rax: rsi / rcx ("..." given: its text, GNU's)
    call    gm_unquote_dq
    lea     rdx, [rel gm_vals]
    mov     r8, rax
    shl     r8, 4
    mov     [rdx + r8], rsi
    mov     [rdx + r8 + 8], rcx
    lea     rdx, [rel gm_vset]
    mov     byte [rdx + rax], 1
    inc     r12
    jmp     .arg
.too_many:
    mov     eax, EXIT_GAS_ARG_MANY
    jmp     .done_rax
.bound:
    ; :req ones given
    xor     ecx, ecx
.req:
    cmp     rcx, [r15 + MAC_nparams]
    jae     .expand
    imul    rax, rcx, P_SIZE
    add     rax, [r15 + MAC_params]
    test    qword [rax + P_flags], PF_REQ
    jz      .req_next
    mov     rdx, rcx
    shl     rdx, 4
    lea     r8, [rel gm_vals]
    cmp     qword [r8 + rdx + 8], 0
    jne     .req_next
    mov     rsi, [rax + P_name]
    mov     rcx, [rax + P_nlen]
    call    gm_subject
    mov     eax, EXIT_GAS_ARG_REQ
    jmp     .done_rax
.req_next:
    inc     rcx
    jmp     .req
.expand:
    call    gm_prune
    call    gm_begin
    mov     al, 10
    call    gm_putc
    mov     rdx, [r15 + MAC_file]
    mov     r8d, [r15 + MAC_line]
    call    gm_putline
    mov     rsi, [r15 + MAC_body]
    mov     rcx, [r15 + MAC_blen]
    mov     rdx, [r15 + MAC_params]
    mov     r8, [r15 + MAC_nparams]
    lea     r9, [rel gm_vals]
    call    gm_subst
    mov     al, 10
    call    gm_putc
    inc     qword [rel gm_counter]
    mov     rsi, [r15 + MAC_file]
    mov     edx, 1
    call    gm_push
.done_rax:
    mov     rdx, rax
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- gas_macro_purge ----------------------
;
; gas_macro_purge
; ".purgem NAME": the macro forgotten.
; Input    : rdi = PrepState
; Output   : rax = OK or an error
;
global gas_macro_purge
gas_macro_purge:
    push    rbx
    mov     rbx, rdi
    call    gm_rest
    test    rax, rax
    jnz     .ret
    push    rsi
    push    rcx
    call    gm_find
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .none
    mov     rcx, [rax + MAC_next]
    mov     [rdx], rcx
    dec     qword [rel gm_defined]
    xor     eax, eax
    jmp     .ret
.none:
    call    gm_subject
    mov     eax, EXIT_GAS_NO_MACRO
.ret:
    pop     rbx
    ret

; ---- gas_macro_exit -----------------------
;
; gas_macro_exit
; ".exitm": the macro being expanded ends here (and a .rept / .irp in it);
; its conditionals still open close with it.
; Input    : rdi = PrepState
; Output   : rax = OK or an error
;
global gas_macro_exit
gas_macro_exit:
    push    rbx
    mov     rbx, rdi
    call    gm_prune
.e_frame:
    mov     rax, [rel gm_frames_n]
    test    rax, rax
    jz      .e_stray
    dec     rax
    mov     [rel gm_frames_n], rax
    imul    rax, rax, F_SIZE
    lea     rcx, [rel gm_frames]
    add     rcx, rax
    mov     rdx, [rcx + F_lexer]
    mov     rax, [rdx + LEXER_end]
    mov     [rdx + LEXER_pos], rax
    cmp     dword [rcx + F_type], 1
    jne     .e_frame
    mov     eax, [rcx + F_cond]
    mov     [rel gm_cond_n], rax
    xor     eax, eax
    jmp     .e_ret
.e_stray:
    lea     rdi, [rel w_exitm]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
.e_ret:
    pop     rbx
    ret

; ============================================================================
; .rept / .irp / .irpc
; ============================================================================

; ---- gas_repeat ---------------------------
;
; gas_repeat
; ".rept N", ".irp S, V1, V2 ...", ".irpc S, CHARS" and the body to .endr.
; Input    : rdi = PrepState, esi = 0 .rept, 1 .irp, 2 .irpc
; Output   : rax = OK or an error
;
global gas_repeat
gas_repeat:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r15d, esi
    test    r15d, r15d
    jnz     .symbol
    ; .rept N
    call    gm_const
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    test    r12, r12
    jns     .body
    xor     r12d, r12d                     ; (negative: none, as GNU's)
    jmp     .body
.symbol:
    call    gm_rest
    test    rax, rax
    jnz     .ret
    push    rsi
    push    rcx
    call    gm_name_at
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .bad
    lea     rdx, [rel gm_one]
    mov     [rdx + P_name], rsi
    mov     [rdx + P_nlen], rax
    add     rsi, rax
    sub     rcx, rax
    mov     edx, 1
    call    gm_blanks
    mov     r13, rsi                       ; the values
    mov     r14, rcx
    mov     rdi, rbx
    call    preprocessor_peek_token        ; (the line's newline)
    test    rax, rax
    jnz     .ret
.body:
    mov     esi, 1
    call    gm_body
    test    rax, rax
    jnz     .no_end
    push    rsi                            ; the body: [rsp + 24]
    push    rcx                            ; [rsp + 16]
    push    rdx                            ; the file: [rsp + 8]
    push    r8                             ; the line: [rsp]
    call    gm_prune
    call    gm_begin
    mov     al, 10
    call    gm_putc
    test    r15d, r15d
    jnz     .values
.copy:
    test    r12, r12
    jz      .built
    mov     rdx, [rsp + 8]
    mov     r8d, [rsp]
    call    gm_putline
    mov     rsi, [rsp + 24]
    mov     rcx, [rsp + 16]
    call    gm_put
    dec     r12
    cmp     byte [rel gm_over], 0
    jne     .built
    jmp     .copy
.values:
    cmp     r15d, 2
    je      .chars
    mov     rsi, r13
    mov     rcx, r14
    mov     edx, 1
    call    gm_split
    xor     r12d, r12d
    cmp     qword [rel gm_args_n], 0
    jne     .value
    ; no values: once, S empty
    mov     qword [rel gm_one_val], 0
    mov     qword [rel gm_one_val + 8], 0
    call    .one
    jmp     .built
.value:
    cmp     r12, [rel gm_args_n]
    jae     .built
    lea     rax, [rel gm_args_s]
    mov     rax, [rax + r12 * 8]
    mov     [rel gm_one_val], rax
    lea     rax, [rel gm_args_l]
    mov     rax, [rax + r12 * 8]
    mov     [rel gm_one_val + 8], rax
    call    .one
    inc     r12
    jmp     .value
.chars:
    mov     rsi, r13
    mov     rcx, r14
    call    gm_cut
    mov     r13, rsi
    mov     r14, rcx
    xor     r12d, r12d
    test    r14, r14
    jnz     .char
    mov     qword [rel gm_one_val], 0
    mov     qword [rel gm_one_val + 8], 0
    call    .one
    jmp     .built
.char:
    cmp     r12, r14
    jae     .built
    lea     rax, [r13 + r12]
    mov     [rel gm_one_val], rax
    mov     qword [rel gm_one_val + 8], 1
    call    .one
    inc     r12
    jmp     .char
.built:
    mov     rsi, [rsp + 8]
    add     rsp, 32
    mov     edx, 2
    call    gm_push
    jmp     .ret
.no_end:
    cmp     rax, EXIT_GAS_NO_ENDR
    jne     .ret
    lea     rdi, [rel w_rept]
    cmp     r15d, 1
    jb      .no_end_named
    lea     rdi, [rel w_irp]
    je      .no_end_named
    lea     rdi, [rel w_irpc]
.no_end_named:
    push    rax
    call    error_set_subject
    pop     rax
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

; .one: a copy of the body with \S the value in gm_one_val (the body, its
; file and line on the caller's stack, under this call's return address)
.one:
    mov     rdx, [rsp + 16]
    mov     r8d, [rsp + 8]
    call    gm_putline
    mov     rsi, [rsp + 32]
    mov     rcx, [rsp + 24]
    lea     rdx, [rel gm_one]
    mov     r8d, 1
    lea     r9, [rel gm_one_val]
    call    gm_subst
    ret

; gm_const: an expression that is a number. Output rax = OK or error,
; rdx = it
gm_const:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .k_ret
    test    rcx, rcx
    jnz     .k_not
    test    r11, r11
    jz      .k_ret
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    jne     .k_not
    xor     eax, eax
.k_ret:
    ret
.k_not:
    mov     eax, EXIT_NOT_SIMPLE
    ret

; ============================================================================
; CONDITIONALS
; ============================================================================

; ---- gas_if -------------------------------
;
; gas_if
; .if and its kind: the part after it read, or dropped up to its .else /
; .elseif / .endif.
; Input    : rdi = PrepState, esi = 0 .if/.ifne, 1 .ifeq, 2 .ifgt, 3 .ifge,
;            4 .iflt, 5 .ifle, 6 .ifdef, 7 .ifndef, 8 .ifb, 9 .ifnb,
;            10 .ifc, 11 .ifnc, 12 .ifeqs, 13 .ifnes
; Output   : rax = OK or an error
;
global gas_if
gas_if:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12d, esi
    ; where it is (for "no .endif")
    mov     rax, [rel gm_cond_n]
    cmp     rax, GM_MAXC
    jae     .deep
    mov     rdx, [rel error_loc_file]
    lea     rcx, [rel gm_cond_file]
    mov     [rcx + rax * 8], rdx
    mov     edx, [rel error_loc_line]
    lea     rcx, [rel gm_cond_line]
    mov     [rcx + rax * 4], edx
    cmp     r12d, 6
    jb      .value
    cmp     r12d, 8
    jb      .defined
    cmp     r12d, 10
    jb      .blank
    ; .ifc / .ifeqs: two texts, as written (GNU's: 'a' is not a)
    call    gm_rest
    test    rax, rax
    jnz     .ret
    xor     edx, edx
    call    gm_split
    cmp     qword [rel gm_args_n], 2
    jne     .bad
    mov     rdi, [rel gm_args_s]
    mov     rdx, [rel gm_args_l]
    mov     rsi, [rel gm_args_s + 8]
    mov     rcx, [rel gm_args_l + 8]
    call    gm_memeq
    sete    al
    movzx   r13d, al
    mov     eax, r12d
    and     eax, 1                         ; .ifnc / .ifnes
    xor     r13d, eax
    jmp     .decided
.blank:
    call    gm_rest
    test    rax, rax
    jnz     .ret
    xor     r13d, r13d
    test    rcx, rcx
    setz    r13b
    cmp     r12d, 9
    jne     .decided
    xor     r13d, 1
    jmp     .decided
.defined:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    parser_gas_name
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    xor     r13d, r13d
    test    rax, rax
    jnz     .defined_known
    cmp     word [rdx + SYMBOL_section], 0
    je      .defined_known                 ; (named, not defined: extern)
    mov     r13d, 1
.defined_known:
    cmp     r12d, 7
    jne     .decided
    xor     r13d, 1
    jmp     .decided
.value:
    call    gm_const
    test    rax, rax
    jnz     .ret
    xor     r13d, r13d
    cmp     r12d, 1
    je      .eq
    cmp     r12d, 2
    je      .gt
    cmp     r12d, 3
    je      .ge
    cmp     r12d, 4
    je      .lt
    cmp     r12d, 5
    je      .le
    test    rdx, rdx
    setnz   r13b
    jmp     .decided
.eq:
    test    rdx, rdx
    setz    r13b
    jmp     .decided
.gt:
    test    rdx, rdx
    setg    r13b
    jmp     .decided
.ge:
    test    rdx, rdx
    setge   r13b
    jmp     .decided
.lt:
    test    rdx, rdx
    setl    r13b
    jmp     .decided
.le:
    test    rdx, rdx
    setle   r13b
.decided:
    inc     qword [rel gm_cond_n]
    test    r13d, r13d
    jnz     .ok
    xor     esi, esi
    call    gm_skip
    jmp     .ret
.ok:
    xor     eax, eax
    jmp     .ret
.deep:
    mov     eax, EXIT_COND_DEPTH
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; gm_unquote_dq: rsi/rcx without the double quotes around it. Preserves
; all but rsi, rcx.
gm_unquote_dq:
    cmp     rcx, 2
    jb      .dq_ret
    cmp     byte [rsi], '"'
    jne     .dq_ret
    cmp     byte [rsi + rcx - 1], '"'
    jne     .dq_ret
    inc     rsi
    sub     rcx, 2
.dq_ret:
    ret

; ---- gas_else / gas_endif -----------------
;
; gas_else
; ".else" / ".elseif E" reached in the part being read: the rest of the
; conditional dropped, to its .endif.
; Input    : rdi = PrepState, esi = 0 .else, 1 .elseif
; Output   : rax = OK or an error
;
global gas_else
gas_else:
    push    rbx
    mov     rbx, rdi
    cmp     qword [rel gm_cond_n], 0
    je      .stray
    mov     esi, 1
    call    gm_skip
    pop     rbx
    ret
.stray:
    lea     rdi, [rel w_else]
    test    esi, esi
    jz      .named
    lea     rdi, [rel w_elseif]
.named:
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     rbx
    ret

global gas_endif
gas_endif:
    cmp     qword [rel gm_cond_n], 0
    je      .stray
    dec     qword [rel gm_cond_n]
    xor     eax, eax
    ret
.stray:
    lea     rdi, [rel w_endif]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    ret

; gm_skip: the source dropped, line by line (as tokens), to the .endif of
; the conditional open - or, when esi is 0 (no part read yet), to its .else
; or a true .elseif, from where it is read. The line it stops at is read
; up to its newline.
; Input rbx = PrepState, esi = 0 / 1. Output rax = OK or an error
gm_skip:
    push    r12
    push    r13
    push    r14
    mov     r12d, esi
    xor     r13d, r13d                     ; nesting
    call    gm_drop_line                   ; (the rest of this line)
.k_line:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .k_ret
.k_tok:
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_EOF
    je      .k_eof
    cmp     eax, TOK_NEWLINE
    je      .k_line
    cmp     eax, TOK_LABEL
    je      .k_label
    cmp     eax, TOK_LOCAL_LABEL
    je      .k_label
    cmp     eax, TOK_IDENT
    jne     .k_other
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .k_other
    ; the word in lower case
    lea     rdi, [rel gm_word]
    xor     ecx, ecx
.k_lc:
    movzx   eax, byte [rsi + rcx]
    cmp     eax, 'A'
    jb      .k_lc_put
    cmp     eax, 'Z'
    ja      .k_lc_put
    or      eax, 0x20
.k_lc_put:
    mov     [rdi + rcx], al
    test    eax, eax
    jz      .k_word
    inc     ecx
    cmp     ecx, 62
    jb      .k_lc
    mov     byte [rdi + rcx], 0
.k_word:
    cmp     dword [rdi], '.if'             ; (.if\0)
    je      .k_open
    cmp     word [rdi], '.i'
    jne     .k_not_if
    cmp     byte [rdi + 2], 'f'
    je      .k_open                        ; .ifdef, .ifne ...
.k_not_if:
    lea     rsi, [rel w_endif]
    call    gm_streq
    je      .k_endif
    lea     rsi, [rel w_else]
    call    gm_streq
    je      .k_else
    lea     rsi, [rel w_elseif]
    call    gm_streq
    je      .k_elseif
.k_other:
    call    gm_drop_line
    jmp     .k_line
.k_label:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .k_ret
    jmp     .k_tok
.k_open:
    inc     r13d
    jmp     .k_other
.k_endif:
    test    r13d, r13d
    jz      .k_closed
    dec     r13d
    jmp     .k_other
.k_closed:
    dec     qword [rel gm_cond_n]
    jmp     .k_read
.k_else:
    test    r13d, r13d
    jnz     .k_other
    test    r12d, r12d
    jnz     .k_other
    jmp     .k_read
.k_elseif:
    test    r13d, r13d
    jnz     .k_other
    test    r12d, r12d
    jnz     .k_other
    call    gm_const
    test    rax, rax
    jnz     .k_ret
    test    rdx, rdx
    jz      .k_other
.k_read:
    call    gm_to_eol
    xor     eax, eax
    jmp     .k_ret
.k_eof:
    mov     rdi, rbx
    mov     rsi, rdx
    call    preprocessor_putback_token     ; (the end, for the parser)
    call    gm_open_loc
    mov     qword [rel gm_cond_n], 0       ; (reported here, not again)
    mov     eax, EXIT_GAS_NO_ENDIF
.k_ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; gm_drop_line: the tokens up to and with the newline (the end of the
; source handed back)
gm_drop_line:
.dl_next:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .dl_ret
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .dl_ret
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    jne     .dl_next
    mov     rdi, rbx
    mov     rsi, rdx
    call    preprocessor_putback_token
.dl_ret:
    ret

; gm_to_eol: the tokens up to the newline, which stays next
gm_to_eol:
.te_next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .te_ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .te_ret
    cmp     eax, TOK_EOF
    je      .te_ret
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .te_next
.te_ret:
    ret

; gm_open_loc: the error's place, the outermost conditional still open
gm_open_loc:
    mov     rax, [rel gm_cond_file]
    mov     [rel error_loc_file], rax
    mov     eax, [rel gm_cond_line]
    mov     [rel error_loc_line], eax
    ret

; ---- gas_macro_finish ---------------------
;
; gas_macro_finish
; The source read: a conditional still open is an error (where it opened).
; Output   : rax = OK or EXIT_GAS_NO_ENDIF
;
global gas_macro_finish
gas_macro_finish:
    xor     eax, eax
    cmp     qword [rel gm_cond_n], 0
    je      .ret
    call    gm_open_loc
    mov     eax, EXIT_GAS_NO_ENDIF
.ret:
    ret
