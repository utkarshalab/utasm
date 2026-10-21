// ============================================================================
// TEST: tests/asm/common/error_include_self.s
// Suite: Common Preprocessor Security
// Purpose: Verify detection of circular include (self-inclusion).
// Expected: EXIT_MACRO_RECURSION or similar include limit error.
// ============================================================================

%inc "tests/asm/common/error_include_self.s"
