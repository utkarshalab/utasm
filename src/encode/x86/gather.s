;
; ============================================================================
; File        : src/encode/x86/gather.s
; Project     : utasm
; Description : The gathers' operand rule (amd64).
;
;   A gather's destination, its memory's vector index and (VEX: AVX2's)
;   mask register must all differ: Intel's #UD otherwise, whatever the
;   registers' widths ("vpgatherqd xmm1, [rax + ymm1*4], xmm2" too). The
;   EVEX forms' mask is a k register: only the destination and the index
;   there. NASM takes them; GNU's as warns; utasm refuses. A gather is
;   told by its shape - a vector register, then memory with a vector index
;   - so every gather the table has is covered; scatters and the
;   AVX512PF prefetches (the memory first) are not gathers.
;
;   The EVEX gathers, the scatters and the AVX512PF prefetches all need a
;   write mask, {k1} to {k7}: k0 (none written) is #UD too - GNU's as
;   refuses them, NASM takes them.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"
%include "src/include/arch/amd64.inc"          ; (REG_ZMM0: the parser's 80)

DEFAULT REL

[SECTION .text]

;*
; * [amd64_gather_check]
; * Purpose: A gather with its destination, index and mask not distinct?
; * Input  : R12 = INST
; * Output : RAX = OK, EXIT_GATHER_SAME or EXIT_VSIB_NO_MASK. Preserves all
; *          but rax, rcx, rdx.
; ;
global amd64_gather_check
amd64_gather_check:
    ; memory with a vector index, as op0 or op1, of an EVEX form (VEX's
    ; gathers have three operands): op0 has the mask
    movzx   ecx, byte [r12 + INST_nops]
    test    ecx, ecx
    jz      .ok
    cmp     ecx, 3
    jae     .regs
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_MEM
    jne     .op1
    cmp     byte [r12 + INST_op0 + OPERAND_vsib], 0
    jne     .masked
.op1:
    cmp     ecx, 2
    jb      .ok
    cmp     byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_kind], OP_MEM
    jne     .regs
    cmp     byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_vsib], 0
    je      .regs
.masked:
    cmp     byte [r12 + INST_op0 + OPERAND_mask], 0
    je      .no_mask
.regs:
    xor     eax, eax
    cmp     byte [r12 + INST_nops], 2
    jb      .ret
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .ret
    movzx   ecx, byte [r12 + INST_op0 + OPERAND_reg]
    sub     ecx, REG_ZMM0                  ; (xmm / ymm / zmm n: REG_ZMM0 + n)
    cmp     ecx, 32
    jae     .ret
    cmp     byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_kind], OP_MEM
    jne     .ret
    cmp     byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_vsib], 0
    je      .ret
    movzx   edx, byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_index]
    sub     edx, REG_ZMM0
    cmp     ecx, edx
    je      .same
    ; VEX: the mask, a vector register too
    cmp     byte [r12 + INST_nops], 3
    jne     .ret
    cmp     byte [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_kind], OP_REG
    jne     .ret
    movzx   eax, byte [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_reg]
    sub     eax, REG_ZMM0
    cmp     eax, ecx
    je      .same
    cmp     eax, edx
    je      .same
.ok:
    xor     eax, eax
.ret:
    ret
.no_mask:
    mov     eax, EXIT_VSIB_NO_MASK
    ret
.same:
    mov     eax, EXIT_GATHER_SAME
    ret
