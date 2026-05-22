;
; ============================================================================
; File        : src/core/parser.s
; Project     : utasm
; Description : Multi-Architecture Instruction Parser and Dispatch System.
; ============================================================================
;

%include "include/constant.s"
%include "include/macro.s"
%include "include/type.s"

DEFAULT REL
%include "include/elf.s"
%include "include/arch/aarch64.s"

extern arena_alloc
extern preprocessor_next_token
extern preprocessor_peek_token
extern preprocessor_putback_token
extern str_to_int
extern symbol_add
extern symbol_find
extern str_compare
extern asm_ctx_align
extern str_concat
extern error_emit
extern asm_ctx_create_section
extern asmctx_get_section
extern asmctx_emit_byte
extern asmctx_emit_word
extern asmctx_emit_dword
extern asmctx_emit_qword
extern parser_is_register
extern parser_lookup_mnemonic
extern parser_check_prefix
extern parser_define_label
extern parser_parse_mem_operand
extern parser_concat_local_name

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
    
    ; Reserve space for tables on stack
    sub     rsp, 16
    mov     [rsp], r10
    mov     [rsp + 8], r11
    
    ; 2. Get mnemonic token
.get_mnemonic:
    ; Reload tables from stack
    mov     r10, [rsp]
    mov     r11, [rsp + 8]

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
        mov     [rdi + ASMCTX_last_global], rsi
        call    parser_define_label
        check_err
        jmp     .get_mnemonic
        ENDIF



    IF al, e, TOK_LOCAL_LABEL
        ; Local Label: concat last_global + local_name
        mov     rdi, [rbx + PREP_ctx]
        mov     r14, [rdi + ASMCTX_last_global]
        test    r14, r14
        jz      .error_no_global
        
        mov     rsi, [r12 + TOKEN_value] ; local name (e.g. ".loop")
        call    parser_concat_local_name
        mov     rsi, rdx                ; namespaced name
        call    parser_define_label
        check_err
        jmp     .get_mnemonic
        ENDIF

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
        mov     rsi, [rdx + TOKEN_value]
        lea     rdi, [rel str_equ]
        extern  str_cmp
        call    str_cmp
        IF rax, e, OK
            ; Yes! The next token is "equ".
            ; 1. Define the current identifier (in r12) as a label/symbol.
            mov     rsi, [r12 + TOKEN_value]
            mov     rdi, [rbx + PREP_ctx]
            call    parser_define_label
            check_err
            
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
    hash_fnv1a_64 rsi, r13
    
    ; Reload tables as hash macro clobbers r11 (and potentially others)
    mov     r10, [rsp]
    mov     r11, [rsp + 8]

    mov     rdi, r13
    mov     rsi, r11                ; Current Arch Mnemonic Table
    call    parser_lookup_mnemonic
    
    test    rax, rax
    jz      .try_pseudo_op
    
    mov     [r15 + INST_op_id], ax
    jmp     .operand_loop

.try_pseudo_op:
    ; Check for db, dw, dd, dq, resb, etc.
    mov     rdi, rbx               ; rdi = PrepState
    mov     rsi, [r12 + TOKEN_value]
    call    parser_handle_pseudo_op
    test    rax, rax
    jz      .unknown_mnemonic
    cmp     rax, 1
    je      .get_mnemonic
    jmp     .error

    ; 4. Operand Parsing Loop
.operand_loop:
    xor     r14, r14
    call    parser_parse_operand
    test    rax, rax
    jnz     .error
    
    IF r14, ge, 4
        mov     rax, EXIT_INVALID_OPERAND
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
    
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token
        jmp     .operand_loop
        ENDIF
    
    mov     rax, OK
    mov     rdx, r15
    jmp     .done

.eof:
    xor     rax, rax
    xor     rdx, rdx                ; RDX=0 signals EOF to main loop
    jmp     .done

.error_no_global:
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .error

.unknown_mnemonic:
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
    
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r13, rdx
    
    mov     al, [r13 + TOKEN_kind]
    
    ; 1. Memory Operands [base + index*scale + disp]
    IF al, e, TOK_LBRACKET
        call    parser_parse_mem_operand
        check_err
        jmp     .success
        ENDIF

    ; 2. Registers (handled via ident lookup)
    IF al, e, TOK_IDENT
        mov     rsi, [r13 + TOKEN_value]
        mov     rdi, r10
        call    parser_parse_reg_info
        IF rax, ne, ERR
            mov     byte [r12 + OPERAND_kind], OP_REG
            jmp     .success
            ENDIF

        .success:
            mov     rax, OK
            pop     r13
            pop     r12
            pop     rbx
            epilogue

        .error:
            epilogue

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
        mov     rdi, rbx
        call    preprocessor_putback_token ; put back the ident
        ENDIF

    ; 3. Expressions (Numbers, Symbols, Math)
    mov     rdi, [rbx + PREP_ctx]
    call    parser_evaluate_expression
    test    rax, rax
    IF z
        mov     byte [r12 + OPERAND_kind], OP_IMM
        mov     [r12 + OPERAND_imm], rdx
        ; If the expression involved symbols, we mark it
        IF rcx, ne, 0
             mov     byte [r12 + OPERAND_kind], OP_SYMBOL
             mov     [r12 + OPERAND_sym], rcx
             ENDIF
        jmp     .success
        ENDIF

    mov     rax, EXIT_INVALID_OPERAND
    jmp     .error

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
    and     cl, 0x7F            ; Size in bytes
    shl     cl, 3               ; Convert to bits
    mov     [r12 + OPERAND_size], cl
    
    shr     rax, 16
    and     al, 1
    mov     [r12 + OPERAND_is_high], al
    
    mov     rax, OK
    epilogue

;*
; * [parser_evaluate_additive]
; * Purpose: Additive level (+ -)
; ;
parser_evaluate_additive:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; RBX = PrepState
    
    mov     rdi, rbx
    call    parser_evaluate_term
    check_err
    mov     r13, rdx               ; R13 = current running total
    
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_PLUS
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        add     r13, rdx
        jo      .overflow
        jmp     .loop
    ELSEIF al, e, TOK_MINUS
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_term
        check_err
        sub     r13, rdx
        jo      .overflow
        jmp     .loop
        ENDIF
    
    mov     rdx, r13
    xor     rax, rax

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.overflow:
    mov     rax, EXIT_IMM_RANGE
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

;*
; * [parser_evaluate_expression]
; * Purpose: Entry point for expression evaluation (Relational level: == !=)
; ;
global parser_evaluate_expression
parser_evaluate_expression:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; RBX = PrepState
    mov     r10, [rbx + PREP_ctx]  ; R10 = AsmCtx
    
    ; Check Recursion Depth
    inc     dword [r10 + ASMCTX_expr_depth]
    IF dword [r10 + ASMCTX_expr_depth], g, 64
        mov     rax, EXIT_EXPR_TOO_DEEP
        jmp     .done_err
        ENDIF
        
    mov     rdi, rbx
    call    parser_evaluate_additive
    check_err_to .done_err
    mov     r13, rdx               ; R13 = left operand value
    mov     r14, rcx               ; R14 = left operand symbol (optional)
    
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_EQUAL
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_additive
        check_err_to .done_err
        
        ; Evaluate: left == right
        cmp     r13, rdx
        sete    cl
        movzx   r13, cl
        xor     r14, r14           ; comparisons produce raw integers
        jmp     .loop
        
    ELSEIF al, e, TOK_NEQUAL
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_additive
        check_err_to .done_err
        
        ; Evaluate: left != right
        cmp     r13, rdx
        setne   cl
        movzx   r13, cl
        xor     r14, r14           ; comparisons produce raw integers
        jmp     .loop
        ENDIF
        
    mov     rdx, r13
    mov     rcx, r14
    xor     rax, rax

.done:
    mov     r10, [rbx + PREP_ctx]
    dec     dword [r10 + ASMCTX_expr_depth]
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.done_err:
    mov     r10, [rbx + PREP_ctx]
    dec     dword [r10 + ASMCTX_expr_depth]
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

;*
; * [parser_evaluate_term]
; * Purpose: Multiplicative level (* / << >> & | ^)
; ;
parser_evaluate_term:
    prologue
    push    rbx
    mov     rbx, rdi               ; RBX = PrepState
    
    mov     rdi, rbx
    call    parser_evaluate_factor
    check_err
    mov     rbx, rdx
    
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_STAR
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        imul    rbx, rdx
        jo      .overflow
        jmp     .loop
    ELSEIF al, e, TOK_SLASH
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        test    rdx, rdx
        jz      .div_zero
        mov     r13, rdx           ; R13 = divisor
        mov     rax, rbx           ; RAX = dividend
        cqo                        ; Sign-extend RAX into RDX (A64)
        idiv    r13
        mov     rbx, rax
        jmp     .loop
    ELSEIF al, e, TOK_LSHIFT
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     rcx, rdx
        and     cl, 0x3F           ; Safety Mask: shift count 0-63
        shl     rbx, cl
        jmp     .loop
    ELSEIF al, e, TOK_RSHIFT
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        mov     rcx, rdx
        and     cl, 0x3F           ; Safety Mask: shift count 0-63
        shr     rbx, cl
        jmp     .loop
    ELSEIF al, e, TOK_AMPERSAND
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        and     rbx, rdx
        jmp     .loop
    ELSEIF al, e, TOK_PIPE
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        or      rbx, rdx
        jmp     .loop
    ELSEIF al, e, TOK_CARET
        mov     rdi, rbx
        call    preprocessor_next_token
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        xor     rbx, rdx
        jmp     .loop
        ENDIF
    
    mov     rdx, rbx
    xor     rax, rax
    pop     rbx
    epilogue

.error:
    pop     rbx
    epilogue

.overflow:
    mov     rax, EXIT_IMM_RANGE
    pop     rbx
    epilogue

.div_zero:
    mov     rax, EXIT_INVALID_IMM
    pop     rbx
    epilogue

;*
; * [parser_evaluate_factor]
; * Purpose: Primary level (Numbers, Symbols, Parens)
; ;
parser_evaluate_factor:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi               ; RBX = PrepState
    
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_MINUS
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        neg     rdx
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_TILDE
        mov     rdi, rbx
        call    parser_evaluate_factor
        check_err
        not     rdx
        xor     rax, rax
        jmp     .done
        ENDIF

    IF al, e, TOK_NUMBER
        mov     rsi, [r12 + TOKEN_value]
        call    str_to_int
        mov     rdx, rax
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_DOLLAR
        ; Current location counter ($)
        mov     rax, [rbx + PREP_ctx]
        mov     rax, [rax + ASMCTX_curr_sec]
        IF rax, e, 0
            ; If no section, return 0 (or error?)
            xor rax, rax
            jmp     .done
            ENDIF
        mov     rdx, [rax + SECTION_size]
        xor     rax, rax
        jmp     .done
    ELSEIF al, e, TOK_IDENT
        ; Symbol lookup
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, [r12 + TOKEN_value]
        extern  symbol_find
        call    symbol_find
        IF rax, e, OK
            mov     r11, rdx               ; return SYMBOL* in r11 (A78)
            mov     rdx, [rdx + SYMBOL_value]
            xor     rax, rax
            ELSE
            ; Deferred symbol (R_ABS64 reloc)
            mov     rdx, 0
            mov     r11, 0                 ; no symbol metadata yet
            mov     rcx, [r12 + TOKEN_value] ; return symbol name in RCX
            xor     rax, rax
            ENDIF
        jmp     .done
    ELSEIF al, e, TOK_LPAREN
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
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
    pop     r12
    pop     rbx
    epilogue
.done:
    pop     r12
    pop     rbx
    epilogue

.success:
    mov     rax, OK
    mov     rdx, r12
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
    
    mov     rdi, rbx
    call    preprocessor_peek_token
    mov     r13, rdx
    mov     al, [r13 + TOKEN_kind]
    
    ; 1. Check for 'rel' keyword (RIP-relative)
    IF al, e, TOK_IDENT
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [str_rel]
        extern  str_cmp
        call    str_cmp
        IF rax, e, 0
            mov     rdi, rbx
            call    preprocessor_next_token ; consume 'rel'
            mov     byte [r12 + OPERAND_flags], OP_FLAG_REL
            ; Fall through to parse the symbol/offset
            ENDIF
            ENDIF

.loop:
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

    IF al, e, TOK_MINUS
        ; handle negative disp? usually handled by expression engine
        call    preprocessor_putback_token
        jmp     .parse_item
        ENDIF

.parse_item:
    IF al, e, TOK_IDENT
        ; Could be a register OR a symbol
        mov     rsi, [r13 + TOKEN_value]
        mov     rdi, r10               ; Register table
        call    parser_parse_reg_info
        IF rax, ne, ERR
            ; It's a register. Is it base or index?
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
                call    parser_evaluate_expression
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
                
                mov     rax, EXIT_INVALID_OPERAND
                jmp     .error
            .scale_ok:
                mov     [r12 + OPERAND_scale], al
                ENDIF
            jmp     .loop
            ENDIF
        ; Not a register, must be a symbol/expression
        call    preprocessor_putback_token
        ENDIF

    ; 2. Parse as expression (Displacement)
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    ; result in rdx, symbol metadata in r11 (A78)
    add     [r12 + OPERAND_imm], rdx
    IF r11, ne, 0
        mov [r12 + OPERAND_sym], r11
        ENDIF
    jmp     .loop

.finalize:
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
    mov     r14, [r13 + SYMBOL_size]       ; r14 = field byte width
    
    ; Instruction access size (bits) is in OPERAND_size -> convert to bytes
    movzx   rcx, byte [r12 + OPERAND_size]
    shr     cl, 3                           ; bits -> bytes
    
    cmp     rcx, r14
    jle     .bounds_ok                     ; write size <= field size -> OK
    
    ; FATAL: write exceeds field width
    extern error_struct_bounds
    mov     rdi, [r13 + SYMBOL_name]       ; field name for error message
    mov     rsi, r14                       ; declared field size
    mov     rdx, rcx                       ; attempted access size
    call    error_struct_bounds
    mov     rax, EXIT_STRUCT_BOUNDS
    jmp     .error

.bounds_ok:
    mov     rax, OK
.done:
    epilogue

.error:
    epilogue

[SECTION .rodata]
str_rel: db "rel", 0

[SECTION .text]

;*
; * [parser_is_register]
; * Input: RSI = String, RDI = Table Pointer
; ;
parser_is_register:
    prologue
    hash_fnv1a_64 rsi, r13
.loop:
    mov     rax, [rdi]
    test    rax, rax
    jz      .not_found
    cmp     rax, r13
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
    movzx   rax, word [rsi + 8]
    epilogue

.not_found:
    xor     rax, rax
    epilogue

;*
; * [parser_check_prefix]
; * Input: RSI = String pointer
; * Output: AL = Prefix byte or 0
; ;
parser_check_prefix:
    prologue
    extern     str_compare
    mov     rdi, rsi
    
    lea     rsi, [str_rep]
    call    str_compare
    IF rax, e, 0
        mov al, 0xF3
        epilogue
        ENDIF
    
    lea     rsi, [str_repe]
    call    str_compare
    IF rax, e, 0
        mov al, 0xF3
        epilogue
        ENDIF
    
    lea     rsi, [str_repne]
    call    str_compare
    IF rax, e, 0
        mov al, 0xF2
        epilogue
        ENDIF
    
    lea     rsi, [str_lock]
    call    str_compare
    IF rax, e, 0
        mov al, 0xF0
        epilogue
        ENDIF
    
    xor     rax, rax
    epilogue

[SECTION .rodata]
str_rep:    db "rep", 0
str_repe:   db "repe", 0
str_repne:  db "repne", 0
str_lock:   db "lock", 0

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
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     r15, rdi               ; r15 = struct name Token
    xor     r14, r14               ; r14 = running byte offset
    
    ; Build struct-name string ("StructName", null-terminated from token)
    mov     r13, [r15 + TOKEN_value]  ; r13 = struct name ptr
    
.field_loop:
    ; Read next meaningful token (skip newlines)
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
    
    ; Check for 'endstruc'
    IF al, e, TOK_IDENT
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_endstruc]
        extern  str_compare
        call    str_compare
        IF rax, e, 0
            jmp .register_struct
            ENDIF
        
        ; Check for 'field' keyword
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_field]
        call    str_compare
        IF rax, ne, 0
            mov     rax, EXIT_UNEXPECTED_TOKEN
            jmp     .error
            ENDIF
            ELSE
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; Parse: field <name>, <size>
    ; 1. Field name
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     r12, [rdx + TOKEN_value]   ; r12 = field name ptr
    
    ; Consume comma
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; 2. Field byte size (integer literal)
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_NUMBER
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     rsi, [rdx + TOKEN_value]
    call    str_to_int                 ; rax = field byte size
    mov     r11, rax                   ; r11 = field size
    
    ; 3. Optional: Alignment (A77)
    mov     r10, 1                     ; default alignment
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        call    preprocessor_next_token
        mov     rsi, [rdx + TOKEN_value]
        call    str_to_int
        mov     r10, rax
        
        ; VALIDATION: Power of 2 (Industrial Safety)
        mov     rax, r10
        dec     rax
        test    r10, rax
        jnz     .error_invalid_align
        ENDIF
    
    ; Apply Alignment
    mov     rax, r14                   ; current offset
    add     rax, r10
    dec     rax
    neg     r10
    and     rax, r10                   ; rax = aligned offset
    mov     r14, rax
    
    ; Register SYMBOL: kind=SYM_STRUCT_FIELD, value=offset, size=field_size
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    ; Zero the symbol
    xor     rax, rax
    mov     rcx, 6                     ; SYMBOL_SIZE / 8
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT_FIELD
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     [rsi + SYMBOL_name],  r12      ; field name ptr
    mov     [rsi + SYMBOL_value], r14      ; byte offset
    mov     [rsi + SYMBOL_size],  r11      ; field byte width
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    
    ; Advance offset
    add     r14, r11
    jmp     .field_loop
    
.register_struct:
    ; Register the struct itself: kind=SYM_STRUCT, size=total
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, 6
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     [rsi + SYMBOL_name],  r13     ; struct name ptr
    mov     qword [rsi + SYMBOL_value], 0
    mov     [rsi + SYMBOL_size],  r14     ; total byte size
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    
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
    mov     rsp, rbp
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
    
    ; Create Symbol struct
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, 6
    rep stosq
    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_LABEL
    mov     [rdi + SYMBOL_name], rsi
    
    ; Set value to current section location
    mov     rax, [rbx + ASMCTX_curr_sec]
    IF rax, ne, 0
        mov     rcx, [rax + SECTION_size]
        mov     [rdi + SYMBOL_value], rcx
        movzx   ecx, word [rax + SECTION_index]
        mov     [rdi + SYMBOL_section], cx
        ENDIF

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

.error:
    add     rsp, SYMBOL_SIZE
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
    
    ; We need PrepState in RBX for the arena_alloc call
    ; Assuming the caller is parser_handle_line which keeps PrepState in RBX
    ; but we'll be safer and ensure it's valid if possible, 
    ; or just assume caller convention and document it.
    ; Actually, in our current arch, RBX IS the PrepState throughout the parser loop.
    
    mov     r12, r14               ; global
    mov     r13, rsi               ; local
    
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MAX_TOKEN
    call    arena_alloc
    check_err_to .error
    mov     r10, rdx               ; R10 = temp buffer
    
    mov     rdi, r10
    mov     rsi, r12
    mov     rdx, r13
    extern  str_concat
    call    str_concat
    
    mov     rdx, r10
    xor     rax, rax
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

    ; 1. Data Directives (db, dw, dd, dq)
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
        ENDIF

    ; 2. Section Directive
    mov     rdi, r12
    lea     rsi, [rel str_section]
    extern  str_cmp
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_section_directive
        jmp     .check_handler_result
        ENDIF

    ; 2.5 Comm Directive
    mov     rdi, r12
    lea     rsi, [rel str_comm]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_comm
        jmp     .check_handler_result
        ENDIF

    ; 3. Align Directives
    mov     rdi, r12
    lea     rsi, [rel str_align]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        xor     rsi, rsi           ; type = 0 (byte)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_p2align]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, 1             ; type = 1 (p2)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    ; 4. Visibility Directives (global, weak, local)
    mov     rdi, r12
    lea     rsi, [rel str_global]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_GLOBAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_weak]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_WEAK
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_local]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_LOCAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_org]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_org
        jmp     .check_handler_result
        ENDIF
    
    mov     rdi, r12
    lea     rsi, [rel str_extern]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_extern
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_default]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_default
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_equ]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_equ
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_bits]
    call    str_cmp
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_default   ; reuse same skip logic
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
    call    str_cmp
    IF rax, e, 0
        mov rax, SHIFT_LSL
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_lsr]
    call    str_cmp
    IF rax, e, 0
        mov rax, SHIFT_LSR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_asr]
    call    str_cmp
    IF rax, e, 0
        mov rax, SHIFT_ASR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_ror]
    call    str_cmp
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
        call    parser_evaluate_expression
        check_err
        mov     r14, rdx
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
    call    asm_ctx_align
    
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
    
    ; Evaluate expression
    call    parser_evaluate_expression
    check_err
    mov     r12, rdx               ; r12 = value
    
    ; Get last symbol
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_last_symbol]
    IF rax, e, 0
        mov     rax, EXIT_UNDEF_SYMBOL
        jmp     .error
        ENDIF
    
    ; Override value and make it absolute (SHN_ABS = 0xFFF1)
    mov     [rax + SYMBOL_value], r12
    mov     word [rax + SYMBOL_section], 0xFFF1
    
    pop     r12
    mov     rax, OK
    epilogue

.error:
    pop     r12
    epilogue

[SECTION .rodata]
str_equ:    db "equ", 0

[SECTION .text]

parser_emit_data_8:
    prologue
.loop:
    call    preprocessor_next_token
    check_err
    mov     r12, rdx
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_STRING
        mov     rsi, [r12 + TOKEN_value]
        mov     rdi, [rbx + PREP_ctx]
        extern  asmctx_emit_string
        call    asmctx_emit_string
        ELSE
        call    preprocessor_putback_token
        call    parser_evaluate_expression
        check_err
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rdx
        extern  asmctx_emit_byte
        call    asmctx_emit_byte
        ENDIF
    
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    epilogue

.error:
    epilogue

parser_emit_data_16:
    prologue
.loop:
    call    parser_evaluate_expression
    check_err
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    extern  asmctx_emit_word
    call    asmctx_emit_word
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    epilogue

.error:
    epilogue

parser_emit_data_32:
    prologue
.loop:
    call    parser_evaluate_expression
    check_err
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    extern  asmctx_emit_dword
    call    asmctx_emit_dword
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    epilogue

.error:
    epilogue

parser_emit_data_64:
    prologue
.loop:
    call    parser_evaluate_expression
    check_err
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    extern  asmctx_emit_qword
    call    asmctx_emit_qword
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        jmp     .loop
        ENDIF
    epilogue

.error:
    epilogue

;*
; * [parser_handle_extern]
; * Input: None (reads from preprocessor)
; ;
parser_handle_extern:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rdi = PrepState
.loop:
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
    check_err
    
    ; Check for comma (extern name1, name2)
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
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
    prologue
    ; Just consume until end of line for now
.loop:
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_NEWLINE
        jmp .done
        ENDIF
    IF byte [rdx + TOKEN_kind], e, TOK_EOF
        jmp .done
        ENDIF
    call    preprocessor_next_token
    jmp     .loop
.done:
    epilogue

;*
; * [parser_handle_section_directive]
; * Input: None (reads from preprocessor)
; ;
parser_handle_section_directive:
    prologue
    push    rbx
    push    r12
    
    ; Get section name token
    call    preprocessor_next_token
    check_err
    mov     r12, rdx               ; r12 = token (.text, .data, etc)
    
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    extern  asmctx_find_section
    call    asmctx_find_section
    
    IF rax, e, OK
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

    ; 2. Auto-assign flags and type for standard sections if new
    IF rax, ne, OK
        mov     rdi, [r12 + TOKEN_value]
        mov     dword [r13 + SECTION_elf_type], SHT_PROGBITS ; Default
        
        ; .text -> AX
        lea     rsi, [str_text]
        call    str_cmp
        IF rax, e, OK
            mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_EXECINSTR)
            ELSE
            ; .data -> AW
            lea     rsi, [str_data]
            call    str_cmp
            IF rax, e, OK
                mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                ELSE
                ; .bss -> AW, NOBITS
                lea     rsi, [str_bss]
                call    str_cmp
                IF rax, e, OK
                    mov word [r13 + SECTION_flags], (SHF_ALLOC | SHF_WRITE)
                    mov dword [r13 + SECTION_elf_type], SHT_NOBITS
                    ELSE
                    ; .rodata -> A
                    lea     rsi, [str_rodata]
                    call    str_cmp
                    IF rax, e, OK
                        mov word [r13 + SECTION_flags], SHF_ALLOC
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF
                        ENDIF

    ; 3. Reset last_global on section change
    mov     rdi, [rbx + PREP_ctx]
    mov     qword [rdi + ASMCTX_last_global], 0
    
    ; 3. Check for attributes (comma + string)
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
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
            
            ; A92: Validate flag consistency for duplicate declarations
            movzx   ecx, word [r13 + SECTION_flags]
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
            call    preprocessor_next_token
            IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
                mov     rax, EXIT_UNEXPECTED_TOKEN
                jmp     .done
                ENDIF
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
            call    preprocessor_peek_token
            IF byte [rdx + TOKEN_kind], e, TOK_COMMA
                call    preprocessor_next_token
                call    preprocessor_next_token
                mov     rdi, [rdx + TOKEN_value]
                lea     rsi, [str_comdat]
                call    str_cmp
                IF rax, e, 0
                    mov dword [r13 + SECTION_group_flags], GRP_COMDAT
                    ENDIF
                    ENDIF
            
        .no_group:
        ENDIF

        ; 4. Optional: Type (@progbits, etc)
        call    preprocessor_peek_token
        IF byte [rdx + TOKEN_kind], e, TOK_COMMA
            call    preprocessor_next_token
            call    preprocessor_next_token
            ; Check for @progbits, @nobits, etc
            ; For now, support @ progbits as separate or joined
            ENDIF
            ENDIF
    
.done:
    pop     r12
    pop     rbx
    epilogue

.error:
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
    mov     r12, rsi               ; r12 = visibility
    
    call    preprocessor_next_token
    check_err
    mov     r11, rdx
    IF byte [r11 + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r11 + TOKEN_value]
    extern  symbol_find
    call    symbol_find
    
    IF rax, e, OK
        ; A91: Audit symbol binding visibility conflicts
        movzx   eax, byte [rdx + SYMBOL_vis]
        IF al, ne, r12b
            ; If already Global/Weak, don't allow demotion to Local if defined
            IF al, e, VIS_GLOBAL
            ELSEIF al, e, VIS_WEAK
                IF r12b, e, VIS_LOCAL
                    ; Symbol is already visible to the linker; demotion is unsafe
                    mov     rax, EXIT_SYMBOL_RANGE
                    jmp     .error
                    ENDIF
                    ENDIF
                    ENDIF
        mov     byte [rdx + SYMBOL_vis], r12b
        ELSE
        ; Symbol doesn't exist, create it as UNDEFINED for now
        sub     rsp, SYMBOL_SIZE
        mov     rdi, rsp
        xor     rax, rax
        mov     rcx, 6
        rep stosq
        mov     rdi, [rbx + PREP_ctx]
        mov     rsi, rsp
        mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
        mov     rax, [r11 + TOKEN_value]
        mov     [rsi + SYMBOL_name], rax
        mov     byte [rsi + SYMBOL_vis], r12b
        call    symbol_add
        add     rsp, SYMBOL_SIZE
        ENDIF
    
    mov     rax, OK
.done:
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r12
    pop     rbx
    epilogue

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
        mov     rcx, 6
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
str_data:      db ".data", 0
str_bss:       db ".bss", 0
str_rodata:    db ".rodata", 0
str_extern:    db "extern", 0
str_default:   db "default", 0
str_bits:      db "bits", 0
msg_debug_pseudo: db "DEBUG: Pseudo-op: ", 0
msg_newline:      db 10, 0
msg_debug_token:   db "DEBUG: Token: ", 0
msg_parser_entry: db "DEBUG: Parser entry", 10, 0
msg_debug_lookup: db "DEBUG: Mnemonic lookup finished", 10, 0
msg_debug_null:   db "(null)", 0
