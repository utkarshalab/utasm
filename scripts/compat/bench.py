#!/usr/bin/env python3
"""Speed against NASM: the same inputs assembled by both, timed.

  straight   lines of ordinary instructions (mov, add, lea, loads, imul)
  jumps      short and long jumps among labels (NASM's passes; utasm's
             jump shortening)
  macros     multi-line macros, %define with parameters, %assign
  data       labelled dd / db lines (symbol and string tables)
  sources    utasm's own sources, one run each

usage: scripts/compat/bench.py [utasm-binary] [--scale N] [--only NAME]
       --scale  input sizes times N (default 1: about a second for NASM)

Prints each time, the ratio, and whether the code is the same (objdump of
the two objects).
"""
import glob, os, random, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REGS = ["rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"]


def straight(n, rng):
    out = ["bits 64", "section .text"]
    for _ in range(n):
        a, b = rng.choice(REGS), rng.choice(REGS)
        out.append(rng.choice(["mov %s, %s" % (a, b), "add %s, %d" % (a, rng.randrange(1000)),
                               "lea %s, [%s + %s*4 + %d]" % (a, b, rng.choice(REGS), rng.randrange(256)),
                               "xor %s, %s" % (a, b), "mov %s, [%s + %d]" % (a, b, rng.randrange(4096)),
                               "imul %s, %s, %d" % (a, b, rng.randrange(100))]))
    return "\n".join(out) + "\n"


def jumps(n, rng):
    out = ["bits 64", "section .text"]
    for i in range(n):
        out += ["L%d:" % i, "cmp eax, %d" % (i % 50),
                rng.choice(["je", "jne", "jmp", "jl"]) + " L%d" % rng.randrange(max(0, i - 40), i + 40), "nop"]
    out += ["L%d:" % j for j in range(n, n + 41)]
    return "\n".join(out) + "\n"


def macros(n, rng):
    out = ["bits 64", "%macro push3 3\npush %1\npush %2\npush %3\n%endmacro",
           "%macro pop3 3\npop %3\npop %2\npop %1\n%endmacro", "%define SLOT(i) [rbp - 8*(i)]", "section .text"]
    for i in range(n):
        out += ["push3 rax, rbx, rcx", "mov rax, SLOT(%d)" % (i % 30 + 1), "%%assign k %d" % i, "pop3 rax, rbx, rcx"]
    return "\n".join(out) + "\n"


def data(n, rng):
    out = ["section .data"]
    for i in range(n):
        out += ["d%d: dd %d, %d, %d, %d" % (i, i, i * 2, i * 3, i * 4), "s%d: db 'string number %d', 0" % (i, i)]
    return "\n".join(out) + "\n"


def timed(cmd, cwd):
    start = time.time()
    r = subprocess.run(cmd, cwd=cwd, capture_output=True)
    return time.time() - start, r.returncode


def code(path):
    out = subprocess.run(["objdump", "-d", "-s", path], capture_output=True, text=True).stdout
    return out.splitlines()[3:]


def main(argv):
    scale = float(argv[argv.index("--scale") + 1]) if "--scale" in argv else 1.0
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    args = [a for i, a in enumerate(argv) if not a.startswith("-") and (i == 0 or argv[i - 1] not in ("--scale", "--only"))]
    utasm = os.path.abspath(args[0] if args else os.path.join(ROOT, "build", "gen1", "utasm"))
    rng = random.Random(1)
    inputs = [("straight", straight, 200000), ("jumps", jumps, 20000), ("macros", macros, 50000), ("data", data, 100000)]
    print("%-10s %8s %10s %10s %8s  %s" % ("input", "lines", "nasm", "utasm", "faster", "code"))
    with tempfile.TemporaryDirectory(prefix="utasm-bench-") as d:
        for name, gen, n in inputs:
            if only and only != name:
                continue
            src = gen(int(n * scale), rng)
            open(os.path.join(d, "b.s"), "w").write(src)
            tn, rn = timed(["nasm", "-f", "elf64", "b.s", "-o", "n.o"], d)
            tu, ru = timed([utasm, "-f", "elf64", "b.s", "-o", "u.o"], d)
            same = "same" if rn == ru == 0 and code(os.path.join(d, "n.o")) == code(os.path.join(d, "u.o")) else "DIFFERS"
            print("%-10s %8d %9.2fs %9.2fs %7.1fx  %s" % (name, src.count("\n"), tn, tu, tn / tu if tu else 0, same),
                  flush=True)
        if not only or only == "sources":
            files = [f for f in glob.glob(os.path.join(ROOT, "**", "*.s"), recursive=True)
                     if "/tests/" not in f and "/build/" not in f]
            tn = sum(timed(["nasm", "-f", "elf64", f, "-o", os.path.join(d, "x.o")], ROOT)[0] for f in files)
            tu = sum(timed([utasm, "-f", "elf64", f, "-o", os.path.join(d, "y.o")], ROOT)[0] for f in files)
            print("%-10s %8d %9.2fs %9.2fs %7.1fx  (%d files)" % ("sources", 0, tn, tu, tn / tu, len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
