// ============================================================================
// TEST: tests/asm/riscv64/simd.s
// Suite: RISC-V 64 Core
// Purpose: Vector extension (V) instruction coverage.
//   Covers: Vector loads/stores, vector arithmetic, vector logic,
//           vector-scalar operations, vector reductions.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Vector Config (vsetvli) ---------------------------
vsetvli t0, a0, e8, m1, ta, ma
vsetvli t1, a1, e16, m2, tu, mu
vsetvli t2, a2, e32, m4, ta, mu
vsetvli t3, a3, e64, m8, tu, ma

// ---- Vector Loads / Stores -----------------------------
vle8.v v0, (a0)
vle16.v v1, (a1)
vle32.v v2, (a2)
vle64.v v3, (a3)

vse8.v v0, (a0)
vse16.v v1, (a1)
vse32.v v2, (a2)
vse64.v v3, (a3)

vlm.v v0, (a0)              // vector load mask
vsm.v v0, (a0)              // vector store mask

// ---- Vector Arithmetic (VV, VX, VI) --------------------
vadd.vv v0, v1, v2
vadd.vx v3, v4, a0
vadd.vi v5, v6, 5

vsub.vv v7, v8, v9
vsub.vx v10, v11, a1

vmul.vv v12, v13, v14
vmul.vx v15, v16, a2

vdiv.vv v17, v18, v19
vrem.vv v20, v21, v22

// Narrowing / Widening
vwadd.vv v0, v1, v2
vwadd.vx v3, v4, a0
vnsrl.wv v5, v6, v7

// ---- Vector Logic --------------------------------------
vand.vv v0, v1, v2
vor.vv v3, v4, v5
vxor.vv v6, v7, v8
vnot.v v9, v10

// ---- Vector FP -----------------------------------------
vfadd.vv v0, v1, v2
vfadd.vf v3, v4, fa0
vfsub.vv v5, v6, v7
vfmul.vv v8, v9, v10
vfdiv.vv v11, v12, v13

// ---- Vector Permute ------------------------------------
vmv.v.v v0, v1
vmv.v.x v2, a0
vmv.v.i v3, 0

vrgather.vv v0, v1, v2
vslidedown.vi v3, v4, 1
vslideup.vi v5, v6, 2

// ---- Vector Reduction ----------------------------------
vredsum.vs v0, v1, v2
vredmax.vs v3, v4, v5
vfredsum.vs v0, v1, v2
