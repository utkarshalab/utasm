%ifndef TYPE_S
%define TYPE_S

;
; ============================================
; File     : include/type.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Core data struc definitions using automatic offset calculation.
; ============================================
;

%include "include/macro.inc"

%define TOK_COMMENT            0x20

; ============================================================================
; STRUCT: Token
; ============================================================================

struc TOKEN
    field tag,      1       ; always TAG_TOKEN
    field kind,     1       ; TOK_* value
    field flags,    1       ; TOK_FLAG_* values
    field pad0,     5       ; alignment padding
    field value,    8       ; pointer or integer
    field line,     4       ; source line number (1-based)
    field col,      2       ; source column number (1-based)
    field len,      2       ; token text length in bytes
    field file,     8       ; filename pointer
endstruc

; ============================================================================
; STRUCT: Arena
; ============================================================================

struc ARENA
    field tag,      1       ; always TAG_ARENA
    field pad0,     7       ; alignment padding
    field base,     8       ; start of arena memory
    field ptr,      8       ; next free byte pointer
    field end,      8       ; end of arena memory boundary
endstruc

; ============================================================================
; STRUCT: Vec  (lib/vec.s)
; ============================================================================
; Growable array of fixed-size elements, backed by an Arena.
; Growth allocates a new buffer and copies; the old one is abandoned
; (arenas never free individual blocks).

struc VEC
    field tag,       1      ; always TAG_VEC
    field pad0,      3      ; alignment padding
    field elem_size, 4      ; bytes per element (> 0)
    field data,      8      ; pointer to element storage
    field len,       8      ; number of elements in use
    field cap,       8      ; number of elements allocated
    field arena,     8      ; Arena used for (re)allocation
endstruc

; ============================================================================
; STRUCT: List / ListNode  (lib/list.s)
; ============================================================================
; Doubly linked list of 64-bit values (integers or pointers).
; Nodes are allocated from an Arena; removed nodes are not reclaimed.

struc LIST
    field tag,      1       ; always TAG_LIST
    field pad0,     7       ; alignment padding
    field head,     8       ; first LISTNODE or 0
    field tail,     8       ; last LISTNODE or 0
    field count,    8       ; number of nodes
    field arena,    8       ; Arena used for node allocation
endstruc

struc LISTNODE
    field next,     8       ; next node or 0
    field prev,     8       ; previous node or 0
    field value,    8       ; payload
endstruc

; ============================================================================
; STRUCT: FmtBuf  (lib/fmt.s)
; ============================================================================
; Bounded string builder over a caller-supplied buffer. One byte is always
; reserved for the NUL terminator. Writes past capacity are dropped and
; set the truncated flag instead of overflowing.

struc FMTBUF
    field tag,       1      ; always TAG_FMTBUF
    field truncated, 1      ; 1 once any write was dropped
    field pad0,      6      ; alignment padding
    field buf,       8      ; destination buffer
    field len,       8      ; bytes written (excluding NUL)
    field cap,       8      ; buffer size in bytes (including NUL slot)
endstruc

; ============================================================================
; STRUCT: Symbol
; ============================================================================

struc SYMBOL
    field tag,      1       ; always TAG_SYMBOL
    field kind,     1       ; SYM_* value
    field vis,      1       ; VIS_* value
    field pad0,     5       ; alignment padding
    field name,     8       ; pointer to name string
    field value,    8       ; address or constant value
    field size,     8       ; size in bytes
    field section,  4       ; section index
    field name_idx, 4       ; index into .strtab
    field elf_idx,  4       ; final index in ELF .symtab
    field line,     4       ; definition line
    field file,     8       ; definition filename pointer
endstruc

; ============================================================================
; STRUCT: Section
; ============================================================================

struc SECTION
    field tag,      1       ; always TAG_SECTION
    field type,     1       ; SEC_* internal type (was kind)
    field flags,    2       ; SHF_* flags
    field elf_type, 4       ; SHT_* ELF type
    field name,     8       ; pointer to section name
    field data,     8       ; pointer to content buffer
    field size,     8       ; current size in bytes
    field cap,      8       ; buffer capacity in bytes
    field addr,     8       ; virtual address
    field align,    8       ; required alignment boundary
    field index,    4       ; ELF section index
    field group_flags, 4    ; GRP_COMDAT
    field group_sig,   8    ; pointer to signature SYMBOL
    field pad1,        8    ; maintain 16-byte alignment
endstruc

; ============================================================================
; STRUCT: Relocation
; ============================================================================

struc RELOC
    field tag,         1       ; TAG_RELOC
    field pad0,        3       ; explicit padding to align type to 4-byte boundary
    field type,        4       ; RELOC_* value (Arch-specific)
    field offset,      8       ; offset in binary section (8 bytes for ELF64)
    field addend,      8       ; signed addend for RELA
    field sym,         8       ; pointer to symbol name string
    field section,     8       ; pointer to target section
    field pc_adjust,   4       ; adjustment for PC-relative relocs
    field pad1,        4       ; alignment padding (maintains multiple of 8)
endstruc

; ============================================================================
; STRUCT: IncludeCtx
; ============================================================================

struc INCLUDECTX
    field tag,      1       ; always TAG_INCLUDE_CTX
    field depth,    1       ; nesting depth
    field pad0,     6       ; alignment padding
    field file,     8       ; filename pointer
    field parent,   8       ; parent IncludeCtx pointer
    field buf,      8       ; mapped file buffer pointer
    field size,     8       ; file size (for munmap)
    field pos,      8       ; read position pointer
    field line,     4       ; current line number
    field pad1,     4       ; alignment padding
    field lexer,    8       ; saved LexerState
endstruc

; ============================================================================
; STRUCT: MacroDef
; ============================================================================

struc MACRO
    field tag,      1       ; always TAG_MACRO
    field min_params, 1     ; minimum required parameters
    field max_params, 1     ; maximum allowed parameters (0xFF = variadic)
    field pad0,      5       ; alignment padding
    field name,     8       ; macro name pointer
    field ntokens,  4       ; token count in body
    field pad1,     4       ; explicit padding to align tokens to 8-byte boundary
    field tokens,   8       ; pointer to token array
endstruc

; ============================================================================
; STRUCT: MacroExpansion
; ============================================================================

struc MACROEXP
    field tag,      1       ; always TAG_MACRO_EXP
    field depth,    1       ; nesting depth
    field nparams,  1       ; parameter count
    field pad0,      1       ; explicit padding to align rep_count to 4-byte boundary
    field rep_count, 4      ; repetitions remaining (for %rep)
    field macro,    8       ; pointer to Macro symbol
    field parent,   8       ; parent MacroExpansion pointer
    field params,   8       ; array of pointers to each argument's first token
    field body,     8       ; current body position token pointer
    field line,     4       ; invocation line number
    field pad1,     4       ; alignment padding
    field arglens,  8       ; per-argument token counts (byte array)
    field pend_ptr, 8       ; next token of the argument being substituted
    field pend_cnt, 4       ; tokens still to emit from that argument
    field exp_id,   4       ; id used by %%locals (shared with %rep bodies)
endstruc

; ============================================================================
; STRUCT: AsmCtx
; ============================================================================

struc ASMCTX
    field tag,         1       ; always TAG_ASM_CTX
    field target,      1       ; TARGET_* value
    field fmt,         1       ; FMT_* value
    field opt,         1       ; OPT_* value
    field err_count,   2       ; error counter
    field warn_count,  2       ; warning counter
    field arena,       8       ; pointer to Arena
    field symtab,      8       ; pointer to symbol table
    field symcount,    4       ; symbol count
    field pad0,        4       ; alignment padding
    field sections,    8       ; pointer to section array
    field seccount,    4       ; section count
    field group_count, 4       ; section group count
    field relocs,      8       ; pointer to relocation array
    field nrelocs,     4       ; relocation count
    field inst_len,    4       ; current instruction length (0-15)
    field debug_line,  4       ; current source line for DWARF
    field debug_file,  4       ; current source file index for DWARF
    field debug_col,   4       ; current source column for DWARF
    field standalone,  1       ; 1 if generating standalone executable
    field pad_sove,    3       ; alignment padding to naturally align entry_point to 8-byte boundary
    field entry_point, 8       ; virtual address of entry point
    field inc_ctx,     8       ; current IncludeCtx pointer
    field mac_exp,     8       ; current MacroExpansion pointer
    field input,       8       ; input filename pointer
    field output,      8       ; output filename pointer
    field ld_script,   8       ; linker script filename pointer
    field inc_paths,   8       ; include path array pointer
    field ninc_paths,  4       ; include path count
    field flags,       4       ; CTX_FLAG_* values
    field last_global, 8       ; pointer to string of last global label
    field curr_sec,    8       ; pointer to current active SECTION
    field total_lines, 8       ; total lines processed
    field perf_start,  8       ; RDTSC start cycles
    field perf_end,    8       ; RDTSC end cycles
    field symhash,     8       ; pointer to symbol hash table (64k entries)
    field expr_depth,  4       ; expression recursion depth sentinel
    field mac_exp_id,  4       ; global macro expansion counter (A70)
    field last_symbol, 8       ; pointer to last defined SYMBOL (for equ)
endstruc

; ============================================================================
; STRUCT: LexerState
; ============================================================================

struc LEXER
    field tag,      1       ; always TAG_LEXER
    field pad0,     7       ; alignment padding
    field buf,      8       ; buffer start pointer
    field pos,      8       ; current position pointer
    field end,      8       ; buffer end boundary pointer
    field file,     8       ; filename pointer
    field line,     4       ; current line number
    field col,      2       ; current column number
    field pad1,     2       ; alignment padding
    field peek,     TOKEN_SIZE ; inline token storage
    field has_peek, 1       ; peek valid flag (TRUE/FALSE)
    field pad2,     7       ; alignment padding
    field ctx,      8       ; pointer to AsmCtx
    field arena,    8       ; pointer to Arena
endstruc

; ============================================================================
; STRUCT: Archive
; ============================================================================

struc ARCHIVE
    field tag,          1       ; TAG_ARCHIVE
    field pad0,         7       ; alignment padding
    field buf,          8       ; pointer to mapped library
    field size,         8       ; total size in bytes
    field curr,         8       ; current iterator position pointer
    field symtab,       8       ; pointer to '/' member (symbols)
    field strtab,       8       ; pointer to ';' member (long names)
    field nmembers,     4       ; total members found
    field pad1,         4       ; alignment padding
endstruc

; ============================================================================
; STRUCT: PrepState
; ============================================================================

struc PREP
    field tag,          1       ; always TAG_PREPROCESSOR
    field depth,        1       ; conditional depth
    field skip_depth,   1       ; skipping depth
    field has_peek,     1       ; TRUE if peek is valid
    field mac_depth,    1       ; macro recursion depth (A83)
    field pad0,         3       ; alignment padding
    field line,         4       ; current source line number
    field col,          4       ; current source column number
    field peek,         TOKEN_SIZE ; peek buffer token
    field lexer,        8       ; current LexerState pointer
    field ctx,          8       ; pointer to AsmCtx
    field arena,        8       ; pointer to Arena
    field cond_taken,   PREP_CTX_MAX ; per level: a branch already fired here
    field ctx_depth,    4       ; %push context stack depth
    field ctx_next_id,  4       ; next unique context id
    field ctx_ids,      PREP_CTX_MAX * 4   ; unique id per stacked context
    field ctx_names,    PREP_CTX_MAX * 8   ; name pointer per stacked context
endstruc

; ============================================================================
; STRUCT: Operand
; ============================================================================

struc OPERAND
    field tag,        1       ; always TAG_OPERAND
    field kind,       1       ; OP_* value
    field size,       1       ; operand size in bits
    field reg,        1       ; register ID
    field segment,    1       ; segment override (0x64, 0x65)
    field is_high,    1       ; 1 if AH/CH/DH/BH
    field mask,       1       ; AVX-512 k-register mask (0-7)
    field ctrl,       1       ; AVX-512 rounding/broadcast control
    field flags,      1       ; OP_FLAG_* value
    field base,       1       ; base register ID
    field index,      1       ; index register ID
    field scale,      1       ; scale factor (1, 2, 4, 8)
    field shift_type, 1       ; AArch64 shift type (LSL, LSR, etc)
    field shift_imm,  1       ; shift immediate amount
    field pad0,       2       ; padding to align reloc to 4-byte boundary
    field reloc,      4       ; relocation type (e.g. :lo12:)
    field pad1,       4       ; padding to align imm to 8-byte boundary
    field imm,        8       ; immediate or displacement value
    field sym,        8       ; pointer to Symbol
    field pad2,       8       ; alignment padding to maintain multiple of 8
endstruc

; ============================================================================
; STRUCT: Instruction
; ============================================================================

struc INST
    field tag,       1       ; always TAG_INSTRUCTION
    field nops,      1       ; operand count
    field flags,     1       ; instruction flags
    field pad0,      1       ; explicit padding to align op_id to 2-byte boundary
    field op_id,     2       ; mnemonic ID
    field pad1,      2       ; explicit padding to align next field to 8-byte boundary
    field prefixes,  4       ; instruction prefixes (up to 4 slots)
    field pad2,      4       ; padding to align op0 to 8-byte boundary
    field op0,       OPERAND_SIZE
    field op1,       OPERAND_SIZE
    field op2,       OPERAND_SIZE
    field op3,       OPERAND_SIZE
    field offset,    8       ; offset in section
    field section,   8       ; pointer to SECTION
endstruc

; ============================================================================
; STRUCT: PHDR (Elf64_Phdr)
; ============================================================================

struc PHDR
    field type,     4       ; segment type (PT_LOAD, etc)
    field flags,    4       ; segment flags (PF_X | PF_W | PF_R)
    field offset,   8       ; file offset
    field vaddr,    8       ; virtual address
    field paddr,    8       ; physical address
    field filesz,   8       ; size in file
    field memsz,    8       ; size in memory
    field align,    8       ; alignment
endstruc

; ============================================================================
; STRUCT: ErrorRecord — single diagnostic record
; ============================================================================

struc ERRORREC
    field code,      2    ; dw  error/warning code number (E1xx etc)
    field severity,  1    ; db  SEV_* constant (ERROR, WARNING, NOTE, HINT)
    field pad0,      1    ; db  alignment padding
    field file_id,   2    ; dw  index into file registry
    field pad1,      2    ; dw  alignment padding
    field line,      4    ; dd  source line number (1-based)
    field col_start, 2    ; dw  column start (inclusive)
    field col_end,   2    ; dw  column end (inclusive)
    field msg_idx,   2    ; dw  message table index
    field note_idx,  2    ; dw  note table index (0 = none)
    field hint_idx,  2    ; dw  hint table index (0 = none)
    field chain_id,  2    ; dw  macro expansion chain id (0 = none)
endstruc

; ============================================================================
; STRUCT: ISAEntry — row in the ISA opcode table
; ============================================================================

struc ISAENTRY
    field name_ptr,   8    ; dq  pointer to mnemonic string
    field opcode,     4    ; dd  opcode bytes
    field opcode_ext, 1    ; db  /0–/7 or 0xFF (none)
    field enc_type,   1    ; db  encoding class (ENC_*)
    field prefix_req, 1    ; db  required prefix flags (PREFIX_*)
    field pad0,       1    ; db  explicit padding to align operand types
    field op_type0,   1    ; db  operand type 0 (OT_*)
    field op_type1,   1    ; db  operand type 1 (OT_*)
    field op_type2,   1    ; db  operand type 2 (OT_*)
    field op_type3,   1    ; db  operand type 3 (OT_*)
    field pad1,       4    ; dd  explicit padding to naturally align cpu_flags to 8
    field cpu_flags,  8    ; dq  required 64-bit CPU feature mask
endstruc

; ============================================================================
; STRUCT: FileRegistryEntry — registered source files metadata
; ============================================================================

struc FILEREG
    field index,        4       ; unique file registration index
    field pad0,         4       ; alignment padding
    field name_ptr,     8       ; pointer to filename string
    field buf_ptr,      8       ; pointer to mapped file buffer
    field size,         8       ; size of the file in bytes
    field parent_idx,   4       ; index of parent include file (0xFFFFFFFF = none)
    field pad1,         4       ; alignment padding (maintains multiple of 8)
endstruc

; ============================================================================
; STRUCT: Elf64_Dyn — dynamic linking table segment entry
; ============================================================================

struc ELFDYN
    field tag,          8       ; dynamic table entry type tag (DT_*)
    field val,          8       ; dynamic QWORD value or offset pointer
endstruc

; ============================================================================
; STRUCT: HashBucket — single slot inside the symbol hash table
; ============================================================================

struc HASHBUCKET
    field hash,         8       ; calculated 64-bit FNV1a hash of symbol name
    field name,         8       ; pointer to name string (borrowed from symbol)
    field sym_ptr,      8       ; pointer to resolved SYMBOL structure
endstruc

; ============================================================================
; STRUCT: UPKHeader — sovereign package format file header
; ============================================================================

struc UPKHEADER
    field magic,         4       ; "UPK!" magic bytes (UPK_MAGIC)
    field version,       2       ; UPK format version
    field flags,         2       ; UPK_FLAG_* bitmask
    field entry_point,   8       ; virtual address entry point offset
    field dep_count,     4       ; count of package dependencies
    field sec_count,     4       ; count of sections in package
    field name,        128       ; package name string buffer
    field signature,    64       ; cryptographically signed payload signature
endstruc

; ============================================================================
; STRUCT: UPKSection — section record inside sovereign packages
; ============================================================================

struc UPKSECTION
    field name,         64       ; section name buffer
    field offset,        8       ; file offset of section payload
    field size,          8       ; actual size of section payload
    field vaddr,         8       ; virtual loading address of section
    field flags,         4       ; section attribute flags
    field pad0,          4       ; alignment padding (maintains multiple of 8)
endstruc

; ============================================================================
; STRUCT: ProfileEntry — single profiling measurement record
; ============================================================================
; One entry per assembler pipeline phase. Measures RDTSC cycle counts.
; See docs/profiler_architecture.md §4.1 for byte-level layout.

struc PROFENTRY
    field tag,         1       ; TAG_PROFENTRY (0x10)
    field phase_id,    1       ; PHASE_* identifier (0x01–0x08)
    field is_hot,      1       ; TRUE if cycles > hot_threshold
    field pad0,        5       ; alignment padding
    field label,       8       ; pointer to phase name string
    field start_tsc,   8       ; RDTSC value at phase entry
    field end_tsc,     8       ; RDTSCP value at phase exit
    field cycles,      8       ; accumulated delta (end - start - overhead)
    field call_count,  4       ; invocation count
    field pad1,        4       ; alignment padding
endstruc
; PROFENTRY_SIZE = 48 bytes (6 × 8)

; ============================================================================
; STRUCT: ProfileState — global profiler context
; ============================================================================
; Single instance allocated at profiler_init time. Owns the entry array.
; See docs/profiler_architecture.md §4.2 for byte-level layout.

struc PROFSTATE
    field tag,            1    ; TAG_PROFSTATE (0x11)
    field enabled,        1    ; TRUE if profiling is active
    field num_entries,    2    ; current entry count (≤ MAX_PROF_ENTRIES)
    field hot_threshold,  4    ; cycles threshold for hot path flag
    field entries,        8    ; pointer to PROFENTRY[MAX_PROF_ENTRIES] array
    field total_cycles,   8    ; sum of all phase cycles
    field calib_overhead, 8    ; measured RDTSC pair overhead
    field arena,          8    ; pointer to Arena allocator
    field global_start,   8    ; TSC at profiler_init time
    field global_end,     8    ; TSC at profiler_finalize time
endstruc
; PROFSTATE_SIZE = 56 bytes (7 × 8)

%endif ; TYPE_S
