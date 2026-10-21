# frontend/ — from source text to statements

The front end turns the source into what the encoders consume, one
statement at a time, in three stages that pull from each other:

```
 source bytes ──▶ lexer/ ──tokens──▶ preproc/ ──tokens──▶ syntax/ ──▶ INST (an instruction)
                  (characters)       (%define, %macro,     (statements: labels,      │
                                      %if, %rep, %include) directives, data, equ,   ▼
                                                            instructions)        encode/
```

- **[lexer/](lexer/README.md)** reads characters and produces tokens
  (identifiers, numbers, strings, punctuation, newlines). One lexer per
  file; an `%include` gets its own.
- **[preproc/](preproc/README.md)** sits between the lexer and the parser:
  it executes `%` directives, expands macros, and hands the parser the
  tokens of the program as NASM's preprocessor would produce them.
- **[syntax/](syntax/README.md)** reads statements from those tokens. The
  NASM parser (`syntax/nasm/parser.s`) is the main one; MASM's, fasm's and
  GNU as's syntaxes are layers that turn their constructs into what the
  NASM parser understands.

The parser **pulls**: `parser_parse_instruction` asks the preprocessor for
the next token (`preprocessor_next_token`), which asks the lexer when it
has nothing expanded to give. So there is no token list for the whole
file — each statement is read, handled and forgotten before the next.

## How the stages talk

| Call | From → to | What |
| --- | --- | --- |
| `lexer_next`, `lexer_peek` | preproc → lexer | the next raw token of the current file |
| `preprocessor_next_token`, `_peek_token`, `_putback_token` | syntax → preproc | the next token after expansion |
| `prep_push_buffer` | syntax → preproc | read some text as if it were the next lines (MASM's and GNU's layers rewrite a statement and push the rewrite) |
| `parser_evaluate_pp` | preproc → syntax | evaluate an expression for `%if`, `%assign`, `%rep` |
| `symbol_find`, `symbol_add` | all → semantic/ | names |

## Status and tests

See each folder's README. Tested by nearly every suite in
`tests/compat/run_all.py`; most directly *data forms*, *expressions*,
*limits*, *diagnostics*, *listings* (which show the preprocessor's output
line by line) and the syntax suites (*masm features*, *fasm features*,
*gas*, *att*).
