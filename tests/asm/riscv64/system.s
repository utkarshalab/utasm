// ============================================================================
// TEST: tests/asm/riscv64/system.s
// Suite: RISC-V 64 Core
// Purpose: System instruction and CSR coverage.
//   Covers: ECALL, EBREAK, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI,
//           FENCE, FENCE.I, SFENCE.VMA, WFI, MRET, SRET, URET.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Environment Call / Breakpoint ----------------------
ecall                       // syscall
ebreak                      // trap/breakpoint

// ---- CSR Access (Atomic) -------------------------------
csrrw   a0, mstatus, a1     // write mstatus, read old value to a0
csrrs   a2, mepc, a3        // set bits in mepc using a3 mask
csrrc   a4, mtvec, a5       // clear bits in mtvec using a5 mask

// Immediate versions (5-bit imm)
csrrwi  a0, mstatus, 3
csrrsi  a1, mepc, 1
csrrci  a2, mtvec, 0

// Pseudo CSR read/write
csrr    a0, mstatus         // read CSR
csrw    mstatus, a1         // write CSR
csrs    mstatus, a1         // set bits
csrc    mstatus, a1         // clear bits
csrwi   mstatus, 1          // write imm
csrsi   mstatus, 1          // set imm
csrci   mstatus, 1          // clear imm

// ---- Barriers -------------------------------------------
fence                       // full fence
fence   iorw, iorw          // explicit predecessor/successor
fence   rw, rw
fence   r, r
fence   w, w
fence.i                     // instruction fetch fence

// ---- Privilege Transitions ------------------------------
mret                        // machine-mode return
sret                        // supervisor-mode return
uret                        // user-mode return (N extension)
wfi                         // wait for interrupt

// ---- MMU / Virtual Memory -------------------------------
sfence.vma                  // flush all TLB
sfence.vma a0               // flush for specific asid/addr (depending on form)
sfence.vma a0, a1

// ---- Common CSRs ----------------------------------------
csrr    a0, ucycle          // user cycle counter
csrr    a1, utime           // user time counter
csrr    a2, uinstret        // user instructions retired
csrr    t0, mhartid         // hart ID
csrr    t1, misa            // ISA extension register
