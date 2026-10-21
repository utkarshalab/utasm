// ============================================================================
// TEST: tests/asm/riscv64/load.s
// Suite: RISC-V 64 Core
// Purpose: Load instruction coverage.
//   Covers: LB, LH, LW, LD, LBU, LHU, LWU — all sizes, all offset ranges.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- LD (load doubleword — 64-bit) ----------------------
ld      a0, 0(sp)
ld      a0, 8(sp)
ld      a0, -8(sp)
ld      a0, 2047(sp)            // max positive imm12
ld      a0, -2048(sp)           // min negative imm12
ld      a0, 0(a1)
ld      a0, 8(a1)
ld      a0, -8(a1)
ld      t0, 0(t1)
ld      s0, 16(s1)
ld      zero, 0(a0)             // discard load (prefetch)
ld      ra, 0(sp)               // restore RA from stack

// ---- LW (load word — 32-bit, sign-extend) ---------------
lw      a0, 0(sp)
lw      a0, 4(sp)
lw      a0, -4(sp)
lw      a0, 2044(sp)            // max for 32-bit aligned
lw      a0, -2048(sp)
lw      a0, 0(a1)
lw      t0, 4(t1)

// ---- LH (load halfword — 16-bit, sign-extend) -----------
lh      a0, 0(sp)
lh      a0, 2(sp)
lh      a0, -2(sp)
lh      a0, 0(a1)
lh      t0, 2(t1)

// ---- LB (load byte — 8-bit, sign-extend) ----------------
lb      a0, 0(sp)
lb      a0, 1(sp)
lb      a0, -1(sp)
lb      a0, 0(a1)
lb      t0, 1(t1)

// ---- LWU (load word unsigned — 32-bit, zero-extend) -----
lwu     a0, 0(sp)
lwu     a0, 4(sp)
lwu     a0, -4(sp)
lwu     a0, 0(a1)
lwu     t0, 8(t1)

// ---- LHU (load halfword unsigned — 16-bit, zero-extend) -
lhu     a0, 0(sp)
lhu     a0, 2(sp)
lhu     a0, -2(sp)
lhu     a0, 0(a1)

// ---- LBU (load byte unsigned — 8-bit, zero-extend) ------
lbu     a0, 0(sp)
lbu     a0, 1(sp)
lbu     a0, -1(sp)
lbu     a0, 0(a1)

// ---- LA/LI pseudo-instructions (effective address) ------
la      a0, .Ldata_label        // auipc + addi
li      a0, 0                   // addi rd, zero, 0
li      a0, 2047                // fits in I-type imm
li      a0, 2048                // needs LUI + ADDI
li      a0, 0x12345678          // 32-bit constant
li      a0, 0x123456789ABCDEF0  // 64-bit constant (long sequence)

// ---- FLW / FLD (float loads) ----------------------------
flw     f0, 0(sp)
flw     f1, 4(sp)
fld     f2, 0(sp)
fld     f3, 8(sp)
flw     f4, 0(a0)
fld     f5, 8(a1)

[SECTION .data]
.Ldata_label: dq 0
