; ============================================================================
; File        : src/frontend/syntax/nasm/parser/equ.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : org, equ, the late equs and aliases
; ============================================================================


;*
; * [parser_handle_org]
; ;
parser_handle_org:
    prologue
    call    parser_evaluate_expression
    check_err
    
    mov     rdi, [rbx + PREP_ctx]
    mov     r10, [rdi + ASMCTX_curr_sec]
    mov     rdi, [rbx + PREP_ctx]
    mov     r10, [rdi + ASMCTX_curr_sec]
    mov     [r10 + SECTION_addr], rdx
    epilogue

.error:
    epilogue

;*
; * [parser_handle_equ]
; ;
parser_handle_equ:
    prologue
    push    r12
    push    r13

    ; the name this line defines: taken before the expression, whose
    ; symbols would otherwise be taken for it
    mov     rax, [rbx + PREP_ctx]
    mov     r13, [rax + ASMCTX_last_symbol]
    test    r13, r13
    jz      .no_name

    mov     qword [rel known_pos_uses], 0
    extern  known_diff_n
    mov     qword [rel known_diff_n], 0
    mov     byte [rel expr_keep_forward], 1
    mov     byte [rel expr_keep_quiet], 1
    call    relax_defer_begin              ; (the ranges it freezes held)
    call    parser_evaluate_expression
    mov     byte [rel expr_keep_forward], 0
    mov     byte [rel expr_keep_quiet], 0
    test    rax, rax
    jz      .evaluated
    mov     edi, 1
    call    relax_defer_end
    jmp     .error
.evaluated:
    mov     r12, rdx               ; r12 = value

    ; a symbol not defined yet: its value is unknown here, and utasm reads
    ; the source once - the expression is kept and worked out later (no
    ; code need keep its size for it)
    test    rcx, rcx
    jz      .known
    xor     edi, edi
    call    relax_defer_end
    jmp     .forward
.known:
    ; "len equ y - x" over code jumps may shorten: freezing it kept them
    ; long where NASM shortens them. Such an equ is worked out once the
    ; code is laid out, as one of something defined later; pass 2 takes
    ; the value pass 1 found, checked once its code is laid out
    push    r11
    cmp     byte [rel equ_again], 0
    jne     .commit
    cmp     qword [rel known_diff_n], 1
    jne     .commit
    cmp     qword [rel known_pos_uses], 2
    jne     .commit
    cmp     qword [rel expr_last_record], 0
    je      .commit
    extern  known_diff
    mov     rdi, [rel known_diff]
    test    rdi, rdi
    jz      .commit
    cmp     byte [rdi + SECTION_type], SEC_TEXT
    jne     .commit
    mov     rax, [rbx + PREP_ctx]
    cmp     byte [rax + ASMCTX_opt], OPT_NONE
    je      .commit                        ; (-O0, -O1: nothing changes size)
    cmp     byte [rax + ASMCTX_opt], OPT_MIN
    je      .commit
    mov     rsi, [rel known_diff + 8]
    mov     rdx, [rel known_diff + 16]
    extern  relax_range_fixed
    call    relax_range_fixed
    test    eax, eax
    jnz     .commit                        ; nothing there changes size
    xor     edi, edi
    call    relax_defer_end                ; (nothing frozen for it)
    pop     r11
    mov     rdi, [rel expr_last_record]
    cmp     byte [rel known_active], 0
    je      .measure_late
    mov     rsi, [rdi + DEFER_KEY]
    test    rsi, rsi
    jz      .measure_late
    push    rdi
    call    known_lookup
    pop     rdi
    test    eax, eax
    jz      .measure_late
    ; pass 2: the value from pass 1's layout, checked at the end
    mov     r12, rdx
    mov     rsi, rdx
    call    known_note_verify
    xor     r11d, r11d
    jmp     .first
.measure_late:
    mov     byte [rdi + DEFER_DATA], 0
    call    known_note_defer               ; (pass 1: handed on)
    mov     rsi, rdi
    mov     rdi, r13
    call    parser_late_note
    jmp     .error                         ; (rax = OK or the error)
.commit:
    mov     edi, 1
    call    relax_defer_end
    pop     r11

    ; a constant defined again: the same value, or the error a label
    ; defined twice gets
    cmp     byte [rel equ_again], 0
    je      .first
    mov     byte [rel equ_again], 0
    test    r11, r11
    jz      .again_value
    cmp     byte [r11], TAG_SYMBOL
    jne     .again_value
    cmp     word [r11 + SYMBOL_section], 0xFFF1
    jne     .again_bad                     ; now a label
.again_value:
    cmp     r12, [r13 + SYMBOL_value]
    jne     .again_bad
    xor     eax, eax
    jmp     .error
.again_bad:
    mov     rdi, [r13 + SYMBOL_name]
    call    error_set_subject
    mov     rax, EXIT_DUP_SYMBOL
    jmp     .error
.first:

    ; "x equ label [+ n]": x is a label of the same section (NASM's alias),
    ; moved with it when jumps are shortened. Anything else - a number, a
    ; difference of two labels ("$ - msg"), a constant - is a constant.
    mov     word [r13 + SYMBOL_section], 0xFFF1      ; SHN_ABS
    test    r11, r11
    jz      .set
    cmp     byte [r11], TAG_SYMBOL
    jne     .set
    cmp     byte [r11 + SYMBOL_kind], SYM_LABEL
    jne     .set
    movzx   eax, word [r11 + SYMBOL_section]
    test    eax, eax
    jz      .set
    cmp     eax, 0xFF00
    jae     .set
    mov     [r13 + SYMBOL_section], ax
    mov     byte [r13 + SYMBOL_kind], SYM_LABEL
.set:
    mov     [r13 + SYMBOL_value], r12
    ; "len equ $ - msg", "x equ label + 4": not a constant a second pass
    ; could take before its definition (src/core/known.s)
    cmp     qword [rel known_pos_uses], 0
    je      .set_done
    or      byte [r13 + SYMBOL_pflags], SYMF_POSDEP
    ; just one "b - a": it may turn out fixed (known_second_pass)
    cmp     qword [rel known_diff_n], 1
    jne     .set_done
    cmp     qword [rel known_pos_uses], 2
    jne     .set_done
    mov     rdi, r13
    extern  known_note_equ_diff
    call    known_note_equ_diff
.set_done:
    xor     eax, eax
    jmp     .error

.forward:
    ; "len equ end - start" above "end:", "size equ 4 * PAGE" above
    ; "PAGE equ ...": the name stays undefined - what uses it is a forward
    ; reference - and its value is worked out once the code is laid out
    ; (parser_late_equs): at the end of pass 1, for pass 2 to take as a
    ; number (src/core/known.s), and before the relocations are resolved
    cmp     byte [rel equ_again], 0
    jne     .forward_error                 ; (a constant defined again)
    mov     rsi, [rel expr_last_record]
    test    rsi, rsi
    jz      .forward_error
    mov     r12, rcx
    mov     rdi, r13
    call    parser_late_note
    mov     rcx, r12
    test    rax, rax
    jnz     .forward_error
    jmp     .error                         ; (rax = OK)
.forward_error:
    mov     byte [rel equ_again], 0
    mov     rdi, rcx               ; "equ: `y' is not defined yet"
    call    error_set_subject
    mov     rax, EXIT_EQU_FORWARD
    jmp     .error
.no_name:
    mov     rax, EXIT_UNDEF_SYMBOL
.error:
    pop     r13
    pop     r12
    epilogue

; ---- parser_late_note (internal) ----------
; An equ of something not defined yet: the symbol rdi is undefined until
; parser_late_equs works out the record rsi. Output: rax = OK, or an error
; when there is no room.
parser_late_note:
    push    rbx
    mov     rbx, rdi
    mov     rax, [rel late_list]
    test    rax, rax
    jnz     .have
    push    rsi
    mov     rsi, LATE_CAP * 32
    extern  mem_reserve
    call    mem_reserve
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     [rel late_list], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel late_equ_n]
    cmp     rcx, LATE_CAP
    jae     .full
    shl     rcx, 5
    add     rax, rcx
    mov     [rax], rbx
    mov     [rax + 8], rsi
    extern  error_loc_file
    mov     rdx, [rel error_loc_file]
    mov     [rax + 16], rdx
    mov     edx, [rel error_loc_line]
    mov     [rax + 24], rdx
    inc     qword [rel late_equ_n]
    mov     word [rbx + SYMBOL_section], 0
    mov     qword [rbx + SYMBOL_value], 0
    or      byte [rbx + SYMBOL_pflags], SYMF_LATE
    xor     eax, eax
    jmp     .ret
.full:
    mov     eax, EXIT_EQU_FORWARD
.ret:
    pop     rbx
    ret

;*
; * [parser_late_aliases]
; * Purpose: Before jumps are shortened: the late equs that are a label of
; *   a section ("p equ y + 1") become that label now, so that a jump to
; *   them is shortened and they move with the code; the others wait for
; *   parser_late_equs. Nothing is frozen by working them out.
; ;
global parser_late_aliases
parser_late_aliases:
    mov     byte [rel late_only_alias], 1
    call    parser_late_equs
    mov     byte [rel late_only_alias], 0
    xor     eax, eax
    ret

;*
; * [parser_late_equs]
; * Purpose: The equs of something defined later (parser_late_note), worked
; *   out now that every label is placed: round after round, as one may
; *   name another ("a equ b + 1" above "b equ end - start"). Each becomes
; *   what parser_handle_equ makes of a value: a constant, or a label of
; *   its section ("x equ later + 4").
; * Output : RAX = OK, or the error of one that names something never
; *          defined, at its line
; ;
global parser_late_equs
parser_late_equs:
    xor     eax, eax
    cmp     qword [rel late_equ_n], 0
    jne     .work
    ret
.work:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
.round:
    xor     r13d, r13d                     ; r13 = worked out this round
    xor     r14d, r14d                     ; r14 = the first still not
    xor     r12d, r12d
.item:
    cmp     r12, [rel late_equ_n]
    jae     .round_done
    mov     rbx, r12
    shl     rbx, 5
    add     rbx, [rel late_list]
    inc     r12
    mov     r15, [rbx]                     ; the symbol
    test    byte [r15 + SYMBOL_pflags], SYMF_LATE
    jz      .item
    mov     qword [rel known_pos_uses], 0
    mov     qword [rel expr_undef_uses], 0
    extern  relax_no_freeze
    movzx   eax, byte [rel late_only_alias]
    mov     [rel relax_no_freeze], al      ; (before the jumps: freeze nothing)
    mov     rdi, [rbx + 8]
    call    parser_deferred_value
    mov     byte [rel relax_no_freeze], 0
    test    rax, rax
    jnz     .not_yet
    ; a name in it not defined (yet): taken as 0 in arithmetic
    cmp     qword [rel expr_undef_uses], 0
    je      .value
.not_yet:
    test    r14, r14
    jnz     .item
    mov     r14, rbx
    jmp     .item
.value:
    cmp     byte [rel late_only_alias], 0
    je      .define
    ; before the jumps are shortened: only a label of a section now
    test    r11, r11
    jz      .item
    cmp     byte [r11], TAG_SYMBOL
    jne     .item
    cmp     byte [r11 + SYMBOL_kind], SYM_LABEL
    jne     .item
    movzx   eax, word [r11 + SYMBOL_section]
    test    eax, eax
    jz      .item
    cmp     eax, 0xFF00
    jae     .item
.define:
    and     byte [r15 + SYMBOL_pflags], ~SYMF_LATE
    mov     [r15 + SYMBOL_value], rdx
    mov     word [r15 + SYMBOL_section], SHN_ABS
    test    r11, r11
    jz      .posdep
    cmp     byte [r11], TAG_SYMBOL
    jne     .posdep
    cmp     byte [r11 + SYMBOL_kind], SYM_LABEL
    jne     .posdep
    movzx   eax, word [r11 + SYMBOL_section]
    test    eax, eax
    jz      .posdep
    cmp     eax, 0xFF00
    jae     .posdep
    mov     [r15 + SYMBOL_section], ax
    mov     byte [r15 + SYMBOL_kind], SYM_LABEL
    ; its offset in that section: placed sections (a flat binary, an
    ; executable) came with their address (expr_deferred_addr)
    lea     rcx, [rel global_ctx]
    cmp     byte [rcx + ASMCTX_fmt], FMT_BIN
    je      .unplace
    cmp     byte [rcx + ASMCTX_standalone], 0
    je      .posdep
.unplace:
    cmp     ax, [rcx + ASMCTX_seccount]
    ja      .posdep
    mov     rcx, [rcx + ASMCTX_sections]
    mov     rcx, [rcx + rax * 8 - 8]
    test    rcx, rcx
    jz      .posdep
    mov     rax, [rcx + SECTION_addr]
    sub     [r15 + SYMBOL_value], rax
.posdep:
    cmp     qword [rel known_pos_uses], 0
    je      .worked
    or      byte [r15 + SYMBOL_pflags], SYMF_POSDEP
.worked:
    inc     r13
    jmp     .item
.round_done:
    xor     eax, eax
    test    r13, r13
    jz      .no_progress
    test    r14, r14
    jnz     .round
    jmp     .ret
.no_progress:
    test    r14, r14
    jz      .ret
    cmp     byte [rel late_only_alias], 0
    jne     .ret                           ; (the rest after the jumps)
    ; nothing more can be worked out: the first one left names something
    ; never defined (or they name each other) - its error, at its line
    mov     qword [rel expr_undef_name], 0
    mov     rdi, [r14 + 8]
    call    parser_deferred_value
    mov     rsi, [rel expr_undef_name]
    test    rsi, rsi
    jnz     .named
    test    rax, rax
    jnz     .located
    jmp     .undefined
.named:
    ; one of these equs: they name each other
    lea     rdi, [rel global_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .undefined_name
    test    byte [rdx + SYMBOL_pflags], SYMF_LATE
    jz      .undefined_name
    mov     rax, [r14]
    mov     rdi, [rax + SYMBOL_name]
    call    error_set_subject
    mov     eax, EXIT_CIRCULAR_REF
    jmp     .located
.undefined_name:
    mov     rdi, [rel expr_undef_name]
    call    error_set_subject
.undefined:
    mov     eax, EXIT_UNDEF_SYMBOL
.located:
    mov     rdx, [r14 + 16]
    mov     [rel error_loc_file], rdx
    mov     rdx, [r14 + 24]
    mov     [rel error_loc_line], edx
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .rodata]
str_equ:    db "equ", 0
