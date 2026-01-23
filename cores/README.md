# Reference Cores

This directory contains reference CPU cores used as a starting point for M65832 development.

## 6502-mx65

- **Source**: https://github.com/Steve-Teal/mx65
- **License**: MIT
- **Purpose**: Cycle-accurate 6502 core for the Classic Coprocessor's dedicated 6502
- **Key File**: `mx65.vhd` - Single-file 6502 implementation

## 65816-mister

- **Source**: https://github.com/MiSTer-devel/SNES_MiSTer
- **License**: GPL-3.0
- **Purpose**: Reference for M65832 main core architecture
- **Key Files**:
  - `rtl/65C816/P65C816.vhd` - Main 65816 CPU
  - `rtl/65C816/ALU.vhd` - Arithmetic Logic Unit
  - `rtl/65C816/AddrGen.vhd` - Address Generator
  - `rtl/65C816/MCode.vhd` - Microcode

## License Notes

- **MX65 (MIT)**: Can be used freely in M65832 with attribution
- **MiSTer 65816 (GPL-3.0)**: Any derivative code must also be GPL-3.0

The M65832 RTL in `../rtl/` derives from both cores and is licensed GPL-3.0 due to the MiSTer dependency.
