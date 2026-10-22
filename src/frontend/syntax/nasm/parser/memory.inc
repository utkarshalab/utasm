; ============================================================================
; File        : src/frontend/syntax/nasm/parser/memory.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : memory operands: relocation modifiers (wrt, rel, abs), base / index / scale terms, rip, MIB, decorators ({k}, {z}, {1toN}, {dfv=})
; ============================================================================


;*
; * [parser_handle_reloc_modifier]
; ;
parser_handle_reloc_modifier:
    prologue
    push    rbx
    push    r12
    push    r14
    
    mov     rdi, rbx
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

; ---- parser_complex_dest ------------------
;
; parser_complex_dest
; vfmaddcph / vfcmaddcph / vfmulcph / vfcmulcph and their sh forms (r15 =
; the INST): the destination register must not be a source (Intel: #UD).
; Output   : rax = OK or EXIT_DEST_IS_SOURCE
; Clobbers : rcx, rdx
;
parser_complex_dest:
    movzx   eax, word [r15 + INST_op_id]
    cmp     eax, 1807
    jb      .other
    cmp     eax, 1810
    jbe     .complex                       ; vfcmaddc*, vfcmulc*
    cmp     eax, 1833
    je      .complex
    cmp     eax, 1834
    je      .complex                       ; vfmaddc*
    cmp     eax, 1872
    je      .complex
    cmp     eax, 1873
    jne     .other                         ; vfmulc*
.complex:
    ; (two operands: the first source is the destination - always #UD)
    cmp     byte [r15 + INST_nops], 2
    je      .bad
    cmp     byte [r15 + INST_op0 + OPERAND_kind], OP_REG
    jne     .ok
    mov     dl, [r15 + INST_op0 + OPERAND_reg]
    cmp     byte [r15 + INST_op1 + OPERAND_kind], OP_REG
    jne     .src2
    cmp     dl, [r15 + INST_op1 + OPERAND_reg]
    je      .bad
.src2:
    cmp     byte [r15 + INST_nops], 3
    jb      .ok
    cmp     byte [r15 + INST_op2 + OPERAND_kind], OP_REG
    jne     .ok
    cmp     dl, [r15 + INST_op2 + OPERAND_reg]
    je      .bad
.ok:
.other:
    xor     eax, eax
    ret
.bad:
    mov     eax, EXIT_DEST_IS_SOURCE
    ret

; ---- parser_mib_index ---------------------
;
; parser_mib_index
; bndldx / bndstx with three operands (ICC's "bndstx [rax+3], bnd0, rbx"):
; the general register becomes the address's index (times 1), and is taken
; out of the operands. Not one memory operand and one such register, or an
; address with an index already: left for the encoder to refuse.
; Input    : r15 = the INST (three operands)
; Output   : rax = OK
; Clobbers : rcx, rdx, rsi, rdi, r8-r10
;
parser_mib_index:
    mov     r8, -1                         ; the memory operand
    mov     r9, -1                         ; the general register
    xor     ecx, ecx
.find:
    cmp     ecx, 3
    jae     .found
    imul    rdx, rcx, OPERAND_SIZE
    lea     rdx, [r15 + INST_op0 + rdx]
    cmp     byte [rdx + OPERAND_kind], OP_MEM
    jne     .not_mem
    mov     r8, rdx
    jmp     .next
.not_mem:
    cmp     byte [rdx + OPERAND_kind], OP_REG
    jne     .next
    cmp     byte [rdx + OPERAND_reg], 32   ; (a general one: 0 .. 31)
    jae     .next
    mov     r9, rcx
.next:
    inc     ecx
    jmp     .find
.found:
    cmp     r8, -1
    je      .ok
    cmp     r9, -1
    je      .ok
    cmp     byte [r8 + OPERAND_index], 0xFF
    jne     .ok
    imul    rdx, r9, OPERAND_SIZE
    lea     rsi, [r15 + INST_op0 + rdx]
    ; the address's width is the register's ([0], ecx: 32-bit); a base
    ; of another width: left as it is
    xor     ecx, ecx
    cmp     byte [rsi + OPERAND_size], 32
    jne     .not32
    mov     ecx, OP_FLAG_ADDR32
.not32:
    cmp     byte [rsi + OPERAND_size], 16
    jne     .width
    mov     ecx, OP_FLAG_ADDR16
.width:
    cmp     byte [r8 + OPERAND_base], 0xFF
    je      .width_set
    mov     al, [r8 + OPERAND_flags]
    and     al, OP_FLAG_ADDR32 | OP_FLAG_ADDR16
    cmp     al, cl
    jne     .ok
.width_set:
    or      [r8 + OPERAND_flags], cl
    mov     al, [rsi + OPERAND_reg]
    mov     [r8 + OPERAND_index], al
    mov     byte [r8 + OPERAND_scale], 1
    ; the operands after it move down one
    lea     rdi, [rsi]
    add     rsi, OPERAND_SIZE
    mov     ecx, 2
    sub     rcx, r9
    imul    rcx, rcx, OPERAND_SIZE
    rep     movsb
    mov     byte [r15 + INST_op2 + OPERAND_kind], OP_NONE
    mov     byte [r15 + INST_nops], 2
.ok:
    xor     eax, eax
    ret

;*
; * [parser_parse_mem_operand]
; * Purpose: Technical SIB Parser.
; ;
parser_parse_mem_operand:
    prologue
    ; an MIB address (bndmk, bndldx, bndstx): a register with a scale written is
    ; the index ("[rcx*1]", "[1*rbx+3]"), as under nosplit; one without, the
    ; base - NASM's
    cmp     byte [rel mem_mib], 0
    je      .not_mib
    or      byte [r12 + OPERAND_flags], OP_FLAG_NOSPLIT
.not_mib:
    mov     qword [rel mem_struc], 0       ; ("[rbx:PACKET]": parser_typed_field)
    mov     byte [rel mem_typed_next], 0
    mov     byte [rel mem_scaling], 1      ; "4*rcx": parser_evaluate_term
    mov     byte [rel mem_expect_term], 1  ; (a term must come)
    xor     eax, eax
    mov     [rel mem_scaled_n], eax
    mov     [rel mem_scaled_take], eax
    mov     [rel mem_terms_n], eax
    mov     [rel mem_addr_width], eax
    mov     byte [rel mem_after_comma], 0
    mov     byte [rel mem_term_pending], 0
    mov     byte [rel mem_rip_written], 0
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

    ; 1c. "[a32 foo]": the address size, as the a16 / a32 / a64 prefix
    ;     gives it (r15 is the instruction)
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .no_asize
    mov     rdi, [rdx + TOKEN_value]
    movzx   eax, byte [rdi]
    or      eax, 0x20
    cmp     eax, 'a'
    jne     .no_asize
    cmp     byte [rdi + 3], 0
    jne     .no_asize
    movzx   eax, word [rdi + 1]
    mov     ecx, 16
    cmp     eax, '1' | '6' << 8
    je      .asize_kw
    mov     ecx, 32
    cmp     eax, '3' | '2' << 8
    je      .asize_kw
    mov     ecx, 64
    cmp     eax, '6' | '4' << 8
    jne     .no_asize
.asize_kw:
    push    rcx
    mov     rdi, rbx
    call    preprocessor_next_token        ; the word
    pop     rcx
    mov     [r15 + INST_asize], cl
    movzx   eax, byte [rel asm_bits]
    cmp     ecx, eax
    je      .kw_again                      ; the mode's own: no byte
    cmp     ecx, 64
    je      .asize_kw_bad                  ; a64 outside 64-bit code
    cmp     eax, 64
    jne     .asize_kw_67
    cmp     ecx, 16
    je      .asize_kw_bad                  ; a16 in 64-bit code
.asize_kw_67:
    xor     ecx, ecx
.asize_kw_slot:
    cmp     byte [r15 + INST_prefixes + rcx], 0x67
    je      .kw_again                      ; (a32 written twice)
    cmp     byte [r15 + INST_prefixes + rcx], 0
    je      .asize_kw_put
    inc     ecx
    cmp     ecx, 4
    jb      .asize_kw_slot
    jmp     .no_asize
.asize_kw_put:
    mov     byte [r15 + INST_prefixes + rcx], 0x67
.kw_again:
    ; "[a64 abs foo]", "[a32 rel x]": abs / rel after the size too
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .no_asize
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [str_abs]
    call    str_cmp_kw
    test    rax, rax
    jnz     .kw_rel
    mov     rdi, rbx
    call    preprocessor_next_token
    or      byte [r12 + OPERAND_flags], OP_FLAG_ABS
    jmp     .no_asize
.kw_rel:
    lea     rsi, [str_rel]
    call    str_cmp_kw
    test    rax, rax
    jnz     .no_asize
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [r12 + OPERAND_flags], OP_FLAG_REL
    mov     byte [r12 + OPERAND_base], REG_RIP
    jmp     .no_asize
.asize_kw_bad:
    mov     eax, EXIT_EA_SIZE_MIX
    jmp     .error
.no_asize:

.loop:
    ; a register the expression evaluator took as "4*rcx" (mem_scaled_*)
    mov     eax, [rel mem_scaled_take]
    cmp     eax, [rel mem_scaled_n]
    jb      .take_scaled
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    mov     r13, rdx
    mov     al, [r13 + TOKEN_kind]

    ; %use masm's "ptr x" (mem_open): the operand ends at a comma or the
    ; end of the line, which are handed back; "ptr fs:[x]": its bracket
    ; makes it an ordinary one
    cmp     byte [rel mem_open], 0
    je      .closed
    cmp     al, TOK_LBRACKET
    jne     .open_end
    mov     byte [rel mem_open], 0
    jmp     .loop
.open_end:
    cmp     al, TOK_COMMA
    je      .open_done
    cmp     al, TOK_NEWLINE
    je      .open_done
    cmp     al, TOK_EOF
    je      .open_done
    cmp     al, TOK_LBRACE
    jne     .closed
.open_done:
    mov     rdi, rbx
    mov     rsi, r13
    call    preprocessor_putback_token
    mov     byte [rel mem_open], 0
    mov     al, TOK_RBRACKET
.closed:

    ; %use masm's "flat:": nothing (an address is flat)
    cmp     al, TOK_IDENT
    jne     .not_flat
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [rel str_masm_flat]
    call    str_cmp
    test    rax, rax
    jnz     .not_flat_ident
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err_to .error
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    jne     .loop
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .loop
.not_flat_ident:
    mov     al, [r13 + TOKEN_kind]
.not_flat:

    IF al, e, TOK_RBRACKET
        ; "[ ]", "[rbx + ]": NASM's syntax error (they were [0], [rbx])
        cmp     byte [rel mem_expect_term], 0
        je      .finalize
        mov     eax, EXIT_INVALID_EXPR
        jmp     .error
        ENDIF

    IF al, e, TOK_PLUS
        mov     byte [rel mem_expect_term], 1
        jmp     .loop
        ENDIF

    ; "[rbx + rcx*8:PACKET]": the address typed by the struc at its end
    cmp     al, TOK_COLON
    jne     .not_typed_end
    cmp     byte [rel gas_names], 0
    jne     .not_typed_end
    mov     eax, EXIT_INVALID_EXPR
    cmp     byte [rel mem_expect_term], 0
    jne     .error
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    mov     eax, EXIT_UNEXPECTED_TOKEN
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .error
    mov     rsi, [rdx + TOKEN_value]
    lea     rdx, [rel str_size_suffix]
    call    ns_ref_suffix
    call    parser_is_struc
    jz      .typed_end
    mov     rdi, rsi
    call    error_set_subject
    mov     eax, EXIT_NOT_STRUC
    jmp     .error
.typed_end:
    mov     [rel mem_struc], rsi
    jmp     .loop
.not_typed_end:

    ; NASM's split form "[eax+8, ecx*4]" (the index after the comma; the
    ; MIB operand of tileloadd and bndldx): as "+", but a register after
    ; the comma is the index even times 1 ("[3, 1*r12]": r12 no base)
    IF al, e, TOK_COMMA
        mov     byte [rel mem_expect_term], 1
        mov     byte [rel mem_after_comma], 2
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

    ; GNU's "[rip + x]" / "x[rip]" (bits 64): relative to x, as [rel x];
    ; "[rip + 8]", "[rip]": that displacement, from the next instruction,
    ; as written. rip with another register: NASM's invalid address.
    IF al, e, TOK_IDENT
        cmp     byte [rel asm_bits], 64
        jne     .not_rip_word
        mov     rdi, [r13 + TOKEN_value]
        lea     rsi, [rel str_rip]
        call    str_cmp_kw
        test    rax, rax
        jnz     .not_rip_word
        mov     eax, EXIT_INVALID_ADDR
        cmp     byte [rel mem_rip_written], 0
        jne     .error                         ; ([rip + rip])
        cmp     byte [r12 + OPERAND_base], 0xFF
        jne     .error                         ; ([rel rip])
        cmp     byte [r12 + OPERAND_index], 0xFF
        jne     .error
        mov     byte [rel mem_rip_written], 1
        mov     byte [r12 + OPERAND_base], REG_RIP
        or      byte [r12 + OPERAND_flags], OP_FLAG_REL
        mov     byte [rel mem_expect_term], 0
        jmp     .loop
.not_rip_word:
        mov     al, [r13 + TOKEN_kind]
        ENDIF

    ; "fs:" lexes as a label: inside brackets it is a segment override -
    ; or "rbx:" a register typed by the struc after it ("[rbx:PACKET]")
    IF al, e, TOK_LABEL
        mov     rsi, [r13 + TOKEN_value]
        call    parser_seg_override
        test    rax, rax
        jz      .loop
        cmp     byte [rel gas_names], 0
        jne     .error
        push    rax
        call    parser_get_arch_tables
        mov     rdi, rdx
        mov     rsi, [r13 + TOKEN_value]
        call    parser_is_register
        cmp     rax, ERR
        pop     rcx
        je      .label_not_reg
        cmp     al, 32
        jae     .label_not_reg
        mov     byte [r13 + TOKEN_kind], TOK_IDENT
        mov     byte [rel mem_typed_next], 1
        mov     al, TOK_IDENT
        jmp     .parse_item
    .label_not_reg:
        mov     rax, rcx
        jmp     .error
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
.reg_token:
        call    parser_get_arch_tables
        mov     rdi, rdx               ; RDI = Register Table Pointer
        mov     rsi, [r13 + TOKEN_value]
        movzx   rcx, byte [r12 + OPERAND_size]  ; reg_info overwrites the size
        push    rcx
        movzx   rcx, word [r12 + OPERAND_xsize]
        push    rcx
        call    parser_parse_reg_info
        movzx   r8d, word [r12 + OPERAND_xsize] ; the register's width, if it is one
        mov     [rel mem_term_width], r8d
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
            ; "[rbx:PACKET]": a general register the address of a struc
            ; (the field after the bracket: parser_typed_field)
            cmp     al, 32
            jae     .not_typed
            cmp     byte [rel gas_names], 0
            jne     .not_typed
            push    rax
            cmp     byte [rel mem_typed_next], 0
            jne     .typed_name                    ; ("rbx:" lexed its colon)
            mov     rdi, rbx
            call    preprocessor_peek_token
            cmp     byte [rdx + TOKEN_kind], TOK_COLON
            jne     .typed_none
            mov     rdi, rbx
            call    preprocessor_next_token        ; ':'
        .typed_name:
            mov     byte [rel mem_typed_next], 0
            mov     rdi, rbx
            call    preprocessor_next_token        ; the struc
            mov     eax, EXIT_UNEXPECTED_TOKEN
            cmp     byte [rdx + TOKEN_kind], TOK_IDENT
            jne     .typed_bad
            mov     rsi, [rdx + TOKEN_value]
            lea     rdx, [rel str_size_suffix]
            call    ns_ref_suffix
            call    parser_is_struc
            jnz     .typed_not
            mov     [rel mem_struc], rsi
            jmp     .typed_none
        .typed_not:
            mov     rdi, rsi
            call    error_set_subject
            mov     eax, EXIT_NOT_STRUC
        .typed_bad:
            add     rsp, 8
            jmp     .error
        .typed_none:
            pop     rax
        .not_typed:
            ; registers of one size: [eax + rbx] is no address
            mov     ecx, [rel mem_term_width]
            cmp     ecx, 128
            jae     .one_size                      ; a vector index
            cmp     dword [rel mem_addr_width], 0
            jne     .size_seen
            mov     [rel mem_addr_width], ecx
            jmp     .one_size
        .size_seen:
            cmp     [rel mem_addr_width], ecx
            je      .one_size
            mov     eax, EXIT_EA_SIZE_MIX
            jmp     .error
        .one_size:
            ; how it is scaled: "rcx*4" (read here), "4*rcx" (read by the
            ; expression evaluator), or not at all
            mov     [rel mem_term_reg], al
            cmp     byte [rel mem_term_pending], 0
            jne     .scaled_given
            mov     rdi, rbx
            call    preprocessor_peek_token
            cmp     byte [rdx + TOKEN_kind], TOK_STAR
            jne     .unscaled
            mov     qword [rel mem_term_coef], 1
        .scale_factor:
            mov     rdi, rbx
            call    preprocessor_next_token ; consume '*'
            mov     rdi, rbx
            ; The scale is a single factor: in [base+index*4+8] the "+8"
            ; belongs to the displacement, not to the scale.
            call    parser_evaluate_factor
            check_err_to .error
            test    rcx, rcx
            jnz     .scale_bad                     ; a label not defined yet
            mov     rdi, r11
            call    expr_sym_class
            test    eax, eax
            jnz     .scale_bad                     ; a label
            imul    rdx, [rel mem_term_coef]
            mov     [rel mem_term_coef], rdx
            mov     rdi, rbx
            call    preprocessor_peek_token
            cmp     byte [rdx + TOKEN_kind], TOK_STAR
            je      .scale_factor                  ; "rbx*2*2"
        .scaled_given:
            mov     byte [rel mem_term_pending], 0
            mov     al, [rel mem_term_reg]
            mov     rcx, [rel mem_term_coef]
            mov     dl, 1                          ; written multiplied
            call    .add_term
            check_err_to .error
            jmp     .loop
        .unscaled:
            mov     al, [rel mem_term_reg]
            mov     ecx, 1
            xor     edx, edx
            call    .add_term
            check_err_to .error
            jmp     .loop
        .scale_bad:
            mov     eax, EXIT_INVALID_ADDR
            jmp     .error
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
    mov     byte [rel expr_pcrel_ok], 1    ; ("[rdi + rod1 - $$]", rod1 elsewhere)
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_pcrel_ok], 0
    pop     r8
    check_err_to .error
    mov     al, [rel expr_pcrel]
    or      [r12 + OPERAND_pcrel], al
    mov     byte [rel mem_expect_term], 0
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
    ; the registers into base and index, now that all are known
    call    .place_terms
    check_err_to .error
    ; "a32 mov eax, [rbx]", "[a16 ebx]": registers of another size than
    ; the address size written (NASM's "impossible combination")
    movzx   eax, byte [r15 + INST_asize]
    test    eax, eax
    jz      .asize_regs_ok
    mov     ecx, [rel mem_addr_width]
    test    ecx, ecx
    jz      .asize_regs_ok
    cmp     eax, ecx
    je      .asize_regs_ok
    mov     eax, EXIT_EA_SIZE_MIX
    jmp     .error
.asize_regs_ok:
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
    ; "[rel 0xaaaa]": a number has no RIP-relative form either - absolute,
    ; with NASM's warning (the same for an equ constant)
    ; GNU's rip: a label is reached rip-relative, as [rel x]; a number
    ; ([rip + 8], [rip], an equ constant) is the displacement as written
    cmp     byte [rel mem_rip_written], 0
    je      .not_rip_written
    mov     rax, [r12 + OPERAND_sym]
    test    rax, rax
    jz      .rel_done
    cmp     byte [rax], TAG_SYMBOL
    jne     .rel_done                      ; a label not defined yet
    cmp     byte [rax + SYMBOL_kind], SYM_CONSTANT
    je      .rip_number
    cmp     byte [rax + SYMBOL_kind], SYM_STRUCT_FIELD
    je      .rip_number
    cmp     word [rax + SYMBOL_section], 0xFFF1
    jne     .rel_done
.rip_number:
    mov     qword [r12 + OPERAND_sym], 0
    jmp     .rel_done
.not_rip_written:
    test    byte [r12 + OPERAND_flags], OP_FLAG_REL
    jz      .not_rel_number
    cmp     byte [r12 + OPERAND_index], 0xFF
    jne     .not_rel_number
    mov     rax, [r12 + OPERAND_sym]
    test    rax, rax
    jz      .rel_number
    cmp     byte [rax], TAG_SYMBOL
    jne     .not_rel_number                ; a label not defined yet
    cmp     byte [rax + SYMBOL_kind], SYM_CONSTANT
    je      .rel_number
    cmp     byte [rax + SYMBOL_kind], SYM_STRUCT_FIELD
    je      .rel_number
    cmp     word [rax + SYMBOL_section], 0xFFF1
    jne     .not_rel_number
.rel_number:
    and     byte [r12 + OPERAND_flags], ~OP_FLAG_REL & 0xFF
    mov     byte [r12 + OPERAND_base], 0xFF
    jmp     .ea_absolute
.not_rel_number:
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
    jz      .ea_absolute                   ; no symbol: numeric address
    ; "[baz - $]": a distance (or an expression kept) is a number, not an
    ; address - absolute, with NASM's warning
    cmp     byte [rax], RELOC_OFFSET_MARK
    je      .ea_absolute
    cmp     byte [rax], RELOC_EXPR_MARK
    je      .ea_absolute
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
    jmp     .rel_done
.ea_absolute:
    ; "[5]" under default rel: absolute, with NASM's warning (and the
    ; ModRM form, no moffs: mode.s)
    mov     byte [r12 + OPERAND_relnum], 1
    mov     edi, WC_EA_ABSOLUTE
    call    warn_begin
    test    eax, eax
    jz      .rel_done
    lea     rsi, [rel str_ea_absolute]
    call    warn_text
    call    warn_end
.rel_done:
    mov     rax, OK
.done:
    mov     byte [rel mem_scaling], 0
    epilogue

.error:
    mov     byte [rel mem_scaling], 0
    epilogue

; .take_scaled: the next register the evaluator took (rax = its number):
; through the register path, with its scale
.take_scaled:
    inc     dword [rel mem_scaled_take]
    lea     rcx, [rel mem_scaled_tok]
    mov     r13, [rcx + rax * 8]
    lea     rcx, [rel mem_scaled_coef]
    mov     rcx, [rcx + rax * 8]
    mov     [rel mem_term_coef], rcx
    mov     byte [rel mem_term_pending], 1
    jmp     .reg_token

; .add_term: a register of the address (al), times rcx; dl = 1 when the
; scale was written ("rbx*1", "4*rbx"). The terms are kept in the order
; written, a register written twice once (its scales added: [rax+rax*3] is
; rax*4), and placed when the address is complete (.place_terms).
; rax = OK or EXIT_INVALID_ADDR (more registers than there is room for).
.add_term:
    mov     byte [rel mem_expect_term], 0
    or      dl, [rel mem_after_comma]      ; (2: after a split form's comma)
    lea     r10, [rel mem_terms_reg]
    mov     r8d, [rel mem_terms_n]
    xor     r9d, r9d
.at_find:
    cmp     r9d, r8d
    jae     .at_new
    cmp     [r10 + r9], al
    je      .at_merge
    inc     r9d
    jmp     .at_find
.at_merge:
    lea     r10, [rel mem_terms_coef]
    add     [r10 + r9 * 8], rcx
    lea     r10, [rel mem_terms_mul]
    or      [r10 + r9], dl
    xor     eax, eax
    ret
.at_new:
    cmp     r8d, MEM_SCALED_MAX
    jae     .bad_too_many
    mov     [r10 + r8], al
    lea     r10, [rel mem_terms_coef]
    mov     [r10 + r8 * 8], rcx
    lea     r10, [rel mem_terms_mul]
    mov     [r10 + r8], dl
    inc     dword [rel mem_terms_n]
    xor     eax, eax
    ret
.place_bad:
    mov     eax, EXIT_INVALID_ADDR
    ret
.bad_too_many:
    mov     eax, EXIT_EA_TOO_MANY
    ret
.bad_two_index:
    mov     eax, EXIT_EA_TWO_INDEX
    ret
.bad_bits:
    ; "invalid 64-bit effective address": the address's size
    lea     rdi, [rel s_bits64]
    mov     eax, [rel mem_addr_width]
    test    eax, eax
    jnz     .bad_bits_size
    movzx   eax, byte [rel asm_bits]
.bad_bits_size:
    cmp     eax, 32
    jne     .bad_bits_16
    lea     rdi, [rel s_bits32]
.bad_bits_16:
    cmp     eax, 16
    jne     .bad_bits_set
    lea     rdi, [rel s_bits16]
.bad_bits_set:
    call    error_set_subject
    mov     eax, EXIT_EA_BITS
    ret

; .place_terms: the registers into base and index, as NASM places them.
; A register times 0 is dropped. One register: times 1 the base (the index
; for "nosplit rax*1"), times 2, 4 or 8 the index, times 3, 5 or 9 base and
; index both ([rbx*3] is [rbx + rbx*2]). Two: the one with a scale is the
; index; both times 1, the first written is the base unless its scale was
; written ([rbx*1 + rax] is [rax + rbx]). A vector register is always the
; index. rax = OK or EXIT_INVALID_ADDR.
.place_terms:
    ; drop the registers times 0
    lea     r8, [rel mem_terms_reg]
    lea     r9, [rel mem_terms_coef]
    lea     r10, [rel mem_terms_mul]
    xor     ecx, ecx                       ; read
    xor     edx, edx                       ; kept
.pt_drop:
    cmp     ecx, [rel mem_terms_n]
    jae     .pt_dropped
    mov     rax, [r9 + rcx * 8]
    test    rax, rax
    jz      .pt_drop_next
    mov     [r9 + rdx * 8], rax
    mov     al, [r8 + rcx]
    mov     [r8 + rdx], al
    mov     al, [r10 + rcx]
    mov     [r10 + rdx], al
    inc     edx
.pt_drop_next:
    inc     ecx
    jmp     .pt_drop
.pt_dropped:
    mov     [rel mem_terms_n], edx
    test    edx, edx
    jz      .pt_ok
    ; [rip + rax]: no such address (GNU's rip takes no other register)
    mov     eax, EXIT_INVALID_ADDR
    cmp     byte [rel mem_rip_written], 0
    jne     .error
    ; [rel rax]: NASM's warning, and the address is [rax]
    test    byte [r12 + OPERAND_flags], OP_FLAG_REL
    jz      .pt_placed_rel
    cmp     byte [r12 + OPERAND_base], REG_RIP
    jne     .pt_placed_rel
    and     byte [r12 + OPERAND_flags], ~OP_FLAG_REL
    mov     byte [r12 + OPERAND_base], 0xFF
    mov     edi, WC_OTHER
    call    warn_begin
    lea     rsi, [rel s_rel_regs]
    call    warn_text
    call    warn_end
    lea     r8, [rel mem_terms_reg]
    lea     r9, [rel mem_terms_coef]
    lea     r10, [rel mem_terms_mul]
    mov     edx, [rel mem_terms_n]
.pt_placed_rel:
    cmp     edx, 2
    ja      .bad_too_many
    je      .pt_two
    ; one register
    movzx   eax, byte [r8]
    mov     rcx, [r9]
    call    .pt_vector
    jnc     .pt_index
    cmp     rcx, 1
    jne     .pt_one_scaled
    test    byte [r10], 2
    jnz     .pt_index                      ; "[3, r12]": the index
    test    byte [r12 + OPERAND_flags], OP_FLAG_NOSPLIT
    jz      .pt_base
    cmp     byte [r10], 0
    jne     .pt_index                      ; "nosplit rax*1"
.pt_base:
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .place_bad
    mov     [r12 + OPERAND_base], al
.pt_ok:
    xor     eax, eax
    ret
.pt_one_scaled:
    cmp     rcx, 3
    je      .pt_split
    cmp     rcx, 5
    je      .pt_split
    cmp     rcx, 9
    jne     .pt_index
.pt_split:
    cmp     byte [r12 + OPERAND_base], 0xFF
    jne     .bad_bits
    mov     [r12 + OPERAND_base], al
    dec     ecx
    jmp     .pt_index

.pt_two:
    movzx   eax, byte [r8]
    call    .pt_vector
    jnc     .pt_first_index                ; [xmm1 + rax]: the vector
    movzx   eax, byte [r8 + 1]
    call    .pt_vector
    jnc     .pt_second_index
    cmp     qword [r9], 1
    je      .pt_first_once
    cmp     qword [r9 + 8], 1
    jne     .bad_two_index
.pt_first_index:
    ; the first one the index, the second the base
    movzx   eax, byte [r8 + 1]
    call    .pt_vector
    jnc     .bad_two_index                 ; two vector registers
    cmp     qword [r9 + 8], 1
    jne     .pt_first_scaled
    call    .pt_base
    test    eax, eax
    jnz     .pt_ret
    movzx   eax, byte [r8]
    mov     rcx, [r9]
    jmp     .pt_index
.pt_first_once:
    cmp     qword [r9 + 8], 1
    jne     .pt_second_index
    cmp     byte [r10], 0
    jne     .pt_first_index                ; [rbx*1 + rax]: rax is the base
.pt_second_index:
    ; the first one the base, the second the index
    cmp     qword [r9], 1
    jne     .pt_second_scaled
    movzx   eax, byte [r8]
    call    .pt_base
    test    eax, eax
    jnz     .pt_ret
    movzx   eax, byte [r8 + 1]
    mov     rcx, [r9 + 8]
    ; (falls through)
.pt_index:
    ; eax = the index, rcx its scale: 1, 2, 4 or 8
    cmp     rcx, 1
    je      .pt_scale_ok
    cmp     rcx, 2
    je      .pt_scale_ok
    cmp     rcx, 4
    je      .pt_scale_ok
    cmp     rcx, 8
    jne     .bad_bits
.pt_scale_ok:
    cmp     byte [r12 + OPERAND_index], 0xFF
    jne     .place_bad
    mov     [r12 + OPERAND_index], al
    mov     [r12 + OPERAND_scale], cl
    xor     eax, eax
.pt_ret:
    ret
; the base has a scale too: two index registers, unless it can be split
; ([rbx*3 + rcx]: NASM's "invalid 64-bit effective address")
.pt_first_scaled:
    mov     rcx, [r9 + 8]
    jmp     .pt_scaled_base
.pt_second_scaled:
    mov     rcx, [r9]
.pt_scaled_base:
    cmp     rcx, 3
    je      .bad_bits
    cmp     rcx, 5
    je      .bad_bits
    cmp     rcx, 9
    je      .bad_bits
    jmp     .bad_two_index

; .pt_vector: CF clear when eax is a vector register (xmm / ymm / zmm)
.pt_vector:
    cmp     eax, 80
    jb      .pt_not_vector
    cmp     eax, 112
    jae     .pt_not_vector
    clc
    ret
.pt_not_vector:
    stc
    ret

[SECTION .bss]
; a memory operand being read: the registers the expression evaluator took
; as "4*rcx" (parser_evaluate_term), for parser_parse_mem_operand
mem_scaled_tok:   resq MEM_SCALED_MAX     ; the register's token
mem_scaled_coef:  resq MEM_SCALED_MAX     ; its scale
mem_term_coef:    resq 1                  ; the register being placed: scale
mem_terms_coef:   resq MEM_SCALED_MAX     ; the address's registers, as written:
mem_terms_reg:    resb MEM_SCALED_MAX     ; scale, register, and whether the
mem_terms_mul:    resb MEM_SCALED_MAX     ; scale was written (.add_term);
                                          ; 2: after a split form's comma
mem_after_comma:  resb 1                  ; 2 once "[base, index]"'s comma is read
mem_mib:          resb 1                  ; the instruction's address is an MIB
alignb 4
mem_terms_n:      resd 1
mem_scaled_n:     resd 1
mem_scaled_take:  resd 1                  ; how many the operand has taken
mem_scaling:      resb 1                  ; a memory operand is being read
mem_term_pending: resb 1                  ; mem_term_coef came from the evaluator
mem_term_reg:     resb 1
mem_expect_term:  resb 1                  ; a '+' or '[' wants a term
mem_rip_written:  resb 1                  ; GNU's "rip" in the address
masm_no_var:      resb 1                  ; %use masm: OFFSET read (an address)
alignb 4
mem_term_width:   resd 1                  ; the register just read: its width
mem_addr_width:   resd 1                  ; the address's registers' width
[SECTION .text]

;*
; * [parser_parse_dfv]
; * Purpose: APX's "{dfv=of,sf,zf,cf}" (any of them, or none: "{dfv=}"),
; *   the '{' already read: INST_dfv the flags' bits (OF 8, SF 4, ZF 2,
; *   CF 1), APX_DFV in INST_apx - the flags ccmp / ctest set when their
; *   condition is false.
; * Input  : RBX = PrepState, R15 = INST
; * Output : RAX = OK or EXIT_UNEXPECTED_TOKEN
; ;
parser_parse_dfv:
    push    r13
    or      byte [r15 + INST_apx], APX_DFV
    mov     rdi, rbx
    call    preprocessor_next_token        ; "dfv"
    test    rax, rax
    jnz     .pd_ret
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    test    rax, rax
    jnz     .pd_ret
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .pd_bad
.pd_next:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .pd_ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_RBRACE
    je      .pd_ok
    cmp     eax, TOK_COMMA
    je      .pd_next
    cmp     eax, TOK_IDENT
    jne     .pd_bad
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rsi + 2], 0
    jne     .pd_bad
    movzx   ecx, word [rsi]
    or      ecx, 0x2020                    ; (any case)
    lea     r13, [rel dfv_words]
.pd_word:
    cmp     byte [r13], 0
    je      .pd_bad
    cmp     cx, [r13]
    je      .pd_hit
    add     r13, 3
    jmp     .pd_word
.pd_hit:
    mov     al, [r13 + 2]
    or      [r15 + INST_dfv], al
    jmp     .pd_next
.pd_ok:
    xor     eax, eax
    jmp     .pd_ret
.pd_bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.pd_ret:
    pop     r13
    ret

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
