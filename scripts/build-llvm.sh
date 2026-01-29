#!/bin/bash
# build-llvm.sh - Build LLVM/Clang for M65832
#
# Builds LLVM with the M65832 backend. Creates two build directories:
#   - build/      Full build with LLD
#   - build-fast/ Fast incremental build (clang only)
#
# Usage: ./build-llvm.sh [--full|--fast|--clean]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Configuration
# ============================================================================

BUILD_TYPE="${1:---fast}"

# ============================================================================
# Functions
# ============================================================================

build_full() {
    log_section "Building LLVM (full build with LLD)"
    
    if [ ! -d "$LLVM_SRC" ]; then
        log_error "LLVM source not found at $LLVM_SRC"
        log_info "Run: ./scripts/clone-deps.sh --llvm"
        exit 1
    fi
    
    mkdir -p "$LLVM_BUILD"
    
    log_info "Configuring LLVM..."
    cmake -G Ninja -S "$LLVM_SRC/llvm" -B "$LLVM_BUILD" \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_TARGETS_TO_BUILD=M65832 \
        -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=M65832 \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DCMAKE_BUILD_TYPE=Release
    
    log_info "Building LLVM (this may take a while)..."
    cmake --build "$LLVM_BUILD" -j "$JOBS"
    
    log_success "LLVM full build complete"
    log_info "Binaries at: $LLVM_BUILD/bin/"
}

build_fast() {
    log_section "Building LLVM (fast build - clang only)"
    
    if [ ! -d "$LLVM_SRC" ]; then
        log_error "LLVM source not found at $LLVM_SRC"
        log_info "Run: ./scripts/clone-deps.sh --llvm"
        exit 1
    fi
    
    # Configure if needed
    if [ ! -f "$LLVM_BUILD_FAST/build.ninja" ]; then
        log_info "Configuring LLVM (fast build)..."
        mkdir -p "$LLVM_BUILD_FAST"
        cmake -G Ninja -S "$LLVM_SRC/llvm" -B "$LLVM_BUILD_FAST" \
            -DLLVM_ENABLE_PROJECTS=clang \
            -DLLVM_TARGETS_TO_BUILD=M65832 \
            -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=M65832 \
            -DLLVM_INCLUDE_TESTS=OFF \
            -DLLVM_INCLUDE_EXAMPLES=OFF \
            -DLLVM_INCLUDE_DOCS=OFF \
            -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
            -DCLANG_ENABLE_ARCMT=OFF \
            -DCLANG_ENABLE_OBJC_REWRITER=OFF \
            -DCLANG_TOOL_CLANG_CHECK_BUILD=OFF \
            -DCLANG_TOOL_CLANG_FORMAT_BUILD=OFF \
            -DCLANG_TOOL_CLANG_OFFLOAD_BUNDLER_BUILD=OFF \
            -DCLANG_TOOL_CLANG_SCAN_DEPS_BUILD=OFF \
            -DCLANG_TOOL_CLANG_SHLIB_BUILD=OFF \
            -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
            -DCLANG_TOOL_DIAGTOOL_BUILD=OFF \
            -DCLANG_TOOL_CLANG_REPL_BUILD=OFF \
            -DCLANG_TOOL_CLANG_REFACTOR_BUILD=OFF \
            -DCLANG_TOOL_CLANG_DIFF_BUILD=OFF \
            -DCLANG_TOOL_CLANG_EXTDEF_MAPPING_BUILD=OFF \
            -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
            -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
            -DCLANG_TOOL_CLANG_NVLINK_WRAPPER_BUILD=OFF \
            -DCLANG_TOOL_CLANG_FUZZER_BUILD=OFF \
            -DCLANG_TOOL_CLANG_INSTALLAPI_BUILD=OFF \
            -DCLANG_TOOL_CLANG_LSP_BUILD=OFF \
            -DCLANG_TOOL_CLANG_SYCL_LINKER_BUILD=OFF \
            -DCLANG_TOOL_HANDLE_CXX_BUILD=OFF \
            -DCLANG_TOOL_HANDLE_LLVM_BUILD=OFF \
            -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
            -DCLANG_TOOL_OFFLOAD_ARCH_BUILD=OFF \
            -DCLANG_TOOL_SCAN_BUILD_BUILD=OFF \
            -DCLANG_TOOL_SCAN_VIEW_BUILD=OFF \
            -DCLANG_ENABLE_HLSL=OFF \
            -DLLVM_ENABLE_ASSERTIONS=OFF \
            -DCMAKE_BUILD_TYPE=Release
    fi
    
    log_info "Building clang..."
    cmake --build "$LLVM_BUILD_FAST" --target clang -j "$JOBS"
    
    log_success "LLVM fast build complete"
    log_info "Clang at: $LLVM_BUILD_FAST/bin/clang"
    
    # Check if LLD exists in full build, warn if not
    if [ ! -x "$LLD" ]; then
        log_warn "LLD not found at $LLD"
        log_warn "Run './scripts/build-llvm.sh --full' for LLD support"
    fi
}

clean_builds() {
    log_section "Cleaning LLVM builds"
    
    if [ -d "$LLVM_BUILD" ]; then
        log_info "Removing $LLVM_BUILD..."
        rm -rf "$LLVM_BUILD"
    fi
    
    if [ -d "$LLVM_BUILD_FAST" ]; then
        log_info "Removing $LLVM_BUILD_FAST..."
        rm -rf "$LLVM_BUILD_FAST"
    fi
    
    log_success "Clean complete"
}

print_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Build LLVM/Clang for M65832"
    echo ""
    echo "Options:"
    echo "  --fast      Fast incremental build (clang only, default)"
    echo "  --full      Full build with LLD"
    echo "  --clean     Remove build directories"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Build directories:"
    echo "  Full:  $LLVM_BUILD"
    echo "  Fast:  $LLVM_BUILD_FAST"
}

# ============================================================================
# Main
# ============================================================================

main() {
    check_prerequisites || exit 1
    
    case "$BUILD_TYPE" in
        --fast)
            build_fast
            ;;
        --full)
            build_full
            ;;
        --clean)
            clean_builds
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $BUILD_TYPE"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
