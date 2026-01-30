# M65832 Build Guide

This document describes how to build the complete M65832 toolchain, including the compiler, libraries, and emulator.

## Overview

The M65832 build system supports two primary targets:

1. **Baremetal** - For running directly on FPGA hardware or the emulator without an OS
2. **Linux** - For running as Linux userspace applications (future)

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| CMake | 3.20+ | LLVM build system |
| Ninja | 1.10+ | Fast parallel builds |
| Python | 3.8+ | Build scripts |
| Meson | 1.0+ | Picolibc build system |
| Git | 2.0+ | Source control |
| GCC/Clang | 10+ | Host compiler |

### Installing Prerequisites

**macOS:**
```bash
brew install cmake ninja python meson
```

**Ubuntu/Debian:**
```bash
sudo apt install cmake ninja-build python3 python3-pip
pip3 install meson
```

**Fedora:**
```bash
sudo dnf install cmake ninja-build python3 meson
```

## Quick Start

```bash
# Clone the main repository
git clone https://github.com/benjcooley/m65832.git
cd m65832

# Build everything for baremetal
./build.sh baremetal

# Run the test suite
./build.sh test
```

## Directory Structure

After a successful build, the directory structure will be:

```
projects/
├── m65832/                      # Main repo (you are here)
│   ├── build.sh                 # Bootstrap script
│   ├── scripts/                 # Build scripts
│   ├── emu/                     # Emulator source
│   ├── as/                      # Assembler source
│   ├── rtl/                     # FPGA RTL
│   └── docs/                    # Documentation
├── llvm-m65832/                 # LLVM fork (cloned automatically)
│   ├── build/                   # Full LLVM build
│   └── build-fast/              # Fast incremental build
├── picolibc-m65832/             # Picolibc fork (cloned automatically)
├── m65832-sysroot/              # Baremetal sysroot (build output)
│   ├── include/                 # Header files
│   └── lib/                     # Libraries and linker scripts
└── m65832-sysroot-linux/        # Linux sysroot (future)
```

## Build Targets

### Baremetal Target

The baremetal target builds a freestanding C library that communicates directly with hardware via memory-mapped I/O (MMIO).

```bash
./build.sh baremetal
```

This will:
1. Clone `llvm-m65832` and `picolibc-m65832` if not present (with `--depth=1`)
2. Build LLVM/Clang with the M65832 backend
3. Build picolibc with baremetal syscalls
4. Install to `../m65832-sysroot/`

### Linux Target (Future)

The Linux target builds a C library that uses Linux system calls via the `TRAP #0` instruction.

```bash
./build.sh linux
```

### All Targets

Build everything:

```bash
./build.sh all
```

### Running Tests

```bash
./build.sh test
```

This runs:
- Emulator unit tests
- Assembler tests
- C compiler tests (151 tests)
- Picolibc integration tests

## MMIO Address Map (Baremetal)

The baremetal library uses these hardware addresses, which are identical between the emulator and FPGA:

| Device | Base Address | Size | Description |
|--------|--------------|------|-------------|
| System Registers | `0x00FFF000` | 256B | MMU control, Timer |
| UART | `0x00FFF100` | 16B | Console I/O |
| Block Device | `0x00FFF120` | 32B | Disk I/O |
| Exit Code | `0xFFFFFFFC` | 4B | Program exit status |

### UART Registers

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| +0x00 | STATUS | R | TX_READY, RX_AVAIL flags |
| +0x04 | TX_DATA | W | Transmit data |
| +0x08 | RX_DATA | R | Receive data |
| +0x0C | CTRL | R/W | IRQ enable, loopback |

### Block Device Registers

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| +0x00 | STATUS | R | READY, BUSY, ERROR flags |
| +0x04 | COMMAND | W | READ, WRITE, FLUSH |
| +0x08 | SECTOR_LO | R/W | Sector number (low 32 bits) |
| +0x0C | SECTOR_HI | R/W | Sector number (high 32 bits) |
| +0x10 | DMA_ADDR | R/W | DMA transfer address |
| +0x14 | COUNT | R/W | Sector count |

## Linux System Calls (Future)

Linux applications use the `TRAP #0` instruction for system calls:

```asm
; System call convention
; R0 = syscall number
; R1-R6 = arguments
; Return: R0 = result (or -errno on error)

    LDA #SYS_WRITE      ; syscall number
    STA R0
    LDA #fd             ; file descriptor
    STA R1
    LDA #buffer         ; buffer address
    STA R2
    LDA #count          ; byte count
    STA R3
    TRAP #0             ; invoke kernel
    ; Result in R0
```

## Building Individual Components

### LLVM Only

```bash
./scripts/build-llvm.sh
```

### Picolibc Only (requires LLVM)

```bash
./scripts/build-libc-baremetal.sh
```

### Emulator Only

```bash
cd emu
make
```

### Assembler Only

```bash
cd as
make
```

## Using the Toolchain

After building, you can compile M65832 programs:

```bash
# Set up paths
export M65832_SYSROOT=$HOME/projects/m65832-sysroot
export PATH=$HOME/projects/llvm-m65832/build-fast/bin:$PATH

# Compile
clang -target m65832-elf -ffreestanding \
    -I$M65832_SYSROOT/include \
    -c myprogram.c -o myprogram.o

# Link
ld.lld -T $M65832_SYSROOT/lib/m65832.ld \
    $M65832_SYSROOT/lib/crt0.o myprogram.o \
    -L$M65832_SYSROOT/lib -lc -lsys \
    -o myprogram.elf

# Run on emulator
m65832emu myprogram.elf
```

## Platform-Specific Builds

### DE2-115 FPGA (de25)

```bash
./build.sh baremetal de25
```

This configures:
- 50 MHz system clock
- 115200 baud UART
- SDRAM memory

### Kria KV260 (kv260)

```bash
./build.sh baremetal kv260
```

This configures:
- 100 MHz system clock
- 115200 baud UART
- DDR4 memory

## Troubleshooting

### LLVM Build Fails

**Symptom:** CMake or ninja errors during LLVM build

**Solutions:**
1. Ensure you have enough RAM (16GB+ recommended)
2. Try reducing parallelism: `ninja -j4` instead of default
3. Check CMake version is 3.20+

### Picolibc Build Fails

**Symptom:** Meson configuration errors

**Solutions:**
1. Ensure meson is installed: `pip install meson`
2. Check that LLVM build completed successfully
3. Delete build directory and retry: `rm -rf ../picolibc-build-m65832`

### Compiler Crashes

**Known issues:**
- Debug info (`-g`) crashes in `MCAssembler::layout()` - use `-g0`
- Optimization `-O2+` may crash in `BranchFolder` - use `-O1`

### Emulator Segfaults

**Symptom:** Exit code 139 when running programs

**Solutions:**
1. Increase cycle limit: `-c 10000000`
2. Check for infinite loops in your code
3. Run with verbose mode: `-v`

## Advanced Topics

### Cross-Compilation Details

The M65832 target triple is `m65832-elf` for baremetal or `m65832-linux` for Linux.

Clang flags for M65832:
```
-target m65832-elf     # Target triple
-ffreestanding         # No hosted environment
-O1                    # Optimization level (avoid -O2+ for now)
-fuse-ld=lld          # Use LLD linker
```

### Linker Script

The default linker script (`m65832.ld`) provides:
- `.text` at `0x00020000` (code)
- `.data` at `0x00080000` (initialized data)
- `.bss` after `.data` (uninitialized data)
- Stack at `0x000FFFFF` (grows down)
- Heap between BSS and stack

### Adding New Syscalls (Baremetal)

Edit `picolibc-m65832/libc/machine/m65832/syscalls.c` to add new system calls. The file contains POSIX-compatible stubs that can be extended.

## Version Information

- LLVM: 20.x (M65832 fork)
- Picolibc: 1.8.x (M65832 fork)
- Emulator: 1.0.0

## See Also

- [M65832_Architecture_Reference.md](M65832_Architecture_Reference.md) - CPU architecture
- [M65832_Instruction_Set.md](M65832_Instruction_Set.md) - Instruction encoding
- [M65832_C_ABI.md](M65832_C_ABI.md) - C calling convention
- [M65832_Linux_Porting_Guide.md](M65832_Linux_Porting_Guide.md) - Linux kernel porting
