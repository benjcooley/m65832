#!/bin/bash
# test.sh - M65832 Toolchain Test Runner
#
# This is the top-level test runner for the M65832 project. It runs
# various test suites to validate the toolchain, emulator, and RTL.
#
# Usage:
#   ./test.sh                Run all tests
#   ./test.sh --quick        Run quick smoke tests only
#   ./test.sh --compiler     Run compiler tests only
#   ./test.sh --emulator     Run emulator tests only
#   ./test.sh --assembler    Run assembler tests only
#   ./test.sh --rtl          Run RTL/VHDL tests only
#   ./test.sh --help         Show all options
#
# Prerequisites:
#   - Run ./configure.sh first
#   - Run ./build.sh to build tools (at minimum: emulator + assembler)

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.m65832_config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Fall back to common.sh if no config file
    if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
        source "$SCRIPT_DIR/scripts/common.sh"
    else
        echo "Error: No configuration found. Run ./configure.sh first."
        exit 1
    fi
fi

# Test options
TEST_TARGET="${1:---all}"
VERBOSE="${VERBOSE:-OFF}"

# Test counters
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# ============================================================================
# Color Output
# ============================================================================

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }
log_section() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}$*${NC}"
    echo -e "${BOLD}========================================${NC}"
}

# ============================================================================
# Utility Functions
# ============================================================================

# Check if a tool exists
check_tool() {
    local tool="$1"
    local path="$2"
    
    if [ ! -x "$path" ]; then
        return 1
    fi
    return 0
}

# Build a tool if it doesn't exist
ensure_tool() {
    local name="$1"
    local path="$2"
    local build_cmd="$3"
    
    if [ ! -x "$path" ]; then
        log_info "Building $name..."
        eval "$build_cmd"
        
        if [ ! -x "$path" ]; then
            log_fail "Failed to build $name"
            return 1
        fi
    fi
    return 0
}

# Run a test suite and track results
run_suite() {
    local name="$1"
    local cmd="$2"
    local pass=0
    local fail=0
    
    log_section "$name"
    
    if eval "$cmd"; then
        log_success "$name completed successfully"
        return 0
    else
        log_fail "$name had failures"
        return 1
    fi
}

# ============================================================================
# Test Suites
# ============================================================================

# Emulator basic tests
test_emulator_basic() {
    log_section "Emulator Basic Tests"
    
    # Ensure emulator is built
    if ! ensure_tool "emulator" "$EMU" "make -C '$M65832_DIR/emu' -j ${JOBS:-4}"; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Emulator not available"
        return 1
    fi
    
    # Ensure assembler is built
    if ! ensure_tool "assembler" "$ASM" "make -C '$M65832_DIR/as' -j ${JOBS:-4}"; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Assembler not available"
        return 1
    fi
    
    # Run emulator tests
    cd "$M65832_DIR/emu"
    if ./run_tests.sh; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
        return 0
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        return 1
    fi
}

# Assembler tests
test_assembler() {
    log_section "Assembler Tests"
    
    # Ensure assembler is built
    if ! ensure_tool "assembler" "$ASM" "make -C '$M65832_DIR/as' -j ${JOBS:-4}"; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Assembler not available"
        return 1
    fi
    
    # Check if assembler has tests
    if [ -f "$M65832_DIR/as/run_tests.sh" ]; then
        cd "$M65832_DIR/as"
        if ./run_tests.sh; then
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    else
        # Run basic assembler validation
        log_info "Running basic assembler validation..."
        local test_asm="/tmp/m65832_asm_test.asm"
        local test_bin="/tmp/m65832_asm_test.bin"
        
        cat > "$test_asm" << 'EOF'
    .org $1000
start:
    LDA #$42
    STP
EOF
        
        if "$ASM" "$test_asm" -o "$test_bin" 2>/dev/null; then
            log_success "Assembler basic validation passed"
            rm -f "$test_asm" "$test_bin"
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            log_fail "Assembler basic validation failed"
            rm -f "$test_asm" "$test_bin"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    fi
}

# Core C compiler tests
test_compiler_core() {
    log_section "Core C Compiler Tests"
    
    # Check if LLVM is built
    if [ ! -x "$CLANG" ]; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Clang not built (run ./build.sh first)"
        return 1
    fi
    
    # Ensure emulator is built
    if ! ensure_tool "emulator" "$EMU" "make -C '$M65832_DIR/emu' -j ${JOBS:-4}"; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Emulator not available"
        return 1
    fi
    
    local test_dir="$M65832_DIR/emu/c_tests"
    
    if [ ! -d "$test_dir" ]; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "C test directory not found: $test_dir"
        return 1
    fi
    
    cd "$test_dir"
    
    if [ -x "./run_core_tests.sh" ]; then
        if ./run_core_tests.sh; then
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    else
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Core test runner not found"
        return 1
    fi
}

# Inline assembly tests
test_inline_asm() {
    log_section "Inline Assembly Tests"
    
    if [ ! -x "$CLANG" ]; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Clang not built"
        return 1
    fi
    
    local test_dir="$M65832_DIR/emu/c_tests"
    
    if [ -x "$test_dir/test_inline_asm.sh" ]; then
        cd "$test_dir"
        if ./test_inline_asm.sh; then
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    else
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Inline assembly tests not found"
        return 1
    fi
}

# Picolibc integration tests
test_picolibc() {
    log_section "Picolibc Integration Tests"
    
    if [ ! -x "$CLANG" ]; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Clang not built"
        return 1
    fi
    
    if [ ! -d "$SYSROOT_BAREMETAL/lib" ]; then
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Baremetal sysroot not built"
        return 1
    fi
    
    local test_dir="$M65832_DIR/emu/c_tests"
    
    if [ -x "$test_dir/run_picolibc_suite.sh" ]; then
        cd "$test_dir"
        if ./run_picolibc_suite.sh; then
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    else
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "Picolibc test runner not found"
        return 1
    fi
}

# RTL/VHDL tests using GHDL
test_rtl() {
    log_section "RTL/VHDL Tests"
    
    if [ "$HAVE_GHDL" != "ON" ]; then
        if ! command -v ghdl &> /dev/null; then
            TOTAL_SKIP=$((TOTAL_SKIP + 1))
            log_skip "GHDL not installed"
            return 1
        fi
    fi
    
    cd "$M65832_DIR"
    
    if [ -x "tb/run_tests.sh" ]; then
        if ./tb/run_tests.sh; then
            TOTAL_PASS=$((TOTAL_PASS + 1))
            return 0
        else
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            return 1
        fi
    else
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        log_skip "RTL test runner not found"
        return 1
    fi
}

# Quick smoke tests (fast validation)
test_smoke() {
    log_section "Quick Smoke Tests"
    
    local pass=0
    local fail=0
    
    # Test 1: Assembler can assemble
    echo -n "  Assembler... "
    if ensure_tool "assembler" "$ASM" "make -C '$M65832_DIR/as' -j ${JOBS:-4}" 2>/dev/null; then
        local test_asm="/tmp/smoke_test.asm"
        echo -e ".org \$1000\n    LDA #\$42\n    STP" > "$test_asm"
        if "$ASM" "$test_asm" -o "/tmp/smoke_test.bin" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
            pass=$((pass + 1))
        else
            echo -e "${RED}FAIL${NC}"
            fail=$((fail + 1))
        fi
        rm -f "$test_asm" "/tmp/smoke_test.bin"
    else
        echo -e "${RED}FAIL (build)${NC}"
        fail=$((fail + 1))
    fi
    
    # Test 2: Emulator can run
    echo -n "  Emulator... "
    if ensure_tool "emulator" "$EMU" "make -C '$M65832_DIR/emu' -j ${JOBS:-4}" 2>/dev/null; then
        if "$EMU" --help 2>&1 | grep -q "M65832"; then
            echo -e "${GREEN}OK${NC}"
            pass=$((pass + 1))
        else
            echo -e "${RED}FAIL${NC}"
            fail=$((fail + 1))
        fi
    else
        echo -e "${RED}FAIL (build)${NC}"
        fail=$((fail + 1))
    fi
    
    # Test 3: Assembler + Emulator integration
    echo -n "  Integration... "
    local test_asm="/tmp/integration_test.asm"
    local test_bin="/tmp/integration_test.bin"
    echo -e ".org \$1000\n    LDA #\$42\n    STP" > "$test_asm"
    
    if "$ASM" "$test_asm" -o "$test_bin" 2>/dev/null; then
        local result
        # Look for the register line format: "A: 00000042" (with PC before it)
        result=$("$EMU" -c 100 -s "$test_bin" 2>&1 | grep "PC:.*A:" | head -1 || true)
        # Match "A: 00000042" - the accumulator should be 0x42
        if echo "$result" | grep -qE "A: 00000042"; then
            echo -e "${GREEN}OK${NC}"
            pass=$((pass + 1))
        else
            echo -e "${RED}FAIL${NC}"
            fail=$((fail + 1))
        fi
    else
        echo -e "${RED}FAIL (asm)${NC}"
        fail=$((fail + 1))
    fi
    rm -f "$test_asm" "$test_bin"
    
    # Test 4: Check if Clang exists (optional)
    echo -n "  Clang... "
    if [ -x "$CLANG" ]; then
        if "$CLANG" --version 2>&1 | grep -q "clang"; then
            echo -e "${GREEN}OK${NC}"
            pass=$((pass + 1))
        else
            echo -e "${RED}FAIL${NC}"
            fail=$((fail + 1))
        fi
    else
        echo -e "${YELLOW}SKIP (not built)${NC}"
    fi
    
    echo ""
    log_info "Smoke tests: $pass passed, $fail failed"
    
    if [ $fail -eq 0 ]; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
        return 0
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        return 1
    fi
}

# Run all tests
test_all() {
    local failed=0
    
    test_emulator_basic || failed=1
    test_assembler || failed=1
    test_compiler_core || failed=1
    test_inline_asm || failed=1
    test_picolibc || failed=1
    test_rtl || failed=1
    
    return $failed
}

# ============================================================================
# Help
# ============================================================================

print_usage() {
    cat << EOF
M65832 Toolchain Test Runner

Usage: $0 [OPTIONS]

Test Selection:
  --all, -a             Run all test suites (default)
  --quick, -q           Run quick smoke tests only
  --compiler, -c        Run compiler tests only
  --emulator, -e        Run emulator tests only
  --assembler, -s       Run assembler tests only
  --rtl, -r             Run RTL/VHDL tests only
  --picolibc, -p        Run picolibc integration tests
  --inline-asm          Run inline assembly tests

Options:
  --verbose, -v         Verbose output
  --help, -h            Show this help message

Examples:
  $0                    # Run all tests
  $0 --quick            # Quick smoke tests
  $0 --compiler         # Compiler tests only
  $0 -e -s              # Emulator and assembler tests

Prerequisites:
  1. Run ./configure.sh first
  2. Run ./build.sh to build tools (emulator + assembler minimum)
  3. For compiler tests, run ./build.sh baremetal

Test Suites:
  - Smoke:      Basic tool validation (~5 seconds)
  - Emulator:   Emulator instruction tests (~30 seconds)
  - Assembler:  Assembler syntax tests (~10 seconds)
  - Compiler:   C compiler code generation (~5 minutes)
  - Picolibc:   C library integration (~2 minutes)
  - RTL:        VHDL simulation tests (~10 minutes, requires GHDL)
EOF
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    log_section "Test Summary"
    
    echo ""
    echo -e "  ${GREEN}Passed:${NC}  $TOTAL_PASS"
    echo -e "  ${RED}Failed:${NC}  $TOTAL_FAIL"
    echo -e "  ${YELLOW}Skipped:${NC} $TOTAL_SKIP"
    echo ""
    
    if [ $TOTAL_FAIL -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_fail "Some tests failed"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "M65832 Toolchain Test Suite"
    echo "============================"
    
    local failed=0
    
    case "$TEST_TARGET" in
        --all|-a)
            test_all || failed=1
            ;;
        --quick|-q)
            test_smoke || failed=1
            ;;
        --compiler|-c)
            test_compiler_core || failed=1
            ;;
        --emulator|-e)
            test_emulator_basic || failed=1
            ;;
        --assembler|-s)
            test_assembler || failed=1
            ;;
        --rtl|-r)
            test_rtl || failed=1
            ;;
        --picolibc|-p)
            test_picolibc || failed=1
            ;;
        --inline-asm)
            test_inline_asm || failed=1
            ;;
        --verbose|-v)
            VERBOSE="ON"
            test_all || failed=1
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            # Check if it's a combined short option
            if [[ "$TEST_TARGET" == -* ]]; then
                for (( i=1; i<${#TEST_TARGET}; i++ )); do
                    char="${TEST_TARGET:$i:1}"
                    case "$char" in
                        a) test_all || failed=1 ;;
                        q) test_smoke || failed=1 ;;
                        c) test_compiler_core || failed=1 ;;
                        e) test_emulator_basic || failed=1 ;;
                        s) test_assembler || failed=1 ;;
                        r) test_rtl || failed=1 ;;
                        p) test_picolibc || failed=1 ;;
                        v) VERBOSE="ON" ;;
                        h) print_usage; exit 0 ;;
                        *) 
                            log_fail "Unknown option: -$char"
                            print_usage
                            exit 1
                            ;;
                    esac
                done
            else
                log_fail "Unknown option: $TEST_TARGET"
                echo ""
                print_usage
                exit 1
            fi
            ;;
    esac
    
    print_summary
    
    if [ $TOTAL_FAIL -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"
