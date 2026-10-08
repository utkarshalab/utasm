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
;   label differences      "b - a" (also "$ - msg", "$ - $$") turns the
;                          distance into a plain number: nothing between a
;                          and b may change size (a frozen range); no jump
;                          inside one is shortened, and when padding in
;                          one would change the section is left as it is
;   times K-($-$$) db F    padding up to offset K (RELAX_PADTO): it grows
;                          by what is removed before it
;   other uses of a        a position in arithmetic NASM cannot relocate
;   position as a number   (label >> 4) freezes its whole section
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
;        In a section of jumps only, it also takes the fewest long jumps
;        (rx_fast), where NASM's passes can settle on more.
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
%define RX_fill      48     ; q  align: the fill spec (optimizer/align.s)
%define RX_tidx      56     ; q  candidate: the records ending at or before
                            ;    its target (rx_ub; the same every pass)
%define RX_SIZE      64

%define RS_LONG       0     ; candidate, not shortened (yet)
%define RS_SHORT      1     ; candidate, shortened
%define RS_FORCED     2     ; shortened once, put back for good
%define RS_NO         3     ; not eligible
%define RS_DELETE     4     ; -O2: removed entirely

%define RF_RETARGET   1     ; -O2: target changed; resolve it here, even
                            ; if it stays rel32 (its relocation is stale)
%define RF_BACKWARD   2     ; a backward rel16/rel32 jump the encoder
                            ; resolved in place (RELAX_FIXED, rx_backward):
                            ; RX_fill = its displacement | width << 56
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
alignb 8
; frozen ranges: SECTION*, lo, hi (relax_freeze_range)
%define FREEZE_MAX  4096
freeze_ranges:      resq 3 * FREEZE_MAX
freeze_n:           resq 1
; ranges held back while a "times" count is read (relax_defer_begin)
freeze_pend:        resq 3 * 4
freeze_pend_n:      resq 1
freeze_defer:       resb 1
freeze_pend_over:   resb 1
rw_has_ranges:      resb 1              ; the section being processed has some
alignb 8
rw_removed:         resq 1              ; bytes removed so far in this pass
rw_passes:          resq 1              ; passes made choosing the sizes
rw_ends:            resq 1              ; each record's RX_end
rw_pref:            resq 1              ; bytes removed before each record
rw_pref_ok:         resb 1              ; rw_pref and rw_ends hold (rx_new)
rw_sorted:          resb 1              ; the records' RX_pos never go down
alignb 8
fx_fw:              resq 1              ; rx_fast: the Fenwick tree (changes)
fx_bstart:          resq 1              ; ... where each block's jumps start
fx_bcur:            resq 1              ; ... filling them
fx_blist:           resq 1              ; ... the jumps, by block
fx_stack:           resq 1              ; ... the worklist
fx_queued:          resq 1              ; ... on it (a byte per record)

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
;            r8b = condition code / width; align: r8 = the fill spec
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
    mov     byte  [rsp + RX_flags], 0
    mov     byte  [rsp + RX_cc], r8b
    mov     dword [rsp + RX_aux32], ecx
    mov     [rsp + RX_sec], rax
    mov     [rsp + RX_pos], rsi
    mov     [rsp + RX_aux], rdx
    mov     qword [rsp + RX_end], 0
    mov     qword [rsp + RX_change], 0
    mov     [rsp + RX_fill], r8

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

; ---- relax_freeze_range ------------------
;
; relax_freeze_range
; "b - a" became a number: the code from a to b must keep its size.
; Preserves every register.
; Input    : rdi = SECTION*, rsi / rdx = the two offsets (either order)
;
global relax_freeze_range
relax_freeze_range:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    test    rdi, rdi
    jz      .out
    cmp     rsi, rdx
    jbe     .ordered
    xchg    rsi, rdx
.ordered:
    cmp     byte [rel freeze_defer], 0
    je      .commit
    mov     rax, [rel freeze_pend_n]
    cmp     rax, 4
    jae     .too_many
    imul    rax, rax, 24
    lea     rcx, [rel freeze_pend]
    add     rcx, rax
    mov     [rcx], rdi
    mov     [rcx + 8], rsi
    mov     [rcx + 16], rdx
    inc     qword [rel freeze_pend_n]
    jmp     .out
.too_many:
    mov     byte [rel freeze_pend_over], 1
.commit:
    mov     rax, [rel freeze_n]
    cmp     rax, FREEZE_MAX
    jae     .whole
    imul    rax, rax, 24
    lea     rcx, [rel freeze_ranges]
    add     rcx, rax
    mov     [rcx], rdi
    mov     [rcx + 8], rsi
    mov     [rcx + 16], rdx
    inc     qword [rel freeze_n]
    jmp     .out
.whole:
    mov     byte [rdi + SECTION_relax_frozen], 1
.out:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ---- relax_defer_begin / relax_defer_end --
;
; Around the count of a "times": the ranges it freezes are held back; if
; the count is K - ($ - $$) the padding is a RELAX_PADTO record and they
; are dropped (relax_defer_end with edi = 0), else committed (edi = 1).
; relax_pending_padto: eax = 1 when the only range held back is [0, rsi)
; in section rdi (the "$ - $$" of the count). All preserve other registers.
;
global relax_defer_begin, relax_defer_end, relax_pending_padto
relax_defer_begin:
    mov     byte [rel freeze_defer], 1
    mov     qword [rel freeze_pend_n], 0
    mov     byte [rel freeze_pend_over], 0
    ret

relax_defer_end:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    mov     byte [rel freeze_defer], 0
    test    edi, edi
    jz      .done
    xor     ecx, ecx
.next:
    cmp     rcx, [rel freeze_pend_n]
    jae     .done
    imul    rax, rcx, 24
    lea     rdx, [rel freeze_pend]
    add     rax, rdx
    mov     rdi, [rax]
    mov     rsi, [rax + 8]
    mov     rdx, [rax + 16]
    call    relax_freeze_range
    inc     rcx
    jmp     .next
.done:
    mov     qword [rel freeze_pend_n], 0
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret

relax_pending_padto:
    xor     eax, eax
    cmp     byte [rel freeze_pend_over], 0
    jne     .ret
    cmp     qword [rel freeze_pend_n], 1
    jne     .ret
    cmp     [rel freeze_pend], rdi
    jne     .ret
    cmp     qword [rel freeze_pend + 8], 0
    jne     .ret
    cmp     [rel freeze_pend + 16], rsi
    jne     .ret
    mov     eax, 1
.ret:
    ret

; ---- rx_in_frozen (internal) -------------
; eax = 1 when offset rdi lies in a frozen range of rw_sec. Clobbers rcx,
; rdx.
rx_in_frozen:
    xor     ecx, ecx
.next:
    cmp     rcx, [rel freeze_n]
    jae     .no
    imul    rdx, rcx, 24
    push    rax
    lea     rax, [rel freeze_ranges]
    add     rdx, rax
    pop     rax
    inc     rcx
    mov     rax, [rel rw_sec]
    cmp     [rdx], rax
    jne     .next
    mov     byte [rel rw_has_ranges], 1
    cmp     rdi, [rdx + 8]
    jb      .next
    cmp     rdi, [rdx + 16]
    jae     .next
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- rx_ranges_kept (internal) -----------
; eax = 1 when, in the current layout, every frozen range of rw_sec keeps
; its length. Clobbers rcx, rdx, rdi, r8-r11.
rx_ranges_kept:
    push    rbx
    push    r12
    xor     ebx, ebx
.next:
    cmp     rbx, [rel freeze_n]
    jae     .yes
    imul    r12, rbx, 24
    lea     rax, [rel freeze_ranges]
    add     r12, rax
    inc     rbx
    mov     rax, [rel rw_sec]
    cmp     [r12], rax
    jne     .next
    mov     rdi, [r12 + 16]
    call    rx_new
    mov     r11, rax
    mov     rdi, [r12 + 8]
    call    rx_new
    sub     r11, rax                       ; the new length
    mov     rax, [r12 + 16]
    sub     rax, [r12 + 8]
    cmp     rax, r11
    je      .next
    xor     eax, eax
    jmp     .ret
.yes:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    ret

; ---- relax_count / relax_truncate --------
;
; relax_count: rax = how many records there are. relax_truncate: drop
; the records from index rdi on (a trial encoding's, encoder.s).
; Both preserve the other registers.
;
global relax_count, relax_truncate
relax_count:
    xor     eax, eax
    push    rcx
    lea     rcx, [rel relax_vec]
    cmp     byte [rcx + VEC_tag], TAG_VEC
    jne     .ret
    mov     rax, [rcx + VEC_len]
.ret:
    pop     rcx
    ret

relax_truncate:
    push    rcx
    lea     rcx, [rel relax_vec]
    cmp     byte [rcx + VEC_tag], TAG_VEC
    jne     .ret
    cmp     rdi, [rcx + VEC_len]
    jae     .ret
    mov     [rcx + VEC_len], rdi
.ret:
    pop     rcx
    ret

; ---- relax_range_fixed -------------------
;
; relax_range_fixed
; eax = 1 when no record of section rdi lies in [rsi, rdx): no jump,
; padding or in-place branch there the optimizer could resize.
;
global relax_range_fixed
relax_range_fixed:
    push    rbx
    xor     eax, eax
    lea     rcx, [rel relax_vec]
    cmp     byte [rcx + VEC_tag], TAG_VEC
    jne     .yes
    mov     r8, [rcx + VEC_data]
    mov     r9, [rcx + VEC_len]
    xor     ecx, ecx
.next:
    cmp     rcx, r9
    jae     .yes
    imul    rbx, rcx, RX_SIZE
    add     rbx, r8
    inc     rcx
    cmp     [rbx + RX_sec], rdi
    jne     .next
    mov     r10, [rbx + RX_pos]
    cmp     r10, rsi
    jb      .next
    cmp     r10, rdx
    jae     .next
    xor     eax, eax
    pop     rbx
    ret
.yes:
    mov     eax, 1
    pop     rbx
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
    mov     qword [rel rw_pref], 0         ; (this section's: not yet)
    mov     qword [rel rw_ends], 0
    mov     byte [rel rw_pref_ok], 0
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
    mov     byte [rel rw_has_ranges], 0
    mov     rdi, -1
    call    rx_in_frozen                   ; notes whether there are ranges
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
    cmp     eax, RELAX_PADTO
    je      .prep_align
    cmp     eax, RELAX_P1
    je      .prep_p1
    mov     rdi, r13
    call    rx_prepare_candidate
    ; a jump between two labels whose distance is a number keeps its size
    cmp     byte [r13 + RX_state], RS_LONG
    jne     .prep_next
    mov     rdi, [r13 + RX_pos]
    call    rx_in_frozen
    test    eax, eax
    jz      .prep_next
    mov     byte [r13 + RX_state], RS_NO
    jmp     .prep_next
.prep_fixed:
    mov     rax, [r13 + RX_pos]
    mov     [r13 + RX_end], rax
    jmp     .prep_next
.prep_p1:
    mov     byte [r13 + RX_state], RS_NO
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

    ; ---- 2b. -O2: rewrite jumps before choosing sizes (not around
    ;          frozen ranges: they remove and move jumps) ----
    cmp     byte [rbx + ASMCTX_opt], OPT_SIZE
    jb      .o2_done
    cmp     byte [rel rw_has_ranges], 0
    jne     .o2_done
    call    rx_o2
.o2_done:

    ; backward jumps resolved in place are candidates too (after -O2,
    ; whose rewrites are for the forward ones)
    call    rx_backward

    ; ---- 3. choose the jumps to shorten, pass by pass as NASM does ----
    ; In a pass, a jump's own position is this pass's (what jumps before
    ; it shrank in it), a label before it is this pass's too, and a label
    ; after it is where the previous pass put it - so a forward jump is
    ; short only when it reaches without counting its own shrinking. The
    ; passes repeat until no size changes: NASM's sizes, byte for byte.
    ; NASM's first pass takes a jump to a label it has not seen yet as
    ; short ("optimistic"): the sizes start from there
    mov     qword [rel rw_passes], 0
    xor     r15d, r15d
.optimist:
    cmp     r15, [rel rw_n]
    jae     .arrays
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    inc     r15
    cmp     byte [r13 + RX_kind], RELAX_JCC
    ja      .optimist
    cmp     byte [r13 + RX_state], RS_LONG
    jne     .optimist
    mov     byte [r13 + RX_state], RS_SHORT
    jmp     .optimist
    ; ---- per-pass bookkeeping: each record's end, and the bytes removed
    ;      before each in the pass (binary search instead of a walk) ----
.arrays:
    mov     rdi, [rbx + ASMCTX_arena]
    mov     rsi, [rel rw_n]
    shl     rsi, 3
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel rw_ends], rdx
    mov     rdi, [rbx + ASMCTX_arena]
    mov     rsi, [rel rw_n]
    lea     rsi, [rsi*8 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .ret
    mov     [rel rw_pref], rdx
    call    rx_layout                      ; the first pass's predecessor
    xor     r15d, r15d
.ends:
    cmp     r15, [rel rw_n]
    jae     .first_pass
    mov     rax, [rel rw_recs]
    mov     rax, [rax + r15*8]
    mov     rax, [rax + RX_end]
    mov     rdx, [rel rw_ends]
    mov     [rdx + r15*8], rax
    inc     r15
    jmp     .ends

    ; ---- NASM's first pass: a jump to a label not seen yet is short, one
    ;      to a label behind it is sized by where things lie in this pass,
    ;      and instructions with symbols not defined yet have the sizes the
    ;      first pass gives them (RELAX_P1). Its layout is what the second
    ;      pass measures forward jumps against. ----
.first_pass:
    ; each jump's target in records (the records do not move while the
    ; sizes are chosen): its position in a pass is RX_aux less
    ; rw_pref[RX_tidx], with no search
    xor     r15d, r15d
.tidx:
    cmp     r15, [rel rw_n]
    jae     .tidx_done
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    inc     r15
    cmp     byte [r13 + RX_kind], RELAX_JCC
    ja      .tidx
    mov     rdi, [r13 + RX_aux]
    call    rx_ub
    mov     [r13 + RX_tidx], rax
    jmp     .tidx
.tidx_done:
    ; from here rw_ends holds the records' ends and rw_pref, kept up to
    ; date by the passes and rx_layout, the bytes removed before each:
    ; rx_new is a binary search
    mov     byte [rel rw_pref_ok], 1
    mov     qword [rel rw_removed], 0
    mov     rdi, [rel rw_pref]
    mov     qword [rdi], 0
    xor     r15d, r15d
.fp:
    cmp     r15, [rel rw_n]
    jae     .fp_done
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    inc     r15
    movzx   eax, byte [r13 + RX_kind]
    cmp     eax, RELAX_ALIGN
    je      .fp_align
    cmp     eax, RELAX_PADTO
    je      .fp_padto
    cmp     eax, RELAX_P1
    je      .fp_p1
    cmp     eax, RELAX_JCC
    ja      .fp_zero
    movzx   eax, byte [r13 + RX_state]
    cmp     eax, RS_LONG
    je      .fp_jump
    cmp     eax, RS_SHORT
    jne     .fp_zero
.fp_jump:
    mov     rax, [r13 + RX_aux]
    cmp     rax, [r13 + RX_end]
    jae     .fp_short                      ; forward: optimistic
    mov     rax, [r13 + RX_tidx]
    mov     rdx, [rel rw_pref]
    mov     rcx, [r13 + RX_aux]
    sub     rcx, [rdx + rax*8]             ; the target in this pass
    mov     rax, [r13 + RX_pos]
    sub     rax, [rel rw_removed]
    add     rax, 2
    sub     rcx, rax
    cmp     rcx, -128
    jl      .fp_long
    cmp     rcx, 127
    jg      .fp_long
.fp_short:
    mov     byte [r13 + RX_state], RS_SHORT
    mov     rax, [r13 + RX_end]
    sub     rax, [r13 + RX_pos]
    sub     rax, 2
    jmp     .fp_store
.fp_long:
    mov     byte [r13 + RX_state], RS_LONG
    jmp     .fp_zero
.fp_p1:
    movsxd  rax, dword [r13 + RX_aux32]    ; first-pass size - final
    neg     rax
    jmp     .fp_store
.fp_align:
    mov     rax, [r13 + RX_pos]
    sub     rax, [rel rw_removed]
    neg     rax
    mov     rcx, [r13 + RX_aux]
    dec     rcx
    and     rax, rcx
    mov     ecx, [r13 + RX_aux32]
    sub     rcx, rax
    mov     rax, rcx
    jmp     .fp_store
.fp_padto:
    mov     rax, [r13 + RX_pos]
    sub     rax, [rel rw_removed]
    neg     rax
    add     rax, [r13 + RX_aux]
    jns     .fp_padto_len
    xor     eax, eax
.fp_padto_len:
    mov     ecx, [r13 + RX_aux32]
    sub     rcx, rax
    mov     rax, rcx
    jmp     .fp_store
.fp_zero:
    xor     eax, eax
.fp_store:
    mov     [r13 + RX_change], rax
    add     rax, [rel rw_removed]
    mov     [rel rw_removed], rax
    mov     rdx, [rel rw_pref]
    mov     [rdx + r15*8], rax
    jmp     .fp
.fp_done:
    ; -O2: the smallest sizes, not NASM's (rx_fast). NASM's passes can
    ; put a jump back to short after making it long, and in a long run of
    ; jumps they settle on more long ones than they need; a worklist that
    ; only ever grows a jump that does not reach finds the fewest, in one
    ; look per change instead of hundreds of passes.
    cmp     byte [rbx + ASMCTX_opt], OPT_SIZE
    jb      .again
    call    rx_fast
    test    eax, eax
    jnz     .stable

.again:
    ; the previous pass: the bytes removed before each record
    mov     rdi, [rel rw_pref]
    xor     eax, eax
    mov     [rdi], rax
    xor     r15d, r15d
.prefix:
    cmp     r15, [rel rw_n]
    jae     .prefixed
    mov     rcx, [rel rw_recs]
    mov     rcx, [rcx + r15*8]
    add     rax, [rcx + RX_change]
    inc     r15
    mov     [rdi + r15*8], rax
    jmp     .prefix
.prefixed:
    xor     r14d, r14d; r14 = a size changed
    mov     qword [rel rw_removed], 0
    xor     r15d, r15d
.pass:
    cmp     r15, [rel rw_n]
    jae     .passed
    mov     rax, [rel rw_recs]
    mov     r13, [rax + r15*8]
    inc     r15
    movzx   eax, byte [r13 + RX_kind]
    cmp     eax, RELAX_ALIGN
    je      .p_align
    cmp     eax, RELAX_PADTO
    je      .p_padto
    cmp     eax, RELAX_JCC
    ja      .p_zero                        ; RELAX_FIXED
    movzx   eax, byte [r13 + RX_state]
    cmp     eax, RS_DELETE
    je      .p_delete
    cmp     eax, RS_LONG
    je      .p_decide
    cmp     eax, RS_SHORT
    jne     .p_zero                        ; RS_NO, RS_FORCED: long
.p_decide:
    ; backward: this pass's position (the records before it are done);
    ; forward: the previous pass's (rw_pref past this record is not
    ; rewritten yet)
    mov     rcx, [r13 + RX_tidx]
    mov     rdx, [rel rw_pref]
    mov     rax, [r13 + RX_aux]
    sub     rax, [rdx + rcx*8]
.p_disp:
    mov     rcx, [r13 + RX_pos]
    sub     rcx, [rel rw_removed]
    add     rcx, 2
    sub     rax, rcx                       ; the rel8 it would have
    mov     dl, RS_SHORT
    cmp     rax, -128
    jl      .p_long
    cmp     rax, 127
    jle     .p_state
.p_long:
    mov     dl, RS_LONG
.p_state:
    cmp     dl, [r13 + RX_state]
    je      .p_same
    mov     [r13 + RX_state], dl
    mov     r14d, 1
.p_same:
    cmp     dl, RS_SHORT
    jne     .p_zero
    mov     rax, [r13 + RX_end]
    sub     rax, [r13 + RX_pos]
    sub     rax, 2                         ; 3 (jmp) or 4 (jcc) bytes saved
    jmp     .p_store
.p_delete:
    mov     rax, [r13 + RX_end]
    sub     rax, [r13 + RX_pos]
    jmp     .p_store
.p_align:
    mov     rax, [r13 + RX_pos]
    sub     rax, [rel rw_removed]
    neg     rax
    mov     rcx, [r13 + RX_aux]
    dec     rcx
    and     rax, rcx                       ; its padding in this pass
    mov     ecx, [r13 + RX_aux32]
    sub     rcx, rax
    mov     rax, rcx
    jmp     .p_store
.p_padto:
    mov     rax, [r13 + RX_pos]
    sub     rax, [rel rw_removed]
    neg     rax
    add     rax, [r13 + RX_aux]
    jns     .p_padto_len
    xor     eax, eax
.p_padto_len:
    mov     ecx, [r13 + RX_aux32]
    sub     rcx, rax
    mov     rax, rcx
    jmp     .p_store
.p_zero:
    xor     eax, eax
.p_store:
    mov     [r13 + RX_change], rax
    add     rax, [rel rw_removed]
    mov     [rel rw_removed], rax
    mov     rdx, [rel rw_pref]
    mov     [rdx + r15*8], rax             ; (r15 is past this record)
    jmp     .pass
.passed:
    test    r14d, r14d
    jz      .stable
    ; as NASM: pass after pass until nothing moves (a ripple of jumps
    ; settling takes one pass per step)
    inc     qword [rel rw_passes]
    cmp     qword [rel rw_passes], 100000
    jb      .again
.stable:

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

    ; frozen ranges must keep their lengths (align padding inside one
    ; changes with what moves before it): if not, nothing changes here
    cmp     byte [rel rw_has_ranges], 0
    je      .ranges_ok
    call    rx_ranges_kept
    test    eax, eax
    jz      .give_up
.ranges_ok:

    ; the backward jumps left long are in-place displacements again
    ; (their records move: rw_ends again)
    call    rx_backward_restore
    call    rx_fill_ends
    call    rx_layout

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

    ; jmp E9 rel32 (5) / jcc 0F 8x rel32 (6); in bits 16 (RX_cc bit 7)
    ; rel16: 3 / 4
    mov     eax, 5
    cmp     byte [r12 + RX_kind], RELAX_JMP
    je      .have_len
    mov     eax, 6
.have_len:
    mov     ecx, 4                         ; the displacement's width
    mov     edx, R_X86_64_PC32
    test    byte [r12 + RX_cc], 0x80
    jz      .have_width
    sub     eax, 2
    mov     ecx, 2
    mov     edx, 13                        ; R_X86_64_PC16
.have_width:
    add     rax, [r12 + RX_pos]
    mov     [r12 + RX_end], rax

    ; its relocation: PC32 (PC16), in this section, on the displacement
    mov     eax, [r12 + RX_aux32]
    cmp     eax, [rbx + ASMCTX_nrelocs]
    jae     .done
    imul    r13, rax, RELOC_SIZE
    add     r13, [rbx + ASMCTX_relocs]     ; r13 = RELOC*
    cmp     [r13 + RELOC_type], edx
    jne     .done
    mov     rax, [rel rw_sec]
    cmp     [r13 + RELOC_section], rax
    jne     .done
    mov     rax, [r12 + RX_end]
    sub     rax, rcx
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

    ; its rewrites are written for rel32 jumps: a section with bits 16 code
    ; (rel16 jumps) keeps to shortening
    xor     r15d, r15d
.w16:
    cmp     r15, [rel rw_n]
    jae     .w16_none
    mov     rax, [rel rw_recs]
    mov     rax, [rax + r15*8]
    inc     r15
    movzx   ecx, byte [rax + RX_kind]
    cmp     ecx, RELAX_FIXED
    je      .w16_fixed
    cmp     ecx, RELAX_JCC
    ja      .w16
    test    byte [rax + RX_cc], 0x80
    jnz     .o2_done
    jmp     .w16
.w16_fixed:
    cmp     byte [rax + RX_cc], 2
    je      .o2_done
    jmp     .w16
.w16_none:

    ; records in the order of their positions (as emitted): rx_find_jmp_at
    ; can search instead of walking them all for every jump
    mov     byte [rel rw_sorted], 1
    xor     edx, edx                       ; rdx = the previous RX_pos
    xor     r15d, r15d
.sorted:
    cmp     r15, [rel rw_n]
    jae     .sorted_done
    mov     rax, [rel rw_recs]
    mov     rax, [rax + r15*8]
    inc     r15
    mov     rax, [rax + RX_pos]
    cmp     rax, rdx
    mov     rdx, rax
    jae     .sorted
    mov     byte [rel rw_sorted], 0
.sorted_done:

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
.o2_done:
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
    cmp     byte [rel rw_sorted], 0
    je      .loop
    ; sorted: from the first record at or after rdi (those before cannot
    ; match), and only while they lie at rdi or rdi+1
    mov     r8, [rel rw_n]
    mov     r9, [rel rw_recs]
.search:
    cmp     rcx, r8
    jae     .loop
    lea     rdx, [rcx + r8]
    shr     rdx, 1
    mov     rax, [r9 + rdx*8]
    cmp     [rax + RX_pos], rdi
    jae     .search_upper
    lea     rcx, [rdx + 1]
    jmp     .search
.search_upper:
    mov     r8, rdx
    jmp     .search
.loop:
    cmp     rcx, [rel rw_n]
    jae     .none
    mov     rdx, [rel rw_recs]
    mov     rdx, [rdx + rcx*8]
    cmp     byte [rel rw_sorted], 0
    je      .any_pos
    lea     r9, [rdi + 1]
    cmp     [rdx + RX_pos], r9
    ja      .none                          ; past rdi+1: no more to look at
.any_pos:
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
    cmp     byte [rdx + RX_kind], RELAX_PADTO
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
    cmp     eax, RELAX_PADTO
    je      .padto
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
    jmp     .store
.padto:
    ; up to offset RX_aux, which does not move (it counts from $$)
    mov     rax, [rbx + RX_pos]
    sub     rax, r8                        ; new position of the padding
    neg     rax
    add     rax, [rbx + RX_aux]            ; new padding
    jns     .padto_len
    xor     eax, eax
.padto_len:
    mov     edx, [rbx + RX_aux32]          ; old padding
    sub     rdx, rax
.store:
    mov     [rbx + RX_change], rdx
    add     r8, rdx
    inc     rcx
    mov     rax, [rel rw_pref]             ; (the bytes removed before the
    test    rax, rax                       ;  next record, for rx_new)
    jz      .loop
    mov     [rax + rcx*8], r8
    jmp     .loop
.done:
    pop     rbx
    ret

; ---- rx_fast (internal) -----------------
;
; The sizes the passes would settle on, for a section whose records are
; all jumps (and displacements resolved in place): from the first pass on,
; a jump only ever grows (the code after it only moves away), so the
; layout the passes reach is the one reached by making long, in any order,
; each short jump that does not reach - looking again only at the short
; jumps across one that grew. The bytes removed before each record are a
; Fenwick tree over the records; the short jumps are filed by the 256-byte
; blocks their spans cover.
; Output: eax = 1 when the sizes are settled (RX_state / RX_change), 0 when
;         the section is not one for it (the passes then).
;
rx_fast:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    xor     eax, eax
    cmp     byte [rel rw_has_ranges], 0
    jne     .out
    mov     r12, [rel rw_recs]
    mov     r13, [rel rw_n]
    test    r13, r13
    jz      .out
    ; only jumps and resolved displacements
    xor     ecx, ecx
.kinds:
    cmp     rcx, r13
    jae     .kinds_ok
    mov     rax, [r12 + rcx * 8]
    cmp     byte [rax + RX_state], RS_DELETE
    je      .not_for_it                    ; (-O2: counted only after pass 1)
    movzx   eax, byte [rax + RX_kind]
    cmp     eax, RELAX_FIXED
    je      .kind_next
    cmp     eax, RELAX_JCC
    ja      .not_for_it
.kind_next:
    inc     rcx
    jmp     .kinds
.not_for_it:
    xor     eax, eax
    jmp     .out
.kinds_ok:
    mov     rbx, [rel rw_ctx]
    ; the Fenwick tree: fw[1..n] over the records' changes
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r13 * 8 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_fw], rdx
    xor     ecx, ecx
.fw_fill:
    cmp     rcx, r13
    jae     .fw_filled
    mov     rax, [r12 + rcx * 8]
    mov     rax, [rax + RX_change]
    add     [rdx + rcx * 8 + 8], rax       ; fw[i+1] += change[i]
    lea     r8, [rcx + 1]                  ; i+1
    mov     r9, r8
    neg     r9
    and     r9, r8                         ; its lowest bit
    add     r9, r8                         ; its parent
    cmp     r9, r13
    ja      .fw_next
    mov     rax, [rdx + r8 * 8]
    add     [rdx + r9 * 8], rax
.fw_next:
    inc     rcx
    jmp     .fw_fill
.fw_filled:
    ; the blocks: how many short jumps' spans cover each
    mov     rax, [rel rw_sec]
    mov     r14, [rax + SECTION_size]
    shr     r14, 8
    add     r14, 2                         ; r14 = blocks
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r14 * 4 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_bstart], rdx
    xor     ecx, ecx
.count:
    cmp     rcx, r13
    jae     .counted
    call    .span                          ; r8 / r9 = first / last block, CF: none
    jc      .count_next
.count_block:
    mov     rax, [rel fx_bstart]
    inc     dword [rax + r8 * 4 + 4]
    inc     r8
    cmp     r8, r9
    jbe     .count_block
.count_next:
    inc     rcx
    jmp     .count
.counted:
    ; where each block's list starts (prefix sums)
    mov     rax, [rel fx_bstart]
    xor     ecx, ecx
    xor     edx, edx
.starts:
    cmp     rcx, r14
    jae     .started
    add     edx, [rax + rcx * 4 + 4]
    mov     [rax + rcx * 4 + 4], edx
    inc     rcx
    jmp     .starts
.started:
    mov     r15d, edx                      ; entries
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r14 * 4 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_bcur], rdx
    mov     rsi, [rel fx_bstart]
    xor     ecx, ecx
.cursors:
    cmp     rcx, r14
    jae     .cursored
    mov     eax, [rsi + rcx * 4]
    mov     [rdx + rcx * 4], eax
    inc     rcx
    jmp     .cursors
.cursored:
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r15 * 4 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_blist], rdx
    xor     ecx, ecx
.file:
    cmp     rcx, r13
    jae     .filed
    call    .span
    jc      .file_next
.file_block:
    mov     rax, [rel fx_bcur]
    mov     edx, [rax + r8 * 4]
    inc     dword [rax + r8 * 4]
    mov     rax, [rel fx_blist]
    mov     [rax + rdx * 4], ecx
    inc     r8
    cmp     r8, r9
    jbe     .file_block
.file_next:
    inc     rcx
    jmp     .file
.filed:
    ; the worklist: every short jump, then those a growing one crosses
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r13 * 4 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_stack], rdx
    mov     rdi, [rbx + ASMCTX_arena]
    lea     rsi, [r13 + 8]
    call    arena_alloc
    test    rax, rax
    jnz     .not_for_it
    mov     [rel fx_queued], rdx
    xor     r15d, r15d                     ; r15 = stack depth
    xor     ecx, ecx
.seed:
    cmp     rcx, r13
    jae     .work
    call    .push_if_short
    inc     rcx
    jmp     .seed
.work:
    test    r15, r15
    jz      .settled
    dec     r15
    mov     rax, [rel fx_stack]
    mov     ecx, [rax + r15 * 4]
    mov     rax, [rel fx_queued]
    mov     byte [rax + rcx], 0
    mov     rbp, [r12 + rcx * 8]           ; rbp = the record
    cmp     byte [rbp + RX_state], RS_SHORT
    jne     .work
    ; its rel8 in the current layout
    push    rcx
    mov     rdi, [rbp + RX_aux]
    call    .new
    mov     r14, rax                       ; the target, now
    mov     rdi, [rbp + RX_pos]
    call    .new
    pop     rcx
    add     rax, 2
    sub     r14, rax
    cmp     r14, -128
    jl      .grow
    cmp     r14, 127
    jle     .work
.grow:
    mov     byte [rbp + RX_state], RS_LONG
    mov     rdx, [rbp + RX_change]
    mov     qword [rbp + RX_change], 0
    neg     rdx
    lea     r8, [rcx + 1]                  ; fw: change[i] loses what it saved
.fw_add:
    cmp     r8, r13
    ja      .fw_added
    mov     rax, [rel fx_fw]
    add     [rax + r8 * 8], rdx
    mov     r9, r8
    neg     r9
    and     r9, r8
    add     r8, r9
    jmp     .fw_add
.fw_added:
    ; the short jumps whose spans cover it
    mov     rax, [rbp + RX_pos]
    shr     rax, 8
    mov     rdx, [rel fx_bstart]
    mov     r8d, [rdx + rax * 4]
    mov     r9d, [rdx + rax * 4 + 4]
.cross:
    cmp     r8d, r9d
    jae     .work
    mov     rax, [rel fx_blist]
    mov     ecx, [rax + r8 * 4]
    call    .push_if_short
    inc     r8d
    jmp     .cross
.settled:
    ; the bytes removed before each record, for rx_new and what follows
    call    rx_layout
    mov     eax, 1
.out:
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; .push_if_short: record rcx onto the worklist when it is a short jump not
; already on it. Clobbers rax.
.push_if_short:
    mov     rax, [r12 + rcx * 8]
    cmp     byte [rax + RX_kind], RELAX_JCC
    ja      .pis_ret
    cmp     byte [rax + RX_state], RS_SHORT
    jne     .pis_ret
    mov     rax, [rel fx_queued]
    cmp     byte [rax + rcx], 0
    jne     .pis_ret
    mov     byte [rax + rcx], 1
    mov     rax, [rel fx_stack]
    mov     [rax + r15 * 4], ecx
    inc     r15
.pis_ret:
    ret

; .span: the blocks record rcx's span covers (r8 the first, r9 the last)
; when it is a short jump that could still reach; CF set when it is not
; one. A span longer than 1024 bytes cannot be reached by a rel8 whatever
; shrinks in it (a jump keeps a third of its bytes): such a jump is made
; long when it is looked at, and nothing need look at it again.
; Clobbers rax, rdx.
.span:
    mov     rax, [r12 + rcx * 8]
    cmp     byte [rax + RX_kind], RELAX_JCC
    ja      .no_span
    cmp     byte [rax + RX_state], RS_SHORT
    jne     .no_span
    mov     r8, [rax + RX_pos]
    mov     r9, [rax + RX_aux]
    cmp     r8, r9
    jbe     .ordered
    xchg    r8, r9
.ordered:
    mov     rdx, r9
    sub     rdx, r8
    cmp     rdx, 1024
    ja      .no_span
    shr     r8, 8
    shr     r9, 8
    clc
    ret
.no_span:
    stc
    ret

; .new: rax = offset rdi in the current layout (rdi less what the records
; ending at or before it remove). Clobbers rcx, rdx, r8, r9.
.new:
    push    rdi
    call    rx_ub                          ; rax = how many records
    mov     rcx, rax
    xor     eax, eax
    mov     r8, [rel fx_fw]
.prefix:
    test    rcx, rcx
    jz      .prefixed
    add     rax, [r8 + rcx * 8]
    mov     r9, rcx
    neg     r9
    and     r9, rcx
    sub     rcx, r9
    jmp     .prefix
.prefixed:
    pop     rdi
    neg     rax
    add     rax, rdi
    ret

; rx_fill_ends: rw_ends from the records' RX_end
rx_fill_ends:
    mov     r8, [rel rw_ends]
    test    r8, r8
    jz      .ret
    mov     r9, [rel rw_recs]
    xor     ecx, ecx
.loop:
    cmp     rcx, [rel rw_n]
    jae     .ret
    mov     rax, [r9 + rcx*8]
    mov     rax, [rax + RX_end]
    mov     [r8 + rcx*8], rax
    inc     rcx
    jmp     .loop
.ret:
    ret

; ---- rx_ub (internal) --------------------
; rax = how many records end at or before offset rdi (rw_ends ascends).
; Clobbers rcx, rdx, r8.
rx_ub:
    xor     eax, eax
    mov     rcx, [rel rw_n]
    mov     r8, [rel rw_ends]
.loop:
    cmp     rax, rcx
    jae     .done
    lea     rdx, [rax + rcx]
    shr     rdx, 1
    cmp     [r8 + rdx*8], rdi
    ja      .upper
    lea     rax, [rdx + 1]
    jmp     .loop
.upper:
    mov     rcx, rdx
    jmp     .loop
.done:
    ret

; ---- rx_new (internal) -------------------
;
; Maps an old offset in the section to its offset in the current layout.
; Input: rdi = old offset. Output: rax = new offset. Clobbers: rdx, r9.
;
rx_new:
    ; the records ending at or before rdi, and the bytes they removed:
    ; walking them for every jump and label made relaxation quadratic
    cmp     byte [rel rw_pref_ok], 0
    je      .walk
    push    rcx
    push    r8
    call    rx_ub
    mov     r9, [rel rw_pref]
    mov     rax, [r9 + rax*8]
    pop     r8
    pop     rcx
    neg     rax
    add     rax, rdi
    ret
.walk:
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

; ---- rx_backward (internal) --------------
;
; A backward jmp / jcc the encoder resolved in place as rel16 / rel32 (its
; target was too far for rel8 then) may come within reach once code
; between shrinks, as NASM would find over its passes: its RELAX_FIXED
; record becomes a candidate (RF_BACKWARD). rx_backward_restore turns the
; ones left long back into RELAX_FIXED, whose displacements rx_apply
; rewrites.
;
rx_backward:
    push    rbx
    push    r12
    push    r13
    mov     rax, [rel rw_sec]
    mov     r12, [rax + SECTION_data]
    test    r12, r12
    jz      .done
    xor     r13d, r13d
.next:
    cmp     r13, [rel rw_n]
    jae     .done
    mov     rax, [rel rw_recs]
    mov     rbx, [rax + r13*8]
    inc     r13
    cmp     byte [rbx + RX_kind], RELAX_FIXED
    jne     .next
    movzx   ecx, byte [rbx + RX_cc]        ; the displacement's width
    cmp     ecx, 1
    je      .next
    mov     rdx, [rbx + RX_pos]            ; the displacement
    cmp     [rbx + RX_aux], rdx
    jae     .next                          ; forward: not this
    cmp     rdx, 2
    jb      .next
    ; the opcode before the displacement: E9 (jmp) or 0F 8x (jcc); a call
    ; or a loop stays as it is
    cmp     byte [r12 + rdx - 1], 0xE9
    je      .jmp
    cmp     byte [r12 + rdx - 2], 0x0F
    jne     .next
    movzx   eax, byte [r12 + rdx - 1]
    and     eax, 0xF0
    cmp     eax, 0x80
    jne     .next
    movzx   eax, byte [r12 + rdx - 1]
    and     eax, 0x0F                      ; the condition
    lea     r8, [rdx - 2]
    mov     r9d, RELAX_JCC
    jmp     .convert
.jmp:
    xor     eax, eax
    lea     r8, [rdx - 1]
    mov     r9d, RELAX_JMP
.convert:
    cmp     ecx, 2
    jne     .cc
    or      eax, 0x80                      ; a rel16
.cc:
    mov     [rbx + RX_cc], al
    mov     [rbx + RX_kind], r9b
    mov     rax, rcx
    shl     rax, 56
    or      rax, rdx
    mov     [rbx + RX_fill], rax
    mov     [rbx + RX_pos], r8
    add     rdx, rcx
    mov     [rbx + RX_end], rdx
    mov     dword [rbx + RX_aux32], NO_RELOC
    mov     byte [rbx + RX_flags], RF_BACKWARD
    mov     byte [rbx + RX_state], RS_LONG
    push    rcx
    push    rdx
    mov     rdi, r8
    call    rx_in_frozen
    pop     rdx
    pop     rcx
    test    eax, eax
    jz      .next
    mov     byte [rbx + RX_state], RS_NO
    jmp     .next
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

rx_backward_restore:
    xor     ecx, ecx
.next:
    cmp     rcx, [rel rw_n]
    jae     .done
    mov     rax, [rel rw_recs]
    mov     rdx, [rax + rcx*8]
    inc     rcx
    test    byte [rdx + RX_flags], RF_BACKWARD
    jz      .next
    cmp     byte [rdx + RX_state], RS_SHORT
    je      .next
    mov     rax, [rdx + RX_fill]
    mov     r8, rax
    shr     r8, 56                         ; the width
    shl     rax, 8
    shr     rax, 8                         ; the displacement
    mov     byte [rdx + RX_kind], RELAX_FIXED
    mov     [rdx + RX_cc], r8b
    mov     [rdx + RX_pos], rax
    mov     [rdx + RX_end], rax
    mov     byte [rdx + RX_flags], 0
    jmp     .next
.done:
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
    cmp     eax, RELAX_PADTO
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
    mov     esi, [rbx + RX_aux32]
    sub     rsi, [rbx + RX_change]         ; new padding
    lea     rdi, [rbp + r14]
    add     r14, rsi
    mov     rdx, [rbx + RX_fill]           ; as align wrote it first
    extern  align_fill
    call    align_fill
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
    jne     .fixed_wide
    mov     [rbp + r8], cl
    jmp     .fixed_next
.fixed_wide:
    cmp     edx, 2
    jne     .fixed32
    mov     [rbp + r8], cx                 ; bits 16: a rel16
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
