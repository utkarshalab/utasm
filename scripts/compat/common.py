"""Shared helpers for the NASM compatibility suites (scripts/compat/)."""
import os, re, shutil, subprocess, tempfile

# Differences from NASM that are deliberate or not implemented yet. A case
# listed here is reported as "known" and does not fail the run; remove it
# once utasm matches.
KNOWN = {
    # utasm's %use masm does MASM's PROC (frontend/parser/masm.s): USES
    # saves its registers, a far PROC's ret is retf; NASM's package ignores
    # both when more than one word follows "proc" ("j proc far uses rbx")
    "use_masm_proc": "MASM's USES and far kept (NASM's package drops them)",
    "listing use_masm_proc": "MASM's USES and far kept (NASM's package drops them)",
    # "//" is a comment in utasm (the test suite uses it), so NASM's
    # signed-division operator is not available; %% (signed modulo) is.
    "op_signed_div": "// is a comment in utasm",
    # NASM 2.16.03 gives 0/0/1 for <=>; its manual (and utasm) say -1/0/1.
    "op_cmp3": "NASM's <=> disagrees with its own manual",
# a value that measures its own instruction: NASM converges on the short
    # form; utasm keeps the long one (correct, the value of that layout)
    "expr self_add": "add eax, (e - s) * 30 over itself: 05 id (NASM: 83 /0 ib)",
    # NASM writes a meaningless number for a negated address in an object
    "scalar -l1 back elf64": "NASM's value for -label in an object",
    "scalar 2 - l1 back elf64": "NASM's value for n - label in an object",
    # listings (-l): the encoding differences above show there too
    "listing op_cmp3": "NASM's <=> disagrees with its own manual",
    "listing op_signed_div": "// is a comment in utasm",
    # listing details not reproduced
    "listing data_dup": "NASM lists each dup copy and a zeroing warning per ? item",
    "listing pp_ctx_label_macro": "NASM lists %$x's source text for a label before a macro",
    "listing pp_rep_nolist": "NASM lists a .nolist %rep's bytes on its %endrep line",
    "listing struc_base_offset": "NASM lists at's padding as 00<rep 4h>",
    "listing disp8_forced": "NASM gives the [byte x] bounds warning twice (once a pass)",
    "global_declared_first": "utasm relocates against a global symbol itself (as GNU as), NASM against its section",
    "elf_branch_to_number": "utasm relocates a branch to a number against symbol 0 (GNU as's *ABS*): right wherever it is linked; NASM writes a value right only at address 0",
    "listing cross_section_distance": "NASM lists a value across sections before the sections are placed",
    "listing known_runs_settle": "NASM lists a value across sections before the sections are placed",
    "listing displacement_wraps": "NASM warns for [eax + 0xffffffff], an address that wraps exactly to eax - 1",
    "listing ptr_as_label": "the line after \"dword ptr\" is read early: its bytes list there",
# -f win64: a label with no section before it is an undefined external in
    # NASM's object (its .text is made only for code or data); utasm's is a
    # label of .text
    "coff label_only": "a label before any section: NASM makes it external",
}


def run(cmd, cwd=None, timeout=60):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, errors="replace",
                              cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", "timed out")


def first_line(r):
    msg = re.sub(r"\x1b\[[0-9;]*m", "", (r.stdout or "") + (r.stderr or "")).strip().splitlines()
    return msg[0][:90] if msg else ""


def have(tool):
    return shutil.which(tool) is not None


def assemble_bin(utasm, src, d, name="p"):
    """Assemble src with NASM and utasm as flat binaries in directory d.

    Returns (nasm_bytes or None, utasm_bytes or None, utasm_result)."""
    s = os.path.join(d, name + ".s")
    with open(s, "w") as f:
        f.write(src)
    n = os.path.join(d, name + ".n.bin")
    u = os.path.join(d, name + ".u.bin")
    rn = run(["nasm", "-f", "bin", s, "-o", n], cwd=d)
    ru = run([utasm, "-f", "bin", s, "-o", u], cwd=d)
    nb = open(n, "rb").read() if rn.returncode == 0 and os.path.exists(n) else None
    ub = open(u, "rb").read() if ru.returncode == 0 and os.path.exists(u) else None
    return nb, ub, ru


class Suite:
    """Counts results; prints the unexpected ones."""

    def __init__(self, name, verbose=False):
        self.name, self.verbose = name, verbose
        self.ok = self.bad = self.known = self.skipped = 0
        self.failures = []

    def result(self, case, good, detail=""):
        if good:
            self.ok += 1
            if case in KNOWN:
                self.failures.append("%s: now matches NASM -- remove it from KNOWN" % case)
            return
        if case in KNOWN:
            self.known += 1
            if self.verbose:
                print("    known  %-28s %s" % (case, KNOWN[case]))
            return
        self.bad += 1
        self.failures.append("%-28s %s" % (case, detail))

    def skip(self):
        self.skipped += 1

    def report(self):
        extra = []
        if self.known:
            extra.append("%d known" % self.known)
        if self.skipped:
            extra.append("%d skipped (NASM rejects)" % self.skipped)
        print("  %-18s %4d match, %d differ%s" % (
            self.name, self.ok, self.bad, (" (" + ", ".join(extra) + ")") if extra else ""))
        for f in self.failures:
            print("      " + f)
        return self.bad == 0 and not any("remove it from KNOWN" in f for f in self.failures)


def tempdir():
    return tempfile.TemporaryDirectory(prefix="utasm-compat-")
