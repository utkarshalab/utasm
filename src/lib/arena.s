;
; ============================================
; File     : src/lib/arena.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

%define AMD64_SYS_MADVISE      28
%define MADV_DONTDUMP          16          ; madvise: leave out of a core dump
%define MADV_HUGEPAGE          14          ; madvise: back it with 2 MB pages

DEFAULT REL

; ============================================================================
; ARENA ALLOCATOR
; ============================================================================
; Bump allocator for the entire utasm compilation pass.
; One arena is created at startup and lives until utasm exits.
; All tokens, symbols, strings, and structs are allocated here.
;
; How it works:
;   - mmap reserves a large contiguous block of memory upfront
;   - every allocation just moves a pointer forward
;   - nothing is freed: an allocation lasts until utasm exits
;   - no fragmentation, no use-after-free, no double-free
;
; This is our Rust-style memory discipline in assembly.
; Think of it as a Region / Bump allocator / LinearAllocator.
;
; Allocation strategy:
;   - all allocations are aligned to 8 bytes
;   - if arena is full, utasm exits with EXIT_OOM
;   - no growing â€” size is fixed at arena_init time
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result pointer
;   callee saved: rbx, r12-r15, rbp

[SECTION .text]

; ---- arena_init -------------------------
;
; arena_init
; Allocates a fresh arena of the requested size using mmap.
; Initializes the Arena struct at the beginning of the mapping.
; Input    : rdi = pointer to Arena struct
;             rsi = size in bytes to reserve
; Output   : rax = EXIT_OK or EXIT_OOM
;              rdx = pointer to Arena struct (same as rdi)
; Clobbers : rcx, r8, r9, r10, r11
;
global arena_init
arena_init:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                ; rbx = arena struct pointer
    mov     r12, rsi                ; r12 = requested size

    ; align size up to PAGE_SIZE boundary
    mov     rax, PAGE_SIZE
    sub     rax, 1                  ; rax = 0xFFF
    add     rsi, rax               ; size + 4095
    jc      .mmap_failed           ; overflow
    not     rax                    ; rax = ~0xFFF
    and     rsi, rax               ; page aligned size
    mov     r12, rsi

    ; mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
    xor     rdi, rdi               ; addr = NULL
    mov     rsi, r12               ; length = aligned size
    mov     rdx, PROT_READ         
    or      rdx, PROT_WRITE        ; prot = PROT_READ | PROT_WRITE
    mov     r10, MAP_PRIVATE
    or      r10, MAP_ANONYMOUS     ; flags = MAP_PRIVATE | MAP_ANONYMOUS, and
    or      r10, MAP_NORESERVE     ; pages only taken as they are touched
    mov     r8,  -1                ; fd = -1
    xor     r9,  r9                ; offset = 0
    mov     rax, AMD64_SYS_MMAP
    syscall

    ; check mmap result — returns -1 to -4095 on failure
    cmp     rax, -4095
    jae     .mmap_failed

    ; left out of a core dump: the reservation is gigabytes of pages never
    ; touched, which a crash handler may write out in full (WSL's did:
    ; several GB per crash)
    push    rax
    mov     rdi, rax
    mov     rsi, r12
    mov     edx, MADV_DONTDUMP
    mov     eax, AMD64_SYS_MADVISE
    syscall
    ; in 2 MB pages where the kernel has them (transparent huge pages):
    ; a fault per 2 MB, not per 4 KB - most of a large source's time was
    ; the kernel's, taking tens of thousands of page faults
    mov     rdi, [rsp]
    mov     rsi, r12
    mov     edx, MADV_HUGEPAGE
    mov     eax, AMD64_SYS_MADVISE
    syscall
    pop     rax

    ; write TAG_ARENA at offset 0
    mov     byte [rbx + ARENA_tag], TAG_ARENA

    ; base = mmap result
    mov     [rbx + ARENA_base], rax

    ; ptr = base (next free byte starts at base)
    mov     [rbx + ARENA_ptr], rax

    ; end = base + size
    add     rax, r12
    mov     [rbx + ARENA_end], rax

    ; return OK
    xor     rax, rax               ; rax = EXIT_OK
    mov     rdx, rbx               ; rdx = arena pointer
    pop     r12
    pop     rbx
    epilogue
    ret

.mmap_failed:
    mov     rax, EXIT_OOM
    xor     rdx, rdx               ; rdx = NULL
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- mem_reserve -------------------------
;
; mem_reserve
; A large zeroed table outside the arena: address space reserved with
; MAP_NORESERVE, pages committed only as they are touched (the symbol
; table, its hash, the relocations).
; Input    : rsi = size in bytes
; Output   : rax = EXIT_OK or EXIT_OOM, rdx = the memory
; Clobbers : rcx, r8-r11
;
global mem_reserve
mem_reserve:
    push    rdi
    xor     edi, edi
    add     rsi, PAGE_SIZE - 1
    and     rsi, ~(PAGE_SIZE - 1)
    mov     edx, PROT_READ | PROT_WRITE
    mov     r10d, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    mov     eax, AMD64_SYS_MMAP
    syscall
    cmp     rax, -4095
    jae     .fail_pop
    ; not in a core dump either (arena_init)
    push    rax
    mov     rdi, rax                       ; (rsi: the size, kept by syscall)
    mov     edx, MADV_DONTDUMP
    mov     eax, AMD64_SYS_MADVISE
    syscall
    mov     rdi, [rsp]                     ; 2 MB pages too (arena_init)
    mov     edx, MADV_HUGEPAGE
    mov     eax, AMD64_SYS_MADVISE
    syscall
    pop     rdx
    pop     rdi
    xor     eax, eax
    ret
.fail_pop:
    pop     rdi
.fail:
    mov     eax, EXIT_OOM
    xor     edx, edx
    ret

; ---- arena_alloc -------------------------
;
; arena_alloc
; Allocates n bytes from the arena, aligned to 8 bytes.
; Never returns unaligned memory.
; Input    : rdi = pointer to Arena struct
;             rsi = number of bytes to allocate
; Output   : rax = EXIT_OK or EXIT_OOM
;              rdx = pointer to allocated memory (zeroed)
; Clobbers : rcx, r8
;
global arena_alloc
arena_alloc:
    push    rbx
    mov     rbx, rdi               ; rbx = arena pointer (safe across zeroing)

    ; validate tag
    cmp     byte [rbx + ARENA_tag], TAG_ARENA
    jne     .bad_arena

    ; align requested size up to 8 bytes
    mov     rcx, rsi
    add     rcx, 7
    and     rcx, ~7                ; rcx = aligned size

    ; load current ptr and end
    mov     rax, [rbx + ARENA_ptr] ; rax = current free pointer
    mov     r8,  [rbx + ARENA_end] ; r8  = end of arena

    ; check if enough space remains
    mov     rdx, rax
    add     rdx, rcx               ; rdx = new ptr after alloc
    jc      .out_of_memory         ; carry = integer overflow
    cmp     rdx, r8
    ja      .out_of_memory         ; new ptr > end = no space

    ; (zeroed already: the arena is mapped fresh and nothing is handed
    ; out twice - clearing every block here cost a rep stosq per token)

    ; advance arena ptr
    mov     rdx, rax               ; rdx = result pointer
    add     rax, rcx               ; rax = next free pointer
    mov     [rbx + ARENA_ptr], rax ; update arena state

    xor     rax, rax               ; rax = EXIT_OK
    pop     rbx
    ret

.out_of_memory:
    mov     rax, EXIT_OOM
    xor     rdx, rdx
    pop     rbx
    ret

.bad_arena:
    mov     rax, EXIT_INTERNAL
    xor     rdx, rdx
    pop     rbx
    ret

; ---- arena_alloc_struct ------------------
;
; arena_alloc_struct
; Allocates exactly n bytes and writes a type tag at offset 0.
; Convenience wrapper around arena_alloc for typed structs.
; Input    : rdi = pointer to Arena struct
;             rsi = number of bytes to allocate
;             rdx = TAG_* value to write at offset 0
; Output   : rax = EXIT_OK or EXIT_OOM
;              rdx = pointer to allocated struct
; Clobbers : rcx, r8, r9
;
global arena_alloc_struct
arena_alloc_struct:
    push    rbx
    mov     rbx, rdx               ; save tag value

    ; allocate
    call    arena_alloc
    test    rax, rax
    jnz     .fail

    ; write tag at offset 0
    mov     byte [rdx], bl         ; tag = saved tag value

    xor     rax, rax               ; rax = EXIT_OK
    pop     rbx
    ret

.fail:
    pop     rbx
    ret

; ---- arena_alloc_string ------------------
;
; arena_alloc_string
; Copies a string of known length into the arena.
; Appends a null terminator.
; Input    : rdi = pointer to Arena struct
;             rsi = pointer to source string
;             rdx = string length in bytes (not including null)
; Output   : rax = EXIT_OK or EXIT_OOM
;              rdx = pointer to null-terminated copy in arena
; Clobbers : rcx, r8, r9, r10
;
global arena_alloc_string
arena_alloc_string:
    ; arena_alloc's work in line (every identifier and number token comes
    ; here): length + 1 in 8s, from the arena's free pointer
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena
    lea     rcx, [rdx + 8]
    and     rcx, ~7
    mov     rax, [rdi + ARENA_ptr]
    add     rcx, rax
    jc      .out_of_memory
    cmp     rcx, [rdi + ARENA_end]
    ja      .out_of_memory
    mov     [rdi + ARENA_ptr], rcx

    ; copy string bytes: a loop for a token's few, which rep movsb's start
    ; costs more than
    mov     rdi, rax               ; destination = allocated block
    mov     rcx, rdx               ; count = length
    mov     rdx, rax               ; the result
    cmp     rcx, 32
    jae     .long
    test    rcx, rcx
    jz      .terminate
.short:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .short
    jmp     .terminate
.long:
    rep movsb

.terminate:
    ; write null terminator (the rest of the block is zero already)
    mov     byte [rdi], 0
    xor     eax, eax               ; rax = EXIT_OK
    ret

.out_of_memory:
    mov     eax, EXIT_OOM
    xor     edx, edx
    ret

.bad_arena:
    mov     eax, EXIT_INTERNAL
    xor     edx, edx
    ret
