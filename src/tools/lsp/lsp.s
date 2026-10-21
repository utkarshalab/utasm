;
; ============================================
; File     : src/tools/lsp/lsp.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

DEFAULT REL

; ============================================================================
; A LANGUAGE SERVER (utasm --lsp)
; ============================================================================
; The Language Server Protocol over stdin / stdout (JSON-RPC, each message
; after its "Content-Length: N" header), for an editor's diagnostics as
; one types:
;
;   initialize                   the capabilities: the whole document sent
;                                on each change (textDocumentSync 1)
;   textDocument/didOpen         the document assembled, its messages
;   textDocument/didChange       published (textDocument/publishDiagnostics)
;   textDocument/didSave
;   textDocument/didClose        its messages cleared
;   shutdown, exit
;
; Each document is assembled by utasm itself, run anew (/proc/self/exe -X
; json -f elf64 -I <its directory> -o /dev/null), on a copy of its text in
; /tmp (the editor's text, saved or not): every message as JSON (src/diag/
; json.s), its line and column made the diagnostic's range (0-based), its
; severity an error (1), a warning (2), a note (3). A request it does not
; know is answered "method not found".

%define SYS_READ     0
%define SYS_WRITE    1
%define SYS_OPEN     2
%define SYS_CLOSE    3
%define SYS_PIPE     22
%define SYS_DUP2     33
%define SYS_GETPID   39
%define SYS_FORK     57
%define SYS_EXECVE   59
%define SYS_EXIT     60
%define SYS_WAIT4    61
%define SYS_UNLINK   87

%define IN_CAP       (1 << 27)
%define TEXT_CAP     (1 << 27)
%define OUT_CAP      (1 << 26)
%define ERR_CAP      (1 << 24)

extern  mem_reserve
extern  utasm_envp

[SECTION .rodata]
k_length:   db "content-length:", 0
k_method:   db '"method"', 0
k_id:       db '"id"', 0
k_uri:      db '"uri"', 0
k_text:     db '"text"', 0
k_changes:  db '"contentChanges"', 0
m_init:     db "initialize", 0
m_open:     db "textDocument/didOpen", 0
m_change:   db "textDocument/didChange", 0
m_save:     db "textDocument/didSave", 0
m_close:    db "textDocument/didClose", 0
m_shutdown: db "shutdown", 0
m_exit:     db "exit", 0
r_head:     db '{"jsonrpc":"2.0","id":', 0
r_init:     db ',"result":{"capabilities":{"textDocumentSync":1},"serverInfo":{"name":"utasm"}}}', 0
r_null:     db ',"result":null}', 0
r_unknown:  db ',"error":{"code":-32601,"message":"method not found"}}', 0
p_head:     db '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"', 0
p_diags:    db '","diagnostics":[', 0
p_tail:     db ']}}', 0
d_range:    db '{"range":{"start":{"line":', 0
d_char:     db ',"character":', 0
d_end:      db '},"end":{"line":', 0
d_endchar:  db ',"character":10000}},"severity":', 0
d_source:   db ',"source":"utasm","message":"', 0
d_close:    db '"}', 0
h_length:   db "Content-Length: ", 0
h_end:      db 13, 10, 13, 10, 0
j_file:     db '"file":"', 0
j_line:     db '"line":', 0
j_column:   db '"column":', 0
j_severity: db '"severity":"', 0
j_message:  db '"message":"', 0
s_error:    db "error", 0
s_fatal:    db "fatal", 0
s_warning:  db "warning", 0
s_file:     db "file://", 0
s_tmp:      db "/tmp/utasm-lsp-", 0
s_tmp_ext:  db ".s", 0
s_self:     db "/proc/self/exe", 0
a_utasm:    db "utasm", 0
a_x:        db "-X", 0
a_json:     db "json", 0
a_f:        db "-f", 0
a_elf64:    db "elf64", 0
a_i:        db "-I", 0
a_o:        db "-o", 0
a_null:     db "/dev/null", 0

[SECTION .bss]
alignb 8
in_buf:         resq 1
in_len:         resq 1
text_buf:       resq 1
out_buf:        resq 1
out_len:        resq 1
err_buf:        resq 1
err_len:        resq 1
body:           resq 1              ; the message being handled
body_len:       resq 1
tmp_path:       resb 64
doc_path:       resb 4096           ; the document's file (its directory: -I)
doc_dir:        resb 4096
uri_buf:        resb 4096
id_buf:         resb 128
id_len:         resq 1
exit_status:    resq 1
fds:            resd 2
argv:           resq 16

[SECTION .text]

; ---- lsp_main -----------------------------
;
; lsp_main
; utasm --lsp: the server, until "exit" or the end of stdin. Does not
; return.
;
global lsp_main
lsp_main:
    and     rsp, -16
    mov     rsi, IN_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .fail
    mov     [rel in_buf], rdx
    mov     rsi, TEXT_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .fail
    mov     [rel text_buf], rdx
    mov     rsi, OUT_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .fail
    mov     [rel out_buf], rdx
    mov     rsi, ERR_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .fail
    mov     [rel err_buf], rdx
    call    lsp_tmp_name
    mov     qword [rel in_len], 0
.message:
    call    lsp_read_message               ; body / body_len
    test    rax, rax
    jnz     .eof
    call    lsp_handle
    jmp     .message
.eof:
    mov     rdi, [rel exit_status]
    jmp     lsp_exit
.fail:
    mov     edi, 1
lsp_exit:
    push    rdi
    mov     eax, SYS_UNLINK
    lea     rdi, [rel tmp_path]
    syscall
    pop     rdi
    mov     eax, SYS_EXIT
    syscall

; lsp_tmp_name: tmp_path = /tmp/utasm-lsp-PID.s
lsp_tmp_name:
    lea     rdi, [rel tmp_path]
    lea     rsi, [rel s_tmp]
    call    l_cpy
    push    rdi
    mov     eax, SYS_GETPID
    syscall
    pop     rdi
    call    l_num
    lea     rsi, [rel s_tmp_ext]
    call    l_cpy
    mov     byte [rdi], 0
    ret

; l_cpy: the NUL-terminated rsi at rdi (rdi past it, no NUL written)
l_cpy:
    mov     al, [rsi]
    test    al, al
    jz      .c_ret
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     l_cpy
.c_ret:
    ret

; l_num: rax in decimal at rdi (rdi past it)
l_num:
    sub     rsp, 32
    lea     rsi, [rsp + 31]
    xor     ecx, ecx
.n_dig:
    xor     edx, edx
    mov     r8d, 10
    div     r8
    add     dl, '0'
    mov     [rsi], dl
    dec     rsi
    inc     ecx
    test    rax, rax
    jnz     .n_dig
.n_out:
    inc     rsi
    mov     al, [rsi]
    mov     [rdi], al
    inc     rdi
    dec     ecx
    jnz     .n_out
    add     rsp, 32
    ret

; ============================================================================
; READING
; ============================================================================

; lsp_read_message: the next message's body (body / body_len), the input
; read as far as needed. Output rax = OK, or 1 at the end of the input
lsp_read_message:
    push    r12
    push    r13
    ; the message handed out before: dropped
    mov     r9, [rel pending_cut]
    test    r9, r9
    jz      .parse
    call    l_cut
    mov     qword [rel pending_cut], 0
.parse:
    ; the header's end
    mov     r12, [rel in_buf]
    mov     r13, [rel in_len]
    xor     ecx, ecx
.h_find:
    lea     rax, [rcx + 3]
    cmp     rax, r13
    jae     .more
    cmp     dword [r12 + rcx], 0x0A0D0A0D  ; \r\n\r\n
    je      .h_end
    inc     rcx
    jmp     .h_find
.h_end:
    lea     r8, [rcx + 4]                  ; the body's start
    ; Content-Length (any case) in [0, rcx)
    xor     edx, edx
.l_find:
    cmp     rdx, rcx
    jae     .no_length
    lea     rsi, [rel k_length]
    lea     rdi, [r12 + rdx]
    call    l_prefix_ci
    je      .l_found
    inc     rdx
    jmp     .l_find
.l_found:
    lea     rdi, [r12 + rdx + 15]
    xor     eax, eax
.l_blank:
    cmp     byte [rdi], ' '
    jne     .l_digit
    inc     rdi
    jmp     .l_blank
.l_digit:
    movzx   r9d, byte [rdi]
    sub     r9d, '0'
    cmp     r9d, 9
    ja      .l_have
    imul    rax, rax, 10
    add     rax, r9
    inc     rdi
    jmp     .l_digit
.l_have:
    ; the whole body there?
    lea     r9, [r8 + rax]
    cmp     r9, r13
    ja      .more
    lea     rdi, [r12 + r8]
    mov     [rel body], rdi
    mov     [rel body_len], rax
    ; (dropped at the next call, once it is handled)
    mov     [rel pending_cut], r9
    xor     eax, eax
    pop     r13
    pop     r12
    ret
.no_length:
    ; a header with no length: dropped
    lea     r9, [rcx + 4]
    call    l_cut
    jmp     .parse
.more:
.read:
    mov     rsi, [rel in_buf]
    add     rsi, [rel in_len]
    mov     rdx, IN_CAP
    sub     rdx, [rel in_len]
    jz      .eof                           ; (a message larger than all)
    xor     edi, edi
    mov     eax, SYS_READ
    syscall
    cmp     rax, -4
    je      .read
    test    rax, rax
    jle     .eof
    add     [rel in_len], rax
    jmp     .parse
.eof:
    mov     eax, 1
    pop     r13
    pop     r12
    ret

; l_cut: the first r9 bytes of the input dropped
l_cut:
    push    rsi
    push    rdi
    push    rcx
    mov     rdi, [rel in_buf]
    lea     rsi, [rdi + r9]
    mov     rcx, [rel in_len]
    sub     rcx, r9
    mov     [rel in_len], rcx
    rep movsb
    pop     rcx
    pop     rdi
    pop     rsi
    ret

; l_prefix_ci: does rdi start with the lower-case rsi (any case)? ZF
l_prefix_ci:
.p_next:
    mov     al, [rsi]
    test    al, al
    jz      .p_yes
    mov     ah, [rdi]
    cmp     ah, 'A'
    jb      .p_cmp
    cmp     ah, 'Z'
    ja      .p_cmp
    or      ah, 0x20
.p_cmp:
    cmp     al, ah
    jne     .p_ret
    inc     rsi
    inc     rdi
    jmp     .p_next
.p_yes:
    cmp     al, al
.p_ret:
    ret

; ---- JSON ---------------------------------

; j_key: the value after key rsi ("name", with its quotes) in the body
; from rdi: rax = its first character (past blanks), 0 when there is none.
; A key inside a string is escaped there (\"): not found.
j_key:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, [rel body]
    add     r13, [rel body_len]            ; the end
.k_next:
    cmp     rdi, r13
    jae     .k_none
    push    rdi
    mov     rsi, r12
.k_cmp:
    mov     al, [rsi]
    test    al, al
    jz      .k_match
    cmp     rdi, r13
    jae     .k_fail
    cmp     al, [rdi]
    jne     .k_fail
    inc     rsi
    inc     rdi
    jmp     .k_cmp
.k_fail:
    pop     rdi
    inc     rdi
    jmp     .k_next
.k_match:
    pop     rax
    ; not escaped (a \" before the key)
    cmp     rax, [rel body]
    jbe     .k_colon
    cmp     byte [rax - 1], '\'
    jne     .k_colon
    lea     rdi, [rax + 1]
    jmp     .k_next
.k_colon:
    ; blanks, ':', blanks
.k_blank1:
    cmp     rdi, r13
    jae     .k_none
    cmp     byte [rdi], ' '
    jne     .k_col
    inc     rdi
    jmp     .k_blank1
.k_col:
    cmp     byte [rdi], ':'
    jne     .k_next
    inc     rdi
.k_blank2:
    cmp     rdi, r13
    jae     .k_none
    movzx   eax, byte [rdi]
    cmp     eax, ' '
    je      .k_skip
    cmp     eax, 9
    je      .k_skip
    cmp     eax, 10
    je      .k_skip
    cmp     eax, 13
    jne     .k_have
.k_skip:
    inc     rdi
    jmp     .k_blank2
.k_have:
    mov     rax, rdi
    pop     r13
    pop     r12
    ret
.k_none:
    xor     eax, eax
    pop     r13
    pop     r12
    ret

; j_string: the JSON string at rsi (its opening quote) decoded into rdi
; (UTF-8, NUL-terminated, at most rdx bytes): rax = its length, -1 when
; it is no string
j_string:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rdi + rdx - 5]           ; (room for a character and NUL)
    cmp     byte [rsi], '"'
    jne     .s_bad
    inc     rsi
    mov     r8, [rel body]
    add     r8, [rel body_len]
.s_next:
    cmp     rsi, r8
    jae     .s_end
    cmp     rdi, r13
    jae     .s_end
    movzx   eax, byte [rsi]
    inc     rsi
    cmp     eax, '"'
    je      .s_end
    cmp     eax, '\'
    jne     .s_put
    movzx   eax, byte [rsi]
    inc     rsi
    cmp     eax, 'n'
    mov     ecx, 10
    je      .s_esc
    cmp     eax, 't'
    mov     ecx, 9
    je      .s_esc
    cmp     eax, 'r'
    mov     ecx, 13
    je      .s_esc
    cmp     eax, 'b'
    mov     ecx, 8
    je      .s_esc
    cmp     eax, 'f'
    mov     ecx, 12
    je      .s_esc
    cmp     eax, 'u'
    je      .s_unicode
    mov     ecx, eax                       ; \" \\ \/
.s_esc:
    mov     [rdi], cl
    inc     rdi
    jmp     .s_next
.s_put:
    mov     [rdi], al
    inc     rdi
    jmp     .s_next
.s_unicode:
    call    .hex4
    ; a surrogate pair
    cmp     eax, 0xD800
    jb      .s_utf8
    cmp     eax, 0xDBFF
    ja      .s_utf8
    cmp     byte [rsi], '\'
    jne     .s_utf8
    cmp     byte [rsi + 1], 'u'
    jne     .s_utf8
    push    rax
    add     rsi, 2
    call    .hex4
    pop     rcx
    sub     ecx, 0xD800
    shl     ecx, 10
    sub     eax, 0xDC00
    add     eax, ecx
    add     eax, 0x10000
.s_utf8:
    cmp     eax, 0x80
    jae     .s_u2
    mov     [rdi], al
    inc     rdi
    jmp     .s_next
.s_u2:
    cmp     eax, 0x800
    jae     .s_u3
    mov     ecx, eax
    shr     ecx, 6
    or      cl, 0xC0
    mov     [rdi], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 1], al
    add     rdi, 2
    jmp     .s_next
.s_u3:
    cmp     eax, 0x10000
    jae     .s_u4
    mov     ecx, eax
    shr     ecx, 12
    or      cl, 0xE0
    mov     [rdi], cl
    mov     ecx, eax
    shr     ecx, 6
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 1], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 2], al
    add     rdi, 3
    jmp     .s_next
.s_u4:
    mov     ecx, eax
    shr     ecx, 18
    or      cl, 0xF0
    mov     [rdi], cl
    mov     ecx, eax
    shr     ecx, 12
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 1], cl
    mov     ecx, eax
    shr     ecx, 6
    and     cl, 0x3F
    or      cl, 0x80
    mov     [rdi + 2], cl
    and     al, 0x3F
    or      al, 0x80
    mov     [rdi + 3], al
    add     rdi, 4
    jmp     .s_next
.s_end:
    mov     byte [rdi], 0
    mov     rax, rdi
    sub     rax, r12
    pop     r13
    pop     r12
    ret
.s_bad:
    mov     rax, -1
    pop     r13
    pop     r12
    ret
; .hex4: four hex digits at rsi: eax (rsi past them)
.hex4:
    xor     eax, eax
    mov     ecx, 4
.h_dig:
    movzx   edx, byte [rsi]
    inc     rsi
    shl     eax, 4
    cmp     edx, '9'
    ja      .h_letter
    sub     edx, '0'
    jmp     .h_add
.h_letter:
    or      edx, 0x20
    sub     edx, 'a' - 10
.h_add:
    and     edx, 15
    or      eax, edx
    dec     ecx
    jnz     .h_dig
    ret

; ============================================================================
; HANDLING
; ============================================================================

lsp_handle:
    push    r12
    ; the method
    mov     rdi, [rel body]
    lea     rsi, [rel k_method]
    call    j_key
    test    rax, rax
    jz      .response                      ; (a response from the client)
    mov     rsi, rax
    sub     rsp, 128
    mov     rdi, rsp
    mov     edx, 120
    call    j_string
    ; the id (raw), when there is one
    mov     qword [rel id_len], 0
    mov     rdi, [rel body]
    lea     rsi, [rel k_id]
    call    j_key
    test    rax, rax
    jz      .no_id
    call    l_id
.no_id:
    mov     r12, rsp
    lea     rsi, [rel m_init]
    call    .is
    je      .initialize
    lea     rsi, [rel m_open]
    call    .is
    je      .check
    lea     rsi, [rel m_change]
    call    .is
    je      .check
    lea     rsi, [rel m_save]
    call    .is
    je      .saved
    lea     rsi, [rel m_close]
    call    .is
    je      .close
    lea     rsi, [rel m_shutdown]
    call    .is
    je      .shutdown
    lea     rsi, [rel m_exit]
    call    .is
    je      .exit
    ; anything else: a request answered "not found", a notification taken
    cmp     qword [rel id_len], 0
    je      .done
    lea     rsi, [rel r_unknown]
    call    l_reply
    jmp     .done
.is:
    mov     rdi, r12
.is_next:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .is_ret
    test    al, al
    jz      .is_ret
    inc     rdi
    inc     rsi
    jmp     .is_next
.is_ret:
    ret
.initialize:
    lea     rsi, [rel r_init]
    call    l_reply
    jmp     .done
.shutdown:
    lea     rsi, [rel r_null]
    call    l_reply
    jmp     .done
.exit:
    add     rsp, 128
    pop     r12
    xor     edi, edi
    jmp     lsp_exit
.check:
    ; the text: didOpen's textDocument.text, didChange's contentChanges[0].text
    mov     rdi, [rel body]
    lea     rsi, [rel k_changes]
    call    j_key
    mov     rdi, rax
    test    rax, rax
    jnz     .text_from
    mov     rdi, [rel body]
.text_from:
    lea     rsi, [rel k_text]
    call    j_key
    test    rax, rax
    jz      .done
    mov     rsi, rax
    mov     rdi, [rel text_buf]
    mov     rdx, TEXT_CAP
    call    j_string
    test    rax, rax
    js      .done
    mov     r12, rax                       ; its length
    call    l_uri
    test    rax, rax
    jnz     .done
    call    l_write_tmp
    call    l_assemble
    call    l_publish
    jmp     .done
.saved:
    ; (the text was sent with each change: nothing new)
    jmp     .done
.close:
    call    l_uri
    test    rax, rax
    jnz     .done
    mov     qword [rel err_len], 0
    call    l_publish
.done:
    add     rsp, 128
    pop     r12
    ret
.response:
    pop     r12
    ret

; l_id: the id's raw text at rax (a number or a string) into id_buf
l_id:
    lea     rdi, [rel id_buf]
    xor     ecx, ecx
    cmp     byte [rax], '"'
    jne     .i_num
    ; a string: to its closing quote, the quotes kept
    mov     dl, '"'
    mov     [rdi], dl
    inc     ecx
    inc     rax
.i_str:
    cmp     ecx, 120
    jae     .i_done
    mov     dl, [rax]
    mov     [rdi + rcx], dl
    inc     ecx
    inc     rax
    cmp     dl, '"'
    jne     .i_str
    jmp     .i_done
.i_num:
    cmp     ecx, 120
    jae     .i_done
    mov     dl, [rax]
    cmp     dl, ','
    je      .i_done
    cmp     dl, '}'
    je      .i_done
    cmp     dl, ' '
    je      .i_done
    mov     [rdi + rcx], dl
    inc     ecx
    inc     rax
    jmp     .i_num
.i_done:
    mov     [rel id_len], rcx
    ret

; l_uri: the document's uri (uri_buf, as written) and its file's path and
; directory (doc_path, doc_dir). Output rax = OK, or 1 (none, or not a
; file: uri)
l_uri:
    mov     rdi, [rel body]
    lea     rsi, [rel k_uri]
    call    j_key
    test    rax, rax
    jz      .u_none
    ; as written (escaped), for the reply
    cmp     byte [rax], '"'
    jne     .u_none
    lea     rsi, [rax + 1]
    lea     rdi, [rel uri_buf]
    xor     ecx, ecx
.u_raw:
    cmp     ecx, 4090
    jae     .u_none
    mov     dl, [rsi + rcx]
    cmp     dl, '"'
    je      .u_raw_end
    cmp     dl, '\'
    jne     .u_raw_put
    mov     [rdi + rcx], dl
    inc     ecx
    mov     dl, [rsi + rcx]
.u_raw_put:
    mov     [rdi + rcx], dl
    inc     ecx
    jmp     .u_raw
.u_raw_end:
    mov     byte [rdi + rcx], 0
    ; the path: file:// off, %XX decoded
    lea     rsi, [rel uri_buf]
    lea     rdi, [rel s_file]
.u_prefix:
    mov     al, [rdi]
    test    al, al
    jz      .u_path
    cmp     al, [rsi]
    jne     .u_none
    inc     rsi
    inc     rdi
    jmp     .u_prefix
.u_path:
    lea     rdi, [rel doc_path]
.u_char:
    mov     al, [rsi]
    test    al, al
    jz      .u_end
    cmp     al, '%'
    jne     .u_put
    movzx   eax, byte [rsi + 1]
    call    .u_hex
    mov     ecx, eax
    shl     ecx, 4
    movzx   eax, byte [rsi + 2]
    call    .u_hex
    or      eax, ecx
    add     rsi, 2
.u_put:
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .u_char
.u_end:
    mov     byte [rdi], 0
    ; its directory: up to the last '/'
    lea     rsi, [rel doc_path]
    lea     rdi, [rel doc_dir]
    xor     ecx, ecx
    xor     edx, edx                       ; the last '/'
.u_dir:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    jz      .u_dir_end
    cmp     al, '/'
    jne     .u_dir_next
    mov     rdx, rcx
.u_dir_next:
    inc     rcx
    jmp     .u_dir
.u_dir_end:
    mov     byte [rdi + rdx], 0
    test    rdx, rdx
    jnz     .u_ok
    mov     word [rdi], '/'
.u_ok:
    xor     eax, eax
    ret
.u_none:
    mov     eax, 1
    ret
.u_hex:
    cmp     eax, '9'
    ja      .uh_letter
    sub     eax, '0'
    jmp     .uh_ret
.uh_letter:
    or      eax, 0x20
    sub     eax, 'a' - 10
.uh_ret:
    and     eax, 15
    ret

; l_write_tmp: the text (r12 bytes) into tmp_path
l_write_tmp:
    mov     eax, SYS_OPEN
    lea     rdi, [rel tmp_path]
    mov     esi, 0x241                     ; O_WRONLY | O_CREAT | O_TRUNC
    mov     edx, 0o600
    syscall
    test    rax, rax
    js      .w_ret
    push    rax
    mov     edi, eax
    mov     rsi, [rel text_buf]
    mov     rdx, r12
.w_more:
    test    rdx, rdx
    jz      .w_close
    mov     eax, SYS_WRITE
    push    rdx
    push    rsi
    syscall
    pop     rsi
    pop     rdx
    test    rax, rax
    jle     .w_close
    add     rsi, rax
    sub     rdx, rax
    mov     edi, [rsp]
    jmp     .w_more
.w_close:
    pop     rdi
    mov     eax, SYS_CLOSE
    syscall
.w_ret:
    ret

; l_assemble: utasm run on it: its stderr (the JSON messages) into err_buf
l_assemble:
    mov     qword [rel err_len], 0
    mov     eax, SYS_PIPE
    lea     rdi, [rel fds]
    syscall
    test    rax, rax
    jnz     .a_ret
    mov     eax, SYS_FORK
    syscall
    test    rax, rax
    js      .a_close
    jz      .a_child
    push    rax                            ; the child
    mov     eax, SYS_CLOSE
    mov     edi, [rel fds + 4]
    syscall
.a_read:
    mov     rsi, [rel err_buf]
    add     rsi, [rel err_len]
    mov     rdx, ERR_CAP
    sub     rdx, [rel err_len]
    jz      .a_drain
    mov     edi, [rel fds]
    mov     eax, SYS_READ
    syscall
    cmp     rax, -4
    je      .a_read
    test    rax, rax
    jle     .a_done
    add     [rel err_len], rax
    jmp     .a_read
.a_drain:
    ; (full: the rest read and dropped)
    sub     rsp, 4096
    mov     rsi, rsp
    mov     edx, 4096
    mov     edi, [rel fds]
    mov     eax, SYS_READ
    syscall
    add     rsp, 4096
    test    rax, rax
    jg      .a_drain
.a_done:
    mov     eax, SYS_CLOSE
    mov     edi, [rel fds]
    syscall
    pop     rdi
    xor     esi, esi
    xor     edx, edx
    xor     r10d, r10d
    mov     eax, SYS_WAIT4
    syscall
.a_ret:
    ret
.a_close:
    mov     eax, SYS_CLOSE
    mov     edi, [rel fds]
    syscall
    mov     eax, SYS_CLOSE
    mov     edi, [rel fds + 4]
    syscall
    ret
.a_child:
    ; stderr the pipe; stdout away (the editor's channel)
    mov     eax, SYS_DUP2
    mov     edi, [rel fds + 4]
    mov     esi, 2
    syscall
    mov     eax, SYS_OPEN
    lea     rdi, [rel a_null]
    mov     esi, 1                         ; O_WRONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .a_args
    mov     edi, eax
    mov     esi, 1
    mov     eax, SYS_DUP2
    syscall
.a_args:
    lea     rdi, [rel argv]
    lea     rax, [rel a_utasm]
    mov     [rdi], rax
    lea     rax, [rel a_x]
    mov     [rdi + 8], rax
    lea     rax, [rel a_json]
    mov     [rdi + 16], rax
    lea     rax, [rel a_f]
    mov     [rdi + 24], rax
    lea     rax, [rel a_elf64]
    mov     [rdi + 32], rax
    lea     rax, [rel a_i]
    mov     [rdi + 40], rax
    lea     rax, [rel doc_dir]
    mov     [rdi + 48], rax
    lea     rax, [rel a_o]
    mov     [rdi + 56], rax
    lea     rax, [rel a_null]
    mov     [rdi + 64], rax
    lea     rax, [rel tmp_path]
    mov     [rdi + 72], rax
    mov     qword [rdi + 80], 0
    mov     eax, SYS_EXECVE
    lea     rdi, [rel s_self]
    lea     rsi, [rel argv]
    mov     rdx, [rel utasm_envp]
    syscall
    mov     eax, SYS_EXIT
    mov     edi, 127
    syscall

; l_publish: textDocument/publishDiagnostics for the document: each JSON
; message utasm gave on its copy
l_publish:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     qword [rel out_len], 0
    lea     rsi, [rel p_head]
    call    o_str
    lea     rsi, [rel uri_buf]
    call    o_str
    lea     rsi, [rel p_diags]
    call    o_str
    xor     r15d, r15d                     ; diagnostics so far
    mov     r12, [rel err_buf]
    mov     r13, r12
    add     r13, [rel err_len]
.line:
    cmp     r12, r13
    jae     .lines_done
    mov     r14, r12
.eol:
    cmp     r14, r13
    jae     .one
    cmp     byte [r14], 10
    je      .one
    inc     r14
    jmp     .eol
.one:
    ; the line [r12, r14): its file must be the copy
    lea     rsi, [rel j_file]
    call    l_field
    test    rax, rax
    jz      .next
    mov     rdi, rax
    lea     rsi, [rel tmp_path]
.same:
    mov     al, [rsi]
    test    al, al
    jz      .same_end
    cmp     al, [rdi]
    jne     .next
    inc     rsi
    inc     rdi
    jmp     .same
.same_end:
    cmp     byte [rdi], '"'
    jne     .next
    ; its line, column (1-based), severity, message
    lea     rsi, [rel j_line]
    call    l_field
    test    rax, rax
    jz      .next
    mov     rdi, rax
    call    l_atoi
    mov     r8, rax
    lea     rsi, [rel j_column]
    call    l_field
    xor     r9d, r9d
    test    rax, rax
    jz      .no_col
    push    r8
    mov     rdi, rax
    call    l_atoi
    pop     r8
    mov     r9, rax
.no_col:
    test    r15, r15
    jz      .first
    mov     al, ','
    call    o_chr
.first:
    inc     r15
    push    r9
    push    r8
    lea     rsi, [rel d_range]
    call    o_str
    mov     rax, [rsp]
    test    rax, rax
    jz      .l0
    dec     rax
.l0:
    call    o_num
    lea     rsi, [rel d_char]
    call    o_str
    mov     rax, [rsp + 8]
    test    rax, rax
    jz      .c0
    dec     rax
.c0:
    call    o_num
    lea     rsi, [rel d_end]
    call    o_str
    pop     rax
    test    rax, rax
    jz      .e0
    dec     rax
.e0:
    call    o_num
    add     rsp, 8
    lea     rsi, [rel d_endchar]
    call    o_str
    ; severity: error / fatal 1, warning 2, else 3
    lea     rsi, [rel j_severity]
    call    l_field
    mov     ecx, 3
    test    rax, rax
    jz      .sev
    mov     rdi, rax
    lea     rsi, [rel s_error]
    call    l_word_at
    mov     ecx, 1
    je      .sev
    lea     rsi, [rel s_fatal]
    call    l_word_at
    je      .sev
    lea     rsi, [rel s_warning]
    call    l_word_at
    mov     ecx, 2
    je      .sev
    mov     ecx, 3
.sev:
    mov     eax, ecx
    call    o_num
    lea     rsi, [rel d_source]
    call    o_str
    ; the message, as escaped there
    lea     rsi, [rel j_message]
    call    l_field
    test    rax, rax
    jz      .msg_done
    mov     rsi, rax
.msg:
    cmp     rsi, r14
    jae     .msg_done
    mov     al, [rsi]
    cmp     al, '"'
    je      .msg_done
    call    o_chr
    cmp     al, '\'
    jne     .msg_next
    inc     rsi
    mov     al, [rsi]
    call    o_chr
.msg_next:
    inc     rsi
    jmp     .msg
.msg_done:
    lea     rsi, [rel d_close]
    call    o_str
.next:
    lea     r12, [r14 + 1]
    jmp     .line
.lines_done:
    lea     rsi, [rel p_tail]
    call    o_str
    call    o_send
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; l_field: the value after key rsi ('"name":' / '"name":"') in the line
; [r12, r14): rax = it (0 none). Preserves r8, r9.
l_field:
    mov     rdi, r12
.f_next:
    cmp     rdi, r14
    jae     .f_none
    push    rdi
    push    rsi
.f_cmp:
    mov     al, [rsi]
    test    al, al
    jz      .f_hit
    cmp     rdi, r14
    jae     .f_miss
    cmp     al, [rdi]
    jne     .f_miss
    inc     rsi
    inc     rdi
    jmp     .f_cmp
.f_hit:
    add     rsp, 16
    mov     rax, rdi
    ret
.f_miss:
    pop     rsi
    pop     rdi
    inc     rdi
    jmp     .f_next
.f_none:
    xor     eax, eax
    ret

; l_word_at: does rdi start with rsi? ZF. Preserves rdi.
l_word_at:
    push    rdi
.w_next:
    mov     al, [rsi]
    test    al, al
    jz      .w_yes
    cmp     al, [rdi]
    jne     .w_ret
    inc     rsi
    inc     rdi
    jmp     .w_next
.w_yes:
    cmp     al, al
.w_ret:
    pop     rdi
    ret

; l_atoi: the decimal number at rdi: rax
l_atoi:
    xor     eax, eax
.a_dig:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .a_end
    imul    rax, rax, 10
    add     rax, rcx
    inc     rdi
    jmp     .a_dig
.a_end:
    ret

; ---- output -------------------------------

; l_reply: '{"jsonrpc":"2.0","id":ID' and the rest rsi, sent
l_reply:
    push    rsi
    mov     qword [rel out_len], 0
    lea     rsi, [rel r_head]
    call    o_str
    lea     rsi, [rel id_buf]
    mov     rcx, [rel id_len]
.id:
    test    rcx, rcx
    jz      .id_done
    mov     al, [rsi]
    call    o_chr
    inc     rsi
    dec     rcx
    jmp     .id
.id_done:
    pop     rsi
    call    o_str
    jmp     o_send

o_chr:
    push    rcx
    push    rdx
    mov     rcx, [rel out_len]
    cmp     rcx, OUT_CAP
    jae     .c_full
    mov     rdx, [rel out_buf]
    mov     [rdx + rcx], al
    inc     qword [rel out_len]
.c_full:
    pop     rdx
    pop     rcx
    ret

o_str:
    push    rax
.s_next:
    mov     al, [rsi]
    test    al, al
    jz      .s_ret
    call    o_chr
    inc     rsi
    jmp     .s_next
.s_ret:
    pop     rax
    ret

; o_num: rax in decimal
o_num:
    push    rdi
    sub     rsp, 32
    mov     rdi, rsp
    call    l_num
    mov     byte [rdi], 0
    mov     rsi, rsp
    call    o_str
    add     rsp, 32
    pop     rdi
    ret

; o_send: the header and the message built, on stdout
o_send:
    sub     rsp, 64
    mov     rdi, rsp
    lea     rsi, [rel h_length]
    call    l_cpy
    mov     rax, [rel out_len]
    call    l_num
    lea     rsi, [rel h_end]
    call    l_cpy
    mov     rsi, rsp
    mov     rdx, rdi
    sub     rdx, rsp
    call    l_out
    mov     rsi, [rel out_buf]
    mov     rdx, [rel out_len]
    call    l_out
    add     rsp, 64
    ret

; l_out: rsi / rdx to stdout, all of it
l_out:
.o_more:
    test    rdx, rdx
    jz      .o_ret
    mov     edi, 1
    mov     eax, SYS_WRITE
    push    rsi
    push    rdx
    syscall
    pop     rdx
    pop     rsi
    cmp     rax, -4
    je      .o_more
    test    rax, rax
    jle     .o_ret
    add     rsi, rax
    sub     rdx, rax
    jmp     .o_more
.o_ret:
    ret

[SECTION .bss]
pending_cut:    resq 1              ; the bytes of the message last handed out
