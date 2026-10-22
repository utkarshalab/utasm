; ============================================================================
; File        : src/frontend/syntax/nasm/parser/pseudo.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : the pseudo-instruction dispatch; string, UTF-16 / 32, float and BCD data; the float and ilog2 functions; incbin
; ============================================================================



;*
; * [parser_handle_pseudo_op]
; * Input: RSI = mnemonic string
; * Output: RAX = 1 if handled, 0 if unknown
; ;
parser_handle_pseudo_op:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = mnemonic string
    ; directives are compared in lower case: NASM takes BITS, Org, SECTION
    lea     rdi, [rel pseudo_lc]
    xor     ecx, ecx
.lc:
    movzx   eax, byte [rsi + rcx]
    cmp     al, 'A'
    jb      .lc_put
    cmp     al, 'Z'
    ja      .lc_put
    or      al, 0x20
.lc_put:
    mov     [rdi + rcx], al
    test    al, al
    jz      .lc_done
    inc     ecx
    cmp     ecx, 63
    jb      .lc
    jmp     .lc_keep               ; longer than any directive
.lc_done:
    mov     r12, rdi
.lc_keep:

    ; GAS's call frame directives: .cfi_startproc ... (src/debug/cfi.s)
    cmp     dword [r12], '.cfi'
    jne     .not_cfi
    cmp     byte [r12 + 4], '_'
    jne     .not_cfi
    call    parser_cfi
    jmp     .check_handler_result
.not_cfi:

    ; the directives NASM makes standard macros (section, global, align
    ; ...) move its %% counter as a macro call does - so many numbers each
    ; (std_macro_words) - which ..@N names show; not in [ ] (the primitive),
    ; nor after times ("times 2 incbin f": no macro there, the line's first
    ; word is times)
    cmp     byte [rel stmt_bracketed], 0
    jne     .counted
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .count_word
    mov     rax, [rax + MACROEXP_macro]
    test    byte [rax + MACRO_flags], MACRO_FLAG_TIMES
    jnz     .counted
.count_word:
    mov     rdi, r12
    lea     rsi, [rel std_macro_words]
    call    parser_word_index
    test    eax, eax
    jz      .counted
    imul    eax, eax, 12
    lea     rcx, [rel std_macro_words]
    movzx   ecx, byte [rcx + rax - 1]
    mov     rax, [rbx + PREP_ctx]
    add     [rax + ASMCTX_mac_exp_id], ecx
.counted:

    ; %use masm's LOCAL, INVOKE, .IF & co, .CODE (src/frontend/syntax/masm/masm.s)
    extern  masm_word
    mov     rdi, rbx
    mov     rsi, r12
    call    masm_word
    test    eax, eax
    jz      .not_masm_word
    mov     rax, rdx
    jmp     .check_handler_result
.not_masm_word:

    ; GNU as's directives (.globl, .section, .ascii, .p2align ...: gas.s),
    ; worked there or handed on under NASM's name
    cmp     byte [r12], '.'
    jne     .not_gas
    extern  gas_directive
    mov     rdi, rbx
    mov     rsi, r12
    call    gas_directive
    test    eax, eax
    jz      .not_gas
    cmp     eax, 2
    je      .gas_renamed
    mov     rax, rdx
    jmp     .check_handler_result
.gas_renamed:
    mov     r12, rdx
.not_gas:

    ; FASM's virtual / end virtual / load / store (src/frontend/syntax/fasm/fasm.s)
    call    parser_fasm_word
    test    eax, eax
    jz      .not_fasm
    mov     rax, rdx
    jmp     .check_handler_result
.not_fasm:

    ; 1. Data Directives (db, dw, dd, dq) - the whole word, not a prefix
    ;    ("dbg" or "dword_table" as a statement word is not db / dw)
    cmp     byte [r12 + 2], 0
    jne     .not_data
    mov     byte [rel zero_warned], 0      ; one warning a line (db ?, ?)
    mov     byte [rel expr_in_data], 1     ; (kept expressions: no pass 2)
    ; "dw $, $": $ is where the line starts, for each item (NASM)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     [rel pos_line_sec], rax
    test    rax, rax
    jz      .data_pos
    mov     rax, [rax + SECTION_size]
    mov     [rel pos_line], rax
.data_pos:
    ; "db" alone: NASM's warning, nothing written
    cmp     byte [r12], 'd'
    jne     .data_word
    lea     rcx, [rel data_letters]
    mov     al, [r12 + 1]
.data_letter:
    cmp     byte [rcx], 0
    je      .data_word
    cmp     [rcx], al
    je      .data_operands
    inc     rcx
    jmp     .data_letter
.data_operands:
    mov     rdi, rbx
    call    preprocessor_peek_token
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .data_empty
    cmp     eax, TOK_EOF
    jne     .data_word
.data_empty:
    mov     edi, WC_DB_EMPTY
    call    warn_begin
    lea     rsi, [rel s_db_empty]
    call    warn_text
    call    warn_end
    xor     eax, eax
    jmp     .check_handler_result
.data_word:
    mov     ax, [r12]
    IF ax, e, 'db'
        mov     rdi, rbx
        call    parser_emit_data_8
        jmp     .check_handler_result
    ELSEIF ax, e, 'dw'
        mov     rdi, rbx
        call    parser_emit_data_16
        jmp     .check_handler_result
    ELSEIF ax, e, 'dd'
        mov     rdi, rbx
        call    parser_emit_data_32
        jmp     .check_handler_result
    ELSEIF ax, e, 'dq'
        mov     rdi, rbx
        call    parser_emit_data_64
        jmp     .check_handler_result
    ELSEIF ax, e, 'dt'
        mov     esi, 10
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'do'
        mov     esi, 16
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'dy'
        mov     esi, 32
        call    parser_emit_data_wide
        jmp     .check_handler_result
    ELSEIF ax, e, 'dz'
        mov     esi, 64
        call    parser_emit_data_wide
        jmp     .check_handler_result
        ENDIF

.not_data:
    ; 1.4 "times N <directive>" repeats the rest of the line N times
    mov     rdi, r12
    lea     rsi, [rel str_times]
    call    str_cmp_kw
    IF rax, e, OK
        mov     rdi, rbx
        call    parser_handle_times
        jmp     .check_handler_result
        ENDIF

    ; 1.5 Reservation Directives (resb, resw, resd, resq)
    cmp     byte [r12 + 4], 0
    jne     .not_res
    mov     eax, [r12]
    IF eax, e, 'resb'
        mov     rdi, rbx
        mov     rsi, 1
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resw'
        mov     rdi, rbx
        mov     rsi, 2
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resd'
        mov     rdi, rbx
        mov     rsi, 4
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resq'
        mov     rdi, rbx
        mov     rsi, 8
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'rest'
        mov     rdi, rbx
        mov     rsi, 10
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'reso'
        mov     rdi, rbx
        mov     rsi, 16
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resy'
        mov     rdi, rbx
        mov     rsi, 32
        call    parser_handle_res
        jmp     .check_handler_result
    ELSEIF eax, e, 'resz'
        mov     rdi, rbx
        mov     rsi, 64
        call    parser_handle_res
        jmp     .check_handler_result
        ENDIF

.not_res:
    ; endstruc after a section line ended a struc's layout
    cmp     qword [rel struc_open], 0
    je      .not_late_endstruc
    mov     rdi, r12
    lea     rsi, [rel str_endstruc]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_late_endstruc
    call    parser_endstruc_late
    jmp     .check_handler_result
.not_late_endstruc:
    ; NASM's structure instances: istruc NAME / at FIELD, data / iend
    mov     rdi, r12
    lea     rsi, [rel str_istruc]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_istruc
    call    parser_istruc
    jmp     .check_handler_result
.not_istruc:
    mov     rdi, r12
    lea     rsi, [rel str_at]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_at
    call    parser_at
    jmp     .check_handler_result
.not_at:
    mov     rdi, r12
    lea     rsi, [rel str_iend]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_iend
    call    parser_iend
    jmp     .check_handler_result
.not_iend:
    ; utasm's procedures: proc NAME [uses REG, ...] / endproc
    ; (src/semantic/proc.s)
    extern  proc_word
    mov     rdi, r12
    call    proc_word
    test    eax, eax
    jz      .not_proc
    mov     rax, rdx
    jmp     .check_handler_result
.not_proc:
    ; namespace / endnamespace / module / export / private
    ; (src/semantic/namespace.s)
    extern  ns_word
    mov     rdi, r12
    call    ns_word
    test    eax, eax
    jz      .not_ns
    mov     rax, rdx
    jmp     .check_handler_result
.not_ns:
    mov     rdi, r12
    lea     rsi, [rel str_absolute]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_absolute
    call    parser_absolute
    jmp     .check_handler_result
.not_absolute:
    mov     rdi, r12
    lea     rsi, [rel str_alignb_d]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_alignb
    call    parser_alignb
    jmp     .check_handler_result
.not_alignb:
    mov     rdi, r12
    lea     rsi, [rel str_incbin]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_incbin
    call    parser_incbin
    jmp     .check_handler_result
.not_incbin:
    ; 2. Section Directive ("segment" is NASM's other name for it)
    mov     rdi, r12
    lea     rsi, [rel str_segment]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_segment
    mov     rdi, rbx
    call    parser_handle_section_directive
    jmp     .check_handler_result
.not_segment:
    ; "cpu <level>": utasm encodes whatever it is given - but NASM's
    ; encoding choices are kept: "cpu latevex" lets the VEX forms of
    ; AVX-IFMA / AVX-VNNI ... be chosen over their EVEX ones, "novex" /
    ; "noevex" leave those out, "default" undoes them (dispatch.s, CPUF_*)
    mov     rdi, r12
    lea     rsi, [rel str_cpu]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_cpu
    extern  cpu_latevex
.cpu_word:
    mov     rdi, rbx
    call    preprocessor_peek_token
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .cpu_rest
    cmp     eax, TOK_EOF
    je      .cpu_rest
    cmp     eax, TOK_RBRACKET
    je      .cpu_rest                      ; "[cpu 386]" (a "386]" was a level)
    cmp     eax, TOK_NUMBER
    je      .cpu_level
    cmp     eax, TOK_IDENT
    jne     .cpu_skip
    mov     r13, [rdx + TOKEN_value]
    ; "x86-64", "ia-64": three tokens
    lea     rsi, [rel str_cpu_x86]
    mov     r14d, 11
    mov     rdi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .cpu_dash
    lea     rsi, [rel str_cpu_ia]
    mov     r14d, 10
    mov     rdi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .cpu_dash
    mov     rdi, r13
    call    parser_cpu_num
    push    rax                            ; (1: a level - "default" an
    lea     r14, [rel cpu_words]           ; option too)
.cpu_find:
    cmp     byte [r14], 0
    je      .cpu_find_end
    mov     rdi, r13
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .cpu_found
    add     r14, 12
    jmp     .cpu_find
.cpu_find_end:
    pop     rax
    test    eax, eax
    jnz     .cpu_other                     ; a level
    jmp     .cpu_unknown
.cpu_found:
    add     rsp, 8
    mov     al, [rel cpu_latevex]
    and     al, [r14 + 10]                 ; the bits it clears
    or      al, [r14 + 11]                 ; ... and sets
    mov     [rel cpu_latevex], al
    jmp     .cpu_skip
.cpu_dash:
    mov     rdi, rbx
    call    preprocessor_next_token        ; the word
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_MINUS
    jne     .cpu_unknown_now
    mov     rdi, rbx
    call    preprocessor_next_token        ; "-"
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .cpu_unknown_now
    mov     rax, [rdx + TOKEN_value]
    cmp     dword [rax], '64'
    jne     .cpu_unknown_now
    extern  cpu_num
    mov     [rel cpu_num], r14b
    and     byte [rel cpu_latevex], ~CPUF_8086 & 0xFF
    jmp     .cpu_skip
.cpu_unknown:
    mov     rdi, rbx
    call    preprocessor_next_token
.cpu_unknown_now:
    ; NASM's "unknown CPU type or flag"
    mov     rdi, r13
    extern  error_set_subject
    call    error_set_subject
    call    parser_skip_to_eol
    mov     rax, EXIT_CPU_UNKNOWN
    jmp     .check_handler_result
.cpu_level:
    ; "cpu 8086": pop cs is an instruction there; any other level not
    mov     rdi, [rdx + TOKEN_value]
    mov     r13, rdi
    push    rdi
    call    parser_cpu_num
    pop     rdi
    test    eax, eax
    jz      .cpu_unknown
    lea     rsi, [rel str_8086]
    call    str_cmp
    test    rax, rax
    jnz     .cpu_other
    or      byte [rel cpu_latevex], CPUF_8086
    jmp     .cpu_skip
.cpu_other:
    and     byte [rel cpu_latevex], ~CPUF_8086 & 0xFF
.cpu_skip:
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .cpu_word
.cpu_rest:
    call    parser_skip_to_eol
    mov     rax, 1
    jmp     .check_handler_result
.not_cpu:
    ; use16 / use32 / use64: bits 16 / 32 / 64
    lea     r13, [rel use_words]
.use_word:
    cmp     byte [r13], 0
    je      .not_use
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .use_hit
    add     r13, 8
    jmp     .use_word
.use_hit:
    movzx   edx, byte [r13 + 7]
    call    parser_bits_cpu
    test    eax, eax
    jnz     .check_handler_result
    mov     al, [r13 + 7]
    mov     [rel asm_bits], al
    xor     eax, eax
    jmp     .check_handler_result
.not_use:
    ; sectalign N / on / off
    mov     rdi, r12
    lea     rsi, [rel str_sectalign]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_sectalign
    call    parser_sectalign
    test    rax, rax
    jnz     .check_handler_result
    call    parser_skip_to_eol
    mov     rax, 1
    jmp     .check_handler_result
.not_sectalign:
    ; warning, map, list, float, debug, required: accepted, nothing for
    ; utasm to do
    lea     r13, [rel ignored_words]
.ignored_word:
    cmp     byte [r13], 0
    je      .not_ignored
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .ignored_hit
    add     r13, 10
    jmp     .ignored_word
.ignored_hit:
    ; "required x": an extern written to the object even when nothing
    ; refers to it (NASM's)
    mov     rdi, r12
    lea     rsi, [rel str_required]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_required
    mov     byte [rel extern_required], 1
    mov     rdi, rbx
    call    parser_handle_extern
    mov     byte [rel extern_required], 0
    jmp     .check_handler_result
.not_required:
    ; [map OPTIONS FILE] in a flat binary: its map file (src/object/
    ; map.s); in an object file not a directive (see org)
    mov     rdi, r12
    lea     rsi, [rel str_map]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ignored_list
    call    parser_object_out
    test    eax, eax
    jnz     .not_ignored
    call    parser_map_words
    jmp     .check_handler_result
.ignored_list:
    ; [list -] / [list +]: the listing stops and goes on
    mov     rdi, r12
    lea     rsi, [rel str_list]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ignored_rest
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ignored_rest
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     edi, 1
    cmp     eax, TOK_PLUS
    je      .list_switch
    xor     edi, edi
    cmp     eax, TOK_MINUS
    jne     .ignored_rest
.list_switch:
    extern  lst_listing
    call    lst_listing
.ignored_rest:
    call    parser_skip_to_eol
    mov     rax, 1
    jmp     .check_handler_result
.not_ignored:
    mov     rdi, r12
    lea     rsi, [rel str_section]
    extern  str_cmp
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_section_directive
        jmp     .check_handler_result
    ELSE
        mov     rdi, r12
        lea     rsi, [rel str_section_upper]
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    parser_handle_section_directive
            jmp     .check_handler_result
            ENDIF
        ENDIF

    ; alignmode MODE [, threshold | nojmp]: once %use smartalign defined it
    extern  smartalign_mode
    cmp     byte [rel smartalign_mode], 0
    je      .not_alignmode
    mov     rdi, r12
    lea     rsi, [rel str_alignmode]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_alignmode
    call    parser_alignmode
    jmp     .check_handler_result
.not_alignmode:

    ; 3. Align Directives
    mov     rdi, r12
    lea     rsi, [rel str_align]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        xor     rsi, rsi           ; type = 0 (byte)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_p2align]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, 1             ; type = 1 (p2)
        call    parser_handle_align
        jmp     .check_handler_result
        ENDIF

    ; 4. Visibility Directives (global, weak, local)
    mov     rdi, r12
    lea     rsi, [rel str_global]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_GLOBAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_weak]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_WEAK
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_local]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_LOCAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    ; static NAME: a local symbol, kept in the object by name
    mov     rdi, r12
    lea     rsi, [rel str_static_d]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        mov     rsi, VIS_LOCAL
        call    parser_handle_visibility
        jmp     .check_handler_result
        ENDIF

    ; common NAME SIZE[:ALIGN]
    mov     rdi, r12
    lea     rsi, [rel str_common_d]
    call    str_cmp_kw
    IF rax, e, 0
        call    parser_handle_common
        jmp     .check_handler_result
        ENDIF

    ; org and [map] are the flat formats' (NASM's bin macros): in an
    ; object file a word like any other
    call    parser_object_out
    test    eax, eax
    jnz     .not_org
    mov     rdi, r12
    lea     rsi, [rel str_org]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_org
        jmp     .check_handler_result
        ENDIF
.not_org:
    
    mov     rdi, r12
    lea     rsi, [rel str_extern]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_extern
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_default]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_default
        jmp     .check_handler_result
    ELSE
        mov     rdi, r12
        lea     rsi, [rel str_default_upper]
        call    str_cmp_kw
        IF rax, e, 0
            mov     rdi, rbx
            call    parser_handle_default
            jmp     .check_handler_result
            ENDIF
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_equ]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    parser_handle_equ
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_bits]
    call    str_cmp_kw
    IF rax, e, 0
        call    parser_handle_bits
        jmp     .check_handler_result
        ENDIF

    mov     rdi, r12
    lea     rsi, [rel str_struc]
    call    str_cmp_kw
    IF rax, e, 0
        mov     rdi, rbx
        call    preprocessor_next_token
        test    rax, rax
        jnz     .done
        mov     rsi, rdx
        mov     rdi, rbx
        call    parser_parse_struc
        jmp     .check_handler_result
        ENDIF

    xor     rax, rax               ; Not a pseudo-op
    jmp     .done

.check_handler_result:
    mov     byte [rel expr_in_data], 0
    mov     qword [rel pos_line_sec], 0
    test    rax, rax
    jnz     .done
    mov     rax, 1

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

%define INCBIN_CHUNK 4096
%define DS_UTF_SIZE  16384        ; __utf16__ / __utf32__ output
%define GSIZE_MAX      256          ; "global f:function (size)" per file
%define GSIZE_TOKENS   64           ; tokens in one size expression

;*
; * [parser_data_string]
; * Purpose: A data item that is a string: a "..." / `...` string, or a
; *   quoted literal standing alone ('abc', not 'a'+1). Its bytes are
; *   emitted and zero-padded to a whole number of units, as NASM does
; *   (dd "abcde" is 8 bytes). Anything else is handed back untouched.
; * Input  : RBX = PrepState, ESI = unit in bytes
; * Output : RAX = OK or an error, EDX = 1 when a string was emitted
; ;
parser_data_string:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r15d, esi
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    movzx   eax, byte [r12 + TOKEN_kind]
    cmp     eax, TOK_STRING
    je      .string
    cmp     eax, TOK_IDENT
    je      .utf
    cmp     eax, TOK_CHAR
    jne     .not
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_COMMA
    je      .chars
    cmp     eax, TOK_NEWLINE
    je      .chars
    cmp     eax, TOK_EOF
    je      .chars
.not:
    mov     rdi, rbx
    mov     rsi, r12
    call    preprocessor_unread_token      ; ahead of the token peeked
    xor     eax, eax
    xor     edx, edx
    jmp     .ret
.chars:
    mov     rax, [r12 + TOKEN_value]       ; packed, first character lowest
    mov     [rel ds_chars], rax
    lea     r14, [rel ds_chars]
    movzx   r13d, word [r12 + TOKEN_len]
    jmp     .emit

.utf:
    ; __utf16__('text') and the others: the string in UTF-16 / UTF-32
    mov     rdi, [r12 + TOKEN_value]
    call    parser_utf_kind
    test    eax, eax
    jz      .not
    mov     r14d, eax                      ; the form
    ; the parentheses may be left out: __utf16__ "text"
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .utf_text
    or      r14d, 0x100                    ; a ")" to come
    mov     rdi, rbx
    call    preprocessor_next_token
.utf_text:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    movzx   r13d, word [r12 + TOKEN_len]
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    je      .utf_chars
    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    jne     .utf_bad
    mov     rsi, [r12 + TOKEN_value]
    test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .utf_close
    mov     rdi, rsi
    call    str_len
    mov     r13, rax
    mov     rsi, [r12 + TOKEN_value]
    jmp     .utf_close
.utf_chars:
    mov     rax, [r12 + TOKEN_value]
    mov     [rel ds_chars], rax
    lea     rsi, [rel ds_chars]
.utf_close:
    test    r14d, 0x100
    jz      .utf_encode
    push    rsi
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rsi
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RPAREN
    jne     .utf_bad
.utf_encode:
    mov     rdi, rsi
    mov     rsi, r13
    movzx   edx, r14b
    call    parser_utf_encode
    test    rax, rax
    jnz     .ret
    mov     r14, [rel ds_utf_buf]
    mov     r13, rdx
    jmp     .emit
.utf_bad:
    mov     eax, EXIT_INVALID_EXPR
    jmp     .ret
.string:
    ; GNU's syntax: "name" in .byte / .long / .quad is a symbol's name, as
    ; GNU as reads it (GCC 16's -masm=intel quotes them: .quad "jb",
    ; .long "x"@dtpoff) - .ascii and the like are its strings
    cmp     byte [rel gas_names], 0
    je      .string_bytes
    cmp     byte [r12 + TOKEN_quote], '"'
    je      .not
.string_bytes:
    mov     r14, [r12 + TOKEN_value]
    movzx   r13d, word [r12 + TOKEN_len]
    test    byte [r12 + TOKEN_flags], TOK_FLAG_COUNTED
    jnz     .emit
    mov     rdi, r14
    call    str_len
    mov     r13, rax
.emit:
    mov     rax, r13
    xor     edx, edx
    div     r15
    xor     ecx, ecx
    test    rdx, rdx
    jz      .no_pad
    mov     rcx, r15
    sub     rcx, rdx
.no_pad:
    mov     [rel ds_pad], rcx
.byte:
    test    r13, r13
    jz      .pad
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, byte [r14]
    call    asmctx_emit_byte
    test    rax, rax
    jnz     .ret
    inc     r14
    dec     r13
    jmp     .byte
.pad:
    cmp     qword [rel ds_pad], 0
    je      .done
    mov     rdi, [rbx + PREP_ctx]
    xor     esi, esi
    call    asmctx_emit_byte
    dec     qword [rel ds_pad]
    jmp     .pad
.done:
    xor     eax, eax
    mov     edx, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

;*
; * [parser_emit_data_wide]
; * Purpose: dt / do / dy / dz: 10-, 16-, 32- and 64-byte items: a
; *   floating-point constant in dt (the x87 80-bit format) or a string,
; *   zero-padded to the unit. NASM takes no plain integer here.
; * Input  : RBX = PrepState, ESI = unit in bytes
; * Output : RAX = OK or an error
; ;
;*
; * [parser_utf_kind]
; * Purpose: Which of NASM's string functions a name is: __utf16__,
; *   __utf16le__, __utf16be__, __utf32__, __utf32le__, __utf32be__ (also
; *   spelled __?utf16?__ ...).
; * Input  : RDI = name
; * Output : EAX = 0 none, else 1 UTF-16 / 2 UTF-32, | 4 big-endian
; ;
parser_utf_kind:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel utf_fn_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_utf_encode]
; * Purpose: UTF-8 text as UTF-16 (surrogate pairs above U+FFFF) or UTF-32,
; *   little- or big-endian, into ds_utf_buf: at most four bytes for each
; *   byte of text, so a bigger buffer is taken first when the text needs it.
; * Input  : RDI = text, RSI = its length, EDX = parser_utf_kind's form
; * Output : RAX = OK or EXIT_INVALID_EXPR (not UTF-8), RDX = bytes written
; ;
parser_utf_encode:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                       ; r12 = position
    lea     r13, [rdi + rsi]               ; r13 = end
    mov     r14d, edx                      ; r14 = form
    lea     rax, [rsi * 4 + 8]
    cmp     rax, [rel ds_utf_cap]
    jbe     .room
    mov     [rel ds_utf_cap], rax
    mov     rsi, rax
    extern  global_ctx
    lea     rdi, [rel global_ctx]
    mov     rdi, [rdi + ASMCTX_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel ds_utf_buf], rdx
.room:
    mov     r15, [rel ds_utf_buf]          ; r15 = output
.char:
    cmp     r12, r13
    jae     .done
    movzx   edx, byte [r12]
    mov     eax, 1
    cmp     edx, 0x80
    jb      .have                          ; ASCII (and NUL)
    mov     rdi, r12
    mov     rsi, r13
    extern  str_utf8_decode
    call    str_utf8_decode                ; rax = length, rdx = code point
    test    rax, rax
    jz      .bad
.have:
    add     r12, rax
    test    r14d, 2
    jnz     .utf32
    cmp     edx, 0x10000
    jb      .unit
    ; a surrogate pair
    sub     edx, 0x10000
    push    rdx
    shr     edx, 10
    add     edx, 0xD800
    call    .put16
    pop     rdx
    and     edx, 0x3FF
    add     edx, 0xDC00
.unit:
    call    .put16
    jmp     .char
.utf32:
    test    r14d, 4
    jz      .le32
    bswap   edx
.le32:
    mov     [r15], edx
    add     r15, 4
    jmp     .char
.done:
    mov     rdx, [rel ds_utf_buf]
    neg     rdx
    add     rdx, r15
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_INVALID_EXPR
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret
.put16:
    test    r14d, 4
    jz      .le16
    xchg    dl, dh
.le16:
    mov     [r15], dx
    add     r15, 2
    ret

parser_emit_data_wide:
    push    r12
    push    r13
    mov     r12d, esi
.loop:
    call    parser_item_begin
    mov     esi, r12d
    call    parser_data_string
    test    rax, rax
    jnz     .ret
    test    edx, edx
    jnz     .next
    ; dt: the x87 80-bit format; do: binary128
    xor     eax, eax
    cmp     r12d, 10
    jne     .fmt_do
    mov     eax, FLT_EXT
.fmt_do:
    cmp     r12d, 16
    jne     .fmt
    mov     eax, FLT_QUAD
.fmt:
    mov     [rel float_fmt], al
    mov     byte [rel float_seen], 0
    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rel float_fmt], 0
    test    rax, rax
    jnz     .ret
    ; "dt ?": ten bytes, uninitialised
    cmp     byte [rel expr_question], 0
    je      .not_question
    mov     r13d, r12d
.question_byte:
    mov     rdi, [rbx + PREP_ctx]
    xor     esi, esi
    call    asmctx_emit_byte
    dec     r13d
    jnz     .question_byte
    jmp     .next
.not_question:
    ; as in NASM, only a float constant (dt) or a string fills these
    cmp     byte [rel float_seen], 0
    je      .not_float
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rdx
    call    asmctx_emit_qword
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [rel float_hi]            ; sign and exponent / high half
    cmp     r12d, 16
    je      .quad_hi
    call    asmctx_emit_word
    jmp     .next
.quad_hi:
    extern  asmctx_emit_qword
    call    asmctx_emit_qword
    jmp     .next
.not_float:
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .ret
.next:
    call    parser_item_end
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    call    parser_data_more
    test    eax, eax
    jnz     .loop
    jmp     .done
.done:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_float_special]
; * Purpose: Is this name __Infinity__, __QNaN__ or __SNaN__?
; * Input  : RDI = name
; * Output : EAX = 1, 2, 3, or 0
; ;
parser_float_special:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel float_special_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_ilog2_func]
; * Purpose: Is this name one of NASM's integer log2 functions?
; * Input  : RDI = name
; * Output : EAX = 1 __?ilog2e?__ (exact), 2 __?ilog2w?__ (warned), 3
; *          __?ilog2f?__ (floor), 4 __?ilog2c?__ (ceiling); 0: none
; ;
parser_ilog2_func:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel ilog2_fn_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_ptr_warn]
; * Purpose: NASM's warning for the word "ptr" (MASM's) where NASM reads
; *   a name: "`ptr' is not a NASM keyword" [-w+ptr]; not under %use masm,
; *   where ptr is a word of its own.
; * Input  : RDI = a name. Preserves every register but rax.
; ;
parser_ptr_warn:
    push    rdi
    push    rsi
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    cmp     byte [rel masm_enabled], 0
    jne     .ret
    test    rdi, rdi
    jz      .ret
    lea     rsi, [rel str_ptr]
    call    str_cmp_kw
    test    rax, rax
    jnz     .ret
    mov     edi, WC_PTR
    call    warn_begin
    test    eax, eax
    jz      .ret
    lea     rsi, [rel str_ptr_warn]
    call    warn_text
    call    warn_end
.ret:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rsi
    pop     rdi
    ret

;*
; * [parser_split_float]
; * Purpose: A number written "1e" or "1.2e" - no integer - with "+" or "-"
; *   and digits after it, the tokens of a pasted "%1e+%2": the float text
; *   "1e+36", the three tokens taken.
; * Input  : RBX = PrepState, RDI = the number's text
; * Output : EAX = 0 and RDX = the text; EAX = 1 (nothing taken) otherwise
; ;
parser_split_float:
    push    r12
    push    r13
    mov     r12, rdi
    ; digits, at most one point, then the e
    xor     ecx, ecx
    xor     r8d, r8d                       ; digits seen
.digit:
    movzx   eax, byte [r12 + rcx]
    cmp     eax, '.'
    je      .next
    sub     eax, '0'
    cmp     eax, 9
    ja      .e
    inc     r8d
.next:
    inc     ecx
    jmp     .digit
.e:
    test    r8d, r8d
    jz      .no
    movzx   eax, byte [r12 + rcx]
    or      eax, 0x20
    cmp     eax, 'e'
    jne     .no
    cmp     byte [r12 + rcx + 1], 0
    jne     .no
    mov     r13d, ecx                      ; the text's length less the e
    ; then + or -, then digits
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .no
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     r8b, '+'
    cmp     eax, TOK_PLUS
    je      .sign
    mov     r8b, '-'
    cmp     eax, TOK_MINUS
    jne     .no
.sign:
    mov     [rel split_sign], r8b
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .no_back
    cmp     byte [rdx + TOKEN_kind], TOK_NUMBER
    jne     .no_back
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, [rdx + TOKEN_value]
    ; the text: the number, e, the sign, the digits
    lea     rdi, [rel split_buf]
    xor     ecx, ecx
.copy_num:
    cmp     ecx, r13d
    ja      .copied_num
    mov     al, [r12 + rcx]
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .copy_num
.copied_num:
    mov     al, [rel split_sign]
    mov     [rdi + rcx], al
    inc     ecx
.copy_exp:
    mov     al, [rsi]
    mov     [rdi + rcx], al
    test    al, al
    jz      .copied
    inc     rsi
    inc     ecx
    cmp     ecx, 62
    jb      .copy_exp
    mov     byte [rdi + rcx], 0
.copied:
    lea     rdx, [rel split_buf]
    xor     eax, eax
    pop     r13
    pop     r12
    ret
.no_back:
    ; (the sign taken and no digits after it: "1e" is no number either way)
.no:
    mov     eax, 1
    pop     r13
    pop     r12
    ret

[SECTION .bss]
split_buf:     resb 64
split_sign:    resb 1
[SECTION .text]

;*
; * [parser_bcd]
; * Purpose: NASM's packed BCD constant, "765432109876543210p" or
; *   "0p765432109876543210" (underscores between digits): 18 decimal
; *   digits, two a byte from the lowest, the sign in the tenth byte. A
; *   longer one keeps its last 18, with NASM's "packed BCD truncated to 18
; *   digits".
; * Input  : RDI = the number's text
; * Output : EAX = 0 and RDX = bytes 0-7, RCX = byte 8 (the sign word's
; *          high byte 0); EAX = 1 when it is not one
; ;
parser_bcd:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    ; the digits: after "0p", or before a last "p"
    cmp     byte [rbx], '0'
    jne     .suffix
    movzx   eax, byte [rbx + 1]
    or      eax, 0x20
    cmp     eax, 'p'
    jne     .suffix
    add     rbx, 2
    mov     r12, rbx
.prefix_end:
    cmp     byte [r12], 0
    je      .digits
    inc     r12
    jmp     .prefix_end
.suffix:
    mov     r12, rbx
.suffix_end:
    cmp     byte [r12], 0
    je      .suffix_p
    inc     r12
    jmp     .suffix_end
.suffix_p:
    cmp     r12, rbx
    je      .no
    movzx   eax, byte [r12 - 1]
    or      eax, 0x20
    cmp     eax, 'p'
    jne     .no
    dec     r12                            ; (the p)
.digits:
    ; rbx .. r12: digits and underscores, at least one digit
    cmp     r12, rbx
    je      .no
    xor     edx, edx                       ; the packed digits, bytes 0-7
    xor     ecx, ecx                       ; byte 8
    xor     r13d, r13d                     ; digits taken
    mov     rsi, r12
.digit:
    cmp     rsi, rbx
    je      .packed
    dec     rsi
    movzx   eax, byte [rsi]
    cmp     eax, '_'
    je      .digit
    sub     eax, '0'
    cmp     eax, 9
    ja      .no
    cmp     r13d, 18
    jae     .more
    mov     r8d, r13d
    shl     r8d, 2                         ; the nibble's bit
    cmp     r8d, 64
    jae     .high
    mov     r9, rax
    mov     ecx, r8d
    shl     r9, cl
    or      rdx, r9
    mov     ecx, [rel bcd_high]
    jmp     .taken
.high:
    lea     ecx, [r8 - 64]
    mov     r9d, eax
    shl     r9d, cl
    or      [rel bcd_high], r9d
    mov     ecx, [rel bcd_high]
.taken:
    inc     r13d
    jmp     .digit
.more:
    mov     byte [rel bcd_cut], 1          ; a digit past the 18th
    jmp     .digit
.packed:
    test    r13d, r13d
    jz      .no
    cmp     byte [rel bcd_cut], 0
    je      .out
    push    rdx
    mov     edi, WC_OTHER
    call    warn_begin
    lea     rsi, [rel s_bcd_cut]
    call    warn_text
    call    warn_end
    pop     rdx
.out:
    mov     ecx, [rel bcd_high]
    mov     dword [rel bcd_high], 0
    mov     byte [rel bcd_cut], 0
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret
.no:
    mov     dword [rel bcd_high], 0
    mov     byte [rel bcd_cut], 0
    mov     eax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
bcd_high:      resd 1                  ; byte 8 (digits 17 and 18)
bcd_cut:       resb 1
[SECTION .rodata]
s_bcd_cut:     db "packed BCD truncated to 18 digits", 0
[SECTION .text]

;*
; * [parser_float_func]
; * Purpose: Is this name __float16__, __float32__ or __float64__?
; * Input  : RDI = name
; * Output : EAX = the FLT_* format, or 0
; ;
parser_float_func:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel float_fn_names]
.name:
    cmp     byte [r13], 0
    je      .none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r13, 16
    jmp     .name
.hit:
    movzx   eax, byte [r13 + 15]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_incbin]
; * Purpose: incbin "file" [, offset [, length]]: the file's bytes.
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_incbin:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    mov     r12, [rdx + TOKEN_value]
    cmp     eax, TOK_STRING
    je      .have_name
    cmp     eax, TOK_CHAR
    jne     .bad
    mov     [rel ds_chars], r12            ; a short 'name', unpacked
    mov     byte [rel ds_chars + 8], 0
    lea     r12, [rel ds_chars]
.have_name:
    xor     r13d, r13d                     ; offset
    mov     r14, -1                        ; length: to the end
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .open
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r13, rdx
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .open
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r14, rdx
.open:
    mov     [rel incbin_name], r12         ; (r12 is the buffer later)
    mov     rdi, r12                       ; as named, then in each -I dir
    extern  incpath_open
    call    incpath_open
    test    rax, rax
    jnz     .not_found
    mov     r15, rdx                       ; fd
    mov     rdi, r15
    mov     rsi, r13
    xor     edx, edx                       ; SEEK_SET
    call    io_lseek
.chunk:
    test    r14, r14
    jz      .close
    mov     rdx, INCBIN_CHUNK
    cmp     r14, rdx
    jae     .read
    mov     rdx, r14
.read:
    mov     rdi, r15
    lea     rsi, [rel incbin_buf]
    call    io_read
    test    rax, rax
    jnz     .close_error
    test    rdx, rdx
    jz      .close                         ; end of the file
    sub     r14, rdx
    mov     r13, rdx
    lea     r12, [rel incbin_buf]
.byte:
    test    r13, r13
    jz      .chunk
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, byte [r12]
    call    asmctx_emit_byte
    inc     r12
    dec     r13
    jmp     .byte
.close:
    mov     rdi, r15
    call    io_close
    mov     edi, 1                         ; the listing: <bin Nh>
    extern  lst_mark
    call    lst_mark
    xor     eax, eax
    jmp     .ret
.close_error:
    mov     r13, rax                       ; "`x' is a directory, not a file",
    mov     rdi, r15                       ; "error reading `x'"
    call    io_close
    mov     rdi, [rel incbin_name]
    call    error_set_subject
    mov     rax, r13
    jmp     .ret
.not_found:
    push    rax                            ; "unable to open `x': no such file"
    mov     rdi, r12
    call    error_set_subject
    pop     rax
    jmp     .ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

[SECTION .bss]
incbin_name:   resq 1                      ; the file being read, for its error
[SECTION .rodata]
str_incbin:    db "incbin", 0
str_list:      db "list", 0
; name (15 bytes) + FLT_* format
; NASM's string functions: name (15), form (parser_utf_kind)
utf_fn_names:
              db "__utf16__", 0, 0, 0, 0, 0, 0, 1
              db "__?utf16?__", 0, 0, 0, 0, 1
              db "__utf16le__", 0, 0, 0, 0, 1
              db "__?utf16le?__", 0, 0, 1
              db "__utf16be__", 0, 0, 0, 0, 5
              db "__?utf16be?__", 0, 0, 5
              db "__utf32__", 0, 0, 0, 0, 0, 0, 2
              db "__?utf32?__", 0, 0, 0, 0, 2
              db "__utf32le__", 0, 0, 0, 0, 2
              db "__?utf32le?__", 0, 0, 2
              db "__utf32be__", 0, 0, 0, 0, 6
              db "__?utf32be?__", 0, 0, 6
              db 0
; name (15 bytes) + parser_ilog2_func's number
ilog2_fn_names: db "__?ilog2e?__", 0, 0, 0, 1
               db "__?ilog2w?__", 0, 0, 0, 2
               db "__?ilog2f?__", 0, 0, 0, 3
               db "__?ilog2c?__", 0, 0, 0, 4
               db "__ilog2e__", 0, 0,0,0,0, 1
               db "__ilog2w__", 0, 0,0,0,0, 2
               db "__ilog2f__", 0, 0,0,0,0, 3
               db "__ilog2c__", 0, 0,0,0,0, 4
               db 0
str_ilog2_warn: db "ilog2 argument is not a power of two", 0
str_ptr_warn:  db "`ptr' is not a NASM keyword", 0
str_ea_absolute: db "absolute address can not be RIP-relative", 0
str_implicit_abs: db "implicit DEFAULT ABS is deprecated", 0
str_masm_ptr:  db "__?masm_ptr?__", 0
str_masm_flat: db "__?masm_flat?__", 0
str_flat:      db "flat", 0
float_fn_names: db "__float8__", 0, 0,0,0,0, FLT_BYTE
               db "__float16__", 0, 0,0,0, FLT_HALF
               db "__bfloat16__", 0, 0,0, FLT_BF16
               db "__?float8?__", 0, 0,0, FLT_BYTE
               db "__?bfloat16?__", 0, FLT_BF16
               db "__float32__", 0, 0,0,0, FLT_SINGLE
               db "__float64__", 0, 0,0,0, FLT_DOUBLE
               db "__float80m__", 0, 0,0, FLT_EXT
               db "__float80e__", 0, 0,0, FLT_EXT | FLT_HIGH
               db "__float128l__", 0, 0, FLT_QUAD
               db "__float128h__", 0, 0, FLT_QUAD | FLT_HIGH
               db "__?float16?__", 0, 0, FLT_HALF
               db "__?float32?__", 0, 0, FLT_SINGLE
               db "__?float64?__", 0, 0, FLT_DOUBLE
               db 0
; name (15 bytes) + 1 infinity / 2 quiet NaN / 3 signalling NaN
float_special_names:
               db "__Infinity__", 0, 0, 0, 1
               db "__QNaN__", 0, 0, 0, 0, 0, 0, 0, 2
               db "__SNaN__", 0, 0, 0, 0, 0, 0, 0, 3
               db "__?Infinity?__", 0, 1
               db "__?QNaN?__", 0, 0, 0, 0, 0, 2
               db "__?SNaN?__", 0, 0, 0, 0, 0, 3
               db "__NaN__", 0, 0, 0, 0, 0, 0, 0, 0, 2
               db "__?NaN?__", 0, 0, 0, 0, 0, 0, 2
               db 0
s_float_overflow: db "overflow in floating-point constant", 0
[SECTION .bss]
float_fmt:     resb 1              ; FLT_* for a float constant here, 0: none
float_seen:    resb 1              ; the last value was a float constant
float_hi:      resq 1              ; its 80-bit sign/exponent word, or
                                   ; binary128's high half
float_part:    resb 1              ; a float function's FLT_HIGH
float_fn_val:  resq 1
ds_utf:        resb DS_UTF_SIZE    ; __utf16__ / __utf32__ text
far_colon:     resb 1              ; a far pointer's colon came with its segment
opnd_to:       resb 1              ; "to" before this operand's st register
opnd_wrap:     resb 1              ; "[QWORD PTR x]": a bracket around the sized operand (GNU's Intel syntax)
alignb 8
inst_ring:     resb INST_RING * INST_SIZE   ; parser_parse_instruction's INSTs
opnd_ring:     resb OPERAND_RING * OPERAND_SIZE ; parser_parse_operand's
inst_ring_next: resd 1
opnd_ring_next: resd 1
global expr_coeff
expr_coeff:    resq 1              ; how the last value moves with $ (1: $ itself)
times_newline: resq 1; the token that ends a times line
times_padto:   resb 1              ; this times count is K - ($ - $$)
equ_again:     resb 1              ; this equ defines a constant again
expr_keep_forward: resb 1           ; an equ: keep a name not defined yet too
expr_keep_quiet: resb 1             ; an equ: a record of a known value too
global expr_pcrel, expr_pcrel_ok
expr_pcrel:    resb 1              ; the value is PC-relative ("x - $", x elsewhere)
expr_pcrel_ok: resb 1              ; ... and the writer can make it so
alignb 8
expr_last_record: resq 1            ; the record the last expression was kept as
global expr_undef_uses, expr_undef_first
expr_undef_uses: resq 1            ; names met not defined (parser_late_equs)
expr_undef_name: resq 1            ; ... the last
expr_undef_first: resq 1           ; ... the first since expr_undef_uses was 0
late_only_alias: resb 1            ; parser_late_aliases: labels only
alignb 8
late_list:     resq 1              ; equs of something defined later:
global late_equ_n                  ; {SYMBOL*, record, file, line}
late_equ_n:    resq 1
%define LATE_CAP (1 << 20)
pseudo_lc:     resb 64             ; a statement word in lower case
ds_chars:      resq 2              ; a quoted literal's characters
ds_pad:        resq 1
incbin_buf:    resb 4096
