// ============================================================================
// TEST: tests/asm/aarch64/call.s
// Suite: AArch64 Core
// Purpose: Function call instruction coverage.
//   Covers: BL, BLR, RET, AAPCS64 prologue/epilogue idioms.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- BL (branch with link — direct call) ----------------
    bl      .Lfunction_a
    bl      .Lfunction_b

// ---- BLR (branch with link to register — indirect call) -
    mov     x8, #0          // placeholder address
    blr     x8
    blr     x0
    blr     x1
    blr     x15

// ---- RET (return using LR = x30) -----------------------
    ret
    ret     x30             // explicit LR
    ret     x27             // alternate link register

// ---- AAPCS64 Function Prologue/Epilogue Idiom ----------
.Lfunction_a:
    // Leaf function — save LR + frame pointer
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    // ... body ...
    ldp     x29, x30, [sp], #16
    ret

.Lfunction_b:
    // Non-leaf function — save all callee-saved registers
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    // ... body ...
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

// ---- Indirect call via function pointer array ----------
.Lfunc_table:
    dq      .Lfunction_a
    dq      .Lfunction_b

.Lcall_via_table:
    adrp    x0, .Lfunc_table
    add     x0, x0, :lo12:.Lfunc_table
    ldr     x0, [x0]                // load first function pointer
    blr     x0
    ret

// ---- Tail call (B instead of BL+RET) --------------------
.Ltail_caller:
    b       .Lfunction_a            // no need to save LR for tail call

// ---- Stack probe (guard page detection) -----------------
.Lstack_probe:
    sub     sp, sp, #4096
    mov     x0, sp
    ldr     x1, [x0]                // probe page
    add     sp, sp, #4096
    ret
