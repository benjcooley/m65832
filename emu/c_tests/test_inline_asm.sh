#!/bin/bash
# Test inline assembly support for M65832
# These tests verify that the compiler correctly handles inline asm constraints

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source test_common.sh 2>/dev/null || {
    # Minimal fallback if test_common.sh doesn't exist
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
}

PASS=0
FAIL=0
SKIP=0

run_inline_asm_test() {
    local name="$1"
    local file="$2"
    local cycles="${3:-5000}"
    
    if [ ! -f "$file" ]; then
        echo -e "  ${YELLOW}SKIP${NC}: $name (file not found)"
        ((SKIP++))
        return
    fi
    
    # Run without expected value - test returns 0 for success, non-zero for failures
    result=$(./run_c_test.sh "$file" 2>&1)
    
    # Check if result shows A=00000000 (test passed)
    if echo "$result" | grep -q "A=00000000"; then
        echo -e "  ${GREEN}PASS${NC}: $name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}: $name"
        echo "    $result" | head -5
        ((FAIL++))
    fi
}

echo "========================================"
echo "M65832 Inline Assembly Tests"
echo "========================================"
echo ""

echo "--- Basic GPR Register Constraints ---"
run_inline_asm_test "inline_asm_basic" "inline_asm/test_inline_asm_basic.c"

echo ""
echo "--- Accumulator Constraints ---"
run_inline_asm_test "inline_asm_acc" "inline_asm/test_inline_asm_acc.c"

echo ""
echo "--- Clobbers and Memory Constraints ---"
run_inline_asm_test "inline_asm_clobbers" "inline_asm/test_inline_asm_clobbers.c"

echo ""
echo "--- Memory Addressing (B+offset) ---"
run_inline_asm_test "inline_asm_memory" "inline_asm/test_inline_asm_memory.c"

echo ""
echo "--- Indexed Addressing (Y-indexed) ---"
run_inline_asm_test "inline_asm_indexed" "inline_asm/test_inline_asm_indexed.c"

echo ""
echo "--- Shift and Logic Operations ---"
run_inline_asm_test "inline_asm_shifts" "inline_asm/test_inline_asm_shifts.c"

echo ""
echo "--- Extended ALU Instructions ---"
run_inline_asm_test "inline_asm_extended" "inline_asm/test_inline_asm_extended.c"

echo ""
echo "--- Index Register Operations (INX/INY/DEX/DEY) ---"
run_inline_asm_test "inline_asm_indexops" "inline_asm/test_inline_asm_indexops.c"

echo ""
echo "--- Practical Use Cases ---"
run_inline_asm_test "inline_asm_practical" "inline_asm/test_inline_asm_practical.c"

echo ""
echo "--- Syscall Patterns ---"
run_inline_asm_test "inline_asm_syscall" "inline_asm/test_inline_asm_syscall.c"

echo ""
echo "--- Memory Operand Constraints ---"
run_inline_asm_test "inline_asm_memop" "inline_asm/test_inline_asm_memop.c"

echo ""
echo "--- Memory Barriers ---"
run_inline_asm_test "inline_asm_barrier" "inline_asm/test_inline_asm_barrier.c"

echo ""
echo "--- Explicit Register Constraints ---"
run_inline_asm_test "inline_asm_explicit" "inline_asm/test_inline_asm_explicit.c"

echo ""
echo "--- Local Labels ---"
run_inline_asm_test "inline_asm_labels" "inline_asm/test_inline_asm_labels.c"

echo ""
echo "--- Atomic Operations (Fences) ---"
run_inline_asm_test "inline_asm_atomic" "inline_asm/test_inline_asm_atomic.c"

echo ""
echo "--- Memory Constraint (m) ---"
run_inline_asm_test "inline_asm_m_constraint" "inline_asm/test_inline_asm_m_constraint.c"

echo ""
echo "--- Transfer Instructions ---"
run_inline_asm_test "inline_asm_transfers" "inline_asm/test_inline_asm_transfers.c"

echo ""
echo "========================================"
echo "Summary: $PASS passed, $FAIL failed, $SKIP skipped"
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
