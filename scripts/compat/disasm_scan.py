#!/usr/bin/env python3
"""disasm_scan.py UTASM [--bits 16|32|64]... [--quick] [-j N]

The whole opcode space through utasm --disasm and objdump -D -b binary
-M intel (binutils 2.47 or later first on PATH), first instruction of each
case against first instruction: its bytes and its text.

A case is a prefix (none, 66, F3, F2), a map (one-byte, 0F, 0F 38, 0F 3A),
an opcode, a ModRM byte, then fixed filler bytes (the displacement, SIB,
immediate or VEX / EVEX payload whatever reads them). The ModRM bytes are
33: every mod x reg with an rm that varies with them, and F8 - 133,320
cases a mode; --quick takes 4 (00 C0 08 D1), 16,160 a mode.

Prints each difference (the case's bytes, objdump's and utasm's first
instruction) and a count per mode on stderr; exits 1 when any differ.
The prefixes alone (26 2E 36 3E 64 65 66 67 F0 F2 F3) and the 0F escapes
are not opcodes of their own here: the cases with a prefix cover them."""
import argparse, concurrent.futures as cf, os, re, subprocess, sys, tempfile

TAIL = bytes.fromhex("01020304050607089090909090909090")
ARCH = {"16": "i8086", "32": "i386", "64": "i386:x86-64"}
PREFIX_BYTES = (0x0F, 0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x66, 0x67, 0xF0, 0xF2, 0xF3)


def cases(quick):
    if quick:
        modrms = [0x00, 0xC0, 0x08, 0xD1]
    else:
        modrms = [(m << 6) | (r << 3) | ((r + 5 * m) & 7) for m in range(4) for r in range(8)] + [0xF8]
    out = []
    for pfx in ("", "66", "f3", "f2"):
        for mp in ("", "0f", "0f38", "0f3a"):
            for op in range(256):
                if mp == "0f" and op in (0x38, 0x3A):
                    continue
                if mp == "" and op in PREFIX_BYTES:
                    continue
                for modrm in modrms:
                    out.append(bytes.fromhex(pfx + mp + "%02x%02x" % (op, modrm)) + TAIL)
    return out


def first(text, ours):
    """The first instruction's bytes and text, blanks folded."""
    for line in text.splitlines():
        if ours:
            m = re.match(r"^  ([0-9a-f]{8,}):\s+((?:[0-9a-f]{2} )+)\s*(.*)$", line)
            if m:
                return " ".join(m.group(2).split()), " ".join(m.group(3).split())
        else:
            p = line.split("\t")
            if len(p) >= 3 and p[0].strip().endswith(":"):
                return " ".join(p[1].split()), " ".join(p[2].split())
    return None, None


def objdump_ok():
    try:
        v = subprocess.run(["objdump", "--version"], capture_output=True, text=True).stdout
    except OSError:
        return False
    m = re.search(r"(\d+)\.(\d+)", v.splitlines()[0] if v else "")
    return bool(m) and (int(m.group(1)), int(m.group(2))) >= (2, 47)


def scan(utasm, bits, quick, jobs, tmp):
    cs = cases(quick)

    def one(i):
        f = os.path.join(tmp, "c%d_%d.bin" % (int(bits), i))
        with open(f, "wb") as fh:
            fh.write(cs[i])
        o = subprocess.run(["objdump", "-D", "-b", "binary", "-m", ARCH[bits], "-M", "intel", "-w", f],
                           capture_output=True, text=True).stdout
        u = subprocess.run([utasm, "--disasm", "--bits", bits, f], capture_output=True, text=True).stdout
        os.unlink(f)
        return i, first(o, False), first(u, True)

    bad = 0
    with cf.ThreadPoolExecutor(jobs) as ex:
        for i, o, u in ex.map(one, range(len(cs))):
            if o != u:
                bad += 1
                print("%s | objdump %s | utasm %s" % (cs[i][:len(cs[i]) - len(TAIL)].hex(), o, u))
    print("bits %s: %d cases, %d differ" % (bits, len(cs), bad), file=sys.stderr)
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("utasm")
    ap.add_argument("--bits", action="append", choices=("16", "32", "64"))
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()
    if not objdump_ok():
        sys.exit("disasm_scan: needs objdump 2.47 or later first on PATH")
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for bits in a.bits or ["64", "32", "16"]:
            bad += scan(a.utasm, bits, a.quick, a.j, tmp)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
