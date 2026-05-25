# Contributing to utasm

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

1. Add the opcode entry to `backend/isa/<arch>.s`
2. Add the encoding handler to `backend/encoder/<arch>/` (appropriate file)
3. Add a unit test at `tests/unit/encoder/<arch>/<instr>.s`
4. Verify encoding matches reference (objdump or manual check)
5. Run `bash scripts/test.sh unit/encoder/<arch>/<instr>`

---

## Adding a New Error Code

1. Reserve the code in `docs/error_reference.md`
2. Add the message string to `error/table.s`
3. Emit it from the correct stage with `error_emit`
4. Add a test at `tests/error/E<Nxx>/E<NNN>.s`
5. Verify: correct code fires, correct line/col, recovery continues

---

## Adding a New CPU Profile

1. Add the profile file at `cpu/profiles/<name>.s`
2. Register it in `cpu/profiles/profiles.s`
3. Add feature flags to `cpu/features.s`
4. Document it in `docs/cpu_profiles.md`

---

## Adding a New Output Format

1. Add the entry point at `backend/output/<format>/out.s`
2. Register the format in `backend/output/output.s` dispatcher
3. Add the `-f <format>` CLI option in `cli.s`
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

See [TESTS.md](TESTS.md) for the regression test format.

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
