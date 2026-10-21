// ============================================================================
// TEST: tests/asm/common/error_path_traversal.s
// Suite: Common Preprocessor Security
// Purpose: Verify enforcement of path traversal protection.
// Expected: EXIT_FILE_PERM (Path traversal detected).
// ============================================================================

%inc "../sensitive.s"
