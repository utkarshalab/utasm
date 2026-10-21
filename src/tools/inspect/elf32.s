;
; ============================================================================
; File        : src/tools/inspect/elf32.s
; Project     : utasm
; Description : An ELF32 file read as ELF64 (--inspect, --disasm).
;
;   The inspector reads ELF64's tables. An ELF32 file (-f elf32's, an i386
;   object) is widened into one in memory: a 64-byte header, the file's
;   bytes after it (every offset 64 on), the program and section headers
;   in their 64-bit layouts, and the symbol tables (16 -> 24 bytes) and
;   relocations (REL 8 -> 16, RELA 12 -> 24; r_info's symbol >> 8 into the
;   high 32 bits) converted after them. e_machine is kept: EM_386 says
;   32-bit mode to the disassembler, and R_386_* names to the relocation
;   dumps. ins_elf32 says the file was one ("Class: ELF32").
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"
%include "src/include/elf.inc"

DEFAULT REL

extern io_mmap

[SECTION .bss]
global ins_elf32
ins_elf32:  resb 1              ; the file inspected was ELF32 (elf32_widen)

[SECTION .text]

; ---- elf32_widen ------------------------
;
; elf32_widen
; Builds the ELF64 image of an ELF32 little-endian file.
; Input    : rdi = the file's bytes, rsi = its length
; Output   : rax = EXIT_OK, EXIT_INVALID_FORMAT or EXIT_OOM
;            rdx = the image, rcx = its length
;
global elf32_widen
elf32_widen:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 40                        ; [0] total [8] image [16] P [24] S [32] T
    mov     rbx, rdi                       ; rbx = the file
    mov     r12, rsi                       ; r12 = its length
    cmp     r12, 52
    jb      .bad
    movzx   r13d, word [rbx + 48]          ; r13 = e_shnum
    mov     r14d, [rbx + 32]               ; r14 = e_shoff
    test    r13, r13
    jz      .sh_ok
    cmp     word [rbx + 46], 40            ; e_shentsize
    jne     .bad
    imul    rax, r13, 40
    add     rax, r14
    cmp     rax, r12
    ja      .bad
.sh_ok:
    movzx   r15d, word [rbx + 44]          ; r15 = e_phnum
    mov     ebp, [rbx + 28]                ; rbp = e_phoff
    test    r15, r15
    jz      .ph_ok
    cmp     word [rbx + 42], 32            ; e_phentsize
    jne     .bad
    imul    rax, r15, 32
    add     rax, rbp
    cmp     rax, r12
    ja      .bad
.ph_ok:
    ; the layout: header, the file, (8-aligned) program headers, section
    ; headers, the converted tables
    lea     rax, [r12 + 64 + 7]
    and     rax, -8
    mov     [rsp + 16], rax                ; P
    imul    rcx, r15, 56
    add     rax, rcx
    mov     [rsp + 24], rax                ; S
    imul    rcx, r13, 64
    add     rax, rcx
    mov     [rsp + 32], rax                ; T
    mov     [rsp], rax                     ; total (+ the tables)
    xor     ecx, ecx
.size:
    cmp     rcx, r13
    jae     .sized
    imul    rdx, rcx, 40
    add     rdx, r14
    add     rdx, rbx
    call    .kind
    test    eax, eax
    jz      .size_next
    imul    r9, rax
    add     [rsp], r9
.size_next:
    inc     rcx
    jmp     .size
.sized:
    xor     edi, edi
    mov     rsi, [rsp]
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap                        ; (zeroed)
    test    rax, rax
    jnz     .ret_err
    mov     [rsp + 8], rdx
    mov     r10, rdx                       ; r10 = the image

    ; ---- the header ----
    mov     rax, [rbx]
    mov     [r10], rax
    mov     rax, [rbx + 8]
    mov     [r10 + 8], rax
    mov     byte [r10 + EI_CLASS], ELFCLASS64
    mov     eax, [rbx + 16]                ; e_type, e_machine
    mov     [r10 + 16], eax
    mov     eax, [rbx + 20]                ; e_version
    mov     [r10 + 20], eax
    mov     eax, [rbx + 24]                ; e_entry
    mov     [r10 + 24], rax
    test    r15, r15
    jz      .no_phoff
    mov     rax, [rsp + 16]
    mov     [r10 + 32], rax                ; e_phoff
.no_phoff:
    test    r13, r13
    jz      .no_shoff
    mov     rax, [rsp + 24]
    mov     [r10 + 40], rax                ; e_shoff
.no_shoff:
    mov     eax, [rbx + 36]
    mov     [r10 + 48], eax                ; e_flags
    mov     word [r10 + 52], 64            ; e_ehsize
    mov     word [r10 + 54], 56            ; e_phentsize
    mov     [r10 + 56], r15w
    mov     word [r10 + 58], 64            ; e_shentsize
    mov     [r10 + 60], r13w
    mov     ax, [rbx + 50]
    mov     [r10 + 62], ax                 ; e_shstrndx

    ; ---- the file, at 64 ----
    mov     rsi, rbx
    lea     rdi, [r10 + 64]
    mov     rcx, r12
    rep     movsb

    ; ---- program headers ----
    xor     ecx, ecx
.phdr:
    cmp     rcx, r15
    jae     .phdrs_done
    imul    rsi, rcx, 32
    add     rsi, rbp
    add     rsi, rbx
    imul    rdi, rcx, 56
    add     rdi, [rsp + 16]
    add     rdi, r10
    mov     eax, [rsi]
    mov     [rdi], eax                     ; p_type
    mov     eax, [rsi + 24]
    mov     [rdi + 4], eax                 ; p_flags
    mov     eax, [rsi + 4]
    add     rax, 64
    mov     [rdi + 8], rax                 ; p_offset
    mov     eax, [rsi + 8]
    mov     [rdi + 16], rax                ; p_vaddr
    mov     eax, [rsi + 12]
    mov     [rdi + 24], rax                ; p_paddr
    mov     eax, [rsi + 16]
    mov     [rdi + 32], rax                ; p_filesz
    mov     eax, [rsi + 20]
    mov     [rdi + 40], rax                ; p_memsz
    mov     eax, [rsi + 28]
    mov     [rdi + 48], rax                ; p_align
    inc     rcx
    jmp     .phdr
.phdrs_done:

    ; ---- section headers (and the tables they convert) ----
    xor     ecx, ecx
.shdr:
    cmp     rcx, r13
    jae     .done
    imul    rdx, rcx, 40
    add     rdx, r14
    add     rdx, rbx                       ; rdx = Elf32_Shdr
    imul    rdi, rcx, 64
    add     rdi, [rsp + 24]
    add     rdi, r10                       ; rdi = Elf64_Shdr
    mov     eax, [rdx]
    mov     [rdi], eax                     ; sh_name
    mov     eax, [rdx + 4]
    mov     [rdi + 4], eax                 ; sh_type
    mov     eax, [rdx + 8]
    mov     [rdi + 8], rax                 ; sh_flags
    mov     eax, [rdx + 12]
    mov     [rdi + 16], rax                ; sh_addr
    mov     eax, [rdx + 16]
    add     rax, 64
    mov     [rdi + 24], rax                ; sh_offset
    mov     eax, [rdx + 20]
    mov     [rdi + 32], rax                ; sh_size
    mov     eax, [rdx + 24]
    mov     [rdi + 40], eax                ; sh_link
    mov     eax, [rdx + 28]
    mov     [rdi + 44], eax                ; sh_info
    mov     eax, [rdx + 32]
    mov     [rdi + 48], rax                ; sh_addralign
    mov     eax, [rdx + 36]
    mov     [rdi + 56], rax                ; sh_entsize
    push    rcx
    push    rdi
    call    .kind                          ; eax = new entry size, r8 = old,
    pop     rdi                            ; r9 = count
    mov     r10, [rsp + 8 + 8]             ; (the image: .kind took r10)
    test    eax, eax
    jz      .shdr_next
    ; the table, converted at T
    mov     r11, [rsp + 8 + 32]            ; T (past the pushed rcx)
    mov     [rdi + 24], r11
    mov     [rdi + 56], rax
    push    rax
    imul    rax, r9
    mov     [rdi + 32], rax
    add     [rsp + 16 + 32], rax           ; T += the table (past rax, rcx)
    pop     rax
    mov     esi, [rdx + 16]
    add     rsi, rbx                       ; the old entries
    add     r11, r10                       ; the new ones
.entry:
    test    r9, r9
    jz      .shdr_next
    cmp     r8d, 16
    je      .sym
    mov     ecx, [rsi]                     ; r_offset
    mov     [r11], rcx
    mov     ecx, [rsi + 4]                 ; r_info: sym << 8 | type
    mov     edi, ecx
    and     edi, 0xFF
    shr     ecx, 8
    shl     rcx, 32
    or      rcx, rdi
    mov     [r11 + 8], rcx
    cmp     r8d, 12
    jne     .entry_next
    movsxd  rcx, dword [rsi + 8]           ; r_addend
    mov     [r11 + 16], rcx
    jmp     .entry_next
.sym:
    mov     ecx, [rsi]                     ; st_name
    mov     [r11], ecx
    mov     cl, [rsi + 12]                 ; st_info
    mov     [r11 + 4], cl
    mov     cl, [rsi + 13]                 ; st_other
    mov     [r11 + 5], cl
    mov     cx, [rsi + 14]                 ; st_shndx
    mov     [r11 + 6], cx
    mov     ecx, [rsi + 4]                 ; st_value
    mov     [r11 + 8], rcx
    mov     ecx, [rsi + 8]                 ; st_size
    mov     [r11 + 16], rcx
.entry_next:
    add     rsi, r8
    add     r11, rax
    dec     r9
    jmp     .entry
.shdr_next:
    pop     rcx
    inc     rcx
    jmp     .shdr

.done:
    mov     byte [rel ins_elf32], 1
    xor     eax, eax
    mov     rdx, [rsp + 8]
    mov     rcx, [rsp]
    jmp     .ret
.bad:
    mov     eax, EXIT_INVALID_FORMAT
.ret_err:
    xor     edx, edx
    xor     ecx, ecx
.ret:
    add     rsp, 40
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .kind: the Elf32_Shdr at rdx - a table to convert? eax = its new entry
; size (24 symbols / RELA, 16 REL) or 0; r8 = the old one, r9 = the count.
; Keeps rcx, rdx.
.kind:
    xor     eax, eax
    mov     r10d, [rdx + 4]                ; sh_type
    mov     r11d, [rdx + 36]               ; sh_entsize
    cmp     r10d, SHT_SYMTAB
    je      .k_sym
    cmp     r10d, SHT_DYNSYM
    je      .k_sym
    cmp     r10d, SHT_REL
    je      .k_rel
    cmp     r10d, SHT_RELA
    jne     .k_ret
    mov     r8d, 12
    mov     r9d, 24
    jmp     .k_check
.k_rel:
    mov     r8d, 8
    mov     r9d, 16
    jmp     .k_check
.k_sym:
    mov     r8d, 16
    mov     r9d, 24
.k_check:
    cmp     r11d, r8d
    jne     .k_ret
    mov     r10d, [rdx + 16]               ; in the file?
    mov     r11d, [rdx + 20]
    add     r10, r11
    cmp     r10, r12
    ja      .k_ret
    push    rdx
    push    r9
    mov     eax, r11d
    xor     edx, edx
    div     r8
    mov     r10, rdx                       ; (a part entry: not converted)
    mov     r11, rax
    pop     rax                            ; the new entry size
    pop     rdx
    test    r10, r10
    jnz     .k_none
    mov     r9, r11
    ret
.k_none:
    xor     eax, eax
.k_ret:
    ret
