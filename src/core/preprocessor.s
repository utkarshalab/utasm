;
; ============================================
; File     : src/core/preprocessor.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

DEFAULT REL

extern error_new_from_errno
extern symbol_add
extern str_len
extern arena_alloc
extern lexer_next
extern lexer_peek
extern lexer_init
extern io_open
extern io_file_size
extern io_mmap
extern io_close
extern str_cmp
extern str_to_int
extern symbol_find

; ============================================================================
; PREPROCESSOR
; ============================================================================
; Processes assembler directives and manages the token stream.
; Handles file inclusions, macro expansions, and conditional assembly.
;
; All functions return error codes in rax and results in rdx.
; Follows standard utasm calling convention (AMD64).
; ============================================================================

[SECTION .text]

; ---- prep_init --------------------------
;
; prep_init
; Initialises the preprocessor state.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to initial LexerState
;             rdx = pointer to AsmCtx
;             rcx = pointer to Arena
; Output   : rax = EXIT_OK
; Clobbers : none
;
global prep_init
prep_init:
    mov     byte [rdi + PREP_tag], TAG_PREPROCESSOR
    mov     byte [rdi + PREP_depth], 0
    mov     byte [rdi + PREP_skip_depth], 0
    mov     byte [rdi + PREP_has_peek], FALSE
    mov     byte [rdi + PREP_mac_depth], 0 ; (A83)
    mov     [rdi + PREP_lexer], rsi
    mov     [rdi + PREP_ctx], rdx
    mov     [rdi + PREP_arena], rcx
    xor     rax, rax
    ret

global preprocessor_next_token
preprocessor_next_token:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Handle peek slot
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_peek
    
    ; Return peek token
    mov     byte [rbx + PREP_has_peek], FALSE
    lea     rdx, [rbx + PREP_peek]
    xor     rax, rax
    jmp     .done
    
.no_peek:
    ; 2. Allocate token in arena for the result
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = pointer to new token

    mov     rdi, rbx
    mov     rsi, r12
    call    prep_internal_next
    test    rax, rax
    jnz     .error
    
    mov     rdx, r12
.done:
    pop     rcx                    ; Alignment padding
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.error:
    xor     rdx, rdx
    jmp     .done


global preprocessor_putback_token
preprocessor_putback_token:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rdi = PrepState
    mov     r12, rsi               ; rsi = TOKEN*
    
    ; Copy token into peek slot
    lea     rdi, [rbx + PREP_peek]
    mov     rsi, r12
    mov     rcx, TOKEN_SIZE
    rep     movsb
    
    mov     byte [rbx + PREP_has_peek], TRUE
    
    pop     r12
    pop     rbx
    epilogue

; ---- preprocessor_peek_token ------------
global preprocessor_peek_token
preprocessor_peek_token:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi
    
    cmp     byte [rbx + PREP_has_peek], TRUE
    je      .done
    
    ; Allocate token in arena
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_internal_next
    test    rax, rax
    jnz     .error

    
    ; Success - token in r12
    mov     byte [rbx + PREP_has_peek], TRUE
    ; copy r12 to peek slot
    mov     rdi, r12
    lea     rsi, [rbx + PREP_peek]
    mov     rcx, TOKEN_SIZE
    rep movsb
    
.done:
    lea     rdx, [rbx + PREP_peek]
    xor     rax, rax
.exit:
    pop     rcx                    ; Alignment padding
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.error:
    xor     rdx, rdx
    jmp     .exit



; ---- prep_internal_next -----------------
prep_internal_next:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token dest

.next:
    ; 1. Check if we are expanding a macro
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .from_lexer

    ; Get token from expansion body
    call    prep_expand_next
    test    rax, rax
    jz      .done                  ; expansion produced a token
    ; if expansion finished, try again (checks for parent or falls to lexer)
    jmp     .next

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; lexer error

    ; check if it's a macro call
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_macro_call
    
    ; look up in symtab
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .not_macro_call        ; not found or error
    
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_macro_call
    
    ; Found a macro call!
    mov     rdi, rbx
    mov     rsi, [rdx + SYMBOL_value] ; rsi = pointer to MACRO struct
    call    prep_expand_start
    test    rax, rax
    jnz     .done                  ; error starting expansion
    jmp     .next                  ; get first token of expansion

.not_macro_call:
    ; handle EOF
    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .handle_eof

    ; check if skipping
    cmp     byte [rbx + PREP_skip_depth], 0
    je      .not_skipping

    ; we are skipping. only care about % directives
    cmp     byte [r12 + TOKEN_kind], TOK_PERCENT
    jne     .next                  ; consume everything else

    ; handle directive even when skipping
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_handle_directive
    jmp     .next

.not_skipping:
    cmp     byte [r12 + TOKEN_kind], TOK_PERCENT
    je      .is_directive
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    je      .is_directive
    jmp     .done                  ; normal token

.is_directive:
    ; it's a directive. handle it.
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_handle_directive
    test    rax, rax
    jnz     .done                  ; error handling directive

    ; if the directive didn't produce a token, get next
    jmp     .next

.handle_eof:
    ; check if we have a parent include context
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    test    r9, r9
    jz      .done                  ; real EOF (main file)

    ; 1. Unmap the current file buffer
    mov     rdi, [r9 + INCLUDECTX_buf]
    mov     rsi, [r9 + INCLUDECTX_size]
    extern  io_munmap
    call    io_munmap
    
    ; 2. Restore previous lexer
    mov     r10, [r9 + INCLUDECTX_lexer]
    mov     [rbx + PREP_lexer], r10
    
    ; 3. Pop include context
    mov     r11, [r9 + INCLUDECTX_parent]
    mov     [r8 + ASMCTX_inc_ctx], r11
    
    ; 4. Try getting next token from parent
    jmp     .next

.done:
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_expand_start ------------------
;
; prep_expand_start
; Starts expanding a macro.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to MACRO struct
; Output   : rax = EXIT_OK or error code
;
prep_expand_start:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = MACRO struct

    ; 0. Check recursion depth (A99)
    inc     byte [rbx + PREP_mac_depth]
    cmp     byte [rbx + PREP_mac_depth], MAX_MACRO_DEPTH
    jle     .depth_ok
    
    mov rax, EXIT_MACRO_RECURSION
    jmp .error

.depth_ok:
    ; Increment global expansion ID (A70)
    mov     r8, [rbx + PREP_ctx]
    inc     dword [r8 + ASMCTX_mac_exp_id]

    ; 1. Allocate MACROEXP struct
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACROEXP_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r13, rdx               ; r13 = MACROEXP struct

    mov     byte [r13 + MACROEXP_tag], TAG_MACRO_EXP
    mov     [r13 + MACROEXP_macro], r12
    mov     qword [r13 + MACROEXP_rep_count], 1 ; Default: expand once
    ; Check arity
    movzx   rax, byte [r12 + MACRO_min_params]
    movzx   rdx, byte [r12 + MACRO_max_params]
    
    ; Allocate space for up to MAX_PARAMS (let's say 32)
    ; For now, we'll allocate based on max_params if not variadic, 
    ; or a fixed buffer if variadic.
    mov     r14, 32                ; max potential params for variadic
    cmp     dl, 0xFF
    je      .alloc_params
    movzx   r14, dl
    
.alloc_params:
    mov     rsi, r14
    imul    rsi, 8
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx               ; r14 = param array
    
    xor     r15, r15               ; current param index
.param_loop:
    ; Check if we reached max
    movzx   rax, byte [r12 + MACRO_max_params]
    IF al, ne, 0xFF
        cmp r15b, al
        jge .check_trailing
        ELSE
        ; Variadic limit (hardcoded to 32 slots in allocation)
        IF r15, ge, 32
            mov rax, EXIT_MACRO_ARITY_FAIL
            jmp .error
            ENDIF
            ENDIF
    
    ; Peek to see if we have more arguments (comma or not)
    ; Actually, we should lex and if it's a newline, we stop.
    ; If it's a comma, we continue.
    
    ; For the first param, we don't need a comma.
    test    r15, r15
    jz      .parse_param_value
    
    ; consume comma
    sub     rsp, TOKEN_SIZE
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    IF byte [rsp + TOKEN_kind], ne, TOK_COMMA
        ; No more params? Check if we met min
        add     rsp, TOKEN_SIZE
        movzx   rax, byte [r12 + MACRO_min_params]
        cmp     r15b, al
        jl      .error_too_few_args
        jmp     .done_params
        ENDIF
    add     rsp, TOKEN_SIZE

.get_param:
    ; Check if this is the LAST parameter of a variadic macro
    movzx   rax, byte [r12 + MACRO_max_params]
    IF al, e, 0xFF
        ; If we are at min_params - 1? No, usually variadic is just the last one.
        ; Let's say if we are at index (min_params - 1), we capture everything else.
        movzx   rcx, byte [r12 + MACRO_min_params]
        dec     rcx
        IF r15, e, rcx
            call    prep_capture_greedy
            jmp     .done_params
            ENDIF
            ENDIF

.parse_param_value:
    ; allocate token for param
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     [r14 + r15 * 8], rdx
    
    ; lex into it
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rdx
    call    lexer_next
    test    rax, rax
    jnz     .error
    
    ; Guard: check if we hit newline/EOF unexpectedly
    mov     al, [rdx + TOKEN_kind]
    cmp     al, TOK_NEWLINE
    je      .check_min_params
    cmp     al, TOK_EOF
    je      .check_min_params
    
    inc     r15
    jmp     .param_loop

.check_min_params:
    movzx   rax, byte [r12 + MACRO_min_params]
    cmp     r15b, al
    jl      .error_too_few_args
    jmp     .done_params

.check_trailing:
    ; Check for too many arguments (is there a comma next?)
    mov     rdi, [rbx + PREP_lexer]
    extern  lexer_peek
    sub     rsp, 16                ; 16-byte alignment (TOKEN_SIZE is handled separately)
    mov     rsi, rsp
    call    lexer_peek
    mov     al, [rsp + TOKEN_kind]
    add     rsp, 16
    cmp     al, TOK_COMMA
    je      .error_too_many_args
    jmp     .done_params

.error_too_few_args:
.error_too_many_args:
    mov     rax, EXIT_MACRO_ARITY_FAIL
    jmp     .error

.done_params:
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    mov     [rax + MACROEXP_nparams], r15b
    
    ; 3. Link to previous
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    mov     [r13 + MACROEXP_parent], r9
    mov     [r8 + ASMCTX_mac_exp], r13
    
    xor     rax, rax
    mov     rdx, r13               ; Return expansion struct in RDX (A99)
    jmp     .done

.error_pop_token:
    add     rsp, TOKEN_SIZE
    jmp     .error

.error_expected_comma:
    add     rsp, TOKEN_SIZE
    mov     rax, EXIT_INVALID_OPERAND
    jmp     .done

.done:
    pop     rcx                    ; Alignment padding
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.error:
    jmp     .done

; ---- prep_expand_next -------------------
;
; prep_expand_next
; Serves the next token from the current macro expansion.
; Handles parameter substitution.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (destination)
; Output   : rax = 0 (produced token) or non-zero (finished)
;
prep_expand_next:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token dest

    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp] ; r13 = current expansion
    test    r13, r13
    jz      .finished

    ; 1. Get current token index
    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .expansion_end

    ; 2. Copy token from macro body
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = source token

    ; copy to dest
    mov     rdi, r12
    mov     rsi, r10
    mov     rcx, (TOKEN_SIZE / 8)
    rep movsq

    ; increment body pos
    inc     qword [r13 + MACROEXP_body]

    ; 2.5 Handle Stringification (#) (A67)
    cmp     byte [r12 + TOKEN_kind], TOK_HASH
    jne     .not_hash
        ; Peek at NEXT token in macro body
        mov     rax, [r13 + MACROEXP_body]
        mov     r9, [r13 + MACROEXP_macro]
        cmp     eax, [r9 + MACRO_ntokens]
        jge     .produced              ; Nothing after #
        
        mov     r10, [r9 + MACRO_tokens]
        imul    rax, TOKEN_SIZE
        add     r10, rax               ; r10 = potential parameter ref
        
        cmp     byte [r10 + TOKEN_kind], TOK_DIRECTIVE
        jne     .not_hash
            ; Check if it's %1-%9
            mov     rdi, [r10 + TOKEN_value]
            movzx   rax, byte [rdi]
            sub     al, '0'
            cmp     al, 1
            jl      .not_hash
            cmp     al, 9
            jg      .not_hash
                ; Yes, it's stringification!
                ; 1. Consume the directive token
                inc     qword [r13 + MACROEXP_body]
                
                ; 2. Get the parameter token
                dec     al
                movzx   rax, al
                mov     r11, [r13 + MACROEXP_params]
                mov     rsi, [r11 + rax * 8]   ; rsi = param token
                
                ; 3. Stringify it (Create a TOK_STRING)
                mov     byte [r12 + TOKEN_kind], TOK_STRING
                
                ; Use TOKEN_value or name string? 
                ; For TOK_IDENT, use value. For others, we need a helper.
                ; Simple implementation: use the value directly if it's already a string.
                mov     rax, [rsi + TOKEN_value]
                mov     [r12 + TOKEN_value], rax
                
                jmp     .produced
.not_hash:

    ; 3. Handle parameter substitution
    ; Macro parameters are TOK_DIRECTIVE with value like "0", "1", "2"...
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .produced

    mov     rdi, [r12 + TOKEN_value]
    movzx   rax, byte [rdi]
    
    ; CASE 1: %0 (Parameter Count)
    cmp     al, '0'
    jne     .not_case1
        ; Allocate space for the number string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .expansion_end ; or other error
        
        mov     rdi, rdx       ; dst
        movzx   rsi, byte [r13 + MACROEXP_nparams]
        extern  str_int_to_str
        call    str_int_to_str
        
        mov     byte [r12 + TOKEN_kind], TOK_NUMBER
        mov     [r12 + TOKEN_value], rdx ; pointer to formatted string
        jmp     .produced
.not_case1:

    ; CASE 2: %1-%9 (Parameter Reference)
    sub     al, '0'
    cmp     al, 1
    jl      .not_case2
    cmp     al, 9
    jg      .not_case2
        ; it's a param ref! (1-9)
        ; check if it is within nparams
        movzx   rcx, byte [r13 + MACROEXP_nparams]
        cmp     al, cl
        jg      .produced              ; out of range, keep as directive
        
        ; replace r12 with the parameter token
        dec     al                     ; 0-indexed
        mov     r11, [r13 + MACROEXP_params]
        movzx   rax, al
        mov     rsi, [r11 + rax * 8]   ; rsi = param token
        
        mov     rdi, r12
        mov     rcx, (TOKEN_SIZE / 8)
        rep movsq
        jmp     .produced
.not_case2:

    ; CASE 3: Variadic Expansion %{n..} (A69)
    cmp     byte [rdi], '{'
    jne     .not_case3
        ; parse braced parameter ref like "{1..}"
        inc     rdi                    ; skip {
        
        ; simple parser for digit
        movzx   rax, byte [rdi]
        sub     al, '0'
        cmp     al, 1
        jl      .not_case3
        cmp     al, 9
        jg      .not_case3
            ; r14 = starting index (1-based)
            movzx   r14, al
            
            ; check for ".." suffix
            cmp     byte [rdi + 1], '.'
            jne     .not_case3
            cmp     byte [rdi + 2], '.'
            jne     .not_case3
                ; It's %{n..}!
                ; We need to expand all params from r14 to nparams.
                ; This is complex for a single prep_expand_next call 
                ; because it returns one token.
                ; For now, we'll implement it by expanding the FIRST 
                ; param in the range and setting a flag to expand 
                ; the rest in subsequent calls? 
                
                ; Better: if nparams > r14, we expand r14 and then 
                ; we'd need to inject commas.
                ; To keep it simple for now, we'll support %{n..} as a 
                ; way to get ALL arguments from n onwards as a single 
                ; space-separated sequence if captured greedy.
                
                ; If the parameter was captured via prep_capture_greedy, 
                ; it is ALREADY a single string.
                movzx   rcx, byte [r13 + MACROEXP_nparams]
                cmp     r14b, cl
                jg      .produced      ; Out of range
                
                dec     r14b           ; 0-indexed
                mov     r11, [r13 + MACROEXP_params]
                movzx   rax, r14b
                mov     rsi, [r11 + rax * 8]
                
                mov     rdi, r12
                mov     rcx, (TOKEN_SIZE / 8)
                rep movsq
                jmp     .produced
.not_case3:

    ; CASE 4: Macro Local Label %% (A70)
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    jne     .not_case4
        ; Expand to ..@ID_label
        mov     r8, [rbx + PREP_ctx]
        mov     r14d, dword [r8 + ASMCTX_mac_exp_id]
        
        ; 1. Allocate buffer for ID string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, 32
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r15, rdx               ; r15 = ID string buffer
        
        mov     rdi, r15
        mov     rsi, r14               ; value
        extern  str_int_to_str
        call    str_int_to_str
        
        ; 2. Allocate final label buffer
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, MAX_TOKEN
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r14, rdx               ; r14 = final label buffer
        
        ; 3. Construct "..@ID_label"
        mov     byte [r14], '.'
        mov     byte [r14+1], '.'
        mov     byte [r14+2], '@'
        
        mov     rdi, r14
        add     rdi, 3                 ; skip "..@"
        mov     rsi, r15               ; ID string
        mov     rdx, [r12 + TOKEN_value] ; original label name
        extern  str_concat
        call    str_concat
        
        ; Update token
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], r14
        jmp     .produced
.not_case4:

.produced:
    ; ---- A68: Token Concatenation (##) ----
.check_concat:
    mov     r8, [rbx + PREP_ctx]
    mov     r13, [r8 + ASMCTX_mac_exp]
    test    r13, r13
    jz      .done_concat

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .done_concat
    
    ; Peek at next token
    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax               ; r10 = next token in body
    
    IF byte [r10 + TOKEN_kind], e, TOK_CONCAT
        ; 1. Consume ##
        inc     qword [r13 + MACROEXP_body]
        
        ; 2. Get the NEXT operand (A ## B)
        ; We need to produce the next token into a temp buffer
        sub     rsp, TOKEN_SIZE
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_expand_next
        IF rax, ne, 0
            ; Error or expansion end (unexpected)
            add     rsp, TOKEN_SIZE
            jmp     .done_concat
            ENDIF
        
        ; 3. Concatenate r12 (merged so far) and rsp (next token)
        ; Allocate space for combined string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, MAX_TOKEN
        extern  arena_alloc
        call    arena_alloc
        test    rax, rax
        jnz     .done_concat           ; OOM or error
        
        mov     r14, rdx               ; r14 = concat buffer
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value]
        mov     rdx, [rsp + TOKEN_value]
        extern  str_concat
        call    str_concat
        
        ; 4. Update r12 to be the merged IDENT
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     [r12 + TOKEN_value], r14
        
        add     rsp, TOKEN_SIZE
        jmp     .check_concat          ; Chain: allow A ## B ## C
        ENDIF

.done_concat:
    xor     rax, rax
    jmp     .done

.expansion_end:
    ; Check for %rep loop
    cmp     dword [r13 + MACROEXP_rep_count], 1
    jle     .do_pop
    
    dec     dword [r13 + MACROEXP_rep_count]
    mov     qword [r13 + MACROEXP_body], 0
    mov     rax, 1                 ; try again (retry expansion from start of loop)
    jmp     .done

.do_pop:
    call    prep_expand_pop
    ; we finished this expansion, but there might be a parent
    ; we return non-zero to tell caller to try again (which will check mac_exp again)
    mov     rax, 1
    jmp     .done

.finished:
    mov     rax, 1

.done:
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

global prep_expand_pop
prep_expand_pop:
    prologue
    push    rbx
    push    r12                    ; Alignment padding
    mov     rbx, rdi
    
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .done
    
    ; Decrease depth
    dec     byte [rbx + PREP_mac_depth]
    
    ; Pop from expansion stack
    mov     rax, [r9 + MACROEXP_parent]
    mov     [r8 + ASMCTX_mac_exp], rax
    
.done:
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_handle_directive --------------
;
; prep_handle_directive
; Processes a directive starting with %.
; Input    : rdi = pointer to PrepState
;             rsi = pointer to % Token
; Output   : rax = EXIT_OK or error code
; Clobbers : ...
;
prep_handle_directive:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14                    ; r14 = stack cleanup flag
    mov     r14, 0                 ; initialize flag early
    mov     rbx, rdi               ; rbx = PrepState
    mov     r13, rsi               ; r13 = the token triggering the directive (% or %name)
    
    ; check if we already have the identifier
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    je      .have_ident
    
    ; next token should be the directive identifier
    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, TOKEN_SIZE        ; space for temp token
    mov     r14, 1                 ; stack cleanup flag: YES
    mov     r12, rsp               ; r12 = temp token dest
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error_pop_rsp

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .expected_ident_pop_rsp
    
    jmp     .start_match

.have_ident:
    mov     r12, r13               ; use the directive token as the ident token
    mov     r14, 0                 ; stack cleanup flag: NO

.start_match:
    ; check which directive it is
    mov     rdi, [r12 + TOKEN_value] ; directive name
    lea     rsi, [dir_inc]
    call    str_cmp
    test    rax, rax
    jz      .do_inc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_def]
    call    str_cmp
    test    rax, rax
    jz      .do_def

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_if]
    call    str_cmp
    test    rax, rax
    jz      .do_if

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifdef]
    call    str_cmp
    test    rax, rax
    jz      .do_ifdef

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifndef]
    call    str_cmp
    test    rax, rax
    jz      .do_ifndef

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_else]
    call    str_cmp
    test    rax, rax
    jz      .do_else

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endif]
    call    str_cmp
    test    rax, rax
    jz      .do_endif

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .do_macro

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_struc]
    call    str_cmp
    test    rax, rax
    jz      .do_struc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .do_rep

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .do_endrep

    xor     rax, rax
    jmp     .done_cleanup

.do_struc:
    ; TODO: implement %struc
    ; call prep_handle_struc
    jmp     .done_cleanup

.do_inc:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_inc
    jmp     .done_cleanup

.do_def:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_if:
    mov     rdi, rbx
    call    prep_handle_if
    jmp     .done_cleanup

.do_ifdef:
    mov     rdi, rbx
    call    prep_handle_ifdef
    jmp     .done_cleanup

.do_ifndef:
    mov     rdi, rbx
    call    prep_handle_ifndef
    jmp     .done_cleanup

.do_else:
    mov     rdi, rbx
    call    prep_handle_else
    jmp     .done_cleanup

.do_endif:
    mov     rdi, rbx
    call    prep_handle_endif
    jmp     .done_cleanup

.do_macro:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    macro_handle_def
    jmp     .done_cleanup

.do_rep:
    mov     rdi, rbx
    call    prep_handle_rep
    jmp     .done_cleanup

.do_endrep:
    mov     rax, EXIT_ERROR
    jmp     .done_cleanup

.error_pop_rsp:
    mov     rax, EXIT_ERROR
    jmp     .done_cleanup

.expected_ident_pop_rsp:
    mov     rax, EXIT_ERROR
    jmp     .done_cleanup

.done_cleanup:
    test    r14, r14
    jz      .done
    add     rsp, TOKEN_SIZE

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

; ---- prep_handle_inc --------------------
;
; prep_handle_inc
; Handles the %include directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_inc:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi

    ; Allocate stack space for:
    ; [rsp + 0]  : temporary TOKEN (32 bytes)
    ; [rsp + 32] : new_lexer pointer (8 bytes)
    ; [rsp + 40] : saved depth (8 bytes)
    sub     rsp, 64                ; 32 (token) + 8 (IncludeCtx) + 8 (new_lexer) + 8 (depth) + 8 (padding) = 64
    
    ; 1. Get filename token
    mov     rdi, [rbx + PREP_lexer]
    lea     r12, [rsp]             ; r12 = temporary token buffer
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    jne     .error_expected_string
    
    mov     r12, [r12 + TOKEN_value] ; r12 = filename string

    ; 2. Check include depth
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    xor     r14, r14               ; r14 = depth
    test    r9, r9
    jz      .depth_ok
    movzx   r14, byte [r9 + INCLUDECTX_depth]
    inc     r14
    cmp     r14, MAX_INCLUDES
    jge     .error_too_deep
.depth_ok:
    mov     [rsp + 56], r14         ; save depth at [rsp+56]

    ; 3. Open file

    mov     rdi, r12
    xor     rsi, rsi               ; rsi = O_RDONLY (0)
    call    io_open


    test    rax, rax
    jnz     .error_open
    mov     r13, rdx               ; r13 = fd

    ; 4. Get file size
    mov     rdi, r13
    call    io_file_size
    test    rax, rax
    jnz     .error_size
    mov     r14, rdx               ; r14 = size

    ; 5. Map file into memory
    xor     rdi, rdi               ; addr = NULL
    mov     rsi, r14               ; length
    mov     rdx, PROT_READ         ; prot
    mov     rcx, MAP_PRIVATE       ; flags
    mov     r8, r13                ; fd
    xor     r9, r9                 ; offset = 0
    call    io_mmap
    test    rax, rax
    jnz     .error_mmap
    mov     r15, rdx               ; r15 = buffer

    ; 6. Create new LexerState
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEXER_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error_oom
    mov     rcx, rdx                ; rcx = new lexer (using rcx temp)

    ; initialize new lexer
    ; We need to save new_lexer somewhere safe while calling lexer_init
    ; Let's use the 16-byte aligned stack space we already have
    mov     [rsp + 48], rcx         ; save new_lexer at [rsp+48]
    
    mov     rdi, rcx
    mov     rsi, r15               ; buf
    mov     rdx, r14               ; size
    mov     r11, r12               ; filename string (save to r11)
    mov     rcx, r11
    mov     r8, [rbx + PREP_ctx]   ; r8 = AsmCtx
    mov     r9, [rbx + PREP_arena] ; r9 = Arena
    call    lexer_init
    test    rax, rax
    jnz     .error_open            ; check for init failure

    ; 7. Save state in IncludeCtx
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, INCLUDECTX_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error_oom
    mov     r9, rdx                ; r9 = new IncludeCtx
    mov     [rsp + 40], r9         ; save IncludeCtx ptr at [rsp+40]

    mov     byte [r9 + INCLUDECTX_tag], TAG_INCLUDE_CTX
    
    mov     r10, [rbx + PREP_ctx]
    mov     r11, [r10 + ASMCTX_inc_ctx]
    mov     [r9 + INCLUDECTX_parent], r11 ; link to previous
    mov     [r10 + ASMCTX_inc_ctx], r9    ; update current in AsmCtx
    
    mov     [r9 + INCLUDECTX_buf], r15
    mov     [r9 + INCLUDECTX_size], r14
    
    mov     r9, [rsp + 40]         ; restore IncludeCtx ptr
    
    mov     rax, [rbx + PREP_lexer]
    mov     [r9 + INCLUDECTX_lexer], rax
    movzx   rax, byte [rsp + 56]   ; depth
    mov     byte [r9 + INCLUDECTX_depth], al
    
    mov     r8, [rsp + 48]         ; restore new_lexer
    mov     [rbx + PREP_lexer], r8 ; Switch to new lexer

    ; 8. Close the fd
    mov     rdi, r13
    call    io_close

    xor     rax, rax
    jmp     .done

.error_oom:
    mov     rax, EXIT_OOM
    jmp     .done

.error_expected_string:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_too_deep:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_open:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_size:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_mmap:
    mov     rax, EXIT_ERROR
    jmp     .done

.error:
    mov     rax, EXIT_ERROR
    jmp     .done

.done:
    add     rsp, 64                ; Clean up our stack frame
    pop     rcx                    ; Alignment padding
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret
    ret


[SECTION .rodata]
dir_inc:    db "include", 0
dir_def:    db "define", 0
dir_if:     db "if", 0
dir_ifdef:  db "ifdef", 0
dir_ifndef: db "ifndef", 0
dir_else:   db "else", 0
dir_endif:  db "endif", 0
dir_rep:    db "rep", 0
dir_endrep: db "endrep", 0
dir_macro:  db "macro", 0
dir_endm:   db "endmacro", 0
dir_struc:  db "struc", 0
dir_endstruc: db "endstruc", 0

msg_preprocessor_dir_trace: db "[+] PREP: Directive: ", 0
msg_newline:                db 10, 0
[SECTION .data]

; ---- prep_handle_struc ------------------
;
[SECTION .text]
; prep_handle_struc
    push    rbx
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Lex the struct name
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    
    ; 2. Dispatch to parser
    mov     rdi, rbx               ; rdi = PrepState
    mov     rsi, rdx               ; rsi = Name Token
    extern  parser_parse_struc
    call    parser_parse_struc
    
.error:
    pop     rbx
    ret
; ---- prep_handle_def --------------------
;
; prep_handle_def
; Handles the %define directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_def:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi               ; rbx = PrepState
    
    ; 112 is a multiple of 16. Perfect.
    sub     rsp, (TOKEN_SIZE * 2) + SYMBOL_SIZE
    
    ; 1. Lex the identifier (the constant name)
    mov     rdi, [rbx + PREP_lexer]
    lea     r12, [rsp]             ; r12 = name token buffer
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .expected_ident

    ; Save the name pointer
    mov     r13, [r12 + TOKEN_value]

    ; 2. Lex the value
    mov     rdi, [rbx + PREP_lexer]
    lea     r12, [rsp + TOKEN_SIZE] ; r12 = value token buffer
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    ; 3. Create a symbol entry
    lea     rdi, [rsp + (TOKEN_SIZE * 2)] ; rdi = temp Symbol dest
    
    ; zero out the struct
    mov     rcx, 6                 ; 48 / 8 = 6
    xor     rax, rax
    mov     r10, rdi               ; save rdi
    rep stosq
    mov     rdi, r10               ; restore rdi

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     [rdi + SYMBOL_name], r13
    
    mov     r14, rdi               ; save symbol ptr
    ; handle value
    cmp     byte [r12 + TOKEN_kind], TOK_NUMBER
    jne     .finish_def            ; for now, ignore non-numeric %def

    mov     rdi, [r12 + TOKEN_value]
    call    str_to_int             ; from string.s
    mov     rdi, r14
    mov     [rdi + SYMBOL_value], rdx

.finish_def:
    mov     rdi, [rbx + PREP_ctx]  ; rdi = AsmCtx
    mov     rsi, rdi               ; (wait, rsi should be symbol ptr)
    mov     rsi, r14               ; rsi = pointer to temp Symbol on stack
    call    symbol_add
    test    rax, rax
    jnz     .error

    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_ERROR
.done:
    add     rsp, (TOKEN_SIZE * 2) + SYMBOL_SIZE
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

.expected_ident:
    mov     rax, EXIT_ERROR
    jmp     .done

;*
; * [prep_capture_greedy]
; ;
prep_capture_greedy:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r15, rsi               ; r15 = param index
    mov     r12, [rbx + PREP_lexer]
    
    ; 1. Find the end of the line in the current lexer buffer
    mov     r13, [r12 + LEXER_pos] ; start
    mov     r14, r13               ; current
.find_eol:
    cmp     r14, [r12 + LEXER_end]
    jge     .found_eol
    movzx   rax, byte [r14]
    cmp     al, 10                 ; LF
    je      .found_eol
    inc     r14
    jmp     .find_eol

.found_eol:
    ; length = r14 - r13
    mov     rdx, r14
    sub     rdx, r13               ; rdx = length
    
    ; 2. Allocate and copy
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, rdx
    inc     rsi                    ; +1 for null
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r10, rdx               ; r10 = dst
    
    mov     rdi, r10
    mov     rsi, r13
    mov     rdx, r14
    sub     rdx, r13               ; length
    mov     rcx, rdx
    rep     movsb
    mov     byte [rdi], 0          ; null terminate
    
    ; 3. Update lexer position (consume the text, but not the newline)
    mov     [r12 + LEXER_pos], r14
    
    ; 4. Create string token
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     byte [rdx + TOKEN_kind], TOK_STRING
    mov     [rdx + TOKEN_value], r10
    
    ; 5. Store in macro params
    mov     rax, [rbx + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .error
    
    mov     rcx, [rax + MACROEXP_params]
    mov     [rcx + r15 * 8], rdx
    
    xor     rax, rax
    jmp     .done

.error:
    mov     rax, EXIT_ERROR
    
.done:
    pop     rcx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret


; ---- prep_handle_if ---------------------
;
; prep_handle_if
; Handles the %if directive by evaluating a mathematical expression.
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_if:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. If we are already skipping, just increment depth
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .already_skipping

    ; 2. Evaluate expression
    mov     rdi, [rbx + PREP_ctx]
    extern  parser_evaluate_expression
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .done
    
    ; 3. Evaluate boolean result
    test    rdx, rdx
    jnz     .condition_true

    ; 4. Condition false, begin skipping
    inc     byte [rbx + PREP_skip_depth]
    inc     byte [rbx + PREP_depth]
    xor     rax, rax
    jmp     .done

.condition_true:
    inc     byte [rbx + PREP_depth]
    xor     rax, rax
    jmp     .done

.already_skipping:
    inc     byte [rbx + PREP_skip_depth]
    inc     byte [rbx + PREP_depth]
    xor     rax, rax

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_ifdef ------------------
;
; prep_handle_ifdef
; Handles the %ifdef directive.
;
prep_handle_ifdef:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    ; increment total depth
    inc     byte [rbx + PREP_depth]

    ; if already skipping, just increment skip depth and return
    cmp     byte [rbx + PREP_skip_depth], 0
    jz      .ifdef_not_skipping
    inc     byte [rbx + PREP_skip_depth]
    jmp     .done_no_pop
.ifdef_not_skipping:

    ; next token must be an identifier
    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, TOKEN_SIZE
    mov     r12, rsp
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .expected_ident

    ; check if symbol exists
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jz      .done                  ; found (0) -> condition true -> don't skip
    
    ; not found -> start skipping
    inc     byte [rbx + PREP_skip_depth]

.done:
    add     rsp, TOKEN_SIZE
.done_no_pop:
    xor     rax, rax
    pop     r12
    pop     rbx
    epilogue

.error:
.expected_ident:
    mov     rax, EXIT_ERROR
    jmp     .done

; ---- prep_handle_ifndef -----------------
prep_handle_ifndef:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    inc     byte [rbx + PREP_depth]

    ; if already skipping, just increment skip depth and return
    cmp     byte [rbx + PREP_skip_depth], 0
    jz      .ifndef_not_skipping
    inc     byte [rbx + PREP_skip_depth]
    jmp     .done_no_pop
.ifndef_not_skipping:

    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, TOKEN_SIZE
    mov     r12, rsp
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .expected_ident

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .done                  ; not found (non-zero) -> condition true -> don't skip

    ; found -> start skipping (since it's ifndef)
    inc     byte [rbx + PREP_skip_depth]

.done:
    add     rsp, TOKEN_SIZE
.done_no_pop:
    xor     rax, rax
    pop     r12
    pop     rbx
    epilogue

.error:
.expected_ident:
    mov     rax, EXIT_ERROR
    jmp     .done

; ---- prep_handle_else -------------------
prep_handle_else:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     al, [rbx + PREP_depth]
    test    al, al
    jz      .error                 ; %else without %if

    ; 1. If we are currently skipping at THIS depth ONLY, we toggle.
    ; If skip_depth == 1, it means the current level is the only one skipping.
    ; If skip_depth > 1, an outer level is skipping, so %else doesn't matter.
    ; If skip_depth == 0, the current level was taken, so now we skip.
    
    mov     al, [rbx + PREP_skip_depth]
    cmp     al, 0
    je      .was_taken
    cmp     al, 1
    je      .was_skipped
    jmp     .done                  ; skip_depth > 1, keep skipping

.was_taken:
    inc     byte [rbx + PREP_skip_depth]
    jmp     .done

.was_skipped:
    dec     byte [rbx + PREP_skip_depth]

.done:
    xor     rax, rax
    pop     rbx
    epilogue

.error:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue

; ---- prep_handle_endif ------------------
prep_handle_endif:
    prologue
    push    rbx
    mov     rbx, rdi

    ; 1. If we are skipping, decrement skip depth
    cmp     byte [rbx + PREP_skip_depth], 0
    je      .not_skipping
    dec     byte [rbx + PREP_skip_depth]

.not_skipping:
    ; 2. Always decrement total depth
    dec     byte [rbx + PREP_depth]
    xor     rax, rax
    pop     rbx
    epilogue

.error_no_if:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue
; ---- macro_handle_def -------------------
;
; macro_handle_def
; Handles the %macro directive.
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
macro_handle_def:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    mov     rbx, rdi               ; rbx = PrepState

    ; Allocate: 3 Tokens = 96 bytes (Multiple of 16)
    sub     rsp, 96
    
    ; 1. Lex the macro name
    mov     rdi, [rbx + PREP_lexer]
    lea     r12, [rsp]             ; r12 = name token
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .error_expected_ident

    ; 2. Lex the parameter count
    mov     rdi, [rbx + PREP_lexer]
    lea     r13, [rsp + 32]        ; r13 = param count token
    mov     rsi, r13
    call    lexer_next
    test    rax, rax
    jnz     .error

    ; Param count can be N, N-M, or N-*
    xor     r14, r14               ; min_params
    xor     r15, r15               ; max_params
    
    cmp     byte [r13 + TOKEN_kind], TOK_NUMBER
    jne     .body_start            ; No params specified
    
    ; Parse minimum
    mov     rdi, [r13 + TOKEN_value]
    call    str_to_int
    mov     r14, rax
    mov     r15, rax               ; Default max = min
    
    ; Peek for hyphen '-'
    mov     rdi, [rbx + PREP_lexer]
    lea     rsi, [rsp + 64]
    call    lexer_peek
    cmp     byte [rsp + 64 + TOKEN_kind], TOK_MINUS
    jne     .no_hyphen
    
    ; Consume hyphen
    mov     rdi, [rbx + PREP_lexer]
    lea     rsi, [rsp + 64]
    call    lexer_next
    
    ; Lex next for max
    mov     rdi, [rbx + PREP_lexer]
    lea     rsi, [rsp + 64]
    call    lexer_next
    
    cmp     byte [rsp + 64 + TOKEN_kind], TOK_NUMBER
    jne     .check_star
    mov     rdi, [rsp + 64 + TOKEN_value]
    call    str_to_int
    mov     r15, rax
    jmp     .no_hyphen

.check_star:
    cmp     byte [rsp + 64 + TOKEN_kind], TOK_STAR
    jne     .no_hyphen
    mov     r15, 0xFF              ; Variadic

.no_hyphen:
    ; VALIDATION: Enforce max 32 parameters
    cmp     r14, 32
    jg      .error_macro_def
    
    cmp     r15, 0xFF
    je      .body_start
    cmp     r15, 32
    jg      .error_macro_def

.body_start:
    ; 3. Allocate MACRO struct in arena
    ; We need to save r14 (min) and r15 (max) while we use r15 for the struct pointer
    ; Let's use the stack or other registers.
    ; [rsp + 64] = min_params (8 bytes)
    ; [rsp + 72] = max_params (8 bytes)
    mov     [rsp + 64], r14
    mov     [rsp + 72], r15

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r15, rdx               ; r15 = pointer to MACRO struct

    mov     byte [r15 + MACRO_tag], TAG_MACRO
    mov     rax, [r12 + TOKEN_value]
    mov     [r15 + MACRO_name], rax
    
    mov     rax, [rsp + 64]
    mov     [r15 + MACRO_min_params], al
    mov     rax, [rsp + 72]
    mov     [r15 + MACRO_max_params], al

    ; 4. Capture tokens until %endmacro
    mov     rdi, [rbx + PREP_arena]
    mov     rax, [rdi + ARENA_ptr]
    mov     [r15 + MACRO_tokens], rax
    xor     r14, r14               ; r14 = token count
    mov     r13, 1                 ; r13 = nesting depth

.capture_loop:
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = current token slot

    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .error_eof

    ; Check for % directive
    cmp     byte [r12 + TOKEN_kind], TOK_PERCENT
    jne     .store_token

    ; It's a %. Peek next to check for nesting.
    ; (Allocating another token for peeking)
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r8, rdx                ; r8 = next token slot

    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r8
    call    lexer_next
    test    rax, rax
    jnz     .error

    cmp     byte [r8 + TOKEN_kind], TOK_IDENT
    jne     .store_percent_and_next

    ; Check for "macro" or "endmacro"
    mov     rdi, [r8 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in

    mov     rdi, [r8 + TOKEN_value]
    lea     rsi, [dir_endm]
    call    str_cmp
    test    rax, rax
    jz      .nest_out

.store_percent_and_next:
    inc     r14                    ; counted %
    inc     r14                    ; counted next token
    jmp     .capture_loop

.nest_in:
    inc     r13                    ; found nested %macro
    inc     r14
    inc     r14
    jmp     .capture_loop

.nest_out:
    dec     r13
    test    r13, r13
    jz      .found_endmacro        ; Outermost %endmacro found!
    
    inc     r14
    inc     r14
    jmp     .capture_loop

.store_token:
    inc     r14
    jmp     .capture_loop

.found_endmacro:
    mov     [r15 + MACRO_ntokens], r14d

    ; 5. Register in symbol table
    ; Use stack for temp symbol
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    
    ; zero out
    mov     rcx, 6
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_MACRO
    mov     rax, [r15 + MACRO_name]
    mov     [rdi + SYMBOL_name], rax
    mov     [rdi + SYMBOL_value], r15

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    test    rax, rax
    jnz     .error_add_sym
    
    add     rsp, SYMBOL_SIZE
    xor     rax, rax
    jmp     .done

.error_add_sym:
    add     rsp, SYMBOL_SIZE
.error:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_macro_def:
    mov     rax, EXIT_MACRO_DEF
    jmp     .done

.error_expected_ident:
    mov     rax, EXIT_ERROR
    jmp     .done

.error_eof:
    mov     rax, EXIT_ERROR
    jmp     .done

.done:
    add     rsp, 96                ; token buffers
    pop     rcx                    ; Alignment
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

;*
; * [prep_handle_rep]
; * Input: RDI = PrepState
; ;
prep_handle_rep:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax                    ; Alignment padding
    sub     rsp, 16                ; [rbp - 56]: total token count, [rbp - 64]: temp slot
    
    mov     rbx, rdi               ; rbx = PREP state

    ; 1. Get repeat count
    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, TOKEN_SIZE
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .error
    
    cmp     byte [rsp + TOKEN_kind], TOK_NUMBER
    jne     .error
    
    mov     rdi, [rsp + TOKEN_value]
    mov     rsi, [rsp + TOKEN_len]
    call    str_to_int
    mov     r14, rax               ; r14 = count
    add     rsp, TOKEN_SIZE        ; Clean up temp token

    ; 2. Allocate anonymous MACRO struct
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r15, rdx               ; r15 = Macro struct
    mov     byte [r15 + MACRO_tag], TAG_MACRO
    mov     qword [r15 + MACRO_name], 0
    mov     byte [r15 + MACRO_min_params], 0
    
    ; 3. Capture tokens until %endrep
    mov     qword [rbp - 56], 0    ; Total token count = 0
    xor     r13, r13               ; Nesting depth = 0

    ; Record where the body starts
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 0                 ; zero-size alloc to get current pointer
    call    arena_alloc
    mov     [r15 + MACRO_tokens], rdx

.capture:
    ; Check for EOF
    mov     rdi, [rbx + PREP_lexer]
    sub     rsp, 16                ; Alignment for peek
    mov     rsi, rsp
    call    lexer_peek
    mov     al, [rsp + TOKEN_kind]
    add     rsp, 16
    cmp     al, TOK_EOF
    je      .error_eof

    ; Allocate slot for token
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx               ; r12 = current token slot
    
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .error

    ; Is it a %?
    cmp     byte [r12 + TOKEN_kind], TOK_PERCENT
    jne     .store_token

    ; It's a %. Peek next to check for nesting.
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     [rbp - 64], rdx        ; Safe offset

    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, [rbp - 64]
    call    lexer_next
    test    rax, rax
    jnz     .error

    mov     rdx, [rbp - 64]        ; rdx = peeked token

    ; Check for "rep" or "endrep"
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store_percent_and_next

    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in

    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out

.store_percent_and_next:
    add     qword [rbp - 56], 2     ; counted % and next token
    jmp     .capture

.nest_in:
    inc     r13                    ; nesting++
    add     qword [rbp - 56], 2
    jmp     .capture

.nest_out:
    test    r13, r13
    jz      .captured              ; outermost %endrep found!
    
    dec     r13                    ; nesting--
    add     qword [rbp - 56], 2
    jmp     .capture

.store_token:
    inc     qword [rbp - 56]
    jmp     .capture

.captured:
    mov     rax, [rbp - 56]
    mov     [r15 + MACRO_ntokens], eax
    
    ; 4. Start expansion
    mov     rdi, rbx
    mov     rsi, r15
    call    prep_expand_start
    test    rax, rax
    jnz     .error
    mov     [rdx + MACROEXP_rep_count], r14 ; set repetition count
    
    xor     rax, rax               ; success
    jmp     .done

.error_eof:
.error:
    mov     rax, 1                 ; error
    jmp     .done

.done:
    add     rsp, 16                ; Clean up reserved space
    pop     rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret
