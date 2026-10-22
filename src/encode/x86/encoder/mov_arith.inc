; ============================================================================
; File        : src/encode/x86/encoder/mov_arith.inc
; Part of     : src/encode/x86/encoder.s (%included by it, in this place)
; Contents    : mov, arithmetic, syscall / sysret, xchg, push / pop, branches, ret, jcc
; ============================================================================


;*
; * [amd64_encode_mov]
; * Handles various MOV encodings.
; ;
amd64_encode_mov:
    prologue
    ; check operands
    cmp     byte [r12 + INST_nops], 2
    jne     .error
    
    lea     r13, [r12 + INST_op0]  ; r13 = Dest
    lea     r14, [r12 + INST_op1]  ; r14 = Src
    
    ; Case 0: PRIVILEGED MOV (CRn/DRn)
    IF byte [r13 + OPERAND_reg], ge, 32
        IF byte [r13 + OPERAND_reg], le, 63
            ; MOV CRn/DRn, reg (0x0F 0x22/0x23)
            mov cl, [r13 + OPERAND_reg]
            and cl, 0x0F
            mov dl, [r14 + OPERAND_reg] ; GPR
            
            ; Calculate REX: 0x40
            ; (CR_hi << 2)
            ; (GPR_hi)
            mov al, 0x40
            mov r8b, cl
            shr r8b, 3
            shl r8b, 2
            or al, r8b  ; REX.R for CR
            mov r8b, dl
            shr r8b, 3
            or al, r8b              ; REX.B for GPR
            IF al, ne, 0x40
                call amd64_emit_byte
            ENDIF 
            
            mov al, 0x0F
            call amd64_emit_byte
            mov al, 0x22
            IF byte [r13 + OPERAND_reg], ge, 48
            inc al
            ENDIF
            call amd64_emit_byte
            
            mov al, cl
            and al, 0x07
            mov rdi, r14
            call amd64_emit_modrm_sib
            jmp .done
            ENDIF
            ENDIF
    IF byte [r14 + OPERAND_reg], ge, 32
        IF byte [r14 + OPERAND_reg], le, 63
            ; MOV reg, CRn/DRn (0x0F 0x20/0x21)
            mov cl, [r14 + OPERAND_reg]
            and cl, 0x0F
            mov dl, [r13 + OPERAND_reg] ; GPR
            
            ; Calculate REX: 0x40
            ; (CR_hi << 2)
            ; (GPR_hi)
            mov al, 0x40
            mov r8b, cl
            shr r8b, 3
            shl r8b, 2
            or al, r8b  ; REX.R for CR
            mov r8b, dl
            shr r8b, 3
            or al, r8b              ; REX.B for GPR
            IF al, ne, 0x40
                call amd64_emit_byte
            ENDIF 
            
            mov al, 0x0F
            call amd64_emit_byte
            mov al, 0x20
            IF byte [r14 + OPERAND_reg], ge, 48
            inc al
            ENDIF
            call amd64_emit_byte
            
            mov al, cl
            and al, 0x07
            mov rdi, r13
            call amd64_emit_modrm_sib
            jmp .done
            ENDIF
            ENDIF

    ; Case 1: MOV REG, REG
    IF byte [r13 + OPERAND_kind], e, OP_REG
        IF byte [r14 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r13 + OPERAND_size]
            mov     rsi, r14           ; Src
            mov     rdx, r13           ; Dest
            call    amd64_emit_prefixes
            
            ; Opcode 0x88 (8-bit) or 0x89 (16/32/64-bit)
            mov     al, 0x88
            IF byte [r13 + OPERAND_size], ne, 8
                inc al
                ENDIF
            call    amd64_emit_byte
            
            ; ModR/M: 11 (reg,reg)
            ; (src << 3)
            ; dest
            mov     al, 0xC0
            mov     cl, [r14 + OPERAND_reg]
            and cl, 0x07
            shl cl, 3
            or al, cl
            mov     cl, [r13 + OPERAND_reg]
            and cl, 0x07
            or al, cl
            call    amd64_emit_byte
            jmp     .done
            ENDIF
        
        ; Case 2: MOV REG, IMM / SYMBOL
        mov     al, [r14 + OPERAND_kind]
        IF al, e, OP_IMM
            jmp .do_imm
        ENDIF
        IF al, e, OP_SYMBOL
            jmp .do_imm
        ENDIF
        jmp .not_imm
        
    .do_imm:
            ; mov r64: "dword x" is REX.W C7 /0 id (sign-extended); "strict
            ; x", -O0 and -O1 the B8+r imm64 form; else the shortest (NASM)
            cmp     byte [r13 + OPERAND_size], 64
            jne     .imm_any
            cmp     byte [r14 + OPERAND_size], 32
            jne     .imm_unsized
            ; "dword 5" (a number, not strict) under -Ox: the shortest
            ; still, NASM 3's (B8+r imm32 for 5, C7 for -1)
            cmp     byte [r14 + OPERAND_kind], OP_SYMBOL
            je      .mov_c7
            test    byte [r14 + OPERAND_flags], OP_FLAG_STRICT
            jnz     .mov_c7
            cmp     byte [rbx + ASMCTX_opt], OPT_NONE
            je      .mov_c7
            cmp     byte [rbx + ASMCTX_opt], OPT_MIN
            je      .mov_c7
.imm_unsized:
            mov     dl, 64
            test    byte [r14 + OPERAND_flags], OP_FLAG_STRICT
            jnz     .mov_imm64
            cmp     byte [rbx + ASMCTX_opt], OPT_NONE
            je      .mov_imm64
            cmp     byte [rbx + ASMCTX_opt], OPT_MIN
            je      .mov_imm64
.imm_any:
            mov     dl, [r13 + OPERAND_size]
            mov     rax, [r14 + OPERAND_imm]
            
            ; OPTIMIZATION: 64-bit MOV to REG with 32-bit non-negative IMM
            ; can use 32-bit MOV (zero-extension) - NASM's; GNU as writes
            ; the REX.W form it was asked for ("mov rax, 5": 48 C7 C0)
            extern  gas_names
            cmp     byte [rel gas_names], 0
            jne     .no_zext
            IF dl, e, 64
                IF byte [r14 + OPERAND_kind], e, OP_IMM
                    mov     r11, rax
                    shr     r11, 32
                    IF r11, e, 0
                        mov dl, 32
                    ENDIF
                    ENDIF
                ENDIF
.no_zext:

            ; A negative value that fits a sign-extended imm32: REX.W C7 /0 id
            ; (7 bytes, not the 10 of B8+r imm64), as NASM picks
            IF dl, e, 64
                IF byte [r14 + OPERAND_kind], e, OP_IMM
                    movsxd  r11, eax
                    cmp     r11, rax
                    jne     .mov_imm64
                    mov     al, 64
                    mov     rsi, 0
                    mov     rdx, r13
                    call    amd64_emit_prefixes
                    mov     al, 0xC7
                    call    amd64_emit_byte
                    mov     al, [r13 + OPERAND_reg]
                    and     al, 0x07
                    or      al, 0xC0
                    call    amd64_emit_byte
                    mov     rdi, [r14 + OPERAND_imm]
                    call    amd64_emit_dword
                    jmp     .done
                    ENDIF
                ENDIF
            jmp     .mov_imm64
.mov_c7:
            ; "mov rax, dword x": REX.W C7 /0 id, a label's address as a
            ; sign-extended 32-bit field (R_X86_64_32S)
            mov     al, 64
            xor     esi, esi
            mov     rdx, r13
            call    amd64_emit_prefixes
            mov     al, 0xC7
            call    amd64_emit_byte
            lea     r13, [r12 + INST_op0]
            lea     r14, [r12 + INST_op1]
            mov     al, [r13 + OPERAND_reg]
            and     al, 0x07
            or      al, 0xC0
            call    amd64_emit_byte
            lea     r14, [r12 + INST_op1]
            cmp     byte [r14 + OPERAND_kind], OP_SYMBOL
            je      .c7_sym
            mov     rdi, [r14 + OPERAND_imm]
            call    amd64_emit_dword
            jmp     .done
.c7_sym:
            mov     rdi, rbx
            mov     rsi, [rbx + ASMCTX_curr_sec]
            mov     rsi, [rsi + SECTION_size]
            mov     rdx, [r14 + OPERAND_sym]
            mov     rcx, [r14 + OPERAND_imm]
            mov     r8, R_X86_64_32S
            cmp     byte [r14 + OPERAND_pcrel], 0
            je      .c7_abs
            mov     r8, R_X86_64_PC32
            add     rcx, rsi
.c7_abs:
            call    reloc_record
            xor     edi, edi
            call    amd64_emit_dword
            jmp     .done
.mov_imm64:
            ; 64-bit MOV REG, IMM64 / SYMBOL
            IF dl, e, 64
                mov al, 64
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]     ; Current offset in active section
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_64
                    cmp byte [r14 + OPERAND_pcrel], 0   ; "mov eax, x - $"
                    je .abs_64
                    mov r8, R_X86_64_PC64
                    add rcx, rsi                       ; (the field's place)
.abs_64:
                    call reloc_record
                    xor rdi, rdi
                    call amd64_emit_qword
                    ELSE
                    mov rdi, [r14 + OPERAND_imm]
                    call amd64_emit_qword
                    ENDIF
                jmp .done
                ENDIF
            
            ; 32-bit MOV REG, IMM32 / SYMBOL
            IF dl, e, 32
                mov al, 32
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]     ; Current offset
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_32
                    cmp byte [r14 + OPERAND_pcrel], 0   ; "mov eax, x - $"
                    je .abs_32
                    mov r8, R_X86_64_PC32
                    add rcx, rsi                       ; (the field's place)
.abs_32:
                    call reloc_record
                    xor rdi, rdi
                    call amd64_emit_dword
                    ELSE
                    mov rdi, [r14 + OPERAND_imm]
                    call amd64_emit_dword
                    ENDIF
                jmp .done
                ENDIF
            
            ; 16-bit MOV REG, IMM16 / SYMBOL
            IF dl, e, 16
                mov al, 16
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB8
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    ; a label or a constant defined later: relocated
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_16
                    cmp byte [r14 + OPERAND_pcrel], 0   ; "mov eax, x - $"
                    je .abs_16
                    mov r8, R_X86_64_PC16
                    add rcx, rsi                       ; (the field's place)
.abs_16:
                    call reloc_record
                    xor rdi, rdi
                    call amd64_emit_word
                    ELSE
                    mov rdi, [r14 + OPERAND_imm]   ; emit_word takes its value in RDI
                    call amd64_emit_word
                    ENDIF
                jmp .done
                ENDIF
            
            ; 8-bit MOV REG, IMM8
            IF dl, e, 8
                mov al, 8
                mov rsi, 0
                mov rdx, r13
                call amd64_emit_prefixes
                mov al, 0xB0
                mov cl, [r13 + OPERAND_reg]
                and cl, 0x07
                add al, cl
                call amd64_emit_byte
                IF byte [r14 + OPERAND_kind], e, OP_SYMBOL
                    mov rdi, rbx
                    mov rsi, [rbx + ASMCTX_curr_sec]
                    mov rsi, [rsi + SECTION_size]
                    mov rdx, [r14 + OPERAND_sym]
                    mov rcx, [r14 + OPERAND_imm]      ; Addend
                    mov r8, R_X86_64_8
                    cmp byte [r14 + OPERAND_pcrel], 0   ; "mov eax, x - $"
                    je .abs_8
                    mov r8, R_X86_64_PC8
                    add rcx, rsi                       ; (the field's place)
.abs_8:
                    call reloc_record
                    xor eax, eax
                    call amd64_emit_byte
                    ELSE
                    mov rax, [r14 + OPERAND_imm]
                    call amd64_emit_byte
                    ENDIF
                jmp .done
                ENDIF
    .not_imm:

        ; Case 3: MOV REG, MEM
        IF byte [r14 + OPERAND_kind], e, OP_MEM
            ; Dynamic Prefixes (al = size, rsi = ModRM.reg operand, rdx = rm)
            mov     al, [r13 + OPERAND_size]
            mov     rsi, r13         ; Reg -> ModRM.reg
            mov     rdx, r14         ; Mem -> ModRM.rm
            call    amd64_emit_prefixes
            lea     r13, [r12 + INST_op0]
            lea     r14, [r12 + INST_op1]

            mov     al, 0x8B
            IF byte [r13 + OPERAND_size], e, 8
                mov al, 0x8A       ; 8-bit load
                ENDIF
            call amd64_emit_byte
            
            ; ModRM/SIB
            mov     al, [r13 + OPERAND_reg]
            and     al, 7            ; Low 3 bits for ModRM
            mov     rdi, r14
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
            ENDIF

    ; Case 4: MOV MEM, REG
    IF byte [r13 + OPERAND_kind], e, OP_MEM
        IF byte [r14 + OPERAND_kind], e, OP_REG
            ; Dynamic Prefixes (al = size, rsi = ModRM.reg operand, rdx = rm)
            mov     al, [r14 + OPERAND_size]
            mov     rsi, r14         ; Reg -> ModRM.reg
            mov     rdx, r13         ; Mem -> ModRM.rm
            call    amd64_emit_prefixes
            lea     r13, [r12 + INST_op0]
            lea     r14, [r12 + INST_op1]

            mov     al, 0x89
            IF byte [r14 + OPERAND_size], e, 8
                mov al, 0x88       ; 8-bit store
                ENDIF
            call amd64_emit_byte
            
            mov     al, [r14 + OPERAND_reg]
            and     al, 7
            mov     rdi, r13
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
        
        ; Case 5: MOV MEM, IMM
        IF byte [r14 + OPERAND_kind], e, OP_IMM
            ; Dynamic Prefixes (W bit depends on MEM size)
            mov     al, [r13 + OPERAND_size]
            xor     rsi, rsi
            mov     rdx, r13         ; Mem -> ModRM.rm
            call    amd64_emit_prefixes
            lea     r13, [r12 + INST_op0]
            lea     r14, [r12 + INST_op1]
            
            mov     al, 0xC7
            IF byte [r13 + OPERAND_size], e, 8
                mov al, 0xC6       ; 8-bit immediate store
                ENDIF
            call amd64_emit_byte
            
            xor     al, al   ; Extension Digit 0
            mov     rdi, r13
            call    amd64_emit_modrm_sib
            
            mov     rdi, [r14 + OPERAND_imm]
            ; In x86_64, MOV [MEM], IMM32 is the standard even for 64-bit;
            ; the 8-bit form (0xC6) takes an imm8 and a 16-bit store an imm16.
            IF byte [r13 + OPERAND_size], e, 8
                mov     rax, rdi
                call    amd64_emit_byte
                jmp     .done
                ENDIF
            IF byte [r13 + OPERAND_size], e, 16
                call    amd64_emit_word
                jmp     .done
                ENDIF
            call    amd64_emit_dword
            jmp     .done
            ENDIF
            ENDIF
    
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_arithmetic]
; * Input:
; *   R13: Base Opcode (for reg-reg)
; *   R14: Extension Digit (for imm)
; ;
amd64_encode_arithmetic:
    prologue
    cmp     byte [r12 + INST_nops], 2
    jne     .error

    lea     r10, [r12 + INST_op0]  ; Dest
    lea     r11, [r12 + INST_op1]  ; Src

    ; A 64-bit destination takes a sign-extended imm32. Like NASM, a value
    ; from 0x80000000 to 0xFFFFFFFF stands for its low 32 bits sign-extended:
    ; "cmp r8, 0xFFFFFFFF" is cmp r8, -1 and "or rax, 0x80000001" sets the
    ; upper half too.
    cmp     byte [r11 + OPERAND_kind], OP_IMM
    jne     .imm_ok
    cmp     byte [r10 + OPERAND_size], 64
    jne     .imm_ok
    mov     rax, [r11 + OPERAND_imm]
    mov     rcx, rax
    shr     rcx, 32
    jnz     .imm_ok
    movsxd  rax, eax
    mov     [r11 + OPERAND_imm], rax
.imm_ok:
    
    ; Case 1: r/m, reg
    IF byte [r10 + OPERAND_kind], e, OP_REG
        IF byte [r11 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            mov     rsi, r11           ; Src
            mov     rdx, r10           ; Dest
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Table holds the 16/32/64-bit opcode; 8-bit form is Base - 1
            mov     rax, r13
            IF byte [r10 + OPERAND_size], e, 8
                dec al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]

            ; ModR/M: 11
            ; src
            ; dest
            mov     al, 0xC0
            mov     cl, [r11 + OPERAND_reg]
            and cl, 0x07
            shl cl, 3
            or al, cl
            mov     cl, [r10 + OPERAND_reg]
            and cl, 0x07
            or al, cl
            call    amd64_emit_byte
            jmp     .done
            ENDIF
        
        ; Case 2: r/m, imm
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            ; VALIDATION: a 64-bit destination takes a sign-extended imm32, so
            ; the immediate must fit. Narrower destinations accept any value of
            ; their own width ("and edx, 0xFC000000" is legal).
            IF byte [r10 + OPERAND_size], e, 64
                mov     rax, [r11 + OPERAND_imm]
                mov     rcx, rax
                sar     rcx, 31            ; Check if bits 31-63 are identical
                IF ecx, ne, 0
                    IF ecx, ne, 0xFFFFFFFF
                        jmp .error
                        ENDIF
                        ENDIF
                ENDIF

            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            xor     rsi, rsi
            mov     rdx, r10
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; 8-bit case: 0x80 /extension
            IF byte [r10 + OPERAND_size], e, 8
                ; AL takes the one-byte accumulator form (base + 3), no ModRM
                IF byte [r10 + OPERAND_reg], e, REG_RAX
                IF byte [r10 + OPERAND_is_high], e, 0
                    mov rax, r13
                    add al, 3
                    call amd64_emit_byte
                    lea     r11, [r12 + INST_op1]
                    mov rax, [r11 + OPERAND_imm]
                    call amd64_emit_byte
                    jmp .done
                    ENDIF
                    ENDIF
                mov al, 0x80
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov al, 0xC0
                mov cl, r14b
                shl cl, 3
                or al, cl
                mov cl, [r10 + OPERAND_reg]
                and cl, 0x07
                or al, cl
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov rax, [r11 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
            
            ; 16/32/64-bit: the sign-extended imm8 form (0x83) as
            ; amd64_imm_canon chose it, else for a value that is a signed byte
            extern  amd64_imm_sb
            cmp     byte [rel amd64_imm_sb], 2
            je      .long_imm
            cmp     byte [rel amd64_imm_sb], 1
            je      .short_imm
            mov     rax, [r11 + OPERAND_imm]
            cmp     rax, -128
            jl      .long_imm
            cmp     rax, 127
            jg      .long_imm
.short_imm:
            mov     al, 0x83
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; ModR/M: 11
            ; extension
            ; dest
            mov     al, 0xC0
            mov     cl, r14b
            shl     cl, 3
            or      al, cl
            mov     cl, [r10 + OPERAND_reg]
            and     cl, 0x07
            or      al, cl
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     rax, [r11 + OPERAND_imm]
            call    amd64_emit_byte
            jmp     .done

.long_imm:
            ; rAX takes the one-byte accumulator form (base + 4) with no
            ; ModRM byte. It is only shorter than 0x81 /digit, never than the
            ; sign-extended 0x83 form handled above.
            lea     r10, [r12 + INST_op0]
            IF byte [r10 + OPERAND_reg], e, REG_RAX
                mov     rax, r13
                add     al, 4
                call    amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov     rdi, [r11 + OPERAND_imm]
                IF byte [r10 + OPERAND_size], e, 16
                    call    amd64_emit_word
                    jmp     .done
                    ENDIF
                call    amd64_emit_dword
                jmp     .done
                ENDIF

            mov     al, 0x81
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; ModR/M: 11
            ; extension
            ; dest
            mov     al, 0xC0
            mov     cl, r14b       ; Extension digit
            shl     cl, 3
            or      al, cl
            mov     cl, [r10 + OPERAND_reg]
            and     cl, 0x07
            or      al, cl
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     rdi, [r11 + OPERAND_imm]
            ; A 16-bit destination takes an imm16; 32- and 64-bit both take
            ; an imm32 (sign-extended for the 64-bit form).
            IF byte [r10 + OPERAND_size], e, 16
                call    amd64_emit_word
                jmp     .done
                ENDIF
            call    amd64_emit_dword
            jmp     .done
            ENDIF

        ; Case 3: r, m
        IF byte [r11 + OPERAND_kind], e, OP_MEM
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            mov     rsi, r10           ; Reg (Src for ModRM)
            mov     rdx, r11           ; Mem (Dest for ModRM)
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Table holds the 16/32/64-bit opcode; reg,mem form is Base + 2
            mov     rax, r13
            add al, 2
            IF byte [r10 + OPERAND_size], e, 8
                dec al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     al, [r10 + OPERAND_reg]
            mov     rdi, r11
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
            ENDIF

    ; Case 4: m, r
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        IF byte [r11 + OPERAND_kind], e, OP_REG
            ; Smart Prefixes
            mov     al, [r11 + OPERAND_size]
            mov     rsi, r11           ; Reg
            mov     rdx, r10           ; Mem
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Table holds the 16/32/64-bit opcode; 8-bit form is Base - 1
            mov     rax, r13
            IF byte [r11 + OPERAND_size], e, 8
                dec al
                ENDIF
            call    amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            mov     al, [r11 + OPERAND_reg]
            mov     rdi, r10
            call    amd64_emit_modrm_sib
            jmp     .done
            ENDIF
        
        ; Case 5: m, imm
        IF byte [r11 + OPERAND_kind], e, OP_IMM
            ; Smart Prefixes
            mov     al, [r10 + OPERAND_size]
            xor     rsi, rsi
            mov     rdx, r10
            call    amd64_emit_prefixes
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            
            ; Logic similar to Case 2 (0x81/0x83) but with memory
            ; 8-bit case: 0x80 /extension
            IF byte [r10 + OPERAND_size], e, 8
                mov al, 0x80
                call amd64_emit_byte
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov al, r14b
                mov rdi, r10
                call amd64_emit_modrm_sib
                lea     r10, [r12 + INST_op0]
                lea     r11, [r12 + INST_op1]
                mov rax, [r11 + OPERAND_imm]
                call amd64_emit_byte
                jmp .done
                ENDIF
            
            ; 16/32/64-bit: 0x83 /n ib as for a register
            cmp     byte [rel amd64_imm_sb], 2
            je      .mem_long
            cmp     byte [rel amd64_imm_sb], 1
            je      .mem_short
            mov     rax, [r11 + OPERAND_imm]
            cmp     rax, -128
            jl      .mem_long
            cmp     rax, 127
            jg      .mem_long
.mem_short:
            mov al, 0x83
            call amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov al, r14b
            mov rdi, r10
            call amd64_emit_modrm_sib
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov rax, [r11 + OPERAND_imm]
            call amd64_emit_byte
            jmp .done
.mem_long:
            mov al, 0x81
            call amd64_emit_byte
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov al, r14b
            mov rdi, r10
            call amd64_emit_modrm_sib
            lea     r10, [r12 + INST_op0]
            lea     r11, [r12 + INST_op1]
            mov rdi, [r11 + OPERAND_imm]
            ; A 16-bit destination takes an imm16, wider ones an imm32
            IF byte [r10 + OPERAND_size], e, 16
                call    amd64_emit_word
                jmp     .done
                ENDIF
            call amd64_emit_dword
            jmp .done
            ENDIF
            ENDIF

.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_syscall]
; ;
amd64_encode_syscall:
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x05
    call amd64_emit_byte
    ret

;*
; * [amd64_encode_sysret]
; ;
amd64_encode_sysret:
    mov     al, 0x48
    call amd64_emit_byte
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x07
    call amd64_emit_byte
    ret

;*
; * [amd64_encode_xchg]
; * XCHG r/m, reg. A 16/32/64-bit exchange with the accumulator has the
; * one-byte 90+r form; everything else is 86 /r (8-bit) or 87 /r.
; ;
amd64_encode_xchg:
    prologue
    cmp     byte [r12 + INST_nops], 2
    jne     .error

    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]

    IF byte [r10 + OPERAND_kind], ne, OP_REG
        jmp .rm_form                       ; memory destination
        ENDIF
    IF byte [r11 + OPERAND_kind], ne, OP_REG
        jmp .rm_form                       ; memory source
        ENDIF
    IF byte [r10 + OPERAND_size], e, 8
        jmp .rm_form                       ; no short form for bytes
        ENDIF

    ; xchg eax, eax is not 90: that is nop, which would not clear the upper
    ; half of rax. NASM encodes it 87 C0.
    cmp     byte [r10 + OPERAND_size], 32
    jne     .not_eax_eax
    cmp     byte [r10 + OPERAND_reg], REG_RAX
    jne     .not_eax_eax
    cmp     byte [r11 + OPERAND_reg], REG_RAX
    je      .rm_form
.not_eax_eax:

    ; Accumulator short form: whichever operand is rAX names the opcode,
    ; the other supplies the low three bits.
    IF byte [r10 + OPERAND_reg], e, REG_RAX
        mov     r15, r11
        jmp     .short_form
        ENDIF
    IF byte [r11 + OPERAND_reg], e, REG_RAX
        mov     r15, r10
        jmp     .short_form
        ENDIF
    jmp     .rm_form

.short_form:
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r15
    call    amd64_emit_prefixes

    mov     al, 0x90
    mov     cl, [r15 + OPERAND_reg]
    and     cl, 0x07
    add     al, cl
    call    amd64_emit_byte
    jmp     .done

.rm_form:
    ; The register operand goes in ModRM.reg; the other becomes r/m. When both
    ; are registers op1 takes the reg field, which is what NASM emits
    ; ("xchg bl, r9b" is 44 86 CB).
    lea     r10, [r12 + INST_op0]
    lea     r11, [r12 + INST_op1]
    IF byte [r11 + OPERAND_kind], e, OP_REG
        mov     r14, r11                   ; r14 = ModRM.reg operand
        mov     r15, r10                   ; r15 = r/m operand
        ELSE
        mov     r14, r10
        mov     r15, r11
        ENDIF

    IF byte [r14 + OPERAND_kind], ne, OP_REG
        jmp .error                         ; memory-to-memory is not encodable
        ENDIF

    mov     al, [r14 + OPERAND_size]
    mov     rsi, r14
    mov     rdx, r15
    call    amd64_emit_prefixes

    mov     al, 0x87
    IF byte [r14 + OPERAND_size], e, 8
        mov al, 0x86
        ENDIF
    call    amd64_emit_byte

    mov     al, [r14 + OPERAND_reg]
    mov     rdi, r15
    call    amd64_emit_modrm_sib
    jmp     .done

.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_push]
; ;
amd64_encode_push:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_size], e, 32
        jmp .error
    ENDIF 

    ; Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    lea     r10, [r12 + INST_op0]  ; emit_prefixes clobbers r10

    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, 0x50
        mov cl, [r10 + OPERAND_reg]
        and cl, 0x07
        add al, cl
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        mov     al, 0xFF
        call amd64_emit_byte
        mov     al, 6
        mov rdi, r10
        call amd64_emit_modrm_sib
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_SYMBOL
        ; push label: 68 id, R_X86_64_32S
        mov     al, 0x68
        call    amd64_emit_byte
        mov     rdi, rbx
        mov     rsi, [rbx + ASMCTX_curr_sec]
        mov     rsi, [rsi + SECTION_size]
        lea     r10, [r12 + INST_op0]
        mov     rdx, [r10 + OPERAND_sym]
        mov     rcx, [r10 + OPERAND_imm]
        mov     r8, R_X86_64_32S
        cmp     byte [r10 + OPERAND_pcrel], 0
        je      .push_abs
        mov     r8, R_X86_64_PC32          ; "push x - $", x elsewhere
        add     rcx, rsi
.push_abs:
        call    reloc_record
        xor     edi, edi
        call    amd64_emit_dword
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_IMM
        ; "push word 5": 66 (above) 6A ib / 68 iw
        mov     rax, [r10 + OPERAND_imm]
        ; 6A ib as amd64_imm_canon chose it ("push byte x"; not for
        ; "push strict dword 5" or -O0), else for a signed byte
        cmp     byte [rel amd64_imm_sb], 2
        je      .push_imm32
        cmp     byte [rel amd64_imm_sb], 1
        je      .push_byte
        cmp     rax, -128
        jl      .push_imm32
        cmp     rax, 127
        jg      .push_imm32
.push_byte:
        mov     al, 0x6A
        call    amd64_emit_byte
        mov     rax, [r10 + OPERAND_imm]
        call    amd64_emit_byte
        jmp     .done
.push_imm32:
        mov     al, 0x68
        call    amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov     rdi, [r10 + OPERAND_imm]
        cmp     byte [r10 + OPERAND_size], 16
        jne     .push_dword
        call    amd64_emit_word
        jmp     .done
.push_dword:
        call    amd64_emit_dword
        jmp     .done
        ENDIF
    jmp     .error
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

amd64_encode_pop:
    prologue
    lea     r10, [r12 + INST_op0]
    IF byte [r10 + OPERAND_size], e, 32
        jmp .error
    ENDIF 

    ; Prefixes
    mov     al, [r10 + OPERAND_size]
    xor     rsi, rsi
    mov     rdx, r10
    call    amd64_emit_prefixes
    lea     r10, [r12 + INST_op0]  ; emit_prefixes clobbers r10

    IF byte [r10 + OPERAND_kind], e, OP_REG
        mov     al, 0x58
        mov cl, [r10 + OPERAND_reg]
        and cl, 0x07
        add al, cl
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    IF byte [r10 + OPERAND_kind], e, OP_MEM
        mov     al, 0x8F
        call amd64_emit_byte
        mov     al, 0
        mov rdi, r10
        call amd64_emit_modrm_sib
        jmp     .done
        ENDIF
    jmp     .error
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_branch]
; * Input: R13 = Opcode for REL32 form
; ;
amd64_encode_branch:
    prologue
    lea     r10, [r12 + INST_op0]
    
    ; Case 1: Symbol (REL32)
    IF qword [r10 + OPERAND_sym], ne, 0
        mov     al, r13b
        call    amd64_emit_byte
        lea     r10, [r12 + INST_op0]
        mov     rsi, [r10 + OPERAND_sym]
        mov     rcx, 4             ; rel32 ends the instruction
        mov     al, RELOC_REL32
        call    amd64_emit_branch_disp
        jmp     .done
        ENDIF
    
    ; Case 2: Register or Memory (FF /digit)
    ; CALL = FF /2, JMP = FF /4
    mov     al, 0xFF
    call    amd64_emit_byte
    
    mov     al, 2               ; Default to CALL extension
    IF r13b, e, 0xE9            ; If it was JMP (E9)
        mov al, 4               ; Use JMP extension
        ENDIF
    
    mov     rdi, r10
    call    amd64_emit_modrm_sib
    jmp     .done
.error:
    mov     rax, EXIT_ENCODE_FAIL
.done:
    epilogue

;*
; * [amd64_encode_ret]
; ;
amd64_encode_ret:
    prologue
    cmp     byte [r12 + INST_nops], 0
    IF e
        mov     al, 0xC3
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    
    ; RET imm16 (0xC2)
    mov     al, 0xC2
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rdi, [r10 + OPERAND_imm]   ; emit_word takes its value in RDI
    call    amd64_emit_word
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_jcc]
; ;
amd64_encode_jcc:
    prologue
    ; Pick the 2-byte form (7x rel8) or the 6-byte form (0F 8x rel32):
    ;   jcc short label       always rel8 (the user asked for it)
    ;   jcc near/strict label always rel32
    ;   jcc label             rel8 if the target is a backward local label
    ;                         already within reach, else rel32
    lea     r10, [r12 + INST_op0]
    test    byte [r10 + OPERAND_flags], OP_FLAG_SHORT
    jnz     .short
    test    byte [r10 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .near
    ; -O0: short unless strict, as NASM 3 - "near" and a size too ("jz
    ; word x" is 66 7x; the 8086's only jcc)
    cmp     byte [rbx + ASMCTX_opt], OPT_NONE
    je      .short

    ; "jz word x" / "jz near x": GNU's syntax keeps it near; NASM 3 makes
    ; it short where it reaches, its 66 kept (amd64_branch_size_first)
    call    amd64_branch_size_first
    jnz     .near_emit
    mov     rsi, [r10 + OPERAND_sym]
    call    amd64_branch_fits_rel8
    test    eax, eax
    jz      .near
.short:
    call    amd64_branch_osize_once        ; (66 for "jz word x" in bits 32)
    mov     byte [rel amd64_branch_width], 0   ; (rel8 all the same)
    call    amd64_encode_jcc_short
    jmp     .done

.near:
    ; A rel32 jcc to a label not yet defined may be shortened later by
    ; src/optimize/jump.s - unless the user wrote near/strict.
    test    byte [r10 + OPERAND_flags], OP_FLAG_STRICT
    jnz     .near_emit
    mov     byte [rel amd64_relax_kind], RELAX_JCC
.near_emit:
    mov     ax, [r12 + INST_op_id]

    ; Extract condition code from ID (3000-3031)
    sub     ax, 3000
    and     rax, 0x0F          ; Get CC bits
    mov     r14, rax
    mov     [rel amd64_relax_cc], al

    call    amd64_branch_osize_once        ; (66 for "jz word x" in bits 32)
    mov     al, 0x0F
    call amd64_emit_byte
    mov     al, 0x80
    add al, r14b
    call amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 4                 ; rel32 ends the instruction
    mov     al, RELOC_REL32
    call    amd64_emit_branch_disp
.done:
    epilogue

;*
; * [amd64_encode_branch_short]
; * R13 = Opcode (0xEB for JMP, etc)
; ;
amd64_encode_branch_short:
    prologue
    mov     al, r13b
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 1                 ; rel8 ends the instruction
    mov     al, RELOC_REL8
    call    amd64_emit_branch_disp
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_jcc_short]
; ;
amd64_encode_jcc_short:
    prologue
    mov     ax, [r12 + INST_op_id]
    sub     ax, 3000
    and     rax, 0x0F
    add     al, 0x70           ; 0x70 = JO short, 0x74 = JE short
    call    amd64_emit_byte
    
    lea     r10, [r12 + INST_op0]
    mov     rsi, [r10 + OPERAND_sym]
    mov     rcx, 1                 ; rel8 ends the instruction
    mov     al, RELOC_REL8
    call    amd64_emit_branch_disp
    jmp     .done
.done:
    epilogue

;*
; * [amd64_encode_retf]
; * RETF: CB, or CA iw with a count to pop (RETFQ puts REX.W before it).
; ;
amd64_encode_retf:
    prologue
    cmp     byte [r12 + INST_nops], 0
    IF e
        mov     al, 0xCB
        call    amd64_emit_byte
        jmp     .done
        ENDIF
    mov     al, 0xCA
    call    amd64_emit_byte
    lea     r10, [r12 + INST_op0]
    mov     rdi, [r10 + OPERAND_imm]
    call    amd64_emit_word
.done:
    epilogue
