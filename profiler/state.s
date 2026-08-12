;
; ============================================================================
; File        : profiler/state.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Global profiler state allocation and accessor functions.
;
; Owns the global_profstate BSS region. Provides helper functions for
; querying profiler status without exposing the struct layout to callers.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

[SECTION .bss]
    align 64

; ---- Global Profiler State ----
; Single instance. Initialized by profiler_init, read by all profiler modules.
global global_profstate
global_profstate: resb PROFSTATE_SIZE
    resb 64                         ; guard padding against buffer overruns

[SECTION .text]

; ---- profiler_is_enabled -------------------------------------------------
;
; profiler_is_enabled
; Fast check: is the profiler currently active?
;
; Input    : (none)
; Output   : rax = TRUE (1) if enabled, FALSE (0) otherwise
; Clobbers : (none)
;
global profiler_is_enabled
profiler_is_enabled:
    lea     rax, [rel global_profstate]
    movzx   eax, byte [rax + PROFSTATE_enabled]
    ret

; ---- profiler_get_state --------------------------------------------------
;
; profiler_get_state
; Returns a pointer to the global ProfileState.
;
; Input    : (none)
; Output   : rax = pointer to global_profstate
; Clobbers : (none)
;
global profiler_get_state
profiler_get_state:
    lea     rax, [rel global_profstate]
    ret

; ---- profiler_get_entry --------------------------------------------------
;
; profiler_get_entry
; Returns a pointer to the PROFENTRY for the given phase_id.
;
; Input    : rdi = pointer to ProfileState
;            rsi = phase_id (1-based, PHASE_* constant)
; Output   : rax = pointer to PROFENTRY, or 0 if invalid
; Clobbers : rcx, rdx
;
global profiler_get_entry
profiler_get_entry:
    ; validate phase_id
    cmp     rsi, 1
    jb      .invalid
    cmp     rsi, MAX_PROF_PHASES
    ja      .invalid

    ; compute: entries + (phase_id - 1) * PROFENTRY_SIZE
    mov     rax, [rdi + PROFSTATE_entries]
    mov     rcx, rsi
    dec     rcx
    imul    rcx, PROFENTRY_SIZE
    add     rax, rcx
    ret

.invalid:
    xor     rax, rax
    ret

; ---- profiler_get_total_cycles -------------------------------------------
;
; profiler_get_total_cycles
; Returns the total accumulated cycles across all phases.
;
; Input    : rdi = pointer to ProfileState
; Output   : rax = total_cycles
; Clobbers : (none)
;
global profiler_get_total_cycles
profiler_get_total_cycles:
    mov     rax, [rdi + PROFSTATE_total_cycles]
    ret
