;
; ============================================================================
; File        : backend/output/elf/elf32.s
; Project     : utasm
; Description : -f elf32: the ELF64 object rewritten as an i386 ELF32 one.
;
;   The object is written as ELF64 first (sections, symbols, groups and
;   custom sections all come from the one writer), then rewritten:
;
;   - the header, the section headers and the symbols take their 32-bit
;     layouts (Elf32_Ehdr 52 bytes, Elf32_Shdr 40, Elf32_Sym 16), EM_386
;   - every .rela.X becomes .rel.X: Elf32_Rel entries (offset, symbol << 8 |
;     type) with the i386 types, and each addend written into the bytes it
;     relocates, as i386 objects carry them (NASM's -f elf32 does the same)
;
;     R_X86_64_32 / 32S -> R_386_32      R_X86_64_PC32 -> R_386_PC32
;     R_X86_64_PLT32    -> R_386_PLT32   R_X86_64_GOT32 -> R_386_GOT32
;     R_X86_64_16 / PC16 / 8 / PC8 -> R_386_16 / PC16 / 8 / PC8
;
;   A relocation that has no 32-bit form (R_X86_64_64: "dq label") is an
;   error.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  io_open
extern  io_close
extern  io_write
extern  io_file_size
extern  io_mmap
extern  arena_alloc
extern  mem_zero
extern  global_ctx

%define MAX_SECS        256

[SECTION .bss]
alignb 8
global elf32_enabled
e32_in:         resq 1              ; the ELF64 image
e32_shoff:      resq 1
e32_shnum:      resq 1
e32_data:       resq MAX_SECS       ; each section's new contents
e32_size:       resq MAX_SECS       ; ... and size
e32_off:        resq MAX_SECS       ; ... and offset in the new file
e32_name:       resq MAX_SECS       ; ... and name offset in .shstrtab
e32_strtab:     resq 1              ; the new .shstrtab
e32_strlen:     resq 1
e32_out:        resq 1              ; the new file
e32_outlen:     resq 1
elf32_enabled:  resb 1              ; -f elf32

[SECTION .text]

; shdr64 rcx -> rax = its address in the input
%macro SHDR64 1
    mov     rax, %1
    shl     rax, 6
    add     rax, [rel e32_shoff]
    add     rax, [rel e32_in]
%endmacro

;*
; * [elf32_convert]
; * Purpose: Rewrite the ELF64 object at path RDI as ELF32.
; * Input  : RDI = output path
; * Output : RAX = EXIT_OK or an error
; ;
global elf32_convert
elf32_convert:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15, rdi

    ; ---- read the ELF64 object ----
    xor     esi, esi
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     r12, rdx                       ; fd
    mov     rdi, r12
    call    io_file_size
    test    rax, rax
    jnz     .close_ret
    mov     r13, rdx                       ; size
    xor     edi, edi
    mov     rsi, r13
    mov     edx, PROT_READ
    mov     ecx, MAP_PRIVATE
    mov     r8, r12
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .close_ret
    mov     [rel e32_in], rdx
    mov     rdi, r12
    call    io_close

    mov     rbx, [rel e32_in]
    mov     rax, [rbx + 40]                ; e_shoff
    mov     [rel e32_shoff], rax
    movzx   eax, word [rbx + 60]           ; e_shnum
    mov     [rel e32_shnum], rax
    cmp     eax, MAX_SECS
    ja      .bad

    ; ---- the section names: .rela.X becomes .rel.X ----
    movzx   eax, word [rbx + 62]           ; e_shstrndx
    SHDR64  rax
    mov     r14, [rax + 24]                ; its offset
    add     r14, rbx                       ; r14 = the old names
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, [rax + 32]
    add     rsi, 16
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel e32_strtab], rdx
    mov     qword [rel e32_strlen], 1      ; "" at 0 (the arena is zeroed)
    xor     r12d, r12d
.name:
    cmp     r12, [rel e32_shnum]
    jae     .names_done
    SHDR64  r12
    mov     ecx, [rax]                     ; sh_name
    mov     edx, [rax + 4]                 ; sh_type
    lea     rsi, [r14 + rcx]               ; the old name
    mov     rdi, [rel e32_strtab]
    mov     r8, [rel e32_strlen]
    lea     rcx, [rel e32_name]
    mov     [rcx + r12*8], r8
    test    r12, r12
    jz      .name_next                     ; the null section: name 0
    add     rdi, r8
    cmp     edx, SHT_RELA
    jne     .copy_name
    ; ".rela" -> ".rel"
    cmp     dword [rsi], '.rel'
    jne     .copy_name
    cmp     byte [rsi + 4], 'a'
    jne     .copy_name
    mov     dword [rdi], '.rel'
    add     rdi, 4
    add     rsi, 5
.copy_name:
    lodsb
    stosb
    test    al, al
    jnz     .copy_name
    sub     rdi, [rel e32_strtab]
    mov     [rel e32_strlen], rdi
.name_next:
    inc     r12
    jmp     .name
.names_done:

    ; ---- each section's new contents ----
    xor     r12d, r12d
.sec:
    cmp     r12, [rel e32_shnum]
    jae     .secs_done
    SHDR64  r12
    mov     r13, rax                       ; r13 = shdr64
    mov     edx, [r13 + 4]
    lea     rcx, [rel e32_data]
    lea     r8, [rel e32_size]
    cmp     edx, SHT_SYMTAB
    je      .sec_symtab
    cmp     edx, SHT_RELA
    je      .sec_rel
    movzx   eax, word [rbx + 62]
    cmp     r12, rax
    je      .sec_names
    ; as it is (NOBITS: no bytes, the size kept); copied, so the addends
    ; can be written into it
    mov     rax, [r13 + 32]
    mov     [r8 + r12*8], rax
    cmp     edx, SHT_NOBITS
    je      .sec_next
    test    rax, rax
    jz      .sec_next
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, rax
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    lea     rcx, [rel e32_data]
    mov     [rcx + r12*8], rdx
    mov     rdi, rdx
    mov     rsi, [r13 + 24]
    add     rsi, rbx
    mov     rcx, [r13 + 32]
    rep     movsb
    jmp     .sec_next
.sec_names:
    mov     rax, [rel e32_strtab]
    mov     [rcx + r12*8], rax
    mov     rax, [rel e32_strlen]
    mov     [r8 + r12*8], rax
    jmp     .sec_next
.sec_symtab:
    ; Elf64_Sym (24) -> Elf32_Sym (16)
    mov     rax, [r13 + 32]
    xor     edx, edx
    mov     ecx, 24
    div     rcx
    mov     r14, rax                       ; count
    shl     rax, 4
    lea     r8, [rel e32_size]
    mov     [r8 + r12*8], rax
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    lea     rsi, [rax + 16]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    lea     rcx, [rel e32_data]
    mov     [rcx + r12*8], rdx
    mov     rsi, [r13 + 24]
    add     rsi, rbx
.sym:
    test    r14, r14
    jz      .sec_next
    mov     eax, [rsi]                     ; st_name
    mov     [rdx], eax
    mov     eax, [rsi + 8]                 ; st_value
    mov     [rdx + 4], eax
    mov     eax, [rsi + 16]                ; st_size
    mov     [rdx + 8], eax
    mov     al, [rsi + 4]                  ; st_info
    mov     [rdx + 12], al
    mov     al, [rsi + 5]                  ; st_other
    mov     [rdx + 13], al
    mov     ax, [rsi + 6]                  ; st_shndx
    mov     [rdx + 14], ax
    add     rsi, 24
    add     rdx, 16
    dec     r14
    jmp     .sym
.sec_rel:
    ; done once every section is copied (the addends go into them)
.sec_next:
    inc     r12
    jmp     .sec
.secs_done:

    ; ---- the relocations: Elf64_Rela (24) -> Elf32_Rel (8) ----
    xor     r12d, r12d
.rel_sec:
    cmp     r12, [rel e32_shnum]
    jae     .rels_done
    SHDR64  r12
    mov     r13, rax
    cmp     dword [r13 + 4], SHT_RELA
    jne     .rel_next
    mov     rax, [r13 + 32]
    xor     edx, edx
    mov     ecx, 24
    div     rcx
    mov     r14, rax                       ; count
    shl     rax, 3
    lea     r8, [rel e32_size]
    mov     [r8 + r12*8], rax
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    lea     rsi, [rax + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    lea     rcx, [rel e32_data]
    mov     [rcx + r12*8], rdx
    mov     r9, rdx                        ; r9 = the Rel entries
    mov     rsi, [r13 + 24]
    add     rsi, rbx                       ; rsi = the Rela entries
    mov     eax, [r13 + 44]                ; sh_info: the relocated section
    lea     rcx, [rel e32_data]
    mov     r10, [rcx + rax*8]             ; r10 = its new contents
.rel:
    test    r14, r14
    jz      .rel_next
    mov     eax, [rsi + 8]                 ; the type
    call    .map_type                      ; eax = i386 type, ecx = width
    test    ecx, ecx
    jz      .bad_reloc
    mov     rdx, [rsi]                     ; r_offset
    mov     [r9], edx
    mov     r11d, [rsi + 12]               ; the symbol
    shl     r11d, 8
    or      r11d, eax
    mov     [r9 + 4], r11d
    ; the addend, in place
    test    r10, r10
    jz      .rel_done
    mov     rax, [rsi + 16]
    cmp     ecx, 4
    jne     .rel_narrow
    mov     [r10 + rdx], eax
    jmp     .rel_done
.rel_narrow:
    cmp     ecx, 2
    jne     .rel_byte
    mov     [r10 + rdx], ax
    jmp     .rel_done
.rel_byte:
    mov     [r10 + rdx], al
.rel_done:
    add     rsi, 24
    add     r9, 8
    dec     r14
    jmp     .rel
.rel_next:
    inc     r12
    jmp     .rel_sec
.rels_done:

    ; ---- the layout ----
    mov     r13, 52                        ; after the header
    mov     r12d, 1
.layout:
    cmp     r12, [rel e32_shnum]
    jae     .laid_out
    SHDR64  r12
    mov     rcx, [rax + 48]                ; sh_addralign
    cmp     dword [rax + 4], SHT_SYMTAB
    je      .align_table
    cmp     dword [rax + 4], SHT_RELA
    jne     .align_given
.align_table:
    cmp     rcx, 4
    jbe     .align_given
    mov     ecx, 4
.align_given:
    cmp     rcx, 1
    jbe     .placed
    cmp     rcx, 16
    jbe     .align
    mov     rcx, 16
.align:
    dec     rcx
    add     r13, rcx
    not     rcx
    and     r13, rcx
.placed:
    lea     rcx, [rel e32_off]
    mov     [rcx + r12*8], r13
    cmp     dword [rax + 4], SHT_NOBITS
    je      .layout_next
    lea     rcx, [rel e32_size]
    add     r13, [rcx + r12*8]
.layout_next:
    inc     r12
    jmp     .layout
.laid_out:
    add     r13, 3
    and     r13, -4
    mov     r14, r13                       ; r14 = e_shoff
    mov     rax, [rel e32_shnum]
    imul    rax, rax, 40
    add     r13, rax
    mov     [rel e32_outlen], r13
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, r13
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel e32_out], rdx
    mov     r12, rdx                       ; r12 = the new file

    ; ---- the header ----
    mov     rsi, rbx
    mov     rdi, r12
    mov     ecx, 16
    rep     movsb                          ; e_ident ...
    mov     byte [r12 + 4], 1              ; ... ELFCLASS32
    mov     ax, [rbx + 16]
    mov     [r12 + 16], ax                 ; e_type
    mov     word [r12 + 18], 3             ; e_machine: EM_386
    mov     dword [r12 + 20], 1            ; e_version
    mov     [r12 + 32], r14d               ; e_shoff
    mov     word [r12 + 40], 52            ; e_ehsize
    mov     word [r12 + 46], 40            ; e_shentsize
    mov     rax, [rel e32_shnum]
    mov     [r12 + 48], ax                 ; e_shnum
    mov     ax, [rbx + 62]
    mov     [r12 + 50], ax                 ; e_shstrndx

    ; ---- the contents and the section headers ----
    xor     r13d, r13d
.write_sec:
    cmp     r13, [rel e32_shnum]
    jae     .written
    test    r13, r13
    jz      .write_next
    SHDR64  r13
    mov     r8, rax                        ; shdr64
    lea     rcx, [rel e32_off]
    mov     r9, [rcx + r13*8]              ; new offset
    lea     rcx, [rel e32_size]
    mov     r10, [rcx + r13*8]             ; new size
    lea     rcx, [rel e32_data]
    mov     rsi, [rcx + r13*8]
    test    rsi, rsi
    jz      .write_hdr
    cmp     dword [r8 + 4], SHT_NOBITS
    je      .write_hdr
    lea     rdi, [r12 + r9]
    mov     rcx, r10
    rep     movsb
.write_hdr:
    mov     rax, r13
    imul    rax, rax, 40
    lea     rdi, [r12 + r14]
    add     rdi, rax
    lea     rcx, [rel e32_name]
    mov     rax, [rcx + r13*8]
    mov     [rdi], eax                     ; sh_name
    mov     eax, [r8 + 4]
    cmp     eax, SHT_RELA
    jne     .hdr_type
    mov     eax, SHT_REL
.hdr_type:
    mov     [rdi + 4], eax                 ; sh_type
    mov     eax, [r8 + 8]
    mov     [rdi + 8], eax                 ; sh_flags
    mov     eax, [r8 + 16]
    mov     [rdi + 12], eax                ; sh_addr
    mov     [rdi + 16], r9d                ; sh_offset
    mov     [rdi + 20], r10d               ; sh_size
    mov     eax, [r8 + 40]
    mov     [rdi + 24], eax                ; sh_link
    mov     eax, [r8 + 44]
    mov     [rdi + 28], eax                ; sh_info
    mov     rax, [r8 + 48]
    cmp     rax, 16
    jbe     .hdr_align_tables
    mov     eax, 16
.hdr_align_tables:
    ; the symbol and relocation tables hold 4-byte fields now
    cmp     dword [r8 + 4], SHT_SYMTAB
    je      .hdr_align4
    cmp     dword [r8 + 4], SHT_RELA
    jne     .hdr_align
.hdr_align4:
    cmp     eax, 4
    jbe     .hdr_align
    mov     eax, 4
.hdr_align:
    mov     [rdi + 32], eax                ; sh_addralign
    mov     eax, [r8 + 56]                 ; sh_entsize
    cmp     dword [r8 + 4], SHT_SYMTAB
    jne     .hdr_rel
    mov     eax, 16
.hdr_rel:
    cmp     dword [r8 + 4], SHT_RELA
    jne     .hdr_ent
    mov     eax, 8
.hdr_ent:
    mov     [rdi + 36], eax
.write_next:
    inc     r13
    jmp     .write_sec
.written:

    ; ---- out ----
    mov     rdi, r15
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     edi, r13d
    mov     rsi, [rel e32_out]
    mov     rdx, [rel e32_outlen]
    call    io_write
    mov     r14, rax
    mov     rdi, r13
    call    io_close
    mov     rax, r14
    jmp     .ret

.bad_reloc:
    mov     eax, EXIT_RELOC_ERROR
    jmp     .ret
.bad:
    mov     eax, EXIT_INVALID_FORMAT
    jmp     .ret
.close_ret:
    push    rax
    mov     rdi, r12
    call    io_close
    pop     rax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .map_type: eax = an R_X86_64 type -> eax = the R_386 one, ecx = the field
; width (0: none)
.map_type:
    mov     ecx, 4
    cmp     eax, 10                        ; 32
    je      .t_32
    cmp     eax, 11                        ; 32S
    je      .t_32
    cmp     eax, 2                         ; PC32
    je      .t_same
    cmp     eax, 4                         ; PLT32
    je      .t_same
    cmp     eax, 3                         ; GOT32
    je      .t_same
    mov     ecx, 2
    cmp     eax, 12                        ; 16
    je      .t_16
    cmp     eax, 13                        ; PC16
    je      .t_pc16
    mov     ecx, 1
    cmp     eax, 14                        ; 8
    je      .t_8
    cmp     eax, 15                        ; PC8
    je      .t_pc8
    xor     ecx, ecx
    ret
.t_32:
    mov     eax, 1                         ; R_386_32
    ret
.t_same:
    ret
.t_16:
    mov     eax, 20
    ret
.t_pc16:
    mov     eax, 21
    ret
.t_8:
    mov     eax, 22
    ret
.t_pc8:
    mov     eax, 23
    ret
