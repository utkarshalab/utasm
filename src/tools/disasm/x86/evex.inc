; ============================================================================
; File        : src/tools/disasm/x86/evex.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : shapes, VSIB, EVEX operands, mask registers
; ============================================================================


; ============================================================================
; EVEX (AVX-512)
; ============================================================================

; dx_shape_find: r12 = the entry of key ecx in the table rdx (x86_evex's
; layout), or 0
dx_shape_find:
    mov     r12, rdx
.sf_scan:
    mov     eax, [r12]
    test    eax, eax
    jz      .sf_none
    cmp     eax, ecx
    je      .sf_mod
.sf_next:
    add     r12, 16
    jmp     .sf_scan
.sf_mod:
    ; an entry for a register ModRM.rm only, or memory only (EV2_REG /
    ; EV2_MEM): the other is another entry
    test    byte [r12 + 15], EV2_REG | EV2_MEM
    jz      .sf_ret
    push    rcx
    call    dx_peek
    pop     rcx
    cmp     byte [rel dx_fail], 0
    jne     .sf_none
    and     eax, 0xC0
    cmp     eax, 0xC0
    je      .sf_is_reg
    test    byte [r12 + 15], EV2_MEM
    jz      .sf_next
    jmp     .sf_ret
.sf_is_reg:
    test    byte [r12 + 15], EV2_REG
    jz      .sf_next
    jmp     .sf_ret
.sf_none:
    xor     r12d, r12d
.sf_ret:
    ret

; dx_shape_vsib: the entry r12's shape has a VSIB operand (S: its index as
; wide as the vector, s: half of it, at least xmm) - dx_vsib its class, for
; dx_modrm_decode to read the index as a vector register
dx_shape_vsib:
    lea     rcx, [r12 + 8]
.sv_next:
    movzx   eax, byte [rcx]
    test    eax, eax
    jz      .sv_ret
    inc     rcx
    cmp     eax, 'S'
    je      .sv_full
    cmp     eax, 's'
    jne     .sv_next
    movzx   eax, byte [rel dx_vl]
    test    eax, eax
    jnz     .sv_set
    inc     eax
    jmp     .sv_set
.sv_full:
    movzx   eax, byte [rel dx_vl]
    inc     eax
.sv_set:
    mov     [rel dx_vsib], al
.sv_ret:
    ret

; ---- dx_pgrp ------------------------------
; A group whose members differ by register / memory, mandatory prefix and W
; (0F AE, 0F C7, F3 0F 1E): rsi = its entries (pg_*). The one for this
; ModRM.reg, mod, prefix (one that is its own, else one of none and the
; prefix printed), W; printed. EAX = 1, or 0 when there is none.
%define PG_NONE     0           ; no operands
%define PG_MEM      1           ; memory (the entry's size)
%define PG_REGW     2           ; a register of 32 / 64 bits by W
%define PG_REGA     3           ; a register of the address size (67: 32)
%define PG_REG32    4
%define PG_RMW      5           ; a register or memory of 32 / 64 bits by W
%define PG_REG64    6
dx_pgrp:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     byte [rel dx_pgnone], 0
    xor     edx, edx                       ; the prefix: 66 1, F3 2, F2 3
    cmp     byte [rel dx_p66], 0
    je      .pg_f3
    mov     edx, 1
.pg_f3:
    cmp     byte [rel dx_rep], 0
    je      .pg_f2
    mov     edx, 2
.pg_f2:
    cmp     byte [rel dx_repne], 0
    je      .pg_pfx
    mov     edx, 3
.pg_pfx:
    movzx   ecx, byte [rel dx_regno]
    and     ecx, 7
    xor     r8d, r8d
    cmp     byte [rel dx_mod], 3
    jne     .pg_mod
    mov     r8d, 1
.pg_mod:
    mov     r9d, 1                         ; W: 1 W0, 2 W1
    test    byte [rel dx_rex], 8
    jz      .pg_w
    mov     r9d, 2
.pg_w:
    xor     r13d, r13d                     ; pass 0: its own prefix; 1: none
.pg_pass:
    mov     rbx, r12
.pg_scan:
    movzx   eax, byte [rbx]
    cmp     eax, 0xFF
    je      .pg_next_pass
    cmp     eax, ecx
    jne     .pg_skip
    cmp     [rbx + 1], r8b
    jne     .pg_skip
    movzx   eax, byte [rbx + 2]
    test    r13d, r13d
    jnz     .pg_none_pfx
    test    edx, edx
    jz      .pg_skip                       ; (no prefix: pass 1)
    cmp     eax, edx
    jne     .pg_skip
    jmp     .pg_w_ok
.pg_none_pfx:
    test    eax, eax
    jnz     .pg_skip
.pg_w_ok:
    test    byte [rbx + 6], 2              ; (a prefix not its own: none, the
    jz      .pg_pt_ok                      ; prefix taken)
    test    r13d, r13d
    jz      .pg_pt_ok
    test    edx, edx
    jz      .pg_pt_ok
    mov     byte [rel dx_pgnone], 1
    jmp     .pg_skip
.pg_pt_ok:
    test    byte [rbx + 6], 4              ; (ModRM.rm 0 alone: else none, the
    jz      .pg_rm_ok                      ; prefixes named)
    test    byte [rel dx_modrm], 7
    jz      .pg_rm_ok
    mov     byte [rel dx_pgnone], 1
    mov     byte [rel dx_pgnamed], 1
    jmp     .pg_skip
.pg_rm_ok:
    test    byte [rbx + 6], 1              ; (64-bit mode's alone: fsgsbase)
    jz      .pg_mode_ok
    cmp     byte [rel dx_mode], 64
    jne     .pg_skip
.pg_mode_ok:
    movzx   eax, byte [rbx + 3]
    test    eax, eax
    jz      .pg_found
    cmp     eax, r9d
    je      .pg_found
.pg_skip:
    add     rbx, 24
    jmp     .pg_scan
.pg_next_pass:
    inc     r13d
    cmp     r13d, 2
    jb      .pg_pass
    xor     eax, eax
    jmp     .pg_ret
.pg_found:
    ; its own prefix: not printed
    test    r13d, r13d
    jnz     .pg_print
    cmp     edx, 1
    jne     .pg_own_rep
    mov     byte [rel dx_p66], 0
    dec     byte [rel dx_n66]
.pg_own_rep:
    cmp     edx, 2
    jne     .pg_own_repne
    mov     byte [rel dx_rep], 0
.pg_own_repne:
    cmp     edx, 3
    jne     .pg_print
    mov     byte [rel dx_repne], 0
.pg_print:
    lea     rax, [rbx + 8]
    mov     [rel dx_mnem], rax
    movzx   eax, byte [rbx + 4]
    xor     esi, esi
    cmp     eax, PG_NONE
    je      .pg_mn
    mov     esi, 1
.pg_mn:
    push    rax
    push    rax
    call    dx_mnemonic
    pop     rax
    pop     rax
    cmp     eax, PG_NONE
    je      .pg_done
    cmp     eax, PG_MEM
    jne     .pg_regs
    movzx   edi, byte [rbx + 5]
    shl     edi, 3
    call    dx_mem
    jmp     .pg_done
.pg_regs:
    mov     edi, 32
    cmp     eax, PG_REG32
    je      .pg_reg
    mov     edi, 64
    cmp     eax, PG_REG64
    jne     .pg_not64
    cmp     byte [rel dx_mode], 64
    je      .pg_reg
    mov     edi, 32
    jmp     .pg_reg
.pg_not64:
    cmp     eax, PG_REGA
    jne     .pg_by_w
    movzx   edi, byte [rel dx_asz]
    jmp     .pg_reg
.pg_by_w:
    mov     edi, 32                        ; PG_REGW / PG_RMW: 32, 64 with W
    test    byte [rel dx_rex], 8
    jz      .pg_rmw
    mov     edi, 64
.pg_rmw:
    cmp     eax, PG_RMW
    jne     .pg_reg
    call    dx_rm                          ; (a register or memory at that size)
    jmp     .pg_done
.pg_reg:
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
.pg_done:
    mov     eax, 1
.pg_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; dx_tmmreg: "tmmN", N = esi & 7
dx_tmmreg:
    and     esi, 7
    push    rsi
    lea     rsi, [rel s_tmm]
    call    dx_puts
    pop     rsi
    add     esi, '0'
    jmp     dx_putc

; dx_evex_bytes: eax = size in bytes of the memory operand (not a broadcast)
dx_evex_bytes:
    movzx   ecx, byte [rel dx_vl]
    test    ecx, ecx
    jnz     .not_dup
    test    byte [rel dx_eflags2], EV2_DUP
    jz      .not_dup
    mov     eax, 8                         ; (vmovddup xmm, m64)
    ret
.not_dup:
    mov     edx, 16
    shl     edx, cl                        ; vector length in bytes
    movzx   eax, byte [rel dx_emsize]
    test    eax, eax
    jz      .full
    cmp     eax, 4
    ja      .part
    lea     ecx, [rax - 1]                 ; b/w/d/q: 1/2/4/8
    mov     eax, 1
    shl     eax, cl
    ret
.part:
    cmp     eax, 8
    je      .x
    cmp     eax, 9
    je      .y
    lea     ecx, [rax - 4]                 ; half/quarter/eighth of the vector
    shr     edx, cl
.full:
    mov     eax, edx
    ret
.x:
    mov     eax, 16
    ret
.y:
    mov     eax, 32
    ret

; dx_evex_elem: eax = element size in bytes (8 with W, else 4; 2 for
; FP16 / BF16's, EV2_E16)
dx_evex_elem:
    mov     eax, 1
    test    byte [rel dx_eflags2], EV2_E8
    jnz     .ret
    mov     eax, 2
    test    byte [rel dx_eflags2], EV2_E16
    jnz     .ret
    mov     eax, 4
    test    byte [rel dx_rex], 8
    jz      .ret
    mov     eax, 8
.ret:
    ret

; ---- dx_vvvv_unused ------------------------
; A generated VEX / EVEX entry (r12) whose shape has no vvvv operand (H h
; J u) needs vvvv 1111: ZF clear when it is not - no instruction (#UD),
; objdump's "(bad)" through the opcode.
dx_vvvv_unused:
    lea     rsi, [r12 + 8]
    mov     ecx, 7
.scan:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .unused
    cmp     eax, 'H'
    je      .used
    cmp     eax, 'h'
    je      .used
    cmp     eax, 'J'
    je      .used
    cmp     eax, 'u'
    je      .used
    inc     rsi
    dec     ecx
    jnz     .scan
.unused:
    movzx   eax, byte [rel dx_vvvv]
    and     eax, 15                        ; (V' is not looked at: objdump's)
    ret
.used:
    xor     eax, eax                       ; (ZF set)
    ret

; ---- dx_bad_marks --------------------------
; What objdump marks as one the CPU refuses (#UD) in a VEX / EVEX entry
; r12: dx_markbad (bit n: "/(bad)" after operand n) and dx_repbad (the
; operand written "(bad)", 0xFF none).
;   - a VEX gather (V S H): destination / index / mask, each pair that is
;     one register marks both;
;   - an EVEX gather (V S) with no mask: its destination;
;   - vmovw with a mask: after it;
;   - vf(c)maddc / vf(c)mulc ph / sh whose destination is a source: it.
dx_bad_marks:
    lea     rsi, [r12 + 8]                 ; shape: V / Y / X, then S / s
    movzx   eax, byte [rsi + 1]
    cmp     eax, 'S'
    je      .g_mem
    cmp     eax, 's'
    jne     .not_gather
.g_mem:
    movzx   eax, byte [rsi]
    cmp     eax, 'V'
    je      .g_dest
    cmp     eax, 'Y'
    je      .g_dest
    cmp     eax, 'X'
    jne     .not_gather
.g_dest:
    movzx   eax, byte [rel dx_regno]
    movzx   ecx, byte [rel dx_reghi]
    or      eax, ecx                       ; destination
    movzx   ecx, byte [rel dx_index]       ; index
    cmp     byte [rel dx_evex], 0
    jne     .evex_gather
    movzx   edx, byte [rsi + 2]
    cmp     edx, 'H'
    je      .g_mask
    cmp     edx, 'h'
    jne     .ret
.g_mask:
    movzx   edx, byte [rel dx_vvvv]        ; mask
    xor     r8d, r8d
    cmp     eax, ecx
    jne     .g1
    or      r8d, 3
.g1:
    cmp     eax, edx
    jne     .g2
    or      r8d, 5
.g2:
    cmp     ecx, edx
    jne     .g3
    or      r8d, 6
.g3:
    mov     [rel dx_markbad], r8b
    ret
.evex_gather:
    cmp     byte [rel dx_eaaa], 0
    jne     .ret
    mov     byte [rel dx_markbad], 1
    ret
.not_gather:
    mov     rdi, [rel dx_mnem]
    ; vmovw: no masking
    cmp     dword [rdi], "vmov"
    jne     .not_vmovw
    cmp     word [rdi + 4], "w"            ; ("w", 0)
    jne     .not_vmovw
    cmp     byte [rel dx_eaaa], 0
    je      .ret
    mov     byte [rel dx_markbad], 1
    ret
.not_vmovw:
    ; the complex FP16 multiplies: vf[c]maddc / vf[c]mulc + ph / sh
    cmp     word [rdi], "vf"
    jne     .ret
    lea     rdx, [rdi + 2]
    cmp     byte [rdx], 'c'
    jne     .cx_op
    inc     rdx
.cx_op:
    cmp     dword [rdx], "madd"
    jne     .cx_mul
    add     rdx, 4
    jmp     .cx_c
.cx_mul:
    cmp     word [rdx], "mu"
    jne     .ret
    cmp     byte [rdx + 2], 'l'
    jne     .ret
    add     rdx, 3
.cx_c:
    cmp     byte [rdx], 'c'
    jne     .ret
    cmp     byte [rdx + 2], 'h'
    jne     .ret
    cmp     byte [rdx + 3], 0
    jne     .ret
    movzx   eax, byte [rel dx_regno]
    movzx   ecx, byte [rel dx_reghi]
    or      eax, ecx
    movzx   ecx, byte [rel dx_vvvv]
    cmp     eax, ecx
    je      .cx_bad
    cmp     byte [rel dx_mod], 3
    jne     .ret
    movzx   ecx, byte [rel dx_rmreg]
    movzx   edx, byte [rel dx_rmhi]
    or      ecx, edx
    cmp     eax, ecx
    jne     .ret
.cx_bad:
    mov     byte [rel dx_repbad], 0
.ret:
    ret

; ---- dx_evex_operands --------------------
; Prints the mnemonic and the operands the entry's shape string lists (see
; x86_evex in scripts/gen/gen_x86_tables.py), with {kN}{z} after the first one.
; r12 = the x86_evex entry.
dx_evex_operands:
    push    rbx
    push    r14
    ; vpclmulqdq: the four known selectors have names
    cmp     byte [rel dx_map], 4
    jne     .preds
    cmp     byte [rel dx_op], 0x44
    jne     .preds
    call    dx_peek
    cmp     byte [rel dx_fail], 0
    jne     .done
    cmp     eax, 2                         ; (objdump: 02 / 03 as 10 / 11)
    jne     .pcl0_3
    mov     eax, 0x10
.pcl0_3:
    cmp     eax, 3
    jne     .pcl0_n
    mov     eax, 0x11
.pcl0_n:
    lea     rsi, [rel s_pclmul_ll]
    cmp     eax, 0x00
    je      .pclmul
    lea     rsi, [rel s_pclmul_hl]
    cmp     eax, 0x01
    je      .pclmul
    lea     rsi, [rel s_pclmul_lh]
    cmp     eax, 0x10
    je      .pclmul
    lea     rsi, [rel s_pclmul_hh]
    cmp     eax, 0x11
    jne     .named
.pclmul:
    mov     [rel dx_mnem], rsi
    mov     byte [rel dx_vpfx], 1          ; "v" + pclmul...
    mov     byte [rel dx_epred], 1         ; the selector is in the name
    jmp     .named
.preds:
    lea     r8, [rel cmp_preds]
    ; XOP's vpcom: imm8 0-7 named (lt le gt ge eq neq false true), after
    ; "vpcom"
    test    byte [rel dx_eflags2], EV2_PCOM
    jz      .not_pcom
    call    dx_peek
    cmp     byte [rel dx_fail], 0
    jne     .done
    cmp     eax, 8
    jae     .named
    lea     r8, [rel xop_preds]
    mov     ecx, 5
    jmp     .pred
.not_pcom:
    ; vpcmp / vcmp: a known predicate goes into the name
    test    byte [rel dx_eflags], EV_PINT | EV_PFP
    jz      .named
    call    dx_peek
    cmp     byte [rel dx_fail], 0
    jne     .done
    test    byte [rel dx_eflags], EV_PFP
    jnz     .pfp
    cmp     eax, 3                         ; vpcmp: 0-2 and 4-6 have names
    je      .named
    cmp     eax, 7
    jae     .named
    mov     ecx, 5                         ; after "vpcmp"
    jmp     .pred
.pfp:
    cmp     eax, 32
    jae     .named
    mov     ecx, 4                         ; after "vcmp"
    test    byte [rel dx_eflags2], EV2_PFPBF
    jz      .pred
    mov     ecx, 6                         ; after "vcmpbf" (objdump's vcmpbfeq16)
.pred:
    mov     byte [rel dx_epred], 1
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
.p_head:
    mov     dl, [rsi]
    mov     [rdi], dl
    inc     rsi
    inc     rdi
    dec     ecx
    jnz     .p_head
    mov     rdx, r8                        ; (cmp_preds, xop_preds)
    shl     eax, 4
    add     rdx, rax
.p_pred:
    mov     al, [rdx]
    test    al, al
    jz      .p_tail
    mov     [rdi], al
    inc     rdx
    inc     rdi
    jmp     .p_pred
.p_tail:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .p_tail
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.named:
    call    dx_bad_marks
    mov     esi, 1
    call    dx_mnemonic
    lea     rbx, [r12 + 8]                 ; shape
    xor     r14d, r14d                     ; operands printed so far
.next:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .done
    inc     rbx
    cmp     eax, 'H'
    jne     .not_h
    test    byte [rel dx_eflags], EV_MOVS
    jz      .not_h
    cmp     byte [rel dx_mod], 3
    jne     .next                          ; vmovss/vmovsd with memory: no H
.not_h:
    cmp     eax, 'I'
    jne     .sep
    cmp     byte [rel dx_epred], 0
    je      .sep
    call    dx_rd8                         ; the predicate, already named
    jmp     .next
.sep:
    test    r14d, r14d
    jz      .first
    push    rax
    call    dx_sep
    pop     rax
.first:
    movzx   ecx, byte [rel dx_repbad]
    cmp     ecx, r14d
    jne     .operand_put
    push    rax
    push    rax
    lea     rsi, [rel s_bad_opnd]          ; (a destination it may not be)
    call    dx_puts
    pop     rax
    pop     rax
    jmp     .operand_done
.operand_put:
    call    .operand
.operand_done:
    cmp     byte [rel dx_fail], 0
    jne     .done
    inc     r14d
    cmp     r14d, 1
    jne     .marked
    call    .mask
.marked:
    lea     ecx, [r14 - 1]
    movzx   eax, byte [rel dx_markbad]
    bt      eax, ecx
    jnc     .next
    lea     rsi, [rel s_slash_bad]
    call    dx_puts
    jmp     .next

.done:
    pop     r14
    pop     rbx
    ret

; one operand; eax = its letter
.operand:
    cmp     eax, 'V'
    je      .o_V
    cmp     eax, 'H'
    je      .o_H
    cmp     eax, 'W'
    je      .o_W
    cmp     eax, 'Y'
    je      .o_Y
    cmp     eax, 'X'
    je      .o_X
    cmp     eax, 'S'
    je      .o_S
    cmp     eax, 's'
    je      .o_S
    cmp     eax, 'L'
    je      .o_L
    cmp     eax, 'h'
    je      .o_h
    cmp     eax, 'T'
    je      .o_T
    cmp     eax, 't'
    je      .o_t
    cmp     eax, 'u'
    je      .o_u
    cmp     eax, 'J'
    je      .o_J
    cmp     eax, 'M'
    je      .o_M
    cmp     eax, 'Z'
    je      .o_Z
    cmp     eax, 'E'
    je      .o_E
    cmp     eax, 'G'
    je      .o_G
    cmp     eax, 'K'
    je      .o_K
    cmp     eax, 'k'
    je      .o_k
    cmp     eax, 'I'
    je      .o_I
.o_fail:
    mov     byte [rel dx_fail], 1
    ret
.o_V:
    call    .main_class
    movzx   esi, byte [rel dx_regno]
    movzx   eax, byte [rel dx_reghi]
    or      esi, eax
    jmp     dx_vecreg_c
.o_Y:
    movzx   edi, byte [rel dx_vl]          ; half the vector length, at least xmm
    test    edi, edi
    jnz     .y_class
    mov     edi, 1
.y_class:
    movzx   esi, byte [rel dx_regno]
    movzx   eax, byte [rel dx_reghi]
    or      esi, eax
    jmp     dx_vecreg_c
.o_h:                                      ; vvvv at half the length (a gather's mask)
    movzx   edi, byte [rel dx_vl]
    test    edi, edi
    jnz     .h_class
    mov     edi, 1
.h_class:
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_vecreg_c
.o_L:                                      ; FMA4 / XOP: a register in imm8[7:4]
    call    dx_rd8
    mov     esi, eax
    shr     esi, 4
    call    .main_class
    jmp     dx_vecreg_c
.o_T:                                      ; tiles: from ModRM.reg, .rm, vvvv
    movzx   esi, byte [rel dx_regno]
    jmp     dx_tmmreg
.o_t:
    cmp     byte [rel dx_mod], 3
    jne     .o_fail
    movzx   esi, byte [rel dx_rmreg]
    jmp     dx_tmmreg
.o_u:
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_tmmreg
.o_J:                                      ; a general register in vvvv
    call    .gpr_size
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_reg
.o_Z:                                      ; an imm32 (as objdump: unsigned)
    call    dx_rd32
    mov     esi, eax
    jmp     dx_hex
.o_M:                                      ; memory, no size written - or an
    cmp     byte [rel dx_mod], 3           ; EVEX entry's fixed one (v4fmaddps'
    je      .o_fail                        ; m128)
    xor     edi, edi
    cmp     byte [rel dx_evex], 0
    je      dx_mem
    cmp     byte [rel dx_emsize], 0
    je      dx_mem
    call    dx_evex_bytes
    lea     edi, [eax * 8]
    jmp     dx_mem
.o_S:                                      ; VSIB memory: one element
    call    dx_evex_elem
    lea     edi, [eax * 8]
    jmp     dx_mem
.o_X:                                      ; xmm whatever the length
    mov     edi, 1
    movzx   esi, byte [rel dx_regno]
    movzx   eax, byte [rel dx_reghi]
    or      esi, eax
    jmp     dx_vecreg_c
.o_H:
    call    .main_class
    movzx   esi, byte [rel dx_vvvv]
    jmp     dx_vecreg_c
.o_W:
    cmp     byte [rel dx_mod], 3
    jne     .memory
    call    dx_evex_bytes                  ; register as wide as the memory form
    mov     edi, 1
    cmp     eax, 32
    jb      .w_reg
    mov     edi, 2
    je      .w_reg
    mov     edi, 3
.w_reg:
    movzx   esi, byte [rel dx_rmreg]
    movzx   eax, byte [rel dx_rmhi]
    or      esi, eax
    call    dx_vecreg_c
    jmp     .round
.o_E:
    cmp     byte [rel dx_mod], 3
    jne     .memory
    call    .gpr_size
    ; a fixed size (lwpval r64, r/m32): the entry's memory size, d / q
    cmp     byte [rel dx_emsize], 3
    jne     .e_q
    mov     edi, 32
.e_q:
    cmp     byte [rel dx_emsize], 4
    jne     .e_size
    mov     edi, 64
.e_size:
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .round
.o_G:
    call    .gpr_size
    movzx   esi, byte [rel dx_regno]
    jmp     dx_reg
.o_K:
    movzx   esi, byte [rel dx_regno]
    jmp     dx_kreg
.o_k:
    cmp     byte [rel dx_mod], 3
    jne     .o_fail
    movzx   esi, byte [rel dx_rmreg]
    jmp     dx_kreg
.o_I:
    call    dx_rd8
    mov     rsi, rax
    jmp     dx_hex

.memory:
    cmp     byte [rel dx_eb], 0
    je      .m_plain
    call    dx_evex_elem                   ; "DWORD BCST [...]"
    mov     edi, 0x120
    cmp     eax, 8
    jne     .m_bw
    mov     edi, 0x140
    jmp     .m_put
.m_bw:
    cmp     eax, 2
    jne     .m_put
    mov     edi, 0x110                     ; (WORD BCST: FP16 / BF16)
    jmp     .m_put
.m_plain:
    call    dx_evex_bytes
    mov     edi, eax
    shl     edi, 3
.m_put:
    cmp     byte [rel dx_eb], 0
    je      dx_mem
    call    dx_mem
    ; a broadcast to a narrower destination (vcvtpd2dq xmm), or a mask
    ; (vfpclassps k): objdump says how many, "{1to4}"
    movzx   eax, byte [r12 + 8]
    cmp     byte [r12 + 9], 'H'            ; (a second source says the
    je      .m_ret                         ; length: vcvtbiasph2bf8)
    cmp     eax, 'Y'
    jne     .m_notY
    cmp     byte [rel dx_vl], 2            ; (a zmm's half is a ymm: said)
    jne     .m_count
    jmp     .m_ret
.m_notY:
    cmp     eax, 'X'
    je      .m_count
    cmp     eax, 'K'
    jne     .m_ret
    cmp     byte [r12 + 9], 'W'            ; (a mask and the memory alone:
    jne     .m_ret                         ; vfpclass - a compare's H says it)
.m_count:
    call    dx_evex_elem
    mov     ecx, eax
    movzx   eax, byte [rel dx_vl]
    mov     edx, 16
    push    rcx
    mov     cl, al
    shl     edx, cl                        ; the vector's bytes
    pop     rcx
    mov     eax, edx
    xor     edx, edx
    div     ecx                            ; elements
    push    rax
    lea     rsi, [rel s_1to]
    call    dx_puts
    pop     rax
    cmp     eax, 10
    jb      .m_one
    push    rax
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    lea     esi, [rax + '0']
    push    rdx
    call    dx_putc
    pop     rdx
    pop     rax
    mov     eax, edx
.m_one:
    lea     esi, [rax + '0']
    call    dx_putc
    mov     esi, '}'
    jmp     dx_putc
.m_ret:
    ret

; {rn-sae} / {sae} after a register source when EVEX.b is set
.round:
    cmp     byte [rel dx_eb], 0
    je      .r_ret
    lea     rsi, [rel s_sae]
    test    byte [rel dx_eflags], EV_ER
    jz      .r_put
    movzx   eax, byte [rel dx_eround]
    shl     eax, 4
    lea     rsi, [rel s_rounds]
    add     rsi, rax
.r_put:
    jmp     dx_puts
.r_ret:
    ret

; edi = register class of V and H
.main_class:
    mov     edi, 1
    test    byte [rel dx_eflags], EV_SCALAR
    jnz     .mc_ret
    movzx   edi, byte [rel dx_vl]
    inc     edi
.mc_ret:
    ret

; edi = 64 with W, else 32
.gpr_size:
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .gs_ret
    cmp     byte [rel dx_mode], 64
    jne     .gs_ret
    mov     edi, 64
.gs_ret:
    ret

; "{kN}" when a mask is applied, "{z}" when zeroing
.mask:
    movzx   eax, byte [rel dx_eaaa]
    test    eax, eax
    jz      .no_k
    lea     rsi, [rel s_kopen]
    call    dx_puts
    movzx   esi, byte [rel dx_eaaa]
    add     esi, '0'
    call    dx_putc
    mov     esi, '}'
    call    dx_putc
.no_k:
    cmp     byte [rel dx_ez], 0
    je      .mask_ret
    lea     rsi, [rel s_zmask]
    jmp     dx_puts
.mask_ret:
    ret

; dx_kreg: mask register k(esi & 7)
dx_kreg:
    and     esi, 7
    push    rsi
    mov     esi, 'k'
    call    dx_putc
    pop     rsi
    add     esi, '0'
    jmp     dx_putc

; ---- k-mask instructions (VEX) -----------

; dx_kop_find: rax = the x86_kops entry for this VEX instruction, or 0.
; ecx = VEX.pp (kept).
dx_kop_find:
    lea     rax, [rel x86_kops]
    mov     edx, ecx
    test    byte [rel dx_rex], 8
    jz      .scan
    or      edx, 4                         ; pp | W << 2
.scan:
    cmp     byte [rax], 0
    je      .none
    movzx   r8d, byte [rax]
    movzx   r9d, byte [rel dx_map]
    cmp     r8d, r9d
    jne     .next
    movzx   r8d, byte [rax + 1]
    movzx   r9d, byte [rel dx_op]
    cmp     r8d, r9d
    jne     .next
    movzx   r8d, byte [rax + 2]
    cmp     r8d, edx
    je      .ret
.next:
    add     rax, 16
    jmp     .scan
.none:
    xor     eax, eax
.ret:
    ret

; dx_kop: prints the k-mask instruction whose x86_kops entry is r12
dx_kop:
    push    rbx
    mov     rbx, r12
    xor     eax, eax                       ; VEX.L: 1 for k,k,k forms, else 0
    cmp     byte [rbx + 3], 1
    jne     .l
    mov     eax, 1
.l:
    cmp     [rel dx_vl], al
    jne     .fail
    lea     rax, [rbx + 4]
    mov     [rel dx_mnem], rax
    movzx   eax, byte [rbx + 3]
    cmp     byte [rel dx_mod], 3
    je      .regs
    cmp     eax, 2                         ; only kmov has memory forms
    je      .go
    cmp     eax, 3
    je      .go
    jmp     .fail
.regs:
    cmp     eax, 3
    je      .fail
.go:
    mov     esi, 1
    call    dx_mnemonic
    movzx   eax, byte [rbx + 3]
    cmp     eax, 3
    je      .s_store
    cmp     eax, 5
    je      .s_gpr_k
    movzx   esi, byte [rel dx_regno]       ; k from ModRM.reg first
    call    dx_kreg
    call    dx_sep
    movzx   eax, byte [rbx + 3]
    cmp     eax, 1
    je      .s_three
    cmp     eax, 4
    je      .s_k_gpr
    cmp     byte [rel dx_mod], 3
    jne     .s_mem
    movzx   esi, byte [rel dx_rmreg]
    call    dx_kreg
    cmp     byte [rbx + 3], 7
    jne     .done
    call    dx_sep
    call    dx_rd8
    mov     rsi, rax
    call    dx_hex
    jmp     .done
.s_three:
    movzx   esi, byte [rel dx_vvvv]
    call    dx_kreg
    call    dx_sep
    movzx   esi, byte [rel dx_rmreg]
    call    dx_kreg
    jmp     .done
.s_k_gpr:
    call    .gpr_size
    movzx   esi, byte [rel dx_rmreg]
    call    dx_reg
    jmp     .done
.s_mem:
    call    .mem_size
    call    dx_mem
    jmp     .done
.s_store:
    call    .mem_size
    call    dx_mem
    call    dx_sep
    movzx   esi, byte [rel dx_regno]
    call    dx_kreg
    jmp     .done
.s_gpr_k:
    call    .gpr_size
    movzx   esi, byte [rel dx_regno]
    call    dx_reg
    call    dx_sep
    movzx   esi, byte [rel dx_rmreg]
    call    dx_kreg
    jmp     .done
.fail:
    mov     byte [rel dx_fail], 1
.done:
    pop     rbx
    ret

; edi = 64 for kmovq, else 32
.gpr_size:
    mov     edi, 32
    test    byte [rel dx_rex], 8
    jz      .gs_ret
    mov     edi, 64
.gs_ret:
    ret

; edi = memory size from the name's last letter (b/w/d/q)
.mem_size:
    lea     rsi, [rbx + 4]
.ms_end:
    cmp     byte [rsi + 1], 0
    je      .ms_last
    inc     rsi
    jmp     .ms_end
.ms_last:
    mov     edi, 8
    cmp     byte [rsi], 'b'
    je      .ms_ret
    mov     edi, 16
    cmp     byte [rsi], 'w'
    je      .ms_ret
    mov     edi, 32
    cmp     byte [rsi], 'd'
    je      .ms_ret
    mov     edi, 64
.ms_ret:
    ret
