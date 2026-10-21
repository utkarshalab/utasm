// ============================================================================
// TEST: tests/asm/riscv64/branch.s
// Suite: RISC-V 64 Core
// Purpose: Branch and jump instruction coverage.
//   Covers: BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR,
//           pseudo: J, CALL, RET, BEQZ, BNEZ, BLTZ, BGEZ, BGTZ, BLEZ.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _start
_start:
    j       .L1                 // unconditional jump (pseudo: JAL x0, offset)

// ---- BEQ (branch if equal) ------------------------------
.L1:
    beq     a0, a1, .L1
    beq     a0, zero, .L2       // beqz idiom explicit
    beq     zero, zero, .L1     // always taken

// ---- BNE (branch if not equal) --------------------------
.L2:
    bne     a0, a1, .L1
    bne     a0, zero, .L2       // bnez idiom explicit
    bne     a0, a1, .L2

// ---- BLT (branch if less than — signed) -----------------
    blt     a0, a1, .L1
    blt     a0, zero, .L1       // bltz idiom explicit
    blt     zero, a0, .L1       // bgtz idiom explicit

// ---- BGE (branch if greater or equal — signed) ----------
    bge     a0, a1, .L1
    bge     a0, zero, .L1       // bgez idiom explicit
    bge     zero, a0, .L1       // blez idiom explicit

// ---- BLTU (branch if less than — unsigned) --------------
    bltu    a0, a1, .L1
    bltu    a0, zero, .L1       // always false (unsigned)

// ---- BGEU (branch if greater or equal — unsigned) -------
    bgeu    a0, a1, .L1
    bgeu    a0, zero, .L1       // always true (unsigned)

// ---- JAL (jump and link — call / unconditional jump) ----
    jal     ra, .L1             // call .L1, save return in ra
    jal     ra, .L2             // call .L2
    jal     zero, .L1           // unconditional jump (no link)
    jal     t0, .L1             // save return in t0

// ---- JALR (jump and link register — indirect) -----------
    jalr    ra, ra, 0           // return (RET)
    jalr    zero, ra, 0         // return (no link)
    jalr    ra, t0, 0           // indirect call via t0
    jalr    ra, a0, 4           // call a0+4
    jalr    zero, a1, -4        // jump to a1-4

// ---- Pseudo-instructions --------------------------------
    ret                         // = jalr zero, ra, 0
    j       .L1                 // = jal zero, offset
    call    .L1                 // = auipc ra, hi20; jalr ra, ra, lo12
    tail    .L1                 // = auipc t1, hi20; jalr zero, t1, lo12

// ---- Pseudo branch comparisons -------------------------
    beqz    a0, .L1             // beq a0, zero, .L1
    bnez    a0, .L1             // bne a0, zero, .L1
    bltz    a0, .L1             // blt a0, zero, .L1
    bgez    a0, .L1             // bge a0, zero, .L1
    bgtz    a0, .L1             // blt zero, a0, .L1
    blez    a0, .L1             // bge zero, a0, .L1
    bgt     a0, a1, .L1         // blt a1, a0, .L1
    ble     a0, a1, .L1         // bge a1, a0, .L1
    bgtu    a0, a1, .L1
    bleu    a0, a1, .L1
