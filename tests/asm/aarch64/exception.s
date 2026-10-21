// ============================================================================
// TEST: tests/asm/aarch64/exception.s
// Suite: AArch64 System
// Purpose: Exception-class instruction and handler idiom encoding.
//   Covers: All exception classes, ESR decode patterns, FAR usage,
//           ERET sequences, EL-switching idioms.
// Expected: EXIT_OK (encoding only).
// ============================================================================

[SECTION .text]

// ---- System register access around exceptions ----------
.exc_entry:
    mrs     x0, esr_el1             // read exception syndrome
    ubfx    x1, x0, #26, #6         // extract EC (exception class) bits [31:26]
    
    // Switch on exception class
    cmp     x1, #0x01               // WFI/WFE instruction
    b.eq    .handle_wfi
    cmp     x1, #0x12               // HVC from AArch64
    b.eq    .handle_hvc
    cmp     x1, #0x15               // SVC from AArch64
    b.eq    .handle_svc
    cmp     x1, #0x20               // instruction abort from lower EL
    b.eq    .handle_iabt
    cmp     x1, #0x24               // data abort from lower EL
    b.eq    .handle_dabt
    cmp     x1, #0x3C               // BRK instruction
    b.eq    .handle_brk
    b       .handle_unknown

.handle_wfi:
    nop
    b       .exc_return

.handle_hvc:
    mrs     x2, esr_el2             // re-read from EL2 perspective
    b       .exc_return

.handle_svc:
    mrs     x2, esr_el1
    and     x2, x2, #0xFFFF         // SVC immediate in [15:0]
    b       .exc_return

.handle_iabt:
    mrs     x2, far_el1             // fault address
    mrs     x3, esr_el1
    ubfx    x4, x3, #0, #12        // DFSC bits
    b       .exc_return

.handle_dabt:
    mrs     x2, far_el1
    mrs     x3, esr_el1
    ubfx    x4, x3, #0, #6         // DFSC bits
    tst     x3, #(1 << 6)          // WnR bit (write not read)
    b.ne    .dabt_write
    b       .exc_return
.dabt_write:
    b       .exc_return

.handle_brk:
    mrs     x2, elr_el1             // address of BRK instruction
    add     x2, x2, #4             // advance past BRK
    msr     elr_el1, x2
    b       .exc_return

.handle_unknown:
    brk     #0xFF                   // signal unhandled exception

.exc_return:
    eret

// ---- EL2 → EL1 transition (return from hypervisor) ----
.drop_to_el1:
    // Set up EL1 SPSR to return to EL1h mode
    mov     x0, #0x3C5             // SPSR_EL2: EL1h, interrupts masked
    msr     spsr_el2, x0
    adr     x1, .el1_entry
    msr     elr_el2, x1
    eret

.el1_entry:
    nop

// ---- EL1 → EL0 transition (return to user) -------------
.drop_to_el0:
    mov     x0, #0x0               // SPSR: EL0t, no masks
    msr     spsr_el1, x0
    adr     x1, .el0_entry
    msr     elr_el1, x1
    eret

.el0_entry:
    svc     #0
