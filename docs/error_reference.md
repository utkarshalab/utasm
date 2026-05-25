# Error Reference

All error codes emitted by utasm, grouped by stage. Every code has exactly one message string in `error/table.s`.

Recovery behaviour: **R** = recoverable (assembly continues), **F** = fatal (assembly stops immediately).

---

## E1xx — Lexer Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E101 | Error | Unexpected character in input stream | R |
| E102 | Error | Unterminated string literal | R |
| E103 | Error | Unterminated character literal | R |
| E104 | Error | Invalid escape sequence in string | R |
| E105 | Error | Integer literal overflow (exceeds 64-bit range) | R |
| E106 | Error | Invalid hexadecimal digit | R |
| E107 | Error | Invalid binary digit | R |
| E108 | Error | Invalid octal digit | R |
| E109 | Error | Source file exceeds maximum size (2 GB) | F |
| E110 | Error | Source file could not be opened | F |
| E111 | Error | Source file read error | F |

---

## E2xx — Parser Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E201 | Error | Expected operand, got end of line | R |
| E202 | Error | Expected closing bracket ']' | R |
| E203 | Error | Expected closing parenthesis ')' | R |
| E204 | Error | Unknown mnemonic | R |
| E205 | Error | Invalid operand combination for instruction | R |
| E206 | Error | Expected register, got immediate | R |
| E207 | Error | Expected immediate, got register | R |
| E208 | Error | Memory operand not allowed for this instruction | R |
| E209 | Error | Invalid segment override | R |
| E210 | Error | Scale factor must be 1, 2, 4, or 8 | R |
| E211 | Error | Base register not valid in this addressing mode | R |
| E212 | Error | Index register cannot be RSP/SP | R |
| E213 | Error | Displacement out of range | R |
| E214 | Error | SECTION directive missing section name | R |
| E215 | Error | Unknown section attribute | R |
| E216 | Error | GLOBAL directive missing symbol name | R |
| E217 | Error | EXTERN directive missing symbol name | R |
| E218 | Error | EQU requires a label | R |
| E219 | Error | Expression syntax error | R |
| E220 | Error | Division by zero in constant expression | R |
| E221 | Error | STRUC/ENDSTRUC mismatch | R |
| E222 | Error | ALIGN value must be a power of two | R |
| E223 | Error | RESB/RESW/RESD/RESQ requires positive count | R |
| E224 | Error | DB/DW/DD/DQ: value out of range for size | R |

---

## E3xx — Preprocessor Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E301 | Error | %define: missing macro name | R |
| E302 | Error | %macro: missing macro name | R |
| E303 | Error | %macro: invalid parameter count specification | R |
| E304 | Error | %endmacro without matching %macro | R |
| E305 | Error | %if: missing expression | R |
| E306 | Error | %elif without matching %if | R |
| E307 | Error | %else without matching %if | R |
| E308 | Error | %endif without matching %if | R |
| E309 | Error | %rep: missing count | R |
| E310 | Error | %rep count must be a non-negative integer | R |
| E311 | Error | %endrep without matching %rep | R |
| E312 | Error | %include: missing filename | F |
| E313 | Error | %include: file not found | F |
| E314 | Error | %include: circular inclusion detected | F |
| E315 | Error | %include: nesting depth exceeded (max 32) | F |
| E316 | Error | Macro expansion depth exceeded (max 64) | F |
| E317 | Error | %undef: missing macro name | R |
| E318 | Error | %assign: missing variable name or expression | R |
| E319 | Error | %rotate without matching %macro | R |
| E320 | Error | Token paste (##) produced invalid token | R |

---

## E4xx — Symbol Table Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E401 | Error | Symbol redefined | R |
| E402 | Error | Symbol table full (increase MAX_SYMBOLS) | F |
| E403 | Error | Undefined symbol | R |
| E404 | Error | Forward reference not resolved after second pass | F |
| E405 | Error | COMMON symbol size mismatch (multiple definitions) | R |
| E406 | Error | EXTERN symbol also defined locally | R |
| E407 | Error | Symbol name too long (max 255 bytes) | R |

---

## E5xx — Encoder Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E501 | Error | Instruction not supported for target architecture | R |
| E502 | Error | Instruction not available on target CPU profile | R |
| E503 | Error | REX prefix required but operand size conflict | R |
| E504 | Error | VEX/EVEX encoding conflict | R |
| E505 | Error | AVX-512 mask register required | R |
| E506 | Error | Immediate out of range for instruction form | R |
| E507 | Error | Register size mismatch between operands | R |
| E508 | Error | AArch64: shift amount out of range | R |
| E509 | Error | AArch64: invalid condition code | R |
| E510 | Error | RISC-V: branch offset out of range (± 4 KiB) | R |
| E511 | Error | RISC-V: JAL offset out of range (± 1 MiB) | R |
| E512 | Error | Output buffer overflow | F |

---

## E6xx — Linker Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E601 | Error | No sections defined | F |
| E602 | Error | _start symbol not found (standalone build) | F |
| E603 | Error | Relocation overflow: target out of range | R |
| E604 | Error | Unknown relocation type | R |
| E605 | Error | Section alignment conflict | R |
| E606 | Error | Duplicate section name | R |
| E607 | Error | Archive member not found | R |
| E608 | Error | ELF output write error | F |
| E609 | Error | Section flag conflict (W+X not allowed) | F |

---

## E7xx — Output Errors

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E701 | Error | Unknown output format | F |
| E702 | Error | Output file could not be created | F |
| E703 | Error | Output file write error | F |
| E704 | Error | PE32+: no .text section to emit | F |
| E705 | Error | UPK: signing key not found | F |

---

## E9xx — Internal Errors

These indicate bugs in utasm itself. File an issue if you see one.

| Code | Severity | Message | Recovery |
| ---- | -------- | ------- | -------- |
| E901 | Internal | Arena allocator out of memory | F |
| E902 | Internal | Null pointer in internal API | F |
| E903 | Internal | Inconsistent assembler context state | F |
| E904 | Internal | Encoder dispatch table corrupt | F |
| E905 | Internal | Symbol table integrity check failed | F |

---

## Warnings (W-series)

Warnings do not stop assembly. All are suppressible with `--no-warn <code>`.

| Code | Message |
| ---- | ------- |
| W101 | Unused label |
| W102 | Label defined but never referenced |
| W201 | Implicit data size assumed (use BYTE/WORD/DWORD/QWORD) |
| W202 | Truncated immediate — value fits but high bits lost |
| W301 | Macro defined but never used |
| W302 | %define overwrites existing definition |
| W401 | EXTERN symbol never referenced |
| W501 | NOP inserted for alignment (performance note) |
| W601 | Section has no content |

---

## CPU Profiles

| Profile     | Target                       |
| ----------- | ---------------------------- |
| `generic`   | x86-64 baseline (SSE2 only)  |
| `x86_64_v3` | AVX2 + FMA + POPCNT + BMI2   |
| `skylake`   | Intel Skylake (AVX2, no AVX-512) |
| `znver3`    | AMD Zen 3 (AVX2 + CLWB + WBNOINVD) |

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
