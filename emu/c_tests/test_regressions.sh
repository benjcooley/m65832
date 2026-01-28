#!/bin/bash
# Regression tests for compiler bug fixes
# These tests ensure fixed bugs don't come back

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

run_test() {
    ./run_c_test.sh "regression/$1" "$2" "${3:-5000}"
}

echo "======================================"
echo "Compiler Regression Tests"
echo "======================================"
echo ""

echo "--- Stack Spill Bug (2026-01-27) ---"
echo "Bug: storeRegToStackSlot/loadRegFromStackSlot used wrong instructions"
run_test "regress_stack_spill.c" "00000088"            # 136 = 0x88
run_test "regress_stack_spill_complex.c" "00000064"   # 100 = 0x64

echo ""
echo "--- BRCOND Bug (2026-01-27) ---"
echo "Bug: Backend couldn't select brcond nodes"
run_test "regress_brcond.c" "0000002A"                 # 42 = 0x2A

echo ""
echo "--- Call Frame Bug (2026-01-27) ---"
echo "Bug: JSR overwrote local variables because call frame space wasn't reserved"
run_test "regress_call_frame.c" "0000006C"             # 108 = 0x6C

echo ""
echo "--- Branch Offset Bug (2026-01-27) ---"
echo "Bug: Branch instructions with immediate offsets weren't adjusted for PC-relative"
run_test "regress_branch_offset.c" "00000532"          # 1330 = 0x532

echo ""
echo "======================================"
echo "Regression Tests Complete"
echo "======================================"
