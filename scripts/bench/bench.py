#!/usr/bin/env python3
"""Benchmarks: utasm against the other assemblers installed.

Generated workloads, each assembled into an ELF64 object by every
assembler found (nasm, yasm, GNU as, fasm), the best wall time of several
runs and the peak memory reported:

  instructions   mixed integer / SSE / AVX instructions, memory operands
  data           large db / dd / dq tables and strings
  macros         a %macro called many times, %rep loops, %assign
  jumps          many forward and backward jumps (relaxation)

usage: scripts/bench/bench.py [utasm] [--scale N] [--runs N] [--only NAME]

GNU as reads the same instructions in its Intel syntax (a translated
copy); FASM only the instructions and data workloads; YASM the NASM ones.
"""

import os, random, resource, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def gen_instructions(n, rnd):
    regs = ["rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
    r32 = ["eax", "ebx", "ecx", "edx", "esi", "edi", "r8d", "r9d"]
    xmm = ["xmm%d" % i for i in range(16)]
    ymm = ["ymm%d" % i for i in range(16)]
    lines = []
    for i in range(n):
        k = rnd.randrange(12)
        a, b = rnd.choice(regs), rnd.choice(regs)
        if k == 0:
            lines.append("mov %s, %s" % (a, b))
        elif k == 1:
            lines.append("add %s, %d" % (a, rnd.randrange(1, 100000)))
        elif k == 2:
            lines.append("lea %s, [%s + %s*%d + %d]" % (a, b, rnd.choice(regs[:4]), rnd.choice((1, 2, 4, 8)),
                                                        rnd.randrange(-500, 500)))
        elif k == 3:
            lines.append("mov %s, [%s + %d]" % (rnd.choice(r32), b, rnd.randrange(0, 4096, 4)))
        elif k == 4:
            lines.append("imul %s, %s, %d" % (a, b, rnd.randrange(2, 99)))
        elif k == 5:
            lines.append("xor %s, %s" % (rnd.choice(r32), rnd.choice(r32)))
        elif k == 6:
            lines.append("addps %s, %s" % (rnd.choice(xmm), rnd.choice(xmm)))
        elif k == 7:
            lines.append("vpaddd %s, %s, %s" % (rnd.choice(ymm), rnd.choice(ymm), rnd.choice(ymm)))
        elif k == 8:
            lines.append("movdqu %s, [%s + %d]" % (rnd.choice(xmm), b, rnd.randrange(0, 1024, 16)))
        elif k == 9:
            lines.append("shl %s, %d" % (a, rnd.randrange(1, 63)))
        elif k == 10:
            lines.append("cmp %s, %s" % (a, b))
        else:
            lines.append("push %s\npop %s" % (a, b))
    return "section .text\n" + "\n".join(lines) + "\n"


def gen_data(n, rnd):
    lines = ["section .data"]
    for i in range(n // 4):
        lines.append("d%d: dd %s" % (i, ", ".join(str(rnd.randrange(1 << 31)) for _ in range(8))))
        lines.append("q%d: dq %s" % (i, ", ".join(str(rnd.randrange(1 << 62)) for _ in range(4))))
        lines.append("b%d: db %s" % (i, ", ".join(str(rnd.randrange(256)) for _ in range(16))))
        lines.append('s%d: db "string number %d with some text", 0' % (i, i))
    return "\n".join(lines) + "\n"


def gen_macros(n, rnd):
    text = ['section .text', '%macro step 2', '    mov rax, %1', '    add rax, %2', '    %assign acc acc + 1', '%endmacro', '%assign acc 0', '%rep REPS', '    step acc, 3', '    step rbx, acc', '%endrep', '%assign i 0', '%rep REPS', '    %if i % 2', '        nop', '    %else', '        inc rcx', '    %endif', '    %assign i i + 1', '%endrep']
    return "".join(l.replace("REPS", str(n // 4)) + chr(10) for l in text)


def gen_jumps(n, rnd):
    lines = ["section .text"]
    m = n // 3
    for i in range(m):
        lines.append("L%d:" % i)
        t = rnd.randrange(max(1, i - 50), min(m, i + 50))
        lines.append("    %s L%d" % (rnd.choice(("jmp", "je", "jne", "jl", "ja", "call")), t))
        lines.append("    add eax, %d" % rnd.randrange(100))
    return "\n".join(lines) + "\n"


WORKLOADS = [("instructions", gen_instructions), ("data", gen_data), ("macros", gen_macros), ("jumps", gen_jumps)]


def to_gas(src):
    """the NASM text in GNU as's Intel syntax (enough for these workloads)"""
    out = [".intel_syntax noprefix"]
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("section "):
            out.append(".section " + s.split()[1])
            continue
        for d, g in (("db ", ".byte "), ("dd ", ".long "), ("dq ", ".quad ")):
            if (": " + d) in line:
                lbl, rest = line.split(": " + d, 1)
                if '"' in rest:
                    rest = rest.replace(", 0", "")
                    out.append(lbl + ": .asciz " + rest)
                else:
                    out.append(lbl + ": " + g + rest)
                break
        else:
            out.append(line.replace("movdqu ", "movdqu ").replace("[", "QWORD PTR [") if s.startswith("mov ") and "[" in s
                       and s.split()[1].rstrip(",") in ("rax", "rbx", "rcx", "rdx", "rsi", "rdi") else line)
    return "\n".join(out) + "\n"


def to_fasm(src):
    out = ["format ELF64"]
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("section "):
            out.append("section '%s'" % s.split()[1] + (" executable" if s.split()[1] == ".text" else " writeable"))
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def assemblers(utasm):
    a = [("utasm", lambda src, out: [utasm, "-f", "elf64", "-o", out, src], None)]
    if shutil.which("nasm"):
        a.append(("nasm", lambda src, out: ["nasm", "-f", "elf64", "-o", out, src], None))
    if shutil.which("yasm"):
        a.append(("yasm", lambda src, out: ["yasm", "-f", "elf64", "-o", out, src], None))
    if shutil.which("as"):
        a.append(("gas", lambda src, out: ["as", "--64", "-o", out, src], to_gas))
    if shutil.which("fasm"):
        a.append(("fasm", lambda src, out: ["fasm", src, out], to_fasm))
    return a


def measure(cmd, runs):
    best, rss, rc = None, 0, 0
    for _ in range(runs):
        t = time.perf_counter()
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _, status, usage = os.wait4(p.pid, 0)
        dt = time.perf_counter() - t
        rc = os.waitstatus_to_exitcode(status)
        best = dt if best is None or dt < best else best
        rss = max(rss, usage.ru_maxrss)
    return best, rss, rc


def main(argv):
    utasm = os.path.join(ROOT, "build", "gen1", "utasm")
    scale, runs, only = 20000, 5, None
    i = 0
    while i < len(argv):
        if argv[i] == "--scale":
            scale = int(argv[i + 1]); i += 2
        elif argv[i] == "--runs":
            runs = int(argv[i + 1]); i += 2
        elif argv[i] == "--only":
            only = argv[i + 1]; i += 2
        else:
            utasm = argv[i]; i += 1
    if not os.path.exists(utasm):
        print("no utasm binary at %s" % utasm)
        return 1
    rnd = random.Random(1)
    print("%-13s %8s  %-6s %10s %12s %9s %8s" % ("workload", "lines", "asm", "time ms", "lines/s", "rss MB", "vs utasm"))
    with tempfile.TemporaryDirectory() as d:
        for name, gen in WORKLOADS:
            if only and name != only:
                continue
            src = gen(scale, rnd)
            nlines = src.count("\n")
            base = None
            for asm, cmd, conv in assemblers(utasm):
                if conv is not None and name in ("macros",) and asm in ("gas", "fasm"):
                    continue                       # (NASM's preprocessor)
                if asm == "fasm" and name == "jumps":
                    continue
                text = conv(src) if conv else src
                path = os.path.join(d, "%s-%s.s" % (name, asm))
                open(path, "w").write(text)
                t, rss, rc = measure(cmd(path, os.path.join(d, "out.o")), runs)
                if rc != 0:
                    print("%-13s %8d  %-6s %10s" % (name, nlines, asm, "failed (rc %d)" % rc))
                    continue
                if asm == "utasm":
                    base = t
                rel = "%.2fx" % (t / base) if base else "-"
                print("%-13s %8d  %-6s %10.1f %12.0f %9.1f %8s" % (name, nlines, asm, t * 1000, nlines / t,
                                                                  rss / 1024.0, rel))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
