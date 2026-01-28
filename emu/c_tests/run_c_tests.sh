#!/bin/bash
# M65832 C Compiler Test Suite
# Run all C tests or specific test groups

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Run a test: run_test "description" "test_file.c" "expected_hex" [cycles]
run_test() {
    local desc="$1"
    local file="$2"
    local expected="$3"
    local cycles="${4:-1000}"
    
    printf "  %-25s" "$desc..."
    
    if [ ! -f "$file" ]; then
        echo -e "${CYAN}SKIP${NC} (file not found)"
        ((SKIPPED++))
        return
    fi
    
    # Run test silently, capture result
    result=$(./run_c_test.sh "$file" "$expected" "$cycles" 2>&1)
    
    if echo "$result" | grep -q "^PASS:"; then
        echo -e "${GREEN}PASS${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        # Show failure details
        echo "$result" | grep -E "^(FAIL:|Final CPU)" | sed 's/^/    /'
        ((FAILED++))
    fi
}

# Run a group of tests
run_group() {
    local group="$1"
    local script="test_${group}.sh"
    
    if [ -f "$script" ]; then
        echo -e "${CYAN}=== Running $group tests ===${NC}"
        source "$script"
        echo ""
    else
        echo "Warning: $script not found"
    fi
}

# Print summary
print_summary() {
    echo "=========================================="
    echo -e " ${GREEN}Passed${NC}: $PASSED"
    echo -e " ${RED}Failed${NC}: $FAILED"
    if [ $SKIPPED -gt 0 ]; then
        echo -e " ${CYAN}Skipped${NC}: $SKIPPED"
    fi
    echo " Total:  $((PASSED + FAILED))"
    echo "=========================================="
}

# Available test groups
TEST_GROUPS="arithmetic control memory functions bitops types edge algorithms fpu structs switch operators sizeof advanced casts datastructs strings integration"

# Main
echo "=========================================="
echo " M65832 C Compiler Test Suite"
echo "=========================================="
echo ""

if [ $# -eq 0 ]; then
    # Run all groups
    for group in $TEST_GROUPS; do
        run_group "$group"
    done
else
    # Run specified groups
    for group in "$@"; do
        run_group "$group"
    done
fi

print_summary

# Exit with failure if any tests failed
[ $FAILED -eq 0 ]
