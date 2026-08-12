;
; ============================================================================
; File        : profiler/fmt.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Number formatting utilities for profiler report output.
;
; Provides comma-separated cycle formatting, percentage computation,
; and right-aligned numeric printing. These are internal helpers called
; by table.s and report.s.
;
; See docs/profiler_architecture.md §9.2 for formatting specifications.
; ============================================================================
;

bits 64

%include "include/constant.inc"

DEFAULT REL

extern print_str
extern print_num
extern prof_space
extern prof_dot
extern prof_pct_sign
extern prof_pct_zero

[SECTION .text]

; ---- profiler_print_padded -----------------------------------------------
;
; profiler_print_padded
; Prints a 64-bit unsigned integer right-aligned in a fixed-width field.
;
; Counts digits in the value, prints (width - digits) leading spaces,
; then prints the number itself.
;
; Input    : rdi = file descriptor (STDERR_FILENO)
;            rsi = value to print
;            rdx = field width (e.g., 14 for cycles, 9 for counts)
; Output   : (none)
; Clobbers : rax, rcx, rdx, r8, r9
;
global profiler_print_padded
profiler_print_padded:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi                ; rbx = fd
    mov     r12, rsi                ; r12 = value
    mov     r13, rdx                ; r13 = field width

    ; count digits in value
    mov     rax, r12
    xor     rcx, rcx
    mov     r8, 10

    ; handle zero specially (1 digit)
    test    rax, rax
    jnz     .count_loop
    mov     rcx, 1
    jmp     .count_done

.count_loop:
    inc     rcx
    xor     rdx, rdx
    div     r8                      ; rax = quotient
    test    rax, rax
    jnz     .count_loop

.count_done:
    ; print (width - digits) spaces
    mov     r8, r13
    sub     r8, rcx
    jle     .spaces_done

.space_loop:
    push    r8
    mov     rdi, rbx
    lea     rsi, [rel prof_space]
    call    print_str
    pop     r8
    dec     r8
    jnz     .space_loop

.spaces_done:
    ; print the number
    mov     rdi, rbx
    mov     rsi, r12
    call    print_num

    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- profiler_print_percent ----------------------------------------------
;
; profiler_print_percent
; Computes and prints a percentage as "  NN.N%" right-aligned.
;
; Uses fixed-point arithmetic: (part × 1000) / total → tenths of a percent.
; E.g., 423 → "42.3%"
;
; Input    : rdi = file descriptor
;            rsi = part (numerator, e.g., phase cycles)
;            rdx = total (denominator, e.g., total pipeline cycles)
; Output   : (none)
; Clobbers : rax, rcx, rdx, r8, r9
;
global profiler_print_percent
profiler_print_percent:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; rbx = fd

    ; handle division by zero
    test    rdx, rdx
    jz      .pct_zero

    ; save total before mul clobbers rdx
    mov     r12, rdx                ; r12 = total

    ; fixed-point: (part × 1000) / total
    mov     rax, rsi                ; rax = part
    mov     rcx, 1000
    mul     rcx                     ; rdx:rax = part × 1000
    ; for profiler values (<2^53 cycles), high part rdx is 0
    div     r12                     ; rax = tenths of percent

    ; split: integer% = tenths / 10, fraction = tenths % 10
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx                     ; rax = integer%, rdx = fraction digit
    mov     r13, rax                ; r13 = integer%
    mov     r14, rdx                ; r14 = fraction digit

    ; count digits in integer% for alignment
    mov     rax, r13
    xor     rcx, rcx
    test    rax, rax
    jnz     .pct_count
    mov     rcx, 1
    jmp     .pct_counted

.pct_count:
    mov     r8, 10
.pct_count_loop:
    inc     rcx
    xor     rdx, rdx
    div     r8
    test    rax, rax
    jnz     .pct_count_loop

.pct_counted:
    ; print (5 - digits) leading spaces
    mov     r8, 5
    sub     r8, rcx
    jle     .pct_spaces_done

.pct_space_loop:
    push    r8
    mov     rdi, rbx
    lea     rsi, [rel prof_space]
    call    print_str
    pop     r8
    dec     r8
    jnz     .pct_space_loop

.pct_spaces_done:
    ; print integer part
    mov     rdi, rbx
    mov     rsi, r13
    call    print_num

    ; print "."
    mov     rdi, rbx
    lea     rsi, [rel prof_dot]
    call    print_str

    ; print fractional digit
    mov     rdi, rbx
    mov     rsi, r14
    call    print_num

    ; print "%"
    mov     rdi, rbx
    lea     rsi, [rel prof_pct_sign]
    call    print_str

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.pct_zero:
    mov     rdi, rbx
    lea     rsi, [rel prof_pct_zero]
    call    print_str

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- profiler_str_len ----------------------------------------------------
;
; profiler_str_len
; Returns the length of a null-terminated string.
; Internal helper used for name padding calculations.
;
; Input    : rdi = pointer to null-terminated string
; Output   : rax = length in bytes (not including null)
; Clobbers : (none)
;
global profiler_str_len
profiler_str_len:
    xor     rax, rax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret
