;
; ============================================================================
; File        : src/object/ubf/ubf.s
; Project     : utasm
; Description : -f ubf: the ELF64 object rewritten as a UBF program image,
;               the Utkarsha Binary Format of Utkarsha OS programs
;               (docs/user/ubf.md; the OS repository's docs/UBF_SPEC.md).
;
;   The object is written as ELF64 first, then rewritten:
;
;   - its allocated sections are grouped into four segments, each starting
;     on a page: text (R-X), rodata (R--), data (RW-), bss (RW-, no bytes);
;   - every extern a relocation names becomes an import: an 8-byte slot at
;     the end of rodata, which the loader fills, and a stub `jmp [rel slot]`
;     (FF 25 disp32, padded to 8 with int3) at the end of text;
;   - the relocations are resolved against that layout:
;       R_X86_64_64 to a label          the value, plus an ABS64 entry
;       PC32 / PLT32 to a label         the displacement
;       PC32 / PLT32 to an import       the displacement to its stub
;       GOTPCREL(X) to an import        the displacement to its slot
;       PC64 / PC16 / PC8 to a label    the displacement
;       32 / 32S / 16 / 8               only to an absolute value
;     anything else is an error naming the symbol;
;   - defined globals become exports; `_start` (else `main`) in text is the
;     entry point, and an image without one is a library;
;   - the file: a 128-byte header, the segment, relocation, import and
;     export tables, the string table, then the segments' bytes; the
;     header's SHA-256 covers the whole file with that field zero.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"

extern  io_open
extern  io_create
extern  io_close
extern  io_write
extern  io_file_size
extern  io_mmap
extern  arena_alloc
extern  global_ctx
extern  sha256_hash
extern  error_set_subject

%define MAX_SECS        (1 << 16)

%ifndef SHN_ABS
%define SHN_ABS         0xFFF1
%endif
%ifndef SHN_COMMON
%define SHN_COMMON      0xFFF2
%endif

%define UBF_MAGIC_V     0x00464255      ; "UBF\0"
%define UBF_HEADER      128
%define UBF_PAGE        4096
%define UBF_MAX_MEM     (1 << 30)       ; 1 GiB
%define UBF_SLOT        8               ; an import slot / stub, bytes

; classes (also the UBF segment types)
%define CL_NONE         0
%define CL_TEXT         1
%define CL_RODATA       2
%define CL_DATA         3
%define CL_BSS          4

[SECTION .bss]
alignb 8
global ubf_enabled
ub_in:          resq 1              ; the ELF64 image
ub_shoff:       resq 1
ub_shnum:       resq 1
ub_names:       resq 1              ; its section names
ub_syms:        resq 1              ; its symbols (Elf64_Sym)
ub_nsym:        resq 1
ub_strs:        resq 1              ; its symbol names
ub_imp_of:      resq 1              ; dword per symbol: import index + 1, or 0
ub_imp_sym:     resq 1              ; dword per import: its symbol
ub_nimp:        resq 1
ub_rel:         resq 1              ; dword per ABS64 relocation: its offset
ub_nrel:        resq 1
ub_nexp:        resq 1
ub_entry:       resq 1              ; image offset of the entry, or -1
ub_start:       resq 5              ; per class: image offset of its start
ub_size:        resq 5              ; per class: bytes used
ub_stubs:       resq 1              ; image offset of the first stub
ub_slots:       resq 1              ; image offset of the first slot
ub_mem:         resq 1              ; the image's size, page-rounded
ub_fbend:       resq 1              ; end of the bytes the file carries
ub_img:         resq 1              ; the image up to ub_fbend
ub_strsize:     resq 1              ; the UBF string table's size
ub_out:         resq 1
ub_outlen:      resq 1
ub_base:        resq MAX_SECS       ; per section: its image offset
ub_class:       resb MAX_SECS       ; per section: CL_*
ubf_enabled:    resb 1              ; -f ubf

[SECTION .text]

; shdr rax -> rax = its address in the input
%macro SHDR 1
    mov     rax, %1
    shl     rax, 6
    add     rax, [rel ub_shoff]
    add     rax, [rel ub_in]
%endmacro

; sym %1 -> rax = its Elf64_Sym
%macro SYM 1
    mov     rax, %1
    imul    rax, rax, 24
    add     rax, [rel ub_syms]
%endmacro

; align %1 up to the power of two %2 (a register; clobbers it)
%macro ALIGNUP 2
    dec     %2
    add     %1, %2
    not     %2
    and     %1, %2
%endmacro

;*
; * [ubf_convert]
; * Purpose: Rewrite the ELF64 object at path RDI as a UBF image.
; * Input  : RDI = output path
; * Output : RAX = EXIT_OK or an error (the subject set to the symbol)
; ;
global ubf_convert
ubf_convert:
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
    mov     [rel ub_in], rdx
    mov     rdi, r12
    call    io_close

    mov     rbx, [rel ub_in]
    mov     rax, [rbx + 40]                ; e_shoff
    mov     [rel ub_shoff], rax
    movzx   eax, word [rbx + 60]           ; e_shnum
    mov     [rel ub_shnum], rax
    cmp     eax, MAX_SECS
    ja      .bad
    movzx   eax, word [rbx + 62]           ; e_shstrndx
    SHDR    rax
    mov     rax, [rax + 24]
    add     rax, rbx
    mov     [rel ub_names], rax

    call    ub_classify
    call    ub_find_imports
    test    rax, rax
    jnz     .ret
    call    ub_layout
    test    rax, rax
    jnz     .ret
    call    ub_build_image
    test    rax, rax
    jnz     .ret
    call    ub_relocate
    test    rax, rax
    jnz     .ret
    call    ub_find_entry
    call    ub_write
    test    rax, rax
    jnz     .ret

    ; ---- out ----
    mov     rdi, r15
    mov     rdx, 0o644
    call    io_create
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     edi, r13d
    mov     rsi, [rel ub_out]
    mov     rdx, [rel ub_outlen]
    call    io_write
    mov     r14, rax
    mov     rdi, r13
    call    io_close
    mov     rax, r14
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

; ---- ub_classify --------------------------------------------------------
; Each section's class, and the symbol table. Clobbers rax-rdx, rsi, r8.
ub_classify:
    mov     qword [rel ub_syms], 0
    mov     qword [rel ub_nsym], 0
    xor     r8d, r8d
.next:
    inc     r8
    cmp     r8, [rel ub_shnum]
    jae     .done
    SHDR    r8
    mov     edx, [rax + 4]                 ; sh_type
    mov     rcx, [rax + 8]                 ; sh_flags
    lea     rsi, [rel ub_class]
    mov     byte [rsi + r8], CL_NONE
    cmp     edx, SHT_SYMTAB
    jne     .not_symtab
    mov     rcx, [rax + 24]
    add     rcx, [rel ub_in]
    mov     [rel ub_syms], rcx
    mov     rcx, rax
    mov     rax, [rcx + 32]
    xor     edx, edx
    mov     esi, 24
    div     rsi
    mov     [rel ub_nsym], rax
    mov     eax, [rcx + 40]                ; sh_link: its names
    SHDR    rax
    mov     rax, [rax + 24]
    add     rax, [rel ub_in]
    mov     [rel ub_strs], rax
    jmp     .next
.not_symtab:
    test    rcx, SHF_ALLOC
    jz      .next
    mov     byte [rsi + r8], CL_BSS
    cmp     edx, SHT_NOBITS
    je      .next
    mov     byte [rsi + r8], CL_TEXT
    test    rcx, SHF_EXECINSTR
    jnz     .next
    mov     byte [rsi + r8], CL_DATA
    test    rcx, SHF_WRITE
    jnz     .next
    mov     byte [rsi + r8], CL_RODATA
    jmp     .next
.done:
    ret

; ---- ub_find_imports ----------------------------------------------------
; Every undefined symbol a relocation of a loaded section names becomes an
; import. Output: rax = EXIT_OK or an error. Clobbers rax-rdx, rsi, rdi,
; r8-r11.
ub_find_imports:
    mov     qword [rel ub_nimp], 0
    mov     rsi, [rel ub_nsym]
    shl     rsi, 2
    add     rsi, 8
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel ub_imp_of], rdx
    mov     rsi, [rel ub_nsym]
    shl     rsi, 2
    add     rsi, 8
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel ub_imp_sym], rdx

    xor     r8d, r8d
.sec:
    inc     r8
    cmp     r8, [rel ub_shnum]
    jae     .ok
    SHDR    r8
    cmp     dword [rax + 4], SHT_RELA
    jne     .sec
    mov     ecx, [rax + 44]                ; the relocated section
    lea     rdx, [rel ub_class]
    cmp     byte [rdx + rcx], CL_NONE
    je      .sec                           ; a debug section's: not loaded
    mov     r9, [rax + 24]
    add     r9, [rel ub_in]                ; r9 = the entries
    push    rax
    mov     rax, [rax + 32]
    call    ub_div24
    mov     r10, rax                       ; r10 = their count
    pop     rax
.rela:
    test    r10, r10
    jz      .sec
    mov     r11d, [r9 + 12]                ; the symbol
    test    r11d, r11d
    jz      .rela_next
    SYM     r11
    cmp     word [rax + 6], 0              ; SHN_UNDEF
    jne     .rela_next
    mov     rdx, [rel ub_imp_of]
    cmp     dword [rdx + r11*4], 0
    jne     .rela_next
    mov     rcx, [rel ub_nimp]
    mov     rdi, [rel ub_imp_sym]
    mov     [rdi + rcx*4], r11d
    inc     rcx
    mov     [rel ub_nimp], rcx
    mov     [rdx + r11*4], ecx
.rela_next:
    add     r9, 24
    dec     r10
    jmp     .rela
.ok:
    xor     eax, eax
.ret:
    ret

; ---- ub_layout ----------------------------------------------------------
; Each class on its own page, its sections in order and aligned; stubs at
; the end of text, slots at the end of rodata. Output: rax = EXIT_OK or an
; error. Clobbers rax-rdx, rsi, rdi, r8-r11.
ub_layout:
    xor     r10d, r10d                     ; r10 = the next free image offset
    xor     r11d, r11d                     ; r11 = the end of file-backed bytes
    mov     r9d, CL_TEXT                   ; r9 = the class
.class:
    cmp     r9d, CL_BSS
    ja      .classes_done
    mov     rdi, r10
    mov     ecx, UBF_PAGE
    ALIGNUP rdi, rcx                       ; rdi = the class's start
    mov     rsi, rdi                       ; rsi = the cursor
    xor     r8d, r8d
.sec:
    inc     r8
    cmp     r8, [rel ub_shnum]
    jae     .secs_done
    lea     rax, [rel ub_class]
    cmp     byte [rax + r8], r9b
    jne     .sec
    SHDR    r8
    mov     rcx, [rax + 48]                ; sh_addralign
    cmp     rcx, 1
    jbe     .aligned
    ALIGNUP rsi, rcx
.aligned:
    lea     rcx, [rel ub_base]
    mov     [rcx + r8*8], rsi
    add     rsi, [rax + 32]                ; sh_size
    jmp     .sec
.secs_done:
    ; the stubs (text) and the slots (rodata)
    mov     rcx, [rel ub_nimp]
    test    rcx, rcx
    jz      .no_imports
    cmp     r9d, CL_TEXT
    je      .stubs
    cmp     r9d, CL_RODATA
    jne     .no_imports
    add     rsi, 7
    and     rsi, -8
    mov     [rel ub_slots], rsi
    shl     rcx, 3
    add     rsi, rcx
    jmp     .no_imports
.stubs:
    add     rsi, 7
    and     rsi, -8
    mov     [rel ub_stubs], rsi
    shl     rcx, 3
    add     rsi, rcx
.no_imports:
    lea     rax, [rel ub_start]
    mov     [rax + r9*8], rdi
    mov     rcx, rsi
    sub     rcx, rdi
    lea     rax, [rel ub_size]
    mov     [rax + r9*8], rcx
    test    rcx, rcx
    jz      .class_next                    ; empty: no segment, no page
    mov     r10, rsi
    cmp     r9d, CL_BSS
    je      .class_next
    mov     r11, rsi
.class_next:
    inc     r9d
    jmp     .class
.classes_done:
    mov     ecx, UBF_PAGE
    ALIGNUP r10, rcx
    mov     [rel ub_mem], r10
    mov     [rel ub_fbend], r11
    cmp     r10, UBF_MAX_MEM
    ja      .too_big
    xor     eax, eax
    ret
.too_big:
    mov     eax, EXIT_UBF_TOO_BIG
    ret

; ---- ub_build_image -----------------------------------------------------
; The file-backed part of the image: each section's bytes at its offset,
; then the stubs. Output: rax = EXIT_OK or an error. Clobbers rax-rdx, rsi,
; rdi, r8.
ub_build_image:
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, [rel ub_fbend]
    add     rsi, 16
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel ub_img], rdx
    xor     r8d, r8d
.sec:
    inc     r8
    cmp     r8, [rel ub_shnum]
    jae     .stubs
    lea     rax, [rel ub_class]
    movzx   ecx, byte [rax + r8]
    cmp     ecx, CL_NONE
    je      .sec
    cmp     ecx, CL_BSS
    je      .sec
    SHDR    r8
    cmp     dword [rax + 4], SHT_NOBITS
    je      .sec
    mov     rcx, [rax + 32]                ; sh_size
    mov     rsi, [rax + 24]
    add     rsi, [rel ub_in]
    lea     rdx, [rel ub_base]
    mov     rdi, [rdx + r8*8]
    add     rdi, [rel ub_img]
    rep     movsb
    jmp     .sec
.stubs:
    ; stub k: FF 25 (slot k - (stub k + 6)) CC CC
    xor     ecx, ecx
.stub:
    cmp     rcx, [rel ub_nimp]
    jae     .ok
    mov     rdi, rcx
    shl     rdi, 3
    mov     rax, [rel ub_slots]
    add     rax, rdi
    add     rdi, [rel ub_stubs]            ; rdi = stub k's image offset
    sub     rax, rdi
    sub     rax, 6                         ; the displacement
    add     rdi, [rel ub_img]
    mov     word [rdi], 0x25FF
    mov     [rdi + 2], eax
    mov     word [rdi + 6], 0xCCCC
    inc     rcx
    jmp     .stub
.ok:
    xor     eax, eax
.ret:
    ret

; ---- ub_relocate --------------------------------------------------------
; Every relocation of a loaded section, resolved into the image; the
; ABS64 ones also recorded. Output: rax = EXIT_OK or an error. Clobbers
; everything but rbx, r12-r15 (saved).
ub_relocate:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    ; room for every relocation as an ABS64 entry
    xor     ecx, ecx
    xor     r8d, r8d
.count:
    inc     r8
    cmp     r8, [rel ub_shnum]
    jae     .counted
    SHDR    r8
    cmp     dword [rax + 4], SHT_RELA
    jne     .count
    add     rcx, [rax + 32]
    jmp     .count
.counted:
    shr     rcx, 2                         ; 4 bytes per 24-byte entry: / 6 needed
    lea     rsi, [rcx + 16]
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel ub_rel], rdx
    mov     qword [rel ub_nrel], 0

    xor     r12d, r12d                     ; r12 = the RELA section
.sec:
    inc     r12
    cmp     r12, [rel ub_shnum]
    jae     .ok
    SHDR    r12
    cmp     dword [rax + 4], SHT_RELA
    jne     .sec
    mov     r13d, [rax + 44]               ; r13 = the relocated section
    lea     rcx, [rel ub_class]
    movzx   ecx, byte [rcx + r13]
    cmp     ecx, CL_NONE
    je      .sec
    mov     r14, [rax + 24]
    add     r14, [rel ub_in]               ; r14 = the entries
    push    rax
    push    rcx
    mov     rax, [rax + 32]
    call    ub_div24
    mov     r15, rax                       ; r15 = their count
    pop     rcx
    pop     rax
    cmp     ecx, CL_BSS
    jne     .rela
    test    r15, r15
    jnz     .bad_reloc_sec                 ; nothing to patch in bss
.rela:
    test    r15, r15
    jz      .sec
    ; P = the field's image offset, rdi = its address
    lea     rax, [rel ub_base]
    mov     rbx, [rax + r13*8]
    add     rbx, [r14]                     ; rbx = P
    mov     rdi, rbx
    add     rdi, [rel ub_img]
    mov     r9, [r14 + 16]                 ; r9 = A
    mov     r10d, [r14 + 8]                ; r10 = the type
    mov     r11d, [r14 + 12]               ; r11 = the symbol
    ; what the symbol is: r8 = 0 label (S image-relative), 1 absolute,
    ; 2 import (rdx = its index); rsi = S
    xor     esi, esi
    mov     r8d, 1
    test    r11d, r11d
    jz      .have_sym
    SYM     r11
    movzx   ecx, word [rax + 6]            ; st_shndx
    mov     rsi, [rax + 8]                 ; st_value
    test    ecx, ecx
    jz      .is_import
    cmp     ecx, SHN_ABS
    je      .have_sym
    cmp     ecx, SHN_COMMON
    je      .bad_reloc
    cmp     rcx, [rel ub_shnum]
    jae     .bad_reloc
    lea     rdx, [rel ub_class]
    cmp     byte [rdx + rcx], CL_NONE
    je      .bad_reloc                     ; a section that is not loaded
    lea     rdx, [rel ub_base]
    add     rsi, [rdx + rcx*8]
    xor     r8d, r8d
    jmp     .have_sym
.is_import:
    mov     rdx, [rel ub_imp_of]
    mov     edx, [rdx + r11*4]
    dec     edx
    mov     r8d, 2
.have_sym:
    cmp     r10d, 1                        ; R_X86_64_64
    je      .r64
    cmp     r10d, 2                        ; PC32
    je      .pc32
    cmp     r10d, 4                        ; PLT32
    je      .pc32
    cmp     r10d, 9                        ; GOTPCREL
    je      .gotpc
    cmp     r10d, 41                       ; GOTPCRELX
    je      .gotpc
    cmp     r10d, 42                       ; REX_GOTPCRELX
    je      .gotpc
    cmp     r10d, 24                       ; PC64
    je      .pc64
    cmp     r10d, 13                       ; PC16
    je      .pc16
    cmp     r10d, 15                       ; PC8
    je      .pc8
    cmp     r10d, 10                       ; 32
    je      .abs32
    cmp     r10d, 11                       ; 32S
    je      .abs32
    cmp     r10d, 12                       ; 16
    je      .abs16
    cmp     r10d, 14                       ; 8
    je      .abs8
    jmp     .bad_reloc

.r64:
    cmp     r8d, 2
    je      .bad_import_data
    lea     rax, [rsi + r9]
    mov     [rdi], rax
    test    r8d, r8d
    jnz     .rela_next                     ; an absolute value: as it is
    mov     rax, [rel ub_nrel]
    mov     rcx, [rel ub_rel]
    mov     [rcx + rax*4], ebx
    inc     rax
    mov     [rel ub_nrel], rax
    jmp     .rela_next

.pc32:
    cmp     r8d, 1
    je      .bad_reloc                     ; relative to an absolute value
    cmp     r8d, 2
    jne     .pc32_target
    mov     rsi, rdx                       ; an import: its stub
    shl     rsi, 3
    add     rsi, [rel ub_stubs]
.pc32_target:
    lea     rax, [rsi + r9]
    sub     rax, rbx
    movsxd  rcx, eax
    cmp     rcx, rax
    jne     .bad_reloc                     ; out of 32-bit reach
    mov     [rdi], eax
    jmp     .rela_next

.gotpc:
    cmp     r8d, 2
    jne     .bad_reloc                     ; a GOT entry for a label: none
    mov     rax, rdx
    shl     rax, 3
    add     rax, [rel ub_slots]
    add     rax, r9
    sub     rax, rbx
    mov     [rdi], eax
    jmp     .rela_next

.pc64:
    test    r8d, r8d
    jnz     .bad_reloc
    lea     rax, [rsi + r9]
    sub     rax, rbx
    mov     [rdi], rax
    jmp     .rela_next

.pc16:
    test    r8d, r8d
    jnz     .bad_reloc
    lea     rax, [rsi + r9]
    sub     rax, rbx
    movsx   rcx, ax
    cmp     rcx, rax
    jne     .bad_reloc
    mov     [rdi], ax
    jmp     .rela_next

.pc8:
    test    r8d, r8d
    jnz     .bad_reloc
    lea     rax, [rsi + r9]
    sub     rax, rbx
    movsx   rcx, al
    cmp     rcx, rax
    jne     .bad_reloc
    mov     [rdi], al
    jmp     .rela_next

.abs32:
    cmp     r8d, 1
    jne     .bad_abs32                     ; a label: moves with the image
    lea     rax, [rsi + r9]
    mov     [rdi], eax
    jmp     .rela_next
.abs16:
    cmp     r8d, 1
    jne     .bad_abs32
    lea     rax, [rsi + r9]
    mov     [rdi], ax
    jmp     .rela_next
.abs8:
    cmp     r8d, 1
    jne     .bad_abs32
    lea     rax, [rsi + r9]
    mov     [rdi], al

.rela_next:
    add     r14, 24
    dec     r15
    jmp     .rela

.ok:
    xor     eax, eax
    jmp     .ret
.bad_reloc_sec:
    mov     r11d, [r14 + 12]
.bad_reloc:
    mov     r12d, EXIT_UBF_RELOC
    jmp     .bad_sym
.bad_abs32:
    mov     r12d, EXIT_UBF_ABS32
    jmp     .bad_sym
.bad_import_data:
    mov     r12d, EXIT_UBF_IMPORT_DATA
.bad_sym:
    mov     rdi, r11
    call    ub_sym_name
    mov     rdi, rax
    call    error_set_subject
    mov     eax, r12d
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- ub_div24 -----------------------------------------------------------
; rax = a table's size -> rax = its entries of 24 bytes. Clobbers rcx, rdx.
ub_div24:
    xor     edx, edx
    mov     ecx, 24
    div     rcx
    ret

; ---- ub_sym_name --------------------------------------------------------
; rdi = a symbol -> rax = its name (a section symbol's: its section's).
; Clobbers rax, rcx.
ub_sym_name:
    SYM     rdi
    mov     ecx, [rax]                     ; st_name
    test    ecx, ecx
    jz      .section
    mov     rax, [rel ub_strs]
    add     rax, rcx
    ret
.section:
    movzx   ecx, word [rax + 6]
    cmp     rcx, [rel ub_shnum]
    jae     .none
    SHDR    rcx
    mov     ecx, [rax]                     ; sh_name
    mov     rax, [rel ub_names]
    add     rax, rcx
    ret
.none:
    lea     rax, [rel ub_empty]
    ret

; ---- ub_is_export -------------------------------------------------------
; rax = a symbol -> ZF clear when it is exported: a global (or weak),
; defined in a loaded section, not a section or file symbol. Clobbers rcx.
ub_is_export:
    movzx   ecx, byte [rax + 4]            ; st_info
    shr     ecx, 4
    cmp     ecx, STB_GLOBAL
    je      .binding_ok
    cmp     ecx, STB_WEAK
    jne     .no
.binding_ok:
    movzx   ecx, byte [rax + 4]
    and     ecx, 15
    cmp     ecx, 3                         ; STT_SECTION
    je      .no
    cmp     ecx, 4                         ; STT_FILE
    je      .no
    movzx   ecx, word [rax + 6]
    test    ecx, ecx
    jz      .no
    cmp     rcx, [rel ub_shnum]
    jae     .no
    push    rdx
    lea     rdx, [rel ub_class]
    cmp     byte [rdx + rcx], CL_NONE
    pop     rdx
    je      .no
    or      ecx, 1                         ; ZF clear
    ret
.no:
    xor     ecx, ecx                       ; ZF set
    ret

; ---- ub_find_entry ------------------------------------------------------
; ub_entry = the image offset of `_start`, else `main`, defined in text;
; -1 when neither is. Clobbers rax-rdx, rsi, rdi, r8.
ub_find_entry:
    lea     r9, [rel ub_name_start]
    call    .find
    cmp     qword [rel ub_entry], -1
    jne     .ret
    lea     r9, [rel ub_name_main]
    call    .find
.ret:
    ret
.find:
    mov     qword [rel ub_entry], -1
    xor     r8d, r8d
.sym:
    inc     r8
    cmp     r8, [rel ub_nsym]
    jae     .not_found
    SYM     r8
    movzx   ecx, word [rax + 6]
    test    ecx, ecx
    jz      .sym
    cmp     rcx, [rel ub_shnum]
    jae     .sym
    lea     rdx, [rel ub_class]
    cmp     byte [rdx + rcx], CL_TEXT
    jne     .sym
    mov     edx, [rax]
    test    edx, edx
    jz      .sym
    mov     rsi, [rel ub_strs]
    add     rsi, rdx
    mov     rdi, r9
.cmp:
    mov     dl, [rsi]
    cmp     dl, [rdi]
    jne     .sym
    inc     rsi
    inc     rdi
    test    dl, dl
    jnz     .cmp
    mov     rdx, [rax + 8]                 ; found
    lea     rsi, [rel ub_base]
    add     rdx, [rsi + rcx*8]
    mov     [rel ub_entry], rdx
.not_found:
    ret

; ---- ub_fnv -------------------------------------------------------------
; rsi = a NUL-terminated name -> eax = its FNV-1a 32-bit hash, rcx = its
; length. Clobbers rdx.
ub_fnv:
    mov     eax, 0x811C9DC5
    xor     ecx, ecx
.byte:
    movzx   edx, byte [rsi + rcx]
    test    edx, edx
    jz      .done
    xor     eax, edx
    imul    eax, eax, 0x01000193
    inc     rcx
    jmp     .byte
.done:
    ret

; ---- ub_write -----------------------------------------------------------
; The UBF file in ub_out / ub_outlen. Output: rax = EXIT_OK or an error.
; Clobbers everything but rbx, r12-r15 (saved).
ub_write:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; the exports, and the string table's size: "" at 0, then each name
    mov     qword [rel ub_nexp], 0
    mov     r13, 1                         ; r13 = string table size
    xor     r8d, r8d
.imp_len:
    cmp     r8, [rel ub_nimp]
    jae     .imp_len_done
    mov     rax, [rel ub_imp_sym]
    mov     edi, [rax + r8*4]
    call    ub_sym_name
    mov     rsi, rax
    call    ub_fnv
    lea     r13, [r13 + rcx + 1]
    inc     r8
    jmp     .imp_len
.imp_len_done:
    xor     r8d, r8d
.exp_len:
    inc     r8
    cmp     r8, [rel ub_nsym]
    jae     .exp_len_done
    SYM     r8
    call    ub_is_export
    jz      .exp_len
    inc     qword [rel ub_nexp]
    mov     edi, r8d
    call    ub_sym_name
    mov     rsi, rax
    call    ub_fnv
    lea     r13, [r13 + rcx + 1]
    jmp     .exp_len
.exp_len_done:
    mov     [rel ub_strsize], r13

    ; the file's layout
    xor     r12d, r12d                     ; r12 = segments
    mov     ecx, CL_TEXT
.nseg:
    lea     rax, [rel ub_size]
    cmp     qword [rax + rcx*8], 0
    je      .nseg_next
    inc     r12
.nseg_next:
    inc     ecx
    cmp     ecx, CL_BSS
    jbe     .nseg
    mov     r14, UBF_HEADER                ; r14 = the cursor
    mov     [rel .seg_off], r14
    mov     rax, r12
    shl     rax, 5
    add     r14, rax
    mov     [rel .rel_off], r14
    mov     rax, [rel ub_nrel]
    lea     r14, [r14 + rax*8]
    mov     [rel .imp_off], r14
    mov     rax, [rel ub_nimp]
    shl     rax, 4
    add     r14, rax
    mov     [rel .exp_off], r14
    mov     rax, [rel ub_nexp]
    shl     rax, 4
    add     r14, rax
    mov     [rel .str_off], r14
    add     r14, r13
    ; each file-backed segment, 16-aligned
    mov     ecx, CL_TEXT
.data_off:
    add     r14, 15
    and     r14, -16
    lea     rax, [rel .file_off]
    mov     [rax + rcx*8], r14
    cmp     ecx, CL_BSS
    je      .data_next
    lea     rax, [rel ub_size]
    add     r14, [rax + rcx*8]
.data_next:
    inc     ecx
    cmp     ecx, CL_BSS
    jbe     .data_off
    mov     [rel ub_outlen], r14
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    mov     rsi, r14
    add     rsi, 16
    call    arena_alloc                    ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel ub_out], rdx
    mov     rbx, rdx                       ; rbx = the file

    ; ---- the header ----
    mov     dword [rbx], UBF_MAGIC_V
    mov     word [rbx + 4], 1              ; version
    mov     word [rbx + 6], UBF_HEADER
    mov     word [rbx + 8], 2              ; kind: a library ...
    mov     word [rbx + 10], 1             ; arch: x86-64
    mov     rax, [rel ub_entry]
    cmp     rax, -1
    je      .no_entry
    mov     word [rbx + 8], 1              ; ... or an application
    mov     dword [rbx + 12], 1            ; flags: has an entry point
    mov     [rbx + 0x18], rax
.no_entry:
    mov     rax, [rel ub_mem]
    mov     [rbx + 0x10], rax
    mov     [rbx + 0x24], r12d             ; seg_count
    mov     rax, [rel .seg_off]
    mov     [rbx + 0x28], eax
    mov     rax, [rel .rel_off]
    mov     [rbx + 0x2C], eax
    mov     rax, [rel ub_nrel]
    mov     [rbx + 0x30], eax
    mov     rax, [rel .imp_off]
    mov     [rbx + 0x34], eax
    mov     rax, [rel ub_nimp]
    mov     [rbx + 0x38], eax
    mov     rax, [rel .exp_off]
    mov     [rbx + 0x3C], eax
    mov     rax, [rel ub_nexp]
    mov     [rbx + 0x40], eax
    mov     rax, [rel .str_off]
    mov     [rbx + 0x44], eax
    mov     [rbx + 0x48], r13d             ; strtab_size
    mov     rax, [rel ub_outlen]
    mov     [rbx + 0x50], eax              ; file_size

    ; ---- the segments ----
    mov     rdi, [rel .seg_off]
    add     rdi, rbx
    mov     ecx, CL_TEXT
.seg:
    lea     rax, [rel ub_size]
    mov     rdx, [rax + rcx*8]
    test    rdx, rdx
    jz      .seg_next
    mov     [rdi], ecx                     ; type
    lea     rax, [rel ub_prot]
    movzx   eax, byte [rax + rcx]
    mov     [rdi + 4], eax                 ; prot
    lea     rax, [rel ub_start]
    mov     rax, [rax + rcx*8]
    mov     [rdi + 0x10], rax              ; mem_off
    mov     [rdi + 0x18], rdx              ; mem_size
    cmp     ecx, CL_BSS
    je      .seg_bss
    lea     rax, [rel .file_off]
    mov     rax, [rax + rcx*8]
    mov     [rdi + 8], eax                 ; file_off
    mov     [rdi + 12], edx                ; file_size
    ; the bytes
    push    rcx
    push    rdi
    lea     rdi, [rbx + rax]
    lea     rax, [rel ub_start]
    mov     rsi, [rax + rcx*8]
    add     rsi, [rel ub_img]
    mov     rcx, rdx
    rep     movsb
    pop     rdi
    pop     rcx
.seg_bss:
    add     rdi, 32
.seg_next:
    inc     ecx
    cmp     ecx, CL_BSS
    jbe     .seg

    ; ---- the relocations ----
    mov     rdi, [rel .rel_off]
    add     rdi, rbx
    xor     ecx, ecx
    mov     rsi, [rel ub_rel]
.rel:
    cmp     rcx, [rel ub_nrel]
    jae     .rels_done
    mov     eax, [rsi + rcx*4]
    mov     [rdi], eax
    mov     dword [rdi + 4], 1             ; ABS64
    add     rdi, 8
    inc     rcx
    jmp     .rel
.rels_done:

    ; ---- the imports and exports, with their names ----
    mov     r15, [rel .str_off]
    add     r15, rbx                       ; r15 = the string table
    mov     r13d, 1                        ; r13 = the next name's offset
    mov     r14, [rel .imp_off]
    add     r14, rbx
    xor     r8d, r8d
.imp:
    cmp     r8, [rel ub_nimp]
    jae     .imps_done
    mov     rax, [rel ub_imp_sym]
    mov     edi, [rax + r8*4]
    push    rdi
    call    ub_sym_name
    mov     rsi, rax
    call    ub_fnv                         ; eax = hash, rcx = length
    mov     [r14], r13d                    ; name_off
    mov     [r14 + 4], eax                 ; hash
    mov     rax, r8
    shl     rax, 3
    add     rax, [rel ub_slots]
    mov     [r14 + 8], eax                 ; slot
    pop     rdi
    SYM     rdi
    xor     edx, edx
    movzx   eax, byte [rax + 4]
    shr     eax, 4
    cmp     eax, STB_WEAK
    jne     .imp_strong
    mov     edx, 1
.imp_strong:
    mov     [r14 + 12], edx                ; flags
    lea     rdi, [r15 + r13]
    inc     rcx
    add     r13, rcx
    rep     movsb                          ; the name and its NUL
    add     r14, 16
    inc     r8
    jmp     .imp
.imps_done:
    mov     r14, [rel .exp_off]
    add     r14, rbx
    xor     r8d, r8d
.exp:
    inc     r8
    cmp     r8, [rel ub_nsym]
    jae     .exps_done
    SYM     r8
    call    ub_is_export
    jz      .exp
    mov     rdx, [rax + 8]                 ; st_value
    movzx   ecx, word [rax + 6]
    lea     rax, [rel ub_base]
    add     rdx, [rax + rcx*8]
    mov     [r14 + 8], rdx                 ; offset
    mov     edi, r8d
    call    ub_sym_name
    mov     rsi, rax
    call    ub_fnv
    mov     [r14], r13d
    mov     [r14 + 4], eax
    lea     rdi, [r15 + r13]
    inc     rcx
    add     r13, rcx
    rep     movsb
    add     r14, 16
    jmp     .exp
.exps_done:

    ; ---- the digest, over the whole file with its field zero ----
    mov     rdi, rbx
    mov     rsi, [rel ub_outlen]
    lea     rdx, [rbx + 0x58]
    call    sha256_hash
    xor     eax, eax

.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
alignb 8
ub_write.seg_off:   resq 1
ub_write.rel_off:   resq 1
ub_write.imp_off:   resq 1
ub_write.exp_off:   resq 1
ub_write.str_off:   resq 1
ub_write.file_off:  resq 5

[SECTION .rodata]
ub_prot:        db 0, 5, 1, 3, 3    ; per class: R-X, R--, RW-, RW-
ub_name_start:  db "_start", 0
ub_name_main:   db "main", 0
ub_empty:       db 0
