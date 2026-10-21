// ============================================================================
// TEST: tests/asm/aarch64/simd.s
// Suite: AArch64 NEON/AdvSIMD
// Purpose: NEON Advanced SIMD instruction coverage.
//   Covers: Vector arithmetic, logic, load/store, permute, compare,
//           convert — all element types (.8b, .16b, .4h, .8h, .2s, .4s, .2d).
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- NEON load / store ----------------------------------
ld1     {v0.16b}, [x0]
ld1     {v1.8h}, [x1]
ld1     {v2.4s}, [x2]
ld1     {v3.2d}, [x3]
ld1     {v4.16b, v5.16b}, [x4]
ld1     {v6.4s, v7.4s, v8.4s}, [x5]
ld1     {v0.16b}, [x0], x1
ld1     {v2.2d}, [x6], #16

ld2     {v0.4s, v1.4s}, [x0]
ld3     {v0.8h, v1.8h, v2.8h}, [x1]
ld4     {v0.4s, v1.4s, v2.4s, v3.4s}, [x2]

st1     {v0.16b}, [x0]
st1     {v1.4s}, [x1]
st1     {v0.2d, v1.2d}, [x2]
st2     {v0.4s, v1.4s}, [x0]
st3     {v0.8h, v1.8h, v2.8h}, [x1]
st4     {v0.4s, v1.4s, v2.4s, v3.4s}, [x2]

// ---- Integer NEON arithmetic ----------------------------
add     v0.16b, v1.16b, v2.16b
add     v3.8h,  v4.8h,  v5.8h
add     v6.4s,  v7.4s,  v8.4s
add     v9.2d,  v10.2d, v11.2d
sub     v0.16b, v1.16b, v2.16b
sub     v3.4s,  v4.4s,  v5.4s
mul     v0.8h,  v1.8h,  v2.8h
mul     v3.4s,  v4.4s,  v5.4s
mla     v0.4s,  v1.4s,  v2.4s       // multiply-accumulate
mls     v0.4s,  v1.4s,  v2.4s       // multiply-subtract

// Signed/unsigned saturating arithmetic
sqadd   v0.8h, v1.8h, v2.8h
sqsub   v3.4s, v4.4s, v5.4s
uqadd   v0.16b, v1.16b, v2.16b
uqsub   v3.8h,  v4.8h,  v5.8h

// Halving add/sub
shadd   v0.16b, v1.16b, v2.16b
uhadd   v3.8h,  v4.8h,  v5.8h
shsub   v6.4s,  v7.4s,  v8.4s

// ---- FP NEON arithmetic ---------------------------------
fadd    v0.4s, v1.4s, v2.4s
fadd    v3.2d, v4.2d, v5.2d
fsub    v6.4s, v7.4s, v8.4s
fmul    v0.4s, v1.4s, v2.4s
fmul    v3.2d, v4.2d, v5.2d
fdiv    v0.4s, v1.4s, v2.4s
fdiv    v3.2d, v4.2d, v5.2d
fmla    v0.4s, v1.4s, v2.4s
fmls    v3.2d, v4.2d, v5.2d
fmax    v0.4s, v1.4s, v2.4s
fmin    v3.4s, v4.4s, v5.4s
fsqrt   v0.4s, v1.4s
fabs    v2.2d, v3.2d
fneg    v4.4s, v5.4s

// ---- Logic NEON -----------------------------------------
and     v0.16b, v1.16b, v2.16b
orr     v3.16b, v4.16b, v5.16b
eor     v6.16b, v7.16b, v8.16b
bic     v9.16b, v10.16b, v11.16b
orn     v12.16b, v13.16b, v14.16b
not     v15.16b, v16.16b             // bitwise NOT (alias for MVN)

// ---- Compare NEON ---------------------------------------
cmeq    v0.4s, v1.4s, v2.4s
cmeq    v3.4s, v4.4s, #0             // compare with zero
cmgt    v5.4s, v6.4s, v7.4s
cmgt    v8.4s, v9.4s, #0
cmge    v10.4s, v11.4s, v12.4s
cmlt    v13.4s, v14.4s, #0           // less than zero
cmle    v15.4s, v16.4s, #0

// ---- Shift NEON -----------------------------------------
shl     v0.4s, v1.4s, #4
shl     v2.2d, v3.2d, #32
ushl    v4.4s, v5.4s, v6.4s
sshl    v7.4s, v8.4s, v9.4s
sshll   v0.4s, v1.4h, #8            // signed shift left long
ushll   v2.8h, v3.8b, #4            // unsigned shift left long

// ---- Permute / Shuffle ----------------------------------
zip1    v0.4s, v1.4s, v2.4s
zip2    v3.4s, v4.4s, v5.4s
uzp1    v6.4s, v7.4s, v8.4s
uzp2    v9.4s, v10.4s, v11.4s
trn1    v12.4s, v13.4s, v14.4s
trn2    v15.4s, v16.4s, v17.4s
ext     v0.16b, v1.16b, v2.16b, #4
rev64   v3.4s, v4.4s
rev32   v5.8h, v6.8h
rev16   v7.16b, v8.16b

// ---- DUP / INS / UMOV / SMOV ---------------------------
dup     v0.4s, w1                    // duplicate GP register to all lanes
dup     v2.4s, v3.s[0]              // duplicate lane to all lanes
ins     v0.s[1], w1                  // insert GP register into lane
ins     v2.s[1], v3.s[2]             // copy lane to lane
umov    w0, v1.s[0]                  // move lane to GP (zero-extend)
smov    x0, v1.s[0]                  // move lane to GP (sign-extend)

// ---- Widening/Narrowing operations ----------------------
saddl   v0.4s, v1.4h, v2.4h         // signed add long
uaddl   v3.8h, v4.8b, v5.8b
ssubl   v6.2d, v7.2s, v8.2s
saddw   v0.4s, v1.4s, v2.4h         // signed add wide
addhn   v0.4h, v1.4s, v2.4s         // add, narrow result
raddhn  v3.8b, v4.8h, v5.8h         // rounding add narrow

// ---- Convert NEON ---------------------------------------
scvtf   v0.4s, v1.4s                // int32 → single
ucvtf   v2.2d, v3.2d                // uint64 → double
fcvtzs  v4.4s, v5.4s                // single → int32
fcvtzu  v6.2d, v7.2d
fcvtn   v8.4h, v9.4s                // narrow: single → half
fcvtl   v10.4s, v11.4h              // widen: half → single

// ---- SVE (Scalable Vector Extension) --------------------
add     z0.s, z1.s, z2.s
add     z3.d, z4.d, z5.d
sub     z6.s, z7.s, z8.s
and     z9.d, z10.d, z11.d
