# utasm

> A high-performance, self-hosting, multi-architecture assembler and linker — written entirely in x86-64 assembly.

`utasm` is the universal assembler engine of the UtkarshaLab toolchain. It targets three architectures from a single unified codebase, produces correct ELF64 binaries, and is designed to assemble itself.

---

## Features

- **Multi-Architecture** — Native instruction encoding for x86-64, AArch64, and RISC-V 64 (RV64GC)
- **Integrated Linker** — ELF64 emission with section layout, program headers, symbol tables, and RELA relocation resolution
- **Recursive Preprocessor** — `%define`, `%macro`, `%if`, `%rep` with full compile-time expression evaluation and token pasting
- **O(1) Symbol Table** — FNV-1a hash with quadratic probing, 50% load-factor cap, forward-reference resolution
- **Self-Patching Engine** — Runtime binary modification driven by RDTSC profiler data; hot paths rewritten without restart
- **CPU Profile Validation** — Target CPU feature flags validated at encode time (`cpu/<profile>.s`)
- **SIMD Coverage** — AVX/AVX2 (VEX-3/EVEX), AArch64 NEON/SVE, RISC-V V extension foundations
- **DWARF v5** — Full debug symbol emission (`.debug_info`, `.debug_abbrev`, `.debug_line`)
- **io_uring I/O** — Asynchronous file operations for ultra-fast multi-megabyte builds
- **Self-Hosting** — Bootstrap pipeline (`scripts/bootstrap.sh`) that builds Gen0 via NASM and Gen1 via itself
- **ELF Section Groups** — SHT_GROUP + COMDAT support
- **BSS / Common Symbols** — SHT_NOBITS with zero disk footprint; SHN_COMMON handling
- **Static Archive I/O** — `.a` reader and generator
- **Struct Support** — STRUC/ENDSTRUC with field alignment

---

## Supported Architectures

| Architecture | Base ISA | Extensions                     |
| ------------ | -------- | ------------------------------ |
| x86-64       | AMD64    | REX, VEX-3, EVEX, AVX/AVX-512 |
| AArch64      | ARMv8-A  | NEON Advanced SIMD, SVE        |
| RISC-V 64    | RV64GC   | M, A, F, D, V extensions       |

---

## Project Structure

```
utasm/
├── utasm.s                   # Entry point — CLI dispatch
├── include/                  # Shared headers (arch-agnostic)
│   ├── arch/                 # Per-arch register and opcode maps
│   │   ├── amd64.inc
│   │   ├── aarch64.inc
│   │   └── riscv64.inc
│   ├── constant.inc          # Global constants (exit codes, limits, flags)
│   ├── elf.inc               # ELF64 struct offsets and constants
│   ├── macro.inc             # prologue/epilogue and utility macros
│   ├── register.inc          # Register aliases across all three architectures
│   ├── syscall.inc           # Linux syscall numbers (AMD64, AArch64, RISC-V)
│   ├── type.inc              # Internal type tags and struct field offsets
│   └── uring.inc             # io_uring SQE/CQE struct definitions
│
├── frontend/                 # Source text → tokens → parse tree
│   ├── lexer/                # Character stream → token stream
│   │   └── lexer.s
│   ├── parser/               # Token stream → parse tree
│   │   └── parser.s
│   └── macro/                # Preprocessing, macro expansion, conditionals
│       └── preprocessor.s
│
├── middle/                   # Parse tree → validated, resolved IR
│   ├── semantic/             # Type checking, operand validation
│   │   └── semantic.s
│   ├── symtable/             # O(1) hash table, forward references
│   │   └── symbol.s
│   └── expr/                 # Constant folding, relocation expressions
│       └── expr.s
│
├── backend/                  # IR → binary output
│   ├── encoder/              # Instruction → bytes (arch-specific)
│   │   ├── amd64/
│   │   ├── aarch64/
│   │   └── riscv64/
│   ├── isa/                  # Instruction tables per architecture
│   │   ├── amd64.s
│   │   ├── aarch64.s
│   │   └── riscv64.s
│   ├── linker/               # Section layout, relocation, symbol resolution
│   │   ├── linker.s
│   │   ├── elf64.s
│   │   ├── reloc.s
│   │   └── script.s
│   └── output/               # ELF64 / PE32+ / flat / .upk emission
│       ├── elf64/
│       ├── pe32plus/
│       ├── flat/
│       └── upk/
│
├── core/                     # Shared runtime primitives
│   ├── arena.s               # Arena allocator
│   ├── asmctx.s              # Assembler context and section state
│   └── string.s              # String utilities
│
├── error/                    # Error engine (zero dependencies, runs at all stages)
│   ├── error.s               # Error formatting (line/col caret)
│   └── table.s               # Error code → message string table
│
├── cpu/                      # CPU profile validation and feature flags
│   ├── features.s
│   └── profiles/
│
├── debug/                    # DWARF v5 emission
│   └── dwarf.s
│
├── optimizer/                # Post-encoding optimization passes
│   └── optimizer.s
│
├── selfpatch/                # Runtime binary self-modification
│   └── selfpatch.s
│
├── profiler/                 # RDTSC-based hot path measurement
│   └── profiler.s
│
├── io/                       # Platform I/O abstraction
│   ├── io.s                  # Raw Linux syscall I/O
│   └── uring.s               # io_uring ring initialization and async submission
│
├── lib/                      # Shared library utilities
│   └── archive.s             # Static archive (.a) reader and generator
│
├── host/                     # Host-platform helpers
│   ├── mem.s                 # Memory management (mmap, munmap)
│   └── qemu.s                # QEMU interface helpers
│
├── tools/                    # Developer tooling
│   ├── listing.s             # Assembly listing file generator
│   ├── mapfile.s             # Symbol map file generator
│   └── symdump.s             # Symbol table dump utility
│
├── tests/                    # Full test suite (see TESTS.md)
│   ├── unit/
│   ├── error/
│   ├── warning/
│   ├── integration/
│   ├── regression/
│   ├── fuzz/
│   ├── perf/
│   └── stress/
│
├── scripts/
│   ├── bootstrap.sh          # Gen0 (NASM) → Gen1 (utasm) bootstrap pipeline
│   └── test.sh               # Test harness orchestrator
│
├── docs/
│   ├── dev_guide.md          # How to add instructions, errors, CPU profiles
│   └── error_reference.md    # Full error code table (E101–E9xx)
│
├── Makefile                  # Build shortcuts (gen0, gen1, test, clean)
├── utasm.toml                # Project manifest
├── utasm.ld                  # Linker script for self-hosted builds
├── VERSION                   # Current release version
└── LICENSE                   # Apache-2.0
```

---

## Building

`utasm` requires a Linux host (or WSL2) with NASM and GNU `ld`.

```sh
# Full bootstrap: Gen0 (NASM) → Gen1 (utasm) → parity check
make gen1

# Or step by step:
make gen0          # Build Gen0 using NASM
make gen1          # Build Gen1 using Gen0, verify binary parity
make test          # Run full test suite against Gen1
make clean         # Remove all build artifacts
```

**Manual bootstrap:**

```sh
bash scripts/bootstrap.sh
```

---

## Usage

```
utasm [options] <source.s>

Options:
  -f <format>     Output format: elf64, pe32plus, bin, upk  (default: elf64)
  -o <file>       Output file                               (default: a.out)
  -arch <arch>    Target architecture: amd64, aarch64, riscv64
  -cpu <profile>  CPU profile for feature-flag validation
  --standalone    Produce a standalone executable (resolves _start)
  --list          Generate assembly listing file
  --map           Generate symbol map file
  --dwarf         Emit DWARF v5 debug information
  -h, --help      Show this help message
  -v, --version   Print version and exit
```

**Assemble a standalone AMD64 executable:**

```sh
utasm -f elf64 --standalone tests/integration/hello/hello_amd64.s -o hello
chmod +x hello && ./hello
```

**Assemble a relocatable object:**

```sh
utasm -f elf64 frontend/lexer/lexer.s -o build/lexer.o
```

**Cross-assemble for AArch64:**

```sh
utasm -arch aarch64 -f elf64 tests/integration/hello/hello_aarch64.s -o hello_arm
qemu-aarch64 hello_arm
```

---

## Running Tests

```sh
make test
```

Or with the harness directly:

```sh
bash scripts/bootstrap.sh   # ensure Gen1 is built
bash scripts/test.sh        # run all test categories
```

Expected output:

```
[+] Initiating UtkarshaLab Test Harness...
    [*] unit/encoder/amd64...       OK
    [*] unit/encoder/aarch64...     OK
    [*] unit/encoder/riscv64...     OK
    [*] integration/hello/amd64...  OK (native)
    [*] integration/hello/aarch64.. OK (qemu-aarch64)
    [*] integration/hello/riscv64.. OK (qemu-riscv64)
============================================================
    TEST RESULTS: N Passed | 0 Failed
============================================================
[+] VALIDATION SUCCESSFUL: Absolute architectural parity achieved.
```

---

## Requirements

| Dependency   | Purpose                         | Required |
| ------------ | ------------------------------- | -------- |
| Linux / WSL2 | Raw syscall ABI, ELF loader     | Yes      |
| NASM         | Gen0 bootstrap compilation      | Yes      |
| GNU ld       | Linking Gen0 and Gen1           | Yes      |
| QEMU         | Cross-arch smoke test execution | Optional |

---

## Documentation

| Document                                  | What it covers                                      |
| ----------------------------------------- | --------------------------------------------------- |
| [ARCHITECTURE.md](ARCHITECTURE.md)        | Design rationale — why every major decision was made |
| [CONTRIBUTING.md](CONTRIBUTING.md)        | Code style, naming conventions, how to add features |
| [TESTS.md](TESTS.md)                      | Full test architecture and naming conventions       |
| [CHANGELOG.md](CHANGELOG.md)             | Release history                                     |
| [docs/dev_guide.md](docs/dev_guide.md)   | Step-by-step: add instruction, error, CPU profile   |
| [docs/error_reference.md](docs/error_reference.md) | Full error code table (E101–E9xx)         |

---

## Versioning

Tracked in [`VERSION`](VERSION). Follows [Semantic Versioning](https://semver.org/).

---

## License

Released under the [Apache License 2.0](LICENSE).

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
