;
; ============================================
; File     : lib/time.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

; ============================================================================
; THE TIME OF ASSEMBLY
; ============================================================================
; NASM's __DATE__, __TIME__, __DATE_NUM__, __TIME_NUM__, their __UTC_*
; forms and __POSIX_TIME__: the moment assembly starts, taken once.
;
; Local time is UTC plus the offset of the time zone: the TZif file named
; by TZ (":/path", "/path" or a zone name under /usr/share/zoneinfo), or
; /etc/localtime. The offset is the one of the last transition before now
; (a TZif file lists them; the rule string at its end, for times past the
; last one, is not read). No file: UTC.
;
; time_init fills, once:
;   time_local, time_utc    "YYYY-MM-DD" at +0, "HH:MM:SS" at +16,
;                           YYYYMMDD at +32, HHMMSS (no leading zeros)
;                           at +48, all NUL-terminated
;   time_posix              seconds since 1970 (decimal text)

%define SYS_READ    0
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_TIME    201

%define TZ_BUF      65536

[SECTION .bss]
global time_local, time_utc, time_posix
time_local:     resb 64
time_utc:       resb 64
time_posix:     resb 24
ti_done:        resb 1
ti_path:        resb 256
ti_buf:         resb TZ_BUF

[SECTION .rodata]
ti_tz_name:     db "TZ="
ti_localtime:   db "/etc/localtime", 0
ti_zoneinfo:    db "/usr/share/zoneinfo/"
ti_zoneinfo_len equ $ - ti_zoneinfo

[SECTION .text]

; ---- time_init ---------------------------
;
; time_init
; Takes the time and writes time_local, time_utc and time_posix (once).
; Preserves rbx, rbp, r12-r15.
;
global time_init
time_init:
    cmp     byte [rel ti_done], 0
    jne     .ret
    mov     byte [rel ti_done], 1
    push    rbx
    push    r12
    mov     eax, SYS_TIME
    xor     edi, edi
    syscall
    test    rax, rax
    jns     .have
    xor     eax, eax
.have:
    mov     r12, rax
    mov     rdi, rax
    lea     rsi, [rel time_posix]
    call    ti_decimal
    mov     rdi, r12
    lea     rsi, [rel time_utc]
    call    ti_format
    call    ti_zone_offset
    lea     rdi, [r12 + rax]
    test    rdi, rdi
    jns     .local
    xor     edi, edi
.local:
    lea     rsi, [rel time_local]
    call    ti_format
    pop     r12
    pop     rbx
.ret:
    ret

; ---- ti_format (internal) ----------------
; rdi = seconds since 1970, rsi = a 64-byte block (see above)
ti_format:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rsi
    mov     rax, rdi
    xor     edx, edx
    mov     ecx, 86400
    div     rcx
    mov     r12, rdx                       ; r12 = second of the day
    ; the civil date of day rax (H. Hinnant's days_from_civil, inverted)
    add     rax, 719468
    xor     edx, edx
    mov     ecx, 146097
    div     rcx                            ; rax = era, rdx = day of era
    imul    r13, rax, 400                  ; r13 = era * 400
    mov     r8, rdx                        ; r8 = doe
    ; yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365
    mov     rax, r8
    xor     edx, edx
    mov     ecx, 1460
    div     rcx
    mov     r9, r8
    sub     r9, rax
    mov     rax, r8
    xor     edx, edx
    mov     ecx, 36524
    div     rcx
    add     r9, rax
    mov     rax, r8
    xor     edx, edx
    mov     ecx, 146096
    div     rcx
    sub     r9, rax
    mov     rax, r9
    xor     edx, edx
    mov     ecx, 365
    div     rcx
    mov     r9, rax                        ; r9 = yoe
    add     r13, rax                       ; r13 = year (March-based)
    ; doy = doe - (365*yoe + yoe/4 - yoe/100)
    imul    r10, r9, 365
    mov     rax, r9
    shr     rax, 2
    add     r10, rax
    mov     rax, r9
    xor     edx, edx
    mov     ecx, 100
    div     rcx
    sub     r10, rax
    mov     r11, r8
    sub     r11, r10                       ; r11 = doy
    ; mp = (5*doy + 2) / 153; day = doy - (153*mp + 2)/5 + 1
    imul    rax, r11, 5
    add     rax, 2
    xor     edx, edx
    mov     ecx, 153
    div     rcx
    mov     r9, rax                        ; r9 = mp
    imul    rax, r9, 153
    add     rax, 2
    xor     edx, edx
    mov     ecx, 5
    div     rcx
    sub     r11, rax
    inc     r11                            ; r11 = day
    lea     r10, [r9 + 3]                  ; month = mp < 10 ? mp + 3 : mp - 9
    cmp     r9, 10
    jb      .month
    lea     r10, [r9 - 9]
.month:
    cmp     r10, 2
    ja      .year
    inc     r13                            ; January, February: next year
.year:
    ; "YYYY-MM-DD" and YYYYMMDD
    lea     rdi, [rbx]
    mov     eax, r13d
    call    ti_put4
    mov     byte [rdi], '-'
    inc     rdi
    mov     eax, r10d
    call    ti_put2
    mov     byte [rdi], '-'
    inc     rdi
    mov     eax, r11d
    call    ti_put2
    mov     byte [rdi], 0
    lea     rdi, [rbx + 32]
    mov     eax, r13d
    call    ti_put4
    mov     eax, r10d
    call    ti_put2
    mov     eax, r11d
    call    ti_put2
    mov     byte [rdi], 0
    ; "HH:MM:SS" and HHMMSS
    mov     rax, r12
    xor     edx, edx
    mov     ecx, 3600
    div     rcx
    mov     r9, rax                        ; hours
    mov     rax, rdx
    xor     edx, edx
    mov     ecx, 60
    div     rcx
    mov     r10, rax                       ; minutes
    mov     r11, rdx                       ; seconds
    lea     rdi, [rbx + 16]
    mov     eax, r9d
    call    ti_put2
    mov     byte [rdi], ':'
    inc     rdi
    mov     eax, r10d
    call    ti_put2
    mov     byte [rdi], ':'
    inc     rdi
    mov     eax, r11d
    call    ti_put2
    mov     byte [rdi], 0
    imul    rdi, r9, 10000
    imul    rax, r10, 100
    add     rdi, rax
    add     rdi, r11
    lea     rsi, [rbx + 48]
    call    ti_decimal
    pop     r13
    pop     r12
    pop     rbx
    ret

; ti_put2: eax (0..99) as two digits at rdi, rdi advanced
ti_put2:
    xor     edx, edx
    mov     ecx, 10
    div     ecx                            ; eax = tens, edx = units
    add     al, '0'
    mov     [rdi], al
    add     dl, '0'
    mov     [rdi + 1], dl
    add     rdi, 2
    ret

; ti_put4: eax (0..9999) as four digits at rdi, rdi advanced
ti_put4:
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    push    rdx
    call    ti_put2
    pop     rax
    jmp     ti_put2

; ---- ti_zone_offset (internal) -----------
; rax = the local time zone's offset from UTC in seconds now (r12 = now),
; 0 when it cannot be read
ti_zone_offset:
    push    rbx
    push    r13
    push    r14
    push    r15
    ; the file: TZ (":path", "/path", a zone name), else /etc/localtime
    lea     rbx, [rel ti_localtime]
    extern  utasm_envp
    mov     r8, [rel utasm_envp]
    test    r8, r8
    jz      .open
.env:
    mov     rsi, [r8]
    test    rsi, rsi
    jz      .open
    mov     eax, [rsi]
    and     eax, 0x00FFFFFF
    cmp     eax, 'TZ='
    je      .tz
    add     r8, 8
    jmp     .env
.tz:
    add     rsi, 3
    cmp     byte [rsi], ':'
    jne     .tz_text
    inc     rsi
.tz_text:
    cmp     byte [rsi], 0
    je      .open                          ; TZ= : /etc/localtime
    lea     rdi, [rel ti_path]
    cmp     byte [rsi], '/'
    je      .tz_copy
    push    rsi
    lea     rsi, [rel ti_zoneinfo]
    mov     ecx, ti_zoneinfo_len
    rep movsb
    pop     rsi
.tz_copy:
    lea     rcx, [rel ti_path + 255]
.tz_ch:
    cmp     rdi, rcx
    jae     .utc
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .tz_ch
    lea     rbx, [rel ti_path]
.open:
    mov     eax, SYS_OPEN
    mov     rdi, rbx
    xor     esi, esi                       ; O_RDONLY
    xor     edx, edx
    syscall
    test    rax, rax
    js      .utc
    mov     r13, rax                       ; fd
    xor     r14d, r14d                     ; bytes read
.read:
    mov     eax, SYS_READ
    mov     rdi, r13
    lea     rsi, [rel ti_buf]
    add     rsi, r14
    mov     edx, TZ_BUF
    sub     rdx, r14
    jz      .read_done
    syscall
    test    rax, rax
    jle     .read_done
    add     r14, rax
    jmp     .read
.read_done:
    mov     eax, SYS_CLOSE
    mov     rdi, r13
    syscall

    ; ---- TZif: a header, then the transitions and the types ----
    lea     rbx, [rel ti_buf]
    lea     r15, [rbx + r14]               ; r15 = end of the data
    mov     r8d, 4                         ; r8 = size of a transition time
    call    .header
    jc      .utc
    cmp     byte [rbx + 4], '2'
    jb      .v1
    ; version 2+: skip the 32-bit block to the 64-bit one
    mov     rbx, rsi
    call    .header
    jc      .utc
    mov     r8d, 8
.v1:
    ; rbx = header; r9 = timecnt, r10 = typecnt
    lea     r11, [rbx + 44]                ; the transition times
    xor     eax, eax                       ; type of the last one <= now
    xor     ecx, ecx
.trans:
    cmp     rcx, r9
    jae     .type
    cmp     r8d, 8
    je      .t64
    mov     edx, [r11]
    bswap   edx
    movsxd  rdx, edx
    jmp     .cmp
.t64:
    mov     rdx, [r11]
    bswap   rdx
.cmp:
    cmp     rdx, r12
    jg      .type
    lea     rdx, [rbx + 44]
    mov     rsi, r9
    imul    rsi, r8
    add     rdx, rsi                       ; the type indices
    movzx   eax, byte [rdx + rcx]
    add     r11, r8
    inc     rcx
    jmp     .trans
.type:
    cmp     rax, r10
    jae     .utc
    ; ttinfo: utoff (4, big-endian), isdst, abbrind
    lea     rdx, [rbx + 44]
    mov     rsi, r9
    imul    rsi, r8
    add     rdx, rsi
    add     rdx, r9
    imul    rax, rax, 6
    mov     eax, [rdx + rax]
    bswap   eax
    movsxd  rax, eax
    jmp     .ret
.utc:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     rbx
    ret

    ; checks the header at rbx and its block's size: CF set when it is
    ; not TZif or the file is short; r9 = timecnt, r10 = typecnt, rsi =
    ; the first byte after the block (r8 = the time size)
.header:
    lea     rax, [rbx + 44]
    cmp     rax, r15
    ja      .bad
    cmp     dword [rbx], 'TZif'
    jne     .bad
    mov     eax, [rbx + 20]                ; isutcnt
    bswap   eax
    mov     esi, eax
    mov     eax, [rbx + 24]                ; isstdcnt
    bswap   eax
    add     rsi, rax
    mov     eax, [rbx + 28]                ; leapcnt
    bswap   eax
    lea     rdx, [r8 + 4]              ; a leap record: time + 4
    imul    rax, rdx
    add     rsi, rax
    mov     eax, [rbx + 32]                ; timecnt
    bswap   eax
    mov     r9, rax
    lea     rdx, [r8 + 1]
    imul    rax, rdx
    add     rsi, rax
    mov     eax, [rbx + 36]                ; typecnt
    bswap   eax
    mov     r10, rax
    imul    rax, rax, 6
    add     rsi, rax
    mov     eax, [rbx + 40]                ; charcnt
    bswap   eax
    add     rsi, rax
    lea     rsi, [rbx + rsi + 44]
    cmp     rsi, r15
    ja      .bad
    clc
    ret
.bad:
    stc
    ret

; ---- ti_decimal (internal) ---------------
; rdi = an unsigned number -> its decimal text at rsi, NUL-terminated
ti_decimal:
    sub     rsp, 32
    mov     rax, rdi
    lea     r8, [rsp + 31]
    mov     byte [r8], 0
    mov     ecx, 10
.digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digit
.copy:
    mov     al, [r8]
    mov     [rsi], al
    inc     r8
    inc     rsi
    test    al, al
    jnz     .copy
    add     rsp, 32
    ret
