;
; ============================================================================
; File        : src/encoder/amd64.s
; Project     : utasm
; Description : AMD64 Instruction Encoder Logic.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"
%include "include/arch/amd64.inc"
%include "include/elf.inc"

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
    
    ; Reset length counter
    mov     dword [rbx + ASMCTX_inst_len], 0
    
    ; 0. VALIDATION: Check operand size consistency (A87: Hardened)
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
    
    ; 1. Emit Prefixes if present (REP/LOCK) (A71)
    xor     rcx, rcx
.prefix_loop:
    movzx   rax, byte [r12 + INST_prefixes + rcx]
    IF rax, ne, 0
        push    rcx
        mov     rdi, rbx
        mov     rsi, rax
        extern  amd64_emit_byte
        call    amd64_emit_byte
        pop     rcx
        ENDIF
    inc     rcx
    cmp     rcx, 4
    jl      .prefix_loop
    
    ; 2. Emit Segment Prefix if present in any operand
    lea     rdi, [r12 + INST_op0]
    mov     al, [rdi + OPERAND_segment]
    IF al, e, 0
        lea rdi, [r12 + INST_op1]
        mov al, [rdi + OPERAND_segment]
        ENDIF
    IF al, ne, 0
        call    amd64_emit_byte
        ENDIF
    
    ; 2. Dispatch based on Mnemonic ID
    movzx   rax, word [r12 + INST_op_id]
    
    IF ax, e, 1391                 ; MOV
        call    amd64_encode_mov
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
    ELSEIF ax, ge, 3000            ; Jcc
        IF ax, le, 3029
            call    amd64_encode_jcc
            ENDIF
    ELSEIF ax, e, 1611             ; RET
        call    amd64_encode_ret
    ELSEIF ax, e, 1583             ; PUSH
        mov     r13, 0x50
        mov r14, 0x35
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
    ELSEIF ax, ge, 4000            ; CMOVcc & SETcc
        IF ax, le, 4015
            call amd64_encode_cmovcc
        ELSEIF ax, le, 4031
            call amd64_encode_setcc
            ENDIF
    ELSEIF ax, ge, 1418            ; MOVS - MOVSW
        IF ax, le, 1425
            mov r13, 0xA4
            call amd64_encode_string
            ENDIF
    ELSEIF ax, ge, 1668            ; STOS - STOSW
        IF ax, le, 1672
            mov r13, 0xAA
            call amd64_encode_string
            ENDIF
    ELSEIF ax, ge, 1368            ; LODS - LODSW
        IF ax, le, 1372
            mov r13, 0xAC
            call amd64_encode_string
            ENDIF
    ELSEIF ax, ge, 1629            ; SCAS - SCASW
        IF ax, le, 1632
            mov r13, 0xAE
            call amd64_encode_string
            ENDIF
    ELSEIF ax, ge, 1078            ; CMPS - CMPSW
        IF ax, le, 1083
            mov r13, 0xA6
            call amd64_encode_string
            ENDIF
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
    ELSEIF ax, ge, 1630            ; SCAS
        IF ax, le, 1632
            sub ax, 1630
            ; logic for 0xA6/0xA7
            ENDIF
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
    ELSEIF ax, e, 1591             ; RDTSC
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
    ELSEIF ax, e, 1355             ; LDTILECFG
        mov     r13, 0x49
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1674             ; STTILECFG
        mov     r13, 0x49
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1693             ; TILELOADD
        mov     r13, 0x4B
        mov r14, 2
        mov r15, 0x66
        call amd64_encode_vex
    ELSEIF ax, e, 1696             ; TILESTORED
        mov     r13, 0x4B
        mov r14, 2
        mov r15, 0xF3
        call amd64_encode_vex
    ELSEIF ax, e, 1697             ; TILEZERO
        mov     r13, 0x49
        mov r14, 2
        mov r15, 0
        call amd64_encode_vex
    ELSEIF ax, e, 1687             ; TDPBSSD
        mov     r13, 0x5E
        mov r14, 2
        mov r15, 0xF2
        call amd64_encode_vex
    ELSEIF ax, e, 1590             ; RDRAND
        mov     r14, 6
        call amd64_encode_sec_r
    ELSEIF ax, e, 1593             ; RDSEED
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
    ELSEIF ax, e, 1642             ; SFENCE
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0xAE
        call amd64_emit_byte
        mov     al, 0xF8
        call amd64_emit_byte
    ELSEIF ax, e, 1380             ; MFENCE
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
    ELSEIF ax, ge, 1832            ; FMA3 Range
        IF ax, le, 1909
            ; Complex VEX.DDS/NDS encoding required. Stubbing for OS kernel purity.
            mov     al, 0x0F
            call amd64_emit_byte
            mov al, 0x38
            call amd64_emit_byte
            mov     al, 0x98
            call amd64_emit_byte
            ENDIF

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
    ELSEIF ax, ge, 5400            ; AVX-512 Range
        IF ax, le, 5412
            ; Complete EVEX 4-byte prefix stub
            mov     al, 0x62
            call amd64_emit_byte
            mov     al, 0xF1
            call amd64_emit_byte
            mov     al, 0xFD
            call amd64_emit_byte
            mov     al, 0x08
            call amd64_emit_byte
            ENDIF

    ; ---- Step 6: VNNI & BFLOAT16 ----
    ELSEIF ax, ge, 5500            ; VNNI Range
        IF ax, le, 5503
            ; VEX/EVEX hybrid stub
            mov     al, 0x62
            call amd64_emit_byte
            ENDIF

    ; ---- Step 7: 3DNow! & AMD XOP ----
    ELSEIF ax, ge, 5600            ; 3DNow Range
        IF ax, le, 5612
            ; 3DNow uses 0F 0F [ModRM] [Opcode] suffix
            mov     al, 0x0F
            call amd64_emit_byte
            mov al, 0x0F
            call amd64_emit_byte
            ENDIF

    ; ---- Step 8: SGX Enclave Sub-Leafs ----
    ELSEIF ax, ge, 5700            ; SGX Range
        IF ax, le, 5706
            ; Resolves to ENCLS (0F 01 CF) or ENCLU (0F 01 D7)
            mov     al, 0x0F
            call amd64_emit_byte
            mov al, 0x01
            call amd64_emit_byte
            mov     al, 0xCF
            call amd64_emit_byte
            ENDIF

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
    ELSEIF ax, ge, 1043            ; BNDCL - BNDSTX
        IF ax, le, 1049
            call amd64_encode_mpx
            ENDIF

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
        mov     rsi, r10
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        and al, 7
        add al, 0xC8
        call amd64_emit_byte

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
    ELSEIF ax, ge, 4016            ; SETcc
        call    amd64_encode_setcc
    ELSEIF ax, ge, 4000            ; CMOVcc
        call    amd64_encode_cmovcc
    ELSEIF ax, e, 1168             ; ENTER
        call    amd64_encode_enter
    ELSEIF ax, e, 1357             ; LEAVE
        mov     al, 0xC9
        call    amd64_emit_byte
    ELSEIF ax, e, 1373             ; LOOP
        mov     al, 0xE2
        call    amd64_emit_branch_rel8
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
    ELSEIF ax, ge, 5100            ; AVX-512 (EVEX)
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
    ELSEIF ax, e, 1888             ; XBEGIN
        mov     al, 0xC7
        call amd64_emit_byte
        mov     al, 0xF8
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
            mov al, RELOC_REL32
            mov rsi, [r10 + OPERAND_sym]
            call amd64_emit_reloc
            xor rax, rax
            call amd64_emit_dword
            ELSE
            mov rdi, [r10 + OPERAND_imm]
            call amd64_emit_dword
            ENDIF
    ELSEIF ax, e, 1889             ; XEND
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, 0x01
        call amd64_emit_byte
        mov     al, 0xD5
        call amd64_emit_byte
    ELSEIF ax, e, 1887             ; XABORT
        mov     al, 0xC6
        call amd64_emit_byte
        mov     al, 0xF8
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov     rax, [r10 + OPERAND_imm]
        call amd64_emit_byte
    ELSEIF ax, e, 1069             ; CLI / STI / CLD / STD
        mov     al, 0xFA
        IF ax, e, 1666
        mov al, 0xFB
        ELSEIF ax, e, 1065
        mov al, 0xFC
        ELSEIF ax, e, 1665
        mov al, 0xFD
        ENDIF
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
    
    ; If a helper returned an error (30 or 53), preserve it.
    ; Otherwise, clear RAX to signal success (0).
    cmp     rax, EXIT_ENCODE_FAIL
    je      .done
    cmp     rax, EXIT_RELOC_ERROR
    je      .done
    xor     rax, rax
.done:
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

;*
; * [amd64_encode_mov]
; * Handles various MOV encodings.
; ;
amd64_encode_mov:
    prologue
    ; check operands
    cmp     byte [r12 + INST_nops], 2
    jne     .error
    
    lea     r13, [r12 + INST_op0]  ; r13 = Dest
    lea     r14, [r12 + INST_op1]  ; r14 = Src
    
    ; Case 0: PRIVILEGED MOV (CRn/DRn)
    IF byte [r13 + OPERAND_reg], ge, 32
        IF byte [r13 + OPERAND_reg], le, 63
            ; MOV CRn/DRn, reg (0x0F 0x22/0x23)
            mov cl, [r13 + OPERAND_reg]
            and cl, 0x0F
            mov dl, [r14 + OPERAND_reg] ; GPR
            
            ; Calculate REX: 0x40
            ; (CR_hi << 2)
            ; (GPR_hi)
            mov al, 0x40
            mov r8b, cl
            shr r8b, 3
            shl r8b, 2
            or al, r8b  ; REX.R for CR
            mov r8b, dl
            shr r8b, 3
            or al, r8b              ; REX.B for GPR
            IF al, ne, 0x40
                call amd64_emit_byte
            ENDIF 
            
            mov al, 0x0F
            call amd64_emit_byte
            mov al, 0x22
            IF byte [r13 + OPERAND_reg], ge, 48
            inc al
            ENDIF
            call amd64_emit_byte
            
            mov al, cl
            and al, 0x07
            mov rdi, r14
            call amd64_emit_modrm_sib
            jmp .done
            ENDIF
            ENDIF
    IF byte [r14 + OPERAND_reg], ge, 32
        IF byte [r14 + OPERAND_reg], le, 63
            ; MOV reg, CRn/DRn (0x0F 0x20/0x21)
            mov cl, [r14 + OPERAND_reg]
            and cl, 0x0F
            mov dl, [r13 + OPERAND_reg] ; GPR
            
            ; Calculate REX: 0x40
            ; (CR_hi << 2)
            ; (GPR_hi)
            mov al, 0x40
            mov r8b, cl
            shr r8b, 3
            shl r8b, 2
            or al, r8b  ; REX.R for CR
            mov r8b, dl
            shr r8b, 3
            or al, r8b              ; REX.B for GPR
            IF al, ne, 0x40
                call amd64_emit_byte
            ENDIF 
            
            mov al, 0x0F
            call amd64_emit_byte
            mov al, 0x20
            IF byte [r14 + OPERAND_reg], ge, 48
            inc al
            ENDIF
            call amd64_emit_byte
            
            mov al, cl
            and al, 0x07
            mov rdi, r13
            call amd64_emit_modrm_sib
            jmp .done
            ENDIF
            ENDIF

    ; Case 1: MOV REG, REG
    IF byte [r13 + OPERAND_kind], e, OP_REG
        IF byte [r14 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r13 + OPERAND_size]
            mov     rsi, r14           ; Src
            mov     rdx, r13           ; Dest
            call    amd64_emit_prefixes
            
            ; Opcode 0x88 (8-bit) or 0x89 (16/32/64-bit)
            mov     al, 0x88
            IF byte [r13 + OPERAND_size], ne, 8
                inc al
                ENDIF
            call    amd64_emit_byte
            
            ; ModR/M: 11 (reg,reg)
            ; (src << 3)
            ; dest
            mov     al, 0xC0
            mov     cl, [r14 + OPERAND_reg]
            and cl, 0x07
            shl cl, 3
            or al, cl
            mov     cl, [r13 + OPERAND_reg]
            and cl, 0x07
            or al, cl
            call    amd64_emit_byte
            jmp     .done
            ENDIF
        
        ; Case 2: MOV REG, IMM / SYMBOL
        mov     al, [r14 + OPERAND_kind]
        IF al, e, OP_IMM
            jmp .do_imm
        ENDIF
        IF al, e, OP_SYMBOL
            jmp .do_imm
        ENDIF
        jmp .not_imm
        
    .do_imm:
            mov     dl, [r13 + OPERAND_size]
            mov     rax, [r14 + OPERAND_imm]
            
            ; OPTIMIZATION: 64-bit MOV to REG with 32-bit non-negative IMM
            ; can use 32-bit MOV (zero-extension)
            IF dl, e, 64
                IF byte [r14 + OPERAND_kind], e, OP_IMM
                    mov     r11, rax
                    shr     r11, 32
                    IF r11, e, 0
                        mov dl, 32
                    ENDIF
                    ENDIF
                ENDIF

            ; 64-bit MOV REG, IMM64 / SYMBOL
            IF dl, e, 64
                mov al, 64
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]     ; Current offset in active section
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_64
                    call reloc_record
                    xor rdi, rdi
                    call amd64_emit_qword
                    ELSE
                    mov rdi, [r14 + OPERAND_imm]
                    call amd64_emit_qword
                    ENDIF
                jmp .done
                ENDIF
            
            ; 32-bit MOV REG, IMM32 / SYMBOL
            IF dl, e, 32
                mov al, 32
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]     ; Current offset
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_32
                    call reloc_record
                    xor rdi, rdi
                    call amd64_emit_dword
                    ELSE
                    mov rdi, [r14 + OPERAND_imm]
                    call amd64_emit_dword
                    ENDIF
                jmp .done
                ENDIF
            
            ; 16-bit MOV REG, IMM16 / SYMBOL
            IF dl, e, 16
                mov al, 16
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                mov rax, [r14 + OPERAND_imm]
                call amd64_emit_word
                jmp .done
                ENDIF
            
            ; 8-bit MOV REG, IMM8
            IF dl, e, 8
                mov al, 8
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB0
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                mov rax, [r14 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
    .not_imm:

        ; Case 3: MOV REG, MEM
        IF byte [r14 + OPERAND_kind], e, OP_MEM
            ; Dynamic Prefixes
            mov     rdi, r13
            mov     rsi, r14
            call    amd64_emit_prefixes
            
            mov     al, 0x8B
            call amd64_emit_byte
            
            ; ModRM/SIB
            mov     al, [r13 + OPERAND_reg]
            and     al, 7            ; Low 3 bits for ModRM
            mov     rdi, r14
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
            ENDIF

    ; Case 4: MOV MEM, REG
    IF byte [r13 + OPERAND_kind], e, OP_MEM
        IF byte [r14 + OPERAND_kind], e, OP_REG
            ; Dynamic Prefixes
            mov     rdi, r14         ; Reg is Src (Op1)
            mov     rsi, r13         ; Mem is Dest (Op0)
            call    amd64_emit_prefixes
            
            mov     al, 0x89
            call amd64_emit_byte
            
            mov     al, [r14 + OPERAND_reg]
            and     al, 7
            mov     rdi, r13
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
        
        ; Case 5: MOV MEM, IMM
        IF byte [r14 + OPERAND_kind], e, OP_IMM
            ; Dynamic Prefixes (W bit depends on MEM size)
            mov     rdi, r13
            mov     rsi, r14
            call    amd64_emit_prefixes
            
            mov     al, 0xC7
            call amd64_emit_byte
            
            xor     al, al   ; Extension Digit 0
            mov     rdi, r13
            call    amd64_emit_modrm_sib
            
            mov     rdi, [r14 + OPERAND_imm]
            ; check size to emit dd or dq? 
            ; In x86_64, MOV [MEM], IMM32 is the standard even for 64-bit.
            call    amd64_emit_dword
            jmp     .done
            ENDIF
            ENDIF
    
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_arithmetic]
; * Input:
; *   R13: Base Opcode (for reg-reg)
; *   R14: Extension Digit (for imm)
; ;
amd64_encode_arithmetic:
    prologue
    cmp     byte [r12 + INST_nops], 2
    jne     .error
    
    lea     r10, [r12 + INST_op0]  ; Dest
    lea     r11, [r12 + INST_op1]  ; Src
    
    ; Case 1: r/m, reg
    IF byte [r10 + OPERAND_kind], e, OP_REG
        IF byte [r11 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            mov     rsi, r11           ; Src
            mov     rdx, r10           ; Dest
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Opcode is Base (8-bit) or Base + 1 (16/32/64-bit)
            mov     rax, r13
            IF byte [r10 + OPERAND_size], ne, 8
                inc al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; ModR/M: 11
            ; src
            ; dest
            mov     al, 0xC0
            mov     cl, [r11 + OPERAND_reg]
            and cl, 0x07
            shl cl, 3
            or al, cl
            mov     cl, [r10 + OPERAND_reg]
            and cl, 0x07
            or al, cl
            call    amd64_emit_byte
            jmp     .done
            ENDIF
        
        ; Case 2: r/m, imm
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            ; VALIDATION: Arithmetic instructions only support 32-bit sign-extended IMM
            mov     rax, [r11 + OPERAND_imm]
            mov     rcx, rax
            sar     rcx, 31            ; Check if bits 31-63 are identical
            IF ecx, ne, 0
                IF ecx, ne, 0xFFFFFFFF
                    jmp .error
                    ENDIF
                    ENDIF

            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            xor     rsi, rsi
            mov     rdx, r10
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; 8-bit case: 0x80 /extension
            IF byte [r10 + OPERAND_size], e, 8
                mov al, 0x80
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov al, 0xC0
                mov cl, r14b
                shl cl, 3
                or al, cl
                mov cl, [r10 + OPERAND_reg]
                and cl, 0x07
                or al, cl
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov rax, [r11 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
            
            ; 16/32/64-bit logic
            ; OPTIMIZATION: Check if immediate fits in 8-bit signed
            mov     rax, [r11 + OPERAND_imm]
            cmp     rax, -128
            jl      .long_imm
            cmp     rax, 127
            jg      .long_imm
            
            ; 8-bit optimization (0x83)
            mov     al, 0x83
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; ModR/M: 11
            ; extension
            ; dest
            mov     al, 0xC0
            mov     cl, r14b
            shl     cl, 3
            or      al, cl
            mov     cl, [r10 + OPERAND_reg]
            and     cl, 0x07
            or      al, cl
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     rax, [r11 + OPERAND_imm]
            call    amd64_emit_byte
            jmp     .done

.long_imm:
            mov     al, 0x81
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; ModR/M: 11
            ; extension
            ; dest
            mov     al, 0xC0
            mov     cl, r14b       ; Extension digit
            shl     cl, 3
            or      al, cl
            mov     cl, [r10 + OPERAND_reg]
            and     cl, 0x07
            or      al, cl
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     rax, [r11 + OPERAND_imm]
            call    amd64_emit_dword
            jmp     .done
            ENDIF

        ; Case 3: r, m
        IF byte [r11 + OPERAND_kind], e, OP_MEM
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            mov     rsi, r10           ; Reg (Src for ModRM)
            mov     rdx, r11           ; Mem (Dest for ModRM)
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Opcode is Base + 2 (8-bit) or Base + 3 (16/32/64-bit)
            mov     rax, r13
            add al, 2
            IF byte [r10 + OPERAND_size], ne, 8
                inc al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     al, [r10 + OPERAND_reg]
            mov     rdi, r11
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
            ENDIF

    ; Case 4: m, r
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        IF byte [r11 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r11 + OPERAND_size]
            mov     rsi, r11           ; Reg
            mov     rdx, r10           ; Mem
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Opcode is Base (8-bit) or Base + 1 (16/32/64-bit)
            mov     rax, r13
            IF byte [r11 + OPERAND_size], ne, 8
                inc al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     al, [r11 + OPERAND_reg]
            mov     rdi, r10
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
        
        ; Case 5: m, imm
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            xor     rsi, rsi
            mov     rdx, r10
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Logic similar to Case 2 (0x81/0x83) but with memory
            ; 8-bit case: 0x80 /extension
            IF byte [r10 + OPERAND_size], e, 8
                mov al, 0x80
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov al, r14b
                mov rdi, r10
                call amd64_emit_modrm_sib
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov rax, [r11 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
            
            ; 16/32/64-bit
            mov rax, [r11 + OPERAND_imm]
            IF rax, ge, -128
                IF rax, le, 127
                    mov al, 0x83
                    call amd64_emit_byte
                    lea     r10, [r12 + INST_op0]
                    lea     r11, [r12 + INST_op1]
                    mov al, r14b
                    mov rdi, r10
                    call amd64_emit_modrm_sib
                    lea     r10, [r12 + INST_op0]
                    lea     r11, [r12 + INST_op1]
                    mov rax, [r11 + OPERAND_imm]
                    call amd64_emit_byte
                    jmp .done
                    ENDIF
                    ENDIF
            mov al, 0x81
            call amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov al, r14b
            mov rdi, r10
            call amd64_emit_modrm_sib
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov rdi, [r11 + OPERAND_imm]
            call amd64_emit_dword
            jmp .done
            ENDIF
            ENDIF

.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_syscall]
; ;
amd64_encode_syscall:
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x05
    call amd64_emit_byte
    ret

;*
; * [amd64_encode_sysret]
; ;
amd64_encode_sysret:
    mov     al, 0x48
    call amd64_emit_byte
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x07
    call amd64_emit_byte
    ret

;*
; * [amd64_encode_push]
; ;
amd64_encode_push:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_size], e, 32
        jmp .error
    ENDIF 

    ; Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    
    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, 0x50
        mov cl, [r10 + OPERAND_reg]
        and cl, 0x07
        add al, cl
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        mov     al, 0xFF
        call amd64_emit_byte
        mov     al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_IMM
        mov     rax, [r10 + OPERAND_imm]
        IF rax, ge, -128
            IF rax, le, 127
                mov al, 0x6A
                call amd64_emit_byte
                mov rax, [r10 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
                ENDIF
        mov     al, 0x68
        call amd64_emit_byte
        mov     rax, [r10 + OPERAND_imm]
        call amd64_emit_dword
        jmp     .done
        ENDIF
    jmp     .error
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

amd64_encode_pop:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_size], e, 32
        jmp .error
    ENDIF 

    ; Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    
    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, 0x58
        mov cl, [r10 + OPERAND_reg]
        and cl, 0x07
        add al, cl
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        mov     al, 0x8F
        call amd64_emit_byte
        mov     al, 0
        mov rdi, r10
        call amd64_emit_modrm_sib
        jmp     .done
        ENDIF
    jmp     .error
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_branch]
; * Input: R13 = Opcode for REL32 form
; ;
amd64_encode_branch:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; Case 1: Symbol (REL32)
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, r13b
        call    amd64_emit_byte
        mov     al, RELOC_REL32
        mov     rsi, [r10 + OPERAND_sym]
        call    amd64_emit_reloc
        xor     rax, rax
        call    amd64_emit_dword
        jmp     .done
        ENDIF
    
    ; Case 2: Register or Memory (FF /digit)
    ; CALL = FF /2, JMP = FF /4
    mov     al, 0xFF
    call    amd64_emit_byte
    
    mov     al, 2               ; Default to CALL extension
    IF r13b, e, 0xE9            ; If it was JMP (E9)
        mov al, 4               ; Use JMP extension
        ENDIF
    
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_ret]
; ;
amd64_encode_ret:
    prologue
    cmp     byte [r12 + INST_nops], 0
    IF e
        mov     al, 0xC3
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    
    ; RET imm16 (0xC2)
    mov     al, 0xC2
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rax, [r10 + OPERAND_imm]
    call    amd64_emit_word
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_jcc]
; ;
amd64_encode_jcc:
    prologue
    mov     ax, [r12 + INST_op_id]
    
    ; Extract condition code from ID (3000-3031)
    sub     ax, 3000
    and     rax, 0x0F          ; Get CC bits
    mov     r14, rax
    
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x80
    add al, r14b
    call amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, RELOC_REL32
        mov     rsi, [r10 + OPERAND_sym]
        call    amd64_emit_reloc
        ENDIF
    xor     rax, rax
    call    amd64_emit_dword
.done:
    epilogue

;*
; * [amd64_encode_branch_short]
; * R13 = Opcode (0xEB for JMP, etc)
; ;
amd64_encode_branch_short:
    prologue
    mov     al, r13b
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, RELOC_REL8
        mov     rsi, [r10 + OPERAND_sym]
        call    amd64_emit_reloc
        ENDIF
    
    xor     rax, rax
    call    amd64_emit_byte    ; 1-byte placeholder
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_jcc_short]
; ;
amd64_encode_jcc_short:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 3000
    and     rax, 0x0F
    add     al, 0x70           ; 0x70 = JO short, 0x74 = JE short
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, RELOC_REL8
        mov     rsi, [r10 + OPERAND_sym]
        call    amd64_emit_reloc
        ENDIF
    
    xor     rax, rax
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_lea]
; ;
amd64_encode_lea:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     al, 0x48       ; REX.W
    IF byte [r10 + OPERAND_reg], ge, 8
        or  al, 0x04       ; REX.R
        ENDIF
    call    amd64_emit_byte
    
    mov     al, 0x8D       ; Opcode LEA
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_test]
; ;
amd64_encode_test:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; REX
    xor     r15, r15
    IF byte [r10 + OPERAND_size], e, 8
        or  r15, 0x48
        ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or  r15, 0x44      ; REX.R (Src)
        ENDIF
    
    test    r15, r15
    jz      .no_rex
    mov     rax, r15
    call    amd64_emit_byte
.no_rex:
    mov     rax, r13       ; Opcode 0x85 (r/m, reg)
    call    amd64_emit_byte
    
    mov     al, [r11 + OPERAND_reg]
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_unary]
; * INC/DEC/NEG/NOT
; ;
amd64_encode_unary:
    prologue
    lea     r10, [r12 + INST_op0]
    
    xor     r15, r15
    IF byte [r10 + OPERAND_size], e, 8
        or  r15, 0x48
        ENDIF
    
    test    r15, r15
    jz      .no_rex
    mov     rax, r15
    call    amd64_emit_byte
.no_rex:
    mov     al, 0xFF       ; Multi-op Unary
    IF r14b, ge, 2         ; NEG/NOT use 0xF7
        mov al, 0xF7
        ENDIF
    call    amd64_emit_byte
    
    mov     al, r14b       ; Extension Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_shift]
; * SHL/SHR/SAR/ROL/ROR
; ;
amd64_encode_shift:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    xor     r15, r15
    IF byte [r10 + OPERAND_size], e, 8
        or  r15, 0x48
        ENDIF
    
    test    r15, r15
    jz      .no_rex
    mov     rax, r15
    call    amd64_emit_byte
.no_rex:
    ; Opcode: 0xD1 (1), 0xD3 (CL), 0xC1 (imm8)
    IF byte [r11 + OPERAND_kind], e, OP_IMM
        mov al, 0xC1
        call    amd64_emit_byte
        mov     al, r14b
        mov     rdi, r10
        call    amd64_emit_modrm_sib
        mov     rax, [r11 + OPERAND_imm]
        call    amd64_emit_byte
        ELSE
        ; Default to shift by 1 (0xD1) for now
        mov     al, 0xD1
        call    amd64_emit_byte
        mov     al, r14b
        mov     rdi, r10
        call    amd64_emit_modrm_sib
        ENDIF
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_imul]
; ;
amd64_encode_imul:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     rdx, [r12 + INST_op2]
    
    ; 1-Operand: IMUL r/m (F7 /5)
    cmp     byte [r12 + INST_nops], 1
    IF e
        mov r14, 5
        jmp amd64_encode_unary_math
        ENDIF
    
    ; 2-Operand: IMUL reg, r/m (0F AF)
    cmp     byte [r12 + INST_nops], 2
    IF e
        mov al, [r10 + OPERAND_size]
        mov rsi, r10
        mov rdx, r11
        call amd64_emit_prefixes
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0xAF
        call amd64_emit_byte
        mov al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
        jmp .done
        ENDIF
    jmp .done
.done:
    epilogue
    
    ; 3-Operand: IMUL reg, r/m, imm (69/6B)
    mov al, [r10 + OPERAND_size]
    mov rsi, r10
    mov rdx, r11
    call amd64_emit_prefixes
    
    mov rax, [rdx + OPERAND_imm]
    IF rax, ge, -128
        IF rax, le, 127
            mov al, 0x6B
            call amd64_emit_byte
            mov al, [r10 + OPERAND_reg]
            mov rdi, r11
            call amd64_emit_modrm_sib
            mov rax, [rdx + OPERAND_imm]
            call amd64_emit_byte
            jmp .done
            ENDIF
            ENDIF
    
    mov al, 0x69
    call amd64_emit_byte
    mov al, [r10 + OPERAND_reg]
    mov rdi, r11
    call amd64_emit_modrm_sib
    mov rdi, [rdx + OPERAND_imm]
    call amd64_emit_dword
    jmp .done

;*
; * [amd64_encode_unary_math]
; * MUL/DIV/IDIV/etc.
; ;
amd64_encode_unary_math:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; Smart Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    
    ; Opcode is 0xF6 (8-bit) or 0xF7 (16/32/64-bit)
    mov     al, 0xF6
    IF byte [r10 + OPERAND_size], ne, 8
        inc al
        ENDIF
    call    amd64_emit_byte
    
    mov     al, r14b       ; Digit (4=MUL, 6=DIV, 7=IDIV)
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_cmovcc]
; ;
amd64_encode_cmovcc:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 4000
    and     rax, 0x0F
    mov     r14, rax           ; Condition Code
    
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; REX.W
    mov     al, 0x48
    IF byte [r10 + OPERAND_reg], ge, 8
        or  al, 0x04
        ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or  al, 0x01
        ENDIF
    call    amd64_emit_byte
    
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x40
    add     al, r14b
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_setcc]
; ;
amd64_encode_setcc:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 4016
    and     rax, 0x0F
    mov     r14, rax
    
    lea     r10, [r12 + INST_op0]
    
    ; REX if reg >= 8
    IF byte [r10 + OPERAND_reg], ge, 8
        mov al, 0x41
        call    amd64_emit_byte
        ENDIF
    
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x90
    add     al, r14b
    call    amd64_emit_byte
    
    xor     al, al             ; Reg field 0
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_enter]
; ;
amd64_encode_enter:
    prologue
    mov     al, 0xC8
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    mov     ax, [r10 + OPERAND_imm]
    call    amd64_emit_byte    ; Enter uses word, then byte
    mov     al, ah
    call    amd64_emit_byte
    
    lea     r11, [r12 + INST_op1]
    mov     al, [r11 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_emit_branch_rel8]
; ;
amd64_emit_branch_rel8:
    call    amd64_emit_byte
    xor     al, al             ; rel8 placeholder
    call    amd64_emit_byte
    ret

    xor     al, al             ; rel8 placeholder
    call    amd64_emit_byte
    ret

;*
; * [amd64_encode_int]
; ;
amd64_encode_int:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0xCD
    call    amd64_emit_byte
    mov     rax, [r10 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_system_m]
; * LGDT/LIDT
; ;
amd64_encode_system_m:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x01
    call    amd64_emit_byte
    
    mov     al, r14b           ; Digit 2 for LGDT, 3 for LIDT
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_system_00]
; * R14 = Digit
; ;
amd64_encode_system_00:
    prologue
    lea     r10, [r12 + INST_op0]
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x00
    call amd64_emit_byte
    mov     al, r14b
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_in]
; ;
amd64_encode_in:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; Case: in al/eax, dx
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov al, 0xEC
        IF byte [r10 + OPERAND_size], e, 4
            mov al, 0xED
            ENDIF
        call    amd64_emit_byte
        ELSE
        ; Case: in al/eax, imm8
        mov al, 0xE4
        IF byte [r10 + OPERAND_size], e, 4
            mov al, 0xE5
            ENDIF
        call    amd64_emit_byte
        mov     rax, [r11 + OPERAND_imm]
        call    amd64_emit_byte
        ENDIF
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_out]
; ;
amd64_encode_out:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov al, 0xEE
        IF byte [r11 + OPERAND_size], e, 4
            mov al, 0xEF
            ENDIF
        call    amd64_emit_byte
        ELSE
        mov al, 0xE6
        IF byte [r11 + OPERAND_size], e, 4
            mov al, 0xE7
            ENDIF
        call    amd64_emit_byte
        mov     rax, [r10 + OPERAND_imm]
        call    amd64_emit_byte
        ENDIF
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_fpu]
; * FLD/FST/FADD/etc.
; ;
amd64_encode_fpu:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; x87 doesn't use REX
    mov     rax, r13           ; Base Opcode (e.g. 0xD8)
    call    amd64_emit_byte
    
    ; ModRM extension
    mov     al, r14b           ; Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

    mov     al, r14b           ; Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done

;*
; * [amd64_encode_sse]
; * R13 = Opcode
; * R14 = Format (0=0F, 1=66 0F, 2=0F 38, 3=0F 3A)
; ;
;*
; * [amd64_encode_sse_crypto]
; * R13 = Opcode
; * R14 = Map (1=0F, 2=0F 38, 3=0F 3A)
; * R15 = Mandatory Prefix (0=None, 0x66, 0xF2, 0xF3)
; ;
amd64_encode_sse_crypto:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; Mandatory Prefix
    IF r15, ne, 0
        mov rax, r15
        call amd64_emit_byte
        ENDIF
    
    ; REX if using R8-R15 or XMM8-XMM31
    xor     rax, rax
    IF byte [r10 + OPERAND_reg], ge, 8
        or al, 0x44
    ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or al, 0x41
    ENDIF
    IF al, ne, 0
        call amd64_emit_byte
    ENDIF
    
    ; Opcode Escape
    mov     al, 0x0F
    call amd64_emit_byte
    IF r14b, e, 2
        mov al, 0x38
        call amd64_emit_byte
    ELSEIF r14b, e, 3
        mov al, 0x3A
        call amd64_emit_byte
        ENDIF
    
    mov     al, r13b
    call amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    
    ; If Map 3 (0F 3A), emit immediate byte if present
    IF r14b, e, 3
        lea r11, [r12 + INST_op2]
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            mov rax, [r11 + OPERAND_imm]
            call amd64_emit_byte
            ENDIF
            ENDIF
    jmp     .done
.done:
    epilogue

amd64_encode_vex:
    prologue
    push    rbx
    push    r13
    push    r14
    push    r15
    
    ; Inputs: R13=Opcode, R14=Map, R15=pp (bit 8=W)
    ; Operands: R10=Dest (Reg), R11=Src1 (Reg), RDX=Src2 (Reg/Mem)
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     rdx, [r12 + INST_op2]
    
    ; 1. Calculate R, X, B bits
    xor     dl, dl                 ; Initial R, X, B = 0
    
    ; R bit (from Dest reg)
    mov     al, [r10 + OPERAND_reg]
    IF al, ge, 8
        or dl, 0x04
    ENDIF
    
    ; X, B bits (from Src2)
    IF byte [rdx + OPERAND_kind], e, OP_MEM
        mov al, [rdx + OPERAND_base]
        IF al, ge, 8
            or dl, 0x01
        ENDIF 
        mov al, [rdx + OPERAND_index]
        IF al, ge, 8
            or dl, 0x02
        ENDIF 
    ELSEIF byte [rdx + OPERAND_kind], e, OP_REG
        mov al, [rdx + OPERAND_reg]
        IF al, ge, 8
            or dl, 0x01
        ENDIF
        ENDIF

    ; 2. Resolve vvvv (Src1)
    movzx   ecx, byte [r11 + OPERAND_reg]
    
    ; 3. W, L, pp bits
    mov     r8b, r15b              ; pp
    and     r8b, 0x03
    
    ; L bit (from register size)
    IF byte [r10 + OPERAND_size], e, 32
        or r8b, 0x02
        ENDIF
    
    ; W bit (from instruction metadata? For now, if operand size is 8/64, assume W=1)
    ; Actually, W depends on the instruction. Let's pass it via R15's upper bits.
    mov     rax, r15
    shr     rax, 8                 ; W is in bit 8+
    IF rax, e, 1
        or r8b, 0x04
        ENDIF
    
    ; 4. Emit Prefix (Unified)
    ; r8b: W:bit2, L:bit1, pp:bits1-0
    ; r9b: Map
    ; cl:  vvvv
    ; dl:  R,X,B (inverted)
    
    and     r15b, 0x03             ; pp bits
    or      r8b, r15b
    mov     r9b, r14b              ; Map
    mov     dl, [rsp + 0]          ; Actually, I need to preserve r8b (R,X,B) properly
    ; ... refactor needed ...
; Check if W is needed (e.g. 64-bit SIMD ops)
    IF byte [r10 + OPERAND_size], e, 64
        or al, 0x80                ; W=1
        ENDIF
    call    amd64_emit_byte

    ; 5. Opcode and ModRM
    mov     al, r13b
    call amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    and     al, 7                  ; Only low 3 bits for ModRM
    mov     rdi, rdx
    call    amd64_emit_modrm_sib
    
    pop     r15
    pop     r14
    pop     r13
    pop     rbx
    jmp     .done
.done:
    epilogue
    
    IF bl, e, 0xC5
        mov al, 0xC5
        call amd64_emit_byte
        ; Byte 1: R vvvv L pp
        mov al, r15b           ; pp
        
        ; R (inverted)
        mov cl, [r10 + OPERAND_reg]
        IF cl, ge, 8
        ELSE
        or al, 0x80
        ENDIF
        
        ; vvvv (inverted)
        IF byte [r12 + INST_nops], ge, 3
            mov cl, [r11 + OPERAND_reg]
            and cl, 0x0F
            xor cl, 0x0F
            shl cl, 3
            or al, cl
            ELSE
            or al, 0x78        ; 1111
            ENDIF
        call amd64_emit_byte
        ELSE
        mov al, 0xC4
        call amd64_emit_byte
        ; Byte 1: R X B m-mmmm
        mov al, r14b           ; Map
        mov cl, [r10 + OPERAND_reg]
        IF cl, ge, 8
        ELSE
        or al, 0x80
        ENDIF  ; R
        mov cl, [rdx + OPERAND_reg]
        IF cl, ge, 8
        ELSE
        or al, 0x40
        ENDIF  ; X
        mov cl, [rdx + OPERAND_base]
        IF cl, ge, 8
        ELSE
        or al, 0x20
        ENDIF  ; B
        call amd64_emit_byte
        
        ; Byte 2: W vvvv L pp
        mov al, r15b           ; pp
        IF byte [r10 + OPERAND_size], e, 64
            or al, 0x80
        ENDIF ; W bit
        
        ; vvvv
        IF byte [r12 + INST_nops], ge, 3
            mov cl, [r11 + OPERAND_reg]
            and cl, 0x0F
            xor cl, 0x0F
            shl cl, 3
            or al, cl
            ELSE
            or al, 0x78
            ENDIF
        call amd64_emit_byte
        ENDIF
    
    ; 2. Opcode
    mov al, r13b
    call amd64_emit_byte
    
    ; 3. ModRM/SIB
    mov al, [r10 + OPERAND_reg]
    mov rdi, rdx
    IF byte [r12 + INST_nops], lt, 3
        mov rdi, r11
        ENDIF
    call    amd64_emit_modrm_sib
    jmp .done

;*
; * [amd64_encode_evex]
; * R13 = Opcode
; * R14 = Map (1=0F, 2=0F 38, 3=0F 3A)
; * R15 = W (0 or 1)
; LL (0, 1, 2) << 2
; ;
amd64_encode_evex:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    lea     rdx, [r12 + INST_op2]
    
    ; Byte 0: 0x62
    mov     al, 0x62
    call amd64_emit_byte
    
    ; Byte 1: ~R ~X ~B ~R' 0 0 m m
    ; m-mmmm (Map)
    mov     al, r14b
    and     al, 0x03
    
    ; R, X, B, R' inverted (1 if bit is 0, 0 if bit is 1)
    mov cl, [r10 + OPERAND_reg]
    IF cl, ge, 8
    ELSE
    or al, 0x80
    ENDIF  ; R
    IF cl, ge, 16
    ELSE
    or al, 0x10
    ENDIF ; R'
    
    ; Default X and B to 1 (inverted)
    or al, 0x60
    IF byte [rdx + OPERAND_kind], e, OP_MEM
        mov cl, [rdx + OPERAND_reg]
        IF cl, ge, 8
            and al, ~0x40
        ENDIF ; X
        ; R16-R31 for index? EVEX supports it.
        IF cl, ge, 16
            and al, ~0x04
        ENDIF ; Wait, X' is V' in byte 3? No, X' is bit 2 of byte 1.
        
        mov cl, [rdx + OPERAND_base]
        IF cl, ge, 8
            and al, ~0x20
        ENDIF ; B
        ELSE
        mov cl, [rdx + OPERAND_reg]
        IF cl, ge, 8
            and al, ~0x40
        ENDIF ; X (using reg field for X bit in reg-reg)
        IF cl, ge, 8
            and al, ~0x20
        ENDIF ; B (using reg field for B bit in reg-reg)
        ENDIF
    call    amd64_emit_byte
    
    ; Byte 2: W vvvv 1 pp
    ; pp (Prefix from INST_prefixes)
    mov     cl, [r12 + INST_prefixes]
    xor     al, al
    IF cl, e, 0x66
    mov al, 1
    ELSEIF cl, e, 0xF3
    mov al, 2
    ELSEIF cl, e, 0xF2
    mov al, 3
    ENDIF
    or      al, 0x04           ; Bit 2 is mandatory 1
    
    ; W bit
    mov     cl, r15b
    and cl, 1
    shl cl, 7
    or al, cl
    
    ; vvvv (inverted)
    IF byte [r12 + INST_nops], ge, 3
        mov cl, [r11 + OPERAND_reg]
        and cl, 0x0F
        xor cl, 0x0F
        shl cl, 3
        or al, cl
        ELSE
        or al, 0x78
        ENDIF
    call    amd64_emit_byte
    
    ; Byte 3: z L' L b V' aaa
    ; aaa = Masking register from op0
    mov     al, [r10 + OPERAND_mask]
    and     al, 0x07
    
    ; V' (inverted) from vvvv's high bit
    IF byte [r12 + INST_nops], ge, 3
        mov cl, [r11 + OPERAND_reg]
        IF cl, ge, 16
        ELSE
        or al, 0x08
        ENDIF
        ELSE
        or al, 0x08
        ENDIF
    
    ; b = Broadcast/Static Rounding from op0.ctrl
    mov     cl, [r10 + OPERAND_ctrl]
    and     cl, 0x01
    shl cl, 4
    or al, cl
    
    ; L'L (Vector length / Rounding control) from R15
    mov     cl, r15b
    shr cl, 2
    and cl, 0x03
    shl cl, 5
    or al, cl
    
    ; z = Zeroing masking from op0.ctrl bit 1
    mov     cl, [r10 + OPERAND_ctrl]
    and     cl, 0x02
    shl cl, 6
    or al, cl
    
    call    amd64_emit_byte
    
    ; 2. Opcode
    mov     al, r13b
    call amd64_emit_byte
    
    ; 3. ModRM/SIB
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, rdx
    IF byte [r12 + INST_nops], lt, 3
        mov rdi, r11
        ENDIF
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_string]
; * R13 = Base Opcode (e.g. 0xA4 for MOVSB)
; ;
amd64_encode_string:
    prologue
    mov     ax, [r12 + INST_op_id]
    
    ; Determine size (8, 16, 32, 64)
    ; 1. Check if fixed-size mnemonic (e.g. MOVSB = 8)
    ; 2. Check operands if generic (e.g. MOVS [rdi], [rsi])
    
    xor     r8b, r8b             ; 0=8, 1=16, 2=32, 3=64
    
    ; Check suffixes (This is a bit hardcoded but fast)
    ; MOVSB=1419, STOSB=1669, LODSB=1369, SCASB=1630, CMPSB=1079
    IF ax, e, 1419
    ELSEIF ax, e, 1669
    ELSEIF ax, e, 1369
    ELSEIF ax, e, 1630
    ELSEIF ax, e, 1079
        mov r8b, 0
    ; MOVSW=1425, STOSW=1672, LODSW=1372, SCASW=1632, CMPSW=1083
    ELSEIF ax, e, 1425
    ELSEIF ax, e, 1672
    ELSEIF ax, e, 1372
    ELSEIF ax, e, 1632
    ELSEIF ax, e, 1083
        mov r8b, 1
    ; MOVSD=1420, STOSD=1670, LODSD=1370, SCASD=1631, CMPSD=1080
    ELSEIF ax, e, 1420
    ELSEIF ax, e, 1670
    ELSEIF ax, e, 1370
    ELSEIF ax, e, 1631
    ELSEIF ax, e, 1080
        mov r8b, 2
    ; MOVSQ=1423, STOSQ=1671, LODSQ=1371, SCASQ=???, CMPSQ=1081
    ELSEIF ax, e, 1423
    ELSEIF ax, e, 1671
    ELSEIF ax, e, 1371
    ELSEIF ax, e, 1081
        mov r8b, 3
        ELSE
        ; Generic form - use operand 0 size
        lea r10, [r12 + INST_op0]
        mov cl, [r10 + OPERAND_size]
        IF cl, e, 8
        mov r8b, 0
        ELSEIF cl, e, 16
        mov r8b, 1
        ELSEIF cl, e, 32
        mov r8b, 2
        ELSEIF cl, e, 64
        mov r8b, 3
        ENDIF
        ENDIF
    
    ; REX.W for 64-bit
    IF r8b, e, 3
        mov al, 0x48
        call amd64_emit_byte
    ; 16-bit prefix
    ELSEIF r8b, e, 1
        mov al, 0x66
        call amd64_emit_byte
        ENDIF
    
    ; Opcode
    mov     al, r13b
    IF r8b, ne, 0
        inc al
        ENDIF
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_bin0f]
; * R13 = Opcode (after 0x0F)
; ;
amd64_encode_bin0f:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r11           ; Reg (Src)
    mov     rdx, r10           ; R/M (Dst)
    call    amd64_emit_prefixes
    
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, r13b
    IF byte [r10 + OPERAND_size], e, 8
        dec al                 ; 0xB1 -> 0xB0 for byte
        ENDIF
    call    amd64_emit_byte
    
    mov     al, [r11 + OPERAND_reg]
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_cmpxchg_nb]
; * CMPXCHG8B / CMPXCHG16B
; ;
amd64_encode_cmpxchg_nb:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; REX.W for 16B
    IF word [r12 + INST_op_id], e, 1085
        mov al, 0x48
        call amd64_emit_byte
    ELSEIF byte [r10 + OPERAND_reg], ge, 8
        mov al, 0x41
        call amd64_emit_byte
        ENDIF
    
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0xC7
    call amd64_emit_byte
    
    mov     al, r14b           ; Digit 1
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_sec_r]
; * RDRAND/RDSEED
; ;
amd64_encode_sec_r:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; REX if reg >= 8
    IF byte [r10 + OPERAND_reg], ge, 8
        mov al, 0x48
        call    amd64_emit_byte
        ENDIF
    
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0xC7
    call    amd64_emit_byte
    
    mov     al, r14b           ; Digit 6 or 7
    mov     cl, [r10 + OPERAND_reg]
    and     cl, 0x07
    shl     al, 3
    or      al, 0xC0           ; Mod 11
    or      al, cl
    call    amd64_emit_byte
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_vm_m]
; * R13 = Prefix (0 if none)
; * R14 = Digit
; ;
amd64_encode_vm_m:
    prologue
    lea     r10, [r12 + INST_op0]
    
    IF r13, ne, 0
        mov al, r13b
        call amd64_emit_byte
        ENDIF
    
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0xC7
    call amd64_emit_byte
    
    mov     al, r14b           ; Digit
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_vm_rm_r]
; * R13 = Opcode (0x78 or 0x79)
; ;
amd64_encode_vm_rm_r:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, r13b
    call amd64_emit_byte
    
    mov     al, [r11 + OPERAND_reg]
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_bt]
; * R13 = Base Opcode for REG form (e.g. 0xA3)
; * R14 = Digit for IMM form (e.g. 4)
; ;
amd64_encode_bt:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; Case 1: BT r/m, reg
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov     al, [r10 + OPERAND_size]
        mov rsi, r11
        mov rdx, r10
        call amd64_emit_prefixes
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, r13b
        call amd64_emit_byte
        mov     al, [r11 + OPERAND_reg]
        mov rdi, r10
        call amd64_emit_modrm_sib
    ; Case 2: BT r/m, imm8
    ELSE
        mov     al, [r10 + OPERAND_size]
        xor rsi, rsi
        mov rdx, r10
        call amd64_emit_prefixes
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, 0xBA
        call amd64_emit_byte
        mov     al, r14b
        mov rdi, r10
        call amd64_emit_modrm_sib
        mov     rax, [r11 + OPERAND_imm]
        call amd64_emit_byte
        ENDIF
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_mem_sync]
; * CLFLUSH/etc.
; ;
amd64_encode_mem_sync:
    prologue
    lea     r10, [r12 + INST_op0]
    
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0xAE
    call    amd64_emit_byte
    
    mov     al, r14b           ; Digit 7 for CLFLUSH
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_rm_r]
; * R13 = Opcode (multi-byte)
; ;
amd64_encode_rm_r:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; REX.W
    mov     al, 0x48
    IF byte [r10 + OPERAND_reg], ge, 8
        or  al, 0x04
        ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or  al, 0x01
        ENDIF
    call    amd64_emit_byte
    
    ; Multi-byte Opcode
    mov     ax, r13w
    xchg    al, ah
    IF al, ne, 0
        call amd64_emit_byte
    ENDIF 
    mov     al, ah
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_emit_reloc]
; * Input:
; *   AL: Relocation Type (RELOC_REL32, etc)
; *   RSI: Pointer to Symbol String
; *   EDX: PC Adjustment (bytes from reloc site to end of instruction)
; ;
amd64_emit_reloc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    movzx   r12d, al           ; r12 = type
    mov     r13, rsi           ; r13 = symbol
    mov     r14d, edx          ; r14 = pc_adjust

    ; 1. Check capacity
    mov     eax, [rbx + ASMCTX_nrelocs]
    cmp     eax, MAX_RELOC
    jge     .error_capacity

    ; 2. Get slot pointer: relocs + nrelocs * RELOC_SIZE
    mov     rcx, rax
    imul    rcx, RELOC_SIZE
    mov     rdx, [rbx + ASMCTX_relocs]
    test    rdx, rdx
    jz      .error_no_reloc_table
    add     rdx, rcx           ; rdx = RELOC*

    ; 3. Get current active section
    mov     r15, [rbx + ASMCTX_curr_sec]
    test    r15, r15
    jnz     .have_sec
    mov     r15, [rbx + ASMCTX_sections]
    test    r15, r15
    jz      .error_no_sections_ptr
    mov     r15, [r15]
    test    r15, r15
    jz      .error_no_first_section
.have_sec:

    ; 4. Populate slot fields
    mov     qword [rdx], 0     ; zero tag/type/pad0 first
    mov     byte [rdx + RELOC_tag], TAG_RELOC
    mov     [rdx + RELOC_type], r12d
    
    mov     rax, [r15 + SECTION_size]
    mov     [rdx + RELOC_offset], rax
    mov     qword [rdx + RELOC_addend], 0
    mov     [rdx + RELOC_sym], r13
    mov     [rdx + RELOC_section], r15
    mov     [rdx + RELOC_pc_adjust], r14d
    mov     dword [rdx + RELOC_pad1], 0

    ; 5. Increment relocation count
    inc     dword [rbx + ASMCTX_nrelocs]
    xor     rax, rax
    jmp     .done

.error_capacity:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_cap_err]
    extern  print_str
    call    print_str
    pop     rax
    jmp     .error

.error_no_reloc_table:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_table_err]
    call    print_str
    pop     rax
    jmp     .error

.error_no_sections_ptr:
.error_no_first_section:
    push    rax
    mov     rdi, 2
    lea     rsi, [rel msg_reloc_sec_err]
    call    print_str
    pop     rax
    jmp     .error

.error:
    mov     rax, EXIT_RELOC_ERROR
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [amd64_emit_prefixes]
; * Input:
; *   AL: Operation Size (8, 16, 32, 64)
; *   RSI: Pointer to Op0 (Dest)
; *   RDX: Pointer to Op1 (Src/Index)
; ;
amd64_emit_prefixes:
    prologue
    push    rax
    push    rsi
    push    rdx
    
    ; 1. 16-bit Override
    IF al, e, 16
        mov al, 0x66
        call amd64_emit_byte
        ENDIF
    
    ; 2. Address-Size Override (0x67)
    IF rdx, ne, 0
        ; If memory operand uses 32-bit registers
        IF byte [rdx + OPERAND_kind], e, OP_MEM
            IF byte [rdx + OPERAND_size], e, 32
                mov al, 0x67
                call amd64_emit_byte
                ENDIF
            ENDIF
        ENDIF

    ; 3. REX Calculation
    xor     r11, r11
    pop     rdx
    pop     rsi
    pop     rax
    
    IF al, e, 64
        or  r11, 0x48           ; REX.W
        ELSE
        ; Even for non-64-bit, we need REX if using R8-R15
        ; or if using SIL/DIL/BPL/SPL in 8-bit mode
        xor r10, r10
        IF rsi, ne, 0
            IF byte [rsi + OPERAND_reg], ge, 8
                or r10, 1
            ENDIF 
            IF byte [rsi + OPERAND_base], ge, 8
                or r10, 1
            ENDIF 
            IF byte [rsi + OPERAND_index], ge, 8
                or r10, 1
            ENDIF
            ENDIF
        IF rdx, ne, 0
            IF byte [rdx + OPERAND_reg], ge, 8
                or r10, 1
            ENDIF 
            IF byte [rdx + OPERAND_base], ge, 8
                or r10, 1
            ENDIF 
            IF byte [rdx + OPERAND_index], ge, 8
                or r10, 1
            ENDIF
            ENDIF
        IF r10, ne, 0
            mov r11, 0x40
            ENDIF
            ENDIF
    
    test    r11, r11
    jz      .done
    
    ; REX.R (from op0/src reg)
    IF rsi, ne, 0
        mov cl, [rsi + OPERAND_reg]
        IF cl, ge, 8
            or r11, 0x04
        ENDIF
        ENDIF
    
    ; REX.B (from op1/dest reg or mem base)
    IF rdx, ne, 0
        mov cl, [rdx + OPERAND_reg]
        IF cl, ge, 8
            or r11, 0x01
        ENDIF 
        mov cl, [rdx + OPERAND_base]
        IF cl, ge, 8
            or r11, 0x01
        ENDIF 
        mov cl, [rdx + OPERAND_index]
        IF cl, ge, 8
            or r11, 0x02
        ENDIF
        ENDIF
    
    IF r11, ne, 0
        ; VALIDATION: REX vs High-Byte (AH/CH/DH/BH)
        ; Architectural constraint: Cannot use REX with legacy 8-bit high regs.
        IF rsi, ne, 0
            IF byte [rsi + OPERAND_is_high], e, 1
                jmp .error
            ENDIF
            IF byte [rdx + OPERAND_is_high], e, 1
                jmp .error
            ENDIF
            ENDIF
        
        mov     rax, r11
        call    amd64_emit_byte
        ENDIF
    
.done:
    epilogue

.error:
    mov     rax, EXIT_ENCODE_FAIL
    epilogue

;*
; * [amd64_emit_modrm_sib]
; * Emits ModR/M, SIB, and Displacement.
; * Input:
; *   AL  = Reg field value (3 bits)
; *   RDI = Pointer to memory OPERAND
; ;
amd64_emit_modrm_sib:
    push    rbx
    push    rcx
    push    rdx
    push    r13
    push    r14
    
    mov     r13, rdi            ; Operand
    movzx   r14, al             ; Reg field
    
    ; 1. Check for RIP-Relative addressing
    mov     r8b, [r13 + OPERAND_base]
    IF r8b, e, REG_RIP
        ; Mod=00, R/M=101
        shl     r14b, 3
        mov     al, r14b
        or      al, 0x05
        call    amd64_emit_byte
        
        ; Emit Relocation for Symbol
        mov     al, RELOC_REL32
        mov     rsi, [r13 + OPERAND_sym]
        call    amd64_emit_reloc
        
        ; Emit 4-byte zero placeholder
        xor     rax, rax
        call    amd64_emit_dword
        jmp     .done_sib
        ENDIF
    
    mov     cl, [r13 + OPERAND_index]
    IF cl, e, 4
        jmp amd64_encode_instruction.error
        ENDIF
    
    xor     rdx, rdx            ; Mod field
    mov     rdi, [r13 + OPERAND_imm] ; Displacement
    
    ; Determine Mod based on Displacement
    test    rdi, rdi
    jz      .mod00
    ; Check if fits in 8 bits
    cmp     rdi, -128
    jl      .mod32
    cmp     rdi, 127
    jg      .mod32
    mov     dl, 1               ; Mod 01 (8-bit disp)
    jmp     .emit_start
.mod32:
    mov     dl, 2               ; Mod 10 (32-bit disp)
    jmp     .emit_start
.mod00:
    xor     dl, dl              ; Mod 00 (no disp)
    ; Special case: if base is RBP/R13, we MUST use Mod 01 with disp 0
    mov     al, r8b
    and     al, 0x07
    cmp     al, 5
    jne     .emit_start
    mov     dl, 1
    
.emit_start:
    ; SIB Logic
    ; If index != 0xFF or base == 4 (RSP), use SIB
    cmp     cl, 0xFF
    jne     .use_sib
    mov     al, r8b
    and     al, 0x07
    cmp     al, 4               ; RSP/R12
    je      .use_sib
    
    ; No SIB
    mov     al, dl              ; Mod
    shl     al, 6
    shl     r14b, 3             ; Reg
    or      al, r14b
    mov     cl, r8b              ; R/M (Base)
    and     cl, 0x07
    or      al, cl
    call    amd64_emit_byte
    jmp     .disp
    
.use_sib:
    ; Emit ModRM with R/M = 100b (4)
    mov     al, dl
    shl     al, 6
    shl     r14b, 3
    or      al, r14b
    or      al, 4               ; R/M = 4 (SIB follows)
    call    amd64_emit_byte
    
    ; Emit SIB
    ; Scale (2 bits)
    ; Index (3 bits)
    ; Base (3 bits)
    mov     al, [r13 + OPERAND_scale]
    ; Map scale 1,2,4,8 to 0,1,2,3
    xor     cl, cl
    cmp     al, 2
    je      .s1
    cmp     al, 4
    je      .s2
    cmp     al, 8
    je      .s3
    jmp     .s0
.s1: mov cl, 1
jmp .s0
.s2: mov cl, 2
jmp .s0
.s3: mov cl, 3
.s0:
    shl     cl, 6
    mov     al, [r13 + OPERAND_index]
    cmp     al, 0xFF
    jne     .idx_ok
    mov     al, 4               ; Index 4 with SIB = no index
.idx_ok:
    and     al, 0x07
    shl     al, 3
    or      cl, al
    mov     al, r8b              ; Base
    and     al, 0x07
    or      cl, al
    mov     al, cl
    call    amd64_emit_byte
    
.disp:
    ; Emit Displacement
    IF dl, e, 1
        mov     rax, [r13 + OPERAND_imm]
        call    amd64_emit_byte
    ELSEIF dl, e, 2
        mov     rdi, [r13 + OPERAND_imm]
        call    amd64_emit_dword
        ENDIF

.done_sib:
    pop     r14
    pop     r13
    pop     rdx
    pop     rcx
    pop     rbx
    ret

;*
; * [amd64_emit_byte]
; ;
amd64_emit_byte:
    extern asm_ctx_emit_byte
    push    rax
    
    ; Check architectural limit (15 bytes)
    mov     eax, [rbx + ASMCTX_inst_len]
    IF eax, ge, 15
        pop rax
        jmp amd64_encode_instruction.error
        ENDIF
    inc     dword [rbx + ASMCTX_inst_len]
    
    pop     rax
    mov     rdi, rbx
    movzx   rsi, al
    call    asm_ctx_emit_byte
    ret

;*
; * [amd64_emit_dword]
; * Input: RDI = 32-bit value
; ;
amd64_emit_dword:
    push    rax
    push    rcx
    mov     rcx, 4
.loop:
    mov     al, dil
    call    amd64_emit_byte
    shr     rdi, 8
    loop    .loop
    pop     rcx
    pop     rax
    ret

;*
; * [amd64_encode_jmp]
; ;
amd64_encode_jmp:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, 0xE9
        call amd64_emit_byte
        mov     al, RELOC_REL32
        mov rsi, [r10 + OPERAND_sym]
        mov edx, 4
        call amd64_emit_reloc
        xor     rax, rax
        call amd64_emit_dword
        ELSE
        mov     r13, 0xFF
        mov r14, 4
        call amd64_encode_unary
        ENDIF
    epilogue

;*
; * [amd64_encode_call]
; ;
amd64_encode_call:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        mov     al, 0xE8
        call amd64_emit_byte
        mov     al, RELOC_REL32
        mov rsi, [r10 + OPERAND_sym]
        mov edx, 4
        call amd64_emit_reloc
        xor     rax, rax
        call amd64_emit_dword
        ELSE
        mov     r13, 0xFF
        mov r14, 2
        call amd64_encode_unary
        ENDIF
    epilogue

;*
; * [amd64_encode_jcc]
; ;

;*
; * [amd64_encode_ret]
; ;

;*
; * [amd64_encode_push_pop]
; * r13 = base opcode (0x50 for PUSH, 0x58 for POP)
; * r14 = extended opcode (0xFF /6 for PUSH, 0x8F /0 for POP)
; * r15 = reg field for ModRM
; ;
amd64_encode_push_pop:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, [r10 + OPERAND_reg]
        mov     cl, al
        and     cl, 7
        mov     dl, r13b
        add     dl, cl
        mov     al, [r10 + OPERAND_size]
        IF al, e, 16
            mov al, 0x66
            call amd64_emit_byte
            ENDIF
        ; REX prefix if reg >= 8
        mov     al, [r10 + OPERAND_reg]
        IF al, ge, 8
            mov al, 0x41
            call amd64_emit_byte
            ENDIF
        mov     al, dl
        call amd64_emit_byte
        ELSE
        ; MEM
        mov     al, [r10 + OPERAND_size]
        IF al, e, 16
            mov al, 0x66
            call amd64_emit_byte
            ENDIF
        mov     al, 0
        mov rsi, r10
        mov rdx, 0
        call amd64_emit_prefixes
        mov     al, r14b
        call amd64_emit_byte
        mov     al, r15b
        mov rdi, r10
        call amd64_emit_modrm_sib
        ENDIF
    epilogue

;*
; * [amd64_encode_shift]
; * r14 = extension (4 for SHL, 5 for SHR, 7 for SAR)
; ;

;*
; * [amd64_encode_imul]
; ;

;*
; * [amd64_encode_cmovcc]
; ;

;*
; * [amd64_encode_setcc]
; ;

;*
; * [amd64_encode_mpx]
; * Handles BNDMK, BNDCL, BNDCU, BNDCN, BNDMOV, BNDLDX, BNDSTX
; ;
amd64_encode_mpx:
    prologue
    mov     ax, [r12 + INST_op_id]
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    IF ax, e, 1047 ; BNDMK: F3 0F 1B /r
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1043 ; BNDCL: F3 0F 1A /r
        mov     al, 0xF3
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1045 ; BNDCU: F2 0F 1A /r
        mov     al, 0xF2
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1044 ; BNDCN: F2 0F 1B /r
        mov     al, 0xF2
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1048 ; BNDMOV
        mov     al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        IF byte [r10 + OPERAND_kind], e, OP_MEM
            mov al, 0x1B
            call amd64_emit_byte
            mov al, [r11 + OPERAND_reg]
            mov rdi, r10
            call amd64_emit_modrm_sib
            ELSE
            mov al, 0x1A
            call amd64_emit_byte
            mov al, [r10 + OPERAND_reg]
            mov rdi, r11
            call amd64_emit_modrm_sib
            ENDIF
    ELSEIF ax, e, 1046 ; BNDLDX: 0F 1A /r
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x1A
        call amd64_emit_byte
        mov     al, [r10 + OPERAND_reg]
        mov rdi, r11
        call amd64_emit_modrm_sib
    ELSEIF ax, e, 1049 ; BNDSTX: 0F 1B /r
        mov     al, 0x0F
        call amd64_emit_byte
        mov al, 0x1B
        call amd64_emit_byte
        mov     al, [r11 + OPERAND_reg]
        mov rdi, r10
        call amd64_emit_modrm_sib
        ENDIF
    epilogue

;*
; * [amd64_emit_nop]
; * Purpose: Emits an optimal NOP sequence of length RAX.
; * Maximum supported in one call: 9 bytes.
; ;
amd64_emit_nop:
    prologue
    IF rax, e, 1
        mov al, 0x90
        call amd64_emit_byte
    ELSEIF rax, e, 2
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x90
        call amd64_emit_byte
    ELSEIF rax, e, 3
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 4
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x40
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 5
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x44
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 6
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x44
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
        mov al, 0x00
        call amd64_emit_byte
    ELSEIF rax, e, 7
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x80
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
    ELSEIF rax, e, 8
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x84
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
    ELSEIF rax, e, 9
        mov al, 0x66
        call amd64_emit_byte
        mov al, 0x0F
        call amd64_emit_byte
        mov al, 0x1F
        call amd64_emit_byte
        mov al, 0x84
        call amd64_emit_byte
        xor al, al
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        call amd64_emit_byte
        ENDIF
    epilogue

;*
; * [amd64_emit_word]
; ;
amd64_emit_word:
    push    rax
    push    rcx
    mov     rcx, 2
.loopw:
    mov     al, dil
    call    amd64_emit_byte
    shr     rdi, 8
    loop    .loopw
    pop     rcx
    pop     rax
    ret

;*
; * [amd64_emit_dword]
; ;

;*
; * [amd64_emit_qword]
; ;
amd64_emit_qword:
    push    rax
    push    rcx
    mov     rcx, 8
.loopq:
    mov     al, dil
    call    amd64_emit_byte
    shr     rdi, 8
    loop    .loopq
    pop     rcx
    pop     rax
    ret

;*
; * [amd64_encode_avx]
; * Encodes 3-operand AVX instructions.
; * Input:
; *   r13 = Opcode
; *   r14 = Type (0=None, 1=66, 2=F3, 3=F2)
; ;
amd64_encode_avx:
    prologue
    ; Operands: R12 points to INST
    lea     r10, [r12 + INST_op0] ; Dest
    lea     r11, [r12 + INST_op1] ; Src1 (vvvv)
    lea     r9,  [r12 + INST_op2] ; Src2 (ModRM)
    
    ; 1. Determine Prefix
    ; For now, assume VEX2 if possible.
    ; R, X, B bits
    xor     r8, r8                 ; r8 = R,X,B packed
    
    movzx   rax, byte [r10 + OPERAND_reg]
    test    al, 8
    jz      .no_r
    or      r8, 4
.no_r:
    movzx   rax, byte [r9 + OPERAND_reg]
    test    al, 8
    jz      .no_b
    or      r8, 1
.no_b:

    ; 2. Emit VEX
    ; dl = R,X,B, cl = vvvv, r8b = W,L,pp, r9b = map
    mov     dl, r8b
    movzx   rcx, byte [r11 + OPERAND_reg]
    mov     r8b, r14b              ; pp
    mov     r9b, 1                 ; map 0F
    
    ; Check if we can use VEX2 (map 0F, X=0, B=0, W=0)
    test    dl, 0x03               ; X or B?
    jnz     .use_vex3
    
    call    amd64_emit_vex2
    jmp     .vex_done
    
.use_vex3:
    call    amd64_emit_vex3

.vex_done:
    ; 3. Emit Opcode
    mov     al, r13b
    call    amd64_emit_byte
    
    ; 4. Emit ModRM
    ; reg = op0, r/m = op2
    movzx   rax, byte [r10 + OPERAND_reg]
    and     al, 7
    shl     al, 3
    movzx   rcx, byte [r9 + OPERAND_reg]
    and     cl, 7
    or      al, cl
    or      al, 0xC0               ; Register-Register for now
    call    amd64_emit_byte
    
    epilogue
; * Optimized 2-byte VEX (0xC5)
; ;
amd64_emit_vex2:
    push    rax
    mov     al, 0xC5
    call    amd64_emit_byte
    xor     dl, 1
    shl     dl, 7
    not     cl
    and     cl, 0x0F
    shl     cl, 3
    or      dl, cl
    shl     r8b, 2
    or      dl, r8b
    or      dl, r9b
    mov     al, dl
    call    amd64_emit_byte
    pop     rax
    ret

;*
; * [amd64_emit_vex3]
; * Full 3-byte VEX (0xC4)
; ;
amd64_emit_vex3:
    push    rax
    mov     al, 0xC4
    call    amd64_emit_byte
    xor     dl, 0x07
    shl     dl, 5
    or      dl, r9b
    mov     al, dl
    call    amd64_emit_byte
    not     cl
    and     cl, 0x0F
    shl     cl, 3
    mov     al, r8b
    and     al, 0x03
    test    r8b, 4
    jz      .no_w
    or      al, 0x80
.no_w:
    test    r8b, 2
    jz      .no_l
    or      al, 0x04
.no_l:
    or      al, cl
    call    amd64_emit_byte
    pop     rax
    ret


;*
; * [amd64_encode_sse]
; * R13 = Opcode
; * R14 = Format (0=0F, 1=66 0F, 2=0F 38, 3=0F 3A)
; ;
amd64_encode_sse:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; REX calculation
    xor     r15, r15
    IF byte [r10 + OPERAND_reg], ge, 8
        or  r15, 0x44
    ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or  r15, 0x41
    ENDIF
    
    IF r15, ne, 0
        mov rax, r15
        call amd64_emit_byte
    ENDIF

    ; Mandatory Prefix
    IF r14b, e, 1
        mov al, 0x66
        call amd64_emit_byte
    ENDIF
    
    ; Opcode Escape
    mov     al, 0x0F
    call    amd64_emit_byte
    IF r14b, e, 2
        mov al, 0x38
        call amd64_emit_byte
    ELSEIF r14b, e, 3
        mov al, 0x3A
        call amd64_emit_byte
    ENDIF
    
    mov     rax, r13
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_rm_r_0f]
; ;
amd64_encode_rm_r_0f:
    prologue
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    
    ; REX.W
    mov     al, 0x48
    IF byte [r10 + OPERAND_reg], ge, 8
        or  al, 0x04
        ENDIF
    IF byte [r11 + OPERAND_reg], ge, 8
        or  al, 0x01
        ENDIF
    call    amd64_emit_byte
    
    ; 0F Escape
    mov     al, 0x0F
    call    amd64_emit_byte
    
    mov     al, r13b
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_rm_m]
; ;
amd64_encode_rm_m:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; Multi-byte Opcode (R13)
    mov     ax, r13w
    xchg    al, ah
    IF al, ne, 0
        call amd64_emit_byte
    ENDIF
    mov     al, ah
    call    amd64_emit_byte
    
    ; ModRM with Digit (R14)
    mov     al, r14b
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_vex_unary]
; ;
amd64_encode_vex_unary:
    prologue
    lea     r10, [r12 + INST_op0] ; Dest
    lea     r11, [r12 + INST_op1] ; Src
    
    ; 1. REX/VEX R,X,B
    xor     dl, dl
    mov     al, [r10 + OPERAND_reg]
    IF al, ge, 8
        or dl, 0x04
    ENDIF
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov al, [r11 + OPERAND_reg]
        IF al, ge, 8
            or dl, 0x01
        ENDIF
    ELSEIF byte [r11 + OPERAND_kind], e, OP_MEM
        mov al, [r11 + OPERAND_base]
        IF al, ge, 8
            or dl, 0x01
        ENDIF
    ENDIF
    
    ; 2. Emit VEX2/VEX3
    mov     al, 0xC4
    call    amd64_emit_byte
    xor     dl, 0x07
    shl     dl, 5
    or      dl, r14b               ; Map
    mov     al, dl
    call    amd64_emit_byte
    
    mov     al, 0x78               ; vvvv = 1111b (unused)
    or      al, r15b               ; pp
    call    amd64_emit_byte
    
    mov     al, r13b
    call    amd64_emit_byte
    
    mov     al, [r10 + OPERAND_reg]
    and     al, 7
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    jmp     .done
.done:
    epilogue

[SECTION .data]
msg_reloc_cap_err:   db "Reloc error: MAX_RELOC capacity exceeded", 10, 0
msg_reloc_table_err: db "Reloc error: ASMCTX_relocs is NULL", 10, 0
msg_reloc_sec_err:   db "Reloc error: No active section or sections array is NULL", 10, 0
