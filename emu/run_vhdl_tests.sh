#!/bin/bash
#
# M65832 Emulator Test Runner
# Runs VHDL-extracted tests against the emulator
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh 122          # Run test 122
#   ./run_tests.sh 100-110      # Run tests 100-110
#   ./run_tests.sh alu          # Run ALU category tests
#   ./run_tests.sh --list       # List available tests
#   ./run_tests.sh --categories # List test categories
#   ./run_tests.sh -v 122       # Run test 122 with verbose output
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EMU_DIR="$PROJECT_ROOT/emu"
TEST_SCRIPT="$SCRIPT_DIR/extract_vhdl_tests.py"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get test range for a category
get_category_range() {
    case "$1" in
        basic)      echo "1-20" ;;
        alu)        echo "21-50" ;;
        load)       echo "51-70" ;;
        store)      echo "71-80" ;;
        stack)      echo "81-90" ;;
        rset)       echo "91-100" ;;
        branch)     echo "101-110" ;;
        interrupt)  echo "111-120" ;;
        mmu)        echo "121-127" ;;
        timer)      echo "128" ;;
        illegal)    echo "124-126" ;;
        privilege)  echo "122-123" ;;
        fpu)        echo "100G 100H 100I 100J 100K 100L 100M 100N 100O 100P 100Q 100R 100S 100T 100U 100V 100W" ;;
        *)          echo "" ;;
    esac
}

usage() {
    echo "M65832 Emulator Test Runner"
    echo ""
    echo "Usage: $0 [OPTIONS] [TEST_SPEC...]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -v, --verbose     Verbose output"
    echo "  -l, --list        List all available tests"
    echo "  -c, --categories  List test categories"
    echo "  -q, --quiet       Only show summary"
    echo "  --failing         Only run previously failing tests"
    echo "  --build           Rebuild emulator before testing"
    echo ""
    echo "Test Specifications:"
    echo "  <number>          Run single test (e.g., 122)"
    echo "  <start>-<end>     Run range of tests (e.g., 100-110)"
    echo "  <category>        Run category (e.g., alu, mmu, stack)"
    echo "  all               Run all tests (default)"
    echo ""
    echo "Categories:"
    echo "  basic       Tests 1-20      (basic instructions)"
    echo "  alu         Tests 21-50     (arithmetic/logic)"
    echo "  load        Tests 51-70     (load instructions)"
    echo "  store       Tests 71-80     (store instructions)"
    echo "  stack       Tests 81-90     (stack operations)"
    echo "  rset        Tests 91-100    (register set mode)"
    echo "  branch      Tests 101-110   (branches/jumps)"
    echo "  interrupt   Tests 111-120   (IRQ/NMI/exceptions)"
    echo "  mmu         Tests 121-127   (MMU/page tables)"
    echo "  timer       Tests 128       (timer hardware)"
    echo "  illegal     Tests 124-126   (illegal opcode handling)"
    echo "  privilege   Tests 122-123   (privilege traps)"
    echo "  fpu         Tests 100G-100W (FPU instructions)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 122                # Run test 122"
    echo "  $0 mmu                # Run MMU tests (121-127)"
    echo "  $0 -v privilege       # Run privilege tests with verbose"
    echo "  $0 100 105 110        # Run tests 100, 105, and 110"
    echo "  $0 alu branch         # Run ALU and branch tests"
}

list_tests() {
    echo "Available tests:"
    echo ""
    python3 "$TEST_SCRIPT" --list 2>/dev/null
}

list_categories() {
    echo "Test Categories:"
    echo ""
    echo "  basic       Tests 1-20      (basic instructions)"
    echo "  alu         Tests 21-50     (arithmetic/logic)"
    echo "  load        Tests 51-70     (load instructions)"
    echo "  store       Tests 71-80     (store instructions)"
    echo "  stack       Tests 81-90     (stack operations)"
    echo "  rset        Tests 91-100    (register set mode)"
    echo "  branch      Tests 101-110   (branches/jumps)"
    echo "  interrupt   Tests 111-120   (IRQ/NMI/exceptions)"
    echo "  mmu         Tests 121-127   (MMU/page tables)"
    echo "  timer       Tests 128       (timer hardware)"
    echo "  illegal     Tests 124-126   (illegal opcode handling)"
    echo "  privilege   Tests 122-123   (privilege traps)"
    echo "  fpu         Tests 100G-100W (FPU instructions)"
}

build_emulator() {
    echo -e "${YELLOW}Building emulator...${NC}"
    if make -C "$EMU_DIR" > /dev/null 2>&1; then
        echo -e "${GREEN}Build successful${NC}"
    else
        echo -e "${RED}Build failed${NC}"
        exit 1
    fi
}

# Parse arguments
VERBOSE=""
QUIET=""
BUILD=""
TEST_SPECS=""

while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE="--verbose"
            shift
            ;;
        -q|--quiet)
            QUIET="1"
            shift
            ;;
        -l|--list)
            list_tests
            exit 0
            ;;
        -c|--categories)
            list_categories
            exit 0
            ;;
        --build)
            BUILD="1"
            shift
            ;;
        --failing)
            # Known failing tests
            TEST_SPECS="$TEST_SPECS 79 84 85 87 95 96 97 99 114 127 128"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            TEST_SPECS="$TEST_SPECS $1"
            shift
            ;;
    esac
done

# Build if requested
if [ -n "$BUILD" ]; then
    build_emulator
fi

# Check emulator exists
if [ ! -x "$EMU_DIR/m65832emu" ]; then
    echo -e "${YELLOW}Emulator not found, building...${NC}"
    build_emulator
fi

# Expand test specs into --test arguments
TEST_ARGS=""
for spec in $TEST_SPECS; do
    # Check if it's a category
    range=$(get_category_range "$spec")
    if [ -n "$range" ]; then
        # It's a category - check if it's a numeric range or space-separated list
        if echo "$range" | grep -q '^[0-9]*-[0-9]*$'; then
            start="${range%-*}"
            end="${range#*-}"
            i=$start
            while [ $i -le $end ]; do
                TEST_ARGS="$TEST_ARGS --test $i"
                i=$((i + 1))
            done
        else
            # Space-separated list of test IDs (e.g., fpu category)
            for tid in $range; do
                TEST_ARGS="$TEST_ARGS --test $tid"
            done
        fi
    # Check if it's a numeric range
    elif echo "$spec" | grep -q '^[0-9]*-[0-9]*$'; then
        start="${spec%-*}"
        end="${spec#*-}"
        i=$start
        while [ $i -le $end ]; do
            TEST_ARGS="$TEST_ARGS --test $i"
            i=$((i + 1))
        done
    # Check if it's "all"
    elif [ "$spec" = "all" ]; then
        TEST_ARGS=""
        break
    # Otherwise it's a single test ID (number or alphanumeric like 100G)
    elif echo "$spec" | grep -q '^[0-9]*[A-Za-z]*$'; then
        TEST_ARGS="$TEST_ARGS --test $spec"
    else
        echo "Unknown test spec: $spec"
        exit 1
    fi
done

# Run tests
echo -e "${BLUE}Running M65832 emulator tests...${NC}"
echo ""

if [ -n "$QUIET" ]; then
    python3 "$TEST_SCRIPT" $VERBOSE $TEST_ARGS 2>&1 | tail -10
    exit_code=${PIPESTATUS[0]}
else
    python3 "$TEST_SCRIPT" $VERBOSE $TEST_ARGS 2>&1
    exit_code=$?
fi

if [ $exit_code -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
else
    echo -e "\n${YELLOW}Some tests failed${NC}"
fi

exit $exit_code
