# optimize/ — jump shortening and alignment padding

Two things that decide how big code is once the whole program is known:
**which jumps can be short** (`jump.s`) and **what `align` pads with**
(`align.s`). Both have to stay right while code moves, so they are built
together: when the shortener moves code, the padding is regenerated.

## Jump shortening (`jump.s`)

utasm assembles in one pass, so a jump to a label not defined yet has to
be written before its distance is known — the 5- or 6-byte rel32 form.
Most such targets turn out to be close. `relax_run` (called from
`link/linker.s` once every instruction is emitted, before relocations are
resolved) rewrites every forward

```
jmp label   E9 rel32     (5 bytes)  →  EB rel8  (2 bytes)
jcc label   0F 8x rel32  (6 bytes)  →  7x rel8  (2 bytes)
```

whose target is within reach, and moves the rest of the section up. That
is the same result NASM reaches by reading the source again and again —
but in one walk over the jumps per round instead of a pass over the
source, which is why utasm is ~100x faster on jump-heavy code.

### What moving code must keep correct

While assembling, the encoder, the parser and `align` **note** what the
shortener needs (`relax_note`, emission order):

| Kept correct | How |
| --- | --- |
| labels | the section's symbols are remapped (`relax_map_offset`) |
| relocations | their offsets are remapped; a shortened jump's own is deleted (resolved here) |
| branches already resolved (backward jumps, calls) | recorded (`RELAX_FIXED`) and their displacements rewritten |
| `align` | the padding points are recorded (`RELAX_ALIGN`) and re-padded for the new layout (align.s's fill specs) |
| label differences (`b - a`, `$ - msg`, `$ - $$`) | the range between them is **frozen** (`relax_freeze_range`): nothing inside may change size; an `equ` of such a difference is worked out after shortening instead (`parser_late_equs`) |
| `times K-($-$$) db F` | padding up to an offset (`RELAX_PADTO`) grows by what is removed before it |
| a position used as a plain number (`label >> 4`) | freezes the whole section |
| the listing, the DWARF line table, CFI | follow the moved code (`lst_remap`, `line_remap`, `cfi_remap`) |

Choosing jumps is **iterative**: shortening one can bring another into
reach. Growing padding can push a shortened jump back out of reach; such
a jump is put back to rel32 for good and the search repeats, so it always
terminates. If a branch the encoder already wrote as rel8 would no longer
reach, the section is left unchanged.

Only local labels in the same section are shortened (exported ones stay
long, as NASM leaves them), only in x86-64 output.

### Optimization levels (`-O`)

| Level | What happens |
| --- | --- |
| `-O0`, `-O1` | nothing: every jump as the encoder wrote it (NASM's -O0 / -O1) |
| `-Ox` (default) | shortening only: NASM's result |
| `-Os` | also rewrites jumps beyond NASM: `jcc L1 / jmp L2 / L1:` → `j!cc L2`; jump threading (`jmp A`, `A: jmp B` → `jmp B`); a jump to the next instruction removed — each only when it keeps the program's behaviour. In a section of jumps only it finds the fewest long jumps (`rx_fast`), where NASM's passes can settle on more |

## Alignment padding (`align.s`)

What `align N` writes. Without a fill it is NASM's: `0x90` repeated (in
data sections too). `%use smartalign` makes it long NOPs chosen by
`alignmode`:

| Mode | Padding |
| --- | --- |
| `nop` | 0x90 bytes |
| `generic` (default) | `lea` / `mov` forms that do nothing (bits 16/32), 66-prefixed nops (bits 64) |
| `k8`, `k7` | AMD's 66-prefixed nops (k7: `lea` forms in bits 32) |
| `p6` | `0F 1F /0` multi-byte nops |
| `gas` | GNU as's (`0F 1F /0` up to 11 bytes, never a jump) — what a GNU directive's alignment writes in code |

Padding longer than the mode's threshold (8 generic, 16 others; never with
`alignmode MODE, nojmp`) is jumped over: a `jmp` to its end, then nops.
Every byte follows from the length, the mode and the bits, described by a
**fill spec** (a qword kept in the relaxation record), so jump.s can
regenerate it after moving code.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `jump.s` | 3,320 | `relax_run` and the records it reads, the iterative choice, moving code, the `-Os` rewrites, `rx_fast` |
| `align.s` | 352 | `align_fill`, `align_fill_spec`, the NOP tables per mode and bits, `alignmode` (`align_mode_directive`), GNU's `.p2align` MAX (`align_gas_spec`) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `relax_run`, `relax_padto_check` | link/linker.s; core/known.s (pass 1 lays the code out to work values out) |
| `relax_note`, `relax_freeze_*`, `relax_defer_*`, `relax_mark_rank`, `relax_count`, `relax_truncate` | encode/x86 (jumps), frontend/syntax (differences, times), core/asmctx.s (align), main/utasm.s (undoing a failed statement) |
| `relax_map_offset*` | debug/, object/listing (following moved code), core/known.s |
| `align_fill`, `align_fill_spec`, `align_mode_directive`, `smartalign_mode` | core/asmctx.s, frontend/preproc (`%use smartalign`), frontend/syntax |

## Depends on

lib/ (vectors, strings), object/ and debug/ (their remaps), frontend/syntax
(late equs), diag/.

## Status

Complete for x86-64. Other architectures' jumps are not shortened
(RISC-V's call relaxation is a placeholder, `encode/riscv64/relax.s`).

## Tests

`tests/compat/run_all.py`: *bin probes* and *encoder corpus* (NASM's
bytes, so NASM's jump sizes), *listings* (the listing follows moved code),
*dwarf line tables*, *cfi frames*, *expressions* (label differences over
jumps); the benchmarks in `scripts/bench/` measure the speed.
