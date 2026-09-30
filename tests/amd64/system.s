// ============================================================================
// TEST: tests/amd64/system.s
// Suite: AMD64 System
// Purpose: System/privileged instruction coverage.
//   Covers: SYSCALL/SYSRET, INT/IRET, HLT, RDTSC, RDMSR/WRMSR,
//           CPUID, RDPMC, LGDT/SGDT, LIDT/SIDT, LLDT/SLDT,
//           MOV CR/DR, CLTS, INVLPG, WBINVD.
// Expected: EXIT_OK (just encoding, no execution).
// ============================================================================

[SECTION .text]

// ---- Software interrupts --------------------------------
int     0x80            // Linux legacy syscall
int     0x03            // breakpoint (INT 3 short form)
int3                    // short breakpoint encoding
int     0xFF            // max interrupt vector
// into: not valid in 64-bit mode
iret                    // interrupt return (16-bit)
iretd                   // interrupt return (32-bit)
iretq                   // interrupt return (64-bit)

// ---- SYSCALL / SYSRET -----------------------------------
syscall
sysret
sysretq

// ---- Halt / NOP / UD2 -----------------------------------
hlt
nop
ud2                     // guaranteed invalid (for testing traps)

// ---- RDTSC / RDTSCP / RDPMC ----------------------------
rdtsc
rdtscp
rdpmc

// ---- CPUID ----------------------------------------------
cpuid

// ---- MSR access -----------------------------------------
rdmsr                   // read MSR[ECX] → EDX:EAX
wrmsr                   // write MSR[ECX] ← EDX:EAX

// ---- Control Register access ----------------------------
mov     rax, cr0
mov     rax, cr2
mov     rax, cr3
mov     rax, cr4
mov     rax, cr8        // TPR shadow (VMX)
mov     cr0, rax
mov     cr3, rbx
mov     cr4, rcx
mov     cr8, rdx

// ---- Debug Register access ------------------------------
mov     rax, dr0
mov     rax, dr1
mov     rax, dr2
mov     rax, dr3
mov     rax, dr6
mov     rax, dr7
mov     dr0, rax
mov     dr6, rbx
mov     dr7, rcx

// ---- Descriptor table operations -----------------------
lgdt    [rax]           // load GDT register
sgdt    [rbx]           // store GDT register
lidt    [rcx]           // load IDT register
sidt    [rdx]           // store IDT register
lldt    ax              // load LDT selector
sldt    ax              // store LDT selector
ltr     ax              // load task register
str     ax              // store task register

// ---- TLB / Cache management ----------------------------
invlpg  [rax]           // invalidate TLB entry
wbinvd                  // write-back and invalidate D-cache
clts                    // clear task-switched flag in CR0

// ---- Segment override concepts (prefix) ----------------
mov     rax, [fs:rbx]   // FS-relative load
mov     rax, [gs:rcx]   // GS-relative load
mov     [fs:rdx], rax   // FS-relative store
mov     [gs:r8], rbx    // GS-relative store

// ---- SWAPGS (fast OS/user GS swap) ---------------------
swapgs

// ---- XSETBV / XGETBV (extended state control) ----------
xsetbv                  // write XCR[ECX] ← EDX:EAX
xgetbv                  // read  XCR[ECX] → EDX:EAX

// ---- MONITOR / MWAIT (enhanced halt) --------------------
monitor
mwait

// ---- CLAC / STAC (SMAP) --------------------------------
clac
stac

// ---- String repeat with REP prefix ----------------------
rep     movsb
rep     movsw
rep     movsd
rep     movsq
rep     stosb
rep     stosw
rep     stosd
rep     stosq
rep     lodsb
repe    cmpsb
repe    scasb
repne   cmpsb
repne   scasb

// ---- PAUSE (spin-wait hint) ----------------------------
pause

// ---- Bound / ENTER / LEAVE (legacy) --------------------
enter   64, 0
leave
