#!/bin/bash
# test_common.sh - Common functions for M65832 test runners
#
# Source this file in test scripts:
#   source ./test_common.sh

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
LLVM_ROOT="$PROJECTS_DIR/llvm-m65832"
LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
    LLVM_BUILD="$LLVM_BUILD_FAST"
else
    LLVM_BUILD="$LLVM_BUILD_DEFAULT"
fi
EMU="$(dirname "$SCRIPT_DIR")/m65832emu"
BUILD_DIR="$SCRIPT_DIR/build"

# Tools
CLANG="$LLVM_BUILD/bin/clang"
LLD_FAST="$LLVM_BUILD_FAST/bin/ld.lld"
LLD_DEFAULT="$LLVM_BUILD_DEFAULT/bin/ld.lld"
if [ -x "$LLD_FAST" ]; then
    LLD="$LLD_FAST"
else
    LLD="$LLD_DEFAULT"
fi

# Newlib paths (if installed)
SYSROOT="$PROJECTS_DIR/m65832-sysroot/m65832-elf"

# Create build directory
mkdir -p "$BUILD_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#
# compile_standalone - Compile a test without any libc
#
# Usage: compile_standalone <source.c>
# Output: build/<name>.elf
#
compile_standalone() {
    local src="$1"
    local name=$(basename "$src" .c)
    local obj="$BUILD_DIR/${name}.o"
    local elf="$BUILD_DIR/${name}.elf"
    
    # Compile
    "$CLANG" -target m65832-elf -O2 -ffreestanding -nostdlib \
        -c "$src" -o "$obj" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
# Link with baremetal linker script so the emulator can load it
local ldscript="$PROJECTS_DIR/llvm-m65832/m65832-stdlib/scripts/baremetal/m65832.ld"
if [ -f "$ldscript" ]; then
    "$LLD" -T "$ldscript" --entry=main -o "$elf" "$obj" 2>/dev/null
else
    "$LLD" --entry=main -o "$elf" "$obj" 2>/dev/null
fi
    
    return $?
}

#
# compile_with_newlib - Compile a test with newlib
#
# Usage: compile_with_newlib <source.c>
# Output: build/<name>.elf
#
compile_with_newlib() {
    local src="$1"
    local name=$(basename "$src" .c)
    local obj="$BUILD_DIR/${name}.o"
    local elf="$BUILD_DIR/${name}.elf"
    
    if [ ! -d "$SYSROOT" ]; then
        echo "ERROR: Newlib not installed. Run scripts/build_newlib.sh first."
        return 1
    fi
    
    # Compile with newlib headers
    "$CLANG" -target m65832-elf -O2 -ffreestanding \
        -I"$SYSROOT/include" \
        -c "$src" -o "$obj" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Link with newlib
    "$LLD" -T "$SYSROOT/lib/m65832.ld" \
        "$SYSROOT/lib/crt0.o" "$obj" \
        -L"$SYSROOT/lib" -lc -lsys -lm \
        -o "$elf" 2>/dev/null
    
    return $?
}

#
# run_test - Run a compiled test on the emulator
#
# Usage: run_test <name> [expected_exit_code]
# Returns: 0 if test passed, 1 if failed
#
run_test() {
    local name="$1"
    local expected="${2:-0}"
    local elf="$BUILD_DIR/${name}.elf"
    
    if [ ! -f "$elf" ]; then
        return 1
    fi
    
    # Run with instruction limit to prevent infinite loops
    "$EMU" "$elf" -n 500000 >/dev/null 2>&1
    local exit_code=$?
    
    if [ "$exit_code" = "$expected" ]; then
        return 0
    else
        return 1
    fi
}

#
# run_test_check_value - Run test and check A register value
#
# Usage: run_test_check_value <name> <expected_hex>
#
run_test_check_value() {
    local name="$1"
    local expected="$2"
    local elf="$BUILD_DIR/${name}.elf"
    
    if [ ! -f "$elf" ]; then
        return 1
    fi
    
    # Run and capture output
    local output=$("$EMU" "$elf" -n 500000 -s 2>&1)
    
    # Extract A register value
    local actual=$(echo "$output" | grep "PC:.*A:" | sed 's/.*A: *\([0-9A-Fa-f]*\).*/\1/' | head -1)
    
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "  Expected: $expected, Got: $actual"
        return 1
    fi
}
