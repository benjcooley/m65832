#!/bin/bash
# Run a single C test on the M65832 emulator
#
# Usage: run_c_test.sh <test.c> [expected_result] [cycles]
#
# This uses the LLVM toolchain (clang, lld) exclusively.

LLVM_ROOT="/Users/benjamincooley/projects/llvm-m65832"
LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
    LLVM_BUILD="$LLVM_BUILD_FAST"
else
    LLVM_BUILD="$LLVM_BUILD_DEFAULT"
fi
CLANG="$LLVM_BUILD/bin/clang"
LLD="$LLVM_BUILD/bin/ld.lld"
EMU="../m65832emu"

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
    ; Initialize Direct Page to $4000
    .byte 0xA9, 0x00, 0x40, 0x00, 0x00   ; LDA #$00004000
    .byte 0x5B                            ; TCD
    ; Enable register window (RSET)
    .byte 0x02, 0x30
    ; Initialize Stack Pointer to $FFFF
    .byte 0xA2, 0xFF, 0xFF, 0x00, 0x00   ; LDX #$0000FFFF
    .byte 0x9A                            ; TXS
    ; Initialize B register to 0 for absolute addressing
    .byte 0x02, 0x22, 0x00, 0x00, 0x00, 0x00  ; SB #$00000000
    ; Call main
    .byte 0x20                            ; JSR opcode
    .long main
    ; Get return value from R0 and stop
    .byte 0xA5, 0x00                      ; LDA dp $00 (R0)
    .byte 0xDB                            ; STP
EOF

# Create a simple linker script
LDSCRIPT="$WORKDIR/${BASE}.ld"
cat > "$LDSCRIPT" << 'EOF'
ENTRY(_start)
SECTIONS {
    . = 0x1000;
    .text : { *(.text*) }
    . = 0x2000;
    .data : { *(.data*) *(.rodata*) }
    . = 0x3000;
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
if ! $LLD -T "$LDSCRIPT" --oformat=binary "$WORKDIR/${BASE}_crt0.o" "$WORKDIR/${BASE}.o" -o "$WORKDIR/${BASE}.bin" 2>&1; then
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
    A_UPPER=$(echo "$A_VALUE" | tr 'a-f' 'A-F')
    EXP_UPPER=$(echo "$EXPECTED" | tr 'a-f' 'A-F')
    
    if [ "$A_UPPER" = "$EXP_UPPER" ]; then
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
