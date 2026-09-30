// ============================================================================
// TEST: tests/common/error_utf8.s
// Suite: Common Lexer Error
// Purpose: Verify detection of malformed UTF-8 sequences.
// Expected: EXIT_ERROR (Malformed UTF-8).
// ============================================================================

[SECTION .text]
    ; The source itself contains malformed UTF-8: a 2-byte lead byte
    ; (0xC2) followed by a space instead of a continuation byte.
    Â nop
