; ============================================================================
; File        : src/frontend/preproc/macro/directives.inc
; Part of     : src/frontend/preproc/macro.s (%included by it, in this place)
; Contents    : prep_handle_directive (the % directive dispatch), %include
; ============================================================================


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
    mov     eax, [r13 + TOKEN_line]
    mov     [rel dir_line], eax    ; its line: what is left of it (prep_trailing)
    
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
    lea     rsi, [dir_require]
    call    str_cmp
    test    rax, rax
    jz      .do_require

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

    ; the names below dispatch through dir_more (name, handler, 16 bytes)
    lea     r8, [rel dir_more]
.more:
    cmp     byte [r8], 0
    je      .more_done
    push    r8
    mov     rdi, [r12 + TOKEN_value]
    mov     rsi, r8
    call    str_cmp
    pop     r8
    test    rax, rax
    jz      .more_hit
    add     r8, 16
    jmp     .more
.more_hit:
    movzx   eax, byte [r8 + 15]            ; handler number
    cmp     eax, 64
    jae     .m_iftest                      ; %ifnum family: also while skipping
    cmp     eax, 20
    je      .m_ifn                         ; conditionals: also while skipping
    cmp     eax, 21
    je      .m_elifn
    cmp     eax, 23
    je      .m_rmacro                      ; skipping handled like %macro
    cmp     eax, 24
    je      .m_irmacro
    cmp     eax, 10
    je      .m_imacro                      ; skipping handled like %macro
    cmp     eax, 4
    jb      .more_cond                     ; %ifidn family: also while skipping
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
.more_cond:
    lea     rcx, [rel .more_table]
    jmp     [rcx + rax*8]
.more_table:
    dq      .m_ifidn, .m_ifnidn, .m_ifnidni, .m_elifidn
    dq      .m_warning, .m_fatal, .m_exitrep, .m_strcat, .m_deftok
    dq      .m_defstr, .m_imacro, .m_exitmacro, .m_repl, .m_line, .m_use
    dq      .m_pragma, .m_clear, .m_iassign, .m_defalias, .m_idefstr
    dq      .m_ifn, .m_elifn, .m_ixdefine, .m_rmacro, .m_irmacro
    dq      .m_depend, .m_pathsearch, .m_stacksize, .m_arg, .m_local
    dq      .m_undefalias, .m_idefalias, .m_aliases
.m_stacksize:
    mov     rdi, rbx
    call    prep_handle_stacksize
    jmp     .done_cleanup
.m_arg:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_frame
    jmp     .done_cleanup
.m_local:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_frame
    jmp     .done_cleanup
.m_ifn:
    mov     byte [rel cond_negate], 1      ; %ifn: %if, the other way
    mov     rdi, rbx
    call    prep_handle_if
    jmp     .done_cleanup
.m_elifn:
    mov     byte [rel cond_negate], 1
    mov     rdi, rbx
    call    prep_handle_elif
    jmp     .done_cleanup
.m_ixdefine:
    mov     byte [rel def_icase], 1        ; %ixdefine: both
    mov     byte [rel def_eager], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup
.m_irmacro:
    mov     eax, 10                        ; %irmacro is %imacro (recursion
    jmp     .m_imacro                      ; is allowed, up to a depth)
.m_rmacro:
    jmp     .do_macro                      ; %rmacro is %macro
.m_depend:
    mov     rdi, rbx
    call    prep_handle_depend
    jmp     .done_cleanup
.m_pathsearch:
    mov     rdi, rbx
    call    prep_handle_pathsearch
    jmp     .done_cleanup
.m_iftest:
    sub     eax, 64
    mov     edx, eax
    and     edx, 3                         ; negate / elif
    shr     eax, 2
    mov     esi, eax                       ; IFT_*
    mov     rdi, rbx
    call    prep_handle_iftest
    jmp     .done_cleanup
.m_defstr:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_defstr
    jmp     .done_cleanup
.m_idefstr:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_defstr
    jmp     .done_cleanup
.m_imacro:
    mov     byte [rel mdef_icase], 1
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_macro_normal
    mov     byte [rel mdef_icase], 0
    jmp     .do_macro
.m_exitmacro:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_exit
    jmp     .done_cleanup
.m_repl:
    mov     rdi, rbx
    call    prep_handle_repl
    jmp     .done_cleanup
.m_line:
    mov     rdi, rbx
    call    prep_handle_line
    jmp     .done_cleanup
.m_use:
    mov     rdi, rbx
    call    prep_handle_use
    jmp     .done_cleanup
.m_pragma:
    mov     rdi, rbx
    call    prep_handle_pragma
    mov     rdi, rbx
    call    prep_drain_line
    xor     eax, eax
    jmp     .done_cleanup
.m_clear:
    mov     rdi, rbx
    call    prep_handle_clear
    jmp     .done_cleanup
.m_iassign:
    mov     rdi, rbx
    call    prep_handle_iassign
    jmp     .done_cleanup
.m_defalias:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_defalias
    jmp     .done_cleanup
.m_idefalias:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_defalias
    jmp     .done_cleanup
.m_undefalias:
    mov     rdi, rbx
    mov     esi, 2
    call    prep_handle_defalias
    jmp     .done_cleanup
.m_aliases:
    mov     rdi, rbx
    mov     esi, 3
    call    prep_handle_defalias
    jmp     .done_cleanup
.m_ifidn:
    mov     rdi, rbx
    call    prep_handle_ifidn
    jmp     .done_cleanup
.m_ifnidn:
    mov     rdi, rbx
    call    prep_handle_ifnidn
    jmp     .done_cleanup
.m_ifnidni:
    mov     rdi, rbx
    call    prep_handle_ifnidni
    jmp     .done_cleanup
.m_elifidn:
    mov     rdi, rbx
    call    prep_handle_elifidn
    jmp     .done_cleanup
.m_warning:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_message
    jmp     .done_cleanup
.m_fatal:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_message
    jmp     .done_cleanup
.m_exitrep:
    mov     rdi, rbx
    call    prep_handle_exitrep
    jmp     .done_cleanup
.m_strcat:
    mov     rdi, rbx
    xor     esi, esi
    call    prep_handle_strtok
    jmp     .done_cleanup
.m_deftok:
    mov     rdi, rbx
    mov     esi, 1
    call    prep_handle_strtok
    jmp     .done_cleanup
.more_done:

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
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_inc
    jmp     .done_cleanup

.do_require:
    ; NASM 3's %require: an %include of a file not read yet
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel inc_require], 1
    mov     rdi, rbx
    call    prep_handle_inc
    jmp     .done_cleanup

.do_def:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_assign:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup                  ; don't execute when skipping
    mov     rdi, rbx
    call    prep_handle_assign
    jmp     .done_cleanup

.do_push:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_push
    jmp     .done_cleanup

.do_pop:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_pop
    jmp     .done_cleanup

.do_ifctx:
    mov     rdi, rbx
    mov     esi, IFT_CTX
    xor     edx, edx
    call    prep_handle_iftest
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
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_strlen
    jmp     .done_cleanup

.do_substr:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_substr
    jmp     .done_cleanup

.do_idefine:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_icase], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_xdefine:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     byte [rel def_eager], 1
    mov     rdi, rbx
    call    prep_handle_def
    jmp     .done_cleanup

.do_undef:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    call    prep_handle_undef
    jmp     .done_cleanup

.do_rotate:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup
    mov     rdi, rbx
    extern  prep_handle_rotate
    call    prep_handle_rotate             ; src/frontend/preproc/rotate.s
    jmp     .done_cleanup




.do_if:
    mov     rdi, rbx
    call    prep_handle_if
    jmp     .done_cleanup

.do_ifdef:
    mov     rdi, rbx
    mov     esi, IFT_DEF
    xor     edx, edx
    call    prep_handle_iftest
    jmp     .done_cleanup

.do_ifndef:
    mov     rdi, rbx
    mov     esi, IFT_DEF
    mov     edx, 1                         ; negated
    call    prep_handle_iftest
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
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_macro_normal
    mov     rdi, rbx
    call    prep_skip_macro_block
    jmp     .done_cleanup
.do_macro_normal:
    mov     rax, [r12 + TOKEN_value]       ; macro / imacro / rmacro: messages
    mov     [rel mdef_dir], rax
    mov     rdi, rbx
    call    macro_handle_def
    jmp     .done_cleanup

.do_unmacro:
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .done_cleanup          ; inside a skipped block: ignore entirely
    mov     rdi, rbx
    call    prep_handle_unmacro
    jmp     .done_cleanup

.do_rep:
    cmp     word [rbx + PREP_skip_depth], 0
    je      .do_rep_normal
    mov     rdi, rbx
    call    prep_skip_rep_block
    jmp     .done_cleanup
.do_rep_normal:
    mov     rdi, rbx
    call    prep_handle_rep
    jmp     .done_cleanup

.do_endrep:
    mov     rax, EXIT_NO_REP               ; no %rep is being read
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
    cmp     word [rbx + PREP_skip_depth], 0
    jne     .discard_quietly
    ; %endmacro / %endm with no %macro being read
    mov     rdi, [r12 + TOKEN_value]
    call    prep_is_macro_end
    jnz     .not_macro_end
    mov     rdi, [r12 + TOKEN_value]
    call    error_set_subject
    mov     rax, EXIT_NOT_DEFINING
    jmp     .done_cleanup
.not_macro_end:
    mov     rax, [r12 + TOKEN_value]
    test    rax, rax
    jz      .discard_quietly
    movzx   eax, byte [rax]
    or      eax, 0x20
    sub     eax, 'a'
    cmp     eax, 25
    ja      .discard_quietly
    mov     rdi, [r12 + TOKEN_value]
    call    error_set_subject
    mov     rax, EXIT_UNKNOWN_DIRECTIVE
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
; Handles the %include directive, and %require (inc_require set): the same
; but for a file an %include or %require read already in this pass, which
; it leaves (NASM 3; the source itself is not one: it is read once more).
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
    movzx   eax, byte [rel inc_require]
    mov     byte [rel inc_require], 0
    mov     [rsp + 32], rax        ; 1: %require
    
    ; 1. Get filename token - through the preprocessor: the %include of a
    ;    %rep or macro body comes from that body ("%rep 5 / %include
    ;    'x.inc' / %endrep", NASM's br890790), and a %define names a file
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .error
    mov     r12, rdx

    cmp     byte [r12 + TOKEN_kind], TOK_STRING
    je      .name_string
    ; 'file.inc': eight characters or fewer lex as a character constant
    cmp     byte [r12 + TOKEN_kind], TOK_CHAR
    jne     .error_expected_string
    mov     rdx, r12
    call    prep_token_text
    mov     r12, rax                 ; r12 = filename string
    jmp     .name_done
.name_string:
    mov     r12, [r12 + TOKEN_value] ; r12 = filename string
.name_done:

    ; 2. Check include depth
    mov     r8, [rbx + PREP_ctx]
    mov     r9, [r8 + ASMCTX_inc_ctx]
    xor     r14, r14               ; r14 = depth
    test    r9, r9
    jz      .depth_ok
    movzx   r14, word [r9 + INCLUDECTX_depth]
    inc     r14
    cmp     r14, MAX_INCLUDES
    jge     .error_too_deep
.depth_ok:
    mov     [rsp + 56], r14         ; save depth at [rsp+56]

    ; 3. Open file: as named, then in each -I directory
    mov     rdi, r12
    extern  incpath_open
    call    incpath_open
    test    rax, rax
    jnz     .error_open
    mov     r12, rcx               ; the name it was found under
    mov     r13, rdx               ; r13 = fd
    mov     edi, r13d
    call    prep_file_seen
    test    eax, eax
    jz      .first_read
    cmp     qword [rsp + 32], 0
    je      .first_read
    mov     rdi, r13               ; %require of a file read already
    call    io_close
    xor     eax, eax
    jmp     .done
.first_read:

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
    ; the body it is read from waits until the file has been read
    mov     r11, [r10 + ASMCTX_mac_exp]
    mov     [r9 + INCLUDECTX_mac_exp], r11
    mov     qword [r10 + ASMCTX_mac_exp], 0
    
    mov     [r9 + INCLUDECTX_buf], r15
    mov     [r9 + INCLUDECTX_size], r14
    
    mov     r9, [rsp + 40]         ; restore IncludeCtx ptr
    
    mov     rax, [rbx + PREP_lexer]
    mov     [r9 + INCLUDECTX_lexer], rax
    movzx   rax, word [rsp + 56]   ; depth
    mov     word [r9 + INCLUDECTX_depth], ax
    
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
    mov     rax, EXIT_INC_NAME
    jmp     .done

.error_too_deep:
    mov     rax, EXIT_INC_DEPTH
    jmp     .done

.error_open:
    mov     rdi, r12                   ; "unable to open include file `x'"
    call    error_set_subject
    mov     rax, EXIT_INC_NOT_FOUND
    jmp     .done

.error_size:
.error_mmap:
    mov     rdi, r12
    call    error_set_subject
    mov     rax, EXIT_FILE_READ
    jmp     .done

.error:
    jmp     .done                      ; the lexer's own code

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
