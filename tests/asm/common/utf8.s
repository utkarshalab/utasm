// Tests for UTF-8 Identifier Sanitization
[SECTION .text]
global _start

_start:
    mov rax, 60
    mov rdi, 0
    syscall

// UTF-8 Identifiers
Σ_total:
    dq 0

// Preprocessor using UTF-8
%define π 3
    mov rax, π

// Malformed UTF-8 test (this should trigger an error if we were to compile it)
// We can't easily test the error path without running the assembler and checking output.
// But we can check if it assembles correctly for valid UTF-8.
