// ============================================================================
// TEST: tests/asm/aarch64/shift_preprocessor.s
// Suite: AArch64 Preprocessor
// Purpose: Verify architecture-specific shift mnemonics in preprocessor expressions.
// Expected: EXIT_OK.
// ============================================================================

%def SHIFT_VAL 4

[SECTION .text]
    // Verification of shift mnemonics in preprocessor context
    add x0, x1, x2, lsl #SHIFT_VAL
    add x3, x4, x5, lsr #2
    add x6, x7, x8, asr #1
    add x9, x10, x11, ror #3
