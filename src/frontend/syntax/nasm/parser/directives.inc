; ============================================================================
; File        : src/frontend/syntax/nasm/parser/directives.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : bits / cpu, sectalign, absolute, alignb, istruc / at / iend, cfi; the expression operator tables and the parser's state
; ============================================================================

[SECTION .text]

;*
; * [parser_handle_bits]
; * Purpose: "bits 16 / 32 / 64": the code mode (asm_bits, __BITS__).
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_handle_bits:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    cmp     rdx, 16
    je      .ok
    cmp     rdx, 32
    je      .ok
    cmp     rdx, 64
    je      .ok
    mov     rax, EXIT_INVALID_OPERAND
    ret
.ok:
    call    parser_bits_cpu
    test    eax, eax
    jnz     .ret
    mov     [rel asm_bits], dl
    xor     eax, eax
.ret:
    ret

; parser_bits_cpu: "bits 32" under a "cpu" below 386, "bits 64" below x86-64
; (cpu_num): NASM's "cannot specify 32-bit / 64-bit segment on processor
; below ..." - edx = the bits -> eax = 0 or the error. Preserves edx.
parser_bits_cpu:
    xor     eax, eax
    movzx   ecx, byte [rel cpu_num]
    test    ecx, ecx
    jz      .bc_ret
    cmp     edx, 32
    jne     .bc_64
    cmp     ecx, 4
    jae     .bc_ret
    mov     eax, EXIT_BITS32_CPU
    ret
.bc_64:
    cmp     edx, 64
    jne     .bc_ret
    cmp     ecx, 11
    jae     .bc_ret
    mov     eax, EXIT_BITS64_CPU
.bc_ret:
    ret

[SECTION .data]
align 8
ds_utf_buf:    dq ds_utf           ; __utf16__ / __utf32__ output (it grows)
; the operators' texts by EOP_* / EXP_* (expr_scalar's messages)
eop_texts:     dq 0, eop_bar, eop_hat, eop_amp, eop_eq, eop_ne, eop_lt
               dq eop_le, eop_gt, eop_ge, eop_cmp, eop_bar, eop_hat, eop_amp
               dq 0, 0, 0, 0, 0, eop_tilde, eop_bang
eop_bar:       db "|", 0
eop_hat:       db "^", 0
eop_amp:       db "&", 0
eop_eq:        db "==", 0
eop_ne:        db "!=", 0
eop_lt:        db "<", 0
eop_le:        db "<=", 0
eop_gt:        db ">", 0
eop_ge:        db ">=", 0
eop_cmp:       db "<=>", 0
eop_tilde:     db "~", 0
eop_bang:      db "!", 0
expr_level:    dd 0                ; parser_evaluate_expression's nesting
expr_terms:    dd 0                ; the terms read in this expression ...
align 8
global eval_limit
eval_limit:    dq 8192             ; ... at most (--limit-eval, NASM's default)
expr_lost:     db 0                ; a label not defined yet went into arithmetic
default_given: db 0                ; "default rel" / "default abs" written
implicit_said: db 0                ; implicit-abs-deprecated given (once)
global expr_xsec
expr_xsec:     db 0                ; two sections' labels in a difference (a flat binary)
expr_pp:       db 0                ; in a preprocessor expression (parser_evaluate_pp)
expr_deferring: db 0               ; parser_deferred_value is working one out
global expr_late_diff
expr_late_diff: db 0               ; a GNU LEB128: "b - a" of code worked out late
ds_utf_cap:    dq DS_UTF_SIZE
global asm_bits
asm_bits:       db 64               ; bits 16 / 32 / 64
align 8
global user_sect_name
user_sect_name: dq str_text         ; __SECT__'s section
[SECTION .rodata]
; name (7 bytes) + bits
use_words:      db "use16", 0, 0, 16
                db "use32", 0, 0, 32
                db "use64", 0, 0, 64
                db 0
str_sectalign:  db "sectalign", 0
str_sa_on:      db "on", 0
str_sa_off:     db "off", 0
; -f win64 (parser_coff_section): a name (8 bytes), its class, its SEC_*
coff_sec_names:
    db ".text", 0, 0, 0, COFF_CODE, SEC_TEXT
    db ".data", 0, 0, 0, COFF_DATA, SEC_DATA
    db ".bss", 0, 0, 0, 0, COFF_BSS, SEC_BSS
    db ".rdata", 0, 0, COFF_RDATA, SEC_CUSTOM
    db ".xdata", 0, 0, COFF_RDATA, SEC_CUSTOM
    db ".pdata", 0, 0, COFF_PDATA, SEC_CUSTOM
    db 0
; the classes (parser_coff_class): ELF type, flags, alignment
align 8
coff_classes:
    dd SHT_PROGBITS
    dw SHF_ALLOC | SHF_EXECINSTR, 16       ; COFF_CODE
    dd SHT_PROGBITS
    dw SHF_ALLOC | SHF_WRITE, 4            ; COFF_DATA
    dd SHT_PROGBITS
    dw SHF_ALLOC, 8                        ; COFF_RDATA
    dd SHT_NOBITS
    dw SHF_ALLOC | SHF_WRITE, 4            ; COFF_BSS
    dd SHT_PROGBITS
    dw 0, 1                                ; COFF_INFO
    dd SHT_PROGBITS
    dw SHF_ALLOC, 4                        ; COFF_PDATA
; the attribute words: word (11 bytes) + class
coff_attr_words:
    db "code", 0, 0,0,0,0,0,0, COFF_CODE
    db "text", 0, 0,0,0,0,0,0, COFF_CODE
    db "data", 0, 0,0,0,0,0,0, COFF_DATA
    db "rdata", 0, 0,0,0,0,0, COFF_RDATA
    db "bss", 0, 0,0,0,0,0,0,0, COFF_BSS
    db "info", 0, 0,0,0,0,0,0, COFF_INFO
    db 0
; directive names, 10 bytes each
ignored_words:db "warning", 0, 0, 0
                db "map", 0, 0, 0, 0, 0, 0, 0
                db "list", 0, 0, 0, 0, 0, 0
                db "float", 0, 0, 0, 0, 0
                db "debug", 0, 0, 0, 0, 0
                db "required", 0, 0
                db 0
[SECTION .bss]
stmt_bracketed: resb 1              ; the statement is in [ ]
stmt_labelled: resb 1               ; a label came before its first word
extern_required: resb 1             ; parser_handle_extern for "required"
sect_sep:       resb 1              ; a section name's joining character ('-' ',')
alignb 8
sect_sep_tok:   resb TOKEN_SIZE     ; ... its token, to put back
alignb 2
opnd_kw_size:   resw 1              ; "qword gs:[x]": the size written
global sectalign_off
sectalign_off:  resb 1              ; "sectalign off": align leaves the section's
[SECTION .text]

;*
; * [parser_sectalign]
; * Purpose: "sectalign N": the current section's alignment at least N (a
; *   power of two); "sectalign off": align / alignb no longer raise a
; *   section's alignment; "sectalign on": they do again (NASM's).
; * Input  : RBX = PrepState. Output: RAX = OK or an error
; ;
parser_sectalign:
    push    r12
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .value
    mov     r12, [rdx + TOKEN_value]
    mov     rdi, r12
    lea     rsi, [rel str_sa_off]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_off
    mov     byte [rel sectalign_off], 1
    jmp     .word
.not_off:
    mov     rdi, r12
    lea     rsi, [rel str_sa_on]
    call    str_cmp_kw
    test    rax, rax
    jnz     .value
    mov     byte [rel sectalign_off], 0
.word:
    mov     rdi, rbx
    call    preprocessor_next_token
    xor     eax, eax
    jmp     .ret
.value:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    test    rdx, rdx
    jz      .ok
    lea     rcx, [rdx - 1]
    test    rcx, rdx
    jnz     .ok                            ; not a power of two: nothing
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .ok
    cmp     rdx, [rax + SECTION_align]
    jbe     .ok
    mov     [rax + SECTION_align], rdx
.ok:
    xor     eax, eax
.ret:
    pop     r12
    ret

;*
; * [parser_absolute]
; * Purpose: "absolute ADDR": what follows (until the next section
; *   directive) is laid out from ADDR without emitting anything; its labels
; *   are plain numbers (the way a structure's fields are).
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_absolute:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    call    parser_abs_place
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rax, [rel abs_section]
    test    rax, rax
    jnz     .have
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel str_absolute]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .error
    ; not a section of the output: out of the list again
    mov     rdi, [rbx + PREP_ctx]
    dec     word [rdi + ASMCTX_seccount]
    mov     dword [rdx + SECTION_elf_type], SHT_NOBITS
    mov     byte [rdx + SECTION_type], SEC_ABSOLUTE    ; (its labels numbers)
    mov     [rel abs_section], rdx
    mov     rax, rdx
.have:
    pop     rdx
    mov     [rax + SECTION_addr], rdx
    mov     qword [rax + SECTION_size], 0
    mov     rdi, [rbx + PREP_ctx]
    mov     [rdi + ASMCTX_curr_sec], rax
    xor     eax, eax
.ret:
    ret
.error:
    pop     rdx
    ret

;*
; * [parser_abs_place]
; * Purpose: The address an "absolute" / FASM "virtual at" block starts at,
; *   from its expression's value (rdx) and label (r11): "absolute x+7" is
; *   x's offset as the code is laid out, the jumps before it shortened
; *   (src/core/known.s, as for "%if $ - $$"; or that code keeps its size); in
; *   a flat binary its section's start (org) with it, as NASM has it.
; * Input  : RBX = PrepState, RDX = the value, R11 = its label (or 0)
; * Output : RAX = OK, RDX = the address
; ;
global parser_abs_place
parser_abs_place:
    test    r11, r11
    jz      .based
    movzx   ecx, word [r11 + SYMBOL_section]
    test    ecx, ecx
    jz      .based
    cmp     ecx, SHN_ABS
    jae     .based
    mov     rax, [rbx + PREP_ctx]
    mov     r8, [rax + ASMCTX_sections]
    movzx   r9d, word [rax + ASMCTX_seccount]
.find_sec:
    test    r9d, r9d
    jz      .based
    mov     r10, [r8]
    cmp     [r10 + SECTION_index], cx
    je      .sec_found
    add     r8, 8
    dec     r9d
    jmp     .find_sec
.sec_found:
    push    rdx
    mov     rdi, r10
    mov     rsi, [r11 + SYMBOL_value]
    xor     edx, edx                       ; (from the section's start)
    call    known_pp_diff
    test    eax, eax
    jz      .abs_kept
    add     [rsp], rdx
    jmp     .abs_taken
.abs_kept:
    call    relax_freeze_range
.abs_taken:
    pop     rdx
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    jne     .based
    add     rdx, [r10 + SECTION_addr]
.based:
    xor     eax, eax
    ret

;*
; * [parser_alignb]
; * Purpose: "alignb N [, fill]": reserve up to the next multiple of N (no
; *   bytes are written; the fill is ignored, as for resb).
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_alignb:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .fill
    test    rdx, rdx
    jz      .fill
    mov     rcx, [rax + SECTION_size]
    neg     rcx
    lea     r8, [rdx - 1]
    and     rcx, r8
    ; the listing shows the space as reserved ("<res 3FFFFh>"), as NASM's
    push    rax
    push    rcx
    push    rdx
    mov     rdi, [rax + SECTION_size]
    lea     rsi, [rdi + rcx]
    extern  lst_uninit
    call    lst_uninit
    pop     rdx
    pop     rcx
    pop     rax
    add     [rax + SECTION_size], rcx
    push    rax
    push    rcx
    push    rdx
    mov     rdi, rax
    extern  asm_ctx_fit
    call    asm_ctx_fit                    ; (its bytes, past the buffer)
    pop     rdx
    pop     rcx
    pop     rax
    cmp     byte [rel sectalign_off], 0
    jne     .fill                          ; "sectalign off"
    cmp     rdx, [rax + SECTION_align]
    jbe     .fill
    mov     [rax + SECTION_align], rdx
.fill:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .ok
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
.ok:
    xor     eax, eax
.ret:
    ret

;*
; * [parser_alignmode]
; * Purpose: "alignmode MODE [, threshold | nojmp]" (%use smartalign): the
; *   NOPs "align" pads code with (src/optimize/align.s).
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_alignmode:
    push    r12
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; the mode
    xor     esi, esi                       ; its own threshold
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    xor     esi, esi
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .set
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .threshold
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_nojmp]
    call    str_cmp_kw
    test    rax, rax
    jnz     .threshold
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     esi, 1                         ; nojmp: never jump
    jmp     .set
.threshold:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     esi, 2                         ; rdx = the threshold
.set:
    mov     rdi, r12
    extern  align_mode_directive
    call    align_mode_directive
    test    rax, rax
    jz      .ret
    mov     rdi, r12
    call    error_set_subject
    jmp     .ret
.bad:
    mov     eax, EXIT_ALIGN_MODE
.ret:
    pop     r12
    ret

[SECTION .rodata]
str_absolute:  db "absolute", 0
str_fasm_virtual: db "virtual", 0
str_fasm_end:  db "end", 0
str_fasm_load: db "load", 0
str_fasm_store: db "store", 0
str_fasm_format: db "format", 0
str_fasm_entry: db "entry", 0
str_fasm_segment: db "segment", 0
str_defined:   db "defined", 0
str_masm_offset: db "__?masm_offset?__", 0
str_sizeof:    db "sizeof", 0
str_lengthof:  db "lengthof", 0
str_type_op:   db "type", 0
str_alignb_d:  db "alignb", 0
str_alignmode: db "alignmode", 0
str_nojmp:     db "nojmp", 0
attr_vstart:   db "vstart", 0
attr_start:    db "start", 0
attr_follows:  db "follows", 0
[SECTION .bss]
global abs_section
abs_section:   resq 1              ; the "absolute" pseudo-section
[SECTION .text]

;*
; * [parser_struc_const]
; * Purpose: Defines a number (a NASM struc field, "<struct>_size").
; * Input  : RBX = PrepState, RSI = name, RDX = value
; * Output : RAX = OK or an error
; ;
parser_struc_const:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    ; the same structure defined again (two files each declaring it):
    ; a field with the same offset is fine, as in NASM
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .new
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    je      .again
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .new
.again:
    cmp     [rdx + SYMBOL_value], r13
    jne     .new                           ; symbol_add reports it
    xor     eax, eax
    pop     r13
    pop     r12
    ret
.new:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     rcx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rsp + SYMBOL_vis], VIS_LOCAL
    ; a number, as for equ: a use before the structure (thread_t.x in a
    ; file included first) is resolved to it at the end
    mov     word [rsp + SYMBOL_section], SHN_ABS
    mov     byte [rsp + SYMBOL_pflags], SYMF_STRUC
    mov     [rsp + SYMBOL_name], r12
    mov     [rsp + SYMBOL_value], r13
    mov     qword [rsp + SYMBOL_size], 8
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    pop     r13
    pop     r12
    ret

;*
; * [parser_res_unit]
; * Purpose: The unit of a reservation word: resb 1, resw 2, resd 4,
; *          resq 8, rest 10, reso 16, resy 32, resz 64.
; * Input  : RDI = word
; * Output : EAX = bytes per unit, 0 when it is no reservation word
; ;
parser_res_unit:
    cmp     byte [rdi + 4], 0
    jne     .none
    mov     ecx, [rdi]
    or      ecx, 0x20202020                ; RESB is resb
    mov     eax, 1
    cmp     ecx, 'resb'
    je      .ret
    mov     eax, 2
    cmp     ecx, 'resw'
    je      .ret
    mov     eax, 4
    cmp     ecx, 'resd'
    je      .ret
    mov     eax, 8
    cmp     ecx, 'resq'
    je      .ret
    mov     eax, 10
    cmp     ecx, 'rest'
    je      .ret
    mov     eax, 16
    cmp     ecx, 'reso'
    je      .ret
    mov     eax, 32
    cmp     ecx, 'resy'
    je      .ret
    mov     eax, 64
    cmp     ecx, 'resz'
    je      .ret
.none:
    xor     eax, eax
.ret:
    ret

;*
; * [parser_pad_to]
; * Purpose: Zero-fills the current section up to an offset (istruc/at/iend).
; * Input  : RBX = PrepState, RDI = offset
; * Output : RAX = OK or an error
; ;
    extern  asm_ctx_emit_byte
parser_pad_to:
    push    r12
    mov     r12, rdi
.loop:
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    cmp     [rax + SECTION_size], r12
    jge     .done                          ; (signed: "at" before the start,
    xor     esi, esi                       ; a negative struc offset, is nothing)
    call    asm_ctx_emit_byte
    test    rax, rax
    jnz     .ret
    jmp     .loop
.done:
    xor     eax, eax
.ret:
    pop     r12
    ret

;*
; * [parser_istruc]
; * Purpose: "istruc NAME" starts an instance of a NASM structure here.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_istruc:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rax, [rdx + TOKEN_value]
    mov     [rel istruc_name], rax
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     rax, [rax + SECTION_size]
    mov     [rel istruc_base], rax
    ; NASM's istruc is a macro that opens a context and puts the label
    ; "%$strucstart" here: "..@N.strucstart", N the context's number (the
    ; macro's own is counted already). The same label, as NASM's objects
    ; and listings have it
    push    r12
    mov     rdi, [rbx + PREP_arena]
    mov     esi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .label_ret
    mov     r12, rdx
    mov     dword [r12], '..@'
    mov     rax, [rbx + PREP_ctx]
    mov     esi, [rax + ASMCTX_mac_exp_id]
    inc     dword [rax + ASMCTX_mac_exp_id]
    lea     rdi, [r12 + 3]
    extern  str_int_to_str
    call    str_int_to_str
    lea     rdi, [r12 + 3]
    call    str_len
    lea     rdi, [r12 + rax + 3]
    lea     rsi, [rel str_strucstart]
.copy:
    lodsb
    stosb
    test    al, al
    jnz     .copy
    mov     rsi, r12
    call    parser_define_label
.label_ret:
    pop     r12
    ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    ret

;*
; * [parser_cfi]
; * Purpose: A .cfi_ directive (GAS's), recorded by src/debug/cfi.s: its
; *   register (a name - rbp, xmm3, or GAS's %rbp - or DWARF's number) and
; *   offset as its form wants them.
; * Input  : RBX = PrepState, R12 = the directive's name, in lower case
; * Output : RAX = OK or an error
; ;
parser_cfi:
    push    r12
    push    r13
    push    r14
    push    r15
    lea     r13, [rel cfi_words]
.word:
    cmp     byte [r13], 0
    je      .unknown
    lea     rdi, [r12 + 5]                 ; after ".cfi_"
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .found
    add     r13, 32
    jmp     .word
.unknown:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_CFI_UNKNOWN
    jmp     .ret
.found:
    xor     r14d, r14d                     ; the register
    xor     r15d, r15d                     ; the second / the offset
    movzx   eax, byte [r13 + 31]           ; its form
    cmp     eax, 0
    je      .record
    cmp     eax, 1
    je      .reg_only
    cmp     eax, 2
    je      .expr_only
    cmp     eax, 3
    je      .reg_expr
    cmp     eax, 4
    je      .reg_reg
    cmp     eax, 5
    je      .startproc
    cmp     eax, 6
    je      .escape
    ; 7: accepted, nothing to record (.cfi_sections .eh_frame)
    call    parser_skip_to_eol
    xor     eax, eax
    jmp     .ret
.reg_only:
    call    .reg
    test    rax, rax
    jnz     .ret
    mov     r14d, edx
    jmp     .record
.expr_only:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    jmp     .record
.reg_expr:
    call    .reg
    test    rax, rax
    jnz     .ret
    mov     r14d, edx
    call    .comma
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    jmp     .record
.reg_reg:
    call    .reg
    test    rax, rax
    jnz     .ret
    mov     r14d, edx
    call    .comma
    test    rax, rax
    jnz     .ret
    call    .reg
    test    rax, rax
    jnz     .ret
    mov     r15d, edx
    jmp     .record
.startproc:
    ; ".cfi_startproc simple": no initial rules
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .record
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_cfi_simple]
    call    str_cmp_kw
    test    rax, rax
    jnz     .record
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r15d, 1
    jmp     .record
.escape:
    ; bytes, one record each
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     rcx, rdx
    and     ecx, 0xFF
    mov     edi, CFI_ESCAPE
    xor     esi, esi
    xor     edx, edx
    extern  cfi_directive
    call    cfi_directive
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .escape
.record:
    movzx   edi, byte [r13 + 30]           ; CFI_*
    mov     esi, r14d
    mov     edx, r15d
    mov     rcx, r15
    call    cfi_directive
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; .comma: the comma between two arguments
.comma:
    mov     rdi, rbx
    call    preprocessor_next_token
    xor     eax, eax
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    je      .comma_ret
    mov     eax, EXIT_UNEXPECTED_TOKEN
.comma_ret:
    ret

; .reg: a register -> edx = its DWARF number (rax = OK or an error)
.reg:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .reg_ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NUMBER
    je      .reg_number
    cmp     eax, TOK_IDENT
    je      .reg_name
    cmp     eax, TOK_DIRECTIVE              ; GAS's "%rbp"
    je      .reg_name
    mov     eax, EXIT_UNEXPECTED_TOKEN
    ret
.reg_number:
    mov     rdi, [rdx + TOKEN_value]
    call    str_to_int
    ret
.reg_name:
    push    qword [rdx + TOKEN_value]
    mov     rdi, [rdx + TOKEN_value]
    extern  cfi_register
    call    cfi_register                   ; eax = the number, or -1
    pop     rdi
    mov     edx, eax
    xor     eax, eax
    test    edx, edx
    jns     .reg_ret
    call    error_set_subject
    mov     eax, EXIT_CFI_REG
.reg_ret:
    ret

;*
; * [parser_endstruc_late]
; * Purpose: endstruc for a struc whose layout a section line ended
; *   (parser_parse_struc .struc_left): NASM's "<name>_size equ $ - <name>"
; *   is then a label where it is, as NASM's object has it.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_endstruc_late:
    push    r12
    push    r13
    mov     rax, [rbx + PREP_ctx]
    inc     dword [rax + ASMCTX_mac_exp_id] ; (a macro in NASM)
    mov     r12, [rel struc_open]
    mov     qword [rel struc_open], 0
    mov     rdi, r12
    call    str_len
    mov     r13, rax
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r13 + 6]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, r12
    mov     rcx, r13
    rep     movsb
    mov     dword [rdi], '_siz'
    mov     word [rdi + 4], 'e'
    mov     rsi, rdx
    call    parser_define_label
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_at]
; * Purpose: "at FIELD, <data>": zero-fill up to the field; the data after
; *          the comma is then parsed as a statement of its own.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_at:
    ; ".w" is the istruc's structure's field (NASM 2.16): the structure's
    ; name the local labels' base while the field is read
    push    r12
    mov     rax, [rbx + PREP_ctx]
    mov     r12, [rax + ASMCTX_last_global]
    mov     rcx, [rel istruc_name]
    test    rcx, rcx
    jz      .at_base
    mov     [rax + ASMCTX_last_global], rcx
.at_base:
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     rcx, [rbx + PREP_ctx]
    mov     [rcx + ASMCTX_last_global], r12
    pop     r12
    test    rax, rax
    jnz     .ret
    ; a struc with a base offset ("struc s, -40"): its fields count from
    ; that offset, the instance from 0
    mov     rdi, rdx
    mov     rsi, [rel istruc_name]
    test    rsi, rsi
    jz      .at_offset                     ; "at" with no istruc
    push    rdx
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    pop     rdi
    test    rax, rax
    jnz     .at_offset
    cmp     byte [rdx + SYMBOL_kind], SYM_STRUCT
    jne     .at_offset
    sub     rdi, [rdx + SYMBOL_value]
.at_offset:
    add     rdi, [rel istruc_base]
    call    parser_pad_to
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .ok
    mov     rdi, rbx
    call    preprocessor_next_token
.ok:
    xor     eax, eax
.ret:
    ret

;*
; * [parser_iend]
; * Purpose: "iend": zero-fill to the end of the structure (its
; *          "<name>_size", or utasm's "<name>_SIZE").
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_iend:
    push    r12
    push    r13
    mov     r12, [rel istruc_name]
    test    r12, r12
    jz      .ok
    mov     rdi, r12
    call    str_len
    mov     r13, rax
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rax + 6]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    mov     dword [rdi], '_siz'
    mov     word [rdi + 4], 'e'
    mov     r12, rdx                       ; the name
    mov     r13, rdi                       ; its suffix
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jz      .found
    mov     dword [r13], '_SIZ'
    mov     byte [r13 + 4], 'E'
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .ok                            ; unknown: nothing to fill
.found:
    mov     rdi, [rel istruc_base]
    add     rdi, [rdx + SYMBOL_value]
    call    parser_pad_to
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
str_alignb:    db "alignb", 0
str_istruc:    db "istruc", 0
str_at:        db "at", 0
str_iend:      db "iend", 0
[SECTION .bss]
istruc_base:   resq 1              ; offset where the istruc began
istruc_name:   resq 1              ; its structure's name
