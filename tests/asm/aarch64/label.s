// ============================================================================
// TEST: tests/asm/aarch64/label.s
// Suite: AArch64 Core
// Purpose: Label and symbol definition coverage for AArch64.
//   Covers: global labels, local labels, forward references,
//           cross-section symbol references.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

global _entry
_entry:
    nop

global _func_a
_func_a:
    b       _func_b             // forward reference
    ret

global _func_b
_func_b:
    b       _func_a             // backward reference
    ret

// ---- Local labels (reusable within parent scope) --------
_outer_a:
.loop:
    subs    x0, x0, #1
    b.ne    .loop
    b       .done
.done:
    ret

_outer_b:
.loop:
    add     x0, x0, #1
    cmp     x0, #10
    b.lt    .loop
.done:
    ret

// ---- Data labels ----------------------------------------
[SECTION .data]
global _data_sym
_data_sym:  dq 0x1234567890ABCDEF

[SECTION .rodata]
_ro_sym:    db "Hello, AArch64!", 0

[SECTION .bss]
_bss_sym:   resb 128

// ---- Cross-section references ---------------------------
[SECTION .text]
_cross_ref:
    adrp    x0, _data_sym
    add     x0, x0, :lo12:_data_sym
    adrp    x1, _ro_sym
    add     x1, x1, :lo12:_ro_sym
    adrp    x2, _bss_sym
    add     x2, x2, :lo12:_bss_sym
    ret

// ---- Long identifier stress test -----------------------
a_very_long_label_name_that_exhausts_identifier_scanner_limit_aarch64_architecture_test:
    nop
