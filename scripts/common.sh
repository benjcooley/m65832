#!/bin/bash
# common.sh - Shared variables and functions for M65832 build scripts
#
# Source this file from other scripts:
#   source "$(dirname "$0")/common.sh"

set -e

# ============================================================================
# Directory Configuration
# ============================================================================

# Get the absolute path to the m65832 directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M65832_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$(dirname "$M65832_DIR")"

# Source repositories
LLVM_REPO="https://github.com/benjcooley/llvm-m65832.git"
PICOLIBC_REPO="https://github.com/benjcooley/picolibc-m65832.git"
MUSL_REPO="https://github.com/benjcooley/musl-m65832.git"
LINUX_REPO="https://github.com/benjcooley/linux-m65832.git"

# Source directories (adjacent to m65832)
LLVM_SRC="$PROJECTS_DIR/llvm-m65832"
PICOLIBC_SRC="$PROJECTS_DIR/picolibc-m65832"
MUSL_SRC="$PROJECTS_DIR/musl-m65832"
LINUX_SRC="$PROJECTS_DIR/linux-m65832"

# Build directories
LLVM_BUILD="$LLVM_SRC/build"
LLVM_BUILD_FAST="$LLVM_SRC/build-fast"
PICOLIBC_BUILD="$PROJECTS_DIR/picolibc-build-m65832"
PICOLIBC_BUILD_LINUX="$PROJECTS_DIR/picolibc-build-m65832-linux"
MUSL_BUILD="$PROJECTS_DIR/musl-build-m65832"
LINUX_BUILD="$PROJECTS_DIR/linux-build-m65832"

# Output directories (sysroots)
SYSROOT_BAREMETAL="$PROJECTS_DIR/m65832-sysroot"
SYSROOT_LINUX="$PROJECTS_DIR/m65832-sysroot-linux"

# Installed toolchain (populated by scripts/install-toolchain.sh)
TOOLCHAIN_BIN="$M65832_DIR/bin"

# Tools
CLANG="$TOOLCHAIN_BIN/clang"
LLD="$TOOLCHAIN_BIN/ld.lld"
LLVM_AR="$TOOLCHAIN_BIN/llvm-ar"
LLVM_RANLIB="$TOOLCHAIN_BIN/llvm-ranlib"
LLVM_OBJCOPY="$TOOLCHAIN_BIN/llvm-objcopy"
LLVM_NM="$TOOLCHAIN_BIN/llvm-nm"
LLVM_STRIP="$TOOLCHAIN_BIN/llvm-strip"
LLVM_OBJDUMP="$TOOLCHAIN_BIN/llvm-objdump"
LLVM_READELF="$TOOLCHAIN_BIN/llvm-readelf"
LLVM_SIZE="$TOOLCHAIN_BIN/llvm-size"
EMU="$TOOLCHAIN_BIN/m65832emu"
ASM="$TOOLCHAIN_BIN/m65832as"

# ============================================================================
# MMIO Configuration (must match FPGA and emulator)
# ============================================================================

MMIO_SYSREG_BASE="0x00FFF000"
MMIO_UART_BASE="0x00FFF100"
MMIO_BLKDEV_BASE="0x00FFF120"
MMIO_EXIT_CODE="0xFFFFFFFC"

# ============================================================================
# Build Configuration
# ============================================================================

# Number of parallel jobs (default: number of CPUs)
if [ -z "$JOBS" ]; then
    if command -v nproc &> /dev/null; then
        JOBS=$(nproc)
    elif command -v sysctl &> /dev/null; then
        JOBS=$(sysctl -n hw.ncpu)
    else
        JOBS=4
    fi
fi

# ============================================================================
# Color Output
# ============================================================================

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}$*${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
}

# Check if a command exists
check_command() {
    local cmd="$1"
    local install_hint="$2"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd not found"
        if [ -n "$install_hint" ]; then
            echo "  Install with: $install_hint"
        fi
        return 1
    fi
    return 0
}

# Check all prerequisites
check_prerequisites() {
    local missing=0
    
    log_info "Checking prerequisites..."
    
    check_command cmake "brew install cmake / apt install cmake" || missing=1
    check_command ninja "brew install ninja / apt install ninja-build" || missing=1
    check_command python3 "brew install python / apt install python3" || missing=1
    check_command meson "pip install meson" || missing=1
    check_command git "brew install git / apt install git" || missing=1
    
    if [ $missing -eq 1 ]; then
        log_error "Missing prerequisites. Please install them and try again."
        return 1
    fi
    
    log_success "All prerequisites found"
    return 0
}

# Clone a repository if it doesn't exist
clone_if_missing() {
    local repo="$1"
    local dir="$2"
    local branch="${3:-main}"
    
    if [ -d "$dir" ]; then
        log_info "Repository exists: $dir"
        return 0
    fi
    
    log_info "Cloning $repo (depth=1)..."
    git clone --depth=1 --branch "$branch" "$repo" "$dir"
    log_success "Cloned to $dir"
}

# Check if LLVM is built
check_llvm_built() {
    if [ ! -x "$CLANG" ]; then
        log_error "LLVM not built. Run: ./build.sh llvm"
        return 1
    fi
    return 0
}

# Check if the sysroot exists
check_sysroot() {
    local sysroot="$1"
    if [ ! -d "$sysroot/lib" ] || [ ! -d "$sysroot/include" ]; then
        return 1
    fi
    return 0
}

# Get the current platform
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Print build configuration
print_config() {
    log_section "Build Configuration"
    echo "M65832 Dir:      $M65832_DIR"
    echo "Projects Dir:    $PROJECTS_DIR"
    echo "LLVM Source:     $LLVM_SRC"
    echo "LLVM Build:      $LLVM_BUILD_FAST"
    echo "Picolibc Source: $PICOLIBC_SRC"
    echo "Baremetal Root:  $SYSROOT_BAREMETAL"
    echo "Linux Root:      $SYSROOT_LINUX"
    echo "Parallel Jobs:   $JOBS"
    echo "Platform:        $(detect_platform)"
    echo ""
}

# ============================================================================
# Export for subshells
# ============================================================================

export M65832_DIR PROJECTS_DIR
export LLVM_SRC LLVM_BUILD LLVM_BUILD_FAST
export PICOLIBC_SRC PICOLIBC_BUILD PICOLIBC_BUILD_LINUX
export SYSROOT_BAREMETAL SYSROOT_LINUX
export TOOLCHAIN_BIN
export CLANG LLD LLVM_AR LLVM_RANLIB
export LLVM_OBJCOPY LLVM_NM LLVM_STRIP LLVM_OBJDUMP LLVM_READELF LLVM_SIZE
export EMU ASM
export JOBS
