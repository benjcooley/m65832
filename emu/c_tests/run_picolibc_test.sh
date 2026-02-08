#!/bin/bash
# run_picolibc_test.sh - Run a C test linked against picolibc
#
# Usage: run_picolibc_test.sh <test.c> [expected_result] [max_cycles]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
M65832_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECTS_DIR="$(dirname "$M65832_DIR")"
TOOLCHAIN_BIN="$M65832_DIR/bin"

if [ -x "$TOOLCHAIN_BIN/clang" ]; then
    CLANG="$TOOLCHAIN_BIN/clang"
    LLD="$TOOLCHAIN_BIN/ld.lld"
    EMU="$TOOLCHAIN_BIN/m65832emu"
else
    LLVM_ROOT="$PROJECTS_DIR/llvm-m65832"
    LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
    LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
    if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
        LLVM_BUILD="$LLVM_BUILD_FAST"
    else
        LLVM_BUILD="$LLVM_BUILD_DEFAULT"
    fi
    CLANG="$LLVM_BUILD/bin/clang"
    LLD="$LLVM_BUILD/bin/ld.lld"
    EMU="$M65832_DIR/emu/m65832emu"
fi
SYSROOT="$PROJECTS_DIR/m65832-sysroot"

TEST_FILE="$1"
EXPECTED="$2"
MAX_CYCLES="${3:-100000}"

if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test.c> [expected_result] [max_cycles]"
    exit 1
fi

BASE=$(basename "$TEST_FILE" .c)
WORKDIR="/tmp/picolibc_tests"
mkdir -p "$WORKDIR"

# Step 1: Compile
# Note: Using -O0 due to register allocation bug at -O1+ with comparisons
if ! $CLANG -target m65832-elf -O0 -ffreestanding \
    -I"$SYSROOT/include" \
    -c "$TEST_FILE" -o "$WORKDIR/${BASE}.o" 2>&1; then
    echo "FAIL: $BASE - Compilation failed"
    exit 1
fi

# Step 2: Link
if ! $LLD -T "$SYSROOT/lib/m65832.ld" \
    "$SYSROOT/lib/crt0.o" \
    "$WORKDIR/${BASE}.o" \
    -L"$SYSROOT/lib" -lc -lsys \
    -o "$WORKDIR/${BASE}.elf" 2>&1; then
    echo "FAIL: $BASE - Link failed"
    exit 1
fi

# Step 3: Run
OUTPUT=$($EMU -c "$MAX_CYCLES" -s "$WORKDIR/${BASE}.elf" 2>&1)
EMU_EXIT=$?

if [ $EMU_EXIT -ne 0 ]; then
    echo "FAIL: $BASE - Emulator error"
    echo "$OUTPUT"
    exit 1
fi

# Extract exit code written by _exit (preferred), fallback to A register
EXIT_VALUE=$(echo "$OUTPUT" | grep "EXIT:" | sed 's/.*EXIT: *\([0-9A-Fa-f]*\).*/\1/' | tr -d ' ')
if [ -z "$EXIT_VALUE" ]; then
    EXIT_VALUE=$(echo "$OUTPUT" | grep "PC:.*A:" | sed 's/.*A: *\([0-9A-Fa-f]*\).*/\1/' | tr -d ' ')
fi
if [ -z "$EXIT_VALUE" ]; then
    echo "FAIL: $BASE - Could not parse exit code from output"
    echo "$OUTPUT"
    exit 1
fi
EXIT_DEC=$((16#$EXIT_VALUE))

# Check against expected
if [ -n "$EXPECTED" ]; then
    if [ "$EXIT_DEC" = "$EXPECTED" ]; then
        echo "PASS: $BASE (result=$EXIT_DEC)"
        exit 0
    else
        echo "FAIL: $BASE (expected=$EXPECTED, got=$EXIT_DEC)"
        exit 1
    fi
else
    echo "Result: $BASE = $EXIT_DEC (0x$EXIT_VALUE)"
fi
