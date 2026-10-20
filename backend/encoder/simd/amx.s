;
; ============================================================================
; File        : backend/encoder/simd/amx.s
; Project     : utasm
; Description : AMX's operand rule (amd64): the tile dot products.
;
;   tdpbssd / tdpbsud / tdpbusd / tdpbuud, tdpbf16ps, tdpfp16ps, tdpbf8ps /
;   tdpbhf8ps / tdphbf8ps / tdphf8ps, tcmmimfp16ps / tcmmrlfp16ps: their
;   three tile registers must all differ (Intel: #UD otherwise). NASM takes
;   "tdpbf16ps tmm1, tmm1, tmm2"; GNU's as and utasm do not. The forms
;   themselves are the table's (tables/opcode.s).
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

[SECTION .rodata]
align 2
amx_dot_ids:
    dw 1686, 1687, 1688, 1689, 1690        ; tdpbf16ps, tdpbssd .. tdpbuud
    dw 7660, 7661                          ; tcmmimfp16ps, tcmmrlfp16ps
    dw 7667, 7668, 7669, 7670, 7671        ; tdpbf8ps, tdpbhf8ps, tdpfp16ps,
                                           ; tdphbf8ps, tdphf8ps
amx_dot_end:

[SECTION .text]

;*
; * [amd64_amx_check]
; * Purpose: A tile dot product with a tile register twice?
; * Input  : R12 = INST
; * Output : RAX = OK or EXIT_TMM_SAME. Preserves all but rax, rcx, rdx.
; ;
global amd64_amx_check
amd64_amx_check:
    xor     eax, eax
    cmp     byte [r12 + INST_nops], 3
    jne     .ret
    movzx   ecx, word [r12 + INST_op_id]
    lea     rdx, [rel amx_dot_ids]
.find:
    lea     rax, [rel amx_dot_end]
    cmp     rdx, rax
    jae     .ok
    cmp     cx, [rdx]
    je      .dot
    add     rdx, 2
    jmp     .find
.dot:
    ; three registers: op0 / op1 / op2's numbers, each against the others
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .ok
    cmp     byte [r12 + INST_op0 + OPERAND_SIZE + OPERAND_kind], OP_REG
    jne     .ok
    cmp     byte [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_kind], OP_REG
    jne     .ok
    mov     cl, [r12 + INST_op0 + OPERAND_reg]
    mov     dl, [r12 + INST_op0 + OPERAND_SIZE + OPERAND_reg]
    cmp     cl, dl
    je      .same
    cmp     cl, [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_reg]
    je      .same
    cmp     dl, [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_reg]
    je      .same
.ok:
    xor     eax, eax
.ret:
    ret
.same:
    mov     eax, EXIT_TMM_SAME
    ret
