; ============================================================================
; File        : src/tools/disasm/x86/decode.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : dx_decode1: one instruction - prefixes, opcode maps
; ============================================================================


; dx_decode1: x86_decode's decoder itself (the same input / output)
dx_decode1:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     [rel dx_start], rdi
    mov     [rel dx_cur], rdi
    cmp     rsi, 15
    jbe     .avail_ok
    mov     esi, 15                        ; an instruction is at most 15 bytes
.avail_ok:
    add     rsi, rdi
    mov     [rel dx_end], rsi
    mov     [rel dx_addr], rdx
    mov     [rel dx_fb], rcx
    mov     rax, [rcx + FMTBUF_len]
    mov     [rel dx_textpos], rax
    mov     qword [rel dx_target], -1
    mov     qword [rel x86_rip_target], -1
    xor     eax, eax
    mov     [rel dx_ripmem], al
    mov     [rel dx_ewretry], al
    mov     [rel dx_undef], al
    mov     [rel dx_trunc], al
    mov     [rel dx_sel66], al
    mov     [rel dx_ssepfx], al
    mov     [rel dx_vexpath], al
    mov     [rel dx_badk], al
    mov     [rel dx_rex2own], al
    mov     byte [rel dx_vraw], 0xFF
    mov     byte [rel dx_pgnamed], 0
    mov     qword [rel dx_opend], 0
    mov     qword [rel dx_opstart], 0
    mov     [rel dx_markbad], al
    mov     byte [rel dx_repbad], 0xFF
    mov     [rel dx_rex], al
    mov     [rel dx_rex4], al
    mov     [rel dx_rex2], al
    mov     [rel dx_nf], al
    mov     [rel dx_evexp], al
    mov     [rel dx_p66], al
    mov     [rel dx_n66], al
    mov     [rel dx_d16w], al
    mov     [rel dx_sflags], al
    mov     [rel dx_vex], al
    mov     [rel dx_vl], al
    mov     [rel dx_vvvv], al
    mov     [rel dx_vpfx], al
    mov     [rel dx_half], al
    mov     [rel dx_narrow], al
    mov     byte [rel dx_vclass], 1
    mov     [rel dx_p67], al
    mov     [rel dx_lock], al
    mov     [rel dx_rep], al
    mov     [rel dx_repne], al
    mov     [rel dx_seg], al
    mov     [rel dx_vsib], al
    mov     [rel dx_vexp], al
    mov     [rel dx_fail], al
    mov     [rel dx_evex], al
    mov     [rel dx_reghi], al
    mov     [rel dx_rmhi], al
    mov     [rel dx_eaaa], al
    mov     [rel dx_ez], al
    mov     [rel dx_eb], al
    mov     [rel dx_epred], al
    mov     [rel dx_fwait], al
    mov     byte [rel dx_disp8n], 1

    ; ---- legacy prefixes ----
.prefix:
    call    dx_peek
    cmp     byte [rel dx_fail], 0
    jne     .bad
    cmp     al, 0xF0
    je      .p_lock
    cmp     al, 0xF2
    je      .p_repne
    cmp     al, 0xF3
    je      .p_rep
    cmp     al, 0x66
    je      .p_66
    cmp     al, 0x67
    je      .p_67
    mov     cl, 'c'
    cmp     al, 0x2E
    je      .p_seg
    mov     cl, 's'
    cmp     al, 0x36
    je      .p_seg
    mov     cl, 'd'
    cmp     al, 0x3E
    je      .p_seg
    mov     cl, 'e'
    cmp     al, 0x26
    je      .p_seg
    mov     cl, 'f'
    cmp     al, 0x64
    je      .p_seg
    mov     cl, 'g'
    cmp     al, 0x65
    je      .p_seg
    jmp     .rex
.p_lock:
    mov     byte [rel dx_lock], 1
    jmp     .p_skip
.p_repne:
    mov     byte [rel dx_repne], 1
    jmp     .p_skip
.p_rep:
    mov     byte [rel dx_rep], 1
    jmp     .p_skip
.p_66:
    mov     byte [rel dx_p66], 1
    inc     byte [rel dx_n66]
    jmp     .p_skip
.p_67:
    mov     byte [rel dx_p67], 1
    jmp     .p_skip
.p_seg:
    mov     [rel dx_seg], cl
.p_skip:
    call    dx_rd8
    jmp     .prefix

    ; ---- REX ----
.rex:
    ; the mode (x86_mode; 0 is 64) and the address size: the mode's, or
    ; with 67 the other one (64: 32, 32: 16, 16: 32)
    movzx   ecx, byte [rel x86_mode]
    test    ecx, ecx
    jnz     .mode_set
    mov     ecx, 64
.mode_set:
    mov     [rel dx_mode], cl
    mov     edx, ecx
    cmp     byte [rel dx_p67], 0
    je      .asz_set
    mov     edx, 32
    cmp     ecx, 64
    je      .asz_set
    mov     edx, 16
    cmp     ecx, 32
    je      .asz_set
    mov     edx, 32
.asz_set:
    mov     [rel dx_asz], dl
    cmp     ecx, 64
    je      .rex64
    ; 16 / 32-bit mode: no REX / REX2 (40-4F are inc / dec, D5 aad); C4 /
    ; C5 / 62 are VEX / EVEX only where the next byte would be a ModRM of
    ; mod 11 (les / lds / bound take memory)
    cmp     al, 0x8F
    je      .xop_check
    cmp     al, 0x62
    je      .legacy_vex
    cmp     al, 0xC4
    je      .legacy_vex
    cmp     al, 0xC5
    jne     .opcode
.legacy_vex:
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 1]
    cmp     rdx, [rel dx_end]
    jae     .opcode
    cmp     byte [rcx + 1], 0xC0
    jb      .opcode
    cmp     al, 0x62
    je      .evex
    cmp     al, 0xC5
    je      .vex2
    jmp     .vex3
.rex64:
    cmp     al, 0xD5
    je      .rex2
    cmp     al, 0x62
    je      .evex
    cmp     al, 0xC5
    je      .vex2
    cmp     al, 0xC4
    je      .vex3
    cmp     al, 0x8F
    jne     .not_xop
.xop_check:
    ; 8F with a map of 8 or more in the next byte's low 5 bits: AMD's XOP
    ; (pop r/m's ModRM.reg is 0, so its byte there is below 8 ... or not
    ; - objdump reads XOP)
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 1]
    cmp     rdx, [rel dx_end]
    jae     .not_xop
    movzx   edx, byte [rcx + 1]
    and     edx, 0x1F
    cmp     edx, 8
    jae     .xop3
.not_xop:
    cmp     byte [rel dx_mode], 64
    jne     .opcode                        ; (no REX outside 64-bit mode)
    mov     ecx, eax
    and     ecx, 0xF0
    cmp     ecx, 0x40
    jne     .opcode
    call    dx_rd8
    mov     [rel dx_rex], al
    call    dx_peek                        ; (a VEX after it: the REX ignored)
    cmp     al, 0xC5
    je      .vex2
    cmp     al, 0xC4
    je      .vex3
    cmp     al, 0x8F
    jne     .opcode
    mov     rcx, [rel dx_cur]              ; (XOP: a map of 8 or more)
    lea     rdx, [rcx + 1]
    cmp     rdx, [rel dx_end]
    jae     .opcode
    movzx   edx, byte [rcx + 1]
    and     edx, 0x1F
    cmp     edx, 8
    jae     .xop3
    jmp     .opcode

    ; ---- REX2 (APX): D5, M0 R4 X4 B4 W R3 X3 B3 ----
; W R3 X3 B3 a REX byte as ever, R4 X4 B4 dx_rex4 (bit 4 of the registers
; for r16-r31); M0 the 0F map, its 0F not written. No 0F 38 / 0F 3A.
.rex2:
    call    dx_rd8                         ; D5
    call    dx_rd8                         ; the payload
    cmp     byte [rel dx_fail], 0
    jne     .bad
    mov     byte [rel dx_rex2], 1
    mov     ecx, eax
    and     ecx, 0x0F
    or      ecx, 0x40
    mov     [rel dx_rex], cl
    mov     ecx, eax
    and     ecx, 0x70
    mov     [rel dx_rex4], cl
    test    al, 0x80
    jz      .opcode
    call    dx_rd8                         ; the 0F map's opcode
    cmp     byte [rel dx_fail], 0
    jne     .bad
    cmp     al, 0x38
    je      .bad
    cmp     al, 0x3A
    je      .bad
    mov     byte [rel dx_map], 2
    lea     r12, [rel x86_map2]
    jmp     .have_op

    ; ---- VEX (C5 xx / C4 xx xx): AVX, AVX2, FMA, BMI ----
; The R/X/B/W bits become a synthetic REX byte, so the ModRM/SIB code and
; the REX.W checks work unchanged. R, X, B and vvvv are stored inverted.
.vex2:
    call    dx_rd8                         ; C5
    mov     [rel dx_opend], rcx
    call    dx_rd8                         ; R vvvv L pp
    mov     byte [rel dx_map], 2           ; implied 0F map
    mov     edx, 0x40
    test    al, 0x80
    jnz     .vex_fields
    or      edx, 4                         ; R
    jmp     .vex_fields
    ; ---- XOP (8F xx xx, AMD): as VEX, maps 8 / 9 / A (dx_map 9-11), only
    ; in x86_vexgen ----
.xop3:
    call    dx_rd8                         ; 8F
    mov     [rel dx_opend], rcx            ; (no XOP after it: "(bad)" through 8F)
    call    dx_rd8                         ; R X B mmmmm
    mov     edx, 0x40
    test    al, 0x80
    jnz     .xo_x
    or      edx, 4                         ; R
.xo_x:
    test    al, 0x40
    jnz     .xo_b
    or      edx, 2                         ; X
.xo_b:
    test    al, 0x20
    jnz     .xo_map
    or      edx, 1                         ; B
.xo_map:
    and     eax, 0x1F
    cmp     eax, 10
    ja      .bad
    inc     eax                            ; 8 / 9 / A -> 9 / 10 / 11
    mov     [rel dx_map], al
    call    dx_rd8                         ; W vvvv L pp (rd8 keeps edx)
    test    al, 0x80
    jz      .vex_fields
    or      edx, 8                         ; W
    jmp     .vex_fields
.vex3:
    call    dx_rd8                         ; C4
    mov     [rel dx_opend], rcx            ; (no VEX after it: "(bad)" through C4)
    mov     [rel dx_vexstart], rcx
    call    dx_rd8                         ; R X B mmmmm
    mov     edx, 0x40
    test    al, 0x80
    jnz     .v3_x
    or      edx, 4                         ; R
.v3_x:
    test    al, 0x40
    jnz     .v3_b
    or      edx, 2                         ; X
.v3_b:
    test    al, 0x20
    jnz     .v3_map
    or      edx, 1                         ; B
.v3_map:
    and     eax, 0x1F
    cmp     eax, 7
    je      .vex7                          ; map 7: x86/apx.inc (dx_vex7)
    cmp     eax, 1
    jb      .bad
    cmp     eax, 6
    ja      .bad
    cmp     eax, 4
    je      .bad
    inc     eax                            ; 1/2/3 -> maps 2/3/4 (0F, 0F38, 0F3A),
                                           ; 5/6 -> 6/7 (AMX-FP8: x86_vexgen)
    mov     [rel dx_map], al
    call    dx_rd8                         ; W vvvv L pp (rd8 keeps edx)
    test    al, 0x80
    jz      .vex_fields
    or      edx, 8                         ; W
.vex_fields:
    ; eax = the byte holding vvvv L pp, edx = synthetic REX
    cmp     byte [rel dx_mode], 64
    je      .vf_rex
    and     edx, 0x48                      ; (16 / 32-bit mode: W alone)
.vf_rex:
    mov     [rel dx_rex], dl
    mov     ecx, eax
    shr     ecx, 3
    not     ecx
    and     ecx, 15
    mov     [rel dx_vraw], cl
    cmp     byte [rel dx_mode], 64
    je      .vf_vvvv
    and     ecx, 7
.vf_vvvv:
    mov     [rel dx_vvvv], cl
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 1
    mov     [rel dx_vl], cl
    and     eax, 3                         ; pp: prefix index
    mov     byte [rel dx_vex], 1
    push    rax
    call    dx_rd8                         ; opcode
    mov     [rel dx_opend], rcx            ; (where it ends)
    mov     byte [rel dx_vexpath], 1
    mov     [rel dx_op], al
    pop     rcx
    cmp     byte [rel dx_fail], 0
    jne     .bad
.vex_decode:
    ; k-mask instructions (AVX-512 opmask registers)
    call    dx_kop_find                    ; keeps rcx
    test    rax, rax
    jnz     .kop
    cmp     byte [rel dx_map], 2
    jne     .vex_tables
    cmp     byte [rel dx_op], 0xAE
    jne     .vex_tables
    test    ecx, ecx
    jz      .vex_ae
    jmp     .bad
.vex_tables:
    ; the generated entries first (x86_vexgen: the encoder's VEX forms the
    ; tables below have not), printed as EVEX's are (dx_evex_operands)
    movzx   eax, byte [rel dx_map]
    shl     eax, 8
    mov     al, [rel dx_op]
    shl     eax, 8
    or      eax, ecx                       ; pp
    shl     eax, 8
    test    byte [rel dx_rex], 8
    jz      .vg_key
    or      eax, 0x10
.vg_key:
    push    rcx
    mov     r9d, eax
    mov     ecx, eax
    lea     rdx, [rel x86_vexgen]
    call    dx_shape_find
    test    r12, r12
    jnz     .vg_found
    call    dx_peek                        ; a group member: 8 + ModRM.reg
    cmp     byte [rel dx_fail], 0
    jne     .vg_none
    shr     eax, 3
    and     eax, 7
    lea     ecx, [r9 + rax + 8]
    lea     rdx, [rel x86_vexgen]
    call    dx_shape_find
    test    r12, r12
    jnz     .vg_found
.vg_none:
    pop     rcx
    cmp     byte [rel dx_map], 4
    jbe     .vex_own
    cmp     byte [rel dx_map], 7           ; (XOP's maps 9-11 and map 5: through
    jne     .bad                           ; the opcode)
    mov     rax, [rel dx_vexstart]         ; (map 6: x86_vexgen's only - none
    mov     [rel dx_opend], rax            ; there, objdump's no map: "(bad)"
    mov     byte [rel dx_vexpath], 0       ; through the C4, its prefixes named)
    jmp     .bad
.vg_found:
    pop     rcx
    movzx   r13d, word [r12 + 4]           ; name
    mov     al, [r12 + 6]
    mov     [rel dx_emsize], al
    mov     al, [r12 + 7]
    mov     [rel dx_eflags], al
    mov     al, [r12 + 15]
    mov     [rel dx_eflags2], al
    test    byte [rel dx_eflags], EV_SAE   ; (VG_PVEX: objdump's "{vex}")
    jz      .vg_no_pvex
    mov     byte [rel dx_vexp], 1
    and     byte [rel dx_eflags], ~EV_SAE
.vg_no_pvex:
    xor     eax, eax
    mov     [rel dx_eaaa], al              ; (VEX: no mask, zeroing, broadcast)
    mov     [rel dx_ez], al
    mov     [rel dx_eb], al
    mov     byte [rel dx_disp8n], 1
    call    dx_shape_vsib
    call    dx_vvvv_unused
    jnz     .undef
    mov     byte [rel dx_flags], FL_MODRM
    mov     byte [rel dx_form], FM_EVEX
    jmp     .entry_loaded
.vex_own:
    ; VEX-only table first
    lea     rdx, [rel x86_vex0f]
    cmp     byte [rel dx_map], 3
    jb      .vex_tab
    lea     rdx, [rel x86_vex38]
    je      .vex_tab
    lea     rdx, [rel x86_vex3a]
.vex_tab:
    movzx   eax, byte [rel dx_op]
    lea     eax, [rax*4 + rcx]
    lea     r12, [rdx + rax*4]
    movzx   r13d, word [r12]
    cmp     r13d, 0xFFFF
    je      .vex_sse
    mov     al, [r12 + 3]
    mov     [rel dx_sflags], al            ; bit 3 = VF_WSD here
    jmp     .vex_loaded
.vex_sse:
    ; otherwise the SSE instruction with a "v" in front
    lea     rdx, [rel x86_sse0f]
    cmp     byte [rel dx_map], 3
    jb      .vex_sse_tab
    lea     rdx, [rel x86_sse38]
    je      .vex_sse_tab
    lea     rdx, [rel x86_sse3a]
.vex_sse_tab:
    movzx   eax, byte [rel dx_op]
    lea     eax, [rax*4 + rcx]
    lea     r12, [rdx + rax*4]
    movzx   r13d, word [r12]
    cmp     r13d, 0xFFFF
    je      .bad
    mov     al, [r12 + 3]
    test    al, SF_INT | SF_NOVEX | SF_MMX
    jnz     .bad
    mov     [rel dx_sflags], al
    mov     byte [rel dx_vpfx], 1
.vex_loaded:
    or      byte [rel dx_sflags], 0x80     ; mark "vector"
    mov     al, [r12 + 2]
    mov     [rel dx_form], al
    ; an SSE instruction's VEX form with no vvvv operand: vvvv 1111, else
    ; no instruction (#UD; objdump's "(bad)")
    cmp     byte [rel dx_vpfx], 0
    je      .vex_vvvv_ok
    test    byte [rel dx_sflags], SF_NDS
    jnz     .vex_vvvv_ok
    test    byte [rel dx_vvvv], 15
    jz      .vex_vvvv_ok
    lea     rdx, [rel vex_novvvv_forms]
.vex_nv_scan:
    movzx   ecx, byte [rdx]
    cmp     ecx, 0xFF
    je      .vex_vvvv_ok
    cmp     ecx, eax
    je      .vex_vvvv_bad
    inc     rdx
    jmp     .vex_nv_scan
.vex_vvvv_bad:
    mov     byte [rel dx_vpfx], 0
    jmp     .undef
.vex_vvvv_ok:
    mov     byte [rel dx_flags], FL_MODRM
    cmp     al, FM_XZERO
    jne     .vex_class
    mov     byte [rel dx_flags], 0
.vex_class:
    ; xmm, or ymm with VEX.L for packed operations (scalar ones stay xmm)
    mov     byte [rel dx_vclass], 1
    ; widening moves/conversions: xmm/ymm destination, half-width source
    cmp     byte [rel dx_map], 3
    jne     .half_0f
    movzx   eax, byte [rel dx_op]
    and     eax, 0xEF                      ; 20-25 and 30-35
    cmp     eax, 0x20
    jb      .not_half
    cmp     eax, 0x25
    ja      .not_half
    jmp     .is_half
.half_0f:
    cmp     byte [rel dx_map], 2
    jne     .not_half
    cmp     byte [rel dx_op], 0x5A         ; vcvtps2pd (no prefix)
    jne     .half_e6
    cmp     byte [rel dx_vpfx], 0
    je      .not_half
    cmp     ecx, 0
    je      .is_half
    cmp     ecx, 1                         ; vcvtpd2ps (66)
    je      .is_narrow
    jmp     .not_half
.half_e6:
    cmp     byte [rel dx_op], 0xE6         ; vcvtdq2pd (F3)
    jne     .not_half
    cmp     ecx, 2
    je      .is_half
    jmp     .is_narrow                     ; vcvttpd2dq (66), vcvtpd2dq (F2)
.is_narrow:
    mov     byte [rel dx_narrow], 1
    jmp     .not_half
.is_half:
    mov     byte [rel dx_half], 1
    jmp     .by_l
.not_half:
    cmp     byte [rel dx_form], FM_XBCAST
    je      .by_l                          ; broadcasts: destination by VEX.L
    cmp     byte [rel dx_vl], 0
    je      .entry_loaded
    movzx   eax, byte [rel dx_sflags]
    and     eax, SF_MEM
    jz      .vex_ymm
    cmp     eax, 5
    jne     .entry_loaded
.vex_ymm:
    mov     byte [rel dx_vclass], 2
    jmp     .entry_loaded
.by_l:
    cmp     byte [rel dx_vl], 0
    je      .entry_loaded
    mov     byte [rel dx_vclass], 2
    jmp     .entry_loaded

    ; ---- EVEX (62 P0 P1 P2): AVX-512 ----
; P0 = R X B R' 0 0 m m, P1 = W vvvv 1 pp, P2 = z L'L b V' aaa. As with VEX,
; R/X/B/W become a synthetic REX byte; R' (and X for a register rm) select
; vector registers 16-31, V' extends vvvv.
.evex:
    call    dx_rd8                         ; 62
    mov     [rel dx_opend], rcx            ; (no EVEX after it: "(bad)" through 62)
    call    dx_rd8                         ; P0
    cmp     byte [rel dx_mode], 64
    je      .e_p0_ok
    mov     edx, eax                       ; (16 / 32-bit mode: map 4 - no EVEX,
    and     edx, 7                         ; "(bad)" through 62, a prefix taken)
    cmp     edx, 4
    jne     .e_not4
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    jmp     .bad
.e_not4:
    cmp     edx, 7                         ; (map 7: P1's bit 2 as the others')
    jne     .e_p0_ok
    mov     rcx, [rel dx_cur]
    lea     rdx, [rcx + 2]
    cmp     rdx, [rel dx_end]
    ja      .e_p0_ok
    test    byte [rcx], 4
    jnz     .e_p0_ok
    inc     rcx
    mov     [rel dx_opend], rcx
    movzx   edx, byte [rcx]
    and     edx, 7
    mov     [rel dx_badk], dl
    jmp     .bad
.e_p0_ok:
    ; mmm: 1-3 0F / 0F 38 / 0F 3A, 5 / 6 (AVX512-FP16, AVX10.2), 4 and 7
    ; APX's (dx_evex4)
    mov     ecx, eax
    and     ecx, 7
    cmp     ecx, 4
    je      .evex4
    cmp     ecx, 7
    je      .evex4
    test    al, 0x08
    jz      .e_nob4
    or      byte [rel dx_rex4], 0x10       ; B4 (APX): a base / rm of r16-r31
.e_nob4:
    test    ecx, ecx
    jz      .bad
    inc     ecx                            ; 1/2/3/5/6 -> maps 2/3/4/6/7
    mov     [rel dx_map], cl
    mov     edx, 0x40
    test    al, 0x80
    jnz     .e_x
    or      edx, 4                         ; R
.e_x:
    test    al, 0x40
    jnz     .e_b
    or      edx, 2                         ; X
    mov     byte [rel dx_rmhi], 16
.e_b:
    test    al, 0x20
    jnz     .e_r2
    or      edx, 1                         ; B
.e_r2:
    test    al, 0x10
    jnz     .e_p1
    mov     byte [rel dx_reghi], 16        ; R'
    or      byte [rel dx_rex4], 0x40       ; (and R4: a general register's bit 4)
.e_p1:
    call    dx_rd8                         ; P1 (rd8 keeps edx)
    cmp     byte [rel dx_mode], 64
    je      .e_p1_ok
    test    al, 4
    jnz     .e_p1_ok
    mov     rcx, [rel dx_cur]              ; (16 / 32-bit mode: no EVEX - objdump
    mov     [rel dx_opend], rcx            ; takes 62 P0 P1 and writes P2's mask)
    call    dx_peek
    and     eax, 7
    mov     [rel dx_badk], al
    jmp     .bad
.e_p1_ok:
    test    al, 4
    jnz     .e_x4
    or      byte [rel dx_rex4], 0x20       ; X4 (APX, inverted): an index of r16-r31
.e_x4:
    test    al, 0x80
    jz      .e_w
    or      edx, 8                         ; W
.e_w:
    mov     [rel dx_rex], dl
    mov     ecx, eax
    shr     ecx, 3
    not     ecx
    and     ecx, 15
    mov     [rel dx_vvvv], cl
    and     eax, 3
    mov     r8d, eax                       ; pp
    call    dx_rd8                         ; P2
    mov     [rel dx_p2], al
    mov     ecx, eax
    and     ecx, 7
    mov     [rel dx_eaaa], cl
    mov     ecx, eax
    shr     ecx, 7
    mov     [rel dx_ez], cl
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 1
    mov     [rel dx_eb], cl
    mov     ecx, eax
    shr     ecx, 5
    and     ecx, 3
    mov     [rel dx_vl], cl
    test    al, 8
    jnz     .e_op
    or      byte [rel dx_vvvv], 16         ; V'
.e_op:
    cmp     byte [rel dx_mode], 64
    je      .e_op64
    and     byte [rel dx_rex], 0x48        ; (16 / 32-bit mode: registers 0-7)
    and     byte [rel dx_vvvv], 7
    mov     byte [rel dx_reghi], 0
    mov     byte [rel dx_rmhi], 0
    mov     byte [rel dx_rex4], 0
.e_op64:
    call    dx_rd8                         ; opcode
    mov     [rel dx_opend], rcx            ; (where it ends)
    mov     byte [rel dx_vexpath], 1
    mov     [rel dx_op], al
    cmp     byte [rel dx_fail], 0
    jne     .bad
    ; key = map << 24 | opcode << 16 | pp << 8 | W << 4
    movzx   ecx, byte [rel dx_map]
    shl     ecx, 8
    or      ecx, eax
    shl     ecx, 8
    or      ecx, r8d
    shl     ecx, 8
    test    byte [rel dx_rex], 8
    jz      .e_key
    or      ecx, 0x10
.e_key:
    mov     r9d, ecx
    lea     rdx, [rel x86_evex]
    call    dx_shape_find
    test    r12, r12
    jnz     .e_found
    ; a group member: 8 + ModRM.reg in the key
    call    dx_peek
    cmp     byte [rel dx_fail], 0
    jne     .bad
    shr     eax, 3
    and     eax, 7
    lea     ecx, [r9 + rax + 8]
    lea     rdx, [rel x86_evex]
    call    dx_shape_find
    test    r12, r12
    jnz     .e_found
    ; APX: a VEX instruction written as EVEX (kmov, BMI, AMX with r16-r31):
    ; no z, L'L 0 / 1, no broadcast, no mask but NF - the VEX tables with
    ; these fields
    movzx   eax, byte [rel dx_p2]
    test    eax, 0x80 | 0x40 | 0x10 | 0x03
    jnz     .bad
    test    eax, 0x04
    jz      .e_vex_nf
    mov     byte [rel dx_nf], 1
.e_vex_nf:
    mov     byte [rel dx_eaaa], 0
    mov     byte [rel dx_reghi], 0
    mov     byte [rel dx_rmhi], 0
    mov     byte [rel dx_vex], 1
    mov     ecx, r8d                       ; pp
    jmp     .vex_decode
.e_found:
    ; (16 / 32-bit mode: W1 of an E / G shape is ignored - the W0 entry)
    cmp     byte [rel dx_mode], 64
    je      .e_found_w
    test    byte [rel dx_rex], 8
    jz      .e_found_w
    cmp     byte [rel dx_ewretry], 0
    jne     .e_found_w
    lea     rax, [r12 + 8]
    mov     ecx, 7
.e_wscan:
    movzx   edx, byte [rax]
    cmp     edx, 'E'
    je      .e_wretry
    cmp     edx, 'G'
    je      .e_wretry
    inc     rax
    dec     ecx
    jnz     .e_wscan
    jmp     .e_found_w
.e_wretry:
    mov     byte [rel dx_ewretry], 1
    and     byte [rel dx_rex], ~8
    mov     ecx, r9d
    and     ecx, ~0x1F                     ; (no W, no group member)
    jmp     .e_key
.e_found_w:
    mov     byte [rel dx_evex], 1
    movzx   r13d, word [r12 + 4]           ; name
    mov     al, [r12 + 6]
    mov     [rel dx_emsize], al
    mov     al, [r12 + 7]
    mov     [rel dx_eflags], al
    mov     al, [r12 + 15]                 ; (the shape's last byte: EV2_*)
    mov     [rel dx_eflags2], al
    call    dx_shape_vsib
    call    dx_vvvv_unused
    jnz     .undef
    ; written as EVEX, readable as VEX: objdump's "{evex}" - no mask, no
    ; zeroing, no broadcast / rounding, 128 / 256 bits, registers 0-15
    test    byte [rel dx_eflags2], EV2_HASVEX
    jz      .e_no_evexp
    cmp     byte [rel dx_eaaa], 0
    jne     .e_no_evexp
    cmp     byte [rel dx_ez], 0
    jne     .e_no_evexp
    cmp     byte [rel dx_eb], 0
    jne     .e_no_evexp
    cmp     byte [rel dx_vl], 2
    jae     .e_no_evexp
    cmp     byte [rel dx_reghi], 0
    jne     .e_no_evexp
    cmp     byte [rel dx_rmhi], 0
    je      .e_rm_low
    call    dx_peek                        ; (EVEX.X: a register's bit 4 with a
    and     eax, 0xC0                      ; register, an index's bit 3 with memory)
    cmp     eax, 0xC0
    je      .e_no_evexp
.e_rm_low:
    cmp     byte [rel dx_vvvv], 16
    jae     .e_no_evexp
    cmp     byte [rel dx_rex4], 0
    jne     .e_no_evexp
    cmp     byte [rel dx_vsib], 0
    jne     .e_no_evexp
    ; 66 0F 71 / 72 / 73 (shifts by an imm8): VEX's are registers only -
    ; the memory forms are EVEX's alone
    cmp     byte [rel dx_map], 2
    jne     .e_vex_reads
    movzx   eax, byte [rel dx_op]
    sub     eax, 0x71
    cmp     eax, 2
    ja      .e_vex_reads
    call    dx_peek
    and     eax, 0xC0
    cmp     eax, 0xC0
    jne     .e_no_evexp
.e_vex_reads:
    mov     byte [rel dx_evexp], 1
.e_no_evexp:
    call    dx_peek                        ; ModRM
    cmp     byte [rel dx_fail], 0
    jne     .bad
    shr     eax, 6
    cmp     eax, 3
    je      .e_regs
    ; memory: EVEX.b broadcasts one element, and disp8 is scaled by N
    cmp     byte [rel dx_vl], 3
    je      .bad
    cmp     byte [rel dx_eb], 0
    je      .e_n_size
    test    byte [rel dx_eflags], EV_BCST
    jz      .bad
    jmp     .e_n_elem
.e_n_size:
    test    byte [rel dx_eflags], EV_NELEM
    jnz     .e_n_elem
    call    dx_evex_bytes
    jmp     .e_n
.e_n_elem:
    call    dx_evex_elem
.e_n:
    mov     [rel dx_disp8n], al
    jmp     .e_ready
.e_regs:
    ; registers: EVEX.b means rounding control or {sae}, at 512 bits
    cmp     byte [rel dx_eb], 0
    je      .e_len
    test    byte [rel dx_eflags], EV_ER | EV_SAE
    jz      .bad
    mov     al, [rel dx_vl]
    mov     [rel dx_eround], al
    mov     byte [rel dx_vl], 2
    jmp     .e_ready
.e_len:
    cmp     byte [rel dx_vl], 3
    je      .bad
.e_ready:
    mov     byte [rel dx_flags], FL_MODRM
    mov     byte [rel dx_form], FM_EVEX
    jmp     .entry_loaded

    ; ---- opcode ----
.opcode:
    mov     rcx, [rel dx_cur]
    mov     [rel dx_opstart], rcx
    call    dx_rd8
    cmp     byte [rel dx_fail], 0
    jne     .bad
    lea     r12, [rel x86_map1]
    mov     byte [rel dx_map], 1
    cmp     al, 0x0F
    jne     .have_op
    mov     byte [rel dx_map], 2
    call    dx_rd8
    cmp     byte [rel dx_fail], 0
    jne     .bad
    cmp     al, 0x38
    je      .map38
    cmp     al, 0x3A
    je      .map3a
    lea     r12, [rel x86_map2]
    jmp     .have_op
.map38:
    mov     byte [rel dx_map], 3
    jmp     .map3
.map3a:
    mov     byte [rel dx_map], 4
.map3:
    call    dx_rd8                         ; the opcode byte after 0F 38 / 0F 3A
    cmp     byte [rel dx_fail], 0
    jne     .bad
.have_op:
    mov     [rel dx_op], al
    mov     rcx, [rel dx_cur]
    mov     [rel dx_opend], rcx
    cmp     byte [rel dx_mode], 64
    je      .op_map_kept
    cmp     byte [rel dx_map], 1
    jne     .op_map_kept
    movzx   ecx, al
    lea     rdx, [rel x86_map1l]
    cmp     word [rdx + rcx * 4], 0xFFFF
    je      .op_map_kept
    mov     r12, rdx                       ; (16 / 32-bit mode's own)
.op_map_kept:
    ; F2 / F3 0F 38 F8 with a register: urdmsr / uwrmsr (x86/apx.inc)
    cmp     byte [rel dx_map], 3
    jne     .not_umsr
    cmp     al, 0xF8
    jne     .not_umsr
    call    dx_umsr
    test    eax, eax
    jz      .not_umsr_al
    cmp     byte [rel dx_fail], 0
    jne     .bad
    jmp     .finish
.not_umsr_al:
    mov     al, 0xF8
.not_umsr:
    ; REX2's own: jmpabs (A1 imm64, W 0), pushp / popp (50+r / 58+r, W 1)
    cmp     byte [rel dx_rex2], 0
    je      .not_rex2_own
    cmp     byte [rel dx_map], 1
    jne     .not_rex2_own
    cmp     al, 0xA1
    jne     .rex2_push
    test    byte [rel dx_rex], 8
    jnz     .bad
    call    dx_rd64
    cmp     byte [rel dx_fail], 0
    jne     .bad
    push    rax
    mov     byte [rel dx_rex2own], 1
    lea     rax, [rel s_jmpabs]
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    pop     rsi
    mov     byte [rel dx_osz], 64
    call    dx_hex
    jmp     .finish
.rex2_push:
    test    byte [rel dx_rex], 8
    jz      .not_rex2_own
    mov     ecx, eax
    and     ecx, 0xF0
    cmp     ecx, 0x50
    jne     .not_rex2_own
    mov     byte [rel dx_rex2own], 1
    lea     rcx, [rel s_pushp]
    cmp     al, 0x58
    jb      .rex2_pp
    lea     rcx, [rel s_popp]
.rex2_pp:
    mov     [rel dx_mnem], rcx
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 64
    call    dx_opreg
    jmp     .finish
.not_rex2_own:
    mov     al, [rel dx_op]
    ; 9B + an x87 instruction (prefixes, a REX between): objdump writes one
    ; instruction - fnstsw / fnstcw / fnclex ... without the "n"
    cmp     byte [rel dx_map], 1
    jne     .not_wait
    cmp     al, 0x9B
    jne     .not_wait
    call    dx_fwait_combo
    test    eax, eax
    jz      .not_wait
    mov     byte [rel dx_fwait], 1
    mov     byte [rel dx_rex], 0           ; (a REX before the 9B: none)
    jmp     .prefix                        ; (what follows: its prefixes, opcode)
.not_wait:

    ; ---- SSE family: 0F / 0F 38 / 0F 3A chosen by the mandatory prefix ----
    cmp     byte [rel dx_map], 2
    jb      .integer
    xor     ecx, ecx                       ; prefix index: none
    cmp     byte [rel dx_p66], 0
    je      .pfx_f3
    mov     ecx, 1                         ; 66
.pfx_f3:
    cmp     byte [rel dx_rep], 0
    je      .pfx_f2
    mov     ecx, 2                         ; F3
.pfx_f2:
    cmp     byte [rel dx_repne], 0
    je      .pfx_done
    mov     ecx, 3                         ; F2
.pfx_done:
    lea     rdx, [rel x86_sse0f]
    cmp     byte [rel dx_map], 3
    jb      .sse_tab
    lea     rdx, [rel x86_sse38]
    je      .sse_tab
    lea     rdx, [rel x86_sse3a]
.sse_tab:
    cmp     byte [rel dx_map], 2           ; (F2 0F 00 is lkgs with /6 alone:
    jne     .sse_tab_go                    ; else sldt & co., the F2 a repnz)
    cmp     byte [rel dx_op], 0
    jne     .sse_tab_go
    push    rcx
    push    rdx
    call    dx_peek
    pop     rdx
    pop     rcx
    shr     eax, 3
    and     eax, 7
    cmp     eax, 6
    jne     .sse_none_map
    cmp     byte [rel dx_mode], 64         ; (64-bit mode's alone; there /6 is
    jne     .sse_none_map                  ; objdump's prefix table - a 66 / F3
    cmp     ecx, 3                         ; taken, no instruction)
    jne     .undef_sel
.sse_tab_go:
    movzx   eax, byte [rel dx_op]
    lea     eax, [rax*4 + rcx]
    lea     rdx, [rdx + rax*4]
    movzx   eax, word [rdx]
    cmp     eax, 0xFFFF
    je      .sse_none
    mov     r12, rdx
    mov     r13d, eax
    ; the prefix is part of the opcode now, not operand size / rep (16-bit
    ; mode: still the operand size's - 32 bits, as the CPU reads it)
    cmp     ecx, 1
    jne     .sse_c2
    dec     byte [rel dx_n66]
    cmp     byte [rel dx_mode], 16
    je      .sse_c2
    mov     byte [rel dx_p66], 0
.sse_c2:
    cmp     ecx, 2
    jne     .sse_c3
    mov     byte [rel dx_rep], 0
.sse_c3:
    cmp     ecx, 3
    jne     .sse_c4
    mov     byte [rel dx_repne], 0
.sse_c4:
    mov     [rel dx_ssepfx], cl            ; (the prefix that chose the entry)
    cmp     ecx, 1
    jne     .sse_c4_named
    cmp     byte [rel dx_map], 2           ; (0F 71-73's groups: a 66 named
    jne     .sse_c4_66                     ; where none is the member)
    movzx   eax, byte [rel dx_op]
    sub     eax, 0x71
    cmp     eax, 2
    jbe     .sse_c4_named
.sse_c4_66:
    mov     byte [rel dx_sel66], 1         ; (a 66 the opcode's: never unused)
.sse_c4_named:
    mov     al, [r12 + 2]
    mov     [rel dx_form], al
    mov     al, [r12 + 3]
    test    al, SF_INT
    jz      .sse_vec
    and     al, 0x7F                       ; integer instruction: FL_* flags
    mov     [rel dx_flags], al
    jmp     .entry_loaded
.sse_vec:
    mov     [rel dx_sflags], al
    or      byte [rel dx_sflags], 0x80     ; mark "SSE" even with no flags set
    test    al, SF_MMX
    jz      .sse_xmm
    mov     byte [rel dx_vclass], 0
.sse_xmm:
    mov     byte [rel dx_flags], FL_MODRM
    cmp     byte [rel dx_form], FM_NONE
    jne     .entry_loaded
    mov     byte [rel dx_flags], 0         ; emms: no ModRM
    jmp     .entry_loaded
.sse_none:
    cmp     byte [rel dx_map], 2           ; (0F 1E: a hint nop with any other
    jne     .sse_not1e                     ; prefix - "repnz nop eax"; 0F 00
    cmp     byte [rel dx_op], 0x1E         ; its group's; 0F 71-73 a prefix
    je      .sse_none_map                  ; named, "repz (bad)")
    cmp     byte [rel dx_op], 0
    je      .sse_none_map
    movzx   eax, byte [rel dx_op]
    sub     eax, 0x71
    cmp     eax, 2
    ja      .sse_not1e
    push    rcx
    push    rdx
    call    dx_peek
    pop     rdx
    pop     rcx
    mov     edx, eax
    shr     edx, 3                         ; (the prefix taken if ModRM.reg is
    and     edx, 7                         ; one of the group's -
    movzx   eax, byte [rel dx_op]          ; 71 / 72: 2 4 6, 73: 2 3 6 7)
    mov     ecx, 0x54
    cmp     eax, 0x73
    jne     .shift_regs
    mov     ecx, 0xCC
.shift_regs:
    bt      ecx, edx
    jc      .undef_sel
    jmp     .sse_none_map
.sse_not1e:
    ; the prefix chose a column of this opcode's and it is empty: does the
    ; opcode have any (objdump's prefix table)? F3 / F2: "(bad)", the prefix
    ; taken; 66: the no-prefix instruction with 66 its operand size, if it
    ; has operands (bsf ax, ax), else "(bad)" (66 0F 09)
    mov     r8, rdx
    lea     rax, [rcx * 4]
    sub     r8, rax                        ; the opcode's four entries
    xor     r9d, r9d
.sse_any:
    cmp     word [r8 + r9 * 4], 0xFFFF
    je      .sse_any_next
    cmp     byte [rel dx_mode], 64
    je      .sse_some
    mov     al, [r8 + r9 * 4 + 3]          ; (an integer entry of 64-bit mode
    and     al, SF_INT | FL_O64            ; alone: none here)
    cmp     al, SF_INT | FL_O64
    jne     .sse_some
.sse_any_next:
    inc     r9d
    cmp     r9d, 4
    jb      .sse_any
    jmp     .sse_none_66
.sse_some:
    cmp     ecx, 2
    jae     .undef_sel
    cmp     ecx, 1
    jne     .sse_none_66
    cmp     byte [rel dx_map], 2
    je      .sse_some_0f
    cmp     byte [rel dx_map], 3           ; (0F 38 F0 / F1: movbe's, below)
    jne     .undef_sel
    movzx   eax, byte [rel dx_op]
    cmp     eax, 0x8B                      ; (movrs r16)
    je      .sse_none_66
    and     eax, 0xFE
    cmp     eax, 0xF0
    jne     .undef_sel
    jmp     .sse_none_66
.sse_some_0f:
    movzx   eax, byte [rel dx_op]
    lea     r9, [rel x86_map2]
    cmp     word [r9 + rax * 4], 0xFFFF
    je      .undef_sel
    cmp     byte [r9 + rax * 4 + 2], FM_NONE
    je      .undef_sel
    jmp     .sse_none_map
.undef_sel:
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1         ; (x86_decode: 66 is no unused one)
    jmp     .undef
.sse_none_66:
    ; 66 and no entry for it: an integer instruction's own no-prefix one,
    ; the 66 its operand size (movbe cx, [rax])
    cmp     ecx, 1
    jne     .sse_none_map
    cmp     byte [rel dx_mode], 64         ; (not 64-bit mode's alone, outside it)
    je      .sse_66_try
    test    byte [rdx - 4 + 3], FL_O64
    jnz     .sse_none_map
.sse_66_try:
    cmp     byte [rel dx_map], 3
    jb      .sse_none_map
    movzx   eax, word [rdx - 4]
    cmp     eax, 0xFFFF
    je      .sse_none_map
    test    byte [rdx - 4 + 3], SF_INT
    jz      .sse_none_map
    lea     r12, [rdx - 4]
    mov     r13d, eax
    jmp     .sse_c4
.sse_none_map:
    cmp     byte [rel dx_map], 2
    jne     .undef                         ; nothing else in 0F 38 / 0F 3A
    lea     r12, [rel x86_map2]
.integer:
    movzx   eax, byte [rel dx_op]
    lea     r12, [r12 + rax*4]             ; r12 = table entry
    movzx   r13d, word [r12]               ; r13 = name offset / group
    cmp     r13d, 0xFFFF
    jne     .defined
    cmp     byte [rel dx_map], 2
    jae     .undef
    jmp     .bad
.defined:
    mov     al, [r12 + 2]
    mov     [rel dx_form], al
    cmp     al, FM_X87
    je      .x87
    mov     al, [r12 + 3]
    mov     [rel dx_flags], al
.entry_loaded:
    test    byte [rel dx_flags], FL_O64
    jz      .o64_ok
    cmp     byte [rel dx_mode], 64
    jne     .undef
.o64_ok:

    ; ---- ModRM (and SIB / displacement) ----
    test    byte [rel dx_flags], FL_MODRM
    jz      .no_modrm
    call    dx_modrm_decode
    cmp     byte [rel dx_fail], 0
    jne     .bad
.no_modrm:

    ; ---- groups: the mnemonic comes from ModRM.reg ----
    test    byte [rel dx_flags], FL_GROUP
    jz      .named
    ; 0F 18 / 0F 1C with a register: no prefetch / cldemote, a hint nop
    ; (and 0F 1C /0 with a 66 / F3 / F2: cldemote has none)
    cmp     byte [rel dx_map], 2
    jne     .not_hint_reg
    movzx   eax, byte [rel dx_op]
    cmp     byte [rel dx_mod], 3
    jne     .hint_pfx
    cmp     eax, 0x18
    je      .hint_reg
    cmp     eax, 0x1C
    jne     .not_hint_reg
    jmp     .hint_reg
.hint_pfx:
    cmp     eax, 0x1C
    jne     .not_hint_reg
    test    byte [rel dx_regno], 7
    jnz     .not_hint_reg
    mov     al, [rel dx_p66]
    or      al, [rel dx_rep]
    or      al, [rel dx_repne]
    jz      .not_hint_reg
.hint_reg:
    mov     r13d, [rel x86_group_gnop]
    and     byte [rel dx_flags], ~FL_BYTE
    mov     byte [rel dx_form], FM_Ev
.not_hint_reg:
    lea     rax, [rel x86_groups]
    shl     r13d, 3                        ; group * 8
    movzx   ecx, byte [rel dx_regno]
    and     ecx, 7
    add     r13d, ecx
    lea     r12, [rax + r13*4]             ; group entry
    movzx   r13d, word [r12]
    cmp     r13d, 0xFFFF
    jne     .group_named
    mov     rax, [rel dx_after_modrm]      ; no member: "(bad)" through the
    dec     rax                            ; opcode (objdump's, the ModRM not
    mov     [rel dx_cur], rax              ; taken)
    jmp     .undef
.group_named:
    mov     al, [r12 + 2]
    test    al, al
    jz      .keep_form
    mov     [rel dx_form], al
.keep_form:
    mov     al, [r12 + 3]
    or      [rel dx_flags], al
.named:
    lea     rax, [rel x86_names]
    add     rax, r13
    mov     [rel dx_mnem], rax
    ; 0F 18 /6 /7 with memory, 64-bit mode: objdump's prefix table - an F3 /
    ; F2 taken (the hint nop), none with [rip + disp] prefetchit1 / 0
    cmp     byte [rel dx_map], 2
    jne     .not_pfit
    cmp     byte [rel dx_op], 0x18
    jne     .not_pfit
    cmp     byte [rel dx_mod], 3
    je      .not_pfit
    cmp     byte [rel dx_mode], 64
    jne     .not_pfit
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 6
    jb      .not_pfit
    mov     cl, [rel dx_rep]
    or      cl, [rel dx_repne]
    jz      .pfit_np
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    jmp     .not_pfit
.pfit_np:
    cmp     byte [rel dx_p66], 0
    jne     .not_pfit
    cmp     byte [rel dx_base], RIP_REG
    jne     .not_pfit
    lea     rcx, [rel s_prefetchit1]
    cmp     eax, 6
    je      .pfit_put
    lea     rcx, [rel s_prefetchit0]
.pfit_put:
    mov     [rel dx_mnem], rcx
    mov     byte [rel dx_form], FM_Mb
.not_pfit:

    ; ---- operand size ----
    mov     al, 8
    test    byte [rel dx_flags], FL_BYTE
    jnz     .osz
    cmp     byte [rel dx_mode], 64
    je      .osz_64
    mov     al, 32
    test    byte [rel dx_flags], FL_X32
    jnz     .osz
    jmp     .osz_std
.osz_64:
    mov     al, 64
    test    byte [rel dx_rex], 8           ; REX.W
    jnz     .osz
    test    byte [rel dx_flags], FL_F64
    jz      .osz_d64
    cmp     byte [rel dx_p66], 0           ; (66: 16 bits, as objdump reads it -
    je      .osz                           ; "call cx")
    mov     al, 16
    jmp     .osz
.osz_d64:
    test    byte [rel dx_flags], FL_D64
    jz      .osz_std
    cmp     byte [rel dx_p66], 0
    je      .osz
    mov     al, 16
    jmp     .osz
.osz_std:
    mov     al, 32                         ; (16-bit mode: 16, 32 with 66)
    cmp     byte [rel dx_mode], 16
    jne     .osz_66
    mov     al, 16
.osz_66:
    cmp     byte [rel dx_p66], 0
    je      .osz
    xor     al, 32 ^ 16
.osz:
    mov     [rel dx_osz], al

    ; ---- redundant 66 prefixes: objdump writes "data16 " for each ----
.data16:
    movzx   eax, byte [rel dx_n66]
    test    eax, eax
    jz      .rexw
    test    byte [rel dx_flags], FL_BYTE   ; (a byte operation: no 66 sets it)
    jnz     .d16_loop
    test    byte [rel dx_rex], 8
    jz      .d16_keep
    cmp     byte [rel dx_sflags], 0
    je      .d16_loop                      ; REX.W overrides 66: each is data16
.d16_keep:
    dec     eax                            ; one 66 sets the operand size
.d16_loop:
    test    eax, eax
    jz      .rexw
    mov     byte [rel dx_d16w], 1          ; (x86_decode: one written)
    push    rax
    lea     rsi, [rel s_data16]
    cmp     byte [rel dx_mode], 16
    jne     .d16_put
    lea     rsi, [rel s_u66_32]            ; (16-bit mode: data32)
.d16_put:
    call    dx_puts
    pop     rax
    dec     eax
    jmp     .d16_loop
    ; (REX.W on a near call / jmp: x86_decode's trials find it unused)
.rexw:
.data16_done:

    ; ---- one-byte map prefixes objdump spells out ----
    cmp     byte [rel dx_map], 1
    jne     .spelled_done
    ; F3 C3 / F3 C2: "repz ret"
    movzx   eax, byte [rel dx_op]
    and     eax, 0xFE
    cmp     eax, 0xC2
    jne     .notrack
    cmp     byte [rel dx_rep], 0
    je      .spelled_done
    mov     byte [rel dx_rep], 0
    lea     rsi, [rel s_repz]
    call    dx_puts
    jmp     .spelled_done
.notrack:
    ; 3E on an indirect call/jmp (FF /2, FF /4): "notrack"
    cmp     byte [rel dx_op], 0xFF
    jne     .spelled_done
    cmp     byte [rel dx_seg], 'd'
    jne     .spelled_done
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    cmp     eax, 2
    je      .notrack_put
    cmp     eax, 4
    jne     .spelled_done
.notrack_put:
    mov     byte [rel dx_seg], 0
    lea     rsi, [rel s_notrack]
    call    dx_puts
.spelled_done:

    ; ---- 0F 1F nop with a segment prefix: objdump writes "cs nop ..." ----
    cmp     byte [rel dx_map], 2
    jne     .operands
    cmp     byte [rel dx_op], 0x1F
    jne     .operands
    movzx   esi, byte [rel dx_seg]
    test    esi, esi
    jz      .operands
    mov     byte [rel dx_seg], 0
    call    dx_putc                        ; 'c' (etc.) + "s "
    mov     esi, 's'
    call    dx_putc
    mov     esi, ' '
    call    dx_putc

    ; ---- operands ----
.operands:
    call    dx_operands
    cmp     byte [rel dx_fail], 0
    je      .finish
    cmp     byte [rel dx_undef], 0         ; (a form found no instruction:
    je      .bad                           ; "(bad)", the bytes it took)
    mov     byte [rel dx_fail], 0
    mov     rcx, [rel dx_fb]
    mov     rax, [rel dx_textpos]
    mov     [rcx + FMTBUF_len], rax
    mov     rdx, [rcx + FMTBUF_buf]
    mov     byte [rdx + rax], 0
    jmp     .undef

    ; ---- x87 floating point: ModRM, then its own tables ----
.x87:
    call    dx_modrm_decode
    cmp     byte [rel dx_fail], 0
    jne     .bad
    cmp     byte [rel dx_mod], 3           ; (a register form: no instruction
    jne     .x87_go                        ; is "(bad)" with the ModRM)
    mov     rcx, [rel dx_cur]
    mov     [rel dx_opend], rcx
.x87_go:
    call    dx_x87
    cmp     byte [rel dx_fail], 0
    jne     .bad
    jmp     .finish

    ; ---- k-mask instructions: rax = x86_kops entry ----
.kop:
    mov     r12, rax
    call    dx_modrm_decode
    cmp     byte [rel dx_fail], 0
    jne     .bad
    call    dx_kop
    cmp     byte [rel dx_fail], 0
    jne     .bad
    jmp     .finish

    ; ---- VEX 0F AE: vldmxcsr / vstmxcsr (memory, /2 and /3) ----
.vex_ae:
    cmp     byte [rel dx_vl], 0
    jne     .bad
    call    dx_modrm_decode
    cmp     byte [rel dx_fail], 0
    jne     .bad
    cmp     byte [rel dx_mod], 3
    je      .bad
    movzx   eax, byte [rel dx_regno]
    and     eax, 7
    lea     rsi, [rel s_vldmxcsr]
    cmp     eax, 2
    je      .vex_ae_put
    lea     rsi, [rel s_vstmxcsr]
    cmp     eax, 3
    jne     .bad
.vex_ae_put:
    mov     [rel dx_mnem], rsi
    mov     esi, 1
    call    dx_mnemonic
    mov     edi, 32
    call    dx_mem
    cmp     byte [rel dx_fail], 0
    jne     .bad

    jmp     .finish                        ; (vldmxcsr / vstmxcsr above)

    ; ---- EVEX map 4 (APX): x86/apx.inc ----
.vex7:
    call    dx_rd8                         ; W vvvv L pp (rd8 keeps edx)
    call    dx_vex7
    cmp     byte [rel dx_fail], 0
    jne     .bad
    jmp     .finish
.evex4:
    call    dx_evex4
    cmp     byte [rel dx_fail], 0
    jne     .bad
    jmp     .finish

.finish:
    mov     rax, [rel dx_cur]
    sub     rax, [rel dx_start]            ; length
    ; [rip + disp]: the address it names, for objdump's "# 13 <sym+0x7>"
    cmp     byte [rel dx_ripmem], 0
    je      .rip_done
    mov     rcx, [rel dx_addr]
    add     rcx, rax
    add     rcx, [rel dx_disp]
    cmp     byte [rel dx_p67], 0
    je      .rip_put
    mov     ecx, ecx                       ; ([eip + disp])
.rip_put:
    mov     [rel x86_rip_target], rcx
.rip_done:
    mov     rdx, [rel dx_target]
    jmp     .ret

.undef:
    ; no instruction: objdump's "(bad)" takes the prefixes, 0F (38 / 3A) and
    ; the opcode byte (and names the prefixes: "repz (bad)" - not a VEX /
    ; EVEX one's, read with its opcode)
    cmp     byte [rel dx_vexpath], 0
    je      .undef_named
    cmp     byte [rel dx_vraw], 0          ; (a VEX one with vvvv 0: its prefixes
    je      .undef_named                   ; named)
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
    mov     byte [rel dx_vpfx], 0
.undef_named:
    cmp     byte [rel dx_map], 2           ; (0F AE: a prefix's group - it was
    jne     .undef_put                     ; taken)
    cmp     byte [rel dx_op], 0xAE
    jne     .undef_put
    cmp     byte [rel dx_pgnamed], 0       ; (a fence's ModRM.rm: named)
    jne     .undef_put
    mov     byte [rel dx_rep], 0
    mov     byte [rel dx_repne], 0
    mov     byte [rel dx_sel66], 1
.undef_put:
    mov     byte [rel dx_map], 0           ; (no xacquire / xrelease)
    mov     byte [rel dx_ripmem], 0
    lea     rax, [rel s_bad_opnd]
    mov     [rel dx_mnem], rax
    xor     esi, esi
    call    dx_mnemonic
    movzx   eax, byte [rel dx_badk]        ; (" {k2}": the EVEX that is none)
    test    eax, eax
    jz      .undef_k_none
    push    rax
    push    rax
    lea     rsi, [rel s_space_k]
    call    dx_puts
    pop     rax
    pop     rax
    lea     esi, [rax + '0']
    call    dx_putc
    mov     esi, '}'
    call    dx_putc
.undef_k_none:
    jmp     .finish
.bad:
    cmp     byte [rel dx_trunc], 0
    jne     .bad_real
    mov     rax, [rel dx_opend]
    test    rax, rax
    jz      .bad_real
    ; an opcode was read and no instruction is there: "(bad)" through it
    mov     [rel dx_cur], rax
    mov     qword [rel dx_opend], 0
    mov     byte [rel dx_fail], 0
    mov     rcx, [rel dx_fb]
    mov     rax, [rel dx_textpos]
    mov     [rcx + FMTBUF_len], rax
    mov     rdx, [rcx + FMTBUF_buf]
    mov     byte [rdx + rax], 0
    jmp     .undef
.bad_real:
    ; undo any partial text
    mov     rcx, [rel dx_fb]
    mov     rax, [rel dx_textpos]
    mov     [rcx + FMTBUF_len], rax
    mov     rdx, [rcx + FMTBUF_buf]
    mov     byte [rdx + rax], 0
    xor     eax, eax
    mov     rdx, -1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
