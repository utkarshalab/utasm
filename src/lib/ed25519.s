;
; ============================================================================
; File        : src/lib/ed25519.s
; Project     : utasm
; Description : Ed25519 signatures (RFC 8032) and SHA-512, for -f upk.
;
;   The arithmetic is Utkarsha OS's own (src/lib/ed25519/*.inc, copied from
;   its lib/crypto), so a package utasm signs is checked by the same code the
;   OS verifies it with. Exported: ed25519_public_from_seed, ed25519_sign,
;   ed25519_verify, ed25519_keygen, sha512_init / update / final.
;
;   urand_get_bytes, which ed25519_keygen needs, is the getrandom system call
;   here (the OS has its own CSPRNG).
; ============================================================================
;

default rel

%include "src/lib/ed25519/sha512_impl.inc"
%include "src/lib/ed25519/ed25519_impl.inc"

[SECTION .text]

;*
; * [urand_get_bytes]
; * Purpose: Fill a buffer with random bytes from the kernel.
; * Input  : RDI = buffer, RSI = length
; * Output : RAX = bytes written (the whole length), or 0 on failure, when
; *          nothing is to be relied on
; ;
global urand_get_bytes
urand_get_bytes:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    xor     ecx, ecx                    ; bytes so far
.more:
    cmp     rcx, r12
    jae     .done
    push    rcx
    lea     rdi, [rbx + rcx]
    mov     rsi, r12
    sub     rsi, rcx
    xor     edx, edx                    ; flags: block until seeded
    mov     eax, 318                    ; getrandom
    syscall
    pop     rcx
    cmp     rax, -4                     ; EINTR: try again
    je      .more
    test    rax, rax
    jle     .fail
    add     rcx, rax
    jmp     .more
.done:
    mov     rax, r12
    pop     r12
    pop     rbx
    ret
.fail:
    xor     eax, eax
    pop     r12
    pop     rbx
    ret
