# Contributing to utasm

---

## Before You Change a Module

Read its README first: every folder under `src/` has one
([src/README.md](src/README.md) is the map) — what the module does, how,
each file, its entry points and who calls them, what is left to do, and
which tests cover it.

Keep it true. When you add, move or remove a file, update the module's
**Files** table; `scripts/check_readmes.py` (run by `tests/run.sh`) fails
when a table and its folder disagree. When behaviour, an entry point or the
status changes, change the README in the same commit.

---

## Code Style

### Assembly Rules

**Indentation:** 4 spaces. No tabs.

**Labels:**
```asm
global_label:           ; left-aligned, colon attached
.local_label:           ; dot prefix, left-aligned
```

**Instructions:**
```asm
    mov     rax, rdi    ; opcode left-padded to col 4, operands col 12
    call    some_func   ; consistent spacing
```

**Registers:** Always lowercase. `rax` not `RAX`.

**Immediates:** Hex preferred for addresses/flags (`0xFF`), decimal for counts (`4`).

**Comments:** Only when the WHY is non-obvious. Never describe what the instruction does — the instruction already does that.
```asm
    and     rsp, -16    ; ABI: 16-byte align before call
    ; NOT: "align the stack" — obvious from the instruction
```

---

### Naming Conventions

**Functions:** `module_verb_noun` — e.g., `lexer_scan_ident`, `elf_write_shdr`

**Local labels:** `.verb_noun` — e.g., `.scan_loop`, `.error`, `.done`

**Constants:** `UPPER_SNAKE` — e.g., `ELF64_EHDR_SIZE`, `MAX_SYMBOLS`

**Registers saved across calls:** Document in the function header comment if non-obvious.

---

### File Structure

Every source file must start with:
```asm
;
; ============================================================================
; File        : path/from/root/file.s
; Description : One line, what this file does.
; ============================================================================
;
```

Every exported function must have:
```asm
;*
; * [function_name]
; * Purpose: What it does.
; * Input:   Register = meaning
; * Output:  Register = meaning, RAX = OK or error code
; ;
```

---

### Prologue / Epilogue

Always use the project macros:
```asm
my_function:
    prologue
    push    rbx
    push    r12
    ; ... work ...
    pop     r12
    pop     rbx
    epilogue
```

Callee-save registers (RBX, RBP, R12–R15) must be saved if used.
Stack must be 16-byte aligned before any `call`.

---

## Adding a New Instruction

1. Add the opcode entry to `src/encode/<arch>.s`
2. Add the encoding handler to `src/encode/<arch>/` (appropriate file)
3. Add a unit test at `tests/unit/encoder/<arch>/<instr>.s`
4. Verify encoding matches reference (objdump or manual check)
5. Run `bash tests/run.sh unit/encoder/<arch>/<instr>`

---

## Adding a New Error Code

1. Reserve the code in `docs/user/errors.md`
2. Add the message string to `src/diag/table.s`
3. Emit it from the correct stage with `error_emit`
4. Add a test at `tests/error/E<Nxx>/E<NNN>.s`
5. Verify: correct code fires, correct line/col, recovery continues

---

## Adding a New CPU Profile

1. Add the profile file at `src/planned/cpu/profiles/<name>.s`
2. Register it in `src/planned/cpu/profiles/profiles.s`
3. Add feature flags to `src/planned/cpu/features.s`
4. Document it in `docs/cpu_profiles.md`

---

## Adding a New Output Format

1. Add the entry point at `src/object/<format>/out.s`
2. Register the format in the output dispatch of `src/link/linker.s` (by `ASMCTX_fmt`'s `FMT_*` value)
3. Add the `-f <format>` CLI option in `src/main/cli.s`
4. Add integration tests at `tests/integration/<format>/`

---

## Branch Naming

```
fix/<short-description>       ; bug fixes
feat/<short-description>      ; new features
refactor/<short-description>  ; restructuring, no behaviour change
test/<short-description>      ; test additions only
docs/<short-description>      ; documentation only
```

---

## Commit Format

```
<type>: <short description>

<body — optional, explains WHY not WHAT>
```

Types: `fix`, `feat`, `refactor`, `test`, `docs`, `chore`

---

## Regression Rule

**Every bug fixed gets a regression test. No exceptions.**

See [tests.md](docs/dev/tests.md) for the regression test format.

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
