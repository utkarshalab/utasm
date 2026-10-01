;
; ============================================================================
; File        : backend/encoder/shape.s
; Project     : utasm
; Description : Operand shapes of the general-purpose integer instructions.
;
;   The table encoder (dispatch.s) knows only part of the forms of MOV,
;   ADD, BSF and the like, and the hand-written encoders after it take
;   whatever operands they are given. So "mov bl, r9w" used to come out as
;   "mov bl, r9b", and "bsf [rbx], bl" as some BSF. NASM rejects both with
;   "invalid combination of opcode and operands"; amd64_check_shape does
;   the same, before anything is encoded.
;
;   Operands are sorted into GPRs (R), memory (M) and immediates or labels
;   (I); a size of 0 means "not written" (a memory operand without BYTE,
;   WORD, ...) and fits any size. Anything else (segment, control or vector
;   registers) is left to the encoders.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

; operand classes
%define K_R     1
%define K_M     2
%define K_I     3
%define K_X     4

; rules
%define RU_SAME     1               ; mov, add .. xor, cmp, test, xchg
%define RU_XADD     2               ; xadd, cmpxchg: r/m, reg
%define RU_NO8      3               ; bsf, bsr, popcnt, lzcnt, tzcnt, cmovcc
%define RU_IMUL     4
%define RU_MOVBE    5
%define RU_BT       6               ; bt, bts, btr, btc
%define RU_SHLD     7               ; shld, shrd
%define RU_ANDN     8
%define RU_MOVSXD   9
%define RU_MOVX     10              ; movsx, movzx
%define RU_CRC32    11
%define RU_ADX      12              ; adcx, adox

[SECTION .rodata]
; first id, last id (dw), rule (db); sorted by nothing, ended by 0
%macro shape 3
    dw %1, %2
    db %3
%endmacro
shape_table:
    shape 1391, 1391, RU_SAME          ; mov
    shape 1004, 1004, RU_SAME          ; adc
    shape 1006, 1006, RU_SAME          ; add
    shape 1028, 1028, RU_SAME          ; and
    shape 1075, 1075, RU_SAME          ; cmp
    shape 1442, 1442, RU_SAME          ; or
    shape 1628, 1628, RU_SAME          ; sbb
    shape 1676, 1676, RU_SAME          ; sub
    shape 1691, 1691, RU_SAME          ; test
    shape 2152, 2152, RU_SAME          ; xchg
    shape 2157, 2157, RU_SAME          ; xor
    shape 2150, 2150, RU_XADD          ; xadd
    shape 1084, 1084, RU_XADD          ; cmpxchg
    shape 1051, 1052, RU_NO8           ; bsf, bsr
    shape 1537, 1537, RU_NO8           ; popcnt
    shape 1378, 1378, RU_NO8           ; lzcnt
    shape 1699, 1699, RU_NO8           ; tzcnt
    shape 4000, 4015, RU_NO8           ; cmovcc
    shape 1276, 1276, RU_IMUL          ; imul
    shape 1394, 1394, RU_MOVBE         ; movbe
    shape 1054, 1057, RU_BT            ; bt, btc, btr, bts
    shape 1648, 1648, RU_SHLD          ; shld
    shape 1651, 1651, RU_SHLD          ; shrd
    shape 1029, 1029, RU_ANDN          ; andn
    shape 1427, 1427, RU_MOVSXD        ; movsxd
    shape 1426, 1426, RU_MOVX          ; movsx
    shape 1430, 1430, RU_MOVX          ; movzx
    shape 1091, 1091, RU_CRC32         ; crc32
    shape 1005, 1005, RU_ADX           ; adcx
    shape 1013, 1013, RU_ADX           ; adox
    dw 0, 0
    db 0

[SECTION .bss]
sh_kind:    resb 4                  ; K_* of each operand
sh_size:    resb 4                  ; its size in bits / 8 .. 64, 0 = unknown

[SECTION .text]

;*
; * [amd64_check_shape]
; * Purpose: Reject operand combinations no form of the instruction has.
; * Input  : R12 = INST
; * Output : RAX = 0, or EXIT_ENCODE_FAIL
; * Clobbers: rcx, rdx, rsi, rdi, r8 - r11
; ;
global amd64_check_shape
amd64_check_shape:
    movzx   eax, word [r12 + INST_op_id]
    lea     rsi, [rel shape_table]
.find:
    movzx   ecx, word [rsi]
    test    ecx, ecx
    jz      .ok
    cmp     eax, ecx
    jb      .skip
    cmp     ax, [rsi + 2]
    jbe     .found
.skip:
    add     rsi, 5
    jmp     .find
.found:
    movzx   r11d, byte [rsi + 4]           ; r11 = rule

    ; classify the operands
    xor     ecx, ecx
.cls:
    cmp     ecx, 4
    jae     .classified
    imul    rdi, rcx, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0 + rdi]
    movzx   eax, byte [rdi + OPERAND_kind]
    movzx   edx, byte [rdi + OPERAND_size]
    mov     r8d, K_X
    cmp     eax, OP_REG
    jne     .not_reg
    cmp     byte [rdi + OPERAND_reg], 16
    jae     .put
    mov     r8d, K_R
    jmp     .put
.not_reg:
    mov     r8d, K_M
    cmp     eax, OP_MEM
    je      .put
    mov     r8d, K_I
    cmp     eax, OP_IMM
    je      .put
    cmp     eax, OP_SYMBOL
    je      .put
    mov     r8d, K_X
.put:
    lea     r9, [rel sh_kind]
    mov     [r9 + rcx], r8b
    lea     r9, [rel sh_size]
    mov     [r9 + rcx], dl
    inc     ecx
    jmp     .cls
.classified:
    ; anything but GPRs, memory and immediates: the encoders decide
    movzx   ecx, byte [r12 + INST_nops]
    xor     edx, edx
.any_x:
    cmp     edx, ecx
    jae     .no_x
    lea     r9, [rel sh_kind]
    cmp     byte [r9 + rdx], K_X
    je      .ok
    inc     edx
    jmp     .any_x
.no_x:
    ; r8b/r9b = kinds of operands 0/1, r10b = kind of 2; sizes in sh_size
    lea     rsi, [rel sh_kind]
    movzx   r8d, byte [rsi]
    movzx   r9d, byte [rsi + 1]
    movzx   r10d, byte [rsi + 2]
    lea     rsi, [rel sh_size]
    movzx   eax, byte [rsi]                ; eax = size 0
    movzx   edx, byte [rsi + 1]            ; edx = size 1
    movzx   esi, byte [rsi + 2]            ; esi = size 2

    cmp     r11d, RU_SAME
    je      .same
    cmp     r11d, RU_XADD
    je      .xadd
    cmp     r11d, RU_NO8
    je      .no8
    cmp     r11d, RU_IMUL
    je      .imul
    cmp     r11d, RU_MOVBE
    je      .movbe
    cmp     r11d, RU_BT
    je      .bt
    cmp     r11d, RU_SHLD
    je      .shld
    cmp     r11d, RU_ANDN
    je      .andn
    cmp     r11d, RU_MOVSXD
    je      .movsxd
    cmp     r11d, RU_MOVX
    je      .movx
    cmp     r11d, RU_CRC32
    je      .crc32
    jmp     .adx

; Each family takes a fixed number of operands (imul 1 to 3): any other
; count is an error, not something to ignore ("crc32 ebx, r9d, 3").

; ---- r/m, r/m/imm: one memory operand at most, equal sizes ----
.same:
    cmp     ecx, 2
    jne     .fail
    cmp     r9d, K_I
    jne     .same_rm
    cmp     word [r12 + INST_op_id], 2152  ; xchg: no immediate form
    je      .fail
    jmp     .ok
.same_rm:
    cmp     r8d, K_I
    je      .fail
    cmp     r8d, K_M
    jne     .same_sizes
    cmp     r9d, K_M
    je      .fail
.same_sizes:
    call    .eq01
    jmp     .ret

; ---- r/m, reg ----
.xadd:
    cmp     ecx, 2
    jne     .fail
    cmp     r9d, K_R
    jne     .fail
    cmp     r8d, K_I
    je      .fail
    call    .eq01
    jmp     .ret

; ---- reg16/32/64, r/m of the same size ----
.no8:
    cmp     ecx, 2
    jne     .fail
.no8_two:
    cmp     r8d, K_R
    jne     .fail
    cmp     eax, 8
    je      .fail
    cmp     r9d, K_I
    je      .fail
    call    .eq01
    jmp     .ret

.imul:
    cmp     ecx, 1
    je      .ok
    cmp     ecx, 2
    jne     .imul3
    cmp     r9d, K_I
    jne     .no8_two
    cmp     r8d, K_R                       ; imul reg, imm
    jne     .fail
    cmp     eax, 8
    je      .fail
    jmp     .ok
.imul3:
    cmp     ecx, 3
    jne     .fail
    cmp     r10d, K_I
    jne     .fail
    jmp     .no8_two

; ---- reg, mem or mem, reg; no bytes ----
.movbe:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_R
    jne     .movbe_store
    cmp     r9d, K_M
    jne     .fail
    jmp     .movbe_size
.movbe_store:
    cmp     r8d, K_M
    jne     .fail
    cmp     r9d, K_R
    jne     .fail
.movbe_size:
    cmp     eax, 8
    je      .fail
    cmp     edx, 8
    je      .fail
    call    .eq01
    jmp     .ret

; ---- r/m16/32/64, reg of that size or imm8 ----
.bt:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_I
    je      .fail
    cmp     eax, 8
    je      .fail
    cmp     r9d, K_I
    je      .ok
    cmp     r9d, K_R
    jne     .fail
    cmp     edx, 8
    je      .fail
    call    .eq01
    jmp     .ret

; ---- r/m16/32/64, reg of that size, imm8 or cl ----
.shld:
    cmp     ecx, 3
    jne     .fail
    cmp     r8d, K_I
    je      .fail
    cmp     r9d, K_R
    jne     .fail
    cmp     edx, 8
    je      .fail
    cmp     r10d, K_I
    je      .shld_sizes
    cmp     r10d, K_R
    jne     .fail
    cmp     esi, 8
    jne     .fail
.shld_sizes:
    call    .eq01
    jmp     .ret

; ---- reg32/64, reg, r/m: all one size ----
.andn:
    cmp     ecx, 3
    jne     .fail
    cmp     r8d, K_R
    jne     .fail
    cmp     r9d, K_R
    jne     .fail
    cmp     r10d, K_I
    je      .fail
    cmp     eax, 32
    jb      .fail
    call    .eq01
    test    eax, eax
    jnz     .ret
    movzx   eax, byte [rel sh_size]
    test    esi, esi
    jz      .ok
    cmp     esi, eax
    jne     .fail
    jmp     .ok

; ---- reg64, r/m32 ----
.movsxd:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_R
    jne     .fail
    cmp     eax, 64
    jne     .fail
    cmp     r9d, K_I
    je      .fail
    test    edx, edx
    jz      .ok
    cmp     edx, 32
    jne     .fail
    jmp     .ok

; ---- reg16/32/64, r/m8 or r/m16 narrower than it ----
.movx:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_R
    jne     .fail
    cmp     eax, 8
    je      .fail
    cmp     r9d, K_I
    je      .fail
    test    edx, edx
    jnz     .movx_sized
    cmp     eax, 16                        ; "movzx bx, [mem]": a byte, as
    jne     .fail                          ; in NASM; wider needs the size
    mov     byte [r12 + INST_op1 + OPERAND_size], 8
    jmp     .ok
.movx_sized:
    cmp     edx, 32
    jne     .movx_narrow
    cmp     word [r12 + INST_op_id], 1426  ; movsx r64, r/m32: MOVSXD
    jne     .fail
    cmp     eax, 64
    jne     .fail
    jmp     .ok
.movx_narrow:
    cmp     edx, 16
    ja      .fail
    cmp     edx, eax
    jae     .fail
    jmp     .ok

; ---- reg32/64, r/m8/16/32 (r/m64 into reg64 only) ----
.crc32:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_R
    jne     .fail
    cmp     eax, 32
    jb      .fail
    cmp     r9d, K_I
    je      .fail
    test    edx, edx
    jz      .fail                          ; the source size must be known
    cmp     eax, 64
    je      .crc_64
    cmp     edx, 64                        ; reg32: r/m8, r/m16, r/m32
    je      .fail
    jmp     .ok
.crc_64:
    cmp     edx, 8                         ; reg64: r/m8 or r/m64
    je      .ok
    cmp     edx, 64
    jne     .fail
    jmp     .ok

; ---- reg32/64, r/m of the same size ----
.adx:
    cmp     ecx, 2
    jne     .fail
    cmp     r8d, K_R
    jne     .fail
    cmp     eax, 32
    jb      .fail
    cmp     r9d, K_I
    je      .fail
    call    .eq01
    jmp     .ret

; eax = 0 when operands 0 and 1 have the same size (or one is unknown),
; else EXIT_ENCODE_FAIL
.eq01:
    test    eax, eax
    jz      .eq_ok
    test    edx, edx
    jz      .eq_ok
    cmp     eax, edx
    jne     .eq_bad
.eq_ok:
    xor     eax, eax
    ret
.eq_bad:
    mov     eax, EXIT_ENCODE_FAIL
    ret

.ok:
    xor     eax, eax
.ret:
    ret
.fail:
    mov     eax, EXIT_ENCODE_FAIL
    ret
