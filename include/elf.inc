%ifndef ELF_S
%define ELF_S

;
; ============================================================================
; File        : include/elf.s
; Project     : utasm
; Description : ELF64 format constants, header offsets, and section/segment
;               type definitions. Used by src/linker/elf64.s to emit valid
;               ELF64 object files and executables.
; ============================================================================
;

; ============================================================================
; ELF MAGIC & IDENTIFICATION
; ============================================================================
%define ELFMAG0                0x7F        ; e_ident[0]
%define ELFMAG1                0x45        ; 'E'
%define ELFMAG2                0x4C        ; 'L'
%define ELFMAG3                0x46        ; 'F'
%define ELFMAG                 0x464C457F  ; 4-byte magic (little-endian)

; e_ident[EI_CLASS]
%define ELFCLASSNONE           0
%define ELFCLASS32             1
%define ELFCLASS64             2           ; 64-bit ELF

; e_ident[EI_DATA]
%define ELFDATANONE            0
%define ELFDATA2LSB            1           ; Little-endian (x86_64)
%define ELFDATA2MSB            2           ; Big-endian

; e_ident[EI_VERSION]
%define EV_NONE                0
%define EV_CURRENT             1

; e_ident[EI_OSABI]
%define ELFOSABI_NONE          0           ; UNIX System V ABI
%define ELFOSABI_LINUX         3           ; Linux
%define ELFOSABI_FREEBSD       9
%define ELFOSABI_STANDALONE    255         ; Standalone (embedded / bare-metal OS)

; e_ident indices
%define EI_MAG0                0
%define EI_MAG1                1
%define EI_MAG2                2
%define EI_MAG3                3
%define EI_CLASS               4
%define EI_DATA                5
%define EI_VERSION             6
%define EI_OSABI               7
%define EI_ABIVERSION          8
%define EI_PAD                 9
%define EI_NIDENT              16

; ============================================================================
; ELF FILE TYPES (e_type)
; ============================================================================
%define ET_NONE                0           ; No file type
%define ET_REL                 1           ; Relocatable object file (.o)
%define ET_EXEC                2           ; Executable file
%define ET_DYN                 3           ; Shared object (.so)
%define ET_CORE                4           ; Core dump
%define ET_LOOS                0xFE00      ; OS-specific range begin
%define ET_HIOS                0xFEFF      ; OS-specific range end
%define ET_LOPROC              0xFF00      ; Processor-specific range begin
%define ET_HIPROC              0xFFFF      ; Processor-specific range end

; ============================================================================
; MACHINE TYPES (e_machine)
; ============================================================================
%define EM_NONE                0
%define EM_386                 3           ; Intel 80386
%define EM_MIPS                8           ; MIPS
%define EM_PPC                 20          ; PowerPC
%define EM_PPC64               21          ; 64-bit PowerPC
%define EM_ARM                 40          ; ARM 32-bit
%define EM_X86_64              62          ; AMD64 / x86-64
%define EM_AARCH64             183         ; ARM 64-bit (AArch64)
%define EM_RISCV               243         ; RISC-V

; ============================================================================
; ELF64 FILE HEADER LAYOUT (Ehdr) — Byte Offsets
; ============================================================================
; Total size: 64 bytes
%define ELF64_EHDR_SIZE        64

%define EHDR_IDENT             0           ; e_ident[16]       16 bytes
%define EHDR_TYPE              16          ; e_type             2 bytes
%define EHDR_MACHINE           18          ; e_machine          2 bytes
%define EHDR_VERSION           20          ; e_version          4 bytes
%define EHDR_ENTRY             24          ; e_entry            8 bytes
%define EHDR_PHOFF             32          ; e_phoff            8 bytes
%define EHDR_SHOFF             40          ; e_shoff            8 bytes
%define EHDR_FLAGS             48          ; e_flags            4 bytes
%define EHDR_EHSIZE            52          ; e_ehsize           2 bytes
%define EHDR_PHENTSIZE         54          ; e_phentsize        2 bytes
%define EHDR_PHNUM             56          ; e_phnum            2 bytes
%define EHDR_SHENTSIZE         58          ; e_shentsize        2 bytes
%define EHDR_SHNUM             60          ; e_shnum            2 bytes
%define EHDR_SHSTRNDX          62          ; e_shstrndx         2 bytes

; ============================================================================
; ELF64 SECTION HEADER LAYOUT (Shdr) — Byte Offsets
; ============================================================================
; Total size: 64 bytes
%define ELF64_SHDR_SIZE        64

%define SHDR_NAME              0           ; sh_name            4 bytes (index into .shstrtab)
%define SHDR_TYPE              4           ; sh_type            4 bytes
%define SHDR_FLAGS             8           ; sh_flags           8 bytes
%define SHDR_ADDR              16          ; sh_addr            8 bytes
%define SHDR_OFFSET            24          ; sh_offset          8 bytes
%define SHDR_SIZE              32          ; sh_size            8 bytes
%define SHDR_LINK              40          ; sh_link            4 bytes
%define SHDR_INFO              44          ; sh_info            4 bytes
%define SHDR_ADDRALIGN         48          ; sh_addralign       8 bytes
%define SHDR_ENTSIZE           56          ; sh_entsize         8 bytes

; ============================================================================
; SECTION TYPES (sh_type)
; ============================================================================
%define SHT_NULL               0           ; Inactive section
%define SHT_PROGBITS           1           ; Program-defined content
%define SHT_SYMTAB             2           ; Symbol table
%define SHT_STRTAB             3           ; String table
%define SHT_RELA               4           ; Relocation with explicit addends
%define SHT_HASH               5           ; Symbol hash table
%define SHT_DYNAMIC            6           ; Dynamic linking info
%define SHT_NOTE               7           ; Notes
%define SHT_NOBITS             8           ; .bss — occupies no file space
%define SHT_REL                9           ; Relocation without addends
%define SHT_SHLIB              10          ; Reserved (unspecified semantics)
%define SHT_DYNSYM             11          ; Dynamic symbol table
%define SHT_INIT_ARRAY         14          ; Array of init function ptrs
%define SHT_FINI_ARRAY         15          ; Array of fini function ptrs
%define SHT_PREINIT_ARRAY      16          ; Array of pre-init function ptrs
%define SHT_GROUP              17          ; Section group
%define SHT_SYMTAB_SHNDX       18          ; Extended symbol table index
%define SHT_RELR               19          ; Compact relative relocations
%define SHT_LOOS               0x60000000  ; OS-specific begin
%define SHT_GNU_HASH           0x6FFFFFF6  ; GNU hash table
%define SHT_GNU_VERNEED        0x6FFFFFFE  ; GNU version requirement
%define SHT_GNU_VERSYM         0x6FFFFFFF  ; GNU version symbol
%define SHT_HIOS               0x6FFFFFFF  ; OS-specific end
%define SHT_LOPROC             0x70000000  ; Processor-specific begin
%define SHT_X86_64_UNWIND      0x70000001  ; x86_64 unwind table
%define SHT_HIPROC             0x7FFFFFFF  ; Processor-specific end

; ============================================================================
; SECTION GROUP FLAGS (used in SHT_GROUP data)
; ============================================================================
%define GRP_COMDAT             0x1         ; COMDAT group semantics

; ============================================================================
; SECTION FLAGS (sh_flags)
; ============================================================================
%define SHF_WRITE              0x1         ; Section is writable
%define SHF_ALLOC              0x2         ; Section occupies memory during exec
%define SHF_EXECINSTR          0x4         ; Section contains executable code
%define SHF_MERGE              0x10        ; Section may be merged
%define SHF_STRINGS            0x20        ; Section contains null-terminated strings
%define SHF_INFO_LINK          0x40        ; sh_info holds section header index
%define SHF_LINK_ORDER         0x80        ; Preserve order after combining
%define SHF_OS_NONCONFORMING   0x100       ; Non-standard OS handling required
%define SHF_GROUP              0x200       ; Section is member of a group
%define SHF_TLS                0x400       ; Section holds thread-local data
%define SHF_COMPRESSED         0x800       ; Section with compressed data
%define SHF_MASKOS             0x0FF00000  ; OS-specific flags mask
%define SHF_MASKPROC           0xF0000000  ; Processor-specific flags mask
%define SHF_GNU_RETAIN         0x200000    ; GNU: Retain section in final link

; ============================================================================
; ELF64 PROGRAM HEADER LAYOUT (Phdr) — Byte Offsets
; ============================================================================
; Total size: 56 bytes
%define ELF64_PHDR_SIZE        56

%define PHDR_TYPE              0           ; p_type             4 bytes
%define PHDR_FLAGS             4           ; p_flags            4 bytes
%define PHDR_OFFSET            8           ; p_offset           8 bytes
%define PHDR_VADDR             16          ; p_vaddr            8 bytes
%define PHDR_PADDR             24          ; p_paddr            8 bytes
%define PHDR_FILESZ            32          ; p_filesz           8 bytes
%define PHDR_MEMSZ             40          ; p_memsz            8 bytes
%define PHDR_ALIGN             48          ; p_align            8 bytes

; ============================================================================
; SEGMENT TYPES (p_type)
; ============================================================================
%define PT_NULL                0           ; Unused entry
%define PT_LOAD                1           ; Loadable segment
%define PT_DYNAMIC             2           ; Dynamic linking info
%define PT_INTERP              3           ; Interpreter path
%define PT_NOTE                4           ; Auxiliary info
%define PT_SHLIB               5           ; Reserved
%define PT_PHDR                6           ; Program header table itself
%define PT_TLS                 7           ; Thread-local storage
%define PT_LOOS                0x60000000
%define PT_GNU_EH_FRAME        0x6474E550  ; .eh_frame_hdr segment
%define PT_GNU_STACK           0x6474E551  ; Stack permissions
%define PT_GNU_RELRO           0x6474E552  ; Read-only after relocation
%define PT_GNU_PROPERTY        0x6474E553  ; GNU properties
%define PT_HIOS                0x6FFFFFFF
%define PT_LOPROC              0x70000000
%define PT_HIPROC              0x7FFFFFFF

; ============================================================================
; SEGMENT PERMISSION FLAGS (p_flags)
; ============================================================================
%define PF_X                   0x1         ; Executable
%define PF_W                   0x2         ; Writable
%define PF_R                   0x4         ; Readable
%define PF_RX                  0x5         ; Readable + Executable (.text)
%define PF_RW                  0x6         ; Readable + Writable  (.data/.bss)
%define PF_RWX                 0x7         ; All permissions (dangerous)

; ============================================================================
; ELF64 SYMBOL TABLE ENTRY (Sym64) — Byte Offsets
; ============================================================================
; Total size: 24 bytes
%define ELF64_SYM_SIZE         24

%define SYM64_NAME             0           ; st_name    4 bytes (strtab index)
%define SYM64_INFO             4           ; st_info    1 byte  (bind | type)
%define SYM64_OTHER            5           ; st_other   1 byte  (visibility)
%define SYM64_SHNDX            6           ; st_shndx   2 bytes (section index)
%define SYM64_VALUE            8           ; st_value   8 bytes (address/value)
%define SYM64_SIZE             16          ; st_size    8 bytes (symbol size)

; ---- Symbol Binding (high nibble of st_info) ----
%define STB_LOCAL              0           ; Local symbol (not visible outside obj)
%define STB_GLOBAL             1           ; Global symbol
%define STB_WEAK               2           ; Weak symbol (overrideable)
%define STB_LOOS               10
%define STB_GNU_UNIQUE         10          ; GNU: unique symbol
%define STB_HIOS               12
%define STB_LOPROC             13
%define STB_HIPROC             15

; ---- Symbol Type (low nibble of st_info) ----
%define STT_NOTYPE             0           ; Unspecified type
%define STT_OBJECT             1           ; Data object (variable, array)
%define STT_FUNC               2           ; Function / code entry point
%define STT_SECTION            3           ; Associated with a section
%define STT_FILE               4           ; Source file name
%define STT_COMMON             5           ; Uninitialised common block
%define STT_TLS                6           ; Thread-local storage object
%define STT_LOOS               10
%define STT_GNU_IFUNC          10          ; GNU indirect function (ifunc)
%define STT_HIOS               12
%define STT_LOPROC             13
%define STT_HIPROC             15

; ---- Symbol Visibility (low 2 bits of st_other) ----
%define STV_DEFAULT            0           ; Default (controlled by binding)
%define STV_INTERNAL           1           ; Processor-specific hidden
%define STV_HIDDEN             2           ; Hidden from other components
%define STV_PROTECTED          3           ; Not preemptable

; ---- Special Section Indices ----
%define SHN_UNDEF              0           ; Undefined section
%define SHN_LORESERVE          0xFF00
%define SHN_LOPROC             0xFF00
%define SHN_HIPROC             0xFF1F
%define SHN_LOOS               0xFF20
%define SHN_HIOS               0xFF3F
%define SHN_ABS                0xFFF1      ; Absolute value (not relocated)
%define SHN_COMMON             0xFFF2      ; Common block — size in st_value
%define SHN_XINDEX             0xFFFF      ; Extended index (use SYMTAB_SHNDX)
%define SHN_HIRESERVE          0xFFFF

; ============================================================================
; ELF64 RELOCATION ENTRY — Byte Offsets (Rela — with addend)
; ============================================================================
; Total size: 24 bytes
%define ELF64_RELA_SIZE        24

%define RELA_OFFSET            0           ; r_offset   8 bytes
%define RELA_INFO              8           ; r_info     8 bytes (sym << 32 | type)
%define RELA_ADDEND            16          ; r_addend   8 bytes (signed)

; ---- Relocation Without Addend (Rel) ----
; Total size: 16 bytes
%define ELF64_REL_SIZE         16
%define REL_OFFSET             0
%define REL_INFO               8

; ============================================================================
; x86_64 RELOCATION TYPES (used in r_info low 32 bits)
; ============================================================================
%define R_X86_64_NONE          0           ; No relocation
%define R_X86_64_64            1           ; Direct 64-bit symbol value
%define R_X86_64_PC32          2           ; PC-relative 32-bit signed
%define R_X86_64_GOT32         3           ; 32-bit GOT offset
%define R_X86_64_PLT32         4           ; 32-bit PLT offset (call)
%define R_X86_64_COPY          5           ; Copy symbol at runtime
%define R_X86_64_GLOB_DAT      6           ; Create GOT entry
%define R_X86_64_JUMP_SLOT     7           ; Create PLT entry
%define R_X86_64_RELATIVE      8           ; Adjust by program base
%define R_X86_64_GOTPCREL      9           ; 32-bit signed PC-rel GOT
%define R_X86_64_32            10          ; Direct 32-bit zero-extended
%define R_X86_64_32S           11          ; Direct 32-bit sign-extended
%define R_X86_64_16            12          ; Direct 16-bit zero-extended
%define R_X86_64_PC16          13          ; PC-relative 16-bit signed
%define R_X86_64_8             14          ; Direct 8-bit
%define R_X86_64_PC8           15          ; PC-relative 8-bit signed
%define R_X86_64_DTPMOD64      16          ; TLS module index
%define R_X86_64_DTPOFF64      17          ; TLS module-relative offset
%define R_X86_64_TPOFF64       18          ; TP-relative offset, 64-bit
%define R_X86_64_TLSGD         19          ; 32-bit PC-rel offset to GD TLS
%define R_X86_64_TLSLD         20          ; 32-bit PC-rel offset to LD TLS
%define R_X86_64_DTPOFF32      21          ; TLS module-relative offset, 32-bit
%define R_X86_64_GOTTPOFF      22          ; 32-bit PC-rel offset to IE TLS
%define R_X86_64_TPOFF32       23          ; TP-relative offset, 32-bit
%define R_X86_64_PC64          24          ; PC-relative 64-bit
%define R_X86_64_GOTOFF64      25          ; 64-bit offset from GOT base
%define R_X86_64_GOTPC32       26          ; 32-bit signed PC-rel to GOT
%define R_X86_64_GOT64         27          ; 64-bit GOT entry offset
%define R_X86_64_GOTPCREL64    28
%define R_X86_64_GOTPC64       29
%define R_X86_64_GOTPLT64      30
%define R_X86_64_PLTOFF64      31
%define R_X86_64_SIZE32        32
%define R_X86_64_SIZE64        33
%define R_X86_64_GOTPC32_TLSDESC 34
%define R_X86_64_TLSDESC_CALL  35
%define R_X86_64_TLSDESC       36
%define R_X86_64_IRELATIVE     37          ; Adjust indirectly
%define R_X86_64_RELATIVE64    38
%define R_X86_64_GOTPCRELX     41          ; Relaxable GOTPCREL
%define R_X86_64_REX_GOTPCRELX 42          ; Relaxable GOTPCREL (REX)

; ---- AArch64 Relocation Types -----------
%define R_AARCH64_NONE         0
%define R_AARCH64_ABS64        257
%define R_AARCH64_COPY         258
%define R_AARCH64_GLOB_DAT     259
%define R_AARCH64_JUMP_SLOT    260
%define R_AARCH64_RELATIVE     261
%define R_AARCH64_ADR_PREL_LO21 274
%define R_AARCH64_ADR_PREL_PG_HI21 275
%define R_AARCH64_ADR_PREL_PG_HI21_NC 276
%define R_AARCH64_ADD_ABS_LO12_NC 277
%define R_AARCH64_LDST8_ABS_LO12_NC 278
%define R_AARCH64_TSTBR_14     279
%define R_AARCH64_CONDBR19     280
%define R_AARCH64_JMP26        282
%define R_AARCH64_CALL26       283
%define R_AARCH64_LDST16_ABS_LO12_NC 284
%define R_AARCH64_LDST32_ABS_LO12_NC 285
%define R_AARCH64_LDST64_ABS_LO12_NC 286
%define R_AARCH64_LDST128_ABS_LO12_NC 299

; ---- RISC-V Relocation Types -----------
%define R_RISCV_64             2
%define R_RISCV_RELATIVE       3
%define R_RISCV_COPY           4
%define R_RISCV_JUMP_SLOT      5
%define R_RISCV_BRANCH         16
%define R_RISCV_JAL            17
%define R_RISCV_CALL           18
%define R_RISCV_PCREL_HI20     26
%define R_RISCV_PCREL_LO12_I   27
%define R_RISCV_PCREL_LO12_S   28
%define R_RISCV_HI20           29
%define R_RISCV_LO12_I         30
%define R_RISCV_LO12_S         31

; ============================================================================
; HELPER MACRO: ELF64_R_INFO — pack symbol index and reloc type
; ============================================================================
; Usage: ELF64_R_INFO sym_idx, reloc_type  -> result in rax
%macro ELF64_R_INFO 2
    mov     rax, %1
    shl     rax, 32
    or      rax, %2
%endmacro

; ============================================================================
; ELF64 DYNAMIC SECTION TAGS (d_tag in .dynamic)
; ============================================================================
%define DT_NULL                0           ; End of dynamic array
%define DT_NEEDED              1           ; Name of needed library
%define DT_PLTRELSZ            2           ; Size of PLT relocation table
%define DT_PLTGOT              3           ; Address of PLT/GOT
%define DT_HASH                4           ; Symbol hash table address
%define DT_STRTAB              5           ; String table address
%define DT_SYMTAB              6           ; Symbol table address
%define DT_RELA                7           ; RELA relocation table address
%define DT_RELASZ              8           ; Size of RELA table
%define DT_RELAENT             9           ; Size of one RELA entry
%define DT_STRSZ               10          ; String table size
%define DT_SYMENT              11          ; Size of one symbol table entry
%define DT_INIT                12          ; Address of init function
%define DT_FINI                13          ; Address of fini function
%define DT_SONAME              14          ; Shared object name
%define DT_RPATH               15          ; Library search path (deprecated)
%define DT_SYMBOLIC            16          ; Symbolic flag
%define DT_REL                 17          ; REL relocation table
%define DT_RELSZ               18          ; Size of REL table
%define DT_RELENT              19          ; Size of one REL entry
%define DT_PLTREL              20          ; Type of PLT relocation
%define DT_DEBUG               21          ; Debugger info
%define DT_TEXTREL             22          ; Text section relocation
%define DT_JMPREL              23          ; Address of PLT relocation entries
%define DT_BIND_NOW            24          ; Process relocations immediately
%define DT_INIT_ARRAY          25          ; Array of init function addresses
%define DT_FINI_ARRAY          26          ; Array of fini function addresses
%define DT_INIT_ARRAYSZ        27          ; Size of DT_INIT_ARRAY
%define DT_FINI_ARRAYSZ        28          ; Size of DT_FINI_ARRAY
%define DT_RUNPATH             29          ; Library search path
%define DT_FLAGS               30          ; Flags for object being loaded
%define DT_GNU_HASH            0x6FFFFEF5  ; GNU hash table
%define DT_VERSYM              0x6FFFFFF0  ; Version symbol table
%define DT_RELACOUNT           0x6FFFFFF9  ; Count of RELA relocations
%define DT_RELCOUNT            0x6FFFFFFA  ; Count of REL relocations
%define DT_FLAGS_1             0x6FFFFFFB  ; State flags
%define DT_VERDEF              0x6FFFFFFC  ; Version definition table
%define DT_VERDEFNUM           0x6FFFFFFD  ; Count of verdef entries
%define DT_VERNEED             0x6FFFFFFE  ; Version requirement table
%define DT_VERNEEDNUM          0x6FFFFFFF  ; Count of verneed entries

%endif
