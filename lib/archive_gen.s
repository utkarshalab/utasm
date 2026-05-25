;
; ============================================================================
; File        : src/linker/archive_gen.s
; Project     : utasm
; Description : Unix Archive (.a) Generator Implementation.
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/archive.s"
%include "include/macro.s"

[SECTION .text]

;*
; * [archive_gen_header]
; * Purpose: Fills an ARHDR structure with member metadata.
; * Input:
; *   RDI: Pointer to ARHDR (60 bytes)
; *   RSI: Filename string
; *   RDX: Member size (integer)
; * Output:
; *   None
; ;
global archive_gen_header
archive_gen_header:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi               ; ARHDR*
    mov     r12, rsi               ; filename
    mov     r13, rdx               ; size
    
    ; 1. Clear Header (Space Padded)
    mov     rsi, AR_HDR_SIZE
    mov     dl, ' '
    extern  mem_set
    call    mem_set
    
    ; 2. Write Name (Ends with '/')
    mov     rdi, rbx
    mov     rsi, r12
    extern  str_len
    call    str_len
    mov     rcx, rax
    IF rcx, g, 15
        mov rcx, 15
    ENDIF
    
    mov     rdi, rbx
    mov     rsi, r12
    ; rdx is already set to size if we used mem_set, but we need to copy rcx bytes
    rep movsb
    mov     byte [rdi], '/'        ; Add AR terminator
    
    ; 3. Date (Fixed 0 for now)
    mov     byte [rbx + 16], '0'
    
    ; 4. UID / GID (Fixed 0)
    mov     byte [rbx + 28], '0'
    mov     byte [rbx + 34], '0'
    
    ; 5. Mode (Fixed 644 octal)
    mov     dword [rbx + 40], "644 "
    
    ; 6. Size (Decimal ASCII)
    mov     rdi, r13
    extern  error_uint_to_str      ; Reusing helper from diagnostics
    call    error_uint_to_str
    mov     rsi, rdx               ; string ptr
    mov     rdi, rbx
    add     rdi, 48                ; size offset
    extern  str_len
    call    str_len
    mov     rcx, rax
    rep movsb
    
    ; 7. Magic (`\n)
    mov     word [rbx + 58], 0x0A60 ; "`\n"
    
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [archive_write_member]
; * Purpose: Writes a member (header + data + optional padding) to a buffer.
; * Input:
; *   RDI: Output Buffer Pointer (current write position)
; *   RSI: Filename
; *   RDX: Data Pointer
; *   RCX: Data Size
; * Output:
; *   RAX: Number of bytes written
; ;
global archive_write_member
archive_write_member:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     rbx, rdi               ; out
    mov     r12, rsi               ; name
    mov     r13, rdx               ; data
    mov     r14, rcx               ; size
    
    ; 1. Write Header
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r14
    call    archive_gen_header
    
    ; 2. Write Data
    lea     rdi, [rbx + AR_HDR_SIZE]
    mov     rsi, r13
    mov     rcx, r14
    rep movsb
    
    ; 3. Optional Padding (AR members start on even boundaries)
    mov     rax, AR_HDR_SIZE
    add     rax, r14
    test    r14, 1
    JZ      .done
    mov     byte [rdi], 0x0A       ; Add newline padding
    inc     rax
    
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
; * [archive_gen_index]
; * Purpose: Generates the SysV-style symbol index member ('/').
; * Input:
; *   RDI: Output Buffer Pointer
; *   RSI: Number of Symbols (32-bit)
; *   RDX: Pointer to array of 32-bit offsets (Big-Endian)
; *   RCX: Pointer to concatenated symbol string table
; *   R8:  Size of string table
; * Output:
; *   RAX: Total size of member (header + data)
; ;
global archive_gen_index
archive_gen_index:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     rbx, rdi               ; out
    mov     r12d, esi              ; num_syms
    mov     r13, rdx               ; offsets
    mov     r14, rcx               ; strings
    mov     r15, r8                ; str_size
    
    ; 1. Calculate Data Size
    ; size = 4 (count) + 4 * num_syms + str_size
    mov     rax, r12
    shl     rax, 2
    add     rax, 4
    add     rax, r15
    push    rax                    ; save data size
    
    ; 2. Generate Header
    mov     rdi, rbx
    lea     rsi, [str_ar_symtab]
    mov     rdx, rax               ; data size
    call    archive_gen_header
    
    ; 3. Write Count (Big-Endian)
    lea     rdi, [rbx + AR_HDR_SIZE]
    mov     eax, r12d
    bswap   eax
    mov     [rdi], eax
    
    ; 4. Write Offsets
    add     rdi, 4
    mov     rsi, r13
    mov     ecx, r12d
    shl     rcx, 2
    rep movsb
    
    ; 5. Write String Table
    mov     rsi, r14
    mov     rcx, r15
    rep movsb
    
    pop     rax                    ; restore data size
    add     rax, AR_HDR_SIZE
    
    ; 6. Padding
    test    al, 1
    JZ      .done
    mov     byte [rdi], 0x0A
    inc     rax
    
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [archive_gen_strtab]
; * Purpose: Generates the long filename string table member (';').
; * Input:
; *   RDI: Output Buffer
; *   RSI: Pointer to long names table
; *   RDX: Size of long names table
; * Output:
; *   RAX: Total size of member
; ;
global archive_gen_strtab
archive_gen_strtab:
    prologue
    push    rbx
    push    r12
    push    r13
    
    mov     rbx, rdi
    mov     r12, rsi               ; table
    mov     r13, rdx               ; size
    
    ; 1. Header
    mov     rdi, rbx
    lea     rsi, [str_ar_strtab]
    mov     rdx, r13
    call    archive_gen_header
    
    ; 2. Data
    lea     rdi, [rbx + AR_HDR_SIZE]
    mov     rsi, r12
    mov     rcx, r13
    rep movsb
    
    mov     rax, r13
    add     rax, AR_HDR_SIZE
    
    ; 3. Padding
    test    al, 1
    JZ      .done
    mov     byte [rdi], 0x0A
    inc     rax
    
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

[SECTION .rodata]
str_ar_symtab: db "/", 0
str_ar_strtab: db ";", 0
