# M65832 Emulator

High-performance emulator for the M65832 processor architecture. Supports the full M65832 instruction set including the 6502 coprocessor subsystem.

## Features

- **Complete M65832 CPU emulation**
  - All 6502/65816 instructions
  - M65832 extended instructions ($02 prefix)
  - Extended ALU sizing via $02 prefix (WID removed)
  - Variable register widths (8/16/32-bit)
  - Default: 32-bit native mode (for new code)
  - Optional: 6502 emulation mode (for legacy code)
  
- **Floating Point Unit (FPU)**
  - Three 64-bit FPU registers (F0, F1, F2)
  - Single-precision operations (FADD.S, FSUB.S, FMUL.S, FDIV.S, FNEG.S, FABS.S, FCMP.S)
  - Double-precision operations (FADD.D, FSUB.D, FMUL.D, FDIV.D, FNEG.D, FABS.D, FCMP.D)
  - Conversion instructions (F2I.S, I2F.S, F2I.D, I2F.D)
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
```

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
