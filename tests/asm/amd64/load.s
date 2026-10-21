// ============================================================================
// TEST: tests/asm/amd64/load.s
// Suite: AMD64 Core
// Purpose: All load instruction forms: MOV (load), MOVZX, MOVSX, MOVSXD,
//          LODSx, CMOVcc loads, all size prefixes.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- QWORD loads (64-bit) --------------------------------
mov     rax, [rbx]
mov     rax, [rcx + 8]
mov     rax, [rdx + rsi*4]
mov     rax, [r8 + r9*8 + 16]
mov     r12, [rsp]
mov     r13, [rbp - 8]
mov     r14, [r15 + 0x100]

// ---- DWORD loads (32-bit, zero-extend to 64) ------------
mov     eax, [rbx]
mov     ecx, [rdx + 4]
mov     r9d, [r10 + 8]
mov     r11d, [r12 + r13*2 + 4]

// ---- WORD loads (16-bit) ---------------------------------
mov     ax,  [rbx]
mov     bx,  [rcx + 2]
mov     r8w, [r9 + 4]

// ---- BYTE loads (8-bit) ----------------------------------
mov     al,  [rbx]
mov     bl,  [rcx + 1]
mov     r8b, [r9]
mov     sil, [rax]          // REX-required low byte of RSI
mov     dil, [rbx]

// ---- MOVZX (zero-extend loads) ---------------------------
movzx   eax, byte  [rbx]
movzx   eax, word  [rcx]
movzx   rax, byte  [rdx]
movzx   rax, word  [r8]
movzx   r9,  byte  [r10 + 4]
movzx   r11, word  [r12 + r13*2]

// ---- MOVSX / MOVSXD (sign-extend loads) -----------------
movsx   eax, byte  [rbx]
movsx   eax, word  [rcx]
movsx   rax, byte  [rdx]
movsx   rax, word  [r8]
movsx   rax, dword [r9]         // MOVSXD
movsx   r10, byte  [r11 + 4]
movsx   r12, word  [r13 + r14*4 + 8]

// ---- LODS (string loads) ---------------------------------
lodsb                           // AL  = [RSI]; RSI += DF?1:-1
lodsw                           // AX  = [RSI]
lodsd                           // EAX = [RSI]
lodsq                           // RAX = [RSI]

// ---- CMOVcc with memory source --------------------------
cmove   rax, [rbx]
cmovne  rcx, [rdx + 8]
cmovl   r8,  [r9]
cmovge  r10, [r11 + r12*4]
cmova   r13, [r14]
cmovb   r15, [rax + 16]

// ---- BSWAP (byte-swap, not strictly load but related) ---
bswap   rax
bswap   rbx
bswap   r12
bswap   eax
bswap   r9d

// ---- MOVBE (move with byte-swap, big-endian aware) ------
movbe   rax, [rbx]
movbe   eax, [rcx + 4]
movbe   ax,  [rdx + 2]
