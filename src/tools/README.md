# tools/ — the built-in tools

utasm checks and explains its own output without external tools. These
run instead of assembling, chosen on the command line (main/utasm.s):

| Tool | Option | What it does |
| --- | --- | --- |
| [disasm/](disasm/README.md) | `--disasm` | an ELF64 / ELF32 file's code, or a raw file, as x86 instructions — objdump 2.47's output |
| [inspect/](inspect/README.md) | `--inspect`, `--inspect-only parts` | a readelf-style view of an ELF file: header, sections, segments, symbols, relocations |
| [symdump/](symdump/README.md) | (inside `--inspect`) | the symbol and relocation tables, and the column helpers both tools share |
| [lsp/](lsp/README.md) | `--lsp` | a language server: an editor's diagnostics as one types |

`--inspect` and `--disasm` share one validated view of the file
(`inspect_validate`): a malformed file is an error, never an out-of-bounds
read. ELF32 files are widened to ELF64 in memory first (`inspect/elf32.s`),
so every printer reads one layout.

```
   main/utasm.s  (--inspect, --inspect-only, --disasm)
        │
        ▼
   inspect/inspector.s: inspect_file — read, validate, widen ELF32
        │                 │
        │ header,         │ disasm part
        │ sections,       ▼
        │ segments    disasm/disasm.s ──▶ disasm/x86.s (one instruction)
        ▼                 │
   symdump/ (symbols, relocations; the column helpers both use)
```
