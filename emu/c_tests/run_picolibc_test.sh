#!/bin/bash
# run_picolibc_test.sh - Run a C test linked against picolibc
#
# Usage: run_picolibc_test.sh <test.c> [expected_result] [max_cycles]

CLANG="/Users/benjamincooley/projects/llvm-m65832/build/bin/clang"
LLD="/Users/benjamincooley/projects/llvm-m65832/build/bin/ld.lld"
EMU="/Users/benjamincooley/projects/M65832/emu/m65832emu"
SYSROOT="/Users/benjamincooley/projects/m65832-sysroot"

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

# Extract A register (exit code) - look for "PC:.*A:" pattern
A_VALUE=$(echo "$OUTPUT" | grep "PC:.*A:" | sed 's/.*A: *\([0-9A-Fa-f]*\).*/\1/' | tr -d ' ')
if [ -z "$A_VALUE" ]; then
    echo "FAIL: $BASE - Could not parse A register from output"
    echo "$OUTPUT"
    exit 1
fi
A_DEC=$((16#$A_VALUE))

# Check against expected
if [ -n "$EXPECTED" ]; then
    if [ "$A_DEC" = "$EXPECTED" ]; then
        echo "PASS: $BASE (result=$A_DEC)"
        exit 0
    else
        echo "FAIL: $BASE (expected=$EXPECTED, got=$A_DEC)"
        exit 1
    fi
else
    echo "Result: $BASE = $A_DEC (0x$A_VALUE)"
fi
