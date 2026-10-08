// ============================================================================
// TEST: tests/amd64/barrier.s
// Suite: AMD64 Core
// Purpose: Memory barrier and synchronization instruction coverage.
//   Covers: MFENCE, SFENCE, LFENCE, PAUSE, LOCK prefix, XCHG implicit lock,
//           CMPXCHG with LOCK, serialization instructions.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Store fence (prevents store reordering) -----------
sfence              // serialize all prior stores

// ---- Load fence (prevents load reordering) -------------
lfence              // serialize all prior loads

// ---- Full memory fence ---------------------------------
mfence              // serialize all prior loads AND stores

// ---- PAUSE (spin-wait hint — reduces power + avoids speculation penalty) ---
pause

// ---- LOCK prefix: atomic read-modify-write -------------
lock add  [rax], rbx
lock add  dword [rbx], 1
lock sub  [rcx], rdx
lock sub  dword [rdx], 1
lock adc  [r8], r9
lock sbb  [r10], r11
lock and  [rax], rbx
lock or   [rcx], rdx
lock xor  [r12], r13
lock inc  dword [r14]
lock dec  dword [r15]
lock neg  dword [rax]
lock not  dword [rbx]
lock xchg [rcx], rdx       // XCHG is always atomic
lock xadd [rdx], r8
lock cmpxchg [r9], r10
lock cmpxchg8b  [rax]
lock cmpxchg16b [rbx]

// Byte, word, dword LOCK forms
lock add  byte  [rax], 1
lock add  word  [rbx], 1
lock add  dword [rcx], 1
lock xor  byte  [rdx], 0xFF
lock or   word  [r8],  0x8000

// ---- Serialization (full pipeline flush) ---------------
cpuid               // cpuid is a serialization barrier
rdtscp              // reads TSC + aux after completing all prior instructions

// ---- Write ordering idiom used in OS kernels -----------
mfence
mov     qword [rax], 0     // release store (visible after fence)

// ---- Acquire load idiom --------------------------------
mov     rbx, [rax]         // load
lfence                     // all subsequent reads see this result

// ---- Segment-prefix barriers (legacy x86) ---------------
// These effectively operate as full barriers on x86
lock xchg [rsp], rax       // historically used as full barrier

// ---- CLFLUSH / CLFLUSHOPT / CLWB ----------------------
clflush     [rax]
clflush     [rbx + 64]
clflushopt  [rcx]
clflushopt  [rdx + 128]
clwb        [r8]
clwb        [r9 + 256]

// ---- WC (write-combining) store (MOVNTI + SFENCE) -------
movnti  [rax], rbx
movnti  [rcx + 8], rdx
sfence                      // ensure WC stores reach memory
