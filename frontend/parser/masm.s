;
; ============================================
; File     : frontend/parser/masm.s
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
; MASM'S PROCEDURES, INVOKE AND RUNTIME CONTROL FLOW (%use masm)
; ============================================================================
;   NAME PROC [NEAR|FAR] [C|STDCALL|SYSCALL] [PUBLIC] [USES R1 R2 ...]
;             [, P1[:TYPE], P2[:TYPE] ...]          ... NAME ENDP
;       a frame when it has parameters or LOCALs (push rbp / mov rbp, rsp /
;       sub rsp, its size); the USES registers saved; the parameters copied
;       from their registers (System V: rdi rsi rdx rcx r8 r9, xmm0-7; -f
;       win64: rcx rdx r8 r9 into their home slots) and named, as typed
;       memory ("mov eax, p1"); "ret" in it the epilogue (the registers
;       back, leave, ret / retf; stdcall's ret N in 32-bit code)
;   LOCAL A:TYPE, B[N]:TYPE ...     named stack slots in the frame
;   INVOKE F, A1, A2 ...            the arguments in their registers (and
;       pushed past them), "addr x" its address, al = 0 (System V's vector
;       count), call, the stack put back; an argument read from a register
;       an earlier one was loaded into: an error
;   .IF C / .ELSEIF C / .ELSE / .ENDIF, .WHILE C / .ENDW, .REPEAT / .UNTIL C
;   / .UNTILCXZ, .BREAK [.IF C], .CONTINUE [.IF C]
;       compares and jumps; C is A == B, !=, <, <=, >, >= (unsigned; signed
;       with an sbyte / sword / sdword / sqword operand), A & B (test), A
;       alone (not zero), ZERO? CARRY? SIGN? OVERFLOW? PARITY?, with !, &&,
;       || and parentheses
;   .CODE .DATA .DATA? .CONST       sections; EXTERNDEF N[:T] an extern;
;   PROTO and OPTION lines taken
; Each turns into text read next (prep_push_buffer), every line of it
; numbered as the statement that made it; listed as that line.

extern  preprocessor_peek_token
extern  preprocessor_next_token
extern  prep_push_buffer
extern  prep_tokens_text
extern  mem_reserve
extern  str_len
extern  str_cmp_kw
extern  error_set_subject
extern  error_loc_file, error_loc_line
extern  asm_bits
extern  coff_enabled

%define MT_MAX       512            ; tokens of one statement
%define MB_CAP       (1 << 24)
%define MP_MAXP      32             ; parameters
%define MP_MAXN      256            ; names %defined in a procedure
%define MP_MAXU      16             ; USES registers
%define MK_MAX       64             ; blocks open

; block kinds
%define MK_IF        1
%define MK_WHILE     2
%define MK_REPEAT    3
; a block: kind, its labels (end, next / top, test / top, continue), the
; condition's code (.WHILE), whether .ELSE was seen
%define K_kind       0
%define K_end        8
%define K_a          16
%define K_b          24
%define K_cond       32
%define K_else       40
%define K_SIZE       48

[SECTION .rodata]
s_lbl:      db "..@m", 0
s_line:     db "%line ", 0
s_q:        db ' "', 0
s_jmp:      db "jmp ", 0
s_cmp:      db "cmp ", 0
s_test:     db "test ", 0
s_comma:    db ", ", 0
s_zero:     db ", 0", 0
s_define:   db "%define ", 0
s_undef:    db "%undef ", 0
s_push:     db "push ", 0
s_pop:      db "pop ", 0
s_rbp_m:    db " [rbp - ", 0
s_rbp_p:    db " [rbp + ", 0
s_ebp_m:    db " [ebp - ", 0
s_ebp_p:    db " [ebp + ", 0
s_close:    db "]", 0
s_frame64:  db "push rbp", 10, "mov rbp, rsp", 0
s_frame32:  db "push ebp", 10, "mov ebp, esp", 0
s_subrsp:   db "sub rsp, ", 0
s_subesp:   db "sub esp, ", 0
s_addrsp:   db "add rsp, ", 0
s_addesp:   db "add esp, ", 0
s_leave:    db "leave", 0
s_ret:      db "ret", 0
s_retf:     db "retf", 0
s_space:    db " ", 0
s_frame_n:  db "_f", 0
s_equ:      db " equ ", 0
s_movq:     db "mov qword [rbp ", 0
s_movsd:    db "movsd qword [rbp ", 0
s_movss:    db "movss dword [rbp ", 0
s_minus:    db "- ", 0
s_plus:     db "+ ", 0
s_xmm:      db "], xmm", 0
s_regto:    db "], ", 0
s_call:     db "call ", 0
s_xoreax:   db "xor eax, eax", 0
s_lea:      db "lea ", 0
s_rel:      db ", [rel ", 0
s_brk:      db ", [", 0
s_mov:      db "mov ", 0
s_movzx:    db "movzx ", 0
s_movsx:    db "movsx ", 0
s_section:  db "section ", 0
s_extern:   db "extern ", 0
s_loop:     db "loop ", 0
s_sub8:     db "sub rsp, 8", 0
s_sub32:    db "sub rsp, 32", 0
s_global:   db "global ", 0
sec_text:   db ".text", 0
sec_data:   db ".data", 0
sec_bss:    db ".bss", 0
sec_rodata: db ".rodata", 0

w_proc:     db "proc", 0
w_endp:     db "endp", 0
w_near:     db "near", 0
w_far:      db "far", 0
w_c:        db "c", 0
w_stdcall:  db "stdcall", 0
w_syscall:  db "syscall", 0
w_pascal:   db "pascal", 0
w_public:   db "public", 0
w_private:  db "private", 0
w_export:   db "export", 0
w_uses:     db "uses", 0
w_local:    db "local", 0
w_invoke:   db "invoke", 0
w_addr:     db "addr", 0
w_ptr:      db "__?masm_ptr?__", 0
w_ptr2:     db "ptr", 0
w_vararg:   db "vararg", 0
w_externdef: db "externdef", 0
w_proto:    db "proto", 0
w_option:   db "option", 0
w_retn:     db "retn", 0
w_if:       db ".if", 0
w_elseif:   db ".elseif", 0
w_else:     db ".else", 0
w_endif:    db ".endif", 0
w_while:    db ".while", 0
w_endw:     db ".endw", 0
w_repeat:   db ".repeat", 0
w_until:    db ".until", 0
w_untilcxz: db ".untilcxz", 0
w_break:    db ".break", 0
w_continue: db ".continue", 0
w_code:     db ".code", 0
w_data:     db ".data", 0
w_datau:    db ".data?", 0
w_const:    db ".const", 0
w_zero:     db "zero?", 0
w_carry:    db "carry?", 0
w_sign:     db "sign?", 0
w_overflow: db "overflow?", 0
w_parity:   db "parity?", 0

; the types: word, size, NASM's size word
types:
    db "byte", 0, 1
    db "sbyte", 0, 0x81
    db "word", 0, 2
    db "sword", 0, 0x82
    db "dword", 0, 4
    db "sdword", 0, 0x84
    db "real4", 0, 0x44
    db "qword", 0, 8
    db "sqword", 0, 0x88
    db "real8", 0, 0x48
    db "tbyte", 0, 10
    db "real10", 0, 10
    db "oword", 0, 16
    db "xmmword", 0, 16
    db "ymmword", 0, 32
    db 0
size_words:
    db "byte", 0, 0, 0, 0     ; 1
    db "word", 0, 0, 0, 0     ; 2
    db "dword", 0, 0, 0       ; 4
    db "qword", 0, 0, 0       ; 8
    db "tword", 0, 0, 0       ; 10
    db "oword", 0, 0, 0       ; 16
    db "yword", 0, 0, 0       ; 32

; the general registers: name, size, number (for INVOKE's check)
regs:
    db "rax",0,64,0, "rcx",0,64,1, "rdx",0,64,2, "rbx",0,64,3
    db "rsp",0,64,4, "rbp",0,64,5, "rsi",0,64,6, "rdi",0,64,7
    db "r8",0,64,8, "r9",0,64,9, "r10",0,64,10, "r11",0,64,11
    db "r12",0,64,12, "r13",0,64,13, "r14",0,64,14, "r15",0,64,15
    db "eax",0,32,0, "ecx",0,32,1, "edx",0,32,2, "ebx",0,32,3
    db "esp",0,32,4, "ebp",0,32,5, "esi",0,32,6, "edi",0,32,7
    db "r8d",0,32,8, "r9d",0,32,9, "r10d",0,32,10, "r11d",0,32,11
    db "r12d",0,32,12, "r13d",0,32,13, "r14d",0,32,14, "r15d",0,32,15
    db "ax",0,16,0, "cx",0,16,1, "dx",0,16,2, "bx",0,16,3
    db "sp",0,16,4, "bp",0,16,5, "si",0,16,6, "di",0,16,7
    db "r8w",0,16,8, "r9w",0,16,9, "r10w",0,16,10, "r11w",0,16,11
    db "r12w",0,16,12, "r13w",0,16,13, "r14w",0,16,14, "r15w",0,16,15
    db "al",0,8,0, "cl",0,8,1, "dl",0,8,2, "bl",0,8,3
    db "spl",0,8,4, "bpl",0,8,5, "sil",0,8,6, "dil",0,8,7
    db "ah",0,8,0, "ch",0,8,1, "dh",0,8,2, "bh",0,8,3
    db "r8b",0,8,8, "r9b",0,8,9, "r10b",0,8,10, "r11b",0,8,11
    db "r12b",0,8,12, "r13b",0,8,13, "r14b",0,8,14, "r15b",0,8,15
    db 0
; System V's argument registers (64, 32-bit names; number); Win64's
sysv64:     db "rdi", 0, "rsi", 0, "rdx", 0, "rcx", 0, "r8", 0, "r9", 0
sysv32:     db "edi", 0, "esi", 0, "edx", 0, "ecx", 0, "r8d", 0, "r9d", 0
sysvnum:    db 7, 6, 2, 1, 8, 9
win64:      db "rcx", 0, "rdx", 0, "r8", 0, "r9", 0
r64names:   db "rax", 0, "rcx", 0, "rdx", 0, "rbx", 0, "rsp", 0, "rbp", 0, "rsi", 0, "rdi", 0
            db "r8", 0, "r9", 0, "r10", 0, "r11", 0, "r12", 0, "r13", 0, "r14", 0, "r15", 0
win32:      db "ecx", 0, "edx", 0, "r8d", 0, "r9d", 0
winnum:     db 1, 2, 8, 9
; jumps by condition: true / false, unsigned / signed
;           ==   !=   <    <=   >    >=
jt_u:  dq j_e, j_ne, j_b, j_be, j_a, j_ae
jf_u:  dq j_ne, j_e, j_ae, j_a, j_be, j_b
jt_s:  dq j_e, j_ne, j_l, j_le, j_g, j_ge
jf_s:  dq j_ne, j_e, j_ge, j_g, j_le, j_l
j_e:   db "je ", 0
j_ne:  db "jne ", 0
j_b:   db "jb ", 0
j_be:  db "jbe ", 0
j_a:   db "ja ", 0
j_ae:  db "jae ", 0
j_l:   db "jl ", 0
j_le:  db "jle ", 0
j_g:   db "jg ", 0
j_ge:  db "jge ", 0
j_nz:  db "jnz ", 0
j_z:   db "jz ", 0
j_c:   db "jc ", 0
j_nc:  db "jnc ", 0
j_s:   db "js ", 0
j_ns:  db "jns ", 0
j_o:   db "jo ", 0
j_no:  db "jno ", 0
j_p:   db "jp ", 0
j_np:  db "jnp ", 0

[SECTION .bss]
alignb 8
global masm_hl
masm_hl:        resb 1              ; %use masm: these words MASM's
alignb 8
mt_toks:        resb MT_MAX * TOKEN_SIZE
mt_n:           resq 1
mb_buf:         resq 1
mb_len:         resq 1
mb_over:        resb 1
alignb 8
m_label:        resq 1              ; the labels made so far
; the procedure open
mp_in:          resb 1
mp_far:         resb 1
mp_frame:       resb 1
mp_stdcall:     resb 1
mp_ret_raw:     resb 1              ; the next ret is the epilogue's own
alignb 8
mp_id:          resq 1              ; its frame constant's number
mp_name:        resq 1
mp_nuses:       resq 1
mp_uses:        resq MP_MAXU        ; the registers' names
mp_spill:       resq 1              ; bytes below rbp so far
mp_args:        resq 1              ; 32-bit: bytes of parameters
mp_names:       resq MP_MAXN
mp_nnames:      resq 1
; blocks open
mk:             resb MK_MAX * K_SIZE
mk_n:           resq 1
mk_file:        resq 1
mk_line:        resd 1
; the parts of a statement (INVOKE's arguments, PROC's parameters)
alignb 8
mx_s:           resq 64
mx_n:           resq 64
mx_cnt:         resq 1

[SECTION .text]

; ============================================================================
; TOKENS AND TEXT
; ============================================================================

; mt_collect: the tokens to the end of the line (the newline stays next),
; copied into mt_toks / mt_n. Output rax = OK or error
mt_collect:
    mov     qword [rel mt_n], 0
.c_next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .c_ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .c_done
    cmp     eax, TOK_EOF
    je      .c_done
    cmp     eax, TOK_COMMENT
    je      .c_done
    mov     rax, [rel mt_n]
    cmp     rax, MT_MAX
    jae     .c_long
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, rdx
    mov     rax, [rel mt_n]
    imul    rax, rax, TOKEN_SIZE
    lea     rdi, [rel mt_toks]
    add     rdi, rax
    copy_token
    inc     qword [rel mt_n]
    jmp     .c_next
.c_done:
    xor     eax, eax
.c_ret:
    ret
.c_long:
    mov     eax, EXIT_INVALID_EXPR
    ret

; mt_tok: rax = token rcx
mt_tok:
    imul    rax, rcx, TOKEN_SIZE
    push    rdx
    lea     rdx, [rel mt_toks]
    add     rax, rdx
    pop     rdx
    ret

; mt_is: token rcx an identifier that is the word rsi (any case)? ZF.
; Preserves rcx.
mt_is:
    push    rcx
    cmp     rcx, [rel mt_n]
    jae     .is_no
    call    mt_tok
    cmp     byte [rax + TOKEN_kind], TOK_IDENT
    jne     .is_no
    mov     rdi, [rax + TOKEN_value]
    call    str_cmp_kw
    test    rax, rax
    pop     rcx
    ret
.is_no:
    pop     rcx
    or      eax, 1
    ret

; mt_kind: eax = the kind of token rcx (0 past the end)
mt_kind:
    xor     eax, eax
    cmp     rcx, [rel mt_n]
    jae     .k_ret
    push    rax
    call    mt_tok
    movzx   eax, byte [rax + TOKEN_kind]
    add     rsp, 8
.k_ret:
    ret

; mt_put: the text of tokens [rcx, rdx) after the expansion
mt_put:
    cmp     rcx, rdx
    jae     .p_ret
    push    rsi
    mov     rsi, rdx
    sub     rsi, rcx
    push    rsi
    call    mt_tok
    mov     rsi, rax
    pop     rdx
    mov     rdi, rbx
    call    prep_tokens_text
    test    rax, rax
    jnz     .p_pop
    mov     rsi, rdx
    call    mb_putz
.p_pop:
    pop     rsi
.p_ret:
    ret

; mt_close: the token after the bracket at rcx closes it: rcx = its index
; (the end when it does not close)
mt_close:
    xor     edx, edx
.cl_next:
    cmp     rcx, [rel mt_n]
    jae     .cl_ret
    call    mt_kind
    cmp     eax, TOK_LPAREN
    je      .cl_in
    cmp     eax, TOK_LBRACKET
    je      .cl_in
    cmp     eax, TOK_RPAREN
    je      .cl_out
    cmp     eax, TOK_RBRACKET
    je      .cl_out
    jmp     .cl_step
.cl_in:
    inc     edx
    jmp     .cl_step
.cl_out:
    dec     edx
    jz      .cl_ret
.cl_step:
    inc     rcx
    jmp     .cl_next
.cl_ret:
    ret

; mt_split: tokens [rcx, rdx) at their commas outside brackets: mx_s /
; mx_n / mx_cnt (each part's first token and how many)
mt_split:
    push    r12
    push    r13
    push    r14
    mov     qword [rel mx_cnt], 0
    cmp     rcx, rdx
    jae     .sp_ret
    mov     r12, rcx                       ; a part's start
    mov     r13, rdx
    xor     r14d, r14d                     ; brackets
.sp_tok:
    cmp     rcx, r13
    jae     .sp_part
    call    mt_kind
    cmp     eax, TOK_LPAREN
    je      .sp_in
    cmp     eax, TOK_LBRACKET
    je      .sp_in
    cmp     eax, TOK_RPAREN
    je      .sp_out
    cmp     eax, TOK_RBRACKET
    je      .sp_out
    cmp     eax, TOK_COMMA
    jne     .sp_step
    test    r14d, r14d
    jnz     .sp_step
    call    .sp_add
    lea     r12, [rcx + 1]
    jmp     .sp_step
.sp_in:
    inc     r14d
    jmp     .sp_step
.sp_out:
    dec     r14d
.sp_step:
    inc     rcx
    jmp     .sp_tok
.sp_part:
    call    .sp_add
.sp_ret:
    pop     r14
    pop     r13
    pop     r12
    ret
.sp_add:
    mov     rax, [rel mx_cnt]
    cmp     rax, 64
    jae     .sp_add_ret
    lea     r8, [rel mx_s]
    mov     [r8 + rax * 8], r12
    mov     r9, rcx
    sub     r9, r12
    lea     r8, [rel mx_n]
    mov     [r8 + rax * 8], r9
    inc     qword [rel mx_cnt]
.sp_add_ret:
    ret

; mt_reg: is token rcx (alone in [rcx, rdx)) a general register? eax =
; its size (0: no), r8d = its number. Preserves rcx, rdx.
mt_reg:
    push    rcx
    push    rdx
    lea     rax, [rcx + 1]
    cmp     rax, rdx
    jne     .rg_no
    call    mt_tok
    cmp     byte [rax + TOKEN_kind], TOK_IDENT
    jne     .rg_no
    mov     r9, [rax + TOKEN_value]
    lea     r10, [rel regs]
.rg_entry:
    cmp     byte [r10], 0
    je      .rg_no
    mov     rdi, r9
    mov     rsi, r10
    call    str_cmp_kw
    mov     rcx, r10
.rg_skip:
    inc     rcx
    cmp     byte [rcx - 1], 0
    jne     .rg_skip
    test    rax, rax
    jz      .rg_hit
    lea     r10, [rcx + 2]
    jmp     .rg_entry
.rg_hit:
    movzx   eax, byte [rcx]
    movzx   r8d, byte [rcx + 1]
    pop     rdx
    pop     rcx
    ret
.rg_no:
    xor     eax, eax
    pop     rdx
    pop     rcx
    ret

; mt_type: the type word at token rcx (r12 the part's end): eax = the size
; with 0x80 signed, 0x40 a float (0: none); rcx past it (and "ptr X")
mt_type:
    call    mt_kind
    cmp     eax, TOK_IDENT
    jne     .ty_none
    ; PTR [TYPE]: a pointer
    lea     rsi, [rel w_ptr]
    call    mt_is
    je      .ty_ptr
    lea     rsi, [rel w_ptr2]
    call    mt_is
    je      .ty_ptr
    lea     rsi, [rel w_vararg]
    call    mt_is
    je      .ty_vararg
    call    mt_tok
    mov     r9, [rax + TOKEN_value]
    lea     r10, [rel types]
.ty_entry:
    cmp     byte [r10], 0
    je      .ty_none
    mov     rdi, r9
    mov     rsi, r10
    call    str_cmp_kw
    mov     r11, r10
.ty_skip:
    inc     r11
    cmp     byte [r11 - 1], 0
    jne     .ty_skip
    test    rax, rax
    jz      .ty_hit
    lea     r10, [r11 + 1]
    jmp     .ty_entry
.ty_hit:
    movzx   eax, byte [r11]
    inc     rcx
    ; "DWORD PTR": still the type's size... a pointer to it is a pointer
    push    rax
    lea     rsi, [rel w_ptr]
    call    mt_is
    je      .ty_ptr_after
    lea     rsi, [rel w_ptr2]
    call    mt_is
    je      .ty_ptr_after
    pop     rax
    ret
.ty_ptr_after:
    add     rsp, 8
.ty_ptr:
    mov     rcx, r12                       ; (the rest: its target type)
    mov     eax, 8
    cmp     byte [rel asm_bits], 64
    je      .ty_ret
    mov     eax, 4
.ty_ret:
    ret
.ty_vararg:
    mov     rcx, r12
    mov     eax, 0xFF                      ; (no slot of its own)
    ret
.ty_none:
    xor     eax, eax
    ret

; ============================================================================
; THE TEXT BUILT
; ============================================================================

mb_begin:
    mov     qword [rel mb_len], 0
    mov     byte [rel mb_over], 0
    cmp     qword [rel mb_buf], 0
    jne     .b_ok
    push    rsi
    mov     rsi, MB_CAP
    call    mem_reserve
    pop     rsi
    test    rax, rax
    jnz     .b_none
    mov     [rel mb_buf], rdx
.b_ok:
    mov     al, 10
    jmp     mb_putc
.b_none:
    mov     byte [rel mb_over], 1
    ret

; mb_putc: al. Preserves all.
mb_putc:
    push    rcx
    push    rdx
    mov     rcx, [rel mb_len]
    cmp     rcx, MB_CAP
    jae     .pc_over
    mov     rdx, [rel mb_buf]
    test    rdx, rdx
    jz      .pc_over
    mov     [rdx + rcx], al
    inc     qword [rel mb_len]
    jmp     .pc_ret
.pc_over:
    mov     byte [rel mb_over], 1
.pc_ret:
    pop     rdx
    pop     rcx
    ret

; mb_putz: the NUL-terminated rsi. Preserves all.
mb_putz:
    push    rsi
    push    rax
.z_next:
    mov     al, [rsi]
    test    al, al
    jz      .z_ret
    call    mb_putc
    inc     rsi
    jmp     .z_next
.z_ret:
    pop     rax
    pop     rsi
    ret

; mb_num: rax in decimal. Preserves all.
mb_num:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    sub     rsp, 32
    lea     rsi, [rsp + 31]
    xor     ecx, ecx
.n_dig:
    xor     edx, edx
    push    rcx
    mov     ecx, 10
    div     rcx
    pop     rcx
    add     dl, '0'
    mov     [rsi], dl
    dec     rsi
    inc     ecx
    test    rax, rax
    jnz     .n_dig
.n_out:
    inc     rsi
    mov     al, [rsi]
    call    mb_putc
    dec     ecx
    jnz     .n_out
    add     rsp, 32
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; mb_line: a new line of output: '%line N-1 "file"' first, so the line is
; numbered as the statement that made it
mb_line:
    push    rsi
    push    rax
    lea     rsi, [rel s_line]
    call    mb_putz
    mov     eax, [rel error_loc_line]
    dec     eax
    call    mb_num
    lea     rsi, [rel s_q]
    call    mb_putz
    mov     rsi, [rel error_loc_file]
    test    rsi, rsi
    jz      .l_nofile
    call    mb_putz
.l_nofile:
    mov     al, '"'
    call    mb_putc
    mov     al, 10
    call    mb_putc
    pop     rax
    pop     rsi
    ret

; mb_nl: the line's end
mb_nl:
    mov     al, 10
    jmp     mb_putc

; mb_lbl: the label rax ("..@mN")
mb_lbl:
    push    rsi
    lea     rsi, [rel s_lbl]
    call    mb_putz
    call    mb_num
    pop     rsi
    ret

; mb_def: "LABEL:" on a line of its own (rax)
mb_def:
    call    mb_line
    call    mb_lbl
    push    rax
    mov     al, ':'
    call    mb_putc
    pop     rax
    jmp     mb_nl

; mb_jcc: "JCC LABEL" (rsi the jump, rax the label)
mb_jcc:
    call    mb_line
    call    mb_putz
    call    mb_lbl
    jmp     mb_nl

; m_new: a new label: rax
m_new:
    inc     qword [rel m_label]
    mov     rax, [rel m_label]
    ret

; mb_push: the text built, read next, listed as this statement's line
; Output rax = OK or error
mb_push:
    mov     eax, EXIT_OOM
    cmp     byte [rel mb_over], 0
    jne     .ps_ret
    mov     rdi, rbx
    mov     rsi, [rel mb_buf]
    mov     rdx, [rel mb_len]
    mov     rcx, [rel error_loc_file]
    test    rcx, rcx
    jnz     .ps_named
    lea     rcx, [rel w_proc]
.ps_named:
    call    prep_push_buffer
    test    rax, rax
    jnz     .ps_ret
    mov     rax, [rbx + PREP_lexer]
    mov     byte [rax + LEXER_nolist], 1
    xor     eax, eax
.ps_ret:
    ret

; ============================================================================
; THE STATEMENTS
; ============================================================================

; ---- masm_word ----------------------------
;
; masm_word
; A statement word MASM's under %use masm: LOCAL, INVOKE, .IF & co, .CODE
; .DATA? .CONST, EXTERNDEF, PROTO / OPTION.
; Input    : rdi = PrepState (the operands next), rsi = the word (lower
;            case)
; Output   : eax = 0: not one; 1: done, rdx = OK or an error
;
global masm_word
masm_word:
    cmp     byte [rel masm_hl], 0
    jne     .on
    xor     eax, eax
    ret
.on:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    lea     rsi, [rel w_invoke]
    call    .word
    je      .invoke
    lea     rsi, [rel w_local]
    call    .word
    je      .local
    lea     rsi, [rel w_if]
    call    .word
    je      .if
    lea     rsi, [rel w_elseif]
    call    .word
    je      .elseif
    lea     rsi, [rel w_else]
    call    .word
    je      .else
    lea     rsi, [rel w_endif]
    call    .word
    je      .endif
    lea     rsi, [rel w_while]
    call    .word
    je      .while
    lea     rsi, [rel w_endw]
    call    .word
    je      .endw
    lea     rsi, [rel w_repeat]
    call    .word
    je      .repeat
    lea     rsi, [rel w_until]
    call    .word
    je      .until
    lea     rsi, [rel w_untilcxz]
    call    .word
    je      .untilcxz
    lea     rsi, [rel w_break]
    call    .word
    je      .break
    lea     rsi, [rel w_continue]
    call    .word
    je      .continue
    lea     rsi, [rel w_code]
    lea     r13, [rel sec_text]
    call    .word
    je      .section
    lea     rsi, [rel w_datau]
    lea     r13, [rel sec_bss]
    call    .word
    je      .section
    lea     rsi, [rel w_const]
    lea     r13, [rel sec_rodata]
    call    .word
    je      .section
    lea     rsi, [rel w_externdef]
    call    .word
    je      .externdef
    lea     rsi, [rel w_proto]
    call    .word
    je      .skip
    lea     rsi, [rel w_option]
    call    .word
    je      .skip
    xor     eax, eax
    jmp     .ret
.word:
    mov     rdi, r12
    call    str_cmp_kw
    test    rax, rax                       ; (ZF on a hit)
    ret

.section:
    call    mt_collect
    test    rax, rax
    jnz     .done_rax
    call    mb_begin
    call    mb_line
    lea     rsi, [rel s_section]
    call    mb_putz
    mov     rsi, r13
    call    mb_putz
    call    mb_nl
    call    mb_push
    jmp     .done_rax

.externdef:
    ; EXTERNDEF NAME[:TYPE], ...: extern NAME
    call    mt_collect
    test    rax, rax
    jnz     .done_rax
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    call    mt_split
    call    mb_begin
    xor     r13d, r13d
.ext_part:
    cmp     r13, [rel mx_cnt]
    jae     .ext_done
    lea     rax, [rel mx_s]
    mov     rcx, [rax + r13 * 8]
    call    mt_kind
    cmp     eax, TOK_LABEL
    je      .ext_name
    cmp     eax, TOK_IDENT
    jne     .ext_next
.ext_name:
    call    mb_line
    lea     rsi, [rel s_extern]
    call    mb_putz
    lea     rdx, [rcx + 1]
    call    mt_put
    call    mb_nl
.ext_next:
    inc     r13
    jmp     .ext_part
.ext_done:
    call    mb_push
    jmp     .done_rax

.skip:
    call    mt_collect
    jmp     .done_rax

.local:
    cmp     byte [rel mp_in], 0
    je      .not_ours                      ; (outside a PROC: NASM's / GNU's)
    call    masm_local
    jmp     .done_rax

.invoke:
    call    masm_invoke
    jmp     .done_rax

.if:
    call    masm_if
    jmp     .done_rax
.elseif:
    call    masm_elseif
    jmp     .done_rax
.else:
    call    masm_else
    jmp     .done_rax
.endif:
    call    masm_endif
    jmp     .done_rax
.while:
    call    masm_while
    jmp     .done_rax
.endw:
    call    masm_endw
    jmp     .done_rax
.repeat:
    call    masm_repeat
    jmp     .done_rax
.until:
    xor     esi, esi
    call    masm_until
    jmp     .done_rax
.untilcxz:
    mov     esi, 1
    call    masm_until
    jmp     .done_rax
.break:
    xor     esi, esi
    call    masm_break
    jmp     .done_rax
.continue:
    mov     esi, 1
    call    masm_break
    jmp     .done_rax

.not_ours:
    xor     eax, eax
    jmp     .ret
.done_rax:
    mov     rdx, rax
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- masm_label_word ----------------------
;
; masm_label_word
; "NAME PROC ..." / "NAME ENDP" under %use masm.
; Input    : rdi = PrepState (the word after NAME peeked), rsi = NAME
; Output   : eax = 0: neither; 1: done, rdx = OK or an error
;
global masm_label_word
masm_label_word:
    cmp     byte [rel masm_hl], 0
    jne     .on
    xor     eax, eax
    ret
.on:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .none
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     r13, [rdx + TOKEN_value]
    mov     rdi, r13
    lea     rsi, [rel w_proc]
    call    str_cmp_kw
    test    rax, rax
    jz      .proc
    mov     rdi, r13
    lea     rsi, [rel w_endp]
    call    str_cmp_kw
    test    rax, rax
    jz      .endp
.none:
    xor     eax, eax
    jmp     .ret
.proc:
    mov     rdi, rbx
    call    preprocessor_next_token
    call    masm_proc
    jmp     .done
.endp:
    mov     rdi, rbx
    call    preprocessor_next_token
    call    masm_endp
.done:
    mov     rdx, rax
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- masm_ret -----------------------------
;
; masm_ret
; "ret" / "retn" / "retf" in a PROC: its epilogue (the USES registers back,
; leave) and the return the PROC's kind has (retf in a far one; stdcall's
; ret N).
; Input    : rdi = PrepState (the operands next), rsi = the word
; Output   : eax = 0: an ordinary ret; 1: done, rdx = OK or an error
;
global masm_ret
masm_ret:
    cmp     byte [rel mp_in], 0
    jne     .on
.plain:
    xor     eax, eax
    ret
.on:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    ; "ret" / "retn" only (retf written: as it is)
    mov     rdi, r12
    lea     rsi, [rel s_ret]
    call    str_cmp_kw
    mov     r13d, eax                      ; 0: "ret"
    mov     rdi, r12
    lea     rsi, [rel w_retn]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_retn
    xor     r13d, r13d
.not_retn:
    test    r13d, r13d
    jnz     .none
    ; the epilogue's own ret: as it is
    cmp     byte [rel mp_ret_raw], 0
    je      .ours
    mov     byte [rel mp_ret_raw], 0
    jmp     .none
.ours:
    cmp     byte [rel mp_frame], 0
    jne     .epilogue
    cmp     qword [rel mp_nuses], 0
    jne     .epilogue
    cmp     byte [rel mp_far], 0
    jne     .epilogue
    cmp     byte [rel mp_stdcall], 0
    je      .none
.epilogue:
    call    mt_collect                     ; (an operand: ret 8)
    test    rax, rax
    jnz     .done
    call    mb_begin
    ; the USES registers, last first
    mov     r14, [rel mp_nuses]
.pop:
    test    r14, r14
    jz      .popped
    dec     r14
    call    mb_line
    lea     rsi, [rel s_pop]
    call    mb_putz
    lea     rax, [rel mp_uses]
    mov     rsi, [rax + r14 * 8]
    call    mb_putz
    call    mb_nl
    jmp     .pop
.popped:
    cmp     byte [rel mp_frame], 0
    je      .no_leave
    call    mb_line
    lea     rsi, [rel s_leave]
    call    mb_putz
    call    mb_nl
.no_leave:
    call    mb_line
    lea     rsi, [rel s_ret]
    cmp     byte [rel mp_far], 0
    je      .ret_word
    lea     rsi, [rel s_retf]
.ret_word:
    call    mb_putz
    cmp     qword [rel mt_n], 0
    je      .no_operand
    lea     rsi, [rel s_space]
    call    mb_putz
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    call    mt_put
    jmp     .ret_done
.no_operand:
    ; stdcall (32-bit): its parameters' bytes
    cmp     byte [rel mp_stdcall], 0
    je      .ret_done
    mov     rax, [rel mp_args]
    test    rax, rax
    jz      .ret_done
    lea     rsi, [rel s_space]
    call    mb_putz
    call    mb_num
.ret_done:
    call    mb_nl
    mov     byte [rel mp_ret_raw], 1
    call    mb_push
.done:
    mov     rdx, rax
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- PROC ---------------------------------

; masm_proc: "NAME PROC ..." (r12 = NAME, the operands next)
masm_proc:
    mov     eax, EXIT_MASM_NESTED
    cmp     byte [rel mp_in], 0
    jne     .ret
    mov     byte [rel mp_in], 1
    mov     byte [rel mp_far], 0
    mov     byte [rel mp_frame], 0
    mov     byte [rel mp_stdcall], 0
    mov     byte [rel mp_ret_raw], 0
    mov     qword [rel mp_nuses], 0
    mov     qword [rel mp_spill], 0
    mov     qword [rel mp_args], 0
    mov     qword [rel mp_nnames], 0
    mov     [rel mp_name], r12
    call    m_new
    mov     [rel mp_id], rax
    call    mt_collect
    test    rax, rax
    jnz     .ret
    xor     r13d, r13d                     ; the token
    xor     r15d, r15d                     ; 1: PUBLIC
.attr:
    mov     rcx, r13
    call    mt_kind
    test    eax, eax
    jz      .attrs_done
    cmp     eax, TOK_COMMA
    je      .attrs_done
    cmp     eax, TOK_LABEL
    je      .attrs_done                    ; ("f PROC a:DWORD": no comma)
    cmp     eax, TOK_IDENT
    jne     .bad
    lea     rsi, [rel w_far]
    call    mt_is
    jne     .not_far
    mov     byte [rel mp_far], 1
    jmp     .attr_next
.not_far:
    lea     rsi, [rel w_stdcall]
    call    mt_is
    jne     .not_stdcall
    mov     byte [rel mp_stdcall], 1
    jmp     .attr_next
.not_stdcall:
    lea     rsi, [rel w_public]
    call    mt_is
    jne     .not_public
    mov     r15d, 1
    jmp     .attr_next
.not_public:
    lea     rsi, [rel w_uses]
    call    mt_is
    jne     .attr_other
    ; USES R1 R2 ... (to a comma or the end)
.uses:
    inc     r13
    mov     rcx, r13
    call    mt_kind
    cmp     eax, TOK_IDENT
    jne     .attr
    mov     rax, [rel mp_nuses]
    cmp     rax, MP_MAXU
    jae     .bad
    mov     rcx, r13
    call    mt_tok
    mov     rdx, [rax + TOKEN_value]
    mov     rax, [rel mp_nuses]
    lea     rcx, [rel mp_uses]
    mov     [rcx + rax * 8], rdx
    inc     qword [rel mp_nuses]
    jmp     .uses
.attr_other:
    ; NEAR, C, SYSCALL, PASCAL, PRIVATE, EXPORT: taken
.attr_next:
    inc     r13
    jmp     .attr
.attrs_done:
    ; the parameters, after the comma
    xor     r14d, r14d                     ; how many
    mov     rcx, r13
    call    mt_kind
    cmp     eax, TOK_COMMA
    jne     .params_split
    inc     r13
.params_split:
    mov     rcx, r13
    mov     rdx, [rel mt_n]
    call    mt_split
    mov     r14, [rel mx_cnt]
    ; a frame: with parameters, or LOCALs on the lines after
    test    r14, r14
    jnz     .framed
    call    masm_locals_next
    test    eax, eax
    jz      .head
.framed:
    mov     byte [rel mp_frame], 1
.head:
    call    mb_begin
    test    r15d, r15d
    jz      .label
    call    mb_line
    lea     rsi, [rel s_global]
    call    mb_putz
    mov     rsi, r12
    call    mb_putz
    call    mb_nl
.label:
    call    mb_line
    mov     rsi, r12
    call    mb_putz
    mov     al, ':'
    call    mb_putc
    call    mb_nl
    cmp     byte [rel mp_frame], 0
    je      .uses_push
    ; push rbp / mov rbp, rsp / sub rsp, ..@mN_f (its size known at ENDP)
    call    mb_line
    lea     rsi, [rel s_frame64]
    cmp     byte [rel asm_bits], 64
    je      .frame_text
    lea     rsi, [rel s_frame32]
.frame_text:
    call    mb_frame_lines
    call    mb_line
    lea     rsi, [rel s_subrsp]
    cmp     byte [rel asm_bits], 64
    je      .sub_text
    lea     rsi, [rel s_subesp]
.sub_text:
    call    mb_putz
    mov     rax, [rel mp_id]
    call    mb_lbl
    lea     rsi, [rel s_frame_n]
    call    mb_putz
    call    mb_nl
.uses_push:
    xor     r13d, r13d
.push_use:
    cmp     r13, [rel mp_nuses]
    jae     .params
    call    mb_line
    lea     rsi, [rel s_push]
    call    mb_putz
    lea     rax, [rel mp_uses]
    mov     rsi, [rax + r13 * 8]
    call    mb_putz
    call    mb_nl
    inc     r13
    jmp     .push_use
.params:
    call    masm_params
    test    rax, rax
    jnz     .ret
    call    mb_push
.ret:
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    ret

; mb_frame_lines: the two-line text rsi, each line numbered
mb_frame_lines:
.fl_next:
    mov     al, [rsi]
    test    al, al
    jz      .fl_end
    call    mb_putc
    inc     rsi
    cmp     al, 10
    jne     .fl_next
    call    mb_line
    jmp     .fl_next
.fl_end:
    jmp     mb_nl

; masm_params: the parameters in mx_*: their names %defined, the register
; ones copied into the frame. Output rax = OK or error
masm_params:
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r13d, r13d                     ; the parameter
    xor     r14d, r14d                     ; integer registers used
    xor     r15d, r15d                     ; vector registers used
    mov     qword [rel mp_args], 0         ; 32-bit: bytes so far / stack
.param:
    cmp     r13, [rel mx_cnt]
    jae     .done
    cmp     r13, MP_MAXP
    jae     .bad
    lea     rax, [rel mx_s]
    mov     rcx, [rax + r13 * 8]           ; its first token: the name
    lea     rax, [rel mx_n]
    mov     r12, [rax + r13 * 8]
    add     r12, rcx                       ; the part's end
    call    mt_kind
    mov     r10d, eax                      ; ("n:QWORD": a label, the colon read)
    cmp     eax, TOK_LABEL
    je      .named
    cmp     eax, TOK_IDENT
    jne     .bad
.named:
    push    rcx
    call    mt_tok
    mov     r8, [rax + TOKEN_value]        ; the name
    pop     rcx
    push    r8
    ; :TYPE
    inc     rcx
    mov     eax, 8
    cmp     byte [rel asm_bits], 64
    je      .default
    mov     eax, 4
.default:
    push    rax
    cmp     r10d, TOK_LABEL
    je      .type
    call    mt_kind
    cmp     eax, TOK_COLON
    jne     .typed
    inc     rcx
.type:
    call    mt_type
    test    eax, eax
    jz      .pop2_bad
    mov     [rsp], rax
.typed:
    pop     rax                            ; the type
    pop     r8                             ; the name
    cmp     eax, 0xFF
    je      .next                          ; (VARARG: nothing of its own)
    mov     r9d, eax
    and     r9d, 0x3F                      ; its size
    cmp     byte [rel asm_bits], 64
    jne     .stack32
    ; 64-bit: where it is
    cmp     byte [rel coff_enabled], 0
    jne     .win64
    test    eax, 0x40
    jnz     .sysv_float
    cmp     r14, 6
    jae     .sysv_stack
    ; a register: copied below rbp
    add     qword [rel mp_spill], 8
    call    mb_line
    lea     rsi, [rel s_movq]
    call    mb_putz
    lea     rsi, [rel s_minus]
    call    mb_putz
    mov     rax, [rel mp_spill]
    call    mb_num
    lea     rsi, [rel s_regto]
    call    mb_putz
    lea     rsi, [rel sysv64]
    mov     rcx, r14
    call    nth_word
    call    mb_putz
    call    mb_nl
    inc     r14
    mov     rax, [rel mp_spill]
    neg     rax
    jmp     .define
.sysv_float:
    cmp     r15, 8
    jae     .sysv_stack
    add     qword [rel mp_spill], 8
    call    mb_line
    lea     rsi, [rel s_movsd]
    cmp     r9d, 8
    je      .float_mov
    lea     rsi, [rel s_movss]
.float_mov:
    call    mb_putz
    lea     rsi, [rel s_minus]
    call    mb_putz
    mov     rax, [rel mp_spill]
    call    mb_num
    lea     rsi, [rel s_xmm]
    call    mb_putz
    mov     rax, r15
    call    mb_num
    call    mb_nl
    inc     r15
    mov     rax, [rel mp_spill]
    neg     rax
    jmp     .define
.sysv_stack:
    ; past the registers: above the return address
    mov     rax, [rel mp_args]
    add     rax, 16
    add     qword [rel mp_args], 8
    jmp     .define
.win64:
    ; parameter N's home: rbp + 16 + 8 N (its register stored there)
    lea     rax, [r13 * 8 + 16]
    cmp     r13, 4
    jae     .define
    push    rax
    call    mb_line
    lea     rsi, [rel s_movq]
    test    r9d, 0x40
    jz      .win_int
    lea     rsi, [rel s_movsd]
.win_int:
    call    mb_putz
    lea     rsi, [rel s_plus]
    call    mb_putz
    mov     rax, [rsp]
    call    mb_num
    test    r9d, 0x40
    jz      .win_reg
    lea     rsi, [rel s_xmm]
    call    mb_putz
    mov     rax, r13
    call    mb_num
    jmp     .win_done
.win_reg:
    lea     rsi, [rel s_regto]
    call    mb_putz
    lea     rsi, [rel win64]
    mov     rcx, r13
    call    nth_word
    call    mb_putz
.win_done:
    call    mb_nl
    pop     rax
    jmp     .define
.stack32:
    ; 32-bit: above the return address, each 4 bytes at least
    mov     rax, [rel mp_args]
    add     rax, 8
    lea     rcx, [r9 + 3]
    and     rcx, -4
    add     [rel mp_args], rcx
.define:
    ; %define NAME SIZE [rbp +/- N]
    call    masm_define_slot
.next:
    inc     r13
    jmp     .param
.done:
    xor     eax, eax
    jmp     .ret
.pop2_bad:
    add     rsp, 16
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; masm_define_slot: "%define NAME SIZE [rbp OFF]" (r8 = NAME, r9d = the
; size, rax = the offset from rbp, signed); NAME noted for ENDP's %undef
masm_define_slot:
    push    rax
    call    mb_line
    lea     rsi, [rel s_define]
    call    mb_putz
    mov     rsi, r8
    call    mb_putz
    mov     al, ' '
    call    mb_putc
    call    size_word
    call    mb_putz
    pop     rax
    test    rax, rax
    js      .ds_minus
    lea     rsi, [rel s_rbp_p]
    cmp     byte [rel asm_bits], 64
    je      .ds_base
    lea     rsi, [rel s_ebp_p]
    jmp     .ds_base
.ds_minus:
    neg     rax
    lea     rsi, [rel s_rbp_m]
    cmp     byte [rel asm_bits], 64
    je      .ds_base
    lea     rsi, [rel s_ebp_m]
.ds_base:
    call    mb_putz
    call    mb_num
    lea     rsi, [rel s_close]
    call    mb_putz
    call    mb_nl
    mov     rax, [rel mp_nnames]
    cmp     rax, MP_MAXN
    jae     .ds_ret
    lea     rcx, [rel mp_names]
    mov     [rcx + rax * 8], r8
    inc     qword [rel mp_nnames]
.ds_ret:
    ret

; size_word: rsi = NASM's size word for r9d bytes
size_word:
    lea     rsi, [rel size_words]
    cmp     r9d, 1
    je      .sw_ret
    add     rsi, 8
    cmp     r9d, 2
    je      .sw_ret
    add     rsi, 8
    cmp     r9d, 4
    je      .sw_ret
    add     rsi, 8
    cmp     r9d, 8
    je      .sw_ret
    add     rsi, 8
    cmp     r9d, 10
    je      .sw_ret
    add     rsi, 8
    cmp     r9d, 16
    je      .sw_ret
    add     rsi, 8
.sw_ret:
    ret

; nth_word: rsi = word rcx of the NUL-separated list rsi
nth_word:
    test    rcx, rcx
    jz      .nw_ret
.nw_skip:
    inc     rsi
    cmp     byte [rsi - 1], 0
    jne     .nw_skip
    dec     rcx
    jmp     nth_word
.nw_ret:
    ret

; masm_locals_next: do LOCAL lines come right after this one (the raw
; source, blank and comment lines passed)? eax = 1
masm_locals_next:
    push    r12
    mov     rax, [rbx + PREP_ctx]
    cmp     qword [rax + ASMCTX_mac_exp], 0
    jne     .ln_no
    mov     r12, [rbx + PREP_lexer]
    test    r12, r12
    jz      .ln_no
    mov     rdi, [r12 + LEXER_pos]
    ; at the next line already (the PROC line's newline read)?
    cmp     rdi, [r12 + LEXER_buf]
    jbe     .ln_eol
    cmp     byte [rdi - 1], 10
    je      .ln_blank
    ; past this line's end
.ln_eol:
    cmp     rdi, [r12 + LEXER_end]
    jae     .ln_no
    cmp     byte [rdi], 10
    je      .ln_line
    inc     rdi
    jmp     .ln_eol
.ln_line:
    inc     rdi
.ln_blank:
    cmp     rdi, [r12 + LEXER_end]
    jae     .ln_no
    movzx   eax, byte [rdi]
    cmp     eax, ' '
    je      .ln_skip
    cmp     eax, 9
    je      .ln_skip
    cmp     eax, 13
    je      .ln_skip
    cmp     eax, 10
    je      .ln_line
    cmp     eax, ';'
    je      .ln_eol                        ; (a comment line)
    ; "local" and a blank?
    lea     rcx, [rdi + 6]
    cmp     rcx, [r12 + LEXER_end]
    ja      .ln_no
    mov     eax, [rdi]
    or      eax, 0x20202020
    cmp     eax, 'loca'
    jne     .ln_no
    movzx   eax, byte [rdi + 4]
    or      eax, 0x20
    cmp     eax, 'l'
    jne     .ln_no
    movzx   eax, byte [rdi + 5]
    cmp     eax, ' '
    je      .ln_yes
    cmp     eax, 9
    jne     .ln_no
.ln_yes:
    mov     eax, 1
    pop     r12
    ret
.ln_skip:
    inc     rdi
    jmp     .ln_blank
.ln_no:
    xor     eax, eax
    pop     r12
    ret

; ---- LOCAL --------------------------------

; masm_local: "LOCAL A:TYPE, B[N]:TYPE ..." in the PROC open
masm_local:
    push    r12
    push    r13
    mov     eax, EXIT_MASM_FRAME
    cmp     byte [rel mp_frame], 0
    je      .lc_ret
    call    mt_collect
    test    rax, rax
    jnz     .lc_ret
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    call    mt_split
    call    mb_begin
    xor     r13d, r13d
.lc_part:
    cmp     r13, [rel mx_cnt]
    jae     .lc_done
    lea     rax, [rel mx_s]
    mov     rcx, [rax + r13 * 8]
    lea     rax, [rel mx_n]
    mov     r12, [rax + r13 * 8]
    add     r12, rcx
    call    mt_kind
    mov     r11d, eax                      ; ("acc:QWORD": a label)
    cmp     eax, TOK_LABEL
    je      .lc_named
    cmp     eax, TOK_IDENT
    jne     .lc_bad
.lc_named:
    push    rcx
    call    mt_tok
    mov     r8, [rax + TOKEN_value]
    pop     rcx
    inc     rcx
    ; [N]
    mov     r10d, 1                        ; the count
    cmp     r11d, TOK_LABEL
    je      .lc_type
    call    mt_kind
    cmp     eax, TOK_LBRACKET
    jne     .lc_type
    inc     rcx
    push    r8
    call    mt_tok
    pop     r8
    cmp     byte [rax + TOKEN_kind], TOK_NUMBER
    jne     .lc_bad
    push    rcx
    push    r8
    mov     rdi, [rax + TOKEN_value]
    extern  str_to_int
    call    str_to_int
    pop     r8
    pop     rcx
    test    rax, rax
    jnz     .lc_bad
    mov     r10, rdx
    inc     rcx
    call    mt_kind
    cmp     eax, TOK_RBRACKET
    jne     .lc_bad
    inc     rcx
    mov     r11d, TOK_IDENT
.lc_type:
    mov     eax, 8
    cmp     byte [rel asm_bits], 64
    je      .lc_default
    mov     eax, 4
.lc_default:
    push    rax
    cmp     r11d, TOK_LABEL
    je      .lc_typename
    call    mt_kind
    cmp     eax, TOK_COLON
    jne     .lc_typed
    inc     rcx
.lc_typename:
    push    r8
    push    r10
    call    mt_type
    pop     r10
    pop     r8
    test    eax, eax
    jz      .lc_pop_bad
    mov     [rsp], rax
.lc_typed:
    pop     rax
    mov     r9d, eax
    and     r9d, 0x3F
    ; the slot: its bytes, aligned to its size (8 at most)
    mov     rax, r9
    imul    rax, r10
    add     rax, [rel mp_spill]
    mov     rcx, r9
    cmp     rcx, 8
    jbe     .lc_align
    mov     ecx, 8
.lc_align:
    dec     rcx
    add     rax, rcx
    not     rcx
    and     rax, rcx
    mov     [rel mp_spill], rax
    neg     rax
    call    masm_define_slot
    inc     r13
    jmp     .lc_part
.lc_done:
    call    mb_push
    jmp     .lc_ret
.lc_pop_bad:
    add     rsp, 8
.lc_bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.lc_ret:
    pop     r13
    pop     r12
    ret

; ---- ENDP ---------------------------------

; masm_endp: "NAME ENDP" (r12 = NAME)
masm_endp:
    mov     eax, EXIT_MASM_STRAY
    cmp     byte [rel mp_in], 0
    je      .ret
    mov     rdi, r12
    mov     rsi, [rel mp_name]
    call    m_streq_ci
    mov     eax, EXIT_MASM_ENDP
    jne     .ret
    call    mt_collect
    test    rax, rax
    jnz     .ret
    mov     byte [rel mp_in], 0
    call    mb_begin
    ; the frame's size: the slots, 16-aligned with the USES pushes (System
    ; V's rsp at a call); 4-aligned in 32-bit code
    cmp     byte [rel mp_frame], 0
    je      .undefs
    call    mb_line
    mov     rax, [rel mp_id]
    call    mb_lbl
    lea     rsi, [rel s_frame_n]
    call    mb_putz
    lea     rsi, [rel s_equ]
    call    mb_putz
    mov     rax, [rel mp_spill]
    cmp     byte [rel asm_bits], 64
    jne     .align4
    add     rax, 15
    and     rax, -16
    test    qword [rel mp_nuses], 1
    jz      .sized
    add     rax, 8
    jmp     .sized
.align4:
    add     rax, 3
    and     rax, -4
.sized:
    call    mb_num
    call    mb_nl
.undefs:
    xor     ecx, ecx
.undef:
    cmp     rcx, [rel mp_nnames]
    jae     .push
    call    mb_line
    lea     rsi, [rel s_undef]
    call    mb_putz
    lea     rax, [rel mp_names]
    mov     rsi, [rax + rcx * 8]
    call    mb_putz
    call    mb_nl
    inc     rcx
    jmp     .undef
.push:
    call    mb_push
.ret:
    ret

; m_streq_ci: rdi and rsi the same name in any case? ZF
m_streq_ci:
.ci_next:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    cmp     eax, 'A'
    jb      .ci_a
    cmp     eax, 'Z'
    ja      .ci_a
    or      eax, 0x20
.ci_a:
    cmp     ecx, 'A'
    jb      .ci_b
    cmp     ecx, 'Z'
    ja      .ci_b
    or      ecx, 0x20
.ci_b:
    cmp     eax, ecx
    jne     .ci_ret
    test    eax, eax
    jz      .ci_ret
    inc     rdi
    inc     rsi
    jmp     .ci_next
.ci_ret:
    ret

; ---- INVOKE -------------------------------

; masm_invoke: "INVOKE F, A1, A2 ..."
masm_invoke:
    push    r12
    push    r13
    push    r14
    push    r15
    call    mt_collect
    test    rax, rax
    jnz     .ret
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    call    mt_split
    mov     r12, [rel mx_cnt]
    mov     eax, EXIT_UNEXPECTED_TOKEN
    test    r12, r12
    jz      .ret
    dec     r12                            ; the arguments
    call    mb_begin
    ; how many go on the stack (past the registers)
    mov     r13d, 6
    cmp     byte [rel coff_enabled], 0
    je      .regs_n
    mov     r13d, 4
.regs_n:
    cmp     byte [rel asm_bits], 64
    je      .have_regs
    xor     r13d, r13d                     ; 32-bit: all on the stack
.have_regs:
    xor     r15d, r15d                     ; the stack's bytes
    mov     rax, r12
    sub     rax, r13
    jbe     .no_stack
    mov     r14, rax                       ; stack arguments
    cmp     byte [rel asm_bits], 64
    jne     .push_args
    ; (System V / Win64: the stack 16-aligned at the call)
    test    r14, 1
    jz      .push_args
    call    mb_line
    lea     rsi, [rel s_sub8]
    call    mb_putz
    call    mb_nl
    add     r15, 8
.push_args:
    ; the last first
    mov     r14, r12
.push_arg:
    cmp     r14, r13
    jbe     .no_stack
    mov     rcx, r14                       ; part r14 (argument r14 - 1)
    call    .part
    call    mb_line
    lea     rsi, [rel s_push]
    call    mb_putz
    cmp     byte [rel asm_bits], 64
    jne     .push_text
    call    mt_reg
    test    eax, eax
    jz      .push_text
    cmp     eax, 64
    je      .push_text
    ; (push eax in 64-bit code: push rax - its upper half the same)
    lea     rsi, [rel r64names]
    push    rcx
    mov     ecx, r8d
    call    nth_word
    pop     rcx
    call    mb_putz
    jmp     .push_done
.push_text:
    call    mt_put
.push_done:
    call    mb_nl
    mov     eax, 8
    cmp     byte [rel asm_bits], 64
    je      .pushed
    mov     eax, 4
.pushed:
    add     r15, rax
    dec     r14
    jmp     .push_arg
.no_stack:
    ; the registers, in order (one an earlier one took: an error)
    xor     r14d, r14d
    mov     qword [rel mi_taken], 0
.reg_arg:
    cmp     r14, r12
    jae     .regs_done
    cmp     r14, r13
    jae     .regs_done
    lea     rcx, [r14 + 1]
    call    .part
    call    masm_arg
    test    rax, rax
    jnz     .ret
    inc     r14
    jmp     .reg_arg
.regs_done:
    cmp     byte [rel coff_enabled], 0
    je      .no_shadow
    cmp     byte [rel asm_bits], 64
    jne     .no_shadow
    call    mb_line
    lea     rsi, [rel s_sub32]
    call    mb_putz
    call    mb_nl
    add     r15, 32
.no_shadow:
    ; al = 0 (System V's count of vector arguments) unless F is rax
    cmp     byte [rel asm_bits], 64
    jne     .call
    cmp     byte [rel coff_enabled], 0
    jne     .call
    xor     ecx, ecx
    call    .part
    call    mt_reg
    test    eax, eax
    jz      .zero_al
    test    r8d, r8d
    jz      .call
.zero_al:
    call    mb_line
    lea     rsi, [rel s_xoreax]
    call    mb_putz
    call    mb_nl
.call:
    call    mb_line
    lea     rsi, [rel s_call]
    call    mb_putz
    xor     ecx, ecx
    call    .part
    call    mt_put
    call    mb_nl
    test    r15, r15
    jz      .pushed_back
    call    mb_line
    lea     rsi, [rel s_addrsp]
    cmp     byte [rel asm_bits], 64
    je      .add_text
    lea     rsi, [rel s_addesp]
.add_text:
    call    mb_putz
    mov     rax, r15
    call    mb_num
    call    mb_nl
.pushed_back:
    call    mb_push
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
; .part: part rcx's tokens: rcx = first, rdx = past its last
.part:
    lea     rax, [rel mx_s]
    mov     rdx, [rax + rcx * 8]
    lea     rax, [rel mx_n]
    mov     rax, [rax + rcx * 8]
    mov     rcx, rdx
    add     rdx, rax
    ret

; masm_arg: argument r14 (its tokens [rcx, rdx)) into its register
; Output rax = OK or EXIT_INVOKE_CLOBBER
masm_arg:
    push    r12
    push    r13
    mov     r12, rcx
    mov     r13, rdx
    ; its register's names
    lea     rsi, [rel sysv64]
    lea     rdi, [rel sysv32]
    lea     r10, [rel sysvnum]
    cmp     byte [rel coff_enabled], 0
    je      .names
    lea     rsi, [rel win64]
    lea     rdi, [rel win32]
    lea     r10, [rel winnum]
.names:
    movzx   r11d, byte [r10 + r14]         ; its number
    mov     rcx, r14
    call    nth_word
    mov     [rel mi_r64], rsi
    mov     rsi, rdi
    mov     rcx, r14
    call    nth_word
    mov     [rel mi_r32], rsi
    ; read from a register an earlier one was loaded into?
    mov     rcx, r12
    mov     rdx, r13
    call    mt_reg
    test    eax, eax
    jz      .not_reg
    bt      qword [rel mi_taken], r8
    jc      .clobber
    ; the register itself: nothing to do
    cmp     r8d, r11d
    jne     .reg_move
    cmp     eax, 64
    je      .taken
.reg_move:
    cmp     eax, 32
    je      .mov32
    cmp     eax, 64
    je      .mov64
    jmp     .movzx                         ; (8 / 16)
.not_reg:
    ; ADDR X: its address
    mov     rcx, r12
    lea     rsi, [rel w_addr]
    call    mt_is
    je      .addr
    ; a size first: memory of that size
    call    mt_kind
    cmp     eax, TOK_IDENT
    jne     .mov64
    mov     rcx, r12
    call    mt_tok
    mov     rdi, [rax + TOKEN_value]
    lea     rsi, [rel size_words]
    call    str_cmp_kw
    test    rax, rax
    jz      .movzx
    mov     rcx, r12
    call    mt_tok
    mov     rdi, [rax + TOKEN_value]
    lea     rsi, [rel size_words + 8]
    call    str_cmp_kw
    test    rax, rax
    jz      .movzx
    mov     rcx, r12
    call    mt_tok
    mov     rdi, [rax + TOKEN_value]
    lea     rsi, [rel size_words + 16]
    call    str_cmp_kw
    test    rax, rax
    jz      .mov32
.mov64:
    call    mb_line
    lea     rsi, [rel s_mov]
    call    mb_putz
    mov     rsi, [rel mi_r64]
    jmp     .operand
.mov32:
    call    mb_line
    lea     rsi, [rel s_mov]
    call    mb_putz
    mov     rsi, [rel mi_r32]
    jmp     .operand
.movzx:
    call    mb_line
    lea     rsi, [rel s_movzx]
    call    mb_putz
    mov     rsi, [rel mi_r32]
.operand:
    call    mb_putz
    lea     rsi, [rel s_comma]
    call    mb_putz
    mov     rcx, r12
    mov     rdx, r13
    call    mt_put
    call    mb_nl
    jmp     .taken
.addr:
    ; lea REG, [X] - X a memory operand (its size word dropped) or a label
    call    mb_line
    lea     rsi, [rel s_lea]
    call    mb_putz
    mov     rsi, [rel mi_r64]
    call    mb_putz
    lea     rcx, [r12 + 1]
    ; a size word: skip it
    push    rcx
    call    mt_tok
    mov     rdi, [rax + TOKEN_value]
    cmp     byte [rax + TOKEN_kind], TOK_IDENT
    pop     rcx
    jne     .addr_mem
    push    rcx
    lea     r8, [rel size_words]
    mov     r9d, 7
.addr_size:
    mov     rsi, r8
    push    rdi
    push    r8
    push    r9
    call    str_cmp_kw
    pop     r9
    pop     r8
    pop     rdi
    test    rax, rax
    jz      .addr_sized
    add     r8, 8
    dec     r9d
    jnz     .addr_size
    pop     rcx
    jmp     .addr_mem
.addr_sized:
    pop     rcx
    inc     rcx
.addr_mem:
    call    mt_kind
    cmp     eax, TOK_LBRACKET
    jne     .addr_label
    lea     rsi, [rel s_comma]
    call    mb_putz
    mov     rdx, r13
    call    mt_put
    jmp     .addr_done
.addr_label:
    lea     rsi, [rel s_rel]
    cmp     byte [rel asm_bits], 64
    je      .addr_open
    lea     rsi, [rel s_brk]
.addr_open:
    call    mb_putz
    mov     rdx, r13
    call    mt_put
    lea     rsi, [rel s_close]
    call    mb_putz
.addr_done:
    call    mb_nl
.taken:
    bts     qword [rel mi_taken], r11
    xor     eax, eax
    pop     r13
    pop     r12
    ret
.clobber:
    mov     eax, EXIT_INVOKE_CLOBBER
    pop     r13
    pop     r12
    ret

; ---- .IF & co -----------------------------

; mk_top: rax = the block on top (0 none)
mk_top:
    mov     rax, [rel mk_n]
    test    rax, rax
    jz      .t_ret
    dec     rax
    imul    rax, rax, K_SIZE
    push    rcx
    lea     rcx, [rel mk]
    add     rax, rcx
    pop     rcx
.t_ret:
    ret

; mk_push: a new block of kind edi: rax = it (0: too deep)
mk_push:
    mov     rax, [rel mk_n]
    cmp     rax, MK_MAX
    jae     .mp_deep
    test    rax, rax
    jnz     .mp_noted
    mov     rcx, [rel error_loc_file]
    mov     [rel mk_file], rcx
    mov     ecx, [rel error_loc_line]
    mov     [rel mk_line], ecx
.mp_noted:
    inc     qword [rel mk_n]
    call    mk_top
    mov     [rax + K_kind], rdi
    mov     qword [rax + K_else], 0
    mov     qword [rax + K_cond], 0
    ret
.mp_deep:
    xor     eax, eax
    ret

masm_if:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    mov     edi, MK_IF
    call    mk_push
    test    rax, rax
    jz      .deep
    mov     r12, rax
    call    m_new
    mov     [r12 + K_end], rax
    call    m_new
    mov     [r12 + K_a], rax               ; the next part's
    call    mb_begin
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    mov     r8, [r12 + K_a]
    xor     r9d, r9d                       ; (jump when false)
    call    mc_jump
    test    rax, rax
    jnz     .ret
    call    mb_push
.ret:
    pop     r12
    ret
.deep:
    mov     eax, EXIT_COND_DEPTH
    pop     r12
    ret

masm_elseif:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    call    mk_top
    test    rax, rax
    jz      .stray
    cmp     qword [rax + K_kind], MK_IF
    jne     .stray
    cmp     qword [rax + K_else], 0
    jne     .stray
    mov     r12, rax
    call    mb_begin
    call    mb_line
    lea     rsi, [rel s_jmp]
    mov     rax, [r12 + K_end]
    call    mb_jcc_noline
    mov     rax, [r12 + K_a]
    call    mb_def
    call    m_new
    mov     [r12 + K_a], rax
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    mov     r8, rax
    xor     r9d, r9d
    call    mc_jump
    test    rax, rax
    jnz     .ret
    call    mb_push
.ret:
    pop     r12
    ret
.stray:
    lea     rdi, [rel w_elseif]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     r12
    ret

; mb_jcc_noline: "JCC LABEL" on the line begun (rsi, rax)
mb_jcc_noline:
    call    mb_putz
    call    mb_lbl
    jmp     mb_nl

masm_else:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    call    mk_top
    test    rax, rax
    jz      .stray
    cmp     qword [rax + K_kind], MK_IF
    jne     .stray
    cmp     qword [rax + K_else], 0
    jne     .stray
    mov     r12, rax
    mov     qword [r12 + K_else], 1
    call    mb_begin
    call    mb_line
    lea     rsi, [rel s_jmp]
    mov     rax, [r12 + K_end]
    call    mb_jcc_noline
    mov     rax, [r12 + K_a]
    call    mb_def
    mov     qword [r12 + K_a], 0
    call    mb_push
.ret:
    pop     r12
    ret
.stray:
    lea     rdi, [rel w_else]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     r12
    ret

masm_endif:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    call    mk_top
    test    rax, rax
    jz      .stray
    cmp     qword [rax + K_kind], MK_IF
    jne     .stray
    mov     r12, rax
    call    mb_begin
    mov     rax, [r12 + K_a]
    test    rax, rax
    jz      .no_next
    call    mb_def
.no_next:
    mov     rax, [r12 + K_end]
    call    mb_def
    dec     qword [rel mk_n]
    call    mb_push
.ret:
    pop     r12
    ret
.stray:
    lea     rdi, [rel w_endif]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     r12
    ret

; .WHILE C: jmp test / top: ... / test: (C) jumps to top / end:
masm_while:
    push    r12
    push    r13
    call    mt_collect
    test    rax, rax
    jnz     .ret
    mov     edi, MK_WHILE
    call    mk_push
    test    rax, rax
    jz      .deep
    mov     r12, rax
    call    m_new
    mov     [r12 + K_end], rax
    call    m_new
    mov     [r12 + K_a], rax               ; the top
    call    m_new
    mov     [r12 + K_b], rax               ; the test
    ; the test's code, kept for .ENDW
    call    mb_begin
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    mov     r8, [r12 + K_a]
    mov     r9d, 1                         ; (jump when true)
    call    mc_jump
    test    rax, rax
    jnz     .ret
    call    mb_keep
    test    rax, rax
    jnz     .ret
    mov     [r12 + K_cond], rdx
    call    mb_begin
    call    mb_line
    lea     rsi, [rel s_jmp]
    mov     rax, [r12 + K_b]
    call    mb_jcc_noline
    mov     rax, [r12 + K_a]
    call    mb_def
    call    mb_push
.ret:
    pop     r13
    pop     r12
    ret
.deep:
    mov     eax, EXIT_COND_DEPTH
    jmp     .ret

; mb_keep: the text built (past its first newline) copied into the arena:
; rdx = it (NUL-terminated). Output rax = OK or error
mb_keep:
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rel mb_len]
    inc     rsi
    extern  arena_alloc
    call    arena_alloc
    test    rax, rax
    jnz     .k_ret
    push    rdx
    mov     rdi, rdx
    mov     rsi, [rel mb_buf]
    inc     rsi
    mov     rcx, [rel mb_len]
    dec     rcx
    rep movsb
    mov     byte [rdi], 0
    pop     rdx
    xor     eax, eax
.k_ret:
    ret

masm_endw:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    call    mk_top
    test    rax, rax
    jz      .stray
    cmp     qword [rax + K_kind], MK_WHILE
    jne     .stray
    mov     r12, rax
    call    mb_begin
    mov     rax, [r12 + K_b]
    call    mb_def
    mov     rsi, [r12 + K_cond]
    call    mb_putz
    mov     rax, [r12 + K_end]
    call    mb_def
    dec     qword [rel mk_n]
    call    mb_push
.ret:
    pop     r12
    ret
.stray:
    lea     rdi, [rel w_endw]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     r12
    ret

; .REPEAT: top: ... / .UNTIL C: continue: (not C) jumps to top / end:
masm_repeat:
    push    r12
    call    mt_collect
    test    rax, rax
    jnz     .ret
    mov     edi, MK_REPEAT
    call    mk_push
    test    rax, rax
    jz      .deep
    mov     r12, rax
    call    m_new
    mov     [r12 + K_end], rax
    call    m_new
    mov     [r12 + K_a], rax               ; the top
    call    m_new
    mov     [r12 + K_b], rax               ; .CONTINUE's
    call    mb_begin
    mov     rax, [r12 + K_a]
    call    mb_def
    call    mb_push
.ret:
    pop     r12
    ret
.deep:
    mov     eax, EXIT_COND_DEPTH
    pop     r12
    ret

; masm_until: esi = 0 .UNTIL C, 1 .UNTILCXZ (loop top)
masm_until:
    push    r12
    push    r13
    mov     r13d, esi
    call    mt_collect
    test    rax, rax
    jnz     .ret
    call    mk_top
    test    rax, rax
    jz      .stray
    cmp     qword [rax + K_kind], MK_REPEAT
    jne     .stray
    mov     r12, rax
    call    mb_begin
    mov     rax, [r12 + K_b]
    call    mb_def
    test    r13d, r13d
    jnz     .cxz
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    mov     r8, [r12 + K_a]
    xor     r9d, r9d                       ; (back to the top when false)
    call    mc_jump
    test    rax, rax
    jnz     .ret
    jmp     .end
.cxz:
    call    mb_line
    lea     rsi, [rel s_loop]
    mov     rax, [r12 + K_a]
    call    mb_jcc_noline
.end:
    mov     rax, [r12 + K_end]
    call    mb_def
    dec     qword [rel mk_n]
    call    mb_push
.ret:
    pop     r13
    pop     r12
    ret
.stray:
    lea     rdi, [rel w_until]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    pop     r13
    pop     r12
    ret

; masm_break: esi = 0 .BREAK, 1 .CONTINUE - [.IF C]
masm_break:
    push    r12
    push    r13
    mov     r13d, esi
    call    mt_collect
    test    rax, rax
    jnz     .ret
    ; the loop innermost
    mov     rcx, [rel mk_n]
.find:
    test    rcx, rcx
    jz      .stray
    dec     rcx
    imul    rax, rcx, K_SIZE
    lea     rdx, [rel mk]
    add     rax, rdx
    cmp     qword [rax + K_kind], MK_IF
    je      .find
    mov     r12, rax
    mov     r8, [r12 + K_end]
    test    r13d, r13d
    jz      .target
    mov     r8, [r12 + K_b]                ; (the test / .UNTIL's)
.target:
    push    r8
    call    mb_begin
    pop     r8
    cmp     qword [rel mt_n], 0
    je      .always
    ; .IF C
    xor     ecx, ecx
    lea     rsi, [rel w_if]
    call    mt_is
    jne     .bad
    mov     ecx, 1
    mov     rdx, [rel mt_n]
    mov     r9d, 1
    call    mc_jump
    test    rax, rax
    jnz     .ret
    jmp     .push
.always:
    call    mb_line
    lea     rsi, [rel s_jmp]
    mov     rax, r8
    call    mb_jcc_noline
.push:
    call    mb_push
.ret:
    pop     r13
    pop     r12
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret
.stray:
    lea     rdi, [rel w_break]
    test    r13d, r13d
    jz      .stray_named
    lea     rdi, [rel w_continue]
.stray_named:
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    jmp     .ret

; ---- the conditions -----------------------
;
; mc_jump: the code of the condition in tokens [rcx, rdx) that jumps to
; label r8 when it is r9d (1 true, 0 false), and falls through otherwise.
; Output rax = OK or error
;
mc_jump:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rcx
    mov     r13, rdx
    mov     r14, r8
    mov     r15d, r9d
    mov     eax, EXIT_INVALID_EXPR
    cmp     r12, r13
    jae     .ret
    ; A || B at the top level
    mov     edi, TOK_OR
    call    mc_find
    test    rax, rax
    jns     .or
    mov     edi, TOK_AND
    call    mc_find
    test    rax, rax
    jns     .and
    ; !A
    mov     rcx, r12
    call    mt_kind
    cmp     eax, TOK_NOT
    jne     .not_not
    lea     rcx, [r12 + 1]
    mov     rdx, r13
    mov     r8, r14
    mov     r9d, r15d
    xor     r9d, 1
    call    mc_jump
    jmp     .ret
.not_not:
    ; (A) as a whole
    cmp     eax, TOK_LPAREN
    jne     .leaf
    mov     rcx, r12
    call    mt_close
    lea     rax, [rcx + 1]
    cmp     rax, r13
    jne     .leaf
    lea     rcx, [r12 + 1]
    lea     rdx, [r13 - 1]
    mov     r8, r14
    mov     r9d, r15d
    call    mc_jump
    jmp     .ret
.or:
    ; true: A to L, B to L; false: A to M (true), B to L (false), M:
    push    rax
    test    r15d, r15d
    jz      .or_false
    mov     rcx, r12
    mov     rdx, [rsp]
    mov     r8, r14
    mov     r9d, 1
    call    mc_jump
    test    rax, rax
    jnz     .pop_ret
    pop     rcx
    inc     rcx
    mov     rdx, r13
    mov     r8, r14
    mov     r9d, 1
    call    mc_jump
    jmp     .ret
.or_false:
    call    m_new
    push    rax                            ; M
    mov     rcx, r12
    mov     rdx, [rsp + 8]
    mov     r8, rax
    mov     r9d, 1
    call    mc_jump
    test    rax, rax
    jnz     .pop2_ret
    mov     rcx, [rsp + 8]
    inc     rcx
    mov     rdx, r13
    mov     r8, r14
    xor     r9d, r9d
    call    mc_jump
    test    rax, rax
    jnz     .pop2_ret
    pop     rax
    call    mb_def
    add     rsp, 8
    xor     eax, eax
    jmp     .ret
.and:
    ; false: A to L, B to L; true: A to M (false), B to L (true), M:
    push    rax
    test    r15d, r15d
    jnz     .and_true
    mov     rcx, r12
    mov     rdx, [rsp]
    mov     r8, r14
    xor     r9d, r9d
    call    mc_jump
    test    rax, rax
    jnz     .pop_ret
    pop     rcx
    inc     rcx
    mov     rdx, r13
    mov     r8, r14
    xor     r9d, r9d
    call    mc_jump
    jmp     .ret
.and_true:
    call    m_new
    push    rax
    mov     rcx, r12
    mov     rdx, [rsp + 8]
    mov     r8, rax
    xor     r9d, r9d
    call    mc_jump
    test    rax, rax
    jnz     .pop2_ret
    mov     rcx, [rsp + 8]
    inc     rcx
    mov     rdx, r13
    mov     r8, r14
    mov     r9d, 1
    call    mc_jump
    test    rax, rax
    jnz     .pop2_ret
    pop     rax
    call    mb_def
    add     rsp, 8
    xor     eax, eax
    jmp     .ret
.leaf:
    call    mc_leaf
    jmp     .ret
.pop2_ret:
    add     rsp, 8
.pop_ret:
    add     rsp, 8
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; mc_find: the first token of kind edi in [r12, r13) outside brackets: rax
; (-1 none)
mc_find:
    mov     rcx, r12
    xor     edx, edx
.f_tok:
    cmp     rcx, r13
    jae     .f_none
    call    mt_kind
    cmp     eax, TOK_LPAREN
    je      .f_in
    cmp     eax, TOK_LBRACKET
    je      .f_in
    cmp     eax, TOK_RPAREN
    je      .f_out
    cmp     eax, TOK_RBRACKET
    je      .f_out
    test    edx, edx
    jnz     .f_step
    cmp     eax, edi
    jne     .f_step
    mov     rax, rcx
    ret
.f_in:
    inc     edx
    jmp     .f_step
.f_out:
    dec     edx
.f_step:
    inc     rcx
    jmp     .f_tok
.f_none:
    mov     rax, -1
    ret

; mc_leaf: A OP B, A & B, A, or a flag word in [r12, r13): its compare and
; the jump to r14 when r15d
mc_leaf:
    ; a flag word alone
    lea     rax, [r12 + 1]
    cmp     rax, r13
    jne     .compare
    mov     rcx, r12
    lea     rsi, [rel w_zero]
    lea     r10, [rel j_z]
    lea     r11, [rel j_nz]
    call    mt_is
    je      .flag
    lea     rsi, [rel w_carry]
    lea     r10, [rel j_c]
    lea     r11, [rel j_nc]
    call    mt_is
    je      .flag
    lea     rsi, [rel w_sign]
    lea     r10, [rel j_s]
    lea     r11, [rel j_ns]
    call    mt_is
    je      .flag
    lea     rsi, [rel w_overflow]
    lea     r10, [rel j_o]
    lea     r11, [rel j_no]
    call    mt_is
    je      .flag
    lea     rsi, [rel w_parity]
    lea     r10, [rel j_p]
    lea     r11, [rel j_np]
    call    mt_is
    je      .flag
.compare:
    ; the operator: == != < <= > >= or &
    xor     ecx, ecx                       ; which
    mov     edi, TOK_EQUAL
    call    mc_find_c
    jns     .op
    mov     ecx, 1
    mov     edi, TOK_NEQUAL
    call    mc_find_c
    jns     .op
    mov     ecx, 3
    mov     edi, TOK_LE
    call    mc_find_c
    jns     .op
    mov     ecx, 5
    mov     edi, TOK_GE
    call    mc_find_c
    jns     .op
    mov     ecx, 2
    mov     edi, TOK_LT
    call    mc_find_c
    jns     .op
    mov     ecx, 4
    mov     edi, TOK_GT
    call    mc_find_c
    jns     .op
    mov     edi, TOK_AMPERSAND
    call    mc_find_c
    jns     .test
    ; A alone: not zero (test a register, cmp anything else with 0)
    mov     rcx, r12
    mov     rdx, r13
    call    mt_reg
    test    eax, eax
    jz      .alone_cmp
    call    mb_line
    lea     rsi, [rel s_test]
    call    mb_putz
    mov     rcx, r12
    mov     rdx, r13
    call    mt_put
    lea     rsi, [rel s_comma]
    call    mb_putz
    mov     rcx, r12
    mov     rdx, r13
    call    mt_put
    call    mb_nl
    jmp     .nz
.alone_cmp:
    call    mb_line
    lea     rsi, [rel s_cmp]
    call    mb_putz
    call    mc_operand
    lea     rsi, [rel s_zero]
    call    mb_putz
    call    mb_nl
.nz:
    lea     rsi, [rel j_nz]
    lea     rdi, [rel j_z]
    jmp     .flag_jump
.test:
    ; A & B: test A, B - true when not zero
    push    rax
    call    mb_line
    lea     rsi, [rel s_test]
    call    mb_putz
    mov     rdx, [rsp]
    call    mc_side_a
    lea     rsi, [rel s_comma]
    call    mb_putz
    pop     rcx
    inc     rcx
    mov     rdx, r13
    call    mc_side
    call    mb_nl
    jmp     .nz
.op:
    ; cmp A, B; the jump by the operator, signed when a side is
    push    rcx
    push    rax
    mov     byte [rel mc_signed], 0
    call    mb_line
    lea     rsi, [rel s_cmp]
    call    mb_putz
    mov     rdx, [rsp]
    call    mc_side_a
    lea     rsi, [rel s_comma]
    call    mb_putz
    pop     rcx
    inc     rcx
    mov     rdx, r13
    call    mc_side
    call    mb_nl
    pop     rcx                            ; the operator
    lea     rax, [rel jt_u]
    lea     rdx, [rel jf_u]
    cmp     byte [rel mc_signed], 0
    je      .table
    lea     rax, [rel jt_s]
    lea     rdx, [rel jf_s]
.table:
    test    r15d, r15d
    jnz     .true_table
    mov     rax, rdx
.true_table:
    mov     rsi, [rax + rcx * 8]
    mov     rax, r14
    call    mb_jcc
    xor     eax, eax
    ret
.flag:
    mov     rsi, r10
    mov     rdi, r11
.flag_jump:
    test    r15d, r15d
    jnz     .flag_true
    mov     rsi, rdi
.flag_true:
    mov     rax, r14
    call    mb_jcc
    xor     eax, eax
    ret

; mc_find_c: mc_find keeping rcx (the operator's number); SF clear found
mc_find_c:
    push    rcx
    call    mc_find
    pop     rcx
    test    rax, rax
    ret

; mc_side_a: the left side [r12, rdx)
mc_side_a:
    mov     rcx, r12
; mc_side: one side's text, [rcx, rdx): an sbyte / sword / sdword /
; sqword first makes the compare signed (written as byte / word / ...)
mc_side:
    push    r12
    push    r13
    mov     r12, rcx
    mov     r13, rdx
    call    mt_kind
    cmp     eax, TOK_IDENT
    jne     .whole
    mov     rcx, r12
    call    mt_tok
    mov     rdi, [rax + TOKEN_value]
    movzx   eax, byte [rdi]
    or      eax, 0x20
    cmp     eax, 's'
    jne     .whole
    lea     rdi, [rdi + 1]
    lea     rsi, [rel size_words]
    mov     ecx, 4
.signed_word:
    push    rdi
    push    rsi
    push    rcx
    call    str_cmp_kw
    pop     rcx
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .signed
    add     rsi, 8
    dec     ecx
    jnz     .signed_word
    jmp     .whole
.signed:
    mov     byte [rel mc_signed], 1
    inc     r12
    ; "sdword ptr eax": the register itself, compared signed
    mov     rcx, r12
    push    rsi
    lea     rsi, [rel w_ptr]
    call    mt_is
    je      .signed_ptr
    lea     rsi, [rel w_ptr2]
    call    mt_is
    jne     .signed_kept
.signed_ptr:
    inc     r12
.signed_kept:
    pop     rsi
    mov     rcx, r12
    mov     rdx, r13
    call    mt_reg
    test    eax, eax
    jnz     .whole                         ; (a register: no size)
    call    mb_putz                        ; (byte / word / dword / qword)
    mov     al, ' '
    call    mb_putc
.whole:
    mov     rcx, r12
    mov     rdx, r13
    call    mt_put
    pop     r13
    pop     r12
    ret

; mc_operand: [r12, r13)'s text (for "cmp A, 0")
mc_operand:
    mov     rcx, r12
    mov     rdx, r13
    jmp     mc_side

; ---- masm_finish --------------------------
;
; masm_finish
; The source read: a PROC or a block still open is an error.
; Output   : rax = OK or an error
;
global masm_finish
masm_finish:
    xor     eax, eax
    cmp     qword [rel mk_n], 0
    je      .procs
    mov     rax, [rel mk_file]
    mov     [rel error_loc_file], rax
    mov     eax, [rel mk_line]
    mov     [rel error_loc_line], eax
    mov     qword [rel mk_n], 0
    mov     eax, EXIT_MASM_OPEN
    ret
.procs:
    cmp     byte [rel mp_in], 0
    je      .ret
    mov     byte [rel mp_in], 0
    mov     rdi, [rel mp_name]
    call    error_set_subject
    mov     eax, EXIT_MASM_PROC_OPEN
.ret:
    ret

[SECTION .bss]
mi_taken:       resq 1              ; INVOKE: the registers loaded (bits)
mi_r64:         resq 1
mi_r32:         resq 1
mc_signed:      resb 1
