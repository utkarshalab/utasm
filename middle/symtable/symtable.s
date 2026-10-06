;
; ============================================
; File     : src/core/symbol.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern arena_alloc

; ============================================================================
; SYMBOL TABLE (Hash Table Implementation)
; ============================================================================
; Manages the registration and lookup of labels, constants, and macros.
; Implements a high-performance FNV-1a 64-bit hash table with linear probing.
; ============================================================================

[SECTION .text]

; ---- symbol_init ------------------------
global symbol_init
symbol_init:
    prologue
    push    rbx
    mov     rbx, rdi

    ; 1. Linear Symbol Array (Sequential storage) and 2. the hash table:
    ;    MAX_SYMBOL slots each, reserved and committed as they are used
    ;    (a 500,000-line kernel has hundreds of thousands of symbols)
    extern  mem_reserve
    mov     rsi, SYMBOL_SIZE
    imul    rsi, MAX_SYMBOL
    call    mem_reserve
    check_err
    mov     [rbx + ASMCTX_symtab], rdx
    mov     dword [rbx + ASMCTX_symcount], 0
    mov     rsi, 8
    imul    rsi, MAX_SYMBOL
    call    mem_reserve                    ; zeroed: every bucket empty
    check_err
    mov     [rbx + ASMCTX_symhash], rdx

    xor     rax, rax
    pop     rbx
    epilogue

.error:
    pop     rbx
    epilogue

; ---- symbol_hash ------------------------
; FNV-1a 64-bit hash
; Input: RSI = string pointer (preserved)
; Output: RAX = hash
symbol_hash:
    prologue
    push    rsi                     ; callers keep using the name afterwards
    mov     rax, 0xcbf29ce484222325 ; FNV offset basis
    mov     r10, 0x100000001b3      ; FNV prime
.loop:
    movzx   rcx, byte [rsi]
    test    cl, cl
    jz      .done
    xor     al, cl
    mul     r10
    inc     rsi
    jmp     .loop
.done:
    pop     rsi
    epilogue

; ---- symbol_unescape --------------------
; rdi = a name -> rax = the name without the $ of "$name" (a $ before a
; letter, '_', '.' or '?'). Clobbers nothing else.
symbol_unescape:
    mov     rax, rdi
    test    rdi, rdi
    jz      .ret
    cmp     byte [rdi], '$'
    jne     .ret
    push    rcx
    movzx   ecx, byte [rdi + 1]
    or      cl, 0x20               ; ASCII letters to lower case
    cmp     cl, 'a'
    jb      .other
    cmp     cl, 'z'
    jbe     .strip
.other:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, '_'
    je      .strip
    cmp     cl, '.'
    je      .strip
    cmp     cl, '?'
    jne     .keep
.strip:
    inc     rax
.keep:
    pop     rcx
.ret:
    ret

; ---- symbol_add -------------------------
global symbol_add
symbol_add:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi               ; AsmCtx
    mov     r12, rsi               ; Template symbol
    ; "$name" is the symbol "name" (NASM's escape for names that are
    ; registers or keywords)
    mov     rdi, [r12 + SYMBOL_name]
    call    symbol_unescape
    mov     [r12 + SYMBOL_name], rax

    ; 1. Check if it already exists (Hash lookup)
    mov     rdi, rbx
    mov     rsi, [r12 + SYMBOL_name]
    call    symbol_find
    IF rax, e, OK
        mov     rax, EXIT_DUP_SYMBOL
        jmp     .done
        ENDIF

    ; 2. Add to Linear Array
    mov     eax, [rbx + ASMCTX_symcount]
    
    ; Check load factor (limit to 3/4 of MAX_SYMBOL)
    IF rax, g, MAX_SYMBOL / 4 * 3
        mov     rax, EXIT_SYMBOL_RANGE
        jmp     .done
        ENDIF

    mov     rcx, rax
    imul    rcx, SYMBOL_SIZE
    mov     r13, [rbx + ASMCTX_symtab]
    add     r13, rcx               ; r13 = Slot in linear table
    
    ; Copy symbol data
    mov     rdi, r13
    mov     rsi, r12
    mov     rcx, (SYMBOL_SIZE / 8)
    rep movsq

    ; 3. Index in Hash Table (Quadratic Probing)
    mov     rsi, [r13 + SYMBOL_name]
    call    symbol_hash
    mov     r10, rax
    and     r10, (MAX_SYMBOL - 1)  ; base hash
    
    mov     r11, [rbx + ASMCTX_symhash]
    mov     rcx, 0                 ; i = 0
.probe:
    cmp     rcx, MAX_SYMBOL
    jge     .error_limit
    
    ; pos = (hash + (i*i + i)/2) % MAX_SYMBOL
    mov     rax, rcx
    imul    rax, rcx
    add     rax, rcx
    shr     rax, 1
    add     rax, r10
    and     rax, (MAX_SYMBOL - 1)
    
    lea     rdx, [r11 + rax * 8]
    cmp     qword [rdx], 0
    je      .found_slot
    
    inc     rcx
    jmp     .probe

.error_limit:
    mov     rax, EXIT_SYMBOL_RANGE
    jmp     .done

.found_slot:
    mov     [rdx], r13             ; Store pointer to symbol in bucket

    ; 4. Increment count
    inc     dword [rbx + ASMCTX_symcount]
    mov     rdx, r13               ; Return pointer to stored symbol
    xor     rax, rax

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- symbol_find ------------------------
global symbol_find
symbol_find:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rsi
    call    symbol_unescape        ; "$name" is "name"
    mov     rsi, rax
    mov     r12, rsi               ; Name to find

    call    symbol_hash
    mov     r10, rax
    and     r10, (MAX_SYMBOL - 1)
    
    mov     r11, [rbx + ASMCTX_symhash]
    mov     rcx, 0                 ; i = 0 (iteration counter)
.probe:
    cmp     rcx, MAX_SYMBOL
    jge     .not_found
    
    ; pos = (hash + (i*i + i)/2) % MAX_SYMBOL
    mov     rax, rcx
    imul    rax, rcx               ; i*i
    add     rax, rcx               ; i*i + i
    shr     rax, 1                 ; (i*i + i)/2
    add     rax, r10               ; hash + ...
    and     rax, (MAX_SYMBOL - 1)  ; modulo size
    
    mov     rdx, [r11 + rax * 8]
    test    rdx, rdx
    jz      .not_found
    
    ; Compare names. str_cmp scratches CL/DL, and RCX is the probe counter,
    ; so it has to be saved or a collision sends the probe to a random slot.
    push    rcx
    push    rdx
    mov     rdi, [rdx + SYMBOL_name]
    mov     rsi, r12
    extern  str_cmp
    call    str_cmp
    pop     rdx
    pop     rcx

    test    rax, rax
    jz      .found
    
    inc     rcx
    jmp     .probe
    jmp     .not_found

.found:
    ; rdx already points to the symbol
    xor     rax, rax
    pop     r12
    pop     rbx
    epilogue

.not_found:
    mov     rax, EXIT_UNDEF_SYMBOL
    pop     r12
    pop     rbx
    epilogue
