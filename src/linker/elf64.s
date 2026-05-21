;
; ============================================================================
; File        : src/linker/elf64.s
; Project     : utasm
; Description : ELF64 relocatable object file emitter (-f elf64).
;                Writes a standards-compliant ELF64 .o file consumable by
;                ld, lld, and any POSIX linker.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"
%include "include/elf.s"

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

    ; Allocate section info table (32 entries of {offset, size} = 512 bytes)
    sub     rsp, 512
    
    mov     rdi, rsp
    mov     rsi, 512
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
        call    elf64_write_phdrs
        check_err
        ENDIF

    ; ---- 3. Write .text section ----
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    movzx   ebx, word [rdx + SECTION_index] ; ebx = index
    
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

    ; ---- 4. Write .data section ----
    ; Ensure .data is aligned correctly in file (A88)
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    movzx   ebx, word [rdx + SECTION_index] ; ebx = index
    
    mov     rsi, [rdx + SECTION_align]
    IF rsi, e, 0
        mov rsi, 8
    ENDIF ; Default 8-byte
    mov     edi, r13d
    call    elf64_align_file
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

    ; Ensure .bss is aligned (A88)
    mov     rdi, r12
    mov     rsi, SEC_BSS
    call    asmctx_get_section
    IF rax, e, 0
        movzx   ebx, word [rdx + SECTION_index] ; ebx = index
        mov     rsi, [rdx + SECTION_align]
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
        mov     r11, [rdx + SECTION_size]
        mov     [rsp + rax + 8], r11        ; size
    ENDIF

    ; ---- 4.5 Write Section Groups (A57) ----
    call    elf64_write_groups
    check_err

    ; ---- 5. Write Metadata sections ----
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

    ; ---- Write .rela.text ----
    IF dword [r12 + ASMCTX_nrelocs], ne, 0
        lea     ebx, [r14d + 4]
        
        mov     edi, r13d
        xor     rsi, rsi
        mov     rdx, 1
        call    io_lseek
        mov     rax, rbx
        shl     rax, 4
        mov     [rsp + rax], rdx
        
        call    elf64_write_rela
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
    ENDIF

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
    add     rsp, 512
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
    
    mov     rdi, [r12 + ASMCTX_symtab]
    lea     rsi, [rel .str_start]
    extern  symbol_find
    call    symbol_find
    IF rax, e, EXIT_OK
        mov     r10, rdx ; SYMBOL*
        mov     rax, [r10 + SYMBOL_value]
        
        ; Add section base address
        movzx   r11, word [r10 + SYMBOL_section]
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
        mov     word  [r14 + EHDR_PHNUM], 2 ; For now: 1 Code + 1 Data
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
    IF dword [r12 + ASMCTX_nrelocs], ne, 0
        inc     eax                ; .rela.text
        ENDIF
    mov     word  [r14 + EHDR_SHNUM], ax
    
    ; .shstrtab index is 1 + seccount + group_count + 2 (symtab, strtab)
    movzx   ecx, word [r12 + ASMCTX_seccount]
    add     ecx, [r12 + ASMCTX_group_count]
    add     ecx, 3                 ; 0:NULL, 1..N:User, N+1:sym, N+2:str, N+3:shstr
    mov     word  [r14 + EHDR_SHSTRNDX], cx

    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

;*
; * [elf64_write_phdrs]
; ;
elf64_write_phdrs:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     r12, rdi               ; r12 = AsmCtx
    mov     r13d, esi              ; r13d = fd
    
    ; Allocate 112 bytes for 2 PHDRs
    mov     rdi, [r12 + ASMCTX_arena]
    mov     rsi, 112
    call    arena_alloc
    check_err
    mov     r14, rdx               ; r14 = buffer
    
    mov     rdi, r14
    mov     rsi, 112
    call    mem_zero
    
    ; 1. Calculate Code Offset: Immediately after Headers
    mov     rax, ELF64_EHDR_SIZE
    add     rax, 112               ; 2 PHDRs * 56 bytes
    mov     r15, rax               ; r15 = code_offset
    
    ; CODE Segment
    mov     dword [r14 + PHDR_type],   PT_LOAD
    mov     dword [r14 + PHDR_flags],  (PF_R | PF_X)
    mov     qword [r14 + PHDR_offset], r15
    mov     rax, [r12 + ASMCTX_entry_point]
    mov     qword [r14 + PHDR_vaddr],  rax
    mov     qword [r14 + PHDR_paddr],  rax
    
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    mov     rax, [rdx + SECTION_size]
    mov     qword [r14 + PHDR_filesz], rax
    mov     qword [r14 + PHDR_memsz],  rax
    mov     qword [r14 + PHDR_align],  0x1000
    
    ; 2. Calculate Data Offset: Align(Code_Offset + Code_Size, 4096)
    add     r15, rax               ; r15 = code_offset + code_size
    add     r15, 4095
    and     r15, -4096             ; r15 = data_offset (aligned)
    
    ; DATA Segment
    add     r14, 56
    mov     dword [r14 + PHDR_type],   PT_LOAD
    mov     dword [r14 + PHDR_flags],  (PF_R | PF_W)
    mov     qword [r14 + PHDR_offset], r15
    
    ; Virtual Address for data segment: Entry + (Data_Offset - Code_Offset)
    mov     rax, [r12 + ASMCTX_entry_point]
    mov     rcx, r15               ; data_offset
    sub     rcx, [r14 - 56 + PHDR_offset] ; code_offset
    add     rax, rcx
    
    mov     qword [r14 + PHDR_vaddr],  rax
    mov     qword [r14 + PHDR_paddr],  rax
    
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    mov     rax, [rdx + SECTION_size]
    mov     qword [r14 + PHDR_filesz], rax
    
    ; memsz = data_size + bss_size
    mov     r8, rax                ; r8 = data_size
    
    mov     rdi, r12
    mov     rsi, SEC_BSS
    call    asmctx_get_section
    mov     rax, [rdx + SECTION_size]
    add     r8, rax                ; r8 = data_size + bss_size
    
    mov     qword [r14 + PHDR_memsz],  r8
    mov     qword [r14 + PHDR_align],  0x1000
    
    ; Write buffer
    sub     r14, 56
    mov     edi, r13d
    mov     rsi, r14
    mov     rdx, 112
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

    ; ---- 2. Pass 1: Local Symbols ----
    mov     r11, 1                 ; ELF symbol index (0 is Null)
    xor     r14, r14               ; internal loop index
    mov     r15, [r12 + ASMCTX_symtab]
    mov     ebx, [r12 + ASMCTX_symcount]
.local_loop:
    cmp     r14d, ebx
    jge     .global_pass
    
    mov     r10, r14
    imul    r10, SYMBOL_SIZE
    add     r10, r15                       ; r10 = SYMBOL*
    IF byte [r10 + SYMBOL_vis], e, VIS_LOCAL
        mov     [r10 + SYMBOL_elf_idx], r11d
        call    .write_one_sym
        check_err
        inc     r11
        ENDIF
    inc     r14
    jmp     .local_loop

    ; ---- 3. Pass 2: Global/Weak Symbols ----
.global_pass:
    xor     r14, r14
.global_loop:
    cmp     r14d, ebx
    jge     .done
    
    mov     r10, r14
    imul    r10, SYMBOL_SIZE
    add     r10, r15                       ; r10 = SYMBOL*
    IF byte [r10 + SYMBOL_vis], ne, VIS_LOCAL
        mov     [r10 + SYMBOL_elf_idx], r11d
        call    .write_one_sym
        check_err
        inc     r11
        ENDIF
    inc     r14
    jmp     .global_loop

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
    
    mov     rdi, rsp
    add     rdi, 24                ; back to scratch
    mov     rsi, ELF64_SYM_SIZE
    call    mem_zero
    
    ; st_name
    mov     eax, [r10 + SYMBOL_name_idx]
    mov     [rsp + 24 + SYM64_NAME], eax
    
    ; st_info: (bind << 4)
    ; (kind == LABEL ? FUNC : OBJECT)
    movzx   eax, byte [r10 + SYMBOL_vis]   ; VIS_LOCAL=0, VIS_GLOBAL=1, VIS_WEAK=2
    shl     al, 4
    mov     cl, [r10 + SYMBOL_kind]
    IF cl, e, SYM_LABEL
        or      al, STT_FUNC
        ELSE
        or      al, STT_OBJECT
        ENDIF
    mov     [rsp + 24 + SYM64_INFO], al
    
    ; st_other: STV_DEFAULT (0)
    mov     byte [rsp + 24 + SYM64_OTHER], 0
    
    ; st_shndx
    movzx   eax, word [r10 + SYMBOL_section]
    mov     [rsp + 24 + SYM64_SHNDX], ax
    
    ; st_value
    mov     rax, [r10 + SYMBOL_value]
    mov     [rsp + 24 + SYM64_VALUE], rax
    
    ; st_size
    mov     rax, [r10 + SYMBOL_size]
    mov     [rsp + 24 + SYM64_SIZE], rax
    
    mov     edi, r13d
    lea     rsi, [rsp + 24]
    mov     rdx, ELF64_SYM_SIZE
    call    io_write
    
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
        push    rax
        mov     rdi, rsi
        call    str_len
        mov     rdx, rax
        inc     rdx
        
        mov     edi, r13d
        call    io_write
        check_err
        pop     rax
        
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
    jge     .done
    
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

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    movzx   eax, word [r12 + ASMCTX_seccount]
    shl     rax, 3
    add     rsp, rax
    
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
elf64_write_shstrtab:
    prologue

    mov     edi, r13d

    ; Write the whole shstrtab as one blob
    lea     rsi, [shstrtab_data]
    mov     rdx, shstrtab_end - shstrtab_data
    call    io_write
    check_err

    xor     rax, rax
    jmp     .done
.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    epilogue

; ============================================================================
; elf64_write_rela
; ============================================================================
;
; Writes .rela.text â€” relocation entries for unresolved symbols in .text.
; Walks the RELOC table stored in AsmCtx.
;
elf64_write_rela:
    prologue
    push    rbx
    push    r14
    push    r15

    sub     rsp, ELF64_RELA_SIZE   ; scratch Rela64 on stack

    mov     rbx, [r12 + ASMCTX_relocs]
    mov     r14d, [r12 + ASMCTX_nrelocs]
    xor     rcx, rcx

.loop:
    cmp     ecx, r14d
    jge     .done

    mov     rdi, rcx
    imul    rdi, RELOC_SIZE
    add     rdi, rbx                       ; rdi = RELOC*

    ; r_offset
    mov     rax, [rdi + RELOC_offset]
    mov     qword [rsp + RELA_OFFSET], rax

    mov     r15, rdi               ; r15 = RELOC*
    
    ; r_info: (sym_index << 32)
    mov     rsi, [r15 + RELOC_sym]
    mov     rdi, [r12 + ASMCTX_symtab]
    call    symbol_find
    IF rax, e, EXIT_OK
        mov     eax, [rdx + SYMBOL_elf_idx]
    ELSE
        xor     eax, eax
    ENDIF
    
    mov     r11, rax
    shl     r11, 32
    
    ; ---- FIX: ARCH-SPECIFIC RELOC TYPE ----
    mov     edx, [r15 + RELOC_type]
    or      r11, rdx
    mov     qword [rsp + RELA_INFO], r11

    ; r_addend
    mov     rax, [r15 + RELOC_addend]
    mov     qword [rsp + RELA_ADDEND], rax

    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, ELF64_RELA_SIZE
    call    io_write
    check_err

    inc     ecx
    jmp     .loop

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    add     rsp, ELF64_RELA_SIZE
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
    ENDIF
    
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
    call    io_write
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
    mov     r10, 1                 ; 1 for NULL symbol
    mov     rsi, [rbx + ASMCTX_symtab]
    mov     edi, [rbx + ASMCTX_symcount]
    xor     ecx, ecx
.count_local:
    cmp     ecx, edi
    jge     .count_done
    mov     rax, rcx
    imul    rax, SYMBOL_SIZE
    add     rax, rsi
    IF byte [rax + SYMBOL_vis], e, VIS_LOCAL
        inc     r10
    ENDIF
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
    
    ; 6. .rela.text (if nrelocs != 0)
    IF dword [rbx + ASMCTX_nrelocs], ne, 0
        mov     rdi, rsp
        mov     rsi, ELF64_SHDR_SIZE
        call    mem_zero
        mov     dword [rsp + SHDR_NAME], 44    ; ".rela.text"
        mov     dword [rsp + SHDR_TYPE], 4     ; SHT_RELA
        mov     qword [rsp + SHDR_FLAGS], 0x40 ; SHF_INFO_LINK
        mov     qword [rsp + SHDR_ENTSIZE], 24 ; sizeof(Elf64_Rela)
        
        ; Link = .symtab index
        movzx   eax, word [rbx + ASMCTX_seccount]
        add     eax, [rbx + ASMCTX_group_count]
        inc     eax                            ; NULL + User + Groups + SYMTAB
        mov     dword [rsp + SHDR_LINK], eax
        
        ; Info = .text index
        push    rcx
        push    rsi
        mov     rdi, rbx
        mov     rsi, SEC_TEXT
        call    asmctx_get_section
        movzx   eax, word [rdx + SECTION_index] ; eax = index of .text
        pop     rsi
        pop     rcx
        mov     dword [rsp + SHDR_INFO], eax
        
        movzx   ecx, word [rbx + ASMCTX_seccount]
        add     ecx, [rbx + ASMCTX_group_count]
        add     ecx, 4                         ; index of .rela.text
        
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
    ENDIF
    
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

; ============================================================================
; Read-only data: .shstrtab content
; ============================================================================
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
shstrtab_end:
%define shstrtab_size (shstrtab_end - shstrtab_data)
