#!/usr/bin/env python3
"""A sampling profiler for utasm (no perf needed): where its time goes.

    scripts/bench/sample.py [--interval US] [--top N] [--callers FUNC] utasm ARGS...

Runs the command under ptrace, stops it every --interval microseconds
(500 by default), reads its instruction pointer, and counts the samples by
function (nm's symbols of the binary, which is static: "foo.bar" local
labels fold into "foo"). Prints the hottest functions and, for the top
one, its hottest labels. --callers FUNC: for the samples in FUNC, where
it was called from (the first return address on its stack: a value just
past a call instruction).
"""

import bisect, collections, ctypes, os, signal, subprocess, sys, time

PTRACE_TRACEME, PTRACE_PEEKDATA, PTRACE_CONT, PTRACE_GETREGS = 0, 2, 7, 12
libc = ctypes.CDLL(None, use_errno=True)
libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_long, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]


class Regs(ctypes.Structure):
    _fields_ = [(n, ctypes.c_ulonglong) for n in (
        "r15", "r14", "r13", "r12", "rbp", "rbx", "r11", "r10", "r9", "r8", "rax", "rcx", "rdx", "rsi",
        "rdi", "orig_rax", "rip", "cs", "eflags", "rsp", "ss", "fs_base", "gs_base", "ds", "es", "fs", "gs")]


def symbols(binary):
    out = subprocess.run(["nm", "-n", binary], capture_output=True, text=True).stdout
    addrs, names = [], []
    for line in out.splitlines():
        f = line.split()
        if len(f) == 3 and f[1] in "tTwW":
            addrs.append(int(f[0], 16))
            names.append(f[2])
    return addrs, names


def main(argv):
    interval, top, callers = 500, 25, None
    while argv and argv[0].startswith("--"):
        if argv[0] == "--interval":
            interval = int(argv[1]); argv = argv[2:]
        elif argv[0] == "--top":
            top = int(argv[1]); argv = argv[2:]
        elif argv[0] == "--callers":
            callers = argv[1]; argv = argv[2:]
        else:
            break
    if not argv:
        print(__doc__)
        return 1
    addrs, names = symbols(argv[0])
    text = open(argv[0], "rb").read()
    base = text_base(argv[0])
    pid = os.fork()
    if pid == 0:
        libc.ptrace(PTRACE_TRACEME, 0, None, None)
        os.execv(argv[0], argv)
        os._exit(127)
    os.waitpid(pid, 0)                     # (stopped at its exec)
    libc.ptrace(PTRACE_CONT, pid, None, None)
    regs = Regs()
    samples = collections.Counter()
    labels = collections.Counter()
    sites = collections.Counter()
    n = 0
    while True:
        time.sleep(interval / 1e6)
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            break
        _, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status) or os.WIFSIGNALED(status):
            break
        sig = os.WSTOPSIG(status)
        if libc.ptrace(PTRACE_GETREGS, pid, None, ctypes.byref(regs)) == 0:
            i = bisect.bisect_right(addrs, regs.rip) - 1
            if i >= 0:
                full = names[i]
                samples[full.split(".")[0]] += 1
                labels[full] += 1
                n += 1
                if callers and full.split(".")[0] == callers:
                    site = caller(pid, regs.rsp, text, base, addrs)
                    if site is not None:
                        j = bisect.bisect_right(addrs, site) - 1
                        sites["%s+%#x" % (names[j], site - addrs[j]) if j >= 0 else hex(site)] += 1
        libc.ptrace(PTRACE_CONT, pid, None, ctypes.c_void_p(0 if sig == signal.SIGSTOP else sig))
    if not n:
        print("no samples")
        return 1
    print("%d samples" % n)
    for name, c in samples.most_common(top):
        print("%6.1f%%  %6d  %s" % (100.0 * c / n, c, name))
    hot = samples.most_common(1)[0][0]
    print("\nin %s:" % hot)
    for name, c in [x for x in labels.most_common() if x[0].split(".")[0] == hot][:12]:
        print("%6.1f%%  %6d  %s" % (100.0 * c / n, c, name))
    if callers:
        print("\n%s called from:" % callers)
        for name, c in sites.most_common(top):
            print("%6.1f%%  %6d  %s" % (100.0 * c / n, c, name))
    return 0


def text_base(binary):
    """(file offset, address) of the executable segment, from readelf"""
    out = subprocess.run(["readelf", "-lW", binary], capture_output=True, text=True).stdout
    for line in out.splitlines():
        f = line.split()
        if f and f[0] == "LOAD" and "E" in f[-2]:
            return int(f[1], 16), int(f[2], 16)
    return 0, 0


def caller(pid, rsp, text, base, addrs):
    """the first value on the stack just past a call (e8 rel32 / ff /2)"""
    off, vaddr = base
    for k in range(12):
        v = ctypes.c_ulong(libc.ptrace(PTRACE_PEEKDATA, pid, ctypes.c_void_p(rsp + 8 * k), None)).value
        fo = v - vaddr + off
        if not addrs or v < addrs[0] or fo < 6 or fo > len(text):
            continue
        if text[fo - 5] == 0xE8 or (text[fo - 2] == 0xFF and (text[fo - 1] >> 3) & 7 == 2):
            return v
    return None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
