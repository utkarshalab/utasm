# tools/inspect/ — the ELF inspector (`--inspect`)

A built-in, readelf-style view of an ELF file, so utasm can check its own
output without external tools:

```sh
utasm --inspect prog.o                                  # everything but disassembly
utasm --inspect --inspect-only header,sections,symbols prog.o
```

Parts: `header`, `sections`, `segments`, `symbols`, `relocs`, `all`
(every part but `disasm`), `disasm` (the disassembler).

## How it works

1. **Validate once** (`inspect_validate`): the ELF header, the section and
   program header tables, and every section's file range must lie inside
   the buffer. After that the printers only bounds-check indices (symbol
   numbers, `sh_link`, string offsets). A malformed file is
   `EXIT_INVALID_FORMAT` — never an out-of-bounds read.
2. **ELF32** (`elf32.s`): an i386 file is first **widened** into an ELF64
   image in memory — a 64-byte header, the program and section headers in
   their 64-bit layouts, symbols 16 → 24 bytes, relocations REL 8 → 16 and
   RELA 12 → 24 (the symbol index moved into the 64-bit `r_info`), with a
   note (`ins_elf32`) that the original was ELF32 so `R_386_*` names are
   printed. Every printer then reads one layout; `--disasm` uses the same
   path.
3. **Print** each part asked for, one line at a time, to a **sink**
   callback (`inspect_sink_fd` writes to stdout; a test can capture it).
   The first non-zero sink result stops the output and is the return
   value. Symbols and relocations are printed by tools/symdump, which
   shares this file's context and `ins_*` helpers.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `inspector.s` | 896 | `inspect_file` (the CLI entry), `inspect_run` (in memory), `inspect_validate`, the header / section / segment printers, the `ins_*` helpers |
| `elf32.s` | 349 | `elf32_widen`: an ELF32 file as an ELF64 image |

## Entry points

| Symbol | Used by |
| --- | --- |
| `inspect_file` | main/utasm.s (`--inspect` and `--disasm`) |
| `ins_shdr`, `ins_put_secname`, `ins_flush_line` | tools/symdump, tools/disasm |

`inspect_run`, `inspect_validate` and `inspect_sink_fd` are global for
tests and future callers; inspector.s is their only user today.

## Depends on

tools/symdump (symbols, relocations, columns), tools/disasm (the
`disasm` part), platform/ (reading the file), lib/ (FmtBuf).

## Status

Complete for ELF64 and ELF32 little-endian files. Not read: other
formats (COFF objects, UBF images). With signed UBF (planned), checking
an image's signatures belongs here.

## Tests

Used by the *ubf images*, *elf probes* and *disassembler* suites in
`tests/compat/run_all.py`; malformed files in *robustness*.
