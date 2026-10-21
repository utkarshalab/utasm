// ============================================================================
// TEST: tests/asm/amd64/simd.s
// Suite: AMD64 SIMD
// Purpose: SSE/SSE2/SSE4, AVX (VEX-128), AVX2 (VEX-256), FMA coverage.
//   Exercises XMM (128-bit) and YMM (256-bit) registers.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- SSE: Packed/Scalar Float (XMM, 128-bit) -----------

// MOVAPS / MOVUPS (aligned / unaligned packed single)
movaps  xmm0, xmm1
movaps  xmm2, [rax]
movaps  [rbx], xmm3
movups  xmm4, xmm5
movups  xmm6, [rcx + 16]
movups  [rdx + 32], xmm7

// MOVAPD / MOVUPD (double)
movapd  xmm8,  xmm9
movapd  xmm10, [r8]
movupd  xmm11, [r9 + 16]

// Arithmetic: single-precision packed
addps   xmm0,  xmm1
subps   xmm2,  xmm3
mulps   xmm4,  xmm5
divps   xmm6,  xmm7
sqrtps  xmm8,  xmm9
maxps   xmm10, xmm11
minps   xmm12, xmm13

// Arithmetic: double-precision packed
addpd   xmm0, xmm1
subpd   xmm2, xmm3
mulpd   xmm4, xmm5
divpd   xmm6, xmm7

// Arithmetic: scalar single
addss   xmm0, xmm1
subss   xmm2, [rax]
mulss   xmm3, xmm4
divss   xmm5, [rbx + 4]
sqrtss  xmm6, xmm7

// Arithmetic: scalar double
addsd   xmm0, xmm1
subsd   xmm2, [rcx + 8]
mulsd   xmm3, xmm4
divsd   xmm5, [rdx]
sqrtsd  xmm6, xmm7

// Compare: CMPPS / CMPPD
cmpps   xmm0, xmm1, 0      // EQ
cmpps   xmm2, xmm3, 4      // NEQ
cmppd   xmm4, xmm5, 1      // LT
cmppd   xmm6, xmm7, 2      // LE

// Compare: UCOMISS / UCOMISD
ucomiss xmm0, xmm1
ucomiss xmm2, [rax]
ucomisd xmm3, xmm4
ucomisd xmm5, [rbx + 8]

// Convert
cvtss2sd  xmm0, xmm1
cvtsd2ss  xmm2, xmm3
cvtsi2ss  xmm4, rax
cvtsi2sd  xmm5, rbx
cvttss2si rax, xmm6
cvttsd2si rbx, xmm7

// Shuffle / Pack / Unpack
shufps  xmm0, xmm1, 0xE4   // identity shuffle
shufpd  xmm2, xmm3, 0
unpcklps xmm4, xmm5
unpckhps xmm6, xmm7
unpcklpd xmm8, xmm9
unpckhpd xmm10, xmm11

// Logic (integer-domain)
pand    xmm0, xmm1
por     xmm2, xmm3
pxor    xmm4, xmm5
pandn   xmm6, xmm7

// Integer SSE2
paddb   xmm0, xmm1
paddw   xmm2, xmm3
paddd   xmm4, xmm5
paddq   xmm6, xmm7
psubb   xmm8, xmm9
psubw   xmm10, xmm11
psubd   xmm12, xmm13
psubq   xmm14, xmm15

pcmpeqb xmm0, xmm1
pcmpeqw xmm2, xmm3
pcmpeqd xmm4, xmm5
pcmpgtb xmm6, xmm7
pcmpgtw xmm8, xmm9

pmulhw  xmm0, xmm1
pmullw  xmm2, xmm3
pmulld  xmm4, xmm5         // SSE4.1

// ---- AVX (VEX-128, XMM) --------------------------------
vmovaps xmm0, xmm1
vmovaps xmm2, [rax]
vmovaps [rbx], xmm3

vaddps  xmm0, xmm1, xmm2
vsubps  xmm3, xmm4, xmm5
vmulps  xmm6, xmm7, xmm8
vdivps  xmm9, xmm10, xmm11

vaddsd  xmm0, xmm1, xmm2
vmulss  xmm3, xmm4, [rcx]

// ---- AVX2 (VEX-256, YMM) --------------------------------
vmovaps ymm0, ymm1
vmovaps ymm2, [rax]
vmovaps [rbx + 32], ymm3

vaddps  ymm0, ymm1, ymm2
vsubps  ymm3, ymm4, ymm5
vmulps  ymm6, ymm7, ymm8
vdivps  ymm9, ymm10, ymm11

vaddpd  ymm0, ymm1, ymm2
vsubpd  ymm3, ymm4, ymm5
vmulpd  ymm6, ymm7, [rcx + 64]

// AVX2 integer
vpand   ymm0, ymm1, ymm2
vpor    ymm3, ymm4, ymm5
vpxor   ymm6, ymm7, ymm8
vpaddd  ymm9, ymm10, ymm11
vpsubd  ymm12, ymm13, ymm14

// Gather
vgatherdpd xmm0, [rbx + xmm1*4], xmm2

// Broadcast / Permute
vbroadcastss ymm0, xmm1
vbroadcastsd ymm2, xmm3
vpermpd  ymm4, ymm5, 0x1B
vpermilps ymm6, ymm7, 0xE4

// Blend
vblendps ymm0, ymm1, ymm2, 0x0F
vblendpd ymm3, ymm4, ymm5, 0x03

// Insert / Extract
vinsertf128 ymm0, ymm1, xmm2, 0
vinsertf128 ymm3, ymm4, xmm5, 1
vextractf128 xmm0, ymm1, 0
vextractf128 xmm2, ymm3, 1

// ---- FMA (Fused Multiply-Add) ---------------------------
vfmadd132pd  ymm0, ymm1, ymm2
vfmadd213pd  ymm3, ymm4, ymm5
vfmadd231pd  ymm6, ymm7, ymm8
vfmadd132ps  xmm9, xmm10, xmm11
vfmsub132pd  ymm0, ymm1, ymm2
vfnmadd132pd ymm3, ymm4, ymm5
