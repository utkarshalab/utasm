;
; ============================================================================
; File        : profiler/phase.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Per-phase measurement — start and end timestamp capture.
;
; These are the hot-path functions called at every pipeline phase transition.
; profiler_start_phase inlines LFENCE+RDTSC (no function call overhead).
; profiler_end_phase captures RDTSCP first, then validates (excludes
; validation time from the measurement).
;
; See docs/profiler_architecture.md §6.2, §6.3 for protocol details.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

[SECTION .text]

; ---- profiler_start_phase ------------------------------------------------
;
; profiler_start_phase
; Records a serialized RDTSC start timestamp for the given phase.
; Increments the phase's call count.
;
; Uses inlined LFENCE+RDTSC rather than calling rdtsc_read to
; eliminate function call overhead in the hot path.
;
; Input    : rdi = pointer to ProfileState
;            rsi = phase_id (PHASE_* constant, 1-based)
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : rcx, rdx, r8
;
global profiler_start_phase
profiler_start_phase:
    ; fast path: check if profiling is enabled
    cmp     byte [rdi + PROFSTATE_enabled], TRUE
    jne     .start_disabled

    ; validate phase_id range [1, MAX_PROF_PHASES]
    cmp     rsi, 1
    jb      .start_invalid
    cmp     rsi, MAX_PROF_PHASES
    ja      .start_invalid

    ; compute entry pointer: entries + (phase_id - 1) * PROFENTRY_SIZE
    push    rbx
    mov     rbx, [rdi + PROFSTATE_entries]
    mov     rax, rsi
    dec     rax                     ; 0-based index
    imul    rax, PROFENTRY_SIZE
    add     rbx, rax                ; rbx = &entries[phase_id - 1]

    ; ── capture serialized start timestamp (inlined) ──
    lfence                          ; serialize: complete all prior instructions
    rdtsc                           ; EDX:EAX = 64-bit timestamp counter
    shl     rdx, 32
    or      rax, rdx                ; rax = full 64-bit TSC

    ; store start_tsc
    mov     [rbx + PROFENTRY_start_tsc], rax

    ; increment call count
    inc     dword [rbx + PROFENTRY_call_count]

    xor     rax, rax                ; EXIT_OK
    pop     rbx
    ret

.start_disabled:
    xor     rax, rax                ; EXIT_OK (silently skip)
    ret

.start_invalid:
    mov     rax, EXIT_INTERNAL
    ret

; ---- profiler_end_phase --------------------------------------------------
;
; profiler_end_phase
; Records a serialized RDTSCP end timestamp, computes the delta,
; subtracts calibration overhead, and accumulates into entry.cycles.
;
; IMPORTANT: The RDTSCP is captured FIRST, before any validation,
; so that validation overhead is excluded from the measurement.
;
; Input    : rdi = pointer to ProfileState
;            rsi = phase_id (PHASE_* constant, 1-based)
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : rcx, rdx, r8, r9
;
global profiler_end_phase
profiler_end_phase:
    ; fast path: check if profiling is enabled
    cmp     byte [rdi + PROFSTATE_enabled], TRUE
    jne     .end_disabled

    ; ── capture end timestamp FIRST (before validation) ──
    ; This is the key design decision: we take the timestamp immediately
    ; so that validation code doesn't inflate the measured delta.
    push    rbx
    push    r12

    rdtscp                          ; EDX:EAX = TSC, ECX = processor ID
    lfence                          ; prevent future insns from reordering
    shl     rdx, 32
    or      rax, rdx
    mov     r12, rax                ; r12 = end TSC (saved)

    ; validate phase_id range [1, MAX_PROF_PHASES]
    cmp     rsi, 1
    jb      .end_invalid
    cmp     rsi, MAX_PROF_PHASES
    ja      .end_invalid

    ; compute entry pointer
    mov     rbx, [rdi + PROFSTATE_entries]
    mov     rax, rsi
    dec     rax
    imul    rax, PROFENTRY_SIZE
    add     rbx, rax                ; rbx = &entries[phase_id - 1]

    ; store end_tsc
    mov     [rbx + PROFENTRY_end_tsc], r12

    ; compute delta = end_tsc - start_tsc
    mov     rax, r12
    sub     rax, [rbx + PROFENTRY_start_tsc]

    ; subtract calibration overhead
    mov     r8, [rdi + PROFSTATE_calib_overhead]
    sub     rax, r8

    ; clamp to 0 if underflow (overhead > actual delta)
    jns     .end_no_clamp
    xor     rax, rax
.end_no_clamp:

    ; accumulate into cycles (handles repeated phases like ENCODER)
    add     [rbx + PROFENTRY_cycles], rax

    xor     rax, rax                ; EXIT_OK
    pop     r12
    pop     rbx
    ret

.end_disabled:
    xor     rax, rax                ; EXIT_OK (silently skip)
    ret

.end_invalid:
    mov     rax, EXIT_INTERNAL
    pop     r12
    pop     rbx
    ret
