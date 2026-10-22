; ============================================================================
; File        : src/tools/disasm/x86/tables.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : register names and the decoder's strings
; ============================================================================


[SECTION .rodata]
; register names, 8 bytes per slot
rn64:   db "rax",0,0,0,0,0, "rcx",0,0,0,0,0, "rdx",0,0,0,0,0, "rbx",0,0,0,0,0
        db "rsp",0,0,0,0,0, "rbp",0,0,0,0,0, "rsi",0,0,0,0,0, "rdi",0,0,0,0,0
        db "r8",0,0,0,0,0,0, "r9",0,0,0,0,0,0, "r10",0,0,0,0,0, "r11",0,0,0,0,0
        db "r12",0,0,0,0,0, "r13",0,0,0,0,0, "r14",0,0,0,0,0, "r15",0,0,0,0,0
rn32:   db "eax",0,0,0,0,0, "ecx",0,0,0,0,0, "edx",0,0,0,0,0, "ebx",0,0,0,0,0
        db "esp",0,0,0,0,0, "ebp",0,0,0,0,0, "esi",0,0,0,0,0, "edi",0,0,0,0,0
        db "r8d",0,0,0,0,0, "r9d",0,0,0,0,0, "r10d",0,0,0,0, "r11d",0,0,0,0
        db "r12d",0,0,0,0, "r13d",0,0,0,0, "r14d",0,0,0,0, "r15d",0,0,0,0
rn16:   db "ax",0,0,0,0,0,0, "cx",0,0,0,0,0,0, "dx",0,0,0,0,0,0, "bx",0,0,0,0,0,0
        db "sp",0,0,0,0,0,0, "bp",0,0,0,0,0,0, "si",0,0,0,0,0,0, "di",0,0,0,0,0,0
        db "r8w",0,0,0,0,0, "r9w",0,0,0,0,0, "r10w",0,0,0,0, "r11w",0,0,0,0
        db "r12w",0,0,0,0, "r13w",0,0,0,0, "r14w",0,0,0,0, "r15w",0,0,0,0
rn8rex: db "al",0,0,0,0,0,0, "cl",0,0,0,0,0,0, "dl",0,0,0,0,0,0, "bl",0,0,0,0,0,0
        db "spl",0,0,0,0,0, "bpl",0,0,0,0,0, "sil",0,0,0,0,0, "dil",0,0,0,0,0
        db "r8b",0,0,0,0,0, "r9b",0,0,0,0,0, "r10b",0,0,0,0, "r11b",0,0,0,0
        db "r12b",0,0,0,0, "r13b",0,0,0,0, "r14b",0,0,0,0, "r15b",0,0,0,0
; APX's r16-r31
rnx64:  db "r16",0,0,0,0,0, "r17",0,0,0,0,0, "r18",0,0,0,0,0, "r19",0,0,0,0,0
        db "r20",0,0,0,0,0, "r21",0,0,0,0,0, "r22",0,0,0,0,0, "r23",0,0,0,0,0
        db "r24",0,0,0,0,0, "r25",0,0,0,0,0, "r26",0,0,0,0,0, "r27",0,0,0,0,0
        db "r28",0,0,0,0,0, "r29",0,0,0,0,0, "r30",0,0,0,0,0, "r31",0,0,0,0,0
rnx32:  db "r16d",0,0,0,0, "r17d",0,0,0,0, "r18d",0,0,0,0, "r19d",0,0,0,0
        db "r20d",0,0,0,0, "r21d",0,0,0,0, "r22d",0,0,0,0, "r23d",0,0,0,0
        db "r24d",0,0,0,0, "r25d",0,0,0,0, "r26d",0,0,0,0, "r27d",0,0,0,0
        db "r28d",0,0,0,0, "r29d",0,0,0,0, "r30d",0,0,0,0, "r31d",0,0,0,0
rnx16:  db "r16w",0,0,0,0, "r17w",0,0,0,0, "r18w",0,0,0,0, "r19w",0,0,0,0
        db "r20w",0,0,0,0, "r21w",0,0,0,0, "r22w",0,0,0,0, "r23w",0,0,0,0
        db "r24w",0,0,0,0, "r25w",0,0,0,0, "r26w",0,0,0,0, "r27w",0,0,0,0
        db "r28w",0,0,0,0, "r29w",0,0,0,0, "r30w",0,0,0,0, "r31w",0,0,0,0
rnx8:   db "r16b",0,0,0,0, "r17b",0,0,0,0, "r18b",0,0,0,0, "r19b",0,0,0,0
        db "r20b",0,0,0,0, "r21b",0,0,0,0, "r22b",0,0,0,0, "r23b",0,0,0,0
        db "r24b",0,0,0,0, "r25b",0,0,0,0, "r26b",0,0,0,0, "r27b",0,0,0,0
        db "r28b",0,0,0,0, "r29b",0,0,0,0, "r30b",0,0,0,0, "r31b",0,0,0,0
rn8leg: db "al",0,0,0,0,0,0, "cl",0,0,0,0,0,0, "dl",0,0,0,0,0,0, "bl",0,0,0,0,0,0
        db "ah",0,0,0,0,0,0, "ch",0,0,0,0,0,0, "dh",0,0,0,0,0,0, "bh",0,0,0,0,0,0
        db "r8b",0,0,0,0,0, "r9b",0,0,0,0,0, "r10b",0,0,0,0, "r11b",0,0,0,0
        db "r12b",0,0,0,0, "r13b",0,0,0,0, "r14b",0,0,0,0, "r15b",0,0,0,0

s_byte:     db "BYTE PTR ", 0
s_word:     db "WORD PTR ", 0
s_dword:    db "DWORD PTR ", 0
s_qword:    db "QWORD PTR ", 0
s_xmmword:  db "XMMWORD PTR ", 0
s_ymmword:  db "YMMWORD PTR ", 0
s_zmmword:  db "ZMMWORD PTR ", 0
s_word_bcst: db "WORD BCST ", 0
s_dword_bcst: db "DWORD BCST ", 0
s_qword_bcst: db "QWORD BCST ", 0
s_zmm:      db "zmm", 0
s_oword:    db "OWORD PTR ", 0
s_cmpxchg8b: db "cmpxchg8b", 0
s_cmpxchg16b: db "cmpxchg16b", 0
s_rdrand:   db "rdrand", 0
; 0F C7 /0-7 with a register: objdump's name of the memory form (then
; "(bad)"), W0 and W1 in 16-byte slots - empty for none
g9_badop_names:
    times 32 db 0
    db "cmpxchg8b", 0, 0, 0, 0, 0, 0, 0, "cmpxchg16b", 0, 0, 0, 0, 0, 0
    times 32 db 0
    db "xrstors", 0, 0, 0, 0, 0, 0, 0, 0, 0, "xrstors64", 0, 0, 0, 0, 0, 0, 0
    db "xsavec", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "xsavec64", 0, 0, 0, 0, 0, 0, 0, 0
    db "xsaves", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "xsaves64", 0, 0, 0, 0, 0, 0, 0, 0
    times 64 db 0
s_rdseed:   db "rdseed", 0
s_vldmxcsr: db "vldmxcsr", 0
s_vstmxcsr: db "vstmxcsr", 0
s_kopen:    db "{k", 0
s_zmask:    db "{z}", 0
s_sae:      db "{sae}", 0
s_rounds:   db "{rn-sae}", 0, 0, 0, 0, 0, 0, 0, 0
            db "{rd-sae}", 0, 0, 0, 0, 0, 0, 0, 0
            db "{ru-sae}", 0, 0, 0, 0, 0, 0, 0, 0
            db "{rz-sae}", 0, 0, 0, 0, 0, 0, 0, 0
s_tbyte:    db "TBYTE PTR ", 0
s_st:       db "st", 0
s_commast:  db ",st", 0
s_data16:   db "data16 ", 0
s_mm:       db "mm", 0
s_xmm:      db "xmm", 0
s_ymm:      db "ymm", 0
s_vzeroall: db "vzeroall", 0
s_commaxmm0: db ",xmm0", 0
s_movhlps:  db "movhlps", 0
s_movlhps:  db "movlhps", 0
s_endbr64:  db "endbr64", 0
s_endbr32:  db "endbr32", 0
s_pclmul_ll: db "pclmullqlqdq", 0
s_pclmul_hl: db "pclmulhqlqdq", 0
s_pclmul_lh: db "pclmullqhqdq", 0
s_pclmul_hh: db "pclmulhqhqdq", 0
; cmpps predicates 0-7, 8-byte slots
; the 32 vcmp predicates (legacy SSE uses the first 8), 16 bytes each
xop_preds:  db "lt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "le", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "gt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ge", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "eq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "neq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "false", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "true", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
cmp_preds:  db "eq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "lt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "le", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "unord", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "neq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nlt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nle", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ord", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "eq_uq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nge", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ngt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "false", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "neq_oq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ge", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "gt", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "true", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "eq_os", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "lt_oq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "le_oq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "unord_s", 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "neq_us", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nlt_uq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nle_uq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ord_s", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "eq_us", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "nge_uq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ngt_uq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "false_os", 0, 0, 0, 0, 0, 0, 0, 0
            db "neq_os", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "ge_oq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "gt_oq", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            db "true_us", 0, 0, 0, 0, 0, 0, 0, 0, 0
s_ds:       db "ds:", 0
s_rip:      db "rip", 0
s_eip:      db "eip", 0
s_lock:     db "lock ", 0
s_rep:      db "rep ", 0
s_repz:     db "repz ", 0
s_repnz:    db "repnz ", 0
s_bnd:      db "bnd ", 0
s_notrack:  db "notrack ", 0
s_u66:      db "data16 ", 0
s_u67:      db "addr32 ", 0
s_u66_32:   db "data32 ", 0
s_u67_16:   db "addr16 ", 0
s_eiz:      db "eiz", 0
s_ucs:      db "cs ", 0
s_uss:      db "ss ", 0
s_uds:      db "ds ", 0
s_ues:      db "es ", 0
s_ufs:      db "fs ", 0
s_ugs:      db "gs ", 0
s_rexbits:  db "WRXB"
s_comma1:   db ",1", 0
s_commacl:  db ",cl", 0
s_movabs:   db "movabs", 0
s_jmpabs:   db "jmpabs", 0
s_tmm:      db "tmm", 0
s_rstorssp: db "rstorssp", 0
s_vexp:     db "{vex} ", 0
s_1to:      db "{1to", 0
s_8087_only: db "(8087 only)", 0
s_bad_opnd: db "(bad)", 0
s_slash_bad: db "/(bad)", 0
; the SSE forms whose VEX form has no vvvv operand without SF_NDS
vex_novvvv_forms: db FM_VW, FM_WV, FM_VWI, FM_VE, FM_EV, FM_GW, FM_GU, FM_VM, FM_MV
                  db FM_EVI, FM_GUI, FM_XBCAST, FM_XEXT, FM_XZERO, 0xFF
; 0F 01 register forms of 64-bit mode alone: prefix (0 none, 1 66, 2 F3,
; 3 F2), ModRM; FF ends it
; 0F 01's register forms objdump reads through a prefix table: a prefix
; with no entry of its own there - "(bad)", the prefix taken
g7_pfxtab:  db 0xC6, 0xC7, 0xCA, 0xCC, 0xCD, 0xCE, 0xCF, 0xD9, 0xE8, 0xE9
            db 0xEA, 0xEC, 0xED, 0xEE, 0xEF, 0xFA, 0xFB, 0xFD, 0xFE, 0xFF, 0
g7_64only:  db 0, 0xC7, 1, 0xCD, 1, 0xCE, 1, 0xCF, 2, 0xC6, 2, 0xCA
            db 2, 0xEC, 2, 0xED, 2, 0xEE, 2, 0xEF, 2, 0xFD, 2, 0xFE, 2, 0xFF
            db 3, 0xC6, 3, 0xCA, 3, 0xFD, 3, 0xFE, 0xFF
s_hint_nop: db "nop", 0
s_prefetchit0: db "prefetchit0", 0
s_prefetchit1: db "prefetchit1", 0
s_287_only: db "(287 only)", 0
s_bnd_reg:  db "bnd", 0
; 3DNow!'s opcodes (the imm8 after the operands) and names, 12-byte slots
d3now_names:
    db 0x0C, "pi2fw", 0, 0, 0, 0, 0, 0
    db 0x0D, "pi2fd", 0, 0, 0, 0, 0, 0
    db 0x1C, "pf2iw", 0, 0, 0, 0, 0, 0
    db 0x1D, "pf2id", 0, 0, 0, 0, 0, 0
    db 0x8A, "pfnacc", 0, 0, 0, 0, 0
    db 0x8E, "pfpnacc", 0, 0, 0, 0
    db 0x90, "pfcmpge", 0, 0, 0, 0
    db 0x94, "pfmin", 0, 0, 0, 0, 0, 0
    db 0x96, "pfrcp", 0, 0, 0, 0, 0, 0
    db 0x97, "pfrsqrt", 0, 0, 0, 0
    db 0x9A, "pfsub", 0, 0, 0, 0, 0, 0
    db 0x9E, "pfadd", 0, 0, 0, 0, 0, 0
    db 0xA0, "pfcmpgt", 0, 0, 0, 0
    db 0xA4, "pfmax", 0, 0, 0, 0, 0, 0
    db 0xA6, "pfrcpit1", 0, 0, 0
    db 0xA7, "pfrsqit1", 0, 0, 0
    db 0xAA, "pfsubr", 0, 0, 0, 0, 0
    db 0xAE, "pfacc", 0, 0, 0, 0, 0, 0
    db 0xB0, "pfcmpeq", 0, 0, 0, 0
    db 0xB4, "pfmul", 0, 0, 0, 0, 0, 0
    db 0xB6, "pfrcpit2", 0, 0, 0
    db 0xB7, "pmulhrw", 0, 0, 0, 0
    db 0xBB, "pswapd", 0, 0, 0, 0, 0
    db 0xBF, "pavgusb", 0, 0, 0, 0
    db 0
s_xlat_rbx: db "[rbx]", 0
s_xlat_ebx: db "[ebx]", 0
s_xlat_bx:  db "[bx]", 0
s_es:       db "es:", 0
s_cr:       db "cr", 0
s_xacquire: db "xacquire ", 0
s_sm2:      db "sm2", 0
s_space_k:  db " {k", 0
s_jecxz:    db "jecxz", 0
s_jcxz:     db "jcxz", 0
s_xrelease: db "xrelease ", 0
s_rex2_open: db "{rex2 0x", 0
s_loadiwkey: db "loadiwkey", 0
kl_wide_names: db "aesencwide128kl", 0, "aesdecwide128kl", 0, "aesencwide256kl", 0, "aesdecwide256kl", 0
s_dr:       db "dr", 0
s_tr:       db "tr", 0
s_di:       db "[di]", 0
s_si:       db "[si]", 0
; 16-bit addressing by ModRM.rm: base / index registers (NO_REG: none)
dx_m16_base:  db 3, 3, 5, 5, 6, 7, 5, 3
dx_m16_index: db 6, 7, 6, 7, NO_REG, NO_REG, NO_REG, NO_REG
s_rdi:      db "[rdi]", 0
s_edi:      db "[edi]", 0
s_rsi:      db "[rsi]", 0
s_esi:      db "[esi]", 0
sreg_names: db "es", 0, 0, "cs", 0, 0, "ss", 0, 0, "ds", 0, 0, "fs", 0, 0, "gs", 0, 0
s_fword:    db "FWORD PTR ", 0
s_rdsspd:   db "rdsspd", 0
s_rdsspq:   db "rdsspq", 0
s_riz:      db "riz", 0
s_nf:       db "{nf} ", 0
s_pushp:    db "pushp", 0
s_popp:     db "popp", 0
s_pause:    db "pause", 0
s_xchg:     db "xchg", 0
s_cbw:      db "cbw", 0
s_cwde:     db "cwde", 0
s_cdqe:     db "cdqe", 0
s_cwd:      db "cwd", 0
s_cdq:      db "cdq", 0
s_cqo:      db "cqo", 0
s_rexw_nop: db "rex.W nop", 0

; 0F 01 with a memory operand, by ModRM.reg (16-byte slots) and operand size
g7_mem_names:  db "sgdt",0,0,0,0,0,0,0,0,0,0,0,0,  "sidt",0,0,0,0,0,0,0,0,0,0,0,0
               db "lgdt",0,0,0,0,0,0,0,0,0,0,0,0,  "lidt",0,0,0,0,0,0,0,0,0,0,0,0
               db "smsw",0,0,0,0,0,0,0,0,0,0,0,0,  "(bad)",0,0,0,0,0,0,0,0,0,0,0
               db "lmsw",0,0,0,0,0,0,0,0,0,0,0,0,  "invlpg",0,0,0,0,0,0,0,0,0,0
g7_mem_sizes:  db 0, 0, 0, 0, 16, 0xFF, 16, 8
; 0F 01 with a register form: the whole ModRM byte, the mandatory prefix
; (0 none, 1 66, 2 F3, 3 F2), the name (16-byte slots) - the prefixed ones
; first: a prefix finds its own, else the plain one (and is printed)
g7_reg_names:
               db 0xC6, 3, "rdmsrlist", 0, 0, 0, 0, 0
               db 0xC6, 2, "wrmsrlist", 0, 0, 0, 0, 0
               db 0xCA, 3, "erets", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCA, 2, "eretu", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCC, 1, "tdcall", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCD, 1, "seamret", 0, 0, 0, 0, 0, 0, 0
               db 0xCE, 1, "seamops", 0, 0, 0, 0, 0, 0, 0
               db 0xCF, 1, "seamcall", 0, 0, 0, 0, 0, 0
               db 0xD9, 2, "vmgexit", 0, 0, 0, 0, 0, 0, 0
               db 0xD9, 3, "vmgexit", 0, 0, 0, 0, 0, 0, 0
               db 0xE8, 2, "setssbsy", 0, 0, 0, 0, 0, 0
               db 0xE8, 3, "xsusldtrk", 0, 0, 0, 0, 0
               db 0xE9, 3, "xresldtrk", 0, 0, 0, 0, 0
               db 0xEA, 2, "saveprevssp", 0, 0, 0
               db 0xEC, 2, "uiret", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xED, 2, "testui", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xEE, 2, "clui", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xEF, 2, "stui", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFA, 2, "mcommit", 0, 0, 0, 0, 0, 0, 0
               db 0xFD, 2, "rmpquery", 0, 0, 0, 0, 0, 0
               db 0xFE, 2, "rmpadjust", 0, 0, 0, 0, 0
               db 0xFE, 3, "rmpupdate", 0, 0, 0, 0, 0
               db 0xFD, 3, "rmpread", 0, 0, 0, 0, 0, 0, 0
               db 0xFF, 2, "psmash", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFF, 3, "pvalidate", 0, 0, 0, 0, 0
               db 0xC0, 0, "enclv", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xC1, 0, "vmcall", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xC2, 0, "vmlaunch", 0, 0, 0, 0, 0, 0
               db 0xC3, 0, "vmresume", 0, 0, 0, 0, 0, 0
               db 0xC4, 0, "vmxoff", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xC5, 0, "pconfig", 0, 0, 0, 0, 0, 0, 0
               db 0xC6, 0, "wrmsrns", 0, 0, 0, 0, 0, 0, 0
               db 0xC7, 0, "pbndkb", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xC8, 0, "monitor", 0, 0, 0, 0, 0, 0, 0
               db 0xC9, 0, "mwait", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCA, 0, "clac", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCB, 0, "stac", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xCF, 0, "encls", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD0, 0, "xgetbv", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD1, 0, "xsetbv", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD4, 0, "vmfunc", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD5, 0, "xend", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD6, 0, "xtest", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD7, 0, "enclu", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD8, 0, "vmrun", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xD9, 0, "vmmcall", 0, 0, 0, 0, 0, 0, 0
               db 0xDA, 0, "vmload", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xDB, 0, "vmsave", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xDC, 0, "stgi", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xDD, 0, "clgi", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xDE, 0, "skinit", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xDF, 0, "invlpga", 0, 0, 0, 0, 0, 0, 0
               db 0xE8, 0, "serialize", 0, 0, 0, 0, 0
               db 0xEE, 0, "rdpkru", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xEF, 0, "wrpkru", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xF8, 0, "swapgs", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xF9, 0, "rdtscp", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFA, 0, "monitorx", 0, 0, 0, 0, 0, 0
               db 0xFB, 0, "mwaitx", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFC, 0, "clzero", 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFD, 0, "rdpru", 0, 0, 0, 0, 0, 0, 0, 0, 0
               db 0xFE, 0, "invlpgb", 0, 0, 0, 0, 0, 0, 0
               db 0xFF, 0, "tlbsync", 0, 0, 0, 0, 0, 0, 0
               db 0
; 0F AE with a memory operand, and the register forms /5 /6 /7
; 0F AE / 0F C7: dx_pgrp's entries (24 bytes): ModRM.reg, 1 for a
; register (0 memory), the mandatory prefix (0 none, 1 66, 2 F3, 3 F2), W (0
; either, 1 W0, 2 W1), the operands (PG_*), the memory's size in bytes (0:
; none written), flags (1 64-bit mode's alone; 2 none with a prefix not its
; own - objdump's prefix table, the prefix taken; 4 ModRM.rm 0 alone), the
; name - the prefixed ones first
pg_0fae:
    db 6, 0, 1, 0, 1, 1, 0, 0, "clwb", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 0, 2, 0, 1, 8, 0, 0, "clrssbsy", 0, 0, 0, 0, 0, 0, 0, 0
    db 7, 0, 1, 0, 1, 1, 0, 0, "clflushopt", 0, 0, 0, 0, 0, 0
    db 4, 0, 2, 0, 5, 0, 0, 0, "ptwrite", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 1, 2, 0, 2, 0, 1, 0, "rdfsbase", 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 1, 2, 0, 2, 0, 1, 0, "rdgsbase", 0, 0, 0, 0, 0, 0, 0, 0
    db 2, 1, 2, 0, 2, 0, 1, 0, "wrfsbase", 0, 0, 0, 0, 0, 0, 0, 0
    db 3, 1, 2, 0, 2, 0, 1, 0, "wrgsbase", 0, 0, 0, 0, 0, 0, 0, 0
    db 4, 1, 2, 0, 5, 0, 0, 0, "ptwrite", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 1, 2, 1, 4, 0, 0, 0, "incsspd", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 1, 2, 2, 6, 0, 0, 0, "incsspq", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 1, 2, 0, 3, 0, 0, 0, "umonitor", 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 1, 1, 0, 4, 0, 0, 0, "tpause", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 1, 3, 0, 4, 0, 0, 0, "umwait", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 1, 1, 0, 0, 0, "fxsave", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 2, 1, 0, 0, 0, "fxsave64", 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 0, 0, 1, 1, 0, 0, 0, "fxrstor", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 1, 0, 0, 2, 1, 0, 0, 0, "fxrstor64", 0, 0, 0, 0, 0, 0, 0
    db 2, 0, 0, 0, 1, 4, 0, 0, "ldmxcsr", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 3, 0, 0, 0, 1, 4, 0, 0, "stmxcsr", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 4, 0, 0, 1, 1, 0, 2, 0, "xsave", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 4, 0, 0, 2, 1, 0, 2, 0, "xsave64", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 0, 0, 1, 1, 0, 2, 0, "xrstor", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 0, 0, 2, 1, 0, 2, 0, "xrstor64", 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 0, 0, 1, 1, 0, 2, 0, "xsaveopt", 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 0, 0, 2, 1, 0, 2, 0, "xsaveopt64", 0, 0, 0, 0, 0, 0
    db 7, 0, 0, 0, 1, 1, 2, 0, "clflush", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 1, 0, 0, 0, 0, 2, 0, "lfence", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 1, 0, 0, 0, 0, 4, 0, "mfence", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 7, 1, 0, 0, 0, 0, 4, 0, "sfence", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0xFF
pg_0fc7:
    db 6, 0, 1, 0, 1, 8, 0, 0, "vmclear", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 0, 2, 0, 1, 8, 0, 0, "vmxon", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 7, 1, 2, 0, 6, 0, 0, 0, "rdpid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 1, 2, 0, 6, 0, 1, 0, "senduipi", 0, 0, 0, 0, 0, 0, 0, 0
    db 3, 0, 0, 1, 1, 0, 0, 0, "xrstors", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 3, 0, 0, 2, 1, 0, 0, 0, "xrstors64", 0, 0, 0, 0, 0, 0, 0
    db 4, 0, 0, 1, 1, 0, 0, 0, "xsavec", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 4, 0, 0, 2, 1, 0, 0, 0, "xsavec64", 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 0, 0, 1, 1, 0, 0, 0, "xsaves", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 5, 0, 0, 2, 1, 0, 0, 0, "xsaves64", 0, 0, 0, 0, 0, 0, 0, 0
    db 6, 0, 0, 0, 1, 8, 2, 0, "vmptrld", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 7, 0, 0, 0, 1, 8, 0, 0, "vmptrst", 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0xFF
gae_mem_names: db "fxsave",0,0,0,0,0,0,0,0,0,0,  "fxrstor",0,0,0,0,0,0,0,0,0
               db "ldmxcsr",0,0,0,0,0,0,0,0,0,  "stmxcsr",0,0,0,0,0,0,0,0,0
               db "xsave",0,0,0,0,0,0,0,0,0,0,0,  "xrstor",0,0,0,0,0,0,0,0,0,0
               db "xsaveopt",0,0,0,0,0,0,0,0,  "clflush",0,0,0,0,0,0,0,0,0
gae_mem_sizes: db 0, 0, 32, 32, 0, 0, 0, 8
gae_reg_names: db "lfence",0,0, "mfence",0,0, "sfence",0,0

%include "src/tools/disasm/gen/x86_tables.inc"

[SECTION .text]
%include "src/tools/disasm/x86/apx.inc"
