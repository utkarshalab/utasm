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
extern arena_alloc
extern print_str

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

    ; Defaults make the short, conventional invocation useful:
    ;     utasm source.s
    ; is equivalent to:
    ;     utasm -f elf64 -a amd64 source.s
    mov     byte [rbx + ASMCTX_fmt], FMT_ELF64
    mov     byte [rbx + ASMCTX_target], TARGET_AMD64
    and     dword [rbx + ASMCTX_flags], ~(CTX_FLAG_FORMAT_BIN | CTX_FLAG_FORMAT_ELF)
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_FORMAT_ELF
    lea     rax, [rel .default_output]
    mov     [rbx + ASMCTX_output], rax

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

    mov     rdi, r14
    lea     rsi, [rel .flag_help_short]
    call    str_cmp
    test    rax, rax
    jz      .handle_help

    mov     rdi, r14
    lea     rsi, [rel .flag_version]
    call    str_cmp
    test    rax, rax
    jz      .handle_version

    mov     rdi, r14
    lea     rsi, [rel .flag_version_short]
    call    str_cmp
    test    rax, rax
    jz      .handle_version

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

    mov     rdi, r14
    lea     rsi, [rel .flag_format_long]
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

    mov     rdi, r14
    lea     rsi, [rel .flag_arch_compat]
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
    lea     rsi, [rel .flag_verbose_long]
    call    str_cmp
    test    rax, rax
    jz      .handle_verbose

    ; check for --color
    mov     rdi, r14
    lea     rsi, [rel .flag_color]
    call    str_cmp
    test    rax, rax
    jz      .handle_color

    mov     rdi, r14
    lea     rsi, [rel .flag_no_color]
    call    str_cmp
    test    rax, rax
    jz      .handle_no_color

    ; check for -Werror
    mov     rdi, r14
    lea     rsi, [rel .flag_werror]
    call    str_cmp
    test    rax, rax
    jz      .handle_werror

    ; check for --profile
    mov     rdi, r14
    lea     rsi, [rel .flag_profile]
    call    str_cmp
    test    rax, rax
    jz      .handle_profile

    ; check for -P (short form of --profile)
    mov     rdi, r14
    lea     rsi, [rel .flag_profile_short]
    call    str_cmp
    test    rax, rax
    jz      .handle_profile

    ; If it starts with '-', it's an unknown flag
    cmp     byte [r14], '-'
    je      .unknown_flag

    ; Otherwise, it is the one permitted input file.
    cmp     qword [rbx + ASMCTX_input], 0
    jne     .too_many_inputs
    mov     [rbx + ASMCTX_input], r14
    
    jmp     .next_arg

.handle_help:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_SHOW_HELP
    xor     eax, eax
    jmp     .exit

.handle_version:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_SHOW_VERSION
    xor     eax, eax
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
    and     dword [rbx + ASMCTX_flags], ~(CTX_FLAG_FORMAT_BIN | CTX_FLAG_FORMAT_ELF)
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_FORMAT_ELF
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_RELOCATABLE
    jmp     .next_arg

.set_bin:
    mov     byte [rbx + ASMCTX_fmt], FMT_BIN
    and     dword [rbx + ASMCTX_flags], ~(CTX_FLAG_FORMAT_BIN | CTX_FLAG_FORMAT_ELF)
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_FORMAT_BIN
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_RELOCATABLE
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
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_NO_COLOR
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_COLOR
    jmp     .next_arg

.handle_no_color:
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_COLOR
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_NO_COLOR
    jmp     .next_arg

.handle_werror:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_WERROR
    jmp     .next_arg

.handle_standalone:
    mov     byte [rbx + ASMCTX_standalone], 1
    jmp     .next_arg

.handle_profile:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_PROFILE
    jmp     .next_arg

.next_arg:
    add     r13, 8
    dec     r12
    jmp     .loop

.done:
    ; Derive a useful object/binary filename only when the caller did not
    ; provide -o. Standalone ELF deliberately keeps the conventional a.out.
    cmp     qword [rbx + ASMCTX_input], 0
    je      .success
    lea     rax, [rel .default_output]
    cmp     [rbx + ASMCTX_output], rax
    jne     .success
    cmp     byte [rbx + ASMCTX_standalone], 0
    jne     .success
    mov     rdi, rbx
    call    cli_derive_output
    test    rax, rax
    jnz     .exit
.success:
    xor     rax, rax
    jmp     .exit

.unknown_flag:
    lea     rsi, [rel .msg_unknown_flag]
    jmp     .print_arg_error
.unknown_val:
    lea     rsi, [rel .msg_unknown_value]
    jmp     .print_arg_error
.missing_val:
    lea     rsi, [rel .msg_missing_value]
    jmp     .print_arg_error
.too_many_inputs:
    lea     rsi, [rel .msg_second_input]
    jmp     .print_arg_error

.print_arg_error:
    mov     rdi, 2
    call    print_str
    mov     rdi, 2
    mov     rsi, r14
    call    print_str
    mov     rdi, 2
    lea     rsi, [rel .msg_newline]
    call    print_str
    mov     rax, EXIT_USAGE
    jmp     .exit

; cli_derive_output
; Replaces the final source extension (after the final path separator) with
; .o for ELF or .bin for flat output. The result is arena-owned.
; Input: rdi = AsmCtx*
; Output: rax = EXIT_OK or EXIT_OOM
cli_derive_output:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     r12, rdi
    mov     r13, [r12 + ASMCTX_input]
    mov     r14, r13                ; scan pointer
    xor     r15d, r15d              ; last extension dot
.scan:
    mov     al, [r14]
    test    al, al
    jz      .scanned
    cmp     al, '/'
    je      .separator
    cmp     al, 92                  ; '\\'
    je      .separator
    cmp     al, '.'
    cmove   r15, r14
    inc     r14
    jmp     .scan
.separator:
    xor     r15d, r15d
    inc     r14
    jmp     .scan
.scanned:
    mov     rbx, r14                ; end pointer
    test    r15, r15
    cmovnz  rbx, r15                ; copy through final dot, if any
    sub     rbx, r13                ; base output length

    movzx   eax, byte [r12 + ASMCTX_fmt]
    cmp     eax, FMT_BIN
    jne     .elf_suffix
    lea     r15, [rel cli_parse.suffix_bin]
    mov     esi, 5                  ; ".bin" plus NUL
    jmp     .allocate
.elf_suffix:
    lea     r15, [rel cli_parse.suffix_obj]
    mov     esi, 3                  ; ".o" plus NUL
.allocate:
    add     rsi, rbx
    mov     rdi, [r12 + ASMCTX_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .done

    mov     rdi, rdx                ; destination
    mov     r8, rdx                 ; preserve result pointer
    mov     rsi, r13
    mov     rcx, rbx
    cld
    rep movsb
    mov     rsi, r15
.copy_suffix:
    lodsb
    stosb
    test    al, al
    jnz     .copy_suffix
    mov     [r12 + ASMCTX_output], r8
    xor     eax, eax
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

cli_parse.exit:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .rodata]
cli_parse.flag_help:    db "--help", 0
cli_parse.flag_help_short: db "-h", 0
cli_parse.flag_version: db "--version", 0
cli_parse.flag_version_short: db "-v", 0
cli_parse.flag_output:  db "-o", 0
cli_parse.flag_format:  db "-f", 0
cli_parse.flag_format_long: db "--format", 0
cli_parse.flag_arch:    db "-a", 0
cli_parse.flag_arch_long: db "--arch", 0
cli_parse.flag_arch_compat: db "-arch", 0
cli_parse.flag_standalone: db "--standalone", 0
cli_parse.flag_verbose_long: db "--verbose", 0
cli_parse.val_elf64:    db "elf64", 0
cli_parse.val_bin:      db "bin", 0
cli_parse.val_amd64:    db "amd64", 0
cli_parse.val_aarch64:  db "aarch64", 0
cli_parse.val_riscv64:  db "riscv64", 0

cli_parse.flag_color:   db "--color", 0
cli_parse.flag_no_color: db "--no-color", 0
cli_parse.flag_werror:  db "-Werror", 0
cli_parse.flag_profile: db "--profile", 0
cli_parse.flag_profile_short: db "-P", 0
cli_parse.default_output: db "a.out", 0
cli_parse.suffix_obj: db ".o", 0
cli_parse.suffix_bin: db ".bin", 0
cli_parse.msg_unknown_flag: db "utasm: unknown option: ", 0
cli_parse.msg_unknown_value: db "utasm: unknown option value: ", 0
cli_parse.msg_missing_value: db "utasm: missing value for option: ", 0
cli_parse.msg_second_input: db "utasm: only one input file is supported; second input: ", 0
cli_parse.msg_newline: db 10, 0
