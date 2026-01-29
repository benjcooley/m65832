#!/bin/bash
# run-tests.sh - Run M65832 test suites
#
# Runs various test suites to validate the toolchain:
#   - Core C compiler tests (151 tests)
#   - Picolibc integration tests
#   - Assembler tests
#   - Emulator tests
#
# Usage: ./run-tests.sh [--all|--core|--picolibc|--asm|--emu]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Configuration
# ============================================================================

TEST_TARGET="${1:---all}"

# Test directories
CORE_TESTS="$M65832_DIR/emu/c_tests"
ASM_TESTS="$M65832_DIR/as/test"
STDLIB_TESTS="$LLVM_SRC/m65832-stdlib/test"

# ============================================================================
# Functions
# ============================================================================

check_emulator() {
    if [ ! -x "$EMU" ]; then
        log_warn "Emulator not found at $EMU"
        log_info "Building emulator..."
        make -C "$M65832_DIR/emu" -j "$JOBS"
    fi
}

check_assembler() {
    if [ ! -x "$ASM" ]; then
        log_warn "Assembler not found at $ASM"
        log_info "Building assembler..."
        make -C "$M65832_DIR/as" -j "$JOBS"
    fi
}

run_core_tests() {
    log_section "Running Core C Compiler Tests"
    
    check_emulator
    
    if [ ! -d "$CORE_TESTS" ]; then
        log_error "Core tests not found at $CORE_TESTS"
        return 1
    fi
    
    cd "$CORE_TESTS"
    
    if [ -x "./run_core_tests.sh" ]; then
        ./run_core_tests.sh
    else
        log_error "Test runner not found: $CORE_TESTS/run_core_tests.sh"
        return 1
    fi
}

run_picolibc_tests() {
    log_section "Running Picolibc Integration Tests"
    
    check_emulator
    
    if [ ! -d "$CORE_TESTS" ]; then
        log_error "Test directory not found at $CORE_TESTS"
        return 1
    fi
    
    cd "$CORE_TESTS"
    
    if [ -x "./run_picolibc_suite.sh" ]; then
        ./run_picolibc_suite.sh
    else
        log_warn "Picolibc test runner not found"
    fi
}

run_stdlib_tests() {
    log_section "Running Stdlib Tests"
    
    check_emulator
    
    if [ ! -d "$STDLIB_TESTS" ]; then
        log_error "Stdlib tests not found at $STDLIB_TESTS"
        return 1
    fi
    
    cd "$STDLIB_TESTS"
    
    if [ -x "./run_tests.sh" ]; then
        ./run_tests.sh
    else
        log_error "Test runner not found: $STDLIB_TESTS/run_tests.sh"
        return 1
    fi
}

run_asm_tests() {
    log_section "Running Assembler Tests"
    
    check_assembler
    
    if [ ! -d "$ASM_TESTS" ]; then
        log_error "Assembler tests not found at $ASM_TESTS"
        return 1
    fi
    
    cd "$M65832_DIR/as"
    
    if [ -x "./run_tests.sh" ]; then
        ./run_tests.sh
    else
        log_error "Test runner not found: $M65832_DIR/as/run_tests.sh"
        return 1
    fi
}

run_emu_tests() {
    log_section "Running Emulator Self-Tests"
    
    check_emulator
    
    # Basic sanity check - run a simple program
    log_info "Testing emulator with simple program..."
    
    local test_file="/tmp/m65832_emu_test.s"
    local test_bin="/tmp/m65832_emu_test.bin"
    
    cat > "$test_file" << 'EOF'
    .org $1000
start:
    LDA #$42
    STP
EOF
    
    "$ASM" "$test_file" -o "$test_bin" 2>/dev/null
    
    local result
    result=$("$EMU" -c 100 -s "$test_bin" 2>&1 | grep "A:" | head -1)
    
    if echo "$result" | grep -q "0000002A\|00000042"; then
        log_success "Emulator basic test passed"
    else
        log_error "Emulator basic test failed"
        log_error "Expected A=0x42, got: $result"
        return 1
    fi
    
    rm -f "$test_file" "$test_bin"
}

run_all_tests() {
    local failed=0
    
    run_emu_tests || failed=1
    run_asm_tests || failed=1
    run_core_tests || failed=1
    run_stdlib_tests || failed=1
    run_picolibc_tests || failed=1
    
    if [ $failed -eq 0 ]; then
        log_section "All Tests Passed"
    else
        log_section "Some Tests Failed"
        return 1
    fi
}

print_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Run M65832 test suites"
    echo ""
    echo "Options:"
    echo "  --all       Run all tests (default)"
    echo "  --core      Run core C compiler tests (151 tests)"
    echo "  --stdlib    Run stdlib tests"
    echo "  --picolibc  Run picolibc integration tests"
    echo "  --asm       Run assembler tests"
    echo "  --emu       Run emulator self-tests"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Test locations:"
    echo "  Core:     $CORE_TESTS"
    echo "  Stdlib:   $STDLIB_TESTS"
    echo "  ASM:      $ASM_TESTS"
}

# ============================================================================
# Main
# ============================================================================

main() {
    case "$TEST_TARGET" in
        --all)
            run_all_tests
            ;;
        --core)
            run_core_tests
            ;;
        --stdlib)
            run_stdlib_tests
            ;;
        --picolibc)
            run_picolibc_tests
            ;;
        --asm)
            run_asm_tests
            ;;
        --emu)
            run_emu_tests
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $TEST_TARGET"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
