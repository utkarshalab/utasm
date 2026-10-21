# platform/ — system calls: files and memory

utasm uses no libc. Everything it asks of the operating system goes
through here as raw x86-64 Linux system calls (`syscall`, numbers from
`include/constant.inc` / `include/syscall.inc`), each wrapped so the rest
of utasm sees utasm's convention: `rax` = `EXIT_OK` or an `EXIT_*` code,
`rdx` = the result.

This is also the layer that changes when utasm runs **on Utkarsha OS**
itself: its file and memory calls are all here (and `lib/arena.s` on top
of `mem.s`).

## File I/O (`io.s`)

| Function | System call | Notes |
| --- | --- | --- |
| `io_open`, `io_close` | open, close | |
| `io_read`, `io_read_full` | read | `_full` loops until all bytes are read |
| `io_write`, `io_write_full`, `io_write_byte` | write | `_full` loops until all are written |
| `io_lseek`, `io_file_size` | lseek | the size: seek to the end |
| `io_mmap`, `io_munmap` | mmap, munmap | the source file is mmapped, not read |
| `io_ftruncate` | ftruncate | object/ubf (the image's size) |
| `io_exists` | access | unused |

A failure keeps the errno for the message (`error_new_from_errno`,
diag/error.s): "no such file", "permission denied".

## Memory (`mem.s`)

| Function | What it does |
| --- | --- |
| `mem_map` | anonymous mmap (the bump allocator's pages) |
| `heap_alloc`, `heap_free` | a bump allocator on top — used by `lib/string.s` (`str_dup` & co.); the arena (`lib/arena.s`) reserves its own memory |
| `mem_unmap`, `mem_protect`, `mem_alloc_exec`, `mem_lock`, `mem_unlock`, `mem_advise` | munmap, mprotect, mlock, madvise wrappers — unused today (kept for the self-patching engine, `src/planned/selfpatch/`, which needs executable memory) |

## io_uring (`uring.s`) — unused

`uring_init`, `uring_submit_and_wait`, `uring_write_async`: an io_uring
ring for asynchronous writes. **Nothing calls them**: every file is read
by mmap and written with `write`. Either wire it into the output writer
(large outputs) or remove it.

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `io.s` | 525 | the file calls above |
| `mem.s` | 292 | the memory calls and the bump allocator |
| `uring.s` | 138 | io_uring (unused) |
| `syscall.s` | 4 | placeholder: a raw system call layer (`io.s` / `mem.s` do it directly) |
| `qemu.s` | 0 | empty: meant for running cross-architecture tests under QEMU (tests/run.sh does that from the shell) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `io_*` | object/ (writing outputs), frontend/preproc (includes), tools/inspect (reading), main/, core/known.s, debug/, link/ |
| `heap_alloc`, `heap_free` | lib/string.s |

## Depends on

diag/error.s (errno messages), lib/ (strings), main/.

## What is left

Deciding about `uring.s` (use it or remove it), and the Utkarsha OS port
of this layer when utasm runs on its own OS.

## Tests

Indirect: every suite reads sources and writes outputs through here;
*command line* covers missing / unreadable files (`no such file`,
`permission denied`).
