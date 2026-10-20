;
; ============================================================================
; File        : middle/semantic/proc.s
; Project     : utasm
; Description : Procedures and their checks (amd64).
;
;     proc NAME [uses REG, REG ...]
;         ...
;     endproc
;
;   NAME is a label as any other. Between the two utasm follows the stack
;   and the preserved registers (docs/abi.md: rbx rbp r12-r15) through the
;   code as it is written - no code is added:
;   - proc-stack (an error): the stack not back where it was at a ret, or
;     at a label two paths reach with different depths;
;   - proc-uses (an error): a register named in uses written before it is
;     pushed, not restored by the ret, or never saved at all;
;   - proc-clobber: a preserved register written that uses does not name;
;   - proc-unreachable: code after a ret or a jmp with no label between;
;   - proc-fallthrough: the code runs on into endproc.
;   The depth is the bytes pushed since NAME: push / pop, sub / add rsp,
;   imm, lea rsp, [rsp + imm], enter / leave, mov rbp, rsp ... mov rsp,
;   rbp. Any other write to rsp leaves it unknown (no stack check) until a
;   frame restores it. A jump carries its depth to its label.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

DEFAULT REL

extern  preprocessor_next_token, preprocessor_peek_token
extern  parser_define_label, parser_is_register, str_cmp_kw
extern  amd64_register_table
extern  warn_begin, warn_text, warn_end
extern  masm_enabled, gas_names

%define PL_MAX      256             ; labels a procedure's jumps name
%define PRESERVED   ((1 << 3) | (1 << 5) | (1 << 12) | (1 << 13) | (1 << 14) | (1 << 15))

[SECTION .bss]
global proc_active
proc_active:    resb 1              ; inside proc .. endproc
pr_known:       resb 1              ; the depth is known
pr_reach:       resb 1              ; this point can be reached
pr_unr_warned:  resb 1              ; unreachable code reported since the last label
pr_frame:       resb 1              ; mov rbp, rsp seen: pr_frame_d is its depth
alignb 8
pr_name:        resq 1              ; the procedure's name
pr_depth:       resq 1              ; bytes pushed since the entry
pr_frame_d:     resq 1
pr_uses:        resd 1              ; registers uses names (bit per number)
pr_saved:       resd 1              ; of them: pushed, not yet popped back
pr_ever:        resd 1              ; of them: pushed once at least
pr_warned:      resd 1              ; registers reported already
pr_slot:        resq 32             ; the depth each saved register was pushed at
pr_ln:          resq 1              ; labels recorded
pr_lname:       resq PL_MAX         ; their names
pr_ldepth:      resq PL_MAX         ; the depth there (-1 << 62: unknown)
pr_ldef:        resb PL_MAX         ; 1: the label is defined (else a jump's)
pr_num:         resb 24             ; a number as text

[SECTION .rodata]
s_proc:         db "proc", 0
s_endproc:      db "endproc", 0
s_uses:         db "uses", 0
m_ret_more:     db "stack not balanced at ret: ", 0
m_ret_pushed:   db " bytes still pushed", 0
m_ret_popped:   db " bytes more popped than pushed", 0
m_label_a:      db "stack depth differs where paths meet: ", 0
m_label_b:      db " bytes here, ", 0
m_label_c:      db " by a jump to it", 0
m_unsaved:      db " is written before it is saved (it is in uses)", 0
m_not_rest:     db " is not restored at this ret (it is in uses)", 0
m_never:        db " is in uses but never saved", 0
m_clobber:      db " is written but not in uses (a preserved register)", 0
m_unreach:      db "unreachable code", 0
m_fall:         db "control reaches endproc (no ret or jmp before it)", 0
s_space:        db " ", 0
rn_names:       db "rax",0,"rcx",0,"rdx",0,"rbx",0,"rsp",0,"rbp",0,"rsi",0,"rdi",0
                db "r8",0,0,"r9",0,0,"r10",0,"r11",0,"r12",0,"r13",0,"r14",0,"r15",0

[SECTION .text]

;*
; * [proc_word]
; * Purpose: Is the statement's first word, rdi, "proc" or "endproc" -
; *   utasm's (not under %use masm, whose PROC follows its name, nor GNU's
; *   syntax)? Then its handler runs.
; * Input  : RDI = the word, RBX = PrepState
; * Output : EAX = 0: not one; 1: handled, RDX = OK or an error code
; ;
global proc_word
proc_word:
    cmp     byte [rel masm_enabled], 0
    jne     .no
    cmp     byte [rel gas_names], 0
    jne     .no
    push    rdi
    lea     rsi, [rel s_proc]
    call    str_cmp_kw
    pop     rdi
    test    rax, rax
    jz      .proc
    lea     rsi, [rel s_endproc]
    call    str_cmp_kw
    test    rax, rax
    jz      .endproc
.no:
    xor     eax, eax
    ret
.proc:
    ; "proc NAME": a name after it (a label "proc:" is no statement here)
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .no
    call    proc_begin
    mov     rdx, rax
    mov     eax, 1
    ret
.endproc:
    call    proc_end
    mov     rdx, rax
    mov     eax, 1
    ret

; proc_begin: "proc" read: its NAME (the label) and "uses REG, ..."
proc_begin:
    push    r12
    push    r13
    mov     eax, EXIT_PROC_NESTED
    cmp     byte [rel proc_active], 0
    jne     .ret
    mov     rdi, rbx
    call    preprocessor_next_token        ; NAME
    test    rax, rax
    jnz     .ret
    mov     r12, [rdx + TOKEN_value]
    mov     rsi, r12
    call    parser_define_label
    test    rax, rax
    jnz     .ret
    call    pr_reset
    mov     [rel pr_name], r12
    mov     byte [rel proc_active], 1
    ; uses REG [,] REG ...
    mov     rdi, rbx
    call    preprocessor_peek_token
    cmp     byte [rdx + TOKEN_kind], TOK_IDENT
    jne     .ok
    mov     rdi, [rdx + TOKEN_value]
    lea     rsi, [rel s_uses]
    call    str_cmp_kw
    test    rax, rax
    jnz     .bad
    mov     rdi, rbx
    call    preprocessor_next_token        ; "uses"
.reg:
    mov     rdi, rbx
    call    preprocessor_peek_token
    movzx   eax, byte [rdx + TOKEN_kind]
    cmp     eax, TOK_COMMA
    je      .comma
    cmp     eax, TOK_IDENT
    jne     .ok
    mov     rdi, rbx
    call    preprocessor_next_token
    lea     rdi, [rel amd64_register_table]
    mov     rsi, [rdx + TOKEN_value]
    call    parser_is_register
    cmp     rax, ERR
    je      .bad
    movzx   ecx, al
    cmp     ecx, 32
    jae     .bad                           ; a general register only
    bts     dword [rel pr_uses], ecx
    jmp     .reg
.comma:
    mov     rdi, rbx
    call    preprocessor_next_token
    jmp     .reg
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, EXIT_UNEXPECTED_TOKEN
.ret:
    pop     r13
    pop     r12
    ret

; proc_end: "endproc" read
proc_end:
    cmp     byte [rel proc_active], 0
    jne     .open
    mov     eax, EXIT_PROC_NO_PROC
    ret
.open:
    cmp     byte [rel pr_reach], 0
    je      .never
    mov     edi, WC_PROC_FALLTHROUGH
    lea     rsi, [rel m_fall]
    call    pr_warn
.never:
    ; a register uses names that no push saved
    mov     eax, [rel pr_uses]
    mov     ecx, [rel pr_ever]
    not     ecx
    and     eax, ecx
    xor     ecx, ecx
.never_reg:
    cmp     ecx, 32
    jae     .done
    bt      eax, ecx
    jnc     .never_next
    push    rax
    push    rcx
    mov     edi, WC_PROC_USES
    mov     edx, ecx
    lea     rsi, [rel m_never]
    call    pr_warn_reg
    pop     rcx
    pop     rax
.never_next:
    inc     ecx
    jmp     .never_reg
.done:
    mov     byte [rel proc_active], 0
    xor     eax, eax
    ret

;*
; * [proc_finish]
; * Purpose: The source read: a proc still open is an error.
; * Output : RAX = 0 or EXIT_PROC_OPEN
; ;
global proc_finish
proc_finish:
    xor     eax, eax
    cmp     byte [rel proc_active], 0
    je      .ret
    mov     byte [rel proc_active], 0
    mov     eax, EXIT_PROC_OPEN
.ret:
    ret

; pr_reset: a procedure's state, fresh
pr_reset:
    xor     eax, eax
    mov     [rel pr_depth], rax
    mov     [rel pr_uses], eax
    mov     [rel pr_saved], eax
    mov     [rel pr_ever], eax
    mov     [rel pr_warned], eax
    mov     [rel pr_ln], rax
    mov     byte [rel pr_known], 1
    mov     byte [rel pr_reach], 1
    mov     byte [rel pr_unr_warned], 0
    mov     byte [rel pr_frame], 0
    ret

;*
; * [proc_label]
; * Purpose: A label defined inside a procedure: where paths meet. A jump
; *   to it before gave its depth; the code before it, if it can reach it,
; *   another - they must agree. It can be reached from here on.
; * Input  : RSI = the label's name. Preserves every register.
; ;
global proc_label
proc_label:
    cmp     byte [rel proc_active], 0
    je      .quick
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    call    pr_find                        ; rcx = its slot or -1
    cmp     rcx, -1
    je      .new
    lea     rdx, [rel pr_ldepth]
    mov     rax, [rdx + rcx * 8]
    cmp     byte [rel pr_reach], 0
    je      .adopt
    cmp     byte [rel pr_known], 0
    je      .adopt
    mov     r8, 1 << 62
    neg     r8
    cmp     rax, r8
    je      .mark                          ; (the jump's was unknown)
    cmp     rax, [rel pr_depth]
    je      .mark
    ; two depths here
    push    rcx
    push    rax
    mov     edi, WC_PROC_STACK
    call    warn_begin
    test    eax, eax
    jz      .meet_off
    lea     rsi, [rel m_label_a]
    call    warn_text
    mov     rax, [rel pr_depth]
    call    pr_number
    lea     rsi, [rel m_label_b]
    call    warn_text
    mov     rax, [rsp]
    call    pr_number
    lea     rsi, [rel m_label_c]
    call    warn_text
    call    warn_end
.meet_off:
    pop     rax
    pop     rcx
    mov     byte [rel pr_known], 0         ; (one error, not one per ret after)
    jmp     .mark
.adopt:
    ; reached only by the jumps: their depth
    mov     r8, 1 << 62
    neg     r8
    mov     byte [rel pr_known], 1
    cmp     rax, r8
    jne     .adopt_set
    mov     byte [rel pr_known], 0
.adopt_set:
    mov     [rel pr_depth], rax
.mark:
    lea     rdx, [rel pr_ldef]
    mov     byte [rdx + rcx], 1
    jmp     .reached
.new:
    ; no jump to it yet: reached only from above - or, after a ret / jmp,
    ; from a jump below (unknown till then)
    cmp     byte [rel pr_reach], 0
    jne     .new_put
    mov     byte [rel pr_known], 0
.new_put:
    call    pr_put                         ; (the depth now, defined)
.reached:
    mov     byte [rel pr_reach], 1
    mov     byte [rel pr_unr_warned], 0
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.quick:
    ret

; pr_find: rcx = the slot of the label named rsi, or -1. Preserves rsi.
pr_find:
    xor     ecx, ecx
.f_next:
    cmp     rcx, [rel pr_ln]
    jae     .f_none
    lea     rdx, [rel pr_lname]
    mov     rdi, [rdx + rcx * 8]
    push    rcx
    push    rsi
    call    str_cmp_kw
    pop     rsi
    pop     rcx
    test    rax, rax
    jz      .f_ret
    inc     rcx
    jmp     .f_next
.f_none:
    mov     rcx, -1
.f_ret:
    ret

; pr_put: a label named rsi at the depth now (unknown when not known),
; defined; rcx its slot (-1: no room)
pr_put:
    mov     rcx, [rel pr_ln]
    cmp     rcx, PL_MAX
    jae     .p_full
    lea     rdx, [rel pr_lname]
    mov     [rdx + rcx * 8], rsi
    mov     rax, [rel pr_depth]
    cmp     byte [rel pr_known], 0
    jne     .p_depth
    mov     rax, 1 << 62
    neg     rax
.p_depth:
    lea     rdx, [rel pr_ldepth]
    mov     [rdx + rcx * 8], rax
    lea     rdx, [rel pr_ldef]
    mov     byte [rdx + rcx], 1
    inc     qword [rel pr_ln]
    ret
.p_full:
    mov     rcx, -1
    ret

;*
; * [proc_insn]
; * Purpose: An instruction inside a procedure, before it is encoded: what
; *   it does to the stack and the preserved registers, and whether it can
; *   be reached.
; * Input  : RDI = INST. Preserves every register.
; ;
global proc_insn
proc_insn:
    cmp     byte [rel proc_active], 0
    je      .quick
    push    rax
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    mov     r12, rdi
    ; reached?
    cmp     byte [rel pr_reach], 0
    jne     .reached
    cmp     byte [rel pr_unr_warned], 0
    jne     .reached
    mov     byte [rel pr_unr_warned], 1
    mov     edi, WC_PROC_UNREACHABLE
    lea     rsi, [rel m_unreach]
    call    pr_warn
.reached:
    movzx   eax, word [r12 + INST_op_id]
    cmp     eax, 1583
    je      .push
    cmp     eax, 1534
    je      .pop
    cmp     eax, 1586                      ; pushf
    je      .push8
    cmp     eax, 1588                      ; pushfq
    je      .push8
    cmp     eax, 1538                      ; popf
    je      .pop8
    cmp     eax, 1540                      ; popfq
    je      .pop8
    cmp     eax, 7648                      ; push2
    je      .push2
    cmp     eax, 7650                      ; push2p
    je      .push2
    cmp     eax, 7649                      ; pop2
    je      .pop2
    cmp     eax, 7651                      ; pop2p
    je      .pop2
    cmp     eax, 7652                      ; pushp
    je      .push
    cmp     eax, 7653                      ; popp
    je      .pop
    cmp     eax, 1611                      ; ret
    je      .ret_insn
    cmp     eax, 6534                      ; retn
    je      .ret_insn
    cmp     eax, 7166                      ; retq
    je      .ret_insn
    cmp     eax, 1298                      ; jmp
    je      .jmp
    cmp     eax, 3000
    jb      .not_jcc
    cmp     eax, 3015
    jbe     .jcc
.not_jcc:
    cmp     eax, 1373                      ; loop
    je      .jcc
    cmp     eax, 6524                      ; loope .. jrcxz
    jb      .not_loop
    cmp     eax, 6529
    jbe     .jcc
.not_loop:
    cmp     eax, 6536                      ; jcxz
    je      .jcc
    cmp     eax, 1168                      ; enter
    je      .enter
    cmp     eax, 1357                      ; leave
    je      .leave
    cmp     eax, 1089                      ; cpuid: writes rbx
    je      .cpuid
    cmp     eax, 1676                      ; sub
    je      .sub
    cmp     eax, 1006                      ; add
    je      .add
    cmp     eax, 1356                      ; lea
    je      .lea
    cmp     eax, 1391                      ; mov
    je      .mov
    jmp     .writes

; ---- push / pop ----
.push:
    lea     rsi, [r12 + INST_op0]
    call    .width                         ; ecx = 2 or 8
    add     [rel pr_depth], rcx
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .done
    cmp     ecx, 8
    jne     .done
    movzx   ecx, byte [rsi + OPERAND_reg]
    call    .save
    jmp     .done
.push8:
    add     qword [rel pr_depth], 8
    jmp     .done
.pop8:
    sub     qword [rel pr_depth], 8
    jmp     .done
.pop:
    lea     rsi, [r12 + INST_op0]
    call    .width
    push    rcx
    cmp     byte [rsi + OPERAND_kind], OP_REG
    jne     .pop_go
    movzx   ecx, byte [rsi + OPERAND_reg]
    call    .restore
.pop_go:
    pop     rcx
    sub     [rel pr_depth], rcx
    jmp     .done
.push2:
    lea     rsi, [r12 + INST_op0]
    add     qword [rel pr_depth], 8
    movzx   ecx, byte [rsi + OPERAND_reg]
    call    .save
    add     qword [rel pr_depth], 8
    movzx   ecx, byte [rsi + OPERAND_SIZE + OPERAND_reg]
    call    .save
    jmp     .done
.pop2:
    lea     rsi, [r12 + INST_op0]
    movzx   ecx, byte [rsi + OPERAND_reg]
    call    .restore
    sub     qword [rel pr_depth], 8
    movzx   ecx, byte [rsi + OPERAND_SIZE + OPERAND_reg]
    call    .restore
    sub     qword [rel pr_depth], 8
    jmp     .done

; .width: ecx = the bytes push / pop of operand rsi moves (2 for a word)
.width:
    mov     ecx, 8
    cmp     byte [rsi + OPERAND_size], 16
    jne     .w_ret
    mov     ecx, 2
.w_ret:
    ret

; .save: register ecx pushed at the depth now: a preserved one is saved
; (named in uses or not - push / pop around it keeps it)
.save:
    cmp     ecx, 16
    jae     .s_ret
    mov     eax, PRESERVED
    bt      eax, ecx
    jnc     .s_ret
    bts     dword [rel pr_saved], ecx
    bts     dword [rel pr_ever], ecx
    mov     rax, [rel pr_depth]
    lea     rdx, [rel pr_slot]
    mov     [rdx + rcx * 8], rax
.s_ret:
    ret

; .restore: register ecx popped at the depth now: a saved uses one popped
; from its slot is restored; anything else popped into it a write
.restore:
    cmp     ecx, 32
    jae     .r_ret
    cmp     ecx, 4
    je      .r_rsp
    bt      dword [rel pr_saved], ecx
    jnc     .r_write
    mov     rax, [rel pr_depth]
    lea     rdx, [rel pr_slot]
    cmp     [rdx + rcx * 8], rax
    jne     .r_write
    btr     dword [rel pr_saved], ecx
.r_ret:
    ret
.r_write:
    jmp     pr_write
.r_rsp:
    mov     byte [rel pr_known], 0
    ret

; ---- ret: back at the entry depth, every uses register restored ----
.ret_insn:
    cmp     byte [rel pr_known], 0
    je      .ret_out
    mov     rax, [rel pr_depth]
    test    rax, rax
    jz      .ret_regs
    mov     edi, WC_PROC_STACK
    call    warn_begin
    test    eax, eax
    jz      .ret_regs
    lea     rsi, [rel m_ret_more]
    call    warn_text
    mov     rax, [rel pr_depth]
    lea     rsi, [rel m_ret_pushed]
    test    rax, rax
    jns     .ret_n
    neg     rax
    lea     rsi, [rel m_ret_popped]
.ret_n:
    push    rsi
    call    pr_number
    pop     rsi
    call    warn_text
    call    warn_end
.ret_regs:
    mov     eax, [rel pr_saved]
    and     eax, [rel pr_uses]
    xor     ecx, ecx
.ret_reg:
    cmp     ecx, 32
    jae     .ret_out
    bt      eax, ecx
    jnc     .ret_reg_next
    push    rax
    push    rcx
    mov     edi, WC_PROC_USES
    mov     edx, ecx
    lea     rsi, [rel m_not_rest]
    call    pr_warn_reg
    pop     rcx
    pop     rax
.ret_reg_next:
    inc     ecx
    jmp     .ret_reg
.ret_out:
    mov     byte [rel pr_reach], 0
    jmp     .done

; ---- jumps: their target takes the depth ----
.jmp:
    call    .target
    mov     byte [rel pr_reach], 0
    jmp     .done
.jcc:
    call    .target
    jmp     .done
.target:
    lea     rsi, [r12 + INST_op0]
    movzx   eax, byte [rsi + OPERAND_kind]
    cmp     eax, OP_REG
    je      .t_ret
    cmp     eax, OP_MEM
    je      .t_ret
    mov     rsi, [rsi + OPERAND_sym]
    test    rsi, rsi
    jz      .t_ret
    cmp     byte [rsi], TAG_SYMBOL
    jne     .t_name
    mov     rsi, [rsi + SYMBOL_name]
.t_name:
    jmp     pr_jump
.t_ret:
    ret

; ---- enter imm16, imm8: push rbp, mov rbp, rsp, sub rsp, imm16 ----
.enter:
    add     qword [rel pr_depth], 8
    mov     ecx, 5
    call    .save
    mov     rax, [rel pr_depth]
    mov     [rel pr_frame_d], rax
    mov     byte [rel pr_frame], 1
    mov     rax, [r12 + INST_op0 + OPERAND_imm]
    and     eax, 0xFFFF
    add     [rel pr_depth], rax
    jmp     .done
; ---- leave: mov rsp, rbp, pop rbp ----
.leave:
    cmp     byte [rel pr_frame], 0
    je      .unknown
    mov     rax, [rel pr_frame_d]
    mov     [rel pr_depth], rax
    mov     ecx, 5
    call    .restore
    sub     qword [rel pr_depth], 8
    jmp     .done
.cpuid:
    mov     ecx, 3
    call    pr_write
    jmp     .done

; ---- sub / add rsp, imm; lea rsp, [rsp + imm] ----
.sub:
    call    .rsp_imm
    jnz     .writes
    add     [rel pr_depth], rax
    jmp     .done
.add:
    call    .rsp_imm
    jnz     .writes
    sub     [rel pr_depth], rax
    jmp     .done
; .rsp_imm: "op rsp, imm": ZF = 1, rax = the immediate
.rsp_imm:
    cmp     byte [r12 + INST_nops], 2
    jne     .ri_no
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .ri_no
    cmp     byte [r12 + INST_op0 + OPERAND_reg], 4
    jne     .ri_no
    cmp     byte [r12 + INST_op0 + OPERAND_size], 64
    jne     .ri_no
    cmp     byte [r12 + INST_op1 + OPERAND_kind], OP_IMM
    jne     .ri_no
    mov     rax, [r12 + INST_op1 + OPERAND_imm]
    cmp     eax, eax
    ret
.ri_no:
    test    esp, esp
    ret
.lea:
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .writes
    cmp     byte [r12 + INST_op0 + OPERAND_reg], 4
    jne     .writes
    cmp     byte [r12 + INST_op1 + OPERAND_index], 0xFF
    jne     .unknown
    cmp     byte [r12 + INST_op1 + OPERAND_base], 5
    je      .lea_rbp
    cmp     byte [r12 + INST_op1 + OPERAND_base], 4
    jne     .unknown
    mov     rax, [r12 + INST_op1 + OPERAND_imm]
    sub     [rel pr_depth], rax
    jmp     .done
.lea_rbp:
    ; lea rsp, [rbp - n] in a frame: n bytes below where rbp was set
    cmp     byte [rel pr_frame], 0
    je      .unknown
    mov     rax, [rel pr_frame_d]
    sub     rax, [r12 + INST_op1 + OPERAND_imm]
    mov     [rel pr_depth], rax
    mov     byte [rel pr_known], 1
    jmp     .done

; ---- mov rbp, rsp (a frame) / mov rsp, rbp (back to it) ----
.mov:
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .writes
    cmp     byte [r12 + INST_op1 + OPERAND_kind], OP_REG
    jne     .writes
    cmp     byte [r12 + INST_op0 + OPERAND_size], 64
    jne     .writes
    movzx   eax, byte [r12 + INST_op0 + OPERAND_reg]
    movzx   ecx, byte [r12 + INST_op1 + OPERAND_reg]
    cmp     eax, 5
    jne     .mov_rsp
    cmp     ecx, 4
    jne     .writes
    mov     rax, [rel pr_depth]
    mov     [rel pr_frame_d], rax
    mov     al, [rel pr_known]
    mov     [rel pr_frame], al
    jmp     .writes                        ; (rbp is written)
.mov_rsp:
    cmp     eax, 4
    jne     .writes
    cmp     ecx, 5
    jne     .unknown
    cmp     byte [rel pr_frame], 0
    je      .unknown
    mov     rax, [rel pr_frame_d]
    mov     [rel pr_depth], rax
    mov     byte [rel pr_known], 1
    jmp     .done

.unknown:
    mov     byte [rel pr_known], 0
    jmp     .done

; ---- what else it writes: its first operand, a register (both for xchg
; and xadd) - not cmp, test, bt, call, ccmp, ctest ----
.writes:
    movzx   eax, word [r12 + INST_op_id]
    cmp     byte [r12 + INST_nops], 0
    je      .done
    cmp     eax, 1075                      ; cmp
    je      .done
    cmp     eax, 1691                      ; test
    je      .done
    cmp     eax, 1054                      ; bt
    je      .done
    cmp     eax, 1059                      ; call
    je      .done
    cmp     eax, 7600                      ; ccmp, ctest
    jb      .w_op0
    cmp     eax, 7631
    jbe     .done
.w_op0:
    cmp     byte [r12 + INST_op0 + OPERAND_kind], OP_REG
    jne     .w_op1
    movzx   ecx, byte [r12 + INST_op0 + OPERAND_reg]
    cmp     ecx, 4
    jne     .w_op0_reg
    mov     byte [rel pr_known], 0         ; rsp, some other way
    jmp     .w_op1
.w_op0_reg:
    call    pr_write
.w_op1:
    movzx   eax, word [r12 + INST_op_id]   ; (pr_write takes eax)
    cmp     eax, 2152                      ; xchg
    je      .w_both
    cmp     eax, 2150                      ; xadd
    jne     .done
.w_both:
    cmp     byte [r12 + INST_op1 + OPERAND_kind], OP_REG
    jne     .done
    movzx   ecx, byte [r12 + INST_op1 + OPERAND_reg]
    call    pr_write
.done:
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
.quick:
    ret

; pr_write: register ecx written - a preserved one: in uses, it must be
; saved by now (proc-uses); else proc-clobber. Each once a procedure.
pr_write:
    cmp     ecx, 16
    jae     .pw_ret                        ; (r16-r31: the caller's, APX)
    mov     eax, PRESERVED
    bt      eax, ecx
    jnc     .pw_ret
    bt      dword [rel pr_warned], ecx
    jc      .pw_ret
    bt      dword [rel pr_saved], ecx
    jc      .pw_ret                        ; (pushed: its value is kept)
    bt      dword [rel pr_uses], ecx
    jnc     .pw_clobber
    bts     dword [rel pr_warned], ecx
    mov     edi, WC_PROC_USES
    mov     edx, ecx
    lea     rsi, [rel m_unsaved]
    jmp     pr_warn_reg
.pw_clobber:
    bts     dword [rel pr_warned], ecx
    mov     edi, WC_PROC_CLOBBER
    mov     edx, ecx
    lea     rsi, [rel m_clobber]
    jmp     pr_warn_reg
.pw_ret:
    ret

; pr_jump: a jump to the label named rsi at the depth now. Defined
; already (a backward jump): the depths must agree; else its depth kept
; for the label (the first jump's).
pr_jump:
    call    pr_find
    cmp     rcx, -1
    je      .pj_new
    lea     rdx, [rel pr_ldef]
    cmp     byte [rdx + rcx], 0
    je      .pj_ret                        ; (a jump's already)
    cmp     byte [rel pr_known], 0
    je      .pj_ret
    lea     rdx, [rel pr_ldepth]
    mov     rax, [rdx + rcx * 8]
    mov     r8, 1 << 62
    neg     r8
    cmp     rax, r8
    je      .pj_ret
    cmp     rax, [rel pr_depth]
    je      .pj_ret
    push    rax
    mov     edi, WC_PROC_STACK
    call    warn_begin
    test    eax, eax
    jz      .pj_off
    lea     rsi, [rel m_label_a]
    call    warn_text
    mov     rax, [rsp]
    call    pr_number
    lea     rsi, [rel m_label_b]
    call    warn_text
    mov     rax, [rel pr_depth]
    call    pr_number
    lea     rsi, [rel m_label_c]
    call    warn_text
    call    warn_end
.pj_off:
    pop     rax
    mov     byte [rel pr_known], 0
.pj_ret:
    ret
.pj_new:
    call    pr_put
    cmp     rcx, -1
    je      .pj_ret
    lea     rdx, [rel pr_ldef]
    mov     byte [rdx + rcx], 0            ; (a jump's, not defined)
    ret

; pr_warn: warning class edi, the text rsi
pr_warn:
    push    rsi
    call    warn_begin
    pop     rsi
    test    eax, eax
    jz      .pw_off
    call    warn_text
    call    warn_end
.pw_off:
    ret

; pr_warn_reg: warning class edi: register edx's name, then the text rsi
pr_warn_reg:
    push    rsi
    push    rdx
    call    warn_begin
    pop     rdx
    pop     rsi
    test    eax, eax
    jz      .pwr_off
    push    rsi
    lea     rsi, [rel rn_names]
    lea     rsi, [rsi + rdx * 4]
    call    warn_text
    pop     rsi
    call    warn_text
    call    warn_end
.pwr_off:
    ret

; pr_number: rax (unsigned) as decimal text, into the warning
pr_number:
    lea     rdi, [rel pr_num + 23]
    mov     byte [rdi], 0
    mov     ecx, 10
.pn_digit:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    rax, rax
    jnz     .pn_digit
    mov     rsi, rdi
    jmp     warn_text
