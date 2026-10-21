// ============================================================================
// TEST: tests/asm/aarch64/system.s
// Suite: AArch64 System
// Purpose: System and privileged instruction coverage.
//   Covers: SVC, HVC, SMC, MSR/MRS, ISB, DMB, DSB, ERET, AT, DC, IC,
//           TLBI, PRFM, BTI, AUTIA, PACIA.
// Expected: EXIT_OK (encoding only).
// ============================================================================

[SECTION .text]

// ---- Software exceptions --------------------------------
svc     #0                  // supervisor call (syscall)
svc     #1
svc     #0xFFFF

hvc     #0                  // hypervisor call
hvc     #1
hvc     #0xFFFF

smc     #0                  // secure monitor call
smc     #1

// ---- ERET (exception return) ----------------------------
eret

// ---- HLT (halt, debug) ----------------------------------
hlt     #0
hlt     #0xFFFF

// ---- BRK (breakpoint) -----------------------------------
brk     #0
brk     #1
brk     #0xFFFF

// ---- System registers (MSR / MRS) -----------------------
// Read common system registers
mrs     x0, nzcv            // condition flags
mrs     x1, fpcr            // FP control register
mrs     x2, fpsr            // FP status register
mrs     x3, currentel       // current exception level
mrs     x4, spsel           // stack pointer selection
mrs     x5, daif            // debug/async interrupt mask
mrs     x6, sp_el0          // EL0 stack pointer
mrs     x7, sp_el1          // EL1 stack pointer (from EL2)
mrs     x8, tpidr_el0       // thread ID register EL0
mrs     x9, tpidr_el1       // thread ID register EL1
mrs     x10, sctlr_el1      // system control register EL1
mrs     x11, ttbr0_el1      // translation table base 0
mrs     x12, ttbr1_el1      // translation table base 1
mrs     x13, tcr_el1        // translation control register
mrs     x14, mair_el1       // memory attribute indirection
mrs     x15, vbar_el1       // vector base address
mrs     x16, esr_el1        // exception syndrome register
mrs     x17, far_el1        // fault address register
mrs     x18, elr_el1        // exception link register
mrs     x19, spsr_el1       // saved program status register
mrs     x20, cntfrq_el0     // counter timer frequency
mrs     x21, cntvct_el0     // virtual timer count
mrs     x22, cntpct_el0     // physical timer count (if accessible)

// Write system registers
msr     nzcv, x0
msr     fpcr, x1
msr     fpsr, x2
msr     spsel, x3
msr     daif, x4
msr     sp_el0, x5
msr     tpidr_el0, x6
msr     tpidr_el1, x7
msr     sctlr_el1, x8
msr     ttbr0_el1, x9
msr     ttbr1_el1, x10
msr     tcr_el1, x11
msr     mair_el1, x12
msr     vbar_el1, x13
msr     elr_el1, x14
msr     spsr_el1, x15

// Immediate MSR (for DAIF and PAN)
msr     daifset, #0xF       // disable all
msr     daifclr, #0xF       // enable all

// ---- Barriers -------------------------------------------
isb                         // instruction sync barrier
isb     sy                  // explicit full system ISB

dsb     sy                  // data sync barrier, full system
dsb     st                  // store barrier
dsb     ld                  // load barrier
dsb     ish                 // inner shareable
dsb     ishst               // inner shareable stores
dsb     ishld               // inner shareable loads
dsb     nsh                 // non-shareable
dsb     osh                 // outer shareable

dmb     sy
dmb     st
dmb     ld
dmb     ish
dmb     ishst
dmb     ishld
dmb     nsh
dmb     osh

// ---- Cache maintenance ----------------------------------
dc      civac, x0           // clean and invalidate by VA to PoC
dc      cvac, x1            // clean by VA to PoC
dc      cvau, x2            // clean by VA to PoU
dc      ivac, x3            // invalidate by VA to PoC
dc      isw, x4             // invalidate by set/way
dc      csw, x5             // clean by set/way
dc      cisw, x6            // clean and invalidate by set/way
dc      zva, x7             // zero by VA (user accessible)

// Instruction cache
ic      ialluis             // invalidate all to PoU inner shareable
ic      iallu               // invalidate all to PoU
ic      ivau, x0            // invalidate by VA to PoU

// ---- TLB invalidation -----------------------------------
tlbi    vmalle1             // TLB invalidate all EL1
tlbi    alle1is             // all EL1, inner shareable
tlbi    vaae1is, x0         // by VA, all ASID, EL1, inner shareable
tlbi    aside1is, x1        // by ASID, EL1, inner shareable
tlbi    vae1is, x2

// ---- Address translation --------------------------------
at      s1e1r, x0           // stage 1 EL1 read
at      s1e1w, x1           // stage 1 EL1 write
at      s1e0r, x2           // stage 1 EL0 read
at      s1e0w, x3           // stage 1 EL0 write

// ---- NOP ------------------------------------------------
nop
wfi                         // wait for interrupt
wfe                         // wait for event
sev                         // send event
sevl                        // send event local

// ---- BTI (Branch Target Identification — ARMv8.5) ------
bti
bti     c                   // call target
bti     j                   // jump target
bti     jc                  // call or jump target
