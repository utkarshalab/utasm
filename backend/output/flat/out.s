;
; ============================================================================
; File        : src/linker/binary.s
; Project     : utasm
; Description : Flat binary emitter (-f bin).
;                Writes raw machine bytes with no ELF container.
;                Essential for OS bootloaders and bare-metal images.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

extern asmctx_get_section
extern reloc_apply_one
extern io_write
extern io_lseek
extern symbol_find

[SECTION .text]

; ============================================================================
; Flat binary layout
; ============================================================================
; Like NASM's bin format: the first section (.text) starts at the origin
; that "org" set (0 by default); every other section with contents follows
; in the order it was declared, aligned to its own alignment and at least 4
; bytes; .bss and other NOBITS sections come last and take no file space.
; binary_layout runs before relocations are resolved, so references between
; sections (lea rsi, [rel msg] into .data, dq label) get real addresses.

[SECTION .bss]
bin_origin: resq 1                  ; address of the first byte of the file

[SECTION .text]

;*
; * [binary_layout]
; * Purpose: Assign every section its address in the flat binary.
; * Input  : RDI = AsmCtx
; * Output : RAX = EXIT_OK
; ;
global binary_layout
binary_layout:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, [rbx + ASMCTX_sections]
    movzx   r13d, word [rbx + ASMCTX_seccount]
    xor     r14d, r14d                     ; cursor
    test    r13d, r13d
    jz      .done
    mov     rax, [r12]
    test    rax, rax
    jz      .done
    mov     r14, [rax + SECTION_addr]      ; the origin (org)
    mov     [rel bin_origin], r14
    xor     r8d, r8d                       ; 1 once a section has been placed
    xor     r15d, r15d                     ; pass 0: contents, pass 1: NOBITS
.pass:
    xor     ecx, ecx
.sec:
    cmp     ecx, r13d
    jae     .pass_done
    mov     rdx, [r12 + rcx*8]
    inc     ecx
    test    rdx, rdx
    jz      .sec
    xor     eax, eax
    cmp     dword [rdx + SECTION_elf_type], SHT_NOBITS
    sete    al
    cmp     eax, r15d
    jne     .sec                           ; not this pass
    cmp     qword [rdx + SECTION_size], 0
    jne     .place
    mov     [rdx + SECTION_addr], r14      ; empty: no space, no alignment
    jmp     .sec
.place:
    test    r8d, r8d
    jz      .at_cursor                     ; the first section is the origin
    mov     rax, [rdx + SECTION_align]
    cmp     rax, 4
    jae     .align
    mov     eax, 4
.align:
    lea     r9, [rax - 1]
    add     r14, r9
    not     r9
    and     r14, r9
.at_cursor:
    mov     [rdx + SECTION_addr], r14
    add     r14, [rdx + SECTION_size]
    mov     r8d, 1
    jmp     .sec
.pass_done:
    inc     r15d
    cmp     r15d, 2
    jb      .pass
.done:
    xor     eax, eax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; binary_emit
; ============================================================================
;
; binary_emit
; Writes every section with contents at its offset from the origin (see
; binary_layout); the gaps between them read as zeros. Relocations were
; already applied by reloc_resolve_all against the laid-out addresses.
;
; Input  : rdi = pointer to AsmCtx
;          rsi = output file descriptor (i32, already opened for write)
;          rdx = unused (the origin comes from "org")
; Output : rax = EXIT_OK or error code
;
global binary_emit
binary_emit:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r15d, esi                      ; fd
    mov     r12, [rbx + ASMCTX_sections]
    movzx   r13d, word [rbx + ASMCTX_seccount]
    xor     r14d, r14d
.sec:
    cmp     r14d, r13d
    jae     .ok
    mov     rdx, [r12 + r14*8]
    inc     r14d
    test    rdx, rdx
    jz      .sec
    cmp     dword [rdx + SECTION_elf_type], SHT_NOBITS
    je      .sec
    cmp     qword [rdx + SECTION_size], 0
    je      .sec
    push    rdx
    mov     edi, r15d
    mov     rsi, [rdx + SECTION_addr]
    sub     rsi, [rel bin_origin]
    xor     edx, edx                       ; SEEK_SET
    call    io_lseek
    pop     rdx
    test    rax, rax
    jnz     .ret
    mov     edi, r15d
    mov     rsi, [rdx + SECTION_data]
    mov     rdx, [rdx + SECTION_size]
    call    io_write
    test    rax, rax
    jnz     .ret
    jmp     .sec
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================================
; binary_emit_bootloader
; ============================================================================
;
; binary_emit_bootloader
; Convenience wrapper: emits flat binary with ORG=0x7C00 and appends the
; mandatory 0x55AA boot signature at offset 510.
; Used for writing MBR-bootable disk images.

; Input  : rdi = AsmCtx, rsi = fd
; Output : rax = EXIT_OK or error
;
global binary_emit_bootloader
binary_emit_bootloader:
    prologue
    push    r12
    push    r13

    mov     r12, rdi
    mov     r13d, esi

    ; Emit flat binary at ORG 0x7C00
    mov     rdx, 0x7C00
    call    binary_emit
    check_err

    ; Get .text size â€” must be <= 510 bytes for a valid MBR
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    check_err
    mov     rcx, [rdx + SECTION_size]

    ; Pad to 510 bytes if needed
    mov     rax, 510
    sub     rax, rcx
    jle     .write_sig             ; already 510 bytes (or over, error)

    ; Write (510 - size) zero bytes as padding
    mov     r10, rax               ; pad count
    sub     rsp, 512
.pad_loop:
    test    r10, r10
    jz      .write_sig
    mov     byte [rsp], 0
    mov     edi, r13d
    mov     rsi, rsp
    mov     rdx, 1
    call    io_write
    check_err
    dec     r10
    jmp     .pad_loop

.write_sig:
    add     rsp, 512
    ; Write 0xAA55 boot signature (little-endian: 0x55 then 0xAA)
    mov     word [rsp - 2], 0xAA55
    mov     edi, r13d
    lea     rsi, [rsp - 2]
    mov     rdx, 2
    call    io_write
    check_err

.error:
    xor     rax, rax
    pop     r13
    pop     r12
    epilogue
