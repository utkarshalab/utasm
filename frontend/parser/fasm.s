;
; ============================================
; File     : frontend/parser/fasm.s
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
; FASM'S VIRTUAL, LOAD AND STORE
; ============================================================================
;   virtual [at ADDR] ... end virtual
;       what is between is assembled and laid out from ADDR (from $ with no
;       "at") into a space of its own, written nowhere: its labels are plain
;       numbers, its bytes there for "load" - an instruction's length or
;       encoding at assembly time ("virtual at 0 / mov eax, ebx / len = $
;       / load op byte from 0 / end virtual"). They nest.
;   load NAME [byte|word|dword|qword] from ADDR
;       NAME (a constant, set again each time) the bytes at ADDR of the
;       space being assembled (the section, or the virtual block), little
;       endian; a byte when no size is written
;   store [byte|word|dword|qword] VALUE at ADDR
;       those bytes made VALUE: an image patched, checksummed or encoded at
;       assembly time
; The bytes must be there and final: not past the end, not a field a
; relocation or a jump fills in later (a forward jump's displacement) -
; else an error. ADDR is a label (or $) of that space, or an address in a
; virtual block or a flat binary's first section.

extern  preprocessor_peek_token
extern  preprocessor_next_token
extern  preprocessor_unread_token
extern  parser_evaluate_expression
extern  parser_gas_name
extern  parser_pos_label
extern  parser_abs_place
extern  symbol_find
extern  symbol_add
extern  asm_ctx_create_section
extern  error_set_subject
extern  error_loc_file, error_loc_line
extern  relax_count, relax_truncate, relax_overlap
extern  str_cmp_kw

%define VIRT_MAX     32

[SECTION .rodata]
s_virtual:  db "virtual", 0
s_at:       db "at", 0
s_from:     db "from", 0
s_byte:     db "byte", 0
s_word:     db "word", 0
s_dword:    db "dword", 0
s_qword:    db "qword", 0
s_endv:     db "end virtual", 0

[SECTION .bss]
alignb 8
; the virtual blocks open: the section left, the relocations and relaxation
; records then, where it opened
virt_prev:      resq VIRT_MAX
virt_nrelocs:   resd VIRT_MAX
virt_relax:     resq VIRT_MAX
virt_file:      resq VIRT_MAX
virt_line:      resd VIRT_MAX
virt_n:         resq 1

[SECTION .text]

; ---- fasm_virtual -------------------------
;
; fasm_virtual
; "virtual [at ADDR]": the block opened.
; Input    : rdi = PrepState (the operands next)
; Output   : rax = OK or an error
;
global fasm_virtual
fasm_virtual:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rax, [rel virt_n]
    cmp     rax, VIRT_MAX
    jae     .deep
    ; ADDR: after "at", else $
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .here
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_at]
    call    str_cmp_kw
    test    rax, rax
    jnz     .here
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    jmp     .placed
.here:
    xor     edi, edi
    call    parser_pos_label               ; ($: rdx = its label)
    test    rax, rax
    jnz     .ret
    mov     r11, rdx
    mov     rdx, [r11 + SYMBOL_value]
.placed:
    call    parser_abs_place               ; rdx = the address it starts at
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    ; the space: a section of the output's list for no longer than made
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel s_virtual]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     rdi, [rbx + PREP_ctx]
    dec     word [rdi + ASMCTX_seccount]
    mov     byte [rdx + SECTION_type], SEC_ABSOLUTE   ; (its labels numbers)
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     byte [rdx + SECTION_relax_frozen], 1      ; (its bytes as made)
    mov     [rdx + SECTION_addr], r12
    mov     qword [rdx + SECTION_size], 0
    ; what is restored at its end
    mov     rcx, [rel virt_n]
    mov     rax, [rdi + ASMCTX_curr_sec]
    lea     r8, [rel virt_prev]
    mov     [r8 + rcx * 8], rax
    mov     eax, [rdi + ASMCTX_nrelocs]
    lea     r8, [rel virt_nrelocs]
    mov     [r8 + rcx * 4], eax
    push    rdx
    call    relax_count
    pop     rdx
    lea     r8, [rel virt_relax]
    mov     [r8 + rcx * 8], rax
    mov     rax, [rel error_loc_file]
    lea     r8, [rel virt_file]
    mov     [r8 + rcx * 8], rax
    mov     eax, [rel error_loc_line]
    lea     r8, [rel virt_line]
    mov     [r8 + rcx * 4], eax
    inc     qword [rel virt_n]
    mov     [rdi + ASMCTX_curr_sec], rdx
    xor     eax, eax
    jmp     .ret
.deep:
    mov     eax, EXIT_COND_DEPTH
.ret:
    pop     r12
    pop     rbx
    ret

; ---- fasm_end_virtual ---------------------
;
; fasm_end_virtual
; "end virtual": the block closed - the section before it current again,
; the block's relocations and relaxation records dropped.
; Input    : rdi = PrepState
; Output   : rax = OK or an error
;
global fasm_end_virtual
fasm_end_virtual:
    mov     rax, [rel virt_n]
    test    rax, rax
    jz      .stray
    dec     rax
    mov     [rel virt_n], rax
    mov     rdi, [rdi + PREP_ctx]
    lea     r8, [rel virt_prev]
    mov     rcx, [r8 + rax * 8]
    mov     [rdi + ASMCTX_curr_sec], rcx
    lea     r8, [rel virt_nrelocs]
    mov     ecx, [r8 + rax * 4]
    mov     [rdi + ASMCTX_nrelocs], ecx
    lea     r8, [rel virt_relax]
    mov     rdi, [r8 + rax * 8]
    call    relax_truncate
    xor     eax, eax
    ret
.stray:
    lea     rdi, [rel s_endv]
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    ret

; ---- fasm_finish --------------------------
;
; fasm_finish
; The source read: a virtual block still open is an error (where it opened).
; Output   : rax = OK or EXIT_VIRTUAL_OPEN
;
global fasm_finish
fasm_finish:
    xor     eax, eax
    cmp     qword [rel virt_n], 0
    je      .ret
    mov     rax, [rel virt_file]
    mov     [rel error_loc_file], rax
    mov     eax, [rel virt_line]
    mov     [rel error_loc_line], eax
    mov     qword [rel virt_n], 0
    mov     eax, EXIT_VIRTUAL_OPEN
.ret:
    ret

; ---- fasm_load / fasm_store ---------------
;
; fasm_load
; "load NAME [SIZE] from ADDR".
; Input    : rdi = PrepState (the operands next)
; Output   : rax = OK or an error
;
global fasm_load
fasm_load:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    parser_gas_name
    mov     r12, rsi                       ; NAME
    call    fasm_size                      ; r13 = the size
    test    rax, rax
    jnz     .ret
    ; from
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_from]
    call    str_cmp_kw
    test    rax, rax
    jnz     .bad
    call    fasm_place                     ; r14 = the section, r15 = offset
    test    rax, rax
    jnz     .ret
    ; the value, little endian
    mov     rsi, [r14 + SECTION_data]
    add     rsi, r15
    xor     eax, eax
    mov     rcx, r13
.byte:
    dec     rcx
    shl     rax, 8
    movzx   edx, byte [rsi + rcx]
    or      rax, rdx
    test    rcx, rcx
    jnz     .byte
    mov     r13, rax
    ; NAME = it: a constant, set again when there already
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .new
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .taken
    mov     [rdx + SYMBOL_value], r13
    xor     eax, eax
    jmp     .ret
.new:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_CONSTANT
    mov     [rsp + SYMBOL_name], r12
    mov     [rsp + SYMBOL_value], r13
    mov     word [rsp + SYMBOL_section], SHN_ABS
    mov     eax, [rel error_loc_line]
    mov     [rsp + SYMBOL_line], eax
    mov     rax, [rel error_loc_file]
    mov     [rsp + SYMBOL_file], rax
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    jmp     .ret
.taken:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_DUP_SYMBOL
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; fasm_store
; "store [SIZE] VALUE at ADDR".
; Input    : rdi = PrepState (the operands next)
; Output   : rax = OK or an error
;
global fasm_store
fasm_store:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    call    fasm_size                      ; r13 = the size
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    test    rcx, rcx
    jnz     .not_number
    test    r11, r11
    jz      .number
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    jne     .not_number
.number:
    mov     r12, rdx                       ; VALUE
    ; at
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_at]
    call    str_cmp_kw
    test    rax, rax
    jnz     .bad
    call    fasm_place
    test    rax, rax
    jnz     .ret
    mov     rdi, [r14 + SECTION_data]
    add     rdi, r15
    mov     rax, r12
    mov     rcx, r13
.byte:
    mov     [rdi], al
    inc     rdi
    shr     rax, 8
    dec     rcx
    jnz     .byte
    xor     eax, eax
    jmp     .ret
.not_number:
    mov     eax, EXIT_NOT_SIMPLE
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; fasm_size: an optional byte / word / dword / qword: r13 = 1, 2, 4, 8
; (1 when none). Output rax = OK or error
fasm_size:
    mov     r13d, 1
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .sz_ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .sz_ok
    mov     r8, [rdx + TOKEN_value]
    mov     rdi, r8
    lea     rsi, [rel s_byte]
    call    str_cmp_kw
    mov     r13d, 1
    test    rax, rax
    jz      .sz_take
    mov     rdi, r8
    lea     rsi, [rel s_word]
    call    str_cmp_kw
    mov     r13d, 2
    test    rax, rax
    jz      .sz_take
    mov     rdi, r8
    lea     rsi, [rel s_dword]
    call    str_cmp_kw
    mov     r13d, 4
    test    rax, rax
    jz      .sz_take
    mov     rdi, r8
    lea     rsi, [rel s_qword]
    call    str_cmp_kw
    mov     r13d, 8
    test    rax, rax
    jz      .sz_take
    mov     r13d, 1
    jmp     .sz_ok
.sz_take:
    mov     rdi, rbx
    call    preprocessor_next_token
.sz_ok:
    xor     eax, eax
.sz_ret:
    ret

; fasm_place: ADDR (an expression next) in the space being assembled:
; r14 = its section, r15 = the offset there - checked: r13 bytes there,
; and final
; Output rax = OK or error
fasm_place:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .pl_ret
    test    rcx, rcx
    jnz     .pl_later                      ; (a label not defined yet)
    mov     rax, [rbx + PREP_ctx]
    mov     r14, [rax + ASMCTX_curr_sec]
    test    r14, r14
    jz      .pl_range
    mov     r15, rdx
    ; a label of this section: its offset; a number (an absolute label):
    ; less the space's start
    test    r11, r11
    jz      .pl_number
    movzx   eax, word [r11 + SYMBOL_section]
    cmp     eax, SHN_ABS
    je      .pl_number
    cmp     ax, [r14 + SECTION_index]
    jne     .pl_range                      ; (another section's)
    jmp     .pl_have
.pl_number:
    sub     r15, [r14 + SECTION_addr]
.pl_have:
    ; inside what is made
    test    r15, r15
    js      .pl_range
    lea     rax, [r15 + r13]
    cmp     rax, [r14 + SECTION_size]
    ja      .pl_range
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    je      .pl_range
    ; final: no relocation field, no jump to come, over those bytes
    mov     rdi, r14
    mov     rsi, r15
    lea     rdx, [r15 + r13]
    call    fasm_reloc_overlap
    test    eax, eax
    jnz     .pl_not_final
    cmp     byte [r14 + SECTION_relax_frozen], 0
    jne     .pl_final                      ; (a virtual block: as made)
    mov     rdi, r14
    mov     rsi, r15
    lea     rdx, [r15 + r13]
    call    relax_overlap
    test    eax, eax
    jnz     .pl_not_final
.pl_final:
    xor     eax, eax
.pl_ret:
    ret
.pl_range:
    mov     eax, EXIT_LOAD_RANGE
    ret
.pl_later:
    mov     eax, EXIT_LOAD_LATER
    ret
.pl_not_final:
    mov     eax, EXIT_LOAD_LATER
    ret

; fasm_reloc_overlap: a relocation of section rdi over [rsi, rdx)? eax = 1
fasm_reloc_overlap:
    push    r12
    mov     r8, [rbx + PREP_ctx]
    mov     ecx, [r8 + ASMCTX_nrelocs]
    mov     r9, [r8 + ASMCTX_relocs]
    xor     eax, eax
.ro_next:
    test    ecx, ecx
    jz      .ro_ret
    dec     ecx
    imul    r10, rcx, RELOC_SIZE
    add     r10, r9
    cmp     [r10 + RELOC_section], rdi
    jne     .ro_next
    ; its field's size by its type
    mov     r12d, [r10 + RELOC_type]
    mov     r11d, 4
    cmp     r12d, 1                        ; R_X86_64_64
    je      .ro_8
    cmp     r12d, 24                       ; PC64
    je      .ro_8
    cmp     r12d, 25                       ; GOTOFF64
    je      .ro_8
    cmp     r12d, 16
    jb      .ro_small
    cmp     r12d, 18                       ; DTPMOD64 DTPOFF64 TPOFF64
    jbe     .ro_8
.ro_small:
    cmp     r12d, 12                       ; 16 / PC16
    je      .ro_2
    cmp     r12d, 13
    je      .ro_2
    cmp     r12d, 14                       ; 8 / PC8
    je      .ro_1
    cmp     r12d, 15
    je      .ro_1
    jmp     .ro_size
.ro_8:
    mov     r11d, 8
    jmp     .ro_size
.ro_2:
    mov     r11d, 2
    jmp     .ro_size
.ro_1:
    mov     r11d, 1
.ro_size:
    mov     r8, [r10 + RELOC_offset]
    cmp     r8, rdx
    jae     .ro_next
    add     r8, r11
    cmp     r8, rsi
    jbe     .ro_next
    mov     eax, 1
.ro_ret:
    pop     r12
    ret

; ---- fasm_defined -------------------------
;
; fasm_defined
; "defined NAME" in an expression: 1 when NAME is a label or a constant
; defined so far (not one only named, nor an extern), else 0. utasm reads
; the source once: a label defined further on is not defined yet.
; Input    : rdi = PrepState (NAME, or (NAME), next)
; Output   : rax = OK or an error, rdx = 1 / 0
;
global fasm_defined
fasm_defined:
    push    rbx
    push    r12
    mov     rbx, rdi
    xor     r12d, r12d                     ; 1: in parentheses
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .name
    mov     r12d, 1
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
.name:
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    parser_gas_name
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    xor     ecx, ecx
    test    rax, rax
    jnz     .known
    cmp     byte [rdx + SYMBOL_kind], SYM_EXTERN
    je      .known
    cmp     word [rdx + SYMBOL_section], 0
    je      .known
    mov     ecx, 1
.known:
    push    rcx
    test    r12d, r12d
    jz      .done
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .pop_ret
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .pop_bad
.done:
    pop     rdx
    xor     eax, eax
    jmp     .ret
.pop_bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.pop_ret:
    pop     rdx
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r12
    pop     rbx
    ret

; ============================================================================
; FASM'S FORMAT, ENTRY AND SEGMENT
; ============================================================================
;   format ELF64 executable [N]     an executable, as --standalone: written
;                                   whole, no linker (the source's name
;                                   without its extension when no -o)
;   format ELF64 / ELF / binary     the format -f gives (another one: an
;                                   error - it is chosen before the source)
;   entry NAME                      where the executable starts (_start
;                                   when there is no entry line)
;   segment readable executable     after a format line: section .text
;   segment readable writeable      ... .data, "segment readable" .rodata

[SECTION .rodata]
w_elf64:    db "elf64", 0
w_elf:      db "elf", 0
w_binary:   db "binary", 0
w_exec:     db "executable", 0
w_readable: db "readable", 0
w_writeable: db "writeable", 0
w_writable: db "writable", 0
w_execute:  db "executable", 0
t_text:     db 10, "section .text", 10
t_text_len  equ $ - t_text
t_data:     db 10, "section .data", 10
t_data_len  equ $ - t_data
t_rodata:   db 10, "section .rodata", 10
t_rodata_len equ $ - t_rodata
s_segment:  db "segment", 0

[SECTION .bss]
global fasm_entry_name
fasm_entry_name: resq 1             ; entry NAME, or 0 (_start)
fasm_formatted: resb 1              ; a format line was read
fasm_out:       resb 4096           ; the executable's name (no -o)

[SECTION .text]

extern  prep_push_buffer
extern  cli_output_given
extern  elf32_enabled, coff_enabled

; ---- fasm_format --------------------------
;
; fasm_format
; "format ELF64 [executable [N]]", "format ELF", "format binary".
; Input    : rdi = PrepState (the operands next)
; Output   : rax = OK or an error
;
global fasm_format
fasm_format:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]
    mov     byte [rel fasm_formatted], 1
    mov     rax, [rbx + PREP_ctx]
    ; ELF64
    mov     rdi, r12
    lea     rsi, [rel w_elf64]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_elf64
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_ELF64
    jne     .other
    cmp     byte [rel elf32_enabled], 0
    jne     .other
    cmp     byte [rel coff_enabled], 0
    jne     .other
    ; executable [N]
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_exec]
    call    str_cmp_kw
    test    rax, rax
    jnz     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rax, [rbx + PREP_ctx]
    mov     byte [rax + ASMCTX_standalone], 1
    ; no -o: the source's name without its extension
    cmp     byte [rel cli_output_given], 0
    jne     .abi
    mov     rsi, [rax + ASMCTX_input]
    lea     rdi, [rel fasm_out]
    xor     ecx, ecx
    xor     edx, edx                       ; the last '.' after the last '/'
.copy:
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    test    al, al
    jz      .copied
    cmp     al, '/'
    jne     .copy_dot
    xor     edx, edx
.copy_dot:
    cmp     al, '.'
    jne     .copy_next
    mov     rdx, rcx
.copy_next:
    inc     rcx
    cmp     rcx, 4000
    jb      .copy
.copied:
    test    rdx, rdx
    jz      .named
    mov     byte [rdi + rdx], 0
.named:
    mov     rax, [rbx + PREP_ctx]
    mov     [rax + ASMCTX_output], rdi
.abi:
    ; [N]: the OS ABI byte (taken)
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .done
.not_elf64:
    mov     rdi, r12
    lea     rsi, [rel w_elf]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_elf
    cmp     byte [rel elf32_enabled], 0
    je      .other
    jmp     .done
.not_elf:
    mov     rdi, r12
    lea     rsi, [rel w_binary]
    call    str_cmp_kw
    test    rax, rax
    jnz     .other
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    jne     .other
.done:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret
.other:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_FASM_FORMAT
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret

; ---- fasm_entry ---------------------------
;
; fasm_entry
; "entry NAME": the executable starts there.
; Input    : rdi = PrepState (NAME next)
; Output   : rax = OK or an error
;
global fasm_entry
fasm_entry:
    push    rbx
    mov     rbx, rdi
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     eax, EXIT_UNEXPECTED_TOKEN
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ret
    mov     rax, [rdx + TOKEN_value]
    mov     [rel fasm_entry_name], rax
    xor     eax, eax
.ret:
    pop     rbx
    ret

; ---- fasm_segment -------------------------
;
; fasm_segment
; After a format line, "segment readable executable" (.text), "segment
; readable writeable" (.data), "segment readable" (.rodata).
; Input    : rdi = PrepState (the words next)
; Output   : eax = 0: not FASM's (NASM's segment = section); 1: done, rdx =
;            OK or an error
;
global fasm_segment
fasm_segment:
    cmp     byte [rel fasm_formatted], 0
    jne     .on
    xor     eax, eax
    ret
.on:
    push    rbx
    push    r12
    mov     rbx, rdi
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .none
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_readable]
    call    str_cmp_kw
    mov     r12d, 0                        ; 1 exec, 2 write
    test    rax, rax
    jz      .words
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_writeable]
    call    str_cmp_kw
    test    rax, rax
    jz      .words
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_execute]
    call    str_cmp_kw
    test    rax, rax
    jnz     .none
.words:
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .chosen
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_execute]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_exec
    or      r12d, 1
    jmp     .words
.not_exec:
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_writeable]
    call    str_cmp_kw
    test    rax, rax
    jz      .write
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel w_writable]
    call    str_cmp_kw
    test    rax, rax
    jnz     .words
.write:
    or      r12d, 2
    jmp     .words
.chosen:
    lea     rsi, [rel t_rodata]
    mov     edx, t_rodata_len
    test    r12d, 1
    jz      .not_text
    lea     rsi, [rel t_text]
    mov     edx, t_text_len
    jmp     .push
.not_text:
    test    r12d, 2
    jz      .push
    lea     rsi, [rel t_data]
    mov     edx, t_data_len
.push:
    mov     rdi, rbx
    lea     rcx, [rel s_segment]
    call    prep_push_buffer
    mov     rdx, rax
    mov     eax, 1
    pop     r12
    pop     rbx
    ret
.none:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
