# Memory Architecture: CPU + GPU with Shared DDR

## Overview

The m65832 CPU and Milo832 GPU each have their own private BRAM pools. Neither can see the other's on-chip memory. Both access external DDR/SDRAM through a shared memory controller with an arbiter.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FPGA                                            │
│                                                                              │
│  ┌─────────────────────────────────┐    ┌─────────────────────────────────┐ │
│  │          m65832 CPU             │    │          Milo832 GPU            │ │
│  │                                 │    │                                 │ │
│  │  ┌─────────┐    ┌─────────┐    │    │    ┌─────────┐    ┌─────────┐  │ │
│  │  │ I-Cache │    │ D-Cache │    │    │    │ Reg File│    │ Shared  │  │ │
│  │  │ (BRAM)  │    │ (BRAM)  │    │    │    │ (BRAM)  │    │ Memory  │  │ │
│  │  │ 4-8 KB  │    │ 4-8 KB  │    │    │    │ 4 KB    │    │ (BRAM)  │  │ │
│  │  └────┬────┘    └────┬────┘    │    │    └─────────┘    │ 8-16 KB │  │ │
│  │       │              │         │    │                   └─────────┘  │ │
│  │       │    ┌─────────┘         │    │    ┌─────────┐    ┌─────────┐  │ │
│  │       │    │                   │    │    │ Tex $   │    │ Tile    │  │ │
│  │  ┌────▼────▼────┐              │    │    │ (BRAM)  │    │ Buffers │  │ │
│  │  │ Cache        │              │    │    │ 8-16 KB │    │ (BRAM)  │  │ │
│  │  │ Controller   │              │    │    └────┬────┘    │ 2-8 KB  │  │ │
│  │  └──────┬───────┘              │    │         │         └─────────┘  │ │
│  │         │                      │    │         │                      │ │
│  │         │ Miss?                │    │    ┌────▼────────────────────┐ │ │
│  │         │                      │    │    │ GPU Memory Controller  │ │ │
│  │         ▼                      │    │    │ (coalescing, ordering) │ │ │
│  │  ┌──────────────┐              │    │    └───────────┬────────────┘ │ │
│  │  │ CPU Bus      │              │    │                │              │ │
│  │  │ Interface    │              │    │    ┌───────────▼────────────┐ │ │
│  │  └──────┬───────┘              │    │    │ GPU Bus Interface      │ │ │
│  │         │                      │    │    └───────────┬────────────┘ │ │
│  └─────────┼──────────────────────┘    └────────────────┼──────────────┘ │
│            │                                            │                 │
│            │         CPU BUS MASTER                     │ GPU BUS MASTER  │
│            │                                            │                 │
│            ▼                                            ▼                 │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                        MEMORY ARBITER                                │ │
│  │                                                                      │ │
│  │   Priority:  1. CPU (low latency critical)                          │ │
│  │              2. GPU reads (texture, vertex, commands)               │ │
│  │              3. GPU writes (framebuffer, triangle store)            │ │
│  │                                                                      │ │
│  │   Scheduling: Round-robin within priority, burst-aware              │ │
│  └──────────────────────────────┬──────────────────────────────────────┘ │
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                     MEMORY CONTROLLER                                │ │
│  │                                                                      │ │
│  │   DE2-115: SDRAM Controller (custom, directly in PL)                │ │
│  │   KV260:   AXI interface to PS DDR4 controller                      │ │
│  └──────────────────────────────┬──────────────────────────────────────┘ │
│                                 │                                        │
└─────────────────────────────────┼────────────────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │     External Memory         │
                    │                             │
                    │  DE2-115: 32 MB SDRAM       │
                    │  KV260:   4 GB DDR4         │
                    └─────────────────────────────┘
```

## CPU Memory System

The CPU needs caches to avoid stalling on every memory access.

### CPU Cache Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     CPU CACHE SUBSYSTEM                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    L1 Instruction Cache                      │    │
│  │                                                              │    │
│  │   Size: 4 KB (DE2-115) / 8 KB (KV260)                       │    │
│  │   Line size: 32 bytes (8 instructions)                       │    │
│  │   Associativity: 2-way set associative                       │    │
│  │   Replacement: LRU                                           │    │
│  │                                                              │    │
│  │   128 lines × 32 bytes = 4 KB                               │    │
│  │   64 sets × 2 ways                                          │    │
│  │                                                              │    │
│  │   BRAM usage: 4 M9K (DE2-115) or 1 BRAM36 (KV260)          │    │
│  │                                                              │    │
│  │   Read-only: No write-back needed                           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    L1 Data Cache                             │    │
│  │                                                              │    │
│  │   Size: 4 KB (DE2-115) / 8 KB (KV260)                       │    │
│  │   Line size: 32 bytes                                        │    │
│  │   Associativity: 2-way set associative                       │    │
│  │   Write policy: Write-back with write-allocate               │    │
│  │   Replacement: LRU                                           │    │
│  │                                                              │    │
│  │   BRAM usage: 4 M9K (DE2-115) or 1 BRAM36 (KV260)          │    │
│  │   + 1 M9K/BRAM for dirty bits and tags                      │    │
│  │                                                              │    │
│  │   Coherency: CPU flushes before GPU reads                   │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Cache Controller State Machine

```
┌───────────┐     hit      ┌───────────┐
│   IDLE    │─────────────▶│  RESPOND  │
│           │◀─────────────│           │
└─────┬─────┘              └───────────┘
      │ miss
      ▼
┌───────────┐   dirty?    ┌───────────┐
│  LOOKUP   │────────────▶│ WRITEBACK │
│           │     yes     │           │
└─────┬─────┘             └─────┬─────┘
      │ no                      │
      ▼                         ▼
┌───────────┐             ┌───────────┐
│   FILL    │◀────────────│   FILL    │
│  (fetch)  │             │  (fetch)  │
└─────┬─────┘             └───────────┘
      │
      ▼
┌───────────┐
│  RESPOND  │
└───────────┘
```

## GPU Memory System

The GPU has multiple separate BRAM pools for different purposes:

### GPU BRAM Allocation

```
┌─────────────────────────────────────────────────────────────────────┐
│                     GPU PRIVATE BRAM                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. REGISTER FILE (per SM)                                          │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ 32 registers × 32 threads × 4 bytes = 4 KB per SM        │   │
│     │ Dual-port: simultaneous read of 2 operands               │   │
│     │ BRAM: 4 M9K (DE2-115) or 1 BRAM36 (KV260)               │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  2. SHARED MEMORY (per SM)                                          │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ 8 KB (DE2-115) / 16 KB (KV260)                           │   │
│     │ 32 banks for conflict-free parallel access               │   │
│     │ Used for: uniforms, scratch space, vertex output         │   │
│     │ BRAM: 8-16 M9K or 2-4 BRAM36                            │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  3. TEXTURE CACHE                                                   │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ 8 KB (DE2-115) / 16 KB L1 + 64 KB L2 (KV260)            │   │
│     │ 4-way set associative                                    │   │
│     │ Line size: 64 bytes (one ETC block row)                  │   │
│     │ BRAM: 8 M9K or 4 BRAM36 + URAM for L2                   │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  4. TILE BUFFERS (double-buffered)                                  │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ Color: 16×16×4 = 1 KB (DE2) / 32×32×4 = 4 KB (KV260)    │   │
│     │ Depth: 16×16×3 = 768 B (DE2) / 32×32×3 = 3 KB (KV260)   │   │
│     │ ×2 for double buffer                                     │   │
│     │ BRAM: 4 M9K or 2 BRAM36                                 │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  5. INSTRUCTION CACHE                                               │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ 4 KB, read-only                                          │   │
│     │ Caches shader code fetched from DDR                      │   │
│     │ BRAM: 4 M9K or 1 BRAM36                                 │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
│  6. SFU LOOKUP TABLES                                               │
│     ┌──────────────────────────────────────────────────────────┐   │
│     │ sin, cos, exp2, log2, rcp, rsqrt, sqrt tables           │   │
│     │ 256 entries × 32 bits × 7 tables = 7 KB                  │   │
│     │ BRAM: 8 M9K or 2 BRAM36                                 │   │
│     └──────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## External DDR Memory Map

Both CPU and GPU see the same address space in DDR, but access it through different paths:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DDR MEMORY MAP                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  0x0000_0000 ┌────────────────────────────────────────────────────┐ │
│              │  BOOT ROM / FIRMWARE (CPU)                         │ │
│              │  64 KB                                              │ │
│  0x0001_0000 ├────────────────────────────────────────────────────┤ │
│              │  CPU CODE + DATA (CPU private region)              │ │
│              │  Application code, stack, heap                     │ │
│              │  2 MB                                               │ │
│  0x0021_0000 ├────────────────────────────────────────────────────┤ │
│              │  GPU REGISTERS (memory-mapped I/O)                 │ │
│              │  4 KB - CPU writes here to control GPU             │ │
│  0x0021_1000 ├────────────────────────────────────────────────────┤ │
│              │  COMMAND RING BUFFER                               │ │
│              │  64 KB - CPU writes commands, GPU reads            │ │
│  0x0022_0000 ├────────────────────────────────────────────────────┤ │
│              │  VERTEX BUFFERS                                    │ │
│              │  CPU writes, GPU reads                             │ │
│              │  1 MB                                               │ │
│  0x0032_0000 ├────────────────────────────────────────────────────┤ │
│              │  INDEX BUFFERS                                     │ │
│              │  CPU writes, GPU reads                             │ │
│              │  256 KB                                             │ │
│  0x0036_0000 ├────────────────────────────────────────────────────┤ │
│              │  UNIFORM BUFFERS                                   │ │
│              │  CPU writes, GPU reads                             │ │
│              │  64 KB                                              │ │
│  0x0037_0000 ├────────────────────────────────────────────────────┤ │
│              │  SHADER PROGRAMS                                   │ │
│              │  CPU writes, GPU reads                             │ │
│              │  256 KB                                             │ │
│  0x003B_0000 ├────────────────────────────────────────────────────┤ │
│              │  TEXTURE MEMORY                                    │ │
│              │  CPU writes, GPU reads                             │ │
│              │  4 MB (DE2) / 16 MB (KV260)                        │ │
│  0x007B_0000 ├────────────────────────────────────────────────────┤ │
│              │  TRIANGLE STORAGE (GPU private)                    │ │
│              │  GPU writes post-transform vertices                │ │
│              │  2 MB                                               │ │
│  0x009B_0000 ├────────────────────────────────────────────────────┤ │
│              │  TILE BIN LISTS (GPU private)                      │ │
│              │  GPU writes during binning                         │ │
│              │  256 KB                                             │ │
│  0x009F_0000 ├────────────────────────────────────────────────────┤ │
│              │  FRAMEBUFFER (double-buffered)                     │ │
│              │  GPU writes, display controller reads              │ │
│              │  2 × 1.2 MB (640×480) or 2 × 8 MB (1920×1080)     │ │
│  0x00BF_0000 ├────────────────────────────────────────────────────┤ │
│              │  FREE / HEAP                                       │ │
│              │  Remaining memory                                  │ │
│  0x01FF_FFFF └────────────────────────────────────────────────────┘ │
│              (32 MB total for DE2-115)                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Bus Arbiter Design

```vhdl
-- memory_arbiter.vhd
-- Arbitrates between CPU and GPU for external memory access

entity memory_arbiter is
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        
        -- CPU Master Interface
        cpu_req         : in  std_logic;
        cpu_wr          : in  std_logic;
        cpu_addr        : in  std_logic_vector(31 downto 0);
        cpu_wdata       : in  std_logic_vector(31 downto 0);
        cpu_rdata       : out std_logic_vector(31 downto 0);
        cpu_ready       : out std_logic;
        
        -- GPU Read Master Interface  
        gpu_rd_req      : in  std_logic;
        gpu_rd_addr     : in  std_logic_vector(31 downto 0);
        gpu_rd_len      : in  std_logic_vector(7 downto 0);  -- burst length
        gpu_rd_data     : out std_logic_vector(63 downto 0); -- wider for bandwidth
        gpu_rd_valid    : out std_logic;
        gpu_rd_ready    : out std_logic;
        
        -- GPU Write Master Interface
        gpu_wr_req      : in  std_logic;
        gpu_wr_addr     : in  std_logic_vector(31 downto 0);
        gpu_wr_len      : in  std_logic_vector(7 downto 0);
        gpu_wr_data     : in  std_logic_vector(63 downto 0);
        gpu_wr_ready    : out std_logic;
        
        -- Memory Controller Interface
        mem_req         : out std_logic;
        mem_wr          : out std_logic;
        mem_addr        : out std_logic_vector(31 downto 0);
        mem_wdata       : out std_logic_vector(63 downto 0);
        mem_rdata       : in  std_logic_vector(63 downto 0);
        mem_ready       : in  std_logic
    );
end entity;
```

### Arbitration Policy

```
┌─────────────────────────────────────────────────────────────────────┐
│                     ARBITRATION RULES                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Priority (highest to lowest):                                      │
│                                                                      │
│  1. CPU requests (always wins if pending)                           │
│     - CPU is latency-sensitive                                      │
│     - Cache miss stalls the entire CPU                              │
│     - Typically short bursts (1 cache line = 8 words)              │
│                                                                      │
│  2. GPU reads (texture, vertex, command fetches)                    │
│     - Can be pipelined/buffered                                     │
│     - Longer bursts (16-64 words)                                   │
│     - Miss causes shader stall but other warps can run              │
│                                                                      │
│  3. GPU writes (framebuffer, triangle store)                        │
│     - Lowest priority, can be buffered                              │
│     - Long bursts (entire tile = 256-1024 words)                    │
│     - Write buffer absorbs latency                                  │
│                                                                      │
│  Fairness:                                                          │
│  - After CPU burst completes, check GPU requests                    │
│  - GPU gets at least 1 burst per N CPU accesses (N=4)              │
│  - Prevents GPU starvation under heavy CPU load                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

Timeline Example:
─────────────────────────────────────────────────────────────────────────
    │ CPU  │ GPU-R │ CPU  │ GPU-R │ GPU-R │ CPU  │ GPU-W │ CPU  │
    │burst1│burst1 │burst2│burst2 │burst3 │burst3│burst1 │burst4│
─────────────────────────────────────────────────────────────────────────
         CPU wins      GPU gets turn   CPU wins  GPU write  CPU wins
```

## Cache Coherency

Since CPU and GPU have separate caches viewing the same DDR, we need coherency:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     COHERENCY PROTOCOL                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Simple software-managed coherency (no hardware snooping):          │
│                                                                      │
│  RULE 1: CPU writes data for GPU (vertex buffers, textures)        │
│  ────────────────────────────────────────────────────────────────   │
│     cpu_write(vertex_buffer, data);                                 │
│     cpu_cache_flush(vertex_buffer, size);  // Write-back to DDR    │
│     gpu_kick();  // Now GPU can safely read                         │
│                                                                      │
│  RULE 2: GPU writes data for CPU (rare - maybe readback)           │
│  ────────────────────────────────────────────────────────────────   │
│     gpu_render();                                                   │
│     gpu_fence();  // Wait for GPU writes to complete                │
│     cpu_cache_invalidate(framebuffer, size);  // Discard stale     │
│     cpu_read(framebuffer);  // Fresh data from DDR                  │
│                                                                      │
│  RULE 3: GPU register access (memory-mapped I/O)                   │
│  ────────────────────────────────────────────────────────────────   │
│     GPU registers are in uncached address range                     │
│     CPU reads/writes go directly to GPU, bypass cache               │
│                                                                      │
│  Implementation:                                                    │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │ Address bits [31:28] determine cacheability:             │      │
│  │   0x0XXX_XXXX  = Cacheable (normal DDR)                  │      │
│  │   0x1XXX_XXXX  = Uncached (GPU registers, MMIO)          │      │
│  └──────────────────────────────────────────────────────────┘      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Driver Cache Management

```c
// Driver helper functions for cache coherency

void upload_vertex_buffer(void* data, size_t size, uint32_t gpu_addr) {
    // Copy to DDR
    memcpy((void*)gpu_addr, data, size);
    
    // Flush CPU cache to ensure data reaches DDR
    cpu_dcache_flush(gpu_addr, size);
    
    // Memory barrier
    __sync_synchronize();
}

void upload_texture(void* data, size_t size, uint32_t gpu_addr) {
    memcpy((void*)gpu_addr, data, size);
    cpu_dcache_flush(gpu_addr, size);
    __sync_synchronize();
}

void kick_gpu(CommandBuffer* cmd) {
    // Flush command buffer
    cpu_dcache_flush(cmd->base, cmd->size);
    __sync_synchronize();
    
    // Write to GPU doorbell (uncached write)
    volatile uint32_t* doorbell = (uint32_t*)GPU_CMD_WRITE_PTR;
    *doorbell = cmd->write_ptr;
}

void wait_gpu_idle(void) {
    volatile uint32_t* status = (uint32_t*)GPU_STATUS;
    while (*status & GPU_BUSY) {
        // spin or yield
    }
}

// Rare: read back from GPU
void readback_framebuffer(void* dest, uint32_t gpu_addr, size_t size) {
    wait_gpu_idle();
    
    // Invalidate CPU cache (discard any stale copies)
    cpu_dcache_invalidate(gpu_addr, size);
    
    // Now safe to read
    memcpy(dest, (void*)gpu_addr, size);
}
```

## KV260 Specifics (AXI)

On KV260, the PS (Processing System) has the DDR controller. The PL (Programmable Logic) accesses DDR via AXI ports:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     KV260 AXI TOPOLOGY                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                         ┌─────────────────┐                         │
│                         │   DDR4 (PS)     │                         │
│                         │   4 GB          │                         │
│                         └────────┬────────┘                         │
│                                  │                                   │
│                         ┌────────▼────────┐                         │
│                         │  PS DDR         │                         │
│                         │  Controller     │                         │
│                         └────────┬────────┘                         │
│                                  │                                   │
│  ┌───────────────────────────────┼───────────────────────────────┐  │
│  │                    PS/PL AXI Interface                        │  │
│  │                                                               │  │
│  │  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐    │  │
│  │  │ S_AXI_HP0   │     │ S_AXI_HP1   │     │ S_AXI_HP2   │    │  │
│  │  │ (CPU)       │     │ (GPU Read)  │     │ (GPU Write) │    │  │
│  │  │ 64-bit      │     │ 128-bit     │     │ 128-bit     │    │  │
│  │  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘    │  │
│  │         │                   │                   │            │  │
│  └─────────┼───────────────────┼───────────────────┼────────────┘  │
│            │                   │                   │                │
│  ┌─────────▼─────────┐ ┌───────▼───────┐ ┌────────▼────────┐      │
│  │  m65832 CPU       │ │  GPU Memory   │ │  GPU Memory     │      │
│  │  Cache/Bus I/F    │ │  Read Unit    │ │  Write Unit     │      │
│  │                   │ │  (tex, vtx)   │ │  (FB, tri)      │      │
│  └───────────────────┘ └───────────────┘ └─────────────────┘      │
│                                                                      │
│  Bandwidth:                                                         │
│  - Each HP port: ~4 GB/s theoretical                               │
│  - 3 ports total: ~12 GB/s max                                     │
│  - Practical: ~6-8 GB/s with arbitration overhead                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Revised BRAM Budget

With CPU and GPU having **completely separate** BRAM:

### DE2-115 (432 M9K total = 486 KB)

| Owner | Component | M9K | KB |
|-------|-----------|-----|-----|
| CPU | I-Cache | 4 | 4.5 |
| CPU | D-Cache | 4 | 4.5 |
| CPU | Cache tags/state | 2 | 2.3 |
| **CPU Total** | | **10** | **11.3** |
| | | | |
| GPU | Register file | 4 | 4.5 |
| GPU | Shared memory | 8 | 9.0 |
| GPU | Texture cache | 8 | 9.0 |
| GPU | Tile buffers (×2) | 4 | 4.5 |
| GPU | Instruction cache | 4 | 4.5 |
| GPU | SFU tables | 8 | 9.0 |
| GPU | Command FIFO | 2 | 2.3 |
| **GPU Total** | | **38** | **42.8** |
| | | | |
| Shared | Memory controller buffers | 4 | 4.5 |
| **Grand Total** | | **52** | **58.6** |
| **Remaining** | | **380** | **427** |

Plenty of headroom for larger caches if logic permits!

### KV260 (144 BRAM36 + 64 URAM)

| Owner | Component | BRAM36 | URAM | KB |
|-------|-----------|--------|------|-----|
| CPU | I-Cache | 2 | - | 9 |
| CPU | D-Cache | 2 | - | 9 |
| CPU | L2 Cache | - | 2 | 72 |
| **CPU Total** | | **4** | **2** | **90** |
| | | | | |
| GPU | Register files (×2 SM) | 4 | - | 18 |
| GPU | Shared memory (×2 SM) | 8 | - | 36 |
| GPU | Texture cache L1 | 4 | - | 18 |
| GPU | Texture cache L2 | - | 2 | 72 |
| GPU | Tile buffers | - | 1 | 36 |
| GPU | Triangle storage | - | 4 | 144 |
| GPU | Instruction cache | 2 | - | 9 |
| GPU | SFU tables | 2 | - | 9 |
| **GPU Total** | | **20** | **7** | **342** |
| | | | | |
| **Grand Total** | | **24** | **9** | **432** |
| **Remaining** | | **120** | **55** | **~2.4 MB** |
