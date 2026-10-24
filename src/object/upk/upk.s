;
; ============================================================================
; File        : src/object/upk/upk.s
; Project     : utasm
; Description : -f upk: a UPK package for Utkarsha OS (docs/user/upk.md; the
;               OS repository's docs/UPK_SPEC.md), and --upk-keygen.
;
;   utasm -f upk MANIFEST --upk-add PATH=FILE ... [--upk-sign KEY] -o OUT
;
;   The input is the package's manifest (key = value text), not a source.
;   utasm checks it (known keys, each once; name, version, kind; an entry
;   for an app or a command, naming one of the files and a UBF image), checks
;   every PATH, reads every FILE and takes its SHA-256, and writes:
;
;     a 144-byte header, the entry table (64 bytes per file: path, kind,
;     offset, size, SHA-256), the string table (the paths), the manifest,
;     then each file's bytes on a 16-byte boundary.
;
;   --upk-sign KEY signs it: the SHA-256 of the header (signature field
;   zero), entry table, string table and manifest, signed with Ed25519
;   (src/lib/ed25519.s); the header names the signer by the SHA-256 of its
;   public key. A key file is the 32-byte seed, or seed and public key (64
;   bytes) as --upk-keygen writes it.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"

extern  io_open
extern  io_create
extern  io_close
extern  io_write
extern  io_file_size
extern  io_mmap
extern  arena_alloc
extern  global_ctx
extern  sha256_hash
extern  error_set_subject
extern  error_report_code
extern  ed25519_public_from_seed
extern  ed25519_sign
extern  ed25519_keygen
extern  print_str

%define UPK_MAX_FILES   256             ; per invocation
%define UPK_HEADER      144
%define UPK_ENTRY       64
%define UPK_MAX_MANIFEST (64 * 1024)
%define UPK_MAX_NAME    32

; entry kinds
%define UK_MAIN         1
%define UK_LIB          2
%define UK_CMD          3
%define UK_RES          4
%define UK_CONF         5
%define UK_MODEL        6

; manifest keys (index into upk_keys)
%define MK_NAME         0
%define MK_VERSION      1
%define MK_KIND         2
%define MK_TITLE        3
%define MK_PUBLISHER    4
%define MK_ENTRY        5
%define MK_CAPS         6
%define MK_MODELS       7
%define MK_DEPENDS      8
%define MK_MIN_OS       9
%define MK_COUNT        10

[SECTION .bss]
alignb 8
global upk_enabled, upk_sign_path, upk_keygen_path
upk_sign_path:      resq 1          ; --upk-sign KEY, or 0
upk_keygen_path:    resq 1          ; --upk-keygen FILE, or 0
upk_count:          resq 1
upk_paths:          resq UPK_MAX_FILES      ; PATH of each --upk-add
upk_srcs:           resq UPK_MAX_FILES      ; ... and its FILE
upk_data:           resq UPK_MAX_FILES      ; its bytes
upk_sizes:          resq UPK_MAX_FILES
upk_kinds:          resd UPK_MAX_FILES
upk_val:            resq MK_COUNT   ; each manifest key's value (NUL-ended)
upk_man:            resq 1          ; the manifest's bytes
upk_man_len:        resq 1
upk_out:            resq 1
upk_out_len:        resq 1
upk_seed:           resb 32
upk_pub:            resb 32
upk_keybuf:         resb 64
upk_digest:         resb 32
upk_hex:            resb 80
upk_enabled:        resb 1          ; -f upk

[SECTION .rodata]
upk_keys:
    db "name", 0, "version", 0, "kind", 0, "title", 0, "publisher", 0
    db "entry", 0, "capabilities", 0, "models", 0, "depends", 0, "min_os", 0
    db 0
upk_kind_app:   db "app", 0
upk_kind_lib:   db "lib", 0
upk_kind_cmd:   db "cmd", 0
upk_reserved:   db "lib", 0, "cmd", 0, "model", 0, 0
upk_conf_pre:   db "conf/", 0
upk_model_pre:  db "model/", 0
upk_pub_suffix: db ".pub", 0
upk_msg_pub:    db "public key: ", 0
upk_nl:         db 10, 0
upk_s_name:     db "name", 0
upk_s_version:  db "version", 0
upk_s_kind:     db "kind", 0
upk_s_entry:    db "entry", 0
upk_hexdig:     db "0123456789abcdef"

[SECTION .text]

;*
; * [upk_add]
; * Purpose: Record one --upk-add PATH=FILE.
; * Input  : RDI = the argument (written to: the '=' becomes a NUL)
; * Output : RAX = EXIT_OK, or EXIT_USAGE (no '=', or too many files)
; ;
global upk_add
upk_add:
    mov     rcx, [rel upk_count]
    cmp     rcx, UPK_MAX_FILES
    jae     .bad
    mov     rsi, rdi
.find:
    mov     al, [rsi]
    test    al, al
    jz      .bad
    cmp     al, '='
    je      .have
    inc     rsi
    jmp     .find
.have:
    cmp     rsi, rdi
    je      .bad                        ; an empty PATH
    mov     byte [rsi], 0
    inc     rsi
    cmp     byte [rsi], 0
    je      .bad                        ; an empty FILE
    lea     rax, [rel upk_paths]
    mov     [rax + rcx*8], rdi
    lea     rax, [rel upk_srcs]
    mov     [rax + rcx*8], rsi
    inc     rcx
    mov     [rel upk_count], rcx
    xor     eax, eax
    ret
.bad:
    mov     eax, EXIT_USAGE
    ret

;*
; * [upk_build]
; * Purpose: Write the package (-f upk). Reports its own errors.
; * Input  : RDI = the manifest's path, RSI = the output's path
; * Output : RAX = EXIT_OK, or the exit status to leave with
; ;
global upk_build
upk_build:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r14, rdi                    ; the manifest
    mov     r15, rsi                    ; the output

    mov     rdi, r14
    call    upk_read_file
    test    rax, rax
    jnz     .file_error
    mov     [rel upk_man], rdx
    mov     [rel upk_man_len], rcx
    cmp     rcx, UPK_MAX_MANIFEST
    ja      .manifest_big
    call    upk_parse_manifest
    test    rax, rax
    jnz     .report
    call    upk_check_manifest
    test    rax, rax
    jnz     .report
    call    upk_read_files
    test    rax, rax
    jnz     .report
    call    upk_layout
    test    rax, rax
    jnz     .report
    cmp     qword [rel upk_sign_path], 0
    je      .write
    call    upk_sign
    test    rax, rax
    jnz     .report

.write:
    mov     rdi, r15
    mov     rdx, 0o644
    call    io_create
    test    rax, rax
    jnz     .report
    mov     r13, rdx
    mov     edi, r13d
    mov     rsi, [rel upk_out]
    mov     rdx, [rel upk_out_len]
    call    io_write
    mov     r12, rax
    mov     rdi, r13
    call    io_close
    mov     rax, r12
    test    rax, rax
    jnz     .report
    jmp     .ret

.manifest_big:
    mov     rdi, r14
    call    error_set_subject
    mov     eax, EXIT_UPK_MANIFEST
    jmp     .report
.file_error:
    push    rax
    mov     rdi, r14
    call    error_set_subject
    pop     rax
.report:
    mov     r12, rax
    mov     edi, eax
    call    error_report_code
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- upk_read_file -------------------------------------------------------
; RDI = a path -> RAX = EXIT_OK or an error, RDX = its bytes, RCX = its size
; (an empty file: RDX = an empty buffer). Clobbers RSI, RDI, R8-R11.
upk_read_file:
    push    rbx
    push    r12
    push    r13
    xor     esi, esi
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     rbx, rdx                    ; fd
    mov     rdi, rbx
    call    io_file_size
    test    rax, rax
    jnz     .close
    mov     r12, rdx                    ; size
    test    r12, r12
    jnz     .map
    lea     r13, [rel upk_nl]           ; any readable byte: nothing is read
    jmp     .closed
.map:
    xor     edi, edi
    mov     rsi, r12
    mov     edx, PROT_READ
    mov     ecx, MAP_PRIVATE
    mov     r8, rbx
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .close
    mov     r13, rdx
.closed:
    mov     rdi, rbx
    call    io_close
    mov     rdx, r13
    mov     rcx, r12
    xor     eax, eax
    jmp     .ret
.close:
    push    rax
    mov     rdi, rbx
    call    io_close
    pop     rax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- upk_parse_manifest -------------------------------------------------
; Each "key = value" line; '#' starts a comment; blank lines are skipped.
; Output: RAX = EXIT_OK, or EXIT_UPK_MANIFEST with the subject set.
upk_parse_manifest:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rdi, [rel upk_val]
    xor     eax, eax
    mov     ecx, MK_COUNT
    rep     stosq
    mov     rbx, [rel upk_man]          ; RBX = the cursor
    mov     r12, rbx
    add     r12, [rel upk_man_len]      ; R12 = the end
.line:
    cmp     rbx, r12
    jae     .ok
    ; R13 = the line's start, R14 = its end (the newline or the end)
    mov     r13, rbx
.eol:
    cmp     rbx, r12
    jae     .have_line
    cmp     byte [rbx], 10
    je      .have_line
    inc     rbx
    jmp     .eol
.have_line:
    mov     r14, rbx
    inc     rbx                         ; past the newline
    ; a comment ends the line
    mov     rsi, r13
.comment:
    cmp     rsi, r14
    jae     .trim
    cmp     byte [rsi], '#'
    je      .cut
    inc     rsi
    jmp     .comment
.cut:
    mov     r14, rsi
.trim:
    call    .trim_range                 ; R13..R14 without blanks at either end
    cmp     r13, r14
    jae     .line                       ; blank
    ; the '='
    mov     rsi, r13
.eq:
    cmp     rsi, r14
    jae     .bad_line
    cmp     byte [rsi], '='
    je      .have_eq
    inc     rsi
    jmp     .eq
.have_eq:
    mov     r15, rsi                    ; R15 = the '='
    ; the key: R13 .. R15, trimmed; which one it is
    push    r14
    mov     r14, r15
    call    .trim_range
    mov     rdi, r13
    mov     rsi, r14
    call    upk_key_index               ; EAX = MK_*, or -1
    pop     r14
    cmp     eax, -1
    je      .bad_key
    lea     rcx, [rel upk_val]
    cmp     qword [rcx + rax*8], 0
    jne     .bad_key                    ; a second time
    ; the value: after the '=', trimmed, copied NUL-terminated
    push    rax                         ; the key's index (.trim_range uses AL)
    push    rax                         ; (keeps RSP aligned for the call)
    lea     r13, [r15 + 1]
    call    .trim_range
    mov     rsi, r14
    sub     rsi, r13
    inc     rsi
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc                 ; zeroed: the NUL is there already
    mov     r8, rax
    pop     rax
    pop     rax
    test    r8, r8
    jnz     .oom
    lea     rcx, [rel upk_val]
    mov     [rcx + rax*8], rdx
    mov     rdi, rdx
    mov     rsi, r13
    mov     rcx, r14
    sub     rcx, r13
    rep     movsb
    jmp     .line
.ok:
    xor     eax, eax
    jmp     .ret
.oom:
    mov     eax, EXIT_OOM
    jmp     .ret
.bad_key:
    ; the subject: the key as written (copied, NUL-terminated)
    mov     r14, r15
    call    .trim_range
.bad_line:
    mov     rsi, r14
    sub     rsi, r13
    inc     rsi
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .oom
    mov     rdi, rdx
    mov     rsi, r13
    mov     rcx, r14
    sub     rcx, r13
    rep     movsb
    mov     rdi, rdx
    call    error_set_subject
    mov     eax, EXIT_UPK_MANIFEST
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
; R13..R14 -> the same range without spaces, tabs or CRs at either end.
; Clobbers AL.
.trim_range:
.trim_front:
    cmp     r13, r14
    jae     .trimmed
    mov     al, [r13]
    cmp     al, ' '
    je      .front_next
    cmp     al, 9
    je      .front_next
    cmp     al, 13
    jne     .trim_back
.front_next:
    inc     r13
    jmp     .trim_front
.trim_back:
    cmp     r14, r13
    jbe     .trimmed
    mov     al, [r14 - 1]
    cmp     al, ' '
    je      .back_next
    cmp     al, 9
    je      .back_next
    cmp     al, 13
    jne     .trimmed
.back_next:
    dec     r14
    jmp     .trim_back
.trimmed:
    ret

; ---- upk_key_index ------------------------------------------------------
; RDI..RSI = a key -> EAX = its MK_* index, or -1. Clobbers RCX, RDX, R8.
upk_key_index:
    lea     r8, [rel upk_keys]
    xor     eax, eax
.key:
    cmp     byte [r8], 0
    je      .none
    xor     ecx, ecx
.cmp:
    lea     rdx, [rdi + rcx]
    cmp     rdx, rsi
    je      .key_end
    mov     dl, [rdi + rcx]
    cmp     dl, [r8 + rcx]
    jne     .next
    inc     rcx
    jmp     .cmp
.key_end:
    cmp     byte [r8 + rcx], 0
    je      .found
.next:
    ; past this key's NUL
.skip:
    cmp     byte [r8], 0
    je      .skipped
    inc     r8
    jmp     .skip
.skipped:
    inc     r8
    inc     eax
    jmp     .key
.found:
    ret
.none:
    mov     eax, -1
    ret

; ---- upk_check_manifest -------------------------------------------------
; name, version and kind present and well-formed; entry for app / cmd only.
; Output: RAX = EXIT_OK, or an error with the subject set.
upk_check_manifest:
    ; name: 1-32 of a-z 0-9 -, not a reserved one
    mov     rsi, [rel upk_val + MK_NAME*8]
    test    rsi, rsi
    jz      .missing_name
    xor     ecx, ecx
.name_char:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .name_end
    cmp     al, '-'
    je      .name_ok
    cmp     al, '0'
    jb      .bad_name
    cmp     al, '9'
    jbe     .name_ok
    cmp     al, 'a'
    jb      .bad_name
    cmp     al, 'z'
    ja      .bad_name
.name_ok:
    inc     ecx
    jmp     .name_char
.name_end:
    test    ecx, ecx
    jz      .bad_name
    cmp     ecx, UPK_MAX_NAME
    ja      .bad_name
    lea     rdi, [rel upk_reserved]
.reserved:
    cmp     byte [rdi], 0
    je      .version
    mov     rdx, rdi
    call    upk_streq                   ; RSI vs RDX
    je      .bad_name
.res_skip:
    inc     rdi
    cmp     byte [rdi - 1], 0
    jne     .res_skip
    jmp     .reserved

.version:
    ; major.minor.patch: three runs of digits
    mov     rsi, [rel upk_val + MK_VERSION*8]
    test    rsi, rsi
    jz      .missing_version
    mov     r8d, 3
.ver_part:
    xor     ecx, ecx
.ver_digit:
    mov     al, [rsi]
    cmp     al, '0'
    jb      .ver_part_end
    cmp     al, '9'
    ja      .ver_part_end
    inc     rsi
    inc     ecx
    jmp     .ver_digit
.ver_part_end:
    test    ecx, ecx
    jz      .bad_version
    dec     r8d
    jz      .ver_last
    cmp     al, '.'
    jne     .bad_version
    inc     rsi
    jmp     .ver_part
.ver_last:
    test    al, al
    jnz     .bad_version

    ; kind: app, lib or cmd; an entry exactly when it is not a lib
    mov     rsi, [rel upk_val + MK_KIND*8]
    test    rsi, rsi
    jz      .missing_kind
    lea     rdx, [rel upk_kind_lib]
    call    upk_streq
    je      .is_lib
    lea     rdx, [rel upk_kind_app]
    call    upk_streq
    je      .needs_entry
    lea     rdx, [rel upk_kind_cmd]
    call    upk_streq
    jne     .bad_kind
.needs_entry:
    cmp     qword [rel upk_val + MK_ENTRY*8], 0
    je      .missing_entry
    xor     eax, eax
    ret
.is_lib:
    cmp     qword [rel upk_val + MK_ENTRY*8], 0
    jne     .lib_entry
    xor     eax, eax
    ret

.missing_name:
.bad_name:
    lea     rdi, [rel upk_s_name]
    jmp     .bad
.missing_version:
.bad_version:
    lea     rdi, [rel upk_s_version]
    jmp     .bad
.missing_kind:
.bad_kind:
    lea     rdi, [rel upk_s_kind]
    jmp     .bad
.missing_entry:
.lib_entry:
    lea     rdi, [rel upk_s_entry]
.bad:
    call    error_set_subject
    mov     eax, EXIT_UPK_MANIFEST
    ret

; ---- upk_streq ----------------------------------------------------------
; RSI, RDX = two NUL-terminated strings -> ZF set when equal. Clobbers RCX, AL.
upk_streq:
    xor     ecx, ecx
.c:
    mov     al, [rsi + rcx]
    cmp     al, [rdx + rcx]
    jne     .r
    inc     rcx
    test    al, al
    jnz     .c
.r:
    ret

; ---- upk_read_files -----------------------------------------------------
; Each --upk-add: its path checked, its file read, its kind decided.
; Output: RAX = EXIT_OK, or an error with the subject set.
upk_read_files:
    push    rbx
    push    r12
    push    r13
    cmp     qword [rel upk_count], 0
    je      .no_files
    xor     ebx, ebx
    xor     r13d, r13d                  ; R13 = entries that matched `entry`
.file:
    cmp     rbx, [rel upk_count]
    jae     .files_done
    lea     rax, [rel upk_paths]
    mov     r12, [rax + rbx*8]          ; R12 = the path
    mov     rdi, r12
    call    upk_check_path
    jnz     .bad_path
    ; not the same path as an earlier one
    xor     ecx, ecx
.dup:
    cmp     rcx, rbx
    jae     .dup_done
    lea     rax, [rel upk_paths]
    mov     rdx, [rax + rcx*8]
    mov     rsi, r12
    push    rcx
    call    upk_streq
    pop     rcx
    je      .bad_path
    inc     rcx
    jmp     .dup
.dup_done:
    lea     rax, [rel upk_srcs]
    mov     rdi, [rax + rbx*8]
    push    rdi
    call    upk_read_file
    pop     rdi
    test    rax, rax
    jnz     .bad_file
    lea     rax, [rel upk_data]
    mov     [rax + rbx*8], rdx
    lea     rax, [rel upk_sizes]
    mov     [rax + rbx*8], rcx

    ; the kind: a UBF image is the entry, or a library; anything else is
    ; configuration under conf/, model data under model/, or a resource
    xor     r8d, r8d                    ; R8D = 1: a UBF image
    cmp     rcx, 4
    jb      .not_ubf
    cmp     dword [rdx], 0x00464255     ; "UBF\0"
    jne     .not_ubf
    mov     r8d, 1
.not_ubf:
    mov     rsi, r12
    mov     rdx, [rel upk_val + MK_ENTRY*8]
    test    rdx, rdx
    jz      .not_entry
    call    upk_streq
    jne     .not_entry
    test    r8d, r8d
    jz      .entry_not_ubf
    inc     r13
    mov     r9d, UK_MAIN                ; (the helpers clobber EAX: R9D)
    mov     rsi, [rel upk_val + MK_KIND*8]
    lea     rdx, [rel upk_kind_cmd]
    call    upk_streq
    jne     .set_kind
    mov     r9d, UK_CMD
    jmp     .set_kind
.not_entry:
    mov     r9d, UK_LIB
    test    r8d, r8d
    jnz     .set_kind
    mov     r9d, UK_CONF
    mov     rdi, r12
    lea     rsi, [rel upk_conf_pre]
    call    upk_prefix
    je      .set_kind
    mov     r9d, UK_MODEL
    mov     rdi, r12
    lea     rsi, [rel upk_model_pre]
    call    upk_prefix
    je      .set_kind
    mov     r9d, UK_RES
.set_kind:
    lea     rcx, [rel upk_kinds]
    mov     [rcx + rbx*4], r9d
    inc     rbx
    jmp     .file
.files_done:
    ; an app or a command: `entry` names one of the files
    cmp     qword [rel upk_val + MK_ENTRY*8], 0
    je      .ok
    test    r13, r13
    jz      .entry_missing
.ok:
    xor     eax, eax
    jmp     .ret
.no_files:
    mov     eax, EXIT_UPK_EMPTY
    jmp     .ret
.bad_path:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_UPK_PATH
    jmp     .ret
.bad_file:
    push    rax
    call    error_set_subject           ; RDI = the file
    pop     rax
    jmp     .ret
.entry_not_ubf:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_UPK_ENTRY
    jmp     .ret
.entry_missing:
    mov     rdi, [rel upk_val + MK_ENTRY*8]
    call    error_set_subject
    mov     eax, EXIT_UPK_ENTRY
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- upk_prefix ---------------------------------------------------------
; RDI = a string, RSI = a prefix -> ZF set when the string starts with it.
; Clobbers EAX, RCX.
upk_prefix:
    xor     ecx, ecx
.c:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .yes
    cmp     al, [rdi + rcx]
    jne     .r
    inc     rcx
    jmp     .c
.yes:
    xor     eax, eax                    ; ZF set
.r:
    ret

; ---- upk_check_path -----------------------------------------------------
; RDI = a path -> ZF set when it is one: parts of a-z 0-9 . _ - joined by
; '/', none empty, none "." or "..". Clobbers RAX, RCX, RDX.
upk_check_path:
    xor     ecx, ecx                    ; part length
    xor     edx, edx                    ; dots in the part
.c:
    mov     al, [rdi]
    test    al, al
    jz      .end
    cmp     al, '/'
    je      .slash
    inc     ecx
    cmp     al, '.'
    jne     .not_dot
    inc     edx
    jmp     .next
.not_dot:
    cmp     al, '_'
    je      .next
    cmp     al, '-'
    je      .next
    cmp     al, '0'
    jb      .bad
    cmp     al, '9'
    jbe     .next
    cmp     al, 'a'
    jb      .bad
    cmp     al, 'z'
    ja      .bad
.next:
    inc     rdi
    jmp     .c
.slash:
    call    .part_ok
    jnz     .bad
    xor     ecx, ecx
    xor     edx, edx
    inc     rdi
    jmp     .c
.end:
    call    .part_ok
    ret                                 ; ZF from .part_ok
.bad:
    or      eax, 1                      ; ZF clear
    ret
; ZF set when the part (ECX characters, EDX of them dots) is a name
.part_ok:
    test    ecx, ecx
    jz      .part_bad
    cmp     ecx, edx
    jne     .part_good                  ; something besides dots
    cmp     ecx, 2
    jbe     .part_bad                   ; "." or ".."
.part_good:
    xor     eax, eax
    ret
.part_bad:
    or      eax, 1
    ret

; ---- upk_layout ---------------------------------------------------------
; The package in upk_out / upk_out_len, unsigned. Output: RAX = EXIT_OK or
; an error.
upk_layout:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, [rel upk_count]
    ; the string table: each path and its NUL
    xor     r12d, r12d                  ; R12 = its size
    xor     ecx, ecx
.str_len:
    cmp     rcx, rbx
    jae     .str_done
    lea     rax, [rel upk_paths]
    mov     rsi, [rax + rcx*8]
.len:
    inc     r12
    lodsb
    test    al, al
    jnz     .len
    inc     rcx
    jmp     .str_len
.str_done:
    mov     r13, UPK_HEADER
    mov     rax, rbx
    shl     rax, 6
    add     r13, rax                    ; R13 = the string table's offset
    lea     r14, [r13 + r12]            ; R14 = the manifest's offset
    lea     r15, [r14 + 0]
    add     r15, [rel upk_man_len]      ; R15 = the cursor
    ; each file's offset, 16-aligned
    xor     ecx, ecx
.place:
    cmp     rcx, rbx
    jae     .placed
    add     r15, 15
    and     r15, -16
    lea     rax, [rel upk_sizes]
    add     r15, [rax + rcx*8]
    inc     rcx
    jmp     .place
.placed:
    mov     [rel upk_out_len], r15
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    lea     rsi, [r15 + 16]
    call    arena_alloc                 ; zeroed
    test    rax, rax
    jnz     .ret
    mov     [rel upk_out], rdx
    mov     r9, rdx                     ; R9 = the file

    ; the header
    mov     dword [r9], 0x004B5055      ; "UPK\0"
    mov     word [r9 + 4], 1
    mov     word [r9 + 6], UPK_HEADER
    mov     [r9 + 0x0C], ebx            ; entry_count
    mov     dword [r9 + 0x10], UPK_HEADER
    mov     [r9 + 0x14], r13d           ; strtab_off
    mov     [r9 + 0x18], r12d           ; strtab_size
    mov     [r9 + 0x1C], r14d           ; manifest_off
    mov     rax, [rel upk_man_len]
    mov     [r9 + 0x20], eax
    mov     [r9 + 0x28], r15            ; file_size

    ; the manifest
    lea     rdi, [r9 + r14]
    mov     rsi, [rel upk_man]
    mov     rcx, [rel upk_man_len]
    rep     movsb

    ; the entries, the paths, the files
    lea     r10, [r9 + r13]             ; R10 = the next path
    lea     r15, [r14 + 0]
    add     r15, [rel upk_man_len]      ; R15 = the next file's offset
    xor     r12d, r12d                  ; R12 = the entry
.entry:
    cmp     r12, rbx
    jae     .entries_done
    mov     r11, r12
    shl     r11, 6
    lea     r11, [r9 + r11 + UPK_HEADER]    ; R11 = the entry
    mov     rax, r10
    sub     rax, r9
    sub     rax, r13
    mov     [r11], eax                  ; path_off
    lea     rax, [rel upk_kinds]
    mov     eax, [rax + r12*4]
    mov     [r11 + 4], eax              ; kind
    add     r15, 15
    and     r15, -16
    mov     [r11 + 8], r15              ; data_off
    lea     rax, [rel upk_sizes]
    mov     rcx, [rax + r12*8]
    mov     [r11 + 16], rcx             ; size
    ; the path
    lea     rax, [rel upk_paths]
    mov     rsi, [rax + r12*8]
.copy_path:
    lodsb
    mov     [r10], al
    inc     r10
    test    al, al
    jnz     .copy_path
    ; the bytes and their SHA-256
    lea     rax, [rel upk_data]
    mov     rsi, [rax + r12*8]
    lea     rdi, [r9 + r15]
    push    rsi
    push    rcx
    rep     movsb
    pop     rsi                         ; the size
    pop     rdi                         ; the bytes
    lea     rdx, [r11 + 24]
    push    r9
    push    r10
    push    r11
    sub     rsp, 8
    call    sha256_hash                 ; RDI = the bytes, RSI = the size
    add     rsp, 8
    pop     r11
    pop     r10
    pop     r9
    lea     rax, [rel upk_sizes]
    add     r15, [rax + r12*8]
    inc     r12
    jmp     .entry
.entries_done:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- upk_sign -----------------------------------------------------------
; Sign upk_out with the key in upk_sign_path. Output: RAX = EXIT_OK or an
; error with the subject set.
upk_sign:
    push    rbx
    push    r12
    sub     rsp, 8
    call    upk_load_key                ; upk_seed, upk_pub
    test    rax, rax
    jnz     .ret
    mov     rbx, [rel upk_out]
    or      dword [rbx + 0x08], 1       ; flags: signed
    ; signer = SHA-256 of the public key
    lea     rdi, [rel upk_pub]
    mov     esi, 32
    lea     rdx, [rbx + 0x30]
    call    sha256_hash
    ; the message: SHA-256 of header (signature zero), entries, paths, manifest
    mov     rdi, rbx
    mov     esi, [rbx + 0x1C]
    add     esi, [rbx + 0x20]
    lea     rdx, [rel upk_digest]
    call    sha256_hash
    lea     rdi, [rel upk_seed]
    lea     rsi, [rel upk_digest]
    mov     edx, 32
    lea     rcx, [rbx + 0x50]
    call    ed25519_sign
    test    rax, rax
    jz      .sign_failed
    xor     eax, eax
    jmp     .ret
.sign_failed:
    mov     rdi, [rel upk_sign_path]
    call    error_set_subject
    mov     eax, EXIT_UPK_KEY
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; ---- upk_load_key -------------------------------------------------------
; upk_sign_path's key: 32 bytes (a seed) or 64 (seed, then its public key,
; which must match). Output: RAX = EXIT_OK or EXIT_UPK_KEY (subject set).
upk_load_key:
    push    rbx
    sub     rsp, 16                     ; [rsp] = the key's size; RSP aligned
    mov     rdi, [rel upk_sign_path]
    call    upk_read_file
    test    rax, rax
    jnz     .bad_read
    mov     rbx, rdx
    cmp     rcx, 32
    je      .seed
    cmp     rcx, 64
    jne     .bad
.seed:
    mov     [rsp], rcx
    lea     rdi, [rel upk_seed]
    mov     rsi, rbx
    mov     ecx, 32
    rep     movsb
    lea     rdi, [rel upk_pub]
    lea     rsi, [rel upk_seed]
    call    ed25519_public_from_seed
    mov     rcx, [rsp]
    cmp     rcx, 64
    jne     .ok
    lea     rsi, [rbx + 32]             ; the stored public key must match
    lea     rdi, [rel upk_pub]
    mov     ecx, 32
    repe    cmpsb
    jne     .bad
.ok:
    xor     eax, eax
    add     rsp, 16
    pop     rbx
    ret
.bad_read:
.bad:
    mov     rdi, [rel upk_sign_path]
    call    error_set_subject
    mov     eax, EXIT_UPK_KEY
    add     rsp, 16
    pop     rbx
    ret

;*
; * [upk_keygen]
; * Purpose: --upk-keygen FILE: a new Ed25519 key. FILE gets the seed and
; *          the public key (64 bytes, mode 0600), FILE.pub the public key
; *          (32 bytes); the public key is printed in hex.
; * Input  : RDI = FILE
; * Output : RAX = EXIT_OK, or the exit status (the error reported)
; ;
global upk_keygen
upk_keygen:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    lea     rdi, [rel upk_keybuf]
    lea     rsi, [rel upk_keybuf + 32]
    call    ed25519_keygen
    test    rax, rax
    jz      .no_random
    ; FILE
    mov     rdi, rbx
    lea     rsi, [rel upk_keybuf]
    mov     edx, 64
    mov     ecx, 0o600
    call    upk_write_whole
    test    rax, rax
    jnz     .report
    ; FILE.pub
    mov     rdi, rbx
    call    upk_pub_name
    test    rax, rax
    jnz     .report
    mov     rdi, rdx
    lea     rsi, [rel upk_keybuf + 32]
    mov     edx, 32
    mov     ecx, 0o644
    call    upk_write_whole
    test    rax, rax
    jnz     .report
    ; "public key: <hex>"
    lea     rdi, [rel upk_hex]
    lea     rsi, [rel upk_keybuf + 32]
    lea     r8, [rel upk_hexdig]
    mov     ecx, 32
.hex:
    movzx   eax, byte [rsi]
    mov     edx, eax
    shr     eax, 4
    and     edx, 15
    mov     al, [r8 + rax]
    mov     [rdi], al
    mov     al, [r8 + rdx]
    mov     [rdi + 1], al
    add     rdi, 2
    inc     rsi
    dec     ecx
    jnz     .hex
    mov     byte [rdi], 10
    mov     byte [rdi + 1], 0
    mov     edi, 1
    lea     rsi, [rel upk_msg_pub]
    call    print_str
    mov     edi, 1
    lea     rsi, [rel upk_hex]
    call    print_str
    xor     eax, eax
    jmp     .ret
.no_random:
    mov     eax, EXIT_UPK_KEY
    mov     rdi, rbx
    push    rax
    call    error_set_subject
    pop     rax
.report:
    mov     edi, eax
    call    error_report_code
    mov     eax, 1
.ret:
    ; the seed does not stay in memory longer than needed
    lea     rdi, [rel upk_keybuf]
    mov     r12, rax
    xor     eax, eax
    mov     ecx, 64
    rep     stosb
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- upk_pub_name -------------------------------------------------------
; RDI = FILE -> RAX = EXIT_OK or EXIT_OOM, RDX = "FILE.pub" (arena).
upk_pub_name:
    push    rbx
    mov     rbx, rdi
    xor     ecx, ecx
.len:
    cmp     byte [rbx + rcx], 0
    je      .have_len
    inc     rcx
    jmp     .len
.have_len:
    push    rcx
    lea     rsi, [rcx + 8]
    mov     rdi, [rel global_ctx + ASMCTX_arena]
    call    arena_alloc
    pop     rcx
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    mov     rsi, rbx
    rep     movsb
    mov     dword [rdi], '.pub'
    mov     byte [rdi + 4], 0
    xor     eax, eax
.ret:
    pop     rbx
    ret

; ---- upk_write_whole ----------------------------------------------------
; RDI = path, RSI = bytes, EDX = length, ECX = mode -> RAX = EXIT_OK or an
; error (the subject set to the path).
upk_write_whole:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     edx, ecx
    call    io_create
    test    rax, rax
    jnz     .failed
    mov     r14, rdx
    mov     edi, r14d
    mov     rsi, r12
    mov     edx, r13d
    call    io_write
    push    rax
    mov     rdi, r14
    call    io_close
    pop     rax
    test    rax, rax
    jz      .ret
.failed:
    push    rax
    mov     rdi, rbx
    call    error_set_subject
    pop     rax
.ret:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
