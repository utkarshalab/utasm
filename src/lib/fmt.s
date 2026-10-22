;
; ============================================
; File     : src/lib/fmt.s
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
; FMT — BOUNDED STRING BUILDER
; ============================================================================
; Builds text into a caller-supplied buffer without ever overflowing it:
;
;     FmtBuf fb over char buf[256]
;     fmt_init   fb, buf, 256
;     fmt_str    fb, "offset "
;     fmt_hex    fb, 0x1f, 8          -> "offset 0000001f"
;     (then the caller writes FMTBUF_buf, FMTBUF_len bytes)
;
; Invariants:
;   - the buffer is NUL-terminated after every call (usable as a C string)
;   - at most cap-1 content bytes are written; excess input is cut off and
;     FMTBUF_truncated is set (sticky until fmt_reset)
;
; Calling convention (AMD64):
;   args  : rdi = FmtBuf, then rsi, rdx
;   return: rax = EXIT_OK, or EXIT_ERROR if this call truncated
;           rdx = current length
;   callee saved: rbx, r12-r15, rbp

%define FMT_NUM_SCRATCH 32                 ; >= 20 decimal / 16 hex digits

[SECTION .text]

; ---- fmt_init ---------------------------
;
; fmt_init
; Attaches a FmtBuf to a buffer and empties it.
; Input    : rdi = pointer to FmtBuf header (FMTBUF_SIZE bytes)
;             rsi = destination buffer
;             rdx = buffer size in bytes (>= 1, includes the NUL slot)
; Output   : rax = EXIT_OK or EXIT_ERROR (NULL pointer or zero size)
;              rdx = 0
; Clobbers : none
;
global fmt_init
fmt_init:
    test    rdi, rdi
    jz      .bad_args
    test    rsi, rsi
    jz      .bad_args
    test    rdx, rdx
    jz      .bad_args

    mov     byte  [rdi + FMTBUF_tag], TAG_FMTBUF
    mov     byte  [rdi + FMTBUF_truncated], 0
    mov     [rdi + FMTBUF_buf], rsi
    mov     [rdi + FMTBUF_cap], rdx
    mov     qword [rdi + FMTBUF_len], 0
    mov     byte  [rsi], 0

    xor     eax, eax
    xor     edx, edx
    ret

.bad_args:
    mov     eax, EXIT_ERROR
    xor     edx, edx
    ret

; ---- fmt_reset --------------------------
;
; fmt_reset
; Empties the builder and clears the truncated flag.
; Input    : rdi = pointer to FmtBuf
; Output   : none
; Clobbers : rax
;
global fmt_reset
fmt_reset:
    mov     qword [rdi + FMTBUF_len], 0
    mov     byte  [rdi + FMTBUF_truncated], 0
    mov     rax, [rdi + FMTBUF_buf]
    mov     byte [rax], 0
    ret

; ---- fmt_mem ----------------------------
;
; fmt_mem
; Appends n raw bytes. Core routine: every other appender ends up here.
; If only part fits, the part that fits is written.
; Input    : rdi = pointer to FmtBuf
;             rsi = source bytes
;             rdx = byte count
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated)
;              rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_mem
fmt_mem:
    mov     r10, rdi                       ; r10 = FmtBuf
    xor     eax, eax                       ; assume no truncation

    mov     r9,  [r10 + FMTBUF_len]
    mov     rcx, [r10 + FMTBUF_cap]
    dec     rcx                            ; reserve the NUL slot
    sub     rcx, r9                        ; rcx = room left
    cmp     rdx, rcx
    jbe     .fits
    mov     byte [r10 + FMTBUF_truncated], 1
    mov     eax, EXIT_ERROR
    mov     rdx, rcx                       ; clamp to what fits
.fits:
    mov     rdi, [r10 + FMTBUF_buf]
    add     rdi, r9                        ; rdi = write position
    mov     rcx, rdx
    add     r9, rdx                        ; r9 = new length
    test    rsi, rsi
    jz      .terminate                     ; NULL source: append nothing
    cld
    rep movsb

.terminate:
    mov     [r10 + FMTBUF_len], r9
    mov     r8, [r10 + FMTBUF_buf]
    mov     byte [r8 + r9], 0
    mov     rdx, r9
    ret

; ---- fmt_str ----------------------------
;
; fmt_str
; Appends a null-terminated string (NULL appends nothing).
; Input    : rdi = pointer to FmtBuf
;             rsi = null-terminated string
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated), rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_str
fmt_str:
    xor     edx, edx
    test    rsi, rsi
    jz      fmt_mem                        ; zero-length append
.len:
    cmp     byte [rsi + rdx], 0
    je      fmt_mem                        ; tail call with rdx = strlen
    inc     rdx
    jmp     .len

; ---- fmt_char ---------------------------
;
; fmt_char
; Appends a single byte.
; Input    : rdi = pointer to FmtBuf
;             rsi = character (low 8 bits)
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated), rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_char
fmt_char:
    push    rsi                            ; byte lives on the stack
    mov     rsi, rsp
    mov     edx, 1
    call    fmt_mem
    add     rsp, 8
    ret

; ---- fmt_pad ----------------------------
;
; fmt_pad
; Appends a character repeated count times (indentation, column padding).
; Input    : rdi = pointer to FmtBuf
;             rsi = character (low 8 bits)
;             rdx = repeat count
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated), rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_pad
fmt_pad:
    mov     r10, rdi
    xor     eax, eax

    mov     r9,  [r10 + FMTBUF_len]
    mov     rcx, [r10 + FMTBUF_cap]
    dec     rcx
    sub     rcx, r9                        ; room left
    cmp     rdx, rcx
    jbe     .fits
    mov     byte [r10 + FMTBUF_truncated], 1
    mov     eax, EXIT_ERROR
    mov     rdx, rcx
.fits:
    mov     rdi, [r10 + FMTBUF_buf]
    add     rdi, r9
    add     r9, rdx
    mov     rcx, rdx
    mov     r8, rax                        ; keep status across stosb
    mov     eax, esi
    cld
    rep stosb
    mov     rax, r8

    mov     [r10 + FMTBUF_len], r9
    mov     r8, [r10 + FMTBUF_buf]
    mov     byte [r8 + r9], 0
    mov     rdx, r9
    ret

; ---- fmt_udec ---------------------------
;
; fmt_udec
; Appends an unsigned 64-bit integer in decimal.
; Input    : rdi = pointer to FmtBuf
;             rsi = value
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated), rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_udec
fmt_udec:
    sub     rsp, FMT_NUM_SCRATCH
    mov     r10, rdi                       ; r10 = FmtBuf
    lea     r8, [rsp + FMT_NUM_SCRATCH]    ; r8 = end of scratch (write backwards)
    mov     rax, rsi
    mov     ecx, 10

.digit:
    xor     edx, edx
    div     rcx                            ; rax = q, rdx = digit
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digit

    mov     rdi, r10
    mov     rsi, r8
    lea     rdx, [rsp + FMT_NUM_SCRATCH]
    sub     rdx, r8                        ; digit count
    call    fmt_mem
    add     rsp, FMT_NUM_SCRATCH
    ret

; ---- fmt_hex ----------------------------
;
; fmt_hex
; Appends an unsigned value in lowercase hexadecimal, no "0x" prefix,
; zero-padded to at least min_digits (clamped to 1..16).
;   fmt_hex(0x1f, 0) -> "1f",  fmt_hex(0x1f, 4) -> "001f"
; Input    : rdi = pointer to FmtBuf
;             rsi = value
;             rdx = minimum digit count
; Output   : rax = EXIT_OK or EXIT_ERROR (truncated), rdx = current length
; Clobbers : rcx, rsi, rdi, r8, r9, r10
;
global fmt_hex
fmt_hex:
    sub     rsp, FMT_NUM_SCRATCH
    mov     r10, rdi                       ; r10 = FmtBuf
    lea     r8, [rsp + FMT_NUM_SCRATCH]    ; write backwards from the end
    lea     r9, [hex_digits]

    ; clamp min_digits to 1..16
    test    rdx, rdx
    jnz     .min_nonzero
    mov     edx, 1
.min_nonzero:
    cmp     rdx, 16
    jbe     .min_ok
    mov     edx, 16
.min_ok:

.digit:
    mov     rax, rsi
    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    dec     r8
    mov     [r8], al
    shr     rsi, 4
    dec     rdx                            ; one more required digit produced
    test    rsi, rsi
    jnz     .digit                         ; value bits remain
    cmp     rdx, 0
    jg      .digit                         ; still below min_digits: emit '0'

    mov     rdi, r10
    mov     rsi, r8
    lea     rdx, [rsp + FMT_NUM_SCRATCH]
    sub     rdx, r8
    call    fmt_mem
    add     rsp, FMT_NUM_SCRATCH
    ret

[SECTION .rodata]
hex_digits: db "0123456789abcdef"
