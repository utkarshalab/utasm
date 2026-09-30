;
; ============================================================================
; File        : backend/encoder/dispatch.s
; Project     : utasm
; Description : Table-driven AMD64 encoder.
;
;   The instruction forms live in backend/encoder/tables/opcode.s, which
;   scripts/gen_x86_enc.py generates from the same opcode map the
;   disassembler decodes with. amd64_encode_instruction tries this encoder
;   first; when no form of the mnemonic fits the operands it falls back to
;   the hand-written encoders in encoder.s.
;
;   A form lists up to four operand types (T_* in the generator), the
;   prefix, opcode map, opcode and ModRM layout, and where each operand
;   goes: ModRM.reg, ModRM.rm, the low bits of the opcode or of a fixed
;   ModRM byte, or an immediate. The first form whose types all match wins.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/arch/amd64.inc"

extern  x86_enc_types
extern  x86_enc_index
extern  x86_enc_table
extern  x86_enc_maxid
extern  amd64_emit_byte
extern  amd64_emit_modrm_sib
extern  amd64_disp8n

; ---- operand classes (C_* in scripts/gen_x86_enc.py) ----
%define C_GPR       1
%define C_XMM       2
%define C_YMM       3
%define C_ZMM       4
%define C_K         5
%define C_ST        6
%define C_MM        7
%define C_CR        8
%define C_DR        9
%define C_SEG       10
%define C_RC        11              ; {rn-sae} .. {rz-sae}: te_num = rounding mode
%define C_SAE       12              ; {sae}
%define C_MEM       16
%define C_IMM       17

; ---- type record: db rclass, special; dw rsize, msize; db fixreg, imm ----
%define TY_RCLASS   0
%define TY_SPECIAL  1
%define TY_RSIZE    2
%define TY_MSIZE    4
%define TY_FIXREG   6
%define TY_IMM      7
%define SP_V        1               ; size 16/32/64 sets the operand size
%define SP_DQ       2               ; size 32/64 sets the operand size
%define SP_IMM      3
%define NOMEM       0xFFFF

; immediate kinds
%define IK_I8       1
%define IK_I8S      2
%define IK_I16      3
%define IK_I32      4
%define IK_IZ       5
%define IK_I64      6
%define IK_ONE      7

; ---- form record ----
%define FM_ID       0
%define FM_TYPES    2
%define FM_PFX      6
%define FM_MAP      7
%define FM_OPCODE   8
%define FM_MODRM    9
%define FM_ROLES    10
%define FM_FLAGS    12
%define FM_VL       13              ; VEX/EVEX vector length (L)
%define FM_N8       14              ; EVEX disp8*N scale
%define FM_FIXIMM   15
%define ENC_VEX     1
%define ENC_EVEX    2

; roles
%define RL_NONE     0
%define RL_REG      1
%define RL_RM       2
%define RL_VVVV     3
%define RL_PLUS     4
%define RL_IMM      5
%define RL_IS4      6               ; register in imm8[7:4] (vblendvps)

; flags
%define TF_W        1
%define TF_OSZ      2
%define TF_D64      4
%define TF_WAIT     8
%define TF_FIXIMM   16
%define TF_BCST     32              ; EVEX: a memory operand may be a {1toN} broadcast

%define MODRM_R     8
%define MODRM_NONE  9

[SECTION .bss]
te_cls:     resb 4                  ; class of each operand (0 = none)
te_num:     resb 4                  ; register number
te_high:    resb 4                  ; AH/CH/DH/BH
te_size:    resw 4                  ; size in bits (0 = not written)
te_osz:     resb 1                  ; operand size the v-types chose (0 = none)
te_regop:   resb 1                  ; operand index for each role, 0xFF = none
te_rmop:    resb 1
te_plusop:  resb 1
te_vop:     resb 1
te_vvvv:    resb 1                  ; inverted vvvv | L << 4 | pp, for the VEX bytes
te_evex:    resb 1                  ; an operand needs EVEX (mask, broadcast, rounding)

[SECTION .rodata]
; segment register IDs 24-29 (cs ds es fs gs ss) -> encoding
te_segnum:  db 1, 3, 0, 4, 5, 2

[SECTION .text]

;*
; * [amd64_table_has]
; * Purpose: Does the table have forms for this instruction's mnemonic?
; * Input  : R12 = INST
; * Output : EAX = 1 or 0
; ;
global amd64_table_has
amd64_table_has:
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, [rel x86_enc_maxid]
    ja      .no
    lea     rcx, [rel x86_enc_index]
    movzx   eax, word [rcx + rax*2]
    test    eax, eax
    jz      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

;*
; * [amd64_table_encode]
; * Purpose: Encode the instruction from the table, if a form fits.
; * Input  : RBX = AsmCtx, R12 = INST (as in amd64_encode_instruction)
; * Output : RAX = 1 encoded, 0 no form fits (nothing emitted),
; *          or EXIT_ENCODE_FAIL
; ;
global amd64_table_encode
amd64_table_encode:
    push    r13
    push    r14
    push    r15
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, [rel x86_enc_maxid]
    ja      .none
    lea     rcx, [rel x86_enc_index]
    movzx   eax, word [rcx + rax*2]
    test    eax, eax
    jz      .none
    dec     eax
    shl     eax, 4
    lea     r13, [rel x86_enc_table]
    add     r13, rax                       ; r13 = first form of the mnemonic
    call    te_classify
.try:
    call    te_match
    test    eax, eax
    jnz     .encode
    add     r13, 16
    movzx   eax, word [r13 + FM_ID]
    cmp     ax, [r12 + INST_op_id]
    je      .try
.none:
    xor     eax, eax
    jmp     .ret
.encode:
    call    te_emit
.ret:
    pop     r15
    pop     r14
    pop     r13
    ret

; ---- te_operand: rdi = operand ecx (0-3) ----
te_operand:
    mov     eax, ecx
    imul    eax, eax, OPERAND_SIZE
    lea     rdi, [r12 + INST_op0]
    add     rdi, rax
    ret

;*
; * [te_classify]
; * Fills te_cls / te_num / te_high / te_size for the INST operands.
; ;
te_classify:
    mov     byte [rel te_evex], 0
    xor     ecx, ecx
.loop:
    lea     rdx, [rel te_cls]
    mov     byte [rdx + rcx], 0
    lea     rdx, [rel te_num]
    mov     byte [rdx + rcx], 0
    lea     rdx, [rel te_high]
    mov     byte [rdx + rcx], 0
    lea     rdx, [rel te_size]
    mov     word [rdx + rcx*2], 0
    movzx   eax, byte [r12 + INST_nops]
    cmp     ecx, eax
    jae     .next
    call    te_operand
    cmp     byte [rdi + OPERAND_mask], 0
    jne     .needs_evex
    cmp     byte [rdi + OPERAND_ctrl], 0
    je      .kind
.needs_evex:
    mov     byte [rel te_evex], 1          ; {k}, {z} and {1toN} exist only in EVEX
.kind:
    movzx   eax, byte [rdi + OPERAND_kind]
    cmp     eax, OP_ROUNDING
    je      .rc
    cmp     eax, OP_SAE
    je      .sae
    cmp     eax, OP_REG
    je      .reg
    cmp     eax, OP_MEM
    je      .mem
    cmp     eax, OP_IMM
    je      .imm
    jmp     .next                          ; symbols and the rest: no class
.imm:
    mov     r8d, C_IMM
    jmp     .set_cls
.rc:
    mov     byte [rel te_evex], 1
    mov     rax, [rdi + OPERAND_imm]
    and     eax, 3
    mov     r8d, C_RC
    jmp     .set_num
.sae:
    mov     byte [rel te_evex], 1
    xor     eax, eax
    mov     r8d, C_SAE
    jmp     .set_num
.mem:
    movzx   eax, word [rdi + OPERAND_xsize]
    test    eax, eax
    jnz     .mem_size
    movzx   eax, byte [rdi + OPERAND_size]
.mem_size:
    lea     rdx, [rel te_size]
    mov     [rdx + rcx*2], ax
    mov     r8d, C_MEM
    jmp     .set_cls
.reg:
    movzx   eax, byte [rdi + OPERAND_reg]
    movzx   r9d, byte [rdi + OPERAND_size]
    cmp     eax, 16
    jb      .gpr
    cmp     eax, 24
    jb      .next
    cmp     eax, 30
    jb      .seg
    cmp     eax, 32
    jb      .next
    cmp     eax, 48
    jb      .cr
    cmp     eax, 64
    jb      .dr
    cmp     eax, 72
    jb      .next
    cmp     eax, 80
    jb      .k
    cmp     eax, 112
    jb      .vec
    cmp     eax, 120
    jb      .st
    cmp     eax, 128
    jb      .mm
    jmp     .next
.gpr:
    mov     r8d, C_GPR
    lea     rdx, [rel te_size]
    mov     [rdx + rcx*2], r9w
    movzx   r9d, byte [rdi + OPERAND_is_high]
    lea     rdx, [rel te_high]
    mov     [rdx + rcx], r9b
    jmp     .set_num
.seg:
    sub     eax, 24
    lea     rdx, [rel te_segnum]
    movzx   eax, byte [rdx + rax]
    mov     r8d, C_SEG
    jmp     .set_num
.cr:
    sub     eax, 32
    mov     r8d, C_CR
    jmp     .set_num
.dr:
    sub     eax, 48
    mov     r8d, C_DR
    jmp     .set_num
.k:
    sub     eax, 72
    mov     r8d, C_K
    jmp     .set_num
.st:
    sub     eax, 112
    mov     r8d, C_ST
    jmp     .set_num
.mm:
    sub     eax, 120
    mov     r8d, C_MM
    jmp     .set_num
.vec:
    sub     eax, 80
    movzx   r9d, word [rdi + OPERAND_xsize]
    mov     r8d, C_XMM
    cmp     r9d, 128
    je      .set_num
    mov     r8d, C_YMM
    cmp     r9d, 256
    je      .set_num
    mov     r8d, C_ZMM
    cmp     r9d, 512
    je      .set_num
    jmp     .next
.set_num:
    lea     rdx, [rel te_num]
    mov     [rdx + rcx], al
.set_cls:
    lea     rdx, [rel te_cls]
    mov     [rdx + rcx], r8b
.next:
    inc     ecx
    cmp     ecx, 4
    jb      .loop
    ret

;*
; * [te_match]
; * Input : R13 = form
; * Output: EAX = 1 when every operand fits the form's types (te_osz set)
; ;
te_match:
    push    rbx
    mov     byte [rel te_osz], 0
    cmp     byte [rel te_evex], 0
    je      .enc_ok
    movzx   eax, byte [r13 + FM_PFX]
    shr     eax, 4
    cmp     eax, ENC_EVEX
    jne     .fail                          ; masks/broadcast/rounding: EVEX forms only
.enc_ok:
    xor     ecx, ecx
.op:
    movzx   eax, byte [r13 + FM_TYPES + rcx]
    lea     rdx, [rel te_cls]
    movzx   r8d, byte [rdx + rcx]          ; r8 = class
    test    eax, eax
    jnz     .typed
    test    r8d, r8d
    jnz     .fail                          ; an operand the form does not have
    jmp     .next
.typed:
    test    r8d, r8d
    jz      .fail
    lea     rbx, [rel x86_enc_types]
    lea     rbx, [rbx + rax*8]             ; rbx = type record
    lea     rdx, [rel te_size]
    movzx   r9d, word [rdx + rcx*2]        ; r9 = size
    movzx   eax, byte [rbx + TY_SPECIAL]
    cmp     eax, SP_IMM
    je      .imm
    cmp     r8d, C_MEM
    je      .mem
    cmp     r8d, C_IMM
    je      .fail

    ; register: class, size, fixed register
    movzx   eax, byte [rbx + TY_RCLASS]
    cmp     eax, r8d
    jne     .fail
    cmp     r8d, C_XMM
    jb      .reg_fix
    cmp     r8d, C_ZMM
    ja      .reg_fix
    lea     rdx, [rel te_num]
    cmp     byte [rdx + rcx], 16
    jb      .reg_fix
    movzx   eax, byte [r13 + FM_PFX]
    shr     eax, 4
    cmp     eax, ENC_EVEX
    jne     .fail                          ; xmm16-31 need EVEX
.reg_fix:
    movzx   eax, byte [rbx + TY_FIXREG]
    cmp     eax, 0xFF
    je      .reg_size
    lea     rdx, [rel te_num]
    movzx   r10d, byte [rdx + rcx]
    cmp     eax, r10d
    jne     .fail
.reg_size:
    cmp     r8d, C_GPR
    jne     .next                          ; vector/k/st classes carry their size
    movzx   eax, word [rbx + TY_RSIZE]
    test    eax, eax
    jz      .reg_v
    cmp     eax, r9d
    jne     .fail
.reg_v:
    call    .vsize
    test    eax, eax
    jz      .fail
    jmp     .next

.mem:
    movzx   eax, word [rbx + TY_MSIZE]
    cmp     eax, NOMEM
    je      .fail
    ; {1toN}: N elements (8 bytes with W, else 4) must fill the operand
    push    rax
    call    te_operand
    pop     rax
    test    byte [rdi + OPERAND_ctrl], 2
    jz      .mem_whole
    test    byte [r13 + FM_FLAGS], TF_BCST
    jz      .fail
    movzx   r10d, byte [rdi + OPERAND_ctrl]
    shr     r10d, 2
    and     r10d, 7                        ; log2(N)
    mov     r11d, 32
    test    byte [r13 + FM_FLAGS], TF_W
    jz      .bc_elem
    mov     r11d, 64
.bc_elem:
    push    rcx
    mov     ecx, r10d
    shl     r11d, cl                       ; bits the broadcast covers
    pop     rcx
    and     eax, 0x7FFF
    cmp     eax, r11d
    jne     .fail
    jmp     .next
.mem_whole:
    movzx   r10d, byte [rbx + TY_SPECIAL]
    test    r10d, r10d
    jz      .mem_plain
    test    r9d, r9d
    jz      .next                          ; v-sized memory with no size given
    call    .vsize
    test    eax, eax
    jz      .fail
    jmp     .next
.mem_plain:
    mov     r10d, eax
    and     r10d, 0x7FFF                   ; required size (0 = any)
    jz      .next
    test    r9d, r9d
    jnz     .mem_sized
    test    eax, 0x8000                    ; strict: the size must be written
    jnz     .fail
    jmp     .next
.mem_sized:
    cmp     r9d, r10d
    jne     .fail
    jmp     .next

.imm:
    cmp     r8d, C_IMM
    jne     .fail
    call    te_operand
    mov     rax, [rdi + OPERAND_imm]
    movzx   r10d, byte [rbx + TY_IMM]
    cmp     r10d, IK_ONE
    je      .i_one
    cmp     r10d, IK_I8
    je      .i_8
    cmp     r10d, IK_I8S
    je      .i_8s
    cmp     r10d, IK_I16
    je      .i_16
    cmp     r10d, IK_I64
    je      .next
    cmp     r10d, IK_IZ
    jne     .i_32
    cmp     byte [rel te_osz], 16
    je      .i_16
    cmp     byte [rel te_osz], 64
    jne     .i_32
    ; 64-bit operation: a sign-extended imm32
    mov     rdx, -2147483648
    cmp     rax, rdx
    jl      .fail
    mov     rdx, 2147483647
    cmp     rax, rdx
    jg      .fail
    jmp     .next
.i_one:
    cmp     rax, 1
    jne     .fail
    jmp     .next
.i_8:
    cmp     rax, -128
    jl      .fail
    cmp     rax, 255
    jg      .fail
    jmp     .next
.i_8s:
    cmp     rax, -128
    jl      .fail
    cmp     rax, 127
    jg      .fail
    jmp     .next
.i_16:
    cmp     rax, -32768
    jl      .fail
    cmp     rax, 65535
    jg      .fail
    jmp     .next
.i_32:
    mov     rdx, -2147483648
    cmp     rax, rdx
    jl      .fail
    mov     rdx, 4294967295
    cmp     rax, rdx
    jg      .fail

.next:
    inc     ecx
    cmp     ecx, 4
    jb      .op
    mov     eax, 1
    pop     rbx
    ret
.fail:
    xor     eax, eax
    pop     rbx
    ret

; the v-types: r9 = size; SP_V takes 16/32/64, SP_DQ 32/64, and every
; v-sized operand of the form must have the same size. EAX = 1 if it fits.
.vsize:
    movzx   eax, byte [rbx + TY_SPECIAL]
    test    eax, eax
    jz      .vs_ok
    cmp     r9d, 64
    je      .vs_width
    cmp     r9d, 32
    je      .vs_width
    cmp     r9d, 16
    jne     .vs_no
    cmp     eax, SP_V
    jne     .vs_no
.vs_width:
    movzx   eax, word [rbx + TY_RSIZE]     ; a fixed width (RM16V) must match
    test    eax, eax
    jz      .vs_osz
    cmp     eax, r9d
    jne     .vs_no
.vs_osz:
    movzx   eax, byte [rel te_osz]
    test    eax, eax
    jz      .vs_set
    cmp     eax, r9d
    jne     .vs_no
.vs_set:
    mov     [rel te_osz], r9b
.vs_ok:
    mov     eax, 1
    ret
.vs_no:
    xor     eax, eax
    ret

;*
; * [te_emit]
; * Emits the instruction for the matched form R13.
; * Output: RAX = 1, or EXIT_ENCODE_FAIL
; ;
te_emit:
    push    rbx
    push    r14
    push    r15

    ; which operand has which role
    mov     byte [rel te_regop], 0xFF
    mov     byte [rel te_rmop], 0xFF
    mov     byte [rel te_plusop], 0xFF
    mov     byte [rel te_vop], 0xFF
    movzx   r15d, word [r13 + FM_ROLES]
    xor     ecx, ecx
.roles:
    mov     eax, r15d
    and     eax, 7
    cmp     eax, RL_REG
    jne     .r_rm
    mov     [rel te_regop], cl
.r_rm:
    cmp     eax, RL_RM
    jne     .r_plus
    mov     [rel te_rmop], cl
.r_plus:
    cmp     eax, RL_PLUS
    jne     .r_vvvv
    mov     [rel te_plusop], cl
.r_vvvv:
    cmp     eax, RL_VVVV
    jne     .r_next
    mov     [rel te_vop], cl
.r_next:
    shr     r15d, 3
    inc     ecx
    cmp     ecx, 4
    jb      .roles

    ; fwait (fstsw, fstcw, ...)
    test    byte [r13 + FM_FLAGS], TF_WAIT
    jz      .no_wait
    mov     al, 0x9B
    call    amd64_emit_byte
.no_wait:
    movzx   eax, byte [r13 + FM_PFX]
    shr     eax, 4
    cmp     eax, ENC_VEX
    je      .vex
    cmp     eax, ENC_EVEX
    je      .evex
    ; operand-size prefix
    test    byte [r13 + FM_FLAGS], TF_OSZ
    jz      .no_66
    cmp     byte [rel te_osz], 16
    jne     .no_66
    mov     al, 0x66
    call    amd64_emit_byte
.no_66:
    ; mandatory prefix
    movzx   eax, byte [r13 + FM_PFX]
    and     eax, 15
    jz      .rex
    mov     cl, 0x66
    cmp     eax, 1
    je      .pfx_put
    mov     cl, 0xF3
    cmp     eax, 2
    je      .pfx_put
    mov     cl, 0xF2
.pfx_put:
    mov     al, cl
    call    amd64_emit_byte

    ; ---- REX ----
.rex:
    call    .rexbits
    jmp     .rex_byte

; r15d = the W R X B bits (REX layout) the operands need
.rexbits:
    xor     r15d, r15d
    test    byte [r13 + FM_FLAGS], TF_W
    jnz     .rex_w
    test    byte [r13 + FM_FLAGS], TF_OSZ
    jz      .rex_r
    test    byte [r13 + FM_FLAGS], TF_D64
    jnz     .rex_r
    cmp     byte [rel te_osz], 64
    jne     .rex_r
.rex_w:
    or      r15d, 8
.rex_r:
    movzx   ecx, byte [rel te_regop]
    cmp     ecx, 0xFF
    je      .rex_b
    lea     rdx, [rel te_num]
    test    byte [rdx + rcx], 8
    jz      .rex_b
    or      r15d, 4
.rex_b:
    movzx   ecx, byte [rel te_rmop]
    cmp     ecx, 0xFF
    je      .rex_plus
    lea     rdx, [rel te_cls]
    cmp     byte [rdx + rcx], C_MEM
    je      .rex_mem
    lea     rdx, [rel te_num]
    test    byte [rdx + rcx], 8
    jz      .rex_plus
    or      r15d, 1
    jmp     .rex_plus
.rex_mem:
    call    te_operand
    movzx   eax, byte [rdi + OPERAND_base]
    cmp     eax, 0xFF
    je      .rex_idx
    cmp     eax, REG_RIP
    je      .rex_idx
    test    eax, 8
    jz      .rex_idx
    or      r15d, 1
.rex_idx:
    movzx   eax, byte [rdi + OPERAND_index]
    cmp     eax, 0xFF
    je      .rex_plus
    test    eax, 8
    jz      .rex_plus
    or      r15d, 2
.rex_plus:
    movzx   ecx, byte [rel te_plusop]
    cmp     ecx, 0xFF
    je      .rexbits_ret
    lea     rdx, [rel te_cls]
    cmp     byte [rdx + rcx], C_ST
    je      .rexbits_ret                   ; st(i) has no REX bit
    lea     rdx, [rel te_num]
    test    byte [rdx + rcx], 8
    jz      .rexbits_ret
    or      r15d, 1
.rexbits_ret:
    ret

.rex_byte:
    ; spl/bpl/sil/dil exist only with a REX prefix; ah/ch/dh/bh never do
    xor     ecx, ecx
    xor     r8d, r8d                       ; r8 = an ah/ch/dh/bh operand
.rex_8:
    lea     rdx, [rel te_cls]
    cmp     byte [rdx + rcx], C_GPR
    jne     .rex_8_next
    lea     rdx, [rel te_size]
    cmp     word [rdx + rcx*2], 8
    jne     .rex_8_next
    lea     rdx, [rel te_high]
    cmp     byte [rdx + rcx], 0
    jne     .rex_8_high
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
    cmp     eax, 4
    jb      .rex_8_next
    cmp     eax, 7
    ja      .rex_8_next
    or      r15d, 0x40
    jmp     .rex_8_next
.rex_8_high:
    mov     r8d, 1
.rex_8_next:
    inc     ecx
    cmp     ecx, 4
    jb      .rex_8
    test    r15d, r15d
    jz      .map
    test    r8d, r8d
    jnz     .fail                          ; ah/ch/dh/bh cannot take a REX prefix
    mov     eax, r15d
    or      eax, 0x40
    call    amd64_emit_byte
    jmp     .map

    ; ---- VEX prefix: C5 (0F map, no W/X/B) or C4 ----
.vex:
    call    .rexbits                       ; r15 = W R X B
    xor     eax, eax
    movzx   ecx, byte [rel te_vop]
    cmp     ecx, 0xFF
    je      .vex_v
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
.vex_v:
    not     eax
    and     eax, 15
    shl     eax, 3                         ; inverted vvvv
    movzx   ecx, byte [r13 + FM_VL]
    and     ecx, 1
    shl     ecx, 2
    or      eax, ecx                       ; L
    movzx   ecx, byte [r13 + FM_PFX]
    and     ecx, 3
    or      eax, ecx                       ; pp
    mov     [rel te_vvvv], al
    cmp     byte [r13 + FM_MAP], 2
    jne     .vex3
    test    r15d, 0x0B
    jnz     .vex3
    mov     al, 0xC5
    call    amd64_emit_byte
    movzx   eax, byte [rel te_vvvv]
    test    r15d, 4
    jnz     .vex2_put
    or      eax, 0x80                      ; R, inverted
.vex2_put:
    call    amd64_emit_byte
    jmp     .opcode
.vex3:
    mov     al, 0xC4
    call    amd64_emit_byte
    movzx   eax, byte [r13 + FM_MAP]
    dec     eax                            ; mmmmm: 1 0F, 2 0F 38, 3 0F 3A
    test    r15d, 4
    jnz     .vex3_x
    or      eax, 0x80
.vex3_x:
    test    r15d, 2
    jnz     .vex3_b
    or      eax, 0x40
.vex3_b:
    test    r15d, 1
    jnz     .vex3_put
    or      eax, 0x20
.vex3_put:
    call    amd64_emit_byte
    movzx   eax, byte [rel te_vvvv]
    test    r15d, 8
    jz      .vex3_w
    or      eax, 0x80                      ; W
.vex3_w:
    call    amd64_emit_byte
    jmp     .opcode

    ; ---- EVEX prefix: 62 P0 P1 P2 ----
; P0 = R X B R' 0 0 m m, P1 = W vvvv 1 pp, P2 = z L'L b V' aaa (R X B R' vvvv
; V' inverted). Registers 16-31 use R' (ModRM.reg), X (a register ModRM.rm)
; and V' (vvvv).
.evex:
    call    .rexbits                       ; r15 = W R X B
    mov     al, 0x62
    call    amd64_emit_byte
    movzx   eax, byte [r13 + FM_MAP]
    dec     eax                            ; mm: 1 0F, 2 0F 38, 3 0F 3A
    test    r15d, 4
    jnz     .ev_x
    or      eax, 0x80                      ; R
.ev_x:
    ; X: bit 4 of a register rm, else REX.X (the index)
    movzx   ecx, byte [rel te_rmop]
    cmp     ecx, 0xFF
    je      .ev_x_rex
    lea     rdx, [rel te_cls]
    cmp     byte [rdx + rcx], C_MEM
    je      .ev_x_rex
    lea     rdx, [rel te_num]
    test    byte [rdx + rcx], 16
    jnz     .ev_b
    or      eax, 0x40
    jmp     .ev_b
.ev_x_rex:
    test    r15d, 2
    jnz     .ev_b
    or      eax, 0x40
.ev_b:
    test    r15d, 1
    jnz     .ev_r2
    or      eax, 0x20                      ; B
.ev_r2:
    movzx   ecx, byte [rel te_regop]
    cmp     ecx, 0xFF
    je      .ev_r2_set
    lea     rdx, [rel te_num]
    test    byte [rdx + rcx], 16
    jnz     .ev_p0
.ev_r2_set:
    or      eax, 0x10                      ; R'
.ev_p0:
    call    amd64_emit_byte

    ; P1: W, vvvv, 1, pp
    xor     eax, eax
    movzx   ecx, byte [rel te_vop]
    cmp     ecx, 0xFF
    je      .ev_v
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
.ev_v:
    mov     [rel te_vvvv], al              ; keep bit 4 for V'
    not     eax
    and     eax, 15
    shl     eax, 3
    or      eax, 4
    movzx   ecx, byte [r13 + FM_PFX]
    and     ecx, 3
    or      eax, ecx
    test    r15d, 8
    jz      .ev_p1
    or      eax, 0x80                      ; W
.ev_p1:
    call    amd64_emit_byte

    ; P2: z, L'L, b, V', aaa - and the disp8*N scale
    movzx   r15d, byte [r13 + FM_N8]       ; N for a whole memory operand
    movzx   eax, byte [r13 + FM_VL]
    and     eax, 3
    shl     eax, 5                         ; L'L
    xor     ecx, ecx
.ev_ops:
    lea     rdx, [rel te_cls]
    movzx   r8d, byte [rdx + rcx]
    cmp     r8d, C_RC
    jne     .ev_not_rc
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
    shl     eax, 5                         ; L'L = rounding mode
    or      eax, 0x10                      ; b
    jmp     .ev_next
.ev_not_rc:
    cmp     r8d, C_SAE
    jne     .ev_not_sae
    mov     eax, 0x10                      ; b, L'L = 00
    jmp     .ev_next
.ev_not_sae:
    cmp     r8d, C_MEM
    jne     .ev_next
    push    rax
    call    te_operand
    pop     rax
    test    byte [rdi + OPERAND_ctrl], 2
    jz      .ev_next
    or      eax, 0x10                      ; b: a broadcast
    mov     r15d, 4                        ; N = one element
    test    byte [r13 + FM_FLAGS], TF_W
    jz      .ev_next
    mov     r15d, 8
.ev_next:
    inc     ecx
    cmp     ecx, 4
    jb      .ev_ops
    test    byte [rel te_vvvv], 16
    jnz     .ev_aaa
    or      eax, 0x08                      ; V'
.ev_aaa:
    push    rax
    xor     ecx, ecx
    call    te_operand                     ; the mask belongs to the first operand
    pop     rax
    movzx   ecx, byte [rdi + OPERAND_mask]
    and     ecx, 7
    or      eax, ecx
    test    byte [rdi + OPERAND_ctrl], 1
    jz      .ev_p2
    or      eax, 0x80                      ; z
.ev_p2:
    call    amd64_emit_byte
    mov     [rel amd64_disp8n], r15b
    jmp     .opcode

    ; ---- opcode map and opcode ----
.map:
    movzx   eax, byte [r13 + FM_MAP]
    cmp     eax, 2
    jb      .opcode
    mov     al, 0x0F
    call    amd64_emit_byte
    movzx   eax, byte [r13 + FM_MAP]
    cmp     eax, 3
    jb      .opcode
    mov     cl, 0x38
    je      .map_put
    mov     cl, 0x3A
.map_put:
    mov     al, cl
    call    amd64_emit_byte
.opcode:
    movzx   r15d, byte [r13 + FM_OPCODE]
    cmp     byte [r13 + FM_MODRM], MODRM_NONE
    jne     .op_put
    call    .plus_bits                     ; bswap r, push fs: register in the opcode
    add     r15d, eax
.op_put:
    mov     eax, r15d
    call    amd64_emit_byte

    ; ---- ModRM ----
    movzx   eax, byte [r13 + FM_MODRM]
    cmp     eax, MODRM_NONE
    je      .imms
    cmp     eax, 0xC0
    jae     .fixed_modrm
    cmp     eax, MODRM_R
    jne     .digit
    movzx   ecx, byte [rel te_regop]
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]          ; ModRM.reg = the register
.digit:
    movzx   ecx, byte [rel te_rmop]
    cmp     ecx, 0xFF
    je      .fail
    push    rax
    call    te_operand
    pop     rax
    call    amd64_emit_modrm_sib
    mov     byte [rel amd64_disp8n], 1
    jmp     .imms
.fixed_modrm:
    mov     r15d, eax
    call    .plus_bits                     ; st(i) in the ModRM byte
    add     eax, r15d
    call    amd64_emit_byte

    ; ---- immediates ----
.imms:
    movzx   r15d, word [r13 + FM_ROLES]
    xor     ecx, ecx
.imm_loop:
    mov     eax, r15d
    and     eax, 7
    cmp     eax, RL_IS4
    je      .imm_is4
    cmp     eax, RL_IMM
    jne     .imm_next
    push    rcx
    push    r15
    call    .emit_imm
    pop     r15
    pop     rcx
    jmp     .imm_next
.imm_is4:
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
    shl     eax, 4
    push    rcx
    call    amd64_emit_byte
    pop     rcx
.imm_next:
    shr     r15d, 3
    inc     ecx
    cmp     ecx, 4
    jb      .imm_loop
    test    byte [r13 + FM_FLAGS], TF_FIXIMM
    jz      .ok
    mov     al, [r13 + FM_FIXIMM]
    call    amd64_emit_byte
.ok:
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     rbx
    ret
.fail:
    mov     eax, EXIT_ENCODE_FAIL
    jmp     .ret

; eax = low 3 bits of the R_PLUS operand's register, or 0
.plus_bits:
    xor     eax, eax
    movzx   ecx, byte [rel te_plusop]
    cmp     ecx, 0xFF
    je      .pb_ret
    lea     rdx, [rel te_num]
    movzx   eax, byte [rdx + rcx]
    and     eax, 7
.pb_ret:
    ret

; the immediate operand ecx, as wide as its type says
.emit_imm:
    movzx   eax, byte [r13 + FM_TYPES + rcx]
    lea     rdx, [rel x86_enc_types]
    movzx   eax, byte [rdx + rax*8 + TY_IMM]
    mov     r8d, 1
    cmp     eax, IK_I16
    jne     .ei_z
    mov     r8d, 2
.ei_z:
    cmp     eax, IK_IZ
    jne     .ei_32
    mov     r8d, 4
    cmp     byte [rel te_osz], 16
    jne     .ei_32
    mov     r8d, 2
.ei_32:
    cmp     eax, IK_I32
    jne     .ei_64
    mov     r8d, 4
.ei_64:
    cmp     eax, IK_I64
    jne     .ei_put
    mov     r8d, 8
.ei_put:
    call    te_operand
    mov     r15, [rdi + OPERAND_imm]
.ei_byte:
    mov     eax, r15d
    push    r8
    call    amd64_emit_byte
    pop     r8
    shr     r15, 8
    dec     r8d
    jnz     .ei_byte
    ret
