;
; ============================================================================
; File        : backend/encoder/apx.s
; Project     : utasm
; Description : APX's EVEX-encoded integer instructions (map 4).
;
;   62  P0 = R3' X3' B3' R4' B4 1 0 0          (' inverted)
;       P1 = W vvvv' X4' pp
;       P2 = 0 0 0 ND V4' NF 0 0
;   opcode ModRM [SIB] [disp] [imm]
;
;   vvvv is the new data destination ("add rax, rbx, rcx"); NF ({nf})
;   keeps the flags. amd64_apx_claim says, before the legacy checks,
;   whether an instruction is one of these; amd64_apx_encode writes it
;   once the legacy prefixes are out (backend/encoder/encoder.s). Forms
;   and bytes are NASM 3's.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  asm_bits
extern  amd64_emit_byte, amd64_emit_word, amd64_emit_dword
extern  amd64_emit_modrm_sib
extern  amd64_rex2_at, amd64_disp8n
extern  gas_names

%define AK_ALU      1               ; add or adc sbb and sub xor
%define AK_UNARY    2               ; inc dec neg not (opcode: the 8-bit one)
%define AK_SHIFT    3               ; rol .. sar (/digit)
%define AK_SHXD     4               ; shld shrd (opcode: the imm8 one; cl + 0x81)
%define AK_IMUL     5
%define AK_MULDIV   6               ; mul div idiv: F6 / F7 /digit
%define AK_CMOV     7               ; cmovcc: 40 + cc (NDD)
%define AK_CFCMOV   8               ; cfcmovcc: 40 + cc
%define AK_SETCC    9               ; setcc: 40 + cc, F2
%define AK_ADX      10              ; adcx adox: 66 (pp)
%define AK_CNT      11              ; popcnt lzcnt tzcnt
%define AK_MOVBE    12              ; 60 (r, m) / 61 (r/m, r)
%define AK_CRC32    13              ; F0 (r/m8) / F1
%define AK_REGMEM   14              ; r64, m (W 1): invept .. enqcmds, movdir64b
%define AK_MEMREG   15              ; m, r: movdiri, wrss, wruss
%define AK_CCMP     16              ; ccmpscc: 38 .. 3B, 80 / 81 / 83 /7
%define AK_CTEST    17              ; ctestscc: 84 / 85, F6 / F7 /0
%define AK_PUSH2    18              ; push2 (FF /6), pop2 (8F /0); /digit field: W
%define AK_PUSHP    19              ; pushp / popp: REX2.W 50+r / 58+r
%define AK_JMPABS   20              ; REX2 A1 imm64

%define AF_NF       0x01            ; {nf} allowed
%define AF_NDD      0x02            ; a new data destination form
%define AF_ZU       0x04            ; {zu} allowed (ND)
%define AF_ONLY     0x10            ; APX's own: always EVEX
%define AF_EGPR     0x08            ; no REX2 form: EVEX when r16-r31 appear

[SECTION .rodata]
; dw first id, last id; db kind, opcode, /digit, pp, flags, the NDD
; form's operand count, 0, 0
%macro apx 8
    dw %1, %2
    db %3, %4, %5, %6, %7, %8, 0, 0
%endmacro
apx_table:
    apx 1006, 1006, AK_ALU, 0x00, 0, 0, AF_NF | AF_NDD, 3     ; add
    apx 1442, 1442, AK_ALU, 0x08, 1, 0, AF_NF | AF_NDD, 3     ; or
    apx 1004, 1004, AK_ALU, 0x10, 2, 0, AF_NDD, 3             ; adc
    apx 1628, 1628, AK_ALU, 0x18, 3, 0, AF_NDD, 3             ; sbb
    apx 1028, 1028, AK_ALU, 0x20, 4, 0, AF_NF | AF_NDD, 3     ; and
    apx 1676, 1676, AK_ALU, 0x28, 5, 0, AF_NF | AF_NDD, 3     ; sub
    apx 2157, 2157, AK_ALU, 0x30, 6, 0, AF_NF | AF_NDD, 3     ; xor
    apx 1278, 1278, AK_UNARY, 0xFE, 0, 0, AF_NF | AF_NDD, 2   ; inc
    apx 1118, 1118, AK_UNARY, 0xFE, 1, 0, AF_NF | AF_NDD, 2   ; dec
    apx 1439, 1439, AK_UNARY, 0xF6, 3, 0, AF_NF | AF_NDD, 2   ; neg
    apx 1441, 1441, AK_UNARY, 0xF6, 2, 0, AF_NDD, 2           ; not
    apx 1612, 1612, AK_SHIFT, 0, 0, 0, AF_NF | AF_NDD, 3      ; rol
    apx 1613, 1613, AK_SHIFT, 0, 1, 0, AF_NF | AF_NDD, 3      ; ror
    apx 1590, 1590, AK_SHIFT, 0, 2, 0, AF_NF | AF_NDD, 3      ; rcl
    apx 1593, 1593, AK_SHIFT, 0, 3, 0, AF_NF | AF_NDD, 3      ; rcr
    apx 1647, 1647, AK_SHIFT, 0, 4, 0, AF_NF | AF_NDD, 3      ; shl
    apx 1624, 1624, AK_SHIFT, 0, 4, 0, AF_NF | AF_NDD, 3      ; sal
    apx 1650, 1650, AK_SHIFT, 0, 5, 0, AF_NF | AF_NDD, 3      ; shr
    apx 1625, 1625, AK_SHIFT, 0, 7, 0, AF_NF | AF_NDD, 3      ; sar
    apx 1648, 1648, AK_SHXD, 0x24, 0, 0, AF_NF | AF_NDD, 4    ; shld
    apx 1651, 1651, AK_SHXD, 0x2C, 0, 0, AF_NF | AF_NDD, 4    ; shrd
    apx 1276, 1276, AK_IMUL, 0, 5, 0, AF_NF | AF_ZU, 0        ; imul (NDD: claim)
    apx 1432, 1432, AK_MULDIV, 0xF6, 4, 0, AF_NF, 0           ; mul
    apx 1119, 1119, AK_MULDIV, 0xF6, 6, 0, AF_NF, 0           ; div
    apx 1275, 1275, AK_MULDIV, 0xF6, 7, 0, AF_NF, 0           ; idiv
    apx 4000, 4015, AK_CMOV, 0x40, 0, 0, AF_NDD, 3            ; cmovcc
    apx 7632, 7647, AK_CFCMOV, 0x40, 0, 0, AF_ONLY, 0         ; cfcmovcc
    apx 4016, 4031, AK_SETCC, 0x40, 0, 3, AF_ZU, 0            ; setcc
    apx 1005, 1005, AK_ADX, 0x66, 0, 1, AF_NDD | AF_EGPR, 3   ; adcx
    apx 1013, 1013, AK_ADX, 0x66, 0, 2, AF_NDD | AF_EGPR, 3   ; adox
    apx 1537, 1537, AK_CNT, 0x88, 0, 0, AF_NF, 0              ; popcnt
    apx 1378, 1378, AK_CNT, 0xF5, 0, 0, AF_NF, 0              ; lzcnt
    apx 1699, 1699, AK_CNT, 0xF4, 0, 0, AF_NF, 0              ; tzcnt
    apx 1394, 1394, AK_MOVBE, 0x60, 0, 0, AF_EGPR, 0          ; movbe
    apx 1091, 1091, AK_CRC32, 0xF0, 0, 0, AF_EGPR, 0          ; crc32
    apx 1291, 1291, AK_REGMEM, 0xF0, 0, 2, AF_EGPR, 0         ; invept
    apx 1294, 1294, AK_REGMEM, 0xF1, 0, 2, AF_EGPR, 0         ; invvpid
    apx 1293, 1293, AK_REGMEM, 0xF2, 0, 2, AF_EGPR, 0         ; invpcid
    apx 1397, 1397, AK_REGMEM, 0xF8, 0, 1, AF_EGPR, 0         ; movdir64b
    apx 1166, 1166, AK_REGMEM, 0xF8, 0, 3, AF_EGPR, 0         ; enqcmd
    apx 1167, 1167, AK_REGMEM, 0xF8, 0, 2, AF_EGPR, 0         ; enqcmds
    apx 1398, 1398, AK_MEMREG, 0xF9, 0, 0, AF_EGPR, 0         ; movdiri
    apx 2144, 2145, AK_MEMREG, 0x66, 0, 0, AF_EGPR, 0         ; wrssd, wrssq
    apx 2146, 2147, AK_MEMREG, 0x65, 0, 1, AF_EGPR, 0         ; wrussd, wrussq
    apx 7600, 7615, AK_CCMP, 0x38, 7, 0, AF_ONLY, 0           ; ccmpscc
    apx 7616, 7631, AK_CTEST, 0x84, 0, 0, AF_ONLY, 0          ; ctestscc
    apx 7648, 7648, AK_PUSH2, 0xFF, 0, 0, AF_ONLY, 0          ; push2
    apx 7649, 7649, AK_PUSH2, 0x8F, 0, 0, AF_ONLY, 0          ; pop2
    apx 7650, 7650, AK_PUSH2, 0xFF, 1, 0, AF_ONLY, 0          ; push2p
    apx 7651, 7651, AK_PUSH2, 0x8F, 1, 0, AF_ONLY, 0          ; pop2p
    apx 7652, 7652, AK_PUSHP, 0x50, 0, 0, AF_ONLY, 0          ; pushp
    apx 7653, 7653, AK_PUSHP, 0x58, 0, 0, AF_ONLY, 0          ; popp
    apx 7654, 7654, AK_JMPABS, 0xA1, 0, 0, AF_ONLY, 0         ; jmpabs
    dw 0

[SECTION .bss]
global amd64_apx_mine
amd64_apx_mine: resb 1              ; 1: amd64_apx_encode writes the instruction
apx_size:   resb 1                  ; the operation's size, bits
apx_pp:     resb 1
apx_nd:     resb 1
apx_op:     resb 1                  ; the opcode
apx_digit:  resb 1                  ; ModRM.reg when no register is there
apx_immw:   resb 1                  ; the immediate's width, bytes (0: none)
apx_nfx:    resb 1                  ; NF set by the form itself (cfcmov)
apx_sc:     resb 1                  ; ccmp / ctest's condition (0xFF: none)
alignb 8
apx_desc:   resq 1                  ; the apx_table entry
apx_reg:    resq 1                  ; the ModRM.reg operand (0: apx_digit)
apx_rm:     resq 1                  ; the ModRM.rm operand
apx_vvvv:   resq 1                  ; the vvvv operand (0: none)
apx_imm:    resq 1                  ; the immediate's value

[SECTION .text]

;*
; * [amd64_apx_claim]
; * Purpose: Is the instruction one APX writes as EVEX? {nf} on one that
; *   takes it, {evex}, or one operand more than the legacy form (a new
; *   data destination). amd64_apx_mine says so to the encoder.
; * Input  : R12 = INST
; * Output : EAX = 0, or EXIT_ENCODE_FAIL (outside 64-bit code)
; * Clobbers rcx, rdx, rsi.
; ;
global amd64_apx_claim
amd64_apx_claim:
    mov     byte [rel amd64_apx_mine], 0
    movzx   eax, word [r12 + INST_op_id]
    lea     rsi, [rel apx_table]
.find:
    movzx   ecx, word [rsi]
    test    ecx, ecx
    jz      .not_apx
    cmp     eax, ecx
    jb      .next
    cmp     ax, [rsi + 2]
    jbe     .found
    jmp     .next
.not_apx:
    ; {nf} on andn, bextr, blsi, blsmsk, blsr, bzhi: their VEX form as EVEX
    ; with NF, by the table encoder (dispatch.s .vex_evex): mine = 2
    test    byte [r12 + INST_apx], APX_NF
    jz      .ok
    cmp     eax, 1029                      ; andn
    je      .bmi_nf
    cmp     eax, 1035                      ; bextr
    je      .bmi_nf
    cmp     eax, 1058                      ; bzhi
    je      .bmi_nf
    cmp     eax, 1040                      ; blsi, blsmsk, blsr
    jb      .ok
    cmp     eax, 1042
    ja      .ok
.bmi_nf:
    mov     byte [rel amd64_apx_mine], 2
    jmp     .ok
.next:
    add     rsi, 12
    jmp     .find
.found:
    mov     [rel apx_desc], rsi
    movzx   edx, byte [rsi + 8]            ; flags
    ; "{nf} not": not leaves the flags alone - {nf} changes nothing (NASM)
    cmp     eax, 1441
    jne     .not_not
    and     byte [r12 + INST_apx], ~APX_NF
.not_not:
    test    edx, AF_ONLY
    jnz     .mine
    test    byte [r12 + INST_apx], APX_ZU
    jz      .no_zu
    test    edx, AF_ZU
    jz      .ok
    jmp     .mine
.no_zu:
    ; imul r, r, r/m (r, r/m, imm is the legacy form)
    cmp     eax, 1276
    jne     .not_imul3
    cmp     byte [r12 + INST_nops], 3
    jne     .not_imul3
    movzx   ecx, byte [r12 + INST_op2 + OPERAND_kind]
    cmp     ecx, OP_IMM
    je      .not_imul3
    cmp     ecx, OP_SYMBOL
    jne     .mine
.not_imul3:
    test    byte [r12 + INST_apx], APX_NF
    jz      .no_nf
    test    edx, AF_NF
    jz      .ok                            ; (left to the legacy checks)
    jmp     .mine
.no_nf:
    test    byte [r12 + INST_flags], INSTF_EVEX
    jnz     .mine
    ; r16-r31 where REX2 has no form (0F 38): EVEX
    test    edx, AF_EGPR
    jz      .no_egpr
    call    apx_has_egpr
    jnz     .mine
.no_egpr:
    test    edx, AF_NDD
    jz      .ok
    movzx   ecx, byte [rsi + 9]            ; the NDD form's operand count
    cmp     [r12 + INST_nops], cl
    jne     .ok
.mine:
    cmp     byte [rel asm_bits], 64
    jne     .fail
    mov     byte [rel amd64_apx_mine], 1
.ok:
    xor     eax, eax
    ret
.fail:
    mov     eax, EXIT_ENCODE_FAIL
    ret

; apx_has_egpr: ZF = 0 when an operand is, or addresses by, r16-r31.
; Clobbers rax, rcx, rdi.
apx_has_egpr:
    xor     ecx, ecx
.he_op:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .he_no
    imul    eax, ecx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rax]
    inc     ecx
    movzx   eax, byte [rdi + OPERAND_kind]
    cmp     eax, OP_REG
    je      .he_reg
    cmp     eax, OP_MEM
    jne     .he_op
    movzx   eax, byte [rdi + OPERAND_base]
    sub     eax, 16
    cmp     eax, 16
    jb      .he_yes
    movzx   eax, byte [rdi + OPERAND_index]
    sub     eax, 16
    cmp     eax, 16
    jb      .he_yes
    jmp     .he_op
.he_reg:
    movzx   eax, byte [rdi + OPERAND_reg]
    sub     eax, 16
    cmp     eax, 16
    jb      .he_yes
    jmp     .he_op
.he_no:
    cmp     eax, eax                       ; ZF = 1
    ret
.he_yes:
    test    esp, esp                       ; ZF = 0
    ret

;*
; * [amd64_apx_encode]
; * Purpose: The instruction amd64_apx_claim took, written (its legacy
; *   prefixes are out). The kind places the operands, .emit writes them.
; * Input  : R12 = INST, RBX = AsmCtx
; * Output : RAX = 0 or EXIT_ENCODE_FAIL
; ;
global amd64_apx_encode
amd64_apx_encode:
    push    r13
    push    r14
    mov     r13, [rel apx_desc]
    xor     eax, eax
    mov     [rel apx_reg], rax
    mov     [rel apx_rm], rax
    mov     [rel apx_vvvv], rax
    mov     byte [rel apx_digit], 0
    mov     byte [rel apx_nd], 0
    mov     byte [rel apx_immw], 0
    mov     byte [rel apx_nfx], 0
    mov     byte [rel apx_sc], 0xFF
    movzx   eax, byte [r13 + 7]
    mov     [rel apx_pp], al
    ; ah .. bh have no EVEX form
    xor     ecx, ecx
.high:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .kind
    imul    eax, ecx, OPERAND_SIZE
    inc     ecx
    cmp     byte [r12 + INST_op0 + rax + OPERAND_kind], OP_REG
    jne     .high
    cmp     byte [r12 + INST_op0 + rax + OPERAND_is_high], 0
    jne     .fail
    jmp     .high
.kind:
    movzx   eax, byte [r13 + 4]
    cmp     eax, AK_ALU
    je      .alu
    cmp     eax, AK_UNARY
    je      .unary
    cmp     eax, AK_SHIFT
    je      .shift
    cmp     eax, AK_SHXD
    je      .shxd
    cmp     eax, AK_IMUL
    je      .imul
    cmp     eax, AK_MULDIV
    je      .muldiv
    cmp     eax, AK_CMOV
    je      .cmov
    cmp     eax, AK_CFCMOV
    je      .cfcmov
    cmp     eax, AK_SETCC
    je      .setcc
    cmp     eax, AK_ADX
    je      .adx
    cmp     eax, AK_CNT
    je      .cnt
    cmp     eax, AK_MOVBE
    je      .movbe
    cmp     eax, AK_CRC32
    je      .crc32
    cmp     eax, AK_REGMEM
    je      .regmem
    cmp     eax, AK_MEMREG
    je      .memreg
    cmp     eax, AK_CCMP
    je      .ccmp
    cmp     eax, AK_CTEST
    je      .ctest
    cmp     eax, AK_PUSH2
    je      .push2
    cmp     eax, AK_PUSHP
    je      .pushp
    cmp     eax, AK_JMPABS
    je      .jmpabs
    jmp     .fail

; .r_rm: r14 a register in ModRM.reg, the next operand ModRM.rm, the
; operation's size theirs. ZF = 1 if so.
.r_rm:
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .r_rm_ret
    lea     rdi, [r14 + OPERAND_SIZE]
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     rsi, r14
    call    .size_of
.r_rm_ret:
    ret

; ---- adcx / adox: 66 (66 / F3); NDD dest, r, r/m ----
.adx:
    lea     r14, [r12 + INST_op0]
    cmp     byte [r12 + INST_nops], 2
    je      .adx_go
    cmp     byte [r12 + INST_nops], 3
    jne     .fail
    call    .ndd
    jnz     .fail
.adx_go:
    call    .r_rm
    jnz     .fail
    cmp     byte [rel apx_size], 32
    jb      .fail
    mov     byte [rel apx_op], 0x66
    jmp     .emit

; ---- popcnt lzcnt tzcnt: r, r/m ----
.cnt:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    call    .r_rm
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .fail
    mov     al, [r13 + 5]
    mov     [rel apx_op], al
    jmp     .emit

; ---- movbe: 60 r, m; 61 r/m, r ----
.movbe:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    lea     rdi, [r14 + OPERAND_SIZE]
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .fail
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .movbe_store
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .movbe_store
    mov     [rel apx_reg], r14             ; the load
    mov     [rel apx_rm], rdi
    mov     byte [rel apx_op], 0x60
    jmp     .emit
.movbe_store:
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_rm], r14
    mov     [rel apx_reg], rdi
    mov     byte [rel apx_op], 0x61
    jmp     .emit

; ---- crc32 r32 / r64, r/m: F0 (a byte), F1 - sized by the source ----
.crc32:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r14 + OPERAND_size], 32
    jb      .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    movzx   eax, byte [rdi + OPERAND_size]
    test    eax, eax
    jz      .fail
    mov     byte [rel apx_op], 0xF1
    cmp     eax, 8
    jne     .crc_size
    mov     byte [rel apx_op], 0xF0
    mov     eax, 32                        ; (W 0, no 66)
    cmp     byte [rel gas_names], 0
    je      .crc_size
    cmp     byte [r14 + OPERAND_size], 64
    jne     .crc_size
    mov     eax, 64                        ; (GNU as: W from a 64-bit destination)
.crc_size:
    mov     [rel apx_size], al
    jmp     .emit

; ---- invept .. enqcmds, movdir64b: r64, m (W 1) ----
.regmem:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r14 + OPERAND_size], 64
    jne     .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     byte [rel apx_size], 64        ; W 1 (NASM's)
    cmp     byte [rel gas_names], 0
    je      .regmem_op
    mov     byte [rel apx_size], 32        ; (GNU as: W 0)
.regmem_op:
    mov     al, [r13 + 5]
    mov     [rel apx_op], al
    jmp     .emit

; ---- movdiri, wrss, wruss: m, r ----
.memreg:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    cmp     byte [r14 + OPERAND_kind], OP_MEM
    jne     .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_rm], r14
    mov     [rel apx_reg], rdi
    movzx   eax, byte [rdi + OPERAND_size]
    cmp     eax, 32
    jb      .fail
    mov     [rel apx_size], al
    mov     al, [r13 + 5]
    mov     [rel apx_op], al
    jmp     .emit

; ---- ccmpscc {dfv=..} a, b: 38 / 39 (r/m, r), 3A / 3B (r, m), 80 / 83 /
; 81 /7 (r/m, imm) - vvvv the default flags, P2 the condition ----
.ccmp:
    call    .scc
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     rsi, [r12 + INST_op0]
    lea     rdi, [rsi + OPERAND_SIZE]
    call    .size_of
    jnz     .fail
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    je      .ccmp_imm
    cmp     byte [rdi + OPERAND_kind], OP_REG
    je      .ccmp_mr
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .fail
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], rsi             ; r, m: 3A / 3B
    mov     [rel apx_rm], rdi
    mov     eax, 2
    jmp     .ccmp_op
.ccmp_mr:
    mov     [rel apx_rm], rsi              ; r/m, r: 38 / 39
    mov     [rel apx_reg], rdi
    xor     eax, eax
.ccmp_op:
    add     al, [r13 + 5]
    cmp     byte [rel apx_size], 8
    je      .ccmp_op8
    inc     eax
.ccmp_op8:
    mov     [rel apx_op], al
    jmp     .emit
.ccmp_imm:
    mov     [rel apx_rm], rsi
    mov     byte [rel apx_digit], 7
    mov     rax, [rdi + OPERAND_imm]
    call    .imm_group
    jnz     .fail
    jmp     .emit

; ---- ctestscc {dfv=..} a, b: 84 / 85, F6 / F7 /0 imm (no imm8 form) ----
.ctest:
    call    .scc
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     rsi, [r12 + INST_op0]
    lea     rdi, [rsi + OPERAND_SIZE]
    call    .size_of
    jnz     .fail
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    je      .ctest_imm
    cmp     byte [rdi + OPERAND_kind], OP_REG
    je      .ctest_mr
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .fail
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .fail
    xchg    rsi, rdi                       ; (test is r/m, r either way)
.ctest_mr:
    mov     [rel apx_rm], rsi
    mov     [rel apx_reg], rdi
    mov     eax, 0x84
    jmp     .ctest_op
.ctest_imm:
    mov     [rel apx_rm], rsi
    mov     byte [rel apx_digit], 0
    movzx   ecx, byte [rel apx_size]
    mov     rax, [rdi + OPERAND_imm]
    call    .imm_canon
    jnz     .fail
    mov     [rel apx_imm], rax
    mov     edx, 1
    cmp     ecx, 8
    je      .ctest_w
    mov     edx, 2
    cmp     ecx, 16
    je      .ctest_w
    mov     edx, 4
.ctest_w:
    mov     [rel apx_immw], dl
    mov     eax, 0xF6
.ctest_op:
    cmp     byte [rel apx_size], 8
    je      .ctest_op8
    inc     eax
.ctest_op8:
    mov     [rel apx_op], al
    jmp     .emit

; .scc: ccmp's / ctest's condition, from the id's place in its range
.scc:
    movzx   eax, word [r12 + INST_op_id]
    sub     ax, [r13]
    and     eax, 15
    mov     [rel apx_sc], al
    ret

; ---- push2 / pop2 r64, r64: FF /6, 8F /0 - ND, vvvv the first; the p
; forms W 1 ----
.push2:
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    lea     r14, [r12 + INST_op0]
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r14 + OPERAND_size], 64
    jne     .fail
    cmp     byte [rdi + OPERAND_size], 64
    jne     .fail
    mov     [rel apx_vvvv], r14
    mov     [rel apx_rm], rdi
    mov     byte [rel apx_nd], 1
    mov     al, [r13 + 5]
    mov     [rel apx_op], al
    mov     byte [rel apx_digit], 6
    cmp     al, 0xFF
    je      .push2_w
    mov     byte [rel apx_digit], 0
.push2_w:
    mov     byte [rel apx_size], 32        ; (W 0)
    cmp     byte [r13 + 6], 0
    je      .emit
    mov     byte [rel apx_size], 64        ; push2p / pop2p: W 1
    jmp     .emit

; ---- pushp / popp r64: REX2 with W, 50+r / 58+r ----
.pushp:
    cmp     byte [r12 + INST_nops], 1
    jne     .fail
    lea     r14, [r12 + INST_op0]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r14 + OPERAND_size], 64
    jne     .fail
    mov     qword [rel amd64_rex2_at], -2
    mov     al, 0xD5
    call    amd64_emit_byte
    movzx   ecx, byte [r14 + OPERAND_reg]
    mov     eax, 0x08                      ; W
    test    ecx, 8
    jz      .pushp_b4
    or      eax, 0x01                      ; B3
.pushp_b4:
    test    ecx, 16
    jz      .pushp_put
    or      eax, 0x10                      ; B4
.pushp_put:
    call    amd64_emit_byte
    movzx   eax, byte [r14 + OPERAND_reg]
    and     eax, 7
    add     al, [r13 + 5]
    call    amd64_emit_byte
    jmp     .ok

; ---- jmpabs imm64: REX2 (W 0) A1 ----
.jmpabs:
    cmp     byte [r12 + INST_nops], 1
    jne     .fail
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_IMM
    jne     .fail
    mov     qword [rel amd64_rex2_at], -2
    mov     al, 0xD5
    call    amd64_emit_byte
    xor     eax, eax
    call    amd64_emit_byte
    mov     al, 0xA1
    call    amd64_emit_byte
    mov     rdi, [r12 + INST_op0 + OPERAND_imm]
    extern  amd64_emit_qword
    call    amd64_emit_qword
    jmp     .ok

; .cc_op: 0x40 + the condition, from the id's place in its range
.cc_op:
    movzx   eax, word [r12 + INST_op_id]
    sub     ax, [r13]
    and     eax, 15
    add     eax, 0x40
    mov     [rel apx_op], al
    ret

; ---- imul: F7 /5 (one), AF (two; NDD three), 6B ib / 69 (r, r/m, imm) ----
.imul:
    lea     r14, [r12 + INST_op0]
    movzx   eax, byte [r12 + INST_nops]
    cmp     eax, 1
    je      .muldiv
    cmp     eax, 2
    je      .imul_rrm
    cmp     eax, 3
    jne     .fail
    movzx   ecx, byte [r14 + OPERAND_SIZE * 2 + OPERAND_kind]
    cmp     ecx, OP_IMM
    je      .imul_imm
    call    .ndd                           ; imul dest, r, r/m
    jnz     .fail
.imul_rrm:
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .fail
    mov     byte [rel apx_op], 0xAF
    jmp     .emit
.imul_imm:
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    ; {zu}: ND
    test    byte [r12 + INST_apx], APX_ZU
    jz      .imul_imm_go
    mov     byte [rel apx_nd], 1
.imul_imm_go:
    movzx   ecx, byte [rel apx_size]
    cmp     ecx, 8
    je      .fail
    mov     rax, [r14 + OPERAND_SIZE * 2 + OPERAND_imm]
    call    .imm_canon
    jnz     .fail
    mov     [rel apx_imm], rax
    mov     byte [rel apx_op], 0x6B
    mov     byte [rel apx_immw], 1
    cmp     rax, -128
    jl      .imul_long
    cmp     rax, 127
    jle     .emit
.imul_long:
    mov     byte [rel apx_op], 0x69
    mov     byte [rel apx_immw], 4
    cmp     ecx, 16
    jne     .emit
    mov     byte [rel apx_immw], 2
    jmp     .emit

; ---- mul div idiv (and imul's one-operand form): F6 / F7 /digit ----
.muldiv:
    cmp     byte [r12 + INST_nops], 1
    jne     .fail
    lea     r14, [r12 + INST_op0]
    mov     [rel apx_rm], r14
    mov     rsi, r14
    mov     rdi, r14
    call    .size_of
    jnz     .fail
    movzx   eax, byte [r13 + 6]
    mov     [rel apx_digit], al
    mov     eax, 0xF6
    cmp     byte [rel apx_size], 8
    je      .muldiv_op
    inc     eax
.muldiv_op:
    mov     [rel apx_op], al
    jmp     .emit

; ---- cmovcc dest, r, r/m: 40 + cc ----
.cmov:
    lea     r14, [r12 + INST_op0]
    cmp     byte [r12 + INST_nops], 3
    jne     .fail
    call    .ndd
    jnz     .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .fail
    call    .cc_op
    jmp     .emit

; ---- cfcmovcc: r, r/m (NF 0, the load); r/m, r (NF 1, the store, and
; two registers as NASM writes them); dest, r, r/m (ND, NF 1) ----
.cfcmov:
    lea     r14, [r12 + INST_op0]
    call    .cc_op
    movzx   eax, byte [r12 + INST_nops]
    cmp     eax, 3
    je      .cf_ndd
    cmp     eax, 2
    jne     .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    je      .cf_load
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [rel gas_names], 0
    je      .cf_store
    cmp     byte [r14 + OPERAND_kind], OP_REG
    je      .cf_load                       ; (two registers: GNU as's load form)
.cf_store:
    mov     [rel apx_rm], r14              ; the store: r/m, r
    mov     [rel apx_reg], rdi
    mov     byte [rel apx_nfx], 1
    jmp     .cf_go
.cf_load:
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    jmp     .cf_go
.cf_ndd:
    call    .ndd
    jnz     .fail
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], r14
    mov     [rel apx_rm], rdi
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    mov     byte [rel apx_nfx], 1
.cf_go:
    cmp     byte [rel apx_size], 8
    je      .fail
    jmp     .emit

; ---- setcc r/m8: 40 + cc, F2 ({zu}: ND) ----
.setcc:
    cmp     byte [r12 + INST_nops], 1
    jne     .fail
    lea     r14, [r12 + INST_op0]
    mov     [rel apx_rm], r14
    movzx   eax, byte [r14 + OPERAND_size]
    test    eax, eax
    jz      .setcc_size
    cmp     eax, 8
    jne     .fail
.setcc_size:
    mov     byte [rel apx_size], 8
    test    byte [r12 + INST_apx], APX_ZU
    jz      .setcc_op
    mov     byte [rel apx_nd], 1
.setcc_op:
    call    .cc_op
    jmp     .emit

; .ndd: the first operand (r14) the new destination - a register - in
; vvvv, its size the operation's; r14 then the next. ZF = 1 if so.
.ndd:
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .ndd_ret
    mov     [rel apx_vvvv], r14
    mov     byte [rel apx_nd], 1
    movzx   eax, byte [r14 + OPERAND_size]
    mov     [rel apx_size], al
    add     r14, OPERAND_SIZE
    cmp     eax, eax
.ndd_ret:
    ret

; ---- inc dec neg not: FE / FF, F6 / F7 /digit (NDD: dest, src) ----
.unary:
    lea     r14, [r12 + INST_op0]
    cmp     byte [r12 + INST_nops], 1
    je      .unary_rm
    cmp     byte [r12 + INST_nops], 2
    jne     .fail
    call    .ndd
    jnz     .fail
.unary_rm:
    mov     [rel apx_rm], r14
    mov     rsi, r14
    mov     rdi, r14
    call    .size_of
    jnz     .fail
    movzx   eax, byte [r13 + 6]
    mov     [rel apx_digit], al
    movzx   eax, byte [r13 + 5]
    cmp     byte [rel apx_size], 8
    je      .unary_op
    inc     eax
.unary_op:
    mov     [rel apx_op], al
    jmp     .emit

; ---- shifts: D0 / D1 by 1, C0 / C1 ib, D2 / D3 by cl (NDD: dest, src, n) ----
.shift:
    lea     r14, [r12 + INST_op0]
    cmp     byte [r12 + INST_nops], 2
    je      .shift_rm
    cmp     byte [r12 + INST_nops], 3
    jne     .fail
    call    .ndd
    jnz     .fail
.shift_rm:
    mov     [rel apx_rm], r14
    mov     rsi, r14
    mov     rdi, r14
    call    .size_of
    jnz     .fail
    movzx   eax, byte [r13 + 6]
    mov     [rel apx_digit], al
    lea     rdi, [r14 + OPERAND_SIZE]      ; the count
    call    .count                         ; eax: D0 / C0 / D2
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .shift_op
    inc     eax
.shift_op:
    mov     [rel apx_op], al
    jmp     .emit

; .count: the shift count rdi - 1 (D0), an imm8 (C0, apx_imm), cl (D2):
; eax the 8-bit opcode. ZF = 1 if it is one of them.
.count:
    cmp     byte [rdi + OPERAND_kind], OP_REG
    je      .count_cl
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    jne     .count_ret
    mov     rax, [rdi + OPERAND_imm]
    cmp     rax, 1
    jne     .count_imm
    mov     eax, 0xD0
    cmp     eax, eax
    ret
.count_imm:
    mov     [rel apx_imm], rax
    mov     byte [rel apx_immw], 1
    mov     eax, 0xC0
    cmp     eax, eax
    ret
.count_cl:
    cmp     byte [rdi + OPERAND_reg], 1
    jne     .count_ret
    cmp     byte [rdi + OPERAND_size], 8
    jne     .count_ret
    mov     eax, 0xD2
    cmp     eax, eax
.count_ret:
    ret

; ---- shld shrd: 24 / 2C ib, A5 / AD by cl (NDD: dest, r/m, r, n) ----
.shxd:
    lea     r14, [r12 + INST_op0]
    cmp     byte [r12 + INST_nops], 3
    je      .shxd_rm
    cmp     byte [r12 + INST_nops], 4
    jne     .fail
    call    .ndd
    jnz     .fail
.shxd_rm:
    lea     rdi, [r14 + OPERAND_SIZE]
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_rm], r14
    mov     [rel apx_reg], rdi
    mov     rsi, r14
    call    .size_of
    jnz     .fail
    cmp     byte [rel apx_size], 8
    je      .fail
    lea     rdi, [r14 + OPERAND_SIZE * 2]
    call    .count
    jnz     .fail
    movzx   ecx, byte [r13 + 5]
    cmp     eax, 0xD2
    jne     .shxd_imm
    add     ecx, 0x81                      ; by cl
    jmp     .shxd_op
.shxd_imm:
    cmp     eax, 0xD0
    jne     .shxd_op
    mov     qword [rel apx_imm], 1         ; (by 1: the imm8 form, 1)
    mov     byte [rel apx_immw], 1
.shxd_op:
    mov     [rel apx_op], cl
    jmp     .emit

; ---- add .. xor: r/m, r (op); r, r/m (op + 2); r/m, imm (80 81 83) ----
; NDD (dest, src1, src2): src2 an immediate - r/m src1; src1 memory -
; r/m src1, r src2; else r src1, r/m src2. Two operands: the same with
; the destination as src1 (a register: r, r/m - NASM's choice).
.alu:
    lea     r14, [r12 + INST_op0]
    movzx   eax, byte [r12 + INST_nops]
    cmp     eax, 2
    je      .alu_ops
    cmp     eax, 3
    jne     .fail
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_vvvv], r14            ; the new destination
    mov     byte [rel apx_nd], 1
    movzx   eax, byte [r14 + OPERAND_size]
    mov     [rel apx_size], al
    add     r14, OPERAND_SIZE
.alu_ops:
    lea     rsi, [r14]                     ; src1 (or the destination)
    lea     rdi, [r14 + OPERAND_SIZE]      ; src2
    call    .size_of
    jnz     .fail
    movzx   eax, byte [rdi + OPERAND_kind]
    cmp     eax, OP_IMM
    je      .alu_imm
    cmp     eax, OP_REG
    je      .alu_src_reg
    cmp     eax, OP_MEM
    jne     .fail
    ; src2 memory: r src1, r/m src2
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], rsi
    mov     [rel apx_rm], rdi
    mov     eax, 2
    jmp     .alu_op
.alu_src_reg:
    cmp     byte [rsi + OPERAND_kind], OP_MEM
    je      .alu_rm_r
    cmp     byte [rel gas_names], 0
    jne     .alu_rm_r                      ; (two registers: GNU as's r/m, r)
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .fail
    mov     [rel apx_reg], rsi             ; r, r/m
    mov     [rel apx_rm], rdi
    mov     eax, 2
    jmp     .alu_op
.alu_rm_r:
    mov     [rel apx_rm], rsi              ; r/m, r
    mov     [rel apx_reg], rdi
    xor     eax, eax
.alu_op:
    add     al, [r13 + 5]
    cmp     byte [rel apx_size], 8
    je      .alu_op8
    inc     eax
.alu_op8:
    mov     [rel apx_op], al
    jmp     .emit
.alu_imm:
    mov     [rel apx_rm], rsi
    movzx   eax, byte [r13 + 6]
    mov     [rel apx_digit], al
    mov     rax, [rdi + OPERAND_imm]
    call    .imm_group
    jnz     .fail
    jmp     .emit

; .size_of: the operation's size from rsi / rdi (and the destination
; already taken for NDD); the registers' sizes must agree. ZF = 1 if so.
.size_of:
    movzx   eax, byte [rel apx_size]
    cmp     byte [rel apx_nd], 0
    jne     .so_have
    xor     eax, eax
.so_have:
    mov     rcx, rsi
    call    .so_one
    jnz     .so_ret
    mov     rcx, rdi
    call    .so_one
    jnz     .so_ret
    test    eax, eax
    jz      .so_bad                        ; no size anywhere
    mov     [rel apx_size], al
    cmp     eax, eax
.so_ret:
    ret
.so_bad:
    test    esp, esp
    ret
; .so_one: operand rcx's size against eax (0: none yet)
.so_one:
    movzx   edx, byte [rcx + OPERAND_kind]
    cmp     edx, OP_IMM
    je      .so_ok
    movzx   edx, byte [rcx + OPERAND_size]
    test    edx, edx
    jz      .so_ok
    test    eax, eax
    jz      .so_take
    cmp     eax, edx
    ret                                    ; (ZF: they agree)
.so_take:
    mov     eax, edx
.so_ok:
    cmp     eax, eax
    ret

; .imm_group: the immediate rax for the group-1 opcodes: 80 ib (bytes),
; 83 ib (a signed byte), else 81 iw / id. ZF = 1 if it fits.
.imm_group:
    movzx   ecx, byte [rel apx_size]
    call    .imm_canon
    jnz     .ig_ret
    mov     [rel apx_imm], rax
    cmp     ecx, 8
    jne     .ig_wide
    mov     byte [rel apx_op], 0x80
    mov     byte [rel apx_immw], 1
    jmp     .ig_ok
.ig_wide:
    cmp     rax, -128
    jl      .ig_long
    cmp     rax, 127
    jg      .ig_long
    mov     byte [rel apx_op], 0x83
    mov     byte [rel apx_immw], 1
    jmp     .ig_ok
.ig_long:
    mov     byte [rel apx_op], 0x81
    mov     edx, 4
    cmp     ecx, 16
    jne     .ig_w
    mov     edx, 2
.ig_w:
    mov     [rel apx_immw], dl
.ig_ok:
    cmp     eax, eax
.ig_ret:
    ret

; .imm_canon: rax as an operation of ecx bits sees it (0xFFFF in 16 bits
; is -1; a 64-bit one takes a sign-extended imm32, 0x80000000 ..
; 0xFFFFFFFF its low half sign-extended, as NASM). ZF = 1 if it fits.
.imm_canon:
    cmp     ecx, 64
    je      .ic_64
    cmp     ecx, 32
    je      .ic_32
    cmp     ecx, 16
    je      .ic_16
    movsx   rax, al
    jmp     .ic_ok
.ic_16:
    movsx   rax, ax
    jmp     .ic_ok
.ic_32:
    movsxd  rax, eax
    jmp     .ic_ok
.ic_64:
    mov     rdx, rax
    shr     rdx, 32
    jnz     .ic_64_s
    movsxd  rax, eax
    jmp     .ic_ok
.ic_64_s:
    movsxd  rdx, eax
    cmp     rdx, rax
    jne     .ic_bad
.ic_ok:
    cmp     eax, eax
    ret
.ic_bad:
    test    esp, esp
    ret

; ---- .emit: 62 P0 P1 P2, the opcode, ModRM .., the immediate ----
.emit:
    ; ModRM.rm is a register or memory, whatever the form ("cmovz rbx, r9,
    ; 3" has no form); ModRM.reg, when an operand, a register
    mov     rsi, [rel apx_rm]
    test    rsi, rsi
    jz      .fail
    movzx   eax, byte [rsi + OPERAND_kind]
    cmp     eax, OP_REG
    je      .emit_reg
    cmp     eax, OP_MEM
    jne     .fail
.emit_reg:
    mov     rsi, [rel apx_reg]
    test    rsi, rsi
    jz      .emit_go
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .fail
.emit_go:
    mov     qword [rel amd64_rex2_at], -2  ; (r16-r31 are in the EVEX bits)
    mov     byte [rel amd64_disp8n], 1     ; (no disp8*N here)
    mov     al, 0x62
    call    amd64_emit_byte
    ; P0: R3' X3' B3' R4' B4 100
    mov     r14d, 0x04 | 0x80 | 0x40 | 0x20 | 0x10
    xor     r9d, r9d                       ; r9 = X4
    mov     rsi, [rel apx_reg]
    test    rsi, rsi
    jz      .p0_rm
    movzx   eax, byte [rsi + OPERAND_reg]
    test    eax, 8
    jz      .p0_r4
    and     r14d, ~0x80                    ; R3
.p0_r4:
    test    eax, 16
    jz      .p0_rm
    and     r14d, ~0x10                    ; R4
.p0_rm:
    mov     rsi, [rel apx_rm]
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .p0_mem
    movzx   eax, byte [rsi + OPERAND_reg]
    call    .p0_base
    jmp     .p0_put
.p0_mem:
    movzx   eax, byte [rsi + OPERAND_base]
    cmp     eax, 32
    jae     .p0_index                      ; (none, rip)
    call    .p0_base
.p0_index:
    movzx   eax, byte [rsi + OPERAND_index]
    cmp     eax, 32
    jae     .p0_put
    test    eax, 8
    jz      .p0_x4
    and     r14d, ~0x40                    ; X3
.p0_x4:
    test    eax, 16
    jz      .p0_put
    mov     r9d, 1                         ; X4
.p0_put:
    mov     eax, r14d
    call    amd64_emit_byte
    ; P1: W vvvv' X4' pp
    xor     eax, eax
    mov     rsi, [rel apx_vvvv]
    test    rsi, rsi
    jz      .p1_v
    movzx   eax, byte [rsi + OPERAND_reg]
.p1_v:
    mov     r14d, eax                      ; (bit 4: V4)
    not     eax
    and     eax, 15
    cmp     byte [rel apx_sc], 0xFF
    je      .p1_vv
    movzx   eax, byte [r12 + INST_dfv]     ; ccmp / ctest: OF SF ZF CF
    and     eax, 15
    mov     r14d, 16                       ; (no V4' there)
.p1_vv:
    shl     eax, 3
    test    r9d, r9d
    jnz     .p1_x4
    or      eax, 4
.p1_x4:
    movzx   ecx, byte [rel apx_size]
    cmp     ecx, 64
    jne     .p1_pp
    or      eax, 0x80                      ; W
.p1_pp:
    movzx   edx, byte [rel apx_pp]
    cmp     ecx, 16
    jne     .p1_put
    test    edx, edx
    jnz     .p1_put
    mov     edx, 1                         ; 16 bits: 66
.p1_put:
    or      eax, edx
    call    amd64_emit_byte
    ; P2: 000 ND V4' NF 00 - ccmp / ctest: 0000 SC3..SC0
    movzx   eax, byte [rel apx_sc]
    cmp     eax, 0xFF
    jne     .p2_put
    movzx   eax, byte [rel apx_nd]
    shl     eax, 4
    test    r14d, 16
    jnz     .p2_nf
    or      eax, 8                         ; V4'
.p2_nf:
    cmp     byte [rel apx_nfx], 0
    jne     .p2_nf_set
    test    byte [r12 + INST_apx], APX_NF
    jz      .p2_put
.p2_nf_set:
    or      eax, 4
.p2_put:
    call    amd64_emit_byte
    mov     al, [rel apx_op]
    call    amd64_emit_byte
    ; ModRM, SIB, displacement
    mov     al, [rel apx_digit]
    mov     rsi, [rel apx_reg]
    test    rsi, rsi
    jz      .modrm
    mov     al, [rsi + OPERAND_reg]
.modrm:
    mov     rdi, [rel apx_rm]
    call    amd64_emit_modrm_sib
    ; the immediate
    movzx   ecx, byte [rel apx_immw]
    mov     rax, [rel apx_imm]
    cmp     ecx, 1
    jne     .imm2
    call    amd64_emit_byte
    jmp     .ok
.imm2:
    cmp     ecx, 2
    jne     .imm4
    mov     rdi, rax
    call    amd64_emit_word
    jmp     .ok
.imm4:
    cmp     ecx, 4
    jne     .ok
    mov     rdi, rax
    call    amd64_emit_dword
.ok:
    xor     eax, eax
    pop     r14
    pop     r13
    ret
.fail:
    mov     eax, EXIT_ENCODE_FAIL
    pop     r14
    pop     r13
    ret

; .p0_base: register eax as ModRM.rm or the base: B3 (inverted), B4
.p0_base:
    test    eax, 8
    jz      .pb_b4
    and     r14d, ~0x20
.pb_b4:
    test    eax, 16
    jz      .pb_ret
    or      r14d, 0x08
.pb_ret:
    ret
