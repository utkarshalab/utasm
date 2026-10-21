;
; ============================================================================
; File        : src/link/script.s
; Project     : utasm
; Description : Linker Script Parser. 
; ============================================================================
;

%include "src/include/constant.inc"
%include "src/include/type.inc"
%include "src/include/macro.inc"

extern lexer_init
extern lexer_next

[SECTION .text]

;*
; * [linker_script_parse]
; * Purpose: Parses a .ld script to configure the linker's memory map.
; ;
global linker_script_parse
linker_script_parse:
    prologue
    push    rbx
    mov     rbx, rdi               ; RBX = AsmCtx
    
    ; 1. Initialize Lexer on the script buffer
    ; ...
    
    ; 2. Parse Loop (Stub for basic ORG support)
    ; Most kernel scripts just need to define the base address.
    
    pop     rbx
    epilogue
