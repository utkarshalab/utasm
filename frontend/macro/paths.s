;
; ============================================================================
; File        : frontend/macro/paths.s
; Project     : utasm
; Description : Include search paths (-I) and the files a source depends on.
;
;   %include and incbin open their file through incpath_open: the name as
;   written first (relative to the current directory, as NASM does), then
;   each -I directory in the order given. A directory without a trailing
;   '/' gets one.
;
;   Every file that opens is recorded, after the main source, for the
;   Makefile dependencies of -M / -MD (deps_write): "target: source
;   included.inc data.bin".
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

%define MAX_INCPATHS    32
%define MAX_DEPS        512

extern  io_open
extern  io_write
extern  arena_alloc
extern  str_len
extern  str_cmp
extern  global_ctx

[SECTION .bss]
alignb 8
incpaths:       resq MAX_INCPATHS       ; -I directories (argv strings)
deps:           resq MAX_DEPS           ; files read, the main source first
incpath_count:  resd 1
deps_count:     resd 1

[SECTION .text]

;*
; * [incpath_add]
; * Purpose: Add a directory to the include search path (-I).
; * Input  : RDI = directory (kept by pointer)
; * Output : RAX = EXIT_OK, or EXIT_USAGE when there are too many
; ;
global incpath_add
incpath_add:
    mov     eax, [rel incpath_count]
    cmp     eax, MAX_INCPATHS
    jae     .full
    lea     rcx, [rel incpaths]
    mov     [rcx + rax*8], rdi
    inc     dword [rel incpath_count]
    xor     eax, eax
    ret
.full:
    mov     eax, EXIT_USAGE
    ret

;*
; * [deps_add]
; * Purpose: Record a file the output depends on (each name once).
; * Input  : RDI = file name (kept by pointer)
; * Clobbers: rax, rcx, rdx, rsi, rdi, r8 - r11
; ;
global deps_add
deps_add:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    xor     ebx, ebx
.seen:
    cmp     ebx, [rel deps_count]
    jae     .new
    lea     rax, [rel deps]
    mov     rsi, [rax + rbx*8]
    mov     rdi, r12
    call    str_cmp
    test    rax, rax
    jz      .done
    inc     ebx
    jmp     .seen
.new:
    mov     eax, [rel deps_count]
    cmp     eax, MAX_DEPS
    jae     .done
    ; a copy: the name may sit in a buffer that is reused ("incbin 'x'")
    mov     rdi, r12
    call    str_len
    mov     r13, rax
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_arena]
    lea     rsi, [r13 + 1]
    call    arena_alloc                    ; zeroed: the copy ends in NUL
    test    rax, rax
    jnz     .done
    mov     rdi, rdx
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    mov     eax, [rel deps_count]
    lea     rcx, [rel deps]
    mov     [rcx + rax*8], rdx
    inc     dword [rel deps_count]
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [incpath_open]
; * Purpose: Open a file for %include / incbin: as named, then in each -I
; *          directory.
; * Input  : RDI = file name
; * Output : RAX = EXIT_OK or the error of opening it as named,
; *          RDX = fd, RCX = the name it was opened under
; ;
global incpath_open
incpath_open:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                       ; r12 = the name as written
    xor     esi, esi                       ; O_RDONLY
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .search
    mov     r13, rdx
    mov     r14, r12
    jmp     .opened

.search:
    mov     r15, rax                       ; the error to report if all fail
    cmp     byte [r12], '/'
    je      .fail                          ; an absolute name: nowhere else
    mov     rdi, r12
    call    str_len
    mov     r13, rax                       ; r13 = name length
    xor     ebx, ebx
.dir:
    cmp     ebx, [rel incpath_count]
    jae     .fail
    lea     rax, [rel incpaths]
    mov     rsi, [rax + rbx*8]             ; the directory
    inc     ebx
    push    rsi
    mov     rdi, rsi
    call    str_len
    pop     rsi
    mov     r14, rax                       ; r14 = directory length
    ; directory + '/' + name + NUL, in the arena (it names the file from
    ; now on: the lexer's file name, the dependency list)
    push    rsi
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_arena]
    lea     rsi, [r14 + r13 + 2]
    call    arena_alloc
    pop     rsi
    test    rax, rax
    jnz     .fail
    mov     rdi, rdx
    push    rdx
    mov     rcx, r14
    rep movsb
    test    r14, r14
    jz      .no_slash
    cmp     byte [rdi - 1], '/'
    je      .no_slash
    mov     byte [rdi], '/'
    inc     rdi
.no_slash:
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    mov     byte [rdi], 0
    pop     r14                            ; r14 = the full name
    mov     rdi, r14
    xor     esi, esi
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .dir
    mov     r13, rdx

.opened:
    mov     rdi, r14
    call    deps_add
    xor     eax, eax
    mov     rdx, r13
    mov     rcx, r14
    jmp     .ret
.fail:
    mov     rax, r15
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [incpath_find]
; * Purpose: Where %include would find a file (%pathsearch).
; * Input  : RDI = file name
; * Output : RAX = its path (as named, or in a -I directory), 0 when none
; ;
global incpath_find
incpath_find:
    push    rbx
    call    incpath_open
    test    rax, rax
    jnz     .none
    mov     rbx, rcx
    mov     rdi, rdx
    extern  io_close
    call    io_close
    mov     rax, rbx
    pop     rbx
    ret
.none:
    xor     eax, eax
    pop     rbx
    ret

;*
; * [deps_write]
; * Purpose: Write the Makefile rule as NASM does: "target : dep dep ...",
; *          lines wrapped with a backslash before column 62, a blank line
; *          after it, and with -MP an empty rule "dep :" for each file.
; * Input  : EDI = fd, RSI = target, EDX = 1 for the phony rules (-MP)
; * Output : RAX = EXIT_OK or EXIT_FILE_WRITE
; ;
global deps_write
deps_write:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, edx
    push    rsi
    mov     rdi, rsi
    call    str_len
    lea     r14, [rax + 2]                 ; r14 = the column reached
    pop     rdi
    call    .str
    lea     rdi, [rel s_colon]
    call    .str
    xor     ebx, ebx
.dep:
    cmp     ebx, [rel deps_count]
    jae     .rule_done
    lea     rax, [rel deps]
    mov     r15, [rax + rbx*8]
    mov     rdi, r15
    call    str_len
    lea     rcx, [r14 + rax]
    cmp     rcx, 62
    jbe     .fits
    cmp     r14, 1
    jbe     .fits
    push    rax
    lea     rdi, [rel s_wrap]
    call    .str
    pop     rax
    mov     r14d, 1
.fits:
    lea     r14, [r14 + rax + 1]
    lea     rdi, [rel s_space]
    call    .str
    mov     rdi, r15
    call    .str
    inc     ebx
    jmp     .dep
.rule_done:
    lea     rdi, [rel s_blank_line]
    call    .str
    test    r13d, r13d
    jz      .ok
    xor     ebx, ebx
.phony:
    cmp     ebx, [rel deps_count]
    jae     .ok
    lea     rax, [rel deps]
    mov     rdi, [rax + rbx*8]
    call    .str
    lea     rdi, [rel s_phony]
    call    .str
    inc     ebx
    jmp     .phony
.ok:
    xor     eax, eax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .str: write the NUL-terminated rdi to fd r12d
.str:
    push    rdi
    call    str_len
    pop     rsi
    mov     rdx, rax
    mov     edi, r12d
    jmp     io_write

[SECTION .rodata]
s_colon:        db " :", 0
s_space:        db " ", 0
s_wrap:         db " ", 92, 10, " ", 0   ; a backslash, a new line, a blank
s_blank_line:   db 10, 10, 0
s_phony:        db " :", 10, 10, 0
