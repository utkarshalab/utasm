;
; ============================================================================
; File        : src/frontend/syntax/nasm/parser.s
; Project     : utasm
; Description : Multi-Architecture Instruction Parser and Dispatch System.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/macro.inc"
%include "src/include/type.inc"

%define SIZE_LATE_CAP  (1 << 20)        ; .size directives kept (parser_size_late)
DEFAULT REL
%include "src/include/elf.inc"
%include "src/include/arch/aarch64.inc"

extern arena_alloc
extern float_encode
extern warn_begin
extern known_active
extern known_lookup
extern known_note_verify
extern warn_data_bounds
extern warn_text
extern warn_end
extern lst_uninit
extern io_open
extern io_read
extern io_close
extern io_lseek
extern asmctx_emit_word
extern asmctx_emit_qword
extern preprocessor_next_token
extern preprocessor_peek_token
extern preprocessor_putback_token
extern preprocessor_unread_token
extern str_to_int
extern symbol_add
extern symbol_find
extern str_compare
extern asm_ctx_align
extern str_concat
extern error_hint_mnemonic
extern relax_freeze_current
extern relax_freeze_symref
extern relax_freeze_range
extern relax_defer_begin
extern relax_defer_end
extern relax_pending_padto
extern asm_ctx_create_section
extern asmctx_get_section
extern asmctx_emit_byte
extern asmctx_emit_word
extern asmctx_emit_dword
extern asmctx_emit_qword
extern str_cmp_kw
extern known_lookup
extern known_note_forward
extern known_fwd_uses
extern parser_lookup_mnemonic
extern parser_check_prefix
extern parser_parse_mem_operand
extern masm_hl
extern parser_concat_local_name
extern print_str
extern print_num

[SECTION .text]

;*
; * [parser_parse_instruction]
; * Purpose: Parses an instruction and dispatches to the correct architectural table.
; * Parameters:
; *   RBX: [in] Pointer to PrepState
; ;
global parser_parse_instruction
global parser_evaluate_expression
parser_parse_instruction:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16
    mov     rbx, rdi               ; RBX = PrepState
    extern  reloc_wrt
    extern  gas_names
    mov     byte [rel reloc_wrt], 0    ; no "wrt ..name" pending

    ; the statement's INST: one of INST_RING, used in turn and cleared (it
    ; is encoded before the next is parsed; an arena one each was most of
    ; the memory a long source took)
    mov     eax, [rel inst_ring_next]
    lea     ecx, [eax + 1]
    and     ecx, INST_RING - 1
    mov     [rel inst_ring_next], ecx
    imul    eax, eax, INST_SIZE
    lea     rdx, [rel inst_ring]
    add     rdx, rax
    mov     rdi, rdx
    mov     ecx, INST_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     r15, rdx
    mov     byte [r15 + INST_tag], TAG_INSTRUCTION
    
    ; 1. Resolve architectural tables based on context
    call    parser_get_arch_tables
    mov     r11, rax                ; R11 = Mnemonic Table
    mov     r10, rdx                ; R10 = Register Table
    
    ; Reserve space for tables and metadata on stack
    sub     rsp, 32
    mov     [rsp], r10
    mov     [rsp + 8], r11
    mov     qword [rsp + 16], 0     ; is_bracketed = 0
    mov     qword [rsp + 24], 0     ; a word of the line read (a label)
    
    ; 2. Get mnemonic token
.get_mnemonic:
    ; Reload tables from stack
    mov     r10, [rsp]
    mov     r11, [rsp + 8]
    mov     byte [rel stmt_bracketed], 0

    ; Check if bracketed directive/statement starts
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    IF byte [rdx + TOKEN_kind], e, TOK_LBRACKET
        cmp     qword [rsp + 24], 0
        jne     .bracket_mid
        ; Consume the LBRACKET
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     qword [rsp + 16], 1 ; is_bracketed = 1
        mov     byte [rel stmt_bracketed], 1
        ENDIF

    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx

    ; "[db 1]", "[mov eax, 1]", "[align 4]": only NASM's directives go in
    ; [ ] (the primitives; db, align, struc ... are no directives there)
    cmp     qword [rsp + 16], 1
    jne     .bracket_ok
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .bracket_ok
    lea     r13, [rel bracket_words]
.bracket_word:
    cmp     byte [r13], 0
    je      .bracket_unknown
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .bracket_ok
.bracket_skip:
    inc     r13
    cmp     byte [r13 - 1], 0
    jne     .bracket_skip
    jmp     .bracket_word
.bracket_mid:
    ; "x: [bits 32]": a [ ] statement begins its line (NASM: "parser:
    ; instruction expected")
    extern  error_subject
    mov     qword [rel error_subject], 0
    mov     rax, EXIT_UNKNOWN_INSTR
    jmp     .done
.bracket_unknown:
    mov     rdi, [r12 + TOKEN_value]
    extern  error_set_subject
    call    error_set_subject
    mov     rax, EXIT_BRACKET_UNKNOWN
    jmp     .done
.bracket_ok:
    ; "[pragma ...]" (what -E writes for a %pragma): what %pragma does
    cmp     qword [rsp + 16], 1
    jne     .not_pragma
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_pragma
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_pragma]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_pragma
    extern  prep_handle_pragma, pragma_bracket
    mov     byte [rel pragma_bracket], 1
    call    prep_handle_pragma
    mov     byte [rel pragma_bracket], 0
.pragma_rest:
    ; its "]" and the rest of the line
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_EOF
    je      .pragma_eof
    cmp     eax, TOK_NEWLINE
    jne     .pragma_rest
    mov     qword [rsp + 16], 0     ; the next line: no [ ] of its own yet
    mov     qword [rsp + 24], 0
    jmp     .get_mnemonic
.pragma_eof:
    xor     rax, rax
    xor     rdx, rdx                ; RDX=0 signals EOF to main loop
    jmp     .done
.not_pragma:

    mov     al, [r12 + TOKEN_kind]
    IF al, e, TOK_EOF
        xor     rax, rax
        xor     rdx, rdx                ; RDX=0 signals EOF to main loop
        jmp     .done
        ENDIF
    IF al, e, TOK_NEWLINE
        mov     qword [rsp + 24], 0
        jmp     .get_mnemonic           ; Skip empty lines
        ENDIF
    mov     qword [rsp + 24], 1

    ; NASM's encoding prefixes: "{rex} add eax, edx", "{vex3} vcomisd ..."
    cmp     al, TOK_LBRACE
    jne     .no_enc_prefix
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .no_enc_prefix_brace
    mov     r13, [rdx + TOKEN_value]
    lea     r14, [rel enc_prefix_words]
.enc_prefix_find:
    cmp     byte [r14], 0
    je      .apx_prefix
    mov     rdi, r13
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .enc_prefix_found
    add     r14, 8
    jmp     .enc_prefix_find
.enc_prefix_found:
    mov     al, [r14 + 7]
    or      [r15 + INST_flags], al
    mov     rdi, rbx
    call    preprocessor_next_token        ; the word
    check_err
    mov     rdi, rbx
    call    preprocessor_next_token        ; "}"
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACE
    jne     .enc_prefix_bad
    jmp     .get_mnemonic
.enc_prefix_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .error
.apx_prefix:
    ; APX's: "{nf} add rax, rbx" (the flags kept), "{zu} setz al"
    lea     r14, [rel apx_prefix_words]
.apx_prefix_find:
    cmp     byte [r14], 0
    je      .no_enc_prefix_brace
    mov     rdi, r13
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .apx_prefix_found
    add     r14, 4
    jmp     .apx_prefix_find
.apx_prefix_found:
    mov     al, [r14 + 3]
    or      [r15 + INST_apx], al
    mov     rdi, rbx
    call    preprocessor_next_token        ; the word
    check_err
    mov     rdi, rbx
    call    preprocessor_next_token        ; "}"
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACE
    jne     .enc_prefix_bad
    jmp     .get_mnemonic
.no_enc_prefix_brace:
    mov     al, [r12 + TOKEN_kind]
.no_enc_prefix:

    ; GNU's syntax: "name": - a quoted name's label (GCC 16, -masm=intel)
    cmp     al, TOK_STRING
    jne     .not_quoted_label
    cmp     byte [rel gas_names], 0
    je      .not_quoted_label
    cmp     byte [r12 + TOKEN_quote], '"'
    jne     .not_quoted_label
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .quoted_word
    mov     rdi, rbx
    call    preprocessor_next_token        ; ":"
    mov     byte [r12 + TOKEN_kind], TOK_LABEL
    mov     al, TOK_LABEL
    jmp     .not_quoted_label
.quoted_word:
    mov     al, TOK_STRING
.not_quoted_label:

    IF al, e, TOK_LABEL
        ; Global Label: rsi = name
        mov     rsi, [r12 + TOKEN_value]
        mov     rdi, [rbx + PREP_ctx]
        ; A "..@N_name" is an expanded %%local, not a global. Letting it
        ; become last_global would namespace every following .local label
        ; under it, and the references would no longer resolve.
        cmp     byte [rsi], '.'
        je      .keep_global
        mov     [rdi + ASMCTX_last_global], rsi
    .keep_global:
        call    parser_define_label
        check_err
        jmp     .get_mnemonic
        ENDIF



    IF al, e, TOK_LOCAL_LABEL
        ; Local Label: concat last_global + local_name
        mov     rsi, [r12 + TOKEN_value] ; local name (e.g. ".loop")
        cmp     byte [rsi + 1], '.'
        je      .macro_local_label       ; "..@N_x" stands on its own

        mov     rdi, [rbx + PREP_ctx]
        mov     r14, [rdi + ASMCTX_last_global]
        test    r14, r14
        jz      .local_no_global           ; before any global label

        mov     rsi, [r12 + TOKEN_value] ; local name (e.g. ".loop")
        call    parser_concat_local_name
        mov     rsi, rdx                ; namespaced name
        call    parser_define_label
        check_err
        jmp     .get_mnemonic

    .macro_local_label:
        call    parser_define_label
        check_err
        jmp     .get_mnemonic
        ENDIF

    ; A GNU numeric label ("1:") arrives as NUMBER followed by COLON
    IF al, e, TOK_NUMBER
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        IF byte [rdx + TOKEN_kind], e, TOK_COLON
            mov     rdi, rbx
            call    preprocessor_next_token    ; consume ':'
            check_err
            mov     rdi, [r12 + TOKEN_value]
            call    parser_numlabel_def
            check_err
            call    parser_define_label
            check_err
            jmp     .get_mnemonic
            ENDIF
        mov     al, [r12 + TOKEN_kind]
        ENDIF

    ; A label built by token pasting arrives as IDENT followed by COLON,
    ; because the lexer only forms TOK_LABEL when ':' directly follows the
    ; identifier text in the source.
    IF al, e, TOK_IDENT
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        IF byte [rdx + TOKEN_kind], e, TOK_COLON
            mov     rdi, rbx
            call    preprocessor_next_token    ; consume ':'
            check_err

            mov     rsi, [r12 + TOKEN_value]
            cmp     byte [rsi], '.'
            jne     .pasted_global_label
            cmp     byte [rsi + 1], '.'
            jne     .pasted_local_label
.pasted_global_label:

            mov     rdi, [rbx + PREP_ctx]
            ; "..@N_name" is an expanded %%local, never the enclosing global
            cmp     byte [rsi], '.'
            je      .pasted_keep_global
            mov     [rdi + ASMCTX_last_global], rsi
        .pasted_keep_global:
            call    parser_define_label
            check_err
            jmp     .get_mnemonic

        .pasted_local_label:
            mov     rdi, [rbx + PREP_ctx]
            mov     r14, [rdi + ASMCTX_last_global]
            test    r14, r14
            jz      .local_no_global           ; before any global label
            call    parser_concat_local_name
            mov     rsi, rdx
            call    parser_define_label
            check_err
            jmp     .get_mnemonic
            ENDIF
        ENDIF

    mov     al, [r12 + TOKEN_kind]     ; the peek above clobbered al

    IF al, ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF

    ; Peek at the next token to see if it is "equ"
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    ; RDX = peeked TOKEN*
    IF byte [rdx + TOKEN_kind], e, TOK_IDENT
        mov     rdi, [rdx + TOKEN_value]
        lea     rsi, [rel str_equ]
        extern  str_cmp
        call    str_cmp_kw                 ; EQU too
        IF rax, e, OK
            ; Yes! The next token is "equ".
            ; 1. Define the current identifier (in r12) as a label/symbol.
            ;    A constant already defined may be defined again with the
            ;    same value (NASM: two files both define SEL_NULL equ 0).
            mov     byte [rel equ_again], 0
            mov     rsi, [r12 + TOKEN_value]
            cmp     byte [rsi], '.'
            je      .equ_define
            xor     edx, edx
            call    ns_qualify                 ; (net::x inside net)
            mov     rdi, [rbx + PREP_ctx]
            call    symbol_find
            test    rax, rax
            jnz     .equ_define
            cmp     word [rdx + SYMBOL_section], SHN_ABS
            jne     .equ_define
            cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
            je      .equ_define
            mov     rax, [rbx + PREP_ctx]
            mov     [rax + ASMCTX_last_symbol], rdx
            mov     byte [rel equ_again], 1
            jmp     .equ_defined
.equ_define:
            mov     rsi, [r12 + TOKEN_value]
            mov     rdi, [rbx + PREP_ctx]
            call    parser_define_label
            check_err
.equ_defined:

            ; 2. Consume the "equ" token
            mov     rdi, rbx
            call    preprocessor_next_token
            check_err
            
            ; 3. Handle the equ (evaluates expression and overrides symbol)
            mov     rdi, rbx
            call    parser_handle_equ
            check_err
            
            ; 4. Done with this instruction line!
            jmp     .get_mnemonic
            ENDIF
        ENDIF

    ; MASM's "NAME PROC ..." / "NAME ENDP" (%use masm: src/frontend/syntax/
    ; masm.s)
    extern  masm_label_word
    mov     rdi, rbx
    mov     rsi, [r12 + TOKEN_value]
    call    masm_label_word
    test    eax, eax
    jz      .not_masm_label
    mov     rax, rdx
    check_err
    jmp     .get_mnemonic
.not_masm_label:

    ; "NAME = EXPR" (GNU as, FASM, MASM): a constant, which a later "NAME =
    ; ..." sets again (src/frontend/syntax/gas/gas.s gas_assign) - "==" is no such
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .not_assign
    cmp     word [rdx + TOKEN_len], 1
    jne     .not_assign
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    mov     rsi, [r12 + TOKEN_value]
    extern  gas_assign
    call    gas_assign
    check_err
    jmp     .get_mnemonic
.not_assign:

    ; 3. Sync DWARF line info
    mov     rdi, [rbx + PREP_ctx]
    mov     eax, [rbx + PREP_line]
    mov     [rdi + ASMCTX_debug_line], eax
    mov     ax, [rbx + PREP_col]
    movzx   eax, ax
    mov     [rdi + ASMCTX_debug_col], eax
    
    ; AT&T syntax (.att_syntax, --att): the statement, its prefixes too, in
    ; utasm's syntax, read next (src/frontend/syntax/gas/att.s)
    extern  att_on, att_statement
    cmp     byte [rel att_on], 0
    je      .not_att
    mov     rdi, rbx
    mov     rsi, r12
    call    att_statement
    test    eax, eax
    jz      .not_att
    mov     rax, rdx
    check_err
    jmp     .get_mnemonic
.not_att:

    ; 4. Lookup Mnemonic
    mov     rsi, [r12 + TOKEN_value]

    ; Check for prefixes (A71)
    call    parser_check_prefix
    test    rax, rax
    jz      .lookup_mnemonic
    cmp     eax, 1
    je      .get_mnemonic
    ; xacquire / xrelease (8 / 9): F2 / F3, and which it was for the HLE
    ; warnings (parser_check_hle) - repne / rep are the same bytes
    cmp     eax, 8
    je      .hle_acquire
    cmp     eax, 9
    jne     .not_hle
    or      byte [r15 + INST_flags], INSTF_XRELEASE
    mov     eax, 0xF3
    jmp     .prefix_byte
.hle_acquire:
    or      byte [r15 + INST_flags], INSTF_XACQUIRE
    mov     eax, 0xF2
    jmp     .prefix_byte
.not_hle:
    cmp     eax, 7
    ja      .prefix_byte
    cmp     eax, 5
    jb      .asize
    ; o16 / o32 / o64 (5, 6, 7): the operation size asked for - the encoder
    ; gives the instruction its prefix (amd64_force_osize)
    lea     ecx, [eax - 4]
    mov     eax, 8
    shl     eax, cl                        ; 16, 32, 64
    mov     [r15 + INST_osize], al
    jmp     .get_mnemonic
.asize:
    ; a16 / a32 / a64 (2, 3, 4): the address size asked for. Its byte, 67,
    ; only when it is not the mode's own; 16 in 64-bit code, or 64 outside
    ; it, is NASM's error
    lea     ecx, [eax - 1]
    mov     eax, 8
    shl     eax, cl                        ; 16, 32, 64
    mov     [r15 + INST_asize], al
    movzx   ecx, byte [rel asm_bits]
    cmp     eax, ecx
    je      .get_mnemonic                  ; the mode's own: no byte
    cmp     eax, 64
    je      .asize_bad                     ; a64 outside 64-bit code
    cmp     ecx, 64
    jne     .asize_67
    cmp     eax, 16
    je      .asize_bad                     ; a16 in 64-bit code
.asize_67:
    mov     eax, 0x67
    jmp     .prefix_byte
.asize_bad:
    mov     rax, EXIT_EA_SIZE_MIX
    jmp     .error
.prefix_byte:
    ; Find empty slot in prefixes[4]
    xor     rcx, rcx
.prefix_slot_loop:
    cmp     byte [r15 + INST_prefixes + rcx], 0
    je      .prefix_found_slot
    inc     rcx
    cmp     rcx, 4
    jl      .prefix_slot_loop
    jmp     .get_mnemonic           ; All slots full, ignore or error
    
.prefix_found_slot:
    mov     byte [r15 + INST_prefixes + rcx], al
    jmp     .get_mnemonic           ; Get the actual mnemonic or next prefix

.lookup_mnemonic:
    ; MASM's ret in a PROC: its epilogue (src/frontend/syntax/masm/masm.s)
    extern  masm_ret
    mov     rdi, rbx
    mov     rsi, [r12 + TOKEN_value]
    call    masm_ret
    test    eax, eax
    jz      .no_masm_ret
    mov     rax, rdx
    test    rax, rax
    jnz     .error
    jmp     .pseudo_op_ok
.no_masm_ret:
    ; GNU's .macro names (src/frontend/syntax/gas/gas_macro.s), before the
    ; mnemonics: a macro may be named as an instruction is
    extern  gm_defined, gas_macro_call
    cmp     qword [rel gm_defined], 0
    je      .no_gas_macro
    mov     rdi, rbx
    mov     rsi, [r12 + TOKEN_value]
    call    gas_macro_call
    test    eax, eax
    jz      .no_gas_macro
    mov     rax, rdx
    test    rax, rax
    jnz     .error
    jmp     .pseudo_op_ok
.no_gas_macro:
    mov     rsi, [r12 + TOKEN_value]
    mov     [rel inst_mnem_text], rsi      ; (parser_check_lock)
    hash_fnv1a_64_ci rsi, r13
    
    ; Reload tables as hash macro clobbers r11 (and potentially others)
    mov     r10, [rsp]
    mov     r11, [rsp + 8]

    mov     rdi, r13
    mov     rsi, r11                ; Current Arch Mnemonic Table
    call    parser_lookup_mnemonic
    
    test    rax, rax
    jz      .try_pseudo_op
    
    mov     [r15 + INST_op_id], ax
    ; "cpu 386": an instruction of a later level (x86_cpu_level, the
    ; lowest of its forms') is NASM's "no instruction for this cpu level"
    extern  cpu_num, x86_cpu_level, x86_cpu_maxid
    movzx   ecx, byte [rel cpu_num]
    test    ecx, ecx
    jz      .parse_operands
    mov     rdx, [rbx + PREP_ctx]
    cmp     byte [rdx + ASMCTX_target], TARGET_AMD64
    jne     .parse_operands
    movzx   eax, ax
    cmp     eax, [rel x86_cpu_maxid]
    ja      .parse_operands
    lea     rdx, [rel x86_cpu_level]
    movzx   edx, byte [rdx + rax]
    cmp     edx, ecx
    jbe     .parse_operands
    mov     rax, EXIT_CPU_LEVEL
    jmp     .error

.try_pseudo_op:
    ; Check for db, dw, dd, dq, resb, etc.
    mov     rdi, rbx               ; rdi = PrepState
    mov     rsi, [r12 + TOKEN_value]
    call    parser_handle_pseudo_op
    test    rax, rax
    jz      .unknown_mnemonic
    cmp     rax, 1
    je      .pseudo_op_ok
    jmp     .error

.pseudo_op_ok:
    ; If it was bracketed, we must consume the closing RBRACKET
    cmp     qword [rsp + 16], 1
    je      .consume_rbracket
    jmp     .get_mnemonic

.consume_rbracket:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    IF byte [rdx + TOKEN_kind], ne, TOK_RBRACKET
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     qword [rsp + 16], 0     ; clear bracketed flag
    jmp     .get_mnemonic

.parse_operands:
    xor     r14, r14
    mov     byte [rel far_colon], 0
    ; bndmk / bndldx / bndstx: an MIB address (parser_parse_mem_operand);
    ; AMX's tile loads / stores too: their SIB index is the stride, so
    ; "[r12*2]" is no base and a stride of r12*2, not [r12 + r12]
    movzx   eax, word [r15 + INST_op_id]
    mov     byte [rel mem_mib], 0
    cmp     eax, 1046                      ; BNDLDX
    je      .mib
    cmp     eax, 1047                      ; BNDMK
    je      .mib
    cmp     eax, 1049                      ; BNDSTX
    je      .mib
    cmp     eax, 1693                      ; TILELOADD
    je      .mib
    cmp     eax, 1694                      ; TILELOADDT1
    je      .mib
    cmp     eax, 1696                      ; TILESTORED
    je      .mib
    cmp     eax, 7672                      ; TILELOADDRS
    je      .mib
    cmp     eax, 7673                      ; TILELOADDRST1
    jne     .mib_noted
.mib:
    mov     byte [rel mem_mib], 1
.mib_noted:

    ; Check for 0-operand instruction
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    mov     al, [rdx + TOKEN_kind]
    IF al, e, TOK_NEWLINE
        jmp     .instruction_ok
    ELSEIF al, e, TOK_EOF
        jmp     .instruction_ok
    ELSEIF al, e, TOK_COMMENT
        jmp     .instruction_ok
    ELSEIF al, e, TOK_RBRACKET
        cmp     qword [rsp + 16], 1
        je      .instruction_consume_rbracket
        ENDIF

.operand_loop:
    call    parser_parse_operand
    test    rax, rax
    jnz     .error
    test    rdx, rdx
    jz      .not_far_pointer       ; merged into the one before (", lsl #2")

    cmp     r14, 4
    jb      .slot_free
    ; "vcmppd k1, zmm2, zmm3, {sae}, 5": the {sae} before the last operand
    ; is the instruction's (INST_sae), its slot the last operand's
    cmp     r14, 4
    jne     .too_many
    cmp     byte [r15 + INST_op3 + OPERAND_kind], OP_SAE
    jne     .too_many
    cmp     byte [r15 + INST_sae], 0
    jne     .too_many
    mov     byte [r15 + INST_sae], 1
    mov     r14d, 3
    jmp     .slot_free
.too_many:
    mov     rax, EXIT_ENCODE_FAIL          ; (it was "error 210")
    jmp     .error
.slot_free:
    
    mov     r13, rdx                ; A100.5: Preserve operand pointer (RDX) before mul
    mov     rax, OPERAND_SIZE
    mul     r14
    lea     rdi, [r15 + INST_op0 + rax]
    mov     rsi, r13                ; Restore preserved pointer
    mov     rcx, OPERAND_SIZE
    rep     movsb
    
    inc     r14
    mov     [r15 + INST_nops], r14b

    ; "jmp 0x10:label" / "call SEL:label": a far pointer, segment first;
    ; the two parts become two operands, the segment marked OP_FLAG_FAR
    cmp     byte [rel far_colon], 0
    jne     .far_pointer
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .not_far_pointer
    mov     rdi, rbx
    call    preprocessor_next_token
.far_pointer:
    mov     byte [rel far_colon], 0
    cmp     r14, 1
    jne     .far_bad
    movzx   eax, byte [r15 + INST_op0 + OPERAND_kind]
    cmp     eax, OP_IMM
    je      .far_mark
    cmp     eax, OP_SYMBOL
    jne     .far_bad
.far_mark:
    or      byte [r15 + INST_op0 + OPERAND_flags], OP_FLAG_FAR
    jmp     .operand_loop
.far_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .error
.not_far_pointer:

    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        ; "imul rax," (a macro's empty last argument): the comma ends
        ; the operands, as in NASM
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
        je      .operands_end
        cmp     byte [rdx + TOKEN_kind], TOK_EOF
        je      .operands_end
        jmp     .operand_loop
        ENDIF
.operands_end:
    ; "bndstx [rax+3], bnd0, rbx", "bndldx bnd2, [3], ebx" (ICC's): the
    ; register is the address's index, as NASM encodes it
    cmp     byte [rel mem_mib], 0
    je      .mib_done
    cmp     r14, 3
    jne     .mib_done
    call    parser_mib_index
    test    rax, rax
    jnz     .error
    mov     r14d, 2
.mib_done:
    ; the complex FP16 ones (vfmaddcph, vfcmulcsh ...): a destination that is
    ; a source faults (#UD) - an error, not an instruction that cannot run
    call    parser_complex_dest
    test    rax, rax
    jnz     .error

    ; If bracketed instruction/directive, consume closing RBRACKET
    cmp     qword [rsp + 16], 1
    je      .instruction_consume_rbracket
    
.instruction_ok:
    call    parser_check_lock
    call    parser_check_hle
    call    parser_check_size              ; "inc [rax]": how big?
    test    rax, rax
    jnz     .error
    mov     rax, OK
    mov     rdx, r15
    jmp     .done

.instruction_consume_rbracket:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    IF byte [rdx + TOKEN_kind], ne, TOK_RBRACKET
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     qword [rsp + 16], 0
    jmp     .instruction_ok

.eof:
    xor     rax, rax
    xor     rdx, rdx                ; RDX=0 signals EOF to main loop
    jmp     .done

.error_no_global:
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .error

; A local label with no global label before it keeps its own name
; (".L1"), as in NASM; references to it do the same.
.local_no_global:
    call    parser_define_label
    check_err
    jmp     .get_mnemonic

.unknown_mnemonic:
    ; NASM also takes a label without its colon when an instruction or data
    ; directive follows it ("msg db 'hi'") or it is alone on the line
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .no_label
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .orphan
    cmp     eax, TOK_EOF
    je      .orphan
    cmp     eax, TOK_IDENT
    jne     .no_label
    mov     rsi, [rdx + TOKEN_value]
    call    parser_is_statement_word
    test    eax, eax
    jz      .no_label
    jmp     .colonless
.orphan:
    ; alone on its line: NASM's warning - and a misspelt instruction
    ; ("rett", "nopp") becomes a label: one letter from one, a hint
    mov     edi, WC_LABEL_ORPHAN
    call    warn_begin
    test    eax, eax
    jz      .colonless
    lea     rsi, [rel s_orphan]
    call    warn_text
    call    warn_end
    mov     rdi, [r12 + TOKEN_value]
    call    error_hint_mnemonic
    test    eax, eax
    jz      .colonless
    extern  suggest_result, error_hint_clear, warn_hint
    call    suggest_result
    cmp     rax, 1
    jbe     .orphan_hint
    call    error_hint_clear
    jmp     .colonless
.orphan_hint:
    call    warn_hint
.colonless:
    mov     rsi, [r12 + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .colonless_global
    cmp     byte [rsi + 1], '.'
    je      .colonless_define             ; "..@N_x": a macro-local
    mov     rdi, [rbx + PREP_ctx]
    mov     r14, [rdi + ASMCTX_last_global]
    test    r14, r14
    jz      .colonless_define             ; before any global label
    call    parser_concat_local_name
    mov     rsi, rdx
    jmp     .colonless_define
.colonless_global:
    mov     rdi, [rbx + PREP_ctx]
    mov     [rdi + ASMCTX_last_global], rsi
.colonless_define:
    call    parser_define_label
    check_err
    jmp     .get_mnemonic
.no_label:
    ; "[foo 0]": NASM's "unrecognized directive [foo]" (an org or a map
    ; in an object file too)
    mov     rdi, [r12 + TOKEN_value]
    extern  error_set_subject
    call    error_set_subject
    cmp     byte [rel stmt_bracketed], 0
    je      .no_label_word
    mov     rax, EXIT_BRACKET_UNKNOWN
    jmp     .done
.no_label_word:
    ; Remember the closest known instruction/directive; src/main/utasm.s prints it
    ; as a hint after the error line ("... expected, found `x'").
    call    error_hint_mnemonic
    mov     rax, EXIT_UNKNOWN_INSTR
    jmp     .done

.error:
    ; RAX already has error code
    
.done:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    epilogue

; the rest is in src/frontend/syntax/nasm/parser/, in this order:
%include "src/frontend/syntax/nasm/parser/operand.inc"
%include "src/frontend/syntax/nasm/parser/expr.inc"
%include "src/frontend/syntax/nasm/parser/memory.inc"
%include "src/frontend/syntax/nasm/parser/labels.inc"
%include "src/frontend/syntax/nasm/parser/section_attrs.inc"
%include "src/frontend/syntax/nasm/parser/checks.inc"
%include "src/frontend/syntax/nasm/parser/struc.inc"
%include "src/frontend/syntax/nasm/parser/pseudo.inc"
%include "src/frontend/syntax/nasm/parser/directives.inc"
%include "src/frontend/syntax/nasm/parser/times_align.inc"
%include "src/frontend/syntax/nasm/parser/equ.inc"
%include "src/frontend/syntax/nasm/parser/data.inc"
%include "src/frontend/syntax/nasm/parser/symbols.inc"
