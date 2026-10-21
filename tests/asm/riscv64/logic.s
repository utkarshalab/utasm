// ============================================================================
// TEST: tests/asm/riscv64/logic.s
// Suite: RISC-V 64 Core
// Purpose: Logical/bitwise instruction coverage.
//   Covers: AND, ANDI, OR, ORI, XOR, XORI, NOT — all forms.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- AND (R-type) ---------------------------------------
and     a0, a1, a2
and     t0, t1, t2
and     s0, s1, s2
and     a0, a0, a0          // idempotent
and     a0, a0, zero        // zero result

// ---- ANDI (I-type) --------------------------------------
andi    a0, a1, 0
andi    a0, a1, 1
andi    a0, a1, -1          // 0xFFF (sign-extended)
andi    a0, a1, 0xFF
andi    a0, a1, 0x0F
andi    a0, a1, 2047        // max
andi    a0, a1, -2048       // min
andi    t0, t0, 0xF         // mask lower nibble

// ---- OR (R-type) ----------------------------------------
or      a0, a1, a2
or      t0, t1, t2
or      a0, zero, a1        // effectively: mv a0, a1

// ---- ORI (I-type) ----------------------------------------
ori     a0, a1, 0
ori     a0, a1, 1
ori     a0, a1, -1
ori     a0, a1, 0xFF
ori     a0, zero, 0x42      // load small constant via ORI

// ---- XOR (R-type) ---------------------------------------
xor     a0, a1, a2
xor     t0, t0, t0          // zero self
xor     s0, s1, s2

// ---- XORI (I-type) ---------------------------------------
xori    a0, a1, 0
xori    a0, a1, 1
xori    a0, a1, -1          // bitwise NOT idiom
xori    a0, a1, 0xFF

// ---- NOT (pseudo — alias for XORI rd, rs, -1) ----------
not     a0, a1
not     t0, t0
not     s0, s1

// ---- SLT / SLTU (set less than) -------------------------
slt     a0, a1, a2          // signed
slt     t0, zero, a0        // test if a0 is positive
sltu    a0, a1, a2          // unsigned
sltu    a3, zero, a4        // test if a4 is non-zero

// ---- SLTI / SLTIU (set less than immediate) -------------
slti    a0, a1, 0
slti    a0, a1, 1
slti    a0, a1, -1
slti    a0, a1, 2047
slti    a0, a1, -2048
sltiu   a0, a1, 0
sltiu   a0, a1, 1
sltiu   a0, a1, -1          // -1 as unsigned = UINT64_MAX (all set)

// ---- Pseudo: SEQZ, SNEZ, SLTZ, SGTZ -------------------
seqz    a0, a1              // a0 = (a1 == 0) ? 1 : 0
snez    a0, a1              // a0 = (a1 != 0) ? 1 : 0
sltz    a0, a1              // a0 = (a1 < 0)  ? 1 : 0  (signed)
sgtz    a0, a1              // a0 = (a1 > 0)  ? 1 : 0  (signed)
