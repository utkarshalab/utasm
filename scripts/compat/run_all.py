#!/usr/bin/env python3
"""NASM compatibility suites for utasm.

Assembles the same sources with NASM and utasm and compares the results:
feature probes (flat binaries), ELF objects (sections, relocations,
symbols), data directives and floats, section layouts and linked programs,
labels as instruction operands, UBF boot images, error messages (the file
and line of the first error), NASM's command-line options, listings (-l),
DWARF line tables (-g), i386 objects (-f elf32), labels in expressions
(defined later, and NASM's scalar errors), inputs past the old fixed limits,
inputs that crashed utasm before (robustness), every order of base, index and
scale in addresses,
the encoder corpus (also under bits 32 and bits 16), operand shapes (valid
and invalid pairings), and the disassembler against objdump.

usage: scripts/compat/run_all.py [utasm-binary] [--quick] [-v]
       --quick  skips the encoder corpus, the operand shapes, the addresses and the
                disassembler
                (the slow ones)
       -v       also lists the known differences (common.KNOWN)

Exits 0 when everything matches or is a known difference, 1 otherwise, and
0 with a note when NASM, readelf or objdump is not installed.
"""
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from common import have  # noqa: E402
import suites  # noqa: E402


def main(argv):
    args = [a for a in argv if not a.startswith("-")]
    utasm = os.path.abspath(args[0] if args else "build/gen1/utasm")
    quick, verbose = "--quick" in argv, "-v" in argv
    missing = [t for t in ("nasm", "readelf", "objdump", "objcopy") if not have(t)]
    if missing:
        print("  NASM compatibility suites skipped: %s not installed" % ", ".join(missing))
        return 0
    if not os.path.exists(utasm):
        print("  no utasm binary at %s" % utasm)
        return 1
    runs = [suites.bin_probes, suites.elf_probes, suites.data_forms,
            suites.sections, suites.symbol_imm, suites.ubf, suites.diagnostics,
            suites.command_line, suites.listing, suites.dwarf, suites.elf32,
            suites.expressions, suites.limits, suites.robustness]
    if not quick:
        runs += [suites.encoder, suites.operand_shapes, suites.modes, suites.addresses]
    good = True
    for fn in runs:
        good = fn(utasm, verbose).report() and good
    if not quick:
        objects = sorted(glob.glob(os.path.join(os.path.dirname(os.path.dirname(utasm)), "gen1", "**", "*.o"),
                                   recursive=True))
        good = suites.disasm(utasm, verbose, objects).report() and good
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
