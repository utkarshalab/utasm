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
extern error_report_code
extern error_deferred
extern error_loc_file
extern global_profstate

[SECTION .bss]
    align 64
    global global_arena
    global_arena: resb 64
    resb 1024
    global global_ctx
    global_ctx:   resb ASMCTX_SIZE
    global utasm_envp
    utasm_envp:   resq 1            ; the environment (NAME=value strings)
    global utasm_argv
    utasm_argv:   resq 1            ; the command line
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

    ; a fault in utasm is reported as an internal error (core/crash.s)
    extern  crash_install
    call    crash_install

    ; [rbp+8] is argc, [rbp+16] is argv[0]
    mov     r12, [rbp + 8]          ; r12 = argc
    lea     r13, [rbp + 16]         ; r13 = argv
    ; the environment follows argv and its NULL (%ifenv)
    lea     rax, [r13 + r12*8 + 8]
    mov     [rel utasm_envp], rax
    mov     [rel utasm_argv], r13          ; to run again (core/known.s)
    extern  known_init
    call    known_init                     ; pass 2 of two?

    ; 1. Initialize Arena
    lea     rdi, [rel global_arena]
    mov     rsi, 0x200000000 ; 8GB reserved (MAP_NORESERVE: used pages only)
    call    arena_init
    test    rax, rax
    jnz     .exit_oom

    ; 2. Initialize Context
    lea     rbx, [rel global_ctx]
    lea     rax, [rel global_arena]
    mov     [rbx + ASMCTX_arena], rax
    mov     byte [rbx + ASMCTX_tag], TAG_ASM_CTX
    
    ; Allocate sections array: MAX_SECTIONS pointers, as many as
    ; asm_ctx_create_section allows (it was 64, and the 65th section wrote
    ; past it into what the arena handed out next). The arena commits the
    ; pages as they are used.
    mov     rdi, rax               ; rdi = &global_arena
    mov     rsi, MAX_SECTIONS * 8
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
    ; on a terminal, messages show the line and explain (error/format)
    extern  diag_init
    call    diag_init

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

    ; the source is the first file the output depends on (-M, -MD)
    lea     rbx, [rel global_ctx]
    mov     rdi, [rbx + ASMCTX_input]
    extern  deps_add
    call    deps_add

    ; -D, -U, -p, --before: read ahead of the source, as if included first
    extern  cli_prelude, cli_prelude_len, prep_push_buffer
    mov     edx, [rel cli_prelude_len]
    test    edx, edx
    jz      .no_prelude
    lea     rdi, [rel global_prep]
    lea     rsi, [rel cli_prelude]
    lea     rcx, [rel msg_cmdline]
    call    prep_push_buffer
    test    rax, rax
    jnz     .exit_error
.no_prelude:

    ; -E only runs the preprocessor (-M assembles, to see incbin too, but
    ; writes the dependencies instead of the output)
    extern  cli_mode
    cmp     byte [rel cli_mode], CLI_MODE_PREPROCESS
    je      .preprocess_only

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

    ; an error the preprocessor gave a caller that went on without it (it
    ; got an end of line instead): the one to report
    extern  prep_error_take
    mov     rcx, rax
    call    prep_error_take
    test    eax, eax
    jnz     .error_in_parser
    mov     rax, rcx

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
    extern  amd64_encode_tracked
    call    amd64_encode_tracked
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
    ; errors from here on come with the warnings (error/warnings.s)
    extern  warn_final
    mov     byte [rel warn_final], 1
    ; what needs the whole source read ("global f:function (size)")
    lea     rdi, [rel global_prep]
    extern  parser_finish
    call    parser_finish

    ; %error lines were reported as they were reached; no output after them
    cmp     dword [rel error_deferred], 0
    jne     .parser_failed

    ; what fails from here on belongs to no one line
    mov     qword [rel error_loc_file], 0

    ; -M: the files read are the dependencies; no output
    cmp     byte [rel cli_mode], CLI_MODE_DEPS
    jne     .link
    lea     rdi, [rel global_ctx]
    extern  cli_write_deps
    call    cli_write_deps
    test    rax, rax
    jnz     .error_in_linker
    xor     eax, eax
    jmp     .exit
.link:
    ; constants used before their definition: assemble again knowing them,
    ; as NASM's passes would (core/known.s); nothing is written before this
    lea     rdi, [rel global_ctx]
    extern  prep_unshadow
    call    prep_unshadow                  ; equ values a %define hid
    extern  known_second_pass
    call    known_second_pass
    test    rax, rax
    jnz     .error_in_parser               ; (one a second pass was to settle)

    extern  lst_close
    call    lst_close                      ; the listing's last line

    lea     rbx, [rel global_ctx]
    mov     rdi, rbx
    call    linker_run
    test    rax, rax
    jnz     .error_in_linker

    ; -MD: the dependencies, now that the output is written
    extern  cli_deps
    test    byte [rel cli_deps], CLI_DEPS_AFTER
    jz      .no_deps
    lea     rdi, [rel global_ctx]
    call    cli_write_deps
    test    rax, rax
    jnz     .error_in_linker
.no_deps:

    ; -l: the listing, with the final offsets and bytes
    extern  lst_file, lst_write
    cmp     qword [rel lst_file], 0
    je      .no_listing
    lea     rdi, [rel global_ctx]
    call    lst_write
    test    rax, rax
    jnz     .error_in_linker
.no_listing:

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

.preprocess_only:
    ; -E: the preprocessed source, on stdout or into the -o file
    mov     r12d, 1
    extern  cli_output_given
    cmp     byte [rel cli_output_given], 0
    je      .dump
    lea     rbx, [rel global_ctx]
    mov     rdi, [rbx + ASMCTX_output]
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .error_in_linker
    mov     r12d, edx
.dump:
    lea     rdi, [rel global_prep]
    mov     esi, r12d
    extern  prep_dump
    call    prep_dump
    test    rax, rax
    jnz     .error_in_parser
    cmp     dword [rel error_deferred], 0
    jne     .parser_failed
    xor     eax, eax
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
    ; "file:line: error: <message>" for the statement being encoded, and
    ; what its operands were (error/format/source.s)
    extern  diag_inst
    mov     [rel diag_inst], r12
    mov     r15, rax
    mov     edi, eax
    call    error_report_code
    mov     rax, EXIT_ENCODER_ERROR
    jmp     .exit

.error_in_linker:
    ; located errors (undefined symbols) are reported where they are found;
    ; what is left is about the program as a whole: "utasm: error: ..."
    mov     edi, eax
    call    error_report_code
    mov     rax, EXIT_LINKER_ERROR
    jmp     .exit

.error_in_parser:
    ; %fatal has printed its own message: nothing to add
    cmp     rax, EXIT_FATAL
    je      .parser_failed
    ; "file:line: error: <message>", then "hint: did you mean '...'?" if
    ; the parser found a close match
    mov     edi, eax
    call    error_report_code
.parser_failed:
    mov     rax, EXIT_PARSER_ERROR
    jmp     .exit


.exit_error:
    mov     rax, 1
.exit:
    extern  warn_flush
    call    warn_flush                     ; the warnings held
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
    ; a warning being written is held (error/warnings.s)
    cmp     rbx, 2
    jne     .write
    extern  stderr_hold, warn_hold_put
    cmp     byte [rel stderr_hold], 0
    je      .write
    mov     rdi, r12
    mov     rsi, rdx
    call    warn_hold_put
    jmp     .written
.write:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rax, 1 ; SYS_WRITE
    syscall
.written:
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
                   db "  -f, --format <format>     elf64 (default), elf32, bin, ubf (a UBF boot image)", 10
                   db "  -o <file>                 output path (default: source.o / .bin / .ubf)", 10
                   db "  --ubf-add TYPE=FILE[@ADDR]  -f ubf: add a component (initrd, dtb,", 10
                   db "                            config, module, firmware) loaded at ADDR", 10
                   db "  -a, -arch, --arch <arch>  amd64 (default), aarch64, riscv64", 10
                   db "  --standalone              produce a standalone executable", 10
                   db "  --profile, -P             print internal compiler profile", 10
                   db "  --verbose                 enable verbose diagnostics", 10
                   db "  --color | --no-color      control diagnostic color", 10
                   db "  -Werror                   treat warnings as errors", 10
                   db "  -I dir, -i dir            add an include search directory", 10
                   db "  -D name[=value], -U name  define / undefine a macro ahead of the source", 10
                   db "  -p file, --include file   include a file ahead of the source", 10
                   db "  --before text             a line ahead of the source", 10
                   db "  -E                        preprocess only (to stdout, or the -o file)", 10
                   db "  -l file                   write a listing (lines, offsets, bytes)", 10
                   db "  -g                        DWARF debug information (line table)", 10
                   db "  -M, -MD, -MF file, -MT t, -MQ t, -MP", 10
                   db "                            Makefile dependencies, as NASM writes them", 10
                   db "  -w+error                  warnings are errors (other -w/-W accepted)", 10
                   db "  -X gnu | -X vc            message style: file:line: | file(line) :", 10
                   db "  -s, -Z file               messages on stdout / into a file", 10
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
    msg_newline:      db 10, 0
    msg_cmdline:      db "command line", 0

