// ============================================================================
// TEST: tests/asm/riscv64/interrupt.s
// Suite: RISC-V 64 Core
// Purpose: Trap and interrupt handling instruction coverage.
//   Covers: CSR manipulation for traps (mstatus, mepc, mtvec),
//           trap entry/exit idioms, and return instructions.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Trap Return ----------------------------------------
mret                        // Machine mode return
sret                        // Supervisor mode return
uret                        // User mode return (N extension)

// ---- Trap Vector Setup ---------------------------------
la      t0, .Ltrap_handler
csrw    mtvec, t0           // set trap vector

// ---- Enable/Disable Interrupts --------------------------
csrsi   mstatus, 8          // set MIE bit (machine interrupt enable)
csrci   mstatus, 8          // clear MIE bit

// ---- Trap Entry Idiom (Save State) ----------------------
.Ltrap_handler:
    // Save registers to stack or scratch
    csrrw   sp, mscratch, sp    // swap sp with scratch
    addi    sp, sp, -256
    sd      ra, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    // ... save others ...
    
    // Read cause
    csrr    t0, mcause
    csrr    t1, mepc
    
    // ... handle trap ...
    
    // Restore and return
    ld      t1, 16(sp)
    ld      t0, 8(sp)
    ld      ra, 0(sp)
    addi    sp, sp, 256
    csrrw   sp, mscratch, sp    // restore sp
    mret

// ---- Software Interrupts --------------------------------
// Trigger via CSR
li      t0, 8               // MSI bit
csrs    mip, t0             // set pending interrupt
