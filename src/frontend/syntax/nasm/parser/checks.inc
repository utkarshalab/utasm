; ============================================================================
; File        : src/frontend/syntax/nasm/parser/checks.inc
; Part of     : src/frontend/syntax/nasm/parser.s (%included by it, in this place)
; Contents    : register and mnemonic lookup (the hash indexes), operand size checks, lock / HLE / prefix checks
; ============================================================================


[SECTION .text]

;*
; * [parser_is_reg_name]
; * Purpose: Is the word one of the target's registers? (AT&T's noprefix:
; *   src/frontend/syntax/gas/att.s)
; * Input  : RDI = the word
; * Output : EAX = 1 / 0. Preserves rbx, r12-r15.
; ;
global parser_is_reg_name
parser_is_reg_name:
    push    rdi
    call    parser_get_arch_tables
    pop     rsi
    mov     rdi, rdx                       ; the register table
    call    parser_is_register
    cmp     rax, ERR
    setne   al
    movzx   eax, al
    ret

;*
; * [parser_is_register]
; * Input: RSI = String, RDI = Table Pointer
; * Output: RAX = the entry's value (the first with that hash), or ERR
; * Every operand word is looked up: the first table asked (the target's)
; * is indexed by hash then, as parser_lookup_mnemonic's; another walked.
; ;
global parser_is_register
parser_is_register:
    prologue
    hash_fnv1a_64_ci rsi, r8
    cmp     rdi, [rel reg_idx_of]
    jne     .other
.probe:
    mov     rax, r8
    mov     rcx, [rel reg_idx_slots]
.slot:
    and     rax, [rel reg_idx_mask]
    mov     rdx, [rcx + rax * 8]
    test    rdx, rdx
    jz      .not_found
    cmp     [rdx], r8
    je      .slot_hit
    inc     rax
    jmp     .slot
.slot_hit:
    mov     rdi, rdx
    jmp     .found
.other:
    cmp     qword [rel reg_idx_of], 0
    jne     .loop                          ; (another table: the walk)
    call    reg_index_build
    cmp     rdi, [rel reg_idx_of]
    je      .probe
.loop:
    mov     rax, [rdi]
    test    rax, rax
    jz      .not_found
    cmp     rax, r8
    je      .found
    add     rdi, 16
    jmp     .loop

.found:
    mov     rax, [rdi + 8]
    epilogue

.not_found:
    mov     rax, ERR
    epilogue

; reg_index_build: index the register table RDI (16-byte entries, a zero
; hash last) by hash into reg_idx_slots - its first entry of a hash kept.
; No memory: reg_idx_of -1, the walk. Preserves every register.
reg_index_build:
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    xor     ecx, ecx
.count:
    cmp     qword [rdi + rcx * 8], 0
    je      .counted
    add     rcx, 2
    jmp     .count
.counted:
    mov     eax, 64
.size:
    cmp     rax, rcx                       ; (rcx = entries * 2)
    jae     .sized
    shl     rax, 1
    jmp     .size
.sized:
    lea     rdx, [rax - 1]
    mov     [rel reg_idx_mask], rdx
    lea     rsi, [rax * 8]
    extern  mem_reserve
    call    mem_reserve
    test    rax, rax
    jnz     .no_index
    mov     [rel reg_idx_slots], rdx
    mov     r8, rdx
    mov     rsi, [rsp + 32]                ; the table (pushed fifth)
    mov     [rel reg_idx_of], rsi
.entry:
    mov     r9, [rsi]
    test    r9, r9
    jz      .ret
    mov     rax, r9
.place:
    and     rax, [rel reg_idx_mask]
    mov     r10, [r8 + rax * 8]
    test    r10, r10
    jz      .put
    cmp     [r10], r9
    je      .placed                        ; the first entry of a name stays
    inc     rax
    jmp     .place
.put:
    mov     [r8 + rax * 8], rsi
.placed:
    add     rsi, 16
    jmp     .entry
.no_index:
    mov     qword [rel reg_idx_of], -1
.ret:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    ret

;*
; * [parser_lookup_mnemonic]
; * Input: RDI = Hash, RSI = Table Pointer
; * Output: RAX = the mnemonic's id (the first entry with that hash), or 0
; * The table (16-byte entries, a zero hash last) was walked for every
; * statement - all of it for a word that is no instruction; it is indexed
; * by hash the first time it is used.
; ;
parser_lookup_mnemonic:
    cmp     rsi, [rel mnc_idx_of]
    jne     .index
.probe:
    push    rcx
    mov     rax, rdi
    mov     rcx, [rel mnc_idx_slots]
.slot:
    and     rax, [rel mnc_idx_mask]
    mov     rsi, [rcx + rax * 8]
    test    rsi, rsi
    jz      .not_found
    cmp     [rsi], rdi
    je      .found
    inc     rax
    jmp     .slot
.found:
    movzx   eax, word [rsi + 9]
    pop     rcx
    ret
.not_found:
    xor     eax, eax
    pop     rcx
    ret
.index:
    ; slots: a power of two, at least twice the entries
    push    rcx
    push    rdx
    push    rdi
    push    rsi
    push    r8
    push    r9
    push    r10
    push    r11
    xor     ecx, ecx
.count:
    cmp     qword [rsi + rcx * 8], 0
    je      .counted
    add     rcx, 2
    jmp     .count
.counted:
    mov     eax, 64
.size:
    cmp     rax, rcx                       ; (rcx = entries * 2)
    jae     .sized
    shl     rax, 1
    jmp     .size
.sized:
    lea     rdx, [rax - 1]
    mov     [rel mnc_idx_mask], rdx
    lea     rsi, [rax * 8]
    extern  mem_reserve
    call    mem_reserve
    test    rax, rax
    jnz     .no_index
    mov     [rel mnc_idx_slots], rdx
    mov     r8, rdx
    mov     rsi, [rsp + 32]                ; the table (pushed fourth)
    mov     [rel mnc_idx_of], rsi
.entry:
    mov     r9, [rsi]
    test    r9, r9
    jz      .indexed
    mov     rax, r9
.place:
    and     rax, [rel mnc_idx_mask]
    mov     r10, [r8 + rax * 8]
    test    r10, r10
    jz      .put
    cmp     [r10], r9
    je      .placed                        ; the first entry of a name stays
    inc     rax
    jmp     .place
.put:
    mov     [r8 + rax * 8], rsi
.placed:
    add     rsi, 16
    jmp     .entry
.indexed:
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    jmp     .probe
.no_index:
    ; (no memory: the walk)
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
.walk:
    mov     rax, [rsi]
    test    rax, rax
    jz      .walk_none
    cmp     rax, rdi
    je      .walk_found
    add     rsi, 16
    jmp     .walk
.walk_found:
    movzx   eax, word [rsi + 9]
    ret
.walk_none:
    xor     eax, eax
    ret

[SECTION .bss]
alignb 8
mnc_idx_of:     resq 1                  ; the table indexed (parser_lookup_mnemonic)
mnc_idx_slots:  resq 1                  ; its entries by hash
mnc_idx_mask:   resq 1
reg_idx_of:     resq 1                  ; the table indexed (parser_is_register)
reg_idx_slots:  resq 1                  ; its entries by hash
reg_idx_mask:   resq 1
[SECTION .text]

; parser_check_size: a memory operand with no size where nothing else gives
; one - "inc [rax]", "mov [rax], 5", "shl [rax], cl" - is NASM's "operation
; size not specified" (r15 = INST); utasm used to pick a size and say
; nothing (a dword, a qword). The instructions are those NASM asks a size
; for, by form: one memory operand, memory and a number, memory and cl.
; rax = OK or EXIT_NO_SIZE. Preserves rbx, r12-r15.
parser_check_size:
    xor     eax, eax
    mov     rcx, [rbx + PREP_ctx]
    cmp     byte [rcx + ASMCTX_target], TARGET_AMD64
    jne     .ret
    cmp     byte [r15 + INST_op0 + OPERAND_kind], OP_MEM
    jne     .ret
    cmp     byte [r15 + INST_op0 + OPERAND_size], 0
    jne     .ret
    cmp     word [r15 + INST_op0 + OPERAND_xsize], 0
    jne     .ret
    movzx   ecx, byte [r15 + INST_nops]
    lea     rsi, [rel nosize_m]
    cmp     ecx, 1
    je      .listed
    cmp     ecx, 2
    jne     .ret
    movzx   edx, byte [r15 + INST_op0 + OPERAND_SIZE + OPERAND_kind]
    lea     rsi, [rel nosize_mi]
    cmp     edx, OP_IMM
    je      .mem_imm
    cmp     edx, OP_SYMBOL
    je      .mem_imm
    cmp     edx, OP_REG
    jne     .ret
    cmp     byte [r15 + INST_op0 + OPERAND_SIZE + OPERAND_reg], REG_RCX ; cl
    jne     .ret
    cmp     byte [r15 + INST_op0 + OPERAND_SIZE + OPERAND_size], 8
    jne     .ret
    lea     rsi, [rel nosize_mc]
.listed:
    push    r12
    mov     r12, rsi
.name:
    cmp     byte [r12], 0
    je      .unlisted
    mov     rdi, [rel inst_mnem_text]
    mov     rsi, r12
    call    str_cmp_kw
    test    rax, rax
    jz      .no_size
.skip:
    inc     r12
    cmp     byte [r12 - 1], 0
    jne     .skip
    jmp     .name
.no_size:
    mov     eax, EXIT_NO_SIZE
    pop     r12
    ret
.unlisted:
    xor     eax, eax
    pop     r12
.ret:
    ret
.mem_imm:
    ; "mov [rax], dword 5": the immediate's size is the operation's, in the
    ; forms NASM sizes so (mov, test and the ALU group)
    movzx   ecx, byte [r15 + INST_op0 + OPERAND_SIZE + OPERAND_size]
    cmp     ecx, 8
    je      .imm_sized
    cmp     ecx, 16
    je      .imm_sized
    cmp     ecx, 32
    jne     .listed
.imm_sized:
    push    r12
    push    rcx
    lea     r12, [rel size_from_imm]
.adopt:
    cmp     byte [r12], 0
    je      .adopt_none
    mov     rdi, [rel inst_mnem_text]
    mov     rsi, r12
    call    str_cmp_kw
    test    rax, rax
    jz      .adopt_it
.adopt_skip:
    inc     r12
    cmp     byte [r12 - 1], 0
    jne     .adopt_skip
    jmp     .adopt
.adopt_it:
    pop     rcx
    pop     r12
    mov     [r15 + INST_op0 + OPERAND_size], cl
    xor     eax, eax
    ret
.adopt_none:
    pop     rcx
    pop     r12
    lea     rsi, [rel nosize_mi]
    jmp     .listed

[SECTION .rodata]
; the instructions NASM asks a size for (found by asking NASM: every
; mnemonic, unsized, in each form)
nosize_m:
    db "dec", 0, "div", 0, "fadd", 0, "fcom", 0, "fdiv", 0, "fld", 0, "fmul", 0
    db "fst", 0, "fstp", 0, "fsub", 0, "idiv", 0, "imul", 0, "inc", 0, "mul", 0
    db "neg", 0, "nop", 0, "not", 0, "pop", 0, "push", 0, 0
size_from_imm:
    db "adc", 0, "add", 0, "and", 0, "cmp", 0, "mov", 0, "or", 0, "sbb", 0
    db "sub", 0, "test", 0, "xor", 0, 0
nosize_mi:
    db "adc", 0, "add", 0, "and", 0, "bt", 0, "btc", 0, "btr", 0, "bts", 0
    db "cmp", 0, "mov", 0, "or", 0, "rcl", 0, "rcr", 0, "rol", 0, "ror", 0
    db "sar", 0, "sbb", 0, "shl", 0, "shr", 0, "sub", 0, "test", 0, "xor", 0
    db "sal", 0, 0
nosize_mc:
    db "rcl", 0, "rcr", 0, "rol", 0, "ror", 0, "sar", 0, "shl", 0, "shr", 0
    db "sal", 0, 0
[SECTION .text]

; parser_check_lock: NASM's warnings for a LOCK prefix (r15 = INST): on an
; instruction that cannot be locked, or without a memory operand,
; "instruction is not lockable"; on XCHG with one, which locks anyway,
; "superfluous LOCK prefix on XCHG instruction". Preserves rbx, r12-r15.
parser_check_lock:
    xor     ecx, ecx
.prefix:
    cmp     byte [r15 + INST_prefixes + rcx], 0xF0
    je      .locked
    inc     ecx
    cmp     ecx, 4
    jb      .prefix
    ret
.locked:
    push    r12
    push    r13
    ; a memory operand?
    movzx   r12d, byte [r15 + INST_nops]
    lea     r13, [r15 + INST_op0]
.operand:
    test    r12d, r12d
    jz      .not_lockable
    cmp     byte [r13 + OPERAND_kind], OP_MEM
    je      .has_memory
    add     r13, OPERAND_SIZE
    dec     r12d
    jmp     .operand
.has_memory:
    ; one of the instructions that can be locked?
    lea     r12, [rel lockable_names]
.name:
    cmp     byte [r12], 0
    je      .not_lockable
    mov     rdi, [rel inst_mnem_text]
    mov     rsi, r12
    call    str_cmp_kw
    test    rax, rax
    jz      .lockable
.skip:
    inc     r12
    cmp     byte [r12 - 1], 0
    jne     .skip
    jmp     .name
.lockable:
    mov     rdi, [rel inst_mnem_text]
    lea     rsi, [rel str_xchg]
    call    str_cmp_kw
    test    rax, rax
    jnz     .memory_first
    mov     edi, WC_PREFIX_LOCK_XCHG
    lea     r12, [rel s_lock_xchg]
    jmp     .warn
.memory_first:
    ; "lock add ecx, [rax]": the memory is not what changes - NASM's
    ; error too (xchg's may be either)
    cmp     byte [r15 + INST_op0 + OPERAND_kind], OP_MEM
    je      .out
.not_lockable:
    mov     edi, WC_PREFIX_LOCK_ERROR
    lea     r12, [rel s_not_lockable]
.warn:
    call    warn_begin
    mov     rsi, r12
    call    warn_text
    call    warn_end
.out:
    pop     r13
    pop     r12
    ret

; parser_check_hle: NASM's warnings for xacquire / xrelease (r15 = INST):
; with an instruction LOCK can go before, its memory operand first,
; "xacquire with this instruction requires lock" when it has no LOCK (xchg
; locks anyway); xrelease with a mov to memory is right, xacquire there is
; not; on anything else "xrelease invalid with this instruction".
; Preserves rbx, r12-r15.
parser_check_hle:
    movzx   eax, byte [r15 + INST_flags]
    and     eax, INSTF_XACQUIRE | INSTF_XRELEASE
    jz      .ret
    push    r12
    push    r13
    lea     r13, [rel s_xacquire]
    test    eax, INSTF_XACQUIRE
    jnz     .which
    lea     r13, [rel s_xrelease]
.which:
    mov     rdi, [rel inst_mnem_text]
    lea     rsi, [rel str_mov_hle]
    call    str_cmp_kw
    test    rax, rax
    jnz     .not_mov
    cmp     byte [r15 + INST_op0 + OPERAND_kind], OP_MEM
    jne     .invalid
    test    byte [r15 + INST_flags], INSTF_XRELEASE
    jnz     .out
    jmp     .invalid
.not_mov:
    lea     r12, [rel lockable_names]
.name:
    cmp     byte [r12], 0
    je      .invalid
    mov     rdi, [rel inst_mnem_text]
    mov     rsi, r12
    call    str_cmp_kw
    test    rax, rax
    jz      .lockable
.skip:
    inc     r12
    cmp     byte [r12 - 1], 0
    jne     .skip
    jmp     .name
.lockable:
    cmp     byte [r15 + INST_op0 + OPERAND_kind], OP_MEM
    jne     .invalid
    mov     rdi, [rel inst_mnem_text]
    lea     rsi, [rel str_xchg]
    call    str_cmp_kw
    test    rax, rax
    jz      .out                           ; xchg: locked anyway
    xor     ecx, ecx
.lock:
    cmp     byte [r15 + INST_prefixes + rcx], 0xF0
    je      .out
    inc     ecx
    cmp     ecx, 4
    jb      .lock
    lea     r12, [rel s_hle_lock]
    jmp     .warn
.invalid:
    lea     r12, [rel s_hle_invalid]
.warn:
    mov     edi, WC_PREFIX_HLE
    call    warn_begin
    mov     rsi, r13
    call    warn_text
    mov     rsi, r12
    call    warn_text
    call    warn_end
.out:
    pop     r13
    pop     r12
.ret:
    ret

[SECTION .rodata]
; the instructions LOCK may come before (with a memory operand)
lockable_names:
    db "add", 0, "adc", 0, "and", 0, "btc", 0, "btr", 0, "bts", 0
    db "cmpxchg", 0, "cmpxchg8b", 0, "cmpxchg16b", 0, "dec", 0, "inc", 0
    db "neg", 0, "not", 0, "or", 0, "sbb", 0, "sub", 0, "xor", 0
    db "xadd", 0, "xchg", 0, 0
str_xchg:       db "xchg", 0
s_lock_xchg:    db "superfluous LOCK prefix on XCHG instruction", 0
s_not_lockable: db "instruction is not lockable", 0
str_mov_hle:    db "mov", 0
s_xacquire:     db "xacquire", 0
s_xrelease:     db "xrelease", 0
s_hle_lock:     db " with this instruction requires lock", 0
s_hle_invalid:  db " invalid with this instruction", 0
[SECTION .bss]
alignb 8
inst_mnem_text: resq 1                  ; the mnemonic of the instruction read
[SECTION .text]

;*
; * [parser_check_prefix]
; * Purpose: Is the word an instruction prefix? rep/repe/repz, repne/repnz,
; *   lock, xacquire/xrelease, bnd, o16/o32/o64, a16/a32/a64 and the
; *   segment prefixes cs ds es ss fs gs, as NASM writes them.
; * Input: RSI = String pointer
; * Output: EAX = Prefix byte, 2 / 3 / 4 (a16 / a32 / a64: the caller
; *         decides), 5 / 6 / 7 (o16 / o32 / o64: the operation size),
; *         8 / 9 (xacquire / xrelease) or 0
; ;
parser_check_prefix:
    push    r12
    push    r13
    mov     r12, rsi
    lea     r13, [rel prefix_words]
    test    r12, r12
    jz      .none
    ; only a word with a prefix's first letter is compared (every
    ; mnemonic comes here)
    movzx   eax, byte [r12]
    or      eax, 0x20
.word:
    cmp     byte [r13], 0
    je      .none
    cmp     al, [r13]
    jne     .next
    mov     rdi, r12
    mov     rsi, r13
    call    str_cmp_kw
    test    rax, rax
    jz      .hit
    movzx   eax, byte [r12]
    or      eax, 0x20
.next:
    add     r13, 10
    jmp     .word
.hit:
    movzx   eax, byte [r13 + 9]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    mov     rdi, r12
    mov     rsi, r13
    pop     r13
    pop     r12
    ret

[SECTION .rodata]
; name (9 bytes) + the prefix byte or the code above
prefix_words:
    db "rep", 0, 0,0,0,0,0, 0xF3
    db "repe", 0, 0,0,0,0, 0xF3
    db "repz", 0, 0,0,0,0, 0xF3
    db "repne", 0, 0,0,0, 0xF2
    db "repnz", 0, 0,0,0, 0xF2
    db "lock", 0, 0,0,0,0, 0xF0
    db "xacquire", 0, 8
    db "xrelease", 0, 9
    db "bnd", 0, 0,0,0,0,0, 0xF2
    db "notrack", 0, 0, 0x3E               ; CET: an indirect jmp / call IBT lets be
    db "ht", 0, 0,0,0,0,0,0, 0x3E          ; GNU's branch hints: taken
    db "hnt", 0, 0,0,0,0,0, 0x2E           ; ... not taken
    db "o16", 0, 0,0,0,0,0, 5              ; the operation sizes
    db "o32", 0, 0,0,0,0,0, 6
    db "o64", 0, 0,0,0,0,0, 7
    db "osp", 0, 0,0,0,0,0, 0x66           ; the size prefixes as they are
    db "asp", 0, 0,0,0,0,0, 0x67
    db "a16", 0, 0,0,0,0,0, 2              ; the address sizes: by the mode
    db "a32", 0, 0,0,0,0,0, 3
    db "a64", 0, 0,0,0,0,0, 4
    db "cs", 0, 0,0,0,0,0,0, 0x2E
    db "ds", 0, 0,0,0,0,0,0, 0x3E
    db "es", 0, 0,0,0,0,0,0, 0x26
    db "ss", 0, 0,0,0,0,0,0, 0x36
    db "fs", 0, 0,0,0,0,0,0, 0x64
    db "gs", 0, 0,0,0,0,0,0, 0x65
    db 0
