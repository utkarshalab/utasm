// ============================================================================
// TEST: tests/asm/riscv64/exception.s
// Suite: RISC-V 64 Core
// Purpose: Exception-class instruction and handler idiom encoding.
//   Covers: ECALL, EBREAK, illegal instruction trap idioms,
//           ESR/MCAUSE decode patterns.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Exception Trigger ----------------------------------
ecall                       // Environment call
ebreak                      // Environment break

// ---- Exception Cause Decoding ---------------------------
.Lhandle_exception:
    csrr    a0, mcause
    li      t0, 2           // Illegal instruction
    beq     a0, t0, .Lillegal_instr
    li      t0, 8           // ECALL from U-mode
    beq     a0, t0, .Lecall_umode
    li      t0, 11          // ECALL from M-mode
    beq     a0, t0, .Lecall_mmode
    j       .Lunknown_exception

.Lillegal_instr:
    nop
    j       .Ldone

.Lecall_umode:
    nop
    j       .Ldone

.Lecall_mmode:
    nop
    j       .Ldone

.Lunknown_exception:
    ebreak

.Ldone:
    csrr    t0, mepc
    addi    t0, t0, 4       // advance past faulting instruction
    csrw    mepc, t0
    mret
