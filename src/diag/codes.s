;
; ============================================
; File     : src/diag/codes.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

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
    ; the line is where the expansion stands in its body (the body token
    ; just read): an argument's tokens are the line of its %1, even when
    ; they were written in this body too (a %rmacro calling itself listed
    ; its lines twice, switching to the call's line and back)
    cmp     qword [r8 + MACRO_name], 0
    je      .body_line                     ; (a %rep body has no arguments)
    mov     r10, [rsi + MACROEXP_body]
    test    r10, r10
    jz      .body_line
    dec     r10
    imul    r10, r10, TOKEN_SIZE
    mov     ecx, [r9 + r10 + TOKEN_line]
.body_line:
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
    ; ... not in a .nolist macro, or inside one: its bytes are the calling
    ; line's, as NASM lists them
    cmp     byte [rsi + MACROEXP_nolist], 0
    jne     .done
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
    ; where the parser stopped, should it stop here (src/diag/source.s)
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
    mov     [rel diag_code], edi           ; (src/diag/source.s)
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
    code_msg EXIT_SIZE_MISMATCH,     m_size_mismatch
    code_msg EXIT_COFF_RELOC,        m_coff_reloc, t_coff_reloc
    code_msg EXIT_COFF_SPECIAL,      m_coff_special
    code_msg EXIT_ILOG2,             m_ilog2
    code_msg EXIT_CFI_NO_PROC,       m_cfi_no_proc
    code_msg EXIT_CFI_OPEN,          m_cfi_open
    code_msg EXIT_CFI_EOF,           m_cfi_eof
    code_msg EXIT_CFI_REG,           m_cfi_reg, t_cfi_reg
    code_msg EXIT_CFI_UNKNOWN,       m_cfi_unknown, t_cfi_unknown
    code_msg EXIT_CFI_STATE,         m_cfi_state
    code_msg EXIT_CFI_ENDPROC,       m_cfi_endproc
    code_msg EXIT_RES_NEGATIVE,      m_res_negative
    code_msg EXIT_SECTION_SIZE,      m_section_size, t_section_size
    code_msg EXIT_TIMES_LARGE,       m_times_large
    code_msg EXIT_TIMES_NEGATIVE,    m_times_negative, t_times_negative
    code_msg EXIT_UNDEF_BEFORE,      m_undef, t_undef_before
    code_msg EXIT_PP_NONCONST,       m_not_simple, t_pp_nonconst
    code_msg EXIT_BRACKET_UNKNOWN,   m_bracket_unknown, t_bracket_unknown
    code_msg EXIT_BIN_COMMON,        m_bin_common
    code_msg EXIT_BIN_SPECIAL,       m_bin_special
    code_msg EXIT_FAR_NOT_RELOC,     m_far_not_reloc
    code_msg EXIT_SEG_BASE,          m_seg_base, t_seg_base
    code_msg EXIT_SEG_NOT_RELOC,     m_seg_not_reloc
    code_msg EXIT_GOTOFF_QWORD,      m_gotoff_qword
    code_msg EXIT_GOTOFF_QWORD_ABS,  m_gotoff_qword_abs
    code_msg EXIT_WRT_UNSUPPORTED,   m_wrt_unsupported
    code_msg EXIT_DEST_IS_SOURCE,    m_dest_is_source
    code_msg EXIT_ORG_BACKWARDS,     m_org_backwards
    code_msg EXIT_ATT_SYNTAX,        m_att_syntax
    code_msg EXIT_MERGE_ENTSIZE,     m_merge_entsize
    code_msg EXIT_SYM_TYPE,          m_sym_type, t_sym_type
    code_msg EXIT_POPSECTION,        m_popsection
    code_msg EXIT_GAS_RAW,           m_gas_raw
    code_msg EXIT_GAS_NO_ENDM,       m_gas_no_endm, t_gas_no_endm
    code_msg EXIT_GAS_NO_ENDR,       m_gas_no_endr, t_gas_no_endr
    code_msg EXIT_GAS_STRAY,         m_gas_stray, t_gas_stray
    code_msg EXIT_GAS_NO_ENDIF,      m_gas_no_endif
    code_msg EXIT_GAS_ARG_REQ,       m_gas_arg_req, t_gas_arg_req
    code_msg EXIT_GAS_ARG_MANY,      m_gas_arg_many
    code_msg EXIT_GAS_ARG_NAME,      m_gas_arg_name, t_gas_arg_name
    code_msg EXIT_GAS_NO_MACRO,      m_gas_no_macro, t_gas_no_macro
    code_msg EXIT_GAS_PARAMS,        m_gas_params
    code_msg EXIT_INPUT_OPEN,        m_input_open, t_input_open
    code_msg EXIT_VIRTUAL_OPEN,      m_virtual_open
    code_msg EXIT_LOAD_RANGE,        m_load_range
    code_msg EXIT_LOAD_LATER,        m_load_later
    code_msg EXIT_MASM_NESTED,       m_masm_nested
    code_msg EXIT_MASM_FRAME,        m_masm_frame
    code_msg EXIT_MASM_STRAY,        m_masm_stray
    code_msg EXIT_MASM_ENDP,         m_masm_endp
    code_msg EXIT_INVOKE_CLOBBER,    m_invoke_clobber
    code_msg EXIT_MASM_OPEN,         m_masm_open
    code_msg EXIT_MASM_PROC_OPEN,    m_masm_proc_open, t_masm_proc_open
    code_msg EXIT_MASM_SIZEOF,       m_masm_sizeof, t_masm_sizeof
    code_msg EXIT_MASM_FIELD,        m_masm_field, t_masm_field
    code_msg EXIT_MASM_ENDS,         m_masm_ends
    code_msg EXIT_MASM_STRUCT_OPEN,  m_masm_struct_open, t_masm_struct_open
    code_msg EXIT_FASM_FORMAT,       m_fasm_format, t_fasm_format
    code_msg EXIT_KNOWN_RERUN,       m_known_rerun
    code_msg EXIT_CPU_LEVEL,         m_cpu_level
    code_msg EXIT_CPU_UNKNOWN,       m_cpu_unknown, t_cpu_unknown
    code_msg EXIT_BITS32_CPU,        m_bits32_cpu
    code_msg EXIT_BITS64_CPU,        m_bits64_cpu
    code_msg EXIT_LINE_FILE_NUM,     m_line_file_num
    code_msg EXIT_LINE_UNASSIGNED,   m_line_unassigned, t_line_unassigned
    code_msg EXIT_LINE_FILE_SLOT,    m_line_file_slot, t_line_file_slot
    code_msg EXIT_LINE_FILE_BIG,     m_line_file_big, t_line_file_big
    code_msg EXIT_LINE_STMT,         m_line_stmt
    code_msg EXIT_LINE_VIEW_NUM,     m_line_view_num
    code_msg EXIT_LINE_LOC_WORD,     m_line_loc_word, t_line_loc_word
    code_msg EXIT_LINE_VIEW_MISMATCH, m_line_view_mismatch
    code_msg EXIT_LINE_VIEW_MOVED,   m_line_view_moved, t_line_view_moved
    code_msg EXIT_LINE_DUP,          m_line_dup
    code_msg EXIT_GAS_BASE64,        m_gas_base64
    code_msg EXIT_PROC_NESTED,       m_proc_nested
    code_msg EXIT_PROC_NO_PROC,      m_proc_no_proc
    code_msg EXIT_PROC_OPEN,         m_proc_open
    code_msg EXIT_NOT_STRUC,         m_not_struc, t_not_struc
    code_msg EXIT_FIELD_SIZE,        m_field_size, t_field_size
    code_msg EXIT_NS_NO_NS,          m_ns_no_ns
    code_msg EXIT_NS_MODULE,         m_ns_module
    code_msg EXIT_NS_OUTSIDE,        m_ns_outside
    code_msg EXIT_NS_DEPTH,          m_ns_depth
    code_msg EXIT_NS_OPEN,           m_ns_open
    code_msg EXIT_NS_PRIVATE,        m_ns_private, t_ns_private
    code_msg EXIT_NS_SHADOW,         m_ns_shadow, t_ns_shadow
    code_msg EXIT_TMM_SAME,          m_tmm_same
    code_msg EXIT_GATHER_SAME,       m_gather_same
    code_msg EXIT_VSIB_NO_MASK,      m_vsib_no_mask
    code_msg EXIT_MASK_REFUSED,      m_mask_refused
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
    code_msg EXIT_BITS_MODE,         m_bits_mode, t_bits_mode
    code_msg EXIT_NON64_OPERANDS,    m_non64
    code_msg EXIT_ALIGN_LARGE,       m_align_large, t_align_large
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
t_bits_mode:    db "instruction not supported in ^ mode", 0
m_non64:        db "invalid operands in non-64-bit mode", 0
m_align_large:  db "absurdly large segment alignment", 0
m_coff_reloc:   db "COFF format has no relocation for this reference", 0
t_coff_reloc:   db "COFF format has no ^ relocation", 0
m_coff_special: db "COFF format does not support any special symbol types", 0
m_ilog2:        db "ilog2 argument is not a power of two", 0
m_cfi_no_proc:  db "CFI instruction used without previous .cfi_startproc", 0
m_cfi_open:     db "previous CFI entry not closed (missing .cfi_endproc)", 0
m_cfi_eof:      db "open CFI at the end of file; missing .cfi_endproc directive", 0
m_cfi_reg:      db "bad register expression", 0
t_cfi_reg:      db "bad register expression `^'", 0
m_cfi_unknown:  db "unknown CFI directive", 0
t_cfi_unknown:  db "unknown CFI directive `^'", 0
m_cfi_state:    db "CFI state restore without previous remember", 0
m_cfi_endproc:  db ".cfi_endproc without corresponding .cfi_startproc", 0
m_res_negative: db "attempt to reserve negative space", 0
m_section_size: db "section larger than 4 GiB", 0
t_section_size: db "section `^' larger than 4 GiB", 0
m_times_large:  db "TIMES value is too large (more than 4294967295)", 0
m_times_negative: db "TIMES value is negative", 0
t_times_negative: db "TIMES value ^ is negative", 0
t_align_large:  db "absurdly large segment alignment `^'", 0
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
m_size_mismatch: db "mismatch in operand sizes", 0
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
t_undef_before: db "symbol `^' not defined before use", 0
t_pp_nonconst:  db "non-constant value given to `%^'", 0
m_bracket_unknown: db "unrecognized directive", 0
m_bin_common:   db "binary output format does not support common variables", 0
m_bin_special:  db "binary format does not support any special symbol types", 0
m_far_not_reloc: db "value referenced by FAR is not relocatable", 0
m_seg_base:     db "segment base references are not supported", 0
t_seg_base:     db "^ format does not support segment base references", 0
m_seg_not_reloc: db "cannot apply SEG to a non-relocatable value", 0
m_gotoff_qword: db "ELF64 requires ..gotoff references to be qword", 0
m_gotoff_qword_abs: db "ELF64 requires ..gotoff references to be qword absolute", 0
m_wrt_unsupported: db "ELF format does not support this use of WRT", 0
m_dest_is_source: db "the destination must not be a source register (the CPU faults: #UD)", 0
m_org_backwards: db ".org would move the location counter backwards", 0
m_att_syntax:   db "AT&T syntax: an instruction or operand not read (operands are %reg, $imm, disp(base, index, scale), *target)", 0
m_merge_entsize: db "entity size for SHF_MERGE not specified", 0
m_sym_type:     db "unrecognized symbol type", 0
t_sym_type:     db "unrecognized symbol type `^'", 0
m_popsection:   db ".popsection without corresponding .pushsection", 0
m_gas_raw:      db "a GNU .macro, .rept, .irp, .ifb or .ifc inside a NASM macro or %rep (its source text is not there)", 0
m_gas_no_endm:  db "unexpected end of file in a macro definition (no .endm)", 0
t_gas_no_endm:  db "unexpected end of file in macro `^' definition (no .endm)", 0
m_gas_no_endr:  db "no .endr for this repetition", 0
t_gas_no_endr:  db "`^' without .endr", 0
m_gas_stray:    db "a closing directive with nothing open", 0
t_gas_stray:    db "`^' with nothing open for it", 0
m_gas_no_endif: db "end of file in conditional (an .if with no .endif)", 0
m_gas_arg_req:  db "missing value for a required macro parameter", 0
t_gas_arg_req:  db "missing value for required parameter `^'", 0
m_gas_arg_many: db "too many positional arguments", 0
m_gas_arg_name: db "no macro parameter of that name", 0
t_gas_arg_name: db "no macro parameter named `^'", 0
m_gas_no_macro: db "no macro of that name", 0
t_gas_no_macro: db "macro `^' not defined", 0
m_gas_params:   db "bad .macro parameter list (NAME, NAME=DEFAULT, NAME:req, NAME:vararg)", 0
m_input_open:   db "unable to open the input file", 0
t_input_open:   db "unable to open input file `^'", 0
m_virtual_open: db "`virtual' with no `end virtual'", 0
m_load_range:   db "load / store outside the bytes assembled (past the end, another section, or none)", 0
m_load_later:   db "load / store of bytes not final yet (a relocation or a jump fills them in later)", 0
m_masm_nested:  db "PROC inside a PROC (an ENDP missing?)", 0
m_masm_frame:   db "LOCAL needs the PROC's frame: put the LOCAL lines right after the PROC line", 0
m_masm_stray:   db "ENDP with no PROC open", 0
m_masm_endp:    db "ENDP's name is not the PROC's", 0
m_invoke_clobber: db "INVOKE argument reads a register an earlier argument was loaded into", 0
m_masm_open:    db ".IF / .WHILE / .REPEAT with no end (.ENDIF / .ENDW / .UNTIL)", 0
m_masm_proc_open: db "PROC with no ENDP", 0
t_masm_proc_open: db "PROC `^' with no ENDP", 0
m_masm_sizeof:  db "SIZEOF / LENGTHOF / TYPE of a name that is no type, field or variable MASM declared", 0
t_masm_sizeof:  db "SIZEOF / LENGTHOF / TYPE of `^': no type, field or variable MASM declared", 0
m_masm_field:   db "no such structure field", 0
t_masm_field:   db "no structure field `^'", 0
m_masm_ends:    db "ENDS's name is not the STRUCT's", 0
m_masm_struct_open: db "STRUCT with no ENDS", 0
t_masm_struct_open: db "STRUCT `^' with no ENDS", 0
m_fasm_format:  db "format: not the output format -f chose (ELF64 [executable], ELF, binary)", 0
t_fasm_format:  db "format `^': not the output format -f chose (ELF64 [executable], ELF, binary)", 0
m_known_rerun:  db "the second pass could not be started (running /proc/self/exe failed)", 0
m_cpu_level:    db "no instruction for this cpu level", 0
m_cpu_unknown:  db "unknown CPU type or flag", 0
t_cpu_unknown:  db "unknown CPU type or flag '^'", 0
m_bits32_cpu:   db "cannot specify 32-bit segment on processor below a 386", 0
m_bits64_cpu:   db "cannot specify 64-bit segment on processor below an x86-64", 0
m_line_file_num: db "file number less than one", 0
m_line_unassigned: db "unassigned file number", 0
t_line_unassigned: db "unassigned file number ^", 0
m_line_file_slot: db "file table slot is already occupied by a different file", 0
t_line_file_slot: db "file table slot ^ is already occupied by a different file", 0
m_line_file_big: db "file number is too big", 0
t_line_file_big: db "file number ^ is too big", 0
m_line_stmt:    db "is_stmt value not 0 or 1", 0
m_line_view_num: db "numeric view can only be asserted to zero", 0
m_line_loc_word: db "unknown .loc sub-directive", 0
t_line_loc_word: db "unknown .loc sub-directive `^'", 0
m_line_view_mismatch: db "view number mismatch", 0
m_line_view_moved: db "a view number changed when jumps were shortened", 0
t_line_view_moved: db "view number `^' changed when jumps were shortened", 0
m_line_dup:     db "duplicate .debug_line sections", 0
m_gas_base64:   db "invalid character found inside .base64 string", 0
m_proc_nested:  db "proc inside a proc (no endproc for the one before)", 0
m_proc_no_proc: db "endproc with no proc", 0
m_proc_open:    db "proc has no endproc", 0
m_not_struc:    db "not a structure", 0
t_not_struc:    db "`^' is not a structure (one defined before this line)", 0
m_field_size:   db "the size written is not the field's", 0
t_field_size:   db "the size written is not that of the field `^'", 0
m_ns_no_ns:     db "endnamespace with no namespace", 0
m_ns_module:    db "endnamespace in a module (a module ends with its file)", 0
m_ns_outside:   db "export / private outside a namespace or module", 0
m_ns_depth:     db "namespaces nested too deep", 0
m_ns_open:      db "namespace has no endnamespace", 0
m_ns_private:   db "private name used from outside", 0
t_ns_private:   db "`^' is private: used from outside its namespace / module", 0
m_ns_shadow:    db "name taken from an outer namespace, then defined inside", 0
m_tmm_same:     db "the three tile registers must all differ (#UD otherwise)", 0
m_gather_same:  db "a gather's destination, index and mask registers must all differ (#UD otherwise)", 0
m_vsib_no_mask: db "a gather / scatter needs a write mask, {k1} to {k7} (#UD with k0)", 0
m_mask_refused: db "this instruction takes no write mask / {z} here (#UD with one)", 0
t_ns_shadow:    db "`^' was taken from an outer namespace, then this one defined it (write ::^, or define it before)", 0
t_bracket_unknown: db "unrecognized directive [^]", 0
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
