%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
global _start
_start:
    mov rax, LEXER_SIZE
    mov rbx, LEXER_ctx
    mov rcx, PREP_lexer
    mov rdx, TOKEN_SIZE
