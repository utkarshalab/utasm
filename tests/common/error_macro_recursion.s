// ============================================================================
// TEST: tests/common/error_macro_recursion.s
// Suite: Common Preprocessor Error
// Purpose: Verify detection of infinite macro recursion.
//          A %macro does not call itself (its name inside it is a label, as
//          in NASM); a %rmacro does, until the depth limit.
// Expected: EXIT_MACRO_RECURSION.
// ============================================================================

%rmacro infinite 0
    infinite
%endmacro

[SECTION .text]
    infinite
