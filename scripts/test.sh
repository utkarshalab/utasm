#!/bin/bash
# ============================================================================
# File        : scripts/test.sh
# Project     : utasm
# Description : Test Harness for instruction suite validation.
#               Executes the utasm compiler against all payloads in tests/.
# ============================================================================

set -e

# ANSI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BOLD}[+] Initiating UtkarshaLab Test Harness...${NC}"

UTASM_BIN="build/gen1/utasm"

if [ ! -f "$UTASM_BIN" ]; then
    echo -e "${RED}[-] CRITICAL ERROR: utasm Gen1 binary not found. Run bootstrap.sh first.${NC}"
    exit 1
fi

mkdir -p build/tests
FAILED=0
PASSED=0
TOTAL=0

echo -e "${BOLD}[+] Executing Global Test Matrix...${NC}"

# Use find to get all .s files recursively in tests/
test_files=$(find tests -name "*.s")

for test_file in $test_files; do
    ((TOTAL++))
    basename=$(basename "$test_file" .s)
    dirname=$(dirname "$test_file")
    arch="amd64" # Default
    
    # Simple architecture detection based on directory
    if [[ "$test_file" == *"aarch64"* ]]; then
        arch="aarch64"
    elif [[ "$test_file" == *"riscv64"* ]]; then
        arch="riscv64"
    elif [[ "$test_file" == *"amd64"* ]]; then
        arch="amd64"
    fi

    echo -n "    [*] [$arch] Assembling $basename... "
    
    # Determine output format and flags
    is_executable=0
    if [[ "$basename" == "hello_"* ]]; then
        is_executable=1
    fi

    # Run utasm
    set +e
    if [ $is_executable -eq 1 ]; then
        $UTASM_BIN -arch "$arch" -f elf64 --standalone "$test_file" -o "build/tests/$basename" > /dev/null 2>&1
    else
        $UTASM_BIN -arch "$arch" -f elf64 "$test_file" -o "build/tests/$basename.o" > /dev/null 2>&1
    fi
    exit_code=$?
    set -e

    # Determine if this is a negative test (expected to fail)
    is_negative=0
    if [[ "$basename" == "error_"* ]]; then
        is_negative=1
    fi

    if [ $is_negative -eq 1 ]; then
        if [ $exit_code -ne 0 ]; then
            echo -e "${GREEN}OK (Expected Failure)${NC}"
            ((PASSED++))
        else
            echo -e "${RED}FAILED (Should have failed)${NC}"
            ((FAILED++))
        fi
    else
        if [ $exit_code -eq 0 ]; then
            # Phase 2: Execution Validation (if it's an executable)
            if [ $is_executable -eq 1 ]; then
                echo -n "Running... "
                runner=""
                if [ "$arch" == "aarch64" ]; then
                    runner="qemu-aarch64"
                elif [ "$arch" == "riscv64" ]; then
                    runner="qemu-riscv64"
                fi
                
                set +e
                if [ -n "$runner" ]; then
                    if command -v "$runner" >/dev/null 2>&1; then
                        $runner "./build/tests/$basename" > /dev/null 2>&1
                    else
                        echo -n "[$runner missing] "
                        (exit 0) # Skip execution check
                    fi
                else
                    "./build/tests/$basename" > /dev/null 2>&1
                fi
                run_exit_code=$?
                set -e
                
                if [ $run_exit_code -eq 0 ]; then
                    echo -e "${GREEN}OK${NC}"
                    ((PASSED++))
                else
                    echo -e "${RED}EXECUTION FAILED${NC}"
                    ((FAILED++))
                fi
            else
                echo -e "${GREEN}OK${NC}"
                ((PASSED++))
            fi
        else
            echo -e "${RED}FAILED${NC}"
            ((FAILED++))
            echo -e "${RED}    [!] Diagnostic Output for $test_file:${NC}"
            $UTASM_BIN -arch "$arch" -f elf64 "$test_file" -o "build/tests/$basename.o" || true
        fi
    fi
done

echo "============================================================================"
echo -e "    ${BOLD}TEST RESULTS: ${GREEN}$PASSED Passed${NC} | ${RED}$FAILED Failed${NC} | ${BOLD}Total: $TOTAL${NC}"
echo "============================================================================"

if [ $FAILED -ne 0 ]; then
    echo -e "${RED}[-] VALIDATION FAILED: Architectural instability detected in encoder.${NC}"
    exit 1
else
    echo -e "${GREEN}[+] VALIDATION SUCCESSFUL: Absolute architectural parity achieved.${NC}"
    exit 0
fi
