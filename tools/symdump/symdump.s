;
; ============================================
; File     : tools/symdump/symdump.s
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
; SYMBOL AND RELOCATION DUMPER
; ============================================================================
; Prints every symbol table (SHT_SYMTAB, SHT_DYNSYM) and every relocation
; section (SHT_RELA, SHT_REL) of an ELF image already validated by
; inspect_validate (tools/inspector/inspector.s).
;
; Validation guarantees each section's bytes are inside the image. This
; file still checks everything that is an *index*: entry sizes, sh_link
; targets, symbol numbers and string offsets. Anything inconsistent is
; printed as "<malformed ...>", "<bad symbol N>" or "<corrupt>" instead of
; being followed.
;
; Unnamed STT_SECTION symbols are shown with their section's name, which
; is what makes relocations like "R_X86_64_64  .rodata + 0x10" readable.
; x86-64 relocation types are named; other machines print the raw type.
;
; Calling convention (AMD64):
;   args  : rdi = InspCtx
;   callee saved: rbx, r12-r15, rbp

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

; Stack locals shared by both printers (offsets from rsp after the
; prologue). Every call site leaves these untouched.
%define L_COUNT     0       ; entries in the current section
%define L_ENTSIZE   8       ; expected entry size (24 or 16)
%define L_SYMS      16      ; symbol table data (0 if unusable)
%define L_NSYMS     24      ; number of symbols in it
%define L_STR       32      ; string table for those symbols (0 if none)
%define L_STRSIZE   40      ; its size
%define L_ISRELA    48      ; 1 for SHT_RELA, 0 for SHT_REL
%define L_FOUND     56      ; any matching section seen
%define L_FRAME     64      ; 5 pushes + 64 keeps rsp 16-byte aligned

[SECTION .text]

; ---- symdump_symbols --------------------
;
; symdump_symbols
; Prints every SHT_SYMTAB / SHT_DYNSYM section, or a note if none exist.
; Input    : rdi = InspCtx (validated)
; Output   : none (errors are kept in InspCtx_err)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global symdump_symbols
symdump_symbols:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, L_FRAME
    mov     rbx, rdi
    mov     qword [rsp + L_FOUND], 0

    xor     r12d, r12d                     ; r12 = section index
.section:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .all_done
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_shdr
    mov     r13, rax                       ; r13 = shdr
    mov     eax, [r13 + SHDR_TYPE]
    cmp     eax, SHT_SYMTAB
    je      .is_symtab
    cmp     eax, SHT_DYNSYM
    jne     .next_section
.is_symtab:
    mov     qword [rsp + L_FOUND], 1

    ; count = size / 24
    mov     rax, [r13 + SHDR_SIZE]
    xor     edx, edx
    mov     ecx, ELF64_SYM_SIZE
    div     rcx
    mov     [rsp + L_COUNT], rax
    mov     r14, rdx                       ; r14 = leftover bytes

    INS_PUTS "Symbol table '"
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_put_secname
    INS_PUTS "' contains "
    INS_DEC [rsp + L_COUNT]
    INS_PUTS " entries:"
    INS_NL

    cmp     qword [r13 + SHDR_ENTSIZE], ELF64_SYM_SIZE
    jne     .malformed
    test    r14, r14
    jnz     .malformed

    ; symbol data and its string table (sh_link)
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, rsp                       ; our locals
    call    symdump_load_symtab_strings
    mov     rax, [r13 + SHDR_OFFSET]
    add     rax, [rbx + INSPCTX_buf]
    mov     [rsp + L_SYMS], rax

    INS_PUTS "   Num:"
    INS_PAD 9
    INS_PUTS "Value"
    INS_PAD 28
    INS_PUTS "Size"
    INS_PAD 33
    INS_PUTS "Type"
    INS_PAD 41
    INS_PUTS "Bind"
    INS_PAD 48
    INS_PUTS "Vis"
    INS_PAD 59
    INS_PUTS "Ndx"
    INS_PAD 63
    INS_PUTS "Name"
    INS_NL

    xor     r14d, r14d                     ; r14 = symbol number
.sym:
    cmp     r14, [rsp + L_COUNT]
    jae     .table_done
    imul    r15, r14, ELF64_SYM_SIZE
    add     r15, [rsp + L_SYMS]            ; r15 = Elf64_Sym

    INS_RDEC r14, 6
    INS_PUTC ':'
    INS_PAD 9
    INS_HEX [r15 + SYM64_VALUE], 16
    INS_PAD 26
    INS_RDEC [r15 + SYM64_SIZE], 6
    INS_PAD 33
    movzx   eax, byte [r15 + SYM64_INFO]
    and     eax, 0x0F
    INS_NAME NAME_STTYPE, rax
    INS_PAD 41
    movzx   eax, byte [r15 + SYM64_INFO]
    shr     eax, 4
    INS_NAME NAME_STBIND, rax
    INS_PAD 48
    movzx   eax, byte [r15 + SYM64_OTHER]
    and     eax, 3
    INS_NAME NAME_STVIS, rax
    INS_PAD 58
    mov     rdi, rbx
    movzx   esi, word [r15 + SYM64_SHNDX]
    call    symdump_put_shndx
    INS_PAD 63
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, [rsp + L_STR]
    mov     rcx, [rsp + L_STRSIZE]
    call    symdump_put_symname
    INS_NL

    inc     r14
    jmp     .sym

.malformed:
    INS_PUTS "  <malformed: entry size "
    INS_DEC [r13 + SHDR_ENTSIZE]
    INS_PUTS ", section size "
    INS_DEC [r13 + SHDR_SIZE]
    INS_PUTC '>'
    INS_NL
.table_done:
    INS_NL
.next_section:
    inc     r12
    jmp     .section

.all_done:
    cmp     qword [rsp + L_FOUND], 0
    jne     .ret
    INS_PUTS "There are no symbol tables."
    INS_NL
    INS_NL
.ret:
    add     rsp, L_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- symdump_relocs ---------------------
;
; symdump_relocs
; Prints every SHT_RELA / SHT_REL section, or a note if none exist.
; Input    : rdi = InspCtx (validated)
; Output   : none (errors are kept in InspCtx_err)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global symdump_relocs
symdump_relocs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, L_FRAME
    mov     rbx, rdi
    mov     qword [rsp + L_FOUND], 0

    xor     r12d, r12d
.section:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .all_done
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_shdr
    mov     r13, rax
    mov     eax, [r13 + SHDR_TYPE]
    cmp     eax, SHT_RELA
    je      .rela
    cmp     eax, SHT_REL
    jne     .next_section
    mov     qword [rsp + L_ISRELA], 0
    mov     qword [rsp + L_ENTSIZE], ELF64_REL_SIZE
    jmp     .reloc_section
.rela:
    mov     qword [rsp + L_ISRELA], 1
    mov     qword [rsp + L_ENTSIZE], ELF64_RELA_SIZE
.reloc_section:
    mov     qword [rsp + L_FOUND], 1

    mov     rax, [r13 + SHDR_SIZE]
    xor     edx, edx
    div     qword [rsp + L_ENTSIZE]
    mov     [rsp + L_COUNT], rax
    mov     r14, rdx                       ; leftover bytes

    ; "Relocation section '<name>' at offset 0x.. contains N entries
    ;  (applies to '<target>'):"
    INS_PUTS "Relocation section '"
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_put_secname
    INS_PUTS "' at offset "
    INS_HEX0X [r13 + SHDR_OFFSET]
    INS_PUTS " contains "
    INS_DEC [rsp + L_COUNT]
    INS_PUTS " entries"
    mov     eax, [r13 + SHDR_INFO]
    test    eax, eax
    jz      .no_target
    INS_PUTS " (applies to '"
    mov     rdi, rbx
    mov     esi, [r13 + SHDR_INFO]
    call    ins_put_secname
    INS_PUTS "')"
.no_target:
    INS_PUTC ':'
    INS_NL

    mov     rax, [rsp + L_ENTSIZE]
    cmp     [r13 + SHDR_ENTSIZE], rax
    jne     .malformed
    test    r14, r14
    jnz     .malformed

    ; the symbol table this section refers to (sh_link)
    mov     qword [rsp + L_SYMS], 0
    mov     qword [rsp + L_NSYMS], 0
    mov     qword [rsp + L_STR], 0
    mov     qword [rsp + L_STRSIZE], 0
    mov     rdi, rbx
    mov     esi, [r13 + SHDR_LINK]
    call    ins_shdr
    test    rax, rax
    jz      .have_symtab                   ; unusable: every symbol is "bad"
    mov     r15, rax
    mov     ecx, [r15 + SHDR_TYPE]
    cmp     ecx, SHT_SYMTAB
    je      .link_is_symtab
    cmp     ecx, SHT_DYNSYM
    jne     .have_symtab
.link_is_symtab:
    cmp     qword [r15 + SHDR_ENTSIZE], ELF64_SYM_SIZE
    jne     .have_symtab
    mov     rax, [r15 + SHDR_SIZE]
    xor     edx, edx
    mov     ecx, ELF64_SYM_SIZE
    div     rcx
    mov     [rsp + L_NSYMS], rax
    mov     rax, [r15 + SHDR_OFFSET]
    add     rax, [rbx + INSPCTX_buf]
    mov     [rsp + L_SYMS], rax
    mov     rdi, rbx
    mov     rsi, r15
    mov     rdx, rsp                       ; our locals
    call    symdump_load_symtab_strings
.have_symtab:

    INS_PUTS "  Offset"
    INS_PAD 20
    INS_PUTS "Info"
    INS_PAD 38
    INS_PUTS "Type"
    INS_PAD 63
    cmp     qword [rsp + L_ISRELA], 0
    je      .rel_header
    INS_PUTS "Sym. Name + Addend"
    jmp     .header_done
.rel_header:
    INS_PUTS "Sym. Name"
.header_done:
    INS_NL

    mov     r14, [r13 + SHDR_OFFSET]
    add     r14, [rbx + INSPCTX_buf]       ; r14 = current entry
    mov     r15, [rsp + L_COUNT]           ; r15 = entries left
.entry:
    test    r15, r15
    jz      .table_done

    INS_PUTS "  "
    INS_HEX [r14 + RELA_OFFSET], 16
    INS_PAD 20
    INS_HEX [r14 + RELA_INFO], 16
    INS_PAD 38
    mov     rax, [rbx + INSPCTX_buf]
    cmp     word [rax + EHDR_MACHINE], EM_X86_64
    jne     .raw_type
    mov     eax, [r14 + RELA_INFO]         ; ELF64_R_TYPE = low 32 bits
    INS_NAME NAME_R_X86_64, rax
    jmp     .type_done
.raw_type:
    mov     eax, [r14 + RELA_INFO]
    INS_HEX0X rax
.type_done:
    INS_PAD 63

    mov     rdi, rbx
    mov     rsi, r14
    mov     rdx, rsp                       ; our locals
    call    symdump_put_reloc_target
    INS_NL

    add     r14, [rsp + L_ENTSIZE]
    dec     r15
    jmp     .entry

.malformed:
    INS_PUTS "  <malformed: entry size "
    INS_DEC [r13 + SHDR_ENTSIZE]
    INS_PUTS ", section size "
    INS_DEC [r13 + SHDR_SIZE]
    INS_PUTC '>'
    INS_NL
.table_done:
    INS_NL
.next_section:
    inc     r12
    jmp     .section

.all_done:
    cmp     qword [rsp + L_FOUND], 0
    jne     .ret
    INS_PUTS "There are no relocations."
    INS_NL
    INS_NL
.ret:
    add     rsp, L_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; Internal helpers
; ============================================================================

; ---- symdump_load_symtab_strings --------
;
; Stores the string table of a symbol table section (its sh_link) into
; the caller's L_STR / L_STRSIZE locals, or 0/0 when the link is out of
; range or points at a NOBITS section.
; Input : rdi = InspCtx, rsi = symbol table shdr, rdx = caller's locals
;
symdump_load_symtab_strings:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx                       ; r13 = caller locals
    mov     qword [r13 + L_STR], 0
    mov     qword [r13 + L_STRSIZE], 0
    mov     esi, [r12 + SHDR_LINK]
    call    ins_shdr
    test    rax, rax
    jz      .done
    cmp     dword [rax + SHDR_TYPE], SHT_NOBITS
    je      .done
    mov     rcx, [rax + SHDR_OFFSET]
    add     rcx, [rbx + INSPCTX_buf]
    mov     [r13 + L_STR], rcx
    mov     rcx, [rax + SHDR_SIZE]
    mov     [r13 + L_STRSIZE], rcx
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- symdump_put_shndx ------------------
;
; Appends st_shndx right-aligned in 4 columns: UND, ABS, COM or a number.
; Input : rdi = InspCtx, rsi = st_shndx
;
symdump_put_shndx:
    push    rbx
    mov     rbx, rdi
    test    esi, esi
    jz      .und
    cmp     esi, SHN_ABS
    je      .abs
    cmp     esi, SHN_COMMON
    je      .com
    INS_RDEC rsi, 4
    pop     rbx
    ret
.und:
    INS_PUTS " UND"
    pop     rbx
    ret
.abs:
    INS_PUTS " ABS"
    pop     rbx
    ret
.com:
    INS_PUTS " COM"
    pop     rbx
    ret

; ---- symdump_put_symname ----------------
;
; Appends a symbol's name. An unnamed STT_SECTION symbol is shown with the
; name of the section it stands for.
; Input : rdi = InspCtx, rsi = Elf64_Sym, rdx = strtab, rcx = strtab size
;
symdump_put_symname:
    push    rbx
    mov     rbx, rdi
    mov     r8d, [rsi + SYM64_NAME]
    test    r8d, r8d
    jnz     .by_name
    movzx   eax, byte [rsi + SYM64_INFO]
    and     eax, 0x0F
    cmp     eax, STT_SECTION
    jne     .by_name
    movzx   esi, word [rsi + SYM64_SHNDX]
    cmp     rsi, [rbx + INSPCTX_shnum]
    jae     .by_name                       ; not a real section: leave blank
    mov     rdi, rbx
    call    ins_put_secname
    pop     rbx
    ret
.by_name:
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, rdx
    mov     rdx, rcx
    mov     rcx, r8
    call    dump_put_strtab
    pop     rbx
    ret

; ---- symdump_put_reloc_target -----------
;
; Appends "symbol + 0xaddend" (RELA), "symbol" (REL), or just the signed
; addend when the relocation has no symbol (index 0).
; Input : rdi = InspCtx, rsi = relocation entry,
;         rdx = pointer to the caller's locals block
;
symdump_put_reloc_target:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi                       ; r12 = entry
    mov     r13, rdx                       ; r13 = caller locals

    mov     r14, [r12 + RELA_INFO]
    shr     r14, 32                        ; r14 = ELF64_R_SYM
    test    r14, r14
    jz      .no_symbol

    cmp     r14, [r13 + L_NSYMS]
    jb      .sym_ok
    INS_PUTS "<bad symbol "
    INS_DEC r14
    INS_PUTC '>'
    jmp     .addend
.sym_ok:
    imul    rsi, r14, ELF64_SYM_SIZE
    add     rsi, [r13 + L_SYMS]
    mov     rdi, rbx
    mov     rdx, [r13 + L_STR]
    mov     rcx, [r13 + L_STRSIZE]
    call    symdump_put_symname

.addend:
    cmp     qword [r13 + L_ISRELA], 0
    je      .done
    mov     r14, [r12 + RELA_ADDEND]
    test    r14, r14
    js      .minus
    INS_PUTS " + "
    INS_HEX0X r14
    jmp     .done
.minus:
    INS_PUTS " - "
    neg     r14
    INS_HEX0X r14
    jmp     .done

.no_symbol:
    cmp     qword [r13 + L_ISRELA], 0
    je      .done
    mov     r14, [r12 + RELA_ADDEND]
    test    r14, r14
    jns     .plain
    INS_PUTC '-'
    neg     r14
.plain:
    INS_HEX0X r14

.done:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
