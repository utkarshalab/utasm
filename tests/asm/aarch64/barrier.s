// ============================================================================
// TEST: tests/asm/aarch64/barrier.s
// Suite: AArch64 System
// Purpose: Memory barrier and synchronization instruction coverage.
//   Covers: ISB, DMB, DSB (all domains and types), LDAXR, STLXR,
//           LDAR, STLR, CAS, CASP — acquire/release semantics.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- ISB ------------------------------------------------
isb
isb     sy

// ---- DSB (data synchronization barrier) ----------------
dsb     sy
dsb     st
dsb     ld
dsb     ish
dsb     ishst
dsb     ishld
dsb     nsh
dsb     nshst
dsb     nshld
dsb     osh
dsb     oshst
dsb     oshld

// ---- DMB (data memory barrier) -------------------------
dmb     sy
dmb     st
dmb     ld
dmb     ish
dmb     ishst
dmb     ishld
dmb     nsh
dmb     nshst
dmb     nshld
dmb     osh
dmb     oshst
dmb     oshld

// ---- Acquire/Release load primitives -------------------
// LDAR (load acquire — all prior stores visible before this load)
ldar    x0, [x1]
ldar    w2, [x3]
ldarb   w4, [x5]
ldarh   w6, [x7]

// LDAPR (load acquire — RCpc, not sequentially consistent)
ldapr   x8, [x9]
ldapr   w10, [x11]
ldaprb  w12, [x13]
ldaprh  w14, [x15]

// LDAXR (load acquire exclusive)
ldaxr   x0, [x1]
ldaxr   w2, [x3]
ldaxrb  w4, [x5]
ldaxrh  w6, [x7]
ldaxp   x0, x1, [x2]

// ---- Acquire/Release store primitives ------------------
// STLR (store release — this store visible before all subsequent loads/stores)
stlr    x0, [x1]
stlr    w2, [x3]
stlrb   w4, [x5]
stlrh   w6, [x7]

// STLXR (store release exclusive — w0 = success/failure)
stlxr   w0, x1, [x2]
stlxr   w0, w3, [x4]
stlxrb  w0, w5, [x6]
stlxrh  w0, w7, [x8]
stlxp   w0, x1, x2, [x3]

// ---- CAS (compare and swap — LSE atomics) ---------------
cas     x0, x1, [x2]        // CAS (relaxed)
casa    x3, x4, [x5]        // CAS acquire
casl    x6, x7, [x8]        // CAS release
casal   x9, x10, [x11]      // CAS acquire+release
cas     w12, w13, [x14]
casb    w15, w16, [x17]
cash    w18, w19, [x20]

// CASP (compare and swap pair)
casp    x0, x1, x2, x3, [x4]
caspa   x0, x1, x2, x3, [x4]
caspl   x0, x1, x2, x3, [x4]
caspal  x0, x1, x2, x3, [x4]

// ---- SWP (swap — LSE atomics) ---------------------------
swp     x0, x1, [x2]
swpa    x3, x4, [x5]
swpl    x6, x7, [x8]
swpal   x9, x10, [x11]
swpb    w12, w13, [x14]
swph    w15, w16, [x17]

// ---- LDADD / STADD (atomic add — LSE) ------------------
ldadd   x0, x1, [x2]
ldadda  x3, x4, [x5]
ldaddl  x6, x7, [x8]
ldaddal x9, x10, [x11]
ldaddab w12, w13, [x14]      // byte
ldaddh  w15, w16, [x17]      // halfword
stadd   x0, [x1]             // store only variant
staddl  x2, [x3]

// ---- LDCLR / STCLR (atomic clear bits — LSE) -----------
ldclr   x0, x1, [x2]
ldclral x3, x4, [x5]
stclr   x6, [x7]

// ---- LDSET / STSET (atomic set bits — LSE) -------------
ldset   x0, x1, [x2]
ldsetal x3, x4, [x5]
stset   x6, [x7]

// ---- LDEOR / STEOR (atomic XOR — LSE) ------------------
ldeor   x0, x1, [x2]
ldeoral x3, x4, [x5]
steor   x6, [x7]

// ---- WFI / WFE / SEV (CPU idle hints) ------------------
wfi
wfe
sev
sevl
