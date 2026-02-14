# M65832 Emulator Debugging Guide

## Quick Start

```bash
# Terminal 1: Start emulator with debug server
./m65832emu --system --kernel vmlinux --debug

# Terminal 2: Send commands via edb
edb "b start_kernel"    # Set breakpoint at symbol
edb c                   # Continue execution
edb wait                # Block until CPU stops
edb reg                 # Show registers
edb dis                 # Disassemble at PC
edb list                # Show source code (requires DWARF)
```

## Starting the Debug Server

### System mode (Linux kernel)
```bash
./m65832emu --system --kernel path/to/vmlinux --debug
```

### Legacy mode (baremetal ELF)
```bash
./m65832emu --debug program.elf
```

The emulator starts paused. Use `edb c` to begin execution.

### With boot ROM (DMA kernel loading)
```bash
./m65832emu --system --bootrom rom.bin --kernel vmlinux --disk disk.img --debug
```
The boot ROM must execute `WDM #$01` after DMA-loading the kernel.
This signals the debugger to re-insert any breakpoints into the freshly-loaded image.

## The `edb` Command

`edb` sends a single command to the debug server and prints the response:
```bash
edb COMMAND [ARGS...]
```

Multiple arguments are joined: `edb b start_kernel` sends `"b start_kernel"`.

## Command Reference

### Inspection

| Command | Description |
|---------|-------------|
| `reg` | Show all registers (PC, A, X, Y, S, P) with disassembly and source |
| `mem ADDR [N]` | Hex dump N lines (16 bytes each) starting at ADDR |
| `dis [ADDR] [N]` | Disassemble N instructions (default: 10 at PC). Shows source annotations |
| `bt` | Backtrace: walk stack and show return addresses with symbols |
| `list [ADDR]` | Show source code context (requires DWARF). Opens the C source file |
| `sys` | System registers: MMUCR, VBR, PTBR, timer |
| `tlb` | Dump TLB entries |

### Symbols

| Command | Description |
|---------|-------------|
| `sym ADDR` | Look up symbol containing address |
| `addr NAME` | Find address of a named symbol |

### Breakpoints

| Command | Description |
|---------|-------------|
| `b ADDR\|SYMBOL` | Set software breakpoint (writes BRK opcode) |
| `bc [ADDR]` | Clear breakpoint at ADDR, or all if no argument |
| `bl` | List all breakpoints |

### Watchpoints

| Command | Description |
|---------|-------------|
| `wp ADDR [0\|1]` | Set watchpoint. 0=read/write (default), 1=write-only |
| `wc [ADDR]` | Clear watchpoint at ADDR, or all |
| `wl` | List watchpoints |

When a watchpoint triggers, the debugger pauses and reports the address, current value, and the PC that caused the access.

### Register Access

| Command | Description |
|---------|-------------|
| `pc [VAL]` | Get or set Program Counter |
| `a [VAL]` | Get or set Accumulator |
| `x [VAL]` | Get or set X register |
| `y [VAL]` | Get or set Y register |
| `w ADDR VAL` | Write a byte to memory |

### Execution Control

| Command | Description |
|---------|-------------|
| `s [N]` | Step N instructions (default 1) |
| `n` | Step over: execute calls as a single step |
| `finish` | Run until current function returns (reads return address from stack) |
| `until ADDR\|SYM` | Run until a specific address or symbol |
| `c` | Continue execution |
| `r [N]` | Run for N cycles synchronously (shows result when done) |
| `pause` | Pause execution |
| `wait` | Block until CPU stops (breakpoint, watchpoint, or halt) |
| `trace [on\|off]` | Toggle instruction tracing to stdout |

### System

| Command | Description |
|---------|-------------|
| `status` | Show running/paused state, cycle and instruction counts |
| `reset` | CPU reset |
| `irq [0\|1]` | Assert or deassert IRQ |
| `nmi` | Trigger NMI |
| `q` | Quit emulator |
| `help` | Show command reference |

## Source-Level Debugging

### Enabling DWARF

The kernel must be built with debug info. In `.config`:
```
CONFIG_DEBUG_INFO_DWARF4=y
CONFIG_DEBUG_INFO=y
```
Then rebuild: `make -j$(nproc)`

The emulator automatically loads DWARF `.debug_line` from the ELF.

### Workflow

```bash
# Set a breakpoint at a C function
edb "b start_kernel"
edb c
edb wait

# See where you are with source context
edb list              # Shows ~10 lines of C source around current PC
edb dis               # Disassembly with interleaved source annotations
edb reg               # Registers show file:line

# Step through C code
edb n                 # Step over function calls
edb s                 # Step into (single instruction)
edb finish            # Run until current function returns
edb "until setup_arch"  # Run until a function

# Inspect state
edb bt                # Backtrace with symbols
edb "mem 80000000 8"  # Dump memory
edb sys               # MMU state
edb tlb               # Page table entries

# Watch a variable
edb "wp 80123456"     # Watch a memory location (read/write)
edb c
edb wait              # Will stop when the location is accessed
```

## Debugging a Kernel Crash

When the kernel oopses (NULL pointer deref, illegal instruction, etc.):

### Strategy 1: Breakpoint at the crash site
```bash
edb "b die"           # Break at kernel's die() function
edb c
edb wait
edb bt                # See full call stack
edb reg               # See register state
edb list              # See source code
```

### Strategy 2: Binary search with breakpoints
```bash
# Set breakpoints at init functions to narrow down where crash occurs
edb "b setup_arch"
edb "b mm_init"
edb "b sched_init"
edb c
edb wait              # See which one gets hit
```

### Strategy 3: Watch for corruption
```bash
# If a known struct gets corrupted, watch its memory
edb "addr init_task"  # Find the address
edb "wp 805XXXXX 1"   # Watch for writes
edb c
edb wait              # Stops at the write that corrupts it
```

## Boot ROM Integration

For hardware boot flows where the boot ROM loads the kernel via DMA:

1. The boot ROM finishes loading the kernel to RAM
2. The boot ROM executes: `WDM #$01` (bytes: `42 01`)
3. The emulator intercepts this, re-inserts all software breakpoints
4. Execution continues transparently

If no debugger is attached, `WDM #$01` is a harmless 2-cycle NOP.

## Architecture Notes

- **Software breakpoints**: The debugger writes BRK (`$00`) opcodes into memory. When hit, the original byte is restored and the debugger pauses.
- **Zero per-step overhead**: The main loop only checks a single `volatile int` flag. The mutex is only acquired when a command is actually pending.
- **Temporary breakpoints**: `next`, `until`, and `finish` use auto-removing breakpoints that don't persist after being hit.
- **WDM trap**: `WDM #$01` signals "kernel loaded" for DMA-based boot flows, handled transparently.
