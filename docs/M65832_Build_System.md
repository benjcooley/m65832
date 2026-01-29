# M65832 Build System Reference

This document describes the M65832 build system, including configuration, building, testing, and the overall directory structure.

## Overview

The M65832 build system consists of three main scripts:

| Script | Purpose |
|--------|---------|
| `configure.sh` | Detect host platform, validate prerequisites, generate configuration |
| `build.sh` | Build toolchain components (LLVM, libc, emulator, assembler) |
| `test.sh` | Run test suites to validate the build |

The build system supports two primary targets:

- **Baremetal** - For running directly on FPGA hardware or the emulator without an OS
- **Linux** - For running as Linux userspace applications

## Quick Start

```bash
# Clone the main repository
git clone https://github.com/benjcooley/m65832.git
cd m65832

# Configure (auto-detects platform, validates prerequisites)
./configure.sh

# Build just the tools (emulator + assembler) - fast
./build.sh tools

# Run quick tests
./test.sh --quick

# Build full baremetal toolchain (includes LLVM - slow)
./build.sh baremetal

# Run all tests
./test.sh
```

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Install (macOS) | Install (Ubuntu) |
|------|---------|---------|-----------------|------------------|
| CMake | 3.20+ | LLVM build system | `brew install cmake` | `apt install cmake` |
| Ninja | 1.10+ | Fast parallel builds | `brew install ninja` | `apt install ninja-build` |
| Python | 3.8+ | Build scripts | `brew install python` | `apt install python3` |
| Meson | 1.0+ | Picolibc build system | `pip3 install meson` | `pip3 install meson` |
| Git | 2.0+ | Source control | `brew install git` | `apt install git` |
| GCC/Clang | 10+ | Host compiler | Xcode CLT | `apt install build-essential` |

### Optional Tools

| Tool | Purpose | Install |
|------|---------|---------|
| GHDL | RTL/VHDL tests | `brew install ghdl` / `apt install ghdl` |

### Checking Prerequisites

Run `./configure.sh` to automatically check for all prerequisites:

```bash
./configure.sh

# Output:
# [INFO] Checking prerequisites...
# [INFO]   cmake: cmake version 3.28.1
# [INFO]   ninja: 1.11.1
# [INFO]   python3: Python 3.12.0
# [INFO]   meson: 1.3.0
# [INFO]   git: git version 2.43.0
# [INFO]   make: GNU Make 3.81
# [INFO]   ghdl: GHDL 4.0.0 (optional)
# [INFO]   host cc: clang 15.0.0
# [OK] All prerequisites found
```

## Configuration (configure.sh)

The configure script sets up the build environment and generates `.m65832_config`.

### Basic Usage

```bash
# Auto-configure for baremetal target
./configure.sh

# Configure for Linux userspace
./configure.sh --target=linux

# Configure for specific FPGA platform
./configure.sh --target=baremetal --platform=de25

# Debug build with assertions
./configure.sh --debug
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--target=TARGET` | Build target: `baremetal`, `linux`, `all` | `baremetal` |
| `--platform=PLATFORM` | Hardware platform: `de25`, `kv260` | (none) |
| `--jobs=N` | Parallel build jobs | CPU count |
| `--debug` | Enable debug build with assertions | off |
| `--assertions` | Enable LLVM assertions only | off |
| `--skip-clone` | Assume repositories exist | off |
| `--no-shallow` | Use full git clone | off |
| `--verbose` | Enable verbose output | off |

### Configuration File

The configuration is stored in `.m65832_config`:

```bash
# Generated variables include:
HOST_OS="macos"
HOST_ARCH="aarch64"
TARGET="baremetal"
PLATFORM=""
JOBS="10"
# ... paths to all tools and directories
```

## Building (build.sh)

The build script clones dependencies and builds the toolchain.

### Build Targets

```bash
# Primary targets (build complete toolchains)
./build.sh baremetal          # Baremetal toolchain (picolibc)
./build.sh baremetal de25     # Baremetal for DE2-115 FPGA
./build.sh linux              # Linux userspace toolchain (musl)
./build.sh all                # Build everything

# Individual targets (build specific components)
./build.sh tools              # Emulator + assembler only (fast)
./build.sh llvm               # LLVM/Clang only
./build.sh clone              # Clone all dependencies only

# Utilities
./build.sh test               # Run test suites
./build.sh clean              # Clean all build directories
./build.sh status             # Show build status
./build.sh help               # Show help message
```

### What Gets Built

#### `./build.sh tools` (Fast - ~2 minutes)
1. Emulator (`emu/m65832emu`)
2. Assembler (`as/m65832as`)

#### `./build.sh baremetal` (Slow - ~30-60 minutes first time)
1. Clone `llvm-m65832` and `picolibc-m65832`
2. Build LLVM with M65832 backend (full build for LLD)
3. Build LLVM fast (clang only, incremental)
4. Build picolibc with MMIO syscalls
5. Build emulator and assembler
6. Install to `../m65832-sysroot/`

#### `./build.sh linux`
1. Clone `llvm-m65832`, `musl-m65832`, and `linux-m65832`
2. Build LLVM
3. Build musl libc with Linux syscalls
4. Install to `../m65832-sysroot-linux/`

### Build Status

Check what's built with:

```bash
./build.sh status

# Output:
# Dependencies:
#   llvm-m65832:     found
#   picolibc-m65832: found
#   musl-m65832:     not cloned
#   linux-m65832:    not cloned
#
# Tools:
#   Clang:     /Users/.../llvm-m65832/build-fast/bin/clang
#   LLD:       /Users/.../llvm-m65832/build/bin/ld.lld
#   Emulator:  /Users/.../m65832/emu/m65832emu
#   Assembler: /Users/.../m65832/as/m65832as
#
# Sysroots:
#   Baremetal: /Users/.../m65832-sysroot
#   Linux:     not built
```

## Testing (test.sh)

The test script runs various validation suites.

### Test Suites

```bash
# Run all tests
./test.sh

# Run specific test suites
./test.sh --quick       # Quick smoke tests (~5 seconds)
./test.sh --emulator    # Emulator instruction tests (~30 seconds)
./test.sh --assembler   # Assembler syntax tests (~10 seconds)
./test.sh --compiler    # C compiler tests (~5 minutes)
./test.sh --picolibc    # Picolibc integration tests (~2 minutes)
./test.sh --rtl         # VHDL simulation tests (~10 minutes)
./test.sh --inline-asm  # Inline assembly tests
```

### Short Options

```bash
./test.sh -q    # Quick (smoke tests)
./test.sh -e    # Emulator
./test.sh -s    # Assembler
./test.sh -c    # Compiler
./test.sh -p    # Picolibc
./test.sh -r    # RTL
./test.sh -v    # Verbose
```

### Test Output

```bash
./test.sh --quick

# ========================================
# Quick Smoke Tests
# ========================================
#   Assembler... OK
#   Emulator... OK
#   Integration... OK
#   Clang... OK
#
# [INFO] Smoke tests: 4 passed, 0 failed
#
# ========================================
# Test Summary
# ========================================
#   Passed:  1
#   Failed:  0
#   Skipped: 0
#
# [PASS] All tests passed!
```

## Directory Structure

After a successful build, the directory structure will be:

```
projects/
├── m65832/                      # Main repository
│   ├── configure.sh             # Configuration script
│   ├── build.sh                 # Build script
│   ├── test.sh                  # Test runner
│   ├── .m65832_config           # Generated configuration
│   ├── scripts/                 # Build helper scripts
│   │   ├── common.sh            # Shared variables/functions
│   │   ├── clone-deps.sh        # Clone dependencies
│   │   ├── build-llvm.sh        # Build LLVM
│   │   ├── build-libc-baremetal.sh  # Build picolibc
│   │   ├── build-libc-linux.sh  # Build musl
│   │   └── run-tests.sh         # Test runner
│   ├── emu/                     # Emulator source
│   │   ├── m65832emu            # Built emulator
│   │   ├── c_tests/             # C compiler tests
│   │   └── test/                # Assembly tests
│   ├── as/                      # Assembler source
│   │   └── m65832as             # Built assembler
│   ├── rtl/                     # FPGA RTL (VHDL)
│   ├── tb/                      # RTL testbenches
│   ├── docs/                    # Documentation
│   ├── test/                    # Assembly test files
│   └── syn/                     # Synthesis projects
│
├── llvm-m65832/                 # LLVM fork (cloned automatically)
│   ├── build/                   # Full LLVM build (has LLD)
│   ├── build-fast/              # Fast incremental build (clang only)
│   └── m65832-stdlib/           # M65832 support files
│
├── picolibc-m65832/             # Picolibc fork (cloned automatically)
├── musl-m65832/                 # musl fork (cloned for Linux target)
├── linux-m65832/                # Linux kernel fork (cloned for Linux target)
│
├── m65832-sysroot/              # Baremetal sysroot (build output)
│   ├── include/                 # Header files
│   └── lib/                     # Libraries and linker scripts
│       ├── libc.a               # C library
│       ├── libsys.a             # System calls
│       ├── crt0.o               # C runtime startup
│       └── m65832.ld            # Linker script
│
├── m65832-sysroot-linux/        # Linux sysroot (build output)
├── picolibc-build-m65832/       # Picolibc build directory
└── musl-build-m65832/           # musl build directory
```

## Sibling Repositories

The build system automatically clones these repositories as siblings to the main `m65832` directory:

| Repository | Purpose | Branch |
|------------|---------|--------|
| `llvm-m65832` | LLVM/Clang with M65832 backend | `main` |
| `picolibc-m65832` | Picolibc C library for baremetal | `main` |
| `musl-m65832` | musl libc for Linux userspace | `main` |
| `linux-m65832` | Linux kernel with M65832 support | `m65832` |

### Manual Cloning

If you prefer to clone manually:

```bash
cd ~/projects  # or your preferred directory
git clone --depth=1 https://github.com/benjcooley/m65832.git
git clone --depth=1 https://github.com/benjcooley/llvm-m65832.git
git clone --depth=1 https://github.com/benjcooley/picolibc-m65832.git
git clone --depth=1 https://github.com/benjcooley/musl-m65832.git
git clone --depth=1 -b m65832 https://github.com/benjcooley/linux-m65832.git
```

Or use the clone script:

```bash
cd m65832
./build.sh clone
```

## Using the Built Toolchain

After building, you can compile M65832 programs:

### Baremetal Programs

```bash
# Set up paths
export M65832_SYSROOT=$HOME/projects/m65832-sysroot
export PATH=$HOME/projects/llvm-m65832/build-fast/bin:$PATH

# Compile
clang -target m65832-elf -ffreestanding \
    -I$M65832_SYSROOT/include \
    -c hello.c -o hello.o

# Link
ld.lld -T $M65832_SYSROOT/lib/m65832.ld \
    $M65832_SYSROOT/lib/crt0.o hello.o \
    -L$M65832_SYSROOT/lib -lc -lsys \
    -o hello.elf

# Run on emulator
m65832emu hello.elf
```

### Assembly Programs

```bash
# Assemble
m65832as myprogram.asm -o myprogram.bin

# Run on emulator
m65832emu -s myprogram.bin
```

## Troubleshooting

### LLVM Build Fails

**Symptom:** CMake or ninja errors during LLVM build

**Solutions:**
1. Ensure you have enough RAM (16GB+ recommended)
2. Try reducing parallelism: `./configure.sh --jobs=4`
3. Check CMake version is 3.20+
4. Run `./build.sh clean` and rebuild

### Picolibc Build Fails

**Symptom:** Meson configuration errors

**Solutions:**
1. Ensure meson is installed: `pip3 install meson`
2. Check that LLVM build completed successfully
3. Delete build directory: `rm -rf ../picolibc-build-m65832`
4. Rebuild: `./build.sh baremetal`

### Compiler Crashes

**Known issues:**
- Debug info (`-g`) may crash in `MCAssembler::layout()` - use `-g0`
- Optimization `-O2+` may crash in `BranchFolder` - use `-O1`

### Tests Fail

1. Run `./build.sh status` to check what's built
2. Ensure emulator and assembler are built: `./build.sh tools`
3. Run quick tests first: `./test.sh --quick`
4. Check verbose output: `./test.sh --verbose`

### Clone Fails

**Symptom:** Git clone errors

**Solutions:**
1. Check network connectivity
2. Use full clone: `./configure.sh --no-shallow`
3. Clone manually (see "Manual Cloning" above)

## Advanced Configuration

### Environment Variables

You can override configuration with environment variables:

```bash
export JOBS=4              # Limit parallel jobs
export VERBOSE=ON          # Enable verbose output
./build.sh baremetal
```

### Custom Build Flags

Edit `scripts/common.sh` to customize:
- MMIO addresses
- Compiler flags
- Library options

### Platform-Specific Configuration

For FPGA targets, create a configuration in `platforms/<name>/config.sh`:

```bash
# platforms/de25/config.sh
FPGA_CLOCK_MHZ=50
UART_BAUD=115200
MEMORY_TYPE="SDRAM"
```

## CI/CD Integration

For automated builds:

```bash
#!/bin/bash
set -e

# Configure
./configure.sh --target=baremetal

# Build
./build.sh tools
./build.sh baremetal

# Test
./test.sh --quick
./test.sh --compiler

# Report
echo "Build successful"
```

## See Also

- [M65832_Build_Guide.md](M65832_Build_Guide.md) - Getting started guide
- [M65832_Architecture_Reference.md](M65832_Architecture_Reference.md) - CPU architecture
- [M65832_Instruction_Set.md](M65832_Instruction_Set.md) - Instruction encoding
- [M65832_C_ABI.md](M65832_C_ABI.md) - C calling convention
- [M65832_Linux_Porting_Guide.md](M65832_Linux_Porting_Guide.md) - Linux kernel porting
