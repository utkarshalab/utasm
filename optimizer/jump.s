;
; ============================================
; File     : optimizer/jump.s
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
; JUMP SHORTENING (branch relaxation)
; ============================================================================
; utasm assembles in one pass. A jump to a label that is not defined yet
; (a forward jump) has to be emitted before its distance is known, so the
; encoder writes the 5/6-byte rel32 form. Most of those targets turn out
; to be close. This pass runs once all code is emitted, before
; relocations are resolved, and rewrites every forward
;     jmp  label   E9 rel32     (5 bytes)  ->  EB rel8  (2 bytes)
;     jcc  label   0F 8x rel32  (6 bytes)  ->  7x rel8  (2 bytes)
; whose target lies within reach, then moves the rest of the section up.
;
; What moving code must keep correct, and how:
;   labels                 symbols in the section are remapped
;   relocations            offsets in the section are remapped; those of
;                          shortened jumps are deleted (resolved here)
;   in-place displacements branches the encoder resolved directly
;                          (backward jumps, calls) are recorded
;                          (RELAX_FIXED) and rewritten
;   align                  padding points are recorded (RELAX_ALIGN) and
;                          re-padded for the new layout
;   $, label differences,  these turn a position into a plain number,
;   equ with a label       which cannot be updated afterwards; they mark
;                          their section frozen and it is left untouched
;
; Choosing which jumps to shorten is iterative: shortening one can bring
; another into reach, so candidates are added until nothing changes.
; Growing align padding can also push a shortened jump back out of reach;
; such a jump is put back to rel32 for good and the search repeats, so it
; always terminates. If a branch the encoder already resolved as rel8
; would no longer reach, the section is left unchanged.
;
; Only x86-64 output, only local labels in the same section (exported
; labels stay long, as in amd64_emit_branch_disp), and never under
; CTX_FLAG_DEBUG / CTX_FLAG_DWARF. -g keeps it on: the listing (-l) and
; the DWARF line table follow the moved code (lst_remap).
;
; Optimization levels (ASMCTX_opt, set by -O0/-O1/-O2):
;   -O0  nothing: every jump stays as the encoder wrote it
;   -O1  shortening only (default) - the same result NASM produces
;   -O2  also rewrites jumps, beyond what NASM does:
;          jcc L1 / jmp L2 / L1:    ->  j!cc L2       (one jump fewer)
;          jmp/jcc A, A: jmp B      ->  jmp/jcc B     (threading)
;          jmp/jcc to the next instruction  ->  removed
;        Each keeps the program's behaviour: jumps never touch flags, a
;        jcc whose both paths meet does nothing, and a jump is only
;        removed when no label and no other branch points at it.
;
; Calling convention (AMD64): rdi, rsi, rdx, rcx, r8; callee saved
; rbx, rbp, r12-r15.

; ---- record layout (one per noted event, emission order) ----
%define RX_kind       0     ; b  RELAX_* kind
%define RX_state      1     ; b  candidates: RS_* below
%define RX_cc         2     ; b  jcc condition code / FIXED width (1 or 4)
%define RX_flags      3     ; b  RF_* below
%define RX_aux32      4     ; d  candidate: reloc index; align: old padding
%define RX_sec        8     ; q  SECTION*
%define RX_pos       16     ; q  candidate/align: start; fixed: disp offset
%define RX_aux       24     ; q  target offset (old) / alignment
%define RX_end       32     ; q  first byte after the part that can change
%define RX_change    40     ; q  bytes removed here in the current layout
%define RX_SIZE      48

%define RS_LONG       0     ; candidate, not shortened (yet)
%define RS_SHORT      1     ; candidate, shortened
%define RS_FORCED     2     ; shortened once, put back for good
%define RS_NO         3     ; not eligible
%define RS_DELETE     4     ; -O2: removed entirely

%define RF_RETARGET   1     ; -O2: target changed; resolve it here, even
                            ; if it stays rel32 (its relocation is stale)
%define NO_RELOC      0xFFFFFFFF          ; RX_aux32 of a record with none

%define RELOC_DELETED 0xFFFFFFFF

extern global_ctx
extern vec_init
extern vec_push
extern arena_alloc
extern mem_copy
extern symbol_find

[SECTION .bss]
align 8
relax_vec:          resb VEC_SIZE       ; records (lib/vec.s)
rw_ctx:             resq 1              ; AsmCtx during relax_run
rw_sec:             resq 1              ; section being processed
rw_recs:            resq 1              ; its records (array of pointers)
rw_n:               resq 1              ; number of records
rw_deleted:         resq 1              ; any relocation deleted
relax_all_frozen:   resb 1              ; a position escaped somewhere unknown

[SECTION .text]

; ============================================================================
; Noting events while assembling (called by the encoder, align, parser)
; ============================================================================

; ---- relax_note --------------------------
;
; relax_note
; Appends a record for the current section. Preserves every register.
; Input    : dil = RELAX_* kind
;            rsi = position (see RX_pos)
;            rdx = aux (see RX_aux)
;            ecx = aux32 (see RX_aux32)
;            r8b = condition code / width
;
global relax_note
relax_note:
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, RX_SIZE

    lea     rbx, [rel global_ctx]
    mov     rax, [rbx + ASMCTX_curr_sec]
    test    rax, rax
    jz      .out                           ; no section: nothing to track

    mov     byte  [rsp + RX_kind], dil
    mov     byte  [rsp + RX_state], RS_LONG
    mov     byte  [rsp + RX_cc], r8b
    mov     dword [rsp + RX_aux32], ecx
    mov     [rsp + RX_sec], rax
    mov     [rsp + RX_pos], rsi
    mov     [rsp + RX_aux], rdx
    mov     qword [rsp + RX_end], 0
    mov     qword [rsp + RX_change], 0

    lea     rdi, [rel relax_vec]
    cmp     byte [rdi + VEC_tag], TAG_VEC
    je      .ready
    mov     rsi, [rbx + ASMCTX_arena]
    mov     edx, RX_SIZE
    mov     ecx, 256
    call    vec_init
    test    rax, rax
    jnz     .out                           ; out of memory: just don't track
.ready:
    lea     rdi, [rel relax_vec]
    mov     rsi, rsp
    call    vec_push

.out:
    add     rsp, RX_SIZE
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ---- relax_freeze_current ----------------
;
; relax_freeze_current
; The current position was used as a number ($): keep this section as is.
; Preserves every register.
;
global relax_freeze_current
relax_freeze_current:
    push    rax
    lea     rax, [rel global_ctx]
    mov     rax, [rax + ASMCTX_curr_sec]
    test    rax, rax
    jz      .out
    mov     byte [rax + SECTION_relax_frozen], 1
.out:
    pop     rax
    ret

; ---- relax_freeze_symref -----------------
;
; relax_freeze_symref
; A label's value was used as a number (label difference, equ): keep the
; label's section as is. A reference to a label not defined yet has an
; unknown section, so everything is kept as is.
; Preserves every register.
; Input    : rdi = SYMBOL* or 0
;            rsi = deferred (forward) symbol name or 0
;
global relax_freeze_symref
relax_freeze_symref:
    push    rax
    push    rcx
    push    rdx
    test    rdi, rdi
    jz      .deferred
    movzx   eax, word [rdi + SYMBOL_section]
    test    eax, eax
    jz      .out                           ; undefined / extern: no section
    cmp     eax, 0xFF00
    jae     .out                           ; SHN_ABS, SHN_COMMON, ...
    lea     rcx, [rel global_ctx]
    movzx   edx, word [rcx + ASMCTX_seccount]
    cmp     eax, edx
    ja      .out
    mov     rcx, [rcx + ASMCTX_sections]
    mov     rcx, [rcx + rax*8 - 8]         ; index is 1-based
    test    rcx, rcx
    jz      .out
    mov     byte [rcx + SECTION_relax_frozen], 1
    jmp     .out
.deferred:
    test    rsi, rsi
    jz      .out
    mov     byte [rel relax_all_frozen], 1
.out:
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ============================================================================
; The pass
; ============================================================================

; ---- relax_run --------------------------
;
; relax_run
; Shortens forward jumps in every section that allows it.
; Input    : rdi = AsmCtx
; Output   : rax = EXIT_OK (the pass never fails; at worst it changes
;            nothing)
;
global relax_run
relax_run:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     [rel rw_ctx], rdi
    mov     qword [rel rw_deleted], 0

    lea     rax, [rel relax_vec]
    cmp     byte [rax + VEC_tag], TAG_VEC
    jne     .done
    cmp     qword [rax + VEC_len], 0
    je      .done
    test    dword [rbx + ASMCTX_flags], CTX_FLAG_DEBUG | CTX_FLAG_DWARF
    jnz     .done
    cmp     byte [rel relax_all_frozen], 0
    jne     .done
    cmp     byte [rbx + ASMCTX_target], TARGET_AMD64
    jne     .done
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .done                          ; -O0: jumps as written

    xor     r12d, r12d                     ; r12 = section slot
.sections:
    movzx   eax, word [rbx + ASMCTX_seccount]
    cmp     r12, rax
    jae     .compact
    mov     rax, [rbx + ASMCTX_sections]
    mov     r13, [rax + r12*8]
    test    r13, r13
    jz      .next_section
    cmp     byte [r13 + SECTION_relax_frozen], 0
    jne     .next_section
    mov     rdi, r13
    call    rx_section
.next_section:
    inc     r12
    jmp     .sections

.compact:
    cmp     qword [rel rw_deleted], 0
    je      .done
    call    rx_compact_relocs
.done:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- rx_section (internal) --------------
;
; Shortens what it can in one section. Input: rdi = SECTION*.
;
rx_section:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, [rel rw_ctx]
    mov     [rel rw_sec], rdi
    mov     r12, rdi                       ; r12 = section

    ; ---- 1. collect this section's records, in emission order ----
    lea     rax, [rel relax_vec]
    mov     r13, [rax + VEC_data]          ; r13 = first record
    mov     r14, [rax + VEC_len]           ; r14 = total records
    xor     ecx, ecx
    xor     r15d, r15d                     ; r15 = records here
    xor     r8d, r8d                       ; r8  = candidates here
.count:
    cmp     rcx, r14
    jae     .counted
    imul    rax, rcx, RX_SIZE
    add     rax, r13
    cmp     [rax + RX_sec], r12
    jne     .count_next
    inc     r15
    cmp     byte [rax + RX_kind], RELAX_JCC
    ja      .count_next
    inc     r8
.count_next:
    inc     rcx
    jmp     .count
.counted:
    test    r8, r8
    jz      .ret                           ; no candidates here

    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r15*8]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel rw_recs], rdx
    mov     [rel rw_n], r15
    mov     r9, rdx                        ; r9 = output slot
    xor     ecx, ecx
.fill:
    cmp     rcx, r14
    jae     .filled
    imul    rax, rcx, RX_SIZE
    add     rax, r13
    cmp     [rax + RX_sec], r12
    jne     .fill_next
    mov     [r9], rax
    add     r9, 8
.fill_next:
    inc     rcx
    jmp     .fill
.filled:

    ; ---- 2. prepare each record ----
    xor     r15d, r15d
.prep:
    cmp     r15, [rel rw_n]
    jae     .prepared
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]             ; r13 = record
    mov     qword [r13 + RX_change], 0
    movzx   eax, byte [r13 + RX_kind]
    cmp     eax, RELAX_FIXED
    je      .prep_fixed
    cmp     eax, RELAX_ALIGN
    je      .prep_align
    mov     rdi, r13
    call    rx_prepare_candidate
    jmp     .prep_next
.prep_fixed:
    mov     rax, [r13 + RX_pos]
    mov     [r13 + RX_end], rax
    jmp     .prep_next
.prep_align:
    mov     eax, [r13 + RX_aux32]          ; old padding
    add     rax, [r13 + RX_pos]
    mov     [r13 + RX_end], rax
.prep_next:
    inc     r15
    jmp     .prep
.prepared:

    ; ---- 2b. -O2: rewrite jumps before choosing sizes ----
    cmp     byte [rbx + ASMCTX_opt], OPT_SIZE
    jb      .again
    call    rx_o2

    ; ---- 3. choose the jumps to shorten ----
.again:
    call    rx_layout
    xor     r14d, r14d                     ; r14 = changed
    xor     r15d, r15d
.try:
    cmp     r15, [rel rw_n]
    jae     .tried
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    cmp     byte [r13 + RX_kind], RELAX_JCC
    ja      .try_next
    cmp     byte [r13 + RX_state], RS_LONG
    jne     .try_next
    mov     rdi, r13
    call    rx_short_disp                  ; rax = displacement if short
    cmp     rax, -128
    jl      .try_next
    cmp     rax, 127
    jg      .try_next
    mov     byte [r13 + RX_state], RS_SHORT
    mov     r14d, 1
.try_next:
    inc     r15
    jmp     .try
.tried:
    test    r14d, r14d
    jnz     .again

    ; verify the final layout; undo any shortened jump that no longer fits
    call    rx_layout
    xor     r14d, r14d
    xor     r15d, r15d
.verify:
    cmp     r15, [rel rw_n]
    jae     .verified
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    movzx   eax, byte [r13 + RX_kind]
    cmp     eax, RELAX_FIXED
    je      .verify_fixed
    cmp     eax, RELAX_JCC
    ja      .verify_next
    cmp     byte [r13 + RX_state], RS_SHORT
    jne     .verify_next
    mov     rdi, r13
    call    rx_short_disp
    cmp     rax, -128
    jl      .force_long
    cmp     rax, 127
    jle     .verify_next
.force_long:
    mov     byte [r13 + RX_state], RS_FORCED
    mov     r14d, 1
    jmp     .verify_next
.verify_fixed:
    cmp     byte [r13 + RX_cc], 1
    jne     .verify_next                   ; rel32 always reaches
    mov     rdi, [r13 + RX_aux]
    call    rx_new
    mov     rcx, rax                       ; new target
    mov     rdi, [r13 + RX_pos]
    call    rx_new                         ; new displacement offset
    inc     rax
    sub     rcx, rax
    cmp     rcx, -128
    jl      .give_up
    cmp     rcx, 127
    jg      .give_up
.verify_next:
    inc     r15
    jmp     .verify
.verified:
    test    r14d, r14d
    jnz     .again

    ; ---- 4. anything to do? ----
    xor     r15d, r15d
.any:
    cmp     r15, [rel rw_n]
    jae     .ret                           ; nothing shortened
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    cmp     byte [r13 + RX_kind], RELAX_JCC
    ja      .any_next
    cmp     byte [r13 + RX_state], RS_SHORT
    je      .apply
    cmp     byte [r13 + RX_state], RS_DELETE
    je      .apply
    test    byte [r13 + RX_flags], RF_RETARGET
    jnz     .apply
.any_next:
    inc     r15
    jmp     .any

.apply:
    call    rx_apply
    jmp     .ret

.give_up:
    ; A branch already resolved as rel8 would stop reaching: leave the
    ; section exactly as the encoder produced it.
    xor     r15d, r15d
.undo:
    cmp     r15, [rel rw_n]
    jae     .ret
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    cmp     byte [r13 + RX_state], RS_SHORT
    jne     .undo_next
    mov     byte [r13 + RX_state], RS_LONG
.undo_next:
    inc     r15
    jmp     .undo

.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- rx_prepare_candidate (internal) ----
;
; Checks that a noted jump can be shortened at all and finds its target.
; Eligible: its rel32 relocation is intact, and the target is a local
; label defined later in the same section.
; Input: rdi = record. Sets RX_end, RX_aux (target) and RX_state.
;
rx_prepare_candidate:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     rbx, [rel rw_ctx]
    mov     byte [r12 + RX_state], RS_NO
    mov     byte [r12 + RX_flags], 0

    mov     eax, 5                         ; jmp E9 rel32
    cmp     byte [r12 + RX_kind], RELAX_JMP
    je      .have_len
    mov     eax, 6                         ; jcc 0F 8x rel32
.have_len:
    add     rax, [r12 + RX_pos]
    mov     [r12 + RX_end], rax

    ; its relocation: PC32, in this section, on the jump's displacement
    mov     eax, [r12 + RX_aux32]
    cmp     eax, [rbx + ASMCTX_nrelocs]
    jae     .done
    imul    r13, rax, RELOC_SIZE
    add     r13, [rbx + ASMCTX_relocs]     ; r13 = RELOC*
    cmp     dword [r13 + RELOC_type], R_X86_64_PC32
    jne     .done
    mov     rax, [rel rw_sec]
    cmp     [r13 + RELOC_section], rax
    jne     .done
    mov     rax, [r12 + RX_end]
    sub     rax, 4
    cmp     [r13 + RELOC_offset], rax
    jne     .done

    ; its target
    mov     rdi, rbx
    mov     rsi, [r13 + RELOC_sym]
    test    rsi, rsi
    jz      .done
    call    symbol_find
    test    rax, rax
    jnz     .done
    cmp     byte [rdx + SYMBOL_kind], SYM_LABEL
    jne     .done                          ; (global or not, as NASM does)
    mov     rax, [rel rw_sec]
    mov     eax, [rax + SECTION_index]
    cmp     ax, [rdx + SYMBOL_section]
    jne     .done
    mov     rax, [rdx + SYMBOL_value]
    cmp     rax, [r12 + RX_end]
    jb      .done                          ; not a forward target
    mov     [r12 + RX_aux], rax
    mov     byte [r12 + RX_state], RS_LONG
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- rx_o2 (internal) -------------------
;
; -O2 rewrites, applied to the section's records before sizes are chosen:
;   1. jcc L1 / jmp L2 / L1:  ->  j!cc L2      (the jmp is removed)
;   2. a jump to a jmp goes straight to that jmp's target (threading)
;   3. a jump to the very next instruction is removed
; Retargeted jumps are resolved here (RF_RETARGET); removed ones become
; RS_DELETE and lose their bytes and relocation in rx_apply.
;
rx_o2:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; ---- 1. jcc over a jmp ----
    xor     r15d, r15d
.over:
    cmp     r15, [rel rw_n]
    jae     .thread
    mov     rax, [rel rw_recs]
    mov     r12, [rax + r15*8]             ; r12 = A (the jcc)
    cmp     byte [r12 + RX_kind], RELAX_JCC
    jne     .over_next
    cmp     byte [r12 + RX_state], RS_LONG
    jne     .over_next
    mov     rdi, [r12 + RX_end]            ; is a jmp right after it?
    call    rx_find_jmp_at
    cmp     rax, -1
    je      .over_next
    mov     r13, rdx                       ; r13 = B's record
    mov     r14, rax                       ; r14 = B's target
    mov     rcx, [r12 + RX_end]
    add     rcx, r8                        ; end of B
    cmp     [r12 + RX_aux], rcx            ; does A jump just past B?
    jne     .over_next
    push    r8                             ; B's length (clobbered below)
    push    r8
    mov     rdi, [r12 + RX_end]
    call    rx_is_targeted                 ; is anything pointing at B?
    pop     r8
    pop     r8
    test    eax, eax
    jnz     .over_next

    xor     byte [r12 + RX_cc], 1          ; invert the condition
    mov     [r12 + RX_aux], r14            ; ...and jump where B went
    or      byte [r12 + RX_flags], RF_RETARGET
    cmp     byte [r13 + RX_kind], RELAX_FIXED
    jne     .b_is_candidate
    ; B was resolved in place: turn its record into a removal
    mov     rax, [r12 + RX_end]
    mov     [r13 + RX_pos], rax
    add     rax, r8
    mov     [r13 + RX_end], rax
    mov     byte [r13 + RX_kind], RELAX_JMP
    mov     dword [r13 + RX_aux32], NO_RELOC
    mov     byte [r13 + RX_flags], 0
.b_is_candidate:
    mov     byte [r13 + RX_state], RS_DELETE
.over_next:
    inc     r15
    jmp     .over

    ; ---- 2. threading ----
.thread:
    xor     r15d, r15d
.thread_loop:
    cmp     r15, [rel rw_n]
    jae     .next_ins
    mov     rax, [rel rw_recs]
    mov     r12, [rax + r15*8]             ; r12 = X
    cmp     byte [r12 + RX_kind], RELAX_JCC
    ja      .thread_next
    cmp     byte [r12 + RX_state], RS_LONG
    jne     .thread_next
    mov     r13, [r12 + RX_aux]            ; r13 = current target
    mov     r14d, 8                        ; follow at most 8 jumps
.follow:
    mov     rdi, r13
    call    rx_find_jmp_at
    cmp     rax, -1
    je      .followed
    cmp     rax, r13
    je      .followed                      ; a jmp to itself: stop
    mov     r13, rax
    dec     r14d
    jnz     .follow
.followed:
    cmp     r13, [r12 + RX_aux]
    je      .thread_next
    mov     [r12 + RX_aux], r13
    or      byte [r12 + RX_flags], RF_RETARGET
.thread_next:
    inc     r15
    jmp     .thread_loop

    ; ---- 3. jumps to the next instruction ----
.next_ins:
    xor     r15d, r15d
.next_loop:
    cmp     r15, [rel rw_n]
    jae     .done
    mov     rax, [rel rw_recs]
    mov     r12, [rax + r15*8]
    cmp     byte [r12 + RX_kind], RELAX_JCC
    ja      .next_next
    cmp     byte [r12 + RX_state], RS_LONG
    jne     .next_next
    mov     rax, [r12 + RX_aux]
    cmp     rax, [r12 + RX_end]
    jne     .next_next
    mov     byte [r12 + RX_state], RS_DELETE
.next_next:
    inc     r15
    jmp     .next_loop

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- rx_find_jmp_at (internal) ----------
;
; Is there an unconditional jmp starting at offset rdi whose target is
; known here? Either an eligible jmp candidate, or a jmp the encoder
; resolved in place (EB rel8 / E9 rel32 with a RELAX_FIXED record).
; Input : rdi = offset
; Output: rax = its target offset, or -1
;         rdx = its record, r8 = its length
; Clobbers: rcx, r9
;
rx_find_jmp_at:
    xor     ecx, ecx
.loop:
    cmp     rcx, [rel rw_n]
    jae     .none
    mov     rdx, [rel rw_recs]
    mov     rdx, [rdx + rcx*8]
    cmp     byte [rdx + RX_kind], RELAX_JMP
    jne     .fixed
    cmp     [rdx + RX_pos], rdi
    jne     .next
    cmp     byte [rdx + RX_state], RS_LONG
    jne     .none
    mov     rax, [rdx + RX_aux]
    mov     r8d, 5
    ret
.fixed:
    cmp     byte [rdx + RX_kind], RELAX_FIXED
    jne     .next
    lea     r9, [rdi + 1]
    cmp     [rdx + RX_pos], r9             ; displacement right after 1 opcode byte
    jne     .next
    mov     r9, [rel rw_sec]
    mov     r9, [r9 + SECTION_data]
    movzx   eax, byte [r9 + rdi]           ; the opcode
    cmp     byte [rdx + RX_cc], 1
    jne     .fixed32
    cmp     eax, 0xEB
    jne     .none
    mov     rax, [rdx + RX_aux]
    mov     r8d, 2
    ret
.fixed32:
    cmp     eax, 0xE9
    jne     .none
    mov     rax, [rdx + RX_aux]
    mov     r8d, 5
    ret
.next:
    inc     rcx
    jmp     .loop
.none:
    mov     rax, -1
    ret

; ---- rx_is_targeted (internal) ----------
;
; Does anything point at offset rdi: a label of this section, or a
; branch (candidate or in-place) whose target it is?
; Input : rdi = offset.  Output: eax = 1 if so, else 0.
; Clobbers: rcx, rdx, r8, r9
;
rx_is_targeted:
    mov     r8, [rel rw_ctx]
    mov     r9, [rel rw_sec]
    mov     r9d, [r9 + SECTION_index]
    mov     rdx, [r8 + ASMCTX_symtab]
    xor     ecx, ecx
.syms:
    cmp     ecx, [r8 + ASMCTX_symcount]
    jae     .recs
    cmp     [rdx + SYMBOL_section], r9w
    jne     .syms_next
    cmp     [rdx + SYMBOL_value], rdi
    je      .yes
.syms_next:
    add     rdx, SYMBOL_SIZE
    inc     rcx
    jmp     .syms
.recs:
    xor     ecx, ecx
.recs_loop:
    cmp     rcx, [rel rw_n]
    jae     .no
    mov     rdx, [rel rw_recs]
    mov     rdx, [rdx + rcx*8]
    cmp     byte [rdx + RX_kind], RELAX_ALIGN
    je      .recs_next
    cmp     byte [rdx + RX_kind], RELAX_FIXED
    je      .check
    cmp     byte [rdx + RX_state], RS_NO
    je      .recs_next                     ; its aux is not a target
.check:
    cmp     [rdx + RX_aux], rdi
    je      .yes
.recs_next:
    inc     rcx
    jmp     .recs_loop
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; ---- rx_layout (internal) ---------------
;
; Recomputes, for the current choice of shortened jumps, how many bytes
; each record removes (RX_change; negative when align padding grows).
;
rx_layout:
    push    rbx
    xor     r8d, r8d                       ; r8 = bytes removed so far
    xor     ecx, ecx
.loop:
    cmp     rcx, [rel rw_n]
    jae     .done
    mov     rax, [rel rw_recs]
    mov     rbx, [rax + rcx*8]
    xor     edx, edx                       ; rdx = change here
    movzx   eax, byte [rbx + RX_kind]
    cmp     eax, RELAX_FIXED
    je      .store
    cmp     eax, RELAX_ALIGN
    je      .align
    cmp     byte [rbx + RX_state], RS_DELETE
    je      .deleted
    cmp     byte [rbx + RX_state], RS_SHORT
    jne     .store
    mov     rdx, [rbx + RX_end]
    sub     rdx, [rbx + RX_pos]
    sub     rdx, 2                         ; 3 (jmp) or 4 (jcc) bytes saved
    jmp     .store
.deleted:
    mov     rdx, [rbx + RX_end]
    sub     rdx, [rbx + RX_pos]            ; the whole jump is removed
    jmp     .store
.align:
    mov     rax, [rbx + RX_pos]
    sub     rax, r8                        ; new position of the padding
    neg     rax
    mov     r9, [rbx + RX_aux]
    dec     r9
    and     rax, r9                        ; new padding
    mov     edx, [rbx + RX_aux32]          ; old padding
    sub     rdx, rax
.store:
    mov     [rbx + RX_change], rdx
    add     r8, rdx
    inc     rcx
    jmp     .loop
.done:
    pop     rbx
    ret

; ---- rx_new (internal) -------------------
;
; Maps an old offset in the section to its offset in the current layout.
; Input: rdi = old offset. Output: rax = new offset. Clobbers: rdx, r9.
;
rx_new:
    xor     eax, eax                       ; bytes removed before rdi
    xor     edx, edx
.loop:
    cmp     rdx, [rel rw_n]
    jae     .done
    mov     r9, [rel rw_recs]
    mov     r9, [r9 + rdx*8]
    cmp     [r9 + RX_end], rdi
    ja      .done                          ; records are in position order
    add     rax, [r9 + RX_change]
    inc     rdx
    jmp     .loop
.done:
    neg     rax
    add     rax, rdi
    ret

; relax_map_offset: rx_new for the listing (lst_remap), while rx_apply
; rewrites a section
global relax_map_offset
relax_map_offset:
    jmp     rx_new

; ---- rx_short_disp (internal) -----------
;
; The rel8 displacement a candidate would have in the current layout.
; Input: rdi = record. Output: rax. Clobbers: rcx, rdx, rdi, r9.
;
rx_short_disp:
    push    rbx
    mov     rbx, rdi
    mov     rdi, [rbx + RX_aux]
    call    rx_new
    mov     rcx, rax                       ; new target
    mov     rdi, [rbx + RX_pos]
    call    rx_new                         ; new start of the jump
    add     rax, 2
    sub     rcx, rax
    mov     rax, rcx
    pop     rbx
    ret

; ---- rx_apply (internal) -----------------
;
; Rewrites the section for the chosen layout: bytes, in-place
; displacements, relocations and labels.
;
rx_apply:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8
    mov     rbx, [rel rw_ctx]
    mov     r12, [rel rw_sec]

    ; new buffer (never larger than the old contents)
    mov     rdi, [rbx + ASMCTX_arena]
    mov     rsi, [r12 + SECTION_size]
    add     rsi, 8
    call    arena_alloc
    test    rax, rax
    jnz     .out                           ; no memory: leave it unchanged
    mov     rbp, rdx                       ; rbp = new buffer

    xor     r13d, r13d                     ; r13 = old read position
    xor     r14d, r14d                     ; r14 = new write position
    xor     r15d, r15d                     ; r15 = record index
.sweep:
    cmp     r15, [rel rw_n]
    jae     .tail
    mov     rax, [rel rw_recs]
    mov     rbx, [rax + r15*8]             ; rbx = record (ctx reloaded below)
    movzx   eax, byte [rbx + RX_kind]
    cmp     eax, RELAX_ALIGN
    je      .sweep_align
    cmp     eax, RELAX_JCC
    ja      .sweep_next
    cmp     byte [rbx + RX_state], RS_DELETE
    je      .sweep_delete
    cmp     byte [rbx + RX_state], RS_SHORT
    je      .sweep_short
    test    byte [rbx + RX_flags], RF_RETARGET
    jnz     .sweep_long
    jmp     .sweep_next

.sweep_delete:
    ; -O2: drop the jump's bytes altogether
    mov     rdi, [rbx + RX_pos]
    call    .copy_to
    mov     r13, [rbx + RX_end]
    jmp     .drop_reloc

.sweep_long:
    ; -O2: a retargeted jump that stays rel32 - rewrite it in place
    mov     rdi, [rbx + RX_pos]
    call    .copy_to
    mov     rdi, [rbx + RX_aux]
    call    rx_new
    mov     rcx, rax                       ; new target
    mov     rax, [rbx + RX_end]
    sub     rax, [rbx + RX_pos]            ; 5 (jmp) or 6 (jcc)
    add     rax, r14                       ; new end of the jump
    sub     rcx, rax                       ; rel32
    cmp     byte [rbx + RX_kind], RELAX_JMP
    jne     .long_jcc
    mov     byte [rbp + r14], 0xE9
    mov     [rbp + r14 + 1], ecx
    add     r14, 5
    jmp     .long_done
.long_jcc:
    mov     al, [rbx + RX_cc]
    and     al, 0x0F
    or      al, 0x80
    mov     byte [rbp + r14], 0x0F
    mov     [rbp + r14 + 1], al
    mov     [rbp + r14 + 2], ecx
    add     r14, 6
.long_done:
    mov     r13, [rbx + RX_end]
    jmp     .drop_reloc

.sweep_short:
    ; copy up to the jump, then write the 2-byte form
    mov     rdi, [rbx + RX_pos]
    call    .copy_to
    mov     rdi, rbx
    call    rx_short_disp                  ; rax = rel8
    mov     cl, 0xEB                       ; jmp rel8
    cmp     byte [rbx + RX_kind], RELAX_JMP
    je      .have_op
    mov     cl, [rbx + RX_cc]
    and     cl, 0x0F
    or      cl, 0x70                       ; jcc rel8
.have_op:
    mov     [rbp + r14], cl
    mov     [rbp + r14 + 1], al
    add     r14, 2
    mov     r13, [rbx + RX_end]            ; skip the old 5/6 bytes

.drop_reloc:
    ; its relocation is resolved now
    mov     eax, [rbx + RX_aux32]
    cmp     eax, NO_RELOC
    je      .sweep_next
    imul    rax, rax, RELOC_SIZE
    mov     rcx, [rel rw_ctx]
    add     rax, [rcx + ASMCTX_relocs]
    mov     dword [rax + RELOC_type], RELOC_DELETED
    mov     qword [rel rw_deleted], 1
    jmp     .sweep_next

.sweep_align:
    mov     rdi, [rbx + RX_pos]
    call    .copy_to
    mov     ecx, [rbx + RX_aux32]
    sub     rcx, [rbx + RX_change]         ; new padding
    xor     eax, eax                       ; fill: 0 for data
    cmp     byte [r12 + SECTION_type], SEC_TEXT
    jne     .pad
    mov     al, 0x90                       ; nop for x86-64 code
.pad:
    test    rcx, rcx
    jz      .padded
    mov     [rbp + r14], al
    inc     r14
    dec     rcx
    jmp     .pad
.padded:
    mov     r13, [rbx + RX_end]            ; skip the old padding
.sweep_next:
    inc     r15
    jmp     .sweep

.tail:
    mov     rdi, [r12 + SECTION_size]
    call    .copy_to

    ; in-place displacements, recomputed for the new layout
    xor     r15d, r15d
.fixed:
    cmp     r15, [rel rw_n]
    jae     .fixed_done
    mov     rax, [rel rw_recs]
    mov     rbx, [rax + r15*8]
    cmp     byte [rbx + RX_kind], RELAX_FIXED
    jne     .fixed_next
    mov     rdi, [rbx + RX_aux]
    call    rx_new
    mov     rcx, rax                       ; new target
    mov     rdi, [rbx + RX_pos]
    call    rx_new
    mov     r8, rax                        ; new displacement offset
    movzx   edx, byte [rbx + RX_cc]        ; width
    add     rax, rdx                       ; end of the displacement
    sub     rcx, rax
    cmp     edx, 1
    jne     .fixed32
    mov     [rbp + r8], cl
    jmp     .fixed_next
.fixed32:
    mov     [rbp + r8], ecx
.fixed_next:
    inc     r15
    jmp     .fixed
.fixed_done:

    ; install the new contents
    mov     rdi, [r12 + SECTION_data]
    mov     rsi, rbp
    mov     rdx, r14
    call    mem_copy
    mov     [r12 + SECTION_size], r14

    ; relocations located in this section
    mov     rbx, [rel rw_ctx]
    xor     r15d, r15d
.relocs:
    cmp     r15d, [rbx + ASMCTX_nrelocs]
    jae     .relocs_done
    imul    r13, r15, RELOC_SIZE
    add     r13, [rbx + ASMCTX_relocs]
    cmp     [r13 + RELOC_section], r12
    jne     .relocs_next
    cmp     dword [r13 + RELOC_type], RELOC_DELETED
    je      .relocs_next
    mov     rdi, [r13 + RELOC_offset]
    call    rx_new
    mov     [r13 + RELOC_offset], rax
.relocs_next:
    inc     r15
    jmp     .relocs
.relocs_done:

    ; labels defined in this section
    mov     r14d, [r12 + SECTION_index]
    mov     r13, [rbx + ASMCTX_symtab]
    xor     r15d, r15d
.syms:
    cmp     r15d, [rbx + ASMCTX_symcount]
    jae     .listing
    cmp     [r13 + SYMBOL_section], r14w
    jne     .syms_next
    mov     rdi, [r13 + SYMBOL_value]
    call    rx_new
    mov     [r13 + SYMBOL_value], rax
.syms_next:
    add     r13, SYMBOL_SIZE
    inc     r15
    jmp     .syms

.listing:
    ; and the listing's lines (-l)
    mov     rdi, r12
    extern  lst_remap
    call    lst_remap

.out:
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; copy old bytes [r13, rdi) to the new buffer at r14
.copy_to:
    cmp     r13, rdi
    jae     .copied
    mov     rax, [r12 + SECTION_data]
    mov     al, [rax + r13]
    mov     [rbp + r14], al
    inc     r13
    inc     r14
    jmp     .copy_to
.copied:
    ret

; ---- rx_compact_relocs (internal) -------
;
; Removes the relocations of shortened jumps from the relocation table.
;
rx_compact_relocs:
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rel rw_ctx]
    mov     r12, [rbx + ASMCTX_relocs]
    xor     ecx, ecx                       ; read index
    xor     r13d, r13d                     ; write index
.loop:
    cmp     ecx, [rbx + ASMCTX_nrelocs]
    jae     .done
    imul    rsi, rcx, RELOC_SIZE
    add     rsi, r12
    cmp     dword [rsi + RELOC_type], RELOC_DELETED
    je      .next
    cmp     rcx, r13
    je      .keep
    imul    rdi, r13, RELOC_SIZE
    add     rdi, r12
    push    rcx
    mov     ecx, RELOC_SIZE
    cld
    rep     movsb
    pop     rcx
.keep:
    inc     r13
.next:
    inc     rcx
    jmp     .loop
.done:
    mov     [rbx + ASMCTX_nrelocs], r13d
    pop     r13
    pop     r12
    pop     rbx
    ret
