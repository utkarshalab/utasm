;
; ============================================
; File     : error/codes.s
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
; ERROR CODES AS MESSAGES, AT THE RIGHT LINE
; ============================================================================
; The frontend and the encoders fail with an EXIT_* code. This module turns
; that code into a NASM-style diagnostic:
;
;   prog.s:12: error: invalid combination of opcode and operands
;   prog.s:4: ... from macro `m' defined here
;
; The line is the one the failing statement came from, tracked as the
; preprocessor hands out tokens (error_track_token):
;
;   - a token read from a file sets the location to its own file and line;
;   - a token from a %rep (or times) body sets it to the body line;
;   - a token from a multi-line macro keeps the invocation line and records
;     the body line for the "... from macro" note;
;   - a token from a single-line macro (%define) changes nothing.
;
;   error_track_token(tok, mexp)   called by the preprocessor per token
;   error_report_code(code)        prints the diagnostic (and any hint)
;   error_report_text(sev, text)   "file:line: <sev>: text" for %warning,
;                                  %error and %fatal
;   error_code_message(code)       the message text of an EXIT_* code
;   error_set_subject(name)        what the next error is about: a label,
;                                  a file, a macro ("label `x' ...")
;   error_set_location(file, line) where an error found later belongs
;
; error_style (-X) chooses "file:line: " (gnu, the default) or
; "file(line) : " (vc).
;
; error_deferred counts errors that do not stop the assembly (%error): the
; source is read to the end, so every one is reported, but no output file
; is written.

extern print_str
extern print_num
extern error_hint_flush
extern lst_note
extern lst_line_end
extern lst_rep_tick
extern lst_parent_exp
extern lst_enabled
extern warn_flush
extern warn_before_error
extern diag_code, diag_inst, diag_notes, diag_snippet, diag_snippet_macro
extern diag_color_on, diag_color_off
extern diag_tok_file, diag_tok_line, diag_tok_col, diag_tok_len
extern c_bold, c_red, c_magenta
extern stderr_hold
extern global_ctx

[SECTION .bss]
alignb 8
global error_loc_file
global error_loc_line
global error_subject
global error_mac_file
global error_mac_line
global error_mac_name
global error_deferred
error_loc_file:  resq 1                 ; file of the current statement, or 0
error_mac_name:  resq 1                 ; macro being expanded, or 0
error_mac_file:  resq 1                 ; its body line: file ...
error_subject:   resq 1                 ; name for the message, or 0
error_loc_line:  resd 1                 ; ... and line of the statement
error_mac_line:  resd 1                 ; ... and line in the macro body
error_deferred:  resd 1                 ; %error count
global error_style
error_style:     resb 1                 ; 0 file:line: (gnu), 1 file(line) : (vc)

[SECTION .text]

; ---- error_track_token ------------------
;
; Input    : rdi = TOKEN* just produced
;            rsi = MACROEXP* it came from, or 0 when it came from a file
; Output   : none
; Clobbers : nothing (the preprocessor calls it mid-flight)
;
global error_track_token
error_track_token:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    mov     ecx, [rdi + TOKEN_line]
    test    ecx, ecx
    jz      .done                          ; a made-up token: no position
    test    rsi, rsi
    jz      .file
    mov     r8, [rsi + MACROEXP_macro]
    test    byte [r8 + MACRO_flags], MACRO_FLAG_DEFINE
    jnz     .done                          ; %define: stays on its line
    test    byte [r8 + MACRO_flags], MACRO_FLAG_TIMES
    jnz     .times
    ; A body line lies within the body's own lines, in its file: from its
    ; first token (a %rep body) or after it (a macro's: its first token
    ; is the %macro line's newline, and default arguments come from that
    ; line) up to its last. Anything else is a macro argument.
    mov     r9, [r8 + MACRO_tokens]
    test    r9, r9
    jz      .done
    mov     rdx, [rdi + TOKEN_file]
    cmp     rdx, [r9 + TOKEN_file]
    jne     .done
    cmp     ecx, [r9 + TOKEN_line]
    jb      .done
    ja      .after_first
    cmp     qword [r8 + MACRO_name], 0
    jne     .done
.after_first:
    mov     r10d, [r8 + MACRO_ntokens]
    test    r10d, r10d
    jz      .done
    dec     r10d
    imul    r10, r10, TOKEN_SIZE
    cmp     ecx, [r9 + r10 + TOKEN_line]
    ja      .done
    mov     rax, [r8 + MACRO_name]
    test    rax, rax
    jz      .body                          ; %rep body: the body line
    ; a multi-line macro: the statement stays at the invocation line, the
    ; body line is remembered for the "... from macro" note
    mov     [rel error_mac_name], rax
    mov     [rel error_mac_file], rdx
    mov     [rel error_mac_line], ecx
    jmp     .listed_body

.body:
    ; a %rep body: its lines are where the statements are
    mov     [rel error_loc_file], rdx
    mov     [rel error_loc_line], ecx
.listed_body:
    ; the listing: a body line, marked with the expansions around it (<N>)
    cmp     byte [rel lst_enabled], 0
    je      .done
    cmp     byte [rdi + TOKEN_kind], TOK_NEWLINE
    je      .body_line_end
    call    .expansion_depth
    mov     [rel lst_parent_exp], r9       ; the enclosing body, if any
    mov     rdi, rdx
    mov     esi, ecx
    mov     edx, r8d
    mov     ecx, 1
    call    lst_note
    jmp     .done
.body_line_end:
    call    lst_line_end
    jmp     .done

.times:
    ; times: the statement's own line again; nothing moves, the listing
    ; counts the repetitions
    cmp     byte [rdi + TOKEN_kind], TOK_NEWLINE
    jne     .done
    call    lst_rep_tick
    jmp     .done

.file:
    mov     qword [rel error_mac_name], 0
    mov     rax, [rdi + TOKEN_file]
    mov     [rel error_loc_file], rax
    mov     [rel error_loc_line], ecx
    ; where the parser stopped, should it stop here (error/format/source.s)
    cmp     byte [rdi + TOKEN_kind], TOK_NEWLINE
    je      .not_marked
    cmp     byte [rdi + TOKEN_kind], TOK_EOF
    je      .not_marked
    mov     [rel diag_tok_file], rax
    mov     [rel diag_tok_line], ecx
    movzx   eax, word [rdi + TOKEN_col]
    mov     [rel diag_tok_col], eax
    movzx   eax, word [rdi + TOKEN_len]
    mov     [rel diag_tok_len], eax
.not_marked:
    ; the listing: an include's lines are marked with their depth
    xor     edx, edx
    lea     rax, [rel global_ctx]
    mov     rax, [rax + ASMCTX_inc_ctx]
    test    rax, rax
    jz      .note_file
    movzx   edx, word [rax + INCLUDECTX_depth]
    inc     edx
.note_file:
    mov     rdi, [rel error_loc_file]
    mov     esi, ecx
    xor     ecx, ecx
    call    lst_note
.done:
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; .expansion_depth: r8d = how many macro and %rep expansions are open
; around the token (rsi = the innermost), the listing's <N>; r9 = the
; nearest one around rsi's own (0 when none). Kept on each expansion as it
; opens (prep_expand_start).
.expansion_depth:
    xor     r8d, r8d
    xor     r9d, r9d
    test    rsi, rsi
    jz      .depth_done
    mov     r8d, [rsi + MACROEXP_lst_depth]
    mov     r9, [rsi + MACROEXP_lst_second]
.depth_done:
    ret

; ---- error_set_subject ------------------
;
; Names what the error about to be returned is about; the message then
; says it: "label `x' inconsistently redefined".
; Input    : rdi = NUL-terminated name (kept by pointer, not copied)
; Clobbers : nothing
;
global error_set_subject
error_set_subject:
    mov     [rel error_subject], rdi
    ret

; ---- print_subject ----------------------
;
; The error's subject on stderr: a distance kept as a name
; (RELOC_OFFSET_MARK A RELOC_OFFSET_MARK B) as "A - B", an expression kept
; until the end (RELOC_EXPR_MARK) by its text.
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
print_subject:
    push    r12
    push    r13
    mov     r12, [rel error_subject]
    cmp     byte [r12], RELOC_EXPR_MARK
    jne     .not_expr
    mov     rdi, 2
    mov     rsi, [r12 + 8]
    call    print_str
    jmp     .ret
.not_expr:
    cmp     byte [r12], RELOC_OFFSET_MARK
    jne     .plain
    inc     r12
    mov     r13, r12
.find:
    mov     al, [r13]
    test    al, al
    jz      .plain
    cmp     al, RELOC_OFFSET_MARK
    je      .split
    inc     r13
    jmp     .find
.split:
    mov     byte [r13], 0
    mov     rdi, 2
    mov     rsi, r12
    call    print_str
    mov     byte [r13], RELOC_OFFSET_MARK
    mov     rdi, 2
    lea     rsi, [rel subj_minus]
    call    print_str
    lea     r12, [r13 + 1]
.plain:
    mov     rdi, 2
    mov     rsi, r12
    call    print_str
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
subj_minus:     db " - ", 0
[SECTION .text]

; ---- error_set_location -----------------
;
; For errors found after the source is read (undefined symbols): the
; position the failing statement was recorded with.
; Input    : rdi = file (0 = none), esi = line
; Clobbers : nothing
;
global error_set_location
error_set_location:
    mov     [rel error_loc_file], rdi
    mov     [rel error_loc_line], esi
    mov     qword [rel error_mac_name], 0
    ret

; ---- error_code_message -----------------
;
; Input    : edi = EXIT_* code
; Output   : rax = its message (NUL-terminated), 0 when it has none
;            rdx = its message naming the subject, where '^' stands for
;                  the name, or 0 when it has no such form
; Clobbers : rcx
;
global error_code_message
error_code_message:
    lea     rcx, [rel code_table]
.scan:
    mov     eax, [rcx]
    test    eax, eax
    jz      .none
    cmp     eax, edi
    je      .found
    add     rcx, 24
    jmp     .scan
.found:
    mov     rax, [rcx + 8]
    mov     rdx, [rcx + 16]
    ret
.none:
    xor     eax, eax
    xor     edx, edx
    ret

; ---- error_report_code ------------------
;
; Prints "file:line: error: <message>" for an EXIT_* code, the macro note
; when the statement came from a macro, then any pending hint.
; Input    : edi = EXIT_* code
; Output   : none
;
global error_report_code
error_report_code:
    call    warn_before_error              ; the warnings held: given or not
    mov     [rel diag_code], edi           ; (error/format/source.s)
    push    rbx
    mov     ebx, edi
    lea     rdi, [rel sev_error]
    xor     esi, esi
    call    report_head
    mov     edi, ebx
    call    error_code_message
    test    rax, rax
    jz      .numbered
    cmp     qword [rel error_subject], 0
    je      .plain
    test    rdx, rdx
    jnz     .template
.plain:
    mov     rdi, 2
    mov     rsi, rax
    call    print_str
    jmp     .tail
.template:
    ; print the template in pieces, the subject in place of each '^'
    push    r12
    push    r13
    mov     r12, rdx
.piece:
    mov     r13, r12
.find:
    mov     al, [r13]
    test    al, al
    jz      .last
    cmp     al, '^'
    je      .cut
    inc     r13
    jmp     .find
.cut:
    mov     byte [r13], 0
    mov     rdi, 2
    mov     rsi, r12
    call    print_str
    mov     byte [r13], '^'
    call    print_subject
    lea     r12, [r13 + 1]
    jmp     .piece
.last:
    mov     rdi, 2
    mov     rsi, r12
    call    print_str
    pop     r13
    pop     r12
    jmp     .tail
.numbered:
    mov     rdi, 2
    lea     rsi, [rel msg_code]
    call    print_str
    mov     rdi, 2
    mov     esi, ebx
    call    print_num
.tail:
    call    report_tail
    call    error_hint_flush
    call    diag_notes                     ; what the operands were
    mov     qword [rel diag_inst], 0
    mov     dword [rel diag_code], 0
    mov     qword [rel error_subject], 0
    pop     rbx
    ret

; ---- error_report_text ------------------
;
; Starts a diagnostic of the given severity at the current statement:
; "file:line: <severity>: ". The caller prints the text; error_report_end
; ends the line and adds the macro note.
; Input    : edi = 0 warning, 1 error, 2 fatal
;
global error_report_text
error_report_text:
    mov     dword [rel diag_code], 0
    lea     rax, [rel sev_warning]
    cmp     edi, 1
    jb      .go
    ; %error (and a warning made an error): the warnings before it are
    ; given; %fatal: as any error (warn_before_error)
    ja      .fatal_held
    cmp     byte [rel stderr_hold], 0
    jne     .held_done                     ; a warning made an error: held too
    call    warn_flush
    jmp     .held_done
.fatal_held:
    call    warn_before_error
.held_done:
    cmp     edi, 1                         ; (the flags again)
    lea     rax, [rel sev_error]
    je      .go
    lea     rax, [rel sev_fatal]
.go:
    mov     rdi, rax
    jmp     report_head

global error_report_end
error_report_end:
    jmp     report_tail

; report_head: "file:line: " (or "utasm: " with no position) and the
; severity at rdi.
report_head:
    push    rbx
    mov     rbx, rdi
    lea     rsi, [rel c_bold]              ; (on a terminal: color)
    call    diag_color_on
    mov     rsi, [rel error_loc_file]
    test    rsi, rsi
    jz      .anon
    mov     edx, [rel error_loc_line]
    call    report_position
    jmp     .sev
.anon:
    mov     rdi, 2
    lea     rsi, [rel msg_utasm]
    call    print_str
.sev:
    call    diag_color_off
    lea     rsi, [rel c_magenta]
    lea     rax, [rel sev_warning]
    cmp     rbx, rax
    je      .sev_color
    lea     rsi, [rel c_red]
.sev_color:
    call    diag_color_on
    mov     rdi, 2
    mov     rsi, rbx
    call    print_str
    call    diag_color_off
    pop     rbx
    ret

; report_position: "file:line: ", or "file(line) : " in the -X vc style
; (rsi = file, edx = line)
report_position:
    push    rbx
    mov     ebx, edx
    mov     rdi, 2
    call    print_str
    mov     rdi, 2
    lea     rsi, [rel msg_colon]
    cmp     byte [rel error_style], 0
    je      .open
    lea     rsi, [rel msg_paren]
.open:
    call    print_str
    mov     rdi, 2
    mov     esi, ebx
    call    print_num
    mov     rdi, 2
    lea     rsi, [rel msg_colon_sp]
    cmp     byte [rel error_style], 0
    je      .close
    lea     rsi, [rel msg_paren_sp]
.close:
    call    print_str
    pop     rbx
    ret

; report_tail: the newline, then "file:line: ... from macro `m' defined
; here" when the statement came from a macro.
report_tail:
    sub     rsp, 8
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    call    print_str
    call    diag_snippet                   ; on a terminal: the line, marked
    cmp     qword [rel error_mac_name], 0
    je      .done
    mov     rsi, [rel error_mac_file]
    test    rsi, rsi
    jz      .done
    mov     edx, [rel error_mac_line]
    call    report_position
    mov     rdi, 2
    lea     rsi, [rel msg_from_macro]
    call    print_str
    mov     rdi, 2
    mov     rsi, [rel error_mac_name]
    call    print_str
    mov     rdi, 2
    lea     rsi, [rel msg_defined_here]
    call    print_str
    call    diag_snippet_macro             ; on a terminal: the body's line
.done:
    add     rsp, 8
    ret

[SECTION .data]

; code (dd, padded to 8), message (dq), message naming the subject (dq,
; 0 when there is none); a zero code ends the table
%macro code_msg 2-3 0
    dd %1, 0
    dq %2, %3
%endmacro

align 8
code_table:
    code_msg EXIT_ERROR,             m_error
    code_msg EXIT_OOM,               m_oom
    code_msg EXIT_IO_ERROR,          m_io
    code_msg EXIT_PARSER_ERROR,      m_parse
    code_msg EXIT_ENCODER_ERROR,     m_combination
    code_msg EXIT_LINKER_ERROR,      m_link
    code_msg EXIT_INTERNAL,          m_internal
    code_msg EXIT_ASSERTION,         m_assert
    code_msg EXIT_SIGNAL,            m_signal
    code_msg EXIT_FILE_NOT_FOUND,    m_no_file, t_no_file
    code_msg EXIT_FILE_PERM,         m_perm
    code_msg EXIT_FILE_READ,         m_read, t_read
    code_msg EXIT_FILE_WRITE,        m_write
    code_msg EXIT_INVALID_FORMAT,    m_format
    code_msg EXIT_INC_NOT_FOUND,     m_include, t_include
    code_msg EXIT_MACRO_DEF,         m_macro_def
    code_msg EXIT_MACRO_EXP,         m_macro_exp
    code_msg EXIT_MACRO_RECURSION,   m_macro_deep
    code_msg EXIT_COND_DEPTH,        m_cond_deep
    code_msg EXIT_NOT_SIMPLE,        m_not_simple
    code_msg EXIT_NONSCALAR_OP,      m_nonscalar, t_nonscalar
    code_msg EXIT_NONSCALAR_DIV,     m_nonscalar_div
    code_msg EXIT_NONSCALAR_SHIFT,   m_nonscalar_shift
    code_msg EXIT_NONSCALAR_CMP,     m_nonscalar_cmp, t_nonscalar_cmp
    code_msg EXIT_NONSCALAR_COND,    m_nonscalar_cond
    code_msg EXIT_TIMES_NONCONST,    m_times_nonconst
    code_msg EXIT_RES_NONCONST,      m_res_nonconst
    code_msg EXIT_UNKNOWN_DIRECTIVE, m_unknown_dir, t_unknown_dir
    code_msg EXIT_EA_TWO_INDEX,      m_ea_two_index
    code_msg EXIT_EA_TOO_MANY,       m_ea_too_many
    code_msg EXIT_EA_BITS,           m_addr, t_ea_bits
    code_msg EXIT_EA_SIZE_MIX,       m_ea_size_mix
    code_msg EXIT_MACRO_NO_NAME,     m_macro_def, t_macro_no_name
    code_msg EXIT_MACRO_NO_COUNT,    m_macro_def, t_macro_no_count
    code_msg EXIT_MACRO_NO_MAX,      m_macro_def, t_macro_no_max
    code_msg EXIT_MACRO_MINMAX,      m_macro_minmax
    code_msg EXIT_MACRO_EOF,         m_macro_def, t_macro_eof
    code_msg EXIT_NOT_DEFINING,      m_macro_def, t_not_defining
    code_msg EXIT_NO_REP,            m_no_rep
    code_msg EXIT_NO_SIZE,           m_no_size
    code_msg EXIT_CTX_DEPTH,         m_ctx_deep
    code_msg EXIT_MACRO_ARITY_FAIL,  m_macro_arity, t_macro_arity
    code_msg EXIT_DEFINE,            m_define
    code_msg EXIT_INC_NAME,          m_inc_name
    code_msg EXIT_INC_DEPTH,         m_inc_depth
    code_msg EXIT_EQU_FORWARD,       m_equ_fwd, t_equ_fwd
    code_msg EXIT_UNKNOWN_INSTR,     m_instr, t_instr
    code_msg EXIT_INVALID_OPERAND,   m_operand
    code_msg EXIT_INVALID_REG,       m_reg
    code_msg EXIT_INVALID_IMM,       m_imm
    code_msg EXIT_INVALID_ADDR,      m_addr
    code_msg EXIT_UNEXPECTED_TOKEN,  m_token
    code_msg EXIT_UNEXPECTED_EOF,    m_eof
    code_msg EXIT_EXPR_TOO_DEEP,     m_deep
    code_msg EXIT_INVALID_EXPR,      m_expr
    code_msg EXIT_INVALID_SECTION_FLAGS, m_sect_flags
    code_msg EXIT_ENCODE_FAIL,       m_combination
    code_msg EXIT_IMM_RANGE,         m_imm_range
    code_msg EXIT_OFFSET_RANGE,      m_offset_range
    code_msg EXIT_UNSUPPORTED_INSTR, m_unsupported
    code_msg EXIT_ALIGN_ERROR,       m_align
    code_msg EXIT_STRUCT_BOUNDS,     m_struct
    code_msg EXIT_BITS_MODE,         m_bits_mode
    code_msg EXIT_USE_PACKAGE,       m_use, t_use
    code_msg EXIT_ALIGN_MODE,        m_align_mode, t_align_mode
    code_msg EXIT_REG_SIZE,          m_reg_size
    code_msg EXIT_UNDEF_SYMBOL,      m_undef, t_undef
    code_msg EXIT_DUP_SYMBOL,        m_dup, t_dup
    code_msg EXIT_SYMBOL_RANGE,      m_sym_range
    code_msg EXIT_CIRCULAR_REF,      m_circular, t_circular
    code_msg EXIT_LD_SCRIPT_404,     m_ld_404
    code_msg EXIT_LD_SCRIPT_PARSE,   m_ld_parse
    code_msg EXIT_SECTION_OVERLAP,   m_overlap
    code_msg EXIT_RELOC_ERROR,       m_reloc
    code_msg EXIT_UNDEF_REF,         m_undef, t_undef
    code_msg EXIT_MULTI_DEF,         m_multi, t_multi
    code_msg EXIT_INVALID_SECTION,   m_section
    code_msg EXIT_OUT_CREATE,        m_out_create
    code_msg EXIT_ELF_WRITE,         m_elf_write
    code_msg EXIT_BIN_WRITE,         m_bin_write
    code_msg EXIT_ASSERT,            m_assert
    code_msg EXIT_UNREACHABLE,       m_unreachable
    code_msg EXIT_NOT_IMPLEMENTED,   m_not_impl
    code_msg EXIT_UBF_EMPTY,         m_ubf_empty
    code_msg EXIT_UBF_TOO_BIG,       m_ubf_big
    dd 0, 0
    dq 0, 0

m_error:        db "error", 0
m_oom:          db "out of memory", 0
m_io:           db "input/output error", 0
m_parse:        db "syntax error", 0
m_link:         db "cannot link the program", 0
m_internal:     db "internal error (a utasm bug)", 0
m_assert:       db "assertion failed", 0
m_signal:       db "interrupted", 0
m_no_file:      db "no such file", 0
m_perm:         db "permission denied", 0
m_read:         db "error reading a file", 0
m_write:        db "error writing a file", 0
m_format:       db "invalid file format", 0
m_include:      db "unable to open include file", 0
m_macro_def:    db "invalid macro definition", 0
m_macro_exp:    db "error expanding a macro", 0
m_macro_deep:   db "macros nested too deeply (runaway recursion?)", 0
m_macro_arity:  db "no macro of this name takes this number of parameters", 0
m_define:       db "invalid %define", 0
m_inc_name:     db "`%include' expects a quoted file name", 0
m_inc_depth:    db "includes nested too deeply (does a file include itself?)", 0
m_equ_fwd:      db "equ refers to a symbol defined later", 0
m_instr:        db "parser: instruction expected", 0
m_operand:      db "invalid operand", 0
m_reg:          db "invalid register", 0
m_imm:          db "invalid immediate value", 0
m_addr:         db "invalid effective address", 0
m_token:        db "unexpected token (comma, colon or end of line expected?)", 0
m_eof:          db "unexpected end of file", 0
m_deep:         db "expression too deeply nested", 0
m_expr:         db "expression syntax error", 0
m_sect_flags:   db "invalid section attributes", 0
m_combination:  db "invalid combination of opcode and operands", 0
m_imm_range:    db "value out of range for the operand size", 0
m_offset_range: db "jump or displacement out of range", 0
m_unsupported:  db "instruction not supported for this target", 0
m_align:        db "invalid alignment (not a power of two?)", 0
m_struct:       db "operand larger than the structure field", 0
m_bits_mode:    db "instruction not supported in this bits mode (16/32/64)", 0
m_use:          db "unknown `%use' package", 0
m_cond_deep:    db "conditionals nested too deeply", 0
m_not_simple:   db "expression is not simple or relocatable", 0
m_nonscalar:    db "operator may only be applied to scalar values", 0
m_nonscalar_div: db "division operator may only be applied to scalar values", 0
m_nonscalar_shift: db "shift operator may only be applied to scalar values", 0
m_nonscalar_cmp: db "operands differ by a non-scalar", 0
m_nonscalar_cond: db "the left-hand side of `?' must be a scalar value", 0
m_times_nonconst: db "non-constant argument supplied to TIMES", 0
m_res_nonconst: db "attempt to reserve non-constant quantity of BSS space", 0
m_unknown_dir:  db "unknown preprocessor directive", 0
m_ea_two_index: db "invalid effective address: two index registers", 0
m_ea_too_many:  db "invalid effective address: too many registers", 0
m_ea_size_mix:  db "impossible combination of address sizes", 0
m_macro_minmax: db "minimum parameter count exceeds maximum", 0
m_no_rep:       db "`%endrep': no matching `%rep'", 0
m_no_size:      db "operation size not specified", 0
m_ctx_deep:     db "context stack nested too deeply", 0
m_align_mode:   db "unknown alignment mode", 0
m_reg_size:     db "invalid register size specification", 0
m_undef:        db "undefined symbol", 0
m_dup:          db "label inconsistently redefined", 0
m_sym_range:    db "symbol value out of range", 0
m_circular:     db "circular symbol definition", 0
m_ld_404:       db "linker script not found", 0
m_ld_parse:     db "linker script syntax error", 0
m_overlap:      db "sections overlap", 0
m_reloc:        db "relocation out of range or not supported", 0
m_multi:        db "symbol defined more than once", 0
m_section:      db "invalid section", 0
m_out_create:   db "unable to create the output file", 0
m_elf_write:    db "error writing the ELF output", 0
m_bin_write:    db "error writing the binary output", 0
m_unreachable:  db "internal error: unreachable code reached", 0
m_not_impl:     db "not implemented yet", 0
m_ubf_empty:    db "-f ubf: the program has no bytes to boot", 0
m_ubf_big:      db "-f ubf: a component is larger than 4 GiB", 0

t_no_file:      db "unable to open `^': no such file", 0
t_read:         db "error reading `^'", 0
t_circular:     db "`^' is defined in terms of itself", 0
t_equ_fwd:      db "equ refers to `^', defined later", 0
t_include:      db "unable to open include file `^'", 0
t_macro_arity:  db "multi-line macro `^' does not take this number of parameters", 0
t_undef:        db "symbol `^' not defined", 0
t_dup:          db "label `^' inconsistently redefined", 0
t_multi:        db "symbol `^' defined more than once", 0
t_instr:        db "parser: instruction expected, found `^'", 0
t_use:          db "unknown `%use' package `^'", 0
t_nonscalar:    db "`^' operator may only be applied to scalar values", 0
t_nonscalar_cmp: db "`^': operands differ by a non-scalar", 0
t_unknown_dir:  db "unknown preprocessor directive `%^'", 0
t_ea_bits:      db "invalid ^-bit effective address", 0
t_macro_no_name: db "`%^' expects a macro name", 0
t_macro_no_count: db "`%^' expects a parameter count", 0
t_macro_no_max: db "`%^' expects a parameter count after `-'", 0
t_macro_eof:    db "end of file while still defining macro `^'", 0
t_not_defining: db "`%^': not defining a macro", 0
t_align_mode:   db "unknown alignment mode: ^", 0

sev_warning:    db "warning: ", 0
sev_error:      db "error: ", 0
sev_fatal:      db "fatal: ", 0
msg_code:       db "error ", 0
msg_utasm:      db "utasm: ", 0
msg_colon:      db ":", 0
msg_colon_sp:   db ": ", 0
msg_newline:    db 10, 0
msg_from_macro: db "... from macro `", 0
msg_paren:      db "(", 0
msg_paren_sp:   db ") : ", 0
msg_defined_here: db "' defined here", 10, 0
