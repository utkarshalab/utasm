;
; ============================================================================
; File        : profiler/profiler.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Profiler engine orchestrator — initialization and finalization.
;
; profiler_init allocates all memory, populates phase entries, runs
; RDTSC calibration, and captures the global start timestamp.
;
; profiler_finalize captures the global end timestamp, sums total
; cycles, and triggers hot path detection + ranking.
;
; Start/end phase timing is in phase.s.
; Hot path logic is in hotpath.s + rank.s.
; Report output is in report.s.
;
; See docs/profiler_architecture.md §5, §6.1 for lifecycle details.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ── External dependencies ──
extern arena_alloc
extern rdtsc_read
extern rdtsc_read_end
extern rdtsc_calibrate
extern hotpath_detect
extern hotpath_rank

; ── Profiler module dependencies ──
extern global_profstate
extern prof_phase_names

[SECTION .text]

; ---- profiler_init -------------------------------------------------------
;
; profiler_init
; Allocates PROFENTRY array from the arena, initializes the global
; ProfileState, populates phase entries with IDs and labels, runs
; RDTSC calibration, and captures the pipeline start timestamp.
;
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_OOM
;            rdx = pointer to ProfileState (global_profstate)
; Clobbers : rcx, rsi, r8, r9, r10, r11
;
global profiler_init
profiler_init:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    rbp
    mov     rbp, rsp

    mov     r12, rdi                ; r12 = arena pointer

    ; ── Step 1: Allocate PROFENTRY array ──
    ; MAX_PROF_ENTRIES * PROFENTRY_SIZE = 64 * 48 = 3072 bytes
    mov     rdi, r12
    mov     rsi, MAX_PROF_ENTRIES * PROFENTRY_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .oom

    mov     r13, rdx                ; r13 = PROFENTRY array pointer

    ; ── Step 2: Initialize global_profstate ──
    lea     rbx, [rel global_profstate]

    ; zero the struct
    mov     rdi, rbx
    xor     rax, rax
    mov     rcx, PROFSTATE_SIZE / 8
    cld
    rep     stosq

    ; populate fields
    mov     byte [rbx + PROFSTATE_tag], TAG_PROFSTATE
    mov     byte [rbx + PROFSTATE_enabled], TRUE
    mov     word [rbx + PROFSTATE_num_entries], MAX_PROF_PHASES
    mov     dword [rbx + PROFSTATE_hot_threshold], PROF_HOT_THRESHOLD
    mov     [rbx + PROFSTATE_entries], r13
    mov     [rbx + PROFSTATE_arena], r12

    ; ── Step 3: Initialize each phase entry ──
    lea     r14, [rel prof_phase_names]

    xor     rcx, rcx                ; rcx = phase index (0-based)
.init_phase:
    cmp     rcx, MAX_PROF_PHASES
    jge     .phases_done

    ; compute entry address
    mov     rax, rcx
    imul    rax, PROFENTRY_SIZE
    add     rax, r13                ; rax = &entries[index]

    ; set tag
    mov     byte [rax + PROFENTRY_tag], TAG_PROFENTRY

    ; set phase_id (1-based)
    lea     rdx, [rcx + 1]
    mov     byte [rax + PROFENTRY_phase_id], dl

    ; set label pointer from phase name table
    mov     rdx, [r14 + rcx * 8]
    mov     [rax + PROFENTRY_label], rdx

    ; cycles, call_count, is_hot already zeroed by arena_alloc

    inc     rcx
    jmp     .init_phase

.phases_done:
    ; ── Step 4: Run RDTSC calibration ──
    call    rdtsc_calibrate
    mov     [rbx + PROFSTATE_calib_overhead], rax

    ; ── Step 5: Capture global start timestamp ──
    call    rdtsc_read
    mov     [rbx + PROFSTATE_global_start], rax

    ; ── Return success ──
    xor     rax, rax                ; EXIT_OK
    mov     rdx, rbx                ; rdx = &global_profstate

    mov     rsp, rbp
    pop     rbp
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.oom:
    ; Allocation failed — disable profiler silently
    lea     rbx, [rel global_profstate]
    mov     byte [rbx + PROFSTATE_enabled], FALSE
    mov     rax, EXIT_OOM
    xor     rdx, rdx

    mov     rsp, rbp
    pop     rbp
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- profiler_finalize ---------------------------------------------------
;
; profiler_finalize
; Captures global end timestamp. Sums total cycles across all phase
; entries. Runs hot path detection and sorts entries by cycles.
;
; Must be called after the last profiler_end_phase but before
; profiler_report or profiler_trigger_check.
;
; Input    : rdi = pointer to ProfileState
; Output   : rax = EXIT_OK
; Clobbers : rcx, rdx, rsi, r8, r9, r10, r11
;
global profiler_finalize
profiler_finalize:
    push    rbx
    push    r12
    push    rbp
    mov     rbp, rsp

    mov     rbx, rdi                ; rbx = ProfileState

    ; check enabled
    cmp     byte [rbx + PROFSTATE_enabled], TRUE
    jne     .fin_done

    ; ── Step 1: Capture global end timestamp ──
    call    rdtsc_read_end
    mov     [rbx + PROFSTATE_global_end], rax

    ; ── Step 2: Sum total_cycles ──
    mov     r12, [rbx + PROFSTATE_entries]
    xor     rax, rax                ; accumulator
    xor     rcx, rcx                ; index
    movzx   r8, word [rbx + PROFSTATE_num_entries]

.sum_loop:
    cmp     rcx, r8
    jge     .sum_done

    mov     rdx, rcx
    imul    rdx, PROFENTRY_SIZE
    add     rdx, r12                ; rdx = &entries[index]

    add     rax, [rdx + PROFENTRY_cycles]

    inc     rcx
    jmp     .sum_loop

.sum_done:
    mov     [rbx + PROFSTATE_total_cycles], rax

    ; ── Step 3: Detect hot paths ──
    mov     rdi, r12                ; entries array
    movzx   rsi, word [rbx + PROFSTATE_num_entries]
    mov     edx, dword [rbx + PROFSTATE_hot_threshold]
    ; zero-extend threshold to 64-bit
    call    hotpath_detect
    ; rax = hot_count (informational)

    ; ── Step 4: Sort entries by cycles descending ──
    mov     rdi, r12                ; entries array
    movzx   rsi, word [rbx + PROFSTATE_num_entries]
    call    hotpath_rank

.fin_done:
    xor     rax, rax                ; EXIT_OK

    mov     rsp, rbp
    pop     rbp
    pop     r12
    pop     rbx
    ret
