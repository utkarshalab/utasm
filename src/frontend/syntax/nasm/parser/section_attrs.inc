; ============================================================================
; File        : src/frontend/syntax/nasm/parser/section_attrs.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : statement words, COFF section attributes and classes, section attributes, segment overrides, and their names
; ============================================================================


;*
; * [parser_is_statement_word]
; * Purpose: Is this word an instruction or a data directive? Used to take
; *          "msg db 'hi'" / "top nop" as a label without its colon.
; * Input  : RSI = word, RBX = PrepState
; * Output : EAX = 1 or 0
; ;
parser_is_statement_word:
    push    r12
    push    r13
    mov     r12, rsi
    lea     r13, [rel stmt_words]
.word:
    cmp     byte [r13], 0
    je      .mnemonic
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .yes
.skip:
    inc     r13
    cmp     byte [r13 - 1], 0
    jne     .skip
    jmp     .word
.mnemonic:
    hash_fnv1a_64_ci r12, r13
    call    parser_get_arch_tables         ; rax = mnemonic table
    mov     rdi, r13
    mov     rsi, rax
    call    parser_lookup_mnemonic
    test    rax, rax
    jnz     .yes
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_skip_to_eol]
; * Purpose: Skip the rest of the statement (a directive utasm accepts but
; *          has nothing to do for, such as "cpu").
; * Input  : RBX = PrepState
; ;
parser_skip_to_eol:
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .ret
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACKET
    je      .ret
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .ret
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .next
.ret:
    xor     eax, eax
    ret

;*
; * [parser_coff_section]
; * Purpose: -f win64: a new section's type, flags and alignment by its
; *   name, as NASM's COFF output has them: .text code (aligned 16), .data
; *   data (4), .bss (4), .rdata and .xdata read-only data (8), .pdata (4);
; *   any other name code (16). Attributes after the name change them.
; * Input  : RDI = the name, R13 = SECTION
; ;
parser_coff_section:
    push    r12
    push    r14
    mov     r12, rdi
    lea     r14, [rel coff_sec_names]
.row:
    cmp     byte [r14], 0
    je      .other
    mov     rdi, r12
    mov     rsi, r14
    call    str_cmp
    test    rax, rax
    jz      .hit
    add     r14, 10
    jmp     .row
.hit:
    movzx   eax, byte [r14 + 9]            ; SEC_TEXT / DATA / BSS / CUSTOM
    mov     [r13 + SECTION_type], al
    movzx   edi, byte [r14 + 8]            ; the class
    jmp     .class
.other:
    mov     byte [r13 + SECTION_type], SEC_CUSTOM
    mov     edi, COFF_CODE
.class:
    mov     esi, 1
    call    parser_coff_class
    pop     r14
    pop     r12
    ret

;*
; * [parser_coff_class]
; * Purpose: -f win64: section R13 made one of NASM's COFF classes (EDI:
; *   COFF_CODE, DATA, RDATA, BSS, INFO, PDATA): its ELF type and flags,
; *   which the COFF converter reads back, and, when ESI = 1, the class's
; *   alignment
; ;
parser_coff_class:
    lea     rax, [rel coff_classes]
    lea     rax, [rax + rdi*8]
    mov     ecx, [rax]
    mov     [r13 + SECTION_elf_type], ecx
    mov     cx, [rax + 4]
    mov     [r13 + SECTION_flags], cx
    test    esi, esi
    jz      .ret
    movzx   ecx, word [rax + 6]
    mov     [r13 + SECTION_align], rcx
.ret:
    ret

;*
; * [parser_section_attrs]
; * Purpose: NASM's section attributes after the name: progbits / nobits,
; *          alloc / noalloc, exec / noexec, write / nowrite, align=N.
; * Input  : RBX = PrepState, R13 = SECTION
; * Output : RAX = OK or an error
; ;
parser_section_attrs:
    push    r12
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .done
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     r12, [rdx + TOKEN_value]
    mov     byte [rel attr_seen], 1        ; (an attribute, known or not)
    mov     rdi, r12
    lea     rsi, [rel attr_progbits]
    call    str_cmp
    test    rax, rax
    jnz     .not_progbits
    mov     dword [r13 + SECTION_elf_type], SHT_PROGBITS
    jmp     .next
.not_progbits:
    mov     rdi, r12
    lea     rsi, [rel attr_nobits]
    call    str_cmp
    test    rax, rax
    jnz     .not_nobits
    mov     dword [r13 + SECTION_elf_type], SHT_NOBITS
    jmp     .next
.not_nobits:
    lea     r8, [rel attr_flag_names]
    xor     ecx, ecx
.flag:
    cmp     ecx, 8                         ; (alloc exec write tls, and no...)
    jae     .not_flag
    push    rcx
    push    r8
    mov     rdi, r12
    mov     rsi, r8
    call    str_cmp
    pop     r8
    pop     rcx
    test    rax, rax
    jz      .flag_hit
    add     r8, 8
    inc     ecx
    jmp     .flag
.flag_hit:
    lea     rax, [rel attr_flag_bits]
    movzx   eax, word [rax + rcx*2]
    test    ecx, 1
    jnz     .flag_off
    or      [r13 + SECTION_flags], ax      ; alloc / exec / write
    jmp     .next
.flag_off:
    not     eax
    and     [r13 + SECTION_flags], ax      ; noalloc / noexec / nowrite
    jmp     .next
.not_flag:
    ; -f win64: NASM's COFF words - code / text, data, rdata, bss, info -
    ; each with its alignment unless align= says it
    extern  coff_enabled
    cmp     byte [rel coff_enabled], 0
    je      .not_coff_word
    mov     rdi, r12
    lea     rsi, [rel coff_attr_words]
    call    parser_word_index
    test    eax, eax
    jz      .not_coff_word
    imul    eax, eax, 12
    lea     rcx, [rel coff_attr_words]
    movzx   edi, byte [rcx + rax - 1]
    xor     esi, esi
    cmp     byte [rel attr_seen + 1], 0
    sete    sil
    call    parser_coff_class
    jmp     .next
.not_coff_word:
    ; flat binary placement: vstart=, start=, follows=
    mov     rdi, r12
    lea     rsi, [rel attr_vstart]
    call    str_cmp
    test    rax, rax
    jz      .vstart
    mov     rdi, r12
    lea     rsi, [rel attr_start]
    call    str_cmp
    test    rax, rax
    jz      .start
    mov     rdi, r12
    lea     rsi, [rel attr_follows]
    call    str_cmp
    test    rax, rax
    jz      .follows
    mov     rdi, r12
    lea     rsi, [rel attr_align]
    call    str_cmp
    test    rax, rax
    jnz     .unknown
    mov     byte [rel attr_seen + 1], 1    ; align= given
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .bad
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_align], rdx
    jmp     .next
.unknown:
    ; an attribute NASM does not have: ignored with NASM's warning, its
    ; value too ("name=3", "name=(1+2)": one token, or one in parentheses)
    mov     qword [rel attr_value], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .unknown_warn
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    mov     rdi, rbx
    call    prep_rec_begin
    test    rax, rax
    jnz     .ret
    mov     qword [rel attr_depth], 0
.value_token:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .value_done
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .value_done
    cmp     eax, TOK_EOF
    je      .value_done
    cmp     eax, TOK_LPAREN
    jne     .value_not_open
    inc     qword [rel attr_depth]
.value_not_open:
    cmp     eax, TOK_RPAREN
    jne     .value_take
    dec     qword [rel attr_depth]
.value_take:
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     qword [rel attr_depth], 0
    jg      .value_token                   ; inside the parentheses
.value_done:
    call    prep_rec_end                   ; rdx = tokens, rcx = how many
    test    rcx, rcx
    jz      .value_none
    mov     rdi, rbx
    mov     rsi, rdx
    mov     rdx, rcx
    call    prep_tokens_text
    test    rax, rax
    jnz     .value_none
    mov     [rel attr_value], rdx
.value_none:
    call    prep_rec_drop
.unknown_warn:
    mov     edi, WC_OTHER
    call    warn_begin
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    jne     .unknown_named
    ; a flat binary: ignoring unknown section attribute: "name=value"
    lea     rsi, [rel s_attr_bin]
    call    warn_text
    mov     rsi, r12
    call    warn_text
    cmp     qword [rel attr_value], 0
    je      .unknown_quote
    lea     rsi, [rel s_attr_eq]
    call    warn_text
    mov     rsi, [rel attr_value]
    call    warn_text
.unknown_quote:
    lea     rsi, [rel s_attr_q]
    call    warn_text
    call    warn_end
    jmp     .next
.unknown_named:
    ; an object: unknown section attribute 'name' ignored on declaration
    ; of section `.s'
    lea     rsi, [rel s_attr_a]
    call    warn_text
    mov     rsi, r12
    call    warn_text
    lea     rsi, [rel s_attr_b]
    call    warn_text
    mov     rsi, [r13 + SECTION_name]
    call    warn_text
    lea     rsi, [rel s_attr_c]
    call    warn_text
    call    warn_end
    jmp     .next
.vstart:
    call    .bin_only
    call    .equals_value
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_vstart], rdx
    or      byte [r13 + SECTION_bin_flags], BIN_VSTART
    jmp     .next
.start:
    call    .bin_only
    call    .equals_value
    test    rax, rax
    jnz     .ret
    mov     [r13 + SECTION_start], rdx
    or      byte [r13 + SECTION_bin_flags], BIN_START
    jmp     .next
.follows:
    call    .bin_only
    mov     rdi, rbx
    call    preprocessor_next_token        ; "="
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .bad
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rax, [rdx + TOKEN_value]
    mov     [r13 + SECTION_follows], rax
    jmp     .next
; .bin_only: vstart=, start=, follows= place sections in a flat binary;
; in any other output NASM ignores them with a warning (r12 = the name)
.bin_only:
    lea     rax, [rel global_ctx]
    cmp     byte [rax + ASMCTX_fmt], FMT_BIN
    je      .bin_ret
    mov     edi, WC_OTHER
    call    warn_begin
    lea     rsi, [rel s_attr_a]
    call    warn_text
    mov     rsi, r12
    call    warn_text
    lea     rsi, [rel s_attr_b]
    call    warn_text
    mov     rsi, [r13 + SECTION_name]
    call    warn_text
    lea     rsi, [rel s_attr_c]
    call    warn_text
    call    warn_end
.bin_ret:
    ret
; "= expr": rax = OK or error, rdx = the value
.equals_value:
    mov     rdi, rbx
    call    preprocessor_next_token
    cmp     byte [rdx + TOKEN_kind], TOK_EQUAL
    jne     .ev_bad
    mov     rdi, rbx
    jmp     parser_evaluate_expression
.ev_bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    ret
.bad:
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .ret
.done:
    xor     eax, eax
.ret:
    pop     r12
    ret

;*
; * [parser_seg_override_flat]
; * Purpose: Is RSI "flat" under %use masm, or __?masm_flat?__ (the
; *   address is flat: no override)? ZF set when it is. Preserves rsi.
; ;
parser_seg_override_flat:
    push    rsi
    mov     rdi, rsi
    lea     rsi, [rel str_masm_flat]
    call    str_cmp
    pop     rsi
    test    rax, rax
    jz      .ret
    cmp     byte [rel masm_enabled], 0
    je      .no
    push    rsi
    mov     rdi, rsi
    lea     rsi, [rel str_flat]
    call    str_cmp_kw
    pop     rsi
    test    rax, rax
    ret
.no:
    or      eax, 1                         ; (ZF clear)
.ret:
    ret

;*
; * [parser_seg_override]
; * Purpose: Record a segment override written inside brackets ([fs:0x28]).
; * Input  : RSI = register name, R12 = OPERAND
; * Output : RAX = OK, or EXIT_INVALID_EXPR if it is not a segment register
; ;
parser_seg_override:
    push    rbx
    push    r13
    mov     r13, rsi
    call    parser_seg_override_flat
    mov     rax, OK
    jz      .ret                           ; "flat:" (%use masm): none
    xor     ebx, ebx
.next:
    mov     rdi, r13
    lea     rsi, [rel seg_names]
    lea     rsi, [rsi + rbx*4]
    call    str_cmp
    test    rax, rax
    jz      .found
    inc     ebx
    cmp     ebx, 6
    jb      .next
    mov     rax, EXIT_INVALID_EXPR
    jmp     .ret
.found:
    lea     rsi, [rel seg_prefix_bytes]
    mov     al, [rsi + rbx]
    mov     [r12 + OPERAND_segment], al
    mov     rax, OK
.ret:
    pop     r13
    pop     rbx
    ret

[SECTION .bss]
deco_buf:   resb 64                 ; the decorator text being matched
numlbl_count: resd NUMLBL_MAX       ; definitions of each numeric label so far
numlbl_digits: resb 24
pos_count:  resq 1                  ; "$" labels made so far

[SECTION .rodata]
str_rel: db "rel", 0
str_rip: db "rip", 0
; AVX-512 decorators, 8 bytes each (parser_parse_decorator relies on the order)
deco_names: db "z", 0, 0, 0, 0, 0, 0, 0
            db "1to2", 0, 0, 0, 0, "1to4", 0, 0, 0, 0, "1to8", 0, 0, 0, 0
            db "1to16", 0, 0, 0, "1to32", 0, 0, 0
            db "rn-sae", 0, 0, "rd-sae", 0, 0, "ru-sae", 0, 0, "rz-sae", 0, 0
            db "sae", 0, 0, 0, 0, 0
deco_dash:  db "-", 0
numlbl_prefix: db "L@num.", 0
pos_prefix: db "L@here.", 0
pos_end_prefix: db "L@here.e", 0       ; an end's (parser_size_late)
numlbl_dot: db ".", 0
; segment registers in REG_CS..REG_SS order, 4 bytes each
seg_names:  db "cs", 0, 0, "ds", 0, 0, "es", 0, 0, "fs", 0, 0, "gs", 0, 0, "ss", 0, 0
; segment override prefixes for REG_CS..REG_SS (cs ds es fs gs ss)
seg_prefix_bytes: db 0x2E, 0x3E, 0x26, 0x64, 0x65, 0x36
str_abs: db "abs", 0
