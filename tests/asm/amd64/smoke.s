// ============================================================================
// TEST: tests/asm/amd64/smoke.s
// Suite: AMD64 Core
// Purpose: Minimal smoke check — verifies the assembler pipeline can parse
//          and emit a trivial instruction sequence without crashing.
// Expected: EXIT_OK, valid ELF64 relocatable output.
// ============================================================================

[SECTION .text]

global _start
_start:
    // Simplest possible instructions — one of each broad class
    nop                         // no-op
    mov     rax, 0              // immediate to reg
    mov     rbx, rax            // reg to reg
    add     rax, 1              // arithmetic imm
    ret                         // control flow
