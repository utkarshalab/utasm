# Developer Guide

Practical step-by-step procedures for extending utasm.

---

## Adding a New Instruction

### 1. Add the opcode entry to the ISA table

File: `src/encode/<arch>.s`

Each entry is a fixed-width record:
```asm
; format: mnemonic_hash, opcode_bytes, encoding_flags, operand_template
db  "MNEMONIC", 0       ; null-terminated mnemonic string
dw  OPCODE              ; primary opcode word(s)
db  ENC_FLAGS           ; encoding class flags (see src/include/type.inc)
db  OP_TEMPLATE         ; operand template id
```

### 2. Add the encoding handler

File: `src/encode/<arch>/` — pick the appropriate sub-file by instruction class (alu, branch, load_store, simd, etc.).

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

Register an entry in the dispatch table at the top of `src/encode/<arch>/encoder.s`.

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
bash tests/run.sh unit/encoder/amd64/<mnemonic>
```

---

## Adding a New Error Code

utasm's errors are NASM-style messages, `file:line: error: <message>`,
chosen by an exit code: a function that finds the problem returns an
`EXIT_*` code in `rax`, and `src/diag/codes.s` turns it into the message
at the statement's line (see `src/diag/README.md`). The full list is in
`docs/user/errors.md`.

### 1. The code

File: `src/include/constant.inc`, *EXIT CODES* — the next free number:

```asm
%define EXIT_MY_PROBLEM        182 ; what it means
```

### 2. The message

File: `src/diag/codes.s` — the text, and a row in `code_table`:

```asm
m_my_problem:   db "what went wrong", 0
t_my_problem:   db "what went wrong with `^'", 0   ; optional: ^ = the subject
    ...
    code_msg EXIT_MY_PROBLEM,        m_my_problem, t_my_problem
```

### 3. Return it

```asm
    lea     rdi, [rel the_name]        ; when the message names something
    call    error_set_subject
    mov     eax, EXIT_MY_PROBLEM
    ret
```

The caller passes it up; `main/utasm.s` reports it, undoes the statement
and goes on to the next one.

### 4. Document and test it

Add it to `docs/user/errors.md`, and a case to `tests/compat/cases.py`
(*diagnostics* if NASM rejects the same source, *rejections* /
`ISA_ERRORS` if only utasm refuses it); run `tests/compat/run_all.py`.

## Adding a New CPU Profile

CPU profiles gate which instructions are legal for a given target chip.

### 1. Create the profile file

File: `src/planned/cpu/profiles/<name>.s`

```asm
; src/planned/cpu/profiles/<name>.s
; Feature flags for <chip name>

cpu_profile_<name>:
    db  CPU_HAS_SSE2    ; always on for x86-64 baseline
    db  CPU_HAS_AVX2
    db  CPU_HAS_AVX512F
    ; ... flags from src/include/type.inc CPU_HAS_* constants
    db  0               ; terminator
```

### 2. Register the profile

File: `src/planned/cpu/profiles/profiles.s` — add an entry to the profile table:

```asm
    dq  cpu_profile_<name>
    db  "<name>", 0
```

### 3. Add feature flags if needed

File: `src/planned/cpu/features.s` — if the new profile requires a feature flag that doesn't exist yet, add it here and define the corresponding `CPU_HAS_*` constant in `src/include/type.inc`.

### 4. Document the profile

File: `docs/user/errors.md` — add a row to the CPU Profiles table at the bottom.

---

## Adding a New Output Format

### 1. Create the entry point

File: `src/object/<format>/out.s`

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

File: `src/link/linker.s` (the output dispatch, by `ASMCTX_fmt`)

Add a dispatch entry:
```asm
    cmp     eax, FMT_<FORMAT>
    je      .emit_<format>
```

Add the `FMT_<FORMAT>` constant to `src/include/constant.inc` (next to
`FMT_ELF64` and `FMT_BIN`).

### 3. Add the CLI option

File: `src/main/utasm.s` (CLI parser section)

```asm
    ; -f <format>
    cmp_str rsi, "<format>"
    je      .set_format_<format>
```

### 4. Add integration tests

Directory: `tests/integration/<format>/`

```sh
bash tests/run.sh integration/<format>
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
bash tests/run.sh unit/encoder/amd64/mov
bash tests/run.sh error/E201
bash tests/run.sh integration/hello/amd64
bash tests/run.sh regression/R042
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
