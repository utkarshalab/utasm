# Changelog

All meaningful changes to utasm are tracked here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- New project structure: `frontend/`, `middle/`, `backend/`, `core/`, `error/`, `cpu/`, `debug/`, `optimizer/`, `selfpatch/`, `profiler/`, `tools/`, `io/`, `lib/`, `host/`
- `docs/tests.md` — full test architecture documentation
- `docs/architecture.md` — design rationale and decisions
- CONTRIBUTING.md — contribution guidelines
- CHANGELOG.md — this file
- Makefile — development command shortcuts
- `docs/error_reference.md` — full error code table
- `docs/dev_guide.md` — developer guide for adding instructions, errors, CPU profiles
- `--disasm`: 16- and 32-bit mode (`--bits`), raw files (`--org`), ELF32 input, `-r` relocations, objdump's symbol annotations and `# addr <sym>` after `[rip]` operands
- `scripts/compat/disasm_scan.py` — the opcode space (prefix × map × opcode × ModRM, 133,320 cases a mode) against objdump 2.47
- EXIT_MASK_REFUSED (181): a write mask / `{z}` the instruction does not take is refused (#UD)

### Fixed
- `--disasm` reads every encoding as objdump 2.47 does, in all three modes: unused prefixes named, prefixes an opcode's prefix table takes, `(bad)` operands, a REX before a prefix, `9B` folded into x87 instructions, 66 with REX.W, VEX / EVEX that cannot be one — no difference left on NASM's every form or the opcode-space scan

### Changed
- Repository layout: all assembly under `src/` (`main/`, `core/`, `include/`, `frontend/{lexer,preproc,syntax}`, `semantic/`, `encode/<arch>/`, `object/`, `link/`, `optimize/`, `debug/`, `diag/`, `tools/`, `profile/`, `platform/`, `lib/`, `planned/`); generated tables in `gen/` folders; the suites in `tests/compat/`; build and generator scripts in `scripts/{build,gen,bench}/`; NASM's tables in `third_party/nasm/`; docs in `docs/{user,reference,dev}/`. Every gen1 object is byte-identical to before the move
- The build reads every source under `src/` in one sorted order: the same tree gives the same binary everywhere
- Utkarsha OS (was Tattva OS) in the docs; `-h` names utasm its native assembler
- Project restructured from `src/` flat layout to layered architecture
- Include files renamed from `.s` to `.inc`
- Entry point moved from `src/main.s` to `utasm.s`

---

## [0.1.0] - 2026-04-29

### Added
- **Core Infrastructure**: Lexer, parser, preprocessor, symbol table, arena allocator
- **Multi-Architecture Encoding**: x86-64 (REX/VEX-3/EVEX/AVX-512), AArch64 (NEON/SVE), RISC-V 64 (RV64GC + M/A/F/D/V)
- **ELF64 Linker**: Section layout, symbol table, RELA relocations, string table de-duplication
- **Preprocessor**: `%define`, `%macro`, `%if`, `%rep`, `%rotate`, token pasting, stringification, `%include`
- **O(1) Symbol Table**: FNV-1a hash with quadratic probing
- **DWARF v5**: `.debug_info`, `.debug_abbrev`, `.debug_line` emission
- **io_uring I/O**: Asynchronous file operations
- **Self-Hosting**: Bootstrap pipeline (Gen0 via NASM → Gen1 via itself → parity check)
- **Error Engine**: Structured error codes E1xx–E1xx with line/col reporting
- **ELF Section Groups**: SHT_GROUP + COMDAT support
- **BSS Support**: SHT_NOBITS sections with zero disk footprint
- **Common Symbols**: SHN_COMMON handling
- **Archive Support**: Static `.a` reader and generator
- **Section Flag Validation**: W^X security policy enforcement
- **Struct Support**: STRUC/ENDSTRUC with field alignment
- **100-phase industrial audit**: Phases 1–10 complete (A01–A100)

### Fixed
- Stack alignment in `elf64_emit` and linker_run
- Preprocessor stack frame corruption in `prep_handle_rep`
- `preprocessor_next_token` and `preprocessor_peek_token` register restoration
- `parser_handle_section_directive`: R15 preservation, SECTION_type not set, RAX clobbered before second check
- `elf64_emit`: .data write not guarded by existence check
- `elf64_write_ehdr`: missing `e_ehsize` and `e_shentsize` fields
- `elf64_align_file`: wrong epilogue using elf64_emit's stack cleanup

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
