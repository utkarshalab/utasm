;
; ============================================================================
; File        : profiler/hotpath.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Hot path detection — threshold-based classification.
;
; Scans the PROFENTRY array and flags entries whose accumulated cycle
; count exceeds the hot_threshold. O(N) linear scan, N ≤ 64.
;
; See docs/profiler_architecture.md §7.1 for algorithm details.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

[SECTION .text]

; ---- hotpath_detect ------------------------------------------------------
;
; hotpath_detect
; Sets is_hot = TRUE on entries exceeding the threshold.
; Sets is_hot = FALSE on entries below.
;
; Input    : rdi = pointer to PROFENTRY array
;            rsi = entry count
;            rdx = hot threshold in cycles (64-bit)
; Output   : rax = number of hot entries found
; Clobbers : rcx, r8, r9, r10
;
global hotpath_detect
hotpath_detect:
    xor     rax, rax                ; rax = hot_count = 0
    xor     rcx, rcx                ; rcx = index = 0
    mov     r8,  rdi                ; r8  = entries base pointer
    mov     r9,  rsi                ; r9  = count
    mov     r10, rdx                ; r10 = threshold

    test    r9, r9
    jz      .done

.loop:
    ; compute entry pointer: r8 + rcx * PROFENTRY_SIZE
    mov     rdi, rcx
    imul    rdi, PROFENTRY_SIZE
    add     rdi, r8                 ; rdi = &entries[rcx]

    ; load cycles for this entry
    mov     rdx, [rdi + PROFENTRY_cycles]

    ; compare against threshold
    cmp     rdx, r10
    jb      .not_hot

    ; mark as hot
    mov     byte [rdi + PROFENTRY_is_hot], TRUE
    inc     rax                     ; hot_count++
    jmp     .next

.not_hot:
    mov     byte [rdi + PROFENTRY_is_hot], FALSE

.next:
    inc     rcx
    cmp     rcx, r9
    jb      .loop

.done:
    ret
