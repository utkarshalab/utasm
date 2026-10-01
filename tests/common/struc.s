// ============================================================================
// TEST: tests/common/struc.s
// Suite: Common Parser
// Purpose: Verify struct parsing and field offset registration.
// Expected: EXIT_OK.
// ============================================================================

struc Point
    field x, 8
    field y, 8
    field z, 8, 16  // Aligned to 16
endstruc

[SECTION .text]
    mov rax, Point_SIZE     // Should be 32 (8+8 = 16, aligned to 16 = 16, + 8 = 24? Wait)
    // Actually Point_SIZE calculation:
    // x: offset 0, size 8. next offset 8.
    // y: offset 8, size 8. next offset 16.
    // z: align 16 (offset 16), size 8. next offset 24.
    // total size = 24.
    
    mov rbx, Point_z        // Should be 16 (fields are named Struct_field)
