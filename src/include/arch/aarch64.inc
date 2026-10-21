;
; ============================================================================
; File        : include/arch/aarch64.s
; Project     : utasm
; Description : AArch64 Architecture Constants and Register IDs.
;                Aligned with src/isa/aarch64.s IDs.
; ============================================================================
;

; ---- 64-bit GPRs (X0-X30, XZR) -----------
%assign i 0
%rep 31
    %define REG_X%[i]          %[i]
    %assign i i+1
%endrep

%define REG_XZR                31
%define REG_SP                 32

; ---- Shift Types -------------------------
%define SHIFT_LSL              0
%define SHIFT_LSR              1
%define SHIFT_ASR              2
%define SHIFT_ROR              3

; ---- Mnemonic IDs (AArch64 Specific) -----
; These must match the IDs in src/isa/aarch64.s exactly.
%define ID_AARCH64_ABS         2000
%define ID_AARCH64_ADCLB       2001
%define ID_AARCH64_ADCLT       2002
%define ID_AARCH64_ADD         2003
%define ID_AARCH64_ADR         2020
%define ID_AARCH64_ADRP        2650
%define ID_AARCH64_AND         2027
%define ID_AARCH64_ANDS        2029
%define ID_AARCH64_ASR         2031
%define ID_AARCH64_B           2034
%define ID_AARCH64_BIC         2076
%define ID_AARCH64_BICS        2077
%define ID_AARCH64_BL          2080
%define ID_AARCH64_BLR         2081
%define ID_AARCH64_BR          2083
%define ID_AARCH64_CBNZ        2098
%define ID_AARCH64_CBZ         2099
%define ID_AARCH64_CMP         2108
%define ID_AARCH64_EON         2140
%define ID_AARCH64_EOR         2141
%define ID_AARCH64_LDP         2241
%define ID_AARCH64_LDR         2246
%define ID_AARCH64_LSL         2308
%define ID_AARCH64_LSR         2309
%define ID_AARCH64_MOV         2324
%define ID_AARCH64_MOVK        2325
%define ID_AARCH64_MOVN        2326
%define ID_AARCH64_MOVZ        2327
%define ID_AARCH64_NOP         2347
%define ID_AARCH64_ORN         2356
%define ID_AARCH64_ORR         2357
%define ID_AARCH64_RET         2451
%define ID_AARCH64_ROR         2461
%define ID_AARCH64_STP         2549
%define ID_AARCH64_STR         2554
%define ID_AARCH64_SUB         2569
%define ID_AARCH64_SUBS        2571
%define ID_AARCH64_SVC         2576
%define ID_AARCH64_TBNZ        2583
%define ID_AARCH64_TBZ         2584
%define ID_AARCH64_TST         2602
%define ID_AARCH64_MRS         2328
%define ID_AARCH64_MSR         2330
%define ID_AARCH64_DSB         2133
%define ID_AARCH64_DMB         2131
%define ID_AARCH64_ISB         2228
%define ID_AARCH64_WFI         2617
%define ID_AARCH64_HLT         2176
%define ID_AARCH64_UBFM        2605
%define ID_AARCH64_SBFM        2501
%define ID_AARCH64_BFM         2074
%define ID_AARCH64_ADD_V       2800
%define ID_AARCH64_SUB_V       2801
%define ID_AARCH64_AND_V       2802
%define ID_AARCH64_ORR_V       2803
%define ID_AARCH64_EOR_V       2804
%define ID_AARCH64_SXTB        2805
%define ID_AARCH64_SXTH        2806
%define ID_AARCH64_SXTW        2807
%define ID_AARCH64_REV         2808
%define ID_AARCH64_WFI_V       2809
%define ID_AARCH64_MRS_V       2810
%define ID_AARCH64_MSR_V       2811
%define ID_AARCH64_DSB_V       2812
%define ID_AARCH64_ISB_V       2813

; ---- String Operations (Pseudo-Mnemonics) ----
%define ID_AARCH64_MOVSB       3000
%define ID_AARCH64_MOVSW       3001
%define ID_AARCH64_MOVSD       3002
%define ID_AARCH64_MOVSQ       3003
%define ID_AARCH64_STOSB       3010
%define ID_AARCH64_STOSW       3011
%define ID_AARCH64_STOSD       3012
%define ID_AARCH64_STOSQ       3013
%define ID_AARCH64_SCASB       3020
%define ID_AARCH64_SCASW       3021
%define ID_AARCH64_SCASD       3022
%define ID_AARCH64_SCASQ       3023
%define ID_AARCH64_CMPSB       3030
%define ID_AARCH64_CMPSW       3031
%define ID_AARCH64_CMPSD       3032
%define ID_AARCH64_CMPSQ       3033

; ---- Conditional Branches (B.cond) ----
%define ID_AARCH64_BEQ         3100
%define ID_AARCH64_BNE         3101
%define ID_AARCH64_BCS         3102
%define ID_AARCH64_BHS         3102
%define ID_AARCH64_BCC         3103
%define ID_AARCH64_BLO         3103
%define ID_AARCH64_BMI         3104
%define ID_AARCH64_BPL         3105
%define ID_AARCH64_BVS         3106
%define ID_AARCH64_BVC         3107
%define ID_AARCH64_BHI         3108
%define ID_AARCH64_BLS         3109
%define ID_AARCH64_BGE         3110
%define ID_AARCH64_BLT         3111
%define ID_AARCH64_BGT         3112
%define ID_AARCH64_BLE         3113
%define ID_AARCH64_BAL         3114
%define ID_AARCH64_BNV         3115

;*
; * [def_mnc]
; * Purpose: AArch64-specific wrapper for the global mnemonic_entry macro.
; ;
%macro def_mnc 3
    mnc_ent %1, %3, %2
%endmacro
