;
; ============================================================================
; File        : backend/output/ubf/out.s
; Project     : utasm
; Description : UBF -- Utkarsha Boot Format -- boot image output (-f ubf)
; ============================================================================
;
; A UBF image is the container the Tattva OS stage-2 loader reads
; (tattvaos boot/stage2/fs/ubf.asm): a 1024-byte header, then the
; components, each starting on a 512-byte sector.
;
;   header (sectors 0-1)
;     0x000  8    magic "UBFORMAT"
;     0x008  4    version (1)
;     0x00C  4    total image size in sectors
;     0x010  4    component count (1-8)
;     0x014  4    CRC-32 of the 1024-byte header, taken with this field 0
;     0x018  4    flags (bit 0: all components signed -- not set here)
;     0x020  512  component table, 8 entries of 64 bytes
;   component entry
;     0x00   4    type (UBF_COMP_*)
;     0x04   4    start sector, from the start of the image
;     0x08   4    size in bytes
;     0x0C   4    load address (physical)
;     0x10   4    entry offset, from the load address (the kernel's)
;     0x14   4    flags
;     0x18   32   SHA-256 of the component's bytes
;
; The assembled program is the kernel component: laid out as a flat binary
; (-f bin: org, sections, relocations), loaded at its org, entered at
; _start (offset 0 without one). --ubf-add TYPE=FILE[@ADDR] adds the other
; components (initrd, dtb, config, module, firmware) from files.
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern io_open
extern io_close
extern io_read_full
extern io_write
extern io_lseek
extern io_mmap
extern io_munmap
extern io_file_size
extern io_ftruncate
extern mem_zero
extern hash_crc32
extern sha256_hash
extern symbol_find
extern str_cmp
extern str_to_int
extern bin_origin

[SECTION .text]

;
; ubf_add_component
; Records one --ubf-add TYPE=FILE[@ADDR] (the string is edited in place).
; Input    : rdi = the option's value
; Output   : rax = EXIT_OK, or EXIT_USAGE when it cannot be read
;
global ubf_add_component
ubf_add_component:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    cmp     dword [rel ubf_extra], UBF_MAX_COMPONENTS - 1
    jae     .bad
    ; TYPE up to '='
    mov     r12, rdi
.find_eq:
    mov     al, [r12]
    test    al, al
    jz      .bad
    cmp     al, '='
    je      .have_eq
    inc     r12
    jmp     .find_eq
.have_eq:
    mov     byte [r12], 0
    inc     r12                            ; the file
    lea     r13, [rel ubf_type_names]
.type:
    cmp     byte [r13], 0
    je      .bad
    mov     rdi, rbx
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .have_type
    add     r13, 12
    jmp     .type
.have_type:
    mov     eax, [rel ubf_extra]
    movzx   ecx, byte [r13 + 11]
    lea     rdx, [rel ubf_comp_type]
    mov     [rdx + rax * 4], ecx
    lea     rdx, [rel ubf_comp_path]
    mov     [rdx + rax * 8], r12
    lea     rdx, [rel ubf_comp_addr]
    mov     dword [rdx + rax * 4], 0
    ; @ADDR: where the loader puts it
    mov     rdi, r12
.find_at:
    mov     cl, [rdi]
    test    cl, cl
    jz      .no_addr
    cmp     cl, '@'
    je      .have_at
    inc     rdi
    jmp     .find_at
.have_at:
    mov     byte [rdi], 0
    inc     rdi
    call    str_to_int
    test    rax, rax
    jnz     .bad
    mov     eax, [rel ubf_extra]
    lea     rcx, [rel ubf_comp_addr]
    mov     [rcx + rax * 4], edx
.no_addr:
    cmp     byte [r12], 0
    je      .bad                           ; no file
    inc     dword [rel ubf_extra]
    xor     eax, eax
    jmp     .ret
.bad:
    mov     rax, EXIT_USAGE
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; ubf_emit
; Writes the image: the laid-out program as the kernel component, the
; --ubf-add files after it, then the header.
; Input    : rdi = AsmCtx (binary_layout has run), esi = output fd
; Output   : rax = EXIT_OK or error
;
global ubf_emit
ubf_emit:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12d, esi

    lea     rdi, [rel ubf_header]
    mov     rsi, UBF_HEADER_BYTES
    call    mem_zero

    ; ---- 1. the kernel: every section with contents at its place ----
    xor     r13d, r13d                     ; its size: the end of the last one
    mov     r8, [rbx + ASMCTX_sections]
    movzx   ecx, word [rbx + ASMCTX_seccount]
    xor     edx, edx
.size_sec:
    cmp     edx, ecx
    jae     .sized
    mov     rax, [r8 + rdx * 8]
    inc     edx
    cmp     dword [rax + SECTION_elf_type], SHT_NOBITS
    je      .size_sec
    mov     r9, [rax + SECTION_size]
    test    r9, r9
    jz      .size_sec
    add     r9, [rax + SECTION_bin_off]
    cmp     r9, r13
    jbe     .size_sec
    mov     r13, r9
    jmp     .size_sec
.sized:
    test    r13, r13
    jz      .empty
    mov     rax, 0xFFFFFFFF
    cmp     r13, rax
    ja      .too_big
    xor     edi, edi
    mov     rsi, r13
    mov     rdx, PROT_READ | PROT_WRITE
    mov     rcx, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap                        ; zeroed: the gaps read as zeros
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; the kernel's bytes
    mov     r8, [rbx + ASMCTX_sections]
    xor     r15d, r15d
.copy_sec:
    cmp     r15w, [rbx + ASMCTX_seccount]
    jae     .copied
    mov     rax, [r8 + r15 * 8]
    inc     r15d
    cmp     dword [rax + SECTION_elf_type], SHT_NOBITS
    je      .copy_sec
    mov     rcx, [rax + SECTION_size]
    test    rcx, rcx
    jz      .copy_sec
    mov     rdi, r14
    add     rdi, [rax + SECTION_bin_off]
    mov     rsi, [rax + SECTION_data]
    rep movsb
    jmp     .copy_sec
.copied:
    ; entry 0
    lea     r15, [rel ubf_header + UBF_HDR_TABLE]
    mov     dword [r15 + UBF_CE_TYPE], UBF_COMP_KERNEL
    mov     dword [r15 + UBF_CE_START], UBF_HEADER_SECTORS
    mov     [r15 + UBF_CE_SIZE], r13d
    mov     rax, [rel bin_origin]
    mov     [r15 + UBF_CE_LOAD], eax
    call    ubf_entry_offset
    mov     [r15 + UBF_CE_ENTRY], eax
    mov     rdi, r14
    mov     rsi, r13
    lea     rdx, [r15 + UBF_CE_SHA256]
    call    sha256_hash
    mov     esi, UBF_HEADER_SECTORS
    mov     rdi, r14
    mov     rdx, r13
    call    ubf_write_at                   ; rax = error, edx = next sector
    push    rdx
    push    rax
    mov     rdi, r14
    mov     rsi, r13
    call    io_munmap
    pop     rax
    pop     rdx
    test    rax, rax
    jnz     .ret
    mov     [rel ubf_next_sector], edx

    ; ---- 2. the --ubf-add components ----
    xor     r15d, r15d
.extra:
    cmp     r15d, [rel ubf_extra]
    jae     .extras_done
    mov     edi, r15d
    call    ubf_add_file
    test    rax, rax
    jnz     .ret
    inc     r15d
    jmp     .extra
.extras_done:

    ; ---- 3. the header ----
    lea     rdi, [rel ubf_header]
    mov     rax, UBF_MAGIC
    mov     [rdi + UBF_HDR_MAGIC], rax
    mov     dword [rdi + UBF_HDR_VERSION], UBF_VERSION
    mov     eax, [rel ubf_next_sector]
    mov     [rdi + UBF_HDR_TOTAL], eax
    mov     eax, [rel ubf_extra]
    inc     eax
    mov     [rdi + UBF_HDR_COUNT], eax
    mov     dword [rdi + UBF_HDR_FLAGS], 0
    mov     rsi, UBF_HEADER_BYTES
    xor     edx, edx
    call    hash_crc32                     ; the CRC field is still 0
    lea     rdi, [rel ubf_header]
    mov     [rdi + UBF_HDR_CRC32], eax
    mov     edi, r12d
    xor     esi, esi
    xor     edx, edx
    call    io_lseek
    test    rax, rax
    jnz     .ret
    mov     edi, r12d
    lea     rsi, [rel ubf_header]
    mov     rdx, UBF_HEADER_BYTES
    call    io_write
    test    rax, rax
    jnz     .ret
    ; the image ends on a sector boundary
    mov     edi, r12d
    mov     esi, [rel ubf_next_sector]
    shl     rsi, 9
    call    io_ftruncate
    jmp     .ret
.empty:
    mov     rax, EXIT_UBF_EMPTY
    jmp     .ret
.too_big:
    mov     rax, EXIT_UBF_TOO_BIG
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; ubf_write_at
; Writes RDX bytes from RDI at sector ESI of the image.
; Input    : r12d = fd
; Output   : rax = EXIT_OK or error, edx = the sector after them
;
ubf_write_at:
    push    r13
    push    r14
    push    r15
    mov     r13, rdi
    mov     r14, rdx
    mov     r15d, esi
    mov     edi, r12d
    mov     esi, r15d
    shl     rsi, 9
    xor     edx, edx
    call    io_lseek
    test    rax, rax
    jnz     .ret
    mov     edi, r12d
    mov     rsi, r13
    mov     rdx, r14
    call    io_write
    test    rax, rax
    jnz     .ret
    lea     rdx, [r14 + 511]
    shr     rdx, 9
    add     edx, r15d
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    ret

;
; ubf_add_file
; Component EDI of the --ubf-add list: read the file, write it at the next
; sector, fill its table entry.
; Input    : rbx = AsmCtx, r12d = fd
; Output   : rax = EXIT_OK or error
;
ubf_add_file:
    push    r13
    push    r14
    push    r15
    push    rbp
    mov     r15d, edi
    lea     rax, [rel ubf_comp_path]
    mov     rdi, [rax + r15 * 8]
    mov     esi, AMD64_O_RDONLY
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     ebp, edx                       ; its fd
    mov     edi, ebp
    call    io_file_size
    test    rax, rax
    jnz     .close
    mov     r13, rdx                       ; its size
    mov     rax, 0xFFFFFFFF
    cmp     r13, rax
    ja      .too_big
    mov     r14, 0                         ; no buffer for an empty file
    test    r13, r13
    jz      .entry
    xor     edi, edi
    mov     rsi, r13
    mov     rdx, PROT_READ | PROT_WRITE
    mov     rcx, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .close
    mov     r14, rdx
    mov     edi, ebp
    mov     rsi, r14
    mov     rdx, r13
    call    io_read_full
    test    rax, rax
    jnz     .unmap
.entry:
    ; entry 1 + EDI
    lea     rax, [r15 + 1]
    shl     rax, 6                         ; 64 bytes an entry
    lea     rdi, [rel ubf_header + UBF_HDR_TABLE]
    add     rdi, rax
    push    rdi
    lea     rax, [rel ubf_comp_type]
    mov     eax, [rax + r15 * 4]
    mov     [rdi + UBF_CE_TYPE], eax
    mov     eax, [rel ubf_next_sector]
    mov     [rdi + UBF_CE_START], eax
    mov     [rdi + UBF_CE_SIZE], r13d
    lea     rax, [rel ubf_comp_addr]
    mov     eax, [rax + r15 * 4]
    mov     [rdi + UBF_CE_LOAD], eax
    lea     rdx, [rdi + UBF_CE_SHA256]
    mov     rdi, r14
    mov     rsi, r13
    call    sha256_hash
    pop     rdi
    ; the bytes
    test    r13, r13
    jz      .unmap
    mov     esi, [rel ubf_next_sector]
    mov     rdi, r14
    mov     rdx, r13
    call    ubf_write_at
    test    rax, rax
    jnz     .unmap
    mov     [rel ubf_next_sector], edx
.unmap:
    push    rax
    test    r14, r14
    jz      .unmapped
    mov     rdi, r14
    mov     rsi, r13
    call    io_munmap
.unmapped:
    pop     rax
.close:
    push    rax
    mov     edi, ebp
    call    io_close
    pop     rax
.ret:
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    ret
.too_big:
    mov     rax, EXIT_UBF_TOO_BIG
    jmp     .close

;
; ubf_entry_offset
; eax = _start's offset from the load address, 0 without a _start.
; Input    : rbx = AsmCtx
;
ubf_entry_offset:
    mov     rdi, rbx
    lea     rsi, [rel ubf_start_name]
    call    symbol_find
    test    rax, rax
    jnz     .none
    movzx   ecx, word [rdx + SYMBOL_section]
    test    ecx, ecx
    jz      .none
    cmp     ecx, 0xFF00
    jae     .none
    mov     rax, [rbx + ASMCTX_sections]
    mov     rax, [rax + rcx * 8 - 8]
    mov     rax, [rax + SECTION_addr]
    add     rax, [rdx + SYMBOL_value]
    sub     rax, [rel bin_origin]
    ret
.none:
    xor     eax, eax
    ret

[SECTION .rodata]
ubf_start_name: db "_start", 0
; --ubf-add types: name (11 bytes) + UBF_COMP_*
ubf_type_names:
    db "initrd", 0, 0,0,0,0, UBF_COMP_INITRD
    db "dtb", 0, 0,0,0,0,0,0,0, UBF_COMP_DTB
    db "config", 0, 0,0,0,0, UBF_COMP_CONFIG
    db "module", 0, 0,0,0,0, UBF_COMP_MODULE
    db "firmware", 0, 0,0, UBF_COMP_FIRMWARE
    db "kernel", 0, 0,0,0,0, UBF_COMP_KERNEL
    db 0

[SECTION .bss]
global ubf_enabled
ubf_enabled:    resb 1              ; -f ubf
alignb 8
ubf_extra:      resd 1              ; --ubf-add components
ubf_next_sector: resd 1
ubf_comp_type:  resd UBF_MAX_COMPONENTS
ubf_comp_addr:  resd UBF_MAX_COMPONENTS
ubf_comp_path:  resq UBF_MAX_COMPONENTS
ubf_header:     resb UBF_HEADER_BYTES
