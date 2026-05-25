;
; ============================================================================
; File        : include/arch/amd64.s
; Project     : utasm
; Description : AMD64 Architecture Constants and Register IDs.
; ============================================================================
;

; ---- 64-bit GPRs -------------------------
%define REG_RAX                0
%define REG_RCX                1
%define REG_RDX                2
%define REG_RBX                3
%define REG_RSP                4
%define REG_RBP                5
%define REG_RSI                6
%define REG_RDI                7
%define REG_R8                 8
%define REG_R9                 9
%define REG_R10                10
%define REG_R11                11
%define REG_R12                12
%define REG_R13                13
%define REG_R14                14
%define REG_R15                15

; ---- SIMD Registers (XMM/YMM/ZMM) --------
%define REG_ZMM0               80
%define REG_ZMM1               81
%define REG_ZMM2               82
%define REG_ZMM3               83
%define REG_ZMM4               84
%define REG_ZMM5               85
%define REG_ZMM6               86
%define REG_ZMM7               87
%assign i 8
%rep 24
    %define REG_ZMM%[i] 80+%[i]
    %assign i i+1
%endrep

; ---- Segment Registers -------------------
%define REG_CS                 24
%define REG_DS                 25
%define REG_ES                 26
%define REG_FS                 27
%define REG_GS                 28
%define REG_SS                 29

; ---- Control Registers (CR0-CR15) --------
%assign i 0
%rep 16
    %define REG_CR%[i] 32+%[i]
    %assign i i+1
%endrep

; ---- Debug Registers (DR0-DR15) ----------
%assign i 0
%rep 16
    %define REG_DR%[i] 48+%[i]
    %assign i i+1
%endrep

; ---- FPU Stack (ST0-ST7) -----------------
%assign i 0
%rep 8
    %define REG_ST%[i] 64+%[i]
    %assign i i+1
%endrep

; ---- Opmask Registers (K0-K7) ------------
%assign i 0
%rep 8
    %define REG_K%[i] 72+%[i]
    %assign i i+1
%endrep

; ---- Mnemonic IDs (AMD64 Specific) -------
%define OP_MOV                 1
%define OP_ADD                 2
%define OP_SUB                 3
%define OP_RET                 4
%define OP_JMP                 5
%define OP_CALL                6
%define OP_CMP                 7
%define OP_XOR                 8
%define OP_LEA                 9
%define OP_PUSH                10
%define OP_POP                 11
%define OP_INC                 12
%define OP_DEC                 13
%define OP_NOP                 14
%define OP_INT3                15
%define OP_SYSCALL             16
%define ID_RVC_NOP             3066
%define ID_VADDPS              3000
%define ID_VMOVUPS              3001
%define ID_VXORPS              3002

;*
; * [def_mnc]
; ;
%macro def_mnc 3
    mnc_ent %1, %2, %3
%endmacro
