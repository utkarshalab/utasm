;
; ============================================================================
; File        : backend/output/coff/coff.s
; Project     : utasm
; Description : -f win64: the ELF64 object rewritten as an x86-64 COFF one,
;               laid out as NASM's win64 output is.
;
;   The object is written as ELF64 first (sections, relocations and the
;   unused externs left out all come from the one writer), then rewritten:
;
;   - the file header (IMAGE_FILE_MACHINE_AMD64, the time stamp; 0 under
;     --reproducible), then the section headers, then each section's bytes
;     followed by its relocations, then the symbols, then the strings
;   - a section's characteristics from its ELF flags: code, data, read-only
;     data, uninitialised data, or information; its alignment in them
;   - the symbols as NASM writes them: ".file" with the source's name in
;     an auxiliary record (18 bytes of it; none under --reproducible), each
;     section's symbol with one (its length and
;     relocation count), ".absolut", then every symbol in the order it was
;     defined (SYMBOL_defseq) - labels, constants, struc names and fields,
;     labels of absolute blocks,
;     externs a relocation names, commons (their value the size)
;   - each relocation against its symbol for an extern or a common, and
;     against its section's symbol, the label's offset added, for a label
;     of this file (as NASM does, global or not); the addend written into
;     the field, as COFF objects carry it:
;
;     R_X86_64_64          -> IMAGE_REL_AMD64_ADDR64
;     R_X86_64_32 / 32S    -> IMAGE_REL_AMD64_ADDR32
;     R_X86_64_PC32 / PLT32 -> IMAGE_REL_AMD64_REL32 (the addend + 4: COFF's
;                             counts from the end of the field)
;     "wrt ..imagebase"    -> IMAGE_REL_AMD64_ADDR32NB
;
;     COFF has no 8- or 16-bit relocation, no 64-bit relative one and no
;     GOT: elf64_write_rela stops at the statement with one (coff_reloc_name)
;     where NASM writes a broken object.
;
;   The .text utasm makes up front is left out when the source never names
;   it and nothing is in it, as NASM makes it only when used.
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
extern  global_ctx
extern  sym_defseq

; a row of cf_secs, per ELF section
%define CS_NUM          0               ; its COFF section number (0: none)
%define CS_NREL         4               ; its relocations
%define CS_RAW          8               ; file offset of its bytes
%define CS_RELP         12              ; ... and of its relocations
%define CS_RELA         16              ; its .rela section's header, or 0
%define CS_SIZE         24

%define COFF_HDR        20
%define COFF_SHDR       40
%define COFF_SYM        18
%define COFF_REL        10

[SECTION .bss]
alignb 8
global coff_enabled, coff_reproducible
cf_in:          resq 1              ; the ELF64 image
cf_shoff:       resq 1
cf_shnum:       resq 1
cf_names:       resq 1              ; its section names
cf_symtab:      resq 1              ; its symbols
cf_nsym:        resq 1
cf_nuser:       resq 1              ; the source's sections: ELF 1..this
cf_secs:        resq 1              ; CS_* rows
cf_map:         resq 1              ; ELF symbol -> COFF symbol (dword)
cf_slots:       resq 1              ; SYMBOL* by SYMBOL_defseq
cf_nsec:        resq 1              ; sections written
cf_fileaux:     resq 1              ; .file's auxiliary records
cf_firstsym:    resq 1              ; the first of the source's symbols
cf_nrec:        resq 1              ; symbol records, auxiliary ones too
cf_strsize:     resq 1              ; the string table, without its size
cf_symoff:      resq 1
cf_out:         resq 1
cf_outlen:      resq 1
cf_strpos:      resq 1              ; the next string's offset
coff_enabled:   resb 1              ; -f win64
coff_reproducible: resb 1           ; --reproducible: time stamp 0

[SECTION .rodata]
cf_debug:       db ".debug"
cf_debug_len    equ $ - cf_debug
cf_file:        db ".file", 0, 0, 0
cf_absolut:     db ".absolut"
cf_here:        db "L@here."
cf_n8:          db "8-bit", 0
cf_n16:         db "16-bit", 0
cf_npc8:        db "8-bit relative", 0
cf_npc16:       db "16-bit relative", 0
cf_npc64:       db "64-bit relative", 0
cf_nib64:       db "64-bit image-relative", 0
cf_ngotpcrel:   db "..gotpcrel", 0
cf_ngot:        db "..got", 0
cf_ngotoff:     db "..gotoff", 0
cf_ntlsie:      db "..tlsie", 0
cf_nother:      db "such a", 0

[SECTION .text]

; shdr64 %1 -> rax = its address in the input
%macro SHDR64 1
    mov     rax, %1
    shl     rax, 6
    add     rax, [rel cf_shoff]
    add     rax, [rel cf_in]
%endmacro

; row %1 of cf_secs -> rax
%macro SECROW 1
    imul    rax, %1, CS_SIZE
    add     rax, [rel cf_secs]
%endmacro

;*
; * [coff_reloc_name]
; * Purpose: Whether COFF has a form of an ELF relocation type.
; * Input  : EDI = R_X86_64_* (or R_UTASM_IMAGEBASE*)
; * Output : RAX = 0 when it has; else what the reference is, for
; *          "COFF format has no ^ relocation"
; ;
global coff_reloc_name
coff_reloc_name:
    xor     eax, eax
    cmp     edi, R_X86_64_64
    je      .ret
    cmp     edi, R_X86_64_32
    je      .ret
    cmp     edi, R_X86_64_32S
    je      .ret
    cmp     edi, R_X86_64_PC32
    je      .ret
    cmp     edi, R_X86_64_PLT32
    je      .ret
    cmp     edi, R_UTASM_IMAGEBASE
    je      .ret
    lea     rax, [rel cf_n8]
    cmp     edi, 14                        ; R_X86_64_8
    je      .ret
    lea     rax, [rel cf_n16]
    cmp     edi, 12                        ; R_X86_64_16
    je      .ret
    lea     rax, [rel cf_npc8]
    cmp     edi, 15                        ; R_X86_64_PC8
    je      .ret
    lea     rax, [rel cf_npc16]
    cmp     edi, 13                        ; R_X86_64_PC16
    je      .ret
    lea     rax, [rel cf_npc64]
    cmp     edi, 24                        ; R_X86_64_PC64
    je      .ret
    lea     rax, [rel cf_nib64]
    cmp     edi, R_UTASM_IMAGEBASE64
    je      .ret
    lea     rax, [rel cf_ngotpcrel]
    cmp     edi, R_X86_64_GOTPCREL
    je      .ret
    lea     rax, [rel cf_ngot]
    cmp     edi, R_X86_64_GOT32
    je      .ret
    cmp     edi, 27                        ; R_X86_64_GOT64
    je      .ret
    lea     rax, [rel cf_ngotoff]
    cmp     edi, R_X86_64_GOTOFF64
    je      .ret
    lea     rax, [rel cf_ntlsie]
    cmp     edi, R_X86_64_GOTTPOFF
    je      .ret
    lea     rax, [rel cf_nother]
.ret:
    ret

;*
; * [coff_convert]
; * Purpose: Rewrite the ELF64 object at path RDI as COFF.
; * Input  : RDI = output path
; * Output : RAX = EXIT_OK or an error
; ;
global coff_convert
coff_convert:
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
    mov     [rel cf_in], rdx
    mov     rdi, r12
    call    io_close

    mov     rbx, [rel cf_in]
    mov     rax, [rbx + 40]                ; e_shoff
    mov     [rel cf_shoff], rax
    movzx   eax, word [rbx + 60]           ; e_shnum
    mov     [rel cf_shnum], rax
    movzx   eax, word [rbx + 62]           ; e_shstrndx
    SHDR64  rax
    mov     rax, [rax + 24]
    add     rax, rbx
    mov     [rel cf_names], rax
    lea     rax, [rel global_ctx]
    movzx   eax, word [rax + ASMCTX_seccount]
    mov     [rel cf_nuser], rax
    cmp     rax, [rel cf_shnum]
    jae     .bad

    ; the symbol table
    mov     qword [rel cf_symtab], 0
    mov     qword [rel cf_nsym], 0
    xor     r12d, r12d
.find_symtab:
    cmp     r12, [rel cf_shnum]
    jae     .symtab_found
    SHDR64  r12
    cmp     dword [rax + 4], SHT_SYMTAB
    jne     .next_symtab
    mov     rcx, [rax + 24]
    add     rcx, rbx
    mov     [rel cf_symtab], rcx
    mov     rax, [rax + 32]
    xor     edx, edx
    mov     ecx, 24
    div     rcx
    mov     [rel cf_nsym], rax
    jmp     .symtab_found
.next_symtab:
    inc     r12
    jmp     .find_symtab
.symtab_found:

    ; ---- the sections written ----
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, [rel cf_shnum]
    imul    rsi, rsi, CS_SIZE
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel cf_secs], rdx
    mov     qword [rel cf_nsec], 0
    mov     r12d, 1
.which:
    cmp     r12, [rel cf_nuser]
    ja      .which_done
    SHDR64  r12
    mov     r13, rax
    cmp     dword [r13 + 4], 17            ; SHT_GROUP: no COFF form
    je      .which_next
    ; debug information (-g): DWARF has no place in COFF
    mov     esi, [r13]
    add     rsi, [rel cf_names]
    lea     rdi, [rel cf_debug]
    mov     ecx, cf_debug_len
    repe    cmpsb
    je      .which_next
    mov     rdi, r12
    call    cf_unused_text
    test    eax, eax
    jnz     .which_next
    inc     qword [rel cf_nsec]
    SECROW  r12
    mov     rcx, [rel cf_nsec]
    mov     [rax + CS_NUM], ecx
.which_next:
    inc     r12
    jmp     .which
.which_done:

    ; ---- their relocations ----
    xor     r12d, r12d
.rela:
    cmp     r12, [rel cf_shnum]
    jae     .rela_done
    SHDR64  r12
    mov     r13, rax
    cmp     dword [r13 + 4], SHT_RELA
    jne     .rela_next
    mov     ecx, [r13 + 44]                ; sh_info: the section relocated
    test    rcx, rcx
    jz      .rela_next
    cmp     rcx, [rel cf_nuser]
    ja      .rela_next
    SECROW  rcx
    cmp     dword [rax + CS_NUM], 0
    je      .rela_next
    mov     [rax + CS_RELA], r13
    mov     r8, rax
    mov     rax, [r13 + 32]
    xor     edx, edx
    mov     ecx, 24
    div     rcx
    cmp     rax, 0xFFFF
    ja      .bad_reloc                     ; (COFF counts them in 16 bits)
    mov     [r8 + CS_NREL], eax
.rela_next:
    inc     r12
    jmp     .rela
.rela_done:

    ; ---- the symbols: .file, the sections', .absolut, then the source's
    ;      in the order they were defined. .file has one auxiliary record,
    ;      as NASM writes it ----
    mov     eax, 1
    mov     [rel cf_fileaux], rax
    mov     rcx, [rel cf_nsec]
    lea     rax, [rax + rcx*2 + 2]         ; .file, its aux, 2 a section, .absolut
    mov     [rel cf_firstsym], rax
    mov     [rel cf_nrec], rax
    mov     qword [rel cf_strsize], 0

    ; the section names longer than 8 go in the strings first
    mov     r12d, 1
.long_names:
    cmp     r12, [rel cf_nuser]
    ja      .long_names_done
    SECROW  r12
    cmp     dword [rax + CS_NUM], 0
    je      .long_next
    SHDR64  r12
    mov     esi, [rax]
    add     rsi, [rel cf_names]
    call    cf_strlen                      ; rcx
    cmp     rcx, 8
    jbe     .long_next
    inc     rcx
    add     [rel cf_strsize], rcx
.long_next:
    inc     r12
    jmp     .long_names
.long_names_done:

    ; SYMBOL* by its place in the order
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     esi, [rel sym_defseq]
    lea     rsi, [rsi*8 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel cf_slots], rdx
    lea     rax, [rel global_ctx]
    mov     r13, [rax + ASMCTX_symtab]
    mov     r14d, [rax + ASMCTX_symcount]
.slot:
    test    r14d, r14d
    jz      .slotted
    mov     r8, r13
    call    cf_sym_written
    test    eax, eax
    jz      .slot_next
    mov     eax, [r13 + SYMBOL_defseq]
    cmp     eax, [rel sym_defseq]
    ja      .slot_next
    mov     rcx, [rel cf_slots]
    mov     [rcx + rax*8], r13
.slot_next:
    add     r13, SYMBOL_SIZE
    dec     r14d
    jmp     .slot
.slotted:

    ; ELF symbol -> COFF symbol, for the relocations against externs and
    ; commons (-1: none)
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, [rel cf_nsym]
    lea     rsi, [rsi*4 + 4]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel cf_map], rdx
    mov     rdi, rdx
    mov     rcx, [rel cf_nsym]
    inc     rcx
    mov     eax, -1
    rep     stosd
    xor     r12d, r12d                     ; the place in the order
.number:
    cmp     r12d, [rel sym_defseq]
    ja      .numbered
    mov     rcx, [rel cf_slots]
    mov     r13, [rcx + r12*8]
    test    r13, r13
    jz      .number_next
    mov     rdx, [rel cf_nrec]
    inc     qword [rel cf_nrec]
    mov     eax, [r13 + SYMBOL_elf_idx]
    test    eax, eax
    jz      .number_name
    cmp     rax, [rel cf_nsym]
    jae     .number_name
    mov     rcx, [rel cf_map]
    mov     [rcx + rax*4], edx
.number_name:
    mov     rsi, [r13 + SYMBOL_name]
    call    cf_strlen
    cmp     rcx, 8
    jbe     .number_next
    inc     rcx
    add     [rel cf_strsize], rcx
.number_next:
    inc     r12d
    jmp     .number
.numbered:

    ; ---- the layout ----
    mov     r13, [rel cf_nsec]
    imul    r13, r13, COFF_SHDR
    add     r13, COFF_HDR                  ; after the headers
    mov     r12d, 1
.layout:
    cmp     r12, [rel cf_nuser]
    ja      .laid_out
    SECROW  r12
    mov     r14, rax
    cmp     dword [r14 + CS_NUM], 0
    je      .layout_next
    SHDR64  r12
    cmp     dword [rax + 4], SHT_NOBITS
    je      .layout_next                   ; no bytes, no relocations
    mov     [r14 + CS_RAW], r13d
    add     r13, [rax + 32]
    mov     [r14 + CS_RELP], r13d
    mov     eax, [r14 + CS_NREL]
    imul    eax, eax, COFF_REL
    add     r13, rax
.layout_next:
    inc     r12
    jmp     .layout
.laid_out:
    mov     [rel cf_symoff], r13
    mov     rax, [rel cf_nrec]
    imul    rax, rax, COFF_SYM
    add     r13, rax
    add     r13, 4                         ; the strings' size
    add     r13, [rel cf_strsize]
    mov     [rel cf_outlen], r13
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, r13
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel cf_out], rdx
    mov     r12, rdx                       ; r12 = the new file

    ; ---- the file header ----
    mov     word [r12], 0x8664             ; IMAGE_FILE_MACHINE_AMD64
    mov     rax, [rel cf_nsec]
    mov     [r12 + 2], ax
    xor     eax, eax
    cmp     byte [rel coff_reproducible], 0
    jne     .stamp
    mov     eax, 201                       ; SYS_time
    xor     edi, edi
    syscall
.stamp:
    mov     [r12 + 4], eax                 ; TimeDateStamp
    mov     rax, [rel cf_symoff]
    mov     [r12 + 8], eax                 ; PointerToSymbolTable
    mov     rax, [rel cf_nrec]
    mov     [r12 + 12], eax                ; NumberOfSymbols

    ; ---- the section headers, bytes and relocations ----
    mov     rax, [rel cf_symoff]
    add     rax, [rel cf_nrec]
    imul    rcx, [rel cf_nrec], COFF_SYM - 1
    add     rax, rcx                       ; symoff + nrec * 18
    mov     ecx, 4
    add     rcx, [rel cf_strsize]
    mov     [r12 + rax], ecx               ; the strings' size
    mov     qword [rel cf_strpos], 4
    mov     r14d, 1
.write_sec:
    cmp     r14, [rel cf_nuser]
    ja      .secs_written
    SECROW  r14
    mov     r13, rax                       ; r13 = the row
    mov     ecx, [r13 + CS_NUM]
    test    ecx, ecx
    jz      .write_next
    dec     ecx
    imul    ecx, ecx, COFF_SHDR
    lea     rdi, [r12 + rcx + COFF_HDR]    ; rdi = its header
    SHDR64  r14
    mov     rbx, rax                       ; rbx = the ELF one
    ; the name: 8 bytes, or "/N" with N its offset in the strings
    mov     esi, [rbx]
    add     rsi, [rel cf_names]
    call    cf_strlen
    cmp     rcx, 8
    ja      .long_sec_name
    push    rdi
    rep     movsb
    pop     rdi
    jmp     .sec_named
.long_sec_name:
    call    cf_put_string                  ; eax = its offset
    call    cf_slash_name
.sec_named:
    mov     rax, [rbx + 32]
    mov     [rdi + 16], eax                ; SizeOfRawData (.bss too)
    mov     eax, [r13 + CS_RAW]
    mov     [rdi + 20], eax                ; PointerToRawData
    mov     eax, [r13 + CS_RELP]
    mov     [rdi + 24], eax                ; PointerToRelocations
    mov     eax, [r13 + CS_NREL]
    mov     [rdi + 32], ax                 ; NumberOfRelocations
    call    cf_characteristics             ; rbx = shdr64 -> eax
    mov     [rdi + 36], eax
    ; the bytes
    cmp     dword [rbx + 4], SHT_NOBITS
    je      .write_next
    mov     rsi, [rbx + 24]
    add     rsi, [rel cf_in]
    mov     ecx, [r13 + CS_RAW]
    lea     rdi, [r12 + rcx]
    mov     rcx, [rbx + 32]
    rep     movsb
    ; the relocations
    mov     rdi, r13
    call    cf_relocations
    test    rax, rax
    jnz     .ret
.write_next:
    inc     r14
    jmp     .write_sec
.secs_written:

    ; ---- the symbols ----
    mov     rdi, [rel cf_symoff]
    add     rdi, r12                       ; rdi = the next record
    ; .file and the source's name
    lea     rsi, [rel cf_file]
    mov     rax, [rsi]
    mov     [rdi], rax
    mov     word [rdi + 12], 0xFFFE        ; IMAGE_SYM_DEBUG
    mov     byte [rdi + 16], 103           ; IMAGE_SYM_CLASS_FILE
    mov     rax, [rel cf_fileaux]
    mov     [rdi + 17], al
    add     rdi, COFF_SYM
    ; the name as given, its first 18 bytes (NASM's); none under
    ; --reproducible, as NASM leaves it
    cmp     byte [rel coff_reproducible], 0
    jne     .file_named
    call    cf_file_len
    cmp     rcx, COFF_SYM
    jbe     .file_name
    mov     ecx, COFF_SYM
.file_name:
    push    rdi
    rep     movsb
    pop     rdi
.file_named:
    add     rdi, COFF_SYM
    ; a symbol for each section, with its length and relocations
    mov     r14d, 1
.sec_sym:
    cmp     r14, [rel cf_nuser]
    ja      .sec_syms_done
    SECROW  r14
    mov     r13, rax
    mov     ecx, [r13 + CS_NUM]
    test    ecx, ecx
    jz      .sec_sym_next
    mov     [rdi + 12], cx                 ; SectionNumber
    mov     byte [rdi + 16], 3             ; IMAGE_SYM_CLASS_STATIC
    mov     byte [rdi + 17], 1
    SHDR64  r14
    mov     rbx, rax
    mov     esi, [rbx]
    add     rsi, [rel cf_names]
    call    cf_strlen
    cmp     rcx, 8
    jbe     .sec_sym_name
    mov     ecx, 8                         ; NASM's: cut to 8
.sec_sym_name:
    push    rdi
    rep     movsb
    pop     rdi
    mov     rax, [rbx + 32]
    mov     [rdi + COFF_SYM], eax          ; aux: Length
    mov     eax, [r13 + CS_NREL]
    mov     [rdi + COFF_SYM + 4], ax       ; NumberOfRelocations
    add     rdi, COFF_SYM * 2
.sec_sym_next:
    inc     r14
    jmp     .sec_sym
.sec_syms_done:
    ; .absolut
    lea     rsi, [rel cf_absolut]
    mov     rax, [rsi]
    mov     [rdi], rax
    mov     word [rdi + 12], 0xFFFF        ; IMAGE_SYM_ABSOLUTE
    mov     byte [rdi + 16], 3
    add     rdi, COFF_SYM
    ; the source's
    xor     r14d, r14d
.user_sym:
    cmp     r14d, [rel sym_defseq]
    ja      .user_syms_done
    mov     rcx, [rel cf_slots]
    mov     r8, [rcx + r14*8]
    test    r8, r8
    jz      .user_sym_next
    call    cf_write_symbol
    add     rdi, COFF_SYM
.user_sym_next:
    inc     r14d
    jmp     .user_sym
.user_syms_done:

    ; ---- out ----
    mov     rdi, r15
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     edi, r13d
    mov     rsi, [rel cf_out]
    mov     rdx, [rel cf_outlen]
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

; ---- cf_strlen: rsi = a string -> rcx = its length (rsi kept) ----
cf_strlen:
    xor     ecx, ecx
    test    rsi, rsi
    jz      .ret
.len:
    cmp     byte [rsi + rcx], 0
    je      .ret
    inc     rcx
    jmp     .len
.ret:
    ret

; ---- cf_file_len: rcx = the source's name's length (0: none) ----
cf_file_len:
    mov     rsi, [rel global_ctx + ASMCTX_input]
    jmp     cf_strlen

; ---- cf_put_string: rsi = a string, rcx = its length -> eax = its offset
;      in the strings, where it is copied with its NUL. Keeps rdi. ----
cf_put_string:
    push    rdi
    mov     rax, [rel cf_strpos]
    push    rax
    mov     rdi, [rel cf_symoff]
    add     rdi, [rel cf_out]
    imul    rdx, [rel cf_nrec], COFF_SYM
    add     rdi, rdx
    add     rdi, rax                       ; the strings at symoff + nrec * 18
    lea     rdx, [rax + rcx + 1]
    mov     [rel cf_strpos], rdx
    rep     movsb
    mov     byte [rdi], 0
    pop     rax
    pop     rdi
    ret

; ---- cf_slash_name: eax = an offset in the strings -> "/0000004" at rdi,
;      as NASM writes a long section name. Keeps rdi. ----
cf_slash_name:
    mov     byte [rdi], '/'
    mov     ecx, 7
    mov     r8d, 10
.digit:
    xor     edx, edx
    div     r8d
    add     dl, '0'
    mov     [rdi + rcx], dl
    dec     ecx
    jnz     .digit
    ret

; ---- cf_characteristics: rbx = an ELF section header -> eax = its COFF
;      characteristics ----
cf_characteristics:
    mov     eax, 0xC0000080                ; uninitialised data, read write
    cmp     dword [rbx + 4], SHT_NOBITS
    je      .align
    mov     rcx, [rbx + 8]                 ; sh_flags
    mov     eax, 0x60000020                ; code, execute read
    test    ecx, SHF_EXECINSTR
    jnz     .align
    mov     eax, 0xC0000040                ; initialised data, read write
    test    ecx, SHF_WRITE
    jnz     .align
    mov     eax, 0x40000040                ; ... read only
    test    ecx, SHF_ALLOC
    jnz     .align
    mov     eax, 0x00000A00                ; information, removed when linked
.align:
    ; IMAGE_SCN_ALIGN_<n>BYTES: (log2(n) + 1) << 20, 8192 at most
    mov     rcx, [rbx + 48]
    xor     edx, edx
    cmp     rcx, 1
    jbe     .align_bits
    bsr     rdx, rcx
.align_bits:
    inc     edx
    cmp     edx, 14
    jbe     .align_put
    mov     edx, 14
.align_put:
    shl     edx, 20
    or      eax, edx
    ret

; ---- cf_unused_text: rdi = an ELF section index -> eax = 1 when it is
;      the .text utasm made up front, never named by the source and with
;      nothing in it ----
cf_unused_text:
    lea     r8, [rel global_ctx]
    mov     r9, [r8 + ASMCTX_sections]
    movzx   ecx, word [r8 + ASMCTX_seccount]
.find:
    test    ecx, ecx
    jz      .no
    mov     rax, [r9]
    add     r9, 8
    dec     ecx
    test    rax, rax
    jz      .find
    cmp     [rax + SECTION_index], edi
    jne     .find
    cmp     byte [rax + SECTION_implicit], 0
    je      .no
    cmp     dword [rax + SECTION_named_at], 0
    jne     .no
    cmp     qword [rax + SECTION_size], 0
    jne     .no
    ; and no label in it
    mov     r9, [r8 + ASMCTX_symtab]
    mov     ecx, [r8 + ASMCTX_symcount]
.label:
    test    ecx, ecx
    jz      .yes
    cmp     byte [r9 + SYMBOL_kind], SYM_MACRO
    je      .label_next
    movzx   eax, word [r9 + SYMBOL_section]
    cmp     eax, edi
    je      .no
.label_next:
    add     r9, SYMBOL_SIZE
    dec     ecx
    jmp     .label
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- cf_sym_written: r8 = SYMBOL -> eax = 1 when COFF has it ----
cf_sym_written:
    movzx   eax, byte [r8 + SYMBOL_kind]
    cmp     eax, SYM_MACRO
    je      .no
    cmp     eax, SYM_SECTION
    je      .no
    cmp     eax, SYM_BUILTIN
    je      .no
    mov     rcx, [r8 + SYMBOL_name]
    test    rcx, rcx
    jz      .no
    ; the hidden labels "$" makes (parser_pos_label)
    cmp     dword [rcx], 'L@he'
    jne     .not_here
    cmp     word [rcx + 4], 're'
    jne     .not_here
    cmp     byte [rcx + 6], '.'
    je      .no
.not_here:
    cmp     eax, SYM_COMMON
    je      .yes
    test    byte [r8 + SYMBOL_pflags], SYMF_STRUC
    jnz     .yes                           ; a label of an absolute block
    cmp     eax, SYM_STRUCT
    je      .yes
    cmp     eax, SYM_STRUCT_FIELD
    je      .yes
    cmp     word [r8 + SYMBOL_section], 0
    jne     .yes
    ; undefined: an extern a relocation names
    cmp     eax, SYM_EXTERN
    jne     .no
    test    byte [r8 + SYMBOL_pflags], SYMF_USED
    jz      .no
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- cf_write_symbol: r8 = SYMBOL, rdi = its record (zeroed). Keeps
;      rdi, r12-r15. ----
cf_write_symbol:
    push    rbx
    mov     rbx, r8
    ; the name: 8 bytes, or 0 and its offset in the strings
    mov     rsi, [rbx + SYMBOL_name]
    call    cf_strlen
    cmp     rcx, 8
    ja      .long_name
    push    rdi
    rep     movsb
    pop     rdi
    jmp     .named
.long_name:
    call    cf_put_string
    mov     [rdi + 4], eax
.named:
    ; the value: a common's is its size
    mov     rax, [rbx + SYMBOL_value]
    cmp     byte [rbx + SYMBOL_kind], SYM_COMMON
    jne     .value
    mov     rax, [rbx + SYMBOL_size]
.value:
    mov     [rdi + 8], eax
    ; the section: a struc's name, field or absolute label, a constant:
    ; -1 (absolute); undefined or common: 0
    mov     eax, 0xFFFF
    movzx   ecx, byte [rbx + SYMBOL_kind]
    cmp     ecx, SYM_STRUCT
    je      .section
    cmp     ecx, SYM_STRUCT_FIELD
    je      .section
    test    byte [rbx + SYMBOL_pflags], SYMF_STRUC
    jnz     .section
    movzx   ecx, word [rbx + SYMBOL_section]
    xor     eax, eax
    test    ecx, ecx
    jz      .section
    cmp     ecx, SHN_COMMON
    je      .section
    mov     eax, 0xFFFF
    cmp     ecx, 0xFF00
    jae     .section
    xor     eax, eax
    cmp     rcx, [rel cf_nuser]
    ja      .section
    SECROW  rcx
    mov     eax, [rax + CS_NUM]
.section:
    mov     [rdi + 12], ax
    ; the type: a function's (DT_FUNCTION << 4), declared "global f:function"
    xor     eax, eax
    cmp     byte [rbx + SYMBOL_etype], ETYPE_FUNC
    jne     .type
    mov     eax, 0x20
.type:
    mov     [rdi + 14], ax
    ; the class: external, or static for a local
    mov     byte [rdi + 16], 2             ; IMAGE_SYM_CLASS_EXTERNAL
    cmp     byte [rbx + SYMBOL_vis], VIS_LOCAL
    jne     .class
    mov     byte [rdi + 16], 3             ; IMAGE_SYM_CLASS_STATIC
.class:
    pop     rbx
    ret

; ---- cf_relocations: rdi = the row of a section written, its bytes in
;      place -> each relocation in COFF's form, its addend in the field.
;      rax = 0 or an error. Keeps r12-r15. ----
cf_relocations:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi                       ; rbx = the row
    mov     r12, [rel cf_out]
    mov     rax, [rbx + CS_RELA]
    test    rax, rax
    jz      .done
    mov     r13, [rax + 24]
    add     r13, [rel cf_in]               ; r13 = the Rela entries
    mov     r14d, [rbx + CS_NREL]
    mov     r15d, [rbx + CS_RELP]
    add     r15, r12                       ; r15 = the COFF ones
.one:
    test    r14d, r14d
    jz      .done
    mov     r8, [r13 + 8]                  ; r_info
    mov     r9d, r8d                       ; the type
    shr     r8, 32                         ; the symbol
    mov     r10, [r13 + 16]                ; the addend
    ; the symbol: a label of a section written -> that section's, its
    ; offset added
    cmp     r8, [rel cf_nsym]
    jae     .bad
    imul    rax, r8, 24
    add     rax, [rel cf_symtab]
    movzx   ecx, word [rax + 6]            ; st_shndx
    test    ecx, ecx
    jz      .by_symbol
    cmp     rcx, [rel cf_nuser]
    ja      .by_symbol
    add     r10, [rax + 8]                 ; st_value
    SECROW  rcx
    mov     eax, [rax + CS_NUM]
    test    eax, eax
    jz      .bad
    dec     eax
    shl     eax, 1
    add     rax, [rel cf_fileaux]
    inc     eax                            ; after .file and its aux
    jmp     .have_symbol
.by_symbol:
    mov     rcx, [rel cf_map]
    mov     eax, [rcx + r8*4]
    cmp     eax, -1
    je      .bad
.have_symbol:
    mov     [r15 + 4], eax                 ; SymbolTableIndex
    mov     rax, [r13]
    mov     [r15], eax                     ; VirtualAddress
    ; the type, and the addend into the field
    mov     ecx, [rbx + CS_RAW]
    add     rcx, rax
    add     rcx, r12                       ; rcx = the field
    cmp     r9d, R_X86_64_64
    jne     .not64
    mov     word [r15 + 8], 1              ; IMAGE_REL_AMD64_ADDR64
    mov     [rcx], r10
    jmp     .next
.not64:
    mov     edx, 2                         ; IMAGE_REL_AMD64_ADDR32
    cmp     r9d, R_X86_64_32
    je      .field32
    cmp     r9d, R_X86_64_32S
    je      .field32
    mov     edx, 3                         ; IMAGE_REL_AMD64_ADDR32NB
    cmp     r9d, R_UTASM_IMAGEBASE
    je      .field32
    mov     edx, 4                         ; IMAGE_REL_AMD64_REL32
    add     r10, 4                         ; from the end of the field
    cmp     r9d, R_X86_64_PC32
    je      .field32
    cmp     r9d, R_X86_64_PLT32
    je      .field32
    mov     eax, EXIT_COFF_RELOC           ; (elf64_write_rela says where)
    jmp     .ret
.field32:
    mov     [r15 + 8], dx
    mov     [rcx], r10d
.next:
    add     r13, 24
    add     r15, COFF_REL
    dec     r14d
    jmp     .one
.bad:
    mov     eax, EXIT_RELOC_ERROR
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
