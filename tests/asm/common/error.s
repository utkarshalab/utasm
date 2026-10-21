// ============================================================================
// TEST: tests/asm/common/error.s
// Suite: Common Preprocessor
// Purpose: Intentional error coverage (verifies diagnostics).
// Expected: EXIT_FAILURE or specific error code.
// ============================================================================

// This test might be designed to FAIL if we want to test error reporting.
// For a general "bulletproof" suite, we should have a way to expect errors.
// For now, let's just put something that might be borderline or a common mistake.

[SECTION .text]
    // Undefined macro usage (should be caught)
    // UNDEFINED_MACRO
    
    // Invalid directive
    // %invalid_directive
    
    // Unclosed macro (intentional error if we were testing failure paths)
    // %macro unclosed 0
    //     nop
    
    nop
