# tools/lsp/ — the language server (`--lsp`)

The Language Server Protocol over stdin / stdout, for an editor's
diagnostics as one types. Point the editor's LSP client at
`utasm --lsp`.

## How it works

Messages are JSON-RPC, each after its `Content-Length: N` header.

| Method | What happens |
| --- | --- |
| `initialize` | the capabilities: the whole document sent on each change (`textDocumentSync` 1) |
| `textDocument/didOpen`, `didChange`, `didSave` | the document is assembled and its messages published (`textDocument/publishDiagnostics`) |
| `textDocument/didClose` | its messages cleared |
| `shutdown`, `exit` | as the protocol says |
| anything else | answered "method not found" |

Each document is assembled by **utasm itself, run anew**
(`/proc/self/exe -X json -f elf64 -I <its directory> -o /dev/null`) on a
copy of the editor's text in `/tmp` (saved or not). Every message comes
back as JSON (diag/json.s); its line and column become the diagnostic's
range (0-based), its severity an error (1), a warning (2) or a note (3).
Running a fresh process per change keeps the server simple and immune to
state left over from the last assembly.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `lsp.s` | 1,366 | `lsp_main`: the message loop, the JSON reading and writing it needs, running utasm, publishing diagnostics |

## Entry points

| Symbol | Used by |
| --- | --- |
| `lsp_main` | main/utasm.s (`--lsp`) |

## Depends on

lib/ (strings), main/ (the arguments); at run time, utasm's own `-X json`
output.

## What is left

Diagnostics only. Possible next: hover (an instruction's forms, a
symbol's value), go to definition (labels, macros, includes), document
symbols (labels, procs, namespaces).

## Tests

*lsp server* in `tests/compat/run_all.py` (a session over stdin / stdout).
