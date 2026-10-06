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
global known_active
known_active:   resb 1              ; this is pass 2

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
    mov     r8, rsi
    call    known_hash
    mov     r9, [rel known_tab]
.probe:
    and     rax, [rel known_mask]
    mov     rdx, [r9 + rax*8]
    test    rdx, rdx
    jz      .none
    push    rax
    push    rdx
    lea     rdi, [rdx + 8]                 ; the record's name
    mov     rsi, r8
    call    str_cmp
    mov     rcx, rax
    pop     rdx
    pop     rax
    test    rcx, rcx
    jz      .hit
    inc     rax
    jmp     .probe
.hit:
    mov     rdx, [rdx]                     ; the value
    mov     eax, 1
    jmp     .out
.none:
    xor     eax, eax
.out:
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
.quick_ret:
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
    test    byte [rdx + SYMBOL_pflags], SYMF_POSDEP | SYMF_KNOWN
    jnz     .name
    or      byte [rdx + SYMBOL_pflags], SYMF_KNOWN
    mov     rax, KNOWN_OUT_CAP - 4096
    cmp     r14, rax
    jae     .names_done
    mov     rax, [rdx + SYMBOL_value]
    mov     [r13 + r14], rax
    add     r14, 8
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
    test    r15, r15
    jz      .ret                           ; nothing a second pass would change
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
