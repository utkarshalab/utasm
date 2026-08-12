;
; ============================================================================
; File        : profiler/trigger.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Self-patch trigger bridge — hot path → selfpatch engine.
;
; After profiler_finalize, the trigger module scans hot entries and
; calls into the self-patch engine's suggestion interface.
;
; Currently the self-patch engine is stubbed, so triggers log a
; diagnostic message to stderr and return without applying patches.
;
; See docs/profiler_architecture.md §10 for trigger protocol.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

extern print_str
extern print_num

; ── String constants from strings.s ──
extern prof_trigger_hot_prefix
extern prof_trigger_hot_suffix
extern prof_trigger_stub_msg
extern prof_trigger_open_paren

[SECTION .text]

; ---- profiler_trigger_check ----------------------------------------------
;
; profiler_trigger_check
; Scans the PROFENTRY array for hot entries and invokes the trigger
; for each one. Returns the count of triggered hot paths.
;
; Input    : rdi = pointer to ProfileState
;            rsi = pointer to AsmCtx (reserved for CTX_FLAG_SELFPATCH check)
; Output   : rax = number of hot paths triggered
; Clobbers : rcx, rdx, r8-r11
;
global profiler_trigger_check
profiler_trigger_check:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; rbx = ProfileState
    ; rsi = AsmCtx (reserved)

    ; check enabled
    cmp     byte [rbx + PROFSTATE_enabled], TRUE
    jne     .check_done_zero

    mov     r12, [rbx + PROFSTATE_entries]
    movzx   r13, word [rbx + PROFSTATE_num_entries]
    xor     r14, r14                ; r14 = triggered count
    xor     rcx, rcx                ; index

.check_loop:
    cmp     rcx, r13
    jge     .check_done

    ; compute entry pointer
    push    rcx
    mov     rax, rcx
    imul    rax, PROFENTRY_SIZE
    lea     rdi, [r12 + rax]

    ; check if hot
    cmp     byte [rdi + PROFENTRY_is_hot], TRUE
    jne     .check_next

    ; ── trigger for this entry ──
    ; Keep the entry pointer in R8 and read every field from it. Loading
    ; cycles into RSI first and then dereferencing RSI treats a cycle count
    ; as an address.
    mov     r8, rdi                       ; r8 = PROFENTRY*
    mov     rdx, [r8 + PROFENTRY_label]   ; rdx = phase name
    mov     rsi, [r8 + PROFENTRY_cycles]  ; rsi = cycles
    movzx   rdi, byte [r8 + PROFENTRY_phase_id]
    call    profiler_trigger_selfpatch

    inc     r14                     ; triggered++

.check_next:
    pop     rcx
    inc     rcx
    jmp     .check_loop

.check_done:
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.check_done_zero:
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- profiler_trigger_selfpatch ------------------------------------------
;
; profiler_trigger_selfpatch
; Bridge to the self-patch engine. Currently a diagnostic stub that
; logs the hot path detection to stderr.
;
; When the selfpatch engine is implemented, this function will call
; selfpatch_suggest(phase_id, cycles) instead of logging.
;
; Input    : rdi = phase_id (byte)
;            rsi = cycles (qword)
;            rdx = phase name label pointer
; Output   : rax = EXIT_OK
; Clobbers : rcx, r8
;
global profiler_trigger_selfpatch
profiler_trigger_selfpatch:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi                ; phase_id
    mov     r12, rsi                ; cycles
    mov     r13, rdx                ; label

    ; print: "[profiler] hot path detected: "
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_trigger_hot_prefix]
    call    print_str

    ; print phase name
    mov     rdi, STDERR_FILENO
    mov     rsi, r13
    call    print_str

    ; print " ("
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_trigger_open_paren]
    call    print_str

    ; print cycle count
    mov     rdi, STDERR_FILENO
    mov     rsi, r12
    call    print_num

    ; print " cycles)\n"
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_trigger_hot_suffix]
    call    print_str

    ; print stub message
    mov     rdi, STDERR_FILENO
    lea     rsi, [rel prof_trigger_stub_msg]
    call    print_str

    xor     rax, rax                ; EXIT_OK

    pop     r13
    pop     r12
    pop     rbx
    ret
