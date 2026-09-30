;
; ============================================================================
; File        : tests/unit/test_profiler.s
; Project     : utasm
; Description : Standalone test of the profiler subsystem (profiler/*.s),
;               built and run by scripts/test_profiler.sh.
;
;   It drives the public API the way the assembler does - init, a
;   start/end pair per phase, finalize, report - and checks the state it
;   leaves behind. Exit status 0 means every check passed; otherwise the
;   failing check's number is printed and the exit status is 1.
; ============================================================================
;

%include "include/macro.inc"
%include "include/constant.inc"
%include "include/type.inc"

extern  arena_init
extern  profiler_init
extern  profiler_is_enabled
extern  profiler_start_phase
extern  profiler_end_phase
extern  profiler_get_entry
extern  profiler_get_total_cycles
extern  profiler_finalize
extern  profiler_report

[SECTION .bss]
arena:      resb ARENA_SIZE
state:      resq 1
checks:     resq 1                  ; number of the check being run
numbuf:     resb 24

[SECTION .rodata]
msg_fail:   db "test_profiler: FAILED check ", 0
msg_ok:     db "test_profiler: all checks passed", 10, 0
msg_nl:     db 10, 0

[SECTION .text]

; CHECK jcc: count the check; the jump (the opposite of what must hold)
; goes to the failure report
%macro CHECK 1
    mov     r15, [rel checks]              ; mov/lea: the flags must survive
    lea     r15, [r15 + 1]
    mov     [rel checks], r15
    %1      fail
%endmacro

global _start
_start:
    ; ---- 1. an arena and profiler_init ----
    lea     rdi, [rel arena]
    mov     rsi, 65536
    call    arena_init
    test    rax, rax
    CHECK   jnz

    lea     rdi, [rel arena]
    call    profiler_init
    test    rax, rax
    CHECK   jnz
    mov     [rel state], rdx
    test    rdx, rdx
    CHECK   jz

    mov     rbx, [rel state]
    cmp     byte [rbx + PROFSTATE_tag], TAG_PROFSTATE
    CHECK   jne
    cmp     byte [rbx + PROFSTATE_enabled], TRUE
    CHECK   jne
    cmp     word [rbx + PROFSTATE_num_entries], MAX_PROF_PHASES
    CHECK   jne
    cmp     qword [rbx + PROFSTATE_entries], 0
    CHECK   je
    call    profiler_is_enabled
    cmp     rax, TRUE
    CHECK   jne

    ; every entry is tagged and numbered 1..MAX_PROF_PHASES
    mov     r12, [rbx + PROFSTATE_entries]
    xor     r13d, r13d
.ids:
    mov     rax, r13
    imul    rax, rax, PROFENTRY_SIZE
    cmp     byte [r12 + rax + PROFENTRY_tag], TAG_PROFENTRY
    CHECK   jne
    lea     ecx, [r13 + 1]
    cmp     byte [r12 + rax + PROFENTRY_phase_id], cl
    CHECK   jne
    cmp     qword [r12 + rax + PROFENTRY_label], 0
    CHECK   je
    inc     r13d
    cmp     r13d, MAX_PROF_PHASES
    jb      .ids

    ; ---- 2. profiler_get_entry ----
    mov     rdi, rbx
    xor     esi, esi
    call    profiler_get_entry
    test    rax, rax
    CHECK   jnz                              ; phase 0 does not exist
    mov     rdi, rbx
    mov     esi, MAX_PROF_PHASES + 1
    call    profiler_get_entry
    test    rax, rax
    CHECK   jnz
    mov     rdi, rbx
    mov     esi, PHASE_PARSER
    call    profiler_get_entry
    lea     rcx, [r12 + (PHASE_PARSER - 1) * PROFENTRY_SIZE]
    cmp     rax, rcx
    CHECK   jne

    ; ---- 3. a start/end pair for each phase, spending more time in later ones ----
    mov     r13d, PHASE_LEXER
.phase:
    mov     rdi, rbx
    mov     esi, r13d
    call    profiler_start_phase
    test    rax, rax
    CHECK   jnz
    mov     ecx, r13d
    imul    ecx, ecx, 20000                ; busy work
.spin:
    dec     ecx
    jnz     .spin
    mov     rdi, rbx
    mov     esi, r13d
    call    profiler_end_phase
    test    rax, rax
    CHECK   jnz
    mov     rdi, rbx
    mov     esi, r13d
    call    profiler_get_entry
    cmp     dword [rax + PROFENTRY_call_count], 1
    CHECK   jne
    mov     rcx, [rax + PROFENTRY_end_tsc]
    cmp     rcx, [rax + PROFENTRY_start_tsc]
    CHECK   jb                             ; the clock does not run backwards
    inc     r13d
    cmp     r13d, PHASE_OUTPUT
    jbe     .phase

    ; phase IDs outside 1..MAX_PROF_PHASES are refused
    mov     rdi, rbx
    xor     esi, esi
    call    profiler_start_phase
    cmp     rax, EXIT_INTERNAL
    CHECK   jne
    mov     rdi, rbx
    mov     esi, 200
    call    profiler_end_phase
    cmp     rax, EXIT_INTERNAL
    CHECK   jne

    ; the longest phase measured some cycles
    mov     rdi, rbx
    mov     esi, PHASE_OUTPUT
    call    profiler_get_entry
    cmp     qword [rax + PROFENTRY_cycles], 0
    CHECK   jbe

    ; ---- 4. profiler_finalize: total = sum of phases, entries ranked ----
    mov     rdi, rbx
    call    profiler_finalize
    test    rax, rax
    CHECK   jnz
    xor     r14, r14                       ; sum of the entries
    xor     r13d, r13d
.sum:
    mov     rax, r13
    imul    rax, rax, PROFENTRY_SIZE
    add     r14, [r12 + rax + PROFENTRY_cycles]
    inc     r13d
    cmp     r13d, MAX_PROF_PHASES
    jb      .sum
    mov     rdi, rbx
    call    profiler_get_total_cycles
    cmp     rax, r14
    CHECK   jne
    xor     r13d, r13d
.sorted:
    mov     rax, r13
    imul    rax, rax, PROFENTRY_SIZE
    mov     rcx, [r12 + rax + PROFENTRY_cycles]
    cmp     rcx, [r12 + rax + PROFENTRY_SIZE + PROFENTRY_cycles]
    CHECK   jb                             ; descending by cycles
    inc     r13d
    cmp     r13d, MAX_PROF_PHASES - 1
    jb      .sorted

    ; ---- 5. the report runs ----
    mov     rdi, rbx
    call    profiler_report
    test    rax, rax
    CHECK   jnz

    mov     rdi, 1
    lea     rsi, [rel msg_ok]
    call    print_str
    mov     eax, 60
    xor     edi, edi
    syscall

fail:
    mov     rdi, 2
    lea     rsi, [rel msg_fail]
    call    print_str
    mov     rdi, 2
    mov     rsi, [rel checks]
    call    print_num
    mov     rdi, 2
    lea     rsi, [rel msg_nl]
    call    print_str
    mov     eax, 60
    mov     edi, 1
    syscall

; ---- the output helpers the profiler report uses (utasm.s has its own) ----

; print_str: write the NUL-terminated string RSI to fd RDI
global print_str
print_str:
    push    rdi
    push    rsi
    xor     edx, edx
.len:
    cmp     byte [rsi + rdx], 0
    je      .write
    inc     rdx
    jmp     .len
.write:
    mov     eax, 1                         ; write(fd, str, len)
    syscall
    pop     rsi
    pop     rdi
    ret

; print_num: write the unsigned number RSI in decimal to fd RDI
global print_num
print_num:
    push    rdi
    lea     r8, [rel numbuf + 23]
    mov     byte [r8], 0
    mov     rax, rsi
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digit
    pop     rdi
    mov     rsi, r8
    jmp     print_str
