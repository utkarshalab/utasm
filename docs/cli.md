## Command-line interface

```
utasm [options] <source.s>
utasm --inspect [--inspect-only <parts>] <file>
```

UTASM assembles one source file per invocation. With no output options,
`utasm source.s` targets AMD64 and writes an ELF64 relocatable object named
after the source file (for example, `source.s` becomes `source.o`).

| Option | Meaning |
| --- | --- |
| `-f`, `--format <format>` | Output format: `elf64` (default) or `bin`. Non-standalone ELF output is a relocatable object. |
| `-o <file>` | Output path; defaults to a source-derived `.o` or `.bin` filename. |
| `-a`, `-arch`, `--arch <arch>` | Target architecture: `amd64` (default), `aarch64`, or `riscv64`. |
| `--standalone` | Produce a standalone executable and require `_start`. |
| `--profile`, `-P` | Print the assembler's internal performance profile. |
| `--verbose` | Enable verbose diagnostics. |
| `--color`, `--no-color` | Explicitly enable or disable ANSI diagnostic color. |
| `-Werror` | Treat warnings as errors. |
| `--inspect` | Print an existing ELF file instead of assembling (see below). |
| `--inspect-only <parts>` | Inspect only the listed parts; implies `--inspect`. |
| `-h`, `--help` | Print help and exit successfully. |
| `-v`, `--version` | Print the UTASM version and exit successfully. |

The CLI rejects unknown options, missing option values, unknown formats or
architectures, and more than one input file. Formats without an implemented
emitter (for example PE32+ and UPK) are deliberately not accepted.

Examples:

```sh
# Default AMD64 ELF output
utasm hello.s -o hello.o

# Explicit relocatable object
utasm --arch amd64 --format elf64 source.s -o source.o

# Flat binary
utasm -f bin boot.s -o boot.bin

# A self-contained executable, with profiling
utasm --standalone --profile main.s -o main
```

## Inspecting ELF files

`--inspect` turns utasm into a built-in, readelf-style viewer, so its own
output can be checked without external tools:

```sh
utasm hello.s                   # writes hello.o
utasm --inspect hello.o         # header, sections, segments, symbols, relocations
utasm --inspect-only symbols,relocs hello.o
```

`<parts>` is a comma-separated list of `header`, `sections`, `segments`,
`symbols`, `relocs` and `all`. Unknown or empty names are rejected.

Any ELF64 little-endian file can be inspected: objects, executables and
shared libraries, from utasm or any other toolchain. The whole file is
validated before anything is printed, so a truncated or corrupt file is
reported instead of crashing the viewer. Unnamed section symbols are shown
with their section's name, and relocation targets read as `symbol + addend`:

```
Relocation section '.rela.data' at offset 0x460 contains 2 entries (applies to '.data'):
  Offset            Info              Type                     Sym. Name + Addend
  0000000000000006  0000000300000001  R_X86_64_64              .data + 0x0
```

On failure utasm prints `utasm: cannot inspect '<file>': <reason>` and exits
with a specific code:

| Exit code | Reason |
| --- | --- |
| 10 | no such file |
| 11 | permission denied |
| 14 | not a valid ELF64 little-endian file (including empty files) |
| 13 | error writing output |
