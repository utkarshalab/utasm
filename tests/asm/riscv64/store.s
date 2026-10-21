// ============================================================================
// TEST: tests/asm/riscv64/store.s
// Suite: RISC-V 64 Core
// Purpose: Store instruction coverage.
//   Covers: SB, SH, SW, SD — all sizes, all offset ranges.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- SD (store doubleword — 64-bit) ----------------------
sd      a0, 0(sp)
sd      a0, 8(sp)
sd      a0, -8(sp)
sd      a0, 2047(sp)            // max positive imm12 (split into imm[11:5] and imm[4:0])
sd      a0, -2048(sp)
sd      a0, 0(a1)
sd      a0, 8(a1)
sd      t0, 0(t1)
sd      s0, 16(s1)
sd      zero, 0(a0)             // store zero
sd      ra, 0(sp)               // save RA to stack

// ---- SW (store word — 32-bit) ---------------------------
sw      a0, 0(sp)
sw      a0, 4(sp)
sw      a0, -4(sp)
sw      a0, 2044(sp)
sw      a0, 0(a1)
sw      t0, 4(t1)
sw      zero, 0(a0)

// ---- SH (store halfword — 16-bit) -----------------------
sh      a0, 0(sp)
sh      a0, 2(sp)
sh      a0, -2(sp)
sh      a0, 0(a1)
sh      zero, 0(a0)

// ---- SB (store byte — 8-bit) ----------------------------
sb      a0, 0(sp)
sb      a0, 1(sp)
sb      a0, -1(sp)
sb      a0, 0(a1)
sb      zero, 0(a0)

// ---- FSW / FSD (float stores) ---------------------------
fsw     f0, 0(sp)
fsw     f1, 4(sp)
fsd     f2, 0(sp)
fsd     f3, 8(sp)
fsw     f4, 0(a0)
fsd     f5, 8(a1)

// ---- Common store patterns ------------------------------
// Push RA to stack (function call save)
addi    sp, sp, -8
sd      ra, 0(sp)

// Restore and return
ld      ra, 0(sp)
addi    sp, sp, 8
ret

// ---- Memset idiom (zero an array) ----------------------
.Lmemset_zero:
    li      t0, 64              // loop count (bytes / 8)
    mv      t1, a0              // pointer
.Lmemset_loop:
    sd      zero, 0(t1)
    addi    t1, t1, 8
    addi    t0, t0, -1
    bnez    t0, .Lmemset_loop
    ret
