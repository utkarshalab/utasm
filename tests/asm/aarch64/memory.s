// ============================================================================
// TEST: tests/asm/aarch64/memory.s
// Suite: AArch64 Core
// Purpose: Memory addressing mode exhaustion.
//   Covers: Base, Base+Offset, Base+Register, STP/LDP patterns,
//           pre-index, post-index, extended/shifted registers.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Base register only ---------------------------------
ldr     x0, [x1]
str     x2, [x3]
ldrb    w4, [x5]
strb    w6, [x7]
ldrh    w8, [x9]
strh    w10, [x11]
ldr     w12, [x13]
str     w14, [x15]

// ---- Base + unsigned scaled offset ----------------------
ldr     x0, [x1, #0]
ldr     x0, [x1, #8]
ldr     x0, [x1, #16]
ldr     x0, [x1, #4080]         // max 4096-aligned offset
str     x0, [x1, #4080]
ldr     w0, [x1, #4]
ldr     w0, [x1, #2044]         // max for 32-bit
ldrh    w0, [x1, #2]
ldrb    w0, [x1, #255]          // max for byte

// ---- Base + signed unscaled offset (LDUR/STUR) ----------
ldur    x0, [x1, #-1]
ldur    x0, [x1, #-8]
ldur    x0, [x1, #-256]         // min signed offset
stur    x0, [x1, #-8]
ldurb   w0, [x1, #-1]
sturb   w0, [x1, #-1]
ldurh   w0, [x1, #-2]
sturh   w0, [x1, #-2]

// ---- Pre-index (write-back before access) ---------------
ldr     x0, [x1, #8]!
str     x2, [x3, #-8]!
ldrb    w4, [x5, #1]!
strh    w6, [x7, #2]!
ldp     x0, x1, [x2, #16]!
stp     x3, x4, [x5, #-16]!

// ---- Post-index (write-back after access) ---------------
ldr     x0, [x1], #8
str     x2, [x3], #-8
ldrb    w4, [x5], #1
strh    w6, [x7], #2
ldp     x0, x1, [x2], #16
stp     x3, x4, [x5], #-16

// ---- Register offset (with optional shift) --------------
ldr     x0, [x1, x2]
str     x0, [x1, x2]
ldr     x0, [x1, x2, lsl #3]    // scaled index for 8-byte elements
str     x0, [x1, x2, lsl #3]
ldrb    w0, [x1, x2]
ldrh    w0, [x1, x2, lsl #1]
ldr     w0, [x1, x2, lsl #2]

// Extended register offset (32-bit index)
ldr     x0, [x1, w2, uxtw]
str     x0, [x1, w2, uxtw #3]
ldr     x0, [x1, w2, sxtw]
str     x0, [x1, w2, sxtw #2]

// ---- Zero register as index ----------------------------
str     xzr, [x0]               // store zero
str     wzr, [x0, #4]
ldr     xzr, [x0]               // prefetch / discard

// ---- SP as base register --------------------------------
ldr     x0, [sp]
str     x0, [sp, #8]
ldp     x0, x1, [sp]
stp     x0, x1, [sp, #16]
ldr     x0, [sp, #-8]!
str     x0, [sp, #-8]!
