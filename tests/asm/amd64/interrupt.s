// ============================================================================
// TEST: tests/asm/amd64/interrupt.s
// Suite: AMD64 System
// Purpose: Interrupt, exception, and trap instruction coverage.
//   Covers: INT n (all vectors), INT3, INTO, IRET/IRETQ, UD2,
//           debug traps, software breakpoints.
// Expected: EXIT_OK (just encoding).
// ============================================================================

[SECTION .text]

// ---- Software interrupt vectors (full range) -----------
int     0           // divide error
int     1           // debug
int     2           // NMI
int     3           // breakpoint (cc opcode — same as int3)
int     4           // overflow
int     5           // bound range exceeded
int     6           // invalid opcode
int     7           // device not available
int     8           // double fault
int     9           // FPU segment overrun (legacy)
int     10          // invalid TSS
int     11          // segment not present
int     12          // stack-segment fault
int     13          // general protection fault
int     14          // page fault
int     15          // reserved
int     16          // x87 FPU floating-point error
int     17          // alignment check
int     18          // machine check
int     19          // SIMD floating-point exception
int     20          // virtualization exception

// User-defined vectors
int     0x21        // legacy DOS
int     0x2E        // Windows syscall (legacy)
int     0x80        // Linux syscall (legacy)
int     0xFF        // max vector

// ---- INT3 (special 1-byte breakpoint encoding) ---------
int3

// ---- INTO (overflow trap) ------------------------------
// into -- legacy 32-bit instruction (not valid in 64-bit mode)
// into

// ---- UD2 (guaranteed illegal instruction) --------------
ud2

// ---- IRET family ----------------------------------------
iret                // 16-bit return from interrupt
iretd               // 32-bit return from interrupt
iretq               // 64-bit return from interrupt

// ---- Breakpoint patterns used in debuggers -------------
nop                 // sometimes used as soft-break insertion point
int3
nop

// ---- Stack state for interrupt handler -----------------
// Simulate what the CPU pushes on interrupt entry:
// [rsp+0]  = RIP (return address)
// [rsp+8]  = CS
// [rsp+16] = RFLAGS
// [rsp+24] = RSP (if privilege change)
// [rsp+32] = SS   (if privilege change)

// Handler epilogue that restores this frame:
push    rbp
mov     rbp, rsp
// ... handler body ...
mov     rsp, rbp
pop     rbp
iretq
