;
; ============================================
; File     : src/host/io.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.s"
%include "include/type.s"

extern error_new_from_errno

; ============================================================================
; HOST I/O (Syscall Interface)
; ============================================================================
; Safe, abstracted interface to system calls.
; Used by the assembler during bootstrapping on the host system.
; All functions return error codes in rax and results in rdx.
; Follows standard utasm calling convention.
;
; Calling convention (AMD64):
;   args  : rdi, rsi, rdx, rcx, r8, r9
;   return: rax = error code, rdx = result
;   callee saved: rbx, r12-r15, rbp
; ============================================================================

[SECTION .text]

; ---- io_write ---------------------------------
;
; io_write
; Writes a buffer to a file descriptor.
; Input    : rdi = file descriptor (i32)
;            rsi = buffer pointer (*const u8)
;            rdx = buffer size (usize)
; Output   : rax = EXIT_OK or EXIT_FILE_WRITE
;            rdx = number of bytes written (on success)
; Clobbers : rcx, r11
;
global io_write
io_write:
    mov     rax, AMD64_SYS_WRITE
    syscall

    ; syscall returns bytes written in rax, negative on error
    test    rax, rax
    js      .error

    mov     rdx, rax               ; rdx = bytes written
    xor     rax, rax               ; rax = EXIT_OK
    ret

.error:
    neg     rax                    ; convert negative error to positive errno
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_FILE_WRITE
    xor     rdx, rdx
    ret

; ---- io_read ----------------------------------
;
; io_read
; Reads from a file descriptor into a buffer.
; Input    : rdi = file descriptor (i32)
;            rsi = buffer pointer (*mut u8)
;            rdx = buffer size (usize)
; Output   : rax = EXIT_OK or EXIT_FILE_READ
;            rdx = number of bytes read (0 on EOF)
; Clobbers : rcx, r11
;
global io_read
io_read:
    mov     rax, AMD64_SYS_READ
    syscall

    test    rax, rax
    js      .error
    jz      .eof                   ; rax = 0 = EOF

    mov     rdx, rax               ; rdx = bytes read
    xor     rax, rax               ; rax = EXIT_OK
    ret

.eof:
    xor     rax, rax               ; rax = EXIT_OK
    xor     rdx, rdx               ; rdx = 0 (EOF)
    ret

.error:
    neg     rax
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_FILE_READ
    xor     rdx, rdx
    ret

; ---- io_open ----------------------------------
;
; io_open
; Opens or creates a file.
; Input    : rdi = pointer to filename string
;            rsi = open flags (AMD64_O_* values)
;            rdx = file mode (permissions) when creating
; Output   : rax = EXIT_OK or EXIT_FILE_NOT_FOUND or EXIT_FILE_PERM
;            rdx = file descriptor (on success)
; Clobbers : rcx, r11
;
global io_open
io_open:
    mov     rax, AMD64_SYS_OPEN
    syscall

    test    rax, rax
    js      .error

    mov     rdx, rax               ; rdx = fd
    xor     rax, rax               ; rax = EXIT_OK
    ret

.error:
    neg     rax                    ; rax = errno
    cmp     rax, ENOENT
    je      .not_found
    cmp     rax, EACCES
    je      .permission

    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_ERROR
    jmp     .done

.not_found:
    mov     rax, EXIT_FILE_NOT_FOUND
    jmp     .done

.permission:
    mov     rax, EXIT_FILE_PERM

.done:
    xor     rdx, rdx
    ret

; ---- io_close ---------------------------------
;
; io_close
; Closes a file descriptor.
; Input    : rdi = file descriptor (i32)
; Output   : rax = EXIT_OK or EXIT_ERROR
; Clobbers : rcx, r11
;
global io_close
io_close:
    mov     rax, AMD64_SYS_CLOSE
    syscall

    test    rax, rax
    js      .error

    xor     rax, rax               ; EXIT_OK
    ret

.error:
    neg     rax
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_ERROR
    ret

; ---- io_lseek ---------------------------------
;
; io_lseek
; Repositions the file offset.
; Input    : rdi = file descriptor (i32)
;            rsi = offset (i64)
;            rdx = whence (0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END)
; Output   : rax = EXIT_OK or EXIT_ERROR
;            rdx = new file offset (on success)
; Clobbers : rcx, r11
;
global io_lseek
io_lseek:
    mov     rax, AMD64_SYS_LSEEK
    syscall

    test    rax, rax
    js      .error

    mov     rdx, rax               ; rdx = new offset
    xor     rax, rax               ; EXIT_OK
    ret

.error:
    neg     rax
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_ERROR
    xor     rdx, rdx
    ret

; ---- io_mmap ----------------------------------
;
; io_mmap
; Maps files or devices into memory.
; Input    : rdi = desired address (or NULL)
;            rsi = length (usize)
;            rdx = protection (PROT_* flags)
;            rcx = flags (MAP_* flags)
;            r8  = file descriptor (i32)
;            r9  = offset (usize)
; Output   : rax = EXIT_OK or EXIT_OOM
;            rdx = pointer to mapped memory (on success)
; Clobbers : rcx, r10, r11
;
global io_mmap
io_mmap:
    mov     r10, rcx               ; r10 = flags (AMD64 syscall ABI)
    mov     rax, AMD64_SYS_MMAP
    syscall

    cmp     rax, MAP_FAILED
    je      .error

    mov     rdx, rax               ; rdx = mapped address
    xor     rax, rax               ; EXIT_OK
    ret

.error:
    neg     rax                    ; get errno from negative return
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_OOM
    xor     rdx, rdx
    ret

; ---- io_munmap --------------------------------
;
; io_munmap
; Unmaps a memory region.
; Input    : rdi = pointer to mapped memory
;            rsi = length (usize)
; Output   : rax = EXIT_OK or EXIT_ERROR
; Clobbers : rcx, r11
;
global io_munmap
io_munmap:
    mov     rax, AMD64_SYS_MUNMAP
    syscall

    test    rax, rax
    js      .error

    xor     rax, rax               ; EXIT_OK
    ret

.error:
    neg     rax
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_ERROR
    ret

; ---- io_ftruncate -----------------------------
;
; io_ftruncate
; Changes the size of a file.
; Input    : rdi = file descriptor (i32)
;            rsi = new length (usize)
; Output   : rax = EXIT_OK or EXIT_ERROR
; Clobbers : rcx, r11
;
global io_ftruncate
io_ftruncate:
    mov     rax, AMD64_SYS_FTRUNCATE
    syscall

    test    rax, rax
    js      .error

    xor     rax, rax               ; EXIT_OK
    ret

.error:
    neg     rax
    mov     rdi, rax
    call    error_new_from_errno
    mov     rax, EXIT_ERROR
    ret

; ---- io_exists --------------------------------
;
; io_exists
; Checks if a file exists and is accessible.
; Input    : rdi = pointer to filename string
; Output   : rax = EXIT_OK (exists) or EXIT_FILE_NOT_FOUND
; Clobbers : rcx, r11
;
global io_exists
io_exists:
    push    rbx
    mov     rbx, rdi               ; save filename

    ; try to open read-only
    mov     rsi, AMD64_O_RDONLY
    xor     rdx, rdx               ; mode = 0 (ignored for existing files)
    call    io_open

    test    rax, rax
    jnz     .done                  ; error occurred

    ; success - close and return OK
    mov     rdi, rdx               ; fd from io_open
    push    rax                    ; save return code (0)
    call    io_close
    pop     rax                    ; restore return code
    mov     rdx, 1                 ; exists = true
    jmp     .done

.done:
    pop     rbx
    ret

; ---- io_file_size -----------------------------
;
; io_file_size
; Gets the size of an open file.
; Input    : rdi = file descriptor (i32)
; Output   : rax = EXIT_OK or EXIT_ERROR
;            rdx = file size in bytes (on success)
; Clobbers : rcx, r10, r11
;
global io_file_size
io_file_size:
    push    rbx
    mov     rbx, rdi               ; save fd

    ; seek to end to get size
    xor     rsi, rsi               ; offset = 0
    mov     rdx, 2                 ; SEEK_END = 2
    call    io_lseek

    test    rax, rax
    jnz     .error

    mov     r10, rdx               ; save file size

    ; seek back to beginning
    mov     rdi, rbx               ; fd
    xor     rsi, rsi               ; offset = 0
    xor     rdx, rdx               ; SEEK_SET = 0
    call    io_lseek

    test    rax, rax
    jnz     .error

    mov     rdx, r10               ; restore file size
    xor     rax, rax               ; EXIT_OK
    pop     rbx
    ret

.error:
    xor     rdx, rdx
    pop     rbx
    ret

; ---- io_read_full -----------------------------
;
; io_read_full
; Reads exactly n bytes from a file (retries on short reads).
; Input    : rdi = file descriptor (i32)
;            rsi = buffer pointer (*mut u8)
;            rdx = bytes to read (usize)
; Output   : rax = EXIT_OK or EXIT_FILE_READ
;            rdx = actual bytes read (should equal input rdx on success)
; Clobbers : rcx, r10, r11
;
global io_read_full
io_read_full:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi               ; save fd
    mov     r12, rsi               ; save buffer
    mov     r13, rdx               ; save total bytes to read

    xor     r10, r10               ; bytes read so far = 0

.read_loop:
    cmp     r10, r13               ; read all requested bytes?
    jge     .success

    ; calculate remaining bytes and current buffer position
    mov     rdi, rbx               ; fd
    lea     rsi, [r12 + r10]       ; current buffer position
    mov     rdx, r13
    sub     rdx, r10               ; remaining bytes

    call    io_read
    test    rax, rax
    jnz     .error                 ; read error

    test    rdx, rdx
    jz      .eof                   ; EOF before reading all data

    add     r10, rdx               ; advance bytes read counter
    jmp     .read_loop

.success:
    mov     rdx, r10               ; total bytes read
    xor     rax, rax               ; EXIT_OK
    jmp     .done

.eof:
    mov     rax, EXIT_UNEXPECTED_EOF
    xor     rdx, rdx
    jmp     .done

.error:
    mov     rax, EXIT_FILE_READ
    xor     rdx, rdx

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- io_write_full ----------------------------
;
; io_write_full
; Writes exactly n bytes to a file (retries on short writes).
; Input    : rdi = file descriptor (i32)
;            rsi = buffer pointer (*const u8)
;            rdx = bytes to write (usize)
; Output   : rax = EXIT_OK or EXIT_FILE_WRITE
; Clobbers : rcx, r10, r11
;
global io_write_full
io_write_full:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi               ; save fd
    mov     r12, rsi               ; save buffer
    mov     r13, rdx               ; save total bytes to write

    xor     r10, r10               ; bytes written so far = 0

.write_loop:
    cmp     r10, r13               ; written all bytes?
    jge     .success

    ; calculate remaining bytes and current buffer position
    mov     rdi, rbx               ; fd
    lea     rsi, [r12 + r10]       ; current buffer position
    mov     rdx, r13
    sub     rdx, r10               ; remaining bytes

    call    io_write
    test    rax, rax
    jnz     .error                 ; write error

    add     r10, rdx               ; advance bytes written counter
    jmp     .write_loop

.success:
    xor     rax, rax               ; EXIT_OK
    jmp     .done

.error:
    mov     rax, EXIT_FILE_WRITE

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- io_write_byte ----------------------------
;
; io_write_byte
; Writes a single byte to a file descriptor.
; Input    : rdi = file descriptor (i32)
;            rsi = byte value (SIL)
; Output   : rax = EXIT_OK or EXIT_FILE_WRITE
; Clobbers : rcx, r11
;
global io_write_byte
io_write_byte:
    push    rsi                    ; put byte on stack
    mov     rsi, rsp               ; point rsi to it
    mov     rdx, 1                 ; size = 1
    call    io_write
    pop     rsi                    ; restore stack
    ret
