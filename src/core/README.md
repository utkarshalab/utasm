# core/ — the assembler context, the second pass, the crash handler

Three things every part of assembly relies on:

- **the AsmCtx and its sections** (`asmctx.s`): where every byte utasm
  produces goes;
- **the second pass** (`known.s`): how utasm, which reads the source once,
  still gives NASM's (multi-pass) bytes for names used before they are
  defined;
- **the crash handler** (`crash.s`): a fault inside utasm becomes an
  error message at the source line, not a core dump.

## The AsmCtx and sections (`asmctx.s`)

There is one `ASMCTX` (struc in `include/type.inc`), `global_ctx`
(main/utasm.s). It holds the target, the output format, the options
(`flags`, `opt`), the arena, the symbol table, the **section array** and
the **current section**, and the relocation array.

A `SECTION` (also in type.inc) is a growable byte buffer (`data`, `size`,
`cap`) with its ELF name, type, flags and alignment, plus what the flat
binary layout needs (`vstart`, `start`, `follows`) and the jump shortener
(`relax_frozen`).

Every encoder and data directive writes through these:

| Function | What it does |
| --- | --- |
| `asm_ctx_emit_byte / word / dword / qword / string` | append to the current section (the buffer doubles when full; a fast path stores directly when there is room) |
| `asm_ctx_create_section` | a new section by name (`section .data`), or the existing one |
| `asmctx_find_section`, `asmctx_get_section` | look a section up by name / index |
| `asm_ctx_fit` | make room for N more bytes |
| `asm_ctx_align`, `asm_ctx_align_fill`, `asm_ctx_align_spec` | `align N` with its fill (the padding is recorded for the jump shortener, which re-pads when code moves) |
| `asm_ctx_padto` | `times K-($-$$)`: pad up to an offset |

The `asmctx_*` names are aliases of the `asm_ctx_*` ones (both are used).

## The second pass (`known.s`)

utasm reads the source once. A constant defined **after** its use

```nasm
mov rsi, [rax + thread_t.cgroup_ptr]   ; the struc comes later in the file
```

is unknown when the instruction is encoded, so it gets the long form (a
disp32 and a relocation), where NASM, reading the source several times,
writes a disp8. To come out the same:

1. **Pass 1** notes every name used before its definition
   (`known_note_forward`). At the end, those that turned out to be
   constants whose value does not depend on where code lies are written to
   a memfd, and utasm **runs itself again** with `UTASM_KNOWN=<fd>`
   (`known_second_pass`; nothing has been written yet).
2. **Pass 2** finds their values with `known_lookup` wherever the name is
   still undefined, and encodes the instruction as for a constant defined
   before it. Pass 2 never asks for a third — with one exception below.

Also handed to pass 2, and **checked** once the code is laid out
(`known_verify`):

- a constant that depends on positions (`len equ y - x`);
- an instruction operand with a label not defined yet
  (`push dword (end - start) / 4`): pass 1 lays the code out as
  `linker_run` would and works it out, pass 2 takes the number, so the
  instruction gets NASM's form (`6A ib`, not `68 id`);
- a label difference the preprocessor reads (`%if $ - $$ > 510`,
  `%assign n end - start`: `known_pp_diff`).

Because a value that shortens code can change what it measures, pass 2
works each one out again once the layout is final; on any difference
utasm runs a third time with the constants only. When pass 1 finds nothing
to hand on, there is no second pass.

## The crash handler (`crash.s`)

`crash_install` sets handlers for SIGSEGV, SIGBUS, SIGFPE and SIGILL, on a
stack of their own (so a stack overflow is caught too). A fault is
reported like NASM's panic, at the statement being read:

```
prog.s:12: fatal: internal error: segmentation fault at 0x41c2a7 (please report it)
```

and utasm exits with `EXIT_SIGNAL` instead of dumping gigabytes of
reserved arena. The handler uses only `write` and `exit_group`.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `asmctx.s` | 806 | sections and the emitters, alignment and padding |
| `known.s` | 1,500 | the second pass: noting forward uses, the memfd hand-over, `known_lookup`, `known_verify`, the preprocessor's label differences (`known_pp_diff`, `known_remap`) |
| `crash.s` | 212 | `crash_install` and the signal handler |

## Entry points

| Symbol | Used by |
| --- | --- |
| `asm_ctx_emit_*`, `asm_ctx_create_section`, `asm_ctx_align*`, `asm_ctx_padto` | frontend/syntax (data, sections, align), encode/ (every instruction), debug/, object/ |
| `known_init`, `known_second_pass` | main/utasm.s |
| `known_note_forward`, `known_lookup`, `known_tentative` ... | frontend/syntax (expressions), encode/x86 (operand sizes), optimize/jump.s, link/ |
| `known_verify`, `known_remap` | link/linker.s, optimize/jump.s |
| `crash_install` | main/utasm.s |

## Depends on

lib/ (strings, the arena), diag/ (messages), optimize/ (layout for the
verification), frontend/syntax (expressions), platform/ (the memfd).

## Status

Complete. Unused today: `asm_ctx_emit_word`, `asm_ctx_emit_qword`,
`asm_ctx_emit_string`, `asmctx_create_section` — kept as the context's
interface.

## Tests

*expressions* (labels and equs defined later, in every position) and
*limits* in `tests/compat/run_all.py`; the second pass is exercised by
every corpus that defines strucs after use (the gen1 self-build is one:
utasm's own sources do this). *robustness* covers the crash handler.
