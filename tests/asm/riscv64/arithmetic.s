// ============================================================================
// TEST: tests/asm/riscv64/arithmetic.s
// Suite: RISC-V 64 Core
// Purpose: Exhaustive arithmetic instruction coverage.
//   Covers: ADD, ADDI, SUB, LUI, AUIPC — RV64I base,
//           ADDW, SUBW, ADDIW — RV64I word ops,
//           MUL, DIV, REM — M extension,
//           MULW, DIVW, REMW — M extension word ops.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- ADD (R-type) ---------------------------------------
add     a0, a1, a2
add     a3, a4, a5
add     t0, t1, t2
add     s0, s1, s2
add     zero, zero, zero    // no-op
add     a0, a0, zero        // identity

// ---- ADDI (I-type) --------------------------------------
addi    a0, a1, 0
addi    a0, a1, 1
addi    a0, a1, -1
addi    a0, a1, 2047        // max positive imm12
addi    a0, a1, -2048       // min negative imm12
addi    a0, a1, 0xFF
addi    a0, a1, -128
addi    a0, zero, 42        // load immediate (LI alias)
addi    t0, t0, 1           // increment
addi    sp, sp, -16         // stack frame allocation
addi    sp, sp, 16          // stack frame deallocation

// ---- SUB (R-type) ---------------------------------------
sub     a0, a1, a2
sub     a3, a4, a5
sub     t0, t1, t2
sub     a0, a0, a0          // zero self

// ---- LUI (U-type) — load upper immediate ---------------
lui     a0, 0x12345
lui     a1, 0xFFFFF
lui     a2, 0
lui     a3, 1
lui     t0, 0x80000         // min negative (sign bit)
lui     gp, 0x10000         // typical GP setup

// ---- AUIPC (U-type) — add upper immediate to PC --------
auipc   a0, 0               // a0 = PC + 0 (current PC low 12)
auipc   a1, 1               // a1 = PC + 0x1000
auipc   a2, 0xFFFFF
auipc   t0, 0x10000

// ---- ADDW (64-bit only — add word, sign-extend) --------
addw    a0, a1, a2
addw    t0, t1, t2
addw    a0, a0, zero

// ---- ADDIW (64-bit only — add word immediate) ----------
addiw   a0, a1, 0
addiw   a0, a1, 1
addiw   a0, a1, -1
addiw   a0, a1, 2047
addiw   a0, a1, -2048

// ---- SUBW (64-bit only — subtract word) ----------------
subw    a0, a1, a2
subw    t0, t1, t2

// ---- M Extension: MUL / DIV / REM ----------------------
mul     a0, a1, a2
mul     t0, t1, t2
mulh    a0, a1, a2          // high 64 bits of signed 128-bit product
mulhsu  a3, a4, a5          // signed × unsigned high
mulhu   a6, a7, t0          // unsigned × unsigned high
div     t1, t2, t3          // signed division
divu    t4, t5, t6          // unsigned division
rem     a0, a1, a2          // signed remainder
remu    a3, a4, a5          // unsigned remainder

// ---- M Extension: Word variants -------------------------
mulw    a0, a1, a2
divw    a3, a4, a5
divuw   a6, a7, t0
remw    t1, t2, t3
remuw   t4, t5, t6

// ---- Pseudo-instructions --------------------------------
li      a0, 0                   // load immediate (via ADDI/LUI+ADDI)
li      a0, 1
li      a0, -1
li      a0, 2047
li      a0, 2048               // requires LUI+ADDI
li      a0, 0x12345678
li      a0, 0xFFFFFFFF
li      a0, 0x7FFFFFFFFFFFFFFF // INT64_MAX

neg     a0, a1                  // neg = sub a0, zero, a1
negw    a0, a1                  // negw = subw a0, zero, a1
