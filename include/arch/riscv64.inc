;
; ============================================================================
; File        : include/arch/riscv64.s
; Project     : utasm
; Description : RISC-V 64-bit Architecture Constants and Register IDs.
;                Aligned with src/isa/riscv64.s IDs.
; ============================================================================
;

; ---- 64-bit GPRs (x0-x31) ----------------
%assign i 0
%rep 32
    %define REG_X%[i]          %[i]
    %assign i i+1
%endrep

; ---- ABI Names ---------------------------
%define REG_ZERO               0
%define REG_RA                 1
%define REG_SP                 2
%define REG_GP                 3
%define REG_TP                 4
%define REG_T0                 5
%define REG_T1                 6
%define REG_T2                 7
%define REG_S0                 8
%define REG_FP                 8
%define REG_S1                 9
%define REG_A0                 10
%define REG_A1                 11

; ---- Mnemonic IDs (RISC-V Specific) ------
; These must match the IDs in src/isa/riscv64.s exactly.
%define ID_RV_ADD              3000
%define ID_RV_ADDI             3001
%define ID_RV_ADDIW            3002
%define ID_RV_ADDW             3003
%define ID_RV_AND              3022
%define ID_RV_ANDI             3023
%define ID_RV_AUIPC            3025
%define ID_RV_BEQ              3026
%define ID_RV_BGE              3027
%define ID_RV_BGEU             3028
%define ID_RV_BGT              3029
%define ID_RV_BGTU             3030
%define ID_RV_BLE              3031
%define ID_RV_BLEU             3032
%define ID_RV_BLT              3033
%define ID_RV_BLTU             3034
%define ID_RV_BNE              3035
%define ID_RV_DIV              3097
%define ID_RV_DIVU             3099
%define ID_RV_DIVUW            3100
%define ID_RV_DIVW             3101
%define ID_RV_JAL              3201
%define ID_RV_JALR             3202
%define ID_RV_LB               3206
%define ID_RV_LBU              3207
%define ID_RV_LD               3208
%define ID_RV_LH               3210
%define ID_RV_LHU              3211
%define ID_RV_LI               3213
%define ID_RV_LUI              3219
%define ID_RV_LW               3220
%define ID_RV_LWU              3221
%define ID_RV_MUL              3245
%define ID_RV_MULH             3246
%define ID_RV_MULHSU           3247
%define ID_RV_MULHU            3248
%define ID_RV_MULW             3249
%define ID_RV_OR               3257
%define ID_RV_ORI              3258
%define ID_RV_REM              3305
%define ID_RV_REMU             3306
%define ID_RV_REMUW            3307
%define ID_RV_REMW             3308
%define ID_RV_SB               3327
%define ID_RV_SD               3328
%define ID_RV_SH               3340
%define ID_RV_SLL              3348
%define ID_RV_SLLI             3349
%define ID_RV_SLLIW            3350
%define ID_RV_SLLW             3351
%define ID_RV_SLT              3352
%define ID_RV_SLTI             3353
%define ID_RV_SLTIU            3354
%define ID_RV_SLTU             3355
%define ID_RV_SRA              3361
%define ID_RV_SRAI             3362
%define ID_RV_SRAIW            3363
%define ID_RV_SRAW             3364
%define ID_RV_SRL              3365
%define ID_RV_SRLI             3366
%define ID_RV_SRLIW            3367
%define ID_RV_SRLW             3368
%define ID_RV_SUB              3370
%define ID_RV_SUBW             3371
%define ID_RV_SW               3372
%define ID_RV_XOR              3775
%define ID_RV_CSRRW            3091
%define ID_RV_CSRRS            3089
%define ID_RV_CSRRC            3087
%define ID_RV_CSRRWI           3092
%define ID_RV_CSRRSI           3090
%define ID_RV_CSRRCI           3088
%define ID_RV_FADD_S           3128
%define ID_RV_FADD_D           3129
%define ID_RV_FSUB_S           3177
%define ID_RV_FSUB_D           3178
%define ID_RV_FMUL_S           3161
%define ID_RV_FMUL_D           3162
%define ID_RV_FDIV_S           3156
%define ID_RV_FDIV_D           3157
%define ID_RV_XORI             3776
%define ID_RV_AMOADD_W         3400
%define ID_RV_AMOADD_D         3401
%define ID_RV_AMOSWAP_W        3402
%define ID_RV_AMOSWAP_D        3403
%define ID_RV_AMOAND_W         3404
%define ID_RV_AMOAND_D         3405
%define ID_RV_AMOOR_W          3406
%define ID_RV_AMOOR_D          3407
%define ID_RV_AMOXOR_W         3408
%define ID_RV_AMOXOR_D         3409
%define ID_RV_AMOMAX_W         3410
%define ID_RV_AMOMAX_D         3411
%define ID_RV_AMOMIN_W         3412
%define ID_RV_AMOMIN_D         3413
%define ID_RV_LR_W             3414
%define ID_RV_LR_D             3415
%define ID_RV_SC_W             3416
%define ID_RV_SC_D             3417
%define ID_RV_CALL             3800
%define ID_RV_TAIL             3801
%define ID_RVC_ADDI            3038
%define ID_RVC_MV              3065
%define ID_RVC_NOP             3066

; ---- String Operations (AMD64 Parity) ----
%define ID_RV_MOVSB            4000
%define ID_RV_MOVSW            4001
%define ID_RV_MOVSD            4002
%define ID_RV_MOVSQ            4003
%define ID_RV_STOSB            4010
%define ID_RV_STOSW            4011
%define ID_RV_STOSD            4012
%define ID_RV_STOSQ            4013

; ---- Bit Manipulation & Extensions ----
%define ID_RV_SEXTB            4100
%define ID_RV_SEXTH            4101
%define ID_RV_REV8             4102

;*
; * [def_mnc]
; ;
%macro def_mnc 3
    mnc_ent %1, %3, %2
%endmacro
