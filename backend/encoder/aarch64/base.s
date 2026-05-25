;
; ============================================================================
; File        : src/encoder/aarch64.s
; Project     : utasm
; Description : AArch64 instruction encoder. Encodes parsed INST structs
;                into 32-bit fixed-width AArch64 machine code words.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
%include "include/arch/aarch64.s"

[SECTION .text]

; ---- aarch64_encode_instruction ----
; Main entry point for AArch64 encoding.
; Input    : r12 = pointer to INST struct
; Output   : rax = EXIT_OK or error code
global aarch64_encode_instruction
aarch64_encode_instruction:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; RBX = AsmCtx
    mov     r12, rsi               ; R12 = INST struct
    
    movzx   eax, word [r12 + INST_op_id]
    
    ; ---- Data Processing (Register) ----
    IF eax, e, ID_AARCH64_ADD
        mov     r13d, 0x0B000000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_SUB
        mov     r13d, 0x4B000000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_AND
        mov     r13d, 0x0A200000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_ORR
        mov     r13d, 0x2A200000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_BIC
        mov     r13d, 0x8A200000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_ORN
        mov     r13d, 0xAA200000
        call    aarch64_encode_dp_reg
    ELSEIF eax, e, ID_AARCH64_EON
        mov     r13d, 0xCA200000
        call    aarch64_encode_dp_reg

    ; ---- String Operations (AMD64 Parity) ----
    ELSEIF eax, ge, ID_AARCH64_MOVSB
        IF eax, le, ID_AARCH64_MOVSQ
            call    aarch64_encode_string_mov
            ENDIF
    ELSEIF eax, ge, ID_AARCH64_STOSB
        IF eax, le, ID_AARCH64_STOSQ
            call    aarch64_encode_string_sto
            ENDIF

    ; ---- Type Conversion & Bit Reversal ----
    ELSEIF eax, e, ID_AARCH64_REV
        call    aarch64_encode_rev
    ELSEIF eax, ge, ID_AARCH64_SXTB
        IF eax, le, ID_AARCH64_SXTW
            call    aarch64_encode_extend
            ENDIF

    ; ---- System & Barrier Instructions ----
    ELSEIF eax, e, ID_AARCH64_SVC
        call    aarch64_encode_svc
    ELSEIF eax, ge, ID_AARCH64_MRS         ; MRS/MSR range
        IF eax, le, ID_AARCH64_MSR
            call    aarch64_encode_system_reg
            ENDIF
    ELSEIF eax, e, ID_AARCH64_DSB
        mov     edi, 0xD503309F
        call    aarch64_emit_word
    ELSEIF eax, e, ID_AARCH64_DMB
        mov     edi, 0xD50330BF
        call    aarch64_emit_word
    ELSEIF eax, e, ID_AARCH64_ISB
        mov     edi, 0xD5033FDF
        call    aarch64_emit_word
    ELSEIF eax, e, ID_AARCH64_WFI
        mov     edi, 0xD503205F
        call    aarch64_emit_word
    ELSEIF eax, e, ID_AARCH64_HLT
        call    aarch64_encode_hlt

    ; ---- Floating Point (Basic) ----
    ELSEIF eax, ge, 2154            ; FADD, FSUB, FMUL, FDIV
        IF eax, le, 2165
            call    aarch64_encode_fp_bin
            ENDIF

    ; ---- Movement ----
    ELSEIF eax, e, ID_AARCH64_MOV
        call    aarch64_encode_mov
    ELSEIF eax, e, ID_AARCH64_MOVZ
        mov     r13d, 0xD2800000
        call    aarch64_encode_mov_wide
    ELSEIF eax, e, ID_AARCH64_MOVN
        mov     r13d, 0x92800000
        call    aarch64_encode_mov_wide
    ELSEIF eax, e, ID_AARCH64_MOVK
        mov     r13d, 0xF2800000
        call    aarch64_encode_mov_wide

    ; ---- Comparison ----
    ELSEIF eax, e, ID_AARCH64_CMP
        call    aarch64_encode_cmp
    ELSEIF eax, e, ID_AARCH64_TST
        call    aarch64_encode_tst

    ; ---- Branches ----
    ELSEIF eax, e, ID_AARCH64_B
        call    aarch64_encode_branch
    ELSEIF eax, e, ID_AARCH64_BL
        mov     r13d, 0x94000000
        call    aarch64_encode_branch_link
    ELSEIF eax, e, ID_AARCH64_BR
        mov     r13d, 0xD61F0000
        call    aarch64_encode_branch_reg
    ELSEIF eax, e, ID_AARCH64_BLR
        mov     r13d, 0xD63F0000
        call    aarch64_encode_branch_reg
    ELSEIF eax, e, ID_AARCH64_RET
        call    aarch64_encode_ret
    ELSEIF eax, e, ID_AARCH64_CBZ
        mov     r13d, 0x34000000
        call    aarch64_encode_comp_branch
    ELSEIF eax, e, ID_AARCH64_CBNZ
        mov     r13d, 0x35000000
        call    aarch64_encode_comp_branch
    ELSEIF eax, ge, ID_AARCH64_BEQ
        IF eax, le, ID_AARCH64_BNV
            call    aarch64_encode_jcc
            ENDIF

    ; ---- Load / Store ----
    ELSEIF eax, e, ID_AARCH64_LDR
        call    aarch64_encode_ldr
    ELSEIF eax, e, ID_AARCH64_STR
        call    aarch64_encode_str
    ELSEIF eax, e, ID_AARCH64_LDP
        mov     r13d, 1
        call    aarch64_encode_ldst_pair
    ELSEIF eax, e, ID_AARCH64_STP
        mov     r13d, 0
        call    aarch64_encode_ldst_pair

    ; ---- SIMD (NEON) ----
    ELSEIF eax, ge, ID_AARCH64_ADD_V
        IF eax, le, ID_AARCH64_EOR_V
            call    aarch64_encode_vector_bin
            ENDIF
    
    ; ---- Misc ----
    ELSEIF eax, e, ID_AARCH64_NOP
        mov     edi, 0xD503201F
        call    aarch64_emit_word
    ELSE
        mov     rax, EXIT_ENCODE_FAIL
        jmp     .done
    ENDIF

    xor     rax, rax
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- aarch64_encode_dp_reg ----
aarch64_encode_dp_reg:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    mov     eax, r13d
    
    ; sf bit (bit 31)
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0x80000000
        ENDIF
        
    ; Rd (bits 4-0)
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    
    ; Rn (bits 9-5)
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    
    ; Rm (bits 20-16)
    movzx   edi, byte [r9 + OPERAND_reg]
    shl     edi, 16
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_mov ----
aarch64_encode_mov:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    IF byte [r11 + OPERAND_kind], e, OP_REG
        ; MOV Rd, Rn -> ORR Rd, ZR, Rn
        mov     r13d, 0x2A0003E0
        call    aarch64_encode_dp_reg
    ELSE
        ; MOV Rd, #imm -> MOVZ Rd, #imm
        mov     r13d, 0xD2800000
        call    aarch64_encode_mov_wide
        ENDIF
    epilogue

; ---- aarch64_encode_mov_wide ----
aarch64_encode_mov_wide:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     eax, r13d
    
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0x80000000
        ENDIF
        
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    
    mov     edi, [r11 + OPERAND_imm]
    and     edi, 0xFFFF
    shl     edi, 5
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_ldr / aarch64_encode_str ----
aarch64_encode_ldr:
    mov     r13d, 0x38400000
    jmp     aarch64_encode_ldst_common
aarch64_encode_str:
    mov     r13d, 0x38000000
aarch64_encode_ldst_common:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     eax, r13d
    
    ; Size (bits 31-30)
    movzx   ecx, byte [r10 + OPERAND_size]
    IF ecx, e, 8
        or      eax, 0xC0000000
    ELSEIF ecx, e, 4
        or      eax, 0x80000000
    ELSEIF ecx, e, 2
        or      eax, 0x40000000
        ENDIF
        
    ; Rt (bits 4-0)
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    
    ; Rn (bits 9-5)
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    
    ; imm12 (bits 21-10) - simplified for now
    mov     edi, [r11 + OPERAND_imm]
    and     edi, 0xFFF
    shl     edi, 10
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_ldst_pair ----
aarch64_encode_ldst_pair:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    mov     eax, 0x28000000
    IF r13d, e, 1
        or      eax, 0x00400000    ; L bit
        ENDIF
        
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0x80000000
        ENDIF
        
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 10
    or      eax, edi
    movzx   edi, byte [r9 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_branch ----
aarch64_encode_branch:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     eax, 0x14000000
    mov     ecx, [r10 + OPERAND_imm]
    shr     ecx, 2
    and     ecx, 0x03FFFFFF
    or      eax, ecx
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_branch_link ----
aarch64_encode_branch_link:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     eax, 0x94000000
    mov     ecx, [r10 + OPERAND_imm]
    shr     ecx, 2
    and     ecx, 0x03FFFFFF
    or      eax, ecx
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_branch_reg ----
aarch64_encode_branch_reg:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     eax, r13d
    movzx   ecx, byte [r10 + OPERAND_reg]
    shl     ecx, 5
    or      eax, ecx
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_ret ----
aarch64_encode_ret:
    prologue
    mov     edi, 0xD65F03C0
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_jcc ----
aarch64_encode_jcc:
    prologue
    lea     r10, [r12 + INST_op0]
    movzx   eax, word [r12 + INST_op_id]
    sub     eax, ID_AARCH64_BEQ    ; 0 for EQ, 1 for NE, etc.
    and     eax, 0xF
    or      eax, 0x54000000
    
    mov     ecx, [r10 + OPERAND_imm]
    shr     ecx, 2
    and     ecx, 0x7FFFF
    shl     ecx, 5
    or      eax, ecx
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_comp_branch ----
aarch64_encode_comp_branch:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     eax, r13d
    
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0x80000000
        ENDIF
        
    movzx   ecx, byte [r10 + OPERAND_reg]
    or      eax, ecx
    
    mov     ecx, [r11 + OPERAND_imm]
    shr     ecx, 2
    and     ecx, 0x7FFFF
    shl     ecx, 5
    or      eax, ecx
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_rev ----
aarch64_encode_rev:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     eax, 0x5AC00800
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0xC0000400    ; sf=1, opc=11
        ENDIF
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_extend ----
aarch64_encode_extend:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     eax, 0x13000000        ; SBFM base
    
    IF byte [r10 + OPERAND_size], e, 8
        or      eax, 0x80400000    ; sf=1, N=1
        ENDIF
        
    movzx   ecx, byte [r10 + OPERAND_reg]
    or      eax, ecx
    movzx   ecx, byte [r11 + OPERAND_reg]
    shl     ecx, 5
    or      eax, ecx
    
    movzx   ecx, word [r12 + INST_op_id]
    IF ecx, e, ID_AARCH64_SXTB
        or      eax, (7 << 10)     ; imms=7
    ELSEIF ecx, e, ID_AARCH64_SXTH
        or      eax, (15 << 10)    ; imms=15
    ELSEIF ecx, e, ID_AARCH64_SXTW
        or      eax, (31 << 10)    ; imms=31
        ENDIF
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_system_reg ----
aarch64_encode_system_reg:
    prologue
    ; Simplified for now
    mov     edi, 0xD503201F
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_svc / aarch64_encode_hlt ----
aarch64_encode_svc:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     eax, 0xD4000001
    mov     ecx, [r10 + OPERAND_imm]
    and     ecx, 0xFFFF
    shl     ecx, 5
    or      eax, ecx
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

aarch64_encode_hlt:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     eax, 0xD4400000
    mov     ecx, [r10 + OPERAND_imm]
    and     ecx, 0xFFFF
    shl     ecx, 5
    or      eax, ecx
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_fp_bin ----
aarch64_encode_fp_bin:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    mov     eax, 0x1E200800        ; FADD base
    
    ; Simplified: Rd, Rn, Rm
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    movzx   edi, byte [r9 + OPERAND_reg]
    shl     edi, 16
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- aarch64_encode_vector_bin ----
aarch64_encode_vector_bin:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    movzx   ecx, word [r12 + INST_op_id]
    
    IF ecx, e, ID_AARCH64_AND_V
        mov eax, 0x0E201C00
    ELSEIF ecx, e, ID_AARCH64_ORR_V
        mov eax, 0x0EA01C00
    ELSEIF ecx, e, ID_AARCH64_EOR_V
        mov eax, 0x2E201C00
    ELSEIF ecx, e, ID_AARCH64_ADD_V
        mov eax, 0x0E208400
    ELSEIF ecx, e, ID_AARCH64_SUB_V
        mov eax, 0x2E208400
    ELSE
        mov eax, 0x0E201C00        ; Default
        ENDIF
    
    ; Q bit (bit 30)
    IF byte [r10 + OPERAND_size], e, 16
        or      eax, 0x40000000
        ENDIF
        
    ; Rd, Rn, Rm
    movzx   edi, byte [r10 + OPERAND_reg]
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 5
    or      eax, edi
    movzx   edi, byte [r9 + OPERAND_reg]
    shl     edi, 16
    or      eax, edi
    
    mov     edi, eax
    call    aarch64_emit_word
    epilogue

; ---- string operations placeholders ----
aarch64_encode_string_mov:
    prologue
    ; Emulate with loop
    epilogue
aarch64_encode_string_sto:
    prologue
    epilogue

; ---- cmp/tst placeholders ----
aarch64_encode_cmp:
    prologue
    ; SUBS ZR, Rn, Rm
    mov     r13d, 0x6B00001F
    call    aarch64_encode_dp_reg
    epilogue
aarch64_encode_tst:
    prologue
    ; ANDS ZR, Rn, Rm
    mov     r13d, 0x6A00001F
    call    aarch64_encode_dp_reg
    epilogue

; ---- aarch64_emit_word ----
aarch64_emit_word:
    prologue
    ; EDI contains the 32-bit instruction
    mov     rsi, rdi
    mov     rdi, rbx               ; Pass AsmCtx
    extern  asm_ctx_emit_dword
    call    asm_ctx_emit_dword
    epilogue
