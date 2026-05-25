;
; ============================================================================
; File        : src/linker/script.s
; Project     : utasm
; Description : Linker Script Parser. 
; ============================================================================
;

%include "include/constant.s"
%include "include/type.s"
%include "include/macro.s"

extern lexer_init
extern lexer_next_token

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
