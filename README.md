# utasm

> A high-performance, self-hosting, multi-architecture assembler and linker — written entirely in x86-64 assembly.

`utasm` is the universal assembler engine of the UtkarshaLab toolchain. It targets three architectures from a single, unified codebase, produces correct ELF64 binaries, and is designed to assemble itself.

---

## Features

- **Multi-Architecture** — Native instruction encoding for x86-64, AArch64, and RISC-V 64 (RV64GC)
- **Integrated Linker** — ELF64 emission with section layout, program headers, symbol tables, and relocation resolution
- **Recursive Preprocessor** — `%define`, `%macro`, `%if` with full compile-time expression evaluation
- **O(1) Symbol Table** — Hash-based lookup with quadratic probing and precise ELF index tracking
- **Standalone Executables** — Dynamic `_start` entry-point resolution injected directly into ELF `e_entry`
- **BSS Support** — Zero-disk-footprint `SHT_NOBITS` sections with correct `p_memsz` aggregation
- **SIMD Coverage** — AVX/AVX2 (VEX-3), AArch64 NEON/SVE, and RISC-V V extension foundations
- **DWARF v5** — Full debug symbol emission (`.debug_info`, `.debug_abbrev`)
- **io_uring I/O** — Asynchronous file write foundation for ultra-fast multi-megabyte builds
- **Self-Hosting** — Bootstrap pipeline (`scripts/bootstrap.sh`) that compiles Gen0 via NASM and Gen1 via itself

---

## Supported Architectures

| Architecture | Base ISA   | Extensions                |
| ------------ | ---------- | ------------------------- |
| x86-64       | RV64I-like | REX, VEX-3, AVX/AVX2, SSE |
| AArch64      | ARMv8-A    | NEON Advanced SIMD, SVE   |
| RISC-V 64    | RV64GC     | M, A, F, D, V extensions  |

---

## Project Structure

```
utasm/
├── include/              # Architecture-agnostic headers and kernel constants
│   ├── arch/             # Architecture-specific register and opcode maps
│   │   ├── amd64.s       # x86-64 register encodings and opcode maps
│   │   ├── aarch64.s     # AArch64 register encodings and opcode maps
│   │   └── riscv64.s     # RISC-V 64 register encodings and opcode maps
│   ├── archive.s         # Static archive (.a) reader definitions
│   ├── constant.s        # Global constants (exit codes, flags, limits)
│   ├── elf.s             # Full ELF64 struct offsets and constants
│   ├── macro.s           # Prologue/epilogue and utility macros
│   ├── macro1.s          # Extended preprocessor macros
│   ├── register.s        # Register aliases across all three architectures
│   ├── syscall.s         # Linux syscall numbers (AMD64, AArch64, RISC-V)
│   ├── type.s            # Internal type tags and struct field offsets
│   └── uring.s           # io_uring SQE/CQE struct definitions
│
├── src/
│   ├── main.s            # Entry point, CLI dispatch, version string
│   ├── cli.s             # Command-line argument parser
│   ├── core/
│   │   ├── archive.s     # Static archive (.a) format reader
│   │   ├── lexer.s       # Token scanner
│   │   ├── parser.s      # Recursive descent expression parser
│   │   ├── preprocessor.s# Macro engine (%define, %macro, %if, %rep)
│   │   ├── symbol.s      # Hash-based symbol table
│   │   ├── asmctx.s      # Assembler context and section state
│   │   ├── arena.s       # Arena allocator
│   │   ├── error.s       # Industrial error formatting (line/col caret)
│   │   ├── diagnostics.s # Diagnostic reporting and warning subsystem
│   │   └── string.s      # String utilities
│   ├── encoder/
│   │   ├── amd64.s       # x86-64 instruction encoder (REX, VEX, SIB)
│   │   ├── aarch64.s     # AArch64 fixed-width instruction encoder
│   │   └── riscv64.s     # RISC-V 64 encoder with relaxation support
│   ├── isa/
│   │   ├── amd64.s       # AMD64 instruction table
│   │   ├── aarch64.s     # AArch64 instruction table
│   │   └── riscv64.s     # RISC-V 64 instruction table
│   ├── linker/
│   │   ├── elf64.s       # ELF64 binary emitter (EHDR, PHDR, SHDR, RELA)
│   │   ├── reloc.s       # Multi-section relocation engine
│   │   ├── linker.s      # Linker coordinator
│   │   ├── binary.s      # Flat binary output
│   │   └── script.s      # Linker script parser
│   ├── output/
│   │   ├── listing.s     # Assembly listing file generator
│   │   ├── mapfile.s     # Symbol map file generator
│   │   └── symdump.s     # Symbol table dump utility
│   └── host/
│       ├── io.s          # Raw Linux syscall I/O (read, write, open, close)
│       ├── mem.s         # Memory management (mmap, munmap)
│       ├── qemu.s        # QEMU virtual machine interface helpers
│       └── uring.s       # io_uring ring initialization and async submission
│
├── tests/
│   ├── amd64/            # Sub-test specifications for x86-64 validation
│   ├── aarch64/          # Sub-test specifications for AArch64 validation
│   ├── riscv64/          # Sub-test specifications for RISC-V validation
│   ├── common/           # Common test structures and helper suites
│   ├── hello_amd64.s     # Standalone AMD64 smoke test (raw syscall)
│   ├── hello_aarch64.s   # Standalone AArch64 smoke test
│   ├── hello_riscv64.s   # Standalone RISC-V 64 smoke test
│   ├── amd64_suite.s     # Comprehensive x86-64 instruction validation
│   ├── aarch64_suite.s   # Comprehensive AArch64 instruction validation
│   └── riscv64_suite.s   # Comprehensive RV64GC instruction validation
│
├── scripts/
│   ├── bootstrap.sh      # Gen0 (NASM) → Gen1 (utasm) bootstrap pipeline
│   └── test.sh           # Sovereign test harness orchestrator
│
├── utasm.toml            # Project manifest (sources, build targets, test runner)
├── utasm.ld              # Linker script for self-hosted builds
├── VERSION               # Current release version
└── LICENSE               # Apache-2.0
```

---

## Building

`utasm` requires a Linux host with NASM and GNU `ld` available. The bootstrap script handles the full two-stage compilation.

**Stage 1 — Build Gen0 compiler using NASM:**

To build manually by assembling all source files and linking them together:

```sh
# Assemble all source files under src/ into build/gen0
for src_file in $(find src -name "*.s"); do
    obj_file="build/gen0/${src_file%.s}.o"
    mkdir -p "$(dirname "$obj_file")"
    nasm -I./ -f elf64 "$src_file" -o "$obj_file"
done

# Link all object files into the Gen0 binary
ld -o build/gen0/utasm $(find build/gen0 -name "*.o")
```

**Stage 2 — Self-host: compile Gen1 using Gen0:**

```sh
# Compile all source files using the newly built Gen0 binary
for src_file in $(find src -name "*.s"); do
    obj_file="build/gen1/${src_file%.s}.o"
    mkdir -p "$(dirname "$obj_file")"
    ./build/gen0/utasm -f elf64 "$src_file" -o "$obj_file"
done

# Link all Gen1 object files
ld -o build/gen1/utasm $(find build/gen1 -name "*.o")
```

Or run the full bootstrap pipeline (which compiles Stage 1, Stage 2, Stage 3 self-hosting, and executes strict parity checks) in one command:

```sh
bash scripts/bootstrap.sh
```

---

## Usage

```
utasm [options] <source.s>

Options:
  -f <format>     Output format: elf64, bin  (default: elf64)
  -o <file>       Output file                (default: a.out)
  -arch <arch>    Target architecture: amd64, aarch64, riscv64
  --standalone    Produce a standalone executable (resolves _start)
  --list          Generate assembly listing file
  --map           Generate symbol map file
  -h, --help      Show this help message
```

**Assemble a standalone AMD64 executable:**

```sh
utasm -f elf64 --standalone tests/hello_amd64.s -o hello
chmod +x hello && ./hello
```

**Assemble a relocatable object:**

```sh
utasm -f elf64 src/main.s -o build/main.o
```

---

## Running Tests

The sovereign test harness requires the Gen1 binary to be built first:

```sh
bash scripts/bootstrap.sh
bash scripts/test.sh
```

Expected output:

```
[+] Initiating UtkarshaLab Sovereign Test Harness...
    [*] Assembling amd64_suite... OK
    [*] Assembling aarch64_suite... OK
    [*] Assembling riscv64_suite... OK
============================================================
    SOVEREIGN TEST RESULTS: 3 Passed | 0 Failed
============================================================
[+] VALIDATION SUCCESSFUL: Absolute architectural parity achieved.
```

---

## Requirements

| Dependency | Purpose                         | Required |
| ---------- | ------------------------------- | -------- |
| Linux      | Raw syscall ABI, ELF loader     | Yes      |
| NASM       | Gen0 bootstrap compilation      | Yes      |
| GNU ld     | Linking Gen0 and Gen1           | Yes      |
| QEMU       | Cross-arch smoke test execution | Optional |

> **Note:** `utasm` uses raw Linux syscalls for all I/O. macOS and Windows are not supported as execution targets. Cross-compilation from a Windows host is possible; use WSL2 or a Linux CI runner for linking and execution.

---

## Versioning

The current release version is tracked in the [`VERSION`](VERSION) file. `utasm` follows [Semantic Versioning](https://semver.org/).

---

## License

`utasm` is released under the [Apache License 2.0](LICENSE).

---

_UtkarshaLab — Engineering the Foundation of Tomorrow_
