#!/bin/bash
# install-toolchain.sh - Install M65832 toolchain binaries to m65832/bin/
#
# Copies LLVM cross-compiler tools from the build directory and native
# tools (emulator, assembler) into the canonical toolchain bin/ directory.
#
# Usage: ./install-toolchain.sh [--clean]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Configuration
# ============================================================================

# Where LLVM tools are built
LLVM_BIN="$LLVM_BUILD_FAST/bin"

# Where native tools are built
EMU_SRC="$M65832_DIR/emu/m65832emu"
ASM_SRC="$M65832_DIR/as/m65832as"

# Destination
DEST="$TOOLCHAIN_BIN"

# ============================================================================
# LLVM binaries to install (actual files, not symlinks)
# ============================================================================

LLVM_BINARIES=(
    clang-23
    lld
    llvm-ar
    llvm-nm
    llvm-objcopy
    llvm-objdump
    llvm-readobj
    llvm-size
    llvm-strings
    llvm-symbolizer
    llvm-cxxfilt
)

# Symlinks to create (target -> link_name)
LLVM_SYMLINKS=(
    "clang-23:clang"
    "clang-23:clang++"
    "lld:ld.lld"
    "llvm-ar:llvm-ranlib"
    "llvm-objcopy:llvm-strip"
    "llvm-readobj:llvm-readelf"
    "llvm-symbolizer:llvm-addr2line"
)

# ============================================================================
# Functions
# ============================================================================

clean_install() {
    if [ -d "$DEST" ]; then
        log_info "Removing $DEST..."
        rm -rf "$DEST"
        log_success "Clean complete"
    else
        log_info "Nothing to clean"
    fi
}

install_toolchain() {
    log_section "Installing M65832 Toolchain"

    # Check LLVM is built
    if [ ! -x "$LLVM_BIN/clang-23" ]; then
        log_error "LLVM not built. Run: ./build.sh llvm"
        log_error "Expected: $LLVM_BIN/clang-23"
        exit 1
    fi

    mkdir -p "$DEST"

    # Install LLVM binaries (symlink to build dir to preserve resource dir resolution)
    log_info "Installing LLVM tools..."
    local installed=0
    for bin in "${LLVM_BINARIES[@]}"; do
        if [ -f "$LLVM_BIN/$bin" ]; then
            ln -sf "$LLVM_BIN/$bin" "$DEST/$bin"
            ((installed++))
        else
            log_warn "Not found: $LLVM_BIN/$bin (skipping)"
        fi
    done
    log_success "Installed $installed LLVM binaries (symlinked)"

    # Create convenience symlinks
    log_info "Creating symlinks..."
    for spec in "${LLVM_SYMLINKS[@]}"; do
        local target="${spec%%:*}"
        local link="${spec##*:}"
        if [ -L "$DEST/$target" ] || [ -f "$DEST/$target" ]; then
            ln -sf "$LLVM_BIN/$target" "$DEST/$link"
        fi
    done
    log_success "Symlinks created"

    # Install native tools
    log_info "Installing native tools..."
    if [ -x "$EMU_SRC" ]; then
        cp "$EMU_SRC" "$DEST/m65832emu"
        chmod +x "$DEST/m65832emu"
        log_success "Installed m65832emu"
    else
        log_warn "Emulator not built: $EMU_SRC"
    fi

    if [ -x "$ASM_SRC" ]; then
        cp "$ASM_SRC" "$DEST/m65832as"
        chmod +x "$DEST/m65832as"
        log_success "Installed m65832as"
    else
        log_warn "Assembler not built: $ASM_SRC"
    fi

    # Preserve any user wrapper scripts (e.g. m65832-linux-clang)
    if [ -f "$LLVM_SRC/bin/m65832-linux-clang" ]; then
        cp "$LLVM_SRC/bin/m65832-linux-clang" "$DEST/m65832-linux-clang"
        chmod +x "$DEST/m65832-linux-clang"
        log_info "Copied m65832-linux-clang wrapper"
    fi

    print_summary
}

print_summary() {
    log_section "Toolchain Installed"
    echo "Location: $DEST"
    echo ""
    echo "Binaries:"
    ls -1 "$DEST" | while read f; do
        if [ -L "$DEST/$f" ]; then
            echo "  $f -> $(readlink "$DEST/$f")"
        elif [ -x "$DEST/$f" ]; then
            echo "  $f"
        fi
    done
    echo ""
    echo "Add to PATH:"
    echo "  export PATH=\"$DEST:\$PATH\""
    echo ""
}

# ============================================================================
# Main
# ============================================================================

case "${1:-install}" in
    install)
        install_toolchain
        ;;
    --clean)
        clean_install
        ;;
    -h|--help)
        echo "Usage: $0 [install|--clean]"
        echo ""
        echo "Install M65832 toolchain binaries to $DEST"
        exit 0
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Usage: $0 [install|--clean]"
        exit 1
        ;;
esac
