; ============================================================================
; File        : src/tools/disasm/x86/x87.inc
; Part of     : src/tools/disasm/x86.s (%included by it, in this place)
; Contents    : x87 instructions, fwait
; ============================================================================


; ============================================================================
; x87 floating point
; ============================================================================

; dx_x87: prints an x87 instruction (opcode D8-DF) whose ModRM is decoded.
; Memory forms come from x87_mem by (opcode - D8) * 8 + ModRM.reg, register
; forms from x87_reg by the same index, and the register encodings that are
; whole instructions of their own (fchs, fld1, fnstsw ax, ...) from x87_fix.
; Sets dx_fail for an invalid encoding.
dx_x87:
    push    rbx
    movzx   ebx, byte [rel dx_op]
    sub     ebx, 0xD8
    shl     ebx, 3
    movzx   eax, byte [rel dx_modrm]
    shr     eax, 3
    and     eax, 7
    add     ebx, eax                       ; (opcode - D8) * 8 + reg
    shl     ebx, 4                         ; 16-byte entries
    cmp     byte [rel dx_mod], 3
    je      .reg

    ; memory: name + operand size in bytes
    lea     rax, [rel x87_mem]
    add     rbx, rax
    cmp     byte [rbx + 15], 0xFF
    jne     .mem_named
    lea     rax, [rel s_bad_opnd]          ; (objdump's "(bad) [rax]")
    mov     [rel dx_mnem], rax
    mov     esi, 1
    call    dx_mnemonic
    xor     edi, edi
    call    dx_mem
    jmp     .done
.mem_named:
    mov     [rel dx_mnem], rbx
    call    dx_x87_wait
    cmp     byte [rbx + 15], 0             ; (fldenv / fnstenv / frstor / fnsave
    jne     .mem_sized                     ; with a 66: objdump's fldenvw - 16
    cmp     byte [rel dx_p66], 0           ; bits; 16-bit mode's fldenvd)
    je      .mem_sized
    lea     rdi, [rel dx_namebuf]
    mov     rsi, [rel dx_mnem]
    call    dx_strcpy
    mov     eax, 'w'
    cmp     byte [rel dx_mode], 16
    jne     .mem_sfx
    mov     eax, 'd'
.mem_sfx:
    mov     [rdi - 1], al
    mov     byte [rdi], 0
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.mem_sized:
    mov     esi, 1
    call    dx_mnemonic
    movzx   edi, byte [rbx + 15]
    shl     edi, 3                         ; bits (0 = no size, 80 = TBYTE)
    call    dx_mem
    jmp     .done

.reg:
    lea     rax, [rel x87_reg]
    add     rbx, rax
    cmp     byte [rbx], 0
    je      .fixed
    mov     [rel dx_mnem], rbx
    mov     esi, 1
    call    dx_mnemonic
    movzx   eax, byte [rbx + 15]
    cmp     eax, 2
    je      .sti_st
    cmp     eax, 1
    jne     .sti
    lea     rsi, [rel s_st]                ; st,st(i)
    call    dx_puts
    mov     esi, ','
    call    dx_putc
.sti:
    call    .put_sti                       ; st(i)
    jmp     .done
.sti_st:
    call    .put_sti                       ; st(i),st
    lea     rsi, [rel s_commast]
    call    dx_puts
    jmp     .done

.fixed:
    ; the whole ModRM byte selects the instruction
    lea     rbx, [rel x87_fix]
    movzx   ecx, byte [rel dx_op]
    movzx   edx, byte [rel dx_modrm]
.fix_scan:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .fail
    cmp     eax, ecx
    jne     .fix_next
    cmp     dl, [rbx + 1]
    je      .fix_hit
.fix_next:
    add     rbx, 16
    jmp     .fix_scan
.fix_hit:
    lea     rax, [rbx + 2]
    mov     [rel dx_mnem], rax
    call    dx_x87_wait
    movzx   esi, byte [rbx + 15]
    cmp     esi, 2
    jae     .fix_only
    call    dx_mnemonic
    cmp     byte [rbx + 15], 0
    je      .done
    xor     esi, esi                       ; fnstsw ax
    mov     edi, 16
    call    dx_reg
    jmp     .done
.fix_only:                                 ; fneni(8087 only), fnsetpm(287 only)
    lea     rdx, [rel s_8087_only]
    cmp     esi, 2
    je      .only_put
    lea     rdx, [rel s_287_only]
.only_put:
    mov     rsi, [rel dx_mnem]
    lea     rdi, [rel dx_namebuf]
    cmp     rsi, rdi
    je      .only_end                      ; (dx_x87_wait put it there)
.only_copy:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .only_copy
    dec     rdi
    jmp     .only_cat
.only_end:
    cmp     byte [rdi], 0
    je      .only_cat
    inc     rdi
    jmp     .only_end
.only_cat:
    mov     al, [rdx]
    mov     [rdi], al
    inc     rdx
    inc     rdi
    test    al, al
    jnz     .only_cat
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
    xor     esi, esi
    call    dx_mnemonic
    jmp     .done

.fail:
    mov     byte [rel dx_fail], 1
.done:
    pop     rbx
    ret

; "st(i)" from ModRM.rm (REX.B does not apply to the x87 stack)
.put_sti:
    lea     rsi, [rel s_st]
    call    dx_puts
    mov     esi, '('
    call    dx_putc
    movzx   esi, byte [rel dx_modrm]
    and     esi, 7
    add     esi, '0'
    call    dx_putc
    mov     esi, ')'
    jmp     dx_putc

; dx_x87_wait: after a folded 9B, "fnstsw" becomes "fstsw" (and so on)
dx_x87_wait:
    cmp     byte [rel dx_fwait], 0
    je      .ret
    mov     rsi, [rel dx_mnem]
    cmp     byte [rsi + 1], 'n'            ; (fnstenv & co.: the n off - not fnop)
    jne     .ret
    cmp     word [rsi + 2], "op"
    je      .ret
    lea     rdi, [rel dx_namebuf]
    mov     byte [rdi], 'f'
    add     rsi, 2
    inc     rdi
.copy:
    mov     al, [rsi]
    mov     [rdi], al
    inc     rsi
    inc     rdi
    test    al, al
    jnz     .copy
    lea     rax, [rel dx_namebuf]
    mov     [rel dx_mnem], rax
.ret:
    ret

; dx_fwait_combo: eax = 1 when an x87 instruction follows a 9B - after
; more 9Bs, legacy prefixes and a REX / REX2 (64-bit mode): objdump folds
; the 9B into it
dx_fwait_combo:
    mov     rcx, [rel dx_cur]
.fc_skip:
    cmp     rcx, [rel dx_end]
    jae     .no
    movzx   eax, byte [rcx]
    cmp     eax, 0x9B
    je      .fc_next
    cmp     eax, 0x66
    je      .fc_next
    cmp     eax, 0x67
    je      .fc_next
    cmp     eax, 0xF0
    je      .fc_next
    cmp     eax, 0xF2
    je      .fc_next
    cmp     eax, 0xF3
    je      .fc_next
    cmp     eax, 0x26
    je      .fc_next
    cmp     eax, 0x2E
    je      .fc_next
    cmp     eax, 0x36
    je      .fc_next
    cmp     eax, 0x3E
    je      .fc_next
    cmp     eax, 0x64
    je      .fc_next
    cmp     eax, 0x65
    jne     .fc_done
.fc_next:
    inc     rcx
    jmp     .fc_skip
.fc_done:
    movzx   eax, byte [rel x86_mode]
    test    eax, eax
    jz      .fc_64
    cmp     eax, 64
    jne     .no_rex2
.fc_64:
    ; a REX before it
    lea     rdx, [rcx + 3]
    cmp     rdx, [rel dx_end]
    ja      .no_rex
    movzx   eax, byte [rcx]
    and     eax, 0xF0
    cmp     eax, 0x40
    jne     .no_rex
    inc     rcx
    call    .no_rex2
    ret
.no_rex:
    ; a REX2 (map 0) before it: "fstsw WORD PTR [r16]" (eax = 2 then)
    lea     rdx, [rcx + 4]
    cmp     rdx, [rel dx_end]
    ja      .no_rex2
    cmp     byte [rcx], 0xD5
    jne     .no_rex2
    test    byte [rcx + 1], 0x80
    jnz     .no_rex2
    add     rcx, 2
    call    .no_rex2
    ret
.no_rex2:
    lea     rdx, [rcx + 2]
    cmp     rdx, [rel dx_end]
    ja      .no
    movzx   eax, byte [rcx]
    cmp     eax, 0xD8
    jb      .no
    cmp     eax, 0xDF
    jbe     .yes
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret
