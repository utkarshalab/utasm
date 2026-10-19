;
; ============================================================================
; File        : debug/cfi.s
; Project     : utasm
; Description : Call frame information: GAS's .cfi_* directives, written as
;               the .eh_frame section an ELF object carries, so debuggers,
;               profilers and backtraces unwind through the code (NASM has
;               no CFI).
;
;   Each directive is recorded where it stands (its section and offset,
;   moved with the code when jumps are shortened: cfi_remap); the CFA
;   offset is followed as the source goes (.cfi_adjust_cfa_offset and
;   .cfi_rel_offset count from it, .cfi_remember_state / restore_state
;   keep it). Once the code is laid out, cfi_build writes .eh_frame as GAS
;   does:
;
;   - a CIE: version 1, augmentation "zR" ("zRS" for a signal frame), code
;     alignment 1, data alignment -8 (-4 in -f elf32), the return address
;     column 16 (8), FDE addresses PC-relative 4 bytes (0x1b), then the
;     state at a call: CFA = rsp + 8, the return address at CFA - 8 (none
;     for ".cfi_startproc simple"); written before the first FDE that
;     uses it
;   - an FDE per .cfi_startproc ... .cfi_endproc: the CIE's distance, the
;     start (an R_X86_64_PC32 / R_386_PC32 relocation against its section
;     and offset), the length, then the rules as the code reaches them
;     (DW_CFA_advance_loc, advance_loc1/2/4 by the distance)
;   - each padded with DW_CFA_nop to the address size
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"

extern  asm_ctx_create_section
extern  asm_ctx_emit_byte
extern  reloc_record
extern  relax_map_offset
extern  io_mmap
extern  global_ctx
extern  elf32_enabled
extern  coff_enabled

; a record
%define CR_KIND     0               ; b CFI_*
%define CR_FLAGS    1               ; b START: CFIF_SIGNAL | CFIF_SIMPLE
%define CR_REG1     2               ; w
%define CR_REG2     4               ; w
%define CR_VALUE    8               ; q
%define CR_SEC      16              ; q SECTION*
%define CR_OFF      24              ; q offset in it
%define CR_SIZE     32
%define CFI_MAX     (1 << 20)       ; records (committed as used)
%define CFI_STACK   32              ; .cfi_remember_state depth

%define CFIF_SIGNAL 1
%define CFIF_SIMPLE 2
%define CFIF_IN_CIE 0x80            ; a rule its FDE's CIE holds
%define CFI_CIES    64              ; CIEs written at most
%define CC_OFF      0               ; q a CIE's offset in .eh_frame
%define CC_FLAGS    8               ; b CFIF_SIGNAL
%define CC_LEN      9               ; b its initial rules' length (0xFF: unique)
%define CC_RULES    16              ; its initial rules
%define CC_MAX      64
%define CC_SIZE     80

[SECTION .bss]
alignb 8
cfi_recs:       resq 1              ; the records
cfi_count:      resq 1
cfi_start:      resq 1              ; the open .cfi_startproc's record
cfi_cfa:        resq 1              ; the CFA offset as the source stands
cfi_depth:      resq 1
cfi_stack:      resq CFI_STACK
cfi_cies:       resb CFI_CIES * CC_SIZE ; the CIEs written
cfi_ncies:      resq 1
cfi_lead_skip:  resq 1              ; leading rule bytes the FDE's CIE has
cfi_last:       resq 1              ; the last START record (its FDE ends
                                    ; the section: padded to 8)
cfi_cur:        resq 1              ; the START record of the FDE open
cfi_lead:       resb 256            ; an FDE's leading rules, encoded
cfi_lead_len:   resq 1              ; their length, 0xFF when no CIE can
cfi_lead_n:     resq 1              ; hold them (over CC_MAX); the length
cfi_ctx:        resq 1
cfi_sec:        resq 1              ; .eh_frame
cfi_fde:        resq 1              ; the FDE being written: its offset
cfi_fde_start:  resq 1              ; ... and its code's start
cfi_fde_sec:    resq 1              ; ... and section
cfi_loc:        resq 1              ; where its rules have reached
cfi_open:       resb 1              ; inside .cfi_startproc ... endproc

[SECTION .text]

;*
; * [cfi_directive]
; * Purpose: Record a CFI directive at the current position.
; * Input  : EDI = CFI_*, ESI = register, EDX = second register, RCX =
; *          value (an offset; START: CFIF_SIMPLE when "simple")
; * Output : RAX = OK or the error (GAS's messages)
; ;
global cfi_directive
cfi_directive:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14, rcx
    ; the state the source has made
    cmp     ebx, CFI_START
    jne     .in_proc
    mov     eax, EXIT_CFI_OPEN
    cmp     byte [rel cfi_open], 0
    jne     .ret
    mov     byte [rel cfi_open], 1
    mov     qword [rel cfi_depth], 0
    mov     eax, 8                         ; the CFA after a call
    cmp     byte [rel elf32_enabled], 0
    je      .cfa_start
    mov     eax, 4
.cfa_start:
    mov     [rel cfi_cfa], rax
    jmp     .record
.in_proc:
    mov     eax, EXIT_CFI_NO_PROC
    cmp     ebx, CFI_END
    jne     .no_proc
    mov     eax, EXIT_CFI_ENDPROC
.no_proc:
    cmp     byte [rel cfi_open], 0
    je      .ret
    cmp     ebx, CFI_END
    jne     .not_end
    mov     byte [rel cfi_open], 0
    jmp     .record
.not_end:
    cmp     ebx, CFI_DEF_CFA
    je      .set_cfa
    cmp     ebx, CFI_DEF_CFA_OFF
    jne     .not_cfa_off
.set_cfa:
    mov     [rel cfi_cfa], r14
    jmp     .record
.not_cfa_off:
    cmp     ebx, CFI_ADJUST
    jne     .not_adjust
    add     r14, [rel cfi_cfa]             ; the new offset, as such
    mov     [rel cfi_cfa], r14
    mov     ebx, CFI_DEF_CFA_OFF
    jmp     .record
.not_adjust:
    cmp     ebx, CFI_REL_OFFSET
    jne     .not_rel
    sub     r14, [rel cfi_cfa]             ; from the CFA
    mov     ebx, CFI_OFFSET
    jmp     .record
.not_rel:
    cmp     ebx, CFI_REMEMBER
    jne     .not_remember
    mov     rax, [rel cfi_depth]
    cmp     rax, CFI_STACK
    jae     .record                        ; (deeper: not followed)
    lea     rcx, [rel cfi_stack]
    mov     rdx, [rel cfi_cfa]
    mov     [rcx + rax*8], rdx
    inc     qword [rel cfi_depth]
    jmp     .record
.not_remember:
    cmp     ebx, CFI_RESTORE_STATE
    jne     .not_restore_state
    mov     eax, EXIT_CFI_STATE
    mov     rcx, [rel cfi_depth]
    test    rcx, rcx
    jz      .ret
    dec     rcx
    mov     [rel cfi_depth], rcx
    lea     rdx, [rel cfi_stack]
    mov     rdx, [rdx + rcx*8]
    mov     [rel cfi_cfa], rdx
    jmp     .record
.not_restore_state:
    cmp     ebx, CFI_SIGNAL
    jne     .record
    ; a signal frame: its own CIE ("zRS")
    mov     rax, [rel cfi_start]
    or      byte [rax + CR_FLAGS], CFIF_SIGNAL
    xor     eax, eax
    jmp     .ret

.record:
    mov     rax, [rel cfi_recs]
    test    rax, rax
    jnz     .room
    xor     edi, edi
    mov     rsi, CFI_MAX * CR_SIZE
    mov     edx, PROT_READ | PROT_WRITE
    mov     ecx, MAP_PRIVATE | MAP_ANONYMOUS | 0x4000   ; MAP_NORESERVE
    mov     r8, -1
    xor     r9d, r9d
    call    io_mmap
    test    rax, rax
    jnz     .ret
    mov     [rel cfi_recs], rdx
    mov     rax, rdx
.room:
    mov     rcx, [rel cfi_count]
    mov     edx, EXIT_SYMBOL_RANGE
    cmp     rcx, CFI_MAX
    jae     .ret_edx
    imul    rcx, rcx, CR_SIZE
    add     rax, rcx
    inc     qword [rel cfi_count]
    mov     [rax + CR_KIND], bl
    mov     byte [rax + CR_FLAGS], 0
    mov     [rax + CR_REG1], r12w
    mov     [rax + CR_REG2], r13w
    mov     [rax + CR_VALUE], r14
    lea     rcx, [rel global_ctx]
    mov     rdx, [rcx + ASMCTX_curr_sec]
    mov     [rax + CR_SEC], rdx
    xor     ecx, ecx
    test    rdx, rdx
    jz      .at
    mov     rcx, [rdx + SECTION_size]
.at:
    mov     [rax + CR_OFF], rcx
    cmp     ebx, CFI_START
    jne     .recorded
    mov     [rel cfi_start], rax
    test    r14, r14
    jz      .recorded
    mov     byte [rax + CR_FLAGS], CFIF_SIMPLE
.recorded:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.ret_edx:
    mov     eax, edx
    jmp     .ret

;*
; * [cfi_remap]
; * Purpose: Section RDI is being rewritten (jumps shortened): its
; *          records' offsets move with the code (relax_map_offset). An
; *          FDE's end is before padding that grew from none there - the
; *          next function's alignment (GCC writes .cfi_endproc after its
; *          last instruction); a rule is after it, as .cfi_startproc is
; *          (GCC's ".p2align 4 / .L5: / .cfi_restore_state").
; ;
global cfi_remap
cfi_remap:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     rbx, [rel cfi_recs]
    mov     r13, [rel cfi_count]
.rec:
    test    r13, r13
    jz      .done
    cmp     [rbx + CR_SEC], r12
    jne     .next
    mov     rdi, [rbx + CR_OFF]
    cmp     byte [rbx + CR_KIND], CFI_END
    jne     .after
    extern  relax_map_offset_before
    call    relax_map_offset_before
    jmp     .mapped
.after:
    call    relax_map_offset
.mapped:
    mov     [rbx + CR_OFF], rax
.next:
    add     rbx, CR_SIZE
    dec     r13
    jmp     .rec
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

;*
; * [cfi_build]
; * Purpose: The .eh_frame section, once the code is laid out: an ELF
; *          object's (not -f bin, -f win64, a standalone executable).
; * Input  : RDI = AsmCtx
; * Output : RAX = OK or an error
; ;
global cfi_build
cfi_build:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     [rel cfi_ctx], rdi
    mov     r15, rdi
    xor     eax, eax
    cmp     qword [rel cfi_count], 0
    je      .ret
    mov     eax, EXIT_CFI_EOF
    cmp     byte [rel cfi_open], 0
    jne     .ret
    xor     eax, eax
    cmp     byte [r15 + ASMCTX_fmt], FMT_ELF64
    jne     .ret
    cmp     byte [r15 + ASMCTX_standalone], 0
    jne     .ret
    cmp     byte [rel coff_enabled], 0
    jne     .ret

    lea     rsi, [rel cfi_name]
    mov     rdi, r15
    mov     edx, SEC_CUSTOM
    call    asm_ctx_create_section
    test    rax, rax
    jnz     .ret
    mov     [rel cfi_sec], rdx
    mov     dword [rdx + SECTION_elf_type], SHT_PROGBITS
    mov     word [rdx + SECTION_flags], SHF_ALLOC
    call    cfi_asize
    mov     [rdx + SECTION_align], rax
    push    qword [r15 + ASMCTX_curr_sec]
    mov     [r15 + ASMCTX_curr_sec], rdx
    mov     qword [rel cfi_ncies], 0
    ; the last FDE: padded to the section's alignment, the others to 4
    mov     rbx, [rel cfi_recs]
    mov     r13, [rel cfi_count]
.last:
    cmp     byte [rbx + CR_KIND], CFI_START
    jne     .last_next
    mov     [rel cfi_last], rbx
.last_next:
    add     rbx, CR_SIZE
    dec     r13
    jnz     .last

    mov     rbx, [rel cfi_recs]
    mov     r13, [rel cfi_count]
.rec:
    test    r13, r13
    jz      .built
    movzx   eax, byte [rbx + CR_KIND]
    cmp     eax, CFI_START
    jne     .not_start
    call    cfi_fde_open
    jmp     .next
.not_start:
    cmp     eax, CFI_END
    jne     .rule
    call    cfi_fde_close
    jmp     .next
.rule:
    xor     eax, eax
    test    byte [rbx + CR_FLAGS], CFIF_IN_CIE
    jnz     .next                          ; its CIE has it
    call    cfi_advance                    ; to where the rule starts
    call    cfi_rule
.next:
    test    rax, rax
    jnz     .failed
    add     rbx, CR_SIZE
    dec     r13
    jmp     .rec
.built:
    xor     eax, eax
.failed:
    pop     qword [r15 + ASMCTX_curr_sec]
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- cfi_asize: rax = the address size (8, 4 in -f elf32); keeps rdx ----
cfi_asize:
    mov     eax, 8
    cmp     byte [rel elf32_enabled], 0
    je      .ret
    mov     eax, 4
.ret:
    ret

; ---- writing into .eh_frame ----
; cfi_u8: sil; cfi_u32: esi; cfi_uleb / cfi_sleb: rsi. Keep rbx, r12-r15.
cfi_u8:
    mov     rdi, [rel cfi_ctx]
    movzx   esi, sil
    jmp     asm_ctx_emit_byte
cfi_u32:
    push    r12
    push    r13
    mov     r12d, esi
    mov     r13d, 4
.byte:
    mov     esi, r12d
    call    cfi_u8
    shr     r12d, 8
    dec     r13d
    jnz     .byte
    pop     r13
    pop     r12
    xor     eax, eax
    ret
cfi_uleb:
    push    r12
    mov     r12, rsi
.more:
    mov     rsi, r12
    and     esi, 0x7F
    shr     r12, 7
    test    r12, r12
    jz      .last
    or      esi, 0x80
    call    cfi_u8
    jmp     .more
.last:
    call    cfi_u8
    pop     r12
    xor     eax, eax
    ret
cfi_sleb:
    push    r12
    mov     r12, rsi
.more:
    mov     rsi, r12
    and     esi, 0x7F
    sar     r12, 7
    ; done when the rest is the sign of what is written
    test    r12, r12
    jnz     .neg
    test    esi, 0x40
    jz      .last
    jmp     .cont
.neg:
    cmp     r12, -1
    jne     .cont
    test    esi, 0x40
    jnz     .last
.cont:
    or      esi, 0x80
    call    cfi_u8
    jmp     .more
.last:
    call    cfi_u8
    pop     r12
    xor     eax, eax
    ret

; cfi_size: rax = .eh_frame's size so far
cfi_size:
    mov     rax, [rel cfi_sec]
    mov     rax, [rax + SECTION_size]
    ret

; cfi_put32: dword esi at offset rdi of .eh_frame
cfi_put32:
    mov     rax, [rel cfi_sec]
    mov     rax, [rax + SECTION_data]
    mov     [rax + rdi], esi
    ret

; cfi_pad: DW_CFA_nop up to a multiple of rsi bytes in the section, then
; the entry's length (less its length field) at rdi, its start. GAS pads
; CIEs and FDEs to 4, the last FDE to the address size - of the section's
; offset, not the entry's (an FDE at 0x6c ends at 0x90, not 0x94).
cfi_pad:
    push    r12
    push    r13
    mov     r12, rdi
    lea     r13, [rsi - 1]
.pad:
    call    cfi_size
    test    rax, r13
    jz      .padded
    xor     esi, esi                       ; DW_CFA_nop
    call    cfi_u8
    jmp     .pad
.padded:
    call    cfi_size
    sub     rax, r12
    lea     esi, [rax - 4]
    mov     rdi, r12
    call    cfi_put32
    pop     r13
    pop     r12
    xor     eax, eax
    ret

; ---- cfi_leading: the FDE of START record rbx: its leading rules - at a
;      call (CFA = sp + address size, the return address below it) unless
;      "simple", and the rules at its start before an advance, a remember or
;      an escape - into cfi_lead, those records marked CFIF_IN_CIE: GAS puts
;      them in the CIE, which FDEs with the same ones share ----
cfi_leading:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    call    cfi_size
    mov     r15, rax                       ; written at the end, then taken out
    test    byte [rbx + CR_FLAGS], CFIF_SIMPLE
    jnz     .rules
    mov     esi, 0x0C                      ; DW_CFA_def_cfa
    call    cfi_u8
    mov     esi, 7                         ; rsp
    cmp     byte [rel elf32_enabled], 0
    je      .sp
    mov     esi, 4                         ; esp
.sp:
    call    cfi_uleb
    call    cfi_asize
    mov     rsi, rax
    call    cfi_uleb
    call    cfi_ra
    lea     esi, [rax + 0x80]              ; DW_CFA_offset ra, 1
    call    cfi_u8
    mov     esi, 1
    call    cfi_uleb
.rules:
    mov     r12, [rbx + CR_SEC]
    mov     r13, [rbx + CR_OFF]
    mov     r14, [rel cfi_recs]
    mov     rax, [rel cfi_count]
    imul    rax, rax, CR_SIZE
    add     r14, rax                       ; the records' end
.rule:
    add     rbx, CR_SIZE
    cmp     rbx, r14
    jae     .taken
    movzx   eax, byte [rbx + CR_KIND]
    cmp     eax, CFI_START
    je      .taken
    cmp     eax, CFI_END
    je      .taken
    cmp     eax, CFI_REMEMBER
    je      .taken
    cmp     eax, CFI_ESCAPE
    je      .taken
    cmp     [rbx + CR_SEC], r12
    jne     .taken
    cmp     [rbx + CR_OFF], r13
    jne     .taken                         ; (an advance first)
    push    r12
    push    r14
    call    cfi_rule
    pop     r14
    pop     r12
    or      byte [rbx + CR_FLAGS], CFIF_IN_CIE
    jmp     .rule
.taken:
    ; out of the section into cfi_lead (too many: no CIE shares them, the
    ; FDE has them)
    call    cfi_size
    sub     rax, r15
    cmp     rax, 256
    jbe     .count
    mov     eax, 256
.count:
    mov     [rel cfi_lead_n], rax
    mov     [rel cfi_lead_len], rax
    mov     rcx, rax
    cmp     rax, CC_MAX
    jbe     .copy
    mov     qword [rel cfi_lead_len], 0xFF
.copy:
    mov     rsi, [rel cfi_sec]
    mov     rsi, [rsi + SECTION_data]
    add     rsi, r15
    lea     rdi, [rel cfi_lead]
    rep     movsb
    mov     rax, [rel cfi_sec]
    mov     [rax + SECTION_size], r15
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- cfi_cie_for: rbx = a START record whose leading rules cfi_lead
;      has: the CIE for them and its signal flag - as GNU as, the first
;      one written whose rules begin the FDE's (the plain CIE begins any:
;      the FDE keeps the rest, cfi_lead_skip bytes on), else a new one
;      with them all: rax = its offset ----
cfi_cie_for:
    push    r12
    push    r13
    push    r14
    movzx   r12d, byte [rbx + CR_FLAGS]
    and     r12d, CFIF_SIGNAL
    mov     qword [rel cfi_lead_skip], 0
    lea     r13, [rel cfi_cies]
    mov     r14, [rel cfi_ncies]
.find:
    test    r14, r14
    jz      .write
    cmp     [r13 + CC_FLAGS], r12b
    jne     .find_next
    movzx   ecx, byte [r13 + CC_LEN]
    cmp     qword [rel cfi_lead_len], 0xFF
    jne     .find_prefix
    test    ecx, ecx                       ; (too many to compare: the
    jnz     .find_next                     ; plain CIE only)
    jmp     .found
.find_prefix:
    cmp     rcx, [rel cfi_lead_len]
    ja      .find_next
    mov     [rel cfi_lead_skip], rcx
    test    ecx, ecx
    jz      .found                         ; (no rules: begins any; repe
                                           ; cmpsb of none sets no flags)
    lea     rsi, [r13 + CC_RULES]
    lea     rdi, [rel cfi_lead]
    repe    cmpsb
    jne     .find_next
.found:
    mov     rax, [r13 + CC_OFF]
    jmp     .ret
.find_next:
    add     r13, CC_SIZE
    dec     r14
    jmp     .find
.write:
    ; (a new CIE takes the leading rules: none left for the FDE)
    mov     rax, [rel cfi_lead_len]
    cmp     rax, 0xFF
    jne     .write_skip
    xor     eax, eax                       ; (too many: all in the FDE)
.write_skip:
    mov     [rel cfi_lead_skip], rax
    call    cfi_size
    mov     r13, rax                       ; its offset
    xor     esi, esi
    call    cfi_u32                        ; the length, later
    xor     esi, esi
    call    cfi_u32                        ; CIE id 0
    mov     esi, 1
    call    cfi_u8                         ; version
    mov     esi, 'z'
    call    cfi_u8
    mov     esi, 'R'
    call    cfi_u8
    test    r12d, CFIF_SIGNAL
    jz      .augmented
    mov     esi, 'S'
    call    cfi_u8
.augmented:
    xor     esi, esi
    call    cfi_u8
    mov     esi, 1
    call    cfi_uleb                       ; code alignment
    call    cfi_asize
    mov     rsi, rax
    neg     rsi
    call    cfi_sleb                       ; data alignment
    call    cfi_ra
    mov     rsi, rax
    call    cfi_uleb                       ; the return address column
    mov     esi, 1
    call    cfi_uleb                       ; augmentation data: 1 byte
    mov     esi, 0x1B                      ; DW_EH_PE_pcrel | sdata4
    call    cfi_u8
    ; the initial rules: the FDE's leading ones
    mov     r14, [rel cfi_lead_len]
    cmp     r14, 0xFF
    je      .rules_done                    ; (left in place: too many)
    xor     ecx, ecx
.rule_byte:
    cmp     rcx, r14
    jae     .rules_done
    push    rcx
    lea     rax, [rel cfi_lead]
    movzx   esi, byte [rax + rcx]
    call    cfi_u8
    pop     rcx
    inc     rcx
    jmp     .rule_byte
.rules_done:
    mov     rdi, r13
    mov     esi, 4
    call    cfi_pad
    ; remembered, for the FDEs after it
    mov     rax, [rel cfi_ncies]
    cmp     rax, CFI_CIES
    jae     .written
    imul    rcx, rax, CC_SIZE
    lea     rdi, [rel cfi_cies]
    add     rdi, rcx
    mov     [rdi + CC_OFF], r13
    mov     [rdi + CC_FLAGS], r12b
    mov     rcx, [rel cfi_lead_len]
    mov     [rdi + CC_LEN], cl
    cmp     rcx, CC_MAX
    jbe     .keep_rules
    xor     ecx, ecx
.keep_rules:
    lea     rdi, [rdi + CC_RULES]
    lea     rsi, [rel cfi_lead]
    rep     movsb
    inc     qword [rel cfi_ncies]
.written:
    mov     rax, r13
.ret:
    pop     r14
    pop     r13
    pop     r12
    ret

; cfi_ra: rax = the return address column (16 rip, 8 eip)
cfi_ra:
    mov     eax, 16
    cmp     byte [rel elf32_enabled], 0
    je      .ret
    mov     eax, 8
.ret:
    ret

; ---- cfi_fde_open: rbx = a START record ----
cfi_fde_open:
    mov     [rel cfi_cur], rbx
    call    cfi_leading
    call    cfi_cie_for
    push    rax                            ; the CIE's offset
    call    cfi_size
    mov     [rel cfi_fde], rax
    xor     esi, esi
    call    cfi_u32                        ; the length, later
    call    cfi_size
    pop     rcx
    sub     rax, rcx
    mov     esi, eax
    call    cfi_u32                        ; the CIE's distance
    ; the start: PC-relative to the code's section and offset
    mov     rax, [rbx + CR_SEC]
    mov     [rel cfi_fde_sec], rax
    mov     rax, [rbx + CR_OFF]
    mov     [rel cfi_fde_start], rax
    mov     [rel cfi_loc], rax
    mov     rdi, [rel cfi_ctx]
    call    cfi_size
    mov     rsi, rax
    mov     rdx, [rel cfi_fde_sec]
    test    rdx, rdx
    jz      .no_section
    mov     rdx, [rdx + SECTION_name]
    mov     rcx, [rbx + CR_OFF]
    mov     r8d, R_X86_64_PC32
    call    reloc_record
    test    rax, rax
    jnz     .ret
    mov     rdi, [rel cfi_ctx]
    mov     eax, [rdi + ASMCTX_nrelocs]
    dec     eax
    imul    rax, rax, RELOC_SIZE
    add     rax, [rdi + ASMCTX_relocs]
    or      byte [rax + RELOC_flags], RELOC_FLAG_SECTION
.no_section:
    xor     esi, esi
    call    cfi_u32                        ; the start (the relocation's)
    xor     esi, esi
    call    cfi_u32                        ; the length, at its end
    xor     esi, esi
    call    cfi_uleb                       ; no augmentation data
    ; leading rules its CIE does not have (past the CIE's own, or all when
    ; too many): here
    mov     rcx, [rel cfi_lead_skip]
.lead_byte:
    cmp     rcx, [rel cfi_lead_n]
    jae     .opened
    push    rcx
    lea     rax, [rel cfi_lead]
    movzx   esi, byte [rax + rcx]
    call    cfi_u8
    pop     rcx
    inc     ecx
    jmp     .lead_byte
.opened:
    xor     eax, eax
.ret:
    ret

; ---- cfi_fde_close: rbx = the END record ----
cfi_fde_close:
    mov     rdi, [rel cfi_fde]
    add     rdi, 12                        ; the code's length
    mov     rsi, [rbx + CR_OFF]
    sub     rsi, [rel cfi_fde_start]
    call    cfi_put32
    mov     esi, 4
    mov     rax, [rel cfi_cur]
    cmp     rax, [rel cfi_last]
    jne     .pad
    call    cfi_asize                      ; the section's last: its alignment
    mov     esi, eax
.pad:
    mov     rdi, [rel cfi_fde]
    jmp     cfi_pad

; ---- cfi_advance: to record rbx's offset, from cfi_loc ----
cfi_advance:
    mov     rax, [rbx + CR_SEC]
    cmp     rax, [rel cfi_fde_sec]
    jne     .done                          ; (another section: no move)
    mov     rcx, [rbx + CR_OFF]
    sub     rcx, [rel cfi_loc]
    jbe     .done
    push    r12
    mov     r12, rcx
    mov     rax, [rbx + CR_OFF]
    mov     [rel cfi_loc], rax
    cmp     r12, 64
    jae     .wide
    lea     esi, [r12 + 0x40]              ; DW_CFA_advance_loc
    call    cfi_u8
    jmp     .moved
.wide:
    cmp     r12, 256
    jae     .two
    mov     esi, 0x02                      ; DW_CFA_advance_loc1
    call    cfi_u8
    mov     esi, r12d
    call    cfi_u8
    jmp     .moved
.two:
    cmp     r12, 65536
    jae     .four
    mov     esi, 0x03                      ; DW_CFA_advance_loc2
    call    cfi_u8
    mov     esi, r12d
    call    cfi_u8
    mov     esi, r12d
    shr     esi, 8
    call    cfi_u8
    jmp     .moved
.four:
    mov     esi, 0x04                      ; DW_CFA_advance_loc4
    call    cfi_u8
    mov     esi, r12d
    call    cfi_u32
.moved:
    pop     r12
.done:
    xor     eax, eax
    ret

; ---- cfi_rule: record rbx as DWARF CFA instructions ----
cfi_rule:
    movzx   eax, byte [rbx + CR_KIND]
    movzx   r12d, word [rbx + CR_REG1]
    mov     r14, [rbx + CR_VALUE]
    cmp     eax, CFI_DEF_CFA
    je      .def_cfa
    cmp     eax, CFI_DEF_CFA_REG
    je      .def_cfa_reg
    cmp     eax, CFI_DEF_CFA_OFF
    je      .def_cfa_off
    cmp     eax, CFI_OFFSET
    je      .offset
    cmp     eax, CFI_RESTORE
    je      .restore
    cmp     eax, CFI_UNDEFINED
    je      .undefined
    cmp     eax, CFI_SAME
    je      .same
    cmp     eax, CFI_REGISTER
    je      .register
    cmp     eax, CFI_REMEMBER
    je      .remember
    cmp     eax, CFI_RESTORE_STATE
    je      .restore_state
    cmp     eax, CFI_ESCAPE
    je      .escape
    xor     eax, eax
    ret
.def_cfa:
    mov     esi, 0x0C
    call    cfi_u8
    mov     esi, r12d
    call    cfi_uleb
    mov     rsi, r14
    jmp     cfi_uleb
.def_cfa_reg:
    mov     esi, 0x0D
    call    cfi_u8
    mov     esi, r12d
    jmp     cfi_uleb
.def_cfa_off:
    mov     esi, 0x0E
    call    cfi_u8
    mov     rsi, r14
    jmp     cfi_uleb
.offset:
    ; factored by the data alignment (-8 / -4)
    call    cfi_asize
    mov     rcx, rax
    mov     rax, r14
    cqo
    idiv    rcx
    neg     rax
    mov     r14, rax
    test    r14, r14
    js      .offset_sf
    cmp     r12d, 64
    jae     .offset_ext
    lea     esi, [r12 + 0x80]              ; DW_CFA_offset
    call    cfi_u8
    mov     rsi, r14
    jmp     cfi_uleb
.offset_ext:
    mov     esi, 0x05                      ; DW_CFA_offset_extended
    call    cfi_u8
    mov     esi, r12d
    call    cfi_uleb
    mov     rsi, r14
    jmp     cfi_uleb
.offset_sf:
    mov     esi, 0x11                      ; DW_CFA_offset_extended_sf
    call    cfi_u8
    mov     esi, r12d
    call    cfi_uleb
    mov     rsi, r14
    jmp     cfi_sleb
.restore:
    cmp     r12d, 64
    jae     .restore_ext
    lea     esi, [r12 + 0xC0]              ; DW_CFA_restore
    jmp     cfi_u8
.restore_ext:
    mov     esi, 0x06
    call    cfi_u8
    mov     esi, r12d
    jmp     cfi_uleb
.undefined:
    mov     esi, 0x07
    call    cfi_u8
    mov     esi, r12d
    jmp     cfi_uleb
.same:
    mov     esi, 0x08
    call    cfi_u8
    mov     esi, r12d
    jmp     cfi_uleb
.register:
    mov     esi, 0x09
    call    cfi_u8
    mov     esi, r12d
    call    cfi_uleb
    movzx   esi, word [rbx + CR_REG2]
    jmp     cfi_uleb
.remember:
    mov     esi, 0x0A
    jmp     cfi_u8
.restore_state:
    mov     esi, 0x0B
    jmp     cfi_u8
.escape:
    mov     rsi, r14
    jmp     cfi_u8

;*
; * [cfi_register]
; * Purpose: A register's DWARF number, for the .cfi_ directives: rax ..
; *   r15, rip, xmm0-31, st0-7, mm0-7, k0-7, rflags, the segment registers
; *   (eax .. edi, eip, xmm0-7, st0-7, mm0-7 in -f elf32), in any case
; * Input  : RDI = the name
; * Output : EAX = the number, -1 when there is none
; ;
global cfi_register
cfi_register:
    push    rbx
    push    r12
    ; in lower case
    lea     r12, [rel cfi_regbuf]
    xor     ecx, ecx
.lower:
    movzx   eax, byte [rdi + rcx]
    cmp     al, 'A'
    jb      .put
    cmp     al, 'Z'
    ja      .put
    or      al, 0x20
.put:
    mov     [r12 + rcx], al
    test    al, al
    jz      .lowered
    inc     ecx
    cmp     ecx, 15
    jb      .lower
    mov     eax, -1
    jmp     .ret
.lowered:
    ; a name of the table
    lea     rbx, [rel cfi_regs64]
    cmp     byte [rel elf32_enabled], 0
    je      .table
    lea     rbx, [rel cfi_regs32]
.table:
    cmp     byte [rbx], 0
    je      .numbered
    mov     rsi, rbx
    mov     rdi, r12
.cmp:
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     .row_next
    test    al, al
    jz      .row_hit
    inc     rsi
    inc     rdi
    jmp     .cmp
.row_hit:
    movzx   eax, byte [rbx + 7]
    jmp     .ret
.row_next:
    add     rbx, 8
    jmp     .table
.numbered:
    ; xmmN, stN, mmN, kN, rN
    lea     rbx, [rel cfi_banks64]
    cmp     byte [rel elf32_enabled], 0
    je      .bank
    lea     rbx, [rel cfi_banks32]
.bank:
    cmp     byte [rbx], 0
    je      .none
    mov     rsi, rbx
    mov     rdi, r12
.prefix:
    mov     al, [rsi]
    test    al, al
    jz      .digits
    cmp     al, [rdi]
    jne     .bank_next
    inc     rsi
    inc     rdi
    jmp     .prefix
.digits:
    ; the number after the prefix
    xor     ecx, ecx
    xor     edx, edx
.digit:
    movzx   eax, byte [rdi]
    test    al, al
    jz      .counted
    sub     eax, '0'
    cmp     eax, 9
    ja      .bank_next
    imul    ecx, ecx, 10
    add     ecx, eax
    inc     rdi
    inc     edx
    jmp     .digit
.counted:
    test    edx, edx
    jz      .bank_next
    ; rows: prefix (5 bytes), first, count, base; then a second range
    movzx   eax, byte [rbx + 5]            ; the first number of the range
    cmp     ecx, eax
    jb      .second
    movzx   edx, byte [rbx + 6]            ; how many
    add     edx, eax
    cmp     ecx, edx
    jae     .second
    sub     ecx, eax
    movzx   eax, byte [rbx + 7]
    add     eax, ecx
    jmp     .ret
.second:
    movzx   eax, byte [rbx + 8]
    cmp     ecx, eax
    jb      .bank_next
    movzx   edx, byte [rbx + 9]
    add     edx, eax
    cmp     ecx, edx
    jae     .bank_next
    sub     ecx, eax
    movzx   eax, byte [rbx + 10]
    add     eax, ecx
    jmp     .ret
.bank_next:
    add     rbx, 12
    jmp     .bank
.none:
    mov     eax, -1
.ret:
    pop     r12
    pop     rbx
    ret

[SECTION .bss]
cfi_regbuf:     resb 16

[SECTION .rodata]
cfi_name:       db ".eh_frame", 0
; name (7 bytes) + DWARF number
cfi_regs64:
    db "rax", 0,0,0,0, 0
    db "rdx", 0,0,0,0, 1
    db "rcx", 0,0,0,0, 2
    db "rbx", 0,0,0,0, 3
    db "rsi", 0,0,0,0, 4
    db "rdi", 0,0,0,0, 5
    db "rbp", 0,0,0,0, 6
    db "rsp", 0,0,0,0, 7
    db "rip", 0,0,0,0, 16
    db "rflags", 0, 49
    db "eflags", 0, 49
    db "es", 0,0,0,0,0, 50
    db "cs", 0,0,0,0,0, 51
    db "ss", 0,0,0,0,0, 52
    db "ds", 0,0,0,0,0, 53
    db "fs", 0,0,0,0,0, 54
    db "gs", 0,0,0,0,0, 55
    db "mxcsr", 0,0, 64
    db "fcw", 0,0,0,0, 65
    db "fsw", 0,0,0,0, 66
    db 0
cfi_regs32:
    db "eax", 0,0,0,0, 0
    db "ecx", 0,0,0,0, 1
    db "edx", 0,0,0,0, 2
    db "ebx", 0,0,0,0, 3
    db "esp", 0,0,0,0, 4
    db "ebp", 0,0,0,0, 5
    db "esi", 0,0,0,0, 6
    db "edi", 0,0,0,0, 7
    db "eip", 0,0,0,0, 8
    db "eflags", 0, 9
    db "es", 0,0,0,0,0, 40
    db "cs", 0,0,0,0,0, 41
    db "ss", 0,0,0,0,0, 42
    db "ds", 0,0,0,0,0, 43
    db "fs", 0,0,0,0,0, 44
    db "gs", 0,0,0,0,0, 45
    db "mxcsr", 0,0, 39
    db 0
; prefix (5 bytes), then two ranges: first, count, DWARF base each; pad
cfi_banks64:
    db "xmm", 0,0,  0, 16, 17,  16, 16, 67, 0
    db "st", 0,0,0, 0, 8, 33,   0, 0, 0, 0
    db "mm", 0,0,0, 0, 8, 41,   0, 0, 0, 0
    db "k", 0,0,0,0, 0, 8, 118, 0, 0, 0, 0
    db "r", 0,0,0,0, 8, 8, 8,   0, 0, 0, 0
    db 0
cfi_banks32:
    db "xmm", 0,0,  0, 8, 21,   0, 0, 0, 0
    db "st", 0,0,0, 0, 8, 11,   0, 0, 0, 0
    db "mm", 0,0,0, 0, 8, 29,   0, 0, 0, 0
    db 0
