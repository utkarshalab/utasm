// ============================================================================
// TEST: tests/asm/amd64/call.s
// Suite: AMD64 Core
// Purpose: CALL instruction — near/indirect, tail-call idioms,
//          calling conventions (System V AMD64 ABI, Microsoft x64 ABI).
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Direct near CALL (relative) -----------------------
    call    .L1
    call    .L2

// ---- Indirect CALL through register --------------------
    mov     rax, 0
    call    rax
    call    rbx
    call    rcx
    call    rdx
    call    rsi
    call    rdi
    call    r8
    call    r9
    call    r10
    call    r11
    call    r12
    call    r13
    call    r14
    call    r15

// ---- Indirect CALL through memory ----------------------
    call    qword [rax]
    call    qword [rbx + 8]
    call    qword [rcx + rdx*8]
    call    qword [r12 + r13*4 + 16]
    call    qword [rsp + 8]
    call    qword [rbp - 8]

// ---- Tail-call idiom (JMP instead of CALL) -------------
    jmp     .L1
    jmp     rax
    jmp     qword [rbx]

// ---- System V AMD64 ABI prologue/epilogue idioms --------
.L1:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8          // align to 16 bytes after 5 pushes
    // ... function body ...
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

// ---- Microsoft x64 ABI prologue -------------------------
.L2:
    push    rbp
    push    rdi
    push    rsi
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 0x28       // 5 register args shadow space
    // ... function body ...
    add     rsp, 0x28
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rsi
    pop     rdi
    pop     rbp
    ret

// ---- Nested call (function calling another) -------------
.nested_caller:
    push    rbx
    sub     rsp, 8
    call    .L1
    call    .L2
    add     rsp, 8
    pop     rbx
    ret
