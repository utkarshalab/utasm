;
; ============================================================================
; File        : src/encoder/riscv64.s
; Project     : utasm
; Description : RISC-V 64-bit instruction encoder.
;                Implementation mirrors the scale and robustness of amd64.s.
;                Supports RV64IM base and extensions.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
%include "include/arch/riscv64.s"

[SECTION .text]

; ============================================================================
; riscv64_encode_instruction
; ============================================================================
;
; riscv64_encode_instruction
; Top-level dispatcher for RISC-V 64 encoding.

; Input  : rdi = AsmCtx*
;           rsi = INST*
; Output : rax = EXIT_OK or EXIT_ENCODE_FAIL
;
global riscv64_encode_instruction
riscv64_encode_instruction:
    prologue
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi               ; RBX = AsmCtx
    mov     r12, rsi               ; R12 = INST*

    ; A96: Dispatch Integrity - Validate operand count
    IF byte [r12 + INST_nops], g, 4
        mov rax, EXIT_ENCODE_FAIL
        jmp .done
        ENDIF

    ; Reset length counter (RISC-V 32-bit instructions)
    mov     dword [rbx + ASMCTX_inst_len], 4

    ; 0. VALIDATION: Check operand size consistency (A87: Hardened)
    movzx   ecx, byte [r12 + INST_nops]
    IF ecx, ge, 2
        lea     r10, [r12 + INST_op0]
        lea     r11, [r12 + INST_op1]
        mov     al, [r10 + OPERAND_size]
        mov     dl, [r11 + OPERAND_size]
        IF al, ne, 0
        IF dl, ne, 0
            IF al, ne, dl
                ; Exceptions: Immediate/Symbol can vary
                IF byte [r11 + OPERAND_kind], ne, OP_IMM
                IF byte [r11 + OPERAND_kind], ne, OP_SYMBOL
                    mov rax, EXIT_INVALID_OPERAND
                    jmp .done
                    ENDIF
                    ENDIF
                    ENDIF
                    ENDIF
                    ENDIF

    movzx   eax, word [r12 + INST_op_id]

    ; ---- R-Type (Arithmetic) ----
    IF eax, e, ID_RV_ADD
        mov     r13d, 0x00000033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SUB
        mov     r13d, 0x40000033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SLL
        mov     r13d, 0x00001033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SLT
        mov     r13d, 0x00002033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SLTU
        mov     r13d, 0x00003033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_XOR
        mov     r13d, 0x00004033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SRL
        mov     r13d, 0x00005033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_SRA
        mov     r13d, 0x40005033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_OR
        mov     r13d, 0x00006033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_AND
        mov     r13d, 0x00007033
        call riscv64_encode_r_type

    ; ---- R-Type (RV64M Extensions) ----
    ELSEIF eax, e, ID_RV_MUL
        mov     r13d, 0x02000033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_MULH
        mov     r13d, 0x02001033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_MULHSU
        mov     r13d, 0x02002033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_MULHU
        mov     r13d, 0x02003033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_DIV
        mov     r13d, 0x02004033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_DIVU
        mov     r13d, 0x02005033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_REM
        mov     r13d, 0x02006033
        call riscv64_encode_r_type
    ELSEIF eax, e, ID_RV_REMU
        mov     r13d, 0x02007033
        call riscv64_encode_r_type

    ; ---- I-Type (Immediate Arithmetic) ----
    ELSEIF eax, e, ID_RV_ADDI
        mov     r13d, 0x00000013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_SLTI
        mov     r13d, 0x00002013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_SLTIU
        mov     r13d, 0x00003013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_XORI
        mov     r13d, 0x00004013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_ORI
        mov     r13d, 0x00006013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_ANDI
        mov     r13d, 0x00007013
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_SLLI
        mov     r13d, 0x00001013
        call riscv64_encode_i_shift
    ELSEIF eax, e, ID_RV_SRLI
        mov     r13d, 0x00005013
        call riscv64_encode_i_shift
    ELSEIF eax, e, ID_RV_SRAI
        mov     r13d, 0x40005013
        call riscv64_encode_i_shift

    ; ---- I-Type (Loads) ----
    ELSEIF eax, e, ID_RV_LB
        mov     r13d, 0x00000003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LH
        mov     r13d, 0x00001003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LW
        mov     r13d, 0x00002003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LD
        mov     r13d, 0x00003003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LBU
        mov     r13d, 0x00004003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LHU
        mov     r13d, 0x00005003
        call riscv64_encode_i_type
    ELSEIF eax, e, ID_RV_LWU
        mov     r13d, 0x00006003
        call riscv64_encode_i_type

    ; ---- S-Type (Stores) ----
    ELSEIF eax, e, ID_RV_SB
        mov     r13d, 0x00000023
        call riscv64_encode_s_type
    ELSEIF eax, e, ID_RV_SH
        mov     r13d, 0x00001023
        call riscv64_encode_s_type
    ELSEIF eax, e, ID_RV_SW
        mov     r13d, 0x00002023
        call riscv64_encode_s_type
    ELSEIF eax, e, ID_RV_SD
        mov     r13d, 0x00003023
        call riscv64_encode_s_type

    ; ---- B-Type (Branches) ----
    ELSEIF eax, e, ID_RV_BEQ
        mov     r13d, 0x00000063
        call riscv64_encode_b_type
    ELSEIF eax, e, ID_RV_BNE
        mov     r13d, 0x00001063
        call riscv64_encode_b_type
    ELSEIF eax, e, ID_RV_BLT
        mov     r13d, 0x00004063
        call riscv64_encode_b_type
    ELSEIF eax, e, ID_RV_BGE
        mov     r13d, 0x00005063
        call riscv64_encode_b_type
    ELSEIF eax, e, ID_RV_BLTU
        mov     r13d, 0x00006063
        call riscv64_encode_b_type
    ELSEIF eax, e, ID_RV_BGEU
        mov     r13d, 0x00007063
        call riscv64_encode_b_type

    ; ---- U-Type ----
    ELSEIF eax, e, ID_RV_LUI
        mov     r13d, 0x00000037
        call riscv64_encode_u_type
    ELSEIF eax, e, ID_RV_AUIPC
        mov     r13d, 0x00000017
        call riscv64_encode_u_type

    ; ---- J-Type ----
    ELSEIF eax, e, ID_RV_JAL
        call    riscv64_encode_j_type
    ELSEIF eax, e, ID_RV_JALR
        call    riscv64_encode_jalr

    ; ---- String Operations (AMD64 Parity) ----
    ELSEIF eax, ge, ID_RV_MOVSB
        IF eax, le, ID_RV_MOVSQ
            call riscv64_encode_string_mov
            ENDIF
    ELSEIF eax, ge, ID_RV_STOSB
        IF eax, le, ID_RV_STOSQ
            call riscv64_encode_string_sto
            ENDIF

    ; ---- Type Conversion & Bit Reversal ----
    ELSEIF eax, e, ID_RV_REV8
        call    riscv64_encode_rev8
    ELSEIF eax, ge, ID_RV_SEXTB
        IF eax, le, ID_RV_SEXTH
            call riscv64_encode_extend
            ENDIF

    ; ---- Privileged & CSR Instructions ----
    ELSEIF eax, ge, 3084            ; CSR range (CSRC to CSRWI)
        IF eax, le, 3096
            call riscv64_encode_csr
            ENDIF
    ELSEIF eax, e, 3121             ; ECALL
        mov     edi, 0x00000073
        call riscv64_emit_word
    ELSEIF eax, e, 3122             ; EBREAK
        mov     edi, 0x00100073
        call riscv64_emit_word
    ELSEIF eax, e, 3244             ; MRET
        mov     edi, 0x30200073
        call riscv64_emit_word
    ELSEIF eax, e, 3332             ; SRET
        mov     edi, 0x10200073
        call riscv64_emit_word

    ; ---- Memory Barriers ----
    ELSEIF eax, e, 3123             ; FENCE
        call    riscv64_encode_fence
    ELSEIF eax, e, 3124             ; FENCE.I
        mov     edi, 0x0000100F
        call riscv64_emit_word

    ; ---- Atomic Memory Operations (AMO) ----
    ELSEIF eax, ge, ID_RV_AMOADD_W
        IF eax, le, ID_RV_SC_D
            call    riscv64_encode_atomic
            ENDIF
            ENDIF
    ; ---- Floating Point (Basic RV64F/D) ----
    ELSEIF eax, ge, 3128            ; FADD.S range
        IF eax, le, 3180
            call riscv64_encode_fp
            ENDIF

    ; ---- Pseudo Instructions ----
    ELSEIF eax, e, ID_RV_CALL
        mov     r13d, 1
        call riscv64_encode_pseudo_call
    ELSEIF eax, e, ID_RV_TAIL
        mov     r13d, 0
        call riscv64_encode_pseudo_call
    ELSEIF eax, e, ID_RV_LI
        call    riscv64_encode_li
    ELSEIF eax, e, ID_RVC_NOP
        mov     dword [rbx + ASMCTX_inst_len], 2
        mov     edi, 0x0001
        call    riscv64_emit_half
    ELSEIF eax, e, ID_RVC_MV
        mov     dword [rbx + ASMCTX_inst_len], 2
        call    riscv64_encode_rvc_mv
    ELSEIF eax, e, ID_RVC_ADDI
        mov     dword [rbx + ASMCTX_inst_len], 2
        call    riscv64_encode_rvc_addi
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

; ============================================================================
; Internal Helpers & Encoders
; ============================================================================

riscv64_emit_word:
    prologue
    mov     rsi, rdi               ; instruction word -> RSI
    mov     rdi, rbx               ; AsmCtx -> RDI
    extern  asm_ctx_emit_dword
    call    asm_ctx_emit_dword
    epilogue

; ---- R-Type ----
; funct7
; rs2
; rs1
; funct3
; rd
; opcode
riscv64_encode_r_type:
    prologue
    lea     r10, [r12 + INST_op0]  ; rd
    lea     r11, [r12 + INST_op1]  ; rs1
    lea     r9,  [r12 + INST_op2]  ; rs2
    
    mov     eax, r13d
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    movzx   edi, byte [r9 + OPERAND_reg]
    shl     edi, 20
    or      eax, edi
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- I-Type ----
; Format: imm[11:0]
; rs1
; funct3
; rd
; opcode
riscv64_encode_i_type:
    prologue
    lea     r10, [r12 + INST_op0]  ; rd
    lea     r11, [r12 + INST_op1]  ; rs1 (or mem base)
    
    mov     eax, r13d
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    
    IF byte [r11 + OPERAND_kind], e, OP_MEM
        movzx   edi, byte [r11 + OPERAND_base]
        shl     edi, 15
        or      eax, edi
        mov     edi, [r11 + OPERAND_imm]
        
        ; Record relocation if symbol is present (A75)
        IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
            push    rax
            push    rdi
            mov     rdi, rbx               ; AsmCtx
            mov     rsi, [r12 + INST_offset]
            mov     rdx, [r11 + OPERAND_sym]
            mov     rcx, [r11 + OPERAND_imm] ; addend
            mov     r8, R_RISCV_PCREL_LO12_I
            extern  reloc_record
            call    reloc_record
            pop     rdi
            pop     rax
            ENDIF
            ELSE
        movzx   edi, byte [r11 + OPERAND_reg]
        shl     edi, 15
        or      eax, edi
        lea     r9, [r12 + INST_op2]
        mov     edi, [r9 + OPERAND_imm]
        
        ; Record relocation for ADDI-style if symbol is present (A75)
        IF byte [r9 + OPERAND_kind], e, OP_SYMBOL
            push    rax
            push    rdi
            mov     rdi, rbx
            mov     rsi, [r12 + INST_offset]
            mov     rdx, [r9 + OPERAND_sym]
            mov     rcx, [r9 + OPERAND_imm]
            mov     r8, R_RISCV_PCREL_LO12_I
            call    reloc_record
            pop     rdi
            pop     rax
            ENDIF
            ENDIF
    
    and     edi, 0xFFF
    shl     edi, 20
    or      eax, edi
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- I-Shift Type ----
; SLLI, SRLI, SRAI (imm is 6-bit for RV64)
riscv64_encode_i_shift:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    mov     eax, r13d
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    
    mov     edi, [r9 + OPERAND_imm]
    IF edi, g, 63
        mov rax, EXIT_IMM_RANGE
        jmp .done
        ENDIF
    and     edi, 0x3F              ; 6-bit shift amount
    shl     edi, 20
    or      eax, edi
    
    mov     rdi, rax
    call    riscv64_emit_word
.done:
    epilogue

; ---- S-Type ----
; Format: imm[11:5]
; rs2
; rs1
; funct3
; imm[4:0]
; opcode
riscv64_encode_s_type:
    prologue
    lea     r10, [r12 + INST_op0]  ; rs2 (source)
    lea     r11, [r12 + INST_op1]  ; [rs1, imm]
    
    mov     eax, r13d
    movzx   edi, byte [r11 + OPERAND_base]
    shl     edi, 15
    or      eax, edi
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 20
    or      eax, edi
    
    mov     edi, [r11 + OPERAND_imm]
    
    ; Record relocation if symbol is present (A75)
    IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
        push    rax
        push    rdi
        mov     rdi, rbx               ; AsmCtx
        mov     rsi, [r12 + INST_offset]
        mov     rdx, [r11 + OPERAND_sym]
        mov     rcx, [r11 + OPERAND_imm] ; addend
        mov     r8, R_RISCV_PCREL_LO12_S
        extern  reloc_record
        call    reloc_record
        pop     rdi
        pop     rax
        ENDIF

    mov     ecx, edi
    and     ecx, 0x1F              ; imm[4:0]
    shl     ecx, 7
    or      eax, ecx
    shr     edi, 5
    and     edi, 0x7F              ; imm[11:5]
    shl     edi, 25
    or      eax, edi
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- B-Type ----
; Format: imm[12]
; imm[10:5]
; rs2
; rs1
; funct3
; imm[4:1]
; imm[11]
; opcode
riscv64_encode_b_type:
    prologue
    lea     r10, [r12 + INST_op0]  ; rs1
    lea     r11, [r12 + INST_op1]  ; rs2
    lea     r9,  [r12 + INST_op2]  ; imm
    
    mov     eax, r13d
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 20
    or      eax, edi
    
    mov     edi, [r9 + OPERAND_imm]
    ; Validation: Check if immediate fits in 13-bit signed (bits 12:1)
    mov     rax, rdi
    sar     rax, 12                ; Keep sign bit if within range
    IF rax, ne, 0
        IF rax, ne, -1
            mov rax, EXIT_INVALID_IMM
            jmp riscv64_encode_instruction.done
        ENDIF
    ENDIF
    
    ; Scramble bits
    mov     ecx, edi
    and     ecx, 0x800             ; imm[11]
    shr     ecx, 4
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x1E              ; imm[4:1]
    shl     ecx, 7
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x7E0             ; imm[10:5]
    shl     ecx, 20
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x1000            ; imm[12]
    shl     ecx, 19
    or      eax, ecx
    
    IF byte [r9 + OPERAND_kind], e, OP_SYMBOL
        push    rax
        mov     rdi, rbx
        mov     rsi, [r12 + INST_offset]
        mov     rdx, [r9 + OPERAND_sym]
        xor     rcx, rcx
        mov     r8, R_RISCV_BRANCH
        extern  reloc_record
        call    reloc_record
        pop     rax
        ENDIF
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- U-Type ----
; Format: imm[31:12]
; rd
; opcode
riscv64_encode_u_type:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     eax, r13d
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    
    mov     edi, [r11 + OPERAND_imm]
    and     edi, 0xFFFFF000
    or      eax, edi
    
    mov     rdi, rax
    call    riscv64_emit_word
    
    IF r13d, e, 0x00000017         ; AUIPC
        IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
            mov     rdi, rbx
            mov     rsi, [r12 + INST_offset]
            mov     rdx, [r11 + OPERAND_sym]
            xor     rcx, rcx
            mov     r8, R_RISCV_HI20
            extern  reloc_record
            call    reloc_record
            ENDIF
            ENDIF
    epilogue

; ---- J-Type (JAL) ----
riscv64_encode_j_type:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     eax, 0x0000006F
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    
    mov     edi, [r11 + OPERAND_imm]
    ; Validation: Check if immediate fits in 21-bit signed (bits 20:1)
    mov     rax, rdi
    sar     rax, 20
    IF rax, ne, 0
        IF rax, ne, -1
            mov rax, EXIT_INVALID_IMM
            jmp riscv64_encode_instruction.done
        ENDIF
    ENDIF
    
    ; Scramble bits
    mov     ecx, edi
    and     ecx, 0xFF000           ; imm[19:12]
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x800             ; imm[11]
    shl     ecx, 9
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x7FE             ; imm[10:1]
    shl     ecx, 20
    or      eax, ecx
    
    mov     ecx, edi
    and     ecx, 0x100000          ; imm[20]
    shl     ecx, 11
    or      eax, ecx
    
    IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
        push    rax
        mov     rdi, rbx
        mov     rsi, [r12 + INST_offset]
        mov     rdx, [r11 + OPERAND_sym]
        xor     rcx, rcx
        mov     r8, R_RISCV_JAL
        call    reloc_record
        pop     rax
        ENDIF
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- JALR ----
riscv64_encode_jalr:
    prologue
    mov     r13d, 0x00000067
    call    riscv64_encode_i_type
    epilogue

; ---- riscv64_encode_string_mov ----
riscv64_encode_string_mov:
    prologue
    ; LB t0, 0(a1)      (0x00058283)
    ; SB t0, 0(a2)      (0x00560023)
    ; ADDI a1, a1, 1    (0x00158593)
    ; ADDI a2, a2, 1    (0x00160613)
    ; ADDI a3, a3, -1   (0xFFF68693)
    ; BNE a3, zero, -12 (0xFE069AE3)
    mov     edi, 0x00058283
    call riscv64_emit_word
    mov     edi, 0x00560023
    call riscv64_emit_word
    mov     edi, 0x00158593
    call riscv64_emit_word
    mov     edi, 0x00160613
    call riscv64_emit_word
    mov     edi, 0xFFF68693
    call riscv64_emit_word
    mov     edi, 0xFE069AE3
    call riscv64_emit_word
    epilogue

; ---- riscv64_encode_string_sto ----
riscv64_encode_string_sto:
    prologue
    ; SB t0, 0(a2)
    ; ADDI a2, a2, 1
    ; ADDI a3, a3, -1
    ; BNE a3, zero, -8
    mov     edi, 0x00560023
    call riscv64_emit_word
    mov     edi, 0x00160613
    call riscv64_emit_word
    mov     edi, 0xFFF68693
    call riscv64_emit_word
    mov     edi, 0xFE069AE3
    call riscv64_emit_word
    epilogue

; ---- riscv64_encode_rev8 ----
riscv64_encode_rev8:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     eax, 0x6B805013        ; REV8 base (Zbb)
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- riscv64_encode_extend ----
riscv64_encode_extend:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    mov     eax, 0x60401013        ; SEXT.B base
    IF word [r12 + INST_op_id], e, ID_RV_SEXTH
        mov eax, 0x60501013
        ENDIF
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- riscv64_encode_csr ----
; CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
riscv64_encode_csr:
    prologue
    lea     r10, [r12 + INST_op0] ; rd
    lea     r11, [r12 + INST_op1] ; csr
    lea     r9,  [r12 + INST_op2] ; rs1 or uimm
    
    mov     eax, 0x00000073
    movzx   ecx, word [r12 + INST_op_id]
    
    ; Funct3 mapping
    IF ecx, e, ID_RV_CSRRW
        or eax, 0x00001000
    ENDIF
    IF ecx, e, ID_RV_CSRRS
        or eax, 0x00002000
    ENDIF
    IF ecx, e, ID_RV_CSRRC
        or eax, 0x00003000
    ENDIF
    IF ecx, e, ID_RV_CSRRWI
        or eax, 0x00005000
    ENDIF
    IF ecx, e, ID_RV_CSRRSI
        or eax, 0x00006000
    ENDIF
    IF ecx, e, ID_RV_CSRRCI
        or eax, 0x00007000
    ENDIF
    
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    
    mov     edi, [r11 + OPERAND_imm]
    and     edi, 0xFFF
    shl     edi, 20
    or      eax, edi
    
    IF byte [r9 + OPERAND_kind], e, OP_REG
        movzx edi, byte [r9 + OPERAND_reg]
        shl   edi, 15
        or    eax, edi
        ELSE
        mov   edi, [r9 + OPERAND_imm]
        and   edi, 0x1F
        shl   edi, 15
        or    eax, edi
        ENDIF
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- riscv64_encode_fp ----
; FADD.S/D, FSUB.S/D, FMUL.S/D, FDIV.S/D, FSQRT.S/D
riscv64_encode_fp:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     r9,  [r12 + INST_op2]
    
    mov     eax, 0x00007053        ; OP-FP base with rm=111 (Dynamic)
    movzx   ecx, word [r12 + INST_op_id]
    
    ; Funct7 mapping
    IF ecx, ge, ID_RV_FADD_S
        IF ecx, le, ID_RV_FADD_D
            or eax, 0x00000000
        ENDIF
    ENDIF
    IF ecx, ge, ID_RV_FSUB_S
        IF ecx, le, ID_RV_FSUB_D
            or eax, 0x08000000
        ENDIF
    ENDIF
    IF ecx, ge, ID_RV_FMUL_S
        IF ecx, le, ID_RV_FMUL_D
            or eax, 0x10000000
        ENDIF
    ENDIF
    IF ecx, ge, ID_RV_FDIV_S
        IF ecx, le, ID_RV_FDIV_D
            or eax, 0x18000000
        ENDIF
    ENDIF
    
    ; Precision: bit 25 (0=Single, 1=Double)
    test    ecx, 1
    IF nz
        or      eax, 0x01000000
        ENDIF
    
    ; Reg IDs: Rd=7, Rs1=15, Rs2=20
    movzx   edi, byte [r10 + OPERAND_reg]
    shl     edi, 7
    or      eax, edi
    movzx   edi, byte [r11 + OPERAND_reg]
    shl     edi, 15
    or      eax, edi
    
    ; Rs2 (only for binary ops)
    IF byte [r9 + OPERAND_kind], e, OP_REG
        movzx   edi, byte [r9 + OPERAND_reg]
        shl     edi, 20
        or      eax, edi
        ENDIF
    
    mov     rdi, rax
    call    riscv64_emit_word
    epilogue

; ---- riscv64_encode_fence ----
riscv64_encode_fence:
    prologue
    mov     edi, 0x0000000F         ; FENCE (full barrier)
    call riscv64_emit_word
    epilogue

; ---- riscv64_encode_pseudo_call ----
riscv64_encode_pseudo_call:
    prologue
    lea     r11, [r12 + INST_op0]
    
    mov     edi, 0x00000017
    mov     ecx, 1
    test    r13d, r13d
    jnz     .is_call
    mov     ecx, 6
.is_call:
    shl     ecx, 7
    or      edi, ecx
    
    IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
        push    rdi
        mov     rdi, rbx
        mov     rsi, [r12 + INST_offset]
        mov     rdx, [r11 + OPERAND_sym]
        mov     rcx, [r11 + OPERAND_imm]
        mov     r8, R_RISCV_CALL_HI20
        extern  reloc_record
        call    reloc_record
        pop     rdi
        ENDIF
    call    riscv64_emit_word
    
    mov     edi, 0x00000067
    IF r13d, e, 1
        or edi, (1 << 7)
        or edi, (1 << 15)
        ELSE
        or edi, (0 << 7)
        or edi, (6 << 15)
        ENDIF
    
    IF byte [r11 + OPERAND_kind], e, OP_SYMBOL
        push    rdi
        mov     rdi, rbx
        mov     rsi, [r12 + INST_offset]
        add     rsi, 4
        mov     rdx, [r11 + OPERAND_sym]
        mov     rcx, [r11 + OPERAND_imm]
        mov     r8, R_RISCV_CALL_LO12
        call    reloc_record
        pop     rdi
        ENDIF
    
    mov     dword [rbx + ASMCTX_inst_len], 8
    call    riscv64_emit_word
    epilogue

;*
; * [riscv64_encode_rvc_mv]
; * c.mv rd, rs2 -> 0x8002
; (rd << 7)
; (rs2 << 2)
; ;
riscv64_encode_rvc_mv:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; Constraints: rd != 0, rs2 != 0
    movzx   eax, byte [r10 + OPERAND_reg]
    test    al, al
    jz .error_reg
    movzx   ecx, byte [r11 + OPERAND_reg]
    test    cl, cl
    jz .error_reg
    
    mov     edi, 0x8002
    shl     eax, 7
    or      edi, eax
    shl     ecx, 2
    or      edi, ecx
    
    call    riscv64_emit_half
    jmp     .done
.error_reg:
    mov     rax, EXIT_INVALID_REG
.done:
    epilogue

;*
; * [riscv64_encode_rvc_addi]
; * c.addi rd, imm -> 0x0001
; (imm[5] << 12)
; (rd << 7)
; (imm[4:0] << 2)
; ;
riscv64_encode_rvc_addi:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    movzx   eax, byte [r10 + OPERAND_reg]
    test    al, al
    jz .error_reg     ; rd != 0
    
    mov     edi, 0x0001
    shl     eax, 7
    or      edi, eax
    
    mov     rax, [r11 + OPERAND_imm]
    test    rax, rax
    jz .error_imm   ; nzimm
    
    mov     rcx, rax
    and     ecx, 0x1F              ; imm[4:0]
    shl     ecx, 2
    or      edi, ecx
    
    and     rax, 0x20              ; imm[5]
    shl     rax, 7                 ; shift to bit 12
    or      edi, eax
    
    call    riscv64_emit_half
    jmp     .done
.error_reg:
    mov     rax, EXIT_INVALID_REG
    jmp     .done
.error_imm:
    mov     rax, EXIT_IMM_RANGE
.done:
    epilogue

;*
; * [riscv64_encode_amo]
; * Encodes Atomic Memory Operations (AMO).
; * Format: funct5(5) aq(1) rl(1) rs2(5) rs1(5) funct3(3) rd(5) 0101111
; ;
riscv64_encode_atomic:
    prologue
    push    r13
    mov     r13d, 0x0000002F       ; base opcode for AMO/LR/SC
    
    ; 1. Resolve rd
    lea     r10, [r12 + INST_op0]
    movzx   eax, byte [r10 + OPERAND_reg]
    shl     eax, 7
    or      r13d, eax
    
    ; 2. Resolve rs1 (address)
    lea     r10, [r12 + INST_op1]
    movzx   eax, byte [r10 + OPERAND_reg]
    shl     eax, 15
    or      r13d, eax
    
    ; 3. Resolve rs2 (value) - only for AMO and SC
    movzx   eax, word [r12 + INST_op_id]
    IF eax, ne, ID_RV_LR_W
        IF eax, ne, ID_RV_LR_D
            lea     r10, [r12 + INST_op2]
            movzx   eax, byte [r10 + OPERAND_reg]
            shl     eax, 20
            or      r13d, eax
            ENDIF
            ENDIF
    
    ; 4. Resolve funct3 (width)
    movzx   eax, word [r12 + INST_op_id]
    test    eax, 1                 ; Check if it's .D (odd ID)
    IF nz
        or      r13d, 0x3000       ; .d
        ELSE
        or      r13d, 0x2000       ; .w
        ENDIF

    ; 5. Map funct5
    movzx   eax, word [r12 + INST_op_id]
    
    ; Simplified mapping based on our ID order
    ; 3400: ADD.W, 3401: ADD.D
    ; 3402: SWAP.W, 3403: SWAP.D
    ; ...
    sub     eax, 3400
    shr     eax, 1                 ; index (0=ADD, 1=SWAP, 2=AND, 3=OR, 4=XOR, 5=MAX, 6=MIN, 7=LR, 8=SC)
    
    ; Jump table or nested IFs for funct5
    IF eax, e, 0
        or r13d, (0x00 << 27)
    ENDIF ; ADD
    IF eax, e, 1
        or r13d, (0x01 << 27)
    ENDIF ; SWAP
    IF eax, e, 2
        or r13d, (0x0C << 27)
    ENDIF ; AND
    IF eax, e, 3
        or r13d, (0x08 << 27)
    ENDIF ; OR
    IF eax, e, 4
        or r13d, (0x04 << 27)
    ENDIF ; XOR
    IF eax, e, 5
        or r13d, (0x14 << 27)
    ENDIF ; MAX
    IF eax, e, 6
        or r13d, (0x10 << 27)
    ENDIF ; MIN
    IF eax, e, 7
        or r13d, (0x02 << 27)
    ENDIF ; LR
    IF eax, e, 8
        or r13d, (0x03 << 27)
    ENDIF ; SC
    
    mov     edi, r13d
    call    riscv64_emit_word
    
    pop     r13
    xor     rax, rax
    epilogue

;*
; * [riscv64_emit_half]
; * Emits a 16-bit compressed instruction.
; ;
; ---- riscv64_encode_li ----
riscv64_encode_li:
    prologue
    ; Simple implementation: ADDI rd, zero, imm
    mov     r13d, 0x00000013
    lea     r11, [r12 + INST_op1]
    mov     byte [r11 + OPERAND_base], 0 ; x0
    call    riscv64_encode_i_type
    epilogue

riscv64_emit_half:
    prologue
    mov     rdx, rdi
    mov     rdi, rbx
    mov     rsi, [r12 + INST_section]
    extern  asmctx_emit_word
    call    asmctx_emit_word
    epilogue

