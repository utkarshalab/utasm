// ============================================================================
// TEST: tests/amd64/exception.s
// Suite: AMD64 System
// Purpose: Exception-generating instruction coverage.
//   Covers: BOUND, DIV (div-by-zero path), IDIV, overflow idioms,
//           UD2, alignment-check triggers, page-fault triggers.
//   NOTE: These tests verify *encoding*, not runtime behavior.
//         The assembler must accept these without syntax errors.
// Expected: EXIT_OK (encoding accepted).
// ============================================================================

[SECTION .text]

// ---- UD2: guaranteed invalid instruction encoding ------
ud2

// ---- BOUND: legacy range check (32-bit only, #BR) ------
// bound  eax, [rbx]    // not valid in 64-bit mode — omit

// ---- Division by zero idiom (encoding only) ------------
// The assembler should encode this; CPU will raise #DE at runtime
xor     rdx, rdx       // clear high half
mov     rax, 1
xor     rcx, rcx       // divisor = 0 (would trap)
div     rcx

// signed division with potential overflow
mov     rax, 0x8000000000000000  // INT64_MIN
mov     rdx, -1                  // sign-extend
mov     rcx, -1
idiv    rcx                      // would trap on overflow

// ---- Overflow check idiom ------------------------------
mov     rax, 0x7FFFFFFFFFFFFFFF  // INT64_MAX
add     rax, 1                   // generates OF=1
// into: 32-bit only, not valid in 64-bit mode (NASM rejects it too)

// ---- Stack overflow probe (encoding only) ---------------
sub     rsp, 0x1000              // page boundary probe
mov     rax, [rsp]               // touch the page

// ---- Misaligned access (generates #AC when CR0.AM set) -
// Force misalignment explicitly
lea     rax, [rsp + 1]
movdqa  xmm0, [rax]             // 16-byte aligned requirement — would fault

// ---- Privileged instruction in user mode (#GP) ---------
hlt                              // ring-3 execution would trap
rdmsr                            // ring-3 would trap

// ---- Segment-limit violation idiom (conceptual encoding) -
// These are valid encodings; OS protects execution
mov     rax, [fs:0]              // GS/FS-relative (valid in user mode)
mov     rbx, [gs:0]
