;
; ============================================================================
; File        : profiler/table.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Report table rendering — single row formatting.
;
; Formats one PROFENTRY into a fixed-column table row:
;   " <name>     <cycles>  <pct>  <calls>  <avg>  [HOT]"
;
; Called by report.s for each entry in the sorted array.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

extern print_str
extern print_num
extern profiler_print_padded
extern profiler_print_percent
extern profiler_str_len
extern prof_row_prefix
extern prof_space
extern prof_hot_marker
extern prof_newline

[SECTION .text]

; ---- profiler_print_row --------------------------------------------------
;
; profiler_print_row
; Formats and prints a single PROFENTRY as a table row to stderr.
;
; Column layout (character positions):
;   [0]     " "          prefix space
;   [1-16]  phase name   left-aligned, padded to 16 chars
;   [17-30] cycles       right-aligned in 14 chars
;   [31-38] percentage   right-aligned "NN.N%"
;   [39-47] call count   right-aligned in 9 chars
;   [48-56] avg cycles   right-aligned in 9 chars
;   [57-61] hot marker   "  HOT" or blank
;   [62]    newline
;
; Input    : rdi = pointer to PROFENTRY
;            rsi = total_cycles (for percentage computation)
; Output   : (none)
; Clobbers : rax, rcx, rdx, r8-r11
;
global profiler_print_row
profiler_print_row:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; rbx = PROFENTRY pointer
    mov     r12, rsi                ; r12 = total_cycles

    ; ── column 1: row prefix " " ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_row_prefix]
    call    print_str

    ; ── column 2: phase name (left-aligned, padded to 16 chars) ──
    mov     rdi, STDERR_FILENO
    mov     rsi, [rbx + PROFENTRY_label]
    call    print_str

    ; compute padding = 16 - strlen(label)
    mov     rdi, [rbx + PROFENTRY_label]
    call    profiler_str_len
    mov     r13, 16
    sub     r13, rax                ; r13 = spaces needed
    jle     .name_pad_done

.name_pad:
    push    r13
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_space]
    call    print_str
    pop     r13
    dec     r13
    jnz     .name_pad
.name_pad_done:

    ; ── column 3: cycles (right-aligned in 14 chars) ──
    mov     rdi, STDERR_FILENO
    mov     rsi, [rbx + PROFENTRY_cycles]
    mov     rdx, 14
    call    profiler_print_padded

    ; ── column 4: percentage ──
    mov     rdi, STDERR_FILENO
    mov     rsi, [rbx + PROFENTRY_cycles]
    mov     rdx, r12                ; total_cycles
    call    profiler_print_percent

    ; ── column 5: call count (right-aligned in 9 chars) ──
    mov     rdi, STDERR_FILENO
    mov     esi, dword [rbx + PROFENTRY_call_count]
    mov     rdx, 9
    call    profiler_print_padded

    ; ── column 6: average cycles per call (right-aligned in 9 chars) ──
    mov     rax, [rbx + PROFENTRY_cycles]
    mov     ecx, dword [rbx + PROFENTRY_call_count]
    test    rcx, rcx
    jz      .avg_zero
    xor     rdx, rdx
    div     rcx                     ; rax = cycles / call_count
    jmp     .avg_print
.avg_zero:
    xor     rax, rax
.avg_print:
    mov     rdi, STDERR_FILENO
    mov     rsi, rax
    mov     rdx, 9
    call    profiler_print_padded

    ; ── column 7: hot marker ──
    cmp     byte [rbx + PROFENTRY_is_hot], TRUE
    jne     .no_hot

    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_hot_marker]
    call    print_str

.no_hot:
    ; ── newline ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_newline]
    call    print_str

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- profiler_print_header_row -------------------------------------------
;
; profiler_print_header_row
; Prints the column header line.
;
; Input    : (none)
; Output   : (none)
; Clobbers : rax, rdi, rsi
;
global profiler_print_header_row
profiler_print_header_row:
    extern prof_col_header
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_col_header]
    call    print_str
    ret
