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

**Naming rule:** folder provides context, filename carries the `test_` prefix + module + behaviour. Consistent, greppable, unambiguous.

```
tests/unit/lexer/test_lex_ident.asm
tests/unit/encoder/x86/test_enc_mov_rr.asm
tests/error/lexer_errors/test_err_E101.asm
tests/regression/reg_001.asm
```

---

## Structure

```
tests/
│
├── README.asm               ; test suite documentation
├── runner.asm               ; test runner entry point
├── runner_report.asm        ; test result reporting
├── runner_diff.asm          ; binary diff for output comparison
├── runner_expect.asm        ; expected output comparison engine
├── runner_timeout.asm       ; hung test detection
├── runner_parallel.asm      ; parallel test execution
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
│   ├── test_lex_ident.asm
│   ├── test_lex_keywords.asm
│   ├── test_lex_num_dec.asm
│   ├── test_lex_num_hex.asm
│   ├── test_lex_num_bin.asm
│   ├── test_lex_num_oct.asm
│   ├── test_lex_num_overflow.asm
│   ├── test_lex_string.asm
│   ├── test_lex_string_esc.asm
│   ├── test_lex_char.asm
│   ├── test_lex_comment_line.asm
│   ├── test_lex_comment_block.asm
│   ├── test_lex_whitespace.asm
│   ├── test_lex_newline.asm
│   ├── test_lex_utf8.asm
│   ├── test_lex_sourcemap.asm
│   └── test_lex_empty.asm
│
├── parser/
│   ├── test_parse_instr.asm
│   ├── test_parse_operand.asm
│   ├── test_parse_reg.asm
│   ├── test_parse_mem.asm
│   ├── test_parse_mem_sib.asm
│   ├── test_parse_mem_disp.asm
│   ├── test_parse_imm.asm
│   ├── test_parse_label.asm
│   ├── test_parse_local.asm
│   ├── test_parse_section.asm
│   ├── test_parse_global.asm
│   ├── test_parse_extern.asm
│   ├── test_parse_data.asm
│   ├── test_parse_data_str.asm
│   ├── test_parse_struct.asm
│   ├── test_parse_proc.asm
│   ├── test_parse_align.asm
│   ├── test_parse_times.asm
│   ├── test_parse_equ.asm
│   ├── test_parse_expr.asm
│   └── test_parse_multiline.asm
│
├── macro/
│   ├── test_macro_define.asm
│   ├── test_macro_redefine.asm
│   ├── test_macro_undef.asm
│   ├── test_macro_args.asm
│   ├── test_macro_args_default.asm
│   ├── test_macro_args_greedy.asm
│   ├── test_macro_local.asm
│   ├── test_macro_nested.asm
│   ├── test_macro_recursive.asm
│   ├── test_macro_stringify.asm
│   ├── test_macro_paste.asm
│   ├── test_macro_cond.asm
│   ├── test_macro_ifdef.asm
│   ├── test_macro_ifidn.asm
│   ├── test_macro_rep.asm
│   ├── test_macro_rotate.asm
│   ├── test_macro_include.asm
│   ├── test_macro_include_depth.asm
│   ├── test_macro_include_circular.asm
│   └── test_macro_library.asm
│
├── symtable/
│   ├── test_sym_insert.asm
│   ├── test_sym_lookup.asm
│   ├── test_sym_redef.asm
│   ├── test_sym_forward.asm
│   ├── test_sym_forward_unresolved.asm
│   ├── test_sym_local.asm
│   ├── test_sym_global.asm
│   ├── test_sym_extern.asm
│   ├── test_sym_common.asm
│   ├── test_sym_weak.asm
│   ├── test_sym_scope.asm
│   └── test_sym_collision.asm
│
├── expr/
│   ├── test_expr_add.asm
│   ├── test_expr_sub.asm
│   ├── test_expr_mul.asm
│   ├── test_expr_div.asm
│   ├── test_expr_mod.asm
│   ├── test_expr_neg.asm
│   ├── test_expr_and.asm
│   ├── test_expr_or.asm
│   ├── test_expr_xor.asm
│   ├── test_expr_not.asm
│   ├── test_expr_shl.asm
│   ├── test_expr_shr.asm
│   ├── test_expr_prec.asm
│   ├── test_expr_paren.asm
│   ├── test_expr_divzero.asm
│   ├── test_expr_overflow.asm
│   ├── test_expr_symref.asm
│   ├── test_expr_reloc.asm
│   └── test_expr_const_fold.asm
│
├── encoder/
│   │
│   ├── x86/
│   │   ├── test_enc_mov_rr.asm
│   │   ├── test_enc_mov_rm.asm
│   │   ├── test_enc_mov_mr.asm
│   │   ├── test_enc_mov_ri.asm
│   │   ├── test_enc_mov_mi.asm
│   │   ├── test_enc_mov_seg.asm
│   │   ├── test_enc_add.asm
│   │   ├── test_enc_sub.asm
│   │   ├── test_enc_mul.asm
│   │   ├── test_enc_div.asm
│   │   ├── test_enc_and.asm
│   │   ├── test_enc_or.asm
│   │   ├── test_enc_xor.asm
│   │   ├── test_enc_not.asm
│   │   ├── test_enc_neg.asm
│   │   ├── test_enc_shift.asm
│   │   ├── test_enc_jmp.asm
│   │   ├── test_enc_jcc.asm
│   │   ├── test_enc_call.asm
│   │   ├── test_enc_ret.asm
│   │   ├── test_enc_push.asm
│   │   ├── test_enc_pop.asm
│   │   ├── test_enc_lea.asm
│   │   ├── test_enc_xchg.asm
│   │   ├── test_enc_cmpxchg.asm
│   │   ├── test_enc_string.asm
│   │   ├── test_enc_bit.asm
│   │   ├── test_enc_cmov.asm
│   │   ├── test_enc_setcc.asm
│   │   ├── test_enc_system.asm
│   │   ├── test_enc_priv.asm
│   │   ├── test_enc_rex.asm
│   │   ├── test_enc_lock.asm
│   │   ├── test_enc_rep.asm
│   │   ├── test_enc_addr32.asm
│   │   ├── test_enc_addr_modes.asm
│   │   ├── test_enc_sib.asm
│   │   ├── test_enc_disp8.asm
│   │   ├── test_enc_disp32.asm
│   │   ├── test_enc_riprel.asm
│   │   └── test_enc_aesni.asm
│   │
│   └── simd/
│       ├── test_enc_mmx.asm
│       ├── test_enc_sse.asm
│       ├── test_enc_sse2.asm
│       ├── test_enc_sse3.asm
│       ├── test_enc_sse4.asm
│       ├── test_enc_avx.asm
│       ├── test_enc_avx2.asm
│       ├── test_enc_avx512f.asm
│       ├── test_enc_avx512bw.asm
│       ├── test_enc_avx512dq.asm
│       ├── test_enc_avx512vl.asm
│       ├── test_enc_avx512vnni.asm
│       ├── test_enc_avx512bf16.asm
│       ├── test_enc_amx.asm
│       ├── test_enc_mask.asm
│       ├── test_enc_broadcast.asm
│       ├── test_enc_rounding.asm
│       ├── test_enc_evex_vl.asm
│       └── test_enc_fpu.asm
│
├── linker/
│   ├── test_link_symbol.asm
│   ├── test_link_forward.asm
│   ├── test_link_extern.asm
│   ├── test_link_reloc.asm
│   ├── test_link_reloc_abs.asm
│   ├── test_link_reloc_rel.asm
│   ├── test_link_sections.asm
│   ├── test_link_layout.asm
│   ├── test_link_align.asm
│   ├── test_link_dead.asm
│   ├── test_link_multi.asm
│   ├── test_link_circular.asm
│   └── test_link_common.asm
│
└── output/
    ├── test_out_elf_exec.asm
    ├── test_out_elf_obj.asm
    ├── test_out_elf_so.asm
    ├── test_out_elf_hdr.asm
    ├── test_out_elf_sym.asm
    ├── test_out_elf_rela.asm
    ├── test_out_pe_exec.asm
    ├── test_out_pe_hdr.asm
    ├── test_out_flat.asm
    ├── test_out_flat_boot.asm
    ├── test_out_upk.asm
    └── test_out_upk_sign.asm
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
├── lexer_errors/
│   ├── test_err_E101.asm        ; invalid character
│   ├── test_err_E102.asm        ; unterminated string
│   ├── test_err_E103.asm        ; unterminated char
│   ├── test_err_E104.asm        ; invalid escape
│   ├── test_err_E105.asm        ; malformed binary
│   ├── test_err_E106.asm        ; malformed octal
│   ├── test_err_E107.asm        ; malformed hex
│   ├── test_err_E108.asm        ; malformed decimal
│   ├── test_err_E109.asm        ; integer overflow
│   ├── test_err_E110.asm        ; float overflow
│   ├── test_err_E111.asm        ; invalid identifier char
│   ├── test_err_E112.asm        ; identifier too long
│   ├── test_err_E113.asm        ; EOF in comment
│   ├── test_err_E114.asm        ; nested comment depth
│   └── test_err_E115.asm        ; invalid UTF-8
│
├── parser_errors/
│   ├── test_err_E201.asm        ; unexpected token
│   ├── test_err_E202.asm        ; missing operand
│   ├── test_err_E203_E205.asm   ; wrong operand type
│   ├── test_err_E208_E209.asm   ; bracket mismatch
│   ├── test_err_E210_E211.asm   ; operand count
│   ├── test_err_E212.asm        ; invalid addressing
│   ├── test_err_E213.asm        ; base reg not 64-bit
│   ├── test_err_E214.asm        ; RSP as index
│   ├── test_err_E215.asm        ; invalid scale
│   ├── test_err_E221.asm        ; division by zero
│   ├── test_err_E226.asm        ; ambiguous size
│   └── test_err_E227.asm        ; size override conflict
│
├── macro_errors/
│   ├── test_err_E301.asm        ; undefined macro
│   ├── test_err_E302.asm        ; macro redefinition
│   ├── test_err_E303_E304.asm   ; wrong arg count
│   ├── test_err_E306.asm        ; expansion depth
│   ├── test_err_E307.asm        ; recursive macro
│   ├── test_err_E311.asm        ; unterminated macro
│   ├── test_err_E312.asm        ; endmacro without macro
│   ├── test_err_E319.asm        ; library not found
│   └── test_err_E320.asm        ; circular include
│
├── semantic_errors/
│   ├── test_err_E401.asm        ; undefined symbol
│   ├── test_err_E402.asm        ; symbol redefinition
│   ├── test_err_E405.asm        ; forward ref in EQU
│   ├── test_err_E406.asm        ; circular EQU
│   ├── test_err_E410_E411.asm   ; entry point issues
│   ├── test_err_E412.asm        ; extern + local conflict
│   ├── test_err_E419_E420.asm   ; TIMES issues
│   └── test_err_E421.asm        ; EQU not constant
│
├── encoder_errors/
│   ├── test_err_E501.asm        ; size mismatch
│   ├── test_err_E502_E504.asm   ; immediate range
│   ├── test_err_E505.asm        ; displacement range
│   ├── test_err_E506_E507.asm   ; jump range
│   ├── test_err_E508_E509.asm   ; register issues
│   ├── test_err_E513.asm        ; two memory operands
│   ├── test_err_E514_E515.asm   ; REX issues
│   ├── test_err_E516_E518.asm   ; VEX/EVEX issues
│   ├── test_err_E519_E520.asm   ; mask register issues
│   ├── test_err_E526_E528.asm   ; prefix issues
│   ├── test_err_E529_E531.asm   ; invalid prefixes
│   └── test_err_E533_E534.asm   ; mode issues
│
├── linker_errors/
│   ├── test_err_E601.asm        ; undefined external
│   ├── test_err_E602.asm        ; multiple definition
│   ├── test_err_E603.asm        ; section overlap
│   ├── test_err_E604.asm        ; relocation overflow
│   └── test_err_E608.asm        ; circular dependency
│
└── cpu_errors/
    ├── test_err_E701_E710.asm   ; missing SSE/AVX
    ├── test_err_E711_E716.asm   ; missing AVX-512
    ├── test_err_E717_E724.asm   ; missing extensions
    ├── test_err_E725_E726.asm   ; mode restrictions
    ├── test_err_E727_E728.asm   ; privilege violations
    └── test_err_E729_E730.asm   ; deprecated instructions
```

---

## Warning Tests

Every warning code must have:
1. A test that verifies it fires
2. A test that verifies `-Wno-<warning>` suppresses it
3. A test that verifies `-Werror` promotes it to error

```
tests/warning/
├── test_warn_W201.asm
├── test_warn_W202.asm
├── test_warn_W301.asm
├── test_warn_W501.asm
├── test_warn_W503.asm
├── test_warn_W505.asm
├── test_warn_W601.asm
├── test_warn_W702.asm
├── test_warn_suppress.asm
└── test_warn_werror.asm
```

---

## Integration Tests

```
tests/integration/
│
├── hello/
│   ├── hello.asm              ; simplest possible program
│   └── hello.expect           ; expected output
│
├── selfhost/
│   ├── test_selfhost.asm      ; utasm assembles itself
│   └── test_selfhost_cmp.asm  ; output matches reference
│
├── elf/
│   ├── test_elf_exec.asm      ; ELF executable runs correctly
│   ├── test_elf_shared.asm    ; shared library linking
│   ├── test_elf_static.asm    ; static linking
│   └── test_elf_debug.asm     ; DWARF info readable
│
├── pe/
│   ├── test_pe_uefi.asm       ; UEFI application valid
│   └── test_pe_sign.asm       ; signed PE validates
│
├── boot/
│   ├── test_boot_mbr.asm      ; MBR boots in emulator
│   └── test_boot_uefi.asm     ; UEFI boots in emulator
│
├── upk/
│   ├── test_upk_build.asm     ; package builds correctly
│   └── test_upk_sign.asm      ; package signature valid
│
├── simd/
│   ├── test_simd_avx512.asm   ; AVX-512 executes correctly
│   ├── test_simd_vnni.asm     ; VNNI dot product correct
│   └── test_simd_result.asm   ; verify computed values
│
└── multifile/
    ├── test_multi_a.asm
    ├── test_multi_b.asm
    └── test_multi_main.asm
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
├── reg_001.asm
└── reg_NNN.asm    ; grows for the lifetime of utasm
```

---

## Fuzz Tests

Random inputs. utasm must never crash, hang, or produce undefined behaviour.

**Invariants that must hold regardless of input:**
- Never segfaults
- Never hangs (enforced by runner_timeout.asm)
- Always exits 0 (success) or 1 (error)
- Error messages always contain valid line/col numbers

```
tests/fuzz/
├── fuzz_runner.asm
├── fuzz_lexer.asm
├── fuzz_parser.asm
├── fuzz_macro.asm
├── fuzz_encoder.asm
├── fuzz_expr.asm
├── seeds/
│   ├── seed_001.asm    ; edge cases for lexer
│   ├── seed_002.asm    ; edge cases for parser
│   └── ...
└── corpus/             ; accumulated fuzz findings (grows as fuzzer runs)
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
├── bench_runner.asm
├── bench_lexer.asm
├── bench_parser.asm
├── bench_macro.asm
├── bench_encoder.asm
├── bench_linker.asm
├── bench_large.asm          ; 100k line file benchmark
├── bench_selfhost.asm       ; time to assemble utasm itself
└── bench_results/           ; historical benchmark data (tsv)
```

---

## Stress Tests

```
tests/stress/
├── stress_deep_macro.asm     ; maximum macro nesting
├── stress_long_expr.asm      ; maximum expression depth
├── stress_many_symbols.asm   ; 1M symbol table
├── stress_many_sections.asm  ; maximum sections
├── stress_large_binary.asm   ; maximum output size
├── stress_many_errors.asm    ; maximum error recovery
└── stress_parallel.asm       ; parallel assembly stress
```

---

## Fixtures

```
tests/fixtures/
├── inc/
│   ├── fixture_basic.inc
│   ├── fixture_simd.inc
│   └── fixture_cpu.inc
├── obj/
│   └── prebuilt_*.obj        ; prebuilt objects for link tests
└── expect/
    └── *.bin                 ; expected binary outputs
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
2. Name: `test_<module>_<behaviour>.asm`
3. Add a header:

```asm
; TEST: test_lex_ident
; Category: unit/lexer
; Tests:    identifier scanning — alphanumeric, underscore, leading underscore
; Expects:  token stream matches fixtures/expect/lex_ident.bin
```

4. Add to runner manifest in `utasm.toml`
5. Run `bash scripts/test.sh unit/lexer/test_lex_ident` and verify it passes

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
