;
; ============================================================================
; File        : src/core/parser.s
; Project     : utasm
; Description : Multi-Architecture Instruction Parser and Dispatch System.
; ============================================================================
;

%include "include/constant.inc"
%include "include/macro.inc"
%include "include/type.inc"

DEFAULT REL
%include "include/elf.inc"
%include "include/arch/aarch64.inc"

extern arena_alloc
extern float_encode
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
extern error_emit
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
extern parser_is_register
extern parser_lookup_mnemonic
extern parser_check_prefix
extern parser_define_label
extern parser_parse_mem_operand
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
    mov     byte [rel reloc_wrt], 0    ; no "wrt ..name" pending

    mov     rdi, [rbx + PREP_arena]

    mov     rsi, INST_SIZE
    call    arena_alloc
    check_err
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
    
    mov     al, [r12 + TOKEN_kind]
    IF al, e, TOK_EOF
        xor     rax, rax
        xor     rdx, rdx                ; RDX=0 signals EOF to main loop
        jmp     .done
        ENDIF
    IF al, e, TOK_NEWLINE
        jmp     .get_mnemonic           ; Skip empty lines
        ENDIF

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
    
    ; 3. Sync DWARF line info
    mov     rdi, [rbx + PREP_ctx]
    mov     eax, [rbx + PREP_line]
    mov     [rdi + ASMCTX_debug_line], eax
    mov     ax, [rbx + PREP_col]
    movzx   eax, ax
    mov     [rdi + ASMCTX_debug_col], eax
    
    ; 4. Lookup Mnemonic
    mov     rsi, [r12 + TOKEN_value]
    
    ; Check for prefixes (A71)
    call    parser_check_prefix
    test    rax, rax
    jz      .lookup_mnemonic
    cmp     eax, 1
    je      .get_mnemonic              ; o32 / a64 in 64-bit code: no byte
    
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
    mov     rsi, [r12 + TOKEN_value]
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
    jmp     .parse_operands

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
    
    IF r14, ge, 4
        mov     rax, 210
        jmp     .error
        ENDIF
    
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
        jmp     .operand_loop
        ENDIF
    
    ; If bracketed instruction/directive, consume closing RBRACKET
    cmp     qword [rsp + 16], 1
    je      .instruction_consume_rbracket
    
.instruction_ok:
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
    je      .colonless
    cmp     eax, TOK_EOF
    je      .colonless
    cmp     eax, TOK_IDENT
    jne     .no_label
    mov     rsi, [rdx + TOKEN_value]
    call    parser_is_statement_word
    test    eax, eax
    jz      .no_label
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
    ; Remember the closest known instruction/directive; utasm.s prints it
    ; as a hint after the error line.
    mov     rdi, [r12 + TOKEN_value]
    extern  error_set_subject
    call    error_set_subject              ; "... expected, found `x'"
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

;*
; * [parser_parse_operand]
; * Purpose: Parses an operand using the current architectural register table.
; ;
parser_parse_operand:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, OPERAND_SIZE
    call    arena_alloc
    check_err
    mov     r12, rdx
    mov     byte [r12 + OPERAND_tag], TAG_OPERAND

.fetch_operand_token:
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r13, rdx

    ; Branch-distance modifiers, recorded on the operand for the encoder:
    ; "short" forces the rel8 form; "near" and "strict" force rel32, so the
    ; encoder never shortens a branch the user sized explicitly.
    IF byte [r13 + TOKEN_kind], e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_strict]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_STRICT
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_near]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_STRICT
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_short]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_SHORT
            jmp .fetch_operand_token
            ENDIF
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_far]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_FAR
            jmp .fetch_operand_token
            ENDIF
        ENDIF

    ; "jmp SEL:offset": a name right before the colon lexes as a label;
    ; it is the far pointer's segment, the colon is noted for
    ; parser_parse_instruction
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    jne     .not_far_label
    mov     byte [r13 + TOKEN_kind], TOK_IDENT
    mov     byte [rel far_colon], 1
.not_far_label:
    mov     al, [r13 + TOKEN_kind]

    ; 0. AVX-512 rounding operand: {rn-sae}, {rd-sae}, {ru-sae}, {rz-sae}, {sae}
    IF al, e, TOK_LBRACE
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
        je      .not_rounding
        call    parser_parse_decorator
        check_err
        cmp     byte [r12 + OPERAND_kind], OP_ROUNDING
        je      .success
        cmp     byte [r12 + OPERAND_kind], OP_SAE
        je      .success
        mov     rax, EXIT_INVALID_EXPR     ; {k1}/{z}/{1toN} must follow an operand
        jmp     .error
.not_rounding:
        mov     al, [r13 + TOKEN_kind]
        ENDIF

    ; 1. Memory Operands [base + index*scale + disp]
    IF al, e, TOK_LBRACKET
        call    parser_parse_mem_operand
        check_err
        jmp     .success
        ENDIF

    ; 2. Registers or Size Specifiers (handled via ident lookup)
    IF al, e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        call    parser_parse_size_specifier_string
        test    rax, rax
        jz      .try_register
        
        ; Size specifier logic
        mov     [r12 + OPERAND_size], al
        mov     [r12 + OPERAND_xsize], ax      ; yword/zword need 16 bits
        
        ; Peek next token. If "ptr", consume
        mov     rdi, rbx
        call    preprocessor_peek_token
        mov     rcx, rdx
        IF byte [rcx + TOKEN_kind], e, TOK_IDENT
            mov     rdi, [rcx + TOKEN_value]
            lea     rsi, [rel str_ptr]
            call    str_cmp_kw
            test    rax, rax
            jnz     .no_ptr
            mov     rdi, rbx
            call    preprocessor_next_token ; consume "ptr"
.no_ptr:
            ENDIF
            
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     r13, rdx
        cmp     byte [r13 + TOKEN_kind], TOK_LBRACKET
        je      .sized_mem
        ; A register with its size written out ("movzx r9d, byte al"): the
        ; size must be the register's. Anything else is a sized immediate.
        cmp     byte [r13 + TOKEN_kind], TOK_IDENT
        jne     .expression
        movzx   eax, word [r12 + OPERAND_xsize]
        push    rax
        call    parser_get_arch_tables
        mov     rdi, rdx
        mov     rsi, [r13 + TOKEN_value]
        call    parser_parse_reg_info
        pop     rcx
        cmp     rax, ERR
        je      .expression                ; a symbol: "dword SIZE_CONST"
        ; a segment register's size is ignored, as NASM does ("push dword
        ; fs" is push fs)
        movzx   eax, byte [r12 + OPERAND_reg]
        sub     eax, 24
        cmp     eax, 5
        jbe     .sized_reg
        cmp     cx, [r12 + OPERAND_xsize]
        jne     .sized_bad
.sized_reg:
        mov     byte [r12 + OPERAND_kind], OP_REG
        jmp     .success
.sized_bad:
        mov     rax, EXIT_REG_SIZE         ; the size does not match the register
        jmp     .error
.sized_mem:
        call    parser_parse_mem_operand
        check_err
        jmp     .success
        
.try_register:
        call    parser_get_arch_tables
        mov     rdi, rdx                ; RDI = Register Table Pointer
        mov     rsi, [r13 + TOKEN_value]
        call    parser_parse_reg_info
        IF rax, ne, ERR
            mov     byte [r12 + OPERAND_kind], OP_REG
            jmp     .success
            ENDIF

        ; Not a register, fall through to expression (it's a symbol)
        ; BUT FIRST: check for AArch64 shift keywords
        mov     rax, [rbx + PREP_ctx]
        cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
        jne     .not_shift
        
        mov     rdi, [r13 + TOKEN_value]
        call    parser_check_aarch64_shift
        IF rax, ne, ERR
            ; It's a shift! (RAX = SHIFT_*)
            mov     [r12 + OPERAND_shift_type], al
            ; Expect TOK_HASH or just expression
            mov     rdi, rbx
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_HASH
                mov     rdi, rbx
                call    preprocessor_next_token
                ENDIF
            mov     rdi, rbx
            call    parser_evaluate_expression
            check_err
            mov     [r12 + OPERAND_shift_imm], dl
            ; This shift applies to the PREVIOUS register operand if this was just "lsl #1"
            ; But usually it's "x2, lsl #1". The parser sees "x2" as op2, then "lsl" as op3.
            ; Wait, our parser handles operands separated by commas.
            ; "add x0, x1, x2, lsl #1" => 4 operands.
            ; The encoder for ADD expects 3 operands, where op2 might have a shift.
            ; So I should actually "merge" this shift into the previous operand.
            movzx   rax, byte [r15 + INST_nops]
            IF al, g, 0
                dec al
                imul rax, OPERAND_SIZE
                lea  rdi, [r15 + INST_op0 + rax]
                mov  cl, [r12 + OPERAND_shift_type]
                mov  [rdi + OPERAND_shift_type], cl
                mov  cl, [r12 + OPERAND_shift_imm]
                mov  [rdi + OPERAND_shift_imm], cl
                
                ; Discard this temporary operand
                xor  rax, rax
                epilogue
                ENDIF
                ENDIF

.not_shift:
        ENDIF

    ; 3. Expressions (Numbers, Symbols, Math)
.expression:
    mov     rdi, rbx
    mov     rsi, r13
    call    preprocessor_putback_token

    push    qword [rel known_fwd_uses]
    mov     rdi, rbx
    call    parser_evaluate_expression
    pop     r8
    cmp     r8, [rel known_fwd_uses]
    je      .not_fwd
    mov     byte [r12 + OPERAND_fwd], 1    ; (encoder.s: NASM's pass 1)
.not_fwd:
    test    rax, rax
    IF z
        mov     byte [r12 + OPERAND_kind], OP_IMM
        mov     [r12 + OPERAND_imm], rdx
        ; If the expression involved symbols, we mark it.
        ; rcx = forward reference (raw name), r11 = already-defined SYMBOL*.
        IF rcx, ne, 0
             mov     byte [r12 + OPERAND_kind], OP_SYMBOL
             mov     [r12 + OPERAND_sym], rcx
        ELSEIF r11, ne, 0
             ; Already-defined symbol: the value is usable as an immediate,
             ; but record the symbol so branches can still emit a relocation.
             mov     [r12 + OPERAND_sym], r11
             ENDIF
        jmp     .success
        ENDIF

    ; not an operand: the expression evaluator's code says why
    jmp     .error

.success:
    ; AVX-512 decorators after a register or memory operand: {k1} {z} {1to16}
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_target], TARGET_AARCH64
    je      .decorated
.decorator:
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_LBRACE
    jne     .decorated
    mov     rdi, rbx
    call    preprocessor_next_token        ; consume '{'
    call    parser_parse_decorator
    check_err
    jmp     .decorator
.decorated:
    mov     rdx, r12
    mov     rax, OK
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_parse_reg_info]
; * Input: RSI = Name String, RDI = Table Pointer, R12 = OPERAND Pointer
; * Output: AL = Reg ID, RAX = ERR if not found
; ;
parser_parse_reg_info:
    prologue
    push    rdi
    call    parser_is_register
    pop     rdi
    IF rax, e, ERR
        epilogue
        ENDIF
    
    ; RAX: bit 16 = is_high, bits 8-15 = size_in_bytes, bits 0-7 = reg_id
    mov     [r12 + OPERAND_reg], al
    
    mov     rcx, rax
    shr     rcx, 8
    and     ecx, 0x7F           ; Size in bytes
    shl     ecx, 3              ; Convert to bits
    mov     [r12 + OPERAND_size], cl
    mov     [r12 + OPERAND_xsize], cx      ; ymm/zmm: 256/512 need 16 bits
    
    shr     rax, 16
    and     al, 1
    mov     [r12 + OPERAND_is_high], al
    
    mov     rax, OK
    epilogue

;*
; * [parser_evaluate_additive]
; * Purpose: Additive level (+ -)
; ;
%define EXPR_COEFF_LIMIT (1 << 20)
%define EXPR_NONLINEAR   (1 << 40)      ; a value not linear in $
parser_evaluate_additive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                ; [rsp] = the position coefficient

    mov     rbx, rdi               ; RBX = PrepState

    mov     rdi, rbx
    call    parser_evaluate_term
    check_err
    mov     r13, rdx               ; R13 = current running total
    mov     r14, rcx               ; R14 = deferred symbol name (optional)
    mov     r15, r11               ; R15 = resolved SYMBOL* (optional)
    mov     rax, [rel expr_coeff]
    mov     [rsp], rax

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]

    IF al, e, TOK_PLUS
        mov     rdi, rbx
        call    preprocessor_next_token

        ; A register name is never a term in an expression. It appears here
        ; only in an address like [table + rcx], where it belongs to the
        ; memory operand, so stop and leave it for the caller to consume.
        mov     rdi, rbx
        call    preprocessor_peek_token
        IF byte [rdx + TOKEN_kind], e, TOK_IDENT
            mov     r12, [rdx + TOKEN_value]
            call    parser_get_arch_tables
            mov     rdi, rdx               ; register table
            mov     rsi, r12
            call    parser_is_register
            IF rax, ne, ERR
                jmp .stop
                ENDIF
            ENDIF

        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        add     r13, rdx
        jo      .overflow
        mov     rdi, [rsp]
        mov     rsi, [rel expr_coeff]
        call    expr_coeff_sum
        mov     [rsp], rax
        ; "1 + label", "CONST + label": the label is the right-hand term's
        test    r14, r14
        jnz     .loop
        test    r15, r15
        jz      .plus_adopt
        cmp     word [r15 + SYMBOL_section], SHN_ABS
        jne     .loop
.plus_adopt:
        mov     rax, rcx
        or      rax, r11
        jz      .loop                      ; a number: the left one stays
        mov     r14, rcx
        mov     r15, r11
        jmp     .loop
    ELSEIF al, e, TOK_MINUS
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        mov     rsi, [rel expr_coeff]
        neg     rsi
        mov     rdi, [rsp]
        call    expr_coeff_sum
        mov     [rsp], rax

        sub     r13, rdx
        jo      .overflow

        ; the right operand a number ("label - 4", "x - CONST"): the left
        ; one's symbol stays
        test    rcx, rcx
        jnz     .minus_symbol
        test    r11, r11
        jz      .loop
        cmp     word [r11 + SYMBOL_section], SHN_ABS
        je      .loop
.minus_symbol:

        ; "later - $$", "end - start" with a label not defined yet: the
        ; distance is only known at the end. It is recorded under a name
        ; holding both labels (RELOC_OFFSET_MARK, parser_offset_name) and
        ; the relocation pass writes it in place, after jumps are
        ; shortened - so nothing has to keep its size for it.
        mov     rax, r14
        or      rax, rcx
        jz      .not_offset                ; both defined: a number now
        test    r14, r14
        jz      .off_left_sym
        cmp     byte [r14], RELOC_OFFSET_MARK
        je      .not_offset                ; already a distance
        mov     rdi, r14                   ; A: not defined yet
        jmp     .off_right
.off_left_sym:
        test    r15, r15
        jz      .not_offset
        cmp     word [r15 + SYMBOL_section], SHN_ABS
        je      .not_offset
        mov     rdi, [r15 + SYMBOL_name]   ; A: defined; its value leaves
        sub     r13, [r15 + SYMBOL_value]  ; the constant part
.off_right:
        test    rcx, rcx
        jz      .off_right_sym
        cmp     byte [rcx], RELOC_OFFSET_MARK
        je      .not_offset
        mov     rsi, rcx                   ; B: not defined yet
        jmp     .off_name
.off_right_sym:
        mov     rsi, [r11 + SYMBOL_name]   ; B: defined
        add     r13, [r11 + SYMBOL_value]
.off_name:
        call    parser_offset_name
        test    rax, rax
        jnz     .error
        mov     r14, rdx
        xor     r15d, r15d
        jmp     .loop
.not_offset:

        ; "b - a", both labels of one section: the distance is a number now,
        ; so the code between them must keep its size (a frozen range,
        ; optimizer/jump.s). Anything else freezes the sections involved.
        test    r14, r14
        jnz     .diff_other
        test    rcx, rcx
        jnz     .diff_other
        test    r15, r15
        jz      .diff_other
        test    r11, r11
        jz      .diff_other
        movzx   eax, word [r15 + SYMBOL_section]
        cmp     ax, [r11 + SYMBOL_section]
        jne     .diff_other
        test    eax, eax
        jz      .diff_other                ; not defined
        cmp     eax, 0xFF00
        jae     .diff_other                ; SHN_ABS, SHN_COMMON ...
        mov     rdx, [rbx + PREP_ctx]
        movzx   r8d, word [rdx + ASMCTX_seccount]
        cmp     eax, r8d
        ja      .diff_other
        mov     rdx, [rdx + ASMCTX_sections]
        mov     rdi, [rdx + rax*8 - 8]     ; the index is 1-based
        mov     rsi, [r15 + SYMBOL_value]
        mov     rdx, [r11 + SYMBOL_value]
        call    relax_freeze_range
        extern  known_note_diff
        call    known_note_diff            ; (core/known.s: "len equ $ - msg")
        jmp     .diff_number
.diff_other:
        push    rdi
        push    rsi
        mov     rdi, r11
        mov     rsi, rcx
        call    relax_freeze_symref
        mov     rdi, r15
        mov     rsi, r14
        call    relax_freeze_symref
        pop     rsi
        pop     rdi
.diff_number:
        ; "label_b - label_a" is an absolute constant: the two references
        ; cancel out. Carrying a symbol onward would make the encoder emit a
        ; relocation that overwrites the difference we just computed.
        xor     r14, r14
        xor     r15, r15
        jmp     .loop
        ENDIF

.stop:
    mov     rdx, r13
    xor     rax, rax

.done:
.error:
    mov     rcx, [rsp]
    mov     [rel expr_coeff], rcx  ; how the value moves with $
    mov     rcx, r14               ; carry the symbol info to the caller
    mov     r11, r15
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.overflow:
    mov     rax, EXIT_IMM_RANGE
    jmp     .error

;*
; * [expr_coeff_sum]
; * Purpose: Adds two position coefficients (expr_coeff): how much a value
; *   grows when $ grows by one. Past +-2^20 a value is not linear in $
; *   (EXPR_NONLINEAR), and stays so.
; * Input  : RDI, RSI. Output: RAX. Clobbers nothing else.
; ;
expr_coeff_sum:
    mov     rax, rdi
    add     rax, EXPR_COEFF_LIMIT
    cmp     rax, 2 * EXPR_COEFF_LIMIT
    ja      .nonlinear
    mov     rax, rsi
    add     rax, EXPR_COEFF_LIMIT
    cmp     rax, 2 * EXPR_COEFF_LIMIT
    ja      .nonlinear
    lea     rax, [rdi + rsi]
    ret
.nonlinear:
    mov     rax, EXPR_NONLINEAR
    ret

;*
; * [expr_combine]
; * Purpose: Two operands joined by an operator other than + and - (* / %
; *   << >> & | ^ comparisons): the result is a plain number. A label in
; *   either is a position used as a number, which freezes its section;
; *   the coefficient is 0, or EXPR_NONLINEAR when either depended on $.
; * Input  : RDI = left SYMBOL* (or 0), RSI = left deferred name (or 0),
; *          RDX = left coefficient; right: R11, RCX, expr_coeff
; * Output : expr_coeff, RAX = the new coefficient. Preserves the others.
; ;
expr_combine:
    push    rdi
    push    rsi
    call    relax_freeze_symref
    mov     rdi, r11
    mov     rsi, rcx
    call    relax_freeze_symref
    pop     rsi
    pop     rdi
    xor     eax, eax
    test    rdx, rdx
    jnz     .nonlinear
    cmp     qword [rel expr_coeff], 0
    je      .set
.nonlinear:
    mov     rax, EXPR_NONLINEAR
.set:
    mov     [rel expr_coeff], rax
    ret

; expr_coeff_taint: after ~ or !, a value that depended on $ no longer
; does so linearly. Preserves every register.
expr_coeff_taint:
    cmp     qword [rel expr_coeff], 0
    je      .ret
    push    rax
    mov     rax, EXPR_NONLINEAR
    mov     [rel expr_coeff], rax
    pop     rax
.ret:
    ret

;*
; * [parser_disp_size_word]
; * Purpose: byte / word / dword / qword inside brackets, in any case.
; * Input  : RDI = word
; * Output : EAX = 8, 16, 32, 64, or 0 when it is none of them
; ;
parser_disp_size_word:
    push    r12
    mov     r12, rdi
    lea     rsi, [rel str_byte]
    call    str_cmp_kw
    mov     edx, 8
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_word]
    call    str_cmp_kw
    mov     edx, 16
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_dword]
    call    str_cmp_kw
    mov     edx, 32
    test    rax, rax
    jz      .hit
    mov     rdi, r12
    lea     rsi, [rel str_qword]
    call    str_cmp_kw
    mov     edx, 64
    test    rax, rax
    jz      .hit
    xor     edx, edx
.hit:
    mov     eax, edx
    pop     r12
    ret

;*
; * [parser_offset_name]
; * Purpose: The name an "A - B" distance is recorded under when A or B is
; *   not defined yet: RELOC_OFFSET_MARK, A, RELOC_OFFSET_MARK, B (reloc.s
; *   resolves it once both are).
; * Input  : RDI = A's name, RSI = B's name, RBX = PrepState
; * Output : RAX = OK or error, RDX = the marked name
; ;
parser_offset_name:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r14, rsi
    call    str_len
    mov     r13, rax
    mov     rdi, r14
    call    str_len
    mov     r15, rax
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r13 + r15 + 3]
    call    arena_alloc                    ; zeroed: the NUL is there
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     byte [rdi], RELOC_OFFSET_MARK
    inc     rdi
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    mov     byte [rdi], RELOC_OFFSET_MARK
    inc     rdi
    mov     rsi, r14
    mov     rcx, r15
    rep movsb
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_evaluate_expression]
; * Purpose: Entry point for expression evaluation: the binary levels
; *   (parser_eval_level), then cond ? a : b.
; ;
global parser_evaluate_expression
parser_evaluate_expression:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r10, [rbx + PREP_ctx]
    inc     dword [r10 + ASMCTX_expr_depth]
    cmp     dword [r10 + ASMCTX_expr_depth], 64
    jg      .too_deep
    mov     rdi, rbx
    xor     esi, esi
    call    parser_eval_level
    mov     r10, [rbx + PREP_ctx]
    dec     dword [r10 + ASMCTX_expr_depth]
    check_err_to .done
    mov     r13, rdx               ; R13 = accumulated value
    mov     r12, rcx               ; R12 = deferred symbol name (optional)
    mov     r14, r11               ; R14 = resolved SYMBOL* (optional)

    ; "sym wrt ..plt" (..gotpcrel, ..got, ..gotoff, ..tlsie, ..sym): the
    ; relocation the reference gets
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ternary
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_wrt]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ternary
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel wrt_words]
    call    parser_word_index
    test    eax, eax
    jz      .wrt_bad
    imul    eax, eax, 12
    lea     rcx, [rel wrt_words]
    movzx   eax, byte [rcx + rax - 1]      ; the row's WRT_*
    mov     [rel reloc_wrt], al
    jmp     .ternary
.wrt_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .done
.too_deep:
    dec     dword [r10 + ASMCTX_expr_depth]
    mov     rax, EXIT_EXPR_TOO_DEEP
    jmp     .done
.ternary:


    ; cond ? a : b, the lowest precedence as in NASM
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_QUESTION
    jne     .no_ternary
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression     ; the "then" value
    check_err_to .done
    push    rdx
    push    rcx
    push    r11
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .ternary_bad
    mov     rdi, rbx
    call    parser_evaluate_expression     ; the "else" value
    test    rax, rax
    jnz     .ternary_err
    test    r13, r13
    jz      .ternary_else
    pop     r11
    pop     rcx
    pop     rdx
    xor     rax, rax
    jmp     .done
.ternary_else:
    add     rsp, 24
    xor     rax, rax
    jmp     .done
.ternary_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN     ; "?" without its ":"
.ternary_err:
    add     rsp, 24
    jmp     .done

.no_ternary:
    mov     rdx, r13
    mov     rcx, r12
    mov     r11, r14
    xor     rax, rax

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

%define EVAL_LAST_LEVEL 7
%define EOP_LOR   1
%define EOP_LXOR  2
%define EOP_LAND  3
%define EOP_EQ    4
%define EOP_NE    5
%define EOP_LT    6
%define EOP_LE    7
%define EOP_GT    8
%define EOP_GE    9
%define EOP_CMP3  10
%define EOP_OR    11
%define EOP_XOR   12
%define EOP_AND   13
%define EOP_SHL   14
%define EOP_SHR   15
%define EOP_SAR   16

;*
; * [parser_eval_level]
; * Purpose: One binary-operator level of NASM's precedence, lowest first:
; *     0 ||    1 ^^    2 &&    3 = == != <> < <= > >= <=>
; *     4 |     5 ^     6 &     7 << >> <<< >>>
; *   then + - (parser_evaluate_additive), * / % %% (parser_evaluate_term)
; *   and the unary operators (parser_evaluate_factor). Left-associative.
; *   A value that went through an operator here is a plain number; one
; *   that did not keeps its symbol for the caller.
; * Input  : RDI = PrepState, ESI = level
; * Output : RAX = OK or an error, RDX = value, RCX / R11 = symbol info
; ;
parser_eval_level:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32                ; [rsp] = level, [rsp + 8] = SYMBOL*,
                                   ; [rsp + 16] = position coefficient
    mov     rbx, rdi
    mov     eax, esi
    mov     [rsp], rax
    mov     rdi, rbx
    call    parser_eval_next
    test    rax, rax
    jnz     .ret
    mov     r12, rdx               ; running value
    mov     r13, rcx               ; deferred symbol name
    mov     [rsp + 8], r11         ; resolved SYMBOL*
    mov     r8, [rel expr_coeff]
    mov     [rsp + 16], r8
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     rcx, [rsp]
    shl     rcx, 4
    lea     r8, [rel eval_level_ops]
    add     r8, rcx
.find:
    movzx   ecx, byte [r8]
    test    ecx, ecx
    jz      .no_op
    cmp     eax, ecx
    je      .found
    add     r8, 2
    jmp     .find
.found:
    movzx   r15d, byte [r8 + 1]    ; the operation
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    mov     rsi, [rsp]
    call    parser_eval_next
    test    rax, rax
    jnz     .ret
    ; a plain number now; a label in it was a position used as a number
    mov     r8, [rsp + 16]
    mov     rdi, [rsp + 8]
    mov     rsi, r13
    call    expr_combine
    mov     [rsp + 16], rax
    xor     eax, eax
    xor     ecx, ecx
    cmp     r15d, EOP_LOR
    je      .lor
    cmp     r15d, EOP_LXOR
    je      .lxor
    cmp     r15d, EOP_LAND
    je      .land
    cmp     r15d, EOP_EQ
    je      .eq
    cmp     r15d, EOP_NE
    je      .ne
    cmp     r15d, EOP_LT
    je      .lt
    cmp     r15d, EOP_LE
    je      .le
    cmp     r15d, EOP_GT
    je      .gt
    cmp     r15d, EOP_GE
    je      .ge
    cmp     r15d, EOP_CMP3
    je      .cmp3
    cmp     r15d, EOP_OR
    je      .bor
    cmp     r15d, EOP_XOR
    je      .bxor
    cmp     r15d, EOP_AND
    je      .band
    mov     rcx, rdx
    and     ecx, 63                ; shift count
    cmp     r15d, EOP_SHL
    je      .shl
    cmp     r15d, EOP_SHR
    je      .shr
    sar     r12, cl                ; EOP_SAR
    jmp     .applied
.lor:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    or      al, cl
    jmp     .bool
.lxor:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    xor     al, cl
    jmp     .bool
.land:
    test    r12, r12
    setne   al
    test    rdx, rdx
    setne   cl
    and     al, cl
    jmp     .bool
.eq:
    cmp     r12, rdx
    sete    al
    jmp     .bool
.ne:
    cmp     r12, rdx
    setne   al
    jmp     .bool
.lt:
    cmp     r12, rdx
    setl    al
    jmp     .bool
.le:
    cmp     r12, rdx
    setle   al
    jmp     .bool
.gt:
    cmp     r12, rdx
    setg    al
    jmp     .bool
.ge:
    cmp     r12, rdx
    setge   al
    jmp     .bool
.cmp3:
    cmp     r12, rdx
    setg    al
    setl    cl
    sub     al, cl                 ; -1, 0 or 1
    movsx   r12, al
    jmp     .applied
.bool:
    movzx   r12d, al
    jmp     .applied
.bor:
    or      r12, rdx
    jmp     .applied
.bxor:
    xor     r12, rdx
    jmp     .applied
.band:
    and     r12, rdx
    jmp     .applied
.shl:
    shl     r12, cl
    jmp     .applied
.shr:
    shr     r12, cl
.applied:
    xor     r13d, r13d             ; a plain number now
    mov     qword [rsp + 8], 0
    jmp     .loop
.no_op:
    mov     rdx, r12
    mov     rcx, r13
    mov     r11, [rsp + 8]
    mov     r8, [rsp + 16]
    mov     [rel expr_coeff], r8
    xor     eax, eax
.ret:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; The level above ESI: the next binary level, or + - after the last one.
parser_eval_next:
    cmp     esi, EVAL_LAST_LEVEL
    jae     parser_evaluate_additive
    inc     esi
    jmp     parser_eval_level


[SECTION .rodata]
; per level, 16 bytes: (token kind, operation) pairs ending in 0
eval_level_ops:
    db TOK_OR, EOP_LOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_LXOR, EOP_LXOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_AND, EOP_LAND, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_EQUAL, EOP_EQ, TOK_NEQUAL, EOP_NE, TOK_LT, EOP_LT, TOK_LE, EOP_LE
    db TOK_GT, EOP_GT, TOK_GE, EOP_GE, TOK_CMP3, EOP_CMP3, 0, 0
    db TOK_PIPE, EOP_OR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_CARET, EOP_XOR, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_AMPERSAND, EOP_AND, 0, 0,0,0,0,0,0,0,0,0,0,0,0,0
    db TOK_LSHIFT, EOP_SHL, TOK_RSHIFT, EOP_SHR, TOK_SAR, EOP_SAR, 0, 0,0,0,0,0,0,0,0,0
[SECTION .text]

;*
; * [parser_evaluate_term]
; * Purpose: Multiplicative level: * / % (unsigned, as in NASM) and %%
; *   (signed modulo). utasm reads "//" as a comment, so NASM's signed
; *   division operator is not available.
; ;
parser_evaluate_term:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                ; [rsp] = resolved SYMBOL* of the left operand
    mov     rbx, rdi               ; RBX = PrepState

    mov     rdi, rbx
    call    parser_evaluate_factor
    check_err
    mov     r12, rdx               ; R12 = running total
    mov     r15, rcx               ; R15 = deferred symbol name (optional)
    mov     [rsp], r11             ; resolved SYMBOL* (optional)
    mov     rax, [rel expr_coeff]
    mov     [rsp + 8], rax         ; position coefficient

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    mov     r13, rdx               ; R13 = peeked token pointer
    mov     al, [r13 + TOKEN_kind]
    
    IF al, e, TOK_STAR
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        call    .combine
        ; Multiplication wraps modulo 2^64 rather than erroring: hash
        ; constructions such as FNV-1a rely on it, including the
        ; compile_time_hash tables in backend/isa/*.s.
        imul    r12, rdx
        jmp     .loop
    ELSEIF al, e, TOK_SLASH
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        call    .combine
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx           ; R14 = divisor
        mov     rax, r12           ; RAX = dividend
        xor     edx, edx           ; unsigned, as NASM's /
        div     r14
        mov     r12, rax
        jmp     .loop
    ELSEIF al, e, TOK_DPERCENT
        ; %% : signed modulo
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        call    .combine
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx
        mov     rax, r12
        cqo
        idiv    r14
        mov     r12, rdx
        jmp     .loop
    ELSEIF al, e, TOK_PERCENT
        ; modulo, unsigned as NASM's %
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        call    .combine
        test    rdx, rdx
        jz      .div_zero
        mov     r14, rdx
        mov     rax, r12
        xor     edx, edx
        div     r14
        mov     r12, rdx
        jmp     .loop
        ENDIF
    
    mov     rdx, r12
    xor     rax, rax
    jmp     .done

; the operands of * / % %%: a plain number from here on
.combine:
    mov     r8, [rsp + 16]
    mov     rdi, [rsp + 8]
    mov     rsi, r15
    call    expr_combine
    mov     [rsp + 16], rax
    mov     qword [rsp + 8], 0
    xor     r15d, r15d
    ret

.error:
    ; RAX already has the error code from check_err
.done:
    push    rax
    mov     rax, [rsp + 16]
    mov     [rel expr_coeff], rax
    pop     rax
    mov     rcx, r15               ; carry the symbol info to the caller
    mov     r11, [rsp]
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.overflow:
    mov     rax, EXIT_IMM_RANGE
    jmp     .done

.div_zero:
    mov     rax, EXIT_INVALID_IMM
    jmp     .done

;*
; * [parser_evaluate_factor]
; * Purpose: Primary level (Numbers, Symbols, Parens)
; ;
parser_evaluate_factor:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; RBX = PrepState

    ; Symbol outputs default to "none"; only the identifier path sets them.
    ; They live in preserved registers so the calls below cannot corrupt them.
    xor     r14, r14               ; deferred symbol name -> rcx
    xor     r15, r15               ; resolved SYMBOL*    -> r11
    mov     qword [rel expr_coeff], 0      ; independent of $ (but $ itself)

    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_MINUS
        ; "-1.5" in a data directive: a negative floating-point constant
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_FLOAT
        jne     .negate
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     r12, rdx
        mov     esi, 1
        jmp     .float
.negate:
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        neg     rdx
        neg     qword [rel expr_coeff]
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_TILDE
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        not     rdx
        call    expr_coeff_taint
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_PLUS
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     r14, rcx               ; +x keeps x's symbol
        mov     r15, r11
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_NOT
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        call    expr_coeff_taint
        test    rdx, rdx
        sete    dl
        movzx   edx, dl
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_QUESTION
        ; "db ?": an uninitialised item, zero here
        xor     edx, edx
        xor     rax, rax
        jmp     .done
        ENDIF

    ; A floating-point constant, in the format float_fmt names (dw/dd/dq/dt
    ; or __floatNN__ set it); anywhere else it is an error, as in NASM
    cmp     al, TOK_FLOAT
    jne     .not_float
    xor     esi, esi
.float:
    movzx   edx, byte [rel float_fmt]
    test    edx, edx
    jz      .float_bad
    mov     rdi, [r12 + TOKEN_value]
    call    float_encode
    check_err
    mov     [rel float_hi], rcx
    mov     byte [rel float_seen], 1
    xor     eax, eax
    jmp     .done
.float_bad:
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .done
.not_float:
    ; __float16__(x) / __float32__(x) / __float64__(x): the bits as a number
    cmp     al, TOK_IDENT
    jne     .not_float_fn
    ; __Infinity__, __QNaN__, __SNaN__: floats, where one goes
    cmp     byte [rel float_fmt], 0
    je      .not_special
    mov     rdi, [r12 + TOKEN_value]
    call    parser_float_special
    test    eax, eax
    jz      .not_special
    lea     esi, [rax - 1]
    movzx   edx, byte [rel float_fmt]
    extern  float_special
    call    float_special
    mov     [rel float_hi], rcx
    mov     byte [rel float_seen], 1
    xor     eax, eax
    jmp     .done
.not_special:
    mov     rdi, [r12 + TOKEN_value]
    call    parser_float_func
    test    eax, eax
    jz      .not_float_fn_ident
    movzx   r13d, byte [rel float_fmt]     ; the enclosing directive's
    mov     [rel float_part], al           ; FLT_HIGH: the high part
    and     al, 0x7F
    mov     [rel float_fmt], al
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .float_fn_end
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .float_fn_bad
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .float_fn_end
    mov     [rel float_fn_val], rdx
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .float_fn_end
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .float_fn_bad
    mov     rdx, [rel float_fn_val]
    test    byte [rel float_part], FLT_HIGH
    jz      .float_fn_low
    mov     rdx, [rel float_hi]            ; __float80e__ / __float128h__
.float_fn_low:
    mov     byte [rel float_seen], 0       ; a plain number from here on
    xor     eax, eax
    jmp     .float_fn_end
.float_fn_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.float_fn_end:
    mov     [rel float_fmt], r13b
    jmp     .done
.not_float_fn_ident:
    mov     al, TOK_IDENT
.not_float_fn:

    IF al, e, TOK_NUMBER
        ; "1f" / "1b": a numeric label reference, looked up like a symbol
        mov     rdi, [r12 + TOKEN_value]
        call    parser_numlabel_ref
        test    rsi, rsi
        jnz     .do_sym_lookup
        mov     rdi, [r12 + TOKEN_value]
        call    str_to_int
        check_err
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_CHAR
        mov     rdx, [r12 + TOKEN_value]
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_DOLLAR
        ; Current location counter ($) or the section's start ($$): a label
        ; at that point. Used as a number only in a difference ("$ - $$"),
        ; which freezes the code between them, or in arithmetic that
        ; freezes the section (expr_combine).
        mov     rax, [rbx + PREP_ctx]
        mov     rax, [rax + ASMCTX_curr_sec]
        IF rax, e, 0
            ; If no section, return 0 (or error?)
            xor rax, rax
            jmp     .done
            ENDIF
        ; "$$" arrives as two '$' tokens
        xor     r13d, r13d
        mov     rdi, rbx
        call    preprocessor_peek_token
        check_err
        cmp     byte [rdx + TOKEN_kind], TOK_DOLLAR
        jne     .pos_label
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     r13d, 1
.pos_label:
        mov     edi, r13d
        call    parser_pos_label
        check_err
        mov     r15, rdx                   ; a defined label, as for an identifier
        mov     rdx, [rdx + SYMBOL_value]
        test    r13d, r13d
        jnz     .pos_start
        mov     qword [rel expr_coeff], 1  ; $ moves with itself
.pos_start:
        inc     qword [rel known_pos_uses]  ; a position (core/known.s)
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_IDENT
        ; Check if local label reference (starts with '.')
        mov     rsi, [r12 + TOKEN_value]
        mov     r10, [rbx + PREP_ctx]
        cmp     byte [rsi], '.'
        jne     .do_sym_lookup
        cmp     byte [rsi + 1], '.'
        je      .do_sym_lookup         ; "..@N_x" is a macro-local, not a local label
        mov     r13, [r10 + ASMCTX_last_global]
        test    r13, r13
        jz      .do_sym_lookup
        push    r14                    ; r14 carries the deferred symbol name
        mov     r14, r13               ; concat_local_name takes the global in r14
        call    parser_concat_local_name
        pop     r14
        mov     rsi, rdx               ; namespaced name

.do_sym_lookup:
        ; Symbol lookup
        mov     rdi, [rbx + PREP_ctx]
        extern  symbol_find
        call    symbol_find
        IF rax, e, OK
            ; an entry not defined yet (named by global, or by a reference
            ; before): the second pass may know it as a constant
            cmp     word [rdx + SYMBOL_section], 0
            jne     .sym_defined
            push    rdx
            inc     qword [rel known_fwd_uses]
            call    known_lookup
            test    rax, rax
            jz      .sym_unknown
            add     rsp, 8
            xor     r15d, r15d             ; a plain number
            xor     r14d, r14d
            xor     eax, eax
            jmp     .done
.sym_unknown:
            call    known_note_forward     ; (pass 1: noted)
            pop     rdx
.sym_defined:
            mov     r15, rdx               ; return SYMBOL* in r11 (A78)
            ; a position (a label, or an equ derived from one) in an equ
            ; makes it depend on the layout (core/known.s)
            cmp     word [rdx + SYMBOL_section], SHN_ABS
            jne     .pos_use
            test    byte [rdx + SYMBOL_pflags], SYMF_POSDEP
            jz      .pos_none
.pos_use:
            extern  known_pos_uses
            inc     qword [rel known_pos_uses]
.pos_none:
            mov     rdx, [rdx + SYMBOL_value]
            xor     rax, rax
            ELSE
            ; not defined yet: the second pass knows it if it is a
            ; constant (core/known.s), the first notes it
            extern  known_lookup, known_note_forward
            inc     qword [rel known_fwd_uses]     ; (NASM: unknown in pass 1)
            call    known_lookup
            test    rax, rax
            jz      .unknown_yet
            xor     r15d, r15d             ; a plain number
            xor     r14d, r14d
            xor     eax, eax
            jmp     .done
.unknown_yet:
            call    known_note_forward
            inc     qword [rel known_pos_uses]
            ; Deferred symbol (R_ABS64 reloc)
            mov     rdx, 0
            xor     r15, r15               ; no symbol metadata yet
            mov     r14, rsi               ; return namespaced symbol name in RCX
            xor     rax, rax
            ENDIF
        jmp     .done
    ELSEIF al, e, TOK_LPAREN
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
        mov     r14, rcx               ; carry the inner symbol info outward
        mov     r15, r11
        mov     r13, rdx
        mov     rdi, rbx
        call    preprocessor_next_token
        IF byte [rdx + TOKEN_kind], ne, TOK_RPAREN
            mov rax, EXIT_UNEXPECTED_TOKEN
            jmp     .done
            ENDIF
        mov     rdx, r13
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_COLON
        call    parser_handle_reloc_modifier
        check_err_to .error
        IF rax, ne, OK
            jmp .error
        ENDIF
        jmp     .done
        ENDIF
    
    mov     rax, EXIT_INVALID_EXPR
    jmp     .error

.error:
.done:
    mov     rcx, r14               ; deferred symbol name (0 if none)
    mov     r11, r15               ; resolved SYMBOL*     (0 if none)
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_handle_reloc_modifier]
; ;
parser_handle_reloc_modifier:
    prologue
    push    rbx
    push    r12
    push    r14
    
    call    preprocessor_next_token
    check_err_to .error
    mov     r12, rdx
    IF byte [r12 + TOKEN_kind], ne, TOK_IDENT
        mov rax, EXIT_UNEXPECTED_TOKEN
        jmp .error
        ENDIF
    
    mov     rdi, [r12 + TOKEN_value]
    xor     r14, r14
    
    ; Simple check for :lo12: and :pg_hi21:
    mov     eax, [rdi]
    IF eax, e, 'lo12'
        mov r14d, 1 ; Placeholder for RELOC_AARCH64_LO12
    ELSEIF eax, e, 'pg_h'
        mov r14d, 2 ; Placeholder for RELOC_AARCH64_PG_HI21
        ENDIF
    
    mov     rdi, rbx
    call    preprocessor_next_token
    IF byte [rdx + TOKEN_kind], ne, TOK_COLON
        mov rax, EXIT_UNEXPECTED_TOKEN
        jmp .error
        ENDIF
    
    call    parser_evaluate_factor
    check_err_to .error
    
    call    asm_ctx_align
    mov     rcx, r14
    xor     rax, rax
    jmp     .done

.error:
    pop     r14
    pop     r12
    pop     rbx
    epilogue
.done:
    pop     r14
    pop     r12
    pop     rbx
    epilogue

.success:
    mov     rax, OK
    mov     rdx, r12
    pop     r14
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_get_arch_tables]
; * Purpose: Resolves mnemonic and register tables based on AsmCtx target.
; * Output:
; *   RAX: Mnemonic Table Pointer
; *   RDX: Register Table Pointer
; ;
parser_get_arch_tables:
    prologue
    mov     rax, [rbx + PREP_ctx]
    movzx   rcx, byte [rax + ASMCTX_target]
    
    IF cl, e, TARGET_AMD64
        extern mnc_tb_x64
        extern amd64_register_table
        lea     rax, [mnc_tb_x64]
        lea     rdx, [amd64_register_table]
    ELSEIF cl, e, TARGET_AARCH64
        extern mnc_tb_arm64
        extern aarch64_register_table
        lea     rax, [mnc_tb_arm64]
        lea     rdx, [aarch64_register_table]
    ELSEIF cl, e, TARGET_RISCV64
        extern mnc_tb_rv64
        extern riscv64_register_table
        lea     rax, [mnc_tb_rv64]
        lea     rdx, [riscv64_register_table]
        ELSE
        xor     rax, rax
        xor     rdx, rdx
        ENDIF
    epilogue

;*
; * [parser_parse_mem_operand]
; * Purpose: Technical SIB Parser.
; ;
parser_parse_mem_operand:
    prologue
    mov     byte [r12 + OPERAND_kind], OP_MEM
    mov     byte [r12 + OPERAND_scale], 1 ; Default scale
    mov     byte [r12 + OPERAND_base],  0xFF ; 0xFF = no base register
    mov     byte [r12 + OPERAND_index], 0xFF ; 0xFF = no index register
    
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r13, rdx
    mov     al, [r13 + TOKEN_kind]
    
    ; 1. Check for 'rel' keyword (RIP-relative)
    IF al, e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [str_rel]
        extern  str_cmp
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    preprocessor_next_token ; consume 'rel'
            mov     byte [r12 + OPERAND_flags], OP_FLAG_REL
            mov     byte [r12 + OPERAND_base], REG_RIP  ; encoder keys off base
            ; Fall through to parse the symbol/offset
            ENDIF
            ENDIF

    ; 1b. 'abs' keyword: an absolute address even under DEFAULT REL
    ;     (r13 still holds the peeked token; after a consumed 'rel' it is
    ;     "rel", which does not match)
    IF byte [r13 + TOKEN_kind], e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [str_abs]
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    preprocessor_next_token ; consume 'abs'
            or      byte [r12 + OPERAND_flags], OP_FLAG_ABS
            ENDIF
        ENDIF

.loop:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    mov     r13, rdx
    mov     al, [r13 + TOKEN_kind]

    IF al, e, TOK_RBRACKET
        jmp     .finalize
        ENDIF

    IF al, e, TOK_PLUS
        jmp     .loop
        ENDIF

    ; [byte x], [word x], [dword x], [qword x]: the displacement's size
    ; (and, for an address with no register, the address size)
    IF al, e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        call    parser_disp_size_word
        test    eax, eax
        jz      .not_disp_size
        mov     [r12 + OPERAND_dispsize], al
        jmp     .loop
.not_disp_size:
        mov     al, [r13 + TOKEN_kind]
        ENDIF

    ; "nosplit": keep [reg*2] as index*2 with a disp32
    IF al, e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_nosplit]
        call    str_cmp_kw
        IF rax, e, 0
            or      byte [r12 + OPERAND_flags], OP_FLAG_NOSPLIT
            jmp     .loop
            ENDIF
        mov     al, [r13 + TOKEN_kind]
        ENDIF

    ; "fs:" lexes as a label: inside brackets it is a segment override
    IF al, e, TOK_LABEL
        mov     rsi, [r13 + TOKEN_value]
        call    parser_seg_override
        check_err_to .error
        jmp     .loop
        ENDIF

    IF al, e, TOK_MINUS
        ; handle negative disp? usually handled by expression engine
        mov     rdi, rbx
        mov     rsi, r13
        call    preprocessor_putback_token
        jmp     .parse_item
        ENDIF

.parse_item:
    IF al, e, TOK_IDENT
        ; Could be a register OR a symbol
        call    parser_get_arch_tables
        mov     rdi, rdx               ; RDI = Register Table Pointer
        mov     rsi, [r13 + TOKEN_value]
        movzx   rcx, byte [r12 + OPERAND_size]  ; reg_info overwrites the size
        push    rcx
        movzx   rcx, word [r12 + OPERAND_xsize]
        push    rcx
        call    parser_parse_reg_info
        movzx   r8d, word [r12 + OPERAND_xsize] ; the register's width, if it is one
        pop     rcx
        mov     [r12 + OPERAND_xsize], cx
        pop     rcx
        mov     [r12 + OPERAND_size], cl        ; a memory operand keeps its own size
        IF rax, ne, ERR
            ; 32-bit address registers ([eax], [r14d+1]) need the 67 prefix
            ; in 64-bit mode; 16-bit ones ([bx+si]) are 16-bit addressing
            cmp     r8d, 32
            jne     .addr_not32
            or      byte [r12 + OPERAND_flags], OP_FLAG_ADDR32
        .addr_not32:
            cmp     r8d, 16
            jne     .addr64
            or      byte [r12 + OPERAND_flags], OP_FLAG_ADDR16
        .addr64:
            ; A vector register is the index of a gather/scatter address
            ; ([rbx + xmm1*4]); record whether it is xmm, ymm or zmm
            cmp     r8d, 128
            jb      .not_vsib
            mov     eax, r8d
            shr     eax, 7                 ; 128/256/512 -> 1/2/4
            cmp     eax, 4
            jne     .vsib_code
            mov     eax, 3
        .vsib_code:
            mov     [r12 + OPERAND_vsib], al
        .not_vsib:
            ; It's a register. Is it base or index?
            ; (reg_info returns a status; the register id landed in OPERAND_reg)
            mov     al, [r12 + OPERAND_reg]

            ; A segment register followed by ':' is an override ([fs:0x28])
            cmp     al, REG_CS
            jb      .not_seg
            cmp     al, REG_SS
            ja      .not_seg
            push    rax
            mov     rdi, rbx
            call    preprocessor_peek_token
            pop     rax
            cmp     byte [rdx + TOKEN_kind], TOK_COLON
            jne     .not_seg
            movzx   eax, al
            sub     eax, REG_CS
            lea     rcx, [rel seg_prefix_bytes]
            mov     al, [rcx + rax]
            mov     [r12 + OPERAND_segment], al
            mov     rdi, rbx
            call    preprocessor_next_token ; consume ':'
            jmp     .loop
        .not_seg:

            ; A scaled register is the index even when there is no base yet,
            ; as in [table + rcx*4]; a vector register is always the index.
            cmp     al, 80
            jb      .gpr_slot
            cmp     al, 112
            jb      .set_index
        .gpr_slot:
            push    rax
            mov     rdi, rbx
            call    preprocessor_peek_token
            mov     cl, [rdx + TOKEN_kind]
            pop     rax
            cmp     cl, TOK_STAR
            je      .set_index

            cmp     byte [r12 + OPERAND_base], 0xFF
            jne     .set_index
            mov     [r12 + OPERAND_base], al
        .check_scale:
            jmp     .loop
        .set_index:
            mov     [r12 + OPERAND_index], al
            ; Check for scale [base + index * scale]
            mov     rdi, rbx
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_STAR
                mov     rdi, rbx
                call    preprocessor_next_token ; consume '*'
                mov     rdi, rbx
                ; The scale is a single factor: in [base+index*4+8] the "+8"
                ; belongs to the displacement, not to the scale.
                call    parser_evaluate_factor
                check_err_to .error
                mov     rax, rdx               ; evaluated scale value
                
                ; Validate Scale: 1, 2, 4, 8
                IF rax, e, 1
                    jmp .scale_ok
                ENDIF 
                IF rax, e, 2
                    jmp .scale_ok
                ENDIF 
                IF rax, e, 4
                    jmp .scale_ok
                ENDIF 
                IF rax, e, 8
                    jmp .scale_ok
                ENDIF 
                
                mov     rax, 212
                jmp     .error
            .scale_ok:
                mov     [r12 + OPERAND_scale], al
                ENDIF
            jmp     .loop
            ENDIF
        ; Not a register, must be a symbol/expression
        ENDIF

    ; 2. Parse as expression (Displacement)
    ; Hand the token back: it starts a displacement expression, whether it is
    ; a symbol, a number, or a leading '-'.
    mov     rdi, rbx
    mov     rsi, r13
    call    preprocessor_putback_token

    push    qword [rel known_fwd_uses]
    mov     rdi, rbx
    call    parser_evaluate_expression
    pop     r8
    check_err_to .error
    cmp     r8, [rel known_fwd_uses]
    je      .disp_known
    mov     byte [r12 + OPERAND_fwd], 1    ; (encoder.s: NASM's pass 1)
.disp_known:
    ; result in rdx, symbol metadata in r11 (A78)
    add     [r12 + OPERAND_imm], rdx
    ; [table + rax + FIELD]: the label stays the operand's symbol; a
    ; constant (equ, structure field) after it only adds its value
    mov     rax, [r12 + OPERAND_sym]
    test    rax, rax
    jz      .take_sym
    cmp     byte [rax], TAG_SYMBOL
    jne     .loop                          ; a label not defined yet
    cmp     word [rax + SYMBOL_section], SHN_ABS
    jne     .loop                          ; a label
.take_sym:
    IF r11, ne, 0
        mov [r12 + OPERAND_sym], r11
    ELSEIF rcx, ne, 0
        mov [r12 + OPERAND_sym], rcx   ; forward reference: raw name string
        ENDIF
    jmp     .loop

.finalize:
    ; a size that cannot be the address's: [dword bx+4], [word ebx],
    ; [qword x] outside bits 64, [word x] in bits 64
    movzx   eax, byte [r12 + OPERAND_dispsize]
    test    eax, eax
    jz      .asize_ok
    cmp     eax, 64
    jne     .asize_not64
    cmp     byte [rel asm_bits], 64
    jne     .asize_bad
.asize_not64:
    cmp     eax, 32
    jne     .asize_not32
    test    byte [r12 + OPERAND_flags], OP_FLAG_ADDR16
    jnz     .asize_bad
.asize_not32:
    cmp     eax, 16
    jne     .asize_ok
    test    byte [r12 + OPERAND_flags], OP_FLAG_ADDR32
    jnz     .asize_bad
    cmp     byte [rel asm_bits], 64
    je      .asize_bad
    test    byte [r12 + OPERAND_flags], OP_FLAG_ADDR16
    jnz     .asize_ok
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .asize_bad                     ; 32-bit registers
    cmp     byte [r12 + OPERAND_index], 0xFF
    jne     .asize_bad
    jmp     .asize_ok
.asize_bad:
    mov     rax, EXIT_INVALID_ADDR
    jmp     .error
.asize_ok:
    ; [dword 0xFEE00300] in bits 16, [word 0x1234] in bits 32: an address
    ; of the other size (67), as with registers of that size
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .asize_done
    cmp     byte [r12 + OPERAND_index], 0xFF
    jne     .asize_done
    movzx   eax, byte [r12 + OPERAND_dispsize]
    cmp     eax, 32
    jne     .asize_word
    cmp     byte [rel asm_bits], 16
    jne     .asize_done
    or      byte [r12 + OPERAND_flags], OP_FLAG_ADDR32
    jmp     .asize_done
.asize_word:
    cmp     eax, 16
    jne     .asize_done
    cmp     byte [rel asm_bits], 32
    jne     .asize_done
    or      byte [r12 + OPERAND_flags], OP_FLAG_ADDR16
.asize_done:
    ; rsp cannot be an index register: [rbx+rsp] is [rsp+rbx], and
    ; [rsp*1] is [rsp], as NASM swaps them
    cmp     byte [r12 + OPERAND_index], REG_RSP
    jne     .rsp_done
    cmp     byte [r12 + OPERAND_vsib], 0
    jne     .rsp_done
    cmp     byte [r12 + OPERAND_scale], 1
    jne     .rsp_done
    mov     al, [r12 + OPERAND_base]
    mov     byte [r12 + OPERAND_base], REG_RSP
    mov     [r12 + OPERAND_index], al      ; 0xFF (none) when there was no base
.rsp_done:
    ; [rbx*2] with no base is [rbx+rbx] -- no disp32 needed -- as NASM
    ; encodes it, unless written with nosplit
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .split_done
    cmp     byte [r12 + OPERAND_index], 0xFF
    je      .split_done
    cmp     byte [r12 + OPERAND_vsib], 0
    jne     .split_done
    test    byte [r12 + OPERAND_flags], OP_FLAG_NOSPLIT
    jnz     .split_done
    cmp     byte [r12 + OPERAND_scale], 2
    jne     .split_done
    mov     al, [r12 + OPERAND_index]
    mov     [r12 + OPERAND_base], al
    mov     byte [r12 + OPERAND_scale], 1
.split_done:
    ; ---- STRUCT BOUNDS CHECK ----
    ; If OPERAND_sym is set, the base address expression contained a
    ; struct-field dot-access (e.g. PageTable.Present).  At this point
    ; OPERAND_sym holds a pointer to the SYMBOL entry, so we can compare
    ; the field's declared byte-width against the instruction's size.
    mov     r13, [r12 + OPERAND_sym]
    test    r13, r13
    jz      .bounds_ok
    
    movzx   rax, byte [r13 + SYMBOL_kind]
    cmp     al, SYM_STRUCT_FIELD
    jne     .bounds_ok
    
    ; Field declared size (bytes) is in SYMBOL_size
    mov     rsi, [r13 + SYMBOL_size]       ; rsi = field byte width
    
    ; Instruction access size (bits) is in OPERAND_size -> convert to bytes
    movzx   rcx, byte [r12 + OPERAND_size]
    shr     cl, 3                           ; bits -> bytes
    
    cmp     rcx, rsi
    jle     .bounds_ok                     ; write size <= field size -> OK
    
    ; FATAL: write exceeds field width
    extern error_struct_bounds
    mov     rdi, [r13 + SYMBOL_name]       ; field name for error message
    mov     rdx, rcx                       ; attempted access size
    call    error_struct_bounds
    mov     rax, EXIT_STRUCT_BOUNDS
    jmp     .error

.bounds_ok:
    ; ---- DEFAULT REL ----
    ; Under DEFAULT REL, a memory operand that names a label and has no
    ; base or index register is RIP-relative, as if written [rel label].
    ; Not affected: [abs label], fs:/gs: overrides (never RIP-relative),
    ; purely numeric addresses, and equ constants / struct fields (plain
    ; numbers, not relocatable addresses).
    mov     rax, [rbx + PREP_ctx]
    test    dword [rax + ASMCTX_flags], CTX_FLAG_DEFAULT_REL
    jz      .rel_done
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .rel_done                      ; has a base (or is already rel)
    cmp     byte [r12 + OPERAND_index], 0xFF
    jne     .rel_done
    test    byte [r12 + OPERAND_flags], OP_FLAG_ABS
    jnz     .rel_done
    cmp     byte [r12 + OPERAND_segment], 0x64    ; fs:
    je      .rel_done
    cmp     byte [r12 + OPERAND_segment], 0x65    ; gs:
    je      .rel_done
    mov     rax, [r12 + OPERAND_sym]
    test    rax, rax
    jz      .rel_done                      ; no symbol: numeric address
    cmp     byte [rax], TAG_SYMBOL
    jne     .make_rel                      ; raw name: a forward label
    cmp     byte [rax + SYMBOL_kind], SYM_CONSTANT
    je      .rel_done
    cmp     byte [rax + SYMBOL_kind], SYM_STRUCT_FIELD
    je      .rel_done
    cmp     byte [rax + SYMBOL_kind], SYM_STRUCT
    je      .rel_done
    cmp     word [rax + SYMBOL_section], 0xFFF1   ; SHN_ABS: an equ constant
    je      .rel_done                      ; (equ keeps the label's kind)
.make_rel:
    or      byte [r12 + OPERAND_flags], OP_FLAG_REL
    mov     byte [r12 + OPERAND_base], REG_RIP
.rel_done:
    mov     rax, OK
.done:
    epilogue

.error:
    epilogue

;*
; * [parser_parse_decorator]
; * Purpose: Parse one AVX-512 decorator; the '{' is already consumed.
; *   {k1}..{k7}      opmask       -> OPERAND_mask = 1..7
; *   {z}             zeroing      -> OPERAND_ctrl bit 0
; *   {1to2}..{1to32} broadcast    -> OPERAND_ctrl bit 1, log2(N) in bits 2-4
; *   {rn-sae} {rd-sae} {ru-sae} {rz-sae} -> OP_ROUNDING, OPERAND_imm = 0..3
; *   {sae}           -> OP_SAE
; *   The text is rebuilt from its tokens: "1to16" lexes as the number 1
; *   and the identifier to16, and a number token carries its text.
; * Input  : RBX = PrepState, R12 = OPERAND
; * Output : RAX = OK or an error code
; ;
parser_parse_decorator:
    push    r13
    push    r14
    lea     r14, [rel deco_buf]
    mov     byte [r14], 0
.tok:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    movzx   eax, byte [r13 + TOKEN_kind]
    cmp     eax, TOK_RBRACE
    je      .match
    cmp     eax, TOK_IDENT
    je      .ident
    cmp     eax, TOK_NUMBER
    je      .ident
    cmp     eax, TOK_MINUS
    je      .minus
    jmp     .bad
.ident:
    mov     rdi, r14
    mov     rsi, [r13 + TOKEN_value]
    call    str_concat
    jmp     .tok
.minus:
    mov     rdi, r14
    lea     rsi, [rel deco_dash]
    call    str_concat
    jmp     .tok

.match:
    ; {k1}..{k7}
    cmp     byte [r14], 'k'
    jne     .named
    cmp     byte [r14 + 2], 0
    jne     .named
    movzx   eax, byte [r14 + 1]
    sub     eax, '1'
    cmp     eax, 6
    ja      .named
    inc     eax
    mov     [r12 + OPERAND_mask], al
    jmp     .ok
.named:
    xor     r13d, r13d
.name_loop:
    mov     rdi, r14
    lea     rsi, [rel deco_names]
    mov     eax, r13d
    shl     eax, 3
    add     rsi, rax
    call    str_cmp
    test    rax, rax
    jz      .found
    inc     r13d
    cmp     r13d, 11
    jb      .name_loop
.bad:
    mov     rax, EXIT_INVALID_EXPR
    jmp     .ret
.found:
    test    r13d, r13d
    jnz     .not_z
    or      byte [r12 + OPERAND_ctrl], 1      ; {z}
    jmp     .ok
.not_z:
    cmp     r13d, 5
    ja      .not_bcst
    mov     eax, r13d                         ; {1toN}: log2(N) = index
    shl     eax, 2
    or      eax, 2
    or      [r12 + OPERAND_ctrl], al
    jmp     .ok
.not_bcst:
    cmp     r13d, 10
    je      .sae
    lea     eax, [r13 - 6]                    ; rn/rd/ru/rz = 0..3
    mov     byte [r12 + OPERAND_kind], OP_ROUNDING
    mov     [r12 + OPERAND_imm], rax
    jmp     .ok
.sae:
    mov     byte [r12 + OPERAND_kind], OP_SAE
.ok:
    mov     rax, OK
.ret:
    pop     r14
    pop     r13
    ret

; ============================================================================
; GNU-style numeric local labels
; ============================================================================
; "N:" defines a new instance of label N (0 <= N < NUMLBL_MAX); "Nb" is the
; latest instance before the reference and "Nf" the next one after it. Each
; instance is an ordinary label named "L@num.N.k" (k counts the definitions
; of N), which no source text can spell, so forward references take the usual
; relocation path. "Nb" before any "N:" stays a number (NASM's binary suffix).

%define NUMLBL_MAX  10000

;*
; * [parser_numlabel_def]
; * Input : RDI = number text of an "N:" label, RBX = PrepState
; * Output: RAX = OK and RSI = the instance's label name, or an error
; ;
parser_numlabel_def:
    call    parser_numlabel_n
    cmp     eax, -1
    je      .bad
    cmp     byte [rdi], 0
    jne     .bad                           ; "1f:" is not a numeric label
    lea     rcx, [rel numlbl_count]
    mov     esi, [rcx + rax*4]
    inc     dword [rcx + rax*4]
    mov     edi, eax
    call    parser_numlabel_name
    mov     rax, OK
    ret
.bad:
    mov     rax, EXIT_INVALID_EXPR
    ret

;*
; * [parser_numlabel_ref]
; * Input : RDI = number token text, RBX = PrepState
; * Output: RSI = the label name "Nf" / "Nb" refers to, or 0 for a number
; ;
parser_numlabel_ref:
    call    parser_numlabel_n
    cmp     eax, -1
    je      .none
    movzx   ecx, byte [rdi]
    cmp     byte [rdi + 1], 0
    jne     .none
    lea     rdx, [rel numlbl_count]
    mov     esi, [rdx + rax*4]             ; definitions so far
    cmp     ecx, 'f'
    je      .name
    cmp     ecx, 'b'
    jne     .none
    test    esi, esi
    jz      .none                          ; no "N:" yet: 1b is binary one
    dec     esi
.name:
    mov     edi, eax
    jmp     parser_numlabel_name
.none:
    xor     esi, esi
    ret

; eax = the decimal number at rdi (rdi left after its digits), or -1 when
; the text does not start with a digit or the number is NUMLBL_MAX or more
parser_numlabel_n:
    xor     eax, eax
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .no
.digit:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .end
    imul    eax, eax, 10
    add     eax, ecx
    cmp     eax, NUMLBL_MAX
    jae     .no
    inc     rdi
    jmp     .digit
.end:
    ret
.no:
    mov     eax, -1
    ret

; rsi = "L@num.<edi>.<esi>", allocated in the preprocessor arena
parser_numlabel_name:
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 40
    call    arena_alloc
    mov     r14, rdx
    mov     rdi, r14
    lea     rsi, [rel numlbl_prefix]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     esi, r12d
    extern  str_int_to_str
    call    str_int_to_str
    mov     rdi, r14
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rdi, r14
    lea     rsi, [rel numlbl_dot]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     esi, r13d
    call    str_int_to_str
    mov     rdi, r14
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rsi, r14
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_pos_label]
; * Purpose: "$" and "$$" as labels. Each use becomes a hidden label
; *          ("L@here.N", which no source can spell) at the current
; *          position, or at offset 0 of the current section for "$$", so
; *          branches, data relocations and label differences treat them
; *          like any other label: "jmp $", "loop $", "dq $", "$-start".
; * Input  : EDI = 0 for "$", 1 for "$$"; RBX = PrepState
; * Output : RAX = OK and RDX = the SYMBOL*, or an error
; ;
parser_pos_label:
    push    r12
    push    r13
    mov     r12d, edi
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, r13
    lea     rsi, [rel pos_prefix]
    call    str_concat
    lea     rdi, [rel numlbl_digits]
    mov     rsi, [rel pos_count]
    inc     qword [rel pos_count]
    call    str_int_to_str
    mov     rdi, r13
    lea     rsi, [rel numlbl_digits]
    call    str_concat
    mov     rsi, r13
    call    parser_define_label
    test    rax, rax
    jnz     .ret
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .ret
    test    r12d, r12d
    jz      .ret
    mov     qword [rdx + SYMBOL_value], 0  ; "$$": the start of the section
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_is_statement_word]
; * Purpose: Is this word an instruction or a data directive? Used to take
; *          "msg db 'hi'" / "top nop" as a label without its colon.
; * Input  : RSI = word, RBX = PrepState
; * Output : EAX = 1 or 0
; ;
parser_is_statement_word:
    push    r12
    push    r13
    mov     r12, rsi
    lea     r13, [rel stmt_words]
.word:
    cmp     byte [r13], 0
    je      .mnemonic
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
.skip:
    inc     r13
    cmp     byte [r13 - 1], 0
    jne     .skip
    jmp     .word
.mnemonic:
    hash_fnv1a_64_ci r12, r13
    call    parser_get_arch_tables         ; rax = mnemonic table
    mov     rdi, r13
    mov     rsi, rax
    call    parser_lookup_mnemonic
    test    rax, rax
    jnz     .yes
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_skip_to_eol]
; * Purpose: Skip the rest of the statement (a directive utasm accepts but
; *          has nothing to do for, such as "cpu").
; * Input  : RBX = PrepState
; ;
parser_skip_to_eol:
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACKET
    je      .ret
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .ret
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .next
.ret:
    xor     eax, eax
    ret

;*
; * [parser_section_attrs]
; * Purpose: NASM's section attributes after the name: progbits / nobits,
; *          alloc / noalloc, exec / noexec, write / nowrite, align=N.
; * Input  : RBX = PrepState, R13 = SECTION
; * Output : RAX = OK or an error
; ;
parser_section_attrs:
    push    r12
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, [rdx + TOKEN_value]
    mov     rdi, r12
    lea     rsi, [rel attr_progbits]
    call    str_cmp
    test    rax, rax
    jnz     .not_progbits
    mov     dword [r13 + SECTION_elf_type], SHT_PROGBITS
    jmp     .next
.not_progbits:
    mov     rdi, r12
    lea     rsi, [rel attr_nobits]
    call    str_cmp
    test    rax, rax
    jnz     .not_nobits
    mov     dword [r13 + SECTION_elf_type], SHT_NOBITS
    jmp     .next
.not_nobits:
    lea     r8, [rel attr_flag_names]
    xor     ecx, ecx
.flag:
    cmp     ecx, 6
    jae     .not_flag
    push    rcx
    push    r8
    mov     rdi, r12
    mov     rsi, r8
    call    str_cmp
    pop     r8
    pop     rcx
    test    rax, rax
    jz      .flag_hit
    add     r8, 8
    inc     ecx
    jmp     .flag
.flag_hit:
    lea     rax, [rel attr_flag_bits]
    movzx   eax, word [rax + rcx*2]
    test    ecx, 1
    jnz     .flag_off
    or      [r13 + SECTION_flags], ax      ; alloc / exec / write
    jmp     .next
.flag_off:
    not     eax
    and     [r13 + SECTION_flags], ax      ; noalloc / noexec / nowrite
    jmp     .next
.not_flag:
    ; flat binary placement: vstart=, start=, follows=
    mov     rdi, r12
    lea     rsi, [rel attr_vstart]
    call    str_cmp
    test    rax, rax
    jz      .vstart
    mov     rdi, r12
    lea     rsi, [rel attr_start]
    call    str_cmp
    test    rax, rax
    jz      .start
    mov     rdi, r12
    lea     rsi, [rel attr_follows]
    call    str_cmp
    test    rax, rax
    jz      .follows
    mov     rdi, r12
    lea     rsi, [rel attr_align]
    call    str_cmp
    test    rax, rax
    jnz     .bad                           ; an attribute NASM does not have
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .bad
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_align], rdx
    jmp     .next
.vstart:
    call    .equals_value
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_vstart], rdx
    or      byte [r13 + SECTION_bin_flags], BIN_VSTART
    jmp     .next
.start:
    call    .equals_value
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_start], rdx
    or      byte [r13 + SECTION_bin_flags], BIN_START
    jmp     .next
.follows:
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .bad
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rax, [rdx + TOKEN_value]
    mov     [r13 + SECTION_follows], rax
    jmp     .next
; "= expr": rax = OK or error, rdx = the value
.equals_value:
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .ev_bad
    mov     rdi, rbx
    jmp     parser_evaluate_expression
.ev_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r12
    ret

;*
; * [parser_seg_override]
; * Purpose: Record a segment override written inside brackets ([fs:0x28]).
; * Input  : RSI = register name, R12 = OPERAND
; * Output : RAX = OK, or EXIT_INVALID_EXPR if it is not a segment register
; ;
parser_seg_override:
    push    rbx
    push    r13
    mov     r13, rsi
    xor     ebx, ebx
.next:
    mov     rdi, r13
    lea     rsi, [rel seg_names]
    lea     rsi, [rsi + rbx*4]
    call    str_cmp
    test    rax, rax
    jz      .found
    inc     ebx
    cmp     ebx, 6
    jb      .next
    mov     rax, EXIT_INVALID_EXPR
    jmp     .ret
.found:
    lea     rsi, [rel seg_prefix_bytes]
    mov     al, [rsi + rbx]
    mov     [r12 + OPERAND_segment], al
    mov     rax, OK
.ret:
    pop     r13
    pop     rbx
    ret

[SECTION .bss]
deco_buf:   resb 64                 ; the decorator text being matched
numlbl_count: resd NUMLBL_MAX       ; definitions of each numeric label so far
numlbl_digits: resb 24
pos_count:  resq 1                  ; "$" labels made so far

[SECTION .rodata]
str_rel: db "rel", 0
; AVX-512 decorators, 8 bytes each (parser_parse_decorator relies on the order)
deco_names: db "z", 0, 0, 0, 0, 0, 0, 0
            db "1to2", 0, 0, 0, 0, "1to4", 0, 0, 0, 0, "1to8", 0, 0, 0, 0
            db "1to16", 0, 0, 0, "1to32", 0, 0, 0
            db "rn-sae", 0, 0, "rd-sae", 0, 0, "ru-sae", 0, 0, "rz-sae", 0, 0
            db "sae", 0, 0, 0, 0, 0
deco_dash:  db "-", 0
numlbl_prefix: db "L@num.", 0
pos_prefix: db "L@here.", 0
numlbl_dot: db ".", 0
; segment registers in REG_CS..REG_SS order, 4 bytes each
seg_names:  db "cs", 0, 0, "ds", 0, 0, "es", 0, 0, "fs", 0, 0, "gs", 0, 0, "ss", 0, 0
; segment override prefixes for REG_CS..REG_SS (cs ds es fs gs ss)
seg_prefix_bytes: db 0x2E, 0x3E, 0x26, 0x64, 0x65, 0x36
str_abs: db "abs", 0

[SECTION .text]

;*
; * [parser_is_register]
; * Input: RSI = String, RDI = Table Pointer
; ;
parser_is_register:
    prologue
    hash_fnv1a_64_ci rsi, r8
.loop:
    mov     rax, [rdi]
    test    rax, rax
    jz      .not_found
    cmp     rax, r8
    je      .found
    add     rdi, 16
    jmp     .loop

.found:
    mov     rax, [rdi + 8]
    epilogue

.not_found:
    mov     rax, ERR
    epilogue

;*
; * [parser_lookup_mnemonic]
; * Input: RDI = Hash, RSI = Table Pointer
; ;
parser_lookup_mnemonic:
    prologue
.loop:
    mov     rax, [rsi]
    test    rax, rax
    jz      .not_found
    cmp     rax, rdi
    je      .found
    add     rsi, 16
    jmp     .loop

.found:
    movzx   rax, word [rsi + 9]
    epilogue

.not_found:
    xor     rax, rax
    epilogue

;*
; * [parser_check_prefix]
; * Purpose: Is the word an instruction prefix? rep/repe/repz, repne/repnz,
; *   lock, xacquire/xrelease, bnd, o16/o32/o64, a32/a64 and the segment
; *   prefixes cs ds es ss fs gs, as NASM writes them.
; * Input: RSI = String pointer
; * Output: EAX = Prefix byte, 1 (accepted, nothing to emit) or 0
; ;
parser_check_prefix:
    push    r12
    push    r13
    mov     r12, rsi
    lea     r13, [rel prefix_words]
.word:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .hit
    add     r13, 10
    jmp     .word
.hit:
    movzx   eax, byte [r13 + 9]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
; name (9 bytes) + the prefix byte; 1 = accepted, no byte in 64-bit code
prefix_words:
    db "rep", 0, 0,0,0,0,0, 0xF3
    db "repe", 0, 0,0,0,0, 0xF3
    db "repz", 0, 0,0,0,0, 0xF3
    db "repne", 0, 0,0,0, 0xF2
    db "repnz", 0, 0,0,0, 0xF2
    db "lock", 0, 0,0,0,0, 0xF0
    db "xacquire", 0, 0xF2
    db "xrelease", 0, 0xF3
    db "bnd", 0, 0,0,0,0,0, 0xF2
    db "o16", 0, 0,0,0,0,0, 0x66
    db "o32", 0, 0,0,0,0,0, 1
    db "o64", 0, 0,0,0,0,0, 1
    db "a32", 0, 0,0,0,0,0, 0x67
    db "a64", 0, 0,0,0,0,0, 1
    db "cs", 0, 0,0,0,0,0,0, 0x2E
    db "ds", 0, 0,0,0,0,0,0, 0x3E
    db "es", 0, 0,0,0,0,0,0, 0x26
    db "ss", 0, 0,0,0,0,0,0, 0x36
    db "fs", 0, 0,0,0,0,0,0, 0x64
    db "gs", 0, 0,0,0,0,0,0, 0x65
    db 0

[SECTION .text]

; ============================================================================
; PARSER EXTENSION: SAFE STRUCT REGISTRATION
; ============================================================================

;*
; * [parser_parse_struc]
; * Purpose: Parse a `struc` ... `endstruc` block.
; *   For each `field name, size` line, registers a SYMBOL with:
; *     kind  = SYM_STRUCT_FIELD
; *     value = byte offset within the struct
; *     size  = declared field byte width
; *   At `endstruc`, registers the struct name itself with:
; *     kind  = SYM_STRUCT
; *     value = 0
; *     size  = total struct size in bytes
; * Input:
; *   RBX: pointer to PrepState
; *   RDI: pointer to the struct-name Token (the token after 'struc')
; * Output:
; *   RAX = EXIT_OK or error code
; ;
global parser_parse_struc
parser_parse_struc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    ; Locals. The offset must survive calls to the token reader and the
    ; expression evaluator, neither of which preserves the scratch registers.
    ;   [rbp - 48] running byte offset
    ;   [rbp - 56] field name pointer
    ;   [rbp - 64] field byte width
    ;   [rbp - 72] field alignment
    ;   [rbp - 80] length of the struct name
    ;   [rbp - 88] length of the field name
    ;   [rbp - 96] 1 once a field is written in NASM's form
    sub     rsp, 64

    mov     rbx, rdi               ; rbx = PrepState
    mov     r15, rsi               ; r15 = struct name Token
    mov     qword [rbp - 48], 0    ; running byte offset
    mov     qword [rbp - 96], 0

    ; Build struct-name string ("StructName", null-terminated from token)
    mov     r13, [r15 + TOKEN_value]  ; r13 = struct name ptr
    
.field_loop:
    ; Read next meaningful token (skip newlines)
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    mov     r12, rdx
    
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_NEWLINE
        jmp     .field_loop
        ENDIF
    
    IF al, e, TOK_EOF
        mov     rax, EXIT_UNEXPECTED_EOF
        jmp     .error
        ENDIF

    ; NASM's ".x:" field label (a "name:" one too)
    IF al, e, TOK_LOCAL_LABEL
        jmp     .nasm_label
        ENDIF
    IF al, e, TOK_LABEL
        jmp     .nasm_label
        ENDIF

    ; Check for 'endstruc'
    IF al, e, TOK_IDENT
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_endstruc]
        extern  str_compare
        call    str_cmp_kw
        IF rax, e, 0
            jmp .register_struct
            ENDIF
        
        ; Check for 'field' keyword; any other word is NASM's form
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_field]
call    str_compare
        IF rax, ne, 0
            jmp     .nasm_word
            ENDIF
            ELSE
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; Parse: field <name>, <size>
    ; 1. Field name
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     rax, [rdx + TOKEN_value]
    mov     [rbp - 56], rax            ; field name ptr

    ; Consume comma
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; 2. Field byte size (expression)
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    mov     [rbp - 64], rdx            ; field byte width

    ; 3. Optional: Alignment (A77)
    mov     qword [rbp - 72], 1        ; default alignment
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token ; consume TOK_COMMA
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err_to .error
        mov     [rbp - 72], rdx

        ; VALIDATION: Power of 2 (Industrial Safety)
        mov     rax, rdx
        dec     rax
        test    rdx, rax
        jnz     .error_invalid_align
        ENDIF

    ; Apply Alignment: offset = (offset + align - 1) & -align
    mov     rax, [rbp - 48]            ; current offset
    add     rax, [rbp - 72]
    dec     rax
    mov     rcx, [rbp - 72]
    neg     rcx
    and     rax, rcx                   ; rax = aligned offset
    mov     [rbp - 48], rax

    ; Build the qualified field name "<Struct>_<field>". NASM's struc
    ; emulation in macro.inc defines the same name, so both toolchains agree.
    mov     rdi, r13
    extern  str_len
    call    str_len
    mov     [rbp - 80], rax
    mov     rdi, [rbp - 56]
    call    str_len
    mov     [rbp - 88], rax

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rbp - 80]
    add     rsi, [rbp - 88]
    add     rsi, 2                     ; '_' + NUL
    call    arena_alloc
    check_err_to .error
    mov     r12, rdx                   ; r12 = qualified name buffer

    mov     rdi, r12
    mov     rsi, r13
    mov     rcx, [rbp - 80]
    rep movsb
    mov     byte [rdi], '_'
    inc     rdi
    mov     rsi, [rbp - 56]
    mov     rcx, [rbp - 88]
    rep movsb
    mov     byte [rdi], 0

    ; Register SYMBOL: kind=SYM_STRUCT_FIELD, value=offset, size=field_size
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    ; Zero the symbol
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT_FIELD
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     word [rsi + SYMBOL_section], SHN_ABS ; a number, as for equ
    mov     [rsi + SYMBOL_name],  r12      ; qualified field name
    mov     rax, [rbp - 48]
    mov     [rsi + SYMBOL_value], rax      ; byte offset
    mov     rax, [rbp - 64]
    mov     [rsi + SYMBOL_size],  rax      ; field byte width
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; Advance offset
    mov     rax, [rbp - 48]
    add     rax, [rbp - 64]
    mov     [rbp - 48], rax
    jmp     .field_loop
    
    ; ---- NASM's form: ".x: resd 1", ".y resw 2", "resb 4", "alignb 8" ----
    ; A field is a plain number, "<struct>.x" (or the name itself when it
    ; has no dot); the reservation after it moves the offset on.
.nasm_word:
    mov     byte [rbp - 96], 1
    mov     rdi, [r12 + TOKEN_value]
    call    parser_res_unit                ; eax = bytes per unit, 0 if none
    test    eax, eax
    jnz     .nasm_res
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_alignb]
    call    str_cmp_kw
    test    rax, rax
    jz      .nasm_alignb
    ; "align 64" in a structure: as alignb (NASM accepts it where it pads
    ; nothing, and has no code to pad with here)
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_align]
    call    str_cmp_kw
    test    rax, rax
    jz      .nasm_alignb
    ; any other word names a field (a label without its colon)
.nasm_label:
    mov     byte [rbp - 96], 1
    mov     rsi, [r12 + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .nasm_named
    mov     [rbp - 56], rsi
    mov     rdi, r13
    call    str_len
    mov     [rbp - 80], rax
    mov     rdi, [rbp - 56]
    call    str_len
    mov     [rbp - 88], rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rbp - 80]
    add     rsi, [rbp - 88]
    inc     rsi                            ; NUL
    call    arena_alloc
    check_err_to .error
    mov     r12, rdx
    mov     rdi, rdx
    mov     rsi, r13
    mov     rcx, [rbp - 80]
    rep movsb
    mov     rsi, [rbp - 56]
    mov     rcx, [rbp - 88]
    rep movsb
    mov     byte [rdi], 0
    mov     rsi, r12                       ; "<struct>.x"
.nasm_named:
    mov     rdx, [rbp - 48]
    call    parser_struc_const
    check_err_to .error
    jmp     .field_loop
.nasm_res:
    mov     [rbp - 64], rax                ; bytes per unit
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    imul    rdx, [rbp - 64]
    mov     rdi, [rbp - 48]                ; the listing: its offset, size
    mov     rsi, rdx
    push    rdx
    extern  lst_field
    call    lst_field
    pop     rdx
    add     [rbp - 48], rdx
    jmp     .field_loop
.nasm_alignb:
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    mov     rax, [rbp - 48]
    lea     rax, [rax + rdx - 1]
    neg     rdx
    and     rax, rdx
    mov     rdi, [rbp - 48]
    mov     rsi, rax
    sub     rsi, rdi
    mov     [rbp - 48], rax
    call    lst_field
    jmp     .field_loop

.register_struct:
    ; Register the struct itself: kind=SYM_STRUCT, size=total
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     word [rsi + SYMBOL_section], SHN_ABS ; a number, as for equ
    mov     [rsi + SYMBOL_name],  r13     ; struct name ptr
    mov     qword [rsi + SYMBOL_value], 0
    mov     rax, [rbp - 48]
    mov     [rsi + SYMBOL_size],  rax     ; total byte size
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; Register the struct size constant: "[StructName]_SIZE"
    ; 1. Calculate struct name length
    mov     rdi, r13
    call    str_len
    mov     r12, rax                   ; r12 = length of struct name
    
    ; 2. Allocate buffer from arena for "[StructName]_SIZE" (len + 5 for "_SIZE" + 1 for null = len + 6)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r12
    add     rsi, 6
    extern  arena_alloc
    call    arena_alloc
    check_err_to .error
    mov     r15, rdx                   ; r15 = allocated buffer ptr
    
    ; 3. Copy struct name to r15
    mov     rdi, r15
    mov     rsi, r13
    mov     rcx, r12
    rep movsb
    
    ; 4. Append "_SIZE" and null terminate
    mov     byte [r15 + r12],     '_'
    mov     byte [r15 + r12 + 1], 'S'
    mov     byte [r15 + r12 + 2], 'I'
    mov     byte [r15 + r12 + 3], 'Z'
    mov     byte [r15 + r12 + 4], 'E'
    mov     byte [r15 + r12 + 5], 0
    
    ; 5. Register the struct size constant: kind=SYM_CONSTANT, value=total
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     [rsi + SYMBOL_name],  r15     ; "[StructName]_SIZE"
    mov     rax, [rbp - 48]
    mov     [rsi + SYMBOL_value], rax     ; total byte size as value!
    mov     qword [rsi + SYMBOL_size], 8  ; size of QWORD constant
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; NASM's form names the size "<struct>_size"
    cmp     byte [rbp - 96], 0
    je      .no_nasm_size
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r12 + 6]
    call    arena_alloc
    check_err_to .error
    mov     rdi, rdx
    mov     rsi, r15
    lea     rcx, [r12 + 6]
    rep movsb
    mov     dword [rdx + r12 + 1], 'size'
    mov     rsi, rdx
    mov     rdx, [rbp - 48]
    call    parser_struc_const
    check_err_to .error
.no_nasm_size:

    xor     rax, rax
    jmp     .done

.error_no_global:
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .error

.error_invalid_align:
    mov     rax, EXIT_ALIGN_ERROR
    jmp     .error

.error:
.done:
    add     rsp, 64                    ; discard the locals frame
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret


;*
; * [parser_define_label]
; * Input: RSI = name string
; ;
parser_define_label:
    prologue
    push    rbx
    push    rsi
    mov     rbx, [rbx + PREP_ctx]
    
    ; 1. Check if the symbol already exists
    mov     rdi, rbx
    mov     rsi, [rsp]                         ; Retrieve original name from stack
    extern  symbol_find
    call    symbol_find
    IF rax, e, OK
        ; Symbol already exists! Check if it is currently undefined
        cmp     byte [rdx + SYMBOL_kind], SYM_UNKNOWN
        je      .define_existing
        cmp     word [rdx + SYMBOL_section], 0
        je      .define_existing
        
        ; Otherwise, it's defined already! Duplicate symbol!
        mov     rdi, [rsp]                 ; "label `x' inconsistently
        call    error_set_subject          ;  redefined"
        mov     rax, EXIT_DUP_SYMBOL
        jmp     .error_no_stack
        ENDIF
        
    ; Create Symbol struct
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    
    ; Setup symbol fields using stable rsi = rsp
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_LABEL
    mov     rax, [rsp + SYMBOL_SIZE]            ; Retrieve original label name from stack
    mov     [rsi + SYMBOL_name], rax
    
    ; Set value to current section location
    mov     rax, [rbx + ASMCTX_curr_sec]
    IF rax, ne, 0
        mov     rcx, [rax + SECTION_size]
        mov     [rsi + SYMBOL_value], rcx
        movzx   ecx, word [rax + SECTION_index]
        mov     [rsi + SYMBOL_section], cx
        ENDIF
    ; in an "absolute" block a label is a plain number
    test    rax, rax
    jz      .not_abs_new
    cmp     rax, [rel abs_section]
    jne     .not_abs_new
    mov     byte [rsi + SYMBOL_kind], SYM_CONSTANT
    mov     rcx, [rax + SECTION_addr]
    add     [rsi + SYMBOL_value], rcx
    mov     word [rsi + SYMBOL_section], 0
.not_abs_new:

    mov     rdi, rbx
    mov     rsi, rsp
    extern  symbol_add
    call    symbol_add
    check_err_to .error
    mov     [rbx + ASMCTX_last_symbol], rdx    ; Store for potential equ override
    
    add     rsp, SYMBOL_SIZE
    pop     rsi
    pop     rbx
    epilogue

.define_existing:
    mov     byte [rdx + SYMBOL_kind], SYM_LABEL
    mov     byte [rdx + SYMBOL_tag], TAG_SYMBOL
    
    ; Set value to current section location
    mov     rax, [rbx + ASMCTX_curr_sec]
    IF rax, ne, 0
        mov     rcx, [rax + SECTION_size]
        mov     [rdx + SYMBOL_value], rcx
        movzx   ecx, word [rax + SECTION_index]
        mov     [rdx + SYMBOL_section], cx
        ENDIF
    test    rax, rax
    jz      .not_abs_old
    cmp     rax, [rel abs_section]
    jne     .not_abs_old
    mov     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    mov     rcx, [rax + SECTION_addr]
    add     [rdx + SYMBOL_value], rcx
    mov     word [rdx + SYMBOL_section], 0
.not_abs_old:
        
    mov     [rbx + ASMCTX_last_symbol], rdx    ; Store for potential equ override
    
    xor     rax, rax
    pop     rsi
    pop     rbx
    epilogue

.error:
    add     rsp, SYMBOL_SIZE
.error_no_stack:
    pop     rsi
    pop     rbx
    epilogue

;*
; * [parser_concat_local_name]
; * Input: R14 = global name, RSI = local name
; * Output: RDX = concatenated name in arena
; ;
parser_concat_local_name:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     r12, r14               ; r12 = global name
    mov     r13, rsi               ; r13 = local name
    
    ; 1. Calculate lengths
    mov     rdi, r12
    extern  str_len
    call    str_len
    mov     r14, rax               ; r14 = len(global)
    
    mov     rdi, r13
    call    str_len
    add     rax, r14               ; rax = len(global) + len(local)
    inc     rax                    ; +1 for null terminator
    
    ; 2. Allocate buffer from arena
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, rax
    extern  arena_alloc
    call    arena_alloc
    check_err_to .error
    mov     r10, rdx               ; r10 = allocated buffer ptr
    
    ; 3. Copy global name to buffer
    mov     rdi, r10
    mov     rsi, r12
    mov     rcx, r14
    rep     movsb
    
    ; 4. Copy local name (including null terminator)
    mov     rsi, r13
.copy_local:
    lodsb
    stosb
    test    al, al
    jnz     .copy_local
    
    mov     rdx, r10               ; rdx = concatenated string pointer
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue


;*
; * [parser_handle_pseudo_op]
; * Input: RSI = mnemonic string
; * Output: RAX = 1 if handled, 0 if unknown
; ;
parser_handle_pseudo_op:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = mnemonic string
    ; directives are compared in lower case: NASM takes BITS, Org, SECTION
    lea     rdi, [rel pseudo_lc]
    xor     ecx, ecx
.lc:
    movzx   eax, byte [rsi + rcx]
    cmp     al, 'A'
    jb      .lc_put
    cmp     al, 'Z'
    ja      .lc_put
    or      al, 0x20
.lc_put:
    mov     [rdi + rcx], al
    test    al, al
    jz      .lc_done
    inc     ecx
    cmp     ecx, 63
    jb      .lc
    jmp     .lc_keep               ; longer than any directive
.lc_done:
    mov     r12, rdi
.lc_keep:

    ; 1. Data Directives (db, dw, dd, dq) - the whole word, not a prefix
    ;    ("dbg" or "dword_table" as a statement word is not db / dw)
    cmp     byte [r12 + 2], 0
    jne     .not_data
    mov     ax, [r12]
    IF ax, e, 'db'
        mov     rdi, rbx
        call    parser_emit_data_8
        jmp     .check_handler_result
    ELSEIF ax, e, 'dw'
        mov     rdi, rbx
        call    parser_emit_data_16
        jmp     .check_handler_result
    ELSEIF ax, e, 'dd'
        mov     rdi, rbx
        call    parser_emit_data_32
        jmp     .check_handler_result
    ELSEIF ax, e, 'dq'
        mov     rdi, rbx
        call    parser_emit_data_64
        jmp     .check_handler_result
    ELSEIF ax, e, 'dt'
        mov     esi, 10
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'do'
        mov     esi, 16
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'dy'
        mov     esi, 32
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'dz'
        mov     esi, 64
        call    parser_emit_data_wide
        jmp     .check_handler_result
        ENDIF

.not_data:
    ; 1.4 "times N <directive>" repeats the rest of the line N times
    mov     rdi, r12
    lea     rsi, [rel str_times]
    call    str_cmp_kw
    IF rax, e, OK
        mov     rdi, rbx
        call    parser_handle_times
        jmp     .check_handler_result
        ENDIF

    ; 1.5 Reservation Directives (resb, resw, resd, resq)
    cmp     byte [r12 + 4], 0
    jne     .not_res
    mov     eax, [r12]
    IF eax, e, 'resb'
        mov     rdi, rbx
        mov     rsi, 1
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resw'
        mov     rdi, rbx
        mov     rsi, 2
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resd'
        mov     rdi, rbx
        mov     rsi, 4
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resq'
        mov     rdi, rbx
        mov     rsi, 8
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'rest'
        mov     rdi, rbx
        mov     rsi, 10
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'reso'
        mov     rdi, rbx
        mov     rsi, 16
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resy'
        mov     rdi, rbx
        mov     rsi, 32
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resz'
        mov     rdi, rbx
        mov     rsi, 64
        call    parser_handle_res
        jmp     .check_handler_result
        ENDIF

.not_res:
    ; NASM's structure instances: istruc NAME / at FIELD, data / iend
    mov     rdi, r12
    lea     rsi, [rel str_istruc]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_istruc
    call    parser_istruc
    jmp     .check_handler_result
.not_istruc:
    mov     rdi, r12
    lea     rsi, [rel str_at]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_at
    call    parser_at
    jmp     .check_handler_result
.not_at:
    mov     rdi, r12
    lea     rsi, [rel str_iend]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_iend
    call    parser_iend
    jmp     .check_handler_result
.not_iend:
    mov     rdi, r12
    lea     rsi, [rel str_absolute]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_absolute
    call    parser_absolute
    jmp     .check_handler_result
.not_absolute:
    mov     rdi, r12
    lea     rsi, [rel str_alignb_d]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_alignb
    call    parser_alignb
    jmp     .check_handler_result
.not_alignb:
    mov     rdi, r12
    lea     rsi, [rel str_incbin]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_incbin
    call    parser_incbin
    jmp     .check_handler_result
.not_incbin:
    ; 2. Section Directive ("segment" is NASM's other name for it)
    mov     rdi, r12
    lea     rsi, [rel str_segment]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_segment
    mov     rdi, rbx
    call    parser_handle_section_directive
    jmp     .check_handler_result
.not_segment:
    ; "cpu <level>": utasm encodes whatever it is given
    mov     rdi, r12
    lea     rsi, [rel str_cpu]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_cpu
    call    parser_skip_to_eol
    mov     rax, 1
    jmp     .check_handler_result
.not_cpu:
    ; use16 / use32 / use64: bits 16 / 32 / 64
    lea     r13, [rel use_words]
.use_word:
    cmp     byte [r13], 0
    je      .not_use
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .use_hit
    add     r13, 8
    jmp     .use_word
.use_hit:
    mov     al, [r13 + 7]
    mov     [rel asm_bits], al
    xor     eax, eax
    jmp     .check_handler_result
.not_use:
    ; warning, map, list, float, sectalign, debug, required: accepted,
    ; nothing for utasm to do
    lea     r13, [rel ignored_words]
.ignored_word:
    cmp     byte [r13], 0
    je      .not_ignored
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .ignored_hit
    add     r13, 10
    jmp     .ignored_word
.ignored_hit:
    ; [list -] / [list +]: the listing stops and goes on
    mov     rdi, r12
    lea     rsi, [rel str_list]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ignored_rest
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ignored_rest
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     edi, 1
    cmp     eax, TOK_PLUS
    je      .list_switch
    xor     edi, edi
    cmp     eax, TOK_MINUS
    jne     .ignored_rest
.list_switch:
    extern  lst_listing
    call    lst_listing
.ignored_rest:
    call    parser_skip_to_eol
    mov     rax, 1
    jmp     .check_handler_result
.not_ignored:
    mov     rdi, r12
    lea     rsi, [rel str_section]
    extern  str_cmp
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_section_directive
        jmp     .check_handler_result
    ELSE
        mov     rdi, r12
        lea     rsi, [rel str_section_upper]
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    parser_handle_section_directive
            jmp     .check_handler_result
            ENDIF
        ENDIF

    ; 2.5 Comm Directive
    mov     rdi, r12
    lea     rsi, [rel str_comm]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_comm
        jmp     .check_handler_result
        ENDIF

    ; alignmode MODE [, threshold | nojmp]: once %use smartalign defined it
    extern  smartalign_mode
    cmp     byte [rel smartalign_mode], 0
    je      .not_alignmode
    mov     rdi, r12
    lea     rsi, [rel str_alignmode]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_alignmode
    call    parser_alignmode
    jmp     .check_handler_result
.not_alignmode:

    ; 3. Align Directives
    mov     rdi, r12
    lea     rsi, [rel str_align]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        xor     rsi, rsi           ; type = 0 (byte)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_p2align]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, 1             ; type = 1 (p2)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    ; 4. Visibility Directives (global, weak, local)
    mov     rdi, r12
    lea     rsi, [rel str_global]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_GLOBAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_weak]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_WEAK
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_local]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_LOCAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    ; static NAME: a local symbol, kept in the object by name
    mov     rdi, r12
    lea     rsi, [rel str_static_d]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_LOCAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    ; common NAME SIZE[:ALIGN]
    mov     rdi, r12
    lea     rsi, [rel str_common_d]
    call    str_cmp_kw
    IF rax, e, 0
        call    parser_handle_common
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_org]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_org
        jmp     .check_handler_result
        ENDIF
    
    mov     rdi, r12
    lea     rsi, [rel str_extern]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_extern
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_default]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_default
        jmp     .check_handler_result
    ELSE
        mov     rdi, r12
        lea     rsi, [rel str_default_upper]
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    parser_handle_default
            jmp     .check_handler_result
            ENDIF
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_equ]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_equ
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_bits]
    call    str_cmp_kw
    IF rax, e, 0
        call    parser_handle_bits
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_struc]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    preprocessor_next_token
        test    rax, rax
        jnz     .done
        mov     rsi, rdx
        mov     rdi, rbx
        call    parser_parse_struc
        jmp     .check_handler_result
        ENDIF

    xor     rax, rax               ; Not a pseudo-op
    jmp     .done

.check_handler_result:
    test    rax, rax
    jnz     .done
    mov     rax, 1

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

%define INCBIN_CHUNK 4096
%define DS_UTF_SIZE  16384        ; __utf16__ / __utf32__ output
%define TIMES_CAPACITY 256
%define GSIZE_MAX      256          ; "global f:function (size)" per file
%define GSIZE_TOKENS   64           ; tokens in one size expression

;*
; * [parser_data_string]
; * Purpose: A data item that is a string: a "..." / `...` string, or a
; *   quoted literal standing alone ('abc', not 'a'+1). Its bytes are
; *   emitted and zero-padded to a whole number of units, as NASM does
; *   (dd "abcde" is 8 bytes). Anything else is handed back untouched.
; * Input  : RBX = PrepState, ESI = unit in bytes
; * Output : RAX = OK or an error, EDX = 1 when a string was emitted
; ;
parser_data_string:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15d, esi
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .string
    cmp     eax, TOK_IDENT
    je      .utf
    cmp     eax, TOK_CHAR
    jne     .not
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_COMMA
    je      .chars
    cmp     eax, TOK_NEWLINE
    je      .chars
    cmp     eax, TOK_EOF
    je      .chars
.not:
    mov     rdi, rbx
    mov     rsi, r12
    call    preprocessor_unread_token      ; ahead of the token peeked
    xor     eax, eax
    xor     edx, edx
    jmp     .ret
.chars:
    mov     rax, [r12 + TOKEN_value]       ; packed, first character lowest
    mov     [rel ds_chars], rax
    lea     r14, [rel ds_chars]
    movzx   r13d, word [r12 + TOKEN_len]
    jmp     .emit

.utf:
    ; __utf16__('text') and the others: the string in UTF-16 / UTF-32
    mov     rdi, [r12 + TOKEN_value]
    call    parser_utf_kind
    test    eax, eax
    jz      .not
    mov     r14d, eax                      ; the form
    ; the parentheses may be left out: __utf16__ "text"
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .utf_text
    or      r14d, 0x100                    ; a ")" to come
    mov     rdi, rbx
    call    preprocessor_next_token
.utf_text:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    movzx   r13d, word [r12 + TOKEN_len]
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    je      .utf_chars
    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    jne     .utf_bad
    mov     rsi, [r12 + TOKEN_value]
    test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .utf_close
    mov     rdi, rsi
    call    str_len
    mov     r13, rax
    mov     rsi, [r12 + TOKEN_value]
    jmp     .utf_close
.utf_chars:
    mov     rax, [r12 + TOKEN_value]
    mov     [rel ds_chars], rax
    lea     rsi, [rel ds_chars]
.utf_close:
    test    r14d, 0x100
    jz      .utf_encode
    push    rsi
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rsi
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .utf_bad
.utf_encode:
    mov     rdi, rsi
    mov     rsi, r13
    movzx   edx, r14b
    call    parser_utf_encode
    test    rax, rax
    jnz     .ret
    lea     r14, [rel ds_utf]
    mov     r13, rdx
    jmp     .emit
.utf_bad:
    mov     eax, EXIT_INVALID_EXPR
    jmp     .ret
.string:
    mov     r14, [r12 + TOKEN_value]
    movzx   r13d, word [r12 + TOKEN_len]
    test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .emit
    mov     rdi, r14
    call    str_len
    mov     r13, rax
.emit:
    mov     rax, r13
    xor     edx, edx
    div     r15
    xor     ecx, ecx
    test    rdx, rdx
    jz      .no_pad
    mov     rcx, r15
    sub     rcx, rdx
.no_pad:
    mov     [rel ds_pad], rcx
.byte:
    test    r13, r13
    jz      .pad
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, byte [r14]
    call    asmctx_emit_byte
    test    rax, rax
    jnz     .ret
    inc     r14
    dec     r13
    jmp     .byte
.pad:
    cmp     qword [rel ds_pad], 0
    je      .done
    mov     rdi, [rbx + PREP_ctx]
    xor     esi, esi
    call    asmctx_emit_byte
    dec     qword [rel ds_pad]
    jmp     .pad
.done:
    xor     eax, eax
    mov     edx, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_emit_data_wide]
; * Purpose: dt / do / dy / dz: 10-, 16-, 32- and 64-byte items: a
; *   floating-point constant in dt (the x87 80-bit format) or a string,
; *   zero-padded to the unit. NASM takes no plain integer here.
; * Input  : RBX = PrepState, ESI = unit in bytes
; * Output : RAX = OK or an error
; ;
;*
; * [parser_utf_kind]
; * Purpose: Which of NASM's string functions a name is: __utf16__,
; *   __utf16le__, __utf16be__, __utf32__, __utf32le__, __utf32be__ (also
; *   spelled __?utf16?__ ...).
; * Input  : RDI = name
; * Output : EAX = 0 none, else 1 UTF-16 / 2 UTF-32, | 4 big-endian
; ;
parser_utf_kind:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel utf_fn_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_utf_encode]
; * Purpose: UTF-8 text as UTF-16 (surrogate pairs above U+FFFF) or UTF-32,
; *   little- or big-endian, into ds_utf.
; * Input  : RDI = text, RSI = its length, EDX = parser_utf_kind's form
; * Output : RAX = OK or EXIT_INVALID_EXPR (not UTF-8, too long),
; *          RDX = bytes written
; ;
parser_utf_encode:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                       ; r12 = position
    lea     r13, [rdi + rsi]               ; r13 = end
    mov     r14d, edx                      ; r14 = form
    lea     r15, [rel ds_utf]              ; r15 = output
.char:
    cmp     r12, r13
    jae     .done
    lea     rax, [rel ds_utf + DS_UTF_SIZE - 8]
    cmp     r15, rax
    jae     .bad
    movzx   edx, byte [r12]
    mov     eax, 1
    cmp     edx, 0x80
    jb      .have                          ; ASCII (and NUL)
    mov     rdi, r12
    mov     rsi, r13
    extern  str_utf8_decode
    call    str_utf8_decode                ; rax = length, rdx = code point
    test    rax, rax
    jz      .bad
.have:
    add     r12, rax
    test    r14d, 2
    jnz     .utf32
    cmp     edx, 0x10000
    jb      .unit
    ; a surrogate pair
    sub     edx, 0x10000
    push    rdx
    shr     edx, 10
    add     edx, 0xD800
    call    .put16
    pop     rdx
    and     edx, 0x3FF
    add     edx, 0xDC00
.unit:
    call    .put16
    jmp     .char
.utf32:
    test    r14d, 4
    jz      .le32
    bswap   edx
.le32:
    mov     [r15], edx
    add     r15, 4
    jmp     .char
.done:
    lea     rdx, [rel ds_utf]
    neg     rdx
    add     rdx, r15
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_INVALID_EXPR
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
.put16:
    test    r14d, 4
    jz      .le16
    xchg    dl, dh
.le16:
    mov     [r15], dx
    add     r15, 2
    ret

parser_emit_data_wide:
    push    r12
    push    r13
    mov     r12d, esi
.loop:
    mov     esi, r12d
    call    parser_data_string
    test    rax, rax
    jnz     .ret
    test    edx, edx
    jnz     .next
    ; dt: the x87 80-bit format; do: binary128
    xor     eax, eax
    cmp     r12d, 10
    jne     .fmt_do
    mov     eax, FLT_EXT
.fmt_do:
    cmp     r12d, 16
    jne     .fmt
    mov     eax, FLT_QUAD
.fmt:
    mov     [rel float_fmt], al
    mov     byte [rel float_seen], 0
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel float_fmt], 0
    test    rax, rax
    jnz     .ret
    ; as in NASM, only a float constant (dt) or a string fills these
    cmp     byte [rel float_seen], 0
    je      .not_float
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    call    asmctx_emit_qword
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rel float_hi]            ; sign and exponent / high half
    cmp     r12d, 16
    je      .quad_hi
    call    asmctx_emit_word
    jmp     .next
.quad_hi:
    extern  asmctx_emit_qword
    call    asmctx_emit_qword
    jmp     .next
.not_float:
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .ret
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .loop
.done:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_float_special]
; * Purpose: Is this name __Infinity__, __QNaN__ or __SNaN__?
; * Input  : RDI = name
; * Output : EAX = 1, 2, 3, or 0
; ;
parser_float_special:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel float_special_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_float_func]
; * Purpose: Is this name __float16__, __float32__ or __float64__?
; * Input  : RDI = name
; * Output : EAX = the FLT_* format, or 0
; ;
parser_float_func:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel float_fn_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_incbin]
; * Purpose: incbin "file" [, offset [, length]]: the file's bytes.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_incbin:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     r12, [rdx + TOKEN_value]
    cmp     eax, TOK_STRING
    je      .have_name
    cmp     eax, TOK_CHAR
    jne     .bad
    mov     [rel ds_chars], r12            ; a short 'name', unpacked
    mov     byte [rel ds_chars + 8], 0
    lea     r12, [rel ds_chars]
.have_name:
    xor     r13d, r13d                     ; offset
    mov     r14, -1                        ; length: to the end
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .open
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .open
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
.open:
    mov     rdi, r12                       ; as named, then in each -I dir
    extern  incpath_open
    call    incpath_open
    test    rax, rax
    jnz     .not_found
    mov     r15, rdx                       ; fd
    mov     rdi, r15
    mov     rsi, r13
    xor     edx, edx                       ; SEEK_SET
    call    io_lseek
.chunk:
    test    r14, r14
    jz      .close
    mov     rdx, INCBIN_CHUNK
    cmp     r14, rdx
    jae     .read
    mov     rdx, r14
.read:
    mov     rdi, r15
    lea     rsi, [rel incbin_buf]
    call    io_read
    test    rax, rax
    jnz     .close_error
    test    rdx, rdx
    jz      .close                         ; end of the file
    sub     r14, rdx
    mov     r13, rdx
    lea     r12, [rel incbin_buf]
.byte:
    test    r13, r13
    jz      .chunk
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, byte [r12]
    call    asmctx_emit_byte
    inc     r12
    dec     r13
    jmp     .byte
.close:
    mov     rdi, r15
    call    io_close
    mov     edi, 1                         ; the listing: <bin Nh>
    extern  lst_mark
    call    lst_mark
    xor     eax, eax
    jmp     .ret
.close_error:
    mov     r13, rax
    mov     rdi, r15
    call    io_close
    mov     rax, r13
    jmp     .ret
.not_found:
    push    rax                            ; "unable to open `x': no such file"
    mov     rdi, r12
    call    error_set_subject
    pop     rax
    jmp     .ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
str_incbin:    db "incbin", 0
str_list:      db "list", 0
; name (15 bytes) + FLT_* format
; NASM's string functions: name (15), form (parser_utf_kind)
utf_fn_names:
              db "__utf16__", 0, 0, 0, 0, 0, 0, 1
              db "__?utf16?__", 0, 0, 0, 0, 1
              db "__utf16le__", 0, 0, 0, 0, 1
              db "__?utf16le?__", 0, 0, 1
              db "__utf16be__", 0, 0, 0, 0, 5
              db "__?utf16be?__", 0, 0, 5
              db "__utf32__", 0, 0, 0, 0, 0, 0, 2
              db "__?utf32?__", 0, 0, 0, 0, 2
              db "__utf32le__", 0, 0, 0, 0, 2
              db "__?utf32le?__", 0, 0, 2
              db "__utf32be__", 0, 0, 0, 0, 6
              db "__?utf32be?__", 0, 0, 6
              db 0
float_fn_names: db "__float16__", 0, 0,0,0, FLT_HALF
               db "__float32__", 0, 0,0,0, FLT_SINGLE
               db "__float64__", 0, 0,0,0, FLT_DOUBLE
               db "__float80m__", 0, 0,0, FLT_EXT
               db "__float80e__", 0, 0,0, FLT_EXT | FLT_HIGH
               db "__float128l__", 0, 0, FLT_QUAD
               db "__float128h__", 0, 0, FLT_QUAD | FLT_HIGH
               db "__?float16?__", 0, 0, FLT_HALF
               db "__?float32?__", 0, 0, FLT_SINGLE
               db "__?float64?__", 0, 0, FLT_DOUBLE
               db 0
; name (15 bytes) + 1 infinity / 2 quiet NaN / 3 signalling NaN
float_special_names:
               db "__Infinity__", 0, 0, 0, 1
               db "__QNaN__", 0, 0, 0, 0, 0, 0, 0, 2
               db "__SNaN__", 0, 0, 0, 0, 0, 0, 0, 3
               db "__?Infinity?__", 0, 1
               db "__?QNaN?__", 0, 0, 0, 0, 0, 2
               db "__?SNaN?__", 0, 0, 0, 0, 0, 3
               db 0
[SECTION .bss]
float_fmt:     resb 1              ; FLT_* for a float constant here, 0: none
float_seen:    resb 1              ; the last value was a float constant
float_hi:      resq 1              ; its 80-bit sign/exponent word, or
                                   ; binary128's high half
float_part:    resb 1              ; a float function's FLT_HIGH
float_fn_val:  resq 1
ds_utf:        resb DS_UTF_SIZE    ; __utf16__ / __utf32__ text
far_colon:     resb 1              ; a far pointer's colon came with its segment
global expr_coeff
expr_coeff:    resq 1              ; how the last value moves with $ (1: $ itself)
times_newline: resq 1              ; the token that ends a times line
times_padto:   resb 1              ; this times count is K - ($ - $$)
equ_again:     resb 1              ; this equ defines a constant again
pseudo_lc:     resb 64             ; a statement word in lower case
ds_chars:      resq 2              ; a quoted literal's characters
ds_pad:        resq 1
incbin_buf:    resb 4096
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
    mov     [rel asm_bits], dl
    xor     eax, eax
.ret:
    ret

[SECTION .data]
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
; directive names, 10 bytes each
ignored_words:  db "warning", 0, 0, 0
                db "map", 0, 0, 0, 0, 0, 0, 0
                db "list", 0, 0, 0, 0, 0, 0
                db "float", 0, 0, 0, 0, 0
                db "sectalign", 0
                db "debug", 0, 0, 0, 0, 0
                db "required", 0, 0
                db 0
[SECTION .bss]
stmt_bracketed: resb 1              ; the statement is in [ ]
[SECTION .text]

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
    add     [rax + SECTION_size], rcx
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
; *   NOPs "align" pads code with (optimizer/align.s).
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
    jae     .done
    xor     esi, esi
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
    xor     eax, eax
    ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    ret

;*
; * [parser_at]
; * Purpose: "at FIELD, <data>": zero-fill up to the field; the data after
; *          the comma is then parsed as a statement of its own.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_at:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     rdi, [rel istruc_base]
    add     rdi, rdx
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
[SECTION .text]

;*
; * [parser_handle_times]
; * Purpose: "times N <directive>" — evaluate the count, then replay the rest
; *   of the line N times by rewinding the lexer. The repeated statement has
; *   to come from the file: a macro or %rep body is replayed from a token
; *   array the lexer cannot be rewound into.
; * Input:
; *   RDI: pointer to PrepState
; * Output:
; *   RAX = EXIT_OK or error code
; ;
parser_handle_times:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    ; 1. Repetition count. "times K-($-$$) db F" pads up to offset K: the
    ;    jump optimizer can then shorten jumps before it and pad more
    ;    (RELAX_PADTO), so the "$ - $$" in it freezes nothing.
    call    relax_defer_begin
    mov     byte [rel times_padto], 0
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    cmp     qword [rel expr_coeff], -1
    jne     .count_done
    test    r15, r15
    js      .count_done
    mov     rax, [rbx + PREP_ctx]
    mov     rdi, [rax + ASMCTX_curr_sec]
    test    rdi, rdi
    jz      .count_done
    mov     rsi, [rdi + SECTION_size]
    call    relax_pending_padto
    mov     [rel times_padto], al
.count_done:

    ; 2. The statement to repeat, with the newline ending it, becomes a
    ;    %rep body: the parser then reads it N times, whether it is an
    ;    instruction or a directive, from a file or inside a macro.
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TIMES_CAPACITY * TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     r12, rdx                   ; the tokens
    xor     r13d, r13d                 ; how many
.token:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .captured
    cmp     eax, TOK_EOF
    je      .captured
    cmp     r13d, TIMES_CAPACITY - 1
    jae     .too_long
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     rsi, rdx
    imul    rdi, r13, TOKEN_SIZE
    add     rdi, r12
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    inc     r13d
    jmp     .token
.captured:
    mov     [rel times_newline], rdx       ; the newline peeked
    ; "db F" with F a number or a character: written directly, N bytes
    ; (times 4194304 db 0 is a table, not four million statements); with a
    ; count K - ($ - $$) it is padding the jump optimizer can lengthen
    cmp     r13d, 2
    jne     .not_padto
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_padto
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_db]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_padto
    movzx   eax, byte [r12 + TOKEN_SIZE + TOKEN_kind]
    mov     rdx, [r12 + TOKEN_SIZE + TOKEN_value]
    cmp     eax, TOK_CHAR
    je      .padto_fill
    cmp     eax, TOK_NUMBER
    jne     .not_padto
    mov     rdi, rdx
    call    str_to_int
    test    rax, rax
    jnz     .not_padto
.padto_fill:
    test    r15, r15
    js      .not_padto                     ; a negative count
    cmp     byte [rel times_padto], 0
    jne     .padto_record                  ; even empty now: it can grow
    test    r15, r15
    jz      .not_padto                     ; times 0
    jmp     .fill_bytes
.padto_record:
    xor     edi, edi
    call    relax_defer_end                ; the range is the padding's own
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r15
    movzx   edx, dl
    extern  asm_ctx_padto
    call    asm_ctx_padto
    test    rax, rax
    jnz     .ret
    jmp     .filled
.fill_bytes:
    mov     edi, 1
    call    relax_defer_end
    mov     r14d, edx                      ; the byte
.fill_byte:
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, r14b
    call    asmctx_emit_byte
    dec     r15
    jnz     .fill_byte
.filled:
    mov     edi, 2                         ; the listing: 00<rep Nh>
    call    lst_mark
    jmp     .ok
.not_padto:
    mov     edi, 1
    call    relax_defer_end
    test    r13d, r13d
    jz      .ok                        ; "times N" alone
    test    r15, r15
    jle     .ok                        ; "times 0": the line is consumed
    ; the newline that ends each repetition
    mov     rsi, [rel times_newline]
    imul    rdi, r13, TOKEN_SIZE
    add     rdi, r12
    mov     r14, rdi
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    mov     byte [r14 + TOKEN_kind], TOK_NEWLINE
    inc     r13d
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_TIMES
    mov     qword [rdx + MACRO_name], 0    ; anonymous, like a %rep body
    mov     [rdx + MACRO_ntokens], r13d
    mov     [rdx + MACRO_tokens], r12
    mov     rdi, rbx
    mov     rsi, rdx
    extern  prep_expand_start
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
    mov     [rdx + MACROEXP_rep_count], r15d
.ok:
    xor     eax, eax
.ret:
    push    rax
    mov     edi, 1
    call    relax_defer_end                ; (nothing left when done above)
    pop     rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.too_long:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret

;*
; * [parser_drain_line]
; * Purpose: Consume tokens up to and including the next newline.
; * Input:
; *   RDI: pointer to PrepState
; ;
parser_drain_line:
    prologue
    push    rbx
    mov     rbx, rdi
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    IF byte [rdx + TOKEN_kind], e, TOK_EOF
        jmp .done
        ENDIF
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    IF byte [rdx + TOKEN_kind], ne, TOK_NEWLINE
        jmp .loop
        ENDIF
.done:
    xor     rax, rax
    pop     rbx
    epilogue

;*
; * [parser_check_aarch64_shift]
; * Input: RDI = Name String
; * Output: RAX = SHIFT_* or ERR
; ;
parser_check_aarch64_shift:
    prologue
    push    rbx
    mov     rbx, rdi
    
    lea     rsi, [str_lsl]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_LSL
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_lsr]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_LSR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_asr]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_ASR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_ror]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_ROR
        jmp .done
        ENDIF
    
    mov     rax, ERR
.done:
    pop     rbx
    epilogue
; * RSI = type (0 = byte, 1 = p2)
; ;
parser_handle_align:
    prologue
    push    r12
    push    r13
    push    r14
    mov     r12, rsi               ; r12 = type
    
    call    parser_evaluate_expression
    check_err
    mov     r13, rdx               ; r13 = alignment value
    
    ; If p2, convert to byte
    IF r12, e, 1
        ; Safety: Limit exponent to 16 (64KB max alignment for industrial stability)
        IF r13, g, 16
            mov rax, EXIT_ALIGN_ERROR
            jmp .error
            ENDIF
        mov     rcx, r13
        mov     rax, 1
        shl     rax, cl
        mov     r13, rax
        ELSE
        ; Safety: Validate power-of-2 for standard alignment
        mov     rax, r13
        test    rax, rax
        jz      .error_invalid_align
        mov     rcx, rax
        dec     rcx
        test    rax, rcx
        jnz     .error_invalid_align
        ENDIF
    
    ; Check for optional fill
    xor     r14, r14               ; default fill
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        ; NASM writes the fill as an instruction: "align 4, db 0xCC"
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_IDENT
        jne     .fill_value
        mov     rdi, [rdx + TOKEN_value]
        lea     rsi, [rel str_db]
        call    str_cmp_kw
        test    rax, rax
        jnz     .fill_value
        mov     rdi, rbx
        call    preprocessor_next_token    ; consume "db"
    .fill_value:
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
        movzx   r14d, dl
        or      r14d, 0x100            ; written by the source
        ELSE
        ; Architecture-specific NOP selection
        mov     rdi, [rbx + PREP_ctx]
        mov     al, [rdi + ASMCTX_target]
        IF al, e, TARGET_AARCH64
            ; For AArch64, NOP is a 4-byte word. Our aligner is byte-based.
            ; Simplified: use 0x00 for now or implement multi-byte padding.
            mov     r14, 0x00
        ELSEIF al, e, TARGET_RISCV64
            mov     r14, 0x00
            ELSE
            mov     r14, 0x90       ; x86_64 NOP
            ENDIF
            ENDIF

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    mov     rdx, r14
    test    r14d, 0x100
    jz      .auto_fill
    extern  asm_ctx_align_fill
    call    asm_ctx_align_fill
    jmp     .aligned
.auto_fill:
    call    asm_ctx_align
.aligned:
    mov     edi, 2                         ; the listing: 90<rep Nh>
    extern  lst_mark
    call    lst_mark

    ; all three: popping only r12 handed the caller back a wrong r12 and a
    ; clobbered r13/r14, which crashed right after "align 4, <fill>"
    pop     r14
    pop     r13
    pop     r12
    mov     rax, OK
    epilogue

.error_invalid_align:
    mov     rax, EXIT_ALIGN_ERROR
    jmp     .error

.error:
    pop     r14
    pop     r13
    pop     r12
    epilogue

;*
; * [parser_handle_org]
; ;
parser_handle_org:
    prologue
    call    parser_evaluate_expression
    check_err
    
    mov     rdi, [rbx + PREP_ctx]
    mov     r10, [rdi + ASMCTX_curr_sec]
    mov     rdi, [rbx + PREP_ctx]
    mov     r10, [rdi + ASMCTX_curr_sec]
    mov     [r10 + SECTION_addr], rdx
    epilogue

.error:
    epilogue

;*
; * [parser_handle_equ]
; ;
parser_handle_equ:
    prologue
    push    r12
    push    r13

    ; the name this line defines: taken before the expression, whose
    ; symbols would otherwise be taken for it
    mov     rax, [rbx + PREP_ctx]
    mov     r13, [rax + ASMCTX_last_symbol]
    test    r13, r13
    jz      .no_name

    mov     qword [rel known_pos_uses], 0
    extern  known_diff_n
    mov     qword [rel known_diff_n], 0
    call    parser_evaluate_expression
    check_err_to .error
    mov     r12, rdx               ; r12 = value

    ; a symbol not defined yet: its value is unknown here, and utasm reads
    ; the source once
    test    rcx, rcx
    jnz     .forward

    ; a constant defined again: the same value, or the error a label
    ; defined twice gets
    cmp     byte [rel equ_again], 0
    je      .first
    mov     byte [rel equ_again], 0
    test    r11, r11
    jz      .again_value
    cmp     byte [r11], TAG_SYMBOL
    jne     .again_value
    cmp     word [r11 + SYMBOL_section], 0xFFF1
    jne     .again_bad                     ; now a label
.again_value:
    cmp     r12, [r13 + SYMBOL_value]
    jne     .again_bad
    xor     eax, eax
    jmp     .error
.again_bad:
    mov     rdi, [r13 + SYMBOL_name]
    call    error_set_subject
    mov     rax, EXIT_DUP_SYMBOL
    jmp     .error
.first:

    ; "x equ label [+ n]": x is a label of the same section (NASM's alias),
    ; moved with it when jumps are shortened. Anything else - a number, a
    ; difference of two labels ("$ - msg"), a constant - is a constant.
    mov     word [r13 + SYMBOL_section], 0xFFF1      ; SHN_ABS
    test    r11, r11
    jz      .set
    cmp     byte [r11], TAG_SYMBOL
    jne     .set
    cmp     byte [r11 + SYMBOL_kind], SYM_LABEL
    jne     .set
    movzx   eax, word [r11 + SYMBOL_section]
    test    eax, eax
    jz      .set
    cmp     eax, 0xFF00
    jae     .set
    mov     [r13 + SYMBOL_section], ax
    mov     byte [r13 + SYMBOL_kind], SYM_LABEL
.set:
    mov     [r13 + SYMBOL_value], r12
    ; "len equ $ - msg", "x equ label + 4": not a constant a second pass
    ; could take before its definition (core/known.s)
    cmp     qword [rel known_pos_uses], 0
    je      .set_done
    or      byte [r13 + SYMBOL_pflags], SYMF_POSDEP
    ; just one "b - a": it may turn out fixed (known_second_pass)
    cmp     qword [rel known_diff_n], 1
    jne     .set_done
    cmp     qword [rel known_pos_uses], 2
    jne     .set_done
    mov     rdi, r13
    extern  known_note_equ_diff
    call    known_note_equ_diff
.set_done:
    xor     eax, eax
    jmp     .error

.forward:
    mov     rdi, rcx               ; "equ: `y' is not defined yet"
    call    error_set_subject
    mov     rax, EXIT_EQU_FORWARD
    jmp     .error
.no_name:
    mov     rax, EXIT_UNDEF_SYMBOL
.error:
    pop     r13
    pop     r12
    epilogue

[SECTION .rodata]
str_equ:    db "equ", 0

[SECTION .text]

parser_emit_data_8:
    prologue
    push    r13
    push    r14
.loop:
    mov     esi, 1
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next_item
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_CHAR
        ; a quoted literal on its own is a string: db 'abc' is 3 bytes
        mov     rdi, rbx
        call    preprocessor_peek_token
        movzx   eax, byte [rdx + TOKEN_kind]
        cmp     eax, TOK_COMMA
        je      .char_bytes
        cmp     eax, TOK_NEWLINE
        je      .char_bytes
        cmp     eax, TOK_EOF
        je      .char_bytes
        mov     al, TOK_CHAR               ; part of an expression ('a'+1)
        jmp     .not_char
.char_bytes:
        movzx   r13d, word [r12 + TOKEN_len]
        mov     r14, [r12 + TOKEN_value]
.char_byte:
        test    r13d, r13d
        jz      .next_item
        mov     rdi, [rbx + PREP_ctx]
        movzx   esi, r14b
        call    asmctx_emit_byte
        shr     r14, 8
        dec     r13d
        jmp     .char_byte
        ENDIF
.not_char:
    IF al, e, TOK_STRING
        mov     rsi, [r12 + TOKEN_value]
        mov     rdi, [rbx + PREP_ctx]
        extern  asmctx_emit_string
        call    asmctx_emit_string
        ELSE
        mov     rdi, rbx
        mov     rsi, r12
        call    preprocessor_unread_token  ; 'a'+1: the '+' is peeked
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rdx
        extern  asmctx_emit_byte
        call    asmctx_emit_byte
        ENDIF

.next_item:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    pop     r14
    pop     r13
    epilogue

.error:
    pop     r14
    pop     r13
    epilogue

parser_emit_data_16:
    prologue
.loop:
    mov     esi, 2
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_HALF
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel float_fmt], 0
    check_err
    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain16
    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_16
    call    reloc_record
    check_err
    xor     esi, esi
    jmp     .emit16
.plain16:
    mov     rsi, r10
.emit16:
    mov     rdi, [rbx + PREP_ctx]
    extern  asmctx_emit_word
    call    asmctx_emit_word
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    epilogue

.error:
    epilogue

;*
; * [parser_data_symbol]
; * Purpose: Decide whether an initialised data word refers to an address the
; *   linker has to fill in, and with what name and addend. "dq label" must
; *   be relocated: emitting the section-relative value in place leaves a
; *   table of offsets rather than pointers, which faults on first use.
; *   Constants and struct fields are plain numbers and never relocate.
; * Input:
; *   R8  = resolved SYMBOL* (0 if none)
; *   R9  = deferred name string (0 if none, for a forward reference)
; *   R10 = the evaluated value
; * Output:
; *   RSI = name to relocate against, or 0 for a plain number
; *   RDI = addend to record
; ;
parser_data_symbol:
    xor     rsi, rsi
    mov     rdi, r10
    test    r8, r8
    jz      .try_deferred

    ; A resolved symbol only carries an address for these kinds
    movzx   eax, byte [r8 + SYMBOL_kind]
    cmp     al, SYM_LABEL
    je      .use_symbol
    cmp     al, SYM_DATA
    je      .use_symbol
    cmp     al, SYM_EXTERN
    je      .use_symbol
    cmp     al, SYM_COMMON
    je      .use_symbol
    ret                            ; constant / struct / macro: a number

.use_symbol:
    mov     rsi, [r8 + SYMBOL_name]
    mov     rdi, r10
    sub     rdi, [r8 + SYMBOL_value]   ; addend = whatever was added to it
    ret

.try_deferred:
    test    r9, r9
    jz      .done
    mov     rsi, r9                ; forward reference: the value is the addend
    mov     rdi, r10
.done:
    ret

parser_emit_data_32:
    prologue
.loop:
    mov     esi, 4
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_SINGLE
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel float_fmt], 0
    check_err

    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain

    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_32
    extern  reloc_record
    call    reloc_record
    check_err
    mov     rdi, [rbx + PREP_ctx]
    xor     rsi, rsi
    extern  asmctx_emit_dword
    call    asmctx_emit_dword
    jmp     .next

.plain:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r10
    call    asmctx_emit_dword

.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    xor     rax, rax
    epilogue

.error:
    epilogue

parser_emit_data_64:
    prologue
.loop:
    mov     esi, 8
    call    parser_data_string
    check_err
    test    edx, edx
    jnz     .next
    mov     byte [rel float_fmt], FLT_DOUBLE
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel float_fmt], 0
    check_err

    mov     r10, rdx
    mov     r8, r11
    mov     r9, rcx
    call    parser_data_symbol
    test    rsi, rsi
    jz      .plain

    mov     rdx, rsi               ; name
    mov     rcx, rdi               ; addend
    mov     rdi, [rbx + PREP_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rsi, [rax + SECTION_size]
    mov     r8, R_X86_64_64
    call    reloc_record
    check_err
    mov     rdi, [rbx + PREP_ctx]
    xor     rsi, rsi
    extern  asmctx_emit_qword
    call    asmctx_emit_qword
    jmp     .next

.plain:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r10
    call    asmctx_emit_qword

.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    xor     rax, rax
    epilogue

.error:
    epilogue

;*
; * [parser_handle_res]
; * Purpose: RESB/RESW/RESD/RESQ — reserve uninitialised space in the
; *          current section (no bytes are emitted, the section just grows).
; * Input:
; *   RDI: PrepState*
; *   RSI: element size in bytes (1, 2, 4 or 8)
; * Output: RAX = EXIT_OK or error code
; ;
parser_handle_res:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = element size

    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err
    imul    rdx, r12               ; total bytes to reserve

    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .no_section
    add     [rax + SECTION_size], rdx
    xor     rax, rax
    jmp     .done

.no_section:
    mov     rax, EXIT_INTERNAL

.error:
.done:
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_handle_extern]
; * Input: None (reads from preprocessor)
; ;
parser_handle_extern:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
.loop:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .done
    mov     r12, rdx               ; r12 = token (name)
    
    IF byte [r12 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF

    ; Create symbol with SYM_EXTERN kind
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    
    mov     r11, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_EXTERN
    mov     byte [rsi + SYMBOL_vis], VIS_GLOBAL
    mov     rax, [r12 + TOKEN_value]
    mov     [rsi + SYMBOL_name], rax
    
    mov     rdi, r11               ; rdi = AsmCtx
    extern  symbol_add
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    ; Re-declaring an extern is legal and idempotent
    IF rax, e, EXIT_DUP_SYMBOL
        xor     rax, rax
        ENDIF
    check_err

    ; Check for comma (extern name1, name2)
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .loop
        ENDIF

.done:
    pop     r12
    pop     rbx
    epilogue

.error:
    jmp     .done

;*
; * [parser_handle_default]
; * Stub for 'default' directive (e.g. default rel)
; ;
parser_handle_default:
    ; DEFAULT REL  - [label] with no base/index register is RIP-relative
    ; DEFAULT ABS  - back to absolute addressing (the initial state)
    ; Other words on the line (e.g. NASM's BND/NOBND) are accepted and
    ; ignored. The setting applies to the rest of the file.
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_NEWLINE
        jmp .done
        ENDIF
    IF byte [rdx + TOKEN_kind], e, TOK_EOF
        jmp .done
        ENDIF
    IF byte [rdx + TOKEN_kind], e, TOK_RBRACKET
        jmp .done                  ; [default rel]
        ENDIF
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, rdx               ; r12 = consumed token
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .loop

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_rel]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_rel
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_rel_upper]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_rel
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_abs]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_abs
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_default_abs_upper]
    call    str_cmp_kw
    test    rax, rax
    jz      .set_abs
    jmp     .loop

.set_rel:
    mov     rax, [rbx + PREP_ctx]
    or      dword [rax + ASMCTX_flags], CTX_FLAG_DEFAULT_REL
    jmp     .loop
.set_abs:
    mov     rax, [rbx + PREP_ctx]
    and     dword [rax + ASMCTX_flags], ~CTX_FLAG_DEFAULT_REL
    jmp     .loop

.done:
    pop     r12
    pop     rbx
    epilogue

[SECTION .rodata]
str_default_rel:        db "rel", 0
str_default_rel_upper:  db "REL", 0
str_default_abs:        db "abs", 0
str_default_abs_upper:  db "ABS", 0
[SECTION .text]

;*
; * [parser_default_section]
; * Purpose: Select .text before the first statement, as NASM does: code and
; *          data written before any "section" directive belong there (they
; *          were dropped), and org has a section to apply to.
; * Input  : RDI = AsmCtx
; * Output : RAX = OK or an error
; ;
global parser_default_section
parser_default_section:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rbx
    lea     rsi, [rel str_text]
    call    asmctx_find_section
    test    rax, rax
    jz      .select
    mov     rdi, rbx
    lea     rsi, [rel str_text]
    mov     rdx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     word [rdx + SECTION_flags], (SHF_ALLOC | SHF_EXECINSTR)
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     byte [rdx + SECTION_type], SEC_TEXT
    mov     byte [rdx + SECTION_implicit], 1   ; placed as NASM would (elf64_order_text)
    cmp     byte [rbx + ASMCTX_fmt], FMT_BIN
    je      .select
    mov     qword [rdx + SECTION_align], 16    ; NASM's ELF default
.select:
    mov     [rbx + ASMCTX_curr_sec], rdx
    xor     eax, eax
.ret:
    pop     rbx
    ret

;*
; * [parser_handle_section_directive]
; * Input: None (reads from preprocessor)
; ;
parser_handle_section_directive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    ; Get section name token
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx               ; r12 = token (.text, .data, etc)

    ; ".note.GNU-stack": a name with '-' in it lexes as several tokens;
    ; join the ones written together
.name_piece:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    jne     .name_done
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [r12 + TOKEN_line]
    jne     .name_done
    movzx   eax, word [r12 + TOKEN_col]
    movzx   ecx, word [r12 + TOKEN_len]
    add     eax, ecx
    cmp     ax, [rdx + TOKEN_col]
    jne     .name_done
    mov     rdi, rbx
    call    preprocessor_next_token        ; the '-'
    mov     rdi, rbx
    call    preprocessor_next_token        ; the next piece
    check_err
    mov     r13, rdx
    mov     rdi, [r12 + TOKEN_value]
    call    str_len
    mov     r14, rax
    mov     rdi, [r13 + TOKEN_value]
    call    str_len
    lea     rsi, [r14 + rax + 2]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     r15, rdx
    mov     rdi, rdx
    mov     rsi, [r12 + TOKEN_value]
    call    str_concat
    mov     byte [r15 + r14], '-'
    mov     rdi, r15
    mov     rsi, [r13 + TOKEN_value]
    call    str_concat
    mov     [r12 + TOKEN_value], r15
    mov     rdi, r15
    call    str_len
    mov     [r12 + TOKEN_len], ax
    jmp     .name_piece
.name_done:
    
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    extern  asmctx_find_section
    call    asmctx_find_section
    mov     r15, rax               ; r15 = find_section result
    
    IF r15, e, OK
        mov     r13, rdx               ; r13 = existing section
        ELSE
        ; Create new section
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, [r12 + TOKEN_value]
        mov     rdx, SEC_CUSTOM
        extern  asm_ctx_create_section
        call    asm_ctx_create_section
        check_err
        mov     r13, rdx
        ENDIF

    ; Set active section in AsmCtx
    mov     rdi, [rbx + PREP_ctx]
    mov     [rdi + ASMCTX_curr_sec], r13
    ; the default .text takes its place among the sections where the
    ; source first names it, as in NASM
    cmp     byte [r13 + SECTION_implicit], 0
    je      .named
    cmp     dword [r13 + SECTION_named_at], 0
    jne     .named
    movzx   eax, word [rdi + ASMCTX_seccount]
    mov     [r13 + SECTION_named_at], eax
.named:
    ; __SECT__ names the section a plain "section" line chose; the
    ; primitive [section ...] form leaves it, as in NASM
    cmp     byte [rel stmt_bracketed], 0
    jne     .sect_noted
    mov     rax, [r12 + TOKEN_value]
    mov     [rel user_sect_name], rax
.sect_noted:

    ; 2. Auto-assign flags and type for standard sections if new
    IF r15, ne, OK
        mov     rdi, [r12 + TOKEN_value]
        mov     dword [r13 + SECTION_elf_type], SHT_PROGBITS ; Default
        mov     word [r13 + SECTION_flags], SHF_ALLOC  ; NASM's for other names
        
        ; .text -> AX
        lea     rsi, [str_text]
        call    str_cmp
        IF rax, e, OK
            mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_EXECINSTR)
            mov byte [r13 + SECTION_type], SEC_TEXT
            ELSE
            ; .data -> AW
            mov     rdi, [r12 + TOKEN_value]   ; str_cmp advances rdi
            lea     rsi, [str_data]
            call    str_cmp
            IF rax, e, OK
                mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                mov byte [r13 + SECTION_type], SEC_DATA
                ELSE
                ; .bss -> AW, NOBITS
                mov     rdi, [r12 + TOKEN_value]
                lea     rsi, [str_bss]
                call    str_cmp
                IF rax, e, OK
                    mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                    mov dword [r13 + SECTION_elf_type], SHT_NOBITS
                    mov byte [r13 + SECTION_type], SEC_BSS
                    ELSE
                    ; .rodata -> A
                    mov     rdi, [r12 + TOKEN_value]
                    lea     rsi, [str_rodata]
                    call    str_cmp
                    IF rax, e, OK
                        mov word [r13 + SECTION_flags], SHF_ALLOC
                        mov byte [r13 + SECTION_type], SEC_RODATA
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF

    ; NASM's default alignments for the standard ELF sections: .text 16,
    ; .data / .rodata / .bss 4 (attributes below may change them)
    cmp     r15, OK
    je      .default_align_done
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    je      .default_align_done
    movzx   eax, byte [r13 + SECTION_type]
    mov     ecx, 16
    cmp     eax, SEC_TEXT
    je      .set_default_align
    mov     ecx, 4
    cmp     eax, SEC_DATA
    je      .set_default_align
    cmp     eax, SEC_BSS
    je      .set_default_align
    cmp     eax, SEC_RODATA
    jne     .default_align_done
.set_default_align:
    mov     [r13 + SECTION_align], rcx
.default_align_done:

    ; 3. NASM attributes: progbits, nobits, alloc, exec, write, align=N
    call    parser_section_attrs
    check_err

    ; Reset last_global on section change (Removed to support local labels after section directives)
    
    
    ; 3. Check for attributes (comma + string)
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    preprocessor_next_token
        check_err
        mov     r14, rdx               ; r14 = attribute token
        IF byte [r14 + TOKEN_kind], e, TOK_STRING
            mov     rsi, [r14 + TOKEN_value]
            xor     rax, rax           ; flags accumulator
        .flag_loop:
            mov     cl, [rsi]
            test    cl, cl
            jz      .flag_done
            IF cl, e, 'a'
                or ax, SHF_ALLOC
            ENDIF 
            IF cl, e, 'w'
                or ax, SHF_WRITE
            ENDIF 
            IF cl, e, 'x'
                or ax, SHF_EXECINSTR
            ENDIF 
            IF cl, e, 'M'
                or ax, SHF_MERGE
            ENDIF 
            IF cl, e, 'S'
                or ax, SHF_STRINGS
            ENDIF 
            IF cl, e, 'G'
                or ax, SHF_GROUP
            ENDIF 
            inc     rsi
            jmp     .flag_loop
        .flag_done:
            ; A90: Enforce W^X security policy (Write XOR Execute)
            mov     ecx, (SHF_WRITE | SHF_EXECINSTR)
            mov     edx, eax
            and     edx, ecx
            IF edx, e, ecx
                mov     rax, EXIT_LD_SCRIPT_PARSE
                jmp     .done
                ENDIF
            
            ; A92: Validate flag consistency for duplicate declarations; a
            ; new section takes the flags over the defaults for its name
            movzx   ecx, word [r13 + SECTION_flags]
            cmp     r15, OK
            je      .check_flags
            xor     ecx, ecx
        .check_flags:
            IF ecx, ne, 0
                IF ecx, ne, eax
                    mov     rax, EXIT_INVALID_SECTION_FLAGS
                    jmp     .done
                    ENDIF
                    ELSE
                mov     [r13 + SECTION_flags], ax
                ENDIF
            
            ; 3.1 Handle Group Signature if 'G' flag is set
            test    ax, SHF_GROUP
            jz      .no_group
            
            ; Expect comma, then signature name
            mov     rdi, rbx
            call    preprocessor_next_token
            IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
                mov     rax, EXIT_UNEXPECTED_TOKEN
                jmp     .done
                ENDIF
            mov     rdi, rbx
            call    preprocessor_next_token
            IF byte [rdx + TOKEN_kind], ne, TOK_IDENT
                mov     rax, EXIT_UNEXPECTED_TOKEN
                jmp     .done
                ENDIF
            
            mov     r14, rdx               ; r14 = signature token
            mov     rdi, [rbx + PREP_ctx]
            mov     rsi, [r14 + TOKEN_value]
            extern  symbol_find
            call    symbol_find
            IF rax, ne, OK
                ; Create UNDEF symbol as signature
                sub     rsp, SYMBOL_SIZE
                mov     rdi, rsp
                xor     rax, rax
                mov     rcx, 6
                rep stosq
                mov     rdi, [rbx + PREP_ctx]
                mov     rsi, rsp
                mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
                mov     [rsi + SYMBOL_name], r12 ; use r12 from caller context or r14? 
                ; Wait, r14 holds signature token
                mov     rax, [r14 + TOKEN_value]
                mov     [rsi + SYMBOL_name], rax
                mov     byte [rsi + SYMBOL_vis], VIS_GLOBAL
                call    symbol_add
                add     rsp, SYMBOL_SIZE
                ENDIF
            mov     [r13 + SECTION_group_sig], rdx
            
            ; 3.1.1 Check if this signature is already used in another group
            ; If not, increment group_count
            mov     r14, rdx               ; r14 = signature symbol
            mov     rdi, [rbx + PREP_ctx]
            xor     rcx, rcx               ; i = 0
        .sig_check_loop:
            cmp     cx, word [rdi + ASMCTX_seccount]
            jge     .sig_unique
            
            mov     rax, [rdi + ASMCTX_sections]
            mov     rax, [rax + rcx * 8]
            cmp     rax, r13               ; Skip current section
            je      .sig_next
            
            cmp     [rax + SECTION_group_sig], r14
            je      .sig_duplicate
        .sig_next:
            inc     rcx
            jmp     .sig_check_loop
            
        .sig_duplicate:
            jmp     .parse_comdat
            
        .sig_unique:
            inc     dword [rdi + ASMCTX_group_count]

        .parse_comdat:
            ; 3.2 Optional COMDAT keyword
            mov     rdi, rbx
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_COMMA
                mov     rdi, rbx
                call    preprocessor_next_token
                mov     rdi, rbx
                call    preprocessor_next_token
                mov     rdi, [rdx + TOKEN_value]
                lea     rsi, [str_comdat]
                call    str_cmp_kw
                IF rax, e, 0
                    mov dword [r13 + SECTION_group_flags], GRP_COMDAT
                    ENDIF
                    ENDIF
            
        .no_group:
        ENDIF

        ; 4. Optional: Type (@progbits, etc)
        mov     rdi, rbx
        call    preprocessor_peek_token
        IF byte [rdx + TOKEN_kind], e, TOK_COMMA
            mov     rdi, rbx
            call    preprocessor_next_token
            mov     rdi, rbx
            call    preprocessor_next_token
            ; Check for @progbits, @nobits, etc
            ; For now, support @ progbits as separate or joined
            ENDIF
            ENDIF
    
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_handle_visibility]
; * RSI = Target visibility (SYM_GLOBAL, SYM_WEAK)
; ;
parser_handle_visibility:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi               ; r12 = visibility

    ; global NAME[:type [visibility] [size]] [, NAME...]
.name:
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r13, rdx               ; r13 = token
    xor     r14d, r14d             ; the declared ELF type
    xor     r15d, r15d             ; bit 8: typed; low byte: visibility
    cmp     byte [r13 + TOKEN_kind], TOK_LABEL
    je      .typed                 ; "f:function": the colon made a label
    IF byte [r13 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    jmp     .have_name
.typed:
    or      r15d, 0x100
.type_word:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .have_name
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel sym_attr_words]
    call    parser_word_index      ; eax = row + 1, 0 if none
    test    eax, eax
    jz      .have_name
    imul    eax, eax, 12
    lea     rcx, [rel sym_attr_words]
    movzx   ecx, byte [rcx + rax - 1]      ; the row's value byte
    cmp     ecx, 0x10
    jb      .is_type
    and     ecx, 0x0F
    mov     r15b, cl               ; default / internal / hidden / protected
    jmp     .attr_used
.is_type:
    mov     r14d, ecx
.attr_used:
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .type_word
.have_name:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r13 + TOKEN_value]
    extern  symbol_find
    call    symbol_find

    IF rax, e, OK
        ; A91: Audit symbol binding visibility conflicts
        movzx   eax, byte [rdx + SYMBOL_vis]
        ; A global or weak symbol is already visible to the linker: demoting
        ; it to local is a conflict (the global branch used to be empty, so
        ; only weak symbols were checked)
        cmp     r12b, VIS_LOCAL
        jne     .vis_ok
        cmp     al, VIS_GLOBAL
        je      .vis_conflict
        cmp     al, VIS_WEAK
        jne     .vis_ok
.vis_conflict:
        mov     rax, EXIT_SYMBOL_RANGE
        jmp     .error
.vis_ok:
        mov     byte [rdx + SYMBOL_vis], r12b
        test    r15d, 0x100
        jz      .next_name
        mov     [rdx + SYMBOL_etype], r14b
        mov     [rdx + SYMBOL_eother], r15b
        ELSE
        ; Symbol doesn't exist, create it as UNDEFINED for now
        sub     rsp, SYMBOL_SIZE
        mov     rdi, rsp
        xor     rax, rax
        mov     rcx, SYMBOL_SIZE / 8           ; the whole record (was 48 bytes)
        rep stosq
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rsp
        mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
        mov     rax, [r13 + TOKEN_value]
        mov     [rsi + SYMBOL_name], rax
        mov     byte [rsi + SYMBOL_vis], r12b
        mov     [rsi + SYMBOL_etype], r14b
        mov     [rsi + SYMBOL_eother], r15b
        call    symbol_add
        add     rsp, SYMBOL_SIZE
        ENDIF

.next_name:
    ; "global f:function (f.end - f)": the size names labels that come
    ; later, so its tokens are kept and evaluated when the whole source
    ; has been read (parser_finish)
    test    r15d, 0x100
    jz      .rest
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .rest
    cmp     eax, TOK_EOF
    je      .rest
    cmp     eax, TOK_COMMA
    je      .rest
    mov     eax, [rel gsize_count]
    cmp     eax, GSIZE_MAX
    jae     .rest
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, (GSIZE_TOKENS + 1) * TOKEN_SIZE
    call    arena_alloc
    check_err
    mov     r14, rdx                       ; the tokens
    xor     r15d, r15d                     ; how many
.size_tok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .size_kept
    cmp     eax, TOK_EOF
    je      .size_kept
    cmp     eax, TOK_COMMA
    je      .size_kept
    cmp     r15d, GSIZE_TOKENS
    jae     .size_kept
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, rdx
    imul    rdi, r15, TOKEN_SIZE
    add     rdi, r14
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    inc     r15d
    jmp     .size_tok
.size_kept:
    test    r15d, r15d
    jz      .rest
    mov     eax, [rel gsize_count]
    lea     rcx, [rel gsize_names]
    mov     rdx, [r13 + TOKEN_value]
    mov     [rcx + rax * 8], rdx
    lea     rcx, [rel gsize_toks]
    mov     [rcx + rax * 8], r14
    lea     rcx, [rel gsize_ntok]
    mov     [rcx + rax * 4], r15d
    inc     dword [rel gsize_count]
.rest:
    ; the rest up to a comma or the end of the line
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .ok
    cmp     eax, TOK_EOF
    je      .ok
    cmp     eax, TOK_RBRACKET
    je      .ok
    push    rax
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rax
    cmp     eax, TOK_COMMA
    je      .name
    jmp     .next_name
.ok:
    mov     rax, OK
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [parser_finish]
; * Purpose: Work that needs the whole source read. The sizes written with
; *   "global f:function (f.end - f)" name labels defined later, so their
; *   tokens were kept (parser_handle_visibility) and are evaluated now,
; *   replayed through the preprocessor like a %rep body.
; * Input  : RDI = PrepState
; * Output : RAX = OK
; ;
global parser_finish
parser_finish:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    xor     r12d, r12d
.next:
    cmp     r12d, [rel gsize_count]
    jae     .done
    ; the tokens and a newline ending them
    lea     rax, [rel gsize_toks]
    mov     r13, [rax + r12 * 8]
    lea     rax, [rel gsize_ntok]
    mov     r14d, [rax + r12 * 4]
    imul    rdi, r14, TOKEN_SIZE
    add     rdi, r13
    lea     rsi, [rdi - TOKEN_SIZE]
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    imul    rax, r14, TOKEN_SIZE
    mov     byte [r13 + rax + TOKEN_kind], TOK_NEWLINE
    inc     r14d
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .skip
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     [rdx + MACRO_ntokens], r14d
    mov     [rdx + MACRO_tokens], r13
    mov     byte [rbx + PREP_has_peek], FALSE    ; the end of the file
    mov     rdi, rbx
    mov     rsi, rdx
    extern  prep_expand_start
    call    prep_expand_start
    test    rax, rax
    jnz     .skip
    mov     rdi, rbx
    call    parser_evaluate_expression
    push    rax
    push    rdx
    mov     rdi, rbx
    call    parser_drain_line              ; what is left, and the newline
    pop     rdx
    pop     rax
    test    rax, rax
    jnz     .skip
    mov     r14, rdx                       ; the size
    lea     rax, [rel gsize_names]
    mov     rsi, [rax + r12 * 8]
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .skip
    mov     [rdx + SYMBOL_size], r14
.skip:
    inc     r12d
    jmp     .next
.done:
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
gsize_count:   resd 1              ; "global f:function (size)" waiting
gsize_names:   resq GSIZE_MAX
gsize_toks:    resq GSIZE_MAX
gsize_ntok:    resd GSIZE_MAX
[SECTION .text]

;*
; * [parser_word_index]
; * Purpose: Which row of a word table (12-byte rows: the word, NUL-padded
; *   to 11 bytes, then a value byte; a 0 byte ends it) matches a word.
; * Input  : RDI = word, RSI = table
; * Output : EAX = row + 1, or 0
; ;
parser_word_index:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    xor     r14d, r14d
.row:
    cmp     byte [r13], 0
    je      .none
    inc     r14d
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 12
    jmp     .row
.hit:
    mov     eax, r14d
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_handle_common]
; * Purpose: NASM's "common NAME SIZE[:ALIGN]": an uninitialised common
; *   block, merged by the linker (SHN_COMMON, value = alignment).
; * Input  : RBX = PrepState
; ;
parser_handle_common:
    push    r12
    push    r13
    push    r14
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; size
    mov     r14d, 1                        ; alignment
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .define
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
.define:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jz      .fill
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     [rsp + SYMBOL_name], r12
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    test    rax, rax
    jnz     .ret
.fill:
    mov     byte [rdx + SYMBOL_kind], SYM_COMMON
    mov     byte [rdx + SYMBOL_vis], VIS_GLOBAL
    mov     byte [rdx + SYMBOL_etype], ETYPE_NOTYPE
    mov     word [rdx + SYMBOL_section], SHN_COMMON
    mov     [rdx + SYMBOL_value], r14
    mov     [rdx + SYMBOL_size], r13
    xor     eax, eax
    jmp     .ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
; "global f:type visibility": word (11 bytes) + value (< 0x10: an ELF
; type, 0x10 + n: a visibility)
sym_attr_words:
    db "function", 0, 0, 0, ETYPE_FUNC
    db "func", 0, 0,0,0,0,0,0, ETYPE_FUNC
    db "data", 0, 0,0,0,0,0,0, ETYPE_OBJECT
    db "object", 0, 0,0,0,0, ETYPE_OBJECT
    db "notype", 0, 0,0,0,0, ETYPE_NOTYPE
    db "default", 0, 0,0,0, 0x10
    db "internal", 0, 0, 0, 0x11
    db "hidden", 0, 0,0,0,0, 0x12
    db "protected", 0, 0, 0x13
    db 0
str_common_d:  db "common", 0
str_static_d:  db "static", 0
str_wrt:       db "wrt", 0
; "wrt ..name": word (11 bytes) + WRT_*
wrt_words:
    db "..plt", 0, 0,0,0,0,0, WRT_PLT
    db "..gotpcrel", 0, WRT_GOTPCREL
    db "..got", 0, 0,0,0,0,0, WRT_GOT
    db "..gotoff", 0, 0, 0, WRT_GOTOFF
    db "..tlsie", 0, 0,0,0, WRT_TLSIE
    db "..sym", 0, 0,0,0,0,0, WRT_SYM
    db 0
[SECTION .text]

;*
; * [parser_handle_comm]
; * Purpose: Parses .comm name, size, [align]
; ;
parser_handle_comm:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi               ; AsmCtx
    
    ; 1. Get Name
    call    preprocessor_next_token
    check_err
    mov     r11, rdx
    IF byte [r11 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp .done
        ENDIF
    mov     r12, [r11 + TOKEN_value]
    
    ; 2. Expect Comma
    call    preprocessor_next_token
    check_err
    mov     r11, rdx
    IF byte [r11 + TOKEN_kind], ne, TOK_COMMA
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp .done
        ENDIF
    
    ; 3. Get Size
    call    preprocessor_next_token
    check_err
    mov     r11, rdx
    IF byte [r11 + TOKEN_kind], ne, TOK_NUMBER
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    mov     r13, [r11 + TOKEN_value]
    
    ; A95: Strong validation for .comm size
    test    r13, r13
    jz      .error_size
    
    ; 4. Expect Comma (optional align)
    mov     r14, 1                 ; Default align = 1
    call    preprocessor_next_token
    check_err
    mov     r11, rdx
    IF byte [r11 + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        check_err
        mov     r11, rdx
        IF byte [r11 + TOKEN_kind], ne, TOK_NUMBER
            mov     rax, EXIT_UNEXPECTED_TOKEN
            jmp .done
            ENDIF
        mov     r14, [r11 + TOKEN_value]
        
        ; VALIDATION: Alignment must be power of 2
        mov     rax, r14
        test    rax, rax
        jz      .error_align
        mov     rcx, rax
        dec     rcx
        test    rax, rcx
        jnz     .error_align
        ENDIF
    
    ; 5. Create / Update Symbol
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    extern  symbol_find
    call    symbol_find
    
    IF rax, e, OK
        mov     r11, rdx
        ELSE
        sub     rsp, SYMBOL_SIZE
        mov     rdi, rsp
        xor     rax, rax
        mov     rcx, SYMBOL_SIZE / 8           ; the whole record (was 48 bytes)
        rep stosq
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rsp
        mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
        mov     [rsi + SYMBOL_name], r12
        mov     byte [rsi + SYMBOL_vis], VIS_GLOBAL
        call    symbol_add
        mov     r11, rdx
        add     rsp, SYMBOL_SIZE
        ENDIF
    
    ; Hardening for SHN_COMMON
    mov     word [r11 + SYMBOL_section], 0xFFF2 ; SHN_COMMON
    mov     [r11 + SYMBOL_value], r14           ; st_value = align
    mov     [r11 + SYMBOL_size], r13            ; st_size = size
    
    mov     rax, OK
    jmp     .done

.error_size:
    mov     rax, EXIT_INVALID_IMM
    jmp     .done

.error_align:
    mov     rax, EXIT_ALIGN_ERROR
    jmp     .done

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

[SECTION .rodata]
str_global:    db "global", 0
str_weak:      db "weak", 0
str_local:     db "local", 0
str_align:     db "align", 0
str_p2align:   db "p2align", 0
str_section:   db "section", 0
str_segment:   db "segment", 0
str_cpu:       db "cpu", 0
; words that make the name before them a label without its colon
stmt_words:    db "db", 0, "dw", 0, "dd", 0, "dq", 0, "dt", 0, "resb", 0, "resw", 0
               db "resd", 0, "resq", 0, "rest", 0, "times", 0, "incbin", 0
               db "do", 0, "dy", 0, "dz", 0, "reso", 0, "resy", 0, "resz", 0, 0
attr_progbits: db "progbits", 0
attr_nobits:   db "nobits", 0
attr_align:    db "align", 0
; alloc/noalloc, exec/noexec, write/nowrite: 8 bytes each, even = set
attr_flag_names: db "alloc", 0, 0, 0, "noalloc", 0, "exec", 0, 0, 0, 0
               db "noexec", 0, 0, "write", 0, 0, 0, "nowrite", 0
attr_flag_bits: dw SHF_ALLOC, SHF_ALLOC, SHF_EXECINSTR, SHF_EXECINSTR, SHF_WRITE, SHF_WRITE
str_section_upper: db "SECTION", 0
str_times:     db "times", 0
str_struc:     db "struc", 0
str_endstruc:  db "endstruc", 0
str_field:     db "field", 0
    ; str_rel (Defined at line 759)
str_comm:      db "comm", 0
str_lsl:       db "lsl", 0
str_lsr:       db "lsr", 0
str_asr:       db "asr", 0
str_ror:       db "ror", 0
str_comdat:    db "comdat", 0
str_org:       db "org", 0
str_text:      db ".text", 0
str_db:        db "db", 0
str_data:      db ".data", 0
str_bss:       db ".bss", 0
str_rodata:    db ".rodata", 0
str_extern:    db "extern", 0
str_default:   db "default", 0
str_default_upper: db "DEFAULT", 0
str_bits:      db "bits", 0
msg_debug_pseudo: db "DEBUG: Pseudo-op: ", 0
msg_newline:      db 10, 0
msg_debug_token:   db "DEBUG: Token: ", 0
msg_parser_entry: db "DEBUG: Parser entry", 10, 0
msg_debug_lookup: db "DEBUG: Mnemonic lookup finished", 10, 0
msg_debug_null:   db "(null)", 0

str_byte:  db "byte", 0
str_word:  db "word", 0
str_dword: db "dword", 0
str_qword: db "qword", 0
str_tword: db "tword", 0
str_tbyte:     db "tbyte", 0
str_oword: db "oword", 0
str_yword: db "yword", 0
str_zword: db "zword", 0
str_ptr:   db "ptr", 0
str_strict: db "strict", 0
str_nosplit: db "nosplit", 0
str_near:   db "near", 0
str_short:  db "short", 0
str_far:    db "far", 0
msg_debug_token_kind: db "Debug token kind: ", 0
msg_size_spec_bracket: db "Size specifier expected '[' but got kind: ", 0

[SECTION .text]
global parser_parse_size_specifier_string
parser_parse_size_specifier_string:
    prologue
    push    rbx                     ; Preserve rbx
    mov     rbx, rdi                ; rbx = input string

    ; 1. Check "byte" -> 8
    mov     rdi, rbx
    lea     rsi, [rel str_byte]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_byte

    ; 2. Check "word" -> 16
    mov     rdi, rbx
    lea     rsi, [rel str_word]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_word

    ; 3. Check "dword" -> 32
    mov     rdi, rbx
    lea     rsi, [rel str_dword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_dword

    ; 4. Check "qword" -> 64
    mov     rdi, rbx
    lea     rsi, [rel str_qword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_qword

    ; 5. Check "tword" -> 80 (and "tbyte", the MASM/GAS spelling)
    mov     rdi, rbx
    lea     rsi, [rel str_tword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_tword
    mov     rdi, rbx
    lea     rsi, [rel str_tbyte]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_tword

    ; 6. Check "oword" -> 128
    mov     rdi, rbx
    lea     rsi, [rel str_oword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_oword

    ; 7. Check "yword" -> 256
    mov     rdi, rbx
    lea     rsi, [rel str_yword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_yword

    ; 8. Check "zword" -> 512
    mov     rdi, rbx
    lea     rsi, [rel str_zword]
    call    str_cmp_kw
    test    rax, rax
    jz      .is_zword

    ; Not a size specifier
    xor     rax, rax
    jmp     .done

.is_byte:
    mov     rax, 8
    jmp     .done
.is_word:
    mov     rax, 16
    jmp     .done
.is_dword:
    mov     rax, 32
    jmp     .done
.is_qword:
    mov     rax, 64
    jmp     .done
.is_tword:
    mov     rax, 80
    jmp     .done
.is_oword:
    mov     rax, 128
    jmp     .done
.is_yword:
    mov     rax, 256
    jmp     .done
.is_zword:
    mov     rax, 512
    jmp     .done

.done:
    pop     rbx
    epilogue
