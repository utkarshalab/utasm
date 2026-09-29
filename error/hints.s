; Context-specific "did you mean" hints.
bits 64
DEFAULT REL
%include "include/constant.inc"
%include "include/type.inc"
extern suggest_best
[SECTION .text]
global error_hint_mnemonic
error_hint_mnemonic:
    lea rsi, [rel mnemonic_candidates]
    mov edx, 24
    jmp error_hint_from_table
global error_hint_directive
error_hint_directive:
    lea rsi, [rel directive_candidates]
    mov edx, 18
error_hint_from_table:
    push rdi
    call suggest_best
    pop rdi
    test rdx, rdx
    jz .none
    ; stderr: hint: did you mean '<candidate>'?\n
    mov r8, rdx
    mov eax, 1
    mov edi, 2
    lea rsi, [rel prefix]
    mov edx, prefix_len
    syscall
    mov rsi, r8
    xor edx, edx
.len: cmp byte [rsi+rdx], 0
    je .write
    inc rdx
    jmp .len
.write:
    mov eax, 1
    mov edi, 2
    syscall
    mov eax, 1
    mov edi, 2
    lea rsi, [rel suffix]
    mov edx, suffix_len
    syscall
    mov eax, 1
    ret
.none:
    xor eax, eax
    ret

; error_hint_symbol(ctx, unknown) finds the closest already-known symbol.
global error_hint_symbol
error_hint_symbol:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov rbx, [r12 + ASMCTX_symtab]
    mov r14d, [r12 + ASMCTX_symcount]
    xor r8d, r8d
    mov r9, -1
.symbol_loop:
    test r14, r14
    jz .symbol_done
    mov rax, [rbx + SYMBOL_name]
    test rax, rax
    jz .symbol_next
    push rax
    mov rdi, r13
    mov rsi, rsp
    mov edx, 1
    call suggest_best
    add rsp, 8
    test rdx, rdx
    jz .symbol_next
    cmp rax, r9
    jae .symbol_next
    mov r9, rax
    mov r8, rdx
.symbol_next:
    add rbx, SYMBOL_SIZE
    dec r14
    jmp .symbol_loop
.symbol_done:
    test r8, r8
    jz .symbol_none
    push r8
    mov rdi, r13
    mov rsi, rsp
    mov edx, 1
    call error_hint_from_table
    add rsp, 8
    jmp .symbol_ret
.symbol_none:
    xor eax, eax
.symbol_ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
[SECTION .rodata]
prefix: db 'hint: did you mean ', 39
prefix_len equ $-prefix
suffix: db 39, '?', 10
suffix_len equ $-suffix
mnemonic_candidates: dq m_mov,m_add,m_sub,m_cmp,m_test,m_lea,m_push,m_pop,m_call,m_ret,m_jmp,m_je,m_jne,m_jg,m_jl,m_nop,m_inc,m_dec,m_xor,m_and,m_or,m_shl,m_shr,m_imul
m_mov db 'mov',0
m_add db 'add',0
m_sub db 'sub',0
m_cmp db 'cmp',0
m_test db 'test',0
m_lea db 'lea',0
m_push db 'push',0
m_pop db 'pop',0
m_call db 'call',0
m_ret db 'ret',0
m_jmp db 'jmp',0
m_je db 'je',0
m_jne db 'jne',0
m_jg db 'jg',0
m_jl db 'jl',0
m_nop db 'nop',0
m_inc db 'inc',0
m_dec db 'dec',0
m_xor db 'xor',0
m_and db 'and',0
m_or db 'or',0
m_shl db 'shl',0
m_shr db 'shr',0
m_imul db 'imul',0
directive_candidates: dq d_section,d_global,d_extern,d_db,d_dw,d_dd,d_dq,d_resb,d_resw,d_resd,d_resq,d_align,d_equ,d_times,d_bits,d_default,d_common,d_weak
d_section db 'section',0
d_global db 'global',0
d_extern db 'extern',0
d_db db 'db',0
d_dw db 'dw',0
d_dd db 'dd',0
d_dq db 'dq',0
d_resb db 'resb',0
d_resw db 'resw',0
d_resd db 'resd',0
d_resq db 'resq',0
d_align db 'align',0
d_equ db 'equ',0
d_times db 'times',0
d_bits db 'bits',0
d_default db 'default',0
d_common db 'common',0
d_weak db 'weak',0
