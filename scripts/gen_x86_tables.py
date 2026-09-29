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
Ewv G7 GAE
VW WV VWI VE EV GW GU UI VM MV V12 EVI VEI GUI VW0 CMPS PCLMUL ENDBR""".split()
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

    def sse_table(tab):
        out = []
        for i in range(1024):
            e = tab.get(i)
            if e is None:
                out.append((0xFFFF, 0, 0))
            else:
                n, f, fl = e
                out.append((n if isinstance(n, int) else name_off(n), f, fl))
        return out

    # Build every table first: that is what fills the name list, which is
    # written out ahead of the tables.
    t1, t2 = table(map1), table(map2)
    ts0f, ts38, ts3a = sse_table(sse_tabs["0f"]), sse_table(sse_tabs["38"]), sse_table(sse_tabs["3a"])
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
    lines += rows(ts0f, "x86_sse0f") + [""]
    lines += rows(ts38, "x86_sse38") + [""]
    lines += rows(ts3a, "x86_sse3a") + [""]
    lines += rows(tg, "x86_groups")
    return "\n".join(lines) + "\n"


# ============================================================================
# SSE family: 0F / 0F 38 / 0F 3A opcodes selected by a mandatory prefix
# ============================================================================
# Three tables of 256 x 4 entries (index = opcode * 4 + prefix, prefix
# 0 = none, 1 = 66, 2 = F3, 3 = F2). A valid entry here wins over the plain
# 0F table; the prefix is then part of the opcode, not an operand-size or
# rep prefix. Entry flags differ from the integer tables:
S_MEM_B, S_MEM_W, S_MEM_D, S_MEM_Q, S_MEM_X = 1, 2, 3, 4, 5   # bits 0-2: memory size
S_MMX = 8        # mm registers, QWORD memory (no-prefix MMX forms)
S_WQ = 16        # REX.W / VEX.W turns a trailing 'd' into 'q' (movd -> movq)
S_NDS = 32       # the VEX form has an extra source register (vvvv)
S_NOVEX = 64     # legacy only - no VEX form
MEM = {"b": S_MEM_B, "w": S_MEM_W, "d": S_MEM_D, "q": S_MEM_Q, "x": S_MEM_X, "": 0}
PFX = {"np": 0, "66": 1, "F3": 2, "F2": 3}
sse_tabs = {"0f": {}, "38": {}, "3a": {}}

def sse(tab, code, pfx, name, form, mem, flags=0):
    sse_tabs[tab][code * 4 + PFX[pfx]] = (name, FM[form], MEM[mem] | flags)

def sse_int(tab, code, pfx, name, form, flags=F_MODRM):
    """An integer instruction selected by a prefix (popcnt, movbe, ...)."""
    sse_tabs[tab][code * 4 + PFX[pfx]] = (name, FM[form], flags | 0x80)   # 0x80: integer flags

def sse_grp(tab, code, pfx, gname, flags):
    sse_tabs[tab][code * 4 + PFX[pfx]] = (group_ids[gname], FM["UI"], flags | 0x80 * 0)

# packed/scalar arithmetic: np=ps, 66=pd, F3=ss, F2=sd
def arith(code, base, nds=True):
    f = S_NDS if nds else 0
    sse("0f", code, "np", base + "ps", "VW", "x", f)
    sse("0f", code, "66", base + "pd", "VW", "x", f)
    sse("0f", code, "F3", base + "ss", "VW", "d", f)
    sse("0f", code, "F2", base + "sd", "VW", "q", f)

sse("0f", 0x10, "np", "movups", "VW", "x"); sse("0f", 0x10, "66", "movupd", "VW", "x")
sse("0f", 0x10, "F3", "movss", "VW", "d", S_NDS); sse("0f", 0x10, "F2", "movsd", "VW", "q", S_NDS)
sse("0f", 0x11, "np", "movups", "WV", "x"); sse("0f", 0x11, "66", "movupd", "WV", "x")
sse("0f", 0x11, "F3", "movss", "WV", "d"); sse("0f", 0x11, "F2", "movsd", "WV", "q")
sse("0f", 0x12, "np", "movlps", "V12", "q", S_NDS); sse("0f", 0x12, "66", "movlpd", "VM", "q", S_NDS)
sse("0f", 0x12, "F3", "movsldup", "VW", "x"); sse("0f", 0x12, "F2", "movddup", "VW", "q")
sse("0f", 0x13, "np", "movlps", "MV", "q"); sse("0f", 0x13, "66", "movlpd", "MV", "q")
sse("0f", 0x14, "np", "unpcklps", "VW", "x", S_NDS); sse("0f", 0x14, "66", "unpcklpd", "VW", "x", S_NDS)
sse("0f", 0x15, "np", "unpckhps", "VW", "x", S_NDS); sse("0f", 0x15, "66", "unpckhpd", "VW", "x", S_NDS)
sse("0f", 0x16, "np", "movhps", "V12", "q", S_NDS); sse("0f", 0x16, "66", "movhpd", "VM", "q", S_NDS)
sse("0f", 0x16, "F3", "movshdup", "VW", "x")
sse("0f", 0x17, "np", "movhps", "MV", "q"); sse("0f", 0x17, "66", "movhpd", "MV", "q")
sse("0f", 0x28, "np", "movaps", "VW", "x"); sse("0f", 0x28, "66", "movapd", "VW", "x")
sse("0f", 0x29, "np", "movaps", "WV", "x"); sse("0f", 0x29, "66", "movapd", "WV", "x")
sse("0f", 0x2A, "F3", "cvtsi2ss", "VE", "", S_NDS); sse("0f", 0x2A, "F2", "cvtsi2sd", "VE", "", S_NDS)
sse("0f", 0x2B, "np", "movntps", "MV", "x"); sse("0f", 0x2B, "66", "movntpd", "MV", "x")
sse("0f", 0x2C, "F3", "cvttss2si", "GW", "d"); sse("0f", 0x2C, "F2", "cvttsd2si", "GW", "q")
sse("0f", 0x2D, "F3", "cvtss2si", "GW", "d"); sse("0f", 0x2D, "F2", "cvtsd2si", "GW", "q")
sse("0f", 0x2E, "np", "ucomiss", "VW", "d"); sse("0f", 0x2E, "66", "ucomisd", "VW", "q")
sse("0f", 0x2F, "np", "comiss", "VW", "d"); sse("0f", 0x2F, "66", "comisd", "VW", "q")
sse("0f", 0x50, "np", "movmskps", "GU", ""); sse("0f", 0x50, "66", "movmskpd", "GU", "")
arith(0x51, "sqrt", nds=False)
sse("0f", 0x51, "F3", "sqrtss", "VW", "d", S_NDS); sse("0f", 0x51, "F2", "sqrtsd", "VW", "q", S_NDS)
sse("0f", 0x52, "np", "rsqrtps", "VW", "x"); sse("0f", 0x52, "F3", "rsqrtss", "VW", "d", S_NDS)
sse("0f", 0x53, "np", "rcpps", "VW", "x"); sse("0f", 0x53, "F3", "rcpss", "VW", "d", S_NDS)
for code, n in ((0x54, "and"), (0x55, "andn"), (0x56, "or"), (0x57, "xor")):
    sse("0f", code, "np", n + "ps", "VW", "x", S_NDS); sse("0f", code, "66", n + "pd", "VW", "x", S_NDS)
for code, n in ((0x58, "add"), (0x59, "mul"), (0x5C, "sub"), (0x5D, "min"), (0x5E, "div"), (0x5F, "max")):
    arith(code, n)
sse("0f", 0x5A, "np", "cvtps2pd", "VW", "q"); sse("0f", 0x5A, "66", "cvtpd2ps", "VW", "x")
sse("0f", 0x5A, "F3", "cvtss2sd", "VW", "d", S_NDS); sse("0f", 0x5A, "F2", "cvtsd2ss", "VW", "q", S_NDS)
sse("0f", 0x5B, "np", "cvtdq2ps", "VW", "x"); sse("0f", 0x5B, "66", "cvtps2dq", "VW", "x")
sse("0f", 0x5B, "F3", "cvttps2dq", "VW", "x")

def mmx_sse(code, name, tab="0f", nds=True, mmx=True):
    """Integer SIMD op: no prefix = MMX (mm, QWORD), 66 = SSE2 (xmm, XMMWORD)."""
    if mmx:
        sse(tab, code, "np", name, "VW", "q", S_MMX | S_NOVEX)
    sse(tab, code, "66", name, "VW", "x", S_NDS if nds else 0)

for i, n in enumerate("punpcklbw punpcklwd punpckldq packsswb pcmpgtb pcmpgtw pcmpgtd packuswb "
                      "punpckhbw punpckhwd punpckhdq packssdw".split()):
    mmx_sse(0x60 + i, n)
mmx_sse(0x6C, "punpcklqdq", mmx=False); mmx_sse(0x6D, "punpckhqdq", mmx=False)
sse("0f", 0x6E, "np", "movd", "VE", "", S_MMX | S_WQ | S_NOVEX); sse("0f", 0x6E, "66", "movd", "VE", "", S_WQ)
sse("0f", 0x6F, "np", "movq", "VW", "q", S_MMX | S_NOVEX)
sse("0f", 0x6F, "66", "movdqa", "VW", "x"); sse("0f", 0x6F, "F3", "movdqu", "VW", "x")
sse("0f", 0x70, "np", "pshufw", "VWI", "q", S_MMX | S_NOVEX); sse("0f", 0x70, "66", "pshufd", "VWI", "x")
sse("0f", 0x70, "F3", "pshufhw", "VWI", "x"); sse("0f", 0x70, "F2", "pshuflw", "VWI", "x")
group("s71", [None, None, ("psrlw", None, 0), None, ("psraw", None, 0), None, ("psllw", None, 0), None])
group("s72", [None, None, ("psrld", None, 0), None, ("psrad", None, 0), None, ("pslld", None, 0), None])
group("s73m", [None, None, ("psrlq", None, 0), None, None, None, ("psllq", None, 0), None])
group("s73x", [None, None, ("psrlq", None, 0), ("psrldq", None, 0), None, None, ("psllq", None, 0), ("pslldq", None, 0)])
for code, g in ((0x71, "s71"), (0x72, "s72")):
    sse_grp("0f", code, "np", g, S_MMX | S_NOVEX); sse_grp("0f", code, "66", g, S_NDS)
sse_grp("0f", 0x73, "np", "s73m", S_MMX | S_NOVEX); sse_grp("0f", 0x73, "66", "s73x", S_NDS)
mmx_sse(0x74, "pcmpeqb"); mmx_sse(0x75, "pcmpeqw"); mmx_sse(0x76, "pcmpeqd")
sse("0f", 0x77, "np", "emms", "NONE", "")
sse("0f", 0x7C, "66", "haddpd", "VW", "x", S_NDS); sse("0f", 0x7C, "F2", "haddps", "VW", "x", S_NDS)
sse("0f", 0x7D, "66", "hsubpd", "VW", "x", S_NDS); sse("0f", 0x7D, "F2", "hsubps", "VW", "x", S_NDS)
sse("0f", 0x7E, "np", "movd", "EV", "", S_MMX | S_WQ | S_NOVEX); sse("0f", 0x7E, "66", "movd", "EV", "", S_WQ)
sse("0f", 0x7E, "F3", "movq", "VW", "q")
sse("0f", 0x7F, "np", "movq", "WV", "q", S_MMX | S_NOVEX)
sse("0f", 0x7F, "66", "movdqa", "WV", "x"); sse("0f", 0x7F, "F3", "movdqu", "WV", "x")
for p, suf, m in (("np", "ps", "x"), ("66", "pd", "x"), ("F3", "ss", "d"), ("F2", "sd", "q")):
    sse("0f", 0xC2, p, "cmp" + suf, "CMPS", m, S_NDS)
sse_int("0f", 0xC3, "np", "movnti", "EvGv")
sse("0f", 0xC4, "np", "pinsrw", "VEI", "w", S_MMX | S_NOVEX); sse("0f", 0xC4, "66", "pinsrw", "VEI", "w", S_NDS)
sse("0f", 0xC5, "np", "pextrw", "GUI", "", S_MMX | S_NOVEX); sse("0f", 0xC5, "66", "pextrw", "GUI", "")
sse("0f", 0xC6, "np", "shufps", "VWI", "x", S_NDS); sse("0f", 0xC6, "66", "shufpd", "VWI", "x", S_NDS)
sse("0f", 0xD0, "66", "addsubpd", "VW", "x", S_NDS); sse("0f", 0xD0, "F2", "addsubps", "VW", "x", S_NDS)
for code, n in ((0xD1, "psrlw"), (0xD2, "psrld"), (0xD3, "psrlq"), (0xD4, "paddq"), (0xD5, "pmullw"),
                (0xD8, "psubusb"), (0xD9, "psubusw"), (0xDA, "pminub"), (0xDB, "pand"), (0xDC, "paddusb"),
                (0xDD, "paddusw"), (0xDE, "pmaxub"), (0xDF, "pandn"), (0xE0, "pavgb"), (0xE1, "psraw"),
                (0xE2, "psrad"), (0xE3, "pavgw"), (0xE4, "pmulhuw"), (0xE5, "pmulhw"), (0xE8, "psubsb"),
                (0xE9, "psubsw"), (0xEA, "pminsw"), (0xEB, "por"), (0xEC, "paddsb"), (0xED, "paddsw"),
                (0xEE, "pmaxsw"), (0xEF, "pxor"), (0xF1, "psllw"), (0xF2, "pslld"), (0xF3, "psllq"),
                (0xF4, "pmuludq"), (0xF5, "pmaddwd"), (0xF6, "psadbw"), (0xF8, "psubb"), (0xF9, "psubw"),
                (0xFA, "psubd"), (0xFB, "psubq"), (0xFC, "paddb"), (0xFD, "paddw"), (0xFE, "paddd")):
    mmx_sse(code, n)
sse("0f", 0xD6, "66", "movq", "WV", "q")
sse("0f", 0xD7, "np", "pmovmskb", "GU", "", S_MMX | S_NOVEX); sse("0f", 0xD7, "66", "pmovmskb", "GU", "")
sse("0f", 0xE6, "66", "cvttpd2dq", "VW", "x"); sse("0f", 0xE6, "F3", "cvtdq2pd", "VW", "q")
sse("0f", 0xE6, "F2", "cvtpd2dq", "VW", "x")
sse("0f", 0xE7, "np", "movntq", "MV", "q", S_MMX | S_NOVEX); sse("0f", 0xE7, "66", "movntdq", "MV", "x")
sse("0f", 0xF0, "F2", "lddqu", "VM", "")
sse("0f", 0xF7, "66", "maskmovdqu", "VW", "x")
sse("0f", 0x1E, "F3", "endbr64", "ENDBR", "", S_NOVEX)
sse_int("0f", 0xB8, "F3", "popcnt", "GvEv")
sse_int("0f", 0xBC, "F3", "tzcnt", "GvEv")
sse_int("0f", 0xBD, "F3", "lzcnt", "GvEv")

# ---- 0F 38 ----
for i, n in enumerate("pshufb phaddw phaddd phaddsw pmaddubsw phsubw phsubd phsubsw "
                      "psignb psignw psignd pmulhrsw".split()):
    mmx_sse(i, n, tab="38")
for code, n in ((0x1C, "pabsb"), (0x1D, "pabsw"), (0x1E, "pabsd")):
    mmx_sse(code, n, tab="38", nds=False)
sse("38", 0x10, "66", "pblendvb", "VW0", "x"); sse("38", 0x14, "66", "blendvps", "VW0", "x")
sse("38", 0x15, "66", "blendvpd", "VW0", "x"); sse("38", 0x17, "66", "ptest", "VW", "x")
for code, n, m in ((0x20, "pmovsxbw", "q"), (0x21, "pmovsxbd", "d"), (0x22, "pmovsxbq", "w"),
                   (0x23, "pmovsxwd", "q"), (0x24, "pmovsxwq", "d"), (0x25, "pmovsxdq", "q"),
                   (0x30, "pmovzxbw", "q"), (0x31, "pmovzxbd", "d"), (0x32, "pmovzxbq", "w"),
                   (0x33, "pmovzxwd", "q"), (0x34, "pmovzxwq", "d"), (0x35, "pmovzxdq", "q")):
    sse("38", code, "66", n, "VW", m)
for code, n in ((0x28, "pmuldq"), (0x29, "pcmpeqq"), (0x2B, "packusdw"), (0x37, "pcmpgtq"),
                (0x38, "pminsb"), (0x39, "pminsd"), (0x3A, "pminuw"), (0x3B, "pminud"),
                (0x3C, "pmaxsb"), (0x3D, "pmaxsd"), (0x3E, "pmaxuw"), (0x3F, "pmaxud"),
                (0x40, "pmulld"), (0xDC, "aesenc"), (0xDD, "aesenclast"), (0xDE, "aesdec"),
                (0xDF, "aesdeclast")):
    sse("38", code, "66", n, "VW", "x", S_NDS)
sse("38", 0x2A, "66", "movntdqa", "VM", "x")
sse("38", 0x41, "66", "phminposuw", "VW", "x"); sse("38", 0xDB, "66", "aesimc", "VW", "x")
sse_int("38", 0xF0, "np", "movbe", "GvEv"); sse_int("38", 0xF1, "np", "movbe", "EvGv")
sse_int("38", 0xF0, "F2", "crc32", "GvEb"); sse_int("38", 0xF1, "F2", "crc32", "GvEv")

# ---- 0F 3A ----
for code, n, m, nds in ((0x08, "roundps", "x", 0), (0x09, "roundpd", "x", 0), (0x0A, "roundss", "d", S_NDS),
                        (0x0B, "roundsd", "q", S_NDS), (0x0C, "blendps", "x", S_NDS), (0x0D, "blendpd", "x", S_NDS),
                        (0x0E, "pblendw", "x", S_NDS), (0x0F, "palignr", "x", S_NDS), (0x21, "insertps", "d", S_NDS),
                        (0x40, "dpps", "x", S_NDS), (0x41, "dppd", "x", S_NDS), (0x42, "mpsadbw", "x", S_NDS),
                        (0x60, "pcmpestrm", "x", 0), (0x61, "pcmpestri", "x", 0), (0x62, "pcmpistrm", "x", 0),
                        (0x63, "pcmpistri", "x", 0), (0xDF, "aeskeygenassist", "x", 0)):
    sse("3a", code, "66", n, "VWI", m, nds)
sse("3a", 0x0F, "np", "palignr", "VWI", "q", S_MMX | S_NOVEX)
sse("3a", 0x14, "66", "pextrb", "EVI", "b"); sse("3a", 0x15, "66", "pextrw", "EVI", "w")
sse("3a", 0x16, "66", "pextrd", "EVI", "d", S_WQ); sse("3a", 0x17, "66", "extractps", "EVI", "d")
sse("3a", 0x20, "66", "pinsrb", "VEI", "b", S_NDS); sse("3a", 0x22, "66", "pinsrd", "VEI", "d", S_NDS | S_WQ)
sse("3a", 0x44, "66", "pclmulqdq", "PCLMUL", "x", S_NDS)

# ---- integer extras in the 0F map ----
group("g16", [("prefetchnta", "Eb", 0), ("prefetcht0", "Eb", 0), ("prefetcht1", "Eb", 0), ("prefetcht2", "Eb", 0),
              None, None, None, None])
grp_op(map2, 0x18, "g16", "Eb", F_BYTE)


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
