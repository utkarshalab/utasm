// ============================================================================
// TEST: tests/asm/amd64/mov.s
// Suite: AMD64 Core
// Purpose: Exhaustive MOV, MOVZX, MOVSX, MOVSXD, XCHG, CMOV coverage.
//   All operand sizes: 8, 16, 32, 64 bits.
//   All addressing modes: immediate, register, direct memory, SIB, RIP-rel.
// Expected: EXIT_OK, all encodings accepted.
// ============================================================================

[SECTION .text]

// ---- MOV reg, imm ---------------------------------------
mov     rax, 0
mov     rax, 1
mov     rax, 0xFF
mov     rax, 0xFFFF
mov     rax, 0xFFFFFFFF
mov     rax, 0xFFFFFFFFFFFFFFFF   // 64-bit immediate (movabs)
mov     rax, -1
mov     r8,  0x1122334455667788
mov     r15, 0
mov     eax, 0x12345678
mov     ecx, 0
mov     r9d, 0xABCD
mov     ax,  0x1234
mov     bx,  0xFFFF
mov     al,  0xAB
mov     r8b, 0x01
mov     spl, 0              // REX-required low byte

// ---- MOV reg, reg ---------------------------------------
mov     rax, rbx
mov     rcx, rdx
mov     r8,  r15
mov     rsp, rbp
mov     eax, ebx
mov     r8d, r9d
mov     ax,  bx
mov     al,  bl
mov     r8b, r9b

// ---- MOV reg, mem (load) --------------------------------
mov     rax, [rbx]
mov     rcx, [r12]
mov     rdx, [rsp]
mov     r8,  [rbp - 8]
mov     rax, [rbx + 4]
mov     rcx, [rdx + 16]
mov     r9,  [r13 + 0x100]
// SIB
mov     rax, [rbx + rcx*1]
mov     rdx, [rsp + r12*2]
mov     r8,  [r13 + r14*4]
mov     r15, [r12 + r15*8]
// SIB + disp
mov     rax, [rbx + rcx*4 + 8]
mov     rdx, [rsp + r12*8 + 0x100]
// 32-bit loads
mov     eax, [rbx]
mov     r9d, [r14 + 4]
// 16-bit loads
mov     ax,  [rbx]
mov     bx,  [rax + 2]
// 8-bit loads
mov     al,  [rbx]
mov     r8b, [rcx + 1]

// ---- MOV mem, reg (store) --------------------------------
mov     [rax], rbx
mov     [rcx + 8], rdx
mov     [r12 + r13*4], rsi
mov     [rsp - 8], r14
// sized stores
mov     dword [rax], ecx
mov     word  [rbx + 2], dx
mov     byte  [rcx],  al
mov     byte  [r8 + 4], r9b

// ---- MOV mem, imm (store immediate) ----------------------
mov     qword [rax], 0
mov     qword [rbx + 8], 0x7FFFFFFF
mov     dword [rcx],     0x12345678
mov     word  [rdx + 2], 0x1234
mov     byte  [rsi],     0xAB
mov     byte  [r12 + r13 + 4], 1

// ---- MOV control/debug registers -------------------------
mov     rax, cr0
mov     rax, cr2
mov     rax, cr3
mov     rax, cr4
mov     rax, cr8
mov     cr0, rax
mov     cr3, rbx
mov     cr8, rcx
mov     rax, dr0
mov     rax, dr6
mov     rax, dr7
mov     dr0, rax
mov     dr7, rbx

// ---- MOVZX (zero-extend) ---------------------------------
movzx   eax, byte  [rbx]
movzx   eax, word  [rcx]
movzx   rax, byte  [rdx]
movzx   rax, word  [r8]
movzx   r9d, byte  al
movzx   r10, word  bx

// ---- MOVSX (sign-extend) ---------------------------------
movsx   eax, byte  [rbx]
movsx   eax, word  [rcx]
movsx   rax, byte  [rdx]
movsx   rax, word  [r8]
movsx   rax, dword [r9]    // MOVSXD equivalent
movsx   r9d, byte  al
movsx   r10, word  cx

// ---- XCHG -----------------------------------------------
xchg    rax, rbx
xchg    r12, r13
xchg    eax, ecx
xchg    [rax], rbx         // memory form (implicit LOCK)

// ---- CMOVcc (conditional moves) -------------------------
cmove   rax, rbx
cmovne  rcx, rdx
cmovl   r8,  r9
cmovle  r10, r11
cmovg   r12, r13
cmovge  r14, r15
cmova   rax, rbx           // unsigned above
cmovb   rcx, rdx           // unsigned below
cmovs   rax, rbx           // sign bit
cmovns  rcx, rdx
cmovz   rax, rbx           // alias for cmove
cmovnz  rcx, rdx           // alias for cmovne

// ---- LEA (load effective address) -----------------------
lea     rax, [rbx]
lea     rcx, [rdx + 8]
lea     r8,  [r12 + r13*4]
lea     r9,  [r14 + r15*8 + 0x1000]
lea     eax, [rbx + 4]
