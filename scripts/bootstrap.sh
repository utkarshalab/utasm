#!/bin/bash
# ============================================================================
# File        : scripts/bootstrap.sh
# Project     : utasm
# Description : Stage 1 (Gen0) and Stage 2 (Gen1) Bootstrapping Pipeline
#               This script initiates the Millennial Inversion.
# ============================================================================

set -e

echo "[+] Initiating UtkarshaLab Bootstrap Sequence..."

mkdir -p build/gen0
mkdir -p build/gen1

# ----------------------------------------------------------------------------
# PHASE 1: GEN0 COMPILATION (via NASM)
# ----------------------------------------------------------------------------
echo "[+] PHASE 1: Assembling Gen0 Compiler via NASM..."

# Find all .s files in modular directories, plus root-level utasm.s and cli.s
src_files="$(find frontend middle backend core error cpu debug optimizer selfpatch profiler io lib host tools -name "*.s") utasm.s cli.s"
obj_files=""

for src_file in $src_files; do
    # Preserve directory structure in build/gen0
    obj_file="build/gen0/${src_file%.s}.o"
    mkdir -p "$(dirname "$obj_file")"
    nasm -d__NASM__=1 -g -F dwarf -I./ -f elf64 "$src_file" -o "$obj_file"
    obj_files="$obj_files $obj_file"
done

# Link all object files into the Gen0 binary
ld -o build/gen0/utasm $obj_files

echo "[+] Gen0 Compilation Successful."
ls -l build/gen0/utasm

# ----------------------------------------------------------------------------
# PHASE 2: GEN1 SELF-HOSTING (utasm -> utasm)
# ----------------------------------------------------------------------------
echo "[+] PHASE 2: Initiating Self-Hosting Ascent (Gen1)..."

obj_files_gen1=""
for src_file in $src_files; do
    obj_file="build/gen1/${src_file%.s}.o"
    mkdir -p "$(dirname "$obj_file")"
    echo "Compiling $src_file..."
    # Use the Gen0 binary to compile the source
    ./build/gen0/utasm -f elf64 "$src_file" -o "$obj_file"
    obj_files_gen1="$obj_files_gen1 $obj_file"
done

# Link the Gen1 object files
ld -o build/gen1/utasm $obj_files_gen1

echo "[+] Gen1 Compilation Successful."
ls -l build/gen1/utasm

# ----------------------------------------------------------------------------
# PHASE 3: BINARY PARITY VERIFICATION (GEN0 vs GEN1)
# ----------------------------------------------------------------------------
echo "[+] PHASE 3: Verifying Binary Parity (Gen0 vs Gen1)..."

if cmp -s build/gen0/utasm build/gen1/utasm; then
    echo "[!] Gen0 and Gen1 are identical."
else
    echo "[-] WARNING: Gen0 and Gen1 differ. (This is expected as Gen0 is assembled by NASM)."
fi

# ----------------------------------------------------------------------------
# PHASE 4: GEN2 SELF-HOSTING (Gen1 -> Gen2)
# ----------------------------------------------------------------------------
echo "[+] PHASE 4: Initiating Stage 2 Self-Hosting Ascent (Gen2)..."

mkdir -p build/gen2
obj_files_gen2=""
for src_file in $src_files; do
    obj_file="build/gen2/${src_file%.s}.o"
    mkdir -p "$(dirname "$obj_file")"
    # Use the Gen1 binary to compile the source
    ./build/gen1/utasm -f elf64 "$src_file" -o "$obj_file"
    obj_files_gen2="$obj_files_gen2 $obj_file"
done

# Link the Gen2 object files
ld -o build/gen2/utasm $obj_files_gen2

echo "[+] Gen2 Compilation Successful."
ls -l build/gen2/utasm

# ----------------------------------------------------------------------------
# PHASE 5: GEN1 vs GEN2 STRICT PARITY VERIFICATION
# ----------------------------------------------------------------------------
echo "[+] PHASE 5: Verifying strict parity between Gen1 and Gen2..."

if cmp -s build/gen1/utasm build/gen2/utasm; then
    echo "[!] MILLENNIAL INVERSION COMPLETE: Gen1 and Gen2 are 100% byte-for-byte identical!"
    echo "[!] Absolute Binary Parity and Self-Hosting Achieved."
else
    echo "[-] ERROR: Gen1 and Gen2 binaries differ! Self-hosting failed."
    exit 1
fi

echo "[+] Sequence Terminated Successfully."
