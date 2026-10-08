// ============================================================================
// TEST: tests/amd64/logic.s
// Suite: AMD64 Core
// Purpose: Pure logical / bitwise operation coverage.
//   Covers: AND, OR, XOR, NOT, TEST, BT/BTS/BTR/BTC, BSF, BSR,
//           POPCNT, LZCNT, TZCNT — all operand sizes and forms.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- AND -----------------------------------------------
and     rax, rbx
and     rax, 0xFF
and     rax, 0x7FFFFFFF
and     eax, 0xFF
and     ax,  0x0F
and     al,  0x01
and     [rax], rbx
and     [rcx + 8], rdx
and     byte  [rdx], 0xF0
and     dword [r8], 0x12345678

// ---- OR ------------------------------------------------
or      rax, rbx
or      rax, 0xFF
or      eax, 0x100
or      ax,  0xFFFF
or      al,  0x80
or      [rax], rbx
or      byte [rcx], 0x01

// ---- XOR -----------------------------------------------
xor     rax, rax            // zero idiom
xor     r15, r15
xor     rax, rbx
xor     rax, 0xFF
xor     eax, 0x12345678
xor     ax,  0x1234
xor     al,  0xFF
xor     [rax], rbx
xor     byte [rcx + 4], 0xAA

// ---- NOT -----------------------------------------------
not     rax
not     rbx
not     r12
not     eax
not     ax
not     al
not     qword [rax]
not     dword [rbx + 4]
not     word  [rcx + 2]
not     byte  [rdx]

// ---- TEST (AND without storing) -------------------------
test    rax, rax
test    rbx, rcx
test    eax, eax
test    ax,  ax
test    al,  al
test    r8,  r9
test    rax, 0xFF
test    eax, 0x12345678
test    byte [rbx], 0x01
test    dword [rcx + 4], 0xFF

// ---- Bit Test: BT / BTS / BTR / BTC --------------------
// BT — test bit N of reg/mem
bt      rax, 5
bt      rax, rcx
bt      dword [rbx], 8
bt      [rcx + 4], rdx

// BTS — test and set
bts     rax, 4
bts     rax, rcx
bts     dword [rdx], 16
lock bts [r8 + r9*4], r10

// BTR — test and reset
btr     rbx, 3
btr     rbx, rdi
btr     dword [rax], 7
lock btr [rcx], rsi

// BTC — test and complement
btc     rcx, 2
btc     rcx, rbx
btc     dword [rdx + 8], 0
lock btc [r11], r12

// ---- BSF / BSR (bit scan forward/reverse) ---------------
bsf     rax, rbx
bsf     rcx, [rdx]
bsf     eax, ecx
bsr     rax, rbx
bsr     rcx, [rdx + 4]
bsr     r8,  r9

// ---- POPCNT (population count) -------------------------
popcnt  rax, rbx
popcnt  rcx, [rdx]
popcnt  eax, ecx
popcnt  r8,  [r9 + 4]

// ---- LZCNT (leading zero count) -------------------------
lzcnt   rax, rbx
lzcnt   rcx, [rdx]
lzcnt   eax, ecx

// ---- TZCNT (trailing zero count) ------------------------
tzcnt   rax, rbx
tzcnt   rcx, [rdx + 8]
tzcnt   r8,  r9
