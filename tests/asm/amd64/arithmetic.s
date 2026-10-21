// ============================================================================
// TEST: tests/asm/amd64/arithmetic.s
// Suite: AMD64 Core
// Purpose: Exhaustive arithmetic and logical instruction coverage.
//   Covers: ADD, SUB, IMUL, IDIV, MUL, DIV, INC, DEC, NEG, NOT,
//           AND, OR, XOR, ADC, SBB — all forms and size suffixes.
// Expected: EXIT_OK, all encodings accepted without error.
// ============================================================================

[SECTION .text]

// ---- ADD -----------------------------------------------
// reg64 + reg64
add     rax, rbx
add     r8,  r15
add     rsp, rbp

// reg64 + imm8 (sign-extended)
add     rax, 1
add     r12, -1
add     rsp, 8

// reg64 + imm32 (sign-extended)
add     rax, 0x7FFFFFFF
add     rbx, 0x12345678

// mem64 + reg64
add     [rax], rbx
add     [rbx + 8], rcx
add     [r12 + r13*4], rdx

// reg32 forms
add     eax, ebx
add     edi, 0xFF
add     r8d, r9d

// reg16 forms
add     ax, bx
add     cx, 0x7F

// reg8 forms
add     al,  bl
add     r8b, 0x10
add     spl, 1              // requires REX

// ---- SUB -----------------------------------------------
sub     rax, rbx
sub     rax, 1
sub     r15, 0x100
sub     [rax + 8], rbx
sub     eax, edx
sub     al, bl

// ---- ADC / SBB (carry-based) ---------------------------
adc     rax, rbx
adc     rax, 0
sbb     rcx, rdx
sbb     r8, 0xFF

// ---- IMUL ----------------------------------------------
// 2-operand
imul    rax, rbx
imul    rcx, rdx
imul    r8,  r9

// 3-operand (reg, reg, imm8)
imul    rax, rbx, 4
imul    rcx, rdx, -1
imul    r10, r11, 0x7F

// 3-operand (reg, reg, imm32)
imul    rax, rbx, 0x1000

// ---- MUL / DIV (unsigned, rAX implicit) ----------------
mul     rbx
mul     r9
mul     dword [rax]
div     rcx
div     r12
idiv    rdx
idiv    r15

// ---- INC / DEC -----------------------------------------
inc     rax
inc     r8
inc     dword [rbx]
inc     byte  [rcx + 4]
dec     rdi
dec     r15
dec     word  [rsp + 8]

// ---- NEG / NOT -----------------------------------------
neg     rax
neg     r14
neg     qword [rbx]
not     rcx
not     r12
not     byte  [rdx]

// ---- AND / OR / XOR ------------------------------------
and     rax, rbx
and     eax, 0xFF
and     al,  0x0F
and     [rax], rcx
or      rax, rbx
or      rax, 0x100
xor     rax, rax           // self-XOR (zero idiom)
xor     r15, r15
xor     rcx, 0xDEAD

// ---- TEST (non-destructive AND) ------------------------
test    rax, rax
test    eax, eax
test    al, al
test    r8, r9
test    r10, 0xFF

// ---- CMP -----------------------------------------------
cmp     rax, rbx
cmp     rcx, 0
cmp     r8,  0xFFFFFFFF
cmp     byte [rax], 0
cmp     word [rbx + 2], 0x1234
