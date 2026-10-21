// ============================================================================
// TEST: tests/asm/common/nested.s
// Suite: Common Preprocessor
// Purpose: Nested macro and conditional coverage.
// Expected: EXIT_OK.
// ============================================================================

%macro outer 1
    %if %1 > 0
        %macro inner 0
            db 0xAA
        %endmacro
        inner
    %else
        db 0xBB
    %endif
%endmacro

[SECTION .text]
    outer 1
    outer 0
