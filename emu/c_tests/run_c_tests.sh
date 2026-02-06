#!/bin/bash
# M65832 C Compiler Test Suite
#
# Single entry point for all compiler tests.
# Delegates to specific test runners for each category.
#
# Usage:
#   ./run_c_tests.sh              Run all tests
#   ./run_c_tests.sh core         Run only core (baremetal) tests
#   ./run_c_tests.sh regression   Run only regression tests
#   ./run_c_tests.sh inline_asm   Run only inline assembly tests
#   ./run_c_tests.sh all          Run everything including inline_asm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

run_suite() {
    local name="$1"
    local script="$2"

    if [ ! -f "$script" ]; then
        echo -e "${RED}ERROR: $script not found${NC}"
        return
    fi

    echo -e "${BOLD}Running $name...${NC}"
    output=$(bash "$script" 2>&1)
    echo "$output"

    # Extract results from the last "Results:" or "Passed:" line
    local p f s
    p=$(echo "$output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+')
    f=$(echo "$output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+')
    s=$(echo "$output" | grep -oE '[0-9]+ skipped' | tail -1 | grep -oE '[0-9]+')
    # Fallback: try "Passed: N" format
    if [ -z "$p" ]; then
        p=$(echo "$output" | grep -oE 'Passed: [0-9]+' | tail -1 | grep -oE '[0-9]+')
        f=$(echo "$output" | grep -oE 'Failed: [0-9]+' | tail -1 | grep -oE '[0-9]+')
    fi
    # Fallback: try "PASS: N" / "FAIL: N" counts
    if [ -z "$p" ]; then
        p=$(echo "$output" | grep -c "^PASS:")
        f=$(echo "$output" | grep -c "^FAIL:")
    fi

    TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
    TOTAL_SKIP=$((TOTAL_SKIP + ${s:-0}))
    echo ""
}

echo "=========================================="
echo -e "${BOLD} M65832 C Compiler Test Suite${NC}"
echo "=========================================="
echo ""

if [ $# -eq 0 ]; then
    set -- core regression
fi

for group in "$@"; do
    case "$group" in
        core)
            run_suite "Core Compiler Tests (baremetal/core/)" "./run_core_tests.sh"
            ;;
        regression)
            run_suite "Regression Tests" "./test_regressions.sh"
            ;;
        inline_asm|asm)
            run_suite "Inline Assembly Tests" "./test_inline_asm.sh"
            ;;
        all)
            run_suite "Core Compiler Tests (baremetal/core/)" "./run_core_tests.sh"
            run_suite "Regression Tests" "./test_regressions.sh"
            run_suite "Inline Assembly Tests" "./test_inline_asm.sh"
            ;;
        *)
            echo -e "${RED}Unknown test group: $group${NC}"
            echo "Available: core, regression, inline_asm, all"
            ;;
    esac
done

echo "=========================================="
echo -e "${BOLD} Overall Results${NC}"
echo "=========================================="
echo -e " ${GREEN}Passed${NC}:  $TOTAL_PASS"
echo -e " ${RED}Failed${NC}:  $TOTAL_FAIL"
if [ $TOTAL_SKIP -gt 0 ]; then
    echo -e " ${CYAN}Skipped${NC}: $TOTAL_SKIP"
fi
echo " Total:   $((TOTAL_PASS + TOTAL_FAIL))"
echo "=========================================="

[ $TOTAL_FAIL -eq 0 ]
