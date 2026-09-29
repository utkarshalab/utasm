## Command-line interface

```
utasm [options] <source.s>
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
