# frontend/preproc/ — NASM's preprocessor

Everything that starts with `%`, and every macro call. It sits between the
lexer and the parser: the parser asks it for tokens
(`preprocessor_next_token`), and it gives the program's tokens **after**
directives have run and macros have been expanded — what NASM's
preprocessor would produce (`utasm -E` prints exactly that).

## How it works

### The token loop

`preprocessor_next_token` → `prep_internal_next`, which, each time:

1. takes the next token from the **innermost source**: a pushed-back
   token, then the current macro expansion (`prep_expand_next`), then a
   pushed buffer (`prep_push_buffer`: text the syntax layers rewrote), then
   the current file's lexer (`lexer_next`), popping finished includes;
2. if a `%` directive starts a line → `prep_handle_directive` runs it
   (and gives nothing to the parser for that line);
3. if it is inside a `%if` branch not taken → skipped;
4. if it is a **single-line macro** (`%define`) → replaced by its body,
   parameters substituted, then read again (so expansions nest);
5. if it is a **multi-line macro** (`%macro`) at the start of a statement
   (`ml_state`) → its arguments are read and an expansion starts
   (`prep_expand_start`);
6. otherwise → the parser gets it.

`%+` and `%[...]` paste and interpolate tokens (`prep_resolve_interp`,
`prep_interp_standalone`); `%?`, `%??`, `%0`, `%1`, `%{1:3}`, `%-1` (the
inverse condition code) and the like are substituted inside bodies.

### The directives (`prep_handle_directive`)

| Group | Directives |
| --- | --- |
| single-line macros | `%define %idefine %xdefine %ixdefine %undef %assign %iassign %defstr %idefstr %deftok %strcat %strlen %substr %defalias %idefalias %undefalias %aliases` |
| multi-line macros | `%macro %imacro %rmacro %irmacro %endmacro %unmacro %exitmacro %rotate` (rotate.s) |
| conditions | `%if %ifn %elif %elifn %else %endif` and every test: `def`, `macro`, `idn` / `idni`, `num`, `str`, `id`, `token`, `empty`, `ctx`, `env`, `defalias` — each with its `n` and `elif` forms |
| repetition | `%rep %endrep %exitrep` |
| files | `%include %depend %pathsearch` (paths.s), `incbin` is the parser's |
| contexts | `%push %pop %repl` (`%$name` local to the context) |
| stack frames | `%stacksize %arg %local` |
| messages | `%error %warning %fatal` |
| others | `%line %use %pragma %clear` |

`%use` packages: `altreg` (r0-r7 names), `smartalign` (long NOPs for
`align`, optimize/align.s), `fp` (NASM's float macros), `ifunc`, `masm`
(MASM's syntax, frontend/syntax/masm).

### Functions inside expressions (`prep_function`)

NASM 3's `%abs %cond %count %eval %hex %num %sel %str %strcat %strlen
%substr %tok`, the `%is...` tests (`%isdef %isnum %isstr %isid %isempty
%istoken` and their `n` forms) and `%map` / `%mapi` / `%mapn`: each reads
its arguments (the `fn_*` helpers) and puts its result tokens in place.

### Conditions

A stack of levels (`prep_cond_enter`, `prep_cond_branch`,
`prep_cond_never`): once one branch of a level is taken every later one
is skipped; a level whose condition cannot be worked out (a label not
defined yet) is NASM's "never". Expressions are evaluated by the parser's
evaluator (`parser_evaluate_pp`), which keeps track of label differences
for the second pass (core/known.s).

### Recording

While a statement's operand is read, the tokens handed out can be
recorded (`prep_rec_begin` / `prep_rec_end`): the parser keeps the
expression text for a value that has to be worked out later (an `equ` of
something not yet defined, a `times` count).

### Predefined macros (`prep_predefine`)

`__NASM_MAJOR__`, `__NASM_MINOR__`, `__NASM_SUBMINOR__`,
`__NASM_PATCHLEVEL__`, `__NASM_VER__`, `__NASM_VERSION_ID__` (utasm answers
as NASM 3.01), `__UTASM__`, `__OUTPUT_FORMAT__`, `__BITS__`, `__FILE__` /
`__LINE__` (dynamic), `__SECT__`, `__PASS__`, the time of assembly
(`__DATE__`, `__TIME__`, `__DATE_NUM__`, `__TIME_NUM__`, their `__UTC_*`
forms, `__POSIX_TIME__`: lib/time.s) — each also as NASM's `__?NAME?__`.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `macro.s` | 14,261 | the whole preprocessor: the token loop, every directive above, macro definition and expansion, conditions, `%rep`, contexts, functions, predefined macros, recording, `-E` output (`prep_dump`), the error reporting at the right line (`prep_error_take`) |
| `paths.s` | 322 | include search paths (`-I`) and dependencies: `incpath_open` tries the name as written, then each `-I` directory; every file opened is recorded for `-M` (`deps_add`, `deps_write`) |
| `rotate.s` | 121 | `%rotate n`: the current macro call's arguments moved n places |

`macro.s` is the largest file after the parser; splitting it (directives,
expansion, conditions, functions) is a planned refactor that does not
change what it does.

## Entry points

| Symbol | Used by |
| --- | --- |
| `prep_init`, `prep_predefine`, `prep_dump`, `prep_error_take` | main/utasm.s |
| `preprocessor_next_token`, `_peek_token`, `_putback_token`, `_unread_token` | frontend/syntax (every token the parser reads) |
| `prep_push_buffer` | frontend/syntax (MASM, GNU, AT&T layers), main/utasm.s (`-p`, `--before`) |
| `prep_rec_*`, `prep_noexpand`, `prep_skip_*_block` | frontend/syntax |
| `incpath_open`, `incpath_add`, `deps_add`, `deps_write` | frontend/syntax (`incbin`), main/ (`-I`, `-M`) |

## Depends on

frontend/lexer (tokens), frontend/syntax (expression evaluation), lib/
(strings, the arena, time), diag/ (messages), platform/ (files),
semantic/ (symbols), object/ (the listing's expansion lines).

## Status

Complete: NASM 3.01's preprocessor, compared against NASM itself. Every
fixed limit is gone (macro parameters, nesting depth, line length grow as
needed).

## Tests

In `tests/compat/run_all.py`: *bin probes* and *listings* (the listing
shows each expansion line, `<1>` `<2>` ...), *limits* (100-parameter
macros, deep nesting, long lines), *command line* (`-D`, `-U`, `-p`,
`--before`, `-E`, `-M*`), *diagnostics* (`%error`, the line an error in a
macro is reported at), *warnings*; and NASM's own test corpus
(`docs/dev/tests.md`).
