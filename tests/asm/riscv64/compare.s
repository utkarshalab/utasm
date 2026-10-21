// ============================================================================
// TEST: tests/asm/riscv64/compare.s
// Suite: RISC-V 64 Core
// Purpose: Comparison instruction coverage.
//   RISC-V uses SLT (Set Less Than) and conditional branches.
//   Covers: SLT, SLTI, SLTU, SLTIU, and all comparison pseudo-instructions.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- SLT (Set Less Than — signed) -----------------------
slt     a0, a1, a2
slt     t0, t1, t2
slt     s0, s1, s2
slt     a0, zero, a1        // test if a1 > 0
slt     a0, a1, zero        // test if a1 < 0

// ---- SLTI (Set Less Than Immediate — signed) -----------
slti    a0, a1, 0
slti    a0, a1, 1
slti    a0, a1, -1
slti    a0, a1, 2047
slti    a0, a1, -2048

// ---- SLTU (Set Less Than — unsigned) --------------------
sltu    a0, a1, a2
sltu    t0, t1, t2
sltu    a0, zero, a1        // test if a1 != 0 (pseudo: snez)

// ---- SLTIU (Set Less Than Immediate — unsigned) ---------
sltiu   a0, a1, 0           // always 0
sltiu   a0, a1, 1           // test if a1 == 0 (pseudo: seqz)
sltiu   a0, a1, -1          // -1 sign-extended is UINT64_MAX

// ---- Comparison Pseudo-instructions ---------------------
seqz    a0, a1              // sltiu a0, a1, 1
snez    a0, a1              // sltu  a0, zero, a1
sltz    a0, a1              // slt   a0, a1, zero
sgtz    a0, a1              // slt   a0, zero, a1

// ---- Macro-like Comparison Idioms ----------------------
// beq/bne/blt/bge are the primary branching comparisons
beq     a0, a1, .Lequal
bne     a0, a1, .Lnotequal
blt     a0, a1, .Lless
bge     a0, a1, .Lgreater_equal
bltu    a0, a1, .Lless_u
bgeu    a0, a1, .Lgreater_equal_u

.Lequal:
.Lnotequal:
.Lless:
.Lgreater_equal:
.Lless_u:
.Lgreater_equal_u:
    nop
