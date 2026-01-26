# M65832 - A Modern (as of maybe mid 2000's) 6502 Evolution

A 32-bit processor architecture extending the 65816, designed for:
- Running classic 6502/65816 code without emulation
- Full Linux compatibility
- FPGA implementation
- Fun assembly programming

## Overview

The M65832 ("M" for Modern) is a direct successor to the WDC 65C816, extending it to a true 32-bit architecture capable of running a modern OS like linux or BSD, while preserving the elegance and "feel" of the 6502 family.

### Key Features

| Feature | Specification |
|---------|---------------|
| Data Width | 8/16/32-bit (flag-selectable) |
| Virtual Address | 32-bit (4 GB) |
| Physical Address | 65-bit (32 exabytes, via paging) |
| Registers | A, X, Y + 64×32-bit register window |
| Endianness | Little-endian (6502 heritage) |
| Compatibility | Cycle accurate 6502 emulation mode |

### Design Goals

1. **Modern 6052 derived 32 bit isa** - 32 bit 6502 instruction set with base regs + 64 ZP registers
2. **6502/65816 Compatible** - Run 6502/816 code with minimal changes
3. **6502 Coprocessor** - Cycle accurate 6502 mode,  multiple instruction variants, selectable clock rate
4. **Flat 32-bit Address Space** - Simple, predictable memory model
5. **Linux Capable** - MMU, privilege levels, atomics
6. **Compact Instructions** - Keep the 6502's code density
7. **FPGA Friendly** - Implementable on mid-range FPGAs

### Reference Implementations

This project includes third-party reference cores for study and the dedicated
6502 coprocessor. We gratefully acknowledge:

- **[MX65](https://github.com/steveteal/mx65)** by Steve Teal (MIT License) -
  Cycle-accurate 6502 core in VHDL, used for the dedicated classic coprocessor
- **[SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer)** by srg320 (GPL-3.0) -
  65C816 implementation used as architectural reference

See [LICENSE.md](LICENSE.md) for complete licensing details.

## Documentation

### Architecture
- **[Architecture Reference](docs/M65832_Architecture_Reference.md)** - Complete CPU specification
- **[Instruction Set](docs/M65832_Instruction_Set.md)** - Detailed opcode reference
- **[Quick Reference](docs/M65832_Quick_Reference.md)** - Programmer's cheat sheet

### Tools
- **[Assembler Reference](docs/M65832_Assembler_Reference.md)** - Assembler usage, syntax, and directives
- **[Disassembler Reference](docs/M65832_Disassembler_Reference.md)** - Disassembler usage and library API
- **[Emulator](emu/README.md)** - High-performance emulator with debugger, FPU, MMU, and 6502 coprocessor support

### System Programming
- **[System Programming Guide](docs/M65832_System_Programming_Guide.md)** - Supervisor mode, MMU, interrupts, and multitasking
- **[Linux Porting Guide](docs/M65832_Linux_Porting_Guide.md)** - OS implementation notes
- **[Classic Coprocessor](docs/M65832_Classic_Coprocessor.md)** - Two-core architecture, 6502 compatibility, cycle-accurate timing

## STATUS

### Toolchain - Complete and Working

- [x] **Assembler** - Full two-pass assembler with macros, includes, sections, and complete instruction set support
- [x] **Disassembler** - Standalone tool and library API for binary analysis
- [x] **Emulator** - High-performance emulator with FPU, MMU, timer, and 100% VHDL test compatibility (366/366 tests passing)
- [x] **Experimental C Compiler** - LCC-based backend for C compilation (experimental)

### RTL Implementation

- [x] Feature complete for the current RTL milestone
- [x] Integer core (ALU, decode, wide data paths)
- [x] 32-bit architectural extensions (addressing, width controls)
- [x] Floating-point unit integration path
- [x] MMU with page-table walk + TLB
- [x] Cycle-accurate 6502 coprocessor and interleaving
- [x] Privilege model, exceptions, and interrupt entry/exit

### In Progress

- [ ] Expanded regression and corner-case validation
- [ ] Hardware bring-up on target FPGA
- [ ] Performance characterization and tuning
- [ ] C compiler optimization and standard library
- [ ] Linux boot and userland enablement

## Tests

GHDL testbenches:

- Core/MMU suite (fast iteration): `tb/run_core_tests.sh`
- Coprocessor suite (fast iteration): `tb/run_coprocessor_tests.sh`
- 6502 illegal/65C02 cycle-accuracy test: `tb/tb_mx65_illegal.vhd` (included in coprocessor suite)
- Manual core testbench:
  `ghdl -a --std=08 rtl/m65832_pkg.vhd rtl/m65832_alu.vhd rtl/m65832_regfile.vhd rtl/m65832_addrgen.vhd rtl/m65832_decoder.vhd rtl/m65832_mmu.vhd rtl/m65832_core.vhd tb/tb_m65832_core.vhd && ghdl -e --std=08 tb_M65832_Core && ghdl -r --std=08 tb_M65832_Core --stop-time=1ms`
- Manual MMU-only testbench:
  `ghdl -a --std=08 rtl/m65832_pkg.vhd rtl/m65832_alu.vhd rtl/m65832_regfile.vhd rtl/m65832_addrgen.vhd rtl/m65832_decoder.vhd rtl/m65832_mmu.vhd rtl/m65832_core.vhd tb/tb_m65832_mmu.vhd && ghdl -e --std=08 tb_M65832_MMU && ghdl -r --std=08 tb_M65832_MMU --stop-time=1ms`

## Architecture Highlights

### Virtual 6502 Mode

Run unmodified 6502 code anywhere in the 32-bit address space:

```asm
SVBR #$10000000     ; 6502 sees $0000-$FFFF at VA $10000000-$1000FFFF
SEC
XCE                 ; Enter emulation mode
JMP $C000           ; Actually jumps to $1000C000
```

### Register Window

64 general-purpose 32-bit registers accessible via Direct Page:

```asm
RSET                ; Enable register window
LDA $00             ; A = R0
ADC $04             ; A += R1
STA $08             ; R2 = A
```

### Base Registers Keep Code Small

```asm
SB #$90000000       ; Set absolute base
LDA $1234           ; Loads from $90001234 (3-byte instruction!)
```

### Classic Coprocessor: Cycle-Accurate 6502 Emulation

The M65832 includes a **dedicated 6502 compatibility coprocessor** (one at a time) for classic platform emulation.

This coprocessor is separate from the normal 8/16/32-bit process model: 8-bit 6502-compatible processes can multitask like any other task but are not cycle-accurate and run at native clockrate.

In coprocessor mode, cycle-accurate beam tracing is supported, and the 6502 runs at a software-selectable cycle rate via time-sliced scheduling alongside the main core.

Both the compatibility core and the regular M65832 core can also connect to FPGA/external coprocessors or chips that emulate classic machines or provide newer accelerators (e.g., VIC/SID, a SID99 with advanced sampling and wavetable synth, or enhanced 2D sprite/video display chips with richer palettes and animation):

```
┌─────────────────────────────────────────────────────────────────────┐
│                    M65832 SoC Architecture                          │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Fractional Clock Divider                        │   │
│  │   Master: 50 MHz  →  Target: 1.022727 MHz (C64 NTSC)        │   │
│  │   Generates tick every ~49 cycles for exact 6502 timing     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│           ┌──────────────────┼──────────────────┐                  │
│           ▼                  ▼                  │                  │
│     ┌──────────┐       ┌──────────┐             │                  │
│     │ M65832   │       │  6502    │             │                  │
│     │ Main Core│       │Game Core │             │                  │
│     │ (Linux)  │       │(Classic) │             │                  │
│     │  ~90%    │       │   ~2%    │             │                  │
│     └──────────┘       └──────────┘             │                  │
│          │                  │                   │                  │
│          └──────────────────┴───────────────────┘                  │
│                              │                                      │
│                    ┌─────────▼─────────┐                           │
│                    │   Shared Memory   │                           │
│                    │ Shadow Regs, FIFO │                           │
│                    └───────────────────┘                           │
└─────────────────────────────────────────────────────────────────────┘
```

**Why two cores?**

Classic games like those for C64, NES, and Atari rely on *exact* cycle timing:
- **Raster racing**: Code that changes graphics mid-scanline
- **Sound timing**: Music engines that count cycles for tempo
- **Sprite multiplexing**: Repositioning sprites during blanking

Software emulation can't match this while Linux handles interrupts. The solution: **dedicated hardware**.

**How it works:**

1. **M65832 Main Core** (~90% of cycles): Runs Linux, apps, and device drivers
2. **6502 Game Core** (~2% of cycles): Executes classic game code at exact original speed
3. **MMIO handling**: Uses main CPU IRQ handlers for computed reads when needed

The **fractional clock divider** uses Bresenham-style scheduling to generate precise 6502 timing even when the master clock isn't an exact multiple:

```
Master Clock:   50.000000 MHz
Target (C64):    1.022727 MHz
Ratio:          ~48.9 cycles per 6502 tick

The divider alternates 49/48 cycle gaps to maintain
long-term frequency accuracy within 0.001%
```

**Shadow registers** capture classic chip writes with cycle timestamps, letting Linux render the frame accurately while the 6502 runs at real speed. Computed MMIO reads raise an IRQ to the main core instead of running a dedicated servicer core.

See [Classic Coprocessor](docs/M65832_Classic_Coprocessor.md) for complete details.

### Modern Features

- **Atomic operations**: CAS, LL/SC for lock-free programming
- **MMU**: 2-level page tables, 4KB pages
- **Privilege levels**: Supervisor/User separation
- **Linux ABI**: Standard calling convention with R0-R7 for arguments

## Project Structure

```
m65832/
├── README.md
├── docs/
│   ├── M65832_Architecture_Reference.md
│   ├── M65832_Instruction_Set.md
│   ├── M65832_Assembler_Reference.md
│   ├── M65832_Disassembler_Reference.md
│   ├── M65832_Linux_Porting_Guide.md
│   ├── M65832_System_Programming_Guide.md
│   ├── M65832_Classic_Coprocessor.md
│   └── M65832_Quick_Reference.md
├── as/                     # Assembler and Disassembler
│   ├── m65832as.c          # Two-pass assembler
│   ├── m65832dis.c         # Disassembler (standalone + library)
│   ├── Makefile
│   ├── README.md
│   └── test/               # Test suite
├── emu/                    # Emulator
│   ├── m65832emu.c         # CPU emulator core
│   ├── m65832emu.h         # Emulator API
│   ├── main.c              # Standalone emulator with debugger
│   ├── Makefile
│   ├── README.md
│   └── test/               # Test programs
├── cores/                  # Reference VHDL cores
│   ├── 6502-mx65/          # MIT-licensed 6502 (for dedicated core)
│   │   └── mx65.vhd        # ~1000 lines, cycle-accurate
│   └── 65816-mister/       # GPL-3 65816 (reference for M65832)
│       └── rtl/65C816/     # Modular: ALU, AddrGen, MCode, etc.
├── rtl/                    # M65832 VHDL implementation
│   ├── m65832_pkg.vhd
│   ├── m65832_core.vhd
│   ├── m65832_alu.vhd
│   ├── m65832_regfile.vhd
│   ├── m65832_decoder.vhd
│   └── m65832_mmu.vhd
├── tb/                     # GHDL testbenches
│   ├── run_core_tests.sh
│   ├── run_coprocessor_tests.sh
│   └── tb_*.vhd
└── software/               # Example code (planned)
```

## Target FPGA

Primary target: **Xilinx Artix-7 (XC7A35T)**
- ~5,500 LUTs estimated
- 50-100 MHz target clock
- Available on affordable dev boards (Arty A7, etc.)

## Use Cases

### Ultra Nintendo / C-64 Ultra / Apple 2 Ultra

Run classic game code **natively** alongside modern software:
- 6502/65816 code runs without software emulation
- Linux kernel manages everything in 32-bit supervisor mode  
- Context switch between modes is automatic (RTI restores mode)
- Multiple "retro" processes can run simultaneously with Linux apps

```
┌─────────────────────────────────────────────┐
│              M65832 System                  │
├─────────────┬─────────────┬─────────────────┤
│ Pac-Man     │ Super Mario │ Linux Terminal  │
│ (6502 mode) │ (65816 mode)│ (32-bit mode)   │
│ E=1         │ E=0, M=01   │ E=0, M=10       │
└─────────────┴─────────────┴─────────────────┘
        All running simultaneously!
```

### Retro-Modern Development

Write new software with a fun, accessible assembly language:
- Short instructions (mostly 1-3 bytes)
- Predictable timing (for cycle-counted code)
- Modern conveniences (multiply, divide, atomics)

### Educational

Learn CPU architecture with a clean, understandable design:
- No microcode (direct decode)
- Simple pipeline
- Well-documented instruction set

### Reference Cores

| Core | Source | License | Purpose |
|------|--------|---------|---------|
| MX65 | Steve-Teal/mx65 | MIT | Dedicated 6502 for cycle-accurate classic |
| P65C816 | MiSTer-devel/SNES_MiSTer | GPL-3 | Reference for M65832 main core |

## Contributing

This is an open design. Contributions welcome for:
- VHDL implementation
- Toolchain (assembler, linker, debugger)
- Software (bootloader, OS port)
- Documentation improvements

## License

- **Documentation**: CC BY-SA 4.0  
- **Original Code**: MIT (when implemented)
- **Reference Cores**: See individual licenses
  - `cores/6502-mx65/`: MIT
  - `cores/65816-mister/`: GPL-3.0

Note: If M65832 derives from MiSTer's 65816 core, derivative code must be GPL-3.0.
The dedicated 6502 core (MX65) is MIT and can be used freely.

## Acknowledgments

- **Steve Teal** for the [MX65](https://github.com/steveteal/mx65) 6502 core (MIT)
- **srg320** for the [SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer) 65C816 core (GPL-3.0)
- WDC for the 6502 and 65816
- The 6502.org community
- Classic computer preservationists everywhere

---

*"The 6502 was elegant. Let's keep that elegance and make it powerful."*
