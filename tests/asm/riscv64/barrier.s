// ============================================================================
// TEST: tests/asm/riscv64/barrier.s
// Suite: RISC-V 64 Core
// Purpose: Memory barrier and synchronization instruction coverage.
//   Covers: FENCE, FENCE.I, and A extension (atomic) barriers.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- FENCE (Memory Ordering) ----------------------------
fence                       // full fence (iorw, iorw)
fence   i, r                // predecessor: i, successor: r
fence   r, w                // read -> write
fence   w, r                // write -> read
fence   rw, rw              // read/write -> read/write
fence   iorw, iorw          // all -> all
fence   tso                 // total store ordering fence (if supported)

// ---- FENCE.I (Instruction Stream Synchronization) -------
fence.i

// ---- Atomics (A extension) — Load Reserved / Store Conditional ----
// These have acquire (.aq) and release (.rl) bits
lr.w    a0, (a1)
lr.w.aq a0, (a1)
lr.w.rl a0, (a1)
lr.w.aqrl a0, (a1)

lr.d    a0, (a1)            // doubleword
lr.d.aq a0, (a1)
lr.d.rl a0, (a1)
lr.d.aqrl a0, (a1)

sc.w    t0, a0, (a1)        // t0 = status
sc.w.aq t0, a0, (a1)
sc.w.rl t0, a0, (a1)
sc.w.aqrl t0, a0, (a1)

sc.d    t0, a0, (a1)
sc.d.aq t0, a0, (a1)
sc.d.rl t0, a0, (a1)
sc.d.aqrl t0, a0, (a1)

// ---- Atomic Memory Operations (AMO) ---------------------
amoadd.w a0, a1, (a2)
amoswap.w a0, a1, (a2)
amoor.w  a0, a1, (a2)
amoand.w a0, a1, (a2)
amoxor.w a0, a1, (a2)
amomax.w a0, a1, (a2)
amomin.w a0, a1, (a2)

// with bits
amoadd.d.aq a0, a1, (a2)
amoadd.d.rl a0, a1, (a2)
amoadd.d.aqrl a0, a1, (a2)
