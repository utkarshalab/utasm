# lib/ — the shared library

General-purpose code every module uses: memory, strings, formatting,
hashing, containers, floats, time, SHA-256. None of it knows about
assembly. Everything follows utasm's convention (`rax` = status or result,
`rbx rbp r12-r15` preserved).

## Memory: the arena (`arena.s`)

utasm allocates almost everything — tokens, symbols, strings, sections'
bookkeeping, macro bodies — from **one arena** made at start
(`global_arena`, main/utasm.s) and kept until exit. `arena_init` reserves
a large contiguous block with `mmap` (only pages actually touched are
committed); `arena_alloc` bumps a pointer (aligned); `arena_alloc_string`
copies a string in, `arena_alloc_struct` allocates and tags a struc.
Nothing is freed: an assembler run is short, and bump allocation is the
fastest there is. `mem_reserve` is the raw reservation other modules use
for their own growable tables (the symbol table, the jump records).

(Functions to undo allocations - `arena_checkpoint` / `arena_rollback` /
`arena_reset` - and `arena_destroy`, `arena_used`, `arena_remaining` were
never called, and were removed on 2026-10-22.)

## Strings (`string.s`)

Lengths (`str_len`), compares (`str_cmp`, case-insensitive `str_cmp_kw`),
`str_concat`, `str_dup`, `mem_copy`, `mem_zero`, identifier characters
(`str_is_ident_char`, `str_ident_chars`), numbers to text and back
(`int_to_str`, `str_int_to_str`, `str_to_int`), UTF-8 decoding
(`str_utf8_decode`): what utasm calls, and nothing else (the 24 functions
nothing called were removed on 2026-10-22; git history has them).

## Formatting (`fmt.s`)

A **bounded string builder**: an `FMTBUF` over a caller's buffer;
`fmt_str`, `fmt_char`, `fmt_hex`, `fmt_udec`, `fmt_pad`, `fmt_mem` append
and never overflow (a full buffer truncates and reports it). The tools'
output is built with it, line by line.

## Hashes (`hash.s`)

`hash_fnv1a_str` (section names, core/asmctx.s; the symbol table has its
own FNV-1a), `hash_crc32` (UBI headers, as zlib's).

## Containers

| File | What |
| --- | --- |
| `vec.s` | a growable array in the arena (`vec_init`, `vec_push`, `vec_reserve`); capacity doubles; used by optimize/jump.s |

## Numbers

| File | What |
| --- | --- |
| `float.s` | `float_encode`: a float constant's text (`1.5`, `1.0e3`, `0x1.8p3`, `Inf`, `NaN`) to IEEE 754 binary16 / 32 / 64 / 128, x87's 80-bit, NASM's 8-bit float and bfloat16 — correctly rounded (NASM's `dw` .. `dt` / `do`, `__?float32?__` & co.) |

## Time (`time.s`)

The moment assembly starts, taken once (`time_init`), for NASM's
`__DATE__`, `__TIME__`, `__DATE_NUM__`, `__TIME_NUM__`, their `__UTC_*`
forms and `__POSIX_TIME__`. Local time reads the TZif file `TZ` names (or
`/etc/localtime`) — no libc.

## SHA-256 (`sha256.s`)

FIPS 180-4, the scalar implementation verified in Utkarsha OS's
`crypto/uhash/sha256` against the FIPS vectors: `sha256_init` /
`_update` / `_final`, one-shot `sha256_hash`. For the UBI components'
digests (object/ubi).

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `arena.s` | 340 | the arena allocator, `mem_reserve` |
| `string.s` | 791 | strings, memory, characters, numbers, UTF-8 |
| `fmt.s` | 301 | the bounded string builder |
| `hash.s` | 111 | FNV-1a, CRC-32 |
| `vec.s` | 246 | growable arrays |
| `float.s` | 1,108 | float constants to IEEE 754 / x87 bits |
| `time.s` | 462 | the time of assembly, time zones |
| `sha256.s` | 513 | SHA-256 |

## Entry points

| Symbol | Used by |
| --- | --- |
| `arena_*`, `mem_reserve` | nearly every module |
| `str_*`, `mem_*`, `int_to_str` | nearly every module |
| `fmt_*` | tools/ |
| `hash_fnv1a_str` | core/asmctx.s |
| `hash_crc32` | object/ubi |
| `vec_init`, `vec_push`, `mem_reserve` | optimize/jump.s; `mem_reserve` also the symbol table, the preprocessor, the parsers, relocations, the ELF writer, map files, the LSP server |
| `float_encode`, `float_overflow`, `float_special` | frontend/syntax |
| `time_*` | frontend/preproc |
| `sha256_*` | object/ubi |

## Depends on

platform/ (`mmap` for the arena and the heap), main/.

## What is left

Nothing unused is left: every function here is called.

## Tests

Indirect: every suite. `float.s` is checked by *data forms* (every float
format against NASM's bytes), `sha256.s` and `hash_crc32` by *ubi images*
(against Python's hashlib and zlib). `time.s` has no test of its own (its
values change with each run); `SOURCE_DATE_EPOCH` support would make one
possible, and make builds that use `__DATE__` reproducible.
