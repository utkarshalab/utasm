;
; ============================================================================
; File        : src/output/listing.s
; Project     : utasm
; Description : Listing File Generator. Produces human-readable .lst files.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

extern io_write
extern io_open
extern io_close
extern error_uint_to_str

[SECTION .text]

;*
; * [listing_generate]
; * Purpose: Iterates through all sections and produces a listing file.
; * Input:
; *   RDI: Pointer to AsmCtx
; * Output:
; *   RAX: EXIT_OK or error
; ;
global listing_generate
listing_generate:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; RBX = AsmCtx
    
    ; 1. Open listing file
    ; For now, use output_name + ".lst"
    mov     rdi, [rbx + ASMCTX_output]
    ; (Logic to append .lst would go here)
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    check_err
    mov     r12, rdx               ; R12 = FD
    
    ; 2. Write Header
    lea     rsi, [msg_header]
    mov     rdx, msg_header_len
    mov     rdi, r12
    call    io_write
    
    ; 3. Iterate Sections
    mov     r13, [rbx + ASMCTX_sections]
    movzx   r14, word [rbx + ASMCTX_seccount]
    
.section_loop:
    test    r14, r14
    jz      .done
    
    mov     r8, [r13]              ; R8 = SECTION*
    call    listing_write_section
    
    add     r13, 8
    dec     r14
    jmp     .section_loop

.error:
    mov     rax, EXIT_FILE_WRITE
.done:
    mov     rdi, r12
    call    io_close
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

listing_write_section:
    ; ... logic to format [ADDR] [HEX] ...
    ret

[SECTION .data]
msg_header:
    db "utasm Listing File", 10
    db "==================", 10, 0
msg_header_len equ $ - msg_header - 1
