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
%include "include/inspect.inc"

DEFAULT REL

extern str_cmp
extern arena_alloc
extern print_str
extern global_ctx

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
    mov     byte [rbx + ASMCTX_opt], OPT_BASIC      ; -O1: NASM-equivalent
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

    ; --bits 16|32|64: the mode the source starts in
    mov     rdi, r14
    lea     rsi, [rel .flag_bits]
    call    str_cmp
    test    rax, rax
    jz      .handle_bits

    ; --ubf-add TYPE=FILE[@ADDR]: another component of a UBF image
    mov     rdi, r14
    lea     rsi, [rel .flag_ubf_add]
    call    str_cmp
    test    rax, rax
    jz      .handle_ubf_add

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

    ; check for -O0 / -O1 / -O2 / -Ox
    cmp     byte [r14], '-'
    jne     .not_opt
    cmp     byte [r14 + 1], 'O'
    jne     .not_opt
    cmp     byte [r14 + 3], 0
    jne     .not_opt
    mov     al, [r14 + 2]
    cmp     al, '0'
    je      .opt_none
    cmp     al, '1'
    je      .opt_basic
    cmp     al, '2'
    je      .opt_size
    cmp     al, 'x'
    je      .opt_size
.not_opt:

    ; check for --inspect / --inspect-only <parts>
    mov     rdi, r14
    lea     rsi, [rel .flag_inspect]
    call    str_cmp
    test    rax, rax
    jz      .handle_inspect

    mov     rdi, r14
    lea     rsi, [rel .flag_inspect_only]
    call    str_cmp
    test    rax, rax
    jz      .handle_inspect_only

    ; check for --disasm (inspect: disassembly only)
    mov     rdi, r14
    lea     rsi, [rel .flag_disasm]
    call    str_cmp
    test    rax, rax
    jz      .handle_disasm

    ; NASM's options (-I, -D, -U, -p, -E, -M..., -w, -X, -s, -Z, ...)
    cmp     byte [r14], '-'
    jne     .not_nasm
    mov     rdi, r14
    xor     esi, esi
    cmp     r12, 1
    jle     .no_next
    mov     rsi, [r13 + 8]
.no_next:
    call    cli_nasm_option
    cmp     eax, 1
    je      .next_arg
    cmp     eax, 2
    je      .took_value
    cmp     eax, 3
    je      .missing_val
    cmp     eax, 4
    je      .unknown_val
.not_nasm:

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
    mov     byte [rel cli_output_given], 1
    jmp     .next_arg

.took_value:
    add     r13, 8                         ; the option's value
    dec     r12
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

    mov     rdi, r14
    lea     rsi, [rel .val_ubf]
    call    str_cmp
    test    rax, rax
    jz      .set_ubf

    mov     rdi, r14
    lea     rsi, [rel .val_elf32]
    call    str_cmp
    test    rax, rax
    jz      .set_elf32
    mov     rdi, r14
    lea     rsi, [rel .val_elf]
    call    str_cmp
    test    rax, rax
    jz      .set_elf32

    mov     rdi, r14
    lea     rsi, [rel .val_win64]
    call    str_cmp
    test    rax, rax
    jz      .set_win64

    jmp     .unknown_val

.set_win64:
    ; a COFF object for Windows (backend/output/coff/coff.s rewrites the
    ; ELF64 object), in bits 64
    extern  elf32_enabled, asm_bits, coff_enabled
    mov     byte [rel elf32_enabled], 0
    mov     byte [rel coff_enabled], 1
    mov     byte [rel asm_bits], 64
    jmp     .set_elf

.set_elf32:
    ; an i386 object (backend/output/elf/elf32.s), in bits 32 by default
    extern  elf32_enabled, asm_bits, coff_enabled
    mov     byte [rel elf32_enabled], 1
    mov     byte [rel coff_enabled], 0
    mov     byte [rel asm_bits], 32
    jmp     .set_elf
.set_elf64:
    extern  elf32_enabled, asm_bits, coff_enabled
    mov     byte [rel elf32_enabled], 0
    mov     byte [rel coff_enabled], 0
    mov     byte [rel asm_bits], 64
.set_elf:
    mov     byte [rbx + ASMCTX_fmt], FMT_ELF64
    and     dword [rbx + ASMCTX_flags], ~(CTX_FLAG_FORMAT_BIN | CTX_FLAG_FORMAT_ELF)
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_FORMAT_ELF
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_RELOCATABLE
    jmp     .next_arg

.set_ubf:
    ; a UBF boot image: laid out as a flat binary, written by ubf_emit
    extern  ubf_enabled
    mov     byte [rel ubf_enabled], 1
    jmp     .set_flat
.set_bin:
    extern  ubf_enabled
    mov     byte [rel ubf_enabled], 0
.set_flat:
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
    extern  diag_color
    mov     byte [rel diag_color], 1       ; messages: the rich form
    jmp     .next_arg

.handle_no_color:
    and     dword [rbx + ASMCTX_flags], ~CTX_FLAG_COLOR
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_NO_COLOR
    mov     byte [rel diag_color], 2       ; messages: NASM's lines only
    jmp     .next_arg

.handle_werror:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_WERROR
    jmp     .next_arg

.handle_standalone:
    mov     byte [rbx + ASMCTX_standalone], 1
    jmp     .next_arg

.handle_bits:
    ; the mode the source starts in, whatever the format's default (-f
    ; bin is 64-bit; NASM starts a flat binary in 16-bit mode)
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     r14, [r13]
    mov     al, 16
    cmp     word [r14], '16'
    je      .bits_two
    mov     al, 32
    cmp     word [r14], '32'
    je      .bits_two
    mov     al, 64
    cmp     word [r14], '64'
    jne     .unknown_val
.bits_two:
    cmp     byte [r14 + 2], 0
    jne     .unknown_val
    mov     [rel cli_bits], al
    jmp     .next_arg

.handle_ubf_add:
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     r14, [r13]
    mov     rdi, r14
    extern  ubf_add_component
    call    ubf_add_component
    test    rax, rax
    jnz     .unknown_val
    jmp     .next_arg

.handle_profile:
    or      dword [rbx + ASMCTX_flags], CTX_FLAG_PROFILE
    jmp     .next_arg

.next_arg:
    add     r13, 8
    dec     r12
    jmp     .loop

.opt_none:
    mov     byte [rbx + ASMCTX_opt], OPT_NONE
    jmp     .next_arg
.opt_basic:
    mov     byte [rbx + ASMCTX_opt], OPT_BASIC
    jmp     .next_arg
.opt_size:
    mov     byte [rbx + ASMCTX_opt], OPT_SIZE
    jmp     .next_arg

.handle_inspect:
    ; Keep a part list chosen by an earlier --inspect-only.
    cmp     byte [rbx + ASMCTX_inspect], 0
    jne     .next_arg
    mov     byte [rbx + ASMCTX_inspect], INSPECT_ALL
    jmp     .next_arg

.handle_disasm:
    or      byte [rbx + ASMCTX_inspect], INSPECT_DISASM
    jmp     .next_arg

.handle_inspect_only:
    dec     r12
    jle     .missing_val
    add     r13, 8
    mov     r14, [r13]
    mov     rdi, r14
    call    cli_parse_inspect_parts
    test    rax, rax
    jnz     .unknown_val
    mov     [rbx + ASMCTX_inspect], dl
    jmp     .next_arg

.done:
    ; --bits: the starting mode, over the format's default (whatever the
    ; order of -f and --bits)
    movzx   eax, byte [rel cli_bits]
    test    eax, eax
    jz      .bits_kept
    extern  asm_bits
    mov     [rel asm_bits], al
.bits_kept:
    ; Inspecting reads an existing file and writes nothing.
    cmp     byte [rbx + ASMCTX_inspect], 0
    jne     .success

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
    extern  ubf_enabled
    cmp     byte [rel ubf_enabled], 0
    je      .allocate
    lea     r15, [rel cli_parse.suffix_ubf]
    jmp     .allocate
.elf_suffix:
    lea     r15, [rel cli_parse.suffix_obj]
    mov     esi, 3                  ; ".o" plus NUL
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .allocate
    lea     r15, [rel cli_parse.suffix_coff]
    mov     esi, 5                  ; ".obj" plus NUL (NASM's for win64)
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

; cli_parse_inspect_parts
; Parses a comma-separated part list for --inspect-only, e.g.
; "header,symbols". Names: header, sections, segments, symbols, relocs,
; all. Empty items and unknown names are rejected.
; Input : rdi = NUL-terminated list
; Output: rax = EXIT_OK or EXIT_USAGE, rdx = INSPECT_* mask
cli_parse_inspect_parts:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                ; rbx = start of current item
    xor     r12d, r12d              ; r12 = mask

.item:
    mov     rcx, rbx                ; find the end of the item
.item_end:
    mov     al, [rcx]
    test    al, al
    jz      .have_item
    cmp     al, ','
    je      .have_item
    inc     rcx
    jmp     .item_end
.have_item:
    mov     r13, rcx                ; r13 = item end (',' or NUL)
    mov     rdx, rcx
    sub     rdx, rbx                ; rdx = item length
    jz      .bad                    ; empty item ("", "a,,b", "a,")

    lea     r8, [rel cli_inspect_part_table]
.entry:
    movzx   r9d, byte [r8]          ; part mask; 0 ends the table
    test    r9d, r9d
    jz      .bad
    lea     r10, [r8 + 1]           ; r10 = part name
    xor     ecx, ecx
.compare:
    cmp     rcx, rdx
    je      .compared
    mov     al, [rbx + rcx]
    cmp     al, [r10 + rcx]
    jne     .next_entry
    inc     rcx
    jmp     .compare
.compared:
    cmp     byte [r10 + rcx], 0     ; name must end exactly here
    jne     .next_entry
    or      r12d, r9d
    cmp     byte [r13], 0
    je      .ok
    lea     rbx, [r13 + 1]          ; skip the ','
    jmp     .item

.next_entry:
    mov     r8, r10
.skip_name:
    cmp     byte [r8], 0
    je      .skipped
    inc     r8
    jmp     .skip_name
.skipped:
    inc     r8                      ; past the NUL
    jmp     .entry

.ok:
    xor     eax, eax
    mov     edx, r12d
    jmp     .ret
.bad:
    mov     eax, EXIT_USAGE
    xor     edx, edx
.ret:
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

; ---- cli_nasm_option -------------------
;
; NASM's options:
;   -I dir, -i dir          include search directory (also -Idir)
;   -D name[=value], -d     %define name value, ahead of the source
;   -U name, -u             %undef name
;   -p file, --include file %include "file" ahead of the source
;   --before text           the line "text" ahead of the source
;   --pragma text           %pragma text
;   -E, -e                  preprocess only: the expanded source on stdout
;                           (or into the -o file)
;   -M, -MG                 Makefile dependencies on stdout, no assembly
;   -MD                     the dependencies too, after assembling
;   -MF file                where they go; -MT / -MQ target: the rule's
;                           target; -MP an empty rule per dependency;
;                           -MW is accepted
;   -w+x, -w-x, -Wx, -Wno-x warning classes on / off ("all": every one);
;                           -w+error[=x], -Werror[=x]: warnings are errors
;   -X gnu | -X vc          message style: file:line: / file(line) :
;   -s                      messages on stdout; -Z file: into a file
;   -l file                 the listing: lines, offsets and bytes
;   -g, -F dwarf            DWARF debug information (ELF objects)
;   --no-line, --keep-all: accepted; --reproducible: a COFF object's time
;   stamp 0
; Input    : rdi = the argument (it starts with '-'), rsi = the next
;            argument or 0
; Output   : eax = 0 not one of these, 1 taken, 2 taken with the next
;            argument, 3 its value is missing, 4 a bad value
;
cli_nasm_option:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    lea     rbx, [r12 + 2]                 ; a value written on ("-Idir")
    movzx   eax, byte [r12 + 1]
    cmp     eax, 'I'
    je      .inc
    cmp     eax, 'i'
    je      .inc
    cmp     eax, 'D'
    je      .def
    cmp     eax, 'd'
    je      .def
    cmp     eax, 'U'
    je      .undef
    cmp     eax, 'u'
    je      .undef
    cmp     eax, 'p'
    je      .pre
    cmp     eax, 'E'
    je      .pp_only
    cmp     eax, 'e'
    je      .pp_only
    cmp     eax, 'M'
    je      .deps
    cmp     eax, 'w'
    je      .warn
    cmp     eax, 'W'
    je      .warn
    cmp     eax, 'X'
    je      .style
    cmp     eax, 's'
    je      .to_stdout
    cmp     eax, 'Z'
    je      .to_file
    cmp     eax, 'g'
    je      .debug
    cmp     eax, 'l'
    je      .listing
    cmp     eax, 'F'
    je      .debug_format
    cmp     eax, '-'
    je      .long
.none:
    xor     eax, eax
    jmp     .ret

.inc:
    call    .value
    test    rax, rax
    jz      .missing
    push    rdx
    mov     rdi, rax
    extern  incpath_add
    call    incpath_add
    pop     rdx
    test    eax, eax
    jnz     .bad
    mov     eax, edx
    jmp     .ret

; a prelude line: r8 = its start, the value, then the end of the line;
; r9 = 0 as written, 1 "name=value" (the = becomes a blank), 2 in quotes
.def:
    lea     r8, [rel .s_define]
    mov     r9d, 1
    jmp     .line
.undef:
    lea     r8, [rel .s_undef]
    xor     r9d, r9d
    jmp     .line
.pre:
    lea     r8, [rel .s_include]
    mov     r9d, 2
.line:
    call    .value
    test    rax, rax
    jz      .missing
    push    rdx
    push    rax
    push    r9
    mov     rdi, r8
    xor     esi, esi
    call    cli_prelude_add
    pop     rsi
    pop     rdi
    push    rsi
    and     esi, 1
    call    cli_prelude_add
    pop     rsi
    lea     rdi, [rel .s_newline]
    cmp     esi, 2
    jne     .line_end
    lea     rdi, [rel .s_quote_nl]
.line_end:
    xor     esi, esi
    call    cli_prelude_add
    pop     rdx
    cmp     byte [rel cli_prelude_full], 0
    jne     .bad
    mov     eax, edx
    jmp     .ret

.pp_only:
    cmp     byte [rbx], 0
    jne     .none
    mov     byte [rel cli_mode], CLI_MODE_PREPROCESS
    jmp     .taken

.deps:
    lea     rbx, [r12 + 3]
    movzx   eax, byte [r12 + 2]
    test    eax, eax
    jz      .deps_only
    cmp     byte [rbx], 0
    jne     .deps_value
    cmp     eax, 'G'
    je      .deps_only
    cmp     eax, 'D'
    je      .deps_after
    cmp     eax, 'P'
    je      .deps_phony
    cmp     eax, 'W'
    je      .taken
.deps_value:
    cmp     eax, 'F'
    je      .deps_file
    cmp     eax, 'T'
    je      .deps_target
    cmp     eax, 'Q'
    je      .deps_target
    jmp     .none
.deps_only:
    mov     byte [rel cli_mode], CLI_MODE_DEPS
    jmp     .taken
.deps_after:
    or      byte [rel cli_deps], CLI_DEPS_AFTER
    jmp     .taken
.deps_phony:
    or      byte [rel cli_deps], CLI_DEPS_PHONY
    jmp     .taken
.deps_file:
    call    .value
    test    rax, rax
    jz      .missing
    mov     [rel cli_deps_file], rax
    mov     eax, edx
    jmp     .ret
.deps_target:
    call    .value
    test    rax, rax
    jz      .missing
    mov     [rel cli_deps_target], rax
    mov     eax, edx
    jmp     .ret

.warn:
    ; -w+class, -w-class, -Wclass, -Wno-class, -w+error[=class]: the
    ; warning classes (error/warnings.s)
    mov     rdi, r12
    extern  warn_option
    call    warn_option
    jmp     .taken

.style:
    call    .value
    test    rax, rax
    jz      .missing
    push    rdx
    push    rax
    mov     rdi, rax
    lea     rsi, [rel .s_gnu]
    call    str_cmp
    xor     ecx, ecx
    test    rax, rax
    jz      .style_set
    mov     rdi, [rsp]
    lea     rsi, [rel .s_vc]
    call    str_cmp
    mov     ecx, 1
    test    rax, rax
    jnz     .style_bad
.style_set:
    extern  error_style
    mov     [rel error_style], cl
    pop     rax
    pop     rdx
    mov     eax, edx
    jmp     .ret
.style_bad:
    pop     rax
    pop     rdx
    jmp     .bad

.to_stdout:
    cmp     byte [rbx], 0
    jne     .none
    mov     eax, 33                        ; dup2(1, 2)
    mov     edi, 1
    mov     esi, 2
    syscall
    jmp     .taken

.to_file:
    call    .value
    test    rax, rax
    jz      .missing
    push    rdx
    mov     rdi, rax
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    extern  io_open
    call    io_open
    test    rax, rax
    jnz     .to_file_bad
    mov     edi, edx                       ; dup2(fd, 2)
    mov     esi, 2
    mov     eax, 33
    syscall
    pop     rdx
    mov     eax, edx
    jmp     .ret
.to_file_bad:
    pop     rdx
    jmp     .bad

.listing:
    call    .value                         ; -l file: the listing
    test    rax, rax
    jz      .missing
    extern  lst_file, lst_enabled
    mov     [rel lst_file], rax
    mov     byte [rel lst_enabled], 1
    mov     eax, edx
    jmp     .ret

.debug:
    ; -g: DWARF debug information (line table, compile unit, ranges)
    cmp     byte [rbx], 0
    jne     .none
    extern  dbg_enabled
    mov     byte [rel dbg_enabled], 1
    mov     byte [rel lst_enabled], 1      ; its rows come from these entries
    jmp     .taken
.debug_format:
    ; -F dwarf (the only format there is for ELF here; -F stabs is taken
    ; as dwarf)
    call    .value
    test    rax, rax
    jz      .missing
    mov     eax, edx
    jmp     .ret

.long:
    mov     rdi, r12
    lea     rsi, [rel .s_before]
    call    str_cmp
    test    rax, rax
    jz      .before
    mov     rdi, r12
    lea     rsi, [rel .s_long_include]
    call    str_cmp
    test    rax, rax
    jz      .long_include
    mov     rdi, r12
    lea     rsi, [rel .s_pragma]
    call    str_cmp
    test    rax, rax
    jz      .long_pragma
    mov     rdi, r12
    lea     rsi, [rel .s_no_line]
    call    str_cmp
    test    rax, rax
    jz      .taken
    mov     rdi, r12
    lea     rsi, [rel .s_reproducible]
    call    str_cmp
    test    rax, rax
    jz      .reproducible
    mov     rdi, r12
    lea     rsi, [rel .s_keep_all]
    call    str_cmp
    test    rax, rax
    jz      .taken
    jmp     .none
.before:
    lea     r8, [rel .s_empty]
    xor     r9d, r9d
    jmp     .long_line
.long_include:
    lea     r8, [rel .s_include]
    mov     r9d, 2
    jmp     .long_line
.long_pragma:
    lea     r8, [rel .s_pragma_line]
    xor     r9d, r9d
.long_line:
    lea     rbx, [rel .s_empty]            ; the value is the next argument
    jmp     .line

.reproducible:
    ; the time stamp of a COFF object 0 (NASM's --reproducible)
    extern  coff_reproducible
    mov     byte [rel coff_reproducible], 1
.taken:
    mov     eax, 1
    jmp     .ret
.missing:
    mov     eax, 3
    jmp     .ret
.bad:
    mov     eax, 4
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; .value: rax = the option's value (written on, else the next argument;
; 0 when there is none), edx = how many arguments that takes (1 / 2)
.value:
    cmp     byte [rbx], 0
    je      .value_next
    mov     rax, rbx
    mov     edx, 1
    ret
.value_next:
    mov     rax, r13
    mov     edx, 2
    ret

;
; cli_prelude_add
; Appends text to the prelude (cli_prelude); sets cli_prelude_full when
; it does not fit.
; Input    : rdi = NUL-terminated text, esi = 1: the first '=' becomes a
;            blank ("-DNAME=value")
; Clobbers : rax, rcx, rdx, rsi, rdi
;
cli_prelude_add:
    mov     ecx, [rel cli_prelude_len]
    lea     rdx, [rel cli_prelude]
.byte:
    movzx   eax, byte [rdi]
    test    eax, eax
    jz      .done
    cmp     ecx, CLI_PRELUDE_MAX - 1
    jae     .full
    test    esi, esi
    jz      .put
    cmp     eax, '='
    jne     .put
    mov     eax, ' '
    xor     esi, esi
.put:
    mov     [rdx + rcx], al
    inc     ecx
    inc     rdi
    jmp     .byte
.full:
    mov     byte [rel cli_prelude_full], 1
.done:
    mov     [rel cli_prelude_len], ecx
    ret

;
; cli_write_deps
; Writes the Makefile rule for -M / -MD: into the -MF file, else on stdout
; for -M and into the output's name with .d for -MD. The target is the
; -MT / -MQ name, else the output file.
; Input    : rdi = AsmCtx
; Output   : rax = EXIT_OK or an error
;
global cli_write_deps
cli_write_deps:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, 1                        ; stdout
    mov     rdi, [rel cli_deps_file]
    test    rdi, rdi
    jnz     .open
    cmp     byte [rel cli_mode], CLI_MODE_DEPS
    je      .write
    ; -MD without -MF: the output's name with .d for its extension
    mov     rdi, rbx
    lea     rsi, [rel .s_dot_d]
    call    cli_with_suffix
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
.open:
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     r12d, edx
.write:
    mov     rsi, [rel cli_deps_target]
    test    rsi, rsi
    jnz     .target
    mov     rsi, [rbx + ASMCTX_output]
.target:
    mov     edi, r12d
    xor     edx, edx
    test    byte [rel cli_deps], CLI_DEPS_PHONY
    setnz   dl
    extern  deps_write
    call    deps_write
    mov     r13, rax
    cmp     r12d, 1
    je      .written
    mov     edi, r12d
    extern  io_close
    call    io_close
.written:
    mov     rax, r13
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; cli_with_suffix
; The output file's name with its extension replaced by a suffix (or the
; suffix added, when it has none), in the arena.
; Input    : rdi = AsmCtx, rsi = suffix (".d")
; Output   : rax = EXIT_OK or EXIT_OOM, rdx = the name
;
cli_with_suffix:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, [rbx + ASMCTX_output]
    mov     rdi, r13
    extern  str_len
    call    str_len
    mov     r14, rax                       ; r14 = the length kept
    mov     rcx, rax
.scan:
    test    rcx, rcx
    jz      .alloc
    dec     rcx
    cmp     byte [r13 + rcx], '/'
    je      .alloc
    cmp     byte [r13 + rcx], '.'
    jne     .scan
    test    rcx, rcx
    jz      .alloc                         ; ".name": not an extension
    cmp     byte [r13 + rcx - 1], '/'
    je      .alloc
    mov     r14, rcx
.alloc:
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r14 + 16]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, r13
    mov     rcx, r14
    rep movsb
    mov     rsi, r12
.suffix:
    lodsb
    stosb
    test    al, al
    jnz     .suffix
    xor     eax, eax
.ret:
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
cli_parse.val_elf32:    db "elf32", 0
cli_parse.val_elf:      db "elf", 0
cli_parse.val_win64:    db "win64", 0
cli_parse.val_ubf:      db "ubf", 0
cli_parse.flag_ubf_add: db "--ubf-add", 0
cli_parse.flag_bits: db "--bits", 0
cli_parse.suffix_ubf:   db ".ubf", 0
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
cli_parse.suffix_coff: db ".obj", 0
cli_parse.suffix_bin: db ".bin", 0
cli_parse.msg_unknown_flag: db "utasm: unknown option: ", 0
cli_parse.msg_unknown_value: db "utasm: unknown option value: ", 0
cli_parse.msg_missing_value: db "utasm: missing value for option: ", 0
cli_parse.msg_second_input: db "utasm: only one input file is supported; second input: ", 0
cli_parse.msg_newline: db 10, 0
cli_parse.flag_inspect: db "--inspect", 0
cli_parse.flag_inspect_only: db "--inspect-only", 0
cli_parse.flag_disasm: db "--disasm", 0
cli_nasm_option.s_define:     db "%define ", 0
cli_nasm_option.s_undef:      db "%undef ", 0
cli_nasm_option.s_include:    db "%include ", 34, 0
cli_nasm_option.s_pragma_line: db "%pragma ", 0
cli_nasm_option.s_newline:    db 10, 0
cli_nasm_option.s_quote_nl:   db 34, 10, 0
cli_nasm_option.s_empty:      db 0
cli_nasm_option.s_gnu:        db "gnu", 0
cli_nasm_option.s_vc:         db "vc", 0
cli_nasm_option.s_before:     db "--before", 0
cli_nasm_option.s_long_include: db "--include", 0
cli_nasm_option.s_pragma:     db "--pragma", 0
cli_nasm_option.s_no_line:    db "--no-line", 0
cli_nasm_option.s_reproducible: db "--reproducible", 0
cli_nasm_option.s_keep_all:   db "--keep-all", 0
cli_write_deps.s_dot_d:       db ".d", 0

[SECTION .bss]
cli_bits:       resb 1              ; --bits 16 / 32 / 64, or 0
global cli_mode
global cli_prelude
global cli_prelude_len
global cli_output_given
global cli_deps
alignb 8
cli_deps_file:    resq 1                ; -MF file, or 0
cli_deps_target:  resq 1                ; -MT / -MQ target, or 0
cli_prelude_len:  resd 1
cli_mode:         resb 1                ; CLI_MODE_*
cli_deps:         resb 1                ; CLI_DEPS_* (-MD, -MP)
cli_prelude_full: resb 1
cli_output_given: resb 1                ; -o was given
cli_prelude:      resb CLI_PRELUDE_MAX  ; the -D / -U / -p / --before lines

[SECTION .rodata]

; --inspect-only part names: mask byte, then NUL-terminated name
cli_inspect_part_table:
    db INSPECT_HEADER,   "header", 0
    db INSPECT_SECTIONS, "sections", 0
    db INSPECT_SEGMENTS, "segments", 0
    db INSPECT_SYMBOLS,  "symbols", 0
    db INSPECT_RELOCS,   "relocs", 0
    db INSPECT_ALL,      "all", 0
    db INSPECT_DISASM,   "disasm", 0
    db 0
