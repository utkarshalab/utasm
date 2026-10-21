;
; ============================================================================
; File        : src/core/asmctx.s
; Project     : utasm
; Description : Assembly Context and Section Management.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

extern hash_fnv1a_str
extern io_mmap

%define SEC_HASH 131072                ; sec_hash's slots: twice MAX_SECTIONS, a power of 2
extern io_munmap
extern arena_alloc_struct
extern str_cmp

extern io_mmap
extern io_munmap
extern arena_alloc_struct
extern str_cmp
extern relax_note

[SECTION .text]

; emit_fast n, src: the common case of the emitters below - a current
; section with room for n more bytes - stores src there and returns
; EXIT_OK, before any frame is built; anything else goes on to .slow.
; Only rax and rdx change, rdx left at the last byte written (as the
; byte-at-a-time path leaves it).
%macro emit_fast 2
    mov     rax, [rdi + ASMCTX_curr_sec]
    test    rax, rax
    jz      .slow
    mov     rdx, [rax + SECTION_size]
    add     rdx, %1
    cmp     rdx, [rax + SECTION_cap]
    ja      .slow
    mov     [rax + SECTION_size], rdx
    add     rdx, [rax + SECTION_data]
    mov     [rdx - %1], %2
    dec     rdx
    xor     eax, eax
    ret
.slow:
%endmacro

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
    emit_fast 1, sil
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

    xor     eax, eax               ; EXIT_OK — callers test rax as a status
    pop     r12
    pop     rbx
    epilogue

.no_section:
    mov     rax, EXIT_INTERNAL
    pop     r12
    pop     rbx
    epilogue

.grow_section:
    push    r13                    ; r13/r14 belong to the caller
    push    r14
    push    rsi                    ; the byte to write: the calls below
                                   ; take rsi (it came out as the low byte
                                   ; of a pointer at each 64KB boundary)

    ; 1. Calculate new capacity: twice the current, and past the size -
    ;    which "resb 0x80000" in a code section moved beyond the buffer
    ;    without writing (the copy below read past the old one: a fault)
    mov     rax, [r12 + SECTION_cap]
    shl     rax, 1
    IF rax, e, 0
        mov rax, 65536
    ENDIF ; Default 64KB
    mov     rcx, [r12 + SECTION_size]
    mov     r8d, 0xFFFFFFFF
    cmp     rcx, r8
    ja      .grow_large                    ; bytes past 4 GiB
    add     rcx, 65536
    and     rcx, -65536            ; the size and a byte more, in 64KB
    cmp     rax, rcx
    jae     .cap_set
    mov     rax, rcx
.cap_set:
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
        jmp .grow_error
    ENDIF
    mov     r14, rdx               ; r14 = new buffer ptr
    
    ; 3. Copy old data: what the old buffer holds (past it, reserved
    ;    space: zero, as the new mapping is)
    mov     rdi, r14
    mov     rsi, [r12 + SECTION_data]
    mov     rcx, [r12 + SECTION_size]
    cmp     rcx, [r12 + SECTION_cap]
    jbe     .copy
    mov     rcx, [r12 + SECTION_cap]
.copy:
    rep movsb
    
    ; 4. Unmap old buffer
    mov     rdi, [r12 + SECTION_data]
    mov     rsi, [r12 + SECTION_cap]
    call    io_munmap
    
    ; 5. Update section struct
    mov     [r12 + SECTION_data], r14
    mov     [r12 + SECTION_cap], r13

    pop     rsi
    pop     r14
    pop     r13
    mov     rax, [r12 + SECTION_size]   ; .write expects rax = write offset
    jmp     .write

.grow_large:
    pop     rsi
    pop     r14
    pop     r13
    mov     rdi, [r12 + SECTION_name]
    extern  error_set_subject
    call    error_set_subject
    mov     rax, EXIT_SECTION_SIZE
    jmp     .done
.grow_error:
    pop     rsi
    pop     r14
    pop     r13
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

    ; and into the index by name (asmctx_find_section)
    mov     rdi, r12
    call    hash_fnv1a_str
    lea     rcx, [rel sec_hash]
.hash_slot:
    and     eax, SEC_HASH - 1
    cmp     qword [rcx + rax*8], 0
    je      .hash_put
    inc     eax
    jmp     .hash_slot
.hash_put:
    mov     [rcx + rax*8], r14
    
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
; * [asm_ctx_fit]
; * Purpose: Section RDI's buffer holds its size: resb and alignb move the
; *   size without writing, and the output reads the bytes up to it (a
; *   "resb 0x80000" at the end of a code section came out cut short). Not
; *   for uninitialised data (no bytes).
; * Output : RAX = EXIT_OK or an error
; ;
global asm_ctx_fit
asm_ctx_fit:
    xor     eax, eax
    cmp     dword [rdi + SECTION_elf_type], SHT_NOBITS
    je      .ret
    mov     rcx, [rdi + SECTION_size]
    cmp     rcx, [rdi + SECTION_cap]
    jb      .ret
    mov     eax, EXIT_SECTION_SIZE         ; bytes past 4 GiB
    mov     r8d, 0xFFFFFFFF
    cmp     rcx, r8
    ja      .ret
    xor     eax, eax
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    add     rcx, 65536
    and     rcx, -65536                    ; the size and a byte more, in 64KB,
    mov     r13, [r12 + SECTION_cap]       ; or twice what it holds: each growth
    shl     r13, 1                         ; copied it all ("alignb 0x40000" 500
    cmp     r13, rcx                       ; times took 31 s)
    jae     .cap_set
    mov     r13, rcx
.cap_set:
    xor     edi, edi
    mov     rsi, r13
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .out
    mov     r14, rdx
    mov     rdi, r14
    mov     rsi, [r12 + SECTION_data]
    mov     rcx, [r12 + SECTION_cap]       ; what the old buffer holds
    rep     movsb
    mov     rdi, [r12 + SECTION_data]
    mov     rsi, [r12 + SECTION_cap]
    extern  io_munmap
    call    io_munmap
    mov     [r12 + SECTION_data], r14
    mov     [r12 + SECTION_cap], r13
    xor     eax, eax
.out:
    pop     r14
    pop     r13
    pop     r12
.ret:
    ret

;*
; * [asm_ctx_emit_dword]
; * Purpose: Appends 4 bytes to the active section's buffer.
; ;
global asmctx_emit_dword
asmctx_emit_dword:
global asm_ctx_emit_dword
asm_ctx_emit_dword:
    emit_fast 4, esi
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
    emit_fast 2, si
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
    emit_fast 8, rsi
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
    
    ; by the index of names (16384 sections looked up one by one was
    ; quadratic: NASM's manysecs): an entry counts while it is the
    ; section its index says (the absolute block's left the list; the ELF
    ; writer renumbers, moving the entries with their indexes)
    mov     rdi, r12
    call    hash_fnv1a_str
    mov     r13, rax
.probe:
    and     r13d, SEC_HASH - 1
    lea     rax, [rel sec_hash]
    mov     r8, [rax + r13*8]
    test    r8, r8
    jz      .not_found
    mov     ecx, [r8 + SECTION_index]
    dec     ecx
    movzx   edx, word [rbx + ASMCTX_seccount]
    cmp     ecx, edx
    jae     .probe_next
    mov     rax, [rbx + ASMCTX_sections]
    cmp     [rax + rcx*8], r8
    jne     .probe_next
    push    r8
    sub     rsp, 8
    mov     rdi, [r8 + SECTION_name]
    mov     rsi, r12
    extern  str_cmp
    call    str_cmp
    add     rsp, 8
    pop     r8
    test    rax, rax
    jz      .found
.probe_next:
    inc     r13d
    jmp     .probe
    
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
    ; an explicit fill from asm_ctx_align_fill / _spec applies to this
    ; call only
    mov     r14, [rel asm_align_fill]
    mov     qword [rel asm_align_fill], 0
    
    ; 1. Get current section
    mov     r13, [rbx + ASMCTX_curr_sec]
    test    r13, r13
    jz      .done
    
    ; Safety: ignore zero or non-power-of-2 alignment (caller should have validated)
    test    r12, r12
    jz      .done
    ; at most 2^31 (the parser refuses 2^32 and above, as NASM). It was
    ; 64 KB, compared signed: "align 0x100000" padded nothing, silently,
    ; and 2^63 - negative - passed and padded forever
    mov     eax, 0x80000000
    cmp     r12, rax
    ja      .done
    mov     rax, r12
    dec     rax
    test    rax, r12               ; (n & (n-1)) == 0
    jnz     .done
    
    ; 2. Update Section-wide maximum alignment (A85) - not after
    ;    "sectalign off" (parser_sectalign)
    extern  sectalign_off
    cmp     byte [rel sectalign_off], 0
    jne     .calc_padding
    cmp     r12, [r13 + SECTION_align]
    jbe     .calc_padding
    mov     [r13 + SECTION_align], r12

.calc_padding:
    ; the fill: the source's byte, or the section's / smartalign's
    test    r14, r14
    jnz     .have_fill
    mov     rdi, rbx
    mov     rsi, r13
    extern  align_fill_spec
    call    align_fill_spec
    mov     r14, rax
.have_fill:
    ; 3. Calculate padding
    mov     rax, [r13 + SECTION_size]
    mov     rcx, r12
    dec     rcx                    ; mask = align - 1
    
    mov     rdx, rax
    and     rdx, rcx               ; offset = size & mask
    mov     rcx, r12
    sub     rcx, rdx               ; padding = align - offset...
    test    rdx, rdx
    cmovz   rcx, rdx               ; ...or 0 when already aligned
    ; GNU's ".p2align N,,MAX" (the fill spec's bits 10-15: MAX + 1): none
    ; where more is needed - src/optimize/jump.s (rx_cap) the same when code
    ; before it moves
    mov     r8, r14
    shr     r8d, 10
    and     r8d, 63
    jz      .uncapped
    dec     r8d
    cmp     rcx, r8
    jbe     .uncapped
    xor     ecx, ecx
.uncapped:

    ; Note the padding point for src/optimize/jump.s - also when no padding
    ; is needed now, since moving earlier code can make some necessary.
    ; (relax_note keeps every register)
    mov     rsi, rax               ; position of the padding
    mov     rdx, r12               ; alignment
    mov     r8, r14                ; the fill spec, to pad again
    mov     edi, RELAX_ALIGN
    call    relax_note
    mov     r12, rcx               ; the padding
    test    r12, r12
    jz      .done                  ; already aligned (or past MAX)
    
    ; 3. The bytes (src/optimize/align.s): a byte repeated, or smartalign's
    ; long NOPs
    test    r14d, 0x200
    jz      .fill_loop
    lea     rdi, [rel align_buf]
    mov     rsi, r12
    mov     rdx, r14
    extern  align_fill
    call    align_fill
    xor     r14d, r14d
    extern  asm_ctx_emit_byte
.smart_loop:
    mov     rdi, rbx
    lea     rax, [rel align_buf]
    movzx   rsi, byte [rax + r14]
    call    asm_ctx_emit_byte
    inc     r14
    cmp     r14, r12
    jb      .smart_loop
    jmp     .done

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
; * [asm_ctx_padto]
; * Purpose: "times K-($-$$) db F": COUNT bytes F, noted (RELAX_PADTO) as
; *   padding up to offset K = here + COUNT, which the jump optimizer
; *   lengthens when it shortens code before it.
; * Input  : RDI = AsmCtx, RSI = count, EDX = fill byte
; * Output : RAX = OK or error
; ;
global asm_ctx_padto
asm_ctx_padto:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, dl
    mov     rax, [rbx + ASMCTX_curr_sec]
    test    rax, rax
    jz      .emit
    push    rdi
    push    rsi
    mov     rsi, [rax + SECTION_size]      ; the padding's position
    lea     rdx, [rsi + r12]               ; K
    mov     ecx, r12d                      ; its length
    test    r12, r12
    jns     .length
    xor     ecx, ecx                       ; K behind: none yet
.length:
    mov     r8d, r13d
    or      r8d, 0x100                     ; fill spec: the byte
    mov     edi, RELAX_PADTO
    call    relax_note
    pop     rsi
    pop     rdi
.emit:
    test    r12, r12
    jle     .done
    mov     rdi, rbx
    mov     esi, r13d
    call    asm_ctx_emit_byte
    dec     r12
    jmp     .emit
.done:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [asm_ctx_align_fill]
; * Purpose: asm_ctx_align with the fill byte the source wrote.
; * Input  : RDI = AsmCtx, RSI = alignment, RDX = fill byte
; ;
global asm_ctx_align_fill
asm_ctx_align_fill:
    movzx   eax, dl
    or      eax, 0x100
    mov     [rel asm_align_fill], rax
    jmp     asm_ctx_align

;*
; * [asm_ctx_align_spec]
; * Purpose: asm_ctx_align with a fill spec (src/optimize/align.s): GNU as's
; *   long NOPs (align_gas_spec).
; * Input  : RDI = AsmCtx, RSI = alignment, RDX = fill spec
; ;
global asm_ctx_align_spec
asm_ctx_align_spec:
    mov     [rel asm_align_fill], rdx
    jmp     asm_ctx_align

[SECTION .bss]
alignb 8
sec_hash:       resq SEC_HASH           ; SECTION* by the hash of its name
asm_align_fill: resq 1             ; a fill spec (0x100 | fill byte ...), or 0 for the default
align_buf:      resb 0x10000       ; smartalign's padding
[SECTION .text]

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
