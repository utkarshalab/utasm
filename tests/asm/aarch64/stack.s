// ============================================================================
// TEST: tests/asm/aarch64/stack.s
// Suite: AArch64 Core
// Purpose: Stack operation coverage for AArch64.
//   AArch64 has no PUSH/POP — uses STP/LDP with pre/post-index.
//   Covers: All stack frame patterns, SP manipulation, alignment.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Simulate PUSH x0 → PUSH is: str x0, [sp, #-8]! ---
str     x0, [sp, #-8]!
str     x1, [sp, #-8]!
str     x2, [sp, #-8]!
str     w3, [sp, #-4]!

// ---- Simulate POP x0 → POP is: ldr x0, [sp], #8 -------
ldr     x0, [sp], #8
ldr     x1, [sp], #8
ldr     x2, [sp], #8
ldr     w3, [sp], #4

// ---- Pair push / pop (more efficient) ------------------
stp     x0, x1, [sp, #-16]!        // push pair
stp     x2, x3, [sp, #-16]!
stp     x4, x5, [sp, #-16]!
stp     x6, x7, [sp, #-16]!

ldp     x6, x7, [sp], #16         // pop pair
ldp     x4, x5, [sp], #16
ldp     x2, x3, [sp], #16
ldp     x0, x1, [sp], #16

// ---- Frame pointer setup --------------------------------
stp     x29, x30, [sp, #-16]!      // save FP and LR
mov     x29, sp                     // set frame pointer
// ... function body ...
ldp     x29, x30, [sp], #16        // restore FP and LR
ret

// ---- Large frame allocation ----------------------------
.Llarge_frame:
    stp     x29, x30, [sp, #-256]! // allocate 256-byte frame
    mov     x29, sp
    // Store local variables
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    // FP registers
    str     d8,  [sp, #48]
    str     d9,  [sp, #56]
    str     d10, [sp, #64]
    // ... code ...
    ldr     d10, [sp, #64]
    ldr     d9,  [sp, #56]
    ldr     d8,  [sp, #48]
    ldr     x22, [sp, #40]
    ldr     x21, [sp, #32]
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #256
    ret

// ---- Stack pointer alignment ----------------------------
// SP must be 16-byte aligned at all function calls
// Check alignment idiom:
    and     x0, sp, #0xF        // x0 = sp & 15 (should be 0)

// ---- Red zone (no red zone in AArch64, but SP probing) -
// AArch64 OS ABI: no red zone, use SP directly
    sub     sp, sp, #64
    str     x0, [sp]
    str     x1, [sp, #8]
    str     x2, [sp, #16]
    ldr     x0, [sp]
    add     sp, sp, #64
    ret

// ---- Dynamic stack probe (guard page) ------------------
.Lprobe_stack:
    mov     x1, #4096
    sub     sp, sp, x1
    ldr     xzr, [sp]           // probe
    sub     sp, sp, x1
    ldr     xzr, [sp]           // probe again
    add     sp, sp, x1
    add     sp, sp, x1
    ret
