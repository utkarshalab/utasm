// ============================================================================
// TEST: tests/asm/common/edge.s
// Suite: Common Preprocessor
// Purpose: Edge case coverage (empty macros, large numbers, etc).
// Expected: EXIT_OK.
// ============================================================================

%macro empty 0
%endmacro

%macro large_params 10
    db %1, %2, %3, %4, %5, %6, %7, %8, %9, %10
%endmacro

[SECTION .text]
    empty
    large_params 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    
    // Deep nesting
    %if 1
        %if 1
            %if 1
                nop
            %endif
        %endif
    %endif
    
    // Empty section
    [SECTION .bss]
    // nothing here
