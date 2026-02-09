#!/bin/bash
# Run a single C test on the M65832 emulator
#
# Usage: run_c_test.sh <test.c> [expected_result] [cycles]
#
# This uses the LLVM toolchain (clang, lld) exclusively.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
M65832_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TOOLCHAIN_BIN="$M65832_DIR/bin"

# Use installed toolchain, fall back to build-fast if not installed
if [ -x "$TOOLCHAIN_BIN/clang" ]; then
    CLANG="$TOOLCHAIN_BIN/clang"
    LLD="$TOOLCHAIN_BIN/ld.lld"
    EMU="$TOOLCHAIN_BIN/m65832emu"
else
    LLVM_ROOT="$(dirname "$M65832_DIR")/llvm-m65832"
    LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
    CLANG="$LLVM_BUILD_FAST/bin/clang"
    LLD="$LLVM_BUILD_FAST/bin/ld.lld"
    EMU="$SCRIPT_DIR/../m65832emu"
fi

LLVM_ROOT="$(dirname "$M65832_DIR")/llvm-m65832"
COMPILER_RT_DIR="$LLVM_ROOT/m65832-stdlib/compiler-rt"
COMPILER_RT="$COMPILER_RT_DIR/libcompiler_rt.a"

TEST_FILE="$1"
EXPECTED="$2"
CYCLES="${3:-10000}"

if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test.c> [expected_result] [cycles]"
    exit 1
fi

BASE=$(basename "$TEST_FILE" .c)
BASE=$(basename "$BASE" .ll)
WORKDIR=$(dirname "$TEST_FILE")
EXT="${TEST_FILE##*.}"

# Create a minimal startup assembly file using LLVM syntax
CRT0="$WORKDIR/${BASE}_crt0.s"
cat > "$CRT0" << 'EOF'
    .text
    .globl _start
_start:
    // Initialize Direct Page to $4000
    .byte 0xA9, 0x00, 0x40, 0x00, 0x00   // LDA #$00004000
    .byte 0x5B                            // TCD
    // Enable register window (RSET)
    .byte 0x02, 0x30
    // Initialize Stack Pointer to $FFFF
    .byte 0xA2, 0xFF, 0xFF, 0x00, 0x00   // LDX #$0000FFFF
    .byte 0x9A                            // TXS
    // Initialize B register to 0 for absolute addressing
    .byte 0x02, 0x22, 0x00, 0x00, 0x00, 0x00  // SB #$00000000
    // Call main
    .byte 0x20                            // JSR opcode
    .long main
    // Get return value from R0 and stop
    .byte 0xA5, 0x00                      // LDA dp $00 (R0)
    .byte 0xDB                            // STP
EOF

# Create a simple linker script
LDSCRIPT="$WORKDIR/${BASE}.ld"
cat > "$LDSCRIPT" << 'EOF'
ENTRY(_start)
SECTIONS {
    . = 0x1000;
    .text : { *(.text*) }
    . = ALIGN(0x1000);
    .data : { *(.data*) *(.rodata*) }
    . = ALIGN(0x1000);
    .bss : { *(.bss*) }
}
EOF

# Step 1: Compile CRT0 to object
if ! $CLANG -target m65832 -c "$CRT0" -o "$WORKDIR/${BASE}_crt0.o" 2>&1; then
    echo "FAIL: CRT0 compilation failed"
    exit 1
fi

# Step 2: Compile test file to object
if [ "$EXT" = "c" ]; then
    if [ ! -f "$CLANG" ]; then
        echo "FAIL: clang not found at $CLANG"
        echo "Build with: cd llvm-m65832 && ninja -C build-fast clang"
        exit 1
    fi
    OPT_LEVEL="${OPT_LEVEL:--O0}"
    if ! $CLANG -target m65832 -c $OPT_LEVEL -fno-builtin "$TEST_FILE" -o "$WORKDIR/${BASE}.o" 2>&1; then
        echo "FAIL: Clang compilation failed"
        exit 1
    fi
else
    echo "FAIL: Unknown file type: $EXT"
    exit 1
fi

# Step 3: Link with LLD, output binary directly
if [ ! -f "$LLD" ]; then
    echo "FAIL: lld not found at $LLD"
    exit 1
fi
# Include compiler_rt if available (needed for 64-bit operations)
EXTRA_LIBS=""
if [ -f "$COMPILER_RT" ]; then
    EXTRA_LIBS="$COMPILER_RT"
fi
if ! $LLD -T "$LDSCRIPT" --oformat=binary "$WORKDIR/${BASE}_crt0.o" "$WORKDIR/${BASE}.o" $EXTRA_LIBS -o "$WORKDIR/${BASE}.bin" 2>&1; then
    echo "FAIL: Linking failed"
    exit 1
fi

# Step 5: Run on emulator
START_TIME=$(date +%s)
OUTPUT=$($EMU -o 0x1000 -e 0x1000 -c "$CYCLES" --stop-on-brk -s "$WORKDIR/${BASE}.bin" 2>&1)
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Extract A register value
A_VALUE=$(echo "$OUTPUT" | grep "PC:.*A:.*X:" | sed 's/.*A: \([0-9A-Fa-f]*\).*/\1/')

if [ -n "$EXPECTED" ]; then
    # Convert both to integers for comparison (handles leading zeros)
    A_INT=$(printf "%d" "0x$A_VALUE" 2>/dev/null || echo "-1")
    EXP_INT=$(printf "%d" "0x$EXPECTED" 2>/dev/null || printf "%d" "$EXPECTED" 2>/dev/null || echo "-2")
    
    if [ "$A_INT" = "$EXP_INT" ]; then
        echo "PASS: $BASE (A=$A_VALUE, ${ELAPSED}s)"
        rm -f "$CRT0" "$LDSCRIPT" "$WORKDIR/${BASE}_crt0.o" "$WORKDIR/${BASE}.o"
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
