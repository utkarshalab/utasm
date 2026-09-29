;
; ============================================
; File     : tools/inspector/inspector.s
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
; ELF INSPECTOR
; ============================================================================
; A built-in, readelf-style viewer for ELF64 little-endian files, so utasm
; can check its own output without external tools:
;
;     inspect_file("hello.o", INSPECT_ALL)     ; CLI entry point
;     inspect_run(buf, len, flags, sink, ctx)  ; in-memory entry point
;
; The image is validated once before anything is printed: the ELF header,
; the section and program header tables, and every section's file range
; must lie inside the buffer. After that, printers only bounds-check
; indices (symbol numbers, sh_link, string offsets). A malformed file
; yields EXIT_INVALID_FORMAT, never an out-of-bounds read.
;
; Output goes one line at a time to a sink callback,
;     sink(rdi = line ptr, rsi = length incl. '\n', rdx = sink_ctx) -> rax
; so the same code can write to stdout (inspect_sink_fd) or be captured in
; tests. The first non-zero sink result stops further output and becomes
; inspect_run's return value.
;
; Symbols and relocations are printed by tools/symdump/symdump.s, which
; shares the InspCtx and the ins_* helpers defined here.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8
;   return: rax = EXIT_OK or error code
;   callee saved: rbx, r12-r15, rbp

; Entries in shflag_table below. A plain constant rather than
; ($ - shflag_table) / 2: utasm cannot use that forward-computed value in
; `cmp r13, SHFLAG_COUNT` before the table has been seen.
%define SHFLAG_COUNT    11

; InspCtx lives on inspect_run's stack; round its size up to 16.
%define INSPCTX_FRAME   ((INSPCTX_SIZE + 15) & ~15)

extern fmt_init
extern fmt_reset
extern fmt_str
extern fmt_char
extern fmt_pad
extern fmt_hex
extern fmt_udec
extern fmt_mem
extern dump_pad_to
extern dump_udec_right
extern dump_put_hex0x
extern dump_put_name
extern dump_put_strtab
extern symdump_symbols
extern symdump_relocs
extern io_open
extern io_close
extern io_file_size
extern io_mmap
extern io_munmap

[SECTION .text]

; ============================================================================
; Entry points
; ============================================================================

; ---- inspect_run ------------------------
;
; inspect_run
; Validates an in-memory ELF image and prints the requested parts.
; Input    : rdi = pointer to the image
;             rsi = image size in bytes
;             rdx = INSPECT_* flags
;             rcx = sink function
;             r8  = sink context
; Output   : rax = EXIT_OK, EXIT_INVALID_FORMAT, or the sink's error
; Clobbers : rcx, rdx, rsi, rdi, r8-r11 (plus sink clobbers)
;
global inspect_run
inspect_run:
    push    rbx
    push    r12
    push    r13
    sub     rsp, INSPCTX_FRAME
    mov     rbx, rsp                       ; rbx = InspCtx
    mov     r12, rdx                       ; r12 = flags

    mov     [rbx + INSPCTX_buf], rdi
    mov     [rbx + INSPCTX_len], rsi
    mov     [rbx + INSPCTX_sink], rcx
    mov     [rbx + INSPCTX_sink_ctx], r8
    xor     eax, eax
    mov     [rbx + INSPCTX_shdrs], rax
    mov     [rbx + INSPCTX_shnum], rax
    mov     [rbx + INSPCTX_shstrndx], rax
    mov     [rbx + INSPCTX_shstr], rax
    mov     [rbx + INSPCTX_shstr_size], rax
    mov     [rbx + INSPCTX_err], rax

    ; line buffer: keep one byte spare so ins_flush_line can always add '\n'
    lea     rdi, [rbx + INSPCTX_fb]
    lea     rsi, [rbx + INSPCTX_line]
    mov     edx, INSPECT_LINE_MAX - 1
    call    fmt_init

    mov     rdi, rbx
    call    inspect_validate
    test    rax, rax
    jnz     .done

    test    r12, INSPECT_HEADER
    jz      .no_header
    mov     rdi, rbx
    call    ins_print_header
.no_header:
    test    r12, INSPECT_SECTIONS
    jz      .no_sections
    mov     rdi, rbx
    call    ins_print_sections
.no_sections:
    test    r12, INSPECT_SEGMENTS
    jz      .no_segments
    mov     rdi, rbx
    call    ins_print_segments
.no_segments:
    test    r12, INSPECT_SYMBOLS
    jz      .no_symbols
    mov     rdi, rbx
    call    symdump_symbols
.no_symbols:
    test    r12, INSPECT_RELOCS
    jz      .no_relocs
    mov     rdi, rbx
    call    symdump_relocs
.no_relocs:
    mov     rax, [rbx + INSPCTX_err]

.done:
    add     rsp, INSPCTX_FRAME
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- inspect_file -----------------------
;
; inspect_file
; Maps a file read-only and inspects it, printing to stdout.
; Input    : rdi = path (NUL-terminated)
;             rsi = INSPECT_* flags
; Output   : rax = EXIT_OK, EXIT_FILE_NOT_FOUND, EXIT_FILE_PERM,
;              EXIT_INVALID_FORMAT (including empty files), EXIT_OOM
;              (mmap failed) or EXIT_FILE_WRITE (stdout failed)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global inspect_file
inspect_file:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi                       ; r12 = flags

    mov     esi, AMD64_O_RDONLY
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     rbx, rdx                       ; rbx = fd

    mov     rdi, rbx
    call    io_file_size
    test    rax, rax
    jnz     .close_ret
    mov     r13, rdx                       ; r13 = size
    mov     eax, EXIT_INVALID_FORMAT
    test    r13, r13
    jz      .close_ret                     ; mmap of 0 bytes would fail

    xor     edi, edi
    mov     rsi, r13
    mov     edx, PROT_READ
    mov     ecx, MAP_PRIVATE
    mov     r8, rbx
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .close_ret
    mov     r14, rdx                       ; r14 = mapping

    mov     rdi, rbx
    call    io_close                       ; the mapping outlives the fd

    mov     rdi, r14
    mov     rsi, r13
    mov     rdx, r12
    lea     rcx, [rel inspect_sink_fd]
    mov     r8d, 1                         ; stdout
    call    inspect_run
    mov     r15, rax

    mov     rdi, r14
    mov     rsi, r13
    call    io_munmap
    mov     rax, r15
    jmp     .ret

.close_ret:
    mov     r15, rax
    mov     rdi, rbx
    call    io_close
    mov     rax, r15
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- inspect_sink_fd --------------------
;
; inspect_sink_fd
; Line sink that writes to a file descriptor, retrying partial writes
; and EINTR.
; Input    : rdi = line, rsi = length, rdx = fd
; Output   : rax = EXIT_OK or EXIT_FILE_WRITE
; Clobbers : rcx, rdx, rsi, rdi, r8, r9, r11
;
global inspect_sink_fd
inspect_sink_fd:
    mov     r8, rdi                        ; cursor
    mov     r9, rsi                        ; remaining
    mov     rdi, rdx                       ; fd
.loop:
    test    r9, r9
    jz      .ok
    mov     eax, AMD64_SYS_WRITE
    mov     rsi, r8
    mov     rdx, r9
    syscall
    cmp     rax, -4                        ; -EINTR
    je      .loop
    test    rax, rax
    jle     .fail
    add     r8, rax
    sub     r9, rax
    jmp     .loop
.ok:
    xor     eax, eax
    ret
.fail:
    mov     eax, EXIT_FILE_WRITE
    ret

; ============================================================================
; Validation
; ============================================================================

; ---- inspect_validate -------------------
;
; inspect_validate
; Checks that the image is a well-formed ELF64 little-endian file whose
; tables all lie inside the buffer, and fills in the derived InspCtx
; fields (shdrs, shnum, shstrndx, shstr, shstr_size).
;   - e_shnum == 0 with a section table: the count is in shdr[0].sh_size
;   - e_shstrndx == SHN_XINDEX: the index is in shdr[0].sh_link
;   - an out-of-range string table index is tolerated (names print as
;     "<corrupt>"); everything that would be read out of bounds is not
; Input    : rdi = InspCtx with buf and len set
; Output   : rax = EXIT_OK or EXIT_INVALID_FORMAT
; Clobbers : rcx, rdx, rsi, r8-r11
;
global inspect_validate
inspect_validate:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, [rbx + INSPCTX_buf]
    mov     r13, [rbx + INSPCTX_len]

    ; ---- identification ----
    test    r12, r12
    jz      .bad
    cmp     r13, ELF64_EHDR_SIZE
    jb      .bad
    cmp     dword [r12], ELFMAG
    jne     .bad
    cmp     byte [r12 + EI_CLASS], ELFCLASS64
    jne     .bad
    cmp     byte [r12 + EI_DATA], ELFDATA2LSB
    jne     .bad
    cmp     byte [r12 + EI_VERSION], EV_CURRENT
    jne     .bad

    ; ---- program header table ----
    movzx   ecx, word [r12 + EHDR_PHNUM]
    test    ecx, ecx
    jz      .phdrs_ok
    cmp     word [r12 + EHDR_PHENTSIZE], ELF64_PHDR_SIZE
    jne     .bad
    mov     rax, [r12 + EHDR_PHOFF]
    cmp     rax, r13
    ja      .bad
    mov     rdx, r13
    sub     rdx, rax                       ; bytes after phoff
    imul    rcx, rcx, ELF64_PHDR_SIZE      ; <= 65535*56, cannot overflow
    cmp     rcx, rdx
    ja      .bad
.phdrs_ok:

    ; ---- section header table ----
    mov     rax, [r12 + EHDR_SHOFF]
    test    rax, rax
    jnz     .have_shdrs
    cmp     word [r12 + EHDR_SHNUM], 0
    jne     .bad                           ; sections claimed, no table
    jmp     .ok                            ; no sections at all

.have_shdrs:
    cmp     word [r12 + EHDR_SHENTSIZE], ELF64_SHDR_SIZE
    jne     .bad
    mov     rdx, r13
    sub     rdx, ELF64_SHDR_SIZE           ; len >= 64 checked above
    cmp     rax, rdx
    ja      .bad                           ; shdr[0] must fit
    lea     r8, [r12 + rax]                ; r8 = shdr table
    mov     [rbx + INSPCTX_shdrs], r8

    movzx   ecx, word [r12 + EHDR_SHNUM]
    test    ecx, ecx
    jnz     .have_count
    mov     rcx, [r8 + SHDR_SIZE]          ; extended section count
.have_count:
    mov     rdx, r13
    sub     rdx, rax
    shr     rdx, 6                         ; headers that fit after shoff
    cmp     rcx, rdx
    ja      .bad
    mov     [rbx + INSPCTX_shnum], rcx

    movzx   edx, word [r12 + EHDR_SHSTRNDX]
    cmp     edx, SHN_XINDEX
    jne     .have_strndx
    mov     edx, [r8 + SHDR_LINK]          ; extended string table index
.have_strndx:
    mov     [rbx + INSPCTX_shstrndx], rdx

    ; every section with file contents must lie inside the image
    xor     r9d, r9d                       ; r9 = section index
.sec_loop:
    cmp     r9, rcx
    jae     .sec_done
    mov     r10, r9
    shl     r10, 6
    add     r10, r8                        ; r10 = shdr[i]
    cmp     dword [r10 + SHDR_TYPE], SHT_NOBITS
    je      .sec_next
    mov     r11, [r10 + SHDR_SIZE]
    test    r11, r11
    jz      .sec_next
    mov     rax, [r10 + SHDR_OFFSET]
    cmp     rax, r13
    ja      .bad
    mov     rsi, r13
    sub     rsi, rax
    cmp     r11, rsi
    ja      .bad
.sec_next:
    inc     r9
    jmp     .sec_loop
.sec_done:

    ; section-name string table (optional)
    mov     rdx, [rbx + INSPCTX_shstrndx]
    test    rdx, rdx
    jz      .ok
    cmp     rdx, rcx
    jae     .ok                            ; tolerated: names -> <corrupt>
    shl     rdx, 6
    add     rdx, r8
    cmp     dword [rdx + SHDR_TYPE], SHT_NOBITS
    je      .ok
    mov     rax, [rdx + SHDR_OFFSET]
    add     rax, r12
    mov     [rbx + INSPCTX_shstr], rax
    mov     rax, [rdx + SHDR_SIZE]
    mov     [rbx + INSPCTX_shstr_size], rax

.ok:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

.bad:
    mov     eax, EXIT_INVALID_FORMAT
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; Shared helpers (also used by tools/symdump/symdump.s)
; ============================================================================

; ---- ins_flush_line ---------------------
;
; ins_flush_line
; Terminates the current line with '\n', hands it to the sink and starts
; a new line. After the first sink error, lines are discarded and the
; error is kept.
; Input    : rdi = InspCtx
; Output   : rax = current sticky error (EXIT_OK if none)
; Clobbers : rcx, rdx, rsi, rdi, r8-r11 (plus sink clobbers)
;
global ins_flush_line
ins_flush_line:
    push    rbx
    mov     rbx, rdi
    mov     rax, [rbx + INSPCTX_err]
    test    rax, rax
    jnz     .reset

    ; the FmtBuf was created with one spare byte, so '\n' always fits
    mov     rdi, [rbx + INSPCTX_fb + FMTBUF_buf]
    mov     rsi, [rbx + INSPCTX_fb + FMTBUF_len]
    mov     byte [rdi + rsi], 10
    inc     rsi
    mov     rdx, [rbx + INSPCTX_sink_ctx]
    call    [rbx + INSPCTX_sink]
    mov     [rbx + INSPCTX_err], rax

.reset:
    lea     rdi, [rbx + INSPCTX_fb]
    call    fmt_reset
    mov     rax, [rbx + INSPCTX_err]
    pop     rbx
    ret

; ---- ins_shdr ---------------------------
;
; ins_shdr
; Input    : rdi = InspCtx, rsi = section index
; Output   : rax = pointer to the section header, or 0 if out of range
; Clobbers : none
;
global ins_shdr
ins_shdr:
    xor     eax, eax
    cmp     rsi, [rdi + INSPCTX_shnum]
    jae     .done
    mov     rax, rsi
    shl     rax, 6
    add     rax, [rdi + INSPCTX_shdrs]
.done:
    ret

; ---- ins_put_secname --------------------
;
; ins_put_secname
; Appends a section's name, or "<bad index>" for an out-of-range index.
; Input    : rdi = InspCtx, rsi = section index
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
; Clobbers : rcx, rdx, rsi, rdi, r8-r10
;
global ins_put_secname
ins_put_secname:
    push    rbx
    mov     rbx, rdi
    call    ins_shdr
    test    rax, rax
    jz      .bad
    mov     ecx, [rax + SHDR_NAME]
    lea     rdi, [rbx + INSPCTX_fb]
    mov     rsi, [rbx + INSPCTX_shstr]
    mov     rdx, [rbx + INSPCTX_shstr_size]
    call    dump_put_strtab
    pop     rbx
    ret
.bad:
    INS_PUTS "<bad index>"
    pop     rbx
    ret

; ============================================================================
; Printers
; ============================================================================

; ---- ins_print_header -------------------
;
; Prints the ELF file header.  Input: rdi = InspCtx (validated).
;
%define HDR_COL 22

ins_print_header:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, [rbx + INSPCTX_buf]

    INS_PUTS "ELF Header:"
    INS_NL

    INS_PUTS "  Class:"
    INS_PAD HDR_COL
    INS_PUTS "ELF64"
    INS_NL

    INS_PUTS "  Data:"
    INS_PAD HDR_COL
    INS_PUTS "little-endian"
    INS_NL

    INS_PUTS "  Version:"
    INS_PAD HDR_COL
    mov     eax, [r12 + EHDR_VERSION]
    INS_DEC rax
    INS_NL

    INS_PUTS "  OS/ABI:"
    INS_PAD HDR_COL
    movzx   eax, byte [r12 + EI_OSABI]
    INS_NAME NAME_OSABI, rax
    INS_NL

    INS_PUTS "  ABI Version:"
    INS_PAD HDR_COL
    movzx   eax, byte [r12 + EI_ABIVERSION]
    INS_DEC rax
    INS_NL

    INS_PUTS "  Type:"
    INS_PAD HDR_COL
    movzx   eax, word [r12 + EHDR_TYPE]
    INS_NAME NAME_ETYPE, rax
    INS_NL

    INS_PUTS "  Machine:"
    INS_PAD HDR_COL
    movzx   eax, word [r12 + EHDR_MACHINE]
    INS_NAME NAME_MACHINE, rax
    INS_NL

    INS_PUTS "  Entry point:"
    INS_PAD HDR_COL
    INS_HEX0X [r12 + EHDR_ENTRY]
    INS_NL

    INS_PUTS "  Program headers:"
    INS_PAD HDR_COL
    movzx   eax, word [r12 + EHDR_PHNUM]
    INS_DEC rax
    INS_PUTS " at offset "
    INS_DEC [r12 + EHDR_PHOFF]
    INS_PUTS ", "
    movzx   eax, word [r12 + EHDR_PHENTSIZE]
    INS_DEC rax
    INS_PUTS " bytes each"
    INS_NL

    INS_PUTS "  Section headers:"
    INS_PAD HDR_COL
    INS_DEC [rbx + INSPCTX_shnum]
    INS_PUTS " at offset "
    INS_DEC [r12 + EHDR_SHOFF]
    INS_PUTS ", "
    movzx   eax, word [r12 + EHDR_SHENTSIZE]
    INS_DEC rax
    INS_PUTS " bytes each"
    INS_NL

    INS_PUTS "  Flags:"
    INS_PAD HDR_COL
    mov     eax, [r12 + EHDR_FLAGS]
    INS_HEX0X rax
    INS_NL

    INS_PUTS "  String table index:"
    INS_PAD HDR_COL
    INS_DEC [rbx + INSPCTX_shstrndx]
    INS_NL
    INS_NL

    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; ---- ins_print_sections -----------------
;
; Prints the section header table.  Input: rdi = InspCtx (validated).
;
ins_print_sections:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi

    cmp     qword [rbx + INSPCTX_shnum], 0
    jne     .have
    INS_PUTS "There are no sections."
    INS_NL
    INS_NL
    jmp     .done

.have:
    INS_PUTS "Section Headers:"
    INS_NL
    INS_PUTS "  [Nr]"
    INS_PAD 7
    INS_PUTS "Name"
    INS_PAD 25
    INS_PUTS "Type"
    INS_PAD 40
    INS_PUTS "Address"
    INS_PAD 57
    INS_PUTS "Off"
    INS_PAD 66
    INS_PUTS "Size"
    INS_PAD 75
    INS_PUTS "ES"
    INS_PAD 79
    INS_PUTS "Flg"
    INS_PAD 84
    INS_PUTS "Lk"
    INS_PAD 88
    INS_PUTS "Inf"
    INS_PAD 92
    INS_PUTS "Al"
    INS_NL

    xor     r12d, r12d                     ; r12 = section index
.row:
    cmp     r12, [rbx + INSPCTX_shnum]
    jae     .key
    mov     r13, r12
    shl     r13, 6
    add     r13, [rbx + INSPCTX_shdrs]     ; r13 = shdr[i]

    INS_PUTS "  ["
    INS_RDEC r12, 2
    INS_PUTC ']'
    INS_PAD 7
    mov     rdi, rbx
    mov     rsi, r12
    call    ins_put_secname
    INS_PAD 25
    mov     eax, [r13 + SHDR_TYPE]
    INS_NAME NAME_SHTYPE, rax
    INS_PAD 40
    INS_HEX [r13 + SHDR_ADDR], 16
    INS_PAD 57
    INS_HEX [r13 + SHDR_OFFSET], 8
    INS_PAD 66
    INS_HEX [r13 + SHDR_SIZE], 8
    INS_PAD 75
    INS_HEX [r13 + SHDR_ENTSIZE], 2
    INS_PAD 79
    mov     rdi, rbx
    mov     rsi, [r13 + SHDR_FLAGS]
    call    ins_put_shflags
    INS_PAD 84
    mov     eax, [r13 + SHDR_LINK]
    INS_DEC rax
    INS_PAD 88
    mov     eax, [r13 + SHDR_INFO]
    INS_DEC rax
    INS_PAD 92
    INS_DEC [r13 + SHDR_ADDRALIGN]
    INS_NL

    inc     r12
    jmp     .row

.key:
    INS_PUTS "Key to Flags: W (write), A (alloc), X (execute), M (merge), S (strings), I (info),"
    INS_NL
    INS_PUTS "  L (link order), O (extra OS processing), G (group), T (TLS), C (compressed)"
    INS_NL
    INS_NL

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- ins_put_shflags --------------------
;
; Appends the sh_flags letters (readelf order WAXMSILOGTC).
; Input: rdi = InspCtx, rsi = sh_flags
;
ins_put_shflags:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi                       ; r12 = flags
    xor     r13d, r13d                     ; r13 = table index
.next:
    cmp     r13, SHFLAG_COUNT
    jae     .done
    lea     rax, [rel shflag_table]
    movzx   ecx, byte [rax + r13*2]        ; bit number
    bt      r12, rcx
    jnc     .skip
    movzx   eax, byte [rax + r13*2 + 1]    ; letter
    INS_PUTC eax
.skip:
    inc     r13
    jmp     .next
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- ins_print_segments -----------------
;
; Prints the program header table.  Input: rdi = InspCtx (validated).
;
ins_print_segments:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r15, [rbx + INSPCTX_buf]
    movzx   r14d, word [r15 + EHDR_PHNUM]  ; r14 = count

    test    r14, r14
    jnz     .have
    INS_PUTS "There are no program headers."
    INS_NL
    INS_NL
    jmp     .done

.have:
    INS_PUTS "Program Headers:"
    INS_NL
    INS_PUTS "  Type"
    INS_PAD 18
    INS_PUTS "Offset"
    INS_PAD 28
    INS_PUTS "VirtAddr"
    INS_PAD 46
    INS_PUTS "PhysAddr"
    INS_PAD 64
    INS_PUTS "FileSiz"
    INS_PAD 74
    INS_PUTS "MemSiz"
    INS_PAD 84
    INS_PUTS "Flg"
    INS_PAD 88
    INS_PUTS "Align"
    INS_NL

    add     r15, [r15 + EHDR_PHOFF]        ; r15 = phdr[0]
    xor     r12d, r12d
.row:
    cmp     r12, r14
    jae     .end
    imul    r13, r12, ELF64_PHDR_SIZE
    add     r13, r15                       ; r13 = phdr[i]

    INS_PUTS "  "
    mov     eax, [r13 + PHDR_TYPE]
    INS_NAME NAME_PTYPE, rax
    INS_PAD 18
    INS_HEX [r13 + PHDR_OFFSET], 8
    INS_PAD 28
    INS_HEX [r13 + PHDR_VADDR], 16
    INS_PAD 46
    INS_HEX [r13 + PHDR_PADDR], 16
    INS_PAD 64
    INS_HEX [r13 + PHDR_FILESZ], 8
    INS_PAD 74
    INS_HEX [r13 + PHDR_MEMSZ], 8
    INS_PAD 84

    ; flags as three fixed columns: R, W, E (space when clear)
    mov     eax, ' '
    mov     ecx, 'R'
    test    dword [r13 + PHDR_FLAGS], PF_R
    cmovnz  eax, ecx
    INS_PUTC eax
    mov     eax, ' '
    mov     ecx, 'W'
    test    dword [r13 + PHDR_FLAGS], PF_W
    cmovnz  eax, ecx
    INS_PUTC eax
    mov     eax, ' '
    mov     ecx, 'E'
    test    dword [r13 + PHDR_FLAGS], PF_X
    cmovnz  eax, ecx
    INS_PUTC eax

    INS_PAD 88
    INS_HEX0X [r13 + PHDR_ALIGN]
    INS_NL

    inc     r12
    jmp     .row
.end:
    INS_NL
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .rodata]
; (bit number, letter) pairs in readelf order
shflag_table:
    db  0, 'W'          ; SHF_WRITE
    db  1, 'A'          ; SHF_ALLOC
    db  2, 'X'          ; SHF_EXECINSTR
    db  4, 'M'          ; SHF_MERGE
    db  5, 'S'          ; SHF_STRINGS
    db  6, 'I'          ; SHF_INFO_LINK
    db  7, 'L'          ; SHF_LINK_ORDER
    db  8, 'O'          ; SHF_OS_NONCONFORMING
    db  9, 'G'          ; SHF_GROUP
    db 10, 'T'          ; SHF_TLS
    db 11, 'C'          ; SHF_COMPRESSED
                        ; (keep SHFLAG_COUNT at the top in sync)
