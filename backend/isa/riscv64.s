;
; ============================================================================
; File        : src/arch/riscv64.s
; Project     : utasm
; Description : RISCV64 Mnemonic and Register Lookup Tables.
; ============================================================================
;

%include "include/macro.inc"
%include "include/constant.inc"
%include "include/arch/riscv64.inc"

section .data
global mnc_tb_rv64

mnc_tb_rv64:
    def_mnc "add", 3000, 0
    def_mnc "addi", 3001, 0
    def_mnc "addiw", 3002, 0
    def_mnc "addw", 3003, 0
    def_mnc "amoadd.d", 3004, 0
    def_mnc "amoadd.w", 3005, 0
    def_mnc "amoand.d", 3006, 0
    def_mnc "amoand.w", 3007, 0
    def_mnc "amomax.d", 3008, 0
    def_mnc "amomax.w", 3009, 0
    def_mnc "amomaxu.d", 3010, 0
    def_mnc "amomaxu.w", 3011, 0
    def_mnc "amomin.d", 3012, 0
    def_mnc "amomin.w", 3013, 0
    def_mnc "amominu.d", 3014, 0
    def_mnc "amominu.w", 3015, 0
    def_mnc "amoor.d", 3016, 0
    def_mnc "amoor.w", 3017, 0
    def_mnc "amoswap.d", 3018, 0
    def_mnc "amoswap.w", 3019, 0
    def_mnc "amoxor.d", 3020, 0
    def_mnc "amoxor.w", 3021, 0
    def_mnc "and", 3022, 0
    def_mnc "andi", 3023, 0
    def_mnc "atomics", 3024, 0
    def_mnc "auipc", 3025, 0
    def_mnc "beq", 3026, 0
    def_mnc "bge", 3027, 0
    def_mnc "bgeu", 3028, 0
    def_mnc "bgt", 3029, 0
    def_mnc "bgtu", 3030, 0
    def_mnc "ble", 3031, 0
    def_mnc "bleu", 3032, 0
    def_mnc "blt", 3033, 0
    def_mnc "bltu", 3034, 0
    def_mnc "bne", 3035, 0
    def_mnc "bool", 3036, 0
    def_mnc "c.add", 3037, 0
    def_mnc "c.addi", 3038, 0
    def_mnc "c.addi16sp", 3039, 0
    def_mnc "c.addi4spn", 3040, 0
    def_mnc "c.addiw", 3041, 0
    def_mnc "call", 3800, 0
    def_mnc "tail", 3801, 0
    def_mnc "c.addw", 3042, 0
    def_mnc "c.and", 3043, 0
    def_mnc "c.andi", 3044, 0
    def_mnc "c.beqz", 3045, 0
    def_mnc "c.bnez", 3046, 0
    def_mnc "c.fld", 3047, 0
    def_mnc "c.fldsp", 3048, 0
    def_mnc "c.flw", 3049, 0
    def_mnc "c.flwsp", 3050, 0
    def_mnc "c.fsd", 3051, 0
    def_mnc "c.fsdsp", 3052, 0
    def_mnc "c.fsw", 3053, 0
    def_mnc "c.fswsp", 3054, 0
    def_mnc "c.j", 3055, 0
    def_mnc "c.jal", 3056, 0
    def_mnc "c.jalr", 3057, 0
    def_mnc "c.jr", 3058, 0
    def_mnc "c.ld", 3059, 0
    def_mnc "c.ldsp", 3060, 0
    def_mnc "c.li", 3061, 0
    def_mnc "c.lui", 3062, 0
    def_mnc "c.lw", 3063, 0
    def_mnc "c.lwsp", 3064, 0
    def_mnc "c.mv", 3065, 0
    def_mnc "c.nop", 3066, 0
    def_mnc "c.or", 3067, 0
    def_mnc "c.sd", 3068, 0
    def_mnc "c.sdsp", 3069, 0
    def_mnc "c.slli", 3070, 0
    def_mnc "c.slli_rv32", 3071, 0
    def_mnc "c.srai", 3072, 0
    def_mnc "c.srai_rv32", 3073, 0
    def_mnc "c.srli", 3074, 0
    def_mnc "c.srli_rv32", 3075, 0
    def_mnc "c.sub", 3076, 0
    def_mnc "c.subw", 3077, 0
    def_mnc "c.sw", 3078, 0
    def_mnc "c.swsp", 3079, 0
    def_mnc "c.xor", 3080, 0
    def_mnc "compressed", 3081, 0
    def_mnc "const", 3082, 0
    def_mnc "control", 3083, 0
    def_mnc "csrc", 3084, 0
    def_mnc "csrci", 3085, 0
    def_mnc "csrr", 3086, 0
    def_mnc "csrrc", 3087, 0
    def_mnc "csrrci", 3088, 0
    def_mnc "csrrs", 3089, 0
    def_mnc "csrrsi", 3090, 0
    def_mnc "csrrw", 3091, 0
    def_mnc "csrrwi", 3092, 0
    def_mnc "csrs", 3093, 0
    def_mnc "csrsi", 3094, 0
    def_mnc "csrw", 3095, 0
    def_mnc "csrwi", 3096, 0
    def_mnc "div", 3097, 0
    def_mnc "division", 3098, 0
    def_mnc "divu", 3099, 0
    def_mnc "divuw", 3100, 0
    def_mnc "divw", 3101, 0
    def_mnc "else", 3102, 0
    def_mnc "fabs.d", 3103, 0
    def_mnc "fabs.s", 3104, 0
    def_mnc "fadd.d", 3105, 0
    def_mnc "fadd.q", 3106, 0
    def_mnc "fadd.s", 3107, 0
    def_mnc "fclass.d", 3108, 0
    def_mnc "fclass.h", 3109, 0
    def_mnc "fclass.q", 3110, 0
    def_mnc "fclass.s", 3111, 0
    def_mnc "fcvt.d.h", 3112, 0
    def_mnc "fcvt.d.l", 3113, 0
    def_mnc "fcvt.d.lu", 3114, 0
    def_mnc "fcvt.d.q", 3115, 0
    def_mnc "fcvt.d.s", 3116, 0
    def_mnc "fcvt.d.w", 3117, 0
    def_mnc "fcvt.d.wu", 3118, 0
    def_mnc "fcvt.h.d", 3119, 0
    def_mnc "fcvt.h.l", 3120, 0
    def_mnc "fcvt.h.lu", 3121, 0
    def_mnc "fcvt.h.q", 3122, 0
    def_mnc "fcvt.h.s", 3123, 0
    def_mnc "fcvt.h.w", 3124, 0
    def_mnc "fcvt.h.wu", 3125, 0
    def_mnc "fcvt.l.d", 3126, 0
    def_mnc "fcvt.l.h", 3127, 0
    def_mnc "fcvt.l.q", 3128, 0
    def_mnc "fcvt.l.s", 3129, 0
    def_mnc "fcvt.lu.d", 3130, 0
    def_mnc "fcvt.lu.h", 3131, 0
    def_mnc "fcvt.lu.q", 3132, 0
    def_mnc "fcvt.lu.s", 3133, 0
    def_mnc "fcvt.q.d", 3134, 0
    def_mnc "fcvt.q.h", 3135, 0
    def_mnc "fcvt.q.l", 3136, 0
    def_mnc "fcvt.q.lu", 3137, 0
    def_mnc "fcvt.q.s", 3138, 0
    def_mnc "fcvt.q.w", 3139, 0
    def_mnc "fcvt.q.wu", 3140, 0
    def_mnc "fcvt.s.d", 3141, 0
    def_mnc "fcvt.s.h", 3142, 0
    def_mnc "fcvt.s.l", 3143, 0
    def_mnc "fcvt.s.lu", 3144, 0
    def_mnc "fcvt.s.q", 3145, 0
    def_mnc "fcvt.s.w", 3146, 0
    def_mnc "fcvt.s.wu", 3147, 0
    def_mnc "fcvt.w.d", 3148, 0
    def_mnc "fcvt.w.h", 3149, 0
    def_mnc "fcvt.w.q", 3150, 0
    def_mnc "fcvt.w.s", 3151, 0
    def_mnc "fcvt.wu.d", 3152, 0
    def_mnc "fcvt.wu.h", 3153, 0
    def_mnc "fcvt.wu.q", 3154, 0
    def_mnc "fcvt.wu.s", 3155, 0
    def_mnc "fdiv.d", 3156, 0
    def_mnc "fdiv.q", 3157, 0
    def_mnc "fdiv.s", 3158, 0
    def_mnc "fence", 3159, 0
    def_mnc "feq.d", 3160, 0
    def_mnc "feq.q", 3161, 0
    def_mnc "feq.s", 3162, 0
    def_mnc "fld", 3163, 0
    def_mnc "fle.d", 3164, 0
    def_mnc "fle.q", 3165, 0
    def_mnc "fle.s", 3166, 0
    def_mnc "flh", 3167, 0
    def_mnc "floating", 3168, 0
    def_mnc "flq", 3169, 0
    def_mnc "flt.d", 3170, 0
    def_mnc "flt.q", 3171, 0
    def_mnc "flt.s", 3172, 0
    def_mnc "flw", 3173, 0
    def_mnc "fmadd.d", 3174, 0
    def_mnc "fmadd.q", 3175, 0
    def_mnc "fmadd.s", 3176, 0
    def_mnc "fmax.d", 3177, 0
    def_mnc "fmax.q", 3178, 0
    def_mnc "fmax.s", 3179, 0
    def_mnc "fmin.d", 3180, 0
    def_mnc "fmin.q", 3181, 0
    def_mnc "fmin.s", 3182, 0
    def_mnc "fmsub.d", 3183, 0
    def_mnc "fmsub.q", 3184, 0
    def_mnc "fmsub.s", 3185, 0
    def_mnc "fmul.d", 3186, 0
    def_mnc "fmul.q", 3187, 0
    def_mnc "fmul.s", 3188, 0
    def_mnc "fmv.d", 3189, 0
    def_mnc "fmv.d.x", 3190, 0
    def_mnc "fmv.h.x", 3191, 0
    def_mnc "fmv.s", 3192, 0
    def_mnc "fmv.w.x", 3193, 0
    def_mnc "fmv.x.d", 3194, 0
    def_mnc "fmv.x.h", 3195, 0
    def_mnc "fmv.x.s", 3196, 0
    def_mnc "fmv.x.w", 3197, 0
    def_mnc "fneg.d", 3198, 0
    def_mnc "fneg.s", 3199, 0
    def_mnc "fnmadd.d", 3200, 0
    def_mnc "fnmadd.q", 3201, 0
    def_mnc "fnmadd.s", 3202, 0
    def_mnc "fnmsub.d", 3203, 0
    def_mnc "fnmsub.q", 3204, 0
    def_mnc "fnmsub.s", 3205, 0
    def_mnc "frcsr", 3206, 0
    def_mnc "frflags", 3207, 0
    def_mnc "frrm", 3208, 0
    def_mnc "fscsr", 3209, 0
    def_mnc "fsd", 3210, 0
    def_mnc "fsflags", 3211, 0
    def_mnc "fsgnj.d", 3212, 0
    def_mnc "fsgnj.h", 3213, 0
    def_mnc "fsgnj.q", 3214, 0
    def_mnc "fsgnj.s", 3215, 0
    def_mnc "fsgnjn.d", 3216, 0
    def_mnc "fsgnjn.h", 3217, 0
    def_mnc "fsgnjn.q", 3218, 0
    def_mnc "fsgnjn.s", 3219, 0
    def_mnc "fsgnjx.d", 3220, 0
    def_mnc "fsgnjx.h", 3221, 0
    def_mnc "fsgnjx.q", 3222, 0
    def_mnc "fsgnjx.s", 3223, 0
    def_mnc "fsh", 3224, 0
    def_mnc "fsq", 3225, 0
    def_mnc "fsqrt.d", 3226, 0
    def_mnc "fsqrt.q", 3227, 0
    def_mnc "fsqrt.s", 3228, 0
    def_mnc "fsrm", 3229, 0
    def_mnc "fsub.d", 3230, 0
    def_mnc "fsub.q", 3231, 0
    def_mnc "fsub.s", 3232, 0
    def_mnc "fsw", 3233, 0
    def_mnc "half", 3234, 0
    def_mnc "hfence.gvma", 3235, 0
    def_mnc "hfence.vvma", 3236, 0
    def_mnc "hinval.gvma", 3237, 0
    def_mnc "hinval.vvma", 3238, 0
    def_mnc "hlv.b", 3239, 0
    def_mnc "hlv.bu", 3240, 0
    def_mnc "hlv.d", 3241, 0
    def_mnc "hlv.h", 3242, 0
    def_mnc "hlv.hu", 3243, 0
    def_mnc "hlv.w", 3244, 0
    def_mnc "hlv.wu", 3245, 0
    def_mnc "hlvx.hu", 3246, 0
    def_mnc "hlvx.wu", 3247, 0
    def_mnc "hsv.b", 3248, 0
    def_mnc "hsv.d", 3249, 0
    def_mnc "hsv.h", 3250, 0
    def_mnc "hsv.w", 3251, 0
    def_mnc "int", 3252, 0
    def_mnc "integer", 3253, 0
    def_mnc "introduction", 3254, 0
    def_mnc "jal", 3255, 0
    def_mnc "jalr", 3256, 0
    def_mnc "lb", 3257, 0
    def_mnc "lbu", 3258, 0
    def_mnc "ld", 3259, 0
    def_mnc "lh", 3260, 0
    def_mnc "lhu", 3261, 0
    def_mnc "load", 3262, 0
    def_mnc "lr.d", 3263, 0
    def_mnc "lr.w", 3264, 0
    def_mnc "lui", 3265, 0
    def_mnc "lw", 3266, 0
    def_mnc "lwu", 3267, 0
    def_mnc "min", 3268, 0
    def_mnc "mul", 3269, 0
    def_mnc "mulh", 3270, 0
    def_mnc "mulhsu", 3271, 0
    def_mnc "mulhu", 3272, 0
    def_mnc "mulw", 3273, 0
    def_mnc "mv", 3274, 0
    def_mnc "neg", 3275, 0
    def_mnc "not", 3276, 0
    def_mnc "or", 3277, 0
    def_mnc "ori", 3278, 0
    def_mnc "rdcycle", 3279, 0
    def_mnc "rdcycleh", 3280, 0
    def_mnc "rdinstret", 3281, 0
    def_mnc "rdinstreth", 3282, 0
    def_mnc "rdtime", 3283, 0
    def_mnc "rdtimeh", 3284, 0
    def_mnc "reads", 3285, 0
    def_mnc "rem", 3286, 0
    def_mnc "remu", 3287, 0
    def_mnc "remuw", 3288, 0
    def_mnc "remw", 3289, 0
    def_mnc "sb", 3290, 0
    def_mnc "sc.d", 3291, 0
    def_mnc "sc.w", 3292, 0
    def_mnc "sd", 3293, 0
    def_mnc "sec", 3294, 0
    def_mnc "seqz", 3295, 0
    def_mnc "sext.w", 3296, 0
    def_mnc "sh", 3297, 0
    def_mnc "single", 3298, 0
    def_mnc "sll", 3299, 0
    def_mnc "slli", 3300, 0
    def_mnc "slliw", 3301, 0
    def_mnc "sllw", 3302, 0
    def_mnc "slt", 3303, 0
    def_mnc "slti", 3304, 0
    def_mnc "sltiu", 3305, 0
    def_mnc "sltu", 3306, 0
    def_mnc "snez", 3307, 0
    def_mnc "sra", 3308, 0
    def_mnc "srai", 3309, 0
    def_mnc "sraiw", 3310, 0
    def_mnc "sraw", 3311, 0
    def_mnc "srl", 3312, 0
    def_mnc "srli", 3313, 0
    def_mnc "srliw", 3314, 0
    def_mnc "srlw", 3315, 0
    def_mnc "sub", 3316, 0
    def_mnc "subw", 3317, 0
    def_mnc "sw", 3318, 0
    def_mnc "unmasked", 3319, 0
    def_mnc "vaadd.vv", 3320, 0
    def_mnc "vaadd.vx", 3321, 0
    def_mnc "vaaddu.vv", 3322, 0
    def_mnc "vaaddu.vx", 3323, 0
    def_mnc "vadc", 3324, 0
    def_mnc "vadc.vim", 3325, 0
    def_mnc "vadc.vvm", 3326, 0
    def_mnc "vadc.vxm", 3327, 0
    def_mnc "vadd.vi", 3328, 0
    def_mnc "vadd.vv", 3329, 0
    def_mnc "vadd.vx", 3330, 0
    def_mnc "vamoaddei16.v", 3331, 0
    def_mnc "vamoaddei32.v", 3332, 0
    def_mnc "vamoaddei64.v", 3333, 0
    def_mnc "vamoaddei8.v", 3334, 0
    def_mnc "vamoandei16.v", 3335, 0
    def_mnc "vamoandei32.v", 3336, 0
    def_mnc "vamoandei64.v", 3337, 0
    def_mnc "vamoandei8.v", 3338, 0
    def_mnc "vamomaxei16.v", 3339, 0
    def_mnc "vamomaxei32.v", 3340, 0
    def_mnc "vamomaxei64.v", 3341, 0
    def_mnc "vamomaxei8.v", 3342, 0
    def_mnc "vamomaxuei16.v", 3343, 0
    def_mnc "vamomaxuei32.v", 3344, 0
    def_mnc "vamomaxuei64.v", 3345, 0
    def_mnc "vamomaxuei8.v", 3346, 0
    def_mnc "vamominei16.v", 3347, 0
    def_mnc "vamominei32.v", 3348, 0
    def_mnc "vamominei64.v", 3349, 0
    def_mnc "vamominei8.v", 3350, 0
    def_mnc "vamominuei16.v", 3351, 0
    def_mnc "vamominuei32.v", 3352, 0
    def_mnc "vamominuei64.v", 3353, 0
    def_mnc "vamominuei8.v", 3354, 0
    def_mnc "vamoorei16.v", 3355, 0
    def_mnc "vamoorei32.v", 3356, 0
    def_mnc "vamoorei64.v", 3357, 0
    def_mnc "vamoorei8.v", 3358, 0
    def_mnc "vamoswapei16.v", 3359, 0
    def_mnc "vamoswapei32.v", 3360, 0
    def_mnc "vamoswapei64.v", 3361, 0
    def_mnc "vamoswapei8.v", 3362, 0
    def_mnc "vamoxorei16.v", 3363, 0
    def_mnc "vamoxorei32.v", 3364, 0
    def_mnc "vamoxorei64.v", 3365, 0
    def_mnc "vamoxorei8.v", 3366, 0
    def_mnc "vand.vi", 3367, 0
    def_mnc "vand.vv", 3368, 0
    def_mnc "vand.vx", 3369, 0
    def_mnc "vasub.vv", 3370, 0
    def_mnc "vasub.vx", 3371, 0
    def_mnc "vasubu.vv", 3372, 0
    def_mnc "vasubu.vx", 3373, 0
    def_mnc "vcompress", 3374, 0
    def_mnc "vcompress.vm", 3375, 0
    def_mnc "vcpop.m", 3376, 0
    def_mnc "vdiv.vv", 3377, 0
    def_mnc "vdiv.vx", 3378, 0
    def_mnc "vdivu.vv", 3379, 0
    def_mnc "vdivu.vx", 3380, 0
    def_mnc "vector", 3381, 0
    def_mnc "vfadd.vf", 3382, 0
    def_mnc "vfadd.vv", 3383, 0
    def_mnc "vfclass.v", 3384, 0
    def_mnc "vfcvt.f.x.v", 3385, 0
    def_mnc "vfcvt.f.xu.v", 3386, 0
    def_mnc "vfcvt.rtz.x.f.v", 3387, 0
    def_mnc "vfcvt.rtz.xu.f.v", 3388, 0
    def_mnc "vfcvt.x.f.v", 3389, 0
    def_mnc "vfcvt.xu.f.v", 3390, 0
    def_mnc "vfdiv.vf", 3391, 0
    def_mnc "vfdiv.vv", 3392, 0
    def_mnc "vfirst.m", 3393, 0
    def_mnc "vfmacc.vf", 3394, 0
    def_mnc "vfmacc.vv", 3395, 0
    def_mnc "vfmadd.vf", 3396, 0
    def_mnc "vfmadd.vv", 3397, 0
    def_mnc "vfmax.vf", 3398, 0
    def_mnc "vfmax.vv", 3399, 0
    def_mnc "vfmerge.vfm", 3400, 0
    def_mnc "vfmin.vf", 3401, 0
    def_mnc "vfmin.vv", 3402, 0
    def_mnc "vfmsac.vf", 3403, 0
    def_mnc "vfmsac.vv", 3404, 0
    def_mnc "vfmsub.vf", 3405, 0
    def_mnc "vfmsub.vv", 3406, 0
    def_mnc "vfmul.vf", 3407, 0
    def_mnc "vfmul.vv", 3408, 0
    def_mnc "vfmv.f.s", 3409, 0
    def_mnc "vfmv.s.f", 3410, 0
    def_mnc "vfmv.v.f", 3411, 0
    def_mnc "vfncvt.f.f.w", 3412, 0
    def_mnc "vfncvt.f.x.w", 3413, 0
    def_mnc "vfncvt.f.xu.w", 3414, 0
    def_mnc "vfncvt.rod.f.f.w", 3415, 0
    def_mnc "vfncvt.rtz.x.f.w", 3416, 0
    def_mnc "vfncvt.rtz.xu.f.w", 3417, 0
    def_mnc "vfncvt.x.f.w", 3418, 0
    def_mnc "vfncvt.xu.f.w", 3419, 0
    def_mnc "vfnmacc.vf", 3420, 0
    def_mnc "vfnmacc.vv", 3421, 0
    def_mnc "vfnmadd.vf", 3422, 0
    def_mnc "vfnmadd.vv", 3423, 0
    def_mnc "vfnmsac.vf", 3424, 0
    def_mnc "vfnmsac.vv", 3425, 0
    def_mnc "vfnmsub.vf", 3426, 0
    def_mnc "vfnmsub.vv", 3427, 0
    def_mnc "vfrdiv.vf", 3428, 0
    def_mnc "vfrec7.v", 3429, 0
    def_mnc "vfredmax.vs", 3430, 0
    def_mnc "vfredmin.vs", 3431, 0
    def_mnc "vfredosum.vs", 3432, 0
    def_mnc "vfredusum.vs", 3433, 0
    def_mnc "vfrsqrt7.v", 3434, 0
    def_mnc "vfrsub.vf", 3435, 0
    def_mnc "vfsgnj.vf", 3436, 0
    def_mnc "vfsgnj.vv", 3437, 0
    def_mnc "vfsgnjn.vf", 3438, 0
    def_mnc "vfsgnjn.vv", 3439, 0
    def_mnc "vfsgnjx.vf", 3440, 0
    def_mnc "vfsgnjx.vv", 3441, 0
    def_mnc "vfslide1down.vf", 3442, 0
    def_mnc "vfslide1up.vf", 3443, 0
    def_mnc "vfsqrt.v", 3444, 0
    def_mnc "vfsub.vf", 3445, 0
    def_mnc "vfsub.vv", 3446, 0
    def_mnc "vfwadd.vf", 3447, 0
    def_mnc "vfwadd.vv", 3448, 0
    def_mnc "vfwadd.wf", 3449, 0
    def_mnc "vfwadd.wv", 3450, 0
    def_mnc "vfwcvt.f.f.v", 3451, 0
    def_mnc "vfwcvt.f.x.v", 3452, 0
    def_mnc "vfwcvt.f.xu.v", 3453, 0
    def_mnc "vfwcvt.rtz.x.f.v", 3454, 0
    def_mnc "vfwcvt.rtz.xu.f.v", 3455, 0
    def_mnc "vfwcvt.x.f.v", 3456, 0
    def_mnc "vfwcvt.xu.f.v", 3457, 0
    def_mnc "vfwmacc.vf", 3458, 0
    def_mnc "vfwmacc.vv", 3459, 0
    def_mnc "vfwmsac.vf", 3460, 0
    def_mnc "vfwmsac.vv", 3461, 0
    def_mnc "vfwmul.vf", 3462, 0
    def_mnc "vfwmul.vv", 3463, 0
    def_mnc "vfwnmacc.vf", 3464, 0
    def_mnc "vfwnmacc.vv", 3465, 0
    def_mnc "vfwnmsac.vf", 3466, 0
    def_mnc "vfwnmsac.vv", 3467, 0
    def_mnc "vfwredosum.vs", 3468, 0
    def_mnc "vfwredusum.vs", 3469, 0
    def_mnc "vfwsub.vf", 3470, 0
    def_mnc "vfwsub.vv", 3471, 0
    def_mnc "vfwsub.wf", 3472, 0
    def_mnc "vfwsub.wv", 3473, 0
    def_mnc "vid.v", 3474, 0
    def_mnc "viota.m", 3475, 0
    def_mnc "vl1re16.v", 3476, 0
    def_mnc "vl1re32.v", 3477, 0
    def_mnc "vl1re64.v", 3478, 0
    def_mnc "vl1re8.v", 3479, 0
    def_mnc "vl2re16.v", 3480, 0
    def_mnc "vl2re32.v", 3481, 0
    def_mnc "vl2re64.v", 3482, 0
    def_mnc "vl2re8.v", 3483, 0
    def_mnc "vl4re16.v", 3484, 0
    def_mnc "vl4re32.v", 3485, 0
    def_mnc "vl4re64.v", 3486, 0
    def_mnc "vl4re8.v", 3487, 0
    def_mnc "vl8re16.v", 3488, 0
    def_mnc "vl8re32.v", 3489, 0
    def_mnc "vl8re64.v", 3490, 0
    def_mnc "vl8re8.v", 3491, 0
    def_mnc "vle1024.v", 3492, 0
    def_mnc "vle1024ff.v", 3493, 0
    def_mnc "vle128.v", 3494, 0
    def_mnc "vle128ff.v", 3495, 0
    def_mnc "vle16.v", 3496, 0
    def_mnc "vle16ff.v", 3497, 0
    def_mnc "vle256.v", 3498, 0
    def_mnc "vle256ff.v", 3499, 0
    def_mnc "vle32.v", 3500, 0
    def_mnc "vle32ff.v", 3501, 0
    def_mnc "vle512.v", 3502, 0
    def_mnc "vle512ff.v", 3503, 0
    def_mnc "vle64.v", 3504, 0
    def_mnc "vle64ff.v", 3505, 0
    def_mnc "vle8.v", 3506, 0
    def_mnc "vle8ff.v", 3507, 0
    def_mnc "vlm.v", 3508, 0
    def_mnc "vloxei1024.v", 3509, 0
    def_mnc "vloxei128.v", 3510, 0
    def_mnc "vloxei16.v", 3511, 0
    def_mnc "vloxei256.v", 3512, 0
    def_mnc "vloxei32.v", 3513, 0
    def_mnc "vloxei512.v", 3514, 0
    def_mnc "vloxei64.v", 3515, 0
    def_mnc "vloxei8.v", 3516, 0
    def_mnc "vlse1024.v", 3517, 0
    def_mnc "vlse128.v", 3518, 0
    def_mnc "vlse16.v", 3519, 0
    def_mnc "vlse256.v", 3520, 0
    def_mnc "vlse32.v", 3521, 0
    def_mnc "vlse512.v", 3522, 0
    def_mnc "vlse64.v", 3523, 0
    def_mnc "vlse8.v", 3524, 0
    def_mnc "vluxei1024.v", 3525, 0
    def_mnc "vluxei128.v", 3526, 0
    def_mnc "vluxei16.v", 3527, 0
    def_mnc "vluxei256.v", 3528, 0
    def_mnc "vluxei32.v", 3529, 0
    def_mnc "vluxei512.v", 3530, 0
    def_mnc "vluxei64.v", 3531, 0
    def_mnc "vluxei8.v", 3532, 0
    def_mnc "vmacc.vv", 3533, 0
    def_mnc "vmacc.vx", 3534, 0
    def_mnc "vmadc", 3535, 0
    def_mnc "vmadc.vi", 3536, 0
    def_mnc "vmadc.vim", 3537, 0
    def_mnc "vmadc.vv", 3538, 0
    def_mnc "vmadc.vvm", 3539, 0
    def_mnc "vmadc.vx", 3540, 0
    def_mnc "vmadc.vxm", 3541, 0
    def_mnc "vmadd.vv", 3542, 0
    def_mnc "vmadd.vx", 3543, 0
    def_mnc "vmand.mm", 3544, 0
    def_mnc "vmandn.mm", 3545, 0
    def_mnc "vmax.vv", 3546, 0
    def_mnc "vmax.vx", 3547, 0
    def_mnc "vmaxu.vv", 3548, 0
    def_mnc "vmaxu.vx", 3549, 0
    def_mnc "vmerge.vim", 3550, 0
    def_mnc "vmerge.vvm", 3551, 0
    def_mnc "vmerge.vxm", 3552, 0
    def_mnc "vmfeq.vf", 3553, 0
    def_mnc "vmfeq.vv", 3554, 0
    def_mnc "vmfge.vf", 3555, 0
    def_mnc "vmfgt.vf", 3556, 0
    def_mnc "vmfle.vf", 3557, 0
    def_mnc "vmfle.vv", 3558, 0
    def_mnc "vmflt.vf", 3559, 0
    def_mnc "vmflt.vv", 3560, 0
    def_mnc "vmfne.vf", 3561, 0
    def_mnc "vmfne.vv", 3562, 0
    def_mnc "vmin.vv", 3563, 0
    def_mnc "vmin.vx", 3564, 0
    def_mnc "vminu.vv", 3565, 0
    def_mnc "vminu.vx", 3566, 0
    def_mnc "vmmv.m", 3567, 0
    def_mnc "vmnand.mm", 3568, 0
    def_mnc "vmnor.mm", 3569, 0
    def_mnc "vmor.mm", 3570, 0
    def_mnc "vmorn.mm", 3571, 0
    def_mnc "vmsbc.vv", 3572, 0
    def_mnc "vmsbc.vvm", 3573, 0
    def_mnc "vmsbc.vx", 3574, 0
    def_mnc "vmsbc.vxm", 3575, 0
    def_mnc "vmsbf.m", 3576, 0
    def_mnc "vmseq.vi", 3577, 0
    def_mnc "vmseq.vv", 3578, 0
    def_mnc "vmseq.vx", 3579, 0
    def_mnc "vmsgt.vi", 3580, 0
    def_mnc "vmsgt.vx", 3581, 0
    def_mnc "vmsgtu.vi", 3582, 0
    def_mnc "vmsgtu.vx", 3583, 0
    def_mnc "vmsif.m", 3584, 0
    def_mnc "vmsle.vi", 3585, 0
    def_mnc "vmsle.vv", 3586, 0
    def_mnc "vmsle.vx", 3587, 0
    def_mnc "vmsleu.vi", 3588, 0
    def_mnc "vmsleu.vv", 3589, 0
    def_mnc "vmsleu.vx", 3590, 0
    def_mnc "vmslt.vv", 3591, 0
    def_mnc "vmslt.vx", 3592, 0
    def_mnc "vmsltu.vv", 3593, 0
    def_mnc "vmsltu.vx", 3594, 0
    def_mnc "vmsne.vi", 3595, 0
    def_mnc "vmsne.vv", 3596, 0
    def_mnc "vmsne.vx", 3597, 0
    def_mnc "vmsof.m", 3598, 0
    def_mnc "vmul.vv", 3599, 0
    def_mnc "vmul.vx", 3600, 0
    def_mnc "vmulh.vv", 3601, 0
    def_mnc "vmulh.vx", 3602, 0
    def_mnc "vmulhsu.vv", 3603, 0
    def_mnc "vmulhsu.vx", 3604, 0
    def_mnc "vmulhu.vv", 3605, 0
    def_mnc "vmulhu.vx", 3606, 0
    def_mnc "vmv.s.x", 3607, 0
    def_mnc "vmv.v.i", 3608, 0
    def_mnc "vmv.v.v", 3609, 0
    def_mnc "vmv.v.x", 3610, 0
    def_mnc "vmv.x.s", 3611, 0
    def_mnc "vmv1r.v", 3612, 0
    def_mnc "vmv2r.v", 3613, 0
    def_mnc "vmv4r.v", 3614, 0
    def_mnc "vmv8r.v", 3615, 0
    def_mnc "vmxnor.mm", 3616, 0
    def_mnc "vmxor.mm", 3617, 0
    def_mnc "vnclip.wi", 3618, 0
    def_mnc "vnclip.wv", 3619, 0
    def_mnc "vnclip.wx", 3620, 0
    def_mnc "vnclipu.wi", 3621, 0
    def_mnc "vnclipu.wv", 3622, 0
    def_mnc "vnclipu.wx", 3623, 0
    def_mnc "vnmsac.vv", 3624, 0
    def_mnc "vnmsac.vx", 3625, 0
    def_mnc "vnmsub.vv", 3626, 0
    def_mnc "vnmsub.vx", 3627, 0
    def_mnc "vnsra.wi", 3628, 0
    def_mnc "vnsra.wv", 3629, 0
    def_mnc "vnsra.wx", 3630, 0
    def_mnc "vnsrl.wi", 3631, 0
    def_mnc "vnsrl.wv", 3632, 0
    def_mnc "vnsrl.wx", 3633, 0
    def_mnc "vor.vi", 3634, 0
    def_mnc "vor.vv", 3635, 0
    def_mnc "vor.vx", 3636, 0
    def_mnc "vredand.vs", 3637, 0
    def_mnc "vredmax.vs", 3638, 0
    def_mnc "vredmaxu.vs", 3639, 0
    def_mnc "vredmin.vs", 3640, 0
    def_mnc "vredminu.vs", 3641, 0
    def_mnc "vredor.vs", 3642, 0
    def_mnc "vredsum.vs", 3643, 0
    def_mnc "vredxor.vs", 3644, 0
    def_mnc "vrem.vv", 3645, 0
    def_mnc "vrem.vx", 3646, 0
    def_mnc "vremu.vv", 3647, 0
    def_mnc "vremu.vx", 3648, 0
    def_mnc "vrgather.vi", 3649, 0
    def_mnc "vrgather.vv", 3650, 0
    def_mnc "vrgather.vx", 3651, 0
    def_mnc "vrgatherei16.vv", 3652, 0
    def_mnc "vrsub.vi", 3653, 0
    def_mnc "vrsub.vx", 3654, 0
    def_mnc "vs1r.v", 3655, 0
    def_mnc "vs2r.v", 3656, 0
    def_mnc "vs4r.v", 3657, 0
    def_mnc "vs8r.v", 3658, 0
    def_mnc "vsadd.vi", 3659, 0
    def_mnc "vsadd.vv", 3660, 0
    def_mnc "vsadd.vx", 3661, 0
    def_mnc "vsaddu.vi", 3662, 0
    def_mnc "vsaddu.vv", 3663, 0
    def_mnc "vsaddu.vx", 3664, 0
    def_mnc "vsbc.vvm", 3665, 0
    def_mnc "vsbc.vxm", 3666, 0
    def_mnc "vse1024.v", 3667, 0
    def_mnc "vse128.v", 3668, 0
    def_mnc "vse16.v", 3669, 0
    def_mnc "vse256.v", 3670, 0
    def_mnc "vse32.v", 3671, 0
    def_mnc "vse512.v", 3672, 0
    def_mnc "vse64.v", 3673, 0
    def_mnc "vse8.v", 3674, 0
    def_mnc "vsetivli", 3675, 0
    def_mnc "vsetvl", 3676, 0
    def_mnc "vsetvli", 3677, 0
    def_mnc "vsext.vf2", 3678, 0
    def_mnc "vsext.vf4", 3679, 0
    def_mnc "vsext.vf8", 3680, 0
    def_mnc "vslide1down", 3681, 0
    def_mnc "vslide1down.vx", 3682, 0
    def_mnc "vslide1up", 3683, 0
    def_mnc "vslide1up.vx", 3684, 0
    def_mnc "vslidedown", 3685, 0
    def_mnc "vslidedown.vi", 3686, 0
    def_mnc "vslidedown.vx", 3687, 0
    def_mnc "vslideup.vi", 3688, 0
    def_mnc "vslideup.vx", 3689, 0
    def_mnc "vsll.vi", 3690, 0
    def_mnc "vsll.vv", 3691, 0
    def_mnc "vsll.vx", 3692, 0
    def_mnc "vsm.v", 3693, 0
    def_mnc "vsmul.vv", 3694, 0
    def_mnc "vsmul.vx", 3695, 0
    def_mnc "vsoxei1024.v", 3696, 0
    def_mnc "vsoxei128.v", 3697, 0
    def_mnc "vsoxei16.v", 3698, 0
    def_mnc "vsoxei256.v", 3699, 0
    def_mnc "vsoxei32.v", 3700, 0
    def_mnc "vsoxei512.v", 3701, 0
    def_mnc "vsoxei64.v", 3702, 0
    def_mnc "vsoxei8.v", 3703, 0
    def_mnc "vsra.vi", 3704, 0
    def_mnc "vsra.vv", 3705, 0
    def_mnc "vsra.vx", 3706, 0
    def_mnc "vsrl.vi", 3707, 0
    def_mnc "vsrl.vv", 3708, 0
    def_mnc "vsrl.vx", 3709, 0
    def_mnc "vsse1024.v", 3710, 0
    def_mnc "vsse128.v", 3711, 0
    def_mnc "vsse16.v", 3712, 0
    def_mnc "vsse256.v", 3713, 0
    def_mnc "vsse32.v", 3714, 0
    def_mnc "vsse512.v", 3715, 0
    def_mnc "vsse64.v", 3716, 0
    def_mnc "vsse8.v", 3717, 0
    def_mnc "vssra.vi", 3718, 0
    def_mnc "vssra.vv", 3719, 0
    def_mnc "vssra.vx", 3720, 0
    def_mnc "vssrl.vi", 3721, 0
    def_mnc "vssrl.vv", 3722, 0
    def_mnc "vssrl.vx", 3723, 0
    def_mnc "vssub.vv", 3724, 0
    def_mnc "vssub.vx", 3725, 0
    def_mnc "vssubu.vv", 3726, 0
    def_mnc "vssubu.vx", 3727, 0
    def_mnc "vsub.vv", 3728, 0
    def_mnc "vsub.vx", 3729, 0
    def_mnc "vsuxei1024.v", 3730, 0
    def_mnc "vsuxei128.v", 3731, 0
    def_mnc "vsuxei16.v", 3732, 0
    def_mnc "vsuxei256.v", 3733, 0
    def_mnc "vsuxei32.v", 3734, 0
    def_mnc "vsuxei512.v", 3735, 0
    def_mnc "vsuxei64.v", 3736, 0
    def_mnc "vsuxei8.v", 3737, 0
    def_mnc "vwadd.vv", 3738, 0
    def_mnc "vwadd.vx", 3739, 0
    def_mnc "vwadd.wv", 3740, 0
    def_mnc "vwadd.wx", 3741, 0
    def_mnc "vwaddu.vv", 3742, 0
    def_mnc "vwaddu.vx", 3743, 0
    def_mnc "vwaddu.wv", 3744, 0
    def_mnc "vwaddu.wx", 3745, 0
    def_mnc "vwmacc.vv", 3746, 0
    def_mnc "vwmacc.vx", 3747, 0
    def_mnc "vwmaccsu.vv", 3748, 0
    def_mnc "vwmaccsu.vx", 3749, 0
    def_mnc "vwmaccu.vv", 3750, 0
    def_mnc "vwmaccu.vx", 3751, 0
    def_mnc "vwmaccus.vx", 3752, 0
    def_mnc "vwmul.vv", 3753, 0
    def_mnc "vwmul.vx", 3754, 0
    def_mnc "vwmulsu.vv", 3755, 0
    def_mnc "vwmulsu.vx", 3756, 0
    def_mnc "vwmulu.vv", 3757, 0
    def_mnc "vwmulu.vx", 3758, 0
    def_mnc "vwredsum.vs", 3759, 0
    def_mnc "vwredsumu.vs", 3760, 0
    def_mnc "vwsub.vv", 3761, 0
    def_mnc "vwsub.vx", 3762, 0
    def_mnc "vwsub.wv", 3763, 0
    def_mnc "vwsub.wx", 3764, 0
    def_mnc "vwsubu.vv", 3765, 0
    def_mnc "vwsubu.vx", 3766, 0
    def_mnc "vwsubu.wv", 3767, 0
    def_mnc "vwsubu.wx", 3768, 0
    def_mnc "vxor.vi", 3769, 0
    def_mnc "vxor.vv", 3770, 0
    def_mnc "vxor.vx", 3771, 0
    def_mnc "vzext.vf2", 3772, 0
    def_mnc "vzext.vf4", 3773, 0
    def_mnc "vzext.vf8", 3774, 0
    def_mnc "xor", 3775, 0
    def_mnc "xori", 3776, 0
    def_mnc "zve", 3777, 0
    dq 0 ; Sentinel

global riscv64_register_table
riscv64_register_table:
    ; ---- Raw Architectural Names (x0-x31) ----
    %assign i 0
    %rep 32
        compile_time_hash "x%[i]", H_X%[i]
        dq H_X%[i], (8 << 8) | %[i]
    %assign i i+1
    %endrep

    ; ---- ABI Names ----
    compile_time_hash "zero", H_ZERO
    dq H_ZERO, (8 << 8) | 0
    compile_time_hash "ra", H_RA
    dq H_RA, (8 << 8) | 1
    compile_time_hash "sp", H_SP
    dq H_SP, (8 << 8) | 2
    compile_time_hash "gp", H_GP
    dq H_GP, (8 << 8) | 3
    compile_time_hash "tp", H_TP
    dq H_TP, (8 << 8) | 4
    compile_time_hash "t0", H_T0
    dq H_T0, (8 << 8) | 5
    compile_time_hash "t1", H_T1
    dq H_T1, (8 << 8) | 6
    compile_time_hash "t2", H_T2
    dq H_T2, (8 << 8) | 7
    compile_time_hash "s0", H_S0
    dq H_S0, (8 << 8) | 8
    compile_time_hash "s1", H_S1
    dq H_S1, (8 << 8) | 9
    compile_time_hash "a0", H_A0
    dq H_A0, (8 << 8) | 10
    compile_time_hash "a1", H_A1
    dq H_A1, (8 << 8) | 11
    compile_time_hash "a2", H_A2
    dq H_A2, (8 << 8) | 12
    compile_time_hash "a3", H_A3
    dq H_A3, (8 << 8) | 13
    compile_time_hash "a4", H_A4
    dq H_A4, (8 << 8) | 14
    compile_time_hash "a5", H_A5
    dq H_A5, (8 << 8) | 15
    compile_time_hash "a6", H_A6
    dq H_A6, (8 << 8) | 16
    compile_time_hash "a7", H_A7
    dq H_A7, (8 << 8) | 17
    compile_time_hash "s2", H_S2
    dq H_S2, (8 << 8) | 18
    compile_time_hash "s3", H_S3
    dq H_S3, (8 << 8) | 19
    compile_time_hash "s4", H_S4
    dq H_S4, (8 << 8) | 20
    compile_time_hash "s5", H_S5
    dq H_S5, (8 << 8) | 21
    compile_time_hash "s6", H_S6
    dq H_S6, (8 << 8) | 22
    compile_time_hash "s7", H_S7
    dq H_S7, (8 << 8) | 23
    compile_time_hash "s8", H_S8
    dq H_S8, (8 << 8) | 24
    compile_time_hash "s9", H_S9
    dq H_S9, (8 << 8) | 25
    compile_time_hash "s10", H_S10
    dq H_S10, (8 << 8) | 26
    compile_time_hash "s11", H_S11
    dq H_S11, (8 << 8) | 27
    compile_time_hash "t3", H_T3
    dq H_T3, (8 << 8) | 28
    compile_time_hash "t4", H_T4
    dq H_T4, (8 << 8) | 29
    compile_time_hash "t5", H_T5
    dq H_T5, (8 << 8) | 30
    compile_time_hash "t6", H_T6
    dq H_T6, (8 << 8) | 31

    ; ---- Floating Point Registers (f0-f31) ----
    %assign i 0
    %rep 32
        compile_time_hash "f%[i]", H_F%[i]
        dq H_F%[i], (8 << 8) | %[i]
    %assign i i+1
    %endrep

    ; ---- FP ABI Aliases ----
    %assign i 0
    %rep 8
        compile_time_hash "ft%[i]", H_FT%[i]
        dq H_FT%[i], (8 << 8) | %[i]
    %assign i i+1
    %endrep
    %assign i 0
    %rep 8
        compile_time_hash "fa%[i]", H_FA%[i]
        dq H_FA%[i], (8 << 8) | (10 + %[i])
    %assign i i+1
    %endrep

    ; ---- Vector Registers (v0-v31) ----
    %assign i 0
    %rep 32
        compile_time_hash "v%[i]", H_V%[i]
        dq H_V%[i], (16 << 8) | %[i]
    %assign i i+1
    %endrep

    dq 0 ; Sentinel
