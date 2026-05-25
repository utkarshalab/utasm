;
; ============================================
; File     : src/cli.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Command-line interface parser for utasm.
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern str_cmp

[SECTION .text]
    global cli_parse

; ---- cli_parse ---------------------------
;
; cli_parse
; Parses argc and argv and populates AsmCtx.
; Input    : rdi = pointer to AsmCtx
;             rsi = argc
;             rdx = argv (pointer to array of pointers)
; Output   : rax = EXIT_OK or EXIT_USAGE
; Clobbers : rcx, r8, r9, r10, r11
;
cli_parse:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi               ; rbx = AsmCtx
    mov     r12, rsi               ; r12 = argc
    mov     r13, rdx               ; r13 = argv

    ; skip argv[0] (program name)
    add     r13, 8
    dec     r12
    jle     .done                  ; no args provided

.loop:
    cmp     r12, 0
    jle     .done

    mov     r14, [r13]             ; r14 = current arg pointer
    test    r14, r14
    jz      .done
    
    ; check for help
    mov     rdi, r14
    lea     rsi, [rel .flag_help]
    call    str_cmp
    test    rax, rax
    jz      .handle_help

    ; check for -o
    mov     rdi, r14
    lea     rsi, [rel .flag_output]
    call    str_cmp
    test    rax, rax
    jz      .handle_output

    ; check for -f
    mov     rdi, r14
    lea     rsi, [rel .flag_format]
    call    str_cmp
    test    rax, rax
    jz      .handle_format

    ; check for -a / --arch
    mov     rdi, r14
    lea     rsi, [rel .flag_arch]
    call    str_cmp
    test    rax, rax
    jz      .handle_arch

    mov     rdi, r14
    lea     rsi, [rel .flag_arch_long]
    call    str_cmp
    test    rax, rax
    jz      .handle_arch

    ; check for --standalone
    mov     rdi, r14
    lea     rsi, [rel .flag_standalone]
    call    str_cmp
    test    rax, rax
    jz      .handle_standalone

    ; check for -v
    mov     rdi, r14
    lea     rsi, [rel .flag_verbose]
    call    str_cmp
    test    rax, rax
    jz      .handle_verbose

    ; check for --color
    mov     rdi, r14
    lea     rsi, [rel .flag_color]
    call    str_cmp
    test    rax, rax
    jz      .handle_color

    ; check for -Werror
    mov     rdi, r14
    lea     rsi, [rel .flag_werror]
    call    str_cmp
    test    rax, rax
    jz      .handle_werror

    ; check for --listing
    mov     rdi, r14
    lea     rsi, [rel .flag_listing]
    call    str_cmp
    test    rax, rax
    jz      .handle_listing

    ; If it starts with '-', it's an unknown flag
    cmp     byte [r14], '-'
    je      .unknown_flag

    ; Otherwise, assume it's the input file
    mov     [rbx + ASMCTX_input], r14
    
    jmp     .next_arg

.handle_help:
    mov     rax, EXIT_USAGE
    jmp     .exit

.handle_output:
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     rax, [r13]
    mov     [rbx + ASMCTX_output], rax
    jmp     .next_arg

.handle_format:
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     r14, [r13]
    
    mov     rdi, r14
    lea     rsi, [rel .val_elf64]
    call    str_cmp
    test    rax, rax
    jz      .set_elf64

    mov     rdi, r14
    lea     rsi, [rel .val_bin]
    call    str_cmp
    test    rax, rax
    jz      .set_bin
    
    jmp     .unknown_val

.set_elf64:
    mov     byte [rbx + ASMCTX_fmt], FMT_ELF64
    mov     byte [rbx + ASMCTX_target], TARGET_AMD64
    jmp     .next_arg

.set_bin:
    mov     byte [rbx + ASMCTX_fmt], FMT_BIN
    jmp     .next_arg

.handle_arch:
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     r14, [r13]
    
    mov     rdi, r14
    lea     rsi, [rel .val_amd64]
    call    str_cmp
    test    rax, rax
    jz      .set_amd64

    mov     rdi, r14
    lea     rsi, [rel .val_aarch64]
    call    str_cmp
    test    rax, rax
    jz      .set_aarch64

    mov     rdi, r14
    lea     rsi, [rel .val_riscv64]
    call    str_cmp
    test    rax, rax
    jz      .set_riscv64

    jmp     .unknown_val

.set_amd64:
    mov     byte [rbx + ASMCTX_target], TARGET_AMD64
    jmp     .next_arg

.set_aarch64:
    mov     byte [rbx + ASMCTX_target], TARGET_AARCH64
    jmp     .next_arg

.set_riscv64:
    mov     byte [rbx + ASMCTX_target], TARGET_RISCV64
    jmp     .next_arg

.handle_verbose:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_VERBOSE
    jmp     .next_arg

.handle_color:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_COLOR
    jmp     .next_arg

.handle_werror:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_WERROR
    jmp     .next_arg

.handle_standalone:
    mov     byte [rbx + ASMCTX_standalone], 1
    jmp     .next_arg

.handle_listing:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_LISTING
    jmp     .next_arg

.next_arg:
    add     r13, 8
    dec     r12
    jmp     .loop

.done:
    xor     rax, rax
    jmp     .exit

.unknown_flag:
.unknown_val:
.missing_val:
    mov     rax, EXIT_USAGE
    jmp     .exit

.exit:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .rodata]
    .flag_help:    db "--help", 0
    .flag_output:  db "-o", 0
    .flag_format:  db "-f", 0
    .flag_arch:    db "-a", 0
    .flag_arch_long: db "--arch", 0
    .flag_standalone: db "--standalone", 0
    .flag_verbose: db "-v", 0
    .val_elf64:    db "elf64", 0
    .val_bin:      db "bin", 0
    .val_amd64:    db "amd64", 0
    .val_aarch64:  db "aarch64", 0
    .val_riscv64:  db "riscv64", 0

    .flag_color:   db "--color", 0
    .flag_werror:  db "-Werror", 0
    .flag_listing: db "--listing", 0
