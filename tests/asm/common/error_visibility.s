// ============================================================================
// TEST: tests/asm/common/error_visibility.s
// Suite: Common Parser Security
// Purpose: Verify detection of symbol visibility binding conflicts.
// Expected: EXIT_VISIBILITY_CONFLICT.
// ============================================================================

global my_symbol
my_symbol:
    nop

local my_symbol   // Conflict: Cannot demote global symbol to local
