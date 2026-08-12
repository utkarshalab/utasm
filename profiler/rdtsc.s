;
; ============================================================================
; File        : profiler/rdtsc.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Low-level RDTSC/RDTSCP wrappers with serialization.
;
; These are leaf functions with no dependencies. They do NOT use
; prologue/epilogue macros to avoid inflating calibration measurements.
;
; See docs/profiler_architecture.md §2, §6.1, §16 for design rationale.
; ============================================================================
;

bits 64

%include "include/constant.inc"

[SECTION .text]

; ---- rdtsc_read ----------------------------------------------------------
;
; rdtsc_read
; Serialized TSC read for START measurements.
; Uses LFENCE before RDTSC to prevent instruction reordering.
; The LFENCE drains the instruction pipeline, ensuring all prior
; instructions have completed before the timestamp is captured.
;
; Input    : (none)
; Output   : rax = 64-bit TSC value (EDX:EAX combined)
; Clobbers : rdx, rcx (rcx not used but RDTSC may clobber on some µarch)
;
global rdtsc_read
rdtsc_read:
    lfence                          ; serialize: complete all prior instructions
    rdtsc                           ; EDX:EAX = 64-bit timestamp counter
    shl     rdx, 32                 ; shift high 32 bits into position
    or      rax, rdx                ; rax = full 64-bit TSC
    ret

; ---- rdtsc_read_end ------------------------------------------------------
;
; rdtsc_read_end
; Serialized TSC read for END measurements.
; Uses RDTSCP (which is itself serializing — waits for prior instructions)
; followed by LFENCE to prevent future instructions from reordering before.
;
; RDTSCP also writes the processor ID into ECX, which we discard.
; This provides a stronger "happens-after" guarantee than LFENCE+RDTSC.
;
; Input    : (none)
; Output   : rax = 64-bit TSC value (EDX:EAX combined)
; Clobbers : rdx, rcx (ECX = processor ID, discarded)
;
global rdtsc_read_end
rdtsc_read_end:
    rdtscp                          ; EDX:EAX = TSC, ECX = processor ID
    lfence                          ; prevent future insns from moving before
    shl     rdx, 32                 ; shift high 32 bits into position
    or      rax, rdx                ; rax = full 64-bit TSC
    ret

; ---- rdtsc_calibrate -----------------------------------------------------
;
; rdtsc_calibrate
; Measures the overhead of one RDTSC start/end pair by running
; PROF_CALIB_ITERS (1024) empty measurements and returning the minimum.
;
; The minimum is used because higher values include OS interrupts,
; cache misses, and context switches — noise we want to exclude.
; The true instruction overhead is the floor of all measurements.
;
; Input    : (none)
; Output   : rax = minimum overhead in cycles (typically 25–40)
; Clobbers : rbx, rcx, rdx, r12, r13
;
; NOTE: This function saves callee-saved registers manually (no prologue)
;       because it is called during profiler_init before the main pipeline.
;
global rdtsc_calibrate
rdtsc_calibrate:
    push    rbx
    push    r12
    push    r13

    ; r12 = minimum overhead seen (initialized to MAX)
    mov     r12, 0xFFFFFFFFFFFFFFFF
    ; r13 = iteration counter
    mov     r13, PROF_CALIB_ITERS

.calib_loop:
    ; ── start timestamp ──
    lfence
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     rbx, rax                ; rbx = start TSC

    ; ── (empty — measuring overhead only) ──

    ; ── end timestamp ──
    rdtscp
    lfence
    shl     rdx, 32
    or      rax, rdx                ; rax = end TSC

    ; ── compute delta ──
    sub     rax, rbx                ; rax = end - start = overhead

    ; ── track minimum ──
    cmp     rax, r12
    cmovb   r12, rax                ; r12 = min(r12, rax)

    dec     r13
    jnz     .calib_loop

    ; return minimum overhead
    mov     rax, r12

    pop     r13
    pop     r12
    pop     rbx
    ret
