# utasm — Syntax Reference

> UtkarshaLab | Engineering the Foundation of Tomorrow
>
> This document covers the complete syntax for writing utasm source files.
>
> **GEN0/GEN1 NOTE:** This document uses NASM-compatible syntax.
> Every line marked `; [GEN2]` will be updated to UTASM native syntax
> after Gen1 == Gen2 parity check passes. Do NOT change these until then.
> When parity passes, do a single search-replace pass on all `[GEN2]` markers.

---

## Source File Basics

```
; file extension: .asm
; encoding:       UTF-8 only
; line ending:    LF or CRLF (both accepted)
; max file size:  2 GB
; max line length: unlimited (but keep reasonable)
; max identifier: 4096 characters
```

---

## Comments

```asm
; single line comment — everything after ; is ignored
mov rax, 1      ; inline comment — also valid

/* block comment
   spans multiple lines
   nests up to 32 levels deep
   /* nested block comment */
   still in outer comment
*/
```

---

## Labels

### Global Labels

```asm
my_label:           ; global label — visible to linker
_start:             ; entry point label (must be global)
my_function:        ; function label
```

### Local Labels

```asm
; local labels start with dot
; only visible within the current global label scope
; same name can be reused in different functions

my_function:
    .loop:          ; local to my_function
        nop
        jmp .loop   ; refers to my_function.loop

other_function:
    .loop:          ; different .loop — no clash
        nop
        jmp .loop   ; refers to other_function.loop
```

### Label Rules

```
- Must start with [a-zA-Z_] or dot (for local)
- Can contain [a-zA-Z0-9_]
- Case sensitive: myLabel ≠ mylabel ≠ MYLABEL
- Cannot be a mnemonic or directive name
- Followed by colon (:) at definition
- Used without colon when referenced
```

---

## Numeric Literals

```asm
; decimal (default)
mov rax, 255
mov rax, 1024

; hexadecimal
mov rax, 0xFF
mov rax, 0hFF           ; alternate hex prefix
mov rax, 0xFF00CAFE

; binary
mov rax, 0b10110011
mov rax, 0y10110011     ; alternate binary prefix

; octal
mov rax, 0o755
mov rax, 0q755          ; alternate octal prefix

; character literal (ASCII value)
mov al, 'A'             ; = 65
mov al, '\n'            ; = 10 (newline)
mov al, '\t'            ; = 9  (tab)
mov al, '\\'            ; = 92 (backslash)
mov al, '\''            ; = 39 (single quote)
mov al, '\"'            ; = 34 (double quote)
mov al, '\0'            ; = 0  (null)
mov al, '\xHH'          ; hex escape
```

---

## String Literals

```asm
; double-quoted strings
db "hello world"
db "line one\nline two"
db "tab\there"
db "null terminated", 0

; single-quoted strings (no escape processing)
db 'hello world'        ; literal backslash, no escapes
db 'it''s fine'         ; double single-quote = one single-quote

; multiple values on one line
db "hello", 0x0A, 0     ; string + newline + null
```

---

## Size Specifiers

```asm
; explicit size in memory operands
mov byte  [rax], 1      ; 8-bit write
mov word  [rax], 1      ; 16-bit write
mov dword [rax], 1      ; 32-bit write
mov qword [rax], 1      ; 64-bit write

; without specifier — inferred from register size
mov [rax], bl           ; 8-bit  (bl is 8-bit)
mov [rax], bx           ; 16-bit (bx is 16-bit)
mov [rax], ebx          ; 32-bit (ebx is 32-bit)
mov [rax], rbx          ; 64-bit (rbx is 64-bit)
```

---

## Registers

### AMD64 (x86-64) General Purpose

```asm
; 64-bit
rax rbx rcx rdx rsi rdi rsp rbp
r8  r9  r10 r11 r12 r13 r14 r15

; 32-bit (low 32 bits of 64-bit)
eax ebx ecx edx esi edi esp ebp
r8d r9d r10d r11d r12d r13d r14d r15d

; 16-bit
ax  bx  cx  dx  si  di  sp  bp
r8w r9w r10w r11w r12w r13w r14w r15w

; 8-bit (low byte)
al  bl  cl  dl  sil dil spl bpl
r8b r9b r10b r11b r12b r13b r14b r15b

; 8-bit (high byte — only legacy regs)
ah  bh  ch  dh

; segment registers
cs  ds  es  fs  gs  ss

; control registers
cr0 cr2 cr3 cr4 cr8

; debug registers
dr0 dr1 dr2 dr3 dr6 dr7

; x87 FPU
st0 st1 st2 st3 st4 st5 st6 st7

; MMX
mm0 mm1 mm2 mm3 mm4 mm5 mm6 mm7

; SSE / AVX (128-bit XMM)
xmm0  xmm1  xmm2  xmm3  xmm4  xmm5  xmm6  xmm7
xmm8  xmm9  xmm10 xmm11 xmm12 xmm13 xmm14 xmm15
xmm16 xmm17 xmm18 xmm19 xmm20 xmm21 xmm22 xmm23   ; AVX-512 only
xmm24 xmm25 xmm26 xmm27 xmm28 xmm29 xmm30 xmm31   ; AVX-512 only

; AVX (256-bit YMM)
ymm0  ymm1  ymm2  ymm3  ymm4  ymm5  ymm6  ymm7
ymm8  ymm9  ymm10 ymm11 ymm12 ymm13 ymm14 ymm15
ymm16 ymm17 ymm18 ymm19 ymm20 ymm21 ymm22 ymm23   ; AVX-512 only
ymm24 ymm25 ymm26 ymm27 ymm28 ymm29 ymm30 ymm31   ; AVX-512 only

; AVX-512 (512-bit ZMM)
zmm0  zmm1  zmm2  zmm3  zmm4  zmm5  zmm6  zmm7
zmm8  zmm9  zmm10 zmm11 zmm12 zmm13 zmm14 zmm15
zmm16 zmm17 zmm18 zmm19 zmm20 zmm21 zmm22 zmm23
zmm24 zmm25 zmm26 zmm27 zmm28 zmm29 zmm30 zmm31

; AVX-512 mask registers
k0 k1 k2 k3 k4 k5 k6 k7

; RIP (instruction pointer — read only, used in addressing)
rip

; RFLAGS (flags register — not directly addressable)
; flags: CF PF AF ZF SF TF IF DF OF
```

### AArch64 (ARMv8-A) Registers

```asm
; 64-bit general purpose
x0  x1  x2  x3  x4  x5  x6  x7
x8  x9  x10 x11 x12 x13 x14 x15
x16 x17 x18 x19 x20 x21 x22 x23
x24 x25 x26 x27 x28 x29 x30

; 32-bit views (low 32 bits)
w0  w1  w2  w3  w4  w5  w6  w7
w8  w9  w10 w11 w12 w13 w14 w15
w16 w17 w18 w19 w20 w21 w22 w23
w24 w25 w26 w27 w28 w29 w30

; special purpose
sp          ; stack pointer (x31 in SP context)
xzr         ; 64-bit zero register
wzr         ; 32-bit zero register
lr          ; link register (x30)
fp          ; frame pointer (x29)
pc          ; program counter (read only)

; SIMD/FP scalar
b0..b31     ; 8-bit
h0..h31     ; 16-bit
s0..s31     ; 32-bit
d0..d31     ; 64-bit
q0..q31     ; 128-bit

; SIMD vector
v0..v31     ; 8..128-bit vector register

; SVE
z0..z31     ; scalable vector (VL-bit wide)
p0..p15     ; predicate registers
ffr         ; first fault register

; System registers accessed via MRS/MSR
; examples:
; nzcv      — condition flags
; fpcr      — FP control
; fpsr      — FP status
; tpidr_el0 — thread pointer
```

### RISC-V 64 Registers

```asm
; ABI names (preferred)
zero        ; x0  — hardwired zero
ra          ; x1  — return address
sp          ; x2  — stack pointer
gp          ; x3  — global pointer
tp          ; x4  — thread pointer
t0 t1 t2    ; x5-x7  — temporaries
s0 fp       ; x8  — saved / frame pointer
s1          ; x9  — saved register
a0 a1       ; x10-x11 — args / return values
a2 a3 a4 a5 a6 a7   ; x12-x17 — args
s2 s3 s4 s5 s6 s7 s8 s9 s10 s11  ; x18-x27 — saved
t3 t4 t5 t6 ; x28-x31 — temporaries

; numeric names (also valid)
x0..x31

; float registers (ABI names)
ft0..ft7    ; f0-f7   — FP temporaries
fs0 fs1     ; f8-f9   — FP saved
fa0 fa1     ; f10-f11 — FP args / return
fa2..fa7    ; f12-f17 — FP args
fs2..fs11   ; f18-f27 — FP saved
ft8..ft11   ; f28-f31 — FP temporaries

; float numeric names
f0..f31

; vector registers
v0..v31
```

---

## Memory Addressing

### AMD64 Addressing Modes

```asm
; direct memory
mov rax, [0x400000]         ; absolute address

; register indirect
mov rax, [rbx]              ; value at address in rbx

; register + displacement
mov rax, [rbx + 8]          ; rbx + 8
mov rax, [rbx - 8]          ; rbx - 8
mov rax, [rbx + 0x10]       ; hex displacement

; base + index
mov rax, [rbx + rcx]        ; rbx + rcx

; base + scaled index
mov rax, [rbx + rcx*2]      ; rbx + rcx*2
mov rax, [rbx + rcx*4]      ; rbx + rcx*4
mov rax, [rbx + rcx*8]      ; rbx + rcx*8
; valid scales: 1, 2, 4, 8 only

; base + scaled index + displacement
mov rax, [rbx + rcx*4 + 16] ; full SIB + displacement

; the scale may come first, and the terms in any order
mov rax, [4*rcx + rbx + 16] ; the same address
mov rax, [rbx*3]            ; rbx + rbx*2 (also *5, *9)
mov rax, [rax + rax*3]      ; rax*4: a register written twice adds up

; RIP-relative (position independent)
mov rax, [rel my_label]     ; relative to instruction pointer

; segment override
mov rax, [fs:0]             ; TLS access via FS segment
mov rax, [gs:0x28]          ; canary via GS segment
```

Base and index are chosen as NASM chooses them: a register with a scale
other than 1 is the index; of two registers times 1, the first written is
the base unless it was written with a scale (`[rbx*1 + rax]` is
`[rax + rbx]`); `nosplit` keeps `[rbx*1]` and `[rbx*2]` as an index with a
32-bit displacement. Two scaled registers, three registers, or a scale
other than 1, 2, 3, 4, 5, 8 or 9 is an error.

### AArch64 Addressing Modes

```asm
; base register only
ldr x0, [x1]               ; value at address in x1

; base + immediate offset
ldr x0, [x1, #8]           ; x1 + 8
ldr x0, [x1, #-8]          ; x1 - 8

; pre-indexed (update base before access)
ldr x0, [x1, #8]!          ; x1 = x1 + 8, then load from x1

; post-indexed (update base after access)
ldr x0, [x1], #8           ; load from x1, then x1 = x1 + 8

; base + register offset
ldr x0, [x1, x2]           ; x1 + x2

; base + scaled register offset
ldr x0, [x1, x2, lsl #3]   ; x1 + (x2 << 3)

; PC-relative (literal pool)
ldr x0, =my_label           ; load address of label
ldr x0, my_label            ; PC-relative load
```

### RISC-V Addressing Modes

```asm
; register + immediate offset (only mode for loads/stores)
lw  a0, 0(sp)               ; load word from sp + 0
ld  a0, 8(sp)               ; load doubleword from sp + 8
sw  a0, 0(sp)               ; store word to sp + 0

; PC-relative (for jumps and AUIPC)
auipc a0, %hi(my_label)     ; load upper 20 bits PC-relative
addi  a0, a0, %lo(my_label) ; add lower 12 bits

; absolute via lui
lui   a0, %hi(0x80000000)
addi  a0, a0, %lo(0x80000000)
```

---

## Expressions and Operators

```asm
; arithmetic
mov rax, 1 + 2              ; = 3
mov rax, 10 - 3             ; = 7
mov rax, 4 * 8              ; = 32
mov rax, 16 / 4             ; = 4
mov rax, 17 % 5             ; = 2 (modulo)

; bitwise
mov rax, 0xFF & 0x0F        ; AND  = 0x0F
mov rax, 0xF0 | 0x0F        ; OR   = 0xFF
mov rax, 0xFF ^ 0x0F        ; XOR  = 0xF0
mov rax, ~0x00              ; NOT  = 0xFFFFFFFFFFFFFFFF
mov rax, 1 << 4             ; SHL  = 16
mov rax, 256 >> 4           ; SHR  = 16

; comparison (returns 0 or 1)
mov rax, 5 == 5             ; = 1
mov rax, 5 != 4             ; = 1
mov rax, 5 >  4             ; = 1
mov rax, 5 <  6             ; = 1
mov rax, 5 >= 5             ; = 1
mov rax, 5 <= 5             ; = 1

; special
mov rax, $ - my_label       ; $ = current address
mov rax, $$ - $$            ; $$ = section start
```

### Labels in expressions

A label is an address, not a number. As in NASM, the difference of two
labels of one section (`end - start`, `$ - $$`) is a number and can go
into any operator, while a label on its own may only be added to or
subtracted from. These are errors, with NASM's messages:

```asm
dd label * 2                ; expression is not simple or relocatable
dd label / 2                ; division operator may only be applied to scalar values
dd label >> 4               ; shift operator may only be applied to scalar values
dd label & 0xFF             ; `&' operator may only be applied to scalar values
dd label < 2                ; `<': operands differ by a non-scalar
dd (end - start) / 4        ; fine: a distance is a number
```

A label may be used before the line that defines it, in arithmetic too:

```asm
count:  dd (table_end - table) / 4      ; 2
table:  dd 1, 2
table_end:
```

utasm reads the source once, so such a value is worked out at the end, once
every label is placed, and written in place. When an instruction uses one,
utasm reads the source a second time knowing it, so the instruction gets
the form NASM gives it: `push dword (table_end - table) / 4` is `6A ib`,
`add rsp, frame_end - frame` takes an imm8. The second pass checks each
value once the code is laid out; one that measures its own instruction
(`s: push dword (e - s)`) keeps the long form, where NASM converges on the
short one. Where the value is needed when the line is read - the count of
`times` or `resb` - the first reading goes on without it and the second
one knows it; a name that is never defined is an error there.

---

## Directives

> **[GEN2] NOTE:** All directives below marked [GEN2] will be replaced
> with UTASM native syntax after Gen1 == Gen2 parity check passes.
> Do NOT change anything marked [GEN2] until then.

---

### Constants and Definitions

```asm
; [GEN2] → def MAX_SIZE 256
%define MAX_SIZE    256             ; constant definition
%define STDOUT      1
%define NULL        0

; expression constant
%define BUFFER_SIZE (MAX_SIZE * 4)

; [GEN2] → will stay as equ (no change)
my_const    equ 100                 ; alternative constant — same as %define

; [GEN2] → undef removed in UTASM (just use if/end instead)
%undef MAX_SIZE                     ; remove definition

; [GEN2] → def with expression
%assign counter 0                   ; mutable constant (can be reassigned)
%assign counter counter + 1
```

`equ` gives its label the value of the expression, as in NASM:

```asm
msg:     db "hello", 10
msg_len  equ $ - msg                ; a constant: 6
mid      equ msg + 3                ; a label in msg's section, msg + 3
```

A difference of two labels of one section (`$ - msg`, `end - start`) or
any other number is a constant; a label plus or minus a number is that
label's section again (it is relocated like a label, and moves with it
when jumps are shortened). A constant may be used before its `equ` line
(`mov ecx, msg_len` above `msg_len equ ...`): its value is written in place
when the object is finished. The `equ` expression may itself use what is
defined after it, as in NASM:

```asm
len      equ end - start            ; labels further on
size     equ len * 2                ; an equ further on
start:   db "hello"
end:
```

Such an `equ` is worked out once every label is placed, and an
instruction that uses it gets the form NASM gives it (`add ecx, len` takes
an imm8): utasm reads the source again knowing the value, and checks it
once the code is laid out. A name that is never defined is an error at the
`equ` line, and so are `equ`s that name each other (`a equ b`, `b equ a`),
which NASM takes as 0.

The same goes for an `equ` that measures code jumps may shorten
(`len equ $ - start` after a function): it is worked out after the
jumps are shortened, so they are as short as NASM makes them and `len`
is the same number. An `equ` of a label written later (`p equ y + 1`)
is that label before the jumps are shortened, so `jmp p` is short too.

---

### Macros

```asm
; [GEN2] → mac my_macro 0 ... end
%macro my_macro 0               ; 0 parameters
    nop
    nop
%endmacro

; [GEN2] → mac my_func 1 ... end
%macro my_func 1                ; 1 parameter
    mov rax, %1                 ; %1 = first parameter
    add rax, 1
%endmacro

; [GEN2] → mac my_func 2 ... end
%macro my_func 2                ; 2 parameters
    mov rax, %1
    mov rbx, %2
    add rax, rbx
%endmacro

; calling a macro:
my_macro                        ; no args
my_func 5                       ; one arg
my_func rax, rbx                ; two args

; local labels inside macros
%macro safe_call 1
    %%check:                    ; %% = macro-local label
        test rdi, rdi
        jz %%skip
        call %1
    %%skip:
%endmacro

; [GEN2] → rotate keyword removed — use mac with index param
%rotate 1                       ; rotate macro parameters

; parameter counts and defaults
%macro args 1-3 5               ; 1 to 3 parameters; %2 is 5 when left out,
    db %1, %2, %3               ; %3 empty ("db 1, 5," ends at the comma)
%endm                           ; %endm is %endmacro
%macro tail 1+                  ; the last parameter takes the rest of the line
%endmacro
%unmacro args 1-3               ; removes the overload with exactly this count
```

The parameter count is required, as in NASM: `%macro name` alone is an
error ("`%macro' expects a parameter count"), as is a minimum above the
maximum. A macro may be defined again with another count; each definition
is an overload, chosen by the number of arguments of a call.

A multi-line macro is called as the first word of a line, or after a
label (`lab: m` - the listing shows `lab:` as the first line of the
expansion unless the macro takes the label with `%00`). Elsewhere its name
is an ordinary word: `db 1, m` is the symbol `m`.

### Preprocessor functions

NASM 2.16's functions work anywhere on a line, their arguments expanded
first; the call is replaced by its result:

```asm
db %eval(2 + 3), %abs(-7)          ; 5, 7     (%hex: 0x...)
db %num(255, 4, 16)                ; '00ff'   (a string: digits, base)
db %strlen('abc'), %count(a, b)    ; 3, 2
db %sel(2, 10, 20, 30)             ; 20
db %cond(DEBUG, 1, 0)              ; the second or the third
db %str(a + b), %strcat('a', "b")  ; 'a + b', 'ab'
db %substr('abcd', 2, 2)           ; 'bc'     (no length: to the end)
%tok('nop')                        ; the tokens a string spells
db %map(F, 1, 2)                   ; F(1), F(2)  (%map(F:(x), a): F(x, a))
db %isdef(DEBUG), %isnum(5)        ; 1 or 0: every %if test as a function
```

`%is(expr)`, `%isdef`, `%isnum`, `%isstr`, `%isid`, `%isempty`, `%istoken`,
`%ismacro`, `%isidn`, `%isidni`, `%isenv`, `%isctx` and their `%isn...`
forms give 1 or 0. A `%[...]` standing alone gives the tokens inside it,
expanded there and then: in a `%define`'s body, the value of the moment.

---

### Conditionals

```asm
; [GEN2] → if DEBUG ... end
%ifdef DEBUG
    mov rax, 1
%endif

; [GEN2] → if !DEBUG ... end
%ifndef DEBUG
    mov rax, 0
%endif

; [GEN2] → if DEBUG == 1 ... end
%if DEBUG == 1
    mov rax, 1
%endif

; [GEN2] → if ... els ... end
%if ARCH == 64
    mov rax, 1
%else
    mov eax, 1
%endif

; [GEN2] → if ... if ... end end (nested)
%ifdef DEBUG
    %if DEBUG_LEVEL > 1
        mov rax, 1
    %endif
%endif

; chained
%if VALUE == 1
    mov rax, 1
%elif VALUE == 2
    mov rax, 2
%elif VALUE == 3
    mov rax, 3
%else
    mov rax, 0
%endif
```

---

### Repetition

```asm
; [GEN2] → times 4 nop
times 4 nop                     ; single instruction, 4 times

; [GEN2] → times 4 ... end (block mode)
%rep 4
    nop
    add rax, 1
%endrep

; times with data
times 64 db 0x00                ; 64 zero bytes
times 16 db 0xFF                ; 16 bytes of 0xFF
```

---

### File Inclusion

```asm
; [GEN2] → inc "utils.asm"
%include "utils.asm"            ; include file (searched in include path)
%include "../lib/common.asm"    ; relative path

; include search path set via CLI:
; utasm -i /usr/local/lib/utasm/ main.asm
```

---

### Data Definition

```asm
; [GEN2] → d8 / d16 / d32 / d64

; emit bytes (initialized data)
db 0x41                         ; [GEN2] d8  0x41
dw 0x1234                       ; [GEN2] d16 0x1234
dd 0xDEADBEEF                   ; [GEN2] d32 0xDEADBEEF
dq 0xDEADBEEFCAFEBABE           ; [GEN2] d64 0xDEADBEEFCAFEBABE

; multiple values
db 0x41, 0x42, 0x43             ; [GEN2] d8 0x41 / d8 0x42 / d8 0x43
db "hello", 0                   ; string + null terminator

; repeated values
times 64 db 0x00                ; [GEN2] d8 64 0x00
times 10 dd 0                   ; [GEN2] d32 10 0

; reserve (uninitialized)
resb 64                         ; [GEN2] d8  64 ?
resw 32                         ; [GEN2] d16 32 ?
resd 16                         ; [GEN2] d32 16 ?
resq 8                          ; [GEN2] d64 8  ?

; single reserve
resb 1                          ; [GEN2] d8  ?
resw 1                          ; [GEN2] d16 ?
resd 1                          ; [GEN2] d32 ?
resq 1                          ; [GEN2] d64 ?
```

---

### Sections

```asm
; [GEN2] → sec .text
section .text                   ; code section (executable)
section .data                   ; initialized data (read/write)
section .bss                    ; uninitialized data (read/write)
section .rodata                 ; read-only data

; with flags
section .mycode exec            ; executable
section .mydata write           ; writable
section .myrodata               ; default: read only

; W+X forbidden — SXE0001 fatal:
; section .bad write exec       ; NEVER — security violation
```

---

### Symbol Visibility

```asm
; [GEN2] → global _start
global _start                   ; export — visible to linker
global my_function
global my_var

; [GEN2] → extern printf
extern printf                   ; import — defined elsewhere
extern malloc
extern free

; common (shared across object files)
common shared_buffer 1024       ; 1024 byte common block
```

---

### Structures

```asm
; [GEN2] → struc my_point ... end
struc my_point
    .x  resq 1                  ; [GEN2] d64 ?
    .y  resq 1                  ; [GEN2] d64 ?
    .z  resq 1                  ; [GEN2] d64 ?
endstruc

; size of structure
; my_point_size = my_point_size (NASM calculates automatically)

; instantiate structure
istruc my_point
    at my_point.x, dq 10        ; [GEN2] d64 10
    at my_point.y, dq 20        ; [GEN2] d64 20
    at my_point.z, dq 30        ; [GEN2] d64 30
iend

; accessing structure fields in code
mov rax, [rbx + my_point.x]    ; field offset used directly
mov rcx, [rbx + my_point.y]
```

---

### Assembler Control

```asm
; [GEN2] → bits 64
bits 64                         ; 64-bit mode (default for AMD64)
bits 32                         ; 32-bit mode
bits 16                         ; 16-bit mode (bootloader/real mode)
use16 / use32 / use64           ; the same

; [GEN2] → cpu generic / cpu x86_64_v3 etc
cpu generic                     ; x86-64 baseline (SSE2 only)
cpu x86_64_v3                   ; AVX2 + FMA + POPCNT + BMI2
cpu skylake                     ; Intel Skylake
cpu znver3                      ; AMD Zen 3

; [GEN2] → fmt elf64 / fmt pe / fmt flat / fmt upk
; output format set via CLI (-f flag):
; utasm -f elf64  main.asm -o main
; utasm -f pe     main.asm -o main.exe
; utasm -f bin    main.asm -o main.bin
; utasm -f upk    main.asm -o main.upk

; [GEN2] → org 0x7C00
org 0x7C00                      ; set origin address (flat binary)
org 0x400000                    ; typical ELF load address

; [GEN2] → align 16
align 16                        ; align to 16-byte boundary (NOP fill)
align 4                         ; align to 4-byte boundary
align 64                        ; align to cache line
```

`bits 16` and `bits 32` encode for those modes, as NASM does: the operand-
size prefix `66` marks the size that is not the mode's (16-bit operands in
32-bit mode, 32-bit ones in 16-bit mode), `67` the address size likewise;
16-bit code has 16-bit addressing (`[bx+si]`, `[bp+di+4]`, `[si]`) and
rel16 near branches (shortened to rel8 like any other); `inc`/`dec` of a
register take their one-byte forms, `push`/`pop` the mode's width, and
`pusha`, `daa`, `aam`, `bound`, `les`, `push es` and the other instructions
that exist only there are available. What a mode does not have - 64-bit
registers, r8-r15, `sil`/`dil`, `[rax]`, RIP-relative addressing outside
64-bit mode; 16-bit addressing in it - is an error. `-f bin` starts in
`bits 64` (NASM's starts in `bits 16`), `-f elf32` in `bits 32`.

---

## Complete Source File Example

```asm
; example.asm — minimal ELF64 Linux executable
; assembled with: utasm -f elf64 example.asm -o example

bits 64                         ; [GEN2] → bits 64 (no change)

; [GEN2] → def STDOUT 1
%define STDOUT      1
%define SYS_WRITE   1
%define SYS_EXIT    60

section .data                   ; [GEN2] → sec .data
    msg db "Hello, Utkarsha!", 0x0A
    msg_len equ $ - msg

section .bss                    ; [GEN2] → sec .bss
    buffer resb 256             ; [GEN2] → d8 256 ?

section .text                   ; [GEN2] → sec .text
global _start                   ; [GEN2] → global _start

_start:
    ; write syscall
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg
    mov rdx, msg_len
    syscall

    ; exit syscall
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
```

---

## AArch64 Complete Example

```asm
; aarch64_example.asm
; assembled with: utasm -arch aarch64 -f elf64 aarch64_example.asm -o example

%define SYS_WRITE   64          ; [GEN2] → def SYS_WRITE 64
%define SYS_EXIT    93          ; [GEN2] → def SYS_EXIT 93
%define STDOUT      1

section .data                   ; [GEN2] → sec .data
    msg db "Hello AArch64!", 0x0A
    msg_len equ $ - msg

section .text                   ; [GEN2] → sec .text
global _start                   ; [GEN2] → global _start

_start:
    mov x8, SYS_WRITE
    mov x0, STDOUT
    adr x1, msg
    mov x2, msg_len
    svc #0

    mov x8, SYS_EXIT
    mov x0, #0
    svc #0
```

---

## RISC-V 64 Complete Example

```asm
; riscv64_example.asm
; assembled with: utasm -arch riscv64 -f elf64 riscv64_example.asm -o example

%define SYS_WRITE   64          ; [GEN2] → def SYS_WRITE 64
%define SYS_EXIT    93          ; [GEN2] → def SYS_EXIT 93
%define STDOUT      1

section .data                   ; [GEN2] → sec .data
    msg db "Hello RISC-V!", 0x0A
    msg_len equ $ - msg

section .text                   ; [GEN2] → sec .text
global _start                   ; [GEN2] → global _start

_start:
    li a7, SYS_WRITE
    li a0, STDOUT
    la a1, msg
    li a2, msg_len
    ecall

    li a7, SYS_EXIT
    li a0, 0
    ecall
```

---

## GEN2 Migration Reference

When Gen1 == Gen2 parity passes — replace ALL `[GEN2]` items:

```
NASM syntax         →   UTASM syntax
─────────────────────────────────────────────────
%define X Y         →   def X Y
%undef X            →   (remove entirely)
%assign X Y         →   def X Y
%macro name N       →   mac name N
%endmacro           →   end
%include "file"     →   inc "file"
%ifdef X            →   if X
%ifndef X           →   if !X
%if EXPR            →   if EXPR
%elif EXPR          →   (if ... els if ... end)
%else               →   els
%endif              →   end
%rep N              →   times N (block mode)
%endrep             →   end
times N INST        →   times N INST (no change)
section .name       →   sec .name
global sym          →   global sym (no change)
extern sym          →   extern sym (no change)
struc name          →   struc name (no change)
endstruc            →   end
istruc / iend       →   (direct d64/d32 etc)
db VALUE            →   d8 VALUE
dw VALUE            →   d16 VALUE
dd VALUE            →   d32 VALUE
dq VALUE            →   d64 VALUE
times N db VALUE    →   d8 N VALUE
resb N              →   d8 N ?
resw N              →   d16 N ?
resd N              →   d32 N ?
resq N              →   d64 N ?
bits N              →   bits N (no change)
org ADDR            →   org ADDR (no change)
align N             →   align N (no change)
cpu PROFILE         →   cpu PROFILE (no change)
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
