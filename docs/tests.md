# utasm — Test Architecture

> Complete test suite documentation.
> Test files live at `tests/` in the project root.
> This document defines structure, coverage requirements, and contribution rules.

---

## Philosophy

```
Tests outnumber source files.
That ratio is correct.
That ratio is healthy.

Write it.
Break it.
Fix it.
Write a test.
It never breaks that way again.
```

**Naming rule:** folder provides context, filename describes only the behaviour. Nothing repeated.

```
tests/unit/lexer/ident.s          ← not lex_ident.s
tests/unit/encoder/x86/mov_rr.s  ← not enc_mov_rr.s
tests/error/E1xx/E101.s           ← not test_err_E101.s
```

---

## Structure

```
tests/
│
├── runner.s                 ; test runner entry point
├── report.s                 ; result reporting + summary
├── diff.s                   ; binary diff engine
├── expect.s                 ; expected output comparison
├── timeout.s                ; hung test detection
├── parallel.s               ; parallel test execution
│
├── unit/                    ; one module, one behaviour
├── error/                   ; verify every error code fires correctly
├── warning/                 ; verify warnings fire and are suppressible
├── integration/             ; source → binary → execution
├── regression/              ; every bug ever fixed, grows forever
├── fuzz/                    ; random inputs, must never crash
├── perf/                    ; throughput benchmarks, must not regress
├── stress/                  ; push every limit to its maximum
└── fixtures/                ; shared includes, objects, expected binaries
```

---

## Unit Tests

```
tests/unit/
│
├── lexer/
│   ├── ident.s
│   ├── keywords.s
│   ├── num_dec.s
│   ├── num_hex.s
│   ├── num_bin.s
│   ├── num_oct.s
│   ├── num_overflow.s
│   ├── string.s
│   ├── string_esc.s
│   ├── char.s
│   ├── comment_line.s
│   ├── comment_block.s
│   ├── whitespace.s
│   ├── newline.s
│   ├── utf8.s
│   ├── sourcemap.s
│   └── empty.s
│
├── parser/
│   ├── instr.s
│   ├── operand.s
│   ├── reg.s
│   ├── reg_8bit.s
│   ├── reg_16bit.s
│   ├── reg_32bit.s
│   ├── reg_64bit.s
│   ├── reg_simd.s
│   ├── mem.s
│   ├── mem_sib.s
│   ├── mem_disp8.s
│   ├── mem_disp32.s
│   ├── mem_riprel.s
│   ├── imm.s
│   ├── label.s
│   ├── local_label.s
│   ├── section.s
│   ├── global.s
│   ├── extern.s
│   ├── common.s
│   ├── data_db.s
│   ├── data_dw.s
│   ├── data_dd.s
│   ├── data_dq.s
│   ├── data_str.s
│   ├── data_dup.s
│   ├── struct.s
│   ├── proc.s
│   ├── align.s
│   ├── times.s
│   ├── equ.s
│   ├── expr_add.s
│   ├── expr_sub.s
│   ├── expr_mul.s
│   ├── expr_div.s
│   ├── expr_paren.s
│   ├── expr_prec.s
│   ├── expr_shift.s
│   ├── expr_bitwise.s
│   └── multiline.s
│
├── macro/
│   ├── define_simple.s
│   ├── define_param.s
│   ├── redefine.s
│   ├── undef.s
│   ├── purge.s
│   ├── args_basic.s
│   ├── args_default.s
│   ├── args_greedy.s
│   ├── args_count.s
│   ├── local.s
│   ├── nested.s
│   ├── recursive.s
│   ├── stringify.s
│   ├── paste.s
│   ├── cond_if.s
│   ├── cond_ifdef.s
│   ├── cond_ifidn.s
│   ├── cond_else.s
│   ├── cond_nested.s
│   ├── rep.s
│   ├── rep_count.s
│   ├── rotate.s
│   ├── include.s
│   ├── include_depth.s
│   ├── include_once.s
│   ├── library.s
│   └── expansion_loc.s
│
├── symtable/
│   ├── insert.s
│   ├── lookup.s
│   ├── lookup_miss.s
│   ├── redef.s
│   ├── forward.s
│   ├── forward_multi.s
│   ├── forward_unresolved.s
│   ├── local_scope.s
│   ├── local_reuse.s
│   ├── global.s
│   ├── extern.s
│   ├── common.s
│   ├── weak.s
│   ├── collision.s
│   └── 1m_symbols.s
│
├── expr/
│   ├── add.s
│   ├── sub.s
│   ├── mul.s
│   ├── div.s
│   ├── mod.s
│   ├── neg.s
│   ├── and.s
│   ├── or.s
│   ├── xor.s
│   ├── not.s
│   ├── shl.s
│   ├── shr.s
│   ├── prec.s
│   ├── paren.s
│   ├── divzero.s
│   ├── overflow.s
│   ├── symref.s
│   ├── reloc.s
│   └── const_fold.s
│
├── encoder/
│   │
│   ├── x86/
│   │   ├── mov_rr.s
│   │   ├── mov_rm.s
│   │   ├── mov_mr.s
│   │   ├── mov_ri.s
│   │   ├── mov_mi.s
│   │   ├── mov_seg.s
│   │   ├── movzx.s
│   │   ├── movsx.s
│   │   ├── movsxd.s
│   │   ├── add.s
│   │   ├── sub.s
│   │   ├── mul.s
│   │   ├── imul.s
│   │   ├── div.s
│   │   ├── idiv.s
│   │   ├── adc.s
│   │   ├── sbb.s
│   │   ├── inc.s
│   │   ├── dec.s
│   │   ├── and.s
│   │   ├── or.s
│   │   ├── xor.s
│   │   ├── not.s
│   │   ├── neg.s
│   │   ├── shl.s
│   │   ├── shr.s
│   │   ├── sar.s
│   │   ├── rol.s
│   │   ├── ror.s
│   │   ├── rcl.s
│   │   ├── rcr.s
│   │   ├── shld.s
│   │   ├── shrd.s
│   │   ├── jmp_short.s
│   │   ├── jmp_near.s
│   │   ├── jmp_ind.s
│   │   ├── jcc.s
│   │   ├── loop.s
│   │   ├── call_near.s
│   │   ├── call_ind.s
│   │   ├── ret.s
│   │   ├── retf.s
│   │   ├── push_reg.s
│   │   ├── push_imm.s
│   │   ├── push_mem.s
│   │   ├── pop.s
│   │   ├── pushf.s
│   │   ├── lea.s
│   │   ├── xchg.s
│   │   ├── cmpxchg.s
│   │   ├── cmpxchg16b.s
│   │   ├── bswap.s
│   │   ├── movbe.s
│   │   ├── string.s
│   │   ├── rep.s
│   │   ├── bt.s
│   │   ├── bsf.s
│   │   ├── tzcnt.s
│   │   ├── cmov.s
│   │   ├── setcc.s
│   │   ├── cmp.s
│   │   ├── nop.s
│   │   ├── hlt.s
│   │   ├── cpuid.s
│   │   ├── rdtsc.s
│   │   ├── rdrand.s
│   │   ├── syscall.s
│   │   ├── priv.s
│   │   ├── lock.s
│   │   ├── rex_w.s
│   │   ├── rex_r.s
│   │   ├── rex_x.s
│   │   ├── rex_b.s
│   │   ├── rex_high.s
│   │   ├── addr_modes.s
│   │   ├── sib_base.s
│   │   ├── sib_index.s
│   │   ├── sib_scale.s
│   │   ├── sib_nobase.s
│   │   ├── riprel.s
│   │   ├── disp8.s
│   │   ├── disp32.s
│   │   ├── aesni.s
│   │   ├── sha.s
│   │   └── pclmul.s
│   │
│   ├── simd/
│   │   ├── mmx.s
│   │   ├── sse_ps.s
│   │   ├── sse_ss.s
│   │   ├── sse2_pd.s
│   │   ├── sse2_sd.s
│   │   ├── sse2_int.s
│   │   ├── ssse3.s
│   │   ├── sse41.s
│   │   ├── sse42.s
│   │   ├── avx_vex2.s
│   │   ├── avx_vex3.s
│   │   ├── avx_128.s
│   │   ├── avx_256.s
│   │   ├── avx2_int.s
│   │   ├── avx2_gather.s
│   │   ├── avx512f.s
│   │   ├── avx512_evex.s
│   │   ├── avx512_mask.s
│   │   ├── avx512_zero.s
│   │   ├── avx512_bcast.s
│   │   ├── avx512_round.s
│   │   ├── avx512bw.s
│   │   ├── avx512dq.s
│   │   ├── avx512vl.s
│   │   ├── avx512vnni.s
│   │   ├── avx512bf16.s
│   │   ├── amx_tile.s
│   │   ├── amx_tmul.s
│   │   └── fpu.s
│   │
│   ├── aarch64/
│   │   ├── mov.s
│   │   ├── arith.s
│   │   ├── logic.s
│   │   ├── branch.s
│   │   ├── load.s
│   │   ├── store.s
│   │   ├── pair.s
│   │   ├── system.s
│   │   ├── neon_int.s
│   │   ├── neon_fp.s
│   │   └── sve.s
│   │
│   └── riscv64/
│       ├── base.s
│       ├── m.s
│       ├── a.s
│       ├── f.s
│       ├── d.s
│       ├── c.s
│       └── v.s
│
├── linker/
│   ├── basic.s
│   ├── forward.s
│   ├── extern.s
│   ├── reloc_abs.s
│   ├── reloc_rel.s
│   ├── reloc_got.s
│   ├── reloc_plt.s
│   ├── reloc_tls.s
│   ├── sections.s
│   ├── layout.s
│   ├── align.s
│   ├── bss.s
│   ├── dead.s
│   ├── multi.s
│   ├── archive.s
│   ├── circular.s
│   ├── common.s
│   ├── weak.s
│   └── script.s
│
└── output/
    ├── elf_exec.s
    ├── elf_obj.s
    ├── elf_so.s
    ├── elf_hdr.s
    ├── elf_sym.s
    ├── elf_rela.s
    ├── elf_phdr.s
    ├── elf_note.s
    ├── pe_exec.s
    ├── pe_hdr.s
    ├── flat.s
    ├── flat_boot.s
    ├── upk.s
    ├── upk_sign.s
    ├── dwarf_info.s
    ├── dwarf_line.s
    ├── listing.s
    └── mapfile.s
```

---

## Error Tests

Every error code must have a test that:
1. Provides input that triggers exactly that error
2. Verifies the correct error code fires
3. Verifies line number is correct
4. Verifies column number is correct
5. Verifies recovery continues to find subsequent errors

```
tests/error/
│
├── E1xx/
│   ├── E101.s
│   ├── E102.s
│   ├── E103.s
│   ├── E104.s
│   ├── E105.s
│   ├── E106.s
│   ├── E107.s
│   ├── E108.s
│   ├── E109.s
│   ├── E110.s
│   ├── E111.s
│   ├── E112.s
│   ├── E113.s
│   ├── E114.s
│   └── E115.s
│
├── E2xx/
│   ├── E201.s
│   ├── E202.s
│   ├── E203.s
│   ├── E204.s
│   ├── E205.s
│   ├── E208.s
│   ├── E209.s
│   ├── E210.s
│   ├── E211.s
│   ├── E212.s
│   ├── E213.s
│   ├── E214.s
│   ├── E215.s
│   ├── E221.s
│   ├── E226.s
│   └── E227.s
│
├── E3xx/
│   ├── E301.s
│   ├── E302.s
│   ├── E303.s
│   ├── E304.s
│   ├── E305.s
│   ├── E306.s
│   ├── E307.s
│   ├── E311.s
│   ├── E312.s
│   ├── E319.s
│   └── E320.s
│
├── E4xx/
│   ├── E401.s
│   ├── E402.s
│   ├── E403.s
│   ├── E405.s
│   ├── E406.s
│   ├── E410.s
│   ├── E411.s
│   ├── E412.s
│   ├── E419.s
│   ├── E420.s
│   └── E421.s
│
├── E5xx/
│   ├── E501.s
│   ├── E502.s
│   ├── E503.s
│   ├── E504.s
│   ├── E505.s
│   ├── E506.s
│   ├── E507.s
│   ├── E508.s
│   ├── E509.s
│   ├── E513.s
│   ├── E514.s
│   ├── E515.s
│   ├── E516.s
│   ├── E519.s
│   ├── E520.s
│   ├── E526.s
│   ├── E527.s
│   ├── E529.s
│   ├── E530.s
│   ├── E533.s
│   └── E534.s
│
├── E6xx/
│   ├── E601.s
│   ├── E602.s
│   ├── E603.s
│   ├── E604.s
│   └── E608.s
│
├── E7xx/
│   ├── E701.s
│   ├── E702.s
│   ├── E708.s
│   ├── E709.s
│   ├── E710.s
│   ├── E714.s
│   ├── E716.s
│   ├── E717.s
│   ├── E720.s
│   ├── E725.s
│   ├── E727.s
│   └── E729.s
│
├── E9xx/
│   ├── E901.s
│   ├── E902.s
│   └── E903.s
│
└── multi/
    ├── recover_lexer.s      ; lexer finds 5 errors not just 1
    ├── recover_parser.s     ; parser finds 5 errors not just 1
    ├── recover_encoder.s    ; encoder finds 5 errors not just 1
    ├── chain.s              ; error + macro expansion chain displayed
    └── dedup.s              ; same error twice → shown once
```

---

## Warning Tests

Every warning code must have:
1. A test that verifies it fires
2. A test that verifies `-Wno-<warning>` suppresses it
3. A test that verifies `-Werror` promotes it to error

```
tests/warning/
├── W201.s
├── W202.s
├── W301.s
├── W302.s
├── W501.s
├── W503.s
├── W505.s
├── W601.s
├── W702.s
├── W703.s
├── suppress_Wno.s
├── suppress_file.s
└── promote_Werror.s
```

---

## Integration Tests

Full pipeline — source to binary to execution.

```
tests/integration/
│
├── hello/
│   ├── amd64.s
│   ├── aarch64.s
│   ├── riscv64.s
│   └── *.expect
│
├── selfhost/
│   ├── selfhost.sh          ; utasm assembles itself
│   └── parity.sh            ; gen1 == gen2 bit-identical check
│
├── elf/
│   ├── exec.s
│   ├── shared.s
│   ├── static.s
│   ├── bss.s
│   └── debug.s
│
├── pe/
│   ├── uefi.s
│   └── signed.s
│
├── boot/
│   ├── mbr.s                ; boots in QEMU
│   └── uefi.s               ; UEFI boots in QEMU
│
├── upk/
│   ├── build.s
│   └── verify.s
│
├── simd/
│   ├── sse2_add.s
│   ├── avx2_add.s
│   ├── avx512_vnni.s
│   ├── aesni.s
│   └── verify.s
│
├── multifile/
│   ├── a.s
│   ├── b.s
│   ├── main.s
│   └── run.sh
│
├── crossarch/
│   ├── aarch64.sh
│   └── riscv64.sh
│
└── selfpatch/
    ├── basic.s
    ├── rollback.s
    └── perf.s
```

---

## Regression Tests

**Rule: every bug fixed gets a regression test. No exceptions.**

```
tests/regression/
├── reg_001.s
├── reg_002.s
├── reg_003.s
└── reg_NNN.s      ; grows for the lifetime of utasm
```

Header format for every regression file:

```asm
; REGRESSION: reg_NNN
; Date:       YYYY-MM-DD
; Bug:        one line description
; Symptom:    what the user saw
; Root cause: what caused it
; Fix:        what was changed
; Error:      E5xx (if applicable)
```

This folder is permanent memory. Every entry is an hour transformed into permanent protection.

---

## Speed

`scripts/compat/bench.py` assembles the same large inputs with NASM and
utasm - straight-line code, jumps among labels, macro calls, labelled data -
and times them, checking that the code is the same. It also times both on
utasm's own sources, NASM with the Makefile's `-d__NASM__=1 -I./`:

```sh
python3 scripts/compat/bench.py build/gen1/utasm            # about a minute
python3 scripts/compat/bench.py build/gen1/utasm --scale 5  # larger inputs
python3 scripts/compat/bench.py build/gen1/utasm --only jumps
```

---

## Fuzz Tests

`scripts/compat/fuzz.py` changes the test sources and the compatibility
cases at random - lines dropped, repeated, cut, swapped or spliced in from
another source; directives, operators, odd bytes and nesting inserted - and
assembles each result as bin, elf64 or elf32, sometimes with `-l` or `-g`:

```sh
python3 scripts/compat/fuzz.py build/gen1/utasm 6000 7   # 6000 runs, seed 7
```

**Invariants that must hold regardless of input:**
- No internal error: a fault in utasm (SIGSEGV, SIGBUS, SIGFPE, SIGILL) is
  caught by `core/crash.s` and reported as `file:line: fatal: internal
  error: ... at 0x...`, exit status 9 - the fuzzer counts it, as it counts
  a death by any other signal
- Finishes within 10 seconds
- Uses no more than 2 GB
- Otherwise, any exit status: assembling it or reporting errors are both fine

Each failing input is saved, cut down to the smallest one that fails at the
same address, and printed once per address with the function it is in. The
same seed gives the same inputs. The inputs it has found are kept in
`cases.ROBUST_CASES`, which the *robustness* compatibility suite runs.

---

## Performance Benchmarks

```
tests/perf/
├── runner.s
├── lexer.s
├── parser.s
├── macro.s
├── encoder.s
├── linker.s
├── output.s
├── large.s              ; 100,000 line file end-to-end
├── selfhost.s           ; time to assemble utasm itself
│
└── results/
    ├── baseline.tsv
    └── YYYY-MM-DD.tsv
```

**Targets:**

| Metric | Target |
|---|---|
| Lexer throughput | > 500 MB/s |
| Encoder throughput | > 5M instructions/sec |
| Self-host time | < 2 seconds |
| 100k line file | < 1 second |

---

## Stress Tests

```
tests/stress/
├── deep_macro.s
├── long_expr.s
├── many_symbols.s
├── many_sections.s
├── large_binary.s
├── many_errors.s
└── parallel.s
```

---

## Fixtures

```
tests/fixtures/
│
├── inc/
│   ├── basic.inc
│   ├── simd.inc
│   ├── cpu.inc
│   └── assert.inc
│
├── obj/
│   └── prebuilt_*.o
│
└── expect/
    └── *.bin
```

---

## Running Tests

```sh
bash scripts/bootstrap.sh          # build Gen1 first

bash scripts/test.sh               # full suite
bash scripts/test.sh unit          # unit tests only
bash scripts/test.sh error         # error tests only
bash scripts/test.sh integration   # integration only
bash scripts/test.sh regression    # regression only
bash scripts/test.sh perf          # benchmarks only
bash scripts/test.sh fuzz          # fuzz tests only

bash scripts/test.sh unit/lexer/ident   ; single test
bash scripts/test.sh --verbose          ; verbose output
bash scripts/test.sh --timeout 30       ; timeout override (default 5s)
```

**Expected output:**

```
[+] utasm Test Harness
    UtkarshaLab Test Suite

    [unit/lexer]         17 passed   0 failed
    [unit/parser]        35 passed   0 failed
    [unit/macro]         27 passed   0 failed
    [unit/symtable]      15 passed   0 failed
    [unit/expr]          19 passed   0 failed
    [unit/encoder/x86]   78 passed   0 failed
    [unit/encoder/simd]  27 passed   0 failed
    [unit/encoder/a64]   11 passed   0 failed
    [unit/encoder/rv64]   7 passed   0 failed
    [unit/linker]        19 passed   0 failed
    [unit/output]        18 passed   0 failed
    [error]             112 passed   0 failed
    [warning]            13 passed   0 failed
    [integration]        22 passed   0 failed
    [regression]        NNN passed   0 failed
    [stress]              7 passed   0 failed
    [perf]                9 passed   0 failed

══════════════════════════════════════
    TOTAL: NNN Passed | 0 Failed
══════════════════════════════════════
[+] VALIDATION SUCCESSFUL
```

---

## Adding a Test

1. Pick the right category folder
2. Name by behaviour only — no folder name prefix
3. Add a header:

```asm
; TEST: ident
; Category: unit/lexer
; Tests:    identifier scanning — alphanumeric, underscore, leading underscore
; Expects:  token stream matches fixtures/expect/lex_ident.bin
```

4. Add to runner manifest in `utasm.toml`
5. Run `bash scripts/test.sh unit/lexer/ident` and verify it passes

---

## Adding a Regression Test

```asm
; REGRESSION: reg_NNN
; Date:       YYYY-MM-DD
; Bug:        utasm crashed on RIP-relative with negative displacement
; Symptom:    segfault in backend/encoder/x86/riprel.s:142
; Root cause: sign extension not applied before range check
; Fix:        MOVSX applied before CMP in range validation
; Error:      E505 now fires correctly instead of crashing
```

Add it. Run it. It passes. The bug is gone forever.

---

## NASM Compatibility Suites

`scripts/compat/run_all.py` assembles the same sources with NASM and with
utasm and compares what comes out. `scripts/test.sh` runs it after the test
matrix; it can also be run alone:

```sh
python3 scripts/compat/run_all.py build/gen1/utasm          # everything
python3 scripts/compat/run_all.py build/gen1/utasm --quick  # skip the slow suites
python3 scripts/compat/run_all.py build/gen1/utasm -v       # also list known differences
```

| Suite | What is compared |
|---|---|
| bin probes | ~170 feature programs (preprocessor, directives, numbers, operators, instruction syntax) as flat binaries, byte for byte |
| elf probes | ELF objects: section contents, relocations (type, symbol, addend) and the symbol table |
| data forms | `db`/`dw`/`dd`/`dq`/`dt`, strings and escapes, floats, `incbin`: the bytes, or both rejecting |
| sections/link | section headers of objects; programs that are linked (`ld` or `--standalone`) and run |
| label operands | labels as immediates and displacements: instruction lengths and relocation types |
| ubf images | `-f ubf` images: every header and component field, the CRC and the SHA-256 digests |
| diagnostics | sources NASM rejects: utasm must reject them too, with the first error at the same file and line |
| listings | `-l` on every bin probe (as an ELF object): the same listing file as NASM's, line for line |
| dwarf line tables | `-g` objects: the same decoded line table rows (file, line, address) as NASM's |
| elf32 objects | `-f elf32`: the same contents, relocations (types and in-place addends) and symbols as NASM's i386 objects, and a program linked with `ld -m elf_i386` that runs |
| bits 32 / bits 16 | the encoder corpus assembled in 32- and 16-bit mode: the same bytes as NASM, or rejected where NASM rejects it (and where NASM takes registers those modes do not have) |
| command line | NASM's options (`-I`, `-D`, `-U`, `-p`, `--before`, `-M` and its variants, `-E`) on the same files: the same binary, or the same dependency rules |
| expressions | labels defined later in arithmetic (`dd (end - start) / 4`), as data, immediates and displacements, in flat binaries and objects: the same bytes; NASM's scalar rule (a label in `*`, `/`, shifts, `&`, comparisons...) before and after its definition: the same error messages; `times` / `resb` counts and `equ`s that use labels and equs defined later: the same bytes; names never defined and equs naming each other: an error |
| limits | inputs past utasm's old fixed limits - long `times` lines, 100-parameter macros, long arguments and bodies, deep `%if` / `%push` / macro / include nesting, long `%ifidn` / `%defstr` / `%[...]` text, 300 sections: the same output as NASM |
| addresses | base, index and scale in every order NASM takes (`[rbx+rcx*4]`, `[4*rcx+rbx]`, `[rbx*1+rcx]`, `[rax+rax*3]`, `[rbx*3]`), with displacements and labels, in bits 64, 32 and 16, and vector indexes: the same bytes as NASM, or rejected where NASM rejects it |
| warnings | NASM's warnings (`%warning`, uninitialized space outside `.bss`, data and immediates out of bounds, `lock`, section attributes) under seven sets of `-w` / `-W` options: the same stderr, the same exit status, and, when NASM succeeds, the same listing with each warning after its line |
| robustness | inputs that crashed or hung utasm before (found by `fuzz.py`, see *Fuzz Tests*): it must finish, with no internal error, and accept or reject each as NASM does |
| encoder corpus | every instruction of `corpus.py` alone, byte for byte |
| operand shapes | ~1,700 pairings of register and memory sizes for the general-purpose instructions: the same bytes as NASM, or rejected where NASM rejects them |
| disassembler | `utasm --disasm` against `objdump -d -M intel` on the gen1 objects and the corpus |

The sources live in `scripts/compat/cases.py` and `corpus.py`. A difference
that is deliberate or not implemented yet goes in `common.KNOWN` with the
reason: it is reported as *known* and does not fail the run, and the suite
says so when it starts matching, so the entry can be removed. The suites
need `nasm`, `readelf`, `objdump` and `objcopy`; without them they are
skipped with a note.

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
