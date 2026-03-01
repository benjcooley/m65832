#!/bin/bash
# Regression tests for compiler bug fixes
# These tests ensure fixed bugs don't come back

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PASSED=0
FAILED=0
HEAVY_CYCLES=500000

run_test() {
    local output
    output=$(./run_c_test.sh "regression/$1" "$2" "${3:-5000}" 2>&1)
    echo "$output"
    if echo "$output" | grep -q "^PASS:"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
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
echo "--- Pointer Arithmetic Bug (2026-01-30) ---"
echo "Bug: stack-local pointer arithmetic selected @<noreg> address"
run_test "regress_ptr_arith.c" "00000063"              # 'c' = 0x63

echo ""
echo "--- Branch Offset Bug (2026-01-27) ---"
echo "Bug: Branch instructions with immediate offsets weren't adjusted for PC-relative"
run_test "regress_branch_offset.c" "00000532"          # 1330 = 0x532

echo ""
echo "--- Select/CMOV Lowering Bug (2026-02-22) ---"
echo "Bug: disjoint OR lowering caused incorrect __ffs/select behavior"
run_test "regress_select_cmov.c" "00000000" "$HEAVY_CYCLES"

echo ""
echo "--- ROL Encoding Bug (2026-02-22) ---"
echo "Bug: rotate/bit-clear codegen mismatch in clear_bit/init_array pattern"
run_test "regress_rol_encoding.c" "00000000" "$HEAVY_CYCLES"

echo ""
echo "--- Varargs String Pointer Bug (2026-02-22) ---"
echo "Bug: va_arg(%s) fetched incorrect pointer value"
run_test "regress_varargs_string.c" "00000000" "$HEAVY_CYCLES"

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed, 0 skipped"
echo "=========================================="

exit $FAILED
