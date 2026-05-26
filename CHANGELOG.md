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

### Changed
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
