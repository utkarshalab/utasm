// ============================================================================
// TEST: tests/asm/riscv64/float.s
// Suite: RISC-V 64 Core
// Purpose: Floating-point instruction coverage (F and D extensions).
//   Covers: FLW, FSW, FLD, FSD, FADD, FSUB, FMUL, FDIV, FSQRT,
//           FMADD, FMSUB, FNMSUB, FNMADD, FMIN, FMAX, FCVT, FMV, FEQ, FLT, FLE.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Single-Precision (F extension) --------------------
flw     fa0, 0(a1)
flw     fa1, 4(sp)
fsw     fa0, 0(a1)
fsw     fa1, 4(sp)

fadd.s  fa0, fa1, fa2
fsub.s  fa3, fa4, fa5
fmul.s  fa6, fa7, ft0
fdiv.s  ft1, ft2, ft3
fsqrt.s ft4, ft5
fsgnj.s ft6, ft7, ft8       // sign injection
fsgnjn.s ft9, ft10, ft11
fsgnjx.s ft12, ft13, ft14

fmin.s  fa0, fa1, fa2
fmax.s  fa3, fa4, fa5

fcvt.w.s a0, fa0            // convert SP to 32-bit int
fcvt.wu.s a1, fa1           // convert SP to 32-bit uint
fcvt.s.w fa2, a2            // convert 32-bit int to SP
fcvt.s.wu fa3, a3           // convert 32-bit uint to SP

fmv.x.w a0, fa0             // move SP bits to GP (no convert)
fmv.w.x fa1, a1             // move GP bits to SP

feq.s   a0, fa0, fa1        // FP equal
flt.s   a1, fa2, fa3        // FP less than
fle.s   a2, fa4, fa5        // FP less or equal

fclass.s a0, fa0            // classify FP value

// ---- Double-Precision (D extension) --------------------
fld     fa0, 0(a1)
fld     fa1, 8(sp)
fsd     fa0, 0(a1)
fsd     fa1, 8(sp)

fadd.d  fa0, fa1, fa2
fsub.d  fa3, fa4, fa5
fmul.d  fa6, fa7, ft0
fdiv.d  ft1, ft2, ft3
fsqrt.d ft4, ft5

fcvt.s.d fa0, fa1           // double → single
fcvt.d.s fa2, fa3           // single → double

fcvt.w.d a0, fa0
fcvt.wu.d a1, fa1
fcvt.d.w fa2, a2
fcvt.d.wu fa3, a3

fcvt.l.d a0, fa0            // convert double to 64-bit int (RV64)
fcvt.lu.d a1, fa1           // convert double to 64-bit uint (RV64)
fcvt.d.l fa2, a2            // convert 64-bit int to double (RV64)
fcvt.d.lu fa3, a3           // convert 64-bit uint to double (RV64)

fmv.x.d a0, fa0             // move double bits to GP (RV64)
fmv.d.x fa1, a1             // move GP bits to double (RV64)

feq.d   a0, fa0, fa1
flt.d   a1, fa2, fa3
fle.d   a2, fa4, fa5

fclass.d a0, fa0

// ---- Fused Multiply-Add --------------------------------
fmadd.s  fa0, fa1, fa2, fa3
fmsub.s  fa4, fa5, fa6, fa7
fnmsub.s ft0, ft1, ft2, ft3
fnmadd.s ft4, ft5, ft6, ft7

fmadd.d  fa0, fa1, fa2, fa3
fmsub.d  fa4, fa5, fa6, fa7
fnmsub.d ft0, ft1, ft2, ft3
fnmadd.d ft4, ft5, ft6, ft7
