# utasm — Error Reference
> UtkarshaLab | Engineering the Foundation of Tomorrow
> 
> Complete documentation for every error, warning, note, and hint code.
> Every code has: category, cause, triggering example, exact output, recovery behavior, and related hints.
> This document is the ground truth. If a code is not here, it does not exist in utasm.

---

## Code Format

```
[CATEGORY][TYPE][NUMBER]

CATEGORY = 2 letters   — identifies the pipeline stage
TYPE     = 1 letter    — E=Error W=Warning N=Note H=Hint
NUMBER   = 4 digits    — 0001–9999

Examples:
  LXE0001   Lexer Error #1
  LXW0001   Lexer Warning #1
  LXN0001   Lexer Note #1
  LXH0001   Lexer Hint #1
  ENE0042   Encoder Error #42
  ITE0001   Internal Error #1
```

---

## Severity Levels

| Type | Letter | Meaning |
|---|---|---|
| Error   | E | Assembly stops after current pass |
| Warning | W | Configurable — suppress with `-Wno-XX0000`, promote with `-Werror` |
| Note    | N | Informational context attached to an error |
| Hint    | H | Actionable fix suggestion attached to an error |

---

## Output Format

Every error follows this exact format:

```
{CATEGORY}{TYPE}{NUMBER}: {message}
  --> {filename}:{line}:{col}
   |
{line-1} |   {source line before}
{line}   |   {source line with error}
         |   {col_start spaces}{^^^^ underline}
   |
   = note[{NoteCode}]:  {note message}
   = hint[{HintCode}]:  {hint message}
   |
   → expanded from macro '{name}' at {file}:{line}
```

Example:

```
LXE0001: invalid character in source
  --> src/main.s:1:10
   |
 1 |     mov rax, @value
   |              ^
   |              character '@' (0x40) is not valid here
   |
   = hint[LXH0001]: valid identifier characters are [a-zA-Z0-9_]
```

---

## Category Table

```
; ── Frontend ──────────────────────────────────────────────────
LX   Lexer           characters, tokens, literals
PR   Parser          syntax, grammar, structure
PP   Preprocessor    %define/%include equivalents
MC   Macro           definition, expansion, recursion

; ── Middle ────────────────────────────────────────────────────
SM   Semantic        symbol usage, context validation
SY   Symbol table    definitions, forward refs, redefinition
EX   Expression      arithmetic, constants, folding
SC   Scope           local labels, proc boundaries

; ── Backend ───────────────────────────────────────────────────
EN   Encoder         instruction encoding, operands
IS   ISA             instruction availability per arch
LN   Linker          symbol resolution, section layout
RL   Relocation      reloc type, overflow, unsupported

; ── Output Formats ────────────────────────────────────────────
EL   ELF             ELF64 format violations
PF   PE Format       PE32+ / COFF format violations
FB   Flat Binary     flat binary format violations
UP   UPK             UtkarshaLab Package format violations

; ── Support Modules ───────────────────────────────────────────
CP   CPU/Arch        feature flags, CPU profile validation
DW   DWARF           debug info generation failures
OP   Optimizer       post-encoding optimization errors
HP   Hot-patch       self-patch / runtime binary modification
RF   Profiler        RDTSC profiler errors
AR   Arena           arena allocator / memory management
BS   Bootstrap       self-hosting pipeline errors

; ── Directives ────────────────────────────────────────────────
DI   Directive       general directive errors
SE   Section         section flags, overlap, permissions
DA   Data            d8/d16/d32/d64 violations
AL   Alignment       section, data, instruction alignment
IC   Include         file not found, circular, depth
VS   Visibility      global/extern conflicts

; ── Instruction Classes ───────────────────────────────────────
SI   SIMD            register class, width, alignment
FP   Float           x87 stack, float literals, SSE size
PV   Privilege       ring level, protected instructions
MM   Memory model    flat, segmented, mode violations

; ── System ────────────────────────────────────────────────────
CL   CLI             command-line argument errors
TY   Type            size specifier, type mismatch
SX   Security        W^X, writable+executable violations
CO   Compatibility   ABI, calling convention errors
IT   Internal        utasm bugs — always report these
```

---

## Migration Table (old → new)

```
OLD         NEW RANGE       CATEGORY
E1xx    →   LXE0001+        Lexer
E2xx    →   PRE0001+        Parser
E3xx    →   MCE0001+        Macro
E4xx    →   SME0001+        Semantic
E5xx    →   ENE0001+        Encoder
E6xx    →   LNE0001+        Linker
E7xx    →   CPE0001+        CPU/Arch
E8xx    →   ITE0001+        Internal
E9xx    →   EXE0001+        Expression
E10xx   →   DIE0001+        Directive
E11xx   →   ICE0001+        Include
E12xx   →   SEE0001+        Section
E13xx   →   VSE0001+        Visibility
E14xx   →   RLE0001+        Relocation
E15xx   →   ELE0001+        ELF output
E16xx   →   PFE0001+        PE output
E17xx   →   FBE0001+        Flat binary
E18xx   →   UPE0001+        UPK
E19xx   →   DWE0001+        DWARF
E20xx   →   DAE0001+        Data
E21xx   →   ALE0001+        Alignment
E22xx   →   SCE0001+        Scope
E23xx   →   TYE0001+        Type
E24xx   →   PVE0001+        Privilege
E25xx   →   SIE0001+        SIMD
E26xx   →   MME0001+        Memory model
E27xx   →   HPE0001+        Hot-patch
E28xx   →   UPE0001+        UPK (merged)
E29xx   →   SXE0001+        Security
E30xx   →   COE0001+        Compatibility
E31xx   →   DIE0001+        Directive (merged)
E32xx   →   PPE0001+        Preprocessor
E33xx   →   LNE0001+        Linker (merged)
E34xx   →   FPE0001+        Float
E35xx   →   UPE0001+        UPK (merged)

W1xx    →   LXW0001+        Lexer warnings
W2xx    →   PRW0001+        Parser warnings
W3xx    →   SMW0001+        Semantic warnings
W4xx    →   SYW0001+        Symbol warnings
W5xx    →   ENW0001+        Encoder warnings
W6xx    →   LNW0001+        Linker warnings
W7xx    →   CPW0001+        CPU warnings
W8xx    →   PRW0001+        Style warnings (merged into Parser)
W9xx    →   COW0001+        Portability/Compatibility warnings
```

---

# LX — Lexer

Fired during tokenization.
Recovery: skip to next newline and continue lexing.

---

## LXE0001 — Invalid character in source

**Cause:** A character not part of the utasm character set appears in source.

**Triggers:**
```asm
mov rax, @value     ; @ is not valid
mov rbx, £100       ; £ is not ASCII
```

**Output:**
```
LXE0001: invalid character in source
  --> src/main.s:1:10
   |
 1 |     mov rax, @value
   |              ^
   |              character '@' (0x40) is not valid here
   |
   = hint[LXH0001]: valid identifier characters are [a-zA-Z0-9_]
```

**Recovery:** Character skipped. Lexer continues from next character.

---

## LXE0002 — Unterminated string literal

**Cause:** A string opened with `"` is not closed before end of line.

**Triggers:**
```asm
d8 "hello world        ; missing closing quote
```

**Output:**
```
LXE0002: unterminated string literal
  --> src/main.s:1:4
   |
 1 |     d8 "hello world
   |        ^~~~~~~~~~~~~ string starts here, never closed
   |
   = note[LXN0002]: string literals must be closed on the same line
   = hint[LXH0002]: add closing '"' before end of line
```

**Recovery:** Skip to end of current line. Lexer continues on next line.

---

## LXE0003 — Unterminated character literal

**Cause:** A character literal opened with `'` is not closed.

**Triggers:**
```asm
mov al, 'A          ; missing closing quote
```

**Output:**
```
LXE0003: unterminated character literal
  --> src/main.s:1:9
   |
 1 |     mov al, 'A
   |             ^~ character literal starts here, never closed
   |
   = hint[LXH0003]: character literals require exactly one character: 'A'
```

**Recovery:** Skip to end of line.

---

## LXE0004 — Invalid escape sequence

**Cause:** A backslash in a string or character literal is followed by an unrecognized character.

**Valid escape sequences:** `\n \t \r \\ \' \" \0 \a \b \f \v \xHH \uHHHH \UHHHHHHHH`

**Triggers:**
```asm
d8 "hello\qworld"     ; \q is not valid
```

**Output:**
```
LXE0004: invalid escape sequence
  --> src/main.s:1:11
   |
 1 |     d8 "hello\qworld"
   |               ^^
   |               '\q' is not a recognized escape sequence
   |
   = note[LXN0004]: valid escapes: \n \t \r \\ \' \" \0 \a \b \f \v \xHH \uHHHH
   = hint[LXH0004]: did you mean '\\' for a literal backslash?
```

**Recovery:** Invalid escape treated as literal character after `\`. Lexing continues.

---

## LXE0005 — Malformed binary literal

**Cause:** Binary literal prefix `0b` not followed by binary digits, or contains non-binary digits.

**Triggers:**
```asm
mov al, 0b          ; prefix with no digits
mov bl, 0b1012      ; '2' is not binary
```

**Output:**
```
LXE0005: malformed binary literal
  --> src/main.s:2:9
   |
 2 |     mov bl, 0b1012
   |             ~~~~~~^
   |                   digit '2' is not valid in binary (only 0 and 1)
   |
   = hint[LXH0005]: binary literals contain only 0 and 1: 0b1010
```

**Recovery:** Stop scanning at invalid character. Use digits scanned so far.

---

## LXE0006 — Malformed octal literal

**Cause:** Octal prefix `0o` followed by non-octal digits (8 or 9).

**Triggers:**
```asm
mov bl, 0o789       ; '8' and '9' are not octal
```

**Output:**
```
LXE0006: malformed octal literal
  --> src/main.s:1:9
   |
 1 |     mov bl, 0o789
   |             ~~~~^
   |                 digit '8' is not valid in octal (only 0–7)
   |
   = hint[LXH0006]: octal literals use digits 0–7: 0o755
```

**Recovery:** Stop at invalid character. Use digits scanned so far.

---

## LXE0007 — Malformed hex literal

**Cause:** Hex prefix `0x` not followed by any hex digits.

**Triggers:**
```asm
mov al, 0x          ; prefix with no digits
```

**Output:**
```
LXE0007: malformed hex literal
  --> src/main.s:1:9
   |
 1 |     mov al, 0x
   |             ^^
   |             '0x' must be followed by at least one hex digit
   |
   = hint[LXH0007]: hex literals: 0xFF, 0h1A2B
```

**Recovery:** Emit value 0. Continue from character after prefix.

---

## LXE0008 — Malformed decimal literal

**Cause:** Decimal literal contains non-decimal characters after first digit.

**Triggers:**
```asm
mov al, 12abc       ; letters after decimal digits
```

**Output:**
```
LXE0008: malformed decimal literal
  --> src/main.s:1:9
   |
 1 |     mov al, 12abc
   |             ~~^^^
   |               unexpected characters in decimal literal
```

**Recovery:** Stop at first non-decimal character. Use digits scanned so far.

---

## LXE0009 — Integer literal overflow

**Cause:** Integer literal exceeds maximum 64-bit unsigned value (18446744073709551615).

**Triggers:**
```asm
mov rax, 99999999999999999999
```

**Output:**
```
LXE0009: integer literal overflow
  --> src/main.s:1:10
   |
 1 |     mov rax, 99999999999999999999
   |              ^^^^^^^^^^^^^^^^^^^^
   |              exceeds maximum 64-bit unsigned integer
   |
   = note[LXN0009]: maximum: 0xFFFFFFFFFFFFFFFF = 18446744073709551615
```

**Recovery:** Use value 0xFFFFFFFFFFFFFFFF (clamped). Assembly continues.

---

## LXE0010 — Float literal overflow

**Cause:** Float literal exceeds IEEE 754 double precision range.

**Triggers:**
```asm
d64 1.8e309
```

**Output:**
```
LXE0010: float literal overflow
  --> src/main.s:1:4
   |
 1 |     d64 1.8e309
   |         ^^^^^^^
   |         exceeds maximum IEEE 754 double precision
   |
   = note[LXN0010]: maximum double: 1.7976931348623157e+308
```

**Recovery:** Use +infinity. Assembly continues.

---

## LXE0011 — Invalid identifier character

**Cause:** Identifier contains character not in [a-zA-Z0-9_].

**Triggers:**
```asm
my-label:           ; hyphen not valid
```

**Output:**
```
LXE0011: invalid identifier character
  --> src/main.s:1:3
   |
 1 |     my-label:
   |       ^
   |       '-' is not valid in an identifier
   |
   = note[LXN0011]: identifiers may contain [a-zA-Z0-9_], must start with [a-zA-Z_]
   = hint[LXH0011]: use underscore: 'my_label'
```

**Recovery:** Identifier ends at invalid character. Remainder treated as separate tokens.

---

## LXE0012 — Identifier too long

**Cause:** Identifier exceeds MAX_TOKEN_LEN (4096 characters).

**Output:**
```
LXE0012: identifier too long
  --> src/main.s:1:1
   |
 1 |     averylongname...
   |     ^~~~~~~~~~~~~~~~
   |     identifier exceeds maximum length of 4096 characters
```

**Recovery:** Identifier truncated to 4096 characters. Assembly continues.

---

## LXE0013 — Unexpected end of file in block comment

**Cause:** Block comment `/* ... */` not closed before end of file.

**Triggers:**
```asm
/* this comment never closes
```

**Output:**
```
LXE0013: unexpected end of file in block comment
  --> src/main.s:1:1
   |
 1 |     /* this comment never closes
   |     ^~ block comment opened here, never closed
   |
   = hint[LXH0013]: close the comment with '*/'
```

**Recovery:** EOF treated as end of comment. Assembly continues.

---

## LXE0014 — Block comment nesting depth exceeded

**Cause:** Block comments nested more than 32 levels deep.

**Output:**
```
LXE0014: block comment nesting depth exceeded
  --> src/main.s:1:40
   |
 1 |     /* level 1 /* level 2 /* ... /* level 33
   |                                    ^^
   |                                    maximum nesting depth is 32
```

**Recovery:** Ignore additional nesting. Continue at depth 32.

---

## LXE0015 — Invalid UTF-8 sequence

**Cause:** Byte sequence in string literal or source is not valid UTF-8.

**Triggers:**
```asm
d8 "hello\xffworld"
```

**Output:**
```
LXE0015: invalid UTF-8 sequence
  --> src/main.s:1:15
   |
 1 |     d8 "hello\xffworld"
   |               ^^^^
   |               byte sequence 0xFF is not valid UTF-8
   |
   = note[LXN0015]: source files must be valid UTF-8
   = hint[LXH0015]: use explicit byte values: d8 0xFF
```

**Recovery:** Invalid bytes replaced with U+FFFD. Assembly continues.

---

# PR — Parser

Fired during parsing.
Recovery: skip tokens until next newline or known-safe boundary.

---

## PRE0001 — Unexpected token

**Cause:** Parser encounters a token it does not expect in current context.

**Triggers:**
```asm
mov rax,, rbx       ; double comma
```

**Output:**
```
PRE0001: unexpected token
  --> src/main.s:1:9
   |
 1 |     mov rax,, rbx
   |             ^
   |             unexpected ',' — expected register, memory, or immediate
```

**Recovery:** Skip token. Attempt to continue parsing current statement.

---

## PRE0002 — Expected operand found none

**Cause:** Instruction requiring operands has none.

**Triggers:**
```asm
mov                 ; MOV requires 2 operands
```

**Output:**
```
PRE0002: expected operand, found none
  --> src/main.s:1:4
   |
 1 |     mov
   |     ~~~
   |     'mov' requires 2 operands
   |
   = hint[PRH0002]: mov rax, rbx
```

**Recovery:** Skip instruction. Continue from next line.

---

## PRE0003 — Expected register operand

**Cause:** Operand position requiring register received something else.

**Output:**
```
PRE0003: expected register operand
  --> src/main.s:1:5
   |
 1 |     mul [rax]
   |         ^^^^^
   |         MUL requires a register operand, found memory
```

**Recovery:** Skip operand. Continue.

---

## PRE0004 — Expected immediate operand

**Cause:** Operand position requiring immediate received something else.

**Triggers:**
```asm
int rax             ; INT requires immediate, not register
```

**Output:**
```
PRE0004: expected immediate operand
  --> src/main.s:1:5
   |
 1 |     int rax
   |         ^^^
   |         'int' requires an immediate value (0–255), found register 'rax'
   |
   = hint[PRH0004]: int 0x80
```

**Recovery:** Skip instruction.

---

## PRE0005 — Expected memory operand

**Cause:** Operand position requiring memory reference received register or immediate.

**Triggers:**
```asm
lea rax, rbx        ; LEA source must be memory
```

**Output:**
```
PRE0005: expected memory operand
  --> src/main.s:1:10
   |
 1 |     lea rax, rbx
   |              ^^^
   |              'lea' source must be memory address, found register 'rbx'
   |
   = hint[PRH0005]: lea rax, [rbx + 8]
```

**Recovery:** Skip instruction.

---

## PRE0006 — Expected label name

**Cause:** Directive requiring label name received something else.

**Triggers:**
```asm
global 42           ; label name expected, not number
```

**Output:**
```
PRE0006: expected label name
  --> src/main.s:1:8
   |
 1 |     global 42
   |            ^^
   |            expected identifier, found integer '42'
   |
   = hint[PRH0006]: global my_function
```

**Recovery:** Skip directive.

---

## PRE0007 — Expected instruction or directive

**Cause:** Line begins with token that is neither mnemonic nor directive.

**Triggers:**
```asm
42 mov rax, rbx     ; line starts with integer
```

**Output:**
```
PRE0007: expected instruction or directive
  --> src/main.s:1:1
   |
 1 |     42 mov rax, rbx
   |     ^^
   |     expected mnemonic, directive, or label — found integer '42'
```

**Recovery:** Skip to next newline.

---

## PRE0008 — Mismatched brackets

**Cause:** Opening and closing brackets do not match.

**Triggers:**
```asm
mov rax, [rbx + (4 * 3]    ; ) expected before ]
```

**Output:**
```
PRE0008: mismatched brackets in expression
  --> src/main.s:1:22
   |
 1 |     mov rax, [rbx + (4 * 3]
   |                     ^      ^
   |                     '(' opened here
   |                            ']' closes '[', but '(' is still open
   |
   = hint[PRH0008]: mov rax, [rbx + (4 * 3)]
```

**Recovery:** Assume missing bracket inserted. Continue.

---

## PRE0009 — Unknown mnemonic

**Cause:** Identifier in instruction position does not match any known mnemonic.

**Triggers:**
```asm
mvo rax, rbx        ; typo — did you mean mov?
```

**Output:**
```
PRE0009: unknown mnemonic 'mvo'
  --> src/main.s:1:5
   |
 1 |     mvo rax, rbx
   |     ~~~
   |     'mvo' is not a recognized instruction
   |
   = hint[PRH0009]: did you mean 'mov'?
```

**Recovery:** Skip instruction. Continue from next line.

---

## PRE0010 — Invalid operand combination

**Cause:** The combination of operand types is not valid for the instruction.

**Triggers:**
```asm
mov [rax], [rbx]    ; mem → mem not allowed
```

**Output:**
```
PRE0010: invalid operand combination
  --> src/main.s:1:5
   |
 1 |     mov [rax], [rbx]
   |     ~~~~~~~~~~~~~~~~
   |     'mov' does not support memory → memory operands
   |
   = note[PRN0010]: x86 cannot move directly between two memory locations
   = hint[PRH0010]: mov rax, [rbx] / mov [rcx], rax
```

**Recovery:** Skip instruction.

---

## PRE0011 — Scale factor invalid

**Cause:** Memory addressing scale factor is not 1, 2, 4, or 8.

**Triggers:**
```asm
mov rax, [rbx + rcx*3]     ; scale must be 1,2,4,8
```

**Output:**
```
PRE0011: scale factor must be 1, 2, 4, or 8
  --> src/main.s:1:20
   |
 1 |     mov rax, [rbx + rcx*3]
   |                         ^
   |                         scale factor '3' is not valid
   |
   = hint[PRH0011]: valid scale factors: 1, 2, 4, 8
```

**Recovery:** Scale ignored. Use scale of 1.

---

## PRE0012 — RSP cannot be index register

**Cause:** RSP/SP used as index register in SIB addressing.

**Triggers:**
```asm
mov rax, [rbx + rsp*2]
```

**Output:**
```
PRE0012: RSP cannot be used as index register
  --> src/main.s:1:17
   |
 1 |     mov rax, [rbx + rsp*2]
   |                     ^^^
   |                     RSP is not valid as an index register in SIB
   |
   = hint[PRH0012]: use another register: [rbx + rcx*2]
```

**Recovery:** Skip instruction.

---

## PRE0013 — Division by zero in constant expression

**Cause:** Constant expression contains division by zero.

**Triggers:**
```asm
def ZERO 0
mov rax, 100 / ZERO
```

**Output:**
```
PRE0013: division by zero in constant expression
  --> src/main.s:2:14
   |
 2 |     mov rax, 100 / ZERO
   |              ~~~~~~~~~~
   |              divisor evaluates to zero
```

**Recovery:** Result treated as 0. Assembly continues.

---

## PRE0014 — end without matching opener

**Cause:** `end` encountered with no open block to close.

**Triggers:**
```asm
mov rax, 1
end                 ; nothing to close
```

**Output:**
```
PRE0014: 'end' without matching 'mac', 'if', 'times', or 'struc'
  --> src/main.s:2:1
   |
 2 |     end
   |     ~~~
   |     no open block to close
```

**Recovery:** Ignore the `end`. Assembly continues.

---

## PRE0015 — align value not power of two

**Cause:** `align` directive value is not a power of two.

**Triggers:**
```asm
align 3             ; must be 1,2,4,8,16,32...
```

**Output:**
```
PRE0015: align value must be a power of two
  --> src/main.s:1:7
   |
 1 |     align 3
   |           ^
   |           '3' is not a power of two
   |
   = hint[PRH0015]: valid values: 2, 4, 8, 16, 32, 64, 128, 256...
```

**Recovery:** Round up to next power of two. Assembly continues.

---

# MC — Macro

Fired during macro definition and expansion.

---

## MCE0001 — Macro name missing

**Cause:** `mac` directive not followed by a name.

**Triggers:**
```asm
mac                 ; missing name
    mov rax, 1
end
```

**Output:**
```
MCE0001: 'mac' requires a name
  --> src/main.s:1:1
   |
 1 |     mac
   |     ~~~
   |     expected macro name after 'mac'
   |
   = hint[MCH0001]: mac my_macro_name
```

**Recovery:** Skip to matching `end`.

---

## MCE0002 — end without matching mac

**Cause:** `end` encountered when no `mac` block is open.

**Triggers:**
```asm
end                 ; no mac opened
```

**Output:**
```
MCE0002: 'end' without matching 'mac'
  --> src/main.s:1:1
   |
 1 |     end
   |     ~~~
```

**Recovery:** Ignore. Assembly continues.

---

## MCE0003 — Invalid parameter count

**Cause:** Parameter count specification after `mac` is not a valid non-negative integer.

**Triggers:**
```asm
mac myfunc -1       ; negative param count
```

**Output:**
```
MCE0003: invalid parameter count specification
  --> src/main.s:1:11
   |
 1 |     mac myfunc -1
   |                ^^
   |                parameter count must be a non-negative integer
```

**Recovery:** Assume 0 parameters. Assembly continues.

---

## MCE0004 — Macro expansion depth exceeded

**Cause:** Macros calling macros exceed max depth (64).

**Triggers:**
```asm
mac infinite
    infinite        ; calls itself
end
infinite            ; triggers infinite recursion
```

**Output:**
```
MCE0004: macro expansion depth exceeded (max 64)
  --> src/main.s:2:5
   |
 2 |     infinite
   |     ~~~~~~~~
   |     macro 'infinite' called recursively — depth limit reached
   |
   = note[MCN0004]: call stack:
   |   infinite → infinite → infinite → ... (64 levels)
```

**Recovery:** Fatal. Assembly stops.

---

## MCE0005 — Macro redefined

**Cause:** `mac` defines a name that already exists as a macro.

**Triggers:**
```asm
mac myfunc
    nop
end
mac myfunc          ; already defined
    nop
end
```

**Output:**
```
MCE0005: macro 'myfunc' redefined
  --> src/main.s:4:5
   |
 4 |     mac myfunc
   |         ~~~~~~
   |         'myfunc' was already defined at src/main.s:1:5
   |
   = hint[MCH0005]: use different name, or remove previous definition
```

**Recovery:** New definition replaces old. Warning also emitted.

---

# SM — Semantic

Fired during semantic analysis.

---

## SME0001 — Symbol redefined

**Cause:** A label or constant is defined more than once.

**Triggers:**
```asm
myLabel:
    nop
myLabel:            ; already defined
    nop
```

**Output:**
```
SME0001: symbol 'myLabel' redefined
  --> src/main.s:3:1
   |
 3 |     myLabel:
   |     ~~~~~~~
   |     'myLabel' was first defined at src/main.s:1:1
```

**Recovery:** Keep first definition. Assembly continues.

---

## SME0002 — Undefined symbol

**Cause:** An identifier is used but never defined anywhere.

**Triggers:**
```asm
mov rax, [myBuffer]     ; myBuffer never defined
```

**Output:**
```
SME0002: undefined symbol 'myBuffer'
  --> src/main.s:1:10
   |
 1 |     mov rax, [myBuffer]
   |              ~~~~~~~~~
   |              'myBuffer' is not defined
   |
   = hint[SMH0002]: did you mean 'myBuf'?
```

**Recovery:** Emit zero for value. Assembly continues.

---

## SME0003 — Forward reference unresolved

**Cause:** A forward reference is still unresolved after the second pass.

**Output:**
```
SME0003: forward reference 'target' not resolved after second pass
  --> src/main.s:1:5
   |
 1 |     jmp target
   |         ~~~~~~
   |         'target' referenced here but never defined
```

**Recovery:** Fatal. Assembly stops.

---

# SY — Symbol Table

---

## SYE0001 — Symbol table full

**Cause:** Maximum symbol count exceeded.

**Output:**
```
SYE0001: symbol table full
  --> src/main.s:4096:1
   |
   |     maximum symbol count reached (increase MAX_SYMBOLS in include/config.inc)
```

**Recovery:** Fatal. Assembly stops.

---

## SYE0002 — Symbol name too long

**Cause:** Symbol name exceeds 255 bytes.

**Output:**
```
SYE0002: symbol name too long (max 255 bytes)
  --> src/main.s:1:1
   |
   |     symbol name truncated to 255 bytes
```

**Recovery:** Name truncated. Assembly continues.

---

## SYE0003 — extern symbol also defined locally

**Cause:** Symbol declared `extern` is also defined in same file.

**Output:**
```
SYE0003: 'printf' declared extern but also defined locally
  --> src/main.s:3:1
   |
 3 |     printf:
   |     ~~~~~~
   |     'printf' was declared extern at src/main.s:1:8
```

**Recovery:** Local definition takes precedence. Warning emitted.

---

# EX — Expression Evaluator

---

## EXE0001 — Expression syntax error

**Cause:** Invalid token sequence in constant expression.

**Output:**
```
EXE0001: expression syntax error
  --> src/main.s:1:14
   |
 1 |     mov rax, 2 ** 8
   |               ^^
   |               '**' is not a valid operator
   |
   = hint[EXH0001]: use 'shl' for power-of-two: 1 shl 8
```

---

## EXE0002 — Division by zero

**Cause:** Divisor in constant expression evaluates to zero.

**Output:**
```
EXE0002: division by zero in constant expression
  --> src/main.s:1:14
   |
 1 |     mov rax, 10 / 0
   |              ~~~~~~
   |              divisor is zero
```

---

## EXE0003 — Expression overflow

**Cause:** Intermediate value in constant expression exceeds 64-bit range.

**Output:**
```
EXE0003: expression overflow
  --> src/main.s:1:10
   |
 1 |     mov rax, 0xFFFFFFFFFFFFFFFF + 1
   |              ~~~~~~~~~~~~~~~~~~~~~~
   |              result exceeds 64-bit range
```

---

# EN — Encoder

---

## ENE0001 — Instruction not supported on target architecture

**Cause:** Instruction exists on one arch but not on the current target.

**Triggers:**
```asm
; when assembled with -arch aarch64:
cpuid               ; x86 only
```

**Output:**
```
ENE0001: 'cpuid' not supported on target architecture 'aarch64'
  --> src/main.s:1:5
   |
 1 |     cpuid
   |     ~~~~~
   |     this instruction is x86-64 specific
   |
   = hint[ENH0001]: use conditional assembly:
   |     if ARCH_AMD64
   |         cpuid
   |     end
```

---

## ENE0002 — Instruction not available on CPU profile

**Cause:** Instruction requires feature not in current CPU profile.

**Triggers:**
```asm
; with cpu generic (SSE2 only)
vaddps ymm0, ymm1, ymm2     ; requires AVX
```

**Output:**
```
ENE0002: 'vaddps' requires AVX — not available on profile 'generic'
  --> src/main.s:1:5
   |
 1 |     vaddps ymm0, ymm1, ymm2
   |     ~~~~~~
   |
   = hint[ENH0002]: use 'cpu x86_64_v3' or higher for AVX support
```

---

## ENE0003 — Immediate out of range

**Cause:** Immediate value does not fit in the encoding for this instruction form.

**Output:**
```
ENE0003: immediate out of range for 'add r/m8, imm8'
  --> src/main.s:1:10
   |
 1 |     add al, 256
   |             ^^^
   |             value 256 exceeds range 0–255 for imm8
```

---

## ENE0004 — Register size mismatch

**Cause:** Source and destination register sizes do not match.

**Triggers:**
```asm
mov rax, ebx        ; 64-bit ← 32-bit (need movzx/movsx)
```

**Output:**
```
ENE0004: register size mismatch
  --> src/main.s:1:5
   |
 1 |     mov rax, ebx
   |     ~~~~~~~~~~~~
   |     destination 'rax' is 64-bit, source 'ebx' is 32-bit
   |
   = hint[ENH0004]: movzx rax, ebx    ; zero-extend
   |                 movsx rax, ebx    ; sign-extend
```

---

## ENE0005 — Output buffer overflow

**Cause:** Encoded output exceeds maximum binary size.

**Output:**
```
ENE0005: output buffer overflow
  --> src/main.s:{line}:{col}
   |
   |     encoded output exceeded maximum binary size
```

**Recovery:** Fatal. Assembly stops.

---

## ENE0006 — AArch64 shift amount out of range

**Cause:** Shift amount in AArch64 instruction exceeds valid range.

**Triggers:**
```asm
lsl x0, x1, #65    ; max is 63 for 64-bit register
```

**Output:**
```
ENE0006: shift amount out of range for AArch64 LSL
  --> src/main.s:1:15
   |
 1 |     lsl x0, x1, #65
   |                 ^^^
   |                 shift amount 65 exceeds maximum 63 for 64-bit register
```

---

## ENE0007 — AArch64 invalid condition code

**Cause:** Unrecognized condition code suffix on AArch64 branch.

**Output:**
```
ENE0007: invalid AArch64 condition code 'XZ'
  --> src/main.s:1:5
   |
 1 |     b.XZ target
   |       ^^
   |       'XZ' is not a valid AArch64 condition code
   |
   = hint[ENH0007]: valid codes: EQ NE CS CC MI PL VS VC HI LS GE LT GT LE AL NV
```

---

## ENE0008 — RISC-V branch offset out of range

**Cause:** Branch target is beyond ±4 KiB from current PC.

**Output:**
```
ENE0008: RISC-V branch offset out of range
  --> src/main.s:1:5
   |
 1 |     beq x0, x1, far_label
   |     ~~~~~~~~~~~~~~~~~~~~~
   |     offset to 'far_label' is ±8192 — RISC-V branch range is ±4096
   |
   = hint[ENH0008]: use JAL for longer jumps (±1 MiB)
```

---

## ENE0009 — RISC-V JAL offset out of range

**Cause:** JAL target is beyond ±1 MiB from current PC.

**Output:**
```
ENE0009: RISC-V JAL offset out of range (±1 MiB)
  --> src/main.s:1:5
   |
 1 |     jal ra, very_far_label
   |     ~~~~~~~~~~~~~~~~~~~~~~
   |     offset exceeds ±1 MiB JALR range
   |
   = hint[ENH0009]: load address into register and use JALR
```

---

## ENE0010 — VEX/EVEX encoding conflict

**Cause:** Operand combination requires conflicting VEX and EVEX encodings.

**Output:**
```
ENE0010: VEX/EVEX encoding conflict
  --> src/main.s:1:5
   |
 1 |     vmovaps zmm0, ymm1
   |     ~~~~~~~~~~~~~~~~~~
   |     ZMM registers require EVEX — YMM/XMM use VEX — cannot mix
```

---

# LN — Linker

---

## LNE0001 — No sections defined

**Cause:** Source file contains no `sec` directives.

**Output:**
```
LNE0001: no sections defined
   |
   |     at least one section must be defined (e.g. sec .text)
```

**Recovery:** Fatal. Assembly stops.

---

## LNE0002 — Entry point not found

**Cause:** `_start` symbol not found in standalone build.

**Output:**
```
LNE0002: entry point '_start' not found
   |
   |     standalone binary requires a '_start' label
   |
   = hint[LNH0002]: global _start
   |                 _start:
   |                     ...
```

**Recovery:** Fatal. Assembly stops.

---

## LNE0003 — Relocation overflow

**Cause:** Relocation target is out of range for relocation type.

**Output:**
```
LNE0003: relocation overflow
  --> src/main.s:{line}:{col}
   |
   |     relocation to 'far_symbol' overflows rel32 range
```

---

## LNE0004 — Duplicate section name

**Cause:** Two `sec` directives use the same section name with conflicting flags.

**Output:**
```
LNE0004: duplicate section '.text' with conflicting flags
  --> src/main.s:5:5
   |
 5 |     sec .text write      ; but .text was readonly at line 1
   |     ~~~~~~~~~~~~~~~~
```

---

## LNE0005 — Section W+X forbidden

**Cause:** Section declared both writable and executable.

**Output:**
```
LNE0005: section '.rwx' cannot be both writable and executable
  --> src/main.s:1:5
   |
 1 |     sec .rwx write exec
   |     ~~~~~~~~~~~~~~~~~~~
   |     W+X sections are forbidden — security violation
   |
   = note[LNN0005]: W^X policy: a section is either writable OR executable, never both
```

**Recovery:** Fatal. Assembly stops.

---

# EL — ELF Output

---

## ELE0001 — ELF write error

**Cause:** Could not write ELF output file.

**Output:**
```
ELE0001: ELF output write error
   |
   |     could not write to output file — check disk space and permissions
```

**Recovery:** Fatal.

---

## ELE0002 — ELF no .text section

**Cause:** ELF output requires at least one executable section.

**Output:**
```
ELE0002: ELF output requires at least one executable section
   |
   |     define 'sec .text' with executable flag
```

**Recovery:** Fatal.

---

# PF — PE Format Output

---

## PFE0001 — PE write error

**Cause:** Could not write PE32+ output file.

**Output:**
```
PFE0001: PE output write error
   |
   |     could not write to output file — check disk space and permissions
```

---

## PFE0002 — PE no .text section

**Cause:** PE output has no executable section to emit.

**Output:**
```
PFE0002: PE output requires at least one executable section
```

---

# FB — Flat Binary Output

---

## FBE0001 — Flat binary write error

**Output:**
```
FBE0001: flat binary write error
   |
   |     could not write output file
```

---

# UP — UPK Package

---

## UPE0001 — Signing key not found

**Cause:** UPK format requires signing key not present.

**Output:**
```
UPE0001: UPK signing key not found
   |
   |     UPK format requires a signing key
   |
   = hint[UPH0001]: generate a key with 'utasm --keygen'
```

**Recovery:** Fatal.

---

## UPE0002 — UPK manifest invalid

**Cause:** Package manifest is malformed or missing required fields.

**Output:**
```
UPE0002: UPK manifest invalid
   |
   |     manifest missing required field: 'version'
```

---

# CP — CPU / Architecture

---

## CPE0001 — Unknown CPU profile

**Cause:** `cpu` directive specifies unrecognized profile name.

**Triggers:**
```asm
cpu superchip       ; unknown profile
```

**Output:**
```
CPE0001: unknown CPU profile 'superchip'
  --> src/main.s:1:5
   |
 1 |     cpu superchip
   |         ~~~~~~~~~
   |         'superchip' is not a recognized CPU profile
   |
   = hint[CPH0001]: known profiles: generic, x86_64_v3, skylake, znver3
```

---

## CPE0002 — Architecture mismatch

**Cause:** Instruction targets architecture different from active target.

**Output:**
```
CPE0002: architecture mismatch — 'cpuid' is x86-64 only, target is 'riscv64'
  --> src/main.s:1:5
```

---

# DW — DWARF / Debug

---

## DWE0001 — DWARF emission error

**Cause:** Error generating DWARF v5 debug information.

**Output:**
```
DWE0001: DWARF debug info emission failed
   |
   |     could not generate .debug_info section
```

---

# IC — Include

---

## ICE0001 — Include file not found

**Cause:** `inc` directive references a file that does not exist.

**Triggers:**
```asm
inc "missing.asm"
```

**Output:**
```
ICE0001: include file not found: 'missing.asm'
  --> src/main.s:1:5
   |
 1 |     inc "missing.asm"
   |         ~~~~~~~~~~~~~
   |         file not found in search path
   |
   = note[ICN0001]: search path: ./ /usr/local/lib/utasm/
```

**Recovery:** Fatal. Assembly stops.

---

## ICE0002 — Circular inclusion

**Cause:** File includes itself directly or indirectly.

**Triggers:**
```asm
; file a.asm includes b.asm
; b.asm includes a.asm → circular
```

**Output:**
```
ICE0002: circular inclusion detected
  --> src/b.asm:1:5
   |
 1 |     inc "a.asm"
   |         ~~~~~~~
   |         inclusion chain: a.asm → b.asm → a.asm
```

**Recovery:** Fatal. Assembly stops.

---

## ICE0003 — Include nesting depth exceeded

**Cause:** More than 32 levels of nested includes.

**Output:**
```
ICE0003: include nesting depth exceeded (max 32)
  --> src/main.s:1:5
   |
 1 |     inc "deep.asm"
   |         ~~~~~~~~~~
   |         nesting depth 33 exceeds maximum of 32
```

**Recovery:** Fatal. Assembly stops.

---

# DA — Data

---

## DAE0001 — Data value out of range

**Cause:** Value does not fit in the declared data size.

**Triggers:**
```asm
d8 256              ; max for d8 is 255
d8 -1               ; signed negative in unsigned context
```

**Output:**
```
DAE0001: value out of range for d8
  --> src/main.s:1:4
   |
 1 |     d8 256
   |        ~~~
   |        value 256 exceeds range 0–255 for d8
   |
   = hint[DAH0001]: use d16 for values up to 65535
```

---

## DAE0002 — Data count must be positive

**Cause:** Count operand in `d8 COUNT VALUE` is zero or negative.

**Triggers:**
```asm
d8 0 0xFF           ; count must be >= 1
d8 -4 ?             ; negative count
```

**Output:**
```
DAE0002: data count must be a positive integer
  --> src/main.s:1:4
   |
 1 |     d8 0 0xFF
   |        ^
   |        count must be >= 1
```

---

# AL — Alignment

---

## ALE0001 — Alignment value not power of two

**Cause:** `align` value is not a power of two.

**Output:**
```
ALE0001: alignment value must be a power of two
  --> src/main.s:1:7
   |
 1 |     align 3
   |           ^
   |           '3' is not a power of two
   |
   = hint[ALH0001]: valid values: 1, 2, 4, 8, 16, 32, 64...
```

---

## ALE0002 — Alignment exceeds section alignment

**Cause:** Data alignment request exceeds the section's own alignment.

**Output:**
```
ALE0002: alignment 64 exceeds section alignment 16
  --> src/main.s:1:7
   |
   |     increase section alignment with 'sec .data align=64'
```

---

# TY — Type

---

## TYE0001 — Register class mismatch

**Cause:** Instruction requires specific register class but wrong class provided.

**Triggers:**
```asm
movaps xmm0, rax    ; movaps needs XMM source, not GPR
```

**Output:**
```
TYE0001: register class mismatch
  --> src/main.s:1:14
   |
 1 |     movaps xmm0, rax
   |                  ^^^
   |                  'movaps' requires XMM register, found GPR 'rax'
```

---

## TYE0002 — Size specifier conflict

**Cause:** Explicit size specifier conflicts with operand size.

**Triggers:**
```asm
mov dword [rax], rax    ; dword ptr but rax is 64-bit
```

**Output:**
```
TYE0002: size specifier conflict
  --> src/main.s:1:5
   |
 1 |     mov dword [rax], rax
   |         ~~~~~            ~~~
   |         'dword' (32-bit) conflicts with 'rax' (64-bit)
```

---

# SX — Security

---

## SXE0001 — W+X section forbidden

**Cause:** Attempt to create section with both write and execute permissions.

**Output:**
```
SXE0001: W+X (writable+executable) section is forbidden
  --> src/main.s:1:5
   |
 1 |     sec .shellcode write exec
   |     ~~~~~~~~~~~~~~~~~~~~~~~~~
   |     security policy: sections cannot be both writable and executable
```

**Recovery:** Fatal. Assembly stops.

---

# IT — Internal

These indicate bugs in utasm itself. File an issue if you see one.

---

## ITE0001 — Arena allocator out of memory

**Output:**
```
ITE0001: arena allocator out of memory
   |
   |     internal: arena exhausted — this is a utasm bug, please report
```

**Recovery:** Fatal.

---

## ITE0002 — Null pointer in internal API

**Output:**
```
ITE0002: null pointer in internal API
   |
   |     internal: unexpected null pointer — this is a utasm bug, please report
```

**Recovery:** Fatal.

---

## ITE0003 — Inconsistent assembler context

**Output:**
```
ITE0003: inconsistent assembler context state
   |
   |     internal: pipeline state corrupted — this is a utasm bug, please report
```

**Recovery:** Fatal.

---

## ITE0004 — Encoder dispatch table corrupt

**Output:**
```
ITE0004: encoder dispatch table corrupt
   |
   |     internal: dispatch table integrity check failed — please report
```

**Recovery:** Fatal.

---

## ITE0005 — Symbol table integrity check failed

**Output:**
```
ITE0005: symbol table integrity check failed
   |
   |     internal: hash table corrupted — please report
```

**Recovery:** Fatal.

---

# CL — CLI

---

## CLE0001 — Unknown flag

**Cause:** Unrecognized command-line flag.

**Triggers:**
```sh
utasm --unknown-flag file.asm
```

**Output:**
```
CLE0001: unknown flag '--unknown-flag'
   |
   = hint[CLH0001]: run 'utasm --help' for valid options
```

---

## CLE0002 — Missing output file

**Cause:** `-o` flag provided without a filename.

**Output:**
```
CLE0002: '-o' requires an output filename
   |
   = hint[CLH0002]: utasm -f elf64 main.asm -o main
```

---

## CLE0003 — No input file

**Cause:** No source file provided on command line.

**Output:**
```
CLE0003: no input file specified
   |
   = hint[CLH0003]: utasm -f elf64 main.asm -o main
```

---

# CO — Compatibility / ABI

---

## COE0001 — Calling convention violation

**Cause:** Function modifies callee-saved register without save/restore.

**Output:**
```
COE0001: possible calling convention violation
  --> src/main.s:15:5
   |
15 |     mov rbx, rax
   |     ~~~~~~~~~~~~
   |     'rbx' is callee-saved in SysV AMD64 ABI but modified without push/pop
   |
   = note[CON0001]: callee-saved: RBX RBP R12 R13 R14 R15
   = hint[COH0001]: push rbx at function entry, pop rbx before ret
```

---

## COE0002 — Stack not aligned at call site

**Cause:** RSP not 16-byte aligned before CALL instruction.

**Output:**
```
COE0002: stack may not be 16-byte aligned at call site
  --> src/main.s:2:5
   |
 2 |     call my_function
   |     ~~~~~~~~~~~~~~~~
   |     SysV AMD64 ABI requires RSP % 16 == 0 before CALL
   |
   = hint[COH0002]: sub rsp, 8 / call my_function / add rsp, 8
```

---

# Warnings

Warnings never stop assembly. All suppressible with `-Wno-XX0000`.
Promote all warnings to errors with `-Werror`.

---

## LXW0001 — Unused label

**Output:**
```
LXW0001: label 'myLabel' defined but never referenced
  --> src/main.s:1:1
```

**Suppress:** `-Wno-LX0001`

---

## PRW0001 — Implicit data size assumed

**Output:**
```
PRW0001: implicit data size assumed — use d8/d16/d32/d64 explicitly
  --> src/main.s:1:5
```

**Suppress:** `-Wno-PR0001`

---

## ENW0001 — NOP inserted for alignment

**Output:**
```
ENW0001: NOP inserted for alignment at 0x00401234 (performance note)
  --> src/main.s:1:5
```

**Suppress:** `-Wno-EN0001`

---

## SYW0001 — extern symbol never referenced

**Output:**
```
SYW0001: 'printf' declared extern but never used
  --> src/main.s:1:8
```

**Suppress:** `-Wno-SY0001`

---

## MCW0001 — Macro defined but never used

**Output:**
```
MCW0001: macro 'my_macro' defined but never called
  --> src/main.s:1:5
```

**Suppress:** `-Wno-MC0001`

---

## COW0001 — Instruction not portable

**Output:**
```
COW0001: 'cpuid' is x86-64 specific — not portable to AArch64 or RISC-V
  --> src/main.s:3:5
   |
   = hint[COH0001]: use conditional assembly with 'if ARCH_AMD64'
```

**Suppress:** `-Wno-CO0001`

---

# Exit Codes

```asm
; defined in include/constant.inc
EXIT_OK             equ 0   ; assembly successful, no errors
EXIT_USAGE          equ 1   ; invalid CLI arguments
EXIT_OOM            equ 2   ; arena out of memory
EXIT_IO_ERROR       equ 3   ; file read/write failure
EXIT_PARSE_ERROR    equ 4   ; LX/PR/MC/SM/SY/EX errors
EXIT_ENCODER_ERROR  equ 5   ; EN/IS errors
EXIT_LINKER_ERROR   equ 6   ; LN/RL errors
EXIT_INTERNAL       equ 7   ; IT internal error — report this
EXIT_ASSERTION      equ 8   ; assertion failure — report this
EXIT_SIGNAL         equ 9   ; terminated by signal
```

---

# Complete Category Index

## Errors (E)

| Code | Category | Description |
|---|---|---|
| LXExxxx | Lexer | Characters, tokens, literals |
| PRExxxx | Parser | Syntax, grammar, structure |
| MCExxxx | Macro | Definition, expansion, recursion |
| SMExxxx | Semantic | Symbol usage, context |
| SYExxxx | Symbol table | Definitions, forward refs |
| EXExxxx | Expression | Arithmetic, constants |
| SCExxxx | Scope | Local labels, proc boundaries |
| ENExxxx | Encoder | Instruction encoding |
| ISExxxx | ISA | Instruction availability |
| LNExxxx | Linker | Symbol resolution, layout |
| RLExxxx | Relocation | Reloc type, overflow |
| ELExxxx | ELF output | ELF64 violations |
| PFExxxx | PE output | PE32+/COFF violations |
| FBExxxx | Flat binary | Flat format violations |
| UPExxxx | UPK | Package format violations |
| CPExxxx | CPU/Arch | Feature flags, profiles |
| DWExxxx | DWARF | Debug info failures |
| OPExxxx | Optimizer | Post-encoding errors |
| HPExxxx | Hot-patch | Self-patch errors |
| RFExxxx | Profiler | Profiler errors |
| ARExxxx | Arena | Memory management |
| BSExxxx | Bootstrap | Self-hosting pipeline |
| DIExxxx | Directive | General directive errors |
| SEExxxx | Section | Section flags, permissions |
| DAExxxx | Data | d8/d16/d32/d64 violations |
| ALExxxx | Alignment | Alignment errors |
| ICExxxx | Include | File, circular, depth |
| VSExxxx | Visibility | Export/import conflicts |
| SIExxxx | SIMD | Register class, width |
| FPExxxx | Float | x87, float literals |
| PVExxxx | Privilege | Ring level errors |
| MMExxxx | Memory model | Mode violations |
| CLExxxx | CLI | Argument errors |
| TYExxxx | Type | Size, type mismatch |
| SXExxxx | Security | W^X violations |
| COExxxx | Compatibility | ABI, calling convention |
| ITExxxx | Internal | utasm bugs — always report |

## Warnings (W)

| Code | Category |
|---|---|
| LXWxxxx | Lexer |
| PRWxxxx | Parser |
| MCWxxxx | Macro |
| SMWxxxx | Semantic |
| SYWxxxx | Symbol table |
| ENWxxxx | Encoder |
| LNWxxxx | Linker |
| CPWxxxx | CPU/Arch |
| COWxxxx | Compatibility/Portability |

## Notes (N) and Hints (H)

Same category prefix as parent error.
Notes provide context. Hints provide actionable fixes.

```
LXE0001 → note:  LXN0001
        → hint:  LXH0001
PRE0009 → hint:  PRH0009  (did you mean X?)
ENE0001 → hint:  ENH0001
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
