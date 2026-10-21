[SECTION .text]
global _start

_start:
    // sys_write(1, msg, len)
    li      a7, 64
    li      a0, 1
    la      a1, msg
    li      a2, msg_len
    ecall

    // sys_exit(0)
    li      a7, 93
    li      a0, 0
    ecall

[SECTION .data]
msg: db "UtkarshaLab RISC-V Ascent Successful.", 10
msg_len: equ $ - msg
