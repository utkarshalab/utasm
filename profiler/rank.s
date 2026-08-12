;
; ============================================================================
; File        : profiler/rank.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Entry ranking — insertion sort by cycles descending.
;
; Sorts PROFENTRY array so the hottest phase is at index 0.
; Uses insertion sort because N ≤ 64 entries (3072 bytes) fits
; entirely in L1 cache, making it faster than quicksort.
;
; See docs/profiler_architecture.md §7.2 for algorithm rationale.
; ============================================================================
;

bits 64

%include "include/constant.inc"
%include "include/type.inc"

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

; ---- hotpath_get_top -----------------------------------------------------
;
; hotpath_get_top
; After sorting, returns a pointer to the first entry (hottest phase)
; and the clamped count of entries to return.
;
; Input    : rdi = pointer to PROFENTRY array (already sorted descending)
;            rsi = total entry count
;            rdx = maximum number of entries to return (n)
; Output   : rax = actual count returned: min(count, n)
;            rdx = pointer to first entry (entries[0])
; Clobbers : (none)
;
global hotpath_get_top
hotpath_get_top:
    mov     rax, rdx                ; rax = n
    cmp     rax, rsi
    cmova   rax, rsi                ; rax = min(n, count)
    mov     rdx, rdi                ; rdx = pointer to entries[0]
    ret
