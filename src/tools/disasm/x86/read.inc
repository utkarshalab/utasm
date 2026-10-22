; ============================================================================
; File        : src/tools/disasm/x86/read.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : reading bytes and ModRM; printing registers, memory, immediates, branches
; ============================================================================


; ============================================================================
; Byte reading
; ============================================================================

; dx_peek: al = next byte without consuming it (sets dx_fail at the end)
dx_peek:
    mov     rcx, [rel dx_cur]
    cmp     rcx, [rel dx_end]
    jae     dx_rd_fail
    movzx   eax, byte [rcx]
    ret

; dx_rd8: eax = next byte (zero-extended), consumed
dx_rd8:
    mov     rcx, [rel dx_cur]
    cmp     rcx, [rel dx_end]
    jae     dx_rd_fail
    movzx   eax, byte [rcx]
    inc     rcx
    mov     [rel dx_cur], rcx
    ret

dx_rd_fail:
    mov     byte [rel dx_fail], 1
    mov     byte [rel dx_trunc], 1         ; (the bytes ran out)
    xor     eax, eax
    ret

; dx_rd16 / dx_rd32 / dx_rd64: rax = next value, zero-extended
dx_rd16:
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 2]
    cmp     rdx, [rel dx_end]
    ja      dx_rd_fail
    movzx   eax, word [rcx]
    mov     [rel dx_cur], rdx
    ret
dx_rd32:
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 4]
    cmp     rdx, [rel dx_end]
    ja      dx_rd_fail
    mov     eax, [rcx]
    mov     [rel dx_cur], rdx
    ret
dx_rd64:
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 8]
    cmp     rdx, [rel dx_end]
    ja      dx_rd_fail
    mov     rax, [rcx]
    mov     [rel dx_cur], rdx
    ret

; ============================================================================
; ModRM / SIB
; ============================================================================

dx_modrm_decode:
    call    dx_rd8
    mov     [rel dx_modrm], al
    mov     rcx, [rel dx_cur]
    mov     [rel dx_after_modrm], rcx
    mov     edx, eax
    shr     edx, 6
    mov     [rel dx_mod], dl
    mov     edx, eax
    shr     edx, 3
    and     edx, 7
    test    byte [rel dx_rex], 4           ; REX.R
    jz      .reg
    or      edx, 8
.reg:
    test    byte [rel dx_rex4], 0x40       ; R4 (APX)
    jz      .reg4
    or      edx, 16
.reg4:
    mov     [rel dx_regno], dl
    and     eax, 7                         ; rm
    mov     byte [rel dx_base], NO_REG
    mov     byte [rel dx_index], NO_REG
    mov     byte [rel dx_scale], 1
    mov     byte [rel dx_hasdisp], 0
    mov     byte [rel dx_riz], 0
    mov     qword [rel dx_disp], 0

    cmp     byte [rel dx_mod], 3
    jne     .memory
    test    byte [rel dx_rex], 1           ; REX.B
    jz      .rmreg
    or      eax, 8
.rmreg:
    test    byte [rel dx_rex4], 0x10       ; B4
    jz      .rmreg4
    or      eax, 16
.rmreg4:
    mov     [rel dx_rmreg], al
    ret

.memory:
    mov     byte [rel dx_a16], 0
    cmp     byte [rel dx_asz], 16
    je      .mem16
    cmp     eax, 4
    je      .sib
    cmp     eax, 5
    jne     .base_rm
    cmp     byte [rel dx_mod], 0
    jne     .base_rm
    cmp     byte [rel dx_mode], 64
    jne     .disp32                        ; (16 / 32-bit mode: [disp32])
    mov     byte [rel dx_base], RIP_REG    ; [rip + disp32]
    mov     byte [rel dx_ripmem], 1
    jmp     .disp32
.mem16:
    ; [bx+si] [bx+di] [bp+si] [bp+di] [si] [di] [bp] [bx]; mod 0 rm 6 a
    ; disp16 alone; disp8 / disp16 after
    mov     byte [rel dx_a16], 1
    lea     rcx, [rel dx_m16_base]
    mov     dl, [rcx + rax]
    mov     [rel dx_base], dl
    lea     rcx, [rel dx_m16_index]
    mov     dl, [rcx + rax]
    mov     [rel dx_index], dl
    cmp     byte [rel dx_mod], 1
    je      .disp8
    cmp     byte [rel dx_mod], 2
    je      .disp16
    cmp     eax, 6
    jne     .m16_ret
    mov     byte [rel dx_base], NO_REG
.disp16:
    call    dx_rd16
    movsx   rax, ax
    mov     [rel dx_disp], rax
    mov     byte [rel dx_hasdisp], 1
.m16_ret:
    ret
.base_rm:
    test    byte [rel dx_rex], 1
    jz      .base_b4
    or      eax, 8
.base_b4:
    test    byte [rel dx_rex4], 0x10
    jz      .base_set
    or      eax, 16
.base_set:
    mov     [rel dx_base], al
    jmp     .disp

.sib:
    call    dx_rd8
    mov     edx, eax
    shr     edx, 6
    mov     cl, dl
    mov     dl, 1
    shl     dl, cl
    mov     [rel dx_scale], dl
    mov     edx, eax
    shr     edx, 3
    and     edx, 7
    test    byte [rel dx_rex], 2           ; REX.X
    jz      .idx
    or      edx, 8
.idx:
    test    byte [rel dx_rex4], 0x20       ; X4: r16-r31 (r20 is an index)
    jz      .idx4
    or      edx, 16
.idx4:
    cmp     byte [rel dx_vsib], 0
    je      .not_vsib
    test    byte [rel dx_vvvv], 16         ; VSIB: EVEX.V' is the index's bit 4
    jz      .vsib_idx
    or      edx, 16
.vsib_idx:
    and     edx, 31
    mov     [rel dx_index], dl             ; (100 is xmm4: there is no "none")
    jmp     .no_index
.not_vsib:
    cmp     edx, 4
    jne     .idx_set
    ; index 100 without REX.X: none - objdump writes riz where the SIB was
    ; not needed (a base but rsp / r12, or a scale)
    mov     ecx, eax
    and     ecx, 7
    cmp     ecx, 4
    jne     .riz
    cmp     byte [rel dx_scale], 1
    je      .no_index
.riz:
    mov     byte [rel dx_riz], 1
    jmp     .no_index
.idx_set:
    mov     [rel dx_index], dl
.no_index:
    and     eax, 7                         ; SIB base
    cmp     eax, 5
    jne     .sib_base
    cmp     byte [rel dx_mod], 0
    je      .disp32                        ; no base, disp32
.sib_base:
    test    byte [rel dx_rex], 1
    jz      .sib_b4
    or      eax, 8
.sib_b4:
    test    byte [rel dx_rex4], 0x10
    jz      .sib_base_set
    or      eax, 16
.sib_base_set:
    mov     [rel dx_base], al

.disp:
    cmp     byte [rel dx_mod], 1
    je      .disp8
    cmp     byte [rel dx_mod], 2
    je      .disp32
    ret
.disp8:
    call    dx_rd8
    movsx   rax, al
    movzx   ecx, byte [rel dx_disp8n]      ; EVEX compressed displacement
    imul    rax, rcx
    mov     [rel dx_disp], rax
    mov     byte [rel dx_hasdisp], 1
    ret
.disp32:
    call    dx_rd32
    movsxd  rax, eax
    mov     [rel dx_disp], rax
    mov     byte [rel dx_hasdisp], 1
    ret

; ============================================================================
; Output helpers
; ============================================================================

; dx_puts: append the string at rsi
dx_puts:
    mov     rdi, [rel dx_fb]
    jmp     fmt_str

; dx_badop: an operand the encoding cannot have (a register where only
; memory goes, ...): objdump writes "(bad)" for it and reads on after the
; opcode's first byte (what follows - an imm8 - is taken from there). A VEX
; / EVEX one: the instruction fails.
dx_badop:
    mov     rax, [rel dx_opstart]
    test    rax, rax
    jz      .fail
    inc     rax
    mov     [rel dx_cur], rax
    mov     byte [rel dx_ripmem], 0        ; (no "# 0x..." for it)
    lea     rsi, [rel s_bad_opnd]
    jmp     dx_puts
.fail:
    mov     byte [rel dx_fail], 1
    ret

; dx_seg_fsgs: "fs:" / "gs:" for an fs / gs override (64-bit mode ignores
; the others' bases: objdump writes them as unused prefixes)
dx_seg_fsgs:
    movzx   eax, byte [rel dx_seg]
    cmp     byte [rel dx_mode], 64
    je      .mode64
    test    eax, eax                       ; (16 / 32-bit mode: any override,
    jnz     .put                           ; else ds:)
    mov     eax, 'd'
    jmp     .put
.mode64:
    cmp     eax, 'f'
    je      .put
    cmp     eax, 'g'
    jne     .ret
.put:
    mov     esi, eax
    call    dx_putc
    mov     esi, 's'
    call    dx_putc
    mov     esi, ':'
    jmp     dx_putc
.ret:
    ret

; dx_putc: append the character in esi
dx_putc:
    mov     rdi, [rel dx_fb]
    jmp     fmt_char

; dx_hex: append "0x" + hex of rsi
dx_hex:
    push    rsi
    mov     esi, '0'
    call    dx_putc
    mov     esi, 'x'
    call    dx_putc
    pop     rsi
dx_hexraw:
    mov     rdi, [rel dx_fb]
    mov     edx, 1
    jmp     fmt_hex

; dx_imm: append rsi (already sign/zero-extended) masked to the operand size
dx_imm:
    movzx   ecx, byte [rel dx_osz]
    cmp     ecx, 64
    je      dx_hex
    mov     rax, 1
    shl     rax, cl
    dec     rax
    and     rsi, rax
    jmp     dx_hex

; .is_branch: ZF = 1 for a near branch (jmp / call / ret / jcc), where F2
; is MPX's bnd
dx_mnemonic.is_branch:
    movzx   eax, byte [rel dx_op]
    cmp     byte [rel dx_map], 2
    jne     .ib_one
    and     eax, 0xF0
    cmp     eax, 0x80                      ; 0F 80-8F: jcc
    ret
.ib_one:
    cmp     byte [rel dx_map], 1
    jne     .ib_no
    cmp     eax, 0xE8
    je      .ib_ret
    cmp     eax, 0xE9
    je      .ib_ret
    cmp     eax, 0xEB
    je      .ib_ret
    cmp     eax, 0xC2
    je      .ib_ret
    cmp     eax, 0xC3
    je      .ib_ret
    cmp     eax, 0xFF
    je      .ib_ff
    and     eax, 0xF0
    cmp     eax, 0x70                      ; jcc rel8
.ib_ret:
    ret
.ib_ff:
    movzx   eax, byte [rel dx_regno]       ; FF /2 call, /4 jmp
    and     eax, 7
    cmp     eax, 2
    je      .ib_ret
    cmp     eax, 4
    ret
.ib_no:
    test    esp, esp
    ret

; dx_mnemonic: the mnemonic (with lock/rep already written), padded as
; objdump pads it when operands follow (esi != 0)
dx_mnemonic:
    push    rsi
    lea     rsi, [rel dx_upfx]             ; unused segment / 66 / 67
    call    dx_puts
    ; F2 / F3 before a locked memory operation (xchg, or with lock) are
    ; xacquire / xrelease; F3 before mov to memory xrelease
    push    rax
    cmp     byte [rel dx_map], 1
    jne     .no_hle
    test    byte [rel dx_flags], FL_MODRM
    jz      .no_hle
    cmp     byte [rel dx_mod], 3
    je      .no_hle
    movzx   eax, byte [rel dx_op]
    cmp     byte [rel dx_lock], 0
    jne     .hle_locked
    and     eax, 0xFE
    cmp     eax, 0x86                      ; xchg
    je      .hle_locked
    cmp     byte [rel dx_rep], 0
    je      .no_hle
    cmp     eax, 0x88                      ; mov r/m, r
    je      .hle_release
    cmp     eax, 0xC6                      ; mov r/m, imm
    jne     .no_hle
.hle_release:
    mov     byte [rel dx_rep], 0
    lea     rsi, [rel s_xrelease]
    call    dx_puts
    jmp     .no_hle
.hle_locked:
    cmp     byte [rel dx_repne], 0
    je      .hle_rep
    mov     byte [rel dx_repne], 0
    lea     rsi, [rel s_xacquire]
    call    dx_puts
    jmp     .no_hle
.hle_rep:
    cmp     byte [rel dx_rep], 0
    jne     .hle_release
.no_hle:
    pop     rax
    ; an F3 / F2 no opcode took: objdump's "repz" / "repnz" - "bnd" on a
    ; branch (MPX)
    cmp     byte [rel dx_repne], 0
    je      .no_repne
    call    .is_branch
    lea     rsi, [rel s_repnz]
    jne     .repne_put
    lea     rsi, [rel s_bnd]
.repne_put:
    call    dx_puts
    jmp     .no_rep
.no_repne:
    cmp     byte [rel dx_rep], 0
    je      .no_rep
    lea     rsi, [rel s_repz]
    call    dx_puts
.no_rep:
    cmp     byte [rel dx_nf], 0
    je      .no_nf
    lea     rsi, [rel s_nf]
    call    dx_puts
.no_nf:
    cmp     byte [rel dx_evexp], 0
    je      .no_evexp
    lea     rsi, [rel s4_evex]
    call    dx_puts
.no_evexp:
    cmp     byte [rel dx_vexp], 0
    je      .no_vexp
    lea     rsi, [rel s_vexp]
    call    dx_puts
.no_vexp:
    cmp     byte [rel dx_lock], 0
    je      .no_lock
    lea     rsi, [rel s_lock]
    call    dx_puts
.no_lock:
    lea     rsi, [rel dx_urex]             ; an unused REX (or bit of it)
    call    dx_puts
    cmp     byte [rel dx_vpfx], 0
    je      .no_v
    mov     esi, 'v'
    call    dx_putc
.no_v:
    mov     rsi, [rel dx_mnem]
    call    dx_puts
    pop     rsi
    test    esi, esi
    jz      .done
    ; pad to 6 columns after the start, then one space
    mov     rdi, [rel dx_fb]
    mov     rdx, [rel dx_textpos]
    add     rdx, 6
    sub     rdx, [rdi + FMTBUF_len]
    jle     .space
    mov     esi, ' '
    call    fmt_pad
.space:
    mov     esi, ' '
    call    dx_putc
.done:
    ret

; dx_sep: ","
dx_sep:
    mov     esi, ','
    jmp     dx_putc

; dx_reg: register name. edi = size (8/16/32/64), esi = number (0-15)
dx_reg:
    ; APX's r16-r31: r16, r16d, r16w, r16b
    cmp     esi, 16
    jb      .low
    cmp     esi, 32
    jae     .low
    lea     rax, [rel rnx64]
    cmp     edi, 64
    je      .have_x
    lea     rax, [rel rnx32]
    cmp     edi, 32
    je      .have_x
    lea     rax, [rel rnx16]
    cmp     edi, 16
    je      .have_x
    lea     rax, [rel rnx8]
.have_x:
    sub     esi, 16
    lea     rsi, [rax + rsi*8]
    jmp     dx_puts
.low:
    lea     rax, [rel rn64]
    cmp     edi, 64
    je      .have
    lea     rax, [rel rn32]
    cmp     edi, 32
    je      .have
    lea     rax, [rel rn16]
    cmp     edi, 16
    je      .have
    lea     rax, [rel rn8rex]
    cmp     byte [rel dx_rex], 0
    jne     .have
    lea     rax, [rel rn8leg]
.have:
    and     esi, 15
    lea     rsi, [rax + rsi*8]
    jmp     dx_puts

; dx_mem: memory operand. edi = size in bits (0 = print no size)
dx_mem:
    push    rbx
    test    edi, edi
    jz      .no_size
    lea     rsi, [rel s_byte]
    cmp     edi, 8
    je      .size
    lea     rsi, [rel s_word]
    cmp     edi, 16
    je      .size
    lea     rsi, [rel s_dword]
    cmp     edi, 32
    je      .size
    lea     rsi, [rel s_xmmword]
    cmp     edi, 128
    je      .size
    lea     rsi, [rel s_ymmword]
    cmp     edi, 256
    je      .size
    lea     rsi, [rel s_tbyte]
    cmp     edi, 80
    je      .size
    lea     rsi, [rel s_fword]
    cmp     edi, 48
    je      .size
    lea     rsi, [rel s_zmmword]
    cmp     edi, 512
    je      .size
    lea     rsi, [rel s_word_bcst]         ; EVEX broadcast: 0x100 + element bits
    cmp     edi, 0x110
    je      .size
    lea     rsi, [rel s_dword_bcst]
    cmp     edi, 0x120
    je      .size
    lea     rsi, [rel s_qword_bcst]
    cmp     edi, 0x140
    je      .size
    lea     rsi, [rel s_oword]
    cmp     edi, 0x180
    je      .size
    lea     rsi, [rel s_qword]
.size:
    call    dx_puts
.no_size:
    movzx   ebx, byte [rel dx_seg]
    test    ebx, ebx
    jz      .no_seg
    mov     esi, ebx
    call    dx_putc
    mov     esi, 's'
    call    dx_putc
    mov     esi, ':'
    call    dx_putc
.no_seg:
    ; absolute [disp32]: ds:0x...
    cmp     byte [rel dx_base], NO_REG
    jne     .bracket
    cmp     byte [rel dx_index], NO_REG
    jne     .bracket
    test    ebx, ebx
    jnz     .abs_value
    lea     rsi, [rel s_ds]
    call    dx_puts
.abs_value:
    mov     rsi, [rel dx_disp]
    cmp     byte [rel dx_mode], 64
    je      .abs_put
    mov     esi, esi                       ; (16 / 32-bit mode: the address's
    cmp     byte [rel dx_asz], 16          ; width)
    jne     .abs_put
    movzx   esi, si
.abs_put:
    call    dx_hex
    pop     rbx
    ret

.bracket:
    mov     esi, '['
    call    dx_putc
    xor     ebx, ebx                       ; ebx = something printed
    movzx   eax, byte [rel dx_base]
    cmp     eax, NO_REG
    je      .index
    cmp     eax, RIP_REG
    jne     .base_reg
    lea     rsi, [rel s_rip]
    cmp     byte [rel dx_p67], 0
    je      .rip_name
    lea     rsi, [rel s_eip]
.rip_name:
    call    dx_puts
    mov     ebx, 1
    jmp     .index
.base_reg:
    call    .addr_size
    mov     esi, eax
    call    dx_reg
    mov     ebx, 1
.index:
    movzx   eax, byte [rel dx_index]
    cmp     eax, NO_REG
    jne     .index_have
    cmp     byte [rel dx_riz], 0
    je      .disp
    test    ebx, ebx                       ; "+riz*N" (objdump's)
    jz      .riz_put
    mov     esi, '+'
    call    dx_putc
.riz_put:
    lea     rsi, [rel s_riz]
    cmp     byte [rel dx_asz], 32
    jne     .riz_named
    lea     rsi, [rel s_eiz]
.riz_named:
    call    dx_puts
    mov     esi, '*'
    call    dx_putc
    movzx   esi, byte [rel dx_scale]
    add     esi, '0'
    call    dx_putc
    mov     ebx, 1
    jmp     .disp
.index_have:
    test    ebx, ebx
    jz      .index_reg
    push    rax
    mov     esi, '+'
    call    dx_putc
    pop     rax
.index_reg:
    movzx   edi, byte [rel dx_vsib]
    test    edi, edi
    jz      .index_gpr
    mov     esi, eax                       ; VSIB: a vector register
    call    dx_vecreg_c
    jmp     .index_scale
.index_gpr:
    call    .addr_size
    mov     esi, eax
    call    dx_reg
.index_scale:
    cmp     byte [rel dx_a16], 0           ; ([bx+si]: no scale)
    jne     .disp
    mov     esi, '*'
    call    dx_putc
    movzx   esi, byte [rel dx_scale]
    add     esi, '0'
    call    dx_putc
.disp:
    cmp     byte [rel dx_hasdisp], 0
    je      .close
    mov     rsi, [rel dx_disp]
    cmp     byte [rel dx_base], RIP_REG
    je      .plus                          ; rip: objdump shows +0xffff...
    test    rsi, rsi
    js      .minus
.plus:
    push    rsi
    mov     esi, '+'
    call    dx_putc
    pop     rsi
    call    dx_hex
    jmp     .close
.minus:
    neg     rsi
    push    rsi
    mov     esi, '-'
    call    dx_putc
    pop     rsi
    call    dx_hex
.close:
    mov     esi, ']'
    call    dx_putc
    pop     rbx
    ret
.addr_size:                                ; edi = the address size
    movzx   edi, byte [rel dx_asz]
    ret

; dx_rm: the ModRM r/m operand at size edi (register or memory)
dx_rm:
    cmp     byte [rel dx_mod], 3
    jne     dx_mem
    movzx   esi, byte [rel dx_rmreg]
    jmp     dx_reg

; dx_greg: the ModRM reg operand at size edi
dx_greg:
    movzx   esi, byte [rel dx_regno]
    jmp     dx_reg

; dx_opreg: register encoded in the opcode's low bits (+ REX.B), size edi
dx_opreg:
    movzx   esi, byte [rel dx_op]
    and     esi, 7
    test    byte [rel dx_rex4], 0x10       ; B4
    jz      .op_b3
    or      esi, 16
.op_b3:
    test    byte [rel dx_rex], 1
    jz      dx_reg
    or      esi, 8
    jmp     dx_reg

; dx_branch: rsi = sign-extended displacement; prints the target address
dx_branch:
    mov     rax, [rel dx_cur]
    sub     rax, [rel dx_start]
    add     rax, [rel dx_addr]             ; address of the next instruction
    add     rsi, rax
    cmp     byte [rel dx_mode], 64         ; (16 / 32-bit mode: the address's
    je      .br_put                        ; 32 bits, as objdump writes it)
    mov     esi, esi
.br_put:
    mov     [rel dx_target], rsi
    cmp     byte [rel x86_hex0x], 0
    je      dx_hexraw
    jmp     dx_hex
