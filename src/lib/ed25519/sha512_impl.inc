; Copied from the Utkarsha OS repository, lib/crypto/uhash/sha512/sha512.asm, at commit 1057f104,
; for utasm -f upk (package signing). Keep it in step with that file.
%ifndef GUARD_CRYPTO_UHASH_SHA512_SHA512_ASM
%define GUARD_CRYPTO_UHASH_SHA512_SHA512_ASM
; =============================================================================
; Utkarsha OS — crypto/uhash/sha512/sha512.asm
; =============================================================================
; SHA-512 (FIPS 180-4).
;
; Implements:
;   - Streaming context API (`sha512_init`, `sha512_update`, `sha512_final`)
;   - One-shot wrapper (`sha512_hash`)
;   - Block compression (`sha512_transform`)
;
; Structurally identical to SHA-256 but on 64-bit words: 80 rounds instead of
; 64, a 128-byte block instead of 64, different rotation amounts, and a
; 128-BIT length field rather than 64-bit.
;
; That last difference is the one that bites. The padding boundary is 112 bytes
; (block size minus 16), not 120 — reserving only 8 bytes for the length works
; on short inputs and then silently corrupts digests once a message lands in
; the 112..119 byte window of its final block.
;
; The previous version of this file was a 64-line stub with no rounds at all.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "src/lib/ed25519/sha512.inc"

section .rodata
align 64

; Round constants: first 64 bits of the fractional parts of the cube roots of
; the first 80 primes.
sha512_k:
    dq 0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc
    dq 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118
    dq 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2
    dq 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694
    dq 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65
    dq 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5
    dq 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4
    dq 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70
    dq 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df
    dq 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b
    dq 0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30
    dq 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8
    dq 0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8
    dq 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3
    dq 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec
    dq 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b
    dq 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178
    dq 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b
    dq 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c
    dq 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817

; Initial state: first 64 bits of the fractional parts of the square roots of
; the first 8 primes.
sha512_h0_init:
    dq 0x6a09e667f3bcc908, 0xbb67ae8584caa73b
    dq 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
    dq 0x510e527fade682d1, 0x9b05688c2b3e6c1f
    dq 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179

section .text

global sha512_init
global sha512_update
global sha512_final
global sha512_hash
global sha512_transform

; -----------------------------------------------------------------------------
; sha512_init
;
; Inputs:
;   RDI = Pointer to a sha512_ctx_t
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha512_init:
    push rdi
    push rsi
    push rcx

    lea rsi, [sha512_h0_init]
    mov rcx, 8
    rep movsq

    pop rcx
    pop rsi
    pop rdi

    mov qword [rdi + sha512_ctx_t.count], 0
    mov qword [rdi + sha512_ctx_t.count + 8], 0
    mov dword [rdi + sha512_ctx_t.buf_len], 0

    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; sha512_transform
;
; Compresses one 128-byte block.
;
; Inputs:
;   RDI = Pointer to a sha512_ctx_t
;   RSI = Pointer to a 128-byte block
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha512_transform:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 704                    ; 80 schedule qwords + spill

    mov [rsp + 640], rdi            ; Context
    mov [rsp + 648], rsi            ; Block

    ; ---- W[0..15]: big-endian load ----
    xor rcx, rcx
.tr_load:
    cmp rcx, 16
    jae .tr_expand
    mov rax, [rsi + rcx * 8]
    bswap rax
    mov [rsp + rcx * 8], rax
    inc rcx
    jmp .tr_load

    ; ---- W[16..79] = s1(W[i-2]) + W[i-7] + s0(W[i-15]) + W[i-16] ----
.tr_expand:
    cmp rcx, 80
    jae .tr_regs

    ; s0(x) = ror1 ^ ror8 ^ shr7
    mov rax, [rsp + rcx * 8 - 120]  ; W[i-15]
    mov rbx, rax
    ror rax, 1
    mov rdx, rbx
    ror rdx, 8
    xor rax, rdx
    mov rdx, rbx
    shr rdx, 7
    xor rax, rdx
    mov r8, rax                     ; s0

    ; s1(x) = ror19 ^ ror61 ^ shr6
    mov rax, [rsp + rcx * 8 - 16]   ; W[i-2]
    mov rbx, rax
    ror rax, 19
    mov rdx, rbx
    ror rdx, 61
    xor rax, rdx
    mov rdx, rbx
    shr rdx, 6
    xor rax, rdx                    ; s1

    add rax, r8
    add rax, [rsp + rcx * 8 - 128]  ; W[i-16]
    add rax, [rsp + rcx * 8 - 56]   ; W[i-7]
    mov [rsp + rcx * 8], rax

    inc rcx
    jmp .tr_expand

.tr_regs:
    mov rdi, [rsp + 640]
    mov rax, [rdi + 0]              ; a
    mov rbx, [rdi + 8]              ; b
    mov r12, [rdi + 16]             ; c
    mov r13, [rdi + 24]             ; d
    mov r14, [rdi + 32]             ; e
    mov r15, [rdi + 40]             ; f
    mov rbp, [rdi + 48]             ; g
    mov rdx, [rdi + 56]             ; h
    mov [rsp + 656], rdx            ; Spill h

    xor rcx, rcx

.tr_round:
    cmp rcx, 80
    jae .tr_store

    ; S1(e) = ror14 ^ ror18 ^ ror41
    mov rdx, r14
    ror rdx, 14
    mov rdi, r14
    ror rdi, 18
    xor rdx, rdi
    mov rdi, r14
    ror rdi, 41
    xor rdx, rdi
    mov [rsp + 664], rdx            ; S1

    ; Ch(e,f,g) = (e & f) ^ (~e & g)
    mov rdx, r14
    and rdx, r15
    mov rdi, r14
    not rdi
    and rdi, rbp
    xor rdx, rdi

    ; T1 = h + S1 + Ch + K[i] + W[i]
    add rdx, [rsp + 656]            ; h
    add rdx, [rsp + 664]            ; S1
    lea rdi, [sha512_k]
    add rdx, [rdi + rcx * 8]
    add rdx, [rsp + rcx * 8]
    mov [rsp + 664], rdx            ; T1

    ; S0(a) = ror28 ^ ror34 ^ ror39
    mov rdx, rax
    ror rdx, 28
    mov rdi, rax
    ror rdi, 34
    xor rdx, rdi
    mov rdi, rax
    ror rdi, 39
    xor rdx, rdi

    ; Maj(a,b,c)
    mov rdi, rax
    and rdi, rbx
    mov r8, rax
    and r8, r12
    xor rdi, r8
    mov r8, rbx
    and r8, r12
    xor rdi, r8
    add rdx, rdi                    ; T2

    ; Rotate
    mov r8, [rsp + 664]             ; T1
    mov [rsp + 656], rbp            ; h = g
    mov rbp, r15                    ; g = f
    mov r15, r14                    ; f = e
    mov r14, r13
    add r14, r8                     ; e = d + T1
    mov r13, r12                    ; d = c
    mov r12, rbx                    ; c = b
    mov rbx, rax                    ; b = a
    mov rax, r8
    add rax, rdx                    ; a = T1 + T2

    inc rcx
    jmp .tr_round

.tr_store:
    mov rdi, [rsp + 640]
    add [rdi + 0], rax
    add [rdi + 8], rbx
    add [rdi + 16], r12
    add [rdi + 24], r13
    add [rdi + 32], r14
    add [rdi + 40], r15
    add [rdi + 48], rbp
    mov rdx, [rsp + 656]
    add [rdi + 56], rdx

    mov rax, 1
    add rsp, 704
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha512_update
;
; Inputs:
;   RDI = Pointer to a sha512_ctx_t
;   RSI = Input pointer
;   RDX = Input length
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha512_update:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    test r13, r13
    jz .up_done

    ; Bit count is 128-bit; propagate carry into the high word.
    mov rax, r13
    shl rax, 3
    add [rbx + sha512_ctx_t.count], rax
    mov rax, r13
    shr rax, 61                     ; Bits that overflow 64
    adc [rbx + sha512_ctx_t.count + 8], rax

.up_loop:
    test r13, r13
    jz .up_done

    mov r14d, dword [rbx + sha512_ctx_t.buf_len]

    test r14d, r14d
    jnz .up_fill
    cmp r13, SHA512_BLOCK_SIZE
    jb .up_fill

    mov rdi, rbx
    mov rsi, r12
    call sha512_transform

    add r12, SHA512_BLOCK_SIZE
    sub r13, SHA512_BLOCK_SIZE
    jmp .up_loop

.up_fill:
    mov r15, SHA512_BLOCK_SIZE
    sub r15, r14
    cmp r15, r13
    jbe .up_copy
    mov r15, r13

.up_copy:
    lea rdi, [rbx + sha512_ctx_t.buf]
    add rdi, r14
    mov rsi, r12
    mov rcx, r15
    rep movsb

    add r14d, r15d
    mov dword [rbx + sha512_ctx_t.buf_len], r14d
    add r12, r15
    sub r13, r15

    cmp r14d, SHA512_BLOCK_SIZE
    jb .up_loop

    lea rsi, [rbx + sha512_ctx_t.buf]
    mov rdi, rbx
    call sha512_transform
    mov dword [rbx + sha512_ctx_t.buf_len], 0
    jmp .up_loop

.up_done:
    mov rax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha512_final
;
; Padding: 0x80, zeros, then a 128-BIT big-endian bit count.
;
; The reserve is 16 bytes, so the flush boundary is at 112 — not 120. Using 8
; like SHA-256 works until a message ends in the 112..119 window of its final
; block, and then produces silently wrong digests.
;
; Inputs:
;   RDI = Pointer to a sha512_ctx_t
;   RSI = Pointer to a 64-byte digest buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha512_final:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi

    mov r13, [rbx + sha512_ctx_t.count]         ; Low 64 bits of the bit count
    mov r15, [rbx + sha512_ctx_t.count + 8]     ; High 64 bits
    mov r14d, dword [rbx + sha512_ctx_t.buf_len]

    lea rdi, [rbx + sha512_ctx_t.buf]
    mov byte [rdi + r14], 0x80
    inc r14d

    cmp r14d, SHA512_BLOCK_SIZE - 16
    jbe .fi_pad

    ; No room for the 16-byte length: flush this block first.
    lea rdi, [rbx + sha512_ctx_t.buf]
    add rdi, r14
    mov ecx, SHA512_BLOCK_SIZE
    sub ecx, r14d
    xor al, al
    rep stosb

    lea rsi, [rbx + sha512_ctx_t.buf]
    mov rdi, rbx
    call sha512_transform

    xor r14d, r14d

.fi_pad:
    lea rdi, [rbx + sha512_ctx_t.buf]
    add rdi, r14
    mov ecx, SHA512_BLOCK_SIZE - 16
    sub ecx, r14d
    xor al, al
    rep stosb

    ; 128-bit big-endian length: high word first, then low.
    mov rax, r15
    bswap rax
    lea rdi, [rbx + sha512_ctx_t.buf]
    mov [rdi + SHA512_BLOCK_SIZE - 16], rax

    mov rax, r13
    bswap rax
    mov [rdi + SHA512_BLOCK_SIZE - 8], rax

    lea rsi, [rbx + sha512_ctx_t.buf]
    mov rdi, rbx
    call sha512_transform

    ; Emit state big-endian.
    xor rcx, rcx
.fi_out:
    cmp rcx, 8
    jae .fi_done
    mov rax, [rbx + rcx * 8]
    bswap rax
    mov [r12 + rcx * 8], rax
    inc rcx
    jmp .fi_out

.fi_done:
    mov rax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha512_hash
;
; One-shot digest.
;
; Inputs:
;   RDI = Input pointer
;   RSI = Input length
;   RDX = Pointer to a 64-byte digest buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha512_hash:
    push rbx
    push r12
    push r13
    sub rsp, sha512_ctx_t_size + 16

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    mov rdi, rsp
    call sha512_init

    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call sha512_update

    mov rdi, rsp
    mov rsi, r13
    call sha512_final

    mov rax, 1
    add rsp, sha512_ctx_t_size + 16
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UHASH_SHA512_SHA512_ASM
