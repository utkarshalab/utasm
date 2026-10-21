// ============================================================================
// TEST: tests/asm/riscv64/mmu.s
// Suite: RISC-V 64 Core
// Purpose: MMU and virtual memory management instruction coverage.
//   Covers: SFENCE.VMA, SATP (CSR) manipulation, page table setup idioms.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- TLB Invalidation -----------------------------------
sfence.vma                  // global flush
sfence.vma  zero, zero      // same as above
sfence.vma  a0, zero        // flush specific virtual address
sfence.vma  zero, a1        // flush specific ASID
sfence.vma  a0, a1          // flush specific addr and ASID

// ---- Paging Setup (SATP) --------------------------------
// satp: [63:60] MODE, [59:44] ASID, [43:0] PPN
li      t0, (8 << 60)       // Mode 8 = Sv39
adrp    t1, .Lpage_table
srli    t1, t1, 12          // shift to PPN
or      t0, t0, t1
csrw    satp, t0            // enable paging
sfence.vma                  // sync TLB

// ---- Memory Attributes (PMA/PMP) -----------------------
csrr    t0, pmpcfg0
csrw    pmpaddr0, a0

[SECTION .data]
.align 4096
.Lpage_table:
    resb 4096               // placeholder root page table
