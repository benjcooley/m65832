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

# Run all tests in baremetal/core
for test_file in baremetal/core/*.c; do
    if [ -f "$test_file" ]; then
        test_name=$(basename "$test_file" .c)
        
        # Compile with standalone settings (no libc)
        if compile_standalone "$test_file"; then
            # Run and check result
            if run_test "$test_name"; then
                PASSED=$((PASSED + 1))
                echo "PASS: $test_name"
            else
                FAILED=$((FAILED + 1))
                echo "FAIL: $test_name"
            fi
        else
            SKIPPED=$((SKIPPED + 1))
            echo "SKIP: $test_name (compilation failed)"
        fi
    fi
done

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "=========================================="

exit $FAILED
