;
; ============================================
; File     : lib/sha256.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;
; SHA-256 (FIPS 180-4), from Tattva OS crypto/uhash/sha256: the scalar
; implementation verified there against the FIPS vectors. utasm uses it for
; the component digests of UBF boot images (backend/output/ubf).
;
;   sha256_init / sha256_update / sha256_final  streaming
;   sha256_hash                                 one shot
;   sha256_transform                            one 64-byte block
;
; SHA-256 is big-endian on the wire: message words and the trailing length
; are byte-swapped on load and store.
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

%define SHA256_BLOCK_SIZE   64          ; 64-byte message block
%define SHA256_DIGEST_SIZE  32          ; 32-byte (256-bit) digest

; SHA-256 context (112 bytes)
struc SHA256CTX
    field state,   32       ; 8 x 32-bit state words (H0..H7)
    field count,   8        ; total bits processed
    field buf,     64       ; the partial block
    field buf_len, 4        ; bytes in buf (0..63)
    field flags,   4
endstruc

[SECTION .rodata]
align 64

; Round constants: first 32 bits of the fractional parts of the cube roots of
; the first 64 primes.
sha256_k:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

; Initial state: first 32 bits of the fractional parts of the square roots of
; the first 8 primes.
sha256_h0:
    dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    dd 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

[SECTION .text]

global sha256_init
global sha256_update
global sha256_final
global sha256_hash
global sha256_transform

; -----------------------------------------------------------------------------
; sha256_init
;
; Inputs:
;   RDI = Pointer to a SHA256CTX
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha256_init:
    push rdi
    push rsi
    push rcx

    ; Load the eight initial state words.
    lea rsi, [rel sha256_h0]
    mov rcx, 8
.si_state:
    mov eax, dword [rsi]
    mov dword [rdi], eax
    add rsi, 4
    add rdi, 4
    dec rcx
    jnz .si_state

    pop rcx
    pop rsi
    pop rdi

    mov qword [rdi + SHA256CTX_count], 0
    mov dword [rdi + SHA256CTX_buf_len], 0
    mov dword [rdi + SHA256CTX_flags], 0

    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; sha256_transform
;
; Compresses one 64-byte block into the context state.
;
; Inputs:
;   RDI = Pointer to a SHA256CTX
;   RSI = Pointer to a 64-byte block
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha256_transform:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 288                    ; 64 schedule dwords + spill space

    mov [rsp + 256], rdi            ; Context
    mov [rsp + 264], rsi            ; Block

    ; ---- Message schedule W[0..15]: big-endian load ----
    xor rcx, rcx
.tr_load:
    cmp rcx, 16
    jae .tr_expand
    mov eax, dword [rsi + rcx * 4]
    bswap eax                       ; SHA-256 words are big-endian on the wire
    mov dword [rsp + rcx * 4], eax
    inc rcx
    jmp .tr_load

    ; ---- W[16..63] = s1(W[i-2]) + W[i-7] + s0(W[i-15]) + W[i-16] ----
.tr_expand:
    cmp rcx, 64
    jae .tr_regs

    ; s0(W[i-15]) = ror7 ^ ror18 ^ shr3
    mov eax, dword [rsp + rcx * 4 - 60]     ; W[i-15]
    mov ebx, eax
    ror eax, 7
    mov edx, ebx
    ror edx, 18
    xor eax, edx
    mov edx, ebx
    shr edx, 3
    xor eax, edx
    mov r8d, eax                            ; s0

    ; s1(W[i-2]) = ror17 ^ ror19 ^ shr10
    mov eax, dword [rsp + rcx * 4 - 8]      ; W[i-2]
    mov ebx, eax
    ror eax, 17
    mov edx, ebx
    ror edx, 19
    xor eax, edx
    mov edx, ebx
    shr edx, 10
    xor eax, edx                            ; s1

    add eax, r8d
    add eax, dword [rsp + rcx * 4 - 64]     ; W[i-16]
    add eax, dword [rsp + rcx * 4 - 28]     ; W[i-7]
    mov dword [rsp + rcx * 4], eax

    inc rcx
    jmp .tr_expand

    ; ---- Working variables a..h from the current state ----
.tr_regs:
    mov rdi, [rsp + 256]
    mov eax, dword [rdi + 0]        ; a
    mov ebx, dword [rdi + 4]        ; b
    mov r12d, dword [rdi + 8]       ; c
    mov r13d, dword [rdi + 12]      ; d
    mov r14d, dword [rdi + 16]      ; e
    mov r15d, dword [rdi + 20]      ; f
    mov ebp, dword [rdi + 24]       ; g
    mov edx, dword [rdi + 28]       ; h
    mov [rsp + 272], rdx            ; Spill h; registers are exhausted

    xor rcx, rcx

.tr_round:
    cmp rcx, 64
    jae .tr_store

    ; T1 = h + S1(e) + Ch(e,f,g) + K[i] + W[i]
    mov edx, r14d
    ror edx, 6
    mov edi, r14d
    ror edi, 11
    xor edx, edi
    mov edi, r14d
    ror edi, 25
    xor edx, edi                    ; S1(e)
    mov [rsp + 280], rdx

    ; Ch(e,f,g) = (e & f) ^ (~e & g)
    mov edx, r14d
    and edx, r15d
    mov edi, r14d
    not edi
    and edi, ebp
    xor edx, edi                    ; Ch

    mov edi, [rsp + 272]            ; h
    add edx, edi
    add edx, [rsp + 280]            ; + S1
    lea rdi, [rel sha256_k]
    add edx, dword [rdi + rcx * 4]  ; + K[i]
    add edx, dword [rsp + rcx * 4]  ; + W[i]
    mov [rsp + 280], rdx            ; T1

    ; T2 = S0(a) + Maj(a,b,c)
    mov edx, eax
    ror edx, 2
    mov edi, eax
    ror edi, 13
    xor edx, edi
    mov edi, eax
    ror edi, 22
    xor edx, edi                    ; S0(a)

    mov edi, eax
    and edi, ebx
    mov r8d, eax
    and r8d, r12d
    xor edi, r8d
    mov r8d, ebx
    and r8d, r12d
    xor edi, r8d                    ; Maj
    add edx, edi                    ; T2

    ; Rotate the working variables.
    mov r8d, [rsp + 280]            ; T1
    mov [rsp + 272], rbp            ; h = g
    mov ebp, r15d                   ; g = f
    mov r15d, r14d                  ; f = e
    mov r14d, r13d
    add r14d, r8d                   ; e = d + T1
    mov r13d, r12d                  ; d = c
    mov r12d, ebx                   ; c = b
    mov ebx, eax                    ; b = a
    mov eax, r8d
    add eax, edx                    ; a = T1 + T2

    inc rcx
    jmp .tr_round

.tr_store:
    ; Feed-forward: state += working variables.
    mov rdi, [rsp + 256]
    add dword [rdi + 0], eax
    add dword [rdi + 4], ebx
    add dword [rdi + 8], r12d
    add dword [rdi + 12], r13d
    add dword [rdi + 16], r14d
    add dword [rdi + 20], r15d
    add dword [rdi + 24], ebp
    mov rdx, [rsp + 272]
    add dword [rdi + 28], edx

    mov rax, 1
    add rsp, 288
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha256_update
;
; Absorbs an arbitrary byte run, buffering any partial trailing block.
;
; Inputs:
;   RDI = Pointer to a SHA256CTX
;   RSI = Input pointer
;   RDX = Input length
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha256_update:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Context
    mov r12, rsi                    ; Input
    mov r13, rdx                    ; Remaining

    test r13, r13
    jz .up_done

    ; Count is in BITS, not bytes.
    mov rax, r13
    shl rax, 3
    add [rbx + SHA256CTX_count], rax

.up_loop:
    test r13, r13
    jz .up_done

    mov r14d, dword [rbx + SHA256CTX_buf_len]

    ; Fast path: a full block with nothing buffered goes straight in.
    test r14d, r14d
    jnz .up_fill
    cmp r13, SHA256_BLOCK_SIZE
    jb .up_fill

    mov rdi, rbx
    mov rsi, r12
    call sha256_transform

    add r12, SHA256_BLOCK_SIZE
    sub r13, SHA256_BLOCK_SIZE
    jmp .up_loop

.up_fill:
    ; Copy into the buffer until it is full or the input runs out.
    mov r15, SHA256_BLOCK_SIZE
    sub r15, r14                    ; Space remaining
    cmp r15, r13
    jbe .up_copy
    mov r15, r13                    ; Input is shorter

.up_copy:
    lea rdi, [rbx + SHA256CTX_buf]
    add rdi, r14
    mov rsi, r12
    mov rcx, r15
    rep movsb

    add r14d, r15d
    mov dword [rbx + SHA256CTX_buf_len], r14d
    add r12, r15
    sub r13, r15

    cmp r14d, SHA256_BLOCK_SIZE
    jb .up_loop                     ; Still partial: wait for more input

    lea rsi, [rbx + SHA256CTX_buf]
    mov rdi, rbx
    call sha256_transform
    mov dword [rbx + SHA256CTX_buf_len], 0
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
; sha256_final
;
; Applies padding and emits the digest.
;
; Padding is 0x80, then zeros, then the 64-bit big-endian bit count. When fewer
; than 9 bytes remain in the block there is no room for the length, so the
; block is flushed and the length goes into a second one. Getting that boundary
; wrong is the other classic SHA bug.
;
; Inputs:
;   RDI = Pointer to a SHA256CTX
;   RSI = Pointer to a 32-byte digest buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha256_final:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Context
    mov r12, rsi                    ; Digest out

    mov r13, [rbx + SHA256CTX_count]      ; Bit count, before padding
    mov r14d, dword [rbx + SHA256CTX_buf_len]

    ; Append the mandatory 0x80.
    lea rdi, [rbx + SHA256CTX_buf]
    mov byte [rdi + r14], 0x80
    inc r14d

    ; If the length will not fit, zero-fill and flush this block first.
    cmp r14d, SHA256_BLOCK_SIZE - 8
    jbe .fi_pad

    ; Zero to the end of the block.
    lea rdi, [rbx + SHA256CTX_buf]
    add rdi, r14
    mov ecx, SHA256_BLOCK_SIZE
    sub ecx, r14d
    xor al, al
    rep stosb

    lea rsi, [rbx + SHA256CTX_buf]
    mov rdi, rbx
    call sha256_transform

    xor r14d, r14d                  ; Length goes in a fresh block

.fi_pad:
    ; Zero from here to the length field.
    lea rdi, [rbx + SHA256CTX_buf]
    add rdi, r14
    mov ecx, SHA256_BLOCK_SIZE - 8
    sub ecx, r14d
    xor al, al
    rep stosb

    ; 64-bit big-endian bit count in the final eight bytes.
    mov rax, r13
    bswap rax
    lea rdi, [rbx + SHA256CTX_buf]
    mov [rdi + SHA256_BLOCK_SIZE - 8], rax

    lea rsi, [rbx + SHA256CTX_buf]
    mov rdi, rbx
    call sha256_transform

    ; Emit the state big-endian.
    xor rcx, rcx
.fi_out:
    cmp rcx, 8
    jae .fi_done
    mov eax, dword [rbx + rcx * 4]
    bswap eax
    mov dword [r12 + rcx * 4], eax
    inc rcx
    jmp .fi_out

.fi_done:
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha256_hash
;
; One-shot digest.
;
; Inputs:
;   RDI = Input pointer
;   RSI = Input length
;   RDX = Pointer to a 32-byte digest buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
sha256_hash:
    push rbx
    push r12
    push r13
    sub rsp, SHA256CTX_SIZE + 16

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    mov rdi, rsp
    call sha256_init

    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call sha256_update

    mov rdi, rsp
    mov rsi, r13
    call sha256_final

    mov rax, 1
    add rsp, SHA256CTX_SIZE + 16
    pop r13
    pop r12
    pop rbx
    ret
