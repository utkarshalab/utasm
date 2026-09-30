#!/usr/bin/env python3
"""
gen_x86_enc.py - regenerate backend/encoder/tables/opcode.s

The table-driven part of the AMD64 encoder (backend/encoder/dispatch.s)
reads the instruction forms written here. Most of them are derived from the
opcode map in scripts/gen_x86_tables.py, the one the disassembler decodes
with, so the assembler and the disassembler agree on every encoding; the
rest (x87, system and other integer instructions) are listed below.

  x86_enc_types   operand types: what an operand may be (8 bytes each)
  x86_enc_index   mnemonic ID -> first form + 1 (0 = not in the table)
  x86_enc_table   the forms, 16 bytes each, grouped by mnemonic, in the
                  order they are tried (the first one that matches wins)

Form layout:
  +0  dw  mnemonic ID (backend/isa/amd64.s)
  +2  db  operand types 0-3 (T_*; 0 = no operand)
  +6  db  mandatory prefix (0 none, 1 66, 2 F3, 3 F2) | encoding << 4
          (0 legacy, 1 VEX, 2 EVEX)
  +7  db  opcode map (1 one-byte, 2 0F, 3 0F 38, 4 0F 3A)
  +8  db  opcode
  +9  db  ModRM: 0-7 /digit, 8 /r, 9 none, 0xC0-0xFF a fixed ModRM byte
  +10 dw  operand roles, 3 bits each (R_*)
  +12 db  flags (F_*)
  +13 db  VEX/EVEX vector length L (0 xmm, 1 ymm, 2 zmm)
  +14 db  EVEX disp8*N scale in bytes (1 for other encodings)
  +15 db  immediate byte appended after the operands (with F_FIXIMM)

    python3 scripts/gen_x86_enc.py           regenerate
    python3 scripts/gen_x86_enc.py --check   fail if out of date
"""

import os, re, sys

sys.dont_write_bytecode = True                   # no __pycache__ in scripts/
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import gen_x86_tables as T                       # the shared opcode map

DST = os.path.join(ROOT, "backend", "encoder", "tables", "opcode.s")
ISA = os.path.join(ROOT, "backend", "isa", "amd64.s")

# ---------------------------------------------------------------- operand types
# rclass: 0 register not allowed, else C_*; special: 1 size 16/32/64 sets the
# operand size, 2 size 32/64 does, 3 immediate; rsize/msize in bits
# (msize 0xFFFF = no memory, 0 = any size); fixreg: required register number;
# imm: immediate kind.
C_GPR, C_XMM, C_YMM, C_ZMM, C_K, C_ST, C_MM, C_CR, C_DR, C_SEG, C_RC, C_SAE = range(1, 13)
NOMEM = 0xFFFF
I8, I8S, I16, I32, IZ, I64, ONE = range(1, 8)
TYPES = [   # name, rclass, special, rsize, msize, fixreg, imm
    ("NONE", 0, 0, 0, NOMEM, 0xFF, 0),
    ("R8", C_GPR, 0, 8, NOMEM, 0xFF, 0), ("R16", C_GPR, 0, 16, NOMEM, 0xFF, 0),
    ("R32", C_GPR, 0, 32, NOMEM, 0xFF, 0), ("R64", C_GPR, 0, 64, NOMEM, 0xFF, 0),
    ("RV", C_GPR, 1, 0, NOMEM, 0xFF, 0), ("RDQ", C_GPR, 2, 0, NOMEM, 0xFF, 0),
    ("RM8", C_GPR, 0, 8, 8, 0xFF, 0), ("RM16", C_GPR, 0, 16, 16, 0xFF, 0),
    ("RM32", C_GPR, 0, 32, 32, 0xFF, 0), ("RM64", C_GPR, 0, 64, 64, 0xFF, 0),
    ("RMV", C_GPR, 1, 0, 0, 0xFF, 0), ("RMDQ", C_GPR, 2, 0, 0, 0xFF, 0),
    ("R32M8", C_GPR, 0, 32, 8, 0xFF, 0), ("R32M16", C_GPR, 0, 32, 16, 0xFF, 0),
    ("RM16V", C_GPR, 1, 16, 16, 0xFF, 0),     # 16-bit r/m that sets the operand size (66)
    ("M", 0, 0, 0, 0, 0xFF, 0), ("M8", 0, 0, 0, 8, 0xFF, 0), ("M16", 0, 0, 0, 16, 0xFF, 0),
    ("M32", 0, 0, 0, 32, 0xFF, 0), ("M64", 0, 0, 0, 64, 0xFF, 0), ("M80", 0, 0, 0, 80, 0xFF, 0),
    ("M128", 0, 0, 0, 128, 0xFF, 0), ("M256", 0, 0, 0, 256, 0xFF, 0), ("M512", 0, 0, 0, 512, 0xFF, 0),
    ("MV", 0, 1, 0, 0, 0xFF, 0), ("MDQ", 0, 2, 0, 0, 0xFF, 0),
    ("X", C_XMM, 0, 128, NOMEM, 0xFF, 0), ("Y", C_YMM, 0, 256, NOMEM, 0xFF, 0),
    ("Z", C_ZMM, 0, 512, NOMEM, 0xFF, 0),
    ("XM8", C_XMM, 0, 128, 8, 0xFF, 0), ("XM16", C_XMM, 0, 128, 16, 0xFF, 0),
    ("XM32", C_XMM, 0, 128, 32, 0xFF, 0), ("XM64", C_XMM, 0, 128, 64, 0xFF, 0),
    ("XM128", C_XMM, 0, 128, 128, 0xFF, 0), ("YM256", C_YMM, 0, 256, 256, 0xFF, 0),
    ("ZM512", C_ZMM, 0, 512, 512, 0xFF, 0),
    ("MM", C_MM, 0, 64, NOMEM, 0xFF, 0), ("MMM64", C_MM, 0, 64, 64, 0xFF, 0),
    ("K", C_K, 0, 0, NOMEM, 0xFF, 0), ("KM8", C_K, 0, 0, 8, 0xFF, 0), ("KM16", C_K, 0, 0, 16, 0xFF, 0),
    ("KM32", C_K, 0, 0, 32, 0xFF, 0), ("KM64", C_K, 0, 0, 64, 0xFF, 0),
    ("ST", C_ST, 0, 0, NOMEM, 0xFF, 0), ("ST0", C_ST, 0, 0, NOMEM, 0, 0),
    ("CR", C_CR, 0, 0, NOMEM, 0xFF, 0), ("DR", C_DR, 0, 0, NOMEM, 0xFF, 0),
    ("SREG", C_SEG, 0, 0, NOMEM, 0xFF, 0),
    ("AL", C_GPR, 0, 8, NOMEM, 0, 0), ("AX", C_GPR, 0, 16, NOMEM, 0, 0),
    ("EAX", C_GPR, 0, 32, NOMEM, 0, 0), ("RAX", C_GPR, 0, 64, NOMEM, 0, 0),
    ("CL", C_GPR, 0, 8, NOMEM, 1, 0), ("DX", C_GPR, 0, 16, NOMEM, 2, 0),
    ("XMM0", C_XMM, 0, 128, NOMEM, 0, 0),
    ("FS", C_SEG, 0, 0, NOMEM, 4, 0), ("GS", C_SEG, 0, 0, NOMEM, 5, 0),
    ("ONE", 0, 3, 0, NOMEM, 0xFF, ONE), ("I8", 0, 3, 0, NOMEM, 0xFF, I8),
    ("I8S", 0, 3, 0, NOMEM, 0xFF, I8S), ("I16", 0, 3, 0, NOMEM, 0xFF, I16),
    ("I32", 0, 3, 0, NOMEM, 0xFF, I32), ("IZ", 0, 3, 0, NOMEM, 0xFF, IZ),
    ("I64", 0, 3, 0, NOMEM, 0xFF, I64),
    # strict memory: the size must be written (x87 picks the opcode by size)
    ("MS16", 0, 0, 0, 0x8000 | 16, 0xFF, 0), ("MS32", 0, 0, 0, 0x8000 | 32, 0xFF, 0),
    ("MS64", 0, 0, 0, 0x8000 | 64, 0xFF, 0), ("MS80", 0, 0, 0, 0x8000 | 80, 0xFF, 0),
    # AVX-512 operands written as {rn-sae} / {rd-sae} / {ru-sae} / {rz-sae} and {sae}
    ("RC", C_RC, 0, 0, NOMEM, 0xFF, 0), ("SAE", C_SAE, 0, 0, NOMEM, 0xFF, 0),
    # gather/scatter addresses: [base + xmm/ymm/zmm index * scale]
    ("VMX", 0, 4, 0, 0, 1, 0), ("VMY", 0, 4, 0, 0, 2, 0), ("VMZ", 0, 4, 0, 0, 3, 0),
]
TY = {t[0]: i for i, t in enumerate(TYPES)}

# roles
R_NONE, R_REG, R_RM, R_VVVV, R_PLUS, R_IMM, R_IS4 = range(7)
# flags
F_W, F_OSZ, F_D64, F_WAIT, F_FIXIMM, F_BCST = 1, 2, 4, 8, 16, 32
PFXN = {"": 0, "np": 0, "66": 1, "F3": 2, "F2": 3}
MAPN = {"": 1, "0f": 2, "38": 3, "3a": 4}
M_DIGIT = lambda d: d
M_R, M_NONE = 8, 9

forms = []     # (name, types, pfx, map, opcode, modrm, roles, flags, fiximm, prio, enc, L)
ENC_LEGACY, ENC_VEX, ENC_EVEX = 0, 1, 2

# objdump's names for undocumented x87 aliases: no assembler accepts them
SKIP = {"fcom2", "fcomp3", "fcomp5", "ffreep", "fstp1", "fstp8", "fstp9", "fxch4", "fxch7"}

def form(name, types, pfx, mp, opcode, modrm, roles, flags=0, fiximm=0, prio=0, enc=ENC_LEGACY, L=0):
    if name in SKIP:
        return
    types = types.split() if isinstance(types, str) else list(types)
    roles = roles.split() if isinstance(roles, str) else list(roles)
    assert len(types) == len(roles), (name, types, roles)
    rmap = {"-": R_NONE, "reg": R_REG, "rm": R_RM, "v": R_VVVV, "+": R_PLUS, "i": R_IMM, "is4": R_IS4}
    forms.append((name, [TY[t] for t in types], PFXN[pfx], MAPN[mp], opcode, modrm,
                  [rmap[r] for r in roles], flags, fiximm, prio, enc, L))

def vform(name, types, pfx, mp, opcode, modrm, roles, flags=0, fiximm=0, prio=0, L=0):
    form(name, types, pfx, mp, opcode, modrm, roles, flags, fiximm, prio, ENC_VEX, L)

# ============================================================================
# SSE family, from the shared opcode map (legacy encodings)
# ============================================================================
MSZ = {T.S_MEM_B: 8, T.S_MEM_W: 16, T.S_MEM_D: 32, T.S_MEM_Q: 64, T.S_MEM_X: 128, 0: 0}
FORM_NAME = {v: k for k, v in T.FM.items()}
PRED8 = "eq lt le unord neq nlt nle ord".split()
PCLMUL = (("lqlq", 0x00), ("hqlq", 0x01), ("lqhq", 0x10), ("hqhq", 0x11))

def vec_types(fl, msz):
    """(register type, register-or-memory type) of an SSE entry."""
    if fl & T.S_MMX:
        return "MM", "MMM64"
    return "X", {8: "XM8", 16: "XM16", 32: "XM32", 64: "XM64", 128: "XM128", 0: "XM128"}[msz]

def mem_type(msz):
    return {0: "M", 8: "M8", 16: "M16", 32: "M32", 64: "M64", 128: "M128"}[msz]

def sse_forms():
    for tab, mp in (("0f", "0f"), ("38", "38"), ("3a", "3a")):
        for key, (name, fm, fl) in sorted(T.sse_tabs[tab].items()):
            opcode, pfx = key // 4, ("np", "66", "F3", "F2")[key % 4]
            f = FORM_NAME[fm]
            if fl & 0x80:                           # integer instruction selected by a prefix
                continue                            # listed by hand below
            msz = MSZ[fl & 7]
            V, W = vec_types(fl, msz)
            wq = fl & T.S_WQ
            if f == "VW":
                form(name, [V, W], pfx, mp, opcode, M_R, "reg rm")
            elif f == "WV":
                form(name, [W, V], pfx, mp, opcode, M_R, "rm reg")
            elif f == "VWI":
                form(name, [V, W, "I8"], pfx, mp, opcode, M_R, "reg rm i")
            elif f in ("VE", "EV", "VEI", "EVI"):
                if msz in (8, 16):
                    E = "R32M%d" % msz
                elif wq or msz == 32:
                    E = "RM32"
                else:
                    E = "RMDQ"
                ops = {"VE": ([V, E], "reg rm"), "EV": ([E, V], "rm reg"),
                       "VEI": ([V, E, "I8"], "reg rm i"), "EVI": ([E, V, "I8"], "rm reg i")}[f]
                form(name, ops[0], pfx, mp, opcode, M_R, ops[1], F_OSZ if E == "RMDQ" else 0)
                if wq:                              # movd -> movq, pinsrd -> pinsrq with REX.W
                    q = [("RM64" if t == "RM32" else t) for t in ops[0]]
                    form(name[:-1] + "q", q, pfx, mp, opcode, M_R, ops[1], F_W, prio=1)
            elif f == "GW":
                form(name, ["RDQ", W], pfx, mp, opcode, M_R, "reg rm", F_OSZ)
            elif f == "GU":
                form(name, ["R32", V], pfx, mp, opcode, M_R, "reg rm")
                form(name, ["R64", V], pfx, mp, opcode, M_R, "reg rm", F_W, prio=1)
            elif f == "GUI":
                form(name, ["R32", V, "I8"], pfx, mp, opcode, M_R, "reg rm i")
            elif f == "UI":
                for r, e in enumerate(T.groups[name]):  # name = group number here
                    if e:
                        form(e[0], [V, "I8"], pfx, mp, opcode, r, "rm i")
            elif f == "VM":
                form(name, [V, mem_type(msz)], pfx, mp, opcode, M_R, "reg rm")
            elif f == "MV":
                form(name, [mem_type(msz), V], pfx, mp, opcode, M_R, "rm reg")
            elif f == "V12":                        # movlps/movhps; the register form is movhlps/movlhps
                form(name, [V, "M64"], pfx, mp, opcode, M_R, "reg rm")
                form("movhlps" if opcode == 0x12 else "movlhps", [V, V], pfx, mp, opcode, M_R, "reg rm")
            elif f == "VW0":
                form(name, [V, W, "XMM0"], pfx, mp, opcode, M_R, "reg rm -")
                form(name, [V, W], pfx, mp, opcode, M_R, "reg rm")
            elif f == "CMPS":
                form(name, [V, W, "I8"], pfx, mp, opcode, M_R, "reg rm i")
                for i, p in enumerate(PRED8):
                    form("cmp" + p + name[3:], [V, W], pfx, mp, opcode, M_R, "reg rm", F_FIXIMM, i)
            elif f == "PCLMUL":
                form(name, [V, W, "I8"], pfx, mp, opcode, M_R, "reg rm i")
                for n, imm in PCLMUL:
                    form("pclmul" + n + "dq", [V, W], pfx, mp, opcode, M_R, "reg rm", F_FIXIMM, imm)
            elif f == "ENDBR":
                form("endbr64", [], pfx, mp, opcode, 0xFA, [])
                form("endbr32", [], pfx, mp, opcode, 0xFB, [])
            elif f == "NONE":
                form(name, [], pfx, mp, opcode, M_NONE, [])
            else:
                raise SystemExit("unhandled SSE form %s (%s)" % (f, name))

sse_forms()

# integer instructions selected by a prefix
form("popcnt", "RV RMV", "F3", "0f", 0xB8, M_R, "reg rm", F_OSZ)
form("tzcnt", "RV RMV", "F3", "0f", 0xBC, M_R, "reg rm", F_OSZ)
form("lzcnt", "RV RMV", "F3", "0f", 0xBD, M_R, "reg rm", F_OSZ)
form("movbe", "RV MV", "np", "38", 0xF0, M_R, "reg rm", F_OSZ)
form("movbe", "MV RV", "np", "38", 0xF1, M_R, "rm reg", F_OSZ)
form("crc32", "R32 RM8", "F2", "38", 0xF0, M_R, "reg rm")
form("crc32", "R64 RM8", "F2", "38", 0xF0, M_R, "reg rm", F_W)
form("crc32", "R32 RM16V", "F2", "38", 0xF1, M_R, "reg rm", F_OSZ)  # 66 from the r/m16
form("crc32", "R32 RM32", "F2", "38", 0xF1, M_R, "reg rm")
form("crc32", "R64 RM64", "F2", "38", 0xF1, M_R, "reg rm", F_W)
form("adcx", "RDQ RMDQ", "66", "38", 0xF6, M_R, "reg rm", F_OSZ)
form("adox", "RDQ RMDQ", "F3", "38", 0xF6, M_R, "reg rm", F_OSZ)
form("movnti", "MDQ RDQ", "np", "0f", 0xC3, M_R, "rm reg", F_OSZ)
# NASM also spells movsxd r64, r/m32 as movsx
form("movsx", "R64 RM32", "", "", 0x63, M_R, "reg rm", F_W)

# ============================================================================
# Other integer and system instructions
# ============================================================================
FIXED = [   # name, prefix, map, opcode, fixed ModRM (or M_NONE), flags
    ("clc", "", "", 0xF8, M_NONE, 0), ("stc", "", "", 0xF9, M_NONE, 0), ("cmc", "", "", 0xF5, M_NONE, 0),
    ("hlt", "", "", 0xF4, M_NONE, 0), ("int1", "", "", 0xF1, M_NONE, 0), ("pause", "F3", "", 0x90, M_NONE, 0),
    ("lahf", "", "", 0x9F, M_NONE, 0), ("sahf", "", "", 0x9E, M_NONE, 0),
    ("pushf", "", "", 0x9C, M_NONE, 0), ("pushfq", "", "", 0x9C, M_NONE, 0), ("pushfw", "66", "", 0x9C, M_NONE, 0),
    ("popf", "", "", 0x9D, M_NONE, 0), ("popfq", "", "", 0x9D, M_NONE, 0), ("popfw", "66", "", 0x9D, M_NONE, 0),
    ("iret", "", "", 0xCF, M_NONE, 0), ("iretd", "", "", 0xCF, M_NONE, 0), ("iretq", "", "", 0xCF, M_NONE, F_W),
    ("cbw", "66", "", 0x98, M_NONE, 0), ("cwde", "", "", 0x98, M_NONE, 0), ("cdqe", "", "", 0x98, M_NONE, F_W),
    ("cwd", "66", "", 0x99, M_NONE, 0), ("cdq", "", "", 0x99, M_NONE, 0), ("cqo", "", "", 0x99, M_NONE, F_W),
    ("wait", "", "", 0x9B, M_NONE, 0), ("fwait", "", "", 0x9B, M_NONE, 0),
    ("ud2", "", "0f", 0x0B, M_NONE, 0), ("cpuid", "", "0f", 0xA2, M_NONE, 0),
    ("rdtsc", "", "0f", 0x31, M_NONE, 0), ("rdmsr", "", "0f", 0x32, M_NONE, 0), ("wrmsr", "", "0f", 0x30, M_NONE, 0),
    ("rdpmc", "", "0f", 0x33, M_NONE, 0), ("clts", "", "0f", 0x06, M_NONE, 0), ("invd", "", "0f", 0x08, M_NONE, 0),
    ("wbinvd", "", "0f", 0x09, M_NONE, 0), ("sysenter", "", "0f", 0x34, M_NONE, 0),
    ("sysexit", "", "0f", 0x35, M_NONE, 0), ("rsm", "", "0f", 0xAA, M_NONE, 0),
    ("sysretq", "", "0f", 0x07, M_NONE, F_W), ("sysexitq", "", "0f", 0x35, M_NONE, F_W),
    ("lfence", "", "0f", 0xAE, 0xE8, 0), ("mfence", "", "0f", 0xAE, 0xF0, 0), ("sfence", "", "0f", 0xAE, 0xF8, 0),
    ("monitor", "", "0f", 0x01, 0xC8, 0), ("mwait", "", "0f", 0x01, 0xC9, 0), ("clac", "", "0f", 0x01, 0xCA, 0),
    ("stac", "", "0f", 0x01, 0xCB, 0), ("vmcall", "", "0f", 0x01, 0xC1, 0), ("vmlaunch", "", "0f", 0x01, 0xC2, 0),
    ("vmresume", "", "0f", 0x01, 0xC3, 0), ("vmxoff", "", "0f", 0x01, 0xC4, 0),
    ("xgetbv", "", "0f", 0x01, 0xD0, 0), ("xsetbv", "", "0f", 0x01, 0xD1, 0), ("xend", "", "0f", 0x01, 0xD5, 0),
    ("xtest", "", "0f", 0x01, 0xD6, 0), ("serialize", "", "0f", 0x01, 0xE8, 0), ("rdpkru", "", "0f", 0x01, 0xEE, 0),
    ("wrpkru", "", "0f", 0x01, 0xEF, 0), ("swapgs", "", "0f", 0x01, 0xF8, 0), ("rdtscp", "", "0f", 0x01, 0xF9, 0),
]
for n, p, mp, op, m, fl in FIXED:
    form(n, [], p, mp, op, m, [], fl)

for n, code in (("bsf", 0xBC), ("bsr", 0xBD)):
    form(n, "RV RMV", "", "0f", code, M_R, "reg rm", F_OSZ)
for n, code in (("shld", 0xA4), ("shrd", 0xAC)):
    form(n, "RMV RV I8", "", "0f", code, M_R, "rm reg i", F_OSZ)
    form(n, "RMV RV CL", "", "0f", code + 1, M_R, "rm reg -", F_OSZ)
for n, code in (("cmpxchg", 0xB0), ("xadd", 0xC0)):
    form(n, "RM8 R8", "", "0f", code, M_R, "rm reg")
    form(n, "RMV RV", "", "0f", code + 1, M_R, "rm reg", F_OSZ)
form("bswap", "RDQ", "", "0f", 0xC8, M_NONE, "+", F_OSZ)
form("cmpxchg8b", "M64", "", "0f", 0xC7, 1, "rm")
form("cmpxchg16b", "M128", "", "0f", 0xC7, 1, "rm", F_W)
form("rdrand", "RV", "", "0f", 0xC7, 6, "rm", F_OSZ)
form("rdseed", "RV", "", "0f", 0xC7, 7, "rm", F_OSZ)
for r, n in enumerate(("prefetchnta", "prefetcht0", "prefetcht1", "prefetcht2")):
    form(n, "M", "", "0f", 0x18, r, "rm")
form("prefetchw", "M", "", "0f", 0x0D, 1, "rm")
for n, p, r, t, fl in (("fxsave", "", 0, "M", 0), ("fxrstor", "", 1, "M", 0), ("ldmxcsr", "", 2, "M32", 0),
                       ("stmxcsr", "", 3, "M32", 0), ("xsave", "", 4, "M", 0), ("xrstor", "", 5, "M", 0),
                       ("xsaveopt", "", 6, "M", 0), ("clflush", "", 7, "M", 0), ("clwb", "66", 6, "M", 0),
                       ("clflushopt", "66", 7, "M", 0), ("fxsave64", "", 0, "M", F_W),
                       ("fxrstor64", "", 1, "M", F_W), ("xsave64", "", 4, "M", F_W), ("xrstor64", "", 5, "M", F_W)):
    form(n, t, p, "0f", 0xAE, r, "rm", fl)
for r, n in enumerate(("sgdt", "sidt", "lgdt", "lidt")):
    form(n, "M", "", "0f", 0x01, r, "rm")
form("smsw", "RV", "", "0f", 0x01, 4, "rm", F_OSZ)
form("smsw", "M16", "", "0f", 0x01, 4, "rm")
form("lmsw", "RM16", "", "0f", 0x01, 6, "rm")
form("invlpg", "M", "", "0f", 0x01, 7, "rm")
# NASM writes str r64 with REX.W but sldt r64 without it
form("sldt", "RV", "", "0f", 0x00, 0, "rm", F_OSZ | F_D64)
form("str", "RV", "", "0f", 0x00, 1, "rm", F_OSZ)
for r, n in enumerate(("sldt", "str")):
    form(n, "M16", "", "0f", 0x00, r, "rm")
for r, n in ((2, "lldt"), (3, "ltr"), (4, "verr"), (5, "verw")):
    form(n, "RM16", "", "0f", 0x00, r, "rm")
form("mov", "R64 CR", "", "0f", 0x20, M_R, "rm reg")
form("mov", "CR R64", "", "0f", 0x22, M_R, "reg rm")
form("mov", "R64 DR", "", "0f", 0x21, M_R, "rm reg")
form("mov", "DR R64", "", "0f", 0x23, M_R, "reg rm")
form("push", "I8S", "", "", 0x6A, M_NONE, "i")
form("push", "IZ", "", "", 0x68, M_NONE, "i")
form("push", "FS", "", "0f", 0xA0, M_NONE, "-")
form("pop", "FS", "", "0f", 0xA1, M_NONE, "-")
form("push", "GS", "", "0f", 0xA8, M_NONE, "-")
form("pop", "GS", "", "0f", 0xA9, M_NONE, "-")
form("nop", "RMV", "", "0f", 0x1F, 0, "rm", F_OSZ)
for r, n in ((2, "rcl"), (3, "rcr")):
    form(n, "RM8 ONE", "", "", 0xD0, r, "rm -")
    form(n, "RMV ONE", "", "", 0xD1, r, "rm -", F_OSZ)
    form(n, "RM8 CL", "", "", 0xD2, r, "rm -")
    form(n, "RMV CL", "", "", 0xD3, r, "rm -", F_OSZ)
    form(n, "RM8 I8", "", "", 0xC0, r, "rm i")
    form(n, "RMV I8", "", "", 0xC1, r, "rm i", F_OSZ)

# ============================================================================
# VEX (AVX, AVX2, FMA, BMI), from the shared opcode map
# ============================================================================
PRED32 = ("eq lt le unord neq nlt nle ord eq_uq nge ngt false neq_oq ge gt true "
          "eq_os lt_oq le_oq unord_s neq_us nlt_uq nle_uq ord_s eq_us nge_uq ngt_uq "
          "false_os neq_os ge_oq gt_oq true_us").split()
# packed (XMMWORD) instructions without a 256-bit VEX form
XMM_ONLY = {"pcmpestri", "pcmpestrm", "pcmpistri", "pcmpistrm", "aesimc", "aeskeygenassist",
            "phminposuw", "maskmovdqu", "dppd"}
VEX_W1_SSE = {"vgf2p8affineqb", "vgf2p8affineinvqb"}
SHIFT_BY_XMM = {"psrlw", "psrld", "psrlq", "psraw", "psrad", "psllw", "pslld", "psllq"}
NARROW = {"cvtpd2ps", "cvtpd2dq", "cvttpd2dq"}           # xmm destination, ymm source
WIDEN = {"cvtdq2pd", "cvtps2pd"}                         # ymm destination, xmm source
XM = {8: "XM8", 16: "XM16", 32: "XM32", 64: "XM64", 128: "XM128"}

def vex_from_sse():
    """The SSE instructions with a VEX form: "v" + name, vvvv as an extra source."""
    for tab, mp in (("0f", "0f"), ("38", "38"), ("3a", "3a")):
        for key, (name, fm, fl) in sorted(T.sse_tabs[tab].items()):
            opcode, pfx = key // 4, ("np", "66", "F3", "F2")[key % 4]
            f = FORM_NAME[fm]
            if fl & (0x80 | T.S_NOVEX | T.S_MMX) or f in ("NONE", "ENDBR", "VW0"):
                continue
            msz = MSZ[fl & 7]
            nds = bool(fl & T.S_NDS)
            wq = fl & T.S_WQ
            v = "v" + name if isinstance(name, str) else None
            vw = F_W if v in VEX_W1_SSE else 0            # VEX.W1 by name
            wide = msz == 128 and (not isinstance(name, str) or name not in XMM_ONLY)
            W = XM.get(msz, "XM128")

            def both(types0, types1, roles, flags=0, fiximm=0, prio=0, nm=None):
                nm = nm or v
                vform(nm, types0, pfx, mp, opcode, M_R, roles, flags | vw, fiximm, prio, L=0)
                if types1:
                    vform(nm, types1, pfx, mp, opcode, M_R, roles, flags | vw, fiximm, prio, L=1)

            if f == "VW":
                if name in ("movss", "movsd"):
                    vform(v, ["X", mem_type(msz)], pfx, mp, opcode, M_R, "reg rm")
                    vform(v, "X X X", pfx, mp, opcode, M_R, "reg v rm")
                elif name in SHIFT_BY_XMM:
                    both(["X", "X", "XM128"], ["Y", "Y", "XM128"], "reg v rm")
                elif name.startswith(("pmovsx", "pmovzx")):
                    both(["X", W], ["Y", XM[2 * msz]], "reg rm")
                elif name in WIDEN:
                    both(["X", W], ["Y", "XM128"], "reg rm")
                elif name in NARROW:
                    both(["X", "XM128"], ["X", "YM256"], "reg rm")
                elif name == "movddup":
                    both(["X", W], ["Y", "YM256"], "reg rm")
                elif nds:
                    both(["X", "X", W], ["Y", "Y", "YM256"] if wide else None, "reg v rm")
                else:
                    both(["X", W], ["Y", "YM256"] if wide else None, "reg rm")
            elif f == "WV":
                if name in ("movss", "movsd"):
                    vform(v, [mem_type(msz), "X"], pfx, mp, opcode, M_R, "rm reg")
                    vform(v, "X X X", pfx, mp, opcode, M_R, "rm v reg")
                else:
                    both([W, "X"], ["YM256", "Y"] if wide else None, "rm reg")
            elif f == "VWI":
                if nds:
                    both(["X", "X", W, "I8"], ["Y", "Y", "YM256", "I8"] if wide else None, "reg v rm i")
                else:
                    both(["X", W, "I8"], ["Y", "YM256", "I8"] if wide else None, "reg rm i")
            elif f in ("VE", "VEI", "EV", "EVI"):
                if msz in (8, 16):
                    E = "R32M%d" % msz
                elif wq or msz == 32:
                    E = "RM32"
                else:
                    E = "RMDQ"
                fl2 = F_OSZ if E == "RMDQ" else 0
                if f == "VE":
                    t, r = (["X", "X", E], "reg v rm") if nds else (["X", E], "reg rm")
                elif f == "VEI":
                    t, r = (["X", "X", E, "I8"], "reg v rm i") if nds else (["X", E, "I8"], "reg rm i")
                elif f == "EV":
                    t, r = [E, "X"], "rm reg"
                else:
                    t, r = [E, "X", "I8"], "rm reg i"
                vform(v, t, pfx, mp, opcode, M_R, r, fl2)
                if wq:
                    vform(v[:-1] + "q", [("RM64" if x == "RM32" else x) for x in t], pfx, mp, opcode,
                          M_R, r, F_W, prio=1)
            elif f == "GW":
                vform(v, ["RDQ", W], pfx, mp, opcode, M_R, "reg rm", F_OSZ)
            elif f == "GU":
                both(["R32", "X"], ["R32", "Y"], "reg rm")
                both(["R64", "X"], ["R64", "Y"], "reg rm", prio=1)
            elif f == "GUI":
                vform(v, ["R32", "X", "I8"], pfx, mp, opcode, M_R, "reg rm i")
            elif f == "UI":
                for r, e in enumerate(T.groups[name]):
                    if e:
                        vform("v" + e[0], "X X I8", pfx, mp, opcode, r, "v rm i", L=0)
                        vform("v" + e[0], "Y Y I8", pfx, mp, opcode, r, "v rm i", L=1)
            elif f == "VM":
                if nds:
                    vform(v, ["X", "X", mem_type(msz)], pfx, mp, opcode, M_R, "reg v rm")
                elif msz == 128:
                    both(["X", "M128"], ["Y", "M256"], "reg rm")
                else:
                    both(["X", "M"], ["Y", "M"], "reg rm")      # vlddqu: sized by the register
            elif f == "MV":
                if msz == 128:
                    both(["M128", "X"], ["M256", "Y"], "rm reg")
                else:
                    vform(v, [mem_type(msz), "X"], pfx, mp, opcode, M_R, "rm reg")
            elif f == "V12":
                vform(v, "X X M64", pfx, mp, opcode, M_R, "reg v rm")
                vform("vmovhlps" if opcode == 0x12 else "vmovlhps", "X X X", pfx, mp, opcode, M_R, "reg v rm")
            elif f == "CMPS":
                sfx = name[3:]
                both(["X", "X", W, "I8"], ["Y", "Y", "YM256", "I8"] if wide else None, "reg v rm i")
                for i, p in enumerate(PRED32):
                    both(["X", "X", W], ["Y", "Y", "YM256"] if wide else None, "reg v rm",
                         F_FIXIMM, i, nm="vcmp" + p + sfx)
            elif f == "PCLMUL":
                both(["X", "X", W, "I8"], ["Y", "Y", "YM256", "I8"], "reg v rm i")
                for n, imm in PCLMUL:
                    both(["X", "X", W], ["Y", "Y", "YM256"], "reg v rm", F_FIXIMM, imm,
                         nm="vpclmul" + n + "dq")
            else:
                raise SystemExit("unhandled SSE form for VEX: %s (%s)" % (f, name))

# VEX.W1 where the name alone does not say so, and the 256-bit-only instructions
VEX_W1 = {"vpermq", "vpermpd"}
YMM_ONLY = {"vpermps", "vpermd", "vpermq", "vpermpd", "vperm2f128", "vperm2i128", "vbroadcastsd",
            "vbroadcastf128", "vbroadcasti128"}

def vex_only():
    for tab, mp in (("0f", "0f"), ("38", "38"), ("3a", "3a")):
        for key, (name, fm, fl) in sorted(T.vex_tabs[tab].items()):
            opcode, pfx = key // 4, ("np", "66", "F3", "F2")[key % 4]
            f = FORM_NAME[fm]
            msz = MSZ[fl & 7]
            names = [(name, 0, msz)]
            if isinstance(name, str) and fl & T.V_WSD:     # vfmadd132ps / vfmadd132pd
                names.append((name[:-1] + "d", F_W, 64 if msz == 32 else msz))
            elif isinstance(name, str) and fl & T.S_WQ:    # vpsrlvd / vpsrlvq
                names.append((name[:-1] + "q", F_W, msz))
            for nm, wf, nmsz in names:
                if isinstance(nm, str) and nm in VEX_W1:
                    wf |= F_W
                ymm_only = isinstance(nm, str) and nm in YMM_ONLY
                wm = XM.get(nmsz, "XM128")
                scalar = msz in (8, 16, 32, 64)

                def both(t0, t1, roles, flags=0):
                    if not ymm_only:
                        vform(nm, t0, pfx, mp, opcode, M_R, roles, flags | wf, L=0)
                    if t1:
                        vform(nm, t1, pfx, mp, opcode, M_R, roles, flags | wf, L=1)

                if f == "VW":
                    if fl & T.S_NDS:
                        both(["X", "X", wm], None if scalar else ["Y", "Y", "YM256"], "reg v rm")
                    else:
                        both(["X", wm], None if scalar else ["Y", "YM256"], "reg rm")
                elif f == "VWI":
                    if fl & T.S_NDS:
                        both(["X", "X", "XM128", "I8"], ["Y", "Y", "YM256", "I8"], "reg v rm i")
                    else:
                        both(["X", "XM128", "I8"], ["Y", "YM256", "I8"], "reg rm i")
                elif f == "XBCAST":
                    src = {8: "XM8", 16: "XM16", 32: "XM32", 64: "XM64", 128: "M128"}[msz]
                    both(["X", src], ["Y", src], "reg rm")
                elif f == "XMLD":
                    both(["X", "X", "M128"], ["Y", "Y", "M256"], "reg v rm")
                elif f == "XMST":
                    both(["M128", "X", "X"], ["M256", "Y", "Y"], "rm v reg")
                elif f == "XINS":
                    vform(nm, "Y Y XM128 I8", pfx, mp, opcode, M_R, "reg v rm i", wf, L=1)
                elif f == "XEXT":
                    vform(nm, "XM128 Y I8", pfx, mp, opcode, M_R, "rm reg i", wf, L=1)
                elif f == "XIS4":
                    both(["X", "X", "XM128", "X"], ["Y", "Y", "YM256", "Y"], "reg v rm is4")
                elif f == "BGBE":
                    vform(nm, "RDQ RDQ RMDQ", pfx, mp, opcode, M_R, "reg v rm", F_OSZ)
                elif f == "BGEB":
                    vform(nm, "RDQ RMDQ RDQ", pfx, mp, opcode, M_R, "reg rm v", F_OSZ)
                elif f == "BBE":
                    for r, e in enumerate(T.groups[nm]):
                        if e:
                            vform(e[0], "RDQ RMDQ", pfx, mp, opcode, r, "v rm", F_OSZ)
                elif f == "BRORX":
                    vform(nm, "RDQ RMDQ I8", pfx, mp, opcode, M_R, "reg rm i", F_OSZ)
                elif f == "XZERO":
                    vform("vzeroupper", [], pfx, mp, opcode, M_NONE, [], L=0)
                    vform("vzeroall", [], pfx, mp, opcode, M_NONE, [], L=1)
                else:
                    raise SystemExit("unhandled VEX form %s (%s)" % (f, nm))

vex_only()
vex_from_sse()
vform("vldmxcsr", "M32", "np", "0f", 0xAE, 2, "rm")
vform("vstmxcsr", "M32", "np", "0f", 0xAE, 3, "rm")

# ============================================================================
# EVEX (AVX-512), from the shared opcode map
# ============================================================================
# The EVEX table is keyed by map, opcode, pp, W and group; its entries give
# the memory size class, flags and an operand shape (see gen_x86_tables.py).
# Each becomes forms for the vector lengths it can have, with the disp8*N
# scale in the form (FM +14) and F_BCST where a memory operand can be a
# broadcast. {k}/{z} masks are accepted on any EVEX form; a trailing
# {rn-sae}.. / {sae} operand selects the rounding forms.
EMAP = {2: "0f", 3: "38", 4: "3a"}
EPFX = {0: "np", 1: "66", 2: "F3", 3: "F2"}
EV_PRED_INT = ("eq", "lt", "le", None, "neq", "nlt", "nle")

def eform(name, types, pfx, mp, opcode, modrm, roles, flags=0, fiximm=0, prio=0, L=0, n8=1):
    form(name, types, pfx, mp, opcode, modrm, roles, flags, fiximm, prio, ENC_EVEX, L)
    forms[-1] = forms[-1] + (n8,)

def ev_mem_bytes(msize, L):
    vl = 16 << L
    return {0: vl, 1: 1, 2: 2, 3: 4, 4: 8, 5: vl // 2, 6: vl // 4, 7: vl // 8, 8: 16, 9: 32}[msize]

def vec_rm(nbytes):
    """register-or-memory type for a W operand of nbytes"""
    return {1: "XM8", 2: "XM16", 4: "XM32", 8: "XM64", 16: "XM128", 32: "YM256", 64: "ZM512"}[nbytes]

def vec_reg(L):
    return ("X", "Y", "Z")[L]

def evex_forms():
    by_slot = {}
    for key, e in T.evex_tab.items():
        slot = key & ~0x10                       # same map/opcode/pp/group, either W
        by_slot.setdefault(slot, {})[(key >> 4) & 1] = e
    for key in sorted(T.evex_tab):
        name, msize, flags, shape = T.evex_tab[key]
        mapn, opcode, pp, w, g = key >> 24, (key >> 16) & 0xFF, (key >> 8) & 3, (key >> 4) & 1, key & 15
        gpr = "E" in shape or "G" in shape
        other = by_slot[key & ~0x10].get(1 - w)
        if w == 1 and other is not None and other[0] == name and not gpr:
            continue                             # W ignored: NASM writes W0
        mp, pfx = EMAP[mapn], EPFX[pp]
        modrm = (g - 8) if g else M_R
        wf = F_W if w else 0
        bc = F_BCST if flags & T.EV_BCST else 0
        elem = 8 if w else 4
        scalar = bool(flags & T.EV_SCALAR)
        for L in ((0,) if scalar else (0, 1, 2)):
            types, roles = [], []
            nbytes = ev_mem_bytes(msize, L)
            for c in shape:
                if c == "V":
                    types.append("X" if scalar else vec_reg(L)); roles.append("reg")
                elif c == "Y":
                    types.append(vec_reg(max(L - 1, 0))); roles.append("reg")
                elif c == "H":
                    types.append("X" if scalar else vec_reg(L)); roles.append("v")
                elif c == "W":
                    types.append(vec_rm(nbytes)); roles.append("rm")
                elif c == "E":
                    if nbytes == 1:
                        t = "R32M8"
                    elif nbytes == 2:
                        t = "R32M16"
                    else:
                        t = "RM64" if w else "RM32"
                    types.append(t); roles.append("rm")
                elif c == "G":
                    types.append("R64" if w else "R32"); roles.append("reg")
                elif c == "K":
                    types.append("K"); roles.append("reg")
                elif c == "k":
                    types.append("K"); roles.append("rm")
                elif c == "I":
                    types.append("I8"); roles.append("i")
            n8 = elem if flags & T.EV_NELEM else nbytes
            if flags & T.EV_MOVS:                # vmovss/vmovsd: vvvv only between registers
                wi = shape.index("W")
                hi = shape.index("H")
                mem_t = [t for i, t in enumerate(types) if i != hi]
                mem_t[mem_t.index(types[wi])] = {4: "M32", 8: "M64"}[nbytes]
                mem_r = [r for i, r in enumerate(roles) if i != hi]
                eform(name, mem_t, pfx, mp, opcode, modrm, mem_r, wf, L=L, n8=n8)
                reg_t = list(types)
                reg_t[wi] = "X"
                eform(name, reg_t, pfx, mp, opcode, modrm, roles, wf, L=L, n8=n8)
                continue
            eform(name, types, pfx, mp, opcode, modrm, roles, wf | bc, L=L, n8=n8,
                  prio=1 if (name, mapn) == ("vpextrw", 2) else 0)
            # predicate pseudo-ops: vpcmpltub, vcmpnle_uqps, ...
            if flags & (T.EV_PINT | T.EV_PFP):
                if flags & T.EV_PINT:
                    base, sfx = "vpcmp", name[5:]
                    preds = [(i, p) for i, p in enumerate(EV_PRED_INT) if p]
                    if not sfx.startswith("u"):
                        preds = [(i, p) for i, p in preds if p != "eq"]   # vpcmpeqb is 0F 74
                else:
                    base, sfx = "vcmp", name[4:]
                    preds = list(enumerate(PRED32))
                for imm, p in preds:
                    eform(base + p + sfx, types[:-1], pfx, mp, opcode, modrm, roles[:-1],
                          wf | bc | F_FIXIMM, imm, L=L, n8=n8)
            # rounding control / suppress-all-exceptions: registers only, full length
            if flags & (T.EV_ER | T.EV_SAE) and (scalar or L == 2) and "W" in shape:
                rt = list(types)
                rt[shape.index("W")] = "X" if scalar else "Z"
                extra = "RC" if flags & T.EV_ER else "SAE"
                rr = list(roles)
                if rr[-1] == "i":                # the imm8 stays last
                    rt.insert(len(rt) - 1, extra); rr.insert(len(rr) - 1, "-")
                else:
                    rt.append(extra); rr.append("-")
                if len(rt) <= 4:
                    eform(name, rt, pfx, mp, opcode, modrm, rr, wf, L=L, n8=n8)
                if flags & T.EV_ER and not flags & T.EV_SAE:
                    pass

evex_forms()

# ---- gathers and scatters (vector-indexed memory) ----
# AVX2 (VEX): dest, address, mask vector.  AVX-512 (EVEX): dest{k}, address
# for gathers, address{k}, source for scatters; disp8*N scales by one element.
# d/q = index elements of 4/8 bytes; ps/dd = 4-byte data, pd/dq/qq = 8-byte.
GATHERS = [   # name, opcode, W, (VEX L0 dest, L0 addr, L1 dest, L1 addr), (EVEX dest per L0/L1/L2, addr per L)
    ("vgatherdps", 0x92, 0, ("X", "VMX", "Y", "VMY"), (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vgatherdpd", 0x92, 1, ("X", "VMX", "Y", "VMX"), (("X", "VMX"), ("Y", "VMX"), ("Z", "VMY"))),
    ("vgatherqps", 0x93, 0, ("X", "VMX", "X", "VMY"), (("X", "VMX"), ("X", "VMY"), ("Y", "VMZ"))),
    ("vgatherqpd", 0x93, 1, ("X", "VMX", "Y", "VMY"), (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vpgatherdd", 0x90, 0, ("X", "VMX", "Y", "VMY"), (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vpgatherdq", 0x90, 1, ("X", "VMX", "Y", "VMX"), (("X", "VMX"), ("Y", "VMX"), ("Z", "VMY"))),
    ("vpgatherqd", 0x91, 0, ("X", "VMX", "X", "VMY"), (("X", "VMX"), ("X", "VMY"), ("Y", "VMZ"))),
    ("vpgatherqq", 0x91, 1, ("X", "VMX", "Y", "VMY"), (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
]
SCATTERS = [  # name, opcode, W, (source, address) per L0/L1/L2
    ("vscatterdps", 0xA2, 0, (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vscatterdpd", 0xA2, 1, (("X", "VMX"), ("Y", "VMX"), ("Z", "VMY"))),
    ("vscatterqps", 0xA3, 0, (("X", "VMX"), ("X", "VMY"), ("Y", "VMZ"))),
    ("vscatterqpd", 0xA3, 1, (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vpscatterdd", 0xA0, 0, (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
    ("vpscatterdq", 0xA0, 1, (("X", "VMX"), ("Y", "VMX"), ("Z", "VMY"))),
    ("vpscatterqd", 0xA1, 0, (("X", "VMX"), ("X", "VMY"), ("Y", "VMZ"))),
    ("vpscatterqq", 0xA1, 1, (("X", "VMX"), ("Y", "VMY"), ("Z", "VMZ"))),
]
for n, code, w, (d0, a0, d1, a1), ev in GATHERS:
    wf = F_W if w else 0
    vform(n, [d0, a0, d0], "66", "38", code, M_R, "reg rm v", wf, L=0)
    vform(n, [d1, a1, d1], "66", "38", code, M_R, "reg rm v", wf, L=1)
    for L, (d, a) in enumerate(ev):
        eform(n, [d, a], "66", "38", code, M_R, "reg rm", wf, L=L, n8=8 if w else 4)
for n, code, w, ev in SCATTERS:
    wf = F_W if w else 0
    for L, (d, a) in enumerate(ev):
        eform(n, [a, d], "66", "38", code, M_R, "rm reg", wf, L=L, n8=8 if w else 4)

# ---- the VEX mask-register instructions (kmov, kand, kortest, ...) ----
def kop_forms():
    for m, code, pp, w, n, shape in T.kops:
        mp, pfx = EMAP[m], EPFX[pp]
        wf = F_W if w else 0
        if shape == 1:
            vform(n, "K K K", pfx, mp, code, M_R, "reg v rm", wf, L=1)
        elif shape == 2:
            vform(n, "K K", pfx, mp, code, M_R, "reg rm", wf)
            vform(n, ["K", {"b": "M8", "w": "M16", "d": "M32", "q": "M64"}[n[-1]]], pfx, mp, code,
                  M_R, "reg rm", wf)
        elif shape == 3:
            vform(n, [{"b": "M8", "w": "M16", "d": "M32", "q": "M64"}[n[-1]], "K"], pfx, mp, code,
                  M_R, "rm reg", wf)
        elif shape == 4:
            vform(n, ["K", "R64" if w else "R32"], pfx, mp, code, M_R, "reg rm", wf)
        elif shape == 5:
            vform(n, ["R64" if w else "R32", "K"], pfx, mp, code, M_R, "reg rm", wf)
        elif shape == 6:
            vform(n, "K K", pfx, mp, code, M_R, "reg rm", wf)
        elif shape == 7:
            vform(n, "K K I8", pfx, mp, code, M_R, "reg rm i", wf)

kop_forms()



# ============================================================================
# x87, from the shared opcode map
# ============================================================================
X87_MS = {2: "MS16", 4: "MS32", 8: "MS64", 10: "MS80", 0: "M"}
def x87_forms():
    sizes = {}
    for code, row in T.X87_MEM.items():
        for e in row:
            if e:
                sizes.setdefault(e[0], set()).add(e[1])
    for code, row in sorted(T.X87_MEM.items()):
        for r, e in enumerate(row):
            if not e:
                continue
            n, sz = e
            t = X87_MS[sz] if len(sizes[n]) > 1 or sz == 0 else {2: "M16", 4: "M32", 8: "M64", 10: "M80"}[sz]
            form(n, [t], "", "", code, r, "rm")
            if n.startswith("fn"):                  # fstsw/fstcw/fstenv/fsave: fwait first
                form("f" + n[2:], [t], "", "", code, r, "rm", F_WAIT)
    for code, row in sorted(T.X87_REG.items()):
        for r, e in enumerate(row):
            if not e:
                continue
            n, shape = e
            base = 0xC0 | (r << 3)
            if shape == 1:                          # st0, st(i)
                form(n, "ST0 ST", "", "", code, base, "- +")
                form(n, "ST", "", "", code, base, "+", prio=1)
            elif shape == 2:                        # st(i), st0
                form(n, "ST ST0", "", "", code, base, "+ -")
                if n.endswith("p"):
                    form(n, "ST", "", "", code, base, "+", prio=1)
                    form(n, [], "", "", code, base | 1, [], prio=2)
            else:                                   # st(i)
                form(n, "ST", "", "", code, base, "+")
                if n in ("fxch", "fcom", "fcomp", "fucom", "fucomp"):
                    form(n, [], "", "", code, base | 1, [], prio=2)
    for code, modrm, n, opnd in T.X87_FIX:
        if opnd:
            form(n, "AX", "", "", code, modrm, "-")
            if n.startswith("fn"):
                form("f" + n[2:], "AX", "", "", code, modrm, "-", F_WAIT)
        else:
            form(n, [], "", "", code, modrm, [])
            if n.startswith("fn") and n != "fnop":
                form("f" + n[2:], [], "", "", code, modrm, [], F_WAIT)

x87_forms()

# ============================================================================
# output
# ============================================================================
def mnemonic_ids():
    ids = {}
    for m in re.finditer(r'mnc_ent\s+"([^"]+)",\s*\d+,\s*(\d+)', open(ISA, encoding="utf-8").read()):
        ids.setdefault(m.group(1), int(m.group(2)))
    return ids

def render():
    ids = mnemonic_ids()
    missing = sorted({f[0] for f in forms if f[0] not in ids})
    if missing:
        sys.exit("mnemonics missing from backend/isa/amd64.s: " + " ".join(missing))
    # group by mnemonic ID in first-seen order, then by priority (stable)
    order, by_id = [], {}
    for i, f in enumerate(forms):
        mid = ids[f[0]]
        if mid not in by_id:
            by_id[mid] = []
            order.append(mid)
        by_id[mid].append((f[10] == ENC_EVEX, f[9], i, f))
    out = [
        "; " + "=" * 76,
        "; GENERATED by scripts/gen_x86_enc.py - do not edit by hand.",
        "; AMD64 instruction forms for the table-driven encoder",
        "; (backend/encoder/dispatch.s). See the script for the layout.",
        "; " + "=" * 76,
        "",
        "bits 64",
        "",
        "[SECTION .rodata]",
        "",
        "global x86_enc_types",
        "global x86_enc_index",
        "global x86_enc_table",
        "",
        "; operand types: db rclass, special; dw rsize, msize; db fixreg, imm",
        "x86_enc_types:",
    ]
    for t in TYPES:
        name, rc, sp, rs, ms, fx, im = t
        out.append("    db %d, %d\n    dw %d, 0x%04x\n    db 0x%02x, %d     ; T_%s" % (rc, sp, rs, ms, fx, im, name))
    table, index = [], {}
    for mid in sorted(order):
        index[mid] = len(table) + 1
        for _, _, _, f in sorted(by_id[mid], key=lambda x: (x[0], x[1], x[2])):
            table.append((mid, f))
    maxid = max(index)
    out += ["", "; mnemonic ID -> first form + 1 (0 = none)", "x86_enc_index:"]
    for i in range(0, maxid + 1, 16):
        out.append("    dw " + ", ".join(str(index.get(j, 0)) for j in range(i, min(i + 16, maxid + 1))))
    out += ["", "global x86_enc_maxid", "x86_enc_maxid: dd %d        ; highest mnemonic ID in the index" % maxid, "",
            "; forms, 16 bytes each", "x86_enc_table:"]
    for mid, f in table:
        name, types, pfx, mp, opcode, modrm, roles, flags, fiximm, _, enc, L = f[:12]
        n8 = f[12] if len(f) > 12 else 1
        ts = (types + [0, 0, 0, 0])[:4]
        rl = 0
        for i, r in enumerate(roles):
            rl |= r << (3 * i)
        out.append("    dw %d\n    db %d, %d, %d, %d, 0x%02x, %d, 0x%02x, 0x%02x\n    dw 0x%04x\n"
                   "    db 0x%02x, %d, %d, 0x%02x      ; %s %s"
                   % (mid, ts[0], ts[1], ts[2], ts[3], pfx | enc << 4, mp, opcode, modrm, rl, flags, L, n8, fiximm,
                      name, " ".join(TYPES[t][0] for t in types)))
    out.append("    dw 0")
    return "\n".join(out) + "\n", len(table)

def main():
    text, n = render()
    if "--check" in sys.argv:
        cur = open(DST, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(DST) else ""
        if cur != text:
            sys.exit("backend/encoder/tables/opcode.s is out of date; run scripts/gen_x86_enc.py")
        return
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("%d forms" % n)

if __name__ == "__main__":
    main()
