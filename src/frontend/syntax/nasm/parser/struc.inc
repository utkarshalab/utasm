; ============================================================================
; File        : src/frontend/syntax/nasm/parser/struc.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : struc / endstruc, defining a label (local names), GNU names, .equ / .set
; ============================================================================


[SECTION .text]

; ============================================================================
; PARSER EXTENSION: SAFE STRUCT REGISTRATION
; ============================================================================

;*
; * [parser_parse_struc]
; * Purpose: Parse a `struc` ... `endstruc` block.
; *   For each `field name, size` line, registers a SYMBOL with:
; *     kind  = SYM_STRUCT_FIELD
; *     value = byte offset within the struct
; *     size  = declared field byte width
; *   At `endstruc`, registers the struct name itself with:
; *     kind  = SYM_STRUCT
; *     value = 0
; *     size  = total struct size in bytes
; * Input:
; *   RBX: pointer to PrepState
; *   RDI: pointer to the struct-name Token (the token after 'struc')
; * Output:
; *   RAX = EXIT_OK or error code
; ;
global parser_parse_struc
parser_parse_struc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    ; Locals. The offset must survive calls to the token reader and the
    ; expression evaluator, neither of which preserves the scratch registers.
    ;   [rbp - 48] running byte offset
    ;   [rbp - 56] field name pointer
    ;   [rbp - 64] field byte width
    ;   [rbp - 72] field alignment
    ;   [rbp - 80] length of the struct name
    ;   [rbp - 88] length of the field name
    ;   [rbp - 96] 1 once a field is written in NASM's form
    ;   [rbp - 104] the base offset ("struc s, -40"; 0)
    sub     rsp, 64

    mov     rbx, rdi               ; rbx = PrepState
    mov     r15, rsi               ; r15 = struct name Token
    mov     qword [rbp - 48], 0    ; running byte offset
    mov     qword [rbp - 96], 0
    mov     qword [rbp - 104], 0

    ; Build struct-name string ("StructName", null-terminated from token)
    mov     r13, [r15 + TOKEN_value]  ; r13 = struct name ptr
    test    r13, r13
    jz      .struc_named
    mov     rsi, r13
    xor     edx, edx
    call    ns_qualify                     ; (net::PACKET inside net)
    mov     r13, rsi
.struc_named:

    ; the struct itself: kind=SYM_STRUCT, defined here as in NASM (its
    ; place in .symtab under -g: before its fields); its size at endstruc
    test    r13, r13
    jz      .field_loop                    ; "struc" alone: no name
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     word [rsi + SYMBOL_section], SHN_ABS ; a number, as for equ
    mov     [rsi + SYMBOL_name],  r13     ; struct name ptr
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; "struc s, -40": the fields from that offset on, the struct's own name
    ; that offset (NASM's [absolute -40]); its size the bytes from there
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err_to .error
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .field_loop
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    mov     [rbp - 48], rdx
    mov     [rbp - 104], rdx
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .field_loop
    mov     rax, [rbp - 104]
    mov     [rdx + SYMBOL_value], rax

.field_loop:
    ; Read next meaningful token (skip newlines)
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    mov     r12, rdx
    
    mov     al, [r12 + TOKEN_kind]
    
    IF al, e, TOK_NEWLINE
        jmp     .field_loop
        ENDIF
    
    IF al, e, TOK_EOF
        mov     rax, EXIT_UNEXPECTED_EOF
        jmp     .error
        ENDIF

    ; a section line ("section .text", "[section .data]"): NASM's struc
    ; is "[absolute 0]" until endstruc, so the layout ends there and the
    ; lines after it are assembled into that section (.struc_left)
    cmp     al, TOK_LBRACKET
    jne     .not_bracket
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err_to .error
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .not_section_line
    mov     rdi, [rdx + TOKEN_value]
    call    .is_section_word
    jnz     .not_section_line
    ; "[section .data]": the primitive
    mov     byte [rel stmt_bracketed], 1
    mov     rdi, rbx
    call    preprocessor_next_token        ; the word
    jmp     .struc_left
.not_bracket:
    cmp     al, TOK_IDENT
    jne     .not_section_line
    mov     rdi, [r12 + TOKEN_value]
    call    .is_section_word
    jnz     .not_section_line
    ; "section .data": NASM's macro, a number of its %% counter
    mov     byte [rel stmt_bracketed], 0
    mov     rax, [rbx + PREP_ctx]
    inc     dword [rax + ASMCTX_mac_exp_id]
    jmp     .struc_left
.not_section_line:
    mov     al, [r12 + TOKEN_kind]

    ; NASM's ".x:" field label (a "name:" one too)
    IF al, e, TOK_LOCAL_LABEL
        jmp     .nasm_label
        ENDIF
    IF al, e, TOK_LABEL
        jmp     .nasm_label
        ENDIF

    ; Check for 'endstruc'
    IF al, e, TOK_IDENT
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_endstruc]
        extern  str_compare
        call    str_cmp_kw
        IF rax, e, 0
            ; a standard macro in NASM: one number of its %% counter
            mov     rax, [rbx + PREP_ctx]
            inc     dword [rax + ASMCTX_mac_exp_id]
            jmp .register_struct
            ENDIF
        
        ; Check for 'field' keyword; any other word is NASM's form
        mov     rdi, [r12 + TOKEN_value]
        lea     rsi, [str_field]
        call    str_compare
        IF rax, ne, 0
            jmp     .nasm_word
            ENDIF
            ELSE
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; Parse: field <name>, <size>
    ; 1. Field name
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    mov     rax, [rdx + TOKEN_value]
    mov     [rbp - 56], rax            ; field name ptr

    ; Consume comma
    mov     rdi, rbx
    call    preprocessor_next_token
    check_err_to .error
    IF byte [rdx + TOKEN_kind], ne, TOK_COMMA
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .error
        ENDIF
    
    ; 2. Field byte size (expression)
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    mov     [rbp - 64], rdx            ; field byte width

    ; 3. Optional: Alignment (A77)
    mov     qword [rbp - 72], 1        ; default alignment
    mov     rdi, rbx
    call    preprocessor_peek_token
    IF byte [rdx + TOKEN_kind], e, TOK_COMMA
        mov     rdi, rbx
        call    preprocessor_next_token ; consume TOK_COMMA
        mov     rdi, rbx
        call    parser_evaluate_expression
        check_err_to .error
        mov     [rbp - 72], rdx

        ; VALIDATION: Power of 2 (Industrial Safety)
        mov     rax, rdx
        dec     rax
        test    rdx, rax
        jnz     .error_invalid_align
        ENDIF

    ; Apply Alignment: offset = (offset + align - 1) & -align
    mov     rax, [rbp - 48]            ; current offset
    add     rax, [rbp - 72]
    dec     rax
    mov     rcx, [rbp - 72]
    neg     rcx
    and     rax, rcx                   ; rax = aligned offset
    mov     [rbp - 48], rax

    ; Build the qualified field name "<Struct>_<field>". NASM's struc
    ; emulation in macro.inc defines the same name, so both toolchains agree.
    mov     rdi, r13
    extern  str_len
    call    str_len
    mov     [rbp - 80], rax
    mov     rdi, [rbp - 56]
    call    str_len
    mov     [rbp - 88], rax

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rbp - 80]
    add     rsi, [rbp - 88]
    add     rsi, 2                     ; '_' + NUL
    call    arena_alloc
    check_err_to .error
    mov     r12, rdx                   ; r12 = qualified name buffer

    mov     rdi, r12
    mov     rsi, r13
    mov     rcx, [rbp - 80]
    rep movsb
    mov     byte [rdi], '_'
    inc     rdi
    mov     rsi, [rbp - 56]
    mov     rcx, [rbp - 88]
    rep movsb
    mov     byte [rdi], 0

    ; Register SYMBOL: kind=SYM_STRUCT_FIELD, value=offset, size=field_size
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    ; Zero the symbol
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_STRUCT_FIELD
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     word [rsi + SYMBOL_section], SHN_ABS ; a number, as for equ
    mov     [rsi + SYMBOL_name],  r12      ; qualified field name
    mov     rax, [rbp - 48]
    mov     [rsi + SYMBOL_value], rax      ; byte offset
    mov     rax, [rbp - 64]
    mov     [rsi + SYMBOL_size],  rax      ; field byte width
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; Advance offset
    mov     rax, [rbp - 48]
    add     rax, [rbp - 64]
    mov     [rbp - 48], rax
    jmp     .field_loop
    
    ; ---- NASM's form: ".x: resd 1", ".y resw 2", "resb 4", "alignb 8" ----
    ; A field is a plain number, "<struct>.x" (or the name itself when it
    ; has no dot); the reservation after it moves the offset on.
.nasm_word:
    mov     byte [rbp - 96], 1
    mov     rdi, [r12 + TOKEN_value]
    call    parser_res_unit                ; eax = bytes per unit, 0 if none
    test    eax, eax
    jnz     .nasm_res
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_alignb]
    call    str_cmp_kw
    test    rax, rax
    jz      .nasm_alignb
    ; "align 64" in a structure: as alignb (NASM accepts it where it pads
    ; nothing, and has no code to pad with here)
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [rel str_align]
    call    str_cmp_kw
    test    rax, rax
    jz      .nasm_alignb
    ; any other word names a field (a label without its colon)
.nasm_label:
    mov     byte [rbp - 96], 1
    mov     rsi, [r12 + TOKEN_value]
    cmp     byte [rsi], '.'
    jne     .nasm_named
    mov     [rbp - 56], rsi
    mov     rdi, r13
    call    str_len
    mov     [rbp - 80], rax
    mov     rdi, [rbp - 56]
    call    str_len
    mov     [rbp - 88], rax
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, [rbp - 80]
    add     rsi, [rbp - 88]
    inc     rsi                            ; NUL
    call    arena_alloc
    check_err_to .error
    mov     r12, rdx
    mov     rdi, rdx
    mov     rsi, r13
    mov     rcx, [rbp - 80]
    rep movsb
    mov     rsi, [rbp - 56]
    mov     rcx, [rbp - 88]
    rep movsb
    mov     byte [rdi], 0
    mov     rsi, r12                       ; "<struct>.x"
.nasm_named:
    mov     rdx, [rbp - 48]
    mov     [rel last_label_name], rsi     ; (its res*: its width)
    mov     [rel last_label_off], rdx
    call    parser_struc_const
    check_err_to .error
    jmp     .field_loop
.nasm_res:
    mov     [rbp - 64], rax                ; bytes per unit
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    imul    rdx, [rbp - 64]
    mov     rcx, [rbp - 48]
    mov     r8, [rbp - 64]
    call    parser_field_width
    mov     rdi, [rbp - 48]                ; the listing: its offset, size
    mov     rsi, rdx
    push    rdx
    extern  lst_field
    call    lst_field
    pop     rdx
    add     [rbp - 48], rdx
    jmp     .field_loop
.nasm_alignb:
    ; NASM's align / alignb macros: two numbers of its %% counter
    mov     rax, [rbx + PREP_ctx]
    add     dword [rax + ASMCTX_mac_exp_id], 2
    mov     rdi, rbx
    call    parser_evaluate_expression
    check_err_to .error
    mov     rax, [rbp - 48]
    lea     rax, [rax + rdx - 1]
    neg     rdx
    and     rax, rdx
    mov     rdi, [rbp - 48]
    mov     rsi, rax
    sub     rsi, rdi
    mov     [rbp - 48], rax
    call    lst_field
    jmp     .field_loop

.struc_left:
    ; the section line taken as it is outside; the size the fields so far
    ; make, and "<name>_size" left for endstruc, which NASM makes a label
    ; where it then is (parser_endstruc_late)
    mov     rdi, rbx
    call    parser_handle_section_directive
    check_err_to .error
    call    parser_skip_to_eol
    mov     rdi, rbx
    call    preprocessor_peek_token
    check_err_to .error
    cmp     byte [rdx + TOKEN_kind], TOK_RBRACKET
    jne     .left_line
    mov     rdi, rbx
    call    preprocessor_next_token        ; "]"
.left_line:
    test    r13, r13
    jz      .left
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .left_named
    cmp     byte [rdx + SYMBOL_kind], SYM_STRUCT
    jne     .left_named
    mov     rax, [rbp - 48]
    sub     rax, [rbp - 104]
    mov     [rdx + SYMBOL_size], rax
.left_named:
    mov     [rel struc_open], r13
.left:
    xor     eax, eax
    jmp     .done

; .is_section_word: rdi = a word -> ZF when it is section / segment (any
; case)
.is_section_word:
    push    rdi
    lea     rsi, [rel str_section]
    call    str_cmp_kw
    pop     rdi
    test    rax, rax
    jz      .is_section_ret
    lea     rsi, [rel str_segment]
    call    str_cmp_kw
    test    rax, rax
.is_section_ret:
    ret

.register_struct:
    ; NASM's endstruc goes back to the section (__SECT__), which makes
    ; .text if the source has named none: utasm's own .text is named here
    ; then (its place among the sections, and a COFF object has it)
    mov     rax, [rbx + PREP_ctx]
    mov     rcx, [rax + ASMCTX_curr_sec]
    test    rcx, rcx
    jz      .sect_back
    cmp     byte [rcx + SECTION_implicit], 0
    je      .sect_back
    cmp     dword [rcx + SECTION_named_at], 0
    jne     .sect_back
    movzx   eax, word [rax + ASMCTX_seccount]
    mov     [rcx + SECTION_named_at], eax
.sect_back:
    ; the struct's total byte size (defined at struc)
    test    r13, r13
    jz      .no_nasm_size                  ; "struc" alone: nothing to name
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .struct_sized
    cmp     byte [rdx + SYMBOL_kind], SYM_STRUCT
    jne     .struct_sized
    mov     rax, [rbp - 48]
    sub     rax, [rbp - 104]               ; (from the base offset)
    mov     [rdx + SYMBOL_size], rax
.struct_sized:

    ; Register the struct size constant: "[StructName]_SIZE"
    ; 1. Calculate struct name length
    mov     rdi, r13
    call    str_len
    mov     r12, rax                   ; r12 = length of struct name
    
    ; 2. Allocate buffer from arena for "[StructName]_SIZE" (len + 5 for "_SIZE" + 1 for null = len + 6)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r12
    add     rsi, 6
    extern  arena_alloc
    call    arena_alloc
    check_err_to .error
    mov     r15, rdx                   ; r15 = allocated buffer ptr
    
    ; 3. Copy struct name to r15
    mov     rdi, r15
    mov     rsi, r13
    mov     rcx, r12
    rep movsb
    
    ; 4. Append "_SIZE" and null terminate
    mov     byte [r15 + r12],     '_'
    mov     byte [r15 + r12 + 1], 'S'
    mov     byte [r15 + r12 + 2], 'I'
    mov     byte [r15 + r12 + 3], 'Z'
    mov     byte [r15 + r12 + 4], 'E'
    mov     byte [r15 + r12 + 5], 0
    
    ; 5. Register the struct size constant: kind=SYM_CONSTANT, value=total
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag],  TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_CONSTANT
    mov     byte [rsi + SYMBOL_vis],  VIS_LOCAL
    mov     [rsi + SYMBOL_name],  r15     ; "[StructName]_SIZE"
    mov     rax, [rbp - 48]
    sub     rax, [rbp - 104]
    mov     [rsi + SYMBOL_value], rax     ; total byte size as value!
    mov     qword [rsi + SYMBOL_size], 8  ; size of QWORD constant
    call    symbol_add
    add     rsp, SYMBOL_SIZE

    ; NASM's form names the size "<struct>_size"
    cmp     byte [rbp - 96], 0
    je      .no_nasm_size
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r12 + 6]
    call    arena_alloc
    check_err_to .error
    mov     rdi, rdx
    mov     rsi, r15
    lea     rcx, [r12 + 6]
    rep movsb
    mov     dword [rdx + r12 + 1], 'size'
    mov     rsi, rdx
    mov     rdx, [rbp - 48]
    sub     rdx, [rbp - 104]               ; (from the base offset)
    call    parser_struc_const
    check_err_to .error
.no_nasm_size:

    xor     rax, rax
    jmp     .done

.error_no_global:
    mov     rax, EXIT_UNDEF_SYMBOL
    jmp     .error

.error_invalid_align:
    mov     rax, EXIT_ALIGN_ERROR
    jmp     .error

.error:
.done:
    add     rsp, 64                    ; discard the locals frame
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret


;*
; * [parser_define_label]
; * Input: RBX = PrepState, RSI = name string
; ;
global parser_define_label
parser_define_label:
    prologue
    ; inside a namespace: its full name, net::x (src/semantic/namespace.s)
    extern  ns_qualify
    mov     edx, 1
    call    ns_qualify
    push    rbx
    push    rsi
    ; inside a proc: a place paths meet (src/semantic/proc.s)
    extern  proc_active, proc_label
    cmp     byte [rel proc_active], 0
    je      .no_proc
    call    proc_label
.no_proc:
    ; the last label and where: a struc field's res* gives it its width
    ; (its name: the symbol's own copy, at the end)
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    mov     qword [rel last_label_off], -1
    test    rax, rax
    jz      .no_last_off
    mov     rcx, [rax + SECTION_size]
    mov     [rel last_label_off], rcx
.no_last_off:
    mov     rdi, rsi
    call    parser_ptr_warn                ; "ptr:" / "ptr equ": NASM's warning
    mov     rbx, [rbx + PREP_ctx]
    
    ; 1. Check if the symbol already exists
    mov     rdi, rbx
    mov     rsi, [rsp]                         ; Retrieve original name from stack
    extern  symbol_find
    call    symbol_find
    IF rax, e, OK
        ; Symbol already exists! Check if it is currently undefined
        cmp     byte [rdx + SYMBOL_kind], SYM_UNKNOWN
        je      .define_existing
        cmp     word [rdx + SYMBOL_section], 0
        je      .define_existing
        
        ; Otherwise, it's defined already! Duplicate symbol!
        mov     rdi, [rsp]                 ; "label `x' inconsistently
        call    error_set_subject          ;  redefined"
        mov     rax, EXIT_DUP_SYMBOL
        jmp     .error_no_stack
        ENDIF
        
    ; Create Symbol struct
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, (SYMBOL_SIZE / 8)
    rep stosq
    
    ; Setup symbol fields using stable rsi = rsp
    mov     rsi, rsp
    mov     byte [rsi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsi + SYMBOL_kind], SYM_LABEL
    mov     rax, [rsp + SYMBOL_SIZE]            ; Retrieve original label name from stack
    mov     [rsi + SYMBOL_name], rax
    
    ; Set value to current section location
    mov     rax, [rbx + ASMCTX_curr_sec]
    IF rax, ne, 0
        mov     rcx, [rax + SECTION_size]
        mov     [rsi + SYMBOL_value], rcx
        movzx   ecx, word [rax + SECTION_index]
        mov     [rsi + SYMBOL_section], cx
        call    .after_pad
        ENDIF
    ; in an "absolute" block (or a FASM virtual one) a label is a plain
    ; number
    test    rax, rax
    jz      .not_abs_new
    cmp     byte [rax + SECTION_type], SEC_ABSOLUTE
    jne     .not_abs_new
    mov     byte [rsi + SYMBOL_kind], SYM_CONSTANT
    or      byte [rsi + SYMBOL_pflags], SYMF_STRUC
    mov     rcx, [rax + SECTION_addr]
    add     [rsi + SYMBOL_value], rcx
    mov     word [rsi + SYMBOL_section], SHN_ABS    ; (as an equ: pass 2 knows it)
.not_abs_new:

    mov     rdi, rbx
    mov     rsi, rsp
    extern  symbol_add
    call    symbol_add
    check_err_to .error
    mov     [rbx + ASMCTX_last_symbol], rdx    ; Store for potential equ override
    mov     rcx, [rdx + SYMBOL_name]
    mov     [rel last_label_name], rcx
    xor     eax, eax

    add     rsp, SYMBOL_SIZE
    pop     rsi
    pop     rbx
    epilogue

; .after_pad: the label rsi (at the end of section rax): its padding rank -
; the paddings empty when read just before it (an align, a times
; K-($-$$)), which it stays after as they grow; one noted after it stays
; after it. Keeps all but the flags
.after_pad:
    push    rax
    push    rdi
    push    rsi
    push    rcx
    mov     rdi, rax
    mov     rsi, [rax + SECTION_size]
    extern  relax_pad_rank
    call    relax_pad_rank
    pop     rcx
    pop     rsi
    pop     rdi
    mov     [rsi + SYMBOL_lflags], al
    pop     rax
    ret

.define_existing:
    mov     byte [rdx + SYMBOL_kind], SYM_LABEL
    mov     byte [rdx + SYMBOL_tag], TAG_SYMBOL
    ; defined now (declared global, or used, before): its place in
    ; NASM's order (-f win64)
    extern  sym_defseq
    inc     dword [rel sym_defseq]
    mov     eax, [rel sym_defseq]
    mov     [rdx + SYMBOL_defseq], eax

    ; Set value to current section location
    mov     rax, [rbx + ASMCTX_curr_sec]
    IF rax, ne, 0
        mov     rcx, [rax + SECTION_size]
        mov     [rdx + SYMBOL_value], rcx
        movzx   ecx, word [rax + SECTION_index]
        mov     [rdx + SYMBOL_section], cx
        push    rsi
        mov     rsi, rdx
        call    .after_pad
        pop     rsi
        ENDIF
    test    rax, rax
    jz      .not_abs_old
    cmp     byte [rax + SECTION_type], SEC_ABSOLUTE
    jne     .not_abs_old
    mov     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    or      byte [rdx + SYMBOL_pflags], SYMF_STRUC
    mov     rcx, [rax + SECTION_addr]
    add     [rdx + SYMBOL_value], rcx
    mov     word [rdx + SYMBOL_section], SHN_ABS
.not_abs_old:
        
    mov     [rbx + ASMCTX_last_symbol], rdx    ; Store for potential equ override
    mov     rax, [rdx + SYMBOL_name]
    mov     [rel last_label_name], rax
    
    xor     rax, rax
    pop     rsi
    pop     rbx
    epilogue

.error:
    add     rsp, SYMBOL_SIZE
.error_no_stack:
    pop     rsi
    pop     rbx
    epilogue

;*
; * [parser_gas_name]
; * Purpose: A name a GNU directive gives (".set .Lx, 4", ".type f, ...")
; *   as utasm keeps it: ".x" under the last global label, as a ".x:"
; *   label is, others as they are.
; * Input  : RBX = PrepState, RSI = name
; * Output : RSI = the name kept
; * Clobbers: rax, rcx, rdx, rdi, r8-r11
; ;
global parser_gas_name
parser_gas_name:
    cmp     byte [rsi], '.'
    jne     .ret
    cmp     byte [rsi + 1], '.'
    je      .ret
    push    r14
    mov     rax, [rbx + PREP_ctx]
    mov     r14, [rax + ASMCTX_last_global]
    test    r14, r14
    jz      .keep
    mov     rdi, rax
    call    parser_concat_local_name
    test    rax, rax
    jnz     .keep
    mov     rsi, rdx
.keep:
    pop     r14
.ret:
    ret

;*
; * [parser_gas_equ]
; * Purpose: GNU's ".equ NAME, EXPR" (".set", ".equiv"): NAME defined as
; *   "NAME equ EXPR" defines it, the expression read from here.
; * Input  : RBX = PrepState, RSI = name (as parser_gas_name gives it)
; * Output : RAX = OK or an error
; ;
global parser_gas_equ
parser_gas_equ:
    mov     byte [rel equ_again], 0
    call    parser_define_label
    test    rax, rax
    jnz     .ret
    mov     rdi, rbx
    call    parser_handle_equ
.ret:
    ret

;*
; * [parser_concat_local_name]
; * Input: R14 = global name, RSI = local name
; * Output: RDX = concatenated name in arena
; * In GNU's syntax (.intel_syntax, .att_syntax, --att) a "." name is a
; * name of its own, as GNU as has it (.L3, .LC0 - GCC's), not local to the
; * label before it: RDX = RSI.
; ;
parser_concat_local_name:
    extern  gas_names
    cmp     byte [rel gas_names], 0
    je      .nasm_local
    mov     rdx, rsi
    xor     eax, eax
    ret
.nasm_local:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    
    mov     r12, r14               ; r12 = global name
    mov     r13, rsi               ; r13 = local name
    
    ; 1. Calculate lengths
    mov     rdi, r12
    extern  str_len
    call    str_len
    mov     r14, rax               ; r14 = len(global)
    
    mov     rdi, r13
    call    str_len
    add     rax, r14               ; rax = len(global) + len(local)
    inc     rax                    ; +1 for null terminator
    
    ; 2. Allocate buffer from arena
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, rax
    extern  arena_alloc
    call    arena_alloc
    check_err_to .error
    mov     r10, rdx               ; r10 = allocated buffer ptr
    
    ; 3. Copy global name to buffer
    mov     rdi, r10
    mov     rsi, r12
    mov     rcx, r14
    rep     movsb
    
    ; 4. Copy local name (including null terminator)
    mov     rsi, r13
.copy_local:
    lodsb
    stosb
    test    al, al
    jnz     .copy_local
    
    mov     rdx, r10               ; rdx = concatenated string pointer
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

.error:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
