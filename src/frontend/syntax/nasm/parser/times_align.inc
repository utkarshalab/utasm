; ============================================================================
; File        : src/frontend/syntax/nasm/parser/times_align.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : times, align, typed struc fields ([reg:TYPE].field), MASM fields, mnemonic tests
; ============================================================================

[SECTION .text]

;*
; * [parser_handle_times]
; * Purpose: "times N <directive>" — evaluate the count, then replay the rest
; *   of the line N times by rewinding the lexer. The repeated statement has
; *   to come from the file: a macro or %rep body is replayed from a token
; *   array the lexer cannot be rewound into.
; * Input:
; *   RDI: pointer to PrepState
; * Output:
; *   RAX = EXIT_OK or error code
; ;
parser_handle_times:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    ; 1. Repetition count. "times K-($-$$) db F" pads up to offset K: the
    ;    jump optimizer can then shorten jumps before it and pad more
    ;    (RELAX_PADTO), so the "$ - $$" in it freezes nothing.
    call    relax_defer_begin
    mov     byte [rel times_padto], 0
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .ret
    mov     r15, rdx
    ; a count not known yet (a label or an equ defined later): pass 1
    ; repeats the line 0 times and makes a second pass, which may know it;
    ; the error is the last pass's
    call    parser_count_known
    jz      .count_known
    mov     edi, EXIT_TIMES_NONCONST
    extern  known_defer_error
    call    known_defer_error
    test    eax, eax
    jnz     .times_nonconst
    xor     r15d, r15d
    jmp     .count_done
.count_known:
    cmp     qword [rel expr_coeff], -1
    jne     .count_done
    mov     rax, [rbx + PREP_ctx]
    mov     rdi, [rax + ASMCTX_curr_sec]
    test    rdi, rdi
    jz      .count_done
    mov     rsi, [rdi + SECTION_size]
    call    relax_pending_padto
    mov     [rel times_padto], al
.count_done:
    ; more repetitions than 2^32: an error (NASM's count wraps; it ran for
    ; ever)
    test    r15, r15
    js      .count_small
    mov     eax, 0xFFFFFFFF
    cmp     r15, rax
    jbe     .count_small
    mov     rax, EXIT_TIMES_LARGE
    jmp     .ret
.count_small:

    ; 2. The statement to repeat, with the newline ending it, becomes a
    ;    %rep body: the parser then reads it N times, whether it is an
    ;    instruction or a directive, from a file or inside a macro.
    ; The line is read into the capture area (macro.s) and copied out at its
    ; size at the end (a block for the longest line cost every pass of a
    ; times inside a %rep its full size)
    extern  prep_cap_base
    extern  prep_cap_slot
    extern  prep_cap_take
    call    prep_cap_base
    test    rax, rax
    jnz     .ret
    mov     r12, rdx                   ; the tokens
    xor     r13d, r13d                 ; how many
.token:
    ; the slot first: a capture made while the token is read goes above
    mov     rdi, r12
    mov     esi, r13d
    call    prep_cap_slot
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .captured
    cmp     eax, TOK_EOF
    je      .captured
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     rsi, rdx
    imul    rdi, r13, TOKEN_SIZE
    add     rdi, r12
    copy_token
    inc     r13d
    jmp     .token
.captured:
    mov     [rel times_newline], rdx       ; the newline peeked
    ; the tokens at their size (and a slot for the newline), out of the
    ; capture area
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    call    prep_cap_take
    test    rax, rax
    jnz     .ret
    mov     r12, rdx
    ; "db F" with F a number or a character: written directly, N bytes
    ; (times 4194304 db 0 is a table, not four million statements); with a
    ; count K - ($ - $$) it is padding the jump optimizer can lengthen
    cmp     r13d, 1
    je      .fill_insn
    cmp     r13d, 2
    jne     .not_padto
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_padto
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_db]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_padto
    movzx   eax, byte [r12 + TOKEN_SIZE + TOKEN_kind]
    mov     rdx, [r12 + TOKEN_SIZE + TOKEN_value]
    cmp     eax, TOK_CHAR
    jne     .fill_number
    ; one character only: 'ab' is two bytes and '' none (db writes them all)
    cmp     word [r12 + TOKEN_SIZE + TOKEN_len], 1
    je      .padto_fill
    jmp     .not_padto
.fill_number:
    cmp     eax, TOK_NUMBER
    jne     .not_padto
    mov     rdi, rdx
    call    str_to_int
    test    rax, rax
    jnz     .not_padto
    jmp     .padto_fill
.fill_insn:
    ; "times 260-($-$$) nop": padding of one-byte instructions (nop,
    ; int3, hlt) the jump optimizer can lengthen too (NASM's fwdopt)
    cmp     byte [rel times_padto], 0
    je      .not_padto
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_padto
    lea     r14, [rel fill_insns]
.fill_insn_next:
    cmp     byte [r14], 0
    je      .not_padto
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .fill_insn_hit
    add     r14, 6
    jmp     .fill_insn_next
.fill_insn_hit:
    movzx   edx, byte [r14 + 5]
.padto_fill:
    cmp     byte [rel times_padto], 0
    jne     .padto_record                  ; even empty now: it can grow
    test    r15, r15
    jle     .not_padto                     ; times 0 (or below)
    jmp     .fill_bytes
.padto_record:
    xor     edi, edi
    call    relax_defer_end                ; the range is the padding's own
    ; "times 510-($-$$) db 0" past 510 bytes: no padding, and an error
    ; unless shortening the jumps before it brings the count up to 0
    ; (relax_padto_negative; NASM's last pass decides it)
    test    r15, r15
    jns     .padto_note
    mov     rdi, r15
    extern  relax_padto_negative
    call    relax_padto_negative
    test    rax, rax
    jnz     .ret
.padto_note:
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r15
    movzx   edx, dl
    extern  asm_ctx_padto
    call    asm_ctx_padto
    test    rax, rax
    jnz     .ret
    jmp     .filled
.fill_bytes:
    mov     edi, 1
    call    relax_defer_end
    mov     r14d, edx                      ; the byte
.fill_byte:
    mov     rdi, [rbx + PREP_ctx]
    movzx   esi, r14b
    call    asmctx_emit_byte
    dec     r15
    jnz     .fill_byte
.filled:
    mov     edi, 2                         ; the listing: 00<rep Nh>
    call    lst_mark
    jmp     .ok
.not_padto:
    mov     edi, 1
    call    relax_defer_end
    test    r15, r15
    js      .negative
    test    r13d, r13d
    jz      .ok                        ; "times N" alone
    test    r15, r15
    jle     .ok                        ; "times 0": the line is consumed
    ; "times N resb K": one reservation of N times K, as NASM makes it -
    ; one warning outside .bss, listed as a resb is ("<res 1900000h>"),
    ; not N statements (a 100 MB listing of ?? for times 50 resb 0x80000)
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_res_times
    lea     r14, [rel res_words]
.res_word:
    cmp     byte [r14], 0
    je      .not_res_times
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r14
    call    str_cmp_kw
    test    rax, rax
    jz      .res_times
    add     r14, 5
    jmp     .res_word
.res_times:
    mov     [rel times_res_mul], r15
    mov     r15d, 1
.not_res_times:
    ; the newline that ends each repetition
    mov     rsi, [rel times_newline]
    imul    rdi, r13, TOKEN_SIZE
    add     rdi, r12
    mov     r14, rdi
    copy_token
    mov     byte [r14 + TOKEN_kind], TOK_NEWLINE
    inc     r13d
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     byte [rdx + MACRO_tag], TAG_MACRO
    mov     byte [rdx + MACRO_flags], MACRO_FLAG_TIMES
    mov     qword [rdx + MACRO_name], 0    ; anonymous, like a %rep body
    mov     [rdx + MACRO_ntokens], r13d
    mov     [rdx + MACRO_tokens], r12
    mov     rdi, rbx
    mov     rsi, rdx
    extern  prep_expand_start
    call    prep_expand_start
    test    rax, rax
    jnz     .ret
    mov     [rdx + MACROEXP_rep_count], r15d
    ; "times 2 dw $": $ is where the line starts, in every copy (NASM)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     [rdx + MACROEXP_times_sec], rax
    test    rax, rax
    jz      .ok
    mov     rax, [rax + SECTION_size]
    mov     [rdx + MACROEXP_times_pos], rax
    jmp     .ok
.times_nonconst:
    mov     eax, EXIT_TIMES_NONCONST
    jmp     .ret
.negative:
    ; "TIMES value -1 is negative" (the line is not repeated)
    mov     rdi, r15
    extern  relax_times_subject
    call    relax_times_subject
    mov     eax, EXIT_TIMES_NEGATIVE
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    push    rax
    mov     edi, 1
    call    relax_defer_end                ; (nothing left when done above)
    pop     rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [parser_drain_line]
; * Purpose: Consume tokens up to and including the next newline.
; * Input:
; *   RDI: pointer to PrepState
; ;
parser_drain_line:
    prologue
    push    rbx
    mov     rbx, rdi
.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    IF byte [rdx + TOKEN_kind], e, TOK_EOF
        jmp .done
        ENDIF
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    IF byte [rdx + TOKEN_kind], ne, TOK_NEWLINE
        jmp .loop
        ENDIF
.done:
    xor     rax, rax
    pop     rbx
    epilogue

;*
; * [parser_check_aarch64_shift]
; * Input: RDI = Name String
; * Output: RAX = SHIFT_* or ERR
; ;
parser_check_aarch64_shift:
    prologue
    push    rbx
    mov     rbx, rdi
    
    lea     rsi, [str_lsl]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_LSL
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_lsr]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_LSR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_asr]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_ASR
        jmp .done
        ENDIF
    
    mov     rdi, rbx
    lea     rsi, [str_ror]
    call    str_cmp_kw
    IF rax, e, 0
        mov rax, SHIFT_ROR
        jmp .done
        ENDIF
    
    mov     rax, ERR
.done:
    pop     rbx
    epilogue
; * RSI = type (0 = byte, 1 = p2)
; ;
parser_handle_align:
    prologue
    push    r12
    push    r13
    push    r14
    mov     r12, rsi               ; r12 = type
    
    call    parser_evaluate_expression
    check_err
    mov     r13, rdx               ; r13 = alignment value
    
    ; If p2, convert to byte
    IF r12, e, 1
        ; 2^31 at most, as for align N
        IF r13, a, 31
            mov rax, EXIT_ALIGN_ERROR
            jmp .error
            ENDIF
        mov     rcx, r13
        mov     rax, 1
        shl     rax, cl
        mov     r13, rax
        ELSE
        ; Safety: Validate power-of-2 for standard alignment
        mov     rax, r13
        test    rax, rax
        jz      .error_invalid_align
        mov     rcx, rax
        dec     rcx
        test    rax, rcx
        jnz     .error_invalid_align
        ; 2^32 and above: NASM's "absurdly large segment alignment"
        mov     rax, 0x100000000
        cmp     r13, rax
        jae     .error_align_large
        ENDIF
    
    ; Check for optional fill
    xor     r14, r14               ; default fill
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        call    preprocessor_next_token
        ; NASM writes the fill as an instruction: "align 4, db 0xCC"
        mov     rdi, rbx
        call    preprocessor_peek_token
        cmp     byte [rdx + TOKEN_kind], TOK_IDENT
        jne     .fill_value
        mov     rdi, [rdx + TOKEN_value]
        lea     rsi, [rel str_db]
        call    str_cmp_kw
        test    rax, rax
        jnz     .fill_value
        mov     rdi, rbx
        call    preprocessor_next_token    ; consume "db"
    .fill_value:
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err
        movzx   r14d, dl
        or      r14d, 0x100            ; written by the source
        ELSE
        ; Architecture-specific NOP selection
        mov     rdi, [rbx + PREP_ctx]
        mov     al, [rdi + ASMCTX_target]
        IF al, e, TARGET_AARCH64
            ; For AArch64, NOP is a 4-byte word. Our aligner is byte-based.
            ; Simplified: use 0x00 for now or implement multi-byte padding.
            mov     r14, 0x00
        ELSEIF al, e, TARGET_RISCV64
            mov     r14, 0x00
            ELSE
            mov     r14, 0x90       ; x86_64 NOP
            ENDIF
            ENDIF

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    mov     rdx, r14
    test    r14d, 0x100
    jz      .auto_fill
    extern  asm_ctx_align_fill
    call    asm_ctx_align_fill
    jmp     .aligned
.auto_fill:
    call    asm_ctx_align
.aligned:
    mov     edi, 2                         ; the listing: 90<rep Nh>
    extern  lst_mark
    call    lst_mark

    ; all three: popping only r12 handed the caller back a wrong r12 and a
    ; clobbered r13/r14, which crashed right after "align 4, <fill>"
    pop     r14
    pop     r13
    pop     r12
    mov     rax, OK
    epilogue

.error_invalid_align:
    mov     rax, EXIT_ALIGN_ERROR
    jmp     .error
.error_align_large:
    ; the value in hex, as NASM writes it
    mov     word [rel align_hex], '0x'
    lea     rdi, [rel align_hex + 2]
    mov     rsi, r13
    mov     edx, 16
    extern  int_to_str
    call    int_to_str
    lea     rdi, [rel align_hex]
    call    error_set_subject
    mov     rax, EXIT_ALIGN_LARGE
    jmp     .error

.error:
    pop     r14
    pop     r13
    pop     r12
    epilogue

; parser_object_out: eax = 1 when the output is an object file (-f elf64,
; elf32, win64; not a flat binary or an executable of its own), where org
; and [map] are no directives. Clobbers rcx.
global parser_object_out
parser_object_out:
    xor     eax, eax
    lea     rcx, [rel global_ctx]
    cmp     byte [rcx + ASMCTX_fmt], FMT_ELF64
    jne     .ret
    cmp     byte [rcx + ASMCTX_standalone], 0
    jne     .ret
    inc     eax
.ret:
    ret

;*
; * [parser_fasm_word]
; * Purpose: FASM's statement words (src/frontend/syntax/fasm/fasm.s): "virtual",
; *   "end virtual", "load", "store" - not when a ':' or a NASM word (equ,
; *   resb, db, times) follows: a label of that name then.
; * Input  : RBX = PrepState, R12 = the word (lower case)
; * Output : EAX = 0: none; 1: done, RDX = OK or an error
; ;
parser_fasm_word:
    mov     rdi, r12
    lea     rsi, [rel str_fasm_virtual]
    call    str_cmp
    test    rax, rax
    jz      .virtual
    mov     rdi, r12
    lea     rsi, [rel str_fasm_end]
    call    str_cmp
    test    rax, rax
    jz      .end
    mov     rdi, r12
    lea     rsi, [rel str_fasm_load]
    call    str_cmp
    test    rax, rax
    jz      .load
    mov     rdi, r12
    lea     rsi, [rel str_fasm_store]
    call    str_cmp
    test    rax, rax
    jz      .store
    mov     rdi, r12
    lea     rsi, [rel str_fasm_format]
    call    str_cmp
    test    rax, rax
    jz      .format
    mov     rdi, r12
    lea     rsi, [rel str_fasm_entry]
    call    str_cmp
    test    rax, rax
    jz      .entry
    mov     rdi, r12
    lea     rsi, [rel str_fasm_segment]
    call    str_cmp
    test    rax, rax
    jz      .segment
.none:
    xor     eax, eax
    ret
.format:
    call    .guard
    jne     .none
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rdi, rbx
    extern  fasm_format
    call    fasm_format
    jmp     .done
.entry:
    call    .guard
    jne     .none
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rdi, rbx
    extern  fasm_entry
    call    fasm_entry
    jmp     .done
.segment:
    ; (NASM's "segment .data" stays section's)
    mov     rdi, rbx
    extern  fasm_segment
    call    fasm_segment
    ret
.virtual:
    call    .guard
    jne     .none
    mov     rdi, rbx
    extern  fasm_virtual
    call    fasm_virtual
    jmp     .done
.end:
    ; "end virtual" (an "end" alone is no FASM word here)
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .none
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel str_fasm_virtual]
    call    str_cmp_kw
    test    rax, rax
    jnz     .none
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    extern  fasm_end_virtual
    call    fasm_end_virtual
    jmp     .done
.load:
    call    .guard
    jne     .none
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .none
    mov     rdi, rbx
    extern  fasm_load
    call    fasm_load
    jmp     .done
.store:
    call    .guard
    jne     .none
    mov     rdi, rbx
    extern  fasm_store
    call    fasm_store
.done:
    mov     rdx, rax
    mov     eax, 1
    ret
; .guard: ZF set when the next token lets the word be FASM's
.guard:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .guard_no
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_COLON
    je      .guard_no
    cmp     eax, TOK_NEWLINE
    je      .guard_newline
    cmp     eax, TOK_IDENT
    jne     .guard_yes
    mov     rdi, [rdx + TOKEN_value]
    extern  gas_nasm_word
    call    gas_nasm_word
    test    eax, eax
    jnz     .guard_no
.guard_yes:
    cmp     eax, eax
    ret
.guard_newline:
    ; ("virtual" alone: at $; "load" / "store" need operands)
    mov     rdi, r12
    lea     rsi, [rel str_fasm_virtual]
    call    str_cmp
    test    rax, rax
    ret
.guard_no:
    or      eax, 1
    ret

;*
; * [parser_cpu_num]
; * Purpose: The level a "cpu" word names, for the encoder's obsolete
; *   warnings and its level check (cpu_num: NASM's levels, 1 8086 ... 7
; *   P6, 8 Katmai, 9 Willamette, 10 Prescott, 11 x86-64, 12 Nehalem, 13
; *   Westmere, 14 Sandy Bridge, 15 future - IA-64 Prescott's; 0 any /
; *   all / default).
; * Input  : RDI = the word. Output: EAX = 1 when it names one (cpu_num
; *   set), else 0 (an option: evex, latevex ... or none). Preserves rbx,
; *   r12-r15.
; ;
parser_cpu_num:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rel cpu_levels]
.cn_entry:
    cmp     byte [r13], 0
    je      .cn_none
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    mov     rcx, r13
.cn_skip:
    inc     rcx
    cmp     byte [rcx - 1], 0
    jne     .cn_skip
    test    rax, rax
    jz      .cn_hit
    lea     r13, [rcx + 1]
    jmp     .cn_entry
.cn_hit:
    mov     al, [rcx]
    extern  cpu_num
    mov     [rel cpu_num], al
    mov     eax, 1
    jmp     .cn_ret
.cn_none:
    xor     eax, eax
.cn_ret:
    pop     r13
    pop     r12
    ret

;*
; * [parser_is_mnemonic]
; * Purpose: Is the word one of the target's mnemonics? (MASM's "NAME
; *   TYPE ..." is data, not "push dword 5".)
; * Input  : RBX = PrepState, RDI = the word
; * Output : EAX = 1 / 0. Preserves rbx, r12-r15.
; ;
global parser_is_mnemonic
parser_is_mnemonic:
    push    r13
    push    r14
    mov     r14, rdi
    hash_fnv1a_64_ci r14, r13
    call    parser_get_arch_tables
    mov     rdi, r13
    mov     rsi, rax
    call    parser_lookup_mnemonic
    test    rax, rax
    setnz   al
    movzx   eax, al
    pop     r14
    pop     r13
    ret

extern  ns_ref_suffix
[SECTION .rodata]
str_size_suffix: db "_size", 0
[SECTION .text]

; parser_is_struc: ZF = 1 when rsi names a struc (NASM's: NAME_size is
; defined with it). Preserves rsi, rbx, r12-r15.
parser_is_struc:
    push    rsi
    lea     rdi, [rel struc_size_buf]
    xor     ecx, ecx
.is_copy:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .is_suffix
    cmp     ecx, 128
    jae     .is_no
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .is_copy
.is_suffix:
    mov     dword [rdi + rcx], '_siz'
    mov     word [rdi + rcx + 4], 'e'
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel struc_size_buf]
    call    symbol_find
    test    rax, rax
    pop     rsi
    ret
.is_no:
    pop     rsi
    test    esp, esp
    ret

;*
; * [parser_typed_field]
; * Purpose: "[rbx:PACKET].len": the memory operand addresses a PACKET
; *   (mem_struc); ".len" after it is PACKET.len - its offset added, its
; *   width the operand's size when none is written (and a size written
; *   must be its: "word [rbx:PACKET].len", .len a dword, is an error).
; *   With no field after it, the operand is the struc's start, unsized.
; * Input  : RBX = PrepState, R12 = the OPERAND
; * Output : RAX = OK or an error
; ;
parser_typed_field:
    push    r14
    mov     r14, [rel mem_struc]
    test    r14, r14
    jz      .tf_ok
    mov     qword [rel mem_struc], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .tf_ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .tf_ok
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .tf_ok
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, [rdx + TOKEN_value]
    push    r14
    mov     r14, [rsp]
    call    parser_concat_local_name       ; "PACKET" + ".len"
    pop     r14
    test    rax, rax
    jnz     .tf_ret
    mov     rsi, rdx
    push    rsi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    pop     rsi
    test    rax, rax
    jnz     .tf_unknown
    test    byte [rdx + SYMBOL_pflags], SYMF_STRUC
    jz      .tf_unknown
    mov     rax, [rdx + SYMBOL_value]
    add     [r12 + OPERAND_imm], rax
    movzx   eax, byte [rdx + SYMBOL_fwidth]
    test    eax, eax
    jz      .tf_ok                         ; (no res* for it: no size)
    shl     eax, 3                         ; bits
    movzx   ecx, byte [r12 + OPERAND_size]
    test    ecx, ecx
    jz      .tf_size
    cmp     ecx, eax
    je      .tf_ok
    mov     rdi, rsi
    call    error_set_subject
    mov     eax, EXIT_FIELD_SIZE
    jmp     .tf_ret
.tf_size:
    mov     [r12 + OPERAND_size], al
    mov     [r12 + OPERAND_xsize], ax
.tf_ok:
    xor     eax, eax
.tf_ret:
    pop     r14
    ret
.tf_unknown:
    mov     rdi, rsi
    call    error_set_subject
    mov     eax, EXIT_MASM_FIELD
    pop     r14
    ret

;*
; * [parser_masm_field]
; * Purpose: %use masm's "[rbx].POINT.y": after a memory operand, ".T.F" -
; *   the field's offset added, its size the operand's when none is
; *   written (src/frontend/syntax/masm/masm.s).
; * Input  : RBX = PrepState, R12 = the OPERAND
; * Output : RAX = OK or an error
; ;
parser_masm_field:
    cmp     byte [rel masm_hl], 0
    je      .ok
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ok
    mov     rsi, [rdx + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .ok
    cmp     byte [rsi + 1], '.'
    je      .ok
    push    rsi
    mov     rdi, rbx
    call    preprocessor_next_token
    pop     rsi
    inc     rsi                            ; "POINT.y"
    push    rsi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    pop     rsi
    test    rax, rax
    jnz     .unknown
    mov     rax, [rdx + SYMBOL_value]
    add     [r12 + OPERAND_imm], rax
    cmp     byte [r12 + OPERAND_size], 0
    jne     .ok
    mov     rdi, rsi
    extern  masm_field_size
    call    masm_field_size
    test    eax, eax
    jz      .ok
    shl     eax, 3                         ; (bits)
    mov     [r12 + OPERAND_size], al
    mov     [r12 + OPERAND_xsize], ax
.ok:
    xor     eax, eax
.ret:
    ret
.unknown:
    mov     rdi, rsi
    call    error_set_subject
    mov     eax, EXIT_MASM_FIELD
    ret

;*
; * [parser_map_words]
; * Purpose: "[map all file.map]": each word an option or the file
; *   (src/object/map.s), to the line's end or its ].
; * Input  : RBX = PrepState
; * Output : RAX = OK or an error
; ;
parser_map_words:
.next:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .ret
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .done
    cmp     eax, TOK_EOF
    je      .done
    cmp     eax, TOK_RBRACKET
    je      .done
    cmp     eax, TOK_IDENT
    je      .word
    cmp     eax, TOK_STRING
    jne     .bad
.word:
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, [rdx + TOKEN_value]
    extern  map_option
    call    map_option
    jmp     .next
.done:
    xor     eax, eax
.ret:
    ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
    ret
