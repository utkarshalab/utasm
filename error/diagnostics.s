;
; ============================================
; File     : src/core/diagnostics.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

[SECTION .data]
    msg_error:   db 0x1B, "[1;31merror: ", 0x1B, "[0m", 0
    msg_warning: db 0x1B, "[1;33mwarning: ", 0x1B, "[0m", 0
    msg_colon:   db ":", 0
    msg_space:   db " ", 0
    msg_caret:   db 0x1B, "[1;32m^", 0x1B, "[0m", 0x0A, 0

[SECTION .text]

;*
; * [diag_error_at]
; * Prints a contextual error message.
; * Input:
; *   rdi = pointer to AsmCtx
; *   rsi = pointer to Token
; *   rdx = message string
; ;
global diag_error_at
diag_error_at:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; rbx = AsmCtx
    mov     r12, rsi               ; r12 = Token
    mov     r13, rdx               ; r13 = Message
    
    inc     word [rbx + ASMCTX_err_count]

    ; 1. Print "file:line:col: error: "
    mov     rsi, [r12 + TOKEN_file]
    test    rsi, rsi
    jnz     .print_file
    lea     rsi, [str_unknown]
.print_file:
    call    .print_str
    
    lea     rsi, [msg_colon]
    call    .print_str
    
    mov     edi, [r12 + TOKEN_line]
    call    .print_int
    
    lea     rsi, [msg_colon]
    call    .print_str
    
    movzx   rdi, word [r12 + TOKEN_col]
    call    .print_int
    
    lea     rsi, [msg_colon]
    call    .print_str
    call    .print_space
    
    lea     rsi, [msg_error]
    call    .print_str
    
    ; 2. Print the message
    mov     rsi, r13
    call    .print_str
    call    .print_nl

    ; 3. Print the source line (if available)
    ; For now, we skip the line snippet for brevity in this round
    ; and just do the caret positioning if col is known.
    
    movzx   rcx, word [r12 + TOKEN_col]
    test    cx, cx
    jz      .done
    
    dec     cx                     ; 1-based to 0-based
.indent:
    push    rcx
    call    .print_space
    pop     rcx
    loop    .indent
    
    lea     rsi, [msg_caret]
    call    .print_str

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.print_str:
    mov     rdi, STDERR_FILENO
    extern  print_str              ; from main.s
    jmp     print_str

.print_space:
    lea     rsi, [msg_space]
    jmp     .print_str

.print_nl:
    lea     rsi, [str_nl]
    jmp     .print_str

.print_int:
    ; Simple integer to decimal printer
    sub     rsp, 32
    mov     rax, rdi
    mov     rcx, 10
    lea     rsi, [rsp + 31]
    mov     byte [rsi], 0
.int_loop:
    xor     rdx, rdx
    div     rcx
    add     dl, '0'
    dec     rsi
    mov     [rsi], dl
    test    rax, rax
    jnz     .int_loop
    call    .print_str
    add     rsp, 32
    ret

[SECTION .rodata]
str_unknown: db "<unknown>", 0
str_nl:      db 0x0A, 0
