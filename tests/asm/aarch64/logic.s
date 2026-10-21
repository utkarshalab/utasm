// ============================================================================
// TEST: tests/asm/aarch64/logic.s
// Suite: AArch64 Core
// Purpose: Logical/bitwise instruction coverage.
//   Covers: AND, ORR, EOR, EON, BIC, ORN, ANDS, TST, CLZ, CLS,
//           RBIT, REV, REV16, REV32 — all register widths.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- AND (bitwise AND) ----------------------------------
and     x0, x1, x2
and     w3, w4, w5
and     x6, x7, x8, lsl #4
and     x9, x10, x11, lsr #8
and     x12, x13, x14, asr #16
and     x15, x16, x17, ror #24

// AND with immediate (bitmask immediate encoding)
and     x0, x1, #0xFF
and     x2, x3, #0xFFFFFFFF
and     x4, x5, #0x0F0F0F0F0F0F0F0F
and     w6, w7, #0xFF
and     w8, w9, #0x0F0F0F0F

// ---- ANDS (AND and set flags) ---------------------------
ands    x0, x1, x2
ands    w3, w4, w5
ands    x6, x7, #0xFF

// ---- TST (test — alias for ANDS with XZR destination) --
tst     x0, x1
tst     w2, w3
tst     x4, #0xFF
tst     w5, #0x0F

// ---- ORR (bitwise OR) -----------------------------------
orr     x0, x1, x2
orr     w3, w4, w5
orr     x6, x7, x8, lsl #8
orr     x9, x10, #0xFF
orr     w11, w12, #0xF0F0F0F0

// ---- EOR (bitwise XOR) ----------------------------------
eor     x0, x1, x2
eor     w3, w4, w5
eor     x6, x7, x8, lsl #16
eor     x9, x10, #0xFF
eor     w11, w12, #0x0000FFFF

// ---- BIC (bit clear — AND with complement) --------------
bic     x0, x1, x2
bic     w3, w4, w5
bic     x6, x7, x8, lsl #4

// ---- BICS (BIC and set flags) ---------------------------
bics    x0, x1, x2
bics    w3, w4, w5

// ---- ORN (OR with complement) ----------------------------
orn     x0, x1, x2
orn     w3, w4, w5
orn     x6, x7, x8, lsl #8

// ---- EON (XOR with complement) ---------------------------
eon     x0, x1, x2
eon     w3, w4, w5
eon     x6, x7, x8, lsr #4

// ---- CLZ (count leading zeros) -------------------------
clz     x0, x1
clz     w2, w3

// ---- CLS (count leading sign bits) ---------------------
cls     x0, x1
cls     w2, w3

// ---- RBIT (reverse bits) --------------------------------
rbit    x0, x1
rbit    w2, w3

// ---- REV (reverse bytes) --------------------------------
rev     x0, x1              // reverse byte order in 64-bit
rev     w2, w3              // reverse byte order in 32-bit

// ---- REV16 (reverse bytes in each 16-bit halfword) -----
rev16   x0, x1
rev16   w2, w3

// ---- REV32 (reverse bytes in each 32-bit word) ----------
rev32   x0, x1              // 64-bit only

// ---- MOV (register — alias for ORR xN, xzr, xM) --------
mov     x0, x1              // these are ORR encodings
mov     w2, w3
