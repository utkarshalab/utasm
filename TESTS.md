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
│   ├── E101.s  ├── E102.s  ├── E103.s  ├── E104.s  ├── E105.s
│   ├── E106.s  ├── E107.s  ├── E108.s  ├── E109.s  ├── E110.s
│   ├── E111.s  ├── E112.s  ├── E113.s  ├── E114.s  └── E115.s
│
├── E2xx/
│   ├── E201.s  ├── E202.s  ├── E203.s  ├── E204.s  ├── E205.s
│   ├── E208.s  ├── E209.s  ├── E210.s  ├── E211.s  ├── E212.s
│   ├── E213.s  ├── E214.s  ├── E215.s  ├── E221.s  ├── E226.s
│   └── E227.s
│
├── E3xx/
│   ├── E301.s  ├── E302.s  ├── E303.s  ├── E304.s  ├── E305.s
│   ├── E306.s  ├── E307.s  ├── E311.s  ├── E312.s  ├── E319.s
│   └── E320.s
│
├── E4xx/
│   ├── E401.s  ├── E402.s  ├── E403.s  ├── E405.s  ├── E406.s
│   ├── E410.s  ├── E411.s  ├── E412.s  ├── E419.s  ├── E420.s
│   └── E421.s
│
├── E5xx/
│   ├── E501.s  ├── E502.s  ├── E503.s  ├── E504.s  ├── E505.s
│   ├── E506.s  ├── E507.s  ├── E508.s  ├── E509.s  ├── E513.s
│   ├── E514.s  ├── E515.s  ├── E516.s  ├── E519.s  ├── E520.s
│   ├── E526.s  ├── E527.s  ├── E529.s  ├── E530.s  ├── E533.s
│   └── E534.s
│
├── E6xx/
│   ├── E601.s  ├── E602.s  ├── E603.s  ├── E604.s  └── E608.s
│
├── E7xx/
│   ├── E701.s  ├── E702.s  ├── E708.s  ├── E709.s  ├── E710.s
│   ├── E714.s  ├── E716.s  ├── E717.s  ├── E720.s  ├── E725.s
│   ├── E727.s  └── E729.s
│
├── E9xx/
│   ├── E901.s  ├── E902.s  └── E903.s
│
└── multi/
    ├── recover_lexer.s
    ├── recover_parser.s
    ├── recover_encoder.s
    ├── chain.s
    └── dedup.s
```

---

## Warning Tests

Every warning code must have:
1. A test that verifies it fires
2. A test that verifies `-Wno-<warning>` suppresses it
3. A test that verifies `-Werror` promotes it to error

```
tests/warning/
├── W201.s  ├── W202.s  ├── W301.s  ├── W302.s  ├── W501.s
├── W503.s  ├── W505.s  ├── W601.s  ├── W702.s  ├── W703.s
├── suppress_Wno.s
├── suppress_file.s
└── promote_Werror.s
```

---

## Integration Tests

```
tests/integration/
│
├── hello/
│   ├── amd64.s  ├── aarch64.s  ├── riscv64.s  └── *.expect
│
├── selfhost/
│   ├── selfhost.sh
│   └── parity.sh
│
├── elf/
│   ├── exec.s  ├── shared.s  ├── static.s  ├── bss.s  └── debug.s
│
├── pe/
│   ├── uefi.s  └── signed.s
│
├── boot/
│   ├── mbr.s  └── uefi.s
│
├── upk/
│   ├── build.s  └── verify.s
│
├── simd/
│   ├── sse2_add.s  ├── avx2_add.s  ├── avx512_vnni.s
│   ├── aesni.s     └── verify.s
│
├── multifile/
│   ├── a.s  ├── b.s  ├── main.s  └── run.sh
│
├── crossarch/
│   ├── aarch64.sh  └── riscv64.sh
│
└── selfpatch/
    ├── basic.s  ├── rollback.s  └── perf.s
```

---

## Regression Tests

**Rule: every bug fixed gets a regression test. No exceptions.**

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

```
tests/regression/
├── reg_001.s
└── reg_NNN.s      ; grows for the lifetime of utasm
```

---

## Fuzz Tests

Random inputs. utasm must never crash, hang, or produce undefined behaviour.

**Invariants that must hold regardless of input:**
- Never segfaults
- Never hangs (enforced by timeout.s)
- Always exits 0 (success) or 1 (error)
- Error messages always contain valid line/col numbers

```
tests/fuzz/
├── runner.s  ├── lexer.s  ├── parser.s  ├── macro.s
├── encoder.s ├── expr.s   ├── elf.s
├── seeds/
│   ├── empty.s  ├── nullbytes.s  ├── allff.s  ├── deep_macro.s
│   ├── long_line.s  ├── unicode.s  └── max_symbols.s
└── corpus/
```

---

## Performance Benchmarks

| Metric | Target |
|---|---|
| Lexer throughput | > 500 MB/s |
| Encoder throughput | > 5M instructions/sec |
| Self-host time | < 2 seconds |
| 100k line file | < 1 second |

```
tests/perf/
├── runner.s  ├── lexer.s  ├── parser.s  ├── macro.s
├── encoder.s ├── linker.s ├── output.s  ├── large.s
├── selfhost.s
└── results/
    ├── baseline.tsv
    └── YYYY-MM-DD.tsv
```

---

## Stress Tests

```
tests/stress/
├── deep_macro.s  ├── long_expr.s    ├── many_symbols.s
├── many_sections.s ├── large_binary.s ├── many_errors.s
└── parallel.s
```

---

## Fixtures

```
tests/fixtures/
├── inc/
│   ├── basic.inc  ├── simd.inc  ├── cpu.inc  └── assert.inc
├── obj/
│   └── prebuilt_*.o
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

bash scripts/test.sh unit/lexer/ident   # single test
bash scripts/test.sh --verbose          # verbose output
bash scripts/test.sh --timeout 30       # timeout override (default 5s)
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

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
