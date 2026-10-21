// ============================================================================
// TEST: tests/asm/riscv64/macros.s
// Suite: RISC-V 64 Preprocessor
// Purpose: Macro definition and expansion for RISC-V.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

%macro rv_prologue 1
    addi    sp, sp, -%1
    sd      ra, (%1 - 8)(sp)
    sd      s0, (%1 - 16)(sp)
    addi    s0, sp, %1
%endmacro

%macro rv_epilogue 1
    ld      s0, (%1 - 16)(sp)
    ld      ra, (%1 - 8)(sp)
    addi    sp, sp, %1
    ret
%endmacro

my_func:
    rv_prologue 32
    nop
    rv_epilogue 32

// ---- Macro with local label -----------------------------
%macro repeat_nop 1
    li      t0, %1
%%loop:
    nop
    addi    t0, t0, -1
    bnez    t0, %%loop
%endmacro

test_repeat:
    repeat_nop 5
    ret

// ---- Multi-param macro ----------------------------------
%macro load_pair 3
    ld      %1, 0(%3)
    ld      %2, 8(%3)
%endmacro

test_load_pair:
    load_pair a0, a1, a2
    ret
