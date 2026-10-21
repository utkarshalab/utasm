// ============================================================================
// TEST: tests/asm/riscv64/smoke.s
// Suite: RISC-V 64 Core
// Purpose: Minimal smoke test — verifies the RISC-V 64 pipeline does not
//          crash on the simplest possible instruction sequence.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _start
_start:
    nop                     // NOP = addi x0, x0, 0
    addi    a0, zero, 0     // load 0 into a0
    mv      a1, a0          // copy a0 to a1
    addi    a0, a0, 1       // add 1
    ret                     // return (pseudo: jalr x0, ra, 0)
