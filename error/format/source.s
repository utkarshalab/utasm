;
; ============================================
; File     : error/format/source.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

; ============================================================================
; DIAGNOSTICS THAT SHOW WHERE AND WHY
; ============================================================================
; NASM prints one line per error. On a terminal utasm also shows the line
; and marks the place, in color, and explains an instruction it cannot
; encode:
;
;     prog.s:12: error: invalid combination of opcode and operands
;        12 |     mov al, rax
;           |     ^~~~~~~~~~~
;     note: `al' is an 8-bit register, `rax' a 64-bit register
;     note: the operands' sizes differ: 8 and 64 bits
;
; What is marked: the name the message is about ("symbol `cnt' not
; defined": cnt), else the token the parser stopped at (a syntax error),
; else the statement. Piped into a file or another program the output is
; NASM's, line for line, plus the "hint:" and "note:" lines: editors and
; scripts that read NASM's messages read utasm's. --color forces the rich
; form, --no-color (or NO_COLOR, TERM=dumb) the plain one.
;
;   diag_init       at start: rich or plain
;   diag_snippet    after a message's line: the source line, marked
;   diag_notes      after an error's line: what the operands were

extern print_str
extern error_loc_file
extern error_loc_line
extern error_subject
extern utasm_envp

%define AMD64_SYS_OPEN_     2
%define AMD64_SYS_IOCTL_    16
%define TCGETS_             0x5401
%define LINE_SHOWN          240         ; bytes of a line shown at most

[SECTION .bss]
alignb 8
global diag_rich, diag_color, diag_inst, diag_code
global diag_tok_file, diag_tok_line, diag_tok_col, diag_tok_len
diag_inst:      resq 1              ; the instruction an encoder error is about
diag_tok_file:  resq 1              ; the last token read from a file: where
diag_tok_line:  resd 1
diag_tok_col:   resd 1
diag_tok_len:   resd 1
diag_code:      resd 1              ; the error being reported (0: a message)
diag_map:       resq 1              ; the file read back, mapped
diag_map_len:   resq 1
diag_line:      resq 1              ; the line in it
diag_line_len:  resq 1
diag_buf:       resb 512            ; a row being built
diag_ops:       resq 8 * 2          ; the operands' text: start, length
diag_nops:      resd 1
diag_rich:      resb 1              ; 1: the source line, color, marks
diag_color:     resb 1              ; --color: 1, --no-color: 2, else 0

[SECTION .rodata]
global c_reset, c_bold, c_red, c_magenta, c_cyan
c_reset:        db 27, "[0m", 0
c_bold:         db 27, "[1m", 0
c_red:          db 27, "[1;31m", 0
c_magenta:      db 27, "[1;35m", 0
c_cyan:         db 27, "[1;36m", 0
c_green:        db 27, "[1;32m", 0
c_dim:          db 27, "[2m", 0
s_bar:          db " | ", 0
s_gutter:       db "       | ", 0
s_nl:           db 10, 0
s_note:         db "note: ", 0
s_tick:         db "`", 0
s_quote:        db "'", 0
s_is:           db " is ", 0
s_comma_sp:     db ", ", 0
s_and:          db " and ", 0
s_a:            db "a ", 0
s_an:           db "an ", 0
s_bit_reg:      db "-bit register", 0
s_bit_vec:      db "-bit vector register", 0
s_bit_mem:      db "-bit memory operand", 0
s_mem_nosize:   db "a memory operand with no size given", 0
s_imm:          db "a number", 0
s_label:        db "a label's address", 0
s_seg:          db "a segment register", 0
s_ctrl:         db "a control register", 0
s_dbg:          db "a debug register", 0
s_x87:          db "an x87 register", 0
s_mmx:          db "an MMX register", 0
s_mask:         db "a mask register", 0
s_reg:          db "a register", 0
s_sizes:        db "the operands' sizes differ: ", 0
s_bits:         db " bits", 0
s_imm_first:    db "the first operand cannot be a number: it is where the result goes", 0
s_none_takes:   db "no form of the instruction takes these operands", 0
s_operand:      db "operand ", 0
s_no_size_a:    db "' has no size: write `dword ", 0
s_no_size_b:    db "' (or byte, word, qword)", 10, 0
s_no_color:     db "NO_COLOR=", 0
s_term_dumb:    db "TERM=dumb", 0
prefix_words:   db "lock", 0, "rep", 0, "repe", 0, "repz", 0, "repne", 0
                db "repnz", 0, "o16", 0, "o32", 0, "o64", 0, "a16", 0, "a32", 0
                db "a64", 0, "xacquire", 0, "xrelease", 0, "bnd", 0, 0

[SECTION .text]

; ---- diag_init ----------------------------
;
; diag_init
; Rich or plain: --color / --no-color, else rich on a terminal unless
; NO_COLOR is set or TERM is dumb.
;
global diag_init
diag_init:
    push    rbx
    movzx   eax, byte [rel diag_color]
    cmp     eax, 1
    je      .rich
    cmp     eax, 2
    je      .plain
    ; stderr a terminal?
    sub     rsp, 64
    mov     eax, AMD64_SYS_IOCTL_
    mov     edi, 2
    mov     esi, TCGETS_
    mov     rdx, rsp
    syscall
    add     rsp, 64
    test    rax, rax
    jnz     .plain
    mov     rbx, [rel utasm_envp]
    test    rbx, rbx
    jz      .rich
.env:
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .rich
    add     rbx, 8
    lea     rsi, [rel s_no_color]
    call    .prefix
    je      .plain
    lea     rsi, [rel s_term_dumb]
    call    .prefix
    jne     .env
    cmp     byte [rdi + 9], 0              ; exactly "TERM=dumb"
    je      .plain
    jmp     .env
.rich:
    mov     byte [rel diag_rich], 1
    pop     rbx
    ret
.plain:
    mov     byte [rel diag_rich], 0
    pop     rbx
    ret
; .prefix: ZF set when the string at rdi starts with the one at rsi
.prefix:
    xor     ecx, ecx
.prefix_char:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .prefix_yes
    cmp     al, [rdi + rcx]
    jne     .prefix_no
    inc     ecx
    jmp     .prefix_char
.prefix_yes:
    xor     eax, eax                       ; ZF set
    ret
.prefix_no:
    or      eax, 1                         ; ZF clear
    ret

; ---- diag_color_on / diag_color_off -------
; rsi = an escape sequence: written when rich. Clobbers what print_str does.
global diag_color_on
diag_color_on:
    cmp     byte [rel diag_rich], 0
    je      .ret
    mov     edi, 2
    call    print_str
.ret:
    ret
global diag_color_off
diag_color_off:
    cmp     byte [rel diag_rich], 0
    je      .ret
    mov     edi, 2
    lea     rsi, [rel c_reset]
    call    print_str
.ret:
    ret

; ---- diag_read_line (internal) ------------
; The line error_loc_line of error_loc_file, read back: diag_line /
; diag_line_len (no newline). rax = 0 when it was found.
diag_read_line:
    push    rbx
    push    r12
    mov     qword [rel diag_map], 0
    mov     rdi, [rel error_loc_file]
    test    rdi, rdi
    jz      .fail
    mov     eax, AMD64_SYS_OPEN_
    xor     esi, esi                       ; O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .fail
    mov     rbx, rax                       ; fd
    mov     eax, 8                         ; lseek
    mov     rdi, rbx
    xor     esi, esi
    mov     edx, 2                         ; SEEK_END
    syscall
    test    rax, rax
    jle     .close_fail
    mov     r12, rax                       ; size
    mov     eax, 9                         ; mmap
    xor     edi, edi
    mov     rsi, r12
    mov     edx, 1                         ; PROT_READ
    mov     r10d, 2                        ; MAP_PRIVATE
    mov     r8, rbx
    xor     r9d, r9d
    syscall
    push    rax
    mov     eax, 3                         ; close
    mov     rdi, rbx
    syscall
    pop     rax
    cmp     rax, -4095
    jae     .fail
    mov     [rel diag_map], rax
    mov     [rel diag_map_len], r12
    ; to the line
    mov     ecx, [rel error_loc_line]
    test    ecx, ecx
    jz      .unmap_fail
    mov     rsi, rax                       ; position
    lea     rdi, [rax + r12]               ; end
.line:
    dec     ecx
    jz      .at_line
.skip:
    cmp     rsi, rdi
    jae     .unmap_fail
    cmp     byte [rsi], 10
    lea     rsi, [rsi + 1]
    jne     .skip
    jmp     .line
.at_line:
    mov     [rel diag_line], rsi
    xor     edx, edx
.len:
    lea     rax, [rsi + rdx]
    cmp     rax, rdi
    jae     .len_done
    cmp     byte [rsi + rdx], 10
    je      .len_done
    inc     rdx
    jmp     .len
.len_done:
    test    rdx, rdx
    jz      .have
    cmp     byte [rsi + rdx - 1], 13       ; a CR before the newline
    jne     .have
    dec     rdx
.have:
    mov     [rel diag_line_len], rdx
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
.unmap_fail:
    call    diag_unmap
.fail:
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.close_fail:
    mov     eax, 3
    mov     rdi, rbx
    syscall
    jmp     .fail

diag_unmap:
    mov     rdi, [rel diag_map]
    test    rdi, rdi
    jz      .ret
    mov     eax, 11                        ; munmap
    mov     rsi, [rel diag_map_len]
    syscall
    mov     qword [rel diag_map], 0
.ret:
    ret

; ---- diag_mark (internal) -----------------
; Which bytes of the line to mark: rax = from (0-based), rdx = how many.
; The name the message is about, else the token the parser stopped at (a
; syntax error), else the statement (its first to its last character
; before a comment).
diag_mark:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rel diag_line]
    mov     r12, [rel diag_line_len]
    ; 1. the subject, as a whole word
    mov     rdi, [rel error_subject]
    test    rdi, rdi
    jz      .token
    movzx   eax, byte [rdi]
    cmp     eax, 0x1E                      ; a kept expression / a distance:
    je      .token                         ; not text of the line
    cmp     eax, 0x1F
    je      .token
    xor     ecx, ecx                       ; subject length
.slen:
    cmp     byte [rdi + rcx], 0
    je      .slen_done
    inc     ecx
    jmp     .slen
.slen_done:
    test    ecx, ecx
    jz      .token
    mov     r13d, ecx
    xor     esi, esi                       ; position in the line
.find:
    lea     rax, [rsi + r13]
    cmp     rax, r12
    ja      .token
    xor     ecx, ecx
.cmp:
    cmp     ecx, r13d
    je      .found
    lea     rax, [rbx + rsi]
    mov     al, [rax + rcx]
    cmp     al, [rdi + rcx]
    jne     .next
    inc     ecx
    jmp     .cmp
.found:
    ; a whole word: no name character either side
    test    esi, esi
    jz      .left_ok
    movzx   eax, byte [rbx + rsi - 1]
    call    .namechar
    je      .next
.left_ok:
    lea     rax, [rsi + r13]
    cmp     rax, r12
    jae     .right_ok
    lea     rax, [rbx + rsi]
    movzx   eax, byte [rax + r13]
    call    .namechar
    je      .next
.right_ok:
    mov     eax, esi
    mov     edx, r13d
    jmp     .ret
.next:
    inc     esi
    jmp     .find
.token:
    ; 2. "operation size not specified": the memory operand
    mov     eax, [rel diag_code]
    cmp     eax, EXIT_NO_SIZE
    jne     .not_size
    call    diag_split_operands
    cmp     dword [rel diag_nops], 0
    je      .statement
    mov     rax, [rel diag_ops]
    sub     rax, rbx
    mov     rdx, [rel diag_ops + 8]
    jmp     .ret
.not_size:
    ; 3. a syntax error: the token the parser stopped at, on this line
    mov     eax, [rel diag_code]
    cmp     eax, EXIT_UNEXPECTED_TOKEN
    je      .stopped
    cmp     eax, EXIT_INVALID_EXPR
    jne     .statement
.stopped:
    mov     rax, [rel diag_tok_file]
    cmp     rax, [rel error_loc_file]
    jne     .statement
    mov     eax, [rel diag_tok_line]
    cmp     eax, [rel error_loc_line]
    jne     .statement
    mov     eax, [rel diag_tok_col]
    test    eax, eax
    jz      .statement
    dec     eax
    cmp     rax, r12
    jae     .statement
    mov     edx, [rel diag_tok_len]
    test    edx, edx
    jnz     .clip
    mov     edx, 1
.clip:
    lea     rcx, [rax + rdx]
    cmp     rcx, r12
    jbe     .ret
    mov     rdx, r12
    sub     rdx, rax
    jmp     .ret
.statement:
    ; 3. the statement: first to last character before a comment
    xor     esi, esi
.lead:
    cmp     rsi, r12
    jae     .whole_line
    movzx   eax, byte [rbx + rsi]
    cmp     eax, ' '
    je      .lead_next
    cmp     eax, 9
    jne     .lead_done
.lead_next:
    inc     rsi
    jmp     .lead
.lead_done:
    ; a label first ("x: inc [rax]"): the statement after it
    mov     r9, rsi                        ; the label's start
    mov     rcx, rsi
.label_word:
    cmp     rcx, r12
    jae     .no_label
    movzx   eax, byte [rbx + rcx]
    cmp     eax, ':'
    je      .after_label
    cmp     eax, ' '
    je      .no_label
    cmp     eax, 9
    je      .no_label
    cmp     eax, ';'
    je      .no_label
    inc     rcx
    jmp     .label_word
.after_label:
    lea     rsi, [rcx + 1]
.after_label_blank:
    cmp     rsi, r12
    jae     .no_label_back
    movzx   eax, byte [rbx + rsi]
    cmp     eax, ' '
    je      .after_label_next
    cmp     eax, 9
    jne     .no_label_check
.after_label_next:
    inc     rsi
    jmp     .after_label_blank
.no_label_check:
    cmp     eax, ';'
    jne     .no_label
.no_label_back:
    mov     rsi, r9                        ; only a label: mark it
.no_label:
    ; the end: a ';' outside quotes, then back over blanks
    mov     rcx, rsi
    xor     r8d, r8d                       ; the quote open, or 0
.scan:
    cmp     rcx, r12
    jae     .scan_done
    movzx   eax, byte [rbx + rcx]
    test    r8d, r8d
    jz      .unquoted
    cmp     eax, r8d
    jne     .scan_next
    xor     r8d, r8d
    jmp     .scan_next
.unquoted:
    cmp     eax, ';'
    je      .scan_done
    cmp     eax, "'"
    je      .quote
    cmp     eax, '"'
    je      .quote
    cmp     eax, '`'
    jne     .scan_next
.quote:
    mov     r8d, eax
.scan_next:
    inc     rcx
    jmp     .scan
.scan_done:
.trail:
    cmp     rcx, rsi
    jbe     .whole_line
    movzx   eax, byte [rbx + rcx - 1]
    cmp     eax, ' '
    je      .trail_back
    cmp     eax, 9
    jne     .trail_done
.trail_back:
    dec     rcx
    jmp     .trail
.trail_done:
    mov     rax, rsi
    mov     rdx, rcx
    sub     rdx, rsi
    jmp     .ret
.whole_line:
    xor     eax, eax
    mov     rdx, r12
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
; .namechar: ZF set when al is a name character (letter, digit, _ . $ @ ? #)
.namechar:
    cmp     eax, '_'
    je      .nc_yes
    cmp     eax, '.'
    je      .nc_yes
    cmp     eax, '$'
    je      .nc_yes
    cmp     eax, '@'
    je      .nc_yes
    cmp     eax, '?'
    je      .nc_yes
    cmp     eax, '#'
    je      .nc_yes
    mov     ecx, eax
    sub     ecx, '0'
    cmp     ecx, 9
    jbe     .nc_yes
    mov     ecx, eax
    or      ecx, 0x20
    sub     ecx, 'a'
    cmp     ecx, 25
    jbe     .nc_yes
    or      ecx, 1                         ; ZF clear
    ret
.nc_yes:
    xor     ecx, ecx                       ; ZF set
    ret

; ---- diag_snippet -------------------------
;
; diag_snippet
; Rich: the line the message is about, and under it the place marked:
;
;        12 |     mov al, rax
;           |     ^~~~~~~~~~~
;
; Nothing when plain, when there is no line (a message about the program
; as a whole), or when the file cannot be read again.
;
global diag_snippet
diag_snippet:
    cmp     byte [rel diag_rich], 0
    je      .ret
    push    rbx
    push    r12
    push    r13
    push    r14
    call    diag_read_line
    test    eax, eax
    jnz     .out
    call    diag_mark
    mov     r13, rax                       ; from
    mov     r14, rdx                       ; how many
    ; "   12 | the line"
    lea     rsi, [rel c_dim]
    call    diag_color_on
    lea     rdi, [rel diag_buf]
    mov     eax, [rel error_loc_line]
    call    diag_number5
    mov     byte [rdi], 0
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    call    print_str
    mov     edi, 2
    lea     rsi, [rel s_bar]
    call    print_str
    call    diag_color_off
    ; the line, as much as is shown
    mov     rbx, [rel diag_line]
    mov     r12, [rel diag_line_len]
    cmp     r12, LINE_SHOWN
    jbe     .shown
    mov     r12, LINE_SHOWN
.shown:
    lea     rdi, [rel diag_buf]
    mov     rsi, rbx
    mov     rcx, r12
    rep     movsb
    mov     byte [rdi], 10
    mov     byte [rdi + 1], 0
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    call    print_str
    ; "      | " and the mark, under the place (tabs kept, to line up)
    cmp     r13, r12
    jae     .unmap
    lea     rsi, [rel c_dim]
    call    diag_color_on
    mov     edi, 2
    lea     rsi, [rel s_gutter]
    call    print_str
    call    diag_color_off
    lea     rdi, [rel diag_buf]
    xor     ecx, ecx
.pad:
    cmp     rcx, r13
    jae     .padded
    mov     al, ' '
    cmp     byte [rbx + rcx], 9
    jne     .pad_put
    mov     al, 9
.pad_put:
    stosb
    inc     rcx
    jmp     .pad
.padded:
    mov     byte [rdi], 0
    push    rdi
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    call    print_str
    lea     rsi, [rel c_green]
    call    diag_color_on
    pop     rdi
    lea     rdi, [rel diag_buf]
    mov     byte [rdi], '^'
    inc     rdi
    mov     rcx, r14
    lea     rax, [r13 + rcx]
    cmp     rax, r12
    jbe     .tildes
    mov     rcx, r12
    sub     rcx, r13
.tildes:
    dec     rcx
    jle     .marked
    cmp     rcx, LINE_SHOWN
    ja      .marked
    mov     al, '~'
    rep     stosb
.marked:
    mov     byte [rdi], 0
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    call    print_str
    call    diag_color_off
    mov     edi, 2
    lea     rsi, [rel s_nl]
    call    print_str
.unmap:
    call    diag_unmap
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.ret:
    ret

; diag_number5: eax right-aligned in 5 columns (more when it is longer) at
; rdi, a blank first; rdi past it
diag_number5:
    sub     rsp, 32
    mov     r10, rsp
    mov     r11d, 10
    xor     ecx, ecx
.digit:
    xor     edx, edx
    div     r11d
    add     dl, '0'
    mov     [r10 + rcx], dl
    inc     ecx
    test    eax, eax
    jnz     .digit
    mov     byte [rdi], ' '
    inc     rdi
    mov     edx, 5
    sub     edx, ecx
    jle     .digits
.space:
    mov     byte [rdi], ' '
    inc     rdi
    dec     edx
    jnz     .space
.digits:
    dec     ecx
    mov     al, [r10 + rcx]
    mov     [rdi], al
    inc     rdi
    test    ecx, ecx
    jnz     .digits
    add     rsp, 32
    ret

; ---- diag_notes ---------------------------
;
; diag_notes
; After "invalid combination of opcode and operands" (or another error about
; an instruction's operands): what each operand is, as written, and what
; does not fit -
;
;     note: `al' is an 8-bit register, `rax' a 64-bit register
;     note: the operands' sizes differ: 8 and 64 bits
;
; In both forms, rich and plain. Nothing for other errors.
;
global diag_notes
diag_notes:
    mov     eax, [rel diag_code]
    cmp     eax, EXIT_NO_SIZE
    je      diag_note_size
    cmp     eax, EXIT_ENCODER_ERROR
    je      .about_operands
    cmp     eax, EXIT_ENCODE_FAIL
    je      .about_operands
    cmp     eax, EXIT_REG_SIZE
    je      .about_operands
    cmp     eax, EXIT_INVALID_OPERAND
    je      .about_operands
    ret
.about_operands:
    cmp     qword [rel diag_inst], 0
    jne     .go
    ret
.go:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, [rel diag_inst]
    movzx   r13d, byte [r12 + INST_nops]
    test    r13d, r13d
    jz      .out
    cmp     r13d, 4
    ja      .out
    ; the operands' text, from the line (when it splits as the parser did)
    mov     dword [rel diag_nops], 0
    call    diag_read_line
    test    eax, eax
    jnz     .described
    call    diag_split_operands
    cmp     [rel diag_nops], r13d
    je      .described
    mov     dword [rel diag_nops], 0       ; (a macro's line: no text)
.described:
    ; "note: `al' is an 8-bit register, `rax' a 64-bit register"
    lea     rsi, [rel c_cyan]
    call    diag_color_on
    mov     edi, 2
    lea     rsi, [rel s_note]
    call    print_str
    call    diag_color_off
    xor     r14d, r14d                     ; operand number
.operand:
    cmp     r14d, r13d
    jae     .first_done
    test    r14d, r14d
    jz      .no_sep
    mov     edi, 2
    lea     rsi, [rel s_comma_sp]
    call    print_str
.no_sep:
    call    .name                          ; `al'
    imul    eax, r14d, OPERAND_SIZE
    lea     rbx, [r12 + INST_op0 + rax]
    test    r14d, r14d
    jnz     .no_is
    mov     edi, 2
    lea     rsi, [rel s_is]
    call    print_str
    jmp     .what
.no_is:
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    mov     word [rsi], ' '
    call    print_str
.what:
    call    diag_describe                  ; rbx = OPERAND
    inc     r14d
    jmp     .operand
.first_done:
    mov     edi, 2
    lea     rsi, [rel s_nl]
    call    print_str
    ; what does not fit
    call    diag_size_clash                ; eax / edx = two sizes, or 0
    test    eax, eax
    jz      .no_clash
    push    rdx
    push    rax
    lea     rsi, [rel c_cyan]
    call    diag_color_on
    mov     edi, 2
    lea     rsi, [rel s_note]
    call    print_str
    call    diag_color_off
    mov     edi, 2
    lea     rsi, [rel s_sizes]
    call    print_str
    pop     rax
    call    diag_print_num
    mov     edi, 2
    lea     rsi, [rel s_and]
    call    print_str
    pop     rax
    call    diag_print_num
    mov     edi, 2
    lea     rsi, [rel s_bits]
    call    print_str
    mov     edi, 2
    lea     rsi, [rel s_nl]
    call    print_str
    jmp     .unmap
.no_clash:
    ; a number where the result goes
    cmp     r13d, 2
    jb      .unmap
    movzx   eax, byte [r12 + INST_op0 + OPERAND_kind]
    cmp     eax, OP_IMM
    jne     .unmap
    lea     rsi, [rel c_cyan]
    call    diag_color_on
    mov     edi, 2
    lea     rsi, [rel s_note]
    call    print_str
    call    diag_color_off
    mov     edi, 2
    lea     rsi, [rel s_imm_first]
    call    print_str
    mov     edi, 2
    lea     rsi, [rel s_nl]
    call    print_str
.unmap:
    call    diag_unmap
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
; .name: "`text'" of operand r14 (or "operand N" with no text)
.name:
    cmp     dword [rel diag_nops], 0
    je      .numbered
    mov     edi, 2
    lea     rsi, [rel s_tick]
    call    print_str
    lea     rax, [rel diag_ops]
    mov     rdx, r14
    shl     rdx, 4
    mov     rsi, [rax + rdx]
    mov     rcx, [rax + rdx + 8]
    cmp     rcx, 60
    jbe     .name_len
    mov     ecx, 60
.name_len:
    lea     rdi, [rel diag_buf]
    rep     movsb
    mov     byte [rdi], 0
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    call    print_str
    mov     edi, 2
    lea     rsi, [rel s_quote]
    jmp     print_str
.numbered:
    mov     edi, 2
    lea     rsi, [rel s_operand]
    call    print_str
    lea     eax, [r14 + 1]
    jmp     diag_print_num

; diag_note_size: after "operation size not specified" -
;     note: `[rax]' has no size: write `dword [rax]' (byte, word, dword, qword)
diag_note_size:
    push    rbx
    call    diag_read_line
    test    eax, eax
    jnz     .ret
    call    diag_split_operands
    cmp     dword [rel diag_nops], 0
    je      .unmap
    lea     rsi, [rel c_cyan]
    call    diag_color_on
    mov     edi, 2
    lea     rsi, [rel s_note]
    call    print_str
    call    diag_color_off
    mov     edi, 2
    lea     rsi, [rel s_tick]
    call    print_str
    call    .operand
    mov     edi, 2
    lea     rsi, [rel s_no_size_a]
    call    print_str
    call    .operand
    mov     edi, 2
    lea     rsi, [rel s_no_size_b]
    call    print_str
.unmap:
    call    diag_unmap
.ret:
    pop     rbx
    ret
; .operand: the first operand's text
.operand:
    mov     rsi, [rel diag_ops]
    mov     rcx, [rel diag_ops + 8]
    cmp     rcx, 60
    jbe     .len
    mov     ecx, 60
.len:
    lea     rdi, [rel diag_buf]
    rep     movsb
    mov     byte [rdi], 0
    mov     edi, 2
    lea     rsi, [rel diag_buf]
    jmp     print_str

; diag_print_num: eax in decimal on stderr
diag_print_num:
    lea     rdi, [rel diag_buf + 64]
    mov     byte [rdi], 0
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    eax, eax
    jnz     .digit
    mov     rsi, rdi
    mov     edi, 2
    jmp     print_str

; diag_bits: the size of operand rbx in bits (0: none given)
diag_bits:
    movzx   eax, word [rbx + OPERAND_xsize]
    test    eax, eax
    jnz     .ret
    movzx   eax, byte [rbx + OPERAND_size]
.ret:
    ret

; diag_describe: what operand rbx is, on stderr ("an 8-bit register")
diag_describe:
    movzx   eax, byte [rbx + OPERAND_kind]
    cmp     eax, OP_IMM
    je      .imm
    cmp     eax, OP_SYMBOL
    je      .label
    cmp     eax, OP_MEM
    je      .mem
    cmp     eax, OP_REG
    jne     .other
    movzx   eax, byte [rbx + OPERAND_reg]
    cmp     eax, REG_CS
    jb      .sized_reg
    lea     rsi, [rel s_seg]
    cmp     eax, REG_CR0
    jb      .say
    lea     rsi, [rel s_ctrl]
    cmp     eax, REG_DR0
    jb      .say
    lea     rsi, [rel s_dbg]
    cmp     eax, REG_ST0
    jb      .say
    lea     rsi, [rel s_x87]
    cmp     eax, REG_MM0
    jb      .say
    lea     rsi, [rel s_mmx]
    cmp     eax, REG_XMM0
    jb      .say
    lea     rsi, [rel s_mask]
    cmp     eax, REG_K0
    jae     .say_mask
    call    diag_bits
    cmp     eax, 128
    jb      .sized_reg
    lea     r8, [rel s_bit_vec]
    jmp     .sized
.say_mask:
    cmp     eax, REG_K0 + 8
    jb      .say
.other:
    lea     rsi, [rel s_reg]
    jmp     .say
.sized_reg:
    call    diag_bits
    lea     r8, [rel s_bit_reg]
    test    eax, eax
    jz      .other
.sized:
    ; "a 64-bit ..." / "an 8-bit ..."
    push    rax
    push    r8
    lea     rsi, [rel s_a]
    cmp     eax, 8
    jne     .article
    lea     rsi, [rel s_an]
.article:
    mov     edi, 2
    call    print_str
    mov     eax, [rsp + 8]
    call    diag_print_num
    pop     rsi
    pop     rax
    mov     edi, 2
    jmp     print_str
.mem:
    call    diag_bits
    test    eax, eax
    jz      .mem_nosize
    lea     r8, [rel s_bit_mem]
    jmp     .sized
.mem_nosize:
    lea     rsi, [rel s_mem_nosize]
    jmp     .say
.imm:
    lea     rsi, [rel s_imm]
    jmp     .say
.label:
    lea     rsi, [rel s_label]
.say:
    mov     edi, 2
    jmp     print_str

; diag_size_clash: two register / memory operands of r12 with sizes given
; that differ (general registers and memory only): eax / edx = the sizes,
; else eax = 0
diag_size_clash:
    push    rbx
    xor     r8d, r8d                       ; the first size seen
    xor     ecx, ecx
.op:
    cmp     ecx, r13d
    jae     .none
    imul    eax, ecx, OPERAND_SIZE
    lea     rbx, [r12 + INST_op0 + rax]
    inc     ecx
    movzx   eax, byte [rbx + OPERAND_kind]
    cmp     eax, OP_MEM
    je      .sized_op
    cmp     eax, OP_REG
    jne     .op
    cmp     byte [rbx + OPERAND_reg], REG_CS
    jae     .op                            ; not a general register
.sized_op:
    push    rcx
    call    diag_bits
    pop     rcx
    test    eax, eax
    jz      .op
    test    r8d, r8d
    jnz     .compare
    mov     r8d, eax
    jmp     .op
.compare:
    cmp     eax, r8d
    je      .op
    mov     edx, eax
    mov     eax, r8d
    pop     rbx
    ret
.none:
    xor     eax, eax
    pop     rbx
    ret

; diag_split_operands: the operands' text in diag_line: after a label
; ("x:"), prefixes and the mnemonic, split at commas outside brackets and
; quotes, blanks trimmed - into diag_ops / diag_nops
diag_split_operands:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rel diag_line]
    mov     r12, [rel diag_line_len]
    xor     esi, esi
.word:
    ; skip blanks, then the next word
    call    .blanks
    mov     rdi, rsi                       ; the word's start
.word_end:
    cmp     rsi, r12
    jae     .no_operands
    movzx   eax, byte [rbx + rsi]
    cmp     eax, ' '
    je      .word_done
    cmp     eax, 9
    je      .word_done
    cmp     eax, ';'
    je      .word_done
    inc     rsi
    jmp     .word_end
.word_done:
    mov     rcx, rsi
    sub     rcx, rdi                       ; its length
    jz      .no_operands
    cmp     byte [rbx + rsi - 1], ':'
    je      .word                          ; a label
    ; a prefix?
    push    rsi
    lea     r8, [rel prefix_words]
.prefix:
    cmp     byte [r8], 0
    je      .mnemonic
    xor     edx, edx
.pchar:
    cmp     rdx, rcx
    je      .pend
    lea     rax, [rbx + rdi]
    movzx   eax, byte [rax + rdx]
    or      eax, 0x20
    cmp     al, [r8 + rdx]
    jne     .pnext
    inc     rdx
    jmp     .pchar
.pend:
    cmp     byte [r8 + rdx], 0
    jne     .pnext
    pop     rsi
    jmp     .word                          ; a prefix: the next word
.pnext:
    cmp     byte [r8], 0
    je      .mnemonic
    inc     r8
    cmp     byte [r8 - 1], 0
    jne     .pnext
    jmp     .prefix
.mnemonic:
    pop     rsi
    ; the operands: split at top-level commas, up to a comment
    xor     r13d, r13d                     ; operands found
    xor     r8d, r8d                       ; bracket depth
    xor     r9d, r9d                       ; the quote open
    call    .blanks
    mov     rdi, rsi                       ; this operand's start
.scan:
    cmp     rsi, r12
    jae     .last
    movzx   eax, byte [rbx + rsi]
    test    r9d, r9d
    jz      .unquoted
    cmp     eax, r9d
    jne     .scan_next
    xor     r9d, r9d
    jmp     .scan_next
.unquoted:
    cmp     eax, ';'
    je      .last
    cmp     eax, "'"
    je      .quote
    cmp     eax, '"'
    je      .quote
    cmp     eax, '['
    je      .open
    cmp     eax, '('
    je      .open
    cmp     eax, '{'
    je      .open
    cmp     eax, ']'
    je      .close
    cmp     eax, ')'
    je      .close
    cmp     eax, '}'
    je      .close
    cmp     eax, ','
    jne     .scan_next
    test    r8d, r8d
    jnz     .scan_next
    call    .take
    inc     rsi
    call    .blanks
    mov     rdi, rsi
    jmp     .scan
.quote:
    mov     r9d, eax
    jmp     .scan_next
.open:
    inc     r8d
    jmp     .scan_next
.close:
    test    r8d, r8d
    jz      .scan_next
    dec     r8d
.scan_next:
    inc     rsi
    jmp     .scan
.last:
    cmp     rsi, rdi
    jbe     .done
    call    .take
.done:
    mov     [rel diag_nops], r13d
    pop     r13
    pop     r12
    pop     rbx
    ret
.no_operands:
    mov     dword [rel diag_nops], 0
    pop     r13
    pop     r12
    pop     rbx
    ret
; .take: the operand from rdi to rsi, trailing blanks off
.take:
    mov     rcx, rsi
.trim:
    cmp     rcx, rdi
    jbe     .took
    movzx   eax, byte [rbx + rcx - 1]
    cmp     eax, ' '
    je      .trim_back
    cmp     eax, 9
    jne     .took
.trim_back:
    dec     rcx
    jmp     .trim
.took:
    cmp     r13d, 8
    jae     .take_ret
    lea     rax, [rel diag_ops]
    mov     rdx, r13
    shl     rdx, 4
    lea     r10, [rbx + rdi]
    mov     [rax + rdx], r10
    mov     r10, rcx
    sub     r10, rdi
    mov     [rax + rdx + 8], r10
    inc     r13d
.take_ret:
    ret
; .blanks: rsi past blanks
.blanks:
    cmp     rsi, r12
    jae     .blanks_done
    movzx   eax, byte [rbx + rsi]
    cmp     eax, ' '
    je      .blank
    cmp     eax, 9
    jne     .blanks_done
.blank:
    inc     rsi
    jmp     .blanks
.blanks_done:
    ret
