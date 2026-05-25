# Developer Guide

Practical step-by-step procedures for extending utasm.

---

## Adding a New Instruction

### 1. Add the opcode entry to the ISA table

File: `backend/isa/<arch>.s`

Each entry is a fixed-width record:
```asm
; format: mnemonic_hash, opcode_bytes, encoding_flags, operand_template
db  "MNEMONIC", 0       ; null-terminated mnemonic string
dw  OPCODE              ; primary opcode word(s)
db  ENC_FLAGS           ; encoding class flags (see include/type.inc)
db  OP_TEMPLATE         ; operand template id
```

### 2. Add the encoding handler

File: `backend/encoder/<arch>/` — pick the appropriate sub-file by instruction class (alu, branch, load_store, simd, etc.).

Follow the existing pattern:
```asm
encode_<mnemonic>:
    prologue
    ; rdi = instruction node pointer
    ; rsi = output buffer pointer
    ; ... encode bytes into [rsi] ...
    ; rax = bytes written, or error code
    epilogue
```

Register an entry in the dispatch table at the top of `backend/encoder/<arch>/encoder.s`.

### 3. Add a unit test

File: `tests/unit/encoder/<arch>/<mnemonic>.s`

```asm
; Expected encoding: <hex bytes>
<mnemonic> <operands>
```

The test harness compares utasm's output bytes against the expected comment.

### 4. Verify encoding

```sh
# Compare against NASM reference (AMD64)
nasm -f bin -o /tmp/ref.bin tests/unit/encoder/amd64/<mnemonic>.s
./build/gen1/utasm -f bin tests/unit/encoder/amd64/<mnemonic>.s -o /tmp/out.bin
cmp /tmp/ref.bin /tmp/out.bin

# Or run the unit test directly
bash scripts/test.sh unit/encoder/amd64/<mnemonic>
```

---

## Adding a New Error Code

Error codes are grouped by stage:

| Range  | Stage           |
| ------ | --------------- |
| E101–E199 | Lexer        |
| E201–E299 | Parser       |
| E301–E399 | Preprocessor |
| E401–E499 | Symbol table |
| E501–E599 | Encoder      |
| E601–E699 | Linker       |
| E701–E799 | Output       |
| E901–E999 | Internal     |

### 1. Reserve the code

File: `docs/error_reference.md` — add a row to the appropriate stage table.

### 2. Add the message string

File: `error/table.s`

```asm
err_E<NNN>:
    db  "E<NNN>: <message text>", 0
```

Add a pointer to it in the dispatch table at the bottom of the file.

### 3. Emit the error

At the detection point in the source:
```asm
    mov     rdi, E<NNN>
    mov     rsi, [cur_line]
    mov     rdx, [cur_col]
    call    error_emit
    check_err
```

### 4. Add a regression test

File: `tests/error/E<NNN>/trigger.s` — source that must produce exactly this error code.

```sh
bash scripts/test.sh error/E<NNN>
```

Verify: correct code fires, correct line/col reported, assembly continues (recovery) or stops (fatal).

---

## Adding a New CPU Profile

CPU profiles gate which instructions are legal for a given target chip.

### 1. Create the profile file

File: `cpu/profiles/<name>.s`

```asm
; cpu/profiles/<name>.s
; Feature flags for <chip name>

cpu_profile_<name>:
    db  CPU_HAS_SSE2    ; always on for x86-64 baseline
    db  CPU_HAS_AVX2
    db  CPU_HAS_AVX512F
    ; ... flags from include/type.inc CPU_HAS_* constants
    db  0               ; terminator
```

### 2. Register the profile

File: `cpu/profiles/profiles.s` — add an entry to the profile table:

```asm
    dq  cpu_profile_<name>
    db  "<name>", 0
```

### 3. Add feature flags if needed

File: `cpu/features.s` — if the new profile requires a feature flag that doesn't exist yet, add it here and define the corresponding `CPU_HAS_*` constant in `include/type.inc`.

### 4. Document the profile

File: `docs/error_reference.md` — add a row to the CPU Profiles table at the bottom.

---

## Adding a New Output Format

### 1. Create the entry point

File: `backend/output/<format>/out.s`

```asm
;*
; * <format>_emit
; * Purpose: Emit binary in <format> format.
; * Input:   rdi = asmctx pointer
; * Output:  rax = 0 on success, error code on failure
; ;
<format>_emit:
    prologue
    ; ... write output ...
    epilogue
```

### 2. Register the format in the dispatcher

File: `backend/output/output.s`

Add a dispatch entry:
```asm
    cmp     rdi, FORMAT_<FORMAT>
    je      <format>_emit
```

Add the `FORMAT_<FORMAT>` constant to `include/type.inc`.

### 3. Add the CLI option

File: `utasm.s` (CLI parser section)

```asm
    ; -f <format>
    cmp_str rsi, "<format>"
    je      .set_format_<format>
```

### 4. Add integration tests

Directory: `tests/integration/<format>/`

```sh
bash scripts/test.sh integration/<format>
```

---

## Working with the Bootstrap Pipeline

```sh
make gen0        # Stage 1: NASM assembles Gen0
make gen1        # Stage 2: Gen0 assembles Gen1; parity check Gen0==Gen1
make bootstrap   # Full 3-stage pipeline with strict binary comparison
```

The parity check (`cmp gen0 gen1`) is the invariant that proves self-hosting is correct. If it fails, something changed the encoding between stages — investigate before committing.

---

## Running a Specific Test

```sh
bash scripts/test.sh unit/encoder/amd64/mov
bash scripts/test.sh error/E201
bash scripts/test.sh integration/hello/amd64
bash scripts/test.sh regression/R042
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
