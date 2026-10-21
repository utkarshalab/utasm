// ============================================================================
// TEST: tests/asm/amd64/shift.s
// Suite: AMD64 Core
// Purpose: Shift and rotate instruction coverage.
//   Covers: SHL, SHR, SAR, ROL, ROR, RCL, RCR — all operand sizes,
//           both immediate (imm8) and CL register shift forms.
//           Also covers SHLD and SHRD double-precision shifts.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- SHL (Shift Left Logical) --------------------------
shl     rax, 1              // by 1 (special encoding)
shl     rax, cl             // by CL
shl     rax, 4              // by imm8
shl     r8,  63             // max shift
shl     eax, 1
shl     eax, cl
shl     eax, 31
shl     ax,  1
shl     al,  1
shl     byte  [rbx], 1
shl     word  [rcx + 2], cl
shl     dword [rdx + 4], 8
shl     qword [r12 + r13*4], cl

// ---- SHR (Shift Right Logical) -------------------------
shr     rax, 1
shr     rax, cl
shr     rax, 4
shr     r15, 63
shr     eax, 1
shr     ax,  cl
shr     bl,  4
shr     qword [rax], 1
shr     dword [rbx + 8], cl

// ---- SAR (Shift Arithmetic Right) ----------------------
sar     rax, 1
sar     rax, cl
sar     rax, 4
sar     r8,  63
sar     eax, 1
sar     eax, cl
sar     ax,  1
sar     al,  4
sar     qword [rcx], cl
sar     byte  [rdx], 1

// ---- ROL (Rotate Left) ---------------------------------
rol     rax, 1
rol     rax, cl
rol     rax, 4
rol     r12, 8
rol     eax, 1
rol     ax,  cl
rol     al,  4
rol     qword [rbx], 1
rol     word  [rcx + 2], cl

// ---- ROR (Rotate Right) --------------------------------
ror     rax, 1
ror     rax, cl
ror     rax, 4
ror     r9,  8
ror     eax, 1
ror     ax,  cl
ror     al,  4
ror     dword [rdx], 1
ror     byte  [r8], cl

// ---- RCL (Rotate Left through Carry) -------------------
rcl     rax, 1
rcl     rax, cl
rcl     eax, 1
rcl     ax,  cl
rcl     byte [rbx], 1

// ---- RCR (Rotate Right through Carry) ------------------
rcr     rax, 1
rcr     rax, cl
rcr     eax, 1
rcr     byte [rcx + 4], cl

// ---- SHLD / SHRD (Double-Precision Shifts) -------------
shld    rax, rbx, 1
shld    rax, rbx, cl
shld    rcx, rdx, 32
shld    eax, ebx, 4
shld    word [r8], r9w, 8
shrd    rax, rbx, 1
shrd    rax, rbx, cl
shrd    rcx, rdx, 16
shrd    eax, ecx, cl
shrd    dword [rdx], ecx, 4
