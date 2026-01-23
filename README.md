# M65832 - Modern 6502 Evolution

A 32-bit processor architecture extending the 65816, designed for:
- Running classic 6502/65816 code without emulation
- Full Linux compatibility
- FPGA implementation
- Fun assembly programming

## Overview

The M65832 ("M" for Modern) is a spiritual successor to the WDC 65C816, extending it to a true 32-bit architecture while preserving the elegance and "feel" of the 6502 family.

### Key Features

| Feature | Specification |
|---------|---------------|
| Data Width | 8/16/32-bit (flag-selectable) |
| Virtual Address | 32-bit (4 GB) |
| Physical Address | 65-bit (32 exabytes, via paging) |
| Registers | A, X, Y + 64×32-bit register window |
| Endianness | Little-endian (6502 heritage) |
| Compatibility | 6502 emulation mode at any address |

### Design Goals

1. **6502/65816 Compatible** - Run classic code with minimal changes
2. **Flat 32-bit Address Space** - Simple, predictable memory model
3. **Linux Capable** - MMU, privilege levels, atomics
4. **Compact Instructions** - Keep the 6502's code density
5. **FPGA Friendly** - Implementable on mid-range FPGAs

## Documentation

- **[Architecture Reference](docs/M65832_Architecture_Reference.md)** - Complete CPU specification
- **[Instruction Set](docs/M65832_Instruction_Set.md)** - Detailed opcode reference
- **[Linux Porting Guide](docs/M65832_Linux_Porting_Guide.md)** - OS implementation notes
- **[Mixed-Mode Multitasking](docs/M65832_Mixed_Mode_Multitasking.md)** - Running 8/16/32-bit processes together
- **[Timing Compatibility](docs/M65832_Timing_Compatibility.md)** - Cycle-accurate 6502, clock speed control
- **[Classic Coprocessor](docs/M65832_Classic_Coprocessor.md)** - Three-core architecture for retro gaming
- **[Quick Reference](docs/M65832_Quick_Reference.md)** - Programmer's cheat sheet

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
│   ├── M65832_Linux_Porting_Guide.md
│   ├── M65832_Classic_Coprocessor.md
│   └── M65832_Quick_Reference.md
├── cores/                  # Reference VHDL cores
│   ├── 6502-mx65/          # MIT-licensed 6502 (for dedicated core)
│   │   └── mx65.vhd        # ~1000 lines, cycle-accurate
│   └── 65816-mister/       # GPL-3 65816 (reference for M65832)
│       └── rtl/65C816/     # Modular: ALU, AddrGen, MCode, etc.
├── rtl/                    # M65832 VHDL implementation (planned)
│   ├── m65832_pkg.vhd
│   ├── m65832_core.vhd
│   ├── m65832_alu.vhd
│   ├── m65832_regfile.vhd
│   ├── m65832_decoder.vhd
│   └── m65832_mmu.vhd
├── sim/                    # Simulation testbenches (planned)
├── asm/                    # Assembler (planned)
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

## Status

**Current Phase**: RTL Development

- [x] Architecture specification
- [x] Instruction set definition
- [x] Linux requirements analysis
- [x] Classic coprocessor design (6502 + servicer interleaving)
- [x] Reference cores acquired (MX65 6502, MiSTer 65816)
- [x] VHDL implementation (4,300+ lines)
  - [x] Package definitions (`m65832_pkg.vhd`)
  - [x] 32-bit ALU (`m65832_alu.vhd`)
  - [x] Address generator (`m65832_addrgen.vhd`)
  - [x] 64x32 register file (`m65832_regfile.vhd`)
  - [x] Instruction decoder (`m65832_decoder.vhd`)
  - [x] Top-level core (`m65832_core.vhd`)
  - [x] MMU with 16-entry TLB (`m65832_mmu.vhd`)
  - [x] Classic interleaver (`m65832_interleave.vhd`)
  - [x] 6502 context registers (`m65832_6502_context.vhd`)
  - [x] Servicer context (`m65832_servicer_context.vhd`)
  - [x] Shadow I/O + FIFO (`m65832_shadow_io.vhd`)
- [ ] Assembler
- [ ] Simulator/Testbench
- [ ] Synthesis for Artix-7

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

- WDC for the 6502 and 65816
- The 6502.org community
- Classic computer preservationists everywhere

---

*"The 6502 was elegant. Let's keep that elegance and make it powerful."*
