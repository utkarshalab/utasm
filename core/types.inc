%ifndef CORE_TYPES_INC
%define CORE_TYPES_INC

;
; ============================================================================
; File     : core/types.inc
; Project  : utasm
; Author   : UtkarshaLab
; License  : Apache-2.0
; Description: Canonical struct definitions for all utasm phases.
;              This is the single most important file — every module
;              depends on it.  Do NOT add code here.  Data definitions only.
; ============================================================================
;

%include "include/macro.inc"

; ============================================================================
; Severity constants (ErrorRecord.severity)
; ============================================================================

SEV_ERROR   equ 0
SEV_WARNING equ 1
SEV_NOTE    equ 2
SEV_HINT    equ 3

; ============================================================================
; Token type enum (Token.type)
; ============================================================================

TOK_EOF         equ 0
TOK_IDENT       equ 1    ; identifier / mnemonic / keyword
TOK_INT         equ 2    ; integer literal
TOK_FLOAT       equ 3    ; float literal
TOK_STRING      equ 4    ; "..." string literal
TOK_CHAR        equ 5    ; '.' character literal
TOK_LABEL       equ 6    ; label definition (ends with ':')
TOK_LOCAL_LABEL equ 7    ; .local_label
TOK_DIRECTIVE   equ 8    ; %define / %macro / SECTION / etc.
TOK_REGISTER    equ 9    ; register name (rax, xmm0, ...)
TOK_COMMA       equ 10
TOK_COLON       equ 11
TOK_LPAREN      equ 12
TOK_RPAREN      equ 13
TOK_LBRACKET    equ 14
TOK_RBRACKET    equ 15
TOK_PLUS        equ 16
TOK_MINUS       equ 17
TOK_STAR        equ 18
TOK_SLASH       equ 19
TOK_PERCENT     equ 20
TOK_AMP         equ 21
TOK_PIPE        equ 22
TOK_CARET       equ 23
TOK_TILDE       equ 24
TOK_LSHIFT      equ 25
TOK_RSHIFT      equ 26
TOK_EQ          equ 27
TOK_NEQ         equ 28
TOK_LT          equ 29
TOK_GT          equ 30
TOK_NEWLINE     equ 31
TOK_COMMENT     equ 32

; ============================================================================
; Token flags (Token.flags)
; ============================================================================

TOK_FLAG_MACRO_EXPANDED equ 0x0001   ; token came from macro expansion
TOK_FLAG_SIGNED         equ 0x0002   ; integer literal is signed
TOK_FLAG_HEX            equ 0x0004   ; integer was in hex notation
TOK_FLAG_BIN            equ 0x0008   ; integer was in binary notation
TOK_FLAG_OCT            equ 0x0010   ; integer was in octal notation

; ============================================================================
; STRUCT: Token — source map fields are mandatory
; ============================================================================
;
;  Token.type      dw  — token type (TOK_*)
;  Token.flags     dw  — token flags (TOK_FLAG_*)
;  Token.pad0      dd  — alignment pad before .value
;  Token.value     dq  — numeric value or pointer to string data
;  Token.file_id   dw  — index into file registry
;  Token.pad1      dw  — alignment pad before .line
;  Token.line      dd  — 1-based source line number
;  Token.col_start dw  — 1-based column start (inclusive)
;  Token.col_end   dw  — 1-based column end (inclusive)
;  Token.macro_id  dw  — 0 = not from macro, else macro chain id
;  Token.length    dw  — length of token text in bytes
;  Token.pad2      dd  — alignment pad before .text_ptr
;  Token.text_ptr  dq  — pointer to token text in source buffer (not owned)
;
;  Total: 40 bytes

struc Token
    field type,      2    ; dw  token type enum (TOK_*)
    field flags,     2    ; dw  token flags (TOK_FLAG_*)
    field pad0,      4    ; dd  alignment padding
    field value,     8    ; dq  numeric value or string ptr
    field file_id,   2    ; dw  index into file registry (0-based)
    field pad1,      2    ; dw  alignment padding
    field line,      4    ; dd  1-based line number
    field col_start, 2    ; dw  1-based column start (inclusive)
    field col_end,   2    ; dw  1-based column end (inclusive)
    field macro_id,  2    ; dw  0 = not from macro, else chain id
    field length,    2    ; dw  token text length in bytes
    field pad2,      4    ; dd  alignment padding
    field text_ptr,  8    ; dq  pointer into source buffer (not owned)
endstruc

; ============================================================================
; STRUCT: ErrorRecord — one record per diagnostic
; ============================================================================
;
;  ErrorRecord.code      dw  — E101–E999 / W101–W999 / N101 / H101
;  ErrorRecord.severity  db  — SEV_ERROR / SEV_WARNING / SEV_NOTE / SEV_HINT
;  ErrorRecord.pad0      db  — alignment pad
;  ErrorRecord.file_id   dw  — source file (index into file registry)
;  ErrorRecord.pad1      dw  — alignment pad before .line
;  ErrorRecord.line      dd  — source line number
;  ErrorRecord.col_start dw  — column start
;  ErrorRecord.col_end   dw  — column end
;  ErrorRecord.msg_idx   dw  — index into message table
;  ErrorRecord.note_idx  dw  — index into note table (0 = none)
;  ErrorRecord.hint_idx  dw  — index into hint table (0 = none)
;  ErrorRecord.chain_id  dw  — macro expansion chain id (0 = none)
;
;  Total: 20 bytes

struc ErrorRecord
    field code,      2    ; dw  error/warning code number
    field severity,  1    ; db  SEV_* constant
    field pad0,      1    ; db  alignment padding
    field file_id,   2    ; dw  source file index
    field pad1,      2    ; dw  alignment padding
    field line,      4    ; dd  source line number
    field col_start, 2    ; dw  column start
    field col_end,   2    ; dw  column end
    field msg_idx,   2    ; dw  message table index
    field note_idx,  2    ; dw  note table index (0 = no note)
    field hint_idx,  2    ; dw  hint table index (0 = no hint)
    field chain_id,  2    ; dw  macro expansion chain id (0 = none)
endstruc

; ============================================================================
; STRUCT: ASTNode — parse tree node
; ============================================================================
;
;  ASTNode.type          dw  — node type (AST_*)
;  ASTNode.flags         dw  — node flags
;  ASTNode.file_id       dw  — source file
;  ASTNode.operand_count dw  — number of operands
;  ASTNode.line          dd  — source line
;  ASTNode.operands      dq  — ptr to operand array (may be null)
;  ASTNode.next          dq  — ptr to next sibling node (null-terminated)
;
;  Total: 24 bytes

struc ASTNode
    field type,          2    ; dw  node type (AST_*)
    field flags,         2    ; dw  node flags
    field file_id,       2    ; dw  source file index
    field operand_count, 2    ; dw  number of operands
    field line,          4    ; dd  source line
    field operands,      8    ; dq  ptr to operand array
    field next,          8    ; dq  ptr to next node (linked list)
endstruc

; ============================================================================
; ASTNode type constants
; ============================================================================

AST_INSTR     equ 0    ; instruction statement
AST_LABEL     equ 1    ; label definition
AST_SECTION   equ 2    ; SECTION directive
AST_DIRECTIVE equ 3    ; other directive
AST_DATA      equ 4    ; DB / DW / DD / DQ
AST_EQU       equ 5    ; EQU constant
AST_STRUCT    equ 6    ; STRUC / ENDSTRUC
AST_PROC      equ 7    ; PROC / ENDP
AST_EXPR      equ 8    ; expression node
AST_MACRO     equ 9    ; macro invocation

; ============================================================================
; STRUCT: ISAEntry — one row in the ISA opcode table
; ============================================================================
;
;  ISAEntry.name_ptr    dq  — pointer to null-terminated mnemonic string
;  ISAEntry.opcode      dd  — primary opcode bytes (little-endian, 0-padded)
;  ISAEntry.opcode_ext  db  — ModRM reg field extension (/0–/7, 0xFF = none)
;  ISAEntry.enc_type    db  — encoding class (ENC_*)
;  ISAEntry.op_type0    db  — operand type 0 (OT_*)
;  ISAEntry.op_type1    db  — operand type 1 (OT_*)
;  ISAEntry.op_type2    db  — operand type 2 (OT_*)
;  ISAEntry.op_type3    db  — operand type 3 (OT_*)
;  ISAEntry.cpu_flags   dd  — CPU feature flags required (CPU_HAS_*)
;  ISAEntry.prefix_req  db  — required prefix (PREFIX_REX/VEX/EVEX, 0=none)
;  ISAEntry.pad0        db  — padding × 3
;  ISAEntry.pad1        dw
;
;  Total: 24 bytes  (3 × 8, cache-friendly)

struc ISAEntry
    field name_ptr,   8    ; dq  pointer to mnemonic string
    field opcode,     4    ; dd  opcode bytes
    field opcode_ext, 1    ; db  /0–/7 or 0xFF
    field enc_type,   1    ; db  encoding class
    field op_type0,   1    ; db  operand type 0
    field op_type1,   1    ; db  operand type 1
    field op_type2,   1    ; db  operand type 2
    field op_type3,   1    ; db  operand type 3
    field cpu_flags,  4    ; dd  required CPU features
    field prefix_req, 1    ; db  required prefix (0 = none)
    field pad0,       3    ; db × 3  alignment padding
endstruc

; ============================================================================
; Encoding class constants (ISAEntry.enc_type)
; ============================================================================

ENC_NONE    equ 0    ; no encoding (pseudo)
ENC_RM      equ 1    ; ModRM r/m
ENC_RMR     equ 2    ; ModRM r, r/m
ENC_RMI     equ 3    ; ModRM r/m + imm
ENC_RI      equ 4    ; reg + imm (short form)
ENC_MI      equ 5    ; ModRM r/m + imm (no reg)
ENC_M       equ 6    ; ModRM r/m only
ENC_I       equ 7    ; immediate only
ENC_O       equ 8    ; opcode + reg (opcode+rd)
ENC_D       equ 9    ; direct branch offset
ENC_VEX     equ 10   ; VEX-encoded
ENC_EVEX    equ 11   ; EVEX-encoded
ENC_NP      equ 12   ; no operands

; ============================================================================
; Operand type constants (ISAEntry.op_typeN)
; ============================================================================

OT_NONE   equ 0    ; no operand in this slot
OT_R8     equ 1    ; 8-bit register
OT_R16    equ 2    ; 16-bit register
OT_R32    equ 3    ; 32-bit register
OT_R64    equ 4    ; 64-bit register
OT_M8     equ 5    ; 8-bit memory
OT_M16    equ 6    ; 16-bit memory
OT_M32    equ 7    ; 32-bit memory
OT_M64    equ 8    ; 64-bit memory
OT_RM8    equ 9    ; r/m 8
OT_RM16   equ 10   ; r/m 16
OT_RM32   equ 11   ; r/m 32
OT_RM64   equ 12   ; r/m 64
OT_IMM8   equ 13   ; 8-bit immediate
OT_IMM16  equ 14   ; 16-bit immediate
OT_IMM32  equ 15   ; 32-bit immediate
OT_IMM64  equ 16   ; 64-bit immediate
OT_REL8   equ 17   ; 8-bit relative offset
OT_REL32  equ 18   ; 32-bit relative offset
OT_XMM    equ 19   ; XMM register
OT_YMM    equ 20   ; YMM register
OT_ZMM    equ 21   ; ZMM register
OT_KMASK  equ 22   ; AVX-512 mask register (k0–k7)
OT_SREG   equ 23   ; segment register

; ============================================================================
; Prefix constants (ISAEntry.prefix_req)
; ============================================================================

PREFIX_NONE equ 0x00
PREFIX_REX  equ 0x01
PREFIX_VEX  equ 0x02
PREFIX_EVEX equ 0x04
PREFIX_LOCK equ 0x08
PREFIX_REP  equ 0x10
PREFIX_REPZ equ 0x20
PREFIX_REPNZ equ 0x40

%endif ; CORE_TYPES_INC
