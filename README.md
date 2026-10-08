# utasm

> A high-performance, self-hosting, self-patching, multi-architecture assembler and linker — written entirely in x86-64 assembly.

`utasm` is the universal assembler engine of the UtkarshaLab toolchain. It targets three architectures from a single unified codebase, produces correct ELF64/PE32+ binaries, assembles itself, and patches itself at runtime based on profiling data.

---

## Features

- **Multi-Architecture** — Native instruction encoding for x86-64, AArch64, and RISC-V 64 (RV64GC)
- **Self-Hosting** — Bootstrap pipeline that compiles Gen0 via NASM and Gen1+ via itself
- **Self-Patching** — Runtime binary self-modification engine that rewrites hot paths based on profiler data
- **Integrated Linker** — ELF64/PE32+ emission with section layout, relocation resolution, and dead code elimination
- **Diagnostics that explain** — on a terminal, each error and warning shows its source line with the place marked, in color; operand errors say what the operands were and what clashes; misspelt instructions and symbols get a "did you mean". Piped, the output is NASM's lines (see [Beyond NASM](#beyond-nasm))
- **Recursive Preprocessor** — `%define`, `%macro`, `%if`, `%rep`, `%rotate`, token pasting, stringification, macro libraries
- **O(1) Symbol Table** — Hash-based lookup with quadratic probing and ELF index tracking
- **Full x86-64 Encoding** — REX, VEX-3, EVEX, AVX-512 (F/BW/DQ/VL/VNNI/BF16), AMX, AES-NI
- **CPU Profiles** — Named CPU targets with per-instruction feature validation
- **DWARF v5** — Full debug symbol emission (`.debug_info`, `.debug_abbrev`, `.debug_line`, `.debug_frame`)
- **io\_uring I/O** — Asynchronous file I/O for ultra-fast multi-megabyte builds
- **Multiple Output Formats** — ELF64 (objects and standalone executables), ELF32 i386 objects, flat binary, `.ubf` boot images for Tattva OS ([docs/ubf.md](docs/ubf.md)); PE32+ (UEFI) and `.upk` packages are planned
- **16-, 32- and 64-bit code** — `bits 16` / `bits 32` / `bits 64` encode as NASM does in each mode (operand- and address-size prefixes, 16-bit addressing, rel16 branches, the instructions each mode has)
- **Built-in Tools** — Disassembler, object inspector, symbol dumper — no external tools required
- **Zero Dependencies** — No libc, no runtime, raw syscalls only

---

## Supported Architectures

| Architecture | Base ISA | Extensions |
|---|---|---|
| x86-64 | AMD64 | REX, VEX-3, EVEX, AVX/AVX2/AVX-512, AMX, AES-NI, SHA |
| AArch64 | ARMv8-A | NEON Advanced SIMD, SVE, SVE2 |
| RISC-V 64 | RV64GC | M, A, F, D, V extensions |

---

## Project Structure

```
utasm/
│
├── utasm.s                      ; entry point, main loop
├── cli.s                        ; CLI argument parser + dispatch
├── utasm.ld                     ; linker script for self-hosted builds
├── utasm.toml                   ; project manifest
├── VERSION                      ; current release version
├── LICENSE                      ; Apache-2.0
├── README.md                    ; this file
│
├── build/                       ; build output (generated, not committed)
│   ├── gen0/                    ; Stage 1: NASM-compiled binary
│   ├── gen1/                    ; Stage 2: Gen0-compiled binary
│   └── gen2/                    ; Stage 3: Gen1-compiled binary (parity check)
│
├── docs/
│   ├── architecture.md          ; design rationale and decisions
│   ├── error_reference.md       ; full error code reference (LXE0001+, etc.)
│   ├── tests.md                 ; full test architecture documentation
│   ├── workflow.md              ; complete stage-by-stage workflow plans
│   └── cpu_profiles.md          ; CPU profile documentation
│
├── include/                     ; architecture-agnostic headers
│   ├── arch/
│   │   ├── amd64.inc            ; x86-64 register encodings, opcode maps
│   │   ├── aarch64.inc          ; AArch64 register encodings, opcode maps
│   │   └── riscv64.inc          ; RISC-V 64 register encodings, opcode maps
│   ├── utasm.inc                ; utasm standard definitions
│   ├── x86_64.inc               ; register names, common macros
│   ├── elf.inc                  ; ELF64 struct offsets and constants
│   ├── pe.inc                   ; PE32+ constants
│   ├── syscall.inc              ; syscall numbers
│   ├── simd.inc                 ; SIMD helper macros
│   ├── debug.inc                ; debug helper macros
│   ├── upk.inc                  ; .upk package format constants
│   ├── constant.inc             ; global constants (exit codes, flags, limits)
│   ├── macro.inc                ; prologue/epilogue and utility macros
│   ├── macro1.inc               ; extended preprocessor macros
│   ├── register.inc             ; register aliases across all architectures
│   ├── type.inc                 ; central aligned structure definitions and type tag offsets
│   └── uring.inc                ; io_uring SQE/CQE struct definitions
│
├── core/
│   ├── config.inc               ; global constants, CPU targets, version
│   ├── types.inc                ; legacy/deprecated structure definitions
│   ├── globals.s                ; global variables, assembler state
│   ├── asmctx.s                 ; assembler context and section state
│   └── memory.s                 ; internal allocator (bump + slab)
│
├── frontend/
│   │
│   ├── lexer/
│   │   ├── lexer.s              ; main entry point
│   │   ├── chars.s              ; character classification tables
│   │   ├── ident.s              ; identifier + keyword scanning
│   │   ├── number/
│   │   │   ├── number.s         ; literal parsing coordinator
│   │   │   ├── bin.s            ; binary literals (0b...)
│   │   │   ├── oct.s            ; octal literals (0o...)
│   │   │   ├── hex.s            ; hex literals (0x...)
│   │   │   └── dec.s            ; decimal literals
│   │   ├── string.s             ; string + char literal scanning
│   │   ├── comment.s            ; line + block comment handling
│   │   ├── token.s              ; token creation, source map attachment
│   │   ├── buffer.s             ; token buffer management
│   │   └── utf8.s               ; UTF-8 validation
│   │
│   ├── parser/
│   │   ├── parser.s             ; main entry point
│   │   ├── instr.s              ; instruction statement parsing
│   │   ├── operand/
│   │   │   ├── operand.s        ; operand parsing coordinator
│   │   │   ├── reg.s            ; register operand parsing
│   │   │   ├── mem.s            ; memory operand parsing
│   │   │   ├── imm.s            ; immediate operand parsing
│   │   │   └── addr.s           ; addressing mode resolution
│   │   ├── directive.s          ; directive statement parsing
│   │   ├── label.s              ; label definition parsing
│   │   ├── expr.s               ; expression parsing (Pratt parser)
│   │   ├── section.s            ; section directive parsing
│   │   ├── data.s               ; DB/DW/DD/DQ/DT/DO/DY/DZ parsing
│   │   ├── struct.s             ; STRUC/ENDSTRUC parsing
│   │   ├── proc.s               ; PROC/ENDPROC parsing
│   │   ├── ast.s                ; AST node allocation + construction
│   │   └── recover.s            ; error recovery logic
│   │
│   └── macro/
│       ├── macro.s              ; main entry point
│       ├── define.s             ; %define, %macro, %imacro
│       ├── expand.s             ; expansion engine
│       ├── args.s               ; argument parsing + substitution
│       ├── local.s              ; local label generation
│       ├── cond/
│       │   ├── cond.s           ; %if/%elif/%else/%endif coordinator
│       │   ├── def.s            ; %ifdef/%ifndef
│       │   ├── expr.s           ; %if expression evaluation
│       │   └── str.s            ; %ifidn/%ifidni string compare
│       ├── rep.s                ; %rep/%endrep
│       ├── rotate.s             ; %rotate
│       ├── stringify.s          ; %str() stringification
│       ├── paste.s              ; token pasting
│       ├── include.s            ; %include file handling
│       ├── library.s            ; macro library (.inc) management
│       ├── table.s              ; macro definition hash table
│       ├── chain.s              ; expansion chain tracking (for errors)
│       └── purge.s              ; %undef/%purge
│
├── middle/
│   │
│   ├── semantic/
│   │   ├── semantic.s           ; main entry point
│   │   ├── instr.s              ; instruction validation
│   │   ├── operand.s            ; operand type checking
│   │   ├── size.s               ; operand size resolution
│   │   ├── type.s               ; type checking + coercion
│   │   ├── scope.s              ; scope rules enforcement
│   │   ├── proc.s               ; PROC boundary validation
│   │   └── data.s               ; data definition validation
│   │
│   ├── symtable/
│   │   ├── symtable.s           ; main entry point
│   │   ├── hash.s               ; hash table (quadratic probing)
│   │   ├── insert.s             ; symbol insertion
│   │   ├── lookup.s             ; O(1) symbol lookup
│   │   ├── resolve.s            ; forward reference resolution
│   │   ├── scope.s              ; scope management
│   │   ├── global.s             ; global/extern declaration
│   │   ├── local.s              ; local label management
│   │   ├── common.s             ; COMMON symbol handling
│   │   ├── weak.s               ; weak symbol handling
│   │   └── dump.s               ; debug: symbol table dump
│   │
│   └── expr/
│       ├── expr.s               ; main entry point
│       ├── arith.s              ; arithmetic operations
│       ├── bitwise.s            ; bitwise operations
│       ├── compare.s            ; comparison operations
│       ├── logical.s            ; logical operations
│       ├── unary.s              ; unary operators
│       ├── const.s              ; constant folding
│       ├── reloc.s              ; relocatable expression handling
│       └── overflow.s           ; overflow detection
│
├── backend/
│   │
│   ├── encoder/
│   │   ├── encoder.s            ; main entry point
│   │   ├── dispatch.s           ; instruction → handler dispatch table
│   │   │
│   │   ├── x86/
│   │   │   ├── mov.s
│   │   │   ├── arith.s          ; ADD/SUB/MUL/DIV/ADC/SBB
│   │   │   ├── logic.s          ; AND/OR/XOR/NOT
│   │   │   ├── shift.s          ; SHL/SHR/SAR/ROL/ROR
│   │   │   ├── jump.s           ; JMP/Jcc/LOOP
│   │   │   ├── call.s           ; CALL/RET
│   │   │   ├── stack.s          ; PUSH/POP
│   │   │   ├── string.s         ; MOVS/STOS/LODS/SCAS + REP
│   │   │   ├── bit.s            ; BT/BSF/BSR/TZCNT/LZCNT
│   │   │   ├── cmov.s           ; CMOVcc
│   │   │   ├── setcc.s          ; SETcc
│   │   │   ├── flag.s           ; CLC/STC/CMC/CLD/STD/CLI/STI
│   │   │   ├── io.s             ; IN/OUT
│   │   │   ├── system.s         ; SYSCALL/SYSRET/HLT/CPUID/RDTSC
│   │   │   ├── priv.s           ; LGDT/LIDT/LTR and privileged ops
│   │   │   ├── misc.s           ; LEA/XCHG/CMPXCHG/BSWAP/MOVBE
│   │   │   └── crypto.s         ; AES-NI/SHA/PCLMULQDQ
│   │   │
│   │   ├── simd/
│   │   │   ├── mmx.s
│   │   │   ├── sse.s
│   │   │   ├── sse2.s
│   │   │   ├── sse3.s           ; SSE3 + SSSE3
│   │   │   ├── sse4.s           ; SSE4.1 + SSE4.2
│   │   │   ├── avx.s            ; VEX encoded
│   │   │   ├── avx2.s
│   │   │   ├── avx512/
│   │   │   │   ├── avx512.s     ; EVEX foundation
│   │   │   │   ├── bw.s         ; byte/word ops
│   │   │   │   ├── dq.s         ; dword/qword ops
│   │   │   │   ├── vl.s         ; 128/256-bit variants
│   │   │   │   ├── vnni.s       ; neural network instructions
│   │   │   │   └── bf16.s       ; bfloat16 instructions
│   │   │   ├── amx.s            ; AMX tile instructions
│   │   │   └── fpu.s            ; x87 FPU
│   │   │
│   │   ├── aarch64/
│   │   │   ├── base.s           ; AArch64 fixed-width encoder
│   │   │   ├── neon.s           ; NEON Advanced SIMD
│   │   │   └── sve.s            ; SVE/SVE2
│   │   │
│   │   ├── riscv64/
│   │   │   ├── base.s           ; RV64GC base encoder
│   │   │   ├── m.s              ; M extension (multiply)
│   │   │   ├── a.s              ; A extension (atomics)
│   │   │   ├── fd.s             ; F/D extensions (float)
│   │   │   ├── v.s              ; V extension (vector)
│   │   │   └── relax.s          ; relaxation support
│   │   │
│   │   ├── prefix/
│   │   │   ├── rex.s            ; REX prefix generation
│   │   │   ├── vex.s            ; VEX prefix generation
│   │   │   ├── evex.s           ; EVEX prefix generation
│   │   │   ├── lock.s           ; LOCK prefix
│   │   │   └── rep.s            ; REP/REPNE prefix
│   │   │
│   │   └── tables/
│   │       ├── opcode.s         ; master opcode table
│   │       ├── modrm.s          ; ModRM encoding helpers
│   │       ├── sib.s            ; SIB byte encoding helpers
│   │       ├── reg.s            ; register encoding table
│   │       └── features.s       ; CPU feature flag table
│   │
│   ├── isa/
│   │   ├── amd64.s              ; AMD64 instruction table
│   │   ├── aarch64.s            ; AArch64 instruction table
│   │   └── riscv64.s            ; RISC-V 64 instruction table
│   │
│   ├── linker/
│   │   ├── linker.s             ; coordinator
│   │   ├── section.s            ; section management
│   │   ├── symbol.s             ; symbol resolution
│   │   ├── reloc/
│   │   │   ├── reloc.s          ; relocation coordinator
│   │   │   ├── abs.s            ; absolute relocations
│   │   │   ├── rel.s            ; relative relocations
│   │   │   ├── got.s            ; GOT relocations
│   │   │   ├── plt.s            ; PLT relocations
│   │   │   └── tls.s            ; TLS relocations
│   │   ├── layout.s             ; memory layout calculation
│   │   ├── merge.s              ; section merging
│   │   ├── dead.s               ; dead code elimination
│   │   ├── map.s                ; map file generation
│   │   ├── script.s             ; linker script parser
│   │   └── archive.s            ; static archive (.a) reader
│   │
│   └── output/
│       ├── output.s             ; format dispatcher
│       │
│       ├── elf/
│       │   ├── out.s            ; ELF64 entry point
│       │   ├── header.s         ; EHDR generation
│       │   ├── phdr.s           ; program header
│       │   ├── shdr.s           ; section header
│       │   ├── symtab.s         ; symbol table output
│       │   ├── rela.s           ; RELA relocation output
│       │   ├── strtab.s         ; string table output
│       │   ├── dynamic.s        ; dynamic section
│       │   └── note.s           ; note sections
│       │
│       ├── pe/
│       │   ├── out.s            ; PE32+ entry point
│       │   ├── dos.s            ; DOS stub
│       │   ├── header.s         ; PE header
│       │   ├── optional.s       ; optional header
│       │   ├── section.s        ; section table
│       │   ├── reloc.s          ; relocation table
│       │   ├── export.s         ; export directory
│       │   ├── import.s         ; import directory
│       │   └── cert.s           ; certificate table (Secure Boot)
│       │
│       ├── flat/
│       │   ├── out.s            ; flat binary output
│       │   ├── boot.s           ; boot sector specifics
│       │   └── map.s            ; flat binary map
│       │
│       ├── upk/
│       │   ├── out.s            ; .upk package output
│       │   ├── header.s         ; package header
│       │   ├── meta.s           ; metadata section
│       │   ├── deps.s           ; dependency declarations
│       │   ├── sign.s           ; package signing
│       │   └── compress.s       ; optional compression
│       │
│       └── listing/
│           ├── listing.s        ; assembly listing generator
│           ├── mapfile.s        ; symbol map generator
│           └── symdump.s        ; symbol table dump
│
├── error/                       ; error engine — zero dependencies, built first
│   ├── error.s                  ; entry point
│   ├── table.s                  ; all error codes E1xx–E30xx + messages
│   ├── record.s                 ; error record allocation + storage
│   ├── report.s                 ; main error reporting function
│   ├── format/
│   │   ├── format.s             ; pretty printer coordinator
│   │   ├── header.s             ; "error[E501]:" line
│   │   ├── location.s           ; "  --> file:line:col"
│   │   ├── source.s             ; source line display
│   │   ├── underline.s          ; ^^^ marker generation
│   │   ├── note.s               ; "= note:" lines
│   │   └── hint.s               ; "= hint:" lines
│   ├── chain.s                  ; macro expansion chain display
│   ├── recover/
│   │   ├── recover.s            ; recovery coordinator
│   │   ├── lexer.s              ; lexer stage recovery
│   │   ├── parser.s             ; parser stage recovery
│   │   ├── macro.s              ; macro stage recovery
│   │   └── encoder.s            ; encoder stage recovery
│   ├── filter.s                 ; warning suppression, -W flags
│   ├── flush.s                  ; final sorted output
│   ├── dedup.s                  ; duplicate error removal
│   ├── count.s                  ; error/warning counters
│   ├── hints.s                  ; all hint codes H1xx–H5xx
│   ├── suggest.s                ; hint attachment logic
│   ├── notes.s                  ; all note codes N1xx–N5xx
│   ├── attach.s                 ; note attachment logic
│   └── warnings.s               ; all warning codes W1xx–W20xx
│
├── cpu/                         ; CPU target management
│   ├── cpu.s                    ; entry point
│   ├── profiles/
│   │   ├── profiles.s           ; named CPU profile coordinator
│   │   ├── generic.s            ; generic x86-64
│   │   ├── server.s             ; server-grade profile
│   │   ├── zen4.s               ; AMD Zen 4
│   │   ├── spr.s                ; Intel Sapphire Rapids
│   │   └── custom.s             ; user-defined profiles
│   ├── features.s               ; feature flag management
│   ├── validate.s               ; instruction vs feature validation
│   ├── errata.s                 ; known CPU errata database
│   └── perf.s                   ; performance hint database
│
├── debug/                       ; debug info generation
│   ├── dwarf.s                  ; DWARF v5 entry point
│   ├── cu.s                     ; compilation unit
│   ├── die.s                    ; debug info entries
│   ├── line.s                   ; line number program
│   ├── abbrev.s                 ; abbreviation table
│   ├── aranges.s                ; address range table
│   ├── frame.s                  ; call frame information
│   ├── str.s                    ; string table
│   ├── srcmap.s                 ; source map management
│   ├── file.s                   ; file registry
│   ├── linemap.s                ; line tracking
│   └── macromap.s               ; macro expansion tracking
│
├── optimizer/                   ; output optimization passes
│   ├── optimizer.s              ; entry point
│   ├── jump.s                   ; jump shortening
│   ├── nop.s                    ; NOP padding + removal
│   ├── align.s                  ; alignment optimization
│   ├── peephole.s               ; peephole optimizer
│   ├── prefix.s                 ; redundant prefix removal
│   └── size.s                   ; size reduction passes
│
├── selfpatch/                   ; self-patching engine
│   ├── selfpatch.s              ; entry point
│   ├── patchmap.s               ; internal patch point registry
│   ├── validate.s               ; patch safety validation
│   ├── apply.s                  ; patch application
│   ├── rollback.s               ; rollback on failed patch
│   └── log.s                    ; patch history log
│
├── profiler/                    ; internal execution profiler
│   ├── profiler.s               ; entry point
│   ├── rdtsc.s                  ; TSC-based timing
│   ├── hotpath.s                ; hot path detection
│   ├── report.s                 ; profile report output
│   └── trigger.s                ; triggers selfpatch from profile data
│
├── tools/                       ; built-in tooling
│   ├── disasm/
│   │   ├── disasm.s             ; entry point
│   │   ├── decode.s             ; instruction decoding
│   │   ├── print.s              ; instruction printing
│   │   └── simd.s               ; SIMD instruction decoding
│   │
│   ├── inspector/
│   │   ├── inspector.s          ; entry point
│   │   ├── elf.s                ; ELF inspection
│   │   ├── pe.s                 ; PE32+ inspection
│   │   └── upk.s                ; .upk package inspection
│   │
│   └── symdump/
│       ├── symdump.s            ; entry point
│       └── fmt.s                ; symbol output formatting
│
├── io/                          ; I/O abstraction
│   ├── io.s                     ; entry point
│   ├── file.s                   ; file read/write
│   ├── buf.s                    ; buffered I/O
│   ├── stderr.s                 ; error output (direct write syscall)
│   ├── stdout.s                 ; normal output
│   ├── mmap.s                   ; memory-mapped file input
│   ├── mem.s                    ; mmap/munmap memory management
│   ├── qemu.s                   ; QEMU virtual machine interface
│   └── uring.s                  ; io_uring ring init + async submission
│
├── lib/                         ; internal utility library
│   ├── string.s                 ; string operations
│   ├── fmt.s                    ; string formatting
│   ├── hash.s                   ; hash functions (FNV-1a, xxHash)
│   ├── sort.s                   ; sorting
│   ├── arena.s                  ; arena allocator
│   ├── list.s                   ; linked list
│   ├── vec.s                    ; dynamic array
│   └── math.s                   ; integer math utilities
│
├── host/                        ; host syscall interface
│   └── syscall.s                ; raw syscall ABI
│
├── scripts/
│   ├── bootstrap.sh             ; Gen0 → Gen1 → Gen2 bootstrap pipeline
│   ├── test.sh                  ; test harness orchestrator
│   └── ci.sh                    ; CI pipeline runner
│
└── tests/                       ; test suite root
    └── (see docs/tests.md)      ; full test architecture documented separately
```

---

## Error System

Messages are NASM's, at the line of the statement they are about, so editors
and scripts that read NASM's output read utasm's:

```
prog.s:12: error: invalid combination of opcode and operands
```

On a terminal (or with `--color`) utasm shows more: the line, the place
marked, and why:

```
prog.s:12: error: invalid combination of opcode and operands
    12 |     mov al, rax
       |     ^~~~~~~~~~~
note: `al' is an 8-bit register, `rax' a 64-bit register
note: the operands' sizes differ: 8 and 64 bits

prog.s:7: error: symbol `counter' not defined
     7 | mov eax, [counter]
       |           ^~~~~~~
hint: did you mean 'count'?
```

The mark is on the name the message is about, else where the parser
stopped, else the statement. `--no-color`, `NO_COLOR` or `TERM=dumb` keep
the plain form. Warnings carry NASM's classes (`[-w+zeroing]`) and the
`-w` / `-W` options; see [docs/cli.md](docs/cli.md).

---

## Beyond NASM

utasm takes NASM's syntax and gives NASM's bytes - the compatibility suites
compare them over tens of thousands of cases - and goes further where NASM
leaves the programmer alone:

- **It explains.** The line, the place, the operands' sizes, what to write
  instead (above).
- **It is fast.** The same output as NASM, measured by
  `scripts/compat/bench.py` (x86-64, one core):

  | input | NASM | utasm |
  |---|---|---|
  | 200,000 lines of instructions | 1.42 s | 0.44 s |
  | 200,000 lines of macro calls | 1.88 s | 0.79 s |
  | 100,000 labelled data lines | 1.56 s | 0.65 s |
  | 20,000 jumps among labels | 9.32 s | 1.00 s |
  | 100,000 jumps among labels | 214 s | 6.2 s |

  NASM's passes grow with the square of the jumps; utasm sizes them
  in passes of its own, each a binary search per jump.
- **It is one pass.** No `-O` passes over the source; labels used before
  their definition are worked out at the end, and an instruction that
  uses one gets NASM's short form through a checked second pass.
- **It catches what links badly.** `-w+pie` warns, at the line, about an
  absolute 32-bit address in 64-bit code - the "relocation R_X86_64_32
  ... can not be used when making a PIE object" the linker reports
  later - and says to write `[rel msg]`. A misspelt instruction alone on
  its line (`rett`) gets NASM's label warning and a "did you mean".
- **It never guesses silently.** An operand size it cannot know is an
  error that says what to write (`dword [rax]`), as are addresses NASM
  rejects - two index registers, mixed address sizes.
- **It finds its own bugs.** A fault inside utasm is reported as an
  internal error at the statement being read, not a core dump; the
  fuzzer (`scripts/compat/fuzz.py`) keeps it that way.
- **No fixed limits.** Macro parameters, nesting, line and section counts
  grow as needed.

---

## CPU Profiles

```asm
CPU GENERIC        ; baseline x86-64 only
CPU SERVER         ; server-grade feature set
CPU ZEN4           ; AMD Zen 4 specific
CPU SPR            ; Intel Sapphire Rapids specific
CPU CUSTOM         ; user defined
```

utasm validates every instruction against the active CPU profile and fires `E7xx` errors for unavailable features.

---

## Building

utasm requires NASM and GNU `ld` for the initial bootstrap only. After Gen1 is built, utasm is fully self-sufficient.

**Bootstrap (one command):**

```sh
bash scripts/bootstrap.sh
```

This runs three stages:

```
Stage 1: NASM assembles utasm  →  build/gen0/utasm
Stage 2: Gen0 assembles utasm  →  build/gen1/utasm
Stage 3: Gen1 assembles utasm  →  build/gen2/utasm
Parity:  gen1 and gen2 must be bit-identical
```

**Manual Stage 1:**

```sh
for src in $(find frontend middle backend core error cpu debug optimizer selfpatch profiler io lib host tools -name "*.s") utasm.s cli.s; do
    obj="build/gen0/${src%.s}.o"
    mkdir -p "$(dirname "$obj")"
    nasm -I./ -f elf64 "$src" -o "$obj"
done
ld -o build/gen0/utasm $(find build/gen0 -name "*.o")
```

**Manual Stage 2:**

```sh
for src in $(find frontend middle backend core error cpu debug optimizer selfpatch profiler io lib host tools -name "*.s") utasm.s cli.s; do
    obj="build/gen1/${src%.s}.o"
    mkdir -p "$(dirname "$obj")"
    ./build/gen0/utasm -arch amd64 -f elf64 "$src" -o "$obj"
done
ld -o build/gen1/utasm $(find build/gen1 -name "*.o")
```

---

## Usage

```
utasm [options] <source.s>

Options:
  -f, --format <format>
                    Output format: elf64, bin  (default: elf64)
  -o <file>         Output file                         (default: source.o / source.bin)
  -a, -arch, --arch <arch>
                    Target: amd64, aarch64, riscv64           (default: amd64)
  --standalone      Produce standalone executable (_start resolved)
  --verbose         Enable verbose diagnostics
  --color, --no-color
                    Control diagnostic color
  -Werror           Treat all warnings as errors
  --profile         Enable internal profiler output
  -h, --help        Show this help
  -v, --version     Show version
```

**Examples:**

```sh
# Standalone AMD64 executable
utasm -arch amd64 -f elf64 --standalone main.s -o hello

# Relocatable object file
utasm -arch amd64 -f elf64 src/scheduler.s -o build/scheduler.o

# AArch64 cross-compile
utasm -arch aarch64 -f elf64 --standalone main.s -o hello_arm

# RISC-V 64 cross-compile
utasm -arch riscv64 -f elf64 --standalone main.s -o hello_rv64

# Produce a standalone executable and an internal compile profile
utasm -arch amd64 -f elf64 --standalone --profile main.s -o main
```

---

## Running Tests

```sh
bash scripts/bootstrap.sh   # build Gen1 first
bash scripts/test.sh        # run full test suite
```

See [tests.md](docs/tests.md) for the complete test architecture.

---

## Requirements

| Dependency | Purpose | Required |
|---|---|---|
| NASM | Gen0 bootstrap compilation | Yes (once) |
| GNU ld | Linking Gen0 and Gen1 | Yes (once) |
| QEMU | Cross-arch smoke test execution | Optional |

> After bootstrap, utasm has zero external dependencies. It assembles and links itself entirely.

---

## Self-Patching

When `--selfpatch` is enabled:

```
1. Profiler measures hot paths via RDTSC
2. Hot path detector identifies slow encoding routines
3. Self-patch engine validates safety of proposed patch
4. Patch applied directly to running binary in memory
5. Rollback triggered automatically if patch degrades performance
6. Patch log written to utasm.patch.log
```

---

## Versioning

Tracked in [`VERSION`](VERSION). Follows [Semantic Versioning](https://semver.org/).

---

## License

Released under the [Apache License 2.0](LICENSE).

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
