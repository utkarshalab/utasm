; ============================================================================
; File        : src/encode/x86/encoder/support.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : CPU forms, GOT forms, obsolete instructions, immediate guesses, rip-relative displacements, relaxation kinds, disp8*N, branch widths, relocation errors
; ============================================================================


;*
; * [amd64_cpu_forms]
; * Purpose: Under "cpu 8086" / 186 / 286 (cpu_num), NASM's levels of an
; *   instruction's forms (the parser checked its mnemonic's lowest): a
; *   form of 32-bit operands is 386 - a 32- or 64-bit general register,
; *   in 16-bit code a 66 prefix, in 32-bit code push / pop of memory or
; *   an immediate not of a word (the address size counts for nothing, as
; *   in NASM); and under 8086, push of an immediate, imul with one
; *   and a shift or rotate by a count other than 1 are 186.
; * Input : R12 = INST, RBX = AsmCtx (the instruction just encoded)
; * Output: EAX = 0, or EXIT_CPU_LEVEL. Preserves rbx, r12, r13.
; ;
amd64_cpu_forms:
    movzx   ecx, byte [rel cpu_num]
    test    ecx, ecx
    jz      .cf_ok
    cmp     ecx, 4
    jae     .cf_ok                         ; 386 on: every such form there
    ; a 32- or 64-bit general register
    movzx   r8d, byte [r12 + INST_nops]
    xor     edx, edx
.cf_op:
    cmp     edx, r8d
    jae     .cf_regs_done
    imul    eax, edx, OPERAND_SIZE
    lea     rsi, [r12 + INST_op0 + rax]
    inc     edx
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .cf_op
    cmp     byte [rsi + OPERAND_reg], 32
    jae     .cf_op                         ; (not a general one)
    cmp     byte [rsi + OPERAND_size], 32
    jae     .cf_level
    jmp     .cf_op
.cf_regs_done:
    movzx   eax, word [r12 + INST_op_id]
    cmp     byte [rel asm_bits], 16
    jne     .cf_wide
    ; 16-bit code: a 66 / 67 among its prefixes
    mov     r9, [rbx + ASMCTX_curr_sec]
    test    r9, r9
    jz      .cf_186
    mov     rsi, [r9 + SECTION_data]
    test    rsi, rsi
    jz      .cf_186
    mov     rdi, [r9 + SECTION_size]
    mov     r10d, [rbx + ASMCTX_inst_len]
    mov     r11, rdi
    sub     r11, r10                       ; its first byte
.cf_pfx:
    cmp     r11, rdi
    jae     .cf_186
    movzx   r10d, byte [rsi + r11]
    inc     r11
    cmp     r10d, 0x66
    je      .cf_level
    cmp     r10d, 0x67
    je      .cf_pfx                        ; (the address size: NASM's level
                                           ; leaves it out)
    cmp     r10d, 0xF0
    je      .cf_pfx
    cmp     r10d, 0xF2
    je      .cf_pfx
    cmp     r10d, 0xF3
    je      .cf_pfx
    cmp     r10d, 0x2E
    je      .cf_pfx
    cmp     r10d, 0x3E
    je      .cf_pfx
    cmp     r10d, 0x26
    je      .cf_pfx
    cmp     r10d, 0x36
    je      .cf_pfx
    cmp     r10d, 0x64
    je      .cf_pfx
    cmp     r10d, 0x65
    je      .cf_pfx
    jmp     .cf_186
.cf_wide:
    ; 32-bit code: a 32-bit (or wider) memory operand is a 386 form - but
    ; x87's (D8-DF: fld dword is the 8087's)
    xor     edx, edx
.cf_mem:
    cmp     edx, r8d
    jae     .cf_mem_done
    imul    r9d, edx, OPERAND_SIZE
    lea     rsi, [r12 + INST_op0 + r9]
    inc     edx
    cmp     byte [rsi + OPERAND_kind], OP_MEM
    jne     .cf_mem
    ; jmp / call far [m]: m16:32 (word: m16:16, 8086's)
    test    byte [rsi + OPERAND_flags], OP_FLAG_FAR
    jz      .cf_mem_size
    cmp     byte [rsi + OPERAND_size], 16
    jne     .cf_level
    jmp     .cf_mem
.cf_mem_size:
    cmp     byte [rsi + OPERAND_size], 32
    jb      .cf_mem
    call    .cf_opcode
    sub     r10d, 0xD8
    cmp     r10d, 7
    jbe     .cf_mem_done
    jmp     .cf_level
.cf_mem_done:
    movzx   eax, word [r12 + INST_op_id]
    ; push / pop of memory or an immediate is 32-bit
    cmp     eax, 1583                      ; PUSH
    je      .cf_stack
    cmp     eax, 1534                      ; POP
    jne     .cf_186
.cf_stack:
    cmp     byte [r12 + INST_nops], 1
    jne     .cf_186
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    je      .cf_186
    cmp     byte [r12 + INST_op0 + OPERAND_size], 16
    jne     .cf_level                      ; (push word [eax]: 8086's)
.cf_186:
    cmp     ecx, 2
    jae     .cf_ok
    ; 8086: the 186's forms
    cmp     eax, 1583                      ; push imm
    jne     .cf_not_push
    movzx   edx, byte [r12 + INST_op0 + OPERAND_kind]
    cmp     edx, OP_IMM
    je      .cf_level
    cmp     edx, OP_SYMBOL
    je      .cf_level
    jmp     .cf_ok
.cf_not_push:
    cmp     eax, 1276                      ; imul r, r/m, imm / imul r, imm
    jne     .cf_not_imul
    cmp     byte [r12 + INST_nops], 2
    jb      .cf_ok
    movzx   edx, byte [r12 + INST_nops]
    dec     edx
    imul    edx, edx, OPERAND_SIZE
    movzx   edx, byte [r12 + INST_op0 + rdx + OPERAND_kind]
    cmp     edx, OP_IMM
    je      .cf_level
    cmp     edx, OP_SYMBOL
    je      .cf_level
    jmp     .cf_ok
.cf_not_imul:
    lea     rsi, [rel cf_shift_ids]
.cf_shift:
    movzx   edx, word [rsi]
    test    edx, edx
    jz      .cf_ok
    add     rsi, 2
    cmp     edx, eax
    jne     .cf_shift
    cmp     byte [r12 + INST_nops], 2
    jne     .cf_ok
    cmp     byte [r12 + INST_op1 + OPERAND_kind], OP_IMM
    jne     .cf_ok
    cmp     qword [r12 + INST_op1 + OPERAND_imm], 1
    jne     .cf_level
.cf_ok:
    xor     eax, eax
    ret
.cf_level:
    mov     eax, EXIT_CPU_LEVEL
    ret
; .cf_opcode: r10d = the instruction's first byte past its prefixes (0
; when there are no bytes). Preserves rax, rcx, rdx, rsi, r8.
.cf_opcode:
    push    rsi
    push    rdi
    push    r11
    xor     r10d, r10d
    mov     r9, [rbx + ASMCTX_curr_sec]
    test    r9, r9
    jz      .co_ret
    mov     rsi, [r9 + SECTION_data]
    test    rsi, rsi
    jz      .co_ret
    mov     rdi, [r9 + SECTION_size]
    mov     r11d, [rbx + ASMCTX_inst_len]
    neg     r11
    add     r11, rdi
.co_byte:
    cmp     r11, rdi
    jae     .co_none
    movzx   r10d, byte [rsi + r11]
    inc     r11
    cmp     r10d, 0x66
    je      .co_byte
    cmp     r10d, 0x67
    je      .co_byte
    cmp     r10d, 0xF0
    je      .co_byte
    cmp     r10d, 0xF2
    je      .co_byte
    cmp     r10d, 0xF3
    je      .co_byte
    cmp     r10d, 0x2E
    je      .co_byte
    cmp     r10d, 0x3E
    je      .co_byte
    cmp     r10d, 0x26
    je      .co_byte
    cmp     r10d, 0x36
    je      .co_byte
    cmp     r10d, 0x64
    je      .co_byte
    cmp     r10d, 0x65
    je      .co_byte
    cmp     r10d, 0x9B                     ; (wait: fstsw's)
    je      .co_byte
    jmp     .co_ret
.co_none:
    xor     r10d, r10d
.co_ret:
    pop     r11
    pop     rdi
    pop     rsi
    ret

;*
; * [amd64_gas_got]
; * Purpose: GNU's syntax (gas_names), the instruction just encoded: its
; *   GOT relocations as GNU as writes them - the relaxable ones where the
; *   linker may turn the GOT load into a direct one (GOTPCRELX, its REX
; *   form, R_386_GOT32X): a mov load (8B), call / jmp (FF /2, /4), test
; *   (85) or a binary operation into a register ((op & C7) = 03). A GOT
; *   or TLS relocation also has GNU as name _GLOBAL_OFFSET_TABLE_
; *   (gas_got_wanted; parser_sizes adds it). Preserves rax, rbx, r12, r13.
; * Input : R12 = INST, RBX = AsmCtx
; ;
amd64_gas_got:
    extern  gas_names
    cmp     byte [rel gas_names], 0
    jne     .gg_go
    ret
.gg_go:
    push    rax
    push    r14
    push    r15
    mov     r14, [rbx + ASMCTX_curr_sec]
    test    r14, r14
    jz      .gg_ret
    mov     r15, [r14 + SECTION_size]
    mov     eax, [rbx + ASMCTX_inst_len]
    sub     r15, rax                       ; the instruction's start
    mov     ecx, [rbx + ASMCTX_nrelocs]
.gg_rel:
    test    ecx, ecx
    jz      .gg_ret
    dec     ecx
    imul    rdx, rcx, RELOC_SIZE
    add     rdx, [rbx + ASMCTX_relocs]
    cmp     [rdx + RELOC_section], r14
    jne     .gg_ret
    cmp     [rdx + RELOC_offset], r15
    jb      .gg_ret                        ; an earlier instruction's
    mov     eax, [rdx + RELOC_type]
    ; GOT and TLS (GOT32, GOTPCREL, DTPMOD64 ... TPOFF32, GOTOFF64,
    ; GOTPC32, GOT64): GNU as names the GOT
    cmp     eax, R_X86_64_GOT32
    je      .gg_named
    cmp     eax, R_X86_64_GOTPCREL
    je      .gg_named
    cmp     eax, 16
    jb      .gg_rel
    cmp     eax, 27
    ja      .gg_rel
    cmp     eax, 24                        ; (PC64)
    je      .gg_rel
.gg_named:
    mov     byte [rel gas_got_wanted], 1
    ; relaxable?
    cmp     eax, R_X86_64_GOTPCREL
    je      .gg_relax
    cmp     eax, R_X86_64_GOT32
    jne     .gg_rel
    extern  elf32_enabled
    cmp     byte [rel elf32_enabled], 0
    je      .gg_rel
.gg_relax:
    push    rcx
    call    .gg_opcode                     ; ZF = 1: relaxable, r8d = REX
    pop     rcx
    jne     .gg_rel
    mov     eax, [rdx + RELOC_type]
    cmp     eax, R_X86_64_GOT32
    jne     .gg_x64
    mov     dword [rdx + RELOC_type], 43   ; R_386_GOT32X (elf32.s)
    jmp     .gg_rel
.gg_x64:
    mov     dword [rdx + RELOC_type], 41   ; R_X86_64_GOTPCRELX
    test    r8d, r8d
    jz      .gg_rel
    mov     dword [rdx + RELOC_type], 42   ; R_X86_64_REX_GOTPCRELX
    jmp     .gg_rel
.gg_ret:
    pop     r15
    pop     r14
    pop     rax
    ret
; .gg_opcode: the instruction at r15 in r14's bytes - ZF = 1 when its
; opcode is one the linker relaxes, r8d = 1 with a REX prefix
.gg_opcode:
    xor     r8d, r8d
    mov     rsi, [r14 + SECTION_data]
    test    rsi, rsi
    jz      .gg_no
    mov     rcx, r15
.gg_pfx:
    movzx   eax, byte [rsi + rcx]
    inc     rcx
    cmp     eax, 0x66
    je      .gg_pfx
    cmp     eax, 0x67
    je      .gg_pfx
    cmp     eax, 0xF0
    je      .gg_pfx
    cmp     eax, 0xF2
    je      .gg_pfx
    cmp     eax, 0xF3
    je      .gg_pfx
    cmp     eax, 0x2E
    je      .gg_pfx
    cmp     eax, 0x3E
    je      .gg_pfx
    cmp     eax, 0x26
    je      .gg_pfx
    cmp     eax, 0x64
    je      .gg_pfx
    cmp     eax, 0x65
    je      .gg_pfx
    cmp     eax, 0x36
    je      .gg_pfx
    cmp     byte [rel asm_bits], 64
    jne     .gg_op
    mov     edi, eax
    and     edi, 0xF0
    cmp     edi, 0x40
    jne     .gg_op
    mov     r8d, 1                         ; REX
    movzx   eax, byte [rsi + rcx]
    inc     rcx
.gg_op:
    cmp     eax, 0x8B
    je      .gg_yes
    cmp     eax, 0x85
    je      .gg_yes
    cmp     eax, 0xFF
    je      .gg_ff
    mov     edi, eax
    and     edi, 0xC7
    cmp     edi, 0x03
    je      .gg_yes
.gg_no:
    or      eax, 1                         ; ZF = 0
    ret
.gg_ff:
    movzx   eax, byte [rsi + rcx]          ; ModRM: /2 call, /4 jmp
    shr     eax, 3
    and     eax, 7
    cmp     eax, 2
    je      .gg_yes
    cmp     eax, 4
    jne     .gg_no
.gg_yes:
    cmp     eax, eax                       ; ZF = 1
    ret

;*
; * [amd64_obsolete]
; * Purpose: NASM 3's warnings for the instructions no CPU of today has:
; *   "obsolete and removed from the target CPU", or "obsolete but valid"
; *   under "cpu" naming the instruction's own level (cpu_num): Cyrix's
; *   system and SMM set, AMD's TBM (bextr's imm form only), loadall,
; *   loadall286, cmpxchg486, ibts, xbts, umov. Preserves rax, rbx, r12,
; *   r13.
; * Input : R12 = INST
; ;
amd64_obsolete:
    push    rax
    movzx   eax, word [r12 + INST_op_id]
    lea     rsi, [rel obsolete_ids]
.ob_next:
    movzx   ecx, word [rsi]
    test    ecx, ecx
    jz      .ob_ret
    cmp     ecx, eax
    je      .ob_hit
    add     rsi, 3
    jmp     .ob_next
.ob_hit:
    cmp     eax, 1035                      ; BEXTR: TBM's form, an imm last
    jne     .ob_warn
    cmp     byte [r12 + INST_nops], 3
    jne     .ob_ret
    cmp     byte [r12 + INST_op0 + 2 * OPERAND_SIZE + OPERAND_kind], OP_IMM
    jne     .ob_ret
.ob_warn:
    movzx   ecx, byte [rsi + 2]            ; its level
    mov     edi, WC_OBSOLETE_REMOVED
    lea     rsi, [rel s_obs_removed]
    cmp     cl, [rel cpu_num]
    jne     .ob_say
    mov     edi, WC_OBSOLETE_VALID
    lea     rsi, [rel s_obs_valid]
.ob_say:
    call    amd64_warn_class
.ob_ret:
    pop     rax
    ret

;*
; * [amd64_imm_guess]
; * Purpose: Pass 1 and a distance or an expression not worked out yet
; *   ("add eax, b - a", b further on) in an instruction with the
; *   sign-extended imm8 form (the ALU group, imul, push): that form, as
; *   NASM's first pass takes it. The code is laid out with it and pass 2
; *   is given the value (src/core/known.s), which keeps the short form when it
; *   is a signed byte - 127 over "times 124 nop" and the instruction, where
; *   laid out long it measured 129 and stayed long. One that is not makes
; *   the code grow there, and known_verify runs again. Pass 1's bytes are
; *   never written (known_guessed). Not under "strict" or -O0, for a
; *   PC-relative value, or in an 8-bit operation (one size either way).
; * Input : RDI = the operand (its flags), RSI = the name in it, EDX = 1
; *         for a PC-relative value, R12 = INST, RBX = AsmCtx
; * Output: EAX = 1 to take the imm8 form. Preserves everything else.
; ;
global amd64_imm_guess
amd64_imm_guess:
    push    rcx
    push    rdx
    xor     eax, eax
    extern  known_active, known_guessed, imm_sb_ids
    cmp     byte [rel known_active], 0
    jne     .ret
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .ret
    test    byte [rdi + OPERAND_flags], OP_FLAG_STRICT
    jnz     .ret
    test    edx, edx
    jnz     .ret
    cmp     byte [r12 + INST_op0 + OPERAND_size], 8
    je      .ret
    mov     rcx, rsi
    test    rcx, rcx
    jz      .ret
    cmp     byte [rcx], RELOC_OFFSET_MARK
    je      .marked
    cmp     byte [rcx], RELOC_EXPR_MARK
    jne     .ret
.marked:
    movzx   ecx, word [r12 + INST_op_id]
    lea     rdx, [rel imm_sb_ids]
.id:
    cmp     word [rdx], 0
    je      .ret
    cmp     [rdx], cx
    je      .take
    add     rdx, 2
    jmp     .id
.take:
    mov     byte [rel known_guessed], 1
    mov     eax, 1
.ret:
    pop     rdx
    pop     rcx
    ret

;*
; * [amd64_imm_fixup]
; * Purpose: The instruction just emitted holds IMM_PLACEHOLDER where a
; *   label's address goes (see 2c in amd64_encode_instruction): the last
; *   4, 2 or 1 bytes. Zero them and record the relocation: R_X86_64_32S
; *   for the imm32 of a 64-bit operation (sign-extended), else _32, _16
; *   or _8 by width.
; * Input : RBX = AsmCtx
; * Output: RAX = OK or an error
; ;
amd64_imm_fixup:
    mov     byte [rel imm_ph_active], 0
    mov     rax, [rbx + ASMCTX_curr_sec]
    mov     rcx, [rax + SECTION_size]      ; the end of the instruction
    mov     rdx, [rax + SECTION_data]
    cmp     rcx, [rax + SECTION_cap]
    ja      .none                          ; (not in the buffer: no bytes)
    cmp     byte [rel imm_ph_byte], 0
    je      .try4
    mov     byte [rel imm_ph_byte], 0
    test    rcx, rcx
    jz      .none
    cmp     byte [rdx + rcx - 1], IMM_PLACEHOLDER & 0x7F
    je      .w1                            ; ("byte foo": its one byte)
.try4:
    cmp     rcx, 4
    jb      .try2
    cmp     dword [rdx + rcx - 4], IMM_PLACEHOLDER
    je      .w4
.try2:
    cmp     rcx, 2
    jb      .try1
    cmp     word [rdx + rcx - 2], IMM_PLACEHOLDER & 0xFFFF
    je      .w2
.try1:
    test    rcx, rcx
    jz      .none
    cmp     byte [rdx + rcx - 1], IMM_PLACEHOLDER & 0xFF
    je      .w1
.none:
    xor     eax, eax
    ret
.w4:
    sub     rcx, 4
    mov     dword [rdx + rcx], 0
    mov     r8d, R_X86_64_32
    mov     r9d, R_X86_64_PC32
    cmp     byte [rel imm_ph_wide], 0
    je      .record
    mov     r8d, R_X86_64_32S
    jmp     .record
.w2:
    sub     rcx, 2
    mov     word [rdx + rcx], 0
    mov     r8d, R_X86_64_16
    mov     r9d, R_X86_64_PC16
    jmp     .record
.w1:
    dec     rcx
    mov     byte [rdx + rcx], 0
    mov     r8d, R_X86_64_8
    mov     r9d, R_X86_64_PC8
.record:
    mov     rdi, rbx
    mov     rsi, rcx
    mov     rdx, [rel imm_ph_sym]
    mov     rcx, [rel imm_ph_addend]
    ; "mov eax, x - $", x elsewhere: PC-relative, the field's place in the
    ; addend
    cmp     byte [rel imm_ph_pcrel], 0
    je      .record_it
    mov     r8d, r9d
    add     rcx, rsi
    mov     byte [rel imm_ph_pcrel], 0
.record_it:
    call    reloc_record
    ret

[SECTION .bss]
imm_ph_sym:     resq 1              ; the label a placeholder stands for
imm_ph_addend:  resq 1
imm_ph_active:  resb 1
imm_ph_wide:    resb 1              ; a 64-bit operation
imm_ph_pcrel:   resb 1              ; PC-relative (OPERAND_pcrel)
imm_ph_byte:    resb 1              ; "byte foo": a 1-byte placeholder
global cpu_num
global gas_got_wanted
gas_got_wanted: resb 1              ; a GOT / TLS relocation (amd64_gas_got)
cpu_num:        resb 1              ; "cpu" named: 1 8086 ... 7 p6, 0x80 a later
                                    ; one, 0 none (amd64_obsolete)
[SECTION .text]

;*
; * [amd64_branch_fits_rel8]
; * Purpose: Can this JMP/Jcc use the 2-byte rel8 form?
; *   utasm assembles in a single pass, so only a target that is already
; *   defined can be measured: a backward, local label in the current
; *   section - the same targets amd64_emit_branch_disp resolves without a
; *   relocation. Choosing the short form then is always safe: everything
; *   after this instruction (labels, align padding, $-based expressions)
; *   has not been emitted yet and simply follows the shorter encoding.
; *   Forward targets are unknown here and keep the rel32 form.
; * Input : RSI = OPERAND_sym (SYMBOL*, raw name for a forward reference,
; *         or 0), RBX = AsmCtx; called before any opcode byte is emitted.
; * Output: EAX = 1 if target - (here + 2) fits in [-128, 127], else 0.
; * Clobbers: RCX, RDX.
; ;
amd64_branch_fits_rel8:
    xor     eax, eax
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .ret                           ; -O0, -O1: jumps as written (rel32)
    ; GNU's syntax: every jump starts long here and GNU as's relaxation
    ; sizes it (src/optimize/jump.s rx_gas) - a backward one too, which may
    ; have to grow when padding after it does
    extern  gas_names
    cmp     byte [rel gas_names], 0
    jne     .ret
    cmp     byte [rbx + ASMCTX_opt], OPT_MIN
    je      .ret
    test    rsi, rsi
    jz      .ret
    cmp     byte [rsi], TAG_SYMBOL
    jne     .ret                           ; raw name: forward reference
    cmp     byte [rsi + SYMBOL_kind], SYM_LABEL
    jne     .ret
    ; a label of this section, global or not, as NASM shortens it; but
    ; "wrt ..plt" and the like ask for their relocation
    extern  reloc_wrt
    cmp     byte [rel reloc_wrt], 0
    jne     .ret
    call    amd64_gas_global
    je      .ret                           ; GNU's syntax: a global's relocation
    mov     rcx, [rbx + ASMCTX_curr_sec]
    test    rcx, rcx
    jz      .ret
    mov     edx, [rcx + SECTION_index]
    cmp     edx, [rsi + SYMBOL_section]
    jne     .ret                           ; other section: needs a reloc

    mov     rdx, [rsi + SYMBOL_value]
    sub     rdx, [rcx + SECTION_size]      ; target - start of this jump
    sub     rdx, 2                         ; - length of the short form
    cmp     rdx, -128
    jl      .ret
    cmp     rdx, 127
    jg      .ret
    mov     eax, 1
.ret:
    ret

; amd64_gas_global: ZF = 1 when, in GNU's syntax (gas_names), the label
; rsi (a SYMBOL*) is not a local one: GNU as leaves a branch to it its
; relocation (PLT32 - another object may define it first) where NASM
; resolves it in the section. Preserves all but the flags.
amd64_gas_global:
    extern  gas_names
    cmp     byte [rel gas_names], 0
    je      .gg_no
    cmp     byte [rsi + SYMBOL_vis], VIS_LOCAL
    je      .gg_no
    cmp     al, al                         ; ZF = 1
    ret
.gg_no:
    cmp     byte [rel gas_names], 2        ; ZF = 0 (it is 0 or 1)
    ret

; amd64_has_evex: ZF = 1 when the instruction just encoded is EVEX (62
; after its legacy prefixes). Preserves all but the flags.
amd64_has_evex:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    mov     rax, [rbx + ASMCTX_curr_sec]
    mov     rcx, [rax + SECTION_size]
    mov     rdx, [rax + SECTION_data]
    mov     esi, [rbx + ASMCTX_inst_len]
    sub     rcx, rsi                       ; its first byte
.he_byte:
    test    esi, esi
    jz      .he_no
    movzx   eax, byte [rdx + rcx]
    cmp     eax, 0x62
    je      .he_ret                        ; (ZF = 1)
    cmp     eax, 0x66
    je      .he_next
    cmp     eax, 0x67
    je      .he_next
    cmp     eax, 0xF0
    je      .he_next
    cmp     eax, 0xF2
    je      .he_next
    cmp     eax, 0xF3
    je      .he_next
    cmp     eax, 0x2E
    je      .he_next
    cmp     eax, 0x3E
    je      .he_next
    cmp     eax, 0x26
    je      .he_next
    cmp     eax, 0x36
    je      .he_next
    cmp     eax, 0x64
    je      .he_next
    cmp     eax, 0x65
    je      .he_next
.he_no:
    test    esp, esp                       ; ZF = 0
    jmp     .he_ret
.he_next:
    inc     rcx
    dec     esi
    jmp     .he_byte
.he_ret:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

; amd64_seg_of: al = the segment prefix the operand rdi (of the INST r12)
; asks for, 0 for none - and none for a string instruction's es:[rdi]
; ("movsb es:[rdi], fs:[rsi]", "stos %al, %es:(%rdi)"): es is that
; operand's own, which no prefix changes; a 26 there overrode the other
; operand's segment instead. Preserves all but rax and the flags.
amd64_seg_of:
    movzx   eax, byte [rdi + OPERAND_segment]
    cmp     eax, 0x26
    jne     .so_ret
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .so_ret
    cmp     byte [rdi + OPERAND_base], 7   ; rdi / edi / di
    jne     .so_ret
    push    rcx
    movzx   ecx, word [r12 + INST_op_id]
    cmp     ecx, 1080                      ; cmpsd / movsd: the string forms
    je      .so_mem                        ; (a memory operand first), not SSE's
    cmp     ecx, 1420
    je      .so_mem
    cmp     ecx, 1078
    jb      .so_keep
    cmp     ecx, 1083
    jbe     .so_fixed                      ; cmps*
    cmp     ecx, 1281
    jb      .so_keep
    cmp     ecx, 1285
    jbe     .so_fixed                      ; ins*
    cmp     ecx, 1418
    je      .so_fixed                      ; movs
    cmp     ecx, 1419
    je      .so_fixed
    cmp     ecx, 1423
    je      .so_fixed
    cmp     ecx, 1425
    je      .so_fixed
    cmp     ecx, 1629
    jb      .so_keep
    cmp     ecx, 1632
    jbe     .so_fixed                      ; scas*
    cmp     ecx, 1668
    jb      .so_keep
    cmp     ecx, 1672
    jbe     .so_fixed                      ; stos*
    cmp     ecx, 7534
    je      .so_fixed                      ; scasq
    jmp     .so_keep
.so_mem:
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_MEM
    jne     .so_keep
.so_fixed:
    xor     eax, eax
.so_keep:
    pop     rcx
.so_ret:
    ret

; amd64_seg_default: ZF = 1 when, in GNU's syntax, the segment prefix al
; written on the operand rdi is the one its address uses anyway - ss with
; rbp / rsp as the base (bp in 16-bit addressing), ds with any other or
; none - which GNU as leaves out ("BYTE PTR ds:0", GCC's; tc-i386
; process_operands). NASM's syntax writes what is written. Preserves all
; but the flags.
amd64_seg_default:
    extern  gas_names
    cmp     byte [rel gas_names], 0
    je      .sd_no
    cmp     byte [rdi + OPERAND_kind], OP_MEM
    jne     .sd_no
    push    rcx
    push    rdx
    mov     edx, 0x3E                      ; ds
    movzx   ecx, byte [rdi + OPERAND_base]
    test    byte [rdi + OPERAND_flags], OP_FLAG_ADDR16
    jz      .sd_64
    cmp     ecx, 5
    je      .sd_ss                         ; [bp], [bp+si], [bp+di]
    cmp     byte [rdi + OPERAND_index], 5
    je      .sd_ss                         ; ([si+bp])
    jmp     .sd_cmp
.sd_64:
    cmp     ecx, 4
    je      .sd_ss                         ; rsp / esp (not r12)
    cmp     ecx, 5
    jne     .sd_cmp                        ; rbp / ebp (not r13)
.sd_ss:
    mov     edx, 0x36
.sd_cmp:
    cmp     al, dl
    pop     rdx
    pop     rcx
    ret
.sd_no:
    test    esp, esp                       ; ZF = 0
    ret

; amd64_gas_preempt: ZF = 1 when, in GNU's syntax, the branch whose opcode
; was just emitted keeps its relocation to the label rsi (a SYMBOL* of
; this section). GNU as resolves a jmp / jcc it relaxes (EB, E9, 7x, 0F
; 8x) in the section when the symbol cannot be preempted there - not weak
; (tc-i386 elf_symbol_resolved_in_segment_p; "jmp x@PLT" never comes
; here) - and a global as well as a local one: only a call (and loop,
; jecxz) to a global stays the linker's. Preserves all but the flags.
amd64_gas_preempt:
    call    amd64_gas_global
    jne     .gp_ret                        ; local, or NASM's syntax: resolve
    cmp     byte [rsi + SYMBOL_vis], VIS_WEAK
    je      .gp_ret                        ; (ZF = 1: may be preempted)
    push    rax
    push    rcx
    push    rdx
    mov     rax, [rbx + ASMCTX_curr_sec]
    mov     rcx, [rax + SECTION_size]
    mov     rdx, [rax + SECTION_data]
    cmp     rcx, [rax + SECTION_cap]
    ja      .gp_keep
    test    rcx, rcx
    jz      .gp_keep
    movzx   eax, byte [rdx + rcx - 1]      ; the opcode before the displacement
    cmp     eax, 0xE9
    je      .gp_resolve
    cmp     eax, 0xEB
    je      .gp_resolve
    mov     edx, eax
    and     edx, 0xF0
    cmp     edx, 0x70
    je      .gp_resolve                    ; jcc rel8
    cmp     edx, 0x80
    jne     .gp_keep
    cmp     rcx, 2
    jb      .gp_keep
    mov     rdx, [rbx + ASMCTX_curr_sec]
    mov     rdx, [rdx + SECTION_data]
    cmp     byte [rdx + rcx - 2], 0x0F
    je      .gp_resolve                    ; jcc rel32
.gp_keep:
    pop     rdx
    pop     rcx
    pop     rax
    cmp     al, al                         ; ZF = 1
    ret
.gp_resolve:
    pop     rdx
    pop     rcx
    pop     rax
    test    esp, esp                       ; ZF = 0
.gp_ret:
    ret

;*
; * [amd64_fix_rip_addend]
; * Purpose: Finish the RIP-relative relocation emitted for this instruction.
; *   emit_modrm_sib records it with a provisional pc_adjust of 4, but any
; *   immediate after the displacement also lies between it and the next
; *   instruction, which RIP points to. Now that the instruction is complete:
; *     pc_adjust = end_of_instruction - displacement_offset
; *     addend    = -pc_adjust
; *   so `cmp byte [rel x], 5` gets -5 and `mov dword [rel x], imm32` -8,
; *   exactly as NASM emits (before this, every such operand addressed past
; *   its variable by the immediate's size).
; *   The operand's displacement is added too: [rel x + 8] -> addend 8 - 4
; *   (it used to be dropped, so [rel x + 8] accessed x itself).
; * Input: RBX = AsmCtx. Clobbers: RAX, RCX, RDX.
; ;
amd64_fix_rip_addend:
    mov     eax, [rel amd64_rip_pending]
    test    eax, eax
    jz      .none
    mov     dword [rel amd64_rip_pending], 0
    dec     eax
    imul    rax, rax, RELOC_SIZE
    add     rax, [rbx + ASMCTX_relocs]     ; RAX = RELOC*
    ; PC-relative, whatever wrt made it ("cmp qword [rel x wrt ..got], 5":
    ; GOTPCREL - its addend lacked the immediate after it)
    mov     ecx, [rax + RELOC_type]
    cmp     ecx, R_X86_64_PC32
    je      .pcrel
    cmp     ecx, R_X86_64_GOTPCREL
    je      .pcrel
    cmp     ecx, R_X86_64_GOTTPOFF
    je      .pcrel
    cmp     ecx, 19                        ; R_X86_64_TLSGD
    je      .pcrel
    cmp     ecx, 20                        ; R_X86_64_TLSLD
    je      .pcrel
    cmp     ecx, R_X86_64_PLT32
    je      .pcrel
    cmp     ecx, 26                        ; R_X86_64_GOTPC32
    jne     .none
.pcrel:
    mov     rdx, [rax + RELOC_section]     ; section holding the instruction
    test    rdx, rdx
    jz      .none
    mov     rcx, [rdx + SECTION_size]      ; = end of this instruction
    sub     rcx, [rax + RELOC_offset]      ; = 4 + trailing immediate bytes
    mov     [rax + RELOC_pc_adjust], ecx
    neg     rcx
    add     rcx, [rel amd64_rip_disp]      ; + displacement written in the source
    mov     [rax + RELOC_addend], rcx
.none:
    ret

[SECTION .bss]
alignb 8
amd64_rip_disp:    resq 1          ; displacement of this instruction's RIP operand
amd64_rip_pending: resd 1          ; index + 1 of this instruction's RIP reloc
amd64_relax_kind:  resb 1          ; RELAX_JMP/JCC: this branch may be shortened
amd64_relax_cc:    resb 1          ; its condition code (jcc)
global amd64_disp8n
amd64_disp8n:      resb 1          ; EVEX disp8*N scale (0/1 = none), set by dispatch.s
global amd64_force_sib
amd64_force_sib:   resb 1          ; 1: a SIB byte even with no index (dispatch.s)
amd64_disp_emit:   resq 1          ; the disp8 value to emit (scaled for EVEX)
amd64_branch_off:  resq 1          ; offset after a branch target label (jz $+2)
amd64_branch_width: resb 1         ; a near branch's width written (amd64_branch_osize)
amd64_osize_done: resb 1           ; its 66 out already (amd64_branch_size_first)
alignb 4
global amd64_reloc_err
amd64_reloc_err:   resd 1          ; an error found deep in the encoders: the instruction fails (amd64_encode_instruction)
[SECTION .text]

extern relax_note
