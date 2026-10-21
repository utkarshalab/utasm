// ============================================================================
// TEST: tests/asm/aarch64/load.s
// Suite: AArch64 Core
// Purpose: Load instruction coverage — LDR, LDRB, LDRH, LDRSB, LDRSH,
//          LDRSW, LDP, LDXR/LDAXR atomics, all addressing modes.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- LDR (64-bit) — all addressing modes ----------------
ldr     x0, [x1]                    // base register, offset=0
ldr     x2, [x3, #8]                // base + unsigned offset
ldr     x4, [x5, #0]                // explicit zero offset
ldr     x6, [x7, #4080]             // max unsigned (pimm9)
ldr     x8, [x9, #-256]             // pre-index or signed offset
ldr     x10, [x11, #255]            // signed offset max
ldr     x12, [x13, x14]             // register offset
ldr     x15, [x16, x17, lsl #3]     // register offset + shift
ldr     x18, [x19, w20, uxtw]       // 32-bit index zero-ext
ldr     x21, [x22, w23, sxtw #3]    // 32-bit index sign-ext + shift

// Pre-index (update base before load)
ldr     x0, [x1, #8]!
ldr     x2, [x3, #16]!
ldr     x4, [x5, #-8]!

// Post-index (update base after load)
ldr     x0, [x1], #8
ldr     x2, [x3], #16
ldr     x4, [x5], #-8

// ---- LDRB / LDRH (zero-extending byte/halfword loads) ---
ldrb    w0, [x1]
ldrb    w2, [x3, #1]
ldrb    w4, [x5, #255]
ldrh    w6, [x7]
ldrh    w8, [x9, #2]
ldrh    w10, [x11, x12, lsl #1]

// ---- LDRSB / LDRSH / LDRSW (sign-extending) -------------
ldrsb   x0, [x1]                    // sign-extend byte to 64-bit
ldrsb   w2, [x3]                    // sign-extend byte to 32-bit
ldrsh   x4, [x5]
ldrsh   w6, [x7]
ldrsw   x8, [x9]                    // sign-extend word to 64-bit
ldrsw   x10, [x11, #4]
ldrsw   x12, [x13, x14, lsl #2]

// ---- LDR (32-bit) ---------------------------------------
ldr     w0, [x1]
ldr     w2, [x3, #4]
ldr     w4, [x5, x6, lsl #2]

// ---- LDP (load pair) ------------------------------------
ldp     x0, x1, [x2]
ldp     x3, x4, [x5, #16]
ldp     x6, x7, [x8, #-16]
ldp     x9, x10, [x11, #32]!        // pre-index
ldp     x12, x13, [x14], #16        // post-index
ldp     w0, w1, [x2]
ldp     w3, w4, [x5, #8]

// ---- LDUR (unscaled offset) -----------------------------
ldur    x0, [x1, #-1]
ldur    x2, [x3, #-8]
ldur    x4, [x5, #-255]
ldur    w6, [x7, #-4]
ldurb   w8, [x9, #-1]
ldurh   w10, [x11, #-2]
ldursb  x12, [x13, #-1]
ldursh  x14, [x15, #-2]
ldursw  x16, [x17, #-4]

// ---- Exclusive load (atomics) ---------------------------
ldxr    x0, [x1]                    // load exclusive 64-bit
ldxr    w2, [x3]                    // load exclusive 32-bit
ldxrb   w4, [x5]
ldxrh   w6, [x7]
ldxp    x0, x1, [x2]                // load exclusive pair
ldaxr   x8, [x9]                    // load acquire exclusive
ldaxr   w10, [x11]
ldaxrb  w12, [x13]
ldaxrh  w14, [x15]
ldaxp   x0, x1, [x2]
ldar    x16, [x17]                  // load acquire (non-exclusive)
ldar    w18, [x19]
ldarb   w20, [x21]
ldarh   w22, [x23]

// ---- Prefetch instructions ------------------------------
prfm    pldl1keep, [x0]
prfm    pldl1strm, [x1]
prfm    pldl2keep, [x2, #8]
prfm    pstl1keep, [x3]
