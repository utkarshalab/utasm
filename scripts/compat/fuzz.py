#!/usr/bin/env python3
"""Mutation fuzzing: utasm must never crash, hang or run away with memory,
whatever the input - only assemble it or report errors.

Takes the test sources (tests/amd64) and the compatibility cases as seeds,
changes each at random (lines dropped, repeated, cut, swapped or spliced in
from another seed; directives, operators, odd bytes and nesting inserted)
and assembles the result as bin, elf64 or elf32, sometimes with -l or -g.
A run fails when utasm reports an internal error (a fault, caught by
core/crash.s) or dies of a signal, takes more than 10 s, or uses more than
2 GB. Each failing input is saved, then cut down - lines, then characters -
to the smallest that fails at the same place, and printed once per place.

usage: scripts/compat/fuzz.py [utasm-binary] [runs] [seed] [--out DIR]
       (defaults: build/gen1/utasm, 2000 runs, seed 1, $TMPDIR/utasm-fuzz)

Exits 1 when a run failed. The runs are reproducible: the same seed gives
the same inputs.
"""
import bisect, glob, os, random, re, subprocess, sys, tempfile, time
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import cases  # noqa: E402

TIMEOUT = 10
MEM_KB = 2 * 1024 * 1024

TOKENS = ["[", "]", "(", ")", ",", "%", "%%", "%$", "$", "$$", ":", "{", "}", "'", '"', "`", "\\",
          "#", "~", "!", "<<", ">>", "?", "*", "/", "//", "-", "+", "&", "|", "^", "==", "<=>",
          "dword", "qword", "byte", "rel", "abs", "strict", "short", "near", "far", "wrt", "..plt",
          "times", "%macro", "%endmacro", "%rep", "%endrep", "%if", "%elif", "%else", "%endif",
          "%define", "%xdefine", "%undef", "%assign", "%strlen", "%substr", "%push", "%pop",
          "%rotate", "%include", "%error", "%line", "%use", "%[", "%{", "%+", "%0", "%1", "%-1",
          "equ", "section", "segment", "global", "extern", "common", "align", "alignb", "struc",
          "endstruc", "istruc", "iend", "at", "db", "dw", "dd", "dq", "dt", "do", "resb", "incbin",
          "org", "bits 16", "bits 32", "bits 64", "default rel", "cpu", "absolute", "mov", "lea",
          "jmp", "call", "push", "rax", "eax", "ax", "al", "r15", "xmm0", "zmm31", "k1", "{k1}",
          "{z}", "cs:", "fs:", "rip", "0x", "0", "-1", "999999999999999999999999", "0x8000000000000000",
          "1e9999", "1.5", "__utf16__", "__float32__", "__?NaN?__", "..@", ".local", "\t", "\x00",
          "\x7f", "\xff", "é", "\r", "\n%endmacro\n", "\n%endif\n", "\n%endrep\n"]
FORMATS = [("bin", []), ("elf64", []), ("elf64", ["-l", "x.lst"]), ("elf64", ["-g"]),
           ("elf32", []), ("bin", ["-l", "x.lst"])]


def seeds():
    out = [open(f, errors="replace").read() for f in sorted(glob.glob(os.path.join(ROOT, "tests", "amd64", "*.s")))]
    out += [s if s.startswith(("bits", "org", "[")) else "bits 64\n" + s for s in cases.BIN_PROBES.values()]
    out += list(cases.ELF_PROBES.values()) + list(cases.EXPR_BIN.values()) + list(cases.EXPR_ELF.values())
    out += [s for s, files, fmt in cases.limit_cases().values() if not files and len(s) < 20000]
    out += [src for _, src, _, _ in cases.ROBUST_CASES]
    return out


def mutate(rng, src, pool):
    lines = src.split("\n") or [""]
    for _ in range(rng.randint(1, 4)):
        op = rng.randrange(9)
        i = rng.randrange(len(lines))
        if op == 0 and len(lines) > 1:
            del lines[i]
        elif op == 1:
            lines.insert(i, lines[i])
        elif op == 2 and lines[i]:
            lines[i] = lines[i][:rng.randrange(len(lines[i]))]
        elif op == 3:
            l, p = lines[i], rng.randint(0, len(lines[i]))
            lines[i] = l[:p] + rng.choice([" ", ""]) + rng.choice(TOKENS) + rng.choice([" ", ""]) + l[p:]
        elif op == 4 and len(lines) > 1:
            j = rng.randrange(len(lines))
            lines[i], lines[j] = lines[j], lines[i]
        elif op == 5:
            other = rng.choice(pool).split("\n")
            a = rng.randrange(len(other))
            lines[i:i] = other[a:a + rng.randint(1, 6)]
        elif op == 6:
            l, p = lines[i], rng.randint(0, len(lines[i]))
            c = rng.choice([rng.randrange(1, 32), rng.randrange(32, 127), rng.randrange(128, 256)])
            lines[i] = l[:p] + chr(c) + l[p:]
        elif op == 7:
            lines.insert(i, " ".join(rng.choice(TOKENS) for _ in range(rng.randint(1, 8))))
        else:
            lines.insert(i, rng.choice(["%rep 100", "%if 1", "%macro mm 1-*", "times 50"]) + " " + lines[i])
    return "\n".join(lines)


def _rss_kb(pid):
    try:
        for l in open("/proc/%d/status" % pid):
            if l.startswith("VmRSS:"):
                return int(l.split()[1])
    except OSError:
        pass
    return 0


def assemble(utasm, src, fmt, opts):
    """None when utasm handled it; otherwise (verdict, the fault's address or
    None, the last line it printed)."""
    with tempfile.TemporaryDirectory(prefix="utasm-fuzz-") as d:
        open(os.path.join(d, "f.s"), "w", errors="replace").write(src)
        err = tempfile.TemporaryFile()
        p = subprocess.Popen([utasm, "-f", fmt, "f.s", "-o", "f.o"] + opts, cwd=d,
                             stdout=subprocess.DEVNULL, stderr=err)
        start, verdict = time.time(), None
        while p.poll() is None:
            if _rss_kb(p.pid) > MEM_KB:
                verdict = "MEMORY"
            elif time.time() - start > TIMEOUT:
                verdict = "HANG"
            if verdict:
                p.kill()
                p.wait()
                break
            time.sleep(0.01)
        err.seek(0)
        text = err.read().decode(errors="replace")
    m = re.search(r"internal error: .* at 0x([0-9a-f]+)", text)
    if not verdict and m:
        verdict = "CRASH"
    elif not verdict and (p.returncode < 0 or p.returncode >= 128):
        verdict = "SIGNAL"
    if not verdict:
        return None
    lines = text.strip().splitlines()
    return verdict, int(m.group(1), 16) if m else None, lines[-1][:120] if lines else ""


def minimize(utasm, src, fmt, opts, want):
    """The smallest input (lines, then characters from each line's end)
    that still fails as want (verdict, address)."""
    def same(s):
        r = assemble(utasm, s, fmt, opts)
        return r is not None and r[:2] == want
    lines, n = src.split("\n"), 2
    while len(lines) >= 2:
        chunk, cut = max(1, len(lines) // n), False
        for i in range(0, len(lines), chunk):
            cand = lines[:i] + lines[i + chunk:]
            if same("\n".join(cand)):
                lines, cut, n = cand, True, max(n - 1, 2)
                break
        if not cut:
            if chunk == 1:
                break
            n = min(n * 2, len(lines))
    for i in range(len(lines)):
        while lines[i] and same("\n".join(lines[:i] + [lines[i][:-1]] + lines[i + 1:])):
            lines[i] = lines[i][:-1]
    return "\n".join(lines)


_POOL = None
_ARGS = None


def _init(args):
    global _POOL, _ARGS
    _POOL, _ARGS = seeds(), args


def _one(k):
    utasm, seed = _ARGS
    rng = random.Random(seed * 1000003 + k)
    src = mutate(rng, rng.choice(_POOL), _POOL)
    fmt, opts = rng.choice(FORMATS)
    r = assemble(utasm, src, fmt, opts)
    return k, src, fmt, opts, r


def _where(utasm, addr):
    syms = []
    for l in subprocess.run(["nm", "-n", utasm], capture_output=True, text=True).stdout.splitlines():
        p = l.split()
        if len(p) == 3:
            syms.append((int(p[0], 16), p[2]))
    i = bisect.bisect_right([a for a, _ in syms], addr) - 1
    return "%s+0x%x" % (syms[i][1], addr - syms[i][0]) if i >= 0 else hex(addr)


def main(argv):
    out = os.path.join(tempfile.gettempdir(), "utasm-fuzz")
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    args = [a for a in argv if not a.startswith("-")]
    utasm = os.path.abspath(args[0] if args else os.path.join(ROOT, "build", "gen1", "utasm"))
    runs = int(args[1]) if len(args) > 1 else 2000
    seed = int(args[2]) if len(args) > 2 else 1
    if not os.path.exists(utasm):
        print("no utasm binary at %s" % utasm)
        return 1
    os.makedirs(out, exist_ok=True)
    found = {}
    with Pool(os.cpu_count() or 4, initializer=_init, initargs=((utasm, seed),)) as pool:
        for k, src, fmt, opts, r in pool.imap_unordered(_one, range(runs), chunksize=8):
            if r:
                found.setdefault(r[:2], []).append((k, src, fmt, opts, r[2]))
    for (verdict, addr), hits in sorted(found.items(), key=lambda x: -len(x[1])):
        k, src, fmt, opts, last = min(hits, key=lambda h: len(h[1]))
        path = os.path.join(out, "%s_%d.s" % (verdict.lower(), k))
        open(path, "w", errors="replace").write(src)
        small = minimize(utasm, src, fmt, opts, (verdict, addr))
        where = _where(utasm, addr) if addr is not None else last
        print("%s x%d  %s  (utasm -f %s %s; %s)" % (verdict, len(hits), where, fmt, " ".join(opts), path))
        for l in small.splitlines()[:12]:
            print("    | " + l)
    problems = sum(len(h) for h in found.values())
    print("runs %d (seed %d), failing %d" % (runs, seed, problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
