%ifndef CONSTANT_S
%define CONSTANT_S

; ============================================================================
; File     : include/constant.inc
%define CONSTANT_S
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Central constants definition for all utasm modular layers.
; ============================================================================

; ============================================================================
; EXIT CODES
; ============================================================================
; Process termination status values passed to the system exit call.
; Valid range is strictly 0 through 125. Values 126 and 127 are reserved
; by the host command interpreter for its own errors. Values 128 and above
; are reserved by the platform for signal-based termination and must never
; be used as normal exit codes.
;
; NOTE ON PARITY & CONVENTIONS:
; - Standard compiler exit codes (0 to 9) align precisely with the calling
;   expectations in main.s, docs/error_reference.md, and docs/abi.md.
; - Values 124 (EXIT_INTERNAL) and 125 (EXIT_OOM) were historically proposed
;   to keep compiler crash statuses distinct from standard shell/OS utility 
;   statuses, but consecutive codes 0-9 are preferred to prevent mismatch 
;   between subsystems.
;
%define EXIT_OK                0   ; operation completed successfully
%define EXIT_ERROR             1   ; unspecified general failure or CLI usage error
%define EXIT_USAGE             1   ; alias for EXIT_ERROR (invalid CLI arguments/flags)
%define EXIT_OOM               2   ; out of memory (corresponds to EXIT_OOM = 2 in abi.md)
%define EXIT_IO_ERROR          3   ; unified I/O error code (file read, write, etc.)
%define EXIT_PARSER_ERROR      4   ; parser syntax or semantic constraint failed
%define EXIT_ENCODER_ERROR     5   ; machine instruction encoding failed
%define EXIT_LINKER_ERROR      6   ; static linking or relocation resolution failed
%define EXIT_INTERNAL          7   ; unrecoverable internal assembler error (utasm bug)
%define EXIT_ASSERTION         8   ; compiler assertion failed
%define EXIT_SIGNAL            9   ; execution interrupted by OS signal or trap

; Specific I/O subdivision exit codes (kept distinct to prevent collision with 0-9)
%define EXIT_FILE_NOT_FOUND    10  ; requested input file does not exist
%define EXIT_FILE_PERM         11  ; insufficient permissions to access file
%define EXIT_FILE_READ         12  ; error occurred during file read operation
%define EXIT_FILE_WRITE        13  ; error occurred during file write operation
%define EXIT_INVALID_FORMAT    14  ; file format is invalid or unrecognized

%define EXIT_INC_NOT_FOUND     15  ; included file specified by source not found
%define EXIT_MACRO_DEF         16  ; malformed or illegal macro definition
%define EXIT_MACRO_EXP         17  ; failure during macro expansion phase
%define EXIT_MACRO_RECURSION   18  ; nested macro depth exceeded limit
%define EXIT_MACRO_ARITY_FAIL  19  ; wrong number of macro arguments
%define EXIT_DEFINE            20  ; invalid or malformed %define directive

%define EXIT_UNKNOWN_INSTR     25  ; mnemonic does not match any known instruction
%define EXIT_INVALID_OPERAND   26  ; operand syntax is not valid for instruction
%define EXIT_INVALID_REG       27  ; register name is unrecognized or illegal
%define EXIT_INVALID_IMM       28  ; immediate value format or content is invalid
%define EXIT_INVALID_ADDR      29  ; addressing mode expression is malformed
%define EXIT_UNEXPECTED_TOKEN  30  ; token encountered where none was expected
%define EXIT_UNEXPECTED_EOF    31  ; end of input reached before construct completed
%define EXIT_EXPR_TOO_DEEP     32  ; expression recursion depth exceeded limit
%define EXIT_INVALID_EXPR      33  ; expression syntax or evaluation error
%define EXIT_INVALID_SECTION_FLAGS 34 ; section flags are invalid or incompatible

%define EXIT_ENCODE_FAIL       40  ; instruction encoding could not be generated
%define EXIT_IMM_RANGE         41  ; immediate value exceeds allowed bit width
%define EXIT_OFFSET_RANGE      42  ; branch or memory offset exceeds range
%define EXIT_UNSUPPORTED_INSTR 43  ; valid instruction not supported by target
%define EXIT_ALIGN_ERROR       44  ; alignment directive could not be satisfied
%define EXIT_STRUCT_BOUNDS     45  ; memory write size exceeds struct field byte width

%define EXIT_UNDEF_SYMBOL      50  ; referenced symbol has no definition
%define EXIT_DUP_SYMBOL        51  ; symbol defined more than once
%define EXIT_SYMBOL_RANGE      52  ; symbol value exceeds representable range
%define EXIT_CIRCULAR_REF      53  ; circular dependency detected between symbols

%define EXIT_LD_SCRIPT_404     60  ; linker script file not found
%define EXIT_LD_SCRIPT_PARSE   61  ; linker script contains syntax errors
%define EXIT_SECTION_OVERLAP   62  ; two or more output sections occupy same address
%define EXIT_RELOC_ERROR       63  ; relocation could not be applied
%define EXIT_UNDEF_REF         64  ; symbol referenced but never defined
%define EXIT_MULTI_DEF         65  ; symbol defined in multiple input objects
%define EXIT_INVALID_SECTION   66  ; section index is out of bounds or invalid

%define EXIT_OUT_CREATE        70  ; failed to create output file
%define EXIT_ELF_WRITE         71  ; error writing ELF format output
%define EXIT_BIN_WRITE         72  ; error writing flat binary output

%define EXIT_ASSERT            75  ; compilation assertion failed
%define EXIT_UNREACHABLE       76  ; compiler hit a code path marked unreachable
%define EXIT_NOT_IMPLEMENTED   77  ; requested compiler feature is not implemented

; ============================================================================
; TEST HARNESS EXIT CODES
; ============================================================================
; These are used solely by test runner scripts and emulator integration,
; completely segregated from standard compiler operations.
%define EXIT_QEMU_404          110 ; emulator binary not found in path
%define EXIT_QEMU_FAIL         111 ; emulator process exited with error

; ============================================================================
; BOOLEAN AND STATUS VALUES
; ============================================================================
; Generic truth values and operation status indicators.
; ERR uses a signed representation and must only be tested with signed
; conditional jumps (JL, JG, etc.). For unsigned-safe error testing,
; use STATUS_ERR instead.

%define TRUE                   1   ; logical affirmative
%define FALSE                  0   ; logical negative
%define NULL                   0   ; null pointer value
%define OK                     0   ; function success status
%define ERR                    -1  ; function failure status (signed only)
%define STATUS_ERR             1   ; function failure status (unsigned-safe)

; ============================================================================
; LIMITS AND CAPACITIES
; ============================================================================
; Hard upper bounds for internal data structures and processing loops.
; These prevent unbounded growth that could exhaust host resources.

%define MAX_ARGS               32          ; maximum command-line arguments
%define MAX_PATH               4096        ; maximum file path length in bytes
%define MAX_LINE               4096        ; maximum source line length (expanded for macro nesting)
%define MAX_TOKEN              4096        ; maximum single token length (matched to macro limits)
%define MAX_SYMBOL             65536       ; maximum entries in symbol table
%define MAX_SECTIONS           65535       ; maximum ELF sections per object (aligned to standard ELF limits)
%define MAX_INCLUDES           256         ; maximum nested include depth
%define MAX_MACRO_PARAMS       32          ; maximum parameters per macro
%define MAX_MACRO_DEPTH        64          ; maximum nested macro expansion depth
%define MAX_REP_COUNT          65536       ; maximum iterations per %rep block
%define MAX_ERRORS             100         ; fatal hard stop threshold for error count (consistent with docs/workflow.md and docs/error_reference.md)
%define MAX_ERRORS_SOFT        100         ; soft threshold for warning count reporting
%define MAX_WARNINGS           100         ; threshold for warning count
%define MAX_RELOC              8192        ; maximum relocation entries per object

; ============================================================================
; BUFFER SIZES
; ============================================================================
; Working buffer dimensions for streaming I/O operations.
; These are chunk sizes for incremental read and write operations,
; not maximum file size limits. Large files are processed in multiple
; passes through these buffers.

%define BUF_INPUT              65536       ; input file read chunk
%define BUF_OUTPUT             65536       ; output file write chunk
%define BUF_TOKEN              4096        ; token accumulation workspace
%define BUF_ERROR              1024        ; formatted error message buffer
%define BUF_LINE               4096        ; single line processing buffer

; ============================================================================
; TYPE TAGS
; ============================================================================
; Every struct in utasm has a 1-byte type tag at offset 0.

%define TAG_TOKEN              0x01
%define TAG_SYMBOL             0x02
%define TAG_SECTION            0x03
%define TAG_RELOC              0x04
%define TAG_MACRO              0x05
%define TAG_MACRO_EXP          0x06
%define TAG_INCLUDE_CTX        0x07
%define TAG_ASM_CTX            0x08
%define TAG_ARENA              0x09
%define TAG_LEXER              0x0A
%define TAG_PREPROCESSOR       0x0B
%define TAG_OPERAND            0x0C
%define TAG_INSTRUCTION        0x0D
%define TAG_ARCHIVE            0x0E
; 0x10–0x11 are taken by the profiler (TAG_PROFENTRY / TAG_PROFSTATE)
%define TAG_VEC                0x12        ; growable array (lib/vec.s)
%define TAG_LIST               0x13        ; doubly linked list (lib/list.s)
%define TAG_FMTBUF             0x14        ; string builder (lib/fmt.s)

; ============================================================================
; TOKEN TYPES
; ============================================================================

%define TOK_UNKNOWN            0x00
%define TOK_EOF                0x01
%define TOK_NEWLINE            0x02
%define TOK_IDENT              0x03
%define TOK_NUMBER             0x04
%define TOK_STRING             0x05
%define TOK_CHAR               0x06
%define TOK_LABEL              0x07
%define TOK_LOCAL_LABEL        0x08
%define TOK_REGISTER           0x09
%define TOK_COMMA              0x0A
%define TOK_COLON              0x0B
%define TOK_LBRACKET           0x0C
%define TOK_RBRACKET           0x0D
%define TOK_LBRACE             0x0E
%define TOK_RBRACE             0x0F
%define TOK_LPAREN             0x10
%define TOK_RPAREN             0x11
%define TOK_PLUS               0x12
%define TOK_MINUS              0x13
%define TOK_STAR               0x14
%define TOK_SLASH              0x15
%define TOK_PERCENT            0x16
%define TOK_AMPERSAND          0x17
%define TOK_PIPE               0x18
%define TOK_CARET              0x19
%define TOK_TILDE              0x1A
%define TOK_LSHIFT             0x1B
%define TOK_RSHIFT             0x1C
%define TOK_HASH               0x1D
%define TOK_CONCAT             0x1E
%define TOK_AT                 0x1F
%define TOK_DIRECTIVE          0x20

; Token flags (TOKEN_flags)
%define TOK_FLAG_INTERP        0x01        ; text contains %[NAME], resolve at expansion
%define TOK_COMMENT            0x21
%define TOK_FLOAT              0x22
%define TOK_MACRO_LOCAL        0x23
%define TOK_DOLLAR             0x24
%define TOK_EQUAL              0x25
%define TOK_NEQUAL             0x26
%define TOK_LT                 0x27
%define TOK_GT                 0x28

; ---- Extended Operators & Multi-Char Tokens ----
%define TOK_LE                 0x29        ; <= operator
%define TOK_GE                 0x2A        ; >= operator
%define TOK_AND                0x2B        ; && logical and
%define TOK_OR                 0x2C        ; || logical or
%define TOK_NOT                0x2D        ; ! logical not
%define TOK_DOLLAR_DOLLAR      0x2E        ; $$ (section start address reference)
%define TOK_DOTDOT             0x2F        ; .. (special section reference prefix like ..start)

; ---- Preprocessor & Macro Parsing Tokens ----
%define TOK_MACRO_PARAM        0x30        ; %1, %2 etc inside macro body
%define TOK_MACRO_COUNT        0x31        ; %0 macro argument count
%define TOK_MACRO_REST         0x32        ; %* macro greedy rest of arguments
%define TOK_LOCAL_MACRO        0x33        ; %%label macro-local labels

; ---- Assembler Specifiers & Directives ----
%define TOK_SEG_OVERRIDE       0x34        ; segment overrides (CS:, DS:, FS:, GS:, etc.)
%define TOK_SIZE_BYTE          0x35        ; BYTE PTR size directive
%define TOK_SIZE_WORD          0x36        ; WORD PTR size directive
%define TOK_SIZE_DWORD         0x37        ; DWORD PTR size directive
%define TOK_SIZE_QWORD         0x38        ; QWORD PTR size directive
%define TOK_SIZE_XMMWORD       0x39        ; XMMWORD PTR size directive
%define TOK_SIZE_YMMWORD       0x3A        ; YMMWORD PTR size directive
%define TOK_SIZE_ZMMWORD       0x3B        ; ZMMWORD PTR size directive

%define TOK_NEAR               0x3C        ; NEAR specifier keyword
%define TOK_FAR                0x3D        ; FAR specifier keyword
%define TOK_SHORT              0x3E        ; SHORT specifier keyword
%define TOK_REL                0x3F        ; REL specifier keyword (RIP-relative)
%define TOK_ABS                0x40        ; ABS specifier keyword (Absolute)
%define TOK_STRICT             0x41        ; STRICT modifier keyword
%define TOK_NOSPLIT            0x42        ; NOSPLIT keyword (prevents SIB splitting)

%define TOK_BACKSLASH          0x43        ; \ backslash character
%define TOK_QUESTION           0x44        ; ? ternary question mark
%define TOK_EXCLAM             0x45        ; ! exclamation mark
%define TOK_SEMICOLON          0x46        ; ; semicolon punctuation
%define TOK_DOT                0x47        ; . dot/period punctuation
%define TOK_COLONCOLON         0x48        ; :: namespace colon operator

; ============================================================================
; SYMBOL KINDS AND VISIBILITY
; ============================================================================

%define SYM_UNKNOWN            0x00
%define SYM_LABEL              0x01
%define SYM_DATA               0x02
%define SYM_CONSTANT           0x03
%define SYM_MACRO              0x04
%define SYM_EXTERN             0x05
%define SYM_SECTION            0x06
%define SYM_STRUCT             0x07        ; a struc definition (name -> total_size)
%define SYM_STRUCT_FIELD       0x08        ; a struct field (name -> offset, size = width)

%define SYM_COMMON             0x09        ; uninitialized common block symbol
%define SYM_FORWARD            0x0A        ; forward reference symbol (pass 1 to pass 2)
%define SYM_BUILTIN            0x0B        ; compiler built-in constants (e.g. $, $$)
%define SYM_PROC               0x0C        ; PROC-scoped executable subroutine symbol
%define SYM_LOCAL_LABEL        0x0D        ; .local label scoped to parent Proc
%define SYM_SET                0x0E        ; mutable variable defined via %assign or SET
%define SYM_EQU                0x0F        ; immutable assembler constant defined via EQU
%define SYM_IFUNC              0x10        ; ELF indirect function symbol
%define SYM_GNU_INDIRECT_FUNC  0x11        ; GNU indirect function resolver
%define SYM_THREAD_LOCAL       0x12        ; Thread-Local Storage symbol

%define VIS_LOCAL              0x00        ; visible only within the defining translation unit
%define VIS_GLOBAL             0x01        ; exported for external linkage visibility
%define VIS_WEAK               0x02        ; weak symbol linkage
%define VIS_HIDDEN             0x03        ; hidden ELF visibility
%define VIS_PROTECTED          0x04        ; protected ELF visibility
%define VIS_INTERNAL           0x05        ; processor-specific internal visibility

; ============================================================================
; SECTION TYPES
; ============================================================================

%define SEC_TEXT               0x01        ; executable code section
%define SEC_DATA               0x02        ; initialized mutable data section
%define SEC_BSS                0x03        ; uninitialized data section (zero disk space)
%define SEC_RODATA             0x04        ; read-only constant data section
%define SEC_CUSTOM             0x05        ; user-defined custom section

%define SEC_INIT               0x06        ; constructor initialisation routine section
%define SEC_FINI               0x07        ; destructor routine section
%define SEC_NOTE               0x08        ; OS build ABI tags and notes section
%define SEC_DEBUG              0x09        ; DWARF v5 metadata debug sections
%define SEC_COMMENT            0x0A        ; compiler identification comments section
%define SEC_ABSOLUTE           0x0B        ; absolute address memory mapped section
%define SEC_EXTERN             0x0C        ; external unresolved symbols section

%define SEC_TLS                0x0D        ; Thread-Local Storage initialized section
%define SEC_INIT_ARRAY         0x0E        ; array of constructor pointers
%define SEC_FINI_ARRAY         0x0F        ; array of destructor pointers
%define SEC_PREINIT_ARRAY      0x10        ; array of pre-constructor pointers
%define SEC_EH_FRAME           0x11        ; exception handling frames unwind table
%define SEC_GOT                0x12        ; Global Offset Table section
%define SEC_PLT                0x13        ; Procedure Linkage Table section
%define SEC_DYNAMIC            0x14        ; dynamic linking metadata section
%define SEC_DYNSYM             0x15        ; dynamic linking symbol table
%define SEC_DYNSTR             0x16        ; dynamic linking string table
%define SEC_HASH               0x17        ; symbol hash table section
%define SEC_GNU_HASH           0x18        ; GNU-style symbol hash table
%define SEC_VERSYM             0x19        ; symbol version table
%define SEC_VERNEED            0x1A        ; version requirements table
%define SEC_RELA_DYN           0x1B        ; relocations for dynamic section
%define SEC_RELA_PLT           0x1C        ; relocations for PLT segment

; ============================================================================
; OPERAND KINDS
; ============================================================================

%define OP_NONE                0x00        ; no operand present
%define OP_REG                 0x01        ; GPR register operand
%define OP_IMM                 0x02        ; absolute immediate value
%define OP_MEM                 0x03        ; standard memory addressing mode
%define OP_SYMBOL              0x04        ; symbolic memory/offset reference

%define OP_REL                 0x05        ; relative offset addressing
%define OP_FAR_MEM             0x06        ; far memory addressing (seg:offset)
%define OP_BROADCAST           0x07        ; AVX-512 vector data broadcasting {1toN}
%define OP_MASK                0x08        ; AVX-512 mask register {k1}
%define OP_ZMASK               0x09        ; AVX-512 zero-mask register {k1}{z}
%define OP_ROUNDING            0x0A        ; AVX-512 embedded rounding controls {rn-sae}
%define OP_SAE                 0x0B        ; AVX-512 suppress all exceptions flag {sae}
%define OP_VSIB                0x0C        ; Vector SIB addressing (XMM/YMM/ZMM indices)

%define OP_FPU_REG             0x0D        ; x87 FPU register operand (ST0-ST7)
%define OP_XMM_REG             0x0E        ; SSE/AVX 128-bit SIMD register
%define OP_YMM_REG             0x0F        ; AVX 256-bit SIMD register
%define OP_ZMM_REG             0x10        ; AVX-512 512-bit SIMD register
%define OP_K_REG               0x11        ; AVX-512 mask register (k0-k7)
%define OP_MM_REG              0x12        ; MMX register operand
%define OP_CR_REG              0x13        ; x86 control register (CR0-CR15)
%define OP_DR_REG              0x14        ; x86 debug register (DR0-DR7)
%define OP_SEG_REG             0x15        ; x86 segment register (CS, DS, etc.)
%define OP_ST_REG              0x16        ; FPU stack register alias
%define OP_LABEL               0x17        ; code target jump label reference
%define OP_EXPR                0x18        ; compound relocatable expressions

; ============================================================================
; OPERAND FLAGS
; ============================================================================
; Modifiers applied to specific operands during parsing.

%define OP_FLAG_REL            0x01        ; target is RIP-relative (REL keyword)
%define OP_FLAG_STRICT         0x02        ; STRICT keyword applied to enforce size
%define OP_FLAG_NOSPLIT        0x04        ; NOSPLIT keyword applied to index register
%define OP_FLAG_ABS            0x08        ; ABS keyword applied to force absolute offset
%define OP_FLAG_SHORT          0x10        ; SHORT keyword applied to a branch target
%define OP_FLAG_ADDR32         0x20        ; memory addressed by 32-bit registers (67 prefix)

; ============================================================================
; CONTEXT FLAGS
; ============================================================================
; Flags controlling the active assembler run context (AsmCtx).
;
; ARCHITECTURAL NOTE:
; - Using individual bits in this bitmask for target output formats is fragile
;   and deprecated. Format is an enum represented by the FMT_* identifiers.
; - A separate format field in the context struct should be used instead of
;   setting multiple potentially conflicting bits in this bitmask.
; - CTX_FLAG_FORMAT_* flags below are preserved solely for backward 
;   compatibility with existing generation-1 parser/linker stages.
;
%define CTX_FLAG_DEBUG         0x000001    ; emit debug DWARF records
%define CTX_FLAG_VERBOSE       0x000002    ; output verbose logs during build
%define CTX_FLAG_WERROR        0x000004    ; treat warnings as hard compilation errors
%define CTX_FLAG_COLOR         0x000008    ; colorize terminal stderr output (ANSI)
%define CTX_FLAG_LISTING       0x000010    ; generate .lst compiler assembly listing
%define CTX_FLAG_MAPFILE       0x000020    ; generate .map static linker map file
%define CTX_FLAG_STRIP         0x000040    ; strip local and debug symbols on emission
%define CTX_FLAG_FORMAT_BIN    0x000080    ; DEPRECATED: output flat binary format flag (use FMT_BIN enum instead)
%define CTX_FLAG_FORMAT_ELF    0x000100    ; DEPRECATED: output ELF64 format flag (use FMT_ELF64 enum instead)
%define CTX_FLAG_FORMAT_PE     0x000200    ; DEPRECATED: output PE32+ format flag (use FMT_PE32PLUS enum instead)
%define CTX_FLAG_FORMAT_UPK    0x000400    ; DEPRECATED: output .upk format flag (use FMT_UPK enum instead)
%define CTX_FLAG_STANDALONE    0x000800    ; standalone build (requires _start entry point)
%define CTX_FLAG_DWARF         0x001000    ; generate explicit DWARF v5 sections
%define CTX_FLAG_SELFPATCH     0x002000    ; enable self-patching optimization engine
%define CTX_FLAG_PROFILE       0x004000    ; enable RDTSC-based compiler performance profile
%define CTX_FLAG_NO_DEAD_STRIP 0x008000    ; disable dead section stripping
%define CTX_FLAG_PIC           0x010000    ; emit Position-Independent Code
%define CTX_FLAG_PIE           0x020000    ; emit Position-Independent Executable
%define CTX_FLAG_NO_COLOR      0x040000    ; explicitly disable ANSI colors (bypasses automatic checks)
%define CTX_FLAG_PASS2         0x080000    ; assembler is currently executing Pass 2
%define CTX_FLAG_RELOCATABLE   0x100000    ; output object is relocatable (ET_REL) rather than linked
; CLI-only actions. These are consumed by _start before an input file is
; required; they deliberately do not affect assembly semantics.
%define CTX_FLAG_SHOW_HELP     0x200000
%define CTX_FLAG_SHOW_VERSION  0x400000
%define CTX_FLAG_DEFAULT_REL   0x800000    ; DEFAULT REL: [label] means [rel label]

; Jump-shortening records (optimizer/jump.s), noted while encoding
%define RELAX_JMP              1           ; forward jmp emitted as E9 rel32
%define RELAX_JCC              2           ; forward jcc emitted as 0F 8x rel32
%define RELAX_FIXED            3           ; branch displacement resolved in place
%define RELAX_ALIGN            4           ; align padding

; ============================================================================
; CPU FEATURE BITS (AMD64)
%define FEAT_AVX               (1ULL << 0)
%define FEAT_AVX2              (1ULL << 1)
%define FEAT_AVX512F           (1ULL << 2)
%define FEAT_AVX512DQ          (1ULL << 3)
%define FEAT_AVX512BW          (1ULL << 4)
%define FEAT_AVX512VL          (1ULL << 5)
%define FEAT_AMX_TILE          (1ULL << 6)
%define FEAT_AMX_INT8          (1ULL << 7)
%define FEAT_AMX_BF16          (1ULL << 8)
%define FEAT_SGX               (1ULL << 9)
%define FEAT_AES               (1ULL << 10)
%define FEAT_SHA               (1ULL << 11)
%define FEAT_KL                (1ULL << 12)

%define FEAT_SSE               (1ULL << 13)
%define FEAT_SSE2              (1ULL << 14)
%define FEAT_SSE3              (1ULL << 15)
%define FEAT_SSSE3             (1ULL << 16)
%define FEAT_SSE4_1            (1ULL << 17)
%define FEAT_SSE4_2            (1ULL << 18)
%define FEAT_MMX               (1ULL << 19)
%define FEAT_RDRAND            (1ULL << 20)
%define FEAT_RDSEED            (1ULL << 21)
%define FEAT_RDTSC             (1ULL << 22)
%define FEAT_RDTSCP            (1ULL << 23)
%define FEAT_XSAVE             (1ULL << 24)
%define FEAT_XSAVEOPT          (1ULL << 25)
%define FEAT_BMI1              (1ULL << 26)
%define FEAT_BMI2              (1ULL << 27)
%define FEAT_FMA               (1ULL << 28)
%define FEAT_F16C              (1ULL << 29)
%define FEAT_PCLMUL            (1ULL << 30)
%define FEAT_CET_SS            (1ULL << 31)
%define FEAT_CET_IBT           (1ULL << 32)
%define FEAT_WAITPKG           (1ULL << 33)
%define FEAT_AVX512VNNI        (1ULL << 34)
%define FEAT_AVX512BF16        (1ULL << 35)
%define FEAT_AVX512FP16        (1ULL << 36)
%define FEAT_GFNI              (1ULL << 37)
%define FEAT_VAES              (1ULL << 38)
%define FEAT_VPCLMULQDQ        (1ULL << 39)
%define FEAT_MOVDIRI           (1ULL << 40)
%define FEAT_ENQCMD            (1ULL << 41)
%define FEAT_SERIALIZE         (1ULL << 42)
%define FEAT_CLDEMOTE          (1ULL << 43)
%define FEAT_PREFETCHI         (1ULL << 44)
%define FEAT_AVX_VNNI          (1ULL << 45)
%define FEAT_AVX_VNNI_INT8     (1ULL << 46)
%define FEAT_APX               (1ULL << 47)

; ============================================================================
; CPU FEATURE BITS (AARCH64)
; ============================================================================
%define FEAT_SVE               (1ULL << 0)
%define FEAT_SVE2              (1ULL << 1)
%define FEAT_SME               (1ULL << 2)
%define FEAT_MTE               (1ULL << 3)
%define FEAT_BTI               (1ULL << 4)
%define FEAT_PAUTH             (1ULL << 5)
%define FEAT_LSE               (1ULL << 6)
%define FEAT_LSE128            (1ULL << 7)
%define FEAT_RME               (1ULL << 8)
%define FEAT_TME               (1ULL << 9)
%define FEAT_WFxT              (1ULL << 10)
%define FEAT_HBC               (1ULL << 11)
%define FEAT_CSSC              (1ULL << 12)
%define FEAT_RCPC              (1ULL << 13)
%define FEAT_DPB               (1ULL << 14)
%define FEAT_JSCVT             (1ULL << 15)
%define FEAT_FCMA              (1ULL << 16)
%define FEAT_RDM               (1ULL << 17)
%define FEAT_DOTPROD           (1ULL << 18)
%define FEAT_SHA3              (1ULL << 19)
%define FEAT_SM3               (1ULL << 20)
%define FEAT_SM4               (1ULL << 21)
%define FEAT_SHA512            (1ULL << 22)
%define FEAT_FP16              (1ULL << 23)
%define FEAT_BF16              (1ULL << 24)
%define FEAT_I8MM              (1ULL << 25)
%define FEAT_F32MM             (1ULL << 26)
%define FEAT_F64MM             (1ULL << 27)

; ============================================================================
; CPU FEATURE BITS (RISC-V)
; ============================================================================
%define FEAT_ZBA               (1ULL << 0)
%define FEAT_ZBB               (1ULL << 1)
%define FEAT_ZBC               (1ULL << 2)
%define FEAT_ZBS               (1ULL << 3)
%define FEAT_ZBKB              (1ULL << 4)
%define FEAT_ZBKC              (1ULL << 5)
%define FEAT_ZBKX              (1ULL << 6)
%define FEAT_ZKND              (1ULL << 7)
%define FEAT_ZKNE              (1ULL << 8)
%define FEAT_ZKNH              (1ULL << 9)
%define FEAT_ZKSED             (1ULL << 10)
%define FEAT_ZKSH              (1ULL << 11)
%define FEAT_ZKR               (1ULL << 12)
%define FEAT_ZKT               (1ULL << 13)
%define FEAT_ZIHINTPAUSE       (1ULL << 14)
%define FEAT_ZICOND            (1ULL << 15)
%define FEAT_ZICBOM            (1ULL << 16)
%define FEAT_ZICBOP            (1ULL << 17)
%define FEAT_ZICBOZ            (1ULL << 18)
%define FEAT_ZACAS             (1ULL << 19)
%define FEAT_ZAWRS             (1ULL << 20)
%define FEAT_ZFA               (1ULL << 21)
%define FEAT_ZFH               (1ULL << 22)
%define FEAT_ZFHMIN            (1ULL << 23)
%define FEAT_ZDINX             (1ULL << 24)
%define FEAT_ZHINX             (1ULL << 25)
%define FEAT_ZHINXMIN          (1ULL << 26)
%define FEAT_ZCE               (1ULL << 27)
%define FEAT_ZMMUL             (1ULL << 28)
%define FEAT_ZVBB              (1ULL << 29)
%define FEAT_ZVBC              (1ULL << 30)
%define FEAT_ZVKG              (1ULL << 31)
%define FEAT_ZVKNED            (1ULL << 32)
%define FEAT_ZVKNHA            (1ULL << 33)
%define FEAT_ZVKNHB            (1ULL << 34)
%define FEAT_ZVKSED            (1ULL << 35)
%define FEAT_ZVKSH             (1ULL << 36)
%define FEAT_ZVKT              (1ULL << 37)

; ============================================================================
; INSTRUCTION FLAGS
; ============================================================================

%define F_VEX                  (1 << 0)    ; uses VEX encoding
%define F_EVEX                 (1 << 1)    ; uses EVEX encoding
%define F_MODRM                (1 << 2)    ; requires ModRM byte
%define F_REX                  (1 << 3)    ; requires REX prefix in 64-bit
%define F_MMX                  (1 << 4)    ; uses MMX registers
%define F_XMM                  (1 << 5)    ; uses XMM/SSE registers
%define F_FPU                  (1 << 6)    ; uses x87 FPU registers
%define F_LOCK                 (1 << 7)    ; supports LOCK prefix

%define F_REP                  (1 << 8)    ; supports REP prefix (MOVSB/STOSB, etc.)
%define F_REPNE                (1 << 9)    ; supports REPNE/REPNZ prefix (SCASB, etc.)
%define F_PRIV                 (1 << 10)   ; privileged Ring 0 instructions (LGDT, HLT, etc.)
%define F_SMM                  (1 << 11)   ; only executable in System Management Mode (RSM)
%define F_NO64                 (1 << 12)   ; invalid in 64-bit mode (DAA, AAA, PUSH DS, etc.)
%define F_ONLY64               (1 << 13)   ; only executable in 64-bit mode (SWAPGS, etc.)
%define F_DEFAULT64            (1 << 14)   ; operand size defaults to 64-bit without REX prefix
%define F_FORCE64              (1 << 15)   ; operand size is strictly 64-bit, prefixes ignored
%define F_VSIB                 (1 << 16)   ; uses Vector SIB memory addressing
%define F_BROADCAST            (1 << 17)   ; supports EVEX embedded broadcasting
%define F_MASK                 (1 << 18)   ; supports EVEX masking ({k1})
%define F_SAE                  (1 << 19)   ; supports embedded Suppress All Exceptions ({sae})
%define F_ROUNDING             (1 << 20)   ; supports EVEX embedded rounding ({rn-sae})
%define F_ZMM                  (1 << 21)   ; instruction requires 512-bit ZMM registers (implies EVEX)
%define F_YMM                  (1 << 22)   ; instruction uses 256-bit YMM registers
%define F_NEAR                 (1 << 23)   ; instruction represents a NEAR branch target
%define F_SHORT                (1 << 24)   ; instruction represents a SHORT branch target
%define F_IMPLICIT_LOCK        (1 << 25)   ; atomic operations that implicitly lock (e.g. XCHG)
%define F_BRANCH               (1 << 26)   ; branch control instruction
%define F_CALL                 (1 << 27)   ; call control instruction
%define F_RET                  (1 << 28)   ; return control instruction

; ============================================================================
; OPERAND SIZES (BITS)
; ============================================================================

%define SZ_8                   8
%define SZ_16                  16
%define SZ_32                  32
%define SZ_64                  64
%define SZ_80                  80          ; x87 FPU 80-bit extended float size
%define SZ_128                 128
%define SZ_256                 256
%define SZ_512                 512
%define SZ_48                  48          ; FPU environment size (SGDT/SIDT 6-byte limit)
%define SZ_28                  28          ; x87 FPU state size
%define SZ_108                 108         ; x87 FXSAVE FPU state size

; ============================================================================
; TARGET ARCHITECTURE IDENTIFIERS
; ============================================================================
; Numeric identifiers for supported instruction set architectures.
; Used by conditional assembly and target-specific code generation paths.

%define TARGET_AARCH64         1           ; ARM 64-bit architecture
%define TARGET_AMD64           2           ; x86-64 architecture
%define TARGET_RISCV64         3           ; RISC-V 64-bit architecture

; ============================================================================
; OUTPUT FORMAT IDENTIFIERS
; ============================================================================
; Determines the binary format written by the assembler and linker.

%define FMT_ELF64              1           ; ELF64 dynamic executable
%define FMT_BIN                2           ; flat raw binary (no metadata)
%define FMT_PE32PLUS           3           ; PE32+ (UEFI image format)
%define FMT_UPK                4           ; Sovereign package distribution (.upk)
%define FMT_ELF64_OBJ          5           ; relocatable ELF64 object (.o)
%define FMT_ELF64_SO           6           ; dynamic shared object (.so)
%define FMT_MACHO64            7           ; Mach-O 64-bit executable format
%define FMT_TEF                8           ; Terse Executable Format
%define FMT_COFF               9           ; Common Object File Format

; ============================================================================
; OPTIMIZATION LEVELS
; ============================================================================
; Controls the aggressiveness of assembler and linker optimizations.

%define OPT_NONE               0           ; no optimizations applied
%define OPT_BASIC              1           ; basic peephole and dead code removal
%define OPT_SIZE               2           ; optimize strictly for binary size (prefer short forms)
%define OPT_SPEED              3           ; optimize strictly for execution speed
%define OPT_FULL               4           ; execute all optimization sweeps
%define OPT_AGGRESSIVE         5           ; maximum aggressive cross-section optimization

; ============================================================================
; LOG LEVELS
; ============================================================================
; Severity classification for diagnostic and debug messages.
; Higher values indicate more critical conditions.

%define LOG_DEBUG              0           ; verbose internal state tracing
%define LOG_INFO               1           ; informational progress messages
%define LOG_WARN               2           ; potential problem detected
%define LOG_ERROR              3           ; recoverable error occurred
%define LOG_FATAL              4           ; unrecoverable error, termination imminent
%define LOG_TRACE              5           ; ultra-verbose dynamic instruction tracing

; ============================================================================
; STANDARD FILE DESCRIPTORS
; ============================================================================
; Numeric handles for the default I/O streams available to every process.

%define STDIN_FILENO           0           ; standard input stream
%define STDOUT_FILENO          1           ; standard output stream
%define STDERR_FILENO          2           ; standard error stream

; ============================================================================
; SYSTEM CALL NUMBERS (AMD64 HOST)
; ============================================================================
; Trap numbers for invoking host platform services on AMD64.
; Prefixed by architecture to allow future multi-arch support without collision.
; These are used only by the bootstrap host binary, not by target output code.

%define AMD64_SYS_READ         0           ; read from file descriptor
%define AMD64_SYS_WRITE        1           ; write to file descriptor
%define AMD64_SYS_OPEN         2           ; open or create file
%define AMD64_SYS_CLOSE        3           ; close file descriptor
%define AMD64_SYS_STAT         4           ; get file status by path
%define AMD64_SYS_FSTAT        5           ; get file status by descriptor
%define AMD64_SYS_LSEEK        8           ; reposition file offset
%define AMD64_SYS_MMAP         9           ; map file or memory into address space
%define AMD64_SYS_MUNMAP       11          ; unmap memory region
%define AMD64_SYS_BRK          12          ; adjust program break (heap end)
%define AMD64_SYS_FTRUNCATE    77          ; change file size
%define AMD64_SYS_EXIT         60          ; terminate current process
%define AMD64_SYS_EXIT_GROUP   231         ; terminate all threads in process group

; ============================================================================
; FILE ACCESS FLAGS (AMD64 HOST)
; ============================================================================
; Bit flags controlling file open behavior on the AMD64 host platform.
; Combined with bitwise OR when invoking the open system call.

%define AMD64_O_RDONLY         0           ; open for read-only access
%define AMD64_O_WRONLY         1           ; open for write-only access
%define AMD64_O_RDWR           2           ; open for read-write access
%define AMD64_O_CREAT          64          ; create file if it does not exist
%define AMD64_O_TRUNC          512         ; truncate existing file to zero length

; ============================================================================
; MEMORY PROTECTION FLAGS
; ============================================================================
; Access permission bits for memory-mapped regions.
; Used when allocating or modifying virtual memory pages.

%define PROT_NONE              0           ; no access permitted
%define PROT_READ              1           ; read access permitted
%define PROT_WRITE             2           ; write access permitted
%define PROT_EXEC              4           ; execute access permitted
%define PROT_GROWSDOWN         0x01000000  ; page can grow downwards (stack boundary)
%define PROT_GROWSUP           0x02000000  ; page can grow upwards
%define PROT_SEM               0x8         ; page contains semaphores

; ============================================================================
; MEMORY MAPPING FLAGS
; ============================================================================
; Behavior modifiers for memory mapping operations.
; Combined with bitwise OR when invoking mmap.

%define MAP_SHARED             1           ; modifications visible to other mappings
%define MAP_PRIVATE            2           ; modifications are private copy-on-write
%define MAP_ANONYMOUS          0x20        ; mapping not backed by any file
%define MAP_FIXED              0x10        ; force mapping at requested address
%define MAP_32BIT              0x40        ; allocate in first 2GB of virtual address space
%define MAP_FAILED             -1          ; mapping failure return value
%define MAP_STACK              0x20000     ; allocate stack region mapping
%define MAP_HUGETLB            0x40000     ; use huge TLB pages
%define MAP_HUGE_2MB           (21 << 26)  ; 2MB huge page size selection
%define MAP_HUGE_1GB           (30 << 26)  ; 1GB huge page size selection
%define MAP_LOCKED             0x2000      ; lock pages into physical memory
%define MAP_NORESERVE          0x4000      ; do not reserve swap space
%define MAP_POPULATE           0x8000      ; pre-populate page tables (read-ahead)
%define MAP_NONBLOCK           0x10000     ; do not block I/O operations
%define MAP_SYNC               0x80000     ; flush metadata sync on write
%define MAP_FILE               0           ; file-backed mapping flag

; ============================================================================
; ERROR RETURN CODES (ERRNO VALUES)
; ============================================================================
; Standard numeric codes returned by system calls on failure.
; These match the conventional errno numbering used by the host platform.

%define EPERM                  1           ; operation not permitted
%define ENOENT                 2           ; no such file or directory
%define ESRCH                  3           ; no such process
%define EINTR                  4           ; interrupted system call
%define EIO                    5           ; input/output error
%define ENXIO                  6           ; no such device or address
%define ENOEXEC                8           ; Exec format error
%define EBADF                  9           ; bad file descriptor
%define EAGAIN                 11          ; try again / resource temporarily unavailable
%define ENOMEM                 12          ; cannot allocate memory
%define EACCES                 13          ; permission denied
%define EFAULT                 14          ; bad address pointer
%define EBUSY                  16          ; device or resource busy
%define EEXIST                 17          ; file already exists
%define EXDEV                  18          ; cross-device link
%define ENODEV                 19          ; no such device
%define ENOTDIR                20          ; not a directory
%define EISDIR                 21          ; is a directory
%define EINVAL                 22          ; invalid argument
%define ENFILE                 23          ; file table overflow
%define EMFILE                 24          ; too many open files
%define ENOTTY                 25          ; not a typewriter
%define ETXTBSY                26          ; text file busy
%define EFBIG                  27          ; file too large
%define ENOSPC                 28          ; no space left on device
%define ESPIPE                 29          ; illegal seek
%define EROFS                  30          ; read-only file system
%define EPIPE                  32          ; broken pipe
%define ERANGE                 34          ; math result out of range

; ============================================================================
; MEMORY ALIGNMENT
; ============================================================================
; Fundamental page and alignment constants for memory management.

%define PAGE_SIZE              4096        ; default virtual memory page size in bytes
%define HUGE_PAGE_SIZE         2097152     ; default 2MB huge page size

; ============================================================================
; ELF64 MAGIC AND IDENTIFICATION
; ============================================================================
; Bytes and indices for the ELF file header identification array.
; EI_MAG0 through EI_MAG3 spell the magic number 0x7F 'E' 'L' 'F'.

%define ELFMAG0                0x7F        ; magic byte 0
%define ELFMAG1                0x45        ; magic byte 1 ('E')
%define ELFMAG2                0x4C        ; magic byte 2 ('L')
%define ELFMAG3                0x46        ; magic byte 3 ('F')
%define ELFCLASS64             2           ; 64-bit object class
%define ELFDATA2LSB            1           ; little-endian data encoding

; ---- ELF e_ident[] array indices ---------

%define EI_MAG0                0           ; offset of first magic byte
%define EI_MAG1                1           ; offset of second magic byte
%define EI_MAG2                2           ; offset of third magic byte
%define EI_MAG3                3           ; offset of fourth magic byte
%define EI_CLASS               4           ; offset of file class field
%define EI_DATA                5           ; offset of data encoding field
%define EI_VERSION             6           ; offset of ELF version field
%define EI_OSABI               7           ; offset of OS/ABI identification field
%define EI_NIDENT              16          ; total size of e_ident[] array

; ---- ELF OSABI Identifiers ----
%define ELFOSABI_NONE          0           ; UNIX System V ABI
%define ELFOSABI_SYSV          0           ; alias for System V
%define ELFOSABI_LINUX         3           ; GNU/Linux ABI
%define ELFOSABI_FREEBSD       9           ; FreeBSD ABI
%define ELFOSABI_NETBSD        2           ; NetBSD ABI
%define ELFOSABI_OPENBSD       12          ; OpenBSD ABI
%define ELFOSABI_SOLARIS       6           ; Sun Solaris ABI

; ---- ELF Note segment types ----
%define NT_GNU_ABI_TAG         1           ; ABI tag note
%define NT_GNU_HWCAP           2           ; hardware capabilities note
%define NT_GNU_BUILD_ID        3           ; build ID note
%define NT_GNU_GOLD_VERSION    4           ; gold linker version note
%define NT_GNU_PROPERTY_TYPE_0 5           ; GNU program property note

; ---- GNU Property Segment Types ----
%define GNU_PROPERTY_STACK_SIZE            1
%define GNU_PROPERTY_NO_COPY_ON_PROTECTED  2
%define GNU_PROPERTY_X86_FEATURE_1_AND     0xc0000002
%define GNU_PROPERTY_X86_FEATURE_1_IBT     (1 << 0)
%define GNU_PROPERTY_X86_FEATURE_1_SHSTK   (1 << 1)
%define GNU_PROPERTY_X86_FEATURE_1_LAM_U48 (1 << 2)
%define GNU_PROPERTY_X86_FEATURE_1_LAM_U57 (1 << 3)

; ============================================================================
; ELF64 VERSION
; ============================================================================

%define EV_NONE                0           ; invalid ELF version
%define EV_CURRENT             1           ; current ELF version identifier

; ============================================================================
; ELF64 OBJECT TYPES
; ============================================================================
; Classification of ELF object files.

%define ET_REL                 1           ; relocatable file
%define ET_EXEC                2           ; executable file
%define ET_DYN                 3           ; shared library object
%define ET_CORE                4           ; core dump file

; ============================================================================
; ELF64 MACHINE TYPES
; ============================================================================
; Architecture identifiers stored in the ELF header e_machine field.

%define EM_386                 3           ; Intel 80386 (32-bit x86)
%define EM_ARM                 40          ; ARM (32-bit)
%define EM_X86_64              62          ; AMD64 / x86-64
%define EM_AARCH64             183         ; ARM AArch64 (64-bit)
%define EM_RISCV               243         ; RISC-V 64-bit

; ============================================================================
; ELF64 SECTION HEADER TYPES
; ============================================================================
; Types of sections contained in an ELF object file.

%define SHT_NULL               0           ; inactive section header
%define SHT_PROGBITS           1           ; program-defined data and code
%define SHT_SYMTAB             2           ; symbol table
%define SHT_STRTAB             3           ; string table
%define SHT_RELA               4           ; relocation entries with explicit addends
%define SHT_HASH               5           ; symbol hash table section
%define SHT_DYNAMIC            6           ; dynamic linking information metadata
%define SHT_NOTE               7           ; note section (ABI tags, etc.)
%define SHT_NOBITS             8           ; uninitialized data (BSS)
%define SHT_REL                9           ; relocation entries without addends
%define SHT_DYNSYM             11          ; dynamic symbol table
%define SHT_INIT_ARRAY         14          ; array of constructor pointers
%define SHT_FINI_ARRAY         15          ; array of destructor pointers
%define SHT_PREINIT_ARRAY      16          ; array of pre-constructor pointers
%define SHT_GROUP              17          ; section group member container

; ---- Section Group Flags ----
%define GRP_COMDAT             0x1         ; COMDAT group

; ============================================================================
; ELF64 SECTION FLAGS
; ============================================================================
; Attribute bits describing section permissions and memory behavior.

%define SHF_WRITE              0x1         ; section contains writable data
%define SHF_ALLOC              0x2         ; section occupies memory at runtime
%define SHF_EXECINSTR          0x4         ; section contains executable instructions
%define SHF_MERGE              0x10        ; data can be merged to eliminate redundancy
%define SHF_STRINGS            0x20        ; section contains null-terminated strings
%define SHF_INFO_LINK          0x40        ; sh_info holds section header table index
%define SHF_LINK_ORDER         0x80        ; special link order requirements
%define SHF_OS_NONCONFORMING   0x100       ; non-standard OS-specific handling needed
%define SHF_GROUP              0x200       ; section is a member of a SHT_GROUP
%define SHF_TLS                0x400       ; section holds thread-local storage data
%define SHF_COMPRESSED         0x800       ; section data is compressed

; ============================================================================
; ELF64 PROGRAM HEADER TYPES
; ============================================================================
%define PT_NULL                0
%define PT_LOAD                1
%define PT_DYNAMIC             2
%define PT_INTERP              3
%define PT_NOTE                4
%define PT_SHLIB               5
%define PT_PHDR                6
%define PT_TLS                 7           ; thread-local storage segment
%define PT_GNU_EH_FRAME        0x6474e550  ; exception handling frame segment
%define PT_GNU_STACK           0x6474e551  ; stack executability flag segment
%define PT_GNU_RELRO           0x6474e552  ; read-only segment after relocations

; ============================================================================
; ELF64 PROGRAM HEADER FLAGS
; ============================================================================
; Permission bits for loadable segments.

%define PF_X                   0x1         ; execute permission
%define PF_W                   0x2         ; write permission
%define PF_R                   0x4         ; read permission

; ============================================================================
; ELF64 SYMBOL TABLE BINDINGS
; ============================================================================
; Visibility scope of symbols within and across object files.

%define STB_LOCAL              0           ; visible only within defining file
%define STB_GLOBAL             1           ; visible to all linked files
%define STB_WEAK               2           ; weak linkage binding (preemptable)

; ============================================================================
; ELF64 SYMBOL TABLE TYPES
; ============================================================================
; Classification of symbol semantics.

%define STT_NOTYPE             0           ; unspecified symbol type
%define STT_OBJECT             1           ; data object (variable, array, etc.)
%define STT_FUNC               2           ; function or executable code
%define STT_SECTION            3           ; associated with a section header
%define STT_FILE               4           ; source file name symbol
%define STT_COMMON             5           ; uninitialized common block symbol
%define STT_TLS                6           ; thread-local storage data object

; ---- Symbol Visibility (st_other field) ----
%define STV_DEFAULT            0           ; default visibility
%define STV_INTERNAL           1           ; processor-specific hidden visibility
%define STV_HIDDEN             2           ; hidden visibility (not exportable)
%define STV_PROTECTED          3           ; visible but cannot be overridden

; ============================================================================
; ELF64 SPECIAL SECTION INDICES
; ============================================================================
; Reserved section index values with special meaning.

%define SHN_UNDEF              0           ; undefined or external symbol
%define SHN_ABS                0xFFF1      ; absolute symbol reference
%define SHN_COMMON             0xFFF2      ; common symbol block reference
%define SHN_XINDEX             0xFFFF      ; escape value for large indices

; ============================================================================
; UTASM HOST MEMORY LAYOUT
; ============================================================================
; Address space configuration for the utasm process itself.
; UTASM_HEAP_BASE is an advisory hint passed to the memory allocator.
; The system may place the heap at a different address; this value merely
; suggests a preferred region. Do not assume the heap begins exactly here.

%define UTASM_HEAP_BASE        0x10000000  ; preferred heap region start address
%define UTASM_HEAP_SIZE        0x10000000  ; maximum heap reservation (256 MiB)
%define UTASM_STACK_SIZE       0x100000    ; default stack allocation (1 MiB)

; ============================================================================
; ARCHITECTURAL REGISTERS (AMD64)
; ============================================================================
%define REG_RIP                0xFE        ; special identifier for RIP
%define REG_NONE               0xFF        ; sentinel for "no register"

; ============================================================================
; AMD64 RELOCATION TYPES (Standard ELF)
; ============================================================================

%define R_X86_64_NONE          0
%define R_X86_64_64            1
%define R_X86_64_PC32          2
%define R_X86_64_GOT32         3
%define R_X86_64_PLT32         4
%define R_X86_64_COPY          5
%define R_X86_64_GLOB_DAT      6
%define R_X86_64_JUMP_SLOT     7
%define R_X86_64_RELATIVE      8
%define R_X86_64_GOTPCREL      9
%define R_X86_64_32            10
%define R_X86_64_32S           11
%define R_X86_64_16            12
%define R_X86_64_PC16          13
%define R_X86_64_8             14
%define R_X86_64_PC8           15

; ---- AMD64 Thread-Local & Advanced Relocations ----
%define R_X86_64_DTPMOD64      16
%define R_X86_64_DTPOFF64      17
%define R_X86_64_TPOFF64       18
%define R_X86_64_TLSGD         19
%define R_X86_64_TLSLD         20
%define R_X86_64_DTPOFF32      21
%define R_X86_64_GOTTPOFF      22
%define R_X86_64_TPOFF32       23
%define R_X86_64_PC64          24
%define R_X86_64_GOTOFF64      25
%define R_X86_64_GOTPC32       26
%define R_X86_64_SIZE32        32
%define R_X86_64_SIZE64        33
%define R_X86_64_GOTPC32_TLSDESC 34
%define R_X86_64_TLSDESC_CALL  35
%define R_X86_64_TLSDESC       36
%define R_X86_64_IRELATIVE     37
%define R_X86_64_GOTPCRELX     41
%define R_X86_64_REX_GOTPCRELX 42

; ---- Backward compatibility aliases ----
%define RELOC_ABS64            R_X86_64_64
%define RELOC_REL32            R_X86_64_PC32
%define RELOC_ABS64_LEGACY     1           ; maps to R_X86_64_64 (formerly RELOC_REL64)
%define RELOC_GOT              R_X86_64_GOT32
%define RELOC_REL8             R_X86_64_PC8

; ============================================================================
; AARCH64 RELOCATION TYPES
; ============================================================================
%define R_AARCH64_NONE                0
%define R_AARCH64_ABS64                257
%define R_AARCH64_ABS32                258
%define R_AARCH64_ABS16                259
%define R_AARCH64_ADR_PREL_LO21        274
%define R_AARCH64_ADR_PREL_PG_HI21     275
%define R_AARCH64_ADD_ABS_LO12_NC      277
%define R_AARCH64_JUMP26               282
%define R_AARCH64_CALL26               283
%define R_AARCH64_LDST8_ABS_LO12_NC    278
%define R_AARCH64_LDST16_ABS_LO12_NC   284
%define R_AARCH64_LDST32_ABS_LO12_NC   285
%define R_AARCH64_LDST64_ABS_LO12_NC   286

; ============================================================================
; RISC-V RELOCATION TYPES
; ============================================================================
%define R_RISCV_NONE           0
%define R_RISCV_32             1
%define R_RISCV_64             2
%define R_RISCV_RELATIVE       3
%define R_RISCV_COPY           4
%define R_RISCV_JUMP_SLOT      5
%define R_RISCV_TLS_DTPMOD32   6
%define R_RISCV_TLS_DTPMOD64   7
%define R_RISCV_TLS_DTPREL32   8
%define R_RISCV_TLS_DTPREL64   9
%define R_RISCV_TLS_TPREL32    10
%define R_RISCV_TLS_TPREL64    11
%define R_RISCV_BRANCH         16
%define R_RISCV_JAL            17
%define R_RISCV_CALL           18
%define R_RISCV_CALL_PLT       19
%define R_RISCV_CALL_HI20      18   ; alias for R_RISCV_CALL (auipc upper 20 bits)
%define R_RISCV_CALL_LO12      19   ; alias for R_RISCV_CALL_PLT (jalr lower 12 bits)
%define R_RISCV_GOT_EDI        20
%define R_RISCV_GNU_PLT_IREL   22
%define R_RISCV_PCREL_HI20     23
%define R_RISCV_PCREL_LO12_I   24
%define R_RISCV_PCREL_LO12_S   25
%define R_RISCV_HI20           26
%define R_RISCV_LO12_I         27
%define R_RISCV_LO12_S         28
%define R_RISCV_RELAX          51

; ============================================================================
; REGISTER IDENTIFIERS
; ============================================================================
; Internal numeric identifiers for architectural registers mapped by the compiler.

; ---- AMD64 general-purpose registers (GPR indices) ----
%define REG_RAX                0
%define REG_RCX                1
%define REG_RDX                2
%define REG_RBX                3
%define REG_RSP                4
%define REG_RBP                5
%define REG_RSI                6
%define REG_RDI                7

; ---- Extended AMD64 general-purpose registers ----
%define REG_R8                 8
%define REG_R9                 9
%define REG_R10                10
%define REG_R11                11
%define REG_R12                12
%define REG_R13                13
%define REG_R14                14
%define REG_R15                15

; ---- AMD64 Segment registers ----
%define REG_CS                 16
%define REG_DS                 17
%define REG_ES                 18
%define REG_FS                 19
%define REG_GS                 20
%define REG_SS                 21

; ---- AMD64 Control registers ----
%define REG_CR0                22
%define REG_CR2                23
%define REG_CR3                24
%define REG_CR4                25
%define REG_CR8                26

; ---- AMD64 Debug registers ----
%define REG_DR0                27
%define REG_DR1                28
%define REG_DR2                29
%define REG_DR3                30
%define REG_DR6                31
%define REG_DR7                32

; ---- AMD64 x87 FPU stack registers ----
%define REG_ST0                33
%define REG_ST1                34
%define REG_ST2                35
%define REG_ST3                36
%define REG_ST4                37
%define REG_ST5                38
%define REG_ST6                39
%define REG_ST7                40

; ---- AMD64 MMX registers ----
%define REG_MM0                41
%define REG_MM1                42
%define REG_MM2                43
%define REG_MM3                44
%define REG_MM4                45
%define REG_MM5                46
%define REG_MM6                47
%define REG_MM7                48

; ---- AMD64 XMM registers (128-bit SIMD) ----
%define REG_XMM0               50
%define REG_XMM1               51
%define REG_XMM2               52
%define REG_XMM3               53
%define REG_XMM4               54
%define REG_XMM5               55
%define REG_XMM6               56
%define REG_XMM7               57
%define REG_XMM8               58
%define REG_XMM9               59
%define REG_XMM10              60
%define REG_XMM11              61
%define REG_XMM12              62
%define REG_XMM13              63
%define REG_XMM14              64
%define REG_XMM15              65
%define REG_XMM16              66
%define REG_XMM17              67
%define REG_XMM18              68
%define REG_XMM19              69
%define REG_XMM20              70
%define REG_XMM21              71
%define REG_XMM22              72
%define REG_XMM23              73
%define REG_XMM24              74
%define REG_XMM25              75
%define REG_XMM26              76
%define REG_XMM27              77
%define REG_XMM28              78
%define REG_XMM29              79
%define REG_XMM30              80
%define REG_XMM31              81

; ---- AMD64 YMM registers (256-bit SIMD) ----
%define REG_YMM0               82
%define REG_YMM1               83
%define REG_YMM2               84
%define REG_YMM3               85
%define REG_YMM4               86
%define REG_YMM5               87
%define REG_YMM6               88
%define REG_YMM7               89
%define REG_YMM8               90
%define REG_YMM9               91
%define REG_YMM10              92
%define REG_YMM11              93
%define REG_YMM12              94
%define REG_YMM13              95
%define REG_YMM14              96
%define REG_YMM15              97
%define REG_YMM16              98
%define REG_YMM17              99
%define REG_YMM18              100
%define REG_YMM19              101
%define REG_YMM20              102
%define REG_YMM21              103
%define REG_YMM22              104
%define REG_YMM23              105
%define REG_YMM24              106
%define REG_YMM25              107
%define REG_YMM26              108
%define REG_YMM27              109
%define REG_YMM28              110
%define REG_YMM29              111
%define REG_YMM30              112
%define REG_YMM31              113

; ---- AMD64 ZMM registers (512-bit SIMD) ----
%define REG_ZMM0               115
%define REG_ZMM1               116
%define REG_ZMM2               117
%define REG_ZMM3               118
%define REG_ZMM4               119
%define REG_ZMM5               120
%define REG_ZMM6               121
%define REG_ZMM7               122
%define REG_ZMM8               123
%define REG_ZMM9               124
%define REG_ZMM10              125
%define REG_ZMM11              126
%define REG_ZMM12              127
%define REG_ZMM13              128
%define REG_ZMM14              129
%define REG_ZMM15              130
%define REG_ZMM16              131
%define REG_ZMM17              132
%define REG_ZMM18              133
%define REG_ZMM19              134
%define REG_ZMM20              135
%define REG_ZMM21              136
%define REG_ZMM22              137
%define REG_ZMM23              138
%define REG_ZMM24              139
%define REG_ZMM25              140
%define REG_ZMM26              141
%define REG_ZMM27              142
%define REG_ZMM28              143
%define REG_ZMM29              144
%define REG_ZMM30              145
%define REG_ZMM31              146

; ---- AMD64 Mask registers (k0-k7) ----
%define REG_K0                 148
%define REG_K1                 149
%define REG_K2                 150
%define REG_K3                 151
%define REG_K4                 152
%define REG_K5                 153
%define REG_K6                 154
%define REG_K7                 155

; ---- AMD64 AMX Tile registers ----
%define REG_TMM0               157
%define REG_TMM1               158
%define REG_TMM2               159
%define REG_TMM3               160
%define REG_TMM4               161
%define REG_TMM5               162
%define REG_TMM6               163
%define REG_TMM7               164

; ---- AMD64 MPX Bound registers ----
%define REG_BND0               165
%define REG_BND1               166
%define REG_BND2               167
%define REG_BND3               168

; ---- AArch64 general-purpose and system registers ----
%define REG_X0                 170
%define REG_X1                 171
%define REG_X2                 172
%define REG_X3                 173
%define REG_X4                 174
%define REG_X5                 175
%define REG_X6                 176
%define REG_X7                 177
%define REG_X8                 178
%define REG_X9                 179
%define REG_X10                180
%define REG_X11                181
%define REG_X12                182
%define REG_X13                183
%define REG_X14                184
%define REG_X15                185
%define REG_X16                186
%define REG_X17                187
%define REG_X18                188
%define REG_X19                189
%define REG_X20                190
%define REG_X21                191
%define REG_X22                192
%define REG_X23                193
%define REG_X24                194
%define REG_X25                195
%define REG_X26                196
%define REG_X27                197
%define REG_X28                198
%define REG_X29                199
%define REG_X30                200
%define REG_XZR                201
%define REG_XSP                202
%define REG_XLR                203

; ---- RISC-V general-purpose and system registers ----
%define REG_RV_X0              210
%define REG_RV_X1              211
%define REG_RV_X2              212
%define REG_RV_X3              213
%define REG_RV_X4              214
%define REG_RV_X5              215
%define REG_RV_X6              216
%define REG_RV_X7              217
%define REG_RV_X8              218
%define REG_RV_X9              219
%define REG_RV_X10             220
%define REG_RV_X11             221
%define REG_RV_X12             222
%define REG_RV_X13             223
%define REG_RV_X14             224
%define REG_RV_X15             225
%define REG_RV_X16             226
%define REG_RV_X17             227
%define REG_RV_X18             228
%define REG_RV_X19             229
%define REG_RV_X20             230
%define REG_RV_X21             231
%define REG_RV_X22             232
%define REG_RV_X23             233
%define REG_RV_X24             234
%define REG_RV_X25             235
%define REG_RV_X26             236
%define REG_RV_X27             237
%define REG_RV_X28             238
%define REG_RV_X29             239
%define REG_RV_X30             240
%define REG_RV_X31             241
%define REG_RV_ZERO            242
%define REG_RV_RA              243
%define REG_RV_SP              244
%define REG_RV_GP              245
%define REG_RV_TP              246

; ============================================================================
; LEXER CHARACTER PROPERTIES
; ============================================================================
%define CHAR_IS_DIGIT          0x01        ; 0-9
%define CHAR_IS_IDENT_START    0x02        ; a-zA-Z or underscore
%define CHAR_IS_IDENT_PART     0x04        ; alphanumeric or underscore
%define CHAR_IS_WHITESPACE     0x08        ; space, tab
%define CHAR_IS_HEX            0x10        ; hex digits

%define CHAR_IS_ALPHA          0x20        ; standard alphabet characters only (a-zA-Z)
%define CHAR_IS_OCTAL          0x40        ; octal digits (0-7)
%define CHAR_IS_BINARY         0x80        ; binary digits (0-1)
%define CHAR_IS_NEWLINE        0x100       ; \n \r
%define CHAR_IS_PUNCT          0x200       ; , + - * / [ ] etc.
%define CHAR_IS_QUOTE          0x400       ; single or double quote qualifiers (' ")
%define CHAR_IS_SPECIAL        0x800       ; preprocessor/comment modifiers (% ; # @)
%define CHAR_IS_PRINTABLE      0x1000      ; printable ASCII range (0x20 - 0x7E)

; ============================================================================
; ARENA ALLOCATOR CONSTANTS
; ============================================================================
%define ARENA_DEFAULT_SIZE     (64 * 1024 * 1024)  ; 64MB main arena capacity
%define ARENA_PASS_SIZE        (16 * 1024 * 1024)  ; 16MB per-pass transient workspace
%define ARENA_ALIGNMENT        16                  ; enforce strict 16-byte allocation boundary

; ============================================================================
; ERROR SYSTEM CONSTANTS
; ============================================================================
%define ERR_NONE               0           ; null error status
%define SEV_ERROR              0           ; hard compiler error severity
%define SEV_WARNING            1           ; compiler warning severity
%define SEV_NOTE               2           ; note severity
%define SEV_HINT               3           ; compiler suggestion hint severity
%define MAX_ERROR_MSG_LEN      256         ; absolute limit of diagnostic text output
%define MAX_HINT_MSG_LEN       256
%define MAX_NOTE_MSG_LEN       256
%define MAX_CHAIN_DEPTH        32          ; maximum nested macro expansion frame tracking
%define ERROR_DEDUP_TABLE_SIZE 1024        ; capacity of error de-duplication table

; ============================================================================
; HASH TABLE CONSTANTS
; ============================================================================
%define HASH_LOAD_MAX          75          ; load limit factor before triggering resizing
%define HASH_INIT_CAP          256         ; starting capacity of symbol lookup tables
%define HASH_DELETED           0xDEAD      ; tombstone sentinel for deleted entries

; ============================================================================
; MACRO ENGINE CONSTANTS
; ============================================================================
%define MACRO_MAX_BODY_TOKENS  4096        ; absolute token capacity in macro body expansion
%define MACRO_BODY_CAPACITY    1024        ; token slots reserved per %macro definition
%define REP_BODY_CAPACITY      256         ; token slots reserved per %rep execution
%define MACRO_ARG_CAPACITY     64          ; token slots reserved for one invocation's arguments
%define MACRO_FLAG_FUNC        0x01        ; %define NAME(a,b): arguments in parentheses
%define MACRO_FLAG_GREEDY      0x02        ; %macro m 1+: the last parameter takes the rest
%define DEFINE_MAX_TOKENS      256         ; tokens in one %define body
%define LEX_INTERP_BUF         256         ; work buffer for %[...] identifier interpolation
%define PREP_CTX_MAX           64          ; maximum nesting depth of %push contexts
%define MACRO_TABLE_INIT_CAP   128         ; starting capacity of macro parser maps

; ============================================================================
; ENCODING CONSTANTS (x86-64 REX/VEX/EVEX shifts & prefixes)
; ============================================================================

; ---- REX Prefix Bits ----
%define REX_BASE               0x40        ; core REX byte prefix value
%define REX_W                  0x48        ; REX.W operand size indicator (64-bit GPR)
%define REX_R                  0x44        ; REX.R extended reg field index
%define REX_X                  0x42        ; REX.X extended SIB index
%define REX_B                  0x41        ; REX.B extended ModRM.rm or base index

; ---- ModRM Field Shifts ----
%define MODRM_MOD_SHIFT        6
%define MODRM_REG_SHIFT        3
%define MODRM_RM_SHIFT         0

; ---- SIB Field Shifts ----
%define SIB_SS_SHIFT           6
%define SIB_INDEX_SHIFT        3
%define SIB_BASE_SHIFT         0

; ---- Special ModRM / SIB Indices ----
%define MODRM_RM_SIB           4           ; r/m index matching SIB indicator
%define MODRM_RM_DISP32        5           ; r/m index indicating absolute 32-bit displacement
%define MODRM_SIB_NO_INDEX     4           ; SIB index matching no-index register
%define MODRM_SIB_NO_BASE      5           ; SIB base index matching no-base register

; ---- VEX / EVEX Magic Byte Prefixes ----
%define VEX2_PREFIX            0xC5        ; 2-byte VEX prefix
%define VEX3_PREFIX            0xC4        ; 3-byte VEX prefix
%define EVEX_PREFIX            0x62        ; 4-byte EVEX prefix

; ---- VEX / EVEX pp fields (mandatory prefix bytes) ----
%define VEX_PP_NONE            0x00
%define VEX_PP_66              0x01
%define VEX_PP_F3              0x02
%define VEX_PP_F2              0x03

; ---- VEX / EVEX mm fields (implied escape bytes) ----
%define VEX_MM_0F              0x01
%define VEX_MM_0F38            0x02
%define VEX_MM_0F3A            0x03

; ---- EVEX Rounding & Exception control flags ----
%define EVEX_RC_RN             0x00        ; round nearest even
%define EVEX_RC_RD             0x01        ; round down (-inf)
%define EVEX_RC_RU             0x02        ; round up (+inf)
%define EVEX_RC_RZ             0x03        ; truncate/round toward zero

; ============================================================================
; DWARF V5 CONSTANTS
; ============================================================================
%define DWARF_VERSION                  5
%define DW_UT_compile                  0x01
%define DW_LANG_Mips_Assembler         0x8001
%define DW_TAG_compile_unit            0x11
%define DW_TAG_subprogram              0x2E
%define DW_TAG_variable                0x34
%define DW_TAG_base_type               0x24
%define DW_AT_producer                 0x25
%define DW_AT_language                 0x13
%define DW_AT_name                     0x03
%define DW_AT_comp_dir                 0x1B
%define DW_AT_low_pc                   0x11
%define DW_AT_high_pc                  0x12
%define DW_AT_stmt_list                0x10
%define DW_FORM_string                 0x08
%define DW_FORM_addr                   0x01
%define DW_FORM_data4                  0x06
%define DW_FORM_data8                  0x07
%define DW_FORM_sec_offset             0x17

; ============================================================================
; UPK SOVEREIGN PACKAGE FORMAT CONSTANTS
; ============================================================================
%define UPK_MAGIC              0x55504B21  ; "UPK!" magic marker
%define UPK_VERSION            1
%define UPK_MAX_NAME_LEN       128
%define UPK_MAX_DEP_COUNT      64
%define UPK_MAX_SECTION_COUNT  16
%define UPK_FLAG_COMPRESSED    0x01
%define UPK_FLAG_SIGNED        0x02
%define UPK_FLAG_EXECUTABLE    0x04

; ============================================================================
; DEBUG / MEMORY POISON CONSTANTS
; ============================================================================
%define POISON_FREED           0xDEADBEEFDEADBEEF  ; invalid use-after-free canary pattern
%define POISON_UNINIT          0xCDCDCDCDCDCDCDCD  ; uninitialized memory pattern
%define POISON_STACK           0xFEEEFEEEFEEEFEEE  ; stack buffer canary guard

; ============================================================================
; PROFILER CONSTANTS
; ============================================================================
; Type tags, phase identifiers, and thresholds for the RDTSC-based profiler.
; See docs/profiler_architecture.md for full design rationale.

; ── Profiler Type Tags ──
%define TAG_PROFENTRY          0x10        ; ProfileEntry struct identifier
%define TAG_PROFSTATE          0x11        ; ProfileState struct identifier

; ── Phase Identifiers ──
; Each phase maps to one slot in the PROFENTRY array.
; Values 0x01–0x08 are reserved for top-level pipeline phases.
; Values 0x09–0x3F are reserved for future sub-phase expansion.
%define PHASE_LEXER            0x01        ; frontend/lexer/* token scanning
%define PHASE_PREPROCESSOR     0x02        ; frontend/macro/* expansion
%define PHASE_PARSER           0x03        ; frontend/parser/* AST construction
%define PHASE_SEMANTIC         0x04        ; middle/semantic/* validation
%define PHASE_ENCODER          0x05        ; backend/encoder/* instruction encoding
%define PHASE_LINKER           0x06        ; backend/linker/* relocation + layout
%define PHASE_OUTPUT           0x07        ; backend/output/* binary emission
%define PHASE_TOTAL            0x08        ; virtual: entire pipeline (init → finalize)

; ── Limits ──
%define MAX_PROF_PHASES        8           ; total top-level phase slots
%define MAX_PROF_ENTRIES       64          ; max entries (8 phases + 56 sub-phases)
%define PROF_CALIB_ITERS       1024        ; calibration loop iteration count

; ── Thresholds ──
%define PROF_HOT_THRESHOLD     10000000    ; 10M cycles ≈ 3.3ms at 3GHz
%define PROF_WARN_THRESHOLD    50000000    ; 50M cycles ≈ 16.7ms at 3GHz (critical)

%endif
