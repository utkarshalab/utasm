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

> This is the target architecture. The repo converges toward this layout incrementally.

```
utasm/
│
├── utasm.asm                    ; entry point, argument parsing, main loop
│
├── core/
│   ├── config.inc               ; global constants, CPU targets, version
│   ├── types.inc                ; all struc definitions used everywhere
│   ├── globals.asm              ; global variables, state
│   └── memory.asm               ; internal allocator (bump + slab)
│
├── frontend/
│   │
│   ├── lexer/
│   │   ├── lexer.asm            ; main lexer entry point
│   │   ├── lexer_chars.asm      ; character classification tables
│   │   ├── lexer_ident.asm      ; identifier + keyword scanning
│   │   ├── lexer_number.asm     ; integer + float literal parsing
│   │   │   ├── lexer_num_bin.asm   ; binary literal (0b...)
│   │   │   ├── lexer_num_oct.asm   ; octal literal (0o...)
│   │   │   ├── lexer_num_hex.asm   ; hex literal (0x...)
│   │   │   └── lexer_num_dec.asm   ; decimal literal
│   │   ├── lexer_string.asm     ; string + char literal scanning
│   │   ├── lexer_comment.asm    ; line + block comment handling
│   │   ├── lexer_token.asm      ; token creation, source map attachment
│   │   ├── lexer_buffer.asm     ; token buffer management
│   │   └── lexer_utf8.asm       ; UTF-8 validation
│   │
│   ├── parser/
│   │   ├── parser.asm           ; main parser entry point
│   │   ├── parser_instr.asm     ; instruction statement parsing
│   │   ├── parser_operand.asm   ; operand parsing (reg/mem/imm)
│   │   │   ├── parser_reg.asm      ; register operand parsing
│   │   │   ├── parser_mem.asm      ; memory operand parsing
│   │   │   ├── parser_imm.asm      ; immediate operand parsing
│   │   │   └── parser_addr.asm     ; addressing mode resolution
│   │   ├── parser_directive.asm ; directive statement parsing
│   │   ├── parser_label.asm     ; label definition parsing
│   │   ├── parser_expr.asm      ; expression parsing (Pratt parser)
│   │   ├── parser_section.asm   ; section directive parsing
│   │   ├── parser_data.asm      ; DB/DW/DD/DQ/DT/DO/DY/DZ parsing
│   │   ├── parser_struct.asm    ; STRUC/ENDSTRUC parsing
│   │   ├── parser_proc.asm      ; PROC/ENDPROC parsing
│   │   ├── parser_ast.asm       ; AST node allocation + construction
│   │   └── parser_recover.asm   ; parser error recovery logic
│   │
│   └── macro/
│       ├── macro.asm            ; macro engine entry point
│       ├── macro_define.asm     ; %define, %macro, %imacro handling
│       ├── macro_expand.asm     ; macro expansion engine
│       ├── macro_args.asm       ; argument parsing + substitution
│       ├── macro_local.asm      ; local label generation inside macros
│       ├── macro_cond.asm       ; %if/%elif/%else/%endif handling
│       │   ├── macro_cond_def.asm  ; %ifdef/%ifndef
│       │   ├── macro_cond_expr.asm ; %if expression evaluation
│       │   └── macro_cond_str.asm  ; %ifidn/%ifidni string compare
│       ├── macro_rep.asm        ; %rep/%endrep handling
│       ├── macro_rotate.asm     ; %rotate handling
│       ├── macro_stringify.asm  ; %str() stringification
│       ├── macro_paste.asm      ; token pasting (##)
│       ├── macro_include.asm    ; %include file handling
│       ├── macro_library.asm    ; macro library (.inc) management
│       ├── macro_table.asm      ; macro definition hash table
│       ├── macro_chain.asm      ; expansion chain tracking (for errors)
│       └── macro_purge.asm      ; %undef/%purge handling
│
├── middle/
│   │
│   ├── semantic/
│   │   ├── semantic.asm         ; semantic analysis entry point
│   │   ├── semantic_instr.asm   ; instruction validation
│   │   ├── semantic_operand.asm ; operand type checking
│   │   ├── semantic_size.asm    ; operand size resolution
│   │   ├── semantic_type.asm    ; type checking + coercion
│   │   ├── semantic_scope.asm   ; scope rules enforcement
│   │   ├── semantic_proc.asm    ; PROC boundary validation
│   │   └── semantic_data.asm    ; data definition validation
│   │
│   ├── symtable/
│   │   ├── symtable.asm         ; symbol table entry point
│   │   ├── symtable_hash.asm    ; hash table implementation
│   │   ├── symtable_insert.asm  ; symbol insertion
│   │   ├── symtable_lookup.asm  ; symbol lookup
│   │   ├── symtable_resolve.asm ; forward reference resolution
│   │   ├── symtable_scope.asm   ; scope management
│   │   ├── symtable_global.asm  ; global/extern declaration
│   │   ├── symtable_local.asm   ; local label management
│   │   ├── symtable_common.asm  ; COMMON symbol handling
│   │   ├── symtable_weak.asm    ; weak symbol handling
│   │   └── symtable_dump.asm    ; debug: dump symbol table
│   │
│   └── expr/
│       ├── expr.asm             ; expression evaluator entry point
│       ├── expr_arith.asm       ; arithmetic operations
│       ├── expr_bitwise.asm     ; bitwise operations
│       ├── expr_compare.asm     ; comparison operations
│       ├── expr_logical.asm     ; logical operations
│       ├── expr_unary.asm       ; unary operators
│       ├── expr_const.asm       ; constant folding
│       ├── expr_reloc.asm       ; relocatable expression handling
│       └── expr_overflow.asm    ; overflow detection
│
├── backend/
│   │
│   ├── encoder/
│   │   ├── encoder.asm          ; encoder entry point
│   │   ├── encoder_dispatch.asm ; instruction → handler dispatch table
│   │   │
│   │   ├── x86/                 ; x86_64 instruction encoding
│   │   │   ├── enc_mov.asm
│   │   │   ├── enc_arith.asm    ; ADD/SUB/MUL/DIV/ADC/SBB
│   │   │   ├── enc_logic.asm    ; AND/OR/XOR/NOT
│   │   │   ├── enc_shift.asm    ; SHL/SHR/SAR/ROL/ROR/RCL/RCR
│   │   │   ├── enc_jump.asm     ; JMP/Jcc/LOOP
│   │   │   ├── enc_call.asm     ; CALL/RET
│   │   │   ├── enc_stack.asm    ; PUSH/POP
│   │   │   ├── enc_string.asm   ; MOVS/STOS/LODS/SCAS/CMPS + REP
│   │   │   ├── enc_bit.asm      ; BT/BTS/BTR/BTC/BSF/BSR/TZCNT/LZCNT
│   │   │   ├── enc_cmov.asm     ; CMOVcc
│   │   │   ├── enc_setcc.asm    ; SETcc
│   │   │   ├── enc_flag.asm     ; CLC/STC/CMC/CLD/STD/CLI/STI
│   │   │   ├── enc_io.asm       ; IN/OUT
│   │   │   ├── enc_system.asm   ; SYSCALL/SYSRET/HLT/NOP/CPUID/RDTSC
│   │   │   ├── enc_priv.asm     ; privileged: LGDT/LIDT/LTR...
│   │   │   ├── enc_misc.asm     ; LEA/XCHG/CMPXCHG/BSWAP/MOVBE
│   │   │   └── enc_crypto.asm   ; AES-NI/SHA/PCLMULQDQ
│   │   │
│   │   ├── simd/                ; SIMD instruction encoding
│   │   │   ├── enc_mmx.asm
│   │   │   ├── enc_sse.asm
│   │   │   ├── enc_sse2.asm
│   │   │   ├── enc_sse3.asm     ; SSE3/SSSE3
│   │   │   ├── enc_sse4.asm     ; SSE4.1/SSE4.2
│   │   │   ├── enc_avx.asm      ; VEX encoded
│   │   │   ├── enc_avx2.asm
│   │   │   ├── enc_avx512.asm   ; EVEX foundation
│   │   │   │   ├── enc_avx512bw.asm
│   │   │   │   ├── enc_avx512dq.asm
│   │   │   │   ├── enc_avx512vl.asm
│   │   │   │   ├── enc_avx512vnni.asm
│   │   │   │   └── enc_avx512bf16.asm
│   │   │   ├── enc_amx.asm      ; AMX tile instructions
│   │   │   └── enc_fpu.asm      ; x87 FPU
│   │   │
│   │   ├── prefix/              ; prefix encoding
│   │   │   ├── enc_rex.asm
│   │   │   ├── enc_vex.asm
│   │   │   ├── enc_evex.asm
│   │   │   ├── enc_lock.asm
│   │   │   └── enc_rep.asm
│   │   │
│   │   └── tables/              ; encoding tables
│   │       ├── opcode_table.asm
│   │       ├── modrm_table.asm
│   │       ├── sib_table.asm
│   │       ├── reg_table.asm
│   │       └── cpu_features.asm
│   │
│   ├── linker/
│   │   ├── linker.asm
│   │   ├── linker_section.asm
│   │   ├── linker_symbol.asm
│   │   ├── linker_reloc.asm
│   │   │   ├── reloc_abs.asm
│   │   │   ├── reloc_rel.asm
│   │   │   ├── reloc_got.asm
│   │   │   ├── reloc_plt.asm
│   │   │   └── reloc_tls.asm
│   │   ├── linker_layout.asm
│   │   ├── linker_merge.asm
│   │   ├── linker_dead.asm      ; dead code elimination
│   │   ├── linker_map.asm
│   │   └── linker_script.asm
│   │
│   └── output/
│       ├── output.asm           ; format dispatcher
│       │
│       ├── elf/
│       │   ├── elf_out.asm
│       │   ├── elf_header.asm
│       │   ├── elf_phdr.asm
│       │   ├── elf_shdr.asm
│       │   ├── elf_symtab.asm
│       │   ├── elf_rela.asm
│       │   ├── elf_strtab.asm
│       │   ├── elf_dynamic.asm
│       │   └── elf_note.asm
│       │
│       ├── pe/
│       │   ├── pe_out.asm
│       │   ├── pe_dos.asm
│       │   ├── pe_header.asm
│       │   ├── pe_optional.asm
│       │   ├── pe_section.asm
│       │   ├── pe_reloc.asm
│       │   ├── pe_export.asm
│       │   ├── pe_import.asm
│       │   └── pe_cert.asm      ; Secure Boot signing
│       │
│       ├── flat/
│       │   ├── flat_out.asm
│       │   ├── flat_boot.asm
│       │   └── flat_map.asm
│       │
│       └── upk/
│           ├── upk_out.asm
│           ├── upk_header.asm
│           ├── upk_meta.asm
│           ├── upk_deps.asm
│           ├── upk_sign.asm
│           └── upk_compress.asm
│
├── error/
│   ├── error.asm
│   ├── error_table.asm          ; all error codes + messages
│   ├── error_record.asm
│   ├── error_report.asm
│   ├── error_format.asm         ; pretty printer
│   │   ├── fmt_header.asm          ; "error[E501]:" line
│   │   ├── fmt_location.asm        ; "  --> file:line:col"
│   │   ├── fmt_source.asm          ; source line display
│   │   ├── fmt_underline.asm       ; ^^^ marker
│   │   ├── fmt_note.asm            ; "= note:" lines
│   │   └── fmt_hint.asm            ; "= hint:" lines
│   ├── error_chain.asm          ; macro expansion chain display
│   ├── error_recover.asm
│   │   ├── recover_lexer.asm
│   │   ├── recover_parser.asm
│   │   ├── recover_macro.asm
│   │   └── recover_encoder.asm
│   ├── error_filter.asm         ; warning suppression, -W flags
│   ├── error_flush.asm          ; sorted final output
│   ├── error_dedup.asm
│   ├── error_count.asm
│   ├── hint_table.asm
│   ├── hint_suggest.asm
│   ├── note_table.asm
│   └── note_attach.asm
│
├── debug/
│   ├── dwarf.asm
│   ├── dwarf_cu.asm             ; compilation unit
│   ├── dwarf_die.asm            ; debug info entries
│   ├── dwarf_line.asm           ; line number program
│   ├── dwarf_abbrev.asm
│   ├── dwarf_aranges.asm
│   ├── dwarf_frame.asm          ; call frame information
│   ├── dwarf_str.asm
│   ├── srcmap.asm               ; source map management
│   ├── srcmap_file.asm
│   ├── srcmap_line.asm
│   └── srcmap_macro.asm
│
├── cpu/
│   ├── cpu.asm
│   ├── cpu_profiles.asm
│   │   ├── profile_generic.asm
│   │   ├── profile_server.asm   ; TATTVA_SERVER
│   │   ├── profile_zen4.asm
│   │   ├── profile_spr.asm      ; Intel Sapphire Rapids
│   │   └── profile_custom.asm
│   ├── cpu_features.asm
│   ├── cpu_validate.asm
│   ├── cpu_errata.asm
│   └── cpu_perf.asm
│
├── optimizer/
│   ├── optimizer.asm
│   ├── opt_jump.asm             ; jump shortening
│   ├── opt_nop.asm
│   ├── opt_align.asm
│   ├── opt_peephole.asm
│   ├── opt_prefix.asm           ; redundant prefix removal
│   └── opt_size.asm
│
├── selfpatch/
│   ├── selfpatch.asm
│   ├── selfpatch_map.asm        ; patch point registry
│   ├── selfpatch_validate.asm
│   ├── selfpatch_apply.asm
│   ├── selfpatch_rollback.asm
│   └── selfpatch_log.asm
│
├── profiler/
│   ├── profiler.asm
│   ├── profiler_rdtsc.asm
│   ├── profiler_hotpath.asm
│   ├── profiler_report.asm
│   └── profiler_trigger.asm     ; triggers selfpatch from profile data
│
├── tools/
│   ├── disasm/
│   │   ├── disasm.asm
│   │   ├── disasm_decode.asm
│   │   ├── disasm_print.asm
│   │   └── disasm_simd.asm
│   ├── inspector/
│   │   ├── inspector.asm
│   │   ├── inspect_elf.asm
│   │   ├── inspect_pe.asm
│   │   └── inspect_upk.asm
│   └── symdump/
│       ├── symdump.asm
│       └── symdump_fmt.asm
│
├── io/
│   ├── io.asm
│   ├── io_file.asm
│   ├── io_buf.asm
│   ├── io_stderr.asm
│   ├── io_stdout.asm
│   └── io_mmap.asm
│
├── lib/
│   ├── string.asm
│   ├── string_fmt.asm
│   ├── hash.asm                 ; FNV-1a, xxHash
│   ├── sort.asm
│   ├── arena.asm
│   ├── list.asm
│   ├── vec.asm                  ; dynamic array
│   └── math.asm
│
├── tests/                       ; full test suite — see TESTS.md
│
├── include/                     ; standard macro library (.inc files)
│   ├── utasm.inc
│   ├── x86_64.inc
│   ├── elf.inc
│   ├── pe.inc
│   ├── syscall.inc              ; syscall numbers (Tattva OS)
│   ├── simd.inc
│   ├── debug.inc
│   └── upk.inc
│
├── scripts/
│   ├── bootstrap.sh             ; Gen0 → Gen1 → parity check
│   └── test.sh                  ; test harness orchestrator
│
├── docs/
│   ├── dev_guide.md
│   └── error_reference.md
│
├── Makefile
├── utasm.toml
├── utasm.ld
├── VERSION
└── LICENSE
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
