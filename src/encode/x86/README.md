# encode/x86/ — the x86-64 encoder

Turns an `INST` into x86 machine code: legacy prefixes, REX / REX2, VEX,
EVEX (AVX-512, AVX10.2), APX, x87 — in 16-, 32- and 64-bit code, giving
NASM's bytes for NASM's input and refusing what the CPU would refuse
(#UD encodings NASM accepts).

## How an instruction is encoded

`amd64_encode_tracked` (called by main/utasm.s for each instruction)
records what the shortener and the line table need and calls
`amd64_encode_instruction` (encoder.s), which goes through these steps:

1. **Operand rules no form expresses** — each refuses an instruction the
   CPU would fault on, with its own message:
   - `amd64_takes_none` (noops.s): `cpuid eax`, `hlt 5` — instructions
     that take no operands;
   - `amd64_msr_claim` / `amd64_encode_msr` (msr.s): `rdmsr r64, imm32`,
     `urdmsr`, `uwrmsr` — the MSR forms with operands;
   - `amd64_amx_check` (amx.s): the three tile registers of a tile dot
     product must differ;
   - `amd64_gather_check` (gather.s): a gather's destination, index and
     mask must differ.
2. **APX** (apx.s): `amd64_apx_claim` decides whether the instruction is
   one of APX's EVEX-encoded integer forms (a new data destination
   `add rax, rbx, rcx`, `{nf}`, `{evex}`, `ccmp`, `ctest`, `cfcmov`,
   `push2` / `pop2`); if so `amd64_apx_encode` writes it after the legacy
   prefixes.
3. **Shapes and mode** (shape.s, mode.s): operand combinations no form
   takes (`mov bl, r9w`: NASM's "invalid combination of opcode and
   operands"), operands that do not exist outside 64-bit mode (`rax`,
   `r8`, `sil`), 16-bit addressing inside it, sized immediates no form
   takes, immediates canonicalised to the operation's width
   (`amd64_imm_canon`: 0xFFFF in a 16-bit operation is -1, so the imm8
   forms apply).
4. **Legacy prefixes**: segment, lock / rep, 66 / 67 as the mode needs.
5. **The table encoder** (dispatch.s, `amd64_table_encode`): the forms in
   `gen/opcode.s`, generated from the same opcode map the disassembler
   decodes with. The first form whose operand types all match wins; it
   gives the prefix, map, opcode, ModRM layout, which operand goes where
   (ModRM.reg, ModRM.rm, opcode low bits, vvvv, an immediate), VEX / EVEX
   length and disp8*N. This handles nearly every instruction.
6. **The hand-written encoders** (`encoder/*.inc`, %included by encoder.s), for what the table does not
   cover: `mov` in all its forms, branches (`jmp`, `jcc`, `call`, `ret`,
   with short/near choice and rel16 in 16-bit code), `push` / `pop`,
   `imul`, `xchg`, `lea`, `in` / `out`, string instructions, `enter`, MPX,
   the system ones, x87.
7. **After encoding**: `amd64_cpu_forms` (the `cpu` level the form needs),
   `amd64_obsolete` (removed instructions), GNU's GOT / PLT preferences.

The building blocks every path uses: `amd64_emit_prefixes`,
`amd64_emit_modrm_sib` (ModRM, SIB, displacement, RIP-relative), the REX /
REX2 bytes (`amd64_rex_out`, `amd64_rex2_finish`), `amd64_emit_vex2/3`,
`amd64_encode_evex`, `amd64_emit_reloc`, `amd64_emit_branch_disp`.

### Outside 64-bit mode (`mode.s`)

The encoders are written for 64-bit mode; `mode.s` holds every
difference: registers and addressing that do not exist (`amd64_mode_check`),
a REX an instruction needs and cannot have (`amd64_rex_scan`), the 66
operand-size prefix meaning the other size (`amd64_osz66`), and the forms
only 16/32-bit mode has or encodes differently (`amd64_mode_special`:
`inc r32` as 40+r, `push`/`pop` of segment registers and immediates,
`pusha`, `daa`, `bound`, `arpl`, `les`/`lds`, A0-A3 `mov` with an absolute
address ...).

### The mnemonic table (`isa.s`)

`mnc_tb_x64`: every mnemonic name → its ID (2,760 entries), and
`amd64_register_table`: every register name → its ID, size and class. The
parser finds names here; the encoders dispatch on the ID. Its
**generated block** (the mnemonics only NASM's list has) is rewritten by
`scripts/gen/gen_x86_enc.py`; `diag/gen/mnemonic_names.inc` is derived
from this file for "did you mean" (rerun `scripts/gen/gen_mnemonic_names.py`
after adding mnemonics).

## The generated table (`gen/opcode.s`)

**Do not edit.** `scripts/gen/gen_x86_enc.py` writes it from the opcode
map in `scripts/gen/gen_x86_tables.py` (shared with the disassembler, so
both read every encoding the same way) plus NASM's `insns.dat`
(`third_party/nasm/`) for what the map lacks. 11,592 forms, 16 bytes each
(the layout is in the script's docstring), indexed by mnemonic ID
(`x86_enc_index`) and tried in order; `x86_cpu_level` gives each form's
`cpu` level.

```sh
python3 scripts/gen/gen_x86_enc.py           # regenerate (also isa.s's block)
python3 scripts/gen/gen_x86_enc.py --check   # fail if out of date
```

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `encoder.s` | 2,220 | `amd64_encode_instruction` (the steps above); the hand-written encoders in the `encoder/` parts, %included in this order: |
| `encoder/support.inc` | 917 | CPU forms, GOT forms, obsolete instructions, immediate guesses, rip-relative displacements, relaxation kinds, disp8*N, branch widths, relocation errors |
| `encoder/mov_arith.inc` | 1,236 | mov, arithmetic, syscall / sysret, xchg, push / pop, branches, ret, jcc |
| `encoder/general.inc` | 929 | movzx / movsx / movsxd, lea, test, unary, shifts, imul, cmovcc / setcc, enter, int, system, in / out, x87, SSE crypto |
| `encoder/vex_evex.inc` | 652 | the VEX / EVEX entries, string instructions, 0F binaries, cmpxchg, bt, memory sync, r/m forms |
| `encoder/branch.inc` | 524 | branch sizing, and tracking each instruction for the second pass |
| `encoder/emit.inc` | 1,172 | relocations, prefixes, ModRM / SIB, bytes and dwords; the SGX leaves |
| `encoder/jmp_call.inc` | 609 | jmp, call, xbegin, far widths, push / pop forms, MPX, nop, words and qwords |
| `encoder/sse_avx.inc` | 393 | AVX / SSE forms, the VEX2 / VEX3 prefixes; messages and the obsolete tables |
| `dispatch.s` | 1,859 | the table encoder: `amd64_table_encode`, `amd64_table_has`, form matching and emission |
| `mode.s` | 3,108 | 16- and 32-bit mode: what changes from 64-bit, REX / REX2 placement, the 66 / 67 prefixes |
| `apx.s` | 1,378 | APX's EVEX map-4 integer instructions |
| `shape.s` | 453 | the operand shapes of the general-purpose instructions (`amd64_check_shape`, `amd64_shape_forms`) |
| `msr.s` | 272 | the MSR instructions with operands (MSR_IMM, USER_MSR) |
| `noops.s` | 206 | the instructions that take no operands |
| `gather.s` | 99 | the gathers' distinct-register rule |
| `amx.s` | 75 | AMX's distinct-tile rule |
| `isa.s` | 3,442 | `mnc_tb_x64` (mnemonics), `amd64_register_table` (registers) |
| `gen/opcode.s` | 47,480 | GENERATED: the table encoder's forms |

## Entry points

| Symbol | Used by |
| --- | --- |
| `amd64_encode_tracked` | main/utasm.s, once per instruction (it calls `amd64_encode_instruction`) |
| `mnc_tb_x64`, `amd64_register_table` | frontend/syntax (names), frontend/preproc (`%use altreg`), semantic/ |
| `amd64_reloc_err` | link/reloc (a relocation's error at the instruction's line); also set by `amd64_emit_modrm_sib` (an address with no encoding) and `amd64_emit_byte` (past 15 bytes), which return as any call does - they jumped to the driver's `.error`, past their callers' pops, and utasm crashed |
| `amd64_table_has`, `cpu_num`, `gas_got_wanted` | frontend/syntax |
| `amd64_emit_modrm_sib`, `amd64_emit_dword`, `amd64_disp8n`, `amd64_force_sib`, `amd64_imm_guess` | the other files here (dispatch, mode, apx, msr) |

## Depends on

core/ (emitting bytes, sections, the second pass), link/reloc
(relocations), optimize/jump.s (forward jump records), frontend/syntax
(`asm_bits`, the expression flags), diag/ (every error and warning).

## Status

Complete for x86-64: the forms of NASM 3.01's and GNU as 2.47's
instruction tables, in all three modes. `encoder.s` holds the driver;
the hand-written encoders are in its `encoder/` parts, cut where its
functions were, in their old order (the object is the same, byte for
byte).

## Tests

`tests/compat/run_all.py`: *encoder corpus* (every instruction of
`corpus.py`, byte for byte against NASM), *operand shapes* (~1,700
register / memory pairings), *addresses* (every base / index / scale
order), *bits 32 / bits 16*, *isa* (newer than NASM: against GNU as),
*rejections* (what NASM refuses, and #UD encodings), *objdump readback*;
`tests/compat/encfuzz.py` (random forms from NASM's own table).
