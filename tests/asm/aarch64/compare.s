// ============================================================================
// TEST: tests/asm/aarch64/compare.s
// Suite: AArch64 Core
// Purpose: Comparison instruction coverage.
//   Covers: CMP, CMN, TST, CCMP, CCMN, CSEL, CSET, CSINC,
//           CSINV, CSNEG — all conditions and widths.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- CMP (compare — SUB with flags, XZR destination) ---
cmp     x0, x1
cmp     x2, #0
cmp     x3, #1
cmp     x4, #0xFFF
cmp     x5, x6, lsl #2
cmp     x7, x8, lsr #4
cmp     x9, x10, asr #8
cmp     w11, w12
cmp     w13, #0xFF

// ---- CMN (compare negative — ADD with flags, XZR dst) --
cmn     x0, x1
cmn     x2, #1
cmn     x3, x4, lsl #4
cmn     w5, w6
cmn     w7, #100

// ---- TST (test bits — ANDS with XZR destination) --------
tst     x0, x1
tst     x2, #0xFF
tst     x3, #0x0F0F0F0F0F0F0F0F
tst     w4, w5
tst     w6, #0xFF

// ---- CCMP (conditional compare — CMP if condition met, else imm) ---
ccmp    x0, x1, #0,  eq
ccmp    x0, x1, #0,  ne
ccmp    x2, x3, #15, lt
ccmp    x4, x5, #4,  ge
ccmp    w6, w7, #0,  cs
ccmp    w8, w9, #1,  hi
ccmp    x10, #5, #0, mi
ccmp    x11, #0, #4, pl

// ---- CCMN (conditional compare negative) ----------------
ccmn    x0, x1, #0,  eq
ccmn    x2, x3, #15, ne
ccmn    w4, w5, #4,  lt
ccmn    x6, #1, #0,  hi

// ---- CSEL (conditional select) --------------------------
csel    x0, x1, x2, eq
csel    x3, x4, x5, ne
csel    x6, x7, x8, lt
csel    x9, x10, x11, ge
csel    w12, w13, w14, le
csel    w15, w16, w17, gt
csel    x18, x19, x20, cs
csel    x21, x22, x23, hi

// ---- CSET (conditional set — CSINC xN, xzr, xzr, ~cond) -
cset    x0, eq
cset    x1, ne
cset    x2, lt
cset    x3, ge
cset    w4, le
cset    w5, gt
cset    x6, cs
cset    x7, hi

// ---- CSETM (conditional set mask — CSINV xN, xzr, xzr, ~cond) -
csetm   x0, eq
csetm   x1, ne
csetm   w2, lt
csetm   w3, ge

// ---- CSINC (conditional select + increment) -------------
csinc   x0, x1, x2, eq
csinc   x3, x4, x5, ne
csinc   w6, w7, w8, lt

// ---- CSINV (conditional select + invert) ----------------
csinv   x0, x1, x2, eq
csinv   x3, x4, x5, ne
csinv   w6, w7, w8, ge

// ---- CSNEG (conditional select + negate) ----------------
csneg   x0, x1, x2, eq
csneg   x3, x4, x5, ne
csneg   w6, w7, w8, lt

// ---- CINC (alias — conditional increment) ---------------
cinc    x0, x1, ne
cinc    w2, w3, eq

// ---- CINV (alias — conditional invert) ------------------
cinv    x0, x1, eq
cinv    w2, w3, ne

// ---- CNEG (alias — conditional negate) ------------------
cneg    x0, x1, eq
cneg    w2, w3, ne
