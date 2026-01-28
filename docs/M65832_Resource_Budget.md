# FPGA Resource Budget: m65832 CPU + Milo832 GPU

## Overview

Both the m65832 CPU and Milo832 GPU must fit on a single FPGA. This document provides resource allocation for the DE2-115 (budget) and KV260 (performance) configurations.

## Target FPGA Resources

| Resource | DE2-115 (Cyclone IV) | KV260 (Zynq UltraScale+) |
|----------|---------------------|--------------------------|
| Logic Elements/LUTs | 114,480 LEs | 256,200 LUTs |
| Block RAM | 432 M9K (486 KB) | 144 BRAM36 (648 KB) |
| UltraRAM | - | 64 URAM (2,304 KB) |
| DSP/Multipliers | 266 (18×18) | 1,248 DSP48 |
| PLLs/MMCMs | 4 | 8 |

## Resource Allocation Strategy

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FPGA RESOURCE PARTITIONING                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                      SHARED RESOURCES                        │    │
│  │  • Memory Controller (DDR/SDRAM)                            │    │
│  │  • System Bus / Interconnect                                │    │
│  │  • Clock/Reset Generation                                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│            ┌─────────────────┴─────────────────┐                    │
│            │                                   │                    │
│            ▼                                   ▼                    │
│  ┌─────────────────────┐           ┌─────────────────────────┐     │
│  │     m65832 CPU      │           │     Milo832 GPU         │     │
│  │                     │           │                         │     │
│  │  • Core pipeline    │           │  • SIMT cores           │     │
│  │  • L1 I-Cache       │           │  • Texture unit         │     │
│  │  • L1 D-Cache       │           │  • Rasterizer           │     │
│  │  • MMU (optional)   │           │  • Tile buffers         │     │
│  └─────────────────────┘           └─────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## DE2-115 Configuration (Budget)

### Logic Element Budget

| Component | LEs | % of Total |
|-----------|-----|------------|
| **m65832 CPU** | | |
| - Core pipeline | 15,000 | 13.1% |
| - L1 I-Cache controller | 2,000 | 1.7% |
| - L1 D-Cache controller | 2,500 | 2.2% |
| - Bus interface | 1,500 | 1.3% |
| **CPU Subtotal** | **21,000** | **18.3%** |
| | | |
| **Milo832 GPU** | | |
| - Command processor | 3,000 | 2.6% |
| - SIMT core (1 SM, 1 warp) | 25,000 | 21.8% |
| - Operand collector | 4,000 | 3.5% |
| - Scoreboard/scheduler | 3,000 | 2.6% |
| - Integer ALU (×32) | 8,000 | 7.0% |
| - FPU (×8, shared) | 12,000 | 10.5% |
| - SFU (×2, shared) | 4,000 | 3.5% |
| - Texture unit | 6,000 | 5.2% |
| - Rasterizer | 5,000 | 4.4% |
| - Tile buffer controller | 2,000 | 1.7% |
| - Triangle binner | 3,000 | 2.6% |
| - ROP | 2,000 | 1.7% |
| **GPU Subtotal** | **77,000** | **67.2%** |
| | | |
| **Shared Infrastructure** | | |
| - SDRAM controller | 5,000 | 4.4% |
| - System bus/arbiter | 3,000 | 2.6% |
| - Clock/reset/misc | 2,000 | 1.7% |
| **Shared Subtotal** | **10,000** | **8.7%** |
| | | |
| **TOTAL** | **108,000** | **94.3%** |
| **Remaining** | **6,480** | **5.7%** |

### Block RAM Budget (M9K = 9 Kbit = 1,152 bytes each)

| Component | M9K Blocks | KB | % of Total |
|-----------|------------|-----|------------|
| **m65832 CPU** | | | |
| - L1 I-Cache (4 KB) | 4 | 4.5 | 0.9% |
| - L1 D-Cache (4 KB) | 4 | 4.5 | 0.9% |
| **CPU Subtotal** | **8** | **9** | **1.9%** |
| | | | |
| **Milo832 GPU** | | | |
| - Register file (32×32×32b) | 4 | 4 | 0.9% |
| - Shared memory (8 KB) | 8 | 9 | 1.9% |
| - Instruction cache (4 KB) | 4 | 4.5 | 0.9% |
| - Texture cache (8 KB) | 8 | 9 | 1.9% |
| - Tile color buffer ×2 (2 KB) | 2 | 2.3 | 0.5% |
| - Tile depth buffer ×2 (1.5 KB) | 2 | 2.3 | 0.5% |
| - Triangle storage (16 KB) | 16 | 18 | 3.7% |
| - Tile bin lists (8 KB) | 8 | 9 | 1.9% |
| - Command FIFO (2 KB) | 2 | 2.3 | 0.5% |
| - Vertex output buffer (4 KB) | 4 | 4.5 | 0.9% |
| - SFU lookup tables (8 KB) | 8 | 9 | 1.9% |
| - Palette memory (2 KB) | 2 | 2.3 | 0.5% |
| **GPU Subtotal** | **68** | **76** | **15.7%** |
| | | | |
| **Shared Infrastructure** | | | |
| - SDRAM read buffer (4 KB) | 4 | 4.5 | 0.9% |
| - SDRAM write buffer (4 KB) | 4 | 4.5 | 0.9% |
| **Shared Subtotal** | **8** | **9** | **1.9%** |
| | | | |
| **TOTAL** | **84** | **94** | **19.4%** |
| **Remaining** | **348** | **392** | **80.6%** |

Note: Remaining BRAM can be used for larger caches or additional GPU features.

### Multiplier Budget (18×18)

| Component | Multipliers | % of Total |
|-----------|-------------|------------|
| m65832 CPU (MUL/DIV) | 4 | 1.5% |
| FPU (×8 units, 3 mults each) | 24 | 9.0% |
| SFU (×2 units, 2 mults each) | 4 | 1.5% |
| Texture filter (bilinear) | 8 | 3.0% |
| Rasterizer (edge functions) | 6 | 2.3% |
| Perspective divide | 4 | 1.5% |
| **TOTAL** | **50** | **18.8%** |
| **Remaining** | **216** | **81.2%** |

### DE2-115 Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DE2-115 RESOURCE SUMMARY                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Logic Elements:  ████████████████████████████████████░░░░  94%     │
│  Block RAM:       ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  19%     │
│  Multipliers:     ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  19%     │
│                                                                      │
│  Bottleneck: Logic (tight fit!)                                     │
│  Headroom: BRAM (can increase caches)                               │
│                                                                      │
│  Configuration:                                                      │
│  • 1 SM, 1 warp (32 threads)                                        │
│  • 8 shared FPUs, 2 SFUs                                            │
│  • 16×16 tiles                                                      │
│  • 8 KB texture cache                                               │
│  • ~200 triangles/frame practical limit                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## KV260 Configuration (Performance)

### LUT Budget

| Component | LUTs | % of Total |
|-----------|------|------------|
| **m65832 CPU** | | |
| - Core pipeline | 18,000 | 7.0% |
| - L1 I-Cache (8 KB) | 3,000 | 1.2% |
| - L1 D-Cache (8 KB) | 3,500 | 1.4% |
| - L2 Cache controller | 4,000 | 1.6% |
| - Bus interface (AXI) | 2,500 | 1.0% |
| **CPU Subtotal** | **31,000** | **12.1%** |
| | | |
| **Milo832 GPU** | | |
| - Command processor | 4,000 | 1.6% |
| - SIMT cores (2 SM, 4 warps) | 80,000 | 31.2% |
| - Operand collectors (×2) | 8,000 | 3.1% |
| - Scoreboard/scheduler | 6,000 | 2.3% |
| - Integer ALUs (×64) | 16,000 | 6.3% |
| - FPUs (×32, pipelined) | 32,000 | 12.5% |
| - SFUs (×8) | 8,000 | 3.1% |
| - Texture unit (32 samplers) | 15,000 | 5.9% |
| - ETC decoder | 3,000 | 1.2% |
| - Rasterizer | 6,000 | 2.3% |
| - Tile buffer controller | 3,000 | 1.2% |
| - Triangle binner | 4,000 | 1.6% |
| - ROP | 3,000 | 1.2% |
| **GPU Subtotal** | **188,000** | **73.4%** |
| | | |
| **Shared Infrastructure** | | |
| - DDR4 controller (PS) | 0* | 0% |
| - AXI interconnect | 8,000 | 3.1% |
| - DMA engine | 5,000 | 2.0% |
| - Misc (clock, debug) | 3,000 | 1.2% |
| **Shared Subtotal** | **16,000** | **6.2%** |
| | | |
| **TOTAL** | **235,000** | **91.7%** |
| **Remaining** | **21,200** | **8.3%** |

*KV260 DDR4 controller is in the Processing System (PS), not PL fabric.

### Block RAM Budget (BRAM36 = 36 Kbit = 4.5 KB each)

| Component | BRAM36 | KB | % of Total |
|-----------|--------|-----|------------|
| **m65832 CPU** | | | |
| - L1 I-Cache (8 KB) | 2 | 9 | 1.4% |
| - L1 D-Cache (8 KB) | 2 | 9 | 1.4% |
| **CPU Subtotal** | **4** | **18** | **2.8%** |
| | | | |
| **Milo832 GPU** | | | |
| - Register files (×2 SM) | 8 | 36 | 5.6% |
| - Shared memory (×2, 16 KB each) | 8 | 36 | 5.6% |
| - Instruction cache (8 KB) | 2 | 9 | 1.4% |
| - Texture cache (16 KB) | 4 | 18 | 2.8% |
| - SFU lookup tables (16 KB) | 4 | 18 | 2.8% |
| - Palette memory (4 KB) | 1 | 4.5 | 0.7% |
| - Command FIFO (4 KB) | 1 | 4.5 | 0.7% |
| - Vertex output buffer (16 KB) | 4 | 18 | 2.8% |
| **GPU BRAM Subtotal** | **32** | **144** | **22.2%** |
| | | | |
| **TOTAL BRAM** | **36** | **162** | **25.0%** |
| **Remaining BRAM** | **108** | **486** | **75.0%** |

### UltraRAM Budget (URAM = 288 Kbit = 36 KB each)

| Component | URAM | KB | % of Total |
|-----------|------|-----|------------|
| **m65832 CPU** | | | |
| - L2 Cache (64 KB) | 2 | 72 | 3.1% |
| **CPU Subtotal** | **2** | **72** | **3.1%** |
| | | | |
| **Milo832 GPU** | | | |
| - Tile color buffer ×2 (8 KB) | 1 | 36 | 1.6% |
| - Tile depth buffer ×2 (6 KB) | 1 | 36 | 1.6% |
| - Triangle storage (128 KB) | 4 | 144 | 6.3% |
| - Tile bin lists (72 KB) | 2 | 72 | 3.1% |
| - Texture cache L2 (72 KB) | 2 | 72 | 3.1% |
| **GPU URAM Subtotal** | **10** | **360** | **15.6%** |
| | | | |
| **TOTAL URAM** | **12** | **432** | **18.8%** |
| **Remaining URAM** | **52** | **1,872** | **81.3%** |

### DSP Budget

| Component | DSP48 | % of Total |
|-----------|-------|------------|
| m65832 CPU | 8 | 0.6% |
| FPU (×32 units) | 128 | 10.3% |
| SFU (×8 units) | 32 | 2.6% |
| Texture filter (×32) | 64 | 5.1% |
| Rasterizer | 16 | 1.3% |
| Primitive setup | 8 | 0.6% |
| **TOTAL** | **256** | **20.5%** |
| **Remaining** | **992** | **79.5%** |

### KV260 Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                    KV260 RESOURCE SUMMARY                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  LUTs:       ████████████████████████████████████████░░░░  92%      │
│  BRAM:       ██████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  25%      │
│  UltraRAM:   ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  19%      │
│  DSP:        ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  21%      │
│                                                                      │
│  Bottleneck: Logic (but comfortable)                                │
│  Headroom: Memory & DSP (lots of room for expansion)                │
│                                                                      │
│  Configuration:                                                      │
│  • 2 SMs, 4 warps total (128 threads)                               │
│  • 32 FPUs, 8 SFUs (fully parallel per warp)                        │
│  • 32×32 tiles                                                      │
│  • 88 KB texture cache (L1+L2)                                      │
│  • ~2000 triangles/frame practical limit                            │
│  • 1080p capable (with reduced geometry)                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Scaling Configurations

Depending on actual synthesis results, here are fallback configurations:

### Ultra-Budget (if DE2-115 is too tight)

Reduce GPU to fit:
- 1 SM, 1 warp (32 threads)
- 4 shared FPUs (8 cycles/warp for FP ops)
- 1 SFU
- 4 KB texture cache
- 8×8 tiles (256 bytes tile buffer)

Saves: ~25,000 LEs

### Maximum Performance (if KV260 has room)

Expand GPU:
- 4 SMs, 8 warps (256 threads)
- 64 FPUs (2 per thread pair)
- 16 SFUs
- 128 KB texture cache
- Larger triangle storage

Uses: Additional ~50,000 LUTs, ~20 URAM

---

## Memory Bandwidth Sharing

Both CPU and GPU need external memory access. Here's how to share fairly:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MEMORY ARBITER                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                      ┌──────────────────┐                           │
│                      │  Memory Arbiter  │                           │
│                      │  (Round-Robin +  │                           │
│                      │   Priority)      │                           │
│                      └────────┬─────────┘                           │
│                               │                                      │
│           ┌───────────────────┼───────────────────┐                 │
│           │                   │                   │                 │
│           ▼                   ▼                   ▼                 │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐       │
│  │ CPU Port        │ │ GPU Read Port   │ │ GPU Write Port  │       │
│  │ (High Priority) │ │ (Burst, Lower)  │ │ (Burst, Lower)  │       │
│  │                 │ │                 │ │                 │       │
│  │ Instruction     │ │ Texture fetch   │ │ Tile writeback  │       │
│  │ Data            │ │ Triangle fetch  │ │ Vertex output   │       │
│  │                 │ │ Vertex fetch    │ │                 │       │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘       │
│                                                                      │
│  Bandwidth Budget (DE2-115 SDRAM @ 100 MHz, 32-bit):               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Total: 400 MB/s                                               │  │
│  │                                                               │  │
│  │ CPU: 100 MB/s reserved (25%)                                  │  │
│  │   - Instruction fetch: ~20 MB/s                              │  │
│  │   - Data access: ~30 MB/s                                    │  │
│  │   - DMA/misc: ~50 MB/s                                       │  │
│  │                                                               │  │
│  │ GPU: 300 MB/s remaining (75%)                                │  │
│  │   - Texture: ~100 MB/s (compressed textures help!)          │  │
│  │   - Geometry: ~50 MB/s                                       │  │
│  │   - Tile writeback: ~80 MB/s                                 │  │
│  │   - Headroom: ~70 MB/s                                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Bandwidth Budget (KV260 DDR4 @ 2400 MT/s, 64-bit):                │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Total: ~15 GB/s (theoretical), ~8 GB/s practical             │  │
│  │                                                               │  │
│  │ CPU: 2 GB/s reserved (25%)                                   │  │
│  │ GPU: 6 GB/s remaining (75%)                                  │  │
│  │   - Plenty for 1080p @ 60 FPS                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Clock Domain Strategy

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CLOCK DOMAINS                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  DE2-115:                                                           │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ sys_clk (50 MHz)  ──► PLL ──┬──► cpu_clk (100 MHz)        │    │
│  │                             ├──► gpu_clk (100 MHz)         │    │
│  │                             └──► mem_clk (100 MHz)         │    │
│  │                                                            │    │
│  │ All synchronous - simplifies design                        │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  KV260:                                                             │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ PS provides clocks via FCLK:                               │    │
│  │                                                            │    │
│  │ FCLK0 (200 MHz) ──► cpu_clk                                │    │
│  │ FCLK1 (250 MHz) ──► gpu_clk (can run faster than CPU)      │    │
│  │ FCLK2 (300 MHz) ──► mem_clk (AXI to DDR)                   │    │
│  │                                                            │    │
│  │ CDC (clock domain crossing) needed at interfaces           │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Practical Recommendations

### For DE2-115 (Tight Fit)

1. **Synthesize CPU first** - Get accurate resource numbers
2. **Start with minimal GPU** - 1 SM, basic features
3. **Add features incrementally** - Monitor utilization after each add
4. **Consider time-multiplexing** - Share FPUs between threads if needed
5. **Aggressive resource sharing** - Same mult for SFU and texture filter

### For KV260 (Comfortable)

1. **Use PS DDR controller** - Saves significant PL resources
2. **Leverage UltraRAM** - Put large buffers in URAM, not BRAM
3. **Scale GPU first** - Add SMs until LUTs are ~85% used
4. **Add advanced features** - ETC decode, more texture formats
5. **Leave 10% headroom** - For routing and timing closure

### Build Order

```
Phase 1: CPU boots, runs test code
Phase 2: Add GPU command processor, can accept commands
Phase 3: Add 1 SM, run simple compute shaders
Phase 4: Add rasterizer, render flat-shaded triangles
Phase 5: Add texture unit, textured rendering
Phase 6: Add second SM (KV260 only)
Phase 7: Optimize, add advanced features
```
