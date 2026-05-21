[SECTION .text]
global _start

_start:
    // sys_write(1, msg, len)
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg]
    mov     rdx, msg_len
    syscall

    // sys_exit(0)
    mov     rax, 60
    xor     rdi, rdi
    syscall

[SECTION .data]
msg: db "UtkarshaLab AMD64 Ascent Successful.", 10
msg_len: equ $ - msg
