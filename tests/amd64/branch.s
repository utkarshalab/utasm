// ============================================================================
// TEST: tests/amd64/branch.s
// Suite: AMD64 Core
// Purpose: All branch/jump/call forms for AMD64.
//   Covers: JMP (near, far, indirect), Jcc (all 16 conditions),
//           CALL (near, indirect), RET, LOOP, LOOPZ, LOOPNZ.
// Expected: EXIT_OK, all encodings accepted.
// ============================================================================

[SECTION .text]

global _start
_start:
    jmp     .near               // near relative jump

// ---- JMP forms -----------------------------------------
.near:
    jmp     .L1                 // short (imm8)
    jmp     .L2                 // near (imm32)
    jmp     rax                 // indirect through register
    jmp     [rax]               // indirect through memory
    jmp     [rbx + 8]           // indirect + disp
    jmp     qword [r12 + r13*4] // indirect + SIB

.L1:
    nop

.L2:
    nop

// ---- CALL forms ----------------------------------------
    call    .near               // near relative call
    call    rax                 // indirect through register
    call    [rbx]               // indirect through memory
    call    [rcx + 0x10]        // indirect + disp
    call    qword [rdx + rsi*8] // indirect + SIB

// ---- RET forms -----------------------------------------
    ret                         // near return
    ret     16                  // near return + imm16 stack pop

// ---- Jcc — all 16 conditions ---------------------------
    je      .L1
    jz      .L1                 // alias for JE
    jne     .L1
    jnz     .L1                 // alias for JNE
    jl      .L1
    jnge    .L1                 // alias for JL
    jge     .L1
    jnl     .L1                 // alias for JGE
    jle     .L1
    jng     .L1                 // alias for JLE
    jg      .L1
    jnle    .L1                 // alias for JG
    jb      .L1
    jnae    .L1                 // alias for JB
    jae     .L1
    jnb     .L1                 // alias for JAE
    jbe     .L1
    jna     .L1                 // alias for JBE
    ja      .L1
    jnbe    .L1                 // alias for JA
    js      .L1
    jns     .L1
    jo      .L1
    jno     .L1
    jp      .L1
    jpe     .L1                 // alias for JP
    jnp     .L1
    jpo     .L1                 // alias for JNP
    // jcxz is not encodable in 64-bit mode (jecxz/jrcxz are)
    jecxz   .L1
    jrcxz   .L1

// ---- LOOP forms ----------------------------------------
    loop    .L1
    loopz   .L1
    loope   .L1                 // alias for LOOPZ
    loopnz  .L1
    loopne  .L1                 // alias for LOOPNZ

// ---- SETcc — conditional byte sets ---------------------
    sete    al
    setne   bl
    setl    cl
    setge   dl
    setle   r8b
    setg    r9b
    setb    r10b
    setae   r11b
    setbe   r12b
    seta    r13b
    sets    al
    setns   bl
    seto    cl
    setno   dl
    setp    r8b
    setnp   r9b
    sete    byte [rax]
    setne   byte [rbx + 4]
