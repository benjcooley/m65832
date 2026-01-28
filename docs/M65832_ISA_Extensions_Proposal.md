# M65832 ISA Extensions Proposal: Accumulator Spill Modes

**Status:** Proposal  
**Date:** 2026-01-28  
**Author:** Architecture Team

## Overview

This document proposes three new addressing modes that leverage unused bits in Direct Page register addresses to dramatically improve code density for accumulator-centric code generation.

## Background

### The A-Centric Code Generation Model

The M65832 architecture maps 64 general-purpose registers (R0-R63) to Direct Page addresses. Since these are 32-bit registers aligned to 4-byte boundaries, the DP addresses are:

| Register | DP Address |
|----------|------------|
| R0 | $00 |
| R1 | $04 |
| R2 | $08 |
| ... | ... |
| R63 | $FC |

The low 2 bits of these addresses are **always 00** and currently unused.

### Current Code Generation Pattern

Optimal M65832 code uses the Accumulator (A) as the computational hub:

```asm
; Compute R0 = (R1 + R2) & R3
LDA R1        ; 2 bytes - A = R1
CLC           ; 1 byte
ADC R2        ; 2 bytes - A = R1 + R2
AND R3        ; 2 bytes - A = (R1 + R2) & R3
STA R0        ; 2 bytes - store result
; Total: 9 bytes
```

However, when A contains a value that must be preserved across operations, we need to spill it:

```asm
; Current spill pattern (4 bytes overhead):
STA R30       ; 2 bytes - save A to spill register
LDA R5        ; 2 bytes - load new value
; ... use A ...
LDA R30       ; 2 bytes - restore A (or store result first)
```

## Proposed Extensions

### Encoding

Repurpose the low 2 bits of DP register addresses as **result destination modes** for instructions that modify A:

| Address [1:0] | Mode | Bytes | Mnemonic | Result Destination |
|---------------|------|-------|----------|-------------------|
| `00` | Normal | 2 | `LDA Rn` | A (default) |
| `01` | Spill | 3 | `LDA.S Rn,Rs` | A, with old A spilled to Rs |
| `10` | Push | 2 | `LDA.P Rn` | A, with old A pushed to stack |
| `11` | Exchange | 2 | `LDA.X Rn` | A, with old A stored to Rn (swap) |

**Key insight:** These modes answer "what do I do with the current A value before it gets overwritten?"

### Mode 01: SPILL (`LDA.S`, `ADC.S`, etc.)

**Encoding:** 3 bytes
```
[opcode] [DP_addr | 0x01] [spill_reg]
```

**Operation:** Before modifying A, save its current value to the specified spill register.
```
LDA.S Rn,Rs:  Rs ← A; A ← Rn         ; Spill A to Rs, then load Rn
ADC.S Rn,Rs:  Rs ← A; A ← A + Rn     ; Spill A to Rs, then add Rn
AND.S Rn,Rs:  Rs ← A; A ← A & Rn     ; Spill A to Rs, then AND Rn
```

**Use Case:** When you need A for a new computation but must preserve its current value.

```asm
; Before (4 bytes):
STA R30       ; save A
LDA R5        ; load new value

; After (3 bytes):
LDA.S R5,R30  ; atomic spill-and-load
```

### Mode 10: PUSH (`LDA.P`, `ADC.P`, etc.)

**Encoding:** 2 bytes
```
[opcode] [DP_addr | 0x02]
```

**Operation:** Before modifying A, push its current value to the stack.
```
LDA.P Rn:  PHA; A ← Rn         ; Push A to stack, then load Rn
ADC.P Rn:  PHA; A ← A + Rn     ; Push A to stack, then add Rn
AND.P Rn:  PHA; A ← A & Rn     ; Push A to stack, then AND Rn
```

**Use Case:** Function prologues or when you need stack-based saving (no register available).

```asm
; Before (3 bytes):
PHA           ; save A to stack
LDA R5        ; load new value

; After (2 bytes):
LDA.P R5      ; atomic push-and-load
```

### Mode 11: EXCHANGE (`LDA.X`, `ADC.X`, etc.)

**Encoding:** 2 bytes
```
[opcode] [DP_addr | 0x03]
```

**Operation:** Swap A with the operand register before/during the operation.
```
LDA.X Rn:  temp ← A; A ← Rn; Rn ← temp    ; Swap A ↔ Rn
```

**Use Case:** Alternating between two values, or storing result back to operand.

```asm
; Before (6+ bytes):
STA R31       ; temp = A
LDA R5        ; A = R5  
... complex swap ...

; After (2 bytes):
LDA.X R5      ; swap A ↔ R5
```

**Note on EXCHANGE with ALU ops:** For `ADC.X Rn`, the semantics could be:
- Option A: `temp ← A; A ← A + Rn; Rn ← temp` (save old A to Rn, result in A)
- Option B: `A ← A + Rn; Rn ← A` (result goes to both A and Rn)

Recommend **Option A** for consistency with SPILL semantics.

## Impact Analysis

### Code Density Improvement

For typical A-centric code with register pressure:

| Pattern | Current | With Extensions | Savings |
|---------|---------|-----------------|---------|
| Spill A to register, load new | 4 bytes | 3 bytes (SPILL) | 25% |
| Push A to stack, load new | 3 bytes | 2 bytes (PUSH) | 33% |
| Swap A with register | 6+ bytes | 2 bytes (EXCHANGE) | 66% |

### Compiler Code Generation

With these extensions, the LLVM backend can:

1. **Freely use A for all arithmetic** knowing spills are cheap (3 bytes vs 4)
2. **Chain operations through A** with minimal overhead for register pressure
3. **Generate code matching hand-optimized 6502 patterns** automatically

### Example: Complex Expression

```c
int result = ((a + b) & c) | d;
```

**Current optimal (with redundant loads):**
```asm
LDA a         ; 2
CLC           ; 1
ADC b         ; 2
STA temp      ; 2  (unnecessary if we had chaining)
LDA temp      ; 2  (unnecessary)
AND c         ; 2
STA temp      ; 2  (unnecessary)
LDA temp      ; 2  (unnecessary)
ORA d         ; 2
STA result    ; 2
; Total: 19 bytes
```

**With peephole optimization (remove STA/LDA pairs):**
```asm
LDA a         ; 2
CLC           ; 1
ADC b         ; 2
AND c         ; 2
ORA d         ; 2
STA result    ; 2
; Total: 11 bytes
```

**With SPILL/PUSH (when A must be preserved):**
```asm
LDA.S a,R30   ; 3 - spill current A to R30, load a
CLC           ; 1
ADC b         ; 2
AND c         ; 2
ORA d         ; 2
STA result    ; 2 - store result (A still available)
LDA R30       ; 2 - restore A from spill register
; Total: 14 bytes (vs 19 without extensions when A must be preserved)

; Or using stack:
LDA.P a       ; 2 - push A to stack, load a
CLC           ; 1
ADC b         ; 2
AND c         ; 2
ORA d         ; 2
STA result    ; 2 - store result
PLA           ; 1 - restore A from stack
; Total: 12 bytes
```

## Implementation Considerations

### Hardware

- **Decode complexity:** Minimal - just check low 2 bits of DP address
- **Additional datapath:** Need mux for spill register source/dest
- **Cycle count:** SPILL/RESTORE = 2 cycles (two register operations), EXCHANGE = 2 cycles

### Assembler

- New mnemonics: `LDA.S`, `STA.S`, `LDA.R`, `STA.R`, `XCH`
- Alternative syntax: `SPILL Rn,Rs` / `RESTORE Rn,Rs` / `XCHG Rn`

### LLVM Backend

- Update `M65832InstrInfo.td` with new instruction definitions
- Modify pseudo expansion to use SPILL/RESTORE when beneficial
- Cost model: SPILL/RESTORE = 1.5x normal load/store cost

## Compatibility

- **Binary compatible:** No - new encodings use previously-reserved bit patterns
- **Source compatible:** Yes - existing assembly code unchanged
- **Detection:** Can check for extension support via CPU ID or feature flags

## Open Questions

1. Should SPILL/RESTORE support immediate mode? (e.g., `LDA.S #imm,Rs`)
2. Should we reserve mode `11` for future use instead of EXCHANGE?
3. What happens if spill register equals source register? (NOP? Undefined?)

## Recommendation

**Implement these extensions.** The A-centric code generation model is fundamental to M65832's efficiency, and these extensions reduce the overhead of the accumulator bottleneck by 25-66% depending on the pattern.

Priority order:
1. **SPILL (mode 01)** - Most common case for compiler-generated code, biggest win (25%)
2. **PUSH (mode 10)** - Function prologues, stack-based saving (33%)
3. **EXCHANGE (mode 11)** - Swap operations, biggest density win (66%)

## References

- M65832 Architecture Reference Manual
- M65832 C ABI Specification
- LLVM M65832 Backend Source (`llvm-m65832/llvm/lib/Target/M65832/`)
