;
; ============================================
; File     : src/core/arena.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

%define AMD64_SYS_MADVISE      28
%define MADV_DONTDUMP          16          ; madvise: leave out of a core dump

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
;   - no individual free â€” checkpoint/rollback mechanisms available
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

    ; (zeroed already: the arena is mapped fresh, and arena_reset /
    ; arena_rollback zero what they hand back - clearing every block here
    ; cost a rep stosq per token)

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
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi               ; save arena pointer
    mov     r12, rsi               ; save source string pointer
    mov     r13, rdx               ; save string length

    ; allocate length + 1 for null terminator
    mov     rsi, r13
    add     rsi, 1
    call    arena_alloc
    test    rax, rax
    jnz     .fail

    ; copy string bytes
    mov     rdi, rdx               ; destination = allocated block
    mov     rsi, r12               ; source = original string
    mov     rcx, r13               ; count = length
    rep movsb

    ; write null terminator
    mov     byte [rdi], 0

    ; rdx already points to allocated block from arena_alloc
    xor     rax, rax               ; rax = EXIT_OK
    pop     r13
    pop     r12
    pop     rbx
    ret

.fail:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- arena_reset -------------------------
;
; arena_reset
; Resets the arena to its initial state without unmapping memory.
; All previously allocated memory becomes invalid immediately.
; Use at the start of a new compilation pass to reuse the arena.
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : rcx
;
global arena_reset
arena_reset:
    ; validate tag
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena

    ; zero what was used (arena_alloc hands out zeroed memory without
    ; clearing it), then reset ptr to base
    push    rdi
    mov     rcx, [rdi + ARENA_ptr]
    mov     rax, [rdi + ARENA_base]
    sub     rcx, rax
    mov     rdi, rax
    xor     eax, eax
    cld
    rep     stosb
    pop     rdi
    mov     rcx, [rdi + ARENA_base]
    mov     [rdi + ARENA_ptr], rcx

    xor     rax, rax               ; rax = EXIT_OK
    ret

.bad_arena:
    mov     rax, EXIT_INTERNAL
    ret

; ---- arena_destroy -----------------------
;
; arena_destroy
; Unmaps the arena memory and zeroes the Arena struct.
; Call once at utasm shutdown.
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_INTERNAL
; Clobbers : rcx, rdx, r8
;
global arena_destroy
arena_destroy:
    push    rbx
    mov     rbx, rdi               ; save arena pointer

    ; validate tag
    cmp     byte [rbx + ARENA_tag], TAG_ARENA
    jne     .bad_arena

    ; compute size = end - base
    mov     rdi, [rbx + ARENA_base] ; addr = base
    mov     rsi, [rbx + ARENA_end]
    sub     rsi, rdi               ; length = end - base

    ; munmap(base, size)
    mov     rax, AMD64_SYS_MUNMAP
    syscall

    ; zero the Arena struct regardless of munmap result
    mov     rdi, rbx
    mov     rsi, ARENA_SIZE
    call    arena_zero

    xor     rax, rax               ; rax = EXIT_OK
    pop     rbx
    ret

.bad_arena:
    mov     rax, EXIT_INTERNAL
    pop     rbx
    ret

; ---- arena_used --------------------------
;
; arena_used
; Returns the number of bytes currently allocated in the arena.
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;              rdx = bytes used (0 if error)
; Clobbers : rcx
;
global arena_used
arena_used:
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena

    mov     rdx, [rdi + ARENA_ptr]
    sub     rdx, [rdi + ARENA_base] ; used = ptr - base

    xor     rax, rax
    ret

.bad_arena:
    mov     rax, EXIT_INTERNAL
    xor     rdx, rdx
    ret

; ---- arena_remaining ---------------------
;
; arena_remaining
; Returns the number of bytes still available in the arena.
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;              rdx = bytes remaining (0 if error)
; Clobbers : rcx
;
global arena_remaining
arena_remaining:
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena

    mov     rdx, [rdi + ARENA_end]
    sub     rdx, [rdi + ARENA_ptr] ; remaining = end - ptr

    xor     rax, rax
    ret

.bad_arena:
    mov     rax, EXIT_INTERNAL
    xor     rdx, rdx
    ret

; ---- arena_checkpoint --------------------
;
; arena_checkpoint
; Returns the current allocation pointer.
; Use with arena_rollback to free temporary allocations.
; Input    : rdi = pointer to Arena struct
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;              rdx = current pointer (checkpoint)
;
global arena_checkpoint
arena_checkpoint:
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena
    mov     rdx, [rdi + ARENA_ptr]
    xor     rax, rax
    ret
.bad_arena:
    mov     rax, EXIT_INTERNAL
    ret

; ---- arena_rollback ----------------------
;
; arena_rollback
; Restores the allocation pointer to a previous checkpoint.
; All memory allocated after the checkpoint becomes invalid.
; Input    : rdi = pointer to Arena struct
;              rsi = pointer to restore to (from arena_checkpoint)
; Output   : rax = EXIT_OK or EXIT_INTERNAL
;
global arena_rollback
arena_rollback:
    cmp     byte [rdi + ARENA_tag], TAG_ARENA
    jne     .bad_arena
    
    ; Safety check: rsi must be within [base, ptr]
    mov     rax, [rdi + ARENA_base]
    cmp     rsi, rax
    jb      .invalid_rollback
    mov     rax, [rdi + ARENA_ptr]
    cmp     rsi, rax
    ja      .invalid_rollback

    ; zero what is handed back (arena_alloc does not clear)
    push    rdi
    mov     rcx, rax
    sub     rcx, rsi
    mov     rdi, rsi
    xor     eax, eax
    cld
    rep     stosb
    pop     rdi
    mov     [rdi + ARENA_ptr], rsi
    xor     rax, rax
    ret

.invalid_rollback:
    mov     rax, EXIT_INTERNAL
    ret
.bad_arena:
    mov     rax, EXIT_INTERNAL
    ret

; ---- arena_zero (internal) ---------------
;
; arena_zero
; Zeroes a region of memory. Internal helper only.
; Input    : rdi = pointer to region
;             rsi = size in bytes
; Output   : none
; Clobbers : rax, rcx, rdi
;
arena_zero:
    xor     rax, rax               ; zero value
    mov     rcx, rsi               ; count
    rep stosb                      ; zero rcx bytes at rdi
    ret

[SECTION .data]
msg_arena_alloc_trace: db "DEBUG: Arena alloc size: "
msg_arena_alloc_size:  db "0", 10, 0
