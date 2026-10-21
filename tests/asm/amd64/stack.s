// ============================================================================
// TEST: tests/asm/amd64/stack.s
// Suite: AMD64 Core
// Purpose: Stack operation coverage.
//   Covers: PUSH (reg, imm, mem), POP (reg, mem),
//           PUSHA/POPA (legacy), PUSHF/POPF,
//           RSP alignment manipulation, ENTER/LEAVE.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- PUSH reg64 ----------------------------------------
push    rax
push    rbx
push    rcx
push    rdx
push    rsi
push    rdi
push    rbp
push    rsp
push    r8
push    r9
push    r10
push    r11
push    r12
push    r13
push    r14
push    r15

// ---- PUSH imm ------------------------------------------
push    0                   // imm8 (zero)
push    1                   // imm8
push    0x7F                // imm8 max
push    0x80                // imm32 (sign-extended)
push    0x12345678          // imm32
push    -1                  // imm8 (-1 fits in sign-extended imm8)
push    0x7FFFFFFF          // max positive imm32

// ---- PUSH mem ------------------------------------------
push    qword [rax]
push    qword [rbx + 8]
push    qword [rcx + rdx*8]
push    qword [rsp + 16]
push    qword [rbp - 8]

// ---- POP reg64 -----------------------------------------
pop     rax
pop     rbx
pop     rcx
pop     rdx
pop     rsi
pop     rdi
pop     rbp
pop     r8
pop     r9
pop     r10
pop     r11
pop     r12
pop     r13
pop     r14
pop     r15

// ---- POP mem -------------------------------------------
pop     qword [rax]
pop     qword [rbx + 16]
pop     qword [r12 + r13*4 + 8]

// ---- PUSHF / POPF (flags) ------------------------------
pushf
popf
pushfq
popfq

// ---- ENTER / LEAVE -------------------------------------
enter   0, 0                // no locals, nesting 0
enter   64, 0               // 64 bytes locals
enter   0x100, 1            // with nesting level
leave

// ---- RSP alignment idiom --------------------------------
// Common sequence for 16-byte alignment before syscalls/calls
and     rsp, -16
sub     rsp, 128
add     rsp, 128

// ---- Stack frame setup/teardown idiom -------------------
push    rbp
mov     rbp, rsp
sub     rsp, 32
mov     rsp, rbp
pop     rbp
ret
