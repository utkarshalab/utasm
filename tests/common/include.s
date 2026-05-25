// ============================================================================
// TEST: tests/common/include.s
// Suite: Common Preprocessor
// Purpose: %inc (include) coverage.
// Expected: EXIT_OK.
// ============================================================================

// Assume there is a file to include or we use a relative path
// For testing purposes, we assume include/constant.s exists
%inc "include/constant.inc"

[SECTION .text]
    // Use a constant defined in the included file
    // e.g., EXIT_OK (assuming it's defined there)
    nop
