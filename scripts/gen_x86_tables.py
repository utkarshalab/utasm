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
  x86_sse*    SSE family by opcode and mandatory prefix; x86_vex* VEX-only
  x87_*       x87 floating point (D8-DF)
  x86_evex    EVEX (AVX-512), a sparse list; x86_kops the k-mask instructions

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
VW WV VWI VE EV GW GU UI VM MV V12 EVI VEI GUI VW0 CMPS PCLMUL ENDBR
XBCAST XINS XEXT XIS4 BGBE BGEB BBE XMLD XMST BRORX XZERO
X87 EVEX G9""".split()
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
# 0F C7: cmpxchg8b/16b (memory), rdrand/rdseed (register); x86.s decodes it (form G9)
op(map2, 0xC7, "(0fc7)", "G9", F_MODRM)
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
    tv0f, tv38, tv3a = sse_table(vex_tabs["0f"]), sse_table(vex_tabs["38"]), sse_table(vex_tabs["3a"])
    tg = []
    for g in groups:
        for e in g:
            if e is None:
                tg.append((0xFFFF, 0, 0))
            else:
                n, form, flags = e
                tg.append((name_off(n), FM[form] if form else 0, flags))

    tev = evex_rows(name_off)       # registers the EVEX names too

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
    lines += rows(tv0f, "x86_vex0f") + [""]
    lines += rows(tv38, "x86_vex38") + [""]
    lines += rows(tv3a, "x86_vex3a") + [""]
    lines += rows(tg, "x86_groups") + [""]
    lines += x87_tables() + [""]
    lines += tev + [""]
    lines += kop_rows()
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
sse("38", 0x10, "66", "pblendvb", "VW0", "x", S_NOVEX); sse("38", 0x14, "66", "blendvps", "VW0", "x", S_NOVEX)
sse("38", 0x15, "66", "blendvpd", "VW0", "x", S_NOVEX); sse("38", 0x17, "66", "ptest", "VW", "x")
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
sse_int("38", 0xF6, "66", "adcx", "GvEv"); sse_int("38", 0xF6, "F3", "adox", "GvEv")
# SHA extensions (legacy encoding only)
for code, n in ((0xC8, "sha1nexte"), (0xC9, "sha1msg1"), (0xCA, "sha1msg2"),
                (0xCC, "sha256msg1"), (0xCD, "sha256msg2")):
    sse("38", code, "np", n, "VW", "x", S_NOVEX)
sse("38", 0xCB, "np", "sha256rnds2", "VW0", "x", S_NOVEX)
sse("3a", 0xCC, "np", "sha1rnds4", "VWI", "x", S_NOVEX)

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
# GFNI (the VEX forms of the affine ones take VEX.W1)
sse("3a", 0xCE, "66", "gf2p8affineqb", "VWI", "x", S_NDS)
sse("3a", 0xCF, "66", "gf2p8affineinvqb", "VWI", "x", S_NDS)
sse("38", 0xCF, "66", "gf2p8mulb", "VW", "x", S_NDS)

# ============================================================================
# VEX-only instructions (AVX/AVX2/FMA/BMI without a legacy SSE form)
# ============================================================================
# Same layout as the SSE tables (opcode * 4 + VEX.pp) and the same flag bits,
# except bit 3, which here means "VEX.W turns the last 's' into 'd'"
# (vfmadd132ps -> vfmadd132pd). A VEX instruction is looked up here first,
# then in the SSE tables (with a "v" prefix added to the name).
V_WSD = 8
vex_tabs = {"0f": {}, "38": {}, "3a": {}}

def vex(tab, code, pfx, name, form, mem, flags=0):
    vex_tabs[tab][code * 4 + PFX[pfx]] = (name, FM[form], MEM[mem] | flags)

def vex_grp(tab, code, pfx, gname, form):
    vex_tabs[tab][code * 4 + PFX[pfx]] = (group_ids[gname], FM[form], 0)

vex("0f", 0x77, "np", "vzeroupper", "XZERO", "")
for code, n, form, m, f in (
        (0x0C, "vpermilps", "VW", "x", S_NDS), (0x0D, "vpermilpd", "VW", "x", S_NDS),
        (0x0E, "vtestps", "VW", "x", 0), (0x0F, "vtestpd", "VW", "x", 0),
        (0x16, "vpermps", "VW", "x", S_NDS), (0x36, "vpermd", "VW", "x", S_NDS),
        (0x18, "vbroadcastss", "XBCAST", "d", 0), (0x19, "vbroadcastsd", "XBCAST", "q", 0),
        (0x1A, "vbroadcastf128", "XBCAST", "x", 0), (0x5A, "vbroadcasti128", "XBCAST", "x", 0),
        (0x58, "vpbroadcastd", "XBCAST", "d", 0), (0x59, "vpbroadcastq", "XBCAST", "q", 0),
        (0x78, "vpbroadcastb", "XBCAST", "b", 0), (0x79, "vpbroadcastw", "XBCAST", "w", 0),
        (0x2C, "vmaskmovps", "XMLD", "x", 0), (0x2D, "vmaskmovpd", "XMLD", "x", 0),
        (0x2E, "vmaskmovps", "XMST", "x", 0), (0x2F, "vmaskmovpd", "XMST", "x", 0),
        (0x8C, "vpmaskmovd", "XMLD", "x", S_WQ), (0x8E, "vpmaskmovd", "XMST", "x", S_WQ),
        (0x45, "vpsrlvd", "VW", "x", S_NDS | S_WQ), (0x46, "vpsravd", "VW", "x", S_NDS),
        (0x47, "vpsllvd", "VW", "x", S_NDS | S_WQ)):
    vex("38", code, "66", n, form, m, f)
# FMA: 132 / 213 / 231 forms; VEX.W picks ps/pd (ss/sd)
for base, fop in (("vfmaddsub", 0x96), ("vfmsubadd", 0x97), ("vfmadd", 0x98), ("vfmsub", 0x9A),
                 ("vfnmadd", 0x9C), ("vfnmsub", 0x9E)):
    for k, order in ((0, "132"), (0x10, "213"), (0x20, "231")):
        vex("38", fop + k, "66", base + order + "ps", "VW", "x", S_NDS | V_WSD)
        if base not in ("vfmaddsub", "vfmsubadd"):
            vex("38", fop + k + 1, "66", base + order + "ss", "VW", "d", S_NDS | V_WSD)
# BMI1 / BMI2 (general registers, size by VEX.W)
group("vbmi", [None, ("blsr", None, 0), ("blsmsk", None, 0), ("blsi", None, 0), None, None, None, None])
vex("38", 0xF2, "np", "andn", "BGBE", "")
vex_grp("38", 0xF3, "np", "vbmi", "BBE")
vex("38", 0xF5, "np", "bzhi", "BGEB", ""); vex("38", 0xF5, "F3", "pext", "BGBE", "")
vex("38", 0xF5, "F2", "pdep", "BGBE", ""); vex("38", 0xF6, "F2", "mulx", "BGBE", "")
vex("38", 0xF7, "np", "bextr", "BGEB", ""); vex("38", 0xF7, "66", "shlx", "BGEB", "")
vex("38", 0xF7, "F3", "sarx", "BGEB", ""); vex("38", 0xF7, "F2", "shrx", "BGEB", "")
vex("3a", 0xF0, "F2", "rorx", "BRORX", "")
for code, n, form, m, f in (
        (0x00, "vpermq", "VWI", "x", 0), (0x01, "vpermpd", "VWI", "x", 0),
        (0x02, "vpblendd", "VWI", "x", S_NDS), (0x04, "vpermilps", "VWI", "x", 0),
        (0x05, "vpermilpd", "VWI", "x", 0), (0x06, "vperm2f128", "VWI", "x", S_NDS),
        (0x46, "vperm2i128", "VWI", "x", S_NDS),
        (0x18, "vinsertf128", "XINS", "x", 0), (0x38, "vinserti128", "XINS", "x", 0),
        (0x19, "vextractf128", "XEXT", "x", 0), (0x39, "vextracti128", "XEXT", "x", 0),
        (0x4A, "vblendvps", "XIS4", "x", 0), (0x4B, "vblendvpd", "XIS4", "x", 0),
        (0x4C, "vpblendvb", "XIS4", "x", 0)):
    vex("3a", code, "66", n, form, m, f)

# ============================================================================
# x87 floating point (D8-DF)
# ============================================================================
# x86.s decodes these itself (form X87) from three tables written below:
#   x87_mem   64 x 16 bytes: memory form by (opcode - D8) * 8 + ModRM.reg:
#             name (NUL-padded to 15) + size code (0 none, 2 WORD, 4 DWORD,
#             8 QWORD, 10 TBYTE; 0xFF = invalid)
#   x87_reg   64 x 16 bytes: register form by the same index: name + operand
#             shape (0 = see x87_fix, 1 "st,st(i)", 2 "st(i),st", 3 "st(i)")
#   x87_fix   fixed register encodings, 16 bytes each: opcode, ModRM byte,
#             name (NUL-padded to 13), operand (0 none, 1 "ax"); ends with 0
for code in range(0xD8, 0xE0):
    op(map1, code, "(x87)", "X87", F_MODRM)
op(map1, 0x9B, "fwait", "NONE")

X87_MEM = {
    0xD8: [(n, 4) for n in "fadd fmul fcom fcomp fsub fsubr fdiv fdivr".split()],
    0xD9: [("fld", 4), None, ("fst", 4), ("fstp", 4), ("fldenv", 0), ("fldcw", 2), ("fnstenv", 0), ("fnstcw", 2)],
    0xDA: [(n, 4) for n in "fiadd fimul ficom ficomp fisub fisubr fidiv fidivr".split()],
    0xDB: [("fild", 4), ("fisttp", 4), ("fist", 4), ("fistp", 4), None, ("fld", 10), None, ("fstp", 10)],
    0xDC: [(n, 8) for n in "fadd fmul fcom fcomp fsub fsubr fdiv fdivr".split()],
    0xDD: [("fld", 8), ("fisttp", 8), ("fst", 8), ("fstp", 8), ("frstor", 0), None, ("fnsave", 0), ("fnstsw", 2)],
    0xDE: [(n, 2) for n in "fiadd fimul ficom ficomp fisub fisubr fidiv fidivr".split()],
    0xDF: [("fild", 2), ("fisttp", 2), ("fist", 2), ("fistp", 2), ("fbld", 10), ("fild", 8), ("fbstp", 10), ("fistp", 8)],
}
X87_REG = {
    0xD8: [("fadd", 1), ("fmul", 1), ("fcom", 3), ("fcomp", 3), ("fsub", 1), ("fsubr", 1), ("fdiv", 1), ("fdivr", 1)],
    0xD9: [("fld", 3), ("fxch", 3), None, ("fstp1", 3), None, None, None, None],
    0xDA: [("fcmovb", 1), ("fcmove", 1), ("fcmovbe", 1), ("fcmovu", 1), None, None, None, None],
    0xDB: [("fcmovnb", 1), ("fcmovne", 1), ("fcmovnbe", 1), ("fcmovnu", 1), None, ("fucomi", 1), ("fcomi", 1), None],
    0xDC: [("fadd", 2), ("fmul", 2), ("fcom2", 3), ("fcomp3", 3), ("fsubr", 2), ("fsub", 2), ("fdivr", 2), ("fdiv", 2)],
    0xDD: [("ffree", 3), ("fxch4", 3), ("fst", 3), ("fstp", 3), ("fucom", 3), ("fucomp", 3), None, None],
    0xDE: [("faddp", 2), ("fmulp", 2), ("fcomp5", 3), None, ("fsubrp", 2), ("fsubp", 2), ("fdivrp", 2), ("fdivp", 2)],
    0xDF: [("ffreep", 3), ("fxch7", 3), ("fstp8", 3), ("fstp9", 3), None, ("fucomip", 1), ("fcomip", 1), None],
}
X87_FIX = [(0xD9, 0xD0, "fnop", 0)] + [(0xD9, 0xE0 + i, n, 0) for i, n in enumerate(
    "fchs fabs - - ftst fxam - - fld1 fldl2t fldl2e fldpi fldlg2 fldln2 fldz - "
    "f2xm1 fyl2x fptan fpatan fxtract fprem1 fdecstp fincstp fprem fyl2xp1 fsqrt fsincos "
    "frndint fscale fsin fcos".split()) if n != "-"] + [
    (0xDA, 0xE9, "fucompp", 0), (0xDB, 0xE2, "fnclex", 0), (0xDB, 0xE3, "fninit", 0),
    (0xDE, 0xD9, "fcompp", 0), (0xDF, 0xE0, "fnstsw", 1)]

def x87_tables():
    out = ["x87_mem:"]
    for code in range(0xD8, 0xE0):
        for e in X87_MEM[code]:
            n, size = e if e else ("(bad)", 0xFF)
            out.append('    db "%s"%s, %d' % (n, ", 0" * (15 - len(n)), size))
    out.append("x87_reg:")
    for code in range(0xD8, 0xE0):
        for e in X87_REG[code]:
            n, shape = e if e else ("", 0)
            out.append('    db %s%s, %d' % (('"%s", ' % n) if n else "", ", ".join(["0"] * (15 - len(n))), shape))
    out.append("x87_fix:")
    for code, modrm, n, opnd in X87_FIX:
        out.append('    db 0x%02X, 0x%02X, "%s"%s, %d' % (code, modrm, n, ", 0" * (13 - len(n)), opnd))
    out.append("    db 0")
    return out

# ---- integer extras in the 0F map ----
group("g16", [("prefetchnta", "Eb", 0), ("prefetcht0", "Eb", 0), ("prefetcht1", "Eb", 0), ("prefetcht2", "Eb", 0),
              None, None, None, None])
grp_op(map2, 0x18, "g16", "Eb", F_BYTE)


# ============================================================================
# EVEX (AVX-512)
# ============================================================================
# x86_evex is a sparse list of 16-byte entries, ending with a zero key:
#   dd key     map << 24 | opcode << 16 | pp << 8 | W << 4 | g
#              (map 2 = 0F, 3 = 0F 38, 4 = 0F 3A; pp 0 none, 1 66, 2 F3,
#              3 F2; g = 8 + ModRM.reg for a group member, else 0)
#   dw name    offset in x86_names
#   db msize   memory operand size (EV_MSIZE), which is also the disp8*N
#              scale unless the operand is a broadcast
#   db flags   EV_* below
#   db shape   operands, one letter each, NUL-padded to 8 bytes:
#              V vector register from ModRM.reg     H vector register from vvvv
#              W vector register or memory (ModRM.rm)
#              Y like V, at half the vector length (vcvtpd2ps ymm, zmm)
#              E general register (32/64 by W) or memory
#              G general register from ModRM.reg (32/64 by W)
#              K mask register from ModRM.reg       k mask register from ModRM.rm
#              I imm8
# The {k}{z} mask is printed after the first operand. W as a register takes
# the width of its memory size (xmm for scalars and 128-bit parts).
EV_MSIZE = {"v": 0, "b": 1, "w": 2, "d": 3, "q": 4, "h": 5, "qv": 6, "o": 7, "x": 8, "y": 9}
EV_BCST = 1      # EVEX.b with memory: broadcast one element (4 bytes, 8 with W)
EV_SCALAR = 2    # V and H are xmm whatever the vector length
EV_ER = 4        # EVEX.b with registers: rounding control {rn-sae} ...
EV_SAE = 8       # EVEX.b with registers: {sae}
EV_PINT = 16     # vpcmp: the predicate immediate becomes part of the name
EV_PFP = 32      # vcmp: likewise, with the 32 floating-point predicates
EV_NELEM = 64    # disp8*N scales by one element (compress / expand)
EV_MOVS = 128    # vmovss/vmovsd: H only in the register form
EV_MAP = {"0f": 2, "38": 3, "3a": 4}
evex_tab = {}

def ev(m, code, pfx, w, name, shape, msize="v", flags=0, reg=None):
    """One EVEX instruction; w = 0, 1 or "ig" (both)."""
    for wv in ((0, 1) if w == "ig" else (w,)):
        key = (EV_MAP[m] << 24) | (code << 16) | (PFX[pfx] << 8) | (wv << 4) | (0 if reg is None else 8 + reg)
        assert key not in evex_tab, (m, hex(code), pfx, wv, name)
        evex_tab[key] = (name, EV_MSIZE[msize], flags, shape)

def ev2(m, code, pfx, n0, n1, shape, msize="v", flags=0, reg=None):
    """W0 and W1 name two instructions (vmovdqa32 / vmovdqa64, vpandd / vpandq)."""
    ev(m, code, pfx, 0, n0, shape, msize, flags, reg)
    ev(m, code, pfx, 1, n1, shape, msize, flags, reg)

B = EV_BCST
# ---- 0F: floating point ----
for code, n, er in ((0x58, "add", EV_ER), (0x59, "mul", EV_ER), (0x5C, "sub", EV_ER),
                    (0x5D, "min", EV_SAE), (0x5E, "div", EV_ER), (0x5F, "max", EV_SAE)):
    ev("0f", code, "np", 0, "v%sps" % n, "VHW", "v", B | er)
    ev("0f", code, "66", 1, "v%spd" % n, "VHW", "v", B | er)
    ev("0f", code, "F3", 0, "v%sss" % n, "VHW", "d", EV_SCALAR | er)
    ev("0f", code, "F2", 1, "v%ssd" % n, "VHW", "q", EV_SCALAR | er)
ev("0f", 0x51, "np", 0, "vsqrtps", "VW", "v", B | EV_ER)
ev("0f", 0x51, "66", 1, "vsqrtpd", "VW", "v", B | EV_ER)
ev("0f", 0x51, "F3", 0, "vsqrtss", "VHW", "d", EV_SCALAR | EV_ER)
ev("0f", 0x51, "F2", 1, "vsqrtsd", "VHW", "q", EV_SCALAR | EV_ER)
for code, n in ((0x54, "and"), (0x55, "andn"), (0x56, "or"), (0x57, "xor"),
                (0x14, "unpckl"), (0x15, "unpckh")):
    ev("0f", code, "np", 0, "v%sps" % n, "VHW", "v", B)
    ev("0f", code, "66", 1, "v%spd" % n, "VHW", "v", B)
ev("0f", 0xC6, "np", 0, "vshufps", "VHWI", "v", B)
ev("0f", 0xC6, "66", 1, "vshufpd", "VHWI", "v", B)
for code, n in ((0x10, "vmovu"), (0x28, "vmova")):
    ev("0f", code, "np", 0, n + "ps", "VW")
    ev("0f", code + 1, "np", 0, n + "ps", "WV")
    ev("0f", code, "66", 1, n + "pd", "VW")
    ev("0f", code + 1, "66", 1, n + "pd", "WV")
ev("0f", 0x10, "F3", 0, "vmovss", "VHW", "d", EV_SCALAR | EV_MOVS)
ev("0f", 0x11, "F3", 0, "vmovss", "WHV", "d", EV_SCALAR | EV_MOVS)
ev("0f", 0x10, "F2", 1, "vmovsd", "VHW", "q", EV_SCALAR | EV_MOVS)
ev("0f", 0x11, "F2", 1, "vmovsd", "WHV", "q", EV_SCALAR | EV_MOVS)
ev("0f", 0x12, "F3", 0, "vmovsldup", "VW")
ev("0f", 0x16, "F3", 0, "vmovshdup", "VW")
ev("0f", 0x2B, "np", 0, "vmovntps", "WV")
ev("0f", 0x2B, "66", 1, "vmovntpd", "WV")
for code, n in ((0x2E, "vucomis"), (0x2F, "vcomis")):
    ev("0f", code, "np", 0, n + "s", "VW", "d", EV_SCALAR | EV_SAE)
    ev("0f", code, "66", 1, n + "d", "VW", "q", EV_SCALAR | EV_SAE)
ev("0f", 0x5A, "np", 0, "vcvtps2pd", "VW", "h", B | EV_SAE)
ev("0f", 0x5A, "66", 1, "vcvtpd2ps", "YW", "v", B | EV_ER)
ev("0f", 0x5A, "F3", 0, "vcvtss2sd", "VHW", "d", EV_SCALAR | EV_SAE)
ev("0f", 0x5A, "F2", 1, "vcvtsd2ss", "VHW", "q", EV_SCALAR | EV_ER)
ev("0f", 0x5B, "np", 0, "vcvtdq2ps", "VW", "v", B | EV_ER)
ev("0f", 0x5B, "np", 1, "vcvtqq2ps", "YW", "v", B | EV_ER)
ev("0f", 0x5B, "66", 0, "vcvtps2dq", "VW", "v", B | EV_ER)
ev("0f", 0x5B, "F3", 0, "vcvttps2dq", "VW", "v", B | EV_SAE)
ev("0f", 0xE6, "F3", 0, "vcvtdq2pd", "VW", "h", B)
ev("0f", 0xE6, "F3", 1, "vcvtqq2pd", "VW", "v", B | EV_ER)
ev("0f", 0xE6, "66", 1, "vcvttpd2dq", "YW", "v", B | EV_SAE)
ev("0f", 0xE6, "F2", 1, "vcvtpd2dq", "YW", "v", B | EV_ER)
ev("0f", 0x2A, "F3", 0, "vcvtsi2ss", "VHE", "d", EV_SCALAR | EV_ER)
ev("0f", 0x2A, "F3", 1, "vcvtsi2ss", "VHE", "q", EV_SCALAR | EV_ER)
ev("0f", 0x2A, "F2", 0, "vcvtsi2sd", "VHE", "d", EV_SCALAR)
ev("0f", 0x2A, "F2", 1, "vcvtsi2sd", "VHE", "q", EV_SCALAR | EV_ER)
for code, n, r in ((0x2C, "vcvtt", EV_SAE), (0x2D, "vcvt", EV_ER)):
    ev("0f", code, "F3", "ig", n + "ss2si", "GW", "d", EV_SCALAR | r)
    ev("0f", code, "F2", "ig", n + "sd2si", "GW", "q", EV_SCALAR | r)
ev("0f", 0xC2, "np", 0, "vcmpps", "KHWI", "v", B | EV_SAE | EV_PFP)
ev("0f", 0xC2, "66", 1, "vcmppd", "KHWI", "v", B | EV_SAE | EV_PFP)
ev("0f", 0xC2, "F3", 0, "vcmpss", "KHWI", "d", EV_SCALAR | EV_SAE | EV_PFP)
ev("0f", 0xC2, "F2", 1, "vcmpsd", "KHWI", "q", EV_SCALAR | EV_SAE | EV_PFP)

# ---- 66 0F: integer ----
for code, n in ((0x60, "vpunpcklbw"), (0x61, "vpunpcklwd"), (0x63, "vpacksswb"), (0x67, "vpackuswb"),
                (0x68, "vpunpckhbw"), (0x69, "vpunpckhwd"), (0xD5, "vpmullw"), (0xD8, "vpsubusb"),
                (0xD9, "vpsubusw"), (0xDA, "vpminub"), (0xDC, "vpaddusb"), (0xDD, "vpaddusw"),
                (0xDE, "vpmaxub"), (0xE0, "vpavgb"), (0xE3, "vpavgw"), (0xE4, "vpmulhuw"),
                (0xE5, "vpmulhw"), (0xE8, "vpsubsb"), (0xE9, "vpsubsw"), (0xEA, "vpminsw"),
                (0xEC, "vpaddsb"), (0xED, "vpaddsw"), (0xEE, "vpmaxsw"), (0xF5, "vpmaddwd"),
                (0xF6, "vpsadbw"), (0xF8, "vpsubb"), (0xF9, "vpsubw"), (0xFC, "vpaddb"), (0xFD, "vpaddw")):
    ev("0f", code, "66", "ig", n, "VHW")
for code, n in ((0x64, "vpcmpgtb"), (0x65, "vpcmpgtw"), (0x74, "vpcmpeqb"), (0x75, "vpcmpeqw")):
    ev("0f", code, "66", "ig", n, "KHW")
for code, n in ((0x62, "vpunpckldq"), (0x6A, "vpunpckhdq"), (0x6B, "vpackssdw"), (0xFA, "vpsubd"), (0xFE, "vpaddd")):
    ev("0f", code, "66", 0, n, "VHW", "v", B)
for code, n in ((0x6C, "vpunpcklqdq"), (0x6D, "vpunpckhqdq"), (0xD4, "vpaddq"), (0xF4, "vpmuludq"), (0xFB, "vpsubq")):
    ev("0f", code, "66", 1, n, "VHW", "v", B)
ev("0f", 0x66, "66", 0, "vpcmpgtd", "KHW", "v", B)
ev("0f", 0x76, "66", 0, "vpcmpeqd", "KHW", "v", B)
for code, n in ((0xDB, "vpand"), (0xDF, "vpandn"), (0xEB, "vpor"), (0xEF, "vpxor")):
    ev2("0f", code, "66", n + "d", n + "q", "VHW", "v", B)
# shifts by a count in xmm/m128
for code, n in ((0xD1, "vpsrlw"), (0xE1, "vpsraw"), (0xF1, "vpsllw")):
    ev("0f", code, "66", "ig", n, "VHW", "x")
ev("0f", 0xD2, "66", 0, "vpsrld", "VHW", "x")
ev("0f", 0xF2, "66", 0, "vpslld", "VHW", "x")
ev2("0f", 0xE2, "66", "vpsrad", "vpsraq", "VHW", "x")
ev("0f", 0xD3, "66", 1, "vpsrlq", "VHW", "x")
ev("0f", 0xF3, "66", 1, "vpsllq", "VHW", "x")
# shifts by an immediate: groups 71 / 72 / 73, destination in vvvv
for r, n in ((2, "vpsrlw"), (4, "vpsraw"), (6, "vpsllw")):
    ev("0f", 0x71, "66", "ig", n, "HWI", reg=r)
ev2("0f", 0x72, "66", "vprord", "vprorq", "HWI", "v", B, reg=0)
ev2("0f", 0x72, "66", "vprold", "vprolq", "HWI", "v", B, reg=1)
ev("0f", 0x72, "66", 0, "vpsrld", "HWI", "v", B, reg=2)
ev2("0f", 0x72, "66", "vpsrad", "vpsraq", "HWI", "v", B, reg=4)
ev("0f", 0x72, "66", 0, "vpslld", "HWI", "v", B, reg=6)
ev("0f", 0x73, "66", 1, "vpsrlq", "HWI", "v", B, reg=2)
ev("0f", 0x73, "66", "ig", "vpsrldq", "HWI", reg=3)
ev("0f", 0x73, "66", 1, "vpsllq", "HWI", "v", B, reg=6)
ev("0f", 0x73, "66", "ig", "vpslldq", "HWI", reg=7)
# moves
ev("0f", 0x6E, "66", 0, "vmovd", "VE", "d", EV_SCALAR)
ev("0f", 0x6E, "66", 1, "vmovq", "VE", "q", EV_SCALAR)
ev("0f", 0x7E, "66", 0, "vmovd", "EV", "d", EV_SCALAR)
ev("0f", 0x7E, "66", 1, "vmovq", "EV", "q", EV_SCALAR)
ev("0f", 0x7E, "F3", 1, "vmovq", "VW", "q", EV_SCALAR)
ev("0f", 0xD6, "66", 1, "vmovq", "WV", "q", EV_SCALAR)
ev2("0f", 0x6F, "66", "vmovdqa32", "vmovdqa64", "VW")
ev2("0f", 0x7F, "66", "vmovdqa32", "vmovdqa64", "WV")
ev2("0f", 0x6F, "F3", "vmovdqu32", "vmovdqu64", "VW")
ev2("0f", 0x7F, "F3", "vmovdqu32", "vmovdqu64", "WV")
ev2("0f", 0x6F, "F2", "vmovdqu8", "vmovdqu16", "VW")
ev2("0f", 0x7F, "F2", "vmovdqu8", "vmovdqu16", "WV")
ev("0f", 0xE7, "66", 0, "vmovntdq", "WV")
ev("0f", 0x70, "66", 0, "vpshufd", "VWI", "v", B)
ev("0f", 0x70, "F3", "ig", "vpshufhw", "VWI")
ev("0f", 0x70, "F2", "ig", "vpshuflw", "VWI")
ev("0f", 0xC4, "66", 0, "vpinsrw", "VHEI", "w", EV_SCALAR)
ev("0f", 0xC5, "66", 0, "vpextrw", "GWI", "w", EV_SCALAR)

# ---- 66 0F 38 ----
for code, n in ((0x00, "vpshufb"), (0x04, "vpmaddubsw"), (0x0B, "vpmulhrsw"), (0x38, "vpminsb"),
                (0x3A, "vpminuw"), (0x3C, "vpmaxsb"), (0x3E, "vpmaxuw"), (0xDC, "vaesenc"),
                (0xDD, "vaesenclast"), (0xDE, "vaesdec"), (0xDF, "vaesdeclast")):
    ev("38", code, "66", "ig", n, "VHW")
ev("38", 0x1C, "66", "ig", "vpabsb", "VW")
ev("38", 0x1D, "66", "ig", "vpabsw", "VW")
ev("38", 0x1E, "66", 0, "vpabsd", "VW", "v", B)
ev("38", 0x1F, "66", 1, "vpabsq", "VW", "v", B)
for code, n in ((0x39, "vpmins"), (0x3B, "vpminu"), (0x3D, "vpmaxs"), (0x3F, "vpmaxu"),
                (0x45, "vpsrlv"), (0x46, "vpsrav"), (0x47, "vpsllv"), (0x64, "vpblendm"),
                (0x76, "vpermi2"), (0x7E, "vpermt2"), (0x36, "vperm")):
    ev2("38", code, "66", n + "d", n + "q", "VHW", "v", B)
for code, n in ((0x16, "vperm"), (0x77, "vpermi2"), (0x7F, "vpermt2"), (0x65, "vblendm"),
                (0x2C, "vscalef")):
    ev2("38", code, "66", n + "ps", n + "pd", "VHW", "v", B | (EV_ER if code == 0x2C else 0))
ev("38", 0x0C, "66", 0, "vpermilps", "VHW", "v", B)       # two opcodes, not one by W
ev("38", 0x0D, "66", 1, "vpermilpd", "VHW", "v", B)
ev2("38", 0x40, "66", "vpmulld", "vpmullq", "VHW", "v", B)
ev("38", 0x28, "66", 1, "vpmuldq", "VHW", "v", B)
ev("38", 0x2B, "66", 0, "vpackusdw", "VHW", "v", B)
for code, n in ((0x66, "vpblendm"), (0x75, "vpermi2"), (0x7D, "vpermt2"), (0x8D, "vperm")):
    ev2("38", code, "66", n + "b", n + "w", "VHW")
for code, n in ((0x10, "vpsrlvw"), (0x11, "vpsravw"), (0x12, "vpsllvw")):
    ev("38", code, "66", 1, n, "VHW")
ev("38", 0x29, "66", 1, "vpcmpeqq", "KHW", "v", B)
ev("38", 0x37, "66", 1, "vpcmpgtq", "KHW", "v", B)
ev2("38", 0x26, "66", "vptestmb", "vptestmw", "KHW")
ev2("38", 0x27, "66", "vptestmd", "vptestmq", "KHW", "v", B)
ev2("38", 0x26, "F3", "vptestnmb", "vptestnmw", "KHW")
ev2("38", 0x27, "F3", "vptestnmd", "vptestnmq", "KHW", "v", B)
# broadcasts
ev("38", 0x18, "66", 0, "vbroadcastss", "VW", "d")
ev("38", 0x19, "66", 0, "vbroadcastf32x2", "VW", "q")
ev("38", 0x19, "66", 1, "vbroadcastsd", "VW", "q")
ev2("38", 0x1A, "66", "vbroadcastf32x4", "vbroadcastf64x2", "VW", "x")
ev2("38", 0x1B, "66", "vbroadcastf32x8", "vbroadcastf64x4", "VW", "y")
ev("38", 0x58, "66", 0, "vpbroadcastd", "VW", "d")
ev("38", 0x59, "66", 0, "vbroadcasti32x2", "VW", "q")
ev("38", 0x59, "66", 1, "vpbroadcastq", "VW", "q")
ev2("38", 0x5A, "66", "vbroadcasti32x4", "vbroadcasti64x2", "VW", "x")
ev2("38", 0x5B, "66", "vbroadcasti32x8", "vbroadcasti64x4", "VW", "y")
ev("38", 0x78, "66", 0, "vpbroadcastb", "VW", "b")
ev("38", 0x79, "66", 0, "vpbroadcastw", "VW", "w")
ev("38", 0x7A, "66", 0, "vpbroadcastb", "VE", "b")
ev("38", 0x7B, "66", 0, "vpbroadcastw", "VE", "w")
ev("38", 0x7C, "66", 0, "vpbroadcastd", "VE", "d")
ev("38", 0x7C, "66", 1, "vpbroadcastq", "VE", "q")
# widening and narrowing moves
for i, (n, sz) in enumerate((("bw", "h"), ("bd", "qv"), ("bq", "o"), ("wd", "h"), ("wq", "qv"), ("dq", "h"))):
    w = 0 if n == "dq" else "ig"
    ev("38", 0x20 + i, "66", w, "vpmovsx" + n, "VW", sz)
    ev("38", 0x30 + i, "66", w, "vpmovzx" + n, "VW", sz)
for i, (n, sz) in enumerate((("wb", "h"), ("db", "qv"), ("qb", "o"), ("dw", "h"), ("qw", "qv"), ("qd", "h"))):
    ev("38", 0x30 + i, "F3", 0, "vpmov" + n, "WV", sz)
    ev("38", 0x20 + i, "F3", 0, "vpmovs" + n, "WV", sz)
    ev("38", 0x10 + i, "F3", 0, "vpmovus" + n, "WV", sz)
ev2("38", 0x28, "F3", "vpmovm2b", "vpmovm2w", "Vk")
ev2("38", 0x38, "F3", "vpmovm2d", "vpmovm2q", "Vk")
ev2("38", 0x29, "F3", "vpmovb2m", "vpmovw2m", "KW")
ev2("38", 0x39, "F3", "vpmovd2m", "vpmovq2m", "KW")
ev2("38", 0x44, "66", "vplzcntd", "vplzcntq", "VW", "v", B)
ev2("38", 0xC4, "66", "vpconflictd", "vpconflictq", "VW", "v", B)
ev2("38", 0x88, "66", "vexpandps", "vexpandpd", "VW", "v", EV_NELEM)
ev2("38", 0x89, "66", "vpexpandd", "vpexpandq", "VW", "v", EV_NELEM)
ev2("38", 0x8A, "66", "vcompressps", "vcompresspd", "WV", "v", EV_NELEM)
ev2("38", 0x8B, "66", "vpcompressd", "vpcompressq", "WV", "v", EV_NELEM)
ev("38", 0x2A, "66", 0, "vmovntdqa", "VW")
ev2("38", 0x4C, "66", "vrcp14ps", "vrcp14pd", "VW", "v", B)
ev2("38", 0x4E, "66", "vrsqrt14ps", "vrsqrt14pd", "VW", "v", B)
ev("38", 0x4D, "66", 0, "vrcp14ss", "VHW", "d", EV_SCALAR)
ev("38", 0x4D, "66", 1, "vrcp14sd", "VHW", "q", EV_SCALAR)
ev("38", 0x4F, "66", 0, "vrsqrt14ss", "VHW", "d", EV_SCALAR)
ev("38", 0x4F, "66", 1, "vrsqrt14sd", "VHW", "q", EV_SCALAR)
ev2("38", 0x42, "66", "vgetexpps", "vgetexppd", "VW", "v", B | EV_SAE)
for code, n in ((0x50, "vpdpbusd"), (0x51, "vpdpbusds"), (0x52, "vpdpwssd"), (0x53, "vpdpwssds")):
    ev("38", code, "66", 0, n, "VHW", "v", B)
ev("38", 0xCF, "66", 0, "vgf2p8mulb", "VHW")
# FMA: 132 / 213 / 231; W picks ps/pd (ss/sd)
for base, fop in (("vfmaddsub", 0x96), ("vfmsubadd", 0x97), ("vfmadd", 0x98), ("vfmsub", 0x9A),
                  ("vfnmadd", 0x9C), ("vfnmsub", 0x9E)):
    for k, order in ((0, "132"), (0x10, "213"), (0x20, "231")):
        ev2("38", fop + k, "66", base + order + "ps", base + order + "pd", "VHW", "v", B | EV_ER)
        if base not in ("vfmaddsub", "vfmsubadd"):
            ev("38", fop + k + 1, "66", 0, base + order + "ss", "VHW", "d", EV_SCALAR | EV_ER)
            ev("38", fop + k + 1, "66", 1, base + order + "sd", "VHW", "q", EV_SCALAR | EV_ER)

# ---- 66 0F 3A ----
ev("3a", 0x00, "66", 1, "vpermq", "VWI", "v", B)
ev("3a", 0x01, "66", 1, "vpermpd", "VWI", "v", B)
ev2("3a", 0x03, "66", "valignd", "valignq", "VHWI", "v", B)
ev("3a", 0x04, "66", 0, "vpermilps", "VWI", "v", B)
ev("3a", 0x05, "66", 1, "vpermilpd", "VWI", "v", B)
ev("3a", 0x08, "66", 0, "vrndscaleps", "VWI", "v", B | EV_SAE)
ev("3a", 0x09, "66", 1, "vrndscalepd", "VWI", "v", B | EV_SAE)
ev("3a", 0x0A, "66", 0, "vrndscaless", "VHWI", "d", EV_SCALAR | EV_SAE)
ev("3a", 0x0B, "66", 1, "vrndscalesd", "VHWI", "q", EV_SCALAR | EV_SAE)
ev("3a", 0x0F, "66", "ig", "vpalignr", "VHWI")
ev("3a", 0x14, "66", 0, "vpextrb", "EVI", "b", EV_SCALAR)
ev("3a", 0x15, "66", 0, "vpextrw", "EVI", "w", EV_SCALAR)
ev("3a", 0x16, "66", 0, "vpextrd", "EVI", "d", EV_SCALAR)
ev("3a", 0x16, "66", 1, "vpextrq", "EVI", "q", EV_SCALAR)
ev("3a", 0x17, "66", 0, "vextractps", "EVI", "d", EV_SCALAR)
ev("3a", 0x20, "66", 0, "vpinsrb", "VHEI", "b", EV_SCALAR)
ev("3a", 0x21, "66", 0, "vinsertps", "VHWI", "d", EV_SCALAR)
ev("3a", 0x22, "66", 0, "vpinsrd", "VHEI", "d", EV_SCALAR)
ev("3a", 0x22, "66", 1, "vpinsrq", "VHEI", "q", EV_SCALAR)
for code, f, sz in ((0x18, "f", "x"), (0x1A, "f", "y"), (0x38, "i", "x"), (0x3A, "i", "y")):
    a, b = ("32x4", "64x2") if sz == "x" else ("32x8", "64x4")
    ev2("3a", code, "66", "vinsert%s%s" % (f, a), "vinsert%s%s" % (f, b), "VHWI", sz)
    ev2("3a", code + 1, "66", "vextract%s%s" % (f, a), "vextract%s%s" % (f, b), "WVI", sz)
ev2("3a", 0x1E, "66", "vpcmpud", "vpcmpuq", "KHWI", "v", B | EV_PINT)
ev2("3a", 0x1F, "66", "vpcmpd", "vpcmpq", "KHWI", "v", B | EV_PINT)
ev2("3a", 0x3E, "66", "vpcmpub", "vpcmpuw", "KHWI", "v", EV_PINT)
ev2("3a", 0x3F, "66", "vpcmpb", "vpcmpw", "KHWI", "v", EV_PINT)
ev2("3a", 0x23, "66", "vshuff32x4", "vshuff64x2", "VHWI", "v", B)
ev2("3a", 0x43, "66", "vshufi32x4", "vshufi64x2", "VHWI", "v", B)
ev2("3a", 0x25, "66", "vpternlogd", "vpternlogq", "VHWI", "v", B)
ev("3a", 0x42, "66", 0, "vdbpsadbw", "VHWI")
ev("3a", 0x44, "66", "ig", "vpclmulqdq", "VHWI")      # x86.s names the known selectors
ev("38", 0xB4, "66", 1, "vpmadd52luq", "VHW", "v", B)
ev("38", 0xB5, "66", 1, "vpmadd52huq", "VHW", "v", B)
ev("3a", 0xCE, "66", 1, "vgf2p8affineqb", "VHWI", "v", B)
ev("3a", 0xCF, "66", 1, "vgf2p8affineinvqb", "VHWI", "v", B)

def evex_rows(name_off):
    out = ["x86_evex:"]
    for key in sorted(evex_tab):
        name, msize, flags, shape = evex_tab[key]
        assert len(shape) < 8
        out.append('    dd 0x%08x\n    dw 0x%04x\n    db %d, 0x%02x, "%s"%s    ; %s'
                   % (key, name_off(name), msize, flags, shape, ", 0" * (8 - len(shape)), name))
    out.append("    dd 0")
    return out

# ---- VEX k-mask instructions (AVX-512 opmask registers) ----
# x86_kops: 16-byte entries ending with a zero byte:
#   db map (2 = 0F, 4 = 0F 3A), opcode, pp | W << 2, shape; name (12)
# Shapes: 1 k,k,k (VEX.L = 1)   2 k,k/mem   3 mem,k   4 k,r32/r64
#         5 r32/r64,k   6 k,k   7 k,k,imm8   (2-7 need VEX.L = 0)
# A memory operand is as wide as the name's last letter (b/w/d/q).
KSUF = {(0, 0): "w", (0, 1): "q", (1, 0): "b", (1, 1): "d"}
kops = []
for code, base, shape in ((0x41, "kand", 1), (0x42, "kandn", 1), (0x45, "kor", 1), (0x46, "kxnor", 1),
                          (0x47, "kxor", 1), (0x4A, "kadd", 1), (0x44, "knot", 6), (0x98, "kortest", 6),
                          (0x99, "ktest", 6), (0x90, "kmov", 2), (0x91, "kmov", 3)):
    for (pp, w), s in KSUF.items():
        kops.append((2, code, pp, w, base + s, shape))
for code, shape in ((0x92, 4), (0x93, 5)):
    for pp, w, n in ((0, 0, "kmovw"), (1, 0, "kmovb"), (3, 0, "kmovd"), (3, 1, "kmovq")):
        kops.append((2, code, pp, w, n, shape))
for pp, w, n in ((1, 0, "kunpckbw"), (0, 0, "kunpckwd"), (0, 1, "kunpckdq")):
    kops.append((2, 0x4B, pp, w, n, 1))
for code, n0, n1 in ((0x30, "kshiftrb", "kshiftrw"), (0x31, "kshiftrd", "kshiftrq"),
                     (0x32, "kshiftlb", "kshiftlw"), (0x33, "kshiftld", "kshiftlq")):
    kops.append((4, code, 1, 0, n0, 7))
    kops.append((4, code, 1, 1, n1, 7))

def kop_rows():
    out = ["x86_kops:"]
    for m, code, pp, w, n, shape in kops:
        out.append('    db %d, 0x%02X, %d, %d, "%s"%s' % (m, code, pp | w << 2, shape, n, ", 0" * (12 - len(n))))
    out.append("    db 0")
    return out


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
