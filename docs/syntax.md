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
mov rax, 2      // to the end of the line, as in C

/* block comment
   spans multiple lines */

# a line whose first character (after blanks) is "#": GNU's comment line
# 1 "file.c"    (GCC's line markers are taken as comments too)
```

A block comment ends at its first `*/`, as in C and GNU `as` (they do not
nest). The `#` comment line is x86's: elsewhere on a line `#` is a token
(stringizing in a macro body), and the AArch64 and RISC-V syntaxes write
immediates with it. `;` stays NASM's comment, where GNU `as` on x86 takes
it between two statements.

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

As in NASM 3, some operand sizes are taken as the form that does the
same thing:

```asm
movzx rbx, r9d          ; mov ebx, r9d (8B: a 32-bit write clears the rest)
movzx bx, r9d           ; mov bx, r9w (66 8B)
movzx ax, dx            ; 66 0F B7 - and movsx ax, dx: 66 0F BF
movsx ebx, r9d          ; movsxd ebx, r9d (63, no REX.W)
movsx eax, ax           ; cwde (98) under -Ox; cbw, cdqe likewise
crc32 ebx, r9           ; the source's size is the operation's: REX.W F1
lar rbx, r9             ; lar ebx, r9d (no REX.W; also lsl, str, sldt, smsw)
andn ebx, r9d           ; andn ebx, ebx, r9d (bextr, bzhi, mulx, pdep,
                        ; pext, sarx, shlx, shrx likewise)
kmov k1, eax            ; kmovd (by the register's size; "kmov byte k1,
                        ; eax" is kmovb)
movzx bx, [rax]         ; an error: a byte or a word?
```

`xchg` of two registers puts the first in ModRM's reg field (`xchg al,
cl` is `86 C1`), and prefixes come in NASM 3's order: segment, `67`,
`lock`, `66`, `rep` (`lock add [eax], bx` is `67 F0 66 01 18`, `rep
movsw` is `66 F3 A5`). An address size that contradicts a count register
(`a16 jecxz`, `a32 loop l, rcx`) is an error.

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

; APX (64-bit code): r16-r31, as 64 / 32 / 16 / 8 bits
r16  ... r31          r16d ... r31d
r16w ... r31w         r16b ... r31b

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

APX's r16-r31 work anywhere a general register does in the ordinary
(legacy and 0F-map) instructions, as a register or as a memory base or
index: utasm writes the REX2 prefix they need (`D5`, then the bits of the
registers above 15 and the 0F map), as NASM 3 and GNU `as` do:

```asm
mov  r16, rax                 ; D5 18 89 C0
add  eax, [r20 + r21*4]       ; D5 30 03 04 AC
push r31                      ; D5 11 57
movdqa xmm0, [r16]            ; 66 D5 90 6F 00 (the 0F folded into REX2)
```

Vector instructions with r16-r31 in their operands are EVEX (a VEX one is
promoted to its EVEX form: `vpaddd xmm0, xmm1, [r16]` is `62 F9 75 08 FE
00`); kmov, the AMX tile loads and stores and the BMI instructions keep
their VEX fields in an EVEX prefix. A VEX-only vector instruction
(`vmovdqu xmm0, [r16]`) has no form with them, as in NASM.

APX's EVEX forms of the integer instructions (map 4), in NASM's syntax
and GNU's:

```asm
add  rax, rbx, rcx            ; a new destination: rax = rbx + rcx
sub  r16, [rbx], 5            ; (add or adc sbb and sub xor, inc dec neg
shl  rax, rbx, cl             ;  not, the shifts, shld shrd, imul, cmovcc,
imul rax, rbx, rcx            ;  adcx adox)
{nf} add rax, rbx             ; the flags kept (add, or, and, sub, xor,
{nf} popcnt rax, rbx          ;  inc dec neg, shifts, imul mul div idiv,
{nf} andn rax, rbx, rcx       ;  popcnt lzcnt tzcnt, andn bextr bls* bzhi)
{zu} imul ax, bx, 5           ; the destination's upper bits zeroed (also
{zu} setz al                  ;  setcc)
{evex} add rax, rbx           ; the EVEX form of the legacy one
ccmpz {dfv=of,zf} rax, rbx    ; compare if ZF, else set OF ZF (ccmp / ctest
ctestnz {dfv=cf} ebx, 7       ;  by any condition, t and f too)
cfcmovz rax, [rbx]            ; cmov that does not fault on a false load
push2 rax, rbx                ; two pushes / pops (push2p / pop2p: the hint)
pushp rax                     ; push / pop with the balanced hint (REX2.W)
jmpabs 0x123456789            ; a jump to a 64-bit address
movbe rax, [r16]              ; (movbe crc32 invept invvpid invpcid enqcmd
crc32 rbx, r16                ;  enqcmds movdir64b movdiri wrss wruss: EVEX
                              ;  with r16-r31)
```

The bytes are NASM 3's in its syntax and GNU `as`'s in GNU's (they part
over register-to-register direction and a few W bits). ccmp and ctest
take no `{dfv=}` too (no flags), as GNU `as` does. r16-r31 outside 64-bit
code, or beside `ah`-`dh`, and `{nf}` / `{zu}` where no form takes them,
are errors.

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

In an object file, the difference of a label of another section (or an
extern) and one of the section being written is a PC-relative reference,
as in NASM: `dd func - $` and `mov eax, table - $` get an
`R_X86_64_PC32` relocation against `func` / `table` (`PC16` for `dw`,
`PC64` for `dq`), the distance from the right-hand label to the field in
its addend. Labels of two other sections (`dd b - a` with neither here)
have no relocation for them: ``expression is not simple or relocatable``.
With `-f bin` the sections are placed, so any difference is a number.

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
value once the code is laid out. A value that measures its own instruction
starts short, as in NASM's first pass: in an instruction with a
sign-extended imm8 form (the ALU group, `imul`, `push`) the first reading
lays it out with that form, so

```asm
s:  add eax, e - s          ; 83 C0 7F: 3 + 124 = 127 fits a signed byte
    times 124 nop
e:
```

gets the short form NASM gives it. A value that turns out not to fit
(`times 200 nop` there) is given the long form and the layout is worked out
again. `strict` and `-O0` keep the long form from the start. A displacement
(`lea eax, [eax + e - s]`) is not guessed: it starts as a disp32, as NASM's
first pass takes it. Where the value is needed when the line is read - the count of
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
label, with its colon or without (`lab: m`, `lab m` - even `push m`, as in
NASM, where `push` is then the label). The label is defined where it
stands, unless the macro's body names `%00`, which is the label (nothing
when there is none): the macro defines it itself.

```asm
%macro proc_entry 0
%00:    push rbp                ; f proc_entry: f is defined here
        mov rbp, rsp
%endmacro
f proc_entry
```

Elsewhere its name is an ordinary word: `db 1, m` is the symbol `m`.

`.nolist` after the count (`%macro m 0.nolist`, `%macro m 1+.nolist`)
leaves the expansion out of the listing: its bytes are listed on the
calling line, as NASM lists them. `%macro m 0+` takes no parameter and
drops what follows the call (`%0` is 0).

### Packages (`%use`)

`%use` loads one of NASM's standard packages, as NASM does:

| Package | What it adds |
| --- | --- |
| `altreg` | `r0`-`r15` (and `r0d`, `r0w`, `r0b`/`r0l`, `r0h`-`r3h`) for the registers |
| `smartalign` | `align` pads code with long NOPs; `alignmode` |
| `fp` | `float32(x)` & co, `Inf`, `NaN`, `QNaN`, `SNaN` |
| `ifunc` | `ilog2(x)` / `ilog2e(x)` (x a power of two, else an error), `ilog2w(x)` / `ilog2fw(x)` (a warning, then the floor), `ilog2f(x)` (floor), `ilog2c(x)` (ceiling), `ilog2cw(x)` |
| `masm` | MASM's forms: `name segment` / `ends`, `end`, `dword ptr [x]` and `qword ptr x` (a memory operand, brackets or not), `[flat:rbx]`, `offset x`, `tbyte`; `default rel`; and MASM's `PROC` / `ENDP`, `LOCAL`, `INVOKE`, `.IF` / `.WHILE` / `.REPEAT` (see MASM's procedures below) |

The functions `ifunc` names are built in, as in NASM: `__?ilog2e?__(x)`,
`__?ilog2w?__`, `__?ilog2f?__`, `__?ilog2c?__` (and `__ilog2e__` & co).
They work on x as an unsigned 64-bit number (`ilog2f(-1)` is 63,
`ilog2c(-1)` 64; 0 for 0).

```asm
%use ifunc
shift   equ ilog2(PAGE_SIZE)    ; 12 for 4096
%use masm
f proc
        mov eax, dword ptr [rbx]
        ret
f endp
```

Without `%use masm`, `ptr` is NASM's warning "`ptr' is not a NASM
keyword" [-w+ptr]; utasm still reads `dword ptr [rbx]` as `dword [rbx]`,
where NASM stops at the undefined symbol `ptr`.

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

%require "utils.asm"            ; NASM 3: %include, unless this pass has
                                ; read that file already
```

`%require` skips a file that an `%include` or `%require` has already read
in this pass. utasm recognises the file by its device and inode, so
`"pi.inc"` and `"./pi.inc"` are the same file, as in NASM's assembly. NASM's
`-E` compares names, so it reads the second spelling again. The source file
itself does not count: a `%require` of it reads it once more, then stops
there, as NASM does. A `%require` of a file that is not found is an error;
NASM 3 skips it without a word.

`[pragma ...]` is the same as `%pragma ...` (it is what `-E` writes for a
`%pragma`): `[pragma output gprefix _]`.

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

With `-f elf64` / `-f elf32`, a section's type, flags and alignment come
from its name, as NASM's do: besides `.text`, `.data`, `.rodata` and
`.bss`, the names `.tdata` / `.tbss` (thread-local, `tls`),
`.init_array`, `.fini_array`, `.preinit_array`, `.comment`, `.note`,
`.lrodata`, `.ldata` and `.lbss` have their defaults. Attributes given on a
section's first line replace them: `progbits`, `nobits`, `alloc`,
`noalloc`, `exec`, `noexec`, `write`, `nowrite`, `tls`, `notls`,
`align=N`. As in NASM, attributes without `align=` leave a new section's
alignment at 1 (`section .data progbits` is 1-aligned, `section .data` is
4-aligned).

```asm
section .tdata                  ; progbits, alloc write tls, align 4
section .tbss                   ; nobits,   alloc write tls, align 4
section .tls2 progbits alloc write tls align=8
```

`align N` and `alignb N` raise the section's alignment to N as well.
`sectalign` controls that:

```asm
sectalign 32                    ; this section is at least 32-aligned
sectalign off                   ; align / alignb pad, but no longer raise it
sectalign on                    ; they do again
```

An `align` of 2^32 or more is NASM's error ``absurdly large segment
alignment `0x100000000'``.

With `-f win64` the defaults are NASM's COFF ones: `.text` code (aligned
16), `.data` data (4), `.bss` uninitialised data (4), `.rdata` and `.xdata`
read-only data (8), `.pdata` read-only data (4), and any other name code
(16). The attributes are `code` (or `text`), `data`, `rdata`, `bss`,
`info` (removed by the linker: `.drectve` directives) and `align=N` (up to
8192), which sets the alignment, below the default too:

```asm
section .rdata rdata align=16
section .mycode code
section .drectve info           ; "-defaultlib:kernel32 " and the like
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
common aligned_buffer 64:16     ; ... aligned to 16
```

With `-f win64`, `dd f wrt ..imagebase` is the address of `f` less the
image's base (`IMAGE_REL_AMD64_ADDR32NB`), as `.pdata` unwind entries need;
only `global f:function` / `:data` of these attributes are accepted (see
[cli.md](cli.md#coff-objects--f-win64)).

`global` and `extern` take NASM's ELF attributes after a colon: a type
(`function`, `data`, `object`, `notype`), a visibility (`default`,
`internal`, `hidden`, `protected`) and a binding (`weak`, `strong`):

```asm
global main:function            ; STT_FUNC
global table:data hidden        ; STT_OBJECT, STV_HIDDEN
global hook:function weak       ; STB_WEAK
extern helper:function hidden
extern optional:weak            ; an undefined weak reference
```

An `extern` that nothing uses is left out of the object's symbol table, as
NASM leaves it out. The table starts with an `STT_FILE` symbol naming the
source file.

---

### Call frame information

GAS's `.cfi_` directives describe how each function's frame is laid out,
for debuggers, profilers and backtraces (`gdb`'s `bt`, `perf`, a C++
exception or a crash handler unwinding through the code). utasm writes
them as the `.eh_frame` section of an ELF object, byte for byte as GNU `as`
does for the same code; NASM has no such directives.

```asm
f:
    .cfi_startproc                  ; at a call: CFA = rsp + 8
    push    rbp
    .cfi_def_cfa_offset 16
    .cfi_offset rbp, -16            ; rbp saved at CFA - 16
    mov     rbp, rsp
    .cfi_def_cfa_register rbp
    ...
    leave
    .cfi_def_cfa rsp, 8
    ret
    .cfi_endproc
```

The directives are `.cfi_startproc` (`simple`: no rules at the start),
`.cfi_endproc`, `.cfi_def_cfa reg, offset`, `.cfi_def_cfa_register reg`,
`.cfi_def_cfa_offset offset`, `.cfi_adjust_cfa_offset delta`,
`.cfi_offset reg, offset`, `.cfi_rel_offset reg, offset` (from the CFA
register), `.cfi_restore reg`, `.cfi_undefined reg`, `.cfi_same_value reg`,
`.cfi_register reg, reg`, `.cfi_remember_state`, `.cfi_restore_state`,
`.cfi_signal_frame`, `.cfi_escape byte, ...` and `.cfi_sections` (accepted).
A register is a name (`rbx`, `r12`, `rip`, `xmm3`, `st0`, `k1`; in
`-f elf32` `ebp`, `eip`, `xmm0`-`xmm7`) or its DWARF number. The rules move
with the code when jumps are shortened. With `-f bin` and `-f win64` they
are read and not written. The misuses are errors with GAS's messages
("CFI instruction used without previous .cfi_startproc" and the like).

### Line tables: .file and .loc

GCC's `-g` output names its source files and gives each instruction its
source position; utasm makes `.debug_line` of them as GNU `as` 2.43 does,
byte for byte (the compatibility suites assemble GCC's `-g` output at every
level, in both syntaxes, with both and compare every section).

```asm
    .file 0 "/build" "src/m.c"      ; DWARF 5: the build directory, file 0
    .file 1 "src/m.c"               ; file 1 ("dir" "name" and md5 0x... too)
    .loc 1 12 5 view .LVU3          ; file, line, column, options
    movl    %edi, %eax
```

- `.loc FILE LINE [COLUMN]` takes `is_stmt 0|1`, `discriminator N`,
  `isa N`, `basic_block`, `prologue_end`, `epilogue_begin` and
  `view NAME | 0 | -0`. Its row is at the next instruction - at once when it
  has a view, or when another `.loc` comes first - in a code section (in
  data it waits for the next instruction).
- A row's view is 0 where the address moved on from the row before in its
  section, else that row's view plus one; `view .LVUn` defines `.LVUn` as
  that number, which GCC's location lists read (`.uleb128 .LVU12`).
  `view 0` asserts it is 0; `view -0` makes it 0.
- The version: `--gdwarf-N` (GCC passes `--gdwarf-5`), DWARF 3 without
  one, DWARF 5 once `.file 0` or `.loc 0` comes. DWARF 5 keeps its file and
  directory names in `.debug_line_str`, after the compiler's own strings.
- The rows move with the code when jumps are shortened. So do the label
  differences GCC's debug sections measure code with, `.quad .LFE1-.LFB1`
  and `.uleb128 .LVL3-.LVL2`: GNU's syntax works them out once the code is
  laid out, as GNU `as` does (a LEB128's in the second pass, its size from
  its value), where utasm used to keep the code between them as it was
  first written - jumps there stayed long.
- A view that only padding decides (a row after `ret`, then `.p2align`,
  then a row) is worked out once the code is laid out, as GNU `as` does:
  the second pass has its value.
- A label or a row just before an alignment (GCC's `.LVL8:` /
  `.p2align 4,,10`) stays before its padding when the padding grows; one
  after it stays after.
- Where GNU `as` starts a new frag because its memory chunk is full, it
  sets a `view -0` row's address again; utasm advances to the same address
  (the same table, a few bytes otherwise).
- `.file N` and `.loc` take the line table from `-g`: utasm writes none of
  its own then, as GNU `as`. Without a `.debug_info` of the source's, GNU
  `as` writes a compile unit of its own for the table; utasm does not yet.
- The errors are GNU `as`'s: "unassigned file number N", "file table slot
  N is already occupied by a different file", "unknown .loc sub-directive",
  "is_stmt value not 0 or 1", "view number mismatch", "duplicate
  .debug_line sections".

### GNU as directives

utasm also reads GNU `as` code in its Intel syntax (`.intel_syntax
noprefix`): its directives, macros, repetitions and conditionals, and its
operand forms. Each does what it does in GNU `as`: the same sections, flags,
bytes and symbols (the compatibility suites check this against GNU `as`
itself). NASM's directives and macros keep working beside them in the same
file.

```asm
    .intel_syntax noprefix
    .section .rodata.str1.1, "aMS", @progbits, 1
msg:
    .asciz  "hello\n"
    .text
    .globl  main
    .type   main, @function
main:
    lea     rdi, msg[rip]
    ...
    ret
    .size   main, . - main
```

| Directives | What they do |
|---|---|
| `.text`, `.data`, `.bss` | `section .text` ... |
| `.section NAME[, "FLAGS"[, @TYPE[, ENTSIZE]]]` | a section; for a new one, GNU's flag letters `a w x M S T`, its type (`@progbits`, `@nobits`, `@note`, `@init_array`, `@fini_array`, `@preinit_array`) and its entry size (needed with `M`) |
| `.pushsection NAME ...`, `.popsection`, `.previous` | the section stack; the section used before the last change |
| `.globl` / `.global`, `.weak`, `.local`, `.extern` | `global`, `weak`, `local`, `extern` |
| `.hidden`, `.internal`, `.protected` | the symbols' ELF visibility |
| `.type NAME, @function` / `@object` / `@tls_object` / `@notype` | the ELF symbol type (`@` is optional; the word may also be in quotes) |
| `.size NAME, EXPR` | the ELF symbol size (`. - main`) |
| `.byte`; `.short` / `.word` / `.hword` / `.value` / `.2byte`; `.long` / `.int` / `.4byte`; `.quad` / `.8byte`; `.octa` | 1, 2, 4, 8 and 16-byte values |
| `.ascii`, `.asciz` / `.string` | strings, with GNU's escapes (`\n \t \b \f \v \r \\ \" \x41 \101`); `.asciz` adds a NUL after each |
| `.base64 "STR"[, "STR" ...]` | the bytes each base64 string encodes (GCC's for a large initializer; "invalid character found inside .base64 string" otherwise) |
| `.zero N`, `.skip N[, F]` / `.space N[, F]` | N bytes of F (reserved in a nobits section) |
| `.fill R[, S[, V]]` | R values of S bytes, each V (its low 4 bytes, the rest zero, as GNU's) |
| `.uleb128`, `.sleb128` | LEB128 numbers |
| `.balign` / `.align N[, F[, MAX]]`, `.p2align K[, F[, MAX]]` | aligned to N bytes / 2^K bytes, with GNU's long NOPs in code and zeros in data unless F is given; no padding when it would take more than MAX bytes (`.p2align 4,,10`) |
| `.org N[, F]` | padding up to offset N in the section (an error if that is behind) |
| `.equ NAME, EXPR`, `.set NAME, EXPR`, `.equiv NAME, EXPR` | constants; `.set` may give a name a new value later, `.equiv` gives an error for a name already defined; set to a label (`.set f.localalias, f`, GCC's) the name is that label's alias: it moves with the label's code and takes its type and size |
| `.comm NAME, SIZE[, ALIGN]`, `.lcomm NAME, SIZE` | a common block; SIZE bytes of `.bss` under a local name, placed after all the `.bss` data the source writes, as GNU `as` places its local commons |
| `.code16`, `.code32`, `.code64` | `bits 16` / `32` / `64` |
| `.ident "TEXT"` | TEXT in the `.comment` section |
| `.intel_syntax` | `DWORD PTR`, `OFFSET`, `FLAT:` read as GNU `as` reads them (`ptr`, `flat` and `offset` as `%use masm` has them) |
| `.file`, `.loc` | the line table (`.debug_line`, see above) |
| `.arch` | accepted, nothing else done |

Addresses relative to `rip` are written as GNU `as` writes them, in 64-bit
code: `[rip + x]` and `x[rip]` (also `DWORD PTR x[rip + 8]`) are `[rel x]`;
`[rip + 8]`, `[rip - 16]` and `[rip]` (a number, or an `equ` constant) are
that displacement from the next instruction, as written. `rip` takes no
other register (`[rip + rax]` is an error). `8[rbp]`, a displacement before
the brackets, is `[rbp + 8]`.

In an expression a single `.` is the current address, `$`. Once GNU's
syntax is chosen (`.intel_syntax`, `.att_syntax` or `--att`) names follow
GNU `as`, so that a compiler's output comes out as the object GNU `as`
makes of it:

- a `.name` (`.L3`, `.LC0`) is a name of its own, not local to the label
  before it; `.L` names are left out of the symbol table, except in a
  section the linker merges (`.rodata.str1.1`, `.rodata.cst8`), where the
  relocations name them;
- a name used and never defined is an external (in an object file);
- a `call` to a global or external name is `R_X86_64_PLT32`, and keeps
  its relocation even within its section (another object may define the
  name first); a `jmp` or `jcc` to a global of its own section is resolved
  there, as GNU `as` resolves it - unless the name is weak or written
  `f@PLT`;
- jumps are sized as GNU `as` sizes them: each starts short and grows
  only when its target is out of reach (never shrinks back), alignment
  padding is worked out again after each change, and a jump's reach
  across an alignment counts the padding as it was - so every jump comes
  out the size GNU `as` gives it, not NASM's choice;
- alignment padding in code after data (`.byte`, `.ascii`, `.zero` ...)
  starts with a one-byte `nop`, as GNU `as` pads it;
- a load through the GOT is the relaxable `R_X86_64_GOTPCRELX` /
  `R_X86_64_REX_GOTPCRELX` (`R_386_GOT32X`), and a GOT or TLS relocation
  names `_GLOBAL_OFFSET_TABLE_`;
- `.size f, .-f` is worked out once jumps are made short (taken when read,
  it froze the function's code); `.p2align 4,,10` pads nothing where more
  than 10 bytes are needed, also after jumps are made short;
- `.local x` then `.comm x, N, A` is N bytes of `.bss`, local; `.file
  "x.c"` names the object's FILE symbol;
- a double-quoted name is the name (GCC 16 quotes every one under
  `-masm=intel`: `"main":`, `.globl "main"`, `call "puts"@PLT`,
  `"cmp"[rip]`), and `sym@PLT` (`@GOTPCREL` ... as in AT&T syntax) is `sym
  wrt ..plt`;
- a segment the address uses anyway (`ds:` with most bases, `ss:` with
  `rbp` or `rsp`) is left out: `BYTE PTR ds:0` is `[0]`, `ss:[rbp]` is
  `[rbp]`; `ds:[rbp]` and `ss:[rax]` keep theirs;
- prefixes are written in GNU `as`'s order - segment, `67`, `66`, `rep`,
  `lock` (`lock add [eax], bx` is `67 66 F0 01 18`; NASM 3's is `67 F0
  66`), an AT&T prefix word (`rep`, `lock`, `addr32`, `%fs` of a string
  instruction) with the instruction's own;
- `mov rax, 5` is the `REX.W C7` form GNU `as` writes, not NASM's `mov eax,
  5`; `pextrw` / `pmovmskb` / `lar` / `lsl` / `str` / `sldt` into a 64-bit
  register take no `REX.W`, as GNU `as`'s.

In GNU's Intel syntax also: `st(1)` is `st1` and `st` alone `st0`;
`XMMWORD PTR`, `YMMWORD PTR`, `ZMMWORD PTR` and `MMWORD PTR` are `oword`,
`yword`, `zword` and `qword`; `movabs` is `mov` (GCC's, for an immediate
past 32 bits); `data16` / `data32` and `addr16` / `addr32` are the raw
`66` / `67` prefixes (`osp`, `asp`), `rex64` alone its `48` - GCC's TLS
sequence. A sized operand may be written in brackets (`call [QWORD PTR
80[rax]]`, GCC's indirect call). GCC's `-masm=intel` output assembles to
the object GNU `as` makes of it as its AT&T output does.

NASM's own sources keep NASM's rules: undefined names are errors, `.loop`
is local to the label before it. A directive name followed by `:` is a
label (`.text:`), and one followed by `equ`, `times`, a `res` or a `d` word
is a label too, so a structure field named `.size` or `.type` keeps
working.

### AT&T syntax (`.att_syntax`, `--att`)

GNU `as`'s own syntax, read as GNU `as` reads it - from `.att_syntax` on,
or from the start with `--att` (GCC writes no directive for it). Each
statement is translated into utasm's syntax and read from there (numbered
as the line that made it), so the encoder and the diagnostics are the same:

```asm
movl $5, -4(%rbp,%rcx,4)     ; mov dword [rbp + rcx*4 + (-4)], 5
leaq .LC0(%rip), %rdi        ; lea rdi, [rel .LC0]
call puts@PLT                ; call puts wrt ..plt
movq %fs:0x28, %rax          ; mov rax, [fs:0x28]
jmp *%rax                    ; jmp rax
ljmp $0x10, $start           ; jmp 0x10:start
```

- Operands: `%reg` (`%st(1)`), `$imm`, memory `seg:disp(base, index,
  scale)`, `*` before an indirect branch's operand; they are written source
  first, the order reversed (`enter` keeps its order). AVX-512's `{%k1}`,
  `{z}`, `{1to16}` and `{rn-sae}` go where they are written.
- Mnemonics: the instruction's own name (`setl`, `cmovl`, `fabs`), else
  with GNU's size suffix taken off - `b w l q` (`x y`: a 128- / 256-bit
  memory operand), x87's `s l t` for floats and `s l ll q` for integers -
  which gives the memory operand its size; and GNU's names: `movzbl`,
  `movslq`, `cltq`, `cqto`, `cwtl`, `movabs`, `lret`, `ljmp`, `lcall`,
  `movsl`, `stosq` and the rest. `push` / `pop` of memory without a suffix
  take the stack's width.
- As GNU `as` does: `fsub`, `fsubr`, `fdiv`, `fdivr` with `%st(i)` the
  destination, and `fsubp` ... without operands, are the other one of the
  pair (the SysV x87 mnemonics); a shift by no count shifts by 1; `movq`
  between general registers or with memory is `mov`, and `movq $imm` to a
  64-bit register is the sign-extended imm32 (`48 C7 /0`); a string
  instruction's operands only name it, a segment other than its own a
  prefix; a prefix (`rep`, `lock`, `data16`, `cs` ... `rex64`) is its byte,
  alone on its line too (`rep; ret`).
- `;` ends a statement and `#` starts a comment anywhere; `%` first on a
  line is still a directive (`%define`, `%include`). Numbers are GNU's:
  `017` is octal. `sym@PLT` (`@GOTPCREL`, `@GOT`, `@GOTOFF`, `@GOTPC`,
  `@TPOFF`, `@NTPOFF`, `@GOTTPOFF`, `@INDNTPOFF`, `@TLSGD`, `@TLSLD`,
  `@DTPOFF`) is `sym wrt ..plt` and so on.

`.intel_syntax` turns it off again. GCC's AT&T output (`gcc -S`) assembles
to the object GNU `as` makes of it, section by section and relocation by
relocation, at `-O0` to `-O3`, `-Os` and `-fPIC`
(`scripts/compat/suites.py`, `att`). `.att_syntax noprefix` takes
registers without their `%` (a name that is a register is then the
register). `-g` output too: the line table comes from `.loc` (see Line
tables above). Over NASM's own C sources compiled by GCC (`-O0` to `-O3`,
`-Os`, `-fPIC`, `-g`, `-gdwarf-4`, `-masm=intel`) every section, symbol
and relocation is GNU `as`'s, but for one thing: GNU `as` sometimes
restarts `.debug_line`'s address with `DW_LNE_set_address` where its
internal fragments happen to break (the same addresses either way).

A string instruction's `es:[rdi]` operand never takes a prefix (es is its
own; a `26` there overrode the other operand's segment):
`movsb es:[rdi], fs:[rsi]` is `64 a4`.

#### GNU macros, repetitions and conditionals

```asm
    .macro  save reg, slot=0
    mov     [rsp + \slot], \reg
    .endm
    save    rax, 8                  ; mov [rsp + 8], rax
    save    rbx                     ; mov [rsp + 0], rbx
    save    slot=16, reg=rcx        ; named arguments

    .irp    r, rbx, r12, r13
    push    \r
    .endr

    .rept   4
    nop
    .endr
```

| Directives | What they do |
|---|---|
| `.macro NAME [P[=DEFAULT \| :req \| :vararg] ...]` ... `.endm` | a macro; its parameters separated by commas or blanks. In its body `\P` is the argument's text, `\@` the number of macros run before this one, and `\()` nothing (`\P\()_x` pastes). Its name is matched in any letter case; a macro may be named like an instruction. |
| `NAME A1, A2` / `NAME A1 A2` / `NAME P2=A2, P1=A1` | a call: arguments by position or by name; a missing one is its default (or empty); a `:req` one must be given; a `:vararg` one takes the rest of the line; `"..."` around an argument is taken off |
| `.exitm` | the macro being expanded ends here (and a `.rept` / `.irp` inside it) |
| `.purgem NAME` | the macro forgotten |
| `.rept N` ... `.endr` | N copies |
| `.irp S, V1, V2 ...` ... `.endr` | a copy for each value, `\S` that value (no values: one copy, `\S` empty) |
| `.irpc S, CHARS` ... `.endr` | a copy for each character |
| `.if E` (`.ifne`), `.ifeq`, `.ifgt`, `.ifge`, `.iflt`, `.ifle E` | E compared with zero (E a number when the line is read) |
| `.ifdef S`, `.ifndef S` / `.ifnotdef S` | S defined so far (a name only declared `extern` is not) |
| `.ifb TEXT`, `.ifnb TEXT` | the rest of the line blank (in a macro: an argument left out) |
| `.ifc A, B`, `.ifnc A, B` | the two texts the same, as written (`'a'` is not `a`) |
| `.ifeqs "A", "B"`, `.ifnes "A", "B"` | the two strings the same |
| `.elseif E`, `.else`, `.endif` | the rest of a conditional |

They nest in each other in any way: a macro's body may hold `.rept`, `.if`
and another `.macro`, and a macro may call itself, ended by an `.if` (more
than 1024 levels at once: "macros nested too deeply"). A body is taken as
source text, up to its `.endm` / `.endr`, and an expansion is read as that
text with its arguments in place; an error in it is reported at the body's
own line. In a listing (`-l`) the call is one line, with all the bytes the
expansion made. A conditional's skipped part is not assembled; NASM's `%`
directives in it are still read. A GNU `.macro`, `.rept` or `.irp`, or an
`.ifb` / `.ifc`, needs its source text, so it cannot be inside a NASM
`%macro` or `%rep` (an error); NASM's macros can be used inside GNU ones.
The errors are GNU's: "unexpected end of file in macro `m' definition",
"`.endif' with nothing open for it", "end of file in conditional", "missing
value for required parameter `a'", "too many positional arguments" and the
like.

### FASM's virtual, load and store

```asm
virtual at 0                ; assembled, written nowhere
    mov     eax, ebx
    len = $                 ; 2
    load    op byte from 0  ; 0x89
end virtual

msg:    db "hello"
sum = 0
%assign i 0
%rep 5
    load    b byte from msg + i
    sum = sum + b           ; a checksum made at assembly time
%assign i i+1
%endrep
    db      sum & 0xFF
    store   byte 0xAA at msg         ; the bytes patched
```

| Directive | What it does |
|---|---|
| `virtual [at ADDR]` ... `end virtual` | what is between is assembled and laid out from ADDR (from `$` without `at`) in a space of its own that is written nowhere: its labels are plain numbers, its bytes there for `load` (an instruction's length or encoding). Blocks nest. |
| `load NAME [byte\|word\|dword\|qword] from ADDR` | NAME a constant: the bytes at ADDR of the space being assembled (the section, or the virtual block), little endian; a byte when no size is written |
| `store [byte\|word\|dword\|qword] VALUE at ADDR` | those bytes made VALUE |
| `defined NAME`, `defined(NAME)` | in an expression: 1 when NAME is a label or a constant defined so far, else 0 (utasm reads the source once: a label defined further on is not defined yet) |
| `NAME = EXPR` | NAME a constant, set again by a later `NAME = ...` (`x = x + 1`), as in FASM, MASM and GNU `as` (`.set`) |

FASM's lines that choose the output work too: `format ELF64 executable`
writes an executable (as `--standalone`; named as the source without its
extension when there is no `-o`), `entry NAME` is where it starts (`_start`
when there is none), and after a `format` line `segment readable
executable` / `segment readable writeable` / `segment readable` are
`.text` / `.data` / `.rodata`. `format ELF64`, `format ELF` and `format
binary` must be the format `-f` chose (it is chosen before the source is
read); another one is an error. NASM's `segment .data` stays `section`.

The bytes `load` and `store` reach must be there and final:not past what
is assembled, not a field a relocation fills in, nor a jump whose
displacement or size is settled later - those are errors ("load / store of
bytes not final yet"). ADDR is a label or `$` of the space being assembled,
or an address in a virtual block (or a flat binary's first section).
`load`, `store` and `virtual` followed by `:`, `equ`, `db`, `resb` or
`times` are still labels of that name.

### MASM's procedures, INVOKE and control flow (`%use masm`)

```asm
%use masm
sumto PROC USES rbx, n:QWORD
    LOCAL acc:QWORD, i:DWORD
    mov     acc, 0
    mov     i, 1
    mov     edx, dword ptr n
    .WHILE i <= edx
        mov     eax, i
        add     acc, rax
        inc     i
    .ENDW
    mov     rax, acc
    ret                         ; pop rbx / leave / ret
sumto ENDP

    invoke  sumto, 10           ; mov rdi, 10 / xor eax, eax / call sumto
    .IF rax > 50 && rax != 99
        ...
    .ELSE
        ...
    .ENDIF
```

| Form | What it does |
|---|---|
| `NAME PROC [NEAR\|FAR] [C\|STDCALL\|SYSCALL] [PUBLIC] [USES R ...] [, P[:TYPE] ...]` ... `NAME ENDP` | a procedure. With parameters or `LOCAL`s it has a frame (`push rbp` / `mov rbp, rsp` / `sub rsp, SIZE`, the size known at `ENDP`); the `USES` registers are pushed after it. The parameters are copied from their registers into the frame (System V: `rdi rsi rdx rcx r8 r9`, `xmm0`-`xmm7` for `REAL4` / `REAL8`; `-f win64`: `rcx rdx r8 r9` into their home slots) or read where the caller pushed them (past the registers, and in 32-bit code), and each is a typed memory operand by its name (`mov eax, p`, `mov p, 5`; `dword ptr p` casts it). `PUBLIC` makes NAME global. |
| `ret` in a `PROC` | its epilogue: the `USES` registers popped, `leave`, then `ret` (`retf` in a `FAR` one; `ret N` for a 32-bit `STDCALL` one, N its parameters' bytes) |
| `LOCAL A:TYPE, B[N]:TYPE ...` | named stack slots in the frame, aligned to their size; right after the `PROC` line |
| `INVOKE F, A1, A2 ...` | the arguments in their registers (64-bit registers moved, 32-bit ones and `dword` memory into the 32-bit name, bytes and words zero-extended, `addr X` its address with `lea`), the rest pushed last first (the stack 16-aligned at the call; Win64's 32-byte shadow space), `xor eax, eax` (System V's count of vector arguments, for variadic functions), `call F`, the stack put back. An argument read from a register an earlier argument was loaded into is an error. |
| `.IF C` / `.ELSEIF C` / `.ELSE` / `.ENDIF` | compares and jumps |
| `.WHILE C` / `.ENDW`, `.REPEAT` / `.UNTIL C`, `.REPEAT` / `.UNTILCXZ` | loops (`.UNTILCXZ`: `loop`) |
| `.BREAK [.IF C]`, `.CONTINUE [.IF C]` | out of / on with the innermost loop |
| `.CODE`, `.DATA`, `.DATA?`, `.CONST` | `section .text`, `.data`, `.bss`, `.rodata` |
| `EXTERNDEF NAME[:TYPE], ...` | `extern NAME`; `PROTO` and `OPTION` lines are taken |

A condition C is `A == B`, `!=`, `<`, `<=`, `>`, `>=` (unsigned; signed when a
side is written `sbyte` / `sword` / `sdword` / `sqword`, as `sdword ptr eax`),
`A & B` (`test`), `A` alone (not zero), or a flag: `ZERO?`, `CARRY?`, `SIGN?`,
`OVERFLOW?`, `PARITY?` - joined with `!`, `&&`, `||` and parentheses, `&&`
before `||`, both short-circuiting. Two memory operands cannot be compared
(x86 has no such `cmp`). The code each of these makes is listed on its own
line in a listing, and an error in it is reported at that line. Its labels are
`..@mN`. NASM's `masm` package treated `proc` as a label and ignored `USES`;
utasm does MASM's.

#### MASM's typed data and structures

```asm
%use masm
POINT STRUCT
    x   DWORD ?
    y   DWORD 7             ; the default
    tag BYTE  "ab"
POINT ENDS

.data
count   DWORD 10
arr     DWORD 1, 2, 3, 4
buf     BYTE  16 DUP (0)
pt      POINT <5, , >       ; x 5, y and tag their defaults
.data?
scratch QWORD 4 DUP (?)
.code
    mov     eax, count              ; a memory read: count is a typed variable
    add     eax, pt.y               ; dword [pt + POINT.y]
    lea     rbx, pt
    add     eax, [rbx].POINT.y      ; a field through a register, typed
    mov     ecx, SIZEOF arr         ; 16 (LENGTHOF arr 4, TYPE arr 4)
    mov     rdx, OFFSET arr         ; the address
```

| Form | What it does |
|---|---|
| `[NAME] TYPE ITEM, ...` | data: TYPE `BYTE` `WORD` `DWORD` `QWORD` (`SBYTE` ... `SQWORD`), `REAL4` `REAL8` `REAL10`, `TBYTE`, `OWORD`; an ITEM a value, a string (`BYTE`), `?` (zero; reserved in a nobits section), `N DUP (ITEM, ...)`. NAME is a typed variable. |
| a typed variable | a memory operand of its type by its name (`mov eax, count`, `add count, 1`, `lea rbx, buf`); `OFFSET count` (and INVOKE's `ADDR count`) is its address |
| `NAME STRUCT` ... `NAME ENDS` | a structure: its lines `FIELD TYPE ITEM` (a NASM `struc`: `NAME.FIELD` the offsets, `NAME_size`); their items the defaults |
| `NAME T <V, ...>` / `NAME T {V, ...}` | an instance (`istruc T`): the values given, the defaults for those left out or empty; `NAME.FIELD` each field, typed (`pt.y`) |
| `[REG].T.FIELD` | the field through a register, typed |
| `SIZEOF X`, `LENGTHOF X`, `TYPE X` | in an expression: the bytes, the elements, an element's bytes - of a typed variable, a structure, a field (`T.F`), a type word, or a NASM `struc` (`X_size`) |

Data written NASM's way (`x dd 5`) is a plain label as before: only MASM's
`x DWORD 5` makes a typed variable. A name followed by a type word is data
unless the name is an instruction or a NASM word (`push dword 5`, `istruc
POINT`, `.IF sdword ...`). `ENDS` with no `STRUCT` open ends a segment.

### Procedures (`proc` / `endproc`)

A procedure is a label with checks between it and its `endproc`. utasm
adds no code - the pushes and pops are written as ever - but follows the
stack and the preserved registers (rbx, rbp, r12-r15: docs/abi.md)
through the procedure as it is written:

```asm
proc net_send uses rbx, r12      ; rbx and r12 are saved here
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    ...
    pop     r12
    pop     rbx
    ret
endproc
```

| Class | By default | What it says |
| --- | --- | --- |
| `proc-stack` | error | the stack is not back where it was at a `ret` ("8 bytes still pushed"), or two paths reach a label with different depths ("16 bytes here, 8 by a jump to it") |
| `proc-uses` | error | a register named in `uses` is written before it is pushed, is not restored at a `ret`, or is never saved |
| `proc-clobber` | warning | a preserved register is written while not saved, and `uses` does not name it |
| `proc-unreachable` | warning | code after a `ret` or `jmp` with no label before it |
| `proc-fallthrough` | warning | the code runs on into `endproc` |

The depth is the bytes pushed since the procedure's label: `push` / `pop`
(2 bytes for a word), `pushf` / `popf`, `push2` / `pop2`, `sub rsp, N` /
`add rsp, N`, `lea rsp, [rsp + N]`, `enter` / `leave`, and a frame - `mov
rbp, rsp`, then `mov rsp, rbp`, `leave` or `lea rsp, [rbp - N]` back to
it. Any other write to `rsp` (`and rsp, -16`) leaves the depth unknown
until a frame restores it; nothing is checked while it is unknown. A
jump carries its depth to its label, so a push on one path and not the
other is found where they meet. A preserved register pushed and popped
around its use is kept, whether `uses` names it or not; `uses` adds that
it must be. `cpuid` writes rbx. The classes take `-w-` and `-w+error=`
as any other (`-w-proc-stack`, `-w+error=proc-clobber`).

`proc` and `endproc` are utasm's own words in its syntax (not under
`%use masm`, whose `NAME PROC` is MASM's, nor GNU's). A label named
`proc` (`proc:`) stays a label.

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

#### Typed access: `[reg:TYPE].field`

utasm's own form. `:TYPE` at the end of an address says what the address
points to. The `.field` after the bracket is then `TYPE.field`: its offset is
added, and its width (the `res*` that reserved it) sizes the operand.

```asm
struc PACKET
    .len:   resd 1
    .flags: resw 1
    .ptr:   resq 1
endstruc

mov eax, [rbx:PACKET].len            ; mov eax, [rbx + PACKET.len]
mov [rbx:PACKET].len, 5              ; a dword: no "dword" needed
inc word [rdi:PACKET].flags          ; a size written must be the field's
mov rdx, [rbx + rcx*8:PACKET].ptr    ; any address; [fs:rbx:PACKET] too
lea rsi, [rbx:PACKET].ptr
mov eax, [rbx:PACKET]                ; no field: the struc's start, unsized
```

These lines are errors:

- `mov eax, [rbx:PACKET].flags`: eax is 32 bits and the field is 16.
- `dword [rbx:PACKET].flags`: the size written is not the field's.
- `[rbx:PACKET].nope`: PACKET has no such field.
- `[rbx:NOPE].len`: NOPE is not a struc.

Notes:

- A field of several elements (`.arr: resb 6`) is sized by one element.
- TYPE must be defined before the line that uses it. A struc is any name
  with a `NAME_size`.
- In GNU mode, `reg:` keeps its meaning as a segment override.

---

### Assembler Control

```asm
; [GEN2] → bits 64
bits 64                         ; 64-bit mode (default for AMD64)
bits 32                         ; 32-bit mode
bits 16                         ; 16-bit mode (bootloader/real mode)
use16 / use32 / use64           ; the same

; [GEN2] → cpu generic / cpu x86_64_v3 etc
cpu 386                         ; NASM's levels: 8086 186 286 386 486
cpu p6                          ;   586 / pentium, 686 / p6 / ppro / p2,
cpu x86-64                      ;   p3 / katmai, p4 / willamette, prescott,
cpu sandybridge                 ;   x64 / x86-64, nehalem, westmere,
cpu default                     ;   sandybridge, ivybridge; any / default
cpu latevex                     ; and its options: latevex, (no)vex, (no)evex

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

`cpu LEVEL` takes NASM's levels: an instruction none of whose forms is of
the level or below is "no instruction for this cpu level" (`cpu 386` and
`cpuid`, `cpu 486` and `cmovz`, `cpu p6` and `movaps`); `cpu any` or `cpu
default` lifts it, an unknown name is an error. Forms are told apart as
NASM tells them: a 32-bit form is 386 (a 32-bit register, `66` in 16-bit
code, a dword memory operand or `push` of an immediate in 32-bit code, a
`jmp far [m]` to a 16:32 pointer; not the address size, and not x87's
`fld dword`), and `push 5`, `imul ax, bx, 3` and `shl ax, 4` are 186.
Under the instruction's own level an obsolete one is "obsolete but
valid" (`cpu 486` and `smintold`), else "obsolete and removed".

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
