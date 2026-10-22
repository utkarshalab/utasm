;
; ============================================
; File     : src/lib/hash.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

DEFAULT REL

; ============================================================================
; HASH FUNCTIONS
; ============================================================================
; Non-cryptographic hashes for hash tables, dedup, and checksums.
;
;   hash_fnv1a_str  - FNV-1a 64 over a null-terminated string
;   hash_crc32      - CRC-32 (IEEE 802.3, reflected, poly 0xEDB88320)
;
; Both are pure and cannot fail: the result is returned in rax.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx
;   return: rax = hash
;   callee saved: rbx, r12-r15, rbp

%define FNV64_OFFSET    0xcbf29ce484222325
%define FNV64_PRIME     0x100000001b3
%define GOLDEN_64       0x9e3779b97f4a7c15
%define SPLITMIX_M1     0xbf58476d1ce4e5b9
%define SPLITMIX_M2     0x94d049bb133111eb
%define CRC32_POLY      0xEDB88320

[SECTION .text]

; ---- hash_fnv1a_str ---------------------
;
; hash_fnv1a_str
; FNV-1a 64-bit hash of a null-terminated string.
; A NULL pointer hashes like the empty string.
; Input    : rdi = pointer to null-terminated string
; Output   : rax = 64-bit hash
; Clobbers : rcx, rdx, r11
;
global hash_fnv1a_str
hash_fnv1a_str:
    mov     rax, FNV64_OFFSET
    test    rdi, rdi
    jz      .done
    mov     r11, FNV64_PRIME
    mov     rcx, rdi

.loop:
    movzx   edx, byte [rcx]
    test    dl, dl
    jz      .done
    xor     rax, rdx               ; FNV-1a: XOR first...
    imul    rax, r11               ; ...then multiply
    inc     rcx
    jmp     .loop

.done:
    ret

; ---- hash_crc32 -------------------------
;
; hash_crc32
; CRC-32 (IEEE 802.3 / zlib / PNG variant), bitwise, no lookup table.
; Pass rdx = 0 for a fresh checksum; pass a previous result to continue
; over a second chunk (pre/post inversion is handled internally).
;   hash_crc32("123456789", 9, 0) == 0xCBF43926
; Input    : rdi = pointer to data
;             rsi = length in bytes
;             rdx = previous CRC (0 to start)
; Output   : rax = CRC-32 in the low 32 bits (upper bits zero)
; Clobbers : rcx, rdx, r8, r9
;
global hash_crc32
hash_crc32:
    mov     eax, edx
    not     eax                    ; pre-invert
    test    rdi, rdi
    jz      .done
    xor     ecx, ecx               ; rcx = index
    mov     r9d, CRC32_POLY

.byte_loop:
    cmp     rcx, rsi
    jae     .done
    movzx   edx, byte [rdi + rcx]
    xor     eax, edx
    mov     r8d, 8                 ; 8 bits per byte

.bit_loop:
    shr     eax, 1                 ; CF = bit shifted out
    jnc     .no_xor
    xor     eax, r9d
.no_xor:
    dec     r8d
    jnz     .bit_loop

    inc     rcx
    jmp     .byte_loop

.done:
    not     eax                    ; post-invert (zero-extends into rax)
    ret
