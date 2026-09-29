;
; ============================================
; File     : lib/math.s
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
; INTEGER MATH HELPERS
; ============================================================================
; Alignment, power-of-two, bit-width range checks, and overflow-checked
; arithmetic. These are the questions the encoder, linker and expression
; evaluator keep asking: "does this displacement fit in imm8?",
; "align this section offset to 16", "did this constant expression overflow?".
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result      (functions that can fail)
;           rax = result                         (pure functions)
;   callee saved: rbx, r12-r15, rbp

[SECTION .text]

; ============================================================================
; Powers of two
; ============================================================================

; ---- math_is_pow2 -----------------------
;
; math_is_pow2
; Tests whether a value is a (non-zero) power of two.
; Input    : rdi = value
; Output   : rax = 1 if power of two, else 0
; Clobbers : rcx
;
global math_is_pow2
math_is_pow2:
    xor     eax, eax
    test    rdi, rdi
    jz      .done                  ; 0 is not a power of two
    lea     rcx, [rdi - 1]
    test    rcx, rdi               ; x & (x-1) == 0  <=>  single bit set
    setz    al
.done:
    ret

; ---- math_next_pow2 ---------------------
;
; math_next_pow2
; Smallest power of two >= value. 0 and 1 both give 1.
; Returns 0 if the result is not representable (value > 2^63).
; Input    : rdi = value
; Output   : rax = power of two, or 0 on overflow
; Clobbers : rcx
;
global math_next_pow2
math_next_pow2:
    mov     eax, 1
    cmp     rdi, 1
    jbe     .done
    lea     rcx, [rdi - 1]
    bsr     rcx, rcx               ; rcx = index of highest set bit of (x-1)
    cmp     ecx, 63
    jae     .overflow              ; would need bit 64
    inc     ecx
    shl     rax, cl                ; 1 << (msb(x-1) + 1)
.done:
    ret
.overflow:
    xor     eax, eax
    ret

; ---- math_log2 --------------------------
;
; math_log2
; Floor of log2(value). log2(0) is undefined and returns -1.
; Input    : rdi = value (unsigned)
; Output   : rax = floor(log2(value)), or -1 for 0
; Clobbers : none
;
global math_log2
math_log2:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    bsr     rax, rdi
.done:
    ret

; ============================================================================
; Alignment
; ============================================================================

; ---- math_align_up ----------------------
;
; math_align_up
; Rounds a value up to a multiple of a power-of-two alignment.
; Input    : rdi = value (unsigned)
;             rsi = alignment (power of two, >= 1)
; Output   : rax = EXIT_OK or EXIT_ALIGN_ERROR
;              (bad alignment, or result overflows 64 bits)
;              rdx = aligned value
; Clobbers : rcx
;
global math_align_up
math_align_up:
    test    rsi, rsi
    jz      .bad
    lea     rcx, [rsi - 1]
    test    rcx, rsi
    jnz     .bad                   ; not a power of two

    mov     rdx, rdi
    add     rdx, rcx               ; value + (align - 1)
    jc      .bad                   ; overflow past 2^64
    not     rcx
    and     rdx, rcx               ; clear low bits
    xor     eax, eax               ; EXIT_OK
    ret

.bad:
    mov     eax, EXIT_ALIGN_ERROR
    xor     edx, edx
    ret

; ---- math_align_down --------------------
;
; math_align_down
; Rounds a value down to a multiple of a power-of-two alignment.
; Input    : rdi = value (unsigned)
;             rsi = alignment (power of two, >= 1)
; Output   : rax = EXIT_OK or EXIT_ALIGN_ERROR
;              rdx = aligned value
; Clobbers : rcx
;
global math_align_down
math_align_down:
    test    rsi, rsi
    jz      .bad
    lea     rcx, [rsi - 1]
    test    rcx, rsi
    jnz     .bad

    not     rcx
    mov     rdx, rdi
    and     rdx, rcx
    xor     eax, eax
    ret

.bad:
    mov     eax, EXIT_ALIGN_ERROR
    xor     edx, edx
    ret

; ---- math_div_ceil ----------------------
;
; math_div_ceil
; Unsigned ceiling division: ceil(a / b).
; Input    : rdi = dividend
;             rsi = divisor
; Output   : rax = EXIT_OK or EXIT_ERROR (division by zero)
;              rdx = quotient rounded up
; Clobbers : rcx
;
global math_div_ceil
math_div_ceil:
    test    rsi, rsi
    jz      .div_zero

    mov     rax, rdi
    xor     edx, edx
    div     rsi                    ; rax = a / b, rdx = a % b
    mov     rcx, rax
    test    rdx, rdx
    jz      .exact
    inc     rcx                    ; remainder -> round up (cannot overflow:
                                   ; a/b < 2^64-1 whenever a%b != 0 and b >= 2)
.exact:
    mov     rdx, rcx
    xor     eax, eax
    ret

.div_zero:
    mov     eax, EXIT_ERROR
    xor     edx, edx
    ret

; ============================================================================
; Bit-width range checks
; ============================================================================

; ---- math_fits_signed -------------------
;
; math_fits_signed
; Does a signed 64-bit value fit in an N-bit two's-complement field?
;   math_fits_signed(-128, 8) = 1,  math_fits_signed(128, 8) = 0
; Input    : rdi = value (signed)
;             rsi = width in bits (0..64; >= 64 always fits, 0 never)
; Output   : rax = 1 if it fits, else 0
; Clobbers : rcx, rdx
;
global math_fits_signed
math_fits_signed:
    xor     eax, eax
    test    rsi, rsi
    jz      .done
    mov     eax, 1
    cmp     rsi, 64
    jae     .done

    mov     ecx, 64
    sub     ecx, esi               ; cl = 64 - bits
    mov     rdx, rdi
    shl     rdx, cl
    sar     rdx, cl                ; sign-extend from bit (bits-1)
    xor     eax, eax
    cmp     rdx, rdi
    sete    al
.done:
    ret

; ---- math_fits_unsigned -----------------
;
; math_fits_unsigned
; Does an unsigned 64-bit value fit in an N-bit unsigned field?
; Input    : rdi = value (unsigned)
;             rsi = width in bits (0..64; >= 64 always fits)
; Output   : rax = 1 if it fits, else 0
; Clobbers : rcx, rdx
;
global math_fits_unsigned
math_fits_unsigned:
    mov     eax, 1
    cmp     rsi, 64
    jae     .done

    mov     ecx, esi
    mov     rdx, rdi
    shr     rdx, cl                ; any bits at or above position N?
    xor     eax, eax
    test    rdx, rdx
    setz    al
.done:
    ret

; ---- math_sign_extend -------------------
;
; math_sign_extend
; Sign-extends the low N bits of a value to 64 bits.
;   math_sign_extend(0xFF, 8) = -1,  math_sign_extend(0x7F, 8) = 127
; Input    : rdi = value
;             rsi = width in bits (1..64; >= 64 or 0 returns value unchanged)
; Output   : rax = sign-extended value
; Clobbers : rcx
;
global math_sign_extend
math_sign_extend:
    mov     rax, rdi
    test    rsi, rsi
    jz      .done
    cmp     rsi, 64
    jae     .done

    mov     ecx, 64
    sub     ecx, esi
    shl     rax, cl
    sar     rax, cl
.done:
    ret

; ============================================================================
; Overflow-checked signed arithmetic
; ============================================================================
; All return rax = EXIT_OK or EXIT_ERROR (signed overflow), rdx = result.
; On overflow rdx holds the wrapped result so callers may still inspect it.

; ---- math_add_checked -------------------
;
; math_add_checked
; Input    : rdi = a, rsi = b   (signed)
; Output   : rax = EXIT_OK or EXIT_ERROR, rdx = a + b
; Clobbers : none
;
global math_add_checked
math_add_checked:
    mov     rdx, rdi
    xor     eax, eax
    add     rdx, rsi
    jno     .ok
    mov     eax, EXIT_ERROR
.ok:
    ret

; ---- math_sub_checked -------------------
;
; math_sub_checked
; Input    : rdi = a, rsi = b   (signed)
; Output   : rax = EXIT_OK or EXIT_ERROR, rdx = a - b
; Clobbers : none
;
global math_sub_checked
math_sub_checked:
    mov     rdx, rdi
    xor     eax, eax
    sub     rdx, rsi
    jno     .ok
    mov     eax, EXIT_ERROR
.ok:
    ret

; ---- math_mul_checked -------------------
;
; math_mul_checked
; Input    : rdi = a, rsi = b   (signed)
; Output   : rax = EXIT_OK or EXIT_ERROR, rdx = a * b (low 64 bits)
; Clobbers : none
;
global math_mul_checked
math_mul_checked:
    mov     rdx, rdi
    xor     eax, eax               ; must precede imul (xor clears OF)
    imul    rdx, rsi
    jno     .ok
    mov     eax, EXIT_ERROR
.ok:
    ret
