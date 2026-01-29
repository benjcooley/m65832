#!/bin/bash
# build.sh - M65832 Toolchain Bootstrap Script
#
# This is the main entry point for building the M65832 toolchain.
# It clones dependencies (with --depth=1) and builds everything needed.
#
# Usage:
#   ./build.sh baremetal    Build baremetal toolchain (FPGA/emulator)
#   ./build.sh linux        Build Linux userspace toolchain
#   ./build.sh all          Build everything
#   ./build.sh test         Run test suites
#   ./build.sh clean        Clean all builds
#
# Platform-specific:
#   ./build.sh baremetal de25    Build for DE2-115 FPGA
#   ./build.sh baremetal kv260   Build for Kria KV260

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

TARGET="${1:-help}"
PLATFORM="${2:-}"

# ============================================================================
# Build Functions
# ============================================================================

build_tools() {
    log_section "Building Tools (Emulator + Assembler)"
    
    log_info "Building emulator..."
    make -C "$M65832_DIR/emu" -j "$JOBS"
    
    log_info "Building assembler..."
    make -C "$M65832_DIR/as" -j "$JOBS"
    
    log_success "Tools built"
}

build_baremetal() {
    log_section "Building Baremetal Toolchain"
    
    local platform="$1"
    
    # Clone dependencies
    "$SCRIPT_DIR/scripts/clone-deps.sh" --llvm
    "$SCRIPT_DIR/scripts/clone-deps.sh" --picolibc
    
    # Build LLVM (full for LLD, then fast for clang)
    if [ ! -x "$LLD" ]; then
        "$SCRIPT_DIR/scripts/build-llvm.sh" --full
    fi
    "$SCRIPT_DIR/scripts/build-llvm.sh" --fast
    
    # Build picolibc
    "$SCRIPT_DIR/scripts/build-libc-baremetal.sh"
    
    # Build tools
    build_tools
    
    # Platform-specific configuration
    if [ -n "$platform" ]; then
        configure_platform "$platform"
    fi
    
    log_success "Baremetal toolchain ready"
    print_baremetal_summary
}

build_linux() {
    log_section "Building Linux Userspace Toolchain"
    
    # Clone dependencies
    "$SCRIPT_DIR/scripts/clone-deps.sh" --llvm
    "$SCRIPT_DIR/scripts/clone-deps.sh" --musl
    "$SCRIPT_DIR/scripts/clone-deps.sh" --linux
    
    # Build LLVM
    if [ ! -x "$LLD" ]; then
        "$SCRIPT_DIR/scripts/build-llvm.sh" --full
    fi
    "$SCRIPT_DIR/scripts/build-llvm.sh" --fast
    
    # Build musl
    "$SCRIPT_DIR/scripts/build-libc-linux.sh"
    
    # Build tools
    build_tools
    
    log_success "Linux toolchain ready"
    print_linux_summary
}

build_all() {
    log_section "Building Complete Toolchain"
    
    build_baremetal "$PLATFORM"
    build_linux
    
    log_success "All toolchains ready"
}

run_tests() {
    log_section "Running Tests"
    "$SCRIPT_DIR/scripts/run-tests.sh" --all
}

clean_all() {
    log_section "Cleaning All Builds"
    
    "$SCRIPT_DIR/scripts/build-llvm.sh" --clean
    "$SCRIPT_DIR/scripts/build-libc-baremetal.sh" --clean
    "$SCRIPT_DIR/scripts/build-libc-linux.sh" --clean
    
    log_info "Cleaning emulator..."
    make -C "$M65832_DIR/emu" clean 2>/dev/null || true
    
    log_info "Cleaning assembler..."
    make -C "$M65832_DIR/as" clean 2>/dev/null || true
    
    log_success "Clean complete"
}

configure_platform() {
    local platform="$1"
    local platform_dir="$M65832_DIR/platforms/$platform"
    
    if [ ! -d "$platform_dir" ]; then
        log_warn "Platform configuration not found: $platform"
        log_info "Available platforms:"
        ls -1 "$M65832_DIR/platforms/" 2>/dev/null || echo "  (none)"
        return
    fi
    
    log_info "Configuring for platform: $platform"
    
    # Source platform-specific configuration if it exists
    if [ -f "$platform_dir/config.sh" ]; then
        source "$platform_dir/config.sh"
    fi
}

# ============================================================================
# Summary Functions
# ============================================================================

print_baremetal_summary() {
    echo ""
    echo "Baremetal Toolchain Summary"
    echo "==========================="
    echo ""
    echo "Compiler:  $CLANG"
    echo "Linker:    $LLD"
    echo "Sysroot:   $SYSROOT_BAREMETAL"
    echo "Emulator:  $EMU"
    echo "Assembler: $ASM"
    echo ""
    echo "Quick compile example:"
    echo ""
    echo "  clang -target m65832-elf -ffreestanding \\"
    echo "    -I$SYSROOT_BAREMETAL/include \\"
    echo "    -c hello.c -o hello.o"
    echo ""
    echo "  ld.lld -T $SYSROOT_BAREMETAL/lib/m65832.ld \\"
    echo "    $SYSROOT_BAREMETAL/lib/crt0.o hello.o \\"
    echo "    -L$SYSROOT_BAREMETAL/lib -lc -lsys -o hello.elf"
    echo ""
    echo "  m65832emu hello.elf"
    echo ""
}

print_linux_summary() {
    echo ""
    echo "Linux Toolchain Summary"
    echo "======================="
    echo ""
    echo "Compiler:  $CLANG"
    echo "Linker:    $LLD"
    echo "Sysroot:   $SYSROOT_LINUX"
    echo ""
    echo "Quick compile example:"
    echo ""
    echo "  clang -target m65832-linux \\"
    echo "    -I$SYSROOT_LINUX/include \\"
    echo "    -c hello.c -o hello.o"
    echo ""
    echo "  ld.lld $SYSROOT_LINUX/lib/crt1.o hello.o \\"
    echo "    -L$SYSROOT_LINUX/lib -lc -o hello"
    echo ""
}

print_usage() {
    echo "M65832 Toolchain Build System"
    echo "=============================="
    echo ""
    echo "Usage: $0 <target> [platform]"
    echo ""
    echo "Targets:"
    echo "  baremetal [platform]  Build baremetal toolchain (picolibc + MMIO)"
    echo "  linux                 Build Linux userspace toolchain (musl + syscalls)"
    echo "  all                   Build everything"
    echo "  test                  Run test suites"
    echo "  clean                 Clean all build directories"
    echo "  help                  Show this help message"
    echo ""
    echo "Platforms (for baremetal):"
    echo "  de25                  DE2-115 FPGA board"
    echo "  kv260                 Kria KV260 board"
    echo ""
    echo "Examples:"
    echo "  $0 baremetal          Build baremetal toolchain"
    echo "  $0 baremetal de25     Build for DE2-115"
    echo "  $0 linux              Build Linux toolchain"
    echo "  $0 all                Build everything"
    echo "  $0 test               Run all tests"
    echo ""
    echo "For more information, see docs/M65832_Build_Guide.md"
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Print header
    echo ""
    echo "M65832 Build System"
    echo "==================="
    echo ""
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Dispatch to target
    case "$TARGET" in
        baremetal)
            build_baremetal "$PLATFORM"
            ;;
        linux)
            build_linux
            ;;
        all)
            build_all
            ;;
        test)
            run_tests
            ;;
        clean)
            clean_all
            ;;
        help|-h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown target: $TARGET"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
