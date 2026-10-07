"""The NASM compatibility suites. Each takes the utasm binary and returns a
common.Suite; scripts/compat/run_all.py runs them all."""
import collections, concurrent.futures as cf, difflib, hashlib, os, platform, re, struct, zlib

from common import Suite, assemble_bin, first_line, have, run, tempdir
import cases, corpus

JOBS = os.cpu_count() or 4


# ---------------------------------------------------------------------------
# feature probes: small programs as flat binaries, byte for byte
# ---------------------------------------------------------------------------
def bin_probes(utasm, verbose=False):
    s = Suite("bin probes", verbose)

    def one(item):
        name, src = item
        if not src.startswith(("bits", "org", "[bits")):
            src = "bits 64\n" + src
        with tempdir() as d:
            nb, ub, ru = assemble_bin(utasm, src, d)
        return name, nb, ub, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, nb, ub, ru in ex.map(one, cases.BIN_PROBES.items()):
            if nb is None:
                s.skip()
            elif ub is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, ub == nb, "nasm %s | utasm %s" % (nb.hex()[:40], ub.hex()[:40]))
    return s


# ---------------------------------------------------------------------------
# ELF objects: sections, contents, relocations, symbols -- all by name
# ---------------------------------------------------------------------------
def elf_view(path):
    secs = run(["readelf", "-SW", path]).stdout
    names, out = {}, []
    for m in re.finditer(r"^\s+\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+[0-9a-f]+\s+[0-9a-f]+\s+([0-9a-f]+)"
                         r"\s+[0-9a-f]+\s+(\S*)\s", secs, re.M):
        idx, name, typ, size, flg = m.groups()
        names[idx] = name
        if name in (".symtab", ".strtab", ".shstrtab") or name.startswith((".rela", ".note")):
            continue
        out.append("S %s %s %s %s" % (name, typ, int(size, 16), flg))
        binf = "%s.%d.bin" % (path, len(out))
        dump = run(["objcopy", "-O", "binary", "--only-section=" + name, path, binf])
        data = open(binf, "rb").read() if dump.returncode == 0 and os.path.exists(binf) else None
        out.append("D %s %s" % (name, data.hex()[:200] if data is not None else "?"))
    for line in run(["readelf", "-rW", path]).stdout.splitlines():
        m = re.match(r"^[0-9a-f]+\s+[0-9a-f]+\s+(R_\S+)\s+[0-9a-f]+\s+(.*)$", line.strip())
        if m:
            out.append("R %s %s" % (m.group(1), re.sub(r"\s+", " ", m.group(2))))
        elif line.startswith("Relocation section"):
            out.append("RS " + line.split("'")[1])
    for line in run(["readelf", "-sW", path]).stdout.splitlines():
        f = line.split()
        if len(f) >= 8 and f[0].rstrip(":").isdigit() and f[3] != "FILE":
            out.append("Y %s %s %s %s %s %s" % (f[7], f[3], f[4], f[5], names.get(f[6], f[6]), f[2]))
    return sorted(out)


def elf_probes(utasm, verbose=False):
    s = Suite("elf probes", verbose)
    for name, src in cases.ELF_PROBES.items():
        with tempdir() as d:
            p = os.path.join(d, "p.s")
            open(p, "w").write(src)
            rn = run(["nasm", "-f", "elf64", p, "-o", os.path.join(d, "n.o")])
            if rn.returncode != 0:
                s.skip()
                continue
            ru = run([utasm, "-f", "elf64", p, "-o", os.path.join(d, "u.o")])
            if ru.returncode != 0:
                s.result(name, False, "utasm error: " + first_line(ru))
                continue
            a = elf_view(os.path.join(d, "n.o"))
            b = elf_view(os.path.join(d, "u.o"))
            sa, sb = set(a), set(b)
            s.result(name, a == b, "nasm-only %s | utasm-only %s" % (sorted(sa - sb)[:3], sorted(sb - sa)[:3]))
    return s


# ---------------------------------------------------------------------------
# data directives, strings, floats, incbin: bytes, or both rejecting
# ---------------------------------------------------------------------------
def data_forms(utasm, verbose=False):
    s = Suite("data forms", verbose)

    def one(i_src):
        i, src = i_src
        with tempdir() as d:
            open(os.path.join(d, "inc.bin"), "w").write("hello-utasm-incbin\n")
            nb, ub, ru = assemble_bin(utasm, "bits 64\n" + src + "\n", d)
        return i, src, nb, ub, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for i, src, nb, ub, ru in ex.map(one, enumerate(cases.DATA_CASES)):
            name = "data#%d %s" % (i, src.splitlines()[0][:30])
            if nb is None and ub is None:
                s.result(name, True)
            elif nb is None:
                s.result(name, False, "NASM rejects it, utasm accepts: %s" % ub.hex()[:40])
            elif ub is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, ub == nb, "nasm %s | utasm %s" % (nb.hex()[:40], ub.hex()[:40]))
    return s


# ---------------------------------------------------------------------------
# section headers of objects, and programs that link and run
# ---------------------------------------------------------------------------
def section_rows(path):
    rows = []
    for m in re.finditer(r"^\s+\[\s*\d+\]\s+(\S+)\s+(\S+)\s+[0-9a-f]+\s+[0-9a-f]+\s+([0-9a-f]+)"
                         r"\s+[0-9a-f]+\s+(\S*)\s+\d+\s+\d+\s+(\d+)$", run(["readelf", "-SW", path]).stdout, re.M):
        name = m.group(1)
        if name in (".symtab", ".strtab", ".shstrtab") or name.startswith((".rela", ".note", ".comment")):
            continue
        rows.append(" ".join(m.groups()))
    return rows


LINKED = [
    # (name, source, --standalone, expected exit status)
    ("link_data", "global _start\nsection .data\nmsg: dq 7\nsection .text\n_start:\n"
                  "    mov edi, [rel msg]\n    mov eax, 60\n    syscall\n", False, 7),
    ("link_moved_text", "global _start\n_start:\n    mov rax, [rel ptr]\n    call rax\n    mov edi, eax\n"
                        "    mov eax, 60\n    syscall\nf:\n    mov eax, [rel val]\n    ret\n"
                        "section .data\nval: dd 9\nptr: dq f\n", False, 9),
    ("link_custom_sections", "global _start\nsection .text\n_start:\n    call helper\n    mov edi, eax\n"
                             "    mov eax, 60\n    syscall\n"
                             "section .text.helper progbits alloc exec nowrite align=16\nhelper:\n"
                             "    mov rax, [rel val]\n    add rax, [rel tbl + 8]\n    ret\n"
                             "section .mydata progbits alloc write align=8\nval: dq 30\n"
                             "section .tables progbits alloc noexec nowrite align=8\ntbl: dq val, 12\n", False, 42),
    ("link_label_immediates", "global _start\nsection .data\ntab: dq 5, 6\nsection .text\n_start:\n"
                              "    mov rsi, tab\n    mov rax, [rsi + 8]\n    cmp rsi, tab\n    jne .bad\n"
                              "    push tab\n    pop rcx\n    add rax, [rcx]\n    mov edi, eax\n"
                              "    mov eax, 60\n    syscall\n.bad:\n    mov edi, 99\n    mov eax, 60\n    syscall\n",
     False, 11),
    ("standalone_sections", "global _start\nsection .text\n_start:\n    call helper\n    add eax, [rel tbl + 4]\n"
                            "    add eax, [rel wval]\n    mov dword [rel scratch], eax\n    add eax, [rel scratch]\n"
                            "    mov edi, eax\n    mov eax, 60\n    syscall\n"
                            "section .text.hot progbits alloc exec nowrite align=16\nhelper:\n"
                            "    mov eax, [rel rodata_val]\n    ret\nsection .rodata\nrodata_val: dd 3\n"
                            "section .tables progbits alloc noexec nowrite align=8\ntbl: dd 100, 4\n"
                            "section .wdata progbits alloc noexec write align=8\nwval: dd 5\n"
                            "section .scratch nobits alloc noexec write align=64\nscratch: resd 4\n", True, 24),
]


def sections(utasm, verbose=False):
    s = Suite("sections/link", verbose)
    for i, src in enumerate(cases.SECTION_CASES):
        name = "sections#%d %s" % (i, src.splitlines()[0][:30])
        with tempdir() as d:
            p = os.path.join(d, "q.s")
            open(p, "w").write(src)
            rn = run(["nasm", "-f", "elf64", p, "-o", os.path.join(d, "n.o")])
            ru = run([utasm, p, "-o", os.path.join(d, "u.o")])
            if rn.returncode != 0:
                s.skip()
                continue
            if ru.returncode != 0:
                s.result(name, False, "utasm error: " + first_line(ru))
                continue
            a, b = section_rows(os.path.join(d, "n.o")), section_rows(os.path.join(d, "u.o"))
            s.result(name, a == b, "nasm %s | utasm %s" % (a, b))
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        return s
    for name, src, standalone, want in LINKED:
        with tempdir() as d:
            p = os.path.join(d, "l.s")
            open(p, "w").write(src)
            exe = os.path.join(d, "l")
            if standalone:
                r = run([utasm, "--standalone", p, "-o", exe])
            else:
                r = run([utasm, p, "-o", os.path.join(d, "l.o")])
                if r.returncode == 0:
                    r = run(["ld", os.path.join(d, "l.o"), "-o", exe])
            if r.returncode != 0:
                s.result(name, False, "build failed: " + first_line(r))
                continue
            os.chmod(exe, 0o755)
            got = run([exe]).returncode
            s.result(name, got == want, "exit %d, want %d" % (got, want))
    return s


# ---------------------------------------------------------------------------
# labels as immediates / displacements: lengths and relocation types
# ---------------------------------------------------------------------------
SYMBOL_INSTRUCTIONS = [
    "mov eax, {L}", "mov rax, {L}", "mov ecx, {L}+8", "mov r9, {L}",
    "mov dword [rbx], {L}", "mov qword [rbx], {L}", "mov word [rbx], {L}",
    "push {L}", "push {L}+4",
    "cmp eax, {L}", "cmp rax, {L}", "add rsi, {L}", "sub edi, {L}",
    "and eax, {L}", "or ecx, {L}", "xor edx, {L}", "test eax, {L}",
    "imul eax, ebx, {L}", "lea rax, [{L}]", "lea rax, [rel {L}]",
    "mov eax, [{L}]", "mov eax, [{L}+rbx]", "mov eax, [rbx*4+{L}]",
    "mov al, [{L}]", "movzx eax, byte [{L}]", "inc dword [{L}]",
    "call {L}", "jmp {L}", "jz {L}",
]


def symbol_imm(utasm, verbose=False):
    s = Suite("label operands", verbose)

    def view(obj):
        d = run(["objdump", "-dr", "--no-show-raw-insn", "-M", "intel", obj]).stdout
        run(["objcopy", "-O", "binary", "--only-section=.text", obj, obj + ".bin"])
        raw = open(obj + ".bin", "rb").read() if os.path.exists(obj + ".bin") else b""
        return len(raw), [m.group(1) for m in re.finditer(r"\s(R_X86_64_\w+)", d)]

    def one(item):
        where, ins = item
        body = ins.format(L="lbl")
        if where == "back":
            src = "section .data\nlbl: dd 1\nsection .text\n" + body + "\n"
        else:
            src = "section .text\n" + body + "\nsection .data\nlbl: dd 1\n"
        with tempdir() as d:
            p = os.path.join(d, "a.s")
            open(p, "w").write(src)
            rn = run(["nasm", "-f", "elf64", p, "-o", os.path.join(d, "n.o")])
            ru = run([utasm, p, "-o", os.path.join(d, "u.o")])
            if rn.returncode != 0:
                return where, body, None, None, ru
            if ru.returncode != 0:
                return where, body, view(os.path.join(d, "n.o")), None, ru
            return where, body, view(os.path.join(d, "n.o")), view(os.path.join(d, "u.o")), ru

    items = [(w, i) for w in ("back", "fwd") for i in SYMBOL_INSTRUCTIONS]
    with cf.ThreadPoolExecutor(JOBS) as ex:
        for where, body, a, b, ru in ex.map(one, items):
            name = "%s %s" % (where, body)
            if a is None:
                s.skip()
            elif b is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, a == b, "nasm %s | utasm %s" % (a, b))
    return s


# ---------------------------------------------------------------------------
# the encoder corpus: every instruction alone, byte for byte
# ---------------------------------------------------------------------------
def corpus_lines():
    body = corpus.coverage_source()
    seen, out = set(), []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.endswith(":") or line.startswith(("db ", "[", "section", "global", "bits")):
            continue
        if line not in seen:
            seen.add(line)
            out.append(line)
    return out


def encoder(utasm, verbose=False):
    s = Suite("encoder corpus", verbose)

    def one(line):
        with tempdir() as d:
            nb, ub, ru = assemble_bin(utasm, "bits 64\nsection .text\n" + line + "\n", d)
        return line, nb, ub, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for line, nb, ub, ru in ex.map(one, corpus_lines()):
            if nb is None:
                s.skip()
            elif ub is None:
                s.result(line, False, "utasm error: " + first_line(ru))
            else:
                s.result(line, ub == nb, "nasm %s | utasm %s" % (nb.hex(" "), ub.hex(" ")))
    return s


# ---------------------------------------------------------------------------
# the disassembler against objdump
# ---------------------------------------------------------------------------
def _norm(t):
    t = re.sub(r"\s*#.*$", "", t)
    t = re.sub(r"\s*<[^>]*>", "", t)
    return re.sub(r"\s+", " ", t).strip()


def _parse(text, ours):
    res, sec = {}, None
    for line in text.splitlines():
        m = re.match(r"Disassembly of section '(.*)':" if ours else r"Disassembly of section (.*):", line)
        if m:
            sec = m.group(1)
            continue
        m = (re.match(r"^  ([0-9a-f]{8,}):\s+((?:[0-9a-f]{2} )+)\s*(.*)$", line) if ours
             else re.match(r"^\s+([0-9a-f]+):\t([0-9a-f ]+)\t(.*)$", line))
        if m and sec is not None:
            res[(sec, int(m.group(1), 16))] = (m.group(2).split(), _norm(m.group(3)))
    return res


def disasm(utasm, verbose=False, objects=()):
    s = Suite("disassembler", verbose)
    with tempdir() as d:
        src = os.path.join(d, "cov.s")
        open(src, "w").write(corpus.coverage_source())
        obj = os.path.join(d, "cov.o")
        if run(["nasm", "-f", "elf64", src, "-o", obj]).returncode != 0:
            s.skip()
            return s
        bad = collections.Counter()
        example = {}
        for f in list(objects) + [obj]:
            r = run([utasm, "--disasm", f], timeout=120)
            if r.returncode != 0:
                s.result("disasm " + os.path.basename(f), False, "utasm failed: " + first_line(r))
                continue
            ours = _parse(r.stdout, True)
            ref = _parse(run(["objdump", "-d", "-M", "intel", "-w", f]).stdout, False)
            for k, (rb, rt) in ref.items():
                o = ours.get(k)
                if o and o[0] == rb and o[1] == rt:
                    s.ok += 1
                    continue
                mn = rt.split(" ")[0] if rt else "?"
                bad[mn] += 1
                example.setdefault(mn, "%s: objdump '%s' | utasm '%s'" % (" ".join(rb), rt, o[1] if o else "-"))
        for mn, n in bad.most_common():
            s.bad += n
            s.failures.append("%-10s x%d  %s" % (mn, n, example[mn]))
    return s


# ---------------------------------------------------------------------------
# UBF boot images (-f ubf): the layout tattvaos boot/stage2/fs/ubf.asm reads
# ---------------------------------------------------------------------------
UBF_KERNEL = """bits 64
org 0x100000
section .text
pad: db 0x90, 0x90
_start:
    mov eax, [rel msg]
    jmp $
section .data
msg: db 'hello from ubf'
"""


def ubf(utasm, verbose=False):
    s = Suite("ubf images", verbose)
    with tempdir() as d:
        k = os.path.join(d, "k.s")
        open(k, "w").write(UBF_KERNEL)
        cfg = b"console=serial root=/dev/uvd0 quiet"
        rd = bytes((i * 37 + 11) & 0xFF for i in range(1500))
        open(os.path.join(d, "cfg.txt"), "wb").write(cfg)
        open(os.path.join(d, "rd.bin"), "wb").write(rd)
        img = os.path.join(d, "img.ubf")
        r = run([utasm, "-f", "ubf", k, "--ubf-add", "config=cfg.txt@0x200000",
                 "--ubf-add", "initrd=rd.bin@0x300000", "-o", img], cwd=d)
        rb = run([utasm, "-f", "bin", k, "-o", os.path.join(d, "k.bin")], cwd=d)
        if r.returncode != 0 or rb.returncode != 0:
            s.result("ubf build", False, "utasm failed: " + first_line(r if r.returncode else rb))
            return s
        data = open(img, "rb").read()
        kern = open(os.path.join(d, "k.bin"), "rb").read()
        hdr = data[:1024]
        magic, version, total, count, crc, flags = struct.unpack_from("<QIIIII", hdr, 0)
        s.result("ubf magic", magic == 0x54414D524F465255, hex(magic))
        s.result("ubf version", version == 1, str(version))
        s.result("ubf count", count == 3, str(count))
        s.result("ubf flags", flags == 0, str(flags))
        s.result("ubf total sectors", total * 512 == len(data), "%d sectors, %d bytes" % (total, len(data)))
        zeroed = hdr[:0x14] + b"\0\0\0\0" + hdr[0x18:]
        s.result("ubf header crc32", crc == zlib.crc32(zeroed) & 0xFFFFFFFF, "%08x vs %08x" % (crc, zlib.crc32(zeroed)))
        want = [(1, kern, 0x100000, 2), (4, cfg, 0x200000, 0), (2, rd, 0x300000, 0)]
        next_sector = 2
        for i, (typ, body, load, entry) in enumerate(want):
            t, start, size, ld, ent, fl = struct.unpack_from("<IIIIII", hdr, 0x20 + 64 * i)
            digest = hdr[0x20 + 64 * i + 0x18:0x20 + 64 * i + 0x38]
            name = "ubf component %d" % i
            s.result(name + " fields", (t, start, size, ld, ent) == (typ, next_sector, len(body), load, entry),
                     "type %d start %d size %d load %x entry %d" % (t, start, size, ld, ent))
            s.result(name + " bytes", data[start * 512:start * 512 + size] == body, "content differs")
            s.result(name + " sha256", digest == hashlib.sha256(body).digest(), digest.hex())
            next_sector += (len(body) + 511) // 512
        s.result("ubf end", total == next_sector, "%d vs %d" % (total, next_sector))
        bad = run([utasm, "-f", "ubf", k, "--ubf-add", "nosuch=cfg.txt", "-o", img], cwd=d)
        s.result("ubf bad --ubf-add", bad.returncode != 0, "accepted an unknown component type")
    return s


# ---------------------------------------------------------------------------
# operand shapes: valid and invalid operand pairings, NASM's verdict
# ---------------------------------------------------------------------------
def operand_shapes(utasm, verbose=False):
    s = Suite("operand shapes", verbose)

    def one(line):
        with tempdir() as d:
            nb, ub, ru = assemble_bin(utasm, "bits 64\n" + line + "\n", d)
            return line, nb, ub, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for line, nb, ub, ru in ex.map(one, cases.shape_lines()):
            if nb is None:
                s.result(line, ub is None, "NASM rejects it, utasm gives " + (ub or b"").hex())
            elif ub is None:
                s.result(line, False, "utasm error: " + first_line(ru))
            else:
                s.result(line, nb == ub, "nasm %s | utasm %s" % (nb.hex(), ub.hex()))
    return s


# ---------------------------------------------------------------------------
# diagnostics: the first error at the same file and line as NASM's
# ---------------------------------------------------------------------------
def _first_error(r):
    for line in re.sub(r"\x1b\[[0-9;]*m", "", (r.stdout or "") + (r.stderr or "")).splitlines():
        m = re.match(r"(\S+?):(\d+): (?:error|fatal): ", line)
        if m:
            return "%s:%s" % (os.path.basename(m.group(1)), m.group(2))
    return None


def diagnostics(utasm, verbose=False):
    s = Suite("diagnostics", verbose)

    def one(case):
        name, files = case
        if isinstance(files, str):
            files = {"main.s": files}
        with tempdir() as d:
            for fn, text in files.items():
                open(os.path.join(d, fn), "w").write(text)
            rn = run(["nasm", "-f", "elf64", "main.s", "-o", "n.o"], cwd=d)
            ru = run([utasm, "-f", "elf64", "main.s", "-o", "u.o"], cwd=d)
            return name, rn, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, rn, ru in ex.map(one, cases.DIAG_CASES):
            if rn.returncode == 0:
                s.skip()
            elif ru.returncode == 0:
                s.result(name, False, "utasm accepts it; NASM: " + first_line(rn))
            else:
                want, got = _first_error(rn), _first_error(ru)
                s.result(name, want == got, "nasm %s | utasm %s (%s)" % (want, got, first_line(ru)))
    return s


# ---------------------------------------------------------------------------
# the command line: NASM's options give NASM's results
# ---------------------------------------------------------------------------
def command_line(utasm, verbose=False):
    s = Suite("command line", verbose)

    def one(case):
        name, args, kind = case
        with tempdir() as d:
            for fn, text in cases.CLI_FILES.items():
                p = os.path.join(d, fn)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                open(p, "w").write(text)
            if kind == "bin":
                rn = run(["nasm"] + args + ["-o", "n.bin"], cwd=d)
                ru = run([utasm] + args + ["-o", "u.bin"], cwd=d)
                a = open(os.path.join(d, "n.bin"), "rb").read() if rn.returncode == 0 else None
                b = open(os.path.join(d, "u.bin"), "rb").read() if ru.returncode == 0 else None
                return name, a, b, ru
            if kind == "deps":
                rn = run(["nasm"] + args, cwd=d)
                ru = run([utasm] + args, cwd=d)
                return name, rn.stdout if rn.returncode == 0 else None, \
                    ru.stdout if ru.returncode == 0 else None, ru
            # -E: the preprocessed text must assemble to NASM's binary
            src = args[-1]
            rn = run(["nasm"] + args + ["-o", "n.bin"], cwd=d)
            ru = run([utasm, "-E", src, "-o", "pp.s.out"], cwd=d)
            if ru.returncode == 0:
                ru = run([utasm, "-f", "bin", "pp.s.out", "-o", "u.bin"], cwd=d)
            a = open(os.path.join(d, "n.bin"), "rb").read() if rn.returncode == 0 else None
            b = open(os.path.join(d, "u.bin"), "rb").read() if ru.returncode == 0 else None
            return name, a, b, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, a, b, ru in ex.map(one, cases.CLI_CASES):
            if a is None:
                s.skip()
            elif b is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, a == b, "nasm %r | utasm %r" % (a[:60], b[:60]))
    return s


# ---------------------------------------------------------------------------
# listings (-l): line for line what NASM writes
# ---------------------------------------------------------------------------
def listing(utasm, verbose=False):
    s = Suite("listings", verbose)

    def one(item):
        name, src = item
        with tempdir() as d:
            open(os.path.join(d, "p.s"), "w").write(src)
            open(os.path.join(d, "inc.bin"), "wb").write(bytes(range(16)))
            rn = run(["nasm", "-f", "elf64", "p.s", "-l", "n.lst", "-o", "n.o"], cwd=d)
            ru = run([utasm, "-f", "elf64", "p.s", "-l", "u.lst", "-o", "u.o"], cwd=d)
            a = open(os.path.join(d, "n.lst")).read() if rn.returncode == 0 else None
            b = open(os.path.join(d, "u.lst")).read() if ru.returncode == 0 else None
            return name, a, b, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, a, b, ru in ex.map(one, sorted(cases.BIN_PROBES.items())):
            case = "listing " + name
            if a is None:
                s.skip()
            elif b is None:
                s.result(case, False, "utasm error: " + first_line(ru))
            else:
                diff = [l for l in difflib.unified_diff(a.splitlines(), b.splitlines(), n=0, lineterm="")][2:4]
                s.result(case, a == b, " | ".join(diff))
    return s


# ---------------------------------------------------------------------------
# DWARF (-g): the decoded line table rows NASM writes
# ---------------------------------------------------------------------------
def _line_rows(obj):
    out = run(["objdump", "--dwarf=decodedline", obj]).stdout
    return [" ".join(l.split()[:3]) for l in out.splitlines()
            if re.match(r"^\S+\s+(\d+|-)\s+(0x[0-9a-f]+|0)\b", l)]


def dwarf(utasm, verbose=False):
    s = Suite("dwarf line tables", verbose)

    def one(item):
        name, src = item
        with tempdir() as d:
            for fn, text in cases.DWARF_FILES.items():
                open(os.path.join(d, fn), "w").write(text)
            open(os.path.join(d, "p.s"), "w").write(src)
            rn = run(["nasm", "-g", "-F", "dwarf", "-f", "elf64", "p.s", "-o", "n.o"], cwd=d)
            ru = run([utasm, "-g", "-f", "elf64", "p.s", "-o", "u.o"], cwd=d)
            if rn.returncode != 0:
                return name, None, None, ru
            if ru.returncode != 0:
                return name, _line_rows(os.path.join(d, "n.o")), None, ru
            return name, _line_rows(os.path.join(d, "n.o")), _line_rows(os.path.join(d, "u.o")), ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, a, b, ru in ex.map(one, sorted(cases.DWARF_CASES.items())):
            if a is None:
                s.skip()
            elif b is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, a == b, "nasm %s | utasm %s" % (a[:6], b[:6]))
    return s


# ---------------------------------------------------------------------------
# bits 32 / bits 16: the encoder corpus in the other modes
# ---------------------------------------------------------------------------
# NASM takes some registers that do not exist outside 64-bit mode in VEX and
# EVEX instructions (vmovq rax, xmm16 ...); utasm rejects them, which counts
# as agreeing.
_WIDE = re.compile(r"\b(r[a-ds]x|r[sd]i|r[sb]p|r\d+[dwb]?|[xyz]mm(1[6-9]|2\d|3[01])|kmovq)\b")


def modes(utasm, verbose=False):
    s = Suite("bits 32 / bits 16", verbose)
    lines = [l for l in corpus_lines()]

    def one(item):
        bits, line = item
        with tempdir() as d:
            nb, ub, ru = assemble_bin(utasm, "bits %d\n%s\n" % (bits, line), d)
            return bits, line, nb, ub, ru

    items = [(b, l) for b in (32, 16) for l in lines]
    with cf.ThreadPoolExecutor(JOBS) as ex:
        for bits, line, nb, ub, ru in ex.map(one, items):
            name = "bits %d: %s" % (bits, line)
            if nb is None:
                s.result(name, ub is None, "NASM rejects it, utasm gives " + (ub or b"").hex())
            elif ub is None:
                s.result(name, bool(_WIDE.search(line)), "utasm error: " + first_line(ru))
            else:
                s.result(name, nb == ub, "nasm %s | utasm %s" % (nb.hex(), ub.hex()))
    return s


# ---------------------------------------------------------------------------
# -f elf32: i386 objects, contents and relocations as NASM writes them
# ---------------------------------------------------------------------------
def _elf32_view(obj):
    d = run(["objdump", "-dr", "-s", obj]).stdout.splitlines()[3:]
    syms = sorted(" ".join(l.split()[3:5] + l.split()[7:8]) for l in
                  run(["readelf", "-sW", obj]).stdout.splitlines()
                  if re.match(r"\s*\d+:", l) and "FILE" not in l and "SECTION" not in l)
    return "\n".join(d), syms


def elf32(utasm, verbose=False):
    s = Suite("elf32 objects", verbose)

    def one(item):
        name, src = item
        with tempdir() as d:
            p = os.path.join(d, "p.s")
            open(p, "w").write(src)
            rn = run(["nasm", "-f", "elf32", p, "-o", os.path.join(d, "n.o")])
            ru = run([utasm, "-f", "elf32", p, "-o", os.path.join(d, "u.o")])
            if rn.returncode:
                return name, None, None, ru
            if ru.returncode:
                return name, _elf32_view(os.path.join(d, "n.o")), None, ru
            return name, _elf32_view(os.path.join(d, "n.o")), _elf32_view(os.path.join(d, "u.o")), ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, a, b, ru in ex.map(one, sorted(cases.ELF32_CASES.items())):
            if a is None:
                s.skip()
            elif b is None:
                s.result(name, False, "utasm error: " + first_line(ru))
            else:
                s.result(name, a == b, "contents %s, symbols %s" %
                         ("same" if a[0] == b[0] else "differ", "same" if a[1] == b[1] else "%s | %s" % (a[1], b[1])))
    # a program that runs
    if have("ld"):
        with tempdir() as d:
            p = os.path.join(d, "h.s")
            open(p, "w").write(cases.ELF32_HELLO)
            ru = run([utasm, "-f", "elf32", p, "-o", os.path.join(d, "h.o")])
            rl = run(["ld", "-m", "elf_i386", os.path.join(d, "h.o"), "-o", os.path.join(d, "h")])
            if ru.returncode == 0 and rl.returncode == 0:
                rr = run([os.path.join(d, "h")])
                s.result("elf32 program runs", rr.returncode == 42 and rr.stdout == "elf32\n",
                         "exit %d, output %r" % (rr.returncode, rr.stdout))
            elif ru.returncode:
                s.result("elf32 program runs", False, "utasm error: " + first_line(ru))
            else:
                s.skip()
    return s


# ---------------------------------------------------------------------------
# expressions: labels defined later in arithmetic, and NASM's scalar rule
# ---------------------------------------------------------------------------
def _error_text(r):
    for line in re.sub(r"\x1b\[[0-9;]*m", "", (r.stdout or "") + (r.stderr or "")).splitlines():
        m = re.search(r"error: (.*)", line)
        if m:
            return m.group(1).strip()
    return ""


def _crashed(r):
    return r.returncode < 0 or r.returncode >= 128 and r.returncode != 124


def _object_view(path):
    out = run(["objdump", "-s", "-r", path]).stdout
    return [l for l in out.splitlines()[2:] if l.strip()]


def _compare_one(utasm, name, fmt, src, files=None):
    """NASM and utasm on one source: (name, nasm result, utasm result, nasm
    output view, utasm output view); the views are None unless both
    assembled it."""
    with tempdir() as d:
        for fn, text in (files or {}).items():
            open(os.path.join(d, fn), "w").write(text)
        open(os.path.join(d, "p.s"), "w").write(src)
        rn = run(["nasm", "-f", fmt, "p.s", "-o", "n.out"], cwd=d)
        ru = run([utasm, "-f", fmt, "p.s", "-o", "u.out"], cwd=d)
        if rn.returncode or ru.returncode:
            return name, rn, ru, None, None
        if fmt == "bin":
            a = open(os.path.join(d, "n.out"), "rb").read().hex()
            b = open(os.path.join(d, "u.out"), "rb").read().hex()
        else:
            a, b = _object_view(os.path.join(d, "n.out")), _object_view(os.path.join(d, "u.out"))
        return name, rn, ru, a, b


def expressions(utasm, verbose=False):
    s = Suite("expressions", verbose)
    jobs = [("expr " + n, "bin", src) for n, src in cases.EXPR_BIN.items()]
    jobs += [("expr " + n, "elf64", src) for n, src in cases.EXPR_ELF.items()]
    scalar = set()
    for e in cases.SCALAR_EXPRS:
        for where, src in (("back", "nop\nl1: dd 0\ndd %s\n" % e), ("fwd", "dd %s\nnop\nl1: dd 0\n" % e)):
            for fmt in ("bin", "elf64"):
                name = "scalar %s %s %s" % (e, where, fmt)
                scalar.add(name)
                jobs.append((name, fmt, ("org 0x100\n" if fmt == "bin" else "") + src))

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, rn, ru, a, b in ex.map(lambda j: _compare_one(utasm, *j), jobs):
            if _crashed(ru):
                s.result(name, False, "utasm crashed")
            elif rn.returncode and ru.returncode:
                # both refuse it: the same message (NASM's scalar errors)
                want, got = _error_text(rn), _error_text(ru)
                s.result(name, want == got or name not in scalar, "nasm: %s | utasm: %s" % (want, got))
            elif rn.returncode:
                if name in scalar:
                    s.result(name, False, "NASM: %s; utasm accepts it" % _error_text(rn))
                else:
                    s.skip()
            elif ru.returncode:
                s.result(name, False, "utasm: " + first_line(ru))
            else:
                s.result(name, a == b, "nasm %s | utasm %s" % (str(a)[:60], str(b)[:60]))

    # where the value is needed when the line is read, utasm (one pass)
    # refuses a label defined later - an error, never a wrong value
    for name, src in cases.EXPR_REJECT.items():
        with tempdir() as d:
            open(os.path.join(d, "p.s"), "w").write(src)
            ru = run([utasm, "-f", "bin", "p.s", "-o", "u.out"], cwd=d)
        s.result("expr " + name, ru.returncode != 0 and not _crashed(ru),
                 "crashed" if _crashed(ru) else "accepted: it must be an error")
    return s


# ---------------------------------------------------------------------------
# limits: inputs past utasm's old fixed limits (tokens on a times line, macro
# parameters, body sizes, nesting depths, buffer lengths, section counts)
# ---------------------------------------------------------------------------
def limits(utasm, verbose=False):
    s = Suite("limits", verbose)
    jobs = [(n, fmt, src, files) for n, (src, files, fmt) in cases.limit_cases().items()]
    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, rn, ru, a, b in ex.map(lambda j: _compare_one(utasm, *j), jobs):
            if _crashed(ru):
                s.result(name, False, "utasm crashed")
            elif rn.returncode:
                s.skip()
            elif ru.returncode:
                s.result(name, False, "utasm: " + first_line(ru))
            else:
                s.result(name, a == b, "outputs differ")
    return s


# ---------------------------------------------------------------------------
# robustness: inputs that crashed or hung utasm before - it must finish,
# with no internal error, and accept or reject each as NASM does
# ---------------------------------------------------------------------------
def robustness(utasm, verbose=False):
    s = Suite("robustness", verbose)

    def one(case):
        name, src, fmt, opts = case
        with tempdir() as d:
            open(os.path.join(d, "p.s"), "w").write(src)
            rn = run(["nasm", "-f", fmt, "p.s", "-o", "n.out"] + opts, cwd=d)
            ru = run([utasm, "-f", fmt, "p.s", "-o", "u.out"] + opts, cwd=d, timeout=10)
        return name, rn, ru

    with cf.ThreadPoolExecutor(JOBS) as ex:
        for name, rn, ru in ex.map(one, cases.ROBUST_CASES):
            if ru.returncode == 124:
                s.result(name, False, "utasm did not finish in 10 s")
            elif _crashed(ru) or "internal error" in (ru.stderr or ""):
                s.result(name, False, "utasm crashed: " + first_line(ru))
            else:
                s.result(name, (rn.returncode == 0) == (ru.returncode == 0),
                         "nasm rc %d | utasm rc %d: %s" % (rn.returncode, ru.returncode, first_line(ru)))
    return s
