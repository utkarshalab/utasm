// ============================================================================
// TEST: tests/asm/riscv64/label.s
// Suite: RISC-V 64 Core
// Purpose: Label and symbol definition coverage for RISC-V 64.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _entry
_entry:
    nop

global _func_a
_func_a:
    j       _func_b         // forward reference
    ret

global _func_b
_func_b:
    j       _func_a         // backward reference
    ret

// ---- Local labels ---------------------------------------
_outer:
.loop:
    addi    a0, a0, -1
    bnez    a0, .loop
    j       .done
.done:
    ret

// ---- Numeric local labels (GNU style) -------------------
1:
    nop
    j       1b              // back to 1
2:
    j       2f              // forward to 2
2:
    ret

// ---- Data symbols ---------------------------------------
[SECTION .data]
global _data_val
_data_val: dq 0x12345678

[SECTION .text]
_sym_ref:
    la      a0, _data_val
    ld      a0, 0(a0)
    ret
