// ============================================================================
// TEST: tests/asm/common/define.s
// Suite: Common Preprocessor
// Purpose: %define and %undef coverage.
// Expected: EXIT_OK.
// ============================================================================

%def VERSION 1
%def ARCH    "amd64"

[SECTION .text]
    // Use the defines
    nop
    %if VERSION == 1
        nop
    %endif

    // Redefine
    %def VERSION 2
    %if VERSION == 2
        nop
    %endif

    // Undefine
    %undef VERSION
    // %if VERSION == 1 // Should fail or be false if we check for existence
    // %endif
