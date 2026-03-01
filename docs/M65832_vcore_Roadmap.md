# M65832/vcore Roadmap

**Status:** Active Development
**Date:** February 2026

## Summary

The M65832 project is adding a modern pipelined out-of-order processor
implementation -- the **vcore** -- alongside the existing multi-cycle VHDL
core. The vcore is a fork of the RSD RISC-V OoO processor
(Apache 2.0, github.com/rsd-devel/rsd), with the RISC-V decoder replaced
by an m65832 decoder targeting a new **fixed-width 32-bit instruction
encoding** for native mode (W=11).

This document outlines the plan, staging, and the relationship between the
existing toolchain and the new processor.

---

## What Is Changing

### New: Fixed-Width 32-bit Encoding (W=11)

32-bit native mode (W=11) is being re-encoded from variable-length
byte-stream instructions to fixed-width 32-bit instruction words. The
architecture (registers, operations, flag behavior, memory model) is
unchanged. Only the binary encoding changes.

Full specification: [M65832_Fixed32_Encoding.md](M65832_Fixed32_Encoding.md)

Key changes:
- All instructions are exactly 4 bytes, word-aligned
- 6-bit register fields address R0-R63 directly
- R0 = hardwired zero register
- R1-R55 = general purpose (compiler allocation pool)
- R56-R63 = architectural registers (A, X, Y, SP, D, B, VBR, T)
- F bit (bit 0) controls flag-setting vs flagless ALU
- Complex addressing modes decomposed into explicit instruction sequences
- Each instruction maps to exactly one pipeline operation (no micro-op cracking)

### New: M65832/vcore Processor

The vcore is a high-performance pipelined processor for fixed32-encoded
W=11 code. It is a fork of the RSD RISC-V OoO core with the following
modifications:

- RISC-V decoder replaced with m65832 fixed32 decoder
- P (flags) register added to the OoO rename table
- Branch resolver adapted for m65832 condition codes
- Targeting KV260 (Zynq UltraScale+) as primary FPGA platform

Repository: github.com/benjcooley/rsd-m65832 (local: `../rsd-m65832/`)

### Updated: Full Toolchain Migration

The existing m65832 toolchain (emulator, assembler, VHDL core, LLVM) is
being upgraded to support fixed32 encoding in W=11 mode. This ensures
Linux bring-up and compiler development happen on the final encoding.

### Unchanged: Legacy Mode Support

6502 emulation (W=00) and 65816 native (W=01) modes retain their existing
variable-length encoding. The existing VHDL core and emulator continue to
support these modes. On the vcore FPGA, legacy modes are handled by
dedicated interleaved compatibility cores (MX65 for 6502, P65816 for
65816), using the existing coprocessor interleaving mechanism.

---

## Architecture: Before and After

### Current: Single Multi-Cycle Core

```
              ┌────────────────────────┐
              │   m65832_core.vhd      │
              │   Multi-cycle FSM      │
              │   All modes (W=00/01/11)│
              │   Variable-length      │
              │   ~4K LUT              │
              └───────────┬────────────┘
                          │ 8-bit bus
                    ┌─────┴─────┐
                    │  Memory   │
                    └───────────┘
```

### Target: Multi-Core with vcore

```
  ┌──────────┐  ┌──────────┐  ┌──────────────────────────┐
  │ MX65     │  │ P65816   │  │ vcore (RSD fork)         │
  │ 6502     │  │ 65816    │  │ OoO, pipelined           │
  │ W=00     │  │ W=01     │  │ W=11 fixed32             │
  │ ~1K LUT  │  │ ~3K LUT  │  │ ~20K LUT                 │
  └────┬─────┘  └────┬─────┘  │ ROB(64), rename, 2-wide  │
       │              │        │ L1 I$/D$, gshare BP      │
       │              │        └────────────┬─────────────┘
       │              │                     │
  ┌────┴──────────────┴─────────────────────┴──────┐
  │              Interleave / Mode Switch           │
  │         (SEPE/REPE/XCE context transfer)        │
  └───────────────────────┬────────────────────────┘
                          │ 64-bit system bus (AXI4)
              ┌───────────┴───────────┐
              │  DDR / SDRAM / BRAM   │
              │  Milo832 GPU          │
              │  Peripherals          │
              └───────────────────────┘
```

---

## Staging

Development proceeds in two parallel workstreams that converge when the
vcore runs the same fixed32 binaries the emulator validates.

### Stage 1: Toolchain Migration to Fixed32 (m65832 repo)

The existing toolchain upgrades to support fixed32 encoding in W=11 mode.
All components continue to support the variable-length encoding for W=00
and W=01 modes.

| Component | Change | Status |
|-----------|--------|--------|
| Encoding spec | Fixed32 v1.2 specification | Done |
| Emulator | Add fixed32 decode path for W=11 | Pending |
| Assembler | Add fixed32 output mode, R0-R63 syntax, traditional aliases | Pending |
| VHDL core decoder | Add fixed32 decode path for W=11 (FSM unchanged) | Pending |
| LLVM backend | Retarget W=11 codegen to fixed32, R1-R55 allocation | Pending |
| ISA reference docs | Update for fixed32, dual encoding documentation | Pending |
| Test suite | Port/add fixed32 assembly tests | Pending |

**Ordering:** Emulator first (LLVM and tests need a validation target),
then assembler (tests need fixed32 encoding), then VHDL core and LLVM
in parallel.

### Stage 2: vcore Pipeline (rsd-m65832 repo)

The RSD fork is modified for m65832.

| Step | Change | Status |
|------|--------|--------|
| Fork RSD | github.com/benjcooley/rsd-m65832 | Done |
| Replace decoder | m65832 fixed32 opcode map, register fields, F-bit | Pending |
| Add flags | P register in OpInfo, rename table, ALU writeback | Pending |
| Branch resolver | cond4 decode instead of RISCV_ISF_Common | Pending |
| Simulation | Validate against emulator commit traces | Pending |

### Stage 3: Hardware Bring-Up

| Milestone | Target | Description |
|-----------|--------|-------------|
| HW0 | KV260 | Boot ROM + BRAM + UART, basic execution |
| HW1 | KV260 | Assembly test suite, pipeline validation |
| HW2 | KV260 | Branch predictor + caches, performance measurement |
| HW3 | KV260 | Full SoC integration (MMU, interrupts, system bus) |
| HW4 | DE25-Nano | Port to Agilex 5 (Quartus), SDRAM |

### Stage 4: System Integration

| Milestone | Description |
|-----------|-------------|
| Linux on vcore | Boot Linux using fixed32-compiled kernel on KV260 |
| GPU integration | Connect Milo832 GPU via shared system bus |
| Compatibility cores | Interleave MX65 + P65816 for legacy mode support |
| Full Commodore 256 | Complete SoC: vcore + GPU + audio + peripherals |

---

## ISA Design Decisions

These decisions have been made and are reflected in the fixed32 spec:

### Flagless X-Instructions (F-bit)

ALU instructions default to flagless (F=0). Flag-setting variants use
F=1. Loads, stores, transfers, stack ops, and control flow are always
flagless. This eliminates flag dependency chains that would otherwise
serialize OoO execution. The compiler emits F=1 only before conditional
branches or carry-chain operations (ADC/SBC).

### Unified Register File

Named registers (A, X, Y, SP, D, B, VBR, T) are aliases for R56-R63.
R0 is a hardwired zero register. R1-R55 are general-purpose. The LLVM
register allocator uses R1-R55 exclusively; R56-R63 are reserved. Hand-
written assembly uses traditional mnemonics mapped to R56-R63.

### 1:1 Instruction-to-Operation Mapping

Every fixed32 instruction maps to exactly one pipeline operation. Complex
addressing modes (DP indirect, indirect indexed, etc.) are decomposed
into explicit instruction sequences by the compiler or assembler. This
eliminates micro-op cracking and simplifies the pipeline.

### Dual Programming Models

Compiler output (R1-R55, pure RISC-style) and hand-written assembly
(R56-R63 via traditional mnemonics) are both valid and execute identically.
The disassembler can pattern-match R56-R63 sequences back to traditional
65xx addressing modes.

---

## FPGA Resource Budget

| Component | LUT (est.) | BRAM | UltraRAM |
|-----------|-----------|------|----------|
| vcore (RSD fork) | ~20-25K | ~12 | 0 |
| MX65 6502 | ~1K | 0 | 0 |
| P65816 | ~3K | 0 | 0 |
| Milo832 GPU | ~50K | ~20 | ~14 |
| System bus + peripherals | ~5K | ~4 | 0 |
| Boot ROM + BRAM | ~1K | ~4 | 0 |
| **Total** | **~80-85K** | **~40** | **~14** |
| **KV260 available** | **~117K CLB** | **144** | **64** |
| **Utilization** | **~70%** | **~28%** | **~22%** |

---

## Related Documents

- [M65832_Fixed32_Encoding.md](M65832_Fixed32_Encoding.md) -- Fixed-width encoding specification
- [M65832_Architecture_Reference.md](M65832_Architecture_Reference.md) -- CPU architecture
- [M65832_Instruction_Set.md](M65832_Instruction_Set.md) -- Instruction reference
- [M65832_System_Bus.md](M65832_System_Bus.md) -- SoC bus architecture
- [M65832_FPGA_Hardware_Reference.md](M65832_FPGA_Hardware_Reference.md) -- FPGA platform details
- [M65832_Classic_Coprocessor.md](M65832_Classic_Coprocessor.md) -- Legacy mode interleaving

## External Repositories

- **rsd-m65832**: github.com/benjcooley/rsd-m65832 (vcore, RSD fork)
- **milo832**: ../milo832/ (GPU)
- **llvm-m65832**: ../llvm-m65832/ (LLVM compiler backend)
