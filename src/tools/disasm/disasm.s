;
; ============================================
; File     : src/tools/disasm/disasm.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"
%include "src/include/elf.inc"
%include "src/include/inspect.inc"

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
; (see src/tools/disasm/x86.s for what decodes).
;
; Calling convention (AMD64): rdi = InspCtx; callee saved rbx, r12-r15.

%define DS_TEXT_MAX  256

extern x86_decode
extern x86_rip_target
extern x86_mode
extern x86_hex0x
extern cli_bits
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
ds_secaddr: resq 1              ; its address and size
ds_secsize: resq 1
ds_rel:     resq 1              ; its relocations (ds_find_rel), or 0
ds_relcnt:  resq 1
ds_relent:  resq 1
ds_rela:    resb 1              ; 1: SHT_RELA (with addends)
ds_raw:     resb 1              ; 1: a raw file (disasm_raw)
ds_linked:  resb 1              ; 1: an executable / shared object (not ET_REL)
ds_anysec:  resb 1              ; ds_sym_ok: any section's symbols (ds_annotate)
alignb 4
ds_symtype: resd 1              ; ds_find_symtab: SHT_SYMTAB, then SHT_DYNSYM
ds_labw:    resb 1              ; a label line's address digits (16 / 8)
alignb 8
global disasm_org
disasm_org: resq 1              ; --org: a raw file's first address
global disasm_relocs
disasm_relocs: resb 1           ; -r: relocations after the instructions
ds_dry:     resb 1              ; ds_annotate: rax = the symbol, nothing printed
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
    mov     byte [rel ds_raw], 0
    mov     byte [rel x86_hex0x], 0
    call    ds_mode
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

; ---- disasm_raw -------------------------
;
; disasm_raw
; Disassembles a file that is no ELF one - a flat binary, a boot sector -
; as objdump -b binary does: one section ".data", at --org (default 0),
; in the --bits mode (default 64); no symbols, branch targets as "0x37".
; Input    : rdi = InspCtx (buf / len set)
;
global disasm_raw
disasm_raw:
    push    rbx
    mov     rbx, rdi
    mov     byte [rel ds_raw], 1
    mov     byte [rel x86_hex0x], 1
    call    ds_mode
    xor     eax, eax
    mov     [rel ds_syms], rax
    mov     [rel ds_nsyms], rax
    mov     [rel ds_rel], rax
    xor     edi, edi
    call    ds_section
    pop     rbx
    ret

; ---- ds_mode (internal) -----------------
;
; The decoder's mode: --bits, else the file's - 32 for an i386 one (ELF32,
; widened), 64 otherwise (ELF64 x86-64, -b binary). Uses rbx.
;
ds_mode:
    movzx   eax, byte [rel cli_bits]
    test    eax, eax
    jnz     .set
    mov     eax, 64
    cmp     byte [rel ds_raw], 0
    jne     .set
    mov     rcx, [rbx + INSPCTX_buf]
    cmp     word [rcx + EHDR_MACHINE], EM_386
    jne     .set
    mov     eax, 32
.set:
    mov     [rel x86_mode], al
    mov     byte [rel ds_labw], 16         ; (a label's address: objdump's 8
    cmp     eax, 64                        ; digits outside 64-bit mode)
    je      .labw
    mov     byte [rel ds_labw], 8
.labw:
    ret

; ---- ds_put_secname (internal) ----------
;
; The section's name (ds_secidx; ".data" for a raw file). Uses rbx.
;
ds_put_secname:
    cmp     byte [rel ds_raw], 0
    je      .elf
    INS_PUTS ".data"
    ret
.elf:
    mov     rdi, rbx
    mov     rsi, [rel ds_secidx]
    jmp     ins_put_secname

; ---- ds_find_symtab (internal) ----------
;
; Remembers the first symbol table and its string table (0 if none).
; Uses rbx = InspCtx.
;
ds_find_symtab:
    push    r12
    push    r13
    mov     rcx, [rbx + INSPCTX_buf]
    cmp     word [rcx + EHDR_TYPE], ET_REL
    setne   byte [rel ds_linked]
    mov     dword [rel ds_symtype], SHT_SYMTAB
    call    .find
    cmp     qword [rel ds_syms], 0
    jne     .found
    mov     dword [rel ds_symtype], SHT_DYNSYM ; (stripped: the dynamic ones)
    call    .find
.found:
    pop     r13
    pop     r12
    ret
.find:
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
    mov     eax, [rel ds_symtype]
    cmp     [r13 + SHDR_TYPE], eax
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
    cmp     byte [rel ds_raw], 0
    jne     .raw
    mov     rsi, rdi
    mov     rdi, rbx
    call    ins_shdr
    mov     r13, rax                       ; r13 = shdr
    mov     r12, [r13 + SHDR_OFFSET]
    add     r12, [rbx + INSPCTX_buf]       ; r12 = section bytes
    mov     r15, [r13 + SHDR_SIZE]         ; r15 = size
    mov     rbp, [r13 + SHDR_ADDR]         ; rbp = address of byte 0
    call    ds_find_rel
    jmp     .region
.raw:                                      ; a raw file: all of it, at --org
    mov     r12, [rbx + INSPCTX_buf]
    mov     r15, [rbx + INSPCTX_len]
    mov     rbp, [rel disasm_org]
.region:
    mov     [rel ds_secaddr], rbp
    mov     [rel ds_secsize], r15

    INS_PUTS "Disassembly of section '"
    call    ds_put_secname
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
    ; "        # 13 <sym+0x7>" after a [rip + disp] operand
    mov     rax, [rel x86_rip_target]
    cmp     rax, -1
    je      .no_rip
    push    rax
    push    rax
    INS_PUTS "        # "
    mov     byte [rel ds_dry], 1           ; a symbol for it? "13 <sym+0x7>",
    mov     rdi, [rsp]                     ; else "0x13"
    call    ds_annotate
    mov     byte [rel ds_dry], 0
    test    rax, rax
    jnz     .rip_sym
    INS_PUTS "0x"
.rip_sym:
    mov     rax, [rsp]
    INS_HEX rax, 0
    pop     rdi
    pop     rdi
    call    ds_annotate
.no_rip:
    INS_NL
    cmp     byte [rel disasm_relocs], 0
    je      .no_relocs
    lea     rdi, [rbp + r14]
    mov     rsi, [rsp + 8]
    call    ds_relocs
.no_relocs:

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
    cmp     byte [rel ds_anysec], 0
    jne     .any_sec
    cmp     rcx, [rel ds_secidx]
    jne     .ret
    jmp     .typed
.any_sec:                                  ; (a linked file's address, named
    test    ecx, ecx                       ; from any section's symbols)
    jz      .ret
    cmp     ecx, 0xFF00
    jae     .ret
.typed:
    movzx   ecx, byte [rsi + SYM64_INFO]
    and     ecx, 0x0F
    cmp     ecx, STT_SECTION
    je      .ret
    cmp     ecx, STT_FILE
    je      .ret
    mov     eax, 1
.ret:
    ret

; ---- ds_sym_before (internal) ----------
;
; Of two symbols at one address, does rsi come before rdi in objdump's
; order (the one it names)? A function first, then not a local, then a
; global (before a weak), then a name not starting with '.', then by name
; (strcmp). Output: eax = 1/0. Clobbers: rcx, rdx, r8, r9.
;
ds_sym_before:
    movzx   ecx, byte [rsi + SYM64_INFO]
    movzx   edx, byte [rdi + SYM64_INFO]
    mov     r8d, ecx
    mov     r9d, edx
    and     r8d, 0x0F                      ; types
    and     r9d, 0x0F
    cmp     r8d, STT_FUNC
    sete    r8b
    cmp     r9d, STT_FUNC
    sete    r9b
    cmp     r8b, r9b
    jne     .by_r8                         ; (a function: first)
    shr     ecx, 4                         ; bindings
    shr     edx, 4
    cmp     ecx, STB_LOCAL
    setne   r8b
    cmp     edx, STB_LOCAL
    setne   r9b
    cmp     r8b, r9b
    jne     .by_r8                         ; (not a local: first)
    cmp     ecx, STB_GLOBAL
    sete    r8b
    cmp     edx, STB_GLOBAL
    sete    r9b
    cmp     r8b, r9b
    jne     .by_r8                         ; (a global: first)
    ; the names
    mov     r8, [rel ds_str]
    test    r8, r8
    jz      .no
    mov     ecx, [rsi + SYM64_NAME]
    mov     edx, [rdi + SYM64_NAME]
    cmp     rcx, [rel ds_strsize]
    jae     .no
    cmp     rdx, [rel ds_strsize]
    jae     .no
    lea     rcx, [r8 + rcx]
    lea     rdx, [r8 + rdx]
    cmp     byte [rcx], '.'
    sete    r8b
    cmp     byte [rdx], '.'
    sete    r9b
    cmp     r8b, r9b
    je      .strcmp
    xor     eax, eax                       ; ('.' last)
    cmp     r8b, 0
    sete    al
    ret
.strcmp:
    mov     al, [rcx]
    cmp     al, [rdx]
    jne     .differ
    test    al, al
    jz      .no                            ; (the same name)
    inc     rcx
    inc     rdx
    jmp     .strcmp
.differ:
    setb    al
    movzx   eax, al
    ret
.by_r8:
    movzx   eax, r8b
    ret
.no:
    xor     eax, eax
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
    push    r15
    mov     r14, rdi
    xor     r15d, r15d                     ; r15 = the symbol objdump names
    mov     r12, [rel ds_syms]
    test    r12, r12
    jz      .none
    xor     r13d, r13d
.loop:
    cmp     r13, [rel ds_nsyms]
    jae     .chosen
    mov     rsi, r12
    call    ds_sym_ok
    test    eax, eax
    jz      .next
    cmp     [r12 + SYM64_VALUE], r14
    jne     .next
    test    r15, r15
    jz      .take
    mov     rsi, r12
    mov     rdi, r15
    call    ds_sym_before
    test    eax, eax
    jz      .next
.take:
    mov     r15, r12
.next:
    add     r12, ELF64_SYM_SIZE
    inc     r13
    jmp     .loop
.chosen:
    test    r15, r15
    jz      .none
    mov     r12, r15
    INS_NL
    movzx   r8d, byte [rel ds_labw]
    INS_HEX r14, r8d
    INS_PUTS " <"
    call    .name
    INS_PUTS ">:"
    INS_NL
    jmp     .ret
.none:
    ; no symbol: the section's first byte gets the first symbol after it
    ; ("<lab-0x5>"), or with none the section's name (objdump's <.text>)
    cmp     r14, [rel ds_secaddr]
    jne     .ret
    INS_NL
    movzx   r8d, byte [rel ds_labw]
    INS_HEX r14, r8d
    cmp     byte [rel ds_raw], 0
    jne     .raw_label
    mov     rdi, r14
    call    ds_annotate                    ; (" <lab-0x5>", " <.text>")
    INS_PUTS ":"
    INS_NL
    jmp     .ret
.raw_label:
    INS_PUTS " <"
    call    ds_put_secname
    INS_PUTS ">:"
    INS_NL
.ret:
    pop     r15
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
    mov     al, [rel ds_linked]            ; (a linked file: its symbols in any
    mov     [rel ds_anysec], al            ; section name the address)
    mov     r14, rdi                       ; r14 = target
    xor     r15d, r15d                     ; r15 = best symbol
    xor     eax, eax
    mov     r12, [rel ds_syms]
    test    r12, r12
    jz      .found
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
    jb      .next
    ja      .take
    mov     rsi, r12                       ; the same address: objdump's choice
    mov     rdi, r15
    call    ds_sym_before
    test    eax, eax
    jz      .next
.take:
    mov     r15, r12
.next:
    add     r12, ELF64_SYM_SIZE
    inc     r13
    jmp     .loop
.found:
    mov     rax, r15                       ; (ds_dry: only whether there is one)
    test    r15, r15
    jz      .section
    cmp     byte [rel ds_dry], 0
    jne     .ret
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
    mov     byte [rel ds_anysec], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
.section:
    ; no symbol at or before it: the first one after it, "<lab-0x2>" -
    ; with none, the section's name, if it is inside (a raw file: none,
    ; objdump writes "0x37")
    cmp     byte [rel ds_raw], 0
    jne     .none
    mov     r12, [rel ds_syms]
    test    r12, r12
    jz      .no_after
    xor     r13d, r13d
.after:
    cmp     r13, [rel ds_nsyms]
    jae     .after_done
    mov     rsi, r12
    call    ds_sym_ok
    test    eax, eax
    jz      .after_next
    test    r15, r15
    jz      .after_take
    mov     rax, [r12 + SYM64_VALUE]
    cmp     rax, [r15 + SYM64_VALUE]
    ja      .after_next
    jb      .after_take
    mov     rsi, r12
    mov     rdi, r15
    call    ds_sym_before
    test    eax, eax
    jz      .after_next
.after_take:
    mov     r15, r12
.after_next:
    add     r12, ELF64_SYM_SIZE
    inc     r13
    jmp     .after
.after_done:
    test    r15, r15
    jz      .no_after
    mov     rax, r15
    cmp     byte [rel ds_dry], 0
    jne     .ret
    INS_PUTS " <"
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, [rel ds_str]
    mov     rdx, [rel ds_strsize]
    mov     ecx, [r15 + SYM64_NAME]
    call    dump_put_strtab
    mov     rax, [r15 + SYM64_VALUE]
    sub     rax, r14
    push    rax
    push    rax
    INS_PUTC '-'
    pop     rax
    pop     rax
    INS_HEX0X rax
    jmp     .close
.no_after:
    mov     rax, r14
    sub     rax, [rel ds_secaddr]
    jb      .none
    cmp     rax, [rel ds_secsize]
    ja      .none
    cmp     byte [rel ds_dry], 0
    jne     .one
    push    rax
    push    rax
    INS_PUTS " <"
    call    ds_put_secname
    pop     rax
    pop     rax
    test    rax, rax
    jz      .close
    push    rax
    push    rax
    INS_PUTC '+'
    pop     rax
    pop     rax
    INS_HEX0X rax
    jmp     .close
.one:
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
    jmp     .ret

; ---- ds_find_rel (internal) -------------
;
; The relocation section (SHT_RELA / SHT_REL) applying to the section
; ds_secidx: ds_rel / ds_relcnt / ds_relent / ds_rela, ds_rel 0 if none.
; Uses rbx = InspCtx.
;
ds_find_rel:
    push    r12
    push    r13
    mov     qword [rel ds_rel], 0
    xor     r12d, r12d
.loop:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .done
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_shdr
    mov     r13, rax
    mov     eax, [r13 + SHDR_INFO]
    cmp     rax, [rel ds_secidx]
    jne     .next
    mov     ecx, ELF64_RELA_SIZE
    mov     byte [rel ds_rela], 1
    cmp     dword [r13 + SHDR_TYPE], SHT_RELA
    je      .typed
    mov     ecx, ELF64_REL_SIZE
    mov     byte [rel ds_rela], 0
    cmp     dword [r13 + SHDR_TYPE], SHT_REL
    jne     .next
.typed:
    cmp     [r13 + SHDR_ENTSIZE], rcx
    jne     .next
    mov     [rel ds_relent], rcx
    mov     rax, [r13 + SHDR_SIZE]
    xor     edx, edx
    div     rcx
    mov     [rel ds_relcnt], rax
    mov     rax, [r13 + SHDR_OFFSET]
    add     rax, [rbx + INSPCTX_buf]
    mov     [rel ds_rel], rax
    jmp     .done
.next:
    inc     r12
    jmp     .loop
.done:
    pop     r13
    pop     r12
    ret

; ---- ds_relocs (internal) ---------------
;
; With -r: a line for each relocation in [rdi, rdi + rsi), as objdump -dr
; writes it - "<tab><tab><tab>6: R_X86_64_PC32<tab>ext_fn-0x4".
;
ds_relocs:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    lea     r13, [rdi + rsi]
    mov     r14, [rel ds_rel]
    test    r14, r14
    jz      .ret
    mov     r15, [rel ds_relcnt]
.loop:
    test    r15, r15
    jz      .ret
    mov     rax, [r14 + RELA_OFFSET]
    cmp     rax, r12
    jb      .next
    cmp     rax, r13
    jae     .next
    INS_PUTS `\t\t\t`
    INS_HEX [r14 + RELA_OFFSET], 0
    INS_PUTS ": "
    mov     eax, [r14 + RELA_INFO]         ; (the type: the low 32 bits)
    mov     rcx, [rbx + INSPCTX_buf]
    cmp     word [rcx + EHDR_MACHINE], EM_386
    je      .r386
    INS_NAME NAME_R_X86_64, rax
    jmp     .typed
.r386:
    INS_NAME NAME_R_386, rax
.typed:
    INS_PUTC 9
    call    .target
    INS_NL
.next:
    add     r14, [rel ds_relent]
    dec     r15
    jmp     .loop
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
.target:                                   ; the symbol (a section's: its name)
    mov     eax, [r14 + RELA_INFO + 4]
    test    eax, eax
    jz      .abs
    cmp     rax, [rel ds_nsyms]
    jae     .abs
    imul    rax, rax, ELF64_SYM_SIZE
    add     rax, [rel ds_syms]
    mov     rsi, rax
    movzx   ecx, byte [rsi + SYM64_INFO]
    and     ecx, 0x0F
    cmp     ecx, STT_SECTION
    jne     .named
    movzx   esi, word [rsi + SYM64_SHNDX]
    mov     rdi, rbx
    call    ins_put_secname
    jmp     .addend
.named:
    mov     ecx, [rsi + SYM64_NAME]
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, [rel ds_str]
    mov     rdx, [rel ds_strsize]
    call    dump_put_strtab
    jmp     .addend
.abs:
    INS_PUTS "*ABS*"
.addend:
    cmp     byte [rel ds_rela], 0
    je      .t_ret
    mov     rax, [r14 + RELA_ADDEND]
    test    rax, rax
    jz      .t_ret
    mov     ecx, '+'
    jns     .sign
    neg     rax
    mov     ecx, '-'
.sign:
    push    rax
    push    rax
    INS_FB
    mov     esi, ecx
    call    fmt_char
    pop     rax
    pop     rax
    INS_HEX0X rax
.t_ret:
    ret

[SECTION .rodata]
s_bad:  db "(bad)", 0
