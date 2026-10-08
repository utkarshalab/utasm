;
; ============================================
; File     : core/known.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ============================================================================
; A SECOND PASS FOR CONSTANTS USED BEFORE THEIR DEFINITION
; ============================================================================
; utasm reads the source once. A constant defined after its use
;
;     mov rsi, [rax + thread_t.cgroup_ptr]     ; the struc comes later
;
; is unknown when the instruction is encoded, so it gets the long form (a
; disp32 and a relocation) where NASM, which reads the source several
; times, writes a disp8. To come out the same:
;
;   pass 1  every name used before it is defined is noted
;           (known_note_forward). At the end, those that turned out to be
;           constants - an equ, a structure field - whose value does not
;           depend on where code lies (SYMF_POSDEP: an expression with a
;           label, $ or an unknown name in it) are written to a memfd, and
;           utasm runs itself again with UTASM_KNOWN=<fd> (nothing has been
;           written yet).
;   pass 2  known_lookup gives those constants' values where the name is
;           still undefined: the instruction is encoded as for a constant
;           defined before it. Pass 2 never asks for a third.
;
; When pass 1 finds no such constant there is no second pass.
;
; A constant that depends on where code lies ("len equ y - x") is handed on
; too, under "\x02" and its name: pass 2 takes it as a number, and
; known_verify checks that the name has that value once the code is laid
; out (the same as the expressions below).
;
; Expressions with a label not defined yet (parser_evaluate_expression kept
; them: "push dword (end - start) / 4") are handed on too, when they are an
; instruction's operand: pass 1 lays the code out as linker_run would and
; works them out; pass 2 takes those values as numbers (known_lookup, by
; the expression's line, text and occurrence), so the instruction gets the
; form NASM gives it (6A ib, not 68 id). A value that shortens code can
; change what it measures: once the layout is final, pass 2 works each one
; out again (known_verify), and on any difference runs utasm a third time
; with the constants only - the expressions then as in pass 1.

%define FWD_CAP         (1 << 23)   ; names noted (reserved, used as needed)
%define KNOWN_OUT_CAP   (1 << 28)   ; bytes of records (reserved)

%define SYS_MEMFD       319
%define SYS_EXECVE      59
%define SEEK_SET        0
%define SEEK_END        2

extern  symbol_find
extern  mem_reserve
extern  global_ctx
extern  utasm_envp
extern  utasm_argv
extern  str_cmp
extern  error_loc_file
extern  error_loc_line

[SECTION .bss]
alignb 8
global known_pos_uses, known_diff_n, known_fwd_uses
known_fwd_uses: resq 1              ; names used before their definition (any)
known_pos_uses: resq 1              ; positions met in the expression (equ)
known_diff_n:   resq 1              ; "b - a" label differences in it
known_diff:     resq 3              ; the last: SECTION*, lo, hi
diff_tab:       resq 1              ; equ symbols that are one "b - a"
diff_n:         resq 1
%define DIFF_CAP (1 << 20)
fwd_list:       resq 1              ; names used before their definition
fwd_n:          resq 1
known_tab:      resq 1              ; pass 2: hash slots -> records
known_mask:     resq 1
known_buf:      resq 1              ; pass 2: the records
known_fd:       resq 1
known_env:      resb 40             ; "UTASM_KNOWN=" and the fd
known_len:      resq 1              ; pass 2: the records' length
defer_list:     resq 1              ; pass 1: kept expressions (operands)
defer_n:        resq 1
verify_list:    resq 1              ; pass 2: {record, value} taken
verify_n:       resq 1
occ_tab:        resq 1              ; {hash, count}: occurrences of a key
key_heap:       resq 1              ; the keys
key_used:       resq 1
%define DEFER_CAP   (1 << 20)
%define OCC_SLOTS   (1 << 20)
%define KEY_HEAP    (1 << 26)
retry_code:     resq 1              ; pass 1: an error a second pass may not have
retry_file:     resq 1              ; ... where
retry_line:     resd 1
global known_active
known_active:   resb 1              ; this is pass 2
defer_laid:     resb 1              ; pass 1 laid the code out (exec, always)

[SECTION .rodata]
known_var:      db "UTASM_KNOWN="
known_var_len   equ $ - known_var
known_exe:      db "/proc/self/exe", 0
known_memfd:    db "utasm-known", 0

[SECTION .text]

; ---- known_note_forward ------------------
;
; known_note_forward
; Pass 1: the name rsi was used before it was defined. Preserves every
; register.
;
global known_note_forward
known_note_forward:
    cmp     byte [rel known_active], 0
    jne     .ret
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     rax, [rel fwd_list]
    test    rax, rax
    jnz     .have
    push    rsi
    mov     rsi, FWD_CAP * 8
    call    mem_reserve
    pop     rsi
    test    rax, rax
    jnz     .out
    mov     [rel fwd_list], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel fwd_n]
    cmp     rcx, FWD_CAP
    jae     .out
    mov     [rax + rcx*8], rsi
    inc     qword [rel fwd_n]
.out:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

; ---- known_note_diff / known_note_equ_diff --
;
; known_note_diff: a "b - a" of two labels of one section became a number
; (rdi = SECTION*, rsi / rdx = the offsets). known_note_equ_diff: the equ
; rdi is that difference alone. At the end of pass 1 such an equ is handed
; on when nothing between a and b can change size: no code section, no
; jump or padding the optimizer resizes (relax_range_fixed). Both preserve
; every register.
;
global known_note_diff, known_note_equ_diff
known_note_diff:
    inc     qword [rel known_diff_n]
    mov     [rel known_diff], rdi
    mov     [rel known_diff + 8], rsi
    mov     [rel known_diff + 16], rdx
    ret

known_note_equ_diff:
    cmp     byte [rel known_active], 0
    jne     .ret
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     rax, [rel diff_tab]
    test    rax, rax
    jnz     .have
    mov     rsi, DIFF_CAP * 32
    call    mem_reserve
    test    rax, rax
    jnz     .out
    mov     [rel diff_tab], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel diff_n]
    cmp     rcx, DIFF_CAP
    jae     .out
    shl     rcx, 5
    add     rax, rcx
    mov     rdi, [rsp + 32]                ; the symbol (pushed rdi)
    mov     [rax], rdi
    mov     rdx, [rel known_diff]
    mov     [rax + 8], rdx
    mov     rdx, [rel known_diff + 8]
    mov     [rax + 16], rdx
    mov     rdx, [rel known_diff + 16]
    mov     [rax + 24], rdx
    inc     qword [rel diff_n]
.out:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

; ---- known_hash (internal) ---------------
; rsi = name -> rax = FNV-1a. Clobbers rcx, rdx.
known_hash:
    mov     rax, 0xcbf29ce484222325
    mov     rcx, 0x100000001b3
.byte:
    movzx   edx, byte [rsi]
    test    edx, edx
    jz      .done
    xor     al, dl
    imul    rax, rcx
    inc     rsi
    jmp     .byte
.done:
    ret

; ---- known_lookup ------------------------
;
; known_lookup
; Pass 2: the value pass 1 found for the constant rsi.
; Output   : rax = 1 and rdx = the value, or rax = 0
; Preserves: everything else
;
global known_lookup
known_lookup:
    xor     eax, eax
    cmp     qword [rel known_tab], 0
    je      .ret                           ; pass 1, or nothing was handed on
    push    rcx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    mov     r8, rsi
    xor     r10d, r10d                     ; r10 = 2: looking under "\x02"
    call    known_hash
.table:
    mov     r9, [rel known_tab]
.probe:
    and     rax, [rel known_mask]
    mov     rdx, [r9 + rax*8]
    test    rdx, rdx
    jz      .none
    push    rax
    push    rdx
    lea     rdi, [rdx + 8]                 ; the record's name
    test    r10d, r10d
    jz      .compare
    cmp     byte [rdi], 2
    jne     .differ
    inc     rdi
.compare:
    mov     rsi, r8
    call    str_cmp
    mov     rcx, rax
    jmp     .compared
.differ:
    mov     ecx, 1
.compared:
    pop     rdx
    pop     rax
    test    rcx, rcx
    jz      .hit
    inc     rax
    jmp     .probe
.hit:
    test    r10d, r10d
    jz      .value
    ; one that depends on the layout: checked once the code is laid out
    lea     rdi, [rdx + 8]
    mov     rsi, [rdx]
    call    known_note_verify
.value:
    mov     rdx, [rdx]                     ; the value
    mov     eax, 1
    jmp     .out
.none:
    xor     eax, eax
    test    r10d, r10d
    jnz     .out
    ; not a constant: perhaps one that depends on the layout
    mov     r10d, 2
    mov     rax, 0xcbf29ce484222325
    xor     al, 2
    mov     rcx, 0x100000001b3
    imul    rax, rcx
    mov     rsi, r8
    call    known_hash.byte
    jmp     .table
.out:
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rcx
.ret:
    ret

; ---- known_init --------------------------
;
; known_init
; At start: with UTASM_KNOWN=<fd> in the environment this is pass 2; the
; records are read and hashed.
;
global known_init
known_init:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, [rel utasm_envp]
    test    rbx, rbx
    jz      .ret
.var:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .ret
    add     rbx, 8
    lea     rdi, [rel known_var]
    xor     ecx, ecx
.cmp:
    cmp     ecx, known_var_len
    je      .found
    mov     al, [rsi + rcx]
    cmp     al, [rdi + rcx]
    jne     .var
    inc     ecx
    jmp     .cmp
.found:
    ; the fd
    add     rsi, known_var_len
    xor     r12d, r12d
.digit:
    movzx   eax, byte [rsi]
    sub     eax, '0'
    cmp     eax, 9
    ja      .have_fd
    imul    r12, r12, 10
    add     r12, rax
    inc     rsi
    jmp     .digit
.have_fd:
    mov     byte [rel known_active], 1     ; pass 2, whatever happens next
    mov     eax, AMD64_SYS_LSEEK
    mov     rdi, r12
    xor     esi, esi
    mov     edx, SEEK_END
    syscall
    test    rax, rax
    jle     .close
    mov     r13, rax                       ; size
    mov     eax, AMD64_SYS_LSEEK
    mov     rdi, r12
    xor     esi, esi
    mov     edx, SEEK_SET
    syscall
    lea     rsi, [r13 + 16]
    call    mem_reserve
    test    rax, rax
    jnz     .close
    mov     [rel known_buf], rdx
    mov     r14, rdx
    xor     r15d, r15d                     ; read so far
.read:
    cmp     r15, r13
    jae     .read_done
    mov     eax, AMD64_SYS_READ
    mov     rdi, r12
    lea     rsi, [r14 + r15]
    mov     rdx, r13
    sub     rdx, r15
    syscall
    test    rax, rax
    jle     .read_done
    add     r15, rax
    jmp     .read
.read_done:
    mov     r13, r15
    mov     [rel known_len], r15
    ; count the records: value (8), name, NUL
    xor     ecx, ecx
    xor     edx, edx
.count:
    cmp     rdx, r13
    jae     .counted
    add     rdx, 8
.count_name:
    cmp     rdx, r13
    jae     .counted
    cmp     byte [r14 + rdx], 0
    je      .count_end
    inc     rdx
    jmp     .count_name
.count_end:
    inc     rdx
    inc     rcx
    jmp     .count
.counted:
    ; slots: a power of two, at least twice the records
    mov     eax, 1024
.size:
    lea     rdx, [rcx * 2]
    cmp     rax, rdx
    jae     .sized
    shl     rax, 1
    jmp     .size
.sized:
    lea     rdx, [rax - 1]
    mov     [rel known_mask], rdx
    lea     rsi, [rax * 8]
    call    mem_reserve
    test    rax, rax
    jnz     .close
    mov     [rel known_tab], rdx
    ; insert each record
    xor     r15d, r15d
.insert:
    cmp     r15, r13
    jae     .close
    lea     rbx, [r14 + r15]               ; the record
    lea     rsi, [rbx + 8]
    call    known_hash
    mov     rdi, [rel known_tab]
.slot:
    and     rax, [rel known_mask]
    cmp     qword [rdi + rax*8], 0
    je      .put
    inc     rax
    jmp     .slot
.put:
    mov     [rdi + rax*8], rbx
    add     r15, 8
.skip_name:
    cmp     byte [r14 + r15], 0
    je      .next_record
    inc     r15
    jmp     .skip_name
.next_record:
    inc     r15
    jmp     .insert
.close:
    mov     eax, AMD64_SYS_CLOSE
    mov     rdi, r12
    syscall
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- known_second_pass -------------------
;
; known_second_pass
; End of pass 1, before anything is written: when constants were used
; before their definition, utasm runs again knowing them. Returns when
; there is nothing to gain (or this is pass 2, or the exec fails).
;
global known_second_pass
known_second_pass:
    cmp     byte [rel known_active], 0
    jne     .quick_ret
    cmp     qword [rel fwd_n], 0
    jne     .work
    cmp     qword [rel retry_code], 0
    jne     .work
.quick_ret:
    xor     eax, eax
    ret
.work:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    ; "len equ $ - msg" over a string: fixed after all
    xor     r12d, r12d
.diff:
    cmp     r12, [rel diff_n]
    jae     .diffs_done
    mov     rbx, r12
    shl     rbx, 5
    add     rbx, [rel diff_tab]
    inc     r12
    mov     rdi, [rbx + 8]                 ; SECTION*
    cmp     byte [rdi + SECTION_type], SEC_TEXT
    je      .diff
    mov     rsi, [rbx + 16]
    mov     rdx, [rbx + 24]
    extern  relax_range_fixed
    call    relax_range_fixed
    test    eax, eax
    jz      .diff
    mov     rax, [rbx]
    and     byte [rax + SYMBOL_pflags], ~SYMF_POSDEP
    jmp     .diff
.diffs_done:
    ; equs of something defined later (parser_late_equs): worked out from
    ; the code laid out, before the names are handed on - a constant among
    ; them is one (one that names nothing defined fails in the last pass)
    extern  late_equ_n, parser_late_equs
    cmp     qword [rel late_equ_n], 0
    je      .late_done
    call    known_layout
    mov     byte [rel defer_laid], 1
    call    parser_late_equs
.late_done:
    mov     rsi, KNOWN_OUT_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; the records
    xor     r14d, r14d                     ; their length
    xor     r15d, r15d                     ; how many
    xor     r12d, r12d                     ; fwd_list index
.name:
    cmp     r12, [rel fwd_n]
    jae     .names_done
    mov     rax, [rel fwd_list]
    mov     rsi, [rax + r12*8]
    inc     r12
    lea     rdi, [rel global_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .name
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .name
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .name
    test    byte [rdx + SYMBOL_pflags], SYMF_KNOWN
    jnz     .name
    or      byte [rdx + SYMBOL_pflags], SYMF_KNOWN
    mov     rax, KNOWN_OUT_CAP - 4096
    cmp     r14, rax
    jae     .names_done
    mov     rax, [rdx + SYMBOL_value]
    mov     [r13 + r14], rax
    add     r14, 8
    ; one that depends on the layout: under "\x02", checked in pass 2
    test    byte [rdx + SYMBOL_pflags], SYMF_POSDEP
    jz      .plain_name
    mov     byte [r13 + r14], 2
    inc     r14
.plain_name:
    mov     rsi, [rdx + SYMBOL_name]
.copy:
    mov     al, [rsi]
    mov     [r13 + r14], al
    inc     r14
    inc     rsi
    test    al, al
    jnz     .copy
    inc     r15
    jmp     .name
.names_done:
    ; expressions kept for a label not defined yet: their values, from the
    ; code laid out as linker_run lays it
    cmp     qword [rel defer_n], 0
    je      .defers_done
    cmp     byte [rel defer_laid], 0
    jne     .laid
    call    known_layout
    mov     byte [rel defer_laid], 1
.laid:
    xor     r12d, r12d
.defer:
    cmp     r12, [rel defer_n]
    jae     .defers_done
    mov     rax, [rel defer_list]
    mov     rbx, [rax + r12*8]             ; the record
    inc     r12
    mov     rdi, rbx
    extern  parser_deferred_value
    call    parser_deferred_value
    test    rax, rax
    jnz     .defer
    test    r11, r11
    jz      .defer_value
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    jne     .defer                         ; an address in an object: no number
.defer_value:
    mov     rax, KNOWN_OUT_CAP - 65536
    cmp     r14, rax
    jae     .defers_done
    mov     [r13 + r14], rdx
    add     r14, 8
    mov     rsi, [rbx + DEFER_KEY]
.defer_copy:
    mov     al, [rsi]
    mov     [r13 + r14], al
    inc     r14
    inc     rsi
    test    al, al
    jnz     .defer_copy
    inc     r15
    jmp     .defer
.defers_done:
    test    r15, r15
    jnz     .exec
    cmp     byte [rel defer_laid], 0
    jne     .exec
    cmp     qword [rel retry_code], 0
    je      .ret                           ; nothing a second pass would change
.exec:
    mov     rdi, r13
    mov     rsi, r14
    call    known_exec
.ret:
    ; no second pass after all: an error kept for one is this pass's
    mov     rax, [rel retry_code]
    test    rax, rax
    jz      .out
    mov     rdx, [rel retry_file]
    mov     [rel error_loc_file], rdx
    mov     edx, [rel retry_line]
    mov     [rel error_loc_line], edx
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- known_defer_error --------------------
;
; known_defer_error
; Pass 1: an error a second pass may not have - "times n" or "resb n" with
; n an equ further on. It is kept (the first one, where it is), and a
; second pass is made; known_second_pass reports it when there is none.
; Input    : edi = the error
; Output   : eax = 0 when kept (go on as for 0), else the error (report it)
; Preserves: everything else
;
global known_defer_error
known_defer_error:
    mov     eax, edi
    cmp     byte [rel known_active], 0
    jne     .ret
    cmp     qword [rel retry_code], 0
    jne     .kept
    push    rdx
    mov     [rel retry_code], rax
    mov     rdx, [rel error_loc_file]
    mov     [rel retry_file], rdx
    mov     edx, [rel error_loc_line]
    mov     [rel retry_line], edx
    pop     rdx
.kept:
    xor     eax, eax
.ret:
    ret

; ---- known_exec (internal) ----------------
; Runs utasm again with the records rdi (rsi bytes) in a memfd: UTASM_KNOWN
; =<fd>. Returns only when that fails.
known_exec:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r13, rdi
    mov     r14, rsi
    ; the records in a memfd the next utasm inherits
    mov     eax, SYS_MEMFD
    lea     rdi, [rel known_memfd]
    xor     esi, esi
    syscall
    test    rax, rax
    js      .ret
    mov     rbx, rax                       ; fd
    xor     r12d, r12d
.write:
    cmp     r12, r14
    jae     .written
    mov     eax, AMD64_SYS_WRITE
    mov     rdi, rbx
    lea     rsi, [r13 + r12]
    mov     rdx, r14
    sub     rdx, r12
    syscall
    test    rax, rax
    jle     .ret
    add     r12, rax
    jmp     .write
.written:
    ; "UTASM_KNOWN=<fd>"
    lea     rdi, [rel known_env]
    lea     rsi, [rel known_var]
    mov     ecx, known_var_len
    rep movsb
    mov     rax, rbx
    sub     rsp, 32
    lea     r8, [rsp + 31]
    mov     byte [r8], 0
    mov     ecx, 10
.fd_digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .fd_digit
.fd_copy:
    mov     al, [r8]
    mov     [rdi], al
    inc     r8
    inc     rdi
    test    al, al
    jnz     .fd_copy
    add     rsp, 32
    ; the environment with it added
    mov     rbx, [rel utasm_envp]
    xor     ecx, ecx
    test    rbx, rbx
    jz      .counted
.count:
    cmp     qword [rbx + rcx*8], 0
    je      .counted
    inc     rcx
    jmp     .count
.counted:
    mov     r12, rcx
    lea     rsi, [rcx*8 + 16]
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    xor     ecx, ecx
.env:
    cmp     rcx, r12
    jae     .env_done
    mov     rax, [rbx + rcx*8]
    mov     [rdx + rcx*8], rax
    inc     rcx
    jmp     .env
.env_done:
    lea     rax, [rel known_env]
    mov     [rdx + rcx*8], rax
    mov     qword [rdx + rcx*8 + 8], 0
    mov     eax, SYS_EXECVE
    lea     rdi, [rel known_exe]
    mov     rsi, [rel utasm_argv]
    syscall                                ; returns only when it fails
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- known_layout (internal) --------------
; The code laid out as linker_run lays it before the relocations: jumps
; shortened, sections placed (a flat binary, an executable). Pass 1 then
; runs utasm again, so this is done once.
known_layout:
    push    rbx
    lea     rbx, [rel global_ctx]
    extern  relax_run
    mov     rdi, rbx
    call    relax_run
    cmp     byte [rbx + ASMCTX_standalone], 0
    je      .not_standalone
    extern  elf64_standalone_layout
    mov     rdi, rbx
    call    elf64_standalone_layout
.not_standalone:
    cmp     byte [rbx + ASMCTX_fmt], FMT_BIN
    jne     .ret
    extern  binary_layout
    mov     rdi, rbx
    call    binary_layout
.ret:
    pop     rbx
    ret

; ---- known_defer_key ----------------------
;
; known_defer_key
; The name a kept expression is known by across the passes: "\x01" line
; ":" text "#" n - the n-th time that text was kept on that line (a macro
; body line is read again for every call).
; Input    : rdi = its text, esi = its line
; Output   : rax = the key, or 0
; Preserves: rbx, r12-r15
;
global known_defer_key
known_defer_key:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13d, esi
    mov     rax, [rel key_heap]
    test    rax, rax
    jnz     .have_heap
    mov     rsi, KEY_HEAP
    call    mem_reserve
    test    rax, rax
    jnz     .none
    mov     [rel key_heap], rdx
    mov     rsi, OCC_SLOTS * 16
    call    mem_reserve
    test    rax, rax
    jnz     .none
    mov     [rel occ_tab], rdx
.have_heap:
    ; room for the text, the line and the count
    mov     rdi, r12
    xor     ecx, ecx
.len:
    cmp     byte [rdi + rcx], 0
    je      .len_done
    inc     rcx
    jmp     .len
.len_done:
    lea     rdx, [rcx + 64]
    add     rdx, [rel key_used]
    cmp     rdx, KEY_HEAP
    ja      .none
    mov     rbx, [rel key_heap]
    add     rbx, [rel key_used]            ; the key
    mov     rdi, rbx
    mov     byte [rdi], 1
    inc     rdi
    mov     eax, r13d
    call    .decimal
    mov     byte [rdi], ':'
    inc     rdi
    mov     rsi, r12
.text:
    mov     al, [rsi]
    test    al, al
    jz      .text_done
    mov     [rdi], al
    inc     rdi
    inc     rsi
    jmp     .text
.text_done:
    mov     byte [rdi], 0
    ; its occurrence
    push    rdi
    mov     rsi, rbx
    call    known_hash
    pop     rdi
    mov     r8, [rel occ_tab]
    mov     r9, rax
    mov     ecx, OCC_SLOTS - 1
.slot:
    and     rax, rcx
    mov     rdx, rax
    shl     rdx, 4
    cmp     qword [r8 + rdx], 0
    je      .new_slot
    cmp     [r8 + rdx], r9
    je      .slot_found
    inc     rax
    jmp     .slot
.new_slot:
    mov     [r8 + rdx], r9
    mov     qword [r8 + rdx + 8], 0
.slot_found:
    mov     rax, [r8 + rdx + 8]
    inc     qword [r8 + rdx + 8]
    mov     byte [rdi], '#'
    inc     rdi
    call    .decimal
    mov     byte [rdi], 0
    inc     rdi
    mov     rax, rdi
    sub     rax, [rel key_heap]
    mov     [rel key_used], rax
    mov     rax, rbx
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
; .decimal: rax in decimal at rdi, rdi past it
.decimal:
    sub     rsp, 32
    mov     r10, rsp
    mov     r11d, 10
    xor     ecx, ecx
.digit:
    xor     edx, edx
    div     r11
    add     dl, '0'
    mov     [r10 + rcx], dl
    inc     ecx
    test    rax, rax
    jnz     .digit
.out:
    dec     ecx
    mov     al, [r10 + rcx]
    mov     [rdi], al
    inc     rdi
    test    ecx, ecx
    jnz     .out
    add     rsp, 32
    ret

; ---- known_note_defer ---------------------
;
; known_note_defer
; Pass 1: a kept expression, an instruction's operand (rdi = its record):
; its value is handed on to pass 2. Preserves every register.
;
global known_note_defer
known_note_defer:
    cmp     byte [rel known_active], 0
    jne     .ret
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     rax, [rel defer_list]
    test    rax, rax
    jnz     .have
    mov     rsi, DEFER_CAP * 8
    call    mem_reserve
    test    rax, rax
    jnz     .out
    mov     [rel defer_list], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel defer_n]
    cmp     rcx, DEFER_CAP
    jae     .out
    mov     rdi, [rsp + 32]                ; (the pushed rdi)
    mov     [rax + rcx*8], rdi
    inc     qword [rel defer_n]
.out:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

; ---- known_note_verify --------------------
;
; known_note_verify
; Pass 2: the value pass 1 found was taken for the kept expression rdi
; (rsi = the value): known_verify checks it. Preserves every register.
;
global known_note_verify
known_note_verify:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    mov     rax, [rel verify_list]
    test    rax, rax
    jnz     .have
    mov     rsi, DEFER_CAP * 16
    call    mem_reserve
    test    rax, rax
    jnz     .out
    mov     [rel verify_list], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel verify_n]
    cmp     rcx, DEFER_CAP
    jae     .out
    shl     rcx, 4
    mov     rdi, [rsp + 32]                ; the record
    mov     rsi, [rsp + 40]                ; the value
    mov     [rax + rcx], rdi
    mov     [rax + rcx + 8], rsi
    inc     qword [rel verify_n]
.out:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ---- known_verify -------------------------
;
; known_verify
; Pass 2, the code laid out: each value taken for a kept expression must
; be what the expression is now. When one is not, utasm runs again with the
; constants only (the expressions then as in pass 1); nothing has been
; written yet.
;
global known_verify
known_verify:
    cmp     qword [rel verify_n], 0
    jne     .check
    ret
.check:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r12d, r12d
.item:
    cmp     r12, [rel verify_n]
    jae     .all_hold
    mov     rbx, r12
    shl     rbx, 4
    add     rbx, [rel verify_list]
    inc     r12
    mov     rdi, [rbx]
    cmp     byte [rdi], 2
    je      .item_name
    call    parser_deferred_value
    test    rax, rax
    jnz     .differs
    cmp     rdx, [rbx + 8]
    jne     .differs
    jmp     .item
.item_name:
    ; a name taken for a constant that depends on the layout: it must be
    ; defined, with that value
    lea     rsi, [rdi + 1]
    lea     rdi, [rel global_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .differs
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .differs
    mov     rax, [rdx + SYMBOL_value]
    cmp     rax, [rbx + 8]
    jne     .differs
    jmp     .item
.differs:
    ; the records without the expressions'
    mov     rsi, [rel known_len]
    add     rsi, 16
    call    mem_reserve
    test    rax, rax
    jnz     .all_hold                      ; (no memory: as it is)
    mov     r13, rdx                       ; the copy
    xor     r14d, r14d                     ; its length
    mov     r15, [rel known_buf]
    xor     ecx, ecx                       ; read
.record:
    cmp     rcx, [rel known_len]
    jae     .copied
    mov     rbx, rcx                       ; the record's start
    add     rcx, 8
.name_end:
    cmp     byte [r15 + rcx], 0
    je      .name_ended
    inc     rcx
    jmp     .name_end
.name_ended:
    inc     rcx                            ; past the NUL
    cmp     byte [r15 + rbx + 8], 1
    je      .record                        ; an expression's: dropped
    cmp     byte [r15 + rbx + 8], 2
    je      .record                        ; one that depends on the layout
.keep:
    cmp     rbx, rcx
    jae     .record
    mov     al, [r15 + rbx]
    mov     [r13 + r14], al
    inc     rbx
    inc     r14
    jmp     .keep
.copied:
    mov     rdi, r13
    mov     rsi, r14
    call    known_exec
.all_hold:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
