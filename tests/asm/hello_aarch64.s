[SECTION .text]
global _start

_start:
    // sys_write(1, msg, len)
    mov     x8, 64
    mov     x0, 1
    adr     x1, msg
    mov     x2, msg_len
    svc     0

    // sys_exit(0)
    mov     x8, 93
    mov     x0, 0
    svc     0

[SECTION .data]
msg: db "UtkarshaLab AArch64 Ascent Successful.", 10
msg_len: equ $ - msg
