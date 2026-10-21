// ============================================================================
// TEST: tests/asm/common/macro.s
// Suite: Common Preprocessor
// Purpose: Basic %macro coverage.
// Expected: EXIT_OK.
// ============================================================================

%macro my_nop 0
    nop
%endmacro

%macro set_val 2
    %1 = %2
%endmacro

[SECTION .text]
    my_nop
    my_nop
    
    // Test parameters
    %macro load_imm 2
        li %1, %2
    %endmacro
    
    // Note: 'li' might be arch-specific, but for preprocessor test it doesn't matter
    // as long as it's parsed as an instruction with operands.
    // However, to be "bulletproof" and arch-neutral:
    %macro emit_data 1
        db %1
    %endmacro
    
    emit_data 0x42
    emit_data 0x43
