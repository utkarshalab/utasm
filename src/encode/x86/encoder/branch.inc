; ============================================================================
; File        : src/encode/x86/encoder/branch.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : branch sizing, and tracking each instruction for the second pass
; ============================================================================


;*
; * [amd64_emit_reloc]
; * Input:
; *   AL: Relocation Type (RELOC_REL32, etc)
; *   RSI: Pointer to Symbol String
; *   EDX: PC Adjustment (bytes from reloc site to end of instruction)
; ;
; ---- amd64_branch_sized / amd64_branch_osize ----
;
; amd64_branch_sized: ZF clear when a size is written on the target ("jmp
; word x", "jz dword x"): a near branch, as written, never shortened.
; amd64_branch_osize: and when that size is not the mode's (word in bits
; 32, dword in bits 16), 66 before the opcode and the displacement that
; wide (amd64_branch_width, amd64_emit_branch_disp). In bits 64 the
; displacement is rel32 whatever is written. Clobber rax (osize: rcx, rdi).
;
amd64_branch_sized:
    cmp     byte [r12 + INST_op0 + OPERAND_size], 16
    je      .yes
    cmp     byte [r12 + INST_op0 + OPERAND_size], 32
    je      .yes
    cmp     eax, eax                       ; ZF set: none
    ret
.yes:
    test    esp, esp                       ; ZF clear
    ret

; amd64_branch_size_first (jmp / jcc to a label): ZF clear when the branch
; is to be near as written - GNU's syntax with a size on it, "near" at -O0
; - else ZF set: it may be short. In NASM's syntax a size other than the
; mode's puts its 66 out first (amd64_branch_osize), so that what follows
; measures the short form after it; amd64_branch_osize_once then adds
; none, and the displacement is rel8 or the size's (amd64_branch_width).
amd64_branch_size_first:
    mov     byte [rel amd64_osize_done], 0
    cmp     byte [r12 + INST_op0 + OPERAND_near], 0
    je      .bsf_near_ok
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .bsf_keep                      ; (-O0: "near" is near)
.bsf_near_ok:
    call    amd64_branch_sized
    jz      .bsf_short                     ; (none written)
    extern  gas_names
    cmp     byte [rel gas_names], 0
    jne     .bsf_keep
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .bsf_keep
    cmp     byte [rbx + ASMCTX_opt], OPT_MIN
    je      .bsf_keep
    push    rcx
    push    rdi
    call    amd64_branch_osize
    pop     rdi
    pop     rcx
    mov     byte [rel amd64_osize_done], 1
.bsf_short:
    cmp     eax, eax                       ; ZF set
    ret
.bsf_keep:
    test    esp, esp                       ; ZF clear
    ret

; amd64_branch_osize_once: amd64_branch_osize unless amd64_branch_size_first
; put the 66 out already. A short form takes a rel8 whatever the size.
amd64_branch_osize_once:
    cmp     byte [rel amd64_osize_done], 0
    je      amd64_branch_osize
    mov     byte [rel amd64_osize_done], 0
    ret

amd64_branch_osize:
    mov     byte [rel amd64_branch_width], 0
    movzx   eax, byte [r12 + INST_op0 + OPERAND_size]
    cmp     eax, 16
    je      .sized
    cmp     eax, 32
    jne     .ret
.sized:
    cmp     al, [rel asm_bits]
    je      .ret                           ; the mode's own
    cmp     byte [rel asm_bits], 64
    je      .ret
    shr     eax, 3
    mov     [rel amd64_branch_width], al
    mov     al, 0x66
    call    amd64_emit_byte
.ret:
    ret

;*
; * [amd64_emit_branch_disp]
; * Emits a branch displacement and the relocation it needs, if any.
; * A target that is already defined, local, and in the section currently
; * being emitted is computed here and needs no relocation — which is what
; * NASM does, and what lets a later pass shorten the branch. Everything else
; * (forward references, other sections, exported symbols) stays the linker's
; * job and gets a zero placeholder.
; * Input:
; *   RSI = OPERAND_sym: a SYMBOL* when resolved, the raw name string for a
; *         forward reference, or 0 for a non-symbolic target
; *   RCX = displacement width in bytes (1 or 4)
; *   AL  = relocation type to record when it cannot be resolved here
; ;
;*
; * [amd64_emit_branch_disp.note_fixed] (see below)
; * Records a displacement resolved in place - its offset, width and the
; * target's offset - so src/optimize/jump.s can rewrite it if code between
; * the branch and its target moves. Preserves every register.
; * Expects: r8 = current section, r14 = width, r15 = target SYMBOL*.
; ;
amd64_emit_branch_disp:
    prologue
    push    r13
    push    r14
    push    r15

    movzx   r13d, al               ; r13 = fallback relocation type
    mov     r14, rcx               ; r14 = displacement width
    mov     r15, rsi               ; r15 = symbol or name

    ; a size written other than the mode's ("jmp word x" in bits 32, 66
    ; before it: amd64_branch_osize): its width
    movzx   eax, byte [rel amd64_branch_width]
    mov     byte [rel amd64_branch_width], 0
    test    eax, eax
    jz      .width_mode
    mov     r14d, eax
    mov     r13d, RELOC_REL32
    cmp     eax, 2
    jne     .width_ok
    mov     r13d, 13                       ; R_X86_64_PC16
    jmp     .width_ok
.width_mode:
    ; bits 16: a near branch takes a rel16 (E9 cw, E8 cw, 0F 8x cw)
    extern  asm_bits
    cmp     byte [rel asm_bits], 16
    jne     .width_ok
    cmp     r14, 4
    jne     .width_ok
    mov     r14d, 2
    mov     r13d, 13                       ; R_X86_64_PC16
.width_ok:

    ; The offset written after the target ("jmp .L1+4", "jz $+2"): the
    ; operand's value is the label's plus that offset
    mov     qword [rel amd64_branch_off], 0
    test    r15, r15
    jz      .off_done
    lea     r8, [r12 + INST_op0]
    cmp     [r8 + OPERAND_sym], r15
    jne     .off_done
    mov     rax, [r8 + OPERAND_imm]
    cmp     byte [r15], TAG_SYMBOL
    jne     .off_set               ; a forward name: the value is the offset
    cmp     byte [r15 + SYMBOL_kind], SYM_LABEL
    jne     .off_done              ; constants go through the relocation as before
    sub     rax, [r15 + SYMBOL_value]
.off_set:
    mov     [rel amd64_branch_off], rax
.off_done:

    ; a number ("jmp 0x7c00", "jz 0x7c10", "call 0x8000"): an absolute
    ; target, through a relocation against no symbol with the number its
    ; addend (RELOC_ABS_MARK) - it was a jump to the next instruction (jcc)
    ; or through a garbage address (jmp / call: FF /4 [rax+rax])
    test    r15, r15
    jnz     .target_named
    lea     r8, [r12 + INST_op0]
    cmp     byte [r8 + OPERAND_kind], OP_IMM
    jne     .placeholder
    mov     rax, [r8 + OPERAND_imm]
    mov     [rel amd64_branch_off], rax
    lea     r15, [rel amd64_abs_target]
    jmp     .relocate
.target_named:

    cmp     byte [r15], TAG_SYMBOL
    jne     .relocate              ; a raw name means a forward reference
    cmp     byte [r15 + SYMBOL_kind], SYM_LABEL
    jne     .relocate
    cmp     byte [rel reloc_wrt], 0
    jne     .relocate              ; "wrt ..plt": its relocation, as asked
    push    rsi
    mov     rsi, r15
    call    amd64_gas_preempt
    pop     rsi
    je      .relocate              ; GNU's syntax: a call to a global keeps its relocation

    mov     r8, [rbx + ASMCTX_curr_sec]
    test    r8, r8
    jz      .relocate
    mov     eax, [r8 + SECTION_index]
    cmp     eax, [r15 + SYMBOL_section]
    jne     .relocate

    ; disp = target - address of the next instruction
    mov     rdi, [r15 + SYMBOL_value]
    add     rdi, [rel amd64_branch_off]
    mov     rax, [r8 + SECTION_size]
    add     rax, r14
    sub     rdi, rax

    IF r14, e, 1
        ; a rel8 target has to actually reach
        IF rdi, l, -128
            jmp .relocate
            ENDIF
        IF rdi, g, 127
            jmp .relocate
            ENDIF
        call    .note_fixed
        mov     rax, rdi
        call    amd64_emit_byte
        jmp     .ok
        ENDIF
    call    .note_fixed
    IF r14, e, 2
        call    amd64_emit_word
        jmp     .ok
        ENDIF
    call    amd64_emit_dword
    jmp     .ok

.relocate:
    mov     rax, r13
    mov     rsi, r15
    mov     rdx, r14
    call    amd64_emit_reloc
    test    rax, rax
    jnz     .done                  ; propagate a real relocation failure
    ; a branch's (the ELF writer: PLT32 to a global in GNU's syntax)
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, [rbx + ASMCTX_relocs]
    or      byte [rcx + RELOC_flags], RELOC_FLAG_BRANCH

    ; the offset after a forward label goes into the relocation's addend
    mov     rax, [rel amd64_branch_off]
    test    rax, rax
    jz      .no_reloc_off
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx
    imul    rcx, rcx, RELOC_SIZE
    add     rcx, [rbx + ASMCTX_relocs]
    add     [rcx + RELOC_addend], rax
.no_reloc_off:

    ; A jmp/jcc rel32 whose target is not defined yet: note it, so
    ; src/optimize/jump.s can shorten it once all code is emitted.
    cmp     byte [rel amd64_relax_kind], 0
    je      .placeholder
    cmp     r14, 1
    je      .placeholder                   ; rel32, or rel16 in bits 16
    mov     rax, [rbx + ASMCTX_curr_sec]
    test    rax, rax
    jz      .placeholder
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    push    r8
    movzx   edi, byte [rel amd64_relax_kind]
    mov     rsi, [rax + SECTION_size]      ; offset of the displacement
    dec     rsi                            ; jmp: E9 before it
    cmp     edi, RELAX_JMP
    je      .cand_start
    dec     rsi                            ; jcc: 0F 8x before it
.cand_start:
    xor     edx, edx
    mov     ecx, [rbx + ASMCTX_nrelocs]
    dec     ecx                            ; the relocation just emitted
    movzx   r8d, byte [rel amd64_relax_cc]
    cmp     r14, 2
    jne     .cand_note
    or      r8d, 0x80                      ; a rel16 (src/optimize/jump.s)
.cand_note:
    call    relax_note
    pop     r8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi

.placeholder:
    IF r14, e, 1
        xor     rax, rax
        call    amd64_emit_byte
        jmp     .ok
        ENDIF
    xor     rdi, rdi
    IF r14, e, 2
        call    amd64_emit_word
        jmp     .ok
        ENDIF
    call    amd64_emit_dword

.ok:
    ; The emit helpers preserve RAX, so it still holds the caller's stale
    ; value here; the dispatcher reads it as the encoder's status.
    xor     rax, rax
    mov     byte [rel amd64_relax_kind], 0

.done:
    pop     r15
    pop     r14
    pop     r13
    epilogue

.note_fixed:
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    push    r8
    mov     rsi, [r8 + SECTION_size]       ; the displacement goes here
    mov     rdx, [r15 + SYMBOL_value]      ; the target's offset
    add     rdx, [rel amd64_branch_off]
    ; 1: its size was asked for ("jmp near x", "strict", "bnd jmp"): the
    ; optimizer keeps it, whatever moves (rx_backward made it short)
    xor     ecx, ecx
    test    byte [r12 + INST_op0 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .fixed_kept
    cmp     byte [r12 + INST_op0 + OPERAND_size], 16
    je      .fixed_kept                    ; "jmp word x", "jmp dword x"
    cmp     byte [r12 + INST_op0 + OPERAND_size], 32
    je      .fixed_kept
    cmp     word [r12 + INST_op_id], 1298  ; JMP
    jne     .fixed_note
    cmp     byte [r12 + INST_prefixes], 0xF2
    je      .fixed_kept
    cmp     byte [r12 + INST_prefixes + 1], 0xF2
    je      .fixed_kept
    cmp     byte [r12 + INST_prefixes + 2], 0xF2
    je      .fixed_kept
    cmp     byte [r12 + INST_prefixes + 3], 0xF2
    jne     .fixed_note
.fixed_kept:
    mov     ecx, 1
.fixed_note:
    mov     r8, r14                        ; width: 1, 2 or 4
    mov     edi, RELAX_FIXED
    call    relax_note
    ; its label's padding rank (where it is among padding that grows)
    movzx   edi, byte [r15 + SYMBOL_lflags]
    extern  relax_mark_rank
    call    relax_mark_rank
    pop     r8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    ret

;*
; * [amd64_encode_tracked]
; * Purpose: amd64_encode_instruction, and for an instruction with a symbol
; *   not defined yet in it, the size NASM's first pass gives it: NASM
; *   takes such a value as unknown - an immediate as small (mov rsi, msg
; *   is mov esi, imm32: 5 bytes), a displacement as 32-bit - and its jump
; *   sizes follow from that pass. A trial encoding with those assumptions
; *   is measured and thrown away; when it differs a RELAX_P1 record notes
; *   the difference for src/optimize/jump.s, which replays NASM's passes.
; * Input  : RDI = AsmCtx, RSI = INST
; * Output : RAX = OK or an error (the real encoding's)
; ;
global amd64_encode_tracked
amd64_encode_tracked:
    test    dword [rdi + ASMCTX_flags], CTX_FLAG_DEBUG | CTX_FLAG_DWARF
    jnz     amd64_encode_instruction
    cmp     qword [rdi + ASMCTX_curr_sec], 0
    je      amd64_encode_instruction
    ; branches: their sizes are the optimizer's own
    movzx   eax, word [rsi + INST_op_id]
    cmp     eax, 1059                      ; CALL
    je      amd64_encode_instruction
    cmp     eax, 1298                      ; JMP
    je      amd64_encode_instruction
    cmp     eax, 1373                      ; LOOP
    je      amd64_encode_instruction
    cmp     eax, 2151                      ; XBEGIN
    je      amd64_encode_instruction
    cmp     eax, 3000
    jb      .not_jcc
    cmp     eax, 3099
    jbe     amd64_encode_instruction
.not_jcc:
    cmp     eax, 6536                      ; JCXZ
    je      amd64_encode_instruction
    cmp     eax, 6524
    jb      .not_loopcc
    cmp     eax, 6529
    jbe     amd64_encode_instruction
.not_loopcc:
    ; an operand with a symbol not defined yet?
    movzx   ecx, byte [rsi + INST_nops]
    xor     edx, edx
.any:
    cmp     edx, ecx
    jae     amd64_encode_instruction
    imul    eax, edx, OPERAND_SIZE
    cmp     byte [rsi + INST_op0 + rax + OPERAND_fwd], 0
    jne     .trial
    inc     edx
    jmp     .any

.trial:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    ; the instruction as NASM's first pass sees it
    lea     rdi, [rel p1_inst]
    mov     rsi, r12
    mov     ecx, INST_SIZE
    rep movsb
    lea     r13, [rel p1_inst]
    movzx   ecx, byte [r13 + INST_nops]
    xor     edx, edx
.op:
    cmp     edx, ecx
    jae     .measure
    imul    eax, edx, OPERAND_SIZE
    lea     rdi, [r13 + INST_op0 + rax]
    inc     edx
    cmp     byte [rdi + OPERAND_fwd], 0
    je      .op
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    je      .op_mem
    cmp     byte [rdi + OPERAND_kind], OP_SYMBOL
    je      .op_imm
    cmp     byte [rdi + OPERAND_kind], OP_IMM
    jne     .op
.op_imm:
    mov     byte [rdi + OPERAND_kind], OP_IMM
    mov     qword [rdi + OPERAND_imm], 0   ; unknown: small
    mov     qword [rdi + OPERAND_sym], 0
    jmp     .op
.op_mem:
    mov     qword [rdi + OPERAND_imm], 0x12345678  ; unknown: disp32
    mov     qword [rdi + OPERAND_sym], 0
    cmp     byte [rdi + OPERAND_base], REG_RIP
    jne     .op
    mov     byte [rdi + OPERAND_base], 0xFF        ; no [rel] yet: absolute
    and     byte [rdi + OPERAND_flags], ~OP_FLAG_REL
    jmp     .op
.measure:
    ; (the encoder keeps rbx, r12 and r13 only)
    mov     r14, [rbx + ASMCTX_curr_sec]
    mov     [rel p1_sec], r14
    mov     r15, [r14 + SECTION_size]      ; where the instruction starts
    mov     [rel p1_start], r15
    mov     eax, [rbx + ASMCTX_nrelocs]
    mov     [rel p1_nrelocs], rax
    extern  relax_count, relax_truncate
    call    relax_count
    mov     [rel p1_nrelax], rax
    mov     rdi, rbx
    mov     rsi, r13
    extern  reloc_quiet
    mov     byte [rel reloc_quiet], 1      ; (a trial: no warnings)
    call    amd64_encode_instruction
    mov     byte [rel reloc_quiet], 0
    mov     r13, -1
    test    rax, rax
    jnz     .undo
    mov     rax, [rel p1_sec]
    mov     r13, [rax + SECTION_size]
    sub     r13, [rel p1_start]            ; NASM's first-pass size
.undo:
    mov     rdi, [rel p1_nrelax]
    call    relax_truncate
    mov     rax, [rel p1_nrelocs]
    mov     [rbx + ASMCTX_nrelocs], eax
    mov     rax, [rel p1_sec]
    mov     rcx, [rel p1_start]
    mov     [rax + SECTION_size], rcx
    ; the real encoding
    mov     rdi, rbx
    mov     rsi, r12
    call    amd64_encode_instruction
    test    rax, rax
    jnz     .ret
    test    r13, r13
    js      .ok
    mov     rcx, r13
    mov     rdx, [rel p1_sec]
    mov     rax, [rdx + SECTION_size]
    sub     rax, [rel p1_start]
    sub     rcx, rax                       ; first pass - final
    jz      .ok
    mov     edi, RELAX_P1
    mov     rsi, [rel p1_start]
    xor     edx, edx
    xor     r8d, r8d
    extern  relax_note
    call    relax_note
.ok:
    xor     eax, eax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
alignb 8
p1_sec:     resq 1
p1_start:   resq 1
p1_nrelocs: resq 1
p1_nrelax:  resq 1
p1_inst:    resb INST_SIZE
