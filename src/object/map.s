;
; ============================================
; File     : src/object/map.s
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
; MAP FILES
; ============================================================================
; NASM's map file, as its bin format writes it ("[map all file.map]"): the
; origin, the sections (summary and detail), the symbols by section and
; address. "[map OPTION ... FILE]" in a flat binary (bin, ubf, standalone):
; all, brief (origin + summary), sections / segments (+ the detail),
; symbols; options of several [map] lines add up, the first file named is
; the one written. "--map FILE" (any format): all of it - for an object
; file the addresses are the sections' offsets.

extern  io_open
extern  io_write
extern  io_close
extern  mem_reserve
extern  bin_origin

%define MAP_ORIGIN   1
%define MAP_SUMMARY  2
%define MAP_SECTIONS 4
%define MAP_SYMBOLS  8
%define MAP_CAP      (1 << 28)
%define MAP_SYMS     (1 << 22)      ; symbols listed (pointers)

[SECTION .rodata]
h_head:     db 10, "- NASM Map file ", 0
h_source:   db "Source file:  ", 0
h_output:   db "Output file:  ", 0
h_origin:   db "-- Program origin ", 0
h_summary:  db "-- Sections (summary) ", 0
h_detail:   db "-- Sections (detailed) ", 0
h_symbols:  db "-- Symbols ", 0
h_nosec:    db "---- No Section ", 0
h_section:  db "---- Section ", 0
h_cols:     db "Vstart            Start             Stop              Length    Class     Name", 10, 0
h_value:    db "Value     Name", 10, 0
h_real:     db "Real              Virtual           Name", 10, 0
f_class:    db "class:     ", 0
f_length:   db "length:    ", 0
f_start:    db "start:     ", 0
f_align:    db "align:     ", 0
f_follows:  db "follows:   ", 0
f_vstart:   db "vstart:    ", 0
f_valign:   db "valign:    ", 0
f_vfollows: db "vfollows:  ", 0
s_undef:    db "not defined", 0
s_progbits: db "progbits", 0
s_nobits:   db "nobits  ", 0
s_two:      db "  ", 0
s_text:     db ".text", 0
mo_all:      db "all", 0
mo_brief:    db "brief", 0
mo_sections: db "sections", 0
mo_segments: db "segments", 0
mo_symbols:  db "symbols", 0
hexdig:     db "0123456789ABCDEF"

[SECTION .bss]
alignb 8
global map_file, map_flags
map_file:       resq 1              ; the file to write, or 0
map_flags:      resd 1              ; MAP_*
alignb 8
mp_buf:         resq 1
mp_len:         resq 1
mp_syms:        resq 1
mp_nsyms:       resq 1

[SECTION .text]

; ---- map_option ---------------------------
;
; map_option
; One word of "[map ...]": an option, or (the first time) the file.
; Input    : rdi = the word
; Output   : rax = OK
;
global map_option
map_option:
    push    rbx
    mov     rbx, rdi
    lea     rsi, [rel mo_all]
    mov     ecx, MAP_ORIGIN | MAP_SUMMARY | MAP_SECTIONS | MAP_SYMBOLS
    call    .is
    je      .add
    lea     rsi, [rel mo_brief]
    mov     ecx, MAP_ORIGIN | MAP_SUMMARY
    call    .is
    je      .add
    lea     rsi, [rel mo_sections]
    mov     ecx, MAP_ORIGIN | MAP_SUMMARY | MAP_SECTIONS
    call    .is
    je      .add
    lea     rsi, [rel mo_segments]
    call    .is
    je      .add
    lea     rsi, [rel mo_symbols]
    mov     ecx, MAP_SYMBOLS
    call    .is
    je      .add
    ; the file (the first one named)
    cmp     qword [rel map_file], 0
    jne     .ok
    mov     [rel map_file], rbx
    jmp     .ok
.add:
    or      [rel map_flags], ecx
.ok:
    xor     eax, eax
    pop     rbx
    ret
; .is: the word rbx is rsi (any case)? ZF
.is:
    mov     rdi, rbx
.is_next:
    movzx   eax, byte [rdi]
    movzx   edx, byte [rsi]
    cmp     eax, 'A'
    jb      .is_cmp
    cmp     eax, 'Z'
    ja      .is_cmp
    or      eax, 0x20
.is_cmp:
    cmp     eax, edx
    jne     .is_ret
    test    eax, eax
    jz      .is_ret
    inc     rdi
    inc     rsi
    jmp     .is_next
.is_ret:
    ret

; ---- map_cli ------------------------------
;
; map_cli
; "--map FILE": all of it, into FILE.
; Input    : rdi = the file
;
global map_cli
map_cli:
    mov     [rel map_file], rdi
    mov     dword [rel map_flags], MAP_ORIGIN | MAP_SUMMARY | MAP_SECTIONS | MAP_SYMBOLS
    ret

; ---- map_write ----------------------------
;
; map_write
; The output written: the map file, when one was asked for.
; Input    : rdi = AsmCtx
; Output   : rax = OK or an error
;
global map_write
map_write:
    xor     eax, eax
    cmp     qword [rel map_file], 0
    jne     .on
    ret
.on:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     eax, [rel map_flags]
    test    eax, eax
    jnz     .flags
    mov     dword [rel map_flags], MAP_ORIGIN | MAP_SUMMARY   ; ([map file])
.flags:
    cmp     qword [rel mp_buf], 0
    jne     .have_buf
    mov     rsi, MAP_CAP
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    mov     [rel mp_buf], rdx
    mov     rsi, MAP_SYMS * 8
    call    mem_reserve
    test    rax, rax
    jnz     .ret
    mov     [rel mp_syms], rdx
.have_buf:
    mov     qword [rel mp_len], 0
    ; the head
    lea     rsi, [rel h_head]
    call    mp_rule
    call    mp_nl
    lea     rsi, [rel h_source]
    call    mp_str
    mov     rsi, [rbx + ASMCTX_input]
    call    mp_str
    call    mp_nl
    lea     rsi, [rel h_output]
    call    mp_str
    mov     rsi, [rbx + ASMCTX_output]
    call    mp_str
    call    mp_nl
    call    mp_nl
    test    dword [rel map_flags], MAP_ORIGIN
    jz      .no_origin
    lea     rsi, [rel h_origin]
    call    mp_rule
    call    mp_nl
    mov     rax, [rel bin_origin]
    mov     ecx, 8
    call    mp_hex0
    call    mp_nl
    call    mp_nl
.no_origin:
    test    dword [rel map_flags], MAP_SUMMARY
    jz      .no_summary
    lea     rsi, [rel h_summary]
    call    mp_rule
    call    mp_nl
    lea     rsi, [rel h_cols]
    call    mp_str
    xor     r15d, r15d                     ; pass: contents, then nobits
.sum_pass:
    xor     r12d, r12d
.sum_sec:
    call    mp_section
    jc      .sum_next_pass
    jz      .sum_skip
    call    mp_start
    mov     r13, rax
    call    mp_vstart
    mov     ecx, 16
    call    mp_hex
    call    mp_two
    mov     rax, r13
    mov     ecx, 16
    call    mp_hex
    call    mp_two
    mov     rax, r13
    add     rax, [r14 + SECTION_size]
    mov     ecx, 16
    call    mp_hex
    call    mp_two
    mov     rax, [r14 + SECTION_size]
    mov     ecx, 8
    call    mp_hex0
    call    mp_two
    call    mp_class
    call    mp_two
    mov     rsi, [r14 + SECTION_name]
    call    mp_str
    call    mp_nl
.sum_skip:
    inc     r12d
    jmp     .sum_sec
.sum_next_pass:
    inc     r15d
    cmp     r15d, 2
    jb      .sum_pass
    call    mp_nl
.no_summary:
    test    dword [rel map_flags], MAP_SECTIONS
    jz      .no_detail
    lea     rsi, [rel h_detail]
    call    mp_rule
    call    mp_nl
    xor     r15d, r15d
.det_pass:
    xor     r12d, r12d
.det_sec:
    call    mp_section
    jc      .det_next_pass
    jz      .det_skip
    lea     rsi, [rel h_section]
    call    mp_str_rule
    call    mp_nl
    lea     rsi, [rel f_class]
    call    mp_str
    lea     rsi, [rel s_progbits]
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    jne     .det_class
    lea     rsi, [rel s_nobits]
.det_class:
    call    mp_str_trim
    call    mp_nl
    lea     rsi, [rel f_length]
    call    mp_str
    mov     rax, [r14 + SECTION_size]
    mov     ecx, 16
    call    mp_hex
    call    mp_nl
    lea     rsi, [rel f_start]
    call    mp_str
    call    mp_start
    mov     ecx, 16
    call    mp_hex
    call    mp_nl
    ; align: as written (align=); NASM's 4 for a section with contents
    ; other than .text, none for .text and the nobits ones
    lea     rsi, [rel f_align]
    call    mp_str
    mov     rax, [r14 + SECTION_align]
    cmp     rax, 1
    ja      .det_align
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    je      .det_no_align
    mov     rdi, [r14 + SECTION_name]
    lea     rsi, [rel s_text]
    call    mp_streq
    je      .det_no_align
    mov     eax, 4
.det_align:
    mov     ecx, 16
    call    mp_hex
    jmp     .det_follows
.det_no_align:
    lea     rsi, [rel s_undef]
    call    mp_str
.det_follows:
    call    mp_nl
    lea     rsi, [rel f_follows]
    call    mp_str
    mov     rsi, [r14 + SECTION_follows]
    test    rsi, rsi
    jnz     .det_follows_name
    lea     rsi, [rel s_undef]
.det_follows_name:
    call    mp_str
    call    mp_nl
    lea     rsi, [rel f_vstart]
    call    mp_str
    call    mp_vstart
    mov     ecx, 16
    call    mp_hex
    call    mp_nl
    ; valign: a nobits section's 4 (NASM's)
    lea     rsi, [rel f_valign]
    call    mp_str
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    jne     .det_no_valign
    mov     eax, 4
    mov     ecx, 16
    call    mp_hex
    jmp     .det_vfollows
.det_no_valign:
    lea     rsi, [rel s_undef]
    call    mp_str
.det_vfollows:
    call    mp_nl
    lea     rsi, [rel f_vfollows]
    call    mp_str
    lea     rsi, [rel s_undef]
    call    mp_str
    call    mp_nl
    call    mp_nl
.det_skip:
    inc     r12d
    jmp     .det_sec
.det_next_pass:
    inc     r15d
    cmp     r15d, 2
    jb      .det_pass
.no_detail:
    test    dword [rel map_flags], MAP_SYMBOLS
    jz      .write
    lea     rsi, [rel h_symbols]
    call    mp_rule
    call    mp_nl
    ; the absolute ones
    mov     r13d, 0xFFF1
    call    mp_collect
    cmp     qword [rel mp_nsyms], 0
    je      .no_abs
    lea     rsi, [rel h_nosec]
    call    mp_rule
    call    mp_nl
    lea     rsi, [rel h_value]
    call    mp_str
    xor     r12d, r12d
.abs_row:
    cmp     r12, [rel mp_nsyms]
    jae     .abs_done
    mov     rax, [rel mp_syms]
    mov     r13, [rax + r12 * 8]
    mov     rax, [r13 + SYMBOL_value]
    mov     ecx, 8
    call    mp_hex0
    call    mp_two
    mov     rsi, [r13 + SYMBOL_name]
    call    mp_str
    call    mp_nl
    inc     r12
    jmp     .abs_row
.abs_done:
    call    mp_nl
    call    mp_nl
.no_abs:
    ; each section's
    xor     r15d, r15d
.sym_pass:
    xor     r12d, r12d
.sym_sec:
    call    mp_section
    jc      .sym_next_pass
    jz      .sym_skip
    push    r12
    mov     r13d, [r14 + SECTION_index]
    call    mp_collect
    cmp     qword [rel mp_nsyms], 0
    je      .sym_none
    lea     rsi, [rel h_section]
    call    mp_str_rule
    call    mp_nl
    lea     rsi, [rel h_real]
    call    mp_str
    xor     r12d, r12d
.sym_row:
    cmp     r12, [rel mp_nsyms]
    jae     .sym_rows_done
    mov     rax, [rel mp_syms]
    mov     r13, [rax + r12 * 8]
    call    mp_start
    add     rax, [r13 + SYMBOL_value]
    mov     ecx, 16
    call    mp_hex
    call    mp_two
    call    mp_vstart
    add     rax, [r13 + SYMBOL_value]
    mov     ecx, 16
    call    mp_hex
    call    mp_two
    mov     rsi, [r13 + SYMBOL_name]
    call    mp_str
    call    mp_nl
    inc     r12
    jmp     .sym_row
.sym_rows_done:
    call    mp_nl
.sym_none:
    pop     r12
.sym_skip:
    inc     r12d
    jmp     .sym_sec
.sym_next_pass:
    inc     r15d
    cmp     r15d, 2
    jb      .sym_pass
.write:
    mov     rdi, [rel map_file]
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     r12d, edx
    mov     edi, r12d
    mov     rsi, [rel mp_buf]
    mov     rdx, [rel mp_len]
    call    io_write
    mov     r13, rax
    mov     edi, r12d
    call    io_close
    mov     rax, r13
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; mp_section: section r12d of this pass (r15d: 0 contents, 1 nobits) in r14:
; CF set past the last one; ZF set when it is not this pass's
mp_section:
    movzx   eax, word [rbx + ASMCTX_seccount]
    cmp     r12d, eax
    jb      .ms_have
    stc
    ret
.ms_have:
    mov     rax, [rbx + ASMCTX_sections]
    mov     r14, [rax + r12 * 8]
    test    r14, r14
    jz      .ms_skip
    xor     eax, eax
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    sete    al
    cmp     eax, r15d
    jne     .ms_skip
    or      eax, 1                         ; (ZF clear, CF clear)
    ret
.ms_skip:
    xor     eax, eax                       ; (ZF set, CF clear)
    ret

; mp_start: r14's start in the image (its labels' "real" base): rax
mp_start:
    mov     rax, [r14 + SECTION_addr]
    cmp     qword [r14 + SECTION_size], 0
    je      .st_ret
    test    byte [r14 + SECTION_bin_flags], BIN_VSTART
    jz      .st_ret
    mov     rax, [rel bin_origin]
    add     rax, [r14 + SECTION_bin_off]
.st_ret:
    ret

; mp_vstart: r14's address its labels count from: rax
mp_vstart:
    mov     rax, [r14 + SECTION_addr]
    ret

; mp_collect: the symbols of section r13d (0xFFF1: the absolute ones),
; sorted by value, into mp_syms / mp_nsyms
mp_collect:
    push    r12
    push    r15
    mov     qword [rel mp_nsyms], 0
    mov     r15, [rbx + ASMCTX_symtab]
    xor     r12d, r12d
.mc_sym:
    cmp     r12d, [rbx + ASMCTX_symcount]
    jae     .mc_sort
    imul    rax, r12, SYMBOL_SIZE
    add     rax, r15
    inc     r12d
    cmp     byte [rax + SYMBOL_tag], TAG_SYMBOL
    jne     .mc_sym
    cmp     byte [rax + SYMBOL_kind], SYM_EXTERN
    je      .mc_sym
    movzx   ecx, word [rax + SYMBOL_section]
    cmp     ecx, r13d
    jne     .mc_sym
    mov     rcx, [rel mp_nsyms]
    cmp     rcx, MAP_SYMS
    jae     .mc_sort
    mov     rdx, [rel mp_syms]
    mov     [rdx + rcx * 8], rax
    inc     qword [rel mp_nsyms]
    jmp     .mc_sym
.mc_sort:
    ; insertion sort by value (stable: the table's order among equals)
    mov     r15, [rel mp_syms]
    mov     r12d, 1
.mc_outer:
    cmp     r12, [rel mp_nsyms]
    jae     .mc_ret
    mov     rax, [r15 + r12 * 8]
    mov     rdx, [rax + SYMBOL_value]
    mov     rcx, r12
.mc_inner:
    test    rcx, rcx
    jz      .mc_place
    mov     r8, [r15 + rcx * 8 - 8]
    cmp     [r8 + SYMBOL_value], rdx
    jle     .mc_place
    mov     [r15 + rcx * 8], r8
    dec     rcx
    jmp     .mc_inner
.mc_place:
    mov     [r15 + rcx * 8], rax
    inc     r12
    jmp     .mc_outer
.mc_ret:
    pop     r15
    pop     r12
    ret

; mp_class: "progbits" / "nobits  " (r14)
mp_class:
    lea     rsi, [rel s_progbits]
    cmp     dword [r14 + SECTION_elf_type], SHT_NOBITS
    jne     mp_str
    lea     rsi, [rel s_nobits]
    jmp     mp_str

; mp_streq: rdi and rsi the same? ZF
mp_streq:
.se_next:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .se_ret
    test    al, al
    jz      .se_ret
    inc     rdi
    inc     rsi
    jmp     .se_next
.se_ret:
    ret

; ---- output -------------------------------

; mp_putc: al
mp_putc:
    push    rcx
    mov     rcx, [rel mp_len]
    cmp     rcx, MAP_CAP
    jae     .pc_full
    push    rdx
    mov     rdx, [rel mp_buf]
    mov     [rdx + rcx], al
    pop     rdx
    inc     qword [rel mp_len]
.pc_full:
    pop     rcx
    ret

; mp_str: the NUL-terminated rsi (rsi past it)
mp_str:
.s_next:
    mov     al, [rsi]
    test    al, al
    jz      .s_ret
    call    mp_putc
    inc     rsi
    jmp     .s_next
.s_ret:
    ret

; mp_str_trim: rsi without its trailing blanks
mp_str_trim:
    mov     rdi, rsi
.t_end:
    cmp     byte [rdi], 0
    je      .t_back
    inc     rdi
    jmp     .t_end
.t_back:
    cmp     rdi, rsi
    jbe     .t_out
    cmp     byte [rdi - 1], ' '
    jne     .t_out
    dec     rdi
    jmp     .t_back
.t_out:
    cmp     rsi, rdi
    jae     .t_ret
    mov     al, [rsi]
    call    mp_putc
    inc     rsi
    jmp     .t_out
.t_ret:
    ret

mp_nl:
    mov     al, 10
    jmp     mp_putc

mp_two:
    push    rsi
    lea     rsi, [rel s_two]
    call    mp_str
    pop     rsi
    ret

; mp_rule: rsi, then dashes to column 79, and the newline
mp_rule:
    push    r12
    mov     r12, [rel mp_len]
    cmp     byte [rsi], 10
    jne     .r_text
    call    mp_nl                          ; (a leading newline: not counted)
    inc     rsi
    mov     r12, [rel mp_len]
.r_text:
    call    mp_str
    jmp     mp_dashes

; mp_str_rule: rsi and the section's name (r14), then the dashes
mp_str_rule:
    push    r12
    mov     r12, [rel mp_len]
    call    mp_str
    mov     rsi, [r14 + SECTION_name]
    call    mp_str
    mov     al, ' '
    call    mp_putc
mp_dashes:
    ; (r12 = the line's start, pushed by the caller's entry)
.d_more:
    mov     rax, [rel mp_len]
    sub     rax, r12
    cmp     rax, 79
    jae     .d_done
    mov     al, '-'
    call    mp_putc
    jmp     .d_more
.d_done:
    call    mp_nl
    pop     r12
    ret

; mp_hex: rax in upper-case hex, right-aligned in ecx columns
mp_hex:
    push    r8
    mov     r8d, ' '
    jmp     mp_hex_go
; mp_hex0: ... zero-padded
mp_hex0:
    push    r8
    mov     r8d, '0'
mp_hex_go:
    push    rbx
    push    rdx
    push    rsi
    sub     rsp, 32
    lea     rsi, [rsp + 31]
    xor     edx, edx                       ; digits
.h_digit:
    mov     rbx, rax
    and     ebx, 15
    push    rcx
    lea     rcx, [rel hexdig]
    mov     bl, [rcx + rbx]
    pop     rcx
    mov     [rsi], bl
    dec     rsi
    inc     edx
    shr     rax, 4
    jnz     .h_digit
.h_pad:
    cmp     edx, ecx
    jae     .h_out
    mov     [rsi], r8b
    dec     rsi
    inc     edx
    jmp     .h_pad
.h_out:
    inc     rsi
.h_put:
    mov     al, [rsi]
    call    mp_putc
    inc     rsi
    dec     edx
    jnz     .h_put
    add     rsp, 32
    pop     rsi
    pop     rdx
    pop     rbx
    pop     r8
    ret
