# object/ — the output files

Everything utasm writes besides diagnostics: the **object or image**
(`-f elf64 | elf32 | win64 | bin | ubf`), the **listing** (`-l`) and the
**map file** (`--map`, `[map ...]`). `link/linker.s` calls the right
writer once the sections are final and the relocations resolved.

## Formats

| `-f` | Writer | What it produces |
| --- | --- | --- |
| `elf64` (default) | `elf/elf64.s` | an x86-64 ELF relocatable object for `ld` / `lld`; with `--standalone`, a static executable |
| `elf32` (`elf`) | `elf/elf32.s` | an i386 ELF object (`bits 32` by default) — written as ELF64 first, then rewritten |
| `win64` | `coff/coff.s` | an x86-64 COFF object, laid out as NASM's win64 output — written as ELF64 first, then rewritten |
| `bin` | `flat/flat.s` | a flat binary: raw bytes, `org` and NASM's section placement |
| `ubf` | `ubf/ubf.s` | a UBF boot image for Utkarsha OS: the flat binary as the kernel component, plus `--ubf-add` components |

**One writer, three object formats.** ELF64 is the real writer;
`elf32_convert` and `coff_convert` rewrite its output in memory (headers
and symbols to their layouts, `.rela` to `.rel` with in-place addends, or
COFF's relocations and symbol table). So sections, symbols, groups and
custom sections behave the same in all three.

### ELF64 (`elf/elf64.s`)

`elf64_emit` writes: the ELF header; each section's bytes (code, data,
`.rodata`, custom sections with their flags and entry sizes, `.bss` taking
no file space); the debug sections (from debug/); `.symtab` and `.strtab`
(locals first, then globals; section symbols; the FILE symbol; only the
externs actually used, as NASM); `.shstrtab`; a `.rela.X` for each section
with relocations; section groups (COMDAT); the section header table.

`--standalone` (`elf64_standalone_layout`): sections placed at addresses,
program headers (`PT_LOAD` per class of permissions), the entry point
(`_start`, or 0) — a static executable that runs without `ld`.

`elf/notes.s` adds the notes NASM never writes: `--noexecstack` /
`--execstack` (`.note.GNU-stack`) and `--cet` (`.note.gnu.property` with
IBT and SHSTK).

### Flat binaries (`flat/flat.s`)

NASM's `bin`: the first section starts at `org` (0 by default), every
other section follows in declaration order, aligned (at least 4), NOBITS
last with no file space; `start=`, `vstart=`, `follows=` place sections
explicitly. `binary_layout` runs before relocations are resolved, so
references between sections get real addresses; `binary_emit` writes the
bytes.

### UBF boot images (`ubf/ubf.s`)

The format Utkarsha OS's stage-2 loader reads (`docs/user/ubf.md`): a
1024-byte header (magic `UBFORMAT`, version, size, component count,
CRC-32, flags), then up to 8 components on 512-byte sector boundaries
(kernel, initrd, dtb, config, module, firmware), each with its load
address, entry offset and SHA-256 (lib/sha256.s). The kernel is
byte-identical to the `-f bin` output of the same source.

### COFF (`coff/coff.s`)

`-f win64`: the file header (`IMAGE_FILE_MACHINE_AMD64`, the time stamp —
0 under `--reproducible`), section headers, each section's bytes and
relocations, the symbol table with auxiliary records and the string table,
in NASM's order.

## Listings and map files

- **Listing** (`listing/listing.s`, `-l file`): every source line with its
  offset and bytes, in NASM's layout — macro expansions marked `<1>` `<2>`,
  long data wrapped over lines, warnings after their line, `%rep` bodies,
  uninitialised data as `??`. It follows code the jump shortener moved
  (`lst_remap`). Its per-line entries also feed the DWARF line table
  (`include/listing.inc`).
- **Map file** (`map.s`, `--map file` or `[map all file.map]`): NASM's bin
  map — the origin, the sections (summary and detail), the symbols by
  section and address.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `elf/elf64.s` | 3,308 | `elf64_emit` (the object), `elf64_standalone_layout` (executables), symbols, relocations, groups, section headers |
| `elf/elf32.s` | 589 | `elf32_convert`: the ELF64 object rewritten as ELF32 / i386 |
| `elf/notes.s` | 153 | `elf_add_notes`: `.note.GNU-stack`, `.note.gnu.property` |
| `coff/coff.s` | 1,021 | `coff_convert`: the ELF64 object rewritten as an x86-64 COFF one |
| `flat/flat.s` | 318 | `binary_layout`, `binary_emit`, `bin_origin` |
| `ubf/ubf.s` | 489 | `ubf_emit`, `ubf_add_component` (`--ubf-add`) |
| `listing/listing.s` | 1,942 | the `-l` listing |
| `map.s` | 752 | map files |
| `pe/out.s`, `pe/header.s`, `pe/dos.s`, `pe/optional.s`, `pe/section.s`, `pe/import.s`, `pe/export.s`, `pe/reloc.s`, `pe/cert.s` | 4-7 each | placeholders: PE32+ output (UEFI images) |
| `upk/out.s`, `upk/header.s`, `upk/meta.s`, `upk/deps.s`, `upk/compress.s`, `upk/sign.s` | 4-7 each | placeholders: `.upk` packages |

## Entry points

| Symbol | Used by |
| --- | --- |
| `elf64_emit`, `elf64_standalone_layout`, `binary_layout`, `binary_emit`, `ubf_emit` | link/linker.s |
| `elf32_convert`, `coff_convert`, `elf32_enabled`, `coff_enabled` | link/linker.s; the flags read by frontend, encode/x86, debug/ |
| `elf_add_notes`, `ubf_add_component`, `map_cli` | main/ |
| `lst_*` | frontend/ (each line and expansion), diag/ (warnings in the listing), optimize/ (remap), debug/dwarf.s |
| `map_option`, `map_write` | frontend/syntax (`[map]`), main/ |
| `bin_origin` | object/map.s, object/ubf/ubf.s (the image's origin) |

`binary_emit_bootloader` (flat.s) is defined but unused.

## Depends on

platform/ (writing files), lib/ (strings, hashes, SHA-256), core/
(sections), semantic/ (symbols), link/reloc (relocations in flat images),
frontend/syntax (section attributes), optimize/ (moved code).

## What is left

PE32+ output for UEFI (`pe/`), `.upk` packages (`upk/`). For Utkarsha OS
specifically: UBF modules that are relocatable and signed (the header has
a "signed" flag that is never set yet) — with multi-object linking, the
next phase (see link/README.md).

## Tests

`tests/compat/run_all.py`: *elf probes* (contents, relocations, symbols
against NASM), *bin probes*, *sections/link* (linked and run), *ubf
images* (every header field, CRC, SHA-256), *elf32 objects* (against
NASM's i386 output, linked with `ld -m elf_i386`), *coff objects* (field
by field against NASM's win64), *listings* (line for line against NASM),
*map files*, *objdump readback*.
