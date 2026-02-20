#!/bin/bash
#
# run-kernel.sh - Boot Linux kernel in M65832 emulator
#
# Usage:
#   run-kernel.sh                      Boot kernel (run until halt/crash)
#   run-kernel.sh --debug              Boot with debug server (use 'edb' to connect)
#   run-kernel.sh --trace              Boot with instruction tracing
#   run-kernel.sh --cycles N           Run for N cycles then stop
#   run-kernel.sh --kernel FILE        Use alternate kernel ELF
#   run-kernel.sh --ram SIZE           Set RAM size (e.g., 256M, 512M)
#
# The script uses the boot ROM flow:
#   1. Boot ROM (bootrom.bin) initializes CPU and loads kernel via DMA
#   2. Kernel flat binary (vmlinux.bin) is loaded at physical 0x00100000
#   3. Symbol table + DWARF line info loaded from vmlinux ELF
#
# Source-level debugging (--debug):
#   1. Start: run-kernel.sh --debug
#   2. Connect: edb (in another terminal)
#   3. Commands: list, dis, bt, sym, b <symbol>, c, s, n, etc.
#

set -e

# Load common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Defaults
KERNEL_ELF="${LINUX_SRC}/vmlinux"
KERNEL_BIN="${LINUX_SRC}/vmlinux.bin"
BOOTROM="${M65832_DIR}/boot/bootrom.bin"
RAM_SIZE="256M"
CYCLES=""
DEBUG=0
TRACE=0
VERBOSE=0
EXTRA_ARGS=""

usage() {
    echo "run-kernel.sh - Boot Linux kernel in M65832 emulator"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --debug              Start debug server (connect with 'edb')"
    echo "  --trace              Enable instruction tracing"
    echo "  --verbose, -v        Verbose output"
    echo "  --kernel FILE        Kernel ELF (default: ../linux-m65832/vmlinux)"
    echo "  --ram SIZE           RAM size (default: 256M)"
    echo "  --cycles N           Stop after N cycles"
    echo "  --raw                Put terminal in raw mode (for UART I/O)"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Debug workflow:"
    echo "  Terminal 1:  $0 --debug"
    echo "  Terminal 2:  edb"
    echo "  edb> list            Show source at current PC"
    echo "  edb> bt              Backtrace with symbols"
    echo "  edb> b start_kernel  Break at function"
    echo "  edb> c               Continue"
    echo "  edb> dis             Disassemble with source annotations"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)     DEBUG=1; shift ;;
        --trace)     TRACE=1; shift ;;
        --trace-ring) EXTRA_ARGS="$EXTRA_ARGS --trace-ring $2"; shift 2 ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --kernel)    KERNEL_ELF="$2"; shift 2 ;;
        --ram)       RAM_SIZE="$2"; shift 2 ;;
        --cycles)    CYCLES="$2"; shift 2 ;;
        --raw)       EXTRA_ARGS="$EXTRA_ARGS --raw"; shift ;;
        -h|--help)   usage ;;
        *)           echo "Unknown option: $1"; usage ;;
    esac
done

# Validate files
if [ ! -f "$KERNEL_ELF" ]; then
    log_error "Kernel ELF not found: $KERNEL_ELF"
    echo "  Build with: ./scripts/build-m65832.sh build"
    exit 1
fi

# Generate vmlinux.bin from ELF if needed
KERNEL_BIN="${KERNEL_ELF%.vmlinux}.vmlinux.bin"
KERNEL_BIN="${KERNEL_ELF}.bin"
# Normalize: if kernel is "vmlinux", binary is "vmlinux.bin"
if [[ "$KERNEL_ELF" == */vmlinux ]]; then
    KERNEL_BIN="$(dirname "$KERNEL_ELF")/vmlinux.bin"
fi

if [ ! -f "$KERNEL_BIN" ] || [ "$KERNEL_ELF" -nt "$KERNEL_BIN" ]; then
    log_info "Generating flat binary: $KERNEL_BIN"
    "$LLVM_OBJCOPY" -O binary "$KERNEL_ELF" "$KERNEL_BIN"
fi

if [ ! -f "$BOOTROM" ]; then
    log_error "Boot ROM not found: $BOOTROM"
    echo "  Build with: m65832as boot/bootrom.s -o boot/bootrom.bin"
    exit 1
fi

# Build emulator command
EMU_CMD="$EMU --system"
EMU_CMD="$EMU_CMD --bootrom $BOOTROM"
EMU_CMD="$EMU_CMD --kernel $KERNEL_BIN"
EMU_CMD="$EMU_CMD --symbols $KERNEL_ELF"
EMU_CMD="$EMU_CMD --ram $RAM_SIZE"

if [ $DEBUG -eq 1 ]; then
    EMU_CMD="$EMU_CMD --debug"
fi

if [ $TRACE -eq 1 ]; then
    EMU_CMD="$EMU_CMD --trace"
fi

if [ $VERBOSE -eq 1 ]; then
    EMU_CMD="$EMU_CMD -v"
fi

if [ -n "$CYCLES" ]; then
    EMU_CMD="$EMU_CMD --cycles $CYCLES"
fi

EMU_CMD="$EMU_CMD $EXTRA_ARGS"

# Print summary
log_info "Booting M65832 Linux kernel"
echo "  Kernel ELF:  $KERNEL_ELF"
echo "  Kernel BIN:  $KERNEL_BIN ($(( $(stat -f %z "$KERNEL_BIN" 2>/dev/null || stat -c %s "$KERNEL_BIN" 2>/dev/null) / 1024 )) KB)"
echo "  Boot ROM:    $BOOTROM"
echo "  RAM:         $RAM_SIZE"
if [ $DEBUG -eq 1 ]; then
    echo "  Debug:       enabled (connect with 'edb')"
fi
echo ""

exec $EMU_CMD
