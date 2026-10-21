;
; ============================================================================
; File        : src/debug/line.s
; Project     : utasm
; Description : The line table GNU's .file and .loc directives give (GCC's
;               -g output): .debug_line, as GNU as 2.43 writes it.
;
;   .file N ["dir"] "name" [md5 0x...]   an entry of the file table
;                                        (.file 0: DWARF 5's)
;   .loc N line [column] [basic_block] [prologue_end] [epilogue_begin]
;        [is_stmt 0|1] [isa N] [discriminator N] [view .LVUn | 0 | -0]
;
;   A .loc becomes a row of the line table at the next instruction (at once
;   when it has a view, or when another .loc comes first), in a code
;   section; elsewhere it is dropped. A row's view is 0 where the address
;   moved on from the row before in its section, else that row's view plus
;   one; "view .LVUn" defines .LVUn as that number (GCC's location lists
;   take it). The rows' places follow the code when jumps are shortened
;   (line_remap); the views are worked out again then, and one that would
;   change is an error: only alignment padding can, between two rows with
;   nothing else.
;
;   Once the code is laid out (line_build) the table goes after what the
;   source wrote into .debug_line (GCC's .Ldebug_line0): the header, the
;   directory and file tables (DWARF 5: their names in .debug_line_str,
;   after GCC's own strings), and a sequence per code section with rows,
;   in the order its first row came, encoded as GNU as does (dwarf2dbg.c:
;   process_entries, emit_inc_line_addr). The version: --gdwarf-N (GCC
;   passes it), 3 without, 5 once .file 0 or .loc 0 comes.
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

DEFAULT REL

extern  global_ctx
extern  asmctx_find_section
extern  asm_ctx_create_section
extern  preprocessor_peek_token
extern  preprocessor_next_token
extern  symbol_find
extern  symbol_add
extern  str_cmp
extern  str_cmp_kw
extern  str_len
extern  str_to_int
extern  arena_alloc_string
extern  io_mmap
extern  relax_map_offset
extern  relax_map_ranked
extern  relax_pad_rank
extern  error_set_subject
extern  str_int_to_str
extern  coff_enabled
extern  known_active, known_guessed, known_lookup
extern  dw_ctx, dw_u8, dw_u16, dw_u32, dw_uleb, dw_sleb, dw_sec_reloc
extern  dw_addr_size, dw_addr_type, dw_address, dw_cstr

; a row of the table
%define GR_SEC      0               ; q SECTION*
%define GR_OFF      8               ; q its place in it
%define GR_LINE     16              ; d
%define GR_COL      20              ; d
%define GR_FILE     24              ; d
%define GR_DISC     28              ; d
%define GR_ISA      32              ; d
%define GR_FLAGS    36              ; b GLF_*
%define GR_VKIND    37              ; b GLV_*
%define GR_FPOS     38              ; b GRF_*: where in GNU's frag it is
%define GR_RANK     39              ; b its padding rank (relax_pad_rank)
%define GR_VIEW     40              ; d its view
%define GR_FRAG     44              ; d the frag it is in (its section's)
%define GR_VSYM     48              ; q the view's symbol (GLV_NAME)
%define GR_SIZE     64
%define GL_ROWS     (1 << 22)       ; rows at most (committed as used)

; a file table entry
%define GF_NAME     0               ; q its name (no directory)
%define GF_DIR      8               ; d its directory's number
%define GF_MD5      16              ; 16 bytes (none: 0s)
%define GF_SIZE     32
%define GL_FILES    (1 << 16)
%define GL_DIRS     (1 << 16)

; a code section's view state while rows come (and once laid out)
%define GS_SEC      0
%define GS_OFF      8
%define GS_VIEW     16
%define GS_SIZE     24
%define GL_SECS     4096

; GNU as's frags: a section's code is cut where a jump it can relax or an
; alignment's padding comes (frag_var). "view -0" at a frag's start, after
; a row at the end of the frag before, has its address set again
; (process_entries): neither knows the padding between
%define FS_SEC      0
%define FS_FRAG     8               ; the frag being filled
%define FS_START    16              ; where it starts
%define FS_LAST     24              ; the section's last row
%define FS_SIZE     32
%define GRF_START   1               ; at the start of its frag
%define GRF_END     2               ; nothing of its frag after it
%define GRF_UNSURE  4               ; its view depends on padding: only
                                    ; padding since the row before (or a
                                    ; row before that, at its place)

%define GLF_NOSTMT      1           ; is_stmt 0 (0: is_stmt 1, the default)
%define GLF_BB          2
%define GLF_PROLOGUE    4
%define GLF_EPILOGUE    8

%define GLV_NONE        0
%define GLV_NAME        1           ; view .LVUn
%define GLV_ZERO        2           ; view 0: asserted 0
%define GLV_RESET       3           ; view -0: made 0

; DWARF
%define DW_LNS_copy             1
%define DW_LNS_advance_pc       2
%define DW_LNS_advance_line     3
%define DW_LNS_set_file         4
%define DW_LNS_set_column       5
%define DW_LNS_negate_stmt      6
%define DW_LNS_set_basic_block  7
%define DW_LNS_const_add_pc     8
%define DW_LNS_set_prologue_end 10
%define DW_LNS_set_epilogue_begin 11
%define DW_LNS_set_isa          12
%define DW_LNE_end_sequence     1
%define DW_LNE_set_address      2
%define DW_LNE_set_discriminator 4
%define DW_LNCT_path            1
%define DW_LNCT_directory_index 2
%define DW_LNCT_MD5             5
%define DW_FORM_udata           0x0F
%define DW_FORM_data16          0x1E
%define DW_FORM_line_strp       0x1F
%define LINE_BASE               -5
%define LINE_RANGE              14
%define OPCODE_BASE             13
%define MAX_SPECIAL_ADDR        17  ; (255 - OPCODE_BASE) / LINE_RANGE
%define LINE_END_SEQ            0x7FFFFFFF

%define SYS_GETCWD      79

[SECTION .bss]
alignb 8
global line_level, line_active, line_pending, line_views_unsure
KEY_MAX equ 256
key_buf:        resb KEY_MAX        ; a view's record's name (view_key)
line_views_unsure: resb 1           ; a view padding decides: pass 2 has it
alignb 4
line_level:     resd 1              ; --gdwarf-N (0: none given, 3)
line_active:    resb 1              ; a .file N or .loc came: the table is ours
line_loc_seen:  resb 1              ; a .loc came
line_pending:   resb 1              ; a .loc waits for its instruction
cur_vkind:      resb 1              ; the .loc read: GLV_*
cur_flags:      resb 1              ; ... GLF_*
alignb 8
cur_vname:      resq 1              ; ... its view's name
cur_file:       resd 1
cur_line:       resd 1
cur_col:        resd 1
cur_isa:        resd 1
cur_disc:       resd 1
alignb 8
rows:           resq 1              ; the rows (mapped)
nrows:          resq 1
files:          resq 1              ; the file table (mapped)
nfiles:         resq 1
dirs:           resq 1              ; the directory table (mapped)
ndirs:          resq 1
secs:           resb GL_SECS * GS_SIZE
nsecs:          resq 1
fsecs:          resb GL_SECS * FS_SIZE ; each code section's frags
nfsecs:         resq 1
md5_buf:        resb 16
cwd_buf:        resb 4096
cwd_got:        resb 1
num_text:       resb 32             ; a number, for a message
alignb 8
ln_sec:         resq 1              ; line_build: .debug_line
str_sec:        resq 1              ; ... .debug_line_str
file0_strp:     resq 1              ; ... file 0's string, for file 1 (-1: none)
ps_file:        resd 1              ; process_rows: the state machine
ps_line:        resd 1
ps_col:         resd 1
ps_isa:         resd 1
ps_flags:       resb 1
ps_first:       resb 1
alignb 8
ps_off:         resq 1
ps_prev:        resq 1              ; ... the row before

[SECTION .rodata]
s_debug_line:     db ".debug_line", 0
s_debug_line_str: db ".debug_line_str", 0
s_debug_info:     db ".debug_info", 0
s_empty:          db 0
w_md5:            db "md5", 0
w_basic_block:    db "basic_block", 0
w_prologue_end:   db "prologue_end", 0
w_epilogue_begin: db "epilogue_begin", 0
w_is_stmt:        db "is_stmt", 0
w_isa:            db "isa", 0
w_discriminator:  db "discriminator", 0
w_view:           db "view", 0

[SECTION .text]

; ---- the directives -------------------------------------------------------

;*
; * [line_file]
; * Purpose: ".file N ["dir"] "name" [md5 X]" (the N already peeked): file
; *          N of the table, as GNU as's allocate_filename_to_slot.
; * Input  : RDI = PrepState
; * Output : RAX = OK or an error (the rest of the line is left)
; ;
global line_file
line_file:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     byte [rel line_active], 1
    call    .next
    call    tok_number
    jc      .bad
    mov     r12, rax                       ; the number
    test    r12, r12
    jns     .not_negative
    mov     eax, EXIT_LINE_FILE_NUM
    jmp     .ret
.not_negative:
    jnz     .numbered
    call    level_5                        ; .file 0: DWARF 5's
.numbered:
    call    .next
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
    call    tok_string
    test    rax, rax
    jnz     .ret
    mov     r13, rdx                       ; the name
    xor     r14d, r14d                     ; the directory: none
    xor     r15d, r15d                     ; no md5
    call    .peek
    jc      .read
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .md5
    call    .next
    call    tok_string
    test    rax, rax
    jnz     .ret
    mov     r14, r13                       ; "dir" "name"
    mov     r13, rdx
    call    .peek
    jc      .read
.md5:
    mov     rdi, [rdx + TOKEN_value]
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .read
    lea     rsi, [rel w_md5]
    call    str_cmp
    test    rax, rax
    jnz     .read
    call    .next                          ; md5
    call    .next                          ; its number
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    md5_parse
    mov     r15d, 1
.read:
    mov     rdi, r14
    mov     rsi, r13
    mov     edx, r12d
    mov     ecx, r15d
    call    file_slot
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret
; .next / .peek: rdx = the token (.peek: CF at the end of the line)
.next:
    mov     rdi, rbx
    jmp     preprocessor_next_token
.peek:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .peek_end
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .peek_end
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .peek_end
    clc
    ret
.peek_end:
    stc
    ret

;*
; * [line_loc]
; * Purpose: ".loc N line [column] [options]", as GNU as's
; *          dwarf2_directive_loc: a .loc still waiting becomes a row here
; *          first; with a view this one does at once.
; * Input  : RDI = PrepState
; * Output : RAX = OK or an error
; ;
global line_loc
line_loc:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     byte [rel line_active], 1
    cmp     byte [rel line_pending], 0
    je      .read
    call    line_emit                      ; two in a row: the first now
    test    rax, rax
    jnz     .ret
.read:
    call    line_file.next
    call    tok_number
    jc      .bad
    mov     r12, rax                       ; the file
    call    line_file.next
    call    tok_number
    jc      .bad
    mov     r13, rax                       ; the line
    test    r12, r12
    jg      .file_ok
    mov     eax, EXIT_LINE_FILE_NUM
    js      .ret
    call    level_5                        ; .loc 0
.file_ok:
    cmp     r12, [rel nfiles]
    jae     .unassigned
    mov     rax, r12
    shl     rax, 5                         ; GF_SIZE
    add     rax, [rel files]
    cmp     qword [rax + GF_NAME], 0
    jne     .assigned
.unassigned:
    mov     rsi, r12
    call    number_subject
    mov     eax, EXIT_LINE_UNASSIGNED
    jmp     .ret
.assigned:
    mov     [rel cur_file], r12d
    mov     [rel cur_line], r13d
    mov     dword [rel cur_disc], 0
    call    line_file.peek
    jc      .done
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .options
    call    line_file.next
    call    tok_number
    mov     [rel cur_col], eax
.options:
    call    line_file.peek
    jc      .done
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done                          ; (the rest: gas.s's)
    mov     r14, [rdx + TOKEN_value]       ; the word
    call    line_file.next
    mov     rdi, r14
    lea     rsi, [rel w_basic_block]
    call    str_cmp
    test    rax, rax
    jnz     .not_bb
    or      byte [rel cur_flags], GLF_BB
    jmp     .options
.not_bb:
    mov     rdi, r14
    lea     rsi, [rel w_prologue_end]
    call    str_cmp
    test    rax, rax
    jnz     .not_pro
    call    level_3
    or      byte [rel cur_flags], GLF_PROLOGUE
    jmp     .options
.not_pro:
    mov     rdi, r14
    lea     rsi, [rel w_epilogue_begin]
    call    str_cmp
    test    rax, rax
    jnz     .not_epi
    call    level_3
    or      byte [rel cur_flags], GLF_EPILOGUE
    jmp     .options
.not_epi:
    mov     rdi, r14
    lea     rsi, [rel w_is_stmt]
    call    str_cmp
    test    rax, rax
    jnz     .not_stmt
    call    line_file.next
    call    tok_number
    jc      .bad
    cmp     rax, 1
    ja      .stmt_bad
    and     byte [rel cur_flags], ~GLF_NOSTMT
    test    rax, rax
    jnz     .options
    or      byte [rel cur_flags], GLF_NOSTMT
    jmp     .options
.stmt_bad:
    mov     eax, EXIT_LINE_STMT
    jmp     .ret
.not_stmt:
    mov     rdi, r14
    lea     rsi, [rel w_isa]
    call    str_cmp
    test    rax, rax
    jnz     .not_isa
    call    level_3
    call    line_file.next
    call    tok_number
    jc      .bad
    mov     [rel cur_isa], eax
    jmp     .options
.not_isa:
    mov     rdi, r14
    lea     rsi, [rel w_discriminator]
    call    str_cmp
    test    rax, rax
    jnz     .not_disc
    call    line_file.next
    call    tok_number
    jc      .bad
    mov     [rel cur_disc], eax
    jmp     .options
.not_disc:
    mov     rdi, r14
    lea     rsi, [rel w_view]
    call    str_cmp
    test    rax, rax
    jnz     .unknown
    call    line_file.next
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NUMBER
    je      .view_zero
    cmp     eax, TOK_MINUS
    je      .view_reset
    mov     rax, [rdx + TOKEN_value]       ; a name
    test    rax, rax
    jz      .bad
    mov     [rel cur_vname], rax
    mov     byte [rel cur_vkind], GLV_NAME
    jmp     .options
.view_reset:
    call    line_file.next
    call    tok_number
    jc      .bad
    test    rax, rax
    jnz     .view_numeric
    mov     byte [rel cur_vkind], GLV_RESET
    jmp     .options
.view_zero:
    call    tok_number
    test    rax, rax
    jnz     .view_numeric
    mov     byte [rel cur_vkind], GLV_ZERO
    jmp     .options
.view_numeric:
    mov     eax, EXIT_LINE_VIEW_NUM
    jmp     .ret
.unknown:
    mov     rdi, r14
    call    error_set_subject
    mov     eax, EXIT_LINE_LOC_WORD
    jmp     .ret
.done:
    mov     byte [rel line_loc_seen], 1
    mov     byte [rel line_pending], 1
    xor     eax, eax
    cmp     byte [rel cur_vkind], GLV_NONE
    je      .ret
    call    line_emit                      ; with a view: the row now
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret

;*
; * [line_insn]
; * Purpose: An instruction starts here: the .loc waiting is its row.
; * Output : RAX = OK or an error
; ;
global line_insn
line_insn:
    cmp     byte [rel line_pending], 0
    jne     line_emit
    xor     eax, eax
    ret

; line_emit: the .loc read becomes a row where the code is now (in a code
; section; elsewhere it is dropped), and is used up: GNU's
; dwarf2_gen_line_info and dwarf2_consume_line_info. RAX = OK or an error
line_emit:
    push    rbx
    push    r12
    push    r13
    mov     byte [rel line_pending], 0
    xor     r13d, r13d                     ; the result
    cmp     dword [rel cur_line], 0
    je      .consumed                      ; line 0: no row
    cmp     dword [rel cur_file], 0
    jne     .file_set
    call    level_5
.file_set:
    lea     rax, [rel global_ctx]
    mov     rbx, [rax + ASMCTX_curr_sec]
    test    rbx, rbx
    jz      .consumed
    test    word [rbx + SECTION_flags], SHF_ALLOC
    jz      .consumed
    test    word [rbx + SECTION_flags], SHF_EXECINSTR
    jz      .consumed
    cmp     dword [rbx + SECTION_elf_type], SHT_NOBITS
    je      .consumed
    ; the row
    call    row_room
    test    rax, rax
    jnz     .failed
    mov     r12, rdx
    mov     [r12 + GR_SEC], rbx
    mov     rax, [rbx + SECTION_size]
    mov     [r12 + GR_OFF], rax
    mov     eax, [rel cur_line]
    mov     [r12 + GR_LINE], eax
    mov     eax, [rel cur_col]
    mov     [r12 + GR_COL], eax
    mov     eax, [rel cur_file]
    mov     [r12 + GR_FILE], eax
    mov     eax, [rel cur_disc]
    mov     [r12 + GR_DISC], eax
    mov     eax, [rel cur_isa]
    mov     [r12 + GR_ISA], eax
    mov     al, [rel cur_flags]
    mov     [r12 + GR_FLAGS], al
    mov     al, [rel cur_vkind]
    mov     [r12 + GR_VKIND], al
    mov     qword [r12 + GR_VSYM], 0
    ; its frag, GNU's
    mov     rdi, rbx
    call    frag_state
    test    rax, rax
    jnz     .failed
    mov     rax, [r8 + FS_FRAG]
    mov     [r12 + GR_FRAG], eax
    xor     eax, eax
    mov     rcx, [r12 + GR_OFF]
    cmp     rcx, [r8 + FS_START]
    jne     .not_start
    mov     eax, GRF_START
.not_start:
    mov     [r12 + GR_FPOS], al
    push    r8
    mov     rdi, rbx
    mov     rsi, [r12 + GR_OFF]
    call    relax_pad_rank
    pop     r8
    mov     [r12 + GR_RANK], al            ; (after those paddings only)
    ; a view that depends on padding: GNU as works it out once the code is
    ; laid out (after the row before, nothing but padding - or the same
    ; place as a row before that does). Pass 2 has its value (src/core/known.s)
    cmp     byte [r12 + GR_VKIND], GLV_RESET
    je      .sure                          ; (0 whatever comes between)
    mov     rax, [r8 + FS_LAST]
    test    rax, rax
    jz      .sure
    mov     ecx, [rax + GR_FRAG]
    cmp     ecx, [r12 + GR_FRAG]
    jne     .other_frag
    mov     rcx, [rax + GR_OFF]
    cmp     rcx, [r12 + GR_OFF]
    jne     .sure
    test    byte [rax + GR_FPOS], GRF_UNSURE
    jz      .sure
    jmp     .unsure
.other_frag:
    test    byte [r12 + GR_FPOS], GRF_START
    jz      .sure
    test    byte [rax + GR_FPOS], GRF_END
    jz      .sure
.unsure:
    or      byte [r12 + GR_FPOS], GRF_UNSURE
    mov     byte [rel line_views_unsure], 1
.sure:
    mov     [r8 + FS_LAST], r12
    ; its view, from the row before in its section
    mov     rdi, rbx
    mov     rsi, [r12 + GR_OFF]
    movzx   edx, byte [r12 + GR_VKIND]
    call    view_next
    test    rax, rax
    jnz     .failed
    ; one padding decides: pass 2 has the value pass 1 laid out, pass 1
    ; asks for pass 2 (its own value is a guess)
    test    byte [r12 + GR_FPOS], GRF_UNSURE
    jz      .view_got
    cmp     byte [r12 + GR_VKIND], GLV_NAME
    jne     .view_got
    cmp     byte [rel known_active], 0
    jne     .view_known
    mov     byte [rel known_guessed], 1
    jmp     .view_got
.view_known:
    push    rdx
    push    r8
    mov     rdi, [rel cur_vname]
    call    view_key
    lea     rsi, [rel key_buf]
    call    known_lookup
    pop     r8
    pop     rcx                            ; (the guess)
    test    eax, eax
    jnz     .view_took
    mov     rdx, rcx
    jmp     .view_got
.view_took:
    mov     [r8 + GS_VIEW], rdx            ; the ones after count from it
.view_got:
    mov     [r12 + GR_VIEW], edx
    cmp     byte [r12 + GR_VKIND], GLV_ZERO
    jne     .not_zero
    test    edx, edx
    jz      .consumed
    mov     r13d, EXIT_LINE_VIEW_MISMATCH  ; "view 0" where it is not
    jmp     .consumed
.not_zero:
    cmp     byte [r12 + GR_VKIND], GLV_NAME
    jne     .consumed
    ; view .LVUn: the name is that number
    mov     rdi, [rel cur_vname]
    mov     esi, edx
    call    view_define
    test    rax, rax
    jnz     .failed
    mov     [r12 + GR_VSYM], rdx
    jmp     .consumed
.failed:
    mov     r13, rax
.consumed:
    and     byte [rel cur_flags], ~(GLF_BB | GLF_PROLOGUE | GLF_EPILOGUE)
    mov     dword [rel cur_disc], 0
    mov     byte [rel cur_vkind], GLV_NONE
    mov     rax, r13
    pop     r13
    pop     r12
    pop     rbx
    ret

; row_room: rdx = the next row (the table mapped first). RAX = OK or error
row_room:
    mov     rax, [rel rows]
    test    rax, rax
    jnz     .mapped
    xor     edi, edi
    mov     rsi, GL_ROWS * GR_SIZE
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS | 0x4000   ; MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .ret
    mov     [rel rows], rdx
    mov     rax, rdx
.mapped:
    mov     rcx, [rel nrows]
    cmp     rcx, GL_ROWS
    jae     .full
    shl     rcx, 6                         ; GR_SIZE
    lea     rdx, [rax + rcx]
    inc     qword [rel nrows]
    xor     eax, eax
.ret:
    ret
.full:
    mov     eax, EXIT_SYMBOL_RANGE
    ret

; frag_state: r8 = section rdi's frag state (made when new). RAX = OK or
; error. Preserves the others but rcx
frag_state:
    lea     r8, [rel fsecs]
    mov     rcx, [rel nfsecs]
.find:
    test    rcx, rcx
    jz      .new
    cmp     [r8 + FS_SEC], rdi
    je      .found
    add     r8, FS_SIZE
    dec     rcx
    jmp     .find
.new:
    cmp     qword [rel nfsecs], GL_SECS
    jae     .full
    inc     qword [rel nfsecs]
    mov     [r8 + FS_SEC], rdi
    xor     eax, eax
    mov     [r8 + FS_FRAG], rax
    mov     [r8 + FS_START], rax
    mov     [r8 + FS_LAST], rax
.found:
    xor     eax, eax
    ret
.full:
    mov     eax, EXIT_SYMBOL_RANGE
    ret

;*
; * [line_frag]
; * Purpose: GNU as ends a frag of the current section here: its fixed part
; *          at RSI, the next one from RDX (a jump it can relax, alignment
; *          padding). A row at RSI is then at its frag's end.
; * Input  : RSI, RDX = the offsets
; ;
global line_frag
line_frag:
    cmp     byte [rel line_active], 0
    je      .ret
    push    r8
    push    rcx
    push    rax
    push    rdi
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_curr_sec]
    test    rdi, rdi
    jz      .out
    call    frag_state
    test    rax, rax
    jnz     .out
    mov     rax, [r8 + FS_LAST]
    test    rax, rax
    jz      .next
    mov     ecx, [rax + GR_FRAG]
    cmp     rcx, [r8 + FS_FRAG]
    jne     .next
    cmp     [rax + GR_OFF], rsi
    jne     .next
    or      byte [rax + GR_FPOS], GRF_END
.next:
    inc     qword [r8 + FS_FRAG]
    mov     [r8 + FS_START], rdx
.out:
    pop     rdi
    pop     rax
    pop     rcx
    pop     r8
.ret:
    ret

;*
; * [line_insn_done]
; * Purpose: An instruction was written: a jump GNU as relaxes (jmp, jcc to
; *          a label) ends its frag there.
; * Input  : RDI = the INST
; ;
global line_insn_done
line_insn_done:
    cmp     byte [rel line_active], 0
    je      .ret
    movzx   eax, word [rdi + INST_op_id]
    cmp     eax, 1298                      ; JMP
    je      .jump
    cmp     eax, 3000                      ; Jcc
    jb      .ret
    cmp     eax, 3099
    ja      .ret
.jump:
    movzx   eax, byte [rdi + INST_op0 + OPERAND_kind]
    cmp     eax, OP_REG
    je      .ret
    cmp     eax, OP_MEM
    je      .ret                           ; (indirect: no relaxing)
    lea     rax, [rel global_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .ret
    mov     rsi, [rax + SECTION_size]
    mov     rdx, rsi
    jmp     line_frag
.ret:
    ret

; view_next: the view of a row at offset rsi of section rdi (edx: its
; GLV_*): 0 at the first in the section, after the address moved on, or
; for "view -0"; else the one before plus one. The section's state moves
; to it. RAX = OK or error, EDX = the view
view_next:
    lea     r8, [rel secs]
    mov     rcx, [rel nsecs]
.find:
    test    rcx, rcx
    jz      .new
    cmp     [r8 + GS_SEC], rdi
    je      .found
    add     r8, GS_SIZE
    dec     rcx
    jmp     .find
.new:
    cmp     qword [rel nsecs], GL_SECS
    jae     .full
    inc     qword [rel nsecs]
    mov     [r8 + GS_SEC], rdi
    xor     eax, eax
    jmp     .set
.found:
    xor     eax, eax
    cmp     edx, GLV_RESET
    je      .set
    cmp     rsi, [r8 + GS_OFF]
    ja      .set                           ; moved on: 0
    mov     rax, [r8 + GS_VIEW]
    inc     rax
.set:
    mov     [r8 + GS_OFF], rsi
    mov     [r8 + GS_VIEW], rax
    mov     edx, eax
    xor     eax, eax
    ret
.full:
    mov     eax, EXIT_SYMBOL_RANGE
    ret

; view_key: key_buf = "\x03" and the view's name rdi: its record handed to
; pass 2 (src/core/known.s). Preserves the others but rcx
view_key:
    push    rdi
    push    rsi
    lea     rsi, [rel key_buf]
    mov     byte [rsi], 3
    inc     rsi
    mov     ecx, KEY_MAX - 2
.byte:
    mov     al, [rdi]
    mov     [rsi], al
    test    al, al
    jz      .done
    inc     rdi
    inc     rsi
    dec     ecx
    jnz     .byte
    mov     byte [rsi], 0
.done:
    pop     rsi
    pop     rdi
    ret

;*
; * [line_views_records]
; * Purpose: Pass 1, the code laid out: the views padding decides, worked
; *          out again, as records for pass 2 (src/core/known.s): the value,
; *          then "\x03" and the name.
; * Input  : RDI = the records, RSI = their length, RDX = the most it may be
; * Output : RAX = the length now, RDX = the records added
; ;
global line_views_records
line_views_records:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    mov     r13, rdi
    mov     r14, rsi
    mov     r15, rdx
    xor     ebp, ebp                       ; added
    mov     qword [rel nsecs], 0
    mov     rbx, [rel rows]
    mov     r12, [rel nrows]
.row:
    test    r12, r12
    jz      .done
    mov     rdi, [rbx + GR_SEC]
    mov     rsi, [rbx + GR_OFF]
    movzx   edx, byte [rbx + GR_VKIND]
    call    view_next
    test    rax, rax
    jnz     .done
    test    byte [rbx + GR_FPOS], GRF_UNSURE
    jz      .next
    cmp     byte [rbx + GR_VKIND], GLV_NAME
    jne     .next
    mov     rax, [rbx + GR_VSYM]
    test    rax, rax
    jz      .next
    push    rdx
    mov     rdi, [rax + SYMBOL_name]
    call    view_key
    pop     rdx
    lea     rax, [r14 + 8 + KEY_MAX]
    cmp     rax, r15
    ja      .done                          ; (no room: pass 2 guesses too)
    mov     [r13 + r14], rdx               ; the value
    add     r14, 8
    lea     rsi, [rel key_buf]
.copy:
    mov     al, [rsi]
    mov     [r13 + r14], al
    inc     r14
    inc     rsi
    test    al, al
    jnz     .copy
    inc     rbp
.next:
    add     rbx, GR_SIZE
    dec     r12
    jmp     .row
.done:
    mov     rax, r14
    mov     rdx, rbp
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; view_define: the constant rdi = esi (a view's name). RAX = OK or an
; error, RDX = the symbol
view_define:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13d, esi
    lea     rbx, [rel global_ctx]
    mov     rdi, rbx
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .add
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_DUP_SYMBOL           ; already defined
    jmp     .ret
.add:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rsi + SYMBOL_vis], VIS_LOCAL
    mov     [rsi + SYMBOL_name], r12
    mov     [rsi + SYMBOL_value], r13
    mov     qword [rsi + SYMBOL_size], 8
    mov     word [rsi + SYMBOL_section], SHN_ABS     ; a number, as an equ's
    mov     rdi, rbx
    call    symbol_add
    add     rsp, SYMBOL_SIZE
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; level_3 / level_5: the version at least 3 / 5
level_3:
    call    level_now
    cmp     dword [rel line_level], 3
    jae     .ret
    mov     dword [rel line_level], 3
.ret:
    ret
level_5:
    call    level_now
    cmp     dword [rel line_level], 5
    jae     .ret
    mov     dword [rel line_level], 5
.ret:
    ret
; level_now: the version (3 when --gdwarf-N gave none)
level_now:
    cmp     dword [rel line_level], 0
    jne     .ret
    mov     dword [rel line_level], 3
.ret:
    ret

; tok_number: rax = the number token rdx (CF: not one)
tok_number:
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .not
    mov     rdi, [rdx + TOKEN_value]
    test    rdi, rdi
    jz      .not
    call    str_to_int
    test    rax, rax
    jnz     .not
    mov     rax, rdx
    clc
    ret
.not:
    xor     eax, eax
    stc
    ret

; tok_string: rdx = the string token rdx's bytes, NUL-terminated (a
; counted one copied). RAX = OK or error
tok_string:
    test    byte [rdx + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .counted
    mov     rdx, [rdx + TOKEN_value]
    xor     eax, eax
    ret
.counted:
    mov     rsi, [rdx + TOKEN_value]
    movzx   edx, word [rdx + TOKEN_len]
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_arena]
    jmp     arena_alloc_string

; md5_parse: md5_buf = the 128-bit number written at rsi (0x...), its low
; byte first (GNU's little-endian md5)
md5_parse:
    lea     rdi, [rel md5_buf]
    xor     eax, eax
    mov     [rdi], rax
    mov     [rdi + 8], rax
    cmp     word [rsi], '0x'
    je      .hex
    cmp     word [rsi], '0X'
    jne     .ret
.hex:
    add     rsi, 2
    mov     rdi, rsi
    call    str_len
    lea     r8, [rsi + rax - 1]            ; the last digit
    xor     ecx, ecx                       ; nibbles taken
.digit:
    cmp     r8, rsi
    jb      .ret
    movzx   eax, byte [r8]
    dec     r8
    cmp     eax, '_'
    je      .digit
    lea     edx, [rax - '0']
    cmp     edx, 9
    jbe     .digit_value
    or      eax, 0x20                      ; a-f, A-F
    sub     eax, 'a'
    cmp     eax, 5
    ja      .ret
    lea     edx, [rax + 10]
.digit_value:
    mov     eax, edx
.nibble:
    cmp     ecx, 32
    jae     .ret
    mov     edx, ecx
    shr     edx, 1
    test    ecx, 1
    jz      .low
    shl     eax, 4
.low:
    lea     rdi, [rel md5_buf]
    or      [rdi + rdx], al
    inc     ecx
    jmp     .digit
.ret:
    ret

; number_subject: rsi as the subject of the next message
number_subject:
    lea     rdi, [rel num_text]
    call    str_int_to_str
    lea     rdi, [rel num_text]
    jmp     error_set_subject

; ---- the file and directory tables ----------------------------------------

; tables_room: the tables mapped. RAX = OK or error
tables_room:
    cmp     qword [rel files], 0
    jne     .ok
    xor     edi, edi
    mov     rsi, GL_FILES * GF_SIZE + GL_DIRS * 8
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS | 0x4000   ; MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .ret
    mov     [rel files], rdx
    add     rdx, GL_FILES * GF_SIZE
    mov     [rel dirs], rdx
.ok:
    xor     eax, eax
.ret:
    ret

; file_slot: file edx of the table: name rsi, in directory rdi (0: the
; name's own), ecx = 1: md5_buf its md5 - GNU's allocate_filename_to_slot.
; RAX = OK or an error
file_slot:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    mov     r12, rdi                       ; the directory given
    mov     r13, rsi                       ; the name
    mov     r14d, edx                      ; the number
    mov     [rsp], ecx                     ; md5
    call    tables_room
    test    rax, rax
    jnz     .ret
    cmp     r14d, GL_FILES
    jae     .too_big
    mov     rbx, r14
    shl     rbx, 5
    add     rbx, [rel files]               ; rbx = its entry
    cmp     r14, [rel nfiles]
    jae     .new
    cmp     qword [rbx + GF_NAME], 0
    je      .new
    ; taken already: the same file, or an error
    cmp     dword [rsp], 0
    je      .same_md5
    mov     rax, [rbx + GF_MD5]
    cmp     rax, [rel md5_buf]
    jne     .occupied
    mov     rax, [rbx + GF_MD5 + 8]
    cmp     rax, [rel md5_buf + 8]
    jne     .occupied
.same_md5:
    mov     eax, [rbx + GF_DIR]
    mov     rcx, [rel dirs]
    mov     r15, [rcx + rax * 8]           ; its directory's name, or 0
    test    r12, r12
    jz      .no_dir_given
    test    r15, r15
    jz      .dir_free
    mov     rdi, r15
    mov     rsi, r12
    call    str_cmp
    test    rax, rax
    jnz     .occupied
.dir_free:
    mov     rdi, r13
    mov     rsi, [rbx + GF_NAME]
    call    str_cmp
    test    rax, rax
    jnz     .occupied
    test    r15, r15
    jnz     .ok
    mov     rdi, r12                       ; the directory given fills it
    call    str_len
    mov     rsi, r12
    mov     rdx, rax
    jmp     .fill_dir
.no_dir_given:
    test    r15, r15
    jz      .base_only
    ; "dir/name" as written once more
    mov     rdi, r15
    call    str_len
    mov     rcx, rax
    mov     rdi, r13
    mov     rsi, r15
    repe cmpsb
    jne     .occupied
    cmp     byte [rdi], '/'
    jne     .occupied
    inc     rdi
    mov     rsi, [rbx + GF_NAME]
    call    str_cmp
    test    rax, rax
    jnz     .occupied
    jmp     .ok
.base_only:
    mov     rdi, r13
    call    basename
    mov     r15, rax
    mov     rdi, rax
    mov     rsi, [rbx + GF_NAME]
    call    str_cmp
    test    rax, rax
    jnz     .occupied
    cmp     r15, r13
    jbe     .ok
    mov     rsi, r13                       ; the name's directory fills it
    mov     rdx, r15
    sub     rdx, r13
.fill_dir:
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_arena]
    call    arena_alloc_string
    test    rax, rax
    jnz     .ret
    mov     eax, [rbx + GF_DIR]
    mov     rcx, [rel dirs]
    mov     [rcx + rax * 8], rdx           ; (not counted in: GNU's neither)
    jmp     .ok
.occupied:
    mov     rsi, r14
    call    number_subject
    mov     eax, EXIT_LINE_FILE_SLOT
    jmp     .ret
.too_big:
    mov     rsi, r14
    call    number_subject
    mov     eax, EXIT_LINE_FILE_BIG
    jmp     .ret

.new:
    test    r14d, r14d
    jnz     .not_zero
    ; file 0: the directory is the build's, the name may have one in it
    mov     rdi, r13
    call    basename
    mov     r15, rax                       ; the name, no directory
    mov     rcx, r12                       ; file 0's directory
    test    r12, r12
    jz      .zero_own
    cmp     rax, r13
    jne     .zero_own
    mov     rdi, r12
    call    str_len
    mov     rdx, rax
    mov     rdi, r12
    jmp     .dir_entry
.zero_own:
    mov     rdi, r13                       ; the name's own directory
    mov     rdx, r15
    sub     rdx, r13
    jmp     .dir_entry
.not_zero:
    xor     ecx, ecx
    test    r12, r12
    jnz     .dir_given
    mov     rdi, r13
    call    basename
    mov     r15, rax
    mov     rdi, r13
    mov     rdx, r15
    sub     rdx, r13
    xor     ecx, ecx
    jmp     .dir_entry
.dir_given:
    mov     rdi, r12
    call    str_len
    mov     rdx, rax
    mov     rdi, r12
    mov     r15, r13
    xor     ecx, ecx
.dir_entry:
    ; rdi = the directory text, rdx its length, rcx file 0's directory
    mov     rsi, rcx
    xor     ecx, ecx
    test    r14d, r14d
    setz    cl                             ; file 0 may take directory 0
    call    dir_entry
    test    rax, rax
    jnz     .ret
    ; the entry
    mov     [rbx + GF_NAME], r15
    mov     [rbx + GF_DIR], edx
    xor     eax, eax
    mov     [rbx + GF_MD5], rax
    mov     [rbx + GF_MD5 + 8], rax
    cmp     dword [rsp], 0
    je      .counted
    mov     rax, [rel md5_buf]
    mov     [rbx + GF_MD5], rax
    mov     rax, [rel md5_buf + 8]
    mov     [rbx + GF_MD5 + 8], rax
.counted:
    lea     rax, [r14 + 1]
    cmp     rax, [rel nfiles]
    jbe     .ok
    mov     [rel nfiles], rax
.ok:
    xor     eax, eax
.ret:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; basename: rax = the name rdi past its last "/" (all of "/x")
basename:
    mov     rax, rdi
    mov     rcx, rdi
.scan:
    movzx   edx, byte [rcx]
    test    edx, edx
    jz      .end
    inc     rcx
    cmp     edx, '/'
    jne     .scan
    mov     rax, rcx
    jmp     .scan
.end:
    lea     rcx, [rdi + 1]
    cmp     rax, rcx
    jne     .ret
    mov     rax, rdi                       ; "/x": all of it
.ret:
    ret

; dir_entry: the directory table's number for rdx bytes at rdi (rsi: file
; 0's directory, or 0; ecx = 1: it may be 0) - GNU's
; get_directory_table_entry, added when new. RAX = OK or error, EDX = it
dir_entry:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rdx
    mov     r14, rsi
    mov     r15d, ecx
    xor     edx, edx
    test    r13, r13
    jz      .found                         ; none: 0
    cmp     byte [r12 + r13 - 1], '/'
    jne     .search
    dec     r13
    jz      .found
.search:
    xor     ebx, ebx
.dir:
    cmp     rbx, [rel ndirs]
    jae     .not_found
    mov     rax, [rel dirs]
    mov     rsi, [rax + rbx * 8]
    test    rsi, rsi
    jz      .dir_next
    mov     rdi, r12
    mov     rcx, r13
    repe cmpsb
    jne     .dir_next
    cmp     byte [rsi], 0
    jne     .dir_next
    mov     edx, ebx
    jmp     .found
.dir_next:
    inc     rbx
    jmp     .dir
.not_found:
    ; rbx = the number of directories
    test    r15d, r15d
    jz      .not_zero
    cmp     qword [rel ndirs], 0
    je      .zero_free
    mov     rax, [rel dirs]
    cmp     qword [rax], 0
    jne     .add
.zero_free:
    ; directory 0 is the build's (DWARF 5): it comes first when this is
    ; another one
    mov     rdi, r14
    test    rdi, rdi
    jnz     .pwd
    call    cwd
    mov     rdi, rax
.pwd:
    xor     ebx, ebx
    cmp     dword [rel line_level], 5
    jb      .add
    push    rdi
    mov     rsi, r12
    call    str_cmp                        ; (all of the text, as GNU does)
    pop     rdi
    test    rax, rax
    jz      .add
    push    rdi
    call    str_len
    pop     rdi
    mov     rdx, rax
    mov     rsi, r14
    mov     ecx, 1
    call    dir_entry
    test    rax, rax
    jnz     .ret
    mov     ebx, 1
    jmp     .add
.not_zero:
    test    rbx, rbx
    jnz     .add
    mov     ebx, 1                         ; not 0: that is the build's
.add:
    cmp     rbx, GL_DIRS
    jae     .full
    lea     rax, [rel global_ctx]
    mov     rdi, [rax + ASMCTX_arena]
    mov     rsi, r12
    mov     rdx, r13
    call    arena_alloc_string
    test    rax, rax
    jnz     .ret
    mov     rax, [rel dirs]
    mov     [rax + rbx * 8], rdx
    lea     rax, [rbx + 1]
    cmp     rax, [rel ndirs]
    jbe     .counted
    mov     [rel ndirs], rax
.counted:
    mov     edx, ebx
.found:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.full:
    mov     eax, EXIT_LINE_FILE_BIG
    jmp     .ret

; cwd: rax = the current directory's name ("" when it cannot be had)
cwd:
    lea     rax, [rel cwd_buf]
    cmp     byte [rel cwd_got], 0
    jne     .ret
    mov     byte [rel cwd_got], 1
    push    rdi
    push    rsi
    lea     rdi, [rel cwd_buf]
    mov     esi, 4095
    mov     eax, SYS_GETCWD
    syscall
    pop     rsi
    pop     rdi
    test    rax, rax
    jns     .got
    mov     byte [rel cwd_buf], 0
.got:
    lea     rax, [rel cwd_buf]
.ret:
    ret

; ---- once the code is laid out --------------------------------------------

;*
; * [line_remap]
; * Purpose: Section RDI is being rewritten (jumps shortened): its rows'
; *          places move with the code.
; ;
global line_remap
line_remap:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     rbx, [rel rows]
    mov     r13, [rel nrows]
.row:
    test    r13, r13
    jz      .done
    cmp     [rbx + GR_SEC], r12
    jne     .next
    mov     rdi, [rbx + GR_OFF]
    movzx   esi, byte [rbx + GR_RANK]
    call    relax_map_ranked               ; (its place among the padding)
    mov     [rbx + GR_OFF], rax
.next:
    add     rbx, GR_SIZE
    dec     r13
    jmp     .row
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [line_build]
; * Purpose: .debug_line from the .file and .loc directives, when they came
; *          (an ELF object), as GNU as's dwarf2_finish: after what the
; *          source wrote there, which is to be nothing; with no row, only
; *          when .debug_info has something (its CU refers to the table).
; * Input  : RDI = AsmCtx
; * Output : RAX = OK or an error
; ;
global line_build
line_build:
    cmp     byte [rel line_active], 0
    jne     .on
.off:
    xor     eax, eax
    ret
.on:
    cmp     byte [rdi + ASMCTX_fmt], FMT_ELF64
    jne     .off
    cmp     byte [rdi + ASMCTX_standalone], 0
    jne     .off
    cmp     byte [rel coff_enabled], 0
    jne     .off
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     [rel dw_ctx], rdi
    call    level_now
    ; .debug_line and .debug_info as the source left them
    mov     rdi, rbx
    lea     rsi, [rel s_debug_line]
    call    asmctx_find_section
    xor     r12d, r12d
    test    rax, rax
    jnz     .no_line
    mov     r12, rdx                       ; r12 = .debug_line
.no_line:
    mov     rdi, rbx
    lea     rsi, [rel s_debug_info]
    call    asmctx_find_section
    xor     r13d, r13d                     ; 1: .debug_info has something
    test    rax, rax
    jnz     .no_info
    cmp     qword [rdx + SECTION_size], 0
    setne   r13b
.no_info:
    xor     r14d, r14d                     ; 1: .debug_line has something
    test    r12, r12
    jz      .line_known
    cmp     qword [r12 + SECTION_size], 0
    setne   r14b
.line_known:
    cmp     qword [rel nrows], 0
    je      .no_rows
    test    r14d, r14d
    jz      .make
    mov     eax, EXIT_LINE_DUP
    cmp     byte [rel line_loc_seen], 0
    jne     .ret
    jmp     .nothing
.no_rows:
    test    r13d, r13d
    jz      .nothing
    test    r14d, r14d
    jnz     .nothing
.make:
    call    views_check
    test    rax, rax
    jnz     .ret
    test    r12, r12
    jnz     .have_line
    mov     rdi, rbx
    lea     rsi, [rel s_debug_line]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     word [rdx + SECTION_flags], 0
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     qword [rdx + SECTION_align], 1
    mov     r12, rdx
.have_line:
    mov     [rel ln_sec], r12
    push    qword [rbx + ASMCTX_curr_sec]
    call    debug_line_out
    pop     qword [rbx + ASMCTX_curr_sec]
    jmp     .ret
.nothing:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; views_check: the views again from the rows' places now; one a name or
; "view 0" holds that comes out otherwise is an error (its value is used
; already). RAX = OK or error
views_check:
    push    rbx
    push    r12
    mov     qword [rel nsecs], 0
    mov     rbx, [rel rows]
    mov     r12, [rel nrows]
.row:
    test    r12, r12
    jz      .ok
    mov     rdi, [rbx + GR_SEC]
    mov     rsi, [rbx + GR_OFF]
    movzx   edx, byte [rbx + GR_VKIND]
    call    view_next
    test    rax, rax
    jnz     .ret
    cmp     byte [rbx + GR_VKIND], GLV_NAME
    je      .held
    cmp     byte [rbx + GR_VKIND], GLV_ZERO
    jne     .next
.held:
    cmp     edx, [rbx + GR_VIEW]
    jne     .moved
.next:
    add     rbx, GR_SIZE
    dec     r12
    jmp     .row
.moved:
    mov     rax, [rbx + GR_VSYM]
    test    rax, rax
    jz      .no_name
    mov     rdi, [rax + SYMBOL_name]
    call    error_set_subject
.no_name:
    mov     eax, EXIT_LINE_VIEW_MOVED
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret

; debug_line_out: the table at the end of .debug_line (ln_sec): GNU's
; out_debug_line. RAX = OK or error
debug_line_out:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, [rel ln_sec]
    lea     rax, [rel global_ctx]
    mov     [rax + ASMCTX_curr_sec], r12
    mov     r13, [r12 + SECTION_size]      ; r13 = where the unit starts
    xor     eax, eax
    call    dw_u32                         ; unit_length (below)
    mov     eax, [rel line_level]
    call    dw_u16                         ; version
    cmp     dword [rel line_level], 5
    jb      .no_sizes
    call    dw_addr_size
    call    dw_u8                          ; address_size
    xor     eax, eax
    call    dw_u8                          ; segment_selector_size
.no_sizes:
    mov     r14, [r12 + SECTION_size]      ; r14 = header_length's place
    xor     eax, eax
    call    dw_u32
    mov     eax, 1
    call    dw_u8                          ; minimum_instruction_length
    cmp     dword [rel line_level], 4
    jb      .no_ops
    mov     eax, 1
    call    dw_u8                          ; maximum_operations_per_instruction
.no_ops:
    mov     eax, 1
    call    dw_u8                          ; default_is_stmt
    mov     eax, LINE_BASE
    call    dw_u8
    mov     eax, LINE_RANGE
    call    dw_u8
    mov     eax, OPCODE_BASE
    cmp     dword [rel line_level], 2
    jne     .base
    mov     eax, 10
.base:
    call    dw_u8                          ; opcode_base
    ; the standard opcodes' operand counts
    lea     rbx, [rel opcode_lengths]
    mov     r15d, 9
    cmp     dword [rel line_level], 3
    jb      .lengths
    mov     r15d, 12
.lengths:
    movzx   eax, byte [rbx]
    call    dw_u8
    inc     rbx
    dec     r15d
    jnz     .lengths
    call    files_out
    test    rax, rax
    jnz     .ret
    ; header_length: after its own field to here
    mov     rax, [r12 + SECTION_size]
    sub     rax, r14
    sub     rax, 4
    mov     rcx, [r12 + SECTION_data]
    mov     [rcx + r14], eax
    ; a sequence per code section, in the order their first rows came
    xor     ebx, ebx
.section:
    cmp     rbx, [rel nsecs]
    jae     .sections_done
    imul    rax, rbx, GS_SIZE
    lea     rcx, [rel secs]
    mov     rdi, [rcx + rax + GS_SEC]
    call    rows_out
    test    rax, rax
    jnz     .ret
    inc     rbx
    jmp     .section
.sections_done:
    ; unit_length
    mov     rax, [r12 + SECTION_size]
    sub     rax, r13
    sub     rax, 4
    mov     rcx, [r12 + SECTION_data]
    mov     [rcx + r13], eax
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; files_out: the directory and file tables (GNU's out_dir_and_file_list).
; RAX = OK or error
files_out:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     qword [rel file0_strp], -1
    cmp     dword [rel line_level], 5
    jb      .dirs
    ; DWARF 5: one column, the path, a string in .debug_line_str
    mov     eax, 1
    call    dw_u8
    mov     eax, DW_LNCT_path
    call    dw_uleb
    mov     eax, DW_FORM_line_strp
    call    dw_uleb
    mov     rax, [rel ndirs]
    test    rax, rax
    jnz     .dir_count
    cmp     qword [rel nfiles], 0
    je      .dir_count
    mov     eax, 1
.dir_count:
    call    dw_uleb
    mov     rax, [rel ndirs]
    or      rax, [rel nfiles]
    jz      .dirs
    call    str_section
    test    rax, rax
    jnz     .ret
    ; directory 0: the build's
    mov     rsi, 0
    cmp     qword [rel ndirs], 0
    je      .dir0_cwd
    mov     rax, [rel dirs]
    mov     rsi, [rax]
.dir0_cwd:
    test    rsi, rsi
    jnz     .dir0
    call    cwd
    mov     rsi, rax
.dir0:
    call    line_strp
    test    rax, rax
    jnz     .ret
.dirs:
    mov     ebx, 1
.dir:
    cmp     rbx, [rel ndirs]
    jae     .dirs_done
    mov     rax, [rel dirs]
    mov     rsi, [rax + rbx * 8]
    test    rsi, rsi
    jnz     .dir_named
    lea     rsi, [rel s_empty]
.dir_named:
    cmp     dword [rel line_level], 5
    jae     .dir_strp
    call    dw_cstr
    jmp     .dir_next
.dir_strp:
    call    line_strp
    test    rax, rax
    jnz     .ret
.dir_next:
    inc     rbx
    jmp     .dir
.dirs_done:
    cmp     dword [rel line_level], 5
    jae     .file_format
    xor     eax, eax
    call    dw_u8                          ; the directories' end
    jmp     .files
.file_format:
    ; DWARF 5: path, directory, and the md5 when a file has one (its first
    ; byte not 0, as GNU tells)
    xor     r15d, r15d
    xor     ebx, ebx
.md5_any:
    cmp     rbx, [rel nfiles]
    jae     .md5_known
    mov     rax, rbx
    shl     rax, 5
    add     rax, [rel files]
    cmp     byte [rax + GF_MD5], 0
    jne     .md5_yes
    inc     rbx
    jmp     .md5_any
.md5_yes:
    mov     r15d, 1
.md5_known:
    lea     eax, [r15 + 2]
    call    dw_u8                          ; the columns
    mov     eax, DW_LNCT_path
    call    dw_uleb
    mov     eax, DW_FORM_line_strp
    call    dw_uleb
    mov     eax, DW_LNCT_directory_index
    call    dw_uleb
    mov     eax, DW_FORM_udata
    call    dw_uleb
    test    r15d, r15d
    jz      .md5_column
    mov     eax, DW_LNCT_MD5
    call    dw_uleb
    mov     eax, DW_FORM_data16
    call    dw_uleb
.md5_column:
    mov     rax, [rel nfiles]
    call    dw_uleb
.files:
    xor     ebx, ebx
    cmp     dword [rel line_level], 5
    jae     .file
    mov     ebx, 1                         ; before DWARF 5: from 1
.file:
    cmp     rbx, [rel nfiles]
    jae     .files_done
    mov     r12, rbx
    shl     r12, 5
    add     r12, [rel files]               ; r12 = the entry
    cmp     qword [r12 + GF_NAME], 0
    jne     .named
    cmp     dword [rel line_level], 5
    jb      .unassigned
    test    rbx, rbx
    jnz     .unassigned
    ; no .file 0: file 1's, or ""
    lea     rax, [rel s_empty]
    mov     [r12 + GF_NAME], rax
    cmp     qword [rel nfiles], 1
    jbe     .named
    mov     rax, [rel files]
    mov     rcx, [rax + GF_SIZE + GF_NAME]
    test    rcx, rcx
    jz      .named
    mov     [r12 + GF_NAME], rcx
    mov     ecx, [rax + GF_SIZE + GF_DIR]
    mov     [r12 + GF_DIR], ecx
    test    r15d, r15d
    jz      .named
    mov     rcx, [rax + GF_SIZE + GF_MD5]
    mov     [r12 + GF_MD5], rcx
    mov     rcx, [rax + GF_SIZE + GF_MD5 + 8]
    mov     [r12 + GF_MD5 + 8], rcx
    jmp     .named
.unassigned:
    mov     rsi, rbx
    call    number_subject
    mov     eax, EXIT_LINE_UNASSIGNED
    jmp     .ret
.named:
    mov     rsi, [r12 + GF_NAME]
    cmp     dword [rel line_level], 5
    jae     .name_strp
    call    dw_cstr
    jmp     .dir_index
.name_strp:
    mov     rdx, [rel file0_strp]
    cmp     rdx, -1
    je      .name_new
    call    strp_at                        ; file 1: file 0's string
    jmp     .name_written
.name_new:
    call    line_strp
.name_written:
    test    rax, rax
    jnz     .ret
    ; file 0 that is file 1's: file 1 takes the same string
    mov     qword [rel file0_strp], -1
    test    rbx, rbx
    jnz     .dir_index
    cmp     qword [rel nfiles], 1
    jbe     .dir_index
    mov     rax, [rel files]
    mov     rcx, [r12 + GF_NAME]
    cmp     rcx, [rax + GF_SIZE + GF_NAME]
    jne     .dir_index
    mov     [rel file0_strp], rdx
.dir_index:
    mov     eax, [r12 + GF_DIR]
    call    dw_uleb
    cmp     dword [rel line_level], 5
    jae     .md5
    xor     eax, eax
    call    dw_uleb                        ; time
    xor     eax, eax
    call    dw_uleb                        ; size
    jmp     .file_next
.md5:
    test    r15d, r15d
    jz      .file_next
    xor     r13d, r13d
.md5_byte:
    movzx   eax, byte [r12 + GF_MD5 + r13]
    call    dw_u8
    inc     r13d
    cmp     r13d, 16
    jb      .md5_byte
.file_next:
    inc     rbx
    jmp     .file
.files_done:
    xor     eax, eax
    cmp     dword [rel line_level], 5
    jae     .ret
    call    dw_u8                          ; the files' end
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; str_section: str_sec = .debug_line_str (made when the source has none).
; RAX = OK or error
str_section:
    lea     rdi, [rel global_ctx]
    lea     rsi, [rel s_debug_line_str]
    call    asmctx_find_section
    test    rax, rax
    jz      .found
    lea     rdi, [rel global_ctx]
    lea     rsi, [rel s_debug_line_str]
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     word [rdx + SECTION_flags], SHF_MERGE | SHF_STRINGS
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     qword [rdx + SECTION_align], 1
    mov     byte [rdx + SECTION_entsize], 1
.found:
    mov     [rel str_sec], rdx
    xor     eax, eax
.ret:
    ret

; line_strp: the string rsi at the end of .debug_line_str, and in
; .debug_line a 4-byte offset to it (relocated). RAX = OK or error, RDX =
; its offset
line_strp:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    lea     rbx, [rel global_ctx]
    mov     rax, [rel str_sec]
    mov     [rbx + ASMCTX_curr_sec], rax
    mov     r13, [rax + SECTION_size]
    mov     rsi, r12
    call    dw_cstr
    mov     rax, [rel ln_sec]
    mov     [rbx + ASMCTX_curr_sec], rax
    mov     rdx, r13
    call    strp_at
    mov     rdx, r13
    pop     r13
    pop     r12
    pop     rbx
    ret

; strp_at: in .debug_line a 4-byte offset rdx into .debug_line_str
; (R_X86_64_32 against its section). RAX = OK or error; RDX kept
strp_at:
    push    rdx
    mov     rsi, [rel str_sec]
    mov     r8d, R_X86_64_32
    call    dw_sec_reloc
    test    rax, rax
    jnz     .ret
    xor     eax, eax
    call    dw_u32
    xor     eax, eax
.ret:
    pop     rdx
    ret

; rows_out: the sequence of section rdi's rows (GNU's process_entries).
; RAX = OK or error
rows_out:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r14, rdi
    mov     dword [rel ps_file], 1
    mov     dword [rel ps_line], 1
    mov     dword [rel ps_col], 0
    mov     dword [rel ps_isa], 0
    mov     byte [rel ps_flags], 0         ; is_stmt 1
    mov     byte [rel ps_first], 1
    mov     rbx, [rel rows]
    mov     r12, [rel nrows]
.row:
    test    r12, r12
    jz      .end
    cmp     [rbx + GR_SEC], r14
    jne     .next
    mov     eax, [rbx + GR_FILE]
    cmp     eax, [rel ps_file]
    je      .same_file
    mov     [rel ps_file], eax
    mov     eax, DW_LNS_set_file
    call    dw_u8
    mov     eax, [rel ps_file]
    call    dw_uleb
.same_file:
    mov     eax, [rbx + GR_COL]
    cmp     eax, [rel ps_col]
    je      .same_col
    mov     [rel ps_col], eax
    mov     eax, DW_LNS_set_column
    call    dw_u8
    mov     eax, [rel ps_col]
    call    dw_uleb
.same_col:
    mov     r13d, [rbx + GR_DISC]
    test    r13d, r13d
    jz      .no_disc
    xor     eax, eax
    call    dw_u8                          ; extended
    mov     eax, r13d
    call    uleb_size
    inc     eax
    call    dw_sleb
    mov     eax, DW_LNE_set_discriminator
    call    dw_u8
    mov     eax, r13d
    call    dw_uleb
.no_disc:
    mov     eax, [rbx + GR_ISA]
    cmp     eax, [rel ps_isa]
    je      .same_isa
    mov     [rel ps_isa], eax
    mov     eax, DW_LNS_set_isa
    call    dw_u8
    mov     eax, [rel ps_isa]
    call    dw_uleb
.same_isa:
    movzx   eax, byte [rbx + GR_FLAGS]
    xor     al, [rel ps_flags]
    test    al, GLF_NOSTMT
    jz      .same_stmt
    movzx   eax, byte [rbx + GR_FLAGS]
    mov     [rel ps_flags], al
    mov     eax, DW_LNS_negate_stmt
    call    dw_u8
.same_stmt:
    test    byte [rbx + GR_FLAGS], GLF_BB
    jz      .no_bb
    mov     eax, DW_LNS_set_basic_block
    call    dw_u8
.no_bb:
    test    byte [rbx + GR_FLAGS], GLF_PROLOGUE
    jz      .no_pro
    mov     eax, DW_LNS_set_prologue_end
    call    dw_u8
.no_pro:
    test    byte [rbx + GR_FLAGS], GLF_EPILOGUE
    jz      .no_epi
    mov     eax, DW_LNS_set_epilogue_begin
    call    dw_u8
.no_epi:
    mov     edi, [rbx + GR_LINE]
    sub     edi, [rel ps_line]             ; the line's step
    cmp     byte [rel ps_first], 0
    jne     .set_address
    mov     rsi, [rbx + GR_OFF]
    cmp     byte [rbx + GR_VKIND], GLV_RESET
    jne     .advance
    ; "view -0": the address set again where GNU as cannot tell it moved
    ; on - the same place in one frag, or a frag's start after a row at the
    ; end of the one before
    mov     rax, [rel ps_prev]
    mov     ecx, [rbx + GR_FRAG]
    cmp     ecx, [rax + GR_FRAG]
    jne     .other_frag
    cmp     rsi, [rel ps_off]
    je      .set_address
    jmp     .advance
.other_frag:
    test    byte [rbx + GR_FPOS], GRF_START
    jz      .advance
    test    byte [rax + GR_FPOS], GRF_END
    jnz     .set_address
.advance:
    sub     rsi, [rel ps_off]
    call    line_addr
    jmp     .stepped
.set_address:
    push    rdi
    xor     eax, eax
    call    dw_u8
    call    dw_addr_size
    inc     eax
    call    dw_uleb
    mov     eax, DW_LNE_set_address
    call    dw_u8
    mov     rsi, r14
    mov     rdx, [rbx + GR_OFF]
    call    dw_addr_type
    call    dw_sec_reloc
    pop     rdi
    test    rax, rax
    jnz     .ret
    push    rdi
    xor     eax, eax
    call    dw_address
    pop     rdi
    xor     esi, esi
    call    line_addr
.stepped:
    mov     byte [rel ps_first], 0
    mov     [rel ps_prev], rbx
    mov     eax, [rbx + GR_LINE]
    mov     [rel ps_line], eax
    mov     rax, [rbx + GR_OFF]
    mov     [rel ps_off], rax
.next:
    add     rbx, GR_SIZE
    dec     r12
    jmp     .row
.end:
    ; to the section's end, and the sequence's
    mov     edi, LINE_END_SEQ
    mov     rsi, [r14 + SECTION_size]
    sub     rsi, [rel ps_off]
    call    line_addr
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; line_addr: a row edi lines and rsi bytes on, as few bytes as GNU writes
; it (emit_inc_line_addr; LINE_END_SEQ: the end of the sequence)
line_addr:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi                       ; the line's step
    mov     r12, rsi                       ; the address's
    cmp     ebx, LINE_END_SEQ
    jne     .row
    cmp     r12, MAX_SPECIAL_ADDR
    jne     .end_advance
    mov     eax, DW_LNS_const_add_pc
    call    dw_u8
    jmp     .end_seq
.end_advance:
    test    r12, r12
    jz      .end_seq
    mov     eax, DW_LNS_advance_pc
    call    dw_u8
    mov     rax, r12
    call    dw_uleb
.end_seq:
    xor     eax, eax
    call    dw_u8
    mov     eax, 1
    call    dw_u8
    mov     eax, DW_LNE_end_sequence
    call    dw_u8
    jmp     .ret
.row:
    xor     r13d, r13d                     ; 1: a copy at the end
    lea     eax, [rbx - LINE_BASE]
    cmp     eax, LINE_RANGE
    jb      .in_range
    ; past a special opcode's lines: advance_line first
    mov     eax, DW_LNS_advance_line
    call    dw_u8
    movsxd  rax, ebx
    call    dw_sleb
    xor     ebx, ebx
    mov     r13d, 1
.in_range:
    test    ebx, ebx
    jnz     .special
    test    r12, r12
    jnz     .special
    mov     eax, DW_LNS_copy
    call    dw_u8
    jmp     .ret
.special:
    lea     ecx, [rbx - LINE_BASE + OPCODE_BASE]   ; the opcode at no address step
    cmp     r12, 256 + MAX_SPECIAL_ADDR
    jae     .advance_pc
    imul    eax, r12d, LINE_RANGE
    add     eax, ecx
    cmp     eax, 255
    ja      .const_add
    call    dw_u8
    jmp     .ret
.const_add:
    cmp     r12, MAX_SPECIAL_ADDR
    jb      .advance_pc
    lea     eax, [r12 - MAX_SPECIAL_ADDR]
    imul    eax, eax, LINE_RANGE
    add     eax, ecx
    cmp     eax, 255
    ja      .advance_pc
    push    rax
    mov     eax, DW_LNS_const_add_pc
    call    dw_u8
    pop     rax
    call    dw_u8
    jmp     .ret
.advance_pc:
    push    rcx
    mov     eax, DW_LNS_advance_pc
    call    dw_u8
    mov     rax, r12
    call    dw_uleb
    pop     rcx
    mov     eax, ecx
    test    r13d, r13d
    jz      .last
    mov     eax, DW_LNS_copy
.last:
    call    dw_u8
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; uleb_size: eax = the bytes eax takes as unsigned LEB128
uleb_size:
    mov     ecx, eax
    xor     eax, eax
.byte:
    inc     eax
    shr     ecx, 7
    jnz     .byte
    ret

[SECTION .rodata]
; DW_LNS_copy .. DW_LNS_set_isa: their operand counts
opcode_lengths: db 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1
