// ============================================================================
// TEST: tests/asm/amd64/stress_operands.s
// Suite: AMD64 Parser
// Purpose: Stress-test operand parsing to verify register stability (r13 fix).
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]
    mov     rax, [rbx + rcx * 8 + 0x12345678]  // Complex addressing
    vaddps  zmm0, zmm1, [rax + rdi * 4 + 64]   // Multi-operand instruction
