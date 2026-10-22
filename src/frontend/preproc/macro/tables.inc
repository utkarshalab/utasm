; ============================================================================
; File        : src/frontend/preproc/macro/tables.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : the directive names and the preprocessor's other string tables
; ============================================================================



[SECTION .rodata]
s_dot:          db ".", 0             ; (..@N.name)
dir_inc:    db "include", 0
dir_require: db "require", 0
dir_def:    db "define", 0
dir_assign: db "assign", 0
dir_push:   db "push", 0
dir_pop:    db "pop", 0
dir_ifctx:  db "ifctx", 0
dir_ifidni:   db "ifidni", 0
dir_elifidni: db "elifidni", 0
dir_elif:     db "elif", 0
dir_error:    db "error", 0
dir_strlen:   db "strlen", 0
dir_substr:   db "substr", 0
dir_rotate:   db "rotate", 0
dir_def_short: db "def", 0          ; utasm short forms: %def, %inc
dir_inc_short: db "inc", 0
dir_xdefine:  db "xdefine", 0       ; %define is already expanded eagerly
dir_rmacro:   db "rmacro", 0
dir_imacro:   db "imacro", 0
dir_irmacro:  db "irmacro", 0
[SECTION .data]
align 8
; prep_idn_collect's buffers: pointer, capacity (they grow)
idn_left:      dq idn_left_buf, IDN_BUF
idn_right:     dq idn_right_buf, IDN_BUF
[SECTION .data]
align 8
def_toks:      dq def_scratch      ; a %define's tokens: def_scratch, or an
                                   ; arena array once it outgrows it
[SECTION .data]
align 8
stk_reg:      dq stk_modes + 10      ; %stacksize: flat until set
stk_size:     dd 4
stk_arg:      dd 8
stk_local:    dd 0
[SECTION .rodata]
dir_arg:      db "arg", 0
dir_local:    db "local", 0
stk_define:   db "%define ", 0
stk_assign:   db "%assign %$localsize %$localsize+", 0
; %stacksize: name (8), slot size, first argument, frame register (6)
stk_modes:    db "flat", 0, 0, 0, 0, 4, 8, "ebp", 0, 0, 0
              db "flat64", 0, 0, 8, 16, "rbp", 0, 0, 0
              db "large", 0, 0, 0, 2, 4, "bp", 0, 0, 0, 0
              db "small", 0, 0, 0, 2, 6, "bp", 0, 0, 0, 0
              db 0
; %arg / %local types: name (7), size
stk_types:    db "byte", 0, 0, 0, 1
              db "word", 0, 0, 0, 2
              db "dword", 0, 0, 4
              db "qword", 0, 0, 8
              db "tword", 0, 0, 10
              db 0
dir_undef:    db "undef", 0
dir_idefine:  db "idefine", 0       ; treated as %define
; more directives: 15-byte name + handler number (see .more_table)
dir_more:     db "ifidn", 0, 0,0,0,0,0,0,0,0,0, 0
              db "ifnidn", 0, 0,0,0,0,0,0,0,0, 1
              db "ifnidni", 0, 0,0,0,0,0,0,0, 2
              db "elifidn", 0, 0,0,0,0,0,0,0, 3
              db "warning", 0, 0,0,0,0,0,0,0, 4
              db "fatal", 0, 0,0,0,0,0,0,0,0,0, 5
              db "exitrep", 0, 0,0,0,0,0,0,0, 6
              db "strcat", 0, 0,0,0,0,0,0,0,0, 7
              db "deftok", 0, 0,0,0,0,0,0,0,0, 8
              db "defstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 9
              db "imacro", 0, 0, 0, 0, 0, 0, 0, 0, 0, 10
              db "exitmacro", 0, 0, 0, 0, 0, 0, 11
              db "repl", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12
              db "line", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13
              db "use", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14
              db "pragma", 0, 0, 0, 0, 0, 0, 0, 0, 0, 15
              db "clear", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16
              db "iassign", 0, 0, 0, 0, 0, 0, 0, 0, 17
              db "defalias", 0, 0, 0, 0, 0, 0, 0, 18
              db "undefalias", 0, 0, 0, 0, 0, 30
              db "idefalias", 0, 0, 0, 0, 0, 0, 31
              db "aliases", 0, 0, 0, 0, 0, 0, 0, 0, 32
              db "ifdefalias", 0, 0, 0, 0, 0, 104
              db "ifndefalias", 0, 0, 0, 0, 105
              db "elifdefalias", 0, 0, 0, 106
              db "elifndefalias", 0, 0, 107
              db "idefstr", 0, 0, 0, 0, 0, 0, 0, 0, 19
              db "ifnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68
              db "ifnnum", 0, 0, 0, 0, 0, 0, 0, 0, 0, 69
              db "elifnum", 0, 0, 0, 0, 0, 0, 0, 0, 70
              db "elifnnum", 0, 0, 0, 0, 0, 0, 0, 71
              db "ifstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 72
              db "ifnstr", 0, 0, 0, 0, 0, 0, 0, 0, 0, 73
              db "elifstr", 0, 0, 0, 0, 0, 0, 0, 0, 74
              db "elifnstr", 0, 0, 0, 0, 0, 0, 0, 75
              db "ifid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 76
              db "ifnid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 77
              db "elifid", 0, 0, 0, 0, 0, 0, 0, 0, 0, 78
              db "elifnid", 0, 0, 0, 0, 0, 0, 0, 0, 79
              db "ifempty", 0, 0, 0, 0, 0, 0, 0, 0, 80
              db "ifnempty", 0, 0, 0, 0, 0, 0, 0, 81
              db "elifempty", 0, 0, 0, 0, 0, 0, 82
              db "elifnempty", 0, 0, 0, 0, 0, 83
              db "ifmacro", 0, 0, 0, 0, 0, 0, 0, 0, 84
              db "ifnmacro", 0, 0, 0, 0, 0, 0, 0, 85
              db "elifmacro", 0, 0, 0, 0, 0, 0, 86
              db "elifnmacro", 0, 0, 0, 0, 0, 87
              db "elifdef", 0, 0, 0, 0, 0, 0, 0, 0, 90
              db "elifndef", 0, 0, 0, 0, 0, 0, 0, 91
              db "ifnctx", 0, 0, 0, 0, 0, 0, 0, 0, 0, 93
              db "elifctx", 0, 0, 0, 0, 0, 0, 0, 0, 94
              db "elifnctx", 0, 0, 0, 0, 0, 0, 0, 95
              db "ifenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 96
              db "ifnenv", 0, 0, 0, 0, 0, 0, 0, 0, 0, 97
              db "elifenv", 0, 0, 0, 0, 0, 0, 0, 0, 98
              db "elifnenv", 0, 0, 0, 0, 0, 0, 0, 99
              db "iftoken", 0, 0, 0, 0, 0, 0, 0, 0, 100
              db "ifntoken", 0, 0, 0, 0, 0, 0, 0, 101
              db "eliftoken", 0, 0, 0, 0, 0, 0, 102
              db "elifntoken", 0, 0, 0, 0, 0, 103
              db "ifn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 20
              db "elifn", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 21
              db "ixdefine", 0, 0, 0, 0, 0, 0, 0, 22
              db "rmacro", 0, 0, 0, 0, 0, 0, 0, 0, 0, 23
              db "irmacro", 0, 0, 0, 0, 0, 0, 0, 0, 24
              db "depend", 0, 0, 0, 0, 0, 0, 0, 0, 0, 25
              db "pathsearch", 0, 0, 0, 0, 0, 26
              db "stacksize", 0, 0, 0, 0, 0, 0, 27
              db "arg", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 28
              db "local", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 29
              db 0
; ---- predefined macro names ---------------
%define DYN_LINE    1
%define DYN_FILE    2
%define DYN_BITS    3
%define DYN_PASS    4
%define DYN_FORMAT  5
%define DYN_SECT    6
pd_major:    db "__NASM_MAJOR__", 0
pd_major_q:  db "__?NASM_MAJOR?__", 0
pd_minor:    db "__NASM_MINOR__", 0
pd_minor_q:  db "__?NASM_MINOR?__", 0
pd_sub:      db "__NASM_SUBMINOR__", 0
pd_patch:    db "__NASM_PATCHLEVEL__", 0
pd_verid:    db "__NASM_VERSION_ID__", 0
pd_ver:      db "__NASM_VER__", 0
pd_ver_q:    db "__?NASM_VER?__", 0
pd_utasm:    db "__UTASM__", 0
; the time of assembly (src/lib/time.s)
pt_date:      db "__DATE__", 0
pt_date_q:    db "__?DATE?__", 0
pt_time:      db "__TIME__", 0
pt_time_q:    db "__?TIME?__", 0
pt_date_num:  db "__DATE_NUM__", 0
pt_date_num_q: db "__?DATE_NUM?__", 0
pt_time_num:  db "__TIME_NUM__", 0
pt_time_num_q: db "__?TIME_NUM?__", 0
pt_utc_date:  db "__UTC_DATE__", 0
pt_utc_date_q: db "__?UTC_DATE?__", 0
pt_utc_time:  db "__UTC_TIME__", 0
pt_utc_time_q: db "__?UTC_TIME?__", 0
pt_utc_date_num: db "__UTC_DATE_NUM__", 0
pt_utc_date_num_q: db "__?UTC_DATE_NUM?__", 0
pt_utc_time_num: db "__UTC_TIME_NUM__", 0
pt_utc_time_num_q: db "__?UTC_TIME_NUM?__", 0
pt_posix_time: db "__POSIX_TIME__", 0
pt_posix_time_q: db "__?POSIX_TIME?__", 0
pv_2:        db "2", 0
pv_16:       db "16", 0
pv_3:        db "3", 0
pv_0:        db "0", 0
pv_1:        db "1", 0
pv_verid:    db "0x02100300", 0
pv_ver:      db "2.16.03", 0
dn_line:     db "__LINE__", 0
dn_line_q:   db "__?LINE?__", 0
dn_file:     db "__FILE__", 0
dn_file_q:   db "__?FILE?__", 0
dn_bits:     db "__BITS__", 0
dn_bits_q:   db "__?BITS?__", 0
dn_pass:     db "__PASS__", 0
dn_pass_q:   db "__?PASS?__", 0
dn_fmt:      db "__OUTPUT_FORMAT__", 0
dn_fmt_q:    db "__?OUTPUT_FORMAT?__", 0
dyn_sect_name: db "__SECT__", 0
dn_sect_q:   db "__?SECT?__", 0
dyn_fmt_bin: db "bin", 0
dyn_fmt_elf64: db "elf64", 0
dyn_fmt_elf32: db "elf32", 0
dyn_fmt_win64: db "win64", 0
dyn_section_word: db "section", 0
dyn_no_file: db 0
use_altreg:  db "altreg", 0
use_fp:      db "fp", 0
; NASM's fp package; the leading newline ends the %use line first
use_smartalign: db "smartalign", 0
use_smartalign_text: db 10
             db "%define __?USE_SMARTALIGN?__", 10
use_smartalign_text_len equ $ - use_smartalign_text
use_fp_text: db 10
             db "%define __?USE_FP?__", 10
             db "%define float8(x) __float8__(x)", 10
             db "%define float16(x) __float16__(x)", 10
             db "%define bfloat16(x) __bfloat16__(x)", 10
             db "%define float32(x) __float32__(x)", 10
             db "%define float64(x) __float64__(x)", 10
             db "%define float80m(x) __float80m__(x)", 10
             db "%define float80e(x) __float80e__(x)", 10
             db "%define float128l(x) __float128l__(x)", 10
             db "%define float128h(x) __float128h__(x)", 10
             db "%define Inf __Infinity__", 10
             db "%define NaN __QNaN__", 10
             db "%define QNaN __QNaN__", 10
             db "%define SNaN __SNaN__", 10
             db "%imacro bf16 1-*.nolist", 10       ; bf16 1.0, NaN: bfloat16 words
             db "  %rep %0", 10
             db "    dw __?bfloat16?__(%1)", 10
             db "    %rotate 1", 10
             db "  %endrep", 10
             db "%endmacro", 10
use_fp_text_len equ $ - use_fp_text
; NASM's ifunc package: integer log2 (parser_evaluate_factor has the
; __?ilog2?__ functions)
use_ifunc:   db "ifunc", 0
use_ifunc_text: db 10
             db "%define __?USE_IFUNC?__", 10
             db "%define ilog2(x) (__?ilog2e?__(x))", 10
             db "%define ilog2e(x) (__?ilog2e?__(x))", 10
             db "%define ilog2w(x) (__?ilog2w?__(x))", 10
             db "%define ilog2fw(x) (__?ilog2w?__(x))", 10
             db "%define ilog2f(x) (__?ilog2f?__(x))", 10
             db "%define ilog2cw(x) (__?ilog2w?__(x) * 0 + __?ilog2c?__(x))", 10
             db "%define ilog2c(x) (__?ilog2c?__(x))", 10
use_ifunc_text_len equ $ - use_ifunc_text
; NASM's masm package: MASM's segment / ends, proc / endp (ret far or
; near), end, ptr, flat, offset and tbyte; and default rel. The parser
; reads __?masm_ptr?__ (a memory operand, brackets or not) and
; __?masm_flat?__ ("flat:" nothing)
use_masm:    db "masm", 0
use_masm_text: db 10
             db "%define __?USE_MASM?__", 10
             db "%imacro segment 0-1+.nolist", 10
             db "%define __?SECT?__ [segment %00 %1]", 10
             db "[segment %00 %1]", 10
             db "%endmacro", 10
             db "%idefine ptr __?masm_ptr?__", 10
             db "%idefine flat __?masm_flat?__", 10
             db "%idefine offset __?masm_offset?__", 10
             db "%imacro end 0+.nolist", 10
             db "%endmacro", 10
             db "%idefine tbyte tword", 10
             db "default rel", 10
use_masm_text_len equ $ - use_masm_text
alt_n0: db "r0", 0
alt_v0: db "rax", 0
alt_n1: db "r0d", 0
alt_v1: db "eax", 0
alt_n2: db "r0w", 0
alt_v2: db "ax", 0
alt_n3: db "r0b", 0
alt_v3: db "al", 0
alt_n4: db "r0l", 0
alt_v4: db "al", 0
alt_n5: db "r1", 0
alt_v5: db "rcx", 0
alt_n6: db "r1d", 0
alt_v6: db "ecx", 0
alt_n7: db "r1w", 0
alt_v7: db "cx", 0
alt_n8: db "r1b", 0
alt_v8: db "cl", 0
alt_n9: db "r1l", 0
alt_v9: db "cl", 0
alt_n10: db "r2", 0
alt_v10: db "rdx", 0
alt_n11: db "r2d", 0
alt_v11: db "edx", 0
alt_n12: db "r2w", 0
alt_v12: db "dx", 0
alt_n13: db "r2b", 0
alt_v13: db "dl", 0
alt_n14: db "r2l", 0
alt_v14: db "dl", 0
alt_n15: db "r3", 0
alt_v15: db "rbx", 0
alt_n16: db "r3d", 0
alt_v16: db "ebx", 0
alt_n17: db "r3w", 0
alt_v17: db "bx", 0
alt_n18: db "r3b", 0
alt_v18: db "bl", 0
alt_n19: db "r3l", 0
alt_v19: db "bl", 0
alt_n20: db "r4", 0
alt_v20: db "rsp", 0
alt_n21: db "r4d", 0
alt_v21: db "esp", 0
alt_n22: db "r4w", 0
alt_v22: db "sp", 0
alt_n23: db "r4b", 0
alt_v23: db "spl", 0
alt_n24: db "r4l", 0
alt_v24: db "spl", 0
alt_n25: db "r5", 0
alt_v25: db "rbp", 0
alt_n26: db "r5d", 0
alt_v26: db "ebp", 0
alt_n27: db "r5w", 0
alt_v27: db "bp", 0
alt_n28: db "r5b", 0
alt_v28: db "bpl", 0
alt_n29: db "r5l", 0
alt_v29: db "bpl", 0
alt_n30: db "r6", 0
alt_v30: db "rsi", 0
alt_n31: db "r6d", 0
alt_v31: db "esi", 0
alt_n32: db "r6w", 0
alt_v32: db "si", 0
alt_n33: db "r6b", 0
alt_v33: db "sil", 0
alt_n34: db "r6l", 0
alt_v34: db "sil", 0
alt_n35: db "r7", 0
alt_v35: db "rdi", 0
alt_n36: db "r7d", 0
alt_v36: db "edi", 0
alt_n37: db "r7w", 0
alt_v37: db "di", 0
alt_n38: db "r7b", 0
alt_v38: db "dil", 0
alt_n39: db "r7l", 0
alt_v39: db "dil", 0
alt_n40: db "r0h", 0
alt_v40: db "ah", 0
alt_n41: db "r1h", 0
alt_v41: db "ch", 0
alt_n42: db "r2h", 0
alt_v42: db "dh", 0
alt_n43: db "r3h", 0
alt_v43: db "bh", 0
idn_unknown: db "?", 0
; token kinds without text: kind, text (NUL-terminated, 4 bytes a row)
idn_assign: db "=", 0
idn_punct:
    db TOK_LBRACKET, "[", 0, 0
    db TOK_RBRACKET, "]", 0, 0
    db TOK_LPAREN, "(", 0, 0
    db TOK_RPAREN, ")", 0, 0
    db TOK_COMMA, ",", 0, 0
    db TOK_COLON, ":", 0, 0
    db TOK_PLUS, "+", 0, 0
    db TOK_MINUS, "-", 0, 0
    db TOK_STAR, "*", 0, 0
    db TOK_SLASH, "/", 0, 0
    db TOK_PERCENT, "%", 0, 0
    db TOK_AMPERSAND, "&", 0, 0
    db TOK_PIPE, "|", 0, 0
    db TOK_CARET, "^", 0, 0
    db TOK_TILDE, "~", 0, 0
    db TOK_LSHIFT, "<<", 0
    db TOK_RSHIFT, ">>", 0
    db TOK_EQUAL, "==", 0
    db TOK_NEQUAL, "!=", 0
    db TOK_LT, "<", 0, 0
    db TOK_GT, ">", 0, 0
    db TOK_LE, "<=", 0
    db TOK_GE, ">=", 0
    db TOK_DOLLAR, "$", 0, 0
    db TOK_LBRACE, "{", 0, 0
    db TOK_RBRACE, "}", 0, 0
    db TOK_QUESTION, "?", 0, 0
    db TOK_NOT, "!", 0, 0
    db 0
align 8
; name, value, token kind (0: an empty definition)
predef_table:
    dq pd_major, pv_2, TOK_NUMBER
    dq pd_major_q, pv_2, TOK_NUMBER
    dq pd_minor, pv_16, TOK_NUMBER
    dq pd_minor_q, pv_16, TOK_NUMBER
    dq pd_sub, pv_3, TOK_NUMBER
    dq pd_patch, pv_0, TOK_NUMBER
    dq pd_verid, pv_verid, TOK_NUMBER
    dq pd_ver, pv_ver, TOK_STRING
    dq pd_ver_q, pv_ver, TOK_STRING
    dq pd_utasm, pv_1, TOK_NUMBER
    dq pt_date, time_local, TOK_STRING
    dq pt_date_q, time_local, TOK_STRING
    dq pt_time, time_local + 16, TOK_STRING
    dq pt_time_q, time_local + 16, TOK_STRING
    dq pt_date_num, time_local + 32, TOK_NUMBER
    dq pt_date_num_q, time_local + 32, TOK_NUMBER
    dq pt_time_num, time_local + 48, TOK_NUMBER
    dq pt_time_num_q, time_local + 48, TOK_NUMBER
    dq pt_utc_date, time_utc, TOK_STRING
    dq pt_utc_date_q, time_utc, TOK_STRING
    dq pt_utc_time, time_utc + 16, TOK_STRING
    dq pt_utc_time_q, time_utc + 16, TOK_STRING
    dq pt_utc_date_num, time_utc + 32, TOK_NUMBER
    dq pt_utc_date_num_q, time_utc + 32, TOK_NUMBER
    dq pt_utc_time_num, time_utc + 48, TOK_NUMBER
    dq pt_utc_time_num_q, time_utc + 48, TOK_NUMBER
    dq pt_posix_time, time_posix, TOK_NUMBER
    dq pt_posix_time_q, time_posix, TOK_NUMBER
    dq dn_line, 0, 0
    dq dn_file, 0, 0
    dq dn_bits, 0, 0
    dq dn_pass, 0, 0
    dq dn_fmt, 0, 0
    dq dyn_sect_name, 0, 0
    dq 0
; %use altreg: name, register
altreg_table:
    dq alt_n0, alt_v0
    dq alt_n1, alt_v1
    dq alt_n2, alt_v2
    dq alt_n3, alt_v3
    dq alt_n4, alt_v4
    dq alt_n5, alt_v5
    dq alt_n6, alt_v6
    dq alt_n7, alt_v7
    dq alt_n8, alt_v8
    dq alt_n9, alt_v9
    dq alt_n10, alt_v10
    dq alt_n11, alt_v11
    dq alt_n12, alt_v12
    dq alt_n13, alt_v13
    dq alt_n14, alt_v14
    dq alt_n15, alt_v15
    dq alt_n16, alt_v16
    dq alt_n17, alt_v17
    dq alt_n18, alt_v18
    dq alt_n19, alt_v19
    dq alt_n20, alt_v20
    dq alt_n21, alt_v21
    dq alt_n22, alt_v22
    dq alt_n23, alt_v23
    dq alt_n24, alt_v24
    dq alt_n25, alt_v25
    dq alt_n26, alt_v26
    dq alt_n27, alt_v27
    dq alt_n28, alt_v28
    dq alt_n29, alt_v29
    dq alt_n30, alt_v30
    dq alt_n31, alt_v31
    dq alt_n32, alt_v32
    dq alt_n33, alt_v33
    dq alt_n34, alt_v34
    dq alt_n35, alt_v35
    dq alt_n36, alt_v36
    dq alt_n37, alt_v37
    dq alt_n38, alt_v38
    dq alt_n39, alt_v39
    dq alt_n40, alt_v40
    dq alt_n41, alt_v41
    dq alt_n42, alt_v42
    dq alt_n43, alt_v43
    dq 0
; the ones with a value of the moment: name, DYN_*
dyn_table:
    dq dn_line, DYN_LINE
    dq dn_line_q, DYN_LINE
    dq dn_file, DYN_FILE
    dq dn_file_q, DYN_FILE
    dq dn_bits, DYN_BITS
    dq dn_bits_q, DYN_BITS
    dq dn_pass, DYN_PASS
    dq dn_pass_q, DYN_PASS
    dq dn_fmt, DYN_FORMAT
    dq dn_fmt_q, DYN_FORMAT
    dq dyn_sect_name, DYN_SECT
    dq dn_sect_q, DYN_SECT
    dq 0
str_nolist:   db ".nolist", 0
msg_space:    db " ", 0
; "0".."9" for the %N references of a function-like %define
def_digits:   db "0", 0, "1", 0, "2", 0, "3", 0, "4", 0, "5", 0, "6", 0, "7", 0, "8", 0, "9", 0
global undef_name                   ; (symbol_grow leaves these out)
undef_name:   db 0                  ; the name of an %undef'd entry
dir_if:     db "if", 0
dir_ifdef:  db "ifdef", 0
dir_ifndef: db "ifndef", 0
dir_else:   db "else", 0
dir_endif:  db "endif", 0
dir_rep:    db "rep", 0
dir_endrep: db "endrep", 0
dir_macro:  db "macro", 0
dir_endm:   db "endmacro", 0
dir_endm_short: db "endm", 0
s_macro_defaults: db "too many default macro parameters in macro `", 0
s_macro_redef:  db "redefining multi-line macro `", 0
s_quote_end: db "'", 0
s_unmacro:  db "unmacro", 0
s_ifmacro:  db "ifmacro", 0
s_ifnmacro: db "ifnmacro", 0
; NASM's directives that are multi-line macros of its own (standard.mac,
; outbin.mac, outelf.mac, outcoff.mac), for %ifmacro: the name, its
; parameter counts (0xFF: any number more), the formats (0 all, 1 bin,
; 2 ELF, 3 COFF)
builtin_macros:
    db "section", 0, 1, 0xFF, 0
    db "segment", 0, 1, 0xFF, 0
    db "sectalign", 0, 1, 0xFF, 0
    db "absolute", 0, 1, 0xFF, 0
    db "struc", 0, 1, 2, 0
    db "endstruc", 0, 0, 0, 0
    db "istruc", 0, 1, 1, 0
    db "at", 0, 1, 0xFF, 0
    db "iend", 0, 0, 0, 0
    db "align", 0, 1, 0xFF, 0
    db "alignb", 0, 1, 0xFF, 0
    db "bits", 0, 1, 0xFF, 0
    db "use16", 0, 0, 0, 0
    db "use32", 0, 0, 0, 0
    db "use64", 0, 0, 0, 0
    db "extern", 0, 1, 0xFF, 0
    db "static", 0, 1, 0xFF, 0
    db "global", 0, 1, 0xFF, 0
    db "required", 0, 1, 0xFF, 0
    db "common", 0, 1, 0xFF, 0
    db "cpu", 0, 1, 0xFF, 0
    db "float", 0, 1, 0xFF, 0
    db "default", 0, 1, 0xFF, 0
    db "userel", 0, 0, 0, 0
    db "useabs", 0, 0, 0, 0
    db "usebnd", 0, 0, 0, 0
    db "usenobnd", 0, 0, 0, 0
    db "incbin", 0, 1, 0xFF, 0
    db "org", 0, 1, 0xFF, 1
    db "osabi", 0, 1, 0xFF, 2
    db "export", 0, 1, 0xFF, 3
    db "safeseh", 0, 1, 1, 3
    db 0
dir_struc:  db "struc", 0
dir_endstruc: db "endstruc", 0
dir_unmacro:  db "unmacro", 0
dir_unimacro: db "unimacro", 0

msg_preprocessor_dir_trace: db "[+] PREP: Directive: ", 0
msg_newline:                db 10, 0

dbg_msg1:     db "prep_handle_directive: kind=", 0
dbg_msg2:     db " value=", 0
dbg_msg3:     db " (not directive)", 0
dbg_msg_null: db "<null>", 0
dbg_newline:  db 10, 0
; a %define's marked parameters (prep_handle_def, prep_def_marks)
def_radix_letters: db "bydtoqhx", 0
s_fn_str:     db "str", 0
s_fn_condstr: db "&&", 0             ; %&&(x): no name a source can spell
s_fn_eval:    db "eval", 0
s_dir_else:   db "%else", 0
s_rep_nolist: db ".nolist", 0
s_dir_endif:  db "%endif", 0
s_trailing_after:   db "trailing garbage after `", 0
s_trailing_ignored: db "' ignored", 0
s_trailing_expr:    db "trailing garbage after expression ignored", 0
s_else_after_else:  db "`%else' after `%else', ignoring content", 0
s_elif_after_else:  db "`%elif' after `%else', ignoring content", 0
s_fn_empty:   db 0                 ; fn_string: an empty argument
s_fn_mapi:    db "mapi", 0
s_fn_mapn:    db "mapn", 0
s_tok_mapi:   db "%mapi", 0         ; ... as the tokens NASM leaves
s_tok_mapn:   db "%mapn", 0
[SECTION .data]
s_fn_radix:   db "=", 0, 0, 0       ; %=(x): its radix letter and s / u filled in

; ---- prep_handle_struc ------------------
;
[SECTION .text]
; prep_handle_struc
    push    rbx
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Lex the struct name
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    
    ; 2. Dispatch to parser
    mov     rdi, rbx               ; rdi = PrepState
    mov     rsi, rdx               ; rsi = Name Token
    extern  parser_parse_struc
    call    parser_parse_struc
    
.error:
    pop     rbx
    ret
