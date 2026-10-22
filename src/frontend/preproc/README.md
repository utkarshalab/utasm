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
for the second pass (core/known.s). What follows the expression on its
line - after `%if`, `%ifn`, `%elif`, `%assign`, `%rep` - is dropped
(`prep_trailing_expr`), with NASM's "trailing garbage after expression
ignored" [`pp-trailing`] (none for `%elif`, as NASM); it used to go on to
the assembler as a statement ("%if 1 x" defined a label `x`).

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
| `macro.s` | 772 | `prep_init`, the token interface (`preprocessor_next_token`, peek / unread / putback), `%pragma`, placing errors (`prep_error_take`); the rest of it in the `macro/` parts, %included in this order: |
| `macro/tokens.inc` | 1,321 | prep_internal_next: the token loop (expansion, directives, single-line macros), the input buffers |
| `macro/expand.inc` | 1,461 | multi-line macro expansion: starting, the next token, popping |
| `macro/directives.inc` | 902 | prep_handle_directive (the % directive dispatch), %include |
| `macro/tables.inc` | 595 | the directive names and the preprocessor's other string tables |
| `macro/cond.inc` | 831 | entering and branching conditionals, %ifidn / %ifidni, %elif, %error; constant text substitution, file pasting |
| `macro/contexts.inc` | 724 | raw tokens, macro labels, %unmacro, %strlen, %substr, %push / %pop |
| `macro/interp.inc` | 804 | prep_resolve_interp: %[...], %+, context-local and parameter interpolation |
| `macro/assign.inc` | 808 | %assign, %undef, predefined and dynamic macros (__LINE__ ...), %ifnidn, %warning, %exitrep, %exitmacro, built-in macros |
| `macro/tests.inc` | 1,225 | %ifdef-style tests, %defstr, %iassign, %repl, %getenv, %stacksize, %arg / %local frames, condition-code inverses |
| `macro/functions.inc` | 1,702 | the preprocessor functions (%sel, %cond, %eval, %str, %num, %hex ...): fn_* |
| `macro/files.inc` | 545 | %depend, %pathsearch, %line, %use, %clear, %strtok |
| `macro/define.inc` | 603 | %define / %xdefine: parameters, marks, storing |
| `macro/cond_if.inc` | 610 | %if / %else / %endif, skipping macro and %rep blocks, counts |
| `macro/macro_def.inc` | 752 | %macro definitions: recording bodies, capture slots, token buffers |
| `macro/rep_state.inc` | 794 | %rep, %defalias and aliases, preprocessor symbols, error lines; the preprocessor's state |
| `paths.s` | 322 | include search paths (`-I`) and dependencies: `incpath_open` tries the name as written, then each `-I` directory; every file opened is recorded for `-M` (`deps_add`, `deps_write`) |
| `rotate.s` | 121 | `%rotate n`: the current macro call's arguments moved n places |

`macro.s` is one object: its parts in `macro/` are %included in order,
cut where its functions were (the object is the same, byte for byte). A
part is not assembled alone; `make` rebuilds `macro.s` when one changes.

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
needed); what is left are NASM's guards against a runaway: 10,000 macro
calls open (`MAX_MACRO_DEPTH`), 10,000,000 tokens in their arguments
(`MAX_MACRO_ARGS_TOKENS`, NASM's macro-tokens: `prep_expand_start` adds a
call's, `prep_expand_pop` takes them off - "r %1-1" calling itself took 9 s
and 2 GB to reach the depth limit), `--limit-rep` (1,000,000), and the
parser's `--limit-eval` (8192 terms in an expression).

## Tests

In `tests/compat/run_all.py`: *bin probes* and *listings* (the listing
shows each expansion line, `<1>` `<2>` ...), *limits* (100-parameter
macros, deep nesting, long lines), *command line* (`-D`, `-U`, `-p`,
`--before`, `-E`, `-M*`), *diagnostics* (`%error`, the line an error in a
macro is reported at), *warnings*; and NASM's own test corpus
(`docs/dev/tests.md`).
