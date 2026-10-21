// ============================================================================
// TEST: tests/asm/riscv64/shift.s
// Suite: RISC-V 64 Core
// Purpose: Shift instruction coverage.
//   Covers: SLL, SRL, SRA, SLLI, SRLI, SRAI — RV64I,
//           SLLW, SRLW, SRAW, SLLIW, SRLIW, SRAIW — RV64I word ops.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- SLL (shift left logical) ---------------------------
sll     a0, a1, a2          // a0 = a1 << (a2 & 63)
sll     t0, t1, t2
sll     s0, s1, s2
sll     a0, a0, zero        // shift by 0

// ---- SLLI (shift left logical immediate) ----------------
slli    a0, a1, 0
slli    a0, a1, 1
slli    a0, a1, 4
slli    a0, a1, 32
slli    a0, a1, 63          // max shift (64-bit)

// ---- SRL (shift right logical — zero-extending) --------
srl     a0, a1, a2
srl     t0, t1, t2
srl     a0, a0, zero

// ---- SRLI (shift right logical immediate) ---------------
srli    a0, a1, 0
srli    a0, a1, 1
srli    a0, a1, 32
srli    a0, a1, 63

// ---- SRA (shift right arithmetic — sign-extending) -----
sra     a0, a1, a2
sra     t0, t1, t2
sra     a0, a0, zero

// ---- SRAI (shift right arithmetic immediate) -----------
srai    a0, a1, 0
srai    a0, a1, 1
srai    a0, a1, 32
srai    a0, a1, 63

// ---- Word shift variants (RV64I) -----------------------
// SLLW: shift left, result is 32-bit sign-extended
sllw    a0, a1, a2
sllw    t0, t1, t2

// SLLIW: shift left logical immediate (word)
slliw   a0, a1, 0
slliw   a0, a1, 1
slliw   a0, a1, 16
slliw   a0, a1, 31         // max shift (32-bit)

// SRLW: shift right logical word
srlw    a0, a1, a2
srlw    t0, t1, t2

// SRLIW: shift right logical immediate word
srliw   a0, a1, 0
srliw   a0, a1, 1
srliw   a0, a1, 16
srliw   a0, a1, 31

// SRAW: shift right arithmetic word
sraw    a0, a1, a2
sraw    t0, t1, t2

// SRAIW: shift right arithmetic immediate word
sraiw   a0, a1, 0
sraiw   a0, a1, 1
sraiw   a0, a1, 16
sraiw   a0, a1, 31

// ---- Bit manipulation (Zbb extension — optional) --------
// These are present if target supports Zbb:
// clz     a0, a1          // count leading zeros
// ctz     a0, a1          // count trailing zeros
// cpop    a0, a1          // population count
// andn    a0, a1, a2      // AND NOT
// orn     a0, a1, a2      // OR NOT
// xnor    a0, a1, a2      // XOR NOT (XNOR)
// rev8    a0, a1          // byte-swap
// orc.b   a0, a1          // bitwise OR-combine bytes
