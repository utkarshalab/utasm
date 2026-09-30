;
; ============================================================================
; File        : frontend/macro/rotate.s
; Project     : utasm
; Description : %rotate - rotate the parameters of the current macro call.
;
;   %rotate n moves the arguments n places to the left: after %rotate 1,
;   %1 is what %2 was and the old %1 is last. A negative n rotates right.
;   Together with %rep %0 this walks a variadic macro's arguments:
;
;       %macro push_all 1-*
;           %rep %0
;               push %1
;               %rotate 1
;           %endrep
;       %endmacro
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  parser_evaluate_expression

%define ROT_MAX     32              ; macro arguments (MACRO_ARG_CAPACITY)

[SECTION .text]

;*
; * [prep_handle_rotate]
; * Purpose: Handle "%rotate n" (the directive name is already consumed).
; * Input  : RDI = PrepState
; * Output : RAX = OK, or an error (no macro call, bad count)
; ;
global prep_handle_rotate
prep_handle_rotate:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, ROT_MAX * 8 + ROT_MAX     ; scratch: pointers, then lengths
    mov     rbx, rdi

    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r14, rdx                       ; r14 = n

    ; the expansion that owns the parameters: a %rep body inside a macro
    ; has none of its own
    mov     rax, [rbx + PREP_ctx]
    mov     r12, [rax + ASMCTX_mac_exp]
.owner:
    test    r12, r12
    jz      .no_macro
    cmp     byte [r12 + MACROEXP_nparams], 0
    jne     .found
    mov     r12, [r12 + MACROEXP_parent]
    jmp     .owner
.found:
    movzx   r13d, byte [r12 + MACROEXP_nparams]
    cmp     r13d, ROT_MAX
    ja      .no_macro

    ; k = n mod count, as a left rotation (negative n rotates right)
    mov     rax, r14
    cqo
    idiv    r13                            ; rdx = n rem count (sign of n)
    test    rdx, rdx
    jns     .k_ok
    add     rdx, r13
.k_ok:
    mov     r15, rdx                       ; r15 = k
    test    r15, r15
    jz      .ok

    ; new[i] = old[(i + k) mod count], for the argument pointers and lengths
    mov     r8, [r12 + MACROEXP_params]
    mov     r9, [r12 + MACROEXP_arglens]
    xor     ecx, ecx
.copy:
    mov     rax, [r8 + rcx*8]
    mov     [rsp + rcx*8], rax
    movzx   eax, byte [r9 + rcx]
    mov     [rsp + ROT_MAX * 8 + rcx], al
    inc     ecx
    cmp     ecx, r13d
    jb      .copy
    xor     ecx, ecx
.place:
    lea     rax, [rcx + r15]
    cmp     rax, r13
    jb      .src_ok
    sub     rax, r13
.src_ok:
    mov     rdx, [rsp + rax*8]
    mov     [r8 + rcx*8], rdx
    movzx   edx, byte [rsp + ROT_MAX * 8 + rax]
    mov     [r9 + rcx], dl
    inc     ecx
    cmp     ecx, r13d
    jb      .place

.ok:
    mov     rax, OK
    jmp     .ret
.no_macro:
    mov     rax, EXIT_UNEXPECTED_TOKEN     ; %rotate outside a macro call
.ret:
    add     rsp, ROT_MAX * 8 + ROT_MAX
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
