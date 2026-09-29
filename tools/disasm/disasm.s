;
; ============================================
; File     : tools/disasm/disasm.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"
%include "include/elf.inc"
%include "include/inspect.inc"

DEFAULT REL

; ============================================================================
; DISASSEMBLER (utasm --disasm)
; ============================================================================
; Prints every executable section of an ELF image as x86-64 instructions,
; one per line, in objdump's Intel style:
;
;   Disassembly of section '.text':
;
;   0000000000000000 <main>:
;     00000000:  48 89 e5                 mov    rbp,rsp
;     00000003:  74 05                    je     a <main+0xa>
;
; Runs as a part of the ELF inspector (INSPECT_DISASM), which has already
; validated the file, so section bytes are in bounds. Symbols come from the
; first SHT_SYMTAB: a symbol starting at an address prints a label line,
; and a direct branch target is annotated with the nearest symbol at or
; before it. Bytes that do not decode print as "(bad)", one byte at a time
; (see tools/disasm/x86.s for what decodes).
;
; Calling convention (AMD64): rdi = InspCtx; callee saved rbx, r12-r15.

%define DS_TEXT_MAX  256

extern x86_decode
extern fmt_init
extern fmt_str
extern fmt_char
extern fmt_pad
extern fmt_hex
extern fmt_udec
extern dump_pad_to
extern dump_udec_right
extern dump_put_hex0x
extern dump_put_name
extern dump_put_strtab
extern ins_flush_line
extern ins_shdr
extern ins_put_secname

[SECTION .bss]
align 8
ds_syms:    resq 1              ; first Elf64_Sym, or 0
ds_nsyms:   resq 1
ds_str:     resq 1              ; its string table, or 0
ds_strsize: resq 1
ds_secidx:  resq 1              ; section being disassembled
ds_textfb:  resb FMTBUF_SIZE    ; one instruction's text
ds_text:    resb DS_TEXT_MAX

[SECTION .text]

; ---- disasm_sections --------------------
;
; disasm_sections
; Disassembles every SHT_PROGBITS section with SHF_EXECINSTR.
; Input    : rdi = InspCtx (validated)
;
global disasm_sections
disasm_sections:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    call    ds_find_symtab

    xor     r14d, r14d                     ; r14 = sections printed
    xor     r12d, r12d                     ; r12 = section index
.sections:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .done
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_shdr
    mov     r13, rax
    cmp     dword [r13 + SHDR_TYPE], SHT_PROGBITS
    jne     .next
    test    qword [r13 + SHDR_FLAGS], SHF_EXECINSTR
    jz      .next
    cmp     qword [r13 + SHDR_SIZE], 0
    je      .next
    mov     rdi, r12
    call    ds_section
    inc     r14
.next:
    inc     r12
    jmp     .sections

.done:
    test    r14, r14
    jnz     .ret
    INS_PUTS "There are no executable sections."
    INS_NL
    INS_NL
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- ds_find_symtab (internal) ----------
;
; Remembers the first symbol table and its string table (0 if none).
; Uses rbx = InspCtx.
;
ds_find_symtab:
    push    r12
    push    r13
    xor     eax, eax
    mov     [rel ds_syms], rax
    mov     [rel ds_nsyms], rax
    mov     [rel ds_str], rax
    mov     [rel ds_strsize], rax
    xor     r12d, r12d
.loop:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .done
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_shdr
    mov     r13, rax
    cmp     dword [r13 + SHDR_TYPE], SHT_SYMTAB
    jne     .next
    cmp     qword [r13 + SHDR_ENTSIZE], ELF64_SYM_SIZE
    jne     .next
    mov     rax, [r13 + SHDR_OFFSET]
    add     rax, [rbx + INSPCTX_buf]
    mov     [rel ds_syms], rax
    mov     rax, [r13 + SHDR_SIZE]
    xor     edx, edx
    mov     ecx, ELF64_SYM_SIZE
    div     rcx
    mov     [rel ds_nsyms], rax
    mov     rdi, rbx
    mov     esi, [r13 + SHDR_LINK]
    call    ins_shdr
    test    rax, rax
    jz      .done
    cmp     dword [rax + SHDR_TYPE], SHT_NOBITS
    je      .done
    mov     rcx, [rax + SHDR_OFFSET]
    add     rcx, [rbx + INSPCTX_buf]
    mov     [rel ds_str], rcx
    mov     rcx, [rax + SHDR_SIZE]
    mov     [rel ds_strsize], rcx
    jmp     .done
.next:
    inc     r12
    jmp     .loop
.done:
    pop     r13
    pop     r12
    ret

; ---- ds_section (internal) --------------
;
; Disassembles one section.  Input: rdi = section index; rbx = InspCtx.
;
ds_section:
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 16
    mov     [rel ds_secidx], rdi
    mov     rsi, rdi
    mov     rdi, rbx
    call    ins_shdr
    mov     r13, rax                       ; r13 = shdr
    mov     r12, [r13 + SHDR_OFFSET]
    add     r12, [rbx + INSPCTX_buf]       ; r12 = section bytes
    mov     r15, [r13 + SHDR_SIZE]         ; r15 = size
    mov     rbp, [r13 + SHDR_ADDR]         ; rbp = address of byte 0

    INS_PUTS "Disassembly of section '"
    mov     rdi, rbx
    mov     rsi, [rel ds_secidx]
    call    ins_put_secname
    INS_PUTS "':"
    INS_NL

    xor     r14d, r14d                     ; r14 = offset
.insn:
    cmp     r14, r15
    jae     .end

    ; a label line for a symbol starting here
    lea     rdi, [rbp + r14]
    call    ds_label

    ; decode into ds_text
    lea     rdi, [rel ds_textfb]
    lea     rsi, [rel ds_text]
    mov     edx, DS_TEXT_MAX
    call    fmt_init
    ; like objdump, never decode across the start of the next symbol, so
    ; data inside code cannot swallow the first bytes of a function
    lea     rdi, [rbp + r14]
    call    ds_next_symbol                 ; rax = its address, or -1
    sub     rax, rbp                       ; as an offset in the section
    cmp     rax, r15
    jbe     .limit
    mov     rax, r15
.limit:
    mov     rsi, rax
    sub     rsi, r14                       ; bytes this instruction may use
    lea     rdi, [r12 + r14]
    lea     rdx, [rbp + r14]
    lea     rcx, [rel ds_textfb]
    call    x86_decode
    mov     [rsp], rdx                     ; branch target or -1
    test    rax, rax
    jnz     .decoded
    lea     rdi, [rel ds_textfb]
    lea     rsi, [rel s_bad]
    call    fmt_str
    mov     qword [rsp], -1
    mov     eax, 1                         ; skip one byte
.decoded:
    mov     [rsp + 8], rax                 ; length

    ; "  address:  bytes    text"
    INS_PUTS "  "
    lea     rax, [rbp + r14]
    INS_HEX rax, 8
    INS_PUTC ':'
    INS_PAD 13
    xor     ecx, ecx
.bytes:
    cmp     rcx, [rsp + 8]
    jae     .bytes_done
    push    rcx
    push    rcx
    lea     rax, [r14 + rcx]
    movzx   eax, byte [r12 + rax]
    INS_HEX rax, 2
    INS_PUTC ' '
    pop     rcx
    pop     rcx
    inc     rcx
    jmp     .bytes
.bytes_done:
    INS_PAD 37
    INS_PUTSTR [rel ds_textfb + FMTBUF_buf]

    ; " <symbol+0x..>" after a direct branch
    mov     rdi, [rsp]
    cmp     rdi, -1
    je      .no_target
    call    ds_annotate
.no_target:
    INS_NL

    add     r14, [rsp + 8]
    jmp     .insn

.end:
    INS_NL
    add     rsp, 16
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; ---- ds_sym_ok (internal) ---------------
;
; Is Elf64_Sym rsi a symbol of the current section worth naming (not a
; section or file symbol)? Output: eax = 1/0. Clobbers: ecx.
;
ds_sym_ok:
    xor     eax, eax
    movzx   ecx, word [rsi + SYM64_SHNDX]
    cmp     rcx, [rel ds_secidx]
    jne     .ret
    movzx   ecx, byte [rsi + SYM64_INFO]
    and     ecx, 0x0F
    cmp     ecx, STT_SECTION
    je      .ret
    cmp     ecx, STT_FILE
    je      .ret
    mov     eax, 1
.ret:
    ret

; ---- ds_next_symbol (internal) ---------
;
; Address of the first symbol of the section that starts after rdi, or
; -1 (all ones) if there is none. Clobbers: rcx, rdx, rsi, r8.
;
ds_next_symbol:
    mov     rax, -1
    mov     r8, [rel ds_syms]
    test    r8, r8
    jz      .ret
    xor     edx, edx
.loop:
    cmp     rdx, [rel ds_nsyms]
    jae     .ret
    push    rax
    mov     rsi, r8
    call    ds_sym_ok
    mov     ecx, eax
    pop     rax
    test    ecx, ecx
    jz      .next
    mov     rcx, [r8 + SYM64_VALUE]
    cmp     rcx, rdi
    jbe     .next
    cmp     rcx, rax
    jae     .next
    mov     rax, rcx
.next:
    add     r8, ELF64_SYM_SIZE
    inc     rdx
    jmp     .loop
.ret:
    ret

; ---- ds_label (internal) ----------------
;
; Prints "\n<address> <name>:" for the first symbol at address rdi.
;
ds_label:
    push    r12
    push    r13
    push    r14
    mov     r14, rdi
    mov     r12, [rel ds_syms]
    test    r12, r12
    jz      .ret
    xor     r13d, r13d
.loop:
    cmp     r13, [rel ds_nsyms]
    jae     .ret
    mov     rsi, r12
    call    ds_sym_ok
    test    eax, eax
    jz      .next
    cmp     [r12 + SYM64_VALUE], r14
    jne     .next
    INS_NL
    INS_HEX r14, 16
    INS_PUTS " <"
    call    .name
    INS_PUTS ">:"
    INS_NL
    jmp     .ret
.next:
    add     r12, ELF64_SYM_SIZE
    inc     r13
    jmp     .loop
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret
.name:
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, [rel ds_str]
    mov     rdx, [rel ds_strsize]
    mov     ecx, [r12 + SYM64_NAME]
    jmp     dump_put_strtab

; ---- ds_annotate (internal) -------------
;
; Appends " <name>" or " <name+0x..>" for the nearest symbol of the
; section at or before address rdi (nothing if there is none).
;
ds_annotate:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r14, rdi                       ; r14 = target
    xor     r15d, r15d                     ; r15 = best symbol
    mov     r12, [rel ds_syms]
    test    r12, r12
    jz      .ret
    xor     r13d, r13d
.loop:
    cmp     r13, [rel ds_nsyms]
    jae     .found
    mov     rsi, r12
    call    ds_sym_ok
    test    eax, eax
    jz      .next
    mov     rax, [r12 + SYM64_VALUE]
    cmp     rax, r14
    ja      .next
    test    r15, r15
    jz      .take
    cmp     rax, [r15 + SYM64_VALUE]
    jbe     .next                          ; keep the first of equals
.take:
    mov     r15, r12
.next:
    add     r12, ELF64_SYM_SIZE
    inc     r13
    jmp     .loop
.found:
    test    r15, r15
    jz      .ret
    INS_PUTS " <"
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, [rel ds_str]
    mov     rdx, [rel ds_strsize]
    mov     ecx, [r15 + SYM64_NAME]
    call    dump_put_strtab
    mov     rax, r14
    sub     rax, [r15 + SYM64_VALUE]
    test    rax, rax
    jz      .close
    push    rax
    push    rax
    INS_PUTC '+'
    pop     rax
    pop     rax
    INS_HEX0X rax
.close:
    INS_PUTC '>'
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
s_bad:  db "(bad)", 0
