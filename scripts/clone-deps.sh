#!/bin/bash
# clone-deps.sh - Clone M65832 dependencies
#
# Clones llvm-m65832 and picolibc-m65832 repositories if they don't exist.
# Uses --depth=1 for faster cloning.
#
# Usage: ./clone-deps.sh [--all|--llvm|--picolibc|--linux]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Functions
# ============================================================================

clone_llvm() {
    log_section "Cloning LLVM"
    clone_if_missing "$LLVM_REPO" "$LLVM_SRC" "main"
}

clone_picolibc() {
    log_section "Cloning Picolibc"
    clone_if_missing "$PICOLIBC_REPO" "$PICOLIBC_SRC" "main"
}

clone_musl() {
    log_section "Cloning musl"
    clone_if_missing "$MUSL_REPO" "$MUSL_SRC" "main"
}

clone_linux() {
    log_section "Cloning Linux"
    clone_if_missing "$LINUX_REPO" "$LINUX_SRC" "m65832"
}

clone_all() {
    clone_llvm
    clone_picolibc
    clone_musl
    clone_linux
}

print_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Clone M65832 dependencies with --depth=1"
    echo ""
    echo "Options:"
    echo "  --all       Clone all dependencies (default)"
    echo "  --llvm      Clone only llvm-m65832"
    echo "  --picolibc  Clone only picolibc-m65832"
    echo "  --musl      Clone only musl-m65832"
    echo "  --linux     Clone only linux-m65832"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Repositories:"
    echo "  LLVM:     $LLVM_REPO"
    echo "  Picolibc: $PICOLIBC_REPO"
    echo "  musl:     $MUSL_REPO"
    echo "  Linux:    $LINUX_REPO"
}

# ============================================================================
# Main
# ============================================================================

main() {
    local target="${1:---all}"
    
    case "$target" in
        --all)
            clone_all
            ;;
        --llvm)
            clone_llvm
            ;;
        --picolibc)
            clone_picolibc
            ;;
        --musl)
            clone_musl
            ;;
        --linux)
            clone_linux
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $target"
            print_usage
            exit 1
            ;;
    esac
    
    log_success "Dependencies cloned successfully"
}

main "$@"
