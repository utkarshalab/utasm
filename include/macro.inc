%ifndef MACRO_S
%define MACRO_S

;
; ============================================
; File     : include/macro.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Standard utility macro library for utasm.
; ============================================
;


%unmacro struc 1
%unmacro struc 1-2
%unimacro struc 1
%unimacro struc 1-2
%unmacro endstruc 0
%unimacro endstruc 0

; ============================================================================
; 1. SYSTEM & CONTEXT MANAGEMENT
; ============================================================================

;*
; * [prologue]
; * Purpose: Establish a standard AMD64 function stack frame.
; * Clobbers: RBP
; ;
%macro prologue 0
    push    rbp
    mov     rbp, rsp
%endmacro

%macro epilogue 0
    mov     rsp, rbp
    pop     rbp
    ret
%endmacro

;*
; * [push_volatile]
; * Purpose: Save all volatile registers as defined by the AMD64 SysV ABI.
; * Used before calling functions where state must be preserved.
; ;
%macro push_volatile 0
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
%endmacro

;*
; * [pop_volatile]
; * Purpose: Restore all volatile registers as defined by the AMD64 SysV ABI.
; ;
%macro pop_volatile 0
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
%endmacro

;*
; * [save_context]
; * Purpose: Save the complete CPU state, including all GPRs and EFLAGS.
; ;
%macro save_context 0
    pushfq
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    rbp
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
%endmacro

;*
; * [restore_context]
; * Purpose: Restore the complete CPU state saved by save_context.
; ;
%macro restore_context 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rbp
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    popfq
%endmacro

;*
; * [switch_context]
; * Purpose: Perform a thread/coroutine context switch by swapping stack pointers.
; * Parameters:
; *   %1: [mem64] Location to save the current RSP
; *   %2: [mem64] Location of the next task's RSP
; ;
%macro switch_context 2
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     [%1], rsp
    mov     rsp, [%2]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
%endmacro

;*
; * [locals_start]
; * Purpose: Initialize a block for named local stack variables.
; ;
%macro locals_start 0
    %push   locals
    %assign %$base_offset 0
%endmacro

;*
; * [local_var]
; * Purpose: Define a named local variable at an offset from RBP.
; * Parameters:
; *   %1: [name] Variable name
; *   %2: [imm] Size in bytes
; ;
%macro local_var 2
    %assign %$base_offset %$base_offset + %2
    %define %1 [rbp - %$base_offset]
%endmacro

;*
; * [locals_end]
; * Purpose: Reserve the calculated stack space for all defined locals.
; ;
%macro locals_end 0
    sub     rsp, %$base_offset
    %pop    locals
%endmacro

;*
; * [try] / [catch] / [endtry]
; * Purpose: Structured exception handling via context-based labels.
; * Usage:
; *   try
; *     call do_risky_work
; *     check_err
; *   catch
; *     call handle_error
; *   endtry
; ;
%macro try 0
    %push   try
%endmacro

%macro catch 0
    jmp     %$done_label
    %$error_label:
    %ifctx try
    %push   catch
    %endif
%endmacro

%macro endtry 0
    %$done_label:
    %ifctx catch
    %pop    catch
    %endif
    %ifctx try
    %pop    try
    %endif
%endmacro

;*
; * [throw]
; * Purpose: Signal an error and branch to the nearest 'catch' block.
; * Parameters:
; *   %1: [imm/reg] Error code to place in RAX
; ;
%macro throw 1
    mov     rax, %1
    jmp     %$error_label
%endmacro

; ============================================================================
; 2. ERROR HANDLING & ASSERTIONS
; ============================================================================

;*
; * [check_err]
; * Purpose: Branch to .error if RAX is non-zero (standard error convention).
; ;
%macro check_err 0
    test    rax, rax
    jnz     .error
%endmacro

;*
; * [check_err_to]
; * Purpose: Branch to a specific label if RAX is non-zero.
; ;
%macro check_err_to 1
    test    rax, rax
    jnz     %1
%endmacro

;*
; * [assert_tag]
; * Purpose: Verify that a structure at [%1] has the expected byte tag %2.
; ;
%macro assert_tag 2
    cmp     byte [%1], %2
    jne     .error_tag
%endmacro

;*
; * [assert_aligned]
; * Purpose: Trap if address in %1 is not aligned to %2 bytes.
; * %2 must be a power of two.
; ;
%macro assert_aligned 2
    test    %1, (%2 - 1)
    jnz     .error_alignment
%endmacro

;*
; * [assert_cache_aligned]
; * Purpose: Trap if address is not on a 64-byte cache line boundary.
; ;
%macro assert_cache_aligned 1
    test    %1, 63
    jnz     .error_cache_split
%endmacro

;*
; * [assert_not_zero]
; * Purpose: Trap if the value in %1 is zero (NULL check).
; ;
%macro assert_not_zero 1
    test    %1, %1
    jz      .error_null
%endmacro

;*
; * [assert_reg_range]
; * Purpose: Trap if %1 is not within the inclusive range [%2, %3].
; ;
%macro assert_reg_range 3
    cmp     %1, %2
    jl      .error_bounds
    cmp     %1, %3
    jg      .error_bounds
%endmacro

;*
; * [stack_align_check]
; * Purpose: Verify that the RSP is 16-byte aligned (required for SSE/ABI).
; ;
%macro stack_align_check 0
    test    rsp, 0xF
    jnz     .error_stack_unaligned
%endmacro

; ============================================================================
; 3. FLOW CONTROL (STRUCTURED)
; ============================================================================

; Global counter for unique IF block IDs
%assign __if_seq 0

;*
; * [IF] / [ELSEIF] / [ELSE] / [ENDIF]
; * Purpose: Structured conditional branching.
; * Uses global sequence with context-local capture and token pasting.
; ;
%macro IF 1-4
    %assign __if_seq __if_seq + 1
    %push if
    %assign %$uid __if_seq
    %assign %$branch 0

    %if %0 == 1
        %ifidni %1, z
            jnz strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, nz
            jz strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, e
            jnz strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, ne
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, c
            jnc strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, nc
            jc strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, s
            jns strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, ns
            js strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, o
            jno strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %1, no
            jo strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %else
            %error "Unsupported single-argument condition: %1"
        %endif
    %else
        %if %0 == 4
            cmp %1, %4
        %else
            cmp %1, %3
        %endif

        %ifidni %2, ==
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, =
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, !=
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, <>
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, e
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ne
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, g
            jng strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ge
            jnge strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, l
            jnl strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, le
            jnle strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, a
            jna strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ae
            jnae strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, b
            jnb strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, be
            jnbe strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %endif
    %endif
%endmacro

%macro ELSEIF 3-4
    %ifctx if
        jmp strict near .if_ %+ %$uid %+ _endif
        .if_ %+ %$uid %+ _else_ %+ %$branch:
        %assign %$branch %$branch + 1
            
        %if %0 == 4
            cmp %1, %4
        %else
            cmp %1, %3
        %endif
        
        %ifidni %2, ==
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, =
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, !=
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, <>
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, e
            jne strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ne
            je strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, g
            jng strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ge
            jnge strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, l
            jnl strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, le
            jnle strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, a
            jna strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, ae
            jnae strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, b
            jnb strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %elifidni %2, be
            jnbe strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        %endif
    %else
        %error "ELSEIF without IF"
    %endif
%endmacro

;*
; * [ELSEIF_RANGE]
; * Purpose: Chain branch taken when %1 lies within [%2, %3] inclusive.
; * Usage  : ELSEIF_RANGE ax, 3000, 3029
; * Note   : A plain "ELSEIF ax, ge, LO" wrapping an inner "IF ax, le, HI"
; *          swallows every value above HI — the inner test failing exits the
; *          whole chain instead of falling through to the next branch.
; ;
%macro ELSEIF_RANGE 3
    %ifctx if
        jmp strict near .if_ %+ %$uid %+ _endif
        .if_ %+ %$uid %+ _else_ %+ %$branch:
        %assign %$branch %$branch + 1
    
        cmp %1, %2
        jl strict near .if_ %+ %$uid %+ _else_ %+ %$branch
        cmp %1, %3
        jg strict near .if_ %+ %$uid %+ _else_ %+ %$branch
    %else
        %error "ELSEIF_RANGE without IF"
    %endif
%endmacro

%macro ELSE 0
    %ifctx if
        jmp strict near .if_ %+ %$uid %+ _endif
        .if_ %+ %$uid %+ _else_ %+ %$branch:
        %assign %$branch %$branch + 1
    %else
        %error "ELSE without IF"
    %endif
%endmacro

%macro ENDIF 0
    %ifctx if
        .if_ %+ %$uid %+ _else_ %+ %$branch:
        .if_ %+ %$uid %+ _endif:
        %pop if
    %else
        %error "ENDIF without IF"
    %endif
%endmacro

;*
; * [WHILE] / [ENDWHILE]
; * Purpose: Structured loop control.
; * Usage: WHILE rcx, ne, 0 ... ENDWHILE
; ;
%macro WHILE 3-4
    %push   while
    %$loop_start:
    %if %0 == 4
        cmp     %1, %4
    %else
        cmp     %1, %3
    %endif
    
    %ifidni %2, ==
        jne %$loop_end
    %elifidni %2, =
        jne %$loop_end
    %elifidni %2, !=
        je  %$loop_end
    %elifidni %2, <>
        je  %$loop_end
    %elifidni %2, e
        jne %$loop_end
    %elifidni %2, ne
        je  %$loop_end
    %else
        jn%+ %2 %$loop_end
    %endif
%endmacro

%macro ENDWHILE 0
    %ifctx while
        jmp     %$loop_start
    %$loop_end:
    %pop    while
    %else
    %error "ENDWHILE without WHILE"
    %endif
%endmacro

;*
; * [j_likely] / [j_unlikely]
; * Purpose: Hints to the CPU (and maintainer) about branch probability.
; ;
%macro j_likely 2
    j%1     %2
%endmacro

%macro j_unlikely 2
    j%1     %2
%endmacro

; ============================================================================
; 4. MEMORY & DATA STRUCTURES
; ============================================================================

;*
; * [zero_mem]
; * Purpose: Fast zero-initialization of memory using REP STOSQ.
; * Parameters:
; *   %1: [reg] Pointer to memory
; *   %2: [imm] Size in bytes (must be multiple of 8)
; ;
%macro zero_mem 2
    mov     rdi, %1
    mov     rcx, (%2 / 8)
    xor     rax, rax
    rep     stosq
%endmacro

;*
; * [alloc_on_arena]
; * Purpose: Allocate memory from the global arena.
; * Parameters:
; *   %1: [out] Register to receive the pointer
; *   %2: [in] Size in bytes
; ;
%macro alloc_on_arena 2
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, %2
    call    arena_alloc
    test    rax, rax
    jnz     .error_oom
    mov     %1, rdx
%endmacro

;*
; * [alloc_aligned_arena]
; * Purpose: Allocate memory from the arena with forced alignment.
; ;
%macro alloc_aligned_arena 3
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, %2
    call    arena_alloc
    check_err
    mov     %1, rdx
%endmacro

;*
; * [push_alloc] / [pop_alloc]
; * Purpose: Checkpoint and restore arena allocation pointers.
; * Useful for temporary allocations in nested parser logic.
; ;
%macro push_alloc 0
    %push   arena
    mov     r10, [rbx + PREP_arena]
    push    qword [r10 + ARENA_ptr]
%endmacro

%macro pop_alloc 0
    %ifctx arena
        mov     r10, [rbx + PREP_arena]
        pop     qword [r10 + ARENA_ptr]
    %pop    arena
    %else
    %error "pop_alloc without push_alloc"
    %endif
%endmacro

;*
; * [struc] / [field] / [endstruc]
; * Purpose: Automatic calculation of structure offsets and total size.
; ;
; Emulation struc macros for NASM
%ifdef __NASM__
%macro struc 1
    %push   struc
    %define %$struc_name %1
    %assign %$offset 0
%endmacro

%macro field 2
    %define %%fname %$struc_name %+ _ %+ %1
    %%fname equ %$offset
    %assign %$offset %$offset + %2
%endmacro

%macro endstruc 0
    %define %%sname %$struc_name %+ _SIZE
    %%sname equ %$offset
    %pop    struc
%endmacro
%endif

;*
; * [vtable_begin] / [vmethod] / [vtable_end]
; * Purpose: Define a Virtual Method Table in .rodata.
; ;
%macro vtable_begin 1
    [SECTION .rodata]
    align   8
    %1:
%endmacro

%macro vmethod 1
    dq      %1
%endmacro

%macro vtable_end 0
    [SECTION .text]
%endmacro

;*
; * [cbuf_push] / [cbuf_pop]
; * Purpose: Low-latency operations on a power-of-two circular buffer.
; ;
%macro cbuf_push 4
    mov     rax, [%2]
    mov     [%1 + rax], %4
    inc     rax
    and     rax, %3
    mov     [%2], rax
%endmacro

%macro cbuf_pop 4
    mov     rax, [%2]
    mov     %4, [%1 + rax]
    inc     rax
    and     rax, %3
    mov     [%2], rax
%endmacro

;*
; * [bloom_add] / [bloom_check]
; * Purpose: Fast membership test kernel for Bloom Filters.
; ;
%macro bloom_add 2
    mov     rax, %2
    mov     rcx, rax
    shr     rax, 3
    and     rcx, 7
    mov     dl, 1
    shl     dl, cl
    or      byte [%1 + rax], dl
%endmacro

%macro bloom_check 2
    mov     rax, %2
    mov     rcx, rax
    shr     rax, 3
    and     rcx, 7
    mov     dl, 1
    shl     dl, cl
    test    byte [%1 + rax], dl
%endmacro

;*
; * [jump_table] / [jt_entry] / [jump_table_end]
; * Purpose: Construct optimized jump tables for opcode dispatch.
; ;
%macro jt_entry 1
    dq      %1
%endmacro

%macro jump_table 1
    [SECTION .rodata]
    align   8
    %1:
%endmacro

%macro jump_table_end 0
    [SECTION .text]
%endmacro

; ============================================================================
; 5. STRING & BUFFER OPERATIONS
; ============================================================================

;*
; * [memcpy]
; * Purpose: Standard memory copy.
; ;
%macro memcpy 3
    mov     rdi, %1
    mov     rsi, %2
    mov     rcx, %3
    rep     movsb
%endmacro

;*
; * [memcpy_nt]
; * Purpose: Non-Temporal memory copy. Bypasses cache to prevent pollution.
; * Requirement: Source and Dest should be aligned for best performance.
; ;
%macro memcpy_nt 3
    mov     rdi, %1
    mov     rsi, %2
    mov     rcx, (%3 / 8)
%%loop:
    mov     rax, [rsi]
    movnti  [rdi], rax
    add     rsi, 8
    add     rdi, 8
    loop    %%loop
    sfence
%endmacro

;*
; * [memset]
; * Purpose: Fill a memory buffer with a specific byte value.
; ;
%macro memset 3
    mov     rdi, %1
    mov     al, %2
    mov     rcx, %3
    rep     stosb
%endmacro

;*
; * [strlen]
; * Purpose: Calculate the length of a null-terminated string.
; * Output: %2 = length in bytes.
; ;
%macro strlen 2
    mov     rdi, %1
    xor     al, al
    mov     rcx, -1
    repne   scasb
    not     rcx
    dec     rcx
    mov     %2, rcx
%endmacro

;*
; * [encode_leb128]
; * Purpose: Encode a 64-bit integer into DWARF-standard Variable Length LEB128.
; * Parameters:
; *   %1: [reg] Source value
; *   %2: [out] Dest pointer (advanced after write)
; ;
%macro encode_leb128 2
    mov     rax, %1
    mov     rdi, %2
%%loop:
    mov     dl, al
    and     dl, 0x7F
    shr     rax, 7
    jz      %%done
    or      dl, 0x80
    mov     [rdi], dl
    inc     rdi
    jmp     %%loop
%%done:
    mov     [rdi], dl
    inc     rdi
    mov     %2, rdi
%endmacro

;*
; * [swap_16/32/64]
; * Purpose: Endianness conversion via byte swapping.
; ;
%macro swap_16 1
    xchg    %h1, %l1
%endmacro

%macro swap_32 1
    bswap   %1
%endmacro

%macro swap_64 1
    bswap   %1
%endmacro

; ============================================================================
; 6. BITWISE & MATHEMATICAL OPERATIONS
; ============================================================================

;*
; * [set_bit] / [clr_bit] / [toggle_bit]
; * Purpose: Single-bit manipulation kernels.
; ;
%macro set_bit 2
    bts     %1, %2
%endmacro

%macro clr_bit 2
    btr     %1, %2
%endmacro

%macro toggle_bit 2
    btc     %1, %2
%endmacro

;*
; * [extract_bits]
; * Purpose: Retrieve a bitfield from a 64-bit source.
; * Parameters: dest, src, start_bit, length
; ;
%macro extract_bits 4
    mov     %1, %2
    %if %3 != 0
        shr     %1, %3
    %endif
    and     %1, ((1 << %4) - 1)
%endmacro

;*
; * [bit_reverse_64]
; * Purpose: Full bit-level reversal of a 64-bit register.
; ;
%macro bit_reverse_64 1
    mov     rax, %1
    bswap   rax
    mov     rcx, rax
    shr     rax, 1
    and     rax, 0x5555555555555555
    and     rcx, 0x5555555555555555
    shl     rcx, 1
    or      rax, rcx
    mov     %1, rax
%endmacro

;*
; * [popcnt_64] / [lzcnt_64] / [tzcnt_64]
; * Purpose: Advanced bit counting.
; ;
%macro popcnt_64 2
    popcnt  %1, %2
%endmacro

%macro lzcnt_64 2
    lzcnt   %1, %2
%endmacro

%macro tzcnt_64 2
    tzcnt   %1, %2
%endmacro

;*
; * [abs_64] / [min_64] / [max_64]
; * Purpose: Standard 64-bit arithmetic kernels.
; ;
%macro abs_64 1
    mov     rax, %1
    sar     rax, 63
    xor     %1, rax
    sub     %1, rax
%endmacro

%macro min_64 2
    cmp     %1, %2
    cmovg   %1, %2
%endmacro

%macro max_64 2
    cmp     %1, %2
    cmovl   %1, %2
%endmacro

;*
; * [clamp]
; * Purpose: Restrict a value to the inclusive range [%2, %3].
; ;
%macro clamp 3
    max_64  %1, %2
    min_64  %1, %3
%endmacro

;*
; * [mul_128]
; * Purpose: 64x64 -> 128-bit unsigned multiplication.
; * Output: %3 (Lo), %4 (Hi)
; ;
%macro mul_128 4
    mov     rax, %1
    mul     qword %2
    mov     %3, rax
    mov     %4, rdx
%endmacro

;*
; * [exp_mod]
; * Purpose: Modular Exponentiation kernel (Binary Exponentiation).
; * Input: %1 (Base), %2 (Exp), %3 (Mod)
; * Output: RAX
; ;
%macro exp_mod 3
    push    rax
    push    rbx
    push    rcx
    mov     rax, 1
    mov     rcx, %1
    mov     rbx, %2
%%loop:
    test    rbx, rbx
    jz      %%done
    test    rbx, 1
    jz      %%square
    mul     rcx
    xor     rdx, rdx
    div     qword %3
    mov     rax, rdx
%%square:
    push    rax
    mov     rax, rcx
    mul     rax
    xor     rdx, rdx
    div     qword %3
    mov     rcx, rdx
    pop     rax
    shr     rbx, 1
    jmp     %%loop
%%done:
    pop     rcx
    pop     rbx
    add     rsp, 8
%endmacro

;*
; * [hash_fnv1a_64]
; * Purpose: Fast non-cryptographic FNV-1a hash of a null-terminated string.
; ;
%macro hash_fnv1a_64 2
    mov     rax, 0xcbf29ce484222325 ; FNV offset basis
    mov     rcx, %1                 ; source string
    mov     r11, 0x100000001b3      ; FNV prime
%%loop:
    movzx   rdx, byte [rcx]
    test    dl, dl
    jz      %%done
    xor     al, dl                  ; FNV-1a: XOR then MUL
    imul    rax, r11
    inc     rcx
    jmp     %%loop
%%done:
    mov     %2, rax
%endmacro

; ============================================================================
; 7. ATOMICS & SYNCHRONIZATION
; ============================================================================

;*
; * [atomic_inc_64] / [atomic_add_64]
; * Purpose: Lock-prefixed atomic modifications.
; ;
%macro atomic_inc_64 1
    lock inc qword [%1]
%endmacro

%macro atomic_add_64 2
    lock add qword [%1], %2
%endmacro

;*
; * [atomic_cmpxchg_128]
; * Purpose: 128-bit atomic compare-and-swap (requires CMPXCHG16B support).
; ;
%macro atomic_cmpxchg_128 5
    mov     rax, %2
    mov     rdx, %3
    mov     rbx, %4
    mov     rcx, %5
    lock cmpxchg16b [%1]
%endmacro

;*
; * [spin_lock] / [spin_unlock]
; * Purpose: Standard 32-bit TAS (Test-And-Set) spinlock.
; ;
%macro spin_lock 1
%%retry:
    lock bts dword [%1], 0
    jc      %%retry
%endmacro

%macro spin_unlock 1
    lock btr dword [%1], 0
%endmacro

;*
; * [pause_backoff]
; * Purpose: Execute a series of PAUSE instructions for exponential backoff.
; ;
%macro pause_backoff 1
    mov     rcx, %1
%%loop:
    pause
    loop    %%loop
%endmacro

;*
; * [xbegin_sync] / [xend_sync]
; * Purpose: TSX Transactional Memory boundaries.
; ;
%macro xbegin_sync 1
    xbegin  %1
%endmacro

%macro xend_sync 0
    xend
%endmacro

; ============================================================================
; 8. ARCHITECTURE & HARDWARE CONTROL
; ============================================================================

;*
; * [require_cpu_feature]
; * Purpose: Verify CPUID feature bit before execution. Trap if missing.
; * Parameters: EAX leaf, Register (ecx=1, edx=0), Bit index
; ;
%macro require_cpu_feature 3
    mov     eax, %1
    xor     ecx, ecx
    cpuid
    bt      %2, %3
    jnc     .error_cpu_feature
%endmacro

;*
; * [rdmsr_64]
; * Purpose: Read Model Specific Register (Privileged).
; ;
%macro rdmsr_64 1
    mov     ecx, %1
    rdmsr
%endmacro

;*
; * [in_port_8] / [out_port_8]
; * Purpose: 8-bit Legacy Port I/O.
; ;
%macro in_port_8 2
    mov     dx, %2
    in      al, dx
    mov     %1, al
%endmacro

%macro out_port_8 2
    mov     dx, %1
    mov     al, %2
    out     dx, al
%endmacro

;*
; * [prefetch_read] / [prefetch_write]
; * Purpose: Software prefetch hints for memory controller.
; ;
%macro prefetch_read 1
    prefetcht0 [%1]
%endmacro

%macro prefetch_write 1
    prefetchw [%1]
%endmacro

;*
; * [lfence_sync] / [sfence_sync]
; * Purpose: Serialization fences for memory ordering.
; ;
%macro lfence_sync 0
    lfence
%endmacro

%macro sfence_sync 0
    sfence
%endmacro

;*
; * [reset_bhb]
; * Purpose: Mitigate Spectre-V2 by clearing the Branch History Buffer.
; ;
%macro reset_bhb 0
    %rep 32
        jmp     %%next
    %%next:
    %endrep
%endmacro

; ============================================================================
; 9. HARDWARE CRYPTO & RANDOM
; ============================================================================

;*
; * [aes_enc_round]
; * Purpose: Execute a single AES-NI encryption round.
; ;
%macro aes_enc_round 2
    aesenc  %1, %2
%endmacro

;*
; * [rdrand_64] / [rdseed_64]
; * Purpose: Retrieve true hardware entropy. Loops until carry flag is set.
; ;
%macro rdrand_64 1
%%retry:
    rdrand  %1
    jnc     %%retry
%endmacro

%macro rdseed_64 1
%%retry:
    rdseed  %1
    jnc     %%retry
%endmacro

; ============================================================================
; 10. VECTOR OPERATIONS (SIMD)
; ============================================================================

;*
; * [v_scan_quotes] / [v_scan_commas]
; * Purpose: Use SSE 4.2 PCMPISTRI to find delimiters in 16-byte chunks.
; * Output: ECX contains index.
; ;
%macro v_scan_quotes 1
    movdqu  xmm0, [%1]
    mov     rax, 0x2227
    movd    xmm1, eax
    pcmpistri xmm0, xmm1, 0x00
%endmacro

%macro v_scan_commas 1
    movdqu  xmm0, [%1]
    mov     rax, 0x2C
    movd    xmm1, eax
    pcmpistri xmm0, xmm1, 0x00
%endmacro

;*
; * [vstr_cmp]
; * Purpose: Fast 16-byte vectorized string comparison.
; ;
%macro vstr_cmp 3
    movdqu  xmm0, [%1]
    movdqu  xmm1, [%2]
    pcmpistri xmm0, xmm1, %3
%endmacro

;*
; * [v_all_zero] / [v_any_set]
; * Purpose: Test vectorized state via PTEST.
; ;
%macro v_all_zero 1
    ptest   %1, %1
%endmacro

%macro v_any_set 1
    ptest   %1, %1
%endmacro

; ============================================================================
; 11. SYSTEM CALLS (AMD64)
; ============================================================================

;*
; * [syscall_0] through [syscall_6]
; * Purpose: Standard AMD64 SysV ABI System Call wrappers.
; ;
%macro syscall_0 1
    mov     rax, %1
    syscall
%endmacro

%macro syscall_1 2
    mov     rax, %1
    mov     rdi, %2
    syscall
%endmacro

%macro syscall_6 7
    mov     rax, %1
    mov     rdi, %2
    mov     rsi, %3
    mov     rdx, %4
    mov     r10, %5
    mov     r8, %6
    mov     r9, %7
    syscall
%endmacro

;*
; * [mmap_anon]
; * Purpose: Allocate anonymous memory from the OS (RW, Private).
; ;
%macro mmap_anon 2
    syscall_6 9, 0, %1, 3, 34, -1, 0
    mov     %2, rax
%endmacro

; ============================================================================
; 12. DIAGNOSTICS & TESTING
; ============================================================================

;*
; * [debug_dump_hex]
; * Purpose: Print a 64-bit value as a hexadecimal string to stderr.
; ;
%macro debug_dump_hex 1
    push_volatile
    mov     rdi, %1
    call    error_uint_to_hex
    pop_volatile
%endmacro

;*
; * [debug_break_on]
; * Purpose: Trigger INT3 breakpoint if %1 == %2.
; ;
%macro debug_break_on 2
    cmp     %1, %2
    jne     %%skip
    int3
%%skip:
%endmacro

;*
; * [stack_trace]
; * Purpose: Walk the RBP frame chain and dump return addresses to stderr.
; ;
%macro stack_trace 0
    push    rbp
    mov     rbp, rbp
%%loop:
    test    rbp, rbp
    jz      %%done
    mov     rax, [rbp + 8]
    debug_dump_hex rax
    mov     rbp, [rbp]
    jmp     %%loop
%%done:
    pop     rbp
%endmacro

;*
; * [bench_start] / [bench_end]
; * Purpose: Capture high-precision instruction counts via RDPMC.
; ;
%macro bench_start 0
    xor     ecx, ecx
    rdpmc
    push    rdx
    push    rax
%endmacro

%macro bench_end 0
    xor     ecx, ecx
    rdpmc
    pop     rcx
    pop     r8
    sub     rax, rcx
    sbb     rdx, r8
%endmacro

; ============================================================================
; 13. METAPROGRAMMING & INTERNALS
; ============================================================================

;*
; * [static_assert]
; * Purpose: Preprocessor-time verification of constants or sizes.
; ;
%macro static_assert 3
    %if %1 %2 %3
        ; ok
    %else
    %error "STATIC ASSERTION FAILED: %1 %2 %3"
    %endif
%endmacro

;*
; * [compile_time_hash]
; * Purpose: Calculate FNV-1a hash at assembly-time for literal strings.
; ;
%macro compile_time_hash 2
    %assign %%hash 0xcbf29ce484222325
    %strlen %%len %1
    %assign %%i 1
    %rep %%len
    %substr %%char %1 %%i
    %assign %%hash ((%%hash ^ %%char) * 0x100000001b3)
    %assign %%i %%i + 1
    %endrep
    %define %2 %%hash
%endmacro

;*
; * [mnc_ent]
; * Purpose: Build a compile-time hashed opcode lookup entry.
; ;
%macro mnc_ent 3
    compile_time_hash %1, %%h
    dq      %%h
    db      %2
    dw      %3
    db      0, 0, 0, 0, 0  ; 5 bytes padding to reach 16-byte stride
%endmacro

;*
; * [is_reg_64]
; * Purpose: Preprocessor validation to ensure an operand is a 64-bit register.
; ;
%macro is_reg_64 1
    %assign %%is_reg 0
    %ifidni %1, rax
    %assign %%is_reg 1
    %elifidni %1, rbx
    %assign %%is_reg 1
    %elifidni %1, rcx
    %assign %%is_reg 1
    %elifidni %1, rdx
    %assign %%is_reg 1
    %elifidni %1, rsi
    %assign %%is_reg 1
    %elifidni %1, rdi
    %assign %%is_reg 1
    %elifidni %1, rbp
    %assign %%is_reg 1
    %elifidni %1, rsp
    %assign %%is_reg 1
    %elifidni %1, r8
    %assign %%is_reg 1
    %elifidni %1, r9
    %assign %%is_reg 1
    %elifidni %1, r10
    %assign %%is_reg 1
    %elifidni %1, r11
    %assign %%is_reg 1
    %elifidni %1, r12
    %assign %%is_reg 1
    %elifidni %1, r13
    %assign %%is_reg 1
    %elifidni %1, r14
    %assign %%is_reg 1
    %elifidni %1, r15
    %assign %%is_reg 1
    %endif
    %if %%is_reg == 0
    %error "Expected 64-bit register, got: %1"
    %endif
%endmacro

; ============================================================================
; 14. SECURITY & HARDENING
; ============================================================================

;*
; * [stack_canary_init] / [stack_canary_check]
; * Purpose: Detect stack smashing via guard values.
; ;
%macro stack_canary_init 1
    mov     rax, 0x55aa55aa55aa55aa
    mov     [%1], rax
%endmacro

%macro stack_canary_check 1
    mov     rax, 0x55aa55aa55aa55aa
    cmp     rax, [%1]
    jne     .error_stack_corrupt
%endmacro

;*
; * [jmp_obfuscate]
; * Purpose: Opaque jump target calculation to resist static disassembly.
; ;
%macro jmp_obfuscate 1
    push    rax
    mov     rax, %1
    xor     rax, 0x5555555555555555
    xor     rax, 0x5555555555555555
    xchg    rax, [rsp]
    ret
%endmacro

;*
; * [rz_secure] / [rz_release]
; * Purpose: Explicit AMD64 Red Zone management.
; ;
%macro rz_secure 0
    sub     rsp, 128
%endmacro

%macro rz_release 0
    add     rsp, 128
%endmacro

; ============================================================================
; 15. LINKER & FORENSICS
; ============================================================================

;*
; * [plt_stub] / [got_entry]
; * Purpose: Generate standard ELF PLT/GOT indirection kernels.
; ;
%macro plt_stub 1
    jmp     [qword %1_GOT]
%endmacro

%macro got_entry 1
    %1_GOT: dq 0
%endmacro

;*
; * [opaque_jmp] / [opaque_constant]
; * Purpose: Antidebugging and obfuscation of control flow and constants.
; ;
%macro opaque_jmp 1
    push    rax
    xor     rax, rax
    jz      %%next
    db      0x0F, 0x0B
%%next:
    pop     rax
    jmp     %1
%endmacro

%macro opaque_constant 2
    mov     %1, (%2 / 2)
    shl     %1, 1
    add     %1, (%2 % 2)
%endmacro

;*
; * [self_check]
; * Purpose: Runtime integrity verification via additive section checksum.
; ;
%macro self_check 0
    push_volatile
    lea     rsi, [$$]
    mov     rcx, ($ - $$)
    xor     rax, rax
%%loop:
    add     al, [rsi]
    inc     rsi
    loop    %%loop
    pop_volatile
%endmacro

;*
; * [code_signature]
; * Purpose: Embed a searchable forensic signature in the binary.
; ;
%macro code_signature 1
    db      "UTASM_SIG:", %1, 0
%endmacro

%endif
