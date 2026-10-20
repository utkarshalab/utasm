;
; ============================================================================
; File        : middle/semantic/namespace.s
; Project     : utasm
; Description : Namespaces and modules.
;
;     namespace net               module net
;         send: ...                   export send
;     endnamespace                    send: ...
;                                     (the file's end closes it)
;
;   A name defined inside is net::send ("namespace" nests: net::tcp::x).
;   A name used inside is looked for in the innermost namespace first,
;   then each one out, then outside them all: "log" in net is net::log if
;   there is one, else log. "::log" is always the outer one.
;   - namespace NAME ... endnamespace: its names are public, but those
;     "private NAME, ..." names, used only from inside it;
;   - module NAME: a namespace to the end of the file it is in, its names
;     private (to it) but those "export NAME, ..." names.
;   A name used before its definition is resolved at the end (ns_finish):
;   the string the reference holds is written over with the name it turned
;   out to be (never longer). Two checks there:
;   - a name taken from an outer namespace where an inner one defined it
;     later is an error (it would mean the inner one had it come first);
;   - a private name used from outside its namespace / module is an error.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern  preprocessor_next_token, preprocessor_peek_token, str_cmp_kw
extern  symbol_find, known_lookup, arena_alloc, mem_reserve
extern  error_set_location, error_set_subject, error_loc_file, error_loc_line
extern  masm_enabled, gas_names, global_ctx

%define NS_MAX      32              ; namespaces open at once
%define NS_PATH_CAP 1024            ; "a::b::c"
%define NS_BUF_CAP  8192            ; a name built (path, name, suffix)
%define NR_CAP      (1 << 20)       ; references recorded
%define NR_SIZE     40
%define NR_ORIG     0               ; the name as written
%define NR_RES      8               ; the name it resolved to (rewritten: L = -1)
%define NR_PATH     16              ; the namespace path where it was used
%define NR_FILE     24
%define NR_LINE     32
%define NR_LEVEL    36              ; the level its name was found at; -1: not yet
%define NV_SLOTS    (1 << 16)       ; private / exported names (a hash)
%define NV_SIZE     24
%define NV_NAME     0
%define NV_SCOPE    8               ; the path it may be used from (and inside)
%define NV_KIND     16              ; NV_PRIVATE / NV_MODULE / NV_EXPORT
%define NV_PRIVATE  1               ; "private x"
%define NV_MODULE   2               ; defined in a module (private unless exported)
%define NV_EXPORT   3               ; "export x"

[SECTION .bss]
global ns_depth
ns_depth:       resd 1              ; namespaces open
ns_done:        resb 1              ; ns_finish ran: nothing more resolved
alignb 8
ns_plen:        resq 1              ; length of ns_path
ns_oldlen:      resq NS_MAX         ; ns_plen before each was opened
ns_inc:         resq NS_MAX         ; a module: the IncludeCtx of its file (0: the main one)
ns_pstr:        resq NS_MAX + 1     ; the path at each depth (a copy that stays)
ns_refs:        resq 1              ; the references recorded
ns_nref:        resq 1
ns_vis:         resq 1              ; the private / exported names
ns_nvis:        resq 1
ns_kind:        resb NS_MAX         ; 0: namespace, 1: module
ns_path:        resb NS_PATH_CAP    ; the namespaces open, "a::b"
ns_buf:         resb NS_BUF_CAP     ; a name built

[SECTION .rodata]
s_namespace:    db "namespace", 0
s_endnamespace: db "endnamespace", 0
s_module:       db "module", 0
s_export:       db "export", 0
s_private:      db "private", 0
s_empty:        db 0

[SECTION .text]

;*
; * [ns_word]
; * Purpose: Is the statement's first word, rdi, one of namespace,
; *   endnamespace, module, export, private (utasm's syntax: not under %use
; *   masm, nor GNU's)? Then it is handled.
; * Input  : RDI = the word, RBX = PrepState
; * Output : EAX = 0: not one; 1: handled, RDX = OK or an error code
; ;
global ns_word
ns_word:
    cmp     byte [rel masm_enabled], 0
    jne     .no_word
    cmp     byte [rel gas_names], 0
    jne     .no_word
    push    r12
    mov     r12, rdi
    lea     rsi, [rel s_namespace]
    call    str_cmp_kw
    test    rax, rax
    jz      .namespace
    mov     rdi, r12
    lea     rsi, [rel s_endnamespace]
    call    str_cmp_kw
    test    rax, rax
    jz      .end
    mov     rdi, r12
    lea     rsi, [rel s_module]
    call    str_cmp_kw
    test    rax, rax
    jz      .module
    mov     rdi, r12
    lea     rsi, [rel s_export]
    call    str_cmp_kw
    test    rax, rax
    jz      .export
    mov     rdi, r12
    lea     rsi, [rel s_private]
    call    str_cmp_kw
    test    rax, rax
    jz      .private
.no:
    pop     r12
.no_word:
    xor     eax, eax
    ret
.namespace:
    xor     r12d, r12d                     ; (the kind)
    jmp     .open
.module:
    mov     r12d, 1
.open:
    ; "namespace NAME": a name after it ("namespace:" stays a label)
    call    ns_peek_ident
    jne     .no
    call    ns_sync
    mov     rdi, rbx
    call    preprocessor_next_token
    mov     rsi, [rdx + TOKEN_value]
    mov     edx, r12d
    call    ns_push
    jmp     .handled
.end:
    call    ns_sync
    mov     eax, EXIT_NS_NO_NS
    mov     ecx, [rel ns_depth]
    test    ecx, ecx
    jz      .handled
    mov     eax, EXIT_NS_MODULE
    lea     rdx, [rel ns_kind]
    cmp     byte [rdx + rcx - 1], 1
    je      .handled
    call    ns_pop
    xor     eax, eax
    jmp     .handled
.export:
    mov     r12d, NV_EXPORT
    jmp     .names
.private:
    mov     r12d, NV_PRIVATE
.names:
    call    ns_peek_ident
    jne     .no
    call    ns_sync
    mov     eax, EXIT_NS_OUTSIDE
    cmp     dword [rel ns_depth], 0
    je      .handled
    mov     edi, r12d
    call    ns_names
.handled:
    mov     rdx, rax
    mov     eax, 1
    pop     r12
    ret

; ns_peek_ident: ZF = 1 when the next token is a name
ns_peek_ident:
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    ret

; ns_names: "export a, b" / "private a, b" - edi the kind. RAX = OK or an
; error
ns_names:
    push    r12
    push    r13
    mov     r12d, edi
.name:
    mov     rdi, rbx
    call    preprocessor_next_token
    test    rax, rax
    jnz     .ret
    mov     eax, EXIT_UNEXPECTED_TOKEN
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ret
    mov     rsi, [rdx + TOKEN_value]
    xor     edx, edx
    call    ns_qualify
    mov     ecx, [rel ns_depth]
    lea     rdx, [rel ns_pstr]
    mov     rdx, [rdx + rcx*8]             ; private: to this namespace
    mov     edi, r12d
    call    ns_vis_put
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_COMMA
    jne     .ok
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .name
.ok:
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret

; ns_push: open the namespace rsi (edx: 0 namespace, 1 module). RAX = OK
; or an error
ns_push:
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13d, edx
    mov     ecx, [rel ns_depth]
    mov     eax, EXIT_NS_DEPTH
    cmp     ecx, NS_MAX
    jae     .ret
    mov     rax, [rel ns_plen]
    lea     rdx, [rel ns_oldlen]
    mov     [rdx + rcx*8], rax
    lea     rax, [rel ns_kind]
    mov     [rax + rcx], r13b
    lea     rax, [rel global_ctx]
    mov     rax, [rax + ASMCTX_inc_ctx]
    lea     rdx, [rel ns_inc]
    mov     [rdx + rcx*8], rax
    lea     rdi, [rel ns_path]
    mov     r8, [rel ns_plen]
    test    r8, r8
    jz      .copy
    mov     word [rdi + r8], '::'
    add     r8, 2
.copy:
    mov     al, [r12]
    test    al, al
    jz      .copied
    cmp     r8, NS_PATH_CAP - 1
    jae     .deep
    mov     [rdi + r8], al
    inc     r8
    inc     r12
    jmp     .copy
.copied:
    mov     byte [rdi + r8], 0
    mov     [rel ns_plen], r8
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [r8 + 1]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     rdi, rdx
    lea     rsi, [rel ns_path]
    mov     rcx, [rel ns_plen]
    inc     rcx
    rep movsb
    mov     ecx, [rel ns_depth]
    inc     ecx
    mov     [rel ns_depth], ecx
    lea     rax, [rel ns_pstr]
    mov     [rax + rcx*8], rdx
    xor     eax, eax
.ret:
    pop     r13
    pop     r12
    ret
.deep:
    mov     ecx, [rel ns_depth]
    lea     r8, [rel ns_oldlen]
    mov     r8, [r8 + rcx*8]
    lea     rdi, [rel ns_path]
    mov     byte [rdi + r8], 0
    mov     eax, EXIT_NS_DEPTH
    jmp     .ret

; ns_pop: close the innermost. Clobbers rax, r8, r9 (not rcx)
ns_pop:
    mov     eax, [rel ns_depth]
    dec     eax
    lea     r9, [rel ns_oldlen]
    mov     r8, [r9 + rax*8]
    mov     [rel ns_plen], r8
    lea     r9, [rel ns_path]
    mov     byte [r9 + r8], 0
    mov     [rel ns_depth], eax
    ret

; ns_sync: a module whose file has ended is closed (with what is open in
; it). Clobbers rax, rcx, r8, r9
ns_sync:
    xor     ecx, ecx
.loop:
    cmp     ecx, [rel ns_depth]
    jae     .ret
    lea     rax, [rel ns_kind]
    cmp     byte [rax + rcx], 1
    jne     .next
    lea     rax, [rel ns_inc]
    mov     r8, [rax + rcx*8]
    test    r8, r8
    jz      .next                          ; (the main file's: to the end)
    lea     rax, [rel global_ctx]
    mov     rax, [rax + ASMCTX_inc_ctx]
.chain:
    test    rax, rax
    jz      .close
    cmp     rax, r8
    je      .next
    mov     rax, [rax + INCLUDECTX_parent]
    jmp     .chain
.close:
    cmp     [rel ns_depth], ecx
    jbe     .ret
    call    ns_pop
    jmp     .close
.next:
    inc     ecx
    jmp     .loop
.ret:
    ret

; ns_cur_path: RAX = the path of the namespaces open ("" for none)
ns_cur_path:
    mov     eax, [rel ns_depth]
    test    eax, eax
    jz      .none
    lea     rcx, [rel ns_pstr]
    mov     rax, [rcx + rax*8]
    ret
.none:
    lea     rax, [rel s_empty]
    ret

;*
; * [ns_qualify]
; * Purpose: The name rsi defines, as its full name: "x" in net is
; *   net::x; "::x" is x; ".x" (a local, already under its label) and a
; *   name already under the path stay. EDX = 1: it is being defined (in a
; *   module: private unless exported).
; * Input  : RSI = the name, EDX, RBX = PrepState
; * Output : RSI = the full name. Preserves every other register but RAX.
; ;
global ns_qualify
ns_qualify:
    cmp     byte [rel gas_names], 0
    jne     .quick
    cmp     byte [rel ns_done], 0
    jne     .quick
    cmp     byte [rsi], ':'
    jne     .not_outer
    cmp     byte [rsi + 1], ':'
    jne     .not_outer
    add     rsi, 2
.quick:
    ret
.not_outer:
    cmp     dword [rel ns_depth], 0
    je      .quick
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    mov     r12d, edx
    push    rsi
    call    ns_sync
    pop     rsi
    cmp     dword [rel ns_depth], 0
    je      .done
    cmp     byte [rsi], '.'
    je      .done
    ; already under the path: "net::x" in net (a local under its label)
    lea     rdi, [rel ns_path]
    mov     rcx, [rel ns_plen]
    xor     eax, eax
.pre:
    cmp     rax, rcx
    jae     .pre_end
    mov     r8b, [rdi + rax]
    cmp     r8b, [rsi + rax]
    jne     .build
    inc     rax
    jmp     .pre
.pre_end:
    cmp     byte [rsi + rax], ':'
    jne     .build
    cmp     byte [rsi + rax + 1], ':'
    je      .defined
.build:
    mov     edi, [rel ns_depth]
    lea     rax, [rel ns_pstr]
    mov     rdi, [rax + rdi*8]
    mov     ecx, -1                        ; the whole path
    call    ns_build
    call    ns_keep
    test    rax, rax
    jnz     .done
    mov     rsi, rdx
.defined:
    ; in a module: private to it unless exported
    test    r12d, r12d
    jz      .done
    mov     ecx, [rel ns_depth]
.mod:
    test    ecx, ecx
    jz      .done
    dec     ecx
    lea     rax, [rel ns_kind]
    cmp     byte [rax + rcx], 1
    jne     .mod
    lea     rax, [rel ns_pstr]
    mov     rdx, [rax + rcx*8 + 8]         ; the module's path
    mov     edi, NV_MODULE
    call    ns_vis_put
.done:
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ns_build: ns_buf = the path rdi's first ecx parts (-1: all), "::", the
; name rsi; RAX = its length. Preserves rsi, rdi
ns_build:
    push    rsi
    push    rdi
    lea     r8, [rel ns_buf]
    xor     r9d, r9d
    test    ecx, ecx
    jz      .name
    cmp     byte [rdi], 0
    je      .name                          ; (no path: the name alone)
.path:
    mov     al, [rdi]
    test    al, al
    jz      .sep
    cmp     al, ':'
    jne     .char
    cmp     byte [rdi + 1], ':'
    jne     .char
    dec     ecx
    jz      .sep
    mov     word [r8 + r9], '::'
    add     r9, 2
    add     rdi, 2
    jmp     .path
.char:
    mov     [r8 + r9], al
    inc     r9
    inc     rdi
    cmp     r9, NS_PATH_CAP
    jb      .path
.sep:
    mov     word [r8 + r9], '::'
    add     r9, 2
.name:
    mov     al, [rsi]
    mov     [r8 + r9], al
    test    al, al
    jz      .end
    inc     rsi
    inc     r9
    cmp     r9, NS_BUF_CAP - 64
    jb      .name
    mov     byte [r8 + r9], 0
.end:
    mov     rax, r9
    pop     rdi
    pop     rsi
    ret

; ns_parts: RAX = the parts of the path rdi ("" 0, "a" 1, "a::b" 2)
ns_parts:
    xor     eax, eax
    cmp     byte [rdi], 0
    je      .ret
    inc     eax
    mov     rcx, rdi
.loop:
    mov     dl, [rcx]
    test    dl, dl
    jz      .ret
    inc     rcx
    cmp     dl, ':'
    jne     .loop
    cmp     byte [rcx], ':'
    jne     .loop
    inc     rcx
    inc     eax
    jmp     .loop
.ret:
    ret

; ns_keep: RDX = a copy of ns_buf that stays (RAX = OK or an error)
ns_keep:
    lea     rdi, [rel ns_buf]
    xor     ecx, ecx
.len:
    cmp     byte [rdi + rcx], 0
    je      .alloc
    inc     rcx
    jmp     .len
.alloc:
    push    rcx
    push    rcx
    mov     rdi, [rbx + PREP_arena]
    lea     rsi, [rcx + 1]
    call    arena_alloc
    pop     rcx
    pop     rcx
    test    rax, rax
    jnz     .ret
    push    rdx
    mov     rdi, rdx
    lea     rsi, [rel ns_buf]
    inc     rcx
    rep movsb
    pop     rdx
    xor     eax, eax
.ret:
    ret

; ns_defined: EAX = 1 when the name rsi is defined (or pass 2 knows it).
; Preserves rsi, rbx, r12-r15
ns_defined:
    push    rsi
    lea     rdi, [rel global_ctx]
    call    symbol_find
    pop     rsi
    test    rax, rax
    jnz     .known
    movzx   eax, byte [rdx + SYMBOL_kind]
    cmp     eax, SYM_MACRO
    je      .known
    cmp     eax, SYM_EXTERN
    je      .yes
    cmp     eax, SYM_UNKNOWN
    je      .known
    cmp     word [rdx + SYMBOL_section], 0
    je      .known
.yes:
    mov     eax, 1
    ret
.known:
    call    known_lookup
    test    rax, rax
    setnz   al
    movzx   eax, al
    ret

;*
; * [ns_ref]
; * Purpose: The name a use of rsi means: inside namespaces the innermost
; *   that has it, else each one out, else the name itself ("::x": the name
; *   x). One not defined yet is a copy of the innermost's name, resolved by
; *   ns_finish (written over). Every use inside a namespace, or of a
; *   qualified name, is recorded for ns_finish's checks.
; * Input  : RSI = the name, RBX = PrepState
; * Output : RSI = the name meant. Preserves every other register but RAX.
; ;
global ns_ref
ns_ref:
    cmp     byte [rel gas_names], 0
    jne     .quick
    cmp     byte [rel ns_done], 0
    jne     .quick
    cmp     byte [rsi], '.'
    je      .quick                         ; ("..@N_x": a macro's own)
    cmp     dword [rel ns_depth], 0
    jne     .full
    cmp     byte [rsi], ':'                ; outside: "::x" is x, "a::b" noted
    jne     .scan
    cmp     byte [rsi + 1], ':'
    jne     .scan
    add     rsi, 2
.scan:
    push    rsi
.scan_c:
    cmp     byte [rsi], 0
    je      .scan_none
    cmp     word [rsi], '::'
    je      .scan_q
    inc     rsi
    jmp     .scan_c
.scan_none:
    pop     rsi
.quick:
    ret
.scan_q:
    pop     rsi
.full:
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi                       ; the name as written
    push    rsi
    call    ns_sync
    pop     rsi
    call    ns_cur_path
    mov     r14, rax                       ; the path here
    cmp     byte [r12], ':'
    jne     .search
    cmp     byte [r12 + 1], ':'
    jne     .search
    lea     r13, [r12 + 2]                 ; "::x": x, as written
    mov     rdi, r14
    call    ns_parts
    mov     r15d, eax                      ; (nothing inner to check)
    jmp     .record
.search:
    mov     rdi, r14
    call    ns_parts
    mov     r15d, eax                      ; the level: innermost first
.try:
    mov     rdi, r14
    mov     ecx, r15d
    mov     rsi, r12
    call    ns_build
    lea     rsi, [rel ns_buf]
    call    ns_defined
    test    eax, eax
    jnz     .found
    dec     r15d
    jns     .try
    ; not defined yet: the innermost's name, a copy ns_finish writes over
    mov     rdi, r14
    mov     ecx, -1
    mov     rsi, r12
    call    ns_build
    call    ns_keep
    mov     r13, r12
    test    rax, rax
    jnz     .out
    mov     r13, rdx
    mov     r15d, -1
    jmp     .record
.found:
    mov     r13, r12
    test    r15d, r15d
    jz      .record                        ; (outside them all: as written)
    call    ns_keep
    test    rax, rax
    jnz     .out
    mov     r13, rdx
.record:
    mov     rax, [rel ns_refs]
    test    rax, rax
    jnz     .have
    mov     rsi, NR_CAP * NR_SIZE
    call    mem_reserve
    test    rax, rax
    jnz     .out
    mov     [rel ns_refs], rdx
    mov     rax, rdx
.have:
    mov     rcx, [rel ns_nref]
    cmp     rcx, NR_CAP
    jae     .out
    imul    rcx, rcx, NR_SIZE
    add     rax, rcx
    mov     [rax + NR_ORIG], r12
    mov     [rax + NR_RES], r13
    mov     [rax + NR_PATH], r14
    mov     rcx, [rel error_loc_file]
    mov     [rax + NR_FILE], rcx
    mov     ecx, [rel error_loc_line]
    mov     [rax + NR_LINE], ecx
    mov     [rax + NR_LEVEL], r15d
    inc     qword [rel ns_nref]
.out:
    mov     rsi, r13
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    ret

;*
; * [ns_ref_suffix]
; * Purpose: As ns_ref for a name known by another made from it - the
; *   struc rsi, by "rsi_size" (rdx the suffix): the innermost namespace's
; *   that has it. Nothing recorded; not found: rsi as it is.
; * Input  : RSI = the name, RDX = the suffix, RBX = PrepState
; * Output : RSI = the name meant. Preserves every other register but RAX.
; ;
global ns_ref_suffix
ns_ref_suffix:
    cmp     byte [rel gas_names], 0
    jne     .quick
    cmp     byte [rsi], ':'
    jne     .not_outer
    cmp     byte [rsi + 1], ':'
    jne     .not_outer
    add     rsi, 2
    ret
.not_outer:
    cmp     dword [rel ns_depth], 0
    jne     .full
.quick:
    ret
.full:
    push    rcx
    push    rdx
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi
    mov     r13, rdx
    push    rsi
    call    ns_sync
    pop     rsi
    call    ns_cur_path
    mov     r14, rax
    mov     rdi, r14
    call    ns_parts
    mov     r15d, eax
.try:
    test    r15d, r15d
    jz      .none                          ; (the name itself: as written)
    mov     rdi, r14
    mov     ecx, r15d
    mov     rsi, r12
    call    ns_build
    lea     rdi, [rel ns_buf]
    add     rdi, rax
    mov     rsi, r13
.suffix:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .suffix
    lea     rsi, [rel ns_buf]
    call    ns_defined
    test    eax, eax
    jnz     .found
    dec     r15d
    jmp     .try
.found:
    mov     rdi, r14
    mov     ecx, r15d
    mov     rsi, r12
    call    ns_build                       ; (without the suffix)
    call    ns_keep
    test    rax, rax
    jnz     .none
    mov     r12, rdx
.none:
    mov     rsi, r12
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rdx
    pop     rcx
    ret

; ---- the private / exported names: a hash of NV_SLOTS --------------------

; ns_vis_slot: RAX = the slot of the name rsi (its own, or the empty one
; it would take); 0 with no table. Preserves rsi, rdx, rdi
ns_vis_slot:
    mov     rax, [rel ns_vis]
    test    rax, rax
    jz      .ret
    push    rdi
    push    rdx
    mov     r8d, 2166136261                ; FNV-1a
    mov     rcx, rsi
.hash:
    movzx   edx, byte [rcx]
    test    edx, edx
    jz      .hashed
    xor     r8d, edx
    imul    r8d, r8d, 16777619
    inc     rcx
    jmp     .hash
.hashed:
    and     r8d, NV_SLOTS - 1
.probe:
    imul    rdi, r8, NV_SIZE
    add     rdi, [rel ns_vis]
    mov     rcx, [rdi + NV_NAME]
    test    rcx, rcx
    jz      .slot
    ; the same name?
    xor     edx, edx
.cmp:
    mov     al, [rcx + rdx]
    cmp     al, [rsi + rdx]
    jne     .next
    test    al, al
    jz      .slot
    inc     rdx
    jmp     .cmp
.next:
    inc     r8d
    and     r8d, NV_SLOTS - 1
    jmp     .probe
.slot:
    mov     rax, rdi
    pop     rdx
    pop     rdi
.ret:
    ret

; ns_vis_put: the name rsi is edi (NV_*), used from rdx's path. A module's
; own default (NV_MODULE) changes no name already noted. Preserves rsi
ns_vis_put:
    push    rdi
    push    rdx
    cmp     qword [rel ns_vis], 0
    jne     .table
    push    rsi
    mov     rsi, NV_SLOTS * NV_SIZE
    call    mem_reserve
    pop     rsi
    test    rax, rax
    jnz     .ret
    mov     [rel ns_vis], rdx
.table:
    call    ns_vis_slot
    test    rax, rax
    jz      .ret
    mov     rdx, [rsp]
    mov     edi, [rsp + 8]
    cmp     qword [rax + NV_NAME], 0
    jne     .noted
    cmp     qword [rel ns_nvis], NV_SLOTS * 3 / 4
    jae     .ret                           ; (full: no more noted)
    inc     qword [rel ns_nvis]
    mov     [rax + NV_NAME], rsi
    jmp     .set
.noted:
    cmp     edi, NV_MODULE
    je      .ret
.set:
    mov     [rax + NV_SCOPE], rdx
    mov     [rax + NV_KIND], edi
.ret:
    pop     rdx
    pop     rdi
    ret

; ns_inside: ZF = 1 when the path rdi is the path rsi or inside it
ns_inside:
    xor     ecx, ecx
.loop:
    mov     al, [rsi + rcx]
    test    al, al
    jz      .end
    cmp     al, [rdi + rcx]
    jne     .ret                           ; (ZF = 0)
    inc     rcx
    jmp     .loop
.end:
    cmp     byte [rdi + rcx], 0
    je      .ret
    test    rcx, rcx
    jz      .yes                           ; (inside "": anywhere)
    cmp     word [rdi + rcx], '::'
    ret
.yes:
    cmp     eax, eax
.ret:
    ret

;*
; * [ns_finish]
; * Purpose: All is read: a namespace still open is an error (a module
; *   ends with its file); each name used before its definition is written
; *   over with the one it is; a name taken from an outer namespace where
; *   an inner one has it, and a private name used from outside, are errors.
; * Output : RAX = OK or an error (its line and name set)
; ;
global ns_finish
ns_finish:
    xor     eax, eax
    cmp     byte [rel ns_done], 0
    jne     .ret0
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    call    ns_sync
    mov     byte [rel ns_done], 1
    ; a namespace not closed (a module's is, at its end)
    xor     ecx, ecx
.open:
    cmp     ecx, [rel ns_depth]
    jae     .refs
    lea     rax, [rel ns_kind]
    cmp     byte [rax + rcx], 0
    je      .not_closed
    inc     ecx
    jmp     .open
.not_closed:
    mov     dword [rel ns_depth], 0
    mov     eax, EXIT_NS_OPEN
    jmp     .ret
.refs:
    mov     dword [rel ns_depth], 0
    xor     r12d, r12d
.ref:
    cmp     r12, [rel ns_nref]
    jae     .ok
    imul    rbx, r12, NR_SIZE
    add     rbx, [rel ns_refs]
    inc     r12
    mov     rdi, [rbx + NR_PATH]
    call    ns_parts
    mov     r13d, eax                      ; the levels where it was used
    mov     r14d, [rbx + NR_LEVEL]
    test    r14d, r14d
    js      .resolve
    ; found at level r14: an inner one defined later would have come first
    mov     r15d, r13d
.inner:
    cmp     r15d, r14d
    jle     .private
    mov     rdi, [rbx + NR_PATH]
    mov     ecx, r15d
    mov     rsi, [rbx + NR_ORIG]
    call    ns_build
    lea     rsi, [rel ns_buf]
    call    ns_defined
    test    eax, eax
    jnz     .shadowed
    dec     r15d
    jmp     .inner
.resolve:
    ; the innermost that has it now; none: the name as written
    mov     r15d, r13d
.level:
    mov     rdi, [rbx + NR_PATH]
    mov     ecx, r15d
    mov     rsi, [rbx + NR_ORIG]
    call    ns_build
    lea     rsi, [rel ns_buf]
    call    ns_defined
    test    eax, eax
    jnz     .write
    dec     r15d
    jns     .level
    mov     rsi, [rbx + NR_ORIG]
    jmp     .copy
.write:
    lea     rsi, [rel ns_buf]
.copy:
    mov     rdi, [rbx + NR_RES]
.copy_c:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .copy_c
.private:
    ; a private name: from inside what it is private to only
    mov     rsi, [rbx + NR_RES]
    call    ns_vis_slot
    test    rax, rax
    jz      .ref
    cmp     qword [rax + NV_NAME], 0
    je      .ref
    cmp     dword [rax + NV_KIND], NV_EXPORT
    je      .ref
    mov     rsi, [rax + NV_SCOPE]
    mov     rdi, [rbx + NR_PATH]
    call    ns_inside
    je      .ref
    mov     rdi, [rbx + NR_FILE]
    mov     esi, [rbx + NR_LINE]
    call    error_set_location
    mov     rdi, [rbx + NR_RES]
    call    error_set_subject
    mov     eax, EXIT_NS_PRIVATE
    jmp     .ret
.shadowed:
    mov     rdi, [rbx + NR_FILE]
    mov     esi, [rbx + NR_LINE]
    call    error_set_location
    mov     rdi, [rbx + NR_ORIG]
    call    error_set_subject
    mov     eax, EXIT_NS_SHADOW
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.ret0:
    ret
