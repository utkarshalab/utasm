;
; ============================================================================
; File        : backend/encoder/tables/noops.s
; Project     : utasm
; Description : The instructions that take no operands (amd64).
;
;   Every form of these has none (NASM 3.01's insns.dat, "void" only), so
;   "cpuid eax", "hlt 5", "rdtsc rax" are no instruction - their encoders
;   wrote the opcode and dropped what followed. Not here: those GNU's as
;   takes an implicit register with (clzero, vmrun, vmload, vmsave, skinit,
;   pvalidate, rmpadjust, invlpga: "vmrun rax"), xlat ("xlat [rbx]"), nop
;   (the long one, "nop eax"), ud0 / ud1 (with operands).
; ============================================================================
;

%include "include/macro.inc"

DEFAULT REL

[SECTION .rodata]
align 2
; the mnemonic ids, sorted (backend/isa/amd64.s)
noops_ids:
    dw 1000  ; aaa
    dw 1003  ; aas
    dw 1060  ; cbw
    dw 1061  ; cdq
    dw 1062  ; cdqe
    dw 1063  ; clac
    dw 1064  ; clc
    dw 1065  ; cld
    dw 1069  ; cli
    dw 1071  ; clts
    dw 1072  ; clui
    dw 1074  ; cmc
    dw 1089  ; cpuid
    dw 1090  ; cqo
    dw 1114  ; cwd
    dw 1115  ; cwde
    dw 1116  ; daa
    dw 1117  ; das
    dw 1126  ; emms
    dw 1127  ; encls
    dw 1148  ; enclu
    dw 1158  ; enclv
    dw 1164  ; endbr32
    dw 1165  ; endbr64
    dw 1170  ; f2xm1
    dw 1171  ; fabs
    dw 1176  ; fchs
    dw 1177  ; fclex
    dw 1183  ; fcompp
    dw 1184  ; fcos
    dw 1185  ; fdecstp
    dw 1198  ; fincstp
    dw 1199  ; finit
    dw 1206  ; fld1
    dw 1209  ; fldl2e
    dw 1210  ; fldl2t
    dw 1211  ; fldlg2
    dw 1212  ; fldln2
    dw 1213  ; fldpi
    dw 1214  ; fldz
    dw 1217  ; fnclex
    dw 1218  ; fninit
    dw 1219  ; fnop
    dw 1224  ; fpatan
    dw 1225  ; fprem
    dw 1226  ; fprem1
    dw 1227  ; fptan
    dw 1228  ; frndint
    dw 1231  ; fscale
    dw 1232  ; fsin
    dw 1233  ; fsincos
    dw 1234  ; fsqrt
    dw 1244  ; ftst
    dw 1249  ; fucompp
    dw 1250  ; fwait
    dw 1251  ; fxam
    dw 1255  ; fxtract
    dw 1256  ; fyl2x
    dw 1257  ; fyl2xp1
    dw 1271  ; hlt
    dw 1287  ; int1
    dw 1288  ; int3
    dw 1289  ; into
    dw 1290  ; invd
    dw 1350  ; lahf
    dw 1359  ; lfence
    dw 1385  ; mfence
    dw 1469  ; pause
    dw 1487  ; pconfig
    dw 1598  ; rdpkru
    dw 1599  ; rdpmc
    dw 1604  ; rdtsc
    dw 1605  ; rdtscp
    dw 1619  ; rsm
    dw 1623  ; sahf
    dw 1627  ; saveprevssp
    dw 1634  ; serialize
    dw 1636  ; setssbsy
    dw 1637  ; sfence
    dw 1663  ; stac
    dw 1664  ; stc
    dw 1665  ; std
    dw 1666  ; sti
    dw 1675  ; stui
    dw 1681  ; swapgs
    dw 1682  ; syscall
    dw 1683  ; sysenter
    dw 1684  ; sysexit
    dw 1685  ; sysret
    dw 1692  ; testui
    dw 1695  ; tilerelease
    dw 1703  ; uiret
    dw 2135  ; vzeroall
    dw 2136  ; vzeroupper
    dw 2138  ; wbinvd
    dw 2139  ; wbnoinvd
    dw 2142  ; wrmsr
    dw 2143  ; wrpkru
    dw 2153  ; xend
    dw 2154  ; xgetbv
    dw 2161  ; xresldtrk
    dw 2168  ; xsetbv
    dw 2169  ; xsusldtrk
    dw 2170  ; xtest
    dw 5000  ; vmcall
    dw 5001  ; vmlaunch
    dw 5002  ; vmresume
    dw 5003  ; vmxoff
    dw 5013  ; vmmcall
    dw 5016  ; clgi
    dw 5017  ; stgi
    dw 5600  ; femms
    dw 6064  ; ud2
    dw 6535  ; vmfunc
    dw 7003  ; bb1_reset
    dw 7012  ; cpu_read
    dw 7013  ; cpu_write
    dw 7014  ; dmint
    dw 7015  ; erets
    dw 7016  ; eretu
    dw 7018  ; fdisi
    dw 7019  ; feni
    dw 7021  ; fndisi
    dw 7022  ; fneni
    dw 7023  ; fsetpm
    dw 7024  ; getsec
    dw 7090  ; icebp
    dw 7092  ; int01
    dw 7093  ; int03
    dw 7111  ; loadall
    dw 7112  ; loadall286
    dw 7116  ; montmul
    dw 7123  ; pcommit
    dw 7158  ; rdmsrlist
    dw 7172  ; salc
    dw 7175  ; smintold
    dw 7183  ; ud2a
    dw 7184  ; ud2b
    dw 7352  ; vmgexit
    dw 7486  ; wrmsrlist
    dw 7490  ; xcryptcbc
    dw 7491  ; xcryptcfb
    dw 7492  ; xcryptctr
    dw 7493  ; xcryptecb
    dw 7494  ; xcryptofb
    dw 7499  ; xsha1
    dw 7500  ; xsha256
    dw 7501  ; xstore
    dw 7554  ; bb0_reset
    dw 7555  ; rdm
    dw 7556  ; smint
noops_end:

[SECTION .text]

;*
; * [amd64_takes_none]
; * Purpose: Does the mnemonic ax take no operands in any form?
; * Input  : AX = the mnemonic id
; * Output : ZF = 1: it takes none. Preserves all but rcx, rdx, r8, r9.
; ;
global amd64_takes_none
amd64_takes_none:
    xor     ecx, ecx                       ; lo
    mov     edx, (noops_end - noops_ids) / 2 ; hi (past the last)
    lea     r9, [rel noops_ids]
.search:
    cmp     ecx, edx
    jae     .no
    lea     r8d, [rcx + rdx]
    shr     r8d, 1                         ; mid
    cmp     ax, [r9 + r8*2]
    je      .ret
    jb      .lower
    lea     ecx, [r8 + 1]
    jmp     .search
.lower:
    mov     edx, r8d
    jmp     .search
.no:
    test    esp, esp
.ret:
    ret
