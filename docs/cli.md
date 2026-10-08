## Command-line interface

```
utasm [options] <source.s>
utasm --inspect [--inspect-only <parts>] <file>
utasm --disasm <file>
```

UTASM assembles one source file per invocation. With no output options,
`utasm source.s` targets AMD64 and writes an ELF64 relocatable object named
after the source file (for example, `source.s` becomes `source.o`).

| Option | Meaning |
| --- | --- |
| `-f`, `--format <format>` | Output format: `elf64` (default), `elf32` (or `elf`: an i386 object, `bits 32` by default), `bin`, or `ubf` (a UBF boot image, see [ubf.md](ubf.md)). Non-standalone ELF output is a relocatable object. |
| `-o <file>` | Output path; defaults to a source-derived `.o`, `.bin` or `.ubf` filename. |
| `--ubf-add TYPE=FILE[@ADDR]` | With `-f ubf`: add a component (`initrd`, `dtb`, `config`, `module`, `firmware`) read from FILE, loaded at ADDR. Repeatable, up to 7. |
| `-a`, `-arch`, `--arch <arch>` | Target architecture: `amd64` (default), `aarch64`, or `riscv64`. |
| `--standalone` | Produce a standalone executable and require `_start`. |
| `--profile`, `-P` | Print the assembler's internal performance profile. |
| `--verbose` | Enable verbose diagnostics. |
| `--color`, `--no-color` | The rich diagnostics (the source line, the place marked, color) or NASM's plain lines; by default rich on a terminal. |
| `-Werror` | Treat warnings as errors. |
| `-O0`, `-O1`, `-O2` (`-Ox`) | Jump optimization level; `-O1` is the default (see below). |
| `-I dir`, `-i dir` | Add a directory to the include search path (see [NASM's options](#nasms-options)). |
| `-D name[=value]`, `-U name`, `-p file`, `--before text` | Define, undefine, include or add a line ahead of the source. |
| `-E` | Preprocess only. |
| `-l file` | Write a listing: every source line with its offset and bytes (see [Listings](#listings)). |
| `-g`, `-F dwarf` | DWARF debug information in ELF objects (see [Debug information](#debug-information)). |
| `-M`, `-MD`, `-MF`, `-MT`, `-MQ`, `-MP` | Makefile dependencies. |
| `-w...`, `-W...`, `-X`, `-s`, `-Z file` | Warnings, message style and destination. |
| `--inspect` | Print an existing ELF file instead of assembling (see below). |
| `--inspect-only <parts>` | Inspect only the listed parts; implies `--inspect`. |
| `--disasm` | Disassemble an ELF file's code sections (x86-64; see below). |
| `-h`, `--help` | Print help and exit successfully. |
| `-v`, `--version` | Print the UTASM version and exit successfully. |

The CLI rejects unknown options, missing option values, unknown formats or
architectures, and more than one input file. Formats without an implemented
emitter (for example PE32+ and UPK) are deliberately not accepted.

Examples:

```sh
# Default AMD64 ELF output
utasm hello.s -o hello.o

# Explicit relocatable object
utasm --arch amd64 --format elf64 source.s -o source.o

# Flat binary
utasm -f bin boot.s -o boot.bin

# UBF boot image: the kernel plus a configuration component
utasm -f ubf kernel.s --ubf-add config=boot.cfg@0x200000 -o tattva.ubf

# A self-contained executable, with profiling
utasm --standalone --profile main.s -o main
```

## Standalone executables

`--standalone` writes a static ELF executable instead of an object file; the
program starts at `_start`:

```sh
utasm --standalone hello.s -o hello && ./hello
```

It is loaded at 0x400000. The ELF header, the program headers and `.text`
form one read/execute segment from the start of the file; `.rodata` gets a
read-only segment and `.data` with `.bss` a read/write one, each starting on
a new page. Sections get their addresses before relocations are resolved,
so `lea rsi, [rel msg]` into `.rodata` or `mov rax, [rel counter]` into
`.bss` reach the right place, and the symbol table lists addresses. The file
is created executable (mode 0755).

## Inspecting ELF files

`--inspect` turns utasm into a built-in, readelf-style viewer, so its own
output can be checked without external tools:

```sh
utasm hello.s                   # writes hello.o
utasm --inspect hello.o         # header, sections, segments, symbols, relocations
utasm --inspect-only symbols,relocs hello.o
```

`<parts>` is a comma-separated list of `header`, `sections`, `segments`,
`symbols`, `relocs`, `all` and `disasm`. Unknown or empty names are
rejected. `all` means every part except `disasm`, which can be long.

Any ELF64 little-endian file can be inspected: objects, executables and
shared libraries, from utasm or any other toolchain. The whole file is
validated before anything is printed, so a truncated or corrupt file is
reported instead of crashing the viewer. Unnamed section symbols are shown
with their section's name, and relocation targets read as `symbol + addend`:

```
Relocation section '.rela.data' at offset 0x460 contains 2 entries (applies to '.data'):
  Offset            Info              Type                     Sym. Name + Addend
  0000000000000006  0000000300000001  R_X86_64_64              .data + 0x0
```

On failure utasm prints `utasm: cannot inspect '<file>': <reason>` and exits
with a specific code:

| Exit code | Reason |
| --- | --- |
| 10 | no such file |
| 11 | permission denied |
| 14 | not a valid ELF64 little-endian file (including empty files) |
| 13 | error writing output |

## Disassembling

`--disasm` (or the `disasm` part of `--inspect-only`) prints every
executable section as x86-64 instructions in Intel syntax, in the same style
as `objdump -d -M intel`:

```
Disassembly of section '.text':

0000000000000000 <math_is_pow2>:
  00000000:  31 c0                   xor    eax,eax
  00000002:  48 85 ff                test   rdi,rdi
  00000005:  74 0a                   je     11 <math_is_pow2.done>
  00000007:  48 8d 4f ff             lea    rcx,[rdi-0x1]
```

A symbol that starts at an address gets a label line, and a direct jump or
call shows its target with the nearest symbol at or before it. Like objdump,
decoding restarts at every symbol, so data inside a code section cannot run
into the next function. Bytes it cannot decode print as `(bad)` and are
skipped one at a time.

It decodes the general-purpose instruction set: every prefix, REX, the
one-byte and `0F` opcode maps (arithmetic and logic, moves, shifts,
multiply/divide, jumps and calls, `setcc`/`cmovcc`, bit operations, string
instructions with `rep`, fences, `syscall`, `cpuid`, system instructions and
so on), with 32-bit addressing under a `67` prefix. It also decodes MMX and
SSE through SSE4.2 - the `0F`, `0F 38` and `0F 3A` maps selected by a `66`,
`F3` or `F2` prefix, including AES and `pclmulqdq` - plus `popcnt`, `tzcnt`,
`lzcnt`, `crc32`, `movbe`, `adcx`/`adox`, the SHA instructions,
`cmpxchg16b`, `rdrand`/`rdseed` and `endbr64`; the VEX-encoded AVX, AVX2,
FMA and BMI1/BMI2 instructions (xmm/ymm, three- and four-operand forms,
broadcasts, `vinserti128`/`vextracti128`, permutes, masked moves,
`vzeroupper`, `andn`, `shlx`, `pdep`, `rorx`, ...); x87 floating point
(`fld`/`fstp` with DWORD, QWORD and TBYTE operands, integer and BCD loads and
stores, `st(i)` register forms, `fcomi`/`fcmovcc`, the constants and
transcendental functions, control and status words); and AVX-512:

- the EVEX prefix with xmm/ymm/zmm and registers 16-31, `{k1}` masking and
  `{z}` zeroing, broadcasts (`DWORD BCST [rax]`), rounding control and
  `{sae}`, and the compressed disp8*N displacement;
- AVX-512F/BW/DQ/VL and friends: `vmovdqu8/16/32/64`, `vpternlogd`,
  `vpcmpub` & co. with their predicate names (`vpcmpnequb`), compares and
  tests into mask registers, `vpermi2`/`vpermt2`, narrowing `vpmov*`,
  compress/expand, `vpconflict`, `vplzcnt`, 512-bit FMA, IFMA, VNNI, VAES,
  `vpclmulqdq` and GFNI;
- the mask-register instructions: `kmov`, `kortest`, `ktest`, `kand`/`kor`/
  `kxor`/`knot`, `kadd`, `kunpck` and `kshift`.

It is checked against objdump: on utasm's own 276 object files, a linked
utasm executable and a coverage file of NASM-assembled instruction forms,
every instruction is identical to objdump's output (same bytes, same text).
So is every instruction of these system binaries:

| File | Instructions | Identical |
| --- | --- | --- |
| `libc.so.6` | 349,012 | 100% |
| `libstdc++.so.6` | 340,870 | 100% |
| `python3` | 1,039,681 | 100% |
| `bash` | 199,949 | 100% |
| `libz.so.1` | 19,289 | 100% |
| `libm.so.6` | 128,689 | 99.6% |
| `libcrypto.so.3` | 874,770 | 99.9% |

What remains in the last two is AMD-only FMA4/XOP, the newest SHA512 and
SM3 instructions and a few prefix spellings. Random bytes never crash it.

The opcode tables are generated by `scripts/gen_x86_tables.py` into
`tools/disasm/x86_tables.inc`; rerun the script after changing it
(`--check` verifies the file is current).

## i386 objects (`-f elf32`)

`-f elf32` writes an i386 relocatable object (`ELFCLASS32`, `EM_386`) and
starts in `bits 32`, as NASM's `-f elf32` does:

```sh
utasm -f elf32 prog.s -o prog.o && ld -m elf_i386 prog.o -o prog
```

Relocations are `.rel` sections with the i386 types (`R_386_32`,
`R_386_PC32`, `R_386_PLT32`, `R_386_GOT32`, `R_386_16`, `R_386_PC16`,
`R_386_8`, `R_386_PC8`) and their addends written into the code, as NASM
writes them; a reference with no 32-bit relocation (`dq label`) is an
error. With `-g` the debug information uses 4-byte addresses.

## NASM's options

utasm takes NASM's command-line options, so a Makefile written for NASM
works with `NASM=utasm`:

| Option | Meaning |
| --- | --- |
| `-I dir`, `-Idir`, `-i dir` | Include search directory. `%include` and `incbin` try the name as written (relative to the current directory), then each directory in the order given; a missing trailing `/` is added. |
| `-D name[=value]`, `-dname` | `%define name value` ahead of the source (`-DNAME` alone defines it empty). |
| `-U name`, `-uname` | `%undef name` ahead of the source. |
| `-p file`, `--include file` | `%include "file"` ahead of the source. (`-P` is utasm's `--profile`, so NASM's `-P` spelling is not available.) |
| `--before text` | The line `text` ahead of the source. `--pragma text` adds `%pragma text`. |
| `-E`, `-e` | Preprocess only: the source with macros expanded, conditionals resolved and includes read, on stdout, or into the `-o` file. It assembles to the same bytes as the original. |
| `-M`, `-MG` | Makefile dependencies on stdout, nothing assembled: `target : source includes incbins`, in NASM's format (lines wrapped with `\`). |
| `-MD` | Assemble, and write the dependencies too: into the `-MF` file, else the output's name with `.d`. |
| `-MF file`, `-MT target`, `-MQ target`, `-MP` | Where the dependencies go, the rule's target (default: the output file), and an empty rule for every file (`-MP`). `-MW` is accepted. |
| `-w+class`, `-w-class`, `-Wclass`, `-Wno-class` | Turn a warning class on or off (`all`: every class). The classes are NASM's: `user` (`%warning`), `zeroing`, `number-overflow`, `prefix-lock-xchg`, `prefix-lock-error`, `other`; a class utasm does not have is accepted and changes nothing. |
| `-w+error`, `-w+error=class`, `-Werror=class` | Warnings (of that class) are errors, like `-Werror`. |
| `-X gnu`, `-X vc` | Message style: `file:line: error: ...` (the default) or `file(line) : error: ...`. |
| `-s`, `-Z file` | Messages on stdout, or into a file. |
| `-l file` | The listing (see [Listings](#listings)). |
| `-g`, `-F dwarf` | DWARF debug information (see [Debug information](#debug-information)); `-F` takes any format name and gives DWARF. |
| `--no-line`, `--reproducible`, `--keep-all` | Accepted. |

`-D`, `-U`, `-p` and `--before` are read in the order given, as if a file
holding those lines were included at the top of the source; an error in
one is reported at `command line:N`.

## Listings

`-l file` writes every source line with the offset and the bytes it
produced, in NASM's layout (`nasm -l` and `utasm -l` give the same file for
the same source):

```
     5 00000000 B801000000                  mov eax, 1
     6 00000005 EB09                        jmp done
    14                                      two
    11 00000007 90                  <1>  nop
    15 00000009 90<rep 3h>                  times 3 nop
    21 00000010 48B888776655443322-         mov rax, qword 0x1122334455667788
    21 00000019 11
    23 00000036 488D35(00000000)            lea rsi, [rel msg]
    29 00000000 <res 40h>               buf: resb 64
```

The columns are the line number, the offset in the section, the bytes (9
to a row; a `-` continues the next row), and the source text. Lines of a
macro or `%rep` body follow the line that expanded them, marked `<1>`
(`<2>` one level deeper), as are the lines of an included file. A
relocated field shows its value in `(...)` when it is PC-relative and in
`[...]` otherwise; `times` and `align` show one repetition and `<rep Nh>`,
`incbin` `<bin Nh>`, reserved space `??` a byte or `<res Nh>`. The offsets
are final: jumps shortened after the line was assembled are listed short.
`[list -]` and `[list +]` stop and resume the listing.

## Debug information

`-g` (with or without `-F dwarf`) adds DWARF to an ELF object, so a
debugger can show the source and step through it line by line:

| Section | Contents |
| --- | --- |
| `.debug_line` | The line table: the address of every line that produced code, with its file and line. A macro's or `%rep` body's code is at its body line, an included file's in that file, as in NASM's (the decoded rows are the same). |
| `.debug_info`, `.debug_abbrev` | One compile unit: the source file, `utasm 0.1.0`, `DW_LANG_Mips_Assembler`, the line table, the first code section's range. |
| `.debug_aranges` | The address range of every code section. |

```sh
utasm -g prog.s -o prog.o && ld prog.o -o prog
gdb ./prog        # break work / next / bt: at inc.s:2, p.s:11, ...
```

Flat binaries and `--standalone` executables carry no debug information.

## Diagnostics

Errors and warnings are printed on stderr the way NASM prints them, at the
line of the statement they are about:

```
prog.s:12: error: invalid combination of opcode and operands
prog.s:3: error: parser: instruction expected, found `foo'
hint: did you mean 'xor'?
prog.s:20: error: symbol `count' not defined
prog.s:7: error: label `loop' inconsistently redefined
prog.s:9: warning: value is 16 ok [-w+user]
prog.s:14: warning: uninitialized space declared in non-BSS section `.text': zeroing [-w+zeroing]
```

- On a terminal (stderr a tty), or with `--color`, each message also
  shows its source line, with the place marked - the name the message is
  about, else where the parser stopped, else the statement - in color.
  An error about an instruction's operands says what they were and what
  clashes ("note: `al' is an 8-bit register, `rax' a 64-bit register");
  "operation size not specified" says what to write (`dword [rax]`).
  `--no-color`, `NO_COLOR` or `TERM=dumb` keep NASM's plain lines; piped
  into a file or a program the output is NASM's, plus the `hint:` and
  `note:` lines after an error.
- An operand size utasm cannot know (`inc [rax]`, `mov [rax], 5`,
  `shl [rax], cl`) is NASM's error "operation size not specified"; utasm
  used to pick one.
- A statement that comes from a multi-line macro is reported at the line
  that invoked the macro, followed by the line of the macro's body:
  `prog.s:4: ... from macro `m' defined here`. One from a `%rep` body (or
  `times`) is reported at its line in the body, one from an included file
  at its line in that file.
- Warnings are NASM's, each ending with its class: `db ?` or `resb` outside
  `.bss` (`zeroing`), a value that does not fit its field - `db 256`,
  `mov eax, 0x100000000` - (`number-overflow`), `lock` before an
  instruction that cannot be locked (`prefix-lock-error`) or before `xchg`
  (`prefix-lock-xchg`), a flat-binary section attribute in an object or
  `[rel rax]` (`other`). As in NASM they are given only when the source
  assembles: an error while it is read stops the assembly with no warning;
  an undefined symbol or a jump out of range is reported with them. The
  listing (`-l`) shows each warning after its line.
- `%warning` prints its text as a warning (class `user`) and assembly goes on. `%error`
  prints an error and assembly goes on, so that every `%error` reached is
  reported, but no output file is written. `%fatal` prints its text and
  stops.
- Undefined symbols are reported at the line that uses them, in every
  output format: a symbol must be defined, or declared `extern` (or
  `common`), as in NASM.
- Operands that no form of the instruction takes (`mov al, rax`,
  `bsf [rbx], bx`, `movzx eax, [rbx]`) are errors; they used to be encoded
  as something else.

The exit status tells which stage failed:

| Status | Meaning |
| --- | --- |
| 0 | success |
| 1 | usage error (bad options) |
| 2 | out of memory |
| 3 | input/output error |
| 4 | error in the source (syntax, preprocessor, `%error`, `%fatal`) |
| 5 | an instruction that cannot be encoded |
| 6 | link-time error (undefined symbol, relocation out of range) |

## Optimization levels

utasm assembles in a single pass, then optimizes jumps once every label
is known:

| Level | What it does |
| --- | --- |
| `-O0` | Nothing: every jump keeps the long form it was emitted with (5 bytes for `jmp`, 6 for `jcc`). |
| `-O1` (default) | Uses the 2-byte form for every `jmp`/`jcc` whose target is within reach, backward and forward, and moves the following code up. The result matches NASM's. |
| `-O2` / `-Ox` | Also rewrites jumps, which NASM does not do: `jcc L1` / `jmp L2` / `L1:` becomes one inverted `jcc L2`; a jump to a `jmp` goes straight to that jump's target; a jump to the very next instruction is removed. |

`-O2` keeps the program's behaviour - jumps never change flags, and a jump
is only removed when no label and no other branch points at it - but the
code no longer matches the source instruction for instruction, which can
surprise you when reading a disassembly. That is why it is opt-in.

Jumps written `jmp short`, `jmp near` or `strict` keep the size you wrote.
Code in a section that turns a position into a number (`$`, a difference
of two labels, or `equ` of a label) is never moved, since that number
could not be updated. Jumps to a label of the same section are shortened
whether the label is `global` or not, and a PC-relative reference to it
(`call f`, `[rel x]`) is written in place with no relocation, as NASM does;
`wrt ..plt` and the like keep their relocation.

On utasm's own 276 source files, `-O1` produces 7.3% less code than no
optimization (within 0.3% of NASM), and a utasm built with `-O2` has 68
fewer jumps and 126 fewer bytes than one built with `-O1` while producing
byte-for-byte identical output.
