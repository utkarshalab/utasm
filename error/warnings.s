;
; ============================================
; File     : error/warnings.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"

DEFAULT REL

; ============================================================================
; WARNINGS, AS NASM GIVES THEM
; ============================================================================
; A warning belongs to a class, by NASM's names, and ends with it:
;
;     prog.s:3: warning: uninitialized space declared in non-BSS section
;     `.text': zeroing [-w+zeroing]
;
; -w-zeroing (-Wno-zeroing) turns a class off, -w+zeroing on, "all" every
; class. Under -Werror (-w+error), or -w+error=zeroing for one class, it is
; an error instead - "error: ... [-w+error=zeroing]" - and the assembly
; fails at the end, as after %error. The listing (-l) shows each warning
; after its line, as NASM does (lst_warning).
;
;   warn_begin  edi = WC_*: starts one at the current statement; eax = 0
;               when its class is off (warn_text / warn_end then do nothing)
;   warn_text   rsi = text: the next piece of the message
;   warn_end    ends it
;   warn_option rdi = a -w / -W option: sets the classes it names
;
; Warnings are held, not written, until an error is reported or utasm
; exits (warn_flush): when a second pass follows (core/known.s runs utasm
; again), the first pass's warnings are dropped with it and each warning
; is given once, as NASM gives it.

extern print_str
extern error_report_text
extern error_report_end
extern error_deferred
extern global_ctx
extern lst_warning
extern str_cmp

%define WARN_BUF    2048

[SECTION .data]
; on (bit 0) and error (bit 1), by class; NASM has these on by default
warn_state:
    db 1                                ; WC_OTHER
    db 1                                ; WC_USER
    db 1                                ; WC_ZEROING
    db 1                                ; WC_PREFIX_LOCK_XCHG
    db 1                                ; WC_NUMBER_OVERFLOW
    db 1                                ; WC_PREFIX_LOCK_ERROR
    db 1                                ; WC_DB_EMPTY
    db 1                                ; WC_PP_MACRO_DEFAULTS
    db 1                                ; WC_LABEL_ORPHAN
    db 0                                ; WC_PIE (utasm's own: -w+pie, -w+all)

[SECTION .rodata]
warn_names:
    dq wn_other, wn_user, wn_zeroing, wn_lock_xchg, wn_overflow
    dq wn_lock_error, wn_db_empty, wn_macro_defaults, wn_label_orphan, wn_pie
wn_other:       db "other", 0
wn_user:        db "user", 0
wn_zeroing:     db "zeroing", 0
wn_lock_xchg:   db "prefix-lock-xchg", 0
wn_overflow:    db "number-overflow", 0
wn_lock_error:  db "prefix-lock-error", 0
wn_db_empty:    db "db-empty", 0
wn_macro_defaults: db "pp-macro-defaults", 0
wn_label_orphan: db "label-orphan", 0
wn_pie:         db "pie", 0
wn_all:         db "all", 0
wn_error:       db "error", 0
s_warning:      db "warning: ", 0
s_error:        db "error: ", 0
s_open:         db " [-w+", 0
s_open_error:   db " [-w+error=", 0
s_close:        db "]", 0
s_byte:         db "byte", 0
s_word:         db "word", 0
s_dword:        db "dword", 0
s_exceeds:      db " data exceeds bounds", 0

[SECTION .bss]
alignb 8
warn_hold:      resq 1                  ; the warnings held (warn_hold_put)
warn_hold_len:  resq 1
global stderr_hold
stderr_hold:    resb 1                  ; print_str: stderr goes to warn_hold
warn_final:     resb 1                  ; the source is read (warn_before_error)
warn_buf:       resb WARN_BUF           ; the message, for the listing
warn_len:       resd 1
warn_class:     resd 1
warn_active:    resb 1
warn_shown:     resb 1                  ; the last warning begun was given
warn_is_error:  resb 1

[SECTION .text]

; ---- warn_begin ---------------------------
;
; warn_begin
; Starts a warning of class edi at the current statement: "file:line:
; warning: " (or "error: " under -Werror).
; Input    : edi = WC_*
; Output   : eax = 1 when it is shown, 0 when its class is off
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global warn_begin
warn_begin:
    lea     rax, [rel warn_state]
    movzx   eax, byte [rax + rdi]
    test    al, 1
    jz      .off
    mov     [rel warn_class], edi
    mov     byte [rel warn_active], 1
    mov     byte [rel warn_shown], 1
    mov     dword [rel warn_len], 0
    xor     ecx, ecx
    test    al, 2
    jnz     .error
    lea     rdx, [rel global_ctx]
    test    dword [rdx + ASMCTX_flags], CTX_FLAG_WERROR
    jz      .severity
.error:
    mov     ecx, 1
    inc     dword [rel error_deferred]     ; fails the assembly at the end
.severity:
    mov     [rel warn_is_error], cl
    lea     rsi, [rel s_warning]
    test    ecx, ecx
    jz      .keep
    lea     rsi, [rel s_error]
.keep:
    push    rcx
    call    warn_keep
    pop     rdi
    mov     byte [rel stderr_hold], 1      ; held until warn_flush
    call    error_report_text              ; "file:line: warning: "
    mov     eax, 1
    ret
.off:
    mov     byte [rel warn_active], 0
    mov     byte [rel warn_shown], 0
    xor     eax, eax
    ret

; ---- warn_hint ----------------------------
;
; warn_hint
; After a warning, the pending "hint: did you mean" line (error/hints.s),
; held with it; dropped when the warning's class is off.
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global warn_hint
extern error_hint_flush, error_hint_clear
warn_hint:
    cmp     byte [rel warn_shown], 0
    je      error_hint_clear
    mov     byte [rel stderr_hold], 1
    call    error_hint_flush
    mov     byte [rel stderr_hold], 0
    ret

; ---- warn_text ----------------------------
;
; warn_text
; The next piece of the warning being given: on stderr, and kept for the
; listing. Nothing when its class is off.
; Input    : rsi = NUL-terminated text
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global warn_text
warn_text:
    cmp     byte [rel warn_active], 0
    je      .ret
    push    rsi
    call    warn_keep
    pop     rsi
    mov     edi, 2
    call    print_str
.ret:
    ret

; ---- warn_end -----------------------------
;
; warn_end
; Ends the warning: " [-w+class]" (" [-w+error=class]"), the newline and
; the macro note; the listing gets the text.
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global warn_end
warn_end:
    cmp     byte [rel warn_active], 0
    je      .ret
    lea     rsi, [rel s_open]
    cmp     byte [rel warn_is_error], 0
    je      .open
    lea     rsi, [rel s_open_error]
.open:
    call    warn_text
    mov     eax, [rel warn_class]
    lea     rcx, [rel warn_names]
    mov     rsi, [rcx + rax * 8]
    call    warn_text
    lea     rsi, [rel s_close]
    call    warn_text
    call    error_report_end
    mov     byte [rel stderr_hold], 0
    mov     byte [rel warn_active], 0
    lea     rdi, [rel warn_buf]
    mov     eax, [rel warn_len]
    mov     byte [rdi + rax], 0
    call    lst_warning
.ret:
    ret

; ---- warn_hold_put ------------------------
;
; warn_hold_put
; Text written to stderr while a warning is held (print_str): kept for
; warn_flush. Written at once when there is no room.
; Input    : rdi = the text, rsi = its length
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
%define WARN_HOLD   (1 << 26)
global warn_hold_put
warn_hold_put:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rax, [rel warn_hold]
    test    rax, rax
    jnz     .room
    xor     edi, edi
    mov     rsi, WARN_HOLD
    mov     edx, 3                         ; PROT_READ | PROT_WRITE
    mov     r10d, 0x4022                   ; MAP_PRIVATE | ANONYMOUS | NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    mov     eax, 9                         ; mmap
    syscall
    cmp     rax, -4095
    jae     .direct
    mov     [rel warn_hold], rax
.room:
    mov     rcx, [rel warn_hold_len]
    lea     rdx, [rcx + r12]
    cmp     rdx, WARN_HOLD
    ja      .direct
    lea     rdi, [rax + rcx]
    mov     rsi, rbx
    mov     rcx, r12
    rep     movsb
    add     [rel warn_hold_len], r12
    jmp     .ret
.direct:
    call    warn_flush
    mov     edi, 2
    mov     rsi, rbx
    mov     rdx, r12
    mov     eax, 1                         ; write
    syscall
.ret:
    pop     r12
    pop     rbx
    ret

; ---- warn_before_error --------------------
;
; warn_before_error
; An error is reported. While the source is read NASM would stop after its
; first pass and give no warning at all: the warnings held are dropped. Once
; it is read (an undefined symbol, a jump out of range: NASM's last pass)
; they are given before it.
; Preserves every register.
;
global warn_before_error
global warn_final
warn_before_error:
    cmp     byte [rel warn_final], 0
    jne     warn_flush
    mov     qword [rel warn_hold_len], 0
    ret

; ---- warn_flush ---------------------------
;
; warn_flush
; Writes the warnings held to stderr: before an error is reported, and at
; exit.
; Preserves every register.
;
global warn_flush
warn_flush:
    cmp     qword [rel warn_hold_len], 0
    je      .ret
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r11
    mov     edi, 2
    mov     rsi, [rel warn_hold]
    mov     rdx, [rel warn_hold_len]
    mov     qword [rel warn_hold_len], 0
    mov     eax, 1                         ; write
    syscall
    pop     r11
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.ret:
    ret

; ---- warn_data_bounds ---------------------
;
; warn_data_bounds
; A value written into a field of esi bytes (1, 2 or 4) that does not fit:
; NASM's "dword data exceeds bounds" (number-overflow), for anything below
; -2^n or above 2^n - 1 (n the field's bits: db -256 and db 255 fit).
; Input    : rdi = the value, esi = the field's bytes
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global warn_data_bounds
warn_data_bounds:
    cmp     esi, 4
    ja      .ret
    lea     ecx, [rsi * 8]
    mov     eax, 1
    shl     rax, cl                        ; 2^n
    cmp     rdi, rax
    jge     .over
    neg     rax
    cmp     rdi, rax
    jge     .ret
.over:
    push    rbx
    mov     ebx, esi
    mov     edi, WC_NUMBER_OVERFLOW
    call    warn_begin
    lea     rsi, [rel s_byte]
    cmp     ebx, 1
    je      .size
    lea     rsi, [rel s_word]
    cmp     ebx, 2
    je      .size
    lea     rsi, [rel s_dword]
.size:
    call    warn_text
    lea     rsi, [rel s_exceeds]
    call    warn_text
    call    warn_end
    pop     rbx
.ret:
    ret

; warn_keep: appends the text at rsi to warn_buf (as much as fits)
warn_keep:
    lea     rdi, [rel warn_buf]
    mov     eax, [rel warn_len]
.copy:
    mov     cl, [rsi]
    test    cl, cl
    jz      .done
    cmp     eax, WARN_BUF - 1
    jae     .done
    mov     [rdi + rax], cl
    inc     eax
    inc     rsi
    jmp     .copy
.done:
    mov     [rel warn_len], eax
    ret

; ---- warn_option --------------------------
;
; warn_option
; A -w / -W option: -w+name, -w-name, -Wname, -Wno-name; name "all" is
; every class; -w+error / -Werror (all) and -w+error=name, -Werror=name,
; -w-error=name, -Wno-error=name make warnings errors or not. A name it
; does not know is accepted and changes nothing, as in NASM.
; Input    : rdi = the option, "-w..." or "-W..."
; Clobbers : rax, rcx, rdx, rsi, rdi, r8-r11
;
global warn_option
warn_option:
    push    rbx
    push    r12
    push    r13
    ; r12d = 1 on / 0 off; r13d = 1: the error bit, not the on bit
    mov     r12d, 1
    xor     r13d, r13d
    cmp     byte [rdi + 1], 'W'
    je      .long_form
    ; -w+... / -w-...
    cmp     byte [rdi + 2], '+'
    je      .short_sign
    cmp     byte [rdi + 2], '-'
    jne     .ret
    xor     r12d, r12d
.short_sign:
    lea     rbx, [rdi + 3]
    jmp     .error_prefix
.long_form:
    lea     rbx, [rdi + 2]
    mov     eax, [rbx]                     ; "no-": the first three bytes
    and     eax, 0x00FFFFFF
    cmp     eax, 'no-'
    jne     .error_prefix
    xor     r12d, r12d
    add     rbx, 3
.error_prefix:
    ; "error" or "error=name"
    mov     eax, [rbx]
    cmp     eax, 'erro'
    jne     .name
    cmp     byte [rbx + 4], 'r'
    jne     .name
    movzx   eax, byte [rbx + 5]
    test    eax, eax
    jz      .all_errors
    cmp     eax, '='
    jne     .name
    mov     r13d, 1
    add     rbx, 6
    jmp     .name
.all_errors:
    ; -w+error / -Werror: every class; -w-error / -Wno-error: none
    lea     rax, [rel global_ctx]
    test    r12d, r12d
    jz      .no_werror
    or      dword [rax + ASMCTX_flags], CTX_FLAG_WERROR
    jmp     .ret
.no_werror:
    and     dword [rax + ASMCTX_flags], ~CTX_FLAG_WERROR
    jmp     .ret
.name:
    mov     rdi, rbx
    lea     rsi, [rel wn_all]
    call    str_cmp
    test    rax, rax
    jz      .every
    xor     ecx, ecx
.find:
    cmp     ecx, WC_COUNT
    jae     .ret                           ; a class utasm does not have
    push    rcx
    lea     rax, [rel warn_names]
    mov     rsi, [rax + rcx * 8]
    mov     rdi, rbx
    call    str_cmp
    pop     rcx
    test    rax, rax
    jz      .set_one
    inc     ecx
    jmp     .find
.set_one:
    call    .set
    jmp     .ret
.every:
    xor     ecx, ecx
.every_next:
    call    .set
    inc     ecx
    cmp     ecx, WC_COUNT
    jb      .every_next
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
; .set: class ecx: its on bit (r13d = 0) or error bit (r13d = 1) to r12d
.set:
    lea     rax, [rel warn_state]
    mov     dl, 1
    test    r13d, r13d
    jz      .bit
    mov     dl, 2
.bit:
    test    r12d, r12d
    jz      .clear
    or      [rax + rcx], dl
    ret
.clear:
    not     dl
    and     [rax + rcx], dl
    ret
