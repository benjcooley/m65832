# M65832 Timing and Cycle Compatibility

**Achieving authentic 6502 timing for classic software**

> **Note**: This document describes timing concepts. For the final three-core
> architecture (M65832 + Servicer + 6502), see 
> [Classic Coprocessor Architecture](M65832_Classic_Coprocessor.md).

---

## 1. The Timing Challenge

### 1.1 Why Cycles Matter

Classic 6502 software often depends on precise timing:

```
Example: C64 raster effect
─────────────────────────────────────────
LDA #$00        ; 2 cycles
STA $D020       ; 4 cycles  ← Change border color
LDX #$09        ; 2 cycles
loop:
  DEX           ; 2 cycles
  BNE loop      ; 3/2 cycles ← Waste exactly 43 cycles
NOP             ; 2 cycles
LDA #$01        ; 2 cycles
STA $D020       ; 4 cycles  ← Change color again at exact raster position
```

If cycles are wrong, the color changes at the wrong position and the effect breaks.

### 1.2 Speed Mismatch

| System | CPU Speed | Our FPGA | Ratio |
|--------|-----------|----------|-------|
| C64 (PAL) | 0.985 MHz | 50 MHz | 50x |
| C64 (NTSC) | 1.023 MHz | 50 MHz | 49x |
| NES (NTSC) | 1.789 MHz | 50 MHz | 28x |
| Apple II | 1.023 MHz | 50 MHz | 49x |
| SNES | 3.58 MHz | 50 MHz | 14x |

Running at full FPGA speed would make games unplayably fast.

---

## 2. Timing Architecture

### 2.1 Core Concept: Cycle Budget

Each 6502-mode process gets a **cycle budget** that controls execution rate:

```
┌─────────────────────────────────────────────────────────────┐
│                    Timing Control Unit                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Master Clock│───▶│Clock Divider│───▶│ Cycle       │     │
│  │   50 MHz    │    │ (per-task)  │    │ Counter     │     │
│  └─────────────┘    └─────────────┘    └──────┬──────┘     │
│                                                │             │
│                                         ┌──────▼──────┐     │
│                                         │  Execute    │     │
│                                         │  Gate       │     │
│                                         └──────┬──────┘     │
│                                                │             │
│                                         ┌──────▼──────┐     │
│                                         │   CPU Core  │     │
│                                         └─────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Timing Registers

New system registers for timing control:

| Register | Address | Description |
|----------|---------|-------------|
| CLKDIV | $FFFFF100 | Clock divider (32-bit) |
| CYCLECOUNT | $FFFFF104 | Current cycle count (64-bit, read-only) |
| CYCLEBUDGET | $FFFFF10C | Cycles allowed before stall (32-bit) |
| TIMINGMODE | $FFFFF110 | Timing control flags |

#### CLKDIV Register

Divides master clock to achieve target frequency:

```
Target_freq = Master_clock / (CLKDIV + 1)

Example: 50 MHz master, want 1.023 MHz (C64 NTSC):
CLKDIV = (50,000,000 / 1,023,000) - 1 = 48

Example: 50 MHz master, want 1.789 MHz (NES):
CLKDIV = (50,000,000 / 1,789,000) - 1 = 27
```

#### TIMINGMODE Register

```
Bit 0:    CYCLE_ACCURATE  - Enable cycle-accurate execution
Bit 1:    STALL_ON_BUDGET - Stall when cycle budget exhausted
Bit 2:    SYNC_VBLANK     - Sync to video blanking
Bit 3:    SYNC_HBLANK     - Sync to horizontal blanking
Bit 7:4:  Reserved
Bit 15:8: REGION          - 0=NTSC (60Hz), 1=PAL (50Hz)
```

### 2.3 Per-Instruction Cycle Counting

The CPU tracks cycles for each instruction:

```vhdl
-- Cycle count lookup (simplified)
type cycle_table is array(0 to 255) of integer range 0 to 7;
constant CYCLES_6502 : cycle_table := (
    -- $00 BRK = 7, $01 ORA (zp,X) = 6, ...
    7, 6, 0, 0, 0, 3, 5, 0,  -- $00-$07
    3, 2, 2, 0, 0, 4, 6, 0,  -- $08-$0F
    2, 5, 0, 0, 0, 4, 6, 0,  -- $10-$17 (BPL = 2/3)
    -- ... full table ...
);
```

**Cycle modifiers:**
- Page boundary crossed: +1 cycle
- Branch taken: +1 cycle (sometimes +2)
- 16-bit operation: +1 cycle (65816 mode)

---

## 3. Execution Model

### 3.1 Cycle-Accurate Mode (E=1, CYCLE_ACCURATE=1)

```
For each instruction:
1. Decode instruction, determine base cycles
2. Add modifiers (page cross, branch taken)
3. Wait for (cycles × CLKDIV) master clocks
4. Execute instruction
5. Update CYCLECOUNT
```

**Example execution at 1 MHz (CLKDIV=49):**

```
Instruction: LDA $1234,X (4 cycles, +1 if page cross)

Master clock ticks needed: 4 × 50 = 200 ticks
If page cross: 5 × 50 = 250 ticks

Timeline:
  Tick 0:     Fetch opcode, start decode
  Tick 1-49:  Wait (appear to be "fetching operand")
  Tick 50-99: Wait (appear to be "calculating address")
  Tick 100-149: Wait (appear to be "reading memory")
  Tick 150-199: Wait (appear to be "loading accumulator")
  Tick 200:   Instruction complete, next instruction
```

### 3.2 Fast Mode (E=0 or CYCLE_ACCURATE=0)

Instructions execute as fast as the pipeline allows:
- No artificial delays
- CYCLECOUNT still tracks (for profiling)
- Maximum performance

### 3.3 Hybrid Mode: Budget-Based

For "mostly accurate" timing without per-cycle stalls:

```
CYCLEBUDGET = cycles_per_frame (e.g., 1,000,000 for ~1MHz at 60fps)

Execution:
1. Run at full speed, counting cycles
2. When CYCLEBUDGET exhausted, stall until VBlank
3. VBlank resets budget
```

This gives correct *average* speed without per-instruction delays.
Good for games that only care about frame rate, not raster timing.

---

## 4. Video Synchronization

### 4.1 VBlank/HBlank Timing

For proper video sync, we need accurate blanking intervals:

| System | HBlank | VBlank | Frame Rate |
|--------|--------|--------|------------|
| C64 PAL | 63 cycles | 312 lines | 50.125 Hz |
| C64 NTSC | 65 cycles | 263 lines | 59.826 Hz |
| NES NTSC | 113.7 cycles | 262 lines | 60.098 Hz |
| Apple II | 65 cycles | 262 lines | 60 Hz |

### 4.2 Raster Counter

```
RASTERLINE ($FFFFF120): Current raster line (0-311 PAL, 0-262 NTSC)
RASTERCYCLE ($FFFFF124): Cycle within current line
```

Games can poll or get interrupts:
```asm
; Wait for specific raster line
wait_raster:
    LDA RASTERLINE
    CMP #$80            ; Line 128
    BNE wait_raster
    ; Now at line 128
```

### 4.3 Raster Interrupts

```
RASTERIRQ ($FFFFF128): Line number to trigger IRQ
RASTERFLAG ($FFFFF12C): Bit 0 = raster IRQ pending
```

---

## 5. Per-Process Timing Configuration

### 5.1 Task Timing State

```c
struct task_timing {
    uint32_t clkdiv;        // Clock divider
    uint32_t timing_mode;   // TIMINGMODE flags
    uint64_t cycle_count;   // Cycles executed
    uint32_t cycle_budget;  // Per-frame budget
    uint8_t  region;        // NTSC/PAL
};
```

### 5.2 Context Switch Timing

On context switch:
1. Save current process's timing state
2. Load new process's timing state
3. Adjust divider hardware

```asm
switch_timing:
    ; Save current timing
    LDA current_task
    TAX
    LDA CLKDIV
    STA TASK_CLKDIV,X
    LDA CYCLECOUNT
    STA TASK_CYCLES,X
    LDA CYCLECOUNT+4
    STA TASK_CYCLES+4,X
    
    ; Load new timing
    LDA new_task
    TAX
    LDA TASK_CLKDIV,X
    STA CLKDIV
    LDA TASK_TIMING_MODE,X
    STA TIMINGMODE
    
    RTS
```

### 5.3 Mixed Timing Example

```
Process 1: C64 game
  - CLKDIV = 49 (1.02 MHz)
  - CYCLE_ACCURATE = 1
  - REGION = NTSC
  - Gets 17,045 cycles per 1/60th second

Process 2: Linux app  
  - CLKDIV = 0 (50 MHz)
  - CYCLE_ACCURATE = 0
  - Runs at full speed

Scheduler gives each process time slices.
6502 process runs slower but accurately.
Linux process runs at full speed.
```

---

## 6. Hardware Implementation

### 6.1 Cycle Counter Module

```vhdl
entity cycle_counter is
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        
        -- Configuration
        clk_divider : in  std_logic_vector(31 downto 0);
        cycle_accurate : in std_logic;
        
        -- From decoder
        instr_cycles : in std_logic_vector(3 downto 0);
        page_cross   : in std_logic;
        branch_taken : in std_logic;
        
        -- Control
        instr_start  : in  std_logic;
        instr_done   : out std_logic;
        
        -- Cycle count output
        cycle_count  : out std_logic_vector(63 downto 0)
    );
end entity;

architecture rtl of cycle_counter is
    signal div_counter : unsigned(31 downto 0);
    signal cycle_target : unsigned(3 downto 0);
    signal cycles_remaining : unsigned(11 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                div_counter <= (others => '0');
                cycles_remaining <= (others => '0');
                instr_done <= '0';
                
            elsif instr_start = '1' then
                -- Calculate total cycles for this instruction
                cycle_target <= unsigned(instr_cycles);
                if page_cross = '1' then
                    cycle_target <= unsigned(instr_cycles) + 1;
                end if;
                if branch_taken = '1' then
                    cycle_target <= unsigned(instr_cycles) + 1;
                end if;
                
                -- Calculate wait ticks
                if cycle_accurate = '1' then
                    cycles_remaining <= cycle_target * unsigned(clk_divider);
                else
                    cycles_remaining <= (others => '0');  -- No wait
                end if;
                instr_done <= '0';
                
            elsif cycles_remaining > 0 then
                cycles_remaining <= cycles_remaining - 1;
                
            else
                instr_done <= '1';
                cycle_count <= cycle_count + cycle_target;
            end if;
        end if;
    end process;
end architecture;
```

### 6.2 Accuracy Considerations

**Exact cycle matching:**
- Internal operations complete in 1-2 clocks
- We insert wait states to match 6502 timing
- From software's perspective, identical to real 6502

**Edge cases:**
- RMW instructions (INC, ASL, etc.): Read-modify-write at correct times
- DMA stealing cycles: Can be emulated if needed
- Bus contention: Simulated via additional wait states

---

## 7. Recommendations by Use Case

### 7.1 C64 Compatibility

```c
// Full compatibility for demos and games
task->timing.clkdiv = 49;        // 1.02 MHz
task->timing.mode = CYCLE_ACCURATE | SYNC_VBLANK | SYNC_HBLANK;
task->timing.region = NTSC;      // or PAL
```

### 7.2 NES Compatibility

```c
// Cycle-accurate for sprite 0 hit, etc.
task->timing.clkdiv = 27;        // 1.79 MHz
task->timing.mode = CYCLE_ACCURATE | SYNC_VBLANK;
task->timing.region = NTSC;
```

### 7.3 Apple II Compatibility

```c
// Most Apple II software less timing-sensitive
task->timing.clkdiv = 49;        // 1.02 MHz
task->timing.mode = CYCLE_ACCURATE;  // No video sync needed
```

### 7.4 SNES Compatibility (65816)

```c
// Instruction-accurate only, fast
task->timing.clkdiv = 0;         // Full speed
task->timing.mode = SYNC_VBLANK; // Just frame sync
// DMA and interrupt timing handled by SNES emulation layer
```

### 7.5 Modern Code

```c
// Maximum performance
task->timing.clkdiv = 0;
task->timing.mode = 0;           // No timing constraints
```

---

## 8. Summary

| Mode | Cycle Accurate | Speed Control | Use Case |
|------|----------------|---------------|----------|
| 6502 Emulation | Yes | Configurable (1-2 MHz) | Classic games, demos |
| 65816 Native | No | Full speed | SNES (with frame sync) |
| Native-32 | No | Full speed | Linux, modern apps |

**Key features:**
- Per-process clock divider
- Cycle-accurate execution when needed
- Raster line tracking for video sync
- Budget mode for "fast enough" compatibility
- Full speed for modern code

**This achieves the "Ultra" goal:** Run a C64 demo with cycle-perfect raster bars alongside a Linux terminal, each at their correct speed.

---

## 9. Open Questions

1. **Should we support "turbo" mode for 6502?** (2x, 4x speed for impatient users)
2. **DMA cycle stealing?** (C64 VIC-II steals cycles - do we emulate this?)
3. **Exact memory timing?** (Some protection schemes check memory access patterns)
4. **Multiple 6502 instances at different speeds?** (C64 at PAL, NES at NTSC simultaneously)

All are implementable; question is priority.
