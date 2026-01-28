#!/bin/bash
# run_core_tests.sh - Run baremetal core tests (no libc dependencies)
#
# These tests use only basic C features and don't require any library functions.
# They test the compiler's ability to generate correct code for:
# - Arithmetic operations
# - Control flow
# - Function calls
# - Memory access
# - Bitwise operations
# - etc.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source ./test_common.sh

echo "=========================================="
echo "Baremetal Core Tests"
echo "=========================================="
echo "These tests verify basic compiler functionality"
echo "without any library dependencies."
echo ""

PASSED=0
FAILED=0
SKIPPED=0

# Extract expected value from test file comments.
# Supports formats like:
#   // Expected: 0x30
#   // Expected: 42
#   // Expected: -1
extract_expected() {
    local file="$1"
    local line expected hexval decval
    line=$(grep -m1 -E 'Expected:' "$file" || true)
    if [ -z "$line" ]; then
        echo ""
        return
    fi
    expected=$(echo "$line" | sed -E 's/.*Expected:[[:space:]]*//')
    expected=$(echo "$expected" | sed -E 's/[^0-9a-fA-FxX+-].*$//')
    if [[ "$expected" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
        hexval="${expected#0x}"
        hexval="${hexval#0X}"
        decval=$((16#$hexval))
    else
        decval=$((expected))
    fi
    if [ "$decval" -lt 0 ]; then
        decval=$((decval + 0x100000000))
    fi
    printf "%08X" "$decval"
}

# Run all tests in baremetal/core
for test_file in baremetal/core/*.c; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file" .c)
        expected_hex=$(extract_expected "$test_file")
        
        # Use run_c_test.sh harness (no libc)
        if [ -n "$expected_hex" ]; then
            if bash ./run_c_test.sh "$test_file" "$expected_hex" 500000 >/dev/null 2>&1; then
                PASSED=$((PASSED + 1))
                echo "PASS: $test_name"
            else
                FAILED=$((FAILED + 1))
                echo "FAIL: $test_name"
            fi
        else
            if bash ./run_c_test.sh "$test_file" "" 500000 >/dev/null 2>&1; then
                PASSED=$((PASSED + 1))
                echo "PASS: $test_name"
            else
                FAILED=$((FAILED + 1))
                echo "FAIL: $test_name"
            fi
        fi
    fi
done

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "=========================================="

exit $FAILED
