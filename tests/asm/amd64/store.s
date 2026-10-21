// ============================================================================
// TEST: tests/asm/amd64/store.s
// Suite: AMD64 Core
// Purpose: All store instruction forms: MOV (store), STOSx, string stores,
//          MOVNTI (non-temporal), all sizes.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- QWORD stores (64-bit) ------------------------------
mov     [rax], rbx
mov     [rcx + 8], rdx
mov     [rsi + rdi*4], r8
mov     [r12 + r13*8 + 32], r14
mov     [rsp - 8], rbp
mov     [rbp + 16], r15

// ---- DWORD stores (32-bit) ------------------------------
mov     [rax], ecx
mov     [rbx + 4], edx
mov     [r8 + r9*2], r10d
mov     [rsp + 8], r11d

// ---- WORD stores (16-bit) --------------------------------
mov     [rax], bx
mov     [rcx + 2], dx
mov     [r12 + 4], r9w

// ---- BYTE stores (8-bit) ---------------------------------
mov     [rax], bl
mov     [rcx + 1], dl
mov     [r8], r9b
mov     [rsp + 8], sil      // REX-required low byte
mov     [rbp - 1], dil

// ---- Store immediate to memory ---------------------------
mov     qword [rax], 0
mov     qword [rbx + 8], 1
mov     qword [rcx + rdx*4], 0x7FFFFFFF
mov     dword [rsi], 0x12345678
mov     dword [rdi + 4], 0
mov     word  [r8],     0xABCD
mov     byte  [r9],     0xFF
mov     byte  [r10 + r11 + 4], 0

// ---- STOS (string stores) --------------------------------
stosb                           // [RDI] = AL;  RDI += DF?-1:1
stosw                           // [RDI] = AX
stosd                           // [RDI] = EAX
stosq                           // [RDI] = RAX

// ---- MOVNTI (non-temporal store, bypasses cache) --------
movnti  [rax], rbx
movnti  [rcx + 8], rdx
movnti  [r12 + r13*4], r14
movnti  [rsp + 16], r15
movnti  [rax], ecx          // 32-bit form
movnti  [rdx], r9d

// ---- CLFLUSH (cache line flush) -------------------------
clflush [rax]
clflush [rbx + 8]
clflush [r12 + r13*4 + 16]

// ---- CLFLUSHOPT (optimized flush) -----------------------
clflushopt [rax]
clflushopt [rbx + 32]

// ---- CLWB (cache line write-back) -----------------------
clwb    [rax]
clwb    [rcx + 64]

// ---- MFENCE / SFENCE / LFENCE ---------------------------
mfence
sfence
lfence
