// ============================================================================
// TEST: tests/asm/aarch64/smoke.s
// Suite: AArch64 Core
// Purpose: Minimal smoke test — verifies the AArch64 pipeline does not crash
//          on the simplest possible instruction sequence.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _start
_start:
    nop                     // no-op
    mov     x0, #0          // move immediate 0 to x0
    mov     x1, x0          // register to register
    add     x0, x0, #1      // arithmetic
    ret                     // return
