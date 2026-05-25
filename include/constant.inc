%ifndef CONSTANT_S
%define CONSTANT_S

;
; ============================================
; File     : include/constant.s
; Project  : utasm
; Author   : Utkarsha Lab
; License  : Apache-2.0
; ============================================
;

; ============================================================================
; EXIT CODES
; ============================================================================
; Process termination status values passed to the system exit call.
; Valid range is strictly 0 through 125. Values 126 and 127 are reserved
; by the host command interpreter for its own errors. Values 128 and above
; are reserved by the platform for signal-based termination and must never
; be used as normal exit codes.

%define EXIT_OK                0   ; operation completed successfully
%define EXIT_ERROR             1   ; unspecified general failure
%define EXIT_USAGE             2   ; invalid command-line arguments or flags

%define EXIT_FILE_NOT_FOUND    3   ; requested input file does not exist
%define EXIT_FILE_PERM         4   ; insufficient permissions to access file
%define EXIT_FILE_READ         5   ; error occurred during file read operation
%define EXIT_FILE_WRITE        6   ; error occurred during file write operation
%define EXIT_INVALID_FORMAT    7   ; file format is invalid or unrecognized

%define EXIT_INC_NOT_FOUND     10  ; included file specified by source not found
%define EXIT_MACRO_DEF         11  ; malformed or illegal macro definition
%define EXIT_MACRO_EXP         12  ; failure during macro expansion phase
%define EXIT_MACRO_RECURSION   13  ; nested macro depth exceeded limit
%define EXIT_MACRO_ARITY_FAIL   14  ; wrong number of macro arguments
%define EXIT_DEFINE            15  ; invalid or malformed %define directive

%define EXIT_UNKNOWN_INSTR     20  ; mnemonic does not match any known instruction
%define EXIT_INVALID_OPERAND   21  ; operand syntax is not valid for instruction
%define EXIT_INVALID_REG       22  ; register name is unrecognized or illegal
%define EXIT_INVALID_IMM       23  ; immediate value format or content is invalid
%define EXIT_INVALID_ADDR      24  ; addressing mode expression is malformed
%define EXIT_UNEXPECTED_TOKEN  25  ; token encountered where none was expected
%define EXIT_UNEXPECTED_EOF    26  ; end of input reached before construct completed
%define EXIT_EXPR_TOO_DEEP     27  ; expression recursion depth exceeded limit
%define EXIT_INVALID_EXPR       28  ; expression syntax or evaluation error
%define EXIT_INVALID_SECTION_FLAGS 29 ; section flags are invalid or incompatible

%define EXIT_ENCODE_FAIL       30  ; instruction encoding could not be generated
%define EXIT_IMM_RANGE         31  ; immediate value exceeds allowed bit width
%define EXIT_OFFSET_RANGE      32  ; branch or memory offset exceeds range
%define EXIT_UNSUPPORTED_INSTR 33  ; valid instruction not supported by target
%define EXIT_ALIGN_ERROR       34  ; alignment directive could not be satisfied
%define EXIT_STRUCT_BOUNDS     35  ; memory write size exceeds struct field byte width

%define EXIT_UNDEF_SYMBOL      40  ; referenced symbol has no definition
%define EXIT_DUP_SYMBOL        41  ; symbol defined more than once
%define EXIT_SYMBOL_RANGE      42  ; symbol value exceeds representable range
%define EXIT_CIRCULAR_REF      43  ; circular dependency detected between symbols

%define EXIT_LD_SCRIPT_404     50  ; linker script file not found
%define EXIT_LD_SCRIPT_PARSE   51  ; linker script contains syntax errors
%define EXIT_SECTION_OVERLAP   52  ; two or more output sections occupy same address
%define EXIT_RELOC_ERROR       53  ; relocation could not be applied
%define EXIT_UNDEF_REF         54  ; symbol referenced but never defined
%define EXIT_MULTI_DEF         55          ; symbol defined in multiple input objects
%define EXIT_INVALID_SECTION   56          ; section index is out of bounds or invalid

%define EXIT_OUT_CREATE        60  ; failed to create output file
%define EXIT_ELF_WRITE         61  ; error writing ELF format output
%define EXIT_BIN_WRITE         62  ; error writing flat binary output

%define EXIT_QEMU_404          70  ; emulator binary not found in path
%define EXIT_QEMU_FAIL         71  ; emulator process exited with error

%define EXIT_INTERNAL          124 ; unrecoverable internal assembler error
%define EXIT_OOM               125 ; memory allocation request could not be fulfilled

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
%define MAX_LINE               1024        ; maximum source line length
%define MAX_TOKEN              256         ; maximum single token length
%define MAX_SYMBOL             65536       ; maximum entries in symbol table
%define MAX_SECTIONS           64          ; maximum ELF sections per object
%define MAX_INCLUDES           256         ; maximum nested include depth
%define MAX_MACRO_PARAMS       32          ; maximum parameters per macro
%define MAX_MACRO_DEPTH        64          ; maximum nested macro expansion depth
%define MAX_REP_COUNT          65536       ; maximum iterations per %rep block
%define MAX_ERRORS             50          ; fatal stop threshold for error count
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
%define BUF_LINE               1024        ; single line processing buffer
; 
; ; ============================================================================
; ; TYPE TAGS
; ; ============================================================================
; ; Every struct in utasm has a 1-byte type tag at offset 0.
; 
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
; 
; ; ============================================================================
; ; TOKEN TYPES
; ; ============================================================================
; 
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
%define TOK_COMMENT            0x21
%define TOK_FLOAT              0x22
%define TOK_MACRO_LOCAL        0x23
%define TOK_DOLLAR             0x24
%define TOK_EQUAL              0x25
%define TOK_NEQUAL             0x26
%define TOK_LT                 0x27
%define TOK_GT                 0x28
; 
%define OP_FLAG_REL            0x01
; 
; ; ============================================================================
; ; SYMBOL KINDS AND VISIBILITY
; ; ============================================================================
; 
%define SYM_UNKNOWN            0x00
%define SYM_LABEL              0x01
%define SYM_DATA               0x02
%define SYM_CONSTANT           0x03
%define SYM_MACRO              0x04
%define SYM_EXTERN             0x05
%define SYM_SECTION            0x06
%define SYM_STRUCT             0x07  ; a struc definition (name -> total_size)
%define SYM_STRUCT_FIELD       0x08  ; a struct field   (name -> offset, size = field byte width)
; 
%define VIS_LOCAL              0x00
%define VIS_GLOBAL             0x01
%define VIS_WEAK               0x02
; 
; ; ============================================================================
; ; SECTION TYPES
; ; ============================================================================
; 
%define SEC_TEXT               0x01
%define SEC_DATA               0x02
%define SEC_BSS                0x03
%define SEC_RODATA             0x04
%define SEC_CUSTOM             0x05
; 
; ; ============================================================================
; ; OPERAND KINDS
; ; ============================================================================
; 
%define OP_NONE                0x00
%define OP_REG                 0x01
%define OP_IMM                 0x02
%define OP_MEM                 0x03
%define OP_SYMBOL              0x04
; 
; ; ============================================================================
; ; CONTEXT FLAGS
; ; ============================================================================
; 
%define CTX_FLAG_DEBUG         0x01
%define CTX_FLAG_VERBOSE       0x02
%define CTX_FLAG_WERROR        0x04
%define CTX_FLAG_COLOR         0x08
%define CTX_FLAG_LISTING       0x10
%define CTX_FLAG_MAPFILE       0x20
%define CTX_FLAG_STRIP         0x40
%define CTX_FLAG_FORMAT_BIN    0x80
%define CTX_FLAG_FORMAT_ELF    0x100
; 
; ; ============================================================================
; ; CPU FEATURE BITS (AMD64)
; ; ============================================================================
; 
%define FEAT_AVX               (1 << 0)
%define FEAT_AVX2              (1 << 1)
%define FEAT_AVX512F           (1 << 2)
%define FEAT_AVX512DQ          (1 << 3)
%define FEAT_AVX512BW          (1 << 4)
%define FEAT_AVX512VL          (1 << 5)
%define FEAT_AMX_TILE          (1 << 6)
%define FEAT_AMX_INT8          (1 << 7)
%define FEAT_AMX_BF16          (1 << 8)
%define FEAT_SGX               (1 << 9)
%define FEAT_AES               (1 << 10)
%define FEAT_SHA               (1 << 11)
%define FEAT_KL                (1 << 12)
; 
; ; ============================================================================
; ; INSTRUCTION FLAGS
; ; ============================================================================
; 
%define F_VEX                  (1 << 0)    ; uses VEX encoding
%define F_EVEX                 (1 << 1)    ; uses EVEX encoding
%define F_MODRM                (1 << 2)    ; requires ModRM byte
%define F_REX                  (1 << 3)    ; requires REX prefix in 64-bit
%define F_MMX                  (1 << 4)    ; uses MMX registers
%define F_XMM                  (1 << 5)    ; uses XMM/SSE registers
%define F_FPU                  (1 << 6)    ; uses x87 FPU registers
%define F_LOCK                 (1 << 7)    ; supports LOCK prefix
; 
; ; ============================================================================
; ; OPERAND SIZES (BITS)
; ; ============================================================================
; 
%define SZ_8                   8
%define SZ_16                  16
%define SZ_32                  32
%define SZ_64                  64
%define SZ_128                 128
%define SZ_256                 256
%define SZ_512                 512
; 

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

%define FMT_ELF64              1           ; ELF64 relocatable or executable
%define FMT_BIN                2           ; flat raw binary (no metadata)

; ============================================================================
; OPTIMIZATION LEVELS
; ============================================================================
; Controls the aggressiveness of assembler and linker optimizations.

%define OPT_NONE               0           ; no optimizations applied
%define OPT_BASIC              1           ; basic peephole and dead code removal

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

; ============================================================================
; MEMORY MAPPING FLAGS
; ============================================================================
; Behavior modifiers for memory mapping operations.
; Combined with bitwise OR when invoking mmap.

%define MAP_SHARED             1           ; modifications visible to other mappings
%define MAP_PRIVATE            2           ; modifications are private copy-on-write
%define MAP_ANONYMOUS          0x20        ; mapping not backed by any file
%define MAP_FIXED              0x10        ; force mapping at requested address
%define MAP_FAILED             -1          ; mapping failure return value

; ============================================================================
; ERROR RETURN CODES (ERRNO VALUES)
; ============================================================================
; Standard numeric codes returned by system calls on failure.
; These match the conventional errno numbering used by the host platform.

%define ENOENT                 2           ; no such file or directory
%define EIO                    5           ; input/output error
%define ENOMEM                 12          ; cannot allocate memory
%define EACCES                 13          ; permission denied
%define EINVAL                 22          ; invalid argument

; ============================================================================
; MEMORY ALIGNMENT
; ============================================================================
; Fundamental page and alignment constants for memory management.

%define PAGE_SIZE              4096        ; default virtual memory page size in bytes

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

; ============================================================================
; ELF64 VERSION
; ============================================================================

%define EV_CURRENT             1           ; current ELF version identifier

; ============================================================================
; ELF64 OBJECT TYPES
; ============================================================================
; Classification of ELF object files.

%define ET_REL                 1           ; relocatable file
%define ET_EXEC                2           ; executable file

; ============================================================================
; ELF64 MACHINE TYPES
; ============================================================================
; Architecture identifiers stored in the ELF header e_machine field.

%define EM_AARCH64             183         ; ARM AArch64
%define EM_X86_64              62          ; AMD64 / x86-64
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
%define SHT_REL                9           ; relocation entries without addends
%define SHT_NOBITS             8           ; uninitialized data (BSS)
%define SHT_GROUP              17          ; section group (0x11)

; ---- Section Group Flags ----
%define GRP_COMDAT             0x1         ; COMDAT group

; ============================================================================
; ELF64 SECTION FLAGS
; ============================================================================
; Attribute bits describing section permissions and memory behavior.

%define SHF_WRITE              0x1         ; section contains writable data
%define SHF_ALLOC              0x2         ; section occupies memory at runtime
%define SHF_EXECINSTR          0x4         ; section contains executable instructions

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

; ============================================================================
; ELF64 SYMBOL TABLE TYPES
; ============================================================================
; Classification of symbol semantics.

%define STT_NOTYPE             0           ; unspecified symbol type
%define STT_OBJECT             1           ; data object (variable, array, etc.)
%define STT_FUNC               2           ; function or executable code

; ============================================================================
; ELF64 SPECIAL SECTION INDICES
; ============================================================================
; Reserved section index values with special meaning.

%define SHN_UNDEF              0           ; undefined or external symbol

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
; 
; ; ============================================================================
; ; AMD64 RELOCATION TYPES (Standard ELF)
; ; ============================================================================
; 
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
; 
; ; Backward compatibility aliases
%define RELOC_ABS64            R_X86_64_64
%define RELOC_REL32            R_X86_64_PC32
%define RELOC_REL64            1           ; Legacy map
%define RELOC_GOT              R_X86_64_GOT32
%define RELOC_REL8             R_X86_64_PC8

; RISC-V Relocations
%define R_RISCV_BRANCH         16
%define R_RISCV_JAL            17
%define R_RISCV_CALL_HI20      18
%define R_RISCV_CALL_LO12      19
%define R_RISCV_PCREL_HI20     23
%define R_RISCV_PCREL_LO12_I   24
%define R_RISCV_PCREL_LO12_S   25
%define R_RISCV_HI20           26
%define R_RISCV_LO12_I         27
%define R_RISCV_LO12_S         28

; ============================================================================
; REGISTER IDENTIFIERS
; ============================================================================
; Internal numeric identifiers for architectural registers.

%define REG_NONE               0xFF        ; sentinel for "no register"

; Base GPR indices
%define REG_RAX                0
%define REG_RCX                1
%define REG_RDX                2
%define REG_RBX                3
%define REG_RSP                4
%define REG_RBP                5
%define REG_RSI                6
%define REG_RDI                7
%define R_AARCH64_ABS64         257
%define R_AARCH64_ADR_PREL_LO21 274
%define R_AARCH64_ADR_PREL_PG_HI21 275
%define R_AARCH64_ADD_ABS_LO12_NC 277
%define R_AARCH64_CALL26        283
%define R_AARCH64_JUMP26        282
%define R_AARCH64_LDST64_ABS_LO12_NC 286
%define R_AARCH64_LDST32_ABS_LO12_NC 285
%define R_AARCH64_LDST16_ABS_LO12_NC 284
%define R_AARCH64_LDST8_ABS_LO12_NC  278

%define R_RISCV_64             2
%define R_RISCV_CALL           18
%define R_RISCV_RELAX          51

; ============================================================================
; LEXER CHARACTER PROPERTIES
; ============================================================================
%define CHAR_IS_DIGIT          0x01
%define CHAR_IS_IDENT_START    0x02
%define CHAR_IS_IDENT_PART     0x04
%define CHAR_IS_WHITESPACE     0x08
%define CHAR_IS_HEX            0x10

%endif
