; ============================================================================
; File        : src/tools/disasm/x86/wrapper.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : x86_decode: the decoder's entry, trials and variants, string helpers
; ============================================================================


[SECTION .text]

; ---- x86_decode --------------------------
;
; x86_decode
; Decodes the instruction at rdi and appends its text to a FmtBuf.
; Input    : rdi = pointer to the code
;            rsi = bytes available from rdi
;            rdx = the instruction's address (for branch targets)
;            rcx = FmtBuf to append to
; Output   : rax = instruction length, or 0 if it could not be decoded
;              (nothing useful is written then; print "(bad)")
;            rdx = target address of a direct jmp/jcc/call/loop, or -1
;            x86_rip_target = the address a [rip + disp] operand names, or -1
;
; A prefix the instruction has no use for is written as objdump writes it
; ("fs", "data16", "addr32", "rex.WB"): the instruction decoded without it
; (a segment / 66 / 67 byte left out, a REX bit cleared, a bare REX left
; out) reads the same - the bytes are there, the listing shows them.
global x86_decode
x86_decode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     [rel dx_wargs], rdi
    mov     [rel dx_wargs + 8], rsi
    mov     [rel dx_wargs + 16], rdx
    mov     [rel dx_wargs + 24], rcx
    cmp     rsi, 15                        ; (the bytes a variant may read)
    jbe     .wavail
    mov     esi, 15
.wavail:
    mov     [rel dx_wavail], rsi
    call    dx_rexstop                     ; (a REX before a prefix: alone)
    test    rax, rax
    jnz     .rexstop
    mov     rdi, [rel dx_wargs]
    mov     rsi, [rel dx_wargs + 8]
    mov     rdx, [rel dx_wargs + 16]
    mov     rcx, [rel dx_wargs + 24]
    mov     byte [rel dx_upfx], 0
    mov     byte [rel dx_urex], 0
    mov     byte [rel dx_upend], 0
    mov     byte [rel dx_urend], 0
    ; the instruction as it is, into the first scratch buffer
    lea     r8, [rel dx_tfb_a]
    lea     r9, [rel dx_tbuf_a]
    call    dx_trial
    test    rax, rax
    jz      .final
    mov     r14, rax                       ; r14 = its length
    mov     al, [rel dx_sel66]
    mov     [rel dx_w66], al
    mov     al, [rel dx_rex2own]
    mov     [rel dx_w2own], al
    mov     al, [rel dx_d16w]
    mov     [rel dx_wd16], al
    ; REX.W on a near call / jmp (64 bits whatever it says): unused, though
    ; with it cleared a 66 would count (objdump: "data16 rex.W call")
    mov     byte [rel dx_wf64], 0
    test    byte [rel dx_rex], 8
    jz      .wf64_done
    test    byte [rel dx_flags], FL_F64 | FL_D64
    jnz     .wf64_f64                      ; (push / pop / enter: so too)
    cmp     byte [rel dx_map], 1           ; (pushf / popf: so too)
    jne     .wf64_done
    mov     al, [rel dx_op]
    and     al, 0xFE
    cmp     al, 0x9C
    jne     .wf64_done
.wf64_f64:
    cmp     byte [rel dx_sflags], 0
    jne     .wf64_done
    mov     byte [rel dx_wf64], 1
.wf64_done:
    ; its prefixes: each segment / 66 / 67 (the first of a kind), then a REX
    xor     r15d, r15d                     ; r15 = index
    mov     qword [rel dx_w66at], -1
    xor     ebx, ebx                       ; bl: kinds seen (1 seg, 2 66, 4 67)
.scan:
    lea     rax, [r15 + 1]
    cmp     rax, r14
    jae     .final                         ; (the opcode is no prefix)
    mov     rcx, [rel dx_wargs]
    movzx   eax, byte [rcx + r15]
    cmp     eax, 0xF0
    je      .next
    cmp     eax, 0xF2
    je      .next
    cmp     eax, 0xF3
    je      .next
    cmp     eax, 0x9B                      ; (fwait folded into an x87 one)
    je      .next
    mov     edx, 2
    lea     r13, [rel s_u66]
    cmp     byte [rel dx_mode], 16
    jne     .u66
    lea     r13, [rel s_u66_32]            ; (16-bit mode: data32)
.u66:
    cmp     eax, 0x66
    je      .kind
    mov     edx, 4
    lea     r13, [rel s_u67]
    cmp     byte [rel dx_mode], 32
    jne     .u67
    lea     r13, [rel s_u67_16]            ; (32-bit mode: addr16)
.u67:
    cmp     eax, 0x67
    je      .kind
    mov     edx, 1
    lea     r13, [rel s_ucs]
    cmp     eax, 0x2E
    je      .kind
    lea     r13, [rel s_uss]
    cmp     eax, 0x36
    je      .kind
    lea     r13, [rel s_uds]
    cmp     eax, 0x3E
    je      .kind
    lea     r13, [rel s_ues]
    cmp     eax, 0x26
    je      .kind
    lea     r13, [rel s_ufs]
    cmp     eax, 0x64
    je      .kind
    lea     r13, [rel s_ugs]
    cmp     eax, 0x65
    je      .kind
    cmp     eax, 0xD5
    je      .rex2
    mov     ecx, eax
    and     ecx, 0xF0
    cmp     ecx, 0x40
    jne     .final
    cmp     byte [rel dx_mode], 64         ; (16 / 32-bit mode: inc / dec)
    je      .rex
    jmp     .final
.rex2:
    ; objdump names a REX2 whose R4 / X4 / B4 change nothing (no register
    ; 16-31: a REX, or none, would do) - "{rex2 0xc0} sgdt [rdx]"
    cmp     byte [rel dx_mode], 64
    jne     .final
    cmp     byte [rel dx_w2own], 0
    jne     .final
    lea     rax, [r15 + 2]
    cmp     rax, r14
    ja      .final
    mov     rcx, [rel dx_wargs]
    movzx   r12d, byte [rcx + r15 + 1]     ; the payload
    test    r12d, 0x70
    jz      .rex2_name
    mov     r13d, 0x40                     ; R4 X4 B4 W R3 X3 B3: one unused?
.rex2_bit:
    test    r12d, r13d
    jz      .rex2_next
    lea     edi, [r15 + 1]
    mov     esi, r13d
    call    dx_variant_clear
    test    eax, eax
    jnz     .rex2_name
.rex2_next:
    shr     r13d, 1
    jnz     .rex2_bit
    jmp     .final
.rex2_name:
    lea     rdi, [rel dx_urend]
    lea     rsi, [rel s_rex2_open]
    call    dx_strcpy
    dec     rdi                            ; (past "0x")
    mov     eax, r12d
    shr     eax, 4
    jz      .rex2_lo
    call    .hex_digit
.rex2_lo:
    mov     eax, r12d
    and     eax, 15
    call    .hex_digit
    mov     dword [rdi], "} "              ; (and the NUL)
    jmp     .final
.hex_digit:
    add     eax, '0'
    cmp     eax, '9'
    jbe     .hex_put
    add     eax, 'a' - '9' - 1
.hex_put:
    mov     [rdi], al
    inc     rdi
    ret
.kind:
    test    ebx, edx
    jnz     .next
    or      ebx, edx
    cmp     edx, 2
    jne     .kind_at
    mov     [rel dx_w66at], r15            ; (the first 66)
.kind_at:
    cmp     edx, 2                         ; (a 66 that chose an SSE column)
    jne     .kind_try
    cmp     byte [rel dx_w66], 0
    jne     .next
.kind_try:
    mov     edi, r15d
    call    dx_variant_drop
    test    eax, eax
    jz      .next
    lea     rdi, [rel dx_upend]
    mov     rsi, r13
    call    dx_strcat
.next:
    inc     r15
    jmp     .scan
.rex:
    mov     r12d, eax                      ; r12 = the REX byte
    test    eax, 0x0F
    jnz     .rex_bits
    mov     edi, r15d                      ; a bare 40: left out
    call    dx_variant_drop
    test    eax, eax
    jz      .final
    jmp     .rex_name
.rex_bits:
    cmp     byte [rel dx_wf64], 0
    jne     .rex_name
    mov     r13d, 8                        ; W, R, X, B
.bit:
    test    r12d, r13d
    jz      .bit_next
    mov     edi, r15d
    mov     esi, r13d
    call    dx_variant_clear
    test    eax, eax
    jnz     .rex_name
    cmp     r13d, 8                        ; (W with a 66 it overrides: the
    jne     .bit_next                      ; same but for that "data16 ")
    cmp     byte [rel dx_wd16], 0
    je      .bit_nod16
    call    dx_same_d16
    test    eax, eax
    jnz     .rex_name
.bit_nod16:
    mov     rax, [rel dx_w66at]            ; (... or without the 66 and W:
    test    rax, rax                       ; "data16 rex.W jl")
    js      .bit_next
    mov     edi, r15d
    call    dx_variant_nod16
    test    eax, eax
    jnz     .rex_name
.bit_next:
    shr     r13d, 1
    jnz     .bit
    jmp     .final
.rex_name:
    ; "rex" and its bits' letters: "rex.WRXB "
    lea     rdi, [rel dx_urend]
    mov     dword [rdi], "rex"
    add     rdi, 3
    test    r12d, 0x0F
    jz      .rn_end
    mov     byte [rdi], '.'
    inc     rdi
    mov     ecx, 8
    lea     rsi, [rel s_rexbits]
.rn_bit:
    test    r12d, ecx
    jz      .rn_skip
    mov     al, [rsi]
    mov     [rdi], al
    inc     rdi
.rn_skip:
    inc     rsi
    shr     ecx, 1
    jnz     .rn_bit
.rn_end:
    mov     word [rdi], ' '                ; (and the NUL)
.final:
    ; the names found, then the real decode
    lea     rdi, [rel dx_upfx]
    lea     rsi, [rel dx_upend]
    call    dx_strcpy
    lea     rdi, [rel dx_urex]
    lea     rsi, [rel dx_urend]
    call    dx_strcpy
    mov     rdi, [rel dx_wargs]
    mov     rsi, [rel dx_wargs + 8]
    mov     rdx, [rel dx_wargs + 16]
    mov     rcx, [rel dx_wargs + 24]
    call    dx_decode1
.rexstop_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.rexstop:
    mov     rdx, -1
    mov     qword [rel x86_rip_target], -1
    jmp     .rexstop_ret

; dx_rexstop: 64-bit mode, prefixes, a REX, then a prefix / REX / D5 (the
; REX ignored): objdump's instruction ends at the REX, each byte named
; ("data16 rex"). rax = the length (the text appended), or 0
dx_rexstop:
    push    rbx
    push    r12
    xor     eax, eax
    movzx   ecx, byte [rel x86_mode]
    test    ecx, ecx
    jz      .s64
    cmp     ecx, 64
    jne     .none
.s64:
    mov     r12, [rel dx_wargs]
    lea     rdi, [rel dx_rsbuf]
    xor     ebx, ebx                       ; index
.scan:
    lea     rax, [rbx + 1]
    cmp     rax, [rel dx_wavail]
    jae     .none                          ; (the REX and a byte after it)
    movzx   eax, byte [r12 + rbx]
    mov     edx, eax
    and     edx, 0xF0
    cmp     edx, 0x40
    je      .rex
    call    .pfx
    test    rsi, rsi
    jz      .none
    call    dx_strcpy
    dec     rdi                            ; (on the NUL)
    inc     ebx
    jmp     .scan
.rex:
    mov     ecx, eax                       ; the REX
    movzx   eax, byte [r12 + rbx + 1]
    mov     edx, eax
    and     edx, 0xF0
    cmp     edx, 0x40
    je      .stop
    cmp     eax, 0xD5
    je      .stop
    cmp     eax, 0x9B                      ; (fwait: a prefix to objdump)
    je      .stop
    push    rcx
    push    rdi
    call    .pfx
    pop     rdi
    pop     rcx
    test    rsi, rsi
    jz      .none
.stop:
    mov     dword [rdi], "rex"
    add     rdi, 3
    test    ecx, 0x0F
    jz      .put
    mov     byte [rdi], '.'
    inc     rdi
    mov     edx, 8
    lea     rsi, [rel s_rexbits]
.bit:
    test    ecx, edx
    jz      .bit_skip
    mov     al, [rsi]
    mov     [rdi], al
    inc     rdi
.bit_skip:
    inc     rsi
    shr     edx, 1
    jnz     .bit
.put:
    mov     byte [rdi], 0
    mov     rdi, [rel dx_wargs + 24]
    lea     rsi, [rel dx_rsbuf]
    call    fmt_str
    lea     eax, [rbx + 1]
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    ret
.pfx:                                      ; al's prefix name (rsi), or 0
    lea     rsi, [rel s_u66]
    cmp     eax, 0x66
    je      .pfx_ret
    lea     rsi, [rel s_u67]
    cmp     eax, 0x67
    je      .pfx_ret
    lea     rsi, [rel s_lock]
    cmp     eax, 0xF0
    je      .pfx_ret
    lea     rsi, [rel s_repz]
    cmp     eax, 0xF3
    je      .pfx_ret
    lea     rsi, [rel s_repnz]
    cmp     eax, 0xF2
    je      .pfx_ret
    lea     rsi, [rel s_ucs]
    cmp     eax, 0x2E
    je      .pfx_ret
    lea     rsi, [rel s_uss]
    cmp     eax, 0x36
    je      .pfx_ret
    lea     rsi, [rel s_uds]
    cmp     eax, 0x3E
    je      .pfx_ret
    lea     rsi, [rel s_ues]
    cmp     eax, 0x26
    je      .pfx_ret
    lea     rsi, [rel s_ufs]
    cmp     eax, 0x64
    je      .pfx_ret
    lea     rsi, [rel s_ugs]
    cmp     eax, 0x65
    je      .pfx_ret
    xor     esi, esi
.pfx_ret:
    ret

; dx_trial: decode rdi / rsi / rdx (x86_decode's) into the scratch FmtBuf
; r8 over the buffer r9 (no unused-prefix names). Output rax = the length.
dx_trial:
    mov     byte [rel dx_trialing], 1
    push    rdi
    push    rsi
    push    rdx
    push    r8
    mov     rdi, r8
    mov     rsi, r9
    mov     edx, DX_TBUF
    call    fmt_init
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi
    call    dx_decode1
    mov     byte [rel dx_trialing], 0
    ret

; dx_variant_drop: the instruction without its byte edi, decoded at the
; address after (its branch targets the same): eax = 1 when it reads as
; the instruction does (length one less)
dx_variant_drop:
    push    rbx
    mov     ebx, edi
    mov     rsi, [rel dx_wargs]
    lea     rdi, [rel dx_tbytes]
    xor     ecx, ecx                       ; from
    xor     edx, edx                       ; to
.copy:
    cmp     rcx, [rel dx_wavail]           ; (what follows too: it may be read)
    jae     .copied
    cmp     ecx, ebx
    je      .skip
    mov     al, [rsi + rcx]
    mov     [rdi + rdx], al
    inc     edx
.skip:
    inc     ecx
    jmp     .copy
.copied:
    lea     rdi, [rel dx_tbytes]
    mov     rsi, [rel dx_wavail]
    dec     rsi
    mov     rdx, [rel dx_wargs + 16]
    inc     rdx
    lea     r8, [rel dx_tfb_b]
    lea     r9, [rel dx_tbuf_b]
    call    dx_trial
    lea     rcx, [r14 - 1]
    pop     rbx
    jmp     dx_same

; dx_variant_clear: the instruction with bit esi of its byte edi cleared:
; eax = 1 when it reads as the instruction does (the same length)
dx_variant_clear:
    push    rbx
    mov     ebx, edi
    not     esi
    mov     r10, [rel dx_wargs]
    lea     rdi, [rel dx_tbytes]
    xor     ecx, ecx
.copy:
    cmp     rcx, [rel dx_wavail]
    jae     .copied
    mov     al, [r10 + rcx]
    cmp     ecx, ebx
    jne     .put
    and     eax, esi
.put:
    mov     [rdi + rcx], al
    inc     ecx
    jmp     .copy
.copied:
    lea     rdi, [rel dx_tbytes]
    mov     rsi, [rel dx_wavail]
    mov     rdx, [rel dx_wargs + 16]
    lea     r8, [rel dx_tfb_b]
    lea     r9, [rel dx_tbuf_b]
    call    dx_trial
    mov     [rel dx_vlen], rax
    mov     rcx, r14
    pop     rbx
    jmp     dx_same

; dx_variant_nod16: the instruction without its 66 (dx_w66at) and with
; REX.W (byte edi) cleared: eax = 1 when it reads as the instruction does but
; for the instruction's leading "data16 "
dx_variant_nod16:
    push    rbx
    mov     ebx, edi
    mov     rsi, [rel dx_wargs]
    lea     rdi, [rel dx_tbytes]
    xor     ecx, ecx                       ; from
    xor     edx, edx                       ; to
.copy:
    cmp     rcx, [rel dx_wavail]
    jae     .copied
    cmp     rcx, [rel dx_w66at]
    je      .skip
    mov     al, [rsi + rcx]
    cmp     ecx, ebx
    jne     .put
    and     al, ~8
.put:
    mov     [rdi + rdx], al
    inc     edx
.skip:
    inc     ecx
    jmp     .copy
.copied:
    lea     rdi, [rel dx_tbytes]
    mov     rsi, [rel dx_wavail]
    dec     rsi
    mov     rdx, [rel dx_wargs + 16]
    inc     rdx
    lea     r8, [rel dx_tfb_b]
    lea     r9, [rel dx_tbuf_b]
    call    dx_trial
    inc     rax                            ; (one byte fewer)
    mov     [rel dx_vlen], rax
    pop     rbx
    jmp     dx_same_d16

; dx_same_d16: eax = 1 when the last dx_variant_clear read as the
; instruction does but for its leading "data16 " (7 bytes)
dx_same_d16:
    cmp     [rel dx_vlen], r14
    jne     .no
    lea     rsi, [rel dx_tbuf_a]           ; (the spacing may differ: a run of
    cmp     byte [rel dx_wd16], 0          ; blanks is one)
    je      .cmp
    add     rsi, 7
.cmp:
    lea     rdi, [rel dx_tbuf_b]
.cmp_loop:
    movzx   eax, byte [rsi]
    movzx   ecx, byte [rdi]
    cmp     eax, ' '
    jne     .cmp_ch
    cmp     ecx, ' '
    jne     .no
.skip_a:
    inc     rsi
    cmp     byte [rsi], ' '
    je      .skip_a
.skip_b:
    inc     rdi
    cmp     byte [rdi], ' '
    je      .skip_b
    jmp     .cmp_loop
.cmp_ch:
    cmp     eax, ecx
    jne     .no
    test    eax, eax
    jz      .yes
    inc     rsi
    inc     rdi
    jmp     .cmp_loop
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; dx_same: eax = 1 when the trial's length rax is rcx and its text (the
; second scratch buffer) is the first's
dx_same:
    cmp     rax, rcx
    jne     .no
    mov     rcx, [rel dx_tfb_a + FMTBUF_len]
    cmp     rcx, [rel dx_tfb_b + FMTBUF_len]
    jne     .no
    lea     rsi, [rel dx_tbuf_a]
    lea     rdi, [rel dx_tbuf_b]
    repe    cmpsb
    jne     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; dx_strcat / dx_strcpy: rsi's string after rdi's / over it
dx_strcat:
    cmp     byte [rdi], 0
    je      dx_strcpy
    inc     rdi
    jmp     dx_strcat
dx_strcpy:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     dx_strcpy
    ret
