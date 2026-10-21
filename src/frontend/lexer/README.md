# frontend/lexer/ — characters to tokens

`lexer.s` turns a source buffer into `TOKEN`s (struc in
`include/type.inc`: kind, flags, value or text, file, line, column,
length). It knows nothing about instructions or directives: a register, a
mnemonic and a label are all identifiers to it; the parser decides.

## How it works

There is one `LEXER` state per open file (the main source and each
`%include`): the buffer (the file is mmapped), the read position, the line and column, and one token of
lookahead (`lexer_peek`).

`lexer_next` skips blanks and comments, then classifies the next character
through a 256-entry table (`lexer_char_props`):

| Input | Token |
| --- | --- |
| space, tab, CR | skipped |
| LF | `TOK_NEWLINE` (statements end at newlines) |
| `;` to the end of the line | skipped (a comment) |
| `[A-Za-z_.?@$][A-Za-z0-9_.?@$#~]*` | `TOK_IDENT` (labels, mnemonics, registers, directives' names) |
| a name followed by `:` | a label definition (marked so) |
| numbers: `123`, `0x1f` / `1fh` / `$1f`, `0b101` / `101b` / `101y`, `0o17` / `17q`, `0d99` / `99t`, `1_000`; C's size suffixes (`1ULL`, `5L`) read and dropped; floats `1.5e3`, `0x1.8p3` | `TOK_NUMBER` / a float (NASM's forms; an integer's value is worked out here, a float's text is kept for `lib/float.s`) |
| `"..."`, `'...'`, `` `...` `` (with C escapes) | `TOK_STRING` |
| `%name`, `%%name`, `%$name`, `%[...]`, `%+` ... | the preprocessor's tokens |
| operators and punctuation | their own kinds: `+ - * / % << >> & ^ ~ ! == != < <= > >= && ? :`, the bar and double bar (or), `[ ] ( ) { } ,` |

An unknown character is an error at its line and column; an unterminated
string is `EXIT_UNEXPECTED_EOF`.

Line numbers step by `lexer_line_step` — 1, or what `%line N+step` set —
so the listing and the diagnostics can report a generated file's original
lines.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `lexer.s` | 2,968 | `lexer_init`, `lexer_next`, `lexer_peek`, the character table, numbers, strings and escapes, `%line` stepping, `lexer_mark_lone` (a word alone on its line, for NASM's orphan-label warning) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `lexer_init` | main/utasm.s (the source), frontend/preproc (each `%include`), link/ (re-reading for messages) |
| `lexer_next`, `lexer_peek` | frontend/preproc |
| `lexer_char_props` | frontend/syntax (GNU's and fasm's word rules) |
| `lexer_line_step`, `lexer_mark_lone` | frontend/preproc |

`lexer_destroy` and `lexer_expect` are defined but unused (lexers live in
the arena and go when utasm exits).

## Depends on

lib/ (strings, numbers), diag/ (the error for a bad character), semantic/
(symbols for `$`-style names).

## Status

Complete for NASM's, MASM's, fasm's and GNU's syntaxes (their
differences are handled in syntax/, not here).

## Tests

*data forms* (every number and string form), *diagnostics* (bad
characters, unterminated strings), *robustness* and the fuzzer
(`tests/compat/fuzz.py`), in `tests/compat/run_all.py`.
