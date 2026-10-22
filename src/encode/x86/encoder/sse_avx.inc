; ============================================================================
; File        : src/encode/x86/encoder/sse_avx.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : AVX / SSE forms, the VEX2 / VEX3 prefixes; messages and the obsolete tables
; ============================================================================


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
    ; LAR / LSL reg16/32/64, r/m: 0F R13 /r. The destination gives the
    ; operand size; the selector is a 16/32/64-bit register or a word in
    ; memory, as NASM takes them ("lar ebx, r9w" is 41 0F 02 D9).
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    cmp     byte [r12 + INST_nops], 2
    jne     .bad
    cmp     byte [r10 + OPERAND_kind], OP_REG
    jne     .bad
    cmp     byte [r10 + OPERAND_reg], 32
    jae     .bad
    cmp     byte [r10 + OPERAND_size], 8
    je      .bad
    cmp     byte [r11 + OPERAND_kind], OP_MEM
    je      .mem
    cmp     byte [r11 + OPERAND_kind], OP_REG
    jne     .bad
    cmp     byte [r11 + OPERAND_reg], 32
    jae     .bad
    cmp     byte [r11 + OPERAND_size], 8
    je      .bad
    jmp     .emit
.mem:
    movzx   eax, byte [r11 + OPERAND_size]
    test    eax, eax
    jz      .emit
    cmp     eax, 16
    jne     .bad
.emit:
    mov     al, [r10 + OPERAND_size]
    mov     rsi, r10
    mov     rdx, r11
    call    amd64_emit_prefixes

    mov     al, 0x0F
    call    amd64_emit_byte
    mov     al, r13b
    call    amd64_emit_byte

    lea     r10, [r12 + INST_op0]          ; the calls above clobber r10/r11
    lea     r11, [r12 + INST_op1]
    mov     al, [r10 + OPERAND_reg]
    mov     rdi, r11
    call    amd64_emit_modrm_sib
    xor     eax, eax
    jmp     .done
.bad:
    mov     eax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_rm_m]
; ;
amd64_encode_rm_m:
    prologue
    ; the prefixes the address needs first (REX.X / REX.B for
    ; "[rax + r14*8]", 67): they were left out ("prefetchwt1 [rax+r14*8]")
    lea     rdx, [r12 + INST_op0]
    xor     rsi, rsi
    mov     al, 32                         ; (no REX.W)
    call    amd64_emit_prefixes

    ; Multi-byte Opcode (R13): the first byte (if any), then the second -
    ; held in r13, not in ah, which amd64_emit_byte does not keep (it was
    ; 0F 00 for prefetchwt1's 0F 0D)
    mov     eax, r13d
    shr     eax, 8
    test    al, al
    jz      .one_byte
    call    amd64_emit_byte
.one_byte:
    mov     eax, r13d
    call    amd64_emit_byte

    ; ModRM with Digit (R14)
    mov     al, r14b
    lea     rdi, [r12 + INST_op0]
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

[SECTION .rodata]
s_disp8_bounds: db "byte data exceeds bounds", 0
s_obs_removed:  db "instruction obsolete and removed from the target CPU", 0
s_obs_valid:    db "instruction obsolete but valid on the target CPU", 0
s_obs_nop:      db "instruction never implemented and is a noop on the target CPU", 0
; amd64_cpu_forms: shl shr sal sar rol ror rcl rcr
cf_shift_ids:   dw 1647, 1650, 1624, 1625, 1612, 1613, 1590, 1593, 0
; amd64_obsolete: mnemonic ID, the level it was valid at (cpu_num's: 3 286,
; 4 386, 5 486, 6 pentium, 7 p6; 0xFF none of them)
obsolete_ids:
    dw 7554
    db 6                                   ; bb0_reset
    dw 7003
    db 6                                   ; bb1_reset
    dw 7012
    db 6                                   ; cpu_read
    dw 7013
    db 6                                   ; cpu_write
    dw 7014
    db 7                                   ; dmint
    dw 7555
    db 7                                   ; rdm
    dw 7159
    db 7                                   ; rdshr
    dw 7488
    db 7                                   ; wrshr
    dw 7556
    db 7                                   ; smint
    dw 7175
    db 5                                   ; smintold
    dw 7169
    db 5                                   ; rsdc
    dw 7170
    db 5                                   ; rsldt
    dw 7171
    db 5                                   ; rsts
    dw 7176
    db 5                                   ; svdc
    dw 7177
    db 5                                   ; svldt
    dw 7178
    db 5                                   ; svts
    dw 7011
    db 5                                   ; cmpxchg486
    dw 7089
    db 4                                   ; ibts
    dw 7489
    db 4                                   ; xbts
    dw 7185
    db 4                                   ; umov
    dw 7111
    db 4                                   ; loadall
    dw 7112
    db 3                                   ; loadall286
    dw 1035
    db 0xFF                                ; bextr (TBM)
    dw 7004
    db 0xFF                                ; blcfill
    dw 7005
    db 0xFF                                ; blci
    dw 7006
    db 0xFF                                ; blcic
    dw 7007
    db 0xFF                                ; blcmsk
    dw 7008
    db 0xFF                                ; blcs
    dw 7009
    db 0xFF                                ; blsfill
    dw 7010
    db 0xFF                                ; blsic
    dw 7179
    db 0xFF                                ; t1mskc
    dw 7180
    db 0xFF                                ; tzmsk
    dw 0
[SECTION .text]
