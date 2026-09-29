;
; ============================================
; File     : lib/sort.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ============================================================================
; SORTING AND SEARCHING
; ============================================================================
;   sort_u64 / sort_i64   - in-place heapsort of 64-bit integers.
;                           O(n log n), no recursion, no extra memory.
;                           NOT stable (irrelevant for plain integers).
;   sort_stable           - in-place insertion sort of arbitrary fixed-size
;                           records with a comparator callback. Stable,
;                           O(n^2): intended for small/near-sorted inputs,
;                           e.g. ordering ELF symbols (locals before globals)
;                           while keeping definition order.
;   bsearch_u64           - binary search in an ascending u64 array.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx
;   callee saved: rbx, r12-r15, rbp

[SECTION .text]

; ----------------------------------------------------------------------------
; HEAPSORT_IMPL name, cc
;   Emits an in-place ascending heapsort over qwords.
;   cc is the condition code meaning "a < b" after `cmp a, b`:
;     b (below) for unsigned, l (less) for signed.
;
; Input    : rdi = pointer to array of qwords
;             rsi = element count
; Output   : none (array sorted in place)
; Clobbers : rax, rcx, rdx, r8, r9, r10, r11
; ----------------------------------------------------------------------------
%macro HEAPSORT_IMPL 2
global %1
%1:
    cmp     rsi, 2
    jb      .done                          ; 0 or 1 element: already sorted

    ; Phase 1: build a max-heap by sifting down every internal node.
    mov     r11, rsi                       ; r11 = heap size = n
    mov     r8, rsi
    shr     r8, 1                          ; r8 = n/2 (one past last parent)
.build:
    dec     r8
    mov     rcx, r8
    call    .sift
    test    r8, r8
    jnz     .build

    ; Phase 2: repeatedly move the max to the end and shrink the heap.
    mov     rax, rsi
.extract:
    dec     rax                            ; rax = last index of the heap
    jz      .done
    mov     r9,  [rdi]
    mov     r10, [rdi + rax*8]
    mov     [rdi], r10
    mov     [rdi + rax*8], r9              ; swap a[0] <-> a[end]
    mov     r11, rax                       ; heap now excludes a[end]
    xor     ecx, ecx
    call    .sift
    jmp     .extract

.done:
    ret

; .sift: sift a[rcx] down within heap a[0 .. r11)
;   Clobbers rcx, rdx, r9, r10
.sift:
    lea     rdx, [rcx*2 + 1]               ; rdx = left child
    cmp     rdx, r11
    jae     .sift_done
    lea     r9, [rdx + 1]                  ; r9 = right child
    cmp     r9, r11
    jae     .have_child
    mov     r10, [rdi + rdx*8]
    cmp     r10, [rdi + r9*8]
    j%+2    .take_right                    ; left < right -> use right
    jmp     .have_child
.take_right:
    mov     rdx, r9
.have_child:
    mov     r9,  [rdi + rcx*8]             ; parent
    mov     r10, [rdi + rdx*8]             ; larger child
    cmp     r9, r10
    j%+2    .swap                          ; parent < child -> swap down
    ret
.swap:
    mov     [rdi + rcx*8], r10
    mov     [rdi + rdx*8], r9
    mov     rcx, rdx
    jmp     .sift
.sift_done:
    ret
%endmacro

; ---- sort_u64 ---------------------------
;
; sort_u64
; Sorts an array of unsigned 64-bit integers ascending, in place.
; Input    : rdi = pointer to array
;             rsi = element count
; Output   : none
; Clobbers : rax, rcx, rdx, r8, r9, r10, r11
;
HEAPSORT_IMPL sort_u64, b

; ---- sort_i64 ---------------------------
;
; sort_i64
; Sorts an array of signed 64-bit integers ascending, in place.
; Input    : rdi = pointer to array
;             rsi = element count
; Output   : none
; Clobbers : rax, rcx, rdx, r8, r9, r10, r11
;
HEAPSORT_IMPL sort_i64, l

; ---- sort_stable ------------------------
;
; sort_stable
; Stable in-place insertion sort of fixed-size records.
; Equal records keep their original relative order.
;   compare(rdi = ptr A, rsi = ptr B) -> rax (signed):
;       < 0 if A sorts before B, 0 if equal, > 0 if A sorts after B
;   The comparator may clobber any caller-saved register.
; Input    : rdi = pointer to first record
;             rsi = record count
;             rdx = record size in bytes (> 0)
;             rcx = compare function
; Output   : rax = EXIT_OK or EXIT_ERROR (NULL base with count > 1,
;              zero record size, or NULL comparator)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11 (plus comparator clobbers)
;
global sort_stable
sort_stable:
    cmp     rsi, 2
    jb      .trivial                       ; nothing to order
    test    rdi, rdi
    jz      .bad_args
    test    rdx, rdx
    jz      .bad_args
    test    rcx, rcx
    jz      .bad_args

    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                         ; 16-byte align for callback

    mov     rbx, rdi                       ; rbx = base
    mov     r12, rsi                       ; r12 = count
    mov     r13, rdx                       ; r13 = record size
    mov     r14, rcx                       ; r14 = compare fn
    mov     r15, 1                         ; r15 = i

.outer:
    cmp     r15, r12
    jae     .finished

    ; rbp = &rec[i]; the record being inserted walks left from here
    mov     rax, r15
    mul     r13
    lea     rbp, [rbx + rax]

.inner:
    cmp     rbp, rbx
    jbe     .next_i                        ; reached index 0

    mov     rdi, rbp
    sub     rdi, r13                       ; A = &rec[j-1]
    mov     rsi, rbp                       ; B = &rec[j]
    call    r14
    test    rax, rax
    jle     .next_i                        ; A <= B: in place (keeps stability)

    ; swap rec[j-1] and rec[j] byte by byte
    mov     rdi, rbp
    sub     rdi, r13
    xor     ecx, ecx
.swap_byte:
    mov     al, [rdi + rcx]
    mov     dl, [rbp + rcx]
    mov     [rdi + rcx], dl
    mov     [rbp + rcx], al
    inc     rcx
    cmp     rcx, r13
    jb      .swap_byte

    sub     rbp, r13                       ; j--
    jmp     .inner

.next_i:
    inc     r15
    jmp     .outer

.finished:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
.trivial:
    xor     eax, eax
    ret

.bad_args:
    mov     eax, EXIT_ERROR
    ret

; ---- bsearch_u64 ------------------------
;
; bsearch_u64
; Binary search for a key in an ascending array of unsigned 64-bit values.
; With duplicates, the index of the FIRST match is returned.
; Input    : rdi = pointer to sorted array
;             rsi = element count
;             rdx = key
; Output   : rax = index of key, or -1 if not present
;              rcx = insertion point (first index with a[i] >= key),
;                    valid whether or not the key was found
; Clobbers : r8, r9
;
global bsearch_u64
bsearch_u64:
    xor     ecx, ecx                       ; lo = 0
    mov     r8, rsi                        ; hi = n   (search [lo, hi))

.loop:
    cmp     rcx, r8
    jae     .settled
    mov     r9, r8
    sub     r9, rcx
    shr     r9, 1
    add     r9, rcx                        ; mid = lo + (hi - lo) / 2
    cmp     [rdi + r9*8], rdx
    jae     .go_left
    lea     rcx, [r9 + 1]                  ; a[mid] < key: lo = mid + 1
    jmp     .loop
.go_left:
    mov     r8, r9                         ; a[mid] >= key: hi = mid
    jmp     .loop

.settled:
    mov     rax, -1
    cmp     rcx, rsi
    jae     .done                          ; key > every element
    cmp     [rdi + rcx*8], rdx
    jne     .done
    mov     rax, rcx
.done:
    ret
