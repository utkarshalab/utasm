# NASM's instruction tables

Data from the [Netwide Assembler](https://www.nasm.us/), kept here
unchanged apart from what is noted below. utasm does not link or run any
NASM code; these files are read by `scripts/gen/gen_x86_enc.py` when it
generates `src/encode/x86/gen/opcode.s`, and by the compatibility tests
(`tests/compat/encfuzz.py`).

| File | Source | Notes |
| --- | --- | --- |
| `insns.dat` | `x86/insns.dat` of NASM 2.16.03 | as distributed |
| `insns3.dat` | `x86/insns.dat` of NASM 3.01 | only the lines for instructions 2.16.03's table does not have (AVX10.2, AVX-VNNI-INT16, AMX-FP8, MOVRS ...), with a header saying so |

## Licence

Copyright 1996-2025 The NASM Authors. Both files are under NASM's
2-clause BSD licence; the notice at the top of each file is kept as it
was. The rest of utasm is under its own licence (`LICENSE`, Apache-2.0).
