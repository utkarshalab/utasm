; ============================================================================
; File        : src/tools/disasm/x86/sse.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : SSE / vector operands, memory sizes
; ============================================================================


; ============================================================================
; SSE-family operands
; ============================================================================
; Operand kinds:  V = vector register from ModRM.reg
;                 W = vector register or memory from ModRM.rm
;                 U = vector register from ModRM.rm (register only)
;                 M = memory from ModRM.rm (memory only)
;                 E = general register or memory, G = general register
; Vector registers are mm0-7 (MMX forms) or xmm0-15. General registers are
; 64-bit with REX.W, else 32-bit.

dx_sse_operands:
    push    rbx
    ; REX.W / VEX.W turns a trailing 'd' into 'q' (movd -> movq, ...)
    test    byte [rel dx_sflags], SF_WQ
    jz      .no_wq
    test    byte [rel dx_rex], 8
    jz      .no_wq
    mov     esi, 'q'
    call    dx_name_last
.no_wq:
    ; VEX-only tables: VEX.W turns a trailing 's' into 'd' (ps -> pd)
    cmp     byte [rel dx_vex], 0
    je      .named
    cmp     byte [rel dx_vpfx], 0
    jne     .named
    test    byte [rel dx_sflags], VF_WSD
    jz      .named
    test    byte [rel dx_rex], 8
    jz      .named
    mov     esi, 'd'
    call    dx_name_last
.named:
    movzx   eax, byte [rel dx_form]
    cmp     eax, FM_VW
    je      .VW
    cmp     eax, FM_WV
    je      .WV
    cmp     eax, FM_VWI
    je      .VWI
    cmp     eax, FM_VE
    je      .VE
    cmp     eax, FM_EV
    je      .EV
    cmp     eax, FM_GW
    je      .GW
    cmp     eax, FM_GU
    je      .GU
    cmp     eax, FM_VQ
    je      .VQ
    cmp     eax, FM_PW
    je      .PW
    cmp     eax, FM_UI
    je      .UI
    cmp     eax, FM_VM
    je      .VM
    cmp     eax, FM_MV
    je      .MV
    cmp     eax, FM_V12
    je      .V12
    cmp     eax, FM_EVI
    je      .EVI
    cmp     eax, FM_VEI
    je      .VEI
    cmp     eax, FM_GUI
    je      .GUI
    cmp     eax, FM_VW0
    je      .VW0
    cmp     eax, FM_CMPS
    je      .CMPS
    cmp     eax, FM_PCLMUL
    je      .PCLMUL
    cmp     eax, FM_ENDBR
    je      .ENDBR
    cmp     eax, FM_XBCAST
    je      .XBCAST
    cmp     eax, FM_XINS
    je      .XINS
    cmp     eax, FM_XEXT
    je      .XEXT
    cmp     eax, FM_XIS4
    je      .XIS4
    cmp     eax, FM_BGBE
    je      .BGBE
    cmp     eax, FM_BGEB
    je      .BGEB
    cmp     eax, FM_BBE
    je      .BBE
    cmp     eax, FM_XMLD
    je      .XMLD
    cmp     eax, FM_XMST
    je      .XMST
    cmp     eax, FM_BRORX
    je      .BRORX
    cmp     eax, FM_XZERO
    je      .XZERO
    jmp     .fail

.VW:
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    cmp     byte [rel dx_map], 2           ; (maskmovq / maskmovdqu: registers
    jne     .vw_w                          ; only)
    cmp     byte [rel dx_op], 0xF7
    jne     .vw_w
    call    .reg_only
    jmp     .done
.vw_w:
    call    dx_opW
    jmp     .done
.WV:
    call    .mn
    call    dx_opW
    call    .movs_nds                      ; vmovss/vmovsd register store
    call    dx_sep
    call    dx_opV
    jmp     .done
.VWI:
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    dx_opW
    jmp     .imm8
.VE:
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    dx_opE
    jmp     .done
.EV:
    call    .mn
    call    dx_opE
    call    dx_sep
    call    dx_opV
    jmp     .done
.GW:
    call    .mn
    call    dx_opG
    call    dx_sep
    call    dx_opW
    jmp     .done
.GU:
    call    .gu_66mem
    call    .mn
    call    .gu_size
    call    dx_greg
    call    dx_sep
    call    .reg_only
    jmp     .done
.gu_66mem:                                 ; 66 pextrw / pmovmskb with memory:
    cmp     byte [rel dx_mod], 3           ; no instruction (objdump's "(bad)"
    je      .gu66_ret                      ; through the opcode)
    cmp     byte [rel dx_vex], 0
    jne     .gu66_ret
    cmp     byte [rel dx_ssepfx], 1
    jne     .gu66_ret
    cmp     byte [rel dx_op], 0xC5
    je      .gu66_bad
    cmp     byte [rel dx_op], 0xD7
    jne     .gu66_ret
.gu66_bad:
    pop     rax                            ; (not back to .GU)
    mov     byte [rel dx_undef], 1
    mov     byte [rel dx_sel66], 1
    mov     rax, [rel dx_opend]
    mov     [rel dx_cur], rax
    jmp     .fail
.gu66_ret:
    ret
.reg_only:                                 ; W a register, or "(bad)" with memory
    cmp     byte [rel dx_mod], 3
    jne     dx_badop
    jmp     dx_opW
.mem_only:                                 ; W memory, or "(bad)" with a register
    cmp     byte [rel dx_mod], 3
    je      dx_badop
    jmp     dx_opW
.UI:                                       ; group: the name comes from ModRM.reg
    lea     rax, [rel x86_groups]
    movzx   ecx, word [r12]                ; group number (r12 = SSE entry)
    shl     ecx, 3
    movzx   edx, byte [rel dx_regno]
    and     edx, 7
    add     ecx, edx
    movzx   ecx, word [rax + rcx*4]
    cmp     ecx, 0xFFFF
    je      .fail
    lea     rax, [rel x86_names]
    add     rax, rcx
    mov     [rel dx_mnem], rax
    cmp     byte [rel dx_mod], 3
    je      .ui_reg
    cmp     byte [rel dx_vex], 0           ; (memory: a VEX one none; else
    jne     .fail                          ; objdump's "psrlw (bad),0x71")
    cmp     byte [rel dx_ssepfx], 1        ; (66: none, the 66 taken - but
    jne     .ui_mem                        ; psrldq / pslldq's "(bad)")
    cmp     byte [rel dx_op], 0x73
    jne     .ui_mem_none
    test    byte [rel dx_regno], 1
    jnz     .ui_mem
.ui_mem_none:
    mov     byte [rel dx_undef], 1
    mov     byte [rel dx_sel66], 1
    mov     rax, [rel dx_opend]
    mov     [rel dx_cur], rax
    jmp     .fail
.ui_mem:
    call    .mn
    call    dx_badop
    jmp     .imm8
.ui_reg:
    call    .mn
    cmp     byte [rel dx_vex], 0
    je      .ui_src
    movzx   esi, byte [rel dx_vvvv]        ; VEX: vvvv is the destination
    call    dx_vecreg
    call    dx_sep
.ui_src:
    call    dx_opW
    jmp     .imm8
.VM:
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    .mem_only
    jmp     .done
.MV:
    call    .mn
    call    .mem_only
    call    dx_sep
    call    dx_opV
    jmp     .done
.V12:                                      ; movlps/movhps, or movhlps/movlhps
    cmp     byte [rel dx_mod], 3
    jne     .VW
    lea     rax, [rel s_movhlps]
    cmp     byte [rel dx_op], 0x12
    je      .v12_name
    lea     rax, [rel s_movlhps]
.v12_name:
    mov     [rel dx_mnem], rax
    jmp     .VW
.EVI:
    call    .mn
    cmp     byte [rel dx_map], 4           ; 0F 3A 17: (v)extractps r/m32 -
    jne     .evi_e                         ; REX.W / VEX.W change nothing
    cmp     byte [rel dx_op], 0x17
    jne     .evi_e
    call    dx_opE.e32
    jmp     .evi_v
.evi_e:
    call    dx_opE
.evi_v:
    call    dx_sep
    call    dx_opV
    jmp     .imm8
.VEI:
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    dx_opE
    jmp     .imm8
.GUI:
    call    .gu_66mem
    call    .mn
    call    .gu_size
    call    dx_greg
    call    dx_sep
    call    .reg_only
    jmp     .imm8
.VQ:                                       ; xmm, mm/m64 (movq2dq: registers only)
    call    .mn
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    call    dx_vecreg_c
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    jne     .mix_mem
    xor     edi, edi
    movzx   esi, byte [rel dx_rmreg]
    and     esi, 7
    call    dx_vecreg_c
    jmp     .done
.PW:                                       ; mm, xmm/m (movdq2q: registers only)
    call    .mn
    xor     edi, edi
    movzx   esi, byte [rel dx_regno]
    and     esi, 7
    call    dx_vecreg_c
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    jne     .mix_mem
    mov     edi, 1
    movzx   esi, byte [rel dx_rmreg]
    call    dx_vecreg_c
    jmp     .done
.mix_mem:
    cmp     byte [rel dx_op], 0xD6         ; (movq2dq / movdq2q: no memory)
    jne     .mix_mem_put
    call    dx_badop
    jmp     .done
.mix_mem_put:
    call    dx_memsize
    call    dx_mem
    jmp     .done
.gu_size:                                  ; movmskps / pmovmskb / pextrw's r32,
    mov     edi, 32                        ; r64 with REX.W (not VEX's W)
    cmp     byte [rel dx_vex], 0
    jne     .gu_ret
    test    byte [rel dx_rex], 8
    jz      .gu_ret
    mov     edi, 64
.gu_ret:
    ret
.VW0:
    call    .mn
    call    dx_opV
    call    dx_sep
    call    dx_opW
    lea     rsi, [rel s_commaxmm0]
    call    dx_puts
    jmp     .done

.CMPS:                                     ; cmpps xmm,xmm,imm - or cmpltps xmm,xmm
    call    .peek_imm
    cmp     eax, 32
    jae     .VWI
    cmp     byte [rel dx_vex], 0
    jne     .cmps_pred                     ; VEX: 32 predicates, SSE: 8
    cmp     eax, 8
    jae     .VWI
.cmps_pred:
    ; "cmp" + predicate + the entry's suffix (ps/pd/ss/sd)
    lea     rdi, [rel dx_namebuf]
    mov     byte [rdi], 'c'
    mov     byte [rdi + 1], 'm'
    mov     byte [rdi + 2], 'p'
    add     rdi, 3
    lea     rsi, [rel cmp_preds]
    shl     eax, 4
    add     rsi, rax
.cmps_copy:
    mov     cl, [rsi]
    test    cl, cl
    jz      .cmps_suffix
    mov     [rdi], cl
    inc     rdi
    inc     rsi
    jmp     .cmps_copy
.cmps_suffix:
    mov     rsi, [rel dx_mnem]             ; "cmpps": suffix at +3
    mov     cl, [rsi + 3]
    mov     [rdi], cl
    mov     cl, [rsi + 4]
    mov     [rdi + 1], cl
    mov     byte [rdi + 2], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    dx_opW
    call    dx_rd8                         ; consume the predicate
    jmp     .done

.PCLMUL:                                   ; pclmulqdq: known selectors get names
    call    .peek_imm
    cmp     eax, 2                         ; (objdump: 02 / 03 as 10 / 11)
    jne     .pcl1_3
    mov     eax, 0x10
.pcl1_3:
    cmp     eax, 3
    jne     .pcl1_n
    mov     eax, 0x11
.pcl1_n:
    lea     rsi, [rel s_pclmul_ll]
    cmp     eax, 0x00
    je      .pcl_named
    lea     rsi, [rel s_pclmul_hl]
    cmp     eax, 0x01
    je      .pcl_named
    lea     rsi, [rel s_pclmul_lh]
    cmp     eax, 0x10
    je      .pcl_named
    lea     rsi, [rel s_pclmul_hh]
    cmp     eax, 0x11
    jne     .VWI
.pcl_named:
    mov     [rel dx_mnem], rsi
    call    .mn
    call    dx_opV
    call    .nds
    call    dx_sep
    call    dx_opW
    call    dx_rd8
    jmp     .done

; ---- VEX-only forms ----
.XZERO:
    cmp     byte [rel dx_vvvv], 0          ; (vvvv 0 alone)
    jne     .fail
    cmp     byte [rel dx_vl], 0
    je      .zero_named
    lea     rax, [rel s_vzeroall]
    mov     [rel dx_mnem], rax
.zero_named:
    xor     esi, esi
    call    dx_mnemonic
    jmp     .done
.XBCAST:                                   ; V, xmm register or memory
    call    .mn
    call    dx_opV
    call    dx_sep
    cmp     byte [rel dx_mod], 3
    jne     .bcast_mem
    movzx   esi, byte [rel dx_rmreg]
    mov     edi, 1
    call    dx_vecreg_c
    jmp     .done
.bcast_mem:
    call    dx_memsize
    cmp     edi, 256
    jne     .mem_done
    mov     edi, 128
    jmp     .mem_done
.XINS:                                     ; ymm, ymm, xmm/m128, imm8
    call    .mn
    call    dx_opV
    call    .vvvv
    call    dx_sep
    call    .xmm_or_m128
    jmp     .imm8
.XEXT:                                     ; xmm/m128, ymm, imm8
    call    .mn
    call    .xmm_or_m128
    call    dx_sep
    call    dx_opV
    jmp     .imm8
.XIS4:                                     ; V, vvvv, W, register from imm8[7:4]
    call    .mn
    call    dx_opV
    call    .vvvv
    call    dx_sep
    call    dx_opW
    call    dx_sep
    call    dx_rd8
    shr     eax, 4
    mov     esi, eax
    call    dx_vecreg
    jmp     .done
.XMLD:                                     ; V, vvvv, memory
    cmp     byte [rel dx_mod], 3
    je      .fail
    call    .mn
    call    dx_opV
    call    .vvvv
    call    dx_sep
    call    dx_opW
    jmp     .done
.XMST:                                     ; memory, vvvv, V
    cmp     byte [rel dx_mod], 3
    je      .fail
    call    .mn
    call    dx_opW
    call    .vvvv
    call    dx_sep
    call    dx_opV
    jmp     .done
.BGBE:                                     ; gpr, vvvv, r/m
    call    .mn
    call    dx_opG
    call    dx_sep
    call    .vvvv_gpr
    call    dx_sep
    call    dx_opE
    jmp     .done
.BGEB:                                     ; gpr, r/m, vvvv
    call    .mn
    call    dx_opG
    call    dx_sep
    call    dx_opE
    call    dx_sep
    call    .vvvv_gpr
    jmp     .done
.BBE:                                      ; group: vvvv, r/m
    lea     rax, [rel x86_groups]
    movzx   ecx, word [r12]
    shl     ecx, 3
    movzx   edx, byte [rel dx_regno]
    and     edx, 7
    add     ecx, edx
    movzx   ecx, word [rax + rcx*4]
    cmp     ecx, 0xFFFF
    je      .fail
    lea     rax, [rel x86_names]
    add     rax, rcx
    mov     [rel dx_mnem], rax
    call    .mn
    call    .vvvv_gpr
    call    dx_sep
    call    dx_opE
    jmp     .done
.BRORX:                                    ; gpr, r/m, imm8
    call    .mn
    call    dx_opG
    call    dx_sep
    call    dx_opE
    jmp     .imm8

; ",vvvv" when this VEX instruction has an extra source register
.nds:
    cmp     byte [rel dx_vex], 0
    je      .nds_ret
    test    byte [rel dx_sflags], SF_NDS
    jz      .nds_ret
    ; vmovss/vmovsd (0F 10): only the register form has one
    cmp     byte [rel dx_map], 2
    jne     .vvvv
    cmp     byte [rel dx_op], 0x10
    jne     .vvvv
    cmp     byte [rel dx_mod], 3
    jne     .nds_ret
.vvvv:
    call    dx_sep
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_vecreg
.nds_ret:
    ret
; vmovss/vmovsd store (0F 11) register form: W, vvvv, V
.movs_nds:
    cmp     byte [rel dx_vex], 0
    je      .nds_ret
    cmp     byte [rel dx_map], 2
    jne     .nds_ret
    cmp     byte [rel dx_op], 0x11
    jne     .nds_ret
    cmp     byte [rel dx_mod], 3
    jne     .nds_ret
    movzx   eax, byte [rel dx_sflags]
    and     eax, SF_MEM
    cmp     eax, 5
    je      .nds_ret                       ; vmovups & co: no extra source
    jmp     .vvvv
; vvvv as a general register (BMI), 32/64 by VEX.W
.vvvv_gpr:
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .vg
    mov     edi, 64
.vg:
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_reg
; an xmm register or 128-bit memory operand (vinsert/vextract)
.xmm_or_m128:
    cmp     byte [rel dx_mod], 3
    jne     .m128
    movzx   esi, byte [rel dx_rmreg]
    mov     edi, 1
    jmp     dx_vecreg_c
.m128:
    mov     edi, 128
    jmp     dx_mem
.mem_done:
    call    dx_mem
    jmp     .done

.ENDBR:                                    ; F3 0F 1E FA / FB
    ; F3 0F 1E /1 with a register: rdsspd / rdsspq (CET)
    cmp     byte [rel dx_mod], 3
    jne     .endbr
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 1
    jne     .endbr
    lea     rax, [rel s_rdsspd]
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .rdssp
    lea     rax, [rel s_rdsspq]
    mov     edi, 64
.rdssp:
    mov     [rel dx_mnem], rax
    push    rdi
    push    rdi
    mov     esi, 1
    call    dx_mnemonic
    pop     rdi
    pop     rdi
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .done
.endbr:
    lea     rax, [rel s_endbr64]
    cmp     byte [rel dx_modrm], 0xFA
    je      .endbr_name
    lea     rax, [rel s_endbr32]
    cmp     byte [rel dx_modrm], 0xFB
    je      .endbr_name
    mov     byte [rel dx_rep], 1           ; (a hint nop, its F3 a repz)
    lea     rax, [rel s_hint_nop]
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    movzx   edi, byte [rel dx_osz]
    call    dx_rm
    jmp     .done
.endbr_name:
    mov     [rel dx_mnem], rax
    xor     esi, esi
    call    dx_mnemonic
    jmp     .done

.imm8:
    call    dx_rd8
    mov     rsi, rax
    push    rsi
    call    dx_sep
    pop     rsi
    call    dx_hex
    jmp     .done

.fail:
    mov     byte [rel dx_fail], 1
.done:
    pop     rbx
    ret

.mn:
    mov     esi, 1
    jmp     dx_mnemonic

; the immediate after the ModRM operand, without consuming it
.peek_imm:
    mov     rcx, [rel dx_cur]
    cmp     rcx, [rel dx_end]
    jae     .peek_fail
    movzx   eax, byte [rcx]
    ret
.peek_fail:
    mov     byte [rel dx_fail], 1
    mov     eax, 0xFF
    ret

; ---- dx_name_last ------------------------
; Copies the mnemonic to dx_namebuf with its last character replaced by
; the character in esi ('q' for movd -> movq, 'd' for ...ps -> ...pd).
dx_name_last:
    mov     edx, esi
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.copy:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .copied
    inc     rsi
    inc     rdi
    jmp     .copy
.copied:
    mov     [rdi - 1], dl
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
    ret

; ---- vector operand printers ------------

; dx_vecreg: vector register esi ("mm3" / "xmm12")
dx_vecreg:
    movzx   edi, byte [rel dx_vclass]
; dx_vecreg_c: vector register esi of class edi (0 mm, 1 xmm, 2 ymm, 3 zmm)
dx_vecreg_c:
    push    rsi
    push    rdi
    lea     rsi, [rel s_mm]
    test    edi, edi
    jz      .prefix
    lea     rsi, [rel s_xmm]
    cmp     edi, 1
    je      .prefix
    lea     rsi, [rel s_ymm]
    cmp     edi, 2
    je      .prefix
    lea     rsi, [rel s_zmm]
.prefix:
    call    dx_puts
    pop     rdi
    pop     rsi
    test    edi, edi
    jnz     .num
    and     esi, 7
.num:
    mov     rdi, [rel dx_fb]
    jmp     fmt_udec

; dx_memsize: edi = memory operand size in bits for this entry (0 = none)
dx_memsize:
    movzx   eax, byte [rel dx_sflags]
    and     eax, SF_MEM
    ; W makes a DWORD operand QWORD where it also renames the instruction
    ; (pinsrd -> pinsrq, vfmadd213ss -> vfmadd213sd)
    cmp     eax, 3
    jne     .sized
    test    byte [rel dx_rex], 8
    jz      .sized
    test    byte [rel dx_sflags], SF_WQ
    jnz     .wide
    cmp     byte [rel dx_vex], 0
    je      .sized
    cmp     byte [rel dx_vpfx], 0
    jne     .sized
    test    byte [rel dx_sflags], VF_WSD
    jz      .sized
.wide:
    mov     eax, 4
.sized:
    xor     edi, edi
    cmp     eax, 1
    jne     .w
    mov     edi, 8
.w: cmp     eax, 2
    jne     .d
    mov     edi, 16
.d: cmp     eax, 3
    jne     .q
    mov     edi, 32
.q: cmp     eax, 4
    jne     .x
    mov     edi, 64
.x: cmp     eax, 5
    jne     .ret
    mov     edi, 64                        ; by register class: mm / xmm / ymm
    cmp     byte [rel dx_vclass], 0
    je      .ret
    mov     edi, 128
    cmp     byte [rel dx_vclass], 1
    je      .ret
    mov     edi, 256
.ret:
    ret

dx_opV:
    movzx   esi, byte [rel dx_regno]
    cmp     byte [rel dx_narrow], 0
    je      dx_vecreg
    mov     edi, 1                         ; narrowing conversion: always xmm
    jmp     dx_vecreg_c

dx_opW:
    cmp     byte [rel dx_half], 0
    jne     .half
    cmp     byte [rel dx_mod], 3
    jne     .mem
    movzx   esi, byte [rel dx_rmreg]
    jmp     dx_vecreg
.mem:
    call    dx_memsize
    jmp     dx_mem
.half:
    cmp     byte [rel dx_mod], 3
    jne     .half_mem
    movzx   esi, byte [rel dx_rmreg]
    mov     edi, 1                         ; always xmm
    jmp     dx_vecreg_c
.half_mem:
    call    dx_memsize
    cmp     byte [rel dx_vl], 0
    je      .half_put
    add     edi, edi                       ; ymm destination: twice the bytes
.half_put:
    jmp     dx_mem

; E: general register (32/64 by REX.W) or memory (entry size, else 32/64)
dx_opE:
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .sized
    cmp     byte [rel dx_mode], 64
    jne     .sized
    mov     edi, 64
    jmp     .sized
.e32:                                      ; dx_opE.e32: 32 bits whatever W says
    mov     edi, 32
.sized:
    cmp     byte [rel dx_mod], 3
    jne     .mem
    movzx   esi, byte [rel dx_rmreg]
    jmp     dx_reg
.mem:
    push    rdi
    call    dx_memsize
    pop     rax
    test    edi, edi
    jnz     .have
    mov     edi, eax
.have:
    jmp     dx_mem

dx_opG:
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .reg
    cmp     byte [rel dx_mode], 64
    jne     .reg
    mov     edi, 64
.reg:
    jmp     dx_greg

; ---- string instructions ----------------
;
; objdump spells them with explicit operands, e.g.
;   rep stos QWORD PTR es:[rdi],rax
;   movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
;   repz cmps BYTE PTR ds:[rsi],BYTE PTR es:[rdi]
;   lods al,BYTE PTR ds:[rsi]        scas al,BYTE PTR es:[rdi]
;   ins BYTE PTR es:[rdi],dx         outs dx,DWORD PTR ds:[rsi]
;
dx_string:
    push    rbx
    movzx   ebx, byte [rel dx_osz]
    movzx   eax, byte [rel dx_op]
    and     eax, 0xFE                      ; A4/A6/AA/AC/AE, 6C/6E family
    cmp     eax, 0x6E
    ja      .sized
    cmp     ebx, 64
    jne     .sized
    mov     ebx, 32                        ; (ins / outs: no 64-bit form)
.sized:

    ; rep prefix spelling
    cmp     byte [rel dx_repne], 0
    je      .no_repne
    lea     rsi, [rel s_repnz]
    jmp     .prefix
.no_repne:
    cmp     byte [rel dx_rep], 0
    je      .mn
    lea     rsi, [rel s_rep]
    cmp     eax, 0xA6                      ; cmps
    je      .repz
    cmp     eax, 0xAE                      ; scas
    jne     .prefix
.repz:
    lea     rsi, [rel s_repz]
.prefix:
    push    rax
    call    dx_puts
    pop     rax
    mov     byte [rel dx_rep], 0           ; (printed: not again by dx_mnemonic)
    mov     byte [rel dx_repne], 0
.mn:
    push    rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rax

    cmp     eax, 0x6C
    je      .ins
    cmp     eax, 0x6E
    je      .outs
    cmp     eax, 0xA4
    je      .movs
    cmp     eax, 0xA6
    je      .cmps
    cmp     eax, 0xAA
    je      .stos
    cmp     eax, 0xAC
    je      .lods
    ; scas: acc, es:[rdi]
    call    .acc
    call    dx_sep
    call    .es_rdi
    jmp     .done
.movs:
    call    .es_rdi
    call    dx_sep
    call    .ds_rsi
    jmp     .done
.cmps:
    call    .ds_rsi
    call    dx_sep
    call    .es_rdi
    jmp     .done
.stos:
    call    .es_rdi
    call    dx_sep
    call    .acc
    jmp     .done
.lods:
    call    .acc
    call    dx_sep
    call    .ds_rsi
    jmp     .done
.ins:
    call    .es_rdi
    call    dx_sep
    call    .dx
    jmp     .done
.outs:
    call    .dx
    call    dx_sep
    call    .ds_rsi
.done:
    pop     rbx
    ret

.acc:
    mov     edi, ebx
    xor     esi, esi
    jmp     dx_reg
.dx:
    mov     edi, 16
    mov     esi, 2                         ; (dx)
    jmp     dx_reg
.es_rdi:                                   ; [rdi] / [edi] / [di]: es, always
    call    .size
    cmp     byte [rel dx_mode], 64
    je      .es_put
    lea     rsi, [rel s_es]                ; (16 / 32-bit mode: written)
    call    dx_puts
.es_put:
    lea     rsi, [rel s_rdi]
    cmp     byte [rel dx_asz], 64
    je      .str_put
    lea     rsi, [rel s_edi]
    cmp     byte [rel dx_asz], 32
    je      .str_put
    lea     rsi, [rel s_di]
.str_put:
    jmp     dx_puts
.ds_rsi:                                   ; [rsi] / [esi] / [si]; fs: / gs:
    call    .size
    call    dx_seg_fsgs
    lea     rsi, [rel s_rsi]
    cmp     byte [rel dx_asz], 64
    je      .str_put
    lea     rsi, [rel s_esi]
    cmp     byte [rel dx_asz], 32
    je      .str_put
    lea     rsi, [rel s_si]
    jmp     .str_put
.size:
    lea     rsi, [rel s_byte]
    cmp     ebx, 8
    je      .size_put
    lea     rsi, [rel s_word]
    cmp     ebx, 16
    je      .size_put
    lea     rsi, [rel s_dword]
    cmp     ebx, 32
    je      .size_put
    lea     rsi, [rel s_qword]
.size_put:
    jmp     dx_puts
