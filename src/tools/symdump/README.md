# tools/symdump/ — symbols, relocations, and the dump columns

Two pieces the inspector and the disassembler share.

## Symbols and relocations (`symdump.s`)

Prints every symbol table (`SHT_SYMTAB`, `SHT_DYNSYM`) and every
relocation section (`SHT_RELA`, `SHT_REL`) of an image `inspect_validate`
already checked — so every section's bytes are inside the buffer. What it
still checks is every **index**: entry sizes, `sh_link`, `sh_info`, symbol
numbers, string offsets; a bad one is an error, not a wild read.
Relocation types are named (`R_X86_64_*`, and `R_386_*` for a widened
ELF32 file).

## The column helpers (`fmt.s`)

Everything writes into a `FmtBuf` (lib/fmt.s), so a line can never
overflow the caller's buffer:

| Function | What it writes |
| --- | --- |
| `dump_pad_to` | spaces up to a column (at least one) |
| `dump_udec_right` | an unsigned decimal, right-aligned |
| `dump_put_hex0x` | `0x...` |
| `dump_put_name`, `dump_name` | a symbolic name from a table (section types, symbol bindings, relocation types ...) |
| `dump_put_strtab` | a string from a string table, bounds-checked |

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `symdump.s` | 577 | `symdump_symbols`, `symdump_relocs` |
| `fmt.s` | 493 | the column helpers and the name tables |

## Entry points

| Symbol | Used by |
| --- | --- |
| `symdump_symbols`, `symdump_relocs` | tools/inspect |
| `dump_*` | tools/inspect, tools/disasm |

## Depends on

tools/inspect (`ins_*` helpers, the validated image), lib/ (FmtBuf,
strings).

## Status and tests

Complete. Covered through `--inspect` and `--disasm` (see those READMEs).
