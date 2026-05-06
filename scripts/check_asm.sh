#!/bin/bash
# Quick assembly-check for all .s files
set -e
cd "$(dirname "$0")/.."

ERRORS=0
for f in $(find src -name "*.s" | sort); do
    out=$(nasm -I./ -f elf64 "$f" -o /dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "[FAIL] $f"
        echo "$out"
        ERRORS=$((ERRORS + 1))
    else
        echo "[OK]   $f"
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "All files assembled successfully."
else
    echo "$ERRORS file(s) had errors."
    exit 1
fi
