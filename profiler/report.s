;
; ============================================================================
; File        : profiler/report.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Profiler report orchestrator — assembles the full report.
;
; Prints the complete profiler report to stderr:
;   1. Top border
;   2. Title
;   3. Column headers
;   4. Separator
;   5. One row per phase entry (via profiler_print_row)
;   6. Separator
;   7. Total line
;   8. Bottom border
;   9. Footer (legend, calibration overhead, wall clock)
;
; All row rendering is delegated to table.s.
; All number formatting is delegated to fmt.s.
; All string constants come from strings.s.
;
; See docs/profiler_architecture.md §9 for report format spec.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ── External dependencies ──
extern print_str
extern print_num

; ── Profiler module dependencies ──
extern profiler_print_row
extern profiler_print_header_row
extern profiler_print_padded

; ── String constants from strings.s ──
extern prof_border_heavy
extern prof_border_light
extern prof_report_title
extern prof_newline
extern prof_total_prefix
extern prof_total_pct
extern prof_footer_legend
extern prof_footer_calib_prefix
extern prof_footer_calib_suffix
extern prof_footer_wall_prefix
extern prof_footer_wall_suffix

[SECTION .text]

; ---- profiler_report -----------------------------------------------------
;
; profiler_report
; Generates the full profiler report and writes it to stderr.
;
; Input    : rdi = pointer to ProfileState
;            rsi = pointer to AsmCtx (for flags check — reserved)
; Output   : rax = EXIT_OK
; Clobbers : rcx, rdx, r8-r11
;
global profiler_report
profiler_report:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    rbp
    mov     rbp, rsp

    mov     rbx, rdi                ; rbx = ProfileState
    mov     r14, rsi                ; r14 = AsmCtx (reserved for color flags)

    ; check enabled
    cmp     byte [rbx + PROFSTATE_enabled], TRUE
    jne     .done

    ; ── 1. Top border ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_border_heavy]
    call    print_str

    ; ── 2. Title ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_report_title]
    call    print_str

    ; ── 3. Mid border ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_border_heavy]
    call    print_str

    ; ── 4. Column headers ──
    call    profiler_print_header_row

    ; ── 5. Separator ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_border_light]
    call    print_str

    ; ── 6. Data rows ──
    mov     r12, [rbx + PROFSTATE_entries]
    movzx   r13, word [rbx + PROFSTATE_num_entries]
    xor     rcx, rcx                ; index

.row_loop:
    cmp     rcx, r13
    jge     .rows_done

    ; compute entry pointer
    push    rcx                     ; save index across call
    mov     rax, rcx
    imul    rax, PROFENTRY_SIZE
    lea     rdi, [r12 + rax]

    ; skip entries with zero cycles (unused sub-phase slots)
    cmp     qword [rdi + PROFENTRY_cycles], 0
    je      .row_skip

    ; print the row
    mov     rsi, [rbx + PROFSTATE_total_cycles]
    call    profiler_print_row

.row_skip:
    pop     rcx
    inc     rcx
    jmp     .row_loop

.rows_done:
    ; ── 7. Separator ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_border_light]
    call    print_str

    ; ── 8. Total line ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_total_prefix]
    call    print_str

    ; print total cycles (right-aligned in 14 chars)
    mov     rdi, STDERR_FILENO
    mov     rsi, [rbx + PROFSTATE_total_cycles]
    mov     rdx, 14
    call    profiler_print_padded

    ; print "   100.0%\n"
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_total_pct]
    call    print_str

    ; ── 9. Bottom border ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_border_heavy]
    call    print_str

    ; ── 10. Footer: hot path legend ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_footer_legend]
    call    print_str

    ; ── 11. Footer: calibration overhead ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_footer_calib_prefix]
    call    print_str

    mov     rdi, STDERR_FILENO
    mov     rsi, [rbx + PROFSTATE_calib_overhead]
    call    print_num

    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_footer_calib_suffix]
    call    print_str

    ; ── 12. Footer: wall clock ──
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_footer_wall_prefix]
    call    print_str

    ; wall clock = global_end - global_start
    mov     rax, [rbx + PROFSTATE_global_end]
    sub     rax, [rbx + PROFSTATE_global_start]
    mov     rdi, STDERR_FILENO
    mov     rsi, rax
    call    print_num

    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_footer_wall_suffix]
    call    print_str

.done:
    xor     rax, rax                ; EXIT_OK

    mov     rsp, rbp
    pop     rbp
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
