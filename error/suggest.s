;
; ============================================
; File     : error/suggest.s
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
; SUGGESTION ENGINE ("did you mean ...?")
; ============================================================================
; Finds the known name closest to a misspelled one, by edit distance with
; adjacent transpositions (optimal string alignment: insert, delete,
; substitute or swap two neighbouring characters, each cost 1), ignoring
; ASCII case - so "movv", "mvo" and "MOV" all lead to "mov".
;
; Candidates are fed one at a time, so any source works (a packed name
; list, the symbol table, a directive list):
;
;     suggest_begin    input               start a search
;     suggest_consider candidate           repeat for every candidate
;     suggest_result                       rdx = best candidate or 0
;
; A candidate is only accepted if it is close enough to be a plausible
; typo: distance <= max(1, ceil(max(len_input, len_candidate) / 3)).
; Ties keep the earliest candidate, so list order is the tie-breaker.
; Names longer than SUGGEST_MAX_LEN are ignored (never matched).
;
; The search state is a single static record: this runs only on error
; paths, one search at a time.
;
; Calling convention (AMD64):
;   args  : rdi, rsi
;   callee saved: rbx, r12-r15, rbp

%define SUGGEST_MAX_LEN     63          ; longest name compared
%define ROW_BYTES           64          ; one DP row (lengths 0..63)
%define ROWS_FRAME          (3 * ROW_BYTES + 8)   ; 3 rows, rsp kept aligned

[SECTION .bss]
align 8
sg_input:       resq 1                  ; input string (0 = search disabled)
sg_input_len:   resq 1
sg_best:        resq 1                  ; best candidate so far (0 = none)
sg_best_dist:   resq 1

[SECTION .text]

; ---- suggest_distance -------------------
;
; suggest_distance
; Case-insensitive edit distance between two strings, where inserting,
; deleting or substituting a character, or swapping two adjacent
; characters, each cost 1 ("mvo" -> "mov" is 1, not 2).
; Input    : rdi = string A (NUL-terminated)
;             rsi = string B (NUL-terminated)
; Output   : rax = edit distance, or -1 if either string is longer than
;              SUGGEST_MAX_LEN (or NULL)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global suggest_distance
suggest_distance:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, ROWS_FRAME
    mov     rbx, rdi                        ; rbx = A
    mov     r12, rsi                        ; r12 = B

    test    rbx, rbx
    jz      .too_long
    test    r12, r12
    jz      .too_long

    ; r8 = len(A), r9 = len(B), each capped
    xor     r8d, r8d
.len_a:
    cmp     byte [rbx + r8], 0
    je      .len_b_start
    inc     r8
    cmp     r8, SUGGEST_MAX_LEN
    ja      .too_long
    jmp     .len_a
.len_b_start:
    xor     r9d, r9d
.len_b:
    cmp     byte [r12 + r9], 0
    je      .lengths_done
    inc     r9
    cmp     r9, SUGGEST_MAX_LEN
    ja      .too_long
    jmp     .len_b
.lengths_done:

    ; rbp = row i-2, r14 = row i-1, r15 = row i;  row0[j] = j
    lea     rbp, [rsp + 2 * ROW_BYTES]
    mov     r14, rsp
    lea     r15, [rsp + ROW_BYTES]
    xor     ecx, ecx
.init_row:
    mov     [r14 + rcx], cl
    inc     rcx
    cmp     rcx, r9
    jbe     .init_row

    mov     r10d, 1                         ; r10 = i (row, 1-based over A)
.row:
    cmp     r10, r8
    ja      .finished
    mov     [r15], r10b                     ; cur[0] = i
    movzx   r13d, byte [rbx + r10 - 1]      ; r13 = A[i-1], lowercased
    lea     eax, [r13 - 'A']
    cmp     eax, 'Z' - 'A'
    ja      .a_lower
    or      r13d, 0x20
.a_lower:

    mov     ecx, 1                          ; rcx = j (column, 1-based over B)
.cell:
    cmp     rcx, r9
    ja      .row_done
    movzx   r11d, byte [r12 + rcx - 1]      ; r11 = B[j-1], lowercased
    lea     eax, [r11 - 'A']
    cmp     eax, 'Z' - 'A'
    ja      .b_lower
    or      r11d, 0x20
.b_lower:
    ; substitute: prev[j-1] + (A[i-1] != B[j-1])
    movzx   eax, byte [r14 + rcx - 1]
    cmp     r13d, r11d
    je      .same
    inc     eax
.same:
    ; delete: prev[j] + 1
    movzx   edx, byte [r14 + rcx]
    inc     edx
    cmp     edx, eax
    cmovb   eax, edx
    ; insert: cur[j-1] + 1
    movzx   edx, byte [r15 + rcx - 1]
    inc     edx
    cmp     edx, eax
    cmovb   eax, edx
    ; transpose: A[i-2..i-1] == B[j-1..j-2]  ->  row(i-2)[j-2] + 1
    cmp     r10, 2
    jb      .store
    cmp     rcx, 2
    jb      .store
    cmp     r13d, r11d
    je      .store                          ; equal pair: nothing to swap
    movzx   edx, byte [rbx + r10 - 2]       ; A[i-2]
    lea     esi, [rdx - 'A']
    cmp     esi, 'Z' - 'A'
    ja      .a2_lower
    or      edx, 0x20
.a2_lower:
    cmp     edx, r11d                       ; A[i-2] == B[j-1] ?
    jne     .store
    movzx   edx, byte [r12 + rcx - 2]       ; B[j-2]
    lea     esi, [rdx - 'A']
    cmp     esi, 'Z' - 'A'
    ja      .b2_lower
    or      edx, 0x20
.b2_lower:
    cmp     edx, r13d                       ; B[j-2] == A[i-1] ?
    jne     .store
    movzx   edx, byte [rbp + rcx - 2]
    inc     edx
    cmp     edx, eax
    cmovb   eax, edx
.store:
    mov     [r15 + rcx], al
    inc     rcx
    jmp     .cell

.row_done:
    ; rotate rows: i-1 -> i-2, i -> i-1, and reuse the oldest for row i+1
    mov     rax, rbp
    mov     rbp, r14
    mov     r14, r15
    mov     r15, rax
    inc     r10
    jmp     .row

.finished:
    movzx   eax, byte [r14 + r9]            ; distance = prev[len(B)]
    jmp     .ret

.too_long:
    mov     rax, -1
.ret:
    add     rsp, ROWS_FRAME
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- suggest_begin ----------------------
;
; suggest_begin
; Starts a new search for names close to an input string.
; An empty, NULL or over-long input disables the search (no result).
; Input    : rdi = misspelled name (NUL-terminated)
; Output   : none
; Clobbers : rax, rcx
;
global suggest_begin
suggest_begin:
    xor     eax, eax
    mov     [sg_best], rax
    mov     qword [sg_best_dist], -1
    mov     [sg_input], rax
    test    rdi, rdi
    jz      .done

    xor     ecx, ecx
.len:
    cmp     byte [rdi + rcx], 0
    je      .measured
    inc     rcx
    cmp     rcx, SUGGEST_MAX_LEN
    ja      .done                           ; too long: stay disabled
    jmp     .len
.measured:
    test    rcx, rcx
    jz      .done                           ; empty: stay disabled
    mov     [sg_input], rdi
    mov     [sg_input_len], rcx
.done:
    ret

; ---- suggest_consider -------------------
;
; suggest_consider
; Scores one candidate against the current input and keeps it if it is
; the closest plausible match so far.
; Input    : rdi = candidate name (NUL-terminated; NULL is ignored)
; Output   : none
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global suggest_consider
suggest_consider:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi                        ; rbx = candidate
    cmp     qword [sg_input], 0
    je      .done
    test    rbx, rbx
    jz      .done

    mov     rdi, [sg_input]
    mov     rsi, rbx
    call    suggest_distance
    cmp     rax, -1
    je      .done
    mov     r12, rax                        ; r12 = distance

    ; threshold = max(1, ceil(max(len_in, len_cand) / 3))
    xor     ecx, ecx
.cand_len:
    cmp     byte [rbx + rcx], 0
    je      .have_len
    inc     rcx
    jmp     .cand_len                       ; bounded: distance succeeded
.have_len:
    mov     rax, [sg_input_len]
    cmp     rcx, rax
    cmova   rax, rcx
    add     rax, 2
    xor     edx, edx
    mov     ecx, 3
    div     rcx                             ; rax = ceil(max_len / 3)
    test    rax, rax
    jnz     .have_threshold
    mov     eax, 1
.have_threshold:
    cmp     r12, rax
    ja      .done                           ; too different to be a typo
    cmp     r12, [sg_best_dist]
    jae     .done                           ; not better (ties keep the first)
    mov     [sg_best_dist], r12
    mov     [sg_best], rbx
.done:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; ---- suggest_result ---------------------
;
; suggest_result
; Returns the outcome of the current search.
; Input    : none
; Output   : rdx = best candidate (pointer passed to suggest_consider),
;              or 0 if nothing was close enough
;              rax = its distance, or -1 if none
; Clobbers : none
;
global suggest_result
suggest_result:
    mov     rdx, [sg_best]
    mov     rax, [sg_best_dist]
    ret

; ---- suggest_consider_packed ------------
;
; suggest_consider_packed
; Considers every name in a packed, NUL-separated list
; ("mov\0add\0...") that ends at a given address.
; Input    : rdi = first name
;             rsi = end of the list (one past the last NUL)
; Output   : none
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global suggest_consider_packed
suggest_consider_packed:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi                        ; rbx = current name
    mov     r12, rsi                        ; r12 = end
.next:
    cmp     rbx, r12
    jae     .done
    mov     rdi, rbx
    call    suggest_consider
.skip:
    cmp     rbx, r12
    jae     .done
    inc     rbx
    cmp     byte [rbx - 1], 0
    jne     .skip                           ; stop just past the NUL
    jmp     .next
.done:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret
