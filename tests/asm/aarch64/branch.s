// ============================================================================
// TEST: tests/asm/aarch64/branch.s
// Suite: AArch64 Core
// Purpose: Branch instruction coverage.
//   Covers: B, BL, BR, BLR, RET, B.cond (all 16 conditions),
//           CBZ, CBNZ, TBZ, TBNZ — all register widths.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _start
_start:
    b       .L1                 // unconditional branch

// ---- B (unconditional branch) ---------------------------
.L1:
    b       .L1                 // tight loop
    b       .L2

.L2:
    nop

// ---- BL (branch with link — CALL equivalent) -----------
    bl      .L1
    bl      .L2

// ---- BR (branch to register) ----------------------------
    br      x0
    br      x30                 // return via LR (same as RET)
    br      x1
    br      x15
    br      x29

// ---- BLR (branch with link to register) ----------------
    blr     x0                  // indirect call
    blr     x1
    blr     x8
    blr     x15

// ---- RET (return from subroutine) ----------------------
    ret                         // uses x30 (LR) by default
    ret     x30                 // explicit
    ret     x15                 // alternate link register

// ---- B.cond — all 16 AArch64 conditions ----------------
    b.eq    .L1
    b.ne    .L1
    b.cs    .L1                 // carry set
    b.hs    .L1                 // same as cs (higher or same)
    b.cc    .L1                 // carry clear
    b.lo    .L1                 // same as cc (lower)
    b.mi    .L1                 // minus / negative
    b.pl    .L1                 // plus / positive or zero
    b.vs    .L1                 // overflow set
    b.vc    .L1                 // overflow clear
    b.hi    .L1                 // higher (unsigned)
    b.ls    .L1                 // lower or same (unsigned)
    b.ge    .L1                 // signed >=
    b.lt    .L1                 // signed <
    b.gt    .L1                 // signed >
    b.le    .L1                 // signed <=
    b.al    .L1                 // always (same as B)

// ---- CBZ (compare and branch if zero) ------------------
    cbz     x0, .L1
    cbz     x1, .L2
    cbz     w2, .L1
    cbz     w3, .L2

// ---- CBNZ (compare and branch if non-zero) -------------
    cbnz    x0, .L1
    cbnz    x4, .L2
    cbnz    w5, .L1
    cbnz    w6, .L2

// ---- TBZ (test bit and branch if zero) -----------------
    tbz     x0, #0,  .L1
    tbz     x1, #63, .L2
    tbz     w2, #0,  .L1
    tbz     w3, #31, .L2
    tbz     x4, #12, .L1
    tbz     x5, #32, .L2

// ---- TBNZ (test bit and branch if non-zero) -------------
    tbnz    x0, #0,  .L1
    tbnz    x1, #63, .L2
    tbnz    w2, #0,  .L1
    tbnz    w3, #31, .L2
    tbnz    x4, #12, .L1

// ---- ISB (instruction synchronization barrier) ----------
    isb

    ret
