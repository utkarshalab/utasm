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
| `io_open`, `io_create`, `io_close` | open, close | `io_create`: an output, named in its error |
| `io_read`, `io_read_full` | read | `_full` loops until all bytes are read |
| `io_write`, `io_write_byte` | write | `io_write` loops until all is written |
| `io_lseek`, `io_file_size` | lseek, fstat | the size: seek to the end; a directory: `EXIT_FILE_IS_DIR` |
| `io_mmap`, `io_munmap` | mmap, munmap | the source file is mmapped, not read |
| `io_ftruncate` | ftruncate | object/ubf (the image's size) |

Nothing here prints. A failure is an `EXIT_*` code saying what failed -
`EXIT_FILE_NOT_FOUND`, `EXIT_FILE_PERM`, `EXIT_FILE_IS_DIR`,
`EXIT_FILE_READ`, `EXIT_FILE_WRITE`, `EXIT_IO_ERROR` (any other errno),
`EXIT_OOM` - and the caller, which knows the file, names it in the message
("`x' is a directory, not a file"). `io_create` opens an output for
writing and names it itself when it cannot ("unable to open output file
`x'"). `io_file_size` tells a directory from a file (`fstat`): a
directory opens, but mapping it failed unseen and utasm crashed.
`io_mmap` of length 0 maps nothing and succeeds (an empty file).

## Memory (`mem.s`)

| Function | What it does |
| --- | --- |
| `heap_alloc` | `arena_alloc` from `global_arena` - used by `lib/string.s` (`str_dup` & co.) |
| `mem_map`, `mem_unmap`, `mem_protect`, `mem_alloc_exec`, `mem_lock`, `mem_unlock`, `mem_advise`, `heap_free` | mmap, munmap, mprotect, mlock, madvise wrappers (and a `heap_free` that frees nothing) - not called today: kept for the self-patching engine, `src/planned/selfpatch/`, which needs executable memory |

## Files

| File | Lines | What is in it |
| --- | --- | --- |
| `io.s` | 501 | the file calls above |
| `mem.s` | 292 | the memory calls and the bump allocator |
| `syscall.s` | 4 | placeholder: a raw system call layer (`io.s` / `mem.s` do it directly) |
| `qemu.s` | 0 | empty: meant for running cross-architecture tests under QEMU (tests/run.sh does that from the shell) |

## Entry points

| Symbol | Used by |
| --- | --- |
| `io_*` | object/ (writing outputs), frontend/preproc (includes), tools/inspect (reading), main/, core/known.s, debug/, link/ |
| `heap_alloc` | lib/string.s |

## Depends on

diag/codes.s (`error_set_subject`, for `io_create`), lib/ (strings), main/.

## What is left

The Utkarsha OS port
of this layer when utasm runs on its own OS.

## Tests

Indirect: every suite reads sources and writes outputs through here;
*command line* covers missing / unreadable files (`no such file`,
`permission denied`).
