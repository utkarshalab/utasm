# encode/ — instructions to machine code

The parser hands each instruction over as an `INST` (struc in
`include/type.inc`: the mnemonic ID, prefixes, up to four `OPERAND`s);
the encoder of the target architecture writes its bytes into the current
section (`core/asmctx.s`) and records a relocation for anything not known
yet (`link/reloc/reloc.s`).

Each architecture has its own folder with its **encoder** and its
**mnemonic / register table** (`isa.s`, which the parser looks names up
in):

| Folder | Target (`-arch`) | Status |
| --- | --- | --- |
| [x86/](x86/README.md) | `amd64` (the default) | complete: every instruction NASM 3.01 and GNU as 2.47 know, in 16-, 32- and 64-bit code |
| [aarch64/](aarch64/README.md) | `aarch64` | base instruction classes; NEON / SVE placeholders |
| [riscv64/](riscv64/README.md) | `riscv64` | RV64I base classes and some of the C / A / F extensions; the rest placeholders |

x86-64 comes first (Utkarsha OS's architecture); the others are deferred
until there are devices to run them on, so their test failures are
expected for now.

## The contract every encoder keeps

- Input: `rdi` = AsmCtx, `rsi` = INST. Output: `rax` = `EXIT_OK` or an
  `EXIT_*` error (reported at the statement's line by `diag/codes.s`; the
  statement is undone and assembly goes on).
- Bytes go out through `asm_ctx_emit_*` in the current section.
- A symbol whose value is not known yet becomes a relocation
  (`reloc_record`) — resolved at the end, or written to the object.
- A forward jump is written long and noted for `optimize/jump.s`, which
  shortens it once every label is known.
