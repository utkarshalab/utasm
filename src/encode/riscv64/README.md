# encode/riscv64/ — the RISC-V 64 encoder (`-arch riscv64`)

**Deferred** (x86-64 comes first; there are no RISC-V devices to test on
yet). The base integer ISA and parts of several extensions are encoded;
the rest is not, so tests of it are expected to fail.

## How it works

`riscv64_encode_instruction` (base.s) checks the operand count, then
dispatches on the mnemonic ID to one encoder per **instruction format**,
each building the 32-bit word (`riscv64_emit_word`; 16-bit for the
compressed ones, `riscv64_emit_half`). Branch and jump targets not known
yet become relocations (`reloc_record` with the RISC-V types).

| Format / group | Mnemonics | Encoder |
| --- | --- | --- |
| R-type | `add sub sll slt sltu xor srl sra or and` | `riscv64_encode_r_type` |
| RV64M (in base.s) | `mul mulh mulhsu mulhu div divu rem remu` | `riscv64_encode_r_type` |
| I-type | `addi slti sltiu xori ori andi`, shifts `slli srli srai` | `riscv64_encode_i_type`, `_i_shift` |
| loads | `lb lh lw ld lbu lhu lwu` | `riscv64_encode_i_type` |
| stores (S-type) | `sb sh sw sd` | `riscv64_encode_s_type` |
| branches (B-type) | `beq bne blt bge bltu bgeu` | `riscv64_encode_b_type` |
| U-type | `lui auipc` | `riscv64_encode_u_type` |
| jumps (J-type) | `jal jalr` | `riscv64_encode_j_type`, `_jalr` |
| bit / extend | `rev8`, `sext.b` & co. | `riscv64_encode_rev8`, `_extend` |
| system | CSR instructions, `ecall ebreak mret sret` | `riscv64_encode_csr` |
| fences | `fence fence.i` | `riscv64_encode_fence` |
| RV64A (in base.s) | the AMO instructions (`amoadd.w` ...) | `riscv64_encode_atomic` |
| RV64F/D (in base.s, basic) | `fadd.s` ... | `riscv64_encode_fp` |
| pseudo | `call tail li`, `c.nop c.mv c.addi` | `riscv64_encode_pseudo_call`, `_li`, `_rvc_mv`, `_rvc_addi` |
| utasm's string ops | `movsb..`, `stosb..` (expanded) | `riscv64_encode_string_mov`, `_string_sto` |

`isa.s` knows far more names (780 mnemonics) than are encoded, so the
parser recognises them.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `base.s` | 1,103 | `riscv64_encode_instruction` and every encoder above |
| `isa.s` | 905 | `mnc_tb_rv64` (mnemonics → IDs), `riscv64_register_table`; IDs match `include/arch/riscv64.inc` |
| `m.s` | 4 | placeholder: RV64M — note that base.s already encodes the eight M instructions |
| `a.s` | 4 | placeholder: RV64A — base.s already encodes the AMOs |
| `fd.s` | 4 | placeholder: RV64F / D — base.s encodes the basic arithmetic only |
| `v.s` | 4 | placeholder: RVV vector instructions |
| `relax.s` | 4 | placeholder: linker relaxation (`call` / `tail` shortening) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `riscv64_encode_instruction` | main/utasm.s (each instruction when `-arch riscv64`) |
| `mnc_tb_rv64`, `riscv64_register_table` | frontend/syntax |

## Depends on

core/asmctx.s (emitting), link/reloc (branch and call relocations).

## What is left

The rest of F / D (conversions, compares, fused multiply-add, loads and
stores), the C extension in full, V (`v.s`), Zb*, relaxation (`relax.s`),
`EM_RISCV` objects with their relocations checked against GNU as. When
that work starts, move the M / A / F encoders out of base.s into their
files (or delete the placeholders).

## Tests

`tests/asm/riscv64/*.s` and `tests/asm/riscv64_suite.s`, run by
`tests/run.sh` (`-arch riscv64`; running needs QEMU). Expected to fail in
part until the work above is done.
