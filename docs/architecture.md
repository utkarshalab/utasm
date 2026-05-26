# utasm — Architecture

> Why each major decision was made.
> The README says what. This document says why.

---

## Why Assembly?

utasm is written entirely in x86-64 assembly because:

1. **Self-hosting proof**: An assembler written in C needs a C compiler. An assembler written in assembly only needs itself after the first bootstrap — total toolchain sovereignty.
2. **Zero dependencies**: No libc, no runtime, no ABI surprises. The binary does exactly what the source says.
3. **Performance control**: Every hot path is hand-optimized. No compiler can beat a human who knows the exact access patterns.
4. **Dogfooding**: utasm assembles utasm. Every feature is immediately exercised at maximum stress.

---

## Why Three Architectures?

x86-64, AArch64, and RISC-V 64 cover:
- The entire server market (x86-64, increasingly AArch64)
- All modern mobile/embedded (AArch64)
- The open sovereign future (RISC-V 64)

A single-arch assembler is a tool. A tri-arch assembler is a platform.

RISC-V was chosen over MIPS/PowerPC because it is the only genuinely open ISA with no legacy encumbrance — the right foundation for sovereign kernel development.

---

## Why Self-Patching?

Static code optimized at compile time misses runtime information. The profiler measures real hot paths on real workloads. The self-patch engine rewrites those paths in the running binary without restart.

This is the same technique used by JIT compilers, but applied to an assembler that runs itself. The result: Gen1 gets faster the more it runs, without recompilation.

---

## Layered Architecture

```
utasm.s / cli.s          ← entry, CLI dispatch
     │
     ▼
frontend/                ← source text → tokens → AST
  lexer/                   character stream → token stream
  parser/                  token stream → parse tree
  macro/                   preprocessing, expansion, conditionals
     │
     ▼
middle/                  ← AST → validated, resolved IR
  semantic/                type checking, operand validation
  symtable/                O(1) hash table, forward references
  expr/                    constant folding, reloc expressions
     │
     ▼
backend/                 ← IR → binary output
  encoder/                 instruction → bytes (arch-specific)
  isa/                     instruction tables per arch
  linker/                  section layout, relocation, symbol resolution
  output/                  ELF64 / PE32+ / flat / .upk emission
     │
     ▼
error/                   ← runs at all stages, independent of pipeline
cpu/                     ← CPU profile validation, feature flags
debug/                   ← DWARF v5 emission
optimizer/               ← post-encoding passes
selfpatch/               ← runtime binary modification
profiler/                ← RDTSC-based hot path measurement
```

### Why This Layering?

**Error module built first, zero dependencies**: errors must work even when everything else is broken. It depends on nothing.

**Macro/preprocessor before parser**: macros expand before the parser sees the token stream. This is the NASM model — simpler than C's integrated preprocessor.

**Symtable in middle, not frontend**: symbols can be defined after use (forward references). Resolution happens after the full file is parsed.

**Encoder per-arch, not per-instruction-class**: x86/AArch64/RISC-V have fundamentally different encoding philosophies. Sharing code between them creates more coupling than benefit.

---

## Why ELF64 First?

ELF64 is the universal relocatable object format on Linux. Every other tool (ld, objdump, readelf, gdb) speaks it. PE32+ is second because UEFI is the only remaining path to bare-metal x86-64 without proprietary firmware tools.

Flat binary is third — needed for boot sectors and raw firmware images.

`.upk` (UtkarshaLab Package) is the sovereign package format: signed, versioned, dependency-aware, designed for the UtkarshaLab kernel ecosystem.

---

## Why io_uring?

Traditional read/write syscalls block. For large source files (100k+ lines), async I/O allows the lexer to process already-read data while the kernel fetches the next chunk. This is the difference between 1.2s and 0.4s on a 50MB source file.

io_uring was chosen over AIO because it supports both reads and writes with a single ring interface, has lower latency, and is the direction Linux I/O is moving.

---

## Why FNV-1a for Hashing?

FNV-1a is:
- Branchless — the entire hash fits in a tight loop with no conditionals
- Cache-friendly — processes one byte at a time sequentially
- Fast for short strings (symbol names are typically 4–16 chars)
- Simple to implement in 8 instructions

xxHash would be faster for bulk data (>64 bytes). For symbol table lookups where names are short and the hash is called millions of times, FNV-1a's simplicity wins because it keeps the instruction cache hot.

---

## Why Quadratic Probing?

Linear probing clusters. Double hashing requires two hash functions. Quadratic probing is the middle ground: simple second probe sequence, good cache behavior, no clustering, one hash function.

The load factor is capped at 50%. Above that, lookup degrades and the table is resized.

---

## Decisions Rejected

| Decision | Rejected Because |
|---|---|
| C for the parser | Breaks self-hosting; requires external compiler forever |
| LLVM backend | 50MB dependency for a tool that must be zero-dependency |
| MIPS as third arch | Dead commercially; RISC-V is the open future |
| Dynamic linking | Adds loader dependency; utasm must run on bare Linux |
| mmap for symbol table | Hash table with probing is O(1); mmap adds OS dependency for the table itself |
| Recursive descent with backtracking | Too slow for 100k-line files; predictive parser with recovery is sufficient |
| Separate linker binary | Integrated linker eliminates IPC overhead and temp file I/O |

---

## Performance Targets

| Metric | Target | Rationale |
|---|---|---|
| Lexer throughput | > 500 MB/s | NASM baseline is ~200 MB/s; 2.5x improvement |
| Encoder throughput | > 5M instr/sec | Saturates typical x86-64 source file density |
| Self-host time | < 2 seconds | Must feel instant on developer hardware |
| 100k line file | < 1 second | Standard large-file benchmark |

---

*UtkarshaLab — Engineering the Foundation of Tomorrow*
