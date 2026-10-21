// ============================================================================
// TEST: tests/asm/aarch64/interrupt.s
// Suite: AArch64 System
// Purpose: Exception generation and interrupt instruction coverage.
//   Covers: BRK, HLT, SVC, HVC, SMC, ERET — all immediate values.
// Expected: EXIT_OK (encoding only).
// ============================================================================

[SECTION .text]

// ---- BRK (software breakpoint) --------------------------
brk     #0
brk     #1
brk     #0x00FF
brk     #0x1000
brk     #0xFFFF             // max 16-bit immediate

// ---- HLT (halt — debug only, EL2+) ---------------------
hlt     #0
hlt     #1
hlt     #0xFFFF

// ---- SVC (supervisor call) ------------------------------
svc     #0
svc     #1
svc     #0x1234
svc     #0xFFFF

// ---- HVC (hypervisor call) ------------------------------
hvc     #0
hvc     #1
hvc     #0xFFFF

// ---- SMC (secure monitor call) --------------------------
smc     #0
smc     #1
smc     #0xFFFF

// ---- ERET (return from exception) ----------------------
eret

// ---- UDF (undefined — permanently undefined encoding) --
// udf     #0             // causes synchronous exception

// ---- Exception vector idioms ----------------------------
// Common EL1 synchronous exception handler structure:
.exception_handler:
    sub     sp, sp, #0x110          // save registers
    stp     x0,  x1,  [sp, #0x00]
    stp     x2,  x3,  [sp, #0x10]
    stp     x4,  x5,  [sp, #0x20]
    stp     x6,  x7,  [sp, #0x30]
    stp     x8,  x9,  [sp, #0x40]
    stp     x10, x11, [sp, #0x50]
    stp     x12, x13, [sp, #0x60]
    stp     x14, x15, [sp, #0x70]
    stp     x16, x17, [sp, #0x80]
    stp     x18, x19, [sp, #0x90]
    stp     x20, x21, [sp, #0xA0]
    stp     x22, x23, [sp, #0xB0]
    stp     x24, x25, [sp, #0xC0]
    stp     x26, x27, [sp, #0xD0]
    stp     x28, x29, [sp, #0xE0]
    str     x30,      [sp, #0xF0]

    // Read ESR to determine exception type
    mrs     x0, esr_el1
    mrs     x1, far_el1
    mrs     x2, elr_el1

    // ... exception handling ...

    // Restore registers
    ldp     x0,  x1,  [sp, #0x00]
    ldp     x2,  x3,  [sp, #0x10]
    ldp     x28, x29, [sp, #0xE0]
    ldr     x30,      [sp, #0xF0]
    add     sp, sp, #0x110

    eret
