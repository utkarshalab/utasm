;
; ============================================================================
; File        : src/profile/rank.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Entry ranking — insertion sort by cycles descending.
;
; Sorts PROFENTRY array so the hottest phase is at index 0.
; Uses insertion sort because N ≤ 64 entries (3072 bytes) fits
; entirely in L1 cache, making it faster than quicksort.
;
; See src/profile/README.md for algorithm rationale.
; ============================================================================
;

bits 64

%include "src/include/constant.inc"
%include "src/include/type.inc"

[SECTION .text]

; ---- hotpath_rank --------------------------------------------------------
;
; hotpath_rank
; Sorts PROFENTRY array by cycles descending (insertion sort).
;
; Algorithm:
;   for i = 1 to count-1:
;       key = entries[i]
;       j = i - 1
;       while j >= 0 and entries[j].cycles < key.cycles:
;           entries[j+1] = entries[j]
;           j--
;       entries[j+1] = key
;
; Input    : rdi = pointer to PROFENTRY array
;            rsi = entry count
; Output   : (none — array sorted in-place)
; Clobbers : rax, rcx, rdx, r8, r9, r10, r11
;
global hotpath_rank
hotpath_rank:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    rbp
    mov     rbp, rsp
    sub     rsp, PROFENTRY_SIZE     ; temp buffer (48 bytes) on stack

    mov     rbx, rdi                ; rbx = entries base pointer
    mov     r12, rsi                ; r12 = count

    ; nothing to sort if 0 or 1 entries
    cmp     r12, 2
    jb      .done

    mov     r13, 1                  ; r13 = i (outer loop index)

.outer:
    cmp     r13, r12
    jge     .done

    ; ── copy entries[i] into temp buffer ──
    mov     rax, r13
    imul    rax, PROFENTRY_SIZE
    lea     rsi, [rbx + rax]        ; source = &entries[i]
    mov     rdi, rsp                ; dest = temp buffer on stack
    mov     rcx, PROFENTRY_SIZE / 8 ; 48/8 = 6 qwords
    cld
    rep     movsq

    ; key_cycles = temp.cycles (for comparisons)
    mov     r14, [rsp + PROFENTRY_cycles]

    ; j = i - 1
    mov     r9, r13
    dec     r9

.inner:
    ; while j >= 0 ...
    test    r9, r9
    js      .insert                 ; j < 0 → insert at position 0

    ; compute &entries[j]
    mov     rax, r9
    imul    rax, PROFENTRY_SIZE
    lea     r10, [rbx + rax]        ; r10 = &entries[j]

    ; ... and entries[j].cycles < key.cycles (descending order)
    mov     r11, [r10 + PROFENTRY_cycles]
    cmp     r11, r14
    jge     .insert                 ; entries[j] >= key → stop shifting

    ; ── shift entries[j] → entries[j+1] ──
    lea     rdi, [r10 + PROFENTRY_SIZE]   ; dest = &entries[j+1]
    mov     rsi, r10                       ; source = &entries[j]
    mov     rcx, PROFENTRY_SIZE / 8        ; 6 qwords
    cld
    rep     movsq

    dec     r9                      ; j--
    jmp     .inner

.insert:
    ; ── entries[j+1] = temp ──
    mov     rax, r9
    inc     rax                     ; j + 1
    imul    rax, PROFENTRY_SIZE
    lea     rdi, [rbx + rax]        ; dest = &entries[j+1]
    mov     rsi, rsp                ; source = temp buffer
    mov     rcx, PROFENTRY_SIZE / 8 ; 6 qwords
    cld
    rep     movsq

    inc     r13                     ; i++
    jmp     .outer

.done:
    mov     rsp, rbp
    pop     rbp
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
