;
; ============================================
; File     : src/core/symbol.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

DEFAULT REL

extern arena_alloc

; ============================================================================
; SYMBOL TABLE (Hash Table Implementation)
; ============================================================================
; Manages the registration and lookup of labels, constants, and macros.
; Implements a high-performance FNV-1a 64-bit hash table with quadratic probing.
; ============================================================================

; The hash starts at SYM_HASH0 slots and doubles whenever it is half full,
; up to MAX_SYMBOL. Its address space is reserved at the full size, but
; every name hashes to a random slot: at the full size from the start, the
; few hundred predefined macros alone touched as many pages, most of an
; empty source's time.
%define SYM_HASH0       (1 << 14)

extern undef_name

[SECTION .bss]
global sym_defseq
sym_defseq:     resd 1              ; symbols defined so far (SYMBOL_defseq)
sym_hmask:      resq 1              ; the hash's slots, less one

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
    mov     qword [rel sym_hmask], SYM_HASH0 - 1

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
    ; the order symbols are defined in (-f win64 writes them so)
    inc     dword [rel sym_defseq]
    mov     eax, [rel sym_defseq]
    mov     [r13 + SYMBOL_defseq], eax
    mov     rsi, [r13 + SYMBOL_name]
    call    symbol_hash
    mov     [r13 + SYMBOL_hash], eax

    ; 3. Index in Hash Table (Quadratic Probing), twice the size first
    ;    when this one would fill more than half of it
    mov     eax, [rbx + ASMCTX_symcount]
    lea     rax, [rax * 2 + 1]
    cmp     rax, [rel sym_hmask]
    jbe     .room
    cmp     qword [rel sym_hmask], MAX_SYMBOL - 1
    jae     .room
    call    symbol_grow
.room:
    mov     rdi, r13
    call    symbol_insert
    test    rax, rax
    jnz     .done                  ; EXIT_SYMBOL_RANGE

    ; 4. Increment count
    inc     dword [rbx + ASMCTX_symcount]
    mov     rdx, r13               ; Return pointer to stored symbol
    xor     rax, rax

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- symbol_insert ----------------------
; rbx = AsmCtx, rdi = a symbol of the linear table (SYMBOL_hash set) -> its
; slot in the hash, the first empty one of its probe sequence. rax =
; EXIT_OK, or EXIT_SYMBOL_RANGE with every slot taken.
; Clobbers rcx, rdx, r10, r11
symbol_insert:
    mov     edx, [rdi + SYMBOL_hash]
    mov     r10, [rel sym_hmask]
    mov     r11, [rbx + ASMCTX_symhash]
    xor     ecx, ecx               ; i = 0
.probe:
    cmp     rcx, r10
    ja      .full
    ; pos = (hash + (i*i + i)/2) & mask
    mov     rax, rcx
    imul    rax, rcx
    add     rax, rcx
    shr     rax, 1
    add     rax, rdx
    and     rax, r10
    cmp     qword [r11 + rax * 8], 0
    je      .slot
    inc     rcx
    jmp     .probe
.slot:
    mov     [r11 + rax * 8], rdi
    xor     eax, eax
    ret
.full:
    mov     eax, EXIT_SYMBOL_RANGE
    ret

; ---- symbol_grow ------------------------
; rbx = AsmCtx: the hash at twice its size, every symbol of the linear
; table put in it again - none is ever taken out of that, so nothing is
; copied. An %undef'd entry (named undef_name) is left out: nothing finds
; it, and the hundreds %clear makes would all share one probe sequence.
; Clobbers rax, rcx, rdx, rdi, r10, r11
symbol_grow:
    push    r12
    push    r13
    mov     rdi, [rbx + ASMCTX_symhash]
    mov     rcx, [rel sym_hmask]
    inc     rcx
    xor     eax, eax
    rep stosq
    mov     rax, [rel sym_hmask]
    lea     rax, [rax * 2 + 1]
    mov     [rel sym_hmask], rax
    mov     r12, [rbx + ASMCTX_symtab]
    mov     r13d, [rbx + ASMCTX_symcount]
.next:
    test    r13d, r13d
    jz      .done
    lea     rax, [rel undef_name]
    cmp     [r12 + SYMBOL_name], rax
    je      .skip
    mov     rdi, r12
    call    symbol_insert          ; (half full at most: always a slot)
.skip:
    add     r12, SYMBOL_SIZE
    dec     r13d
    jmp     .next
.done:
    pop     r13
    pop     r12
    ret

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
    
    mov     r11, [rbx + ASMCTX_symhash]
    mov     rcx, 0                 ; i = 0 (iteration counter)
.probe:
    cmp     rcx, [rel sym_hmask]
    ja      .not_found             ; every slot looked at
    
    ; pos = (hash + (i*i + i)/2) & mask (the hash's size now)
    mov     rax, rcx
    imul    rax, rcx               ; i*i
    add     rax, rcx               ; i*i + i
    shr     rax, 1                 ; (i*i + i)/2
    add     rax, r10               ; hash + ...
    and     rax, [rel sym_hmask]
    
    mov     rdx, [r11 + rax * 8]
    test    rdx, rdx
    jz      .not_found
    cmp     [rdx + SYMBOL_hash], r10d
    jne     .other                 ; another name
    
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
.other:
    inc     rcx
    jmp     .probe

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
