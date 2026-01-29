#!/bin/bash
# configure.sh - M65832 Toolchain Configuration
#
# This script configures the build environment for the M65832 toolchain.
# It detects the host platform, validates prerequisites, and generates
# a configuration file that build.sh and test.sh use.
#
# Usage:
#   ./configure.sh                    Auto-detect and configure
#   ./configure.sh --target=baremetal Configure for baremetal
#   ./configure.sh --target=linux     Configure for Linux userspace
#   ./configure.sh --platform=de25    Configure for DE2-115 FPGA
#   ./configure.sh --help             Show all options
#
# After running configure, use:
#   ./build.sh      Build the toolchain
#   ./test.sh       Run the test suite

set -e

# ============================================================================
# Configuration Variables
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.m65832_config"

# Defaults
TARGET="baremetal"
PLATFORM=""
JOBS=""
LLVM_ASSERTIONS="OFF"
DEBUG_BUILD="OFF"
SKIP_CLONE="OFF"
SHALLOW_CLONE="ON"
VERBOSE="OFF"

# ============================================================================
# Color Output
# ============================================================================

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================================
# Host Detection
# ============================================================================

detect_host_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

detect_host_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "aarch64" ;;
        *) echo "$(uname -m)" ;;
    esac
}

detect_cpu_count() {
    if command -v nproc &> /dev/null; then
        nproc
    elif command -v sysctl &> /dev/null; then
        sysctl -n hw.ncpu 2>/dev/null || echo "4"
    else
        echo "4"
    fi
}

# ============================================================================
# Prerequisite Checking
# ============================================================================

check_command() {
    local cmd="$1"
    local install_hint="$2"
    local version_cmd="${3:-}"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd not found"
        if [ -n "$install_hint" ]; then
            echo "  Install with: $install_hint"
        fi
        return 1
    fi
    
    if [ -n "$version_cmd" ]; then
        local version
        version=$(eval "$version_cmd" 2>/dev/null || echo "unknown")
        log_info "  $cmd: $version"
    else
        log_info "  $cmd: found"
    fi
    return 0
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=0
    
    local host_os
    host_os=$(detect_host_os)
    
    case "$host_os" in
        macos)
            check_command cmake "brew install cmake" "cmake --version | head -1" || missing=1
            check_command ninja "brew install ninja" "ninja --version" || missing=1
            check_command python3 "brew install python" "python3 --version" || missing=1
            check_command meson "pip3 install meson" "meson --version" || missing=1
            check_command git "brew install git" "git --version" || missing=1
            check_command make "" "make --version | head -1" || missing=1
            ;;
        linux)
            check_command cmake "apt install cmake" "cmake --version | head -1" || missing=1
            check_command ninja "apt install ninja-build" "ninja --version" || missing=1
            check_command python3 "apt install python3" "python3 --version" || missing=1
            check_command meson "pip3 install meson" "meson --version" || missing=1
            check_command git "apt install git" "git --version" || missing=1
            check_command make "" "make --version | head -1" || missing=1
            ;;
        *)
            check_command cmake "" "cmake --version | head -1" || missing=1
            check_command ninja "" "ninja --version" || missing=1
            check_command python3 "" "python3 --version" || missing=1
            check_command meson "" "meson --version" || missing=1
            check_command git "" "git --version" || missing=1
            check_command make "" "make --version | head -1" || missing=1
            ;;
    esac
    
    # Check for GHDL (optional, for RTL tests)
    if command -v ghdl &> /dev/null; then
        log_info "  ghdl: $(ghdl --version | head -1) (optional)"
        HAVE_GHDL="ON"
    else
        log_info "  ghdl: not found (RTL tests disabled)"
        HAVE_GHDL="OFF"
    fi
    
    # Check for host C compiler
    if command -v clang &> /dev/null; then
        log_info "  host cc: clang $(clang --version | head -1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1)"
        HOST_CC="clang"
        HOST_CXX="clang++"
    elif command -v gcc &> /dev/null; then
        log_info "  host cc: gcc $(gcc --version | head -1)"
        HOST_CC="gcc"
        HOST_CXX="g++"
    else
        log_error "No C compiler found (need clang or gcc)"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Missing prerequisites. Please install them and try again."
        return 1
    fi
    
    log_success "All prerequisites found"
    return 0
}

# ============================================================================
# Sibling Repository Detection
# ============================================================================

check_sibling_repos() {
    log_info "Checking sibling repositories..."
    
    local projects_dir
    projects_dir=$(dirname "$SCRIPT_DIR")
    
    LLVM_SRC="$projects_dir/llvm-m65832"
    PICOLIBC_SRC="$projects_dir/picolibc-m65832"
    MUSL_SRC="$projects_dir/musl-m65832"
    LINUX_SRC="$projects_dir/linux-m65832"
    
    local repos_found=0
    local repos_missing=0
    
    for repo in "$LLVM_SRC" "$PICOLIBC_SRC" "$MUSL_SRC" "$LINUX_SRC"; do
        local name
        name=$(basename "$repo")
        if [ -d "$repo" ]; then
            log_info "  $name: found"
            repos_found=$((repos_found + 1))
        else
            log_info "  $name: not found (will clone)"
            repos_missing=$((repos_missing + 1))
        fi
    done
    
    if [ $repos_missing -gt 0 ]; then
        log_warn "$repos_missing repositories will be cloned during build"
    fi
    
    return 0
}

# ============================================================================
# Configuration Generation
# ============================================================================

generate_config() {
    log_info "Generating configuration..."
    
    local host_os host_arch cpu_count
    host_os=$(detect_host_os)
    host_arch=$(detect_host_arch)
    cpu_count=$(detect_cpu_count)
    
    # Use specified jobs or default to CPU count
    if [ -z "$JOBS" ]; then
        JOBS=$cpu_count
    fi
    
    local projects_dir
    projects_dir=$(dirname "$SCRIPT_DIR")
    
    cat > "$CONFIG_FILE" << EOF
# M65832 Toolchain Configuration
# Generated by configure.sh on $(date)
# Do not edit manually - re-run ./configure.sh instead

# ============================================================================
# Host Configuration
# ============================================================================
HOST_OS="$host_os"
HOST_ARCH="$host_arch"
HOST_CC="$HOST_CC"
HOST_CXX="$HOST_CXX"

# ============================================================================
# Build Configuration
# ============================================================================
TARGET="$TARGET"
PLATFORM="$PLATFORM"
JOBS="$JOBS"
DEBUG_BUILD="$DEBUG_BUILD"
LLVM_ASSERTIONS="$LLVM_ASSERTIONS"

# ============================================================================
# Clone Configuration
# ============================================================================
SKIP_CLONE="$SKIP_CLONE"
SHALLOW_CLONE="$SHALLOW_CLONE"

# ============================================================================
# Optional Features
# ============================================================================
HAVE_GHDL="$HAVE_GHDL"
VERBOSE="$VERBOSE"

# ============================================================================
# Directory Configuration
# ============================================================================
M65832_DIR="$SCRIPT_DIR"
PROJECTS_DIR="$projects_dir"

# Source repositories (sibling directories)
LLVM_SRC="$projects_dir/llvm-m65832"
PICOLIBC_SRC="$projects_dir/picolibc-m65832"
MUSL_SRC="$projects_dir/musl-m65832"
LINUX_SRC="$projects_dir/linux-m65832"

# Build directories
LLVM_BUILD="$projects_dir/llvm-m65832/build"
LLVM_BUILD_FAST="$projects_dir/llvm-m65832/build-fast"
PICOLIBC_BUILD="$projects_dir/picolibc-build-m65832"
MUSL_BUILD="$projects_dir/musl-build-m65832"
LINUX_BUILD="$projects_dir/linux-build-m65832"

# Output sysroots
SYSROOT_BAREMETAL="$projects_dir/m65832-sysroot"
SYSROOT_LINUX="$projects_dir/m65832-sysroot-linux"

# Tools (after build)
CLANG="$projects_dir/llvm-m65832/build-fast/bin/clang"
LLD="$projects_dir/llvm-m65832/build/bin/ld.lld"
LLVM_AR="$projects_dir/llvm-m65832/build-fast/bin/llvm-ar"
LLVM_RANLIB="$projects_dir/llvm-m65832/build-fast/bin/llvm-ranlib"
EMU="$SCRIPT_DIR/emu/m65832emu"
ASM="$SCRIPT_DIR/as/m65832as"

# ============================================================================
# Repository URLs
# ============================================================================
LLVM_REPO="https://github.com/benjcooley/llvm-m65832.git"
PICOLIBC_REPO="https://github.com/benjcooley/picolibc-m65832.git"
MUSL_REPO="https://github.com/benjcooley/musl-m65832.git"
LINUX_REPO="https://github.com/benjcooley/linux-m65832.git"
EOF

    log_success "Configuration written to .m65832_config"
}

# ============================================================================
# Help and Summary
# ============================================================================

print_usage() {
    cat << EOF
M65832 Toolchain Configuration Script

Usage: $0 [OPTIONS]

Target Options:
  --target=TARGET       Build target: baremetal, linux, all (default: baremetal)
  --platform=PLATFORM   Hardware platform: de25, kv260 (for baremetal)

Build Options:
  --jobs=N              Number of parallel jobs (default: auto-detect)
  --debug               Enable debug build (unoptimized, with assertions)
  --assertions          Enable LLVM assertions

Clone Options:
  --skip-clone          Assume repositories already exist
  --no-shallow          Use full git clone instead of --depth=1

Advanced Options:
  --verbose             Enable verbose output
  --help, -h            Show this help message

Examples:
  $0                            # Auto-configure for baremetal
  $0 --target=linux             # Configure for Linux userspace
  $0 --target=baremetal --platform=de25  # Configure for DE2-115 FPGA
  $0 --jobs=4 --debug           # Debug build with 4 jobs

After configuring, use:
  ./build.sh            # Build the toolchain
  ./test.sh             # Run tests
  ./build.sh clean      # Clean build artifacts
EOF
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Configuration Summary"
    echo "=========================================="
    echo ""
    echo "Host:        $(detect_host_os) / $(detect_host_arch)"
    echo "Target:      $TARGET"
    if [ -n "$PLATFORM" ]; then
        echo "Platform:    $PLATFORM"
    fi
    echo "Jobs:        $JOBS"
    echo "Debug:       $DEBUG_BUILD"
    echo "GHDL:        $HAVE_GHDL (RTL tests)"
    echo ""
    echo "Directories:"
    echo "  Project:   $SCRIPT_DIR"
    echo "  Sysroot:   $(dirname "$SCRIPT_DIR")/m65832-sysroot"
    echo ""
    echo "Next steps:"
    echo "  1. Run ./build.sh to build the toolchain"
    echo "  2. Run ./test.sh to verify the build"
    echo ""
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --target=*)
                TARGET="${1#*=}"
                case "$TARGET" in
                    baremetal|linux|all) ;;
                    *)
                        log_error "Invalid target: $TARGET"
                        log_error "Valid targets: baremetal, linux, all"
                        exit 1
                        ;;
                esac
                ;;
            --platform=*)
                PLATFORM="${1#*=}"
                case "$PLATFORM" in
                    de25|kv260|"") ;;
                    *)
                        log_error "Invalid platform: $PLATFORM"
                        log_error "Valid platforms: de25, kv260"
                        exit 1
                        ;;
                esac
                ;;
            --jobs=*)
                JOBS="${1#*=}"
                if ! [[ "$JOBS" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid job count: $JOBS"
                    exit 1
                fi
                ;;
            --debug)
                DEBUG_BUILD="ON"
                LLVM_ASSERTIONS="ON"
                ;;
            --assertions)
                LLVM_ASSERTIONS="ON"
                ;;
            --skip-clone)
                SKIP_CLONE="ON"
                ;;
            --no-shallow)
                SHALLOW_CLONE="OFF"
                ;;
            --verbose)
                VERBOSE="ON"
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                print_usage
                exit 1
                ;;
        esac
        shift
    done
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "M65832 Toolchain Configuration"
    echo "==============================="
    echo ""
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites || exit 1
    echo ""
    
    # Check sibling repositories
    check_sibling_repos
    echo ""
    
    # Generate configuration file
    generate_config
    
    # Print summary
    print_summary
}

main "$@"
