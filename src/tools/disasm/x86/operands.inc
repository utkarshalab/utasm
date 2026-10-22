; ============================================================================
; File        : src/tools/disasm/x86/operands.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : dx_operands: the operand forms
; ============================================================================


; ============================================================================
; Operands, by form
; ============================================================================

dx_operands:
    push    rbx
    movzx   ebx, byte [rel dx_osz]         ; ebx = operand size
    movzx   eax, byte [rel dx_form]

    cmp     eax, FM_NONE
    je      .f_none
    cmp     eax, FM_EbGb
    je      .f_EG
    cmp     eax, FM_EvGv
    je      .f_EG
    cmp     eax, FM_EvGv_bt
    je      .f_EG
    cmp     eax, FM_GbEb
    je      .f_GE
    cmp     eax, FM_GvEv
    je      .f_GE
    cmp     eax, FM_ALIb
    je      .f_accI
    cmp     eax, FM_eAXIz
    je      .f_accI
    cmp     eax, FM_Zv
    je      .f_Zv
    cmp     eax, FM_ZbIb
    je      .f_ZI
    cmp     eax, FM_ZvIv
    je      .f_ZvIv
    cmp     eax, FM_Jb
    je      .f_Jb
    cmp     eax, FM_Jz
    je      .f_Jz
    cmp     eax, FM_Eb
    je      .f_E
    cmp     eax, FM_Ev
    je      .f_E
    cmp     eax, FM_EbIb
    je      .f_EI
    cmp     eax, FM_EvIz
    je      .f_EI
    cmp     eax, FM_EvIb
    je      .f_EI
    cmp     eax, FM_Eb1
    je      .f_E1
    cmp     eax, FM_Ev1
    je      .f_E1
    cmp     eax, FM_EbCL
    je      .f_ECL
    cmp     eax, FM_EvCL
    je      .f_ECL
    cmp     eax, FM_EbIbU
    je      .f_EIU
    cmp     eax, FM_EvIbU
    je      .f_EIU
    cmp     eax, FM_GvM
    je      .f_GM
    cmp     eax, FM_GvEvIz
    je      .f_GEI
    cmp     eax, FM_GvEvIb
    je      .f_GEI
    cmp     eax, FM_GvEb
    je      .f_GEx
    cmp     eax, FM_GvEw
    je      .f_GEx
    cmp     eax, FM_GvEd
    je      .f_GEx
    cmp     eax, FM_IbU
    je      .f_IbU
    cmp     eax, FM_IbS
    je      .f_IbS
    cmp     eax, FM_Iz
    je      .f_Iz
    cmp     eax, FM_Iw
    je      .f_Iw
    cmp     eax, FM_ZvXchg
    je      .f_xchg
    cmp     eax, FM_EvGvIb
    je      .f_EGI
    cmp     eax, FM_EvGvCL
    je      .f_EGCL
    cmp     eax, FM_STR
    je      .f_str
    cmp     eax, FM_XCHG90
    je      .f_90
    cmp     eax, FM_CBW
    je      .f_cbw
    cmp     eax, FM_CWD
    je      .f_cwd
    cmp     eax, FM_Ewv
    je      .f_Ewv
    cmp     eax, FM_G7
    je      .f_g7
    cmp     eax, FM_GAE
    je      .f_gae
    cmp     eax, FM_EVEX
    je      .f_evex
    cmp     eax, FM_G9
    je      .f_g9
    cmp     eax, FM_GaM
    je      .f_GaM
    cmp     eax, FM_WRSS
    je      .f_WRSS
    cmp     eax, FM_G64MO
    je      .f_G64MO
    cmp     eax, FM_G64M
    je      .f_G64M
    cmp     eax, FM_IO
    je      .f_IO
    cmp     eax, FM_SREGW
    je      .f_SREGW
    cmp     eax, FM_SREGR
    je      .f_SREGR
    cmp     eax, FM_FSGS
    je      .f_FSGS
    cmp     eax, FM_GvMp
    je      .f_GvMp
    cmp     eax, FM_IwIb
    je      .f_IwIb
    cmp     eax, FM_XLAT
    je      .f_XLAT
    cmp     eax, FM_SFXW
    je      .f_SFXW
    cmp     eax, FM_SFXD
    je      .f_SFXD
    cmp     eax, FM_GEwv
    je      .f_GEwv
    cmp     eax, FM_SFXWI
    je      .f_SFXWI
    cmp     eax, FM_D3NOW
    je      .f_D3NOW
    cmp     eax, FM_BGE
    je      .f_BGE
    cmp     eax, FM_BBM
    je      .f_BBM
    cmp     eax, FM_BMB
    je      .f_BMB
    cmp     eax, FM_BM
    je      .f_BM
    cmp     eax, FM_MB
    je      .f_MB
    cmp     eax, FM_SSE4AI
    je      .f_SSE4AI
    cmp     eax, FM_SSE4AR
    je      .f_SSE4AR
    cmp     eax, FM_CRC
    je      .f_CRC
    cmp     eax, FM_SEGOP
    je      .f_SEGOP
    cmp     eax, FM_BOUND
    je      .f_BOUND
    cmp     eax, FM_ARPL
    je      .f_ARPL
    cmp     eax, FM_AP
    je      .f_AP
    cmp     eax, FM_MOFFS
    je      .f_MOFFS
    cmp     eax, FM_MP
    je      .f_MP
    cmp     eax, FM_CRDR
    je      .f_CRDR
    cmp     eax, FM_GvMv
    je      .f_GvMv
    cmp     eax, FM_MvGv
    je      .f_MvGv
    cmp     eax, FM_Mb
    je      .f_Mb
    cmp     eax, FM_PADLOCK
    je      .f_PADLOCK
    cmp     eax, FM_KLW
    je      .f_KLW
    cmp     eax, FM_KLV
    je      .f_KLV
    cmp     eax, FM_KLE
    je      .f_KLE
    cmp     eax, FM_SFX66
    je      .f_SFX66
    cmp     eax, FM_XABEG
    je      .f_XABEG
    cmp     eax, FM_VW
    jb      .unknown_form
    call    dx_sse_operands
    jmp     .done
.f_evex:
    call    dx_evex_operands
    jmp     .done

.f_g9:                                     ; 0F C7
    lea     rsi, [rel pg_0fc7]
    call    dx_pgrp
    test    eax, eax
    jnz     .done
    cmp     byte [rel dx_pgnone], 0        ; (vmptrld's F2: taken, none)
    jne     .g9_taken
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     byte [rel dx_mod], 3
    je      .g9_reg
    cmp     eax, 1                         ; cmpxchg8b m64 / cmpxchg16b m128
    jne     .sys_bad
    lea     rsi, [rel s_cmpxchg8b]
    mov     ebx, 64
    test    byte [rel dx_rex], 8
    jz      .g9_mem
    lea     rsi, [rel s_cmpxchg16b]
    mov     ebx, 0x180                     ; OWORD PTR
.g9_mem:
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_mem
    jmp     .done
.g9_reg:                                   ; rdrand / rdseed r16/32/64
    lea     rsi, [rel g9_badop_names]      ; (a memory one's: objdump's "xsavec
    mov     ecx, eax                       ; (bad)", 64 with W)
    shl     ecx, 5
    test    byte [rel dx_rex], 8
    jz      .g9_bo_w
    add     ecx, 16
.g9_bo_w:
    add     rsi, rcx
    cmp     byte [rsi], 0
    je      .g9_not_bo
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    call    dx_badop
    jmp     .done
.g9_not_bo:
    lea     rsi, [rel s_rdrand]
    cmp     eax, 6
    je      .g9_rchk
    lea     rsi, [rel s_rdseed]
    cmp     eax, 7
    jne     .sys_bad
.g9_rchk:
    mov     cl, [rel dx_repne]             ; (F2, an F3 not senduipi / rdpid's:
    or      cl, [rel dx_rep]               ; objdump's prefix table - taken,
    jz      .g9_rput                       ; none)
.g9_taken:
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .f_undef_op
.g9_rput:
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .done
.unknown_form:
    mov     byte [rel dx_fail], 1
    jmp     .done

; ---- the system / I/O forms (FM_GaM ... FM_SFXD) ----
.f_GaM:                                    ; enqcmd / movdir64b: r (address size), m
    cmp     byte [rel dx_mod], 3
    jne     .gam_go
    movzx   eax, byte [rel dx_ssepfx]      ; (a register: no instruction - an
    cmp     eax, 2                         ; F3 / F2 named, a 66 not)
    jne     .gam_f2
    mov     byte [rel dx_rep], 1
.gam_f2:
    cmp     eax, 3
    jne     .gam_66
    mov     byte [rel dx_repne], 1
.gam_66:
    cmp     eax, 1                         ; (movdir64b's 66: named outside
    jne     .gam_bad                       ; 64-bit mode, as objdump has it)
    cmp     byte [rel dx_mode], 64
    je      .gam_bad
    mov     byte [rel dx_sel66], 0
.gam_bad:
    jmp     .f_undef_op
.gam_go:
    mov     esi, 1
    call    dx_mnemonic
    movzx   edi, byte [rel dx_asz]
.gam_reg:
    call    dx_greg
    call    dx_sep
    xor     edi, edi
    call    dx_mem
    jmp     .done
.f_WRSS:                                   ; wrss / wruss + d / q: m, r
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.wrss_copy:
    mov     al, [rsi]
    test    al, al
    jz      .wrss_sfx
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .wrss_copy
.wrss_sfx:
    mov     ebx, 32
    mov     al, 'd'
    test    byte [rel dx_rex], 8
    jz      .wrss_put
    mov     ebx, 64
    mov     al, 'q'
.wrss_put:
    mov     [rdi], al
    mov     byte [rdi + 1], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    xor     edi, edi
    call    .mem_only
    call    dx_sep
    mov     edi, ebx
    call    dx_greg
    jmp     .done
.f_G64MO:                                  ; invept / invvpid: r64, m128
    mov     ebx, 0x180                     ; (OWORD PTR)
    jmp     .g64m
.f_G64M:                                   ; invpcid: r64, m (no size)
    xor     ebx, ebx
.g64m:
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 64
    cmp     byte [rel dx_mode], 64
    je      .g64m_reg
    mov     edi, 32
.g64m_reg:
    call    dx_greg
    call    dx_sep
    mov     edi, ebx
    call    .mem_only
    jmp     .done
.f_IO:                                     ; in / out: E4-E7 (imm8), EC-EF (dx)
    movzx   eax, byte [rel dx_op]
    mov     ebx, 8                         ; the accumulator: al, or ax / eax
    test    eax, 1
    jz      .io_size
    mov     ebx, 32
    cmp     byte [rel dx_osz], 16
    jne     .io_size
    mov     ebx, 16
.io_size:
    xor     r8d, r8d                       ; the port: imm8 read first
    test    eax, 8
    jnz     .io_go
    call    dx_rd8
    movzx   r8d, al
.io_go:
    mov     [rel dx_port], r8              ; (dx_reg / dx_sep keep no r8)
    mov     esi, 1
    call    dx_mnemonic
    test    byte [rel dx_op], 2            ; E6 / E7 / EE / EF: out port, acc
    jnz     .io_out
    mov     edi, ebx
    xor     esi, esi
    call    dx_reg
    call    dx_sep
    call    .io_port
    jmp     .done
.io_out:
    call    .io_port
    call    dx_sep
    mov     edi, ebx
    xor     esi, esi
    call    dx_reg
    jmp     .done
.io_port:
    test    byte [rel dx_op], 8
    jz      .io_imm
    mov     edi, 16
    mov     esi, 2                         ; dx
    jmp     dx_reg
.io_imm:
    mov     rsi, [rel dx_port]
    jmp     dx_hex
.f_SREGW:                                  ; 8C: mov r/m, sreg
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    cmp     byte [rel dx_mod], 3
    je      .sregw_rm
    mov     edi, 16                        ; (memory: WORD)
.sregw_rm:
    call    dx_rm
    call    dx_sep
    call    .sreg_name
    jmp     .done
.f_SREGR:                                  ; 8E: mov sreg, r/m
    mov     esi, 1
    call    dx_mnemonic
    call    .sreg_name
    call    dx_sep
    mov     edi, ebx
    cmp     byte [rel dx_mod], 3
    je      .sregr_rm
    mov     edi, 16
.sregr_rm:
    call    dx_rm
    jmp     .done
.sreg_name:                                ; ModRM.reg's segment register (6 / 7:
    movzx   eax, byte [rel dx_regno]       ; none - objdump's "?")
    and     eax, 7
    cmp     eax, 5
    jbe     .sreg_known
    mov     esi, '?'
    jmp     dx_putc
.sreg_known:
    lea     rsi, [rel sreg_names]
    lea     rsi, [rsi + rax * 4]
    jmp     dx_puts
.f_FSGS:                                   ; 0F A0 / A1 / A8 / A9: push / pop fs / gs
    call    .sfx66
    mov     esi, 1
    call    dx_mnemonic
    lea     rsi, [rel sreg_names + 16]     ; fs
    test    byte [rel dx_op], 8
    jz      .fsgs_put
    lea     rsi, [rel sreg_names + 20]     ; gs
.fsgs_put:
    call    dx_puts
    jmp     .done
.f_GvMp:                                   ; lss / lfs / lgs: r, a far pointer
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    mov     edi, 32                        ; the pointer: 16:16 DWORD, else
    cmp     ebx, 16                        ; FWORD (objdump's, 16:64 too)
    je      .gvmp_mem
    mov     edi, 48
.gvmp_mem:
    call    .mem_only
    jmp     .done
.f_GEwv:                                   ; lar / lsl: r, r/m (memory WORD)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    mov     edi, ebx
    cmp     byte [rel dx_mod], 3
    je      .gewv_rm
    mov     edi, 16
.gewv_rm:
    call    dx_rm
    jmp     .done
.f_IwIb:                                   ; enter imm16, imm8
    call    dx_rd16
    movzx   ebx, ax
    call    dx_rd8
    push    rax
    push    rax
    call    .sfx66
    mov     esi, 1
    call    dx_mnemonic
    mov     esi, ebx
    call    dx_hex
    call    dx_sep
    pop     rsi
    pop     rsi
    movzx   esi, sil
    call    dx_hex
    jmp     .done
.f_XLAT:                                   ; xlat: BYTE PTR [rbx] (fs: / gs:, [ebx])
    mov     esi, 1
    call    dx_mnemonic
    lea     rsi, [rel s_byte]
    call    dx_puts
    call    dx_seg_fsgs
    lea     rsi, [rel s_xlat_rbx]
    cmp     byte [rel dx_asz], 64
    je      .xlat_put
    lea     rsi, [rel s_xlat_ebx]
    cmp     byte [rel dx_asz], 32
    je      .xlat_put
    lea     rsi, [rel s_xlat_bx]
.xlat_put:
    call    dx_puts
    jmp     .done
.f_SFXW:                                   ; retf / iret / pushf / popf: w with
    xor     ecx, ecx                       ; 66, q with REX.W, else none
    test    byte [rel dx_rex], 8
    jz      .sfx_66
    mov     al, [rel dx_op]                ; (pushf / popf: REX.W unused - no
    and     al, 0xFE                       ; suffix, a 66 unused too)
    cmp     al, 0x9C
    je      .sfx_name
    mov     ecx, 'q'
    jmp     .sfx_name
.sfx_66:
    cmp     byte [rel dx_p66], 0
    je      .sfx_name
    mov     byte [rel dx_p66], 0           ; (the suffix is it)
    dec     byte [rel dx_n66]
    mov     ecx, 'w'
    cmp     byte [rel dx_mode], 16
    jne     .sfx_name
    mov     ecx, 'd'                       ; (16-bit mode: 66 is 32 bits)
    jmp     .sfx_name
; ---- MPX: bnd, r/m64 (memory of no size) / bnd, bnd/m / bnd/m, bnd /
; bnd, m / m, bnd ----
.f_BGE:
    mov     esi, 1
    call    dx_mnemonic
    call    .bnd_reg
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    jne     .bnd_nomem
    mov     edi, 64
    cmp     byte [rel dx_mode], 64
    je      .bge_reg
    mov     edi, 32
.bge_reg:
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .done
.f_BBM:
    mov     esi, 1
    call    dx_mnemonic
    call    .bnd_reg
    call    dx_sep
    call    .bnd_rm
    jmp     .done
.f_BMB:
    mov     esi, 1
    call    dx_mnemonic
    call    .bnd_rm
    call    dx_sep
    call    .bnd_reg
    jmp     .done
.f_BM:
    cmp     byte [rel dx_mod], 3
    je      .bnd_nop
    mov     esi, 1
    call    dx_mnemonic
    call    .bnd_reg
    call    dx_sep
.bnd_nomem:
    call    .bnd_mem
    jmp     .done
.f_MB:
    cmp     byte [rel dx_mod], 3
    je      .bnd_nop
    mov     esi, 1
    call    dx_mnemonic
    call    .bnd_mem
    call    dx_sep
    call    .bnd_reg
    jmp     .done
.bnd_nop:                                  ; bndldx / bndstx with a register: the
    mov     rax, [rel dx_mnem]             ; 0F 1A / 1B hint nop (objdump 2.47);
    cmp     byte [rax + 3], 'l'            ; bndmk's: its F3 a "repz"
    je      .bnd_nop_put
    cmp     byte [rax + 3], 's'
    je      .bnd_nop_put
    cmp     byte [rax + 3], 'm'
    jne     .sys_bad
    mov     byte [rel dx_rep], 1
.bnd_nop_put:
    lea     rax, [rel s_hint_nop]
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    jmp     .done
.bnd_reg:                                  ; ModRM.reg's bnd register
    movzx   esi, byte [rel dx_regno]
    jmp     .bnd_put
.bnd_rm:                                   ; a bnd register or memory (no size)
    cmp     byte [rel dx_mod], 3
    je      .bnd_rmreg
.bnd_mem:                                  ; (16-bit addressing: none - "(bad)")
    cmp     byte [rel dx_a16], 0
    jne     .bnd_bad_mem
    cmp     byte [rel dx_base], RIP_REG    ; (bndldx / bndstx / bndmk's [rip]:
    jne     .bnd_mem_put                   ; none either, the displacement read)
    mov     rax, [rel dx_mnem]
    cmp     byte [rax + 3], 'l'
    je      .bnd_mem_rip
    cmp     byte [rax + 3], 's'
    je      .bnd_mem_rip
    cmp     word [rax + 3], "mk"           ; (and bndmk's)
    jne     .bnd_mem_put
.bnd_mem_rip:
    mov     byte [rel dx_ripmem], 0
    lea     rsi, [rel s_bad_opnd]
    jmp     dx_puts
.bnd_mem_put:
    xor     edi, edi
    jmp     dx_mem
.bnd_bad_mem:
    mov     rax, [rel dx_after_modrm]      ; (objdump reads no displacement)
    mov     [rel dx_cur], rax
    lea     rsi, [rel s_bad_opnd]
    jmp     dx_puts
.bnd_rmreg:
    movzx   esi, byte [rel dx_rmreg]
.bnd_put:
    cmp     esi, 3                         ; bnd4-15 (REX.R / B): none
    ja      .bnd_bad
    push    rsi
    lea     rsi, [rel s_bnd_reg]
    call    dx_puts
    pop     rsi
    add     esi, '0'
    jmp     dx_putc
.bnd_bad:
    cmp     byte [rel dx_trialing], 0      ; (a trial: which one, so that a
    je      .bnd_bad_put                   ; REX bit making it is used)
    add     esi, 'a'
    jmp     dx_putc
.bnd_bad_put:
    lea     rsi, [rel s_bad_opnd]
    jmp     dx_puts
; ---- SSE4a: extrq / insertq ----
.f_SSE4AI:                                 ; 78: extrq xmm, ib, ib / insertq xmm, xmm, ib, ib
    cmp     byte [rel dx_mod], 3
    je      .s4ai_regs
    ; memory: "(bad)" for it, the imm8s read on after the opcode's 0F
    mov     esi, 1
    call    dx_mnemonic
    mov     rax, [rel dx_mnem]
    cmp     byte [rax], 'e'
    je      .s4ai_bad
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    call    dx_vecreg_c
    call    dx_sep
.s4ai_bad:
    call    dx_badop
    call    dx_sep
    call    dx_rd8
    mov     esi, eax
    call    dx_hex
    call    dx_sep
    call    dx_rd8
    mov     esi, eax
    call    dx_hex
    jmp     .done
.s4ai_regs:
    call    dx_rd8
    movzx   ebx, al
    call    dx_rd8
    movzx   eax, al
    mov     [rel dx_port], rax             ; (the second imm8)
    mov     esi, 1
    call    dx_mnemonic
    mov     rax, [rel dx_mnem]
    cmp     byte [rax], 'e'                ; extrq: the register in rm only
    je      .s4a_rm
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    call    dx_vecreg_c
    call    dx_sep
.s4a_rm:
    mov     edi, 1
    movzx   esi, byte [rel dx_rmreg]
    call    dx_vecreg_c
    call    dx_sep
    mov     esi, ebx
    call    dx_hex
    call    dx_sep
    mov     rsi, [rel dx_port]
    call    dx_hex
    jmp     .done
.f_SEGOP:                                  ; push / pop es / cs / ss / ds
    call    .sfx66
    mov     esi, 1
    call    dx_mnemonic
    movzx   eax, byte [rel dx_op]
    shr     eax, 3
    and     eax, 3
    lea     rsi, [rel sreg_names]
    lea     rsi, [rsi + rax * 4]
    call    dx_puts
    jmp     .done
.f_BOUND:                                  ; bound r, m16&16 / m32&32
    cmp     byte [rel dx_mod], 3
    je      .sys_bad
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    lea     edi, [rbx + rbx]
    call    dx_mem
    jmp     .done
.f_ARPL:                                   ; arpl r/m16, r (a register at the
    mov     esi, 1                         ; operand size, as objdump writes)
    call    dx_mnemonic
    mov     edi, ebx
    cmp     byte [rel dx_mod], 3
    je      .arpl_rm
    mov     edi, 16
.arpl_rm:
    call    dx_rm
    call    dx_sep
    mov     edi, ebx
    call    dx_greg
    jmp     .done
.f_CRDR:                                   ; 0F 20-23: the register ModRM.rm's
    test    byte [rel dx_op], 4            ; (0F 24 / 26, the test registers:
    jz      .crdr_ok                       ; none in 64-bit mode)
    cmp     byte [rel dx_mode], 64
    je      .f_undef_op
.crdr_ok:
    mov     rax, [rel dx_after_modrm]      ; (the ModRM a register's whatever
    mov     [rel dx_cur], rax              ; mod says: no SIB, no displacement)
    mov     byte [rel dx_ripmem], 0
    mov     esi, 1                         ; whatever mod says, 64 / 32 bits by
    call    dx_mnemonic                    ; the mode; crN / drN ModRM.reg's
    test    byte [rel dx_op], 2
    jnz     .crdr_to
    call    .crdr_gpr
    call    dx_sep
    call    .crdr_cr
    jmp     .done
.crdr_to:
    call    .crdr_cr
    call    dx_sep
    call    .crdr_gpr
    jmp     .done
.crdr_gpr:
    mov     edi, 64
    cmp     byte [rel dx_mode], 64
    je      .crdr_g
    mov     edi, 32
.crdr_g:
    movzx   esi, byte [rel dx_modrm]
    and     esi, 7
    test    byte [rel dx_rex], 1
    jz      .crdr_g_put
    or      esi, 8
.crdr_g_put:
    jmp     dx_reg
.crdr_cr:
    lea     rsi, [rel s_tr]
    test    byte [rel dx_op], 4
    jnz     .crdr_c_name
    lea     rsi, [rel s_cr]
    test    byte [rel dx_op], 1
    jz      .crdr_c_name
    lea     rsi, [rel s_dr]
.crdr_c_name:
    call    dx_puts
    movzx   esi, byte [rel dx_regno]
    and     esi, 15
    cmp     esi, 10
    jb      .crdr_digit
    push    rsi
    push    rsi
    mov     esi, '1'
    call    dx_putc
    pop     rsi
    pop     rsi
    sub     esi, 10
.crdr_digit:
    add     esi, '0'
    jmp     dx_putc
.f_MP:                                     ; call / jmp far [m]: DWORD (16:16) with a
    mov     esi, 1                         ; 16-bit operand size, else FWORD
    call    dx_mnemonic
    cmp     byte [rel dx_mod], 3           ; (a register: objdump's "call (bad)")
    jne     .mp_go
    call    dx_badop
    jmp     .done
.mp_go:
    mov     edi, 48
    cmp     ebx, 16
    jne     .mp_mem
    mov     edi, 32
.mp_mem:
    call    dx_mem
    jmp     .done
.f_MOFFS:                                  ; A0-A3: the offset as wide as the address
    movzx   eax, byte [rel dx_asz]
    cmp     eax, 64
    je      .mo_64
    cmp     eax, 32
    je      .mo_32
    call    dx_rd16
    jmp     .mo_have
.mo_32:
    call    dx_rd32
    jmp     .mo_have
.mo_64:
    call    dx_rd64
    lea     rcx, [rel s_movabs]            ; (objdump's movabs)
    mov     [rel dx_mnem], rcx
.mo_have:
    mov     [rel dx_port], rax             ; (the offset)
    ; 67: objdump names it ("addr32 mov ax, ds:0x..."), used or not
    cmp     byte [rel dx_p67], 0
    je      .mo_named
    lea     rdi, [rel dx_upfx]
    lea     rsi, [rel s_u67]
    cmp     byte [rel dx_mode], 32
    jne     .mo_cat
    lea     rsi, [rel s_u67_16]
.mo_cat:
    call    dx_strcat
.mo_named:
    mov     esi, 1
    call    dx_mnemonic
    test    byte [rel dx_op], 2
    jnz     .mo_store
    call    .mo_acc
    call    dx_sep
    call    .mo_mem
    jmp     .done
.mo_store:
    call    .mo_mem
    call    dx_sep
    call    .mo_acc
    jmp     .done
.mo_acc:
    mov     edi, ebx
    xor     esi, esi
    jmp     dx_reg
.mo_mem:                                   ; ds:0x... (or the override's)
    movzx   esi, byte [rel dx_seg]
    test    esi, esi
    jnz     .mo_seg
    mov     esi, 'd'
.mo_seg:
    call    dx_putc
    mov     esi, 's'
    call    dx_putc
    mov     esi, ':'
    call    dx_putc
    mov     rsi, [rel dx_port]
    jmp     dx_hex
.f_AP:                                     ; call / jmp 0xseg:0xoffset
    cmp     ebx, 16
    je      .ap_16
    call    dx_rd32
    jmp     .ap_seg
.ap_16:
    call    dx_rd16
.ap_seg:
    push    rax
    call    dx_rd16
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_hex
    mov     esi, ':'
    call    dx_putc
    pop     rsi
    call    dx_hex
    jmp     .done
.f_CRC:                                    ; crc32 r32/r64, r/m8 / r/m16/32/64
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .crc_g
    mov     edi, 64
.crc_g:
    call    dx_greg
    call    dx_sep
    mov     edi, 8
    cmp     byte [rel dx_op], 0xF0
    je      .crc_e
    mov     edi, ebx                       ; (66: a word)
.crc_e:
    call    dx_rm
    jmp     .done
.f_SSE4AR:                                 ; 79: extrq / insertq xmm, xmm
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    call    dx_vecreg_c
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    je      .s4ar_reg
    call    dx_badop
    jmp     .done
.s4ar_reg:
    mov     edi, 1
    movzx   esi, byte [rel dx_rmreg]
    call    dx_vecreg_c
    jmp     .done
.f_D3NOW:                                  ; 0F 0F /r ib: the ib names it
    call    dx_rd8
    movzx   eax, al
    lea     rsi, [rel d3now_names]
.d3_scan:
    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .d3_bad
    cmp     ecx, eax
    je      .d3_found
    add     rsi, 12
    jmp     .d3_scan
.d3_bad:                                   ; (objdump reads on after the 0F)
    mov     byte [rel dx_sel66], 1         ; (a 66 here: no unused one)
    mov     rax, [rel dx_opstart]
    inc     rax
    mov     [rel dx_cur], rax
    lea     rax, [rel s_bad_opnd]
    mov     [rel dx_mnem], rax
    jmp     .f_none
.d3_found:
    inc     rsi
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    xor     edi, edi                       ; mm
    movzx   esi, byte [rel dx_regno]
    and     esi, 7
    call    dx_vecreg_c
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    jne     .d3_mem
    xor     edi, edi
    movzx   esi, byte [rel dx_rmreg]
    and     esi, 7
    call    dx_vecreg_c
    jmp     .done
.d3_mem:
    mov     edi, 64
    call    dx_mem
    jmp     .done
.f_SFXWI:                                  ; ret / retf imm16: w with 66, q with
    cmp     byte [rel dx_op], 0xCA         ; REX.W for retf (a 64-bit ret is
    jne     .sfxwi_ret                     ; its own)
    test    byte [rel dx_rex], 8
    jz      .sfxwi_ret
    mov     ecx, 'q'
    jmp     .sfxwi_named
.sfxwi_ret:
    cmp     byte [rel dx_p66], 0
    je      .f_Iw_ret
    mov     byte [rel dx_p66], 0
    dec     byte [rel dx_n66]
    mov     ecx, 'w'
    cmp     byte [rel dx_mode], 16
    jne     .sfxwi_named
    mov     ecx, 'd'
.sfxwi_named:
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.sfxwi_copy:
    mov     al, [rsi]
    test    al, al
    jz      .sfxwi_end
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .sfxwi_copy
.sfxwi_end:
    mov     [rdi], cl
    mov     byte [rdi + 1], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.f_Iw_ret:
    call    dx_rd16
    movzx   esi, ax
    push    rsi
    push    rsi
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    pop     rsi
    call    dx_hex
    jmp     .done
.f_SFXD:                                   ; sysexit / sysret: d, or q with REX.W
    cmp     byte [rel dx_mode], 64
    jne     .f_none                        ; (16 / 32-bit mode: none)
    mov     ecx, 'd'
    test    byte [rel dx_rex], 8
    jz      .sfx_name
    mov     ecx, 'q'
.sfx_name:
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.sfx_copy:
    mov     al, [rsi]
    test    al, al
    jz      .sfx_end
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .sfx_copy
.sfx_end:
    mov     [rdi], cl
    mov     byte [rdi + 1], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
    jmp     .f_none


.f_Ewv:                                    ; register at operand size, memory WORD
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    cmp     byte [rel dx_mod], 3
    je      .ewv_put
    mov     edi, 16
.ewv_put:
    call    dx_rm
    jmp     .done

.f_g7:                                     ; 0F 01
    cmp     byte [rel dx_mod], 3
    je      .g7_reg
    ; F3 0F 01 /5 m64: rstorssp (CET)
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 5
    jne     .g7_mem
    cmp     byte [rel dx_rep], 0
    jne     .g7_rstorssp
    mov     al, [rel dx_p66]               ; (66 / F2: objdump's prefix table -
    or      al, [rel dx_repne]             ; taken, no instruction)
    jz      .g7_mem
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .f_undef_op
.g7_rstorssp:
    mov     byte [rel dx_rep], 0
    lea     rsi, [rel s_rstorssp]
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 64
    call    dx_mem
    jmp     .done
.g7_mem:
    lea     rsi, [rel g7_mem_names]
    lea     rdi, [rel g7_mem_sizes]
    cmp     byte [rel dx_mode], 64
    je      .sys_mem
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 3
    ja      .sys_mem
    mov     byte [rel dx_sysfx], 'd'       ; (16 / 32-bit mode: the operand
    cmp     ebx, 16                        ; size said, objdump's sgdtw / lidtd)
    jne     .sys_mem
    mov     byte [rel dx_sysfx], 'w'
    jmp     .sys_mem
.g7_reg:
    ; smsw r / lmsw r (reg 4 / 6), else the whole ModRM byte selects it
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 4
    je      .g7_msw
    cmp     eax, 6
    je      .g7_msw
    ; ... with the mandatory prefix there is (66 / F3 / F2), else none
    xor     edx, edx
    cmp     byte [rel dx_p66], 0
    je      .g7_f3
    mov     edx, 1
.g7_f3:
    cmp     byte [rel dx_rep], 0
    je      .g7_f2
    mov     edx, 2
.g7_f2:
    cmp     byte [rel dx_repne], 0
    je      .g7_pfx
    mov     edx, 3
.g7_pfx:
    ; 64-bit mode's alone (seamcall, uiret, erets, the RMP ones ...): in 16 /
    ; 32-bit mode no instruction - "(bad)" through 0F 01, as objdump reads it
    movzx   eax, byte [rel dx_modrm]
    cmp     byte [rel dx_mode], 64
    je      .g7_any
    lea     rsi, [rel g7_64only]
.g7_64scan:
    movzx   ecx, byte [rsi]
    cmp     ecx, 0xFF
    je      .g7_any
    cmp     ecx, edx
    jne     .g7_64next
    cmp     al, [rsi + 1]
    jne     .g7_64next
    mov     byte [rel dx_undef], 1
    dec     qword [rel dx_cur]             ; (the ModRM byte: unread)
    mov     byte [rel dx_rep], 0           ; (the prefix was the instruction's)
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .sys_bad
.g7_64next:
    add     rsi, 2
    jmp     .g7_64scan
.g7_any:
    lea     rsi, [rel g7_reg_names]
    movzx   eax, byte [rel dx_modrm]
.g7_scan:
    movzx   ecx, byte [rsi]
    test    ecx, ecx
    jz      .g7_none
    cmp     ecx, eax
    jne     .g7_next
    movzx   ecx, byte [rsi + 1]
    test    ecx, ecx
    jz      .g7_any_pfx                    ; (no prefix of its own: any)
    cmp     ecx, edx
    je      .g7_own
.g7_next:
    add     rsi, 16
    jmp     .g7_scan
.g7_none:
    test    edx, edx
    jz      .sys_bad
    call    .g7_pt_find
    jnc     .sys_bad
    jmp     .g7_taken
.g7_any_pfx:
    test    edx, edx                       ; (a prefix: objdump's prefix table
    jz      .g7_found                      ; there - none, the prefix taken)
    push    rsi
    call    .g7_pt_find
    pop     rsi
    jnc     .g7_found
.g7_taken:
    mov     byte [rel dx_undef], 1
    dec     qword [rel dx_cur]             ; (the ModRM byte: unread)
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .sys_bad
.g7_pt_find:                               ; CF = 1: ModRM al in g7_pfxtab
    lea     rsi, [rel g7_pfxtab]
.g7_pt_scan:
    cmp     byte [rsi], 0
    je      .g7_pt_no
    cmp     [rsi], al
    je      .g7_pt_yes
    inc     rsi
    jmp     .g7_pt_scan
.g7_pt_yes:
    stc
    ret
.g7_pt_no:
    clc
    ret
.g7_own:
    ; the prefix is the instruction's, not printed
    cmp     ecx, 3                         ; (rmpread / rmpupdate: operands)
    jne     .g7_own_go
    cmp     eax, 0xFD
    jb      .g7_own_go
    cmp     eax, 0xFE
    jbe     .g7_rmp
.g7_own_go:
    cmp     ecx, 1
    jne     .g7_own_rep
    mov     byte [rel dx_p66], 0
    dec     byte [rel dx_n66]
.g7_own_rep:
    cmp     ecx, 2
    jne     .g7_own_repne
    mov     byte [rel dx_rep], 0
.g7_own_repne:
    cmp     ecx, 3
    jne     .g7_found
    mov     byte [rel dx_repne], 0
.g7_found:
    add     rsi, 2
    mov     [rel dx_mnem], rsi
    jmp     .f_none
.g7_rmp:                                   ; rmpread [rcx], rax / rmpupdate rax, [rcx]
    mov     byte [rel dx_repne], 0
    add     rsi, 2
    mov     [rel dx_mnem], rsi
    push    rax
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rax
    pop     rax
    cmp     eax, 0xFD
    jne     .rmp_upd
    call    .rmp_mem
    call    dx_sep
    call    .rmp_reg
    jmp     .done
.rmp_upd:
    call    .rmp_reg
    call    dx_sep
    call    .rmp_mem
    jmp     .done
.rmp_reg:                                  ; rax (66: ax)
    mov     edi, 64
    cmp     byte [rel dx_p66], 0
    je      .rmp_reg_put
    mov     edi, 16
.rmp_reg_put:
    xor     esi, esi
    jmp     dx_reg
.rmp_mem:                                  ; [rcx] (67: [ecx])
    mov     esi, '['
    call    dx_putc
    movzx   edi, byte [rel dx_asz]
    mov     esi, 1
    call    dx_reg
    mov     esi, ']'
    jmp     dx_putc
.g7_msw:
    shl     eax, 4
    lea     rsi, [rel g7_mem_names]
    add     rsi, rax
    mov     [rel dx_mnem], rsi
    cmp     byte [rel dx_regno], 6         ; lmsw takes a 16-bit register
    jne     .f_E
    and     byte [rel dx_regno], 7
    mov     ebx, 16
    jmp     .f_E

.f_gae:                                    ; 0F AE
    lea     rsi, [rel pg_0fae]
    call    dx_pgrp
    test    eax, eax
    jnz     .done
    cmp     byte [rel dx_pgnone], 0        ; (none: no fallback)
    jne     .f_undef_op
    cmp     byte [rel dx_mod], 3
    je      .gae_reg
    lea     rsi, [rel gae_mem_names]
    lea     rdi, [rel gae_mem_sizes]
    jmp     .sys_mem
.gae_reg:                                  ; lfence / mfence / sfence
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 5
    jb      .sys_bad
    lea     rsi, [rel gae_reg_names]
    lea     rsi, [rsi + rax*8 - 40]
    mov     [rel dx_mnem], rsi
    jmp     .f_none

.sys_mem:                                  ; rsi = 16-byte name slots, rdi = sizes
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    movzx   ecx, byte [rdi + rax]
    cmp     ecx, 0xFF
    je      .sys_bad
    shl     eax, 4
    add     rsi, rax
    mov     [rel dx_mnem], rsi
    movzx   eax, byte [rel dx_sysfx]
    test    eax, eax
    jz      .sys_named
    mov     byte [rel dx_sysfx], 0
    lea     rdi, [rel dx_namebuf]
.sys_copy:
    mov     dl, [rsi]
    test    dl, dl
    jz      .sys_end
    mov     [rdi], dl
    inc     rsi
    inc     rdi
    jmp     .sys_copy
.sys_end:
    mov     [rdi], al
    mov     byte [rdi + 1], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.sys_named:
    push    rcx
    push    rcx
    mov     esi, 1
    call    dx_mnemonic
    pop     rdi
    pop     rdi
    call    dx_mem                         ; edi = size (0 = none)
    jmp     .done
.sys_bad:
    mov     byte [rel dx_fail], 1
    jmp     .done

.f_none:
    xor     esi, esi
    call    dx_mnemonic
    jmp     .done

.f_EG:                                     ; r/m, reg
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    call    dx_sep
    mov     edi, ebx
    call    dx_greg
    jmp     .done

.f_GE:                                     ; reg, r/m
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    mov     edi, ebx
    call    dx_rm
    jmp     .done

.f_accI:                                   ; al, imm8 / ax|eax|rax, imm16|32
    cmp     byte [rel dx_form], FM_ALIb
    jne     .acc_z
    call    dx_rd8
    jmp     .acc_have
.acc_z:
    call    .read_imm_z
.acc_have:
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    xor     esi, esi
    call    dx_reg
    call    dx_sep
    pop     rsi
    call    dx_imm
    jmp     .done

.f_Zv:                                     ; register in the opcode
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_opreg
    jmp     .done

.f_ZI:                                     ; r8 in opcode, imm8
    call    dx_rd8
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 8
    call    dx_opreg
    call    dx_sep
    pop     rsi
    call    dx_imm
    jmp     .done

.f_ZvIv:                                   ; mov r, imm16/32 - or movabs r64, imm64
    cmp     ebx, 64
    jne     .zv_small
    call    dx_rd64
    push    rax
    lea     rax, [rel s_movabs]
    mov     [rel dx_mnem], rax
    jmp     .zv_print
.zv_small:
    call    .read_imm_z
    push    rax
.zv_print:
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_opreg
    call    dx_sep
    pop     rsi
    call    dx_imm
    jmp     .done

.f_Jb:
    cmp     byte [rel dx_map], 1           ; (E3: jrcxz / jecxz / jcxz by the
    jne     .jb_go                         ; address size)
    cmp     byte [rel dx_op], 0xE3
    jne     .jb_go
    lea     rax, [rel s_jecxz]
    cmp     byte [rel dx_asz], 32
    je      .jb_cx
    lea     rax, [rel s_jcxz]
    cmp     byte [rel dx_asz], 16
    jne     .jb_go
.jb_cx:
    mov     [rel dx_mnem], rax
.jb_go:
    call    dx_rd8
    movsx   rax, al
    jmp     .jump
.f_Jz:
    ; rel16 in 16-bit mode, or with a 66 in 32 / 64 (objdump's callw / jnew)
    ; - not with REX.W, over the 66 (its data16 then)
    cmp     byte [rel dx_mode], 64
    jne     .jz_66
    test    byte [rel dx_rex], 8
    jz      .jz_66
    call    dx_rd32
    movsxd  rax, eax
    jmp     .jump
.jz_66:
    mov     al, [rel dx_p66]
    cmp     byte [rel dx_mode], 16
    jne     .jz_size
    xor     al, 1
.jz_size:
    test    al, al
    jz      .jz_32
    call    dx_rd16
    movsx   rax, ax
    jmp     .jz_have
.jz_32:
    call    dx_rd32
    movsxd  rax, eax
.jz_have:
    push    rax
    call    .sfx66
    pop     rax
.jump:
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_branch
    jmp     .done

.f_E:                                      ; r/m
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    jmp     .done

.f_EI:                                     ; r/m, imm (Ib sign-extended / Iz)
    movzx   eax, byte [rel dx_form]
    cmp     eax, FM_EvIz
    je      .ei_z
    call    dx_rd8
    movsx   rax, al
    jmp     .ei_have
.ei_z:
    call    .read_imm_z
.ei_have:
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    call    dx_sep
    pop     rsi
    call    dx_imm
    jmp     .done

.f_E1:                                     ; r/m, 1
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    lea     rsi, [rel s_comma1]
    call    dx_puts
    jmp     .done

.f_ECL:                                    ; r/m, cl
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    lea     rsi, [rel s_commacl]
    call    dx_puts
    jmp     .done

.f_EIU:                                    ; r/m, imm8 (unsigned)
    call    dx_rd8
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    call    dx_sep
    pop     rsi
    call    dx_hex
    jmp     .done

.f_GM:                                     ; lea: reg, [mem] (no size)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    xor     edi, edi
    call    .mem_only
    jmp     .done
.mem_only:                                 ; memory at edi, or "(bad)" with a register
    cmp     byte [rel dx_mod], 3
    je      dx_badop
    jmp     dx_mem
.f_GvMv:                                   ; r, m at the operand size (movbe)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    mov     edi, ebx
    call    .mem_only
    jmp     .done
.f_MvGv:                                   ; m, r at the operand size (movnti)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    .mem_only
    call    dx_sep
    mov     edi, ebx
    call    dx_greg
    jmp     .done
.f_XABEG:                                  ; C6 F8 ib xabort / C7 F8 rel xbegin -
    cmp     byte [rel dx_modrm], 0xF8      ; another ModRM, no instruction:
    jne     .f_undef_op                    ; "(bad)" for the opcode alone
    cmp     byte [rel dx_op], 0xC7
    je      .f_Jz                          ; (xbegin: a near branch's rel)
    jmp     .f_IbU
.f_SFX66:                                  ; leave(w / d)
    call    .sfx66
    jmp     .f_none
.sfx66:                                    ; a 66 the operand size: the name's
    cmp     byte [rel dx_p66], 0           ; w (16-bit mode: d) - leavew,
    je      .sfx66_ret                     ; pushw, callw, jnew
    test    byte [rel dx_rex], 8           ; (REX.W overrides it: none)
    jnz     .sfx66_ret
    mov     byte [rel dx_p66], 0
    dec     byte [rel dx_n66]
    mov     ecx, 'w'
    cmp     byte [rel dx_mode], 16
    jne     .sfx66_named
    mov     ecx, 'd'
.sfx66_named:
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.sfx66_copy:
    mov     al, [rsi]
    test    al, al
    jz      .sfx66_end
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .sfx66_copy
.sfx66_end:
    mov     [rdi], cl
    mov     byte [rdi + 1], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.sfx66_ret:
    ret
.f_undef_op:                               ; no instruction: "(bad)" through the opcode
    mov     byte [rel dx_undef], 1
    mov     rax, [rel dx_opend]
    mov     [rel dx_cur], rax
    jmp     .sys_bad
.f_PADLOCK:                                ; 0F A6 / A7: ModRM 11 reg 000, else
    movzx   eax, byte [rel dx_regno]       ; objdump's "xsha1 (bad)"
    and     eax, 7
    cmp     byte [rel dx_op], 0xA6
    jne     .padlock_a7
    cmp     eax, 5
    je      .padlock_sm
    test    eax, eax
    jnz     .padlock_go
    ; 0F A6 /0: F3 montmul (its repz written when it is one), F2 sm2 (any
    ; register)
    cmp     byte [rel dx_repne], 0
    je      .padlock_f3
    mov     byte [rel dx_repne], 0
    lea     rax, [rel s_sm2]
    mov     [rel dx_mnem], rax
    cmp     byte [rel dx_mod], 3
    je      .f_none
    jmp     .padlock_bad
.padlock_a7:
    cmp     eax, 6
    jne     .padlock_go
.padlock_sm:
    ; A6 /5 sm3, A7 /6 sm4: F3's alone (any register; memory "sm3 (bad)"),
    ; a 66 / F2 taken - objdump's prefix table
    cmp     byte [rel dx_rep], 0
    je      .padlock_sm_none
    mov     byte [rel dx_rep], 0
    cmp     byte [rel dx_mod], 3
    je      .f_none
    jmp     .padlock_bad
.padlock_sm_none:
    mov     al, [rel dx_p66]
    or      al, [rel dx_repne]
    jz      .f_undef_op
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .f_undef_op
.padlock_f3:
    cmp     byte [rel dx_rep], 0
    jne     .padlock_rep
    mov     byte [rel dx_sel66], 1
    jmp     .f_undef_op
.padlock_rep:
    cmp     byte [rel dx_mod], 3
    jne     .padlock_mm
    test    byte [rel dx_modrm], 7
    jz      .padlock_go
.padlock_mm:
    mov     byte [rel dx_rep], 0
.padlock_go:
    cmp     byte [rel dx_mod], 3
    jne     .padlock_bad
    test    byte [rel dx_modrm], 7
    jnz     .padlock_bad
    jmp     .f_none
.padlock_bad:
    mov     esi, 1
    call    dx_mnemonic
    call    dx_badop
    jmp     .done
.f_KLW:                                    ; F3 0F 38 D8 /0-3: m (no size)
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 4
    jae     .f_undef_op
    shl     eax, 4
    lea     rsi, [rel kl_wide_names]
    add     rsi, rax
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    xor     edi, edi
    call    .mem_only
    jmp     .done
.f_KLV:                                    ; xmm, m - DC with a register loadiwkey
    cmp     byte [rel dx_mod], 3
    jne     .klv_go
    cmp     byte [rel dx_op], 0xDC
    jne     .klv_go
    lea     rax, [rel s_loadiwkey]
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    call    .kl_reg
    call    dx_sep
    mov     edi, 1
    movzx   esi, byte [rel dx_rmreg]
    call    dx_vecreg_c
    jmp     .done
.klv_go:
    mov     esi, 1
    call    dx_mnemonic
    call    .kl_reg
    call    dx_sep
    xor     edi, edi
    call    .mem_only
    jmp     .done
.kl_reg:
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    jmp     dx_vecreg_c
.f_KLE:                                    ; encodekey r32, r32 (registers only)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 32
    call    dx_greg
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    je      .kle_reg
    call    dx_badop
    jmp     .done
.kle_reg:
    mov     edi, 32
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .done
.f_Mb:                                     ; m8 (prefetch)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 8
    call    .mem_only
    jmp     .done

.f_GEI:                                    ; imul reg, r/m, imm
    movzx   eax, byte [rel dx_form]
    cmp     eax, FM_GvEvIz
    je      .gei_z
    call    dx_rd8
    movsx   rax, al
    jmp     .gei_have
.gei_z:
    call    .read_imm_z
.gei_have:
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    mov     edi, ebx
    call    dx_rm
    call    dx_sep
    pop     rsi
    call    dx_imm
    jmp     .done

.f_GEx:                                    ; movzx/movsx/movsxd: reg, narrower r/m
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_greg
    call    dx_sep
    movzx   eax, byte [rel dx_form]
    mov     edi, 8
    cmp     eax, FM_GvEb
    je      .gex_src
    mov     edi, 16
    cmp     eax, FM_GvEw
    je      .gex_src
    mov     edi, 32
.gex_src:
    call    dx_rm
    jmp     .done

.f_IbU:                                    ; int imm8
    cmp     byte [rel dx_map], 4           ; (hreset: F3 0F 3A F0 C0 ib - another
    jne     .ibu_go                        ; ModRM no instruction)
    cmp     byte [rel dx_op], 0xF0
    jne     .ibu_go
    cmp     byte [rel dx_mod], 3
    je      .hreset_reg
    test    byte [rel dx_modrm], 0x3F      ; (memory with reg 0 rm 0: "hreset
    jnz     .f_undef_op                    ; (bad),ib"; else no instruction)
    mov     esi, 1
    call    dx_mnemonic
    call    dx_badop
    call    dx_sep
    call    dx_rd8
    mov     esi, eax
    call    dx_hex
    jmp     .done
.hreset_reg:
    cmp     byte [rel dx_modrm], 0xC0
    jne     .f_undef_op
.ibu_go:
    call    dx_rd8
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_hex
    jmp     .done

.f_IbS:                                    ; push imm8 (sign-extended)
    call    dx_rd8
    movsx   rax, al
    push    rax
    call    .sfx66
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_imm
    jmp     .done

.f_Iz:                                     ; push imm32 (sign-extended)
    call    .read_imm_z
    push    rax
    call    .sfx66
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_imm
    jmp     .done

.f_Iw:                                     ; ret imm16
    call    dx_rd16
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    call    dx_hex
    jmp     .done

.f_xchg:                                   ; xchg r, rax (91-97)
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_opreg
    call    dx_sep
    mov     edi, ebx
    xor     esi, esi
    call    dx_reg
    jmp     .done

.f_EGI:                                    ; shld/shrd r/m, reg, imm8
    call    .shx_head
    call    dx_rd8
    mov     rsi, rax
    push    rsi
    call    dx_sep
    pop     rsi
    call    dx_hex
    jmp     .done
.f_EGCL:                                   ; shld/shrd r/m, reg, cl
    call    .shx_head
    lea     rsi, [rel s_commacl]
    call    dx_puts
    jmp     .done
.shx_head:
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, ebx
    call    dx_rm
    call    dx_sep
    mov     edi, ebx
    jmp     dx_greg

.f_90:                                     ; nop / pause / xchg r8,rax / xchg ax,ax
    cmp     byte [rel dx_rep], 0
    je      .n90_rex
    mov     byte [rel dx_rep], 0           ; (F3 is pause's own)
    lea     rax, [rel s_pause]
    mov     [rel dx_mnem], rax
    jmp     .f_none
.n90_rex:
    test    byte [rel dx_rex], 1
    jnz     .n90_xchg
    test    byte [rel dx_rex4], 0x10       ; REX2.B4: xchg r16-r31, rax
    jnz     .n90_xchg
    cmp     byte [rel dx_p66], 0           ; (66: xchg ax, ax - or eax, eax in
    jne     .n90_xchg                      ; 16-bit mode)
    test    byte [rel dx_rex], 8
    jz      .f_none                        ; plain nop
    cmp     byte [rel dx_rex2], 0          ; (a REX's unused W: x86_decode's
    je      .f_none                        ; trials; REX2's here)
    lea     rax, [rel s_rexw_nop]          ; objdump says "rex.W nop"
    mov     [rel dx_mnem], rax
    jmp     .f_none
.n90_xchg:
    lea     rax, [rel s_xchg]
    mov     [rel dx_mnem], rax
    jmp     .f_xchg

.f_cbw:
    lea     rax, [rel s_cbw]
    cmp     ebx, 16
    je      .cbw_set
    lea     rax, [rel s_cwde]
    cmp     ebx, 32
    je      .cbw_set
    lea     rax, [rel s_cdqe]
.cbw_set:
    mov     [rel dx_mnem], rax
    jmp     .f_none
.f_cwd:
    lea     rax, [rel s_cwd]
    cmp     ebx, 16
    je      .cbw_set
    lea     rax, [rel s_cdq]
    cmp     ebx, 32
    je      .cbw_set
    lea     rax, [rel s_cqo]
    jmp     .cbw_set

.f_str:
    call    dx_string
    jmp     .done

; .read_imm_z: rax = imm16 or imm32 (sign-extended), by operand size
.read_imm_z:
    cmp     ebx, 16
    jne     .rz32
    call    dx_rd16
    movsx   rax, ax
    ret
.rz32:
    call    dx_rd32
    movsxd  rax, eax
    ret

.done:
    pop     rbx
    ret
