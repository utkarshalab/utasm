// ============================================================================
// TEST: tests/asm/common/error_wx.s
// Suite: Common Parser Security
// Purpose: Verify enforcement of W^X (Write XOR Execute) section policy.
// Expected: EXIT_INVALID_SECTION_FLAGS.
// ============================================================================

[SECTION .shellcode, "awx"]
    nop
    nop
    ret
