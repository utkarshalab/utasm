; ============================================================================
; File        : src/frontend/preproc/macro/rep_state.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : %rep, %defalias and aliases, preprocessor symbols, error lines; the preprocessor's state
; ============================================================================


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
    ; "%rep .nolist 4": its lines not listed (NASM's)
    xor     r12d, r12d
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .error
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .rep_count
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_rep_nolist]
    call    str_cmp_kw
    test    rax, rax
    jnz     .rep_count
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    mov     r12d, MACRO_FLAG_NOLIST
.rep_count:
    mov     rdi, rbx
    call    parser_evaluate_pp
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
    mov     [r15 + MACRO_flags], r12b
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

    ; "%rep 0": the body not at all (it was once); a negative count the
    ; same, with NASM's warning
    test    r14, r14
    jg      .rep_limit
    jz      .rep_none
    mov     edi, WC_PP_REP_NEGATIVE
    call    warn_begin
    lea     rsi, [rel s_rep_negative]
    call    warn_text
    lea     rdi, [rel rep_num]
    mov     byte [rdi], '-'
    inc     rdi
    mov     rsi, r14
    neg     rsi
    mov     edx, 10
    extern  int_to_str
    call    int_to_str
    lea     rsi, [rel rep_num]
    call    warn_text
    call    warn_end
.rep_none:
    xor     eax, eax
    jmp     .done
.rep_limit:
    ; more than --limit-rep (1000000): NASM's error, the body not repeated
    cmp     r14, [rel rep_limit]
    jbe     .rep_start
    lea     rdi, [rel rep_num]
    mov     rsi, r14
    mov     edx, 10
    call    int_to_str
    lea     rdi, [rel rep_num]
    call    str_len
    lea     rdi, [rel rep_num]
    add     rdi, rax
    lea     rsi, [rel s_rep_limit]
.rep_limit_text:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .rep_limit_text
    dec     rdi
    mov     rsi, [rel rep_limit]
    mov     edx, 10
    call    int_to_str
    lea     rdi, [rel rep_num]
    call    str_len
    lea     rdi, [rel rep_num]
    add     rdi, rax
    mov     word [rdi], ')'
    lea     rsi, [rel s_rep_count]
    call    prep_error_line
    lea     rsi, [rel rep_num]
    call    prep_error_more
    xor     eax, eax
    jmp     .done
.rep_start:
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
ml_pending00:  resq 1              ; "f proc": f, for the call's %00
ml_nocolon:    resb 1              ; that label had no colon (the listing)
alignb 8
relex_cap:     resq 1              ; prep_interp_relex: its array's room
ml_label:      resq 1              ; the line's first word (a label?)
relex_tok:     resb TOKEN_SIZE     ; ... the token just read
fn_out:        resq 1              ; prep_function: the result (it grows)
fn_n:          resq 1              ; ... how many tokens
fn_cap:        resq 1              ; ... room
fn_col:        resq 1              ; ... the next one's column
fn_tok:        resb TOKEN_SIZE     ; ... a token being made
fn_num_buf:    resb 96             ; ... a number's digits
fn_exact:      resb 1              ; fn_utoa: the digits asked for exactly (%num)
fn_prefix:     resb 1              ; ... 1: 0x before them
alignb 2
fn_radix:      resw 1              ; %=(x): the radix letter | 0x100 unsigned
cond_is_else:  resb 1              ; prep_cond_branch: called for a %else
interp_ccneg:  resb 1              ; prep_resolve_interp: a "%-1" being written
interp_brace_ctx: resb 1           ; ... a "%{$name}" being read
interp_lead:   resb 1              ; ... a "%N" starting the token (%{1}v)
alignb 32
token_ring:    resb TOKEN_RING * TOKEN_SIZE ; prep_token_slot's tokens
token_ring_next: resd 1
alignb 8
interp_ccstart: resq 1             ; ... where its text starts in the output
alignb 4
dir_line:      resd 1              ; the line of the directive being handled
idn_depth:     resd 1              ; prep_idn_collect: parentheses open
idn_quote:     resb 1              ; ... the quote the token's text is in
alignb 8
global prep_noexpand
prep_noexpand: resb 1              ; 1: identifiers are not macro calls (a directive reads a name)
def_eager:     resb 1              ; 1: %xdefine, expand the body now
def_func:      resb 1              ; MACRO_FLAG_FUNC for NAME(a, b)
def_nparams:   resb 1
fn_depth:      resd 1              ; parenthesis depth in a function-like call
def_pnames:    resq 9              ; parameter names of a function-like %define
def_pflags:    resb 9              ; ... their marks (PF_*)
def_pradix:    resb 9              ; ... the radix letter of an =x/x one, or 0
def_pcur_radix: resb 1             ; the parameter being read: its radix,
def_radix_next: resb 1             ; ... a "/" just read
alignb 8
def_pcur:      resq 1              ; ... and its name (0 so far)
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
mdef_dot:       resb 1              ; prep_parse_count: the count was "N."
mdef_nolist:    resb 1              ; ... MACRO_FLAG_NOLIST after ".nolist"
putback_next:  resb TOKEN_SIZE     ; a token queued behind the peek slot
global has_putback_next
has_putback_next: resb 1            ; (src/frontend/syntax/gas/gas_macro.s: raw text)
interp_cap:    resq 1              ; prep_resolve_interp: its buffer's size
idn_left_buf:  resb IDN_BUF; %ifidn operands as text (to start with)
idn_right_buf: resb IDN_BUF
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
dump_named:     db "abtnvfr"                ; -E: the escapes of bytes 7 to 13
dump_plus:      db "+"
dump_no_file:   db '""'
dump_line_dir:  db "%line ", 0
dump_open:      db "["
dump_pragma:    db "[pragma ", 0
dump_shut:      db "]"
; NASM's standard macros for directives (macros/standard.mac, outbin.mac):
; 1 "name ..." is "[name ...]"; 2 the same for each name the commas part
; ("[extern a]", "[extern b]"); 3 the name stands for the text after it
dump_dir_words:
    db 1, "bits", 0, 1, "section", 0, 1, "segment", 0, 1, "absolute", 0
    db 1, "cpu", 0, 1, "default", 0, 1, "org", 0, 1, "sectalign", 0
    db 2, "extern", 0, 2, "static", 0, 2, "global", 0, 2, "required", 0
    db 2, "common", 0, 2, "float", 0
    db 3, "use16", 0, "bits 16", 0, 3, "use32", 0, "bits 32", 0
    db 3, "use64", 0, "bits 64", 0, 3, "userel", 0, "default rel", 0
    db 3, "useabs", 0, "default abs", 0, 3, "usebnd", 0, "default bnd", 0
    db 3, "usenobnd", 0, "default nobnd", 0, 0

[SECTION .bss]
alignb 8
prep_error_subj: resq 1                 ; prep_error's subject
prep_error:     resd 1                  ; the first error a caller got, or 0
cond_negate:    resb 1                  ; %ifn / %elifn: the result inverted
cond_never_pending: resb 1              ; %elifmacro with no name: COND_NEVER
builtin_min:    resw 1                  ; %ifmacro: NASM's own macro's counts
builtin_max:    resw 1
stk_text:       resb STK_TEXT               ; %arg / %local definitions
elif_negate:    resb 1
alignb 8
dump_file:      resq 1                  ; -E: the file of the line written last,
dump_linnum:    resd 1                  ; the line the next would be (-1: a
dump_lineinc:   resd 1                  ; "%line" before it), the step,
dump_at:        resd 1                  ; the line starting,
dump_fill:      resd 1                  ; and what dump_buf holds
dump_close:     resb 1                  ; the line is a "[...]": its kind
dump_after_word: resb 1                 ; 1: one blank before the next token
alignb 8
dump_word:      resq 1                  ; ... and what follows its "["
dump_eof:       resb 1                  ; 1: the source has ended
dump_buf:       resb DUMP_BUF

[SECTION .rodata]
s_rep_negative: db "negative `%rep' count: ", 0
[SECTION .bss]
rep_num:       resb 96             ; a %rep count's text (its warning, error)
[SECTION .text]

[SECTION .bss]
dump_num:      resb 24             ; -E: an %assign's value as text
PUSH_MAX equ 64
push_count:    resd 1             ; prep_push_buffer's texts: the name,
alignb 8
push_where:    resb 24 * PUSH_MAX ; the file and line that read it in
exp_lead:      resb 1             ; the next expansion's MACROEXP_lead,
alignb 8
exp_call_file: resq 1             ; MACROEXP_call_file
exp_call_line: resd 1             ; and MACROEXP_line
inc_require:   resb 1             ; prep_handle_inc: for %require
SEEN_MAX equ 4096
alignb 8
seen_files:    resq 2 * SEEN_MAX  ; the files read: device, inode
seen_count:    resd 1
[SECTION .text]

; ---- prep_file_seen ---------------------
;
; prep_file_seen
; Whether the open file is one read before in this pass (%require): the
; same device and inode, whatever name it was opened under. A file not
; seen is noted (up to SEEN_MAX; past them %require reads it again).
; Input    : edi = the file descriptor
; Output   : rax = 1 when it was read before, else 0
; Clobbers : rcx, rdx, rsi, r8, r9, r11
;
global prep_file_seen
prep_file_seen:
    sub     rsp, 152                       ; struct stat
    mov     eax, AMD64_SYS_FSTAT
    mov     rsi, rsp
    syscall
    test    rax, rax
    js      .new
    mov     rdx, [rsp]                     ; st_dev
    mov     r8, [rsp + 8]                  ; st_ino
    lea     r9, [rel seen_files]
    mov     ecx, [rel seen_count]
.look:
    test    ecx, ecx
    jz      .note
    cmp     [r9], rdx
    jne     .on
    cmp     [r9 + 8], r8
    je      .seen
.on:
    add     r9, 16
    dec     ecx
    jmp     .look
.note:
    cmp     dword [rel seen_count], SEEN_MAX
    jae     .new
    mov     [r9], rdx
    mov     [r9 + 8], r8
    inc     dword [rel seen_count]
.new:
    xor     eax, eax
    add     rsp, 152
    ret
.seen:
    mov     eax, 1
    add     rsp, 152
    ret

[SECTION .bss]
[SECTION .text]

; ---- aliases: %defalias, %idefalias, %undefalias, %aliases ------
;
; "%defalias foo bar": foo stands for bar - defining, removing, expanding
; or testing foo is doing it to bar - until "%undefalias foo" (NASM 2.15).
; %idefalias matches the alias in any letter case; "%aliases off" stops
; them standing for anything (on: again). Every name macro.s looks up or
; defines goes through prep_alias_of (prep_symbol_find / prep_symbol_add);
; %ifdefalias asks the table itself.

; prep_symbol_find / prep_symbol_add: symbol_find / symbol_add of the
; name an alias stands for (rsi: the name / the SYMBOL)
prep_symbol_find:
    call    prep_alias_of
    jmp     symbol_find
prep_symbol_add:
    cmp     dword [rel alias_count], 0
    je      symbol_add
    push    rsi
    mov     rsi, [rsi + SYMBOL_name]
    call    prep_alias_of
    mov     rax, rsi
    pop     rsi
    mov     [rsi + SYMBOL_name], rax
    jmp     symbol_add

; prep_alias_of: rsi = the name an alias stands for, following a chain of
; them (32 links at most), or the name itself. Only rsi changes.
prep_alias_of:
    cmp     dword [rel alias_count], 0
    je      .ret
    cmp     byte [rel aliases_off], 0
    jne     .ret
    push    rax
    push    rcx
    mov     ecx, 32
.again:
    call    alias_slot
    cmp     eax, -1
    je      .out
    push    rdx
    lea     rdx, [rel alias_targets]
    mov     rsi, [rdx + rax*8]
    pop     rdx
    dec     ecx
    jnz     .again
.out:
    pop     rcx
    pop     rax
.ret:
    ret

; alias_slot: eax = the table slot of alias rsi, or -1. Only rax changes.
alias_slot:
    push    rcx
    push    rdx
    push    rdi
    push    r8
    xor     ecx, ecx
.slot:
    cmp     ecx, [rel alias_count]
    jae     .none
    lea     rdx, [rel alias_names]
    mov     rdi, [rdx + rcx*8]
    test    rdi, rdi
    jz      .next
    lea     rdx, [rel alias_icase]
    movzx   r8d, byte [rdx + rcx]
    xor     edx, edx
.ch:
    movzx   eax, byte [rdi + rdx]
    cmp     al, [rsi + rdx]
    je      .same
    test    r8d, r8d
    jz      .next
    ; %idefalias: letters in either case
    or      eax, 0x20
    cmp     eax, 'a'
    jb      .next
    cmp     eax, 'z'
    ja      .next
    push    rax
    movzx   eax, byte [rsi + rdx]
    or      eax, 0x20
    cmp     eax, [rsp]
    pop     rax
    jne     .next
    inc     edx
    jmp     .ch
.same:
    test    al, al
    jz      .hit
    inc     edx
    jmp     .ch
.next:
    inc     ecx
    jmp     .slot
.hit:
    mov     eax, ecx
    jmp     .out
.none:
    mov     eax, -1
.out:
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; prep_handle_defalias
; Input : rdi = PrepState, esi = 0 %defalias, 1 %idefalias, 2 %undefalias,
;         3 %aliases on/off
prep_handle_defalias:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r13d, esi
    mov     byte [rel prep_noexpand], 1    ; the names, not their bodies
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret_expand
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    cmp     r13d, 3
    je      .on_off
    cmp     r13d, 2
    je      .undef
    ; the target
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret_expand
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r14, [rdx + TOKEN_value]
    mov     byte [rel prep_noexpand], 0
    ; both names kept (the tokens' text does not last)
    mov     rdi, r12
    call    str_len
    mov     rdx, rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r12
    call    arena_alloc_string
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    mov     rdi, r14
    call    str_len
    mov     rdx, rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r14
    call    arena_alloc_string
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
    ; its slot: the alias's own, a free one, or a new one
    mov     rsi, r12
    call    alias_slot
    cmp     eax, -1
    jne     .store
    xor     eax, eax
    lea     rdx, [rel alias_names]
.free:
    cmp     eax, [rel alias_count]
    jae     .append
    cmp     qword [rdx + rax*8], 0
    je      .store
    inc     eax
    jmp     .free
.append:
    cmp     eax, ALIAS_MAX
    jae     .full
    inc     dword [rel alias_count]
.store:
    lea     rdx, [rel alias_names]
    mov     [rdx + rax*8], r12
    lea     rdx, [rel alias_targets]
    mov     [rdx + rax*8], r14
    lea     rdx, [rel alias_icase]
    mov     [rdx + rax], r13b
    jmp     .ok
.undef:
    mov     byte [rel prep_noexpand], 0
    mov     rsi, r12
    call    alias_slot
    cmp     eax, -1
    je      .ok
    lea     rdx, [rel alias_names]
    mov     qword [rdx + rax*8], 0
    jmp     .ok
.on_off:
    mov     byte [rel prep_noexpand], 0
    mov     rdi, r12
    lea     rsi, [rel s_aliases_off]
    call    str_cmp_kw
    xor     ecx, ecx
    test    rax, rax
    jnz     .set_on_off
    mov     ecx, 1
.set_on_off:
    mov     [rel aliases_off], cl
.ok:
    xor     eax, eax
    jmp     .ret
.full:
.bad:
    mov     eax, EXIT_DEFINE
.ret_expand:
    mov     byte [rel prep_noexpand], 0
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .rodata]
s_aliases_off: db "off", 0
[SECTION .bss]
alignb 8
alias_names:   resq ALIAS_MAX          ; an alias's name (0: a free slot)
alias_targets: resq ALIAS_MAX          ; ... the name it stands for
alias_icase:   resb ALIAS_MAX          ; ... %idefalias: any letter case
alias_count:   resd 1                  ; slots in use (free ones among them)
aliases_off:   resb 1                  ; "%aliases off"
[SECTION .text]

[SECTION .bss]
nest_buf:      resb NEST_BUF       ; a nested %[...] worked out (prep_resolve_interp)
[SECTION .text]

[SECTION .bss]
assign_num:    resb 24             ; an %assign's value as a number token's text
[SECTION .text]

; prep_text_splits: eax = 1 when the text at rsi holds a character no name
; or number has (an operator, a blank): NASM's scanner, reading the pasted
; line again, makes more than one token of it. Only rax changes.
prep_text_splits:
    push    rcx
    push    rsi
    push    rdi
.ch:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .no
    inc     rsi
    lea     rdi, [rel split_chars]
.find:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .ch
    inc     rdi
    cmp     eax, ecx
    jne     .find
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     rdi
    pop     rsi
    pop     rcx
    ret

; prep_bracket_text: rdx = "%[" text "]" in the arena (rsi = the text);
; rax = EXIT_OK or an error
prep_bracket_text:
    push    r12
    push    r13
    mov     r12, rsi
    mov     rdi, rsi
    call    str_len
    mov     r13, rax
    lea     rsi, [rax + 4]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     word [rdx], '%['
    xor     ecx, ecx
.copy:
    cmp     rcx, r13
    jae     .copied
    mov     al, [r12 + rcx]
    mov     [rdx + rcx + 2], al
    inc     rcx
    jmp     .copy
.copied:
    mov     byte [rdx + rcx + 2], ']'
    mov     byte [rdx + rcx + 3], 0
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
split_chars:   db "+-*/()<>=!&|^,:[]{} ", 9, 0
[SECTION .text]

[SECTION .bss]
dflt_target:   resd 1              ; a call's parameters with its defaults
[SECTION .text]

[SECTION .bss]
[SECTION .text]

[SECTION .data]
global rep_limit
rep_limit:     dq 1000000          ; --limit-rep (NASM's default)
[SECTION .rodata]
s_rep_limit:   db " exceeds limit (currently ", 0
[SECTION .text]

; prep_error_line / prep_error_more: an error at this line, as %error gives
; one - "file:line: error: " and the text at rsi, then (prep_error_more)
; the text at rsi and the line's end; counted, the assembly goes on and
; fails at its end
prep_error_line:
    push    rsi
    mov     edi, 1                         ; error
    extern  error_report_text
    call    error_report_text
    pop     rsi
    mov     rdi, 2
    jmp     print_str
prep_error_more:
    mov     rdi, 2
    call    print_str
    extern  error_report_end, error_deferred
    call    error_report_end
    inc     dword [rel error_deferred]
    ret

[SECTION .rodata]
s_rep_count:   db "`%rep' count ", 0
s_not_instruction: db "label or instruction expected at start of line", 0
s_empty_text:  db 0
[SECTION .text]

[SECTION .bss]
def_capturing: resb 1               ; a %define's body is being read (prep_handle_def)
[SECTION .text]
