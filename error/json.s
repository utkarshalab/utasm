;
; ============================================
; File     : error/json.s
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
; DIAGNOSTICS AS JSON (-X json)
; ============================================================================
; Every line utasm writes to stderr becomes one JSON object on stderr, for
; editors and build tools:
;
;   {"severity":"error","file":"a.s","line":3,"column":7,"message":"..."}
;   {"severity":"warning","file":"a.s","line":9,"message":"...",
;    "flag":"-w+label-orphan"}
;   {"severity":"note","file":"a.s","line":2,"message":"from macro `m'
;    defined here"}
;   {"severity":"hint","message":"did you mean 'mov'?"}
;   {"severity":"error","message":"..."}          (no place: "utasm: ...")
;
; Whatever path writes a message (the reports, the held warnings, the
; lexer's own), it goes to stderr: stderr is made a pipe to a child process
; that turns each line into its object (diag_json_start), and the child is
; waited for at the end (diag_json_finish). A pipe is no terminal: no
; colors, no source lines shown (diag_init); ANSI sequences are dropped
; anyway.

%define SYS_READ     0
%define SYS_WRITE    1
%define SYS_CLOSE    3
%define SYS_PIPE     22
%define SYS_DUP2     33
%define SYS_FORK     57
%define SYS_EXIT     60
%define SYS_WAIT4    61

%define IN_CAP       (1 << 16)
%define OUT_CAP      (1 << 18)

[SECTION .rodata]
k_sev:      db '{"severity":"', 0
k_file:     db '","file":"', 0
k_line:     db '","line":', 0
k_line_nf:  db '"', 0
k_column:   db ',"column":', 0
k_message:  db ',"message":"', 0
k_msg_nf:   db '","message":"', 0
k_flag:     db '","flag":"', 0
k_end:      db '"}', 10, 0
w_utasm:    db "utasm: ", 0
w_hint:     db "hint: ", 0
w_error:    db "error: ", 0
w_warning:  db "warning: ", 0
w_fatal:    db "fatal: ", 0
w_note:     db "note: ", 0
w_from:     db "... ", 0
w_flag:     db " [-w", 0
s_error:    db "error", 0
s_warning:  db "warning", 0
s_fatal:    db "fatal", 0
s_note:     db "note", 0
s_hint:     db "hint", 0
hexdig:     db "0123456789abcdef"

[SECTION .bss]
alignb 8
global diag_json
diag_json:      resb 1              ; -X json
alignb 8
json_pid:       resq 1
json_fds:       resd 2
alignb 8
in_buf:         resb IN_CAP
in_len:         resq 1
line_buf:       resb IN_CAP
out_buf:        resb OUT_CAP
out_len:        resq 1
; a line's parts
p_sev:          resq 1
p_file:         resq 1
p_file_len:     resq 1
p_line:         resq 1              ; 0: none
p_col:          resq 1
p_msg:          resq 1
p_msg_len:      resq 1
p_flag:         resq 1
p_flag_len:     resq 1

[SECTION .text]

; ---- diag_json_start ----------------------
;
; diag_json_start
; Under -X json: stderr becomes a pipe to the child that writes the JSON.
; Preserves the callee-saved registers.
;
global diag_json_start
diag_json_start:
    cmp     byte [rel diag_json], 0
    jne     .on
    ret
.on:
    push    rbx
    push    r12
    mov     eax, SYS_PIPE
    lea     rdi, [rel json_fds]
    syscall
    test    rax, rax
    jnz     .off                           ; (no pipe: messages as text)
    mov     eax, SYS_FORK
    syscall
    test    rax, rax
    js      .off_close
    jz      .child
    mov     [rel json_pid], rax
    mov     eax, SYS_DUP2
    mov     edi, [rel json_fds + 4]
    mov     esi, 2
    syscall
    mov     eax, SYS_CLOSE
    mov     edi, [rel json_fds + 4]
    syscall
    mov     eax, SYS_CLOSE
    mov     edi, [rel json_fds]
    syscall
    pop     r12
    pop     rbx
    ret
.child:
    mov     eax, SYS_CLOSE
    mov     edi, [rel json_fds + 4]
    syscall
    mov     r12d, [rel json_fds]
    jmp     json_child
.off_close:
    mov     eax, SYS_CLOSE
    mov     edi, [rel json_fds]
    syscall
    mov     eax, SYS_CLOSE
    mov     edi, [rel json_fds + 4]
    syscall
.off:
    mov     byte [rel diag_json], 0
    pop     r12
    pop     rbx
    ret

; ---- diag_json_finish ---------------------
;
; diag_json_finish
; The last message written: stderr closed, the child waited for (its
; output complete before utasm exits). Preserves rax and the callee-saved.
;
global diag_json_finish
diag_json_finish:
    cmp     qword [rel json_pid], 0
    jne     .on
    ret
.on:
    push    rax
    mov     eax, SYS_CLOSE
    mov     edi, 2
    syscall
    mov     eax, SYS_WAIT4
    mov     rdi, [rel json_pid]
    xor     esi, esi
    xor     edx, edx
    xor     r10d, r10d
    syscall
    mov     qword [rel json_pid], 0
    pop     rax
    ret

; ============================================================================
; THE CHILD
; ============================================================================

; json_child: lines from the pipe r12d, as JSON on stderr, until its end
json_child:
    mov     qword [rel in_len], 0
.read:
    mov     eax, SYS_READ
    mov     edi, r12d
    lea     rsi, [rel in_buf]
    add     rsi, [rel in_len]
    mov     edx, IN_CAP
    sub     rdx, [rel in_len]
    syscall
    cmp     rax, -4                        ; (EINTR)
    je      .read
    test    rax, rax
    jle     .eof
    add     [rel in_len], rax
    ; the whole lines in it
.lines:
    lea     rsi, [rel in_buf]
    mov     rcx, [rel in_len]
    xor     edx, edx
.find_nl:
    cmp     rdx, rcx
    jae     .no_nl
    cmp     byte [rsi + rdx], 10
    je      .have_nl
    inc     rdx
    jmp     .find_nl
.have_nl:
    push    rdx
    mov     rcx, rdx
    call    json_line
    pop     rdx
    ; the rest moved down
    lea     rsi, [rel in_buf]
    lea     rsi, [rsi + rdx + 1]
    lea     rdi, [rel in_buf]
    mov     rcx, [rel in_len]
    sub     rcx, rdx
    dec     rcx
    mov     [rel in_len], rcx
    rep movsb
    jmp     .lines
.no_nl:
    cmp     rcx, IN_CAP
    jb      .read
    ; a line longer than the buffer: as it is
    call    json_line
    mov     qword [rel in_len], 0
    jmp     .read
.eof:
    mov     rcx, [rel in_len]
    test    rcx, rcx
    jz      .done
    lea     rsi, [rel in_buf]
    call    json_line
.done:
    call    json_flush
    mov     eax, SYS_EXIT
    xor     edi, edi
    syscall

; json_line: the line rsi/rcx (no newline) as one object
json_line:
    push    rbx
    push    r12
    push    r13
    ; its text, ANSI sequences and CRs dropped, into line_buf
    lea     rdi, [rel line_buf]
    xor     edx, edx                       ; read
    xor     r8d, r8d                       ; written
.clean:
    cmp     rdx, rcx
    jae     .cleaned
    movzx   eax, byte [rsi + rdx]
    inc     rdx
    cmp     eax, 13
    je      .clean
    cmp     eax, 27
    jne     .keep
    ; ESC [ ... a letter
.esc:
    cmp     rdx, rcx
    jae     .cleaned
    movzx   eax, byte [rsi + rdx]
    inc     rdx
    or      eax, 0x20
    cmp     eax, 'a'
    jb      .esc
    cmp     eax, 'z'
    ja      .esc
    jmp     .clean
.keep:
    mov     [rdi + r8], al
    inc     r8
    jmp     .clean
.cleaned:
    test    r8, r8
    jz      .ret                           ; (an empty line)
    mov     rbx, rdi                       ; the line
    mov     r12, r8                        ; its length
    xor     eax, eax
    mov     [rel p_file], rax
    mov     [rel p_line], rax
    mov     [rel p_col], rax
    mov     [rel p_flag], rax
    lea     rax, [rel s_note]
    mov     [rel p_sev], rax
    mov     r13, rbx                       ; where the message is
    ; "hint: ..."
    lea     rsi, [rel w_hint]
    call    json_starts
    jne     .not_hint
    lea     rax, [rel s_hint]
    mov     [rel p_sev], rax
    add     r13, 6
    jmp     .message
.not_hint:
    ; "utasm: ..." (no place)
    lea     rsi, [rel w_utasm]
    call    json_starts
    jne     .place
    add     r13, 7
    jmp     .severity
.place:
    ; "FILE:LINE: " or "FILE:LINE:COL: "
    xor     ecx, ecx
.colon:
    cmp     rcx, r12
    jae     .message                       ; none: the line as a note
    cmp     byte [rbx + rcx], ':'
    je      .colon_digits
    inc     rcx
    jmp     .colon
.colon_digits:
    lea     rsi, [rbx + rcx + 1]
    call    json_number                    ; rax = it, rdx = digits
    test    rdx, rdx
    jz      .colon_next
    lea     r8, [rsi + rdx]
    lea     r9, [rbx + r12]
    cmp     r8, r9
    jae     .colon_next
    cmp     byte [r8], ':'
    jne     .colon_next
    mov     [rel p_file], rbx
    mov     [rel p_file_len], rcx
    mov     [rel p_line], rax
    lea     r13, [r8 + 1]
    ; a column?
    mov     rsi, r13
    call    json_number
    test    rdx, rdx
    jz      .blank
    lea     r8, [rsi + rdx]
    lea     r9, [rbx + r12]
    cmp     r8, r9
    jae     .blank
    cmp     byte [r8], ':'
    jne     .blank
    mov     [rel p_col], rax
    lea     r13, [r8 + 1]
.blank:
    lea     r9, [rbx + r12]
    cmp     r13, r9
    jae     .severity
    cmp     byte [r13], ' '
    jne     .severity
    inc     r13
    jmp     .severity
.colon_next:
    inc     rcx
    jmp     .colon
.severity:
    lea     rsi, [rel w_error]
    lea     rax, [rel s_error]
    call    json_sev
    je      .message
    lea     rsi, [rel w_warning]
    lea     rax, [rel s_warning]
    call    json_sev
    je      .message
    lea     rsi, [rel w_fatal]
    lea     rax, [rel s_fatal]
    call    json_sev
    je      .message
    lea     rsi, [rel w_note]
    lea     rax, [rel s_note]
    call    json_sev
    je      .message
    lea     rsi, [rel w_from]
    lea     rax, [rel s_note]
    call    json_sev                       ; ("... from macro `m' defined here")
.message:
    lea     rcx, [rbx + r12]
    sub     rcx, r13
    mov     [rel p_msg], r13
    mov     [rel p_msg_len], rcx
    ; " [-w+class]" at the end: the flag
    test    rcx, rcx
    jz      .emit
    cmp     byte [r13 + rcx - 1], ']'
    jne     .emit
    mov     rdx, rcx
.flag_back:
    test    rdx, rdx
    jz      .emit
    dec     rdx
    cmp     byte [r13 + rdx], '['
    jne     .flag_back
    test    rdx, rdx
    jz      .emit
    cmp     byte [r13 + rdx - 1], ' '
    jne     .emit
    cmp     byte [r13 + rdx + 1], '-'
    jne     .emit
    lea     rax, [r13 + rdx + 1]
    mov     [rel p_flag], rax
    mov     rax, rcx
    sub     rax, rdx
    sub     rax, 2
    mov     [rel p_flag_len], rax
    dec     rdx
    mov     [rel p_msg_len], rdx
.emit:
    lea     rsi, [rel k_sev]
    call    json_putz
    mov     rsi, [rel p_sev]
    call    json_putz
    mov     rsi, [rel p_file]
    test    rsi, rsi
    jz      .no_file
    push    rsi
    lea     rsi, [rel k_file]
    call    json_putz
    pop     rsi
    mov     rcx, [rel p_file_len]
    call    json_put_escaped
    lea     rsi, [rel k_line]
    call    json_putz
    mov     rax, [rel p_line]
    call    json_putnum
    cmp     qword [rel p_col], 0
    je      .no_col
    lea     rsi, [rel k_column]
    call    json_putz
    mov     rax, [rel p_col]
    call    json_putnum
.no_col:
    lea     rsi, [rel k_message]
    call    json_putz
    jmp     .text
.no_file:
    lea     rsi, [rel k_msg_nf]
    call    json_putz
.text:
    mov     rsi, [rel p_msg]
    mov     rcx, [rel p_msg_len]
    call    json_put_escaped
    mov     rsi, [rel p_flag]
    test    rsi, rsi
    jz      .closed
    push    rsi
    lea     rsi, [rel k_flag]
    call    json_putz
    pop     rsi
    mov     rcx, [rel p_flag_len]
    call    json_put_escaped
.closed:
    lea     rsi, [rel k_end]
    call    json_putz
    call    json_flush                     ; (each object as it comes)
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; json_starts: does the line (rbx / r12) start with the NUL-terminated rsi?
; ZF
json_starts:
    mov     rdi, rbx
    lea     r9, [rbx + r12]
    jmp     json_at

; json_sev: at r13 the word rsi? then r13 past it, p_sev = rax. ZF
json_sev:
    push    rax
    mov     rdi, r13
    lea     r9, [rbx + r12]
    call    json_at
    pop     rax
    jne     .sv_ret
    mov     [rel p_sev], rax
    mov     rdi, rsi                       ; (json_at: rsi at its NUL)
    mov     r13, r8
    cmp     eax, eax
.sv_ret:
    ret

; json_at: the text at rdi (up to r9) starts with the word rsi? ZF; r8 =
; past it
json_at:
    mov     r8, rdi
.at_next:
    mov     al, [rsi]
    test    al, al
    jz      .at_yes
    cmp     r8, r9
    jae     .at_no
    cmp     al, [r8]
    jne     .at_no
    inc     rsi
    inc     r8
    jmp     .at_next
.at_yes:
    cmp     al, al
    ret
.at_no:
    test    esp, esp
    ret

; json_number: the decimal digits at rsi (up to the line's end): rax = the
; value, rdx = how many
json_number:
    xor     eax, eax
    xor     edx, edx
    lea     r9, [rbx + r12]
.num_next:
    lea     r8, [rsi + rdx]
    cmp     r8, r9
    jae     .num_ret
    movzx   r8d, byte [rsi + rdx]
    sub     r8d, '0'
    cmp     r8d, 9
    ja      .num_ret
    imul    rax, rax, 10
    add     rax, r8
    inc     rdx
    jmp     .num_next
.num_ret:
    ret

; json_putz: the NUL-terminated rsi, as it is
json_putz:
.pz_next:
    mov     al, [rsi]
    test    al, al
    jz      .pz_ret
    call    json_putc
    inc     rsi
    jmp     .pz_next
.pz_ret:
    ret

; json_put_escaped: rsi/rcx as JSON string text
json_put_escaped:
    push    rbx
    mov     rbx, rcx
.pe_next:
    test    rbx, rbx
    jz      .pe_ret
    movzx   eax, byte [rsi]
    inc     rsi
    dec     rbx
    cmp     eax, '"'
    je      .pe_escape
    cmp     eax, '\'
    je      .pe_escape
    cmp     eax, 0x20
    jb      .pe_control
    call    json_putc
    jmp     .pe_next
.pe_escape:
    push    rax
    mov     al, '\'
    call    json_putc
    pop     rax
    call    json_putc
    jmp     .pe_next
.pe_control:
    ; \u00XX
    push    rax
    mov     al, '\'
    call    json_putc
    mov     al, 'u'
    call    json_putc
    mov     al, '0'
    call    json_putc
    call    json_putc
    pop     rax
    push    rax
    shr     eax, 4
    lea     rcx, [rel hexdig]
    mov     al, [rcx + rax]
    call    json_putc
    pop     rax
    and     eax, 15
    lea     rcx, [rel hexdig]
    mov     al, [rcx + rax]
    call    json_putc
    jmp     .pe_next
.pe_ret:
    pop     rbx
    ret

; json_putnum: rax in decimal
json_putnum:
    sub     rsp, 24
    lea     rdi, [rsp + 23]
    xor     ecx, ecx
.pn_digit:
    xor     edx, edx
    mov     r8d, 10
    div     r8
    add     dl, '0'
    mov     [rdi], dl
    dec     rdi
    inc     ecx
    test    rax, rax
    jnz     .pn_digit
.pn_out:
    inc     rdi
    mov     al, [rdi]
    call    json_putc
    dec     ecx
    jnz     .pn_out
    add     rsp, 24
    ret

; json_putc: the byte al into the output (written when full). Preserves
; all but rax's upper bits.
json_putc:
    push    rcx
    push    rdx
    mov     rcx, [rel out_len]
    cmp     rcx, OUT_CAP
    jb      .pc_room
    push    rax
    call    json_flush
    pop     rax
    xor     ecx, ecx
.pc_room:
    lea     rdx, [rel out_buf]
    mov     [rdx + rcx], al
    inc     rcx
    mov     [rel out_len], rcx
    pop     rdx
    pop     rcx
    ret

; json_flush: the output written to stderr. Preserves rbx, r12-r15, rsi,
; rdi.
json_flush:
    push    rsi
    push    rdi
    push    r11
    push    rcx
    lea     rsi, [rel out_buf]
.fl_more:
    mov     rdx, [rel out_len]
    test    rdx, rdx
    jz      .fl_done
    mov     eax, SYS_WRITE
    mov     edi, 2
    syscall
    test    rax, rax
    jle     .fl_done
    add     rsi, rax
    sub     [rel out_len], rax
    jmp     .fl_more
.fl_done:
    mov     qword [rel out_len], 0
    pop     rcx
    pop     r11
    pop     rdi
    pop     rsi
    ret
