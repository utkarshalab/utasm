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

Unused today: `arena_checkpoint` / `arena_rollback` / `arena_reset`
(undoing allocations), `arena_destroy`, `arena_used`, `arena_remaining`.

## Strings (`string.s`)

Lengths, compares (`str_cmp`, case-insensitive `str_cmp_kw`, `mem_cmp`),
copies (`str_copy`, `str_dup`, `mem_copy`), searching, character classes
(`str_is_digit`, `str_is_ident_char` ...), numbers to text and back
(`int_to_str`, `str_to_int`), UTF-8 decoding (`str_utf8_decode`). Many of
its 40 exports are unused (see the list at the end).

## Formatting (`fmt.s`)

A **bounded string builder**: an `FMTBUF` over a caller's buffer;
`fmt_str`, `fmt_char`, `fmt_hex`, `fmt_udec`, `fmt_pad`, `fmt_mem` append
and never overflow (a full buffer truncates and reports it). The tools'
output is built with it, line by line.

## Hashes (`hash.s`)

`hash_fnv1a_str` (section names, core/asmctx.s; the symbol table has its
own FNV-1a), `hash_crc32` (UBF headers, as zlib's), `hash_u64` (a
splitmix64 finalizer, used inside hash.s).

## Containers

| File | What |
| --- | --- |
| `vec.s` | a growable array in the arena (`vec_init`, `vec_push`, `vec_get`, `vec_reserve`); capacity doubles; used by optimize/jump.s |

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
`_update` / `_final`, one-shot `sha256_hash`. For the UBF components'
digests (object/ubf).

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `arena.s` | 550 | the arena allocator, `mem_reserve` |
| `string.s` | 1,644 | strings, memory, characters, numbers, UTF-8 |
| `fmt.s` | 380 | the bounded string builder |
| `hash.s` | 202 | FNV-1a, CRC-32, splitmix64 |
| `vec.s` | 406 | growable arrays |
| `float.s` | 1,108 | float constants to IEEE 754 / x87 bits |
| `time.s` | 464 | the time of assembly, time zones |
| `sha256.s` | 513 | SHA-256 |

## Entry points

| Symbol | Used by |
| --- | --- |
| `arena_*`, `mem_reserve` | nearly every module |
| `str_*`, `mem_*`, `int_to_str` | nearly every module |
| `fmt_*` | tools/ |
| `hash_fnv1a_str` | core/asmctx.s |
| `hash_crc32` | object/ubf |
| `vec_*`, `mem_reserve` | optimize/jump.s; `mem_reserve` also the symbol table, the preprocessor, the parsers, relocations, the ELF writer, map files, the LSP server |
| `float_encode`, `float_overflow`, `float_special` | frontend/syntax |
| `time_*` | frontend/preproc |
| `sha256_*` | object/ubf |

## Depends on

platform/ (`mmap` for the arena and the heap), main/.

## What is left

Remove what is unused, or use it: in `string.s`: `hex_to_byte`, `mem_cmp`, `mem_move`, `mem_set`,
`path_get_extension`, `path_get_filename`, `str_cmp_n`, `str_copy_n`,
`str_find_char`, `str_find_str`, `str_free`, `str_hash`, `str_is_alnum`,
`str_split_char`, `str_to_lower`, `str_to_upper`, `str_trim`,
`string_concat`, `string_copy`, `string_length`; `vec_clear`,
`vec_get_u64`, `vec_len`, `vec_pop`, `vec_push_u64`; `fmt_dec`,
`fmt_write_fd`; `hash_combine`, `hash_fnv1a_mem`.

## Tests

Indirect: every suite. `float.s` is checked by *data forms* (every float
format against NASM's bytes), `sha256.s` and `hash_crc32` by *ubf images*
(against Python's hashlib and zlib). `time.s` has no test of its own (its
values change with each run); `SOURCE_DATE_EPOCH` support would make one
possible, and make builds that use `__DATE__` reproducible.
