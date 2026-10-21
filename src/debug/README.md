# debug/ — what debuggers and unwinders read

The sections that let gdb step through assembly source and let debuggers,
profilers and backtraces unwind through it: **DWARF** for `-g`
(`dwarf.s`), **GNU's line table** from `.file` / `.loc` (`line.s`, what
GCC's `-g` output gives), and **call-frame information** from `.cfi_*`
(`cfi.s`). All three are built **once the code is laid out**
(`link/linker.s`), so they describe the code after jump shortening — each
keeps its records' positions in step while code moves.

## `-g`: DWARF for assembly source (`dwarf.s`)

| Section | What is in it |
| --- | --- |
| `.debug_line` | the line table (DWARF 3): for every line that made code, its address, file and line — a macro's or `%rep` body's code at its body line, an included file's in that file, as NASM maps them |
| `.debug_info` | one compile unit: the source's name, the producer, `DW_LANG_Mips_Assembler`, the line table's offset, the first code section's range; a `DW_TAG_subprogram` per function the source types (`global f:function`), as GNU as writes them — gdb's function names and ranges |
| `.debug_abbrev` | the two abbreviations those use |
| `.debug_aranges` | the address ranges of every code section |

The rows come from the per-line entries the listing is made from
(`include/listing.inc`, object/listing), which already follow moved code.
Addresses are relocations against the sections' own symbols, so the
linker places them.

## GNU's `.file` / `.loc` (`line.s`)

For assembly GCC emits with `-g`: `.file N "name"` (DWARF 5's `.file 0`,
md5), `.loc N line [column] [prologue_end] [is_stmt] [discriminator]
[view ...]`. Each `.loc` becomes a row at the next instruction; views
(`.LVUn`, for GCC's location lists) are numbered as GNU as numbers them
and checked again after shortening (a change is an error). `line_build`
writes the header, the directory and file tables (DWARF 5:
`.debug_line_str`), and a sequence per code section, encoded as GNU as
2.43 does. Version 3 by default, 5 with `.file 0` / `.loc 0`, or
`--gdwarf-N`.

## `.cfi_*` → `.eh_frame` (`cfi.s`)

NASM has no CFI; utasm takes GAS's directives (`.cfi_startproc`,
`.cfi_def_cfa`, `.cfi_offset`, `.cfi_adjust_cfa_offset`,
`.cfi_rel_offset`, `.cfi_remember_state` / `.cfi_restore_state`,
`.cfi_endproc`, `simple`, `signal_frame` ...). Each is recorded with its
section and offset (`cfi_directive`, moved with the code: `cfi_remap`) and
the CFA offset is followed as the source goes. `cfi_build` writes
`.eh_frame` as GAS does: a CIE (version 1, augmentation `zR` / `zRS`, data
alignment -8 or -4 in elf32, return address column 16 or 8, PC-relative
FDE pointers, the state at a call), then an FDE per `startproc` ...
`endproc` with its rules at the addresses the code reaches them, padded
with `DW_CFA_nop`.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `dwarf.s` | 876 | `dwarf_generate` and the `dw_*` writers (LEB128, sized values, relocated addresses) |
| `line.s` | 2,293 | `.file`, `.loc` (`line_file`, `line_loc`), the row and view bookkeeping (`line_insn`, `line_remap`), `line_build` |
| `cfi.s` | 1,159 | `cfi_directive`, `cfi_register`, `cfi_remap`, `cfi_build` |

## Entry points

| Symbol | Used by |
| --- | --- |
| `dwarf_generate`, `cfi_build`, `line_build` | link/linker.s |
| `dbg_enabled` | main/ (`-g`, `-F dwarf`) |
| `cfi_directive` | frontend/syntax (`parser_cfi`) |
| `line_file`, `line_loc` | frontend/syntax/gas (`.file`, `.loc`) |
| `line_insn`, `line_insn_done` | main/utasm.s (around each instruction) |
| `cfi_remap`, `line_remap` | optimize/jump.s |

## Depends on

core/ (sections, emitting), object/ (the listing's line entries, ELF32
flags), optimize/ (positions after shortening), link/reloc (address
relocations), lib/.

## What is left

DWARF **types and variables** — structs, procs and namespaces as
`DW_TAG_structure_type`, `DW_TAG_subprogram` with frames,
`DW_TAG_namespace` — so a debugger shows Utkarsha OS's kernel structures,
not just addresses and lines.

## Tests

`tests/compat/run_all.py`: *dwarf line tables* (the decoded rows against
NASM's), *cfi frames* (`.eh_frame` against GNU as's), *gas* (`.file` /
`.loc` line tables against GNU as).
