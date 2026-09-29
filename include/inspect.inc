%ifndef INSPECT_INC
%define INSPECT_INC

;
; ============================================
; File     : include/inspect.inc
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Shared definitions for the ELF inspector
;              (tools/inspector) and symbol dumper (tools/symdump).
; ============================================
;

%include "include/type.inc"

; ============================================================================
; What to print  (inspect_run flags, may be OR-ed)
; ============================================================================

%define INSPECT_HEADER      0x01    ; ELF file header
%define INSPECT_SECTIONS    0x02    ; section header table
%define INSPECT_SEGMENTS    0x04    ; program header table
%define INSPECT_SYMBOLS     0x08    ; every SHT_SYMTAB / SHT_DYNSYM
%define INSPECT_RELOCS      0x10    ; every SHT_RELA / SHT_REL
%define INSPECT_ALL         0x1F
%define INSPECT_DISASM      0x20    ; x86-64 disassembly of code sections (not in ALL)

; ============================================================================
; Name tables  (dump_name / dump_put_name kinds, see tools/symdump/fmt.s)
; ============================================================================

%define NAME_ETYPE          0       ; e_type
%define NAME_MACHINE        1       ; e_machine
%define NAME_OSABI          2       ; e_ident[EI_OSABI]
%define NAME_SHTYPE         3       ; sh_type
%define NAME_PTYPE          4       ; p_type
%define NAME_STTYPE         5       ; ELF64_ST_TYPE(st_info)
%define NAME_STBIND         6       ; ELF64_ST_BIND(st_info)
%define NAME_STVIS          7       ; ELF64_ST_VISIBILITY(st_other)
%define NAME_R_X86_64       8       ; x86-64 relocation types
%define NAME_KIND_COUNT     9

; Output line buffer. Longer lines are cut off (never overflowed).
%define INSPECT_LINE_MAX    512

; ============================================================================
; STRUCT: InspCtx  - one inspection run (lives on inspect_run's stack)
; ============================================================================
; The file is validated once up front, so every section, header table and
; string table referenced through this context is known to lie inside
; [buf, buf + len). Printers only need to bounds-check *indices* (symbol
; numbers, sh_link values, string offsets), never file offsets.

struc INSPCTX
    field buf,        8     ; start of the ELF image
    field len,        8     ; image size in bytes
    field shdrs,      8     ; section header table (0 if none)
    field shnum,      8     ; effective section count (SHN_XINDEX resolved)
    field shstrndx,   8     ; effective string table index
    field shstr,      8     ; section-name string table data (0 if none)
    field shstr_size, 8     ; its size
    field sink,       8     ; line callback: sink(ptr, len, sink_ctx) -> rax
    field sink_ctx,   8     ; opaque value for the sink
    field err,        8     ; first sink error (sticky); 0 = OK
    field fb,         FMTBUF_SIZE
    field line,       INSPECT_LINE_MAX
endstruc

; ============================================================================
; Line-building shorthands. All assume rbx = InspCtx*.
; They clobber caller-saved registers (rax, rcx, rdx, rsi, rdi, r8-r11),
; so keep live values in rbx / r12-r15 / stack slots.
; Operands must not reference rdi, rsi or rdx (those are set first).
; ============================================================================

%macro INS_FB 0
    lea     rdi, [rbx + INSPCTX_fb]
%endmacro

; INS_PUTS "literal"
%macro INS_PUTS 1
[SECTION .rodata]
%%str: db %1, 0
[SECTION .text]
    INS_FB
    lea     rsi, [rel %%str]
    call    fmt_str
%endmacro

; INS_PUTSTR reg_or_mem   (pointer to a NUL-terminated string)
%macro INS_PUTSTR 1
    mov     rax, %1
    INS_FB
    mov     rsi, rax
    call    fmt_str
%endmacro

; INS_PUTC 'c'
%macro INS_PUTC 1
    INS_FB
    mov     esi, %1
    call    fmt_char
%endmacro

; INS_PAD column   (pad with spaces to a column; at least one space)
%macro INS_PAD 1
    INS_FB
    mov     esi, %1
    call    dump_pad_to
%endmacro

; INS_HEX value, min_digits
%macro INS_HEX 2
    mov     rax, %1
    INS_FB
    mov     rsi, rax
    mov     edx, %2
    call    fmt_hex
%endmacro

; INS_HEX0X value     ("0x" + minimal hex)
%macro INS_HEX0X 1
    mov     rax, %1
    INS_FB
    mov     rsi, rax
    call    dump_put_hex0x
%endmacro

; INS_DEC value       (unsigned decimal)
%macro INS_DEC 1
    mov     rax, %1
    INS_FB
    mov     rsi, rax
    call    fmt_udec
%endmacro

; INS_RDEC value, width   (unsigned decimal, right-aligned)
%macro INS_RDEC 2
    mov     rax, %1
    INS_FB
    mov     rsi, rax
    mov     edx, %2
    call    dump_udec_right
%endmacro

; INS_NAME kind, value    (symbolic name, or 0x<hex> when unknown)
%macro INS_NAME 2
    mov     rax, %2
    INS_FB
    mov     esi, %1
    mov     rdx, rax
    call    dump_put_name
%endmacro

; INS_NL                  (finish the line and hand it to the sink)
%macro INS_NL 0
    mov     rdi, rbx
    call    ins_flush_line
%endmacro

%endif
