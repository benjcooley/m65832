#!/bin/bash
# run_picolibc_suite.sh - Run picolibc test sources on M65832 emulator
#
# This script compiles picolibc test sources and runs them on our emulator

PICOLIBC_TEST="/Users/benjamincooley/projects/picolibc-m65832/test"
LLVM_ROOT="/Users/benjamincooley/projects/llvm-m65832"
LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
    LLVM_BUILD="$LLVM_BUILD_FAST"
else
    LLVM_BUILD="$LLVM_BUILD_DEFAULT"
fi
CLANG="$LLVM_BUILD/bin/clang"
LLD_FAST="$LLVM_BUILD_FAST/bin/ld.lld"
LLD_DEFAULT="$LLVM_BUILD_DEFAULT/bin/ld.lld"
if [ -x "$LLD_FAST" ]; then
    LLD="$LLD_FAST"
else
    LLD="$LLD_DEFAULT"
fi
EMU="/Users/benjamincooley/projects/m65832/emu/m65832emu"
SYSROOT="/Users/benjamincooley/projects/m65832-sysroot"
WORKDIR="/tmp/picolibc_suite"

mkdir -p "$WORKDIR"

PASS=0
FAIL=0
SKIP=0

run_test() {
    local name="$1"
    local src="$2"
    local extra_src="$3"
    local expect_fail="${4:-0}"
    local timeout="${5:-100000}"
    
    # Compile
    local compile_cmd="$CLANG -target m65832-elf -O1 -ffreestanding"
    compile_cmd="$compile_cmd -I$SYSROOT/include"
    compile_cmd="$compile_cmd -I$PICOLIBC_TEST"
    compile_cmd="$compile_cmd -c $src -o $WORKDIR/${name}.o"
    
    if ! $CLANG -target m65832-elf -O1 -ffreestanding \
        -I"$SYSROOT/include" \
        -I"$PICOLIBC_TEST" \
        -c "$src" -o "$WORKDIR/${name}.o" 2>/dev/null; then
        echo "SKIP: $name (compile failed)"
        SKIP=$((SKIP + 1))
        return
    fi
    
    # Compile extra source if provided
    local extra_obj=""
    if [ -n "$extra_src" ] && [ -f "$extra_src" ]; then
        if $CLANG -target m65832-elf -O1 -ffreestanding \
            -I"$SYSROOT/include" \
            -I"$PICOLIBC_TEST" \
            -c "$extra_src" -o "$WORKDIR/${name}_extra.o" 2>/dev/null; then
            extra_obj="$WORKDIR/${name}_extra.o"
        fi
    fi
    
    # Link
    if ! $LLD -T "$SYSROOT/lib/m65832.ld" \
        "$SYSROOT/lib/crt0.o" \
        "$WORKDIR/${name}.o" \
        $extra_obj \
        -L"$SYSROOT/lib" -lc -lsys \
        -o "$WORKDIR/${name}.elf" 2>/dev/null; then
        echo "SKIP: $name (link failed)"
        SKIP=$((SKIP + 1))
        return
    fi
    
    # Run
    local output
    output=$($EMU -c "$timeout" -s "$WORKDIR/${name}.elf" 2>&1)
    local emu_exit=$?
    
    if [ $emu_exit -ne 0 ]; then
        if [ "$expect_fail" = "1" ]; then
            echo "PASS: $name (expected failure)"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (emulator error)"
            FAIL=$((FAIL + 1))
        fi
        return
    fi
    
    # Extract A register value (exit code)
    local a_val
    a_val=$(echo "$output" | grep "PC:.*A:" | sed 's/.*A: *\([0-9A-Fa-f]*\).*/\1/')
    local result=$((16#$a_val))
    
    if [ "$expect_fail" = "1" ]; then
        if [ "$result" != "0" ]; then
            echo "PASS: $name (expected failure, got $result)"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (expected failure but passed)"
            FAIL=$((FAIL + 1))
        fi
    else
        if [ "$result" = "0" ]; then
            echo "PASS: $name"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (result=$result)"
            FAIL=$((FAIL + 1))
        fi
    fi
}

echo "=== Picolibc Test Suite ==="
echo ""

# Test categories

echo "--- String Tests ---"
run_test "memset" "$PICOLIBC_TEST/test-string/test-memset.c"
run_test "memchr-simple" "$PICOLIBC_TEST/test-string/test-memchr-simple.c"
run_test "strchr" "$PICOLIBC_TEST/test-string/test-strchr.c"
run_test "strncpy" "$PICOLIBC_TEST/test-string/test-strncpy.c"
run_test "memmem" "$PICOLIBC_TEST/test-string/test-memmem.c"

echo ""
echo "--- Ctype Tests ---"
run_test "ctype" "$PICOLIBC_TEST/test-ctype/test-ctype.c"

echo ""
echo "--- Stdlib Tests ---"
run_test "ffs" "$PICOLIBC_TEST/ffs.c" "$PICOLIBC_TEST/lock-valid.c"
run_test "malloc" "$PICOLIBC_TEST/malloc.c" "$PICOLIBC_TEST/lock-valid.c"
run_test "test-hello" "$PICOLIBC_TEST/test-hello.c" "$PICOLIBC_TEST/lock-valid.c"

echo ""
echo "--- Libc Testsuite ---"
run_test "qsort" "$PICOLIBC_TEST/libc-testsuite/qsort.c"
run_test "string" "$PICOLIBC_TEST/libc-testsuite/string.c"
run_test "strtol" "$PICOLIBC_TEST/libc-testsuite/strtol.c"

echo ""
echo "==========================="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "==========================="
