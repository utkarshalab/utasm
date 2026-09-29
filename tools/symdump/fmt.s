;
; ============================================
; File     : tools/symdump/fmt.s
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
; DUMP FORMATTING HELPERS
; ============================================================================
; Column layout and symbolic names for the ELF inspector and symbol dumper.
; Everything here writes into a FmtBuf (lib/fmt.s), so output is always
; bounded by the caller's line buffer.
;
;   dump_pad_to      pad a line to a column (at least one space)
;   dump_udec_right  right-aligned unsigned decimal
;   dump_put_hex0x   "0x" + minimal hex
;   dump_name        value -> name string for a NAME_* table (or 0)
;   dump_put_name    name, or "0x<hex>" when the value is not in the table
;   dump_put_strtab  bounds-checked read of a name from an ELF string table
;
; Name tables use fixed 32-byte entries (u32 value + NUL-terminated name,
; padded to the next 32-byte boundary; names must stay under 28 bytes)
; and are located with RIP-relative lea in dump_name, so no label
; arithmetic appears in the data.
;
; Calling convention (AMD64):
;   args  : rdi = FmtBuf (except dump_name), then rsi, rdx, rcx
;   return: as lib/fmt.s - rax = EXIT_OK or EXIT_ERROR (truncated)
;   callee saved: rbx, r12-r15, rbp

%define NAMEENT_SIZE    32

extern fmt_str
extern fmt_char
extern fmt_pad
extern fmt_hex
extern fmt_udec
extern fmt_mem

[SECTION .text]

; ---- dump_pad_to ------------------------
;
; dump_pad_to
; Pads the line with spaces up to a column. If the line already reaches
; that column, a single space is added so fields never run together.
; Input    : rdi = pointer to FmtBuf
;             rsi = target column (0-based)
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r10
;
global dump_pad_to
dump_pad_to:
    mov     rdx, rsi
    sub     rdx, [rdi + FMTBUF_len]        ; spaces needed
    jbe     .one_space                     ; already at / past the column
    mov     esi, ' '
    jmp     fmt_pad
.one_space:
    mov     esi, ' '
    jmp     fmt_char

; ---- dump_udec_right --------------------
;
; dump_udec_right
; Unsigned decimal, right-aligned in a field of the given width.
; Wider numbers are printed in full.
; Input    : rdi = pointer to FmtBuf
;             rsi = value
;             rdx = field width
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r10
;
global dump_udec_right
dump_udec_right:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    ; count decimal digits
    mov     rax, rsi
    mov     r8d, 10
    xor     ecx, ecx
    mov     r13, rdx                       ; r13 = width
.count:
    xor     edx, edx
    div     r8
    inc     rcx
    test    rax, rax
    jnz     .count

    cmp     r13, rcx
    jbe     .digits
    mov     rdx, r13
    sub     rdx, rcx
    mov     rdi, rbx
    mov     esi, ' '
    call    fmt_pad

.digits:
    mov     rdi, rbx
    mov     rsi, r12
    call    fmt_udec
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- dump_put_hex0x ---------------------
;
; dump_put_hex0x
; Appends "0x" followed by the minimal lowercase hex form of a value.
; Input    : rdi = pointer to FmtBuf
;             rsi = value
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r10
;
global dump_put_hex0x
dump_put_hex0x:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    lea     rsi, [rel str_0x]
    call    fmt_str
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, 1
    call    fmt_hex
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; ---- dump_name --------------------------
;
; dump_name
; Looks up the symbolic name of a value in one of the NAME_* tables.
; Input    : rdi = table kind (NAME_ETYPE .. NAME_R_X86_64)
;             rsi = value
; Output   : rax = pointer to NUL-terminated name, or 0 if unknown
; Clobbers : rcx, rdx, r8
;
global dump_name
dump_name:
    xor     eax, eax
    cmp     rdi, NAME_KIND_COUNT
    jae     .done
    mov     rcx, 0xFFFFFFFF
    cmp     rsi, rcx
    ja      .done                          ; tables hold 32-bit values

    ; rcx = table start, rdx = table end for this kind. Located with
    ; RIP-relative lea (relocated by the linker) rather than an index of
    ; label differences in data: utasm's own assembler evaluates forward
    ; label differences in data (dd end - start) as 0, which made every
    ; table look empty in a self-built utasm.
    lea     rcx, [rel tab_etype]
    lea     rdx, [rel tab_etype_end]
    cmp     edi, NAME_ETYPE
    je      .scan
    lea     rcx, [rel tab_machine]
    lea     rdx, [rel tab_machine_end]
    cmp     edi, NAME_MACHINE
    je      .scan
    lea     rcx, [rel tab_osabi]
    lea     rdx, [rel tab_osabi_end]
    cmp     edi, NAME_OSABI
    je      .scan
    lea     rcx, [rel tab_shtype]
    lea     rdx, [rel tab_shtype_end]
    cmp     edi, NAME_SHTYPE
    je      .scan
    lea     rcx, [rel tab_ptype]
    lea     rdx, [rel tab_ptype_end]
    cmp     edi, NAME_PTYPE
    je      .scan
    lea     rcx, [rel tab_sttype]
    lea     rdx, [rel tab_sttype_end]
    cmp     edi, NAME_STTYPE
    je      .scan
    lea     rcx, [rel tab_stbind]
    lea     rdx, [rel tab_stbind_end]
    cmp     edi, NAME_STBIND
    je      .scan
    lea     rcx, [rel tab_stvis]
    lea     rdx, [rel tab_stvis_end]
    cmp     edi, NAME_STVIS
    je      .scan
    lea     rcx, [rel tab_rx86]            ; NAME_R_X86_64 (range-checked above)
    lea     rdx, [rel tab_rx86_end]

.scan:
    cmp     rcx, rdx
    jae     .done
    cmp     [rcx], esi
    je      .found
    add     rcx, NAMEENT_SIZE
    jmp     .scan
.found:
    lea     rax, [rcx + 4]
.done:
    ret

; ---- dump_put_name ----------------------
;
; dump_put_name
; Appends a value's symbolic name, or "0x<hex>" if it has none.
; Input    : rdi = pointer to FmtBuf
;             rsi = table kind (NAME_*)
;             rdx = value
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r10
;
global dump_put_name
dump_put_name:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rdx

    mov     rdi, rsi
    mov     rsi, rdx
    call    dump_name
    mov     rdi, rbx
    test    rax, rax
    jz      .numeric
    mov     rsi, rax
    call    fmt_str
    jmp     .done
.numeric:
    mov     rsi, r12
    call    dump_put_hex0x
.done:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; ---- dump_put_strtab --------------------
;
; dump_put_strtab
; Appends the string at an offset in an ELF string table, never reading
; past the table: the name ends at the first NUL or at the table's end.
;   - offset past the end                  -> "<corrupt>"
;   - no table (ptr 0 or size 0), offset 0 -> nothing (unnamed)
;   - no table, offset != 0                -> "<corrupt>"
; Input    : rdi = pointer to FmtBuf
;             rsi = string table data
;             rdx = string table size
;             rcx = offset of the name
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r10
;
global dump_put_strtab
dump_put_strtab:
    test    rsi, rsi
    jz      .no_table
    test    rdx, rdx
    jz      .no_table
    cmp     rcx, rdx
    jae     .corrupt

    lea     r8, [rsi + rcx]                ; r8 = start of name
    sub     rdx, rcx                       ; rdx = bytes available
    xor     r9d, r9d                       ; r9 = name length
.scan:
    cmp     r9, rdx
    jae     .emit                          ; unterminated: stop at table end
    cmp     byte [r8 + r9], 0
    je      .emit
    inc     r9
    jmp     .scan
.emit:
    mov     rsi, r8
    mov     rdx, r9
    jmp     fmt_mem

.no_table:
    xor     eax, eax
    test    rcx, rcx
    jz      .done                          ; unnamed
.corrupt:
    lea     rsi, [rel str_corrupt]
    jmp     fmt_str
.done:
    ret

; ============================================================================
; Name tables
; ============================================================================

; One 32-byte entry: value, NUL-terminated name, padding to the next
; entry. Tables start on a NAMEENT_SIZE boundary, so `align` pads each
; entry to exactly NAMEENT_SIZE bytes as long as the name is < 28 bytes.
; (Plain directives only, so utasm's own macro engine can assemble it.)
%macro NAMEENT 2
    dd      %1
    db      %2, 0
    align   NAMEENT_SIZE
%endmacro

[SECTION .rodata]
align NAMEENT_SIZE
tab_etype:
    NAMEENT ET_NONE,        "NONE (No file type)"
    NAMEENT ET_REL,         "REL (Relocatable file)"
    NAMEENT ET_EXEC,        "EXEC (Executable file)"
    NAMEENT ET_DYN,         "DYN (Shared object file)"
    NAMEENT ET_CORE,        "CORE (Core file)"
tab_etype_end:

tab_machine:
    NAMEENT EM_NONE,        "None"
    NAMEENT EM_386,         "Intel 80386"
    NAMEENT EM_MIPS,        "MIPS"
    NAMEENT EM_PPC,         "PowerPC"
    NAMEENT EM_PPC64,       "PowerPC64"
    NAMEENT EM_ARM,         "ARM"
    NAMEENT EM_X86_64,      "x86-64"
    NAMEENT EM_AARCH64,     "AArch64"
    NAMEENT EM_RISCV,       "RISC-V"
tab_machine_end:

tab_osabi:
    NAMEENT ELFOSABI_NONE,       "UNIX - System V"
    NAMEENT ELFOSABI_LINUX,      "UNIX - Linux"
    NAMEENT ELFOSABI_FREEBSD,    "UNIX - FreeBSD"
    NAMEENT ELFOSABI_STANDALONE, "Standalone"
tab_osabi_end:

tab_shtype:
    NAMEENT SHT_NULL,           "NULL"
    NAMEENT SHT_PROGBITS,       "PROGBITS"
    NAMEENT SHT_SYMTAB,         "SYMTAB"
    NAMEENT SHT_STRTAB,         "STRTAB"
    NAMEENT SHT_RELA,           "RELA"
    NAMEENT SHT_HASH,           "HASH"
    NAMEENT SHT_DYNAMIC,        "DYNAMIC"
    NAMEENT SHT_NOTE,           "NOTE"
    NAMEENT SHT_NOBITS,         "NOBITS"
    NAMEENT SHT_REL,            "REL"
    NAMEENT SHT_SHLIB,          "SHLIB"
    NAMEENT SHT_DYNSYM,         "DYNSYM"
    NAMEENT SHT_INIT_ARRAY,     "INIT_ARRAY"
    NAMEENT SHT_FINI_ARRAY,     "FINI_ARRAY"
    NAMEENT SHT_PREINIT_ARRAY,  "PREINIT_ARRAY"
    NAMEENT SHT_GROUP,          "GROUP"
    NAMEENT SHT_SYMTAB_SHNDX,   "SYMTAB_SHNDX"
    NAMEENT SHT_RELR,           "RELR"
    NAMEENT SHT_GNU_HASH,       "GNU_HASH"
    NAMEENT SHT_GNU_VERNEED,    "VERNEED"
    NAMEENT SHT_GNU_VERSYM,     "VERSYM"
    NAMEENT SHT_X86_64_UNWIND,  "X86_64_UNWIND"
tab_shtype_end:

tab_ptype:
    NAMEENT PT_NULL,            "NULL"
    NAMEENT PT_LOAD,            "LOAD"
    NAMEENT PT_DYNAMIC,         "DYNAMIC"
    NAMEENT PT_INTERP,          "INTERP"
    NAMEENT PT_NOTE,            "NOTE"
    NAMEENT PT_SHLIB,           "SHLIB"
    NAMEENT PT_PHDR,            "PHDR"
    NAMEENT PT_TLS,             "TLS"
    NAMEENT PT_GNU_EH_FRAME,    "GNU_EH_FRAME"
    NAMEENT PT_GNU_STACK,       "GNU_STACK"
    NAMEENT PT_GNU_RELRO,       "GNU_RELRO"
    NAMEENT PT_GNU_PROPERTY,    "GNU_PROPERTY"
tab_ptype_end:

tab_sttype:
    NAMEENT STT_NOTYPE,         "NOTYPE"
    NAMEENT STT_OBJECT,         "OBJECT"
    NAMEENT STT_FUNC,           "FUNC"
    NAMEENT STT_SECTION,        "SECTION"
    NAMEENT STT_FILE,           "FILE"
    NAMEENT STT_COMMON,         "COMMON"
    NAMEENT STT_TLS,            "TLS"
    NAMEENT STT_GNU_IFUNC,      "IFUNC"
tab_sttype_end:

tab_stbind:
    NAMEENT STB_LOCAL,          "LOCAL"
    NAMEENT STB_GLOBAL,         "GLOBAL"
    NAMEENT STB_WEAK,           "WEAK"
    NAMEENT STB_GNU_UNIQUE,     "UNIQUE"
tab_stbind_end:

tab_stvis:
    NAMEENT STV_DEFAULT,        "DEFAULT"
    NAMEENT STV_INTERNAL,       "INTERNAL"
    NAMEENT STV_HIDDEN,         "HIDDEN"
    NAMEENT STV_PROTECTED,      "PROTECTED"
tab_stvis_end:

tab_rx86:
    NAMEENT R_X86_64_NONE,      "R_X86_64_NONE"
    NAMEENT R_X86_64_64,        "R_X86_64_64"
    NAMEENT R_X86_64_PC32,      "R_X86_64_PC32"
    NAMEENT R_X86_64_GOT32,     "R_X86_64_GOT32"
    NAMEENT R_X86_64_PLT32,     "R_X86_64_PLT32"
    NAMEENT R_X86_64_COPY,      "R_X86_64_COPY"
    NAMEENT R_X86_64_GLOB_DAT,  "R_X86_64_GLOB_DAT"
    NAMEENT R_X86_64_JUMP_SLOT, "R_X86_64_JUMP_SLOT"
    NAMEENT R_X86_64_RELATIVE,  "R_X86_64_RELATIVE"
    NAMEENT R_X86_64_GOTPCREL,  "R_X86_64_GOTPCREL"
    NAMEENT R_X86_64_32,        "R_X86_64_32"
    NAMEENT R_X86_64_32S,       "R_X86_64_32S"
    NAMEENT R_X86_64_16,        "R_X86_64_16"
    NAMEENT R_X86_64_PC16,      "R_X86_64_PC16"
    NAMEENT R_X86_64_8,         "R_X86_64_8"
    NAMEENT R_X86_64_PC8,       "R_X86_64_PC8"
    NAMEENT R_X86_64_DTPMOD64,  "R_X86_64_DTPMOD64"
    NAMEENT R_X86_64_DTPOFF64,  "R_X86_64_DTPOFF64"
    NAMEENT R_X86_64_TPOFF64,   "R_X86_64_TPOFF64"
    NAMEENT R_X86_64_TLSGD,     "R_X86_64_TLSGD"
    NAMEENT R_X86_64_TLSLD,     "R_X86_64_TLSLD"
    NAMEENT R_X86_64_DTPOFF32,  "R_X86_64_DTPOFF32"
    NAMEENT R_X86_64_GOTTPOFF,  "R_X86_64_GOTTPOFF"
    NAMEENT R_X86_64_TPOFF32,   "R_X86_64_TPOFF32"
    NAMEENT R_X86_64_PC64,      "R_X86_64_PC64"
    NAMEENT R_X86_64_GOTOFF64,  "R_X86_64_GOTOFF64"
    NAMEENT R_X86_64_GOTPC32,   "R_X86_64_GOTPC32"
    NAMEENT R_X86_64_GOT64,     "R_X86_64_GOT64"
    NAMEENT R_X86_64_GOTPCREL64, "R_X86_64_GOTPCREL64"
    NAMEENT R_X86_64_GOTPC64,   "R_X86_64_GOTPC64"
    NAMEENT R_X86_64_GOTPLT64,  "R_X86_64_GOTPLT64"
    NAMEENT R_X86_64_PLTOFF64,  "R_X86_64_PLTOFF64"
    NAMEENT R_X86_64_SIZE32,    "R_X86_64_SIZE32"
    NAMEENT R_X86_64_SIZE64,    "R_X86_64_SIZE64"
    NAMEENT R_X86_64_GOTPC32_TLSDESC, "R_X86_64_GOTPC32_TLSDESC"
    NAMEENT R_X86_64_TLSDESC_CALL, "R_X86_64_TLSDESC_CALL"
tab_rx86_end:

str_0x:      db "0x", 0
str_corrupt: db "<corrupt>", 0
