;
; ============================================================================
; File        : src/linker/binary.s
; Project     : utasm
; Description : Flat binary emitter (-f bin).
;                Writes raw machine bytes with no ELF container.
;                Essential for OS bootloaders and bare-metal images.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

extern asmctx_get_section
extern reloc_apply_one
extern io_write
extern symbol_find

[SECTION .text]

; ============================================================================
; binary_emit
; ============================================================================
;
; binary_emit
; Writes assembled sections as a contiguous flat binary.
; Section order: .text then .data (no .bss â€” zero-filled at runtime).
; The caller is responsible for setting the correct ORG address by passing
; it as base_addr; this only affects relocation patching, not the output.

; Input  : rdi = pointer to AsmCtx
;            rsi = output file descriptor (i32, already opened for write)
;            rdx = base address (ORG value, 0x7C00 for bootloaders etc.)
; Output : rax = EXIT_OK or error code
;
global binary_emit
binary_emit:
    prologue
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi               ; r12 = AsmCtx
    mov     r13d, esi              ; r13d = fd
    mov     r14, rdx               ; r14 = base_addr (ORG)

    ; ---- 1. Apply relocations before writing ----
    mov     rdi, r12
    mov     rsi, r14
    call    binary_patch_relocs
    check_err

    ; ---- 2. Write .text section ----
    mov     rdi, r12
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    check_err
    mov     r15, rdx               ; r15 = SECTION* for .text

    mov     edi, r13d
    mov     rsi, [r15 + SECTION_data]
    mov     rdx, [r15 + SECTION_size]
    test    rdx, rdx
    jz      .write_data
    call    io_write
    check_err

.write_data:
    ; ---- 3. Write .data section ----
    mov     rdi, r12
    mov     rsi, SEC_DATA
    call    asmctx_get_section
    check_err
    mov     r15, rdx

    mov     edi, r13d
    mov     rsi, [r15 + SECTION_data]
    mov     rdx, [r15 + SECTION_size]
    test    rdx, rdx
    jz      .done
    call    io_write
    check_err

.error:
.done:
    xor     rax, rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    epilogue

; ============================================================================
; binary_patch_relocs
; ============================================================================
;
; binary_patch_relocs
; Applies all relocations in the AsmCtx reloc table directly into the
; in-memory .text buffer before it is flushed to disk.

; For flat binary output, all symbols must be defined (no external refs).
; Any unresolved symbol causes EXIT_UNDEF_REF.

; Input  : rdi = AsmCtx, rsi = base_addr (ORG)
; Output : rax = EXIT_OK or EXIT_UNDEF_REF
;
global binary_patch_relocs
binary_patch_relocs:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi               ; rbx = AsmCtx
    mov     r12, rsi               ; r12 = base_addr

    ; Get .text buffer base
    mov     rdi, rbx
    mov     rsi, SEC_TEXT
    call    asmctx_get_section
    check_err
    mov     r13, [rdx + SECTION_data]  ; r13 = .text buffer

    ; Walk reloc table
    mov     r14, [rbx + ASMCTX_relocs]
    mov     ecx, [rbx + ASMCTX_nrelocs]
    xor     r15d, r15d             ; index

.loop:
    cmp     r15d, ecx
    jge     .done

    mov     rdi, r15
    imul    rdi, RELOC_SIZE
    add     rdi, r14                       ; rdi = RELOC*

    ; resolve symbol value
    mov     rsi, [rdi + RELOC_sym]     ; symbol name ptr
    mov     rdi, rbx
    call    symbol_find
    test    rax, rax
    jnz     .undef                     ; symbol not found

    ; target_va = base_addr + symbol.value
    mov     rax, [rdx + SYMBOL_value]
    add     rax, r12                   ; absolute VA

    ; patch_va = base_addr + reloc.offset
    mov     rcx, [rdi + RELOC_offset]
    lea     rdx, [r13 + rcx]           ; patch_ptr (buffer)
    add     rcx, r12                   ; patch_va (absolute)

    ; Apply via unified helper
    mov     rsi, rax                   ; sym_va
    call    reloc_apply_one
    check_err

    inc     r15d
    jmp     .loop

.error:
.done:
    xor     rax, rax
    jmp     .ret

.undef:
    mov     rax, EXIT_UNDEF_REF

.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

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
