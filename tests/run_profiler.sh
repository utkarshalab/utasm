#!/bin/bash
# ============================================================================
# File        : tests/run_profiler.sh
# Project     : utasm
# Description : Build & execute the standalone manual test suite for the
#               Profiler subsystem.
# ============================================================================

set -e
cd "$(dirname "$0")/.."                    # the repository root

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}[+] Building UtkarshaLab Profiler Engine Test Suite...${NC}"

mkdir -p build/tests

# Profiler source files
PROFILER_SRCS=(
    "src/profile/state.s"
    "src/profile/strings.s"
    "src/profile/rdtsc.s"
    "src/profile/phase.s"
    "src/profile/hotpath.s"
    "src/profile/rank.s"
    "src/profile/profiler.s"
    "src/profile/fmt.s"
    "src/profile/table.s"
    "src/profile/report.s"
    "src/profile/trigger.s"
    "src/lib/arena.s"
    "tests/unit/profiler/test_profiler.s"
)

OBJS=()

for src in "${PROFILER_SRCS[@]}"; do
    obj="build/tests/$(basename "$src" .s).o"
    echo "    [*] Assembling $src -> $obj"
    # -d__NASM__=1 selects the struc/field emulation macros in src/include/macro.inc;
    # without it every "field" line is an unknown instruction.
    nasm -d__NASM__=1 -I./ -f elf64 "$src" -o "$obj"
    OBJS+=("$obj")
done

echo -e "${BOLD}[+] Linking test_profiler executable...${NC}"
ld "${OBJS[@]}" -o build/tests/test_profiler

echo -e "${BOLD}[+] Executing test_profiler...${NC}"
./build/tests/test_profiler

echo -e "${GREEN}[+] Profiler Engine manual validation complete.${NC}"
