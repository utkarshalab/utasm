;
; ============================================
; File     : frontend/parser/att.s
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
; AT&T SYNTAX (.att_syntax, --att)
; ============================================================================
; GNU as's own syntax, read as GNU as reads it. Each statement is turned
; into utasm's and read from there (prep_push_buffer, numbered as the line
; that made it), so the encoder, the diagnostics and the listing are the
; ones every other syntax has:
;
;   movl $5, -4(%rbp,%rcx,4)     mov dword [rbp + rcx*4 + (-4)], 5
;   leaq .LC0(%rip), %rdi        lea rdi, [rel $.LC0]
;   call puts@PLT                call $puts wrt ..plt
;   movq %fs:0x28, %rax          mov rax, [fs:0x28]
;   jmp *%rax / call *8(%rbx)    jmp rax / call [rbx + (8)]
;   ljmp $0x10, $start           jmp 0x10:$start
;
; Operands: %reg (%st(i) is st<i>), $imm, a memory operand
; seg:disp(base, index, scale), * before an indirect branch's; reversed into
; Intel order (enter keeps its order). A name is written $name, so one that
; is a register or a keyword is still the name. Numbers as GNU's: 017 is
; octal. sym@PLT (@GOTPCREL, @GOT, @GOTOFF, @GOTPC, @TPOFF, @NTPOFF,
; @GOTTPOFF, @INDNTPOFF, @TLSGD, @TLSLD, @DTPOFF) is "sym wrt ..plt" ...
;
; Mnemonics: one of the target's as written (setl, cmovl, fabs ...); else
; with GNU's size suffix taken off - b w l q (x y: an xmm / ymm memory
; operand), x87's s l t (fadds: a float) and s l ll q (fiadds: an integer)
; - the size of its memory operand; and GNU's own names (movzbl, movslq,
; cltq, cqto, lret, movabs, ljmp, the string forms ...). As GNU as:
;   fsub / fsubr / fdiv / fdivr with st(i) the destination, and fsubp ...
;     without operands, are the other one (the SysV x87 mnemonics)
;   a shift or rotate of one operand shifts by 1
;   movq between general registers or with memory is mov; movq $imm to a
;     64-bit register the sign-extended imm32 (48 C7 /0), movabs the imm64
;   a string instruction's operands only name it (a segment other than
;     es: its prefix)
;   a prefix (rep, lock, data16, cs ... rex64) is its byte, written before
;     the instruction - alone on its line too ("rep; ret")
; ";" ends a statement and "#" starts a comment anywhere (the lexer);
; "%" at the start of a line is still NASM's directive.
; ============================================================================

extern  mt_collect, mt_tok, mt_kind, mt_split
extern  mt_n, mt_toks, mx_s, mx_n, mx_cnt
extern  mb_begin, mb_putc, mb_putz, mb_num, mb_line, mb_push
extern  prep_tokens_text
extern  preprocessor_peek_token, preprocessor_next_token
extern  parser_is_mnemonic, parser_is_reg_name
extern  gm_find, gm_defined
extern  asm_bits
extern  str_to_int

%define AF_STRING   0x0001          ; operands only name it
%define AF_NOREV    0x0002          ; operands in the order written (enter)
%define AF_BRANCH   0x0004          ; a bare operand is the target, * indirect
%define AF_FAR      0x0008          ; ljmp / lcall
%define AF_FSWAP    0x0010          ; fsub ...: the SysV swap
%define AF_MOVQ     0x0020          ; movq: mov unless a vector register
%define AF_IMMSZ    0x0040          ; push: the suffix's size on an immediate
%define AF_SHIFT    0x0080          ; one operand: by 1
%define AF_MOV      0x0100          ; mov: $imm to a 64-bit register
%define AF_ABS64    0x0200          ; movabs
%define AF_NOSIZE   0x0400          ; the suffix is not the memory's size
%define AF_PORT     0x0800          ; in / out: (%dx) is dx
%define AF_STACK    0x1000          ; push / pop: memory the stack's width
%define AF_STRSZ    0x2000          ; stos ...: b w d q from a register's size

%define AW_MAX      47              ; a mnemonic's length at most

; aw ATT, INTEL, FLAGS, SIZE: one of GNU's own names
%macro aw 4
    db %1, 0, %2, 0
    dw %3, %4
%endmacro
; af NAME, FLAGS: what a mnemonic of the target needs
%macro af 2
    db %1, 0
    dw %2
%endmacro
; ap NAME, BYTE: a prefix
%macro ap 2
    db %1, 0, %2
%endmacro

[SECTION .rodata]
att_words:
    aw "cbtw", "cbw", 0, 0
    aw "cwtl", "cwde", 0, 0
    aw "cwtd", "cwd", 0, 0
    aw "cltd", "cdq", 0, 0
    aw "cltq", "cdqe", 0, 0
    aw "cqto", "cqo", 0, 0
    aw "movzbw", "movzx", 0, 8
    aw "movzbl", "movzx", 0, 8
    aw "movzbq", "movzx", 0, 8
    aw "movzwl", "movzx", 0, 16
    aw "movzwq", "movzx", 0, 16
    aw "movzb", "movzx", 0, 8
    aw "movzw", "movzx", 0, 16
    aw "movsbw", "movsx", 0, 8
    aw "movsbl", "movsx", 0, 8
    aw "movsbq", "movsx", 0, 8
    aw "movswl", "movsx", 0, 16
    aw "movswq", "movsx", 0, 16
    aw "movslq", "movsxd", 0, 32
    aw "movabs", "mov", AF_ABS64, 0
    aw "movabsb", "mov", AF_ABS64, 8
    aw "movabsw", "mov", AF_ABS64, 16
    aw "movabsl", "mov", AF_ABS64, 32
    aw "movabsq", "mov", AF_ABS64, 64
    aw "movq", "movq", AF_MOVQ, 64
    aw "movsb", "movsb", AF_STRING, 0
    aw "movsw", "movsw", AF_STRING, 0
    aw "movsl", "movsd", AF_STRING, 0
    aw "movsq", "movsq", AF_STRING, 0
    aw "cmpsb", "cmpsb", AF_STRING, 0
    aw "cmpsw", "cmpsw", AF_STRING, 0
    aw "cmpsl", "cmpsd", AF_STRING, 0
    aw "cmpsq", "cmpsq", AF_STRING, 0
    aw "lodsb", "lodsb", AF_STRING, 0
    aw "lodsw", "lodsw", AF_STRING, 0
    aw "lodsl", "lodsd", AF_STRING, 0
    aw "lodsq", "lodsq", AF_STRING, 0
    aw "stosb", "stosb", AF_STRING, 0
    aw "stosw", "stosw", AF_STRING, 0
    aw "stosl", "stosd", AF_STRING, 0
    aw "stosq", "stosq", AF_STRING, 0
    aw "scasb", "scasb", AF_STRING, 0
    aw "scasw", "scasw", AF_STRING, 0
    aw "scasl", "scasd", AF_STRING, 0
    aw "scasq", "scasq", AF_STRING, 0
    aw "insb", "insb", AF_STRING, 0
    aw "insw", "insw", AF_STRING, 0
    aw "insl", "insd", AF_STRING, 0
    aw "outsb", "outsb", AF_STRING, 0
    aw "outsw", "outsw", AF_STRING, 0
    aw "outsl", "outsd", AF_STRING, 0
    aw "movs", "movs", AF_STRING | AF_STRSZ, 0
    aw "cmps", "cmps", AF_STRING | AF_STRSZ, 0
    aw "lods", "lods", AF_STRING | AF_STRSZ, 0
    aw "stos", "stos", AF_STRING | AF_STRSZ, 0
    aw "scas", "scas", AF_STRING | AF_STRSZ, 0
    aw "ins", "ins", AF_STRING | AF_STRSZ, 0
    aw "outs", "outs", AF_STRING | AF_STRSZ, 0
    aw "xlat", "xlatb", AF_STRING, 0
    aw "xlatb", "xlatb", AF_STRING, 0
    aw "ljmp", "jmp", AF_BRANCH | AF_FAR, 0
    aw "ljmpw", "jmp", AF_BRANCH | AF_FAR, 16
    aw "ljmpl", "jmp", AF_BRANCH | AF_FAR, 32
    aw "ljmpq", "jmp", AF_BRANCH | AF_FAR, 64
    aw "lcall", "call", AF_BRANCH | AF_FAR, 0
    aw "lcallw", "call", AF_BRANCH | AF_FAR, 16
    aw "lcalll", "call", AF_BRANCH | AF_FAR, 32
    aw "lcallq", "call", AF_BRANCH | AF_FAR, 64
    aw "lret", "retf", 0, 0
    aw "lretw", "o16 retf", 0, 0
    aw "lretl", "retf", 0, 0
    aw "lretq", "o64 retf", 0, 0
    aw "retw", "o16 ret", 0, 0
    aw "retl", "ret", 0, 0
    aw "retq", "ret", 0, 0
    aw "iretl", "iretd", 0, 0
    aw "sysretl", "sysret", 0, 0
    aw "sysretq", "o64 sysret", 0, 0
    aw "sysexitl", "sysexit", 0, 0
    aw "sysexitq", "o64 sysexit", 0, 0
    aw "pushfl", "pushfd", 0, 0
    aw "popfl", "popfd", 0, 0
    aw "pushal", "pushad", 0, 0
    aw "popal", "popad", 0, 0
    aw "leavel", "leave", 0, 0
    aw "leaveq", "leave", 0, 0
    aw "leavew", "o16 leave", 0, 0
    aw "fxsaveq", "fxsave64", 0, 0
    aw "fxrstorq", "fxrstor64", 0, 0
    aw "xsaveq", "xsave64", 0, 0
    aw "xrstorq", "xrstor64", 0, 0
    aw "xsaveoptq", "xsaveopt64", 0, 0
    aw "xsavecq", "xsavec64", 0, 0
    aw "xsavesq", "xsaves64", 0, 0
    aw "xrstorsq", "xrstors64", 0, 0
    db 0

att_flags:
    af "call", AF_BRANCH
    af "loop", AF_BRANCH
    af "loope", AF_BRANCH
    af "loopz", AF_BRANCH
    af "loopne", AF_BRANCH
    af "loopnz", AF_BRANCH
    af "xbegin", AF_BRANCH
    af "fsub", AF_FSWAP
    af "fsubr", AF_FSWAP
    af "fdiv", AF_FSWAP
    af "fdivr", AF_FSWAP
    af "fsubp", AF_FSWAP
    af "fsubrp", AF_FSWAP
    af "fdivp", AF_FSWAP
    af "fdivrp", AF_FSWAP
    af "shl", AF_SHIFT
    af "shr", AF_SHIFT
    af "sal", AF_SHIFT
    af "sar", AF_SHIFT
    af "rol", AF_SHIFT
    af "ror", AF_SHIFT
    af "rcl", AF_SHIFT
    af "rcr", AF_SHIFT
    af "push", AF_IMMSZ | AF_STACK
    af "pop", AF_STACK
    af "mov", AF_MOV
    af "lea", AF_NOSIZE
    af "lds", AF_NOSIZE
    af "les", AF_NOSIZE
    af "lfs", AF_NOSIZE
    af "lgs", AF_NOSIZE
    af "lss", AF_NOSIZE
    af "bound", AF_NOSIZE
    af "in", AF_PORT
    af "out", AF_PORT
    af "enter", AF_NOREV
    db 0

att_prefixes:
    ap "rep", 0xF3
    ap "repe", 0xF3
    ap "repz", 0xF3
    ap "repne", 0xF2
    ap "repnz", 0xF2
    ap "lock", 0xF0
    ap "data16", 0x66
    ap "data32", 0x66
    ap "addr16", 0x67
    ap "addr32", 0x67
    ap "cs", 0x2E
    ap "ds", 0x3E
    ap "es", 0x26
    ap "fs", 0x64
    ap "gs", 0x65
    ap "ss", 0x36
    ap "notrack", 0x3E
    ap "bnd", 0xF2
    ap "xacquire", 0xF2
    ap "xrelease", 0xF3
    ap "rex", 0x40
    ap "rex64", 0x48
    ap "rex.w", 0x48
    ap "rex.r", 0x44
    ap "rex.x", 0x42
    ap "rex.b", 0x41
    db 0

; sym@NAME: the "wrt ..name" it is (NAME upper case as GNU's)
att_relocs:
    db "PLT", 0, "..plt", 0
    db "GOTPCREL", 0, "..gotpcrel", 0
    db "GOTOFF", 0, "..gotoff", 0
    db "GOTPC", 0, "..gotpc", 0
    db "GOTTPOFF", 0, "..gottpoff", 0
    db "GOTNTPOFF", 0, "..gottpoff", 0
    db "GOT", 0, "..got", 0
    db "TPOFF", 0, "..tpoff", 0
    db "NTPOFF", 0, "..tpoff", 0
    db "INDNTPOFF", 0, "..tlsie", 0
    db "TLSGD", 0, "..tlsgd", 0
    db "TLSLD", 0, "..tlsld", 0
    db "DTPOFF", 0, "..dtpoff", 0
    db 0

; the 64-bit general registers (movq $imm: 48 C7 /0)
att_r64:
    db "rax", 0, "rbx", 0, "rcx", 0, "rdx", 0, "rsi", 0, "rdi", 0, "rbp", 0
    db "rsp", 0, "r8", 0, "r9", 0, "r10", 0, "r11", 0, "r12", 0, "r13", 0
    db "r14", 0, "r15", 0, 0

s_db:       db "db 0x", 0
s_byte:     db "byte ", 0
s_word:     db "word ", 0
s_dword:    db "dword ", 0
s_qword:    db "qword ", 0
s_tword:    db "tword ", 0
s_oword:    db "oword ", 0
s_yword:    db "yword ", 0
s_zword:    db "zword ", 0
s_far:      db "far ", 0
s_strict_d: db "strict dword ", 0
s_strict_q: db "strict qword ", 0
s_rel:      db "rel ", 0
s_abs:      db "abs ", 0
s_qbr:      db "qword ", 0
s_wrt:      db " wrt ", 0
s_one:      db ", 1", 0
s_comma:    db ", ", 0
s_plus:     db " + ", 0
s_plus_p:   db " + (", 0
s_mov:      db "mov", 0
s_dx:       db "dx", 0
s_st:       db "st", 0
hexdig:     db "0123456789abcdef"

[SECTION .bss]
global att_on, att_noprefix, gas_names
att_on:         resb 1              ; .att_syntax / --att: statements are AT&T's
att_noprefix:   resb 1              ; .att_syntax noprefix: registers without %
gas_names:      resb 1              ; GNU's syntax seen: "." names are plain ones
alignb 8
at_word:        resb AW_MAX + 9     ; the word, lower case
at_mbuf:        resb AW_MAX + 9     ; the mnemonic made of it
at_mnem:        resq 1              ; the Intel mnemonic's text
at_fl:          resd 1              ; AF_*
at_size:        resd 1              ; the suffix's size in bits (0: none)
at_npfx:        resq 1
at_pfx:         resb 16             ; prefix bytes, in order
at_strict:      resb 1              ; the first operand: "strict dword"
at_err:         resb 1              ; an operand not read

[SECTION .text]

; ============================================================================
; THE STATEMENT
; ============================================================================

; ---- att_statement ------------------------
;
; att_statement
; Under .att_syntax: the statement word (and the rest of its line) as an
; AT&T instruction, translated and read next.
; Input    : rdi = PrepState, rsi = the word's token
; Output   : eax = 0: not an instruction (the parser goes on with the word);
;            1: done, rdx = OK or an error
;
global att_statement
att_statement:
    xor     eax, eax
    cmp     byte [rel att_on], 0
    je      .quick
    mov     rcx, [rdi + PREP_lexer]
    test    rcx, rcx
    jz      .quick
    cmp     byte [rcx + LEXER_intel], 0
    jne     .quick                         ; utasm's own text (made here)
    cmp     byte [rsi + TOKEN_kind], TOK_IDENT
    je      .go
.quick:
    ret
.go:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, [rsi + TOKEN_value]
    mov     qword [rel at_npfx], 0
.word:
    ; r12 = the word
    mov     rsi, r12
    call    at_lower
    test    eax, eax
    jz      .not_word
    ; a GNU macro of that name is called, as GNU as calls it
    cmp     qword [rel gm_defined], 0
    je      .no_macro
    lea     rsi, [rel at_word]
    mov     ecx, eax
    call    gm_find
    test    rax, rax
    jnz     .not_word
.no_macro:
    call    at_prefix
    test    eax, eax
    jz      .mnemonic
    mov     rcx, [rel at_npfx]
    cmp     rcx, 16
    jae     .bad
    lea     rdx, [rel at_pfx]
    mov     [rdx + rcx], al
    inc     qword [rel at_npfx]
    ; another word on the line (the instruction, or another prefix), or
    ; the prefix alone ("rep; ret", "lock" on a line of its own)
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done_rax
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    jne     .prefix_alone
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done_rax
    mov     r12, [rdx + TOKEN_value]
    jmp     .word
.prefix_alone:
    cmp     eax, TOK_NEWLINE
    je      .alone
    cmp     eax, TOK_EOF
    je      .alone
    cmp     eax, TOK_COMMENT
    jne     .bad_line
.alone:
    mov     qword [rel at_mnem], 0
    mov     qword [rel mt_n], 0
    mov     qword [rel mx_cnt], 0
    jmp     .build
.not_word:
    cmp     qword [rel at_npfx], 0
    jne     .bad_line                      ; a prefix before what is no instruction
    xor     eax, eax
    jmp     .ret
.mnemonic:
    call    at_resolve
    test    eax, eax
    jz      .not_word
    call    mt_collect
    test    rax, rax
    jnz     .done_rax
    xor     ecx, ecx
    mov     rdx, [rel mt_n]
    call    mt_split
    call    at_decide
.build:
    call    at_build
    cmp     byte [rel at_err], 0
    jne     .bad
    call    mb_push
    jmp     .done_rax
.bad_line:
    ; the rest of the line goes with the error
    call    mt_collect
.bad:
    mov     eax, EXIT_ATT_SYNTAX
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

; at_lower: rsi = a word -> at_word, its lower case; eax = its length (0:
; empty or longer than a mnemonic)
at_lower:
    lea     rdi, [rel at_word]
    xor     ecx, ecx
.l_next:
    movzx   eax, byte [rsi + rcx]
    test    eax, eax
    jz      .l_end
    cmp     ecx, AW_MAX
    jae     .l_long
    cmp     eax, 'A'
    jb      .l_put
    cmp     eax, 'Z'
    ja      .l_put
    or      eax, 0x20
.l_put:
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .l_next
.l_end:
    mov     byte [rdi + rcx], 0
    mov     eax, ecx
    ret
.l_long:
    xor     eax, eax
    ret

; at_prefix: at_word a prefix? eax = its byte (0: no)
at_prefix:
    lea     rsi, [rel att_prefixes]
.p_entry:
    cmp     byte [rsi], 0
    je      .p_none
    lea     rdi, [rel at_word]
    call    at_streq
    mov     rdx, rsi
.p_skip:
    inc     rdx
    cmp     byte [rdx - 1], 0
    jne     .p_skip
    test    eax, eax
    jnz     .p_hit
    lea     rsi, [rdx + 1]
    jmp     .p_entry
.p_hit:
    movzx   eax, byte [rdx]
    ret
.p_none:
    xor     eax, eax
    ret

; at_streq: rdi, rsi NUL-terminated: eax = 1 when equal. Preserves rsi, rdi.
at_streq:
    xor     ecx, ecx
.e_next:
    movzx   eax, byte [rdi + rcx]
    cmp     al, [rsi + rcx]
    jne     .e_no
    inc     ecx
    test    eax, eax
    jnz     .e_next
    mov     eax, 1
    ret
.e_no:
    xor     eax, eax
    ret

; at_is_mnem: rdi = a word: eax = 1 when the target has that mnemonic.
; Preserves rbx, r12-r15.
at_is_mnem:
    jmp     parser_is_mnemonic

; ============================================================================
; THE MNEMONIC
; ============================================================================

; at_resolve: at_word -> at_mnem, at_fl, at_size; eax = 1 when it is an
; instruction
at_resolve:
    push    r12
    mov     dword [rel at_fl], 0
    mov     dword [rel at_size], 0
    ; GNU's own names
    lea     rsi, [rel att_words]
.w_entry:
    cmp     byte [rsi], 0
    je      .w_none
    lea     rdi, [rel at_word]
    call    at_streq
    mov     r12d, eax
    call    at_skipz                       ; rsi: the Intel name
    mov     rdx, rsi
    call    at_skipz                       ; rsi: flags, size
    test    r12d, r12d
    jnz     .w_hit
    add     rsi, 4
    jmp     .w_entry
.w_hit:
    mov     [rel at_mnem], rdx
    movzx   eax, word [rsi]
    mov     [rel at_fl], eax
    movzx   eax, word [rsi + 2]
    mov     [rel at_size], eax
    jmp     .yes
.w_none:
    ; the target's mnemonic, as written
    lea     rdi, [rel at_word]
    call    at_is_mnem
    test    eax, eax
    jz      .suffix
    lea     rsi, [rel at_word]
    call    at_take
    jmp     .yes
.suffix:
    ; a size suffix: x87's first (fadds, fildll), then b w l q x y
    lea     rsi, [rel at_word]
    call    at_take                        ; at_mbuf: a copy to cut
    lea     rdi, [rel at_mbuf]
    call    at_len
    cmp     eax, 2
    jb      .no
    mov     r12d, eax
    lea     rdi, [rel at_mbuf]
    movzx   ecx, byte [rdi + r12 - 1]
    cmp     byte [rdi], 'f'
    jne     .generic
    cmp     byte [rdi + 1], 'i'
    jne     .x87_float
    ; fiadds fiaddl fildll fildq: s 16, l 32, ll / q 64
    cmp     ecx, 'l'
    jne     .x87_int_other
    cmp     r12d, 4
    jb      .x87_int_l
    cmp     byte [rdi + r12 - 2], 'l'
    jne     .x87_int_l
    ; "ll": try the word without both
    mov     byte [rdi + r12 - 2], 0
    call    at_is_mnem
    test    eax, eax
    jz      .x87_int_l_back
    mov     eax, 64
    jmp     .cut_done
.x87_int_l_back:
    lea     rdi, [rel at_mbuf]
    mov     byte [rdi + r12 - 2], 'l'
.x87_int_l:
    mov     eax, 32
    jmp     .cut
.x87_int_other:
    mov     eax, 16
    cmp     ecx, 's'
    je      .cut
    mov     eax, 64
    cmp     ecx, 'q'
    je      .cut
    jmp     .generic
.x87_float:
    mov     eax, 32
    cmp     ecx, 's'
    je      .cut
    mov     eax, 64
    cmp     ecx, 'l'
    je      .cut
    mov     eax, 80
    cmp     ecx, 't'
    je      .cut
.generic:
    mov     eax, 8
    cmp     ecx, 'b'
    je      .cut
    mov     eax, 16
    cmp     ecx, 'w'
    je      .cut
    mov     eax, 32
    cmp     ecx, 'l'
    je      .cut
    mov     eax, 64
    cmp     ecx, 'q'
    je      .cut
    mov     eax, 128
    cmp     ecx, 'x'
    je      .cut
    mov     eax, 256
    cmp     ecx, 'y'
    je      .cut
    jmp     .no
.cut:
    ; eax = the size: the word without its last letter must be a mnemonic
    push    rax
    lea     rdi, [rel at_mbuf]
    mov     byte [rdi + r12 - 1], 0
    call    at_is_mnem
    mov     ecx, eax
    pop     rax
    test    ecx, ecx
    jz      .no
.cut_done:
    mov     [rel at_size], eax
    lea     rax, [rel at_mbuf]
    mov     [rel at_mnem], rax
.yes:
    call    at_base_flags
    mov     eax, 1
    pop     r12
    ret
.no:
    xor     eax, eax
    pop     r12
    ret

; at_take: rsi = a word -> at_mbuf a copy, at_mnem it
at_take:
    lea     rdi, [rel at_mbuf]
    mov     [rel at_mnem], rdi
.t_next:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .t_next
    ret

; at_skipz: rsi past the NUL-terminated text at it
at_skipz:
    inc     rsi
    cmp     byte [rsi - 1], 0
    jne     at_skipz
    ret

; at_len: eax = the length of rdi's text. Preserves rdi.
at_len:
    xor     eax, eax
.n_next:
    cmp     byte [rdi + rax], 0
    je      .n_ret
    inc     eax
    jmp     .n_next
.n_ret:
    ret

; at_base_flags: at_fl |= what the mnemonic at_mnem needs (att_flags; a
; j... word is a branch; a conversion to an integer register takes the
; suffix for the register, not the memory)
at_base_flags:
    mov     rdi, [rel at_mnem]
    cmp     byte [rdi], 'j'
    jne     .b_table
    or      dword [rel at_fl], AF_BRANCH
.b_table:
    lea     rsi, [rel att_flags]
.b_entry:
    cmp     byte [rsi], 0
    je      .b_cvt
    call    at_streq
    push    rax
    call    at_skipz
    pop     rax
    test    eax, eax
    jnz     .b_hit
    add     rsi, 2
    jmp     .b_entry
.b_hit:
    movzx   eax, word [rsi]
    or      [rel at_fl], eax
    ret
.b_cvt:
    ; cvt...2si / cvt...2usi (vcvt too)
    xor     ecx, ecx
.b_scan:
    movzx   eax, byte [rdi + rcx]
    test    eax, eax
    jz      .b_ret
    cmp     eax, '2'
    jne     .b_step
    cmp     word [rdi + rcx + 1], 'si'
    je      .b_nosize
    cmp     word [rdi + rcx + 1], 'us'
    jne     .b_step
    cmp     byte [rdi + rcx + 3], 'i'
    je      .b_nosize
.b_step:
    inc     ecx
    jmp     .b_scan
.b_nosize:
    or      dword [rel at_fl], AF_NOSIZE
.b_ret:
    ret

; ============================================================================
; CHOICES THE OPERANDS MAKE
; ============================================================================

; at_decide: movq or mov, the x87 swap, movq $imm's strict dword
at_decide:
    push    r12
    push    r13
    mov     byte [rel at_strict], 0
    test    dword [rel at_fl], AF_MOVQ
    jz      .d_fswap
    ; a vector register among the operands: movq; else mov
    xor     r12d, r12d
.d_vec:
    cmp     r12, [rel mt_n]
    jae     .d_gpr
    mov     rcx, r12
    inc     r12
    call    at_reg_name                    ; rsi = the name (no %), or 0
    test    rsi, rsi
    jz      .d_vec
    cmp     byte [rsi], 'x'
    je      .d_keep
    cmp     byte [rsi], 'y'
    je      .d_keep
    cmp     byte [rsi], 'z'
    je      .d_keep
    cmp     word [rsi], 'mm'
    je      .d_keep
    jmp     .d_vec
.d_gpr:
    lea     rax, [rel s_mov]
    mov     [rel at_mnem], rax
    or      dword [rel at_fl], AF_MOV
    jmp     .d_mov
.d_keep:
    mov     dword [rel at_size], 0
    jmp     .d_done
.d_fswap:
    test    dword [rel at_fl], AF_FSWAP
    jz      .d_mov
    mov     rax, [rel mx_cnt]
    test    rax, rax
    jz      .d_fs_none
    cmp     rax, 2
    jne     .d_done
    ; the destination (written last) st(i), i not 0
    mov     rcx, [rel mx_s + 8]
    call    at_reg_name
    test    rsi, rsi
    jz      .d_done
    cmp     word [rsi], 'st'
    jne     .d_done
    cmp     byte [rsi + 2], 0
    jne     .d_done
    mov     rcx, [rel mx_s + 8]
    add     rcx, 2                         ; "%st" "(" N ")"
    call    mt_kind
    cmp     eax, TOK_NUMBER
    jne     .d_done
    call    mt_tok
    mov     rax, [rax + TOKEN_value]
    cmp     word [rax], '0'
    je      .d_done
    jmp     .d_swap
.d_fs_none:
    ; fsubp ... without operands
    mov     rdi, [rel at_mnem]
    call    at_len
    cmp     byte [rdi + rax - 1], 'p'
    jne     .d_done
.d_swap:
    ; fsub <-> fsubr, fdivp <-> fdivrp: the letter after the four
    mov     rsi, [rel at_mnem]
    lea     rdi, [rel at_mbuf]
    cmp     rsi, rdi
    je      .d_swap_in
    call    at_take
.d_swap_in:
    lea     rdi, [rel at_mbuf]
    mov     [rel at_mnem], rdi
    cmp     byte [rdi + 4], 'r'
    je      .d_unr
    ; insert an r at 4
    call    at_len
    mov     ecx, eax
.d_ins:
    cmp     ecx, 4
    jb      .d_ins_put
    mov     dl, [rdi + rcx]
    mov     [rdi + rcx + 1], dl
    dec     ecx
    jmp     .d_ins
.d_ins_put:
    mov     byte [rdi + 4], 'r'
    jmp     .d_done
.d_unr:
    lea     rsi, [rdi + 5]
    add     rdi, 4
.d_unr_next:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .d_unr_next
    jmp     .d_done
.d_mov:
    ; mov $imm, %r64: the sign-extended imm32 as GNU as (48 C7 /0) - unless a
    ; number that is not one (movabs then, as GNU as)
    test    dword [rel at_fl], AF_MOV
    jz      .d_done
    cmp     qword [rel mx_cnt], 2
    jne     .d_done
    mov     rcx, [rel mx_s]
    call    mt_kind
    cmp     eax, TOK_DOLLAR
    jne     .d_done
    cmp     qword [rel mx_n + 8], 1
    jne     .d_done
    mov     rcx, [rel mx_s + 8]
    call    at_reg_name
    test    rsi, rsi
    jz      .d_done
    lea     rdi, [rel att_r64]
.d_r64:
    cmp     byte [rdi], 0
    je      .d_done
    xchg    rsi, rdi
    call    at_streq
    xchg    rsi, rdi
    test    eax, eax
    jnz     .d_wide
    xchg    rsi, rdi
    call    at_skipz
    xchg    rsi, rdi
    jmp     .d_r64
.d_wide:
    ; the immediate: a name in it (an address: R_X86_64_32S), or one number
    mov     r12, [rel mx_s]
    inc     r12
    mov     r13, [rel mx_n]
    add     r13, [rel mx_s]                ; its end
    mov     rcx, r12
.d_names:
    cmp     rcx, r13
    jae     .d_number
    call    mt_kind
    inc     rcx
    cmp     eax, TOK_IDENT
    jne     .d_names
    jmp     .d_strict
.d_number:
    mov     rcx, r12
    call    mt_kind
    xor     r8d, r8d                       ; negative
    cmp     eax, TOK_MINUS
    jne     .d_num
    mov     r8d, 1
    inc     rcx
    call    mt_kind
.d_num:
    cmp     eax, TOK_NUMBER
    jne     .d_done
    lea     rax, [rcx + 1]
    cmp     rax, r13
    jne     .d_done                        ; an expression: as utasm sizes it
    call    mt_tok
    push    r8
    mov     rdi, [rax + TOKEN_value]
    call    at_number_value                ; rdx, eax = 0 when read
    pop     r8
    test    eax, eax
    jnz     .d_done
    test    r8d, r8d
    jz      .d_signed
    neg     rdx
.d_signed:
    movsxd  rax, edx
    cmp     rax, rdx
    jne     .d_done                        ; past an imm32: movabs
.d_strict:
    mov     byte [rel at_strict], 1
.d_done:
    pop     r13
    pop     r12
    ret

; at_number_value: rdi = a number's text, GNU's (017 octal) -> rdx; eax = 0
; when read
at_number_value:
    cmp     byte [rdi], '0'
    jne     .v_plain
    movzx   eax, byte [rdi + 1]
    sub     eax, '0'
    cmp     eax, 7
    ja      .v_plain
    ; octal
    xor     edx, edx
    lea     rsi, [rdi + 1]
.v_oct:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .v_ok
    sub     eax, '0'
    cmp     eax, 7
    ja      .v_bad
    shl     rdx, 3
    add     rdx, rax
    inc     rsi
    jmp     .v_oct
.v_ok:
    xor     eax, eax
    ret
.v_bad:
    mov     eax, 1
    ret
.v_plain:
    call    str_to_int
    ret

; at_reg_name: is token rcx a register (%name; a register's name under
; noprefix)? rsi = the name without %, else 0. Preserves rcx.
at_reg_name:
    push    rcx
    xor     esi, esi
    cmp     rcx, [rel mt_n]
    jae     .r_ret
    call    mt_tok
    movzx   edx, byte [rax + TOKEN_kind]
    cmp     edx, TOK_IDENT
    jne     .r_ret
    mov     rax, [rax + TOKEN_value]
    cmp     byte [rax], '%'
    jne     .r_bare
    lea     rsi, [rax + 1]
.r_ret:
    pop     rcx
    ret
.r_bare:
    ; .att_syntax noprefix: a register's name alone
    cmp     byte [rel att_noprefix], 0
    je      .r_ret
    ; (st and rip: not in the register table - st0 ... st7 are)
    cmp     dword [rax], 'st'
    je      .r_named
    cmp     dword [rax], 'rip'
    je      .r_named
    cmp     dword [rax], 'eip'
    je      .r_named
    push    rax
    mov     rdi, rax
    call    parser_is_reg_name
    pop     rsi
    test    eax, eax
    jnz     .r_ret
    xor     esi, esi
    jmp     .r_ret
.r_named:
    mov     rsi, rax
    jmp     .r_ret

; ============================================================================
; THE TEXT
; ============================================================================

; at_build: the statement in utasm's syntax, into mb_buf; at_err set when an
; operand cannot be read
at_build:
    push    r12
    push    r13
    push    r14
    mov     byte [rel at_err], 0
    call    mb_begin
    ; the prefixes, each its byte on a line before the instruction
    xor     r12d, r12d
.b_pfx:
    cmp     r12, [rel at_npfx]
    jae     .b_pfx_done
    lea     rax, [rel at_pfx]
    movzx   eax, byte [rax + r12]
    call    at_db_line
    inc     r12
    jmp     .b_pfx
.b_pfx_done:
    cmp     qword [rel at_mnem], 0
    je      .b_ret                         ; a prefix alone
    ; a string instruction: a segment named in its operands is its prefix
    test    dword [rel at_fl], AF_STRING
    jz      .b_line
    xor     r12d, r12d
.b_seg:
    cmp     r12, [rel mx_cnt]
    jae     .b_line
    lea     rax, [rel mx_s]
    mov     rcx, [rax + r12 * 8]
    inc     r12
    call    at_segment                     ; eax = its byte (0 none), rcx past
    test    eax, eax
    jz      .b_seg
    ; GNU as writes one that is not the operand's own: ds: is the default
    ; of (%rsi) and (%rbx), and (%rdi)'s es: cannot be another
    cmp     eax, 0x3E
    je      .b_seg
    push    rax
    call    mt_kind
    cmp     eax, TOK_LPAREN
    jne     .b_seg_put
    inc     rcx
    call    at_reg_name
    test    rsi, rsi
    jz      .b_seg_put
    cmp     byte [rsi], 'd'
    je      .b_seg_di
    cmp     byte [rsi + 1], 'd'
    jne     .b_seg_put
.b_seg_di:
    cmp     byte [rsi + 1], 'i'
    je      .b_seg_skip
    cmp     byte [rsi + 2], 'i'
    je      .b_seg_skip
.b_seg_put:
    pop     rax
    call    at_db_line
    jmp     .b_seg
.b_seg_skip:
    pop     rax
    jmp     .b_seg
.b_line:
    call    mb_line
    mov     rsi, [rel at_mnem]
    call    mb_putz
    ; "stos %rax, %es:(%rdi)": the size its register names
    test    dword [rel at_fl], AF_STRSZ
    jz      .b_named
    call    at_string_size
.b_named:
    test    dword [rel at_fl], AF_STRING
    jnz     .b_end
    mov     r13, [rel mx_cnt]
    test    r13, r13
    jz      .b_end
    mov     al, ' '
    call    mb_putc
    ; ljmp $seg, $off: seg:off
    test    dword [rel at_fl], AF_FAR
    jz      .b_order
    cmp     r13, 2
    jne     .b_order
    mov     rcx, [rel mx_s]
    call    mt_kind
    cmp     eax, TOK_DOLLAR
    jne     .b_order
    mov     rcx, [rel mx_s + 8]
    call    mt_kind
    cmp     eax, TOK_DOLLAR
    jne     .b_order
    mov     rcx, [rel mx_s]
    inc     rcx
    mov     rdx, [rel mx_s]
    add     rdx, [rel mx_n]
    call    at_expr
    mov     al, ':'
    call    mb_putc
    mov     rcx, [rel mx_s + 8]
    inc     rcx
    mov     rdx, [rel mx_s + 8]
    add     rdx, [rel mx_n + 8]
    call    at_expr
    jmp     .b_end
.b_order:
    ; Intel's order: the last first (enter: as written)
    xor     r14d, r14d                     ; operands written
.b_op:
    cmp     r14, r13
    jae     .b_shift
    test    r14, r14
    jz      .b_op_first
    lea     rsi, [rel s_comma]
    call    mb_putz
.b_op_first:
    mov     r12, r14
    test    dword [rel at_fl], AF_NOREV
    jnz     .b_op_at
    mov     r12, r13
    sub     r12, r14
    dec     r12
.b_op_at:
    mov     rdi, r12
    call    at_operand
    inc     r14
    jmp     .b_op
.b_shift:
    ; shll %eax: by 1
    test    dword [rel at_fl], AF_SHIFT
    jz      .b_end
    cmp     r13, 1
    jne     .b_end
    lea     rsi, [rel s_one]
    call    mb_putz
.b_end:
    mov     al, 10
    call    mb_putc
.b_ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; at_string_size: a string instruction with no suffix: the letter for its
; register operand's size (al b, ax w, eax d, rax q); with none, GNU as's
; default l: d
at_string_size:
    xor     ecx, ecx
.ss_tok:
    cmp     rcx, [rel mt_n]
    jae     .ss_none
    call    at_reg_name
    inc     rcx
    test    rsi, rsi
    jz      .ss_tok
    mov     al, 'b'
    cmp     word [rsi], 'al'
    je      .ss_put
    mov     al, 'w'
    cmp     word [rsi], 'ax'
    je      .ss_put
    mov     al, 'd'
    cmp     word [rsi], 'ea'
    je      .ss_put
    mov     al, 'q'
    cmp     word [rsi], 'ra'
    je      .ss_put
    jmp     .ss_tok
.ss_put:
    jmp     mb_putc
.ss_none:
    mov     al, 'd'
    jmp     mb_putc

; at_db_line: "db 0xNN" (al) on a line of its own
at_db_line:
    push    rax
    call    mb_line
    lea     rsi, [rel s_db]
    call    mb_putz
    pop     rax
    push    rax
    shr     eax, 4
    and     eax, 15
    lea     rsi, [rel hexdig]
    mov     al, [rsi + rax]
    call    mb_putc
    pop     rax
    and     eax, 15
    lea     rsi, [rel hexdig]
    mov     al, [rsi + rax]
    call    mb_putc
    mov     al, 10
    jmp     mb_putc

; at_segment: a segment at token rcx ("%fs:" or "%fs" ":")? eax = its
; prefix byte (0: none), rcx past it, r8 = its name (two letters)
at_segment:
    xor     eax, eax
    cmp     rcx, [rel mt_n]
    jae     .s_ret
    push    rcx
    call    mt_tok
    pop     rcx
    movzx   edx, byte [rax + TOKEN_kind]
    mov     r8, [rax + TOKEN_value]
    xor     eax, eax
    cmp     edx, TOK_LABEL
    je      .s_text
    cmp     edx, TOK_IDENT
    jne     .s_ret                         ; ("(" and the like have no text)
.s_text:
    cmp     byte [r8], '%'
    jne     .s_ret
    cmp     byte [r8 + 3], 0
    jne     .s_ret
    cmp     edx, TOK_LABEL
    je      .s_name
    cmp     edx, TOK_IDENT
    jne     .s_ret
    lea     rdx, [rcx + 1]
    cmp     rdx, [rel mt_n]
    jae     .s_ret
    push    rcx
    mov     rcx, rdx
    call    mt_kind
    pop     rcx
    cmp     eax, TOK_COLON
    mov     eax, 0
    jne     .s_ret
    inc     rcx                            ; (the ":")
.s_name:
    inc     r8
    movzx   edx, word [r8]
    or      edx, 0x2020
    mov     eax, 0x2E
    cmp     dx, 'cs'
    je      .s_hit
    mov     eax, 0x3E
    cmp     dx, 'ds'
    je      .s_hit
    mov     eax, 0x26
    cmp     dx, 'es'
    je      .s_hit
    mov     eax, 0x64
    cmp     dx, 'fs'
    je      .s_hit
    mov     eax, 0x65
    cmp     dx, 'gs'
    je      .s_hit
    mov     eax, 0x36
    cmp     dx, 'ss'
    je      .s_hit
    xor     eax, eax
    dec     r8
    ret
.s_hit:
    inc     rcx
.s_ret:
    ret

; ---- one operand --------------------------

; at_operand: operand rdi (AT&T's order) in utasm's syntax
at_operand:
    push    r12
    push    r13
    push    r14
    lea     rax, [rel mx_s]
    mov     r12, [rax + rdi * 8]           ; its first token
    lea     rax, [rel mx_n]
    mov     r13, [rax + rdi * 8]
    add     r13, r12                       ; its end
    mov     r14, rdi
    cmp     r12, r13
    jae     .o_bad
    mov     rcx, r12
    call    mt_kind
    cmp     eax, TOK_DOLLAR
    je      .o_imm
    cmp     eax, TOK_STAR
    je      .o_indirect
    cmp     eax, TOK_LBRACE
    je      .o_deco
    ; a register, with its decorations ({%k1}{z})
    mov     rcx, r12
    call    at_reg_name
    test    rsi, rsi
    jz      .o_not_reg
    mov     rcx, r12
    call    at_register
    cmp     rcx, r13
    je      .o_ret
    jmp     .o_bad                         ; more after it
.o_not_reg:
    ; in / out: (%dx) is dx
    test    dword [rel at_fl], AF_PORT
    jz      .o_target
    mov     rax, r13
    sub     rax, r12
    cmp     rax, 3
    jne     .o_target
    mov     rcx, r12
    call    mt_kind
    cmp     eax, TOK_LPAREN
    jne     .o_target
    lea     rcx, [r12 + 1]
    call    at_reg_name
    test    rsi, rsi
    jz      .o_target
    cmp     word [rsi], 'dx'
    jne     .o_target
    cmp     byte [rsi + 2], 0
    jne     .o_target
    lea     rsi, [rel s_dx]
    call    mb_putz
    jmp     .o_ret
.o_target:
    ; a branch's bare operand is its target ("jmp .L3", "call puts@PLT")
    test    dword [rel at_fl], AF_BRANCH
    jz      .o_mem
    mov     rcx, r12
.o_scan:
    cmp     rcx, r13
    jae     .o_bare
    call    mt_kind
    inc     rcx
    cmp     eax, TOK_LPAREN
    je      .o_mem
    cmp     eax, TOK_LABEL
    je      .o_mem
    cmp     eax, TOK_COLON
    je      .o_mem
    jmp     .o_scan
.o_bare:
    mov     rcx, r12
    mov     rdx, r13
    call    at_expr
    jmp     .o_ret
.o_mem:
    mov     rcx, r12
    mov     rdx, r13
    xor     r8d, r8d
    call    at_memory
    jmp     .o_ret
.o_imm:
    ; $imm
    test    dword [rel at_fl], AF_ABS64
    jz      .o_imm_strict
    lea     rsi, [rel s_strict_q]
    call    mb_putz
    jmp     .o_imm_expr
.o_imm_strict:
    cmp     byte [rel at_strict], 0
    je      .o_imm_size
    test    r14, r14
    jnz     .o_imm_size
    lea     rsi, [rel s_strict_d]
    call    mb_putz
    jmp     .o_imm_expr
.o_imm_size:
    test    dword [rel at_fl], AF_IMMSZ
    jz      .o_imm_expr
    mov     eax, [rel at_size]
    call    at_size_word
.o_imm_expr:
    lea     rcx, [r12 + 1]
    mov     rdx, r13
    call    at_expr
    jmp     .o_ret
.o_indirect:
    ; *%rax, *8(%rbx), *foo
    lea     rcx, [r12 + 1]
    call    at_reg_name
    test    rsi, rsi
    jz      .o_ind_mem
    lea     rcx, [r12 + 1]
    call    at_register
    cmp     rcx, r13
    je      .o_ret
    jmp     .o_bad
.o_ind_mem:
    lea     rcx, [r12 + 1]
    mov     rdx, r13
    mov     r8d, 1                         ; (far: "far SIZE")
    call    at_memory
    jmp     .o_ret
.o_deco:
    ; {rn-sae}, {sae}: written as they are
    mov     rcx, r12
.o_deco_tok:
    cmp     rcx, r13
    jae     .o_ret
    call    at_bare_text
    inc     rcx
    jmp     .o_deco_tok
.o_bad:
    mov     byte [rel at_err], 1
.o_ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; at_register: the register at token rcx (%st(1) is st1), and the
; decorations after it ({%k1}{z}); rcx past them
at_register:
    push    r12
    call    at_reg_name
    test    rsi, rsi
    jz      .g_bad
    mov     r12, rsi
    call    at_put_lower                   ; the name
    inc     rcx
    ; %st: (N) after it, or st0
    cmp     word [r12], 'st'
    jne     .g_deco
    cmp     byte [r12 + 2], 0
    jne     .g_deco
    call    mt_kind
    cmp     eax, TOK_LPAREN
    jne     .g_st0
    inc     rcx
    call    mt_kind
    cmp     eax, TOK_NUMBER
    jne     .g_bad
    call    at_bare_text
    inc     rcx
    call    mt_kind
    cmp     eax, TOK_RPAREN
    jne     .g_bad
    inc     rcx
    jmp     .g_deco
.g_st0:
    mov     al, '0'
    call    mb_putc
.g_deco:
    call    at_decorations
    pop     r12
    ret
.g_bad:
    mov     byte [rel at_err], 1
    pop     r12
    ret

; at_decorations: {...} groups at token rcx, written without blanks (a
; register's % dropped); rcx past them
at_decorations:
.c_group:
    cmp     rcx, [rel mt_n]
    jae     .c_ret
    call    mt_kind
    cmp     eax, TOK_LBRACE
    jne     .c_ret
.c_tok:
    cmp     rcx, [rel mt_n]
    jae     .c_ret
    call    mt_kind
    push    rax
    call    at_bare_text
    inc     rcx
    pop     rax
    cmp     eax, TOK_RBRACE
    jne     .c_tok
    jmp     .c_group
.c_ret:
    ret

; at_bare_text: token rcx's text, a register's without its %, lower case.
; Preserves rcx.
at_bare_text:
    push    rcx
    push    r12
    call    mt_tok
    mov     r12, rax
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .x_text
    mov     rsi, [r12 + TOKEN_value]
    cmp     byte [rsi], '%'
    jne     .x_text
    inc     rsi
    call    at_put_lower
    jmp     .x_ret
.x_text:
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, 1
    call    prep_tokens_text
    test    rax, rax
    jnz     .x_ret
    mov     rsi, rdx
    call    mb_putz
.x_ret:
    pop     r12
    pop     rcx
    ret

; at_put_lower: rsi's text in lower case. Preserves rcx, rsi.
at_put_lower:
    push    rsi
.u_next:
    mov     al, [rsi]
    test    al, al
    jz      .u_ret
    cmp     al, 'A'
    jb      .u_put
    cmp     al, 'Z'
    ja      .u_put
    or      al, 0x20
.u_put:
    call    mb_putc
    inc     rsi
    jmp     .u_next
.u_ret:
    pop     rsi
    ret

; at_size_word: the size word for eax bits ("dword "; nothing for 0)
at_size_word:
    lea     rsi, [rel s_byte]
    cmp     eax, 8
    je      .z_put
    lea     rsi, [rel s_word]
    cmp     eax, 16
    je      .z_put
    lea     rsi, [rel s_dword]
    cmp     eax, 32
    je      .z_put
    lea     rsi, [rel s_qword]
    cmp     eax, 64
    je      .z_put
    lea     rsi, [rel s_tword]
    cmp     eax, 80
    je      .z_put
    lea     rsi, [rel s_oword]
    cmp     eax, 128
    je      .z_put
    lea     rsi, [rel s_yword]
    cmp     eax, 256
    je      .z_put
    lea     rsi, [rel s_zword]
    cmp     eax, 512
    je      .z_put
    ret
.z_put:
    jmp     mb_putz

; ---- memory -------------------------------

; at_memory: tokens [rcx, rdx) as a memory operand, r8d = 1 after a * (an
; indirect far branch: "far SIZE")
;   seg:disp(base, index, scale){decorations}
at_memory:
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 48
    mov     r12, rcx                       ; start
    mov     r13, rdx                       ; end
    mov     [rsp + 40], r8
    ; [rsp]: segment name (0), [rsp + 8]: group's "(" (-1 none),
    ; [rsp + 16]: decorations' start, [rsp + 24] base / index / scale
    mov     qword [rsp], 0
    mov     qword [rsp + 8], -1
    mov     [rsp + 16], r13
    ; a segment
    mov     rcx, r12
    call    at_segment
    test    eax, eax
    jz      .m_noseg
    mov     [rsp], r8
    mov     r12, rcx
.m_noseg:
    ; decorations at the end ({1to16})
.m_deco:
    cmp     r13, r12
    jbe     .m_deco_done
    lea     rcx, [r13 - 1]
    call    mt_kind
    cmp     eax, TOK_RBRACE
    jne     .m_deco_done
.m_deco_back:
    cmp     rcx, r12
    jbe     .m_deco_done
    dec     rcx
    call    mt_kind
    cmp     eax, TOK_LBRACE
    jne     .m_deco_back
    mov     r13, rcx
    mov     [rsp + 16], rcx
    jmp     .m_deco
.m_deco_done:
    ; the (base, index, scale) group: a ")" last whose "(" has a register
    ; or a "," after it
    cmp     r13, r12
    jbe     .m_group_done
    lea     rcx, [r13 - 1]
    call    mt_kind
    cmp     eax, TOK_RPAREN
    jne     .m_group_done
    xor     edx, edx                       ; depth
.m_group_back:
    call    mt_kind
    cmp     eax, TOK_RPAREN
    jne     .m_gb_l
    inc     edx
.m_gb_l:
    cmp     eax, TOK_LPAREN
    jne     .m_gb_step
    dec     edx
    jz      .m_group_open
.m_gb_step:
    cmp     rcx, r12
    jbe     .m_group_done
    dec     rcx
    jmp     .m_group_back
.m_group_open:
    lea     rdx, [rcx + 1]
    push    rcx
    mov     rcx, rdx
    call    mt_kind
    pop     rcx
    cmp     eax, TOK_COMMA
    je      .m_group_is
    push    rcx
    inc     rcx
    call    at_reg_name
    pop     rcx
    test    rsi, rsi
    jz      .m_group_done
.m_group_is:
    mov     [rsp + 8], rcx
.m_group_done:
    ; the size, then "["
    mov     rax, [rsp + 40]
    test    eax, eax
    jz      .m_size
    test    dword [rel at_fl], AF_FAR
    jz      .m_size
    lea     rsi, [rel s_far]
    call    mb_putz
    mov     eax, [rel at_size]
    test    eax, eax
    jnz     .m_far_size
    mov     eax, 32
    cmp     byte [rel asm_bits], 16
    jne     .m_far_size
    mov     eax, 16
.m_far_size:
    call    at_size_word
    jmp     .m_open
.m_size:
    test    dword [rel at_fl], AF_NOSIZE | AF_ABS64
    jnz     .m_open
    mov     eax, [rel at_size]
    test    eax, eax
    jnz     .m_sized
    ; push / pop with no suffix: the stack's width, as GNU as takes it
    test    dword [rel at_fl], AF_STACK
    jz      .m_open
    movzx   eax, byte [rel asm_bits]
.m_sized:
    call    at_size_word
.m_open:
    mov     al, '['
    call    mb_putc
    test    dword [rel at_fl], AF_ABS64
    jz      .m_seg
    lea     rsi, [rel s_qbr]
    call    mb_putz
.m_seg:
    mov     rsi, [rsp]
    test    rsi, rsi
    jz      .m_body
    call    at_put_lower
    mov     al, ':'
    call    mb_putc
.m_body:
    ; disp = [r12, group or r13)
    mov     r14, [rsp + 8]
    cmp     r14, -1
    jne     .m_based
    ; no base, no index: an absolute address (abs in 64-bit code, unless a
    ; segment or movabs says)
    cmp     qword [rsp], 0
    jne     .m_abs_disp
    test    dword [rel at_fl], AF_ABS64
    jnz     .m_abs_disp
    cmp     byte [rel asm_bits], 64
    jne     .m_abs_disp
    lea     rsi, [rel s_abs]
    call    mb_putz
.m_abs_disp:
    mov     rcx, r12
    mov     rdx, r13
    cmp     rcx, rdx
    jae     .m_bad
    call    at_expr
    jmp     .m_close
.m_based:
    ; base, index, scale: the group's parts at its commas
    lea     rcx, [r14 + 1]                 ; past "("
    lea     r15, [r13 - 1]                 ; its ")"
    ; base
    xor     ebp, ebp                       ; something written
    call    mt_kind
    cmp     eax, TOK_COMMA
    je      .m_index
    call    at_reg_name
    test    rsi, rsi
    jz      .m_bad
    ; %rip: rip-relative - "rel x" for a name, "rip + N" for a number
    cmp     word [rsi], 'ri'
    jne     .m_base
    cmp     word [rsi + 2], 'p'            ; "rip" (its NUL after)
    jne     .m_base
    lea     rax, [rcx + 1]
    cmp     rax, r15
    jne     .m_bad                         ; (%rip, ...) has nothing more
    call    at_has_name
    test    eax, eax
    jz      .m_base
    lea     rsi, [rel s_rel]
    call    mb_putz
    mov     rcx, r12
    mov     rdx, r14
    call    at_expr
    jmp     .m_close
.m_base:
    call    at_put_lower
    inc     rcx
    mov     ebp, 1
    cmp     rcx, r15
    jae     .m_disp
    call    mt_kind
    cmp     eax, TOK_COMMA
    jne     .m_bad
.m_index:
    inc     rcx                            ; past ","
    cmp     rcx, r15
    jae     .m_disp
    call    mt_kind
    cmp     eax, TOK_COMMA
    je      .m_scale                       ; (%rax,,2)? no index
    call    at_reg_name
    test    rsi, rsi
    jz      .m_bad
    test    ebp, ebp
    jz      .m_index_first
    push    rsi
    lea     rsi, [rel s_plus]
    call    mb_putz
    pop     rsi
.m_index_first:
    call    at_put_lower
    mov     ebp, 1
    inc     rcx
    cmp     rcx, r15
    jae     .m_disp
    call    mt_kind
    cmp     eax, TOK_COMMA
    jne     .m_bad
.m_scale:
    inc     rcx
    cmp     rcx, r15
    jae     .m_disp
    mov     al, '*'
    call    mb_putc
    mov     rdx, r15
    call    at_expr
.m_disp:
    ; the displacement after: " + (disp)" (a reloc's "wrt": no brackets,
    ; which wrt does not go inside)
    cmp     r12, r14
    jae     .m_close
    test    ebp, ebp
    jz      .m_disp_alone
    mov     rcx, r12
    mov     rdx, r14
    call    at_has_reloc
    test    eax, eax
    jnz     .m_disp_wrt
    lea     rsi, [rel s_plus_p]
    call    mb_putz
    mov     rcx, r12
    mov     rdx, r14
    call    at_expr
    mov     al, ')'
    call    mb_putc
    jmp     .m_close
.m_disp_wrt:
    lea     rsi, [rel s_plus]
    call    mb_putz
.m_disp_alone:
    mov     rcx, r12
    mov     rdx, r14
    call    at_expr
.m_close:
    mov     al, ']'
    call    mb_putc
    ; the decorations
    mov     rcx, [rsp + 16]
    call    at_decorations
    jmp     .m_ret
.m_bad:
    mov     byte [rel at_err], 1
.m_ret:
    add     rsp, 48
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; at_has_name: a name among tokens [r12, r14)? eax = 1. Preserves rcx,
; rsi.
at_has_name:
    push    rcx
    mov     rcx, r12
.h_next:
    xor     eax, eax
    cmp     rcx, r14
    jae     .h_ret
    call    mt_kind
    inc     rcx
    cmp     eax, TOK_IDENT
    jne     .h_next
    mov     eax, 1
.h_ret:
    pop     rcx
    ret

; at_has_reloc: a name with @ among tokens [rcx, rdx)? eax = 1
at_has_reloc:
.a_next:
    xor     eax, eax
    cmp     rcx, rdx
    jae     .a_ret
    push    rdx
    call    mt_tok
    pop     rdx
    inc     rcx
    cmp     byte [rax + TOKEN_kind], TOK_IDENT
    jne     .a_next
    mov     rsi, [rax + TOKEN_value]
.a_at:
    mov     al, [rsi]
    test    al, al
    jz      .a_next
    inc     rsi
    cmp     al, '@'
    jne     .a_at
    mov     eax, 1
.a_ret:
    ret

; ---- expressions --------------------------

; at_expr: tokens [rcx, rdx) as an expression in utasm's syntax: a name as
; $name ("." is $), sym@PLT as "$sym wrt ..plt", 017 as 0o17
at_expr:
    push    r12
    push    r13
    mov     r12, rcx
    mov     r13, rdx
.x_next:
    cmp     r12, r13
    jae     .x_done
    mov     rcx, r12
    call    mt_tok
    movzx   edx, byte [rax + TOKEN_kind]
    cmp     edx, TOK_IDENT
    je      .x_name
    cmp     edx, TOK_NUMBER
    je      .x_number
    call    at_bare_text
    jmp     .x_step
.x_name:
    mov     rsi, [rax + TOKEN_value]
    cmp     byte [rsi], '%'
    jne     .x_symbol
    call    at_bare_text                   ; (a register in arithmetic)
    jmp     .x_step
.x_symbol:
    cmp     word [rsi], '.'                ; "." alone: here
    jne     .x_named
    mov     al, '$'
    call    mb_putc
    jmp     .x_step
.x_named:
    call    at_symbol
    jmp     .x_step
.x_number:
    mov     rsi, [rax + TOKEN_value]
    cmp     byte [rsi], '0'
    jne     .x_num_text
    movzx   eax, byte [rsi + 1]
    sub     eax, '0'
    cmp     eax, 7
    ja      .x_num_text
    ; 017: octal, if digits 0-7 only
    lea     rdi, [rsi + 1]
.x_oct:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .x_oct_yes
    sub     eax, '0'
    cmp     eax, 7
    ja      .x_num_text
    inc     rdi
    jmp     .x_oct
.x_oct_yes:
    mov     al, '0'
    call    mb_putc
    mov     al, 'o'
    call    mb_putc
    inc     rsi
    call    mb_putz
    jmp     .x_step
.x_num_text:
    call    at_bare_text
.x_step:
    inc     r12
    cmp     r12, r13
    jae     .x_done
    mov     al, ' '
    call    mb_putc
    jmp     .x_next
.x_done:
    pop     r13
    pop     r12
    ret

; at_symbol: the name rsi as $name; with @RELOC "$name wrt ..reloc"
at_symbol:
    push    r12
    mov     r12, rsi
    mov     al, '$'
    call    mb_putc
    ; the name, to its @
.y_name:
    mov     al, [r12]
    test    al, al
    jz      .y_ret
    cmp     al, '@'
    je      .y_reloc
    call    mb_putc
    inc     r12
    jmp     .y_name
.y_reloc:
    inc     r12                            ; the reloc's name
    lea     rsi, [rel s_wrt]
    call    mb_putz
    lea     rsi, [rel att_relocs]
.y_entry:
    cmp     byte [rsi], 0
    je      .y_unknown
    mov     rdi, r12
    call    at_streq_ci
    push    rax
    call    at_skipz
    pop     rax
    test    eax, eax
    jnz     .y_hit
    call    at_skipz
    jmp     .y_entry
.y_hit:
    call    mb_putz
    jmp     .y_ret
.y_unknown:
    ; as written: utasm names the error ("..x")
    mov     al, '.'
    call    mb_putc
    call    mb_putc
    mov     rsi, r12
    call    at_put_lower
.y_ret:
    pop     r12
    ret

; at_streq_ci: rdi (any case) equal to rsi (upper case)? eax = 1. Preserves
; rsi, rdi.
at_streq_ci:
    xor     ecx, ecx
.q_next:
    movzx   eax, byte [rdi + rcx]
    cmp     eax, 'a'
    jb      .q_cmp
    cmp     eax, 'z'
    ja      .q_cmp
    and     eax, ~0x20
.q_cmp:
    cmp     al, [rsi + rcx]
    jne     .q_no
    inc     ecx
    test    eax, eax
    jnz     .q_next
    mov     eax, 1
    ret
.q_no:
    xor     eax, eax
    ret
