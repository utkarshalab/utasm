# include/ — what every file shares

Headers only: constants, structure layouts and macros, no code. A source
file takes what it needs with
`%include "src/include/<name>.inc"`; each header guards itself against
being included twice.

## The three every file includes

### `constant.inc` (1,880 lines)

Every number utasm's modules agree on, in labelled sections:

- **exit codes** (`EXIT_OK` = 0, `EXIT_USAGE`, `EXIT_OOM`, ...,
  `EXIT_MASK_REFUSED` = 181): what a function returns in `rax` on failure;
  `diag/codes.s` turns each into its message;
- **token kinds** (`TOK_*`), **symbol kinds and visibility** (`SYM_*`,
  `VIS_*`), **section types** (`SEC_*`), **operand kinds and flags**
  (`OP_*`, `OP_FLAG_*`), **context flags** (`CTX_FLAG_*`), **instruction
  flags**, **operand sizes**;
- **targets** (`TARGET_*`), **output formats** (`FMT_ELF64`, `FMT_BIN`,
  ...), **optimization levels** (`OPT_*`);
- **CPU feature bits** for amd64, aarch64, riscv;
- **the host**: system call numbers, `open` / `mmap` flags, errno values;
- **ELF**: magic, types, machines, section and program header types and
  flags, symbol bindings and types, special section indices; AArch64 and
  RISC-V relocation types;
- **register identifiers**, lexer character properties, arena, error
  system, hash table and macro engine constants, DWARF 5 constants, the UBF
  boot format (see `docs/user/ubf.md`), UPK (planned), poison values, the
  profiler's.

### `type.inc` (592 lines)

The structures modules pass to each other (NASM `struc`s; under NASM the
`field` macro from macro.inc lays them out, `-d__NASM__=1`):

| Struc | What it is | Made by |
| --- | --- | --- |
| `TOKEN` | one token: kind, flags, text / value, file, line, column | frontend/lexer |
| `SYMBOL` | a label, constant or extern: name, value, section, size, visibility, ELF type | semantic/symtable.s |
| `SECTION` | a section's bytes, name, ELF type / flags, alignment, flat-binary placement | core/asmctx.s |
| `RELOC` | one relocation: section, offset, symbol, type, addend, source line | link/reloc/reloc.s |
| `ASMCTX` | the assembler context: target, format, options, sections, symbols, relocations | main/utasm.s |
| `LEXER`, `PREP`, `INCLUDECTX`, `MACRO`, `MACROEXP` | the lexer, the preprocessor, an include, a macro and one expansion of it | frontend/ |
| `OPERAND`, `INST` | a parsed instruction: up to four operands (register, memory: base / index / scale / displacement, immediate, masks, decorators) | frontend/syntax |
| `ARENA`, `VEC`, `FMTBUF` | the library's arena, growable array and string builder | lib/ |
| `PHDR` | an ELF program header (standalone executables) | object/elf |
| profiler's `PROFSTATE` / `PROFENTRY` | the per-phase measurements | profile/ |

Unused today (defined, referred to nowhere): `ERRORREC`, `ISAENTRY`,
`FILEREG`, `ELFDYN`, `HASHBUCKET`, and `UPKHEADER` / `UPKSECTION` (for the
planned UPK output).

### `macro.inc` (1,513 lines)

The macros utasm's own code is written with, about 120 of them:

- **functions**: `prologue` / `epilogue`, `push_volatile` / `pop_volatile`,
  `save_context` / `restore_context`, local variables (`locals_start`,
  `local_var`, `locals_end`), stack checks;
- **structures**: `struc` / `field` / `endstruc` — under NASM
  (`-d__NASM__=1`) these emulate the `struc` utasm understands natively, so
  NASM can build the first generation;
- **control flow and errors**: `IF` / `ELSE` / `ENDIF`, `WHILE`,
  `try` / `catch`, `check_err`, the `assert_*` checks, `j_likely`;
- **memory and data**: `alloc_on_arena`, `zero_mem`, `memcpy`, `memset`,
  `strlen`, `encode_leb128`, circular buffers, bloom filters, jump tables;
- **bits and arithmetic**: byte swaps, bit fields, `popcnt_64`, `min_64`,
  `mul_128`, `hash_fnv1a_64`;
- **system level**: `syscall_0` .. `syscall_6`, `mmap_anon`, atomics and
  spin locks, port I/O, MSRs, fences, `rdrand_64` — many are there for OS
  code written with this header, not used by utasm itself;
- **the mnemonic tables**: `mnc_ent` (encode/x86/isa.s) and `copy_token`.

## The others

| File | Lines | What is in it | Included by |
| --- | --- | --- | --- |
| `arch/amd64.inc` | 106 | AMD64 register IDs and encoding constants | constant.inc, encode/x86, frontend/syntax (parser), diag/source.s |
| `arch/aarch64.inc` | 138 | AArch64 register IDs (must match `encode/aarch64/isa.s`) | encode/aarch64, frontend/syntax (parser) |
| `arch/riscv64.inc` | 159 | RISC-V register IDs (must match `encode/riscv64/isa.s`) | encode/riscv64 |
| `elf.inc` | 424 | ELF64 header and section / segment offsets and types | object/elf, link/reloc, encode/x86, frontend/syntax (parser), tools/ |
| `inspect.inc` | 163 | shared definitions of the inspector and the symbol dumper | tools/inspect, tools/symdump, tools/disasm, main/cli.s |
| `listing.inc` | 42 | the per-line entries the listing (`-l`) and the DWARF line table share | object/listing, debug/dwarf |
| `register.inc` | 255 | AMD64 register aliases: ABI roles, control / debug registers, MSR numbers | platform/mem.s |
| `syscall.inc` | 437 | the Linux x86-64 system call numbers (`SYS_*`) | platform/mem.s (the rest use `constant.inc`'s) |

## Files

| File | Lines |
| --- | --- |
| `constant.inc` | 1,888 |
| `type.inc` | 558 |
| `macro.inc` | 1,513 |
| `elf.inc` | 424 |
| `syscall.inc` | 437 |
| `register.inc` | 255 |
| `inspect.inc` | 163 |
| `listing.inc` | 42 |
| `arch/amd64.inc` | 106 |
| `arch/aarch64.inc` | 138 |
| `arch/riscv64.inc` | 159 |

## Rules

- A constant or structure two modules share belongs here; one only one
  file uses stays in that file.
- Register IDs in `arch/*.inc` must match the encoders' tables exactly.
- Adding to a struc changes the offsets of everything after it: every
  file using it is reassembled by `make` (the build has no header
  dependencies — `make clean` if in doubt).

## Tests

Indirect: every suite. A wrong constant shows up as wrong bytes or a wrong
message in `tests/compat/run_all.py`.
