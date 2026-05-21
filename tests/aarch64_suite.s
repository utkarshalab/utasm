// ============================================================================
// UtkarshaLab Test Suite
// Architecture: AArch64 (ARM64)
// Description: Comprehensive coverage for the utasm AArch64 encoder.
// ============================================================================

[SECTION .text]

// ---- 1. Arithmetic & Logic (64-bit and 32-bit) ----
add x0, x1, x2
add w3, w4, w5
sub x6, x7, #0xFF
sub w8, w9, #0xFF, lsl #12
and x10, x11, x12
orr w13, w14, #0xF0
eor x15, x16, x17
mul x18, x19, x20
madd x21, x22, x23, x24
sdiv w25, w26, w27

// ---- 2. Shifts & Bitfields ----
lsl x0, x1, #4
lsr w2, w3, #8
asr x4, x5, #16
ror w6, w7, #24
ubfx x8, x9, #0, #8
sbfx w10, w11, #4, #12
extr x12, x13, x14, #32

// ---- 3. Memory Access (Loads & Stores) ----
ldr x0, [x1]
ldr w2, [x3, #8]
ldr b4, [x5, #1]
ldr h6, [x7, #2]
str x8, [x9, x10]
str w11, [x12, x13, lsl #2]
str x14, [x15, #16]!         // Pre-index
ldr x16, [x17], #8          // Post-index

// ---- 4. Load/Store Pairs ----
ldp x0, x1, [x2]
stp w3, w4, [x5, #16]
ldp x6, x7, [x8, #32]!      // Pre-index
stp x9, x10, [x11], #16     // Post-index

// ---- 5. Control Flow ----
b _label_target
bl _label_target
br x0
blr x1
ret
ret x30
cbz x0, _label_target
cbnz w1, _label_target
tbz x2, #5, _label_target
tbnz w3, #12, _label_target

_label_target:
nop

// ---- 6. Floating Point (Scalar) ----
fadd d0, d1, d2
fsub s3, s4, s5
fmul d6, d7, d8
fdiv s9, s10, s11
fmov d12, x13
fmov x14, d15
scvtf d16, x17
fcvtzs x18, d19

// ---- 7. NEON (Advanced SIMD) ----
add v0.4s, v1.4s, v2.4s
sub v3.2d, v4.2d, v5.2d
mul v6.8h, v7.8h, v8.8h
and v9.16b, v10.16b, v11.16b
orr v12.16b, v13.16b, v14.16b
ext v15.16b, v16.16b, v17.16b, #4
ld1 {v0.16b}, [x0]
st1 {v1.4s, v2.4s}, [x1], x2

// ---- 8. SVE (Scalable Vector Extension) ----
add z0.s, z1.s, z2.s
and p0.b, p1/z, p2.b, p3.b
ld1w z4.s, p5/z, [x6, x7, lsl #2]
st1d z8.d, p9, [x10, #8, mul vl]

// ---- 9. System & Synchronization ----
svc #0
hvc #1
smc #2
msr nzcv, x0
mrs x1, nzcv
isb
dsb sy
dmb ish
ldaxr x2, [x3]
stlxr w4, x5, [x6]
