// ============================================================================
// TEST: tests/asm/amd64/compare.s
// Suite: AMD64 Core
// Purpose: All comparison instructions — CMP, TEST, CMPXCHG, CMPXCHG8B,
//          CMPXCHG16B — all sizes and operand combinations.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- CMP (set flags, no result stored) ------------------
cmp     rax, rbx
cmp     rcx, 0
cmp     rdx, 1
cmp     r8,  -1
cmp     r9,  0xFF
cmp     r10, 0x7FFFFFFF
cmp     r11, 0x80000000
cmp     eax, ebx
cmp     eax, 0
cmp     eax, 0xFF
cmp     ax,  bx
cmp     ax,  0
cmp     al,  bl
cmp     al,  0
cmp     r8b, 0xFF

// ---- CMP with memory source ----------------------------
cmp     rax, [rbx]
cmp     rax, [rcx + 8]
cmp     rax, [rdx + rsi*4 + 16]
cmp     eax, [r8]
cmp     ax,  [r9 + 2]
cmp     al,  [r10]

// ---- CMP memory destination, reg/imm source -------------
cmp     [rax], rbx
cmp     [rcx + 8], rdx
cmp     [r12 + r13*4], r14
cmp     byte  [rax], 0
cmp     byte  [rbx + 1], 0xFF
cmp     word  [rcx], 0x1234
cmp     dword [rdx + 4], 0x12345678
cmp     qword [r8], 0x7FFFFFFF

// ---- TEST (AND, flags only) ----------------------------
test    rax, rax
test    rbx, rcx
test    rdx, 0xFF
test    r8,  0x7FFFFFFF
test    eax, eax
test    eax, 0xFF
test    ax,  0xFFFF
test    al,  al
test    al,  0x01
test    r9b, 0x80

// ---- TEST memory forms ----------------------------------
test    [rax], rbx
test    [rcx + 8], rdx
test    byte  [rdx], 0x01
test    dword [r8 + 4], 0x8000
test    qword [r9], rax

// ---- CMPXCHG (compare and exchange) --------------------
cmpxchg [rax], rbx
cmpxchg [rcx + 8], rdx
cmpxchg byte  [rdx], cl
cmpxchg word  [r8 + 2], dx
cmpxchg dword [r9], r10d
cmpxchg qword [r11 + r12*4 + 16], r13

// LOCK prefix forms
lock cmpxchg [rax], rbx
lock cmpxchg byte [rcx], dl
lock cmpxchg qword [rdx + 8], r8

// ---- CMPXCHG8B / CMPXCHG16B ---------------------------
cmpxchg8b  [rax]
cmpxchg8b  [rbx + 8]
lock cmpxchg8b  [rcx]
cmpxchg16b [rdx]
cmpxchg16b [r8 + 16]
lock cmpxchg16b [r9]
