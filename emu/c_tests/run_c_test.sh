#!/bin/bash
# Run a single C test on the M65832 emulator
#
# Usage: run_c_test.sh <test.c> [expected_result] [cycles]

LLVM_ROOT="/Users/benjamincooley/projects/llvm-m65832"
LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
    LLVM_BUILD="$LLVM_BUILD_FAST"
else
    LLVM_BUILD="$LLVM_BUILD_DEFAULT"
fi
CLANG="$LLVM_BUILD/bin/clang"
LLC="$LLVM_BUILD/bin/llc"
ASM="../../as/m65832as"
EMU="../m65832emu"

TEST_FILE="$1"
EXPECTED="$2"
CYCLES="${3:-1000}"

if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test.c> [expected_result] [cycles]"
    exit 1
fi

BASE=$(basename "$TEST_FILE" .c)
BASE=$(basename "$BASE" .ll)  # Also handle .ll files for backward compat
WORKDIR=$(dirname "$TEST_FILE")
EXT="${TEST_FILE##*.}"

# Step 1: Compile to assembly
if [ "$EXT" = "c" ]; then
    # C file -> clang -> assembly
    if [ ! -f "$CLANG" ]; then
        echo "FAIL: clang not found at $CLANG"
        echo "Build with: cd llvm-m65832 && ninja -C build-fast clang"
        exit 1
    fi
    if ! $CLANG -target m65832 -S -O2 -fno-builtin "$TEST_FILE" -o "$WORKDIR/${BASE}.s" 2>&1; then
        echo "FAIL: Clang compilation failed"
        exit 1
    fi
elif [ "$EXT" = "ll" ]; then
    # LLVM IR -> llc -> assembly
    if ! $LLC -march=m65832 "$TEST_FILE" -o "$WORKDIR/${BASE}.s" 2>&1; then
        echo "FAIL: LLC compilation failed"
        exit 1
    fi
else
    echo "FAIL: Unknown file type: $EXT"
    exit 1
fi

# Step 2: Create combined assembly with startup code
{
    echo "; Combined test: $BASE"
    echo "    .text"
    echo "    .org \$1000"
    echo ""
    echo "; === Startup code ==="
    echo "_crt_start:"
    echo "    JSR B+_c_main"
    echo "    LDA R0"
    echo "    STP"
    echo ""
    echo "; === Test code ==="
    # Filter output: skip ELF-specific directives, rename main->_c_main
    # Filter .text since we add our own; keep .data for globals
    # NOTE: This test harness injects a .org for .data because we do not run
    # a real linker here. In a production toolchain, the linker script would
    # place .text and .data in ROM/RAM respectively.
    cat "$WORKDIR/${BASE}.s" | \
        grep -v '^\s*\.file' | \
        grep -v '^\s*\.text' | \
        grep -v '^\s*\.globl' | \
        grep -v '^\s*\.p2align' | \
        grep -v '^\s*\.type' | \
        grep -v '^\s*\.size' | \
        grep -v '^\s*\.section.*note' | \
        grep -v '^\s*\.ident' | \
        grep -v '^\s*\.addrsig' | \
        grep -v '^\.Lfunc_end' | \
        grep -v '^; %bb' | \
        sed 's/^[[:space:]]*\.data/.data\n    .org $2000  ; test harness: place .data in RAM without a linker/' | \
        sed 's/^[[:space:]]*\.bss/.bss\n    .org $3000  ; test harness: place .bss in RAM without a linker/' | \
        sed 's/^main:/_c_main:/' | \
        sed 's/; @main/; @_c_main/'
} > "$WORKDIR/${BASE}_combined.s"

# Step 3: Assemble
if ! $ASM "$WORKDIR/${BASE}_combined.s" -o "$WORKDIR/${BASE}.bin" 2>&1; then
    echo "FAIL: Assembly failed"
    cat "$WORKDIR/${BASE}_combined.s"
    exit 1
fi

# Step 4: Run on emulator (time the run)
START_TIME=$(date +%s)
OUTPUT=$($EMU -c "$CYCLES" -s "$WORKDIR/${BASE}.bin" 2>&1)
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Extract A register value (from line like "  PC: 00001008  A: 00000030  X: ...")
A_VALUE=$(echo "$OUTPUT" | grep "PC:.*A:.*X:" | sed 's/.*A: \([0-9A-Fa-f]*\).*/\1/')

if [ -n "$EXPECTED" ]; then
    # Normalize both to uppercase for comparison
    A_UPPER=$(echo "$A_VALUE" | tr 'a-f' 'A-F')
    EXP_UPPER=$(echo "$EXPECTED" | tr 'a-f' 'A-F')
    
    if [ "$A_UPPER" = "$EXP_UPPER" ]; then
        echo "PASS: $BASE (A=$A_VALUE, ${ELAPSED}s)"
        exit 0
    else
        echo "FAIL: $BASE (expected A=$EXPECTED, got A=$A_VALUE, ${ELAPSED}s)"
        echo "$OUTPUT"
        exit 1
    fi
else
    echo "Result: $BASE A=$A_VALUE (${ELAPSED}s)"
    echo "$OUTPUT"
fi
