;
; ============================================================================
; File        : src/encode/x86/encoder.s
; Project     : utasm
; Description : AMD64 Instruction Encoder Logic.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

%define IMM_PLACEHOLDER 0x12345678   ; see amd64_imm_fixup
%include "src/include/arch/amd64.inc"
%include "src/include/elf.inc"

extern  reloc_record
extern  arena_alloc

[SECTION .text]

;*
; * [amd64_encode_instruction]
; * Purpose: Encodes an AMD64 instruction into machine code.
; * Input:
; *   RDI: Pointer to AsmCtx
; *   RSI: Pointer to INST struct
; ;
global amd64_encode_instruction
amd64_encode_instruction:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; RBX = AsmCtx
    mov     r12, rsi               ; R12 = INST

    ; A96: Dispatch Integrity - Validate operand count
    IF byte [r12 + INST_nops], g, 4
        mov rax, EXIT_ENCODE_FAIL
        jmp .error
        ENDIF
    
    ; Reset length counter and the pending RIP-relative relocation
    mov     dword [rbx + ASMCTX_inst_len], 0
    extern  amd64_a67_at
    mov     qword [rel amd64_a67_at], -1
    extern  amd64_rex2_at
    mov     qword [rel amd64_rex2_at], -1  ; (no REX2 yet: mode.s)
    mov     dword [rel amd64_rip_pending], 0
    mov     dword [rel amd64_reloc_err], 0
    mov     byte [rel amd64_relax_kind], 0
    mov     byte [rel imm_ph_active], 0

    ; "cpuid eax", "hlt 5": an instruction that takes no operands given
    ; some (tables/noops.s) - no form, not the opcode with them dropped
    cmp     byte [r12 + INST_nops], 0
    je      .ops_any
    movzx   eax, word [r12 + INST_op_id]
    extern  amd64_takes_none
    call    amd64_takes_none
    jne     .ops_any
    mov     rax, EXIT_ENCODE_FAIL
    jmp     .error
.ops_any:
    ; rdmsr / wrmsrns with an MSR's number, urdmsr / uwrmsr (x86/msr.s)
    extern  amd64_msr_claim, amd64_encode_msr
    call    amd64_msr_claim
    jne     .not_msr
    call    amd64_encode_msr
    jmp     .done
.not_msr:
    ; AMX's dot products: three different tile registers (simd/amx.s)
    extern  amd64_amx_check
    call    amd64_amx_check
    test    rax, rax
    jnz     .done                          ; (its own error, not .error's)
    ; a gather: destination, index and mask all different (simd/gather.s)
    extern  amd64_gather_check
    call    amd64_gather_check
    test    rax, rax
    jnz     .done

    ; lea's source is an address, whatever it was written as
    cmp     word [r12 + INST_op_id], 1356  ; LEA
    jne     .not_lea
    cmp     byte [r12 + INST_nops], 2
    jne     .not_lea
    call    amd64_lea_address
    test    rax, rax
    jnz     .error
    ; "lea rsi, dword [foo]": the size of what is addressed does not
    ; matter to lea (NASM ignores it)
    cmp     byte [r12 + INST_op1 + OPERAND_kind], OP_MEM
    jne     .not_lea
    mov     byte [r12 + INST_op1 + OPERAND_size], 0
    mov     word [r12 + INST_op1 + OPERAND_xsize], 0
.not_lea:


    ; the operand shapes NASM 3 takes as another form (mode.s)
    extern  amd64_shape_forms
    call    amd64_shape_forms
    test    rax, rax
    jnz     .error

    ; {disp8} / {disp32}: the displacement's size, for each memory operand
    ; with none written
    test    byte [r12 + INST_flags], INSTF_DISP8 | INSTF_DISP32
    jz      .no_disp_pfx
    mov     al, 8
    test    byte [r12 + INST_flags], INSTF_DISP8
    jnz     .disp_pfx_size
    mov     al, 32
.disp_pfx_size:
    xor     ecx, ecx
.disp_pfx_op:
    movzx   edx, byte [r12 + INST_nops]
    cmp     ecx, edx
    jae     .no_disp_pfx
    imul    rdx, rcx, OPERAND_SIZE
    lea     rdx, [r12 + INST_op0 + rdx]
    inc     ecx
    cmp     byte [rdx + OPERAND_kind], OP_MEM
    jne     .disp_pfx_op
    cmp     byte [rdx + OPERAND_dispsize], 0
    jne     .disp_pfx_op
    mov     [rdx + OPERAND_dispsize], al
    jmp     .disp_pfx_op
.no_disp_pfx:

    ; 0a. An immediate whose value came from a label defined earlier is still
    ;     an address: encode it as a symbol reference, relocated, exactly as
    ;     for a label defined later ("mov eax, msg", "push table"). Only
    ;     branches keep the label itself (they measure the distance to it).
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, 1059                      ; CALL
    je      .branch
    cmp     eax, 1298                      ; JMP
    je      .branch
    cmp     eax, 1373                      ; LOOP
    je      .branch
    cmp     eax, 2151                      ; XBEGIN
    je      .branch
    cmp     eax, 3000
    jb      .sym_not_jcc
    cmp     eax, 3099                      ; Jcc
    jbe     .branch
.sym_not_jcc:
    cmp     eax, 6524
    jb      .sym_ops
    cmp     eax, 6529                      ; LOOPcc, JECXZ, JRCXZ
    jbe     .branch
    cmp     eax, 6536                      ; JCXZ
    jne     .sym_ops
.branch:
    ; "jc" or "jmp" with nothing to go to: no form (NASM's invalid
    ; combination; utasm wrote rel32 0 and FF 24 00)
    cmp     byte [r12 + INST_nops], 0
    jne     .sym_done
    mov     rax, EXIT_ENCODE_FAIL
    jmp     .error
.sym_ops:
    xor     ecx, ecx
.sym_op:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .sym_done
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    jne     .sym_next
    mov     rsi, [rdi + OPERAND_sym]
    test    rsi, rsi
    jz      .sym_next
    cmp     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    jne     .sym_next
    cmp     word [rsi + SYMBOL_section], SHN_ABS
    je      .sym_next                      ; "x equ 5": a number
    ; an address: a label, data, an extern - or a name only declared so far
    ; ("global foo" before "foo:": it was written as a number, 0, with no
    ; relocation)
    push    rdi
    mov     rdi, rsi
    extern  expr_sym_class
    call    expr_sym_class
    pop     rdi
    test    eax, eax
    jz      .sym_next
.sym_convert:
    mov     rax, [rdi + OPERAND_imm]
    sub     rax, [rsi + SYMBOL_value]      ; what was added to it
    mov     [rdi + OPERAND_imm], rax
    mov     rax, [rsi + SYMBOL_name]
    mov     [rdi + OPERAND_sym], rax
    mov     byte [rdi + OPERAND_kind], OP_SYMBOL
.sym_next:
    inc     ecx
    jmp     .sym_op
.sym_done:

    ; APX's EVEX forms (apx.s): "add rax, rbx, rcx", {nf}, {evex} - their
    ; own operand rules, written after the legacy prefixes
    extern  amd64_apx_claim, amd64_apx_mine
    call    amd64_apx_claim
    test    eax, eax
    jnz     .done
    cmp     byte [rel amd64_apx_mine], 1
    je      .apx_claimed
    cmp     byte [rel amd64_apx_mine], 2
    je      .apx_none                      ; ({nf} andn ...: dispatch.s writes it)
    ; {nf} / {zu} / {dfv=...} where no APX form took them: an error, not
    ; the instruction with its flags written after all
    cmp     byte [r12 + INST_apx], 0
    je      .apx_none
    mov     eax, EXIT_ENCODE_FAIL
    jmp     .done
.apx_claimed:
    extern  amd64_asize_mem
    call    amd64_asize_mem
    jmp     .no_size_check
.apx_none:
    ; inc / dec / neg / not take one operand ("inc rax, rbx" - APX's new
    ; destination - went out as inc rax) unless APX writes them
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, 1278                      ; INC
    je      .one_op
    cmp     eax, 1118                      ; DEC
    je      .one_op
    cmp     eax, 1439                      ; NEG
    je      .one_op
    cmp     eax, 1441                      ; NOT
    jne     .one_op_ok
.one_op:
    cmp     byte [r12 + INST_nops], 1
    je      .one_op_ok
    mov     rax, EXIT_ENCODE_FAIL
    jmp     .error
.one_op_ok:

    ; 0-. Operands no form of the instruction takes ("mov bl, r9w")
    extern  amd64_check_shape
    call    amd64_check_shape
    test    rax, rax
    jnz     .done
    ; ... and, outside 64-bit mode, operands that do not exist there
    ; (rax, r8, sil, [rax]) - or, in it, 16-bit addressing (mode.s)
    extern  amd64_asize_mem, amd64_mode_check
    call    amd64_asize_mem                ; ("a32 mov al, [0]")
    call    amd64_mode_check
    test    rax, rax
    jnz     .done
    extern  amd64_mand66
    mov     byte [rel amd64_mand66], 0
    ; "mov eax, word 5": a sized immediate no form takes (mode.s)
    extern  amd64_imm_size_check
    call    amd64_imm_size_check
    test    rax, rax
    jnz     .done
    ; push / pop: in 64-bit code 64 or 16 bits, never a dword (NASM's
    ; error; "push dword [rax]" pushed 64 bits, silently); an immediate of
    ; no size written takes o16 / o32's ("o16 push 0x12345" in bits 32 had
    ; a 66 before a 4-byte immediate: the next instruction read wrong)
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, 1583                      ; PUSH
    je      .push_pop
    cmp     eax, 1534                      ; POP
    jne     .push_pop_ok
.push_pop:
    extern  asm_bits
    cmp     byte [rel asm_bits], 64
    jne     .push_size
    cmp     byte [r12 + INST_op0 + OPERAND_size], 32
    jne     .push_size
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    je      .push_size                     ; (push eax: its own error)
    mov     eax, EXIT_OSZ32_64
    jmp     .done
.push_size:
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_IMM
    jne     .push_pop_ok
    cmp     byte [r12 + INST_op0 + OPERAND_size], 0
    jne     .push_pop_ok
    movzx   eax, byte [r12 + INST_osize]
    test    eax, eax
    jz      .push_pop_ok
    cmp     byte [rel asm_bits], 64
    jne     .push_sized
    cmp     eax, 32
    je      .push_pop_ok                   ; (o32 in 64-bit code: amd64_force_osize)
.push_sized:
    mov     [r12 + INST_op0 + OPERAND_size], al
.push_pop_ok:
    ; immediates as the operation's width sees them: 0xFFFF in a 16-bit
    ; operation is -1, so the imm8 forms apply as in NASM
    extern  amd64_imm_canon
    call    amd64_imm_canon

    ; 0. VALIDATION: Check operand size consistency (A87: Hardened)
    ; Mnemonics with table forms (dispatch.s) check their operands per form:
    ; movd xmm0, eax or cvtsi2sd xmm0, rax mix sizes by design.
    extern  amd64_table_has
    call    amd64_table_has
    test    eax, eax
    jnz     .no_size_check
    ; MOVSX/MOVSXD/MOVZX widen their source, so their operands differ by design
    movzx   eax, word [r12 + INST_op_id]
    cmp     ax, 1426               ; MOVSX
    je      .no_size_check
    cmp     ax, 1427               ; MOVSXD
    je      .no_size_check
    cmp     ax, 1430               ; MOVZX
    je      .no_size_check
    ; IN / OUT pair the accumulator with DX or an imm8; LAR / LSL take any
    ; selector register: their encoders check the sizes themselves
    cmp     ax, 1277               ; IN
    je      .no_size_check
    cmp     ax, 1445               ; OUT
    je      .no_size_check
    cmp     ax, 1351               ; LAR
    je      .no_size_check
    cmp     ax, 1375               ; LSL
    je      .no_size_check

    ; Shifts and rotates take their count in CL or as an imm8, so the two
    ; operand widths differ by design as well
    cmp     ax, 1647               ; SHL
    je      .no_size_check
    cmp     ax, 1650               ; SHR
    je      .no_size_check
    cmp     ax, 1625               ; SAR
    je      .no_size_check
    cmp     ax, 1612               ; ROL
    je      .no_size_check
    cmp     ax, 1613               ; ROR
    je      .no_size_check

    movzx   ecx, byte [r12 + INST_nops]
    IF ecx, ge, 2
        lea     r10, [r12 + INST_op0]
        lea     r11, [r12 + INST_op1]
        mov     al, [r10 + OPERAND_size]
        mov     dl, [r11 + OPERAND_size]
        
        ; If both have explicit sizes, they must match
        IF al, ne, 0
        IF dl, ne, 0
            IF al, ne, dl
                ; Exceptions: Immediate/Symbol can vary
                IF byte [r11 + OPERAND_kind], ne, OP_IMM
                IF byte [r11 + OPERAND_kind], ne, OP_SYMBOL
                    jmp .error
                    ENDIF
                    ENDIF
                    ENDIF
                ENDIF
            ENDIF
    ENDIF
.no_size_check:
    
    ; 0.1 VALIDATION: REX vs Legacy 8-bit (AH, CH, DH, BH)
    ; These registers (indices 4-7 in 8-bit mode without REX)
    ; cannot be used if a REX prefix is present.
    ; ...
    
    ; 1. Emit Prefixes if present (REP/LOCK) (A71); an "a32" goes out
    ;    last, in NASM's order (f3 66 67 a5 for "a32 rep movsd")
    xor     rcx, rcx
.prefix_loop:
    movzx   rax, byte [r12 + INST_prefixes + rcx]
    cmp     eax, 0x67
    je      .prefix_next
    IF rax, ne, 0
        push    rcx
        mov     rdi, rbx
        mov     rsi, rax
        extern  amd64_emit_byte
        call    amd64_emit_byte
        pop     rcx
        ENDIF
.prefix_next:
    inc     rcx
    cmp     rcx, 4
    jl      .prefix_loop
    
    ; 2. Emit Segment Prefix if present in any operand
    lea     rdi, [r12 + INST_op0]
    call    amd64_seg_of
    IF al, e, 0
        lea rdi, [r12 + INST_op1]
        call amd64_seg_of
        ENDIF
    IF al, ne, 0
        call    amd64_seg_default
        je      .seg_done                  ; GNU's syntax: the default one, left out
        call    amd64_emit_byte
        ENDIF
.seg_done:

    ; 2b. Address-size prefix: "a32" written, or memory addressed by
    ;     registers of the other size
    cmp     byte [r12 + INST_prefixes], 0x67
    je      .addr_emit
    cmp     byte [r12 + INST_prefixes + 1], 0x67
    je      .addr_emit
    cmp     byte [r12 + INST_prefixes + 2], 0x67
    je      .addr_emit
    cmp     byte [r12 + INST_prefixes + 3], 0x67
    je      .addr_emit
    xor     ecx, ecx
.addr32_loop:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .addr32_done
    mov     eax, ecx
    imul    eax, eax, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0]
    add     rdi, rax
    inc     ecx
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .addr32_loop
    ; addressed by registers of another width than the mode's: 32-bit ones
    ; in 64-bit or 16-bit mode, 16-bit ones in 32-bit mode
    extern  asm_bits
    movzx   eax, byte [rel asm_bits]
    cmp     eax, 32
    je      .addr_in32
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR32
    jz      .addr32_loop
    jmp     .addr_other
.addr_in32:
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR16
    jz      .addr32_loop
.addr_other:
    ; "a32" already put the prefix there
    cmp     byte [r12 + INST_prefixes], 0x67
    je      .addr32_done
    cmp     byte [r12 + INST_prefixes + 1], 0x67
    je      .addr32_done
    cmp     byte [r12 + INST_prefixes + 2], 0x67
    je      .addr32_done
    cmp     byte [r12 + INST_prefixes + 3], 0x67
    je      .addr32_done
.addr_emit:
    extern  amd64_a67_at
    mov     rax, [rbx + ASMCTX_curr_sec]   ; where it goes: a 66 the encoder
    mov     rax, [rax + SECTION_size]      ; emits later comes before it
    mov     [rel amd64_a67_at], rax
    mov     al, 0x67
    call    amd64_emit_byte
.addr32_done:

    ; "pop cs": the 8086's 0F, which NASM still writes, in any mode, with
    ; its warning (0F is the two-byte opcodes' escape since the 286)
    cmp     word [r12 + INST_op_id], 1534  ; POP
    jne     .not_pop_cs
    cmp     byte [r12 + INST_nops], 1
    jne     .not_pop_cs
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .not_pop_cs
    cmp     byte [r12 + INST_op0 + OPERAND_reg], REG_CS
    jne     .not_pop_cs
    ; not in 64-bit code (NASM 3's error): 0F there began whatever came
    ; next as a two-byte opcode
    cmp     byte [rel asm_bits], 64
    jne     .pop_cs_ok
    extern  amd64_bits_error
    call    amd64_bits_error               ; ("... in 64-bit mode")
    jmp     .done
.pop_cs_ok:
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     edi, WC_OBSOLETE_REMOVED
    lea     rsi, [rel s_obs_removed]
    extern  cpu_latevex
    test    byte [rel cpu_latevex], CPUF_8086
    jz      .pop_cs_warn
    mov     edi, WC_OBSOLETE_VALID
    lea     rsi, [rel s_obs_valid]
.pop_cs_warn:
    call    amd64_warn_class
    jmp     .mode_encoded
.not_pop_cs:
    ; APX's EVEX forms (apx.s), claimed above
    cmp     byte [rel amd64_apx_mine], 1
    jne     .not_apx
    extern  amd64_apx_encode
    call    amd64_apx_encode
    test    rax, rax
    jnz     .done
    jmp     .encoded
.not_apx:
    ; 2a. bits 16 / bits 32: the forms that differ there (mode.s); they are
    ; this mode's own encodings, with no REX to look for afterwards
    extern  amd64_mode_special
    call    amd64_mode_special
    cmp     rax, 1
    je      .mode_encoded
    test    rax, rax
    jnz     .done

    ; 2. Table-driven forms first (dispatch.s: SSE, x87, system and other
    ;    instructions generated by scripts/gen/gen_x86_enc.py). When no form of
    ;    the mnemonic fits, nothing was emitted and the encoders below run.
    ; ("push word 5": the tables have no 16-bit push immediate; the
    ; push encoder writes it with its 66)
    cmp     word [r12 + INST_op_id], 1583
    jne     .table
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_IMM
    jne     .table
    cmp     byte [r12 + INST_op0 + OPERAND_size], 16
    je      .table_done
.table:
    extern  amd64_table_encode
    call    amd64_table_encode
    cmp     rax, 1
    je      .encoded
    test    rax, rax
    jnz     .done
.table_done:
    ; a vector register with a size written ("movss xmm0, dword xmm1") is
    ; only a table form's operand: none fitted, and the encoders below do
    ; not know it
    xor     ecx, ecx
.vec_sized:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .vec_sized_ok
    imul    rdx, rcx, OPERAND_SIZE
    inc     ecx
    cmp     byte [r12 + INST_op0 + rdx + OPERAND_kind], OP_REG
    jne     .vec_sized
    cmp     byte [r12 + INST_op0 + rdx + OPERAND_dispsize], 0
    je      .vec_sized
    mov     rax, EXIT_ENCODE_FAIL
    jmp     .done
.vec_sized_ok:


    ; 2c. Most encoders below take no label as an immediate (only MOV to a
    ;     register and the branches do). Give them a placeholder value that
    ;     only a full-width immediate holds; amd64_imm_fixup then turns its
    ;     bytes into a relocation for the label.
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, 1059                      ; CALL
    je      .ph_done
    cmp     eax, 1298                      ; JMP
    je      .ph_done
    cmp     eax, 1373                      ; LOOP
    je      .ph_done
    cmp     eax, 2151                      ; XBEGIN
    je      .ph_done
    cmp     eax, 3000
    jb      .ph_not_jcc
    cmp     eax, 3099
    jbe     .ph_done
.ph_not_jcc:
    cmp     eax, 6536                      ; JCXZ
    je      .ph_done
    cmp     eax, 6524
    jb      .ph_not_loop
    cmp     eax, 6529
    jbe     .ph_done
.ph_not_loop:
    cmp     eax, 1391                      ; MOV reg, label: handled there
    jne     .ph_scan
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    je      .ph_done
.ph_scan:
    xor     ecx, ecx
.ph_op:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .ph_done
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    cmp     byte [rdi + OPERAND_kind], OP_SYMBOL
    jne     .ph_op
    mov     rax, [rdi + OPERAND_sym]
    mov     [rel imm_ph_sym], rax
    mov     rax, [rdi + OPERAND_imm]
    mov     [rel imm_ph_addend], rax
    mov     al, [rdi + OPERAND_pcrel]
    mov     [rel imm_ph_pcrel], al
    mov     byte [rdi + OPERAND_kind], OP_IMM
    mov     qword [rdi + OPERAND_imm], IMM_PLACEHOLDER
    mov     qword [rdi + OPERAND_sym], 0
    ; "add eax, byte foo": the sign-extended imm8 form, an 8-bit
    ; relocation (R_X86_64_8, PC8 for "byte (bar - $$)"), as NASM
    mov     byte [rel imm_ph_byte], 0
    cmp     byte [rdi + OPERAND_size], 8
    je      .ph_byte
    mov     rsi, [rel imm_ph_sym]
    movzx   edx, byte [rel imm_ph_pcrel]
    call    amd64_imm_guess
    test    eax, eax
    jz      .ph_width
.ph_byte:
    mov     qword [rdi + OPERAND_imm], IMM_PLACEHOLDER & 0x7F
    mov     byte [rel imm_ph_byte], 1
.ph_width:
    xor     eax, eax
    cmp     byte [r12 + INST_op0 + OPERAND_size], 64
    sete    al
    mov     [rel imm_ph_wide], al
    mov     byte [rel imm_ph_active], 1
.ph_done:

    ; 3. Dispatch based on Mnemonic ID
    movzx   rax, word [r12 + INST_op_id]
    
    IF ax, e, 1391                 ; MOV
        call    amd64_encode_mov
    ELSEIF ax, e, 1430             ; MOVZX
        mov     r13, 0xB6
        call    amd64_encode_movx
    ELSEIF ax, e, 1426             ; MOVSX
        mov     r13, 0xBE
        call    amd64_encode_movx
    ELSEIF ax, e, 1427             ; MOVSXD
        call    amd64_encode_movsxd
    ELSEIF ax, e, 1356             ; LEA
        call    amd64_encode_lea
    ELSEIF ax, e, 1006             ; ADD
        mov     r13, 0x01
        mov r14, 0
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1676             ; SUB
        mov     r13, 0x29
        mov r14, 5
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1004             ; ADC
        mov     r13, 0x11
        mov r14, 2
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1628             ; SBB
        mov     r13, 0x19
        mov r14, 3
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1075             ; CMP
        mov     r13, 0x39
        mov r14, 7
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1084             ; CMPXCHG
        mov     r13, 0xB1
        call amd64_encode_bin0f
    ELSEIF ax, e, 2150             ; XADD
        mov     r13, 0xC1
        call amd64_encode_bin0f
    ELSEIF ax, e, 1086             ; CMPXCHG8B
        mov     r14, 1
        call amd64_encode_cmpxchg_nb
    ELSEIF ax, e, 1085             ; CMPXCHG16B
        mov     r14, 1
        call amd64_encode_cmpxchg_nb
    ELSEIF ax, e, 1028             ; AND
        mov     r13, 0x21
        mov r14, 4
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1442             ; OR
        mov     r13, 0x09
        mov r14, 1
        call amd64_encode_arithmetic
    ELSEIF ax, e, 2157             ; XOR
        mov     r13, 0x31
        mov r14, 6
        call amd64_encode_arithmetic
    ELSEIF ax, e, 1691             ; TEST
        mov     r13, 0x85
        call amd64_encode_test
    ELSEIF ax, e, 1278             ; INC
        mov     r14, 0
        call amd64_encode_unary
    ELSEIF ax, e, 1118             ; DEC
        mov     r14, 1
        call amd64_encode_unary
    ELSEIF ax, e, 1439             ; NEG
        mov     r14, 3
        call amd64_encode_unary
    ELSEIF ax, e, 1059             ; CALL
        call    amd64_encode_call
    ELSEIF ax, e, 1298             ; JMP
        call    amd64_encode_jmp
    ELSEIF_RANGE ax, 3000, 3015    ; Jcc (id = 3000 + condition code)
        call    amd64_encode_jcc
    ELSEIF ax, e, 1611             ; RET
        call    amd64_encode_ret
    ELSEIF ax, e, 1583             ; PUSH
        mov     r13, 0x50
        mov r14, 0xFF          ; PUSH r/m is FF /6
        mov r15, 6
        call amd64_encode_push_pop
    ELSEIF ax, e, 1534             ; POP
        mov     r13, 0x58
        mov r14, 0x8F
        mov r15, 0
        call amd64_encode_push_pop
    ELSEIF ax, e, 1647             ; SHL
        mov     r14, 4
        call amd64_encode_shift
    ELSEIF ax, e, 1650             ; SHR
        mov     r14, 5
        call amd64_encode_shift
    ELSEIF ax, e, 1625             ; SAR
        mov     r14, 7
        call amd64_encode_shift
    ELSEIF ax, e, 1612             ; ROL
        mov     r14, 0
        call amd64_encode_shift
    ELSEIF ax, e, 1613             ; ROR
        mov     r14, 1
        call amd64_encode_shift
    ELSEIF ax, e, 1432             ; MUL
        mov     r14, 4
        call amd64_encode_unary
    ELSEIF ax, e, 1275             ; IDIV
        mov     r14, 7
        call amd64_encode_unary
    ELSEIF ax, e, 1276             ; IMUL
        call    amd64_encode_imul
    ELSEIF ax, e, 2152             ; XCHG
        call    amd64_encode_xchg
    ELSEIF_RANGE ax, 4000, 4031    ; CMOVcc & SETcc
        IF ax, le, 4015
            call amd64_encode_cmovcc
        ELSE
            call amd64_encode_setcc
            ENDIF
    ELSEIF_RANGE ax, 1418, 1425    ; MOVS - MOVSW
        mov r13, 0xA4
        call amd64_encode_string
    ELSEIF_RANGE ax, 1668, 1672    ; STOS - STOSW
        mov r13, 0xAA
        call amd64_encode_string
    ELSEIF_RANGE ax, 1368, 1372    ; LODS - LODSW
        mov r13, 0xAC
        call amd64_encode_string
    ELSEIF_RANGE ax, 1629, 1632    ; SCAS - SCASW
        mov r13, 0xAE
        call amd64_encode_string
    ELSEIF_RANGE ax, 1078, 1083    ; CMPS - CMPSW
        mov r13, 0xA6
        call amd64_encode_string
    ELSEIF ax, e, 1119             ; DIV
        mov     r14, 6
        call amd64_encode_unary
    ELSEIF ax, e, 1441             ; NOT
        mov     r14, 2
        call amd64_encode_unary
    ELSEIF ax, e, 1419             ; MOVSB
        mov     al, 0xA4
        call amd64_emit_byte
    ELSEIF ax, e, 1421             ; MOVSW
        mov     al, 16
        mov rsi, 0
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, 0xA5
        call amd64_emit_byte
    ELSEIF ax, e, 1420             ; MOVSD
        IF byte [r12 + INST_nops], e, 0
            mov     al, 0xA5
            call amd64_emit_byte
            ELSE
            mov     r13, 0x10
            mov r14, 1
            call amd64_encode_sse ; SSE (F2 0F 10/11)
            ENDIF
    ELSEIF ax, e, 1422             ; MOVSQ
        mov     al, 64
        mov rsi, 0
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, 0xA5
        call amd64_emit_byte
    ELSEIF ax, e, 1669             ; STOSB
        mov     al, 0xAA
        call amd64_emit_byte
    ELSEIF ax, e, 1672             ; STOSW
        mov     al, 16
        mov rsi, 0
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, 0xAB
        call amd64_emit_byte
    ELSEIF ax, e, 1670             ; STOSD
        mov     al, 0xAB
        call amd64_emit_byte
    ELSEIF ax, e, 1671             ; STOSQ
        mov     al, 64
        mov rsi, 0
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, 0xAB
        call amd64_emit_byte
    ELSEIF_RANGE ax, 1630, 1632    ; SCAS
        sub ax, 1630
        ; logic for 0xA6/0xA7
    ELSEIF ax, e, 1647             ; SHL/SAL
        mov     r14, 4
        call amd64_encode_shift
    ELSEIF ax, e, 1650             ; SHR
        mov     r14, 5
        call amd64_encode_shift
    ELSEIF ax, e, 1625             ; SAR
        mov     r14, 7
        call amd64_encode_shift
    ELSEIF ax, e, 1612             ; ROL
        mov     r14, 0
        call amd64_encode_shift
    ELSEIF ax, e, 1613             ; ROR
        mov     r14, 1
        call amd64_encode_shift
    ELSEIF ax, e, 1432             ; MUL
        mov     r14, 4
        call amd64_encode_unary_math
    ELSEIF ax, e, 1119             ; DIV
        mov     r14, 6
        call amd64_encode_unary_math
    ELSEIF ax, e, 1276             ; IMUL
        call    amd64_encode_imul
    ELSEIF ax, e, 1275             ; IDIV
        mov     r14, 7
        call amd64_encode_unary_math
    ELSEIF ax, e, 1583             ; PUSH
        call    amd64_encode_push
    ELSEIF ax, e, 1089             ; CPUID
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0xA2
        call amd64_emit_byte
    ELSEIF ax, e, 1604             ; RDTSC
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x31
        call amd64_emit_byte
    ELSEIF ax, e, 1605             ; RDTSCP
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xF9
        call amd64_emit_byte
    ELSEIF ax, e, 1596             ; RDMSR
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x32
        call amd64_emit_byte
    ELSEIF ax, e, 2142             ; WRMSR
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x30
        call amd64_emit_byte
    ELSEIF ax, e, 1271             ; HLT
        mov     al, 0xF4
        call amd64_emit_byte
    ELSEIF ax, e, 1286             ; INT
        call    amd64_encode_int
    ELSEIF ax, e, 1288             ; INT3
        mov     al, 0xCC
        call amd64_emit_byte
    ELSEIF ax, e, 1715             ; UD2
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x0B
        call amd64_emit_byte
    ELSEIF ax, e, 1361             ; LGDT
        mov     r14, 2
        call amd64_encode_system_m
    ELSEIF ax, e, 1363             ; LIDT
        mov     r14, 3
        call amd64_encode_system_m
    ELSEIF ax, e, 1364             ; LLDT
        mov     r14, 2
        call amd64_encode_system_00
    ELSEIF ax, e, 1656             ; SLDT
        mov     r14, 0
        call amd64_encode_system_00
    ELSEIF ax, e, 1377             ; LTR
        mov     r14, 3
        call amd64_encode_system_00
    ELSEIF ax, e, 1673             ; STR
        mov     r14, 1
        call amd64_encode_system_00
    ELSEIF ax, e, 1277             ; IN
        call    amd64_encode_in
    ELSEIF ax, e, 1445             ; OUT
        call    amd64_encode_out
    ELSEIF ax, e, 1205             ; FLD
        mov     r13, 0xD9
        mov r14, 0
        call amd64_encode_fpu
    ELSEIF ax, e, 1235             ; FST
        mov     r13, 0xD9
        mov r14, 2
        call amd64_encode_fpu
    ELSEIF ax, e, 1172             ; FADD
        mov     r13, 0xD8
        mov r14, 0
        call amd64_encode_fpu
    ELSEIF ax, e, 1240             ; FSUB
        mov     r13, 0xD8
        mov r14, 4
        call amd64_encode_fpu
    ELSEIF ax, e, 1215             ; FMUL
        mov     r13, 0xD8
        mov r14, 1
        call amd64_encode_fpu
    ELSEIF ax, e, 1186             ; FDIV
        mov     r13, 0xD8
        mov r14, 6
        call amd64_encode_fpu
    ELSEIF ax, e, 1232             ; FSIN
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFE
        call amd64_emit_byte
    ELSEIF ax, e, 1184             ; FCOS
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFF
        call amd64_emit_byte
    ELSEIF ax, e, 1199             ; FINIT
        mov     al, 0xDB
        call amd64_emit_byte
        mov al, 0xE3
        call amd64_emit_byte
    ELSEIF ax, e, 1179             ; FCOM
        mov     r13, 0xD8
        mov r14, 2
        call amd64_encode_fpu
    ELSEIF ax, e, 1238             ; FSTP
        mov     r13, 0xD9
        mov r14, 3
        call amd64_encode_fpu
    ELSEIF ax, e, 1234             ; FSQRT
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFA
        call amd64_emit_byte
    ELSEIF ax, e, 1251             ; FXAM
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xE5
        call amd64_emit_byte
    ELSEIF ax, e, 1227             ; FPTAN
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xF2
        call amd64_emit_byte
    ELSEIF ax, e, 1256             ; FYL2X
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xF1
        call amd64_emit_byte
    ELSEIF ax, e, 1395             ; MOVAPS
        mov     r13, 0x28
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1431             ; MOVUPS
        mov     r13, 0x10
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1459             ; PADDD
        mov     r13, 0xFE
        mov r14, 1
        call amd64_encode_sse ; 0x66 prefix
    ELSEIF ax, e, 1530             ; PMULLD
        mov     r13, 0x40
        mov r14, 2
        call amd64_encode_sse ; 0x0F 0x38
    ELSEIF ax, e, 2160             ; XORPS
        mov     r13, 0x57
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1008             ; ADDPS
        mov     r13, 0x58
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, ID_VADDPS
        mov     r13, 0x58
        mov r14, 0
        call amd64_encode_avx
    ELSEIF ax, e, ID_VXORPS
        mov     r13, 0x57
        mov r14, 0
        call amd64_encode_avx
    ELSEIF ax, e, 1010             ; ADDSS
        mov     r13, 0x58
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1678             ; SUBPS
        mov     r13, 0x5C
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1680             ; SUBSS
        mov     r13, 0x5C
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1434             ; MULPS
        mov     r13, 0x59
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1436             ; MULSS
        mov     r13, 0x59
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1121             ; DIVPS
        mov     r13, 0x5E
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1123             ; DIVSS
        mov     r13, 0x5E
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1660             ; SQRTPS
        mov     r13, 0x51
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1662             ; SQRTSS
        mov     r13, 0x51
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1033             ; ANDPS
        mov     r13, 0x54
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1031             ; ANDNPS
        mov     r13, 0x55
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1444             ; ORPS
        mov     r13, 0x56
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1701             ; UCOMISS
        mov     r13, 0x2E
        mov r14, 0
        call amd64_encode_sse
    ELSEIF ax, e, 1700             ; UCOMISD
        mov     r13, 0x2E
        mov r14, 1
        call amd64_encode_sse
    ELSEIF ax, e, 1739             ; VADDPS
        mov     r13, 0x58
        mov r14, 1
        call amd64_encode_vex
    ELSEIF ax, e, 1933             ; VMOVAPS
        mov     r13, 0x28
        mov r14, 1
        call amd64_encode_vex
    ; AMX (ldtilecfg ... tdpbssd): every form is the table's (NASM's list);
    ; operands it has none for are wrong ones
    ELSEIF ax, e, 1355             ; LDTILECFG
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1674             ; STTILECFG
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1693             ; TILELOADD
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1696             ; TILESTORED
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1697             ; TILEZERO
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1687             ; TDPBSSD
        mov     rax, EXIT_ENCODE_FAIL
    ELSEIF ax, e, 1600             ; RDRAND
        mov     r14, 6
        call amd64_encode_sec_r
    ELSEIF ax, e, 1601             ; RDSEED
        mov     r14, 7
        call amd64_encode_sec_r
    ELSEIF ax, e, 1165             ; ENDBR64
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov     al, 0x1E
        call amd64_emit_byte
        mov al, 0xFA
        call amd64_emit_byte
    ELSEIF ax, e, 1148             ; ENCLU
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xD7
        call amd64_emit_byte
    ELSEIF ax, e, 1158             ; ENCLV
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xC0
        call amd64_emit_byte
    ELSEIF ax, e, 1021             ; AESENC128KL
        mov     r13, 0xDC
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1022             ; AESENC256KL
        mov     r13, 0xDD
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1015             ; AESDEC128KL
        mov     r13, 0xDE
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1016             ; AESDEC256KL
        mov     r13, 0xDF
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1020             ; AESENC
        mov     r13, 0xDC
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1014             ; AESDEC
        mov     r13, 0xDE
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1023             ; AESENCLAST
        mov     r13, 0xDD
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1017             ; AESDECLAST
        mov     r13, 0xDF
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1026             ; AESIMC
        mov     r13, 0xDB
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1027             ; AESKEYGENASSIST
        mov     r13, 0xDF
        mov r14, 3
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1474             ; PCLMULQDQ
        mov     r13, 0x44
        mov r14, 3
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1642             ; SHA1NEXTE
        mov     r13, 0xC8
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1640             ; SHA1MSG1
        mov     r13, 0xC9
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1641             ; SHA1MSG2
        mov     r13, 0xCA
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1643             ; SHA1RNDS4
        mov     r13, 0xCC
        mov r14, 3
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1091             ; CRC32
        mov     r13, 0xF1
        lea     r10, [r12 + INST_op1]
        IF byte [r10 + OPERAND_size], e, 8
            mov r13, 0xF0
        ENDIF
        mov     r14, 2
        mov r15, 0xF2
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1537             ; POPCNT
        mov     r13, 0xB8
        mov r14, 1
        mov r15, 0xF3
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1394             ; MOVBE
        mov     r13, 0xF0
        lea     r10, [r12 + INST_op0]
        IF byte [r10 + OPERAND_kind], e, OP_MEM
            mov r13, 0xF1
        ENDIF
        mov     r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1646             ; SHA256RNDS2
        mov     r13, 0xCB
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1644             ; SHA256MSG1
        mov     r13, 0xCC
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1645             ; SHA256MSG2
        mov     r13, 0xCD
        mov r14, 2
        xor r15, r15
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1268             ; GF2P8MULB
        mov     r13, 0xCF
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1266             ; GF2P8AFFINEINVQB
        mov     r13, 0xCF
        mov r14, 3
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1267             ; GF2P8AFFINEQB
        mov     r13, 0xCE
        mov r14, 3
        mov r15, 0x66
        call amd64_encode_sse_crypto
    ELSEIF ax, e, 1127             ; ENCLS
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov     al, 0xCF
        call amd64_emit_byte
    ELSEIF ax, e, 5000             ; VMCALL
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xC1
        call amd64_emit_byte
    ELSEIF ax, e, 5001             ; VMLAUNCH
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xC2
        call amd64_emit_byte
    ELSEIF ax, e, 5002             ; VMRESUME
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xC3
        call amd64_emit_byte
    ELSEIF ax, e, 5003             ; VMXOFF
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xC4
        call amd64_emit_byte
    ELSEIF ax, e, 5004             ; VMXON
        mov     r13, 0xF3
        mov r14, 6
        call amd64_encode_vm_m
    ELSEIF ax, e, 5005             ; VMPTRLD
        xor     r13, r13
        mov r14, 6
        call amd64_encode_vm_m
    ELSEIF ax, e, 5006             ; VMPTRST
        xor     r13, r13
        mov r14, 7
        call amd64_encode_vm_m
    ELSEIF ax, e, 5007             ; VMCLEAR
        mov     r13, 0x66
        mov r14, 6
        call amd64_encode_vm_m
    ELSEIF ax, e, 5008             ; VMREAD
        mov     r13, 0x78
        call amd64_encode_vm_rm_r
    ELSEIF ax, e, 5009             ; VMWRITE
        mov     r13, 0x79
        call amd64_encode_vm_rm_r
    ELSEIF ax, e, 5010             ; INVEPT
        mov     r13, 0x660F3880
        call amd64_encode_rm_r
    ELSEIF ax, e, 5011             ; INVVPID
        mov     r13, 0x660F3881
        call amd64_encode_rm_r
    ; ---- AMD-V (SVM) ----
    ELSEIF ax, e, 5012             ; VMRUN
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xD8
        call amd64_emit_byte
    ELSEIF ax, e, 5013             ; VMMCALL
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xD9
        call amd64_emit_byte
    ELSEIF ax, e, 5014             ; VMLOAD
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDA
        call amd64_emit_byte
    ELSEIF ax, e, 5015             ; VMSAVE
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDB
        call amd64_emit_byte
    ELSEIF ax, e, 5016             ; CLGI
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDD
        call amd64_emit_byte
    ELSEIF ax, e, 5017             ; STGI
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDC
        call amd64_emit_byte
    ELSEIF ax, e, 5018             ; INVLPGA
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDF
        call amd64_emit_byte
    ELSEIF ax, e, 5019             ; SKINIT
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xDE
        call amd64_emit_byte
    ELSEIF ax, e, 1351             ; LAR
        mov     r13, 0x02
        call amd64_encode_rm_r_0f
    ELSEIF ax, e, 1375             ; LSL
        mov     r13, 0x03
        call amd64_encode_rm_r_0f
    ELSEIF ax, e, 1791             ; VERR
        mov     r14, 4
        call amd64_encode_system_00
    ELSEIF ax, e, 1792             ; VERW
        mov     r14, 5
        call amd64_encode_system_00
    ELSEIF ax, e, 1359             ; LFENCE
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        mov     al, 0xE8
        call amd64_emit_byte
    ELSEIF ax, e, 1637             ; SFENCE
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        mov     al, 0xF8
        call amd64_emit_byte
    ELSEIF ax, e, 1385             ; MFENCE
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        mov     al, 0xF0
        call amd64_emit_byte

    ; ---- Step 2: Cache & Memory Fencing ----
    ELSEIF ax, e, 1067             ; CLFLUSH
        mov     r13, 0x0FAE
        mov r14, 7
        call amd64_encode_rm_m
    ELSEIF ax, e, 1068             ; CLFLUSHOPT
        mov     al, 0x66
        call amd64_emit_byte
        mov     r13, 0x0FAE
        mov r14, 7
        call amd64_encode_rm_m
    ELSEIF ax, e, 1073             ; CLWB
        mov     al, 0x66
        call amd64_emit_byte
        mov     r13, 0x0FAE
        mov r14, 6
        call amd64_encode_rm_m
    ELSEIF ax, e, 5020             ; CLZERO
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xFC
        call amd64_emit_byte
    ELSEIF ax, e, 1543             ; PREFETCHW
        mov     r13, 0x0F0D
        mov r14, 1
        call amd64_encode_rm_m
    ELSEIF ax, e, 1544             ; PREFETCHWT1
        mov     r13, 0x0F0D
        mov r14, 2
        call amd64_encode_rm_m

    ; ---- Step 3: FMA3 / FMA4 (EVEX/VEX) ----
    ELSEIF_RANGE ax, 1832, 1909    ; FMA3 Range
        ; their forms are the table's (dispatch.s): operands none of them
        ; takes are an error - this wrote 0F 38 98 for any of them
        jmp     .error

    ; ---- Step 4: Legacy 8087 Math ----
    ELSEIF ax, e, 5300             ; FSIN
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFE
        call amd64_emit_byte
    ELSEIF ax, e, 5301             ; FCOS
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFF
        call amd64_emit_byte
    ELSEIF ax, e, 5302             ; FSINCOS
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xFB
        call amd64_emit_byte
    ELSEIF ax, e, 5303             ; FPATAN
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xF3
        call amd64_emit_byte
    ELSEIF ax, e, 1170             ; F2XM1
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xF0
        call amd64_emit_byte
    ELSEIF ax, e, 5305             ; FLD1
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xE8
        call amd64_emit_byte
    ELSEIF ax, e, 5306             ; FLDZ
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xEE
        call amd64_emit_byte
    ELSEIF ax, e, 5307             ; FLDPI
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xEB
        call amd64_emit_byte
    ELSEIF ax, e, 5308             ; FLDLN2
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xED
        call amd64_emit_byte
    ELSEIF ax, e, 5309             ; FSAVE
        mov     al, 0x9B
        call amd64_emit_byte
        mov     r13, 0xDD
        mov r14, 6
        call amd64_encode_rm_m
    ELSEIF ax, e, 5310             ; FRSTOR
        mov     r13, 0xDD
        mov r14, 4
        call amd64_encode_rm_m
    ELSEIF ax, e, 5311             ; FLDENV
        mov     r13, 0xD9
        mov r14, 4
        call amd64_encode_rm_m
    ELSEIF ax, e, 5312             ; FSTENV
        mov     al, 0x9B
        call amd64_emit_byte
        mov     r13, 0xD9
        mov r14, 6
        call amd64_encode_rm_m

    ; ---- Step 5: AVX-512 (EVEX) ----
    ELSEIF_RANGE ax, 5400, 5412    ; AVX-512 Range
        ; the table's forms only (it wrote 62 F1 FD 08 and nothing more)
        jmp     .error

    ; ---- Step 6: VNNI & BFLOAT16 ----
    ELSEIF_RANGE ax, 5500, 5503    ; VNNI Range
        ; the table's forms only (it wrote a lone 62)
        jmp     .error

    ; ---- Step 7: 3DNow! & AMD XOP ----
    ELSEIF_RANGE ax, 5600, 5612    ; 3DNow Range
        ; 3DNow! (0F 0F /r and its opcode byte after) and femms are the
        ; table's, NASM's forms (scripts/gen/gen_x86_enc.py); XOP has none: an
        ; error (this wrote 0F 0F alone)
        jmp     .error

    ; ---- Step 8: SGX Enclave Sub-Leafs ----
    ELSEIF_RANGE ax, 5700, 5706    ; SGX Range
        ; a leaf function by its name: "mov eax, leaf" and ENCLS (0F 01 CF)
        ; or ENCLU (0F 01 D7) - eadd / eblock / ecreate / einit are ENCLS
        ; leaves, eenter / eresume / egetkey ENCLU ones (it was ENCLS for
        ; all, and no leaf)
        call    amd64_sgx_leaf
        test    rax, rax
        jnz     .done

    ELSEIF ax, e, 1054             ; BT
        mov     r13, 0xA3
        mov r14, 4
        call amd64_encode_bt
    ELSEIF ax, e, 1057             ; BTS
        mov     r13, 0xAB
        mov r14, 5
        call amd64_encode_bt
    ELSEIF ax, e, 1056             ; BTR
        mov     r13, 0xB3
        mov r14, 6
        call amd64_encode_bt
    ELSEIF ax, e, 1055             ; BTC
        mov     r13, 0xBB
        mov r14, 7
        call amd64_encode_bt
    ELSEIF ax, e, 1063             ; CLAC
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xCA
        call amd64_emit_byte
    ELSEIF ax, e, 1663             ; STAC
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xCB
        call amd64_emit_byte
    ELSEIF ax, e, 2154             ; XGETBV
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xD0
        call amd64_emit_byte
    ELSEIF ax, e, 2168             ; XSETBV
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xD1
        call amd64_emit_byte
    ELSEIF ax, e, 2164             ; XSAVE
        mov     r14, 4
        call amd64_encode_mem_sync
    ELSEIF ax, e, 2162             ; XRSTOR
        mov     r14, 5
        call amd64_encode_mem_sync
    ELSEIF ax, e, 1067             ; CLFLUSH
        mov     r14, 7
        call amd64_encode_mem_sync
    ELSEIF ax, e, 1686             ; SYSENTER
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x34
        call amd64_emit_byte
    ELSEIF ax, e, 1682             ; SYSCALL
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x05
        call amd64_emit_byte
    ELSEIF ax, e, 1684             ; SYSEXIT
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x35
        call amd64_emit_byte
    ELSEIF ax, e, 1685             ; SYSRET
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x07
        call amd64_emit_byte
    ELSEIF ax, e, 1290             ; INVD
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x08
        call amd64_emit_byte
    ELSEIF ax, e, 1295             ; IRET
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0xCF
        call amd64_emit_byte
    ELSEIF ax, e, 1296             ; IRETD
        mov     al, 0xCF
        call amd64_emit_byte
    ELSEIF ax, e, 1297             ; IRETQ
        mov     al, 0x48
        call amd64_emit_byte
        mov al, 0xCF
        call amd64_emit_byte
    ELSEIF ax, e, 1292             ; INVLPG
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov     al, 7
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1376             ; LSS
        mov     r13, 0x0FB2
        call amd64_encode_rm_r
    ELSEIF ax, e, 1360             ; LFS
        mov     r13, 0x0FB4
        call amd64_encode_rm_r
    ELSEIF ax, e, 1362             ; LGS
        mov     r13, 0x0FB5
        call amd64_encode_rm_r
    ELSEIF ax, e, 1293             ; INVPCID
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov     al, 0x38
        call amd64_emit_byte
        mov al, 0x82
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        lea     r11, [r12 + INST_op1]
        mov     al, [r10 + OPERAND_reg]
        mov     rdi, r11
        call amd64_emit_modrm_sib
        
    ; ---- Advanced Bit Manipulation (BMI1/BMI2/TBM) ----
    ELSEIF ax, e, 1029             ; ANDN
        mov     r13, 0xF2
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1035             ; BEXTR
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1040             ; BLSI
        mov     r13, 0xF3
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex_unary
    ELSEIF ax, e, 1041             ; BLSMSK
        mov     r13, 0xF3
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex_unary
    ELSEIF ax, e, 1042             ; BLSR
        mov     r13, 0xF3
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex_unary
    ELSEIF ax, e, 1058             ; BZHI
        mov     r13, 0xF5
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1437             ; MULX
        mov     r13, 0xF6
        mov r14, 2
        mov r15, 0xF2
        call amd64_encode_vex
    ELSEIF ax, e, 1488             ; PDEP
        mov     r13, 0xF5
        mov r14, 2
        mov r15, 0xF2
        call amd64_encode_vex
    ELSEIF ax, e, 1489             ; PEXT
        mov     r13, 0xF5
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_vex
    ELSEIF ax, e, 1614             ; RORX
        mov     r13, 0xF0
        mov r14, 3
        mov r15, 0xF2
        call amd64_encode_vex
    ELSEIF ax, e, 1626             ; SARX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_vex
    ELSEIF ax, e, 1649             ; SHLX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_vex
    ELSEIF ax, e, 1652             ; SHRX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 0xF2
        call amd64_encode_vex
    ELSEIF ax, e, 1699             ; TZCNT
        mov     al, 0xF3
        call amd64_emit_byte
        mov     r13, 0x0FBC
        call amd64_encode_rm_r
        
    ; ----Hardware Sync (WaitPKG / UINTR) ----
    ELSEIF ax, e, 1698             ; TPAUSE
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1704             ; UMONITOR
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1705             ; UMWAIT
        mov     al, 0xF2
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1633             ; SENDUIPI
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xC7
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1703             ; UIRET
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xEC
        call amd64_emit_byte
    ELSEIF ax, e, 1692             ; TESTUI
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xED
        call amd64_emit_byte
    ELSEIF ax, e, 1072             ; CLUI
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xEE
        call amd64_emit_byte
    ELSEIF ax, e, 1675             ; STUI
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xEF
        call amd64_emit_byte

    ; ---- CET (Control-Flow Enforcement Technology) ----
    ELSEIF ax, e, 1602             ; RDSSPD
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1E
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 1
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1603             ; RDSSPQ
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x48
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1E
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 1
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1279             ; INCSSPD
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 5
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1280             ; INCSSPQ
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x48
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 5
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1627             ; SAVEPREVSSP
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xEA
        call amd64_emit_byte
    ELSEIF ax, e, 1622             ; RSTORSSP
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov al, 5
        mov rdi, r10
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1636             ; SETSSBSY
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xE8
        call amd64_emit_byte
    ELSEIF ax, e, 1070             ; CLRSSBSY
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov al, 0xE9
        call amd64_emit_byte

    ; ----Intel MPX (Memory Protection Extensions) ----
    ELSEIF_RANGE ax, 1043, 1049    ; BNDCL - BNDSTX
        call amd64_encode_mpx

    ; ----Hardware Sign-Extension & Type Conversion ----
    ELSEIF ax, e, 1060             ; CBW
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x98
        call amd64_emit_byte
    ELSEIF ax, e, 1115             ; CWDE
        mov     al, 0x98
        call amd64_emit_byte
    ELSEIF ax, e, 1062             ; CDQE
        mov     al, 0x48
        call amd64_emit_byte
        mov al, 0x98
        call amd64_emit_byte
    ELSEIF ax, e, 1114             ; CWD
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x99
        call amd64_emit_byte
    ELSEIF ax, e, 1061             ; CDQ
        mov     al, 0x99
        call amd64_emit_byte
    ELSEIF ax, e, 1090             ; CQO
        mov     al, 0x48
        call amd64_emit_byte
        mov al, 0x99
        call amd64_emit_byte
    ELSEIF ax, e, 2155             ; XLAT
        mov     al, 0xD7
        call    amd64_emit_byte
    ELSEIF ax, e, 2156             ; XLATB
        mov     al, 0xD7
        call    amd64_emit_byte
    ELSEIF ax, e, 6532             ; RETF
        call    amd64_encode_retf
    ELSEIF ax, e, 6533             ; RETFQ
        mov     al, 0x48
        call    amd64_emit_byte
        call    amd64_encode_retf
    ELSEIF ax, e, 6534             ; RETN
        call    amd64_encode_ret

    ; ----Legacy Bit Scanning & Byte Swapping ----
    ELSEIF ax, e, 1051             ; BSF
        mov     r13, 0x0FBC
        call amd64_encode_rm_r
    ELSEIF ax, e, 1052             ; BSR
        mov     r13, 0x0FBD
        call amd64_encode_rm_r
    ELSEIF ax, e, 1053             ; BSWAP
        lea     r10, [r12 + INST_op0]
        mov     al, [r10 + OPERAND_size]
        xor     rsi, rsi
        mov     rdx, r10           ; register lives in the opcode, so REX.B
        call    amd64_emit_prefixes
        mov     al, 0x0F
        call    amd64_emit_byte
        lea     r10, [r12 + INST_op0]  ; the calls above clobber r10
        mov     al, [r10 + OPERAND_reg]
        and     al, 7
        add     al, 0xC8
        call    amd64_emit_byte

    ; ---- Phase 8.6: 1980s BCD Legacy Suite ----
    ELSEIF ax, e, 1000             ; AAA
        mov     al, 0x37
        call amd64_emit_byte
    ELSEIF ax, e, 1001             ; AAD
        mov     al, 0xD5
        call amd64_emit_byte
        mov al, 0x0A
        call amd64_emit_byte
    ELSEIF ax, e, 1002             ; AAM
        mov     al, 0xD4
        call amd64_emit_byte
        mov al, 0x0A
        call amd64_emit_byte
    ELSEIF ax, e, 1003             ; AAS
        mov     al, 0x3F
        call amd64_emit_byte
    ELSEIF ax, e, 1116             ; DAA
        mov     al, 0x27
        call amd64_emit_byte
    ELSEIF ax, e, 1117             ; DAS
        mov     al, 0x2F
        call amd64_emit_byte

    ELSEIF ax, e, 1680             ; SWAPGS
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x01
        call amd64_emit_byte
        mov     al, 0xF8
        call amd64_emit_byte
    ELSEIF ax, e, 1351             ; LAR
        mov     r13, 0x0F02
        call amd64_encode_rm_r
    ELSEIF ax, e, 1377             ; LSL
        mov     r13, 0x0F03
        call amd64_encode_rm_r
    ELSEIF ax, e, 1534             ; POP
        call    amd64_encode_pop
    ELSEIF ax, e, 1298             ; JMP
        mov     r13, 0xE9          ; rel32 JMP
        call    amd64_encode_branch
    ELSEIF ax, e, 1059             ; CALL
        mov     r13, 0xE8
        call    amd64_encode_branch
    ELSEIF ax, e, 1611             ; RET
        call    amd64_encode_ret
    ELSEIF_RANGE ax, 4016, 4031    ; SETcc
        call    amd64_encode_setcc
    ELSEIF_RANGE ax, 4000, 4015    ; CMOVcc
        call    amd64_encode_cmovcc
    ELSEIF ax, e, 1168             ; ENTER
        call    amd64_encode_enter
    ELSEIF ax, e, 1357             ; LEAVE
        mov     al, 0xC9
        call    amd64_emit_byte
    ELSEIF ax, e, 1373             ; LOOP: rel8 only, like jmp short
        mov     r13d, 0xE2
        xor     edi, edi                   ; (the count: "loop l, ecx")
        call    .count_branch
    ELSEIF_RANGE ax, 6524, 6525    ; LOOPE / LOOPZ
        mov     r13d, 0xE1
        xor     edi, edi
        call    .count_branch
    ELSEIF_RANGE ax, 6526, 6527    ; LOOPNE / LOOPNZ
        mov     r13d, 0xE0
        xor     edi, edi
        call    .count_branch
    ELSEIF ax, e, 6529             ; JRCXZ
        mov     r13d, 0xE3
        mov     edi, 64
        call    .count_branch
    ELSEIF ax, e, 6528             ; JECXZ
        mov     r13d, 0xE3
        mov     edi, 32
        call    .count_branch
    ELSEIF ax, e, 6536             ; JCXZ
        mov     r13d, 0xE3
        mov     edi, 16
        call    .count_branch
    ELSEIF ax, e, 1685             ; SYSRET
        call    amd64_encode_sysret
    ELSEIF ax, e, 1682             ; SYSCALL
        call    amd64_encode_syscall
    ELSEIF ax, e, 1029             ; ANDN
        mov     r13, 0xF2
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1058             ; BZHI
        mov     r13, 0xF5
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1649             ; SHLX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 1
        call amd64_encode_vex
    ELSEIF ax, e, 1652             ; SHRX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 3
        call amd64_encode_vex
    ELSEIF ax, e, 1626             ; SARX
        mov     r13, 0xF7
        mov r14, 2
        mov r15, 2
        call amd64_encode_vex
    ELSEIF_RANGE ax, 5100, 5106    ; AVX-512 (EVEX)
        IF ax, e, 5100             ; VAESENC
            mov r13, 0xDC
            mov r14, 2
            mov r15, 1
            call amd64_encode_evex
        ELSEIF ax, e, 5101         ; VAESDEC
            mov r13, 0xDE
            mov r14, 2
            mov r15, 1
            call amd64_encode_evex
        ELSEIF ax, e, 5104         ; VPCLMULQDQ
            mov r13, 0x44
            mov r14, 3
            mov r15, 1
            call amd64_encode_evex
        ELSEIF ax, e, 5105         ; VMOVDQA64
            mov r13, 0x6F
            lea r10, [r12 + INST_op0]
            IF byte [r10 + OPERAND_kind], e, OP_MEM
                mov r13, 0x7F      ; Store form
                ENDIF
            mov r14, 1
            mov r15, 1
            call amd64_encode_evex
        ELSEIF ax, e, 5106         ; VADDPD
            mov r13, 0x58
            mov r14, 1
            mov r15, 1
            call amd64_encode_evex
            ENDIF
    ELSEIF ax, e, 1440             ; NOP
        mov     al, 0x90
        call amd64_emit_byte
    ELSEIF ax, e, 2151             ; XBEGIN rel16/32: a branch's target
        call    amd64_encode_xbegin
    ELSEIF ax, e, 1069             ; CLI
        mov     al, 0xFA
        call    amd64_emit_byte
    ELSEIF ax, e, 1666             ; STI
        mov     al, 0xFB
        call    amd64_emit_byte
    ELSEIF ax, e, 1065             ; CLD
        mov     al, 0xFC
        call    amd64_emit_byte
    ELSEIF ax, e, 1665             ; STD
        mov     al, 0xFD
        call    amd64_emit_byte
    ELSEIF ax, e, 1205             ; FLD1
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xE8
        call amd64_emit_byte
    ELSEIF ax, e, 1206             ; FLDZ
        mov     al, 0xD9
        call amd64_emit_byte
        mov al, 0xEE
        call amd64_emit_byte
    ELSEIF ax, e, 1542             ; PREFETCH
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, 0x18
        call amd64_emit_byte
        mov     al, 1
        mov rdi, r10
        call amd64_emit_modrm_sib ; PREFETCHT0
    ELSEIF ax, e, 1073             ; CLWB
        mov     al, 0x66
        call amd64_emit_byte
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, 0xAE
        call amd64_emit_byte
        mov     al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
        ELSE
            jmp     .error
        ENDIF
    
    ; Preserve the error codes a helper may return, and clear RAX otherwise.
    ; This is an allowlist rather than "any non-zero is an error" because the
    ; emit helpers preserve RAX, so a helper that returns without setting it
    ; hands back the caller's stale value. Any new error code a helper can
    ; return has to be added here or it is silently reported as success.
    cmp     rax, EXIT_ENCODE_FAIL
    je      .done
    cmp     rax, EXIT_RELOC_ERROR
    je      .done
    cmp     rax, EXIT_INVALID_OPERAND
    je      .done
    cmp     rax, EXIT_BITS_MODE            ; (amd64_count_size)
    je      .done
    cmp     rax, EXIT_EA_SIZE_MIX          ; ("a16 jecxz l", amd64_count_size)
    je      .done
.encoded:
    ; pcommit: Intel withdrew it before any CPU had it (NASM's warning)
    cmp     word [r12 + INST_op_id], 7123  ; PCOMMIT
    jne     .not_pcommit
    mov     edi, WC_OBSOLETE_NOP
    lea     rsi, [rel s_obs_nop]
    call    amd64_warn_class
.not_pcommit:
    cmp     byte [rel imm_ph_active], 0
    je      .no_placeholder
    call    amd64_imm_fixup
    test    rax, rax
    jnz     .done
.no_placeholder:
    call    amd64_fix_rip_addend   ; the instruction is complete now
    ; outside 64-bit mode an instruction that needed a REX prefix does not
    ; exist (mode.s)
    extern  amd64_rex_scan
    call    amd64_rex_scan
    test    rax, rax
    jnz     .done
    ; {rex} on an encoding with none (the table's put one itself)
    test    byte [r12 + INST_flags], INSTF_REX
    jz      .osize
    extern  amd64_force_rex
    call    amd64_force_rex
    test    rax, rax
    jnz     .done
    jmp     .osize
.mode_encoded:
    xor     eax, eax
.osize:
    call    amd64_obsolete                 ; (the instruction is encoded)
    call    amd64_gas_got
    call    amd64_cpu_forms
    test    eax, eax
    jnz     .done
    ; o16 / o32 / o64: the operation size's prefix (mode.s)
    cmp     byte [r12 + INST_osize], 0
    je      .done
    extern  amd64_force_osize
    call    amd64_force_osize
.done:
    ; APX's REX2: its map, or the error of r16-r31 it cannot carry; then
    ; the prefixes in the order of the syntax's assembler (mode.s)
    test    rax, rax
    jnz     .ordered
    ; {evex} asked for and none written ("{evex} add rax, rbx": APX's
    ; form, not encoded yet) - an error, not the legacy bytes
    test    byte [r12 + INST_flags], INSTF_EVEX
    jz      .evex_ok
    call    amd64_has_evex
    jz      .evex_ok
    mov     eax, EXIT_ENCODE_FAIL
    jmp     .ordered
.evex_ok:
    extern  amd64_rex2_finish
    call    amd64_rex2_finish
    test    eax, eax
    jnz     .ordered
    extern  amd64_prefix_order
    call    amd64_prefix_order
.ordered:
    ; an error found deep in the encoders, which return as any call does:
    ; a relocation ("[x wrt ..gotoff]" in ELF64), an address with no
    ; encoding (amd64_emit_modrm_sib), past 15 bytes (amd64_emit_byte)
    mov     ecx, [rel amd64_reloc_err]
    test    ecx, ecx
    jz      .done_ret
    mov     dword [rel amd64_reloc_err], 0
    test    rax, rax
    jnz     .done_ret
    mov     eax, ecx
.done_ret:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    mov     rax, EXIT_ENCODE_FAIL
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; .count_branch: a branch on the count register (loop, jcxz, ...): the
; address size it works with (amd64_count_size, edi), then E0-E3 rel8 (r13)
.count_branch:
    extern  amd64_count_size
    call    amd64_count_size
    test    rax, rax
    jnz     .count_ret
    call    amd64_encode_branch_short
.count_ret:
    ret

; the rest is in src/encode/x86/encoder/, in this order:
%include "src/encode/x86/encoder/support.inc"
%include "src/encode/x86/encoder/mov_arith.inc"
%include "src/encode/x86/encoder/general.inc"
%include "src/encode/x86/encoder/vex_evex.inc"
%include "src/encode/x86/encoder/branch.inc"
%include "src/encode/x86/encoder/emit.inc"
%include "src/encode/x86/encoder/jmp_call.inc"
%include "src/encode/x86/encoder/sse_avx.inc"
