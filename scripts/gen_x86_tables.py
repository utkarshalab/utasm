#!/usr/bin/env python3
"""
gen_x86_tables.py - regenerate tools/disasm/x86_tables.inc

The x86-64 disassembler (tools/disasm/x86.s) is table driven. This script
holds the opcode map in readable form and writes the compact tables the
decoder reads:

  x86_names   NUL-terminated mnemonics (offsets are computed here, so the
              assembly needs no label arithmetic)
  x86_map1    256 entries for one-byte opcodes
  x86_map2    256 entries for 0F xx opcodes
  x86_groups  8 entries per ModRM.reg group (80/81/83, C0/C1/D0-D3, ...)

Each entry is 4 bytes: dw name (or group number when F_GROUP), db form,
db flags. Forms and flags must match the constants in tools/disasm/x86.s.

    python3 scripts/gen_x86_tables.py           regenerate
    python3 scripts/gen_x86_tables.py --check   fail if out of date
"""

import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, "tools", "disasm", "x86_tables.inc")

# ---- operand forms (keep in sync with FM_* in tools/disasm/x86.s) ----
FORMS = """NONE EbGb EvGv GbEb GvEv ALIb eAXIz Zv ZbIb ZvIv Jb Jz Eb Ev
EbIb EvIz EvIb Eb1 Ev1 EbCL EvCL EbIbU EvIbU GvM GvEvIz GvEvIb GvEb GvEw
GvEd IbU IbS Iz Iw ZvXchg EvGv_bt EvGvIb EvGvCL STR XCHG90 CBW CWD
Ewv G7 GAE""".split()
FM = {name: i for i, name in enumerate(FORMS)}

# ---- flags (keep in sync with FL_* in tools/disasm/x86.s) ----
F_MODRM, F_GROUP, F_BYTE, F_D64, F_F64 = 1, 2, 4, 8, 16

CC = ["o", "no", "b", "ae", "e", "ne", "be", "a", "s", "ns", "p", "np", "l", "ge", "le", "g"]

map1, map2 = {}, {}
groups = []          # list of 8-entry lists: (name, form or None, flags)
group_ids = {}

def op(table, code, name, form, flags=0):
    table[code] = (name, FM[form], flags)

def group(gname, entries):
    """entries: list of 8 (name, form, flags) or None for invalid."""
    group_ids[gname] = len(groups)
    groups.append(entries)
    return len(groups) - 1

def grp_op(table, code, gname, form, flags=0):
    table[code] = (group_ids[gname], FM[form], flags | F_GROUP | F_MODRM)

# ---------------- groups ----------------
alu = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"]
group("g1", [(n, None, 0) for n in alu])
group("g1a", [("pop", None, F_D64)] + [None] * 7)
group("g2", [("rol", None, 0), ("ror", None, 0), ("rcl", None, 0), ("rcr", None, 0),
             ("shl", None, 0), ("shr", None, 0), None, ("sar", None, 0)])
group("g3b", [("test", "EbIb", 0), None, ("not", "Eb", 0), ("neg", "Eb", 0),
              ("mul", "Eb", 0), ("imul", "Eb", 0), ("div", "Eb", 0), ("idiv", "Eb", 0)])
group("g3v", [("test", "EvIz", 0), None, ("not", "Ev", 0), ("neg", "Ev", 0),
              ("mul", "Ev", 0), ("imul", "Ev", 0), ("div", "Ev", 0), ("idiv", "Ev", 0)])
group("g4", [("inc", None, 0), ("dec", None, 0)] + [None] * 6)
group("g5", [("inc", "Ev", 0), ("dec", "Ev", 0), ("call", "Ev", F_F64), None,
             ("jmp", "Ev", F_F64), None, ("push", "Ev", F_D64), None])
group("g8", [None] * 4 + [("bt", None, 0), ("bts", None, 0), ("btr", None, 0), ("btc", None, 0)])
group("g11", [("mov", None, 0)] + [None] * 7)
group("gnop", [("nop", None, 0)] + [None] * 7)
group("g6", [("sldt", None, 0), ("str", None, 0), ("lldt", None, 0), ("ltr", None, 0),
             ("verr", None, 0), ("verw", None, 0), None, None])
# 0F 01 and 0F AE mix register-only and memory-only encodings that do not
# fit a ModRM.reg group; x86.s decodes them itself (forms G7 and GAE) and
# holds their mnemonics.

# ---------------- one-byte opcodes ----------------
for i, n in enumerate(alu):
    b = i * 8
    op(map1, b + 0, n, "EbGb", F_MODRM | F_BYTE)
    op(map1, b + 1, n, "EvGv", F_MODRM)
    op(map1, b + 2, n, "GbEb", F_MODRM | F_BYTE)
    op(map1, b + 3, n, "GvEv", F_MODRM)
    op(map1, b + 4, n, "ALIb", F_BYTE)
    op(map1, b + 5, n, "eAXIz")
for r in range(8):
    op(map1, 0x50 + r, "push", "Zv", F_D64)
    op(map1, 0x58 + r, "pop", "Zv", F_D64)
op(map1, 0x63, "movsxd", "GvEd", F_MODRM)
op(map1, 0x68, "push", "Iz", F_D64)
op(map1, 0x69, "imul", "GvEvIz", F_MODRM)
op(map1, 0x6A, "push", "IbS", F_D64)
op(map1, 0x6B, "imul", "GvEvIb", F_MODRM)
for i, c in enumerate(CC):
    op(map1, 0x70 + i, "j" + c, "Jb")
grp_op(map1, 0x80, "g1", "EbIb", F_BYTE)
grp_op(map1, 0x81, "g1", "EvIz")
grp_op(map1, 0x83, "g1", "EvIb")
op(map1, 0x84, "test", "EbGb", F_MODRM | F_BYTE)
op(map1, 0x85, "test", "EvGv", F_MODRM)
op(map1, 0x86, "xchg", "EbGb", F_MODRM | F_BYTE)
op(map1, 0x87, "xchg", "EvGv", F_MODRM)
op(map1, 0x88, "mov", "EbGb", F_MODRM | F_BYTE)
op(map1, 0x89, "mov", "EvGv", F_MODRM)
op(map1, 0x8A, "mov", "GbEb", F_MODRM | F_BYTE)
op(map1, 0x8B, "mov", "GvEv", F_MODRM)
op(map1, 0x8D, "lea", "GvM", F_MODRM)
grp_op(map1, 0x8F, "g1a", "Ev")
op(map1, 0x90, "nop", "XCHG90")
for r in range(1, 8):
    op(map1, 0x90 + r, "xchg", "ZvXchg")
op(map1, 0x98, "cwde", "CBW")
op(map1, 0x99, "cdq", "CWD")
for code, name in ((0xA4, "movs"), (0xA5, "movs"), (0xA6, "cmps"), (0xA7, "cmps"),
                   (0xAA, "stos"), (0xAB, "stos"), (0xAC, "lods"), (0xAD, "lods"),
                   (0xAE, "scas"), (0xAF, "scas")):
    op(map1, code, name, "STR", F_BYTE if code % 2 == 0 else 0)
op(map1, 0xA8, "test", "ALIb", F_BYTE)
op(map1, 0xA9, "test", "eAXIz")
for r in range(8):
    op(map1, 0xB0 + r, "mov", "ZbIb", F_BYTE)
    op(map1, 0xB8 + r, "mov", "ZvIv")
grp_op(map1, 0xC0, "g2", "EbIbU", F_BYTE)
grp_op(map1, 0xC1, "g2", "EvIbU")
op(map1, 0xC2, "ret", "Iw")
op(map1, 0xC3, "ret", "NONE")
grp_op(map1, 0xC6, "g11", "EbIb", F_BYTE)
grp_op(map1, 0xC7, "g11", "EvIz")
op(map1, 0xC9, "leave", "NONE")
op(map1, 0xCC, "int3", "NONE")
op(map1, 0xCD, "int", "IbU")
grp_op(map1, 0xD0, "g2", "Eb1", F_BYTE)
grp_op(map1, 0xD1, "g2", "Ev1")
grp_op(map1, 0xD2, "g2", "EbCL", F_BYTE)
grp_op(map1, 0xD3, "g2", "EvCL")
op(map1, 0xE0, "loopne", "Jb")
op(map1, 0xE1, "loope", "Jb")
op(map1, 0xE2, "loop", "Jb")
op(map1, 0xE3, "jrcxz", "Jb")
op(map1, 0xE8, "call", "Jz", F_F64)
op(map1, 0xE9, "jmp", "Jz", F_F64)
op(map1, 0xEB, "jmp", "Jb")
op(map1, 0xF4, "hlt", "NONE")
op(map1, 0xF5, "cmc", "NONE")
grp_op(map1, 0xF6, "g3b", "Eb", F_BYTE)
grp_op(map1, 0xF7, "g3v", "Ev")
op(map1, 0xF8, "clc", "NONE")
op(map1, 0xF9, "stc", "NONE")
op(map1, 0xFA, "cli", "NONE")
op(map1, 0xFB, "sti", "NONE")
op(map1, 0xFC, "cld", "NONE")
op(map1, 0xFD, "std", "NONE")
grp_op(map1, 0xFE, "g4", "Eb", F_BYTE)
grp_op(map1, 0xFF, "g5", "Ev")

# ---------------- two-byte opcodes (0F xx) ----------------
grp_op(map2, 0x00, "g6", "Ewv")
op(map2, 0x01, "(0f01)", "G7", F_MODRM)
op(map2, 0x05, "syscall", "NONE")
op(map2, 0x07, "sysret", "NONE")
op(map2, 0x0B, "ud2", "NONE")
grp_op(map2, 0x1F, "gnop", "Ev")
op(map2, 0x31, "rdtsc", "NONE")
for i, c in enumerate(CC):
    op(map2, 0x40 + i, "cmov" + c, "GvEv", F_MODRM)
    op(map2, 0x80 + i, "j" + c, "Jz", F_F64)
    op(map2, 0x90 + i, "set" + c, "Eb", F_MODRM | F_BYTE)
op(map2, 0xA2, "cpuid", "NONE")
op(map2, 0xA3, "bt", "EvGv_bt", F_MODRM)
op(map2, 0xA4, "shld", "EvGvIb", F_MODRM)
op(map2, 0xA5, "shld", "EvGvCL", F_MODRM)
op(map2, 0xAB, "bts", "EvGv_bt", F_MODRM)
op(map2, 0xAC, "shrd", "EvGvIb", F_MODRM)
op(map2, 0xAD, "shrd", "EvGvCL", F_MODRM)
op(map2, 0xAE, "(0fae)", "GAE", F_MODRM)
op(map2, 0xAF, "imul", "GvEv", F_MODRM)
op(map2, 0xB0, "cmpxchg", "EbGb", F_MODRM | F_BYTE)
op(map2, 0xB1, "cmpxchg", "EvGv", F_MODRM)
op(map2, 0xB3, "btr", "EvGv_bt", F_MODRM)
op(map2, 0xB6, "movzx", "GvEb", F_MODRM)
op(map2, 0xB7, "movzx", "GvEw", F_MODRM)
grp_op(map2, 0xBA, "g8", "EvIbU")
op(map2, 0xBB, "btc", "EvGv_bt", F_MODRM)
op(map2, 0xBC, "bsf", "GvEv", F_MODRM)
op(map2, 0xBD, "bsr", "GvEv", F_MODRM)
op(map2, 0xBE, "movsx", "GvEb", F_MODRM)
op(map2, 0xBF, "movsx", "GvEw", F_MODRM)
op(map2, 0xC0, "xadd", "EbGb", F_MODRM | F_BYTE)
op(map2, 0xC1, "xadd", "EvGv", F_MODRM)
for r in range(8):
    op(map2, 0xC8 + r, "bswap", "Zv")


def render() -> str:
    names, offs = [], {}
    def name_off(n):
        if n not in offs:
            offs[n] = sum(len(x) + 1 for x in names)
            names.append(n)
        return offs[n]
    name_off("(bad)")

    def entry(e):
        if e is None:
            return (0xFFFF, 0, 0)
        name, form, flags = e
        if flags & F_GROUP:
            return (name, form, flags)          # name = group number
        return (name_off(name), form, flags)

    def table(tab):
        return [entry(tab.get(i)) for i in range(256)]

    t1, t2 = table(map1), table(map2)
    tg = []
    for g in groups:
        for e in g:
            if e is None:
                tg.append((0xFFFF, 0, 0))
            else:
                n, form, flags = e
                tg.append((name_off(n), FM[form] if form else 0, flags))

    def rows(entries, label):
        # one 4-byte entry per line, with its index as a comment
        out = [label + ":"]
        for i, (n, f, fl) in enumerate(entries):
            out.append("    dw 0x%04x\n    db %2d, 0x%02x        ; %02x" % (n, f, fl, i))
        return out

    lines = [
        "; " + "=" * 76,
        "; GENERATED by scripts/gen_x86_tables.py - do not edit by hand.",
        "; x86-64 opcode tables for tools/disasm/x86.s. Entry: dw name offset",
        "; (or group number with F_GROUP; 0xFFFF = invalid), db form, db flags.",
        "; " + "=" * 76,
        "",
        "x86_names:",
    ]
    for i in range(0, len(names), 8):
        lines.append("    db " + ", ".join('"%s", 0' % n for n in names[i:i + 8]))
    lines.append("")
    lines += rows(t1, "x86_map1") + [""]
    lines += rows(t2, "x86_map2") + [""]
    lines += rows(tg, "x86_groups")
    return "\n".join(lines) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        cur = open(DST, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(DST) else ""
        if cur != text:
            sys.exit("tools/disasm/x86_tables.inc is out of date; run scripts/gen_x86_tables.py")
        return
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


if __name__ == "__main__":
    main()
