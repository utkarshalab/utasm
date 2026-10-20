; ============================================================================
; File        : tools/disasm/x86_apx.inc (included by x86.s)
; Description : APX's EVEX map 4 - the legacy integer instructions with a
;   new data destination (ND, vvvv), no flags ({nf}: NF), zero upper (ND
;   of imul / setcc), {evex}; ccmp / ctest (the default flags in vvvv,
;   the condition in P2); cfcmov; push2 / pop2; and the 0F 38 ones with
;   r16-r31 (movbe, crc32, adcx, adox, invept .., movdiri, wrss ..). The
;   text is objdump's: "add rax,rbx,rcx", "{nf} add rax,rbx", "{evex} add
;   rax,rbx" (ND 0, NF 0, no r16-r31), "ccmpe {dfv=of, zf} rax,rbx".
; ============================================================================

[SECTION .bss]
d4_vvvv:    resb 1              ; vvvv with V4: the new destination (0-31)
d4_dfv:     resb 1              ; P1's vvvv as written: ccmp's default flags
d4_pp:      resb 1
d4_nd:      resb 1
d4_nf:      resb 1
d4_sc:      resb 1              ; P2's low 4 bits: ccmp / ctest's condition
d4_osz:     resb 1              ; the operation's size
dx_evexp:   resb 1              ; "{evex} " before the mnemonic
[SECTION .text]

; dx_evex4: P0 in al (62 and P0 read). Decodes and prints the
; instruction; dx_fail when it is none.
dx_evex4:
    push    rbx
    ; P0: R3' X3' B3' R4' B4 100
    test    al, 3
    jnz     .fail                          ; (map 5 / 6: not here)
    mov     edx, 0x40
    test    al, 0x80
    jnz     .p0_x
    or      edx, 4
.p0_x:
    test    al, 0x40
    jnz     .p0_b
    or      edx, 2
.p0_b:
    test    al, 0x20
    jnz     .p0_r4
    or      edx, 1
.p0_r4:
    xor     ecx, ecx
    test    al, 0x10
    jnz     .p0_b4
    or      ecx, 0x40                      ; R4
.p0_b4:
    test    al, 0x08
    jz      .p1
    or      ecx, 0x10                      ; B4
.p1:
    push    rcx
    call    dx_rd8                         ; P1: W vvvv' X4' pp (keeps edx)
    pop     rcx
    test    al, 0x80
    jz      .p1_w
    or      edx, 8
.p1_w:
    test    al, 4
    jnz     .p1_x4
    or      ecx, 0x20                      ; X4
.p1_x4:
    mov     [rel dx_rex], dl
    mov     [rel dx_rex4], cl
    mov     ebx, eax
    shr     ebx, 3
    and     ebx, 15
    mov     [rel d4_dfv], bl
    not     ebx
    and     ebx, 15
    mov     [rel d4_vvvv], bl
    and     eax, 3
    mov     [rel d4_pp], al
    call    dx_rd8                         ; P2: 000 ND V4' NF 00 (or the SC)
    mov     ecx, eax
    and     ecx, 15
    mov     [rel d4_sc], cl
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 1
    mov     [rel d4_nd], cl
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 1
    mov     [rel d4_nf], cl
    test    al, 8
    jnz     .p2_v4
    or      byte [rel d4_vvvv], 16
.p2_v4:
    call    dx_rd8                         ; the opcode
    mov     [rel dx_op], al
    cmp     byte [rel dx_fail], 0
    jne     .fail
    ; the operation's size: W 64, 66 16, else 32
    mov     ecx, 32
    cmp     byte [rel d4_pp], 1
    jne     .osz_w
    mov     ecx, 16
.osz_w:
    test    byte [rel dx_rex], 8
    jz      .osz_set
    mov     ecx, 64
.osz_set:
    mov     [rel d4_osz], cl
    mov     [rel dx_osz], cl
    movzx   eax, byte [rel dx_op]
    ; ccmp / ctest: the condition in P2 (ND, V4, NF there are its bits)
    cmp     eax, 0x38
    jb      .not_ccmp
    cmp     eax, 0x3B
    jbe     .ccmp
.not_ccmp:
    cmp     eax, 0x3F
    jbe     .alu
    cmp     eax, 0x4F
    jbe     .cc40
    cmp     eax, 0x60
    je      .movbe
    cmp     eax, 0x61
    je      .movbe
    cmp     eax, 0x65
    je      .wruss
    cmp     eax, 0x66
    je      .adx
    cmp     eax, 0x69
    je      .imul_imm
    cmp     eax, 0x6B
    je      .imul_imm
    cmp     eax, 0x80
    je      .grp1
    cmp     eax, 0x81
    je      .grp1
    cmp     eax, 0x83
    je      .grp1
    cmp     eax, 0x84
    je      .ctest
    cmp     eax, 0x85
    je      .ctest
    cmp     eax, 0x88
    je      .cnt
    cmp     eax, 0x8F
    je      .pop2
    cmp     eax, 0xA5
    je      .shxd
    cmp     eax, 0xAD
    je      .shxd
    cmp     eax, 0xAF
    je      .imul2
    cmp     eax, 0xC0
    je      .grp2
    cmp     eax, 0xC1
    je      .grp2
    cmp     eax, 0xD0
    jb      .not_grp2
    cmp     eax, 0xD3
    jbe     .grp2
.not_grp2:
    cmp     eax, 0xF0
    jb      .fail
    cmp     eax, 0xF2
    jbe     .f0
    cmp     eax, 0xF4
    je      .cnt
    cmp     eax, 0xF5
    je      .cnt
    cmp     eax, 0xF6
    je      .grp3
    cmp     eax, 0xF7
    je      .grp3
    cmp     eax, 0xF8
    je      .f8
    cmp     eax, 0xF9
    je      .movdiri
    cmp     eax, 0xFE
    je      .grp45
    cmp     eax, 0xFF
    je      .grp45
    jmp     .fail

; ---- the printing parts ----

; .begin: ModRM read; {evex} when ND 0, NF 0 and no r16-r31 (objdump's);
; {nf} by NF unless the form says (edi: 1 = NF is part of the name)
.begin:
    push    rdi
    call    dx_modrm_decode
    pop     rdi
    cmp     byte [rel dx_fail], 0
    jne     .begin_ret
    mov     al, [rel d4_nf]
    test    edi, edi
    jz      .begin_nf
    xor     eax, eax
.begin_nf:
    mov     [rel dx_nf], al
    cmp     byte [rel d4_nd], 0
    jne     .begin_ret
    cmp     byte [rel d4_nf], 0
    jne     .begin_ret
    test    edi, edi
    jnz     .begin_ret                     ; (APX's own: no {evex})
    cmp     byte [rel dx_regno], 16
    jae     .begin_ret
    cmp     byte [rel dx_mod], 3
    jne     .begin_mem
    cmp     byte [rel dx_rmreg], 16
    jae     .begin_ret
    jmp     .begin_evex
.begin_mem:
    movzx   eax, byte [rel dx_base]
    sub     eax, 16
    cmp     eax, 16
    jb      .begin_ret
    movzx   eax, byte [rel dx_index]
    sub     eax, 16
    cmp     eax, 16
    jb      .begin_ret
.begin_evex:
    mov     byte [rel dx_evexp], 1
.begin_ret:
    ret

; .name: the mnemonic rsi (a string), printed with its padding
.name:
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    jmp     dx_mnemonic

; .ccname: the mnemonic rsi (a stem) + the condition suffix of eax (sc:
; t / f for 10 / 11 when edx = 1), into dx_namebuf
.ccname:
    lea     rdi, [rel dx_namebuf]
.cn_stem:
    mov     cl, [rsi]
    test    cl, cl
    jz      .cn_cc
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    jmp     .cn_stem
.cn_cc:
    lea     rsi, [rel d4_cc]
    test    edx, edx
    jz      .cn_tab
    lea     rsi, [rel d4_scc]
.cn_tab:
    and     eax, 15
    lea     rsi, [rsi + rax * 4]
.cn_suf:
    mov     cl, [rsi]
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    test    cl, cl
    jnz     .cn_suf
    lea     rsi, [rel dx_namebuf]
    jmp     .name

; .vreg: the new destination (vvvv) at the operation's size, and a comma
.vreg:
    movzx   edi, byte [rel d4_osz]
    movzx   esi, byte [rel d4_vvvv]
    call    dx_reg
    jmp     dx_sep

; .nd_vreg: .vreg when ND
.nd_vreg:
    cmp     byte [rel d4_nd], 0
    je      .nd_ret
    jmp     .vreg
.nd_ret:
    ret

; .rm / .greg at the operation's size (8 for a byte opcode: edi set first)
.rm_osz:
    movzx   edi, byte [rel d4_osz]
    jmp     dx_rm
.greg_osz:
    movzx   edi, byte [rel d4_osz]
    jmp     dx_greg

; .byte_op: the opcode's low bit 0 (a byte form): the size is 8
.byte_op:
    test    byte [rel dx_op], 1
    jnz     .bo_ret
    mov     byte [rel d4_osz], 8
    mov     byte [rel dx_osz], 8
.bo_ret:
    ret

; .imm8s: an imm8, sign-extended, printed at the operation's size
.imm8s:
    call    dx_rd8
    movsx   rsi, al
    jmp     dx_imm
; .immz: an imm16 / imm32 (sign-extended), by the operation's size
.immz:
    cmp     byte [rel d4_osz], 16
    je      .immz16
    cmp     byte [rel d4_osz], 8
    je      .imm8u
    call    dx_rd32
    movsxd  rsi, eax
    jmp     dx_imm
.immz16:
    call    dx_rd16
    movzx   esi, ax
    jmp     dx_imm
.imm8u:
    call    dx_rd8
    movzx   esi, al
    jmp     dx_imm

.fail:
    mov     byte [rel dx_fail], 1
.done:
    pop     rbx
    ret

; ---- add .. xor: 00 / 01 r/m, r; 02 / 03 r, r/m ----
.alu:
    mov     ecx, eax
    and     ecx, 7
    cmp     ecx, 3
    ja      .alu_shxd                      ; 24 / 2C: shld / shrd imm8
    mov     ebx, eax
    shr     ebx, 3                         ; 0 add 1 or 2 adc 3 sbb 4 and 5 sub 6 xor
    cmp     ebx, 7
    je      .fail
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    call    .byte_op
    lea     rsi, [rel d4_alu]
    mov     rsi, [rsi + rbx * 8]
    call    .name
    call    .nd_vreg
    test    byte [rel dx_op], 2
    jnz     .alu_r_rm
    call    .rm_osz                        ; r/m, r
    call    dx_sep
    call    .greg_osz
    jmp     .done
.alu_r_rm:
    call    .greg_osz                      ; r, r/m
    call    dx_sep
    call    .rm_osz
    jmp     .done
.alu_shxd:
    cmp     eax, 0x24
    je      .shxd
    cmp     eax, 0x2C
    je      .shxd
    jmp     .fail

; ---- 80 / 81 / 83: add .. xor r/m, imm (/7: ccmp) ----
.grp1:
    call    dx_peek
    shr     eax, 3
    and     eax, 7
    cmp     eax, 7
    je      .ccmp
    mov     ebx, eax
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    call    .byte_op
    lea     rsi, [rel d4_alu]
    mov     rsi, [rsi + rbx * 8]
    call    .name
    call    .nd_vreg
    call    .rm_osz
    call    dx_sep
    cmp     byte [rel dx_op], 0x83
    je      .grp1_s
    call    .immz
    jmp     .done
.grp1_s:
    call    .imm8s
    jmp     .done

; ---- FE / FF: inc dec (/0 /1), push2 (FF /6) ----
.grp45:
    call    dx_peek
    shr     eax, 3
    and     eax, 7
    cmp     eax, 6
    je      .push2
    cmp     eax, 1
    ja      .fail
    lea     rsi, [rel s4_inc]
    test    eax, eax
    jz      .unary
    lea     rsi, [rel s4_dec]
.unary:
    push    rsi
    xor     edi, edi
    call    .begin
    pop     rsi
    cmp     byte [rel dx_fail], 0
    jne     .fail
    call    .byte_op
    call    .name
    call    .nd_vreg
    call    .rm_osz
    jmp     .done

; ---- F6 / F7: ctest /0, not /2, neg /3, mul /4, imul /5, div /6, idiv /7 ----
.grp3:
    call    dx_peek
    shr     eax, 3
    and     eax, 7
    test    eax, eax
    jz      .ctest_imm
    cmp     eax, 1
    je      .fail
    lea     rcx, [rel d4_grp3]
    mov     rsi, [rcx + rax * 8]
    cmp     eax, 4
    jb      .unary                         ; not / neg: (dest,) r/m
    jmp     .unary                         ; mul .. idiv: r/m

; ---- shifts: C0 / C1 imm8, D0 / D1 by 1, D2 / D3 by cl ----
.grp2:
    call    dx_peek
    shr     eax, 3
    and     eax, 7
    mov     ebx, eax
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    call    .byte_op
    lea     rsi, [rel d4_grp2]
    mov     rsi, [rsi + rbx * 8]
    call    .name
    call    .nd_vreg
    call    .rm_osz
    call    dx_sep
.count:
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0xD2
    jae     .count_cl
    cmp     eax, 0xD0
    jae     .count_1
    call    dx_rd8
    movzx   esi, al
    call    dx_hex
    jmp     .done
.count_1:
    mov     esi, '1'
    call    dx_putc
    jmp     .done
.count_cl:
    lea     rsi, [rel s4_cl]
    call    dx_puts
    jmp     .done

; ---- shld / shrd: 24 / 2C imm8, A5 / AD cl ----
.shxd:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_shld]
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0x24
    je      .shxd_name
    cmp     eax, 0xA5
    je      .shxd_name
    lea     rsi, [rel s4_shrd]
.shxd_name:
    call    .name
    call    .nd_vreg
    call    .rm_osz
    call    dx_sep
    call    .greg_osz
    call    dx_sep
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0xA0
    jae     .count_cl
    call    dx_rd8
    movzx   esi, al
    call    dx_hex
    jmp     .done

; ---- imul: AF (NDD: dest, r, r/m), 69 / 6B r, r/m, imm ({zu}: imulzu) ----
.imul2:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_imul]
    call    .name
    call    .nd_vreg
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done
.imul_imm:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_imul]
    cmp     byte [rel d4_nd], 0
    je      .imul_imm_name
    lea     rsi, [rel s4_imulzu]
.imul_imm_name:
    call    .name
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    call    dx_sep
    cmp     byte [rel dx_op], 0x6B
    je      .imul_i8
    call    .immz
    jmp     .done
.imul_i8:
    call    .imm8s
    jmp     .done

; ---- popcnt (88), tzcnt (F4), lzcnt (F5): r, r/m ----
.cnt:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_popcnt]
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0x88
    je      .cnt_name
    lea     rsi, [rel s4_tzcnt]
    cmp     eax, 0xF4
    je      .cnt_name
    lea     rsi, [rel s4_lzcnt]
.cnt_name:
    call    .name
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done

; ---- 66: adcx (66) / adox (F3): (dest,) r, r/m; wrss (none): m, r ----
.adx:
    ; sized by W only (the 66 is the mnemonic's)
    mov     ecx, 32
    test    byte [rel dx_rex], 8
    jz      .adx_osz
    mov     ecx, 64
.adx_osz:
    mov     [rel d4_osz], cl
    mov     [rel dx_osz], cl
    cmp     byte [rel d4_pp], 0
    je      .wrss
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_adcx]
    cmp     byte [rel d4_pp], 1
    je      .adx_name
    lea     rsi, [rel s4_adox]
    cmp     byte [rel d4_pp], 2
    jne     .fail
.adx_name:
    call    .name
    call    .nd_vreg
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done

; ---- wrss (66, none) / wruss (65, 66): m, r - "wrssq [r16],rax" ----
.wruss:
    mov     ecx, 32
    test    byte [rel dx_rex], 8
    jz      .wruss_osz
    mov     ecx, 64
.wruss_osz:
    mov     [rel d4_osz], cl
    mov     [rel dx_osz], cl
    cmp     byte [rel d4_pp], 1
    jne     .fail
    lea     rbx, [rel s4_wruss]
    jmp     .ss_go
.wrss:
    lea     rbx, [rel s4_wrss]
.ss_go:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    cmp     byte [rel dx_mod], 3
    je      .fail
    mov     rsi, rbx
    lea     rdi, [rel dx_namebuf]
.ss_copy:
    mov     al, [rsi]
    test    al, al
    jz      .ss_suf
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .ss_copy
.ss_suf:
    mov     byte [rdi], 'd'
    cmp     byte [rel d4_osz], 64
    jne     .ss_end
    mov     byte [rdi], 'q'
.ss_end:
    mov     byte [rdi + 1], 0
    lea     rsi, [rel dx_namebuf]
    call    .name
    xor     edi, edi
    call    dx_mem
    call    dx_sep
    call    .greg_osz
    jmp     .done

; ---- movbe: 60 r, m; 61 r/m, r ----
.movbe:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_movbe]
    call    .name
    cmp     byte [rel dx_op], 0x61
    je      .movbe_st
    cmp     byte [rel dx_mod], 3
    je      .fail
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done
.movbe_st:
    call    .rm_osz
    call    dx_sep
    call    .greg_osz
    jmp     .done

; ---- F0 F1 F2: crc32 (none / 66), invept invvpid invpcid (F3) ----
.f0:
    cmp     byte [rel d4_pp], 2
    je      .inv
    cmp     byte [rel dx_op], 0xF2
    je      .fail
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_crc32]
    call    .name
    ; the destination: 64 with W, else 32; the source: F0 a byte, F1 by
    ; 66 / W
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .crc_dst
    mov     edi, 64
.crc_dst:
    push    rdi
    call    dx_greg
    call    dx_sep
    pop     rdi
    cmp     byte [rel dx_op], 0xF0
    jne     .crc_src
    mov     edi, 8
    jmp     .crc_put
.crc_src:
    cmp     byte [rel d4_pp], 1
    jne     .crc_put
    mov     edi, 16
.crc_put:
    mov     [rel dx_osz], dil
    call    dx_rm
    jmp     .done
.inv:
    lea     rcx, [rel d4_inv]
    movzx   eax, byte [rel dx_op]
    sub     eax, 0xF0
    mov     rbx, [rcx + rax * 8]
    jmp     .r64_m
; ---- F8: movdir64b (66), enqcmds (F3), enqcmd (F2): r64, m ----
.f8:
    movzx   eax, byte [rel d4_pp]
    test    eax, eax
    jz      .fail
    lea     rcx, [rel d4_f8]
    mov     rbx, [rcx + rax * 8]
.r64_m:
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    cmp     byte [rel dx_mod], 3
    je      .fail
    mov     rsi, rbx
    call    .name
    mov     edi, 64
    cmp     byte [rel dx_p67], 0
    je      .r64_put
    mov     edi, 32
.r64_put:
    call    dx_greg
    call    dx_sep
    xor     edi, edi
    call    dx_mem
    jmp     .done
; ---- F9: movdiri m, r ----
.movdiri:
    mov     ecx, 32
    test    byte [rel dx_rex], 8
    jz      .md_osz
    mov     ecx, 64
.md_osz:
    mov     [rel d4_osz], cl
    mov     [rel dx_osz], cl
    xor     edi, edi
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    cmp     byte [rel dx_mod], 3
    je      .fail
    lea     rsi, [rel s4_movdiri]
    call    .name
    call    .rm_osz
    call    dx_sep
    call    .greg_osz
    jmp     .done

; ---- 40 + cc: cmov (ND), cfcmov, setcc (F2: setzu with ND) ----
.cc40:
    mov     ebx, eax
    and     ebx, 15
    cmp     byte [rel d4_pp], 3
    je      .setcc
    mov     edi, 1                         ; ({nf} / {evex}: the name's)
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_cfcmov]
    cmp     byte [rel d4_nf], 0
    jne     .cc_name
    cmp     byte [rel d4_nd], 0
    je      .cc_name
    lea     rsi, [rel s4_cmov]
.cc_name:
    mov     eax, ebx
    xor     edx, edx
    call    .ccname
    cmp     byte [rel d4_nd], 0
    jne     .cc_ndd
    cmp     byte [rel d4_nf], 0
    jne     .cc_store
    call    .greg_osz                      ; the load: r, r/m
    call    dx_sep
    call    .rm_osz
    jmp     .done
.cc_store:
    call    .rm_osz                        ; the store: r/m, r
    call    dx_sep
    call    .greg_osz
    jmp     .done
.cc_ndd:
    call    .vreg
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done
.setcc:
    xor     edi, edi
    cmp     byte [rel d4_nd], 0
    je      .setcc_begin
    mov     edi, 1                         ; (setzu: no {evex})
.setcc_begin:
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_set]
    cmp     byte [rel d4_nd], 0
    je      .setcc_name
    lea     rsi, [rel s4_setzu]
.setcc_name:
    mov     eax, ebx
    xor     edx, edx
    call    .ccname
    mov     edi, 8
    call    dx_rm
    jmp     .done

; ---- ccmp: 38 / 39 r/m, r; 3A / 3B r, r/m; 80 / 81 / 83 /7 r/m, imm ----
.ccmp:
    mov     edi, 1
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_ccmp]
    call    .scname
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0x80
    jae     .ccmp_imm
    call    .byte_op
    test    byte [rel dx_op], 2
    jnz     .ccmp_r_rm
    call    .rm_osz
    call    dx_sep
    call    .greg_osz
    jmp     .done
.ccmp_r_rm:
    call    .greg_osz
    call    dx_sep
    call    .rm_osz
    jmp     .done
.ccmp_imm:
    call    .byte_op
    call    .rm_osz
    call    dx_sep
    cmp     byte [rel dx_op], 0x83
    je      .ccmp_i8
    call    .immz
    jmp     .done
.ccmp_i8:
    call    .imm8s
    jmp     .done

; ---- ctest: 84 / 85 r/m, r; F6 / F7 /0 r/m, imm ----
.ctest:
    mov     edi, 1
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_ctest]
    call    .scname
    call    .byte_op
    call    .rm_osz
    call    dx_sep
    call    .greg_osz
    jmp     .done
.ctest_imm:
    mov     edi, 1
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    lea     rsi, [rel s4_ctest]
    call    .scname
    call    .byte_op
    call    .rm_osz
    call    dx_sep
    call    .immz
    jmp     .done

; .scname: rsi's stem + the source condition (t, f) + " {dfv=..}", the
; whole as the mnemonic, as objdump writes it
.scname:
    lea     rdi, [rel dx_namebuf]
.sn_stem:
    mov     cl, [rsi]
    test    cl, cl
    jz      .sn_cc
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    jmp     .sn_stem
.sn_cc:
    movzx   eax, byte [rel d4_sc]
    lea     rsi, [rel d4_scc]
    lea     rsi, [rsi + rax * 4]
.sn_suf:
    mov     cl, [rsi]
    test    cl, cl
    jz      .sn_dfv
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    jmp     .sn_suf
.sn_dfv:
    lea     rsi, [rel s4_dfv]
.sn_d0:
    mov     cl, [rsi]
    test    cl, cl
    jz      .sn_flags
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    jmp     .sn_d0
.sn_flags:
    movzx   edx, byte [rel d4_dfv]
    xor     r8d, r8d                       ; one written already
    lea     rsi, [rel s4_flags]            ; "of" 8, "sf" 4, "zf" 2, "cf" 1
    mov     ecx, 8
.sn_flag:
    test    edx, ecx
    jz      .sn_flag_next
    test    r8d, r8d
    jz      .sn_flag_put
    mov     byte [rdi], ','
    mov     byte [rdi + 1], ' '
    add     rdi, 2
.sn_flag_put:
    mov     ax, [rsi]
    mov     [rdi], ax
    add     rdi, 2
    mov     r8d, 1
.sn_flag_next:
    add     rsi, 2
    shr     ecx, 1
    jnz     .sn_flag
    mov     byte [rdi], '}'
    mov     byte [rdi + 1], 0
    lea     rsi, [rel dx_namebuf]
    jmp     .name

; ---- push2 (FF /6) / pop2 (8F /0): ND, vvvv the first; W: the p form ----
.push2:
    lea     rbx, [rel s4_push2]
    test    byte [rel dx_rex], 8
    jz      .pp2
    lea     rbx, [rel s4_push2p]
    jmp     .pp2
.pop2:
    call    dx_peek
    shr     eax, 3
    and     eax, 7
    jnz     .fail
    lea     rbx, [rel s4_pop2]
    test    byte [rel dx_rex], 8
    jz      .pp2
    lea     rbx, [rel s4_pop2p]
.pp2:
    cmp     byte [rel d4_nd], 0
    je      .fail
    mov     edi, 1
    call    .begin
    cmp     byte [rel dx_fail], 0
    jne     .fail
    cmp     byte [rel dx_mod], 3
    jne     .fail
    mov     rsi, rbx
    call    .name
    mov     byte [rel d4_osz], 64
    call    .vreg
    mov     edi, 64
    call    dx_rm
    jmp     .done

[SECTION .rodata]
align 8
d4_alu:     dq s4_add, s4_or, s4_adc, s4_sbb, s4_and, s4_sub, s4_xor
d4_grp2:    dq s4_rol, s4_ror, s4_rcl, s4_rcr, s4_shl, s4_shr, s4_sal, s4_sar
d4_grp3:    dq 0, 0, s4_not, s4_neg, s4_mul, s4_imul, s4_div, s4_idiv
d4_inv:     dq s4_invept, s4_invvpid, s4_invpcid
d4_f8:      dq 0, s4_movdir64b, s4_enqcmds, s4_enqcmd
d4_cc:      db "o",0,0,0, "no",0,0, "b",0,0,0, "ae",0,0, "e",0,0,0, "ne",0,0, "be",0,0, "a",0,0,0
            db "s",0,0,0, "ns",0,0, "p",0,0,0, "np",0,0, "l",0,0,0, "ge",0,0, "le",0,0, "g",0,0,0
d4_scc:     db "o",0,0,0, "no",0,0, "b",0,0,0, "ae",0,0, "e",0,0,0, "ne",0,0, "be",0,0, "a",0,0,0
            db "s",0,0,0, "ns",0,0, "t",0,0,0, "f",0,0,0, "l",0,0,0, "ge",0,0, "le",0,0, "g",0,0,0
s4_add:     db "add", 0
s4_or:      db "or", 0
s4_adc:     db "adc", 0
s4_sbb:     db "sbb", 0
s4_and:     db "and", 0
s4_sub:     db "sub", 0
s4_xor:     db "xor", 0
s4_inc:     db "inc", 0
s4_dec:     db "dec", 0
s4_not:     db "not", 0
s4_neg:     db "neg", 0
s4_mul:     db "mul", 0
s4_imul:    db "imul", 0
s4_imulzu:  db "imulzu", 0
s4_div:     db "div", 0
s4_idiv:    db "idiv", 0
s4_rol:     db "rol", 0
s4_ror:     db "ror", 0
s4_rcl:     db "rcl", 0
s4_rcr:     db "rcr", 0
s4_shl:     db "shl", 0
s4_shr:     db "shr", 0
s4_sal:     db "sal", 0
s4_sar:     db "sar", 0
s4_shld:    db "shld", 0
s4_shrd:    db "shrd", 0
s4_cl:      db "cl", 0
s4_popcnt:  db "popcnt", 0
s4_lzcnt:   db "lzcnt", 0
s4_tzcnt:   db "tzcnt", 0
s4_adcx:    db "adcx", 0
s4_adox:    db "adox", 0
s4_wrss:    db "wrss", 0
s4_wruss:   db "wruss", 0
s4_movbe:   db "movbe", 0
s4_crc32:   db "crc32", 0
s4_invept:  db "invept", 0
s4_invvpid: db "invvpid", 0
s4_invpcid: db "invpcid", 0
s4_movdir64b: db "movdir64b", 0
s4_enqcmd:  db "enqcmd", 0
s4_enqcmds: db "enqcmds", 0
s4_movdiri: db "movdiri", 0
s4_cmov:    db "cmov", 0
s4_cfcmov:  db "cfcmov", 0
s4_set:     db "set", 0
s4_setzu:   db "setzu", 0
s4_ccmp:    db "ccmp", 0
s4_ctest:   db "ctest", 0
s4_dfv:     db " {dfv=", 0
s4_flags:   db "ofsfzfcf"
s4_push2:   db "push2", 0
s4_push2p:  db "push2p", 0
s4_pop2:    db "pop2", 0
s4_pop2p:   db "pop2p", 0
s4_evex:    db "{evex} ", 0
[SECTION .text]
