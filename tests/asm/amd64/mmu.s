// ============================================================================
// TEST: tests/asm/amd64/mmu.s
// Suite: AMD64 System
// Purpose: MMU and virtual memory management instruction coverage.
//   Covers: INVLPG, INVPCID, MOV CR3, CLFLUSH, SWAPGS,
//           segment register loads, paging structure manipulation.
// Expected: EXIT_OK (encoding only).
// ============================================================================

[SECTION .text]

// ---- TLB Invalidation -----------------------------------
invlpg  [rax]               // invalidate TLB entry for virtual address
invlpg  [rbx + 0x1000]
invlpg  [rcx + rdx*4]

// INVPCID (invalidate process-context identifier entries)
invpcid rax, [rbx]          // form: invpcid reg64, m128
invpcid rcx, [rdx + 16]

// ---- Paging enable/disable (MOV CR0) -------------------
mov     rax, cr0
or      rax, 0x80000001     // set PE and PG bits
mov     cr0, rax

// ---- Page directory pointer (MOV CR3) ------------------
mov     rax, cr3            // read current CR3 (PDBR)
mov     rbx, 0x100000       // new page directory physical addr
mov     cr3, rbx            // flush TLB by writing CR3

// ---- CR4 Feature flags (PAE, PSE, PGE, SMEP, SMAP) ----
mov     rax, cr4
or      rax, 0x20           // set PAE
or      rax, 0x200          // set PGE
or      rax, 0x100000       // set SMEP
or      rax, 0x200000       // set SMAP
mov     cr4, rax

// ---- Segment descriptor table operations ---------------
lgdt    [rax]
sgdt    [rbx]
lidt    [rcx]
sidt    [rdx]

// ---- Segment register loads ----------------------------
// Note: segment loads in 64-bit only meaningful for FS/GS
mov     ax, 0x10            // kernel data selector
// mov  ss, ax             // ring-0 only
// mov  ds, ax
// mov  es, ax
// mov  fs, ax
// mov  gs, ax

// ---- SWAPGS (fast privilege switch) --------------------
swapgs                      // swap GS.base with KernelGSBase MSR

// ---- Cache flush/writeback --------------------------------
wbinvd                      // write-back and invalidate caches
clts                        // clear TS in CR0 (required before FPU access)

// ---- VERR / VERW (verify segment for read/write) -------
verr    ax
verw    ax

// ---- LSL / LAR (load segment limit/attributes) ---------
lsl     rax, rbx
lar     rax, rbx
lsl     rax, [rcx]
lar     rax, [rdx]

// ---- ARPL (adjust requested privilege level — 32-bit) --
// arpl    ax, bx          // not valid in 64-bit mode

// ---- STR / LTR (task register) -------------------------
str     ax
ltr     ax

// ---- LLDT / SLDT (local descriptor table register) -----
sldt    ax
lldt    ax
sldt    [rax]
lldt    [rbx]
