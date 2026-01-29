#!/bin/bash
# build-libc-linux.sh - Build musl libc for M65832 Linux userspace
#
# Builds musl with Linux syscalls (TRAP #0 instruction) for running
# as Linux userspace applications.
#
# Usage: ./build-libc-linux.sh [--clean|--rebuild]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Configuration
# ============================================================================

BUILD_ACTION="${1:-build}"

# ============================================================================
# Functions
# ============================================================================

check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check LLVM is built
    if [ ! -x "$CLANG" ]; then
        log_error "Clang not found at $CLANG"
        log_info "Run: ./scripts/build-llvm.sh --fast"
        exit 1
    fi
    
    # Check LLD is built
    if [ ! -x "$LLD" ]; then
        log_error "LLD not found at $LLD"
        log_info "Run: ./scripts/build-llvm.sh --full"
        exit 1
    fi
    
    # Check musl source exists
    if [ ! -d "$MUSL_SRC" ]; then
        log_error "musl source not found at $MUSL_SRC"
        log_info "Run: ./scripts/clone-deps.sh --musl"
        exit 1
    fi
    
    log_success "Dependencies OK"
}

build_musl() {
    log_section "Building musl for Linux Userspace"
    
    mkdir -p "$MUSL_BUILD"
    cd "$MUSL_BUILD"
    
    # Configure musl
    log_info "Configuring musl..."
    
    # Set up environment for cross-compilation
    export CC="$CLANG"
    export CFLAGS="-target m65832-linux -O1 -fPIC"
    export LDFLAGS="-fuse-ld=lld"
    export AR="$LLVM_AR"
    export RANLIB="$LLVM_RANLIB"
    
    # Run configure
    "$MUSL_SRC/configure" \
        --target=m65832 \
        --prefix="$SYSROOT_LINUX" \
        --disable-shared \
        --enable-static
    
    # Build
    log_info "Building musl..."
    make -j "$JOBS"
    
    # Install
    log_info "Installing musl..."
    make install
    
    log_success "musl build complete"
}

install_linux_syscalls() {
    log_section "Installing Linux Syscall Support"
    
    local lib_dir="$SYSROOT_LINUX/lib"
    local inc_dir="$SYSROOT_LINUX/include"
    local syscalls_src="$M65832_DIR/libc/linux/syscalls.c"
    
    mkdir -p "$lib_dir" "$inc_dir"
    
    # Check if we have Linux syscalls implementation
    if [ -f "$syscalls_src" ]; then
        log_info "Compiling Linux syscalls..."
        "$CLANG" -target m65832-linux -O1 \
            -I"$inc_dir" \
            -c "$syscalls_src" -o "$lib_dir/syscalls.o"
        
        "$LLVM_AR" rcs "$lib_dir/libsyscalls.a" "$lib_dir/syscalls.o"
        log_success "Linux syscalls installed"
    else
        log_warn "Linux syscalls source not found at $syscalls_src"
        log_warn "Using musl's default syscall interface"
    fi
}

clean_build() {
    log_section "Cleaning Linux Build"
    
    if [ -d "$MUSL_BUILD" ]; then
        log_info "Removing $MUSL_BUILD..."
        rm -rf "$MUSL_BUILD"
    fi
    
    if [ -d "$SYSROOT_LINUX" ]; then
        log_info "Removing $SYSROOT_LINUX..."
        rm -rf "$SYSROOT_LINUX"
    fi
    
    log_success "Clean complete"
}

print_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Build musl libc for M65832 Linux userspace"
    echo ""
    echo "Options:"
    echo "  (none)      Build musl"
    echo "  --rebuild   Clean and rebuild"
    echo "  --clean     Remove build directories"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Output: $SYSROOT_LINUX"
    echo ""
    echo "Note: This builds musl for Linux userspace applications."
    echo "      Programs will use TRAP #0 for Linux system calls."
}

print_summary() {
    log_section "Build Complete"
    echo "Sysroot:      $SYSROOT_LINUX"
    echo "Include:      $SYSROOT_LINUX/include"
    echo "Libraries:    $SYSROOT_LINUX/lib"
    echo ""
    echo "To compile Linux userspace programs:"
    echo ""
    echo "  $CLANG -target m65832-linux \\"
    echo "    -I$SYSROOT_LINUX/include \\"
    echo "    -c myprogram.c -o myprogram.o"
    echo ""
    echo "  $LLD \\"
    echo "    $SYSROOT_LINUX/lib/crt1.o myprogram.o \\"
    echo "    -L$SYSROOT_LINUX/lib -lc \\"
    echo "    -o myprogram"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    case "$BUILD_ACTION" in
        build)
            check_prerequisites || exit 1
            check_dependencies
            build_musl
            install_linux_syscalls
            print_summary
            ;;
        --rebuild)
            clean_build
            check_prerequisites || exit 1
            check_dependencies
            build_musl
            install_linux_syscalls
            print_summary
            ;;
        --clean)
            clean_build
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $BUILD_ACTION"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
