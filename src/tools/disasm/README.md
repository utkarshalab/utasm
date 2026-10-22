# tools/disasm/ — the x86 disassembler (`--disasm`)

Prints a file's code as x86 instructions, in Intel syntax, **exactly as
`objdump -d -M intel` (binutils 2.47) prints it**: bytes, text, symbol
annotations, branch targets, `# addr <sym>` after `[rip]` operands,
relocations with `-r`. It reads ELF64 and ELF32 files (objects,
executables, shared objects) and raw files (boot sectors, flat binaries),
in 16-, 32- and 64-bit mode.

```sh
utasm --disasm prog.o
utasm --disasm -r prog.o                         # with relocations
utasm --disasm --bits 16 --org 0x7c00 boot.bin   # a raw file
```

## How it works

1. **`disasm.s`** walks the file: every executable section of an ELF
   image (`disasm_sections`, after `inspect_validate`), or the whole of a
   raw file as one section `.data` at `--org` (`disasm_raw`). For each
   section it prints objdump's headers, a label line where a symbol starts
   (objdump's choice when several do: a function, then a global, then a
   name not starting with `.`, then by name), restarts decoding at every
   symbol (as objdump does), and for each instruction prints the address,
   the bytes and the text, the nearest symbol of a branch target
   (`<lab-0x5>`), the target of a `[rip + disp]`, and with `-r` the
   relocations at that instruction (`disasm_relocs`, `R_X86_64_*` /
   `R_386_*`). Without a symbol table the dynamic one is used.
2. **`x86.s`** decodes **one instruction** (`x86_decode(code, available,
   address, fmtbuf)` → its length and branch target):
   - the **wrapper** decodes it once as it is, then again without each
     legacy prefix, with each REX bit cleared, without a bare REX; where
     the text comes out the same, that prefix did nothing and is named as
     objdump names it (`data16`, `addr32`, `rex.WB`, `fs`, `{rex2 0xNN}`).
     It also handles what objdump treats as instructions of their own: a
     REX before another prefix (`data16 rex`), 9B folded into x87 forms;
   - the **decoder** (`dx_decode1`) reads prefixes, REX / REX2, VEX
     (C4 / C5), XOP (8F), EVEX (62), the opcode and ModRM / SIB /
     displacement / immediates; looks the opcode up in the generated
     tables (`gen/x86_tables.inc`: the one-byte map, 0F, 0F 38, 0F 3A,
     SSE prefix columns, groups, VEX / EVEX / XOP forms); and writes the
     operands by **form** (about 120 operand layouts, `FM_*`). In 16- and
     32-bit mode 40-4F are `inc` / `dec`, C4 / C5 / 62 are VEX / EVEX only
     before a mod-11 ModRM, addressing is 16-bit where it should be;
   - what the CPU would refuse is shown as objdump shows it: `(bad)` for
     an undefined opcode (taking the bytes up to it), an operand an
     encoding cannot have (`call (bad)`, `psrlw (bad),0x71`), prefixes an
     opcode's prefix table takes (`66 0f ae 20` is `(bad)`), `/(bad)` marks
     on gathers, `(bad) {k2}` for an EVEX outside 64-bit mode.
3. **`x86/apx.inc`** decodes APX's EVEX map 4 —
   new-destination forms, `{nf}`, `{zu}`, `{evex}`, `ccmp` / `ctest`
   with `{dfv=...}`, `cfcmov`, `push2` / `pop2` — and the map-7 MSR forms.

## The generated tables (`gen/x86_tables.inc`)

**Do not edit.** `scripts/gen/gen_x86_tables.py` writes them from its
opcode map — the same map `scripts/gen/gen_x86_enc.py` builds the
encoder's forms from, so the assembler and the disassembler read every
encoding the same way. Entries only the disassembler needs (what objdump
reads but no assembler writes) are marked `DIS_ONLY` there, so they make
no encoder forms.

```sh
python3 scripts/gen/gen_x86_tables.py           # regenerate
python3 scripts/gen/gen_x86_tables.py --check   # fail if out of date
```

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `disasm.s` | 954 | the file walk: sections, symbols, labels, annotations, relocations, raw files (`disasm_sections`, `disasm_raw`, `disasm_org`, `disasm_relocs`) |
| `x86.s` | 339 | the decoder's constants (`FM_*`, `FL_*`) and its state (`dx_*`); the rest of it in the `x86/` parts, %included in this order: |
| `x86/wrapper.inc` | 627 | x86_decode: the decoder's entry, trials and variants, string helpers |
| `x86/decode.inc` | 1,592 | dx_decode1: one instruction - prefixes, opcode maps |
| `x86/read.inc` | 729 | reading bytes and ModRM; printing registers, memory, immediates, branches |
| `x86/x87.inc` | 286 | x87 instructions, fwait |
| `x86/evex.inc` | 1,091 | shapes, VSIB, EVEX operands, mask registers |
| `x86/operands.inc` | 1,884 | dx_operands: the operand forms |
| `x86/sse.inc` | 967 | SSE / vector operands, memory sizes |
| `x86/tables.inc` | 398 | register names and the decoder's strings |
| `x86/apx.inc` | 1,216 | APX's EVEX map 4 and map 7 (%included by x86/tables.inc) |
| `gen/x86_tables.inc` | 18,140 | GENERATED: the opcode tables (%included by x86/tables.inc) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `disasm_sections`, `disasm_raw` | tools/inspect/inspector.s — `--disasm` and `--inspect-only disasm` both go through `inspect_file`, which validates the file and calls these |
| `disasm_org`, `disasm_relocs` | main/cli.s (`--org`, `-r`) |
| `x86_decode`, `x86_mode`, `x86_rip_target`, `x86_hex0x` | disasm.s |

## Depends on

tools/inspect (validation, ELF32 widening), tools/symdump (columns,
names), lib/ (FmtBuf, strings).

## Status

Complete for x86, measured against objdump 2.47:

- every form of NASM's instruction tables, in 64-, 32- and 16-bit mode
  (100%: bytes, text, annotations);
- the whole opcode space — every prefix × map × opcode × 33 ModRM bytes,
  133,320 cases a mode — with **no difference** in any mode;
- utasm's own objects, with their relocations.

Not done: the names GNU's dynamic linking adds (`@@GLIBC_2.2.5`,
`<puts@plt>`), and AArch64 / RISC-V decoding (deferred with their
encoders).

## Tests

`tests/compat/run_all.py`: the *disassembler* suite (NASM's every form in
three modes, a 16-bit and a 32-bit corpus, an ELF32 object, the gen1
objects; needs objdump 2.47 on PATH). `tests/compat/disasm_scan.py`: the
opcode space (minutes a mode; not in run_all).
