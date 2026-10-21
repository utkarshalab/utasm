// ============================================================================
// TEST: tests/asm/amd64/macros.s
// Suite: AMD64 Preprocessor
// Purpose: Macro definition and expansion within AMD64 context.
//   Tests: %macro/%endmacro, parameter passing, nested macros,
//          local labels within macros, %if/%endif within macros.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- Simple 0-param macro --------------------------------
%macro epilogue 0
    mov     rsp, rbp
    pop     rbp
    ret
%endmacro

%macro prologue 0
    push    rbp
    mov     rbp, rsp
%endmacro

my_func:
    prologue
    nop
    epilogue

// ---- 1-param macro (register save) ----------------------
%macro save_reg 1
    push    %1
%endmacro

%macro restore_reg 1
    pop     %1
%endmacro

caller:
    save_reg    rbx
    save_reg    r12
    save_reg    r13
    nop
    restore_reg r13
    restore_reg r12
    restore_reg rbx
    ret

// ---- 2-param macro (move with comment) ------------------
%macro load_imm 2
    mov     %1, %2
%endmacro

test_load:
    load_imm rax, 0
    load_imm rbx, 0xFF
    load_imm r12, 0x1234567890ABCDEF
    ret

// ---- 3-param macro (add two regs, result in third) -------
%macro reg_add 3
    mov     %1, %2
    add     %1, %3
%endmacro

test_reg_add:
    reg_add rax, rbx, rcx   // rax = rbx + rcx
    reg_add r8, r9, r10
    ret

// ---- Macro with local label (.loop) ---------------------
%macro repeat_nop 1
    mov     rcx, %1
%%loop:
    nop
    dec     rcx
    jnz     %%loop
%endmacro

test_repeat:
    repeat_nop 10
    repeat_nop 100
    ret

// ---- Macro with %if (conditional assembly) --------------
%macro assert_feature 2
    %if %2
        // Feature %1 is enabled
        nop
    %else
        // Feature %1 is DISABLED
        ud2
    %endif
%endmacro

%def HAS_AVX    1
%def HAS_AVX512 0

test_assert:
    assert_feature AVX, HAS_AVX
    assert_feature AVX512, HAS_AVX512
    ret

// ---- Variadic macro (%0 = param count) ------------------
%macro push_all 1-*
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro

test_variadic:
    push_all rax
    push_all rax, rbx
    push_all rax, rbx, rcx
    ret

// ---- Nested macro invocation ----------------------------
%macro outer 1
    prologue
    load_imm rax, %1
    epilogue
%endmacro

test_nested:
    outer 42
    outer 0xFF
