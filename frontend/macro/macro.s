;
; ============================================
; File     : src/core/preprocessor.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern error_new_from_errno
extern symbol_add
extern str_len
extern arena_alloc_string
extern str_int_to_str
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
extern print_str
extern print_num

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
global prep_internal_next
global prep_handle_directive
preprocessor_next_token:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    mov     rbx, rdi               ; rbx = PrepState

    ; 1. Handle peek slot
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_peek
    
    ; Stable allocation for the peeked token
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    
    mov     byte [rbx + PREP_has_peek], FALSE
    
    mov     rdi, r12
    lea     rsi, [rbx + PREP_peek]
    mov     rcx, TOKEN_SIZE
    rep movsb
    
    mov     rdx, r12
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
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
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
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
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
    lea     rdi, [rbx + PREP_peek]
    mov     rsi, r12
    mov     rcx, TOKEN_SIZE
    rep movsb
    
.done:
    lea     rdx, [rbx + PREP_peek]
    xor     rax, rax
.exit:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
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
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_expand_next
    test    rax, rax
    jz      .check_token           ; produced a token: process it like any other
    ; if expansion finished, try again (checks for parent or falls to lexer)
    jmp     .next

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; lexer error

    ; handle EOF
    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .handle_eof

.check_token:
    ; Tokens from a macro or %rep body get the same treatment as file tokens:
    ; conditional skipping, nested macro calls and % directives all apply.

    ; Resolve any %[NAME] in the token text first: the same body token can be
    ; replayed with different symbol values on each %rep iteration.
    test    byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
    jz      .no_interp
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_resolve_interp
    test    rax, rax
    jnz     .done
.no_interp:

    ; check if skipping
    cmp     byte [rbx + PREP_skip_depth], 0
    je      .not_skipping

    ; we are skipping. only care about % directives (a lone TOK_PERCENT is
    ; the modulo operator: the lexer makes directives TOK_DIRECTIVE)
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .next                  ; consume everything else

    ; handle directive even when skipping
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_handle_directive
    mov     rdi, rbx
    call    prep_drop_stale_newline
    jmp     .next

.not_skipping:
    ; check if it's a macro call (not while a directive reads a name: a
    ; %define being redefined must not expand its old body)
    cmp     byte [rel prep_noexpand], 0
    jne     .not_macro_call
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .not_macro_call
    
    ; look up in symtab
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .try_icase             ; not found or error

    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_macro_call
    jmp     .macro_found

    ; a %idefine matches in any case (only looked for once one exists)
.try_icase:
    cmp     dword [rel idefine_count], 0
    je      .not_macro_call
    mov     rsi, [r12 + TOKEN_value]
    call    prep_icase_buf
    test    rax, rax
    jnz     .not_macro_call
    mov     rdi, [rbx + PREP_ctx]
    lea     rsi, [rel icase_buf]
    call    symbol_find
    test    rax, rax
    jnz     .not_macro_call
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    jne     .not_macro_call

.macro_found:
    ; Found a macro call!
    mov     rdi, rbx
    mov     rsi, [rdx + SYMBOL_value] ; rsi = pointer to MACRO struct
    call    prep_expand_start
    test    rax, rax
    jnz     .done                  ; error starting expansion
    jmp     .next                  ; get first token of expansion

.not_macro_call:
    xor     rax, rax
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

    ; A directive owns its whole line. Its operand reader stops on the
    ; terminating NEWLINE and leaves it in the peek slot, but .next reads
    ; straight from the lexer and would never consume it, so the next macro
    ; call would collect that newline as its first argument token.
    mov     rdi, rbx
    call    prep_drop_stale_newline

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
    
    ; 2. Restore previous lexer (reloading volatile r8 and r9 from callee-saved rbx)
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
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
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
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
    mov     dword [r13 + MACROEXP_rep_count], 1 ; Default: expand once

    ; %%locals are unique per *macro* expansion. A %rep body is an anonymous
    ; macro running inside one, so it must reuse the enclosing id or the
    ; %%names inside the loop would not match those outside it.
    mov     r8, [rbx + PREP_ctx]
    mov     eax, [r8 + ASMCTX_mac_exp_id]
    cmp     qword [r12 + MACRO_name], 0
    jne     .own_exp_id
    mov     r9, [r8 + ASMCTX_mac_exp]
    test    r9, r9
    jz      .own_exp_id
    mov     eax, [r9 + MACROEXP_exp_id]
.own_exp_id:
    mov     [r13 + MACROEXP_exp_id], eax
    ; Check arity
    movzx   rax, byte [r12 + MACRO_min_params]
    movzx   rdx, byte [r12 + MACRO_max_params]
    ; A parameterless macro (every %define) needs no argument buffers
    test    dl, dl
    jnz     .has_params
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jnz     .has_params
    xor     r15, r15
    jmp     .done_params
.has_params:

    ; Allocate space for up to MAX_PARAMS (let's say 32)
    ; For now, we'll allocate based on max_params if not variadic, 
    ; or a fixed buffer if variadic.
    mov     r14, 32                ; max potential params for variadic
    cmp     dl, 0xFF
    je      .alloc_params
    movzx   r14, dl
    
.alloc_params:
    ; params[] : pointer to the first token of each argument
    mov     rsi, r14
    imul    rsi, 8
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_params], rdx
    mov     r14, rdx               ; r14 = param array

    ; arglens[] : token count per argument
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_arglens], rdx

    ; One contiguous buffer for every argument token. The lexer allocates
    ; token value strings from this same arena, so the slots have to be
    ; reserved before any lexing starts, exactly like a macro body.
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_ARG_CAPACITY * TOKEN_SIZE
    call    arena_alloc
    check_err
    mov     [r13 + MACROEXP_pend_ptr], rdx     ; scratch: next free slot
    mov     dword [r13 + MACROEXP_pend_cnt], 0 ; scratch: slots used

    xor     r15, r15               ; r15 = argument index
    mov     dword [rel fn_depth], 0

    ; A function-like %define takes its arguments in parentheses: NAME(a, b)
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .line_args
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .error_too_few_args
    jmp     .arg_loop
.line_args:

    ; A macro that declares no parameters consumes nothing from the line.
    movzx   rax, byte [r12 + MACRO_max_params]
    test    al, al
    jz      .args_done

.arg_loop:
    ; Argument index bound (params[] holds at most 32 entries)
    IF r15, ge, 32
        mov     rax, EXIT_MACRO_ARITY_FAIL
        jmp     .error
        ENDIF

    ; Start a new argument at the current cursor with a zero token count
    mov     rax, [r13 + MACROEXP_pend_ptr]
    mov     [r14 + r15 * 8], rax
    mov     rcx, [r13 + MACROEXP_arglens]
    mov     byte [rcx + r15], 0

.arg_token:
    mov     eax, [r13 + MACROEXP_pend_cnt]
    cmp     eax, MACRO_ARG_CAPACITY
    jge     .error_too_many_args

    ; Read through the preprocessor rather than the raw lexer: a macro
    ; called from inside another macro's body takes its arguments from
    ; the expansion, and %N arguments must already be substituted when
    ; they are captured.
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    mov     rsi, rdx
    mov     rdi, [r13 + MACROEXP_pend_ptr]
    mov     rcx, (TOKEN_SIZE / 8)
    rep movsq

    mov     rsi, [r13 + MACROEXP_pend_ptr]
    movzx   eax, byte [rsi + TOKEN_kind]
    test    byte [r12 + MACRO_flags], MACRO_FLAG_FUNC
    jz      .arg_line_kinds
    ; inside parentheses: nested ( ) belong to the argument, the closing )
    ; ends the call, a comma at depth 0 separates arguments
    cmp     al, TOK_LPAREN
    jne     .fn_not_open
    inc     dword [rel fn_depth]
    jmp     .arg_keep
.fn_not_open:
    cmp     al, TOK_RPAREN
    jne     .fn_not_close
    cmp     dword [rel fn_depth], 0
    je      .arg_end_all
    dec     dword [rel fn_depth]
    jmp     .arg_keep
.fn_not_close:
    cmp     al, TOK_NEWLINE
    je      .error_too_few_args            ; no closing parenthesis
    cmp     al, TOK_EOF
    je      .error_too_few_args
    cmp     al, TOK_COMMA
    jne     .arg_keep
    cmp     dword [rel fn_depth], 0
    je      .arg_end_one
    jmp     .arg_keep
.arg_line_kinds:
    cmp     al, TOK_NEWLINE
    je      .arg_end_all
    cmp     al, TOK_EOF
    je      .arg_end_all
    cmp     al, TOK_COMMA
    je      .arg_end_one

    ; Keep this token as part of the current argument
.arg_keep:
    add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
    inc     dword [r13 + MACROEXP_pend_cnt]
    mov     rcx, [r13 + MACROEXP_arglens]
    inc     byte [rcx + r15]
    jmp     .arg_token

.arg_end_one:
    ; A top-level comma ends this argument; the comma slot gets reused
    inc     r15
    jmp     .arg_loop

.arg_end_all:
    ; Newline or EOF ends the invocation. A trailing empty argument (the
    ; macro was invoked with no arguments at all) does not count.
    mov     rcx, [r13 + MACROEXP_arglens]
    cmp     byte [rcx + r15], 0
    je      .args_done
    inc     r15

.args_done:
    ; Arity checks
    movzx   rax, byte [r12 + MACRO_min_params]
    cmp     r15b, al
    jl      .error_too_few_args
    movzx   rax, byte [r12 + MACRO_max_params]
    IF al, ne, 0xFF
        cmp     r15b, al
        jg      .error_too_many_args
        ENDIF

    ; Release the collection scratch: these fields drive substitution now
    mov     qword [r13 + MACROEXP_pend_ptr], 0
    mov     dword [r13 + MACROEXP_pend_cnt], 0
    jmp     .done_params

.error_too_few_args:
.error_too_many_args:
    mov     rax, EXIT_MACRO_ARITY_FAIL
    jmp     .error

.done_params:
    mov     [r13 + MACROEXP_nparams], r15b
    
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
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
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

    ; 0. An argument spanning several tokens is served one token per call
    mov     eax, [r13 + MACROEXP_pend_cnt]
    test    eax, eax
    jz      .no_pending
        mov     rsi, [r13 + MACROEXP_pend_ptr]
        mov     rdi, r12
        mov     rcx, (TOKEN_SIZE / 8)
        rep movsq
        add     qword [r13 + MACROEXP_pend_ptr], TOKEN_SIZE
        dec     dword [r13 + MACROEXP_pend_cnt]
        jmp     .produced
.no_pending:

.retry_body:
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
    ; A %%local is not a directive, so send it on to CASE 4 rather than
    ; letting it pass through unresolved.
    cmp     byte [r12 + TOKEN_kind], TOK_MACRO_LOCAL
    je      .not_case3
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
        ; A %rep body running inside a macro has no parameters of its own,
        ; so walk out to the nearest expansion that does.
        mov     r11, r13
.param_owner_loop:
        cmp     byte [r11 + MACROEXP_nparams], 0
        jne     .param_owner_found
        mov     r11, [r11 + MACROEXP_parent]
        test    r11, r11
        jnz     .param_owner_loop
        jmp     .retry_body
.param_owner_found:

        ; check if it is within nparams
        movzx   rcx, byte [r11 + MACROEXP_nparams]
        cmp     al, cl
        jg      .retry_body            ; optional parameter not supplied:
                                       ; substitute nothing rather than leaking
                                       ; "%4" out as a stray directive token

        ; Substitute the argument. An argument may span several tokens: emit
        ; the first here and leave the rest pending for the next calls.
        dec     al                     ; 0-indexed
        movzx   rax, al
        mov     r10, r11               ; r10 = expansion owning the parameters
        mov     r11, [r10 + MACROEXP_arglens]
        movzx   rcx, byte [r11 + rax]  ; rcx = token count of this argument
        test    rcx, rcx
        jz      .retry_body            ; empty argument: substitute nothing

        mov     r11, [r10 + MACROEXP_params]
        mov     rsi, [r11 + rax * 8]   ; rsi = first token of the argument

        dec     rcx
        mov     [r13 + MACROEXP_pend_cnt], ecx
        lea     rax, [rsi + TOKEN_SIZE]
        mov     [r13 + MACROEXP_pend_ptr], rax

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
        mov     r14d, dword [r13 + MACROEXP_exp_id]
        
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
        
        ; 2. Allocate the label: "..@" + ID + name + NUL. Only what it needs:
        ;    compile_time_hash expands its %%names once per character, so a
        ;    MAX_TOKEN buffer each time used up the arena on large tables.
        mov     rdi, r15
        call    str_len
        mov     r14, rax
        mov     rdi, [r12 + TOKEN_value]
        call    str_len
        lea     rsi, [r14 + rax + 4]
        mov     rdi, [rbx + PREP_arena]
        call    arena_alloc
        test    rax, rax
        jnz     .produced
        mov     r14, rdx               ; r14 = final label buffer
        
        ; 3. Construct "..@ID_label"
        mov     byte [r14], '.'
        mov     byte [r14+1], '.'
        mov     byte [r14+2], '@'
        mov     byte [r14+3], 0
        
        mov     rdi, r14
        mov     rsi, r15               ; ID string
        extern  str_concat
        call    str_concat
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value] ; original label name
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
        
        ; 2.5 Both operands may still carry %[...] or %$ text: resolve them
        ;     before joining, so ".if_ %+ %$uid" pastes the context's value.
        test    byte [r12 + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_lhs_ready
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_resolve_interp
.concat_lhs_ready:
        test    byte [rsp + TOKEN_flags], TOK_FLAG_INTERP
        jz      .concat_rhs_ready
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_resolve_interp
.concat_rhs_ready:
        ; %assign / %define names paste as their value
        mov     rdi, rbx
        mov     rsi, r12
        call    prep_subst_const_text
        mov     rdi, rbx
        mov     rsi, rsp
        call    prep_subst_const_text

        ; 3. Concatenate r12 (merged so far) and rsp (next token)
        ; Allocate space for combined string
        mov     rdi, [rbx + PREP_arena]
        mov     rsi, MAX_TOKEN
        extern  arena_alloc
        call    arena_alloc
        test    rax, rax
        jnz     .done_concat           ; OOM or error
        
        mov     r14, rdx               ; r14 = concat buffer
        mov     byte [r14], 0          ; null-terminate before str_concat
        
        mov     rdi, r14
        mov     rsi, [r12 + TOKEN_value]
        extern  str_concat
        call    str_concat
        
        mov     rdi, r14
        mov     rsi, [rsp + TOKEN_value]
        call    str_concat
        
        ; 4. Update r12 to be the merged token. When the right-hand piece
        ;    carried the ':' (".lbl_ %+ id %+ _end:"), the join is still a
        ;    label definition, not a plain identifier.
        mov     byte [r12 + TOKEN_kind], TOK_IDENT
        mov     cl, [rsp + TOKEN_kind]
        cmp     cl, TOK_LABEL
        je      .concat_is_label
        cmp     cl, TOK_LOCAL_LABEL
        jne     .concat_kind_set
.concat_is_label:
        mov     byte [r12 + TOKEN_kind], TOK_LABEL
        cmp     byte [r14], '.'
        jne     .concat_kind_set
        mov     byte [r12 + TOKEN_kind], TOK_LOCAL_LABEL
.concat_kind_set:
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
    mov     rdi, rbx
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
    lea     rsi, [dir_assign]
    call    str_cmp
    test    rax, rax
    jz      .do_assign

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_push]
    call    str_cmp
    test    rax, rax
    jz      .do_push

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_pop]
    call    str_cmp
    test    rax, rax
    jz      .do_pop

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifctx]
    call    str_cmp
    test    rax, rax
    jz      .do_ifctx

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_ifidni]
    call    str_cmp
    test    rax, rax
    jz      .do_ifidni

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_elifidni]
    call    str_cmp
    test    rax, rax
    jz      .do_elifidni

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_elif]
    call    str_cmp
    test    rax, rax
    jz      .do_elif

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_error]
    call    str_cmp
    test    rax, rax
    jz      .do_error

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_strlen]
    call    str_cmp
    test    rax, rax
    jz      .do_strlen

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_substr]
    call    str_cmp
    test    rax, rax
    jz      .do_substr

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rotate]
    call    str_cmp
    test    rax, rax
    jz      .do_rotate

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_def_short]
    call    str_cmp
    test    rax, rax
    jz      .do_def

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_xdefine]
    call    str_cmp
    test    rax, rax
    jz      .do_xdefine

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_idefine]
    call    str_cmp
    test    rax, rax
    jz      .do_idefine

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_inc_short]
    call    str_cmp
    test    rax, rax
    jz      .do_inc

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_undef]
    call    str_cmp
    test    rax, rax
    jz      .do_undef

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
    lea     rsi, [dir_unmacro]
    call    str_cmp
    test    rax, rax
    jz      .do_unmacro

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_unimacro]
    call    str_cmp
    test    rax, rax
    jz      .do_unmacro

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

    jmp     .discard_unknown

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

.do_assign:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_assign
    jmp     .done_cleanup

.do_push:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_push
    jmp     .done_cleanup

.do_pop:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_pop
    jmp     .done_cleanup

.do_ifctx:
    mov     rdi, rbx
    call    prep_handle_ifctx
    jmp     .done_cleanup

.do_ifidni:
    mov     rdi, rbx
    call    prep_handle_ifidni
    jmp     .done_cleanup

.do_elifidni:
    mov     rdi, rbx
    call    prep_handle_elifidni
    jmp     .done_cleanup

.do_elif:
    mov     rdi, rbx
    call    prep_handle_elif
    jmp     .done_cleanup

.do_error:
    mov     rdi, rbx
    call    prep_handle_error
    jmp     .done_cleanup

.do_strlen:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_strlen
    jmp     .done_cleanup

.do_substr:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_substr
    jmp     .done_cleanup

.do_idefine:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_icase], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_xdefine:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_eager], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_undef:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_undef
    jmp     .done_cleanup

.do_rotate:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    extern  prep_handle_rotate
    call    prep_handle_rotate             ; frontend/macro/rotate.s
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
    je      .do_macro_normal
    mov     rdi, rbx
    call    prep_skip_macro_block
    jmp     .done_cleanup
.do_macro_normal:
    mov     rdi, rbx
    call    macro_handle_def
    jmp     .done_cleanup

.do_unmacro:
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done_cleanup          ; inside a skipped block: ignore entirely
    mov     rdi, rbx
    call    prep_handle_unmacro
    jmp     .done_cleanup

.do_rep:
    cmp     byte [rbx + PREP_skip_depth], 0
    je      .do_rep_normal
    mov     rdi, rbx
    call    prep_skip_rep_block
    jmp     .done_cleanup
.do_rep_normal:
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

.discard_unknown:
    ; A misspelt directive must not vanish silently. Inside a skipped %if
    ; branch nothing is checked, and names that do not start with a letter
    ; (%1, %{1..}) are macro parameter forms, left as before.
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .discard_quietly
    mov     rax, [r12 + TOKEN_value]
    test    rax, rax
    jz      .discard_quietly
    movzx   eax, byte [rax]
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 25
    ja      .discard_quietly
    mov     rdi, 2
    lea     rsi, [rel msg_unknown_dir]
    extern  print_str
    call    print_str
    mov     rdi, 2
    mov     rsi, [r12 + TOKEN_value]
    call    print_str
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    call    print_str
    mov     rax, EXIT_UNEXPECTED_TOKEN
    jmp     .done_cleanup
.discard_quietly:
    sub     rsp, TOKEN_SIZE
.discard_unknown_loop:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .discard_unknown_done
    cmp     byte [rsp + TOKEN_kind], TOK_NEWLINE
    je      .discard_unknown_done
    cmp     byte [rsp + TOKEN_kind], TOK_EOF
    je      .discard_unknown_done
    jmp     .discard_unknown_loop
.discard_unknown_done:
    add     rsp, TOKEN_SIZE
    xor     rax, rax
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
    mov     rax, 101
    jmp     .done

.error_expected_string:
    mov     rax, 102
    jmp     .done

.error_too_deep:
    mov     rax, 103
    jmp     .done

.error_open:
    ; Keep rax if non-zero, otherwise set 104
    test    rax, rax
    jnz     .error_open_done
    mov     rax, 104
.error_open_done:
    jmp     .done

.error_size:
    mov     rax, 105
    jmp     .done

.error_mmap:
    mov     rax, 106
    jmp     .done

.error:
    mov     rax, 107
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
dir_assign: db "assign", 0
dir_push:   db "push", 0
dir_pop:    db "pop", 0
dir_ifctx:  db "ifctx", 0
dir_ifidni:   db "ifidni", 0
dir_elifidni: db "elifidni", 0
dir_elif:     db "elif", 0
dir_error:    db "error", 0
dir_strlen:   db "strlen", 0
dir_substr:   db "substr", 0
dir_rotate:   db "rotate", 0
dir_def_short: db "def", 0          ; utasm short forms: %def, %inc
dir_inc_short: db "inc", 0
dir_xdefine:  db "xdefine", 0       ; %define is already expanded eagerly
dir_undef:    db "undef", 0
dir_idefine:  db "idefine", 0       ; treated as %define
; "0".."9" for the %N references of a function-like %define
def_digits:   db "0", 0, "1", 0, "2", 0, "3", 0, "4", 0, "5", 0, "6", 0, "7", 0, "8", 0, "9", 0
undef_name:   db 0                  ; the name of an %undef'd entry
msg_unknown_dir: db "error: unknown preprocessor directive %", 0
msg_prep_error: db "preprocessor %error directive reached", 10, 0
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
dir_unmacro:  db "unmacro", 0
dir_unimacro: db "unimacro", 0

msg_preprocessor_dir_trace: db "[+] PREP: Directive: ", 0
msg_newline:                db 10, 0

dbg_msg1:     db "prep_handle_directive: kind=", 0
dbg_msg2:     db " value=", 0
dbg_msg3:     db " (not directive)", 0
dbg_msg_null: db "<null>", 0
dbg_newline:  db 10, 0
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
; ---- prep_subst_const_text --------------
;
; prep_subst_const_text
; If the token names a %assign / %define constant, replace its text with the
; constant's value in decimal. Pasting joins text, and "%assign i 7" makes i
; a numeric macro: ".lbl_ %+ i" has to produce ".lbl_7", not ".lbl_i".
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (rewritten in place)
;
prep_subst_const_text:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .done

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, [r12 + TOKEN_value]
    call    symbol_find
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .done
    mov     r13, [rdx + SYMBOL_value]

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 32
    call    arena_alloc
    test    rax, rax
    jnz     .done

    mov     rdi, rdx
    mov     [r12 + TOKEN_value], rdx
    mov     rsi, r13
    call    str_int_to_str
    mov     byte [r12 + TOKEN_kind], TOK_NUMBER

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- conditional level bookkeeping ------
;
; PREP_depth counts open conditionals and PREP_skip_depth counts how many of
; them are currently suppressing output. cond_taken[level] records whether a
; branch at that level has already fired, which is what makes %elif chains
; behave: once one branch is taken, every later branch stays skipped.
;
; prep_cond_enter : rdi = PrepState, sil = 1 when the condition holds
;
prep_cond_enter:
    movzx   eax, byte [rdi + PREP_depth]
    cmp     al, PREP_CTX_MAX
    jge     .overflow

    cmp     byte [rdi + PREP_skip_depth], 0
    jne     .outer_skipping

    test    sil, sil
    jz      .not_taken
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     byte [rdi + PREP_depth]
    xor     rax, rax
    ret

.not_taken:
    mov     byte [rdi + PREP_cond_taken + rax], 0
    inc     byte [rdi + PREP_skip_depth]
    inc     byte [rdi + PREP_depth]
    xor     rax, rax
    ret

.outer_skipping:
    ; an enclosing level is suppressing: mark taken so %else cannot revive it
    mov     byte [rdi + PREP_cond_taken + rax], 1
    inc     byte [rdi + PREP_skip_depth]
    inc     byte [rdi + PREP_depth]
    xor     rax, rax
    ret

.overflow:
    mov     rax, EXIT_MACRO_RECURSION
    ret

;
; prep_cond_branch : rdi = PrepState, sil = 1 when this branch's condition
;                    holds (%else passes 1). Handles %else / %elif / %elifidni.
;
prep_cond_branch:
    movzx   eax, byte [rdi + PREP_depth]
    test    al, al
    jz      .no_if
    dec     eax

    movzx   ecx, byte [rdi + PREP_skip_depth]
    cmp     cl, 1
    jg      .unchanged             ; an outer level is skipping

    cmp     byte [rdi + PREP_cond_taken + rax], 0
    jne     .force_skip

    test    sil, sil
    jz      .stay_skipping
    mov     byte [rdi + PREP_cond_taken + rax], 1
    mov     byte [rdi + PREP_skip_depth], 0
    xor     rax, rax
    ret

.stay_skipping:
    mov     byte [rdi + PREP_skip_depth], 1
    xor     rax, rax
    ret

.force_skip:
    mov     byte [rdi + PREP_skip_depth], 1
.unchanged:
    xor     rax, rax
    ret

.no_if:
    mov     rax, EXIT_ERROR
    ret

; ---- prep_str_cmp_ci --------------------
;
; Case-insensitive comparison of two NUL-terminated strings.
; Input  : rdi, rsi = strings
; Output : rax = 0 when equal
;
prep_str_cmp_ci:
.loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]

    cmp     al, 'A'
    jb      .a_ready
    cmp     al, 'Z'
    ja      .a_ready
    add     al, 32
.a_ready:
    cmp     cl, 'A'
    jb      .b_ready
    cmp     cl, 'Z'
    ja      .b_ready
    add     cl, 32
.b_ready:
    cmp     al, cl
    jne     .differ
    test    al, al
    jz      .equal
    inc     rdi
    inc     rsi
    jmp     .loop

.equal:
    xor     rax, rax
    ret
.differ:
    mov     rax, 1
    ret

; ---- prep_read_idn_pair -----------------
;
; Reads "A, B" from the directive line and reports whether the two token
; texts are equal ignoring case. Used by %ifidni and %elifidni.
;
; Input  : rdi = PrepState
; Output : rax = EXIT_OK, rdx = 1 when the texts match
;
prep_read_idn_pair:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi

    ; The operands belong to this directive and must be read even inside a
    ; skipped block; with skipping active the token reader would swallow the
    ; rest of the file instead of handing them back.
    movzx   r14d, byte [rbx + PREP_skip_depth]
    mov     byte [rbx + PREP_skip_depth], 0

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    mov     r12, [rdx + TOKEN_value]

    ; separator
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    mov     r13, [rdx + TOKEN_value]

    test    r12, r12
    jz      .not_equal
    test    r13, r13
    jz      .not_equal

    mov     rdi, r12
    mov     rsi, r13
    call    prep_str_cmp_ci
    test    rax, rax
    jnz     .not_equal

    xor     rax, rax
    mov     rdx, 1
    jmp     .done

.not_equal:
    xor     rax, rax
    xor     rdx, rdx
    jmp     .done

.fail:
    xor     rdx, rdx

.done:
    mov     [rbx + PREP_skip_depth], r14b   ; restore the skip state
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_ifidni -----------------
prep_handle_ifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_enter

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elifidni ---------------
prep_handle_elifidni:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_read_idn_pair
    test    rax, rax
    jnz     .done

    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_branch

.done:
    pop     rbx
    epilogue

; ---- prep_handle_elif -------------------
prep_handle_elif:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; Only evaluate when this level could still take a branch
    movzx   eax, byte [rbx + PREP_depth]
    test    al, al
    jz      .no_if
    dec     eax
    movzx   ecx, byte [rbx + PREP_skip_depth]
    cmp     cl, 1
    jg      .no_eval
    cmp     byte [rbx + PREP_cond_taken + rax], 0
    jne     .no_eval

    ; The condition is this directive's own operand: read it with skipping
    ; suspended, or the token reader discards it along with the skipped block.
    movzx   r12d, byte [rbx + PREP_skip_depth]
    mov     byte [rbx + PREP_skip_depth], 0

    mov     rdi, rbx
    call    parser_evaluate_expression
    mov     byte [rbx + PREP_skip_depth], r12b
    test    rax, rax
    jnz     .done
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done

.no_eval:
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_branch
    jmp     .done

.no_if:
    mov     rax, EXIT_ERROR

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_error ------------------
;
; "%error message" — reported only when the line is actually reached.
;
prep_handle_error:
    prologue
    push    rbx
    mov     rbx, rdi

    ; While skipping there is nothing to report and nothing to drain: the
    ; skip loop consumes the rest of the line itself. Peeking here would run
    ; the preprocessor over the following %endif and swallow it.
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .done

    mov     rdi, 2
    lea     rsi, [rel msg_prep_error]
    extern  print_str
    call    print_str

.drain:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .drain

.done:
    xor     rax, rax
    pop     rbx
    epilogue

; ---- prep_raw_next ----------------------
;
; Reads the next token without expanding or interpreting it: from the active
; macro/%rep body when one is running, otherwise from the file. %rep captures
; its body with this, so a %rep written inside a macro copies the macro's
; tokens instead of running off into the source file.
;
; Input  : rdi = PrepState, rsi = destination Token
; Output : rax = EXIT_OK or error
;
prep_raw_next:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi

    mov     rax, [rbx + PREP_ctx]
    mov     r13, [rax + ASMCTX_mac_exp]
    test    r13, r13
    jz      .from_lexer

    mov     rax, [r13 + MACROEXP_body]
    mov     r9, [r13 + MACROEXP_macro]
    cmp     eax, [r9 + MACRO_ntokens]
    jge     .from_lexer                ; body exhausted: continue in the file

    mov     r10, [r9 + MACRO_tokens]
    imul    rax, TOKEN_SIZE
    add     r10, rax
    mov     rdi, r12
    mov     rsi, r10
    mov     rcx, (TOKEN_SIZE / 8)
    rep movsq
    inc     qword [r13 + MACROEXP_body]
    xor     rax, rax
    jmp     .done

.from_lexer:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r12
    call    lexer_next

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_raw_peek ----------------------
;
; prep_raw_peek
; Like prep_raw_next, without consuming the token: the next one of the
; current macro expansion, else of the file.
; Input    : rdi = PrepState, rsi = token to fill
; Output   : rax = EXIT_OK or error
;
prep_raw_peek:
    mov     rax, [rdi + PREP_ctx]
    mov     rax, [rax + ASMCTX_mac_exp]
    test    rax, rax
    jz      .from_lexer
    mov     rcx, [rax + MACROEXP_body]
    mov     r9, [rax + MACROEXP_macro]
    cmp     ecx, [r9 + MACRO_ntokens]
    jge     .from_lexer
    imul    rcx, TOKEN_SIZE
    add     rcx, [r9 + MACRO_tokens]
    push    rdi
    push    rsi
    mov     rdi, rsi
    mov     rsi, rcx
    mov     rcx, (TOKEN_SIZE / 8)
    rep movsq
    pop     rsi
    pop     rdi
    xor     eax, eax
    ret
.from_lexer:
    mov     rdi, [rdi + PREP_lexer]
    jmp     lexer_peek

; ---- prep_handle_unmacro ----------------
;
; prep_handle_unmacro
; "%unmacro name nparams" (and the case-insensitive "%unimacro") removes a
; previously defined multi-line macro. The symbol table has no delete, so the
; entry is retired in place by clearing its kind -- the macro-call lookup in
; prep_internal_next only fires on SYM_MACRO, so an entry of any other kind is
; inert. Removing a name that is not a macro is not an error, matching NASM.
;
; The parameter spec is parsed and discarded: it only disambiguates between
; overloads, which utasm does not keep.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_unmacro:
    prologue
    push    rbx
    push    r12
    sub     rsp, TOKEN_SIZE        ; scratch token
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; 1. Macro name, taken straight from the lexer. Reading it through the
    ;    preprocessor would recognise the name as a macro *call* and expand
    ;    it, which is exactly what %macro avoids for the same reason.
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, rsp
    call    lexer_next
    test    rax, rax
    jnz     .done
    IF byte [rsp + TOKEN_kind], ne, TOK_IDENT
        mov     rax, EXIT_UNEXPECTED_TOKEN
        jmp     .done
        ENDIF
    mov     r12, [rsp + TOKEN_value]

    ; 2. Retire it if it is currently a macro
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    extern  symbol_find
    call    symbol_find
    IF rax, e, OK
        IF byte [rdx + SYMBOL_kind], e, SYM_MACRO
            mov     byte [rdx + SYMBOL_kind], SYM_UNKNOWN
            ENDIF
        ENDIF

    ; 3. Discard the parameter spec
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    add     rsp, TOKEN_SIZE
    pop     r12
    pop     rbx
    epilogue

; ---- prep_drain_line --------------------
;
; Consumes what is left of the current directive's line, including the
; terminating newline, so the next directive starts on a clean stream.
; Directives that evaluate an expression stop *on* the newline and leave it
; in the peek slot instead; those use prep_drop_stale_newline.
;
; Input : rdi = PrepState
;
prep_drain_line:
    prologue
    push    rbx
    mov     rbx, rdi

.loop:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + TOKEN_kind], TOK_EOF
    je      .done
    cmp     byte [rdx + TOKEN_kind], TOK_NEWLINE
    je      .eat_newline
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .loop

.eat_newline:
    mov     rdi, rbx
    call    preprocessor_next_token

.done:
    xor     rax, rax
    pop     rbx
    epilogue

; ---- prep_define_const ------------------
;
; Defines or re-defines a numeric constant, the way %assign does.
; Input : rdi = PrepState, rsi = name string, rdx = value
;
prep_define_const:
    prologue
    push    rbx
    push    r12
    push    r13
    sub     rsp, SYMBOL_SIZE
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .create
    mov     [rdx + SYMBOL_value], r13
    xor     rax, rax
    jmp     .done

.create:
    mov     rdi, rsp
    mov     rcx, (SYMBOL_SIZE / 8)
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     [rdi + SYMBOL_name], r12
    mov     [rdi + SYMBOL_value], r13

    mov     rsi, rdi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_add

.done:
    add     rsp, SYMBOL_SIZE
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_strlen -----------------
;
; "%strlen NAME "text"" defines NAME as the length of the string.
;
prep_handle_strlen:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    call    prep_token_text            ; 'hello' is a packed character constant
    mov     rdi, rax                   ; string contents
    test    rdi, rdi
    jz      .empty
    call    str_len
    jmp     .define
.empty:
    xor     rax, rax

.define:
    mov     rdx, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_define_const
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_substr -----------------
;
; "%substr NAME "text" index" defines NAME as the character at the 1-based
; index. NASM yields a one-character string there; utasm stores the character
; code directly, which is how compile_time_hash consumes it.
;
prep_handle_substr:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     r12, [rdx + TOKEN_value]   ; name

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    call    prep_token_text
    mov     r13, rax                   ; string contents

    mov     rdi, rbx
    call    parser_evaluate_expression ; 1-based index
    test    rax, rax
    jnz     .done
    mov     rcx, rdx

    xor     rax, rax
    test    r13, r13
    jz      .define
    test    rcx, rcx
    jle     .define
    dec     rcx                        ; 0-based

    ; bounds check against the string length
    push    rcx
    mov     rdi, r13
    call    str_len
    pop     rcx
    cmp     rcx, rax
    jge     .out_of_range
    movzx   rax, byte [r13 + rcx]
    jmp     .define
.out_of_range:
    xor     rax, rax

.define:
    mov     rdx, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    prep_define_const
    mov     rdi, rbx
    call    prep_drain_line
    xor     rax, rax

.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_token_text ------------------
;
; prep_token_text
; The text of a quoted token as a NUL-terminated string. A "..." string (or a
; '...' one longer than eight characters) already is one; a short '...' is a
; character constant whose characters are packed into TOKEN_value, so they
; are unpacked into an arena buffer.
; Input    : rdx = token, rbx = PrepState
; Output   : rax = the text (0 if none)
;
prep_token_text:
    cmp     byte [rdx + TOKEN_kind], TOK_CHAR
    je      .char
    mov     rax, [rdx + TOKEN_value]
    ret
.char:
    push    r12
    push    r13
    mov     r12, [rdx + TOKEN_value]
    movzx   r13d, word [rdx + TOKEN_len]
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, 16
    call    arena_alloc                ; zeroed: the text ends in NUL
    test    rax, rax
    jnz     .none
    xor     ecx, ecx
.byte:
    cmp     ecx, r13d
    jae     .done
    cmp     ecx, 8
    jae     .done
    mov     [rdx + rcx], r12b
    shr     r12, 8
    inc     ecx
    jmp     .byte
.done:
    mov     rax, rdx
    pop     r13
    pop     r12
    ret
.none:
    xor     eax, eax
    pop     r13
    pop     r12
    ret

; ---- prep_drop_stale_newline ------------
;
; prep_drop_stale_newline
; Directives that evaluate an expression stop on the terminating NEWLINE and
; leave it in the peek slot. It belongs to the finished line, so the next
; directive that reads operands must not see it.
;
; Input    : rdi = pointer to PrepState
;
prep_drop_stale_newline:
    cmp     byte [rdi + PREP_has_peek], TRUE
    jne     .done
    cmp     byte [rdi + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .done
    mov     byte [rdi + PREP_has_peek], FALSE
.done:
    ret

; ---- prep_handle_push -------------------
;
; prep_handle_push
; "%push name" opens a context. Each context gets a unique id, which is what
; makes %$local names unique per IF/ENDIF pair.
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_push:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    mov     eax, [rbx + PREP_ctx_depth]
    cmp     eax, PREP_CTX_MAX
    jge     .overflow

    ; the context name is optional
    xor     r12, r12
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .store
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .store
    mov     r12, [rdx + TOKEN_value]

.store:
    mov     eax, [rbx + PREP_ctx_depth]
    mov     ecx, [rbx + PREP_ctx_next_id]
    inc     ecx
    mov     [rbx + PREP_ctx_next_id], ecx
    mov     [rbx + PREP_ctx_ids + rax * 4], ecx
    lea     rdx, [rbx + PREP_ctx_names]
    mov     [rdx + rax * 8], r12
    inc     eax
    mov     [rbx + PREP_ctx_depth], eax

    xor     rax, rax
    jmp     .done

.overflow:
    mov     rax, EXIT_MACRO_RECURSION

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_pop --------------------
;
; prep_handle_pop
; "%pop [name]" closes the innermost context.
;
prep_handle_pop:
    prologue
    push    rbx
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; an optional context name may follow; it is not verified
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .drop
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .drop
    mov     rdi, rbx
    call    preprocessor_next_token

.drop:
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .underflow
    dec     eax
    mov     [rbx + PREP_ctx_depth], eax
    xor     rax, rax
    jmp     .done

.underflow:
    mov     rax, EXIT_MACRO_DEF

.done:
    pop     rbx
    epilogue

; ---- prep_handle_ifctx ------------------
;
; prep_handle_ifctx
; "%ifctx name" is true when the innermost context carries that name.
;
prep_handle_ifctx:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rdi, rbx
    call    prep_drop_stale_newline

    ; already skipping: just track the nesting
    cmp     byte [rbx + PREP_skip_depth], 0
    jne     .nested_skip

    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .done
    mov     r12, [rdx + TOKEN_value]

    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .false
    dec     eax
    lea     rdx, [rbx + PREP_ctx_names]
    mov     rsi, [rdx + rax * 8]
    test    rsi, rsi
    jz      .false

    mov     rdi, r12
    call    str_cmp
    test    rax, rax
    jnz     .false

    ; true
    inc     byte [rbx + PREP_depth]
    xor     rax, rax
    jmp     .done

.false:
    inc     byte [rbx + PREP_skip_depth]
    inc     byte [rbx + PREP_depth]
    xor     rax, rax
    jmp     .done

.nested_skip:
    inc     byte [rbx + PREP_skip_depth]
    inc     byte [rbx + PREP_depth]
    xor     rax, rax

.done:
    pop     r12
    pop     rbx
    epilogue

; ---- prep_resolve_interp ----------------
;
; prep_resolve_interp
; Rewrites a token's text, replacing every "%[NAME]" with the decimal value
; of NAME. A name that is not defined contributes nothing, matching how the
; tables in include/arch/*.inc are built.
;
; Input    : rdi = pointer to PrepState
;             rsi = pointer to Token (text is replaced in place)
; Output   : rax = EXIT_OK or error code
;
prep_resolve_interp:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, rsi               ; r12 = Token

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, LEX_INTERP_BUF
    call    arena_alloc
    test    rax, rax
    jnz     .done
    mov     r14, rdx               ; r14 = output buffer
    xor     r15, r15               ; r15 = output length
    mov     r13, [r12 + TOKEN_value] ; r13 = source cursor

.scan:
    cmp     r15, (LEX_INTERP_BUF - 24)
    jge     .finish
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish

    cmp     al, '%'
    jne     .copy_char
    cmp     byte [r13 + 1], '$'
    je      .ctx_local
    cmp     byte [r13 + 1], '['
    jne     .copy_char

    ; "%[" : read the name up to ']'
    add     r13, 2
    mov     r9, r13
.name_loop:
    movzx   rax, byte [r13]
    test    al, al
    jz      .finish
    cmp     al, ']'
    je      .name_done
    inc     r13
    jmp     .name_loop

.name_done:
    mov     r10, r13
    sub     r10, r9                ; name length
    inc     r13                    ; step over ']'

    mov     rdi, [rbx + PREP_arena]
    mov     rsi, r9
    mov     rdx, r10
    call    arena_alloc_string
    test    rax, rax
    jnz     .done
    mov     r9, rdx

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r9
    call    symbol_find
    test    rax, rax
    jnz     .scan                  ; undefined: contributes nothing

    mov     rsi, [rdx + SYMBOL_value]
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    jmp     .scan

.ctx_local:
    ; "%$name" is local to the innermost %push context: rewrite it as the
    ; ordinary symbol "__ctxN$name", which makes each IF/ENDIF pair unique.
    add     r13, 2
    mov     eax, [rbx + PREP_ctx_depth]
    test    eax, eax
    jz      .ctx_id_zero
    dec     eax
    mov     eax, [rbx + PREP_ctx_ids + rax * 4]
    jmp     .ctx_id_ready
.ctx_id_zero:
    xor     eax, eax
.ctx_id_ready:
    mov     byte [r14 + r15], '_'
    mov     byte [r14 + r15 + 1], '_'
    mov     byte [r14 + r15 + 2], 'c'
    mov     byte [r14 + r15 + 3], 't'
    mov     byte [r14 + r15 + 4], 'x'
    add     r15, 5
    mov     rsi, rax
    lea     rdi, [r14 + r15]
    call    str_int_to_str
    lea     rdi, [r14 + r15]
    call    str_len
    add     r15, rax
    mov     byte [r14 + r15], '$'
    inc     r15
    jmp     .scan

.copy_char:
    mov     [r14 + r15], al
    inc     r15
    inc     r13
    jmp     .scan

.finish:
    mov     byte [r14 + r15], 0
    mov     [r12 + TOKEN_value], r14
    mov     word [r12 + TOKEN_len], r15w
    and     byte [r12 + TOKEN_flags], ~TOK_FLAG_INTERP
    xor     rax, rax

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_assign -----------------
;
; prep_handle_assign
; Handles "%assign NAME <expression>". Unlike %define, the value is an
; integer expression evaluated immediately, and re-assignment is allowed
; (that is what makes counters like "%assign i i+1" work).
;
; Input    : rdi = pointer to PrepState
; Output   : rax = EXIT_OK or error code
;
prep_handle_assign:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, TOKEN_SIZE + SYMBOL_SIZE
    mov     rbx, rdi               ; rbx = PrepState

    ; A previous expression-evaluating directive can leave the terminating
    ; NEWLINE in the peek slot. The name below is lexed straight from the
    ; lexer, which does not consult that slot, so drop it first.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_stale_peek
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .no_stale_peek
    mov     byte [rbx + PREP_has_peek], FALSE
.no_stale_peek:

    ; 1. Read the name through the preprocessor, not the raw lexer: inside a
    ;    %rep or %macro body the tokens come from the expansion, not the file.
    ;    Not expanded: a name that is also a %define stays the name.
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .error
    mov     r12, rdx
    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .error_ident
    mov     r13, [r12 + TOKEN_value]

    ; 2. Evaluate the value (same evaluator %if uses)
    mov     rdi, rbx
    extern  parser_evaluate_expression
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .error
    mov     r14, rdx               ; r14 = value

    ; 3. Re-assign in place when the name already exists (it may have been
    ;    a %define: it is a number now)
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r13
    call    symbol_find
    test    rax, rax
    jnz     .create
    mov     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    mov     [rdx + SYMBOL_value], r14
    xor     rax, rax
    jmp     .done

.create:
    lea     rdi, [rsp + TOKEN_SIZE]
    mov     rcx, (SYMBOL_SIZE / 8)
    xor     rax, rax
    mov     r10, rdi
    rep stosq
    mov     rdi, r10

    mov     byte [rdi + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rdi + SYMBOL_kind], SYM_CONSTANT
    mov     [rdi + SYMBOL_name], r13
    mov     [rdi + SYMBOL_value], r14

    mov     rsi, rdi
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_add
    test    rax, rax
    jnz     .error
    xor     rax, rax
    jmp     .done

.error_ident:
    mov     rax, EXIT_DEFINE
    jmp     .done

.error:
    test    rax, rax
    jnz     .done
    mov     rax, EXIT_DEFINE

.done:
    add     rsp, TOKEN_SIZE + SYMBOL_SIZE
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---- prep_handle_undef ------------------
;
; prep_handle_undef
; "%undef NAME" removes a %define. The symbol entry stays in the table (its
; slot keeps later probes working) but gets an empty name, which no lookup
; matches; a later %define NAME creates a fresh entry.
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_undef:
    push    rbx
    mov     rbx, rdi
    mov     byte [rel prep_noexpand], 1    ; the name, not its body
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     byte [rel prep_noexpand], 0
    test    rax, rax
    jnz     .ret
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     rsi, [rdx + TOKEN_value]
    mov     rdi, [rbx + PREP_ctx]
    call    symbol_find
    test    rax, rax
    jnz     .ok                            ; not defined: nothing to remove
    cmp     byte [rdx + SYMBOL_kind], SYM_MACRO
    je      .remove                        ; a %define
    cmp     byte [rdx + SYMBOL_kind], SYM_CONSTANT
    jne     .ok                            ; only %define/%assign names
.remove:
    lea     rax, [rel undef_name]
    mov     [rdx + SYMBOL_name], rax
.ok:
    xor     eax, eax
.ret:
    pop     rbx
    ret
.bad:
    mov     rax, EXIT_DEFINE
    jmp     .ret

; ---- prep_icase_buf ---------------------
;
; prep_icase_buf
; The key a %idefine name is stored under: 0x01 followed by the name in
; lower case (no source text can spell it), written to icase_buf.
; Input    : rsi = name
; Output   : rax = 0, or 1 when the name is too long for the buffer
;
prep_icase_buf:
    lea     rdi, [rel icase_buf]
    mov     byte [rdi], 1
    inc     rdi
    xor     ecx, ecx
.copy:
    movzx   eax, byte [rsi + rcx]
    cmp     eax, 'A'
    jb      .put
    cmp     eax, 'Z'
    ja      .put
    or      eax, 0x20
.put:
    mov     [rdi + rcx], al
    test    eax, eax
    jz      .ok
    inc     ecx
    cmp     ecx, 250
    jb      .copy
    mov     eax, 1
    ret
.ok:
    xor     eax, eax
    ret

; ---- prep_handle_def ------------------
;
; prep_handle_def
; "%define NAME body": NAME stands for the rest of the line, expanded where
; NAME is used (as in NASM, where a %define is text). The body is kept as a
; parameterless macro, so the expansion machinery that serves %macro calls
; serves it too. "%define NAME(a, b) body", with the parenthesis right
; after the name, takes arguments: NAME(1, 2); the parameter names in the
; body become %1, %2.
;
; The body is read with %1 / %%local substituted (inside a macro) but other
; macros left unexpanded, so it is expanded when used; %xdefine (def_eager)
; expands it now. A redefinition replaces the earlier body.
;
; Input    : rdi = PrepState
; Output   : rax = EXIT_OK or error
;
prep_handle_def:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi

    ; An expression-evaluating directive can leave the terminating NEWLINE
    ; in the peek slot; it does not belong to this definition.
    cmp     byte [rbx + PREP_has_peek], TRUE
    jne     .no_stale_peek
    cmp     byte [rbx + PREP_peek + TOKEN_kind], TOK_NEWLINE
    jne     .no_stale_peek
    mov     byte [rbx + PREP_has_peek], FALSE
.no_stale_peek:

    ; 1. The name, never expanded: redefining must not expand the old body
    mov     byte [rel prep_noexpand], 1
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .bad
    mov     r12, [rdx + TOKEN_value]       ; r12 = name
    movzx   r13d, word [rdx + TOKEN_col]
    movzx   eax, word [rdx + TOKEN_len]
    add     r13d, eax                      ; the column right after the name
    mov     r14d, [rdx + TOKEN_line]

    ; %idefine: stored under a case-insensitive key
    cmp     byte [rel def_icase], 0
    je      .name_ready
    mov     rsi, r12
    call    prep_icase_buf
    test    rax, rax
    jnz     .bad
    lea     rdi, [rel icase_buf]
    call    str_len
    lea     rsi, [rax + 1]
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r12, rdx
    mov     rdi, rdx
    lea     rsi, [rel icase_buf]
    call    str_concat
    inc     dword [rel idefine_count]
.name_ready:

    ; the body is expanded now only for %xdefine; that has to hold from the
    ; first peek on, which may already read the body's first token
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al

    ; 2. Parameters: "NAME(a, b)" with no blank before the parenthesis
    mov     byte [rel def_nparams], 0
    mov     byte [rel def_func], 0
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    cmp     byte [rdx + TOKEN_kind], TOK_LPAREN
    jne     .body
    cmp     [rdx + TOKEN_line], r14d
    jne     .body
    cmp     [rdx + TOKEN_col], r13w
    jne     .body
    mov     byte [rel def_func], MACRO_FLAG_FUNC
    mov     rdi, rbx
    call    preprocessor_next_token        ; "("
.param:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_RPAREN
    je      .body
    cmp     eax, TOK_COMMA
    je      .param
    cmp     eax, TOK_IDENT
    jne     .bad
    movzx   ecx, byte [rel def_nparams]
    cmp     ecx, 9
    jae     .bad                           ; %1-%9
    mov     rax, [rdx + TOKEN_value]
    lea     r8, [rel def_pnames]
    mov     [r8 + rcx*8], rax
    inc     byte [rel def_nparams]
    jmp     .param

    ; 3. The body: the rest of the line
.body:
    movzx   eax, byte [rel def_eager]
    xor     eax, 1
    mov     [rel prep_noexpand], al        ; %xdefine expands now
    xor     r15d, r15d                     ; tokens captured
.btok:
    mov     rdi, rbx
    call    preprocessor_peek_token
    test    rax, rax
    jnz     .fail
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_NEWLINE
    je      .store
    cmp     eax, TOK_EOF
    je      .store
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .fail
    cmp     r15d, DEFINE_MAX_TOKENS
    jae     .bad
    mov     eax, r15d
    imul    eax, eax, TOKEN_SIZE
    lea     rdi, [rel def_scratch]
    add     rdi, rax
    mov     r8, rdi                        ; r8 = the captured token
    mov     rsi, rdx
    mov     ecx, TOKEN_SIZE / 8
    rep movsq
    inc     r15d
    ; a parameter name becomes a %N reference
    cmp     byte [r8 + TOKEN_kind], TOK_IDENT
    jne     .btok
    xor     r14d, r14d
.pname:
    movzx   eax, byte [rel def_nparams]
    cmp     r14d, eax
    jae     .btok
    push    r8
    mov     rdi, [r8 + TOKEN_value]
    lea     rax, [rel def_pnames]
    mov     rsi, [rax + r14*8]
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .is_param
    inc     r14d
    jmp     .pname
.is_param:
    mov     byte [r8 + TOKEN_kind], TOK_DIRECTIVE
    lea     rax, [rel def_digits]
    lea     rax, [rax + r14*2 + 2]         ; "1".."9"
    mov     [r8 + TOKEN_value], rax
    jmp     .btok

    ; 4. A MACRO with the captured tokens, under NAME
.store:
    mov     byte [rel prep_noexpand], 0
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     r13, rdx
    mov     byte [r13 + MACRO_tag], TAG_MACRO
    movzx   eax, byte [rel def_nparams]
    mov     [r13 + MACRO_min_params], al
    mov     [r13 + MACRO_max_params], al
    movzx   eax, byte [rel def_func]
    mov     [r13 + MACRO_flags], al
    mov     [r13 + MACRO_name], r12
    mov     [r13 + MACRO_ntokens], r15d
    mov     eax, r15d
    inc     eax
    imul    esi, eax, TOKEN_SIZE
    mov     rdi, [rbx + PREP_arena]
    call    arena_alloc
    test    rax, rax
    jnz     .fail
    mov     [r13 + MACRO_tokens], rdx
    mov     rdi, rdx
    lea     rsi, [rel def_scratch]
    mov     eax, r15d
    imul    ecx, eax, TOKEN_SIZE / 8
    rep movsq

    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, r12
    call    symbol_find
    test    rax, rax
    jnz     .create
    mov     byte [rdx + SYMBOL_kind], SYM_MACRO    ; a redefinition
    mov     [rdx + SYMBOL_value], r13
    xor     eax, eax
    jmp     .ret
.create:
    sub     rsp, SYMBOL_SIZE
    mov     rdi, rsp
    mov     rcx, SYMBOL_SIZE / 8
    xor     eax, eax
    rep stosq
    mov     byte [rsp + SYMBOL_tag], TAG_SYMBOL
    mov     byte [rsp + SYMBOL_kind], SYM_MACRO
    mov     [rsp + SYMBOL_name], r12
    mov     [rsp + SYMBOL_value], r13
    mov     rdi, [rbx + PREP_ctx]
    mov     rsi, rsp
    call    symbol_add
    add     rsp, SYMBOL_SIZE
    jmp     .ret

.bad:
    mov     rax, EXIT_DEFINE
.fail:
    mov     byte [rel prep_noexpand], 0
.ret:
    mov     byte [rel def_eager], 0
    mov     byte [rel def_icase], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     rdi, rbx
    extern  parser_evaluate_expression
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .done

    ; 3. Push the level with the result
    xor     esi, esi
    test    rdx, rdx
    setne   sil
    mov     rdi, rbx
    call    prep_cond_enter
    jmp     .done

.already_skipping:
    xor     esi, esi
    mov     rdi, rbx
    call    prep_cond_enter

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
    
    mov     rdi, rbx
    mov     esi, 1                 ; %else always "matches" if nothing did yet
    call    prep_cond_branch

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
    ; 2. Decrement total depth (guard against underflow)
    cmp     byte [rbx + PREP_depth], 0
    je      .done
    dec     byte [rbx + PREP_depth]

.done:
    xor     rax, rax
    pop     rbx
    epilogue

.error_no_if:
    mov     rax, EXIT_ERROR
    pop     rbx
    epilogue

; ---- prep_skip_macro_block & prep_skip_rep_block ----
global prep_skip_macro_block
prep_skip_macro_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %macro)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, rbx                   ; the expansion first, then the file
    mov     rsi, r13
    call    prep_raw_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "macro"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    
    ; Compare with "endmacro"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_endm]
    call    str_cmp
    test    rax, rax
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

global prep_skip_rep_block
prep_skip_rep_block:
    prologue
    push    rbx
    push    r12
    push    r13
    push    rax                    ; Alignment padding
    
    mov     rbx, rdi               ; rbx = PrepState
    mov     r12, 1                 ; r12 = nesting depth (we already saw the opening %rep)
    
    sub     rsp, TOKEN_SIZE
    mov     r13, rsp               ; r13 = temp token buffer

.loop:
    mov     rdi, [rbx + PREP_lexer]
    mov     rsi, r13
    call    lexer_next
    test    rax, rax
    jnz     .done                  ; stop on lexer error
    
    cmp     byte [r13 + TOKEN_kind], TOK_EOF
    je      .done                  ; stop on EOF
    
    cmp     byte [r13 + TOKEN_kind], TOK_DIRECTIVE
    jne     .loop
    
    ; Compare with "rep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in
    
    ; Compare with "endrep"
    mov     rdi, [r13 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out
    
    jmp     .loop

.nest_in:
    inc     r12
    jmp     .loop

.nest_out:
    dec     r12
    test    r12, r12
    jnz     .loop

.done:
    add     rsp, TOKEN_SIZE
    pop     rcx                    ; Alignment padding
    pop     r13
    pop     r12
    pop     rbx
    epilogue
    ret

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
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     r12, [rsp]             ; r12 = name token
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_IDENT
    jne     .error_expected_ident

    ; 2. Lex the parameter count
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     r13, [rsp + 32]        ; r13 = param count token
    mov     rsi, r13
    call    prep_raw_next
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
    mov     r14, rdx
    mov     r15, rdx               ; Default max = min
    
    ; Peek for hyphen '-'
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     rsi, [rsp + 64]
    call    prep_raw_peek
    cmp     byte [rsp + 64 + TOKEN_kind], TOK_MINUS
    jne     .no_hyphen
    
    ; Consume hyphen
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     rsi, [rsp + 64]
    call    prep_raw_next
    
    ; Lex next for max
    mov     rdi, rbx                   ; the expansion first, then the file
    lea     rsi, [rsp + 64]
    call    prep_raw_next
    
    cmp     byte [rsp + 64 + TOKEN_kind], TOK_NUMBER
    jne     .check_star
    mov     rdi, [rsp + 64 + TOKEN_value]
    call    str_to_int
    mov     r15, rdx
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
    ; The body must be one contiguous token array, so reserve it up front:
    ; lexer_next allocates token value strings from this same arena, and
    ; allocating the slots one at a time would interleave them with strings.
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, MACRO_BODY_CAPACITY * TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx
    xor     r14, r14               ; r14 = token count
    mov     r13, 1                 ; r13 = nesting depth

.capture_loop:
    cmp     r14, MACRO_BODY_CAPACITY
    jge     .error_macro_def       ; body exceeds the reserved capacity
    mov     r12, [r15 + MACRO_tokens]
    mov     rax, r14
    imul    rax, TOKEN_SIZE
    add     r12, rax               ; r12 = current token slot

    mov     rdi, rbx                   ; the expansion first, then the file
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .error_eof

    ; Check for % directive
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .store_token

    ; It's a TOK_DIRECTIVE. Check for "macro" or "endmacro"
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_macro]
    call    str_cmp
    test    rax, rax
    jz      .nest_in

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endm]
    call    str_cmp
    test    rax, rax
    jz      .nest_out

    jmp     .store_token

.nest_in:
    inc     r13                    ; found nested %macro
    inc     r14
    jmp     .capture_loop

.nest_out:
    dec     r13
    test    r13, r13
    jz      .found_endmacro        ; Outermost %endmacro found!
    
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
    
    ; zero out (all of it: 48 bytes left the rest as stack garbage)
    mov     rcx, SYMBOL_SIZE / 8
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
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    and     rsp, -16               ; 16-byte alignment
    sub     rsp, 16                ; [rbp - 56]: total token count, [rbp - 64]: temp slot
    
    mov     rbx, rdi               ; rbx = PREP state

    ; 1. Get repeat count. It is an expression, not just a literal:
    ;    "%rep %%len" drives compile_time_hash.
    mov     rdi, rbx
    call    prep_drop_stale_newline
    mov     rdi, rbx
    call    parser_evaluate_expression
    test    rax, rax
    jnz     .error
    mov     r14, rdx               ; r14 = count

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
    mov     byte [r15 + MACRO_max_params], 0
    
    ; 3. Capture tokens until %endrep
    mov     qword [rbp - 56], 0    ; Total token count = 0
    xor     r13, r13               ; Nesting depth = 0

    ; Reserve the body as one contiguous block: lexer_next allocates token
    ; value strings from this same arena, so slots taken one at a time would
    ; be interleaved with those strings.
    mov     rdi, [rbx + PREP_arena]
    mov     rsi, REP_BODY_CAPACITY * TOKEN_SIZE
    call    arena_alloc
    test    rax, rax
    jnz     .error
    mov     [r15 + MACRO_tokens], rdx

.capture:

    ; Point at the next slot in the reserved body block
    mov     rax, [rbp - 56]
    cmp     rax, REP_BODY_CAPACITY
    jge     .error
    imul    rax, TOKEN_SIZE
    mov     r12, [r15 + MACRO_tokens]
    add     r12, rax               ; r12 = current token slot

    mov     rdi, rbx
    mov     rsi, r12
    call    prep_raw_next
    test    rax, rax
    jnz     .error

    cmp     byte [r12 + TOKEN_kind], TOK_EOF
    je      .error_eof

    ; Check for % directive
    cmp     byte [r12 + TOKEN_kind], TOK_DIRECTIVE
    jne     .store_token

    ; It's a TOK_DIRECTIVE. Check for "rep" or "endrep"
    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_rep]
    call    str_cmp
    test    rax, rax
    jz      .nest_in

    mov     rdi, [r12 + TOKEN_value]
    lea     rsi, [dir_endrep]
    call    str_cmp
    test    rax, rax
    jz      .nest_out

    jmp     .store_token

.nest_in:
    inc     r13                    ; found nested %rep
    inc     qword [rbp - 56]
    jmp     .capture

.nest_out:
    test    r13, r13
    jz      .captured              ; outermost %endrep found!
    
    dec     r13
    inc     qword [rbp - 56]
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
    mov     dword [rdx + MACROEXP_rep_count], r14d ; set repetition count
    
    xor     rax, rax               ; success
    jmp     .done

.error_eof:
.error:
    mov     rax, 1                 ; error
    jmp     .done

.done:
    mov     r15, [rbp - 40]
    mov     r14, [rbp - 32]
    mov     r13, [rbp - 24]
    mov     r12, [rbp - 16]
    mov     rbx, [rbp - 8]
    mov     rsp, rbp
    pop     rbp
    ret

[SECTION .bss]
prep_noexpand: resb 1              ; 1: identifiers are not macro calls (a directive reads a name)
def_eager:     resb 1              ; 1: %xdefine, expand the body now
def_func:      resb 1              ; MACRO_FLAG_FUNC for NAME(a, b)
def_nparams:   resb 1
fn_depth:      resd 1              ; parenthesis depth in a function-like call
def_pnames:    resq 9              ; parameter names of a function-like %define
def_scratch:   resb DEFINE_MAX_TOKENS * TOKEN_SIZE
def_icase:     resb 1              ; 1: %idefine
idefine_count: resd 1              ; %idefine names so far
icase_buf:     resb 256            ; a name's case-insensitive key
