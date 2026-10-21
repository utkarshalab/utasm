// ============================================================================
// TEST: tests/asm/aarch64/arithmetic.s
// Suite: AArch64 Core
// Purpose: Exhaustive arithmetic instruction coverage.
//   Covers: ADD, SUB, MUL, MADD, MSUB, UDIV, SDIV, NEG, NGC,
//           ADDS, SUBS, ADC, SBC, CMN, CMP — all register widths (X/W).
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- ADD (register) ------------------------------------
add     x0, x1, x2
add     x3, x4, x5
add     w6, w7, w8
add     w9, w10, w11
add     x12, x13, x14, lsl #2
add     x15, x16, x17, lsr #4
add     x18, x19, x20, asr #8

// ---- ADD (immediate) ------------------------------------
add     x0, x1, #0
add     x0, x1, #1
add     x0, x1, #0xFFF        // max 12-bit immediate
add     x0, x1, #0x1000       // shifted immediate (lsl #12)
add     w0, w1, #42
add     w2, w3, #0xABC

// ---- ADDS (add and set flags) ---------------------------
adds    x0, x1, x2
adds    x3, x4, #1
adds    w5, w6, w7
adds    w8, w9, #0xFF

// ---- SUB (register / immediate) ------------------------
sub     x0, x1, x2
sub     x3, x4, x5, lsl #1
sub     w6, w7, w8
sub     x0, x1, #1
sub     x0, x1, #0xFFF
sub     w0, w1, #100
sub     w2, w3, w4, asr #4

// ---- SUBS -----------------------------------------------
subs    x0, x1, x2
subs    x3, x4, #1
subs    w5, w6, w7
subs    w8, w9, #255

// ---- ADC / SBC (with carry) ----------------------------
adc     x0, x1, x2
adc     w3, w4, w5
sbc     x6, x7, x8
sbc     w9, w10, w11
adcs    x0, x1, x2
sbcs    x3, x4, x5

// ---- NEG / NEGS (negate) --------------------------------
neg     x0, x1
neg     w2, w3
neg     x4, x5, lsl #2
negs    x6, x7

// ---- CMP (compare — sets flags, discards result) --------
cmp     x0, x1
cmp     x2, #0
cmp     x3, #0xFFF
cmp     w4, w5
cmp     w6, #255

// ---- CMN (compare negative — adds and sets flags) -------
cmn     x0, x1
cmn     x2, #1
cmn     w3, w4
cmn     w5, #100

// ---- MUL / MADD / MSUB ----------------------------------
mul     x0, x1, x2
mul     w3, w4, w5
madd    x6, x7, x8, x9          // x6 = x9 + x7*x8
msub    x10, x11, x12, x13      // x10 = x13 - x11*x12
mneg    x14, x15, x16           // x14 = -(x15*x16)

// High multiply
smulh   x0, x1, x2              // signed 128-bit multiply, high word
umulh   x3, x4, x5              // unsigned

// 32->64 multiply
smull   x0, w1, w2              // signed
umull   x3, w4, w5              // unsigned
smnegl  x6, w7, w8
umnegl  x9, w10, w11
smaddl  x12, w13, w14, x15
umaddl  x16, w17, w18, x19

// ---- UDIV / SDIV (division) ----------------------------
udiv    x0, x1, x2
sdiv    x3, x4, x5
udiv    w6, w7, w8
sdiv    w9, w10, w11

// ---- Extend-based ADD/SUB (UXTB, SXTB, UXTH, etc.) ----
add     x0, x1, w2, uxtb
add     x3, x4, w5, uxth
add     x6, x7, w8, uxtw
add     x9, x10, x11, uxtx
add     x12, x13, w14, sxtb
add     x15, x16, w17, sxth
add     x18, x19, w20, sxtw
