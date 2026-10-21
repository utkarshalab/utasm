// ============================================================================
// TEST: tests/asm/aarch64/shift.s
// Suite: AArch64 Core
// Purpose: Shift instruction coverage.
//   Covers: LSL, LSR, ASR, ROR (register and immediate),
//           EXTR, ubfx, sbfx, bfi, bfm, ubfm, sbfm.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- LSL (logical shift left) ---------------------------
lsl     x0, x1, #0
lsl     x0, x1, #1
lsl     x0, x1, #4
lsl     x0, x1, #63
lsl     w2, w3, #0
lsl     w2, w3, #1
lsl     w2, w3, #31

// LSL by register
lsl     x4, x5, x6
lsl     w7, w8, w9

// ---- LSR (logical shift right) --------------------------
lsr     x0, x1, #1
lsr     x0, x1, #32
lsr     x0, x1, #63
lsr     w2, w3, #1
lsr     w2, w3, #31

// LSR by register
lsr     x4, x5, x6
lsr     w7, w8, w9

// ---- ASR (arithmetic shift right) ----------------------
asr     x0, x1, #1
asr     x0, x1, #32
asr     x0, x1, #63
asr     w2, w3, #1
asr     w2, w3, #31

// ASR by register
asr     x4, x5, x6
asr     w7, w8, w9

// ---- ROR (rotate right) --------------------------------
ror     x0, x1, #1
ror     x0, x1, #32
ror     x0, x1, #63
ror     w2, w3, #1
ror     w2, w3, #31

// ROR by register
ror     x4, x5, x6
ror     w7, w8, w9

// ---- EXTR (extract register — double-width shift) ------
extr    x0, x1, x2, #0
extr    x0, x1, x2, #32
extr    x0, x1, x2, #63
extr    w3, w4, w5, #0
extr    w3, w4, w5, #16
extr    w3, w4, w5, #31

// ---- Bitfield operations --------------------------------

// UBFM (unsigned bitfield move — base instruction)
ubfm    x0, x1, #0, #7      // extract bits [7:0] (alias: ubfx x0, x1, #0, #8)
ubfm    x0, x1, #8, #15     // extract bits [15:8]
ubfm    w2, w3, #4, #11
ubfm    w4, w5, #0, #31

// SBFM (signed bitfield move — base instruction)
sbfm    x0, x1, #0, #7      // sign-extend bits [7:0] (alias: sxtb)
sbfm    x0, x1, #0, #15     // sign-extend halfword (alias: sxth)
sbfm    x0, x1, #0, #31     // sign-extend word (alias: sxtw)
sbfm    w2, w3, #4, #11

// BFM (bitfield move — insert into existing bits)
bfm     x0, x1, #4, #7
bfm     w2, w3, #8, #15

// UBFX (unsigned bitfield extract — alias for UBFM)
ubfx    x0, x1, #0, #8
ubfx    x0, x1, #8, #16
ubfx    x0, x1, #32, #32
ubfx    w2, w3, #4, #12
ubfx    w4, w5, #0, #32

// SBFX (signed bitfield extract — alias for SBFM)
sbfx    x0, x1, #0, #8
sbfx    x0, x1, #16, #16
sbfx    w2, w3, #8, #16

// BFI (bitfield insert — alias for BFM)
bfi     x0, x1, #8, #8      // insert 8 bits at position 8
bfi     x0, x1, #0, #32
bfi     w2, w3, #4, #4
bfi     w4, w5, #16, #16

// BFXIL (bitfield extract and insert at low bits)
bfxil   x0, x1, #8, #8
bfxil   w2, w3, #4, #4

// ---- Sign/zero extend aliases --------------------------
sxtb    x0, w1              // sign-extend byte to 64-bit
sxth    x2, w3              // sign-extend halfword
sxtw    x4, w5              // sign-extend word
uxtb    w6, w7              // zero-extend byte to 32-bit
uxth    w8, w9              // zero-extend halfword
