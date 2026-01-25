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
├── D (32-bit)            ├── VBR (32-bit)
├── B (32-bit)            └── COMPAT (8-bit)
├── VBR (32-bit)
└── R0-R63 (32-bit each)

Hardware cost: ~400 flip-flops for extra cores (trivial on FPGA)
```

---

## 3. 6502 Compatibility

### 3.1 Target Systems

#### Must-Support Systems
- NES (Ricoh 2A03/2A07)
- Commodore 64 (6510/8500/8502)
- Apple II / IIe / IIc (6502/65C02)
- Atari 2600 family (6507)
- Atari 8-bit computers (6502C)

#### Should-Support Arcade Families (6502-based)
- Atari vector/early raster boards (Asteroids, Tempest, Centipede, Missile Command)
- Williams-era 6502 boards where applicable

#### Not Targeted
- Embedded/post-1990 variants
- Simplified or niche derivatives not used by notable systems

### 3.2 Variant Differences

| Variant | Decimal Mode | JMP (ind) Bug | Extra Opcodes |
|---------|--------------|---------------|---------------|
| NMOS 6502 (C64/Atari/Apple II/2600) | Supported | Preserved | Undocumented available |
| Ricoh 2A03/2A07 (NES) | **Disabled** | Preserved | None |
| WDC 65C02 (Apple IIe/IIc) | Supported | **Fixed** | 65C02 extensions |

### 3.3 Compatibility Control Register (COMPAT)

The `COMPAT[7:0]` register is stored with the 6502 coprocessor state and controls CPU variant behavior:

| Bit | Name | Description |
|-----|------|-------------|
| 0 | `DECIMAL_EN` | 1 = Enable BCD in ADC/SBC, 0 = Force binary (NES mode) |
| 1 | `CMOS65C02_EN` | 1 = Enable 65C02 instruction extensions |
| 2 | `NMOS_ILLEGAL_EN` | 1 = Enable undocumented NMOS opcodes |
| 7:3 | Reserved | Reserved for future use |

#### Default System Profiles

```asm
; NES Profile (Ricoh 2A03)
COMPAT_NES      = $00       ; DECIMAL_EN=0, CMOS65C02_EN=0, NMOS_ILLEGAL_EN=0

; NMOS 6502 Profile (C64, Atari)
COMPAT_NMOS     = $01       ; DECIMAL_EN=1, CMOS65C02_EN=0, NMOS_ILLEGAL_EN=0

; NMOS with Illegals (C64 demo scene)
COMPAT_NMOS_ILL = $05       ; DECIMAL_EN=1, CMOS65C02_EN=0, NMOS_ILLEGAL_EN=1

; Apple IIe/IIc Profile (65C02)
COMPAT_65C02    = $03       ; DECIMAL_EN=1, CMOS65C02_EN=1, NMOS_ILLEGAL_EN=0
```

### 3.4 Implemented 65C02 Extensions (CMOS65C02_EN=1)

| Opcode | Instruction | Description |
|--------|-------------|-------------|
| $80 | BRA rel | Branch always |
| $DA | PHX | Push X |
| $FA | PLX | Pull X |
| $5A | PHY | Push Y |
| $7A | PLY | Pull Y |
| $64 | STZ zp | Store zero to zero page |
| $74 | STZ zp,X | Store zero to zero page indexed |
| $9C | STZ abs | Store zero to absolute |
| $9E | STZ abs,X | Store zero to absolute indexed |
| $89 | BIT #imm | Bit test immediate |
| $34 | BIT zp,X | Bit test zero page indexed |
| $3C | BIT abs,X | Bit test absolute indexed |
| $04 | TSB zp | Test and set bits (zero page) |
| $0C | TSB abs | Test and set bits (absolute) |
| $14 | TRB zp | Test and reset bits (zero page) |
| $1C | TRB abs | Test and reset bits (absolute) |
| $7C | JMP (abs,X) | Jump indirect indexed |
| $1A | INC A | Increment accumulator |
| $3A | DEC A | Decrement accumulator |
| $12 | ORA (zp) | OR with accumulator (zp indirect) |
| $32 | AND (zp) | AND with accumulator (zp indirect) |
| $52 | EOR (zp) | XOR with accumulator (zp indirect) |
| $72 | ADC (zp) | Add with carry (zp indirect) |
| $92 | STA (zp) | Store accumulator (zp indirect) |
| $B2 | LDA (zp) | Load accumulator (zp indirect) |
| $D2 | CMP (zp) | Compare (zp indirect) |
| $F2 | SBC (zp) | Subtract with carry (zp indirect) |

### 3.5 Implemented Undocumented NMOS Opcodes (NMOS_ILLEGAL_EN=1)

| Opcode(s) | Instruction | Description |
|-----------|-------------|-------------|
| $A7,$B7,$AF,$BF,$A3,$B3,$AB | LAX | Load A and X |
| $87,$97,$8F,$83 | SAX | Store A AND X |
| $C7,$D7,$CF,$DF,$DB,$C3,$D3 | DCP | Decrement and compare |
| $E7,$F7,$EF,$FF,$FB,$E3,$F3 | ISC/ISB | Increment and subtract |
| $07,$17,$0F,$1F,$1B,$03,$13 | SLO | Shift left and OR |
| $27,$37,$2F,$3F,$3B,$23,$33 | RLA | Rotate left and AND |
| $47,$57,$4F,$5F,$5B,$43,$53 | SRE | Shift right and XOR |
| $67,$77,$6F,$7F,$7B,$63,$73 | RRA | Rotate right and ADC |
| $0B,$2B | ANC | AND with carry out |
| $4B | ALR | AND then LSR |
| $6B | ARR | AND then ROR |
| $CB | SBX/AXS | (A AND X) - imm → X |

---

## 4. Interleaved Execution

### 4.1 Precise Clock Generation

Different classic systems require different exact CPU speeds:

| System | Exact Clock | Master/Target Ratio |
|--------|-------------|---------------------|
| C64 PAL | 985,248 Hz | 50.747... |
| C64 NTSC | 1,022,727 Hz | 48.889... |
| NES NTSC | 1,789,773 Hz | 27.936... |
| NES PAL | 1,662,607 Hz | 30.073... |
| Apple II | 1,023,000 Hz | 48.876... |
| Atari 2600 | 1,193,182 Hz | 41.906... |
| Atari 800 | 1,789,773 Hz | 27.936... |
| BBC Micro | 2,000,000 Hz | 25.000... |

A simple integer divider (e.g., "every 49 cycles") cannot hit these precisely.

#### Accumulator-Based Fractional Divider

The hardware uses an accumulator to achieve exact frequencies (Bresenham-style):

```
Registers:
    TARGET_FREQ  : Target frequency in Hz (e.g., 1022727)
    MASTER_FREQ  : Master frequency in Hz (e.g., 50000000)
    ACCUM        : 32-bit accumulator (internal)

Algorithm (hardware, every master cycle):
    accum += TARGET_FREQ
    if accum >= MASTER_FREQ:
        accum -= MASTER_FREQ
        trigger_6502_cycle = TRUE
    else:
        trigger_6502_cycle = FALSE
```

This alternates between N and N+1 master cycles to achieve the exact average frequency.

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

### 4.2 Beam Position Tracking

The interleaver tracks beam position for raster-accurate emulation. Current RTL uses hardcoded defaults:

```vhdl
-- From m65832_interleave.vhd (lines 91-92)
constant CYCLES_PER_LINE : unsigned(9 downto 0) := to_unsigned(63, 10);   -- C64 PAL default
constant LINES_PER_FRAME : unsigned(9 downto 0) := to_unsigned(312, 10);  -- C64 PAL default
```

> **TODO:** These should be made configurable via input ports for multi-system support.

### 4.3 Coprocessor Top-Level Interface

The coprocessor system is configured via port signals on `M65832_Coprocessor_Top`:

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| `TARGET_FREQ` | 32 | Input | 6502 target frequency in Hz |
| `MASTER_FREQ` | 32 | Input | Master clock frequency in Hz |
| `ENABLE` | 1 | Input | Enable coprocessor execution |
| `VBR_IN` | 32 | Input | Virtual base register value |
| `VBR_LOAD` | 1 | Input | Load VBR strobe |
| `COMPAT_IN` | 8 | Input | Compatibility mode bits |
| `COMPAT_LOAD` | 1 | Input | Load COMPAT strobe |
| `COMPAT_OUT` | 8 | Output | Current COMPAT value |

#### Setting Up C64 Mode (Software Example)

```asm
; Configure for C64 NTSC (1,022,727 Hz at 50 MHz master)
; Assumes memory-mapped control interface

    ; Set target frequency = 1,022,727 ($000F9F97)
    LDA #$9F97
    STA COPROC_TARGET_LO
    LDA #$000F
    STA COPROC_TARGET_HI
    
    ; Set master frequency = 50,000,000 ($02FA4240)
    LDA #$4240
    STA COPROC_MASTER_LO
    LDA #$02FA
    STA COPROC_MASTER_HI
    
    ; Set VBR = $00100000 (6502 memory window)
    LDA #$00100000
    STA COPROC_VBR
    
    ; Set COMPAT = $05 (DECIMAL_EN=1, NMOS_ILLEGAL_EN=1 for C64 demos)
    LDA #$05
    STA COPROC_COMPAT
    
    ; Enable coprocessor
    LDA #$01
    STA COPROC_ENABLE
```

### 4.4 Interleaved Execution Model

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

### 4.5 Timing Examples

| 6502 Instruction | MMIO Work | MMIO Cycles | M65832 Cycles | M65832 % |
|------------------|-----------|-------------|---------------|----------|
| INX (no I/O) | None | 0 | 49 | 98% |
| STA $D020 (color) | Log write | 3 | 46 | 92% |
| STA $D000 (sprite) | Update + collision | 8 | 41 | 82% |
| LDA $D01E (collision) | Compute state | 15 | 34 | 68% |
| LDA $D012 (raster) | Read beam_y | 2 | 47 | 94% |

**Average game workload: ~90% of CPU available for Linux.**

---

## 5. Memory Architecture

### 5.1 Address Translation (VBR)

The 6502 sees a 64KB address space ($0000-$FFFF). The Virtual Base Register (VBR) translates these to physical addresses:

```
Physical Address = VBR + 6502 Address

Example: VBR = $00100000
    6502 $0000 → Physical $00100000
    6502 $D000 → Physical $0010D000
    6502 $FFFF → Physical $0010FFFF
```

The address translation is implemented in hardware:

```vhdl
-- From m65832_6502_coprocessor.vhd
ADDR_VA <= std_logic_vector(unsigned(vbr_reg) + unsigned(x"0000" & addr_16));
```

Interrupt vectors are pre-computed for fast access:

```vhdl
-- From m65832_6502_context.vhd
VEC_NMI   <= std_logic_vector(unsigned(VBRr) + x"0000FFFA");
VEC_RESET <= std_logic_vector(unsigned(VBRr) + x"0000FFFC");
VEC_IRQ   <= std_logic_vector(unsigned(VBRr) + x"0000FFFE");
```

### 5.2 Shadow I/O Registers

The Shadow I/O module intercepts accesses to classic I/O ranges and provides:
- Immediate shadow register storage
- Cycle-accurate write logging (FIFO)
- IRQ-based computed reads

**Configuration:** 4 banks of 64 registers each, with configurable base addresses:

| Bank | Default Use | Base Address Signal |
|------|-------------|---------------------|
| 0 | VIC-II ($D000-$D03F) | `BANK0_BASE` |
| 1 | SID ($D400-$D43F) | `BANK1_BASE` |
| 2 | CIA1 ($DC00-$DC3F) | `BANK2_BASE` |
| 3 | CIA2 ($DD00-$DD3F) | `BANK3_BASE` |

### 5.3 I/O Write FIFO

For cycle-accurate rendering, I/O writes are logged with timestamps:

```
FIFO Entry Format (64 bits, packed as shown):
┌──────────────┬──────────────┬────────┬────────┬──────────┬──────────┐
│   Reserved   │ Frame Number │ Cycle  │  Bank  │   Reg    │  Value   │
│  (12 bits)   │  (16 bits)   │(20 bit)│(2 bits)│ (6 bits) │ (8 bits) │
└──────────────┴──────────────┴────────┴────────┴──────────┴──────────┘
 Bits: [63:52]    [51:36]       [35:16]  [15:14]   [13:8]     [7:0]

FIFO Signals (directly accessible via hardware interface):
    FIFO_RD      : Read strobe (pop entry)
    FIFO_EMPTY   : FIFO empty flag
    FIFO_DATA    : 64-bit entry data
    FIFO_COUNT   : Number of entries in FIFO (9 bits, max 256)
    FIFO_OVERFLOW: Overflow indicator

Usage:
1. 6502 writes to I/O register
2. Hardware logs {frame, cycle, bank, reg, value} to FIFO
3. Hardware updates shadow register immediately
4. At VBlank, Linux process drains FIFO
5. Renderer replays writes in cycle order for accurate raster effects
```

> **Note:** Current RTL (`m65832_shadow_io.vhd`) declares a 48-bit FIFO but packs 52 bits of data.
> This should be corrected to 64-bit entries for proper alignment and headroom.

---

## 6. I/O Flow

### 6.1 Write Path

```
6502 executes: STA $D020 (set border color)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Hardware detects I/O write (address matches BANKn_BASE range)    │
│                                                                      │
│ 2. Value written to shadow register                                 │
│                                                                      │
│ 3. Entry logged to FIFO: {frame, cycle, bank, reg, value}           │
│                                                                      │
│ 4. IO_ACK asserted immediately (6502 continues)                     │
│                                                                      │
│ 5. Main CPU IRQ triggered if additional processing needed           │
│    └── For color registers: No extra work                          │
│    └── For sprite position: Update bounding box                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 Read Path

Some registers return computed values (e.g., collision detection, raster position). These trigger an IRQ to the main CPU:

```
6502 executes: LDA $D01E (read collision register)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Hardware detects I/O read (address in service mask)              │
│                                                                      │
│ 2. 6502 stalled (IO_ACK held low)                                   │
│                                                                      │
│ 3. Main CPU IRQ raised (IRQ_REQ=1, IRQ_ADDR=$D01E)                  │
│                                                                      │
│ 4. Main CPU computes current collision state:                       │
│    └── Reads sprite positions from shadow registers                 │
│    └── Reads current beam position                                  │
│    └── Checks overlaps                                              │
│    └── Writes result via IRQ_DATA, asserts IRQ_VALID                │
│                                                                      │
│ 5. Hardware releases 6502 (IO_ACK asserted)                         │
│                                                                      │
│ 6. 6502 read completes with computed value                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Registers Requiring Computed Response

The following registers trigger an IRQ on read (service mask):

**VIC-II (Bank 0):**
| Register | Address | Read Behavior |
|----------|---------|---------------|
| $D011 | Control (bit 7 = raster MSB) | Compute from beam position |
| $D012 | Raster counter | Compute from cycle count |
| $D019 | Interrupt register | Compute pending IRQs |
| $D01E | Sprite-sprite collision | Compute from sprite positions |
| $D01F | Sprite-background collision | Compute from sprite/char data |

**CIA1 (Bank 2):**
| Register | Address | Read Behavior |
|----------|---------|---------------|
| $DC01 | Port B (keyboard column) | Return current key state |
| $DC04-$DC05 | Timer A | Return current count |
| $DC06-$DC07 | Timer B | Return current count |
| $DC0D | Interrupt control | Return pending IRQs |

**CIA2 (Bank 3):**
| Register | Address | Read Behavior |
|----------|---------|---------------|
| $DD04-$DD05 | Timer A | Return current count |
| $DD06-$DD07 | Timer B | Return current count |
| $DD0D | Interrupt control | Return pending IRQs |

---

## 7. Classic System Configurations

### 7.1 C64 Mode

```c
struct classic_config c64_ntsc = {
    .target_freq = 1022727,     // Exact C64 NTSC frequency
    .master_freq = 50000000,    // 50 MHz FPGA clock
    .compat = 0x05,             // DECIMAL_EN=1, NMOS_ILLEGAL_EN=1
    .scanlines = 263,           // NTSC
    .cycles_per_line = 65,
    .bank0_base = 0xD000,       // VIC-II
    .bank1_base = 0xD400,       // SID
    .bank2_base = 0xDC00,       // CIA1
    .bank3_base = 0xDD00,       // CIA2
};

struct classic_config c64_pal = {
    .target_freq = 985248,      // Exact C64 PAL frequency
    .master_freq = 50000000,
    .compat = 0x05,             // DECIMAL_EN=1, NMOS_ILLEGAL_EN=1
    .scanlines = 312,           // PAL
    .cycles_per_line = 63,
    .bank0_base = 0xD000,
    .bank1_base = 0xD400,
    .bank2_base = 0xDC00,
    .bank3_base = 0xDD00,
};
```

### 7.2 NES Mode

```c
struct classic_config nes_ntsc = {
    .target_freq = 1789773,     // Exact NES NTSC frequency
    .master_freq = 50000000,
    .compat = 0x00,             // DECIMAL_EN=0 (Ricoh 2A03)
    .scanlines = 262,
    .cycles_per_line = 114,     // ~341 PPU dots / 3
    .bank0_base = 0x2000,       // PPU registers
    .bank1_base = 0x4000,       // APU/IO registers
    .bank2_base = 0x4014,       // OAM DMA
    .bank3_base = 0x4016,       // Controller
};

struct classic_config nes_pal = {
    .target_freq = 1662607,     // Exact NES PAL frequency
    .master_freq = 50000000,
    .compat = 0x00,             // DECIMAL_EN=0
    .scanlines = 312,
    .cycles_per_line = 106,
    .bank0_base = 0x2000,
    .bank1_base = 0x4000,
    .bank2_base = 0x4014,
    .bank3_base = 0x4016,
};
```

### 7.3 Apple II Mode

```c
struct classic_config apple2 = {
    .target_freq = 1023000,     // Apple II frequency
    .master_freq = 50000000,
    .compat = 0x01,             // DECIMAL_EN=1, standard 6502
    .scanlines = 262,
    .cycles_per_line = 65,
    .bank0_base = 0xC000,       // Soft switches
    .bank1_base = 0xC080,       // Language card
    .bank2_base = 0xC100,       // Slot ROM
    .bank3_base = 0xCFFF,       // Expansion ROM
};

struct classic_config apple2e = {
    .target_freq = 1023000,
    .master_freq = 50000000,
    .compat = 0x03,             // DECIMAL_EN=1, CMOS65C02_EN=1
    .scanlines = 262,
    .cycles_per_line = 65,
    .bank0_base = 0xC000,
    .bank1_base = 0xC080,
    .bank2_base = 0xC100,
    .bank3_base = 0xCFFF,
};
```

### 7.4 Atari 2600 Mode

```c
struct classic_config atari2600 = {
    .target_freq = 1193182,     // Atari 2600 NTSC frequency
    .master_freq = 50000000,
    .compat = 0x01,             // DECIMAL_EN=1
    .scanlines = 262,
    .cycles_per_line = 76,
    .bank0_base = 0x0000,       // TIA (mirrored)
    .bank1_base = 0x0280,       // RIOT
    .bank2_base = 0x0000,       // Not used
    .bank3_base = 0x0000,       // Not used
};
```

---

## 8. Linux Integration

### 8.1 Video Renderer Process

```c
// Normal Linux process - runs at VBlank
void video_renderer(void) {
    uint64_t log[256];
    
    while (running) {
        // Wait for VBlank interrupt
        wait_for_vblank();
        
        // Drain I/O write FIFO
        int log_count = 0;
        while (!fifo_empty()) {
            log[log_count++] = fifo_read();  // 64-bit entry
        }
        
        // Render frame with cycle-accurate register changes
        int log_idx = 0;
        for (int line = 0; line < 312; line++) {
            int line_end = (line + 1) * 63;  // C64 PAL: 63 cycles/line
            
            // Apply writes that happened before this line
            while (log_idx < log_count) {
                uint64_t entry = log[log_idx];
                
                // Extract fields per FIFO format
                int cycle = (entry >> 16) & 0xFFFFF;   // bits[35:16]
                if (cycle >= line_end) break;
                
                int bank  = (entry >> 14) & 0x3;       // bits[15:14]
                int reg   = (entry >> 8) & 0x3F;       // bits[13:8]
                int value = entry & 0xFF;              // bits[7:0]
                
                apply_io_write(bank, reg, value);
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
        for (int i = 0; i < 25; i++) {
            state.regs[i] = read_shadow(BANK_SID, i);
        }
        
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
| 6502 core (mx65) | ~500 | ~100 | 0 |
| Memory arbiter | ~200 | ~50 | 0 |
| Shadow registers (4×64) | ~100 | ~2,048 | 0 |
| I/O FIFO (256 entries) | ~100 | ~100 | 1 |
| Interleaver | ~100 | ~100 | 0 |
| **Total** | **~6,000** | **~4,400** | **3** |

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
│  └── 6502: Classic games (pure 6502/65C02, time-sliced)             │
│                                                                      │
│  COMPATIBILITY:                                                      │
│  ├── NMOS 6502 with optional BCD (C64, Atari, Apple II)             │
│  ├── Ricoh 2A03 mode (NES - no BCD)                                 │
│  ├── 65C02 extensions (Apple IIe/IIc)                               │
│  └── Undocumented NMOS opcodes (C64 demo scene)                     │
│                                                                      │
│  KEY FEATURES:                                                       │
│  ├── Zero context-switch overhead (dedicated registers)             │
│  ├── Cycle-accurate classic execution (fractional divider)          │
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

*Document Version: 2.1*  
*Architecture: M65832 with Classic Coprocessor*  
*Verified against RTL: m65832_6502_coprocessor.vhd, m65832_interleave.vhd, m65832_shadow_io.vhd, mx65.vhd*

**RTL Issues Noted:**
- `m65832_shadow_io.vhd`: FIFO declared as 48-bit but packs 52 bits (should be 64-bit)
- `m65832_interleave.vhd`: Beam timing constants hardcoded to C64 PAL (should be configurable)
