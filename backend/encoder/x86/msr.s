;
; ============================================================================
; File        : backend/encoder/x86/msr.s
; Project     : utasm
; Description : The MSR forms with operands (amd64): MSR_IMM, USER_MSR.
;
;   rdmsr   r64, imm32      VEX.128.F2.M7.W0 F6 /0 id
;   wrmsrns imm32, r64      VEX.128.F3.M7.W0 F6 /0 id
;   urdmsr  r64, r64        F2 0F 38 F8 /r      (rm: the first, reg: the second)
;   urdmsr  r64, imm32      VEX.128.F2.M7.W0 F8 /0 id
;   uwrmsr  r64, r64        F3 0F 38 F8 /r      (reg: the first, rm: the second)
;   uwrmsr  imm32, r64      VEX.128.F3.M7.W0 F8 /0 id  (NASM's r64, imm32 too)
;   With r16-r31 (APX): the VEX forms as EVEX map 7, the 0F 38 ones as
;   EVEX map 4 - as GNU's as 2.47 writes them. rdmsr and wrmsrns with no
;   operands are the old ones (0F 32, 0F 01 C6), encoded elsewhere.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern  amd64_emit_byte, amd64_emit_dword, amd64_rex2_at

%define ID_RDMSR    1596
%define ID_WRMSRNS  7487
%define ID_URDMSR   7655
%define ID_UWRMSR   7656

[SECTION .text]

;*
; * [amd64_msr_claim]
; * Purpose: Is the instruction one of the forms above (an MSR one with
; *   operands)?
; * Input  : R12 = INST
; * Output : ZF = 1: it is (amd64_encode_msr writes it)
; ;
global amd64_msr_claim
amd64_msr_claim:
    cmp     byte [r12 + INST_nops], 0
    je      .no
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, ID_RDMSR
    je      .ret
    cmp     eax, ID_WRMSRNS
    je      .ret
    cmp     eax, ID_URDMSR
    je      .ret
    cmp     eax, ID_UWRMSR
    ret
.no:
    test    esp, esp
.ret:
    ret

;*
; * [amd64_encode_msr]
; * Input  : RBX = AsmCtx, R12 = INST (amd64_msr_claim took it)
; * Output : RAX = OK or EXIT_ENCODE_FAIL (no such form)
; ;
global amd64_encode_msr
amd64_encode_msr:
    push    r13
    push    r14
    push    r15
    cmp     byte [r12 + INST_nops], 2
    jne     .bad
    movzx   r15d, word [r12 + INST_op_id]
    lea     r13, [r12 + INST_op0]
    lea     r14, [r12 + INST_op0 + OPERAND_SIZE]
    ; the immediate first (wrmsrns, uwrmsr): the register is the other
    cmp     byte [r13 + OPERAND_kind], OP_IMM
    jne     .reg_first
    cmp     r15d, ID_WRMSRNS
    je      .swap
    cmp     r15d, ID_UWRMSR
    jne     .bad
.swap:
    xchg    r13, r14
    jmp     .imm_form
.reg_first:
    call    .gpr64                         ; r13: a 64-bit register
    jne     .bad
    cmp     byte [r14 + OPERAND_kind], OP_IMM
    je      .reg_imm
    ; r64, r64: urdmsr / uwrmsr only
    xchg    r13, r14
    call    .gpr64
    xchg    r13, r14
    jne     .bad
    cmp     r15d, ID_URDMSR
    je      .rr
    cmp     r15d, ID_UWRMSR
    jne     .bad
    xchg    r13, r14                       ; uwrmsr: reg the first, rm the second
.rr:
    ; r13: the rm, r14: the reg; pp F2 (urdmsr) / F3 (uwrmsr)
    movzx   r8d, byte [r13 + OPERAND_reg]
    movzx   r9d, byte [r14 + OPERAND_reg]
    mov     r10d, 3                        ; pp: F2
    cmp     r15d, ID_URDMSR
    je      .rr_pp
    mov     r10d, 2                        ; F3
.rr_pp:
    mov     eax, r8d
    or      eax, r9d
    test    eax, 16
    jnz     .rr_evex
    ; F2 / F3, REX (R: the reg, B: the rm), 0F 38 F8 /r
    mov     al, 0xF2
    cmp     r10d, 3
    je      .rr_legacy_pp
    mov     al, 0xF3
.rr_legacy_pp:
    call    amd64_emit_byte
    xor     eax, eax
    test    r9d, 8
    jz      .rr_no_r
    or      eax, 4
.rr_no_r:
    test    r8d, 8
    jz      .rr_no_b
    or      eax, 1
.rr_no_b:
    test    eax, eax
    jz      .rr_opc
    or      al, 0x40
    call    amd64_emit_byte
.rr_opc:
    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, 0x38
    call    amd64_emit_byte
    jmp     .rr_f8
.rr_evex:
    ; EVEX map 4: 62, R3' X3' B3' R4' B4 100, W0 1111 1 pp, 08 (the EVEX
    ; carries r16-r31: no REX2 wanted, mode.s)
    mov     qword [rel amd64_rex2_at], -2
    mov     al, 0x62
    call    amd64_emit_byte
    mov     eax, 0xE0 | 0x10 | 4           ; R3' X3' B3' R4' set: none
    test    r9d, 8
    jz      .e4_r3
    and     al, ~0x80
.e4_r3:
    test    r8d, 8
    jz      .e4_b3
    and     al, ~0x20
.e4_b3:
    test    r9d, 16
    jz      .e4_r4
    and     al, ~0x10
.e4_r4:
    test    r8d, 16
    jz      .e4_b4
    or      al, 0x08
.e4_b4:
    call    amd64_emit_byte
    mov     eax, 0x7C
    or      eax, r10d
    call    amd64_emit_byte
    mov     al, 0x08
    call    amd64_emit_byte
.rr_f8:
    mov     al, 0xF8
    call    amd64_emit_byte
    mov     eax, r9d
    and     eax, 7
    shl     eax, 3
    mov     ecx, r8d
    and     ecx, 7
    or      eax, ecx
    or      al, 0xC0
    call    amd64_emit_byte
    jmp     .ok

.reg_imm:
    ; rdmsr r64, imm / urdmsr r64, imm / uwrmsr r64, imm (NASM's order)
    cmp     r15d, ID_WRMSRNS
    je      .bad
.imm_form:
    ; r13: the register, r14: the immediate
    call    .gpr64
    jne     .bad
    mov     rax, [r14 + OPERAND_imm]
    mov     rcx, 0xFFFFFFFF
    cmp     rax, rcx
    ja      .bad                           ; (an MSR's number: 32 bits)
    mov     r10d, 3                        ; pp: F2 (rdmsr, urdmsr)
    cmp     r15d, ID_WRMSRNS
    je      .f3
    cmp     r15d, ID_UWRMSR
    jne     .pp_set
.f3:
    mov     r10d, 2                        ; F3 (wrmsrns, uwrmsr)
.pp_set:
    mov     r9d, 0xF6                      ; rdmsr / wrmsrns
    cmp     r15d, ID_URDMSR
    je      .f8
    cmp     r15d, ID_UWRMSR
    jne     .opc_set
.f8:
    mov     r9d, 0xF8
.opc_set:
    movzx   r8d, byte [r13 + OPERAND_reg]
    test    r8d, 16
    jnz     .imm_evex
    ; C4, R X B 00111, W0 1111 0 pp
    mov     al, 0xC4
    call    amd64_emit_byte
    mov     eax, 0xE7
    test    r8d, 8
    jz      .v_b
    and     al, ~0x20
.v_b:
    call    amd64_emit_byte
    mov     eax, 0x78
    or      eax, r10d
    call    amd64_emit_byte
    jmp     .imm_opc
.imm_evex:
    ; EVEX map 7: 62, R3' X3' B3' R4' B4 111, W0 1111 1 pp, 08
    mov     qword [rel amd64_rex2_at], -2
    mov     al, 0x62
    call    amd64_emit_byte
    mov     eax, 0xF7
    test    r8d, 8
    jz      .ev_b3
    and     al, ~0x20
.ev_b3:
    or      al, 0x08                       ; B4 (r16-r31)
    call    amd64_emit_byte
    mov     eax, 0x7C
    or      eax, r10d
    call    amd64_emit_byte
    mov     al, 0x08
    call    amd64_emit_byte
.imm_opc:
    mov     eax, r9d
    call    amd64_emit_byte
    mov     eax, r8d
    and     eax, 7
    or      al, 0xC0                       ; /0
    call    amd64_emit_byte
    mov     edi, [r14 + OPERAND_imm]
    call    amd64_emit_dword
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_ENCODE_FAIL
.ret:
    pop     r15
    pop     r14
    pop     r13
    ret

; .gpr64: ZF = 1 when r13 is a 64-bit general register (rax-r15, r16-r31)
.gpr64:
    cmp     byte [r13 + OPERAND_kind], OP_REG
    jne     .gpr_ret
    cmp     byte [r13 + OPERAND_reg], 32
    jae     .gpr_no
    cmp     byte [r13 + OPERAND_size], 64
.gpr_ret:
    ret
.gpr_no:
    test    esp, esp
    ret
