; Copied from the Utkarsha OS repository, lib/crypto/usign/ed25519/ed25519.asm, at commit 1057f104,
; for utasm -f upk (package signing). Keep it in step with that file.
%ifndef GUARD_CRYPTO_USIGN_ED25519_ED25519_ASM
%define GUARD_CRYPTO_USIGN_ED25519_ED25519_ASM
; =============================================================================
; Utkarsha OS — crypto/usign/ed25519/ed25519.asm
; =============================================================================
; Ed25519 (RFC 8032) — signature verification.
;
; Implements:
;   - Verification (`ed25519_verify`)
;   - Capability report (`ed25519_available`)
;
; Layers, each with its own file and its own tests:
;   fe25519.asm   field arithmetic modulo 2^255 - 19
;   sc25519.asm   scalar arithmetic modulo the group order L
;   ge25519.asm   curve points, decompression, scalar multiplication
;
; VERIFICATION CHECKS [S]B == R + [k]A, with k = SHA-512(R || A || M) mod L.
; The equation is decided by compressing both sides and comparing the 32-byte
; encodings, which is exact: compression is injective on curve points.
;
; The digest is read as a LITTLE-endian integer even though SHA-512 emits its
; state big-endian. That is what RFC 8032 specifies, and getting it backwards
; produces a verifier that rejects every valid signature — a failure that is at
; least loud. The reverse mistake, in the malleability checks below, is silent.
;
; SIGNING USES A DIFFERENT SCALAR MULTIPLICATION FROM VERIFICATION. Verification
; multiplies public scalars, so it takes the fast variable-time path. Signing
; multiplies the private scalar and the per-signature nonce, so it uses
; `ge25519_scalarmult_ct`, which performs a doubling and an addition at every
; bit position and selects between them with a mask. Sharing the fast routine
; between the two would leak the private key through timing to anyone able to
; measure it — the signature would still be valid, so nothing would look wrong.
;
; SIGNING IS DETERMINISTIC. The nonce is SHA-512(prefix || message), where the
; prefix is the half of the seed hash that is not the scalar. It is never
; drawn from the RNG. ECDSA's requirement for a fresh random nonce per
; signature is the single most common way real deployments lose private keys:
; two signatures under one nonce give up the key by elementary algebra.
; Ed25519 removes the possibility rather than managing it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "src/lib/ed25519/ed25519_defs.inc"
%include "src/lib/ed25519/fe25519.inc"
%include "src/lib/ed25519/sc25519.inc"
%include "src/lib/ed25519/ge25519.inc"

section .data
align 32

; Prime modulus p = 2^255 - 19, little-endian limbs.
global curve25519_p
curve25519_p:
    dq 0xFFFFFFFFFFFFFFED, 0xFFFFFFFFFFFFFFFF
    dq 0xFFFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; Group order L = 2^252 + 27742317777372353535851937790883648493.
global curve25519_l
curve25519_l:
    dq 0x5812631A5CF5D3ED, 0x14DEF9DEA2F79CD6
    dq 0x0000000000000000, 0x1000000000000000

ed25519_verifies:   dq 0
ed25519_rejects:    dq 0

section .text

global ed25519_keygen
global ed25519_sign
global ed25519_verify
global ed25519_available
global ed25519_public_from_seed
global ed25519_clamp

; Stack frame for verification.
%define V_A     0                   ; Public key point
%define V_R     128                 ; Signature R point
%define V_LHS   256                 ; [S]B
%define V_RHS   384                 ; R + [k]A
%define V_HASH  512                 ; SHA-512 digest
%define V_K     576                 ; k = digest mod L
%define V_C1    608                 ; Compressed LHS
%define V_C2    640                 ; Compressed RHS
%define V_CTX   672                 ; SHA-512 context
%define V_FRAME (672 + sha512_ctx_t_size)

; -----------------------------------------------------------------------------
; ed25519_available
;
; Returns:
;   RAX = 1 — verification is implemented
;
; Callers use this to decide whether an Ed25519 credential can be honoured at
; all. Signing, verification and key generation are all implemented.
; -----------------------------------------------------------------------------
align 32
ed25519_available:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ed25519_verify
;
; Inputs:
;   RDI = 32-byte public key A
;   RSI = Message pointer
;   RDX = Message length
;   RCX = 64-byte signature, R || S
;
; Returns:
;   RAX = 1 when the signature is valid, 0 otherwise
;
; Rejects, in order: a non-canonical S, a public key that is not a curve point,
; an R that is not a curve point, and finally an equation that does not hold.
; The first three are structural and cost nothing; doing them before the two
; scalar multiplications also keeps malformed input cheap to refuse.
; -----------------------------------------------------------------------------
align 32
ed25519_verify:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, V_FRAME

    mov rbx, rdi                    ; Public key
    mov rbp, rsi                    ; Message
    mov r12, rdx                    ; Message length
    mov r13, rcx                    ; Signature

    test rbx, rbx
    jz .bad
    test r13, r13
    jz .bad

    ; ---- 1. S must be canonical ----
    ; S and S + L both satisfy the verification equation. Accepting both would
    ; give every signature a second valid encoding, so anything keyed on the
    ; signature bytes — a replay cache, an audit record, a transaction id —
    ; could be bypassed with a trivially derived duplicate.
    lea rdi, [r13 + 32]
    call sc25519_lt_order
    test eax, eax
    jz .bad

    ; ---- 2. Decompress the public key ----
    lea rdi, [rsp + V_A]
    mov rsi, rbx
    call ge25519_frombytes
    test eax, eax
    jnz .bad

    ; ---- 3. Decompress R ----
    lea rdi, [rsp + V_R]
    mov rsi, r13
    call ge25519_frombytes
    test eax, eax
    jnz .bad

    ; ---- 4. k = SHA-512(R || A || M) mod L ----
    ; A is bound into the hash, so a signature cannot be transplanted onto a
    ; different public key.
    lea rdi, [rsp + V_CTX]
    call sha512_init

    lea rdi, [rsp + V_CTX]
    mov rsi, r13
    mov rdx, 32
    call sha512_update

    lea rdi, [rsp + V_CTX]
    mov rsi, rbx
    mov rdx, 32
    call sha512_update

    lea rdi, [rsp + V_CTX]
    mov rsi, rbp
    mov rdx, r12
    call sha512_update

    lea rdi, [rsp + V_CTX]
    lea rsi, [rsp + V_HASH]
    call sha512_final

    lea rdi, [rsp + V_K]
    lea rsi, [rsp + V_HASH]
    call sc25519_reduce

    ; ---- 5. LHS = [S]B ----
    lea rdi, [rsp + V_LHS]
    lea rsi, [r13 + 32]
    call ge25519_scalarmult_base

    ; ---- 6. RHS = R + [k]A ----
    lea rdi, [rsp + V_RHS]
    lea rsi, [rsp + V_K]
    lea rdx, [rsp + V_A]
    call ge25519_scalarmult

    lea rdi, [rsp + V_RHS]
    lea rsi, [rsp + V_RHS]
    lea rdx, [rsp + V_R]
    call ge25519_add

    ; ---- 7. Compare ----
    lea rdi, [rsp + V_C1]
    lea rsi, [rsp + V_LHS]
    call ge25519_tobytes

    lea rdi, [rsp + V_C2]
    lea rsi, [rsp + V_RHS]
    call ge25519_tobytes

    mov rax, [rsp + V_C1]
    xor rax, [rsp + V_C2]
    mov rcx, [rsp + V_C1 + 8]
    xor rcx, [rsp + V_C2 + 8]
    or rax, rcx
    mov rcx, [rsp + V_C1 + 16]
    xor rcx, [rsp + V_C2 + 16]
    or rax, rcx
    mov rcx, [rsp + V_C1 + 24]
    xor rcx, [rsp + V_C2 + 24]
    or rax, rcx

    test rax, rax
    jnz .bad

    inc qword [ed25519_verifies]
    mov rax, 1
    jmp .out

.bad:
    inc qword [ed25519_rejects]
    xor eax, eax

.out:
    add rsp, V_FRAME
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Stack frame for signing.
%define S_HASH   0                  ; SHA-512 output, 64
%define S_A      64                 ; Clamped secret scalar, 32
%define S_PREFIX 96                 ; Nonce prefix, 32
%define S_R      128                ; Nonce scalar, 32
%define S_K      160                ; Challenge scalar, 32
%define S_PUB    192                ; Compressed public key, 32
%define S_PT     224                ; A curve point, 128
%define S_CTX    352                ; SHA-512 context
%define S_FRAME  (352 + sha512_ctx_t_size)

; -----------------------------------------------------------------------------
; ed25519_clamp — RDI = 32-byte scalar, adjusted in place.
;
; Clears the three low bits, clears the top bit and sets bit 254.
;
; The low bits are cleared so the scalar is a multiple of the cofactor 8, which
; keeps every scalar multiplication inside the prime-order subgroup — otherwise
; a small-order component of an attacker-supplied point would leak the scalar
; modulo 8. Setting bit 254 fixes the position of the leading bit, so a
; variable-time ladder cannot reveal the scalar's magnitude.
; -----------------------------------------------------------------------------
align 32
ed25519_clamp:
    and byte [rdi], 0xF8
    and byte [rdi + 31], 0x7F
    or  byte [rdi + 31], 0x40
    ret

; -----------------------------------------------------------------------------
; ed25519_public_from_seed
;
; Inputs:
;   RDI = 32-byte public key output
;   RSI = 32-byte private seed
;
; Returns:
;   RAX = 1
;
; The seed is hashed and only the LOW half becomes the scalar; the high half is
; the nonce prefix and never touches the curve. Using the seed directly as a
; scalar would skip the clamping and tie the nonce to the key.
; -----------------------------------------------------------------------------
align 32
ed25519_public_from_seed:
    push rbx
    push r12
    sub rsp, S_FRAME

    mov rbx, rdi                    ; Public key output
    mov r12, rsi                    ; Seed

    lea rdi, [rsp + S_CTX]
    call sha512_init
    lea rdi, [rsp + S_CTX]
    mov rsi, r12
    mov rdx, 32
    call sha512_update
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_HASH]
    call sha512_final

    lea rdi, [rsp + S_A]
    lea rsi, [rsp + S_HASH]
    mov ecx, 32
    rep movsb
    lea rdi, [rsp + S_A]
    call ed25519_clamp

    lea rdi, [rsp + S_PT]
    lea rsi, [rsp + S_A]
    call ge25519_scalarmult_base_ct

    mov rdi, rbx
    lea rsi, [rsp + S_PT]
    call ge25519_tobytes

    ; The hash holds the private scalar; do not leave it on the stack.
    lea rdi, [rsp]
    mov ecx, (S_PT - S_HASH) / 8
    xor eax, eax
.wipe:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .wipe

    mov rax, 1
    add rsp, S_FRAME
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ed25519_keygen
;
; Inputs:
;   RDI = 32-byte private seed output
;   RSI = 32-byte public key output
;
; Returns:
;   RAX = 1 on success, 0 when the entropy source refused
;
; On failure NOTHING is written. A key pair generated from a failed RNG call
; would be derived from whatever the buffer already held — reproducible, and
; catastrophically so.
; -----------------------------------------------------------------------------
align 32
ed25519_keygen:
    push rbx
    push r12

    mov rbx, rdi                    ; Seed output
    mov r12, rsi                    ; Public key output

    test rbx, rbx
    jz .fail
    test r12, r12
    jz .fail

    mov rdi, rbx
    mov rsi, 32
    call urand_get_bytes
    cmp rax, 32
    jne .fail                       ; Short read is a failure, not a warning

    mov rdi, r12
    mov rsi, rbx
    call ed25519_public_from_seed

    mov rax, 1
    pop r12
    pop rbx
    ret

.fail:
    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ed25519_sign
;
; Inputs:
;   RDI = 32-byte private seed
;   RSI = Message pointer
;   RDX = Message length
;   RCX = 64-byte signature output, R || S
;
; Returns:
;   RAX = 1 on success, 0 on a null argument
;
;   a, prefix = SHA-512(seed)          a clamped
;   A         = compress([a]B)
;   r         = SHA-512(prefix || M) mod L
;   R         = compress([r]B)
;   k         = SHA-512(R || A || M) mod L
;   S         = (r + k*a) mod L
;
; A IS HASHED INTO k. Without it a signature could be replayed under a
; different public key chosen by an attacker, which breaks any protocol that
; treats "this key signed this" as an identity claim.
; -----------------------------------------------------------------------------
align 32
ed25519_sign:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, S_FRAME

    mov rbx, rdi                    ; Seed
    mov rbp, rsi                    ; Message
    mov r12, rdx                    ; Message length
    mov r13, rcx                    ; Signature output

    test rbx, rbx
    jz .fail
    test r13, r13
    jz .fail

    ; ---- a, prefix = SHA-512(seed) ----
    lea rdi, [rsp + S_CTX]
    call sha512_init
    lea rdi, [rsp + S_CTX]
    mov rsi, rbx
    mov rdx, 32
    call sha512_update
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_HASH]
    call sha512_final

    lea rdi, [rsp + S_A]
    lea rsi, [rsp + S_HASH]
    mov ecx, 32
    rep movsb
    lea rdi, [rsp + S_A]
    call ed25519_clamp

    lea rdi, [rsp + S_PREFIX]
    lea rsi, [rsp + S_HASH + 32]
    mov ecx, 32
    rep movsb

    ; ---- A = compress([a]B) ----
    lea rdi, [rsp + S_PT]
    lea rsi, [rsp + S_A]
    call ge25519_scalarmult_base_ct
    lea rdi, [rsp + S_PUB]
    lea rsi, [rsp + S_PT]
    call ge25519_tobytes

    ; ---- r = SHA-512(prefix || M) mod L ----
    lea rdi, [rsp + S_CTX]
    call sha512_init
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_PREFIX]
    mov rdx, 32
    call sha512_update
    lea rdi, [rsp + S_CTX]
    mov rsi, rbp
    mov rdx, r12
    call sha512_update
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_HASH]
    call sha512_final

    lea rdi, [rsp + S_R]
    lea rsi, [rsp + S_HASH]
    call sc25519_reduce

    ; ---- R = compress([r]B), written straight into the signature ----
    lea rdi, [rsp + S_PT]
    lea rsi, [rsp + S_R]
    call ge25519_scalarmult_base_ct
    mov rdi, r13
    lea rsi, [rsp + S_PT]
    call ge25519_tobytes

    ; ---- k = SHA-512(R || A || M) mod L ----
    lea rdi, [rsp + S_CTX]
    call sha512_init
    lea rdi, [rsp + S_CTX]
    mov rsi, r13
    mov rdx, 32
    call sha512_update
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_PUB]
    mov rdx, 32
    call sha512_update
    lea rdi, [rsp + S_CTX]
    mov rsi, rbp
    mov rdx, r12
    call sha512_update
    lea rdi, [rsp + S_CTX]
    lea rsi, [rsp + S_HASH]
    call sha512_final

    lea rdi, [rsp + S_K]
    lea rsi, [rsp + S_HASH]
    call sc25519_reduce

    ; ---- S = (r + k*a) mod L ----
    lea rdi, [r13 + 32]
    lea rsi, [rsp + S_K]
    lea rdx, [rsp + S_A]
    lea rcx, [rsp + S_R]
    call sc25519_muladd

    ; Scrub the scalar, the prefix and the nonce. Any one of them recovers the
    ; private key: r and a together give it away directly from S.
    lea rdi, [rsp]
    mov ecx, (S_PUB - S_HASH) / 8
    xor eax, eax
.scrub:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .scrub

    mov rax, 1
    jmp .out

.fail:
    xor eax, eax

.out:
    add rsp, S_FRAME
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; GUARD_CRYPTO_USIGN_ED25519_ED25519_ASM
