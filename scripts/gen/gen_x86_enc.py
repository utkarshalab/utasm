#!/usr/bin/env python3
"""
gen_x86_enc.py - regenerate src/encode/x86/gen/opcode.s

The table-driven part of the AMD64 encoder (src/encode/x86/dispatch.s)
reads the instruction forms written here. Most of them are derived from the
opcode map in scripts/gen/gen_x86_tables.py, the one the disassembler decodes
with, so the assembler and the disassembler agree on every encoding; the
rest (x87, system and other integer instructions) are listed below.

  x86_enc_types   operand types: what an operand may be (8 bytes each)
  x86_enc_index   mnemonic ID -> first form + 1 (0 = not in the table)
  x86_enc_table   the forms, 16 bytes each, grouped by mnemonic, in the
                  order they are tried (the first one that matches wins)

Form layout:
  +0  dw  mnemonic ID (src/encode/x86/isa.s)
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
  +15 db  immediate byte appended after the operands (with F_FIXIMM); else
          a legacy form's mode needs (NASM's list): bits 0-1 operand size
          (1 o16, 2 o32: 66 in the other modes), 2-3 address size (1 a16,
          2 a32, 3 a64: 67 in the other modes), 4 not in 64-bit mode, 5 only
          there, 6 a REP prefix of its own (F3, unless one is written)

    python3 scripts/gen/gen_x86_enc.py           regenerate
    python3 scripts/gen/gen_x86_enc.py --check   fail if out of date
"""

import os, re, sys

sys.dont_write_bytecode = True                   # no __pycache__ in scripts/
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))   # scripts/gen/ -> the repository
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_x86_tables as T                       # the shared opcode map

DST = os.path.join(ROOT, "src", "encode", "x86", "gen", "opcode.s")
ISA = os.path.join(ROOT, "src", "encode", "x86", "isa.s")

# ---------------------------------------------------------------- operand types
# rclass: 0 register not allowed, else C_*; special: 1 size 16/32/64 sets the
# operand size, 2 size 32/64 does, 3 immediate; rsize/msize in bits
# (msize 0xFFFF = no memory, 0 = any size); fixreg: required register number;
# imm: immediate kind.
C_GPR, C_XMM, C_YMM, C_ZMM, C_K, C_ST, C_MM, C_CR, C_DR, C_SEG, C_RC, C_SAE, C_TMM, C_BND = range(1, 15)
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
    ("K", C_K, 0, 0, NOMEM, 0xFF, 0), ("KM8", C_K, 0, 8, 8, 0xFF, 0), ("KM16", C_K, 0, 16, 16, 0xFF, 0),
    ("KM32", C_K, 0, 32, 32, 0xFF, 0), ("KM64", C_K, 0, 64, 64, 0xFF, 0),
    ("ST", C_ST, 0, 0, NOMEM, 0xFF, 0), ("ST0", C_ST, 0, 0, NOMEM, 0, 0),
    ("STTO", C_ST, 5, 0, NOMEM, 0xFF, 0),     # "fadd to st1" (NASM's fpureg|to)
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
    # NASM's instruction list (nasm_forms below): an xmm register or memory
    # of any size, AMX tiles, MPX bounds, and fixed-width operands that set
    # the operand size (o16 / o32 / o64 in its encodings)
    ("XM", C_XMM, 0, 128, 0, 0xFF, 0),
    # a register of one width or memory of another (insns.dat's ymmrm128 ...)
    ("YM16", C_YMM, 0, 256, 16, 0xFF, 0), ("YM128", C_YMM, 0, 256, 128, 0xFF, 0),
    ("ZM16", C_ZMM, 0, 512, 16, 0xFF, 0), ("ZM128", C_ZMM, 0, 512, 128, 0xFF, 0),
    ("XM256", C_XMM, 0, 128, 256, 0xFF, 0),
    ("TMM", C_TMM, 0, 0, NOMEM, 0xFF, 0), ("BND", C_BND, 0, 0, NOMEM, 0xFF, 0),
    ("BNDM64", C_BND, 0, 0, 64, 0xFF, 0), ("BNDM128", C_BND, 0, 0, 128, 0xFF, 0),
    ("R16V", C_GPR, 1, 16, NOMEM, 0xFF, 0), ("R32V", C_GPR, 1, 32, NOMEM, 0xFF, 0),
    ("R64V", C_GPR, 1, 64, NOMEM, 0xFF, 0), ("RM32V", C_GPR, 1, 32, 32, 0xFF, 0),
    ("RM64V", C_GPR, 1, 64, 64, 0xFF, 0),
    ("M16V", 0, 1, 16, 16, 0xFF, 0), ("M32V", 0, 1, 32, 32, 0xFF, 0), ("M64V", 0, 1, 64, 64, 0xFF, 0),
    ("ECX", C_GPR, 0, 32, NOMEM, 1, 0), ("RCX", C_GPR, 0, 64, NOMEM, 1, 0),
    ("EDX", C_GPR, 0, 32, NOMEM, 2, 0), ("CX", C_GPR, 0, 16, NOMEM, 1, 0),
    ("ES", C_SEG, 0, 0, NOMEM, 0, 0), ("CS", C_SEG, 0, 0, NOMEM, 1, 0),
    # a mask register of a written size: NASM's kmov / kand ... with no
    # suffix pick the instruction by it ("kmov byte k1, k2" is kmovb)
    ("K8", C_K, 0, 8, NOMEM, 0xFF, 0), ("K16", C_K, 0, 16, NOMEM, 0xFF, 0),
    ("K32", C_K, 0, 32, NOMEM, 0xFF, 0), ("K64", C_K, 0, 64, NOMEM, 0xFF, 0),
    # one tile register each (tilezero: ModRM 11 tmm 000)
    *[("TMM%d" % n, C_TMM, 0, 0, NOMEM, n, 0) for n in range(8)],
    ("SS", C_SEG, 0, 0, NOMEM, 2, 0), ("DS", C_SEG, 0, 0, NOMEM, 3, 0),
    # NASM's rm8 with "nohi" (pinsrb): the byte register encoded as its
    # 32-bit one - no REX for sil / dil, no ah .. bh
    ("RM8N", C_GPR, 6, 8, 8, 0xFF, 0),
]
TY = {t[0]: i for i, t in enumerate(TYPES)}

# roles
R_NONE, R_REG, R_RM, R_VVVV, R_PLUS, R_IMM, R_IS4 = range(7)
# flags
F_W, F_OSZ, F_D64, F_WAIT, F_FIXIMM, F_BCST = 1, 2, 4, 8, 16, 32
F_V0 = 64      # VEX/EVEX: vvvv is operand 0's register (NASM's "vaddps xmm1, xmm2")
F_B16 = 128    # EVEX: a broadcast's elements are 16-bit (else 32, or 64 with W)
PFXN = {"": 0, "np": 0, "66": 1, "F3": 2, "F2": 3}
# maps: VEX/EVEX mmm + 1 (0F 38 = 3, EVEX map 5 = 6), XOP mmmmm + 1
MAPN = {"": 1, "0f": 2, "38": 3, "3a": 4, "map5": 6, "map6": 7, "xop8": 9, "xop9": 10, "xopa": 11}
M_DIGIT = lambda d: d
M_R, M_NONE = 8, 9

forms = []     # (name, types, pfx, map, opcode, modrm, roles, flags, fiximm, prio, enc, L)
ENC_LEGACY, ENC_VEX, ENC_EVEX, ENC_XOP = 0, 1, 2, 3

# objdump's names for undocumented x87 aliases: no assembler accepts them
SKIP = {"fcom2", "fcomp3", "fcomp5", "ffreep", "fstp1", "fstp8", "fstp9", "fxch4", "fxch7"}

def form(name, types, pfx, mp, opcode, modrm, roles, flags=0, fiximm=0, prio=0, enc=ENC_LEGACY, L=0):
    if name in SKIP and prio != 50:              # (NASM's list, NASM_PRIO, has ffreep)
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
            if name == "maskmovq":                  # registers only: NASM's line
                continue
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
            elif f in ("VQ", "PW"):                 # MMX <-> SSE: the disassembler's
                continue                            # (NASM's lines encode them)
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
# (movnti: the shared map's M R32 / M R64 - NASM's "np", no 66 for a 32-bit
# register in bits 16: 66 0F C3 is not movnti)
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
    ("vmfunc", "", "0f", 0x01, 0xD4, 0),
]
for n, p, mp, op, m, fl in FIXED:
    form(n, [], p, mp, op, m, [], fl)

# VMX: vmread r/m, r and vmwrite r, r/m take the mode's width (r64 in
# 64-bit mode, no REX.W); the VMCS pointer instructions a memory operand
form("vmread", "RM64 R64", "", "0f", 0x78, M_R, "rm reg")
form("vmread", "RM32 R32", "", "0f", 0x78, M_R, "rm reg")
form("vmwrite", "R64 RM64", "", "0f", 0x79, M_R, "reg rm")
form("vmwrite", "R32 RM32", "", "0f", 0x79, M_R, "reg rm")
for n, p, r in (("vmptrld", "", 6), ("vmptrst", "", 7), ("vmclear", "66", 6), ("vmxon", "F3", 6)):
    form(n, "M", p, "0f", 0xC7, r, "rm")

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
# VMX / PCID TLB invalidation: a register (r64 in 64-bit mode) and a
# 128-bit descriptor in memory; invpcid r64 without REX.W (Intel, NASM 3)
for n, op in (("invept", 0x80), ("invvpid", 0x81)):
    form(n, "R64 M", "66", "38", op, M_R, "reg rm")
    form(n, "R32 M", "66", "38", op, M_R, "reg rm")
form("invpcid", "R64 M", "66", "38", 0x82, M_R, "reg rm")
form("invpcid", "R32 M", "66", "38", 0x82, M_R, "reg rm")
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
            if (tab, key) in T.DIS_ONLY:                 # (the disassembler's alone)
                continue
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

# ---- AVX-512 broadcasts from a general register (vpbroadcastb zmm1, al):
# EVEX 7A / 7B / 7C, the register in r/m; NASM takes the byte and word
# ones from a register of that size or wider ----
for n, code, w, srcs in (("vpbroadcastb", 0x7A, 0, ("R8", "R16", "R32")),
                         ("vpbroadcastw", 0x7B, 0, ("R16", "R32")),
                         ("vpbroadcastd", 0x7C, 0, ("R32",)),
                         ("vpbroadcastq", 0x7C, 1, ("R64",))):
    for L, d in enumerate(("X", "Y", "Z")):
        for s in srcs:
            eform(n, [d, s], "66", "38", code, M_R, "reg rm", F_W if w else 0, L=L)

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
        if opnd == 1:                               # fnstsw ax (2 / 3: the 8087's / 287's, none)
            form(n, "AX", "", "", code, modrm, "-")
            if n.startswith("fn"):
                form("f" + n[2:], "AX", "", "", code, modrm, "-", F_WAIT)
        else:
            form(n, [], "", "", code, modrm, [])
            if n.startswith("fn") and n != "fnop":
                form("f" + n[2:], [], "", "", code, modrm, [], F_WAIT)

x87_forms()

# ============================================================================
# NASM's instruction list: the forms the opcode map above does not give
# ============================================================================
# third_party/nasm/insns.dat is NASM's own instruction table (x86/insns.dat of
# NASM 2.16.03, under NASM's 2-clause BSD licence, its notice kept at the
# top). Its 64-bit forms are read here and placed after the forms above
# (prio NASM_PRIO), so they only take operands none of those fit: the
# instructions the opcode map does not have (AMX, AVX-512 FP16, XOP, FMA4,
# the VCMP predicate aliases ...) and the spellings it does not (NASM's
# "vaddps xmm1, xmm2" for "vaddps xmm1, xmm1, xmm2"). Mnemonics new to
# src/encode/x86/isa.s go in its generated block (isa_block below).
INSNS = os.path.join(ROOT, "third_party", "nasm", "insns.dat")
# NASM 3.01's lines for the instructions 2.16.03's has not (AVX10.2, the
# AMX additions, AVX-VNNI-INT16, MOVRS ...): read after it, the same way
INSNS3 = os.path.join(ROOT, "third_party", "nasm", "insns3.dat")
NASM_PRIO = 50

# NASM's AVX512-FP16 FMA names are off from Intel's: its VFMADD132PH is
# opcode 9C, Intel's VFNMADD132PH (a negated result, silently); its
# VPMADD132PH is 98, Intel's VFMADD132PH; the scalar ones are all VP...SH.
# Taken by Intel's names (the opcode decides), as objdump reads them.
NAME_FIX = {}
for n in ("132", "213", "231"):
    NAME_FIX.update({"vpmadd%sph" % n: "vfmadd%sph" % n, "vfmadd%sph" % n: "vfnmadd%sph" % n,
                     "vpmsub%sph" % n: "vfmsub%sph" % n, "vfmsub%sph" % n: "vfnmsub%sph" % n,
                     "vpmadd%ssh" % n: "vfmadd%ssh" % n, "vpnmadd%ssh" % n: "vfnmadd%ssh" % n,
                     "vpmsub%ssh" % n: "vfmsub%ssh" % n, "vpnmsub%ssh" % n: "vfnmsub%ssh" % n})
NAME_FIX["vfcmulcpch"] = "vfcmulcph"          # (NASM's spelling)
# NASM's lines that are wrong, replaced by EXTRA_INSNS: vcvtqq2ph /
# vcvtuqq2ph write xmm whatever the source (NASM: ymm, zmm), vp2intersectd
# takes m256 / m512 (NASM: m128) and a mask pair
NASM_WRONG = {"vcvtqq2ph", "vcvtuqq2ph", "vp2intersectd",
              # (by encfuzz.py --objdump: objdump reads them as another
              # instruction, or as invalid)
              "vgetmantph", "vgetmantsh", "vgetexpsh", "vreducesh", "vrcpph", "vrcpsh",
              "vrsqrtph", "vrsqrtsh", "vcvtneps2bf16",
              # NASM's misspellings, a source missing: vmaxph, vrndscaleph ... are below
              "vgetmaxph", "vgetmaxsh", "vgetminph", "vgetminsh", "vendscaleph",
              "vendscalesh", "vfmulcpch",
              # narrowing conversions with the source's width (xmm for ymm)
              "vcvtdq2ph", "vcvtudq2ph", "vcvtpd2ph",
              # memory narrower than the vector (by src/tools/disasm's generated
              # tables read back against objdump): vcvtph2udq's half of what
              # it is, vdpbf16ps / vsm4key4 / vsm4rnds4's 128 bits at 256 / 512
              "vcvtph2udq", "vdpbf16ps", "vsm4key4", "vsm4rnds4",
              # vaddph / vcmpph's memory 16 bits (its broadcast's element):
              # "zword [rax]" refused, "word [rax]" taken, {1toN} refused
              "vaddph", "vcmpph",
              # retw imm: no o16 (66) - NASM 3's has it
              "retw",
              # vmovw: NASM's takes a mask (#UD: it has none) and no r32
              # (Intel's and GNU's "vmovw xmm1, eax"); below without the
              # mask, with r32 and NASM's r16
              "vmovw",
              # kandn with a size written: 2.16.03's four lines have the
              # encodings of the others ("kandn byte" was kandnq, "word"
              # kandnd ...; NASM 3 has them right) - below as KAND's
              "kandn"}
# (v4fmaddss / v4fnmaddss: NASM's zmm spelling kept, Intel's xmm one added below)
# NASM's VCVTPS2PH of map 5 (no imm8) is Intel's VCVTPS2PHX: NASM's lines are
# wrong in their destinations, those below are right; the F16C / AVX-512
# VCVTPS2PH (with an imm8) stays
NASM_WRONG_MAP5 = {"vcvtps2ph"}
# conditions, as NASM spells them in cc mnemonics, and their codes
CONDITIONS = [("o", 0), ("no", 1), ("b", 2), ("c", 2), ("nae", 2), ("ae", 3), ("nb", 3), ("nc", 3),
              ("e", 4), ("z", 4), ("ne", 5), ("nz", 5), ("be", 6), ("na", 6), ("a", 7), ("nbe", 7),
              ("s", 8), ("ns", 9), ("p", 10), ("pe", 10), ("np", 11), ("po", 11), ("l", 12),
              ("nge", 12), ("ge", 13), ("nl", 13), ("le", 14), ("ng", 14), ("g", 15), ("nle", 15)]
# forms NASM has wrong or not at all, from Intel's manual, in insns.dat's
# notation
EXTRA_INSNS = '''
KANDN		kreg8,kreg,kreg			[rvm: vex.nds.l1.66.0f.w0 42 /r ]	FUTURE,ND,SM
KANDN		kreg16,kreg,kreg		[rvm: vex.nds.l1.0f.w0 42 /r ]	FUTURE,ND,SM
KANDN		kreg32,kreg,kreg		[rvm: vex.nds.l1.66.0f.w1 42 /r ]	FUTURE,ND,SM
KANDN		kreg64,kreg,kreg		[rvm: vex.nds.l1.0f.w1 42 /r ]	FUTURE,ND,SM
VMOVW		xmmreg,rm16			[rm:t1s: evex.128.66.map5.wig 6e /r]	AVX512FP16,FUTURE
VMOVW		xmmreg,reg32			[rm:t1s: evex.128.66.map5.wig 6e /r]	AVX512FP16,FUTURE
VMOVW		rm16,xmmreg			[mr:t1s: evex.128.66.map5.wig 7e /r]	AVX512FP16,FUTURE
VMOVW		reg32,xmmreg			[mr:t1s: evex.128.66.map5.wig 7e /r]	AVX512FP16,FUTURE
AOR	   	mem32,reg32				[mr:	norexw f2 0f 38 fc /r	]	RAOINT,FUTURE,SD
AOR	   	mem64,reg64				[mr:	o64 f2 0f 38 fc /r	]	RAOINT,FUTURE,SQ,LONG
PMULHRW		mmxreg,mmxrm			[rm:	o64nw 0f 0f /r b7]			PENT,3DNOW,SQ
VP4DPWSSDS		zmmreg|mask|z,zmmreg|rs4,mem		[rvm:m128:evex.dds.512.f2.0f38.w0 53 /r]	AVX5124VNNIW,FUTURE,SO
VP4DPWSSD		zmmreg|mask|z,zmmreg|rs4,mem		[rvm:m128:evex.dds.512.f2.0f38.w0 52 /r]	AVX5124VNNIW,FUTURE,SO
VCVTQQ2PH	xmmreg|mask|z,xmmrm128|b64	[rm:fv: evex.128.np.map5.w1 5b /r]	AVX512FP16
VCVTQQ2PH	xmmreg|mask|z,ymmrm256|b64	[rm:fv: evex.256.np.map5.w1 5b /r]	AVX512FP16
VCVTQQ2PH	xmmreg|mask|z,zmmrm512|b64|er	[rm:fv: evex.512.np.map5.w1 5b /r]	AVX512FP16
VCVTUQQ2PH	xmmreg|mask|z,xmmrm128|b64	[rm:fv: evex.128.f2.map5.w1 7a /r]	AVX512FP16
VCVTUQQ2PH	xmmreg|mask|z,ymmrm256|b64	[rm:fv: evex.256.f2.map5.w1 7a /r]	AVX512FP16
VCVTUQQ2PH	xmmreg|mask|z,zmmrm512|b64|er	[rm:fv: evex.512.f2.map5.w1 7a /r]	AVX512FP16
VP2INTERSECTD	kreg,xmmreg,xmmrm128|b32	[rvm:fv: evex.nds.128.f2.0f38.w0 68 /r]	AVX512VP2INTERSECT
VP2INTERSECTD	kreg,ymmreg,ymmrm256|b32	[rvm:fv: evex.nds.256.f2.0f38.w0 68 /r]	AVX512VP2INTERSECT
VP2INTERSECTD	kreg,zmmreg,zmmrm512|b32	[rvm:fv: evex.nds.512.f2.0f38.w0 68 /r]	AVX512VP2INTERSECT
VP2INTERSECTQ	kreg,xmmreg,xmmrm128|b64	[rvm:fv: evex.nds.128.f2.0f38.w1 68 /r]	AVX512VP2INTERSECT
VP2INTERSECTQ	kreg,ymmreg,ymmrm256|b64	[rvm:fv: evex.nds.256.f2.0f38.w1 68 /r]	AVX512VP2INTERSECT
VP2INTERSECTQ	kreg,zmmreg,zmmrm512|b64	[rvm:fv: evex.nds.512.f2.0f38.w1 68 /r]	AVX512VP2INTERSECT
VFMULCPH	xmmreg|mask|z,xmmreg*,xmmrm128|b32	[rvm:fv: evex.nds.128.f3.map6.w0 d6 /r]	AVX512FP16
VFMULCPH	ymmreg|mask|z,ymmreg*,ymmrm256|b32	[rvm:fv: evex.nds.256.f3.map6.w0 d6 /r]	AVX512FP16
VFMULCPH	zmmreg|mask|z,zmmreg*,zmmrm512|b32|er	[rvm:fv: evex.nds.512.f3.map6.w0 d6 /r]	AVX512FP16
VMAXPH	xmmreg|mask|z,xmmreg*,xmmrm128|b16	[rvm:fv: evex.nds.128.np.map5.w0 5f /r]	AVX512FP16
VMAXPH	ymmreg|mask|z,ymmreg*,ymmrm256|b16	[rvm:fv: evex.nds.256.np.map5.w0 5f /r]	AVX512FP16
VMAXPH	zmmreg|mask|z,zmmreg*,zmmrm512|b16|sae	[rvm:fv: evex.nds.512.np.map5.w0 5f /r]	AVX512FP16
VMINPH	xmmreg|mask|z,xmmreg*,xmmrm128|b16	[rvm:fv: evex.nds.128.np.map5.w0 5d /r]	AVX512FP16
VMINPH	ymmreg|mask|z,ymmreg*,ymmrm256|b16	[rvm:fv: evex.nds.256.np.map5.w0 5d /r]	AVX512FP16
VMINPH	zmmreg|mask|z,zmmreg*,zmmrm512|b16|sae	[rvm:fv: evex.nds.512.np.map5.w0 5d /r]	AVX512FP16
VMAXSH	xmmreg|mask|z,xmmreg*,xmmrm16|sae	[rvm:t1s: evex.nds.lig.f3.map5.w0 5f /r]	AVX512FP16
VMINSH	xmmreg|mask|z,xmmreg*,xmmrm16|sae	[rvm:t1s: evex.nds.lig.f3.map5.w0 5d /r]	AVX512FP16
VRNDSCALEPH	xmmreg|mask|z,xmmrm128|b16,imm8	[rmi:fv: evex.128.np.0f3a.w0 08 /r ib]	AVX512FP16
VRNDSCALEPH	ymmreg|mask|z,ymmrm256|b16,imm8	[rmi:fv: evex.256.np.0f3a.w0 08 /r ib]	AVX512FP16
VRNDSCALEPH	zmmreg|mask|z,zmmrm512|b16|sae,imm8	[rmi:fv: evex.512.np.0f3a.w0 08 /r ib]	AVX512FP16
VRNDSCALESH	xmmreg|mask|z,xmmreg*,xmmrm16|sae,imm8	[rvmi:t1s: evex.nds.lig.np.0f3a.w0 0a /r ib]	AVX512FP16
VCVTPS2PHX	xmmreg|mask|z,xmmrm128|b32	[rm:fv: evex.128.66.map5.w0 1d /r]	AVX512FP16
VCVTPS2PHX	xmmreg|mask|z,ymmrm256|b32	[rm:fv: evex.256.66.map5.w0 1d /r]	AVX512FP16
VCVTPS2PHX	ymmreg|mask|z,zmmrm512|b32|er	[rm:fv: evex.512.66.map5.w0 1d /r]	AVX512FP16
VCVTNEPS2BF16	xmmreg|mask|z,xmmrm128|b32	[rm:fv: evex.128.f3.0f38.w0 72 /r]	AVX512BF16
VCVTNEPS2BF16	xmmreg|mask|z,ymmrm256|b32	[rm:fv: evex.256.f3.0f38.w0 72 /r]	AVX512BF16
VCVTNEPS2BF16	ymmreg|mask|z,zmmrm512|b32	[rm:fv: evex.512.f3.0f38.w0 72 /r]	AVX512BF16
VCVTNEPS2BF16	xmmreg,xmmrm128	[rm: vex.128.f3.0f38.w0 72 /r]	AVXNECONVERT,LATEVEX
VCVTNEPS2BF16	xmmreg,ymmrm256	[rm: vex.256.f3.0f38.w0 72 /r]	AVXNECONVERT,LATEVEX
VGETMANTPH	xmmreg|mask|z,xmmrm128|b16,imm8	[rmi:fv: evex.128.np.0f3a.w0 26 /r ib]	AVX512FP16
VGETMANTPH	ymmreg|mask|z,ymmrm256|b16,imm8	[rmi:fv: evex.256.np.0f3a.w0 26 /r ib]	AVX512FP16
VGETMANTPH	zmmreg|mask|z,zmmrm512|b16|sae,imm8	[rmi:fv: evex.512.np.0f3a.w0 26 /r ib]	AVX512FP16
VGETMANTSH	xmmreg|mask|z,xmmreg*,xmmrm16|sae,imm8	[rvmi:t1s: evex.nds.lig.np.0f3a.w0 27 /r ib]	AVX512FP16
VGETEXPSH	xmmreg|mask|z,xmmreg*,xmmrm16|sae	[rvm:t1s: evex.nds.lig.66.map6.w0 43 /r]	AVX512FP16
VREDUCESH	xmmreg|mask|z,xmmreg*,xmmrm16|sae,imm8	[rvmi:t1s: evex.nds.lig.np.0f3a.w0 57 /r ib]	AVX512FP16
VRCPPH	xmmreg|mask|z,xmmrm128|b16	[rm:fv: evex.128.66.map6.w0 4c /r]	AVX512FP16
VRCPPH	ymmreg|mask|z,ymmrm256|b16	[rm:fv: evex.256.66.map6.w0 4c /r]	AVX512FP16
VRCPPH	zmmreg|mask|z,zmmrm512|b16	[rm:fv: evex.512.66.map6.w0 4c /r]	AVX512FP16
VRCPSH	xmmreg|mask|z,xmmreg*,xmmrm16	[rvm:t1s: evex.nds.lig.66.map6.w0 4d /r]	AVX512FP16
VRSQRTPH	xmmreg|mask|z,xmmrm128|b16	[rm:fv: evex.128.66.map6.w0 4e /r]	AVX512FP16
VRSQRTPH	ymmreg|mask|z,ymmrm256|b16	[rm:fv: evex.256.66.map6.w0 4e /r]	AVX512FP16
VRSQRTPH	zmmreg|mask|z,zmmrm512|b16	[rm:fv: evex.512.66.map6.w0 4e /r]	AVX512FP16
VRSQRTSH	xmmreg|mask|z,xmmreg*,xmmrm16	[rvm:t1s: evex.nds.lig.66.map6.w0 4f /r]	AVX512FP16
VCVTDQ2PH	xmmreg|mask|z,xmmrm128|b32	[rm:fv: evex.128.np.map5.w0 5b /r]	AVX512FP16
VCVTDQ2PH	xmmreg|mask|z,ymmrm256|b32	[rm:fv: evex.256.np.map5.w0 5b /r]	AVX512FP16
VCVTDQ2PH	ymmreg|mask|z,zmmrm512|b32|er	[rm:fv: evex.512.np.map5.w0 5b /r]	AVX512FP16
VCVTUDQ2PH	xmmreg|mask|z,xmmrm128|b32	[rm:fv: evex.128.f2.map5.w0 7a /r]	AVX512FP16
VCVTUDQ2PH	xmmreg|mask|z,ymmrm256|b32	[rm:fv: evex.256.f2.map5.w0 7a /r]	AVX512FP16
VCVTUDQ2PH	ymmreg|mask|z,zmmrm512|b32|er	[rm:fv: evex.512.f2.map5.w0 7a /r]	AVX512FP16
VCVTPD2PH	xmmreg|mask|z,xmmrm128|b64	[rm:fv: evex.128.66.map5.w1 5a /r]	AVX512FP16
VCVTPD2PH	xmmreg|mask|z,ymmrm256|b64	[rm:fv: evex.256.66.map5.w1 5a /r]	AVX512FP16
VCVTPD2PH	xmmreg|mask|z,zmmrm512|b64|er	[rm:fv: evex.512.66.map5.w1 5a /r]	AVX512FP16
V4FMADDSS	xmmreg|mask|z,xmmreg|rs4,mem128	[rvm:m128:evex.dds.lig.f2.0f38.w0 9b /r]	AVX5124FMAPS
RETW	void	[	o16 c3]	8086,BND
RETW	imm	[i:	o16 c2 iw]	8086,SW,BND
VADDPH	xmmreg|mask|z,xmmreg*,xmmrm128|b16	[rvm:fv: evex.nds.128.np.map5.w0 58 /r]	AVX512FP16,AVX512VL,FUTURE
VADDPH	ymmreg|mask|z,ymmreg*,ymmrm256|b16	[rvm:fv: evex.nds.256.np.map5.w0 58 /r]	AVX512FP16,AVX512VL,FUTURE
VADDPH	zmmreg|mask|z,zmmreg*,zmmrm512|b16|er	[rvm:fv: evex.nds.512.np.map5.w0 58 /r]	AVX512FP16,FUTURE
VCMPPH	kreg|mask,xmmreg*,xmmrm128|b16,imm8	[rvmi:fv: evex.nds.128.np.0f3a.w0 c2 /r ib]	AVX512FP16,AVX512VL,FUTURE
VCMPPH	kreg|mask,ymmreg*,ymmrm256|b16,imm8	[rvmi:fv: evex.nds.256.np.0f3a.w0 c2 /r ib]	AVX512FP16,AVX512VL,FUTURE
VCMPPH	kreg|mask,zmmreg*,zmmrm512|b16|sae,imm8	[rvmi:fv: evex.nds.512.np.0f3a.w0 c2 /r ib]	AVX512FP16,FUTURE
VCVTPH2UDQ	xmmreg|mask|z,xmmrm64|b16	[rm:hv: evex.128.map5.w0 79 /r]	AVX512FP16,AVX512VL,FUTURE
VCVTPH2UDQ	ymmreg|mask|z,xmmrm128|b16	[rm:hv: evex.256.map5.w0 79 /r]	AVX512FP16,AVX512VL,FUTURE
VCVTPH2UDQ	zmmreg|mask|z,ymmrm256|b16|er	[rm:hv: evex.512.map5.w0 79 /r]	AVX512FP16,FUTURE
VDPBF16PS	xmmreg|mask|z,xmmreg*,xmmrm128|b32	[rvm:fv: evex.128.f3.0f38.w0 52 /r]	AVX512BF16,FUTURE
VDPBF16PS	ymmreg|mask|z,ymmreg*,ymmrm256|b32	[rvm:fv: evex.256.f3.0f38.w0 52 /r]	AVX512BF16,FUTURE
VDPBF16PS	zmmreg|mask|z,zmmreg*,zmmrm512|b32	[rvm:fv: evex.512.f3.0f38.w0 52 /r]	AVX512BF16,FUTURE
VSM4KEY4	xmmreg,xmmreg,xmmrm128	[rvm: vex.128.f3.0f38.w0 da /r]	SM4,FUTURE
VSM4KEY4	ymmreg,ymmreg,ymmrm256	[rvm: vex.256.f3.0f38.w0 da /r]	SM4,FUTURE
VSM4RNDS4	xmmreg,xmmreg,xmmrm128	[rvm: vex.128.f2.0f38.w0 da /r]	SM4,FUTURE
VSM4RNDS4	ymmreg,ymmreg,ymmrm256	[rvm: vex.256.f2.0f38.w0 da /r]	SM4,FUTURE
INVLPGB	void	[	np 0f 01 fe]	AMD,PRIV
INVLPGB	reg_rax,reg_ecx,reg_edx	[---:	a64 np 0f 01 fe]	AMD,PRIV,ND,LONG
INVLPGB	reg_eax,reg_ecx,reg_edx	[---:	a32 np 0f 01 fe]	AMD,PRIV,ND
TLBSYNC	void	[	np 0f 01 ff]	AMD,PRIV
RDPRU	void	[	np 0f 01 fd]	AMD
MCOMMIT	void	[	f3 0f 01 fa]	AMD
PSMASH	void	[	f3 0f 01 ff]	AMD,PRIV
PSMASH	reg_rax	[-:	a64 f3 0f 01 ff]	AMD,PRIV,ND,LONG
PSMASH	reg_eax	[-:	a32 f3 0f 01 ff]	AMD,PRIV,ND
RMPUPDATE	void	[	f2 0f 01 fe]	AMD,PRIV
RMPQUERY	void	[	f3 0f 01 fd]	AMD,PRIV
TDCALL	void	[	66 0f 01 cc]	TDX,PRIV
SEAMCALL	void	[	66 0f 01 cf]	TDX,PRIV
SEAMRET	void	[	66 0f 01 cd]	TDX,PRIV
SEAMOPS	void	[	66 0f 01 ce]	TDX,PRIV
UDB	void	[	d6]	X86_64,LONG
XSTORERNG	void	[	0f a7 c0]	PENT,CYRIX
V4FNMADDSS	xmmreg|mask|z,xmmreg|rs4,mem128	[rvm:m128:evex.dds.lig.f2.0f38.w0 ab /r]	AVX5124FMAPS
'''

NASM_TYPES = {
    "reg8": "R8", "reg16": "R16", "reg32": "R32", "reg64": "R64", "reg32na": "R32",
    "rm8": "RM8", "rm16": "RM16", "rm32": "RM32", "rm64": "RM64",
    "mem": "M", "mem8": "M8", "mem16": "M16", "mem32": "M32", "mem64": "M64", "mem80": "M80",
    "mem128": "M128", "mem256": "M256", "mem512": "M512",
    "xmmreg": "X", "ymmreg": "Y", "zmmreg": "Z", "xmmrm": "XM", "xmmrm8": "XM8",
    "xmmrm16": "XM16", "xmmrm32": "XM32", "xmmrm64": "XM64", "xmmrm128": "XM128",
    "ymmrm256": "YM256", "zmmrm512": "ZM512", "ymmrm16": "YM16", "ymmrm128": "YM128",
    "zmmrm16": "ZM16", "zmmrm128": "ZM128", "xmmrm256": "XM256",
    "mmxreg": "MM", "mmxrm": "MMM64", "mmxrm64": "MMM64",
    "kreg": "K", "kreg8": "K8", "kreg16": "K16", "kreg32": "K32", "kreg64": "K64",
    "krm8": "KM8", "krm16": "KM16", "krm32": "KM32", "krm64": "KM64",
    "tmmreg": "TMM", "bndreg": "BND",
    "xmem32": "VMX", "xmem64": "VMX", "ymem32": "VMY", "ymem64": "VMY",
    "zmem32": "VMZ", "zmem64": "VMZ",
    "reg_al": "AL", "reg_ax": "AX", "reg_eax": "EAX", "reg_rax": "RAX", "reg_cl": "CL",
    "reg_cx": "CX", "reg_ecx": "ECX", "reg_rcx": "RCX", "reg_dx": "DX", "reg_edx": "EDX",
    "reg_es": "ES", "reg_cs": "CS", "reg_ss": "SS", "reg_ds": "DS", "reg_fs": "FS", "reg_gs": "GS",
    "xmm0": "XMM0", "fpureg": "ST", "fpu0": "ST0", "reg_creg": "CR", "reg_dreg": "DR",
    "reg_sreg": "SREG", "unity": "ONE",
}
IMM_OPS = {"imm", "imm8", "imm16", "imm32", "imm64", "sbyteword", "sbytedword", "sbyteword16",
           "sbytedword32", "sbytedword64", "udword", "sdword"}
IMM_ENC = {"ib": "I8", "ib,u": "I8", "ib,s": "I8S", "iw": "I16", "id": "I32", "id,s": "IZ",
           "iwd": "IZ", "iq": "I64"}
# o16 / o32 / o64: an operand of that width sets the operand size (66, REX.W)
OSZ_WIDTH = {"o16": 16, "o32": 32, "o64": 64, "o64nw": 64}
OSZ_TYPES = {"R16": "R16V", "RM16": "RM16V", "R32": "R32V", "RM32": "RM32V", "R64": "R64V",
             "RM64": "RM64V", "M16": "M16V", "M32": "M32V", "M64": "M64V"}
# {rn-sae} / {sae}: the r/m operand is then a register
REG_ONLY = {"XM": "X", "XM8": "X", "XM16": "X", "XM32": "X", "XM64": "X", "XM128": "X",
            "XM256": "X", "YM16": "Y", "YM128": "Y", "YM256": "Y", "ZM16": "Z", "ZM128": "Z",
            "ZM512": "Z", "RM32": "R32", "RM64": "R64"}
VEX_FIELDS = {"128": ("L", 0), "l0": ("L", 0), "lz": ("L", 0), "lig": ("L", 0),
              "256": ("L", 1), "l1": ("L", 1), "512": ("L", 2),
              "66": ("pfx", "66"), "f2": ("pfx", "F2"), "f3": ("pfx", "F3"), "np": ("pfx", "np"),
              "p0": ("pfx", "np"), "p1": ("pfx", "66"),
              "0f": ("map", "0f"), "0f38": ("map", "38"), "0f3a": ("map", "3a"),
              "m1": ("map", "0f"), "m2": ("map", "38"), "m3": ("map", "3a"),
              "map5": ("map", "map5"), "map6": ("map", "map6"),
              "m8": ("map", "xop8"), "m9": ("map", "xop9"), "m10": ("map", "xopa"),
              "w0": ("w", 0), "wig": ("w", 0), "w1": ("w", 1),
              "nds": None, "ndd": None, "dds": None}
VSIB_NOTES = {"vm32x", "vm32y", "vm32z", "vm64x", "vm64y", "vm64z", "vsibx", "vsiby", "vsibz"}

def type_bytes(t):
    """the memory size of a type in bytes (0 = any or none)"""
    m = re.search(r"(\d+)V?$", t)
    return int(m.group(1)) // 8 if m and t not in ("ST0", "XMM0") else 0

def tuple_n8(tup, L, wide, b16, msz):
    vl = 16 << L
    elem = 2 if b16 else (8 if wide else 4)
    return {"fv": vl, "fvm": vl, "hv": vl // 2, "hvm": vl // 2, "qvm": vl // 4, "ovm": vl // 8,
            "m128": 16, "dup": 8 if L == 0 else vl, "t1s": msz or elem, "t1s8": 1, "t1s16": 2,
            "t1f32": 4, "t1f64": 8, "t2": 2 * elem, "t4": 4 * elem, "t8": 8 * elem}.get(tup)

CYRIX_NOLONG = {"bb0_reset", "bb1_reset", "cpu_read", "cpu_write", "dmint", "rdm",
                "rdshr", "rsdc", "rsldt", "rsts", "smint", "smintold", "svdc",
                "svldt", "svts", "wrshr"}

def nasm_form(name, ops, enc, flags=()):
    """The forms (form() argument tuples) of one insns.dat line; [] when
    this encoder cannot express it."""
    parts = [p.strip() for p in enc.split(":")]
    if len(parts) == 3:
        order, tup, body = parts
    elif len(parts) == 2:
        (order, body), tup = parts, ""
    else:
        order, tup, body = "", "", parts[0]
    opl = [] if ops == "void" else ops.split(",")
    # "rvmi" for three operands: the i is a fixed immediate (VCMPEQ_OSPS),
    # or nothing (VPSHLDVW): NASM reads as many letters as there are operands
    if len(order) > len(opl):
        order = order[:len(opl)]
    if len(order) != len(opl) or "+" in order or "x" in order:
        return []
    encn, pfx, mp, L, wide = ENC_LEGACY, "", "", 0, 0
    fl, modrm, fiximm, osz, plus, is4 = 0, M_NONE, None, None, False, False
    asz, mustrep = 0, False
    codes, imms, after_modrm = [], [], False
    for t in body.split():
        if t.split(".")[0] in ("vex", "evex", "xop"):
            encn = {"vex": ENC_VEX, "evex": ENC_EVEX, "xop": ENC_XOP}[t.split(".")[0]]
            pfx = "np"
            for x in t.split(".")[1:]:
                if x not in VEX_FIELDS:
                    return []
                if VEX_FIELDS[x]:
                    k, v = VEX_FIELDS[x]
                    if k == "L":
                        L = v
                    elif k == "pfx":
                        pfx = v
                    elif k == "map":
                        mp = v
                    else:
                        wide = v
        elif t in OSZ_WIDTH:
            osz = t
        elif t == "np" or t in VSIB_NOTES or t in ("nohi", "norexw", "repe", "repne"):
            pass                                 # (nohi: no ah..bh, which VEX has not;
                                                 # repe: the rep a string op takes)
        elif t in ("a16", "a32", "a64"):
            asz = {"a16": 1, "a32": 2, "a64": 3}[t]
        elif t == "mustrep":
            mustrep = True
        elif t in ("66", "f2", "f3") and not codes and encn == ENC_LEGACY:
            if pfx:
                return []
            pfx = t.upper() if t != "66" else "66"
        elif re.fullmatch(r"[0-9a-fA-F]{2}", t):
            if after_modrm:
                if fiximm is not None:
                    return []
                fiximm = int(t, 16)
            else:
                codes.append(int(t, 16))
        elif re.fullmatch(r"[0-9a-f]{2}\+r", t):
            codes.append(int(t[:2], 16))
            plus = len(codes)                    # which byte: the opcode's or a ModRM's
        elif t == "/r":
            modrm, after_modrm = M_R, True
        elif t == "/3r0":
            modrm, after_modrm = "3r0", True     # ModRM 11 reg 000
        elif re.fullmatch(r"/[0-7]", t):
            modrm, after_modrm = int(t[1]), True
        elif t == "/is4":
            is4 = True
        elif t in IMM_ENC:
            imms.append(IMM_ENC[t])
            after_modrm = True
        elif t == "wait":
            fl |= F_WAIT
        else:
            return []                    # rel, hle, a32, seg, jcc8, ...
    if not codes:
        return []
    if encn == ENC_LEGACY:
        # 0f 38 / 0f 3a escape to the three-byte maps - with an opcode after
        # them: SMINT is 0f 38 alone, an opcode of the 0f map
        if codes[0] == 0x0F and len(codes) > 2 and codes[1] in (0x38, 0x3A):
            mp, rest = {0x38: "38", 0x3A: "3a"}[codes[1]], codes[2:]
        elif codes[0] == 0x0F:
            mp, rest = "0f", codes[1:]
        else:
            mp, rest = "", codes
        if not rest:
            return []
        plus_on_modrm = plus and plus == len(codes) and len(rest) == 2
        opcode, rest = rest[0], rest[1:]
        if rest:
            if len(rest) > 1 or modrm != M_NONE or rest[0] < 0xC0:
                return []
            modrm = rest[0]                      # 0f 01 c8: a fixed ModRM byte
    else:
        if not mp or not 1 <= len(codes) <= 2:
            return []
        if len(codes) == 2:                      # tilerelease: a fixed ModRM byte
            if modrm != M_NONE or codes[1] < 0xC0:
                return []
            modrm = codes[1]
        opcode = codes[0]
    if wide:
        fl |= F_W

    types, roles, bc, er_at, stars = [], [], 0, None, []
    deco0 = opl[0].split("|")[1:] if opl else []   # (the first operand's: |mask, |z)
    for i, (o, letter) in enumerate(zip(opl, order.replace("j", "i"))):
        base, *deco = o.split("|")
        if base.endswith("*"):
            base = base[:-1]
            stars.append(i)
        to = False
        for d in deco:
            if d in ("mask", "z"):
                continue
            if d == "to" and base == "fpureg":
                to = True
                continue
            if d == "rs4" and base in ("zmmreg", "xmmreg"):
                continue                         # zmm1+3: the block's first register
            if d in ("b16", "b32", "b64"):
                bc = int(d[1:])
            elif d in ("er", "sae"):
                er_at = (i, "RC" if d == "er" else "SAE")
            else:
                return []                        # near, far, rs4 ...
        if base in IMM_OPS:
            if not imms:
                return []
            t = imms.pop(0)
        elif base in NASM_TYPES:
            t = "STTO" if to else NASM_TYPES[base]
        else:
            return []
        role = {"r": "+" if plus else "reg", "m": "rm", "v": "v", "i": "i", "s": "is4",
                "-": "-"}.get(letter)
        if role is None:
            return []
        types.append(t)
        roles.append(role)
    if plus and not (encn == ENC_LEGACY and plus_on_modrm):
        modrm = M_NONE                           # (fadd: dc c0+r, the ModRM's)
    if is4 != ("is4" in roles):
        return []
    # SM / SM2: the operands (the first two) are of one size, which a size
    # written on any of them sets ("kadd k1, dword k2, k3" is kaddd)
    span = len(types) if "SM" in flags else 2 if "SM2" in flags else 0
    ksized = next((t for t in types[:span] if t in ("K8", "K16", "K32", "K64")), None)
    if ksized:
        types = [ksized if t == "K" and i < span else t for i, t in enumerate(types)]
    # o16 / o32 / o64
    if osz:
        width = OSZ_WIDTH[osz]
        conv = [OSZ_TYPES[t] if t in OSZ_TYPES and type_bytes(t) * 8 == width else t for t in types]
        if conv != types:
            types = conv
            fl |= F_OSZ | (F_D64 if osz == "o64nw" else 0)
        elif osz == "o64":
            fl |= F_W
    elif encn == ENC_LEGACY and any(t in ("R64", "RM64") for t in types) and asz != 3:
        fl |= F_W                                # NASM: a 64-bit register sets REX.W
                                                 # (pextrw rax, xmm0, 0) - not one as
                                                 # wide as the address (enqcmd r64,
                                                 # m512: a64, no W)
    xo = 0                                       # the mode needs (FM_FIXIMM)
    if osz in ("o16", "o32") and not fl & F_OSZ:
        xo = 1 if osz == "o16" else 2            # 66 by the mode, not always
    # not in 64-bit mode: NOLONG, and Cyrix's system and SMM instructions -
    # no Cyrix CPU has it, and there their opcodes are others' (0f 38 the
    # three-byte map's escape, 0f 78 vmread). NASM 3 rejects them; VIA's
    # PadLock and the Cyrix MMX forms (CYRIX too) stay.
    nolong = "NOLONG" in flags or name.lower() in CYRIX_NOLONG
    if encn != ENC_LEGACY and (asz or mustrep or nolong):
        return []
    xo |= asz << 2 | nolong << 4 | ("LONG" in flags) << 5 | mustrep << 6
    if xo and fiximm is not None:
        return []                                # (the byte holds one of them)
    # EVEX: broadcast element size and the disp8*N scale
    n8 = 1
    if encn == ENC_EVEX:
        if bc:
            if bc == 16:
                fl |= F_B16
            elif (bc == 64) != bool(wide):
                return []
            fl |= F_BCST
        if any(r == "rm" and TYPES[TY[t]][4] != NOMEM for t, r in zip(types, roles)):
            msz = next((type_bytes(t) for t, r in zip(types, roles) if r == "rm"), 0)
            n8 = tuple_n8(tup, L, wide, bc == 16, msz)
            if n8 is None:
                return []
    elif bc or er_at:
        return []
    out = []
    # NASM's SIB forms (tileloadd): a SIB byte even with no index (FM_VL bit 7)
    vl = L | (0x80 if "SIB" in flags else 0)
    if encn == ENC_VEX and "LATEVEX" in flags:
        vl |= 0x40                               # (dispatch.s: {vex} / cpu latevex)
    if encn == ENC_EVEX:
        # an EVEX form NASM gives no |mask / |z: none ({k1} on vcomiss,
        # vmovd, vpextrd: #UD; NASM refuses them) - FM_VL 0x04 / 0x08
        vl |= (0 if "mask" in deco0 else 0x04) | (0 if "z" in deco0 else 0x08)
    def add(ts, rs, f, ix=None):
        if len(ts) > 4:
            return
        args = (name, ts, pfx, mp, opcode, modrm, rs, f, xo if fiximm is None else fiximm,
                NASM_PRIO, encn, vl)
        out.append((args, n8 if ix is None else ix))
    if modrm == "3r0":
        if types != ["TMM"]:
            return []
        for n in range(8):
            modrm = 0xC0 | n << 3
            add(["TMM%d" % n], ["-"], fl)
        return out
    fx = F_FIXIMM if fiximm is not None else 0
    add(types, roles, fl | fx)
    # "vaddps xmm1, xmm2": the omitted vvvv source is the destination
    for i in stars:
        if roles[i] == "v":
            add(types[:i] + types[i + 1:], roles[:i] + roles[i + 1:], fl | fx | F_V0)
    # {rn-sae} / {sae} after the operand that takes it, registers only
    if er_at:
        i, extra = er_at
        rt = [REG_ONLY.get(t, t) if r == "rm" else t for t, r in zip(types, roles)]
        if len(types) >= 4 and extra == "SAE":
            # "vcmppd k1, zmm2, zmm3, {sae}, 5": five operands; this form,
            # its rm a register, takes the {sae} as the instruction's
            args = (name, rt, pfx, mp, opcode, modrm, roles, (fl | fx) & ~(F_BCST | F_B16),
                    xo if fiximm is None else fiximm, NASM_PRIO, encn, vl | 0x20)
            out.append((args, n8))
        add(rt[:i + 1] + [extra] + rt[i + 1:], roles[:i + 1] + ["-"] + roles[i + 1:],
            (fl | fx) & ~(F_BCST | F_B16))
        for s in stars:
            if roles[s] == "v" and s != i:
                j = s if s < i else s + 1
                rt2 = rt[:i + 1] + [extra] + rt[i + 1:]
                rr2 = roles[:i + 1] + ["-"] + roles[i + 1:]
                add(rt2[:j] + rt2[j + 1:], rr2[:j] + rr2[j + 1:], (fl | fx | F_V0) & ~(F_BCST | F_B16))
    return out

# src/encode/x86/isa.s: the mnemonics only NASM's list has are kept in a
# block of their own, IDs from NASM_ID0, rewritten with the table
ISA_BEGIN = "    ; ---- NASM's instruction list: GENERATED by scripts/gen/gen_x86_enc.py ----"
ISA_END = "    ; ---- end of NASM's instruction list ----"
NASM_ID0 = 7000

def isa_base():
    """src/encode/x86/isa.s without the generated block"""
    text = open(ISA, encoding="utf-8").read().replace("\r\n", "\n")
    if ISA_BEGIN in text:
        a = text.index(ISA_BEGIN)
        b = text.index(ISA_END) + len(ISA_END) + 1
        text = text[:a] + text[b:]
    return text

ISA_NAMES = set(re.findall(r'mnc_ent\s+"([^"]+)"', isa_base()))
ISA_IDS = {m.group(1): int(m.group(2)) for m in
           re.finditer(r'mnc_ent\s+"([^"]+)",\s*\d+,\s*(\d+)', isa_base())}
TABLE_NAMES = {f[0] for f in forms}
# legacy forms of mnemonics the table has: only these take NASM's (the
# others are the opcode map's own)
# (movd r64, mm; "fadd", "fld" alone: st1)
LEGACY_OK = {"movd", "fadd", "fsub", "fsubr", "fmul", "fdiv", "fdivr", "fld", "fst", "fstp",
             "fxch", "fcom", "fcomp", "fucom", "fucomp", "ffree"}

def hand_ids():
    """the mnemonic IDs the hand-written encoders (encoder.s) dispatch on:
    the table must not take those over"""
    src = open(os.path.join(ROOT, "src", "encode", "x86", "encoder.s"), encoding="utf-8").read()
    ids = {int(n) for n in re.findall(r"\b(?:ELSE)?IF\s+ax,\s*e,\s*(\d+)", src)}
    for a, b in re.findall(r"ELSEIF_RANGE\s+ax,\s*(\d+),\s*(\d+)", src):
        ids.update(range(int(a), int(b) + 1))
    ids.update(range(3000, 3100))            # Jcc
    ids.update(range(6524, 6537))            # LOOPcc, JECXZ, JRCXZ, JCXZ
    return ids

HAND_IDS = hand_ids()
# hand-encoded, but NASM's forms are taken instead (the hand encoders give
# wrong bytes or none)
NASM_OVER = {"ldtilecfg", "sttilecfg", "tileloadd", "tileloaddt1", "tilestored", "tilezero",
             "tilerelease", "tdpbssd", "tdpbsud", "tdpbusd", "tdpbuud", "tdpbf16ps", "tdpfp16ps",
             # MPX (REX.B lost; bndldx / bndstx: REX, 67 and the SIB too), the
             # address-size ones (clzero eax: 67)
             "bndcl", "bndcu", "bndcn", "bndmk", "bndmov", "bndldx", "bndstx",
             # 3DNow! the stub wrote 0F 0F alone for (femms too)
             "femms", "pfadd", "pfcmpeq", "pfmax", "pfmin", "pfrcp", "pfrsqrt", "pi2fd",
             # tests/compat/encfuzz.py's findings: lfs / lgs / lss were 0F 00
             # with a REX.W; senduipi, tpause, umwait, incssp*, rdssp* lost
             # their REX.B; clrssbsy was setssbsy; prefetchwt1 took a 66 in
             # bits 16; cmpsd / movsd with operands were the string ones
             "lfs", "lgs", "lss", "senduipi", "tpause", "umwait", "incsspd", "incsspq",
             "rdsspd", "rdsspq", "clrssbsy", "setssbsy", "prefetchwt1", "uiret", "testui",
             "cmpsd", "movsd", "rsdc", "svdc",
             # their immediates cut without a word, enter's imm16 to a byte
             "ret", "retn", "int", "enter",
             "invlpga", "clzero", "umonitor",
             # rstorssp: its memory's REX.B lost ("[r12+8]" was [rsp+8])
             "rstorssp"}

def nasm_allowed(name, encn):
    """Whether NASM's form of this mnemonic goes in the table. They come
    after the opcode map's own, so they only take operands those do not: what
    NASM accepts there it encodes this way. Only the mnemonics encoded by
    hand (encoder.s) are left to their encoders - the table is tried first,
    so a form there would take their operands over."""
    if name not in ISA_NAMES or name in NASM_OVER:
        return True                              # new to src/encode/x86/isa.s
    if encn != ENC_LEGACY:
        return True                              # (the hand-written VEX / EVEX ones
                                                 # are stubs: vfmaddcph gave 0f 38 98)
    if ISA_IDS.get(name) in HAND_IDS:
        return name in LEGACY_OK
    return True

# the mnemonics whose forms the table has all of: NASM's are VEX / EVEX /
# XOP only (or NASM_OVER's): operands none fits are an error, not the
# hand-written encoders' (stubs for these) - bit 15 of x86_enc_index
NASM_LEGACY_SEEN = set()
NASM_SEEN = set()
AVX10_EVEX = set()      # mnemonics with an AVX10.2 EVEX form (insns3.dat)
# NASM's CPU levels (x86/iflags.ph's order), as "cpu" names them
# (src/frontend/syntax/nasm/parser/symbols.inc cpu_levels: the same numbers)
CPU_LEVELS = {"8086": 1, "186": 2, "286": 3, "386": 4, "486": 5, "PENT": 6, "P6": 7,
              "KATMAI": 8, "WILLAMETTE": 9, "PRESCOTT": 10, "X86_64": 11, "NEHALEM": 12,
              "WESTMERE": 13, "SANDYBRIDGE": 14, "FUTURE": 15, "IA64": 16}
CPU_LEVEL = {}

def nasm_forms():
    lines = []
    for path, line in [(path, l) for path in (INSNS, INSNS3) for l in open(path, encoding="utf-8")]:
        if line.startswith(";") or not line.strip():
            continue
        m = re.match(r"(\S+)\s+(\S+)\s+\[(.*?)\]\s+(\S+)", line)
        if not m:
            continue
        raw = m.group(1)
        if raw.lower() in NASM_WRONG and path == INSNS:
            continue                     # (2.16's: the forms in EXTRA_INSNS instead)
        if raw.lower() in NASM_WRONG_MAP5 and "map5" in m.group(3):
            continue
        if "cc" in raw and raw != raw.upper():
            # CMPccXADD: one mnemonic a condition, its code added to the
            # opcode ("e0+c")
            for cc, code in CONDITIONS:
                enc = re.sub(r"\b([0-9a-f]{2})\+c\b", lambda x: "%02x" % (int(x.group(1), 16) + code),
                             m.group(3))
                lines.append((raw.replace("cc", cc).lower(), m.group(2), enc, m.group(4)))
            continue
        lines.append((NAME_FIX.get(raw.lower(), raw.lower()), m.group(2), m.group(3), m.group(4)))
        if raw.lower() in NAME_FIX and (raw.lower().startswith("vp") or raw.lower() == "vfcmulcpch"):
            # NASM's own spelling too, where it names no other instruction
            lines.append((raw.lower(), m.group(2), m.group(3), m.group(4)))
    for line in EXTRA_INSNS.strip().splitlines():
        m = re.match(r"(\S+)\s+(\S+)\s+\[(.*?)\]\s+(\S+)", line.strip())
        lines.append((m.group(1).lower(), m.group(2), m.group(3), m.group(4)))
    for name, ops, enc, flags in lines:
        flags = flags.split(",")
        NASM_SEEN.add(name)
        if "evex." in enc:
            # does any of its EVEX forms take a mask / {z} (NASM's |mask, |z
            # on the first operand)? (the hand-written forms: as NASM says)
            d0 = ops.split(",")[0].split("|")[1:]
            EV_MASK_OK[name] = EV_MASK_OK.get(name, False) or "mask" in d0
            EV_Z_OK[name] = EV_Z_OK.get(name, False) or "z" in d0
        if "AVX10_2" in flags and "evex." in enc:
            AVX10_EVEX.add(name)
        # its CPU level: the lowest any of its forms has (x86_cpu_level)
        lv = [CPU_LEVELS[f] for f in flags if f in CPU_LEVELS]
        if lv:
            CPU_LEVEL[name] = min(lv + [CPU_LEVEL.get(name, 99)])
        if not re.search(r"\b(vex|evex|xop)\.", enc):
            NASM_LEGACY_SEEN.add(name)
        for args, n8 in nasm_form(name, ops, enc, flags):
            if not nasm_allowed(name, args[10]):
                continue
            if args[10] == ENC_LEGACY and re.search(r"\bnohi\b", enc):
                args = (args[0], ["RM8N" if t == "RM8" else t for t in args[1]]) + tuple(args[2:])
            form(*args)
            if args[10] == ENC_EVEX:
                forms[-1] = forms[-1] + (n8,)
            # vcmpph / vcmpsh's predicate pseudo-ops (vcmpeqph, vcmpnlt_uqsh
            # ...), as the hand-written vcmp* get them (evex_forms)
            if name in ("vcmpph", "vcmpsh") and args[10] == ENC_EVEX and forms[-1][1][-1] == TY["I8"]:
                f = forms[-1]
                for imm, p in enumerate(PRED32):
                    forms.append(("vcmp" + p + name[4:], f[1][:-1], f[2], f[3], f[4], f[5], f[6][:-1],
                                  f[7] | F_FIXIMM, imm) + f[9:])

EV_MASK_OK, EV_Z_OK = {}, {}
nasm_forms()
# the hand-written EVEX forms (evex_forms) of an instruction NASM lists:
# its mask / {z} as NASM's lines take them (FM_VL 0x04 / 0x08)
for i, f in enumerate(forms):
    if f[10] == ENC_EVEX and f[0] in EV_MASK_OK:
        L = f[11]
        if not EV_MASK_OK[f[0]]:
            L |= 0x04
        if not EV_Z_OK[f[0]]:
            L |= 0x08
        forms[i] = f[:11] + (L,) + f[12:]

# NASM's LATEVEX (the VEX form only with {vex} / "cpu latevex"): for a
# mnemonic with an EVEX form to take instead. With none (AVX-NE-CONVERT's
# vcvtneeph2ps, vbcstnebf16ps ...) the VEX form is the one, as NASM 3 writes;
# and where the EVEX form is AVX10.2's, later than the VEX one (AVX-VNNI-INT8
# / INT16: vpdpbssd, vpdpwsud ...), the VEX form too - a byte shorter, and
# what the CPUs of the instruction have (GNU's as 2.47 writes it; NASM 3.01
# the EVEX one)
_EVEX_NAMES = {f[0] for f in forms if f[10] == ENC_EVEX} - AVX10_EVEX
forms[:] = [f[:11] + (f[11] & ~0x40,) + f[12:] if f[10] == ENC_VEX and f[11] & 0x40 and f[0] not in _EVEX_NAMES
            else f for f in forms]

def isa_text():
    text = isa_base()
    new = sorted({f[0] for f in forms} - ISA_NAMES)
    # the IDs the generated block already gave keep theirs (the sources name
    # some: iretw, pushaw ...); a new mnemonic takes the next one free
    prev = open(ISA, encoding="utf-8").read().replace("\r\n", "\n")
    kept = {}
    if ISA_BEGIN in prev:
        blk = prev[prev.index(ISA_BEGIN):prev.index(ISA_END)]
        kept = {m.group(1): int(m.group(2)) for m in re.finditer(r'mnc_ent\s+"([^"]+)",\s*0,\s*(\d+)', blk)}
    # (past every ID in use: the hand-written ones, APX's 7600-7656, too)
    nxt = max(list(kept.values()) + list(ISA_IDS.values()) + [NASM_ID0 - 1]) + 1
    ids = {}
    for n in new:
        if n not in kept:
            kept[n] = nxt
            nxt += 1
        ids[n] = kept[n]
    lines = text.split("\n")
    last = max(i for i, l in enumerate(lines) if re.match(r'\s*mnc_ent\s+"', l))
    block = [ISA_BEGIN] + ['    mnc_ent "%s", 0, %d' % (n, ids[n]) for n in new] + [ISA_END]
    return "\n".join(lines[:last + 1] + block + lines[last + 1:])

# ============================================================================
# output
# ============================================================================
def mnemonic_ids():
    ids = {}
    for m in re.finditer(r'mnc_ent\s+"([^"]+)",\s*\d+,\s*(\d+)', isa_text()):
        ids.setdefault(m.group(1), int(m.group(2)))
    return ids

FINAL_NAMES = (NASM_SEEN - NASM_LEGACY_SEEN) | NASM_OVER

def render():
    ids = mnemonic_ids()
    missing = sorted({f[0] for f in forms if f[0] not in ids})
    if missing:
        sys.exit("mnemonics missing from src/encode/x86/isa.s: " + " ".join(missing))
    # group by mnemonic ID in first-seen order, then by priority (stable)
    order, by_id, name_of = [], {}, {}
    for i, f in enumerate(forms):
        mid = ids[f[0]]
        name_of.setdefault(mid, set()).add(f[0])
        if mid not in by_id:
            by_id[mid] = []
            order.append(mid)
        by_id[mid].append((f[10] == ENC_EVEX, f[9], i, f))
    out = [
        "; " + "=" * 76,
        "; GENERATED by scripts/gen/gen_x86_enc.py - do not edit by hand.",
        "; AMD64 instruction forms for the table-driven encoder",
        "; (src/encode/x86/dispatch.s). See the script for the layout.",
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
        if name_of[mid] <= FINAL_NAMES:
            index[mid] |= 0x8000                 # the table's word is final
        for _, _, _, f in sorted(by_id[mid], key=lambda x: (x[0], x[1], x[2])):
            table.append((mid, f))
    maxid = max(index)
    out += ["", "; mnemonic ID -> first form + 1 (0 = none); bit 15: the table's forms are",
            "; all there are (dispatch.s: none fitting is an error)", "x86_enc_index:"]
    for i in range(0, maxid + 1, 16):
        out.append("    dw " + ", ".join(str(index.get(j, 0)) for j in range(i, min(i + 16, maxid + 1))))
    # mnemonic ID -> the lowest CPU level of its forms (0: none given):
    # "cpu 386" and cpuid is "no instruction for this cpu level"
    lvmax = max(ids.values())
    lvl = [0] * (lvmax + 1)
    for n, mid in ids.items():
        if n in CPU_LEVEL:
            lvl[mid] = CPU_LEVEL[n] if not lvl[mid] else min(lvl[mid], CPU_LEVEL[n])
    out += ["", "; mnemonic ID -> the lowest CPU level of its forms (NASM's: 1 8086 ... 7 P6,",
            "; 8 KATMAI ... 15 FUTURE, 16 IA64; 0 none given)", "global x86_cpu_level, x86_cpu_maxid",
            "x86_cpu_maxid: dd %d" % lvmax, "x86_cpu_level:"]
    for i in range(0, lvmax + 1, 32):
        out.append("    db " + ", ".join(str(v) for v in lvl[i:i + 32]))
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
    isa = isa_text()
    if "--check" in sys.argv:
        cur = open(DST, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(DST) else ""
        if cur != text:
            sys.exit("src/encode/x86/gen/opcode.s is out of date; run scripts/gen/gen_x86_enc.py")
        if open(ISA, encoding="utf-8").read().replace("\r\n", "\n") != isa:
            sys.exit("src/encode/x86/isa.s's NASM block is out of date; run scripts/gen/gen_x86_enc.py")
        return
    with open(DST, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    with open(ISA, "w", encoding="utf-8", newline="\n") as f:
        f.write(isa)
    print("%d forms" % n)

if __name__ == "__main__":
    main()
