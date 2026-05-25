;
; ============================================================================
; File        : src/output/mapfile.s
; Project     : utasm
; Author      : Utkarsha Lab
; License     : Apache-2.0
; Description : Linker Map File Generator. 
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

extern io_write
extern io_open
extern io_close
extern str_len

[SECTION .text]

;*
; * [mapfile_generate]
; * Purpose: Dumps the symbol table into a .map file.
; ;
global mapfile_generate
mapfile_generate:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; RBX = AsmCtx
    
    ; 1. Open .map file
    ; For now, we use a fixed name "utasm.map" or derived from output
    mov     rdi, [rbx + ASMCTX_output] ; base name
    ; (In production we'd append .map here)
    lea     rdi, [str_map_name]
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    check_err
    mov     r12, rdx               ; R12 = FD
    
    ; Write Header
    mov     rdi, r12
    lea     rsi, [msg_header]
    call    io_write_str

    ; 2. Iterate Symbols
    mov     r13, [rbx + ASMCTX_symtab]
    mov     r14d, [rbx + ASMCTX_symcount]
    
.sym_loop:
    test    r14, r14
    jz      .done
    
    ; a. Print Hex Address
    mov     rax, [r13 + SYMBOL_value]
    ; Add section base address if applicable
    movzx   rcx, word [r13 + SYMBOL_section]
    ; (Logic for section base would go here, currently assume flat)
    
    mov     rdi, rax
    call    u64_to_hex             ; result in str_hex_buf
    
    mov     rdi, r12
    lea     rsi, [str_hex_buf]
    call    io_write_str
    
    call    write_tab
    
    ; b. Print Symbol Name
    mov     rdi, r12
    mov     rsi, [r13 + SYMBOL_name]
    call    io_write_str
    
    call    write_nl
    
    add     r13, SYMBOL_SIZE
    dec     r14
    jmp     .sym_loop

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

write_tab:
    mov     rdi, r12
    lea     rsi, [msg_tab]
    mov     rdx, 1
    call    io_write
    ret

write_nl:
    mov     rdi, r12
    lea     rsi, [msg_nl]
    mov     rdx, 1
    call    io_write
    ret

io_write_str:
    push    rdi
    mov     rdi, rsi
    call    str_len
    mov     rdx, rax
    pop     rdi
    call    io_write
    ret

;*
; * [u64_to_hex]
; * Converts RDI to a 16-char hex string in str_hex_buf.
; ;
u64_to_hex:
    push    rbx
    lea     rbx, [str_hex_buf + 15]
    mov     rcx, 16
.loop:
    mov     rax, rdi
    and     rax, 0xF
    cmp     al, 10
    jae     .letter
    add     al, '0'
    jmp     .store
.letter:
    add     al, 'A' - 10
.store:
    mov     [rbx], al
    dec     rbx
    shr     rdi, 4
    loop    .loop
    pop     rbx
    ret

[SECTION .data]
msg_tab:    db 9
msg_nl:     db 10
msg_header: db "Address            Symbol", 10
            db "--------------------------------", 10, 0
str_map_name: db "utasm.map", 0

[SECTION .bss]
str_hex_buf: resb 17
