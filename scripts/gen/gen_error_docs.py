#!/usr/bin/env python3
"""
gen_error_docs.py - regenerate docs/user/errors.md from the source

Every error utasm can report and every warning class, exactly as utasm
prints them, read from:

  src/include/constant.inc   the EXIT_* codes (number, meaning) and the
                             WC_* warning classes (meaning)
  src/diag/codes.s           code_table: each code's message, and the form
                             that names its subject (^ = the subject)
  src/diag/warnings.s        each class's name and whether it is on (and an
                             error) by default

so the reference cannot drift from what utasm says. Rerun after adding or
changing an error or a warning:

    python3 scripts/gen/gen_error_docs.py           regenerate
    python3 scripts/gen/gen_error_docs.py --check   fail if out of date
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONST = os.path.join(ROOT, "src", "include", "constant.inc")
CODES = os.path.join(ROOT, "src", "diag", "codes.s")
WARN = os.path.join(ROOT, "src", "diag", "warnings.s")
DST = os.path.join(ROOT, "docs", "user", "errors.md")

# not reported as source errors (no message): success, an alias, the test
# harness's QEMU statuses, the status of a fatal stop
SKIP = {"EXIT_OK", "EXIT_USAGE", "EXIT_QEMU_404", "EXIT_QEMU_FAIL", "EXIT_FATAL"}
FATAL = {"EXIT_OOM", "EXIT_IO_ERROR", "EXIT_INTERNAL", "EXIT_ASSERTION", "EXIT_MACRO_RECURSION",
         "EXIT_FILE_NOT_FOUND", "EXIT_FILE_PERM", "EXIT_FILE_READ", "EXIT_FILE_WRITE",
         "EXIT_INVALID_FORMAT"}                    # main/utasm.s rc_fatal


# the groups the reference is in, by what the error is about (first match)
GROUPS = [
    ("Files and the command line", lambda n: n.startswith("EXIT_FILE_") or n in (
        "EXIT_ERROR", "EXIT_OOM", "EXIT_IO_ERROR", "EXIT_SIGNAL", "EXIT_INVALID_FORMAT",
        "EXIT_INPUT_OPEN", "EXIT_OUT_CREATE", "EXIT_ELF_WRITE", "EXIT_BIN_WRITE")),
    ("utasm itself", lambda n: n in (
        "EXIT_INTERNAL", "EXIT_ASSERTION", "EXIT_ASSERT", "EXIT_UNREACHABLE", "EXIT_NOT_IMPLEMENTED",
        "EXIT_KNOWN_RERUN")),
    ("The preprocessor and macros", lambda n: n.startswith(("EXIT_INC_", "EXIT_MACRO_")) or n in (
        "EXIT_DEFINE", "EXIT_COND_DEPTH", "EXIT_CTX_DEPTH", "EXIT_USE_PACKAGE", "EXIT_NOT_DEFINING",
        "EXIT_NO_REP", "EXIT_UNDEF_BEFORE", "EXIT_PP_NONCONST", "EXIT_BRACKET_UNKNOWN")),
    ("Instructions and operands", lambda n: n.startswith(("EXIT_EA_", "EXIT_CPU_")) or n in (
        "EXIT_ENCODER_ERROR", "EXIT_UNKNOWN_INSTR", "EXIT_INVALID_OPERAND", "EXIT_INVALID_REG",
        "EXIT_INVALID_IMM", "EXIT_INVALID_ADDR", "EXIT_ENCODE_FAIL", "EXIT_IMM_RANGE",
        "EXIT_UNSUPPORTED_INSTR", "EXIT_BITS_MODE", "EXIT_NON64_OPERANDS", "EXIT_REG_SIZE",
        "EXIT_NO_SIZE", "EXIT_SIZE_MISMATCH", "EXIT_DEST_IS_SOURCE", "EXIT_TMM_SAME",
        "EXIT_GATHER_SAME", "EXIT_VSIB_NO_MASK", "EXIT_MASK_REFUSED", "EXIT_BITS32_CPU",
        "EXIT_BITS64_CPU")),
    ("Expressions and symbols", lambda n: n.startswith("EXIT_NONSCALAR_") or n in (
        "EXIT_PARSER_ERROR", "EXIT_UNEXPECTED_TOKEN", "EXIT_UNEXPECTED_EOF", "EXIT_EXPR_TOO_DEEP",
        "EXIT_INVALID_EXPR", "EXIT_NOT_SIMPLE", "EXIT_UNDEF_SYMBOL", "EXIT_DUP_SYMBOL",
        "EXIT_SYMBOL_RANGE", "EXIT_CIRCULAR_REF", "EXIT_ILOG2", "EXIT_SYM_TYPE", "EXIT_EQU_FORWARD")),
    ("Directives, data and sections", lambda n: n.startswith(("EXIT_ALIGN_", "EXIT_TIMES_", "EXIT_RES_")) or n in (
        "EXIT_INVALID_SECTION_FLAGS", "EXIT_STRUCT_BOUNDS", "EXIT_UNKNOWN_DIRECTIVE",
        "EXIT_SECTION_SIZE", "EXIT_ORG_BACKWARDS", "EXIT_MERGE_ENTSIZE", "EXIT_POPSECTION",
        "EXIT_NOT_STRUC", "EXIT_FIELD_SIZE", "EXIT_INVALID_SECTION", "EXIT_SECTION_OVERLAP")),
    ("Relocations, linking and output formats", lambda n: n.startswith((
        "EXIT_COFF_", "EXIT_BIN_", "EXIT_SEG_", "EXIT_GOTOFF_", "EXIT_UBF_", "EXIT_LD_SCRIPT_")) or n in (
        "EXIT_LINKER_ERROR", "EXIT_OFFSET_RANGE", "EXIT_RELOC_ERROR", "EXIT_UNDEF_REF",
        "EXIT_MULTI_DEF", "EXIT_WRT_UNSUPPORTED", "EXIT_FAR_NOT_RELOC")),
    ("Debug information (.cfi_*, .file / .loc)", lambda n: n.startswith(("EXIT_CFI_", "EXIT_LINE_"))),
    ("GNU as and AT&T syntax", lambda n: n.startswith("EXIT_GAS_") or n == "EXIT_ATT_SYNTAX"),
    ("MASM syntax (%use masm)", lambda n: n.startswith("EXIT_MASM_") or n == "EXIT_INVOKE_CLOBBER"),
    ("fasm syntax", lambda n: n in ("EXIT_VIRTUAL_OPEN", "EXIT_LOAD_RANGE", "EXIT_LOAD_LATER", "EXIT_FASM_FORMAT")),
    ("Procs, namespaces and modules", lambda n: n.startswith(("EXIT_PROC_", "EXIT_NS_"))),
]


def group_of(name):
    for title, test in GROUPS:
        if test(name):
            return title
    sys.exit("gen_error_docs.py: %s is in no group - add it to GROUPS" % name)


def code(s):
    """s as a Markdown code span (a backtick inside: a double-backtick span)"""
    s = s.replace("|", "\\|")
    return "`` %s ``" % s if "`" in s else "`%s`" % s


def db_string(rest):
    """the text of a NASM db line's operands (strings and byte values)"""
    out, i = [], 0
    for m in re.finditer(r'"([^"]*)"|\'([^\']*)\'|`([^`]*)`|(\d+|0x[0-9a-fA-F]+)', rest.split(";")[0]):
        if m.group(4) is not None:
            v = int(m.group(4), 0)
            if v == 0:
                break
            out.append(chr(v))
        else:
            out.append(next(g for g in m.groups()[:3] if g is not None))
    return "".join(out)


def read():
    c = open(CONST, encoding="utf-8").read()
    i = c.index("; EXIT CODES")
    j = c.index("\n; ====", c.index("%define EXIT_OK"))
    exits, group = [], "General"
    for line in c[i:j].split("\n"):
        m = re.match(r"%define (EXIT_\w+)\s+(\d+)\s*(?:;\s*(.*))?$", line)
        if m:
            exits.append((m.group(1), int(m.group(2)), (m.group(3) or "").strip(), group))
        elif line.startswith("; ") and not line.startswith("; ===") and exits:
            s = line[2:].strip()
            if s and not s.startswith("-") and len(s) < 70:
                group = s.rstrip(":")
    classes = [(m.group(1), int(m.group(2)), m.group(3).strip())
               for m in re.finditer(r"^%define (WC_\w+)\s+(\d+)\s*;\s*(.*)$", c, re.M)]
    t = open(CODES, encoding="utf-8").read()
    strings = {m.group(1): db_string(m.group(2))
               for m in re.finditer(r"^(\w+):\s*db\s+(.*)$", t, re.M)}
    table = {}
    for m in re.finditer(r"^\s*code_msg\s+(EXIT_\w+),\s*(\w+)(?:,\s*(\w+))?", t, re.M):
        table[m.group(1)] = (strings[m.group(2)], strings.get(m.group(3)) if m.group(3) else None)
    w = open(WARN, encoding="utf-8").read()
    state = [int(x) for x in re.findall(r"^\s*db (\d)\s*; WC_", w[w.index("warn_state:"):w.index("warn_names:")], re.M)]
    order = re.findall(r"wn_\w+", w[w.index("warn_names:"):w.index("wn_other:")])
    names = {m.group(1): db_string(m.group(2)) for m in re.finditer(r"^(wn_\w+):\s*db\s+(.*)$", w, re.M)}
    wclasses = []
    for (wc, num, desc), label, st in zip(sorted(classes, key=lambda x: x[1]), order, state):
        wclasses.append((names[label], desc.split(":", 1)[1].strip() if ":" in desc else "", st))
    return exits, table, wclasses


INTRO = """# utasm — Error and Warning Reference

> Generated by `scripts/gen/gen_error_docs.py` from the source
> (`src/include/constant.inc`, `src/diag/codes.s`, `src/diag/warnings.s`).
> Do not edit by hand: change the source and rerun the script.

Every message below is exactly what utasm prints.

---

## How a message looks

utasm writes NASM's format, one line per message, on stderr, at the line of
the statement it is about:

```
prog.s:12: error: invalid combination of opcode and operands
prog.s:4: warning: label alone on a line without a colon might be in error [-w+label-orphan]
prog.s:9: fatal: unable to open `inc.s': no such file
```

- **error** — the statement is not assembled. utasm undoes it, reads on, and
  reports every error in the file (stopping after 100: `too many errors
  (100), stopping`). No output file is written, and utasm exits with a
  non-zero status (*Exit status*, below).
- **warning** — assembly goes on. Each ends with its class (`[-w+zeroing]`);
  see *Warnings* below for turning them on and off or into errors.
- **fatal** — assembly stops at once: utasm cannot read on (a missing file,
  out of memory, an internal error, `%fatal`).

When the statement came from a macro, a second line shows where:

```
prog.s:20: error: symbol `cnt' not defined
prog.s:4: ... from macro `count' defined here
```

### On a terminal

On a terminal (or with `--color`) utasm also prints the line, marks the
place, and explains what it can:

```
prog.s:12: error: invalid combination of opcode and operands
    12 |     mov al, rax
       |     ^~~~~~~~~~~
note: `al' is an 8-bit register, `rax' a 64-bit register
note: the operands' sizes differ: 8 and 64 bits

prog.s:7: error: symbol `counter' not defined
     7 | mov eax, [counter]
       |           ^~~~~~~
hint: did you mean 'count'?
```

The mark is on the name the message is about, else where the parser
stopped, else the statement. `hint:` lines suggest the closest known
instruction or symbol. Piped into a file or another program, the output is
the plain form (with the `hint:` and `note:` lines). `--no-color`,
`NO_COLOR` or `TERM=dumb` force the plain form.

### Other formats

| Option | Output |
| --- | --- |
| `-X gnu` (default) | `file:line: error: message` |
| `-X vc` | `file(line) : error: message` |
| `-X json` | one JSON object per message on stderr: `{"severity":"error","file":"a.s","line":3,"column":7,"message":"..."}` (warnings with `"flag"`) — for editors and build tools |
| `-s` / `-Z file` | messages on stdout / into a file |
| `--lsp` | the same messages to an editor, as LSP diagnostics |

### Messages that name something

Many messages name what they are about — a symbol, a file, a macro, a
section. The tables give both forms: the plain one, and the one with the
name (the name shown as `NAME`).

---
"""


def render(exits, table, wclasses):
    out = [INTRO]
    out.append("## Errors\n")
    out.append("Each error has a code inside utasm (`EXIT_*`, its number below); the\n"
               "message is what you see. The exit status is not the code but the kind of\n"
               "the first failure: see *Exit status* at the end.\n")
    rows = [(group_of(n), v, n, d) for n, v, d, _ in exits if n not in SKIP and n in table]
    for title, _ in GROUPS:
        mine = sorted(r for r in rows if r[0] == title)
        if not mine:
            continue
        out.append("\n### %s\n" % title)
        out.append("| Code | Message | Naming its subject | Meaning |")
        out.append("| --- | --- | --- | --- |")
        for _, num, name, desc in mine:
            plain, named = table[name]
            named_txt = code(named.replace("^", "NAME")) if named else ""
            kind = " **(fatal)**" if name in FATAL else ""
            out.append("| %d | %s%s | %s | %s (`%s`) |" % (num, code(plain), kind, named_txt,
                                                           desc.replace("|", "\\|"), name))
    out.append("""
---

## Warnings

Each warning belongs to a class and ends with it: `[-w+CLASS]`.

| Option | Effect |
| --- | --- |
| `-w+CLASS` / `-WCLASS` | turn a class on |
| `-w-CLASS` / `-Wno-CLASS` | turn it off |
| `-w+all` / `-w-all` | every class |
| `-w+error=CLASS` / `-Werror=CLASS` | that class is an error (`error: ... [-w+error=CLASS]`) |
| `-Werror` / `-w+error` | every warning is an error |

A warning made an error fails the assembly at the end (no output file),
after the whole source is read, as `%error` does.

| Class | On by default | What it warns about |
| --- | --- | --- |""")
    for nm, desc, st in wclasses:
        default = "yes, as an error" if st == 3 else ("yes" if st & 1 else "no")
        out.append("| `%s` | %s | %s |" % (nm, default, desc.replace("|", "\\|")))
    out.append("""
`pie`, `slash-comment` and the `proc-*` classes are utasm's own; the others
are NASM's, with NASM's names and defaults.

---

## Exit status

The kind of the first failure:

| Status | When |
| --- | --- |
| 0 | assembled, the output written (warnings do not change it) |
| 1 | the command line: an unknown option or value (`utasm --format nope`) |
| 2 | out of memory at start-up |
| 3 | the source file cannot be opened or read |
| 4 | a statement could not be assembled: the preprocessor (a missing include, `%error`, `%fatal`), a directive, a label, an expression; and a warning made an error by `-Werror` |
| 5 | an instruction could not be encoded |
| 6 | the end of assembly: an undefined symbol, a relocation the format cannot express, overlapping sections |
| 9 | utasm itself crashed (an internal error at the statement being read) |

Errors found while reading the source come first: a source with both an
operand error and an undefined symbol reports the operand error (status
5); undefined symbols are only checked once the whole source has been
read without errors.

---

*Adding an error or a warning: `docs/dev/dev_guide.md`.*
""")
    return "\n".join(out)


def main():
    text = render(*read())
    if "--check" in sys.argv:
        cur = open(DST, encoding="utf-8").read() if os.path.exists(DST) else ""
        if cur != text:
            sys.exit("docs/user/errors.md is out of date; run scripts/gen/gen_error_docs.py")
        return
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote", os.path.relpath(DST, ROOT))


if __name__ == "__main__":
    main()
