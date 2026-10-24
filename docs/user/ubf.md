## UBF program images (`-f ubf`)

UBF — the Utkarsha Binary Format — is the file every Utkarsha OS program
outside the kernel image is: an application (`app/<app>/main`), a command or
a shared library. The kernel's program loader reads it; a UPK package ships
it. The format itself is specified in the OS repository's `docs/UBF_SPEC.md`;
this page is what utasm writes.

```sh
utasm -f ubf app.s -o main        # an application (it has _start or main)
utasm -f ubf lib.s -o libfoo.ubf  # a library (neither)
```

### What goes where

Utkarsha OS runs every task in one address space, so a program is loaded
wherever there is room. utasm therefore builds a relocatable image:

| Source | In the image |
| --- | --- |
| executable sections (`.text`, ...) | the text segment, `R-X` |
| read-only sections (`.rodata`, ...) | the rodata segment, `R--` |
| writable sections (`.data`, ...) | the data segment, `RW-` |
| `.bss`, `nobits` | the bss segment, `RW-`, no bytes in the file |
| debug and note sections | left out |

Each segment starts on a 4096-byte page; no page is both writable and
executable.

- **Imports.** Each `extern` that the code uses becomes an import: an 8-byte
  slot at the end of rodata, which the loader fills with the address it
  resolves the name to, and a stub `jmp [rel slot]` (`FF 25`, padded to 8
  bytes with `int3`) at the end of text. `call name` and `jmp name` go
  through the stub; `mov rax, [rel name wrt ..gotpcrel]` reads the slot
  directly. Any other use of an import — `dq name`, `mov rax, name` — is an
  error.
- **Exports.** Every `global` (or weak) symbol defined in a loaded section.
- **Relocations.** `dq label` and `mov rax, label` (a 64-bit absolute
  address) are written for load address 0 and listed as `ABS64` entries,
  which the loader adds its load address to. RIP-relative references are
  resolved by utasm and need no entry. A 32-, 16- or 8-bit absolute address
  of a label is an error: the label moves with the image. Write `default rel`.
- **Entry point.** `_start`, or `main` when there is no `_start`, defined in
  an executable section. With neither, the image is a library (kind 2, no
  entry point).

### Layout

All fields are little-endian. The file is: a 128-byte header, the segment
table (32 bytes per segment), the relocation table (8 bytes per entry), the
import table (16), the export table (16), the string table (names, each
NUL-terminated, the first byte of the table a NUL), then each segment's
bytes on a 16-byte boundary.

Header:

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 4 | magic `"UBF\0"` (0x00464255) |
| 0x04 | 2 | version: 1 |
| 0x06 | 2 | header size: 128 |
| 0x08 | 2 | kind: 1 application, 2 library |
| 0x0A | 2 | arch: 1 x86-64 |
| 0x0C | 4 | flags; bit 0: has an entry point |
| 0x10 | 8 | image size in memory, a multiple of 4096 |
| 0x18 | 8 | entry point, an offset in the image |
| 0x20 | 4 | stack size wanted (0: the system's default) |
| 0x24 | 4 | segment count |
| 0x28 | 4 | segment table offset |
| 0x2C | 4 | relocation table offset |
| 0x30 | 4 | relocation count |
| 0x34 | 4 | import table offset |
| 0x38 | 4 | import count |
| 0x3C | 4 | export table offset |
| 0x40 | 4 | export count |
| 0x44 | 4 | string table offset |
| 0x48 | 4 | string table size |
| 0x4C | 4 | CPU features needed (utasm writes 0) |
| 0x50 | 4 | file size |
| 0x58 | 32 | SHA-256 of the whole file, taken with this field zero |

Segment entry: type (1 text, 2 rodata, 3 data, 4 bss), protection (bit 0
read, 1 write, 2 execute), file offset, file size (4 bytes each), offset in
the image, size in memory (8 bytes each).

Relocation entry: offset in the image, type (1 `ABS64`).

Import entry: name (string table offset), FNV-1a 32-bit hash of the name,
the slot's offset in the image, flags (bit 0: weak).

Export entry: name, FNV-1a hash (4 bytes each), offset in the image (8).

### Checks

`tests/compat/run_all.py` (the *ubf images* suite) builds a program with
two imports, an `ABS64` pointer, data and bss, and checks every header and
table field, the SHA-256, the page layout and the stubs. It then loads the
image with `tests/compat/ubf_run.py` — the loader's steps on the host, with
the imports resolved to the C library's `strlen` and `write` — runs it and
checks what it prints and returns. It also builds a library, and checks that
the two errors above are reported.
