"""Shared helpers for the NASM compatibility suites (scripts/compat/)."""
import os, re, shutil, subprocess, tempfile

# Differences from NASM that are deliberate or not implemented yet. A case
# listed here is reported as "known" and does not fail the run; remove it
# once utasm matches.
KNOWN = {
    # "//" is a comment in utasm (the test suite uses it), so NASM's
    # signed-division operator is not available; %% (signed modulo) is.
    "op_signed_div": "// is a comment in utasm",
    # NASM 2.16.03 gives 0/0/1 for <=>; its manual (and utasm) say -1/0/1.
    "op_cmp3": "NASM's <=> disagrees with its own manual",
    # %+ pastes inside macro bodies only
    "pp_paste": "top-level %+ paste",
    # [2*rbx]: a scale written before the register
    "ins_mem_scale_forms": "number-first scale",
    # one pass: an equ cannot use a symbol defined after it (an error)
    "elf_equ_forward_ref": "equ with a forward reference",
    # one pass: a value worked out at the end keeps room for any value
    "expr push_imm": "push dword: 68 imm32 (NASM: 6A ib once it knows the value)",
    "expr mov_imm64": "mov rax: the 64-bit immediate (NASM: mov eax once it knows the value)",
    # NASM writes a meaningless number for a negated address in an object
    "scalar -l1 back elf64": "NASM's value for -label in an object",
    "scalar 2 - l1 back elf64": "NASM's value for n - label in an object",
    # listings (-l): the encoding differences above show there too
    "listing op_cmp3": "NASM's <=> disagrees with its own manual",
    "listing op_signed_div": "// is a comment in utasm",
    "listing ins_mem_scale_forms": "number-first scale",
    "listing pp_paste": "top-level %+ paste",
    # NASM lists its warnings; utasm does not give these warnings yet
    "listing basic_warning_dir": "%warning text in the listing",
    "listing dir_db_question": "warning: uninitialized space in a non-BSS section",
    "listing dir_dw_question": "warning: uninitialized space in a non-BSS section",
    "listing dir_times_question": "warning: uninitialized space in a non-BSS section",
    "listing dir_section_follows": "warning: unknown section attribute",
    "listing dir_section_vstart": "warning: unknown section attribute",
    "listing ins_multiple_prefix": "warning: superfluous LOCK prefix on XCHG",
    "listing op_shifts": "warning: dword data exceeds bounds",
    # listing details not reproduced
    "listing basic_exitrep": "lines after %exitrep are listed by NASM",
    "listing pp_line": "%line: the text of the renumbered line",
    "listing pp_macro_range": "NASM shows %{2:3} as %2:3",
    "listing pp_nested_macro_def": "a macro defined by a macro: its body lines",
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
