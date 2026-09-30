"""The NASM compatibility suites. Each takes the utasm binary and returns a
common.Suite; scripts/compat/run_all.py runs them all."""
import collections, concurrent.futures as cf, os, platform, re

from common import Suite, assemble_bin, first_line, run, tempdir
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
