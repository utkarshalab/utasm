// ============================================================================
// TEST: tests/asm/amd64/label.s
// Suite: AMD64 Core
// Purpose: Label and symbol definition coverage.
//   Covers: global labels, local labels (.label:), forward references,
//           backward references, duplicate detection, global directive.
// Expected: EXIT_OK for valid cases.
// ============================================================================

[SECTION .text]

// ---- Global label definition ----------------------------
global  _entry
_entry:
    nop

// ---- Global label used as jump target -------------------
global  _func_a
_func_a:
    jmp     _func_b         // forward reference
    ret

global  _func_b
_func_b:
    jmp     _func_a         // backward reference
    ret

// ---- Local labels (only visible within parent scope) ----
_outer_a:
.loop:
    dec     rax
    jnz     .loop           // backward local ref
    jmp     .done           // forward local ref
.done:
    ret

// Multiple functions can reuse same local label names
_outer_b:
.loop:
    inc     rbx
    cmp     rbx, 10
    jl      .loop           // backward local ref within _outer_b
.done:
    ret

// ---- Label at different section positions ---------------
[SECTION .data]
global data_symbol
data_symbol: dq 0x12345678

[SECTION .rodata]
rodata_sym: db "hello", 0

[SECTION .bss]
bss_sym: resb 64

// ---- Back to .text and use cross-section symbols ---------
[SECTION .text]

_cross_ref:
    lea     rax, [rel data_symbol]
    lea     rbx, [rel rodata_sym]
    lea     rcx, [rel bss_sym]
    ret

// ---- Long label names (stress identifier length) --------
a_very_long_label_name_that_exercises_the_identifier_scanner_limit_boundary_test_label:
    nop
    jmp a_very_long_label_name_that_exercises_the_identifier_scanner_limit_boundary_test_label

// ---- Labels starting with underscore and dot combinations -
_private_func:
.inner_loop:
    nop
    jmp .inner_loop

// ---- Numeric local labels (1f, 1b style — utasm extension) -
// If utasm supports GNU-style numeric labels:
1:
    nop
    jmp 1b                  // jump back to nearest "1:"

2:
    nop
    jmp 2f                  // jump forward to nearest "2:"

2:
    ret
