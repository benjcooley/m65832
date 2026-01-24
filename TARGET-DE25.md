DE25-Nano Target Notes (Bootstrap)
=================================

This document captures initial assumptions for a DE25-Nano bring-up and a
minimal terminal bootstrap plan. These are starting points, not final specs.

Board Summary (Given)
---------------------
- FPGA: A5EB013BB23BE4SCS (138K Logic Elements)
- Memory (FPGA side):
  - LPDDR4: 1 GB, 32-bit bus, 2666 MT/s (Rev B) / 2133 MT/s (Rev A)
  - SDRAM: 128 MB, 16-bit bus
- UART: 2-pin UART via USB Type-C
- HDMI, GPIO, ADC, MIPI, etc. (not needed for earliest boot)

Bring-Up Goals (Phase 0)
-----------------------
Project Vision (Guiding Targets)
--------------------------------
What if these 8-bit consoles had kept innovating, building new backwards
compatible but more advanced chips and systems?

What if there was a Commodore 256 in 1998? Or an Atari 3200?

Guiding targets:
- Late‑90s/early‑2000s “successor” to classic home computers.
- Modernized creative hardware/software appliance (OP‑1‑like feel).
- Emulation mode to run classic 6502 software and systems.
- Strong custom co‑processors (DMA, audio, graphics) with drivers.
- Decent performance (Pentium‑I‑class user experience), not bleeding edge.

1) Get a stable clock and reset into M65832.
2) Execute ROM from BRAM or QSPI shadow.
3) Initialize a RAM region for stack and data.
4) Bring up UART for a text console (polled I/O).
5) Run a tiny monitor with basic commands (mem read/write, dump, jump).

Clocking (Initial Assumptions)
------------------------------
- Use a safe initial CPU clock: 25-50 MHz (FPGA internal PLL).
- Reasoning: conservative timing closure and easy UART divisors.
- Later: scale to 100-150 MHz once memory timing and buses are stable.

Memory (Initial Assumptions)
----------------------------
Option A: SDRAM for early boot (simpler controller).
- 128 MB, 16-bit bus.
- Use a small ROM (BRAM or QSPI shadow) for reset vector and monitor.
- Map RAM at 0x0000_0000.

Option B: LPDDR4 for early boot (more complex controller).
- 1 GB, 32-bit bus.
- Better bandwidth and capacity, but controller integration is larger.
- Consider switching to LPDDR4 only after the UART monitor is stable.

Suggested Memory Map (Draft)
----------------------------
- 0x0000_0000 - 0x07FF_FFFF : SDRAM or LPDDR4 (main RAM)
- 0xFFFF_0000 - 0xFFFF_0FFF : Boot ROM / vectors (BRAM shadow)
- 0xFFFF_F000 - 0xFFFF_FFFF : SoC registers (UART, timer, GPIO, etc.)

Terminal Bootstrap Plan
-----------------------
Stage 0: ROM Monitor
- Reset vector points to a tiny ROM monitor in BRAM.
- Initialize stack and zero BSS (if any).
- Initialize UART at fixed baud (115200 8N1 recommended).
- Provide simple commands:
  - "md <addr> <len>" : memory dump
  - "mw <addr> <val>" : memory write
  - "go <addr>"       : jump to address

Stage 1: RAM Loader
- Add a simple XMODEM or raw binary loader over UART.
- Load a larger monitor or test program into RAM.

Stage 2: Minimal C Runtime
- Add a tiny C runtime to support a barebones shell.
- Provide a small libc subset for printf/scanf-like routines.

UART (Initial Assumptions)
--------------------------
- Polled UART TX/RX for simplicity.
- Typical divisor for 50 MHz and 115200 baud:
  - divisor = 50_000_000 / (16 * 115200) ≈ 27.1
- Choose nearest integer; adjust based on actual clock.

Minimal Linux Goal
------------------
Target is a minimal Linux console on DE25-Nano.

Early Requirements (Minimum)
----------------------------
- MMU: required for standard Linux (unless using uClinux).
- Timer interrupt: periodic tick (or tickless) for scheduler.
- UART: console for early printk.
- Block device: initramfs over UART or SD card (recommended).
- Boot loader: load kernel + optional initramfs into RAM and jump to entry.

Boot Flow (Draft)
-----------------
1) ROM monitor initializes clock, RAM, UART.
2) Load Linux kernel image (and optional initramfs) from UART or SD.
3) Jump to kernel entry with:
   - r0 = 0, r1 = machine ID (or DTB pointer if using device tree),
   - r2 = DTB pointer (preferred).
4) Early printk on UART, then initramfs or SD root.

Minimal Kernel Config (Conceptual)
----------------------------------
- No SMP, no modules, no framebuffer.
- Enable UART early console.
- Use initramfs first, then add SD block driver.

Notes for Toolchain / ABI
-------------------------
- 64-bit load/store (LDQ/STQ) added; useful for long long moves.
- Register window (RSET) can serve as a fast local register file.
- Keep ABI simple: A=low32, T=high32 for 64-bit values.

Potential Performance Accelerators (Future)
-------------------------------------------
- MEMSET/MEMCPY assist: tiny block mover for libc hot paths.
- HASHZ: hash zero-terminated strings for symbol lookup and loaders.
- HASHN: hash N bytes (length in X) for table lookups.

Open Questions
--------------
- Use SDRAM or LPDDR4 for first boot?
- Final clock target after timing closure?
- UART base address and register layout?
- Timer/cycle counter mapping for delays?
- MMU design and page size?
- Linux boot ABI: DTB vs fixed machine ID?

Next Steps
----------
- Define UART register map and implement a minimal UART peripheral.
- Decide early RAM (SDRAM vs LPDDR4) and add controller stub.
- Add a ROM image build step and test a "Hello" console.
- Decide MMU interface and page table format.

Toolchain Bootstrap (Later Stage)
---------------------------------
- Defer binutils/LLVM/GCC until hardware validation is solid.
- Focus first on on-board validation tests and UART console.
- Once stable, bootstrap assembler/linker and C toolchain.
