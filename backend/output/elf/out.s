;
; ============================================================================
; File        : src/linker/elf64.s
; Project     : utasm
; Description : ELF64 relocatable object file emitter (-f elf64).
;                Writes a standards-compliant ELF64 .o file consumable by
;                ld, lld, and any POSIX linker.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"
%include "include/elf.inc"

[SECTION .text]
    extern  mem_zero
    extern  arena_alloc
    extern  io_write
    extern  io_write_byte
    extern  io_lseek
    extern  asmctx_get_section
    extern  str_cmp
    extern  str_len

; ============================================================================
; elf64_emit
; ============================================================================
;
; elf64_emit
; Top-level entry point: writes a complete ELF64 relocatable object file
; from the current AsmCtx to the file descriptor provided.

; Layout written to disk:
;   [0]   ELF64 File Header         (64 bytes)
;   [64]  .text section data        (variable)
;          .data section data        (variable)
;          .bss  section data        (0 bytes in file)
;   [...]  .symtab entries          (24 bytes each)
;   [...]  .strtab null-term strings
;   [...]  .shstrtab section names
;   [...]  .rela.text entries       (24 bytes each)
;   [end]  Section Header Table     (64 bytes each)

; Input  : rdi = pointer to AsmCtx
;            rsi = output file descriptor (i32)
; Output : rax = EXIT_OK or error code
;
global elf64_emit
elf64_emit:
    prologue
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi               ; r12 = AsmCtx
    mov     r13d, esi              ; r13d = fd
    mov     [rel elf_sa_ctx], r12
    mov     al, [r12 + ASMCTX_standalone]
    mov     [rel elf_sa_on], al
    cmp     al, 1
    je      .text_kept
    mov     rdi, r12
    call    elf64_order_text
.text_kept:

    ; The section info table, {offset, size} by section index, on the stack
    ; (the code below addresses it at rsp): an entry for every section, its
    ; .rela section and the ones made here. It was 32 entries, and a file
    ; with 30 sections wrote past it over the saved registers.
    movzx   eax, word [r12 + ASMCTX_seccount]
    lea     rax, [rax * 2 + 16]
    shl     rax, 4                         ; 16 bytes each (a multiple of 16)
    mov     [rel elf_info_size], rax
    sub     rsp, rax

    mov     rdi, rsp
    mov     rsi, rax
    call    mem_zero

    ; ---- 0. Resolve Entry Point (Standalone only) ----
    IF byte [r12 + ASMCTX_standalone], e, 1
        mov     rdi, r12
        call    elf64_resolve_entry
        check_err
        ENDIF

    ; ---- 1. Write ELF Header ----
    mov     rdi, [r12 + ASMCTX_arena]
    mov     rsi, ELF64_EHDR_SIZE
    call    arena_alloc
    check_err
    mov     r14, rdx               ; r14 = ehdr buffer

    call    elf64_write_ehdr
    check_err

    mov     edi, r13d
    mov     rsi, r14
    mov     rdx, ELF64_EHDR_SIZE
    call    io_write
    check_err

    ; ---- 2. Write Program Headers (if standalone) ----
    IF byte [r12 + ASMCTX_standalone], e, 1
        mov     rdi, r12
        mov     esi, r13d
        call    elf64_write_phdrs
        check_err
        ENDIF

    ; ---- 3. Write .text section ----
    ; A source file may define no code at all, so .text can be absent.
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    IF rax, e, 0
        movzx   ebx, word [rdx + SECTION_index] ; ebx = index
        IF byte [r12 + ASMCTX_standalone], e, 1
            mov     edi, r13d
            call    elf64_place_section
            check_err
            ENDIF

        ; Record start
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     [rsp + rax], rdx

        call    elf64_write_text_section
        check_err

        ; Record end/size
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     r11, [rsp + rax]
        sub     rdx, r11
        mov     [rsp + rax + 8], rdx
        ENDIF

    ; ---- 4. Write .data section ----
    ; Ensure .data is aligned correctly in file (A88)
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    IF rax, e, 0
        movzx   ebx, word [rdx + SECTION_index] ; ebx = index
        mov     edi, r13d
        call    elf64_place_section
        check_err

        ; Record start
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     [rsp + rax], rdx
        
        call    elf64_write_data_section
        check_err
        
        ; Record end/size
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     r11, [rsp + rax]
        sub     rdx, r11
        mov     [rsp + rax + 8], rdx
    ENDIF

    ; ---- 4b. Write .rodata section ----
    mov     rdi, r12
    mov     rsi, SEC_RODATA
    call    asmctx_get_section
    IF rax, e, 0
        movzx   ebx, word [rdx + SECTION_index] ; ebx = index
        mov     edi, r13d
        call    elf64_place_section
        check_err

        ; Record start
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     [rsp + rax], rdx

        call    elf64_write_rodata_section
        check_err

        ; Record end/size
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     r11, [rsp + rax]
        sub     rdx, r11
        mov     [rsp + rax + 8], rdx
    ENDIF

    ; Ensure .bss is aligned (A88)
    mov     rdi, r12
    mov     rsi, SEC_BSS
    call    asmctx_get_section
    IF rax, e, 0
        mov     r14, rdx                        ; r14 = BSS Section pointer
        movzx   ebx, word [r14 + SECTION_index] ; ebx = index
        mov     rsi, [r14 + SECTION_align]
        IF rsi, e, 0
            mov rsi, 8
        ENDIF
        mov     edi, r13d
        call    elf64_align_file
        check_err
        
        ; Query position to record offset
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     [rsp + rax], rdx            ; offset
        mov     r11, [r14 + SECTION_size]
        mov     [rsp + rax + 8], r11        ; size
    ENDIF

    ; ---- 4c. Sections with other names ("section .init", ".text.hot") ----
    ; In index order, after the standard four. A nobits one takes no file
    ; space; it is only given its offset and size. In a standalone
    ; executable the loaded ones go to their addresses first; the others
    ; then follow the end of the file.
    mov     byte [rel elf_custom_pass], 1
.custom_pass:
    cmp     byte [rel elf_custom_pass], 2
    jne     .custom_pass_go
    cmp     byte [r12 + ASMCTX_standalone], 1
    jne     .custom_pass_go
    mov     edi, r13d
    xor     esi, esi
    mov     edx, 2                         ; SEEK_END
    call    io_lseek
    check_err
.custom_pass_go:
    xor     r15d, r15d
.custom_loop:
    cmp     r15w, [r12 + ASMCTX_seccount]
    jae     .custom_pass_end
    mov     rax, [r12 + ASMCTX_sections]
    mov     r14, [rax + r15 * 8]           ; r14 = SECTION*
    inc     r15d
    cmp     byte [r14 + SECTION_type], SEC_CUSTOM
    jne     .custom_loop
    ; pass 1: sections with an address; pass 2: the rest
    xor     eax, eax
    cmp     qword [r14 + SECTION_addr], 0
    setne   al
    mov     ecx, 2
    sub     cl, [rel elf_custom_pass]
    cmp     eax, ecx
    jne     .custom_loop
    movzx   ebx, word [r14 + SECTION_index]
    mov     rdx, r14
    mov     edi, r13d
    call    elf64_place_section
    check_err
    mov     edi, r13d
    xor     esi, esi
    mov     edx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     [rsp + rax], rdx               ; offset
    mov     rdx, [r14 + SECTION_size]
    mov     [rsp + rax + 8], rdx           ; size
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    je      .custom_loop
    mov     edi, r13d
    mov     rsi, [r14 + SECTION_data]
    mov     rdx, [r14 + SECTION_size]
    call    io_write
    check_err
    jmp     .custom_loop
.custom_pass_end:
    inc     byte [rel elf_custom_pass]
    cmp     byte [rel elf_custom_pass], 2
    jbe     .custom_pass
.custom_done:

    ; In an executable the sections sit at their addresses, not in writing
    ; order (.rodata comes before .data): continue after the last of them.
    IF byte [r12 + ASMCTX_standalone], e, 1
        mov     edi, r13d
        xor     esi, esi
        mov     edx, 2                 ; SEEK_END
        call    io_lseek
        check_err
        ENDIF

    ; ---- 4.5 Write Section Groups (A57) ----
    mov     rdi, r12
    mov     esi, r13d
    call    elf64_write_groups
    check_err

    ; ---- 5. Write Metadata sections ----
    mov     rdi, r12
    call    elf64_prepare_strtab
    check_err

    ; Compute meta_base = seccount + group_count
    movzx   r14d, word [r12 + ASMCTX_seccount]
    add     r14d, [r12 + ASMCTX_group_count]

    ; ---- Write .symtab ----
    lea     ebx, [r14d + 1]
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     [rsp + rax], rdx

    mov     rdi, r12
    mov     esi, r13d
    call    elf64_write_symtab
    check_err
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     r11, [rsp + rax]
    sub     rdx, r11
    mov     [rsp + rax + 8], rdx

    ; ---- Write .strtab ----
    lea     ebx, [r14d + 2]
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     [rsp + rax], rdx
    
    call    elf64_write_strtab
    check_err
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     r11, [rsp + rax]
    sub     rdx, r11
    mov     [rsp + rax + 8], rdx

    ; ---- Write .shstrtab ----
    lea     ebx, [r14d + 3]
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     [rsp + rax], rdx
    
    call    elf64_write_shstrtab
    check_err
    
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, rbx
    shl     rax, 4
    mov     r11, [rsp + rax]
    sub     rdx, r11
    mov     [rsp + rax + 8], rdx

    ; ---- Write one .rela.<name> per section that has relocations ----
    ; Relocations carry the section they belong to. They must not all go into
    ; .rela.text: the linker applies a relocation section to whatever sh_info
    ; names, so a .rodata entry written there would be applied to .text.
    ; The rela sections come last in the header table, so numbering them from
    ; meta_base+4 upwards shifts nothing before them.
    ; r15 = next rela section index, r10 = iteration index over sections
    lea     r15d, [r14d + 4]
    xor     r10d, r10d
.rela_sec_loop:
    cmp     r10w, [r12 + ASMCTX_seccount]
    jge     .rela_sec_done

    mov     rax, [r12 + ASMCTX_sections]
    mov     rbx, [rax + r10 * 8]           ; rbx = SECTION*

    push    r10
    mov     rdi, r12
    mov     rsi, rbx
    call    elf64_relocs_in_section
    pop     r10
    test    rax, rax
    jz      .rela_sec_next

    ; Record start offset for this rela section
    push    r10
    push    rbx
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, r15
    shl     rax, 4
    mov     [rsp + 16 + rax], rdx          ; +16 for the two pushes above

    mov     rdi, rbx
    call    elf64_write_rela
    check_err_to .rela_err

    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     rax, r15
    shl     rax, 4
    mov     r11, [rsp + 16 + rax]
    sub     rdx, r11
    mov     [rsp + 16 + rax + 8], rdx
    pop     rbx
    pop     r10

    inc     r15d                           ; next rela section index

.rela_sec_next:
    inc     r10d
    jmp     .rela_sec_loop

.rela_err:
    add     rsp, 16                        ; drop the two saved registers
    jmp     .error

.rela_sec_done:

    call    elf64_write_debug_line
    check_err
    call    elf64_write_debug_info
    check_err
    call    elf64_write_debug_abbrev
    check_err

    ; ---- 6. Write Section Header Table ----
    ; Query position for e_shoff
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 1
    call    io_lseek
    mov     r15, rdx               ; r15 = e_shoff

    mov     rdi, r12
    mov     rsi, r13               ; wait, r13d is FD
    mov     rdx, rsp               ; section_info table
    call    elf64_write_shdrs
    check_err

    ; Seek back to EHDR_SHOFF (offset 40)
    mov     edi, r13d
    mov     rsi, 40
    xor     rdx, rdx               ; SEEK_SET
    call    io_lseek
    check_err
    
    ; Write the section header table offset (r15)
    sub     rsp, 8
    mov     [rsp], r15
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 8
    call    io_write
    add     rsp, 8
    check_err
    
    ; Seek back to the end of the file
    mov     edi, r13d
    xor     rsi, rsi
    mov     rdx, 2                 ; SEEK_END
    call    io_lseek
    check_err

    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    add     rsp, [rel elf_info_size]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    epilogue

;*
; * [elf64_write_debug_line]
; ;
elf64_write_debug_line:
    prologue
    push    rbx
    sub     rsp, 16
    
    ; 1. Unit Length (Length of data after this field)
    ; 2 (version) + 1 (type) + 1 (addr_size) + 4 (abbrev) = 8
    ; Note: Line info stub here is even simpler.
    mov     dword [rsp], 0
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 4
    call    io_write
    check_err
    
    ; 2. Version
    mov     word [rsp], 5
    mov     rdx, 2
    call    io_write
    check_err
    
    add     rsp, 16
    pop     rbx
    xor     rax, rax
    jmp     .done
.error:
    add     rsp, 16
    pop     rbx
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

;*
; * [elf64_write_debug_info]
; * Writes a minimal DWARF v5 Compile Unit header.
; ;
elf64_write_debug_info:
    prologue
    push    rbx
    sub     rsp, 16
    
    ; 1. Unit Length (Version + Type + AddrSize + AbbrevOffset = 8)
    mov     dword [rsp], 8
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 4
    call    io_write
    
    ; 2. Version (5)
    mov     word [rsp], 5
    mov     rdx, 2
    call    io_write
    
    ; 3. Unit Type (DW_UT_compile = 1)
    mov     byte [rsp], 1
    mov     rdx, 1
    call    io_write
    
    ; 4. Address Size (8)
    mov     byte [rsp], 8
    mov     rdx, 1
    call    io_write
    
    ; 5. Abbrev Offset (0)
    mov     dword [rsp], 0
    mov     rdx, 4
    call    io_write
    
    add     rsp, 16
    pop     rbx
    xor     rax, rax
    epilogue

;*
; * [elf64_write_debug_abbrev]
; * Writes a minimal DWARF v5 abbreviation table.
; ;
elf64_write_debug_abbrev:
    prologue
    ; Write a single 0 byte (Empty abbrev table)
    sub     rsp, 16
    mov     byte [rsp], 0
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 1
    call    io_write
    add     rsp, 16
    xor     rax, rax
    epilogue

; ============================================================================
; elf64_write_ehdr
; ============================================================================
; Standalone executables
; ============================================================================
; The file is mapped at ELF_SA_BASE. The ELF header, the program headers and
; .text form one R+X segment from file offset 0; .rodata is an R segment and
; .data/.bss an RW segment, each starting on a new page. Every section's file
; offset is therefore its address minus ELF_SA_BASE, which elf64_emit uses
; to place it.

%define ELF_SA_BASE     0x400000

; elf64_sa_class: where a section goes in a standalone executable
%define SA_NONE         0           ; not loaded
%define SA_EXEC         1           ; the R+X segment, after .text
%define SA_RO           2           ; the R segment, after .rodata
%define SA_RW           3           ; the RW segment, after .data
%define SA_NOBITS       4           ; the RW segment's memory part, after .bss

[SECTION .bss]
elf_sa_phnum:   resb 1              ; program headers in this executable
elf_sa_has_ro:  resb 1
elf_sa_has_rw:  resb 1
elf_sa_on:      resb 1              ; 1 while writing a standalone executable
elf_sa_ctx:     resq 1
elf_info_size:  resq 1              ; elf64_emit: its section table's size
elf_sa_rw_off:  resq 1              ; file offset of the RW segment
elf_sa_rw_end:  resq 1              ; its end in memory (.bss included), as offset
elf_sa_text_end: resq 1             ; end of the R+X segment in the file
elf_sa_ro_off:  resq 1              ; the R segment, as file offsets
elf_sa_ro_end:  resq 1
elf_sa_rw_file_end: resq 1          ; end of the RW segment's file part
elf_custom_pass: resb 1             ; elf64_emit's pass over other sections

[SECTION .text]

;*
; * [elf64_standalone_layout]
; * Purpose: Give the sections of a standalone executable their virtual
; *          addresses. Runs after jump relaxation (sizes are final) and
; *          before relocations are resolved (they use the addresses).
; * Input  : RDI = AsmCtx
; * Output : RAX = EXIT_OK
; ;
global elf64_standalone_layout
elf64_standalone_layout:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     byte [rel elf_sa_has_ro], 0
    mov     byte [rel elf_sa_has_rw], 0

    ; which segments are there
    mov     rdi, r12
    mov     rsi, SEC_RODATA
    call    asmctx_get_section
    test    rax, rax
    jnz     .no_ro
    cmp     qword [rdx + SECTION_size], 0
    je      .no_ro
    mov     byte [rel elf_sa_has_ro], 1
.no_ro:
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    test    rax, rax
    jnz     .no_data
    cmp     qword [rdx + SECTION_size], 0
    je      .no_data
    mov     byte [rel elf_sa_has_rw], 1
.no_data:
    mov     rdi, r12
    mov     rsi, SEC_BSS
    call    asmctx_get_section
    test    rax, rax
    jnz     .no_bss
    cmp     qword [rdx + SECTION_size], 0
    je      .no_bss
    mov     byte [rel elf_sa_has_rw], 1
.no_bss:
    ; sections with other names join the segment their flags call for
    xor     r14d, r14d
.scan:
    cmp     r14w, [r12 + ASMCTX_seccount]
    jae     .scanned
    mov     rax, [r12 + ASMCTX_sections]
    mov     rbx, [rax + r14 * 8]
    inc     r14d
    cmp     byte [rbx + SECTION_type], SEC_CUSTOM
    jne     .scan
    cmp     qword [rbx + SECTION_size], 0
    je      .scan
    call    elf64_sa_class
    cmp     eax, SA_RO
    jne     .scan_rw
    mov     byte [rel elf_sa_has_ro], 1
    jmp     .scan
.scan_rw:
    cmp     eax, SA_RW
    jb      .scan
    mov     byte [rel elf_sa_has_rw], 1
    jmp     .scan
.scanned:
    movzx   eax, byte [rel elf_sa_has_ro]
    movzx   ecx, byte [rel elf_sa_has_rw]
    lea     eax, [rax + rcx + 1]
    mov     [rel elf_sa_phnum], al
    imul    r13, rax, ELF64_PHDR_SIZE
    add     r13, ELF64_EHDR_SIZE           ; r13 = file offset after the headers

    ; .text right after the headers, then other executable sections
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    test    rax, rax
    jnz     .text_done
    mov     rbx, rdx
    mov     rsi, [rbx + SECTION_align]
    cmp     rsi, 16
    jae     .text_align
    mov     rsi, 16
.text_align:
    call    .align_r13
    lea     rax, [r13 + ELF_SA_BASE]
    mov     [rbx + SECTION_addr], rax
    add     r13, [rbx + SECTION_size]
.text_done:
    mov     ecx, SA_EXEC
    call    .place_custom
    mov     [rel elf_sa_text_end], r13

    ; .rodata and other read-only sections on their own page
    cmp     byte [rel elf_sa_has_ro], 0
    je      .ro_done
    mov     rsi, 0x1000
    call    .align_r13
    mov     [rel elf_sa_ro_off], r13
    mov     rdi, r12
    mov     rsi, SEC_RODATA
    call    asmctx_get_section
    test    rax, rax
    jnz     .ro_custom
    mov     rbx, rdx
    mov     rsi, [rbx + SECTION_align]
    call    .align_r13
    lea     rax, [r13 + ELF_SA_BASE]
    mov     [rbx + SECTION_addr], rax
    add     r13, [rbx + SECTION_size]
.ro_custom:
    mov     ecx, SA_RO
    call    .place_custom
    mov     [rel elf_sa_ro_end], r13
.ro_done:

    ; .data and other writable sections, then .bss and other nobits ones
    ; (memory only), on the next page
    cmp     byte [rel elf_sa_has_rw], 0
    je      .rw_done
    mov     rsi, 0x1000
    call    .align_r13
    mov     [rel elf_sa_rw_off], r13
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    test    rax, rax
    jnz     .rw_custom
    mov     rbx, rdx
    mov     rsi, [rbx + SECTION_align]
    call    .align_r13
    lea     rax, [r13 + ELF_SA_BASE]
    mov     [rbx + SECTION_addr], rax
    add     r13, [rbx + SECTION_size]
.rw_custom:
    mov     ecx, SA_RW
    call    .place_custom
    mov     [rel elf_sa_rw_file_end], r13  ; the file part ends here
    mov     rdi, r12
    mov     rsi, SEC_BSS
    call    asmctx_get_section
    test    rax, rax
    jnz     .rw_end
    mov     rbx, rdx
    mov     rsi, [rbx + SECTION_align]
    call    .align_r13
    lea     rax, [r13 + ELF_SA_BASE]
    mov     [rbx + SECTION_addr], rax
    add     r13, [rbx + SECTION_size]
.rw_end:
    mov     ecx, SA_NOBITS
    call    .place_custom
    mov     [rel elf_sa_rw_end], r13
.rw_done:
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; The sections of class ECX (elf64_sa_class) with other names, in order,
; each at the next multiple of its alignment from r13.
.place_custom:
    push    r14
    push    r15
    mov     r15d, ecx
    xor     r14d, r14d
.pc_next:
    cmp     r14w, [r12 + ASMCTX_seccount]
    jae     .pc_done
    mov     rax, [r12 + ASMCTX_sections]
    mov     rbx, [rax + r14 * 8]
    inc     r14d
    cmp     byte [rbx + SECTION_type], SEC_CUSTOM
    jne     .pc_next
    call    elf64_sa_class
    cmp     eax, r15d
    jne     .pc_next
    mov     rsi, [rbx + SECTION_align]
    call    .align_r13
    lea     rax, [r13 + ELF_SA_BASE]
    mov     [rbx + SECTION_addr], rax
    add     r13, [rbx + SECTION_size]
    jmp     .pc_next
.pc_done:
    pop     r15
    pop     r14
    ret

; r13 = r13 rounded up to rsi (a power of two; 0 or 1 = no alignment)
.align_r13:
    cmp     rsi, 1
    jbe     .al_ret
    lea     rax, [rsi - 1]
    add     r13, rax
    not     rax
    and     r13, rax
.al_ret:
    ret

;
; elf64_sa_class
; Which part of a standalone executable a section belongs to.
; Input    : rbx = SECTION*
; Output   : eax = SA_NONE (not loaded), SA_EXEC, SA_RO, SA_RW or SA_NOBITS
; Clobbers : rcx
;
elf64_sa_class:
    xor     eax, eax
    movzx   ecx, word [rbx + SECTION_flags]
    test    ecx, SHF_ALLOC
    jz      .ret
    mov     eax, SA_NOBITS
    cmp     dword [rbx + SECTION_elf_type], SHT_NOBITS
    je      .ret
    mov     eax, SA_EXEC
    test    ecx, SHF_EXECINSTR
    jnz     .ret
    mov     eax, SA_RW
    test    ecx, SHF_WRITE
    jnz     .ret
    mov     eax, SA_RO
.ret:
    ret

;
; elf64_order_text
; utasm creates .text before reading the source; NASM creates a section
; where the source first names it. So in an object file the default .text
; moves to where the source named it, or last when it never did -- and is
; left out when, besides, nothing went into it. The sections it passes and
; the symbols in them are renumbered.
; Input    : rdi = AsmCtx
;
elf64_order_text:
    push    rbx
    push    r12
    movzx   ecx, word [rdi + ASMCTX_seccount]
    cmp     ecx, 2
    jb      .keep
    mov     rsi, [rdi + ASMCTX_sections]
    mov     rbx, [rsi]                     ; the default .text
    cmp     byte [rbx + SECTION_implicit], 0
    je      .keep
    mov     r8, [rdi + ASMCTX_symtab]
    mov     r9d, [rdi + ASMCTX_symcount]
    mov     eax, [rbx + SECTION_named_at]
    test    eax, eax
    jz      .never_named
    lea     r12d, [rax - 1]                ; its position
    jmp     .move
.never_named:
    lea     r12d, [rcx - 1]                ; last
    cmp     qword [rbx + SECTION_size], 0
    jne     .move
    xor     r10d, r10d
.sym:
    cmp     r10d, r9d
    jae     .drop
    imul    r11, r10, SYMBOL_SIZE
    cmp     dword [r8 + r11 + SYMBOL_section], 1
    je      .move                          ; a label in it: keep it
    inc     r10d
    jmp     .sym
.drop:
    ; leave it out: the others move up one
    xor     edx, edx
.shift:
    lea     r10d, [rdx + 1]
    cmp     r10d, ecx
    jae     .shifted
    mov     rax, [rsi + r10 * 8]
    mov     [rsi + rdx * 8], rax
    dec     dword [rax + SECTION_index]
    inc     edx
    jmp     .shift
.shifted:
    dec     ecx
    mov     [rdi + ASMCTX_seccount], cx
    xor     r10d, r10d
.drop_renumber:
    cmp     r10d, r9d
    jae     .keep
    imul    r11, r10, SYMBOL_SIZE
    mov     eax, [r8 + r11 + SYMBOL_section]
    cmp     eax, 1
    jbe     .drop_next
    cmp     eax, 0xFF00                    ; SHN_ABS and the like
    jae     .drop_next
    dec     dword [r8 + r11 + SYMBOL_section]
.drop_next:
    inc     r10d
    jmp     .drop_renumber

.move:
    test    r12d, r12d
    jz      .keep                          ; already in place
    xor     edx, edx
.move_up:
    cmp     edx, r12d
    jae     .moved
    mov     rax, [rsi + rdx * 8 + 8]
    mov     [rsi + rdx * 8], rax
    dec     dword [rax + SECTION_index]
    inc     edx
    jmp     .move_up
.moved:
    mov     [rsi + r12 * 8], rbx
    lea     eax, [r12d + 1]
    mov     [rbx + SECTION_index], eax
    ; symbols: 1 -> its new index, 2 .. new index -> one less
    xor     r10d, r10d
.move_renumber:
    cmp     r10d, r9d
    jae     .keep
    imul    r11, r10, SYMBOL_SIZE
    mov     eax, [r8 + r11 + SYMBOL_section]
    cmp     eax, 1
    jb      .move_next
    jne     .move_other
    lea     eax, [r12d + 1]
    mov     [r8 + r11 + SYMBOL_section], eax
    jmp     .move_next
.move_other:
    lea     edx, [r12d + 1]
    cmp     eax, edx
    ja      .move_next
    dec     dword [r8 + r11 + SYMBOL_section]
.move_next:
    inc     r10d
    jmp     .move_renumber
.keep:
    pop     r12
    pop     rbx
    ret

;*
; * [elf64_place_section]
; * Purpose: Move the file position to where section RDX belongs: its
; *          address minus ELF_SA_BASE in a standalone executable (layout
; *          above), else the next multiple of its alignment.
; * Input  : EDI = fd, RDX = SECTION*
; * Output : RAX = EXIT_OK or an error
; ;
elf64_place_section:
    cmp     byte [rel elf_sa_on], 0
    je      .aligned
    mov     rsi, [rdx + SECTION_addr]
    test    rsi, rsi
    jz      .aligned
    sub     rsi, ELF_SA_BASE
    xor     edx, edx                       ; SEEK_SET: the gap reads as zeros
    jmp     io_lseek
.aligned:
    mov     rsi, [rdx + SECTION_align]
    test    rsi, rsi
    jnz     .align_it
    mov     rsi, 8
.align_it:
    jmp     elf64_align_file

; ============================================================================
;
; elf64_resolve_entry
; Finds the _start symbol and computes its absolute virtual address.
; Input  : rdi = AsmCtx
; Output : rax = EXIT_OK or EXIT_UNDEF_SYMBOL
;
elf64_resolve_entry:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     r12, rdi ; AsmCtx
    
    mov     rdi, r12               ; symbol_find takes the AsmCtx
    lea     rsi, [rel .str_start]
    extern  symbol_find
    call    symbol_find
    IF rax, e, EXIT_OK
        mov     r10, rdx ; SYMBOL*
        mov     rax, [r10 + SYMBOL_value]

        ; Add section base address
        movzx   r11, word [r10 + SYMBOL_section]
        dec     r11                ; ELF index is 1-based; array is 0-based
        mov     r14, [r12 + ASMCTX_sections]
        mov     r13, [r14 + r11 * 8] ; SECTION*
        add     rax, [r13 + SECTION_addr]
        
        ; A94: Architectural Validation - Entry must be in Executable section
        movzx   ecx, word [r13 + SECTION_flags]
        test    ecx, SHF_EXECINSTR
        jz      .error_non_exec
        
        mov     [r12 + ASMCTX_entry_point], rax
        xor     rax, rax
        jmp     .done
        ELSE
        mov     rax, EXIT_UNDEF_REF
        jmp     .done
        ENDIF

.error_non_exec:
    mov     rax, EXIT_ENCODE_FAIL   ; Better error code for "entry not executable"

.done:
    
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.str_start: db "_start", 0

; ============================================================================
;
; elf64_write_ehdr
; Fills the 64-byte ELF file header buffer at r14 with correct values
; for a relocatable AMD64 object file (ET_REL).
; Input  : r12 = AsmCtx, r14 = ehdr buffer
; Output : rax = EXIT_OK
;
elf64_write_ehdr:
    prologue

    ; Zero the buffer
    mov     rdi, r14
    mov     rsi, ELF64_EHDR_SIZE
    call    mem_zero
    check_err

    ; e_ident magic
    mov     byte [r14 + EHDR_IDENT + EI_MAG0],    ELFMAG0
    mov     byte [r14 + EHDR_IDENT + EI_MAG1],    ELFMAG1
    mov     byte [r14 + EHDR_IDENT + EI_MAG2],    ELFMAG2
    mov     byte [r14 + EHDR_IDENT + EI_MAG3],    ELFMAG3
    mov     byte [r14 + EHDR_IDENT + EI_CLASS],   ELFCLASS64
    mov     byte [r14 + EHDR_IDENT + EI_DATA],    ELFDATA2LSB
    mov     byte [r14 + EHDR_IDENT + EI_VERSION], EV_CURRENT
    mov     byte [r14 + EHDR_IDENT + EI_OSABI],   ELFOSABI_NONE

    ; e_type
    IF byte [r12 + ASMCTX_standalone], e, 1
        mov     word [r14 + EHDR_TYPE],    ET_EXEC
        ELSE
        mov     word [r14 + EHDR_TYPE],    ET_REL
        ENDIF
    
    ; ---- FIX: DYNAMIC MACHINE TYPE ----
    mov     al, [r12 + ASMCTX_target]
    IF al, e, TARGET_AARCH64
        mov     word [r14 + EHDR_MACHINE], EM_AARCH64
    ELSEIF al, e, TARGET_RISCV64
        mov     word [r14 + EHDR_MACHINE], EM_RISCV
        ELSE
        mov     word [r14 + EHDR_MACHINE], EM_X86_64
        ENDIF
    
    mov     dword [r14 + EHDR_VERSION], EV_CURRENT

    ; e_entry
    mov     rax, [r12 + ASMCTX_entry_point]
    mov     qword [r14 + EHDR_ENTRY], rax

    ; e_phoff
    IF byte [r12 + ASMCTX_standalone], e, 1
        mov     qword [r14 + EHDR_PHOFF], ELF64_EHDR_SIZE
        mov     word  [r14 + EHDR_PHENTSIZE], ELF64_PHDR_SIZE
        movzx   eax, byte [rel elf_sa_phnum]
        mov     word  [r14 + EHDR_PHNUM], ax
        ELSE
        mov     qword [r14 + EHDR_PHOFF], 0
        mov     word  [r14 + EHDR_PHENTSIZE], 0
        mov     word  [r14 + EHDR_PHNUM], 0
        ENDIF

    ; e_shoff will be patched after all sections are written
    ; e_shnum and e_shstrndx
    movzx   eax, word [r12 + ASMCTX_seccount]
    add     eax, [r12 + ASMCTX_group_count]
    add     eax, 4                 ; NULL + symtab + strtab + shstrtab
    ; plus one .rela.<name> for every section that has relocations
    push    rax
    mov     rdi, r12
    call    elf64_count_rela_sections
    mov     rcx, rax
    pop     rax
    add     eax, ecx
    mov     word  [r14 + EHDR_SHNUM], ax
    
    ; .shstrtab index is 1 + seccount + group_count + 2 (symtab, strtab)
    movzx   ecx, word [r12 + ASMCTX_seccount]
    add     ecx, [r12 + ASMCTX_group_count]
    add     ecx, 3                 ; 0:NULL, 1..N:User, N+1:sym, N+2:str, N+3:shstr
    mov     word  [r14 + EHDR_SHSTRNDX], cx

    mov     word  [r14 + EHDR_EHSIZE],    ELF64_EHDR_SIZE
    mov     word  [r14 + EHDR_SHENTSIZE], ELF64_SHDR_SIZE

    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

;*
; * [elf64_write_phdrs]
; * Writes one PT_LOAD per segment of elf64_standalone_layout: R+X for the
; * headers and .text, R for .rodata, RW for .data and .bss.
; ;
elf64_write_phdrs:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi               ; r12 = AsmCtx
    mov     r13d, esi              ; r13d = fd

    mov     rdi, [r12 + ASMCTX_arena]
    mov     rsi, 3 * ELF64_PHDR_SIZE
    call    arena_alloc
    check_err
    mov     r14, rdx               ; r14 = buffer
    mov     rdi, r14
    mov     rsi, 3 * ELF64_PHDR_SIZE
    call    mem_zero
    mov     rbx, r14               ; rbx = next header

    ; headers + .text: R+X from the start of the file
    mov     dword [rbx + PHDR_type],   PT_LOAD
    mov     dword [rbx + PHDR_flags],  (PF_R | PF_X)
    mov     qword [rbx + PHDR_offset], 0
    mov     qword [rbx + PHDR_vaddr],  ELF_SA_BASE
    mov     qword [rbx + PHDR_paddr],  ELF_SA_BASE
    mov     rax, [rel elf_sa_text_end]
    mov     qword [rbx + PHDR_filesz], rax
    mov     qword [rbx + PHDR_memsz],  rax
    mov     qword [rbx + PHDR_align],  0x1000
    add     rbx, ELF64_PHDR_SIZE

    ; .rodata: R
    cmp     byte [rel elf_sa_has_ro], 0
    je      .no_ro
    mov     rax, [rel elf_sa_ro_off]
    mov     rcx, [rel elf_sa_ro_end]
    sub     rcx, rax
    mov     dword [rbx + PHDR_type],   PT_LOAD
    mov     dword [rbx + PHDR_flags],  PF_R
    mov     qword [rbx + PHDR_offset], rax
    add     rax, ELF_SA_BASE
    mov     qword [rbx + PHDR_vaddr],  rax
    mov     qword [rbx + PHDR_paddr],  rax
    mov     qword [rbx + PHDR_filesz], rcx
    mov     qword [rbx + PHDR_memsz],  rcx
    mov     qword [rbx + PHDR_align],  0x1000
    add     rbx, ELF64_PHDR_SIZE
.no_ro:

    ; .data + .bss: RW; only .data takes file bytes
    cmp     byte [rel elf_sa_has_rw], 0
    je      .no_rw
    mov     rax, [rel elf_sa_rw_off]
    mov     dword [rbx + PHDR_type],   PT_LOAD
    mov     dword [rbx + PHDR_flags],  (PF_R | PF_W)
    mov     qword [rbx + PHDR_offset], rax
    lea     rcx, [rax + ELF_SA_BASE]
    mov     qword [rbx + PHDR_vaddr],  rcx
    mov     qword [rbx + PHDR_paddr],  rcx
    mov     rcx, [rel elf_sa_rw_end]
    sub     rcx, rax
    mov     qword [rbx + PHDR_memsz],  rcx
    mov     rcx, [rel elf_sa_rw_file_end]  ; .data and the other writable
    sub     rcx, [rel elf_sa_rw_off]       ; progbits sections are the file part
    mov     qword [rbx + PHDR_filesz], rcx
    mov     qword [rbx + PHDR_align],  0x1000
    add     rbx, ELF64_PHDR_SIZE
.no_rw:

    mov     edi, r13d
    mov     rsi, r14
    mov     rdx, rbx
    sub     rdx, r14
    call    io_write
    check_err
    
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    xor     rax, rax
    jmp     .done
.error:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

; ============================================================================
; elf64_write_text_section
; ============================================================================
;
; Writes the assembled .text bytes to the output fd.
; Input  : r12 = AsmCtx, r13 = fd
; Output : rax = EXIT_OK or error
;
elf64_write_text_section:
    prologue

    ; Get .text section from AsmCtx section array
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    check_err
    mov     r10, rdx               ; r10 = SECTION*

    mov     edi, r13d              ; fd
    mov     rsi, [r10 + SECTION_data]
    mov     rdx, [r10 + SECTION_size]
    call    io_write
    check_err

    xor     rax, rax
    jmp     .done
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

; ============================================================================
; elf64_write_data_section
; ============================================================================
elf64_write_data_section:
    prologue

    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    check_err
    mov     r10, rdx

    mov     edi, r13d
    mov     rsi, [r10 + SECTION_data]
    mov     rdx, [r10 + SECTION_size]
    call    io_write
    check_err

    xor     rax, rax
    jmp     .done
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

; ============================================================================
; elf64_write_rodata_section
; ============================================================================
elf64_write_rodata_section:
    prologue

    mov     rdi, r12
    mov     rsi, SEC_RODATA
    call    asmctx_get_section
    check_err
    mov     r10, rdx

    mov     edi, r13d
    mov     rsi, [r10 + SECTION_data]
    mov     rdx, [r10 + SECTION_size]
    call    io_write
    check_err

    xor     rax, rax
    jmp     .done
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

; ============================================================================
; elf64_prepare_strtab
; ============================================================================
elf64_prepare_strtab:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     r12, rdi               ; AsmCtx
    mov     rbx, [r12 + ASMCTX_symtab]
    
    ; Start at index 1 (0 is null byte)
    mov     r15, 1
    xor     r14, r14               ; i = 0
    
.outer_loop:
    cmp     r14d, [r12 + ASMCTX_symcount]
    jge     .done
    
    mov     r13, r14
    imul    r13, SYMBOL_SIZE
    add     r13, rbx                       ; r13 = SYMBOL*
    mov     rsi, [r13 + SYMBOL_name]
    test    rsi, rsi
    jz      .next_outer

    ; Symbols that never reach .symtab need no name in .strtab either
    mov     r8, r13
    call    elf64_symbol_is_emitted
    test    rax, rax
    jz      .next_outer

    ; Check if this string appeared before index r14
    xor     rcx, rcx               ; j = 0
.inner_loop:
    cmp     ecx, r14d
    jge     .is_unique

    mov     rdi, rcx
    imul    rdi, SYMBOL_SIZE
    add     rdi, rbx                       ; rdi = SYMBOL*
    mov     rax, [rdi + SYMBOL_name]
    test    rax, rax
    jz      .next_inner

    ; Only compare against symbols that were themselves assigned a name index
    mov     r8, rdi
    push    rsi
    push    rcx
    call    elf64_symbol_is_emitted
    pop     rcx
    pop     rsi
    test    rax, rax
    jz      .next_inner
    mov     rax, [r8 + SYMBOL_name]        ; reload: the check above used RAX

    ; Compare names
    push    rsi
    push    rcx
    mov     rdi, rax
    extern  str_cmp
    call    str_cmp
    pop     rcx
    pop     rsi
    
    test    rax, rax
    jnz     .next_inner
    
    ; Found duplicate! Reuse index
    mov     rax, rcx
    imul    rax, SYMBOL_SIZE
    mov     eax, [rbx + rax + SYMBOL_name_idx]
    mov     [r13 + SYMBOL_name_idx], eax
    jmp     .next_outer

.next_inner:
    inc     ecx
    jmp     .inner_loop

.is_unique:
    ; Store current offset
    mov     [r13 + SYMBOL_name_idx], r15d
    
    ; Advance offset
    mov     rdi, rsi
    extern  str_len
    call    str_len
    add     r15, rax
    inc     r15
    
    mov     rax, 0xFFFFFFFF
    IF r15, g, rax
        mov rax, EXIT_ENCODE_FAIL
        jmp .error_bounds
        ENDIF
    
.next_outer:
    inc     r14
    jmp     .outer_loop
    
.done:
    xor     rax, rax
    jmp     .epilogue

.error_bounds:
    ; Error code already in rax

.epilogue:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ============================================================================
; elf64_write_symtab
; ============================================================================
;
; Writes the ELF64 symbol table (.symtab).
; Each utasm SYMBOL maps to one Sym64 entry (24 bytes).
; Input  : r12 = AsmCtx, r13 = fd
;
;*
; * [elf64_symbol_is_emitted]
; * Purpose: Decide whether a symbol belongs in .symtab at all.
; *   Preprocessor constants, macros and struct definitions are assembly-time
; *   values, not addresses. NASM does not emit them, nothing can relocate
; *   against them, and emitting them made objects several times larger than
; *   they need to be. Anything exported is kept regardless of kind.
; * Input:
; *   R8 = SYMBOL*
; * Output:
; *   RAX = 1 to emit, 0 to skip.  Clobbers RAX only.
; ;
elf64_symbol_is_emitted:
    cmp     byte [r8 + SYMBOL_vis], VIS_LOCAL
    jne     .emit                  ; exported: always visible to the linker
    movzx   eax, byte [r8 + SYMBOL_kind]
    cmp     al, SYM_CONSTANT
    je      .skip
    cmp     al, SYM_MACRO
    je      .skip
    cmp     al, SYM_STRUCT
    je      .skip
    cmp     al, SYM_STRUCT_FIELD
    je      .skip
    ; the hidden labels "$" makes ("L@here.N", parser_pos_label): NASM's
    ; "$" leaves no symbol, and relocations use the section's symbol
    mov     rax, [r8 + SYMBOL_name]
    test    rax, rax
    jz      .emit
    cmp     dword [rax], 'L@he'
    jne     .emit
    cmp     word [rax + 4], 're'
    jne     .emit
    cmp     byte [rax + 6], '.'
    je      .skip
.emit:
    mov     rax, 1
    ret
.skip:
    xor     rax, rax
    ret

elf64_write_symtab:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi               ; r12 = AsmCtx
    mov     r13d, esi              ; r13d = fd
    
    sub     rsp, ELF64_SYM_SIZE    ; scratch Sym64

    ; ---- 1. Null Symbol ----
    mov     rdi, rsp
    mov     rsi, ELF64_SYM_SIZE
    call    mem_zero
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, ELF64_SYM_SIZE
    call    io_write
    check_err

    ; ---- 1b. A section symbol per section (local, STT_SECTION, no
    ;      name), as NASM writes them: symbol i is section i, and the
    ;      relocations against local labels use them ----
    xor     r14d, r14d
.secsym:
    cmp     r14w, [r12 + ASMCTX_seccount]
    jae     .secsym_done
    mov     rdi, rsp
    mov     rsi, ELF64_SYM_SIZE
    call    mem_zero
    mov     byte [rsp + SYM64_INFO], STT_SECTION
    lea     eax, [r14 + 1]
    mov     [rsp + SYM64_SHNDX], ax
    xor     ecx, ecx
    cmp     byte [rel elf_sa_on], 0
    je      .secsym_value
    mov     rax, [r12 + ASMCTX_sections]
    mov     rax, [rax + r14 * 8]
    mov     rcx, [rax + SECTION_addr]
.secsym_value:
    mov     [rsp + SYM64_VALUE], rcx
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, ELF64_SYM_SIZE
    call    io_write
    check_err
    inc     r14d
    jmp     .secsym
.secsym_done:

    ; ---- 2. Pass 1: Local Symbols ----
    movzx   r11d, word [r12 + ASMCTX_seccount]
    inc     r11                    ; after the null and the section symbols
    xor     r14, r14               ; internal loop index
    mov     r15, [r12 + ASMCTX_symtab]
    mov     ebx, [r12 + ASMCTX_symcount]
.local_loop:
    cmp     r14d, ebx
    jge     .global_pass
    
    mov     r10, r14
    imul    r10, SYMBOL_SIZE
    add     r10, r15                       ; r10 = SYMBOL*
    mov     r8, r10
    call    elf64_symbol_is_emitted
    test    rax, rax
    jz      .next_local
    IF byte [r10 + SYMBOL_vis], e, VIS_LOCAL
        mov     [r10 + SYMBOL_elf_idx], r11d
        call    .write_one_sym
        check_err
        inc     r11
        ENDIF
.next_local:
    inc     r14
    jmp     .local_loop

    ; ---- 3. Pass 2: Global/Weak Symbols ----
.global_pass:
    xor     r14, r14
.global_loop:
    cmp     r14d, ebx
    jge     .ok
    
    mov     r10, r14
    imul    r10, SYMBOL_SIZE
    add     r10, r15                       ; r10 = SYMBOL*
    mov     r8, r10
    call    elf64_symbol_is_emitted
    test    rax, rax
    jz      .next_global
    IF byte [r10 + SYMBOL_vis], ne, VIS_LOCAL
        mov     [r10 + SYMBOL_elf_idx], r11d
        call    .write_one_sym
        check_err
        inc     r11
        ENDIF
.next_global:
    inc     r14
    jmp     .global_loop

.ok:
    ; Both loops can fall out here with RAX still holding a predicate result,
    ; so the success code has to be set explicitly.
    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    add     rsp, ELF64_SYM_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; Helper: writes SYMBOL at R10 to FD R13D using scratch RSP
.write_one_sym:
    push    rdi
    push    rsi
    push    rdx
    push    rcx                    ; io_write clobbers rcx/r11 (syscall)
    push    r11                    ; r11 = caller's ELF symbol index

    mov     rdi, rsp
    add     rdi, 48                ; back to scratch (40 pushed + 8 return addr)
    mov     rsi, ELF64_SYM_SIZE
    call    mem_zero

    ; st_name
    mov     eax, [r10 + SYMBOL_name_idx]
    mov     [rsp + 48 + SYM64_NAME], eax
    
    ; st_info: (bind << 4)
    ; (kind == LABEL ? FUNC : OBJECT)
    movzx   eax, byte [r10 + SYMBOL_vis]   ; VIS_LOCAL=0, VIS_GLOBAL=1, VIS_WEAK=2
    shl     al, 4
    ; the type the source declared ("global f:function"), STT_NOTYPE
    ; otherwise, as NASM
    or      al, [r10 + SYMBOL_etype]
    mov     [rsp + 48 + SYM64_INFO], al

    ; st_other: the declared visibility (hidden, protected, ...)
    mov     al, [r10 + SYMBOL_eother]
    mov     [rsp + 48 + SYM64_OTHER], al
    
    ; st_shndx
    movzx   eax, word [r10 + SYMBOL_section]
    mov     [rsp + 48 + SYM64_SHNDX], ax
    
    ; st_value (an address in an executable: add the section's)
    mov     rax, [r10 + SYMBOL_value]
    cmp     byte [rel elf_sa_on], 0
    je      .sv_put
    movzx   ecx, word [r10 + SYMBOL_section]
    test    ecx, ecx
    jz      .sv_put                        ; undefined
    cmp     ecx, 0xFF00
    jae     .sv_put                        ; SHN_ABS and other reserved indices
    mov     rdx, [rel elf_sa_ctx]
    mov     rdx, [rdx + ASMCTX_sections]
    dec     ecx
    mov     rdx, [rdx + rcx*8]
    test    rdx, rdx
    jz      .sv_put
    add     rax, [rdx + SECTION_addr]
.sv_put:
    mov     [rsp + 48 + SYM64_VALUE], rax
    
    ; st_size
    mov     rax, [r10 + SYMBOL_size]
    mov     [rsp + 48 + SYM64_SIZE], rax
    
    mov     edi, r13d
    lea     rsi, [rsp + 48]
    mov     rdx, ELF64_SYM_SIZE
    call    io_write
    
    pop     r11
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret

.write_one_sym_done:
    add     rsp, ELF64_SYM_SIZE
    xor     rax, rax
    pop     r15
    pop     r14
    pop     rbx
    epilogue

; ============================================================================
; elf64_write_strtab
; ============================================================================
;
; Writes the .strtab section â€” a sequence of null-terminated symbol names.
; The null symbol at index 0 is the first byte (\0).
;
elf64_write_strtab:
    prologue
    push    rbx
    push    r14
    push    r15

    ; Start at offset 1 (0 is null)
    mov     r15, 1

    ; Write leading null byte
    sub     rsp, 8
    mov     byte [rsp], 0
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 1
    call    io_write
    add     rsp, 8
    check_err

    ; Walk symbols and write each name
    mov     rbx, [r12 + ASMCTX_symtab]
    mov     r14d, [r12 + ASMCTX_symcount]
    xor     rcx, rcx

.loop:
    cmp     ecx, r14d
    jge     .done

    mov     rdi, rcx
    imul    rdi, SYMBOL_SIZE
    add     rdi, rbx                       ; rdi = SYMBOL*
    mov     eax, [rdi + SYMBOL_name_idx]
    
    ; Only write if this is the first occurrence (idx == r15)
    IF eax, e, r15d
        mov     rsi, [rdi + SYMBOL_name]
        push    rcx                    ; io_write clobbers rcx (syscall)
        mov     rdi, rsi
        call    str_len
        mov     rdx, rax
        inc     rdx

        mov     edi, r13d
        call    io_write
        pop     rcx
        check_err

        add     r15, rdx
        ENDIF

    inc     ecx
    jmp     .loop

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    pop     r15
    pop     r14
    pop     rbx
    epilogue

;*
; * [elf64_write_groups]
; * Purpose: Emits SHT_GROUP data for each unique section group.
; ;
elf64_write_groups:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     r12, rdi               ; AsmCtx
    mov     r13d, esi              ; fd
    
    ; We need to iterate over UNIQUE groups.
    ; A group is unique if its signature symbol hasn't been processed yet.
    ; We'll use a temporary array on the stack to track processed signatures.
    movzx   eax, word [r12 + ASMCTX_seccount]
    shl     rax, 3                 ; 8 bytes per pointer
    sub     rsp, rax
    mov     r14, rsp               ; r14 = processed_sigs array
    
    mov     rdi, r14
    mov     rsi, rax
    call    mem_zero
    
    xor     r15, r15               ; n_processed = 0
    
    xor     rbx, rbx               ; i = 0
.outer_loop:
    cmp     bx, [r12 + ASMCTX_seccount]
    jge     .success
    
    mov     rax, [r12 + ASMCTX_sections]
    mov     r10, [rax + rbx * 8]   ; r10 = SECTION*
    
    test    word [r10 + SECTION_flags], SHF_GROUP
    jz      .next_outer
    
    mov     r11, [r10 + SECTION_group_sig]
    test    r11, r11
    jz      .next_outer
    
    ; Check if r11 is in processed_sigs
    xor     rcx, rcx
.sig_check:
    cmp     rcx, r15
    jge     .new_group
    cmp     [r14 + rcx * 8], r11
    je      .next_outer
    inc     rcx
    jmp     .sig_check
    
.new_group:
    ; Mark as processed
    mov     [r14 + r15 * 8], r11
    inc     r15
    
    ; Emit group data: [flags, idx1, idx2, ...]
    ; 1. GRP_COMDAT flag (always first word)
    sub     rsp, 4
    mov     eax, [r10 + SECTION_group_flags]
    mov     [rsp], eax
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 4
    call    io_write
    add     rsp, 4
    check_err
    
    ; 2. Member section indices
    xor     rcx, rcx               ; j = 0
.member_loop:
    cmp     cx, [r12 + ASMCTX_seccount]
    jge     .next_outer
    
    mov     rax, [r12 + ASMCTX_sections]
    mov     r8, [rax + rcx * 8]    ; r8 = member SECTION*
    
    cmp     [r8 + SECTION_group_sig], r11
    jne     .next_member
    
    ; Member found! Index is j + 1 (0 is NULL)
    sub     rsp, 4
    lea     eax, [ecx + 1]
    mov     [rsp], eax
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 4
    call    io_write
    add     rsp, 4
    check_err
    
.next_member:
    inc     ecx
    jmp     .member_loop

.next_outer:
    inc     rbx
    jmp     .outer_loop

.success:
    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    movzx   ecx, word [r12 + ASMCTX_seccount]
    shl     rcx, 3
    add     rsp, rcx
    
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ============================================================================
; elf64_write_shstrtab
; ============================================================================
;
; Writes .shstrtab â€” section name string table.
; Fixed set of names for the standard sections we emit.
;
; The table itself is defined here rather than at the end of the file: the
; size below is a difference of two labels, and a difference of two *forward*
; references cannot be resolved in a single pass.
[SECTION .rodata]
shstrtab_data:
    db 0                ; [0]  null (index 0 = unnamed)
    db ".text", 0       ; [1]
    db ".data", 0       ; [7]
    db ".bss",  0       ; [13]
    db ".symtab", 0     ; [18]
    db ".strtab", 0     ; [26]
    db ".shstrtab", 0   ; [34]
    db ".rela.text", 0  ; [44]
    db ".group", 0      ; [55]
    db ".rodata", 0     ; [62]
    db ".rela.data", 0  ; [70]
    db ".rela.rodata", 0; [81]
shstrtab_end:
str_rela_prefix: db ".rela"

[SECTION .text]
elf64_write_shstrtab:
    prologue

    mov     edi, r13d

    ; Write the whole shstrtab as one blob
    lea     rsi, [shstrtab_data]
    mov     rdx, shstrtab_end - shstrtab_data
    call    io_write
    check_err

    ; then ".rela<name>" for each section with another name: the section's
    ; own name is the tail of that string (elf64_custom_rela_off)
    push    rbx
    push    r14
    xor     ebx, ebx
.custom:
    cmp     bx, [r12 + ASMCTX_seccount]
    jae     .custom_done
    mov     rax, [r12 + ASMCTX_sections]
    mov     r14, [rax + rbx * 8]
    inc     ebx
    cmp     byte [r14 + SECTION_type], SEC_CUSTOM
    jne     .custom
    mov     edi, r13d
    lea     rsi, [rel str_rela_prefix]
    mov     edx, 5
    call    io_write
    test    rax, rax
    jnz     .custom_error
    mov     rdi, [r14 + SECTION_name]
    call    str_len
    lea     rdx, [rax + 1]                 ; with its NUL
    mov     edi, r13d
    mov     rsi, [r14 + SECTION_name]
    call    io_write
    test    rax, rax
    jnz     .custom_error
    jmp     .custom
.custom_error:
    pop     r14
    pop     rbx
    jmp     .error
.custom_done:
    pop     r14
    pop     rbx

    xor     rax, rax
    jmp     .done
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

;
; elf64_custom_rela_off
; Offset in .shstrtab of ".rela<name>" for a section with a name outside the
; fixed table; the name itself is at that offset + 5.
;
; Input    : rsi = SECTION* (SEC_CUSTOM)
; Output   : eax = offset
; Clobbers : rcx, rdx, rdi, r8, r9
;
elf64_custom_rela_off:
    mov     r8, [rel elf_sa_ctx]
    mov     r9, [r8 + ASMCTX_sections]
    mov     eax, shstrtab_end - shstrtab_data
    xor     ecx, ecx
.next:
    cmp     cx, [r8 + ASMCTX_seccount]
    jae     .ret
    mov     rdx, [r9 + rcx * 8]
    cmp     rdx, rsi
    je      .ret
    inc     ecx
    cmp     byte [rdx + SECTION_type], SEC_CUSTOM
    jne     .next
    mov     rdi, [rdx + SECTION_name]
    add     eax, 5                         ; ".rela"
.len:
    inc     eax                            ; each byte, the NUL included
    cmp     byte [rdi], 0
    lea     rdi, [rdi + 1]
    jne     .len
    jmp     .next
.ret:
    ret

; ============================================================================
; elf64_relocs_in_section
; ============================================================================
;
; Counts the relocations recorded against one section. Each RELOC stores the
; section it lives in, so relocations can be grouped into a .rela.<name>
; section per target - a .data relocation written into .rela.text would be
; applied to .text by the linker.
;
; Input  : rdi = AsmCtx, rsi = SECTION*
; Output : rax = count
; Clobbers: rcx, rdx, r8, r9
;
elf64_relocs_in_section:
    xor     rax, rax
    test    rsi, rsi
    jz      .done
    mov     r8, [rdi + ASMCTX_relocs]
    test    r8, r8
    jz      .done
    mov     r9d, [rdi + ASMCTX_nrelocs]
    xor     rcx, rcx
.loop:
    cmp     ecx, r9d
    jge     .done
    mov     rdx, rcx
    imul    rdx, RELOC_SIZE
    add     rdx, r8
    cmp     [rdx + RELOC_section], rsi
    jne     .next
    inc     rax
.next:
    inc     ecx
    jmp     .loop
.done:
    ret

; ============================================================================
; elf64_count_rela_sections
; ============================================================================
;
; How many .rela.<name> sections the object will carry: one per section that
; has at least one relocation recorded against it.
;
; Input  : rdi = AsmCtx
; Output : rax = count
;
elf64_count_rela_sections:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi               ; rbx = AsmCtx
    xor     r14, r14               ; r14 = count
    xor     r13d, r13d             ; r13 = section index
.loop:
    cmp     r13w, [rbx + ASMCTX_seccount]
    jge     .done
    mov     rax, [rbx + ASMCTX_sections]
    mov     r12, [rax + r13 * 8]
    mov     rdi, rbx
    mov     rsi, r12
    call    elf64_relocs_in_section
    test    rax, rax
    jz      .next
    inc     r14
.next:
    inc     r13d
    jmp     .loop
.done:
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ============================================================================
; elf64_rela_name_for
; ============================================================================
;
; Offset in .shstrtab of the ".rela.<name>" string for a section.
;
; Input  : rsi = SECTION*
; Output : eax = shstrtab offset
;
elf64_rela_name_for:
    movzx   eax, byte [rsi + SECTION_type]
    cmp     al, SEC_CUSTOM
    je      elf64_custom_rela_off          ; ".rela<name>"
    cmp     al, SEC_DATA
    je      .data
    cmp     al, SEC_RODATA
    je      .rodata
    mov     eax, 44                ; ".rela.text"
    ret
.data:
    mov     eax, 70                ; ".rela.data"
    ret
.rodata:
    mov     eax, 81                ; ".rela.rodata"
    ret

; ============================================================================
; elf64_write_rela
; ============================================================================
;
; Writes the relocation entries belonging to one section, as the body of that
; section's .rela.<name>. Walks the RELOC table stored in AsmCtx and skips
; every entry recorded against a different section.
;
; Input  : r12 = AsmCtx, r13d = fd, rdi = SECTION* to emit relocations for
;
elf64_write_rela:
    prologue
    push    rbx
    push    r14
    push    r15

    ; scratch Rela64, plus a slot for the target section: rbx/r12/r13/r14/r15
    ; are all already spoken for here and rbp belongs to prologue/epilogue.
    sub     rsp, ELF64_RELA_SIZE + 16
    mov     [rsp + ELF64_RELA_SIZE], rdi   ; target SECTION*

    mov     rbx, [r12 + ASMCTX_relocs]
    mov     r14d, [r12 + ASMCTX_nrelocs]
    xor     rcx, rcx

.loop:
    cmp     ecx, r14d
    jge     .done

    mov     rdi, rcx
    imul    rdi, RELOC_SIZE
    add     rdi, rbx                       ; rdi = RELOC*

    ; Only the relocations belonging to this section
    mov     rax, [rsp + ELF64_RELA_SIZE]
    cmp     [rdi + RELOC_section], rax
    jne     .next

    ; r_offset
    mov     rax, [rdi + RELOC_offset]
    mov     qword [rsp + RELA_OFFSET], rax

    mov     r15, rdi               ; r15 = RELOC*
    
    ; r_info: (sym_index << 32)
    xor     r9d, r9d                       ; added to the addend
    ; against a section itself (debug info): that section's symbol, whose
    ; index is the section's
    test    byte [r15 + RELOC_flags], RELOC_FLAG_SECTION
    jz      .by_symbol
    mov     rsi, [r15 + RELOC_sym]
    mov     r8, [r12 + ASMCTX_sections]
    movzx   r10d, word [r12 + ASMCTX_seccount]
    xor     eax, eax
.find_sec:
    test    r10d, r10d
    jz      .sym_ready
    mov     rdx, [r8]
    cmp     [rdx + SECTION_name], rsi
    je      .found_sec
    add     r8, 8
    dec     r10d
    jmp     .find_sec
.found_sec:
    mov     eax, [rdx + SECTION_index]
    jmp     .sym_ready
.by_symbol:
    mov     rsi, [r15 + RELOC_sym]
    mov     rdi, r12               ; symbol_find takes the AsmCtx
    push    rcx                    ; loop index: the callee clobbers rcx
    call    symbol_find
    pop     rcx
    xor     r9d, r9d                       ; added to the addend
    IF rax, e, EXIT_OK
        mov     eax, [rdx + SYMBOL_elf_idx]
        ; a local label: against its section's symbol, its offset added
        ; to the addend, as NASM writes it (unless "wrt ..sym")
        test    byte [r15 + RELOC_flags], RELOC_FLAG_SYM
        jnz     .sym_ready
        cmp     byte [rdx + SYMBOL_vis], VIS_LOCAL
        jne     .sym_ready
        movzx   r8d, word [rdx + SYMBOL_section]
        test    r8d, r8d
        jz      .sym_ready
        cmp     r8d, 0xFF00
        jae     .sym_ready
        mov     eax, r8d
        mov     r9, [rdx + SYMBOL_value]
    ELSE
        xor     eax, eax
    ENDIF
.sym_ready:

    mov     r11, rax
    shl     r11, 32
    
    ; ---- FIX: ARCH-SPECIFIC RELOC TYPE ----
    mov     edx, [r15 + RELOC_type]
    or      r11, rdx
    mov     qword [rsp + RELA_INFO], r11

    ; r_addend
    mov     rax, [r15 + RELOC_addend]
    add     rax, r9
    mov     qword [rsp + RELA_ADDEND], rax

    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, ELF64_RELA_SIZE
    push    rcx                    ; io_write clobbers rcx (syscall)
    call    io_write
    pop     rcx
    check_err

.next:
    inc     ecx
    jmp     .loop

.error:
    mov     rax, EXIT_FILE_WRITE
    jmp     .exit
.done:
    xor     rax, rax
.exit:
    add     rsp, ELF64_RELA_SIZE + 16
    pop     r15
    pop     r14
    pop     rbx
    epilogue

; ============================================================================
; elf64_write_shdrs
; ============================================================================
;
; Writes the section header table (8 entries for a minimal object).
; Sections: [0] NULL, [1] .text, [2] .data, [3] .bss,
;            [4] .symtab, [5] .strtab, [6] .shstrtab, [7] .rela.text
;
global elf64_write_shdrs
elf64_write_shdrs:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     rbx, rdi               ; AsmCtx
    mov     r12, rsi               ; FD
    mov     r15, rdx               ; section_info table
    
    sub     rsp, ELF64_SHDR_SIZE   ; scratch shdr
    
    ; 1. NULL Section [0]
    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err
    
    ; 2. Iterate User Sections
    mov     r14, [rbx + ASMCTX_sections]
    movzx   r13d, word [rbx + ASMCTX_seccount]
    xor     ecx, ecx
    
.sec_loop:
    cmp     ecx, r13d
    jge     .sec_done
    
    mov     rsi, [r14 + rcx * 8]   ; rsi = SECTION*
    
    mov     rdi, rsp
    push    rcx
    push    rsi
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    pop     rsi
    pop     rcx
    
    ; Populate name index
    mov     rax, [rsi + SECTION_name]
    movzx   edx, byte [rax + 1]    ; skip '.'
    IF dl, e, 't'
        mov     dword [rsp + SHDR_NAME], 1  ; ".text"
    ELSEIF dl, e, 'd'
        mov     dword [rsp + SHDR_NAME], 7  ; ".data"
    ELSEIF dl, e, 'b'
        mov     dword [rsp + SHDR_NAME], 13 ; ".bss"
    ELSEIF dl, e, 'r'
        mov     dword [rsp + SHDR_NAME], 62 ; ".rodata"
    ENDIF
    cmp     byte [rsi + SECTION_type], SEC_CUSTOM
    jne     .named
    push    rcx
    push    rsi
    call    elf64_custom_rela_off
    pop     rsi
    pop     rcx
    add     eax, 5                         ; the name after ".rela"
    mov     dword [rsp + SHDR_NAME], eax
.named:
    
    mov     eax, [rsi + SECTION_elf_type]
    mov     dword [rsp + SHDR_TYPE], eax
    
    movzx   eax, word [rsi + SECTION_flags]
    mov     qword [rsp + SHDR_FLAGS], rax
    
    mov     rax, [rsi + SECTION_addr]
    mov     qword [rsp + SHDR_ADDR], rax
    
    ; Load offset/size from section_info table
    movzx   eax, word [rsi + SECTION_index]
    shl     rax, 4
    add     rax, r15
    
    mov     rdi, [rax]
    mov     qword [rsp + SHDR_OFFSET], rdi
    
    mov     rdi, [rax + 8]
    mov     qword [rsp + SHDR_SIZE], rdi
    
    mov     rax, [rsi + SECTION_align]
    test    rax, rax
    jz      .def_align
    mov     qword [rsp + SHDR_ADDRALIGN], rax
    jmp     .emit
.def_align:
    mov     qword [rsp + SHDR_ADDRALIGN], 1
    
.emit:
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    push    rcx                    ; io_write clobbers rcx (syscall)
    call    io_write
    pop     rcx
    check_err

    inc     ecx
    jmp     .sec_loop
    
.sec_done:
    ; 2.5 Iterate Groups (A57)
    movzx   eax, word [rbx + ASMCTX_seccount]
    shl     rax, 3
    sub     rsp, rax
    mov     r14, rsp               ; r14 = processed_sigs array
    mov     rdi, r14
    mov     rsi, rax
    call    mem_zero
    xor     r13, r13               ; n_processed = 0
    
    xor     rcx, rcx               ; i = 0
.group_loop:
    cmp     cx, [rbx + ASMCTX_seccount]
    jge     .groups_done
    
    mov     rax, [rbx + ASMCTX_sections]
    mov     r10, [rax + rcx * 8]   ; r10 = SECTION*
    test    word [r10 + SECTION_flags], SHF_GROUP
    jz      .next_group_header
    mov     r8, [r10 + SECTION_group_sig]
    test    r8, r8
    jz      .next_group_header
    
    ; De-duplicate
    xor     rdx, rdx
.sig_check_shdr:
    cmp     rdx, r13
    jge     .new_group_shdr
    cmp     [r14 + rdx * 8], r8
    je      .next_group_header
    inc     rdx
    jmp     .sig_check_shdr
    
.new_group_shdr:
    mov     [r14 + r13 * 8], r8
    inc     r13
    
    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    mov     dword [rsp + SHDR_NAME], 55    ; ".group"
    mov     dword [rsp + SHDR_TYPE], 17    ; SHT_GROUP
    mov     qword [rsp + SHDR_OFFSET], 0
    
    ; Info = symbol index of signature
    mov     eax, [r8 + SYMBOL_elf_idx]
    mov     dword [rsp + SHDR_INFO], eax
    
    ; Link = .symtab index
    movzx   eax, word [rbx + ASMCTX_seccount]
    add     eax, [rbx + ASMCTX_group_count]
    inc     eax                    ; NULL + User + Groups + SYMTAB
    mov     dword [rsp + SHDR_LINK], eax
    
    mov     qword [rsp + SHDR_ADDRALIGN], 4
    mov     qword [rsp + SHDR_ENTSIZE], 4
    
    ; Size = 4 * (1 + num_members)
    mov     r9, 4                  ; start with GRP_COMDAT word
    xor     rdx, rdx               ; j = 0
.count_members:
    cmp     dx, [rbx + ASMCTX_seccount]
    jge     .count_members_done
    mov     rax, [rbx + ASMCTX_sections]
    mov     rax, [rax + rdx * 8]
    cmp     [rax + SECTION_group_sig], r8
    jne     .next_count
    add     r9, 4
.next_count:
    inc     rdx
    jmp     .count_members
.count_members_done:
    
    mov     qword [rsp + SHDR_SIZE], r9
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err
    
.next_group_header:
    inc     rcx
    jmp     .group_loop
 
.groups_done:
    movzx   eax, word [rbx + ASMCTX_seccount]
    shl     rax, 3
    add     rsp, rax               ; Clean up processed_sigs


    ; 3. .symtab
    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    mov     dword [rsp + SHDR_NAME], 18    ; ".symtab"
    mov     dword [rsp + SHDR_TYPE], 2     ; SHT_SYMTAB
    mov     qword [rsp + SHDR_ENTSIZE], 24 ; sizeof(Elf64_Sym)
    
    ; Link = .strtab index
    movzx   eax, word [rbx + ASMCTX_seccount]
    add     eax, [rbx + ASMCTX_group_count]
    add     eax, 2                 ; NULL + User + Groups + SYMTAB + STRTAB
    mov     dword [rsp + SHDR_LINK], eax
    
    ; Info = first global symbol index
    movzx   r10d, word [rbx + ASMCTX_seccount]
    inc     r10                    ; the NULL symbol and the section symbols
    mov     rsi, [rbx + ASMCTX_symtab]
    mov     edi, [rbx + ASMCTX_symcount]
    xor     ecx, ecx
.count_local:
    cmp     ecx, edi
    jge     .count_done
    mov     rax, rcx
    imul    rax, SYMBOL_SIZE
    add     rax, rsi
    mov     r8, rax
    call    elf64_symbol_is_emitted
    test    rax, rax
    jz      .count_next
    IF byte [r8 + SYMBOL_vis], e, VIS_LOCAL
        inc     r10
    ENDIF
.count_next:
    inc     ecx
    jmp     .count_local
.count_done:
    mov     dword [rsp + SHDR_INFO], r10d
    
    ; Load offset/size from section_info table
    movzx   ecx, word [rbx + ASMCTX_seccount]
    add     ecx, [rbx + ASMCTX_group_count]
    inc     ecx                    ; ecx = seccount + group_count + 1
    
    mov     rax, rcx
    shl     rax, 4
    add     rax, r15
    mov     rdi, [rax]
    mov     qword [rsp + SHDR_OFFSET], rdi
    mov     rdi, [rax + 8]
    mov     qword [rsp + SHDR_SIZE], rdi
    
    mov     qword [rsp + SHDR_ADDRALIGN], 8
    
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err

    ; 4. .strtab
    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    mov     dword [rsp + SHDR_NAME], 26    ; ".strtab"
    mov     dword [rsp + SHDR_TYPE], 3     ; SHT_STRTAB
    
    movzx   ecx, word [rbx + ASMCTX_seccount]
    add     ecx, [rbx + ASMCTX_group_count]
    add     ecx, 2
    
    mov     rax, rcx
    shl     rax, 4
    add     rax, r15
    mov     rdi, [rax]
    mov     qword [rsp + SHDR_OFFSET], rdi
    mov     rdi, [rax + 8]
    mov     qword [rsp + SHDR_SIZE], rdi
    
    mov     qword [rsp + SHDR_ADDRALIGN], 1
    
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err

    ; 5. .shstrtab
    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero
    mov     dword [rsp + SHDR_NAME], 34    ; ".shstrtab"
    mov     dword [rsp + SHDR_TYPE], 3     ; SHT_STRTAB
    
    movzx   ecx, word [rbx + ASMCTX_seccount]
    add     ecx, [rbx + ASMCTX_group_count]
    add     ecx, 3
    
    mov     rax, rcx
    shl     rax, 4
    add     rax, r15
    mov     rdi, [rax]
    mov     qword [rsp + SHDR_OFFSET], rdi
    mov     rdi, [rax + 8]
    mov     qword [rsp + SHDR_SIZE], rdi
    
    mov     qword [rsp + SHDR_ADDRALIGN], 1
    
    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err
    
    ; 6. One .rela.<name> header per section that has relocations, in the
    ;    same section order the bodies were written in, so the indices match.
    ;    r14 = next rela section index, r13 = section iteration index.
    movzx   r14d, word [rbx + ASMCTX_seccount]
    add     r14d, [rbx + ASMCTX_group_count]
    add     r14d, 4                            ; first rela section index
    xor     r13d, r13d

.rela_hdr_loop:
    cmp     r13w, [rbx + ASMCTX_seccount]
    jge     .rela_hdr_done

    ; The section pointer is re-derived rather than parked in a register:
    ; rbx/r12/r15 are live and rbp belongs to prologue/epilogue.
    mov     rax, [rbx + ASMCTX_sections]
    mov     rsi, [rax + r13 * 8]               ; rsi = SECTION*

    mov     rdi, rbx
    call    elf64_relocs_in_section
    test    rax, rax
    jz      .rela_hdr_next

    mov     rdi, rsp
    mov     rsi, ELF64_SHDR_SIZE
    call    mem_zero

    mov     rax, [rbx + ASMCTX_sections]
    mov     rsi, [rax + r13 * 8]
    call    elf64_rela_name_for
    mov     dword [rsp + SHDR_NAME], eax
    mov     dword [rsp + SHDR_TYPE], 4         ; SHT_RELA
    mov     qword [rsp + SHDR_FLAGS], 0x40     ; SHF_INFO_LINK
    mov     qword [rsp + SHDR_ENTSIZE], 24     ; sizeof(Elf64_Rela)

    ; Link = .symtab index
    movzx   eax, word [rbx + ASMCTX_seccount]
    add     eax, [rbx + ASMCTX_group_count]
    inc     eax                                ; NULL + User + Groups + SYMTAB
    mov     dword [rsp + SHDR_LINK], eax

    ; Info = the section these relocations apply to
    mov     rax, [rbx + ASMCTX_sections]
    mov     rax, [rax + r13 * 8]
    movzx   eax, word [rax + SECTION_index]
    mov     dword [rsp + SHDR_INFO], eax

    mov     rax, r14
    shl     rax, 4
    add     rax, r15
    mov     rdi, [rax]
    mov     qword [rsp + SHDR_OFFSET], rdi
    mov     rdi, [rax + 8]
    mov     qword [rsp + SHDR_SIZE], rdi

    mov     qword [rsp + SHDR_ADDRALIGN], 8

    mov     edi, r12d
    mov     rsi, rsp
    mov     rdx, ELF64_SHDR_SIZE
    call    io_write
    check_err

    inc     r14d

.rela_hdr_next:
    inc     r13d
    jmp     .rela_hdr_loop

.rela_hdr_done:
    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    add     rsp, ELF64_SHDR_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [elf64_align_file]
; * Writes padding to FD until current offset is aligned to RSI.
; * Input:
; *   RDI: FD
; *   RSI: Alignment (Power of 2)
; ;
elf64_align_file:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; FD
    mov     r12, rsi               ; alignment
    
    ; 1. Get current offset
    mov     edi, ebx
    xor     rsi, rsi
    mov     rdx, 1                 ; SEEK_CUR
    extern  io_lseek
    call    io_lseek
    ; If seek fails (e.g. pipe), we can't align correctly for some sections
    ; but for now we assume seekable file for ELF emission.
    test    rax, rax
    js      .done
    mov     r13, rdx               ; current pos
    
    ; 2. Calculate padding
    mov     rax, r13
    mov     rcx, r12
    dec     rcx                    ; mask
    and     rax, rcx
    jz      .done                  ; already aligned
    
    sub     r12, rax               ; r12 = padding size
    
    ; 3. Write padding
.loop:
    test    r12, r12
    jz      .done
    
    mov     edi, ebx
    xor     esi, esi
    call    io_write_byte
    check_err
    
    dec     r12
    jmp     .loop
    
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

%define shstrtab_size (shstrtab_end - shstrtab_data)
