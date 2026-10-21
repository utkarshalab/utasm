# semantic/ — names: the symbol table, procs, namespaces and modules

Everything about **names**: where each label, constant, extern and macro
name is kept and found (`symtable.s`), and utasm's own language features
built on names — **procs** with stack and register checks (`proc.s`) and
**namespaces / modules** with private names (`namespace.s`). The last two
are utasm's syntax only (not under `%use masm` or GNU's).

## The symbol table (`symtable.s`)

A hash table of `SYMBOL`s (struc in `include/type.inc`: name, kind,
value, section, size, visibility, ELF type, defining line ...), keyed by
the FNV-1a 64-bit hash of the name, open addressing with quadratic
probing.

It starts at `SYM_HASH0` slots and **doubles** whenever it is half full,
up to `MAX_SYMBOL`. The address space is reserved at the full size up
front but touched only as it grows: at full size from the start, the few
hundred predefined macros alone touched as many pages as most of an empty
source's run.

| Function | What it does |
| --- | --- |
| `symbol_init` | the empty table (main/utasm.s, at start) |
| `symbol_add` | insert a name, or return the existing entry |
| `symbol_find` | look a name up (rax = the SYMBOL, or 0) |
| `sym_defseq` | a counter of definitions — COFF writes symbols in that order, as NASM does |

## Procs (`proc.s`)

```nasm
proc NAME [uses rbx, r12 ...]
    ...
endproc
```

NAME is a label like any other; **no code is added**. Between `proc` and
`endproc` utasm follows the stack depth and the preserved registers
(System V: rbx, rbp, r12-r15 — `docs/reference/abi.md`) through the code
as written, and reports:

| Check | Kind | When |
| --- | --- | --- |
| `proc-stack` | error | the stack not back where it was at a `ret`, or a label two paths reach with different depths |
| `proc-uses` | error | a `uses` register written before it is pushed, not restored at the `ret`, or never saved |
| `proc-clobber` | warning | a preserved register written that `uses` does not name |
| `proc-unreachable` | warning | code after a `ret` / `jmp` with no label between |
| `proc-fallthrough` | warning | the code runs on into `endproc` |

The depth counts bytes pushed since NAME: `push`/`pop`, `sub`/`add rsp,
imm`, `lea rsp, [rsp+imm]`, `enter`/`leave`, `mov rbp, rsp` ... `mov rsp,
rbp`; any other write to rsp makes it unknown until a frame restores it.
A jump carries its depth to its label. `proc_insn` sees each instruction
before it is encoded (main/utasm.s); `proc_finish` closes the last one.

## Namespaces and modules (`namespace.s`)

```nasm
namespace net               module net          ; a module: to the end of its file
    send: ...                   export send     ;   its names private but those exported
endnamespace                    send: ...
```

- A name defined inside is qualified: `net::send` (they nest:
  `net::tcp::open`). A local label stays its label's: `net::send.again`.
- A name **used** inside is looked for in the innermost namespace first,
  then each one out, then outside them all; `::log` is always the outer
  one.
- `private NAME, ...` in a namespace, and every name a module does not
  `export`, may only be used from inside.
- A name used before its definition is resolved at the end (`ns_finish`):
  the reference's text is rewritten with what it turned out to be. Two
  errors are found there: a name taken from an outer namespace that an
  inner one defines later (it would have meant the inner one), and a
  private name used from outside.

The output is unchanged: `net::send` is an ordinary label in the object.
Full rules: `docs/user/syntax.md`, *Namespaces and modules*.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `symtable.s` | 333 | the hash table: `symbol_init`, `symbol_add`, `symbol_find`, growth |
| `proc.s` | 962 | `proc` / `endproc`, the stack and register tracking, the five checks |
| `namespace.s` | 1,047 | `namespace` / `endnamespace`, `module` / `export` / `private`, qualification, late resolution |

## Entry points

| Symbol | Used by |
| --- | --- |
| `symbol_add`, `symbol_find` | nearly every module (frontend, core, link, object, debug, optimize) |
| `proc_word`, `proc_label`, `proc_insn`, `proc_finish`, `proc_active` | frontend/syntax (the words, labels), main/utasm.s (each instruction, the end) |
| `ns_word`, `ns_qualify`, `ns_ref`, `ns_ref_suffix`, `ns_finish`, `ns_depth` | frontend/syntax, main/utasm.s |

## Depends on

lib/ (hashing, strings, the arena), diag/ (the checks' messages),
frontend/syntax and frontend/preproc (the statements and names being read),
encode/x86 (which registers an instruction writes, for procs).

## Status

Complete. Namespaces work within one assembly: a `module` is brought in
with `%include`. With multi-object linking (Phase B, link/), modules
should get separate compilation — an `import` that reads only a module's
exported names, and private names that stay private across objects.

## Tests

`tests/compat/run_all.py`: *procedures* (each check), *namespaces*
(qualification, lookup order, private / export, the late errors), and
every suite through the symbol table.
