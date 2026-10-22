;
; ============================================
; File     : src/lib/vec.s
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
; VEC — GROWABLE ARRAY
; ============================================================================
; A dynamic array of fixed-size elements backed by the arena allocator.
; The Vec header itself (VEC_SIZE bytes) is caller-owned: embed it in a
; struct, put it in .bss, or arena_alloc_struct it.
;
; Growth: capacity doubles (minimum 8). Because arenas cannot free, the old
; buffer is abandoned on growth — reserve up front when the size is known.
;
; Pointers returned by vec_push are invalidated by any later
; growth. Store indices, not pointers, across pushes.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx
;   return: rax = EXIT_OK or error code, rdx = result
;   callee saved: rbx, r12-r15, rbp
;
; Errors:
;   EXIT_INTERNAL  - header is not a Vec (bad tag) / bad arguments
;   EXIT_OOM       - arena exhausted or size computation overflowed

%define VEC_MIN_CAP     8

extern arena_alloc
extern mem_copy

[SECTION .text]

; ---- vec_init ---------------------------
;
; vec_init
; Initializes a Vec header, optionally reserving initial capacity.
; Input    : rdi = pointer to Vec header (VEC_SIZE bytes)
;             rsi = pointer to Arena
;             rdx = element size in bytes (1 .. 2^32-1)
;             rcx = initial capacity in elements (0 = allocate lazily)
; Output   : rax = EXIT_OK, EXIT_INTERNAL or EXIT_OOM
;              rdx = pointer to Vec header
; Clobbers : rcx, rsi, rdi, r8, r9, r10, r11
;
global vec_init
vec_init:
    test    rdi, rdi
    jz      .bad_args
    test    rsi, rsi
    jz      .bad_args
    test    rdx, rdx
    jz      .bad_args
    mov     rax, 0xFFFFFFFF
    cmp     rdx, rax
    ja      .bad_args

    mov     byte  [rdi + VEC_tag], TAG_VEC
    mov     dword [rdi + VEC_elem_size], edx
    mov     qword [rdi + VEC_data], 0
    mov     qword [rdi + VEC_len], 0
    mov     qword [rdi + VEC_cap], 0
    mov     [rdi + VEC_arena], rsi

    test    rcx, rcx
    jz      .ok
    mov     rsi, rcx
    jmp     vec_reserve            ; tail call: returns rax/rdx for us

.ok:
    xor     eax, eax
    mov     rdx, rdi
    ret

.bad_args:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret

; ---- vec_reserve ------------------------
;
; vec_reserve
; Ensures capacity for at least rsi elements. Existing contents are kept.
; New capacity = max(min_cap, 2 * cap, VEC_MIN_CAP).
; Input    : rdi = pointer to Vec
;             rsi = minimum capacity in elements
; Output   : rax = EXIT_OK, EXIT_INTERNAL or EXIT_OOM
;              rdx = pointer to Vec
; Clobbers : rcx, rsi, rdi, r8, r9, r10, r11
;
global vec_reserve
vec_reserve:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                       ; rbx = vec

    cmp     byte [rbx + VEC_tag], TAG_VEC
    jne     .bad_vec

    mov     rax, [rbx + VEC_cap]
    cmp     rsi, rax
    jbe     .ok                            ; already big enough

    ; r12 = new capacity = max(min_cap, 2*cap, VEC_MIN_CAP)
    mov     r12, rsi
    add     rax, rax                       ; 2 * cap
    jc      .skip_double                   ; doubling overflowed: use min_cap
    cmp     rax, r12
    cmova   r12, rax
.skip_double:
    mov     eax, VEC_MIN_CAP
    cmp     rax, r12
    cmova   r12, rax

    ; byte size = new_cap * elem_size (unsigned, overflow -> OOM)
    mov     eax, dword [rbx + VEC_elem_size]
    mul     r12                            ; rdx:rax = cap * elem_size
    test    rdx, rdx
    jnz     .oom

    mov     rdi, [rbx + VEC_arena]
    mov     rsi, rax
    call    arena_alloc                    ; rdx = new zeroed buffer
    test    rax, rax
    jnz     .fail                          ; propagate arena error
    mov     r13, rdx                       ; r13 = new buffer

    ; copy existing elements
    mov     rcx, [rbx + VEC_len]
    test    rcx, rcx
    jz      .install
    mov     eax, dword [rbx + VEC_elem_size]
    mul     rcx                            ; cannot overflow: len <= old cap
    mov     rdx, rax
    mov     rdi, r13
    mov     rsi, [rbx + VEC_data]
    call    mem_copy

.install:
    mov     [rbx + VEC_data], r13
    mov     [rbx + VEC_cap], r12

.ok:
    xor     eax, eax
    mov     rdx, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

.oom:
    mov     eax, EXIT_OOM
.fail:
    xor     edx, edx
    pop     r13
    pop     r12
    pop     rbx
    ret

.bad_vec:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- vec_push ---------------------------
;
; vec_push
; Appends one element, copied from rsi. If rsi is NULL the new element
; is zero-filled.
; Input    : rdi = pointer to Vec
;             rsi = pointer to source element, or NULL
; Output   : rax = EXIT_OK, EXIT_INTERNAL or EXIT_OOM
;              rdx = pointer to the stored element inside the Vec
; Clobbers : rcx, rsi, rdi, r8, r9, r10, r11
;
global vec_push
vec_push:
    push    rbx
    push    r12
    mov     rbx, rdi                       ; rbx = vec
    mov     r12, rsi                       ; r12 = source element

    cmp     byte [rbx + VEC_tag], TAG_VEC
    jne     .bad_vec

    mov     rax, [rbx + VEC_len]
    cmp     rax, [rbx + VEC_cap]
    jb      .have_room

    lea     rsi, [rax + 1]
    mov     rdi, rbx
    call    vec_reserve
    test    rax, rax
    jnz     .fail

.have_room:
    ; rdi = &data[len]
    mov     eax, dword [rbx + VEC_elem_size]
    mov     rcx, rax                       ; rcx = elem_size (copy count)
    mul     qword [rbx + VEC_len]
    mov     rdi, [rbx + VEC_data]
    add     rdi, rax
    mov     r8, rdi                        ; r8 = slot pointer (result)

    test    r12, r12
    jz      .zero_fill
    mov     rsi, r12
    cld
    rep movsb
    jmp     .stored

.zero_fill:
    xor     eax, eax
    cld
    rep stosb                              ; slot may hold a popped element

.stored:
    inc     qword [rbx + VEC_len]
    xor     eax, eax
    mov     rdx, r8
    pop     r12
    pop     rbx
    ret

.bad_vec:
    mov     eax, EXIT_INTERNAL
.fail:
    xor     edx, edx
    pop     r12
    pop     rbx
    ret
