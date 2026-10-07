;
; ============================================================================
; File        : backend/output/listing/listing.s
; Project     : utasm
; Description : The listing file (-l): each source line with the offset and
;               the bytes it produced, in NASM's layout.
;
;     5 00000000 B801000000                  mov eax, 1
;    11 00000007 90                  <1>  nop
;    21 00000010 48B888776655443322-         mov rax, 0x1122334455667788
;    21 00000019 11
;    23 00000036 488D35(00000000)            lea rsi, [rel msg]
;    29 00000000 <res 40h>               buf: resb 64
;
; How it is gathered: the preprocessor reports where every token comes
; from (error_track_token -> lst_note). Each time that moves to another
; source line an entry is started, holding the current section and its
; size; the line's bytes are what the section gained before the next
; entry. Lines inside a macro or %rep body get entries of their own when
; the body is expanded, marked <1>. Jump shortening moves code after the
; fact, so it remaps the entries of the section it rewrites (lst_remap).
; Lines that produce no tokens of their own (skipped %if blocks, macro
; definitions) are filled in from the file when the listing is written.
;
; Columns: line (6), offset (8 hex), the bytes (20, 9 bytes a row and a
; '-' where a row breaks), the depth marker (4: "<1> "), the source text.
; A relocated field is shown in (...) when PC-relative, [...] otherwise.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  io_open
extern  io_close
extern  io_write
extern  io_mmap
extern  io_file_size
extern  str_len
extern  str_cmp
extern  global_ctx
extern  relax_map_offset

%include "include/listing.inc"

%define LST_MAX     1000000         ; entries (the mapping is committed lazily)
%define LST_FILES   64              ; files read back at once
%define LF_NAME     0               ; q name
%define LF_BUF      8               ; q contents
%define LF_SIZE     16              ; q length
%define LF_POS      24              ; q where line LF_LINE starts
%define LF_LINE     32              ; q
%define LF_LAST     40              ; q last line listed from the file
%define LF_ENTRY    48
%define OUT_BUF     65536

[SECTION .bss]
alignb 8
global lst_enabled
global lst_file
lst_file:       resq 1              ; -l file
global lst_base
global lst_count
lst_base:       resq 1              ; the entries
lst_count:      resq 1
lst_cur:        resq 1              ; the entry being filled, or 0
lst_lastfile:   resq LST_DEPTHS     ; per include depth: its last line
lst_split:      resb 1              ; a body line ended: start anew
lst_hidden:     resb 1              ; [list -] is on
global lst_parent_exp
alignb 8
lst_parent_exp: resq 1              ; set before a body lst_note: the
                                    ; expansion around the token's own
lst_depth_last: resq LST_DEPTHS     ; writing: last line shown per depth
lst_rcur:       resq 1              ; relocation search cursor
lst_fd:         resq 1
lst_outlen:     resq 1
lst_files:      resb LST_FILES * LF_ENTRY
lst_nfiles:     resq 1
lst_out:        resb OUT_BUF
lst_num:        resb 32
lst_enabled:    resb 1
alignb 8
lst_heap:       resq 1              ; the notes (lst_alloc)
lst_heap_used:  resq 1

[SECTION .text]

;*
; * [lst_line_end]
; * Purpose: A line of a macro or %rep body ended: what follows starts
; *          another entry, even on the same line (the next repetition).
; * Clobbers: nothing
; ;
global lst_line_end
lst_line_end:
    mov     byte [rel lst_split], 1        ; its bytes are not out yet
    ret

;*
; * [lst_listing]
; * Purpose: [list +] (EDI = 1) / [list -] (EDI = 0): the lines after it
; *          are listed or not.
; ;
global lst_listing
lst_listing:
    xor     edi, 1
    mov     [rel lst_hidden], dil
    ret

;*
; * [lst_warning]
; * Purpose: A warning given at the current line: listed after it.
; * Input  : RDI = its text ("warning: ... [-w+class]")
; * Clobbers: rax, rcx, rdx, rsi, rdi, r8-r11
; ;
global lst_warning
lst_warning:
    cmp     byte [rel lst_enabled], 0
    je      .ret
    cmp     qword [rel lst_cur], 0
    je      .ret
    push    rbx
    push    r12
    mov     r12, rdi
    call    str_len
    lea     rdi, [rax + 9]                 ; next, the text, its NUL
    call    lst_alloc
    test    rax, rax
    jz      .out
    mov     qword [rax], 0
    lea     rdi, [rax + 8]
    mov     rsi, r12
.copy:
    mov     cl, [rsi]
    mov     [rdi], cl
    inc     rsi
    inc     rdi
    test    cl, cl
    jnz     .copy
    ; after the line's other warnings
    mov     rcx, [rel lst_cur]
    add     rcx, LE_WARN
.tail:
    cmp     qword [rcx], 0
    je      .link
    mov     rcx, [rcx]
    jmp     .tail
.link:
    mov     [rcx], rax
.out:
    pop     r12
    pop     rbx
.ret:
    ret

;*
; * [lst_uninit]
; * Purpose: The current line's bytes from RDI to RSI (offsets in its
; *          section) are uninitialised ("db ?", resb): listed as "??".
; * Clobbers: rax, rcx, rdx, rdi, r8-r11
; ;
global lst_uninit
lst_uninit:
    cmp     byte [rel lst_enabled], 0
    je      .ret
    mov     rax, [rel lst_cur]
    test    rax, rax
    jz      .ret
    push    rsi
    push    rdi
    mov     edi, 24
    call    lst_alloc
    pop     rdi
    pop     rsi
    test    rax, rax
    jz      .ret
    mov     rcx, [rel lst_cur]
    sub     rdi, [rcx + LE_START]          ; from the entry's start: jump
    sub     rsi, [rcx + LE_START]          ; shortening moves the entry
    mov     [rax], rdi
    mov     [rax + 8], rsi
    mov     rdx, [rcx + LE_UNINIT]
    mov     [rax + 16], rdx
    mov     [rcx + LE_UNINIT], rax
.ret:
    ret

; lst_alloc: rdi bytes (rounded up to 8) for the listing's notes; rax = the
; space, or 0. A region reserved once, committed as it is used.
%define LST_HEAP    (1 << 28)
lst_alloc:
    add     rdi, 7
    and     rdi, -8
    mov     rax, [rel lst_heap]
    test    rax, rax
    jnz     .room
    push    rdi
    xor     edi, edi
    mov     rsi, LST_HEAP
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS | 0x4000   ; MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    pop     rdi
    test    rax, rax
    jnz     .none
    mov     [rel lst_heap], rdx
    mov     rax, rdx
.room:
    mov     rcx, [rel lst_heap_used]
    lea     rdx, [rcx + rdi]
    cmp     rdx, LST_HEAP
    ja      .none
    mov     [rel lst_heap_used], rdx
    add     rax, rcx
    ret
.none:
    xor     eax, eax
    ret

;*
; * [lst_field]
; * Purpose: The current line lays out a structure field (struc): show
; *          its offset and size as reserved space.
; * Input  : RDI = offset, RSI = size
; ;
global lst_field
lst_field:
    mov     rax, [rel lst_cur]
    test    rax, rax
    jz      .none
    mov     qword [rax + LE_SEC], 0
    mov     [rax + LE_START], rdi
    add     rsi, rdi
    mov     [rax + LE_END], rsi
    mov     byte [rax + LE_KIND], LK_FIELD
.none:
    ret

;*
; * [lst_mark]
; * Purpose: How the current line's bytes are shown (incbin, align).
; * Input  : EDI = LK_*
; ;
global lst_mark
lst_mark:
    mov     rax, [rel lst_cur]
    test    rax, rax
    jz      .none
    mov     [rax + LE_KIND], dil
.none:
    ret

;*
; * [lst_rep_tick]
; * Purpose: One more repetition of a times line (90<rep 3h>).
; * Clobbers: nothing
; ;
global lst_rep_tick
lst_rep_tick:
    cmp     byte [rel lst_enabled], 0
    je      .ret
    push    rax
    mov     rax, [rel lst_cur]
    test    rax, rax
    jz      .done
    inc     dword [rax + LE_REPS]
.done:
    pop     rax
.ret:
    ret

;*
; * [lst_note]
; * Purpose: The token now read comes from this line: start a new entry
; *          when that is another line than the current entry's.
; * Input  : RDI = file, ESI = line, EDX = depth, ECX = 1 for a macro or
; *          %rep body line
; * Clobbers: nothing (the preprocessor calls it mid-flight)
; ;
global lst_note
lst_note:
    cmp     byte [rel lst_enabled], 0
    jne     .on
    ret
.on:
    test    rdi, rdi
    jnz     .named
    ret
.named:
    push    rax
    push    r8
    push    r9
    push    r10
    push    r11
    mov     r8, [rel lst_cur]
    test    r8, r8
    jz      .fresh
    cmp     byte [rel lst_split], 0
    jne     .close                         ; the next repetition of a line
    cmp     [r8 + LE_FILE], rdi
    jne     .close
    cmp     [r8 + LE_LINE], esi
    jne     .close
    cmp     [r8 + LE_DEPTH], dl
    jne     .close
    cmp     [r8 + LE_BODY], cl
    je      .ret                           ; the same line still
.close:
    call    lst_close_current
    mov     qword [rel lst_cur], 0
.fresh:
    mov     byte [rel lst_split], 0
    ; the rest of a file line already listed (after a macro call or an
    ; %include on it): nothing new
    test    ecx, ecx
    jnz     .new
    movzx   eax, dl
    cmp     eax, LST_DEPTHS
    jae     .new
    lea     r8, [rel lst_lastfile]
    mov     r8, [r8 + rax*8]
    test    r8, r8
    jz      .new
    cmp     [r8 + LE_FILE], rdi
    jne     .new
    cmp     [r8 + LE_LINE], esi
    je      .ret
.new:
    mov     r8, [rel lst_base]
    test    r8, r8
    jnz     .room
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    xor     edi, edi
    mov     rsi, LST_MAX * LE_SIZE
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS | 0x4000   ; MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    mov     r8, rdx
    test    rax, rax
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    jnz     .off                           ; no memory: no listing
    mov     [rel lst_base], r8
.room:
    mov     rax, [rel lst_count]
    cmp     rax, LST_MAX
    jae     .ret
    imul    rax, rax, LE_SIZE
    add     r8, rax
    inc     qword [rel lst_count]
    mov     [r8 + LE_FILE], rdi
    mov     [r8 + LE_LINE], esi
    mov     [r8 + LE_DEPTH], dl
    mov     [r8 + LE_BODY], cl
    lea     rax, [rel global_ctx]
    mov     r9, [rax + ASMCTX_curr_sec]
    mov     [r8 + LE_SEC], r9
    xor     eax, eax
    test    r9, r9
    jz      .start
    mov     rax, [r9 + SECTION_size]
.start:
    mov     [r8 + LE_START], rax
    mov     [r8 + LE_END], rax
    mov     [rel lst_cur], r8
    mov     qword [r8 + LE_WARN], 0
    mov     qword [r8 + LE_UNINIT], 0
    mov     dword [r8 + LE_REPS], 0
    mov     byte [r8 + LE_KIND], LK_CODE
    mov     al, [rel lst_hidden]
    mov     [r8 + LE_HIDE], al
    test    ecx, ecx
    jnz     .body
    movzx   eax, dl
    cmp     eax, LST_DEPTHS
    jae     .ret
    lea     r9, [rel lst_lastfile]
    mov     [r9 + rax*8], r8
    jmp     .ret
.body:
    ; a nested body: how far the enclosing body was read
    mov     qword [r8 + LE_PFILE], 0
    mov     r9, [rel lst_parent_exp]
    test    r9, r9
    jz      .no_parent
    mov     r10, [r9 + MACROEXP_body]      ; index of its next token
    test    r10, r10
    jz      .no_parent
    dec     r10
    imul    r10, r10, TOKEN_SIZE
    mov     r11, [r9 + MACROEXP_macro]
    add     r10, [r11 + MACRO_tokens]
    mov     r11, [r10 + TOKEN_file]
    mov     [r8 + LE_PFILE], r11
    mov     r11d, [r10 + TOKEN_line]
    mov     [r8 + LE_PLINE], r11d
.no_parent:
    ; the file lines read before the expansion began (the %rep block)
    ; are listed before it
    extern  global_prep
    lea     rax, [rel global_prep]
    mov     rax, [rax + PREP_lexer]
    mov     r9, [rax + LEXER_file]
    mov     [r8 + LE_FILLFILE], r9
    ; up to the lexer's line when it has read into it (%endrep), else
    ; up to the line before (a macro call's newline is consumed)
    movzx   r9d, word [rax + LEXER_col]
    mov     eax, [rax + LEXER_line]
    cmp     r9d, 1
    ja      .fill_to
    dec     eax
.fill_to:
    mov     [r8 + LE_FILLTO], eax
.ret:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rax
    ret
.off:
    mov     byte [rel lst_enabled], 0
    jmp     .ret

; lst_close_current: the current entry's bytes end where its section is now
lst_close_current:
    mov     r8, [rel lst_cur]
    test    r8, r8
    jz      .done
    mov     r9, [r8 + LE_SEC]
    test    r9, r9
    jz      .done
    mov     rax, [r9 + SECTION_size]
    mov     [r8 + LE_END], rax
.done:
    ret

;*
; * [lst_close]
; * Purpose: The source is read: close the last entry.
; ;
global lst_close
lst_close:
    push    r8
    push    r9
    call    lst_close_current
    mov     qword [rel lst_cur], 0
    pop     r9
    pop     r8
    ret

;*
; * [lst_remap]
; * Purpose: Jump shortening rewrote this section: move its entries to the
; *          new layout (relax_map_offset is valid while it runs).
; * Input  : RDI = SECTION*
; ;
global lst_remap
lst_remap:
    cmp     byte [rel lst_enabled], 0
    je      .none
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     rbx, [rel lst_base]
    mov     r13, [rel lst_count]
.entry:
    test    r13, r13
    jz      .done
    cmp     [rbx + LE_SEC], r12
    jne     .next
    mov     rdi, [rbx + LE_START]
    call    relax_map_offset
    mov     [rbx + LE_START], rax
    mov     rdi, [rbx + LE_END]
    call    relax_map_offset
    mov     [rbx + LE_END], rax
.next:
    add     rbx, LE_SIZE
    dec     r13
    jmp     .entry
.done:
    pop     r13
    pop     r12
    pop     rbx
.none:
    ret

;*
; * [lst_write]
; * Purpose: Write the listing file.
; * Input  : RDI = AsmCtx
; * Output : RAX = EXIT_OK or an error
; ;
global lst_write
lst_write:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     rdi, [rel lst_file]
    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    test    rax, rax
    jnz     .ret
    mov     [rel lst_fd], rdx
    mov     qword [rel lst_outlen], 0
    mov     qword [rel lst_rcur], 0

    mov     r12, [rel lst_base]
    mov     r13, [rel lst_count]
.entry:
    test    r13, r13
    jz      .finish
    cmp     byte [r12 + LE_HIDE], 0
    je      .shown
    ; inside [list -]: not shown, and not filled in later either
    cmp     byte [r12 + LE_BODY], 0
    jne     .skip_entry
    mov     rdi, [r12 + LE_FILE]
    call    lst_file_slot
    test    rax, rax
    jz      .skip_entry
    mov     ecx, [r12 + LE_LINE]
    cmp     rcx, [rax + LF_LAST]
    jbe     .skip_entry
    mov     [rax + LF_LAST], rcx
    jmp     .skip_entry
.shown:
    ; a line of the file itself: first the lines it skipped (a false
    ; %if, a macro definition), as text; a body line: first the lines of
    ; the file read before the expansion began (the %rep block itself)
    mov     rdi, [r12 + LE_FILE]
    mov     ebx, [r12 + LE_LINE]
    xor     ecx, ecx                       ; up to and with the line
    cmp     byte [r12 + LE_BODY], 0
    je      .gap_file
    mov     rdi, [r12 + LE_FILLFILE]
    mov     ebx, [r12 + LE_FILLTO]
    inc     ebx                            ; with the lexer's line
    test    rdi, rdi
    jz      .print
.gap_file:
    push    rcx
    call    lst_file_slot
    pop     rcx
    test    rax, rax
    jz      .print
    mov     r14, rax                       ; r14 = the file's slot
    mov     r15, [r14 + LF_LAST]
    ; a file line listed already (the %endrep a %rep's expansion listed
    ; ahead of itself) and without bytes: not again
    cmp     byte [r12 + LE_BODY], 0
    jne     .gap
    cmp     rbx, r15
    ja      .gap
    mov     rax, [r12 + LE_END]
    cmp     rax, [r12 + LE_START]
    jne     .gap
    jmp     .skip_entry
.gap:
    inc     r15
    cmp     r15, rbx
    jae     .gap_done
    mov     rdi, r15
    xor     esi, esi
    cmp     byte [r12 + LE_BODY], 0
    jne     .gap_row
    movzx   esi, byte [r12 + LE_DEPTH]
.gap_row:
    mov     rdx, r14
    call    lst_text_row
    jmp     .gap
.gap_done:
    ; the line is listed now (a file line), or the lexer's (a body line)
    cmp     byte [r12 + LE_BODY], 0
    je      .gap_mark
    dec     rbx
.gap_mark:
    cmp     rbx, [r14 + LF_LAST]
    jbe     .print
    mov     [r14 + LF_LAST], rbx
.print:
    call    lst_body_fill
    mov     rdi, r12
    call    lst_entry
.skip_entry:
    add     r12, LE_SIZE
    dec     r13
    jmp     .entry
.finish:
    call    lst_flush
    mov     rdi, [rel lst_fd]
    call    io_close
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- lst_body_fill: before entry r12 ----
; A file line starts the body bookkeeping afresh. A body line at depth d
; first lists the lines of the body around it (depth d-1) that were read
; without entries of their own -- an inner %rep block -- then becomes the
; last line shown at its depth; the depths inside it start afresh.
lst_body_fill:
    push    rbx
    push    r14
    push    r15
    lea     rbx, [rel lst_depth_last]
    movzx   ecx, byte [r12 + LE_DEPTH]
    cmp     byte [r12 + LE_BODY], 0
    jne     .body
    xor     ecx, ecx
    jmp     .clear_from
.body:
    cmp     ecx, LST_DEPTHS
    jae     .done
    cmp     ecx, 2
    jb      .own
    mov     rdi, [r12 + LE_PFILE]
    test    rdi, rdi
    jz      .own
    push    rcx
    call    lst_file_slot
    pop     rcx
    test    rax, rax
    jz      .own
    mov     r14, rax                       ; the file
    mov     r15, [rbx + rcx*8 - 8]         ; last line shown at depth d-1
    mov     eax, [r12 + LE_PLINE]
    cmp     r15, rax
    jae     .own                           ; nothing new above
.fill:
    inc     r15
    mov     eax, [r12 + LE_PLINE]
    cmp     r15, rax
    ja      .filled
    push    rcx
    mov     rdi, r15
    or      edi, 0x80000000                ; a body line: trimmed
    lea     esi, [rcx - 1]
    mov     rdx, r14
    call    lst_text_row
    pop     rcx
    jmp     .fill
.filled:
    mov     eax, [r12 + LE_PLINE]
    mov     [rbx + rcx*8 - 8], rax
.own:
    mov     eax, [r12 + LE_LINE]
    mov     [rbx + rcx*8], rax
    inc     ecx
.clear_from:
    cmp     ecx, LST_DEPTHS
    jae     .done
    mov     qword [rbx + rcx*8], 0
    inc     ecx
    jmp     .clear_from
.done:
    pop     r15
    pop     r14
    pop     rbx
    ret

; ---- lst_entry: one entry's rows (rdi = entry) ----
lst_entry:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     rdi, [rbx + LE_FILE]
    call    lst_file_slot
    mov     r15, rax                       ; the file, or 0
    mov     r12, [rbx + LE_SEC]
    mov     r13, [rbx + LE_START]
    mov     r14, [rbx + LE_END]
    cmp     byte [rbx + LE_KIND], LK_FIELD
    jne     .in_section
    cmp     r14, r13
    ja      .reserved
    jmp     .text_only
.in_section:
    test    r12, r12
    jz      .text_only
    cmp     r14, r13
    jbe     .text_only
    cmp     dword [r12 + SECTION_elf_type], SHT_NOBITS
    je      .reserved
    ; all of it uninitialised ("dt ?", "resb 16" outside .bss): shown as
    ; .bss space is; a times line keeps its "????<rep 2h>"
    cmp     dword [rbx + LE_REPS], 0
    jne     .not_all_uninit
    mov     rax, [rbx + LE_UNINIT]
    test    rax, rax
    jz      .not_all_uninit
    xor     ecx, ecx
.uninit_sum:
    add     rcx, [rax + 8]
    sub     rcx, [rax]
    mov     rax, [rax + 16]
    test    rax, rax
    jnz     .uninit_sum
    mov     rax, r14
    sub     rax, r13
    cmp     rcx, rax
    je      .reserved
.not_all_uninit:

    ; incbin: "<bin Nh>"; align padding: its byte and "<rep Nh>"
    cmp     byte [rbx + LE_KIND], LK_BIN
    je      .binary
    cmp     byte [rbx + LE_KIND], LK_FILL
    jne     .not_fill
    mov     rax, r14
    sub     rax, r13
    cmp     rax, 1
    jbe     .rows
    mov     [rbx + LE_REPS], eax
    lea     r14, [r13 + 1]
    jmp     .repeated
.not_fill:

    ; times N: one repetition's bytes and "<rep Nh>", as NASM shows it
    mov     ecx, [rbx + LE_REPS]
    cmp     ecx, 1
    jbe     .rows
    mov     rax, r14
    sub     rax, r13
    xor     edx, edx
    div     rcx
    test    rdx, rdx
    jnz     .rows
    cmp     rax, 9
    ja      .rows
    lea     r14, [r13 + rax]               ; one repetition
    jmp     .repeated

.rows:

    ; rows of up to 18 hex digits; a relocated field is one group
    xor     ecx, ecx                       ; ecx = 1 after the first row
.row:
    push    rcx
    mov     edi, [rbx + LE_LINE]
    call    lst_put_lineno
    mov     rdi, r13
    call    lst_put_offset
    pop     rcx
    lea     rdi, [rel lst_row]
    xor     r8d, r8d                       ; characters in the row
.item:
    cmp     r13, r14
    jae     .row_end
    push    rcx
    push    rdi
    push    r8
    mov     rdi, r12
    mov     rsi, r13
    call    lst_reloc_at                   ; eax = width, edx = 1 PC-relative
    mov     [rel lst_value], r8            ; ... the value shown
    pop     r8
    pop     rdi
    pop     rcx
    test    eax, eax
    jz      .plain
    mov     r9d, eax
    lea     r10d, [r9 + r9 + 2]            ; "(" hex ")"
    lea     r11d, [r8 + r10]
    cmp     r11d, 18
    jbe     .group
    test    r8d, r8d
    jz      .group
    dec     qword [rel lst_rcur]           ; the field opens the next row
    jmp     .row_break
.group:
    mov     al, '['
    test    edx, edx
    jz      .open
    mov     al, '('
.open:
    stosb
    add     r13, r9                        ; the field's stored bytes...
    mov     r11, [rel lst_value]           ; ... shown as its value
.group_byte:
    mov     eax, r11d
    shr     eax, 4
    and     eax, 15
    lea     rsi, [rel lst_hexdig]
    mov     al, [rsi + rax]
    stosb
    mov     eax, r11d
    and     eax, 15
    mov     al, [rsi + rax]
    stosb
    shr     r11, 8
    dec     r9d
    jnz     .group_byte
    mov     al, ']'
    test    edx, edx
    jz      .close
    mov     al, ')'
.close:
    stosb
    add     r8d, r10d
    jmp     .item
.plain:
    cmp     r8d, 18
    jae     .row_break
    call    .byte_hex
    add     r8d, 2
    jmp     .item
.row_break:
    mov     al, '-'
    stosb
    inc     r8d
.row_end:
    ; pad the bytes to 20 columns on the first row (19 after)
    mov     r9d, 20
    test    ecx, ecx
    jz      .pad
    mov     r9d, 19
.pad:
    cmp     r8d, r9d
    jae     .padded
    mov     al, ' '
    stosb
    inc     r8d
    jmp     .pad
.padded:
    push    rcx
    lea     rsi, [rel lst_row]
    mov     rdx, rdi
    sub     rdx, rsi
    call    lst_put
    pop     rcx
    test    ecx, ecx
    jnz     .continued
    movzx   edi, byte [rbx + LE_DEPTH]
    call    lst_put_marker
    mov     rdi, rbx
    mov     rsi, r15
    call    lst_put_source
.continued:
    call    lst_put_newline
    mov     ecx, 1
    cmp     r13, r14
    jb      .row
    jmp     .done

.repeated:
    mov     edi, [rbx + LE_LINE]
    call    lst_put_lineno
    mov     rdi, r13
    call    lst_put_offset
    lea     rdi, [rel lst_row]
.rep_byte:
    cmp     r13, r14
    jae     .rep_count
    push    rdi
    mov     rdi, r12
    mov     rsi, r13
    call    lst_reloc_at
    pop     rdi
    test    eax, eax
    jz      .rep_plain
    ; a relocated field of the repetition: [value] / (value)
    mov     r9d, eax
    mov     r11, r8
    mov     al, '['
    test    edx, edx
    jz      .rep_open
    mov     al, '('
.rep_open:
    stosb
    add     r13, r9
    lea     rsi, [rel lst_hexdig]
.rep_field:
    mov     eax, r11d
    shr     eax, 4
    and     eax, 15
    mov     al, [rsi + rax]
    stosb
    mov     eax, r11d
    and     eax, 15
    mov     al, [rsi + rax]
    stosb
    shr     r11, 8
    dec     r9d
    jnz     .rep_field
    mov     al, ']'
    test    edx, edx
    jz      .rep_close
    mov     al, ')'
.rep_close:
    stosb
    jmp     .rep_byte
.rep_plain:
    call    .byte_hex
    jmp     .rep_byte
.rep_count:
    mov     dword [rdi], '<rep'
    mov     byte [rdi + 4], ' '
    add     rdi, 5
    mov     eax, [rbx + LE_REPS]
    call    lst_hex_trimmed
    mov     byte [rdi], 'h'
    mov     byte [rdi + 1], '>'
    add     rdi, 2
    jmp     .field_out

.binary:
    mov     edi, [rbx + LE_LINE]
    call    lst_put_lineno
    mov     rdi, r13
    call    lst_put_offset
    lea     rdi, [rel lst_row]
    mov     dword [rdi], '<bin'
    jmp     .sized

.reserved:
    ; space without contents (.bss): "??" a byte up to 8, else "<res Nh>"
    mov     edi, [rbx + LE_LINE]
    call    lst_put_lineno
    mov     rdi, r13
    ; "absolute ADDR" counts from ADDR
    test    r12, r12
    jz      .res_offset
    extern  abs_section
    cmp     r12, [rel abs_section]
    jne     .res_offset
    add     rdi, [r12 + SECTION_addr]
.res_offset:
    call    lst_put_offset
    lea     rdi, [rel lst_row]
    mov     rax, r14
    sub     rax, r13
    cmp     rax, 8
    ja      .res_big
.res_q:
    mov     word [rdi], '??'
    add     rdi, 2
    dec     rax
    jnz     .res_q
    jmp     .field_out
.res_big:
    mov     dword [rdi], '<res'
.sized:
    mov     byte [rdi + 4], ' '
    add     rdi, 5
    mov     rax, r14
    sub     rax, r13
    call    lst_hex_trimmed
    mov     byte [rdi], 'h'
    mov     byte [rdi + 1], '>'
    add     rdi, 2
.field_out:
    lea     rsi, [rel lst_row]
    mov     rdx, rdi
    sub     rdx, rsi
.res_pad:
    cmp     rdx, 20
    jae     .res_out
    mov     byte [rdi], ' '
    inc     rdi
    inc     rdx
    jmp     .res_pad
.res_out:
    call    lst_put
    movzx   edi, byte [rbx + LE_DEPTH]
    call    lst_put_marker
    mov     rdi, rbx
    mov     rsi, r15
    call    lst_put_source
    call    lst_put_newline
    jmp     .done

.text_only:
    test    r15, r15
    jz      .done                          ; no file to show it from
    mov     edi, [rbx + LE_LINE]
    cmp     byte [rbx + LE_BODY], 0
    je      .text_plain
    or      edi, 0x80000000                ; a body line: trimmed
.text_plain:
    movzx   esi, byte [rbx + LE_DEPTH]
    mov     rdx, r15
    call    lst_text_row_entry
.done:
    ; its warnings, after its rows:
    ;      3          ******************       warning: ... [-w+zeroing]
    mov     r12, [rbx + LE_WARN]
.warning:
    test    r12, r12
    jz      .warned
    mov     edi, [rbx + LE_LINE]
    call    lst_put_lineno
    lea     rsi, [rel lst_warn_mark]
    mov     edx, lst_warn_mark_len
    call    lst_put
    movzx   edi, byte [rbx + LE_DEPTH]     ; "<1> " in a macro's lines
    call    lst_put_marker
    lea     rsi, [rel lst_blank]
    mov     edx, 1
    call    lst_put
    lea     rdi, [r12 + 8]
    call    str_len
    mov     edx, eax
    lea     rsi, [r12 + 8]
    call    lst_put
    call    lst_put_newline
    mov     r12, [r12]
    jmp     .warning
.warned:
    ; the other repetitions' relocations are behind us
    mov     rdi, [rbx + LE_SEC]
    mov     rsi, [rbx + LE_END]
    call    lst_reloc_skip
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .byte_hex: the byte at r12's data + r13, as two hex digits at rdi; r13++;
; "??" for a byte a "db ?" or a resb left uninitialised, as NASM lists it
.byte_hex:
    mov     rax, [rbx + LE_UNINIT]
    test    rax, rax
    jz      .initialised
    push    rcx
    mov     rcx, r13
    sub     rcx, [rbx + LE_START]
.uninit:
    test    rax, rax
    jz      .uninit_none
    cmp     rcx, [rax]
    jb      .uninit_next
    cmp     rcx, [rax + 8]
    jb      .uninit_byte
.uninit_next:
    mov     rax, [rax + 16]
    jmp     .uninit
.uninit_byte:
    pop     rcx
    inc     r13
    mov     ax, '??'
    stosw
    ret
.uninit_none:
    pop     rcx
.initialised:
    mov     rax, [r12 + SECTION_data]
    movzx   eax, byte [rax + r13]
    inc     r13
    push    rax
    shr     eax, 4
    lea     rsi, [rel lst_hexdig]
    mov     al, [rsi + rax]
    stosb
    pop     rax
    and     eax, 15
    mov     al, [rsi + rax]
    stosb
    ret

; lst_text_row_entry: a row without bytes for an entry's line (edi =
; line, esi = depth, rdx = file slot); an expansion line too
lst_text_row_entry:
    push    rbx
    mov     rbx, rdx
    push    rsi
    push    rdi
    and     edi, 0x7FFFFFFF                ; without the "trim" flag
    call    lst_put_lineno
    lea     rsi, [rel lst_blank]
    mov     edx, 29                        ; offset and bytes columns
    call    lst_put
    pop     rdi
    pop     rsi
    push    rdi
    mov     edi, esi
    call    lst_put_marker
    pop     rdi
    mov     rsi, rbx
    call    lst_put_line_text
    call    lst_put_newline
    pop     rbx
    ret

; lst_text_row: the same, for a line the entries skipped (rdi = line,
; esi = depth, rdx = file slot)
lst_text_row:
    jmp     lst_text_row_entry

; lst_put_source: an entry's source text (rdi = entry, rsi = slot or 0);
; a body line has its indentation cut to one blank, as NASM shows it
lst_put_source:
    test    rsi, rsi
    jz      .none
    push    rbx
    mov     rbx, rdi
    mov     edi, [rbx + LE_LINE]
    cmp     byte [rbx + LE_BODY], 0
    je      .plain
    or      edi, 0x80000000                ; "trimmed" flag
.plain:
    call    lst_put_line_text
    pop     rbx
.none:
    ret

; lst_put_line_text: line edi (bit 31: trim its indentation to one
; blank) of the file in slot rsi
lst_put_line_text:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rsi
    mov     r13d, edi
    and     edi, 0x7FFFFFFF
    mov     r12d, edi
    ; walk to the line from the remembered position (or the start)
    mov     rax, [rbx + LF_LINE]
    cmp     r12, rax
    jae     .walk
    mov     qword [rbx + LF_LINE], 1
    mov     qword [rbx + LF_POS], 0
.walk:
    mov     rsi, [rbx + LF_BUF]
    mov     rcx, [rbx + LF_POS]
    mov     rdx, [rbx + LF_SIZE]
.seek:
    cmp     [rbx + LF_LINE], r12
    jae     .found
    cmp     rcx, rdx
    jae     .missing
    cmp     byte [rsi + rcx], 10
    lea     rcx, [rcx + 1]
    jne     .seek
    inc     qword [rbx + LF_LINE]
    mov     [rbx + LF_POS], rcx
    jmp     .seek
.found:
    ; the line: [rcx, end of line)
    mov     r8, rcx
.eol:
    cmp     r8, rdx
    jae     .have
    cmp     byte [rsi + r8], 10
    je      .have
    inc     r8
    jmp     .eol
.have:
    cmp     r8, rcx
    jbe     .out
    cmp     byte [rsi + r8 - 1], 13        ; CRLF
    jne     .trim
    dec     r8
.trim:
    test    r13d, 0x80000000
    jz      .out
    mov     r9, rcx                        ; where the indentation starts
.skip_blank:
    cmp     rcx, r8
    jae     .out
    cmp     byte [rsi + rcx], ' '
    je      .blank
    cmp     byte [rsi + rcx], 9
    jne     .indented
.blank:
    inc     rcx
    jmp     .skip_blank
.indented:
    cmp     rcx, r9
    je      .out                           ; none: none
.one_blank:
    push    rsi
    push    rcx
    push    r8
    lea     rsi, [rel lst_blank]
    mov     edx, 1
    call    lst_put
    pop     r8
    pop     rcx
    pop     rsi
.out:
    lea     rsi, [rsi + rcx]
    mov     rdx, r8
    sub     rdx, rcx
    call    lst_put
.missing:
    pop     r13
    pop     r12
    pop     rbx
    ret

; lst_file_slot: rax = the slot of file rdi, read in on first use (0 when
; it cannot be read, e.g. the command line's prelude)
lst_file_slot:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    lea     rbx, [rel lst_files]
    xor     r13d, r13d
.find:
    cmp     r13, [rel lst_nfiles]
    jae     .load
    cmp     [rbx + LF_NAME], r12
    je      .hit
    add     rbx, LF_ENTRY
    inc     r13
    jmp     .find
.load:
    cmp     r13, LST_FILES
    jae     .none
    mov     rdi, r12
    xor     esi, esi
    xor     edx, edx
    call    io_open
    test    rax, rax
    jnz     .none
    mov     r13, rdx                       ; fd
    mov     rdi, r13
    call    io_file_size
    test    rax, rax
    jnz     .close_none
    mov     [rbx + LF_SIZE], rdx
    xor     eax, eax
    mov     [rbx + LF_BUF], rax
    test    rdx, rdx
    jz      .loaded
    xor     edi, edi
    mov     rsi, rdx
    mov     edx, PROT_READ
    mov     ecx, MAP_PRIVATE
    mov     r8, r13
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .close_none
    mov     [rbx + LF_BUF], rdx
.loaded:
    mov     rdi, r13
    call    io_close
    mov     [rbx + LF_NAME], r12
    mov     qword [rbx + LF_POS], 0
    mov     qword [rbx + LF_LINE], 1
    mov     qword [rbx + LF_LAST], 0
    inc     qword [rel lst_nfiles]
.hit:
    mov     rax, rbx
    jmp     .ret
.close_none:
    mov     rdi, r13
    call    io_close
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; lst_reloc_at: is a relocation recorded at (section rdi, offset rsi)?
; eax = its width (0: none), edx = 1 when PC-relative, r8 = the value
; NASM shows: the symbol's offset in its section (when it is defined
; here) plus the addend for an absolute field. Relocations are recorded
; in the order the code is, so the search goes on from the last one
; found, a little way.
lst_reloc_at:
    push    rbx
    lea     rax, [rel global_ctx]
    mov     r8, [rax + ASMCTX_relocs]
    mov     r9d, [rax + ASMCTX_nrelocs]
    mov     r10, [rel lst_rcur]
    lea     r11, [r10 + 256]
.scan:
    cmp     r10, r9
    jae     .none
    cmp     r10, r11
    jae     .none
    mov     rbx, r10
    imul    rbx, rbx, RELOC_SIZE
    add     rbx, r8
    cmp     [rbx + RELOC_section], rdi
    jne     .next
    cmp     [rbx + RELOC_offset], rsi
    je      .found
.next:
    inc     r10
    jmp     .scan
.found:
    inc     r10
    mov     [rel lst_rcur], r10
    call    lst_reloc_value
    mov     ecx, [rbx + RELOC_type]
    mov     eax, 4
    xor     edx, edx
    cmp     ecx, 1                         ; R_X86_64_64
    jne     .t2
    mov     eax, 8
    jmp     .ret
.t2:
    cmp     ecx, 2                         ; PC32
    je      .pc
    cmp     ecx, 4                         ; PLT32
    je      .pc
    cmp     ecx, 9                         ; GOTPCREL
    je      .pc
    cmp     ecx, 12                        ; 16
    je      .w2
    cmp     ecx, 13                        ; PC16
    je      .pc2
    cmp     ecx, 14                        ; 8
    je      .w1
    cmp     ecx, 15                        ; PC8
    je      .pc1
    cmp     ecx, 24                        ; PC64
    jne     .ret
    mov     eax, 8
    jmp     .pc
.pc2:
    mov     eax, 2
    jmp     .pc
.pc1:
    mov     eax, 1
.pc:
    mov     edx, 1
    jmp     .ret
.w2:
    mov     eax, 2
    jmp     .ret
.w1:
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
    xor     edx, edx
    xor     r8d, r8d
    pop     rbx
    ret
.ret:
    test    edx, edx
    jz      .absolute
    mov     r8, [rel lst_symval]           ; PC-relative: the symbol alone
    pop     rbx
    ret
.absolute:
    mov     r8, [rel lst_symval]
    add     r8, [rbx + RELOC_addend]
    pop     rbx
    ret

; lst_reloc_value: lst_symval = the offset of relocation rbx's symbol in
; its section when it is defined here, else 0
lst_reloc_value:
    push    rdi
    push    rsi
    push    rcx
    push    r9
    push    r10
    push    r11
    mov     qword [rel lst_symval], 0
    lea     rdi, [rel global_ctx]
    mov     rsi, [rbx + RELOC_sym]
    test    rsi, rsi
    jz      .done
    extern  symbol_find
    call    symbol_find
    test    rax, rax
    jnz     .done
    cmp     word [rdx + SYMBOL_section], 0
    je      .done
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    je      .done
    mov     rax, [rdx + SYMBOL_value]
    mov     [rel lst_symval], rax
.done:
    pop     r11
    pop     r10
    pop     r9
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; lst_reloc_skip: move the relocation cursor past those of section rdi
; that start before offset rsi
lst_reloc_skip:
    test    rdi, rdi
    jz      .done
    lea     rax, [rel global_ctx]
    mov     r8, [rax + ASMCTX_relocs]
    mov     r9d, [rax + ASMCTX_nrelocs]
    mov     r10, [rel lst_rcur]
.next:
    cmp     r10, r9
    jae     .store
    mov     rcx, r10
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, r8
    cmp     [rcx + RELOC_section], rdi
    jne     .store
    cmp     [rcx + RELOC_offset], rsi
    jae     .store
    inc     r10
    jmp     .next
.store:
    mov     [rel lst_rcur], r10
.done:
    ret

; ---- output: buffered writes to lst_fd ----

; lst_put: rdx bytes at rsi
lst_put:
    push    rcx
    push    rdi
.copy:
    test    rdx, rdx
    jz      .done
    mov     rax, [rel lst_outlen]
    cmp     rax, OUT_BUF
    jb      .room
    push    rsi
    push    rdx
    call    lst_flush
    pop     rdx
    pop     rsi
    mov     rax, [rel lst_outlen]
.room:
    lea     rdi, [rel lst_out]
    mov     cl, [rsi]
    mov     [rdi + rax], cl
    inc     qword [rel lst_outlen]
    inc     rsi
    dec     rdx
    jmp     .copy
.done:
    pop     rdi
    pop     rcx
    ret

lst_flush:
    push    rcx
    push    r11
    mov     rdi, [rel lst_fd]
    lea     rsi, [rel lst_out]
    mov     rdx, [rel lst_outlen]
    test    rdx, rdx
    jz      .done
    call    io_write
.done:
    mov     qword [rel lst_outlen], 0
    pop     r11
    pop     rcx
    ret

lst_put_newline:
    lea     rsi, [rel lst_nl]
    mov     edx, 1
    jmp     lst_put

; lst_put_marker: "<1> " for depth edi > 0, else four blanks
lst_put_marker:
    lea     rsi, [rel lst_blank]
    test    edi, edi
    jz      .out
    cmp     edi, 9
    jbe     .digit
    mov     edi, 9
.digit:
    lea     rsi, [rel lst_marker]
    lea     eax, [rdi + '0']
    mov     [rsi + 1], al
.out:
    mov     edx, 4
    jmp     lst_put

; lst_put_lineno: edi right-aligned in 6 columns, then a blank
lst_put_lineno:
    lea     rsi, [rel lst_num]
    mov     dword [rsi], '    '
    mov     word [rsi + 4], '  '
    mov     byte [rsi + 6], ' '
    mov     eax, edi
    mov     ecx, 5
    mov     r8d, 10
.digit:
    xor     edx, edx
    div     r8d
    add     dl, '0'
    mov     [rsi + rcx], dl
    test    eax, eax
    jz      .out
    dec     ecx
    jns     .digit
.out:
    mov     edx, 7
    jmp     lst_put

; lst_put_offset: rdi as 8 hex digits, then a blank
lst_put_offset:
    lea     rsi, [rel lst_num]
    mov     ecx, 7
    lea     r8, [rel lst_hexdig]
.digit:
    mov     eax, edi
    and     eax, 15
    mov     al, [r8 + rax]
    mov     [rsi + rcx], al
    shr     rdi, 4
    dec     ecx
    jns     .digit
    mov     byte [rsi + 8], ' '
    mov     edx, 9
    jmp     lst_put

; lst_hex_trimmed: rax in hex without leading zeros, at rdi (advanced)
lst_hex_trimmed:
    lea     r8, [rel lst_hexdig]
    mov     ecx, 60
.skip:
    test    ecx, ecx
    jz      .digits
    mov     rdx, rax
    shr     rdx, cl
    test    edx, 15
    jnz     .digits
    sub     ecx, 4
    jmp     .skip
.digits:
    mov     rdx, rax
    shr     rdx, cl
    and     edx, 15
    mov     dl, [r8 + rdx]
    mov     [rdi], dl
    inc     rdi
    sub     ecx, 4
    jns     .digits
    ret

[SECTION .data]
lst_hexdig:     db "0123456789ABCDEF"
lst_warn_mark:  db "         ******************  "
lst_warn_mark_len equ $ - lst_warn_mark
lst_marker:     db "<1> "
lst_nl:         db 10
lst_blank:      times 40 db ' '

[SECTION .bss]
lst_row:        resb 64
lst_value:      resq 1
lst_symval:     resq 1
