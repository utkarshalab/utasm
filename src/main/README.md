# main/ — the entry point and the command line

`_start` is here: utasm's whole run, from the arguments to the exit code.
It sets everything up, runs the **assembly loop** (one statement at a
time: parse, then encode), and at the end hands over to `linker_run`,
which finishes the output (see [../README.md](../README.md) for the
pipeline).

## What `_start` does, in order

1. **Crash handler** (`crash_install`, core/crash.s): a fault inside utasm
   is reported as an internal error at the statement being read, not a
   core dump.
2. **Second pass?** (`known_init`, core/known.s): if `UTASM_KNOWN` is set,
   this run is pass 2 and reads the constants pass 1 found.
3. **Arena, context, symbol table**: `arena_init` (lib/arena.s), an AsmCtx
   (`global_ctx`), `symbol_init` (semantic/symtable.s).
4. **Command line** (`cli_parse`): fills the AsmCtx — format, output,
   mode, include paths, warnings, `-E`, `--inspect`, `--disasm`, `--lsp` ...
   Diagnostics are set up after it (`diag_init`, `-X json`).
5. **Not assembling?** `--inspect` / `--disasm` (tools/inspect),
   `--lsp` (tools/lsp), `-h` / `-v` return from here.
6. **Profiler** (`--profile`): `profiler_init`.
7. **The source**: opened (or stdin copied to a memfd), mmapped, and a
   lexer (`lexer_init`) and preprocessor (`prep_init`) made for it; the
   predefined macros (`prep_predefine`) and the `-p` / `--before` lines go
   in ahead of the source.
8. **The assembly loop** (`.assembly_loop`):
   - `rc_snapshot` notes the section's size, so a statement that fails can
     be undone and assembly can go on (every error in a file is reported);
   - `parser_parse_instruction` reads one statement (a directive or label
     is handled entirely there; an instruction comes back as an INST);
   - the instruction is encoded for the target: `amd64_encode_tracked`
     (encode/x86), `aarch64_encode_instruction`, `riscv64_encode_instruction`,
     with the line table (`line_insn`) and proc checks (`proc_insn`) around it;
   - on an error: report it (`error_report_code`), undo the statement
     (`rc_failed`), skip the rest of its line, go on — up to 100 errors.
9. **End of source**: each syntax finishes (`parser_finish`, `gas_finish`,
   `masm_finish`, `fasm_finish`, `proc_finish`, `ns_finish` ...), `-M`
   dependencies, the second pass if one is needed (`known_second_pass`).
10. **`linker_run`** (link/linker.s): shortens jumps, builds the debug
    tables, resolves relocations, writes the output file.
11. **Listing, map file, profiler report**, then exit with the first
    failure's status (`rc_status`), or 0.

`-E` (preprocess only) takes a shortcut after step 7: `prep_dump` writes
the expanded source.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `utasm.s` | 1,042 | `_start` (the steps above); the error recovery (`rc_snapshot`, `rc_failed`, `rc_fatal`, `rc_skip_line`); stdin as a file (`utasm_stdin`); `print_str` / `print_num`; the `-h` text; the globals every module reaches: `global_ctx`, `global_arena`, `global_lexer`, `global_prep`, `utasm_argv`, `utasm_envp`, `rc_status` |
| `cli.s` | 1,564 | `cli_parse`: every option into the AsmCtx and the module flags; NASM's options (`cli_nasm_option`: `-I -D -U -p -E -l -M* -w -W -X -O -Z -s`); `cli_write_deps` (`-M` output); the options other modules read: `cli_bits`, `cli_mode`, `cli_prelude`, `cli_output_given`, `cli_deps`, `cli_lsp` |

## Entry points

| Symbol | Used by |
| --- | --- |
| `_start` | the kernel (the ELF entry point) |
| `global_ctx`, `global_arena`, `global_prep` | nearly every module: the one AsmCtx, arena and preprocessor |
| `cli_parse`, `cli_write_deps` | `_start` |
| `cli_bits`, `cli_mode`, `cli_prelude*` | frontend/syntax (the starting `bits`), tools/disasm (`--bits`, `--org`) |
| `print_str`, `print_num` | diag, profile, tools — plain output to stdout / stderr |

## Depends on

Everything: this is where every module is started and finished. Most
calls go to diag/, object/, frontend/ and lib/.

## Status

Complete for what utasm does today. When **multi-object linking** comes
(Phase B, link/), the loop will take several sources (or a `link` mode)
and `_start` will hand all of them to the linker.

## Tests

Every suite runs through `_start`. The command line in particular:
`tests/compat/run_all.py` — *command line* (NASM's options against NASM's
own output), *diagnostics*, *error recovery* (every error in a file
reported), *robustness* (inputs that once crashed utasm).
