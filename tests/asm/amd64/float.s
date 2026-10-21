// ============================================================================
// TEST: tests/asm/amd64/float.s
// Suite: AMD64 Core
// Purpose: x87 FPU instruction coverage.
//   Covers: FLD/FST/FSTP, FADD/FSUB/FMUL/FDIV, FCOM/FUCOM,
//           FXCH, FINIT, FSAVE/FRSTOR, F2XM1, FSCALE, FPTAN, etc.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- x87 Load/Store -------------------------------------
fld     dword [rax]         // load single
fld     qword [rbx]         // load double
fld     tbyte [rcx]         // load extended (80-bit)
fld     st0                 // push ST(0) copy
fld     st1

fst     dword [rdx]         // store single
fst     qword [r8]
fst     st1                 // store to ST(1)
fstp    dword [r9]          // store and pop
fstp    qword [r10 + 8]
fstp    tbyte [r11]
fstp    st0                 // pop

// ---- x87 Arithmetic -------------------------------------
fadd    dword [rax]
fadd    qword [rbx]
fadd    st0, st1
fadd    st1, st0
faddp   st1, st0            // add and pop
faddp

fsub    dword [rcx]
fsub    st0, st2
fsubp   st1, st0
fsubr   dword [rdx]
fsubrp  st2, st0

fmul    dword [rax]
fmul    st0, st3
fmulp   st1, st0
fmulp

fdiv    qword [rbx]
fdiv    st0, st4
fdivp   st2, st0
fdivr   dword [rcx]
fdivrp  st1, st0

// ---- x87 Constants -------------------------------------
fldz                        // load 0.0
fld1                        // load 1.0
fldpi                       // load π
fldl2t                      // load log2(10)
fldl2e                      // load log2(e)
fldlg2                      // load log10(2)
fldln2                      // load ln(2)

// ---- x87 Comparison ------------------------------------
fcom    dword [rax]
fcom    qword [rbx]
fcom    st1
fcomp   dword [rcx]
fcomp   st2
fcompp
fucom   st1
fucomp  st2
fucompp

// ---- x87 Transcendental --------------------------------
f2xm1               // ST(0) = 2^ST(0) - 1
fyl2x               // ST(1) = ST(1) * log2(ST(0)), pop
fyl2xp1             // ST(1) = ST(1) * log2(ST(0)+1), pop
fscale              // ST(0) = ST(0) * 2^trunc(ST(1))
fptan               // ST(0) = tan(ST(0)), push 1.0
fpatan              // ST(1) = atan(ST(1)/ST(0)), pop
fsqrt               // ST(0) = sqrt(ST(0))
fabs                // ST(0) = |ST(0)|
fchs                // ST(0) = -ST(0)
frndint             // ST(0) = round(ST(0))
fxtract             // split into mantissa/exponent

// ---- x87 Exchange / Stack control ----------------------
fxch                // swap ST(0) and ST(1)
fxch    st2
fxch    st7
ffree   st0         // mark ST(0) as free
fdecstp             // decrement stack pointer
fincstp             // increment stack pointer

// ---- x87 Control ----------------------------------------
finit               // initialize FPU (no wait)
fninit
fwait               // wait for FPU
fnop                // FPU no-op
fclex               // clear exceptions
fnclex
fstcw   [rax]       // store control word
fnstcw  [rbx]
fldcw   [rcx]       // load control word
fstsw   [rdx]       // store status word
fnstsw  [r8]
fstsw   ax          // store status to AX

// ---- FXSAVE / FXRSTOR (save/restore x87+SSE state) -----
fxsave  [rax]
fxrstor [rbx]

// ---- Scalar SSE fp (modern replacement) ----------------
cvtsi2ss xmm0, rax
cvtsi2sd xmm1, rbx
cvtss2si rax, xmm2
cvtsd2si rbx, xmm3
