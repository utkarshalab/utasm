; ============================================================================
; File        : src/encode/x86/encoder/vex_evex.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : the VEX / EVEX entries, string instructions, 0F binaries, cmpxchg, bt, memory sync, r/m forms
; ============================================================================


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
    ; Every branch has to make its own assignment: an ELSEIF with an empty
    ; body falls through with r8b untouched, which silently gave every
    ; suffixed form the byte size.
    IF ax, e, 1419
        mov r8b, 0
    ELSEIF ax, e, 1669
        mov r8b, 0
    ELSEIF ax, e, 1369
        mov r8b, 0
    ELSEIF ax, e, 1630
        mov r8b, 0
    ELSEIF ax, e, 1079
        mov r8b, 0
    ; MOVSW=1425, STOSW=1672, LODSW=1372, SCASW=1632, CMPSW=1083
    ELSEIF ax, e, 1425
        mov r8b, 1
    ELSEIF ax, e, 1672
        mov r8b, 1
    ELSEIF ax, e, 1372
        mov r8b, 1
    ELSEIF ax, e, 1632
        mov r8b, 1
    ELSEIF ax, e, 1083
        mov r8b, 1
    ; MOVSD=1420, STOSD=1670, LODSD=1370, SCASD=1631, CMPSD=1080
    ELSEIF ax, e, 1420
        mov r8b, 2
    ELSEIF ax, e, 1670
        mov r8b, 2
    ELSEIF ax, e, 1370
        mov r8b, 2
    ELSEIF ax, e, 1631
        mov r8b, 2
    ELSEIF ax, e, 1080
        mov r8b, 2
    ; MOVSQ=1423, STOSQ=1671, LODSQ=1371, CMPSQ=1081
    ELSEIF ax, e, 1423
        mov r8b, 3
    ELSEIF ax, e, 1671
        mov r8b, 3
    ELSEIF ax, e, 1371
        mov r8b, 3
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
    
    ; Case 1: BT r/m, reg (the register gives the size: "bt [rbx], bx")
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov     al, [r11 + OPERAND_size]
        mov rsi, r11
        mov rdx, r10
        call amd64_emit_prefixes
        mov     al, 0x0F
        call amd64_emit_byte
        mov     al, r13b
        call amd64_emit_byte
        lea     r10, [r12 + INST_op0]  ; the calls above clobber r10/r11
        lea     r11, [r12 + INST_op1]
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
        lea     r10, [r12 + INST_op0]  ; the calls above clobber r10/r11
        mov     al, r14b
        mov rdi, r10
        call amd64_emit_modrm_sib
        lea     r11, [r12 + INST_op1]  ; ...and so does emit_modrm_sib
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
