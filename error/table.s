; error/table.s
; Phase 1 — error code constants (E1xx–E9xx) and message string table
;
; Layout:
;   Section 1: equ constants for every error code
;   Section 2: null-terminated message strings
;   Section 3: per-range pointer tables (16 entries each, 0-padded)
;   Section 4: err_get_msg(code) → rax = ptr to message string, 0 on unknown
;
; Conventions:
;   - code constants are plain numbers (E101 equ 101)
;   - message strings are local labels within .rodata
;   - tables are arrays of dq pointers, one per slot
;   - unknown/gap slots point to err_msg_unknown

%include "include/constant.inc"
%include "include/macro.inc"

; ============================================================================
; Section 1 — Error code constants
; ============================================================================

; E1xx — Lexer
E101    equ 101
E102    equ 102
E103    equ 103
E104    equ 104
E105    equ 105
E106    equ 106
E107    equ 107
E108    equ 108
E109    equ 109
E110    equ 110
E111    equ 111

; E2xx — Parser
E201    equ 201
E202    equ 202
E203    equ 203
E204    equ 204
E205    equ 205
E206    equ 206
E207    equ 207
E208    equ 208
E209    equ 209
E210    equ 210
E211    equ 211
E212    equ 212
E213    equ 213
E214    equ 214
E215    equ 215
E216    equ 216
E217    equ 217
E218    equ 218
E219    equ 219
E220    equ 220
E221    equ 221
E222    equ 222
E223    equ 223
E224    equ 224

; E3xx — Preprocessor
E301    equ 301
E302    equ 302
E303    equ 303
E304    equ 304
E305    equ 305
E306    equ 306
E307    equ 307
E308    equ 308
E309    equ 309
E310    equ 310
E311    equ 311
E312    equ 312
E313    equ 313
E314    equ 314
E315    equ 315
E316    equ 316
E317    equ 317
E318    equ 318
E319    equ 319
E320    equ 320

; E4xx — Symbol Table
E401    equ 401
E402    equ 402
E403    equ 403
E404    equ 404
E405    equ 405
E406    equ 406
E407    equ 407

; E5xx — Encoder
E501    equ 501
E502    equ 502
E503    equ 503
E504    equ 504
E505    equ 505
E506    equ 506
E507    equ 507
E508    equ 508
E509    equ 509
E510    equ 510
E511    equ 511
E512    equ 512

; E6xx — Linker
E601    equ 601
E602    equ 602
E603    equ 603
E604    equ 604
E605    equ 605
E606    equ 606
E607    equ 607
E608    equ 608
E609    equ 609

; E7xx — Output
E701    equ 701
E702    equ 702
E703    equ 703
E704    equ 704
E705    equ 705

; E9xx — Internal
E901    equ 901
E902    equ 902
E903    equ 903
E904    equ 904
E905    equ 905

; ============================================================================
; Section 2 — Message strings  (read-only, null-terminated)
; ============================================================================

[SECTION .rodata]

; fallback for unknown / gap codes
err_msg_unknown:
    db  "unknown error code", 0

; ── E1xx — Lexer ─────────────────────────────────────────────────────────────
err_msg_E101: db "E101: unexpected character in input stream", 0
err_msg_E102: db "E102: unterminated string literal", 0
err_msg_E103: db "E103: unterminated character literal", 0
err_msg_E104: db "E104: invalid escape sequence in string", 0
err_msg_E105: db "E105: integer literal overflow (exceeds 64-bit range)", 0
err_msg_E106: db "E106: invalid hexadecimal digit", 0
err_msg_E107: db "E107: invalid binary digit", 0
err_msg_E108: db "E108: invalid octal digit", 0
err_msg_E109: db "E109: source file exceeds maximum size (2 GB)", 0
err_msg_E110: db "E110: source file could not be opened", 0
err_msg_E111: db "E111: source file read error", 0

; ── E2xx — Parser ────────────────────────────────────────────────────────────
err_msg_E201: db "E201: expected operand, got end of line", 0
err_msg_E202: db "E202: expected closing bracket ']'", 0
err_msg_E203: db "E203: expected closing parenthesis ')'", 0
err_msg_E204: db "E204: unknown mnemonic", 0
err_msg_E205: db "E205: invalid operand combination for instruction", 0
err_msg_E206: db "E206: expected register, got immediate", 0
err_msg_E207: db "E207: expected immediate, got register", 0
err_msg_E208: db "E208: memory operand not allowed for this instruction", 0
err_msg_E209: db "E209: invalid segment override", 0
err_msg_E210: db "E210: scale factor must be 1, 2, 4, or 8", 0
err_msg_E211: db "E211: base register not valid in this addressing mode", 0
err_msg_E212: db "E212: index register cannot be RSP/SP", 0
err_msg_E213: db "E213: displacement out of range", 0
err_msg_E214: db "E214: SECTION directive missing section name", 0
err_msg_E215: db "E215: unknown section attribute", 0
err_msg_E216: db "E216: GLOBAL directive missing symbol name", 0
err_msg_E217: db "E217: EXTERN directive missing symbol name", 0
err_msg_E218: db "E218: EQU requires a label", 0
err_msg_E219: db "E219: expression syntax error", 0
err_msg_E220: db "E220: division by zero in constant expression", 0
err_msg_E221: db "E221: STRUC/ENDSTRUC mismatch", 0
err_msg_E222: db "E222: ALIGN value must be a power of two", 0
err_msg_E223: db "E223: RESB/RESW/RESD/RESQ requires positive count", 0
err_msg_E224: db "E224: DB/DW/DD/DQ: value out of range for size", 0

; ── E3xx — Preprocessor ──────────────────────────────────────────────────────
err_msg_E301: db "E301: %define: missing macro name", 0
err_msg_E302: db "E302: %macro: missing macro name", 0
err_msg_E303: db "E303: %macro: invalid parameter count specification", 0
err_msg_E304: db "E304: %endmacro without matching %macro", 0
err_msg_E305: db "E305: %if: missing expression", 0
err_msg_E306: db "E306: %elif without matching %if", 0
err_msg_E307: db "E307: %else without matching %if", 0
err_msg_E308: db "E308: %endif without matching %if", 0
err_msg_E309: db "E309: %rep: missing count", 0
err_msg_E310: db "E310: %rep count must be a non-negative integer", 0
err_msg_E311: db "E311: %endrep without matching %rep", 0
err_msg_E312: db "E312: %include: missing filename", 0
err_msg_E313: db "E313: %include: file not found", 0
err_msg_E314: db "E314: %include: circular inclusion detected", 0
err_msg_E315: db "E315: %include: nesting depth exceeded (max 32)", 0
err_msg_E316: db "E316: macro expansion depth exceeded (max 64)", 0
err_msg_E317: db "E317: %undef: missing macro name", 0
err_msg_E318: db "E318: %assign: missing variable name or expression", 0
err_msg_E319: db "E319: %rotate without matching %macro", 0
err_msg_E320: db "E320: token paste (##) produced invalid token", 0

; ── E4xx — Symbol Table ───────────────────────────────────────────────────────
err_msg_E401: db "E401: symbol redefined", 0
err_msg_E402: db "E402: symbol table full (increase MAX_SYMBOLS)", 0
err_msg_E403: db "E403: undefined symbol", 0
err_msg_E404: db "E404: forward reference not resolved after second pass", 0
err_msg_E405: db "E405: COMMON symbol size mismatch (multiple definitions)", 0
err_msg_E406: db "E406: EXTERN symbol also defined locally", 0
err_msg_E407: db "E407: symbol name too long (max 255 bytes)", 0

; ── E5xx — Encoder ────────────────────────────────────────────────────────────
err_msg_E501: db "E501: instruction not supported for target architecture", 0
err_msg_E502: db "E502: instruction not available on target CPU profile", 0
err_msg_E503: db "E503: REX prefix required but operand size conflict", 0
err_msg_E504: db "E504: VEX/EVEX encoding conflict", 0
err_msg_E505: db "E505: AVX-512 mask register required", 0
err_msg_E506: db "E506: immediate out of range for instruction form", 0
err_msg_E507: db "E507: register size mismatch between operands", 0
err_msg_E508: db "E508: AArch64: shift amount out of range", 0
err_msg_E509: db "E509: AArch64: invalid condition code", 0
err_msg_E510: db "E510: RISC-V: branch offset out of range (+-4 KiB)", 0
err_msg_E511: db "E511: RISC-V: JAL offset out of range (+-1 MiB)", 0
err_msg_E512: db "E512: output buffer overflow", 0

; ── E6xx — Linker ─────────────────────────────────────────────────────────────
err_msg_E601: db "E601: no sections defined", 0
err_msg_E602: db "E602: _start symbol not found (standalone build)", 0
err_msg_E603: db "E603: relocation overflow: target out of range", 0
err_msg_E604: db "E604: unknown relocation type", 0
err_msg_E605: db "E605: section alignment conflict", 0
err_msg_E606: db "E606: duplicate section name", 0
err_msg_E607: db "E607: archive member not found", 0
err_msg_E608: db "E608: ELF output write error", 0
err_msg_E609: db "E609: section flag conflict (W+X not allowed)", 0

; ── E7xx — Output ─────────────────────────────────────────────────────────────
err_msg_E701: db "E701: unknown output format", 0
err_msg_E702: db "E702: output file could not be created", 0
err_msg_E703: db "E703: output file write error", 0
err_msg_E704: db "E704: PE32+: no .text section to emit", 0
err_msg_E705: db "E705: UPK: signing key not found", 0

; ── E9xx — Internal ───────────────────────────────────────────────────────────
err_msg_E901: db "E901: arena allocator out of memory", 0
err_msg_E902: db "E902: null pointer in internal API", 0
err_msg_E903: db "E903: inconsistent assembler context state", 0
err_msg_E904: db "E904: encoder dispatch table corrupt", 0
err_msg_E905: db "E905: symbol table integrity check failed", 0

; ============================================================================
; Section 3 — Per-range pointer tables
;   Each table starts at code XX1 (e.g., E101, E201).
;   Slot index = (code % 100) - 1.
;   Slots for undefined codes point to err_msg_unknown.
; ============================================================================

; E1xx table — slots 0..11 → E101..E111  (32 slots reserved for growth)
err_table_E1xx:
    dq  err_msg_E101
    dq  err_msg_E102
    dq  err_msg_E103
    dq  err_msg_E104
    dq  err_msg_E105
    dq  err_msg_E106
    dq  err_msg_E107
    dq  err_msg_E108
    dq  err_msg_E109
    dq  err_msg_E110
    dq  err_msg_E111
    ; slots 11..31 — reserved
    times 21 dq err_msg_unknown
err_table_E1xx_len equ ($ - err_table_E1xx) / 8

; E2xx table — slots 0..23 → E201..E224
err_table_E2xx:
    dq  err_msg_E201
    dq  err_msg_E202
    dq  err_msg_E203
    dq  err_msg_E204
    dq  err_msg_E205
    dq  err_msg_E206
    dq  err_msg_E207
    dq  err_msg_E208
    dq  err_msg_E209
    dq  err_msg_E210
    dq  err_msg_E211
    dq  err_msg_E212
    dq  err_msg_E213
    dq  err_msg_E214
    dq  err_msg_E215
    dq  err_msg_E216
    dq  err_msg_E217
    dq  err_msg_E218
    dq  err_msg_E219
    dq  err_msg_E220
    dq  err_msg_E221
    dq  err_msg_E222
    dq  err_msg_E223
    dq  err_msg_E224
    ; slots 24..31 — reserved
    times 8 dq err_msg_unknown
err_table_E2xx_len equ ($ - err_table_E2xx) / 8

; E3xx table — slots 0..19 → E301..E320
err_table_E3xx:
    dq  err_msg_E301
    dq  err_msg_E302
    dq  err_msg_E303
    dq  err_msg_E304
    dq  err_msg_E305
    dq  err_msg_E306
    dq  err_msg_E307
    dq  err_msg_E308
    dq  err_msg_E309
    dq  err_msg_E310
    dq  err_msg_E311
    dq  err_msg_E312
    dq  err_msg_E313
    dq  err_msg_E314
    dq  err_msg_E315
    dq  err_msg_E316
    dq  err_msg_E317
    dq  err_msg_E318
    dq  err_msg_E319
    dq  err_msg_E320
    ; slots 20..31 — reserved
    times 12 dq err_msg_unknown
err_table_E3xx_len equ ($ - err_table_E3xx) / 8

; E4xx table — slots 0..6 → E401..E407
err_table_E4xx:
    dq  err_msg_E401
    dq  err_msg_E402
    dq  err_msg_E403
    dq  err_msg_E404
    dq  err_msg_E405
    dq  err_msg_E406
    dq  err_msg_E407
    ; slots 7..31 — reserved
    times 25 dq err_msg_unknown
err_table_E4xx_len equ ($ - err_table_E4xx) / 8

; E5xx table — slots 0..11 → E501..E512
err_table_E5xx:
    dq  err_msg_E501
    dq  err_msg_E502
    dq  err_msg_E503
    dq  err_msg_E504
    dq  err_msg_E505
    dq  err_msg_E506
    dq  err_msg_E507
    dq  err_msg_E508
    dq  err_msg_E509
    dq  err_msg_E510
    dq  err_msg_E511
    dq  err_msg_E512
    ; slots 12..31 — reserved
    times 20 dq err_msg_unknown
err_table_E5xx_len equ ($ - err_table_E5xx) / 8

; E6xx table — slots 0..8 → E601..E609
err_table_E6xx:
    dq  err_msg_E601
    dq  err_msg_E602
    dq  err_msg_E603
    dq  err_msg_E604
    dq  err_msg_E605
    dq  err_msg_E606
    dq  err_msg_E607
    dq  err_msg_E608
    dq  err_msg_E609
    ; slots 9..31 — reserved
    times 23 dq err_msg_unknown
err_table_E6xx_len equ ($ - err_table_E6xx) / 8

; E7xx table — slots 0..4 → E701..E705
err_table_E7xx:
    dq  err_msg_E701
    dq  err_msg_E702
    dq  err_msg_E703
    dq  err_msg_E704
    dq  err_msg_E705
    ; slots 5..31 — reserved
    times 27 dq err_msg_unknown
err_table_E7xx_len equ ($ - err_table_E7xx) / 8

; E8xx — not yet assigned; all unknown
err_table_E8xx:
    times 32 dq err_msg_unknown
err_table_E8xx_len equ ($ - err_table_E8xx) / 8

; E9xx table — slots 0..4 → E901..E905
err_table_E9xx:
    dq  err_msg_E901
    dq  err_msg_E902
    dq  err_msg_E903
    dq  err_msg_E904
    dq  err_msg_E905
    ; slots 5..31 — reserved
    times 27 dq err_msg_unknown
err_table_E9xx_len equ ($ - err_table_E9xx) / 8

; Top-level range dispatch table (indexed by hundreds digit 1..9)
; Entry 0 is a sentinel pointing to err_msg_unknown.
err_range_table:
    dq  err_msg_unknown   ; 0xx — invalid
    dq  err_table_E1xx    ; 1xx
    dq  err_table_E2xx    ; 2xx
    dq  err_table_E3xx    ; 3xx
    dq  err_table_E4xx    ; 4xx
    dq  err_table_E5xx    ; 5xx
    dq  err_table_E6xx    ; 6xx
    dq  err_table_E7xx    ; 7xx
    dq  err_table_E8xx    ; 8xx (reserved)
    dq  err_table_E9xx    ; 9xx

; ============================================================================
; Section 4 — err_get_msg(code) → rax = ptr to message, or err_msg_unknown
;
; Input:   rdi = error code (e.g. 101, 507, 901)
; Output:  rax = pointer to null-terminated message string
; Clobbers: rcx, rdx
; ============================================================================

[SECTION .text]

global err_get_msg
err_get_msg:
    ; range = code / 100   (hundreds digit: 1–9)
    mov     rax, rdi
    mov     rcx, 100
    xor     rdx, rdx
    div     rcx                     ; rax = hundreds, rdx = remainder (0-99)

    ; bounds check: range must be 1..9
    cmp     rax, 1
    jl      .unknown
    cmp     rax, 9
    jg      .unknown

    ; slot = (code % 100) - 1   (0-based index within the range table)
    mov     rcx, rdx               ; rcx = code % 100
    test    rcx, rcx               ; slot 0 would mean code = X00, invalid
    jz      .unknown
    dec     rcx                    ; rcx = slot index (0-based)

    ; guard: slot must be 0..31
    cmp     rcx, 31
    jg      .unknown

    ; load sub-table pointer from err_range_table[rax * 8]
    lea     rdx, [rel err_range_table]
    mov     rdx, [rdx + rax * 8]  ; rdx = ptr to sub-table

    ; load message pointer: sub_table[slot * 8]
    mov     rax, [rdx + rcx * 8]
    ret

.unknown:
    lea     rax, [rel err_msg_unknown]
    ret
