;
; ============================================================================
; File        : src/linker/linker.s
; Project     : utasm
; Description : Main Linker Orchestrator. Coordinates relocations, symbol 
;                resolution, and final file emission.
; ============================================================================
;

%include "include/constant.inc"
%include "include/type.inc"
%include "include/macro.inc"

extern binary_emit
extern elf64_emit
extern reloc_resolve_all
extern error_emit
extern io_open
extern io_close

[SECTION .text]

;*
; * [linker_run]
; * Purpose: The main entry point for the linking stage.
; * Input:
; *   RDI: Pointer to AsmCtx
; * Output:
; *   RAX: EXIT_OK or error code
; ;
global linker_run
linker_run:
    prologue
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi               ; RBX = AsmCtx

    ; 0. Shorten forward jumps now that every label is known (moves code,
    ;    so it must run before relocations are resolved)
    extern  relax_run
    mov     rdi, rbx
    call    relax_run

    ; 1. Resolve all relocations
    extern  global_profstate
    extern  profiler_start_phase
    extern  profiler_end_phase
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_LINKER
    call    profiler_start_phase

    mov     rdi, rbx
    call    reloc_resolve_all

    push    rax
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_LINKER
    call    profiler_end_phase
    pop     rax
    check_err

    ; 1.5 Check for section overlaps
    ; Only meaningful once VAs are assigned; in a relocatable object every
    ; section sits at address 0 and would trivially "overlap".
    IF byte [rbx + ASMCTX_standalone], e, 1
        mov     rdi, rbx
        call    linker_check_overlaps
        check_err
        ENDIF

    ; 1.6 Open Output File
    mov     rdi, [rbx + ASMCTX_output]
    test    rdi, rdi
    jz      .error_no_output

    mov     rsi, AMD64_O_WRONLY | AMD64_O_CREAT | AMD64_O_TRUNC
    mov     rdx, 0o644
    call    io_open
    check_err
    mov     r12, rdx               ; r12 = FD

    ; 2. Determine output format.  The CLI stores the authoritative FMT_*
    ; enum in ASMCTX_fmt; the old CTX_FLAG_FORMAT_* bits are compatibility
    ; state only.  Reading the flags here made `-f bin` silently emit ELF.
    movzx   eax, byte [rbx + ASMCTX_fmt]
    cmp     eax, FMT_BIN
    je      .emit_binary
    cmp     eax, FMT_ELF64
    je      .emit_elf
    mov     rax, EXIT_USAGE
    jmp     .close_and_done

.emit_binary:
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_OUTPUT
    call    profiler_start_phase
    mov     rdi, rbx
    mov     rsi, r12
    xor     rdx, rdx
    call    binary_emit
    mov     r13, rax
    jmp     .end_output_phase

.emit_elf:
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_OUTPUT
    call    profiler_start_phase
    mov     rdi, rbx
    mov     rsi, r12
    call    elf64_emit
    mov     r13, rax

.end_output_phase:
    lea     rdi, [rel global_profstate]
    mov     rsi, PHASE_OUTPUT
    call    profiler_end_phase

.close_and_done:
    mov     rdi, r12
    call    io_close
    mov     rax, r13
    check_err
    jmp     .done

.error_no_output:
    mov     rax, EXIT_FILE_WRITE

.error:
.done:
    pop     r13
    pop     r12
    pop     rbx
    epilogue

;*
; * [linker_check_overlaps]
; * Input: RDI = AsmCtx
; * Checks all section VA ranges for intersections.
; ;
linker_check_overlaps:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi               ; RBX = AsmCtx
    mov     r12, [rbx + ASMCTX_sections]
    mov     r13d, [rbx + ASMCTX_seccount]
    
    xor     r14, r14               ; i = 0
.outer:
    cmp     r14d, r13d
    jge     .done
    
    mov     rax, r14
    shl     rax, 3
    mov     r10, [r12 + rax]       ; r10 = Section[i]
    
    ; Check if empty or NOBITS
    cmp     qword [r10 + SECTION_size], 0
    je      .next_i
    
    mov     r15, r14
    inc     r15                    ; j = i + 1
.inner:
    cmp     r15d, r13d
    jge     .next_i
    
    mov     rax, r15
    shl     rax, 3
    mov     r11, [r12 + rax]       ; r11 = Section[j]
    
    cmp     qword [r11 + SECTION_size], 0
    je      .next_j

    ; Overlap if (A.start < B.end) && (B.start < A.end)
    ; A.start = r10.addr
    ; A.end   = r10.addr + r10.size
    ; B.start = r11.addr
    ; B.end   = r11.addr + r11.size
    
    mov     rax, [r10 + SECTION_addr]
    mov     rdx, rax
    add     rdx, [r10 + SECTION_size] ; rdx = A.end
    
    mov     rcx, [r11 + SECTION_addr]
    mov     r8,  rcx
    add     r8,  [r11 + SECTION_size] ; r8 = B.end
    
    ; (A.start < B.end)
    cmp     rax, r8
    jge     .next_j
    
    ; (B.start < A.end)
    cmp     rcx, rdx
    jge     .next_j
    
    ; OVERLAP DETECTED
    mov     rax, EXIT_SECTION_OVERLAP
    jmp     .ret

.next_j:
    inc     r15
    jmp     .inner
    
.next_i:
    inc     r14
    jmp     .outer

.done:
.error:
    xor     rax, rax
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
