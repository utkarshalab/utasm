// ============================================================================
// UtkarshaLab Test Suite
// Architecture: AMD64 (x86_64)
// Description: Comprehensive coverage for the utasm AMD64 encoder.
// ============================================================================

[SECTION .text]

// ---- 1. Data Transfer & Stack ----
mov rax, rbx
mov rcx, 0x123456789ABCDEF0
mov r8, r9
mov byte [rax], 0x12
mov word [rbx + 4], 0x1234
mov dword [rcx + rdx*4], 0x12345678
mov qword [r15 + r14*8 + 0x7F], 0x11223344

push rax
push r15
push qword [rsp + 8]
pop rbx
pop r12
pop qword [rbp - 16]

// ---- 2. Arithmetic & Logic ----
add rax, rbx
sub r10, r11
imul rsi, rdi
imul r8, r9, 0x40
and eax, 0xFF
or rcx, rdx
xor r15, r15
not qword [rax]
neg byte [rbx + rcx]
inc r14
dec r13

// ---- 3. Shifts & Rotates ----
shl rax, 4
shr rbx, cl
sar r10, 1
rol rcx, 8
ror rdx, cl

// ---- 4. Control Flow ----
jmp _label_near
je _label_near
jne _label_near
call _label_near
ret

_label_near:
jmp qword [rax]
call qword [rbx + 0x10]

// ---- 5. Control Registers & System ----
mov rax, cr0
mov cr3, rbx
mov r8, cr8
mov dr0, rcx
mov rdx, dr7
cpuid
rdtsc
syscall
int 0x80
int3

// ---- 6. Bit Operations & Tests ----
bt rax, 5
bts rbx, rcx
btr rdx, 8
bsf rsi, rdi
bsr r8, r9
test eax, eax
test r10, r11
cmp r12, r13
cmp byte [rax], 0

// ---- 7. SIMD: SSE / AVX / AVX2 (VEX Engine) ----
movaps xmm0, xmm1
movups [rax], xmm2
addps xmm3, xmm4
mulss xmm5, [rbx]

vmovaps ymm0, ymm1
vaddps ymm2, ymm3, ymm4
vmulps ymm5, ymm6, [rcx + 0x20]
vinsertf128 ymm8, ymm9, xmm10, 1
vextractf128 xmm11, ymm12, 0
vpermpd ymm13, ymm14, 0x1B
vfmadd132pd ymm15, ymm0, ymm1

// ---- 8. Complex SIB and REX Edge Cases ----
lea rax, [r12 + r13*4 + 0x1000]
mov r15b, [r14 + r15]
movzx eax, byte [r8]
movsx rbx, word [r9]
xchg rax, rbx
xchg r12, r13
cmpxchg [rcx], rdx
xadd [rsi], rdi

// ---- 9. String Operations ----
rep movsb
repne cmpsb
repe scasb
std
cld
