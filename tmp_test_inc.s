%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
global _start
_start:
    mov rax, INCLUDECTX_lexer
    mov rbx, INCLUDECTX_size
