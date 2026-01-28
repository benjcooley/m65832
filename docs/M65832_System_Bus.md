# System Bus Architecture

## Overview

The Milo832 SoC uses a multi-master bus architecture that can accommodate the CPU, GPU, and additional peripherals. The design supports both a simple shared bus (DE2-115) and a crossbar interconnect (KV260).

## System Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            MILO832 SoC                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │ m65832  │ │ Milo832 │ │  DMA    │ │  Audio  │ │  Video  │ │  Debug  │   │
│  │  CPU    │ │  GPU    │ │ Engine  │ │  (SID?) │ │ Display │ │  Port   │   │
│  │         │ │         │ │         │ │         │ │         │ │         │   │
│  │ Master 0│ │Master 1 │ │Master 2 │ │Master 3 │ │Master 4 │ │Master 5 │   │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘   │
│       │          │          │          │          │          │            │
│       │          │          │          │          │          │            │
│  ═════╪══════════╪══════════╪══════════╪══════════╪══════════╪════════    │
│       │          │          │          │          │          │            │
│       │    ┌─────▼──────────▼──────────▼──────────▼──────────▼─────┐      │
│       │    │                   SYSTEM BUS                          │      │
│       │    │                                                        │      │
│       │    │  • Multi-master arbiter                               │      │
│       │    │  • Address decode                                      │      │
│       │    │  • Burst support                                       │      │
│       │    │  • Priority + fairness                                 │      │
│       │    └─────┬──────────┬──────────┬──────────┬──────────┬─────┘      │
│       │          │          │          │          │          │            │
│  ═════╪══════════╪══════════╪══════════╪══════════╪══════════╪════════    │
│       │          │          │          │          │          │            │
│  ┌────▼────┐┌────▼────┐┌────▼────┐┌────▼────┐┌────▼────┐┌────▼────┐      │
│  │  DDR    ││  Boot   ││  GPU    ││ Periph  ││  Timer  ││  IRQ    │      │
│  │ Memory  ││  ROM    ││  Regs   ││  I/O    ││ /WDT    ││  Ctrl   │      │
│  │         ││         ││         ││         ││         ││         │      │
│  │ Slave 0 ││ Slave 1 ││ Slave 2 ││ Slave 3 ││ Slave 4 ││ Slave 5 │      │
│  └─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Address Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SYSTEM ADDRESS MAP                                    │
├───────────────┬───────────────┬─────────────────────────────────────────────┤
│ Start         │ End           │ Device                                      │
├───────────────┼───────────────┼─────────────────────────────────────────────┤
│ 0x0000_0000   │ 0x0000_FFFF   │ Boot ROM (64 KB)                           │
│ 0x0001_0000   │ 0x001F_FFFF   │ DDR - CPU Code/Data (2 MB)                 │
│ 0x0020_0000   │ 0x0FFF_FFFF   │ DDR - Shared (GPU buffers, FB) (254 MB)    │
├───────────────┼───────────────┼─────────────────────────────────────────────┤
│ 0x1000_0000   │ 0x1000_0FFF   │ GPU Registers (4 KB)                       │
│ 0x1000_1000   │ 0x1000_1FFF   │ DMA Controller Registers (4 KB)            │
│ 0x1000_2000   │ 0x1000_2FFF   │ Audio Registers (4 KB)                     │
│ 0x1000_3000   │ 0x1000_3FFF   │ Video/Display Registers (4 KB)             │
│ 0x1000_4000   │ 0x1000_4FFF   │ Timer/Watchdog (4 KB)                      │
│ 0x1000_5000   │ 0x1000_5FFF   │ Interrupt Controller (4 KB)                │
│ 0x1000_6000   │ 0x1000_6FFF   │ UART (4 KB)                                │
│ 0x1000_7000   │ 0x1000_7FFF   │ SPI Controller (4 KB)                      │
│ 0x1000_8000   │ 0x1000_8FFF   │ I2C Controller (4 KB)                      │
│ 0x1000_9000   │ 0x1000_9FFF   │ GPIO (4 KB)                                │
│ 0x1000_A000   │ 0x1000_AFFF   │ SD Card Controller (4 KB)                  │
│ 0x1000_B000   │ 0x100F_FFFF   │ Reserved for expansion                     │
├───────────────┼───────────────┼─────────────────────────────────────────────┤
│ 0x1010_0000   │ 0x101F_FFFF   │ Debug Port / JTAG (1 MB)                   │
├───────────────┼───────────────┼─────────────────────────────────────────────┤
│ 0x2000_0000   │ 0x2FFF_FFFF   │ External peripheral expansion (256 MB)     │
└───────────────┴───────────────┴─────────────────────────────────────────────┘

Address decode:
  [31:28] = 0x0  → DDR/ROM (cacheable)
  [31:28] = 0x1  → Peripheral registers (uncached, MMIO)
  [31:28] = 0x2  → External expansion (directly memory-mapped)
```

## Bus Protocol

### Signal Definition

```vhdl
-- system_bus_pkg.vhd
package system_bus_pkg is

    constant BUS_ADDR_WIDTH : integer := 32;
    constant BUS_DATA_WIDTH : integer := 64;  -- 64-bit for DDR efficiency
    constant BUS_MASTERS    : integer := 6;
    constant BUS_SLAVES     : integer := 8;
    
    -- Master request
    type bus_master_req_t is record
        valid    : std_logic;
        write    : std_logic;
        addr     : std_logic_vector(31 downto 0);
        wdata    : std_logic_vector(63 downto 0);
        wstrb    : std_logic_vector(7 downto 0);   -- byte enables
        burst    : std_logic_vector(7 downto 0);   -- burst length (0=single)
        size     : std_logic_vector(2 downto 0);   -- 0=1B, 1=2B, 2=4B, 3=8B
        lock     : std_logic;                       -- atomic access
        prot     : std_logic_vector(2 downto 0);   -- privilege level
    end record;
    
    -- Master response
    type bus_master_resp_t is record
        ready    : std_logic;                       -- request accepted
        rvalid   : std_logic;                       -- read data valid
        rdata    : std_logic_vector(63 downto 0);
        error    : std_logic;                       -- bus error
        rlast    : std_logic;                       -- last beat of burst
    end record;
    
    -- Slave interface (directly connected, no arbitration needed)
    type bus_slave_req_t is record
        sel      : std_logic;                       -- this slave selected
        write    : std_logic;
        addr     : std_logic_vector(31 downto 0);
        wdata    : std_logic_vector(63 downto 0);
        wstrb    : std_logic_vector(7 downto 0);
        burst    : std_logic_vector(7 downto 0);
    end record;
    
    type bus_slave_resp_t is record
        ready    : std_logic;
        rvalid   : std_logic;
        rdata    : std_logic_vector(63 downto 0);
        error    : std_logic;
        rlast    : std_logic;
    end record;
    
    -- Arrays for multi-master/slave
    type master_req_array_t is array (0 to BUS_MASTERS-1) of bus_master_req_t;
    type master_resp_array_t is array (0 to BUS_MASTERS-1) of bus_master_resp_t;
    type slave_req_array_t is array (0 to BUS_SLAVES-1) of bus_slave_req_t;
    type slave_resp_array_t is array (0 to BUS_SLAVES-1) of bus_slave_resp_t;

end package;
```

## Arbiter Design

### Priority Configuration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MASTER PRIORITY TABLE                                 │
├─────────┬──────────┬────────────┬───────────────────────────────────────────┤
│ Master  │ ID       │ Priority   │ Notes                                     │
├─────────┼──────────┼────────────┼───────────────────────────────────────────┤
│ CPU     │ 0        │ Highest(0) │ Latency-critical, stalls on cache miss   │
│ GPU Rd  │ 1        │ High (1)   │ Texture/vertex fetch, can pipeline       │
│ GPU Wr  │ 2        │ Medium (2) │ Framebuffer writes, buffered             │
│ DMA     │ 3        │ Medium (2) │ Bulk transfers, not latency critical     │
│ Audio   │ 4        │ High (1)   │ Real-time, small bursts, can't stall     │
│ Display │ 5        │ Highest(0) │ Must not miss refresh, read-only         │
│ Debug   │ 6        │ Lowest (3) │ Only used during development             │
└─────────┴──────────┴────────────┴───────────────────────────────────────────┘

Priority 0 = Highest (wins immediately)
Priority 3 = Lowest (only when no higher priority pending)
```

### Arbitration Algorithm

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     TWO-LEVEL ARBITRATION                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Level 1: Priority Groups                                                   │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Group 0 (Highest): CPU, Display                                            │
│  Group 1 (High):    GPU Read, Audio                                         │
│  Group 2 (Medium):  GPU Write, DMA                                          │
│  Group 3 (Low):     Debug                                                   │
│                                                                              │
│  Level 2: Round-Robin within Group                                          │
│  ─────────────────────────────────────────────────────────────────────────  │
│  If multiple masters in same group request, use round-robin                 │
│                                                                              │
│  Fairness Rules:                                                            │
│  ─────────────────────────────────────────────────────────────────────────  │
│  1. Higher priority always wins over lower                                  │
│  2. Same priority: round-robin (last_granted rotates)                       │
│  3. Burst continuation: current master keeps bus until burst done           │
│  4. Starvation prevention: after N grants, force rotate (N=16)             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Arbiter State Machine

```
                         ┌──────────────┐
              ┌──────────│     IDLE     │◄────────────────┐
              │          └──────┬───────┘                 │
              │                 │ any request             │
              │                 ▼                         │
              │          ┌──────────────┐                 │
              │          │   ARBITRATE  │                 │
              │          │              │                 │
              │          │ Select winner│                 │
              │          │ by priority  │                 │
              │          └──────┬───────┘                 │
              │                 │                         │
              │                 ▼                         │
              │          ┌──────────────┐                 │
              │          │    GRANT     │                 │
     preempt  │          │              │                 │ burst done
     (higher  │          │ Route master │                 │ or single
     priority)│          │ to slave     │                 │
              │          └──────┬───────┘                 │
              │                 │                         │
              │                 ▼                         │
              │          ┌──────────────┐                 │
              └──────────│    BURST     │─────────────────┘
                         │              │
                         │ Continue     │
                         │ burst beats  │
                         └──────────────┘
```

## Bus Interconnect Implementation

### Option A: Shared Bus (DE2-115, simple)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SHARED BUS TOPOLOGY                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│     M0      M1      M2      M3      M4      M5                              │
│     │       │       │       │       │       │                               │
│     ▼       ▼       ▼       ▼       ▼       ▼                               │
│  ┌────────────────────────────────────────────────┐                         │
│  │                  ARBITER                        │                         │
│  │   • Priority encoder                           │                         │
│  │   • Grant register                             │                         │
│  │   • Fairness counter                           │                         │
│  └────────────────────────┬───────────────────────┘                         │
│                           │                                                  │
│                           ▼                                                  │
│  ┌────────────────────────────────────────────────┐                         │
│  │               SHARED BUS (muxed)               │                         │
│  │   addr[31:0], wdata[63:0], rdata[63:0]        │                         │
│  │   write, burst[7:0], ready, error              │                         │
│  └────────────────────────┬───────────────────────┘                         │
│                           │                                                  │
│                           ▼                                                  │
│  ┌────────────────────────────────────────────────┐                         │
│  │              ADDRESS DECODER                    │                         │
│  │   addr[31:28] → slave select                   │                         │
│  └────┬───────┬───────┬───────┬───────┬──────────┘                         │
│       │       │       │       │       │                                      │
│       ▼       ▼       ▼       ▼       ▼                                      │
│      S0      S1      S2      S3      S4     ...                             │
│     DDR     ROM    GPU_R  Periph  Timer                                     │
│                                                                              │
│  Pros: Simple, low area                                                     │
│  Cons: Only one transaction at a time                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Option B: Crossbar (KV260, high performance)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CROSSBAR TOPOLOGY                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│          S0(DDR)    S1(ROM)   S2(GPU)   S3(Periph)  S4(Timer)              │
│             │          │         │          │          │                    │
│     ┌───────┼──────────┼─────────┼──────────┼──────────┼───────┐           │
│     │       │          │         │          │          │       │           │
│ M0 ─┼───────●──────────●─────────●──────────●──────────●───────┼─ CPU      │
│     │       │          │         │          │          │       │           │
│ M1 ─┼───────●──────────○─────────●──────────○──────────○───────┼─ GPU Rd   │
│     │       │          │         │          │          │       │           │
│ M2 ─┼───────●──────────○─────────●──────────○──────────○───────┼─ GPU Wr   │
│     │       │          │         │          │          │       │           │
│ M3 ─┼───────●──────────○─────────○──────────○──────────○───────┼─ DMA      │
│     │       │          │         │          │          │       │           │
│ M4 ─┼───────●──────────○─────────○──────────○──────────○───────┼─ Audio    │
│     │       │          │         │          │          │       │           │
│ M5 ─┼───────●──────────○─────────○──────────○──────────○───────┼─ Display  │
│     │       │          │         │          │          │       │           │
│     └───────┼──────────┼─────────┼──────────┼──────────┼───────┘           │
│             │          │         │          │          │                    │
│             ▼          ▼         ▼          ▼          ▼                    │
│          Per-slave arbiters (only for slaves with multiple masters)        │
│                                                                              │
│  ● = Path exists (master can access slave)                                  │
│  ○ = No path (master never accesses this slave)                            │
│                                                                              │
│  Parallel transactions possible:                                            │
│    CPU → Periph  WHILE  GPU → DDR  WHILE  Display → DDR                    │
│                                                                              │
│  DDR arbiter needed (multiple masters access DDR)                          │
│  Periph: only CPU accesses, no arbiter needed                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Crossbar Arbiter (Per-Slave)

For slaves that multiple masters can access (mainly DDR):

```vhdl
entity slave_arbiter is
    generic (
        NUM_MASTERS : integer := 6;
        PRIORITIES  : integer_vector := (0, 1, 2, 2, 1, 0)  -- per master
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        
        -- From masters (directly connected)
        master_req  : in  master_req_array_t;
        master_resp : out master_resp_array_t;
        
        -- To slave
        slave_req   : out bus_slave_req_t;
        slave_resp  : in  bus_slave_resp_t
    );
end entity;
```

### Arbitration Logic

```vhdl
-- Priority-based selection with round-robin tie-breaking
process(clk)
    variable pending : std_logic_vector(NUM_MASTERS-1 downto 0);
    variable winner  : integer range 0 to NUM_MASTERS-1;
    variable best_pri: integer;
begin
    if rising_edge(clk) then
        if state = IDLE then
            -- Find highest priority pending request
            best_pri := 99;
            winner := 0;
            
            for i in 0 to NUM_MASTERS-1 loop
                pending(i) := master_req(i).valid;
                
                if master_req(i).valid = '1' then
                    if PRIORITIES(i) < best_pri then
                        -- Strictly higher priority
                        best_pri := PRIORITIES(i);
                        winner := i;
                    elsif PRIORITIES(i) = best_pri then
                        -- Same priority: check round-robin
                        if i > last_granted and winner <= last_granted then
                            winner := i;  -- Round-robin favors next in sequence
                        end if;
                    end if;
                end if;
            end loop;
            
            if pending /= (pending'range => '0') then
                grant <= winner;
                last_granted <= winner;
                state <= ACTIVE;
            end if;
            
        elsif state = ACTIVE then
            -- Continue until burst completes
            if slave_resp.ready = '1' and slave_resp.rlast = '1' then
                state <= IDLE;
            end if;
        end if;
    end if;
end process;
```

## Quality of Service (QoS)

For real-time masters (Audio, Display), we need guaranteed bandwidth:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        QoS CONFIGURATION                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Display Controller:                                                        │
│  ─────────────────────────────────────────────────────────────────────────  │
│    Resolution: 640×480 @ 60Hz                                               │
│    Pixel clock: 25.175 MHz                                                  │
│    Bandwidth: 640 × 480 × 4 bytes × 60 = 73.7 MB/s                         │
│    Burst size: 64 pixels = 256 bytes                                        │
│    Bursts per frame: 4800                                                   │
│    Bursts per line: 10 (with FIFO buffering)                               │
│    Max latency: 1 line time = 31.7 µs → need burst every 3.2 µs           │
│                                                                              │
│  Audio (48 kHz stereo, 16-bit):                                            │
│  ─────────────────────────────────────────────────────────────────────────  │
│    Bandwidth: 48000 × 2 × 2 = 192 KB/s (negligible)                        │
│    Burst: 256 samples = 1 KB every 5.3 ms                                  │
│    Very relaxed timing, just needs occasional access                        │
│                                                                              │
│  QoS Mechanism:                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│    Each real-time master has a "credit" counter                            │
│    Credits accumulate at a configured rate                                  │
│    When credits > threshold, master gets elevated priority                 │
│                                                                              │
│    Display: 1 credit per 100 cycles, threshold = 10                        │
│             → guaranteed burst every 1000 cycles (~10 µs at 100 MHz)       │
│             → 3× margin over requirement                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Adding a New Master

To add a new peripheral (e.g., Ethernet MAC):

```vhdl
-- 1. Add to master enumeration
constant MASTER_ETHERNET : integer := 6;

-- 2. Configure priority
constant MASTER_PRIORITIES : integer_vector(0 to 6) := (
    0,  -- CPU
    1,  -- GPU Read
    2,  -- GPU Write
    2,  -- DMA
    1,  -- Audio
    0,  -- Display
    2   -- Ethernet (NEW)
);

-- 3. Connect to crossbar
crossbar_master_req(MASTER_ETHERNET) <= ethernet_bus_req;
ethernet_bus_resp <= crossbar_master_resp(MASTER_ETHERNET);

-- 4. Configure which slaves it can access
constant ETHERNET_SLAVE_MASK : std_logic_vector(7 downto 0) := "00000001";
-- Only DDR (slave 0)
```

## Resource Usage

### Shared Bus (DE2-115)

| Component | LEs | BRAM |
|-----------|-----|------|
| Arbiter (6 masters) | 500 | 0 |
| Address decoder | 200 | 0 |
| Data muxes (64-bit) | 800 | 0 |
| Response routing | 300 | 0 |
| **Total** | **1,800** | **0** |

### Crossbar (KV260)

| Component | LUTs | BRAM |
|-----------|------|------|
| Per-slave arbiters (×8) | 2,400 | 0 |
| Crossbar switches | 3,000 | 0 |
| Address decoders | 400 | 0 |
| QoS counters | 200 | 0 |
| **Total** | **6,000** | **0** |

## Example: Adding Audio Chip

```vhdl
-- audio_interface.vhd
entity audio_interface is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        
        -- Bus master interface (to fetch samples from DDR)
        bus_req     : out bus_master_req_t;
        bus_resp    : in  bus_master_resp_t;
        
        -- Bus slave interface (CPU writes registers)
        reg_req     : in  bus_slave_req_t;
        reg_resp    : out bus_slave_resp_t;
        
        -- Audio output (I2S or PWM)
        audio_left  : out std_logic_vector(15 downto 0);
        audio_right : out std_logic_vector(15 downto 0);
        audio_valid : out std_logic
    );
end entity;

-- The audio chip:
-- 1. CPU writes buffer address and length to registers (slave interface)
-- 2. Audio DMA fetches samples from DDR (master interface)
-- 3. Outputs samples at 48 kHz
```

## Interrupt Routing

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        INTERRUPT CONTROLLER                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  IRQ Sources:                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ IRQ 0  │ GPU frame complete                                         │   │
│  │ IRQ 1  │ GPU command buffer empty                                   │   │
│  │ IRQ 2  │ DMA transfer complete                                      │   │
│  │ IRQ 3  │ Audio buffer low                                           │   │
│  │ IRQ 4  │ Display vsync                                              │   │
│  │ IRQ 5  │ Timer 0                                                    │   │
│  │ IRQ 6  │ Timer 1                                                    │   │
│  │ IRQ 7  │ UART RX ready                                              │   │
│  │ IRQ 8  │ SPI complete                                               │   │
│  │ IRQ 9  │ I2C complete                                               │   │
│  │ IRQ 10 │ GPIO edge detected                                         │   │
│  │ IRQ 11 │ SD card ready                                              │   │
│  │ IRQ 12-15 │ Reserved                                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  Registers:                                                                 │
│    IRQ_STATUS  [15:0] - Current interrupt status (read-only)               │
│    IRQ_ENABLE  [15:0] - Interrupt enable mask                              │
│    IRQ_PENDING [15:0] - STATUS & ENABLE (read-only)                        │
│    IRQ_CLEAR   [15:0] - Write 1 to clear edge-triggered IRQs               │
│    IRQ_PRIORITY[3:0]  - Priority of current highest pending               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
