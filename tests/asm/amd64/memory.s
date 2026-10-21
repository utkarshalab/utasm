// ============================================================================
// TEST: tests/asm/amd64/memory.s
// Suite: AMD64 Core
// Purpose: Addressing mode exhaustion.
//   Covers: All ModRM/SIB combinations, disp8, disp32, RIP-relative,
//           segment overrides (concept), size overrides, memory barriers.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Register indirect (disp = 0) ----------------------
mov     rax, [rbx]
mov     rax, [rcx]
mov     rax, [rdx]
mov     rax, [rsi]
mov     rax, [rdi]
mov     rax, [rbp]          // needs disp8=0 override
mov     rax, [rsp]          // needs SIB
mov     rax, [r8]
mov     rax, [r9]
mov     rax, [r12]          // needs SIB
mov     rax, [r13]          // needs disp8=0 override
mov     rax, [r14]
mov     rax, [r15]

// ---- Base + disp8 (signed -128..127) --------------------
mov     rax, [rbx + 0]
mov     rax, [rbx + 1]
mov     rax, [rbx + 127]
mov     rax, [rbx - 1]
mov     rax, [rbx - 128]
mov     rax, [r12 + 8]
mov     rax, [r13 + 4]

// ---- Base + disp32 (> 127 or < -128) -------------------
mov     rax, [rbx + 128]
mov     rax, [rbx + 0x1000]
mov     rax, [rbx + 0x7FFFFFFF]
mov     rax, [rbx - 129]
mov     rax, [rbx - 0x1000]

// ---- SIB: base + index*scale ----------------------------
mov     rax, [rbx + rcx*1]
mov     rax, [rbx + rcx*2]
mov     rax, [rbx + rcx*4]
mov     rax, [rbx + rcx*8]
mov     rax, [rdx + rsi*1]
mov     rax, [rdi + rbp*2]
mov     rax, [rsp + rax*4]
mov     rax, [r8  + r9*8]
mov     rax, [r12 + r13*4]
mov     rax, [r14 + r15*1]

// ---- SIB + disp8 ----------------------------------------
mov     rax, [rbx + rcx*4 + 0]
mov     rax, [rbx + rcx*4 + 8]
mov     rax, [rbx + rcx*4 - 8]
mov     rax, [r8  + r9*8  + 16]
mov     rax, [rsp + rax*1 + 4]

// ---- SIB + disp32 ---------------------------------------
mov     rax, [rbx + rcx*4 + 0x1000]
mov     rax, [r12 + r13*8 + 0x7FFFFFFF]
mov     rax, [rsp + rax*2 - 0x1000]

// ---- Index-only (base = RIP-relative disp32) -----------
// [rip + disp32] — standard RIP-relative
mov     rax, [rel data_label]
lea     rcx, [rel data_label]

// ---- Mixed size operands --------------------------------
mov     dword [rax], 0x1234     // 32-bit store
mov     word  [rbx + 2], 0xAB   // 16-bit store
mov     byte  [rcx + 1], 0x01   // 8-bit store
movzx   eax, byte  [rdx]        // zero-extend load
movzx   rax, word  [r8 + 4]
movsx   rax, dword [r9]

// ---- XCHG with memory (implicit LOCK) ------------------
xchg    [rax], rbx
xchg    [rcx + 8], rdx

// ---- CMPXCHG -------------------------------------------
lock cmpxchg [rax], rbx
lock cmpxchg byte [rcx], dl
lock cmpxchg word [rdx + 2], cx
lock cmpxchg dword [r8], r9d
lock cmpxchg qword [r12 + r13*4 + 8], r14

// ---- CMPXCHG8B / CMPXCHG16B ---------------------------
lock cmpxchg8b  [rax]
lock cmpxchg16b [rbx]

// ---- XADD (atomic add + exchange) ----------------------
lock xadd [rax], rbx
lock xadd byte [rcx], al
lock xadd dword [rdx], ecx

[SECTION .data]
data_label: dq 0
