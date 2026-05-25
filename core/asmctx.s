;
; ============================================================================
; File        : src/core/asmctx.s
; Project     : utasm
; Description : Assembly Context and Section Management.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

extern io_mmap
extern io_munmap
extern arena_alloc_struct
extern str_cmp

extern io_mmap
extern io_munmap
extern arena_alloc_struct
extern str_cmp

[SECTION .text]

;*
; * [asm_ctx_emit_byte]
; * Purpose: Appends a single byte to the active section's buffer.
; * Input:
; *   RDI: Pointer to AsmCtx
; *   RSI: Byte to emit (SIL)
; ;
global asmctx_emit_byte
asmctx_emit_byte:
global asm_ctx_emit_byte
asm_ctx_emit_byte:
    prologue
    push    rbx
    push    r12
    
    mov     rbx, rdi               ; RBX = AsmCtx
    
    ; 1. Get current section
    mov     r12, [rbx + ASMCTX_curr_sec]
    test    r12, r12
    jz      .try_first_section
    
    jmp     .check_cap

.try_first_section:
    mov     r12, [rbx + ASMCTX_sections]
    mov     r12, [r12]             ; Get first SECTION*
    test    r12, r12
    jz      .no_section

.check_cap:
    ; 2. Check capacity
    mov     rax, [r12 + SECTION_size]
    cmp     rax, [r12 + SECTION_cap]
    jae     .grow_section
    
.write:
    mov     rdx, [r12 + SECTION_data]
    add     rdx, rax
    mov     [rdx], sil
    
    inc     rax
    mov     [r12 + SECTION_size], rax
    
    pop     r12
    pop     rbx
    epilogue

.no_section:
    mov     rax, EXIT_INTERNAL
    pop     r12
    pop     rbx
    epilogue

.grow_section:
    ; 1. Calculate new capacity (current * 2)
    mov     rax, [r12 + SECTION_cap]
    shl     rax, 1
    IF rax, e, 0
        mov rax, 65536
    ENDIF ; Default 64KB
    mov     r13, rax               ; r13 = new cap
    
    ; 2. Map new buffer
    ; io_mmap(NULL, size, PROT_RW, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    xor     rdi, rdi
    mov     rsi, r13
    mov     rdx, (PROT_READ | PROT_WRITE)
    mov     rcx, (MAP_PRIVATE | MAP_ANONYMOUS)
    mov     r8, -1
    xor     r9, r9
    call    io_mmap
    IF rax, ne, EXIT_OK
        jmp .error
    ENDIF
    mov     r14, rdx               ; r14 = new buffer ptr
    
    ; 3. Copy old data
    mov     rdi, r14
    mov     rsi, [r12 + SECTION_data]
    mov     rcx, [r12 + SECTION_size]
    rep movsb
    
    ; 4. Unmap old buffer
    mov     rdi, [r12 + SECTION_data]
    mov     rsi, [r12 + SECTION_cap]
    call    io_munmap
    
    ; 5. Update section struct
    mov     [r12 + SECTION_data], r14
    mov     [r12 + SECTION_cap], r13
    
    jmp     .write

.error:
    mov     rax, EXIT_INTERNAL
.done:
    pop     r12
    pop     rbx
    epilogue

;*
; * [asm_ctx_create_section]
; * Purpose: Creates a new section and adds it to the context.
; ;
;*
; * [asm_ctx_create_section]
; * Purpose: Creates a new section and adds it to the context.
; * Input:
; *   RDI: Pointer to AsmCtx
; *   RSI: Section Name (Pointer)
; *   RDX: Section Type (SEC_*)
; * Output:
; *   RAX: EXIT_OK or error
; *   RDX: Pointer to new SECTION
; ;
global asmctx_create_section
asmctx_create_section:
global asm_ctx_create_section
asm_ctx_create_section:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; RBX = AsmCtx
    mov     r12, rsi               ; R12 = Name
    mov     r13, rdx               ; R13 = Type
    
    ; 1. Allocate SECTION struct from Arena
    mov     rdi, [rbx + ASMCTX_arena]
    mov     rsi, SECTION_SIZE
    mov     rdx, TAG_SECTION
    call    arena_alloc_struct
    check_err
    mov     r14, rdx               ; R14 = SECTION*
    
    ; 2. Initialize metadata
    mov     [r14 + SECTION_name], r12
    mov     byte [r14 + SECTION_type], r13b
    mov     qword [r14 + SECTION_cap], 65536 ; Initial 64KB
    
    ; 3. Allocate initial buffer
    xor     rdi, rdi
    mov     rsi, 65536
    mov     rdx, (PROT_READ | PROT_WRITE)
    mov     rcx, (MAP_PRIVATE | MAP_ANONYMOUS)
    mov     r8, -1
    xor     r9, r9
    call    io_mmap
    check_err
    mov     [r14 + SECTION_data], rdx
    
    ; 4. Add to AsmCtx section array
    movzx   ecx, word [rbx + ASMCTX_seccount]
    IF ecx, ge, MAX_SECTIONS
        mov     rax, EXIT_SECTION_OVERLAP
        jmp     .error
    ENDIF
    
    lea     eax, [ecx + 1]
    mov     [r14 + SECTION_index], eax
    
    mov     rax, [rbx + ASMCTX_sections]
    mov     [rax + rcx*8], r14
    inc     word [rbx + ASMCTX_seccount]
    
    mov     rax, EXIT_OK
    mov     rdx, r14
    jmp     .done

.error:
    ; A97: Unmap the buffer to prevent memory leak on overflow
    mov     rdi, [r14 + SECTION_data]
    mov     rsi, [r14 + SECTION_cap]
    extern  io_munmap
    call    io_munmap
    mov     rax, EXIT_SECTION_OVERLAP
    
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [asm_ctx_emit_dword]
; * Purpose: Appends 4 bytes to the active section's buffer.
; ;
global asmctx_emit_dword
asmctx_emit_dword:
global asm_ctx_emit_dword
asm_ctx_emit_dword:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi               ; the dword
    
    ; Emit 4 bytes
    mov     rdi, rbx
    mov     rsi, r12
    call    asm_ctx_emit_byte
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, 8
    call    asm_ctx_emit_byte
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, 16
    call    asm_ctx_emit_byte
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, 24
    call    asm_ctx_emit_byte
    
    pop     r12
    pop     rbx
    epilogue


;*
; * [asm_ctx_emit_word]
; * Purpose: Appends 2 bytes (16-bit) to the active section.
; ;
global asmctx_emit_word
asmctx_emit_word:
global asm_ctx_emit_word
asm_ctx_emit_word:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    
    mov     rdi, rbx
    mov     rsi, r12
    call    asm_ctx_emit_byte
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, 8
    call    asm_ctx_emit_byte
    
    pop     r12
    pop     rbx
    epilogue

;*
; * [asm_ctx_emit_qword]
; * Purpose: Appends 8 bytes (64-bit) to the active section.
; ;
global asmctx_emit_qword
asmctx_emit_qword:
global asm_ctx_emit_qword
asm_ctx_emit_qword:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    
    mov     rdi, rbx
    mov     rsi, r12
    call    asm_ctx_emit_dword
    mov     rdi, rbx
    mov     rsi, r12
    shr     rsi, 32
    call    asm_ctx_emit_dword
    
    pop     r12
    pop     rbx
    epilogue

;*
; * [asm_ctx_emit_string]
; * Purpose: Appends a null-terminated string to the active section.
; * Input:
; *   RDI: Pointer to AsmCtx
; *   RSI: Pointer to null-terminated string
; ;
global asmctx_emit_string
asmctx_emit_string:
global asm_ctx_emit_string
asm_ctx_emit_string:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    
.loop:
    movzx   rsi, byte [r12]
    test    sil, sil
    jz      .done
    mov     rdi, rbx
    call    asm_ctx_emit_byte
    inc     r12
    jmp     .loop
    
.done:
    pop     r12
    pop     rbx
    epilogue

;*
; * [asmctx_find_section]
; * Purpose: Finds a section by name string.
; * Input:
; *   RDI: Pointer to AsmCtx
; *   RSI: Section Name String
; * Output:
; *   RAX: EXIT_OK (found) or EXIT_ERROR
; *   RDX: Pointer to SECTION
; ;
global asmctx_find_section
asmctx_find_section:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi
    mov     r12, rsi
    
    mov     r13, [rbx + ASMCTX_sections]
    movzx   ecx, word [rbx + ASMCTX_seccount]
    xor     rax, rax
    
.loop:
    test    ecx, ecx
    jz      .not_found
    
    mov     r8, [r13 + rax*8]      ; R8 = SECTION*
    push    rax
    push    rcx
    mov     rdi, [r8 + SECTION_name]
    mov     rsi, r12
    extern  str_cmp
    call    str_cmp
    pop     rcx
    pop     rax
    test    rax, rax
    jz      .found
    
    inc     rax
    dec     ecx
    jmp     .loop
    
.found:
    mov     rdx, r8
    xor     rax, rax
    jmp     .done_find
    
.not_found:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx

.done_find:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [asm_ctx_align]
; * Aligns the current section to the specified boundary.
; * Input:
; *   RDI: AsmCtx*
; *   RSI: Alignment (Power of 2)
; ;
global asm_ctx_align
asm_ctx_align:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi
    mov     r12, rsi               ; r12 = alignment
    
    ; 1. Get current section
    mov     r13, [rbx + ASMCTX_curr_sec]
    test    r13, r13
    jz      .done
    
    ; Safety: ignore zero or non-power-of-2 alignment (caller should have validated)
    test    r12, r12
    jz      .done
    ; A93: Industrial sanity limit (Max 64KB alignment)
    IF r12, g, 0x10000
        jmp .done
    ENDIF
    mov     rax, r12
    dec     rax
    test    rax, r12               ; (n & (n-1)) == 0
    jnz     .done
    
    ; 2. Update Section-wide maximum alignment (A85)
    cmp     r12, [r13 + SECTION_align]
    jbe     .calc_padding
    mov     [r13 + SECTION_align], r12
    
.calc_padding:
    ; 3. Calculate padding
    mov     rax, [r13 + SECTION_size]
    mov     rcx, r12
    dec     rcx                    ; mask = align - 1
    
    mov     rdx, rax
    and     rdx, rcx               ; offset = size & mask
    jz      .done                  ; already aligned
    
    sub     r12, rdx               ; padding = align - offset
    
    ; 3. Determine fill byte
    xor     r14, r14               ; Default: Zero-fill (safe for data/bss)
    
    mov     al, byte [r13 + SECTION_type]
    cmp     al, SEC_TEXT
    jne     .fill_loop
    
    ; Architecturally-aware NOP for .text sections
    mov     al, [rbx + ASMCTX_target]
    IF al, e, TARGET_AMD64
        mov     r14b, 0x90     ; NOP (1 byte)
    ELSEIF al, e, TARGET_AARCH64
        ; AArch64 NOP is 0xD503201F. 
        ; Since we emit byte-by-byte, we'll use a special loop if needed,
        ; but for now, 0x00 is safer than a random byte.
        ; Let's use 0x1F and ensure it's handled as part of a 4-byte NOP.
        mov     r14b, 0x00     ; Default to 0 for now until 4-byte NOP loop implemented
    ELSEIF al, e, TARGET_RISCV64
        mov     r14b, 0x13     ; Part of NOP (addi x0, x0, 0)
        or      r14b, 0x00
    ENDIF
    
.fill_loop:
    mov     rdi, rbx
    movzx   rsi, r14b
    extern  asm_ctx_emit_byte
    call    asm_ctx_emit_byte
    dec     r12
    jnz     .fill_loop

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [asmctx_get_section]
; * Purpose: Returns the SECTION pointer for a given type (SEC_TEXT, SEC_DATA, etc).
; * Input:
; *   RDI: AsmCtx*
; *   RSI: Section Type (SEC_*)
; * Output:
; *   RAX: EXIT_OK or EXIT_ERROR
; *   RDX: SECTION*
; ;
global asmctx_get_section
asmctx_get_section:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi
    mov     r12, rsi               ; requested type
    
    mov     r13, [rbx + ASMCTX_sections]
    movzx   ecx, word [rbx + ASMCTX_seccount]
    xor     rax, rax               ; index
    
.loop:
    test    ecx, ecx
    jz      .not_found
    
    mov     rdx, [r13 + rax*8]     ; rdx = SECTION*
    cmp     byte [rdx + SECTION_type], r12b
    je      .found
    
    inc     rax
    dec     ecx
    jmp     .loop
    
.found:
    xor     rax, rax               ; EXIT_OK
    jmp     .done
    
.not_found:
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue
