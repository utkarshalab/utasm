// ============================================================================
// TEST: tests/asm/riscv64/stack.s
// Suite: RISC-V 64 Core
// Purpose: Stack operation coverage for RISC-V 64.
//   RISC-V has no PUSH/POP — uses ADDI SP and SD/LD.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Single Push/Pop (Idiom) ---------------------------
    addi    sp, sp, -8
    sd      a0, 0(sp)       // push a0

    ld      a0, 0(sp)       // pop a0
    addi    sp, sp, 8

// ---- Multi-Push/Pop (Prologue/Epilogue) ----------------
    addi    sp, sp, -48
    sd      ra, 40(sp)
    sd      s0, 32(sp)
    sd      s1, 24(sp)
    sd      s2, 16(sp)
    
    // ... body ...
    
    ld      s2, 16(sp)
    ld      s1, 24(sp)
    ld      s0, 32(sp)
    ld      ra, 40(sp)
    addi    sp, sp, 48
    ret

// ---- Frame Pointer Setup --------------------------------
    addi    sp, sp, -16
    sd      ra, 8(sp)
    sd      s0, 0(sp)
    addi    s0, sp, 16      // s0 is the frame pointer
    
    // ... body ...
    
    ld      s0, 0(sp)
    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

// ---- Stack Alignment (16-byte) --------------------------
    addi    sp, sp, -16     // valid
    addi    sp, sp, -8      // may cause fault on some ABI/HW
    addi    sp, sp, 16
    addi    sp, sp, 8

// ---- Variable Stack Allocation (alloca) ----------------
    sub     sp, sp, a0      // allocate a0 bytes
    // align sp to 16
    li      t0, -16
    and     sp, sp, t0
    // ... use sp ...
    mv      sp, s0          // restore from frame pointer
