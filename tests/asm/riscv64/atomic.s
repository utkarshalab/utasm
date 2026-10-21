// ============================================================================
// TEST: tests/asm/riscv64/atomic.s
// Suite: RISC-V 64 Core
// Purpose: Atomic extension (A) exhaustive coverage.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Load-Reserved / Store-Conditional ------------------
lr.w    a0, (a1)
sc.w    t0, a0, (a1)
lr.d    a0, (a1)
sc.d    t0, a0, (a1)

// with ordering bits
lr.w.aq a0, (a1)
lr.w.rl a0, (a1)
lr.w.aqrl a0, (a1)
sc.w.aq t0, a0, (a1)
sc.w.rl t0, a0, (a1)
sc.w.aqrl t0, a0, (a1)

// ---- Atomic Memory Operations ---------------------------
amoadd.w  a0, a1, (a2)
amoswap.w a0, a1, (a2)
amoor.w   a0, a1, (a2)
amoand.w  a0, a1, (a2)
amoxor.w  a0, a1, (a2)
amomax.w  a0, a1, (a2)
amomin.w  a0, a1, (a2)
amomaxu.w a0, a1, (a2)
amominu.w a0, a1, (a2)

amoadd.d  a0, a1, (a2)
amoswap.d a0, a1, (a2)
amoor.d   a0, a1, (a2)
amoand.d  a0, a1, (a2)
amoxor.d  a0, a1, (a2)
amomax.d  a0, a1, (a2)
amomin.d  a0, a1, (a2)
amomaxu.d a0, a1, (a2)
amominu.d a0, a1, (a2)

// with ordering
amoadd.w.aq a0, a1, (a2)
amoadd.w.rl a0, a1, (a2)
amoadd.w.aqrl a0, a1, (a2)
