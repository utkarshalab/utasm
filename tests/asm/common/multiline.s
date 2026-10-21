// ============================================================================
// TEST: tests/asm/common/multiline.s
// Suite: Common Preprocessor
// Purpose: Multiline macro and directive coverage.
// Expected: EXIT_OK.
// ============================================================================

%macro multiline 0
    nop
    nop
    nop
%endmacro

[SECTION .text]
    multiline
    
    // Test multiline strings if supported
    db "This is a ", \
       "multiline string"
    
    // Test multiline instruction (not usually supported but directives might)
    db 1, 2, 3, \
       4, 5, 6
