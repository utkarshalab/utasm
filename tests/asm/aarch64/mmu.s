// ============================================================================
// TEST: tests/asm/aarch64/mmu.s
// Suite: AArch64 System
// Purpose: MMU and virtual memory management instruction coverage.
//   Covers: TLBI, DC, IC, AT, MSR/MRS for paging registers,
//           TCR/TTBR/MAIR initialization sequences.
// Expected: EXIT_OK (encoding only).
// ============================================================================

[SECTION .text]

// ---- TLBI (TLB invalidation) ----------------------------
tlbi    vmalle1                     // invalidate all TLB EL1
tlbi    vmalle1is                   // ...inner shareable
tlbi    alle1                       // all EL1
tlbi    alle1is                     // all EL1 IS
tlbi    alle2                       // all EL2
tlbi    alle2is                     // all EL2 IS
tlbi    alle3                       // all EL3
tlbi    alle3is                     // all EL3 IS
tlbi    vae1,   x0                  // by VA, EL1
tlbi    vae1is, x1                  // by VA, EL1, IS
tlbi    aside1, x2                  // by ASID, EL1
tlbi    aside1is, x3                // by ASID, EL1, IS
tlbi    vaae1,  x4                  // by VA all ASID EL1
tlbi    vaae1is, x5                 // by VA all ASID EL1 IS
tlbi    vaale1, x6                  // by VA all ASID last level EL1
tlbi    vae2,   x7                  // by VA, EL2
tlbi    vae3,   x8                  // by VA, EL3

// ---- Translation table setup idioms --------------------
// Load TCR_EL1
ldr     x0, =0x00000005B5193519     // TxSZ=25, TG0=4K, TG1=4K
msr     tcr_el1, x0
isb

// Load MAIR_EL1 (memory attribute indirection)
ldr     x0, =0xFF440C0400           // Device nGnRnE, Normal WB WA
msr     mair_el1, x0

// Load TTBR0/TTBR1
adrp    x0, .Lpagetable_base
msr     ttbr0_el1, x0
msr     ttbr1_el1, x0

// Enable MMU via SCTLR_EL1
mrs     x0, sctlr_el1
orr     x0, x0, #1                 // set M bit (enable MMU)
msr     sctlr_el1, x0
isb

// ---- DC (data cache operations) ------------------------
dc      ivac, x0                    // invalidate by VA to PoC
dc      cvac, x1                    // clean by VA to PoC
dc      civac, x2                   // clean + invalidate by VA to PoC
dc      cvau, x3                    // clean by VA to PoU
dc      cvap, x4                    // clean by VA to PoP
dc      isw, x5                     // invalidate by set/way
dc      csw, x6                     // clean by set/way
dc      cisw, x7                    // clean + invalidate by set/way
dc      zva, x8                     // zero by VA (page zero)

// ---- IC (instruction cache operations) -----------------
ic      ialluis                     // invalidate all IS
ic      iallu                       // invalidate all
ic      ivau, x0                    // invalidate by VA to PoU

// ---- AT (address translation) --------------------------
at      s1e1r, x0                   // EL1 stage 1 read
at      s1e1w, x1                   // EL1 stage 1 write
at      s1e0r, x2                   // EL0 stage 1 read
at      s1e0w, x3                   // EL0 stage 1 write
at      s12e1r, x4                  // EL2 stage 1+2 EL1 read
at      s12e1w, x5                  // EL2 stage 1+2 EL1 write
at      s12e0r, x6                  // EL2 stage 1+2 EL0 read
at      s12e0w, x7                  // EL2 stage 1+2 EL0 write
at      s1e2r, x8                   // EL2 stage 1 read
at      s1e2w, x9                   // EL2 stage 1 write
at      s1e3r, x10                  // EL3 stage 1 read
at      s1e3w, x11                  // EL3 stage 1 write

// Read PAR_EL1 (physical address register after AT)
mrs     x12, par_el1
tst     x12, #1                     // check F bit (translation failed)

[SECTION .data]
.Lpagetable_base:  dq 0
