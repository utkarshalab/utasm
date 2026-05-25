# utasm — Development Workflow

> Complete build path from restructure to public launch.
> Every phase, every file, every task, every gate.
> Nothing skipped. Nothing assumed.

---

## The Law

```
A file is COMPLETE when ALL of these are true:
├── Code written and assembles cleanly
├── All its unit tests pass
├── All its error codes documented in docs/errors.md
├── CHANGELOG.md updated
└── Committed with a meaningful message

NOT complete until all five. No exceptions. No shortcuts.
Never move to the next file with a failing test.
Never end a day with uncommitted work.
```

---

## Completion Checklist (per file)

Copy this into every commit message until it becomes muscle memory:

```
[ ] Code written
[ ] Assembles cleanly with NASM (bootstrap phase)
[ ] Unit tests written
[ ] Unit tests passing
[ ] Error codes documented
[ ] CHANGELOG entry added
[ ] Committed
```

---

## Version Map

```
v0.0.1   →  Restructure complete — existing code in new layout, builds clean
v0.1.0   →  Self-hosting achieved — utasm assembles itself, gen1 == gen2
v0.2.0   →  AArch64 + RISC-V complete — all three architectures working
v0.3.0   →  DWARF + Optimizer complete
v0.4.0   →  Self-patching engine complete
v0.5.0   →  Built-in tools complete
v1.0.0   →  All tests passing — public launch
```

---

## Branch Strategy

```
main          →  always stable, always passes all tests
dev           →  active development, daily work happens here
phase/NNN     →  one branch per phase, merged to dev on completion
fix/reg_NNN   →  regression fixes, merged immediately
```

---

# PHASE 0 — Restructure
**Target: v0.0.1**

Goal: existing code moved into new structure, nothing broken, bootstrap works.

---

### Step 0.1 — Create folder skeleton

Create every folder from README.md before moving any file:

```sh
mkdir -p build/{gen0,gen1,gen2}
mkdir -p docs
mkdir -p include/arch
mkdir -p core
mkdir -p frontend/{lexer/number,parser/operand,macro/cond}
mkdir -p middle/{semantic,symtable,expr}
mkdir -p backend/encoder/{x86,simd/avx512,aarch64,riscv64,prefix,tables}
mkdir -p backend/{isa,linker/reloc,output/{elf,pe,flat,upk,listing}}
mkdir -p error/{format,recover}
mkdir -p cpu/profiles
mkdir -p debug
mkdir -p optimizer
mkdir -p selfpatch
mkdir -p profiler
mkdir -p tools/{disasm,inspector,symdump}
mkdir -p io
mkdir -p lib
mkdir -p host
mkdir -p scripts
mkdir -p tests/{unit/{lexer,parser,macro,symtable,expr,encoder/{x86,simd,aarch64,riscv64},linker,output},error/{E1xx,E2xx,E3xx,E4xx,E5xx,E6xx,E7xx,E9xx,multi},warning,integration/{hello,selfhost,elf,pe,boot,upk,simd,multifile,crossarch,selfpatch},regression,fuzz/seeds,fuzz/corpus,perf/results,stress,fixtures/{inc,obj,expect}}
```

---

### Step 0.2 — Rename all files

```sh
# rename .asm → .s throughout
find . -name "*.asm" | while read f; do
    mv "$f" "${f%.asm}.s"
done
```

---

### Step 0.3 — Move existing files into new structure

Map every existing file from old location to new location per README.md. Do not rewrite. Just move.

---

### Step 0.4 — Verify bootstrap still works

```sh
bash scripts/bootstrap.sh
```

If it fails — fix the include paths and macro references broken by the move. Do not write new code. Fix only what the move broke.

---

### Step 0.5 — Update .gitignore

```
build/
*.o
*.patch.log
*.map
*.lst
tests/fuzz/corpus/
tests/perf/results/*.tsv
```

---

### Step 0.6 — Tag v0.0.1

```sh
git add -A
git commit -m "restructure: align to new project layout v0.0.1"
git tag v0.0.1
```

Gate: bootstrap.sh produces a working binary before tagging.

---

# PHASE 1 — Error Engine
**Depends on: Phase 0**
**Unlocks: everything else**

The error engine has zero dependencies on any other utasm module. Every other module depends on it. Build it completely before touching anything else.

Goal: a single 3-argument call `error_report(code, token, hint)` produces a complete Rust-style error with file, line, col, source line, underline, note, and hint.

---

### Step 1.1 — Define all structs in core/types.inc

This is the single most important file. Everything depends on it.

**Token struc — source map fields are mandatory:**
```asm
struc Token
    .type     dw 0    ; token type enum
    .flags    dw 0    ; token flags
    .value    dq 0    ; numeric value or string ptr
    .file_id  dw 0    ; index into file registry
    .line     dd 0    ; 1-based line number
    .col_start dw 0   ; 1-based column start
    .col_end  dw 0    ; 1-based column end
    .macro_id dw 0    ; 0 = not from macro, else macro chain id
    .length   dw 0    ; token text length
    .text_ptr dq 0    ; pointer to token text in source buffer
endstruc
```

**Error record struc:**
```asm
struc ErrorRecord
    .code     dw 0    ; E101–E999 / W101–W999
    .severity db 0    ; 0=error 1=warning 2=note 3=hint
    .file_id  dw 0    ; source file
    .line     dd 0    ; line number
    .col_start dw 0   ; column start
    .col_end  dw 0    ; column end
    .msg_idx  dw 0    ; index into message table
    .note_idx dw 0    ; 0 = no note
    .hint_idx dw 0    ; 0 = no hint
    .chain_id dw 0    ; macro expansion chain id, 0 = none
endstruc
```

Tests to write after: none yet — this is just data definitions.
Gate: file assembles cleanly with NASM.

---

### Step 1.2 — error/table.s

All error code constants and message strings. Static data only. No code.

```asm
; error code constants
E101  equ 101   ; invalid character in source
E102  equ 102   ; unterminated string literal
; ... all codes through E30xx

; message string table
; indexed by (code - 100) for E1xx etc
err_msg_table:
    dq .msg_E101
    dq .msg_E102
    ; ...

.msg_E101: db "invalid character in source", 0
.msg_E102: db "unterminated string literal", 0
; ...
```

Document every code in docs/errors.md as you add it.
Gate: file assembles. Every E1xx–E30xx code defined. Every message non-empty.

---

### Step 1.3 — error/warnings.s

Same pattern as table.s but for W1xx–W20xx.
Gate: every warning code defined.

---

### Step 1.4 — error/hints.s

H1xx–H5xx hint codes and messages.
Gate: every hint code defined.

---

### Step 1.5 — error/notes.s

N1xx–N5xx note codes and messages.
Gate: every note code defined.

---

### Step 1.6 — lib/arena.s

Error records are allocated from an arena. Build this first because error/record.s needs it.

```asm
; arena_init(ptr, size)  → initializes arena at ptr with given size
; arena_alloc(size)      → returns ptr to allocation, 0 on failure
; arena_reset()          → resets arena (keep buffer)
```

Tests: tests/unit/ — not yet, we don't have a test runner. Write tests after test runner exists (Phase 10).
Gate: three functions work correctly, manually verified.

---

### Step 1.7 — lib/string.s

Error formatting needs these:

```asm
; str_len(ptr)           → length of null-terminated string
; str_copy(dst, src)     → copy string
; str_cmp(a, b)          → compare strings, returns 0 if equal
; str_find(haystack, ch) → find character, returns ptr or 0
; str_append(dst, src)   → append src to dst
```

Gate: all five functions work correctly.

---

### Step 1.8 — lib/fmt.s

Error formatting needs integer → string conversion:

```asm
; fmt_u64(val, buf)      → format uint64 as decimal string
; fmt_x64(val, buf)      → format uint64 as hex string
; fmt_pad(buf, width)    → right-pad with spaces to width
```

Gate: all three functions work correctly.

---

### Step 1.9 — lib/sort.s

Final error output sorted by file then line:

```asm
; sort_errors(records, count)  → sort ErrorRecord array by file_id, then line
```

Gate: function works correctly on array of 1, 2, N records.

---

### Step 1.10 — error/record.s

Allocate and store error records:

```asm
; error_record_init()         → initialize record storage
; error_record_alloc()        → allocate one ErrorRecord, return ptr
; error_record_store(ptr)     → store filled ErrorRecord
; error_record_count()        → return number of stored errors
; error_record_get(idx)       → return ptr to record by index
```

Gate: can store 1000 error records and retrieve them in order.

---

### Step 1.11 — error/count.s

```asm
; count_error()        → increment error counter
; count_warning()      → increment warning counter
; count_get_errors()   → return error count
; count_get_warnings() → return warning count
; count_has_errors()   → return 1 if any errors
; count_reset()        → reset all counters
```

Gate: all counters work correctly.

---

### Step 1.12 — error/dedup.s

Prevent same error at same location from appearing twice:

```asm
; dedup_check(file_id, line, col, code) → 1 if already seen, 0 if new
; dedup_register(file_id, line, col, code) → mark as seen
; dedup_reset()                           → clear dedup table
```

Gate: same error twice → dedup_check returns 1 second time.

---

### Step 1.13 — error/filter.s

Warning suppression via -W flags:

```asm
; filter_suppress(code)       → mark warning code as suppressed
; filter_promote(code)        → mark warning as error (-Werror)
; filter_promote_all()        → all warnings become errors
; filter_is_suppressed(code)  → return 1 if suppressed
; filter_is_promoted(code)    → return 1 if promoted to error
```

Gate: suppress W201, then filter_is_suppressed(W201) returns 1.

---

### Step 1.14 — error/format/ — all six files

These produce the visual output. Build in this exact order:

**format/header.s** — "error[E501]: operand size mismatch"
```asm
; fmt_header(severity, code, msg_ptr, out_buf)
; writes: "error[E501]: operand size mismatch\n"
```

**format/location.s** — "  --> file.s:247:14"
```asm
; fmt_location(file_id, line, col, out_buf)
; writes: "  --> filename.s:247:14\n"
; needs: file registry to map file_id → filename
```

**format/source.s** — the source line with line numbers
```asm
; fmt_source(file_id, line, out_buf)
; writes: "247|     mov al, rax\n"
; needs: source buffer access
```

**format/underline.s** — the ^^^ marker
```asm
; fmt_underline(col_start, col_end, out_buf)
; writes: "   |     ^^  ^^^\n"
```

**format/note.s** — "= note: al is the low byte of rax"
```asm
; fmt_note(note_idx, out_buf)
; writes: "   = note: al is the low byte of rax (bits 7:0)\n"
```

**format/hint.s** — "= hint[H201]: did you mean 'movzx rax, al'?"
```asm
; fmt_hint(hint_idx, out_buf)
; writes: "   = hint[H201]: did you mean 'movzx rax, al'?\n"
```

**format/format.s** — coordinator, calls all six in order:
```asm
; fmt_error(record_ptr, source_buf, out_buf)
; calls all six formatters in sequence
; produces complete error block
```

Gate: calling fmt_error() on a hand-crafted ErrorRecord produces exactly the expected multiline output verified byte-by-byte.

---

### Step 1.15 — error/chain.s

Macro expansion chain display — "→ expanded from macro X at file.inc:17":

```asm
; chain_push(macro_name_ptr, file_id, line) → push expansion frame
; chain_pop()                                → pop frame
; chain_format(chain_id, out_buf)            → format full chain
; chain_reset()                              → clear all chains
```

Gate: three-level macro expansion chain formats correctly.

---

### Step 1.16 — error/recover/ — four files

Recovery logic — how each stage skips to a known-safe state after an error. These are stubs now, filled properly when each stage is built.

**recover/lexer.s** — skip to next newline
**recover/parser.s** — skip to next instruction boundary
**recover/macro.s** — skip to %endmacro or next top-level token
**recover/encoder.s** — skip to next instruction

Each stub:
```asm
; recover_lexer(state_ptr) → advance lexer to next safe position
```

Gate: each stub assembles. Real logic added during its respective phase.

---

### Step 1.17 — error/report.s

The single entry point every other module calls:

```asm
; error_report(code, token_ptr, hint_code)
;
; This is the ONLY function other modules call.
; Everything else in error/ is internal.
;
; Internally:
;   1. check dedup — if already seen, return
;   2. check filter — if suppressed, return
;   3. check promote — if promoted, treat as error
;   4. allocate ErrorRecord
;   5. fill record from token source map
;   6. store record
;   7. increment counter
;   8. if error count > MAX_ERRORS, flush and abort
```

Gate: calling error_report(E501, token, H201) stores exactly one record with correct fields.

---

### Step 1.18 — error/flush.s

Print all accumulated errors at end of pass:

```asm
; flush_errors()
;   1. sort records by file_id, then line
;   2. deduplicate
;   3. for each record: call fmt_error()
;   4. write to stderr
;   5. print summary: "N error(s), M warning(s)"
;   6. return total error count
```

Gate: flush_errors() on 5 hand-crafted records produces sorted, formatted, deduplicated output.

---

### Step 1.19 — error/suggest.s and error/attach.s

```asm
; suggest_hint(record_ptr, hint_code) → attach hint to record
; attach_note(record_ptr, note_code)  → attach note to record
```

Gate: hint and note appear in fmt_error() output when attached.

---

### Step 1.20 — error/error.s — main entry point

Ties everything together:

```asm
; error_init()    → initialize all error subsystems
; error_reset()   → reset for new file
; error_shutdown()→ final flush, return error count
```

Gate: error_init → several error_report calls → error_shutdown produces correct output.

---

### Phase 1 Gate — Full error engine test

Write this test by hand, assemble with NASM, run it:

```asm
; hand-crafted integration test
; creates a fake token at file "test.s" line 42 col 8
; calls error_report(E501, &fake_token, H201)
; calls error_shutdown()
; expected output written to expect/error_engine.txt
; diff actual vs expected — must be identical
```

If this passes, Phase 1 is complete.

```sh
git commit -m "feat(error): complete error engine — all E/W/N/H codes, full formatting"
```

---

# PHASE 2 — Library Foundation
**Depends on: Phase 1**

Complete the lib/ modules needed by later phases.

---

### Step 2.1 — lib/hash.s

FNV-1a hash for symbol table:

```asm
; hash_fnv1a_32(ptr, len) → 32-bit hash
; hash_fnv1a_64(ptr, len) → 64-bit hash
```

Gate: hash("hello") == known FNV-1a value.

---

### Step 2.2 — lib/math.s

```asm
; math_pow2_ceil(n)    → next power of 2 ≥ n
; math_is_pow2(n)      → 1 if n is power of 2
; math_log2(n)         → floor(log2(n))
; math_clamp(v, lo, hi)→ clamp value to range
; math_align(v, align) → align v up to alignment boundary
```

Gate: all functions produce correct results for known inputs.

---

### Step 2.3 — lib/list.s

Intrusive linked list:

```asm
; list_init(head_ptr)           → initialize list head
; list_append(head_ptr, node)   → append node
; list_prepend(head_ptr, node)  → prepend node
; list_remove(head_ptr, node)   → remove node
; list_next(node)               → return next node or 0
; list_empty(head_ptr)          → 1 if empty
```

Gate: append 5 nodes, traverse all 5 in order.

---

### Step 2.4 — lib/vec.s

Dynamic array (grows as needed):

```asm
; vec_init(vec_ptr, elem_size, initial_cap)
; vec_push(vec_ptr, elem_ptr)   → append element
; vec_get(vec_ptr, idx)         → return ptr to element at idx
; vec_len(vec_ptr)              → element count
; vec_clear(vec_ptr)            → reset length to 0
```

Gate: push 1000 elements, get all 1000 back correctly.

---

### Step 2.5 — host/syscall.s

Raw syscall ABI — the only place in utasm that touches the OS:

```asm
; sys_write(fd, buf, len)       → write to file descriptor
; sys_read(fd, buf, len)        → read from file descriptor
; sys_open(path, flags, mode)   → open file, return fd
; sys_close(fd)                 → close file descriptor
; sys_exit(code)                → terminate process
; sys_mmap(addr, len, prot, flags, fd, off) → memory map
; sys_munmap(addr, len)         → unmap memory
; sys_lseek(fd, offset, whence) → seek in file
; sys_fstat(fd, stat_ptr)       → get file info
```

Gate: sys_write(1, "hello\n", 6) writes to stdout. sys_open + sys_read reads a file.

---

### Step 2.6 — io/mem.s

```asm
; mem_alloc(size)    → mmap anonymous page(s), return ptr
; mem_free(ptr, size)→ munmap
; mem_copy(dst, src, len) → copy bytes
; mem_zero(ptr, len) → zero memory
; mem_cmp(a, b, len) → compare memory blocks
```

Gate: allocate 4096 bytes, write pattern, read back correctly, free.

---

### Step 2.7 — io/file.s

```asm
; file_open(path, flags)   → return fd or error
; file_close(fd)
; file_read(fd, buf, len)  → return bytes read
; file_write(fd, buf, len) → return bytes written
; file_size(fd)            → return file size in bytes
; file_mmap(fd)            → return ptr to memory-mapped file
; file_munmap(ptr, size)
```

Gate: open utasm.s, read first 64 bytes, close.

---

### Step 2.8 — io/buf.s

Buffered output (for error messages, listings):

```asm
; buf_init(buf_ptr, size)
; buf_write(buf_ptr, data, len)
; buf_write_str(buf_ptr, str_ptr)
; buf_write_char(buf_ptr, ch)
; buf_flush(buf_ptr, fd)
; buf_reset(buf_ptr)
```

Gate: buf_write_str 100 times, buf_flush writes all to stdout correctly.

---

### Step 2.9 — io/stdout.s and io/stderr.s

```asm
; stdout_write(buf, len)
; stdout_write_str(ptr)
; stderr_write(buf, len)
; stderr_write_str(ptr)
```

Gate: both write to correct file descriptors.

---

### Phase 2 Gate

```sh
git commit -m "feat(lib): complete library foundation — all lib/ and io/ modules"
```

---

# PHASE 3 — Lexer
**Depends on: Phase 1, Phase 2**

Every lexer error fires through error_report() with exact file/line/col.

---

### Step 3.1 — core/config.inc

Global constants needed by lexer:

```asm
MAX_TOKEN_LEN   equ 4096
MAX_INCLUDE_DEPTH equ 64
MAX_MACRO_DEPTH equ 999
MAX_ERRORS      equ 100
TAB_WIDTH       equ 8
```

Gate: file includes cleanly.

---

### Step 3.2 — core/globals.s

Global state variables:

```asm
; current_file_id   dw 0      ; currently assembling file
; current_line      dd 0      ; current line number
; current_col       dw 0      ; current column
; error_count       dd 0      ; total errors
; warning_count     dd 0      ; total warnings
; pass_number       db 0      ; 1 or 2
```

Gate: file assembles cleanly.

---

### Step 3.3 — core/asmctx.s

Assembler context — tracks state across the whole assembly:

```asm
; ctx_init()                → initialize assembler context
; ctx_set_file(path)        → register new source file, return file_id
; ctx_get_filename(file_id) → return filename ptr for file_id
; ctx_push_include(file_id) → push include stack
; ctx_pop_include()         → pop include stack
; ctx_current_file()        → return current file_id
```

Gate: register 3 files, retrieve all 3 filenames correctly.

---

### Step 3.4 — frontend/lexer/chars.s

Character classification lookup table — the foundation of the lexer:

```asm
; char_class table: 256 bytes, one per ASCII value
; each byte is a bitmask:
;   bit 0: ALPHA (a-z A-Z _)
;   bit 1: DIGIT (0-9)
;   bit 2: HEX   (0-9 a-f A-F)
;   bit 3: SPACE (space tab)
;   bit 4: NEWLINE (\n \r)
;   bit 5: PUNCT  (, + - * / [ ] etc)
;   bit 6: QUOTE  (' ")
;   bit 7: SPECIAL (% ; # @)

; char_is_alpha(ch)   → nonzero if alpha
; char_is_digit(ch)   → nonzero if digit
; char_is_hex(ch)     → nonzero if hex digit
; char_is_space(ch)   → nonzero if whitespace
; char_is_newline(ch) → nonzero if newline
; char_is_ident(ch)   → nonzero if valid in identifier (alpha or digit)
; char_is_ident_start(ch) → nonzero if valid identifier start (alpha only)
; char_to_lower(ch)   → lowercase version of ch
; char_hex_val(ch)    → numeric value of hex digit (0-15)
```

Tests: tests/unit/lexer/ — these are data tables, verify every byte of the 256-entry table.
Gate: char_is_alpha('a') = 1, char_is_alpha('1') = 0, all 256 entries correct.

---

### Step 3.5 — frontend/lexer/utf8.s

```asm
; utf8_validate(ptr, len)     → 1 if valid UTF-8, 0 if not
; utf8_next_char(ptr)         → advance ptr past one codepoint
; utf8_codepoint(ptr)         → return codepoint value at ptr
; utf8_byte_count(ptr)        → bytes in current codepoint (1-4)
```

Error fired here: E115 (invalid UTF-8 sequence)
Gate: validates ASCII, 2/3/4-byte sequences, rejects invalid sequences.

---

### Step 3.6 — frontend/lexer/buffer.s

Token buffer — stores all tokens for a source file:

```asm
; tokbuf_init(capacity)        → initialize buffer
; tokbuf_push(token_ptr)       → add token to buffer
; tokbuf_get(idx)              → return ptr to token at idx
; tokbuf_count()               → return token count
; tokbuf_reset()               → clear buffer (keep allocation)
; tokbuf_current()             → return ptr to most recent token
```

Gate: push 10000 tokens, retrieve all 10000 in order.

---

### Step 3.7 — frontend/lexer/number/dec.s

Decimal integer parsing:

```asm
; lex_num_dec(src_ptr, token_ptr) → fill token with decimal value
; fires E108 (malformed decimal)
; fires E109 (integer overflow — value > 2^64-1)
```

Tests: tests/unit/lexer/num_dec.s — 0, 1, 255, 65535, 2^64-1, 2^64 (overflow)
Gate: all unit tests pass. E108 fires on "123abc". E109 fires on number > UINT64_MAX.

---

### Step 3.8 — frontend/lexer/number/hex.s

```asm
; lex_num_hex(src_ptr, token_ptr)
; handles: 0x1A2B, 0h1A2B, $1A2B
; fires E107, E109
```

Tests: tests/unit/lexer/num_hex.s
Gate: all valid forms parse. E107 fires on "0x". E109 fires on overflow.

---

### Step 3.9 — frontend/lexer/number/bin.s

```asm
; lex_num_bin(src_ptr, token_ptr)
; handles: 0b1010, 0y1010
; fires E105, E109
```

Tests: tests/unit/lexer/num_bin.s
Gate: all valid forms parse. E105 fires on "0b". E109 fires on overflow.

---

### Step 3.10 — frontend/lexer/number/oct.s

```asm
; lex_num_oct(src_ptr, token_ptr)
; handles: 0o777, 0q777
; fires E106, E109
```

Tests: tests/unit/lexer/num_oct.s
Gate: all valid forms parse. E106 fires on "0o". E109 fires on overflow.

---

### Step 3.11 — frontend/lexer/number/number.s

Coordinator — detects prefix and dispatches to correct sub-scanner:

```asm
; lex_number(src_ptr, token_ptr)
; detects 0x/0h/$  → hex
; detects 0b/0y    → binary
; detects 0o/0q    → octal
; else             → decimal
```

Gate: all four sub-scanners called correctly based on prefix.

---

### Step 3.12 — frontend/lexer/string.s

```asm
; lex_string(src_ptr, token_ptr)
; handles single-quoted and double-quoted strings
; handles escape sequences: \n \t \r \\ \' \" \xHH \uHHHH
; fires E102 (unterminated string)
; fires E103 (unterminated char)
; fires E104 (invalid escape sequence)
```

Tests: tests/unit/lexer/string.s, string_esc.s, char.s
Gate: all escape sequences parse. E102 fires on EOF in string. E104 fires on unknown escape.

---

### Step 3.13 — frontend/lexer/comment.s

```asm
; lex_comment_line(src_ptr) → skip to end of line (semicolon comments)
; lex_comment_block(src_ptr)→ skip /* ... */ block
; fires E113 (EOF in block comment)
; fires E114 (nested block comment too deep)
```

Tests: tests/unit/lexer/comment_line.s, comment_block.s
Gate: line comments skip correctly. Block comments handle nested. E113 fires on unterminated.

---

### Step 3.14 — frontend/lexer/ident.s

Identifier and keyword scanning:

```asm
; lex_ident(src_ptr, token_ptr)
; scans alphanumeric + underscore sequence
; looks up result in keyword table
; if keyword: set token type to keyword type
; else: set token type to T_IDENT
; fires E111 (invalid identifier character — shouldn't happen, but guard)
; fires E112 (identifier too long > MAX_TOKEN_LEN)
```

Keyword table must include all x86-64 mnemonics, directives, register names, and utasm directives.

Tests: tests/unit/lexer/ident.s, keywords.s
Gate: all register names classified correctly. All mnemonics classified correctly.

---

### Step 3.15 — frontend/lexer/token.s

Token creation with source map attachment:

```asm
; token_create(type, file_id, line, col_start, col_end) → fills Token struc
; token_copy(dst, src)    → copy token
; token_is_type(tok, type)→ 1 if token is given type
; token_text(tok)         → return pointer to token text
```

Gate: created token has all fields correctly set including source map.

---

### Step 3.16 — frontend/lexer/lexer.s

Main lexer entry point — the state machine:

```asm
; lex_init(source_buf, source_len, file_id) → initialize lexer
; lex_next(token_ptr) → fill token_ptr with next token, return 1 or 0 at EOF
; lex_peek(token_ptr) → fill without advancing
; lex_reset()         → reset lexer state
```

State machine:
```
skip whitespace + newlines
    ↓
look at current char
    ↓
  ';'   → comment_line, then restart
  '/'   → if '/*': comment_block, then restart
  '"'   → string
  '\''  → char literal
  '%'   → preprocessor token
  digit → number (detect base)
  alpha or '_' → ident or keyword
  punct → single-char or two-char token
  0     → EOF token
  else  → E101 invalid character, recover_lexer, restart
```

Tests: tests/unit/lexer/sourcemap.s, whitespace.s, newline.s, empty.s
Gate: lex_next() on "mov rax, 42" produces exactly: T_IDENT("mov"), T_REG(rax), T_COMMA, T_INT(42), T_EOF — each with correct file/line/col.

---

### Phase 3 Gate

```sh
bash scripts/test.sh unit/lexer
# all 17 unit tests pass

bash scripts/test.sh error/E1xx
# all 15 E1xx error tests pass
```

```sh
git commit -m "feat(lexer): complete lexer — all token types, source maps, E1xx errors"
```

---

# PHASE 4 — Expression Evaluator
**Depends on: Phase 1, Phase 2, Phase 3**

Build standalone before parser — parser needs it for address expressions.

---

### Step 4.1 — middle/expr/arith.s

```asm
; expr_add(a, b)  → a + b, fires E902 on overflow
; expr_sub(a, b)  → a - b
; expr_mul(a, b)  → a * b, fires E902 on overflow
; expr_div(a, b)  → a / b, fires E901 on b=0
; expr_mod(a, b)  → a % b, fires E901 on b=0
; expr_neg(a)     → -a
```

Tests: tests/unit/expr/add.s through mod.s, divzero.s, overflow.s
Gate: all arithmetic correct. E901 fires on div-by-zero. E902 fires on overflow.

---

### Step 4.2 — middle/expr/bitwise.s

```asm
; expr_and(a, b)  → a & b
; expr_or(a, b)   → a | b
; expr_xor(a, b)  → a ^ b
; expr_not(a)     → ~a
; expr_shl(a, b)  → a << b
; expr_shr(a, b)  → a >> b (logical)
```

Tests: tests/unit/expr/and.s through shr.s
Gate: all bitwise operations correct.

---

### Step 4.3 — middle/expr/compare.s and logical.s

```asm
; expr_eq(a, b)   → a == b → 0 or 1
; expr_ne(a, b)   → a != b
; expr_lt(a, b)   → a <  b
; expr_gt(a, b)   → a >  b
; expr_le(a, b)   → a <= b
; expr_ge(a, b)   → a >= b
; expr_land(a, b) → a && b
; expr_lor(a, b)  → a || b
; expr_lnot(a)    → !a
```

Gate: all return 0 or 1 correctly.

---

### Step 4.4 — middle/expr/const.s

Constant folding — evaluate at assembly time:

```asm
; expr_fold(node_ptr) → evaluate constant expression tree, return value
; fires E903 if expression is not constant where constant required
```

Gate: (2 + 3) * 4 folds to 20 at assembly time.

---

### Step 4.5 — middle/expr/overflow.s

```asm
; overflow_add(a, b, result_ptr) → 1 if overflow
; overflow_mul(a, b, result_ptr) → 1 if overflow
; overflow_neg(a)                → 1 if overflow (INT64_MIN)
```

Gate: UINT64_MAX + 1 overflows. INT64_MIN negated overflows.

---

### Step 4.6 — middle/expr/reloc.s

Relocatable expression tracking — for addresses not known until link time:

```asm
; reloc_expr_init()
; reloc_expr_add_sym(sym_ptr, scale) → add symbol reference
; reloc_expr_add_const(val)          → add constant
; reloc_expr_is_const()              → 1 if fully constant
; reloc_expr_value()                 → value if constant
; reloc_expr_emit(reloc_buf)         → emit relocation record
```

Gate: symbol + constant creates relocatable expression correctly.

---

### Step 4.7 — middle/expr/unary.s

```asm
; expr_unary_plus(a)   → +a (identity)
; expr_unary_minus(a)  → -a
; expr_unary_not(a)    → !a
; expr_unary_bitnot(a) → ~a
```

Gate: all four correct.

---

### Step 4.8 — middle/expr/expr.s

Pratt parser for expressions — entry point:

```asm
; expr_parse(token_stream, result_ptr) → parse expression from tokens
; expr_parse_const(token_stream)       → parse, require constant, return value
```

Operator precedence table (highest to lowest):
```
unary +, -, !, ~
*, /, %
+, -
<<, >>
&
^
|
==, !=, <, >, <=, >=
&&
||
```

Tests: tests/unit/expr/prec.s, paren.s, symref.s, reloc.s, const_fold.s
Gate: 2+3*4 = 14. (2+3)*4 = 20. Precedence table fully correct.

---

### Phase 4 Gate

```sh
bash scripts/test.sh unit/expr
# all 19 unit tests pass

bash scripts/test.sh error/E9xx
# all 3 E9xx error tests pass
```

```sh
git commit -m "feat(expr): complete expression evaluator — all ops, constant folding, reloc"
```

---

# PHASE 5 — Parser
**Depends on: Phase 1, Phase 2, Phase 3, Phase 4**

---

### Step 5.1 — frontend/parser/ast.s

AST node allocation and types:

```asm
; AST node types
AST_INSTR    equ 1   ; instruction with operands
AST_LABEL    equ 2   ; label definition
AST_DIRECTIVE equ 3  ; assembler directive
AST_DATA     equ 4   ; DB/DW/DD/DQ
AST_SECTION  equ 5   ; section change
AST_EXPR     equ 6   ; expression node

struc ASTNode
    .type      db 0
    .flags     db 0
    .line      dd 0
    .file_id   dw 0
    .operand_count db 0
    .operands  dq 0  ; ptr to operand array
    .next      dq 0  ; next node in list
endstruc

; ast_alloc(type)       → allocate node, return ptr
; ast_append(list, node)→ append to node list
; ast_reset()           → free all nodes (reset arena)
```

Gate: allocate 10000 nodes, all fields accessible.

---

### Step 5.2 — frontend/parser/label.s

```asm
; parse_label(token_stream, ast_node_ptr)
; handles: name:, .local:, @@:
; fires E206 (expected label)
; fires E402 (label redefinition — deferred to semantic phase)
```

Tests: tests/unit/parser/label.s, local_label.s
Gate: "my_label:" and ".loop:" both parse to correct AST nodes.

---

### Step 5.3 — frontend/parser/section.s

```asm
; parse_section(token_stream, ast_node_ptr)
; handles: section .text, section .data exec, segment CODE
; fires E408 (invalid section name)
```

Tests: tests/unit/parser/section.s
Gate: section .text, .data, .bss, custom sections all parse.

---

### Step 5.4 — frontend/parser/directive.s

```asm
; parse_directive(token_stream, ast_node_ptr)
; handles: GLOBAL, EXTERN, COMMON, BITS, CPU, ORG, ALIGN, TIMES, EQU
; fires E10xx directive errors
```

Tests: tests/unit/parser/global.s, extern.s, common.s, align.s, times.s, equ.s
Gate: all directives produce correct AST nodes. ALIGN with non-power-of-2 fires E417.

---

### Step 5.5 — frontend/parser/data.s

```asm
; parse_data(token_stream, ast_node_ptr)
; handles: DB, DW, DD, DQ, DT, DO, DY, DZ
; handles: string initializers, dup, expressions
; fires E20xx data errors
```

Tests: tests/unit/parser/data_db.s through data_dup.s, data_str.s
Gate: DB "hello", 0 parses to correct byte list. TIMES 16 DB 0 correct.

---

### Step 5.6 — frontend/parser/struct.s and proc.s

```asm
; parse_struct(token_stream) → STRUC/ENDSTRUC → fills type table
; parse_proc(token_stream)   → PROC/ENDPROC → sets scope boundary
```

Tests: tests/unit/parser/struct.s, proc.s
Gate: STRUC with fields parses. ENDSTRUC without STRUC fires error.

---

### Step 5.7 — frontend/parser/operand/reg.s

Register name → encoding table lookup:

```asm
; parse_reg(token_ptr, operand_ptr)
; recognizes all x86-64 registers:
;   8-bit:  AL AH BL BH CL CH DL DH SPL BPL SIL DIL R8B–R15B
;   16-bit: AX BX CX DX SP BP SI DI R8W–R15W
;   32-bit: EAX EBX ECX EDX ESP EBP ESI EDI R8D–R15D
;   64-bit: RAX RBX RCX RDX RSP RBP RSI RDI R8–R15
;   SIMD:   XMM0–XMM31, YMM0–YMM31, ZMM0–ZMM31
;   Mask:   K0–K7
;   Segment: CS DS ES FS GS SS
;   Control: CR0–CR15
;   Debug:   DR0–DR7
;   x87:    ST(0)–ST(7)
; fires E203 (expected register) if not recognized
```

Tests: tests/unit/parser/reg.s, reg_8bit.s, reg_16bit.s, reg_32bit.s, reg_64bit.s, reg_simd.s
Gate: every register name recognized. "RAX" → reg_id=0, size=64. "ZMM31" → reg_id=31, size=512.

---

### Step 5.8 — frontend/parser/operand/imm.s

```asm
; parse_imm(token_stream, operand_ptr)
; handles: integer literals, expressions, labels
; fires E204 (expected immediate)
```

Tests: tests/unit/parser/imm.s
Gate: immediate values and expressions parse correctly.

---

### Step 5.9 — frontend/parser/operand/mem.s

Memory operand parsing — the most complex operand type:

```asm
; parse_mem(token_stream, operand_ptr)
; handles all addressing modes:
;   [base]
;   [base + disp]
;   [base + index]
;   [base + index*scale]
;   [base + index*scale + disp]
;   [disp]
;   [rel label]        ; RIP-relative
; handles size overrides: BYTE PTR, WORD PTR, DWORD PTR, QWORD PTR
; fires E212 (invalid addressing mode)
; fires E213 (base not 64-bit)
; fires E214 (RSP as index)
; fires E215 (invalid scale — not 1/2/4/8)
```

Tests: tests/unit/parser/mem.s, mem_sib.s, mem_disp8.s, mem_disp32.s, mem_riprel.s
Gate: all addressing modes parse. RSP as index fires E214.

---

### Step 5.10 — frontend/parser/operand/addr.s

Addressing mode resolution — determines ModRM + SIB encoding needed:

```asm
; addr_resolve(mem_operand_ptr, modrm_ptr, sib_ptr, disp_ptr)
; determines: mod, reg, rm, sib, displacement size
```

Gate: [RAX + RCX*4 + 16] → mod=01 rm=100 sib=(scale=2,idx=1,base=0) disp8=16.

---

### Step 5.11 — frontend/parser/operand/operand.s

Coordinator:

```asm
; parse_operand(token_stream, operand_ptr)
; tries: register, then memory, then immediate
; handles: size overrides, segment overrides
; fires E202 (expected operand)
; fires E225 (invalid size override)
```

Gate: "QWORD PTR [RAX]" → memory operand, size=64.

---

### Step 5.12 — frontend/parser/instr.s

Instruction statement parser:

```asm
; parse_instr(token_stream, ast_node_ptr)
; reads: mnemonic token
; reads: 0-4 operands separated by commas
; fires E201 (unexpected token)
; fires E210 (too many operands)
; fires E211 (too few operands)
```

Tests: tests/unit/parser/instr.s, operand.s
Gate: "MOV RAX, [RBX + 8]" → AST_INSTR with mnemonic=MOV, 2 operands.

---

### Step 5.13 — frontend/parser/expr.s

Expression statement parser (Pratt parser wrapper):

```asm
; parse_expr_stmt(token_stream, ast_node_ptr)
; wraps middle/expr/expr.s for use in parser context
```

Tests: tests/unit/parser/expr_add.s through expr_bitwise.s
Gate: expressions in data statements and EQU evaluate correctly.

---

### Step 5.14 — frontend/parser/recover.s

Real implementation now (was stub in Phase 1):

```asm
; recover_parser(token_stream)
; strategy: skip tokens until finding T_NEWLINE or T_EOF
; allows parser to continue after error
```

Gate: after E201 error, parser continues and finds next instruction.

---

### Step 5.15 — frontend/parser/parser.s

Main entry point — top-level parsing loop:

```asm
; parser_init(token_buf)  → initialize parser with token buffer
; parser_parse()          → parse all tokens, return AST list
; parser_reset()          → reset for new file
```

Loop:
```
get next token
  T_IDENT that is a mnemonic → parse_instr
  T_IDENT followed by ':'    → parse_label
  T_DIRECTIVE                → parse_directive
  T_SECTION                  → parse_section
  T_DATA (DB/DW/etc)         → parse_data
  T_STRUC                    → parse_struct
  T_PROC                     → parse_proc
  T_MACRO                    → handled by macro engine before parser
  T_EOF                      → done
  anything else              → E201, recover_parser, continue
```

Tests: tests/unit/parser/multiline.s
Gate: a 20-instruction test file produces correct AST with all nodes in order.

---

### Phase 5 Gate

```sh
bash scripts/test.sh unit/parser
# all 35 unit tests pass

bash scripts/test.sh error/E2xx
# all 16 E2xx error tests pass
```

```sh
git commit -m "feat(parser): complete parser — all statement types, operands, E2xx errors"
```

---

# PHASE 6 — Macro Engine
**Depends on: Phase 1, Phase 2, Phase 3, Phase 5**

---

### Step 6.1 — frontend/macro/table.s

Macro definition hash table:

```asm
; macro_table_init()
; macro_table_insert(name_ptr, def_ptr) → fires E302 on redefinition
; macro_table_lookup(name_ptr)          → return def_ptr or 0
; macro_table_delete(name_ptr)          → fires nothing if not found
; macro_table_exists(name_ptr)          → return 1 if defined
```

Tests: tests/unit/macro/redefine.s, undef.s
Gate: insert 1000 macros, look up all 1000. Redefinition fires E302.

---

### Step 6.2 — frontend/macro/define.s

```asm
; macro_define(token_stream)   → handle %define NAME value
; macro_macro(token_stream)    → handle %macro NAME argcount body %endmacro
; macro_imacro(token_stream)   → handle %imacro (case-insensitive)
; fires E302 on redefinition
; fires E311 on unterminated %macro
```

Tests: tests/unit/macro/define_simple.s, define_param.s
Gate: %define MAX 100 then use MAX in expression → 100.

---

### Step 6.3 — frontend/macro/args.s

Argument parsing and substitution:

```asm
; args_parse(token_stream, argc, argv_buf) → parse comma-separated args
; args_substitute(body_ptr, argc, argv)    → substitute %1 %2 etc
; args_count_required(def_ptr)             → minimum arg count
; fires E303 (wrong argc)
; fires E304 (too many args)
; fires E305 (too few args)
```

Tests: tests/unit/macro/args_basic.s, args_default.s, args_greedy.s, args_count.s
Gate: %macro ADD2 2 → body uses %1 and %2. Call with 2 args substitutes correctly.

---

### Step 6.4 — frontend/macro/local.s

Local label generation inside macros:

```asm
; local_gen(base_name_ptr, result_ptr)
; generates unique label: .base_name_NNN
; NNN increments globally across all macro expansions
```

Tests: tests/unit/macro/local.s
Gate: two expansions of same macro produce different local label names.

---

### Step 6.5 — frontend/macro/cond/def.s, expr.s, str.s, cond.s

Conditional assembly:

```asm
; cond_if(token_stream)    → evaluate %if expression
; cond_ifdef(name_ptr)     → %ifdef / %ifndef
; cond_ifidn(a, b)         → %ifidn string compare
; cond_else()              → flip active state
; cond_elif(token_stream)  → %elif
; cond_endif()             → end conditional block
; cond_skip_to_endif()     → skip tokens when condition false
```

Tests: tests/unit/macro/cond_if.s, cond_ifdef.s, cond_ifidn.s, cond_else.s, cond_nested.s
Gate: nested %if/%else/%endif up to 32 levels deep works correctly.

---

### Step 6.6 — frontend/macro/rep.s

```asm
; macro_rep(token_stream)     → %rep count ... %endrep
; macro_repcount(token_stream)→ %repcount inside loop
; fires E306 (expansion depth exceeded — if rep > MAX_MACRO_DEPTH)
```

Tests: tests/unit/macro/rep.s, rep_count.s
Gate: %rep 5 DB 0 emits 5 zero bytes. %repcount returns 0-4 correctly.

---

### Step 6.7 — frontend/macro/rotate.s

```asm
; macro_rotate(argc, argv, count) → rotate argument list
; %rotate 1 moves first arg to end
; %rotate -1 moves last arg to front
```

Tests: tests/unit/macro/rotate.s
Gate: 3-argument macro with %rotate 1 applied twice rotates correctly.

---

### Step 6.8 — frontend/macro/stringify.s and paste.s

```asm
; macro_stringify(token_ptr, result_buf) → %str(arg) → quoted string
; macro_paste(tok_a, tok_b, result_ptr) → tok_a##tok_b → concatenated token
; fires E314 (invalid token from paste)
```

Tests: tests/unit/macro/stringify.s, paste.s
Gate: %str(hello) → "hello". prefix ## suffix → prefixsuffix.

---

### Step 6.9 — frontend/macro/include.s

```asm
; macro_include(token_stream) → %include "filename"
; pushes new file onto lexer input stack
; fires E319 (file not found)
; fires E320 (circular include detected)
; fires E11xx include depth errors
```

Tests: tests/unit/macro/include.s, include_depth.s, include_once.s
Gate: %include works. Circular include fires E320. Depth > 64 fires E1102.

---

### Step 6.10 — frontend/macro/library.s

```asm
; macro_lib_load(path_ptr) → load .inc macro library file
; macro_lib_search(name_ptr) → search library paths for name
```

Gate: %include "include/utasm.inc" loads and makes macros available.

---

### Step 6.11 — frontend/macro/chain.s

Macro expansion chain tracking for error messages:

```asm
; chain_push_macro(name_ptr, file_id, line) → push expansion frame
; chain_pop_macro()                          → pop frame
; chain_current_id()                         → return current chain_id
; chain_format_macro(chain_id, out_buf)      → format expansion trace
```

Tests: tests/unit/macro/expansion_loc.s
Gate: error inside 3-level macro expansion shows correct chain in error message.

---

### Step 6.12 — frontend/macro/purge.s

```asm
; macro_undef(name_ptr)  → %undef — remove single macro
; macro_purge(name_ptr)  → %purge — same as undef
; fires nothing if macro not found (silent)
```

Tests: tests/unit/macro/undef.s, purge.s
Gate: %undef removes macro. Subsequent use fires E301.

---

### Step 6.13 — frontend/macro/expand.s

The expansion engine — replaces macro calls with their bodies:

```asm
; expand_init()
; expand_token(token_ptr, output_stream) → if macro: expand, else pass through
; expand_check_depth()                   → fires E306 if > MAX_MACRO_DEPTH
; fires E307 on recursive macro detection
```

Tests: tests/unit/macro/nested.s, recursive.s
Gate: nested macro call expands correctly. Recursive macro fires E307.

---

### Step 6.14 — frontend/macro/macro.s

Main entry point — runs before parser on token stream:

```asm
; macro_init()
; macro_process(token_stream, output_stream)
; → scan tokens
; → on %define/%macro: process definition
; → on %if/%ifdef etc: process conditional
; → on %include: load file
; → on %rep: expand repetition
; → on macro call: expand body
; → else: pass token through unchanged
```

Gate: a 50-line file with macros, conditionals, and includes produces correct expanded token stream.

---

### Phase 6 Gate

```sh
bash scripts/test.sh unit/macro
# all 27 unit tests pass

bash scripts/test.sh error/E3xx
# all 11 E3xx error tests pass
```

```sh
git commit -m "feat(macro): complete macro engine — define, expand, cond, rep, include, E3xx"
```

---

# PHASE 7 — Symbol Table + Semantic Analysis
**Depends on: Phase 1, Phase 2, Phase 5, Phase 6**

---

### Step 7.1 — middle/symtable/hash.s

FNV-1a hash table with quadratic probing:

```asm
; ht_init(table_ptr, capacity)      → initialize hash table
; ht_insert(table_ptr, key, val)    → insert, return 1 or 0 on full
; ht_lookup(table_ptr, key)         → return val ptr or 0
; ht_delete(table_ptr, key)         → mark slot as deleted
; ht_resize(table_ptr, new_cap)     → grow table
; ht_load_factor(table_ptr)         → return load as percentage
```

Tests: tests/unit/symtable/insert.s, lookup.s, lookup_miss.s, collision.s
Gate: 1 million symbols insert and lookup correctly in O(1) average.

---

### Step 7.2 — middle/symtable/scope.s

Scope management for local labels:

```asm
; scope_push(name_ptr)       → push new scope (PROC name)
; scope_pop()                → pop scope
; scope_current()            → return current scope name
; scope_mangle(label_ptr, result_ptr) → prefix local label with scope
```

Tests: tests/unit/symtable/local_scope.s, local_reuse.s
Gate: .loop in two different PROCs mangled to different names.

---

### Step 7.3 — middle/symtable/insert.s, lookup.s, resolve.s

```asm
; sym_insert(name, type, value, file_id, line) → fires E402 on redef
; sym_lookup(name)           → return symbol ptr or 0
; sym_lookup_strict(name)    → fires E401 if not found
; sym_resolve_forward()      → second pass: resolve all forward refs
; sym_is_defined(name)       → 1 if defined
; sym_is_forward(name)       → 1 if forward reference pending
```

Tests: tests/unit/symtable/forward.s, forward_multi.s, forward_unresolved.s
Gate: forward reference to label defined 10 lines later resolves correctly on pass 2.

---

### Step 7.4 — middle/symtable/global.s, local.s, common.s, weak.s

```asm
; sym_declare_global(name)  → mark symbol as GLOBAL (exported)
; sym_declare_extern(name)  → mark symbol as EXTERN (imported)
; sym_declare_common(name, size, align) → COMMON symbol
; sym_declare_weak(name)    → weak symbol
; fires E412 (extern also defined locally)
; fires E413 (global not defined)
```

Tests: tests/unit/symtable/global.s, extern.s, common.s, weak.s
Gate: GLOBAL exports to ELF symbol table. EXTERN creates undefined symbol. COMMON resolves correctly.

---

### Step 7.5 — middle/symtable/dump.s

Debug helper:

```asm
; sym_dump(fd)  → print all symbols to file descriptor (debug mode only)
```

Gate: dump produces readable output with name, type, value, file, line.

---

### Step 7.6 — middle/symtable/symtable.s

Entry point:

```asm
; symtable_init()
; symtable_reset()
; symtable_pass2_resolve()  → resolve all forward references, fires E401 for unresolved
```

Gate: two-pass assembly resolves all forward references.

---

### Step 7.7 — middle/semantic/size.s

Operand size resolution:

```asm
; sem_size_infer(instr_ptr)     → infer size from operands
; sem_size_override(operand, sz)→ apply explicit size override
; fires E226 (ambiguous size — e.g. MOV [rax], 1 without size spec)
; fires E227 (size override conflict)
```

Tests: tests/unit/parser/reg_8bit.s through reg_64bit.s (used here)
Gate: MOV RAX, 1 → 64-bit. MOV AL, 1 → 8-bit. MOV [RAX], 1 without override → E226.

---

### Step 7.8 — middle/semantic/type.s

Type checking:

```asm
; sem_type_check(instr_ptr) → verify operand types match instruction
; fires E501 (operand size mismatch)
; fires E508 (invalid register for operand)
; fires E509 (register size mismatch)
```

Tests: tests/error/E5xx/E501.s
Gate: MOV AL, RAX fires E501. MOV RAX, XMM0 fires E508.

---

### Step 7.9 — middle/semantic/scope.s and proc.s

```asm
; sem_scope_check(label_ptr) → verify label is in correct scope
; sem_proc_enter(name_ptr)   → open PROC scope
; sem_proc_exit()            → close PROC scope, check balance
```

Gate: label outside PROC fires scope error. Missing ENDPROC fires error at EOF.

---

### Step 7.10 — middle/semantic/instr.s and operand.s and data.s

```asm
; sem_check_instr(ast_node)    → full instruction validation
; sem_check_operand(operand)   → operand validation
; sem_check_data(ast_node)     → data statement validation
```

Gate: all valid instructions pass. Invalid operand combinations fire correct E5xx errors.

---

### Step 7.11 — middle/semantic/semantic.s

Entry point:

```asm
; semantic_init()
; semantic_analyze(ast_list)  → walk AST, fire all semantic errors
; semantic_pass2()            → second-pass checks after symbol resolution
```

Gate: a complete 100-instruction test file passes semantic analysis with no false errors.

---

### Phase 7 Gate

```sh
bash scripts/test.sh unit/symtable
# all 15 tests pass

bash scripts/test.sh error/E4xx
# all 11 tests pass
```

```sh
git commit -m "feat(semantic): complete symbol table + semantic analysis — E4xx errors"
```

---

# PHASE 8 — Encoder (x86-64)
**Depends on: Phase 1–7**
**Largest phase. One instruction group at a time.**

---

### Step 8.1 — backend/encoder/tables/

Five data files. Pure tables, no logic:

**tables/reg.s** — register → encoding mapping:
```asm
; for each register: id, encoding (0-15), size, rex_required
; REG_RAX: id=0,  enc=0, size=64, rex=0
; REG_R8:  id=8,  enc=0, size=64, rex=1  (requires REX.B/REX.R)
; REG_AH:  id=20, enc=4, size=8,  rex=0, high_byte=1
; ... all 200+ registers
```

**tables/modrm.s** — ModRM byte helpers:
```asm
; modrm_byte(mod, reg, rm) → compose ModRM byte
; modrm_mod(modrm)         → extract mod field
; modrm_reg(modrm)         → extract reg field
; modrm_rm(modrm)          → extract rm field
```

**tables/sib.s** — SIB byte helpers:
```asm
; sib_byte(scale, index, base) → compose SIB byte
; sib_scale_enc(scale)         → 1→0, 2→1, 4→2, 8→3
```

**tables/opcode.s** — master opcode table:
```asm
; for each mnemonic: primary opcode byte(s), encoding type, valid operand forms
; entry format: name, op1, op2, op3, enc_type, operand_flags
```

**tables/features.s** — CPU feature requirements per instruction:
```asm
; for each instruction: which CPU feature flags are required
; VMOVAPS: requires AVX
; VPDPBUSD: requires AVX512VNNI
```

Gate: all five files assemble cleanly. Table lookups return correct values for spot-checked entries.

---

### Step 8.2 — backend/encoder/prefix/rex.s

REX prefix generation:

```asm
; rex_needed(operands_ptr)     → 1 if REX prefix required
; rex_build(w, r, x, b)       → compose REX byte (0x40 | W<<3 | R<<2 | X<<1 | B)
; rex_emit(out_ptr, w, r, x, b)→ write REX byte to output
; rex_check_high_byte(reg)    → fires E515 if AH/BH/CH/DH used with REX
```

Tests: tests/unit/encoder/x86/rex_w.s, rex_r.s, rex_x.s, rex_b.s, rex_high.s
Gate: MOV R8, RAX emits REX.R. MOV AH, [R8] fires E515.

---

### Step 8.3 — backend/encoder/prefix/vex.s

VEX prefix generation (2-byte and 3-byte forms):

```asm
; vex2_emit(out_ptr, R, vvvv, L, pp)     → 2-byte VEX: C5 RvvvvLpp
; vex3_emit(out_ptr, R, X, B, m, W, vvvv, L, pp) → 3-byte VEX: C4 ...
; vex_needs_3byte(instr_ptr)             → 1 if 3-byte VEX required
```

Tests: tests/unit/encoder/simd/avx_vex2.s, avx_vex3.s
Gate: VMOVAPS XMM0, XMM1 → C5 F8 28 C1 (2-byte VEX). VEX.W instructions use 3-byte.

---

### Step 8.4 — backend/encoder/prefix/evex.s

EVEX prefix generation (always 4 bytes):

```asm
; evex_emit(out_ptr, R, X, B, R1, mm, W, vvvv, pp, z, L1, L, b, V1, aaa)
; → P0: 62
; → P1: R X B R1 00 mm
; → P2: W vvvv 1 pp
; → P3: z L1 L b V1 aaa
```

Tests: tests/unit/encoder/simd/avx512_evex.s
Gate: VMOVAPS ZMM0 {K1}{Z}, ZMM1 encodes correct 4-byte EVEX prefix.

---

### Step 8.5 — backend/encoder/prefix/lock.s and rep.s

```asm
; lock_emit(out_ptr, instr_ptr) → emit F0 prefix, fires E529 if not lockable
; rep_emit(out_ptr, prefix_type)→ emit F3 (REP) or F2 (REPNE)
; fires E529 (LOCK not allowed here)
; fires E530 (REP not allowed here)
```

Tests: tests/unit/encoder/x86/lock.s, rep.s
Gate: LOCK XCHG [RAX], RBX emits F0. LOCK JMP fires E529.

---

### Step 8.6 — backend/encoder/x86/mov.s

MOV is the most common instruction and has the most encoding forms. Get this perfect:

```asm
; mov encoding forms:
; MOV r8, r/m8     → 8A /r
; MOV r/m8, r8     → 88 /r
; MOV r64, r/m64   → REX.W 8B /r
; MOV r/m64, r64   → REX.W 89 /r
; MOV r64, imm64   → REX.W B8+rd io (short form for registers)
; MOV r/m64, imm32 → REX.W C7 /0 id (sign-extended)
; MOV r/m8, imm8   → C6 /0 ib
; MOV Sreg, r/m16  → 8E /r
; MOV r/m16, Sreg  → 8C /r
; MOV r64, CR/DR   → privileged
```

Tests: tests/unit/encoder/x86/mov_rr.s, mov_rm.s, mov_mr.s, mov_ri.s, mov_mi.s, mov_seg.s, movzx.s, movsx.s, movsxd.s
Gate: every encoding form produces correct bytes verified against known-good values.

---

### Step 8.7 — backend/encoder/x86/arith.s

ADD, SUB, MUL, DIV, IMUL, IDIV, ADC, SBB, INC, DEC, NEG:

All share similar ModRM encoding patterns. ADD has these forms:
```
ADD AL, imm8      → 04 ib
ADD rAX, imm32    → 05 id
ADD r/m8, imm8    → 80 /0 ib
ADD r/m64, imm8   → REX.W 83 /0 ib (sign-extended)
ADD r/m64, imm32  → REX.W 81 /0 id (sign-extended)
ADD r/m64, r64    → REX.W 01 /r
ADD r64, r/m64    → REX.W 03 /r
```

Tests: tests/unit/encoder/x86/add.s through dec.s
Gate: every arithmetic instruction encodes correctly for all operand sizes.

---

### Step 8.8 — backend/encoder/x86/logic.s

AND, OR, XOR, NOT, TEST — similar to arith.s encoding.

Tests: tests/unit/encoder/x86/and.s, or.s, xor.s, not.s, cmp.s
Gate: XOR RAX, RAX → REX.W 33 C0. TEST RAX, RAX → REX.W 85 C0.

---

### Step 8.9 — backend/encoder/x86/shift.s

SHL, SHR, SAR, ROL, ROR, RCL, RCR, SHLD, SHRD:

```
SHL r/m64, 1      → REX.W D1 /4
SHL r/m64, imm8   → REX.W C1 /4 ib
SHL r/m64, CL     → REX.W D3 /4
```

Tests: tests/unit/encoder/x86/shl.s through shrd.s
Gate: all three forms of each shift instruction encode correctly.

---

### Step 8.10 — backend/encoder/x86/jump.s

JMP and all Jcc — critical: short vs near selection:

```asm
; jmp_encode(target_ptr, out_ptr)
; → if displacement fits in int8: use short form (EB cb)
; → else: use near form (E9 cd)
; → on first pass: emit long form (forward reference)
; → on second pass: shorten if possible
; fires E506 (jump target out of range — > 2GB)
; fires E507 (short jump out of range — > 127 bytes — informational hint only)
```

All 16 Jcc variants: JO JNO JB JAE JE JNE JBE JA JS JNS JP JNP JL JGE JLE JG

Tests: tests/unit/encoder/x86/jmp_short.s, jmp_near.s, jmp_ind.s, jcc.s, loop.s
Gate: short jump within range uses EB. Jump exceeding 127 bytes uses E9. All 16 Jcc encode correctly.

---

### Step 8.11 — backend/encoder/x86/call.s

```asm
; CALL rel32     → E8 cd
; CALL r/m64     → FF /2
; CALL FAR m16:64→ FF /3
```

Tests: tests/unit/encoder/x86/call_near.s, call_ind.s, ret.s, retf.s
Gate: CALL label emits E8 + correct offset. RET → C3. RET 8 → C2 08 00.

---

### Step 8.12 — backend/encoder/x86/stack.s

PUSH, POP, PUSHF, POPF:

```
PUSH r64    → 50+rd
PUSH imm8   → 6A ib
PUSH imm32  → 68 id
PUSH r/m64  → FF /6
POP r64     → 58+rd
PUSHFQ      → 9C
POPFQ       → 9D
```

Tests: tests/unit/encoder/x86/push_reg.s, push_imm.s, push_mem.s, pop.s, pushf.s
Gate: PUSH RAX → 50. PUSH 1 → 6A 01. PUSH QWORD PTR [RAX] → FF 30.

---

### Step 8.13 — backend/encoder/x86/ (remaining instructions)

Build these in order, one file per group, same pattern of test → encode → verify:

```
string.s    → MOVS/STOS/LODS/SCAS/CMPS + REP/REPE/REPNE prefix
bit.s       → BT/BTS/BTR/BTC/BSF/BSR/TZCNT/LZCNT/POPCNT
cmov.s      → CMOVcc all 16 variants (0F 4x /r)
setcc.s     → SETcc all 16 variants (0F 9x /0)
flag.s      → CLC/STC/CMC/CLD/STD/CLI/STI/CLAC/STAC
io.s        → IN AL,imm8 / IN AL,DX / OUT imm8,AL / OUT DX,AL
system.s    → SYSCALL/SYSRET/HLT/NOP/CPUID/RDTSC/RDTSCP/XGETBV/XSETBV
priv.s      → LGDT/LIDT/SGDT/SIDT/LLDT/SLDT/LTR/STR/LMSW/SMSW/MOV CRn/DRn
misc.s      → LEA/XCHG/CMPXCHG/CMPXCHG16B/BSWAP/MOVBE/XLAT/CPUID
crypto.s    → AES-NI: AESENC/AESDEC/AESKEYGENASSIST etc / SHA: SHA1MSG1 etc
```

Gate for each: all unit tests for that file pass.

---

### Step 8.14 — backend/encoder/x86/addr_modes.s + sib tests

Full addressing mode verification:

```
[RAX]                   → ModRM: mod=00 rm=000
[RAX + 8]               → ModRM: mod=01 rm=000 + disp8
[RAX + 512]             → ModRM: mod=10 rm=000 + disp32
[RAX + RCX]             → ModRM: mod=00 rm=100 SIB: ss=00 idx=001 base=000
[RAX + RCX*4]           → SIB: ss=10
[RAX + RCX*4 + 16]      → SIB + disp8
[RIP + label]           → ModRM: mod=00 rm=101 + disp32 (RIP-relative)
[0x1000]                → disp32 only: ModRM mod=00 rm=101 + 0x1000
```

Tests: tests/unit/encoder/x86/addr_modes.s, sib_base.s, sib_index.s, sib_scale.s, sib_nobase.s, riprel.s, disp8.s, disp32.s
Gate: every addressing form produces exact expected byte sequence.

---

### Step 8.15 — backend/encoder/dispatch.s

The master dispatch table — maps mnemonic token to handler:

```asm
; dispatch table indexed by mnemonic token type
; each entry: ptr to encode function
; encode_instr(ast_node_ptr, out_buf) → dispatch to correct handler
```

Gate: MOV dispatches to mov_encode. ADD to arith_encode. Unknown mnemonic fires E527.

---

### Step 8.16 — backend/encoder/encoder.s

Main entry point:

```asm
; encoder_init()
; encoder_encode(ast_list, output_buf) → encode all instructions, return byte count
; encoder_pass1(ast_list)              → first pass (collect symbols, emit with placeholder offsets)
; encoder_pass2(ast_list, output_buf)  → second pass (resolve, emit final)
```

Gate: a 50-instruction test file encodes to correct byte sequence verified with objdump.

---

### Step 8.17 — backend/encoder/simd/ (full SIMD)

Build in strict order — each depends on the previous:

```
mmx.s      → all MMX instructions (MOVQ, PADDB, PAND, etc)
sse.s      → SSE packed single (MOVAPS, ADDPS, MULPS, etc)
sse2.s     → SSE2 packed double + integer (PADDQ, MOVDQA, etc)
sse3.s     → SSE3 (HADDPS, MOVDDUP) + SSSE3 (PSHUFB, PALIGNR, etc)
sse4.s     → SSE4.1 (BLENDPS, DPPS, PMULLD) + SSE4.2 (PCMPESTRI, CRC32)
avx.s      → VEX-encoded 128/256-bit (VMOVAPS, VADDPS, etc)
avx2.s     → AVX2 integer (VPAND, VPADDQ, etc) + GATHER instructions
avx512/avx512.s  → EVEX foundation, k-masks, {z}, broadcasting
avx512/bw.s      → byte/word: VPADDW, VPCMPB, etc
avx512/dq.s      → dword/qword: VPMULLQ, VPANDQ, etc
avx512/vl.s      → VL 128/256-bit variants of AVX-512 instructions
avx512/vnni.s    → VPDPBUSD, VPDPWSSD (critical for Sagar math library)
avx512/bf16.s    → VDPBF16PS, VCVTNE2PS2BF16
amx.s      → TILELOADD, TILESTORED, TDPBSSD, etc
fpu.s      → x87 FPU: FLDZ, FADD, FSQRT, FISTP, etc
```

Tests: one test file per simd/ source file
Gate: for each instruction: encoded bytes match Intel manual encoding. Cross-verify with NASM on a known input.

---

### Phase 8 Gate

```sh
bash scripts/test.sh unit/encoder
# all 110+ encoder unit tests pass

bash scripts/test.sh error/E5xx
# all 21 E5xx error tests pass

bash scripts/test.sh error/E7xx
# all 12 E7xx error tests pass (after cpu/ built in next phase)
```

```sh
git commit -m "feat(encoder): complete x86-64 encoder — all instructions, SIMD, AVX-512, E5xx"
```

---

# PHASE 9 — ISA Tables + CPU Profiles
**Depends on: Phase 8**

---

### Step 9.1 — backend/isa/amd64.s

Full AMD64 instruction table — one entry per instruction form:

```asm
struc ISAEntry
    .name_ptr    dq 0   ; mnemonic string
    .opcode      dw 0   ; primary opcode
    .opcode_ext  db 0   ; opcode extension (/digit)
    .enc_type    db 0   ; encoding type (MR, RM, MI, ZO, etc)
    .op1_type    db 0   ; operand 1 type
    .op2_type    db 0   ; operand 2 type
    .op3_type    db 0   ; operand 3 type
    .cpu_flags   dd 0   ; required CPU features
    .prefix_req  db 0   ; required prefix flags
endstruc
```

Gate: every instruction from Intel manual vol 2 has at least one entry.

---

### Step 9.2 — cpu/features.s

CPU feature flag definitions and runtime detection:

```asm
; feature flag bitmasks
CPU_MMX      equ (1 << 0)
CPU_SSE      equ (1 << 1)
CPU_SSE2     equ (1 << 2)
CPU_SSE3     equ (1 << 3)
CPU_SSSE3    equ (1 << 4)
CPU_SSE41    equ (1 << 5)
CPU_SSE42    equ (1 << 6)
CPU_AVX      equ (1 << 7)
CPU_AVX2     equ (1 << 8)
CPU_AVX512F  equ (1 << 9)
CPU_AVX512BW equ (1 << 10)
CPU_AVX512DQ equ (1 << 11)
CPU_AVX512VL equ (1 << 12)
CPU_VNNI     equ (1 << 13)
CPU_BF16     equ (1 << 14)
CPU_AMX      equ (1 << 15)
CPU_RDRAND   equ (1 << 16)
CPU_RDSEED   equ (1 << 17)
CPU_AESNI    equ (1 << 18)
CPU_SHA      equ (1 << 19)
CPU_CET      equ (1 << 20)
; ... more flags

; features_from_cpuid() → run CPUID and build feature bitmask
; features_active()     → return active feature bitmask (from CPU directive or CPUID)
; features_set(mask)    → force feature set (from CPU directive)
```

Gate: features_from_cpuid() returns correct flags for the build machine.

---

### Step 9.3 — cpu/profiles/

One file per profile — sets the feature bitmask for that CPU:

```asm
; generic.s — baseline x86-64 only
CPU_GENERIC_FLAGS equ CPU_SSE2   ; SSE2 guaranteed in all x86-64

; server.s — modern server-grade
CPU_SERVER_FLAGS equ (CPU_SSE2 | CPU_SSE3 | CPU_SSSE3 | CPU_SSE41 | \
                      CPU_SSE42 | CPU_AVX | CPU_AVX2 | CPU_AVX512F | \
                      CPU_AVX512BW | CPU_AVX512DQ | CPU_AVX512VL | \
                      CPU_VNNI | CPU_RDRAND | CPU_AESNI)

; zen4.s — AMD Zen 4 specific
CPU_ZEN4_FLAGS equ (CPU_SERVER_FLAGS | CPU_BF16 | CPU_AVX512VNNI)

; spr.s — Intel Sapphire Rapids
CPU_SPR_FLAGS equ (CPU_SERVER_FLAGS | CPU_AMX | CPU_BF16)
```

Gate: CPU SERVER profile activates correct feature bits.

---

### Step 9.4 — cpu/validate.s

Instruction vs active profile validation:

```asm
; cpu_validate_instr(isa_entry_ptr) → fires E7xx if required features not in active profile
; called by encoder for every instruction
```

Tests: tests/error/E7xx/ — all 12 tests
Gate: VPDPBUSD with CPU GENERIC fires E714. Same with CPU SERVER passes.

---

### Step 9.5 — cpu/errata.s

Known CPU errata database — advisory warnings:

```asm
; errata_check(instr_ptr) → fires W7xx if instruction has known errata on active CPU
```

Gate: known errata entries produce W729 warnings.

---

### Step 9.6 — cpu/perf.s

Performance hints database:

```asm
; perf_check(instr_ptr) → fires W4xx performance warnings
; e.g. W702: mixing AVX and legacy SSE (causes vzeroupper penalty)
```

Gate: mixing VMOVAPS and MOVAPS fires W702.

---

### Step 9.7 — cpu/cpu.s — entry point

```asm
; cpu_init()                → initialize with GENERIC profile
; cpu_set_profile(profile)  → switch active profile
; cpu_get_flags()           → return active feature bitmask
; cpu_check_instr(ptr)      → validate + errata + perf check
```

Gate: CPU SERVER enables correct features. CPU INVALID fires E729.

---

### Phase 9 Gate

```sh
bash scripts/test.sh error/E7xx
# all 12 E7xx tests pass
```

```sh
git commit -m "feat(cpu): complete ISA tables + CPU profiles — E7xx validation"
```

---

# PHASE 10 — Linker
**Depends on: Phase 1–9**

---

### Step 10.1 — backend/linker/section.s

Section management:

```asm
struc Section
    .name_ptr  dq 0
    .type      dd 0   ; SHT_PROGBITS, SHT_NOBITS, etc
    .flags     dd 0   ; SHF_ALLOC, SHF_EXEC, SHF_WRITE
    .addr      dq 0   ; virtual address (after layout)
    .offset    dq 0   ; file offset (after layout)
    .size      dq 0   ; section size
    .align     dq 0   ; alignment requirement
    .data_ptr  dq 0   ; pointer to section content
    .reloc_ptr dq 0   ; pointer to relocation list
endstruc

; section_create(name, type, flags, align)  → return Section ptr
; section_current()                          → return active section ptr
; section_switch(name)                       → switch active section
; section_emit(data_ptr, len)                → append bytes to current section
; section_emit_byte(byte)                    → append one byte
; section_align_to(align)                    → pad with zeros to alignment
; section_list_all()                         → return linked list of all sections
```

Tests: tests/unit/linker/sections.s, align.s, bss.s
Gate: .text section created, bytes emitted, size tracks correctly. BSS has correct p_memsz.

---

### Step 10.2 — backend/linker/symbol.s

Symbol resolution for linking:

```asm
; link_sym_add(name, section, offset, type, binding) → add defined symbol
; link_sym_add_undef(name)                           → add undefined (EXTERN)
; link_sym_resolve(name)                             → return symbol ptr or 0
; link_sym_resolve_all()                             → fires E601 for remaining undefined
; link_sym_get_value(sym_ptr)                        → section base + offset
```

Tests: tests/unit/linker/basic.s, forward.s, extern.s
Gate: all forward references resolved. Undefined external fires E601.

---

### Step 10.3 — backend/linker/reloc/

Five relocation types:

**reloc/abs.s** — R_X86_64_64: absolute 64-bit address
**reloc/rel.s** — R_X86_64_PC32: relative 32-bit (used by CALL/JMP)
**reloc/got.s** — R_X86_64_GOT32: GOT-relative
**reloc/plt.s** — R_X86_64_PLT32: PLT-relative
**reloc/tls.s** — R_X86_64_TPOFF32: TLS offset

```asm
; reloc_add(section, offset, type, sym_ptr, addend) → add relocation record
; reloc_apply_all(section_list)                      → apply all relocations
; fires E604 (relocation overflow)
```

Tests: tests/unit/linker/reloc_abs.s, reloc_rel.s, reloc_got.s, reloc_plt.s, reloc_tls.s
Gate: CALL label emits E8 + R_X86_64_PC32 relocation. Applied correctly at link time.

---

### Step 10.4 — backend/linker/layout.s

Virtual address and file offset assignment:

```asm
; layout_sections(section_list, base_addr) → assign VAs and file offsets
; layout_program_headers()                  → determine LOAD segments
; fires E603 (section overlap — shouldn't happen but guard)
```

Tests: tests/unit/linker/layout.s
Gate: .text at 0x400000, .data page-aligned after .text, .bss page-aligned after .data.

---

### Step 10.5 — backend/linker/merge.s

Section merging (multiple object files):

```asm
; merge_sections(obj_list) → merge same-named sections from multiple objects
; merge_symbols(obj_list)  → merge symbol tables, fires E602 on duplicate defs
```

Tests: tests/unit/linker/multi.s
Gate: two object files merged, symbols from both accessible.

---

### Step 10.6 — backend/linker/dead.s

Dead code elimination:

```asm
; dead_mark_reachable(entry_sym_ptr) → mark all symbols reachable from entry
; dead_strip_sections()              → remove unreachable sections
```

Tests: tests/unit/linker/dead.s
Gate: unreferenced function removed from output. Entry point always kept.

---

### Step 10.7 — backend/linker/archive.s

Static archive (.a file) reader:

```asm
; archive_open(path)              → open .a file, return handle
; archive_next_obj(handle)        → return next object file ptr + size
; archive_close(handle)
```

Tests: tests/unit/linker/archive.s
Gate: open a .a file created by NASM+ar, extract and link all objects.

---

### Step 10.8 — backend/linker/script.s

Linker script parser (utasm.ld format):

```asm
; script_parse(path)              → parse linker script
; script_get_section_addr(name)   → return specified address for section
; script_get_entry()              → return entry point symbol name
```

Gate: utasm.ld parses correctly and sets entry point to _start.

---

### Step 10.9 — backend/linker/map.s

Map file generation:

```asm
; map_write(path, section_list, sym_table) → write .map file
; format: section | address | size | symbol listing
```

Gate: map file produced matches expected format.

---

### Step 10.10 — backend/linker/linker.s

Main coordinator:

```asm
; linker_init()
; linker_add_object(data_ptr, size) → add object file for linking
; linker_add_archive(path)          → add archive
; linker_link(output_format)        → perform full link, return output buffer
; linker_set_entry(sym_name)        → set entry point symbol
```

Gate: link two object files with cross-references into a working executable.

---

### Phase 10 Gate

```sh
bash scripts/test.sh unit/linker
# all 19 linker unit tests pass

bash scripts/test.sh error/E6xx
# all 5 E6xx error tests pass
```

```sh
git commit -m "feat(linker): complete linker — sections, symbols, relocations, archive, E6xx"
```

---

# PHASE 11 — Output Formats
**Depends on: Phase 10**

---

### Step 11.1 — backend/output/elf/

Build in dependency order:

**out/strtab.s** — string table builder (needed by symtab and shdr)
```asm
; strtab_init()
; strtab_add(str_ptr)   → add string, return offset
; strtab_finalize()     → return ptr + size of final table
```

**out/symtab.s** — ELF symbol table
```asm
; writes Elf64_Sym entries for all symbols
; sets st_name from strtab, st_value from layout, st_size, st_info, st_shndx
```

**out/rela.s** — RELA relocation table
```asm
; writes Elf64_Rela entries for all relocations
; r_offset, r_info (sym<<32 | type), r_addend
```

**out/note.s** — note sections (GNU ABI, build ID)

**out/dynamic.s** — .dynamic section (for shared libraries)

**out/shdr.s** — section header table
```asm
; writes one Elf64_Shdr per section
; correctly sets sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize
```

**out/phdr.s** — program header table
```asm
; determines LOAD segments from section layout
; writes PT_LOAD entries with correct p_flags (R, RW, RX)
; p_filesz vs p_memsz for BSS
```

**out/header.s** — ELF file header
```asm
; e_ident: ELF magic, class=64, data=LSB, version=1, OS/ABI=0
; e_type: ET_EXEC or ET_REL or ET_DYN
; e_machine: EM_X86_64 = 62
; e_entry: entry point address
; e_phoff, e_shoff, e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx
```

**out/out.s** — ELF output coordinator:
```asm
; elf_emit(linker_output_ptr, format, output_fd)
; assembles all sections into correct ELF layout
; writes to output file
```

Tests: tests/unit/output/elf_exec.s, elf_obj.s, elf_so.s, elf_hdr.s, elf_sym.s, elf_rela.s, elf_phdr.s, elf_note.s
Gate: output ELF passes readelf -a with no errors. Executable runs correctly.

---

### Step 11.2 — backend/output/flat/

**flat/out.s** — flat binary output (just raw bytes, no headers)
**flat/boot.s** — boot sector specifics (pads to 512 bytes, appends 0x55AA)
**flat/map.s** — optional flat binary map file

Tests: tests/unit/output/flat.s, flat_boot.s
Gate: flat binary contains exact bytes from .text section. Boot sector ends with 55 AA at offset 510.

---

### Step 11.3 — backend/output/pe/

PE32+ for UEFI:

**pe/dos.s** — DOS stub (MZ header + "This program cannot be run in DOS mode")
**pe/header.s** — PE signature (50 45 00 00) + COFF file header
**pe/optional.s** — PE optional header (IMAGE_OPTIONAL_HEADER64)
**pe/section.s** — section table (IMAGE_SECTION_HEADER per section)
**pe/reloc.s** — base relocation table (.reloc section)
**pe/export.s** — export directory (for DLLs)
**pe/import.s** — import directory
**pe/cert.s** — certificate table slot (for Secure Boot signing)
**pe/out.s** — PE coordinator

Tests: tests/unit/output/pe_exec.s, pe_hdr.s
Gate: output PE passes PE-bear with no errors. UEFI image loads in QEMU OVMF.

---

### Step 11.4 — backend/output/upk/

UtkarshaLab package format:

**upk/header.s** — magic bytes, version, format fields
**upk/meta.s** — package name, version, description, author
**upk/deps.s** — dependency list (name + version constraint per dep)
**upk/sign.s** — Ed25519 signature over package content
**upk/compress.s** — optional LZ4/zstd compression of payload
**upk/out.s** — .upk coordinator

Tests: tests/unit/output/upk.s, upk_sign.s
Gate: .upk file produced has correct magic. Signature validates. Deps list correct.

---

### Step 11.5 — backend/output/listing/

**listing/listing.s** — assembly listing file (.lst format):
```
line | address | bytes | source
0001 | 00401000 | 48 89 C1 | mov rcx, rax
```

**listing/mapfile.s** — symbol map file (.map format):
```
section .text   00401000 - 004015FF (1536 bytes)
  _start        00401000
  main          00401020
```

**listing/symdump.s** — symbol table dump for debugging

Tests: tests/unit/output/listing.s, mapfile.s
Gate: listing file format matches expected output exactly.

---

### Step 11.6 — backend/output/output.s

Format dispatcher:

```asm
; output_emit(format, linker_ptr, output_path)
; format: OUTPUT_ELF64 / OUTPUT_PE32PLUS / OUTPUT_FLAT / OUTPUT_UPK
; dispatches to correct output module
```

Gate: -f elf64 calls elf_emit. -f bin calls flat_emit.

---

### Step 11.7 — utasm.s and cli.s — wire everything together

**cli.s** — argument parser:
```asm
; cli_parse(argc, argv)  → parse all arguments, set global config
; fires error + exit(1) on unknown argument
; fires error + exit(1) on missing required argument
```

**utasm.s** — main entry point:
```asm
_start:
    cli_parse()
    for each input file:
        ctx_set_file(path)
        lexer_init(source)
        macro_process(token_stream)
        parser_parse()
        semantic_analyze()
        encoder_encode()
    linker_link()
    output_emit()
    exit(error_count > 0 ? 1 : 0)
```

Gate: `./utasm -arch amd64 -f elf64 --standalone tests/integration/hello/amd64.s -o hello` produces a working executable.

---

### Phase 11 Gate

```sh
bash scripts/test.sh unit/output
# all 18 output unit tests pass

bash scripts/test.sh integration/hello
# hello world runs on amd64

bash scripts/test.sh integration/elf
bash scripts/test.sh integration/pe
bash scripts/test.sh integration/boot
bash scripts/test.sh integration/upk
```

```sh
git commit -m "feat(output): complete all output formats — ELF64, PE32+, flat, upk"
```

---

# PHASE 12 — Test Runner
**Depends on: Phase 11 — utasm must produce working binaries**

---

### Step 12.1 — tests/runner.s

The test runner itself — assembled by utasm Gen0:

```asm
; runner_init()
; runner_add(name_ptr, test_fn_ptr) → register a test
; runner_run_all()                   → run all tests, collect results
; runner_run_category(cat)           → run one category
; runner_run_single(name)            → run one test
```

---

### Step 12.2 — tests/expect.s and diff.s

```asm
; expect_bytes(actual_ptr, actual_len, expected_ptr, expected_len)
; → compare byte-for-byte, record PASS or FAIL with diff
; diff_show(actual, expected, out_fd)
; → show first difference location
```

---

### Step 12.3 — tests/timeout.s and parallel.s

```asm
; timeout_run(test_fn_ptr, seconds) → run test with timeout, return 0 if timed out
; parallel_run(test_list, thread_count) → run tests in parallel
```

---

### Step 12.4 — tests/report.s

```asm
; report_pass(name)
; report_fail(name, reason)
; report_summary()   → print final table
```

---

### Step 12.5 — Run full test suite

```sh
bash scripts/test.sh
```

All tests from all previous phases now run through the proper test runner.

Fix every failure before proceeding. No exceptions.

---

### Phase 12 Gate

```sh
bash scripts/test.sh
# zero failures across all categories
```

```sh
git commit -m "feat(tests): complete test runner — all tests passing"
```

---

# PHASE 13 — Self-Hosting
**Target: v0.1.0**
**The first major milestone.**

---

### Step 13.1 — Fix bootstrap.sh for new structure

```sh
#!/bin/bash
set -e

echo "[+] Stage 1: Building Gen0 with NASM..."
for src in $(find . -name "*.s" | grep -v tests/ | grep -v build/); do
    obj="build/gen0/${src%.s}.o"
    mkdir -p "$(dirname "$obj")"
    nasm -I./ -f elf64 "$src" -o "$obj"
done
ld -T utasm.ld -o build/gen0/utasm $(find build/gen0 -name "*.o")
echo "[+] Gen0 built: build/gen0/utasm"

echo "[+] Stage 2: Building Gen1 with Gen0..."
for src in $(find . -name "*.s" | grep -v tests/ | grep -v build/); do
    obj="build/gen1/${src%.s}.o"
    mkdir -p "$(dirname "$obj")"
    ./build/gen0/utasm -arch amd64 -f elf64 "$src" -o "$obj"
done
ld -T utasm.ld -o build/gen1/utasm $(find build/gen1 -name "*.o")
echo "[+] Gen1 built: build/gen1/utasm"

echo "[+] Stage 3: Building Gen2 with Gen1..."
for src in $(find . -name "*.s" | grep -v tests/ | grep -v build/); do
    obj="build/gen2/${src%.s}.o"
    mkdir -p "$(dirname "$obj")"
    ./build/gen1/utasm -arch amd64 -f elf64 "$src" -o "$obj"
done
ld -T utasm.ld -o build/gen2/utasm $(find build/gen2 -name "*.o")
echo "[+] Gen2 built: build/gen2/utasm"

echo "[+] Parity check: Gen1 vs Gen2..."
if cmp -s build/gen1/utasm build/gen2/utasm; then
    echo "[+] PARITY ACHIEVED: Gen1 == Gen2 bit-identical"
    echo "[+] utasm is self-hosting"
else
    echo "[-] PARITY FAILED: Gen1 != Gen2"
    echo "[-] utasm is NOT yet self-hosting"
    diff <(xxd build/gen1/utasm) <(xxd build/gen2/utasm) | head -50
    exit 1
fi
```

---

### Step 13.2 — Achieve parity

Run bootstrap.sh. Fix every difference between Gen1 and Gen2.

Common causes of parity failure:
- Uninitialized memory read producing different values in different runs
- Timestamp or non-deterministic value embedded in output
- Pointer values embedded instead of offsets
- Arena allocator returning different addresses

Fix each one until Gen1 == Gen2.

---

### Step 13.3 — Run integration tests

```sh
bash scripts/test.sh integration/selfhost
bash scripts/test.sh integration
```

Gate: all integration tests pass with Gen1 binary.

---

### Step 13.4 — Tag v0.1.0

```sh
echo "0.1.0" > VERSION
git add -A
git commit -m "release: v0.1.0 — utasm is self-hosting, gen1 == gen2"
git tag v0.1.0
```

**This is the first major milestone. utasm can assemble itself.**

---

# PHASE 14 — AArch64 Encoder
**Target: part of v0.2.0**
**Depends on: Phase 13**

AArch64 uses fixed-width 32-bit instructions. Encoding is simpler than x86-64.

---

### Step 14.1 — backend/isa/aarch64.s

AArch64 instruction table — same structure as amd64.s but for ARM instructions.

Gate: table contains all base ARMv8-A instructions.

---

### Step 14.2 — backend/encoder/aarch64/base.s

AArch64 base instruction encoder:

```asm
; Each instruction encodes as a single 32-bit word
; Instruction classes:
;   Data processing (immediate)  — ADD Xd, Xn, #imm12
;   Data processing (register)   — ADD Xd, Xn, Xm
;   Loads and stores             — LDR X0, [X1, #8]
;   Branches                     — B label / BL label / BR X0
;   System instructions          — SVC #0 / MRS X0, NZCV

; encode_a64_instr(ast_node_ptr, out_ptr)
; → determine instruction class
; → encode 32-bit word
; → write to output buffer
```

Tests: tests/unit/encoder/aarch64/mov.s, arith.s, logic.s, branch.s, load.s, store.s, pair.s, system.s
Gate: every instruction produces exact 32-bit word per ARM architecture reference manual.

---

### Step 14.3 — backend/encoder/aarch64/neon.s

NEON Advanced SIMD:

```asm
; NEON uses same 32-bit encoding with Q bit for 128-bit variants
; ADD V0.4S, V1.4S, V2.4S → 0E A28420 (32-bit)
; encode_neon_instr(ast_node_ptr, out_ptr)
```

Tests: tests/unit/encoder/aarch64/neon_int.s, neon_fp.s
Gate: FADD, FMUL, VADD etc encode correctly.

---

### Step 14.4 — backend/encoder/aarch64/sve.s

SVE/SVE2 — scalable vector:

```asm
; SVE instructions use predicate registers (P0-P15) and Z registers (Z0-Z31)
; encode_sve_instr(ast_node_ptr, out_ptr)
```

Tests: tests/unit/encoder/aarch64/sve.s
Gate: FADD Z0.S, P0/M, Z0.S, Z1.S encodes correctly.

---

### Step 14.5 — QEMU cross-arch test

```sh
# assemble AArch64 hello world
./build/gen1/utasm -arch aarch64 -f elf64 --standalone \
    tests/integration/hello/aarch64.s -o build/hello_arm

# run under QEMU
qemu-aarch64 build/hello_arm
```

Gate: hello world prints correctly under QEMU AArch64.

---

# PHASE 15 — RISC-V 64 Encoder
**Target: part of v0.2.0**
**Depends on: Phase 14**

---

### Step 15.1 — backend/isa/riscv64.s

RISC-V 64 instruction table.
Gate: all RV64GC instructions covered.

---

### Step 15.2 — backend/encoder/riscv64/base.s

RV64I base integer instruction set:

```asm
; RISC-V uses variable-length encoding:
; Standard instructions: 32-bit (instr[1:0] = 11)
; Compressed instructions: 16-bit (instr[1:0] != 11)
;
; R-type: funct7 | rs2 | rs1 | funct3 | rd | opcode
; I-type: imm[11:0] | rs1 | funct3 | rd | opcode
; S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
; B-type: imm[12|10:5] | rs2 | rs1 | funct3 | imm[4:1|11] | opcode
; U-type: imm[31:12] | rd | opcode
; J-type: imm[20|10:1|11|19:12] | rd | opcode

; encode_rv64_instr(ast_node_ptr, out_ptr)
```

Tests: tests/unit/encoder/riscv64/base.s
Gate: ADD x1, x2, x3 → 00310033 (little-endian). LUI x1, 0x12345 → 12345037.

---

### Step 15.3 — backend/encoder/riscv64/m.s, a.s, fd.s, v.s, c.s

```
m.s  → MUL, MULH, DIV, REM and 64-bit variants
a.s  → LR.W/D, SC.W/D, AMOSWAP, AMOADD, etc
fd.s → FADD.S/D, FMUL.S/D, FLD, FSW, FCVT etc
v.s  → vector instructions (VSETVLI, VADD.VV, VMUL.VX, etc)
c.s  → compressed: C.MV, C.ADD, C.LW, C.J, etc
```

Tests: one test file per extension
Gate: each extension produces correct encodings.

---

### Step 15.4 — backend/encoder/riscv64/relax.s

RISC-V relaxation — replacing long sequences with shorter ones at link time:

```asm
; relax_scan(section_ptr)   → scan for relaxable sequences
; relax_apply(section_ptr)  → apply relaxations, update relocations
; AUIPC + JALR → JAL if target within ±1MB
```

Gate: relaxation applied correctly on test binary.

---

### Step 15.5 — QEMU RISC-V test

```sh
./build/gen1/utasm -arch riscv64 -f elf64 --standalone \
    tests/integration/hello/riscv64.s -o build/hello_rv64

qemu-riscv64 build/hello_rv64
```

Gate: hello world prints correctly under QEMU RISC-V 64.

---

### Step 15.6 — Cross-arch integration tests

```sh
bash scripts/test.sh integration/crossarch
```

Gate: both aarch64.sh and riscv64.sh pass under QEMU.

---

### Step 15.7 — Tag v0.2.0

```sh
echo "0.2.0" > VERSION
git add -A
git commit -m "release: v0.2.0 — AArch64 + RISC-V 64 complete, all three architectures working"
git tag v0.2.0
```

**Second major milestone. utasm is a fully multi-architecture assembler.**

---

# PHASE 16 — DWARF v5 Debug Info
**Target: v0.3.0**
**Depends on: Phase 15**

---

### Step 16.1 — debug/srcmap.s, file.s, linemap.s, macromap.s

Source map infrastructure (already partially built in Phase 1 for error engine, now fully implemented for DWARF):

```asm
; srcmap_file_register(path)         → return file_id
; srcmap_line_add(file_id, line, addr)→ record source line → address mapping
; srcmap_macro_add(macro, file, line) → record macro origin
```

Gate: 100 source lines mapped to addresses correctly.

---

### Step 16.2 — debug/abbrev.s

DWARF abbreviation table (.debug_abbrev):

```asm
; Defines the DIE tag + attribute encoding used by .debug_info
; Standard abbreviations:
;   1: DW_TAG_compile_unit
;   2: DW_TAG_subprogram
;   3: DW_TAG_variable
;   4: DW_TAG_base_type
```

Gate: abbreviation table matches DWARF v5 spec encoding.

---

### Step 16.3 — debug/cu.s

Compilation unit (.debug_info):

```asm
; dwarf_cu_emit(file_id, producer_str, out_buf)
; → unit_length (4 or 8 bytes)
; → version = 5
; → unit_type = DW_UT_compile
; → address_size = 8
; → debug_abbrev_offset
; → DW_TAG_compile_unit DIE
;     DW_AT_producer: "utasm 0.2.0"
;     DW_AT_language: DW_LANG_Mips_Assembler
;     DW_AT_name: source filename
;     DW_AT_comp_dir: working directory
;     DW_AT_low_pc: .text start address
;     DW_AT_high_pc: .text end address
;     DW_AT_stmt_list: offset into .debug_line
```

Gate: .debug_info section passes dwarfdump with no errors.

---

### Step 16.4 — debug/line.s

Line number program (.debug_line):

```asm
; dwarf_line_emit(srcmap_ptr, out_buf)
; → header: version, opcode base, line range, min instr length
; → standard opcodes
; → file name table
; → state machine program: DW_LNS_advance_pc, DW_LNS_advance_line, DW_LNS_copy
```

Gate: dwarfdump --debug-line shows correct file:line mapping for all addresses.

---

### Step 16.5 — debug/die.s, aranges.s, frame.s, str.s

```asm
; die.s     → DW_TAG_subprogram for each labeled proc
; aranges.s → .debug_aranges: address → CU mapping for fast lookup
; frame.s   → .debug_frame: call frame information (CFA rules per instruction)
; str.s     → .debug_str: string table for DWARF attribute strings
```

Gate: all DWARF sections pass dwarfdump. GDB can set breakpoints by source line.

---

### Step 16.6 — debug/dwarf.s — coordinator

```asm
; dwarf_init()
; dwarf_emit(output_buf) → emit all DWARF sections
```

Gate: `./build/gen1/utasm --dwarf main.s -o main && gdb main` → source-level debugging works.

---

### Phase 16 + 17 combined gate

```sh
git commit -m "feat(dwarf): complete DWARF v5 debug info emission"
```

---

# PHASE 17 — Optimizer
**Target: v0.3.0**

---

### Step 17.1 — optimizer/jump.s

Jump shortening — replace 5-byte near jumps with 2-byte short jumps where possible:

```asm
; opt_jump_scan(section_ptr)  → find all jump instructions
; opt_jump_shorten(section_ptr)→ shorten where displacement fits int8
; returns: bytes saved
```

Gate: 100 short jumps in a row → all shortened to 2 bytes.

---

### Step 17.2 — optimizer/nop.s

NOP handling:

```asm
; opt_nop_pad(addr, align)     → emit multi-byte NOP to reach alignment
; opt_nop_remove(section_ptr)  → remove unnecessary NOPs
; multi-byte NOPs: 1-byte 90, 2-byte 66 90, 3-byte 0F 1F 00, etc up to 15 bytes
```

Gate: alignment padding uses correct multi-byte NOP sequences.

---

### Step 17.3 — optimizer/align.s

Alignment optimization:

```asm
; opt_align_section(section_ptr, align) → align section to boundary
; opt_align_label(label_ptr, align)     → align loop targets for performance
```

Gate: function labels aligned to 16 bytes where specified.

---

### Step 17.4 — optimizer/peephole.s

Peephole optimizer — pattern matching on instruction sequences:

```asm
; known patterns:
; MOV RAX, 0        → XOR RAX, RAX (shorter, faster)
; PUSH RBP          → leave alone (don't optimize stack frames)
; MOV RAX, X / MOV RBX, RAX → MOV RBX, X (eliminate redundant move if RAX not used)
; ADD RAX, 1        → INC RAX (debatable — INC has partial flags issue, make optional)

; peephole_scan(section_ptr)  → find + replace all patterns
; peephole_add_pattern(from, to, fn) → register custom pattern
```

Gate: XOR RAX, RAX replaces MOV RAX, 0 in output.

---

### Step 17.5 — optimizer/prefix.s

Redundant prefix removal:

```asm
; prefix_scan(section_ptr)    → find redundant prefixes
; REX prefix without REX fields → remove
; Redundant operand size override → remove
; Duplicate segment override → E526 (already fired by encoder, belt-and-suspenders)
```

Gate: unnecessary REX bytes removed from output.

---

### Step 17.6 — optimizer/size.s

Size reduction passes:

```asm
; size_imm_shrink(section_ptr) → use imm8 where imm32 was emitted conservatively
; size_disp_shrink(section_ptr)→ use disp8 where disp32 was emitted conservatively
```

Gate: after two-pass size reduction, output is minimal size.

---

### Step 17.7 — optimizer/optimizer.s — coordinator

```asm
; optimizer_init()
; optimizer_run(section_list) → run all passes in correct order
; pass order:
;   1. peephole (create optimization opportunities)
;   2. jump shortening (needs to iterate to fixpoint)
;   3. size reductions
;   4. prefix removal
;   5. NOP handling (last — alignment may add NOPs)
;   6. alignment
```

Gate: optimizer reduces a test binary by measurable amount vs unoptimized.

---

### Phase 17 Gate

```sh
echo "0.3.0" > VERSION
git commit -m "release: v0.3.0 — DWARF v5 + optimizer complete"
git tag v0.3.0
```

---

# PHASE 18 — Self-Patching Engine
**Target: v0.4.0**
**Depends on: Phase 17**

---

### Step 18.1 — profiler/rdtsc.s

RDTSC-based timing:

```asm
; rdtsc_read()           → return current TSC value in RAX
; rdtsc_elapsed(start)   → return TSC delta from start
; rdtsc_calibrate()      → calibrate TSC frequency, return cycles/ns
```

Gate: timing measurements reproducible and monotonic.

---

### Step 18.2 — profiler/hotpath.s

Hot path detection:

```asm
; hotpath_init()
; hotpath_enter(id)       → record entry to hot path region
; hotpath_exit(id)        → record exit, update timing stats
; hotpath_get_slowest()   → return id of slowest hot path
; hotpath_report(fd)      → print hot path timing table
```

Gate: calling hotpath_enter/exit 1000 times produces correct timing stats.

---

### Step 18.3 — profiler/report.s and trigger.s

```asm
; profiler_report(fd)     → print full profiling report
; profiler_trigger(id)    → if hot path is slow enough, trigger selfpatch
```

Gate: trigger fires when measured time exceeds threshold.

---

### Step 18.4 — profiler/profiler.s — coordinator

```asm
; profiler_init()
; profiler_start()        → begin profiling session
; profiler_stop()         → end session, trigger analysis
```

---

### Step 18.5 — selfpatch/patchmap.s

Patch point registry — predefined locations that can be patched:

```asm
struc PatchPoint
    .id          dw 0    ; unique patch point ID
    .offset      dq 0    ; offset in binary
    .size        db 0    ; size of patchable region in bytes
    .original    dq 0    ; ptr to original bytes (for rollback)
    .replacement dq 0    ; ptr to replacement bytes
    .applied     db 0    ; 1 if currently patched
endstruc

; patchmap_register(id, offset, size, original, replacement)
; patchmap_lookup(id)    → return PatchPoint ptr
; patchmap_count()       → return registered patch count
```

Gate: register 10 patch points, look up all 10.

---

### Step 18.6 — selfpatch/validate.s

Safety validation before applying any patch:

```asm
; patch_validate(point_ptr)
; checks:
;   - patch region within binary bounds
;   - patch size matches expected
;   - original bytes match current bytes (not double-patched)
;   - patch region not currently executing (stack inspection)
;   - replacement bytes are valid x86-64 instructions
; returns: 1 if safe, 0 if unsafe
```

Gate: invalid patch (wrong original bytes) → validate returns 0.

---

### Step 18.7 — selfpatch/apply.s

Patch application:

```asm
; patch_apply(point_ptr)
; → validate first (abort if unsafe)
; → mprotect region to PROT_READ|PROT_WRITE|PROT_EXEC
; → copy replacement bytes over original bytes
; → mprotect back to PROT_READ|PROT_EXEC
; → flush instruction cache (on non-x86 architectures)
; → mark patch as applied
; returns: 1 on success, 0 on failure
```

Gate: patch applied → function at patched address executes new code.

---

### Step 18.8 — selfpatch/rollback.s

```asm
; patch_rollback(point_ptr)
; → validate patch is currently applied
; → restore original bytes
; → mark as not applied
; patch_rollback_all()    → rollback all applied patches
```

Gate: rollback restores original behavior.

---

### Step 18.9 — selfpatch/log.s

```asm
; patch_log_init(path)              → open log file
; patch_log_entry(id, result, ns)   → log patch application
; patch_log_close()
```

Gate: patch log file produced with correct entries.

---

### Step 18.10 — selfpatch/selfpatch.s — coordinator

```asm
; selfpatch_init()
; selfpatch_run(profiler_data_ptr) → analyze profile, apply beneficial patches
; → get slowest hot path from profiler
; → look up patch point for that path
; → validate + apply
; → re-measure after patch
; → if no improvement: rollback
; → log result
```

---

### Phase 18 Gate

```sh
bash scripts/test.sh integration/selfpatch
# basic.s, rollback.s, perf.s all pass

echo "0.4.0" > VERSION
git commit -m "release: v0.4.0 — self-patching engine complete"
git tag v0.4.0
```

---

# PHASE 19 — Built-in Tools
**Target: v0.5.0**
**Depends on: Phase 18**

---

### Step 19.1 — tools/disasm/

A disassembler using the same ISA tables as the encoder (consistency guaranteed):

**decode.s** — instruction decoding (reverse of encoding):
```asm
; disasm_decode(bytes_ptr, len, instr_ptr) → decode one instruction, return byte count
```

**print.s** — instruction printing:
```asm
; disasm_print(instr_ptr, addr, out_buf)
; → "  401000:  48 89 c1     mov    rcx, rax"
```

**simd.s** — SIMD instruction decoding (VEX/EVEX prefix parsing):
```asm
; disasm_decode_vex(bytes_ptr, instr_ptr) → decode VEX-encoded instruction
; disasm_decode_evex(bytes_ptr, instr_ptr)→ decode EVEX-encoded instruction
```

**disasm.s** — entry point:
```asm
; disasm_file(path, start_addr, out_fd) → disassemble ELF or flat binary
; invoked by: utasm --disasm file.s
```

Gate: `./utasm --disasm tests/integration/hello/amd64.s -o hello && utasm --list-disasm hello` produces readable disassembly verified against objdump.

---

### Step 19.2 — tools/inspector/

Object file inspector:

**elf.s** — ELF inspector:
```asm
; inspect_elf(path, out_fd)
; → print ELF header fields
; → print all section headers
; → print program headers
; → print symbol table
; → print relocations
```

**pe.s** — PE32+ inspector
**upk.s** — .upk package inspector

**inspector.s** — entry point:
```asm
; invoked by: utasm --inspect file.o
```

Gate: `utasm --inspect build/gen1/utasm` prints readable output matching readelf.

---

### Step 19.3 — tools/symdump/

```asm
; symdump.s → entry point
; fmt.s     → output formatting
; invoked by: utasm --symdump file.o

; prints symbol table:
; NAME                  TYPE    BIND    SECTION   VALUE    SIZE
; _start                FUNC    GLOBAL  .text     00401000    0
```

Gate: symbols from test binary listed correctly.

---

### Phase 19 Gate

```sh
echo "0.5.0" > VERSION
git commit -m "release: v0.5.0 — built-in tools complete — disasm, inspector, symdump"
git tag v0.5.0
```

---

# PHASE 20 — Fuzz, Stress, Performance
**Target: v1.0.0 prerequisite**
**Depends on: Phase 19**

---

### Step 20.1 — Fuzz testing

```sh
bash scripts/test.sh fuzz
```

Run fuzzer for minimum 24 hours. Fix every crash. Add every crash input as a regression test. Repeat until clean for 24 hours.

Invariants verified by fuzzer:
- No segfault regardless of input
- No hang (timeout.s enforces 5s limit)
- Always exits 0 or 1
- Error messages always have valid line/col

---

### Step 20.2 — Stress testing

```sh
bash scripts/test.sh stress
```

All seven stress tests must pass:
- deep_macro.s: 999-level macro nesting completes
- long_expr.s: 10,000 term expression evaluates correctly
- many_symbols.s: 1M symbols insert and resolve
- many_sections.s: 65535 sections in output ELF
- large_binary.s: maximum output size without corruption
- many_errors.s: 10,000 errors reported without crash
- parallel.s: 64 parallel assembly jobs produce identical output

---

### Step 20.3 — Performance benchmarks

```sh
bash scripts/test.sh perf
```

Targets that must be met:

| Metric | Target | How to measure |
|---|---|---|
| Lexer throughput | > 500 MB/s | bench_lexer.s with 100MB input |
| Encoder throughput | > 5M instr/sec | bench_encoder.s with 5M MOV instructions |
| Self-host time | < 2 seconds | bench_selfhost.s: time to assemble utasm itself |
| 100k line file | < 1 second | bench_large.s |

If any target is missed, profile with profiler/ module and optimize the hot path.

---

### Step 20.4 — Full regression suite

```sh
bash scripts/test.sh regression
```

All regression tests pass. Zero exceptions.

---

# PHASE 21 — Pre-Launch
**Target: v1.0.0**

---

### Step 21.1 — Documentation completeness audit

Verify every file in README.md has a corresponding entry in docs/:

```
docs/errors.md      → every E1xx–E30xx code documented with example
docs/warnings.md    → every W1xx–W20xx code documented
docs/hints.md       → every H1xx–H5xx code documented
docs/cpu_profiles.md→ every CPU profile documented with feature list
docs/dev_guide.md   → how to add instruction, error, profile, format
ARCHITECTURE.md     → major design decisions with rationale
CONTRIBUTING.md     → code style, naming, comment requirements
CHANGELOG.md        → every version entry complete
```

Gate: no undocumented error code. No undocumented CPU profile. No missing CHANGELOG entry.

---

### Step 21.2 — Final full test suite run

```sh
bash scripts/test.sh
```

Zero failures. Zero warnings treated as errors missed. Every category green.

```
[unit/lexer]         17 passed   0 failed
[unit/parser]        35 passed   0 failed
[unit/macro]         27 passed   0 failed
[unit/symtable]      15 passed   0 failed
[unit/expr]          19 passed   0 failed
[unit/encoder/x86]   78 passed   0 failed
[unit/encoder/simd]  27 passed   0 failed
[unit/encoder/a64]   11 passed   0 failed
[unit/encoder/rv64]   7 passed   0 failed
[unit/linker]        19 passed   0 failed
[unit/output]        18 passed   0 failed
[error]             112 passed   0 failed
[warning]            13 passed   0 failed
[integration]        22 passed   0 failed
[regression]         NNN passed  0 failed
[stress]              7 passed   0 failed
[perf]                9 passed   0 failed
══════════════════════════════════════
    TOTAL: NNN Passed | 0 Failed
══════════════════════════════════════
```

---

### Step 21.3 — Final bootstrap verification

```sh
bash scripts/bootstrap.sh
```

Gen1 == Gen2 bit-identical. No exceptions.

---

### Step 21.4 — Cross-architecture smoke test

```sh
bash scripts/test.sh integration/crossarch
```

Both aarch64 and riscv64 hello world programs run correctly under QEMU.

---

### Step 21.5 — Tag v1.0.0

```sh
echo "1.0.0" > VERSION
git add -A
git commit -m "release: v1.0.0 — public launch"
git tag v1.0.0
git push origin main --tags
```

**utasm 1.0.0 is public.**

---

## Daily Working Rule

```
Every day:
├── Pick one file from current phase
├── Read its entry in this document
├── Write the code
├── Write its tests immediately after
├── Run the tests: bash scripts/test.sh <category>
├── All tests passing? → commit
├── Update CHANGELOG.md
└── Never end a day with failing tests

Completion checklist per file:
[ ] Code written
[ ] Assembles cleanly
[ ] Tests written
[ ] Tests passing
[ ] Error codes documented in docs/errors.md
[ ] CHANGELOG entry added
[ ] Committed with meaningful message
```

---

## Git Commit Message Format

```
type(scope): description

Types:
  feat     → new feature or file
  fix      → bug fix
  test     → test additions
  docs     → documentation only
  refactor → code restructure, no behavior change
  perf     → performance improvement
  release  → version tag commit

Examples:
  feat(lexer): add UTF-8 validation — E115 fires on invalid sequences
  fix(encoder): REX.B not set for R8–R15 base registers
  test(error): add E5xx encoder error test suite
  release: v0.1.0 — self-hosting achieved
```

---

## Version Summary

```
v0.0.1  →  Restructure        Phase 0
v0.1.0  →  Self-Hosting       Phase 13     ← first major milestone
v0.2.0  →  Multi-Arch         Phase 15     ← public launch target #1
v0.3.0  →  DWARF + Optimizer  Phase 17
v0.4.0  →  Self-Patching      Phase 18
v0.5.0  →  Built-in Tools     Phase 19
v1.0.0  →  Public Launch      Phase 21     ← fully featured
```

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
