#!/usr/bin/env python3
"""
mkstubs.py — create all missing stub .s files and directory scaffolding
for utasm Phase 0.  Safe to re-run; skips files that already exist.
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ──────────────────────────────────────────────────────────────────────────────
# 1.  Directories to create (mkdir -p)
# ──────────────────────────────────────────────────────────────────────────────
DIRS = [
    # build
    "build/gen0", "build/gen1", "build/gen2",
    # docs
    "docs",
    # include
    "include/arch",
    # core
    "core",
    # frontend
    "frontend/lexer/number",
    "frontend/parser/operand",
    "frontend/macro/cond",
    # middle
    "middle/semantic",
    "middle/symtable",
    "middle/expr",
    # backend encoder
    "backend/encoder/x86",
    "backend/encoder/simd/avx512",
    "backend/encoder/aarch64",
    "backend/encoder/riscv64",
    "backend/encoder/prefix",
    "backend/encoder/tables",
    # backend other
    "backend/isa",
    "backend/linker/reloc",
    "backend/output/elf",
    "backend/output/pe",
    "backend/output/flat",
    "backend/output/upk",
    "backend/output/listing",
    # error
    "error/format",
    "error/recover",
    # cpu
    "cpu/profiles",
    # misc top-level
    "debug", "optimizer", "selfpatch", "profiler",
    # tools
    "tools/disasm", "tools/inspector", "tools/symdump",
    # io / lib / host
    "io", "lib", "host",
    # scripts
    "scripts",
    # tests — unit
    "tests/unit/lexer",
    "tests/unit/parser",
    "tests/unit/macro",
    "tests/unit/symtable",
    "tests/unit/expr",
    "tests/unit/encoder/x86",
    "tests/unit/encoder/simd",
    "tests/unit/encoder/aarch64",
    "tests/unit/encoder/riscv64",
    "tests/unit/linker",
    "tests/unit/output",
    # tests — error buckets
    "tests/error/E1xx",
    "tests/error/E2xx",
    "tests/error/E3xx",
    "tests/error/E4xx",
    "tests/error/E5xx",
    "tests/error/E6xx",
    "tests/error/E7xx",
    "tests/error/E9xx",
    "tests/error/multi",
    # tests — other
    "tests/warning",
    "tests/integration/hello",
    "tests/integration/selfhost",
    "tests/integration/elf",
    "tests/integration/pe",
    "tests/integration/boot",
    "tests/integration/upk",
    "tests/integration/simd",
    "tests/integration/multifile",
    "tests/integration/crossarch",
    "tests/integration/selfpatch",
    "tests/regression",
    "tests/fuzz/seeds",
    "tests/fuzz/corpus",
    "tests/perf/results",
    "tests/stress",
    "tests/fixtures/inc",
    "tests/fixtures/obj",
    "tests/fixtures/expect",
]

# ──────────────────────────────────────────────────────────────────────────────
# 2.  Stub .s files to create  (path → phase comment)
# ──────────────────────────────────────────────────────────────────────────────
# Format: ("relative/path/to/file.s", "Phase N — short description")
STUBS = [
    # ── core ──
    ("core/globals.s",                  "Phase 3 — global assembler state"),
    ("core/memory.s",                   "Phase 2 — memory management wrappers"),

    # ── lib ──
    ("lib/fmt.s",                       "Phase 1 — formatted string output"),
    ("lib/sort.s",                      "Phase 1 — sort utilities"),
    ("lib/hash.s",                      "Phase 2 — FNV-1a hash table"),
    ("lib/math.s",                      "Phase 2 — integer math helpers"),
    ("lib/list.s",                      "Phase 2 — intrusive linked list"),
    ("lib/vec.s",                       "Phase 2 — growable array"),

    # ── host ──
    ("host/syscall.s",                  "Phase 2 — raw Linux syscall wrappers"),

    # ── io ──
    ("io/file.s",                       "Phase 2 — file I/O"),
    ("io/buf.s",                        "Phase 2 — buffered I/O"),
    ("io/stdout.s",                     "Phase 2 — stdout helpers"),
    ("io/stderr.s",                     "Phase 2 — stderr helpers"),
    ("io/mmap.s",                       "Phase 2 — mmap helpers"),

    # ── error ──
    ("error/warnings.s",                "Phase 1 — warning message strings"),
    ("error/hints.s",                   "Phase 1 — hint message strings"),
    ("error/notes.s",                   "Phase 1 — note message strings"),
    ("error/record.s",                  "Phase 1 — ErrorRecord alloc/init"),
    ("error/count.s",                   "Phase 1 — error/warning counters"),
    ("error/dedup.s",                   "Phase 1 — duplicate suppression"),
    ("error/filter.s",                  "Phase 1 — severity filter"),
    ("error/chain.s",                   "Phase 1 — error chain linking"),
    ("error/report.s",                  "Phase 1 — batch report entry point"),
    ("error/flush.s",                   "Phase 1 — flush error buffer to stderr"),
    ("error/suggest.s",                 "Phase 1 — suggestion engine"),
    ("error/attach.s",                  "Phase 1 — attach notes/hints to records"),
    ("error/format/header.s",           "Phase 1 — format: filename+line header"),
    ("error/format/location.s",         "Phase 1 — format: col indicator"),
    ("error/format/source.s",           "Phase 1 — format: source line text"),
    ("error/format/underline.s",        "Phase 1 — format: ^^^ underline"),
    ("error/format/note.s",             "Phase 1 — format: note line"),
    ("error/format/hint.s",             "Phase 1 — format: hint line"),
    ("error/format/format.s",           "Phase 1 — format: top-level dispatcher"),
    ("error/recover/lexer.s",           "Phase 1 — lexer error recovery"),
    ("error/recover/parser.s",          "Phase 1 — parser error recovery"),
    ("error/recover/macro.s",           "Phase 1 — macro error recovery"),
    ("error/recover/encoder.s",         "Phase 1 — encoder error recovery"),
    ("error/recover/recover.s",         "Phase 1 — recovery entry point"),

    # ── frontend / lexer ──
    ("frontend/lexer/chars.s",          "Phase 3 — character class tables"),
    ("frontend/lexer/utf8.s",           "Phase 3 — UTF-8 decoder"),
    ("frontend/lexer/buffer.s",         "Phase 3 — source buffer management"),
    ("frontend/lexer/number/dec.s",     "Phase 3 — decimal literal scanner"),
    ("frontend/lexer/number/hex.s",     "Phase 3 — hex literal scanner"),
    ("frontend/lexer/number/bin.s",     "Phase 3 — binary literal scanner"),
    ("frontend/lexer/number/oct.s",     "Phase 3 — octal literal scanner"),
    ("frontend/lexer/number/number.s",  "Phase 3 — numeric literal dispatcher"),
    ("frontend/lexer/string.s",         "Phase 3 — string literal scanner"),
    ("frontend/lexer/comment.s",        "Phase 3 — comment skipper"),
    ("frontend/lexer/ident.s",          "Phase 3 — identifier/keyword scanner"),
    ("frontend/lexer/token.s",          "Phase 3 — Token struc helpers"),

    # ── frontend / parser ──
    ("frontend/parser/ast.s",           "Phase 5 — ASTNode allocation helpers"),
    ("frontend/parser/label.s",         "Phase 5 — label statement parser"),
    ("frontend/parser/section.s",       "Phase 5 — SECTION directive parser"),
    ("frontend/parser/directive.s",     "Phase 5 — generic directive parser"),
    ("frontend/parser/data.s",          "Phase 5 — DB/DW/DD/DQ parser"),
    ("frontend/parser/struct.s",        "Phase 5 — STRUC/ENDSTRUC parser"),
    ("frontend/parser/proc.s",          "Phase 5 — PROC/ENDP parser"),
    ("frontend/parser/operand/reg.s",   "Phase 5 — register operand parser"),
    ("frontend/parser/operand/imm.s",   "Phase 5 — immediate operand parser"),
    ("frontend/parser/operand/mem.s",   "Phase 5 — memory operand parser"),
    ("frontend/parser/operand/addr.s",  "Phase 5 — address expression parser"),
    ("frontend/parser/operand/operand.s","Phase 5 — operand dispatcher"),
    ("frontend/parser/instr.s",         "Phase 5 — instruction statement parser"),
    ("frontend/parser/expr.s",          "Phase 5 — expression parser (Pratt)"),
    ("frontend/parser/recover.s",       "Phase 5 — parser panic recovery"),

    # ── frontend / macro ──
    ("frontend/macro/table.s",          "Phase 6 — macro name table"),
    ("frontend/macro/define.s",         "Phase 6 — %define handler"),
    ("frontend/macro/args.s",           "Phase 6 — macro argument processing"),
    ("frontend/macro/local.s",          "Phase 6 — %local label generation"),
    ("frontend/macro/cond/def.s",       "Phase 6 — %ifdef/%ifndef"),
    ("frontend/macro/cond/expr.s",      "Phase 6 — %if expression"),
    ("frontend/macro/cond/str.s",       "Phase 6 — %ifidn/%ifidni"),
    ("frontend/macro/cond/cond.s",      "Phase 6 — conditional dispatcher"),
    ("frontend/macro/rep.s",            "Phase 6 — %rep/%endrep"),
    ("frontend/macro/rotate.s",         "Phase 6 — %rotate"),
    ("frontend/macro/stringify.s",      "Phase 6 — %str stringification"),
    ("frontend/macro/paste.s",          "Phase 6 — ## token paste"),
    ("frontend/macro/include.s",        "Phase 6 — %include handler"),
    ("frontend/macro/library.s",        "Phase 6 — macro library loader"),
    ("frontend/macro/chain.s",          "Phase 6 — macro call chaining"),
    ("frontend/macro/purge.s",          "Phase 6 — %undef / purge"),
    ("frontend/macro/expand.s",         "Phase 6 — macro expansion engine"),

    # ── middle / expr ──
    ("middle/expr/arith.s",             "Phase 4 — arithmetic operators"),
    ("middle/expr/bitwise.s",           "Phase 4 — bitwise operators"),
    ("middle/expr/compare.s",           "Phase 4 — comparison operators"),
    ("middle/expr/logical.s",           "Phase 4 — logical operators"),
    ("middle/expr/const.s",             "Phase 4 — constant folding"),
    ("middle/expr/overflow.s",          "Phase 4 — overflow detection"),
    ("middle/expr/reloc.s",             "Phase 4 — relocatable expressions"),
    ("middle/expr/unary.s",             "Phase 4 — unary operators"),

    # ── middle / symtable ──
    ("middle/symtable/hash.s",          "Phase 7 — symbol hash table"),
    ("middle/symtable/scope.s",         "Phase 7 — scope stack"),
    ("middle/symtable/insert.s",        "Phase 7 — symbol insertion"),
    ("middle/symtable/lookup.s",        "Phase 7 — symbol lookup"),
    ("middle/symtable/resolve.s",       "Phase 7 — forward-ref resolution"),
    ("middle/symtable/global.s",        "Phase 7 — GLOBAL symbol handling"),
    ("middle/symtable/local.s",         "Phase 7 — local symbol handling"),
    ("middle/symtable/common.s",        "Phase 7 — COMMON symbol handling"),
    ("middle/symtable/weak.s",          "Phase 7 — WEAK symbol handling"),
    ("middle/symtable/dump.s",          "Phase 7 — symbol table dump (debug)"),

    # ── middle / semantic ──
    ("middle/semantic/size.s",          "Phase 7 — operand size inference"),
    ("middle/semantic/type.s",          "Phase 7 — type compatibility checks"),
    ("middle/semantic/scope.s",         "Phase 7 — semantic scope validation"),
    ("middle/semantic/proc.s",          "Phase 7 — procedure semantic checks"),
    ("middle/semantic/instr.s",         "Phase 7 — instruction semantic checks"),
    ("middle/semantic/operand.s",       "Phase 7 — operand semantic checks"),
    ("middle/semantic/data.s",          "Phase 7 — data directive checks"),

    # ── backend / encoder tables ──
    ("backend/encoder/tables/reg.s",    "Phase 8 — register encoding tables"),
    ("backend/encoder/tables/modrm.s",  "Phase 8 — ModRM encoding table"),
    ("backend/encoder/tables/sib.s",    "Phase 8 — SIB encoding table"),
    ("backend/encoder/tables/opcode.s", "Phase 8 — opcode map"),
    ("backend/encoder/tables/features.s","Phase 8 — per-instruction CPU feature table"),

    # ── backend / encoder prefix ──
    ("backend/encoder/prefix/rex.s",    "Phase 8 — REX prefix builder"),
    ("backend/encoder/prefix/vex.s",    "Phase 8 — VEX prefix builder"),
    ("backend/encoder/prefix/evex.s",   "Phase 8 — EVEX prefix builder"),
    ("backend/encoder/prefix/lock.s",   "Phase 8 — LOCK prefix validation"),
    ("backend/encoder/prefix/rep.s",    "Phase 8 — REP/REPE/REPNE prefix"),

    # ── backend / encoder x86 ──
    ("backend/encoder/x86/mov.s",       "Phase 8 — MOV family encoders"),
    ("backend/encoder/x86/arith.s",     "Phase 8 — ADD/SUB/MUL/DIV encoders"),
    ("backend/encoder/x86/logic.s",     "Phase 8 — AND/OR/XOR/NOT encoders"),
    ("backend/encoder/x86/shift.s",     "Phase 8 — SHL/SHR/SAR/ROL/ROR encoders"),
    ("backend/encoder/x86/jump.s",      "Phase 8 — Jcc/JMP encoders"),
    ("backend/encoder/x86/call.s",      "Phase 8 — CALL/RET encoders"),
    ("backend/encoder/x86/stack.s",     "Phase 8 — PUSH/POP encoders"),
    ("backend/encoder/x86/string.s",    "Phase 8 — MOVS/STOS/LODS/SCAS encoders"),
    ("backend/encoder/x86/bit.s",       "Phase 8 — BT/BTS/BTR/BTC encoders"),
    ("backend/encoder/x86/cmov.s",      "Phase 8 — CMOVcc encoders"),
    ("backend/encoder/x86/setcc.s",     "Phase 8 — SETcc encoders"),
    ("backend/encoder/x86/flag.s",      "Phase 8 — flag instruction encoders"),
    ("backend/encoder/x86/io.s",        "Phase 8 — IN/OUT encoders"),
    ("backend/encoder/x86/system.s",    "Phase 8 — SYSCALL/SYSRET/CPUID encoders"),
    ("backend/encoder/x86/priv.s",      "Phase 8 — privileged instruction encoders"),
    ("backend/encoder/x86/misc.s",      "Phase 8 — miscellaneous encoders"),
    ("backend/encoder/x86/crypto.s",    "Phase 8 — AES-NI/SHA encoders"),

    # ── backend / encoder simd ──
    ("backend/encoder/simd/mmx.s",      "Phase 8 — MMX encoders"),
    ("backend/encoder/simd/sse.s",      "Phase 8 — SSE encoders"),
    ("backend/encoder/simd/sse2.s",     "Phase 8 — SSE2 encoders"),
    ("backend/encoder/simd/sse3.s",     "Phase 8 — SSE3/SSSE3 encoders"),
    ("backend/encoder/simd/sse4.s",     "Phase 8 — SSE4.1/4.2 encoders"),
    ("backend/encoder/simd/avx.s",      "Phase 8 — AVX encoders"),
    ("backend/encoder/simd/avx2.s",     "Phase 8 — AVX2 encoders"),
    ("backend/encoder/simd/avx512/avx512.s", "Phase 8 — AVX-512F encoders"),
    ("backend/encoder/simd/avx512/bw.s",     "Phase 8 — AVX-512BW encoders"),
    ("backend/encoder/simd/avx512/dq.s",     "Phase 8 — AVX-512DQ encoders"),
    ("backend/encoder/simd/avx512/vl.s",     "Phase 8 — AVX-512VL encoders"),
    ("backend/encoder/simd/avx512/vnni.s",   "Phase 8 — AVX-512VNNI encoders"),
    ("backend/encoder/simd/avx512/bf16.s",   "Phase 8 — AVX-512BF16 encoders"),
    ("backend/encoder/simd/amx.s",      "Phase 8 — AMX tile encoders"),
    ("backend/encoder/simd/fpu.s",      "Phase 8 — x87 FPU encoders"),
    ("backend/encoder/dispatch.s",      "Phase 8 — encoder dispatch table"),

    # ── backend / encoder aarch64 extensions ──
    ("backend/encoder/aarch64/neon.s",  "Phase 10 — NEON SIMD encoders"),
    ("backend/encoder/aarch64/sve.s",   "Phase 10 — SVE/SVE2 encoders"),

    # ── backend / encoder riscv64 extensions ──
    ("backend/encoder/riscv64/m.s",     "Phase 11 — RV64M multiply/divide"),
    ("backend/encoder/riscv64/a.s",     "Phase 11 — RV64A atomic instructions"),
    ("backend/encoder/riscv64/fd.s",    "Phase 11 — RV64F/D float instructions"),
    ("backend/encoder/riscv64/v.s",     "Phase 11 — RVV vector instructions"),
    ("backend/encoder/riscv64/relax.s", "Phase 11 — linker relaxation stubs"),

    # ── backend / isa ──
    # (amd64.s, aarch64.s, riscv64.s already exist — no stubs needed)

    # ── backend / linker ──
    ("backend/linker/section.s",        "Phase 12 — section table management"),
    ("backend/linker/symbol.s",         "Phase 12 — linker symbol resolution"),
    ("backend/linker/reloc/abs.s",      "Phase 12 — absolute relocation"),
    ("backend/linker/reloc/rel.s",      "Phase 12 — PC-relative relocation"),
    ("backend/linker/reloc/got.s",      "Phase 12 — GOT relocation"),
    ("backend/linker/reloc/plt.s",      "Phase 12 — PLT relocation"),
    ("backend/linker/reloc/tls.s",      "Phase 12 — TLS relocation"),
    ("backend/linker/layout.s",         "Phase 12 — section layout / VMA assignment"),
    ("backend/linker/merge.s",          "Phase 12 — section merging (COMDAT)"),
    ("backend/linker/dead.s",           "Phase 12 — dead section elimination"),
    ("backend/linker/map.s",            "Phase 12 — map file emitter"),

    # ── backend / output ──
    ("backend/output/output.s",         "Phase 13 — output format dispatcher"),
    ("backend/output/elf/header.s",     "Phase 13 — ELF header emitter"),
    ("backend/output/elf/phdr.s",       "Phase 13 — ELF program headers"),
    ("backend/output/elf/shdr.s",       "Phase 13 — ELF section headers"),
    ("backend/output/elf/symtab.s",     "Phase 13 — ELF symbol table"),
    ("backend/output/elf/rela.s",       "Phase 13 — ELF RELA entries"),
    ("backend/output/elf/strtab.s",     "Phase 13 — ELF string table"),
    ("backend/output/elf/dynamic.s",    "Phase 13 — ELF dynamic segment"),
    ("backend/output/elf/note.s",       "Phase 13 — ELF note sections"),
    ("backend/output/pe/dos.s",         "Phase 13 — PE DOS stub"),
    ("backend/output/pe/header.s",      "Phase 13 — PE COFF header"),
    ("backend/output/pe/optional.s",    "Phase 13 — PE optional header"),
    ("backend/output/pe/section.s",     "Phase 13 — PE section table"),
    ("backend/output/pe/reloc.s",       "Phase 13 — PE base relocations"),
    ("backend/output/pe/export.s",      "Phase 13 — PE export directory"),
    ("backend/output/pe/import.s",      "Phase 13 — PE import directory"),
    ("backend/output/pe/cert.s",        "Phase 13 — PE security certificate"),
    ("backend/output/flat/boot.s",      "Phase 13 — flat binary boot sector"),
    ("backend/output/flat/map.s",       "Phase 13 — flat binary map output"),
    ("backend/output/upk/header.s",     "Phase 13 — UPK package header"),
    ("backend/output/upk/meta.s",       "Phase 13 — UPK metadata block"),
    ("backend/output/upk/deps.s",       "Phase 13 — UPK dependency table"),
    ("backend/output/upk/sign.s",       "Phase 13 — UPK signing"),
    ("backend/output/upk/compress.s",   "Phase 13 — UPK compression"),

    # ── cpu ──
    ("cpu/profiles/server.s",           "Phase 9 — SERVER CPU profile"),
    ("cpu/profiles/zen4.s",             "Phase 9 — ZEN4 CPU profile"),
    ("cpu/profiles/spr.s",              "Phase 9 — Sapphire Rapids CPU profile"),
    ("cpu/profiles/custom.s",           "Phase 9 — CUSTOM CPU profile template"),
    ("cpu/profiles/profiles.s",         "Phase 9 — CPU profile dispatch table"),
    ("cpu/validate.s",                  "Phase 9 — per-instruction CPU validation"),
    ("cpu/errata.s",                    "Phase 9 — CPU errata workarounds"),
    ("cpu/errata.s",                    "Phase 9 — CPU errata workarounds"),
    ("cpu/perf.s",                      "Phase 9 — perf hint tables"),
    ("cpu/cpu.s",                       "Phase 9 — cpu module entry point"),

    # ── debug ──
    ("debug/cu.s",                      "Phase 14 — DWARF compilation unit"),
    ("debug/die.s",                     "Phase 14 — DWARF debug info entries"),
    ("debug/line.s",                    "Phase 14 — DWARF line number program"),
    ("debug/abbrev.s",                  "Phase 14 — DWARF abbreviation table"),
    ("debug/aranges.s",                 "Phase 14 — DWARF address ranges"),
    ("debug/frame.s",                   "Phase 14 — DWARF call frame info"),
    ("debug/str.s",                     "Phase 14 — DWARF string section"),
    ("debug/srcmap.s",                  "Phase 14 — source map index"),
    ("debug/file.s",                    "Phase 14 — file table management"),
    ("debug/linemap.s",                 "Phase 14 — line mapping"),
    ("debug/macromap.s",                "Phase 14 — macro expansion mapping"),

    # ── optimizer ──
    ("optimizer/jump.s",                "Phase 15 — jump shortening pass"),
    ("optimizer/nop.s",                 "Phase 15 — NOP removal/replacement"),
    ("optimizer/align.s",               "Phase 15 — alignment NOP insertion"),
    ("optimizer/peephole.s",            "Phase 15 — peephole window"),
    ("optimizer/prefix.s",              "Phase 15 — redundant prefix elimination"),
    ("optimizer/size.s",                "Phase 15 — instruction size minimiser"),

    # ── selfpatch ──
    ("selfpatch/patchmap.s",            "Phase 16 — patch location map"),
    ("selfpatch/validate.s",            "Phase 16 — patch safety validation"),
    ("selfpatch/apply.s",               "Phase 16 — patch application"),
    ("selfpatch/rollback.s",            "Phase 16 — patch rollback"),
    ("selfpatch/log.s",                 "Phase 16 — patch audit log"),

    # ── profiler ──
    ("profiler/rdtsc.s",                "Phase 16 — RDTSC timer wrappers"),
    ("profiler/hotpath.s",              "Phase 16 — hot path detection"),
    ("profiler/report.s",               "Phase 16 — profiler report"),
    ("profiler/trigger.s",              "Phase 16 — selfpatch trigger logic"),

    # ── tools ──
    ("tools/disasm/disasm.s",           "Phase 17 — disassembler entry point"),
    ("tools/inspector/inspector.s",     "Phase 17 — binary inspector entry point"),
    ("tools/symdump/fmt.s",             "Phase 17 — symdump formatter"),
]

# ──────────────────────────────────────────────────────────────────────────────
# 3.  .gitkeep for empty test directories
# ──────────────────────────────────────────────────────────────────────────────
GITKEEP_DIRS = [
    "tests/unit/lexer",
    "tests/unit/parser",
    "tests/unit/macro",
    "tests/unit/symtable",
    "tests/unit/expr",
    "tests/unit/encoder/x86",
    "tests/unit/encoder/simd",
    "tests/unit/linker",
    "tests/unit/output",
    "tests/error/E1xx",
    "tests/error/E2xx",
    "tests/error/E3xx",
    "tests/error/E4xx",
    "tests/error/E5xx",
    "tests/error/E6xx",
    "tests/error/E7xx",
    "tests/error/E9xx",
    "tests/error/multi",
    "tests/warning",
    "tests/integration/selfhost",
    "tests/integration/elf",
    "tests/integration/pe",
    "tests/integration/boot",
    "tests/integration/upk",
    "tests/integration/simd",
    "tests/integration/multifile",
    "tests/integration/crossarch",
    "tests/integration/selfpatch",
    "tests/regression",
    "tests/fuzz/seeds",
    "tests/fuzz/corpus",
    "tests/perf/results",
    "tests/stress",
    "tests/fixtures/inc",
    "tests/fixtures/obj",
    "tests/fixtures/expect",
]

# ──────────────────────────────────────────────────────────────────────────────
# helpers
# ──────────────────────────────────────────────────────────────────────────────

def stub_content(rel_path, phase_comment):
    """Return the standard stub file body."""
    return (
        f"; {rel_path}\n"
        f"; {phase_comment}\n"
        f"; stub — not yet implemented\n"
        f"bits 64\n"
    )

def mkdirs():
    created = 0
    for d in DIRS:
        full = os.path.join(ROOT, d.replace("/", os.sep))
        if not os.path.isdir(full):
            os.makedirs(full, exist_ok=True)
            print(f"  mkdir  {d}")
            created += 1
    return created

def mkstubs():
    created = skipped = 0
    seen = set()
    for rel, phase in STUBS:
        if rel in seen:
            continue
        seen.add(rel)
        full = os.path.join(ROOT, rel.replace("/", os.sep))
        if os.path.exists(full):
            skipped += 1
            continue
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as f:
            f.write(stub_content(rel, phase))
        print(f"  stub   {rel}")
        created += 1
    return created, skipped

def mkgitkeeps():
    created = skipped = 0
    for d in GITKEEP_DIRS:
        full = os.path.join(ROOT, d.replace("/", os.sep))
        os.makedirs(full, exist_ok=True)
        gk = os.path.join(full, ".gitkeep")
        if os.path.exists(gk):
            skipped += 1
            continue
        with open(gk, "w") as f:
            pass
        print(f"  gitkeep {d}/.gitkeep")
        created += 1
    return created, skipped

# ──────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=== mkstubs.py — Phase 0 scaffold ===\n")

    print("[1] Creating directories...")
    nd = mkdirs()
    print(f"    {nd} directories created.\n")

    print("[2] Creating stub .s files...")
    ns, ss = mkstubs()
    print(f"    {ns} stubs created, {ss} already existed.\n")

    print("[3] Creating .gitkeep files...")
    ng, sg = mkgitkeeps()
    print(f"    {ng} .gitkeep files created, {sg} already existed.\n")

    print("Done.")
