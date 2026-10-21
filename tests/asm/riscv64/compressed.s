// ============================================================================
// TEST: tests/asm/riscv64/compressed.s
// Suite: RISC-V 64 Core
// Purpose: Compressed extension (C) instruction coverage.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Compressed Loads / Stores --------------------------
c.lw    a0, 0(a1)
c.sw    a0, 0(a1)
c.ld    a0, 0(a1)           // RV64
c.sd    a0, 0(a1)           // RV64

c.lwsp  a0, 0               // load from stack pointer
c.swsp  a0, 0
c.ldsp  a0, 0               // RV64
c.sdsp  a0, 0               // RV64

// ---- Compressed Arithmetic ------------------------------
c.addi  a0, 1
c.addi  a0, -1
c.addiw a0, 1               // RV64
c.addi16sp 16               // adjust SP by 16
c.addi4spn a0, sp, 16       // a0 = sp + 16

c.li    a0, 1               // c.li rd, imm
c.lui   a0, 1               // c.lui rd, imm

c.add   a0, a1
c.mv    a0, a1
c.sub   a0, a1
c.and   a0, a1
c.or    a0, a1
c.xor   a0, a1

// ---- Compressed Shifts ----------------------------------
c.slli  a0, 1
c.srli  a0, 1
c.srai  a0, 1

// ---- Compressed Jumps / Branches ------------------------
c.j     .Ltarget
c.jr    ra                  // c.jr rs1
c.jalr  ra                  // c.jalr rs1
c.beqz  a0, .Ltarget
c.bnez  a0, .Ltarget

.Ltarget:
    c.nop
    c.ebreak
    ret
