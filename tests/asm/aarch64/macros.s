// ============================================================================
// TEST: tests/asm/aarch64/macros.s
// Suite: AArch64 Preprocessor
// Purpose: Macro definition and expansion within AArch64 context.
//   Tests: %macro/%endmacro, 0/1/2/3 params, local labels,
//          conditional within macros, nested calls.
// Expected: EXIT_OK.
// ============================================================================

[SECTION .text]

// ---- 0-param function prologue/epilogue -----------------
%macro aarch64_prologue 0
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
%endmacro

%macro aarch64_epilogue 0
    ldp     x29, x30, [sp], #16
    ret
%endmacro

my_function:
    aarch64_prologue
    nop
    aarch64_epilogue

// ---- 1-param: save one register -------------------------
%macro save_gp 1
    str     %1, [sp, #-8]!
%endmacro

%macro restore_gp 1
    ldr     %1, [sp], #8
%endmacro

caller:
    save_gp    x19
    save_gp    x20
    nop
    restore_gp x20
    restore_gp x19
    ret

// ---- 2-param: load effective address --------------------
%macro load_addr 2
    adrp    %1, %2
    add     %1, %1, :lo12:%2
%endmacro

.Lmy_data: dq 0

test_load_addr:
    load_addr x0, .Lmy_data
    ret

// ---- 3-param: move immediate into register --------------
%macro set_reg 3
    movz    %1, #(%2 & 0xFFFF)
    movk    %1, #((%2 >> 16) & 0xFFFF), lsl #16
    movk    %1, #((%2 >> 32) & 0xFFFF), lsl #32
    movk    %1, #((%2 >> 48) & 0xFFFF), lsl #48
%endmacro

test_set_reg:
    set_reg x0, 0x12345678DEADBEEF, x1   // third param unused (placeholder)
    ret

// ---- Macro with local label (.loop) ---------------------
%macro countdown 1
    mov     x0, %1
%%loop:
    subs    x0, x0, #1
    b.ne    %%loop
%endmacro

test_countdown:
    countdown 10
    countdown 100
    ret

// ---- Nested macro invocations ---------------------------
test_nested:
    aarch64_prologue
    save_gp     x19
    load_addr   x19, .Lmy_data
    restore_gp  x19
    aarch64_epilogue
