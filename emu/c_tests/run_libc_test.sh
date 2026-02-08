#!/bin/bash
# Run a C test linked against the actual m65832-stdlib library
#
# Usage: run_libc_test.sh <test.c> [expected_result] [cycles]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
M65832_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PROJECTS_DIR="$(dirname "$M65832_DIR")"
TOOLCHAIN_BIN="$M65832_DIR/bin"

# Use installed toolchain, fall back to build-fast if not installed
if [ -x "$TOOLCHAIN_BIN/clang" ]; then
    CLANG="$TOOLCHAIN_BIN/clang"
    ASM="$TOOLCHAIN_BIN/m65832as"
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
    ASM="../../as/m65832as"
    EMU="../m65832emu"
fi
LLVM_ROOT="$PROJECTS_DIR/llvm-m65832"
STDLIB="$LLVM_ROOT/m65832-stdlib"

TEST_FILE="$1"
EXPECTED="$2"
CYCLES="${3:-10000}"

if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test.c> [expected_result] [cycles]"
    exit 1
fi

BASE=$(basename "$TEST_FILE" .c)
WORKDIR=$(dirname "$TEST_FILE")

# Step 1: Compile test to assembly
if ! $CLANG -target m65832 -S -O2 -fno-builtin \
    -I"$STDLIB/libc/include" \
    "$TEST_FILE" -o "$WORKDIR/${BASE}.s" 2>&1; then
    echo "FAIL: Test compilation failed"
    exit 1
fi

# Step 2: Compile library sources to assembly
LIB_SRCS=(
    "$STDLIB/libc/src/string/strlen.c"
    "$STDLIB/libc/src/string/strcmp.c"
    "$STDLIB/libc/src/string/strcpy.c"
    "$STDLIB/libc/src/string/memcpy.c"
    "$STDLIB/libc/src/string/memset.c"
    "$STDLIB/libc/src/string/memcmp.c"
    "$STDLIB/libc/src/string/memchr.c"
    "$STDLIB/libc/src/string/memmove.c"
    "$STDLIB/libc/src/string/strcat.c"
    "$STDLIB/libc/src/string/strchr.c"
    "$STDLIB/libc/src/stdlib/stdlib.c"
    "$STDLIB/libc/src/ctype/ctype.c"
)

for src in "${LIB_SRCS[@]}"; do
    srcbase=$(basename "$src" .c)
    if ! $CLANG -target m65832 -S -O2 -fno-builtin \
        -I"$STDLIB/libc/include" \
        "$src" -o "$WORKDIR/_lib_${srcbase}.s" 2>/dev/null; then
        echo "FAIL: Library compilation failed for $src"
        exit 1
    fi
done

# Step 3: Create combined assembly with startup + test + library
{
    echo "; Combined test: $BASE with m65832-stdlib"
    echo "    .text"
    echo "    .org \$1000"
    echo ""
    echo "; === Startup code ==="
    echo "_crt_start:"
    echo "    JSR B+_c_main"
    echo "    LDA R0"
    echo "    STP"
    echo ""
    
    # Helper to clean assembly output
    clean_asm() {
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
        grep -v '^; %bb'
    }
    
    echo "; === Test code ==="
    cat "$WORKDIR/${BASE}.s" | clean_asm | \
        sed 's/^main:/_c_main:/' | \
        sed 's/; @main/; @_c_main/'
    echo ""
    
    echo "; === Library code ==="
    for src in "${LIB_SRCS[@]}"; do
        srcbase=$(basename "$src" .c)
        echo "; --- $srcbase ---"
        cat "$WORKDIR/_lib_${srcbase}.s" | clean_asm
        echo ""
    done
    
    echo ".data"
    echo "    .org \$8000"
    echo ".bss"
    echo "    .org \$9000"
    
} > "$WORKDIR/${BASE}_linked.s"

# Clean up library assembly files
rm -f "$WORKDIR"/_lib_*.s

# Step 4: Assemble
if ! $ASM "$WORKDIR/${BASE}_linked.s" -o "$WORKDIR/${BASE}_linked.bin" 2>&1; then
    echo "FAIL: Assembly failed"
    exit 1
fi

# Step 5: Run on emulator
OUTPUT=$($EMU -c "$CYCLES" -s "$WORKDIR/${BASE}_linked.bin" 2>&1)

# Extract A register value
A_VALUE=$(echo "$OUTPUT" | grep "PC:.*A:.*X:" | sed 's/.*A: \([0-9A-Fa-f]*\).*/\1/')

if [ -n "$EXPECTED" ]; then
    A_UPPER=$(echo "$A_VALUE" | tr 'a-f' 'A-F')
    EXP_UPPER=$(echo "$EXPECTED" | tr 'a-f' 'A-F')
    
    if [ "$A_UPPER" = "$EXP_UPPER" ]; then
        echo "PASS: $BASE (A=$A_VALUE)"
        exit 0
    else
        echo "FAIL: $BASE (expected A=$EXPECTED, got A=$A_VALUE)"
        echo "$OUTPUT"
        exit 1
    fi
else
    echo "Result: $BASE A=$A_VALUE"
    echo "$OUTPUT"
fi
