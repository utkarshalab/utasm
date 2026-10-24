## UPK packages (`-f upk`)

A UPK package is how software reaches Utkarsha OS: one signed file holding a
program's UBF binaries ([ubf.md](ubf.md)), its resources and default
configuration, and a plain-text manifest. The format is specified in the OS
repository's `docs/UPK_SPEC.md`; this page is what utasm writes.

```sh
utasm --upk-keygen publisher.key            # once: a signing key
utasm -f upk manifest -o calculator.upk \
      --upk-add main=build/main \
      --upk-add res/icon.png=res/icon.png \
      --upk-add conf/calculator=conf/defaults \
      --upk-sign publisher.key
```

With `-f upk` the input is the manifest, not a source: nothing is assembled.
Without `-o`, the package is the manifest's name with `.upk`.

### The manifest

UTF-8 text, one `key = value` per line; `#` starts a comment; blank lines
are skipped. Each key appears at most once, and an unknown key is an error —
a misspelt key would otherwise drop a requirement without a word.

```
# the calculator
name    = calculator
version = 1.2.0
kind    = app
title   = Calculator
entry   = main
```

| Key | Required | Checked |
| --- | --- | --- |
| `name` | yes | 1–32 of `a-z 0-9 -`; not `lib`, `cmd` or `model` |
| `version` | yes | `major.minor.patch`, digits |
| `kind` | yes | `app`, `lib` or `cmd` |
| `entry` | `app`, `cmd` | the path of one of the added files, and that file a UBF image; not allowed for a `lib` |
| `title`, `publisher`, `capabilities`, `models`, `depends`, `min_os` | no | stored as written |

### Files

`--upk-add PATH=FILE` adds FILE under PATH (repeatable, up to 256). A PATH
is parts of `a-z 0-9 . _ -` joined by `/`, none empty, `.` or `..`, and each
PATH once. Each file's kind follows from its path and whether it is a UBF
image:

| File | Kind |
| --- | --- |
| the `entry` | 1 main binary (3 for a `cmd`) |
| any other UBF image | 2 library |
| `conf/...` | 5 default configuration |
| `model/...` | 6 model data |
| anything else | 4 resource |

### Signing

`--upk-sign KEY` signs the package with Ed25519: the signed message is the
SHA-256 of the header (its signature field zero), the entry table, the
string table and the manifest. Each entry carries its file's SHA-256, so the
signature covers every byte of the package. The header names the signer by
the SHA-256 of its public key; the OS accepts the package only when that key
is in its trust store.

A key file is either the 32-byte seed or the 64 bytes `--upk-keygen` writes
(seed, then public key, which must match). Without `--upk-sign` the package
is unsigned (flags bit 0 clear).

`utasm --upk-keygen FILE` makes a key with the system's random source: FILE
(64 bytes, mode 0600) and FILE.pub (the 32-byte public key, to give the OS),
and prints the public key in hex.

The Ed25519 and SHA-512 code is Utkarsha OS's own (`src/lib/ed25519/`,
copied from its `lib/crypto`), so a package is signed by the same arithmetic
the OS checks it with.

### Layout

All fields are little-endian. A 144-byte header, the entry table (64 bytes
per file), the string table (the paths, NUL-terminated), the manifest, then
each file's bytes on a 16-byte boundary.

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 4 | magic `"UPK\0"` (0x004B5055) |
| 0x04 | 2 | version: 1 |
| 0x06 | 2 | header size: 144 |
| 0x08 | 4 | flags; bit 0: signed |
| 0x0C | 4 | entry count |
| 0x10 | 4 | entry table offset |
| 0x14 | 4 | string table offset |
| 0x18 | 4 | string table size |
| 0x1C | 4 | manifest offset |
| 0x20 | 4 | manifest size (at most 64 KiB) |
| 0x28 | 8 | file size |
| 0x30 | 32 | signer: SHA-256 of the Ed25519 public key |
| 0x50 | 64 | Ed25519 signature |

Entry: path (string table offset) and kind (4 bytes each), the file's offset
and size (8 each), its SHA-256 (32), 8 reserved bytes.

### Checks

`tests/compat/run_all.py` (the *upk packages* suite) makes a key, packs a
UBF program, a resource and a configuration file, and checks the result with
`tests/compat/upk_check.py`, which verifies the layout, every digest and the
signature with a pure-Python Ed25519 written from RFC 8032, not with utasm's
code. It checks that a changed file byte and a changed manifest byte are
both caught, that an unsigned package builds, and that each malformed input
above is refused.
