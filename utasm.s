;
; ============================================
; File     : src/main.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

extern arena_init
extern arena_alloc
extern symbol_init
extern cli_parse
extern reloc_init
extern io_open
extern io_file_size
extern io_mmap
extern lexer_init
extern prep_init
extern parser_parse_instruction
extern asm_ctx_align
extern amd64_encode_instruction
extern aarch64_encode_instruction
extern riscv64_encode_instruction
extern linker_run
extern inspect_file
extern global_profstate

[SECTION .bss]
    align 64
    global global_arena
    global_arena: resb 64
    resb 1024
    global global_ctx
    global_ctx:   resb ASMCTX_SIZE
    resb 1024
    global global_lexer
    global_lexer: resb LEXER_SIZE
    resb 1024
    global global_prep
    global_prep:  resb PREP_SIZE
    resb 1024

[SECTION .text]
    global _start
    global print_str

_start:
    cld
    push    rbp
    mov     rbp, rsp
    and     rsp, -16               ; Align stack

    ; [rbp+8] is argc, [rbp+16] is argv[0]
    mov     r12, [rbp + 8]          ; r12 = argc
    lea     r13, [rbp + 16]         ; r13 = argv

    ; 1. Initialize Arena
    lea     rdi, [rel global_arena]
    mov     rsi, 0x20000000 ; 512MB (lazily mapped)
    call    arena_init
    test    rax, rax
    jnz     .exit_oom

    ; 2. Initialize Context
    lea     rbx, [rel global_ctx]
    lea     rax, [rel global_arena]
    mov     [rbx + ASMCTX_arena], rax
    mov     byte [rbx + ASMCTX_tag], TAG_ASM_CTX
    
    ; Allocate sections array (64 * 8 = 512 bytes)
    mov     rdi, rax               ; rdi = &global_arena
    mov     rsi, 512
    call    arena_alloc
    test    rax, rax
    jnz     .exit_oom
    mov     [rbx + ASMCTX_sections], rdx

    ; 3. Initialize Symbol Table
    mov     rdi, rbx
    call    symbol_init
    test    rax, rax
    jnz     .exit_error

    ; 4. Parse CLI
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    cli_parse
    test    rax, rax
    jnz     .show_usage

    test    dword [rbx + ASMCTX_flags], CTX_FLAG_SHOW_HELP
    jnz     .show_help
    test    dword [rbx + ASMCTX_flags], CTX_FLAG_SHOW_VERSION
    jnz     .show_version

    cmp     qword [rbx + ASMCTX_input], 0
    je      .show_usage

    ; 4.1 --inspect: print an existing ELF file instead of assembling
    cmp     byte [rbx + ASMCTX_inspect], 0
    jne     .inspect

    ; 4.5 Profiler start-up.
    ; Only initialised when --profile/-P is given: profiler_init is what sets
    ; PROFSTATE_enabled, and every profiler_start_phase/end_phase call checks
    ; that flag first. global_profstate lives in .bss, so when profiling is
    ; off the instrumentation below costs one predictable branch per call.
    test    dword [rbx + ASMCTX_flags], CTX_FLAG_PROFILE
    jz      .profiler_off
    mov     rdi, [rbx + ASMCTX_arena]
    extern  profiler_init
    call    profiler_init
    test    rax, rax
    jnz     .exit_error
.profiler_off:

    ; 5. Pipeline Setup
    mov     rdi, rbx
    call    reloc_init
    test    rax, rax
    jnz     .exit_error

    ; Open and Map
    mov     rdi, [rbx + ASMCTX_input]
    mov     rsi, 0
    xor     rdx, rdx
    call    io_open
    test    rax, rax
    jnz     .exit_io_error
    mov     r14, rdx                         ; fd

    mov     rdi, r14
    call    io_file_size
    mov     r15, rdx                         ; size

    xor     rdi, rdi
    mov     rsi, r15
    mov     rdx, 1 ; PROT_READ
    mov     rcx, 2 ; MAP_PRIVATE
    mov     r8, r14
    xor     r9, r9
    call    io_mmap
    test    rax, rax
    jnz     .exit_io_error
    mov     r14, rdx                         ; buffer (r14 now buffer, r15 size)

    ; Initialize Lexer
    lea     rdi, [rel global_lexer]
    mov     rsi, r14
    mov     rdx, r15
    mov     r8,  rbx
    mov     rcx, [rbx + ASMCTX_input]
    mov     r9,  [rbx + ASMCTX_arena]
    call    lexer_init
    test    rax, rax
    jnz     .exit_error

    ; Initialize Preprocessor
    lea     rdi, [rel global_prep]
    lea     rsi, [rel global_lexer]
    mov     rdx, rbx
    mov     rcx, [rbx + ASMCTX_arena]
    call    prep_init
    test    rax, rax
    jnz     .exit_error

    ; Code and data before any "section" directive go to .text, as in NASM
    mov     rdi, rbx
    extern  parser_default_section
    call    parser_default_section
    test    rax, rax
    jnz     .exit_error

    ; NASM's predefined macros (__NASM_MAJOR__, __OUTPUT_FORMAT__, ...)
    lea     rdi, [rel global_prep]
    extern  prep_predefine
    call    prep_predefine
    test    rax, rax
    jnz     .exit_error

.assembly_loop:
    ; PHASE_PARSER covers the whole frontend: the lexer and preprocessor are
    ; demand-driven from inside parser_parse_instruction, so this one span
    ; accounts for lexing, macro expansion and parsing together.
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_PARSER
    extern  profiler_start_phase
    call    profiler_start_phase

    lea     rdi, [rel global_prep]           ; parser_parse_instruction takes PrepState in RDI
    call    parser_parse_instruction
    push    rax
    push    rdx
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_PARSER
    extern  profiler_end_phase
    call    profiler_end_phase
    pop     rdx
    pop     rax

    test    rax, rax
    jnz     .error_in_parser
    
    test    rdx, rdx
    jz      .finish_assembly
    
    mov     r12, rdx                         ; r12 = INST*
    lea     rbx, [rel global_ctx]            ; Ensure rbx is global_ctx
    movzx   eax, byte [rbx + ASMCTX_target]

    ; Alignments
    cmp     eax, 1 ; AARCH64
    jne     .check_rv
    mov     rdi, rbx
    mov     rsi, 4
    call    asm_ctx_align
    jmp     .encode
.check_rv:
    cmp     eax, 3 ; RISCV64
    jne     .encode
    mov     rdi, rbx
    mov     rsi, 2
    call    asm_ctx_align

.encode:
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_ENCODER
    call    profiler_start_phase

    mov     rdi, rbx
    mov     rsi, r12
    movzx   rax, byte [rbx + ASMCTX_target]
    cmp     rax, 2 ; AMD64
    je      .call_amd64
    cmp     rax, 1 ; AARCH64
    je      .call_aarch64
    cmp     rax, 3 ; RISCV64
    je      .call_riscv64
    xor     rax, rax
    jmp     .check_enc

.call_amd64:
    call    amd64_encode_instruction
    jmp     .check_enc
.call_aarch64:
    call    aarch64_encode_instruction
    jmp     .check_enc
.call_riscv64:
    call    riscv64_encode_instruction

.check_enc:
    push    rax
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_ENCODER
    call    profiler_end_phase
    pop     rax

    test    rax, rax
    jnz     .error_in_encoder
    jmp     .assembly_loop

.finish_assembly:
    ; what needs the whole source read ("global f:function (size)")
    lea     rdi, [rel global_prep]
    extern  parser_finish
    call    parser_finish

    lea     rbx, [rel global_ctx]
    mov     rdi, rbx
    call    linker_run
    test    rax, rax
    jnz     .error_in_linker

    ; Profiler teardown. Both calls return immediately when profiling is off,
    ; so this needs no flag check of its own.
    lea     rdi, [rel global_profstate]
    extern  profiler_finalize
    call    profiler_finalize
    lea     rdi, [rel global_profstate]
    lea     rsi, [rel global_ctx]
    extern  profiler_report
    call    profiler_report

    xor     rax, rax
    jmp     .exit

.show_usage:
    mov     rdi, 1
    lea     rsi, [rel msg_usage]
    call    print_str
    mov     rax, 1
    jmp     .exit

.show_help:
    mov     rdi, 1
    lea     rsi, [rel msg_help]
    call    print_str
    xor     eax, eax
    jmp     .exit

.show_version:
    mov     rdi, 1
    lea     rsi, [rel msg_version]
    call    print_str
    xor     eax, eax
    jmp     .exit

.inspect:
    mov     rdi, [rbx + ASMCTX_input]
    movzx   esi, byte [rbx + ASMCTX_inspect]
    call    inspect_file
    test    rax, rax
    jz      .exit
    mov     r12, rax                ; exit with the specific error code

    ; utasm: cannot inspect '<file>': <reason>
    lea     r13, [rel msg_insp_nofile]
    cmp     r12, EXIT_FILE_NOT_FOUND
    je      .inspect_report
    lea     r13, [rel msg_insp_perm]
    cmp     r12, EXIT_FILE_PERM
    je      .inspect_report
    lea     r13, [rel msg_insp_fmt]
    cmp     r12, EXIT_INVALID_FORMAT
    je      .inspect_report
    lea     r13, [rel msg_insp_write]
    cmp     r12, EXIT_FILE_WRITE
    je      .inspect_report
    lea     r13, [rel msg_insp_other]
.inspect_report:
    mov     rdi, 2
    lea     rsi, [rel msg_insp_pre]
    call    print_str
    mov     rdi, 2
    mov     rsi, [rbx + ASMCTX_input]
    call    print_str
    mov     rdi, 2
    lea     rsi, [rel msg_insp_mid]
    call    print_str
    mov     rdi, 2
    mov     rsi, r13
    call    print_str
    mov     rax, r12
    jmp     .exit

.exit_oom:
    mov     rdi, 2
    lea     rsi, [rel msg_crit_init]
    call    print_str
    mov     rax, 2
    jmp     .exit

.exit_io_error:
    mov     rax, 3
    jmp     .exit

.error_in_encoder:
    mov     r15, rax
    mov     rdi, 2
    lea     rsi, [rel msg_encoder_err]
    call    print_str
    mov     rdi, 2
    mov     rsi, r15
    call    print_num
    
    ; Print " at "
    mov     rdi, 2
    lea     rsi, [rel msg_at]
    call    print_str
    
    ; Get current LexerState
    lea     rbx, [rel global_prep]
    mov     rbx, [rbx + PREP_lexer]
    
    ; Print filename if not NULL
    mov     rsi, [rbx + LEXER_file]
    test    rsi, rsi
    jz      .enc_no_file
    mov     rdi, 2
    call    print_str
    jmp     .enc_print_line_col
.enc_no_file:
    mov     rdi, 2
    lea     rsi, [rel msg_unknown_file]
    call    print_str

.enc_print_line_col:
    mov     rdi, 2
    lea     rsi, [rel msg_colon]
    call    print_str
    
    mov     esi, dword [rbx + LEXER_line]
    mov     rdi, 2
    call    print_num
    
    mov     rdi, 2
    lea     rsi, [rel msg_colon]
    call    print_str
    
    movzx   rsi, word [rbx + LEXER_col]
    mov     rdi, 2
    call    print_num
    
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    call    print_str
    mov     rax, 5
    jmp     .exit

.error_in_linker:
    mov     r15, rax
    mov     rdi, 2
    lea     rsi, [rel msg_linker_err]
    call    print_str
    mov     rdi, 2
    mov     rsi, r15
    call    print_num
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    call    print_str
    mov     rax, 6
    jmp     .exit

.error_in_parser:
    mov     r15, rax                         ; Preserve error code in r15

    ; %fatal has printed its own message: nothing to add
    cmp     rax, EXIT_FATAL
    jne     .report_parser_error
    mov     rax, 4
    jmp     .exit
.report_parser_error:
    
    ; Print: "Parser error: "
    mov     rdi, 2
    lea     rsi, [rel msg_parser_err]
    call    print_str
    
    ; Print the error code
    mov     rdi, 2
    mov     rsi, r15
    call    print_num
    
    ; Print " at "
    mov     rdi, 2
    lea     rsi, [rel msg_at]
    call    print_str
    
    ; Get current LexerState
    lea     rbx, [rel global_prep]           ; rbx = PrepState
    mov     rbx, [rbx + PREP_lexer]          ; rbx = active LexerState
    
    ; Print filename if not NULL
    mov     rsi, [rbx + LEXER_file]
    test    rsi, rsi
    jz      .no_file
    mov     rdi, 2
    call    print_str
    jmp     .print_line_col
.no_file:
    mov     rdi, 2
    lea     rsi, [rel msg_unknown_file]
    call    print_str

.print_line_col:
    ; Print ":"
    mov     rdi, 2
    lea     rsi, [rel msg_colon]
    call    print_str
    
    ; Print line number
    mov     esi, dword [rbx + LEXER_line]
    mov     rdi, 2
    call    print_num
    
    ; Print ":"
    mov     rdi, 2
    lea     rsi, [rel msg_colon]
    call    print_str
    
    ; Print column number
    movzx   rsi, word [rbx + LEXER_col]
    mov     rdi, 2
    call    print_num
    
    ; Print newline
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    call    print_str

    ; "hint: did you mean '...'?" if the parser found a close match
    extern  error_hint_flush
    call    error_hint_flush

    mov     rax, 4
    jmp     .exit

.exit_error:
    mov     rax, 1
.exit:
    mov     rdi, rax
    mov     rax, 60 ; SYS_EXIT
    syscall

global print_str
print_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rsi
    xor     rdx, rdx
.len_loop:
    cmp     byte [rdi + rdx], 0
    je      .len_done
    inc     rdx
    jmp     .len_loop
.len_done:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rax, 1 ; SYS_WRITE
    syscall
    pop     r12
    pop     rbx
    pop     rbp
    ret

global print_num
print_num:
    push    rbp
    mov     rbp, rsp
    push    rbx                     ; Preserve rbx
    push    r12                     ; Preserve r12
    sub     rsp, 32                 ; 32 bytes buffer
    
    mov     r12, rdi                ; r12 = fd
    mov     rax, rsi                ; rax = number
    lea     rcx, [rbp - 17]         ; pointer to end of buffer
    mov     byte [rcx], 0           ; null terminator
    
    mov     rsi, 10                 ; divisor
.loop:
    xor     rdx, rdx
    div     rsi                     ; rax = quotient, rdx = remainder
    add     dl, '0'
    dec     rcx
    mov     [rcx], dl
    test    rax, rax
    jnz     .loop
    
    ; Now rcx points to the start of the string
    mov     rdi, r12                ; fd
    mov     rsi, rcx                ; string pointer
    call    print_str
    
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

[SECTION .data]
    msg_usage:     db "Usage: utasm [options] <source.s>", 10, "Try 'utasm --help' for usage.", 10, 0
    ; One db line per help line: utasm's own assembler does not support
    ; backslash line continuation, so this text must not use it.
    msg_help:      db "utasm 0.1.0 - multi-architecture assembler and linker", 10, 10
                   db "Usage: utasm [options] <source.s>", 10
                   db "       utasm --inspect [--inspect-only <parts>] <file>", 10, 10
                   db "Options:", 10
                   db "  -f, --format <format>     elf64 (default), bin, ubf (a UBF boot image)", 10
                   db "  -o <file>                 output path (default: source.o / .bin / .ubf)", 10
                   db "  --ubf-add TYPE=FILE[@ADDR]  -f ubf: add a component (initrd, dtb,", 10
                   db "                            config, module, firmware) loaded at ADDR", 10
                   db "  -a, -arch, --arch <arch>  amd64 (default), aarch64, riscv64", 10
                   db "  --standalone              produce a standalone executable", 10
                   db "  --profile, -P             print internal compiler profile", 10
                   db "  --verbose                 enable verbose diagnostics", 10
                   db "  --color | --no-color      control diagnostic color", 10
                   db "  -Werror                   treat warnings as errors", 10
                   db "  -O0 | -O1 | -O2           jumps: as written | shortest, like NASM", 10
                   db "                            (default) | also remove and merge jumps", 10
                   db "  --inspect                 inspect an ELF file instead of assembling", 10
                   db "  --inspect-only <parts>    inspect only: header,sections,segments,", 10
                   db "                            symbols,relocs,all,disasm (comma-separated)", 10
                   db "  --disasm                  disassemble an ELF file's code (x86-64)", 10
                   db "  -h, --help                show this help", 10
                   db "  -v, --version             show version", 10, 0
    msg_insp_pre:   db "utasm: cannot inspect '", 0
    msg_insp_mid:   db "': ", 0
    msg_insp_nofile: db "no such file", 10, 0
    msg_insp_perm:  db "permission denied", 10, 0
    msg_insp_fmt:   db "not a valid ELF64 little-endian file", 10, 0
    msg_insp_write: db "error writing output", 10, 0
    msg_insp_other: db "could not read the file", 10, 0
    msg_version:   db "utasm 0.1.0", 10, 0
    msg_crit_init: db "CRITICAL: Initialization failed", 10, 0
    msg_parser_err:   db "Parser error: ", 0
    msg_encoder_err:  db "Encoder error: ", 0
    msg_linker_err:   db "Linker error: ", 0
    msg_at:           db " at ", 0
    msg_unknown_file: db "<unknown>", 0
    msg_colon:        db ":", 0
    msg_newline:      db 10, 0

