;
; ============================================================================
; File        : backend/encoder/mode.s
; Project     : utasm
; Description : bits 16 / bits 32: what changes from 64-bit mode.
;
;   The encoders are written for 64-bit mode. Outside it the same bytes
;   mostly mean the same, with these exceptions, all handled here or by the
;   central routines that call in here:
;
;   - operands that do not exist: 64-bit registers, r8-r15, spl/bpl/sil/dil,
;     xmm8-15, 64-bit address registers (amd64_mode_check); [rel x] is an
;     absolute [x] (no RIP-relative addressing)
;   - REX: an instruction that needs one cannot be encoded
;     (amd64_rex_scan, after the fact: in a 64-bit encoding a REX byte
;     comes right after the legacy prefixes, so it is found unambiguously)
;   - the operand-size prefix 66 marks the size that is not the mode's
;     default: 16-bit operands in 32/64-bit mode, 32-bit ones in 16-bit
;     mode (amd64_osz66)
;   - forms that exist only outside 64-bit mode, or are shorter there, or
;     take the mode's own width (amd64_mode_special): inc/dec r16/r32
;     (40+r/48+r), push/pop of registers, segment registers, immediates and
;     memory, pusha/popa, pushf/popf, iret, daa/das/aaa/aas/aam/aad/into,
;     bound/arpl/les/lds, cbw/cwde/cwd/cdq and the string instructions,
;     mov between the accumulator and an absolute address (A0-A3), and
;     xchg eax, eax (90)
;
;   In every mode: mov to and from a segment register (8E / 8C), and
;   segment registers anywhere else rejected (amd64_mode_check) - the
;   encoders know registers 0-15 only, and took ds for r9.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  asm_bits
extern  amd64_emit_byte
extern  amd64_emit_word
extern  amd64_emit_dword
extern  amd64_emit_modrm_sib
extern  amd64_emit_reloc
extern  error_set_subject

%define ID_INC      1278
%define ID_DEC      1118
%define ID_PUSH     1583
%define ID_POP      1534
%define ID_XCHG     2152
%define ID_MOV      1391
%define ID_AAM      1002
%define ID_AAD      1001
%define ID_BOUND    1050
%define ID_ARPL     1034
%define ID_LES      1358
%define ID_LDS      1354
%define ID_JMP      1298
%define ID_CALL     1059

[SECTION .rodata]
; 64-bit-only mnemonics (no REX shows them): rejected outside 64-bit mode
; (rdpkru / wrpkru as NASM has them)
only64:
    dw 1588, 1540, 1297, 1062, 1090, 1423, 1671, 1371, 1081, 1681, 6529
    dw 1598, 2143
    dw 0
; mnemonics that exist only outside 64-bit mode
only_legacy:
    dw 1584, 1535, 1585, 1536, 1116, 1117, 1000, 1003, 1002, 1001, 1289
    dw 1050, 1034, 1358, 1354
    dw 0
; fixed one-byte instructions with an operand size: id, opcode, size
; (0 = the mode's default width)
sized_ops:
    dw 1584
    db 0x60, 0                      ; pusha
    dw 1535
    db 0x61, 0                      ; popa
    dw 1585
    db 0x60, 32                     ; pushad
    dw 1536
    db 0x61, 32                     ; popad
    dw 1586
    db 0x9C, 0                      ; pushf
    dw 1538
    db 0x9D, 0                      ; popf
    dw 1587
    db 0x9C, 32                     ; pushfd
    dw 1539
    db 0x9D, 32                     ; popfd
    dw 6063
    db 0x9C, 16                     ; pushfw
    dw 6058
    db 0x9D, 16                     ; popfw
    dw 1295
    db 0xCF, 0                      ; iret
    dw 1296
    db 0xCF, 32                     ; iretd
    dw 1060
    db 0x98, 16                     ; cbw
    dw 1115
    db 0x98, 32                     ; cwde
    dw 1114
    db 0x99, 16                     ; cwd
    dw 1061
    db 0x99, 32                     ; cdq
    dw 1425
    db 0xA5, 16                     ; movsw
    dw 1420
    db 0xA5, 32                     ; movsd (no operands: the string form)
    dw 1672
    db 0xAB, 16                     ; stosw
    dw 1670
    db 0xAB, 32                     ; stosd
    dw 1372
    db 0xAD, 16                     ; lodsw
    dw 1370
    db 0xAD, 32                     ; lodsd
    dw 1632
    db 0xAF, 16                     ; scasw
    dw 1631
    db 0xAF, 32                     ; scasd
    dw 1083
    db 0xA7, 16                     ; cmpsw
    dw 1080
    db 0xA7, 32                     ; cmpsd (no operands: the string form)
    dw 1285
    db 0x6D, 16                     ; insw
    dw 1283
    db 0x6D, 32                     ; insd
    dw 1449
    db 0x6F, 16                     ; outsw
    dw 1448
    db 0x6F, 32                     ; outsd
    dw 1282
    db 0x6C, 8                      ; insb
    dw 1447
    db 0x6E, 8                      ; outsb
    dw 1116
    db 0x27, 8                      ; daa
    dw 1117
    db 0x2F, 8                      ; das
    dw 1000
    db 0x37, 8                      ; aaa
    dw 1003
    db 0x3F, 8                      ; aas
    dw 1289
    db 0xCE, 8                      ; into
    dw 0
; push / pop of a segment register by its id (cs ds es fs gs ss = 24..29;
; fs/gs: 0, encoded as in 64-bit mode; pop cs does not exist)
seg_push_by_id: db 0x0E, 0x1E, 0x06, 0, 0, 0x16
seg_pop_by_id:  db 0x00, 0x1F, 0x07, 0, 0, 0x17
; the ModRM reg field of each (es 0, cs 1, ss 2, ds 3, fs 4, gs 5)
seg_modrm_by_id: db 1, 3, 0, 4, 5, 2

[SECTION .data]
amd64_a67_at:   dq -1                   ; where this instruction's 67 is

[SECTION .text]

;*
; * [amd64_mode_default]
; * Output: EAX = the mode's default operand / address width (16 or 32;
; *         64-bit mode: 32 for operands)
; ;
global amd64_mode_default
amd64_mode_default:
    movzx   eax, byte [rel asm_bits]
    cmp     eax, 16
    je      .ret
    mov     eax, 32
.ret:
    ret

;*
; * [amd64_osz66]
; * Purpose: Does an operation of this size need the operand-size prefix?
; * Input  : AL = operation size (8, 16, 32, 64)
; * Output : EAX = 1 or 0 (only EAX changes)
; ;
global amd64_osz66
amd64_osz66:
    cmp     byte [rel asm_bits], 16
    je      .m16
    cmp     al, 16
    jne     .no
.yes:
    mov     eax, 1
    ret
.m16:
    cmp     al, 32
    je      .yes
.no:
    xor     eax, eax
    ret

;*
; * [amd64_emit_osz_prefix]
; * Purpose: Emit the operand-size prefix 66. NASM puts it before the
; *          address-size prefix 67, which the encoder's entry emits first
; *          (amd64_a67_at): when that 67 is the last byte out, the two
; *          trade places.
; * Input  : RBX = AsmCtx
; ;
global amd64_emit_osz_prefix
global amd64_a67_at
amd64_emit_osz_prefix:
    push    rcx
    push    rdx
    cmp     qword [rel amd64_a67_at], -1
    je      .plain                         ; no 67 in this instruction
    mov     rcx, [rbx + ASMCTX_curr_sec]
    test    rcx, rcx
    jz      .plain
    mov     rdx, [rcx + SECTION_size]
    dec     rdx
    cmp     rdx, [rel amd64_a67_at]
    jne     .plain
    mov     rcx, [rcx + SECTION_data]
    mov     byte [rcx + rdx], 0x66
    mov     qword [rel amd64_a67_at], -1
    pop     rdx
    pop     rcx
    mov     al, 0x67
    jmp     amd64_emit_byte
.plain:
    pop     rdx
    pop     rcx
    mov     al, 0x66
    jmp     amd64_emit_byte

;*
; * [amd64_mode_check]
; * Purpose: Outside 64-bit mode, reject what does not exist there.
; * Input  : R12 = INST
; * Output : RAX = 0 or EXIT_BITS_MODE
; ;
global amd64_mode_check
amd64_mode_check:
    ; segment registers: operands of mov, push and pop only
    xor     ecx, ecx
.seg_op:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .seg_done
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .seg_op
    movzx   eax, byte [rdi + OPERAND_reg]
    sub     eax, 24
    cmp     eax, 5
    ja      .seg_op
    movzx   edx, word [r12 + INST_op_id]
    cmp     edx, ID_MOV
    je      .seg_op
    cmp     edx, ID_PUSH
    je      .seg_stack
    cmp     edx, ID_POP
    jne     .combination
    cmp     eax, 0
    je      .fail                          ; pop cs
.seg_stack:
    cmp     byte [rel asm_bits], 64
    jne     .seg_op
    cmp     eax, 3
    jb      .fail                          ; cs ds es: not in 64-bit mode
    cmp     eax, 5
    je      .fail                          ; ss
    jmp     .seg_op
.combination:
    mov     eax, EXIT_ENCODE_FAIL
    ret
.seg_done:
    movzx   eax, word [r12 + INST_op_id]
    cmp     byte [rel asm_bits], 64
    je      .mode64
    lea     rsi, [rel only64]
    call    .listed
    jnz     .fail
    xor     ecx, ecx
.op:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .ok
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    movzx   eax, byte [rdi + OPERAND_kind]
    cmp     eax, OP_REG
    je      .reg
    cmp     eax, OP_MEM
    je      .mem
    jmp     .op
.reg:
    movzx   eax, byte [rdi + OPERAND_reg]
    cmp     eax, 16
    jae     .not_gpr
    cmp     eax, 8
    jae     .fail                          ; r8 - r15
    cmp     byte [rdi + OPERAND_size], 64
    je      .fail
    cmp     byte [rdi + OPERAND_size], 8
    jne     .op
    cmp     byte [rdi + OPERAND_is_high], 0
    jne     .op
    cmp     eax, 4
    jb      .op
    jmp     .fail                          ; spl bpl sil dil
.not_gpr:
    cmp     eax, 40
    je      .fail                          ; cr8
    cmp     eax, 80
    jb      .op
    cmp     eax, 112
    jae     .op
    sub     eax, 80
    and     eax, 31
    cmp     eax, 8
    jae     .fail                          ; xmm8-31
    jmp     .op
.mem:
    ; [rel x]: no RIP-relative addressing here, x is an absolute address
    cmp     byte [rdi + OPERAND_base], REG_RIP
    jne     .mem_regs
    mov     byte [rdi + OPERAND_base], 0xFF
    and     byte [rdi + OPERAND_flags], ~OP_FLAG_REL
.mem_regs:
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR32 | OP_FLAG_ADDR16
    jnz     .mem_low
    cmp     byte [rdi + OPERAND_base], 0xFF
    jne     .fail                          ; 64-bit address registers
    cmp     byte [rdi + OPERAND_index], 0xFF
    jne     .fail
    jmp     .op
.mem_low:
    movzx   eax, byte [rdi + OPERAND_base]
    cmp     eax, 0xFF
    je      .mem_index
    cmp     eax, 8
    jae     .fail                          ; r8d - r15d
.mem_index:
    movzx   eax, byte [rdi + OPERAND_index]
    cmp     eax, 0xFF
    je      .op
    cmp     eax, 8
    jae     .fail
    jmp     .op

.mode64:
    ; 64-bit mode: 16-bit addressing and the legacy-only instructions do
    ; not exist
    lea     rsi, [rel only_legacy]
    call    .listed
    jnz     .fail
    xor     ecx, ecx
.op64:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .ok
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .op64
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR16
    jnz     .fail
    jmp     .op64
.ok:
    xor     eax, eax
    ret
.fail:
    mov     eax, EXIT_BITS_MODE
    ret

; .listed: is mnemonic id eax in the 0-ended dw list rsi? (ZF clear: yes)
.listed:
    movzx   edx, word [rsi]
    test    edx, edx
    jz      .not_listed
    cmp     edx, eax
    je      .is_listed
    add     rsi, 2
    jmp     .listed
.is_listed:
    or      edx, 1                         ; ZF clear
    ret
.not_listed:
    xor     edx, edx                       ; ZF set
    ret

;*
; * [amd64_imm_canon]
; * Purpose: An immediate of a 16- or 32-bit operation written as the
; *   unsigned value of its bits (0xFFFF, 0xFFFFFF80) is that negative
; *   number to the operation (-1, -128): stored so, the encoders choose
; *   the sign-extended imm8 forms (83 /n ib, 6B, 6A) as NASM does. The
; *   width is the first general register's or memory operand's, else the
; *   immediate's own (push word 0xFFFF).
; * Input  : R12 = INST
; ;
global amd64_imm_canon
amd64_imm_canon:
    push    rbx
    xor     ebx, ebx                       ; the operation's width
    xor     ecx, ecx
.width:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .imms
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    movzx   eax, byte [rdi + OPERAND_kind]
    cmp     eax, OP_MEM
    je      .found
    cmp     eax, OP_REG
    jne     .width
    cmp     byte [rdi + OPERAND_reg], 16
    jae     .imms                          ; xmm, segment ...: leave it
.found:
    movzx   ebx, byte [rdi + OPERAND_size]
.imms:
    xor     ecx, ecx
.imm:
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .done
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    inc     ecx
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    jne     .imm
    mov     edx, ebx
    test    edx, edx
    jnz     .sized
    movzx   edx, byte [rdi + OPERAND_size]
.sized:
    mov     rax, [rdi + OPERAND_imm]
    cmp     edx, 16
    je      .w16
    cmp     edx, 32
    jne     .imm
    mov     rsi, rax
    shr     rsi, 31
    cmp     rsi, 1                         ; 0x80000000 - 0xFFFFFFFF
    jne     .imm
    movsxd  rax, eax
    mov     [rdi + OPERAND_imm], rax
    jmp     .imm
.w16:
    mov     rsi, rax
    shr     rsi, 15
    cmp     rsi, 1                         ; 0x8000 - 0xFFFF
    jne     .imm
    movsx   rax, ax
    mov     [rdi + OPERAND_imm], rax
    jmp     .imm
.done:
    pop     rbx
    ret

;*
; * [amd64_rex_scan]
; * Purpose: Outside 64-bit mode, the instruction just encoded must not
; *          carry a REX prefix (it would be inc/dec there).
; * Input  : RBX = AsmCtx (ASMCTX_inst_len = the instruction's length)
; * Output : RAX = 0 or EXIT_BITS_MODE
; ;
global amd64_rex_scan
amd64_rex_scan:
    cmp     byte [rel asm_bits], 64
    je      .ok
    mov     rcx, [rbx + ASMCTX_curr_sec]
    test    rcx, rcx
    jz      .ok
    mov     rdx, [rcx + SECTION_data]
    test    rdx, rdx
    jz      .ok
    mov     rsi, [rcx + SECTION_size]
    mov     eax, [rbx + ASMCTX_inst_len]
    mov     rdi, rsi
    sub     rdi, rax                       ; the instruction's first byte
.byte:
    cmp     rdi, rsi
    jae     .ok
    movzx   eax, byte [rdx + rdi]
    inc     rdi
    cmp     eax, 0x66
    je      .byte
    cmp     eax, 0x67
    je      .byte
    cmp     eax, 0xF0
    je      .byte
    cmp     eax, 0xF2
    je      .byte
    cmp     eax, 0xF3
    je      .byte
    cmp     eax, 0x26
    je      .byte
    cmp     eax, 0x2E
    je      .byte
    cmp     eax, 0x36
    je      .byte
    cmp     eax, 0x3E
    je      .byte
    cmp     eax, 0x64
    je      .byte
    cmp     eax, 0x65
    je      .byte
    and     eax, 0xF0
    cmp     eax, 0x40
    jne     .ok
    mov     eax, EXIT_BITS_MODE
    ret
.ok:
    xor     eax, eax
    ret

;*
; * [amd64_mode_special]
; * Purpose: Outside 64-bit mode, encode the forms that only exist there or
; *          differ there (see the file header); in any mode, ins / outs.
; * Input  : RBX = AsmCtx, R12 = INST (prefixes already emitted)
; * Output : RAX = 0 not one of them, 1 encoded, or an error
; ;
global amd64_mode_special
amd64_mode_special:
    push    r13
    push    r14
    push    r15
    movzx   r13d, word [r12 + INST_op_id]
    cmp     r13d, ID_MOV
    jne     .not_mov_sreg
    cmp     byte [r12 + INST_nops], 2
    jne     .not_mov_sreg
    lea     r14, [r12 + INST_op0]
    lea     r15, [r12 + INST_op1]
    mov     rdi, r14
    call    .is_sreg
    je      .mov_sreg
    mov     rdi, r15
    call    .is_sreg
    je      .mov_sreg
.not_mov_sreg:
    ; jmp / call SEG:OFFSET (two operands, the segment marked OP_FLAG_FAR)
    cmp     r13d, ID_JMP
    je      .far_check
    cmp     r13d, ID_CALL
    jne     .not_far
.far_check:
    cmp     byte [r12 + INST_nops], 2
    jne     .not_far
    lea     r14, [r12 + INST_op0]
    lea     r15, [r12 + INST_op1]
    test    byte [r14 + OPERAND_flags], OP_FLAG_FAR
    jz      .not_far
    movzx   eax, byte [r14 + OPERAND_kind]
    cmp     eax, OP_IMM
    je      .far_direct
    cmp     eax, OP_SYMBOL
    je      .far_direct
.not_far:
    cmp     byte [rel asm_bits], 64
    jne     .any_mode
    ; 64-bit mode: only ins / outs, which the encoders do not have
    cmp     byte [r12 + INST_nops], 0
    jne     .none
    cmp     r13d, 1282                     ; insb
    je      .any_mode
    cmp     r13d, 1285                     ; insw
    je      .any_mode
    cmp     r13d, 1283                     ; insd
    je      .any_mode
    cmp     r13d, 1447                     ; outsb
    je      .any_mode
    cmp     r13d, 1449                     ; outsw
    je      .any_mode
    cmp     r13d, 1448                     ; outsd
    jne     .none
.any_mode:
    lea     r14, [r12 + INST_op0]
    lea     r15, [r12 + INST_op1]
    movzx   ecx, byte [r12 + INST_nops]

    ; fixed one-byte forms with a size (no operands)
    test    ecx, ecx
    jnz     .with_operands
    lea     rsi, [rel sized_ops]
.sized:
    movzx   eax, word [rsi]
    test    eax, eax
    jz      .none
    cmp     eax, r13d
    je      .sized_hit
    add     rsi, 4
    jmp     .sized
.sized_hit:
    movzx   eax, byte [rsi + 3]            ; size (0: default)
    push    rsi
    test    eax, eax
    jz      .sized_op
    cmp     eax, 8
    je      .sized_op
    call    amd64_osz66
    test    eax, eax
    jz      .sized_op
    call    amd64_emit_osz_prefix
.sized_op:
    pop     rsi
    mov     al, [rsi + 2]
    call    amd64_emit_byte
    jmp     .done

.with_operands:
    cmp     r13d, ID_INC
    je      .incdec
    cmp     r13d, ID_DEC
    je      .incdec
    cmp     r13d, ID_PUSH
    je      .push
    cmp     r13d, ID_POP
    je      .pop
    cmp     r13d, ID_XCHG
    je      .xchg
    cmp     r13d, ID_MOV
    je      .mov
    cmp     r13d, ID_AAM
    je      .aam
    cmp     r13d, ID_AAD
    je      .aam
    cmp     r13d, ID_BOUND
    je      .bound
    cmp     r13d, ID_ARPL
    je      .arpl
    cmp     r13d, ID_LES
    je      .les
    cmp     r13d, ID_LDS
    je      .les
    cmp     r13d, ID_JMP
    je      .indirect
    cmp     r13d, ID_CALL
    je      .indirect
    jmp     .none

; ---- jmp / call r/m: FF /4, FF /2 with the operand's width ----
.indirect:
    cmp     ecx, 1
    jne     .none
    movzx   eax, byte [r14 + OPERAND_kind]
    cmp     eax, OP_REG
    je      .indirect_go
    cmp     eax, OP_MEM
    jne     .none
    test    byte [r14 + OPERAND_flags], OP_FLAG_FAR
    jnz     .none
.indirect_go:
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jnz     .indirect_sized
    call    amd64_mode_default
.indirect_sized:
    cmp     al, 16
    je      .indirect_ok
    cmp     al, 32
    jne     .fail
.indirect_ok:
    call    .osz
    mov     al, 0xFF
    call    amd64_emit_byte
    mov     eax, 4
    cmp     r13d, ID_JMP
    je      .indirect_rm
    mov     eax, 2
.indirect_rm:
    mov     rdi, r14
    call    amd64_emit_modrm_sib
    jmp     .done

; ---- inc / dec r16, r32: 40+r / 48+r ----
.incdec:
    cmp     ecx, 1
    jne     .none
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .none
    movzx   eax, byte [r14 + OPERAND_reg]
    cmp     eax, 8
    jae     .none
    mov     al, [r14 + OPERAND_size]
    cmp     al, 16
    je      .incdec_emit
    cmp     al, 32
    jne     .none
.incdec_emit:
    call    .osz
    mov     al, 0x40
    cmp     r13d, ID_DEC
    jne     .incdec_op
    mov     al, 0x48
.incdec_op:
    add     al, [r14 + OPERAND_reg]
    call    amd64_emit_byte
    jmp     .done

; ---- push / pop ----
.push:
    cmp     ecx, 1
    jne     .none
    movzx   eax, byte [r14 + OPERAND_kind]
    cmp     eax, OP_REG
    je      .push_reg
    cmp     eax, OP_MEM
    je      .push_mem
    cmp     eax, OP_IMM
    je      .push_imm
    cmp     eax, OP_SYMBOL
    je      .push_sym
    jmp     .none
.pop:
    cmp     ecx, 1
    jne     .none
    movzx   eax, byte [r14 + OPERAND_kind]
    cmp     eax, OP_REG
    je      .pop_reg
    cmp     eax, OP_MEM
    je      .pop_mem
    jmp     .none

.push_reg:
    movzx   eax, byte [r14 + OPERAND_reg]
    cmp     eax, 24
    jb      .push_gpr
    cmp     eax, 30
    jae     .none
    lea     rsi, [rel seg_push_by_id]
    movzx   eax, byte [rsi + rax - 24]
    test    eax, eax
    jz      .none                          ; fs / gs: as in 64-bit mode
    call    amd64_emit_byte
    jmp     .done
.push_gpr:
    mov     al, [r14 + OPERAND_size]
    cmp     al, 16
    je      .push_gpr_ok
    cmp     al, 32
    jne     .fail
.push_gpr_ok:
    call    .osz
    mov     al, 0x50
    add     al, [r14 + OPERAND_reg]
    call    amd64_emit_byte
    jmp     .done
.pop_reg:
    movzx   eax, byte [r14 + OPERAND_reg]
    cmp     eax, 24
    jb      .pop_gpr
    cmp     eax, 30
    jae     .none
    lea     rsi, [rel seg_pop_by_id]
    movzx   eax, byte [rsi + rax - 24]
    test    eax, eax
    jz      .pop_seg_none
    call    amd64_emit_byte
    jmp     .done
.pop_seg_none:
    cmp     byte [r14 + OPERAND_reg], 24
    je      .fail                          ; pop cs
    jmp     .none
.pop_gpr:
    mov     al, [r14 + OPERAND_size]
    cmp     al, 16
    je      .pop_gpr_ok
    cmp     al, 32
    jne     .fail
.pop_gpr_ok:
    call    .osz
    mov     al, 0x58
    add     al, [r14 + OPERAND_reg]
    call    amd64_emit_byte
    jmp     .done

.push_mem:
    mov     r15d, 6                        ; FF /6
    mov     ecx, 0xFF
    jmp     .stack_mem
.pop_mem:
    mov     r15d, 0                        ; 8F /0
    mov     ecx, 0x8F
.stack_mem:
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jnz     .stack_mem_sized
    call    amd64_mode_default
.stack_mem_sized:
    cmp     al, 16
    je      .stack_mem_ok
    cmp     al, 32
    jne     .fail
.stack_mem_ok:
    push    rcx
    call    .osz
    pop     rax
    call    amd64_emit_byte
    mov     eax, r15d
    mov     rdi, r14
    call    amd64_emit_modrm_sib
    jmp     .done

.push_imm:
    ; 6A ib when it fits a signed byte (and no size forces more), else 68
    ; with the operation's width
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jnz     .push_imm_sized
    call    amd64_mode_default
    mov     r15d, eax
    test    byte [r14 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .push_imm_full
    jmp     .push_imm_try8
.push_imm_sized:
    movzx   r15d, al
    cmp     r15d, 8
    jne     .push_imm_width
    call    amd64_mode_default             ; "push byte 5": the default width
    mov     r15d, eax
    jmp     .push_imm_try8
.push_imm_width:
    cmp     r15d, 16
    je      .push_imm_strict
    cmp     r15d, 32
    jne     .fail
.push_imm_strict:
    test    byte [r14 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .push_imm_full
.push_imm_try8:
    mov     rax, [r14 + OPERAND_imm]
    movsx   rdx, al
    cmp     rdx, rax
    jne     .push_imm_full
    mov     eax, r15d
    call    .osz
    mov     al, 0x6A
    call    amd64_emit_byte
    mov     rax, [r14 + OPERAND_imm]
    call    amd64_emit_byte
    jmp     .done
.push_imm_full:
    mov     eax, r15d
    call    .osz
    mov     al, 0x68
    call    amd64_emit_byte
    mov     rdi, [r14 + OPERAND_imm]
    cmp     r15d, 16
    je      .push_imm16
    call    amd64_emit_dword
    jmp     .done
.push_imm16:
    call    amd64_emit_word
    jmp     .done

.push_sym:
    ; a label: 68 with a relocated field of the mode's width
    call    amd64_mode_default
    mov     r15d, eax
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jz      .push_sym_width
    movzx   r15d, al
.push_sym_width:
    mov     eax, r15d
    call    .osz
    mov     al, 0x68
    call    amd64_emit_byte
    mov     rsi, [r14 + OPERAND_sym]
    test    rsi, rsi
    jz      .fail
    cmp     byte [rsi], TAG_SYMBOL
    jne     .push_sym_name
    mov     rsi, [rsi + SYMBOL_name]
.push_sym_name:
    xor     edx, edx
    mov     al, R_X86_64_32
    cmp     r15d, 16
    jne     .push_sym_rel
    mov     al, 12                         ; R_X86_64_16
.push_sym_rel:
    push    r15
    call    amd64_emit_reloc
    pop     r15
    ; the addend: the offset written after the label
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, [rbx + ASMCTX_relocs]
    mov     rax, [r14 + OPERAND_imm]
    mov     rsi, [r14 + OPERAND_sym]
    cmp     byte [rsi], TAG_SYMBOL
    jne     .push_sym_addend
    sub     rax, [rsi + SYMBOL_value]
.push_sym_addend:
    mov     [rcx + RELOC_addend], rax
    xor     edi, edi
    cmp     r15d, 16
    je      .push_imm16
    call    amd64_emit_dword
    jmp     .done

; ---- xchg eax, eax / ax, ax: 90 (no zero-extension to keep apart) ----
.xchg:
    cmp     ecx, 2
    jne     .none
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .none
    cmp     byte [r15 + OPERAND_kind], OP_REG
    jne     .none
    cmp     byte [r14 + OPERAND_reg], 0
    jne     .none
    cmp     byte [r15 + OPERAND_reg], 0
    jne     .none
    mov     al, [r14 + OPERAND_size]
    cmp     al, [r15 + OPERAND_size]
    jne     .none
    cmp     al, 8
    je      .none
    call    .osz
    mov     al, 0x90
    call    amd64_emit_byte
    jmp     .done

; ---- mov al/ax/eax <-> [address]: A0-A3 ----
.mov:
    cmp     ecx, 2
    jne     .none
    mov     rdi, r15                       ; load: mov acc, [addr]
    mov     rsi, r14
    mov     r13d, 0xA0                     ; (the id is not needed any more)
    cmp     byte [r14 + OPERAND_kind], OP_REG
    je      .mov_acc
    mov     rdi, r14                       ; store: mov [addr], acc
    mov     rsi, r15
    mov     r13d, 0xA2
.mov_acc:
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .none
    cmp     byte [rsi + OPERAND_reg], 0
    jne     .none
    cmp     byte [rsi + OPERAND_is_high], 0
    jne     .none
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .none
    cmp     byte [rdi + OPERAND_base], 0xFF
    jne     .none
    cmp     byte [rdi + OPERAND_index], 0xFF
    jne     .none
    mov     al, [rsi + OPERAND_size]
    cmp     al, 8
    je      .mov_acc8
    cmp     al, 16
    je      .mov_acc_wide
    cmp     al, 32
    jne     .none
.mov_acc_wide:
    push    rdi
    call    .osz
    pop     rdi
    inc     r13d                           ; A1 / A3
.mov_acc8:
    push    rdi
    mov     eax, r13d
    call    amd64_emit_byte
    pop     rdi
    ; the address: the mode's width, or the one written ([dword x])
    call    amd64_mode_default
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR32
    jz      .mov_addr16
    mov     eax, 32
.mov_addr16:
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR16
    jz      .mov_addr_width
    mov     eax, 16
.mov_addr_width:
    mov     r15d, eax
    mov     rsi, [rdi + OPERAND_sym]
    test    rsi, rsi
    jz      .mov_addr_plain
    push    rdi
    cmp     byte [rsi], TAG_SYMBOL
    jne     .mov_addr_name
    mov     rsi, [rsi + SYMBOL_name]
.mov_addr_name:
    xor     edx, edx
    mov     al, R_X86_64_32
    cmp     r15d, 16
    jne     .mov_addr_rel
    mov     al, 12
.mov_addr_rel:
    call    amd64_emit_reloc
    pop     rdi
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, [rbx + ASMCTX_relocs]
    mov     rax, [rdi + OPERAND_imm]
    mov     rsi, [rdi + OPERAND_sym]
    cmp     byte [rsi], TAG_SYMBOL
    jne     .mov_addend
    sub     rax, [rsi + SYMBOL_value]
.mov_addend:
    mov     [rcx + RELOC_addend], rax
    xor     edi, edi
    jmp     .mov_addr_out
.mov_addr_plain:
    mov     rdi, [rdi + OPERAND_imm]
.mov_addr_out:
    cmp     r15d, 16
    je      .push_imm16
    call    amd64_emit_dword
    jmp     .done

; ---- aam / aad [imm8]: D4 / D5 ib (10 by default) ----
.aam:
    mov     eax, 0xD4
    cmp     r13d, ID_AAD
    jne     .aam_op
    mov     eax, 0xD5
.aam_op:
    cmp     ecx, 1
    ja      .fail
    call    amd64_emit_byte
    mov     eax, 10
    cmp     byte [r12 + INST_nops], 0
    je      .aam_imm
    cmp     byte [r14 + OPERAND_kind], OP_IMM
    jne     .fail
    mov     rax, [r14 + OPERAND_imm]
.aam_imm:
    call    amd64_emit_byte
    jmp     .done

; ---- bound r, m / les r, m / lds r, m: 62 / C4 / C5 /r ----
.bound:
    mov     r8d, 0x62
    jmp     .reg_mem
.les:
    mov     r8d, 0xC4
    cmp     r13d, ID_LDS
    jne     .reg_mem
    mov     r8d, 0xC5
.reg_mem:
    cmp     ecx, 2
    jne     .fail
    cmp     byte [r14 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r15 + OPERAND_kind], OP_MEM
    jne     .fail
    mov     al, [r14 + OPERAND_size]
    cmp     al, 16
    je      .reg_mem_ok
    cmp     al, 32
    jne     .fail
.reg_mem_ok:
    push    r8
    call    .osz
    pop     rax
    call    amd64_emit_byte
    mov     al, [r14 + OPERAND_reg]
    mov     rdi, r15
    call    amd64_emit_modrm_sib
    jmp     .done

; ---- arpl r/m16, r16: 63 /r ----
.arpl:
    cmp     ecx, 2
    jne     .fail
    cmp     byte [r15 + OPERAND_kind], OP_REG
    jne     .fail
    cmp     byte [r15 + OPERAND_size], 16
    jne     .fail
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jz      .arpl_ok
    cmp     al, 16
    jne     .fail
.arpl_ok:
    mov     al, 0x63
    call    amd64_emit_byte
    mov     al, [r15 + OPERAND_reg]
    mov     rdi, r14
    call    amd64_emit_modrm_sib
    jmp     .done

; ---- mov sreg, r/m: 8E /r; mov r/m, sreg: 8C /r (every mode) ----
; A register: 16, 32 or 64 bits, the prefix 66 only for the 16/32-bit
; size stored to a register that is not the mode's; memory: a word, or a
; qword with REX.W.
.mov_sreg:
    mov     r13d, 0x8E                     ; load: mov sreg, r/m
    mov     rdi, r14
    call    .is_sreg
    je      .mov_sreg_dir
    mov     r13d, 0x8C                     ; store: mov r/m, sreg
    xchg    r14, r15
.mov_sreg_dir:
    ; r14 = the segment register, r15 = the r/m operand
    mov     rdi, r15
    call    .is_sreg
    je      .mov_sreg_bad                  ; mov ds, es
    xor     r8d, r8d                       ; r8 = REX bits
    movzx   eax, byte [r15 + OPERAND_kind]
    cmp     eax, OP_REG
    je      .mov_sreg_reg
    cmp     eax, OP_MEM
    jne     .mov_sreg_bad
    mov     al, [r15 + OPERAND_size]
    test    al, al
    jz      .mov_sreg_mem
    cmp     al, 16
    je      .mov_sreg_mem
    cmp     al, 64
    jne     .mov_sreg_bad
    cmp     byte [rel asm_bits], 64
    jne     .mov_sreg_bad
    or      r8d, 8                         ; qword: REX.W
.mov_sreg_mem:
    movzx   eax, byte [r15 + OPERAND_base]
    cmp     eax, 16
    jae     .mov_sreg_index
    cmp     eax, 8
    jb      .mov_sreg_index
    or      r8d, 1                         ; REX.B
.mov_sreg_index:
    movzx   eax, byte [r15 + OPERAND_index]
    cmp     eax, 16
    jae     .mov_sreg_rex
    cmp     eax, 8
    jb      .mov_sreg_rex
    or      r8d, 2                         ; REX.X
    jmp     .mov_sreg_rex
.mov_sreg_reg:
    movzx   eax, byte [r15 + OPERAND_reg]
    cmp     eax, 16
    jae     .mov_sreg_bad                  ; not a general register
    cmp     eax, 8
    jb      .mov_sreg_size
    or      r8d, 1                         ; r8 - r15: REX.B
.mov_sreg_size:
    mov     al, [r15 + OPERAND_size]
    cmp     al, 64
    je      .mov_sreg_rex
    cmp     al, 16
    je      .mov_sreg_osz
    cmp     al, 32
    jne     .mov_sreg_bad
.mov_sreg_osz:
    cmp     r13d, 0x8C
    jne     .mov_sreg_rex                  ; loading takes any width as is
    push    r8
    call    .osz
    pop     r8
.mov_sreg_rex:
    test    r8d, r8d
    jz      .mov_sreg_op
    lea     eax, [r8 + 0x40]
    call    amd64_emit_byte
.mov_sreg_op:
    mov     eax, r13d
    call    amd64_emit_byte
    movzx   eax, byte [r14 + OPERAND_reg]
    lea     rsi, [rel seg_modrm_by_id]
    movzx   eax, byte [rsi + rax - 24]
    mov     rdi, r15
    call    amd64_emit_modrm_sib
    jmp     .done
.mov_sreg_bad:
    mov     eax, EXIT_ENCODE_FAIL
    jmp     .ret

; ---- jmp / call SEG:OFFSET: EA / 9A, the offset then the segment ----
; The offset is the mode's width, or the size written ("jmp dword 8:x" in
; bits 16, with 66). Not in 64-bit mode.
.far_direct:
    cmp     byte [rel asm_bits], 64
    je      .fail
    movzx   eax, byte [r15 + OPERAND_kind]
    cmp     eax, OP_IMM
    je      .far_offset
    cmp     eax, OP_SYMBOL
    jne     .mov_sreg_bad
.far_offset:
    mov     al, [r14 + OPERAND_size]
    test    al, al
    jnz     .far_sized
    mov     al, [r15 + OPERAND_size]
    test    al, al
    jnz     .far_sized
    call    amd64_mode_default
.far_sized:
    cmp     al, 16
    je      .far_width
    cmp     al, 32
    jne     .mov_sreg_bad
.far_width:
    movzx   eax, al
    push    rax
    call    .osz
    mov     al, 0xEA
    cmp     r13d, ID_JMP
    je      .far_op
    mov     al, 0x9A
.far_op:
    call    amd64_emit_byte
    pop     rax
    mov     rdi, r15
    call    .far_value                     ; the offset
    mov     eax, 16
    mov     rdi, r14
    call    .far_value                     ; the segment
    jmp     .done

; .far_value: operand rdi as an eax-bit (16 or 32) field: its number, or
; a label's address (relocated)
.far_value:
    push    r15
    push    r13
    mov     r15d, eax
    mov     r13, rdi
    mov     rsi, [r13 + OPERAND_sym]
    test    rsi, rsi
    jz      .far_plain
    cmp     byte [r13 + OPERAND_kind], OP_SYMBOL
    je      .far_symbol
    ; a label defined earlier comes as its value (jmp / call keep labels
    ; as they are for distances): an address all the same, relocated
    cmp     byte [r13 + OPERAND_kind], OP_IMM
    jne     .far_plain
    cmp     byte [rsi], TAG_SYMBOL
    jne     .far_plain
    cmp     word [rsi + SYMBOL_section], SHN_ABS
    je      .far_plain                     ; "SEL equ 8": a number
    movzx   eax, byte [rsi + SYMBOL_kind]
    cmp     eax, SYM_LABEL
    je      .far_symbol
    cmp     eax, SYM_DATA
    je      .far_symbol
    cmp     eax, SYM_EXTERN
    je      .far_symbol
    cmp     eax, SYM_COMMON
    jne     .far_plain
.far_symbol:
    cmp     byte [rsi], TAG_SYMBOL
    jne     .far_name
    mov     rsi, [rsi + SYMBOL_name]
.far_name:
    xor     edx, edx
    mov     al, R_X86_64_32
    cmp     r15d, 16
    jne     .far_rel
    mov     al, 12                         ; R_X86_64_16
.far_rel:
    call    amd64_emit_reloc
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, [rbx + ASMCTX_relocs]
    mov     rax, [r13 + OPERAND_imm]
    mov     rsi, [r13 + OPERAND_sym]
    cmp     byte [rsi], TAG_SYMBOL
    jne     .far_addend
    sub     rax, [rsi + SYMBOL_value]
.far_addend:
    mov     [rcx + RELOC_addend], rax
    xor     edi, edi
    jmp     .far_emit
.far_plain:
    mov     rdi, [r13 + OPERAND_imm]
.far_emit:
    cmp     r15d, 16
    jne     .far_dword
    call    amd64_emit_word
    jmp     .far_out
.far_dword:
    call    amd64_emit_dword
.far_out:
    pop     r13
    pop     r15
    ret

; .is_sreg: ZF set when operand rdi is a segment register
.is_sreg:
    cmp     byte [rdi + OPERAND_kind], OP_REG
    jne     .is_sreg_ret
    movzx   eax, byte [rdi + OPERAND_reg]
    cmp     eax, 24
    jb      .is_sreg_no
    cmp     eax, 29
    ja      .is_sreg_no
    cmp     eax, eax                       ; ZF set
    ret
.is_sreg_no:
    test    rdi, rdi                       ; ZF clear (rdi is not 0)
.is_sreg_ret:
    ret

; .osz: the operand-size prefix for an operation of size al, if it needs one
.osz:
    push    rax
    call    amd64_osz66
    test    eax, eax
    jz      .osz_none
    call    amd64_emit_osz_prefix
.osz_none:
    pop     rax
    ret

.done:
    mov     eax, 1
    jmp     .ret
.fail:
    mov     eax, EXIT_BITS_MODE
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    ret
