;
; ============================================
; File     : optimizer/align.s
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
; ALIGN PADDING
; ============================================================================
; What "align N" writes. Without a fill operand it is one byte repeated:
; nop (0x90), in data sections too (NASM's align is times n nop).
; "%use smartalign" (NASM's package) makes it long NOPs instead, chosen by
; "alignmode":
;
;   nop       0x90 bytes
;   generic   lea/mov forms that do nothing (bits 16/32), 66-prefixed nops
;             (bits 64) - the default
;   k8, k7    AMD's 66-prefixed nops (k7: lea forms in bits 32)
;   p6        0F 1F /0 multi-byte nops
;
; padding longer than the mode's threshold (8 for generic, 16 otherwise;
; "alignmode MODE, nojmp" never) is jumped over: jmp to its end, then
; nops. Every byte follows from the padding's length, the mode and bits,
; so optimizer/jump.s regenerates it when moving code changes the length.
;
; A padding's fill is described by a FILL SPEC (a qword, kept in the
; relaxation record):
;   0x100 | byte                  that byte repeated
;   0x200 | mode<<16 | bits<<24 | threshold<<32
;                                 smartalign (threshold -1: no jump)

%define SA_NOP       1
%define SA_GENERIC   2
%define SA_K8        3
%define SA_K7        4
%define SA_P6        5

[SECTION .data]
align 4
global smartalign_mode, smartalign_jmp
smartalign_mode:    db 0                ; SA_*, 0 until %use smartalign
                    db 0, 0, 0
smartalign_jmp:     dd 8                ; the jump threshold, -1: nojmp

; ---- the NOP tables ----------------------
; One per mode and bits: the group size G, then the patterns of 1, 2 .. G
; bytes. Padding is as many G-byte patterns as fit, then one for the rest.
sa_nop:      db 1, 0x90
sa_gen16:    db 8, 0x90, 0x89,0xf6, 0x8d,0x74,0x00, 0x8d,0xb4,0x00,0x00
             db 0x8d,0xb4,0x00,0x00,0x90, 0x8d,0xb4,0x00,0x00,0x89,0xff
             db 0x8d,0xb4,0x00,0x00,0x8d,0x7d,0x00
             db 0x8d,0xb4,0x00,0x00,0x8d,0xbd,0x00,0x00
sa_gen32:    db 7, 0x90, 0x89,0xf6, 0x8d,0x76,0x00, 0x8d,0x74,0x26,0x00
             db 0x90,0x8d,0x74,0x26,0x00, 0x8d,0xb6,0x00,0x00,0x00,0x00
             db 0x8d,0xb4,0x26,0x00,0x00,0x00,0x00
sa_66:       db 4, 0x90, 0x66,0x90, 0x66,0x66,0x90, 0x66,0x66,0x66,0x90
; k7 in bits 16: NASM's package sets only the 1-4 byte forms and leaves
; the group (8) and the 5-8 byte forms of generic
sa_k7_16:    db 8, 0x90, 0x66,0x90, 0x66,0x66,0x90, 0x66,0x66,0x66,0x90
             db 0x8d,0xb4,0x00,0x00,0x90, 0x8d,0xb4,0x00,0x00,0x89,0xff
             db 0x8d,0xb4,0x00,0x00,0x8d,0x7d,0x00
             db 0x8d,0xb4,0x00,0x00,0x8d,0xbd,0x00,0x00
sa_k7_32:    db 7, 0x90, 0x8b,0xc0, 0x8d,0x04,0x20, 0x8d,0x44,0x20,0x00
             db 0x8d,0x44,0x20,0x00,0x90, 0x8d,0x80,0x00,0x00,0x00,0x00
             db 0x8d,0x04,0x05,0x00,0x00,0x00,0x00
sa_p6_16:    db 4, 0x90, 0x66,0x90, 0x0f,0x1f,0x00, 0x0f,0x1f,0x40,0x00
sa_p6:       db 8, 0x90, 0x66,0x90, 0x0f,0x1f,0x00, 0x0f,0x1f,0x40,0x00
             db 0x0f,0x1f,0x44,0x00,0x00, 0x66,0x0f,0x1f,0x44,0x00,0x00
             db 0x0f,0x1f,0x80,0x00,0x00,0x00,0x00
             db 0x0f,0x1f,0x84,0x00,0x00,0x00,0x00,0x00

align 8
; [mode - 1][bits 16, 32, 64]
sa_tables:   dq sa_nop, sa_nop, sa_nop
             dq sa_gen16, sa_gen32, sa_66
             dq sa_66, sa_66, sa_66
             dq sa_k7_16, sa_k7_32, sa_66
             dq sa_p6_16, sa_p6, sa_p6

; alignmode's names: 7 bytes, mode, default threshold (dword)
sa_modes:    db "nop", 0, 0, 0, 0, SA_NOP
             dd 16
             db "generic", SA_GENERIC
             dd 8
             db "k8", 0, 0, 0, 0, 0, SA_K8
             dd 16
             db "k7", 0, 0, 0, 0, 0, SA_K7
             dd 16
             db "p6", 0, 0, 0, 0, 0, SA_P6
             dd 16
             db 0

[SECTION .text]

; ---- align_fill_spec ---------------------
;
; align_fill_spec
; The fill spec for an "align" without a fill operand at this point.
; Input    : rdi = AsmCtx, rsi = SECTION
; Output   : rax = fill spec
;
global align_fill_spec
align_fill_spec:
    cmp     byte [rdi + ASMCTX_target], TARGET_AMD64
    jne     .zero
    movzx   eax, byte [rel smartalign_mode]
    test    eax, eax
    jz      .plain
    extern  asm_bits
    movzx   ecx, byte [rel asm_bits]
    shl     ecx, 24
    shl     eax, 16
    or      eax, ecx
    or      eax, 0x200
    movsxd  rcx, dword [rel smartalign_jmp]
    shl     rcx, 32
    or      rax, rcx
    ret
.plain:
    ; nop in every section, as NASM's align (times n nop) writes it; a
    ; nobits section only reserves the space
    mov     eax, 0x100 | 0x90
    ret
.zero:
    cmp     byte [rdi + ASMCTX_target], TARGET_RISCV64
    jne     .zero_fill
    cmp     byte [rsi + SECTION_type], SEC_TEXT
    jne     .zero_fill
    mov     eax, 0x100 | 0x13              ; as before for RISC-V code
    ret
.zero_fill:
    mov     eax, 0x100                     ; 0 elsewhere
    ret

; ---- align_fill --------------------------
;
; align_fill
; Writes a padding's bytes.
; Input    : rdi = destination, rsi = length, rdx = fill spec
; Output   : rax = the first byte after them
; Clobbers : rcx, rdx, rsi, r8-r11
;
global align_fill
align_fill:
    test    edx, 0x200
    jnz     .smart
    mov     eax, edx
    mov     rcx, rsi
    rep stosb
    mov     rax, rdi
    ret

.smart:
    mov     r8, rdx
    sar     r8, 32                         ; threshold
    cmp     r8, -1
    je      .nops
    cmp     rsi, r8
    jle     .nops
    ; jump over it: jmp short / near to its end, then nop
    lea     rcx, [rsi - 2]
    cmp     rcx, 127
    ja      .near
    mov     byte [rdi], 0xEB
    mov     [rdi + 1], cl
    add     rdi, 2
    jmp     .tail
.near:
    mov     byte [rdi], 0xE9
    mov     eax, edx
    shr     eax, 24
    cmp     al, 16
    je      .near16
    lea     rcx, [rsi - 5]
    mov     [rdi + 1], ecx
    add     rdi, 5
    jmp     .tail
.near16:
    lea     rcx, [rsi - 3]
    mov     [rdi + 1], cx
    add     rdi, 3
.tail:
    mov     al, 0x90
    rep stosb
    mov     rax, rdi
    ret

.nops:
    ; the table for the mode and bits
    mov     eax, edx
    shr     eax, 16
    movzx   eax, al
    dec     eax
    imul    eax, eax, 3
    mov     ecx, edx
    shr     ecx, 24
    movzx   ecx, cl
    xor     r9d, r9d                       ; bits 16
    cmp     ecx, 32
    jne     .not32
    mov     r9d, 1
.not32:
    cmp     ecx, 64
    jne     .bits
    mov     r9d, 2
.bits:
    add     eax, r9d
    lea     r10, [rel sa_tables]
    mov     r10, [r10 + rax*8]             ; r10 = table
    movzx   r11d, byte [r10]               ; r11 = group
.group:
    cmp     rsi, r11
    jb      .rest
    mov     rcx, r11
    call    .pattern
    sub     rsi, r11
    jmp     .group
.rest:
    test    rsi, rsi
    jz      .done
    mov     rcx, rsi
    call    .pattern
.done:
    mov     rax, rdi
    ret

    ; copies the rcx-byte pattern: it starts at 1 + rcx*(rcx-1)/2
.pattern:
    push    rsi
    lea     rax, [rcx - 1]
    imul    rax, rcx
    shr     rax, 1
    lea     rsi, [r10 + rax + 1]
    rep movsb
    pop     rsi
    ret

; ---- align_mode_directive ----------------
;
; align_mode_directive
; "alignmode MODE [, threshold | nojmp]" (with %use smartalign).
; Input    : rdi = the mode's name, rsi = 0 (no threshold), 1 (nojmp) or
;            2 (rdx = the threshold)
; Output   : rax = EXIT_OK, or EXIT_ALIGN_MODE for an unknown mode
;
global align_mode_directive
align_mode_directive:
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    mov     r13, rdx
    lea     rbx, [rel sa_modes]
.mode:
    cmp     byte [rbx], 0
    je      .unknown
    ; compare, ignoring case, with the 7-byte name
    xor     ecx, ecx
.ch:
    movzx   eax, byte [rdi + rcx]
    cmp     al, 'A'
    jb      .lower
    cmp     al, 'Z'
    ja      .lower
    or      al, 0x20
.lower:
    cmp     ecx, 7
    je      .end7
    cmp     al, [rbx + rcx]
    jne     .next
    test    al, al
    jz      .hit
    inc     ecx
    jmp     .ch
.end7:
    test    al, al
    jz      .hit
.next:
    add     rbx, 12
    jmp     .mode
.hit:
    movzx   eax, byte [rbx + 7]
    mov     [rel smartalign_mode], al
    mov     eax, [rbx + 8]
    cmp     r12, 1
    jne     .not_nojmp
    mov     eax, -1
.not_nojmp:
    cmp     r12, 2
    jne     .set
    mov     eax, r13d
.set:
    mov     [rel smartalign_jmp], eax
    xor     eax, eax
    jmp     .ret
.unknown:
    mov     eax, EXIT_ALIGN_MODE
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret
