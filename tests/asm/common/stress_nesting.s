// ============================================================================
// TEST: tests/asm/common/stress_nesting.s
// Suite: Common Preprocessor Stress
// Purpose: Extreme nesting of conditionals to verify skip_depth stability.
// Expected: Only specific values emitted.
// ============================================================================

%def LEVEL1 1
%def LEVEL2 0
%def LEVEL3 1
%def LEVEL4 0

[SECTION .text]
    %if LEVEL1
        db 0x01
        %if LEVEL2
            db 0x02
            %if LEVEL3
                db 0x03
            %endif
            db 0x04
        %else
            db 0x05
            %if LEVEL3
                db 0x06
                %if LEVEL4
                    db 0x07
                %else
                    db 0x08
                %endif
                db 0x09
            %endif
            db 0x0A
        %endif
        db 0x0B
    %endif

    // Expected Output: 0x01, 0x05, 0x06, 0x08, 0x09, 0x0A, 0x0B
