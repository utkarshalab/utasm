# utasm — Internal ABI

> utasm's internal calling convention for pure assembly code.
> Every module must follow this exactly. No exceptions. No assumptions.
> If this document and the code disagree, fix the code.

---

## Why This Exists

Pure assembly has no compiler enforcing calling conventions. Every function call
is a promise between the caller and callee. Without a written contract, every
module makes different assumptions and they silently corrupt each other.

This document is that contract. Written once. Followed everywhere.

---

## Platform

```
Architecture:   x86-64 (AMD64)
Mode:           64-bit long mode
Endianness:     Little-endian
Pointer size:   8 bytes
Stack growth:   Downward (toward lower addresses)
```

---

## Register Classification

### Argument Registers (caller-owned, scratch after call)

```
RDI   →  argument 1
RSI   →  argument 2
RDX   →  argument 3
RCX   →  argument 4
R8    →  argument 5
R9    →  argument 6
```

Up to 6 arguments passed in registers. Additional arguments on stack (right to left).

### Return Registers (caller-owned, scratch after call)

```
RAX   →  primary return value (integer, pointer, boolean, error code)
RDX   →  secondary return value (high 64 bits of 128-bit result, or second output)
```

### Scratch Registers (caller-owned, not preserved)

```
RAX   →  return value / scratch
RCX   →  argument 4 / scratch
RDX   →  argument 3 / secondary return / scratch
RSI   →  argument 2 / scratch
RDI   →  argument 1 / scratch
R8    →  argument 5 / scratch
R9    →  argument 6 / scratch
R10   →  scratch
R11   →  scratch
```

Caller must save these before a call if their values are needed after.

### Preserved Registers (callee-owned, must be saved and restored)

```
RBX   →  preserved (general purpose)
RBP   →  preserved (frame pointer, optional but must be saved if used)
R12   →  preserved (general purpose)
R13   →  preserved (general purpose)
R14   →  preserved (general purpose)
R15   →  preserved (general purpose)
```

Callee must save these at function entry and restore before return if used.

### Special Registers

```
RSP   →  stack pointer — always maintained, never scratch
RIP   →  instruction pointer — never directly modified (use JMP/CALL/RET)
RFLAGS→  scratch — callee does not preserve flags
```

---

## Full Register Map

```
Register   Role                    Preserved    Notes
────────   ────────────────────    ─────────    ───────────────────────────
RAX        return / scratch        NO           primary return value
RBX        general                 YES          push/pop in every function that uses it
RCX        arg4 / scratch          NO
RDX        arg3 / secondary ret    NO           high 64 bits of 128-bit returns
RSI        arg2 / scratch          NO
RDI        arg1 / scratch          NO
RBP        frame pointer           YES          save if used, not required
RSP        stack pointer           SPECIAL      always 16-byte aligned at call
R8         arg5 / scratch          NO
R9         arg6 / scratch          NO
R10        scratch                 NO           reserved for syscall link (see below)
R11        scratch                 NO           destroyed by SYSCALL instruction
R12        general                 YES
R13        general                 YES
R14        general                 YES
R15        general                 YES
```

---

## Argument Passing

### Up to 6 Arguments — Register Passing

```asm
; function signature:
;   my_func(ptr, len, flags, mode, extra1, extra2)
;
mov rdi, ptr_value      ; arg1
mov rsi, len_value      ; arg2
mov rdx, flags_value    ; arg3
mov rcx, mode_value     ; arg4
mov r8,  extra1_value   ; arg5
mov r9,  extra2_value   ; arg6
call my_func
```

### More Than 6 Arguments — Stack Passing

Arguments 7+ pushed right-to-left before the call. Callee accesses via `[rsp+8]`, `[rsp+16]` etc. (accounting for return address at `[rsp]`).

```asm
; function with 8 arguments:
push arg8               ; pushed first (rightmost)
push arg7               ; pushed second
mov rdi, arg1
mov rsi, arg2
mov rdx, arg3
mov rcx, arg4
mov r8,  arg5
mov r9,  arg6
call my_func
add rsp, 16             ; caller cleans stack args
```

### Pointer Arguments

All pointers passed as 64-bit values in argument registers. Null pointer = 0.

### Boolean Arguments

0 = false, 1 = true. Any non-zero value is treated as true on the receiving end.

### Small Values

8-bit, 16-bit, 32-bit values are zero-extended to 64-bit before passing. Callee may use full 64-bit register width.

---

## Return Values

### Single Return Value

Returned in RAX.

```asm
; returning a pointer:
my_func:
    ; ... work ...
    mov rax, result_ptr
    ret

; returning an integer:
my_func:
    mov rax, 42
    ret

; returning a boolean:
my_func:
    xor rax, rax        ; rax = 0 (false)
    ; or
    mov rax, 1          ; rax = 1 (true)
    ret
```

### Two Return Values

Primary in RAX, secondary in RDX.

```asm
; returning ptr + length:
my_func:
    mov rax, buf_ptr    ; primary: pointer
    mov rdx, buf_len    ; secondary: length
    ret
```

### Error Returns

See Error Handling section below. Error code in RAX, 0 = success.

### Void Functions

RAX is undefined. Caller must not use it.

---

## Stack Convention

### Alignment

RSP must be **16-byte aligned** at the point of every `call` instruction.

After function entry (after `call` pushes return address), RSP is 8-byte aligned.

```asm
my_func:
    ; RSP is 8-byte aligned here (return address was pushed by call)
    ; RSP % 16 == 8

    push rbx            ; RSP now 16-byte aligned (RSP % 16 == 0)
    push r12            ; RSP now 8-byte aligned again (RSP % 16 == 8)
    push r13            ; RSP now 16-byte aligned
    ; ...

    ; before calling another function:
    ; RSP must be 16-byte aligned
    ; count pushes — if odd number of registers saved, add sub rsp, 8
```

**Rule:** Count saved registers at function entry. If count is odd, add `sub rsp, 8` for alignment. Add `add rsp, 8` before return.

```asm
my_func:
    push rbx            ; 1 register = odd → need alignment pad
    push r12            ; 2 registers = even → aligned
    push r13            ; 3 registers = odd → need alignment pad
    sub rsp, 8          ; pad for alignment

    ; ... call other functions safely ...

    add rsp, 8          ; remove pad
    pop r13
    pop r12
    pop rbx
    ret
```

### Stack Frame (optional)

Frame pointer is optional. Use it when debugging is needed or when complex stack manipulation is happening.

```asm
my_func:
    push rbp
    mov rbp, rsp
    ; ... stack frame established ...
    ; local vars at [rbp - N]
    ; args 7+ at [rbp + 16], [rbp + 24], etc.
    pop rbp
    ret
```

### Red Zone

utasm does NOT use the red zone (128 bytes below RSP). Kernel code and signal handlers invalidate it. All local data must be below the explicitly allocated stack frame.

---

## Error Handling

This is one of the most critical sections of this document. Every function
that can fail must follow these conventions exactly. Inconsistent error
handling is how bugs stay hidden for months.

---

### The Fundamental Contract

```
RAX = 0          →  success. result in RDX if applicable.
RAX = non-zero   →  failure. RAX is the error code. RDX is undefined.
```

No exceptions. No other return conventions for errors. Always RAX.

---

### Error Return Convention

Every function that can fail follows this exact pattern:

```asm
; ─── SUCCESS PATH ───
.success:
    xor rax, rax            ; RAX = 0 = ERR_NONE
    ret                     ; result already in RDX if needed

; ─── FAILURE PATH ───
.fail_undefined_symbol:
    mov rax, E401           ; specific error code — never a generic one
    ret

.fail_redefinition:
    mov rax, E402
    ret
```

**Rules:**
- Use the most specific error code available
- Never use a generic E8xx internal error when a real code exists
- Never return -1 or other ad-hoc values — only defined E codes
- Never leave RAX undefined on any return path

---

### Infallible Functions

Functions that cannot fail must document this explicitly and
must not be called with error checking:

```asm
; INFALLIBLE — always succeeds, no error check needed
; Returns: RAX → hash value
hash_fnv1a:
    ; ...
    ret
```

Calling error_report() is itself infallible. The error engine
must never fail — it is the last resort.

---

### Error Checking at Call Sites

**Every fallible call must be checked. No exceptions.**

```asm
; ─── PATTERN 1: branch on error ───
call parse_operand
test rax, rax
jnz .handle_error           ; non-zero = failure

; success path continues here

; ─── PATTERN 2: propagate immediately ───
call lex_next
test rax, rax
jnz .propagate              ; bubble up unchanged

; ─── PATTERN 3: handle specific errors differently ───
call sym_insert
test rax, rax
jz .inserted_ok             ; zero = success
cmp rax, E402
je .handle_redef            ; E402 = redefinition — we can recover
jmp .propagate              ; anything else — propagate

; ─── PATTERN 4: ignore intentionally ───
call log_debug              ; documented as infallible
; no check — intentionally omitted, must be documented in comment
```

**Never do this:**
```asm
call parse_operand
; (no check — silent error ignore)   ← BUG — forbidden
```

If you genuinely don't care about an error, say so explicitly:

```asm
call flush_log              ; intentionally ignore flush errors — best effort only
```

---

### Propagating Errors

When a callee fails and the caller cannot recover, propagate immediately.
Do not call error_report() again — the callee already reported it.

```asm
my_func:
    push rbx
    push r12
    sub rsp, 8

    call lex_next
    test rax, rax
    jnz .fail               ; propagate — lex_next already reported

    call parse_instr
    test rax, rax
    jnz .fail               ; propagate — parse_instr already reported

    ; ... success path ...
    xor rax, rax
    jmp .done

.fail:
    ; rax already holds the error code from the callee
    ; do NOT call error_report() here — it was already called
    ; do NOT zero rax — preserve the error code

.done:
    add rsp, 8
    pop r12
    pop rbx
    ret                     ; rax = 0 (success) or error code (failure)
```

**The double-report trap:**
```asm
; WRONG — reports the error twice:
call sym_insert
test rax, rax
jz .ok
mov rdi, rax
call error_report           ; WRONG — sym_insert already called error_report
jmp .fail

; CORRECT — just propagate:
call sym_insert
test rax, rax
jnz .fail                   ; propagate silently — already reported
```

---

### When to Call error_report() Directly

Call error_report() only when **your function** detects the error condition
directly — not when a callee returns an error code.

```asm
; CORRECT — this function detected the problem:
parse_register:
    call lex_next
    test rax, rax
    jnz .fail               ; lex error — propagate, do not report

    ; check what we got:
    cmp [rel cur_token.type], T_REG
    je .is_register

    ; WE detected this problem — WE report it:
    mov rdi, E203           ; expected register
    mov rsi, [rel cur_token_ptr]
    xor rdx, rdx            ; no hint
    call error_report

    mov rax, E203           ; return error code
    ret

.is_register:
    xor rax, rax
    ret
```

---

### Error + Valid Result

When a function needs to return both a result and an error status:

```asm
; Convention: RAX = 0 (success), RDX = result value
;             RAX = Exxx (failure), RDX = 0 (undefined)

sym_lookup:
    ; found:
    xor rax, rax            ; success
    mov rdx, [rbx + Symbol.value]  ; result in RDX
    ret

    ; not found:
    mov rax, E401           ; undefined symbol
    xor rdx, rdx            ; RDX = 0 on failure — always
    ret

; caller:
    call sym_lookup
    test rax, rax
    jnz .not_found
    ; rdx = symbol value — valid only because rax == 0
    mov r12, rdx
```

**Rule:** RDX is only valid when RAX == 0. On any failure, RDX is always
zeroed before returning. Callers must never read RDX after a failed call.

---

### Recoverable vs Fatal Errors

Not all errors are equal. Classify explicitly:

**Recoverable** — assembly continues, more errors may be found:
```asm
; lexer recovers by skipping to next line
; parser recovers by skipping to next instruction
; encoder recovers by skipping current instruction
; → call error_report(), then continue
```

**Fatal** — assembly must stop immediately:
```asm
; E812 out of memory — cannot continue without memory
; E8xx internal errors — state is corrupt
; E3207 %fatal directive — user explicitly stopped
; → call error_report(), then call sys_exit(EXIT_ENCODER_ERROR)
```

```asm
; fatal error pattern:
.out_of_memory:
    mov rdi, E812
    xor rsi, rsi            ; no token
    xor rdx, rdx            ; no hint
    call error_report
    mov rdi, EXIT_OOM
    call sys_exit           ; does not return
```

**Deferred** — error recorded but not reported until end of pass:
```asm
; forward reference errors — cannot report until pass 2 resolves
; → store in error buffer, report in error_flush()
```

---

### Error Accumulation Limit

utasm stops accumulating errors after MAX_ERRORS (100 by default).
After this limit, error_report() silently discards new errors and
error_flush() prints the first 100 plus a count of suppressed errors.

```
"100 errors reported. 47 additional errors suppressed.
 Fix the first errors first."
```

This prevents error avalanches where one root cause generates thousands
of downstream errors.

---

### Error Codes Must Be Constants

Error codes in function bodies must always be symbolic constants.
Never use raw numbers.

```asm
; WRONG:
mov rax, 501            ; what is 501? no idea without looking it up

; CORRECT:
mov rax, E501           ; operand size mismatch — immediately clear
```

All constants defined in `error/table.s` and referenced via `include/constant.inc`.

---

### Logging vs Error Reporting

Two separate systems. Do not confuse them.

**error_report()** — for source errors found during assembly.
Fires exactly once per error. Goes to stderr. Counted. Affects exit code.

**log_debug()** — for utasm's own internal diagnostics.
Never shown to users. Only active in DEBUG builds. Never affects exit code.

```asm
; for user-facing source errors:
mov rdi, E501
mov rsi, token_ptr
call error_report

; for internal utasm debugging:
%ifdef DEBUG
    lea rdi, [rel .msg]
    call log_debug
    .msg: db "entered sym_insert, rbx=", 0
%endif
```

Never call log_debug() in release builds. The %ifdef DEBUG guard is mandatory.

---

### Error Handling in Initialization Functions

Init functions (called once at startup) use a stricter pattern.
Any failure is immediately fatal — there is no partial initialization.

```asm
error_init:
    ; allocate error record buffer
    mov rdi, ERROR_RECORD_POOL_SIZE
    call mem_alloc
    test rax, rax
    jz .oom                 ; allocation failed

    mov [rel error_pool_ptr], rax

    ; allocate dedup table
    mov rdi, ERROR_DEDUP_SIZE
    call mem_alloc
    test rax, rax
    jz .oom

    mov [rel error_dedup_ptr], rax

    xor rax, rax            ; success
    ret

.oom:
    ; cannot call error_report — error engine not yet initialized
    ; write directly to stderr and abort
    lea rdi, [rel .oom_msg]
    mov rsi, .oom_msg_len
    call sys_write_stderr
    mov rdi, EXIT_OOM
    call sys_exit

.oom_msg: db "utasm: fatal: out of memory during initialization", 10
.oom_msg_len equ $ - .oom_msg
```

**Rule:** Never partially initialize a module. Either fully initialize and
return 0, or fail completely and abort.

---

### Error Handling Template

Copy this template for every non-trivial fallible function:

```asm
; ─────────────────────────────────────────────────────────────────
; function_name
;
; One-line description of what this function does.
;
; Arguments:
;   RDI  →  arg1_name  [const]  description
;   RSI  →  arg2_name           description
;
; Returns:
;   RAX  →  0 on success, E4xx on failure
;   RDX  →  result (valid only when RAX == 0)
;
; Errors:
;   E401  →  symbol not found (recoverable)
;   E402  →  symbol redefined (recoverable)
;   E812  →  out of memory (fatal)
;
; Calls error_report() directly: YES / NO
; Calls error_report() via callees: YES / NO
; ─────────────────────────────────────────────────────────────────
function_name:
    push rbx
    push r12
    sub rsp, 8              ; alignment

    ; ... body ...

    xor rax, rax            ; success
    jmp .done

.fail_not_found:
    mov rax, E401
    xor rdx, rdx
    jmp .done

.fail_redef:
    mov rax, E402
    xor rdx, rdx

.done:
    add rsp, 8
    pop r12
    pop rbx
    ret
```

---

## Internal-Only Functions (Fastcall Variant)

For very hot internal functions called millions of times (inner loops, hot paths):

```
These functions use a minimal fastcall convention:
- Arguments: RAX, RDX, RCX, RSI (first 4 args only)
- Return: RAX
- Preserved: RBX, R12–R15 (same as standard)
- Scratch: everything else

Must be marked in source with comment:
; FASTCALL — non-standard ABI, internal only
```

Use this only for:
- Micro-kernel inner loops
- Error report hot path
- Hash table lookup (called billions of times during assembly)

Document every fastcall function in its source file header.

---

## Syscall Convention

For direct syscalls to the OS, utasm uses raw syscall ABI:

```
RAX   →  syscall number
RDI   →  arg1
RSI   →  arg2
RDX   →  arg3
R10   →  arg4  (NOTE: R10 not RCX — syscall clobbers RCX and R11)
R8    →  arg5
R9    →  arg6

Return:
RAX   →  return value (negative = error: -errno)

Clobbered by SYSCALL instruction:
RCX   →  destroyed (saved RIP)
R11   →  destroyed (saved RFLAGS)
```

Always use the wrappers in `host/syscall.s`. Never call SYSCALL directly from module code.

```asm
; correct — use wrapper:
mov rdi, STDOUT
lea rsi, [rel msg]
mov rdx, msg_len
call sys_write

; wrong — never do this in module code:
mov rax, SYS_WRITE
mov rdi, STDOUT
mov rsi, msg
mov rdx, msg_len
syscall
```

---

## SIMD Register Convention

When SIMD registers are used inside a function:

```
XMM0–XMM7   →  scratch (not preserved, argument/return for SIMD)
XMM8–XMM15  →  scratch (not preserved)
YMM0–YMM15  →  scratch (not preserved — upper halves are scratch)
ZMM0–ZMM31  →  scratch (not preserved)
K0–K7        →  scratch (not preserved)

No SIMD registers are callee-saved in the utasm internal ABI.
```

If a function uses SIMD heavily and calls other functions, it must save/restore XMM registers it needs across calls using stack slots:

```asm
sub rsp, 32
vmovaps [rsp],    ymm8    ; save
vmovaps [rsp+16], ymm9    ; save

call other_function

vmovaps ymm8, [rsp]       ; restore
vmovaps ymm9, [rsp+16]    ; restore
add rsp, 32
```

**VZEROUPPER rule:** Any function that uses YMM or ZMM registers must emit `vzeroupper` before calling any non-SIMD function. Prevents AVX-SSE transition penalties.

```asm
simd_function:
    ; ... use YMM registers ...
    vzeroupper              ; mandatory before calling non-SIMD code
    call error_report
    ; ...
    ret
```

---

## RFLAGS Convention

RFLAGS is **not preserved** across calls. Callee may use any arithmetic and comparison instructions freely.

Caller must not assume any flag state after a call returns.

```asm
; WRONG — assuming flags survive across call:
cmp rax, 0
call some_function
je .was_zero            ; WRONG — flags may have changed

; CORRECT — save result before call:
cmp rax, 0
setz al                 ; save zero flag in al
movzx rbx, al          ; save to preserved register
call some_function
test rbx, rbx
jnz .was_zero           ; check saved result
```

---

## Function Prologue/Epilogue Templates

### Minimal Function (no preserved regs used)

```asm
my_func:
    ; no prologue needed
    ; ... body ...
    ret
```

### Standard Function (uses preserved regs)

```asm
my_func:
    push rbx            ; save preserved registers used
    push r12
    push r13
    sub rsp, 8          ; alignment (3 pushes = odd, need pad)

    ; ... body uses rbx, r12, r13 freely ...

    add rsp, 8          ; remove alignment pad
    pop r13
    pop r12
    pop rbx
    ret
```

### Function with Local Variables

```asm
my_func:
    push rbx
    push r12
    sub rsp, 40         ; 16 bytes locals + 8 pad (3 total pushes → odd → need pad)
                        ; breakdown: [rsp+0..15] = local data, [rsp+16..23] = pad

    ; access locals:
    mov QWORD PTR [rsp], 0       ; local var 1
    mov QWORD PTR [rsp+8], rdi   ; local var 2 = arg1

    ; ... body ...

    add rsp, 40
    pop r12
    pop rbx
    ret
```

### Function That Calls Syscalls

```asm
my_func:
    push rbx            ; preserve rbx (syscall clobbers nothing we care about
    push r12            ;              except RCX and R11 which are scratch anyway)
    sub rsp, 8          ; alignment

    ; ... use sys_write wrapper, etc. ...

    add rsp, 8
    pop r12
    pop rbx
    ret
```

---

## Naming Conventions

### Function Names

```
module_verb_noun        → preferred pattern
lexer_scan_ident        → lexer module, scans identifier
error_report_fatal      → error module, reports fatal
sym_table_insert        → symbol table, insert operation
enc_emit_rex            → encoder, emits REX prefix
```

Internal-only functions (not called outside their module):
```
.local_helper           → local label, only visible in same file
_module_internal        → underscore prefix, module-internal
```

### Argument Documentation

Every non-trivial function must have a comment header:

```asm
; ─────────────────────────────────────────────────────────────
; sym_insert
;
; Insert a symbol into the symbol table.
;
; Arguments:
;   RDI  →  name_ptr    (ptr to null-terminated symbol name)
;   RSI  →  name_len    (length of name in bytes)
;   RDX  →  value       (symbol value / address)
;   RCX  →  type        (symbol type: SYM_LABEL, SYM_EQU, etc.)
;   R8   →  file_id     (source file index)
;   R9   →  line        (source line number)
;
; Returns:
;   RAX  →  0 on success, E402 on redefinition, E414 on name too long
;
; Preserves: RBX R12 R13 R14 R15
; Clobbers:  RAX RCX RDX RSI RDI R8 R9 R10 R11
; ─────────────────────────────────────────────────────────────
sym_insert:
    push rbx
    ; ...
```

---

## Module Boundaries

Each module has a defined public interface. Only public symbols are callable from other modules.

```asm
; public interface — callable from anywhere:
global lexer_init
global lexer_next
global lexer_peek
global lexer_reset

; private — only within lexer/ files:
; (no global declaration — not visible outside)
scan_ident:
scan_number:
scan_string:
```

Never call private functions from another module. If you need it from outside, make it public and document it.

---

## Memory Safety

Memory bugs in assembly are silent, hard to reproduce, and destructive.
This section defines every rule that prevents them. Every rule is mandatory.

---

### The Four Memory Safety Laws

```
Law 1: Every allocation has exactly one owner.
Law 2: Only the owner frees.
Law 3: No pointer outlives its allocation.
Law 4: No access outside allocated bounds.
```

Violating any of these is a bug. There is no "probably fine".

---

### Allocator Hierarchy

utasm uses a strict allocator hierarchy. Each allocator has a defined
lifetime and purpose. Using the wrong allocator for the purpose is a bug.

```
┌─────────────────────────────────────────────────────────┐
│  LIFETIME          ALLOCATOR         USE CASE           │
├─────────────────────────────────────────────────────────┤
│  Permanent         sys_mmap()        binary buffers,    │
│  (process life)                      output sections,   │
│                                      source file mmap   │
├─────────────────────────────────────────────────────────┤
│  Per-file          arena_alloc()     tokens, AST nodes, │
│  (reset per file)  (main arena)      error records,     │
│                                      symbol names       │
├─────────────────────────────────────────────────────────┤
│  Per-pass          arena_alloc()     intermediate data  │
│  (reset per pass)  (pass arena)      that is rebuilt    │
│                                      each pass          │
├─────────────────────────────────────────────────────────┤
│  Stack             sub rsp, N        small temporaries  │
│  (function scope)                    < 4096 bytes       │
│                                      never escape func  │
└─────────────────────────────────────────────────────────┘
```

**Rules:**
- Stack allocations must never escape the function that allocated them
- Arena allocations are freed only by arena_reset() — never individually
- mmap allocations are freed by mem_free() by exactly one owner
- Never mix allocators for the same logical object

---

### Ownership Model

Every pointer in utasm has exactly one owner at any point in time.

**Ownership states:**

```
OWNED       → this code is responsible for freeing
BORROWED    → this code may use but must not free
TRANSFERRED → ownership has moved to another module
```

Document the state in function headers:

```asm
; RDI → src_ptr  [borrowed]    — we read only, caller still owns
; RSI → dst_ptr  [borrowed]    — we write, caller still owns
; RAX ← new_ptr  [transferred] — caller now owns this allocation
; RAX ← buf_ptr  [borrowed]    — arena-owned, do not free
```

---

### No Implicit Allocation

**Every allocation must be visible at the call site.**

```asm
; WRONG — hidden allocation:
parse_token:
    call arena_alloc        ; where? what size? caller has no idea
    ; ... fill it ...
    mov rax, result_ptr
    ret

; CORRECT — document explicitly:
; Returns: RAX → Token* (arena-owned, valid until next arena_reset)
;          caller must not free this pointer
parse_token:
    mov rdi, Token_size
    call arena_alloc
    ; ...
    ret
```

---

### Arena Allocation Rules

The main arena is used for all per-file data (tokens, AST, symbols).

```asm
; correct arena allocation:
mov rdi, Token_size         ; size in bytes
call arena_alloc            ; returns ptr in RAX, 0 on OOM
test rax, rax
jz .oom                     ; always check — arena can exhaust

; wrong — not checking OOM:
mov rdi, Token_size
call arena_alloc
mov [rbx], rax              ; WRONG — rax could be 0
```

**Arena rules:**
- Always check return value — OOM returns 0
- Arena memory is zero-initialized on allocation
- Do not call any free/munmap on arena pointers
- Do not store arena pointers across arena_reset() calls
- Arena_reset() invalidates ALL pointers from that arena

**After arena_reset() all arena pointers are DEAD:**
```asm
call arena_alloc
mov r12, rax                ; r12 = arena pointer

call arena_reset            ; RESET

mov rax, [r12]              ; USE-AFTER-RESET — r12 is now dead
                            ; this is a bug even if the memory is still mapped
```

---

### Stack Memory Rules

Stack allocations are the simplest — they die when the function returns.

```asm
my_func:
    sub rsp, 64             ; allocate 64 bytes on stack
    lea rbx, [rsp]          ; pointer to stack buffer

    ; ... use rbx as buffer ...

    add rsp, 64
    ret
    ; rbx is now dead — stack frame freed
```

**Stack rules:**
- Never return a pointer to stack memory
- Never pass a stack pointer to a function that stores it
- Never store a stack pointer in a global
- Stack buffers must be allocated at function entry, freed at exit
- Maximum stack allocation without probing: 4096 bytes

**Use-after-return:**
```asm
my_func:
    sub rsp, 64
    lea rax, [rsp]          ; WRONG — returning pointer to stack memory
    add rsp, 64
    ret                     ; rax points to freed stack — caller uses dead memory

; CORRECT — return arena-allocated or caller-provided memory instead
```

---

### Buffer Bounds Rules

Every buffer access must be within bounds. There is no implicit protection.

**Always track buffer size alongside pointer:**

```asm
; tracking size:
mov r12, buf_ptr            ; pointer
mov r13, buf_len            ; size in bytes

; before writing:
cmp rbx, r13                ; current offset vs size
jae .buf_overflow           ; >= size means out of bounds

; writing:
mov BYTE PTR [r12 + rbx], al
inc rbx
```

**Never assume buffer size from context:**
```asm
; WRONG — assuming the buffer is big enough:
mov [output_buf + rcx], rax     ; what if rcx >= output_buf_size?

; CORRECT — check before write:
cmp rcx, output_buf_size
jae .overflow
mov [output_buf + rcx], rax
```

**Buffer overflow on write is a bug. Buffer overflow on read is a bug.
Both are silent. Neither is acceptable.**

---

### Pointer Arithmetic Rules

```asm
; CORRECT — pointer arithmetic:
lea rbx, [rax + rcx]       ; compute address
; then validate before use:
cmp rbx, [rel buf_end]
jae .out_of_bounds
mov rdx, [rbx]             ; safe read

; WRONG — arithmetic then use without validation:
add rax, rcx               ; compute offset
mov rdx, [rax]             ; no bounds check — could be anywhere
```

**Rules for pointer arithmetic:**
- Compute the address first
- Validate the result is within bounds
- Then access memory
- Never access and validate simultaneously

---

### String Bounds

String operations must respect buffer boundaries.

```asm
; scanning a string — always check against end:
.scan_loop:
    cmp rdi, [rel src_end]  ; past end?
    jae .scan_done          ; yes — stop
    movzx rax, BYTE PTR [rdi]
    test rax, rax
    jz .scan_done           ; null terminator
    ; ... process byte ...
    inc rdi
    jmp .scan_loop

; WRONG — trusting null terminator without bounds:
.bad_scan:
    movzx rax, BYTE PTR [rdi]
    test rax, rax
    jz .done                ; what if null byte is missing? scan past end of mapping
    inc rdi
    jmp .bad_scan
```

---

### Use-After-Free Detection (Debug Mode)

In DEBUG builds, freed memory is poisoned with 0xDEADBEEFDEADBEEF.
Any read of this value during debugging indicates use-after-free.

```asm
%ifdef DEBUG
mem_free:
    ; before unmapping, poison the memory:
    mov rdi, [rsp+8]        ; ptr
    mov rsi, [rsp+16]       ; size
    mov rax, 0xDEADBEEFDEADBEEF
    ; fill with poison value
    call mem_poison
%endif
    ; then unmap normally
```

---

### Double-Free Detection (Debug Mode)

In DEBUG builds, freed pointers are tracked in a freed-set.
Freeing the same pointer twice triggers E813.

```asm
%ifdef DEBUG
; before freeing, check if already freed:
    mov rdi, ptr_to_free
    call freed_set_check    ; returns 1 if already freed
    test rax, rax
    jnz .double_free_detected
%endif
```

---

### Memory Initialization Rules

**All allocated memory must be initialized before use.**

```asm
; WRONG — using uninitialized stack memory:
my_func:
    sub rsp, 32
    ; ... use [rsp] without initializing ...    BUG

; CORRECT — initialize first:
my_func:
    sub rsp, 32
    xor rax, rax
    mov [rsp], rax          ; initialize to 0
    mov [rsp+8], rax
    mov [rsp+16], rax
    mov [rsp+24], rax
    ; now safe to use
```

Arena allocations are zero-initialized by arena_alloc(). Stack allocations
are NOT zero-initialized. mmap anonymous allocations ARE zero-initialized
by the OS. Document which is which.

---

### Memory Ownership Transfer Patterns

**Pattern 1: Caller allocates, passes to callee (borrowing)**
```asm
; caller allocates and owns:
    sub rsp, 256            ; stack buffer
    lea rdi, [rsp]          ; pass pointer
    mov rsi, 256            ; pass size
    call fill_buffer        ; callee borrows — fills but does not free
    ; ... use [rsp] ...
    add rsp, 256            ; caller frees
```

**Pattern 2: Callee allocates, caller owns (transfer)**
```asm
; callee allocates:
alloc_token:
    mov rdi, Token_size
    call arena_alloc        ; callee allocates
    ; fills token
    ; rax = ptr
    ret                     ; ownership transferred to caller

; caller now owns (though it's arena memory — do not individual-free):
    call alloc_token
    test rax, rax
    jz .oom
    mov r12, rax            ; r12 owns this token
```

**Pattern 3: Shared ownership via arena (all cleared together)**
```asm
; everything in the main arena dies together:
    call arena_reset        ; ALL arena pointers invalidated at once
                            ; no individual ownership tracking needed
                            ; every pointer from this arena is now dead
```

---

### Memory Safety in the Error Engine

The error engine has special memory safety requirements:

```
Must never allocate from the main arena
    (arena_reset() between files would destroy error records)

Must never fail to allocate
    (OOM during error reporting is catastrophic)

Uses its own fixed-size pool
    (pre-allocated at startup, MAX_ERRORS capacity)
```

This is why error_init() is first in the initialization order and
uses its own pool separate from all other allocations.

---

### Detecting Memory Bugs

When a bug occurs, these symptoms indicate specific memory problems:

```
Symptom                          Likely cause
──────────────────────────       ──────────────────────────
Crash with address 0             Null pointer dereference
Crash with address 0xDEAD...     Use-after-free (debug mode)
Wrong output, no crash           Buffer overflow overwriting adjacent data
Crash in unrelated function      Stack corruption (buffer overflow)
Crash only on second run         Use-after-arena-reset
Different crashes each run       Uninitialized memory read
```

---

### Memory Safety Checklist (per function)

Before marking any function complete, verify:

```
[ ] Every allocation is checked for OOM (arena/mmap return 0 on fail)
[ ] Every buffer write is bounds-checked before the write
[ ] Every buffer read is bounds-checked before the read
[ ] No stack pointer escapes the function
[ ] No pointer is used after arena_reset()
[ ] No pointer is freed twice
[ ] Allocation ownership is documented in function header
[ ] Uninitialized stack memory is zeroed before use
[ ] String scans check against buffer end, not just null terminator
[ ] Pointer arithmetic result is validated before use
```

---

## Thread Safety

utasm is currently single-threaded. No locking is needed.

Global state is centralized in `core/globals.s`. Any function that modifies global state must be documented as doing so.

When parallel assembly is added (Phase 20), this section will be updated with locking rules.

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────┐
│              utasm Internal ABI                     │
├──────────────┬──────────────────────────────────────┤
│ Arg 1–6      │ RDI RSI RDX RCX R8 R9               │
│ Arg 7+       │ stack, right-to-left, caller cleans  │
│ Return       │ RAX (primary) RDX (secondary)        │
│ Scratch      │ RAX RCX RDX RSI RDI R8 R9 R10 R11   │
│ Preserved    │ RBX RBP R12 R13 R14 R15              │
│ Stack align  │ 16-byte at CALL point                │
│ Red zone     │ NOT used                             │
│ SIMD         │ all scratch, no preservation         │
│ VZEROUPPER   │ required before calling non-SIMD     │
│ Flags        │ not preserved across calls           │
│ Error return │ RAX = 0 (ok) or error code (E1xx+)  │
│ Syscalls     │ via host/syscall.s wrappers only     │
└──────────────┴──────────────────────────────────────┘
```

---

## Violation Examples

Common mistakes to avoid:

```asm
; VIOLATION 1 — using preserved register without saving:
my_func:
    mov rbx, rdi        ; WRONG — rbx not saved
    call other
    ret

; CORRECT:
my_func:
    push rbx
    mov rbx, rdi
    call other
    pop rbx
    ret

; ──────────────────────────────────────────────────

; VIOLATION 2 — misaligned stack at call:
my_func:
    push rbx            ; one push = RSP % 16 == 0 now
    call other          ; WRONG — need RSP % 16 == 0 BEFORE call
                        ; one push means RSP % 16 == 0, then CALL pushes 8 more
                        ; so at entry to other: RSP % 16 == 8 ✓ (correct!)
                        ; ACTUALLY: entry RSP%16==8, push makes it 0, call makes it 8 again
                        ; Count: function entered with RSP%16==8
                        ;        push rbx → RSP%16==0
                        ;        call → RSP%16==8 ✓ correct at callee entry

; easier rule: count your pushes at function entry
; odd pushes  → add sub rsp, 8 before first call
; even pushes → you're aligned

; ──────────────────────────────────────────────────

; VIOLATION 3 — assuming flags after call:
    test rax, rax
    call log_something      ; clobbers flags
    jz .was_zero            ; WRONG — flags undefined after call

; CORRECT:
    test rax, rax
    setz bl                 ; save result to preserved register
    call log_something
    test bl, bl
    jnz .was_zero

; ──────────────────────────────────────────────────

; VIOLATION 4 — calling syscall directly:
    mov rax, 1              ; WRONG — call wrapper instead
    mov rdi, 1
    syscall

; CORRECT:
    mov rdi, 1
    lea rsi, [rel msg]
    mov rdx, len
    call sys_write

; ──────────────────────────────────────────────────

; VIOLATION 5 — YMM without vzeroupper:
simd_func:
    vmovaps ymm0, [rax]
    vaddps  ymm0, ymm0, ymm1
    vmovaps [rbx], ymm0
    call error_report       ; WRONG — must vzeroupper first
    ret

; CORRECT:
simd_func:
    vmovaps ymm0, [rax]
    vaddps  ymm0, ymm0, ymm1
    vmovaps [rbx], ymm0
    vzeroupper              ; mandatory
    call error_report
    ret
```

---

---

## Register Sub-Size Aliasing

Every 64-bit register has sub-size aliases. Using them does not clear the upper bits
(except 32-bit writes which zero-extend to 64-bit automatically).

```
64-bit   32-bit   16-bit   8-bit high   8-bit low
──────   ──────   ──────   ──────────   ─────────
RAX      EAX      AX       AH           AL
RBX      EBX      BX       BH           BL
RCX      ECX      CX       CH           CL
RDX      EDX      DX       DH           DL
RSI      ESI      SI       —            SIL
RDI      EDI      DI       —            DIL
RSP      ESP      SP       —            SPL
RBP      EBP      BP       —            BPL
R8       R8D      R8W      —            R8B
R9       R9D      R9W      —            R9B
R10      R10D     R10W     —            R10B
R11      R11D     R11W     —            R11B
R12      R12D     R12W     —            R12B
R13      R13D     R13W     —            R13B
R14      R14D     R14W     —            R14B
R15      R15D     R15W     —            R15B
```

**Critical rules:**

```asm
; 32-bit write ZERO-EXTENDS to 64-bit automatically:
mov eax, 1          ; RAX = 0x0000000000000001 (upper 32 bits cleared)

; 8-bit and 16-bit writes do NOT clear upper bits:
mov al, 1           ; RAX upper 56 bits UNCHANGED — may contain garbage
mov ax, 1           ; RAX upper 48 bits UNCHANGED — may contain garbage

; When returning 8-bit or 16-bit values, zero-extend first:
movzx rax, al       ; correct — RAX = zero-extended AL
; or use 32-bit write:
movzx eax, al       ; also correct — 32-bit write zero-extends to 64-bit

; AH/BH/CH/DH cannot be used with REX prefix — E514 fires:
mov ah, [r8]        ; INVALID — REX required for R8, conflicts with AH
```

**Rule:** When a function returns an 8-bit or 16-bit value in RAX, it must
zero-extend to 64 bits before returning. Callers must not assume upper bits are zero.

---

## String Conventions

utasm uses two string formats. Which one depends on context.

### Null-Terminated Strings (C-style)

Used for: filenames, symbol names, error messages, output text.

```asm
; null-terminated string
my_str: db "hello", 0

; passing to function:
lea rdi, [rel my_str]   ; pointer only — length computed by callee
call str_len            ; returns length in RAX
```

### Length-Prefixed Strings (utasm internal)

Used for: token text, source buffers, binary data that may contain null bytes.

```asm
; always pass as pointer + length pair:
lea rdi, [rel buf]      ; arg1: pointer
mov rsi, buf_len        ; arg2: length in bytes
call process_string
```

**Rule for function arguments:**
- If the string is guaranteed null-terminated and contains no embedded nulls: pass pointer only
- If the string may contain null bytes or length is performance-critical: pass pointer + length
- Never pass length without pointer

**Argument order for pointer+length pairs always:**
```
RDI → pointer
RSI → length
```

Never swap this order. Pointer first. Length second. Always.

---

## Struct Layout Rules

All structs defined in `include/type.inc` follow these layout rules exactly.

### Alignment Rule

Each field is naturally aligned to its own size:

```
BYTE  (1 byte)  → no alignment required
WORD  (2 bytes) → aligned to 2-byte boundary
DWORD (4 bytes) → aligned to 4-byte boundary
QWORD (8 bytes) → aligned to 8-byte boundary
```

### Padding Rule

Padding is inserted between fields to satisfy alignment. Padding bytes are
defined explicitly in the struct — never implicit.

```asm
struc MyStruct
    .byte_field   resb 1    ; offset 0
    .pad1         resb 3    ; offset 1 — explicit padding to align .dword_field
    .dword_field  resd 1    ; offset 4 — aligned to 4
    .pad2         resd 1    ; offset 8 — explicit padding to align .qword_field
    .qword_field  resq 1    ; offset 8 — aligned to 8 — WAIT: 4+4+4 = 12, not 8
    ; CORRECT layout:
endstruc

; CORRECT:
struc MyStruct
    .byte_field   resb 1    ; offset 0, size 1
    .pad1         resb 7    ; offset 1, size 7 — pad to align qword at 8
    .qword_field  resq 1    ; offset 8, size 8
    .dword_field  resd 1    ; offset 16, size 4
    .pad2         resd 1    ; offset 20, size 4 — pad struct to multiple of 8
endstruc                    ; total size: 24 bytes
```

### Struct Size Rule

Total struct size must be a multiple of the largest field alignment.

```asm
; if largest field is QWORD (8 bytes), total size must be multiple of 8
; add trailing padding if needed
```

### No Hidden Padding Rule

All padding bytes must be explicitly defined with `resb` or similar.
No relying on assembler-implicit padding. Every byte of every struct is accounted for.

### Packed Structs

When packing is required (e.g., ELF headers, network packets), use the actual
byte layout with no padding fields, and document it explicitly:

```asm
; PACKED — no alignment padding
; matches ELF64 Elf64_Sym exactly
struc Elf64_Sym
    .st_name    resd 1    ; offset 0,  size 4
    .st_info    resb 1    ; offset 4,  size 1
    .st_other   resb 1    ; offset 5,  size 1
    .st_shndx   resw 1    ; offset 6,  size 2
    .st_value   resq 1    ; offset 8,  size 8
    .st_size    resq 1    ; offset 16, size 8
endstruc                  ; total: 24 bytes — matches ELF spec
```

---

## Pointer Validity Rules

### Null Pointer

Null pointer = 0. Every function that accepts a pointer must document whether
it accepts null.

```asm
; function header must state:
; RDI → ptr (must not be null)
; or:
; RDI → ptr (null = use default)
```

Functions that say "must not be null" do NOT check for null at runtime in
release builds. The caller is responsible.

Debug builds (when DEBUG equ 1) add null checks:

```asm
%ifdef DEBUG
    test rdi, rdi
    jnz .ptr_ok
    mov rdi, E810       ; E810: unexpected null pointer
    call error_report
    ret
.ptr_ok:
%endif
```

### Pointer Range

Pointers must point to valid mapped memory. utasm does not validate pointer
ranges at runtime. Invalid pointers cause segfaults — that is acceptable
behavior during development.

### Ownership at Pointer Boundaries

When a pointer is passed to a function, ownership is NOT transferred unless
explicitly documented:

```asm
; RDI → name_ptr (borrowed — callee must not free)
; RDI → name_ptr (ownership transferred — callee responsible for freeing)
```

---

## Large Return Values (Struct Returns)

Functions that return a struct larger than 16 bytes use a hidden pointer convention.

The caller allocates space and passes a pointer as an implicit first argument in RDI.
The remaining arguments shift: what was arg1 becomes arg2, etc.

```asm
; function logically returning a 32-byte struct:
;   MyResult my_func(int a, int b)
;
; actual ABI:
;   void my_func(MyResult* out, int a, int b)
;   RDI → out ptr (caller-allocated)
;   RSI → a
;   RDX → b
;   RAX → out ptr on return (same as RDI)

; caller:
    sub rsp, 32             ; allocate result space on stack
    mov rdi, rsp            ; pass pointer to result
    mov rsi, arg_a
    mov rdx, arg_b
    call my_func
    ; result now at [rsp]
    ; rax = rsp (can use either)
    add rsp, 32             ; free result space when done
```

**Rule:** If a function needs to return more than 16 bytes of data, use the
hidden pointer convention. Document it explicitly in the function header.

---

## Leaf Function Optimization

A leaf function is a function that makes no calls to other functions.

Leaf functions get these relaxations:
- No need to align RSP before entry (no CALL instruction issued)
- Can use red zone... **NO** — utasm never uses red zone regardless
- Can skip frame pointer setup entirely
- Can use any scratch registers freely including R10/R11

```asm
; leaf function — no calls, no frame setup needed:
hash_fnv1a:
    ; RDI = ptr, RSI = len
    mov rax, 0xcbf29ce484222325  ; FNV offset basis
    test rsi, rsi
    jz .done
.loop:
    movzx rcx, BYTE PTR [rdi]
    xor rax, rcx
    imul rax, 0x100000001b3       ; FNV prime
    inc rdi
    dec rsi
    jnz .loop
.done:
    ret                           ; no push/pop needed — pure leaf
```

Mark leaf functions with a comment:

```asm
; LEAF FUNCTION — makes no calls
hash_fnv1a:
```

---

## Tail Call Convention

When the last action of a function is calling another function and returning
its result, use a tail call: `JMP` instead of `CALL` + `RET`.

This eliminates one stack frame and one return.

```asm
; WRONG — unnecessary call/ret:
my_wrapper:
    push rbx
    ; ... setup ...
    pop rbx
    call target_function
    ret                     ; wasteful — just jmp instead

; CORRECT — tail call:
my_wrapper:
    push rbx
    ; ... setup ...
    pop rbx
    jmp target_function     ; tail call — target's RET returns to my_wrapper's caller
```

**Requirements for tail call:**
- All preserved registers already restored before the JMP
- RSP is in the same state as when my_wrapper was entered
- No cleanup needed after target returns

```asm
; tail call is NOT valid when:
my_func:
    push rbx                ; saved a register
    call target
    pop rbx                 ; need to restore after — cannot tail call
    ret
```

---

## Function Pointer Convention

Function pointers are 64-bit values holding the target address.

### Storing Function Pointers

```asm
; in data section:
my_handler: dq 0            ; function pointer slot (initialized to 0 = null)

; setting:
lea rax, [rel my_function]  ; get address of function
mov [rel my_handler], rax   ; store

; or via register:
mov [rel my_handler], rdi   ; store passed-in function pointer
```

### Calling Function Pointers

Always call through a register. Never call through memory directly.

```asm
; CORRECT:
mov rax, [rel my_handler]   ; load function pointer
test rax, rax               ; check null
jz .no_handler
call rax                    ; call through register

; WRONG — do not call through memory directly:
call [rel my_handler]       ; avoid — not CET-compatible, confuses branch prediction
```

### Passing Function Pointers as Arguments

Function pointers passed as arguments follow normal register conventions.
They are just 64-bit integers. Document them clearly in function headers:

```asm
; RDI → callback (ptr to function: void callback(token_ptr) — may be null)
```

---

## Direction Flag (DF) Convention

The Direction Flag controls string operation direction (MOVS, STOS, LODS, SCAS, CMPS).

**Rule: DF must always be 0 (clear) at function entry and exit.**

- DF = 0: string operations go forward (increment SI/DI)
- DF = 1: string operations go backward (decrement SI/DI)

```asm
; before using any string instruction, explicitly clear DF:
cld                         ; clear direction flag
rep movsb                   ; safe — operates forward

; if you set DF (STD), clear it immediately after:
std
; ... string op going backward ...
cld                         ; RESTORE immediately — never leave DF=1
```

**Never return from a function with DF=1.** Any function that sets DF must
clear it before any call and before return.

---

## FS and GS Segment Register Usage

In 64-bit mode, only FS and GS segment bases are meaningful.

**utasm's convention:**

```
FS base   →  RESERVED — do not use
            (reserved for future thread-local storage if threading added)

GS base   →  RESERVED — do not use
            (reserved for future per-CPU data if SMP assembly added)
```

No module may modify FS or GS base registers (via WRGSBASE, SWAPGS, or WRMSR).

No module may use FS: or GS: segment override prefixes for data access.

If this changes in a future phase, this section will be updated.

---

## x87 FPU State Convention

The x87 FPU has its own register stack (ST0–ST7) and control word.

**utasm's FPU rules:**

```
FPU control word   →  default precision (64-bit extended) assumed
                      do not modify without restoring before return

FPU stack          →  must be empty (all registers free) at function entry and exit
                      if you use x87, pop all values before returning

x87 exceptions     →  masked by default — do not unmask
```

```asm
; correct x87 usage:
fpu_compute:
    fldz                    ; push 0.0 onto ST0
    fld QWORD PTR [rdi]     ; push value
    fadd                    ; ST0 = ST0 + ST1, pops ST1
    fstp QWORD PTR [rsi]    ; pop result to memory — stack now empty
    ret                     ; FPU stack empty ✓

; wrong — returning with values on FPU stack:
fpu_bad:
    fld QWORD PTR [rdi]     ; push to ST0
    ret                     ; WRONG — ST0 still has value, stack not empty
```

**Mixing x87 and SSE:** Do not mix x87 and SSE/AVX floating-point operations
in the same function. Use one or the other. If you must mix, use EMMS or
VZEROUPPER as appropriate.

---

## Stack Probing for Large Allocations

The OS maps stack pages on demand. Allocating more than 4096 bytes at once
may skip unmapped pages, causing a segfault instead of a stack overflow.

**Rule:** For stack allocations larger than 4096 bytes, probe every 4096 bytes:

```asm
; allocating 8192 bytes on stack:
sub rsp, 8192

; WRONG — if stack only has one page mapped, second page never touched before guard page

; CORRECT — probe each page:
sub rsp, 4096
mov [rsp], rax              ; touch first new page
sub rsp, 4096
mov [rsp], rax              ; touch second new page

; or use the stack probe helper:
mov rdi, 8192               ; bytes needed
call stack_probe            ; in lib/math.s — probes all pages
sub rsp, 8192               ; now safe to allocate
```

**In practice:** Most utasm functions allocate well under 4096 bytes. This
rule applies to encoder buffers, output buffers, and large temporary arrays.

---

## Global State Access Rules

All global mutable state lives in `core/globals.s`. Access rules:

### Reading Global State

Any module may read global state directly using RIP-relative addressing:

```asm
; reading a global:
mov rax, [rel current_file_id]
mov rax, [rel error_count]
```

### Writing Global State

Only the module that **owns** the global may write to it directly.
Other modules must call the owner's setter function.

```asm
; ownership table (defined in core/globals.s header):
; current_file_id  → owned by core/asmctx.s
; error_count      → owned by error/count.s
; pass_number      → owned by utasm.s (main)

; WRONG — error module writing to a field it doesn't own:
; (from inside lexer.s)
mov [rel error_count], rax      ; WRONG — error/count.s owns this

; CORRECT — call the owner's setter:
call count_error                 ; error/count.s's public function
```

### Global State Initialization Order

Modules initialize in this exact order. Each module's `_init` function must
be called exactly once by `utasm.s` before any other function of that module:

```
1.  lib/arena.s         → arena_init()
2.  lib/string.s        → (no init needed — pure functions)
3.  lib/hash.s          → (no init needed — pure functions)
4.  host/syscall.s      → (no init needed — pure wrappers)
5.  io/mem.s            → mem_init()
6.  io/file.s           → (no init needed)
7.  error/error.s       → error_init()       ← must be before anything that reports errors
8.  core/globals.s      → globals_init()
9.  core/asmctx.s       → ctx_init()
10. cpu/cpu.s           → cpu_init()
11. middle/symtable/    → symtable_init()
12. frontend/lexer/     → (initialized per-file by lexer_init())
13. frontend/macro/     → macro_init()
14. frontend/parser/    → (initialized per-file by parser_init())
15. middle/semantic/    → semantic_init()
16. backend/encoder/    → encoder_init()
17. backend/linker/     → linker_init()
18. backend/output/     → (initialized per-format)
```

No module may call any function of a module that appears later in this list
during its own initialization.

---

## Atomic Operations and LOCK Prefix

utasm is currently single-threaded. Atomic operations are not required for
correctness. However, LOCK prefix rules still apply for correctness on multi-core
hardware if utasm is ever used in a concurrent context.

**Rule:** Do not use LOCK prefix in utasm internal code unless specifically
implementing a lock-free data structure that is documented as thread-safe.

When LOCK is used:
```asm
; document every LOCK use:
; ATOMIC — required for thread safety when parallel assembly is added (Phase 20)
lock cmpxchg [rel counter], rdx
```

---

## Interrupt Handler ABI

Interrupt handlers (IDT entries in Tattva OS kernel) use a completely different
ABI. **This section is here so you do not confuse the two.**

Interrupt handlers are not called with CALL — they are entered via the
CPU's interrupt mechanism. The CPU pushes its own frame:

```
Before interrupt handler runs, CPU pushes (in this order):
    SS          (if privilege change)
    RSP         (if privilege change)
    RFLAGS
    CS
    RIP
    Error code  (for some exceptions only — #PF, #DF, #GP, etc.)
```

Interrupt handlers must:
- Save ALL registers (none are scratch — interrupted code had its own context)
- Use IRETQ to return (not RET)
- Not assume any register state on entry

```asm
; interrupt handler template:
my_handler:
    push rax            ; save ALL registers
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    push rbp

    ; ... handle interrupt ...

    pop rbp             ; restore ALL registers in reverse order
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq               ; return from interrupt — not RET
```

This ABI is for Tattva OS kernel code, not utasm internal code.
Documented here to prevent confusion.

---

## Varargs Convention

utasm does **not** support variadic functions in its internal ABI.

Every function has a fixed, documented argument count. If a function needs
to handle variable inputs, it accepts:
- A pointer to an array + a count, or
- A null-terminated array of pointers

```asm
; NOT this (no varargs):
; format_string(fmt, ...)

; THIS instead (array + count):
; format_string(fmt_ptr, args_ptr, args_count)
; RDI → fmt_ptr
; RSI → args_ptr (array of 64-bit values)
; RDX → args_count
```

---

## Const and Readonly Pointer Documentation

Function headers document pointer mutability:

```asm
; RDI → src_ptr  [const]  — callee will not write through this pointer
; RSI → dst_ptr  [out]    — callee writes result here, caller provides buffer
; RDX → buf_ptr  [in/out] — callee may both read and write
```

`[const]` is a documentation promise only. There is no enforcement mechanism.
Violating a `[const]` promise is a bug.

---

## Buffer and Size Argument Order

When a function takes a buffer pointer and its size, the order is always:

```
pointer first, size second
```

```asm
; ALWAYS:
; RDI → buf_ptr
; RSI → buf_size

; NEVER:
; RDI → buf_size
; RSI → buf_ptr
```

This applies to all functions in utasm without exception. Consistent ordering
means you never have to look up which argument is which.

When a function takes multiple buffers, they are ordered by their role:
input buffer first, output buffer second.

```asm
; RDI → src_ptr   [const]  input buffer
; RSI → src_len             input size
; RDX → dst_ptr   [out]    output buffer
; RCX → dst_size            output buffer capacity
; RAX ← bytes written (return value)
```

---

## Calling Convention Compatibility with System V AMD64 ABI

utasm's internal ABI is **deliberately compatible** with the System V AMD64
ABI (used by Linux) in its argument passing and preserved register rules.

This means:
- utasm internal functions can call Linux syscalls directly (via wrappers)
- If utasm is ever called as a library from C code, no adapter is needed
- NASM-generated code (Gen0) follows the same convention

**Differences from System V AMD64:**
- utasm does NOT use the red zone (System V allows 128 bytes below RSP)
- utasm requires DF=0 always (System V assumes it too, but is less strict)
- utasm does NOT preserve XMM6–XMM15 (System V on Windows does — we target Linux only)
- utasm uses error codes in RAX rather than errno (different error mechanism)

---

## ABI Versioning

This ABI is version 1.0. It applies to all code until explicitly revised.

Any change to this ABI requires:
1. Update this document with new version number
2. Update CHANGELOG.md
3. Audit every existing function for compliance
4. Full test suite pass before merging

**ABI version history:**

| Version | Date | Change |
|---|---|---|
| 1.0 | initial | established |

---

## Updated Quick Reference Card

```
┌────────────────────────────────────────────────────────────────┐
│                    utasm Internal ABI v1.0                     │
├─────────────────────┬──────────────────────────────────────────┤
│ Arg 1–6             │ RDI RSI RDX RCX R8 R9                   │
│ Arg 7+              │ stack right-to-left, caller cleans       │
│ Return primary      │ RAX                                      │
│ Return secondary    │ RDX                                      │
│ Return struct >16B  │ hidden ptr in RDI, args shift +1        │
│ Scratch registers   │ RAX RCX RDX RSI RDI R8–R11              │
│ Preserved registers │ RBX RBP R12–R15                         │
│ Stack alignment     │ 16-byte at CALL — odd pushes need pad   │
│ Red zone            │ NOT used — ever                          │
│ SIMD registers      │ all scratch — none preserved             │
│ VZEROUPPER          │ required before calling non-SIMD code   │
│ RFLAGS              │ not preserved across calls               │
│ DF flag             │ always 0 — clear after STD immediately  │
│ FS/GS base          │ reserved — do not touch                  │
│ x87 stack           │ empty at entry and exit                  │
│ String convention   │ ptr first, length second — always       │
│ Buffer convention   │ input first, output second — always     │
│ Null pointer        │ 0 — document if accepted                 │
│ Error return        │ RAX = 0 (ok) or error code (non-zero)   │
│ Syscalls            │ via host/syscall.s wrappers only        │
│ Function pointers   │ call through register, not memory       │
│ Varargs             │ not supported — use ptr+count           │
│ Global writes       │ only by owning module                    │
│ Tail calls          │ JMP when last action is a call          │
│ Stack probe         │ required for allocations > 4096 bytes   │
│ Leaf functions      │ no prologue needed if no calls made     │
└─────────────────────┴──────────────────────────────────────────┘
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
