// ============================================================================
// TEST: tests/asm/aarch64/mov.s
// Suite: AArch64 Core
// Purpose: Data movement instruction coverage.
//   Covers: MOV (alias of ORR/MOVN/MOVZ), MOVZ, MOVN, MOVK,
//           LDR (literal), ADR, ADRP, MVN — all widths.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- MOV (register to register) -------------------------
mov     x0, x1
mov     x2, x3
mov     w4, w5
mov     w6, w7
mov     x8, xzr            // zero x8
mov     w9, wzr

// ---- MOVZ (move with zero — 16-bit imm, zero remaining) -
movz    x0, #0
movz    x0, #1
movz    x0, #0xFFFF
movz    x0, #0x1234, lsl #0
movz    x0, #0xABCD, lsl #16
movz    x0, #0x5678, lsl #32
movz    x0, #0x9ABC, lsl #48
movz    w1, #0
movz    w1, #0xFFFF
movz    w1, #0x1234, lsl #0
movz    w1, #0x5678, lsl #16

// ---- MOVN (move with NOT — complement of imm) -----------
movn    x0, #0              // x0 = ~0 = -1 = 0xFFFFFFFFFFFFFFFF
movn    x0, #1              // x0 = ~1
movn    x0, #0xFFFF
movn    x0, #0x1234, lsl #16
movn    w0, #0
movn    w0, #0xFFFF, lsl #0
movn    w0, #0x5678, lsl #16

// ---- MOVK (move keeping other bits) ---------------------
movz    x0, #0x1111             // set bits [15:0]
movk    x0, #0x2222, lsl #16    // set bits [31:16]
movk    x0, #0x3333, lsl #32    // set bits [47:32]
movk    x0, #0x4444, lsl #48    // set bits [63:48]
// Result: x0 = 0x4444333322221111

movz    w0, #0x1111
movk    w0, #0x2222, lsl #16

// ---- ADR (PC-relative address, ±1MB range) --------------
adr     x0, .Ldata
adr     x1, .Ldata2
adr     x2, .Ldata

// ---- ADRP (page-relative address, ±4GB range) -----------
adrp    x0, .Ldata
adrp    x1, .Lpage_data
adrp    x2, .Lbss_region

// ---- LDR (PC-relative literal pool load) ----------------
ldr     x0, =0x1234567890ABCDEF    // load 64-bit constant
ldr     w1, =0x12345678
ldr     x2, .Llit1
ldr     w3, .Llit2

// ---- MVN (bitwise NOT of register) ----------------------
mvn     x0, x1
mvn     x2, x3, lsl #4
mvn     w4, w5
mvn     w6, w7, lsr #8

// ---- Literal pool ----------------------------------------
[SECTION .rodata]
.Llit1:     dq 0xDEADBEEFCAFEBABE
.Llit2:     dd 0xDEADBEEF
.Ldata:     dq 0
.Ldata2:    dq 0
.Lpage_data: dq 0
.Lbss_region: dq 0
