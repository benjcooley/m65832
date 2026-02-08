#!/bin/bash
# Run sandbox filesystem tests in system mode

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
    EMU="$SCRIPT_DIR/../m65832emu"
fi
SYSROOT="$PROJECTS_DIR/m65832-sysroot"

TEST_DIR="$SCRIPT_DIR/filesystem"
LINKER_SCRIPT="$TEST_DIR/m65832_sys.ld"
SANDBOX="$TEST_DIR/sandbox"
BUILD_DIR="$TEST_DIR/build"

mkdir -p "$BUILD_DIR"

PASS=0
FAIL=0

run_test() {
    local src="$1"
    local name
    name=$(basename "$src" .c)
    local obj="$BUILD_DIR/${name}.o"
    local bin="$BUILD_DIR/${name}.bin"
    local syscalls_obj="$BUILD_DIR/syscalls.o"
    local crt0_obj="$BUILD_DIR/crt0.o"

    echo -n "Test: $name... "

    if ! $CLANG -target m65832-elf -O0 -ffreestanding -fno-builtin \
        -I"$SYSROOT/include" \
        -c "$TEST_DIR/syscalls.c" -o "$syscalls_obj" 2>&1; then
        echo "FAIL (syscalls compile)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! $CLANG -target m65832-elf -O0 -ffreestanding -fno-builtin \
        -c "$TEST_DIR/crt0.s" -o "$crt0_obj" 2>&1; then
        echo "FAIL (crt0 compile)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! $CLANG -target m65832-elf -O0 -ffreestanding -fno-builtin \
        -I"$SYSROOT/include" -c "$src" -o "$obj" 2>&1; then
        echo "FAIL (compile)"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! $LLD -T "$LINKER_SCRIPT" --oformat=binary \
        "$crt0_obj" "$obj" "$syscalls_obj" -L"$SYSROOT/lib" -lc -lsys \
        -o "$bin" 2>&1; then
        echo "FAIL (link)"
        FAIL=$((FAIL + 1))
        return
    fi

    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX"
    echo "input-data" > "$SANDBOX/input.txt"

    output=$($EMU --system --kernel "$bin" --entry 0x00100000 --sandbox "$SANDBOX" \
        --stop-on-brk --state -c 2000000 2>&1)

    exit_val=$(echo "$output" | grep "EXIT:" | tail -1 | sed 's/.*EXIT: \([0-9A-Fa-f]*\).*/\1/')
    if [ -z "$exit_val" ]; then
        echo "FAIL (no exit)"
        FAIL=$((FAIL + 1))
        return
    fi

    if [ "$exit_val" = "00000000" ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (exit=$exit_val)"
        echo "$output" | tail -20
        FAIL=$((FAIL + 1))
    fi
}

run_test "$TEST_DIR/test_fs_read.c"
run_test "$TEST_DIR/test_fs_write.c"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
