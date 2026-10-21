# link/ — the end of assembly, and relocations

`linker_run` is what happens after the last statement: it turns the
sections the encoders filled into a finished output file. `reloc/reloc.s`
is the relocation engine: every reference that was not known when its
instruction was encoded.

utasm does **not link several objects yet** — `ld` does that. "Linker"
here means: lay out this one assembly's sections, resolve what can be
resolved inside it, and write the object (or, for `--standalone` and flat
binaries, the finished image). Multi-object linking is the next phase;
its placeholders are listed below.

## What `linker_run` does, in order

1. **Shorten jumps** (`relax_run`, optimize/jump.s) now that every label
   is known; the late aliases first (`parser_late_aliases`), then
   `relax_padto_check`, then GNU's `.size` values (`parser_sizes`).
2. **Debug tables from the final code**: `.eh_frame` (`cfi_build`),
   `-g`'s DWARF (`dwarf_generate`), GNU's `.file` / `.loc` line table
   (`line_build`) — debug/.
3. **Layout**: a standalone executable (`elf64_standalone_layout`) or a
   flat binary (`binary_layout`) gets its section addresses.
4. **Late `equ`s** — values that depended on positions
   (`parser_late_equs`).
5. **Resolve relocations** (`reloc_resolve_all`): each one whose symbol
   is known in this assembly is patched into its section; the rest stay
   for the object file.
6. **Overlaps** (flat binaries: sections placed on top of each other are
   an error), and the **second pass's check** (`known_verify`, core/).
7. **Write**: by `ASMCTX_fmt` — `binary_emit` (`-f bin`), `ubf_emit`
   (`-f ubf`), `elf64_emit` (`-f elf64`, and as the first step of
   `-f elf32` / `-f win64`, which `elf32_convert` / `coff_convert` then
   rewrite) — object/.

## Relocations (`reloc/reloc.s`)

The encoders and data directives call `reloc_record` whenever they write a
reference whose value is not known yet (a forward label, an extern, an
address in a relocatable object). A `RELOC` (struc in `include/type.inc`)
holds the section and offset of the field, the symbol, the type, the
addend and the source line (so a relocation error points at its
statement).

`reloc_resolve_all` walks them once the layout is final:

- the symbol is defined in the same assembly and the field can be filled
  (a PC-relative reference within a section, any reference in a flat
  binary or standalone executable): patched in, the record dropped;
- otherwise the record goes to the object as `R_X86_64_*` (or `R_386_*`
  / COFF's after conversion): `PC32`, `PLT32`, `64`, `32`, `32S`, `16`,
  `8`, GOT / TLS types for `wrt ..got` & co.;
- an expression NASM's object formats cannot express is an error at its
  line, as NASM's.

Also here: `reloc_warn_pie` (`-w+pie`: an absolute 32-bit address in
64-bit code, which `ld -pie` would refuse), `reloc_wrt` (`wrt ..plt`,
`..got`, `..gotpcrel`, `..tlsie` ...), and the RISC-V branch / call
relocations.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `linker.s` | 319 | `linker_run` (the steps above), the overlap check |
| `reloc/reloc.s` | 1,333 | `reloc_record`, `reloc_resolve_all`, `reloc_apply_one`, `reloc_wrt`, `reloc_warn_pie`, expression and offset fields |
| `dead.s` | 4 | placeholder: removing unused sections (`--gc-sections`) |
| `layout.s` | 4 | placeholder: section layout / addresses across objects |
| `merge.s` | 4 | placeholder: section merging (COMDAT) |
| `section.s` | 4 | placeholder: the output section table across objects |
| `symbol.s` | 4 | placeholder: symbol resolution across objects |
| `map.s` | 4 | placeholder: a linker map (the assembler's map files are object/map.s) |
| `reloc/abs.s`, `reloc/rel.s`, `reloc/got.s`, `reloc/plt.s`, `reloc/tls.s` | 4 each | placeholders: the relocation kinds a multi-object linker applies (today all of them are in reloc.s) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `linker_run` | main/utasm.s |
| `reloc_init` | main/utasm.s |
| `reloc_record`, `reloc_wrt` | encode/x86, encode/riscv64, frontend/syntax (data), debug/ |
| `reloc_quiet` | encode/x86 (trial encodings) |
| `reloc_resolve_all` | `linker_run` |
| `reloc_apply_one` | object/flat/flat.s (relocations inside a flat image) |
| `reloc_warn_pie` | encode/x86 |

## Depends on

object/ (layout and writers), optimize/ (shortening), debug/ (the tables),
frontend/syntax (late values), core/ (the second pass), diag/, profile/
(phase timing), lib/.

## What is left: multi-object linking (Phase B)

What Utkarsha OS's build needs from utasm alone:

1. several inputs in one run (or `utasm link a.o b.o -o image`), with
   symbol resolution across them (`symbol.s`), section merging and
   layout (`merge.s`, `layout.s`, `section.s`), a layout description
   (a linker script or a declarative form), `--gc-sections` (`dead.s`);
2. archives (`.a` files; an early unused reader was removed — git history
   has it, commits A59-A62 of 2026-04-29);
3. the relocations of a full linker (`reloc/*.s`);
4. a link map (`map.s`).

## Tests

`tests/compat/run_all.py`: *elf probes* (relocation types, symbols,
addends against NASM), *sections/link* (programs linked with `ld`, or
`--standalone`, and run), *label operands*, *tls relocations*, *objdump
readback*, *bin probes* (flat-binary layouts).
