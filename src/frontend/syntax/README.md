# frontend/syntax/ — statements: NASM's parser, and MASM, fasm, GNU as on top

The parser reads one **statement** at a time from the preprocessor's
tokens and either handles it completely (a label, a directive, data) or
returns it as an `INST` for the encoder (an instruction). The NASM parser
is the base; the other syntaxes are layers that recognise their own
constructs and either act on them directly or **rewrite** them into
NASM-syntax text that is read next (`prep_push_buffer`, numbered as the
line that produced it), so one encoder, one set of diagnostics and one
listing serve every syntax.

```
            tokens (frontend/preproc)
                     │
                     ▼
     nasm/parser.s: parser_parse_instruction
        │   a word of another syntax? ──▶ masm/ , fasm/ , gas/ (directive,
        │                                  macro, AT&T statement): handled
        │                                  here, or rewritten and pushed back
        ├─ label            → semantic/symtable.s (and namespace / proc rules)
        ├─ directive / data → handled: sections, db..dz, times, equ, struc,
        │                     global/extern, align, bits, org, cfi ...
        └─ instruction      → INST (mnemonic, prefixes, ≤ 4 operands) → encode/
```

## The NASM parser (`nasm/parser.s` and its parts in `nasm/parser/`)

### A statement (`parser_parse_instruction`)

1. **Tables**: the target's mnemonic and register tables
   (`parser_get_arch_tables`: encode/x86, aarch64, riscv64).
2. **The first word**: a label (`name:`, or a name alone that is not a
   mnemonic: NASM's orphan-label warning), a numeric local label (GNU's
   `1:` / `1f` / `1b`: `parser_numlabel_*`), a bracketed directive
   (`[section .text]`), a directive or pseudo-op (`parser_handle_pseudo_op`),
   a word of an enabled syntax layer (MASM, fasm, GNU, namespaces, procs),
   or a mnemonic (`parser_lookup_mnemonic`: a hash index built on first
   use).
3. **Prefixes** (`parser_check_prefix`): `lock rep repe repne xacquire
   xrelease`, segment overrides, `a16 a32 a64 o16 o32 o64`, NASM's
   encoding prefixes `{rex}` `{vex}` `{vex2}` `{vex3}` `{evex}`, APX's `{nf}`
   ...
4. **Operands** (`parser_parse_operand`, up to four):
   - a **register** (`parser_parse_reg_info`, by hash), with AVX-512's
     `{k1}{z}` decorators (`parser_parse_decorator`);
   - **memory** (`parser_parse_mem_operand`): `[base + index*scale +
     disp]` in any order NASM accepts, a size (`dword`, `xmmword` ...),
     `rel` / `abs`, a segment, VSIB, `{1to16}` broadcasts, MPX's MIB form,
     MASM's `x[rbx]` and typed struct access (`[rbx:thread_t].field`);
   - an **immediate or label**: an expression, `strict`, `near` / `far` /
     `short`, `seg:off`, `wrt ..plt` & co. (`parser_handle_reloc_modifier`);
   - `{sae}`, `{rn-sae}` ..., `{dfv=...}` (APX's ccmp / ctest).
5. **Checks NASM makes**: a size where none can be inferred
   (`parser_check_size`), `lock` on what cannot be locked
   (`parser_check_lock`), HLE prefixes (`parser_check_hle`), complex FP16
   destinations, MIB indexes.
6. The INST goes back to `_start`, which encodes it.

### Expressions (`parser_evaluate_expression` and the levels below it)

Precedence climbing over NASM's levels (`parser_eval_level`, `?:`, `||`,
`^^`, `&&`, comparisons, `|`, `^`, `&`, shifts, `+ -`, `* / // % %%`,
unary), then terms and factors (numbers, symbols, `$`, `$$`, strings as
numbers, `seg`, `sizeof` & co., NASM's float and ilog2 functions).

Every value carries what it **depends on**: a coefficient of `$` (so
`label - $` is PC-relative), the symbol it is relative to, and whether a
name in it is not defined yet. That lets the parser:

- keep NASM's **scalar rule** (`expr_scalar`: a label in `*`, `/`,
  shifts ... is an error, before and after its definition);
- **defer** what cannot be known yet (`parser_defer_record`: an `equ` of a
  later label, a `times` count) and work it out at the end, once the code
  is laid out (`parser_late_equs`, `parser_late_aliases`);
- tell core/known.s which values a second pass would get right.

### Directives and data (pseudo-ops)

| Directive | Function |
| --- | --- |
| `db dw dd dq dt do dy dz`, strings, UTF-16/32, floats, BCD, `dup` | `parser_emit_data_*`, `parser_data_*`, `parser_data_string`, `parser_utf_*`, lib/float.s |
| `resb .. resz`, `?` | `parser_handle_res` |
| `times` | `parser_handle_times` |
| `equ`, `org` | `parser_handle_equ`, `parser_handle_org` |
| `section` / `segment` and their attributes (`align=`, `progbits`, `vstart=`, `follows=`, COFF's, GNU's flags), `absolute`, `sectalign` | `parser_handle_section_directive`, `parser_section_attrs`, `parser_absolute`, `parser_sectalign` |
| `global`, `extern`, `common`, `static`, `weak`, `required`, visibility, `:function` / `:data` | `parser_handle_visibility`, `parser_handle_extern`, `parser_handle_common` |
| `align`, `alignb`, `alignmode` | `parser_handle_align`, `parser_alignb`, `parser_alignmode` (optimize/align.s) |
| `bits`, `use16/32/64`, `cpu`, `default rel/abs` | `parser_handle_bits`, `parser_cpu_num`, `parser_handle_default` |
| `struc` / `endstruc`, `istruc` / `at` / `iend` | `parser_parse_struc`, `parser_istruc`, `parser_at`, `parser_iend` |
| `incbin` | `parser_incbin` |
| `.cfi_*` | `parser_cfi` (debug/cfi.s) |
| `[map ...]` | `parser_map_words` (object/map.s) |

### At the end

`parser_finish` (open strucs, required externs ...); after layout
`parser_late_equs`, `parser_late_aliases`, `parser_sizes` (GNU's `.size`).

## The other syntaxes

| Folder | Turned on by | What it adds |
| --- | --- | --- |
| `masm/masm.s` (4,598) | `%use masm` | `PROC` / `ENDP` with parameters, `USES`, frames, `LOCAL`; `INVOKE` (System V or win64 registers); `.IF .ELSEIF .ELSE .ENDIF .WHILE .REPEAT .UNTIL .BREAK .CONTINUE`; `.CODE .DATA .DATA? .CONST`, `EXTERNDEF`, `PROTO` / `OPTION` taken; typed data and `STRUCT`, `PTR`, `OFFSET`, `SIZEOF`, `LENGTHOF`, `TYPE` |
| `fasm/fasm.s` (906) | fasm's words, where NASM has none | `virtual [at ADDR]` ... `end virtual` (assembled into a space of its own, written nowhere), `load` / `store` (read and patch assembled bytes at assembly time), `format`, `entry`, `segment` |
| `gas/gas.s` (2,189) | a line starting with a GNU directive | `.text .data .bss .section .pushsection .popsection .previous`, `.ascii .asciz .string .zero .skip .space .fill .uleb128 .sleb128 .octa`, `.align .balign .p2align` (with MAX), `.equ .set .equiv`, `.type .size .hidden .internal .protected`, `.comm .lcomm`, `.org`, `.code16/32/64`, `.ident`, `.intel_syntax`, `.file` / `.loc` (debug/line.s); renames the ones NASM has (`.globl` → global, `.byte` → db) |
| `gas/gas_macro.s` (2,279) | GNU's macro directives | `.macro` / `.endm` (`\P`, defaults, `:req`, `:vararg`, `\@`, `\()`), `.exitm`, `.purgem`, `.rept`, `.irp`, `.irpc`, `.if .ifeq .ifgt ... .ifdef .ifb .ifc .ifeqs`, `.elseif .else .endif` |
| `gas/att.s` (2,140) | `.att_syntax`, `--att` | AT&T statements rewritten to Intel: operand order reversed, `%reg`, `$imm`, `disp(base,index,scale)`, `*` indirect, size suffixes (`movl`, `fadds`, `fiaddl`), GNU's own mnemonics (`movzbl`, `cltq`, `ljmp` ...), `sym@PLT` & co. → `wrt ..plt`, SysV's x87 `fsub`/`fsubr` swap, prefixes on their own line |

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `nasm/parser.s` | 977 | `parser_parse_instruction`: a statement (above); the rest of it in the `nasm/parser/` parts, %included in this order: |
| `nasm/parser/operand.inc` | 779 | one operand: register, immediate, memory or far pointer (parser_parse_operand), a register's size and kind |
| `nasm/parser/expr.inc` | 2,711 | the expression evaluator: the precedence levels, terms and factors, values deferred to a later pass, symbol classes |
| `nasm/parser/memory.inc` | 1,498 | memory operands: relocation modifiers (wrt, rel, abs), base / index / scale terms, rip, MIB, decorators ({k}, {z}, {1toN}, {dfv=}) |
| `nasm/parser/labels.inc` | 496 | numeric labels (1:, 1b, 1f), positional labels, GNU symbol names, .size |
| `nasm/parser/section_attrs.inc` | 496 | statement words, COFF section attributes and classes, section attributes, segment overrides, and their names |
| `nasm/parser/checks.inc` | 644 | register and mnemonic lookup (the hash indexes), operand size checks, lock / HLE / prefix checks |
| `nasm/parser/struc.inc` | 855 | struc / endstruc, defining a label (local names), GNU names, .equ / .set |
| `nasm/parser/pseudo.inc` | 1,720 | the pseudo-instruction dispatch; string, UTF-16 / 32, float and BCD data; the float and ilog2 functions; incbin |
| `nasm/parser/directives.inc` | 987 | bits / cpu, sectalign, absolute, alignb, istruc / at / iend, cfi; the expression operator tables and the parser's state |
| `nasm/parser/times_align.inc` | 927 | times, align, typed struc fields ([reg:TYPE].field), MASM fields, mnemonic tests |
| `nasm/parser/equ.inc` | 442 | org, equ, the late equs and aliases |
| `nasm/parser/data.inc` | 925 | db / dw / dd / dq: item lists, dup, sizes, symbols, field widths, the zeroing warnings |
| `nasm/parser/symbols.inc` | 1,749 | resb .., extern, default, section / segment, global / weak / visibility, common, parser_finish; the directive word tables (cpu_levels) |
| `masm/masm.s` | 4,588 | MASM's procedures, INVOKE, runtime control flow, sections, typed data |
| `fasm/fasm.s` | 906 | fasm's virtual / load / store, format, entry, segment |
| `gas/gas.s` | 2,188 | GNU as's directives |
| `gas/gas_macro.s` | 2,279 | GNU as's macros, repetitions and conditionals |
| `gas/att.s` | 2,140 | AT&T syntax |

## Entry points

| Symbol | Used by |
| --- | --- |
| `parser_parse_instruction` | main/utasm.s (once per statement) |
| `parser_default_section`, `parser_finish`, `gas_finish`, `gas_macro_finish`, `masm_finish`, `fasm_finish` | main/utasm.s |
| `parser_late_equs`, `parser_late_aliases`, `parser_sizes` | link/linker.s |
| `parser_evaluate_expression`, `parser_evaluate_pp` | frontend/preproc (`%if`, `%assign`), core/known.s |
| `parser_define_label`, `parser_is_register`, `parser_is_mnemonic` ... | semantic/, frontend/preproc |
| `asm_bits`, `masm_enabled`, `abs_section` | encode/x86, object/ |

## Depends on

frontend/preproc (every token), core/ (sections, emitting data, the
second pass), semantic/ (symbols, namespaces, procs), encode/ (mnemonic
and register tables), optimize/ (alignment, jump records), debug/ (cfi,
line), object/ (listing, map), diag/, lib/ (strings, floats).

## Status

Complete for NASM 3.01's syntax, and for the MASM / fasm / GNU as features
listed above (each measured: see Tests). `parser.s` is one object: its
13 parts in `nasm/parser/` are %included in order, cut where its
functions were (the object is the same, byte for byte). `make` rebuilds
`parser.s` when one changes.

## Tests

`tests/compat/run_all.py`: *encoder corpus*, *operand shapes*,
*addresses*, *bits 32 / bits 16* (instructions and operands), *data
forms*, *expressions*, *sections/link*, *label operands*, *diagnostics*,
*rejections*, *typed strucs*; per syntax *masm features*, *fasm features*,
*gas* (against GNU as), *att* (each line against GNU as).
