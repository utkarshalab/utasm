; ;
; ============================================
; File     : src/core/string.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

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

; Aliases for backward compatibility
global string_length
string_length:
    jmp     str_len

; ---- str_cmp ----------------------------
;
; str_cmp
; Compares two null-terminated strings lexicographically.
; Input    : rdi = pointer to string A
;             rsi = pointer to string B
; Output   : rax = 0  if A == B
;              rax = -1 if A <  B
;              rax =  1 if A >  B
; Clobbers : rcx, rdx
;
global str_compare
str_compare:
global str_cmp
str_cmp:
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
    ret

.a_less:
    mov     rax, -1
    ret

.a_greater:
    mov     rax, 1
    ret

.a_null:
    test    rsi, rsi
    jz      .equal                 ; both NULL = equal
    mov     rax, -1                ; A=NULL < B
    ret

.b_null:
    mov     rax, 1                 ; A > B=NULL
    ret

; ---- str_cmp_n --------------------------
;
; str_cmp_n
; Compares at most n bytes of two strings.
; Input    : rdi = pointer to string A
;             rsi = pointer to string B
;             rdx = maximum bytes to compare
; Output   : rax = 0 equal, -1 A < B, 1 A > B
; Clobbers : rcx, r8
;
global str_cmp_n
str_cmp_n:
    test    rdx, rdx               ; n = 0 means equal
    jz      .equal
    test    rdi, rdi
    jz      .a_null
    test    rsi, rsi
    jz      .b_null

    xor     rcx, rcx               ; counter = 0

.loop:
    cmp     rcx, rdx               ; reached limit?
    jge     .equal
    mov     al, byte [rdi + rcx]
    mov     r8b, byte [rsi + rcx]
    cmp     al, r8b
    jl      .a_less
    jg      .a_greater
    test    al, al                 ; null terminator?
    jz      .equal
    inc     rcx
    jmp     .loop

.equal:
    xor     rax, rax
    ret

.a_less:
    mov     rax, -1
    ret

.a_greater:
    mov     rax, 1
    ret

.a_null:
    test    rsi, rsi
    jz      .equal
    mov     rax, -1
    ret

.b_null:
    mov     rax, 1
    ret

; ---- str_copy ---------------------------
;
; str_copy
; Copies null-terminated string from src to dst.
; Destination must be large enough — no bounds check.
; Input    : rdi = destination buffer pointer
;             rsi = source string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = pointer to destination (same as rdi)
; Clobbers : rcx, r8
;
global str_copy
str_copy:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr

    mov     rdx, rdi               ; save dst for return

.loop:
    mov     cl, byte [rsi]         ; read source byte
    mov     byte [rdi], cl         ; write to destination
    test    cl, cl                 ; null terminator?
    jz      .done
    inc     rdi
    inc     rsi
    jmp     .loop

.done:
    xor     rax, rax               ; rax = EXIT_OK
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

global string_copy
string_copy:
    jmp     str_copy

; ---- str_copy_n -------------------------
;
; str_copy_n
; Copies at most n bytes from src to dst.
; Always null-terminates dst if n > 0.
; Input    : rdi = destination buffer pointer
;             rsi = source string pointer
;             rdx = maximum bytes to copy (not including null)
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = pointer to destination
; Clobbers : rcx, r8, r9
;
global str_copy_n
str_copy_n:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr
    test    rdx, rdx
    jz      .zero_n

    push    rbx
    mov     rbx, rdi               ; save dst
    mov     rcx, rdx               ; counter = n

.loop:
    test    rcx, rcx
    jz      .terminate
    mov     r8b, byte [rsi]
    mov     byte [rdi], r8b
    test    r8b, r8b
    jz      .done
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .loop

.terminate:
    mov     byte [rdi], 0          ; always null terminate

.done:
    xor     rax, rax
    mov     rdx, rbx               ; rdx = original dst
    pop     rbx
    ret

.zero_n:
    mov     byte [rdi], 0          ; null terminate empty
    xor     rax, rax
    mov     rdx, rdi
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
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

global string_concat
string_concat:
    jmp     str_concat

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

; ---- mem_move ---------------------------
;
; mem_move
; Copies n bytes from src to dst safely handling overlapping regions.
; Input    : rdi = destination pointer
;             rsi = source pointer
;             rdx = number of bytes to copy
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = destination pointer
; Clobbers : rcx, r8
;
global mem_move
mem_move:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi               ; save dst

    ; if dst < src, copy forward (no overlap issue)
    cmp     rdi, rsi
    jl      .forward
    ; if dst > src, copy backward to avoid clobber
    jg      .backward

    ; dst == src, nothing to do
    jmp     .done

.forward:
    mov     rcx, rdx
    rep movsb
    jmp     .done

.backward:
    ; start from end and copy backwards
    mov     rcx, rdx
    add     rdi, rcx
    add     rsi, rcx
    dec     rdi
    dec     rsi
    std                            ; set direction flag = backward
    rep movsb
    cld                            ; restore direction flag = forward

.done:
    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- mem_set ----------------------------
;
; mem_set
; Fills n bytes at dst with the given byte value.
; Input    : rdi = destination pointer
;             rsi = byte value to fill (low byte used)
;             rdx = number of bytes to fill
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = destination pointer
; Clobbers : rax, rcx, r8
;
global mem_set
mem_set:
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi               ; save dst
    mov     rax, rsi               ; fill value
    mov     rcx, rdx               ; count
    rep stosb                      ; fill rcx bytes at rdi with al

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

; ---- mem_cmp ----------------------------
;
; mem_cmp
; Compares n bytes of two memory regions.
; Input    : rdi = pointer to region A
;             rsi = pointer to region B
;             rdx = number of bytes to compare
; Output   : rax = 0 equal, -1 A < B, 1 A > B
; Clobbers : rcx, r8
;
global mem_compare
mem_compare:
global mem_cmp
mem_cmp:
    test    rdx, rdx
    jz      .equal
    test    rdi, rdi
    jz      .null_a
    test    rsi, rsi
    jz      .null_b

    xor     rcx, rcx

.loop:
    cmp     rcx, rdx
    jge     .equal
    mov     al, byte [rdi + rcx]
    mov     r8b, byte [rsi + rcx]
    cmp     al, r8b
    jl      .a_less
    jg      .a_greater
    inc     rcx
    jmp     .loop

.equal:
    xor     rax, rax
    ret

.a_less:
    mov     rax, -1
    ret

.a_greater:
    mov     rax, 1
    ret

.null_a:
    mov     rax, -1
    ret

.null_b:
    mov     rax, 1
    ret

; ---- str_to_int -------------------------
;
; str_to_int
; Converts a string to a signed 64-bit integer.
; Supports decimal, hex (0x prefix), binary (0b prefix),
; octal (0o prefix), and optional leading sign (+ or -).
; Input    : rdi = pointer to null-terminated string
; Output   : rax = EXIT_OK or EXIT_INVALID_IMM
;              rdx = parsed integer value (signed)
; Clobbers : rcx, r8, r9, r10
;
global str_to_int
str_to_int:
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
    jne     .check_prefix
    mov     r13, 1                 ; negative
.skip_sign:
    inc     rdi

.check_prefix:
    ; check for 0x, 0b, 0o prefix
    mov     al, byte [rdi]
    cmp     al, '0'
    jne     .check_suffix
    mov     al, byte [rdi + 1]
    cmp     al, 'x'
    je      .set_hex
    cmp     al, 'X'
    je      .set_hex
    cmp     al, 'b'
    je      .set_bin
    cmp     al, 'B'
    je      .set_bin
    cmp     al, 'o'
    je      .set_oct
    cmp     al, 'O'
    je      .set_oct
    jmp     .check_suffix

.set_hex:
    mov     r12, 16
    add     rdi, 2
    jmp     .parse_loop

.set_bin:
    mov     r12, 2
    add     rdi, 2
    jmp     .parse_loop

.set_oct:
    mov     r12, 8
    add     rdi, 2
    jmp     .parse_loop

.check_suffix:
    ; Check for trailing radix markers (h, b, o, d)
    push    rdi
    extern  str_len
    call    str_len
    pop     rdi
    test    rax, rax
    jz      .parse_loop
    
    ; r8 = length, r9 = last char
    mov     r8, rax
    movzx   r9, byte [rdi + r8 - 1]
    
    ; Hex: h, H
    cmp     r9, 'h'
    je      .found_hex_suffix
    cmp     r9, 'H'
    je      .found_hex_suffix
    
    ; Bin: b, B
    cmp     r9, 'b'
    je      .found_bin_suffix
    cmp     r9, 'B'
    je      .found_bin_suffix
    
    ; Oct: o, O, q, Q
    cmp     r9, 'o'
    je      .found_oct_suffix
    cmp     r9, 'O'
    je      .found_oct_suffix
    cmp     r9, 'q'
    je      .found_oct_suffix
    cmp     r9, 'Q'
    je      .found_oct_suffix
    
    ; Dec: d, D
    cmp     r9, 'd'
    je      .found_dec_suffix
    cmp     r9, 'D'
    je      .found_dec_suffix
    
    jmp     .parse_loop

.found_hex_suffix:
    mov     r12, 16
    dec     r8                     ; ignore suffix in loop
    jmp     .parse_loop_limit

.found_bin_suffix:
    mov     r12, 2
    dec     r8
    jmp     .parse_loop_limit

.found_oct_suffix:
    mov     r12, 8
    dec     r8
    jmp     .parse_loop_limit

.found_dec_suffix:
    mov     r12, 10
    dec     r8
    jmp     .parse_loop_limit

.parse_loop:
    ; Use full length if no suffix
    push    rdi
    extern  str_len
    call    str_len
    pop     rdi
    mov     r8, rax

.parse_loop_limit:
    xor     r10, r10               ; i = 0
.loop:
    cmp     r10, r8
    jge     .apply_sign
    
    movzx   rax, byte [rdi + r10]
    test    al, al
    jz      .apply_sign

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

    ; result = result * base + digit
    mov     rax, rbx
    mul     r12
    test    rdx, rdx
    jnz     .overflow
    add     rax, r9
    jc      .overflow
    mov     rbx, rax
    inc     r10
    jmp     .loop

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

; ---- str_find_char ----------------------
;
; str_find_char
; Finds the first occurrence of a byte in a string.
; Input    : rdi = pointer to null-terminated string
;             rsi = byte to search for (low byte used)
; Output   : rax = EXIT_OK if found, EXIT_ERROR if not found
;              rdx = pointer to first occurrence
; Clobbers : rcx
;
global str_find_char
str_find_char:
    test    rdi, rdi
    jz      .null_ptr

.loop:
    mov     cl, byte [rdi]
    test    cl, cl                 ; end of string?
    jz      .not_found
    cmp     cl, sil                ; match?
    je      .found
    inc     rdi
    jmp     .loop

.found:
    xor     rax, rax
    mov     rdx, rdi
    ret

.not_found:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret
    ret

; ---- str_find_str -----------------------
;
; str_find_str
; Finds the first occurrence of needle in haystack.
; Input    : rdi = haystack string pointer
;             rsi = needle string pointer
; Output   : rax = EXIT_OK if found, EXIT_ERROR if not found
;              rdx = pointer to start of occurrence
; Clobbers : rcx, r8, r9
;
global str_find_str
str_find_str:
    test    rdi, rdi
    jz      .null_ptr
    test    rsi, rsi
    jz      .null_ptr

    ; empty needle matches start of haystack
    cmp     byte [rsi], 0
    je      .found_empty

.loop_haystack:
    mov     al, byte [rdi]
    test    al, al
    jz      .not_found

    ; check if needle starts here
    xor     rcx, rcx
.loop_needle:
    mov     r8b, byte [rsi + rcx]
    test    r8b, r8b
    jz      .found                 ; reached end of needle = match
    mov     r9b, byte [rdi + rcx]
    cmp     r8b, r9b
    jne     .next_haystack
    inc     rcx
    jmp     .loop_needle

.next_haystack:
    inc     rdi
    jmp     .loop_haystack

.found_empty:
    xor     rax, rax
    mov     rdx, rdi
    ret

.found:
    xor     rax, rax
    mov     rdx, rdi
    ret

.not_found:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_to_upper -----------------------
;
; str_to_upper
; Converts a null-terminated string to uppercase in-place.
; Input    : rdi = string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = string pointer
; Clobbers : rcx
;
global str_to_upper
str_to_upper:
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi

.loop:
    mov     al, byte [rdi]
    test    al, al
    jz      .done
    cmp     al, 'a'
    jl      .next
    cmp     al, 'z'
    jg      .next
    sub     al, 32                 ; 'a' - 'A' = 32
    mov     byte [rdi], al

.next:
    inc     rdi
    jmp     .loop

.done:
    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_to_lower -----------------------
;
; str_to_lower
; Converts a null-terminated string to lowercase in-place.
; Input    : rdi = string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = string pointer
; Clobbers : rcx
;
global str_to_lower
str_to_lower:
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi

.loop:
    mov     al, byte [rdi]
    test    al, al
    jz      .done
    cmp     al, 'A'
    jl      .next
    cmp     al, 'Z'
    jg      .next
    add     al, 32
    mov     byte [rdi], al

.next:
    inc     rdi
    jmp     .loop

.done:
    xor     rax, rax
    mov     rdx, rbx
    pop     rbx
    ret

.null_ptr:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- str_trim ---------------------------
;
; str_trim
; Trims leading and trailing whitespace from a string in-place.
; Input    : rdi = string pointer
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = pointer to new start of string
; Clobbers : rcx, r8
;
global str_trim
str_trim:
    test    rdi, rdi
    jz      .null_ptr

    push    rbx
    mov     rbx, rdi

    ; trim leading
.trim_leading:
    mov     al, byte [rbx]
    test    al, al
    jz      .done_leading
    ; check for space, tab, cr, lf
    cmp     al, ' '
    je      .skip_leading
    cmp     al, 9                  ; tab
    je      .skip_leading
    cmp     al, 10                 ; lf
    je      .skip_leading
    cmp     al, 13                 ; cr
    je      .skip_leading
    jmp     .done_leading

.skip_leading:
    inc     rbx
    jmp     .trim_leading

.done_leading:
    ; trim trailing
    push    rdi
    push    rsi
    mov     rdi, rbx
    extern  str_len
    call    str_len
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .done

    lea     rcx, [rbx + rax - 1]   ; end of string
.trim_trailing:
    cmp     rcx, rbx
    jl      .done
    mov     al, byte [rcx]
    cmp     al, ' '
    je      .skip_trailing
    cmp     al, 9
    je      .skip_trailing
    cmp     al, 10
    je      .skip_trailing
    cmp     al, 13
    je      .skip_trailing
    jmp     .done

.skip_trailing:
    mov     byte [rcx], 0
    dec     rcx
    jmp     .trim_trailing

.done:
    xor     rax, rax
    mov     rdx, rbx
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

; ---- str_split_char ---------------------
;
; str_split_char
; Splits a string by a delimiter character.
; Replaces the first occurrence of delimiter with null.
; Input    : rdi = string pointer
;             rsi = delimiter character
; Output   : rax = EXIT_OK or EXIT_ERROR
;              rdx = pointer to second part (or NULL if no split)
; Clobbers : rcx
;
global str_split_char
str_split_char:
    test    rdi, rdi
    jz      .null_ptr

.loop:
    mov     al, byte [rdi]
    test    al, al
    jz      .not_found
    cmp     al, sil
    je      .found
    inc     rdi
    jmp     .loop

.found:
    mov     byte [rdi], 0          ; split
    inc     rdi
    xor     rax, rax
    mov     rdx, rdi
    ret

.not_found:
    xor     rax, rax
    xor     rdx, rdx
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

; ---- str_is_alpha -----------------------
global str_is_alpha
str_is_alpha:
    movzx   eax, dil
    cmp     al, 'a'
    jl      .check_upper
    cmp     al, 'z'
    jle     .yes
.check_upper:
    cmp     al, 'A'
    jl      .no
    cmp     al, 'Z'
    jle     .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; ---- str_is_digit -----------------------
global str_is_digit
str_is_digit:
    movzx   eax, dil
    cmp     al, '0'
    jl      .no
    cmp     al, '9'
    jle     .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; ---- str_is_alnum -----------------------
global str_is_alnum
str_is_alnum:
    push    rdi
    call    str_is_alpha
    test    rax, rax
    jnz     .yes
    pop     rdi
    call    str_is_digit
    ret
.yes:
    pop     rdx
    ret

; ---- str_hash ---------------------------
; DJB2 Hash
global str_hash
str_hash:
    mov     rax, 5381
.loop:
    movzx   rcx, byte [rdi]
    test    cl, cl
    jz      .done
    ; hash = ((hash << 5) + hash) + c
    mov     rdx, rax
    shl     rax, 5
    add     rax, rdx
    add     rax, rcx
    inc     rdi
    jmp     .loop
.done:
    ret

; ============================================================================
; Path Utilities
; ============================================================================

; ---- path_get_filename ------------------
; Returns pointer to the filename part of a path.
global path_get_filename
path_get_filename:
    test    rdi, rdi
    jz      .null
    
    push    rbx
    mov     rbx, rdi
    
    ; find last / or \
    push    rdi
    call    str_len
    pop     rdi
    
    lea     rcx, [rdi + rax - 1]
.loop:
    cmp     rcx, rdi
    jl      .done                  ; not found, return original
    mov     al, byte [rcx]
    cmp     al, '/'
    je      .found
    cmp     al, '\'
    je      .found
    dec     rcx
    jmp     .loop

.found:
    lea     rbx, [rcx + 1]

.done:
    mov     rdx, rbx
    xor     rax, rax
    pop     rbx
    ret

.null:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- path_get_extension -----------------
; Returns pointer to the extension (including .) or NULL.
global path_get_extension
path_get_extension:
    test    rdi, rdi
    jz      .null
    
    push    rdi
    call    str_len
    pop     rdi
    
    lea     rcx, [rdi + rax - 1]
.loop:
    cmp     rcx, rdi
    jl      .not_found
    mov     al, byte [rcx]
    cmp     al, '.'
    je      .found
    cmp     al, '/'
    je      .not_found
    cmp     al, '\'
    je      .not_found
    dec     rcx
    jmp     .loop

.found:
    mov     rdx, rcx
    xor     rax, rax
    ret

.not_found:
    xor     rax, rax
    xor     rdx, rdx
    ret

.null:
    mov     rax, EXIT_ERROR
    ret

; ============================================================================
; Hex Helpers
; ============================================================================

; ---- hex_to_byte ------------------------
; Converts two hex chars to a byte.
global hex_to_byte
hex_to_byte:
    ; first nibble
    movzx   eax, byte [rdi]
    call    .nibble
    shl     al, 4
    mov     cl, al
    
    ; second nibble
    movzx   eax, byte [rdi + 1]
    call    .nibble
    or      al, cl
    ret

.nibble:
    cmp     al, '0'
    jl      .err
    cmp     al, '9'
    jle     .n_digit
    cmp     al, 'a'
    jl      .n_upper
    cmp     al, 'f'
    jg      .err
    sub     al, 'a' - 10
    ret
.n_upper:
    cmp     al, 'A'
    jl      .err
    cmp     al, 'F'
    jg      .err
    sub     al, 'A' - 10
    ret
.n_digit:
    sub     al, '0'
    ret
.err:
    xor     al, al
    ret

; ============================================================================
; Memory Management Bridge
; ============================================================================

; ---- str_free ---------------------------
global str_free
str_free:
    test    rdi, rdi
    jz      .done
    extern  heap_free
    jmp     heap_free
.done:
    ret

; ---- str_is_hex_digit -------------------
global str_is_hex_digit
str_is_hex_digit:
    movzx   eax, dil
    cmp     al, '0'
    jl      .no
    cmp     al, '9'
    jle     .yes
    cmp     al, 'a'
    jl      .check_upper
    cmp     al, 'f'
    jle     .yes
.check_upper:
    cmp     al, 'A'
    jl      .no
    cmp     al, 'F'
    jle     .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; ---- str_is_ident_char ------------------
global str_is_ident_char
str_is_ident_char:
    push    rdi
    call    str_is_alnum
    test    rax, rax
    jnz     .yes_pop
    pop     rdi
    cmp     dil, '_'
    je      .yes
    cmp     dil, '.'
    je      .yes
    xor     rax, rax
    ret
.yes_pop:
    pop     rdi
.yes:
    mov     rax, 1
    ret

; ---- str_int_to_str ---------------------
; Wrapper for int_to_str with base 10.
global str_int_to_str
str_int_to_str:
    mov     rdx, 10
    jmp     int_to_str

; ---- str_utf8_decode --------------------
; Decodes a UTF-8 character at [RDI].
; Returns code point in RAX, length in RDX.
global str_utf8_decode
str_utf8_decode:
    movzx   eax, byte [rdi]
    mov     rdx, 1
    ; Very basic: only 1-byte support for now
    ret
