;
; ============================================================================
; File        : debug/dwarf.s
; Project     : utasm
; Description : DWARF debug information (-g, -F dwarf) for ELF objects.
;
;   What a debugger needs to step through assembly source:
;
;   .debug_line     the line table (DWARF 3): for every line that made code,
;                   its address and its source file and line -- a macro's
;                   or %rep body's code at its body line, an included
;                   file's in that file, as NASM maps them
;   .debug_info     one compile unit: the source's name, the producer,
;                   DW_LANG_Mips_Assembler (what assemblers use), the line
;                   table's offset and the first code section's range
;   .debug_abbrev   the one abbreviation that unit uses
;   .debug_aranges  the address ranges of every code section
;
;   The rows come from the per-line entries the listing is made from
;   (include/listing.inc): they already follow the code as jump shortening
;   moved it. Addresses and section offsets are relocations against the
;   sections' own symbols (RELOC_FLAG_SECTION), so the linker places them.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/listing.inc"

extern  asmctx_emit_byte
extern  asm_ctx_create_section
extern  reloc_record
extern  str_len
extern  lst_base
extern  lst_count

%define DW_MAX_FILES    256
%define DW_MAX_CODE     32

[SECTION .bss]
alignb 8
global dbg_enabled
dw_ctx:         resq 1
dw_files:       resq DW_MAX_FILES   ; file names, index + 1 = DWARF file
dw_nfiles:      resq 1
dw_code:        resq DW_MAX_CODE    ; the code sections
dw_ncode:       resq 1
dw_line_sec:    resq 1
dw_info_sec:    resq 1
dw_abbrev_sec:  resq 1
dw_aranges_sec: resq 1
dw_saved_sec:   resq 1
dw_addr:        resq 1              ; the line program's state
dw_line:        resq 1
dw_file:        resq 1
dw_rows:        resq 1              ; rows out in this sequence
dbg_enabled:    resb 1              ; -g

[SECTION .text]

;*
; * [dwarf_generate]
; * Purpose: Make the debug sections, when -g asked for them and the output
; *          is an ELF object.
; * Input  : RDI = AsmCtx
; * Output : RAX = EXIT_OK or an error
; ;
global dwarf_generate
dwarf_generate:
    cmp     byte [rel dbg_enabled], 0
    jne     .on
    xor     eax, eax
    ret
.on:
    cmp     byte [rdi + ASMCTX_fmt], FMT_ELF64
    jne     .off
    cmp     byte [rdi + ASMCTX_standalone], 0
    je      .object
.off:
    xor     eax, eax
    ret
.object:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     [rel dw_ctx], rdi
    mov     rax, [rbx + ASMCTX_curr_sec]
    mov     [rel dw_saved_sec], rax

    ; the code sections: executable, with contents
    mov     qword [rel dw_ncode], 0
    movzx   r12d, word [rbx + ASMCTX_seccount]
    mov     r13, [rbx + ASMCTX_sections]
.code_scan:
    test    r12d, r12d
    jz      .code_done
    mov     rax, [r13]
    test    word [rax + SECTION_flags], SHF_EXECINSTR
    jz      .code_next
    cmp     qword [rax + SECTION_size], 0
    je      .code_next
    mov     rcx, [rel dw_ncode]
    cmp     rcx, DW_MAX_CODE
    jae     .code_next
    lea     rdx, [rel dw_code]
    mov     [rdx + rcx*8], rax
    inc     qword [rel dw_ncode]
.code_next:
    add     r13, 8
    dec     r12d
    jmp     .code_scan
.code_done:
    cmp     qword [rel dw_ncode], 0
    je      .done                          ; no code: nothing to describe

    ; the files the code comes from
    call    dw_collect_files

    ; the four sections (made first, so the offsets below are theirs)
    lea     rsi, [rel s_debug_abbrev]
    call    dw_new_section
    jnz     .ret
    mov     [rel dw_abbrev_sec], rdx
    lea     rsi, [rel s_debug_info]
    call    dw_new_section
    jnz     .ret
    mov     [rel dw_info_sec], rdx
    lea     rsi, [rel s_debug_line]
    call    dw_new_section
    jnz     .ret
    mov     [rel dw_line_sec], rdx
    lea     rsi, [rel s_debug_aranges]
    call    dw_new_section
    jnz     .ret
    mov     [rel dw_aranges_sec], rdx

    call    dw_write_abbrev
    call    dw_write_line
    test    rax, rax
    jnz     .ret
    call    dw_write_info
    test    rax, rax
    jnz     .ret
    call    dw_write_aranges
    test    rax, rax
    jnz     .ret
.done:
    xor     eax, eax
.ret:
    mov     rcx, [rel dw_saved_sec]
    mov     [rbx + ASMCTX_curr_sec], rcx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; dw_new_section: a non-allocated PROGBITS section named rsi, made the
; current one; rdx = it (ZF set on success)
dw_new_section:
    mov     rdi, [rel dw_ctx]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     word [rdx + SECTION_flags], 0
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     qword [rdx + SECTION_align], 1
    mov     rdi, [rel dw_ctx]
    mov     [rdi + ASMCTX_curr_sec], rdx
    xor     eax, eax
.ret:
    test    rax, rax
    ret

; dw_collect_files: dw_files = the distinct statement files of the entries
; that made code
dw_collect_files:
    push    rbx
    push    r12
    mov     qword [rel dw_nfiles], 0
    ; the source itself first
    mov     rax, [rel dw_ctx]
    mov     rdi, [rax + ASMCTX_input]
    call    dw_file_index
    mov     rbx, [rel lst_base]
    mov     r12, [rel lst_count]
.entry:
    test    r12, r12
    jz      .done
    mov     rax, [rbx + LE_END]
    cmp     rax, [rbx + LE_START]
    je      .next
    mov     rdi, [rbx + LE_FILE]
    test    rdi, rdi
    jz      .next
    call    dw_file_index
.next:
    add     rbx, LE_SIZE
    dec     r12
    jmp     .entry
.done:
    pop     r12
    pop     rbx
    ret

; dw_file_index: rax = the DWARF file number (1-based) of name rdi, added
; when new; 0 when the table is full
dw_file_index:
    xor     ecx, ecx
    lea     rdx, [rel dw_files]
.find:
    cmp     rcx, [rel dw_nfiles]
    jae     .add
    cmp     [rdx + rcx*8], rdi
    je      .hit
    inc     rcx
    jmp     .find
.add:
    cmp     rcx, DW_MAX_FILES
    jae     .full
    mov     [rdx + rcx*8], rdi
    inc     qword [rel dw_nfiles]
.hit:
    lea     rax, [rcx + 1]
    ret
.full:
    xor     eax, eax
    ret

; ---- .debug_abbrev ----
dw_write_abbrev:
    mov     rax, [rel dw_abbrev_sec]
    mov     rdi, [rel dw_ctx]
    mov     [rdi + ASMCTX_curr_sec], rax
    lea     rsi, [rel abbrev_bytes]
    mov     ecx, abbrev_len
    jmp     dw_bytes

; ---- .debug_line ----
dw_write_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rax, [rel dw_line_sec]
    mov     rdi, [rel dw_ctx]
    mov     [rdi + ASMCTX_curr_sec], rax
    call    dw_u32                         ; unit_length (patched below)
    mov     eax, 3
    call    dw_u16                         ; version
    xor     eax, eax
    call    dw_u32                         ; header_length (patched)
    lea     rsi, [rel line_params]
    mov     ecx, line_params_len
    call    dw_bytes                       ; min length .. opcode lengths
    xor     eax, eax
    call    dw_u8                          ; no include directories
    ; the file names: name, directory 0, time 0, length 0
    xor     r12d, r12d
.file:
    cmp     r12, [rel dw_nfiles]
    jae     .files_done
    lea     rax, [rel dw_files]
    mov     rsi, [rax + r12*8]
    call    dw_cstr
    xor     eax, eax
    call    dw_u8
    xor     eax, eax
    call    dw_u8
    xor     eax, eax
    call    dw_u8
    inc     r12
    jmp     .file
.files_done:
    xor     eax, eax
    call    dw_u8
    ; header_length: from after its own field to here
    mov     rax, [rel dw_line_sec]
    mov     rcx, [rax + SECTION_size]
    sub     rcx, 10
    mov     rdx, [rax + SECTION_data]
    mov     [rdx + 6], ecx

    ; a sequence per code section
    xor     r15d, r15d
.sequence:
    cmp     r15, [rel dw_ncode]
    jae     .program_done
    lea     rax, [rel dw_code]
    mov     r14, [rax + r15*8]             ; the section
    ; DW_LNE_set_address: the section's start, relocated
    mov     eax, 0
    call    dw_u8
    mov     eax, 9
    call    dw_u8
    mov     eax, 2
    call    dw_u8
    mov     rsi, r14
    xor     edx, edx
    mov     r8d, R_X86_64_64
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u64
    mov     qword [rel dw_addr], 0
    mov     qword [rel dw_line], 1
    mov     qword [rel dw_file], 1
    mov     qword [rel dw_rows], 0
    ; a row per statement with code here
    mov     rbx, [rel lst_base]
    mov     r12, [rel lst_count]
.row:
    test    r12, r12
    jz      .rows_done
    cmp     [rbx + LE_SEC], r14
    jne     .row_next
    cmp     byte [rbx + LE_KIND], LK_FIELD
    je      .row_next
    mov     rax, [rbx + LE_END]
    cmp     rax, [rbx + LE_START]
    jbe     .row_next
    mov     rdi, [rbx + LE_FILE]
    test    rdi, rdi
    jz      .row_next
    call    dw_file_index
    test    rax, rax
    jz      .row_next
    mov     r13, rax                       ; file
    mov     eax, [rbx + LE_LINE]
    ; the same position as the row before: no new row
    cmp     qword [rel dw_rows], 0
    je      .new_row
    cmp     r13, [rel dw_file]
    jne     .new_row
    cmp     rax, [rel dw_line]
    je      .row_next
.new_row:
    cmp     r13, [rel dw_file]
    je      .same_file
    mov     eax, 4                         ; DW_LNS_set_file
    call    dw_u8
    mov     rax, r13
    call    dw_uleb
    mov     [rel dw_file], r13
.same_file:
    mov     eax, [rbx + LE_LINE]
    sub     rax, [rel dw_line]
    jz      .same_line
    push    rax
    mov     eax, 3                         ; DW_LNS_advance_line
    call    dw_u8
    pop     rax
    call    dw_sleb
    mov     eax, [rbx + LE_LINE]
    mov     [rel dw_line], rax
.same_line:
    mov     rax, [rbx + LE_START]
    sub     rax, [rel dw_addr]
    jz      .same_addr
    push    rax
    mov     eax, 2                         ; DW_LNS_advance_pc
    call    dw_u8
    pop     rax
    call    dw_uleb
    mov     rax, [rbx + LE_START]
    mov     [rel dw_addr], rax
.same_addr:
    mov     eax, 1                         ; DW_LNS_copy
    call    dw_u8
    inc     qword [rel dw_rows]
.row_next:
    add     rbx, LE_SIZE
    dec     r12
    jmp     .row
.rows_done:
    ; to the end of the section, and the end of the sequence
    mov     rax, [r14 + SECTION_size]
    sub     rax, [rel dw_addr]
    jbe     .ended
    push    rax
    mov     eax, 2
    call    dw_u8
    pop     rax
    call    dw_uleb
.ended:
    xor     eax, eax
    call    dw_u8
    mov     eax, 1
    call    dw_u8
    mov     eax, 1                         ; DW_LNE_end_sequence
    call    dw_u8
    inc     r15
    jmp     .sequence
.program_done:
    ; unit_length
    mov     rax, [rel dw_line_sec]
    mov     rcx, [rax + SECTION_size]
    sub     rcx, 4
    mov     rdx, [rax + SECTION_data]
    mov     [rdx], ecx
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- .debug_info ----
dw_write_info:
    push    rbx
    mov     rax, [rel dw_info_sec]
    mov     rdi, [rel dw_ctx]
    mov     [rdi + ASMCTX_curr_sec], rax
    xor     eax, eax
    call    dw_u32                         ; unit_length (patched)
    mov     eax, 3
    call    dw_u16                         ; version
    mov     rsi, [rel dw_abbrev_sec]       ; debug_abbrev_offset
    xor     edx, edx
    mov     r8d, R_X86_64_32
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u32
    mov     eax, 8
    call    dw_u8                          ; address_size
    mov     eax, 1
    call    dw_uleb                        ; the compile unit DIE
    mov     rax, [rel dw_ctx]
    mov     rsi, [rax + ASMCTX_input]
    call    dw_cstr                        ; DW_AT_name
    lea     rsi, [rel s_producer]
    call    dw_cstr                        ; DW_AT_producer
    mov     eax, 0x8001                    ; DW_LANG_Mips_Assembler
    call    dw_u16
    mov     rsi, [rel dw_line_sec]         ; DW_AT_stmt_list
    xor     edx, edx
    mov     r8d, R_X86_64_32
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u32
    mov     rbx, [rel dw_code]             ; DW_AT_low_pc / high_pc: the
    mov     rsi, rbx                       ; first code section
    xor     edx, edx
    mov     r8d, R_X86_64_64
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u64
    mov     rsi, rbx
    mov     rdx, [rbx + SECTION_size]
    mov     r8d, R_X86_64_64
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u64
    mov     rax, [rel dw_info_sec]
    mov     rcx, [rax + SECTION_size]
    sub     rcx, 4
    mov     rdx, [rax + SECTION_data]
    mov     [rdx], ecx
    xor     eax, eax
.ret:
    pop     rbx
    ret

; ---- .debug_aranges ----
dw_write_aranges:
    push    rbx
    push    r12
    mov     rax, [rel dw_aranges_sec]
    mov     rdi, [rel dw_ctx]
    mov     [rdi + ASMCTX_curr_sec], rax
    xor     eax, eax
    call    dw_u32                         ; unit_length (patched)
    mov     eax, 2
    call    dw_u16                         ; version
    mov     rsi, [rel dw_info_sec]         ; debug_info_offset
    xor     edx, edx
    mov     r8d, R_X86_64_32
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u32
    mov     eax, 8
    call    dw_u8                          ; address_size
    xor     eax, eax
    call    dw_u8                          ; segment_size
    xor     eax, eax
    call    dw_u32                         ; padding to 16
    xor     r12d, r12d
.range:
    cmp     r12, [rel dw_ncode]
    jae     .ranges_done
    lea     rax, [rel dw_code]
    mov     rbx, [rax + r12*8]
    mov     rsi, rbx
    xor     edx, edx
    mov     r8d, R_X86_64_64
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u64
    mov     rax, [rbx + SECTION_size]
    call    dw_u64
    inc     r12
    jmp     .range
.ranges_done:
    xor     eax, eax
    call    dw_u64
    xor     eax, eax
    call    dw_u64
    mov     rax, [rel dw_aranges_sec]
    mov     rcx, [rax + SECTION_size]
    sub     rcx, 4
    mov     rdx, [rax + SECTION_data]
    mov     [rdx], ecx
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret

; ---- writing into the current section ----

; dw_sec_reloc: a relocation at the current position against section rsi
; plus rdx, of type r8d
dw_sec_reloc:
    push    rbx
    mov     rdi, [rel dw_ctx]
    mov     rax, [rdi + ASMCTX_curr_sec]
    mov     rcx, rdx                       ; addend
    mov     rdx, [rsi + SECTION_name]      ; its name: the section's symbol
    mov     rsi, [rax + SECTION_size]
    call    reloc_record
    test    rax, rax
    jnz     .ret
    mov     rdi, [rel dw_ctx]
    mov     eax, [rdi + ASMCTX_nrelocs]
    dec     eax
    imul    rax, rax, RELOC_SIZE
    add     rax, [rdi + ASMCTX_relocs]
    or      byte [rax + RELOC_flags], RELOC_FLAG_SECTION
    xor     eax, eax
.ret:
    pop     rbx
    ret

dw_u8:
    push    rcx
    push    rsi
    push    rdi
    push    rdx
    push    r8
    mov     rdi, [rel dw_ctx]
    movzx   esi, al
    call    asmctx_emit_byte
    pop     r8
    pop     rdx
    pop     rdi
    pop     rsi
    pop     rcx
    ret

dw_u16:
    push    rax
    call    dw_u8
    pop     rax
    shr     eax, 8
    jmp     dw_u8

dw_u32:
    push    rax
    call    dw_u16
    pop     rax
    shr     eax, 16
    jmp     dw_u16

dw_u64:
    push    rax
    call    dw_u32
    pop     rax
    shr     rax, 32
    jmp     dw_u32

; dw_uleb / dw_sleb: rax as (un)signed LEB128
dw_uleb:
    mov     rdx, rax
.byte:
    mov     eax, edx
    and     eax, 0x7F
    shr     rdx, 7
    test    rdx, rdx
    jz      .last
    or      eax, 0x80
    push    rdx
    call    dw_u8
    pop     rdx
    jmp     .byte
.last:
    jmp     dw_u8

dw_sleb:
    mov     rdx, rax
.byte:
    mov     eax, edx
    and     eax, 0x7F
    sar     rdx, 7
    ; done when the rest is all sign and the sign bit of this byte agrees
    test    rdx, rdx
    jnz     .neg
    test    eax, 0x40
    jz      .last
    jmp     .more
.neg:
    cmp     rdx, -1
    jne     .more
    test    eax, 0x40
    jnz     .last
.more:
    or      eax, 0x80
    push    rdx
    call    dw_u8
    pop     rdx
    jmp     .byte
.last:
    jmp     dw_u8

; dw_cstr: the NUL-terminated rsi, with its NUL
dw_cstr:
    push    rsi
.byte:
    mov     rsi, [rsp]
    movzx   eax, byte [rsi]
    inc     qword [rsp]
    push    rax
    call    dw_u8
    pop     rax
    test    eax, eax
    jnz     .byte
    pop     rsi
    ret

; dw_bytes: ecx bytes at rsi
dw_bytes:
    test    ecx, ecx
    jz      .done
    movzx   eax, byte [rsi]
    call    dw_u8
    inc     rsi
    dec     ecx
    jmp     dw_bytes
.done:
    xor     eax, eax
    ret

[SECTION .rodata]
s_debug_abbrev:  db ".debug_abbrev", 0
s_debug_info:    db ".debug_info", 0
s_debug_line:    db ".debug_line", 0
s_debug_aranges: db ".debug_aranges", 0
s_producer:      db "utasm 0.1.0", 0

; abbreviation 1: DW_TAG_compile_unit, no children
abbrev_bytes:
    db 1, 0x11, 0
    db 0x03, 0x08                   ; DW_AT_name         DW_FORM_string
    db 0x25, 0x08                   ; DW_AT_producer     DW_FORM_string
    db 0x13, 0x05                   ; DW_AT_language     DW_FORM_data2
    db 0x10, 0x06                   ; DW_AT_stmt_list    DW_FORM_data4
    db 0x11, 0x01                   ; DW_AT_low_pc       DW_FORM_addr
    db 0x12, 0x01                   ; DW_AT_high_pc      DW_FORM_addr
    db 0, 0
    db 0
abbrev_len equ $ - abbrev_bytes

; the line program's parameters: minimum_instruction_length 1,
; default_is_stmt 1, line_base -5, line_range 14, opcode_base 13, and the
; standard opcodes' operand counts
line_params:
    db 1, 1, -5, 14, 13
    db 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1
line_params_len equ $ - line_params
