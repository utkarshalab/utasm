# Security

utasm reads untrusted input: source files, include files, and the objects
and raw files given to `--disasm` / `--inspect`. A crash, hang, out-of-bounds
read or write, or an include that escapes where it should not, on any input,
is a bug we treat as a security issue.

## Reporting

Please report privately, not in a public issue: open a GitHub security
advisory on this repository (Security → Report a vulnerability). Include
the input that triggers it, the command line, and the utasm commit
(`git rev-parse HEAD`).

You will get an answer within a few days. A fix lands with a regression
case in `tests/compat/` (the robustness suite), and the advisory is
published once the fix is on `main`.

## Supported versions

Only `main` is supported until the first release.
