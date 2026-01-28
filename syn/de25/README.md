# M65832 DE25-Nano Synthesis

This directory contains the Quartus project files for synthesizing the M65832 SoC
for the DE25-Nano development board.

## Target Board

- **Board**: Terasic DE25-Nano
- **FPGA**: Intel Agilex 5 E-Series (`A5EB013BB23BE4SCS`, 138K LEs)
- **Memory**: 128MB SDRAM (16-bit), 1GB LPDDR4 (32-bit shared with HPS)
- **UART**: 2-pin via USB Type-C
- **User I/O**: 8 LEDs, 2 buttons, 4 switches

## Current Status

**Phase 0: Initial Bring-Up**

- [x] Top-level SoC wrapper
- [x] UART peripheral (matching emulator interface)
- [x] Boot ROM (placeholder code)
- [x] BRAM for initial testing (16KB)
- [ ] Pin assignments (need from user manual)
- [ ] SDRAM controller
- [ ] PLL for clock generation
- [ ] Full boot ROM with monitor

## Building

### Prerequisites

1. **Intel Quartus Prime Pro Edition 24.1+**
   - Download from: https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime/resource.html
   - Requires Windows or Linux (no native macOS support)
   - ~30GB download

2. **Free Agilex 5 E-Series License**
   - License is FREE (no cost)
   - Auto-acquired on first launch, or manually from: https://licensing.intel.com/psg/s/
   - Valid for 1 year (renewable)

3. **USB-Blaster III drivers** for programming

### First-Time Setup

1. Download and install Quartus Prime Pro 24.1 or later
2. Launch Quartus - it will prompt to acquire the free Agilex 5 license
3. Accept the license terms
4. You're ready to build!

### Option 1: Quartus GUI

1. Open `m65832_de25.qpf` in Quartus Prime Pro
2. **IMPORTANT**: Update pin assignments in `m65832_de25.qsf` from the DE25-Nano user manual
3. Run Analysis & Synthesis
4. Run Fitter
5. Run Timing Analysis
6. Generate programming file (`.sof`)

### Option 2: Command Line

```bash
# From this directory on a Linux/Windows machine with Quartus installed

# Run full compilation
quartus_sh --flow compile m65832_de25

# Or step by step:
quartus_syn m65832_de25           # Analysis & Synthesis
quartus_fit m65832_de25           # Fitter
quartus_sta m65832_de25           # Timing Analysis
quartus_asm m65832_de25           # Generate programming file
```

### Remote Build (from Mac)

Since Quartus doesn't run on macOS, options include:

1. **Linux VM**: Run Quartus in a VirtualBox/UTM/Parallels Linux VM
2. **Remote Linux box**: SSH to a machine with Quartus, rsync files, build there
3. **Cloud**: Use a cloud Linux instance with Quartus installed

Example remote workflow:
```bash
# On Mac: sync project to Linux box
rsync -avz --exclude 'output_files' . user@linux-box:~/m65832-syn/

# On Linux: build
ssh user@linux-box "cd ~/m65832-syn && quartus_sh --flow compile m65832_de25"

# On Mac: get output files
rsync -avz user@linux-box:~/m65832-syn/output_files/ ./output_files/
```

## Programming the FPGA

### Using Quartus Programmer

1. Connect DE25-Nano via USB
2. Open Quartus Programmer
3. Add `output_files/m65832_de25.sof`
4. Click "Start"

### Using OpenFPGALoader (Linux/Mac)

```bash
# Install openFPGALoader
brew install openfpgaloader  # macOS
# or
apt install openfpgaloader   # Linux

# Program (may need to adjust cable type for your board)
openFPGALoader -c usb-blaster output_files/m65832_de25.sof
```

## Memory Map

| Address Range           | Description              |
|------------------------|--------------------------|
| `0x00000000-0x00003FFF` | RAM (16KB BRAM test)     |
| `0xFFFF0000-0xFFFF0FFF` | Boot ROM (4KB)           |
| `0xFFFFF000-0xFFFFF0FF` | System registers         |
| `0xFFFFF100-0xFFFFF10F` | UART                     |

## UART Interface

The UART matches the emulator's register interface:

| Offset | Register   | Access | Description              |
|--------|-----------|--------|--------------------------|
| +0x00  | STATUS    | R      | TX_READY, RX_AVAIL, etc. |
| +0x04  | TX_DATA   | W      | Transmit byte            |
| +0x08  | RX_DATA   | R      | Receive byte             |
| +0x0C  | CTRL      | R/W    | IRQ enables, loopback    |

Settings: 115200 baud, 8N1

## LED Status

| LED | Function          |
|-----|-------------------|
| 0   | Heartbeat (1 Hz)  |
| 1   | Reset released    |
| 2   | Emulation mode    |
| 3   | Opcode fetch      |
| 4   | Boot ROM access   |
| 5   | UART access       |
| 6   | RAM access        |
| 7   | UART IRQ pending  |

## Pin Assignments - IMPORTANT!

**The pin assignments in `m65832_de25.qsf` are PLACEHOLDERS.**

Before synthesis, you MUST:

1. Download the DE25-Nano User Manual from Terasic
2. Find the pin assignment tables for:
   - 50 MHz clock oscillator
   - UART TX/RX (directly directly directly directly on FPGA side directly)
   - LED[7:0]
   - Reset button (KEY0)
   - SDRAM interface (when ready)
3. Update `m65832_de25.qsf` with the correct pin locations

The user manual should have tables like:
```
Signal      FPGA Pin    Description
--------    --------    -----------
CLOCK_50    PIN_xxx     50 MHz oscillator
LED[0]      PIN_xxx     User LED 0
...
```

## Files

| File                  | Description                      |
|-----------------------|----------------------------------|
| `m65832_de25.qpf`     | Quartus project file             |
| `m65832_de25.qsf`     | Quartus settings (pins, options) |
| `m65832_de25.sdc`     | Timing constraints               |
| `m65832_de25_top.vhd` | Top-level SoC wrapper            |
| `m65832_uart.vhd`     | UART peripheral                  |
| `m65832_bootrom.vhd`  | Boot ROM (placeholder code)      |

## Next Steps

1. **Verify pin assignments** for your specific board
2. **Add PLL** for stable clock generation
3. **Add SDRAM controller** for full memory
4. **Write proper boot ROM** using m65832as assembler
5. **Test UART echo** via serial terminal
