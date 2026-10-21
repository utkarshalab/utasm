// ============================================================================
// TEST: tests/asm/riscv64/call.s
// Suite: RISC-V 64 Core
// Purpose: Function call instruction coverage.
//   Covers: JAL, JALR, pseudo: CALL, TAIL, RET.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Direct Call (JAL) ----------------------------------
    jal     ra, .Lfunc_a
    jal     t0, .Lfunc_b

// ---- Indirect Call (JALR) -------------------------------
    li      t1, 0           // placeholder addr
    jalr    ra, t1, 0
    jalr    zero, t1, 0     // jump (no return)
    jalr    ra, a0, 8       // call offset from a0

// ---- Pseudo-instructions --------------------------------
    call    .Lfunc_a        // expands to auipc + jalr
    tail    .Lfunc_b        // tail call (auipc + jalr with x0)
    ret                     // jalr x0, ra, 0

// ---- Function Idioms ------------------------------------
.Lfunc_a:
    nop
    ret

.Lfunc_b:
    // Non-leaf function
    addi    sp, sp, -16
    sd      ra, 8(sp)
    call    .Lfunc_a
    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

// ---- Indirect call via pointer in data -----------------
.Lcall_ptr:
    la      t0, .Lfunc_ptr
    ld      t0, 0(t0)
    jalr    ra, t0, 0
    ret

[SECTION .data]
.Lfunc_ptr: dq .Lfunc_a
