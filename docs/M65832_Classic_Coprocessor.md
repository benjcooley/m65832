# M65832 Classic Coprocessor Architecture

**Two-Core Design for Authentic Classic System Emulation**

---

## 1. Overview

The M65832 SoC includes two interleaved processor cores:

| Core | Purpose | ISA | Execution |
|------|---------|-----|-----------|
| **M65832** | Linux, modern apps | Full M65832 (32-bit) | Time-sliced (configurable) |
| **6502** | Classic game code | Pure 6502 | Time-sliced (configurable) |

The time-slicing ratio is programmable and chosen per target system to preserve cycle accuracy.

---

## 2. Architecture

### 2.1 Block Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          M65832 SoC                                  │
│                                                                      │
│  ┌───────────────┐  ┌───────────────┐                               │
│  │    M65832     │  │     6502      │                               │
│  │    (Main)     │  │    (Game)     │                               │
│  │               │  │               │                               │
│  │ ┌───────────┐ │  │ ┌───────────┐ │                               │
│  │ │A X Y (32b)│ │  │ │A X Y (8b) │ │                               │
│  │ │S PC D B   │ │  │ │S PC P     │ │                               │
│  │ │R0-R63     │ │  │ │Pure 6502  │ │                               │
│  │ └───────────┘ │  │ └───────────┘ │                               │
│  │               │  │               │                               │
│  │  32-bit ALU   │  │  8-bit ALU    │                               │
│  │  Full decode  │  │  6502 decode  │                               │
│  │               │  │               │                               │
│  └───────┬───────┘  └───────┬───────┘                               │
│          │                  │                                       │
│          └──────────────────┘                                       │
│                             │                                        │
│                      ┌──────▼──────┐                                 │
│                      │Memory Arbiter│                                │
│                      └──────┬──────┘                                 │
│                             │                                        │
│      ┌──────────────────────┼──────────────────────┐                │
│      │                      │                      │                 │
│ ┌────▼────┐           ┌─────▼─────┐         ┌─────▼─────┐           │
│ │  Main   │           │  Shadow   │         │   I/O     │           │
│ │  RAM    │           │ Registers │         │  Write    │           │
│ │         │           │ + Log     │         │  FIFO     │           │
│ └─────────┘           └───────────┘         └───────────┘           │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 Each Core Has Dedicated Registers

No context switching needed - each core has its own complete register set:

```
M65832 Core:              6502 Core:
├── A (32-bit)            ├── A (8-bit)
├── X (32-bit)            ├── X (8-bit)
├── Y (32-bit)            ├── Y (8-bit)
├── S (32-bit)            ├── S (8-bit)
├── PC (32-bit)           ├── PC (16-bit)
├── P (16-bit)            ├── P (8-bit)
├── D (32-bit)            └── VBR (32-bit)
├── B (32-bit)
├── VBR (32-bit)
└── R0-R63 (32-bit each)

Hardware cost: ~400 flip-flops for extra cores (trivial on FPGA)
```

---

## 3. Interleaved Execution

### 3.1 Precise Clock Generation

Different classic systems require different exact CPU speeds:

| System | Exact Clock | Master/Target Ratio |
|--------|-------------|---------------------|
| C64 PAL | 985,248 Hz | 50.747... |
| C64 NTSC | 1,022,727 Hz | 48.889... |
| NES NTSC | 1,789,773 Hz | 27.936... |
| Apple II | 1,023,000 Hz | 48.876... |
| Atari 2600 | 1,193,182 Hz | 41.906... |

A simple integer divider (e.g., "every 49 cycles") cannot hit these precisely.

#### Accumulator-Based Fractional Divider

The hardware uses an accumulator to achieve exact frequencies:

```
Registers:
    TARGET_FREQ  ($FFFFF100): Target frequency in Hz (e.g., 1022727)
    MASTER_FREQ  ($FFFFF104): Master frequency in Hz (e.g., 50000000)
    ACCUM        (internal):  32-bit accumulator

Algorithm (hardware, every master cycle):
    accum += TARGET_FREQ
    if accum >= MASTER_FREQ:
        accum -= MASTER_FREQ
        trigger_6502_cycle = TRUE
    else:
        trigger_6502_cycle = FALSE
```

This is equivalent to Bresenham's line algorithm - it alternates between N and N+1 master cycles to achieve the exact average frequency.

#### Example: C64 NTSC (1,022,727 Hz)

```
Master: 50,000,000 Hz
Target: 1,022,727 Hz
Ratio:  48.889...

Cycle pattern (first 10 6502 cycles):
    6502 #1: after 49 master cycles
    6502 #2: after 49 master cycles
    6502 #3: after 49 master cycles
    6502 #4: after 49 master cycles
    6502 #5: after 49 master cycles
    6502 #6: after 49 master cycles
    6502 #7: after 49 master cycles
    6502 #8: after 48 master cycles  ← Catch-up!
    6502 #9: after 49 master cycles
    6502 #10: after 49 master cycles

Over 1 second: Exactly 1,022,727 6502 cycles
```

#### Configuration Registers

```
$FFFFF100: CLK_TARGET_LO    ; Target frequency low 16 bits
$FFFFF102: CLK_TARGET_HI    ; Target frequency high 16 bits
$FFFFF104: CLK_MASTER_LO    ; Master frequency low 16 bits
$FFFFF106: CLK_MASTER_HI    ; Master frequency high 16 bits
$FFFFF108: CLK_CONTROL      ; Bit 0: Enable, Bit 1: Reset accumulator
$FFFFF10A: CLK_ACCUM_LO     ; Accumulator (read-only, for debugging)
$FFFFF10C: CLK_ACCUM_HI
```

#### VHDL Implementation

```vhdl
-- Fractional clock divider for precise 6502 timing
entity clock_divider is
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        target_freq : in  std_logic_vector(31 downto 0);  -- e.g., 1022727
        master_freq : in  std_logic_vector(31 downto 0);  -- e.g., 50000000
        enable      : in  std_logic;
        tick_6502   : out std_logic  -- Pulse when 6502 should execute
    );
end entity;

architecture rtl of clock_divider is
    signal accumulator : unsigned(31 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            tick_6502 <= '0';  -- Default: no tick
            
            if reset = '1' then
                accumulator <= (others => '0');
            elsif enable = '1' then
                -- Add target frequency to accumulator
                accumulator <= accumulator + unsigned(target_freq);
                
                -- Check for overflow (time for a 6502 cycle)
                if accumulator >= unsigned(master_freq) then
                    accumulator <= accumulator - unsigned(master_freq);
                    tick_6502 <= '1';  -- Trigger 6502!
                end if;
            end if;
        end if;
    end process;
end architecture;
```

#### Setting Up C64 Mode (Software)

```asm
; Configure for C64 NTSC (1,022,727 Hz at 50 MHz master)
    LDA #$9F97          ; 1,022,727 low
    STA CLK_TARGET_LO
    LDA #$000F          ; 1,022,727 high
    STA CLK_TARGET_HI
    
    LDA #$4240          ; 50,000,000 low
    STA CLK_MASTER_LO
    LDA #$02FA          ; 50,000,000 high
    STA CLK_MASTER_HI
    
    LDA #$03            ; Enable + reset accumulator
    STA CLK_CONTROL
```

### 3.3 Interleaved Execution Model

When the accumulator triggers a 6502 cycle:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Variable-Length Window                            │
│                    (48-50 cycles depending on accumulator)           │
│                                                                      │
│  6502 trigger: Accumulator overflow → Run one 6502 instruction      │
│                │                                                     │
│                ├─► No I/O access?                                   │
│                │   └── M65832 runs until next trigger              │
│                │                                                     │
│                └─► I/O access detected?                             │
│                    └── IRQ handler computes response (if needed)   │
│                    └── M65832 gets remaining cycles                 │
│                                                                      │
│  Result: 6502 at EXACT target frequency, M65832 gets ~90%+ cycles   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

The interval between 6502 cycles varies (e.g., 48 or 49) but the **average** is precisely the target frequency.

### 3.4 Timing Examples

| 6502 Instruction | MMIO Work | MMIO Cycles | M65832 Cycles | M65832 % |
|------------------|-----------|-------------|---------------|----------|
| INX (no I/O) | None | 0 | 49 | 98% |
| STA $D020 (color) | Log write | 3 | 46 | 92% |
| STA $D000 (sprite) | Update + collision | 8 | 41 | 82% |
| LDA $D01E (collision) | Compute state | 15 | 34 | 68% |
| LDA $D012 (raster) | Read beam_y | 2 | 47 | 94% |

**Average game workload: ~90% of CPU available for Linux.**

---

## 4. Memory Architecture

### 5.1 Shadow Registers

Classic I/O registers exist in a "shadow" memory region accessible by all cores:

```
Physical Memory Map:
────────────────────────────────────────────────────────
$0010_0000 - $0010_FFFF   6502 visible memory (64KB)
$0011_0000 - $0011_00FF   Shadow: Zero page (fast access)
$0011_D000 - $0011_D02E   Shadow: VIC-II registers
$0011_D400 - $0011_D41C   Shadow: SID registers
$0011_DC00 - $0011_DCFF   Shadow: CIA #1 registers
$0011_DD00 - $0011_DDFF   Shadow: CIA #2 registers
$0011_F000 - $0011_F0FF   MMIO handler scratch area
────────────────────────────────────────────────────────

6502 address $D000 → Physical $0011_D000 (via VBR mapping)
MMIO handler sees the same address space as 6502
M65832 can also access for frame rendering
```

### 5.2 I/O Write FIFO

For cycle-accurate rendering, I/O writes are logged with timestamps:

```
FIFO Entry Format (64 bits):
┌────────────────────┬────────────────┬──────────┬──────────┐
│   Cycle Count      │    Address     │  Value   │ Reserved │
│     (32 bits)      │   (16 bits)    │ (8 bits) │ (8 bits) │
└────────────────────┴────────────────┴──────────┴──────────┘

FIFO Registers:
$FFFF_F400: STATUS    - Bit 0: Empty, Bit 1: Full, Bits 15:8: Count
$FFFF_F404: READ      - Pop and return next entry (64-bit)
$FFFF_F40C: CYCLE_RST - Write to reset cycle counter (do at frame start)

Usage:
1. 6502 writes to I/O register
2. Hardware logs {cycle, address, value} to FIFO
3. Hardware updates shadow register immediately
4. At VBlank, Linux process drains FIFO
5. Renderer replays writes in cycle order for accurate raster effects
```

---

## 5. I/O Flow

### 5.1 Write Path

```
6502 executes: STA $D020 (set border color)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Hardware detects I/O write ($D000-$DFFF range)                   │
│                                                                      │
│ 2. Value written to shadow register ($0011_D020)                    │
│                                                                      │
│ 3. Entry logged to FIFO: {cycle_count, $D020, value}                │
│                                                                      │
│ 4. Main CPU IRQ handler runs (if additional processing needed)     │
│    └── For color registers: No extra work                          │
│    └── For sprite position: Update bounding box                    │
│                                                                      │
│ 5. 6502 continues, M65832 resumes                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Read Path

```
6502 executes: LDA $D01E (read collision register)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Hardware detects I/O read ($D000-$DFFF range)                    │
│                                                                      │
│ 2. 6502 read cycle stretched (RDY signal held)                      │
│                                                                      │
│ 3. Main CPU IRQ handler triggered with address $D01E                │
│                                                                      │
│ 4. Main CPU computes current collision state:                       │
│    └── Reads sprite positions from shadow registers                 │
│    └── Reads current beam position                                  │
│    └── Checks overlaps                                              │
│    └── Writes result to $D01E                                       │
│    └── IRQ completion releases the 6502                             │
│                                                                      │
│ 5. Hardware releases 6502 (RDY asserted)                            │
│                                                                      │
│ 6. 6502 read completes with computed value                          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. MMIO Routines by Register

### 6.1 VIC-II Registers

| Register | On Write | On Read |
|----------|----------|---------|
| $D000-$D00F (sprite pos) | Update bounding box | Return shadow |
| $D010 (sprite X MSB) | Update bounding boxes | Return shadow |
| $D011 (control) | Log + update mode | Return shadow |
| $D012 (raster) | Set raster IRQ line | Compute: cycle/63 |
| $D015 (sprite enable) | Update collision mask | Return shadow |
| $D01E (sprite-sprite) | Clear register | **Compute collision** |
| $D01F (sprite-bg) | Clear register | **Compute collision** |
| $D020-$D02E (colors) | Log only | Return shadow |

### 6.2 SID Registers

| Register | On Write | On Read |
|----------|----------|---------|
| $D400-$D414 (voice) | Update oscillator state | N/A (write-only) |
| $D415-$D418 (filter) | Update filter params | N/A |
| $D419-$D41A (paddle) | N/A | Return ADC value |
| $D41B (osc 3) | N/A | Return LFSR (random) |
| $D41C (env 3) | N/A | Return envelope value |

### 6.3 CIA Registers

| Register | On Write | On Read |
|----------|----------|---------|
| $DC00 (port A) | Update output latches | Return input (joystick) |
| $DC04-$DC05 (timer A) | Set timer value | Return current count |
| $DC0D (interrupt) | Clear/set IRQ mask | Return pending IRQs |

---

## 7. Classic System Configurations

### 7.1 C64 Mode

```c
struct classic_config c64_ntsc = {
    .target_freq = 1022727,     // Exact C64 NTSC frequency
    .master_freq = 50000000,    // 50 MHz FPGA clock
    .scanlines = 263,           // NTSC
    .cycles_per_line = 65,
    .vic_base = 0x0011D000,
    .sid_base = 0x0011D400,
    .cia_base = 0x0011DC00,
};

struct classic_config c64_pal = {
    .target_freq = 985248,      // Exact C64 PAL frequency
    .master_freq = 50000000,
    .scanlines = 312,           // PAL
    .cycles_per_line = 63,
    .vic_base = 0x0011D000,
    .sid_base = 0x0011D400,
    .cia_base = 0x0011DC00,
};
```

### 7.2 NES Mode

```c
struct classic_config nes_ntsc = {
    .target_freq = 1789773,     // Exact NES NTSC frequency
    .master_freq = 50000000,
    .scanlines = 262,
    .cycles_per_line = 114,     // ~341 PPU dots / 3
    .ppu_base = 0x0011D000,
    .apu_base = 0x0011D400,
};

struct classic_config nes_pal = {
    .target_freq = 1662607,     // Exact NES PAL frequency
    .master_freq = 50000000,
    .scanlines = 312,
    .cycles_per_line = 106,
    .ppu_base = 0x0011D000,
    .apu_base = 0x0011D400,
};
```

### 7.3 Apple II Mode

```c
struct classic_config apple2 = {
    .target_freq = 1023000,     // Apple II frequency
    .master_freq = 50000000,
    .scanlines = 262,
    .cycles_per_line = 65,
    .soft_switch_base = 0x0011C000,
};
```

### 7.4 Atari 2600 Mode

```c
struct classic_config atari2600 = {
    .target_freq = 1193182,     // Atari 2600 NTSC frequency
    .master_freq = 50000000,
    .scanlines = 262,
    .cycles_per_line = 76,
    .tia_base = 0x0011D000,
    .riot_base = 0x0011D200,
};
```

### 7.5 Frequency Table

| System | Region | Exact Frequency | Master Cycles (avg) |
|--------|--------|-----------------|---------------------|
| C64 | NTSC | 1,022,727 Hz | 48.889 |
| C64 | PAL | 985,248 Hz | 50.747 |
| NES | NTSC | 1,789,773 Hz | 27.936 |
| NES | PAL | 1,662,607 Hz | 30.073 |
| Apple II | - | 1,023,000 Hz | 48.876 |
| Atari 2600 | NTSC | 1,193,182 Hz | 41.906 |
| Atari 800 | NTSC | 1,789,773 Hz | 27.936 |
| BBC Micro | - | 2,000,000 Hz | 25.000 |

---

## 8. Linux Integration

### 8.1 Video Renderer Process

```c
// Normal Linux process - runs at VBlank
void video_renderer(void) {
    while (running) {
        // Wait for VBlank interrupt
        wait_for_vblank();
        
        // Drain I/O write FIFO
        int log_count = 0;
        while (!(FIFO_STATUS & FIFO_EMPTY)) {
            log[log_count++] = FIFO_READ;
        }
        
        // Reset cycle counter for next frame
        FIFO_CYCLE_RST = 1;
        
        // Render frame with cycle-accurate register changes
        int log_idx = 0;
        for (int line = 0; line < 312; line++) {
            int line_end = (line + 1) * 63;
            
            // Apply writes that happened before this line
            while (log_idx < log_count && log[log_idx].cycle < line_end) {
                apply_vic_write(log[log_idx].addr, log[log_idx].value);
                log_idx++;
            }
            
            render_scanline(line, framebuffer);
        }
        
        flip_framebuffer();
    }
}
```

### 8.2 Audio Generator Process

```c
// Normal Linux process - runs on audio buffer low
void audio_generator(void) {
    while (running) {
        // Wait for audio buffer space
        wait_for_audio_space(64);  // 64 samples
        
        // Read current SID state from shadow registers
        sid_state_t state;
        read_sid_shadow(&state);
        
        // Generate samples
        int16_t samples[64];
        for (int i = 0; i < 64; i++) {
            samples[i] = sid_generate_sample(&state);
        }
        
        write_audio_buffer(samples, 64);
    }
}
```

---

## 9. Hardware Resource Summary

### 9.1 FPGA Utilization

| Component | LUTs | Flip-Flops | BRAM |
|-----------|------|------------|------|
| M65832 core | ~5,000 | ~2,000 | 2 |
| 6502 core | ~500 | ~100 | 0 |
| Memory arbiter | ~200 | ~50 | 0 |
| Shadow registers | ~100 | ~500 | 0 |
| I/O FIFO | ~100 | ~100 | 1 |
| **Total** | **~5,900** | **~2,750** | **3** |

**Fits easily in Xilinx Artix-7 35T** with room for peripherals.

### 9.2 Performance Summary

| Metric | Value |
|--------|-------|
| Master clock | 50 MHz |
| 6502 effective speed | Targeted per-system (configurable) |
| M65832 availability | 88-98% (depending on I/O) |
| Context switch overhead | 0 cycles (dedicated registers) |
| I/O FIFO depth | 256 entries |

---

## 10. Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                    M65832 Classic Coprocessor                        │
│                                                                      │
│  TWO CORES:                                                          │
│  ├── M65832: Linux, modern apps (32-bit, gets 90%+ of cycles)       │
│  └── 6502: Classic games (pure 6502, time-sliced)                   │
│                                                                      │
│  KEY FEATURES:                                                       │
│  ├── Zero context-switch overhead (dedicated registers)             │
│  ├── Cycle-accurate classic execution                                │
│  ├── IRQ-based MMIO handling for computed reads                     │
│  ├── Shadow registers + FIFO for renderer                           │
│  └── Linux runs concurrently at near-full speed                     │
│                                                                      │
│  ENABLES:                                                            │
│  ├── C64 game + Linux terminal simultaneously                       │
│  ├── NES game with cycle-perfect timing                             │
│  ├── Raster effects via write logging                               │
│  └── The "Ultra" vision: retro + modern unified                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

*Document Version: 1.0*  
*Architecture: M65832 with Classic Coprocessor*
