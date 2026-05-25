#!/bin/bash
# ============================================================================
# File        : scripts/bootstrap_arm.sh
# Project     : utasm
# Description : ARM-compatible Bootstrap Sequence (via QEMU emulation)
# ============================================================================

set -e

echo "[+] Initiating ARM-Compatible Bootstrap Sequence..."

# Check for required tools
if ! command -v qemu-x86_64-static &> /dev/null && ! command -v qemu-x86_64 &> /dev/null; then
    echo "[-] ERROR: qemu-x86_64 not found. Install with: sudo apt install qemu-user-static"
    exit 1
fi

if ! command -v x86_64-linux-gnu-ld &> /dev/null; then
    echo "[-] ERROR: x86_64-linux-gnu-ld not found. Install with: sudo apt install binutils-x86-64-linux-gnu"
    exit 1
fi

QEMU_EXEC=$(command -v qemu-x86_64-static || command -v qemu-x86_64)
LD_EXEC="x86_64-linux-gnu-ld"

mkdir -p build/gen0
mkdir -p build/gen1

# ----------------------------------------------------------------------------
# PHASE 1: GEN0 COMPILATION (via NASM)
# ----------------------------------------------------------------------------
echo "[+] PHASE 1: Assembling Gen0 Compiler via NASM..."

src_files="$(find frontend middle backend core error cpu debug optimizer selfpatch profiler io lib host tools -name "*.s") utasm.s cli.s"
obj_files=""

for src_file in $src_files; do
    obj_file="build/gen0/$(basename "${src_file%.s}.o")"
    nasm -f elf64 "$src_file" -o "$obj_file"
    obj_files="$obj_files $obj_file"
done

# Link using x86_64 cross-linker
$LD_EXEC -o build/gen0/utasm $obj_files

echo "[+] Gen0 Compilation Successful."

# ----------------------------------------------------------------------------
# PHASE 2: GEN1 SELF-HOSTING (utasm -> utasm)
# ----------------------------------------------------------------------------
echo "[+] PHASE 2: Initiating Self-Hosting Ascent (Gen1)..."

obj_files_gen1=""
for src_file in $src_files; do
    obj_file="build/gen1/$(basename "${src_file%.s}.o")"
    # Run x86_64 Gen0 via QEMU
    $QEMU_EXEC ./build/gen0/utasm -f elf64 "$src_file" -o "$obj_file"
    obj_files_gen1="$obj_files_gen1 $obj_file"
done

# Link using x86_64 cross-linker
$LD_EXEC -o build/gen1/utasm $obj_files_gen1

echo "[+] Gen1 Compilation Successful."
echo "[+] ARM-Compatible Sequence Terminated Successfully."
