# encode/aarch64/ — the AArch64 encoder (`-arch aarch64`)

**Deferred** (x86-64 comes first; there are no AArch64 devices to test on
yet). What is here works for the base instructions below; most of
AArch64 is not encoded yet, so tests of it are expected to fail.

## How it works

`aarch64_encode_instruction` (base.s) dispatches on the INST's mnemonic ID
to one encoder per instruction class, each building the fixed 32-bit
instruction word and writing it with `aarch64_emit_word`:

| Class | Mnemonics | Encoder |
| --- | --- | --- |
| data processing (register) | `add sub and orr bic orn eon` | `aarch64_encode_dp_reg` |
| moves | `mov` (as `orr` / `movz`), `movz movn movk` | `aarch64_encode_mov`, `_mov_wide` |
| compare / test | `cmp` (`subs zr`), `tst` | `aarch64_encode_cmp`, `_tst` |
| branches | `b bl br blr ret cbz cbnz`, `b.eq` .. `b.nv` | `aarch64_encode_branch`, `_branch_link`, `_branch_reg`, `_ret`, `_comp_branch`, `_jcc` |
| loads / stores | `ldr str ldp stp` | `aarch64_encode_ldst_common`, `_ldst_pair` |
| bit / extend | `rev`, `sxtb sxth sxtw` | `aarch64_encode_rev`, `_extend` |
| system | `svc hlt mrs msr dsb dmb isb wfi nop` | `aarch64_encode_svc`, `_hlt`, `_system_reg` |
| floating point | `fadd fsub fmul fdiv` (scalar) | `aarch64_encode_fp_bin` |
| vector (a few) | the `add` .. `eor` vector forms | `aarch64_encode_vector_bin` |
| utasm's string ops | `movsb..movsq`, `stosb..stosq` (expanded) | `aarch64_encode_string_mov`, `_string_sto` |

Anything else is an error. `isa.s` knows far more names than this
(952 mnemonics, from the full ARMv8-A / SVE / SME lists) so the parser
recognises them; only the classes above are encoded.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `base.s` | 589 | `aarch64_encode_instruction` and the class encoders above |
| `isa.s` | 1,029 | `mnc_tb_arm64` (mnemonic names → IDs) and `aarch64_register_table`; the IDs match `include/arch/aarch64.inc` |
| `neon.s` | 4 | placeholder: NEON (Advanced SIMD) encoders |
| `sve.s` | 4 | placeholder: SVE / SVE2 encoders |

## Entry points

| Symbol | Used by |
| --- | --- |
| `aarch64_encode_instruction` | main/utasm.s (each instruction when `-arch aarch64`) |
| `mnc_tb_arm64`, `aarch64_register_table` | frontend/syntax (the parser's tables for this target) |

## Depends on

core/asmctx.s (emitting the words). No relocations yet: branch targets
must be known when the instruction is encoded.

## What is left

Relocations (forward branches, `adrp` / `:lo12:`), the rest of the base
ISA (shifted / extended register operands, immediates of the logical
instructions, every load / store addressing mode, conditional select,
multiply / divide, bit fields), floating point and NEON (`neon.s`), SVE
(`sve.s`), ELF `EM_AARCH64` objects.

## Tests

`tests/asm/aarch64/*.s` and `tests/asm/aarch64_suite.s`, run by
`tests/run.sh` (`-arch aarch64`; running the output needs QEMU). Expected
to fail in part until the work above is done.
