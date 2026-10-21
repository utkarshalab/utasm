;
; ============================================================================
; File        : src/object/elf/notes.s
; Project     : utasm
; Description : The note sections an ELF object can be asked for, which
;               NASM never writes (utasm's options):
;
;   --noexecstack   .note.GNU-stack (progbits, no flags): the program's
;                   stack need not be executable. With no such section,
;                   ld makes the stack executable ("missing
;                   .note.GNU-stack section implies executable stack").
;   --execstack     .note.GNU-stack with the executable flag: it must be.
;   --cet           .note.gnu.property: GNU_PROPERTY_X86_FEATURE_1_AND with
;                   IBT and SHSTK, as gcc -fcf-protection marks its
;                   objects - linked with others marked so, the program
;                   runs with indirect branch tracking and the shadow
;                   stack (its indirect targets begin with endbr64, its
;                   returns match its calls). One object without it turns
;                   both off for the whole program.
;
;   A section of that name the source made already is left as it is.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"

extern  asm_ctx_create_section
extern  asmctx_find_section
extern  asm_ctx_emit_dword
extern  coff_enabled
extern  elf32_enabled

[SECTION .bss]
global elf_gnu_stack, elf_cet
elf_gnu_stack:  resb 1              ; 1 --noexecstack, 2 --execstack
elf_cet:        resb 1              ; --cet: the features (IBT 1 | SHSTK 2)

[SECTION .rodata]
note_gnu_stack: db ".note.GNU-stack", 0
note_property:  db ".note.gnu.property", 0

[SECTION .text]

;*
; * [elf_add_notes]
; * Purpose: The note sections the options asked for, in an ELF object
; *   (not -f bin, -f win64 or a standalone executable).
; * Input  : RDI = AsmCtx
; * Output : RAX = OK or an error
; ;
global elf_add_notes
elf_add_notes:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    xor     eax, eax
    cmp     byte [rbx + ASMCTX_fmt], FMT_ELF64
    jne     .ret
    cmp     byte [rbx + ASMCTX_standalone], 0
    jne     .ret
    cmp     byte [rel coff_enabled], 0
    jne     .ret

    ; ---- .note.GNU-stack ----
    movzx   r12d, byte [rel elf_gnu_stack]
    test    r12d, r12d
    jz      .stack_done
    mov     rdi, rbx
    lea     rsi, [rel note_gnu_stack]
    call    asmctx_find_section
    test    rax, rax
    jz      .stack_done                    ; the source's own
    mov     rdi, rbx
    lea     rsi, [rel note_gnu_stack]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     word [rdx + SECTION_flags], 0
    cmp     r12d, 2
    jne     .stack_flags
    mov     word [rdx + SECTION_flags], SHF_EXECINSTR
.stack_flags:
    mov     qword [rdx + SECTION_align], 1
.stack_done:

    ; ---- .note.gnu.property ----
    movzx   r12d, byte [rel elf_cet]
    test    r12d, r12d
    jz      .ok
    mov     rdi, rbx
    lea     rsi, [rel note_property]
    call    asmctx_find_section
    test    rax, rax
    jz      .ok
    mov     rdi, rbx
    lea     rsi, [rel note_property]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     dword [r13 + SECTION_elf_type], 7       ; SHT_NOTE
    mov     word [r13 + SECTION_flags], SHF_ALLOC
    mov     qword [r13 + SECTION_align], 8
    cmp     byte [rel elf32_enabled], 0
    je      .property
    mov     qword [r13 + SECTION_align], 4
.property:
    ; the note: namesz 4, descsz, NT_GNU_PROPERTY_TYPE_0, "GNU", then the
    ; property GNU_PROPERTY_X86_FEATURE_1_AND: type, size 4, the features,
    ; padded to 8 bytes in a 64-bit object
    push    qword [rbx + ASMCTX_curr_sec]
    mov     [rbx + ASMCTX_curr_sec], r13
    mov     esi, 4
    call    .dword
    mov     esi, 16
    cmp     byte [rel elf32_enabled], 0
    je      .descsz
    mov     esi, 12
.descsz:
    call    .dword
    mov     esi, 5                         ; NT_GNU_PROPERTY_TYPE_0
    call    .dword
    mov     esi, 0x00554E47                ; "GNU\0"
    call    .dword
    mov     esi, 0xC0000002                ; GNU_PROPERTY_X86_FEATURE_1_AND
    call    .dword
    mov     esi, 4
    call    .dword
    mov     esi, r12d
    call    .dword
    cmp     byte [rel elf32_enabled], 0
    jne     .noted
    xor     esi, esi
    call    .dword
.noted:
    pop     qword [rbx + ASMCTX_curr_sec]
.ok:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; .dword: esi into the note
.dword:
    mov     rdi, rbx
    jmp     asm_ctx_emit_dword
