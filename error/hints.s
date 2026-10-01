;
; ============================================
; File     : error/hints.s
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
; "DID YOU MEAN" HINTS
; ============================================================================
; Context-specific suggestions for common mistakes, built on the
; suggestion engine in error/suggest.s:
;
;   error_hint_mnemonic(name)      unknown instruction or directive
;   error_hint_symbol(ctx, name)   undefined symbol
;   error_hint_flush()             print the pending hint, if any
;   error_hint_clear()             drop the pending hint
;
; Finding a hint and printing it are separate on purpose: the hint is
; found where the mistake is detected (the parser, the relocation pass),
; but it must appear *after* the error line, which is printed later by
; the caller. So the finders only remember the best match, and the code
; that prints the error calls error_hint_flush afterwards:
;
;     prog.s:3: error: parser: instruction expected, found `mvo'
;     hint: did you mean 'mov'?
;
; Mnemonic candidates come from error/mnemonic_names.inc, generated from
; the real x86-64 mnemonic table, so only instructions utasm actually
; knows are ever suggested. They are used when targeting amd64; the
; directive list is used for every target.

extern global_ctx
extern suggest_begin
extern suggest_consider
extern suggest_consider_packed
extern suggest_result

[SECTION .bss]
align 8
hint_pending:   resq 1                  ; name to suggest, or 0

[SECTION .text]

; ---- error_hint_mnemonic ----------------
;
; error_hint_mnemonic
; Finds the known instruction or directive closest to an unknown one and
; keeps it as the pending hint.
; Input    : rdi = unknown mnemonic (NUL-terminated)
; Output   : rax = 1 if a hint was found, else 0
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global error_hint_mnemonic
error_hint_mnemonic:
    sub     rsp, 8
    call    suggest_begin

    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_target], TARGET_AMD64
    jne     .directives
    lea     rdi, [rel mnemonic_names_x64]
    lea     rsi, [rel mnemonic_names_x64_end]
    call    suggest_consider_packed
.directives:
    lea     rdi, [rel directive_names]
    lea     rsi, [rel directive_names_end]
    call    suggest_consider_packed

    add     rsp, 8
    jmp     hint_take_result

; ---- error_hint_symbol ------------------
;
; error_hint_symbol
; Finds the defined symbol closest to an undefined one and keeps it as
; the pending hint. Undefined symbols are never suggested.
; Input    : rdi = pointer to AsmCtx
;             rsi = undefined symbol name (NUL-terminated)
; Output   : rax = 1 if a hint was found, else 0
; Clobbers : rcx, rdx, rsi, rdi, r8-r11
;
global error_hint_symbol
error_hint_symbol:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rdi + ASMCTX_symtab]      ; rbx = current SYMBOL
    mov     r12d, [rdi + ASMCTX_symcount]   ; r12 = symbols left

    mov     rdi, rsi
    call    suggest_begin
    test    rbx, rbx
    jz      .done

.loop:
    test    r12, r12
    jz      .done
    cmp     word [rbx + SYMBOL_section], 0  ; SHN_UNDEF: not a real target
    je      .next
    mov     rdi, [rbx + SYMBOL_name]
    call    suggest_consider                ; ignores NULL names
.next:
    add     rbx, SYMBOL_SIZE
    dec     r12
    jmp     .loop

.done:
    pop     r13
    pop     r12
    pop     rbx
    jmp     hint_take_result

; ---- hint_take_result (internal) --------
;
; Stores the finished search's result as the pending hint.
; Output: rax = 1 if there is one, else 0
;
hint_take_result:
    call    suggest_result
    mov     [hint_pending], rdx
    xor     eax, eax
    test    rdx, rdx
    setnz   al
    ret

; ---- error_hint_flush -------------------
;
; error_hint_flush
; Prints the pending hint to stderr and clears it:
;     hint: did you mean '<name>'?
; Input    : none
; Output   : rax = 1 if a hint was printed, else 0
; Clobbers : rcx, rdx, rsi, rdi, r11
;
global error_hint_flush
error_hint_flush:
    mov     rsi, [hint_pending]
    test    rsi, rsi
    jz      .none
    mov     qword [hint_pending], 0
    push    rsi

    lea     rsi, [rel hint_prefix]
    mov     edx, hint_prefix_len
    call    hint_write

    mov     rsi, [rsp]
    xor     edx, edx
.len:
    cmp     byte [rsi + rdx], 0
    je      .have_len
    inc     rdx
    jmp     .len
.have_len:
    call    hint_write

    lea     rsi, [rel hint_suffix]
    mov     edx, hint_suffix_len
    call    hint_write

    add     rsp, 8
    mov     eax, 1
    ret
.none:
    xor     eax, eax
    ret

; ---- error_hint_clear -------------------
;
; error_hint_clear
; Drops the pending hint without printing it.
; Clobbers : none
;
global error_hint_clear
error_hint_clear:
    mov     qword [hint_pending], 0
    ret

; ---- hint_write (internal) --------------
;
; write(2, rsi, rdx), retrying partial writes and EINTR. Errors are
; ignored: a hint is best-effort and must never mask the real error.
; Clobbers: rax, rcx, rdx, rsi, rdi, r11
;
hint_write:
    test    rdx, rdx
    jz      .done
    mov     eax, AMD64_SYS_WRITE
    mov     edi, 2
    syscall
    cmp     rax, -4                         ; -EINTR
    je      hint_write
    test    rax, rax
    jle     .done
    add     rsi, rax
    sub     rdx, rax
    jmp     hint_write
.done:
    ret

[SECTION .rodata]
hint_prefix:     db "hint: did you mean '"
hint_prefix_len  equ $ - hint_prefix
hint_suffix:     db "'?", 10
hint_suffix_len  equ $ - hint_suffix

; Directives recognised by parser_handle_pseudo_op (frontend/parser/parser.s),
; as a packed NUL-separated list. Keep in sync when adding a directive.
directive_names:
    db "section", 0, "global", 0, "extern", 0, "weak", 0, "local", 0, "comm", 0
    db "bits", 0, "default", 0, "align", 0, "p2align", 0, "org", 0
    db "db", 0, "dw", 0, "dd", 0, "dq", 0
    db "resb", 0, "resw", 0, "resd", 0, "resq", 0, "equ", 0, "times", 0
    db "struc", 0, "endstruc", 0, "field", 0
directive_names_end:

%include "error/mnemonic_names.inc"
