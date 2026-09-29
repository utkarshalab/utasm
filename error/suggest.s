; Levenshtein suggestion scoring for short assembler identifiers.
bits 64
DEFAULT REL

[SECTION .text]
; suggest_best(input, candidates, count) -> rax=distance, rdx=best candidate
; candidates is an array of NUL-terminated string pointers. Inputs longer
; than 63 bytes are ignored to keep the bounded stack workspace small.
global suggest_best
suggest_best:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 136                    ; two 64-byte rows, aligned
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ecx, ecx
.in_len:
    cmp byte [r12+rcx], 0
    je .len_ok
    inc rcx
    cmp rcx, 63
    jbe .in_len
    jmp .none
.len_ok:
    mov r15, rcx                    ; input length
    mov rbx, -1                      ; best distance
    xor edx, edx                     ; best pointer
.candidate:
    test r14, r14
    jz .finish
    mov rdi, [r13]
    add r13, 8
    dec r14
    xor r8d, r8d
.cand_len:
    cmp byte [rdi+r8], 0
    je .score
    inc r8
    cmp r8, 63
    jbe .cand_len
    jmp .candidate
.score:
    ; prev = rsp, curr = rsp+64; prev[j] = j
    xor ecx, ecx
.init:
    mov [rsp+rcx], cl
    inc rcx
    cmp rcx, r8
    jbe .init
    mov r9, 1                        ; i
.row:
    cmp r9, r15
    ja .distance
    mov [rsp+64], r9b
    movzx r10d, byte [r12+r9-1]
    mov rcx, 1                       ; j
.cell:
    cmp rcx, r8
    ja .swap
    movzx eax, byte [rsp+rcx]
    inc eax                          ; delete
    movzx esi, byte [rsp+63+rcx]
    inc esi                          ; insert
    cmp esi, eax
    cmovb eax, esi
    movzx esi, byte [rsp+rcx-1]
    xor edx, edx
    cmp r10b, [rdi+rcx-1]
    sete dl
    add esi, edx                     ; substitute
    cmp esi, eax
    cmovb eax, esi
    mov [rsp+64+rcx], al
    inc rcx
    jmp .cell
.swap:
    xor ecx, ecx
.copy:
    mov al, [rsp+64+rcx]
    mov [rsp+rcx], al
    inc rcx
    cmp rcx, r8
    jbe .copy
    inc r9
    jmp .row
.distance:
    movzx eax, byte [rsp+r8]
    ; threshold = max(1, ceil(max(input,candidate)/3))
    mov rcx, r15
    cmp r8, rcx
    cmova rcx, r8
    add rcx, 2
    xor edx, edx
    mov esi, 3
    mov r11, rax
    mov rax, rcx
    div rsi
    test rax, rax
    jnz .threshold
    mov eax, 1
.threshold:
    cmp r11, rax
    ja .candidate
    cmp r11, rbx
    jae .candidate
    mov rbx, r11
    mov rdx, rdi
    jmp .candidate
.finish:
    mov rax, rbx
    jmp .done
.none:
    mov rax, -1
    xor edx, edx
.done:
    add rsp, 136
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
