# M65832 Emulator

High-performance emulator for the M65832 processor architecture. Supports the full M65832 instruction set including the 6502 coprocessor subsystem.

## Features

- **Complete M65832 CPU emulation**
  - All 6502/65816 instructions
  - M65832 extended instructions ($02 prefix)
  - Extended ALU instructions via $02 prefix
  - Variable register widths (8/16/32-bit)
  - Default: 32-bit native mode (for new code)
  - 16 and 8 bit modes (non-coprocessor compatibility processes)
  - ONE 6502 cycle accurate coprocessor process (for legacy code)
  
- **Floating Point Unit (FPU)**
  - Sixteen 64-bit FPU registers (F0-F15)
  - Two-operand destructive format: Fd = Fd op Fs
  - Single-precision operations (FADD.S, FSUB.S, FMUL.S, FDIV.S, FNEG.S, FABS.S, FCMP.S, FMOV.S, FSQRT.S)
  - Double-precision operations (FADD.D, FSUB.D, FMUL.D, FDIV.D, FNEG.D, FABS.D, FCMP.D, FMOV.D, FSQRT.D)
  - Conversion instructions (F2I.S, I2F.S, F2I.D, I2F.D, FCVT.DS, FCVT.SD)
  - Register transfer instructions (FTOA, FTOT, ATOF, TTOF)
  - Load/store (LDF0/LDF1/LDF2, STF0/STF1/STF2)
  - Reserved opcode trap for software emulation
  
- **Memory Management Unit (MMU)**
  - Two-level page table walking
  - TLB with 16 entries
  - Page fault exception handling with FAULTVA latching
  - User/supervisor page protection
  - Write protection
  
- **Timer**
  - 32-bit compare/count timer
  - IRQ generation on count match
  - Count latching at IRQ for precise reading
  - Auto-reset mode

- **Block Device**
  - Sector-based disk I/O (512-byte sectors)
  - DMA transfers to/from system memory
  - Read, write, flush commands
  - Disk image file backing
  - IRQ on command completion
  - Supports disks up to 2^64 sectors
  
- **6502 Coprocessor**
  - Cycle-accurate 6502/65C02 emulation
  - NMOS and CMOS modes
  - BCD arithmetic support
  - Shadow I/O registers with write FIFO
  
- **MMIO Support**
  - Register memory-mapped I/O handlers
  - Custom read/write callbacks per region
  - Essential for building machine emulators
  
- **Debugging Support**
  - Interactive debugger mode
  - Instruction tracing
  - Breakpoints and watchpoints
  - Memory inspection and modification
  - Register inspection and modification

- **Library and Standalone**
  - Use as a library (`libm65832emu.a`)
  - Or as a standalone emulator (`m65832emu`)

## Building

```bash
# Build everything
make

# Build debug version (with sanitizers)
make debug

# Build optimized for profiling
make profile

# Install to /usr/local
sudo make install
```

## Usage

### Command Line

```bash
# Run a binary program
./m65832emu program.bin

# Load at specific address
./m65832emu -o 0x1000 program.bin

# Set entry point
./m65832emu -o 0x1000 -e 0x1000 program.bin

# Enable tracing
./m65832emu -t program.bin

# Limit execution to 10000 cycles
./m65832emu -c 10000 program.bin

# Use 1MB of memory
./m65832emu -m 1024 program.bin

# Load Intel HEX file
./m65832emu -x program.hex

# Run in 6502 emulation mode (for legacy code)
./m65832emu --emulation program.bin

# Interactive debugger
./m65832emu -i program.bin

# System mode with sandboxed filesystem for TRAP syscalls
./m65832emu --system --kernel program.bin --sandbox ./sandbox
```

### System Mode and Sandbox Syscalls

When running with `--system`, the emulator provides a minimal system
environment with UART, block device, and a TRAP-based syscall handler.
If `--sandbox` is provided, file-related syscalls (`open`, `read`, `write`,
`close`, `lseek`, `fstat`) are serviced against that host directory. Paths
are constrained to the sandbox root; `..` references are rejected. Without
`--sandbox`, those file syscalls return `ENOSYS` while exit/getpid still work.

### Interactive Debugger Commands

```
s, step [n]        Step n instructions (default 1)
c, continue        Continue execution
r, run [cycles]    Run for cycles (default: until halt)
reg, regs          Show registers
m, mem ADDR [n]    Show memory (n lines, default 4)
d, dis ADDR [n]    Disassemble n instructions
b, break ADDR      Set breakpoint
bc, clear [ADDR]   Clear breakpoint(s)
bl, list           List breakpoints
w, write ADDR VAL  Write byte to memory
pc ADDR            Set program counter
a VAL              Set accumulator
x VAL              Set X register
y VAL              Set Y register
reset              Reset CPU
trace [on|off]     Toggle instruction tracing
coproc             Show 6502 coprocessor state
mmio               Show MMIO regions
q, quit            Exit debugger
```

## Library API

### Basic Usage

```c
#include "m65832emu.h"

int main() {
    // Initialize with 64KB memory
    m65832_cpu_t *cpu = m65832_emu_init(64 * 1024);
    
    // Load a program
    m65832_load_binary(cpu, "program.bin", 0x1000);
    
    // Set reset vector and reset
    m65832_emu_write16(cpu, 0xFFFC, 0x1000);
    m65832_emu_reset(cpu);
    
    // Run until halt
    while (m65832_emu_is_running(cpu)) {
        m65832_emu_step(cpu);
    }
    
    // Print final state
    m65832_print_state(cpu);
    
    // Clean up
    m65832_emu_close(cpu);
    return 0;
}
```

### MMIO Handlers

```c
// MMIO read handler
uint32_t uart_read(m65832_cpu_t *cpu, uint32_t addr, 
                   uint32_t offset, int width, void *user) {
    uart_state_t *uart = (uart_state_t *)user;
    switch (offset) {
        case 0: return uart->status;
        case 4: return uart->rx_data;
        default: return 0xFF;
    }
}

// MMIO write handler
void uart_write(m65832_cpu_t *cpu, uint32_t addr,
                uint32_t offset, uint32_t value, int width, void *user) {
    uart_state_t *uart = (uart_state_t *)user;
    switch (offset) {
        case 4: uart_send(uart, value); break;
        case 8: uart->control = value; break;
    }
}

// Register MMIO region
uart_state_t uart;
m65832_mmio_register(cpu, 0x10000000, 16, uart_read, uart_write, &uart, "UART");
```

### Memory Access

```c
// Read/write individual bytes
uint8_t val = m65832_emu_read8(cpu, 0x1000);
m65832_emu_write8(cpu, 0x1000, 0x42);

// Read/write 16/32-bit values (little-endian)
uint16_t val16 = m65832_emu_read16(cpu, 0x1000);
uint32_t val32 = m65832_emu_read32(cpu, 0x1000);

// Block operations
uint8_t data[256];
m65832_emu_read_block(cpu, 0x1000, data, 256);
m65832_emu_write_block(cpu, 0x2000, data, 256);

// Direct memory access (fast but bypasses MMIO)
uint8_t *mem = m65832_emu_get_memory_ptr(cpu);
```

### 6502 Coprocessor

```c
// Initialize 6502 coprocessor at C64 NTSC frequency
m65832_coproc_init(cpu, 1022727, 50000000, COMPAT_DECIMAL_EN);

// Set VBR for 6502 address translation
m65832_coproc_set_vbr(cpu, 0x00010000);  // 6502 memory at 64KB offset

// Configure shadow I/O banks
m65832_coproc_set_shadow_bank(cpu, 0, 0xD000);  // VIC-II
m65832_coproc_set_shadow_bank(cpu, 1, 0xD400);  // SID

// Run coprocessor for some cycles
m65832_coproc_run(cpu, 1000);

// Trigger interrupts
m65832_coproc_irq(cpu, true);
m65832_coproc_nmi(cpu);
```

## API Reference

### Lifecycle

| Function | Description |
|----------|-------------|
| `m65832_emu_init(size)` | Initialize emulator with memory size |
| `m65832_emu_close(cpu)` | Free emulator resources |
| `m65832_emu_reset(cpu)` | Reset CPU to initial state |
| `m65832_emu_is_running(cpu)` | Check if CPU is running |

### Execution

| Function | Description |
|----------|-------------|
| `m65832_emu_step(cpu)` | Execute single instruction |
| `m65832_emu_run(cpu, cycles)` | Run for specified cycles |
| `m65832_stop(cpu)` | Stop execution |

### Memory

| Function | Description |
|----------|-------------|
| `m65832_emu_set_memory_size(cpu, size)` | Resize memory |
| `m65832_emu_get_memory_size(cpu)` | Get memory size |
| `m65832_emu_read8/16/32(cpu, addr)` | Read from memory |
| `m65832_emu_write8/16/32(cpu, addr, val)` | Write to memory |
| `m65832_emu_read_block(cpu, addr, buf, size)` | Read block |
| `m65832_emu_write_block(cpu, addr, data, size)` | Write block |
| `m65832_load_binary(cpu, file, addr)` | Load binary file |
| `m65832_load_hex(cpu, file)` | Load Intel HEX file |

### MMIO

| Function | Description |
|----------|-------------|
| `m65832_mmio_register(...)` | Register MMIO region |
| `m65832_mmio_unregister(cpu, idx)` | Unregister by index |
| `m65832_mmio_unregister_addr(cpu, addr)` | Unregister by address |
| `m65832_mmio_clear(cpu)` | Remove all MMIO regions |
| `m65832_mmio_find(cpu, addr)` | Find region by address |
| `m65832_mmio_print(cpu)` | Print all regions |

### Registers

| Function | Description |
|----------|-------------|
| `m65832_get_a/x/y/s/pc/d/b/t/p(cpu)` | Get register value |
| `m65832_set_a/x/y/s/pc/d/b/t/p(cpu, val)` | Set register value |
| `m65832_flag_c/z/i/d/v/n/e/s/r/k(cpu)` | Get flag state |

### Debugging

| Function | Description |
|----------|-------------|
| `m65832_set_trace(cpu, enable, fn, user)` | Enable tracing |
| `m65832_add_breakpoint(cpu, addr)` | Add breakpoint |
| `m65832_remove_breakpoint(cpu, addr)` | Remove breakpoint |
| `m65832_print_state(cpu)` | Print CPU state |
| `m65832_get_trap(cpu)` | Get last trap code |

### Interrupts

| Function | Description |
|----------|-------------|
| `m65832_irq(cpu, active)` | Assert/deassert IRQ |
| `m65832_nmi(cpu)` | Trigger NMI |
| `m65832_abort(cpu)` | Trigger ABORT |

## Building a Machine

To emulate a complete system (like running Linux), you need to:

1. **Initialize with sufficient memory** (e.g., 256MB for Linux)
2. **Register MMIO handlers** for peripherals:
   - UART for console I/O
   - Timer for interrupts
   - Interrupt controller
   - Storage device
3. **Load the kernel** and set up boot parameters
4. **Set reset vector** to kernel entry point
5. **Run the emulator** with interrupt handling

Example machine configuration:

```c
m65832_cpu_t *cpu = m65832_emu_init(256 * 1024 * 1024);  // 256MB RAM

// MMIO regions
m65832_mmio_register(cpu, 0x10000000, 0x100, uart_read, uart_write, &uart, "UART0");
m65832_mmio_register(cpu, 0x10001000, 0x100, timer_read, timer_write, &timer, "TIMER");
m65832_mmio_register(cpu, 0x10002000, 0x100, intc_read, intc_write, &intc, "INTC");

// Load kernel
m65832_load_binary(cpu, "vmlinux", 0x80000000);

// Enter native mode and run
m65832_set_pc(cpu, 0x80000000);
uint16_t p = m65832_get_p(cpu);
m65832_set_p(cpu, (p & ~P_E) | P_S);  // Native mode, supervisor

while (m65832_emu_is_running(cpu)) {
    m65832_emu_step(cpu);
    timer_tick(&timer, cpu);  // Update timer
}
```

## Block Device

The emulator includes a simple block device for disk I/O. It uses DMA transfers to read/write sectors between the disk image and system memory.

### Block Device Registers (at 0x00FFF120)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | STATUS | R | Status register (see bits below) |
| 0x04 | COMMAND | W | Command register |
| 0x08 | SECTOR_LO | R/W | Sector number bits 0-31 |
| 0x0C | SECTOR_HI | R/W | Sector number bits 32-63 |
| 0x10 | DMA_ADDR | R/W | DMA address in system memory |
| 0x14 | COUNT | R/W | Number of sectors to transfer |
| 0x18 | CAPACITY_LO | R | Disk capacity (sectors) bits 0-31 |
| 0x1C | CAPACITY_HI | R | Disk capacity (sectors) bits 32-63 |

### Status Register Bits

| Bit | Name | Description |
|-----|------|-------------|
| 0 | READY | Device ready for commands |
| 1 | BUSY | Operation in progress |
| 2 | ERROR | Error occurred (error code in high byte) |
| 3 | DRQ | Data request (PIO mode, not used) |
| 4 | PRESENT | Media present |
| 5 | WRITABLE | Media is writable |
| 6 | IRQ | IRQ pending (operation complete) |

### Commands

| Code | Name | Description |
|------|------|-------------|
| 0x00 | NOP | No operation |
| 0x01 | READ | Read sector(s) via DMA |
| 0x02 | WRITE | Write sector(s) via DMA |
| 0x03 | FLUSH | Flush write cache to disk |
| 0x04 | IDENTIFY | Identify device |
| 0x05 | RESET | Reset device |
| 0x06 | ACK_IRQ | Acknowledge interrupt |

### Usage Example (Assembly)

```asm
BLKDEV_BASE     = $00FFF120
BLKDEV_STATUS   = BLKDEV_BASE + $00
BLKDEV_COMMAND  = BLKDEV_BASE + $04
BLKDEV_SECTOR   = BLKDEV_BASE + $08
BLKDEV_DMA_ADDR = BLKDEV_BASE + $10
BLKDEV_COUNT    = BLKDEV_BASE + $14

; Read sector 0 into memory at $10000
    LDA #0
    STA BLKDEV_SECTOR       ; Sector 0
    LDA #$10000
    STA BLKDEV_DMA_ADDR     ; DMA to $10000
    LDA #1
    STA BLKDEV_COUNT        ; Read 1 sector
    LDA #1
    STA BLKDEV_COMMAND      ; Issue READ command

.wait:
    LDA BLKDEV_STATUS
    AND #$01                ; Check READY bit
    BEQ .wait               ; Wait until ready
```

### Command Line

```bash
# Run with a disk image
./m65832emu --system --disk rootfs.img kernel.bin

# Create a 10MB disk image
dd if=/dev/zero of=disk.img bs=512 count=20480

# Run with read-only disk
./m65832emu --system --disk disk.img --disk-ro kernel.bin
```

## Performance

On a modern x86-64 system, the emulator typically achieves:
- 50-100 MIPS in optimized mode
- Full Linux boot in seconds (estimated)

For maximum performance:
- Use `-O3 -march=native` (default in Makefile)
- Minimize MMIO regions in hot paths
- Use `m65832_emu_run()` instead of `m65832_emu_step()` when possible

## License

See the project LICENSE file for details.
