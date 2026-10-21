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

    # ── error ──
    ("error/warnings.s",                "Phase 1 — warning message strings"),
    ("error/hints.s",                   "Phase 1 — hint message strings"),
    ("error/suggest.s",                 "Phase 1 — suggestion engine"),
    ("error/format/source.s",           "Phase 1 — format: source line text"),

    # ── frontend / lexer ──

    # ── frontend / parser ──

    # ── frontend / macro ──
    ("frontend/macro/rotate.s",         "Phase 6 — %rotate"),

    # ── middle / expr ──

    # ── middle / symtable ──

    # ── middle / semantic ──
    ("middle/semantic/proc.s",          "Phase 7 — procedure semantic checks"),

    # ── backend / encoder tables ──
    ("backend/encoder/tables/opcode.s", "Phase 8 — opcode map"),

    # ── backend / encoder prefix ──

    # ── backend / encoder x86 ──

    # ── backend / encoder simd ──
    ("backend/encoder/simd/amx.s",      "Phase 8 — AMX tile encoders"),
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
    ("backend/output/pe/dos.s",         "Phase 13 — PE DOS stub"),
    ("backend/output/pe/header.s",      "Phase 13 — PE COFF header"),
    ("backend/output/pe/optional.s",    "Phase 13 — PE optional header"),
    ("backend/output/pe/section.s",     "Phase 13 — PE section table"),
    ("backend/output/pe/reloc.s",       "Phase 13 — PE base relocations"),
    ("backend/output/pe/export.s",      "Phase 13 — PE export directory"),
    ("backend/output/pe/import.s",      "Phase 13 — PE import directory"),
    ("backend/output/pe/cert.s",        "Phase 13 — PE security certificate"),
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
    ("debug/line.s",                    "Phase 14 — DWARF line number program"),

    # ── optimizer ──
    ("optimizer/jump.s",                "Phase 15 — jump shortening pass"),
    ("optimizer/align.s",               "Phase 15 — alignment NOP insertion"),

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
