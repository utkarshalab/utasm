# src/ — utasm's source

Everything utasm is made of, in x86-64 assembly (NASM syntax, so NASM can
build the first generation). The build (`make`) assembles every `.s` under
this folder, in sorted order, and links them with `ld`; `.inc` files are
included by the `.s` files that need them.

Each folder below has its own README: what it does, how, every file in it,
its entry points, what it depends on, what is left to do, and which tests
cover it. Start here, then read the module you are working on.

## How a source file becomes an object

utasm reads the source **once**, statement by statement, and writes each
instruction's bytes as it goes. Everything that needs the whole program —
jump sizes, label values, relocations, debug tables — is worked out at the
end, in `link/linker.s`.

```
                main/utasm.s  (_start: the driver)
                     │
   cli.s ─ options ──┤
                     ▼
  ┌──────────────── the assembly loop: one statement at a time ─────────────────┐
  │                                                                              │
  │  frontend/lexer ──tokens──▶ frontend/preproc ──tokens──▶ frontend/syntax      │
  │   (characters → tokens)     (%macro %if %rep %include,   (statements: an     │
  │                              %define, macro calls)        instruction → INST,│
  │                                                           directives, labels,│
  │                                                           data, expressions) │
  │                                                                 │            │
  │                         semantic/ (symbols, procs, namespaces)◀─┤            │
  │                                                                 ▼            │
  │            encode/x86 (or aarch64, riscv64): INST → bytes in the current     │
  │            section (core/asmctx.s); a reference not known yet → a relocation │
  │            record (link/reloc); a forward jump → long form, noted for        │
  │            optimize/jump.s                                                   │
  └──────────────────────────────────────────────────────────────────────────────┘
                     │  end of source
                     ▼
  link/linker.s (linker_run):
      optimize/jump.s   shorten the forward jumps that reach (code moves up)
      debug/            .eh_frame (cfi), .debug_* (dwarf), GNU's line table
      object/flat, elf  lay out a flat binary / an executable
      link/reloc        resolve every relocation that can be; keep the rest
      core/known.s      check the values a second pass relied on
      object/           write: ELF64 (then ELF32 / COFF from it), bin, UBF
                     │
                     ▼
      object/listing (-l), object/map.s (map files), -M dependencies
```

Errors and warnings at any step go through `diag/`, which reports them at
the source line they came from (and, on a terminal, shows the line).

**Two passes, sometimes.** A constant used before it is defined (an `equ`,
a structure field) cannot be known when its instruction is encoded, so it
would get the long form where NASM, which reads the source many times,
picks the short one. When that happens `core/known.s` runs utasm again
with the values pass 1 found, so the output is NASM's. Most sources need
one pass.

## Modules

| Folder | What it does |
| --- | --- |
| [main/](main/README.md) | the entry point (`_start`), the assembly loop, the command line |
| [core/](core/README.md) | the assembler context (sections, emitting bytes), the second pass, the crash handler |
| [include/](include/README.md) | constants, structures, macros shared by every file |
| [frontend/](frontend/README.md) | source text to statements: [lexer/](frontend/lexer/README.md), [preproc/](frontend/preproc/README.md), [syntax/](frontend/syntax/README.md) |
| [semantic/](semantic/README.md) | the symbol table, procs, namespaces and modules |
| [encode/](encode/README.md) | statements to machine code: [x86/](encode/x86/README.md), [aarch64/](encode/aarch64/README.md), [riscv64/](encode/riscv64/README.md) |
| [optimize/](optimize/README.md) | jump shortening (branch relaxation), alignment padding |
| [link/](link/README.md) | the end of assembly (`linker_run`), relocations |
| [object/](object/README.md) | the output files: ELF64, ELF32, COFF, flat, UBF; listings, map files |
| [debug/](debug/README.md) | DWARF line tables and debug info, call-frame information |
| [diag/](diag/README.md) | errors, warnings, "did you mean", JSON diagnostics |
| [tools/](tools/README.md) | the built-in tools: [disasm/](tools/disasm/README.md), [inspect/](tools/inspect/README.md), [symdump/](tools/symdump/README.md), [lsp/](tools/lsp/README.md) |
| [profile/](profile/README.md) | `--profile`: how long each phase took |
| [platform/](platform/README.md) | system calls: files, memory |
| [lib/](lib/README.md) | the shared library: arena, strings, formatting, hashes, floats, SHA-256 ... |
| [planned/](planned/README.md) | placeholders for work not started (CPU profiles, self-patching) |

## Conventions every file follows

- **Calling convention:** arguments in `rdi, rsi, rdx, rcx, r8, r9`; the
  result or error code in `rax` (`EXIT_OK` = 0, else an `EXIT_*` code from
  `include/constant.inc`), a second result in `rdx`; `rbx, rbp, r12-r15`
  preserved. A function's comment says what it takes, gives, and clobbers.
- **Memory:** almost everything is allocated from one arena
  (`lib/arena.s`) that lives until utasm exits; nothing is freed.
- **No libc:** files and memory are raw system calls (`platform/`).
- **Includes** are written from the repository root:
  `%include "src/include/constant.inc"`.
- **Generated files** live in a `gen/` folder next to the code that uses
  them, and say which script makes them. Never edit them by hand: change
  the script (`scripts/gen/`) and rerun it; `--check` fails when they are
  out of date.
- Each module's README is kept in step with its folder by
  `scripts/check_readmes.py` (run by `tests/run.sh`): a file added, moved
  or removed without the README's file table changing fails it.
