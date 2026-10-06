;
; ============================================
; File     : lib/float.s
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
; FLOATING-POINT CONSTANTS
; ============================================================================
; float_encode turns the text of a floating-point constant ("1.5", "1.0e3",
; "0x1.8p3") into IEEE 754 bits: binary16 (dw), binary32 (dd), binary64 (dq),
; binary128 (do) or the x87 80-bit extended format (dt). The result is correctly rounded
; (round half to even), exactly as NASM produces it.
;
; Method: the constant is exactly M * 10^E (or H * 2^K for a hex float), M an
; integer of up to 60 significant digits (further digits only decide the
; rounding). For E >= 0 the integer M * 10^E is formed directly. For E < 0
; the value is the quotient (M * 2^s) / 10^-E, with s chosen so that the
; quotient has P+1 or P+2 bits; the remainder only records whether anything
; was left over. Either way the value becomes T * 2^k with T at most 66 bits
; plus a "sticky" flag for any bits below T, which is enough to round to P
; bits, normal or subnormal.
;
; The big integers live in fixed buffers of 64-bit limbs, little-endian.
; Exponents are clamped long before a buffer could fill: anything beyond
; 1e5000 is infinite and anything below 1e-5100 rounds to zero in every
; format.
;

%define FBN_LIMBS       320         ; 20480 bits per big integer
%define FLT_MAX_DIGITS  60          ; significant decimal digits kept
%define FLT_MAX_HEX     30          ; significant hex digits kept

[SECTION .text]

;
; float_encode
; Input    : rdi = text of the constant (NUL-terminated)
;            esi = 1 for a negative constant
;            edx = format: FLT_HALF 1, FLT_SINGLE 2, FLT_DOUBLE 3, FLT_EXT 4,
;                  FLT_QUAD 5
; Output   : rax = EXIT_OK or EXIT_INVALID_OPERAND
;            rdx = the bits (for the 80-bit format: the 64-bit significand;
;                  binary128: the low 64 bits)
;            rcx = the 80-bit format's sign and exponent word, binary128's
;                  high 64 bits, else 0
;
global float_encode
float_encode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     [rel f_sign], sil

    ; the format's precision, exponent bias and width
    dec     edx
    cmp     edx, 4
    ja      .bad
    lea     rax, [rel f_formats]
    imul    ecx, edx, 12
    mov     r8d, [rax + rcx]
    mov     [rel f_prec], r8
    mov     r8d, [rax + rcx + 4]
    mov     [rel f_bias], r8
    mov     r8d, [rax + rcx + 8]
    mov     [rel f_width], r8
    xor     eax, eax
    cmp     edx, 3
    sete    al
    mov     [rel f_ext], al

    ; clear the big integers and the state
    lea     rdi, [rel f_a]
    mov     ecx, (FBN_LIMBS + 4) * 3
    xor     eax, eax
    rep stosq
    mov     qword [rel f_alen], 0
    mov     qword [rel f_dlen], 0
    mov     qword [rel f_rlen], 0
    mov     byte [rel f_sticky], 0

    xor     r13d, r13d                     ; exponent adjustment
    xor     r14d, r14d                     ; significant digits taken
    xor     r15d, r15d                     ; 1 once past the point
    mov     rbx, r12
    cmp     byte [rbx], '0'
    jne     .dec_loop
    movzx   eax, byte [rbx + 1]
    or      eax, 0x20
    cmp     eax, 'x'
    je      .hex

    ; ---- decimal: digits [. digits] [e [+-] digits] ----
.dec_loop:
    movzx   eax, byte [rbx]
    cmp     eax, '_'
    je      .dec_next
    cmp     eax, '.'
    jne     .dec_digit
    test    r15d, r15d
    jnz     .bad
    mov     r15d, 1
    jmp     .dec_next
.dec_digit:
    sub     eax, '0'
    cmp     eax, 9
    ja      .dec_end
    test    r14d, r14d
    jnz     .dec_take
    test    eax, eax
    jnz     .dec_take
    ; a leading zero: only a fraction's shifts the value
    test    r15d, r15d
    jz      .dec_next
    dec     r13
    jmp     .dec_next
.dec_take:
    cmp     r14d, FLT_MAX_DIGITS
    jae     .dec_drop
    inc     r14d
    lea     rdi, [rel f_a]
    lea     rsi, [rel f_alen]
    mov     edx, 10
    mov     ecx, eax
    call    bn_mul_add
    test    r15d, r15d
    jz      .dec_next
    dec     r13                            ; a fraction digit
    jmp     .dec_next
.dec_drop:
    test    eax, eax
    jz      .dec_drop_zero
    mov     byte [rel f_sticky], 1
.dec_drop_zero:
    test    r15d, r15d
    jnz     .dec_next
    inc     r13                            ; an integer digit left out: x10
.dec_next:
    inc     rbx
    jmp     .dec_loop
.dec_end:
    movzx   eax, byte [rbx]
    or      eax, 0x20
    cmp     eax, 'e'
    jne     .dec_no_exp
    inc     rbx
    call    f_read_exp
    test    rax, rax
    jnz     .bad
    add     r13, rdx
.dec_no_exp:
    cmp     byte [rbx], 0
    jne     .bad
    cmp     qword [rel f_alen], 0
    je      .zero
    cmp     r13, 5000
    jg      .inf
    cmp     r13, -5100
    jl      .zero
    test    r13, r13
    js      .divide

    ; E >= 0: the integer M * 10^E
.times_ten:
    test    r13, r13
    jz      .reduce
    lea     rdi, [rel f_a]
    lea     rsi, [rel f_alen]
    mov     edx, 10
    xor     ecx, ecx
    call    bn_mul_add
    dec     r13
    jmp     .times_ten

    ; ---- hex: 0x digits [. digits] [p [+-] digits] ----
.hex:
    add     rbx, 2
.hex_loop:
    movzx   eax, byte [rbx]
    cmp     eax, '_'
    je      .hex_next
    cmp     eax, '.'
    jne     .hex_digit
    test    r15d, r15d
    jnz     .bad
    mov     r15d, 1
    jmp     .hex_next
.hex_digit:
    mov     ecx, eax
    sub     ecx, '0'
    cmp     ecx, 9
    jbe     .hex_value
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 5
    ja      .hex_end
    lea     ecx, [rax + 10]
.hex_value:
    test    r14d, r14d
    jnz     .hex_take
    test    ecx, ecx
    jnz     .hex_take
    test    r15d, r15d
    jz      .hex_next
    sub     r13, 4
    jmp     .hex_next
.hex_take:
    cmp     r14d, FLT_MAX_HEX
    jae     .hex_drop
    inc     r14d
    lea     rdi, [rel f_a]
    lea     rsi, [rel f_alen]
    mov     edx, 16
    call    bn_mul_add
    test    r15d, r15d
    jz      .hex_next
    sub     r13, 4
    jmp     .hex_next
.hex_drop:
    test    ecx, ecx
    jz      .hex_drop_zero
    mov     byte [rel f_sticky], 1
.hex_drop_zero:
    test    r15d, r15d
    jnz     .hex_next
    add     r13, 4
.hex_next:
    inc     rbx
    jmp     .hex_loop
.hex_end:
    movzx   eax, byte [rbx]
    or      eax, 0x20
    cmp     eax, 'p'
    jne     .hex_no_exp
    inc     rbx
    call    f_read_exp
    test    rax, rax
    jnz     .bad
    add     r13, rdx
.hex_no_exp:
    cmp     byte [rbx], 0
    jne     .bad
    cmp     qword [rel f_alen], 0
    je      .zero
    cmp     r13, 20000
    jg      .inf
    cmp     r13, -20000
    jl      .zero
    jmp     .reduce

    ; ---- E < 0: q = (M * 2^s) / 10^-E, value = q * 2^-s ----
.divide:
    neg     r13                            ; n
    lea     rax, [rel f_d]
    mov     qword [rax], 1
    mov     qword [rel f_dlen], 1
.pow_ten:
    lea     rdi, [rel f_d]
    lea     rsi, [rel f_dlen]
    mov     edx, 10
    xor     ecx, ecx
    call    bn_mul_add
    dec     r13
    jnz     .pow_ten
    ; s = bitlen(D) - bitlen(M) + P + 1
    lea     rdi, [rel f_d]
    mov     rsi, [rel f_dlen]
    call    bn_bitlen
    mov     r14, rax
    lea     rdi, [rel f_a]
    mov     rsi, [rel f_alen]
    call    bn_bitlen
    sub     r14, rax
    add     r14, [rel f_prec]
    inc     r14                            ; s
    mov     r13, r14
    neg     r13                            ; k = -s
    test    r14, r14
    jns     .div_start
    ; s < 0: divide by D * 2^-s instead, from M itself
    mov     r15, r14
    neg     r15
.shift_d:
    lea     rdi, [rel f_d]
    lea     rsi, [rel f_dlen]
    xor     edx, edx
    call    bn_shl1
    dec     r15
    jnz     .shift_d
    xor     r14d, r14d
.div_start:
    lea     rdi, [rel f_a]
    mov     rsi, [rel f_alen]
    call    bn_bitlen
    lea     r15, [rax + r14]               ; numerator bits
    mov     qword [rel t_lo], 0
    mov     qword [rel t_hi], 0
.div_loop:
    test    r15, r15
    jz      .div_done
    dec     r15
    xor     edx, edx                       ; the numerator's bit r15
    cmp     r15, r14
    jb      .div_bit
    lea     rdi, [rel f_a]
    mov     rsi, r15
    sub     rsi, r14
    call    bn_bit
    mov     edx, eax
.div_bit:
    lea     rdi, [rel f_r]
    lea     rsi, [rel f_rlen]
    call    bn_shl1
    mov     rax, [rel t_lo]
    mov     rdx, [rel t_hi]
    shld    rdx, rax, 1
    shl     rax, 1
    mov     [rel t_lo], rax
    mov     [rel t_hi], rdx
    lea     rdi, [rel f_r]
    mov     rsi, [rel f_rlen]
    lea     rdx, [rel f_d]
    mov     rcx, [rel f_dlen]
    call    bn_cmp
    test    eax, eax
    js      .div_loop
    lea     rdi, [rel f_r]
    lea     rsi, [rel f_rlen]
    lea     rdx, [rel f_d]
    mov     rcx, [rel f_dlen]
    call    bn_sub
    or      qword [rel t_lo], 1
    jmp     .div_loop
.div_done:
    cmp     qword [rel f_rlen], 0
    je      .round
    mov     byte [rel f_sticky], 1
    jmp     .round

    ; ---- X * 2^k with X a big integer: keep its top bits in T (66, or
    ; P + 2 for binary128) ----
.reduce:
    lea     rdi, [rel f_a]
    mov     rsi, [rel f_alen]
    call    bn_bitlen
    mov     rcx, 66
    cmp     qword [rel f_prec], 64
    jbe     .keep
    mov     rcx, [rel f_prec]
    add     rcx, 2
.keep:
    cmp     rax, rcx
    jbe     .small
    sub     rax, rcx
    mov     rcx, rax
    add     r13, rcx
    call    f_extract
    jmp     .round
.small:
    mov     rax, [rel f_a]
    mov     [rel t_lo], rax
    mov     rax, [rel f_a + 8]
    mov     [rel t_hi], rax

    ; ---- round T * 2^k (+ sticky) to the format ----
.round:
    mov     rax, [rel t_hi]
    test    rax, rax
    jz      .lo_only
    bsr     rax, rax
    add     rax, 65
    jmp     .have_len
.lo_only:
    mov     rax, [rel t_lo]
    test    rax, rax
    jz      .zero
    bsr     rax, rax
    inc     rax
.have_len:
    ; e = len - 1 + k ; u = max(e - (P-1), emin - (P-1)), emin = 1 - bias
    lea     r14, [rax - 1]
    add     r14, r13
    mov     r15, [rel f_prec]
    dec     r15                            ; P-1
    mov     rax, r14
    sub     rax, r15
    mov     rcx, 1
    sub     rcx, [rel f_bias]
    sub     rcx, r15
    cmp     rax, rcx
    jge     .u_ok
    mov     rax, rcx
.u_ok:
    mov     [rel f_u], rax
    sub     rax, r13                       ; cut = u - k
    cmp     qword [rel f_prec], 64
    ja      .q_round                       ; binary128: 128-bit significand
    test    rax, rax
    jg      .cut
    ; exact: the significand is T shifted up
    neg     rax
    mov     ecx, eax
    mov     r12, [rel t_lo]
    shl     r12, cl
    jmp     .rounded
.cut:
    mov     r14, rax
    lea     rdi, [rax - 1]
    call    f_t_bit                        ; the guard bit
    mov     ebx, eax
    lea     rdi, [r14 - 1]
    call    f_t_low_nonzero
    or      [rel f_sticky], al
    mov     rdi, r14
    call    f_t_shr
    mov     r12, rax                       ; the significand
    test    ebx, ebx
    jz      .rounded
    cmp     byte [rel f_sticky], 0
    jne     .round_up
    test    r12, 1
    jz      .rounded                       ; a tie goes to even
.round_up:
    add     r12, 1
    jc      .carry64
    mov     rcx, [rel f_prec]
    cmp     rcx, 64
    jae     .rounded
    mov     rax, 1
    shl     rax, cl
    cmp     r12, rax
    jne     .rounded
    shr     r12, 1                         ; 2^P: one more exponent
    inc     qword [rel f_u]
    jmp     .rounded
.carry64:
    mov     r12, 0x8000000000000000
    inc     qword [rel f_u]
.rounded:
    ; normal when the leading bit is at P-1, else subnormal (exponent 0)
    mov     rcx, [rel f_prec]
    dec     ecx
    mov     rax, 1
    shl     rax, cl
    xor     edx, edx
    cmp     r12, rax
    jb      .encode
    mov     rdx, [rel f_u]
    add     rdx, rcx
    add     rdx, [rel f_bias]
    mov     r8, [rel f_bias]
    add     r8, r8
    inc     r8                             ; all ones: infinity
    cmp     rdx, r8
    jl      .encode
.inf:
    cmp     qword [rel f_prec], 64
    ja      .q_inf
    mov     rdx, [rel f_bias]
    add     rdx, rdx
    inc     rdx
    xor     r12d, r12d
    cmp     byte [rel f_ext], 0
    je      .encode
    mov     r12, 0x8000000000000000        ; the explicit integer bit
    jmp     .encode
.zero:
    cmp     qword [rel f_prec], 64
    ja      .q_zero
    xor     r12d, r12d
    xor     edx, edx

    ; ---- sign | exponent | fraction ----
.encode:
    cmp     byte [rel f_ext], 0
    jne     .encode_ext
    mov     rcx, [rel f_prec]
    dec     ecx
    mov     rax, 1
    shl     rax, cl
    dec     rax
    and     r12, rax                       ; the fraction
    shl     rdx, cl
    or      r12, rdx
    cmp     byte [rel f_sign], 0
    je      .encoded
    mov     rcx, [rel f_width]
    dec     ecx
    mov     rax, 1
    shl     rax, cl
    or      r12, rax
.encoded:
    mov     rdx, r12
    xor     ecx, ecx
    xor     eax, eax
    jmp     .ret
.encode_ext:
    movzx   eax, byte [rel f_sign]
    shl     eax, 15
    or      eax, edx
    mov     ecx, eax
    mov     rdx, r12
    xor     eax, eax
    jmp     .ret
    ; ---- binary128: the significand S in r11:r12 ----
.q_round:
    test    rax, rax
    jg      .q_cut
    ; exact: T shifted up by -cut
    neg     rax
    mov     ecx, eax
    mov     r12, [rel t_lo]
    mov     r11, [rel t_hi]
    cmp     ecx, 64
    jb      .q_shl
    mov     r11, r12
    xor     r12d, r12d
    sub     ecx, 64
    shl     r11, cl
    jmp     .q_rounded
.q_shl:
    shld    r11, r12, cl
    shl     r12, cl
    jmp     .q_rounded
.q_cut:
    mov     r14, rax
    lea     rdi, [rax - 1]
    call    f_t_bit                        ; the guard bit
    mov     ebx, eax
    lea     rdi, [r14 - 1]
    call    f_t_low_nonzero
    or      [rel f_sticky], al
    ; S = T >> cut
    mov     r12, [rel t_lo]
    mov     r11, [rel t_hi]
    mov     rcx, r14
    cmp     rcx, 128
    jb      .q_shr
    xor     r12d, r12d
    xor     r11d, r11d
    jmp     .q_guard
.q_shr:
    cmp     ecx, 64
    jb      .q_shr_small
    mov     r12, r11
    xor     r11d, r11d
    sub     ecx, 64
    shr     r12, cl
    jmp     .q_guard
.q_shr_small:
    shrd    r12, r11, cl
    shr     r11, cl
.q_guard:
    test    ebx, ebx
    jz      .q_rounded
    cmp     byte [rel f_sticky], 0
    jne     .q_up
    test    r12, 1
    jz      .q_rounded                     ; a tie goes to even
.q_up:
    add     r12, 1
    adc     r11, 0
    mov     rax, 1
    shl     rax, 49                        ; 2^113: one more exponent
    cmp     r11, rax
    jne     .q_rounded
    test    r12, r12
    jnz     .q_rounded
    shrd    r12, r11, 1
    shr     r11, 1
    inc     qword [rel f_u]
.q_rounded:
    ; normal when bit 112 is set, else subnormal (exponent 0)
    xor     edx, edx
    mov     rax, 1
    shl     rax, 48
    cmp     r11, rax
    jb      .q_encode
    mov     rdx, [rel f_u]
    add     rdx, 112
    add     rdx, [rel f_bias]
    cmp     rdx, 32767
    jge     .q_inf
.q_encode:
    mov     rax, 1
    shl     rax, 48
    dec     rax
    and     r11, rax                       ; the fraction's high 48 bits
    shl     rdx, 48
    or      r11, rdx
    jmp     .q_sign
.q_inf:
    mov     r11, 0x7FFF000000000000
    xor     r12d, r12d
    jmp     .q_sign
.q_zero:
    xor     r11d, r11d
    xor     r12d, r12d
.q_sign:
    cmp     byte [rel f_sign], 0
    je      .q_out
    bts     r11, 63
.q_out:
    mov     rdx, r12
    mov     rcx, r11
    xor     eax, eax
    jmp     .ret

.bad:
    mov     rax, EXIT_INVALID_OPERAND
    xor     edx, edx
    xor     ecx, ecx
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;
; float_special
; __Infinity__, __QNaN__ and __SNaN__ in a format: the exponent all ones,
; the fraction 0, its top bit, or 1.
; Input    : edx = FLT_* format, esi = 0 infinity, 1 quiet NaN, 2 signalling
; Output   : rdx, rcx as float_encode's
;
global float_special
float_special:
    dec     edx
    lea     rax, [rel f_formats]
    imul    ecx, edx, 12
    mov     r8d, [rax + rcx]               ; P
    mov     r9d, [rax + rcx + 8]           ; the width
    cmp     edx, 3
    je      .ext
    cmp     edx, 4
    je      .quad
    ; exponent all ones at bits P-1 .. W-2
    mov     ecx, r9d
    sub     ecx, r8d                       ; exponent bits
    mov     rax, 1
    shl     rax, cl
    dec     rax
    lea     ecx, [r8 - 1]
    shl     rax, cl
    cmp     esi, 1
    jne     .not_q
    lea     ecx, [r8 - 2]
    mov     r10, 1
    shl     r10, cl
    or      rax, r10
.not_q:
    cmp     esi, 2
    jne     .out
    or      rax, 1
.out:
    mov     rdx, rax
    xor     ecx, ecx
    ret
.ext:
    mov     rdx, 0x8000000000000000        ; the explicit integer bit
    cmp     esi, 1
    jne     .ext_s
    bts     rdx, 62
.ext_s:
    cmp     esi, 2
    jne     .ext_out
    or      rdx, 1
.ext_out:
    mov     ecx, 0x7FFF
    ret
.quad:
    mov     rcx, 0x7FFF000000000000
    xor     edx, edx
    cmp     esi, 1
    jne     .quad_s
    bts     rcx, 47
.quad_s:
    cmp     esi, 2
    jne     .quad_out
    mov     edx, 1
.quad_out:
    ret

;
; f_read_exp
; Reads an exponent: [+-] digits (clamped to +-100000).
; Input  : rbx = text     Output : rax = 0 or 1 (no digits), rdx = exponent,
;                                  rbx past it
;
f_read_exp:
    xor     r8d, r8d                       ; negative
    cmp     byte [rbx], '+'
    je      .sign
    cmp     byte [rbx], '-'
    jne     .digits
    mov     r8d, 1
.sign:
    inc     rbx
.digits:
    xor     edx, edx
    xor     r9d, r9d                       ; digits seen
.digit:
    movzx   eax, byte [rbx]
    cmp     eax, '_'
    je      .skip
    sub     eax, '0'
    cmp     eax, 9
    ja      .end
    inc     r9d
    cmp     rdx, 100000
    jae     .skip
    imul    rdx, rdx, 10
    add     rdx, rax
.skip:
    inc     rbx
    jmp     .digit
.end:
    test    r9d, r9d
    jz      .none
    test    r8d, r8d
    jz      .ok
    neg     rdx
.ok:
    xor     eax, eax
    ret
.none:
    mov     eax, 1
    ret

;
; f_extract
; T = the 128 bits of f_a from bit rcx up; the bits below rcx set f_sticky.
; Input  : rcx = bit position (>= 1)
;
f_extract:
    lea     r11, [rel f_a]
    mov     r8, rcx
    shr     r8, 6                          ; limb
    mov     r9, rcx
    and     r9d, 63                        ; bit in it
    xor     r10d, r10d
    xor     eax, eax
.below:
    cmp     rax, r8
    jae     .partial
    or      r10, [r11 + rax * 8]
    inc     rax
    jmp     .below
.partial:
    test    r9d, r9d
    jz      .sticky
    mov     rax, 1
    mov     ecx, r9d
    shl     rax, cl
    dec     rax
    and     rax, [r11 + r8 * 8]
    or      r10, rax
.sticky:
    test    r10, r10
    jz      .take
    mov     byte [rel f_sticky], 1
.take:
    mov     ecx, r9d
    mov     rax, [r11 + r8 * 8]
    mov     rdx, [r11 + r8 * 8 + 8]
    shrd    rax, rdx, cl
    mov     [rel t_lo], rax
    mov     rax, [r11 + r8 * 8 + 8]
    mov     rdx, [r11 + r8 * 8 + 16]
    shrd    rax, rdx, cl
    mov     [rel t_hi], rax
    ret

;
; f_t_bit : eax = bit rdi of T (0 past bit 127)
;
f_t_bit:
    xor     eax, eax
    cmp     rdi, 128
    jae     .ret
    mov     rdx, [rel t_lo]
    cmp     rdi, 64
    jb      .test
    mov     rdx, [rel t_hi]
    sub     rdi, 64
.test:
    mov     ecx, edi
    shr     rdx, cl
    and     edx, 1
    mov     eax, edx
.ret:
    ret

;
; f_t_low_nonzero : eax = 1 when any of T's bits below bit rdi is set
;
f_t_low_nonzero:
    xor     eax, eax
    test    rdi, rdi
    jz      .ret
    mov     rdx, [rel t_lo]
    cmp     rdi, 128
    jb      .under_128
    or      rdx, [rel t_hi]
    jmp     .result
.under_128:
    cmp     rdi, 64
    jb      .mask_lo
    mov     rcx, rdi
    sub     ecx, 64
    jz      .result                        ; exactly the low limb
    mov     r8, 1
    shl     r8, cl
    dec     r8
    and     r8, [rel t_hi]
    or      rdx, r8
    jmp     .result
.mask_lo:
    mov     ecx, edi
    mov     r8, 1
    shl     r8, cl
    dec     r8
    and     rdx, r8
.result:
    test    rdx, rdx
    setnz   al
.ret:
    ret

;
; f_t_shr : rax = the low 64 bits of T >> rdi (rdi >= 1)
;
f_t_shr:
    xor     eax, eax
    cmp     rdi, 128
    jae     .ret
    cmp     rdi, 64
    jb      .both
    mov     rax, [rel t_hi]
    mov     rcx, rdi
    sub     ecx, 64
    shr     rax, cl
    ret
.both:
    mov     ecx, edi
    mov     rax, [rel t_lo]
    mov     rdx, [rel t_hi]
    shrd    rax, rdx, cl
.ret:
    ret

; ---- big integers: 64-bit limbs, little-endian, no zero top limb ----

;
; bn_mul_add : x = x * rdx + rcx
; Input  : rdi = limbs, rsi = pointer to the length, rdx = factor, rcx = addend
;
bn_mul_add:
    push    rbx
    mov     r8, rdi
    mov     r9, rsi
    mov     r10, rdx
    mov     r11, rcx                       ; carry
    mov     rbx, [r9]
    xor     ecx, ecx
.limb:
    cmp     rcx, rbx
    jae     .top
    mov     rax, [r8 + rcx * 8]
    mul     r10
    add     rax, r11
    adc     rdx, 0
    mov     [r8 + rcx * 8], rax
    mov     r11, rdx
    inc     rcx
    jmp     .limb
.top:
    test    r11, r11
    jz      .done
    cmp     rbx, FBN_LIMBS
    jae     .done
    mov     [r8 + rbx * 8], r11
    inc     rbx
    mov     [r9], rbx
.done:
    pop     rbx
    ret

;
; bn_bitlen : rax = bits in x (0 for zero)
; Input  : rdi = limbs, rsi = length
;
bn_bitlen:
    test    rsi, rsi
    jz      .zero
    mov     rax, [rdi + rsi * 8 - 8]
    bsr     rax, rax
    inc     rax
    lea     rcx, [rsi - 1]
    shl     rcx, 6
    add     rax, rcx
    ret
.zero:
    xor     eax, eax
    ret

;
; bn_bit : eax = bit rsi of x
; Input  : rdi = limbs, rsi = bit index
;
bn_bit:
    mov     rcx, rsi
    shr     rcx, 6
    mov     rax, [rdi + rcx * 8]
    mov     ecx, esi
    and     ecx, 63
    shr     rax, cl
    and     eax, 1
    ret

;
; bn_shl1 : x = x * 2 + edx
; Input  : rdi = limbs, rsi = pointer to the length, edx = bit shifted in
;
bn_shl1:
    mov     r8, [rsi]
    mov     r9d, edx
    xor     ecx, ecx
.limb:
    cmp     rcx, r8
    jae     .top
    mov     rax, [rdi + rcx * 8]
    mov     r10, rax
    shr     r10, 63
    shl     rax, 1
    or      rax, r9
    mov     [rdi + rcx * 8], rax
    mov     r9, r10
    inc     rcx
    jmp     .limb
.top:
    test    r9, r9
    jz      .ret
    cmp     r8, FBN_LIMBS
    jae     .ret
    mov     [rdi + r8 * 8], r9
    inc     r8
    mov     [rsi], r8
.ret:
    ret

;
; bn_cmp : eax = -1, 0 or 1 as a <, = or > b
; Input  : rdi = a, rsi = a's length, rdx = b, rcx = b's length
;
bn_cmp:
    cmp     rsi, rcx
    ja      .gt
    jb      .lt
    mov     r8, rsi
.limb:
    test    r8, r8
    jz      .eq
    dec     r8
    mov     rax, [rdi + r8 * 8]
    cmp     rax, [rdx + r8 * 8]
    ja      .gt
    jb      .lt
    jmp     .limb
.gt:
    mov     eax, 1
    ret
.lt:
    mov     eax, -1
    ret
.eq:
    xor     eax, eax
    ret

;
; bn_sub : a = a - b (a >= b)
; Input  : rdi = a, rsi = pointer to a's length, rdx = b, rcx = b's length
;
bn_sub:
    push    rbx
    mov     r8, [rsi]
    xor     r9d, r9d                       ; limb
    xor     r10d, r10d                     ; borrow
.limb:
    cmp     r9, r8
    jae     .normalize
    xor     r11d, r11d
    cmp     r9, rcx
    jae     .have_b
    mov     r11, [rdx + r9 * 8]
.have_b:
    mov     rax, [rdi + r9 * 8]
    xor     ebx, ebx
    sub     rax, r11
    adc     ebx, 0
    sub     rax, r10
    adc     ebx, 0
    mov     [rdi + r9 * 8], rax
    mov     r10, rbx
    inc     r9
    jmp     .limb
.normalize:
    test    r8, r8
    jz      .store
    cmp     qword [rdi + r8 * 8 - 8], 0
    jne     .store
    dec     r8
    jmp     .normalize
.store:
    mov     [rsi], r8
    pop     rbx
    ret

[SECTION .rodata]
; precision, exponent bias, width in bits
f_formats:
    dd      11, 15, 16                     ; binary16  (dw)
    dd      24, 127, 32                    ; binary32  (dd)
    dd      53, 1023, 64                   ; binary64  (dq)
    dd      64, 16383, 80                  ; x87 extended (dt)
    dd      113, 16383, 128                ; binary128 (do)

[SECTION .bss]
f_a:        resq FBN_LIMBS + 4             ; M, M * 10^E, or the hex digits
f_d:        resq FBN_LIMBS + 4             ; 10^-E
f_r:        resq FBN_LIMBS + 4             ; the division's remainder
f_alen:     resq 1
f_dlen:     resq 1
f_rlen:     resq 1
t_lo:       resq 1                         ; the value's top bits, T
t_hi:       resq 1
f_prec:     resq 1                         ; P
f_bias:     resq 1
f_width:    resq 1
f_u:        resq 1                         ; exponent of the significand's last bit
f_sign:     resb 1
f_ext:      resb 1                         ; 1: 80-bit format
f_sticky:   resb 1                         ; bits below T were set
