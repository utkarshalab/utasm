// ============================================================================
// TEST: tests/asm/aarch64/store.s
// Suite: AArch64 Core
// Purpose: Store instruction coverage — STR, STRB, STRH, STP,
//          STXR/STLXR atomics, all addressing modes.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- STR (64-bit) — all addressing modes ----------------
str     x0, [x1]
str     x2, [x3, #8]
str     x4, [x5, #0]
str     x6, [x7, #4080]             // max pimm9
str     x8, [x9, #-256]
str     x10, [x11, x12]
str     x13, [x14, x15, lsl #3]
str     x16, [x17, w18, uxtw]
str     x19, [x20, w21, sxtw #3]

// Pre-index
str     x0, [x1, #8]!
str     x2, [x3, #16]!
str     x4, [x5, #-8]!

// Post-index
str     x0, [x1], #8
str     x2, [x3], #16
str     x4, [x5], #-8

// ---- STR (32-bit) ---------------------------------------
str     w0, [x1]
str     w2, [x3, #4]
str     w4, [x5, x6, lsl #2]

// ---- STRB / STRH ----------------------------------------
strb    w0, [x1]
strb    w2, [x3, #1]
strb    w4, [x5, #255]
strh    w6, [x7]
strh    w8, [x9, #2]
strh    w10, [x11, x12, lsl #1]

// ---- STP (store pair) -----------------------------------
stp     x0, x1, [x2]
stp     x3, x4, [x5, #16]
stp     x6, x7, [x8, #-16]
stp     x9, x10, [x11, #32]!       // pre-index
stp     x12, x13, [x14], #16       // post-index
stp     w0, w1, [x2]
stp     w3, w4, [x5, #8]

// ---- STUR (unscaled offset) -----------------------------
stur    x0, [x1, #-1]
stur    x2, [x3, #-8]
stur    x4, [x5, #-255]
stur    w6, [x7, #-4]
sturb   w8, [x9, #-1]
sturh   w10, [x11, #-2]

// ---- Exclusive store (atomics) --------------------------
stxr    w0, x1, [x2]               // store exclusive 64-bit (w0=status)
stxr    w0, w3, [x4]               // store exclusive 32-bit
stxrb   w0, w5, [x6]
stxrh   w0, w7, [x8]
stxp    w0, x1, x2, [x3]           // store exclusive pair
stlxr   w0, x9, [x10]             // store release exclusive
stlxr   w0, w11, [x12]
stlxrb  w0, w13, [x14]
stlxrh  w0, w15, [x16]
stlxp   w0, x1, x2, [x3]
stlr    x17, [x18]                 // store release (non-exclusive)
stlr    w19, [x20]
stlrb   w21, [x22]
stlrh   w23, [x24]

// ---- Non-temporal store --------------------------------
stnp    x0, x1, [x2]
stnp    x3, x4, [x5, #16]
stnp    w6, w7, [x8]
