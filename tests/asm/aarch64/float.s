// ============================================================================
// TEST: tests/asm/aarch64/float.s
// Suite: AArch64 FP
// Purpose: AArch64 scalar floating-point instruction coverage.
//   Covers: FADD, FSUB, FMUL, FDIV, FMADD, FMSUB, FNMADD, FNMSUB,
//           FABS, FNEG, FSQRT, FCMP, FCMPE, FMOV, FCVT, FCSEL.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Scalar FP: single precision (Sn) -------------------
fadd    s0, s1, s2
fsub    s3, s4, s5
fmul    s6, s7, s8
fdiv    s9, s10, s11
fsqrt   s12, s13
fabs    s14, s15
fneg    s16, s17
fmov    s18, s19
fmov    s20, #1.0           // immediate float

// Fused multiply-add
fmadd   s0, s1, s2, s3      // s0 = s3 + s1*s2
fmsub   s4, s5, s6, s7      // s4 = s7 - s5*s6
fnmadd  s8, s9, s10, s11    // s8 = -(s11 + s9*s10)
fnmsub  s12, s13, s14, s15  // s12 = -(s15 - s13*s14)

// Fused multiply-add (3-register form)
fmul    s0, s1, s2
fmla    s0, s1, s2           // s0 += s1*s2 (vector semantics in scalar context)
fmls    s0, s1, s2           // s0 -= s1*s2

// Max/Min
fmax    s0, s1, s2
fmin    s3, s4, s5
fmaxnm  s6, s7, s8           // max (NaN-propagating)
fminnm  s9, s10, s11

// Round
frintn  s0, s1               // round to nearest (ties-to-even)
frintp  s2, s3               // round towards +∞
frintm  s4, s5               // round towards -∞
frintz  s6, s7               // round towards zero
frinta  s8, s9               // round to nearest (ties-to-away)
frinti  s10, s11             // round using FPCR rounding mode
frintx  s12, s13             // raise inexact

// ---- Scalar FP: double precision (Dn) -------------------
fadd    d0, d1, d2
fsub    d3, d4, d5
fmul    d6, d7, d8
fdiv    d9, d10, d11
fsqrt   d12, d13
fabs    d14, d15
fneg    d16, d17
fmov    d18, d19
fmov    d20, #1.0
fmov    d21, #-0.5

fmadd   d0, d1, d2, d3
fmsub   d4, d5, d6, d7
fnmadd  d8, d9, d10, d11
fnmsub  d12, d13, d14, d15

fmax    d0, d1, d2
fmin    d3, d4, d5
frintn  d0, d1
frintz  d2, d3

// ---- FP Compare -----------------------------------------
fcmp    s0, s1
fcmp    s0, #0.0
fcmp    d0, d1
fcmp    d0, #0.0
fcmpe   s0, s1               // also raise FP exceptions
fcmpe   d0, #0.0

// ---- FCCMP (conditional FP compare) --------------------
fccmp   s0, s1, #0, eq
fccmp   d2, d3, #4, ne
fccmpe  s4, s5, #0, lt

// ---- FCSEL (FP conditional select) ---------------------
fcsel   s0, s1, s2, eq
fcsel   d3, d4, d5, ne
fcsel   s6, s7, s8, lt
fcsel   d9, d10, d11, ge

// ---- FP Convert (between types) -------------------------
fcvt    d0, s1               // single → double
fcvt    s2, d3               // double → single
fcvt    h4, s5               // single → half
fcvt    s6, h7               // half → single
fcvt    h8, d9               // double → half

// ---- FP ↔ Integer convert --------------------------------
scvtf   s0, w1               // int32 → single
scvtf   d2, w3               // int32 → double
scvtf   s4, x5               // int64 → single
scvtf   d6, x7               // int64 → double
ucvtf   s8, w9
ucvtf   d10, x11

fcvtzs  w0, s1               // single → int32 (truncate)
fcvtzs  x2, d3               // double → int64 (truncate)
fcvtzu  w4, s5
fcvtzu  x6, d7
fcvtns  w8, s9               // round to nearest signed int32
fcvtnu  w10, d11
fcvtms  x12, s13
fcvtmu  x14, d15

// ---- FMOV (FP ↔ GP register transfer) ------------------
fmov    w0, s1               // s1 → w0 (raw bits)
fmov    s2, w3               // w3 → s2 (raw bits)
fmov    x4, d5               // d5 → x4
fmov    d6, x7               // x7 → d6
