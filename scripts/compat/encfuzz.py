"""Encoder fuzzing against NASM: random instructions of every form in NASM's
own table (scripts/nasm/insns.dat), with random registers, addresses and
immediates, in bits 16, 32 and 64. Each batch is assembled by both; what
NASM rejects is dropped; then each line's bytes in the two listings must be
the same, and utasm must take every line NASM takes.

    python3 scripts/compat/encfuzz.py UTASM [LINES] [SEED] [-v]
    python3 scripts/compat/encfuzz.py UTASM --objdump [SEED] [-v]

--objdump: NASM's table is not always right (its AVX512-FP16 forms: names
off by an opcode, a source missing, roles swapped), and a mistake both
make is no difference. Every form, in bits 64, is assembled by utasm
alone and read back by objdump: one instruction for the bytes, the same
mnemonic and the same registers, in order.

Prints a summary and the first findings by mnemonic; exit status 1 when
there are any."""
import collections, os, random, re, sys, tempfile
from common import run, tempdir

HERE = os.path.dirname(os.path.abspath(__file__))
INSNS = os.environ.get("ENCFUZZ_INSNS") or os.path.join(os.path.dirname(HERE), "nasm", "insns.dat")

GPR64 = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"] + ["r%d" % i for i in range(8, 16)]
GPR32 = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"] + ["r%dd" % i for i in range(8, 16)]
GPR16 = ["ax", "cx", "dx", "bx", "sp", "bp", "si", "di"] + ["r%dw" % i for i in range(8, 16)]
GPR8 = ["al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil"] + ["r%db" % i for i in range(8, 16)]
GPR8_LEGACY = ["al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"]
SIZE_WORD = {8: "byte", 16: "word", 32: "dword", 64: "qword", 80: "tword", 128: "oword", 256: "yword",
             512: "zword"}
CONDS = ["o", "no", "b", "ae", "e", "ne", "be", "a", "s", "ns", "p", "np", "l", "ge", "le", "g"]
BRANCHES = {"JMP", "CALL", "JCC", "JCXZ", "JECXZ", "JRCXZ", "LOOP", "LOOPE", "LOOPNE", "LOOPZ", "LOOPNZ",
            "XBEGIN", "JMPE"}


class Skip(Exception):
    pass


def forms():
    out = []
    for line in open(INSNS, encoding="utf-8", errors="replace"):
        line = line.split(";", 1)[0].strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"(\S+)\s+(\S+)\s+(\[[^\]]*\]|\S+)\s+(\S+)", line)
        if not m:
            continue
        name, ops, enc, flags = m.groups()
        if ops == "ignore" or name.upper() in BRANCHES or "ND" in flags.split(","):
            continue
        out.append((name, ops, enc, set(flags.split(","))))
    return out


def gpr(size, bits, rng, evex=False):
    if bits == 64:
        pool = {8: GPR8, 16: GPR16, 32: GPR32, 64: GPR64}[size]
    else:
        if size == 64:
            raise Skip
        pool = {8: GPR8_LEGACY, 16: GPR16[:8], 32: GPR32[:8]}[size]
    return rng.choice(pool)


def address(bits, rng, size=None, vsib=None):
    if bits == 16:
        base = rng.choice(["bx", "bp", "si", "di", "bx+si", "bp+di", None])
        parts = [base] if base else []
        disp = rng.choice([0, 1, -2, 0x7F, 0x1234])
    else:
        regs = GPR64 if bits == 64 else GPR32[:8]
        parts = []
        if rng.random() < 0.85:
            parts.append(rng.choice(regs))
        if vsib:
            n = 32 if bits == 64 else 8
            parts.append("%s%d*%d" % (vsib, rng.randrange(n if vsib != "xmm" or bits == 64 else 8),
                                      rng.choice([1, 2, 4, 8])))
        elif rng.random() < 0.4:
            idx = rng.choice([r for r in regs if r not in ("rsp", "esp")])
            parts.append("%s*%d" % (idx, rng.choice([1, 2, 4, 8])))
        disp = rng.choice([0, 0, 8, -8, 0x7F, -0x80, 0x80, 0x12345])
    text = "+".join(parts) if parts else ""
    if disp or not text:
        text = (text + ("%+d" % disp if text else "%d" % (disp or 0x1000)))
    sz = SIZE_WORD.get(size, "") if size else ""
    return ("%s [%s]" % (sz, text)).strip()


def imm(kind, rng):
    if kind == "unity":
        return "1"
    if kind in ("imm8", "sbyteword", "sbytedword", "sbyteword16", "sbytedword32", "sbytedword64"):
        return str(rng.choice([0, 1, 5, 0x7F, -1, -0x80]))
    if kind == "imm16":
        return str(rng.choice([0, 0x1234, 0xFFFF, 0x80, -2]))
    if kind == "imm64":
        return str(rng.choice([0x123456789ABC, 1, -1, 0x80000000]))
    if kind == "imm32":
        return str(rng.choice([0x12345678, 1, -1, 0x80]))
    return str(rng.choice([0, 1, 0x7F, 0x80, 0x1234, 0x12345678, -1]))


VEC = {"xmm": 128, "ymm": 256, "zmm": 512}


def operand(spec, bits, rng, evex):
    parts = spec.rstrip("*").split("|")
    t = parts[0]
    mods = set(parts[1:])
    if mods & {"near", "far", "short", "to", "colon", "abs"}:
        raise Skip
    nvec = 32 if evex and bits == 64 else (16 if bits == 64 else 8)
    m = re.fullmatch(r"reg(8|16|32|64)", t)
    if m:
        return gpr(int(m.group(1)), bits, rng, evex)
    m = re.fullmatch(r"rm(8|16|32|64)", t)
    if m:
        size = int(m.group(1))
        if rng.random() < 0.5:
            return gpr(size, bits, rng, evex)
        return address(bits, rng, size)
    m = re.fullmatch(r"reg_(\w+)", t)
    if m:
        r = m.group(1)
        if r == "sreg":
            return rng.choice(["es", "ss", "ds", "fs", "gs"])
        if r in ("dreg", "creg", "treg"):
            raise Skip
        if r.startswith("r") and len(r) == 3 and bits != 64:
            raise Skip
        return r
    m = re.fullmatch(r"mem(\d*)", t)
    if m:
        size = int(m.group(1)) if m.group(1) else None
        return address(bits, rng, size)
    if t.startswith("imm") or t in ("unity", "sbyteword", "sbytedword", "sbyteword16", "sbytedword32",
                                    "sbytedword64", "udword", "sdword"):
        return imm(t, rng)
    m = re.fullmatch(r"(xmm|ymm|zmm)reg", t)
    if m:
        text = "%s%d" % (m.group(1), rng.randrange(nvec))
        if "mask" in mods and rng.random() < 0.5:
            text += "{k%d}" % rng.randrange(1, 8)
            if "z" in mods and rng.random() < 0.5:
                text += "{z}"
        return text
    m = re.fullmatch(r"(xmm|ymm|zmm)rm(\d+)", t)
    if m:
        # a broadcast ("[rax]{1to16}"): one element of the b16 / b32 / b64 the
        # form allows, as many times as the vector holds
        bc = [int(x[1:]) for x in mods if re.fullmatch(r"b(16|32|64)", x)]
        if bc and evex and rng.random() < 0.3:
            width = {"xmm": 128, "ymm": 256, "zmm": 512}[m.group(1)]
            return "%s{1to%d}" % (address(bits, rng, None), width // bc[0])
        if rng.random() < 0.5:
            text = "%s%d" % (m.group(1), rng.randrange(nvec))
        else:
            text = address(bits, rng, int(m.group(2)))
        if "mask" in mods and rng.random() < 0.5:
            text += "{k%d}" % rng.randrange(1, 8)
        return text
    m = re.fullmatch(r"(x|y|z)mem(32|64)", t)
    if m:
        if bits == 16:
            raise Skip
        text = address(bits, rng, int(m.group(2)), vsib=m.group(1) + "mm")
        if "mask" in mods:
            text += "{k%d}" % rng.randrange(1, 8)
        return text
    m = re.fullmatch(r"kreg(8|16|32|64)?", t)
    if m:
        text = "k%d" % rng.randrange(8)
        if "mask" in mods and rng.random() < 0.5:
            text += "{k%d}" % rng.randrange(1, 8)
        return text
    if t == "krm16" or re.fullmatch(r"krm(8|16|32|64)", t):
        return "k%d" % rng.randrange(8)
    if t == "mmxreg":
        return "mm%d" % rng.randrange(8)
    if t == "mmxrm" or t == "mmxrm64":
        return "mm%d" % rng.randrange(8) if rng.random() < 0.5 else address(bits, rng, 64)
    if t == "fpureg":
        return "st%d" % rng.randrange(1, 8)
    if t == "fpu0":
        return "st0"
    if t == "bndreg":
        return "bnd%d" % rng.randrange(4)
    if t == "tmmreg":
        if bits != 64:
            raise Skip
        return "tmm%d" % rng.randrange(8)
    if t == "sreg":
        return rng.choice(["es", "ss", "ds", "fs", "gs"])
    if t == "creg":
        return rng.choice(["cr0", "cr2", "cr3", "cr4"])
    if t == "dreg":
        return "dr%d" % rng.choice([0, 1, 2, 3, 6, 7])
    if t == "void":
        return None
    raise Skip


def instance(form, bits, rng):
    name, ops, enc, flags = form
    if "LONG" in flags and bits != 64:
        raise Skip
    if "NOLONG" in flags and bits == 64:
        raise Skip
    evex = "evex" in enc
    if "cc" in name.lower() and name.upper() not in ("CPUID",):
        name = re.sub("cc", lambda _: rng.choice(CONDS), name, flags=re.I)
    texts = []
    if ops != "void":
        for spec in ops.split(","):
            o = operand(spec, bits, rng, evex)
            if o is not None:
                texts.append(o)
    return (name.lower() + " " + ", ".join(texts)).strip()


def listing_bytes(path):
    """{source line: hex} from a NASM-style listing"""
    out = collections.OrderedDict()
    last = None
    for row in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*(\d+)\s+([0-9A-F]{8})\s+([0-9A-F()\[\]]+)(-?)", row)
        if m:
            n = int(m.group(1))
            out[n] = out.get(n, "") + re.sub(r"[()\[\]]", "", m.group(3))
            last = n
            continue
        m = re.match(r"\s*(\d+)\s+<rep", row)
    return out


def errors_at(stderr, name):
    return sorted({int(m.group(1)) for m in re.finditer(r"%s:(\d+): (?:error|fatal)" % re.escape(name),
                                                      stderr or "", re.M)})


def batch(utasm, lines, bits):
    """[(line text, nasm hex, utasm hex or None)] for the lines NASM takes"""
    with tempdir() as d:
        src = os.path.join(d, "f.s")
        keep = list(lines)
        for _ in range(8):
            open(src, "w").write("bits %d\n" % bits + "".join(l + "\n" for l in keep))
            r = run(["nasm", "-f", "bin", "-l", os.path.join(d, "n.lst"), "f.s", "-o", "n.bin"], cwd=d)
            bad = errors_at(r.stderr, "f.s")
            if not bad and r.returncode == 0:
                break
            if not bad:
                return [], 0
            keep = [l for i, l in enumerate(keep, 2) if i not in bad]
        else:
            return [], 0
        if not keep:
            return [], 0
        r = run([utasm, "-f", "bin", "-l", os.path.join(d, "u.lst"), "f.s", "-o", "u.bin"], cwd=d)
        rejected = errors_at(r.stderr, "f.s")
        findings = []
        for n in rejected:
            if 2 <= n < 2 + len(keep):
                msg = first_error(r.stderr, n)
                kind = ("nasm-bug" if nasm_bogus(keep[n - 2]) or by_design(keep[n - 2], msg) else
                        "gap" if any(re.search(g, keep[n - 2]) for g in KNOWN_GAPS) else "rejects")
                findings.append((kind, keep[n - 2], "", first_error(r.stderr, n)))
        if rejected:
            keep2 = [l for i, l in enumerate(keep, 2) if i not in rejected]
            open(src, "w").write("bits %d\n" % bits + "".join(l + "\n" for l in keep2))
            run(["nasm", "-f", "bin", "-l", os.path.join(d, "n.lst"), "f.s", "-o", "n.bin"], cwd=d)
            r = run([utasm, "-f", "bin", "-l", os.path.join(d, "u.lst"), "f.s", "-o", "u.bin"], cwd=d)
            keep = keep2
            if r.returncode:
                return findings, len(keep)
        nb = listing_bytes(os.path.join(d, "n.lst"))
        ub = listing_bytes(os.path.join(d, "u.lst")) if os.path.exists(os.path.join(d, "u.lst")) else {}
        for i, l in enumerate(keep, 2):
            if nb.get(i) != ub.get(i):
                kind = "bytes"
                if ub.get(i) and nb.get(i) and (equivalent(nb.get(i), ub.get(i), bits)
                                                 or nasm_wrong(l, nb.get(i), ub.get(i), bits)
                                                 or by_design(l)):
                    kind = "nasm-bug"
                findings.append((kind, l, nb.get(i), ub.get(i)))
        return findings, len(keep)


def decode(hexs, bits):
    """objdump's reading of the bytes (Intel syntax), instructions joined by
    " ; " (a long one's bytes wrap onto a line of their own: not one)"""
    if not hexs:
        return ""
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(bytes.fromhex(hexs))
        p = f.name
    arch = {16: "i8086", 32: "i386", 64: "i386:x86-64"}[bits]
    o = run(["objdump", "-D", "-b", "binary", "-m", arch, "-M", "intel", p]).stdout
    os.unlink(p)
    out = []
    for x in o.splitlines():
        f = x.split("	")
        if len(f) >= 3 and re.match(r"\s+[0-9a-f]+:$", f[0]):
            out.append(re.sub(r"\s+", " ", f[2]).strip())
    return " ; ".join(out)


def disp_of(text):
    """the displacement of the first address in text: "[eax+128]" 128,
    "[ebx-0x8]" -8, None when there is no address"""
    m = re.search(r"\[([^\]]*)\]", text)
    if not m:
        return None
    total = 0
    for sign, num in re.findall(r"([+-]?)(?<![\w*])(0x[0-9a-fA-F]+|\d+)(?![\w*])", m.group(1)):
        v = int(num, 0)
        total += -v if sign == "-" else v
    return total


# NASM's forms that are not the instruction's (its insns.dat; Intel's manual
# and objdump agree): utasm refuses them, by design
NASM_BOGUS = [r"^v(get(max|min)|endscale)", r"^vfmulcpch\b", r"^vcvtu?qq2ph [yz]mm",
              r"^vcvtneps2bf16 [^,]+,[^,]+,", r"^vrcpph [^,]+,[^,]+,", r"^vrsqrt(ph|sh) .*, -?\d+$",
              r"^vget(mant|exp)sh [^,]+, [^,\[]+(, -?\d+)?$", r"^vget(mant|exp)sh [^,]+, [^,]*\[",
              r"^vp2intersectd ", r"^vcvtps2ph [^,]+, [^,]+$", r"^vrcpsh .*\{sae\}",
              # narrowing conversions with the source's width: xmm for ymm, ymm for zmm
              r"^vcvtu?dq2ph (ymm\S*, (ymm|yword)|zmm)", r"^vcvtpd2ph [yz]mm",
              # (and with a broadcast: {1to8} of dwords is a ymm, whose half is xmm)
              r"^vcvtu?dq2ph ymm\S*, .*\{1to8\}",
              # vcvtph2udq's memory half of what it is (xmm, m32 for m64 ...)
              r"^vcvtph2udq "]


def nasm_bogus(text):
    return any(re.search(r, text) for r in NASM_BOGUS)


# what utasm refuses or writes otherwise by design (scripts/compat/README):
# a destination that faults (#UD), an address size the register does not
# give, a VEX gather's index of 16-31 (NASM takes xmm24 as xmm8), ICC's
# MIB index over one written, two-operand vget*sh: the first source the
# destination, as for every omitted source (NASM's xmm0)
BY_DESIGN_MSG = ("#UD", "impossible combination of address sizes")
BY_DESIGN = [r"^v(p)?gather\w+ [xy]mm\d+, \w+ \[[^\]]*[xy]mm(1[6-9]|2\d|3[01])\*[^\]]*\], [xy]mm\d+$",
             r"^bnd(ld|st)x (?=.*\*)[^,]*,[^,]*,[^,]*$", r"^vcvtneps2bf16 ymm\d+, (ymm|yword)",
             r"^vget(exp|mant)sh [^,]+, [^,\[]*\[[^\]]*\](, -?\d+)?$", r"^vget(exp|mant)sh [^,]+, [xyz]mm\d+, -?\d+$"]
KNOWN_GAPS = []                              # (rsdc / svdc matched since batch 58)


def by_design(text, msg=""):
    return any(m in (msg or "") for m in BY_DESIGN_MSG) or any(re.search(r, text) for r in BY_DESIGN)


def strip_prefixes(dec):
    words = dec.split(" ; ")[0].split()
    while words and (words[0].startswith("{") or words[0].lower() in
                     ("data16", "addr32", "rex.w", "rex", "lock", "rep", "repz", "repnz", "bnd")):
        words = words[1:]
    return words


def nasm_wrong(text, a, b, bits):
    """utasm's bytes are what is written and NASM's are not, by objdump: the
    address (NASM's disp8*N for the FP16 scalar forms), the mnemonic (its
    VFMADD132PH is Intel's VFNMADD132PH) or the registers (its VREDUCESH)"""
    da, db = decode(a, bits), decode(b, bits)
    want = disp_of(text)
    if want is not None and disp_of(db) == want and disp_of(da) != want:
        return True
    wa, wb = strip_prefixes(da), strip_prefixes(db)
    if not wb or " ; " in db:
        return False
    mn = text.split()[0]
    ok_b = wb[0].lower() == mn and regs_of(text) == regs_of(" ".join(wb[1:]))
    ok_a = bool(wa) and " ; " not in da and wa[0].lower() == mn and regs_of(text) == regs_of(" ".join(wa[1:]))
    return ok_b and not ok_a


def equivalent(a, b, bits):
    """two encodings objdump reads the same (a disp8 for a disp16, VEX for
    EVEX ...)"""
    da, db = decode(a, bits), decode(b, bits)
    da, db = da.replace("{evex} ", ""), db.replace("{evex} ", "")
    return bool(da) and da == db


def first_error(stderr, n):
    m = re.search(r"f\.s:%d: (?:error|fatal): (.*)" % n, stderr or "")
    return m.group(1)[:70] if m else ""


REGS = re.compile(r"\b([re]?[abcd]x|[re]?[sd]i|[re]?[sb]p|r\d+[dwb]?|[abcd][lh]|[sd]il|[sb]pl|"
                  r"[xyz]mm\d+|k[0-7]|mm[0-7]|st\(?[0-7]\)?|st|bnd[0-3]|tmm[0-7]|cr\d|dr\d)\b")
# objdump's prefixes before a mnemonic ("{evex} vcvtsi2ss", "data16 ...")
OBJDUMP_PREFIXES = ("data16", "addr32", "rex.w", "rex", "lock", "rep", "repz", "repnz", "bnd",
                    "notrack", "rex.wb", "rex.wr", "rex.wx")
# NASM's FMA operand-order aliases (vfmadd312ps is vfmadd132ps ...)
FMA_ORDER = {"312": "132", "123": "213", "321": "231"}


def regs_of(text):
    """the registers of an instruction's text, in order: segment overrides
    left out, st as st0, "[r13*2]" (r13 + r13) as objdump writes it"""
    t = re.sub(r"\{[^}]*\}", "", text.lower())
    t = re.sub(r"\[(\w+)\*2([^\]]*)\]", lambda m: "[%s+%s%s]" % (m.group(1), m.group(1), m.group(2))
               if "+" not in m.group(0).split("*")[0] else m.group(0), t)
    out = []
    for r in REGS.findall(t):
        r = r.replace("(", "").replace(")", "")
        out.append("st0" if r == "st" else r)
    return out


def objdump_check(utasm, rng, verbose):
    """every form, twice, in bits 64: utasm's bytes as objdump reads them.
    VEX / EVEX ones (objdump knows them all): one instruction, the same
    mnemonic, the same registers; the others: the registers."""
    lines = []
    for f in forms():
        for _ in range(2):
            try:
                lines.append(instance(f, 64, rng))
            except Skip:
                pass
    bad = collections.defaultdict(list)
    checked = 0
    for i in range(0, len(lines), 300):
        chunk = lines[i:i + 300]
        with tempdir() as d:
            src = os.path.join(d, "f.s")
            open(src, "w").write("bits 64\n" + "".join(l + "\n" for l in chunk))
            r = run([utasm, "-f", "bin", "-l", "u.lst", "f.s", "-o", "u.bin"], cwd=d)
            rejected = set(errors_at(r.stderr, "f.s"))
            if rejected:
                chunk = [l for n, l in enumerate(chunk, 2) if n not in rejected]
                open(src, "w").write("bits 64\n" + "".join(l + "\n" for l in chunk))
                r = run([utasm, "-f", "bin", "-l", "u.lst", "f.s", "-o", "u.bin"], cwd=d)
            if r.returncode:
                continue
            ub = listing_bytes(os.path.join(d, "u.lst"))
        for n, l in enumerate(chunk, 2):
            h = ub.get(n)
            if not h:
                continue
            checked += 1
            dec = decode(h, 64)
            got = dec.split(" ; ")
            words = got[0].split() if got and got[0] else []
            while words and (words[0].startswith("{") or words[0].lower() in OBJDUMP_PREFIXES):
                words = words[1:]
            dmn = words[0].lower() if words else ""
            mnem = l.split()[0]
            m = re.match(r"(vf\w+?)(312|123|321)(\w+)$", mnem)
            want = m.group(1) + FMA_ORDER[m.group(2)] + m.group(3) if m else mnem
            vector = mnem.startswith("v") and not mnem.startswith("vm")    # (vmcall ...: VMX)
            problems = []
            if vector and (len(got) != 1 or dmn == "(bad)"):
                problems.append("%d instructions" % len(got) if len(got) != 1 else "invalid")
            if vector and dmn != want and dmn != "(bad)" and not re.match(r"^v?p?cmp|^vpcom", mnem):
                problems.append("mnemonic %s" % dmn)
            if dmn != "(bad)" and len(got) == 1 and regs_of(l) != regs_of(" ".join(words[1:])):
                problems.append("registers %s" % regs_of(" ".join(words[1:])))
            if problems:
                bad[mnem].append((l, h, dec, ", ".join(problems)))
    n = sum(len(v) for v in bad.values())
    print("encfuzz --objdump: %d instructions read back, %d differ in %d mnemonics"
          % (checked, n, len(bad)))
    for mnem, v in sorted(bad.items(), key=lambda kv: -len(kv[1]))[: (999 if verbose else 40)]:
        l, h, dec, why = v[0]
        print("  %-14s x%-3d %s\n      %s -> %s  (%s)" % (mnem, len(v), l, h, dec[:90], why))
    return 1 if n else 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if "--objdump" in sys.argv:
        return objdump_check(args[0], random.Random(int(args[1]) if len(args) > 1 else 1),
                             "-v" in sys.argv)
    verbose = "-v" in sys.argv
    utasm = args[0]
    total = int(args[1]) if len(args) > 1 else 3000
    seed = int(args[2]) if len(args) > 2 else 1
    rng = random.Random(seed)
    fs = forms()
    checked = 0
    found = collections.defaultdict(list)
    per_batch = 150
    while checked < total:
        bits = rng.choice([64, 64, 64, 32, 16])
        lines = []
        while len(lines) < per_batch:
            try:
                lines.append(instance(rng.choice(fs), bits, rng))
            except Skip:
                continue
        f, n = batch(utasm, lines, bits)
        checked += n
        for kind, text, a, b in f:
            found[(kind, text.split()[0])].append((bits, text, a, b))
    nasm_bugs = sum(len(v) for k, v in found.items() if k[0] == "nasm-bug")
    gaps = sorted({k[1] for k in found if k[0] == "gap"})
    for k in [k for k in found if k[0] in ("nasm-bug", "gap")]:
        del found[k]
    if gaps:
        print("encfuzz: known gaps (not counted): %s" % ", ".join(gaps))
    n_find = sum(len(v) for v in found.values())
    print("encfuzz: %d instructions NASM takes (seed %d), %d findings in %d mnemonics"
          " (%d where NASM's are not the instruction written, or the same)"
          % (checked, seed, n_find, len(found), nasm_bugs))
    for (kind, mnem), v in sorted(found.items(), key=lambda kv: -len(kv[1]))[: (999 if verbose else 25)]:
        bits, text, a, b = v[0]
        if kind == "rejects":
            print("  %-8s %-14s x%-3d bits %d: %s  -- %s" % (kind, mnem, len(v), bits, text, b))
        else:
            print("  %-8s %-14s x%-3d bits %d: %s  nasm %s utasm %s" % (kind, mnem, len(v), bits, text, a, b))
    return 1 if n_find else 0


if __name__ == "__main__":
    sys.exit(main())
