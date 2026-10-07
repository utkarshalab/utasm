;
; ============================================
; File     : core/crash.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"

DEFAULT REL

; ============================================================================
; A FATAL SIGNAL IS AN INTERNAL ERROR
; ============================================================================
; A fault in utasm itself (SIGSEGV, SIGBUS, SIGFPE, SIGILL) is reported as
; one, at the statement being read, as NASM reports a panic:
;
;     prog.s:12: fatal: internal error: segmentation fault at 0x41c2a7
;                (please report it)
;
; and utasm exits with EXIT_SIGNAL - not a core dump of its address space
; (gigabytes reserved for the arena: WSL's crash handler writes them out).
; The handler runs on a stack of its own, so a stack overflow is caught too,
; and uses write and exit_group only (all that is safe in a signal handler).

%define SYS_RT_SIGACTION    13
%define SYS_RT_SIGRETURN    15
%define SYS_SIGALTSTACK     131
%define SYS_EXIT_GROUP      231
%define SA_SIGINFO          0x00000004
%define SA_ONSTACK          0x08000000
%define SA_RESTORER         0x04000000
%define SA_RESETHAND        0x80000000  ; a fault in the handler ends it
%define ALT_STACK_SIZE      65536
%define UC_RIP              168         ; ucontext_t: uc_mcontext.gregs[REG_RIP]

extern  error_loc_file
extern  warn_flush
extern  error_loc_line

[SECTION .bss]
alignb 16
crash_stack:    resb ALT_STACK_SIZE
crash_buf:      resb 32                 ; a number's digits

[SECTION .data]
align 8
; struct sigaction as the kernel takes it: handler, flags, restorer, mask
crash_action:   dq crash_handler
                dq SA_SIGINFO | SA_ONSTACK | SA_RESTORER | SA_RESETHAND
                dq crash_restorer
                dq 0
; stack_t: ss_sp, ss_flags, ss_size
crash_altstack: dq crash_stack
                dd 0, 0
                dq ALT_STACK_SIZE

[SECTION .rodata]
crash_signals:  db 4, "illegal instruction", 0
                db 7, "bus error", 0
                db 8, "arithmetic exception", 0
                db 11, "segmentation fault", 0
                db 0
crash_other:    db "fatal signal", 0
s_colon:        db ":", 0
s_fatal:        db ": fatal: internal error: ", 0
s_utasm:        db "utasm: fatal: internal error: ", 0
s_at:           db " at 0x", 0
s_report:       db " (please report it)", 10, 0

[SECTION .text]

;*
; * [crash_install]
; * Purpose: The handler for SIGILL, SIGBUS, SIGFPE and SIGSEGV, on an
; *   alternate stack. Called first thing at start.
; * Clobbers: rax, rcx, rdx, rsi, rdi, r8-r11
; ;
global crash_install
crash_install:
    lea     rdi, [rel crash_altstack]
    xor     esi, esi
    mov     eax, SYS_SIGALTSTACK
    syscall
    lea     rcx, [rel crash_signals]
.next:
    movzx   edi, byte [rcx]
    test    edi, edi
    jz      .done
    push    rcx
    lea     rsi, [rel crash_action]
    xor     edx, edx                       ; the old action: not wanted
    mov     r10d, 8                        ; sizeof(sigset_t)
    mov     eax, SYS_RT_SIGACTION
    syscall
    pop     rcx
.skip_name:
    inc     rcx
    cmp     byte [rcx], 0
    jne     .skip_name
    inc     rcx                            ; past the NUL
    jmp     .next
.done:
    ret

; the kernel returns from a handler through this (x86-64 requires one);
; crash_handler never returns, so it is never used
crash_restorer:
    mov     eax, SYS_RT_SIGRETURN
    syscall

; ---- crash_handler -------------------------
; rdi = the signal, rsi = siginfo, rdx = ucontext
crash_handler:
    mov     r12d, edi
    mov     r13, rdx
    call    warn_flush                     ; the warnings held before it
    ; "file:line: fatal: internal error: " - or "utasm: ..." before any
    ; statement was read
    mov     rsi, [rel error_loc_file]
    test    rsi, rsi
    jz      .no_place
    call    .write
    lea     rsi, [rel s_colon]
    call    .write
    mov     eax, [rel error_loc_line]
    call    .decimal
    lea     rsi, [rel s_fatal]
    call    .write
    jmp     .what
.no_place:
    lea     rsi, [rel s_utasm]
    call    .write
.what:
    ; the signal's name
    lea     rsi, [rel crash_signals]
.find:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .unnamed
    inc     rsi
    cmp     eax, r12d
    je      .named
.skip:
    inc     rsi
    cmp     byte [rsi - 1], 0
    jne     .skip
    jmp     .find
.unnamed:
    lea     rsi, [rel crash_other]
.named:
    call    .write
    ; where
    lea     rsi, [rel s_at]
    call    .write
    mov     rax, [r13 + UC_RIP]
    call    .hex
    lea     rsi, [rel s_report]
    call    .write
    mov     edi, EXIT_SIGNAL
    mov     eax, SYS_EXIT_GROUP
    syscall

; .write: the NUL-terminated text at rsi on stderr
.write:
    mov     rdx, rsi
.len:
    cmp     byte [rdx], 0
    je      .len_done
    inc     rdx
    jmp     .len
.len_done:
    sub     rdx, rsi
    mov     edi, 2
    mov     eax, 1                         ; write
    syscall
    ret

; .decimal: eax in decimal on stderr
.decimal:
    lea     rsi, [rel crash_buf + 31]
    mov     byte [rsi], 0
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rsi
    mov     [rsi], dl
    test    eax, eax
    jnz     .digit
    jmp     .write

; .hex: rax in hexadecimal on stderr
.hex:
    lea     rsi, [rel crash_buf + 31]
    mov     byte [rsi], 0
.nibble:
    mov     edx, eax
    and     edx, 15
    cmp     edx, 10
    jb      .dec_digit
    add     edx, 'a' - 10 - '0'
.dec_digit:
    add     edx, '0'
    dec     rsi
    mov     [rsi], dl
    shr     rax, 4
    jnz     .nibble
    jmp     .write
