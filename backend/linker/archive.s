;
; ============================================================================
; File        : src/core/archive.s
; Project     : utasm
; Description : Unix Archive (.a) Parser Implementation.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/archive.s"
%include "include/macro.s"

[SECTION .text]

;*
; * [archive_init]
; * Purpose: Initializes an ARCHIVE struct from a mapped buffer.
; * Input:
; *   RDI: [out] Pointer to ARCHIVE struct
; *   RSI: [in]  Pointer to mapped buffer
; *   RDX: [in]  Total size of buffer
; * Output:
; *   RAX: EXIT_OK or error code
; ;
global archive_init
archive_init:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; rbx = ARCHIVE*
    mov     r12, rsi               ; r12 = buffer
    mov     r13, rdx               ; r13 = size
    
    ; 1. Check Magic
    IF r13, b, AR_MAG_LEN
        mov rax, EXIT_INVALID_FORMAT
        jmp .error
        ENDIF
    
    ; Compare magic
    mov     rax, [r12]
    mov     rcx, 0x0A686372613C217F ; "!<arch>\n" in LE? No, let's be careful.
    ; "!<arch>\n" -> 21 3C 61 72 63 68 3E 0A
    
    lea     rdi, [r12]
    lea     rsi, [str_ar_mag]
    mov     rdx, AR_MAG_LEN
    extern  mem_compare
    call    mem_compare
    IF rax, ne, 0
        mov rax, EXIT_INVALID_FORMAT
        jmp .error
        ENDIF
    
    ; 2. Initialize Struct
    mov     byte [rbx + ARCHIVE_tag], TAG_ARCHIVE
    mov     [rbx + ARCHIVE_buf],  r12
    mov     [rbx + ARCHIVE_size], r13
    
    lea     rax, [r12 + AR_MAG_LEN]
    mov     [rbx + ARCHIVE_curr], rax
    
    ; 3. Scan for special members (/ and ;)
    ; Most archives have these at the start
    call    archive_scan_special
    
    xor     rax, rax
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    jmp     .done

;*
; * [archive_scan_special]
; ;
archive_scan_special:
    prologue
    push    r12
    push    r13
    
    mov     r12, [rbx + ARCHIVE_curr]
    mov     r13, [rbx + ARCHIVE_size]
    add     r13, [rbx + ARCHIVE_buf] ; r13 = end
    
.loop:
    cmp     r12, r13
    jge     .done
    
    ; Check if it's a special member
    mov     al, [r12 + ARHDR_name]
    IF al, e, '/'
        mov     cl, [r12 + ARHDR_name + 1]
        IF cl, e, '/'
            ; Long names table
            mov     [rbx + ARCHIVE_strtab], r12
        ELSEIF cl, e, ' '
            ; Symbol table
            mov     [rbx + ARCHIVE_symtab], r12
            ENDIF
            ELSE
        ; Regular member reached, stop scanning specials
        mov     [rbx + ARCHIVE_curr], r12
        jmp     .done
        ENDIF
    
    ; Advance to next member
    mov     rdi, rbx
    mov     rsi, r12
    call    archive_get_member_size
    add     rax, AR_HDR_SIZE
    test    rax, 1
    jz      .no_pad
    inc     rax                    ; Round up to even boundary
.no_pad:
    add     r12, rax
    jmp     .loop

.done:
    pop     r13
    pop     r12
    epilogue

;*
; * [archive_get_member_size]
; * Input: RSI = pointer to ARHDR
; * Output: RAX = size of member data
; ;
archive_get_member_size:
    prologue
    push    r12
    
    lea     rdi, [rsi + ARHDR_size]
    mov     rcx, 10                ; size field is 10 bytes
    ; Need to parse ASCII integer
    ; We'll copy to a temporary nul-terminated buffer
    sub     rsp, 16
    mov     r12, rsp
    
    mov     rcx, 10
.copy:
    mov     al, [rdi]
    IF al, e, ' '
        mov al, 0
    ENDIF
    mov     [r12], al
    inc     rdi
    inc     r12
    loop    .copy
    mov     byte [r12], 0
    
    mov     rdi, rsp
    extern  str_to_int
    call    str_to_int
    
    add     rsp, 16
    pop     r12
    epilogue

;*
; * [archive_resolve_symbol]
; * Purpose: Finds a symbol in the archive's internal index (the '/' member).
; * Input:
; *   RBX: [in] Pointer to ARCHIVE struct
; *   RSI: [in] Pointer to symbol name string (null-terminated)
; * Output:
; *   RAX: File offset to the member containing the symbol, or 0 if not found.
; ;
global archive_resolve_symbol
archive_resolve_symbol:
    prologue
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     r12, [rbx + ARCHIVE_symtab]
    test    r12, r12
    jz      .not_found
    
    ; r12 points to the ARHDR of the '/' member
    ; Member data starts at ARHDR + 60
    lea     r13, [r12 + AR_HDR_SIZE] ; r13 = data start
    
    ; 1. Get Number of Symbols (4-byte Big-Endian)
    mov     eax, [r13]
    bswap   eax                    ; Convert from Big-Endian to host
    mov     r14d, eax               ; r14 = num_symbols
    
    ; 2. Points to the start of the string table
    ; String table starts after the num_symbols (4) and the offsets array (4 * num_symbols)
    lea     r15, [r13 + 4]
    mov     rax, r14
    shl     rax, 2                 ; rax = num_symbols * 4
    add     r15, rax               ; r15 = string_table pointer
    
    ; 3. Scan strings for a match
    xor     rcx, rcx               ; i = 0
.lookup_loop:
    cmp     ecx, r14d
    jge     .not_found
    
    mov     rdi, r15               ; Current string in archive
    push    rcx
    push    rsi
    extern  str_compare
    call    str_compare
    pop     rsi
    pop     rcx
    
    IF rax, e, 0
        ; Match found! Get offset i from the offsets array
        lea     rax, [r13 + 4]
        mov     eax, [rax + rcx * 4]
        bswap   eax                ; Convert offset to host endianness
        jmp     .done
        ENDIF
    
    ; Advance to next string (null-terminated)
    mov     rdi, r15
    extern  str_len
    call    str_len
    add     r15, rax
    inc     r15                    ; Skip null terminator
    
    inc     ecx
    jmp     .lookup_loop

.not_found:
    xor     rax, rax
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    epilogue

;*
; * [archive_get_member_data]
; * Purpose: Retrieves a pointer to the data and the size of a member at a given offset.
; * Input:
; *   RBX: [in] Pointer to ARCHIVE struct
; *   RSI: [in] File offset to the member header
; * Output:
; *   RAX: Pointer to member data
; *   RDX: Size of member data
; ;
global archive_get_member_data
archive_get_member_data:
    prologue
    
    mov     r8, [rbx + ARCHIVE_buf]
    mov     r9, [rbx + ARCHIVE_size]
    
    ; Validate offset
    IF rsi, ge, r9
        xor rax, rax
        xor rdx, rdx
        epilogue
        ENDIF
    
    lea     r10, [r8 + rsi]        ; r10 = ARHDR*
    
    ; 1. Parse size from header
    push    rsi
    mov     rsi, r10
    call    archive_get_member_size
    pop     rsi
    
    mov     rdx, rax               ; rdx = data size
    lea     rax, [r10 + AR_HDR_SIZE] ; rax = data start
    
    epilogue

[SECTION .rodata]
str_ar_mag:     db "!<arch>", 10
