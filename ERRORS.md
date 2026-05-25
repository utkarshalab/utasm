# utasm — Error Reference

> Complete documentation for every error, warning, note, and hint code.
> Every code has: category, cause, triggering example, exact output, recovery behavior, and related hints.
> This document is the ground truth. If a code is not here, it does not exist in utasm.

---

## Output Level Reference

| Prefix | Range | Severity | Meaning |
|---|---|---|---|
| `E` | E1xx–E35xx | Fatal | Assembly stops after current pass |
| `W` | W1xx–W20xx | Warning | Configurable — suppress with `-Wno-X`, promote with `-Werror` |
| `N` | N1xx–N5xx | Note | Informational context attached to an error |
| `H` | H1xx–H5xx | Hint | Actionable fix suggestion attached to an error |

---

## Output Format

Every error follows this exact format:

```
{severity}[{code}]: {message}
  --> {filename}:{line}:{col}
   |
{line-1}|     {source line before}
{line}  |     {source line with error}
   |     {col_start spaces}{^^^^ underline}
   |
   = note: {note message}
   = hint[{hint_code}]: {hint message}
   |
   → expanded from macro '{name}' at {file}:{line}
```

---

## Error Categories

```
E1xx   Lexer errors          (characters, tokens, literals)
E2xx   Parser errors         (syntax, grammar, structure)
E3xx   Macro errors          (definition, expansion, recursion)
E4xx   Semantic errors       (symbols, labels, scopes)
E5xx   Encoder errors        (instruction encoding, operands)
E6xx   Linker errors         (symbols, relocations, sections)
E7xx   CPU errors            (feature flags, availability)
E8xx   Internal errors       (utasm bugs — report these)
E9xx   Expression errors     (arithmetic, constants)
E10xx  Directive errors      (section, global, align, times)
E11xx  Include errors        (file not found, circular, depth)
E12xx  Section errors        (flags, overlap, permissions)
E13xx  Visibility errors     (scope, export/import conflicts)
E14xx  Relocation errors     (type, overflow, unsupported)
E15xx  ELF output errors     (ELF format violations)
E16xx  PE output errors      (PE/COFF format violations)
E17xx  Flat binary errors    (flat format violations)
E18xx  Package errors        (upk format violations)
E19xx  Debug info errors     (DWARF generation failures)
E20xx  Data errors           (DB/DW/DD/DQ violations)
E21xx  Alignment errors      (section, data, instruction)
E22xx  Scope errors          (local labels, proc boundaries)
E23xx  Type errors           (size specifiers, conflicts)
E24xx  Privilege errors      (ring level, protected instructions)
E25xx  SIMD errors           (register class, width, alignment)
E26xx  Memory model errors   (flat, segmented, mode violations)
E27xx  Self-patch errors     (binary modification validation)
E28xx  Package errors        (upm metadata, dependencies)
E29xx  Security errors       (W^X, writable+executable)
E30xx  Compatibility errors  (ABI, calling convention)
E31xx  Assembler directives  (TIMES, ALIGN, RESB, STRUC, INCBIN)
E32xx  Preprocessor errors   (%ASSIGN, %SEL, %ERROR, %PATHSEARCH)
E33xx  Multi-file/link errors (archive, linker script, PHDR)
E34xx  Floating point errors  (x87 stack, float literals, SSE size)
E35xx  UPK/package errors     (manifest, signature, dependencies)
```

---

# E1xx — Lexer Errors

Fired during tokenization. Recovery: skip to next newline and continue lexing.

---

## E101 — Invalid character in source

**Cause:** A character that is not part of the utasm character set appears in the source.

**Triggers:**
```asm
mov rax, @value     ; @ is not a valid character
mov rbx, £100       ; £ is not ASCII
```

**Output:**
```
error[E101]: invalid character in source
  --> src/main.s:1:10
   |
 1 |     mov rax, @value
   |              ^
   |              character '@' (0x40) is not valid here
   |
   = hint[H101]: valid identifier characters are [a-zA-Z0-9_]
```

**Recovery:** Character skipped. Lexer continues from next character.
**Related hints:** H101

---

## E102 — Unterminated string literal

**Cause:** A string opened with `"` is not closed before end of line or end of file.

**Triggers:**
```asm
db "hello world        ; missing closing quote
db "line one
db "line two"          ; E102 fires on the first unterminated line
```

**Output:**
```
error[E102]: unterminated string literal
  --> src/main.s:1:4
   |
 1 |     db "hello world
   |        ^~~~~~~~~~~~~ string starts here, never closed
   |
   = note: string literals must be closed on the same line
   = hint[H102]: add closing '"' before end of line
```

**Recovery:** Skip to end of current line. Lexer continues on next line.
**Related hints:** H102

---

## E103 — Unterminated character literal

**Cause:** A character literal opened with `'` is not closed.

**Triggers:**
```asm
mov al, 'A          ; missing closing quote
mov bl, 'AB'        ; E104 fires instead (too many chars)
```

**Output:**
```
error[E103]: unterminated character literal
  --> src/main.s:1:9
   |
 1 |     mov al, 'A
   |             ^~ character literal starts here, never closed
   |
   = hint[H103]: character literals require exactly one character: 'A'
```

**Recovery:** Skip to end of line.
**Related hints:** H103

---

## E104 — Invalid escape sequence

**Cause:** A backslash in a string or character literal is followed by an unrecognized character.

**Valid escape sequences:** `\n \t \r \\ \' \" \0 \a \b \f \v \xHH \uHHHH \UHHHHHHHH`

**Triggers:**
```asm
db "hello\qworld"     ; \q is not a valid escape
db "path\dir\file"    ; \d and \f are not valid (use \\ for backslash)
```

**Output:**
```
error[E104]: invalid escape sequence
  --> src/main.s:1:11
   |
 1 |     db "hello\qworld"
   |               ^^
   |               '\q' is not a recognized escape sequence
   |
   = note: valid escapes: \n \t \r \\ \' \" \0 \a \b \f \v \xHH \uHHHH
   = hint[H104]: did you mean '\\' for a literal backslash?
```

**Recovery:** The invalid escape is treated as the literal character after `\`. Lexing continues.
**Related hints:** H104

---

## E105 — Malformed binary literal

**Cause:** A binary literal prefix (`0b` or `0y`) is not followed by binary digits, or contains non-binary digits.

**Triggers:**
```asm
mov al, 0b          ; prefix with no digits
mov bl, 0b1012      ; '2' is not a binary digit
mov cl, 0b_101      ; underscore separators not supported
```

**Output:**
```
error[E105]: malformed binary literal
  --> src/main.s:2:9
   |
 2 |     mov bl, 0b1012
   |             ~~~~~~^
   |                   digit '2' is not valid in a binary literal (only 0 and 1)
   |
   = hint[H105]: binary literals contain only digits 0 and 1: 0b1010
```

**Recovery:** Stop scanning literal at invalid character. Use digits scanned so far as value.
**Related hints:** H105

---

## E106 — Malformed octal literal

**Cause:** An octal literal prefix (`0o` or `0q`) is followed by non-octal digits (8 or 9).

**Triggers:**
```asm
mov al, 0o          ; prefix with no digits
mov bl, 0o789       ; '8' and '9' are not octal digits
```

**Output:**
```
error[E106]: malformed octal literal
  --> src/main.s:2:9
   |
 2 |     mov bl, 0o789
   |             ~~~~^
   |                 digit '8' is not valid in an octal literal (only 0–7)
   |
   = hint[H106]: octal literals use digits 0–7: 0o755
```

**Recovery:** Stop at invalid character. Use digits scanned so far.
**Related hints:** H106

---

## E107 — Malformed hex literal

**Cause:** A hex literal prefix (`0x`, `0h`, or `$`) is not followed by any hex digits.

**Triggers:**
```asm
mov al, 0x          ; prefix with no digits
mov bl, 0xGG        ; G is not a hex digit (E101 fires for G, E107 for empty hex)
```

**Output:**
```
error[E107]: malformed hex literal
  --> src/main.s:1:9
   |
 1 |     mov al, 0x
   |             ^^
   |             hex literal prefix '0x' must be followed by at least one hex digit
   |
   = hint[H107]: hex literals: 0xFF, 0h1A2B, $CAFE
```

**Recovery:** Emit value 0. Continue from character after prefix.
**Related hints:** H107

---

## E108 — Malformed decimal literal

**Cause:** A decimal literal contains non-decimal characters after the first digit. (Rare — usually caught by E101 first.)

**Triggers:**
```asm
mov al, 12abc       ; letters after decimal digits (abc would normally be separate token)
```

**Output:**
```
error[E108]: malformed decimal literal
  --> src/main.s:1:9
   |
 1 |     mov al, 12abc
   |             ~~^^^
   |               unexpected characters in decimal literal
```

**Recovery:** Stop at first non-decimal character. Use digits scanned so far.
**Related hints:** H108

---

## E109 — Integer literal overflow

**Cause:** An integer literal exceeds the maximum value of a 64-bit unsigned integer (18446744073709551615).

**Triggers:**
```asm
mov rax, 99999999999999999999    ; > 2^64 - 1
dq 0xFFFFFFFFFFFFFFFF1           ; > 64-bit max
```

**Output:**
```
error[E109]: integer literal overflow
  --> src/main.s:1:10
   |
 1 |     mov rax, 99999999999999999999
   |              ^^^^^^^^^^^^^^^^^^^^
   |              value exceeds maximum 64-bit unsigned integer (18446744073709551615)
   |
   = note: maximum: 0xFFFFFFFFFFFFFFFF = 18446744073709551615
```

**Recovery:** Use value 0xFFFFFFFFFFFFFFFF (clamped). Assembly continues.
**Related hints:** none

---

## E110 — Float literal overflow

**Cause:** A floating-point literal exceeds IEEE 754 double precision range.

**Triggers:**
```asm
dq 1.8e309          ; > DBL_MAX (1.7976931348623157e+308)
```

**Output:**
```
error[E110]: float literal overflow
  --> src/main.s:1:4
   |
 1 |     dq 1.8e309
   |        ^^^^^^^
   |        value exceeds maximum IEEE 754 double precision
   |
   = note: maximum double: 1.7976931348623157e+308
```

**Recovery:** Use +infinity. Assembly continues.
**Related hints:** none

---

## E111 — Invalid identifier character

**Cause:** An identifier contains a character that is not alphanumeric or underscore after the first character.

**Triggers:**
```asm
my-label:           ; hyphen not valid in identifier
some.field:         ; dot not valid in identifier (use local labels)
```

**Output:**
```
error[E111]: invalid identifier character
  --> src/main.s:1:3
   |
 1 |     my-label:
   |       ^
   |       '-' is not valid in an identifier
   |
   = note: identifiers may contain [a-zA-Z0-9_] and must start with [a-zA-Z_]
   = hint[H111]: use underscore instead: 'my_label'
```

**Recovery:** Identifier ends at invalid character. Remainder is treated as separate tokens.
**Related hints:** H111

---

## E112 — Identifier too long

**Cause:** An identifier exceeds MAX_TOKEN_LEN (4096) characters.

**Triggers:**
```asm
; identifier with 4097+ characters
averylongnamethatgoeson...(4097 chars)...end:
```

**Output:**
```
error[E112]: identifier too long
  --> src/main.s:1:1
   |
 1 |     averylongname...
   |     ^~~~~~~~~~~~~~~~
   |     identifier exceeds maximum length of 4096 characters (found 4097)
```

**Recovery:** Identifier truncated to 4096 characters. Assembly continues.
**Related hints:** none

---

## E113 — Unexpected end of file in comment

**Cause:** A block comment `/* ... */` is not closed before end of file.

**Triggers:**
```asm
; this is the last line of the file
/* this comment never closes
```

**Output:**
```
error[E113]: unexpected end of file in block comment
  --> src/main.s:2:1
   |
 2 |     /* this comment never closes
   |     ^~ block comment opened here
   |
   = hint[H113]: close the comment with '*/'
```

**Recovery:** End of file treated as end of comment. Assembly continues (file is empty at this point).
**Related hints:** H113

---

## E114 — Block comment nesting depth exceeded

**Cause:** Block comments are nested more than 32 levels deep.

**Triggers:**
```asm
/* level 1 /* level 2 /* ... /* level 33 */ */ ... */
```

**Output:**
```
error[E114]: block comment nesting depth exceeded
  --> src/main.s:1:40
   |
 1 |     /* level 1 /* level 2 /* ... /* level 33
   |                                    ^^
   |                                    maximum nesting depth is 32
```

**Recovery:** Ignore additional nesting. Continue parsing as if depth is 32.
**Related hints:** none

---

## E115 — Invalid UTF-8 sequence

**Cause:** A byte sequence in a string literal or source file is not valid UTF-8.

**Triggers:**
```asm
db "hello", 0xFF, "world"   ; 0xFF alone is not valid UTF-8
```

**Output:**
```
error[E115]: invalid UTF-8 sequence
  --> src/main.s:1:15
   |
 1 |     db "hello\xffworld"
   |               ^^^^
   |               byte sequence 0xFF is not valid UTF-8
   |
   = note: source files must be valid UTF-8 encoded text
   = hint[H115]: use explicit byte values: db 0xFF
```

**Recovery:** Invalid bytes replaced with U+FFFD (replacement character). Assembly continues.
**Related hints:** H115

---

# E2xx — Parser Errors

Fired during parsing. Recovery: skip tokens until next newline or known-safe boundary.

---

## E201 — Unexpected token

**Cause:** The parser encounters a token it does not expect in the current context.

**Triggers:**
```asm
mov rax,, rbx       ; double comma
mov , rax           ; operand before register
+ mov rax, rbx      ; leading operator
```

**Output:**
```
error[E201]: unexpected token
  --> src/main.s:1:9
   |
 1 |     mov rax,, rbx
   |             ^
   |             unexpected ',' — expected register, memory, or immediate operand
```

**Recovery:** Skip token. Attempt to continue parsing current statement.
**Related hints:** H201

---

## E202 — Expected operand, found none

**Cause:** An instruction that requires operands has none.

**Triggers:**
```asm
mov                 ; MOV requires 2 operands
add                 ; ADD requires 2 operands
push                ; PUSH requires 1 operand
```

**Output:**
```
error[E202]: expected operand, found none
  --> src/main.s:1:4
   |
 1 |     mov
   |     ~~~
   |     'mov' requires 2 operands
   |
   = note: MOV syntax: mov destination, source
   = hint[H202]: mov rax, rbx
```

**Recovery:** Skip instruction. Continue from next line.
**Related hints:** H202

---

## E203 — Expected register operand

**Cause:** An operand position that requires a register receives something else.

**Triggers:**
```asm
mov [rax], [rbx]    ; destination [rax] ok, source [rbx] is memory (two memory operands)
                    ; E513 fires for this case
push [rax + 8]      ; this is actually valid — push memory
```

**Output:**
```
error[E203]: expected register operand
  --> src/main.s:1:5
   |
 1 |     mul [rax]
   |         ^^^^^
   |         MUL requires a register operand, found memory
   |
   = note: MUL operates on rDX:rAX implicitly
   = hint[H203]: mul rcx
```

**Recovery:** Skip operand. Continue.
**Related hints:** H203

---

## E204 — Expected immediate operand

**Cause:** An operand position that requires an immediate value receives something else.

**Triggers:**
```asm
int rax             ; INT requires an immediate, not a register
ret rax             ; RET imm16 requires an immediate
```

**Output:**
```
error[E204]: expected immediate operand
  --> src/main.s:1:5
   |
 1 |     int rax
   |         ^^^
   |         'int' requires an immediate value (0–255), found register 'rax'
   |
   = hint[H204]: int 0x80
```

**Recovery:** Skip instruction.
**Related hints:** H204

---

## E205 — Expected memory operand

**Cause:** An operand position that requires a memory reference receives a register or immediate.

**Triggers:**
```asm
lea rax, rbx        ; LEA source must be memory
lgdt rax            ; LGDT requires memory operand
```

**Output:**
```
error[E205]: expected memory operand
  --> src/main.s:1:10
   |
 1 |     lea rax, rbx
   |              ^^^
   |              'lea' source operand must be a memory address, found register 'rbx'
   |
   = hint[H205]: lea rax, [rbx + 8]
```

**Recovery:** Skip instruction.
**Related hints:** H205

---

## E206 — Expected label

**Cause:** A directive that requires a label name (like GLOBAL or EXTERN) receives something else.

**Triggers:**
```asm
global 42           ; label name expected, not a number
extern "name"       ; label name expected, not a string
```

**Output:**
```
error[E206]: expected label name
  --> src/main.s:1:8
   |
 1 |     global 42
   |            ^^
   |            expected identifier for label name, found integer literal '42'
   |
   = hint[H206]: global my_function
```

**Recovery:** Skip directive.
**Related hints:** H206

---

## E207 — Expected instruction or directive

**Cause:** A line begins with a token that is neither an instruction mnemonic nor a directive.

**Triggers:**
```asm
42 mov rax, rbx     ; line starts with integer
"label": nop        ; string cannot be a label
```

**Output:**
```
error[E207]: expected instruction or directive
  --> src/main.s:1:1
   |
 1 |     42 mov rax, rbx
   |     ^^
   |     expected instruction mnemonic, directive, or label — found integer literal '42'
```

**Recovery:** Skip to next newline.
**Related hints:** H207

---

## E208 — Mismatched brackets in expression

**Cause:** Opening and closing brackets do not match in a memory expression or arithmetic expression.

**Triggers:**
```asm
mov rax, [rbx + (4 * 3]    ; ) expected before ]
mov rbx, (rax + 4))        ; extra )
```

**Output:**
```
error[E208]: mismatched brackets in expression
  --> src/main.s:1:22
   |
 1 |     mov rax, [rbx + (4 * 3]
   |                     ^      ^
   |                     '(' opened here
   |                            ']' closes '[', not '('
   |
   = hint[H208]: mov rax, [rbx + (4 * 3)]
```

**Recovery:** Insert missing close bracket. Continue.
**Related hints:** H208

---

## E209 — Missing closing bracket

**Cause:** A `[` in a memory operand is not closed before end of statement.

**Triggers:**
```asm
mov rax, [rbx + 8      ; missing ]
```

**Output:**
```
error[E209]: missing closing bracket
  --> src/main.s:1:10
   |
 1 |     mov rax, [rbx + 8
   |              ^ memory operand opened here, never closed
   |
   = hint[H209]: mov rax, [rbx + 8]
```

**Recovery:** Insert `]` at end of operand. Continue.
**Related hints:** H209

---

## E210 — Too many operands

**Cause:** An instruction receives more operands than its maximum.

**Triggers:**
```asm
mov rax, rbx, rcx   ; MOV takes 2 operands, not 3
nop rax             ; NOP takes 0 operands
ret 8, 16           ; RET imm16 takes at most 1 operand
```

**Output:**
```
error[E210]: too many operands
  --> src/main.s:1:15
   |
 1 |     mov rax, rbx, rcx
   |                   ^^^
   |                   'mov' accepts at most 2 operands, found 3
```

**Recovery:** Ignore extra operands. Encode with first N operands.
**Related hints:** H210

---

## E211 — Too few operands

**Cause:** An instruction receives fewer operands than its minimum.

**Triggers:**
```asm
mov rax             ; MOV requires 2 operands
imul rbx, rcx      ; IMUL 3-operand form requires 3 operands (this is actually valid 2-op)
```

**Output:**
```
error[E211]: too few operands
  --> src/main.s:1:4
   |
 1 |     mov rax
   |     ~~~
   |     'mov' requires 2 operands, found 1
   |
   = note: MOV syntax: mov destination, source
   = hint[H211]: mov rax, rbx
```

**Recovery:** Skip instruction.
**Related hints:** H211

---

## E212 — Invalid addressing mode

**Cause:** The combination of base, index, scale, and displacement in a memory operand is not valid for x86-64.

**Triggers:**
```asm
mov rax, [eax]          ; 32-bit base in 64-bit mode without addr32 override
mov rax, [rax + rbx + rcx] ; two index registers
mov rax, [rax * 2]         ; no base with scaled index (valid but unusual — actually OK)
```

**Output:**
```
error[E212]: invalid addressing mode
  --> src/main.s:1:10
   |
 1 |     mov rax, [rax + rbx + rcx]
   |              ^~~~~~~~~~~~~~~~~
   |              only one index register is permitted
   |
   = note: valid form: [base + index*scale + displacement]
```

**Recovery:** Skip operand.
**Related hints:** H212

---

## E213 — Base register must be 64-bit

**Cause:** A 32-bit or 16-bit register is used as a base register in 64-bit mode without an address-size override.

**Triggers:**
```asm
mov rax, [eax + 8]     ; eax is 32-bit
mov rbx, [ax]          ; ax is 16-bit
```

**Output:**
```
error[E213]: base register must be 64-bit in 64-bit mode
  --> src/main.s:1:10
   |
 1 |     mov rax, [eax + 8]
   |               ^^^
   |               'eax' is 32-bit — use 'rax' for addressing in 64-bit mode
   |
   = hint[H213]: mov rax, [rax + 8]
```

**Recovery:** Treat register as 64-bit equivalent. Continue.
**Related hints:** H213

---

## E214 — RSP cannot be used as index register

**Cause:** RSP (or ESP) is used as the index register in a SIB addressing mode. RSP encodes as "no index" in the SIB byte.

**Triggers:**
```asm
mov rax, [rbx + rsp]        ; RSP as index
mov rax, [rsp + rsp*2]      ; RSP as both base and index
```

**Output:**
```
error[E214]: RSP cannot be used as an index register
  --> src/main.s:1:10
   |
 1 |     mov rax, [rbx + rsp]
   |                      ^^^
   |                      'rsp' encodes as "no index" in SIB and cannot be an index
   |
   = note: RSP can be used as a base register: [rsp + 8]
   = hint[H214]: use a different register as index: [rbx + rcx]
```

**Recovery:** Skip operand.
**Related hints:** H214

---

## E215 — Invalid scale factor

**Cause:** The scale in a scaled-index addressing mode is not 1, 2, 4, or 8.

**Triggers:**
```asm
mov rax, [rbx + rcx*3]     ; scale 3 is not valid
mov rax, [rbx + rcx*16]    ; scale 16 is not valid
mov rax, [rbx + rcx*0]     ; scale 0 is not valid (use [rbx] or [rbx + rcx])
```

**Output:**
```
error[E215]: invalid scale factor
  --> src/main.s:1:20
   |
 1 |     mov rax, [rbx + rcx*3]
   |                         ^
   |                         scale '3' is not valid — must be 1, 2, 4, or 8
   |
   = hint[H215]: valid scales: [rbx + rcx*1], [rbx + rcx*2], [rbx + rcx*4], [rbx + rcx*8]
```

**Recovery:** Use scale 1.
**Related hints:** H215

---

## E216 — Displacement out of range for addressing

**Cause:** A displacement in a memory operand does not fit in a signed 32-bit value.

**Triggers:**
```asm
mov rax, [rbx + 0x100000000]   ; displacement > INT32_MAX
```

**Output:**
```
error[E216]: displacement out of range for addressing mode
  --> src/main.s:1:16
   |
 1 |     mov rax, [rbx + 0x100000000]
   |                     ^^^^^^^^^^^
   |                     displacement 0x100000000 does not fit in 32 bits (max: 0x7FFFFFFF)
   |
   = hint[H216]: load address into register first: mov rcx, 0x100000000 / add rcx, rbx
```

**Recovery:** Clamp to INT32_MAX.
**Related hints:** H216

---

## E217 — Segment override invalid here

**Cause:** A segment override prefix is used in a context where it is not meaningful.

**Triggers:**
```asm
mov rax, cs:[rbx]   ; CS override on general-purpose load (usually meaningless)
jmp fs:label        ; FS far jump without proper setup
```

**Output:**
```
error[E217]: segment override has no effect here
  --> src/main.s:1:10
   |
 1 |     mov rax, cs:[rbx]
   |              ^^
   |              'cs:' segment override has no effect on this instruction in 64-bit mode
   |
   = note: in 64-bit mode only FS: and GS: segment overrides are meaningful
```

**Recovery:** Emit instruction without override.
**Related hints:** H217

---

## E218 — Duplicate segment override

**Cause:** Two segment overrides are applied to the same operand.

**Triggers:**
```asm
mov rax, fs:gs:[rbx]    ; two segment overrides
```

**Output:**
```
error[E218]: duplicate segment override
  --> src/main.s:1:14
   |
 1 |     mov rax, fs:gs:[rbx]
   |                  ^^
   |                  'gs:' conflicts with earlier 'fs:' override on same operand
   |
   = hint[H218]: use only one segment override: fs:[rbx] or gs:[rbx]
```

**Recovery:** Use last override seen.
**Related hints:** H218

---

## E219 — Invalid operand combination

**Cause:** The combination of operand types is not valid for any form of the instruction.

**Triggers:**
```asm
mov [rax], [rbx]    ; two memory operands (E513 is more specific)
add [rax], [rbx]    ; two memory operands
```

**Output:**
```
error[E219]: invalid operand combination
  --> src/main.s:1:5
   |
 1 |     mov [rax], [rbx]
   |         ~~~~~~ ~~~~~~
   |         x86-64 does not allow two memory operands in a single instruction
   |
   = hint[H219]: load source into register first: mov rcx, [rbx] / mov [rax], rcx
```

**Recovery:** Skip instruction.
**Related hints:** H219

---

## E220 — Expression expected

**Cause:** A context that requires an expression (for EQU, TIMES, ALIGN etc.) finds something else.

**Triggers:**
```asm
TIMES mov db 0      ; TIMES requires a count expression
ALIGN "16"          ; ALIGN requires a numeric expression
```

**Output:**
```
error[E220]: expression expected
  --> src/main.s:1:7
   |
 1 |     TIMES mov db 0
   |           ^^^
   |           expected numeric expression for TIMES count, found mnemonic 'mov'
```

**Recovery:** Use value 1.
**Related hints:** H220

---

## E221 — Division by zero in expression

**Cause:** A compile-time expression divides by zero.

**Triggers:**
```asm
%define DIVISOR 0
mov rax, 100 / DIVISOR
dq (TABLE_SIZE / ENTRY_COUNT)   ; where ENTRY_COUNT = 0
```

**Output:**
```
error[E221]: division by zero in expression
  --> src/main.s:2:14
   |
 2 |     mov rax, 100 / DIVISOR
   |                  ^~~~~~~~~
   |                  division by zero — DIVISOR expands to 0
   |
   = note: DIVISOR defined at src/main.s:1
```

**Recovery:** Use value 0. Assembly continues.
**Related hints:** none

---

## E222 — Expression result is not an integer

**Cause:** A context requiring an integer receives a floating-point result. (Rare — utasm expressions are integer-only in most contexts.)

**Triggers:**
```asm
ALIGN 1.5           ; alignment must be integer
TIMES 3.14 db 0     ; count must be integer
```

**Output:**
```
error[E222]: expression result must be an integer
  --> src/main.s:1:7
   |
 1 |     ALIGN 1.5
   |           ^^^
   |           alignment value must be an integer, found floating-point '1.5'
   |
   = hint[H222]: ALIGN 2
```

**Recovery:** Truncate to integer.
**Related hints:** H222

---

## E223 — Expression overflow

**Cause:** A compile-time expression produces a result that overflows 64-bit arithmetic.

**Triggers:**
```asm
dq 0xFFFFFFFFFFFFFFFF + 1   ; wraps around (utasm fires error rather than silently wrapping)
```

**Output:**
```
error[E223]: expression overflow
  --> src/main.s:1:4
   |
 1 |     dq 0xFFFFFFFFFFFFFFFF + 1
   |        ~~~~~~~~~~~~~~~~~~~~~~
   |        result exceeds 64-bit unsigned range
   |
   = note: 0xFFFFFFFFFFFFFFFF + 1 = 0x10000000000000000 (requires 65 bits)
```

**Recovery:** Use 0xFFFFFFFFFFFFFFFF (clamped).
**Related hints:** none

---

## E224 — Forward reference not resolvable here

**Cause:** A forward reference to a label is used in a context where it must be resolved on the first pass (e.g., TIMES count, ALIGN, EQU).

**Triggers:**
```asm
TIMES future_label db 0     ; future_label not yet defined — count unknown
future_label:
```

**Output:**
```
error[E224]: forward reference not resolvable in this context
  --> src/main.s:1:7
   |
 1 |     TIMES future_label db 0
   |           ^^^^^^^^^^^^
   |           'future_label' is not yet defined — TIMES count must be known on first pass
   |
   = note: 'future_label' defined at src/main.s:2
```

**Recovery:** Use value 1.
**Related hints:** H224

---

## E225 — Invalid size override

**Cause:** A size override keyword is used with a register of conflicting size.

**Triggers:**
```asm
mov BYTE PTR rax, 1     ; RAX is 64-bit, BYTE PTR says 8-bit
mov QWORD PTR al, 1     ; AL is 8-bit, QWORD PTR says 64-bit
```

**Output:**
```
error[E225]: invalid size override
  --> src/main.s:1:5
   |
 1 |     mov BYTE PTR rax, 1
   |         ~~~~~~~~ ^^^
   |         'BYTE PTR' (8-bit) conflicts with register 'rax' (64-bit)
   |
   = hint[H225]: mov al, 1
```

**Recovery:** Use register size. Ignore override.
**Related hints:** H225

---

## E226 — Ambiguous operand size

**Cause:** An instruction has a memory operand with no size information and no register operand to infer the size from.

**Triggers:**
```asm
mov [rax], 1        ; is this 8-bit, 16-bit, 32-bit, or 64-bit?
add [rax], 255      ; same problem
inc [rax]           ; INC without size
```

**Output:**
```
error[E226]: ambiguous operand size
  --> src/main.s:1:5
   |
 1 |     mov [rax], 1
   |         ~~~~~
   |         size of memory operand is ambiguous — add a size specifier
   |
   = hint[H226]: mov BYTE PTR [rax], 1   ; 8-bit
                 mov WORD PTR [rax], 1   ; 16-bit
                 mov DWORD PTR [rax], 1  ; 32-bit
                 mov QWORD PTR [rax], 1  ; 64-bit
```

**Recovery:** Cannot proceed. Skip instruction.
**Related hints:** H226

---

## E227 — Size override conflict

**Cause:** Two size specifiers in the same instruction disagree.

**Triggers:**
```asm
mov BYTE PTR [rax], DWORD PTR 1    ; BYTE vs DWORD
movzx rax, QWORD PTR [rbx]         ; MOVZX can't zero-extend to same or larger size
```

**Output:**
```
error[E227]: size override conflict
  --> src/main.s:1:5
   |
 1 |     mov BYTE PTR [rax], DWORD PTR 1
   |         ~~~~~~~~            ~~~~~
   |         destination size (BYTE = 8 bits) conflicts with source size (DWORD = 32 bits)
```

**Recovery:** Use destination size.
**Related hints:** H227

---

# E3xx — Macro Errors

Fired during macro processing. Recovery: skip to end of macro body or next top-level token.

---

## E301 — Undefined macro

**Cause:** A macro name is used but has never been defined with `%define` or `%macro`.

**Triggers:**
```asm
%define DEFINED_MACRO 42
mov rax, UNDEFINED_MACRO    ; never defined
CALL_MY_MACRO arg1, arg2    ; never defined as %macro
```

**Output:**
```
error[E301]: undefined macro
  --> src/main.s:2:10
   |
 2 |     mov rax, UNDEFINED_MACRO
   |              ^^^^^^^^^^^^^^^
   |              'UNDEFINED_MACRO' is not defined
   |
   = hint[H301]: did you mean 'DEFINED_MACRO'?
```

**Recovery:** Token left unexpanded. Assembly continues.
**Related hints:** H301 (did-you-mean suggestion)

---

## E302 — Macro redefinition

**Cause:** A macro name is defined with `%define` or `%macro` when it is already defined. Use `%undef` first to redefine.

**Triggers:**
```asm
%define MAX 100
%define MAX 200     ; E302 — MAX already defined
```

**Output:**
```
error[E302]: macro redefinition
  --> src/main.s:2:9
   |
 2 |     %define MAX 200
   |             ^^^
   |             'MAX' is already defined
   |
   = note: previous definition at src/main.s:1
   = hint[H302]: use '%undef MAX' before redefining, or use a different name
```

**Recovery:** New definition replaces old. Assembly continues.
**Related hints:** H302

---

## E303 — Wrong number of macro arguments

**Cause:** A macro is called with a number of arguments that does not match any defined form.

**Triggers:**
```asm
%macro SWAP 2
    xchg %1, %2
%endmacro

SWAP rax                ; 1 argument, needs 2
SWAP rax, rbx, rcx      ; 3 arguments, needs 2
```

**Output:**
```
error[E303]: wrong number of macro arguments
  --> src/main.s:6:5
   |
 6 |     SWAP rax
   |     ~~~~
   |     'SWAP' requires 2 arguments, found 1
   |
   = note: 'SWAP' defined at src/main.s:1
   = hint[H303]: SWAP rax, rbx
```

**Recovery:** Skip macro expansion.
**Related hints:** H303

---

## E304 — Too many macro arguments

**Cause:** More arguments are provided than the macro's maximum.

**Output:** See E303 format.
**Recovery:** Ignore extra arguments. Expand with first N.

---

## E305 — Too few macro arguments

**Cause:** Fewer arguments are provided than the macro's minimum (with no default for missing ones).

**Output:** See E303 format.
**Recovery:** Skip expansion.

---

## E306 — Macro expansion depth exceeded

**Cause:** Macro expansions are nested more than MAX_MACRO_DEPTH (999) levels deep. Usually caused by a recursive macro that was not caught by E307.

**Triggers:**
```asm
%macro DEEP 0
    DEEP            ; calls itself
%endmacro
DEEP                ; E307 fires, but if somehow missed, E306 is the safety net
```

**Output:**
```
error[E306]: macro expansion depth exceeded
  --> src/main.s:2:5
   |
 2 |     DEEP
   |     ^^^^
   |     macro expansion depth limit (999) exceeded — possible infinite recursion
   |
   = note: expansion chain truncated for display
   = hint[H306]: check for recursive macro calls
```

**Recovery:** Abort expansion. Continue from token after macro call.
**Related hints:** H306

---

## E307 — Recursive macro detected

**Cause:** A macro directly or indirectly calls itself, which would cause infinite expansion.

**Triggers:**
```asm
%macro RECURSE 0
    mov rax, 1
    RECURSE         ; calls itself
%endmacro
```

**Output:**
```
error[E307]: recursive macro detected
  --> src/main.s:3:5
   |
 3 |     RECURSE
   |     ^^^^^^^
   |     'RECURSE' calls itself — recursive macros are not permitted
   |
   = note: expansion chain:
           RECURSE → RECURSE → ...
   = hint[H307]: use %rep for loops, not recursive macros
```

**Recovery:** Abort expansion at point of recursion.
**Related hints:** H307

---

## E308 — Undefined macro parameter

**Cause:** Inside a macro body, `%N` is used where N is greater than the argument count.

**Triggers:**
```asm
%macro ONE_ARG 1
    mov rax, %1
    mov rbx, %2     ; %2 doesn't exist — macro only has 1 argument
%endmacro
```

**Output:**
```
error[E308]: undefined macro parameter
  --> src/main.s:3:15
   |
 3 |     mov rbx, %2
   |               ^^
   |               parameter '%2' is not defined — 'ONE_ARG' has 1 argument
```

**Recovery:** Expand to empty token.
**Related hints:** H308

---

## E309 — Invalid macro parameter name

**Cause:** A macro parameter reference is malformed.

**Triggers:**
```asm
%macro BAD 2
    mov rax, %a     ; %a is not a valid parameter reference
    mov rbx, %0x    ; malformed
%endmacro
```

**Output:**
```
error[E309]: invalid macro parameter reference
  --> src/main.s:2:15
   |
 2 |     mov rax, %a
   |               ^^
   |               '%a' is not a valid parameter reference — use %1, %2, %3, etc.
```

**Recovery:** Expand to empty token.
**Related hints:** H309

---

## E310 — Macro body is empty

**Cause:** A `%macro` definition has no body tokens before `%endmacro`.

**Triggers:**
```asm
%macro EMPTY 0
%endmacro           ; empty body — utasm allows this but warns
```

**Output:** (This fires W302 warning, not E310. E310 reserved for future use.)

---

## E311 — Unterminated macro definition

**Cause:** A `%macro` block is not closed with `%endmacro` before end of file.

**Triggers:**
```asm
%macro MY_MACRO 2
    mov rax, %1
    mov rbx, %2
; end of file reached without %endmacro
```

**Output:**
```
error[E311]: unterminated macro definition
  --> src/main.s:1:1
   |
 1 |     %macro MY_MACRO 2
   |     ^~~~~~~~~~~~~~~~~
   |     macro 'MY_MACRO' opened here, never closed with '%endmacro'
   |
   = hint[H311]: add '%endmacro' at the end of the macro body
```

**Recovery:** Close macro at end of file. Assembly continues but macro may be incomplete.
**Related hints:** H311

---

## E312 — %endmacro without %macro

**Cause:** `%endmacro` appears outside of a macro definition.

**Triggers:**
```asm
mov rax, rbx
%endmacro           ; no matching %macro
```

**Output:**
```
error[E312]: '%endmacro' without matching '%macro'
  --> src/main.s:2:1
   |
 2 |     %endmacro
   |     ^~~~~~~~~
   |     '%endmacro' found but no macro definition is open
```

**Recovery:** Ignore `%endmacro`. Continue.
**Related hints:** none

---

## E313 — Local label scope error in macro

**Cause:** A `%%label` local label in a macro is referenced outside its expansion scope.

**Output:**
```
error[E313]: local label referenced outside macro expansion
  --> src/main.s:10:5
   |
10 |     jmp %%loop
   |         ^~~~~~
   |         '%%loop' is a local label — it can only be referenced within its macro expansion
```

**Recovery:** Skip reference.
**Related hints:** H313

---

## E314 — Macro expansion produces invalid token

**Cause:** Token pasting (`##`) or stringification (`%str()`) produces a result that is not a valid token.

**Triggers:**
```asm
%define PASTE(a,b) a ## b
mov rax, PASTE(12, -34)     ; 12-34 is not a valid token
```

**Output:**
```
error[E314]: macro expansion produces invalid token
  --> src/main.s:2:10
   |
 2 |     mov rax, PASTE(12, -34)
   |              ~~~~~~~~~~~~~~
   |              token pasting '12' ## '-34' produces '12-34' which is not valid
   |
   = hint[H314]: ensure pasted tokens form a valid identifier or number
```

**Recovery:** Use invalid token as-is. E201 may fire later.
**Related hints:** H314

---

## E315 — Stringification of invalid token

**Cause:** `%str()` is applied to a token that cannot be converted to a string representation.

**Output:**
```
error[E315]: cannot stringify token
  --> src/main.s:2:10
   |
 2 |     db %str([rax + rbx*4])
   |        ~~~~~~~~~~~~~~~~~~~
   |        complex expression cannot be stringified directly
```

**Recovery:** Use empty string.
**Related hints:** H315

---

## E316 — Token pasting produces invalid token

**Cause:** The `##` operator produces a result that is neither a valid identifier nor a valid number.

**Output:** See E314.

---

## E317 — Macro defined inside macro

**Cause:** A `%macro` definition appears inside another macro body. This is not supported.

**Triggers:**
```asm
%macro OUTER 0
    %macro INNER 0   ; E317
        nop
    %endmacro
%endmacro
```

**Output:**
```
error[E317]: macro definition inside macro body is not permitted
  --> src/main.s:2:5
   |
 2 |     %macro INNER 0
   |     ~~~~~~~~~~~~~~
   |     nested '%macro' found inside 'OUTER' — define macros at file scope
```

**Recovery:** Skip nested definition.
**Related hints:** H317

---

## E318 — Purge of undefined macro

**Cause:** `%undef` or `%purge` is used on a name that is not defined. (This fires a warning W302, not an error. E318 reserved.)

---

## E319 — Macro library not found

**Cause:** A `%include` directive references a file that cannot be found in the include search path.

**Triggers:**
```asm
%include "missing_file.inc"
%include <nonexistent/path.inc>
```

**Output:**
```
error[E319]: included file not found
  --> src/main.s:1:10
   |
 1 |     %include "missing_file.inc"
   |              ^~~~~~~~~~~~~~~~~~
   |              cannot find 'missing_file.inc' in include search path
   |
   = note: search path:
           ./
           ./include/
           /usr/local/include/utasm/
   = hint[H319]: check filename spelling or add directory with -I flag
```

**Recovery:** Skip include. Continue.
**Related hints:** H319

---

## E320 — Circular include detected

**Cause:** A file includes itself directly or through a chain of includes.

**Triggers:**
```asm
; a.inc
%include "b.inc"

; b.inc
%include "a.inc"    ; circular — a includes b includes a
```

**Output:**
```
error[E320]: circular include detected
  --> b.inc:1:1
   |
 1 |     %include "a.inc"
   |              ^~~~~~~
   |              'a.inc' is already in the include stack — circular include
   |
   = note: include chain:
           main.s → a.inc → b.inc → a.inc
   = hint[H320]: use include guards: %ifndef A_INC / %define A_INC / ... / %endif
```

**Recovery:** Skip the circular include. Continue.
**Related hints:** H320

---

# E4xx — Semantic Errors

Fired during semantic analysis. Recovery: continue with next statement.

---

## E401 — Undefined symbol

**Cause:** A label or symbol is referenced but never defined anywhere in the assembled files.

**Triggers:**
```asm
jmp undefined_label     ; label never appears anywhere
call missing_function   ; function never defined or declared EXTERN
```

**Output:**
```
error[E401]: undefined symbol
  --> src/main.s:1:5
   |
 1 |     jmp undefined_label
   |         ^^^^^^^^^^^^^^^
   |         'undefined_label' is not defined in this translation unit
   |
   = hint[H401]: if it is defined in another file, add: extern undefined_label
```

**Recovery:** Symbol given value 0. Relocation emitted for linker to resolve.
**Related hints:** H401

---

## E402 — Symbol redefinition

**Cause:** A label is defined more than once in the same scope.

**Triggers:**
```asm
my_label:
    mov rax, rbx
my_label:           ; E402 — already defined above
    nop
```

**Output:**
```
error[E402]: symbol redefinition
  --> src/main.s:4:1
   |
 4 |     my_label:
   |     ^^^^^^^^
   |     'my_label' is already defined
   |
   = note: previous definition at src/main.s:1
```

**Recovery:** Second definition ignored. Assembly continues.
**Related hints:** H402

---

## E403 — Symbol redefinition with different type

**Cause:** A symbol is defined twice with incompatible types (e.g., once as a label and once as an EQU constant).

**Triggers:**
```asm
MAX equ 100
MAX:                ; E403 — MAX is already an EQU constant, not a label
    nop
```

**Output:**
```
error[E403]: symbol redefinition with incompatible type
  --> src/main.s:2:1
   |
 2 |     MAX:
   |     ^^^
   |     'MAX' is already defined as a constant (EQU) — cannot redefine as a label
   |
   = note: previous definition at src/main.s:1
```

**Recovery:** Second definition ignored.
**Related hints:** H403

---

## E404 — Symbol redefinition with different size

**Cause:** A COMMON symbol is declared twice with different sizes.

**Triggers:**
```asm
common buffer 1024
common buffer 2048  ; E404 — different size
```

**Output:**
```
error[E404]: COMMON symbol redefined with different size
  --> src/main.s:2:8
   |
 2 |     common buffer 2048
   |            ~~~~~~ ~~~~
   |            'buffer' previously declared as COMMON with size 1024, now 2048
   |
   = note: previous declaration at src/main.s:1
   = hint[H404]: use the same size in all declarations
```

**Recovery:** Use first size.
**Related hints:** H404

---

## E405 — Forward reference in EQU

**Cause:** An EQU constant references a label that has not yet been defined, and EQU requires a fully constant expression.

**Triggers:**
```asm
SIZE equ future_label - start   ; future_label not yet defined
start:
    db 0, 0, 0, 0
future_label:
```

**Output:**
```
error[E405]: forward reference in EQU definition
  --> src/main.s:1:12
   |
 1 |     SIZE equ future_label - start
   |              ^^^^^^^^^^^^
   |              'future_label' is not yet defined — EQU requires a constant expression
   |
   = hint[H405]: move the EQU definition after all referenced labels
```

**Recovery:** Use value 0.
**Related hints:** H405

---

## E406 — Circular EQU definition

**Cause:** An EQU constant refers to itself directly or through a chain.

**Triggers:**
```asm
A equ B + 1
B equ A + 1     ; A depends on B, B depends on A
```

**Output:**
```
error[E406]: circular EQU definition
  --> src/main.s:2:7
   |
 2 |     B equ A + 1
   |           ^
   |           'A' refers back to 'B' creating a circular definition
   |
   = note: definition chain: B → A → B
```

**Recovery:** Both values set to 0.
**Related hints:** none

---

## E407 — Label on same line as section directive

**Cause:** A label is defined on the same line as a section change.

**Triggers:**
```asm
my_label: section .text     ; ambiguous — is label in old or new section?
```

**Output:**
```
error[E407]: label and section directive on same line
  --> src/main.s:1:1
   |
 1 |     my_label: section .text
   |     ^~~~~~~~~ ^~~~~~~~~~~~~
   |     label and section change cannot be on the same line — use separate lines
   |
   = hint[H407]:
           section .text
           my_label:
```

**Recovery:** Label placed before section change.
**Related hints:** H407

---

## E408 — Invalid section name

**Cause:** A section name contains characters not valid for ELF section names.

**Triggers:**
```asm
section .my section     ; space in name
section                 ; no name provided
```

**Output:**
```
error[E408]: invalid section name
  --> src/main.s:1:9
   |
 1 |     section .my section
   |             ^^^
   |             section name '.my' followed by unexpected token 'section'
   |
   = note: section names must be a single token with no spaces
   = hint[H408]: section .my_section
```

**Recovery:** Use section name up to first invalid character.
**Related hints:** H408

---

## E409 — Section redefinition with different flags

**Cause:** The same section name is declared twice with incompatible flags.

**Triggers:**
```asm
section .mydata exec    ; executable
section .mydata write   ; now writable — conflicts
```

**Output:**
```
error[E409]: section redefinition with conflicting flags
  --> src/main.s:2:9
   |
 2 |     section .mydata write
   |             ^~~~~~~ ~~~~~
   |             '.mydata' previously declared with flags 'exec', now 'write'
   |
   = note: previous declaration at src/main.s:1
   = hint[H409]: merge flags in single declaration: section .mydata write exec
```

**Recovery:** Merge flags.
**Related hints:** H409

---

## E410 — Entry point not defined

**Cause:** `--standalone` flag is used but no `_start` symbol is defined.

**Output:**
```
error[E410]: entry point not defined
  --> (linker)
   |
   standalone executable requires '_start' to be defined
   |
   = hint[H410]: define _start as your program entry point:
                 global _start
                 _start:
                     mov rax, 60
                     xor rdi, rdi
                     syscall
```

**Recovery:** Cannot produce working standalone executable.
**Related hints:** H410

---

## E411 — Entry point defined multiple times

**Cause:** `_start` is defined in more than one object file being linked.

**Output:**
```
error[E411]: entry point '_start' defined multiple times
  --> (linker)
   |
   '_start' defined in: main.s (line 5) and init.s (line 12)
   |
   = hint[H411]: only one file should define _start
```

**Recovery:** Use first definition found.
**Related hints:** H411

---

## E412 — EXTERN symbol also defined locally

**Cause:** A symbol is declared with `extern` and also defined as a label in the same file.

**Triggers:**
```asm
extern my_function
my_function:            ; E412 — can't be both extern and local
    nop
```

**Output:**
```
error[E412]: 'my_function' declared extern but also defined locally
  --> src/main.s:2:1
   |
 2 |     my_function:
   |     ^^^^^^^^^^^
   |     'my_function' has a local definition but is also declared extern
   |
   = note: extern declaration at src/main.s:1
   = hint[H412]: remove the extern declaration if defining locally, or remove the local definition
```

**Recovery:** Treat as local definition. Ignore extern.
**Related hints:** H412

---

## E413 — GLOBAL symbol not defined

**Cause:** A symbol is declared with `global` but never defined with a label.

**Triggers:**
```asm
global my_function      ; declared as global
; ... no my_function: label anywhere in file
```

**Output:**
```
error[E413]: 'my_function' declared global but never defined
  --> src/main.s:1:8
   |
 1 |     global my_function
   |            ^^^^^^^^^^^
   |            'my_function' is exported but has no definition in this file
   |
   = hint[H413]: add a label definition: my_function: ... or remove the global declaration
```

**Recovery:** Emit as undefined global. Linker may resolve from another object.
**Related hints:** H413

---

## E414 — Symbol name too long

**Cause:** A label or symbol name exceeds the ELF symbol table name length limit.

**Output:**
```
error[E414]: symbol name too long
  --> src/main.s:1:1
   |
 1 |     averylongnamethatexceedsthelimit...:
   |     ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   |     symbol name exceeds maximum length of 4096 characters
```

**Recovery:** Truncate to 4096 characters.
**Related hints:** none

---

## E415 — Reserved keyword used as symbol name

**Cause:** A reserved instruction mnemonic or register name is used as a label.

**Triggers:**
```asm
rax:                ; register name used as label
mov:                ; instruction mnemonic used as label
section:            ; directive used as label
```

**Output:**
```
error[E415]: reserved keyword used as symbol name
  --> src/main.s:1:1
   |
 1 |     rax:
   |     ^^^
   |     'rax' is a register name and cannot be used as a label
   |
   = hint[H415]: choose a different name: rax_save: or my_rax:
```

**Recovery:** Skip label definition.
**Related hints:** H415

---

## E416 — Symbol visibility conflict

**Cause:** A symbol is declared both `global` and `local` (or other conflicting visibility).

**Output:**
```
error[E416]: symbol visibility conflict
  --> src/main.s:2:7
   |
 2 |     local my_func
   |           ^~~~~~~
   |           'my_func' is already declared global at line 1
```

**Recovery:** Global takes precedence.
**Related hints:** none

---

## E417 — Invalid alignment value

**Cause:** An alignment value is not a power of 2.

**Triggers:**
```asm
ALIGN 3         ; 3 is not a power of 2
ALIGN 0         ; 0 is not valid
ALIGN 7         ; 7 is not a power of 2
```

**Output:**
```
error[E417]: invalid alignment value
  --> src/main.s:1:7
   |
 1 |     ALIGN 3
   |           ^
   |           alignment '3' is not a power of 2
   |
   = hint[H417]: valid alignments: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
```

**Recovery:** Round up to next power of 2.
**Related hints:** H417

---

## E418 — Alignment too large

**Cause:** An alignment value exceeds the maximum allowed (4096 for data, 64 for code).

**Triggers:**
```asm
ALIGN 65536     ; exceeds maximum
```

**Output:**
```
error[E418]: alignment too large
  --> src/main.s:1:7
   |
 1 |     ALIGN 65536
   |           ^~~~~
   |           alignment '65536' exceeds maximum (4096)
```

**Recovery:** Use maximum alignment.
**Related hints:** none

---

## E419 — TIMES count is negative

**Cause:** The count expression in a `TIMES` directive evaluates to a negative number.

**Triggers:**
```asm
%define COUNT -5
TIMES COUNT db 0    ; negative count
TIMES (2 - 10) db 0 ; -8
```

**Output:**
```
error[E419]: TIMES count is negative
  --> src/main.s:2:7
   |
 2 |     TIMES COUNT db 0
   |           ^~~~~
   |           TIMES count evaluates to -5 — must be non-negative
   |
   = note: COUNT expands to -5 (defined at src/main.s:1)
```

**Recovery:** Use count 0 (emit nothing).
**Related hints:** H419

---

## E420 — TIMES count is not constant

**Cause:** The `TIMES` count expression cannot be evaluated at assembly time.

**Triggers:**
```asm
TIMES future_label db 0     ; future_label value unknown at this point
```

**Output:**
```
error[E420]: TIMES count must be a constant expression
  --> src/main.s:1:7
   |
 1 |     TIMES future_label db 0
   |           ^^^^^^^^^^^^
   |           'future_label' is a forward reference — TIMES requires a known constant
```

**Recovery:** Use count 1.
**Related hints:** H420

---

## E421 — EQU value is not constant

**Cause:** An EQU definition contains a non-constant expression.

**Triggers:**
```asm
VALUE equ [rax]         ; memory reference is not constant
VALUE equ future_label  ; forward reference (also E405)
```

**Output:**
```
error[E421]: EQU value must be a constant expression
  --> src/main.s:1:12
   |
 1 |     VALUE equ [rax]
   |               ^~~~~
   |               memory reference '[rax]' is not a compile-time constant
   |
   = hint[H421]: EQU defines compile-time constants: VALUE equ 42
```

**Recovery:** Use value 0.
**Related hints:** H421

---

## E422 — Invalid operand type for instruction

**Cause:** An operand type is fundamentally wrong for the instruction — not just a size issue.

**Triggers:**
```asm
jmp 42          ; JMP to an immediate value (not an address)
call 1000       ; CALL to an absolute immediate (use a label)
```

**Output:**
```
error[E422]: invalid operand type for instruction
  --> src/main.s:1:5
   |
 1 |     jmp 42
   |         ^^
   |         'jmp' cannot jump to an integer literal — use a label or register
   |
   = hint[H422]: jmp my_label  or  jmp rax
```

**Recovery:** Skip instruction.
**Related hints:** H422

---

## E423 — Write to read-only section

**Cause:** Data or code is emitted into a section declared as read-only.

**Triggers:**
```asm
section .rodata
db "hello", 0       ; OK — data in rodata is fine
mov [rax], rbx      ; instruction in rodata? unusual — W403 fires, not error
```

Note: E423 fires only for clear violations (e.g., explicitly labeling write attempts).

---

## E424 — Execute from non-executable section

**Cause:** A jump target points to a section that has no execute permission.

**Output:**
```
error[E424]: jump target in non-executable section
  --> src/main.s:5:5
   |
 5 |     jmp data_section_label
   |         ~~~~~~~~~~~~~~~~~~
   |         'data_section_label' is in section '.data' which has no execute permission
   |
   = hint[H424]: ensure jump targets are in .text or another executable section
```

**Recovery:** Emit jump anyway. OS will reject execution.
**Related hints:** H424

---

## E425 — Invalid combination of attributes

**Cause:** Section attributes are mutually exclusive or invalid together.

**Triggers:**
```asm
section .bad noalloc exec   ; noalloc + exec doesn't make sense
```

**Output:**
```
error[E425]: invalid combination of section attributes
  --> src/main.s:1:9
   |
 1 |     section .bad noalloc exec
   |              ~~~~ ~~~~~~~ ^^^^
   |              'noalloc' and 'exec' cannot be combined
```

**Recovery:** Drop conflicting attribute.
**Related hints:** none

---

# E5xx — Encoder Errors

Fired during instruction encoding. Recovery: skip instruction, continue.

---

## E501 — Operand size mismatch

**Cause:** The sizes of two operands in the same instruction are incompatible.

**Triggers:**
```asm
mov al, rax         ; al is 8-bit, rax is 64-bit
add eax, rbx        ; eax is 32-bit, rbx is 64-bit
movzx rax, eax      ; MOVZX extends smaller to larger — backwards here (use MOV)
```

**Output:**
```
error[E501]: operand size mismatch
  --> src/main.s:1:5
   |
 1 |     mov al, rax
   |         ^^  ^^^
   |         destination 'al' is 8-bit, source 'rax' is 64-bit
   |
   = hint[H501]: mov al, al     ; stay 8-bit
                 mov rax, rax   ; stay 64-bit
                 movzx rax, al  ; zero-extend 8-bit to 64-bit
```

**Recovery:** Skip instruction.
**Related hints:** H501

---

## E502 — Immediate value out of range

**Cause:** An immediate operand value does not fit in the allowed range for this instruction form.

**Triggers:**
```asm
mov al, 256         ; 256 > 0xFF — doesn't fit in 8-bit
mov ax, 65536       ; 65536 > 0xFFFF
int 256             ; INT imm8 max is 255
```

**Output:**
```
error[E502]: immediate value out of range
  --> src/main.s:1:9
   |
 1 |     mov al, 256
   |             ^^^
   |             '256' does not fit in 8-bit unsigned immediate (range: 0–255)
   |
   = hint[H502]: mov ah, 1  ; use high byte for values 256–511
                 mov ax, 256 ; use 16-bit register
```

**Recovery:** Skip instruction.
**Related hints:** H502

---

## E503 — Signed immediate out of range

**Cause:** An immediate that is sign-extended does not fit in the allowed signed range.

**Triggers:**
```asm
add rax, 0x80000000     ; immediate sign-extended to 64-bit, fits in 32-bit only if signed
mov rcx, -2147483649    ; < INT32_MIN — doesn't fit as sign-extended imm32
```

**Output:**
```
error[E503]: signed immediate out of range
  --> src/main.s:2:10
   |
 2 |     mov rcx, -2147483649
   |              ~~~~~~~~~~~
   |              '-2147483649' does not fit in a sign-extended 32-bit immediate
   |              (range: -2147483648 to 2147483647)
   |
   = hint[H503]: use MOV with 64-bit immediate: mov rcx, -2147483649  [encoded as B8+rd io]
```

**Recovery:** Skip instruction.
**Related hints:** H503

---

## E504 — Unsigned immediate out of range

**Cause:** An immediate value exceeds the unsigned range for the operand position.

**Output:** See E502 format.

---

## E505 — Displacement out of range

**Cause:** A memory displacement does not fit in the allowed displacement size.

**Triggers:**
```asm
mov rax, [rbx + 0x100000000]   ; > INT32_MAX for 32-bit displacement
```

**Output:**
```
error[E505]: displacement out of range
  --> src/main.s:1:10
   |
 1 |     mov rax, [rbx + 0x100000000]
   |               ~~~~~~~~~~~~~~~~~~
   |               displacement 0x100000000 does not fit in 32-bit signed displacement
   |               (range: -2147483648 to 2147483647)
   |
   = hint[H505]: load offset into register: mov rcx, 0x100000000 / add rcx, rbx / mov rax, [rcx]
```

**Recovery:** Skip instruction.
**Related hints:** H505

---

## E506 — Jump target out of range

**Cause:** A relative jump target is more than ±2GB away from the instruction.

**Output:**
```
error[E506]: jump target out of range
  --> src/main.s:1:5
   |
 1 |     jmp very_distant_label
   |         ~~~~~~~~~~~~~~~~~~
   |         jump target is 4GB away — maximum relative jump is ±2GB
   |
   = hint[H506]: use an indirect jump: mov rax, very_distant_label / jmp rax
```

**Recovery:** Skip instruction.
**Related hints:** H506

---

## E507 — Short jump out of range

**Cause:** An instruction explicitly forced to short form (with `SHORT`) has a target that exceeds ±127 bytes. (This is a hint — utasm normally handles short/near selection automatically.)

**Triggers:**
```asm
jmp SHORT far_label     ; explicit SHORT that doesn't reach
```

**Output:**
```
error[E507]: explicit SHORT jump out of range
  --> src/main.s:1:5
   |
 1 |     jmp SHORT far_label
   |     ~~~
   |     'SHORT' forces 2-byte encoding but target 'far_label' is 512 bytes away (max: 127)
   |
   = hint[H507]: remove SHORT — utasm selects short/near encoding automatically
```

**Recovery:** Encode as NEAR.
**Related hints:** H507

---

## E508 — Invalid register for operand

**Cause:** A register is used in an operand position where it is not permitted.

**Triggers:**
```asm
push xmm0       ; XMM registers cannot be pushed/popped (use MOVAPS)
pop ymm1        ; YMM registers cannot be pushed/popped
div xmm0        ; DIV only accepts general-purpose registers
```

**Output:**
```
error[E508]: invalid register for this operand
  --> src/main.s:1:6
   |
 1 |     push xmm0
   |          ^^^^
   |          'xmm0' (SIMD register) cannot be used with 'push'
   |
   = hint[H508]: sub rsp, 16 / movaps [rsp], xmm0   ; manually save XMM to stack
```

**Recovery:** Skip instruction.
**Related hints:** H508

---

## E509 — Register size mismatch between operands

**Cause:** Two register operands in the same instruction have different sizes, and no size-change instruction is appropriate.

**Triggers:**
```asm
add rax, eax        ; 64-bit + 32-bit
xor rax, al         ; 64-bit XOR 8-bit
```

**Output:**
```
error[E509]: register size mismatch
  --> src/main.s:1:5
   |
 1 |     add rax, eax
   |         ^^^  ^^^
   |         'rax' is 64-bit, 'eax' is 32-bit — operands must be the same size
   |
   = hint[H509]: add rax, rax   ; both 64-bit
                 add eax, eax   ; both 32-bit
```

**Recovery:** Skip instruction.
**Related hints:** H509

---

## E510 — Memory operand not allowed here

**Cause:** A memory operand is used in a position that requires a register or immediate.

**Triggers:**
```asm
push [rax]          ; actually valid — this is a counter-example (push memory IS valid)
imul rax, [rbx], [rcx]  ; third operand of IMUL must be immediate
```

**Output:**
```
error[E510]: memory operand not permitted in this position
  --> src/main.s:1:16
   |
 1 |     imul rax, [rbx], [rcx]
   |                      ^~~~~
   |                      third operand of 'imul' must be an immediate, not memory
```

**Recovery:** Skip instruction.
**Related hints:** H510

---

## E511 — Immediate operand not allowed here

**Cause:** An immediate is used where only a register or memory is allowed.

**Triggers:**
```asm
mov [rax], [rbx]    ; source can't be memory when dest is memory (E513)
neg 42              ; NEG only works on register or memory, not immediate
```

**Output:**
```
error[E511]: immediate operand not permitted here
  --> src/main.s:1:5
   |
 1 |     neg 42
   |         ^^
   |         'neg' cannot operate on an immediate value — use register or memory
   |
   = hint[H511]: mov rax, 42 / neg rax
```

**Recovery:** Skip instruction.
**Related hints:** H511

---

## E512 — Register operand not allowed here

**Cause:** A register is used where only memory is allowed.

**Triggers:**
```asm
lea rax, rbx        ; LEA source must be memory (E205 is more specific)
lgdt rax            ; LGDT requires memory operand
```

**Output:** See E205 format.

---

## E513 — Two memory operands not allowed

**Cause:** Both operands of an instruction are memory references, which is never valid in x86-64.

**Triggers:**
```asm
mov [rax], [rbx]    ; both source and destination are memory
add [rax], [rbx]    ; same
```

**Output:**
```
error[E513]: two memory operands are not permitted
  --> src/main.s:1:5
   |
 1 |     mov [rax], [rbx]
   |         ~~~~~  ~~~~~
   |         x86-64 does not allow two memory operands in one instruction
   |
   = hint[H513]: mov rcx, [rbx] / mov [rax], rcx
```

**Recovery:** Skip instruction.
**Related hints:** H513

---

## E514 — Invalid REX prefix combination

**Cause:** The required REX prefix fields produce an encoding that conflicts with another prefix or is otherwise invalid.

**Triggers:**
```asm
mov ah, [r8]        ; AH requires no REX, but R8 base requires REX.B — conflict
mov bh, r9b         ; BH requires no REX, R9B requires REX — conflict
```

**Output:**
```
error[E514]: invalid REX prefix combination
  --> src/main.s:1:5
   |
 1 |     mov ah, [r8]
   |         ^^  ^^
   |         using 'ah' (high byte register) with 'r8' (requires REX.B) — REX prefix conflict
   |
   = note: high byte registers AH/BH/CH/DH cannot be used with REX prefix
   = hint[H514]: mov al, [r8]   ; use low byte instead
```

**Recovery:** Skip instruction.
**Related hints:** H514

---

## E515 — REX prefix with high byte register

**Cause:** A high byte register (AH, BH, CH, DH) is used in an instruction that also requires a REX prefix for any reason.

**Output:** See E514 format.

---

## E516 — VEX length conflict

**Cause:** An AVX instruction specifies a vector length (128/256-bit) that conflicts with the instruction's requirements.

**Triggers:**
```asm
vmovaps xmm0, zmm1   ; mixing XMM (128-bit) and ZMM (512-bit) in same instruction
```

**Output:**
```
error[E516]: VEX vector length conflict
  --> src/main.s:1:10
   |
 1 |     vmovaps xmm0, zmm1
   |             ^^^^  ^^^^
   |             destination 'xmm0' (128-bit) conflicts with source 'zmm1' (512-bit)
   |
   = hint[H516]: vmovaps zmm0, zmm1   ; use matching vector widths
```

**Recovery:** Skip instruction.
**Related hints:** H516

---

## E517 — EVEX operand not aligned

**Cause:** An AVX-512 instruction requires aligned memory but the operand may not be aligned.

**Triggers:**
```asm
vmovaps zmm0, [rax + 1]    ; VMOVAPS requires 64-byte alignment, +1 is not aligned
```

**Output:**
```
error[E517]: EVEX aligned instruction requires aligned operand
  --> src/main.s:1:15
   |
 1 |     vmovaps zmm0, [rax + 1]
   |                   ~~~~~~~~
   |                   'vmovaps' requires 64-byte alignment — displacement '+1' violates alignment
   |
   = hint[H517]: use vmovups for unaligned loads: vmovups zmm0, [rax + 1]
```

**Recovery:** Emit instruction (alignment enforced at runtime).
**Related hints:** H517

---

## E518 — Broadcast operand size mismatch

**Cause:** An EVEX broadcast modifier (`{1to16}` etc.) is incompatible with the element size of the instruction.

**Triggers:**
```asm
vaddps zmm0, zmm1, [rax]{1to8}   ; VADDPS (float32) needs {1to16} for ZMM
vaddpd zmm0, zmm1, [rax]{1to16}  ; VADDPD (float64) needs {1to8} for ZMM
```

**Output:**
```
error[E518]: broadcast count mismatch
  --> src/main.s:1:28
   |
 1 |     vaddps zmm0, zmm1, [rax]{1to8}
   |                             ^^^^^^
   |             'vaddps' with ZMM uses 32-bit elements — broadcast should be {1to16}, not {1to8}
   |
   = hint[H518]: vaddps zmm0, zmm1, [rax]{1to16}
```

**Recovery:** Skip instruction.
**Related hints:** H518

---

## E519 — Mask register required

**Cause:** An EVEX instruction form that requires a mask register (`{k1}`–`{k7}`) has none specified.

**Triggers:**
```asm
; some instructions require masking — if using merge-masking form
vcompressps [rax], zmm0     ; VCOMPRESSPS to memory requires k-mask
```

**Output:**
```
error[E519]: mask register required
  --> src/main.s:1:5
   |
 1 |     vcompressps [rax], zmm0
   |     ~~~~~~~~~~~
   |     'vcompressps' with memory destination requires a write mask: {k1}–{k7}
   |
   = hint[H519]: vcompressps [rax]{k1}, zmm0
```

**Recovery:** Skip instruction.
**Related hints:** H519

---

## E520 — Mask register K0 not allowed here

**Cause:** K0 is used as a write mask. K0 always means "no masking" and cannot be used as a mask.

**Triggers:**
```asm
vmovaps zmm0{k0}, zmm1      ; {k0} means no mask — same as no braces
vmovaps zmm0{k0}{z}, zmm1   ; {k0}{z} is meaningless
```

**Output:**
```
error[E520]: mask register K0 is not permitted as a write mask
  --> src/main.s:1:13
   |
 1 |     vmovaps zmm0{k0}, zmm1
   |                  ^^
   |                  K0 means "no masking" — use K1–K7 for actual masking
   |
   = hint[H520]: vmovaps zmm0{k1}, zmm1   ; use k1–k7 for masking
```

**Recovery:** Remove mask.
**Related hints:** H520

---

## E521 — Invalid rounding mode

**Cause:** An embedded rounding control is not one of the four valid modes.

**Valid modes:** `{rn-sae}` (nearest), `{rd-sae}` (down), `{ru-sae}` (up), `{rz-sae}` (zero/truncate)

**Triggers:**
```asm
vaddps zmm0, zmm1, zmm2, {rx-sae}    ; rx is not a valid rounding mode
```

**Output:**
```
error[E521]: invalid rounding mode
  --> src/main.s:1:29
   |
 1 |     vaddps zmm0, zmm1, zmm2, {rx-sae}
   |                               ^^
   |                               'rx' is not a valid rounding mode
   |
   = note: valid modes: {rn-sae} {rd-sae} {ru-sae} {rz-sae}
   = hint[H521]: vaddps zmm0, zmm1, zmm2, {rn-sae}
```

**Recovery:** Skip instruction.
**Related hints:** H521

---

## E522 — Invalid exception flag

**Cause:** An embedded exception flag other than `{sae}` is used where only `{sae}` is allowed.

**Output:**
```
error[E522]: invalid exception suppression flag
  --> src/main.s:1:25
   |
 1 |     vcvtss2sd xmm0, xmm1, {rn-sae}
   |                             ^^
   |                             this instruction only accepts {sae}, not a full rounding mode
```

**Recovery:** Skip instruction.
**Related hints:** H522

---

## E523 — EVEX encoding not supported for this instruction

**Cause:** AVX-512 EVEX encoding is requested for an instruction that has no EVEX form.

**Output:**
```
error[E523]: EVEX encoding not available for this instruction
  --> src/main.s:1:5
   |
 1 |     vpand zmm0, zmm1, zmm2     ; VPAND only exists as VEX (use VPANDD/VPANDQ for EVEX)
   |     ~~~~~
   |
   = hint[H523]: vpandd zmm0, zmm1, zmm2   ; 32-bit element EVEX form
                 vpandq zmm0, zmm1, zmm2   ; 64-bit element EVEX form
```

**Recovery:** Skip instruction.
**Related hints:** H523

---

## E524 — VEX encoding not supported

**Cause:** A VEX form is used for an instruction that requires EVEX.

**Output:** See E523 format.

---

## E525 — Instruction requires operand size prefix

**Cause:** A 16-bit form of an instruction is used but the operand size prefix (0x66) cannot be emitted in this context.

**Output:**
```
error[E525]: operand size prefix required but cannot be emitted
  → typically fires in restricted encoding contexts
```

---

## E526 — Redundant prefix

**Cause:** A prefix is specified that is already implied by the instruction encoding, and the combination is invalid.

**Triggers:**
```asm
db 0xF3, 0xF3      ; double REP prefix before an instruction
```

**Output:**
```
error[E526]: redundant prefix
  --> src/main.s:1:1
   |
 1 |     db 0xF3, 0xF3
   |     ^^^^^^^^^^^^
   |     duplicate REP (0xF3) prefix — only one may appear before an instruction
```

**Recovery:** Emit only one prefix.
**Related hints:** H526

---

## E527 — Conflicting prefixes

**Cause:** Two prefixes that cannot coexist are both specified.

**Triggers:**
```asm
lock rep movs [rdi], [rsi]  ; LOCK and REP cannot both prefix MOVS
```

**Output:**
```
error[E527]: conflicting prefixes
  --> src/main.s:1:1
   |
 1 |     lock rep movs [rdi], [rsi]
   |     ~~~~ ~~~
   |     'lock' and 'rep' cannot both prefix 'movs'
```

**Recovery:** Remove one prefix.
**Related hints:** H527

---

## E528 — Too many prefixes

**Cause:** More than 4 legacy prefixes appear before a single instruction.

**Output:**
```
error[E528]: too many prefixes
  --> src/main.s:1:1
   |
   maximum 4 legacy prefixes per instruction, found 5
```

**Recovery:** Use first 4 only.
**Related hints:** none

---

## E529 — LOCK prefix not allowed here

**Cause:** The LOCK prefix is applied to an instruction that does not support atomic locking.

**Lockable instructions:** ADD, ADC, AND, BTC, BTR, BTS, CMPXCHG, CMPXCHG8B, CMPXCHG16B, DEC, INC, NEG, NOT, OR, SBB, SUB, XOR, XADD, XCHG

**Triggers:**
```asm
lock mov [rax], rbx     ; MOV is not lockable
lock jmp label          ; JMP is not lockable
```

**Output:**
```
error[E529]: LOCK prefix not permitted with this instruction
  --> src/main.s:1:1
   |
 1 |     lock mov [rax], rbx
   |     ~~~~
   |     'mov' is not a lockable instruction
   |
   = note: lockable instructions: ADD ADC AND BTC BTR BTS CMPXCHG DEC INC NEG NOT OR SBB SUB XOR XADD XCHG
   = hint[H529]: use xchg [rax], rbx   ; XCHG is always atomic, no LOCK needed
```

**Recovery:** Remove LOCK prefix. Emit instruction without lock.
**Related hints:** H529

---

## E530 — REP prefix not allowed here

**Cause:** REP/REPE/REPNE is applied to an instruction that does not support it.

**REP-able instructions:** MOVS, STOS, LODS, CMPS, SCAS, INS, OUTS

**Triggers:**
```asm
rep mov [rax], rbx  ; MOV is not repeatable
rep add rax, rbx    ; ADD is not repeatable
```

**Output:**
```
error[E530]: REP prefix not permitted with this instruction
  --> src/main.s:1:1
   |
 1 |     rep mov [rax], rbx
   |     ~~~
   |     'mov' does not support the REP prefix
   |
   = note: REP is valid with: MOVS STOS LODS CMPS SCAS INS OUTS
```

**Recovery:** Remove REP. Emit instruction normally.
**Related hints:** H530

---

## E531 — REPNE prefix not allowed here

**Cause:** REPNE/REPNZ is used with an instruction that does not support it.

**REPNE-able instructions:** CMPS, SCAS only

**Output:** See E530 format.

---

## E532 — Invalid segment for this mode

**Cause:** A segment register is used in a context that does not support it in 64-bit mode.

**Output:**
```
error[E532]: segment register not valid in 64-bit mode
  --> src/main.s:1:5
   |
 1 |     mov es, rax
   |         ^^
   |         'es' segment register cannot be loaded in 64-bit mode
   |
   = note: only FS and GS segment loads are supported in 64-bit mode
```

**Recovery:** Skip instruction.
**Related hints:** H532

---

## E533 — Instruction only available in 64-bit mode

**Cause:** A 64-bit mode instruction is used but the assembler is in 16-bit or 32-bit mode.

**Triggers (in 32-bit BITS 32 mode):**
```asm
BITS 32
movsxd rax, eax    ; MOVSXD only exists in 64-bit mode
swapgs             ; SWAPGS only in 64-bit mode
```

**Output:**
```
error[E533]: instruction only available in 64-bit mode
  --> src/main.s:2:5
   |
 2 |     movsxd rax, eax
   |     ~~~~~~
   |     'movsxd' is only available in 64-bit mode (current mode: BITS 32)
   |
   = hint[H533]: add 'BITS 64' at the top of the file or switch to 64-bit mode
```

**Recovery:** Skip instruction.
**Related hints:** H533

---

## E534 — Instruction not available in 64-bit mode

**Cause:** An instruction that was removed or modified in 64-bit mode is used.

**Triggers:**
```asm
; in 64-bit mode:
aaa                 ; ASCII Adjust After Addition — removed in 64-bit
daa                 ; Decimal Adjust After Addition — removed
aam                 ; not in 64-bit
aad                 ; not in 64-bit
push es             ; segment register push — limited in 64-bit
```

**Output:**
```
error[E534]: instruction not available in 64-bit mode
  --> src/main.s:1:5
   |
 1 |     aaa
   |     ~~~
   |     'aaa' was removed in x86-64 (only available in 32-bit mode)
   |
   = note: AAA, AAD, AAM, AAS, DAA, DAS were removed in 64-bit mode
```

**Recovery:** Skip instruction.
**Related hints:** H534

---

# E6xx — Linker Errors

Fired during linking. Recovery: continue linking remaining symbols/sections.

---

## E601 — Undefined external symbol

**Cause:** A symbol declared `extern` or referenced in a relocation has no definition in any linked object.

**Output:**
```
error[E601]: undefined external symbol
  --> (linker)
   |
   'printf' is referenced but not defined in any linked object
   |
   = note: referenced from: src/main.s:42 (call printf)
   = hint[H601]: link with the library that provides 'printf', or define it yourself
```

**Recovery:** Cannot produce working binary. Output aborted.
**Related hints:** H601

---

## E602 — Symbol defined in multiple objects

**Cause:** The same non-weak symbol is defined in more than one linked object file.

**Output:**
```
error[E602]: symbol 'init' defined in multiple objects
  --> (linker)
   |
   defined in: src/init.s (line 5) and src/start.s (line 12)
   |
   = hint[H602]: rename one definition or declare one as 'weak'
```

**Recovery:** Use first definition.
**Related hints:** H602

---

## E603 — Section overlap in memory map

**Cause:** The linker script places two sections at overlapping addresses.

**Output:**
```
error[E603]: section overlap in memory layout
  --> (linker)
   |
   section '.text' (0x401000–0x402000) overlaps with '.data' (0x401800–0x402800)
   |
   = hint[H603]: check linker script section addresses or use automatic layout
```

**Recovery:** Cannot produce valid binary.
**Related hints:** H603

---

## E604 — Relocation overflow

**Cause:** A relocation value does not fit in the field it is being written to.

**Output:**
```
error[E604]: relocation overflow
  --> src/main.s:5:5
   |
 5 |     call distant_function
   |     ~~~~
   |     R_X86_64_PC32 relocation overflow: 'distant_function' is 4GB away (max: ±2GB)
   |
   = hint[H604]: use indirect call: mov rax, distant_function / call rax
```

**Recovery:** Write 0 to field. Binary will crash at this instruction.
**Related hints:** H604

---

## E605 — Invalid relocation type

**Cause:** A relocation type is not supported for the target architecture or output format.

**Output:**
```
error[E605]: relocation type not supported
  --> (linker)
   |
   relocation type R_X86_64_TLS_DTPMOD64 is not supported in flat binary output
```

**Recovery:** Skip relocation.
**Related hints:** none

---

## E606 — Relocation against undefined symbol

**Cause:** A relocation references a symbol that has no value (undefined).

**Output:**
```
error[E606]: relocation against undefined symbol
  --> (linker)
   |
   R_X86_64_PC32 relocation at .text+0x14 references 'missing' which is undefined
```

**Recovery:** Write 0 to field.
**Related hints:** H606

---

## E607 — Relocation in read-only section

**Cause:** A write relocation targets a read-only section.

**Output:**
```
error[E607]: cannot apply relocation to read-only section
  --> (linker)
   |
   R_X86_64_64 relocation in '.rodata' — section is read-only
```

**Recovery:** Skip relocation.
**Related hints:** H607

---

## E608 — Circular dependency between objects

**Cause:** Object files have circular symbol dependencies that cannot be resolved.

**Output:**
```
error[E608]: circular dependency detected
  --> (linker)
   |
   dependency chain: a.o → b.o → c.o → a.o
   |
   = hint[H608]: restructure symbols to break the cycle, or merge affected files
```

**Recovery:** Break cycle at arbitrary point.
**Related hints:** H608

---

## E609 — Entry point section not executable

**Cause:** The `_start` symbol is in a section with no execute permission.

**Output:**
```
error[E609]: entry point '_start' is in non-executable section '.data'
  --> (linker)
   |
   = hint[H609]: define _start in the .text section
```

**Recovery:** Emit binary anyway. OS will reject execution.
**Related hints:** H609

---

## E610 — Output file write error

**Cause:** utasm cannot write the output file due to permissions, disk space, or other I/O error.

**Output:**
```
error[E610]: cannot write output file
  --> (output)
   |
   failed to write 'output.o': Permission denied
```

**Recovery:** Fatal. Assembly aborts.
**Related hints:** none

---

## E611 — Invalid output format

**Cause:** An unknown or unsupported output format is specified.

**Triggers:**
```sh
utasm -f coff main.s    ; COFF not supported
```

**Output:**
```
error[E611]: unknown output format 'coff'
  --> (cli)
   |
   = note: supported formats: elf64, pe32plus, bin, upk
```

**Recovery:** Use default (elf64).
**Related hints:** H611

---

## E612 — Section too large for output format

**Cause:** A section exceeds the maximum size allowed by the output format.

**Output:**
```
error[E612]: section '.text' is too large for output format
  --> (output)
   |
   section size 4GB exceeds ELF32 maximum of 2GB
```

**Recovery:** Cannot produce valid output.
**Related hints:** none

---

## E613 — Too many sections for output format

**Cause:** The number of sections exceeds the limit of the output format.

**Output:**
```
error[E613]: too many sections
  --> (output)
   |
   65536 sections found — ELF format maximum is 65535 (SHN_XINDEX required)
```

**Recovery:** Continue. SHN_XINDEX handling emitted.
**Related hints:** none

---

## E614 — Too many symbols for output format

**Cause:** The symbol table exceeds the limit of the output format.

**Output:**
```
error[E614]: symbol table overflow
  --> (output)
   |
   more than 4294967295 symbols — exceeds ELF64 symbol table capacity
```

**Recovery:** Truncate symbol table.
**Related hints:** none

---

## E615–E620 — Additional linker/output errors

Reserved for string table overflow, ELF/PE generation errors, base address alignment, COMMON/weak resolution edge cases. Documented when implemented.

---

# E7xx — CPU Validation Errors

Fired when an instruction requires CPU features not in the active profile.

---

## E701–E716 — Missing CPU Feature

Format is consistent for all feature errors. Example:

## E710 — Instruction requires AVX-512F

**Cause:** An AVX-512 instruction is used but the active CPU profile does not include AVX-512F.

**Triggers:**
```asm
CPU GENERIC
vmovaps zmm0, [rax]     ; ZMM registers require AVX-512F
```

**Output:**
```
error[E710]: instruction requires AVX-512F
  --> src/main.s:2:5
   |
 2 |     vmovaps zmm0, [rax]
   |     ~~~~~~~
   |     'vmovaps' with ZMM register requires AVX-512F
   |     active CPU profile 'GENERIC' does not include AVX-512F
   |
   = hint[H710]: add 'CPU SERVER' or 'CPU ZEN4' at top of file to enable AVX-512F
```

**Recovery:** Skip instruction.
**Related hints:** H701–H716

---

## Feature Error Table

| Code | Feature Required |
|---|---|
| E701 | MMX |
| E702 | SSE |
| E703 | SSE2 |
| E704 | SSE3 |
| E705 | SSSE3 |
| E706 | SSE4.1 |
| E707 | SSE4.2 |
| E708 | AVX |
| E709 | AVX2 |
| E710 | AVX-512F |
| E711 | AVX-512BW |
| E712 | AVX-512DQ |
| E713 | AVX-512VL |
| E714 | AVX-512VNNI |
| E715 | AVX-512BF16 |
| E716 | AMX |
| E717 | RDRAND |
| E718 | RDSEED |
| E719 | XSAVE |
| E720 | AES-NI |
| E721 | PCLMULQDQ |
| E722 | SHA |
| E723 | CET (Control Flow Enforcement) |
| E724 | WAITPKG |

---

## E725 — Instruction not available in 64-bit mode

**Cause:** An instruction removed in 64-bit mode is used. (Same as E534 — E725 is the CPU-validation version.)

**Output:** See E534 format.

---

## E726 — Instruction not available in 32-bit mode

**Cause:** A 64-bit-only instruction is used with `BITS 32`.

**Output:** See E533 format.

---

## E727 — Instruction requires privilege level 0

**Cause:** A privileged instruction (ring 0 only) is used in user-mode code.

**Triggers:**
```asm
lgdt [gdt_ptr]      ; requires CPL = 0
lidt [idt_ptr]      ; requires CPL = 0
hlt                 ; HLT requires CPL = 0
```

**Output:**
```
warning[E727]: privileged instruction
  --> src/main.s:1:5
   |
 1 |     lgdt [gdt_ptr]
   |     ~~~~
   |     'lgdt' requires ring 0 (CPL = 0) — this will #GP fault in user mode
   |
   = note: this is a warning only — utasm cannot enforce ring level at assembly time
```

Note: This fires as a warning (W level) unless `-Werror` is active.
**Related hints:** none

---

## E728 — Instruction requires CPL check

**Cause:** An instruction requires specific privilege level checks (not strictly ring 0 but requires CR4 bits or similar).

**Output:** See E727 format.

---

## E729 — Deprecated instruction for target CPU

**Cause:** An instruction deprecated on the active CPU profile is used.

**Triggers:**
```asm
CPU ZEN4
fsin            ; x87 transcendental functions are very slow on modern CPUs
```

**Output:**
```
warning[W729]: deprecated instruction on target CPU
  --> src/main.s:2:5
   |
 2 |     fsin
   |     ~~~~
   |     'fsin' is available but extremely slow on Zen 4 (>100 cycles)
   |
   = hint[H729]: use SSE/AVX approximation for better performance
```

**Recovery:** Instruction encoded normally.
**Related hints:** H729

---

## E730 — Performance warning for target CPU

**Cause:** An instruction has known performance issues on the active CPU.

**Output:**
```
warning[W730]: performance warning
  --> src/main.s:1:5
   |
 1 |     movaps xmm0, xmm1
   |     ~~~~~~
   |     mixing non-VEX 'movaps' with VEX instructions causes AVX-SSE transition penalty
   |
   = hint[H730]: use vmovaps to avoid transition penalty on processors that support AVX
```

**Related hints:** H730

---

# E8xx — Internal Errors

These indicate bugs in utasm. Always report with source file and utasm version.

---

## E801–E815 — Internal Errors

| Code | Description |
|---|---|
| E801 | Internal: symbol table corruption |
| E802 | Internal: token buffer overflow |
| E803 | Internal: AST node allocation failed |
| E804 | Internal: relocation table full |
| E805 | Internal: section buffer overflow |
| E806 | Internal: string table corruption |
| E807 | Internal: encoder state invalid |
| E808 | Internal: output buffer overflow |
| E809 | Internal: stack overflow in expression evaluator |
| E810 | Internal: unexpected null pointer |
| E811 | Internal: assertion failed |
| E812 | Internal: out of memory |
| E813 | Internal: file handle leak |
| E814 | Internal: invalid internal state transition |
| E815 | Please report this bug |

**Output for all E8xx:**
```
internal error[E8xx]: {description}
  --> src/main.s:{line}:{col}

This is a bug in utasm. Please report it at:
  https://utkarsha.dev/bugs

Include:
  - this error message
  - your source file
  - utasm version: utasm --version
  - command line used
```

**Recovery:** Fatal. utasm aborts immediately.

---

# E9xx — Expression Errors

---

## E901 — Division by zero in constant expression

**Cause:** A compile-time constant expression divides by zero.

**Output:** See E221 — same error, different category. E221 is the parser-level version, E901 is the expression-evaluator-level version. Both produce identical output.

---

## E902 — Integer overflow in constant expression

**Cause:** A constant expression produces a result that overflows 64-bit.

**Output:** See E223 format.

---

## E903 — Expression is not constant

**Cause:** A context requires a compile-time constant but the expression contains a forward reference or runtime value.

**Output:**
```
error[E903]: expression must be constant
  --> src/main.s:3:10
   |
 3 |     ALIGN runtime_value
   |           ~~~~~~~~~~~~~
   |           'runtime_value' is not a compile-time constant
   |
   = hint[H903]: use EQU to define compile-time constants: ALIGN_VAL equ 16 / ALIGN ALIGN_VAL
```

**Recovery:** Use value 1.
**Related hints:** H903

---

# E10xx — Directive Errors

---

## E1001 — Unknown directive

**Cause:** A directive that is not recognized by utasm.

**Triggers:**
```asm
.global my_func     ; GAS syntax — use utasm 'global' instead
.section .text      ; GAS syntax — use utasm 'section .text'
```

**Output:**
```
error[E1001]: unknown directive '.global'
  --> src/main.s:1:1
   |
 1 |     .global my_func
   |     ^~~~~~~
   |     '.global' is not a utasm directive
   |
   = hint[H1001]: utasm uses 'global my_func' (no dot prefix)
```

**Recovery:** Skip directive.
**Related hints:** H1001

---

## E1002 — Directive not valid in current context

**Cause:** A directive appears where it is not permitted (e.g., ENDSTRUC without STRUC).

**Output:**
```
error[E1002]: directive not valid here
  --> src/main.s:5:1
   |
 5 |     endstruc
   |     ~~~~~~~~
   |     'endstruc' found but no struct definition is open
```

**Recovery:** Ignore directive.
**Related hints:** none

---

# E11xx — Include Errors

---

## E1101 — Include file not found

**Cause:** Same as E319. E1101 fires from the include processing engine, E319 from the macro engine.

**Output:** See E319 format.

---

## E1102 — Include depth exceeded

**Cause:** Files include each other to a depth greater than MAX_INCLUDE_DEPTH (64).

**Output:**
```
error[E1102]: include depth exceeded
  --> include_63.inc:1:1
   |
 1 |     %include "include_64.inc"
   |              ^~~~~~~~~~~~~~~~
   |              maximum include depth (64) exceeded
   |
   = note: include chain contains 64 levels
```

**Recovery:** Skip include.
**Related hints:** H1102

---

## E1103 — Circular include detected

**Cause:** Same as E320.

---

# E12xx–E30xx — Additional Error Categories

The following categories follow the same documentation pattern as above. Each error has a code, cause, trigger example, exact output format, recovery behavior, and related hints. Detailed expansion of each category is ongoing and updated as each phase is implemented.

| Category | Codes | Status |
|---|---|---|
| E12xx — Section errors | E1201–E1220 | Defined, detailed in Phase 7 implementation |
| E13xx — Visibility errors | E1301–E1320 | Defined, detailed in Phase 7 implementation |
| E14xx — Relocation errors | E1401–E1420 | Defined, detailed in Phase 10 implementation |
| E15xx — ELF output errors | E1501–E1520 | Defined, detailed in Phase 11 implementation |
| E16xx — PE output errors | E1601–E1620 | Defined, detailed in Phase 11 implementation |
| E17xx — Flat binary errors | E1701–E1720 | Defined, detailed in Phase 11 implementation |
| E18xx — Package errors | E1801–E1820 | Defined, detailed in Phase 11 implementation |
| E19xx — Debug info errors | E1901–E1920 | Defined, detailed in Phase 16 implementation |
| E20xx — Data errors | E2001–E2020 | Defined, detailed in Phase 5 implementation |
| E21xx — Alignment errors | E2101–E2120 | Defined, detailed in Phase 5 implementation |
| E22xx — Scope errors | E2201–E2220 | Defined, detailed in Phase 7 implementation |
| E23xx — Type errors | E2301–E2320 | Defined, detailed in Phase 8 implementation |
| E24xx — Privilege errors | E2401–E2420 | Defined, detailed in Phase 9 implementation |
| E25xx — SIMD errors | E2501–E2520 | Defined, detailed in Phase 8 implementation |
| E26xx — Memory model errors | E2601–E2620 | Defined, detailed in Phase 8 implementation |
| E27xx — Self-patch errors | E2701–E2720 | Defined, detailed in Phase 18 implementation |
| E28xx — Package errors | E2801–E2820 | Defined, detailed in Phase 11 implementation |
| E29xx — Security errors | E2901–E2920 | Defined, detailed in Phase 9 implementation |
| E30xx — Compatibility errors | E3001–E3020 | Defined, detailed in Phase 11 implementation |

---

# W — Warnings

Warnings are non-fatal. All warnings can be suppressed with `-Wno-NNN` and promoted to errors with `-Werror` or `-Werror=NNN`.

---

## W201 — Label defined but never referenced

**Cause:** A label is defined but never jumped to or referenced.

**Output:**
```
warning[W201]: label 'unused_label' defined but never referenced
  --> src/main.s:5:1
   |
 5 |     unused_label:
   |     ^^^^^^^^^^^^
   |
   = hint[H501]: remove if unused, or prefix with '_' to suppress: _unused_label:
```

**Suppress:** `-Wno-201`

---

## W202 — Unreachable instruction

**Cause:** An instruction appears after an unconditional jump, return, or HLT with no label between them.

**Output:**
```
warning[W202]: unreachable instruction
  --> src/main.s:3:5
   |
 1 |     jmp end
 2 |     nop          ; unreachable
   |     ~~~
   = hint[H202]: remove unreachable code or add a label to make it reachable
```

**Suppress:** `-Wno-202`

---

## W301 — Macro argument unused

**Cause:** A macro parameter `%N` is defined but never used in the macro body.

**Output:**
```
warning[W301]: macro argument '%2' unused in 'MY_MACRO'
  --> src/main.s:1:12
   |
 1 |     %macro MY_MACRO 2
   |                     ^
   |     parameter '%2' is defined but never used in the macro body
```

**Suppress:** `-Wno-301`

---

## W302 — Macro defined but never used

**Cause:** A `%define` or `%macro` is defined but never expanded.

**Output:**
```
warning[W302]: macro 'MY_MACRO' defined but never used
  --> src/main.s:1:9
   |
 1 |     %define MY_MACRO 42
   |             ^^^^^^^^
```

**Suppress:** `-Wno-302`

---

## W501 — Short jump suboptimal

**Cause:** utasm selected a NEAR (5-byte) jump where a SHORT (2-byte) jump would have worked, suggesting the code layout could be optimized.

**Output:**
```
warning[W501]: near jump used where short jump would suffice
  --> src/main.s:1:5
   |
 1 |     jmp nearby_label
   |     ~~~ — target is 45 bytes away (short range: ±127 bytes)
   |
   = hint[H501]: rearrange code to bring target within 127 bytes
```

**Suppress:** `-Wno-501`

---

## W503 — NOP instruction

**Cause:** A NOP instruction appears in code (may be intentional for alignment or timing, but worth noting).

**Output:**
```
warning[W503]: NOP instruction — is this intentional?
  --> src/main.s:5:5
   |
 5 |     nop
   |     ~~~
   = hint[H503]: use ALIGN for padding instead of explicit NOPs
```

**Suppress:** `-Wno-503`

---

## W505 — Unaligned memory access

**Cause:** A memory operand has a displacement or address that suggests the access may be unaligned, which causes performance penalties on most CPUs.

**Output:**
```
warning[W505]: potentially unaligned memory access
  --> src/main.s:3:5
   |
 3 |     movaps xmm0, [rax + 1]
   |             ~~~~~~~~~~~~~~
   |             'movaps' requires 16-byte alignment — displacement '+1' is not aligned
   |
   = hint[H505]: use movups for unaligned access, or ensure address is aligned
```

**Suppress:** `-Wno-505`

---

## W601 — Empty section

**Cause:** A section is declared but contains no data or code.

**Output:**
```
warning[W601]: section '.my_section' is empty
  --> src/main.s:1:9
   |
 1 |     section .my_section
   |             ~~~~~~~~~~~
```

**Suppress:** `-Wno-601`

---

## W702 — Mixing AVX and non-VEX SSE instructions

**Cause:** AVX (VEX-encoded) and legacy SSE (non-VEX) instructions are mixed, causing AVX-SSE transition penalties on certain CPUs.

**Output:**
```
warning[W702]: mixing VEX and non-VEX encoding causes AVX-SSE transition penalty
  --> src/main.s:3:5
   |
 1 |     vmovaps xmm0, xmm1    ; VEX encoded
 2 |     vmulps  xmm0, xmm0, xmm2
 3 |     movaps  xmm3, xmm0    ; non-VEX — causes transition penalty
   |     ~~~~~~
   |
   = hint[H702]: use 'vmovaps' (VEX) consistently throughout the function
```

**Suppress:** `-Wno-702`

---

## W703 — EVEX encoding where VEX would suffice

**Cause:** An EVEX instruction is used for a 128/256-bit operation where the equivalent VEX instruction would produce shorter encoding with identical behavior.

**Output:**
```
warning[W703]: EVEX encoding used where VEX would produce shorter code
  --> src/main.s:1:5
   |
 1 |     vmovaps xmm0{k0}, xmm1    ; EVEX with {k0} (no mask) — same as VEX vmovaps
   |     ~~~~~~~~
   |
   = hint[H703]: vmovaps xmm0, xmm1   ; VEX form is 2 bytes shorter
```

**Suppress:** `-Wno-703`

---

# N — Notes

Notes provide additional context attached to errors. They are never standalone — always follow an error or warning.

| Code | Description |
|---|---|
| N101 | Symbol resolution: which definition was chosen |
| N102 | Symbol resolution: multiple definitions found |
| N201 | Macro expansion chain |
| N202 | Macro argument substitution |
| N301 | Optimization applied |
| N302 | Optimization not applied (reason) |
| N401 | CPU feature compatibility context |
| N402 | Instruction encoding choice |
| N501 | Section layout information |
| N502 | Alignment padding inserted |

---

# H — Hints

Hints are actionable fix suggestions attached to errors. They always contain correct code examples.

| Range | Category |
|---|---|
| H101–H199 | Lexer fix suggestions |
| H201–H299 | Parser fix suggestions |
| H301–H399 | Macro fix suggestions |
| H401–H499 | Semantic fix suggestions |
| H501–H599 | Encoder fix suggestions |
| H601–H699 | Linker fix suggestions |
| H701–H799 | CPU fix suggestions |
| H801–H899 | (reserved — internal errors have no hints) |
| H901–H999 | Expression fix suggestions |

---

## Hint Format

Every hint contains:
1. A short description of the fix
2. Correct code that resolves the error

```
= hint[H513]: load source into register first:
              mov rcx, [rbx]
              mov [rax], rcx
```

---

## Quick Reference — Most Common Errors

| Code | Short Description |
|---|---|
| E101 | Invalid character |
| E102 | Unterminated string |
| E201 | Unexpected token |
| E226 | Ambiguous operand size — add BYTE/WORD/DWORD/QWORD PTR |
| E301 | Undefined macro — check spelling or add %define |
| E401 | Undefined symbol — add extern or check spelling |
| E402 | Symbol redefined — labels must be unique |
| E501 | Operand size mismatch — AL vs RAX |
| E513 | Two memory operands — load one into register first |
| E529 | LOCK on non-lockable instruction |
| E601 | Undefined external — add extern or link library |
| E710 | Instruction needs AVX-512 — change CPU profile |

---

---

# E31xx — Assembler Directive Errors

Fired when directive usage is structurally invalid. Recovery: skip directive, continue.

---

## E3101 — TIMES with non-integer count

**Cause:** The count expression in a TIMES directive evaluates to a non-integer (float or symbol with no integer value).

**Triggers:**
```asm
TIMES 1.5 db 0      ; float count
TIMES 3.0 db 0      ; float even if whole number
```

**Output:**
```
error[E3101]: TIMES count must be an integer
  --> src/main.s:1:7
   |
 1 |     TIMES 1.5 db 0
   |           ^^^
   |           TIMES count '1.5' is not an integer
   |
   = hint[H3101]: TIMES 1 db 0   ; use integer count
```

**Recovery:** Truncate to integer.
**Related hints:** H3101

---

## E3102 — ALIGN value not power of 2

**Cause:** Same as E417 but fired specifically from the directive parser rather than the semantic layer.

**Triggers:**
```asm
ALIGN 3
ALIGN 6
ALIGN 100
```

**Output:** See E417 format.
**Recovery:** Round up to next power of 2.

---

## E3103 — ALIGN in wrong section

**Cause:** ALIGN is used in a section where alignment is meaningless or unsupported (e.g., absolute or external section).

**Triggers:**
```asm
section absolute
ALIGN 16            ; E3103 — cannot align in absolute section
```

**Output:**
```
error[E3103]: ALIGN not permitted in this section type
  --> src/main.s:2:5
   |
 2 |     ALIGN 16
   |     ~~~~~~~~
   |     'ALIGN' cannot be used in an absolute section
   |
   = note: current section type: absolute
```

**Recovery:** Ignore ALIGN.
**Related hints:** none

---

## E3104 — RESB/W/D/Q in initialized section

**Cause:** RES* (reserve) directives can only be used in uninitialized sections (BSS). Using them in .text or .data is invalid.

**Triggers:**
```asm
section .text
resb 64             ; E3104 — .text is initialized
section .data
resq 8              ; E3104 — .data is initialized
```

**Output:**
```
error[E3104]: RES* directive not permitted in initialized section
  --> src/main.s:2:5
   |
 2 |     resb 64
   |     ~~~~
   |     'resb' can only be used in uninitialized sections (BSS)
   |     current section '.text' is initialized
   |
   = hint[H3104]: switch to BSS section first:
                  section .bss
                  resb 64
```

**Recovery:** Skip directive.
**Related hints:** H3104

---

## E3105 — INCBIN file not found

**Cause:** An INCBIN directive references a file that cannot be found.

**Triggers:**
```asm
incbin "missing_data.bin"
incbin "assets/image.raw"   ; file does not exist
```

**Output:**
```
error[E3105]: INCBIN file not found
  --> src/main.s:1:8
   |
 1 |     incbin "missing_data.bin"
   |            ^~~~~~~~~~~~~~~~~
   |            cannot find 'missing_data.bin'
   |
   = note: search path: ./
   = hint[H3105]: check filename and path: incbin "path/to/data.bin"
```

**Recovery:** Emit nothing. Assembly continues.
**Related hints:** H3105

---

## E3106 — INCBIN file too large

**Cause:** An INCBIN file exceeds the maximum embeddable size (typically available address space minus existing content).

**Triggers:**
```asm
incbin "huge_file.bin"      ; file larger than remaining address space
```

**Output:**
```
error[E3106]: INCBIN file too large
  --> src/main.s:1:8
   |
 1 |     incbin "huge_file.bin"
   |            ^~~~~~~~~~~~~~~
   |            file size 8GB exceeds available space in section '.data'
   |
   = hint[H3106]: use INCBIN with offset and size limits:
                  incbin "file.bin", 0, 65536   ; first 64KB only
```

**Recovery:** Include as much as fits.
**Related hints:** H3106

---

## E3107 — EQU redefinition

**Cause:** A constant defined with EQU is assigned a second time. EQU constants are immutable.

**Triggers:**
```asm
MAX equ 100
MAX equ 200         ; E3107
```

**Output:**
```
error[E3107]: EQU constant redefinition
  --> src/main.s:2:1
   |
 2 |     MAX equ 200
   |     ~~~
   |     'MAX' is already defined as EQU constant — EQU values are immutable
   |
   = note: previous definition at src/main.s:1 with value 100
   = hint[H3107]: use %define for mutable constants: %define MAX 200
```

**Recovery:** Keep original value.
**Related hints:** H3107

---

## E3108 — EQU forward reference

**Cause:** Same as E405 — fired specifically from the directive parser.

**Output:** See E405 format.

---

## E3109 — STRUC field redefinition

**Cause:** A field name is defined twice within the same STRUC block.

**Triggers:**
```asm
struc MyStruct
    .x resd 1
    .y resd 1
    .x resq 1       ; E3109 — .x already defined
endstruc
```

**Output:**
```
error[E3109]: struct field redefinition
  --> src/main.s:4:5
   |
 4 |     .x resq 1
   |     ^^
   |     field '.x' is already defined in 'MyStruct'
   |
   = note: previous definition at src/main.s:2 (size: 4 bytes)
```

**Recovery:** Ignore redefinition. Keep first field.
**Related hints:** none

---

## E3110 — ENDSTRUC without STRUC

**Cause:** ENDSTRUC appears without a matching STRUC.

**Triggers:**
```asm
mov rax, rbx
endstruc            ; no STRUC open
```

**Output:**
```
error[E3110]: 'endstruc' without matching 'struc'
  --> src/main.s:2:1
   |
 2 |     endstruc
   |     ~~~~~~~~
   |     'endstruc' found but no struct definition is open
```

**Recovery:** Ignore ENDSTRUC.
**Related hints:** none

---

## E3111 — ISTRUC without matching STRUC

**Cause:** ISTRUC is used to instantiate a struct type that was never defined with STRUC.

**Triggers:**
```asm
istruc UndefinedType    ; UndefinedType was never defined with struc
    at .field, dd 0
iend
```

**Output:**
```
error[E3111]: 'istruc' references undefined struct type
  --> src/main.s:1:8
   |
 1 |     istruc UndefinedType
   |            ^~~~~~~~~~~~~
   |            'UndefinedType' is not defined — use 'struc' to define struct types
   |
   = hint[H3111]: define the struct first:
                  struc UndefinedType
                      .field resd 1
                  endstruc
```

**Recovery:** Skip ISTRUC block.
**Related hints:** H3111

---

## E3112 — AT offset out of bounds

**Cause:** An AT directive inside an ISTRUC block specifies an offset that exceeds the struct's defined size.

**Triggers:**
```asm
struc Small
    .x resd 1       ; size = 4 bytes
endstruc

istruc Small
    at .x + 8, dd 0 ; E3112 — offset 8 is outside Small (size 4)
iend
```

**Output:**
```
error[E3112]: AT offset out of struct bounds
  --> src/main.s:6:5
   |
 6 |     at .x + 8, dd 0
   |        ~~~~~~
   |        offset 8 exceeds struct 'Small' size (4 bytes)
   |
   = note: struct 'Small' is 4 bytes (field '.x' at offset 0)
```

**Recovery:** Clamp to struct size.
**Related hints:** none

---

# E32xx — Preprocessor Errors

Fired during preprocessor directive processing. Recovery: skip directive, continue.

---

## E3201 — %ASSIGN to non-identifier

**Cause:** `%assign` is used with a target that is not a valid identifier.

**Triggers:**
```asm
%assign 42 100      ; 42 is not an identifier
%assign "name" 5    ; string is not an identifier
```

**Output:**
```
error[E3201]: %assign target must be an identifier
  --> src/main.s:1:9
   |
 1 |     %assign 42 100
   |             ^^
   |             '42' is not a valid identifier for %assign
   |
   = hint[H3201]: %assign MY_VAR 100
```

**Recovery:** Skip directive.
**Related hints:** H3201

---

## E3202 — %IASSIGN redefinition of non-assign symbol

**Cause:** `%iassign` (case-insensitive assign) attempts to redefine a symbol that was defined with `%define` or `%macro`, not `%assign`.

**Triggers:**
```asm
%define MY_VAR 100
%iassign MY_VAR 200     ; E3202 — MY_VAR is a %define, not %assign
```

**Output:**
```
error[E3202]: %iassign cannot redefine a %define symbol
  --> src/main.s:2:10
   |
 2 |     %iassign MY_VAR 200
   |              ~~~~~~
   |              'MY_VAR' was defined with '%define' — use '%idefine' to redefine
   |
   = note: previous definition at src/main.s:1
```

**Recovery:** Ignore redefinition.
**Related hints:** H3202

---

## E3203 — %STR stringification of multi-token expression

**Cause:** `%str()` is applied to an expression containing multiple tokens, which produces ambiguous output.

**Triggers:**
```asm
%define RESULT %str(1 + 2)     ; multi-token: what string should this produce?
```

**Output:**
```
error[E3203]: %str() cannot stringify multi-token expression
  --> src/main.s:1:16
   |
 1 |     %define RESULT %str(1 + 2)
   |                    ~~~~~~~~~~
   |                    %str() requires a single token — '1 + 2' has 3 tokens
   |
   = hint[H3203]: evaluate first: %assign VAL 1+2 / %define RESULT %str(VAL)
```

**Recovery:** Use empty string.
**Related hints:** H3203

---

## E3204 — %SEL (select) index out of range

**Cause:** The `%sel()` directive selects a token by index, but the index exceeds the available token count.

**Triggers:**
```asm
%define PICK %sel(5, a, b, c)  ; index 5, only 3 tokens
```

**Output:**
```
error[E3204]: %sel() index out of range
  --> src/main.s:1:16
   |
 1 |     %define PICK %sel(5, a, b, c)
   |                   ^
   |                   index '5' out of range — only 3 tokens provided (valid: 1–3)
   |
   = hint[H3204]: %sel(2, a, b, c)   ; selects 'b'
```

**Recovery:** Use last token.
**Related hints:** H3204

---

## E3205 — %ERROR user-defined error

**Cause:** The `%error` directive is explicitly used by the developer to signal a fatal condition.

**Triggers:**
```asm
%ifndef REQUIRED_DEFINE
    %error "REQUIRED_DEFINE must be set before including this file"
%endif
```

**Output:**
```
error[E3205]: REQUIRED_DEFINE must be set before including this file
  --> src/main.s:2:5
   |
 2 |     %error "REQUIRED_DEFINE must be set before including this file"
   |     ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   |     user-defined error
   |
   = note: %error is used intentionally by the source author
```

**Recovery:** Fatal — assembly aborts at this point.
**Related hints:** none

---

## E3206 — %WARNING user-defined warning

**Cause:** The `%warning` directive explicitly emits a user-defined warning.

**Triggers:**
```asm
%warning "This path is deprecated — use the new API"
```

**Output:**
```
warning[E3206]: This path is deprecated — use the new API
  --> src/main.s:1:1
   |
 1 |     %warning "This path is deprecated — use the new API"
   |     user-defined warning
```

**Recovery:** Continue assembly.
**Suppress:** `-Wno-3206`

---

## E3207 — %FATAL user-defined fatal error

**Cause:** `%fatal` explicitly triggers an immediate abort with a message. Unlike `%error`, `%fatal` does not attempt to continue after the current pass.

**Triggers:**
```asm
%if BITS != 64
    %fatal "This code only supports 64-bit mode"
%endif
```

**Output:**
```
fatal[E3207]: This code only supports 64-bit mode
  --> src/main.s:2:5
   |
 2 |     %fatal "This code only supports 64-bit mode"
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |     user-defined fatal error — assembly aborted immediately
```

**Recovery:** Immediate abort. No further processing.
**Related hints:** none

---

## E3208 — %LINE directive invalid format

**Cause:** A `%line` directive (used to set the apparent line number for error messages) has invalid syntax.

**Triggers:**
```asm
%line notanumber+1 "file.s"     ; count must be integer
%line 10                         ; filename is required
```

**Output:**
```
error[E3208]: invalid %line directive format
  --> src/main.s:1:1
   |
 1 |     %line notanumber+1 "file.s"
   |           ~~~~~~~~~~~
   |           %line requires an integer line number
   |
   = note: format: %line integer+delta "filename"
   = hint[H3208]: %line 42+0 "generated.s"
```

**Recovery:** Keep current line information.
**Related hints:** H3208

---

## E3209 — %DEFSTR/%DEFFLOAT invalid operand

**Cause:** `%defstr` or `%deffloat` is given an operand of the wrong type.

**Triggers:**
```asm
%defstr MY_NUM 42       ; 42 is not a string — should be %define MY_STR "42"
%deffloat MY_INT 42     ; 42 is not a float
```

**Output:**
```
error[E3209]: invalid operand for %defstr
  --> src/main.s:1:9
   |
 1 |     %defstr MY_NUM 42
   |                    ^^
   |                    %defstr requires a string literal operand, found integer '42'
   |
   = hint[H3209]: %defstr MY_NUM "42"
```

**Recovery:** Skip directive.
**Related hints:** H3209

---

## E3210 — %PATHSEARCH file not found

**Cause:** `%pathsearch` cannot locate a file in any directory of the include search path.

**Triggers:**
```asm
%pathsearch RESULT, "missing.inc"   ; file not in any search directory
```

**Output:**
```
error[E3210]: %pathsearch: file not found in search path
  --> src/main.s:1:13
   |
 1 |     %pathsearch RESULT, "missing.inc"
   |                         ^~~~~~~~~~~~~
   |                         'missing.inc' not found in any include search directory
   |
   = note: search path: ./ ./include/ /usr/local/include/utasm/
   = hint[H3210]: add the directory with -I path/to/dir or check filename spelling
```

**Recovery:** RESULT defined as empty string.
**Related hints:** H3210

---

# E33xx — Multi-File and Linker Errors (Extended)

These extend E6xx with more specific multi-file and linker script errors.

---

## E3301 — EXTERN symbol also defined locally

**Cause:** Same as E412 but fired from the linker stage rather than the semantic stage.

**Output:** See E412 format.

---

## E3302 — GLOBAL symbol not exported

**Cause:** A symbol marked GLOBAL cannot be placed in the ELF symbol table because it does not meet export requirements.

**Output:**
```
error[E3302]: symbol 'my_func' cannot be exported
  --> (linker)
   |
   'my_func' is declared global but is in a non-allocatable section
   |
   = hint[H3302]: ensure globally exported symbols are in .text or .data
```

**Recovery:** Skip export.
**Related hints:** H3302

---

## E3303 — COMMON symbol size mismatch across objects

**Cause:** The same COMMON symbol is declared with different sizes in different object files.

**Output:**
```
error[E3303]: COMMON symbol size mismatch
  --> (linker)
   |
   'buffer' declared as COMMON 1024 bytes in main.s
   'buffer' declared as COMMON 2048 bytes in util.s
   |
   = hint[H3303]: use the same COMMON size in all translation units
```

**Recovery:** Use the largest size.
**Related hints:** H3303

---

## E3304 — Archive (.a) format error

**Cause:** A static archive file is malformed or not a valid `.a` format.

**Triggers:**
```sh
utasm -f elf64 main.s lib/corrupt.a -o out
```

**Output:**
```
error[E3304]: invalid archive format
  --> (linker)
   |
   'lib/corrupt.a': not a valid static archive (expected '!<arch>' header)
   |
   = hint[H3304]: rebuild the archive with: ar rcs lib.a obj1.o obj2.o
```

**Recovery:** Skip archive. Continue with remaining inputs.
**Related hints:** H3304

---

## E3305 — Archive member is not an object file

**Cause:** A file inside an archive is not an ELF object file.

**Output:**
```
error[E3305]: archive member is not an object file
  --> (linker)
   |
   'lib/mylib.a(readme.txt)': member is not an ELF object file
   |
   = note: archives should contain only .o object files
```

**Recovery:** Skip member. Continue with other members.
**Related hints:** none

---

## E3306 — Linker script syntax error

**Cause:** The linker script (`utasm.ld` or `-T script.ld`) contains invalid syntax.

**Triggers:**
```
/* linker script */
SECTIONS {
    .text : { *(.text) }
    .data : { *(.data)   /* missing closing brace */
}
```

**Output:**
```
error[E3306]: linker script syntax error
  --> utasm.ld:4:14
   |
 4 |     .data : { *(.data)
   |              ^
   |              expected '}' to close section definition, found end of block
   |
   = hint[H3306]: close section definition: .data : { *(.data) }
```

**Recovery:** Skip to next section definition.
**Related hints:** H3306

---

## E3307 — Linker script undefined symbol

**Cause:** A linker script references a symbol that is not defined in any input object.

**Triggers:**
```
ENTRY(_start_custom)    /* _start_custom not defined anywhere */
```

**Output:**
```
error[E3307]: linker script references undefined symbol
  --> utasm.ld:1:7
   |
 1 |     ENTRY(_start_custom)
   |           ~~~~~~~~~~~~~
   |           '_start_custom' is not defined in any input object
   |
   = hint[H3307]: define '_start_custom' in your source or use a defined entry point
```

**Recovery:** Use default entry `_start` if defined.
**Related hints:** H3307

---

## E3308 — Output section overflow

**Cause:** The combined size of input sections mapped to one output section exceeds the allocated address range.

**Output:**
```
error[E3308]: output section overflow
  --> (linker)
   |
   section '.text' at 0x401000, size limit 0x1000 — content size is 0x2500
   |
   = hint[H3308]: increase section address range in linker script or reduce code size
```

**Recovery:** Truncate at limit. Binary will be broken.
**Related hints:** H3308

---

## E3309 — PHDR segment alignment error

**Cause:** A program header segment has an alignment value that is not a power of 2, or conflicts with the page size.

**Output:**
```
error[E3309]: program header alignment error
  --> (linker)
   |
   PT_LOAD segment alignment 3 is not a power of 2
   |
   = hint[H3309]: use page-aligned segments: alignment must be power of 2 (typically 0x1000)
```

**Recovery:** Round up to next power of 2.
**Related hints:** H3309

---

## E3310 — Dynamic symbol table overflow

**Cause:** The number of dynamic symbols exceeds the ELF format limit for the dynamic symbol table.

**Output:**
```
error[E3310]: dynamic symbol table overflow
  --> (linker)
   |
   more than 65535 dynamic symbols — .dynsym table overflow
   |
   = hint[H3310]: reduce the number of exported symbols or use static linking
```

**Recovery:** Truncate at limit.
**Related hints:** H3310

---

# E34xx — Floating Point Errors

---

## E3401 — Float literal underflow

**Cause:** A floating-point literal is too small to be represented (closer to zero than the smallest normal double).

**Triggers:**
```asm
dq 5.0e-325     ; below IEEE 754 subnormal minimum
```

**Output:**
```
error[E3401]: float literal underflow
  --> src/main.s:1:4
   |
 1 |     dq 5.0e-325
   |        ~~~~~~~~
   |        value underflows IEEE 754 double precision (minimum subnormal: 5.0e-324)
   |
   = hint[H3401]: use 0.0 for zero, or increase the exponent
```

**Recovery:** Use +0.0.
**Related hints:** H3401

---

## E3402 — Float literal is NaN or Infinity when not expected

**Cause:** A float expression produces NaN or ±Infinity in a context that does not explicitly allow it.

**Triggers:**
```asm
dq 1.0 / 0.0    ; produces +Inf at compile time
dq 0.0 / 0.0    ; produces NaN
```

**Output:**
```
error[E3402]: float literal produces NaN or Infinity
  --> src/main.s:1:4
   |
 1 |     dq 1.0 / 0.0
   |        ~~~~~~~~~
   |        expression evaluates to +Infinity
   |
   = note: if intentional, use explicit bit pattern: dq 0x7FF0000000000000   ; +Inf
   = hint[H3402]: dq 0x7FF0000000000000   ; explicit +Infinity bit pattern
```

**Recovery:** Use 0.0.
**Related hints:** H3402

---

## E3403 — DQ used for float but should be DD or DO

**Cause:** A float value is placed in a DQ (64-bit) field but the value is clearly a 32-bit float literal, suggesting DD should be used. (This is a warning-level diagnostic.)

**Triggers:**
```asm
dq 3.14f        ; 'f' suffix suggests single precision — should be dd
```

**Output:**
```
warning[E3403]: single-precision float literal in DQ field
  --> src/main.s:1:4
   |
 1 |     dq 3.14f
   |        ~~~~
   |        'f' suffix indicates single-precision (32-bit) float — use 'dd' for float32
   |
   = hint[H3403]: dd 3.14   ; single-precision (32-bit)
                  dq 3.14   ; double-precision (64-bit)
```

**Recovery:** Store as 64-bit. Assembly continues.
**Related hints:** H3403

---

## E3404 — x87 FPU stack overflow

**Cause:** More than 8 values are pushed onto the x87 FPU stack (detected at assembly time through static analysis).

**Triggers:**
```asm
fld qword [a]
fld qword [b]
fld qword [c]
fld qword [d]
fld qword [e]
fld qword [f]
fld qword [g]
fld qword [h]
fld qword [i]   ; 9th push — stack overflow
```

**Output:**
```
warning[E3404]: x87 FPU stack overflow detected
  --> src/main.s:9:5
   |
 9 |     fld qword [i]
   |     ~~~
   |     static analysis: x87 stack depth reaches 9 (maximum: 8)
   |
   = note: x87 stack overflow causes #IS exception at runtime
   = hint[H3404]: pop values with FSTP before pushing more: fstp qword [result]
```

**Recovery:** Emit instruction. Runtime will fault.
**Related hints:** H3404

---

## E3405 — x87 FPU stack underflow

**Cause:** A pop or operation occurs when the x87 stack is empty (detected at assembly time through static analysis).

**Triggers:**
```asm
fstp qword [result]     ; without a prior fld — stack is empty
```

**Output:**
```
warning[E3405]: x87 FPU stack underflow detected
  --> src/main.s:1:5
   |
 1 |     fstp qword [result]
   |     ~~~~
   |     static analysis: x87 stack is empty at this point
   |
   = note: x87 stack underflow causes #IS exception at runtime
   = hint[H3405]: ensure a value is loaded first: fld qword [source]
```

**Recovery:** Emit instruction. Runtime will fault.
**Related hints:** H3405

---

## E3406 — SSE/AVX float size mismatch

**Cause:** An SSE/AVX instruction operates on floating-point elements of a size that does not match the operand registers.

**Triggers:**
```asm
addss xmm0, ymm1    ; ADDSS (scalar single) + YMM (256-bit) — size conflict
vaddpd xmm0, xmm1, zmm2  ; ADDPD (double) mixing XMM and ZMM
```

**Output:**
```
error[E3406]: SSE/AVX float size mismatch
  --> src/main.s:1:5
   |
 1 |     addss xmm0, ymm1
   |     ~~~~~       ^^^^
   |     'addss' operates on scalar 32-bit float (XMM), but 'ymm1' is 256-bit
   |
   = hint[H3406]: addss xmm0, xmm1   ; both XMM for scalar single
                  vaddps ymm0, ymm1, ymm2  ; YMM for packed single
```

**Recovery:** Skip instruction.
**Related hints:** H3406

---

# E35xx — UPK Package Errors

---

## E3501 — Capability not declared but used

**Cause:** *(Reserved — not yet implemented)*

A `.upk` binary uses a system capability (e.g., network access, filesystem write) that was not declared in the package manifest.

**Output:**
```
error[E3501]: capability used but not declared in manifest
  --> (reserved — not yet implemented)
```

---

## E3502 — .cap directive invalid format

**Cause:** *(Reserved — not yet implemented)*

A `.cap` capability declaration directive has invalid syntax.

**Output:**
```
error[E3502]: invalid .cap directive format
  --> (reserved — not yet implemented)
```

---

## E3503 — UPK output section overlap

**Cause:** *(Reserved — not yet implemented)*

Two sections in a `.upk` output file are mapped to overlapping regions.

**Output:**
```
error[E3503]: UPK section overlap
  --> (reserved — not yet implemented)
```

---

## E3504 — UPK entry point not in .text

**Cause:** *(Reserved — not yet implemented)*

The entry point symbol in a `.upk` binary is not in an executable section.

**Output:**
```
error[E3504]: UPK entry point not in executable section
  --> (reserved — not yet implemented)
```

---

## E3505 — UPK manifest syntax error

**Cause:** The `.upk` package manifest contains malformed metadata.

**Triggers:**
```asm
; in a .upk manifest block:
[package]
name = my package   ; spaces in name without quotes
version = 1.x       ; 'x' is not a valid version component
```

**Output:**
```
error[E3505]: UPK manifest syntax error
  --> src/main.s:2:8
   |
 2 |     name = my package
   |            ~~~~~~~~~~
   |            package name must be a quoted string or single identifier
   |
   = hint[H3505]: name = "my_package"
```

**Recovery:** Skip manifest entry.
**Related hints:** H3505

---

## E3506 — UPK signature verification failed

**Cause:** *(Reserved — not yet implemented)*

A `.upk` package has a signature section but the signature does not verify against the content.

**Output:**
```
error[E3506]: UPK signature verification failed
  --> (reserved — not yet implemented)
```

---

## E3507 — UPK dependency unsatisfied

**Cause:** *(Reserved — not yet implemented)*

A `.upk` package declares a dependency that is not present in the build environment.

**Output:**
```
error[E3507]: UPK dependency unsatisfied
  --> (reserved — not yet implemented)
```

---

## E3508 — UPK architecture mismatch

**Cause:** A `.upk` package is assembled for one architecture but the target system is a different architecture.

**Output:**
```
error[E3508]: UPK architecture mismatch
  --> (linker)
   |
   package 'driver.upk' targets aarch64 but build target is amd64
   |
   = hint[H3508]: assemble for the correct target: utasm -arch amd64 ...
```

**Recovery:** Cannot produce valid package.
**Related hints:** H3508

---

# W8xx — Style Warnings

Configurable style-level warnings. Disabled by default. Enable with `-W8xx` or `-Wall`.

---

## W801 — Instruction could be shorter

**Cause:** An instruction was encoded in a longer form when a shorter encoding exists with identical semantics.

**Output:**
```
warning[W801]: instruction could use shorter encoding
  --> src/main.s:1:5
   |
 1 |     mov rax, 0
   |     ~~~~~~~~~~~
   |     'mov rax, 0' encodes as 10 bytes — 'xor rax, rax' is 3 bytes and equivalent
   |
   = hint[H801]: xor rax, rax
```

**Suppress:** `-Wno-801`

---

## W802 — Redundant REX prefix

**Cause:** A REX prefix is emitted that has no effect (all fields zero). This adds a byte without benefit.

**Output:**
```
warning[W802]: redundant REX prefix
  --> src/main.s:1:5
   |
 1 |     db 0x40, 0x90   ; REX (no fields set) + NOP
   |        ^^^^
   |        REX prefix 0x40 has no effect here
```

**Suppress:** `-Wno-802`

---

## W803 — Redundant operand size override

**Cause:** An explicit operand size override prefix (0x66) is emitted but the instruction already implies the correct size.

**Output:**
```
warning[W803]: redundant operand size override
  --> src/main.s:1:5
   |
 1 |     db 0x66
           nop
   |        ~~~~
   |        operand size override 0x66 has no effect on NOP
```

**Suppress:** `-Wno-803`

---

## W804 — PUSH/POP instead of MOV to stack pointer

**Cause:** A sequence uses PUSH/POP to save and restore a register when direct MOV to a stack slot would be more efficient.

**Output:**
```
warning[W804]: PUSH/POP may be replaced with MOV for better performance
  --> src/main.s:1:5
   |
 1 |     push rbx
   |     ~~~~~~~~
   |     in tight loops, 'mov [rsp-8], rbx' may outperform 'push rbx'
   |
   = hint[H804]: profile-dependent — suppress with -Wno-804
```

**Suppress:** `-Wno-804`

---

## W805 — LEA used where MOV suffices

**Cause:** LEA is used to load an absolute constant into a register, where MOV immediate would be shorter and clearer.

**Triggers:**
```asm
lea rax, [0x1000]       ; loads 0x1000 — MOV rax, 0x1000 is cleaner
```

**Output:**
```
warning[W805]: LEA with constant — use MOV instead
  --> src/main.s:1:5
   |
 1 |     lea rax, [0x1000]
   |     ~~~~~~~~~~~~~~~~~~
   |     'lea rax, [0x1000]' is equivalent to 'mov rax, 0x1000' but potentially longer
   |
   = hint[H805]: mov rax, 0x1000
```

**Suppress:** `-Wno-805`

---

## W806 — Branch likely to be mispredicted

**Cause:** A branch structure has characteristics that commonly cause branch mispredictions (e.g., alternating taken/not-taken with no pattern).

**Output:**
```
warning[W806]: branch likely to be mispredicted
  --> src/main.s:5:5
   |
 5 |     jz rare_case
   |     ~~~~~~~~~~~~
   |     static analysis: this branch appears to be rarely taken
   |
   = hint[H806]: reorder code so the common case falls through without a branch
```

**Suppress:** `-Wno-806`

---

## W807 — Stack frame not aligned

**Cause:** The stack pointer may not be 16-byte aligned at a function call site, which violates the System V AMD64 ABI.

**Triggers:**
```asm
push rbx            ; RSP now odd multiple of 8
call my_function    ; W807 — RSP may not be 16-byte aligned
```

**Output:**
```
warning[W807]: stack may not be 16-byte aligned at call site
  --> src/main.s:2:5
   |
 2 |     call my_function
   |     ~~~~~~~~~~~~~~~~
   |     static analysis: RSP alignment unclear — ABI requires 16-byte alignment at CALL
   |
   = note: System V AMD64 ABI requires RSP % 16 == 0 before CALL (RSP is 8 mod 16 at CALL entry)
   = hint[H807]: sub rsp, 8    ; align before call
                 call my_function
                 add rsp, 8
```

**Suppress:** `-Wno-807`

---

## W808 — Shadow space not reserved (Windows ABI)

**Cause:** A function call is made without reserving the 32-byte shadow space required by the Windows x64 calling convention.

**Triggers:**
```asm
; when building with -abi windows
call ExternalFunction   ; W808 — 32 bytes shadow space not reserved
```

**Output:**
```
warning[W808]: shadow space not reserved for Windows x64 ABI
  --> src/main.s:1:5
   |
 1 |     call ExternalFunction
   |     ~~~~~~~~~~~~~~~~~~~~~
   |     Windows x64 ABI requires 32 bytes shadow space before CALL
   |
   = hint[H808]: sub rsp, 32 / call ExternalFunction / add rsp, 32
```

**Suppress:** `-Wno-808`

---

# W9xx — Portability Warnings

Warnings about code that will not work correctly on other architectures or configurations.

---

## W901 — Instruction not available on all target architectures

**Cause:** An instruction is used that is not available on all architectures in a multi-arch build.

**Output:**
```
warning[W901]: instruction not portable across all target architectures
  --> src/main.s:3:5
   |
 3 |     cpuid
   |     ~~~~~
   |     'cpuid' is x86-64 specific — not available on AArch64 or RISC-V
   |
   = hint[H901]: use conditional assembly: %ifdef ARCH_AMD64 / cpuid / %endif
```

**Suppress:** `-Wno-901`

---

## W902 — Calling convention mismatch

**Cause:** A function appears to violate the active calling convention (e.g., not preserving callee-saved registers).

**Output:**
```
warning[W902]: possible calling convention violation
  --> src/main.s:15:5
   |
15 |     mov rbx, rax        ; RBX is callee-saved in SysV AMD64 ABI
   |                         ; but is modified without being saved/restored
   |
   = note: callee-saved registers: RBX RBP R12 R13 R14 R15
   = hint[H902]: push rbx at function entry, pop rbx before ret
```

**Suppress:** `-Wno-902`

---

## W903 — Stack alignment not guaranteed

**Cause:** The stack alignment cannot be guaranteed at this point due to conditional code paths.

**Output:**
```
warning[W903]: stack alignment not guaranteed on all code paths
  --> src/main.s:8:5
   |
 8 |     call function
   |     ~~~~~~~~~~~~~
   |     some code paths reach this call with RSP not 16-byte aligned
```

**Suppress:** `-Wno-903`

---

## W904 — Position-dependent code in PIE

**Cause:** An absolute address reference is used in code being built as Position Independent Executable.

**Triggers:**
```sh
utasm --pie -f elf64 main.s -o main
```
```asm
mov rax, my_label       ; absolute address — not PIC
```

**Output:**
```
warning[W904]: position-dependent code in PIE binary
  --> src/main.s:1:5
   |
 1 |     mov rax, my_label
   |              ~~~~~~~~
   |              absolute address reference in PIE — use RIP-relative addressing
   |
   = hint[H904]: lea rax, [rel my_label]   ; RIP-relative — works in PIE
```

**Suppress:** `-Wno-904`

---

## W905 — Non-PIC reference in shared library

**Cause:** An absolute address reference appears in code being built as a shared library, where the load address is not fixed.

**Output:**
```
warning[W905]: non-PIC reference in shared library
  --> src/main.s:3:5
   |
 3 |     mov rax, global_var
   |              ~~~~~~~~~~
   |              absolute reference to 'global_var' in shared library — must be PIC
   |
   = hint[H905]: mov rax, [rel global_var]   ; or use GOT: mov rax, [global_var wrt ..got]
```

**Suppress:** `-Wno-905`

---

# Exit Codes

utasm exits with a specific code that tells the calling process exactly what happened.

```asm
; defined in include/constant.inc
EXIT_OK             equ 0   ; assembly successful, no errors
EXIT_USAGE          equ 1   ; invalid command-line arguments
EXIT_OOM            equ 2   ; out of memory — could not allocate required buffers
EXIT_IO_ERROR       equ 3   ; file read/write failure
EXIT_PARSER_ERROR   equ 4   ; one or more E1xx–E4xx errors
EXIT_ENCODER_ERROR  equ 5   ; one or more E5xx errors
EXIT_LINKER_ERROR   equ 6   ; one or more E6xx/E33xx errors
EXIT_INTERNAL       equ 7   ; E8xx internal error — utasm bug
EXIT_ASSERTION      equ 8   ; assertion failure in utasm source
EXIT_SIGNAL         equ 9   ; terminated by signal (SIGINT, SIGSEGV, etc.)
```

**Usage in scripts:**
```sh
utasm -f elf64 main.s -o main
case $? in
    0) echo "Success" ;;
    1) echo "Bad arguments" ;;
    2) echo "Out of memory" ;;
    3) echo "IO error" ;;
    4) echo "Parse/semantic errors" ;;
    5) echo "Encoder errors" ;;
    6) echo "Linker errors" ;;
    7) echo "Internal error — please report" ;;
    8) echo "Assertion failed — please report" ;;
    9) echo "Terminated by signal" ;;
esac
```

**Note:** Warnings alone do not change the exit code from EXIT_OK unless `-Werror` is active.

---

# Complete Error Code Index

## E — Fatal Errors

| Range | Category | Count |
|---|---|---|
| E101–E115 | Lexer | 15 |
| E201–E227 | Parser | 27 |
| E301–E320 | Macro | 20 |
| E401–E425 | Semantic | 25 |
| E501–E534 | Encoder | 34 |
| E601–E620 | Linker | 20 |
| E701–E730 | CPU validation | 30 |
| E801–E815 | Internal | 15 |
| E901–E903 | Expression | 3 |
| E1001–E1002 | Directive | 2 |
| E1101–E1103 | Include | 3 |
| E1201–E1220 | Section | 20 (stubs) |
| E1301–E1320 | Visibility | 20 (stubs) |
| E1401–E1420 | Relocation | 20 (stubs) |
| E1501–E1520 | ELF output | 20 (stubs) |
| E1601–E1620 | PE output | 20 (stubs) |
| E1701–E1720 | Flat binary | 20 (stubs) |
| E1801–E1820 | Package | 20 (stubs) |
| E1901–E1920 | Debug info | 20 (stubs) |
| E2001–E2020 | Data | 20 (stubs) |
| E2101–E2120 | Alignment | 20 (stubs) |
| E2201–E2220 | Scope | 20 (stubs) |
| E2301–E2320 | Type | 20 (stubs) |
| E2401–E2420 | Privilege | 20 (stubs) |
| E2501–E2520 | SIMD | 20 (stubs) |
| E2601–E2620 | Memory model | 20 (stubs) |
| E2701–E2720 | Self-patch | 20 (stubs) |
| E2801–E2820 | Package | 20 (stubs) |
| E2901–E2920 | Security | 20 (stubs) |
| E3001–E3020 | Compatibility | 20 (stubs) |
| E3101–E3112 | Assembler directives | 12 |
| E3201–E3210 | Preprocessor | 10 |
| E3301–E3310 | Multi-file/link | 10 |
| E3401–E3406 | Floating point | 6 |
| E3501–E3508 | UPK/package | 8 |

## W — Warnings

| Range | Category | Count |
|---|---|---|
| W101–W199 | Lexer | reserved |
| W201–W202 | Parser | 2 |
| W301–W302 | Semantic | 2 |
| W401–W403 | Symbol | 3 |
| W501–W507 | Encoder | 7 |
| W601–W602 | Linker | 2 |
| W701–W703 | CPU | 3 |
| W801–W808 | Style | 8 |
| W901–W905 | Portability | 5 |

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
