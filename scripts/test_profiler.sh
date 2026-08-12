#!/bin/bash
# ============================================================================
# File        : scripts/test_profiler.sh
# Project     : utasm
# Description : Build & execute the standalone manual test suite for the
#               Profiler subsystem.
# ============================================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}[+] Building UtkarshaLab Profiler Engine Test Suite...${NC}"

mkdir -p build/tests

# Profiler source files
PROFILER_SRCS=(
    "profiler/state.s"
    "profiler/strings.s"
    "profiler/rdtsc.s"
    "profiler/phase.s"
    "profiler/hotpath.s"
    "profiler/rank.s"
    "profiler/profiler.s"
    "profiler/fmt.s"
    "profiler/table.s"
    "profiler/report.s"
    "profiler/trigger.s"
    "lib/arena.s"
    "tests/unit/test_profiler.s"
)

OBJS=()

for src in "${PROFILER_SRCS[@]}"; do
    obj="build/tests/$(basename "$src" .s).o"
    echo "    [*] Assembling $src -> $obj"
    # -d__NASM__=1 selects the struc/field emulation macros in include/macro.inc;
    # without it every "field" line is an unknown instruction.
    nasm -d__NASM__=1 -I./ -f elf64 "$src" -o "$obj"
    OBJS+=("$obj")
done

echo -e "${BOLD}[+] Linking test_profiler executable...${NC}"
ld "${OBJS[@]}" -o build/tests/test_profiler

echo -e "${BOLD}[+] Executing test_profiler...${NC}"
./build/tests/test_profiler

echo -e "${GREEN}[+] Profiler Engine manual validation complete.${NC}"
