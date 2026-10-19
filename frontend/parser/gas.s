;
; ============================================
; File     : frontend/parser/gas.s
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
; GNU AS DIRECTIVES, IN UTASM'S SYNTAX
; ============================================================================
; The directives GNU as code is written with, beside NASM's: a line that
; starts with one of their names (not followed by ':', which makes a label
; of it) is the directive. Those that are a NASM directive under another
; name are handed on renamed (.globl is global, .byte is db, .section is
; section); the others are worked here:
;
;   .text .data .bss              section .text ...
;   .section NAME[, "FLAGS"[, @TYPE[, ENTSIZE]]]  GNU's flag letters (a w
;                                 x M S T), types (@progbits @nobits @note
;                                 @init_array ...) and entry size (M's):
;                                 the section's when it is new (parser.s)
;   .pushsection / .popsection / .previous   the section stack, the last one
;   .ascii .asciz .string         strings with GNU's escapes (\n \t \b \f \v
;                                 \r \x41 \101 \\ \"; \e is "e", as GNU's)
;   .zero / .skip / .space N[, F] N bytes F (reserved in a nobits section)
;   .fill R[, S[, V]]             R times the S-byte value V
;   .uleb128 / .sleb128           LEB128 numbers
;   .align / .balign N[, F[, MAX]], .p2align K[, F[, MAX]]   no padding
;                                 when more than MAX bytes are needed (as
;                                 the code stands when it is read)
;   .octa                         16-byte integers
;   .equ / .set N, E, .equiv N, E constants (.set: again, a new value;
;                                 .equiv: never twice)
;   .type S, @function|@object|@tls_object|@notype, .size S, E,
;   .hidden / .internal / .protected S, ...   the symbol's type, size,
;                                 visibility, once the source is read
;                                 (gas_finish): S may be defined later
;   .comm S, N[, A], .lcomm S, N[, A]   a common block / N bytes of .bss
;   .org N[, F]                   padding up to offset N of the section
;   .code16 / .code32 / .code64   bits 16 / 32 / 64
;   .ident "TEXT"                 TEXT in .comment, as GNU's
;   .intel_syntax                 ptr, flat and offset as %use masm's
;                                 ("DWORD PTR x[rip]", "OFFSET FLAT:x")
;   .file "NAME"                  the object's FILE symbol
;   .file N ..., .loc N L ...     the line table (debug/line.s)
;   .arch                         taken, nothing done
;   .att_syntax [noprefix]        AT&T syntax from here (frontend/parser/att.s)
;   .macro .endm .exitm .purgem .rept .irp .irpc .endr, .if & co, .else,
;   .elseif, .endif               frontend/parser/gas_macro.s
;
; "." alone in an expression is $ (parser.s), as GNU writes the location.
; A name followed by a NASM word ("equ", "resd", "db", "times") is a label
; as it was: ".size resd 1" in a struc is its field.

extern  preprocessor_peek_token
extern  preprocessor_next_token
extern  preprocessor_unread_token
extern  parser_evaluate_expression
extern  parser_gas_equ
extern  parser_gas_name
extern  parser_define_label
extern  parser_handle_section_directive
extern  symbol_find
extern  symbol_add
extern  asm_ctx_emit_byte
extern  asm_ctx_align
extern  asm_ctx_align_fill
extern  asm_ctx_align_spec
extern  align_gas_spec
extern  asm_ctx_padto
extern  lst_mark
extern  asm_bits
extern  global_ctx
extern  str_cmp
extern  str_cmp_kw
extern  mem_reserve
extern  error_set_subject
extern  prep_push_buffer
extern  masm_enabled
extern  gas_macro_define, gas_macro_exit, gas_macro_purge
extern  gas_repeat, gas_if, gas_else, gas_endif

; actions
%define G_RENAME     1          ; arg: the NASM directive's name
%define G_SECNAME    2          ; arg: the section's name (section NAME)
%define G_SECTION    3
%define G_PUSHSEC    4
%define G_POPSEC     5
%define G_PREVIOUS   6
%define G_ASCII      7          ; arg: 1 with a NUL after each string
%define G_SPACE      8
%define G_FILL       9
%define G_LEB        10         ; arg: 1 signed
%define G_ALIGN      11         ; arg: 1 p2align
%define G_EQU        12         ; arg: 0 .equ, 1 .set, 2 .equiv
%define G_TYPE       13
%define G_SIZE       14
%define G_VIS        15         ; arg: STV_* visibility
%define G_COMM       16
%define G_LCOMM      17
%define G_ORG        18
%define G_BITS       19         ; arg: 16 / 32 / 64
%define G_IGNORE     20
%define G_ATT        21
%define G_OCTA       22
%define G_IDENT      23
%define G_INTEL      24
%define G_MACRO      25             ; frontend/parser/gas_macro.s
%define G_STRAY      26             ; .endm / .endr out of place
%define G_EXITM      27
%define G_PURGEM     28
%define G_REPT       29             ; arg: 0 .rept, 1 .irp, 2 .irpc
%define G_IF         30             ; arg: the kind (gas_if)
%define G_ELSE       31             ; arg: 0 .else, 1 .elseif
%define G_ENDIF      32

%define PEND_TYPE    1
%define PEND_SIZE    2
%define PEND_VIS     3
%define PEND_CAP     (1 << 16)
%define SECSTACK_MAX 64

%macro gas_ent 3
    db %1, 0
    times 15 - %strlen(%1) db 0
    db %2
    dq %3
%endmacro
%define GAS_ENT_SIZE 25

[SECTION .rodata]
s_global:   db "global", 0
s_weak:     db "weak", 0
s_local:    db "local", 0
s_extern:   db "extern", 0
s_incbin:   db "incbin", 0
s_db:       db "db", 0
s_dw:       db "dw", 0
s_dd:       db "dd", 0
s_dq:       db "dq", 0
s_do:       db "do", 0
s_section:  db "section", 0
s_text:     db ".text", 0
s_data:     db ".data", 0
s_bss:      db ".bss", 0
s_comment:  db ".comment", 0
align 8
gm_calls:   dq gas_macro_define, gas_stray, gas_macro_exit, gas_macro_purge
            dq gas_repeat, gas_if, gas_else, gas_endif
s_intel:    db ".intel_syntax", 0
s_noprefix: db "noprefix", 0
intel_text: db 10
            db "%idefine ptr __?masm_ptr?__", 10
            db "%idefine flat __?masm_flat?__", 10
            db "%idefine offset", 10
            ; GNU's (MASM's) size names: XMMWORD PTR ... MMWORD PTR
            db "%idefine xmmword oword", 10
            db "%idefine ymmword yword", 10
            db "%idefine zmmword zword", 10
            db "%idefine mmword qword", 10
            ; movabs: GCC's for an immediate past 32 bits, which mov gives
            ; its imm64 (B8+r) as it is
            db "%idefine movabs mov", 10
            ; GNU's raw prefixes (GCC's TLS sequence: "data16 lea rdi, ...",
            ; "rex64" on a line of its own): NASM's osp / asp, the byte
            db "%idefine data16 osp", 10
            db "%idefine data32 osp", 10
            db "%idefine addr16 asp", 10
            db "%idefine addr32 asp", 10
            db "%idefine rex64 db 0x48", 10
intel_text_len equ $ - intel_text

gas_table:
    gas_ent ".globl", G_RENAME, s_global
    gas_ent ".global", G_RENAME, s_global
    gas_ent ".weak", G_RENAME, s_weak
    gas_ent ".local", G_RENAME, s_local
    gas_ent ".extern", G_RENAME, s_extern
    gas_ent ".incbin", G_RENAME, s_incbin
    gas_ent ".byte", G_RENAME, s_db
    gas_ent ".short", G_RENAME, s_dw
    gas_ent ".word", G_RENAME, s_dw
    gas_ent ".value", G_RENAME, s_dw
    gas_ent ".hword", G_RENAME, s_dw
    gas_ent ".2byte", G_RENAME, s_dw
    gas_ent ".long", G_RENAME, s_dd
    gas_ent ".int", G_RENAME, s_dd
    gas_ent ".4byte", G_RENAME, s_dd
    gas_ent ".quad", G_RENAME, s_dq
    gas_ent ".8byte", G_RENAME, s_dq
    gas_ent ".octa", G_OCTA, 0
    gas_ent ".text", G_SECNAME, s_text
    gas_ent ".data", G_SECNAME, s_data
    gas_ent ".bss", G_SECNAME, s_bss
    gas_ent ".section", G_SECTION, 0
    gas_ent ".pushsection", G_PUSHSEC, 0
    gas_ent ".popsection", G_POPSEC, 0
    gas_ent ".previous", G_PREVIOUS, 0
    gas_ent ".ascii", G_ASCII, 0
    gas_ent ".asciz", G_ASCII, 1
    gas_ent ".string", G_ASCII, 1
    gas_ent ".zero", G_SPACE, 0
    gas_ent ".skip", G_SPACE, 0
    gas_ent ".space", G_SPACE, 0
    gas_ent ".fill", G_FILL, 0
    gas_ent ".uleb128", G_LEB, 0
    gas_ent ".sleb128", G_LEB, 1
    gas_ent ".align", G_ALIGN, 0
    gas_ent ".balign", G_ALIGN, 0
    gas_ent ".p2align", G_ALIGN, 1
    gas_ent ".equ", G_EQU, 0
    gas_ent ".set", G_EQU, 1
    gas_ent ".equiv", G_EQU, 2
    gas_ent ".type", G_TYPE, 0
    gas_ent ".size", G_SIZE, 0
    gas_ent ".hidden", G_VIS, 2
    gas_ent ".internal", G_VIS, 1
    gas_ent ".protected", G_VIS, 3
    gas_ent ".comm", G_COMM, 0
    gas_ent ".lcomm", G_LCOMM, 0
    gas_ent ".org", G_ORG, 0
    gas_ent ".code16", G_BITS, 16
    gas_ent ".code32", G_BITS, 32
    gas_ent ".code64", G_BITS, 64
    gas_ent ".intel_syntax", G_INTEL, 0
    gas_ent ".ident", G_IDENT, 0
    gas_ent ".file", G_IGNORE, 1
    gas_ent ".loc", G_IGNORE, 2
    gas_ent ".arch", G_IGNORE, 0
    gas_ent ".att_syntax", G_ATT, 0
    gas_ent ".macro", G_MACRO, 0
    gas_ent ".endm", G_STRAY, 0
    gas_ent ".exitm", G_EXITM, 0
    gas_ent ".purgem", G_PURGEM, 0
    gas_ent ".rept", G_REPT, 0
    gas_ent ".irp", G_REPT, 1
    gas_ent ".irpc", G_REPT, 2
    gas_ent ".endr", G_STRAY, 0
    gas_ent ".if", G_IF, 0
    gas_ent ".ifne", G_IF, 0
    gas_ent ".ifeq", G_IF, 1
    gas_ent ".ifgt", G_IF, 2
    gas_ent ".ifge", G_IF, 3
    gas_ent ".iflt", G_IF, 4
    gas_ent ".ifle", G_IF, 5
    gas_ent ".ifdef", G_IF, 6
    gas_ent ".ifndef", G_IF, 7
    gas_ent ".ifnotdef", G_IF, 7
    gas_ent ".ifb", G_IF, 8
    gas_ent ".ifnb", G_IF, 9
    gas_ent ".ifc", G_IF, 10
    gas_ent ".ifnc", G_IF, 11
    gas_ent ".ifeqs", G_IF, 12
    gas_ent ".ifnes", G_IF, 13
    gas_ent ".else", G_ELSE, 0
    gas_ent ".elseif", G_ELSE, 1
    gas_ent ".endif", G_ENDIF, 0
    db 0

nw_sizes:   db "bwdqtoyz", 0

; the type words of .type(@function, function, %function's word ...)
type_words:
    db "function", 0, ETYPE_FUNC
    db "object", 0, ETYPE_OBJECT
    db "tls_object", 0, ETYPE_TLS
    db "notype", 0, ETYPE_NOTYPE
    db "common", 0, ETYPE_OBJECT
    db "gnu_indirect_function", 0, 10
    db 0
; the section types of .section
sec_types:
    db "progbits", 0, SHT_PROGBITS
    db "nobits", 0, SHT_NOBITS
    db "note", 0, 7
    db "init_array", 0, 14
    db "fini_array", 0, 15
    db "preinit_array", 0, 16
    db 0

[SECTION .bss]
alignb 8
gas_tok:        resb TOKEN_SIZE     ; a token handed back (the section's name)
gas_minus:      resb TOKEN_SIZE     ; a "-" in it, to put back
alignb 8
global gas_file_name
gas_file_name:  resq 1              ; .file "NAME": the FILE symbol's name
align_from:     resq 1              ; an alignment's start (debug/line.s)
pend:           resq 1              ; the pending .type / .size / visibilities
pend_n:         resq 1
secstack:       resq SECSTACK_MAX   ; .pushsection's sections
secstack_n:     resq 1
global sec_previous
sec_previous:   resq 1              ; the section before the last switch (.previous)
global gas_sec_flags, gas_sec_type, gas_sec_set, gas_sec_entsize
gas_sec_flags:  resw 1              ; .section's flags, for the section directive
gas_sec_set:    resb 1              ; 1: they were given
gas_sec_entsize: resb 1             ; ... its entry size (0: none)
alignb 4
gas_sec_type:   resd 1              ; ... its type (0: by its name)

[SECTION .text]

; ---- gas_directive ------------------------
;
; gas_directive
; A statement word that may be one of GNU as's directives.
; Input    : rdi = PrepState, rsi = the word, in lower case
; Output   : eax = 0: not one (or a label: ".text:"); 1: done, rdx = OK or
;            an error; 2: NASM's directive rdx under its own name, to be
;            done by the caller (the operands are as they were)
;
global gas_directive
gas_directive:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    cmp     byte [r12], '.'
    jne     .none
    lea     r13, [rel gas_table]
.find:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .found
    add     r13, GAS_ENT_SIZE
    jmp     .find
.found:
    ; ".text:" is a label of that name
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .none
    cmp     byte [rdx + TOKEN_kind], TOK_COLON
    je      .none
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .is_gas
    mov     rdi, [rdx + TOKEN_value]
    call    gas_nasm_word
    test    eax, eax
    jnz     .none                          ; ".size resd 1": a label
.is_gas:
    movzx   eax, byte [r13 + 16]
    mov     r14, [r13 + 17]                ; its argument
    cmp     eax, G_RENAME
    je      .rename
    cmp     eax, G_SECNAME
    je      .secname
    cmp     eax, G_SECTION
    je      .section
    cmp     eax, G_PUSHSEC
    je      .pushsec
    cmp     eax, G_POPSEC
    je      .popsec
    cmp     eax, G_PREVIOUS
    je      .previous
    cmp     eax, G_ASCII
    je      .ascii
    cmp     eax, G_SPACE
    je      .space
    cmp     eax, G_FILL
    je      .fill
    cmp     eax, G_LEB
    je      .leb
    cmp     eax, G_ALIGN
    je      .align
    cmp     eax, G_EQU
    je      .equ
    cmp     eax, G_TYPE
    je      .type
    cmp     eax, G_SIZE
    je      .size
    cmp     eax, G_VIS
    je      .vis
    cmp     eax, G_COMM
    je      .comm
    cmp     eax, G_LCOMM
    je      .lcomm
    cmp     eax, G_ORG
    je      .org
    cmp     eax, G_BITS
    je      .bits
    cmp     eax, G_ATT
    je      .att
    cmp     eax, G_OCTA
    je      .octa
    cmp     eax, G_IDENT
    je      .ident
    cmp     eax, G_INTEL
    je      .intel
    cmp     eax, G_MACRO
    jb      .not_gm
    ; .macro, .rept, .if ... (gas_macro.s): rdi = PrepState, esi = the kind
    sub     eax, G_MACRO
    lea     rcx, [rel gm_calls]
    mov     rcx, [rcx + rax * 8]
    mov     rdi, rbx
    mov     esi, r14d
    call    rcx
    mov     rdx, rax
    jmp     .done_rdx
.not_gm:
    ; .loc: a row of the line table (debug/line.s)
    cmp     r14d, 2
    jne     .not_loc
    mov     rdi, rbx
    extern  line_loc
    call    line_loc
    jmp     .line_done
.not_loc:
    ; G_IGNORE: the rest of the line - .file "NAME" names the object's
    ; FILE symbol, as GNU as; ".file 1 ..." is the line table's
    cmp     r14d, 1
    jne     .ignored
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ignored
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .file_name
    mov     rdi, rbx
    extern  line_file
    call    line_file
.line_done:
    test    rax, rax
    jz      .ignored
    push    rax
    call    .skip_line
    pop     rdx
    mov     eax, 1
    jmp     .ret
.file_name:
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .ignored
    mov     rax, [rdx + TOKEN_value]
    mov     [rel gas_file_name], rax
.ignored:
    call    .skip_line
    jmp     .done_ok

.rename:
    mov     rdx, r14
    mov     eax, 2
    jmp     .ret

.secname:
    ; ".text": "section .text" - its name handed back as the next token
    mov     rdi, r14
    call    .push_name
    lea     rdx, [rel s_section]
    mov     eax, 2
    jmp     .ret

.pushsec:
    mov     rax, [rel secstack_n]
    cmp     rax, SECSTACK_MAX
    jae     .bad
    mov     rcx, [rbx + PREP_ctx]
    mov     rcx, [rcx + ASMCTX_curr_sec]
    lea     rdx, [rel secstack]
    mov     [rdx + rax*8], rcx
    inc     qword [rel secstack_n]
    ; fall into .section
.section:
    ; NAME[, "FLAGS"[, @TYPE[, ...]]]: the name read, the rest worked out
    ; here, the name handed back to the section directive
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    je      .sec_named
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
.sec_named:
    lea     rdi, [rel gas_tok]
    mov     rsi, rdx
    copy_token
.sec_glue:
    ; ".note.GNU-stack": a name with "-" in it lexes as pieces - those
    ; written together are one name, read here (the section directive
    ; joins them too, but took the flags and @TYPE after them as NASM's:
    ; ',"",@progbits' left a label "progbits")
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    jne     .sec_glued
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [rel gas_tok + TOKEN_line]
    jne     .sec_glued
    movzx   eax, word [rel gas_tok + TOKEN_col]
    movzx   ecx, word [rel gas_tok + TOKEN_len]
    add     eax, ecx
    cmp     ax, [rdx + TOKEN_col]
    jne     .sec_glued
    mov     rdi, rbx
    call    preprocessor_next_token        ; the "-"
    lea     rdi, [rel gas_minus]
    mov     rsi, rdx
    copy_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .err
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_IDENT
    je      .sec_piece_at
    cmp     eax, TOK_NUMBER
    jne     .sec_unminus
.sec_piece_at:
    mov     eax, [rdx + TOKEN_line]
    cmp     eax, [rel gas_minus + TOKEN_line]
    jne     .sec_unminus
    movzx   eax, word [rel gas_minus + TOKEN_col]
    inc     eax
    cmp     ax, [rdx + TOKEN_col]
    jne     .sec_unminus
    mov     rdi, rbx
    call    preprocessor_next_token        ; the piece
    test    rax, rax
    jnz     .err
    ; the name so far, "-", the piece
    push    rdx
    mov     rdi, [rdx + TOKEN_value]
    extern  str_len
    call    str_len
    movzx   ecx, word [rel gas_tok + TOKEN_len]
    lea     rsi, [rcx + rax + 2]
    push    rax
    mov     rdi, [rbx + PREP_arena]
    extern  arena_alloc
    call    arena_alloc
    pop     r8                             ; the piece's length
    pop     r9                             ; its token
    test    rax, rax
    jnz     .err
    mov     rdi, rdx
    mov     rsi, [rel gas_tok + TOKEN_value]
    movzx   ecx, word [rel gas_tok + TOKEN_len]
    rep movsb
    mov     byte [rdi], '-'
    inc     rdi
    mov     rsi, [r9 + TOKEN_value]
    mov     rcx, r8
    rep movsb
    mov     byte [rdi], 0
    mov     [rel gas_tok + TOKEN_value], rdx
    sub     rdi, rdx
    mov     [rel gas_tok + TOKEN_len], di
    jmp     .sec_glue
.sec_unminus:
    mov     rdi, rbx
    lea     rsi, [rel gas_minus]
    call    preprocessor_unread_token
.sec_glued:
    mov     byte [rel gas_sec_set], 0
    mov     byte [rel gas_sec_entsize], 0
    mov     word [rel gas_sec_flags], 0
    mov     dword [rel gas_sec_type], 0
    call    .comma
    jnz     .sec_go
    ; "FLAGS"
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
    mov     byte [rel gas_sec_set], 1
    mov     rsi, [rdx + TOKEN_value]
    xor     ecx, ecx
.sec_flag:
    movzx   eax, byte [rsi]
    inc     rsi
    test    eax, eax
    jz      .sec_flags_done
    mov     edx, SHF_ALLOC
    cmp     eax, 'a'
    je      .sec_flag_or
    mov     edx, SHF_WRITE
    cmp     eax, 'w'
    je      .sec_flag_or
    mov     edx, SHF_EXECINSTR
    cmp     eax, 'x'
    je      .sec_flag_or
    mov     edx, 0x10                      ; SHF_MERGE
    cmp     eax, 'M'
    je      .sec_flag_or
    mov     edx, 0x20                      ; SHF_STRINGS
    cmp     eax, 'S'
    je      .sec_flag_or
    mov     edx, SHF_TLS
    cmp     eax, 'T'
    je      .sec_flag_or
    jmp     .sec_flag                      ; (G o e d R ...: not kept)
.sec_flag_or:
    or      ecx, edx
    jmp     .sec_flag
.sec_flags_done:
    mov     [rel gas_sec_flags], cx
    call    .comma
    jnz     .sec_go
    ; @TYPE ("@nobits", or "nobits")
    call    .type_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .sec_rest
    mov     rsi, [rdx + TOKEN_value]
    lea     rdi, [rel sec_types]
    call    .word_value
    test    eax, eax
    js      .sec_rest
    mov     [rel gas_sec_type], eax
    ; ENTSIZE (with M)
    call    .comma
    jnz     .sec_go
    call    .const
    jnz     .err_rdx
    cmp     rdx, 255
    ja      .bad
    mov     [rel gas_sec_entsize], dl
.sec_rest:
    call    .skip_line                     ; (a group, "comdat": not kept)
.sec_go:
    ; .init_array / .fini_array / .preinit_array: GNU's entry size, 8
    mov     eax, [rel gas_sec_type]
    cmp     eax, 14
    jb      .sec_es_known
    cmp     eax, 16
    ja      .sec_es_known
    cmp     byte [rel gas_sec_entsize], 0
    jne     .sec_es_known
    mov     byte [rel gas_sec_entsize], 8
.sec_es_known:
    ; M without an entry size: GNU's "entity size for SHF_MERGE not
    ; specified" (a linker refuses the section)
    test    word [rel gas_sec_flags], 0x10
    jz      .sec_merge_ok
    cmp     byte [rel gas_sec_entsize], 0
    mov     edx, EXIT_MERGE_ENTSIZE
    je      .done_rdx
.sec_merge_ok:
    ; a section of GNU's flags and no type: progbits, nobits by the name
    cmp     byte [rel gas_sec_set], 0
    je      .sec_handed
    cmp     dword [rel gas_sec_type], 0
    jne     .sec_handed
    mov     dword [rel gas_sec_type], SHT_PROGBITS
    mov     rsi, [rel gas_tok + TOKEN_value]
    cmp     dword [rsi], '.bss'
    je      .sec_nobits
    cmp     dword [rsi], '.tbs'
    jne     .sec_handed
    cmp     byte [rsi + 4], 's'
    jne     .sec_handed
.sec_nobits:
    mov     dword [rel gas_sec_type], SHT_NOBITS
.sec_handed:
    mov     rdi, rbx
    lea     rsi, [rel gas_tok]
    call    preprocessor_unread_token
    lea     rdx, [rel s_section]
    mov     eax, 2
    jmp     .ret

.popsec:
    mov     rax, [rel secstack_n]
    test    rax, rax
    mov     edx, EXIT_POPSECTION
    jz      .done_rdx
    dec     rax
    mov     [rel secstack_n], rax
    lea     rdx, [rel secstack]
    mov     rcx, [rdx + rax*8]
    jmp     .switch_to
.previous:
    mov     rcx, [rel sec_previous]
    test    rcx, rcx
    jz      .done_ok
.switch_to:
    ; to section rcx, the one left the previous
    mov     rdx, [rbx + PREP_ctx]
    mov     rax, [rdx + ASMCTX_curr_sec]
    mov     [rel sec_previous], rax
    mov     [rdx + ASMCTX_curr_sec], rcx
    jmp     .done_ok

.ascii:
    ; "...", "..." - C's escapes in a "..." string (a `...` one has them
    ; already, NASM's), a NUL after each for .asciz / .string
.ascii_next:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
    mov     r15, rdx
    mov     rsi, [r15 + TOKEN_value]
    movzx   r13d, word [r15 + TOKEN_len]
    test    byte [r15 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .ascii_len
    mov     r13, -1                        ; (to its NUL)
.ascii_len:
    cmp     byte [r15 + TOKEN_quote], '"'
    jne     .ascii_raw
    call    .emit_escaped
    jmp     .ascii_nul
.ascii_raw:
    test    r13, r13
    jz      .ascii_nul
    movzx   eax, byte [rsi]
    cmp     r13, -1
    jne     .ascii_byte
    test    eax, eax
    jz      .ascii_nul
.ascii_byte:
    push    rsi
    mov     esi, eax
    call    .emit
    pop     rsi
    inc     rsi
    cmp     r13, -1
    je      .ascii_raw
    dec     r13
    jmp     .ascii_raw
.ascii_nul:
    test    r14, r14
    jz      .ascii_comma
    xor     esi, esi
    call    .emit
.ascii_comma:
    call    .comma
    jz      .ascii_next
    jmp     .done_ok

.space:
    ; N[, FILL]
    call    .const
    jnz     .err_rdx
    mov     r13, rdx
    xor     r14d, r14d
    call    .comma
    jnz     .space_emit
    call    .const
    jnz     .err_rdx
    mov     r14, rdx
.space_emit:
    test    r13, r13
    js      .bad
    ; a nobits section: reserved
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .space_bytes
    cmp     dword [rax + SECTION_elf_type], SHT_NOBITS
    jne     .space_bytes
    add     [rax + SECTION_size], r13
    jmp     .done_ok
.space_bytes:
    test    r13, r13
    jz      .done_ok
    mov     esi, r14d
    call    .emit
    dec     r13
    jmp     .space_bytes

.fill:
    ; REPEAT[, SIZE[, VALUE]]: the value's low 4 bytes, the rest zero
    call    .const
    jnz     .err_rdx
    mov     r13, rdx
    mov     r14d, 1
    xor     r15d, r15d
    call    .comma
    jnz     .fill_go
    call    .const
    jnz     .err_rdx
    mov     r14, rdx
    call    .comma
    jnz     .fill_go
    call    .const
    jnz     .err_rdx
    mov     r15d, edx
.fill_go:
    test    r13, r13
    js      .bad
    cmp     r14, 8
    jbe     .fill_rep
    mov     r14d, 8
.fill_rep:
    test    r13, r13
    jz      .done_ok
    xor     ecx, ecx
.fill_byte:
    cmp     rcx, r14
    jae     .fill_one
    xor     esi, esi
    cmp     ecx, 4
    jae     .fill_put
    mov     eax, r15d
    push    rcx
    shl     ecx, 3
    shr     eax, cl
    pop     rcx
    movzx   esi, al
.fill_put:
    push    rcx
    call    .emit
    pop     rcx
    inc     ecx
    jmp     .fill_byte
.fill_one:
    dec     r13
    jmp     .fill_rep

.leb:
    ; numbers, each LEB128 (r14: 1 signed). One that measures code ("b - a"
    ; of labels jumps lie between, as GCC's -g writes them) comes from the
    ; code laid out: the second pass has it (core/known.s), this one writes
    ; a byte for it
.leb_next:
    extern  expr_late_diff, known_active, known_guessed
    mov     byte [rel expr_late_diff], 1
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel expr_late_diff], 0
    test    rax, rax
    jnz     .leb_err
    test    rcx, rcx
    jnz     .leb_late
    test    r11, r11
    jz      .leb_value
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    je      .leb_value
.leb_not:
    mov     eax, EXIT_NOT_SIMPLE
.leb_err:
    mov     rdx, rax
    jmp     .err_rdx
.leb_late:
    cmp     byte [rel known_active], 0
    jne     .leb_not                       ; (pass 2 has no value for it)
    mov     byte [rel known_guessed], 1
    xor     edx, edx
.leb_value:
    mov     rax, rdx
.leb_byte:
    mov     ecx, eax
    and     ecx, 0x7F
    test    r14, r14
    jnz     .leb_signed
    shr     rax, 7
    test    rax, rax
    jz      .leb_last
    jmp     .leb_more
.leb_signed:
    sar     rax, 7
    ; done when the rest is the sign of the 7 bits written
    test    rax, rax
    jnz     .leb_neg
    test    ecx, 0x40
    jz      .leb_last
    jmp     .leb_more
.leb_neg:
    cmp     rax, -1
    jne     .leb_more
    test    ecx, 0x40
    jnz     .leb_last
.leb_more:
    or      ecx, 0x80
    push    rax
    mov     esi, ecx
    call    .emit
    pop     rax
    jmp     .leb_byte
.leb_last:
    mov     esi, ecx
    call    .emit
    call    .comma
    jz      .leb_next
    jmp     .done_ok

.align:
    ; N[, FILL[, MAX]] (r14: 1 p2align, N the power of two)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    xor     ecx, ecx
    test    rax, rax
    jz      .align_at
    mov     rcx, [rax + SECTION_size]
.align_at:
    mov     [rel align_from], rcx          ; where it starts
    call    .const
    jnz     .err_rdx
    mov     r13, rdx
    test    r14, r14
    jz      .align_bytes
    cmp     r13, 31
    ja      .align_bad
    mov     ecx, r13d
    mov     r13d, 1
    shl     r13, cl
.align_bytes:
    test    r13, r13
    jz      .align_bad
    mov     rax, r13
    dec     rax
    test    rax, r13
    jnz     .align_bad                     ; (a power of two)
    mov     r15, -1                        ; no fill: GNU's NOPs in code, zeros in data
    xor     r14d, r14d                     ; MAX (0: none)
    call    .comma
    jnz     .align_go
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    je      .align_max                     ; ".p2align 4,,10": no fill written
    call    .const
    jnz     .err_rdx
    movzx   r15d, dl
.align_max:
    call    .comma
    jnz     .align_go
    call    .const                         ; the most to skip
    jnz     .err_rdx
    mov     r14, rdx
.align_go:
    ; more padding than MAX: none (GNU's). In code, once jumps are made
    ; short: MAX goes with the fill spec (its bits 10-15: MAX + 1), the
    ; padding worked out as the code moves (core/asmctx.s, jump.s rx_cap);
    ; elsewhere - or MAX past 62 - as the code stands when it is read
    test    r14, r14
    jz      .align_do
    cmp     r15, -1
    jne     .align_now
    cmp     r14, 62
    ja      .align_now
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .align_now
    test    word [rax + SECTION_flags], SHF_EXECINSTR
    jnz     .align_do
.align_now:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .align_do
    mov     rcx, [rax + SECTION_size]
    neg     rcx
    lea     rdx, [r13 - 1]
    and     rcx, rdx                       ; the padding
    cmp     rcx, r14
    ja      .align_frag
.align_do:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    cmp     r15, -1
    jne     .align_filled
    ; GNU's: its long NOPs in a section of code, zeros in others
    mov     rax, [rdi + ASMCTX_curr_sec]
    test    rax, rax
    jz      .align_auto
    test    word [rax + SECTION_flags], SHF_EXECINSTR
    jnz     .align_nops
    xor     r15d, r15d
.align_filled:
    mov     edx, r15d
    or      edx, 0x100
    call    asm_ctx_align_fill
    jmp     .align_listed
.align_auto:
    mov     edx, 0x90
    call    asm_ctx_align
    jmp     .align_listed
.align_nops:
    call    align_gas_spec
    test    r14, r14
    jz      .align_spec
    cmp     r14, 62
    ja      .align_spec
    lea     rcx, [r14 + 1]
    shl     ecx, 10
    or      rax, rcx                       ; MAX + 1 in bits 10-15
.align_spec:
    mov     rdx, rax
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    asm_ctx_align_spec
.align_listed:
    mov     edi, 2
    call    lst_mark
.align_frag:
    ; GNU as's frag ends where the padding starts (debug/line.s)
    mov     rsi, [rel align_from]
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .done_ok
    mov     rdx, [rax + SECTION_size]
    extern  line_frag
    call    line_frag
    jmp     .done_ok
.align_bad:
    mov     edx, EXIT_ALIGN_ERROR
    jmp     .done_rdx

.equ:
    ; NAME, EXPR (r14: 0 .equ, 1 .set, 2 .equiv)
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    call    parser_gas_name
    mov     r13, rsi
    call    .comma
    jnz     .bad
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .equ_new
    cmp     r14, 2
    je      .equ_twice                     ; .equiv: defined already
    cmp     r14, 1
    jne     .equ_new                       ; (.equ again: as "equ" does it)
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .equ_new
    ; .set again: its new value from here on
    mov     r15, rdx
    call    .const
    jnz     .err_rdx
    mov     [r15 + SYMBOL_value], rdx
    jmp     .done_ok
.equ_new:
    mov     rsi, r13
    call    parser_gas_equ
    test    rax, rax
    jnz     .err
    jmp     .done_ok
.equ_twice:
    mov     rdi, r13
    call    error_set_subject
    mov     edx, EXIT_DUP_SYMBOL
    jmp     .done_rdx

.type:
    ; NAME, @WORD / WORD / "WORD"
    call    .name
    jnz     .err_rdx
    mov     r13, rdx
    call    .comma
    jnz     .bad
    call    .type_token
    test    rax, rax
    jnz     .err
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    je      .type_look
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
.type_look:
    lea     rdi, [rel type_words]
    call    .word_value
    test    eax, eax
    jns     .type_known
    mov     rdi, rsi
    call    error_set_subject
    mov     edx, EXIT_SYM_TYPE
    jmp     .done_rdx
.type_known:
    mov     edi, PEND_TYPE
    mov     rsi, r13
    mov     edx, eax
    call    .pend_add
    jmp     .done_ok

.size:
    ; NAME, EXPR: worked out once jumps are made short (".-f" now would
    ; freeze the function's code; parser_size_late)
    call    .name
    jnz     .err_rdx
    mov     r13, rdx
    call    .comma
    jnz     .bad
    mov     rsi, r13
    extern  parser_size_late
    call    parser_size_late
    mov     rdx, rax
    jmp     .done_rdx

.vis:
    ; NAME[, NAME ...] (r14: the visibility)
.vis_next:
    call    .name
    jnz     .err_rdx
    mov     edi, PEND_VIS
    mov     rsi, rdx
    mov     edx, r14d
    call    .pend_add
    call    .comma
    jz      .vis_next
    jmp     .done_ok

.comm:
    ; NAME, SIZE[, ALIGN]: "common NAME SIZE:ALIGN"
    call    .name
    jnz     .err_rdx
    mov     r13, rdx
    call    .comma
    jnz     .bad
    call    .const
    jnz     .err_rdx
    mov     r14, rdx
    xor     r15d, r15d
    call    .comma
    jnz     .comm_define
    call    .const
    jnz     .err_rdx
    mov     r15, rdx
.comm_define:
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    mov     edx, EXIT_BIN_COMMON
    je      .done_rdx
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jz      .comm_found
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, SYMBOL_SIZE / 8
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     [rsp + SYMBOL_name], r13
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    test    rax, rax
    jnz     .err
    jmp     .comm_fill
.comm_found:
    ; ".local x" before it: x is SIZE bytes of .bss, local - GCC's static
    ; data that is all zeros ("static jmp_buf jb"), as GNU as has it; a
    ; common symbol would be merged with another file's x
    cmp     word [rdx + SYMBOL_section], 0
    jne     .comm_fill
    cmp     byte [rdx + SYMBOL_vis], VIS_LOCAL
    jne     .comm_fill
    cmp     byte [rdx + SYMBOL_kind], SYM_EXTERN
    je      .comm_fill
    cmp     byte [rdx + SYMBOL_kind], SYM_COMMON
    je      .comm_fill
    test    r15, r15
    jnz     .lcomm_go
    mov     r15d, 1
    jmp     .lcomm_go
.comm_fill:
    mov     byte [rdx + SYMBOL_kind], SYM_COMMON
    mov     byte [rdx + SYMBOL_vis], VIS_GLOBAL
    mov     byte [rdx + SYMBOL_etype], ETYPE_OBJECT
    mov     word [rdx + SYMBOL_section], SHN_COMMON
    mov     [rdx + SYMBOL_value], r15
    mov     [rdx + SYMBOL_size], r14
    jmp     .done_ok

.lcomm:
    ; NAME, SIZE[, ALIGN]: SIZE bytes of .bss, NAME a local label there;
    ; the section stays the one it was
    call    .name
    jnz     .err_rdx
    mov     r13, rdx
    call    .comma
    jnz     .bad
    call    .const
    jnz     .err_rdx
    mov     r14, rdx
    mov     r15d, 1
    call    .comma
    jnz     .lcomm_go
    call    .const
    jnz     .err_rdx
    mov     r15, rdx
.lcomm_go:
    mov     rax, [rbx + PREP_ctx]
    push    qword [rax + ASMCTX_curr_sec]
    push    qword [rel sec_previous]
    ; "section .bss", made as that directive makes it
    lea     rdi, [rel s_bss]
    call    .push_name
    mov     byte [rel gas_sec_set], 0
    mov     rdi, rbx
    call    parser_handle_section_directive
    test    rax, rax
    jnz     .lcomm_back
    cmp     r15, 1
    jbe     .lcomm_label
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r15
    xor     edx, edx
    call    asm_ctx_align
.lcomm_label:
    mov     rsi, r13
    call    parser_define_label
    test    rax, rax
    jnz     .lcomm_back
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    add     [rax + SECTION_size], r14
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .lcomm_typed
    mov     byte [rdx + SYMBOL_etype], ETYPE_OBJECT
    mov     [rdx + SYMBOL_size], r14
.lcomm_typed:
    xor     eax, eax
.lcomm_back:
    pop     qword [rel sec_previous]
    pop     rcx
    mov     rdx, [rbx + PREP_ctx]
    mov     [rdx + ASMCTX_curr_sec], rcx
    mov     rdx, rax
    jmp     .done_rdx

.org:
    ; N[, FILL]: padding up to offset N of the section (never back)
    call    .const
    jnz     .err_rdx
    mov     r13, rdx
    xor     r14d, r14d
    call    .comma
    jnz     .org_go
    call    .const
    jnz     .err_rdx
    mov     r14, rdx
.org_go:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .bad
    mov     rsi, r13
    sub     rsi, [rax + SECTION_size]
    js      .org_back
    mov     rdi, [rbx + PREP_ctx]
    movzx   edx, r14b
    call    asm_ctx_padto
    mov     rdx, rax
    jmp     .done_rdx
.org_back:
    mov     edx, EXIT_ORG_BACKWARDS
    jmp     .done_rdx

.bits:
    mov     [rel asm_bits], r14b
    jmp     .done_ok

.intel:
    ; GNU's Intel syntax: "DWORD PTR x[rip]", "OFFSET FLAT:x" - ptr, flat
    ; and offset as %use masm reads them (once; "noprefix" or not)
    extern  att_on, gas_names
    mov     byte [rel att_on], 0
    mov     byte [rel gas_names], 1
    call    .skip_line
    cmp     byte [rel masm_enabled], 0
    jne     .done_ok
    mov     byte [rel masm_enabled], 1
    mov     rdi, rbx
    lea     rsi, [rel intel_text]
    mov     edx, intel_text_len
    lea     rcx, [rel s_intel]
    call    prep_push_buffer
    mov     rdx, rax
    jmp     .done_rdx

.octa:
    ; numbers, 16 bytes each (the value's sign above its 64 bits)
.octa_next:
    call    .const
    jnz     .err_rdx
    mov     r13, rdx
    mov     r14, rdx
    sar     r14, 63
    mov     ecx, 16
.octa_byte:
    push    rcx
    mov     esi, r13d
    call    .emit
    shrd    r13, r14, 8
    sar     r14, 8
    pop     rcx
    dec     ecx
    jnz     .octa_byte
    call    .comma
    jz      .octa_next
    jmp     .done_ok

.ident:
    ; "TEXT": into .comment (strings, entry size 1), after a NUL as GNU's;
    ; the section stays the one it was
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .err
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .bad
    mov     r15, [rdx + TOKEN_value]
    movzx   r14d, word [rdx + TOKEN_len]
    test    byte [rdx + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .ident_len
    mov     r14, -1
.ident_len:
    movzx   eax, byte [rdx + TOKEN_quote]
    push    rax
    mov     rax, [rbx + PREP_ctx]
    push    qword [rax + ASMCTX_curr_sec]
    push    qword [rel sec_previous]
    lea     rdi, [rel s_comment]
    call    .push_name
    mov     byte [rel gas_sec_set], 1
    mov     word [rel gas_sec_flags], 0x30          ; SHF_MERGE | SHF_STRINGS
    mov     dword [rel gas_sec_type], SHT_PROGBITS
    mov     byte [rel gas_sec_entsize], 1
    mov     rdi, rbx
    call    parser_handle_section_directive
    test    rax, rax
    jnz     .ident_back
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    cmp     qword [rax + SECTION_size], 0
    jne     .ident_text
    xor     esi, esi
    call    .emit
.ident_text:
    mov     rsi, r15
    mov     r13, r14
    cmp     byte [rsp + 16], '"'
    jne     .ident_raw
    call    .emit_escaped
    jmp     .ident_nul
.ident_raw:
    ; a `...` or '...' string: as it is
    test    r13, r13
    jz      .ident_nul
    movzx   eax, byte [rsi]
    cmp     r13, -1
    jne     .ident_byte
    test    eax, eax
    jz      .ident_nul
.ident_byte:
    push    rsi
    mov     esi, eax
    call    .emit
    pop     rsi
    inc     rsi
    cmp     r13, -1
    je      .ident_raw
    dec     r13
    jmp     .ident_raw
.ident_nul:
    xor     esi, esi
    call    .emit
    xor     eax, eax
.ident_back:
    pop     qword [rel sec_previous]
    pop     rcx
    mov     rdx, [rbx + PREP_ctx]
    mov     [rdx + ASMCTX_curr_sec], rcx
    add     rsp, 8                                  ; (the quote)
    mov     rdx, rax
    jmp     .done_rdx

.att:
    ; AT&T syntax from here (frontend/parser/att.s); "noprefix": registers
    ; without their %
    extern  att_on, att_noprefix, gas_names
    mov     byte [rel att_on], 1
    mov     byte [rel gas_names], 1
    mov     byte [rel att_noprefix], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .att_rest
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .att_rest
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_noprefix]
    call    str_cmp_kw
    test    rax, rax
    jnz     .att_rest
    mov     byte [rel att_noprefix], 1
.att_rest:
    call    .skip_line
    jmp     .done_ok

.none:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     edx, EXIT_UNEXPECTED_TOKEN
    jmp     .done_rdx
.err:
    mov     rdx, rax
    jmp     .done_rdx
.err_rdx:
    ; (.const and .name leave the error in rdx)
.done_rdx:
    mov     eax, 1
    jmp     .ret
.done_ok:
    xor     edx, edx
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .emit: the byte sil into the section.Preserves rsi (and the callee-saved).
.emit:
    push    rsi
    push    rcx
    push    rax
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, sil
    call    asm_ctx_emit_byte
    pop     rax
    pop     rcx
    pop     rsi
    ret

; .emit_escaped: the "..." text rsi (r13 bytes, or to its NUL if -1),
; C's escapes worked out
.emit_escaped:
.esc_next:
    test    r13, r13
    jz      .esc_done
    movzx   eax, byte [rsi]
    cmp     r13, -1
    jne     .esc_have
    test    eax, eax
    jz      .esc_done
.esc_have:
    inc     rsi
    call    .esc_count
    cmp     eax, '\'
    jne     .esc_plain
    test    r13, r13
    jz      .esc_plain
    movzx   eax, byte [rsi]
    cmp     r13, -1
    jne     .esc_c
    test    eax, eax
    jz      .esc_backslash
.esc_c:
    inc     rsi
    call    .esc_count
    mov     ecx, 10
    cmp     eax, 'n'
    je      .esc_put
    mov     ecx, 9
    cmp     eax, 't'
    je      .esc_put
    mov     ecx, 13
    cmp     eax, 'r'
    je      .esc_put
    mov     ecx, 8
    cmp     eax, 'b'
    je      .esc_put
    mov     ecx, 12
    cmp     eax, 'f'
    je      .esc_put
    mov     ecx, 11
    cmp     eax, 'v'
    je      .esc_put
    cmp     eax, 'x'
    je      .esc_hex
    cmp     eax, '0'
    jb      .esc_self
    cmp     eax, '7'
    jbe     .esc_octal
.esc_self:
    mov     ecx, eax                       ; \\ \" \' and any other (\a, \e too, GNU's): itself
.esc_put:
    push    rsi
    mov     esi, ecx
    call    .emit
    pop     rsi
    jmp     .esc_next
.esc_backslash:
    mov     eax, '\'
.esc_plain:
    push    rsi
    mov     esi, eax
    call    .emit
    pop     rsi
    jmp     .esc_next
.esc_octal:
    ; up to three octal digits
    lea     ecx, [eax - '0']
    mov     edx, 2
.esc_oct_more:
    test    edx, edx
    jz      .esc_put
    test    r13, r13
    jz      .esc_put
    movzx   eax, byte [rsi]
    cmp     eax, '0'
    jb      .esc_put
    cmp     eax, '7'
    ja      .esc_put
    shl     ecx, 3
    lea     ecx, [ecx + eax - '0']
    inc     rsi
    call    .esc_count
    dec     edx
    jmp     .esc_oct_more
.esc_hex:
    ; hex digits, as many as there are (GNU's), the low byte kept
    xor     ecx, ecx
.esc_hex_more:
    test    r13, r13
    jz      .esc_put
    movzx   eax, byte [rsi]
    lea     edx, [eax - '0']
    cmp     edx, 9
    jbe     .esc_hex_digit
    or      eax, 0x20
    lea     edx, [eax - 'a' + 10]
    cmp     eax, 'a'
    jb      .esc_put
    cmp     eax, 'f'
    ja      .esc_put
.esc_hex_digit:
    shl     ecx, 4
    add     ecx, edx
    inc     rsi
    call    .esc_count
    jmp     .esc_hex_more
.esc_done:
    ret
; .esc_count: one byte of a counted text read (r13 down unless -1)
.esc_count:
    cmp     r13, -1
    je      .esc_count_ret
    dec     r13
.esc_count_ret:
    ret

; .comma: ZF set when the next token is a comma (taken)
.comma:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .comma_no
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .comma_no
    mov     rdi, rbx
    call    preprocessor_next_token
    xor     eax, eax                       ; ZF set
    ret
.comma_no:
    or      eax, 1                         ; ZF clear
    ret

; .const: an expression that is a number: ZF set and rdx = it, else ZF
; clear and rdx = the error
.const:
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .const_err
    test    rcx, rcx
    jnz     .const_not
    test    r11, r11
    jz      .const_ok
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    jne     .const_not
.const_ok:
    xor     eax, eax
    ret
.const_not:
    mov     eax, EXIT_NOT_SIMPLE
.const_err:
    mov     rdx, rax
    or      eax, 1                         ; ZF clear
    ret

; .name: an identifier: ZF set and rdx = its text
.name:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .const_err
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    je      .name_ok
    ; "name" quoted, as GCC 16 writes every one under -masm=intel
    cmp     byte [rdx + TOKEN_kind], TOK_STRING
    jne     .name_bad
    cmp     byte [rdx + TOKEN_quote], '"'
    jne     .name_bad
.name_ok:
    mov     rsi, [rdx + TOKEN_value]
    call    parser_gas_name
    mov     rdx, rsi
    xor     eax, eax
    ret
.name_bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    jmp     .const_err

; .type_token: the next token, past an "@" (@function, @nobits)
.type_token:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .tt_ret
    cmp     byte [rdx + TOKEN_kind], TOK_AT
    jne     .tt_ret
    mov     rdi, rbx
    call    preprocessor_next_token
.tt_ret:
    ret

; .skip_line: the tokens up to the end of the line
.skip_line:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .skip_done
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .skip_done
    cmp     eax, TOK_EOF
    je      .skip_done
    cmp     eax, TOK_COMMENT
    je      .skip_done
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .skip_line
.skip_done:
    ret

; .push_name: an identifier token rdi handed back as the next one
.push_name:
    push    rdi
    lea     rdi, [rel gas_tok]
    xor     eax, eax
    mov     ecx, TOKEN_SIZE
    rep stosb
    pop     rdi
    mov     byte [rel gas_tok + TOKEN_tag], TAG_TOKEN
    mov     byte [rel gas_tok + TOKEN_kind], TOK_IDENT
    mov     [rel gas_tok + TOKEN_value], rdi
    mov     eax, [rbx + PREP_line]
    mov     [rel gas_tok + TOKEN_line], eax
    mov     rdi, rbx
    lea     rsi, [rel gas_tok]
    jmp     preprocessor_unread_token

; .word_value: the word rsi in the table rdi (word, NUL, value byte):
; eax = its value, or -1
.word_value:
    push    rsi
.wv_entry:
    cmp     byte [rdi], 0
    je      .wv_none
    push    rdi
    mov     rsi, [rsp + 8]
    call    str_cmp
    pop     rdi
    test    rax, rax
    jz      .wv_found
.wv_skip:
    inc     rdi
    cmp     byte [rdi - 1], 0
    jne     .wv_skip
    inc     rdi                            ; (its value)
    jmp     .wv_entry
.wv_found:
    inc     rdi
    cmp     byte [rdi - 1], 0
    jne     .wv_found
    movzx   eax, byte [rdi]
    pop     rsi
    ret
.wv_none:
    mov     eax, -1
    pop     rsi
    ret

; .pend_add: a pending .type / .size / visibility: edi = its kind, rsi =
; the name, rdx = the value
.pend_add:
    push    rdi
    push    rsi
    push    rdx
    mov     rax, [rel pend]
    test    rax, rax
    jnz     .pend_have
    mov     rsi, PEND_CAP * 24
    call    mem_reserve
    test    rax, rax
    jnz     .pend_out
    mov     [rel pend], rdx
.pend_have:
    mov     rcx, [rel pend_n]
    cmp     rcx, PEND_CAP
    jae     .pend_out
    imul    rcx, rcx, 24
    add     rcx, [rel pend]
    mov     rax, [rsp + 16]
    mov     [rcx], rax                     ; kind
    mov     rax, [rsp + 8]
    mov     [rcx + 8], rax                 ; name
    mov     rax, [rsp]
    mov     [rcx + 16], rax                ; value
    inc     qword [rel pend_n]
.pend_out:
    pop     rdx
    pop     rsi
    pop     rdi
    ret

; gas_stray: ".endm" / ".endr" with nothing open (r12 = the word)
gas_stray:
    mov     rdi, r12
    call    error_set_subject
    mov     eax, EXIT_GAS_STRAY
    ret

; gas_nasm_word: rdi a word NASM puts after a label(equ, times, resb ...
; resz, db ... dz), in any case: eax = 1. Preserves all but rax, rcx.
global gas_nasm_word
gas_nasm_word:
    movzx   eax, byte [rdi]
    or      eax, 0x20
    cmp     eax, 'd'
    je      .nw_d
    cmp     eax, 'r'
    je      .nw_res
    mov     eax, [rdi]
    or      eax, 0x00202020
    cmp     eax, 'equ'                     ; (its NUL the fourth byte)
    je      .nw_yes
    mov     eax, [rdi]
    or      eax, 0x20202020
    cmp     eax, 'time'
    jne     .nw_no
    movzx   eax, byte [rdi + 4]
    or      eax, 0x20
    cmp     eax, 's'
    jne     .nw_no
    cmp     byte [rdi + 5], 0
    je      .nw_yes
    jmp     .nw_no
.nw_d:
    cmp     byte [rdi + 2], 0
    jne     .nw_no
    movzx   eax, byte [rdi + 1]
    jmp     .nw_size
.nw_res:
    cmp     byte [rdi + 4], 0
    jne     .nw_no
    movzx   eax, word [rdi + 1]
    or      eax, 0x2020
    cmp     eax, 'es'
    jne     .nw_no
    movzx   eax, byte [rdi + 3]
.nw_size:
    or      eax, 0x20
    lea     rcx, [rel nw_sizes]
.nw_scan:
    cmp     byte [rcx], 0
    je      .nw_no
    cmp     al, [rcx]
    je      .nw_yes
    inc     rcx
    jmp     .nw_scan
.nw_yes:
    mov     eax, 1
    ret
.nw_no:
    xor     eax, eax
    ret

; ---- gas_assign ---------------------------
;
; gas_assign
; "NAME = EXPR" (GNU's .set, FASM's and MASM's =): NAME the value; set
; again when it is a constant already ("x = x + 1").
; Input    : rdi = PrepState (the expression next), rsi = NAME
; Output   : rax = OK or an error
;
global gas_assign
gas_assign:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    call    parser_gas_name
    mov     r12, rsi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .new
    cmp     word [rdx + SYMBOL_section], SHN_ABS
    jne     .new                           ; (a label: "inconsistently redefined")
    mov     r13, rdx
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    test    rcx, rcx
    jnz     .not_number
    test    r11, r11
    jz      .number
    cmp     word [r11 + SYMBOL_section], SHN_ABS
    jne     .not_number
.number:
    mov     [r13 + SYMBOL_value], rdx
    xor     eax, eax
    jmp     .ret
.not_number:
    mov     eax, EXIT_NOT_SIMPLE
    jmp     .ret
.new:
    mov     rsi, r12
    call    parser_gas_equ
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- gas_finish ---------------------------
;
; gas_finish
; The source read: .type / .size / .hidden ... on the symbols they name
; (a name not defined: nothing, as GNU as leaves an undefined .type).
; Preserves rbx, r12-r15.
;
global gas_finish
gas_finish:
    push    rbx
    push    r12
    xor     r12d, r12d
.next:
    cmp     r12, [rel pend_n]
    jae     .done
    imul    rbx, r12, 24
    add     rbx, [rel pend]
    inc     r12
    lea     rdi, [rel global_ctx]
    mov     rsi, [rbx + 8]
    call    symbol_find
    test    rax, rax
    jnz     .next
    mov     rax, [rbx + 16]
    cmp     qword [rbx], PEND_TYPE
    jne     .not_type
    mov     [rdx + SYMBOL_etype], al
    jmp     .next
.not_type:
    cmp     qword [rbx], PEND_SIZE
    jne     .not_size
    mov     [rdx + SYMBOL_size], rax
    jmp     .next
.not_size:
    mov     [rdx + SYMBOL_eother], al
    jmp     .next
.done:
    pop     r12
    pop     rbx
    ret
