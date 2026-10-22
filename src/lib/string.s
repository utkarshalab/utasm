; ;
; ============================================
; File     : src/lib/string.s
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
; STRING UTILITIES
; ============================================================================
; Core string and memory operations used by every utasm module.
; The lexer, parser, preprocessor, symbol table, and error reporter
; all depend on these routines.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result
;   callee saved: rbx, r12-r15, rbp
;
; All functions that can fail return:
;   rax = EXIT_OK or error code
;   rdx = result value (only valid if rax == EXIT_OK)
;
; Functions that cannot fail (pure computation):
;   rax = result directly (no error code)

[SECTION .bss]
str_int_wrapped: resb 1                 ; str_to_int: the number did not fit in 64 bits

[SECTION .text]
    cld                             ; ensure direction flag is always forward

; ---- str_len ----------------------------
;
; str_len
; Returns the length of a null-terminated string.
; Does not count the null terminator.
; Cannot fail — returns length directly in rax.
; Input    : rdi = pointer to null-terminated string
; Output   : rax = length in bytes
; Clobbers : rcx
;
global str_len
str_len:
    ; guard against NULL pointer
    test    rdi, rdi
    jz      .null_ptr

    xor     rax, rax               ; length counter = 0

.loop:
    cmp     byte [rdi + rax], 0    ; check current byte
    je      .done                  ; found null terminator
    inc     rax                    ; advance counter
    jmp     .loop

.done:
    ret

.null_ptr:
    xor     rax, rax               ; NULL = length 0
    ret

; ---- str_cmp ----------------------------
;
; str_cmp
; Compares two null-terminated strings lexicographically.
; Input    : rdi = pointer to string A
;             rsi = pointer to string B
; Output   : rax = 0  if A == B
;              rax = -1 if A <  B
;              rax =  1 if A >  B
; Clobbers : rax only.
;   The walk below advances RDI/RSI and scratches CL/DL, so all four are saved
;   and restored. Callers routinely keep the string pointer or a loop counter
;   in those registers across the call, and a comparison that stopped part way
;   through a string used to hand back a pointer into the middle of it.
;
global str_compare
str_compare:
global str_cmp
str_cmp:
    push    rdi
    push    rsi
    push    rcx
    push    rdx

    ; guard against NULL
    test    rdi, rdi
    jz      .a_null
    test    rsi, rsi
    jz      .b_null

.loop:
    mov     cl, byte [rdi]         ; cl = byte from A
    mov     dl, byte [rsi]         ; dl = byte from B
    cmp     cl, dl
    jl      .a_less
    jg      .a_greater
    test    cl, cl                 ; both equal — check null
    jz      .equal                 ; both null = strings equal
    inc     rdi
    inc     rsi
    jmp     .loop

.equal:
    xor     rax, rax               ; rax = 0
    jmp     .ret

.a_less:
    mov     rax, -1
    jmp     .ret

.a_greater:
    mov     rax, 1
    jmp     .ret

.a_null:
    test    rsi, rsi
    jz      .equal                 ; both NULL = equal
    mov     rax, -1                ; A=NULL < B
    jmp     .ret

.b_null:
    mov     rax, 1                 ; A > B=NULL

.ret:
    pop     rdx
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ---- str_cmp_kw -------------------------
;
; str_cmp_kw
; Is a source word a keyword, in any letter case? ("DWORD", "Bits")
; Input    : rdi = the word, rsi = the keyword, in lower case
; Output   : rax = 0 equal, 1 not
; Clobbers : nothing else
;
global str_cmp_kw
str_cmp_kw:
    push    rdi
    push    rsi
    push    rcx
    test    rdi, rdi
    jz      .differ
    test    rsi, rsi
    jz      .differ
.loop:
    movzx   ecx, byte [rdi]
    lea     eax, [rcx - 'A']
    cmp     eax, 'Z' - 'A'
    ja      .folded
    or      ecx, 0x20
.folded:
    cmp     cl, [rsi]
    jne     .differ
    test    cl, cl
    jz      .equal
    inc     rdi
    inc     rsi
    jmp     .loop
.equal:
    xor     eax, eax
    jmp     .ret
.differ:
    mov     eax, 1
.ret:
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ---- str_concat -------------------------
;
; str_concat
; Appends src to the end of dst.
; Destination must have enough space.
; Input    : rdi = destination buffer pointer
;             rsi = source string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = pointer to destination
; Clobbers : rcx, r8
;
global str_concat
str_concat:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi               ; save original dst

    ; find end of dst
.find_end:
    cmp     byte [rdi], 0
    je      .append
    inc     rdi
    jmp     .find_end

    ; append src
.append:
    mov     cl, byte [rsi]
    mov     byte [rdi], cl
    test    cl, cl
    jz      .done
    inc     rdi
    inc     rsi
    jmp     .append

.done:
    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- mem_copy ---------------------------
;
; mem_copy
; Copies n bytes from src to dst.
; Regions must not overlap — use mem_move for overlapping regions.
; Input    : rdi = destination pointer
;             rsi = source pointer
;             rdx = number of bytes to copy
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = destination pointer
; Clobbers : rcx, r8
;
global mem_copy
mem_copy:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi               ; save dst
    mov     rcx, rdx               ; count = n
    rep movsb                      ; copy rcx bytes from rsi to rdi

    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- mem_zero ---------------------------
;
; mem_zero
; Fills n bytes at dst with zero.
; Input    : rdi = destination pointer
;             rsi = number of bytes to zero
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = destination pointer
; Clobbers : rax, rcx
;
global mem_zero
mem_zero:
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi
    xor     rax, rax               ; fill value = 0
    mov     rcx, rsi               ; count
    rep stosb

    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_to_int -------------------------
;
; str_to_int
; Converts a string to a signed 64-bit integer, by NASM's rules: an
; optional sign; "$" + digits for hex; the prefixes 0x/0h (hex), 0d/0t
; (decimal), 0o/0q (octal), 0b/0y (binary); else the suffixes h/x, d/t,
; o/q, b/y; else decimal. Underscores between digits are ignored.
; Input    : rdi = pointer to null-terminated string
; Output   : rax = EXIT_OK or EXIT_INVALID_IMM
;              rdx = parsed integer value (signed)
; Clobbers : rcx, r8, r9, r10
;
global str_to_int, str_int_wrapped
str_to_int:
    mov     byte [rel str_int_wrapped], 0
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    push    r12
    push    r13

    xor     rbx, rbx               ; result = 0
    mov     r12, 10                ; default base = 10
    xor     r13, r13               ; sign = positive (0 = pos, 1 = neg)

    ; check for leading sign
    mov     al, byte [rdi]
    cmp     al, '+'
    je      .skip_sign
    cmp     al, '-'
    jne     .radix
    mov     r13, 1                 ; negative
.skip_sign:
    inc     rdi

    ; NASM's radix rules: "$" + digit is hex; "0" + a radix letter is a
    ; prefix (0x 0h hex, 0d 0t decimal, 0o 0q octal, 0b 0y binary);
    ; otherwise a trailing radix letter is a suffix (ffh, 777q, 1010b,
    ; 100d). Underscores are ignored.
.radix:
    ; the common case first: decimal digits only, 19 at most (never past
    ; 64 bits); anything else - a radix, '_', a 20th digit - is read below
    xor     ecx, ecx
.plain:
    movzx   eax, byte [rdi + rcx]
    sub     eax, '0'
    cmp     eax, 9
    ja      .plain_end
    cmp     ecx, 19
    jae     .general
    imul    rbx, rbx, 10
    add     rbx, rax
    inc     ecx
    jmp     .plain
.plain_end:
    test    ecx, ecx
    jz      .general
    cmp     byte [rdi + rcx], 0
    je      .apply_sign
.general:
    xor     ebx, ebx
    push    rdi
    call    str_len
    pop     rdi
    mov     r8, rax                ; r8 = characters left to read
    ; both may be there: the larger radix is the one (NASM's readnum), so
    ; "0dh" is hex 0d and "0x1b" hex 1b; the same one twice: decimal
    xor     r9d, r9d               ; the prefix's radix | its length << 8
    cmp     byte [rdi], '$'
    jne     .zero_prefix
    cmp     r8, 1
    jbe     .suffix
    mov     r9d, 16 | 1 << 8
    jmp     .suffix
.zero_prefix:
    cmp     r8, 2
    jbe     .suffix
    cmp     byte [rdi], '0'
    jne     .suffix
    movzx   ecx, byte [rdi + 1]
    call    .radix_letter
    test    eax, eax
    jz      .suffix
    lea     r9d, [rax + (2 << 8)]
.suffix:
    xor     eax, eax               ; the suffix's radix
    cmp     r8, 1
    jbe     .choose
    movzx   ecx, byte [rdi + r8 - 1]
    call    .radix_letter
.choose:
    cmp     r9b, al
    ja      .by_prefix
    jb      .by_suffix
    jmp     .digits                ; neither, or both alike: decimal
.by_prefix:
    movzx   r12d, r9b
    shr     r9d, 8
    add     rdi, r9
    sub     r8, r9
    jmp     .digits
.by_suffix:
    mov     r12, rax
    dec     r8

.digits:
    test    r8, r8
    jz      .invalid
    xor     r10, r10               ; i = 0
.loop:
    cmp     r10, r8
    jge     .apply_sign

    movzx   rax, byte [rdi + r10]
    test    al, al
    jz      .apply_sign
    cmp     al, '_'
    jne     .digit
    inc     r10
    jmp     .loop
.digit:
    ; convert char to digit value
    cmp     al, '0'
    jl      .invalid
    cmp     al, '9'
    jle     .is_decimal

    ; check hex letters
    cmp     al, 'a'
    jl      .check_upper
    cmp     al, 'f'
    jg      .invalid
    sub     al, 'a'
    add     al, 10
    jmp     .validate_digit

.check_upper:
    cmp     al, 'A'
    jl      .invalid
    cmp     al, 'F'
    jg      .invalid
    sub     al, 'A'
    add     al, 10
    jmp     .validate_digit

.is_decimal:
    sub     al, '0'

.validate_digit:
    ; digit must be < base
    movzx   r9, al
    cmp     r9, r12
    jge     .invalid

    ; result = result * base + digit - past 64 bits the low 64 are kept
    ; and str_int_wrapped says so (NASM's "does not fit in 64 bits"
    ; warning, parser.s); it was an error
    mov     rax, rbx
    mul     r12
    test    rdx, rdx
    jz      .no_wrap_mul
    mov     byte [rel str_int_wrapped], 1
.no_wrap_mul:
    add     rax, r9
    jnc     .no_wrap_add
    mov     byte [rel str_int_wrapped], 1
.no_wrap_add:
    mov     rbx, rax
    inc     r10
    jmp     .loop

; ecx = a character: eax = the radix it names (b y 2, o q 8, d t 10,
; h x 16), or 0
.radix_letter:
    or      ecx, 0x20
    mov     eax, 2
    cmp     ecx, 'b'
    je      .rl_ret
    cmp     ecx, 'y'
    je      .rl_ret
    mov     eax, 8
    cmp     ecx, 'o'
    je      .rl_ret
    cmp     ecx, 'q'
    je      .rl_ret
    mov     eax, 10
    cmp     ecx, 'd'
    je      .rl_ret
    cmp     ecx, 't'
    je      .rl_ret
    mov     eax, 16
    cmp     ecx, 'h'
    je      .rl_ret
    cmp     ecx, 'x'
    je      .rl_ret
    xor     eax, eax
.rl_ret:
    ret

.overflow:
    mov     rax, EXIT_INVALID_IMM
    xor     rdx, rdx
    pop     r13
    pop     r12
    pop     rbx
    ret

.apply_sign:
    test    r13, r13               ; negative?
    jz      .done
    neg     rbx                    ; negate result

.done:
    xor     rax, rax               ; rax = EXIT_OK
    mov     rdx, rbx               ; rdx = parsed value
    pop     r13
    pop     r12
    pop     rbx
    ret

.invalid:
    mov     rax, EXIT_INVALID_IMM
    xor     rdx, rdx
    pop     r13
    pop     r12
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_dup ----------------------------
;
; str_dup
; Duplicates a string using heap allocation.
; Input    : rdi = string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR/EXIT_OOM
;              rdx = pointer to new string
; Clobbers : rcx, rsi
;
global str_dup
str_dup:
    test    rdi, rdi
    jz      .null_ptr

    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, rdi               ; save src

    ; get length
    call    str_len
    inc     rax                    ; +1 for null
    
    ; allocate
    push    rax
    mov     rdi, rax
    extern  heap_alloc
    call    heap_alloc
    pop     rcx                    ; rcx = size
    test    rax, rax
    jz      .no_mem

    ; copy
    mov     rdi, rdx               ; dst = allocated ptr
    mov     rsi, rbx               ; src = original
    rep movsb

    xor     rax, rax
    ; rdx already contains allocated pointer from heap_alloc
    pop     rbx
    leave
    ret

.no_mem:
    mov     rax, EXIT_OOM
    xor     rdx, rdx
    pop     rbx
    leave
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- int_to_str -------------------------
;
; int_to_str
; Converts a 64-bit integer to a string.
; Input    : rdi = destination buffer
;             rsi = integer value
;             rdx = base (2, 8, 10, 16)
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = destination buffer
; Clobbers : rax, rcx, r8, r9
;
global int_to_str
int_to_str:
    test    rdi, rdi
    jz      .null_ptr
    cmp     rdx, 2
    jl      .invalid_base
    cmp     rdx, 36
    jg      .invalid_base

    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; save start
    mov     rax, rsi               ; value
    mov     r12, rdx               ; base
    
    ; check for negative (only if base 10)
    cmp     r12, 10
    jne     .unsigned
    test    rax, rax
    jns     .unsigned
    mov     byte [rdi], '-'
    inc     rdi
    neg     rax

.unsigned:
    mov     r13, rdi               ; start of digits
    
.convert_loop:
    xor     rdx, rdx
    div     r12
    
    ; convert remainder to char
    cmp     dl, 10
    jl      .digit
    add     dl, 'A' - 10
    jmp     .store
.digit:
    add     dl, '0'
.store:
    mov     byte [rdi], dl
    inc     rdi
    test    rax, rax
    jnz     .convert_loop
    
    mov     byte [rdi], 0          ; null terminate
    
    ; reverse digits
    mov     rsi, rdi
    dec     rsi                    ; rsi = end of string
    mov     rdi, r13               ; rdi = start of digits
    
.reverse_loop:
    cmp     rdi, rsi
    jge     .done
    mov     al, byte [rdi]
    mov     ah, byte [rsi]
    mov     byte [rdi], ah
    mov     byte [rsi], al
    inc     rdi
    dec     rsi
    jmp     .reverse_loop

.done:
    xor     rax, rax
    mov     rdx, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

.invalid_base:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_is_ident_char ------------------
global str_is_ident_char
str_is_ident_char:
    movzx   eax, dil
    movzx   eax, byte [str_ident_chars + rax]
    ret

[SECTION .rodata]
; 1 for a character a name goes on with: a-z A-Z 0-9 _ . and NASM's @
; (..@x, names with @ in them), $ and ? (__?float32?__, a?b)
global str_ident_chars
str_ident_chars:
    %assign i 0
    %rep 256
    %if (i >= 'a' && i <= 'z') || (i >= 'A' && i <= 'Z') || (i >= '0' && i <= '9') || i == '_' || i == '.' || i == '@' || i == '$' || i == '?'
        db 1
    %else
        db 0
    %endif
    %assign i i+1
    %endrep
[SECTION .text]

; ---- str_int_to_str ---------------------
; Wrapper for int_to_str with base 10.
global str_int_to_str
str_int_to_str:
    mov     rdx, 10
    jmp     int_to_str

; ---- str_utf8_decode --------------------
; Decodes one UTF-8 character.
; Input  : RDI = pointer to it, RSI = end of the buffer
; Output : RAX = its length in bytes (1-4), or 0 when it is malformed
;          (truncated, bad continuation byte, overlong form, a UTF-16
;          surrogate or above U+10FFFF); RDX = the code point
; Clobbers: RCX, R8, R9
global str_utf8_decode
str_utf8_decode:
    xor     edx, edx
    cmp     rdi, rsi
    jae     .bad
    movzx   eax, byte [rdi]
    cmp     eax, 0x80
    jb      .ascii
    cmp     eax, 0xC2
    jb      .bad                   ; continuation byte, or overlong C0/C1
    cmp     eax, 0xE0
    jb      .two
    cmp     eax, 0xF0
    jb      .three
    cmp     eax, 0xF4
    ja      .bad                   ; above U+10FFFF
    ; 4 bytes: 11110xxx
    and     eax, 0x07
    mov     edx, eax
    mov     ecx, 4
    jmp     .cont
.three:
    and     eax, 0x0F
    mov     edx, eax
    mov     ecx, 3
    jmp     .cont
.two:
    and     eax, 0x1F
    mov     edx, eax
    mov     ecx, 2
.cont:
    lea     r8, [rdi + rcx]
    cmp     r8, rsi
    ja      .bad                   ; truncated
    mov     r8d, 1
.cont_loop:
    movzx   eax, byte [rdi + r8]
    mov     r9d, eax
    and     r9d, 0xC0
    cmp     r9d, 0x80
    jne     .bad                   ; not a continuation byte
    shl     edx, 6
    and     eax, 0x3F
    or      edx, eax
    inc     r8d
    cmp     r8d, ecx
    jb      .cont_loop
    ; the shortest form only, no surrogates, nothing above U+10FFFF
    cmp     ecx, 3
    je      .check3
    ja      .check4
    jmp     .ok                    ; 2 bytes: C2 and up are never overlong
.check3:
    cmp     edx, 0x800
    jb      .bad
    cmp     edx, 0xD800
    jb      .ok
    cmp     edx, 0xDFFF
    jbe     .bad
    jmp     .ok
.check4:
    cmp     edx, 0x10000
    jb      .bad
    cmp     edx, 0x10FFFF
    ja      .bad
.ok:
    mov     eax, ecx
    ret
.ascii:
    mov     edx, eax
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret
