# M65832 Architecture Reference Manual

**Modern 65832 Microprocessor**  
*A 32-bit evolution of the 65816, with 65-bit physical addressing*

Version 0.2  
January 2026

> **Implementation Status:** Core RTL implemented and verified in simulation. See individual sections for specific implementation notes.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [Programming Model](#3-programming-model)
4. [Processor Modes](#4-processor-modes)
5. [Memory Model](#5-memory-model)
6. [Instruction Set Overview](#6-instruction-set-overview)
7. [Addressing Modes](#7-addressing-modes)
8. [Instruction Reference](#8-instruction-reference)
9. [Exceptions and Interrupts](#9-exceptions-and-interrupts)
10. [Memory Management Unit](#10-memory-management-unit)
11. [Atomic Operations](#11-atomic-operations)
12. [Privilege Model](#12-privilege-model)
13. [Linux ABI Considerations](#13-linux-abi-considerations)
14. [Virtual 6502 Mode](#14-virtual-6502-mode)
15. [Assembly Language Guide](#15-assembly-language-guide)

---

## 1. Introduction

### 1.1 Design Philosophy

The M65832 is a direct evolution of the WDC 65C816, extending it to a true 32-bit architecture while preserving the elegant simplicity and "feel" of the 6502 family. The design goals are:

1. **Backward Compatibility**: Run 6502 and 65816 code with minimal modification
2. **Flat 32-bit Virtual Address Space**: Simple, predictable memory model
3. **65-bit Physical Address Space**: Future-proof via MMU/paging
4. **Compact Instructions**: Keep the 6502's code density advantage
5. **Modern OS Support**: Full Linux compatibility (MMU, privilege levels, atomics)
6. **Fun to Program**: The 6502 spirit—predictable, fast, satisfying

### 1.2 Heritage

| Processor | Year | Data Width | Address Space | Key Feature |
|-----------|------|------------|---------------|-------------|
| 6502      | 1975 | 8-bit      | 64 KB         | Zero page, elegant ISA |
| 65C02     | 1983 | 8-bit      | 64 KB         | CMOS, new instructions |
| 65C816    | 1984 | 8/16-bit   | 16 MB         | Bank registers, native mode |
| **M65832**| 2026 | 8/16/32-bit| 4 GB VA / 32 EB PA | Paging, privilege, atomics |

### 1.3 Key Innovations

- **Register Window**: Direct Page can map to a 64×32-bit hardware register file
- **Base Registers**: D (Direct), B (Absolute base), VBR (Virtual 6502 base)
- **Width Flags**: M and X flags extended to select 8/16/32-bit operations
- **Two-Level Paging**: 32-bit VA → 65-bit PA translation
- **Supervisor/User Modes**: Full privilege separation for OS support
- **Atomic Operations**: Compare-and-swap for lock-free programming
- **Classic Coprocessor**: Two-core architecture with dedicated 6502 coprocessor

### 1.4 Classic Coprocessor (SoC Feature)

For authentic classic system emulation, the M65832 SoC includes a dedicated 6502 coprocessor core:

| Core | Purpose | ISA |
|------|---------|-----|
| **M65832** | Linux, modern apps | Full 32-bit |
| **6502** | Classic game code | Pure 6502/65C02 |

These cores are time-sliced using a fractional accumulator: the 6502 runs at a configurable exact frequency (e.g., 1.022727 MHz for C64 NTSC), while M65832 gets the remaining cycles (~90%+). I/O accesses from the 6502 are handled via shadow registers and an IRQ-based interface to the main core.

> **RTL Reference:** `m65832_coprocessor_top.vhd`, `m65832_6502_coprocessor.vhd`, `m65832_interleave.vhd`

See [Classic Coprocessor Architecture](M65832_Classic_Coprocessor.md) for full details.

### 1.5 Endianness

**Little-endian**, consistent with:
- 6502/65816 heritage
- x86, ARM, RISC-V conventions
- Linux ecosystem expectations

Multi-byte values store LSB at the lowest address:
```
Address:  $1000  $1001  $1002  $1003
Value:    $78    $56    $34    $12     ; Represents $12345678
```

---

## 2. Architecture Overview

### 2.1 Block Diagram

> **RTL Reference:** Module structure in `rtl/` directory

```
┌─────────────────────────────────────────────────────────────────┐
│                         M65832 Core (m65832_core.vhd)            │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Register File (m65832_regfile.vhd)              │ │
│  │  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────────────────────┐ │ │
│  │  │   A   │  │   X   │  │   Y   │  │   Register Window     │ │ │
│  │  │32-bit │  │32-bit │  │32-bit │  │   R0-R63 (32-bit)     │ │ │
│  │  └───────┘  └───────┘  └───────┘  └───────────────────────┘ │ │
│  │  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────────┐ │ │
│  │  │  SP   │  │   D   │  │   B   │  │  VBR  │  │     T     │ │ │
│  │  │32-bit │  │32-bit │  │32-bit │  │32-bit │  │  32-bit   │ │ │
│  │  └───────┘  └───────┘  └───────┘  └───────┘  └───────────┘ │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │  P: C Z I D X1 X0 M1 M0 V N E S R K (14 bits)          │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  ┌─────────────┐  ┌──────────┴──────────┐  ┌──────────────────┐ │
│  │   Decoder   │  │        ALU          │  │   Address Gen    │ │
│  │m65832_      │  │   m65832_alu.vhd    │  │  m65832_         │ │
│  │decoder.vhd  │  │   8/16/32-bit       │  │  addrgen.vhd     │ │
│  │             │  │   +BCD (8/16 only)  │  │                  │ │
│  └─────────────┘  └─────────────────────┘  └──────────────────┘ │
│                              │                                   │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │                 State Machine (FSM)                        │  │
│  │  ST_FETCH → ST_DECODE → ST_ADDRn → ST_READn → ST_EXECUTE  │  │
│  └───────────────────────────────────────────────────────────┘  │
└───────────────────────────┬─────────────────────────────────────┘
                            │ 32-bit Virtual Address
                    ┌───────┴───────┐
                    │      MMU      │
                    │m65832_mmu.vhd │
                    │ 16-entry TLB  │
                    └───────┬───────┘
                            │ 65-bit Physical Address
                    ┌───────┴───────┐
                    │  Memory Bus   │
                    └───────────────┘
```

### 2.2 Feature Summary

| Feature | Specification |
|---------|---------------|
| Data widths | 8, 16, 32 bits (flag-selectable) |
| Virtual address | 32 bits (4 GB) |
| Physical address | 65 bits (32 exabytes) |
| Page size | 4 KB |
| TLB | 16-entry fully-associative, ASID-tagged |
| Registers | A, X, Y (width-variable), 64×32-bit register window |
| Stack | 32-bit pointer, anywhere in address space |
| Pipeline | Multi-cycle state machine |
| Privilege levels | 2 (Supervisor, User) |

> **RTL Reference:** Feature constants defined in `m65832_pkg.vhd`

---

## 3. Programming Model

### 3.1 Core Registers

#### 3.1.1 Accumulator (A)

The primary arithmetic register, supporting 8, 16, or 32-bit operations based on the M flag state.

| M1:M0 | Width | Bits Used | Notation |
|-------|-------|-----------|----------|
| 00    | 8-bit | A[7:0]    | .A       |
| 01    | 16-bit| A[15:0]   | .W       |
| 10    | 32-bit| A[31:0]   | .L       |
| 11    | Reserved | — | — |

#### 3.1.2 Index Registers (X, Y)

Used for indexed addressing modes. Width controlled by X flag.

| X1:X0 | Width | Bits Used |
|-------|-------|-----------|
| 00    | 8-bit | [7:0]     |
| 01    | 16-bit| [15:0]    |
| 10    | 32-bit| [31:0]    |
| 11    | Reserved | — |

#### 3.1.3 Stack Pointer (S)

32-bit in native mode. Points to next free location (pre-decrement push).

In emulation mode, limited to page $01 (8-bit: $0100-$01FF).

#### 3.1.4 Program Counter (PC)

32-bit in native mode, 16-bit in emulation mode.

#### 3.1.5 Direct Page Base (D)

32-bit base address for Direct Page addressing mode. All DP references compute: `effective_address = D + offset`

When R=1 (Register Window mode), DP accesses go to hardware registers instead of memory.

#### 3.1.6 Absolute Base (B)

32-bit base address for Absolute addressing. In native mode: `effective_address = B + abs16`

This keeps absolute instructions short (3 bytes) while addressing full 4GB.

#### 3.1.7 Virtual Base Register (VBR)

32-bit base for 6502 emulation mode. All 16-bit addresses are computed as: `effective_address = VBR + addr16`

Allows running 6502 code anywhere in the address space.

#### 3.1.8 Temp Register (T)

32-bit temporary register used for:
- High word of 64-bit operations (LDQ/STQ store T:A pair)
- Remainder from DIV/DIVU operations
- Intermediate results during extended operations

Accessible via TTA (T→A) and TAT (A→T) instructions.

### 3.2 Status Register (P)

The status register is a 14-bit internal register extending the 65816 model. The implementation stores flags in the following layout:

```
Internal P Register (14 bits):
 Bit 13  12  11  10   9   8   7   6   5   4   3   2   1   0
    ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
    │ K │ R │ S │ E │ N │ V │M1 │M0 │X1 │X0 │ D │ I │ Z │ C │
    └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
```

> **RTL Reference:** Bit positions defined as constants `P_C` through `P_K` in `m65832_pkg.vhd`

#### Arithmetic/Logic Flags

| Bit | Name | Description |
|-----|------|-------------|
| 0 | C | Carry/borrow from arithmetic |
| 1 | Z | Zero - set if result is zero |
| 2 | I | IRQ Disable - mask IRQ when set |
| 3 | D | Decimal - enable BCD arithmetic (8/16-bit only) |
| 8 | V | Overflow - set on signed overflow |
| 9 | N | Negative - set if result has MSB=1 |

#### Width Control Flags

| Bits | Name | Description |
|------|------|-------------|
| 5:4 | X1:X0 | Index width: 00=8-bit, 01=16-bit, 10=32-bit, 11=reserved |
| 7:6 | M1:M0 | Accumulator width: 00=8-bit, 01=16-bit, 10=32-bit, 11=reserved |

#### Mode/Privilege Flags

| Bit | Name | Description |
|-----|------|-------------|
| 10 | E | Emulation mode: 1=6502 mode, 0=Native mode |
| 11 | S | Supervisor: 1=Supervisor privilege, 0=User privilege |
| 12 | R | Register Window: 1=DP accesses register file, 0=DP accesses memory |
| 13 | K | Compatibility: 1=illegal opcodes become NOP |

#### 65816-Compatible Push/Pull Format

When pushed to the stack (PHP/PLP), flags are packed into one or two bytes in a 65816-compatible format:

```
Standard byte (always pushed):
 Bit 7   6   5   4   3   2   1   0
    ┌───┬───┬───┬───┬───┬───┬───┬───┐
    │ N │ V │ 1 │ B │ D │ I │ Z │ C │
    └───┴───┴───┴───┴───┴───┴───┴───┘

Extended byte (pushed in native mode):
 Bit 7   6   5   4   3   2   1   0
    ┌───┬───┬───┬───┬───┬───┬───┬───┐
    │M1 │M0 │X1 │X0 │ E │ S │ R │ K │
    └───┴───┴───┴───┴───┴───┴───┴───┘
```

### 3.3 Register Window (R0-R63)

When R=1, Direct Page addresses map to hardware registers:

```
DP Offset    Register    Description
$00-$03      R0          General purpose
$04-$07      R1          General purpose
$08-$0B      R2          General purpose
...
$F8-$FB      R62         General purpose
$FC-$FF      R63         General purpose
```

Each register is 32-bit. Byte-lane access:
- Offset $00 = R0[7:0] (when M=8-bit)
- 16-bit ops access aligned half-registers
- 32-bit ops access full register (offset must be aligned)

This gives 6502-style short encodings with register-machine performance.

---

## 4. Processor Modes

> **RTL Reference:** Mode handling in `m65832_core.vhd`, width functions in `m65832_pkg.vhd`

### 4.1 Emulation Mode (E=1)

Binary-compatible 6502 behavior:
- 8-bit A, X, Y (enforced by `get_data_width`/`get_index_width` functions)
- 16-bit PC (relative to VBR)
- Stack at VBR + $0100-$01FF (high byte of SP locked to $01)
- Zero Page at VBR + $0000-$00FF
- 64KB address space window (VBR-relative)

Enter via: `SEC : XCE` (exchange carry with E flag)

### 4.2 Native-16 Mode (E=0, M=01, X=01)

65816-compatible behavior:
- 16-bit A, X, Y (or 8-bit via M/X flags)
- 16-bit PC (B register extends to 32-bit)
- Full 32-bit address space via B register
- Stepping stone for 65816 code migration

### 4.3 Native-32 Mode (E=0, M=10, X=10)

Full 32-bit operation:
- 32-bit A, X, Y
- 32-bit PC
- 32-bit stack pointer (when W=1)
- Flat 32-bit virtual addressing
- Paging to 65-bit physical addresses

Enter via: `CLC : XCE` then `REP #$A0` (set M1, X1)

### 4.4 Mode Transition Summary

```
                    ┌─────────────────┐
                    │  Reset (E=1)    │
                    │  Emulation Mode │
                    └────────┬────────┘
                             │ CLC : XCE
                             ▼
                    ┌─────────────────┐
                    │  Native-16      │
                    │  E=0, M=01,X=01 │
                    └────────┬────────┘
                             │ REP #$A0
                             ▼
                    ┌─────────────────┐
                    │  Native-32      │
                    │  E=0, M=10,X=10 │
                    └─────────────────┘
```

---

## 5. Memory Model

### 5.1 Address Space Layout (Suggested)

```
Virtual Address         Description
─────────────────────────────────────────
$0000_0000 - $0000_FFFF   Legacy 64KB (6502 compatible region)
$0001_0000 - $7FFF_FFFF   User space (code, data, heap)
$8000_0000 - $BFFF_FFFF   Memory-mapped I/O
$C000_0000 - $FFFF_EFFF   Kernel space
$FFFF_F000 - $FFFF_FFFF   Exception vectors, system registers
```

### 5.2 Effective Address Calculation

| Addressing Mode | Calculation | Size |
|-----------------|-------------|------|
| Immediate | operand in instruction | 2-5 bytes |
| Direct Page | D + dp | 2 bytes |
| Direct Page,X | D + dp + X | 2 bytes |
| Direct Page,Y | D + dp + Y | 2 bytes |
| (Direct Page) | [D + dp] | 2 bytes |
| (Direct Page,X) | [D + dp + X] | 2 bytes |
| (Direct Page),Y | [D + dp] + Y | 2 bytes |
| Absolute | B + abs16 | 3 bytes |
| Absolute,X | B + abs16 + X | 3 bytes |
| Absolute,Y | B + abs16 + Y | 3 bytes |
| (Absolute) | [B + abs16] | 3 bytes |
| (Absolute,X) | [B + abs16 + X] | 3 bytes |
| Long (WID prefix) | abs32 | 5 bytes |
| Long,X | abs32 + X | 5 bytes |

### 5.3 Stack Operations

Native mode stack (W=1):
- S is 32-bit, points anywhere
- Push: `S ← S - width; [S] ← value`
- Pull: `value ← [S]; S ← S + width`

Emulation mode:
- S is 8-bit, wraps within $0100-$01FF (relative to VBR)

---

## 6. Instruction Set Overview

> **RTL Reference:** Instruction decoding in `m65832_decoder.vhd`

### 6.1 Instruction Categories

| Category | Examples | Count |
|----------|----------|-------|
| Load/Store | LDA, STA, LDX, STX, LDY, STY, STZ | 7 |
| Arithmetic | ADC, SBC, INC, DEC | 4 |
| Logic | AND, ORA, EOR, BIT, TSB, TRB | 6 |
| Shift/Rotate | ASL, LSR, ROL, ROR | 4 |
| Compare | CMP, CPX, CPY | 3 |
| Branch | BEQ, BNE, BCS, BCC, BMI, BPL, BVS, BVC, BRA, BRL | 10 |
| Jump/Call | JMP, JML, JSR, JSL, RTS, RTL, RTI | 7 |
| Stack | PHA, PLA, PHX, PLX, PHY, PLY, PHP, PLP, PHD, PLD, PHB, PLB | 12 |
| Status | SEC, CLC, SED, CLD, SEI, CLI, CLV, REP, SEP, XCE | 10 |
| Transfer | TAX, TXA, TAY, TYA, TSX, TXS, TXY, TYX, TCD, TDC, TCS, TSC | 12 |
| Block Move | MVN, MVP | 2 |
| System | BRK, COP, NOP, WAI, STP | 5 |
| **Extended: Multiply/Divide** | MUL, MULU, DIV, DIVU | 4 |
| **Extended: Atomic** | CAS, LLI, SCI | 3 |
| **Extended: Base Registers** | SVBR, SB, SD | 3 |
| **Extended: Register Window** | RSET, RCLR | 2 |
| **Extended: System** | TRAP, FENCE, FENCER, FENCEW | 4 |
| **Extended: 64-bit** | LDQ, STQ, TTA, TAT | 4 |
| **Extended: Address** | LEA | 1 |
| **Extended: Status** | REPE, SEPE | 2 |

### 6.2 Instruction Encoding

Most instructions preserve 6502/65816 encodings. M65832 extensions use:

1. **WID Prefix ($42)**: Signals 32-bit immediate or absolute follows
2. **Extended Opcode Page ($02 prefix)**: Extended operations (in native mode only)

```
Standard instruction:     [opcode] [operand...]
Wide immediate/address:   [$42] [opcode] [32-bit operand]
Extended operation:       [$02] [ext-opcode] [operand...]
```

> **Note:** The $02 opcode is COP in emulation mode (E=1). In native mode (E=0), it serves as the extended opcode prefix.

### 6.3 Instruction Timing (Cycles)

| Operation Type | Base Cycles | Notes |
|----------------|-------------|-------|
| Register-to-register | 1-2 | TAX, INX, etc. |
| DP load/store | 2-3 | Fast path via register window |
| Absolute load/store | 3-4 | Plus wait states if needed |
| Branch taken | 3 | +1 if page cross |
| JSR/RTS | 4-6 | Stack operations |
| MUL | 4-8 | Width dependent |
| DIV | 16-32 | Width dependent |
| Memory atomic | 5-10 | Bus lock required |

---

## 7. Addressing Modes

### 7.1 Immediate

Operand is part of instruction. Width determined by M or X flag.

```asm
LDA #$12        ; 8-bit immediate (M=00)
LDA #$1234      ; 16-bit immediate (M=01)
LDA #$12345678  ; 32-bit immediate (M=10)
```

Encoding:
- 8-bit: `[opcode] [imm8]` (2 bytes)
- 16-bit: `[opcode] [imm16-lo] [imm16-hi]` (3 bytes)
- 32-bit: `[opcode] [imm32...]` (5 bytes)

### 7.2 Direct Page

Short encoding, accesses D+offset. The workhorse mode.

```asm
LDA $20         ; A = [D + $20]
STA $40         ; [D + $40] = A
```

When R=1, this accesses the register file:
```asm
RSET            ; Enable register window
LDA $08         ; A = R2 (offset $08 = R2)
```

### 7.3 Direct Page Indexed

```asm
LDA $20,X       ; A = [D + $20 + X]
LDA $20,Y       ; A = [D + $20 + Y]
```

### 7.4 Direct Page Indirect

Pointer at DP location. Width of pointed-to address depends on mode:
- Emulation/Native-16: 16-bit pointer
- Native-32: 32-bit pointer (requires 4 bytes at DP location)

```asm
LDA ($20)       ; ptr = [D + $20]; A = [ptr]
LDA ($20,X)     ; ptr = [D + $20 + X]; A = [ptr]
LDA ($20),Y     ; ptr = [D + $20]; A = [ptr + Y]
```

### 7.5 Absolute

3-byte instruction, 16-bit offset from B register.

```asm
LDA $1234       ; A = [B + $1234]
STA $5678       ; [B + $5678] = A
```

### 7.6 Absolute Indexed

```asm
LDA $1234,X     ; A = [B + $1234 + X]
LDA $1234,Y     ; A = [B + $1234 + Y]
```

### 7.7 Absolute Indirect

```asm
JMP ($1234)     ; ptr = [B + $1234]; PC = ptr
JMP ($1234,X)   ; ptr = [B + $1234 + X]; PC = ptr
```

### 7.8 Long (WID Prefix)

Full 32-bit address literal. Use sparingly.

```asm
WID LDA $12345678     ; A = [$12345678] (absolute)
WID LDA #$DEADBEEF    ; A = $DEADBEEF (immediate)
WID JMP $C0001000     ; PC = $C0001000
```

### 7.9 Relative (Branches)

8-bit signed offset from PC+2 (standard) or 16-bit with BRL.

```asm
BEQ label       ; if Z=1, PC = PC + 2 + offset8
BRL label       ; PC = PC + 3 + offset16
```

---

## 8. Instruction Reference

### 8.1 Load and Store

#### LDA - Load Accumulator
```
LDA #imm        Load immediate
LDA dp          Load from Direct Page
LDA dp,X        Load from Direct Page indexed by X
LDA abs         Load from Absolute
LDA abs,X       Load from Absolute indexed by X
LDA abs,Y       Load from Absolute indexed by Y
LDA (dp)        Load indirect
LDA (dp,X)      Load indexed indirect
LDA (dp),Y      Load indirect indexed
```
Flags affected: N, Z

#### STA - Store Accumulator
```
STA dp          Store to Direct Page
STA dp,X        Store to Direct Page indexed by X  
STA abs         Store to Absolute
STA abs,X       Store to Absolute indexed by X
STA abs,Y       Store to Absolute indexed by Y
STA (dp)        Store indirect
STA (dp,X)      Store indexed indirect
STA (dp),Y      Store indirect indexed
```
Flags affected: None

#### LDX, LDY, STX, STY
Same patterns, for X and Y registers.

### 8.2 Arithmetic

> **RTL Reference:** `m65832_alu.vhd` - Note: BCD mode (D flag) is only supported for 8-bit and 16-bit operations. 32-bit arithmetic is always binary.

#### ADC - Add with Carry
```
ADC #imm        A = A + imm + C
ADC dp          A = A + [dp] + C
ADC abs         A = A + [abs] + C
... (all addressing modes)
```
Flags affected: N, V, Z, C

#### SBC - Subtract with Carry
```
SBC #imm        A = A - imm - !C
SBC dp          A = A - [dp] - !C
... (all addressing modes)
```
Flags affected: N, V, Z, C

#### INC, DEC - Increment/Decrement
```
INC             Increment A
INC dp          Increment memory at dp
INC dp,X        Increment memory at dp+X
INC abs         Increment memory at abs
INC abs,X       Increment memory at abs+X
```
Flags affected: N, Z

### 8.3 Logic

#### AND - Logical AND
```
AND #imm        A = A & imm
AND dp          A = A & [dp]
... (all addressing modes)
```
Flags affected: N, Z

#### ORA - Logical OR
```
ORA #imm        A = A | imm
... (all addressing modes)
```
Flags affected: N, Z

#### EOR - Exclusive OR
```
EOR #imm        A = A ^ imm
... (all addressing modes)
```
Flags affected: N, Z

#### BIT - Bit Test
```
BIT #imm        Z = !(A & imm), N=imm[msb], V=imm[msb-1]
BIT dp          Z = !(A & [dp]), N=[dp][msb], V=[dp][msb-1]
BIT abs         (same pattern)
```
Flags affected: N, V, Z

### 8.4 Shift and Rotate

#### ASL - Arithmetic Shift Left
```
ASL             A = A << 1, C = old MSB
ASL dp          [dp] = [dp] << 1
ASL dp,X
ASL abs
ASL abs,X
```
Flags affected: N, Z, C

#### LSR - Logical Shift Right
```
LSR             A = A >> 1, C = old LSB
... (all addressing modes)
```
Flags affected: N, Z, C

#### ROL - Rotate Left (through Carry)
```
ROL             {C,A} = {A,C} rotated left
... (all addressing modes)
```
Flags affected: N, Z, C

#### ROR - Rotate Right (through Carry)
```
ROR             {A,C} = {C,A} rotated right
... (all addressing modes)
```
Flags affected: N, Z, C

### 8.5 Compare

#### CMP - Compare Accumulator
```
CMP #imm        Flags from A - imm (result discarded)
CMP dp          Flags from A - [dp]
... (all addressing modes)
```
Flags affected: N, Z, C

#### CPX, CPY - Compare X, Y
Same pattern as CMP.

### 8.6 Branch

| Mnemonic | Condition | Flag Test |
|----------|-----------|-----------|
| BEQ | Equal (zero) | Z=1 |
| BNE | Not equal | Z=0 |
| BCS | Carry set | C=1 |
| BCC | Carry clear | C=0 |
| BMI | Minus | N=1 |
| BPL | Plus | N=0 |
| BVS | Overflow set | V=1 |
| BVC | Overflow clear | V=0 |
| BRA | Always | — |
| BRL | Always long | — (16-bit offset) |

### 8.7 Jump and Subroutine

#### JMP - Jump
```
JMP abs         PC = B + abs16
JMP (abs)       PC = [B + abs16]
JMP (abs,X)     PC = [B + abs16 + X]
WID JMP long    PC = abs32
```

#### JSR - Jump to Subroutine
```
JSR abs         Push PC+2; PC = B + abs16
WID JSR long    Push PC+4; PC = abs32
```

#### RTS - Return from Subroutine
```
RTS             PC = Pull + 1
```

#### RTI - Return from Interrupt
```
RTI             P = Pull; PC = Pull
```

### 8.8 Stack Operations

```
PHA             Push A (width per M flag)
PLA             Pull A
PHX             Push X (width per X flag)
PLX             Pull X
PHY             Push Y
PLY             Pull Y
PHP             Push P (status)
PLP             Pull P
PHD             Push D (32-bit)
PLD             Pull D
PHB             Push B (32-bit)
PLB             Pull B
```

### 8.9 Status Flag Operations

```
CLC             C = 0
SEC             C = 1
CLD             D = 0
SED             D = 1
CLI             I = 0 (enable IRQ)
SEI             I = 1 (disable IRQ)
CLV             V = 0

REP #imm        Clear bits in P where imm bit is 1
SEP #imm        Set bits in P where imm bit is 1
```

Extended flag manipulation:
```
REPE #imm       Clear bits in extended P
SEPE #imm       Set bits in extended P
```

### 8.10 Transfer Operations

```
TAX             X = A
TXA             A = X
TAY             Y = A
TYA             A = Y
TSX             X = S
TXS             S = X
TDA             A = D
TDA             D = A
TBA             A = B
TAB             B = A
```

### 8.11 Extended: Multiply and Divide

> **RTL Reference:** Extended opcode handling in `m65832_decoder.vhd`, core execution in `m65832_core.vhd`

#### MUL - Signed Multiply
```
MUL dp          A = A * [dp] (signed)
MUL abs         A = A * [abs] (signed)
```
Result width depends on operand width:
- 8×8→16: A[7:0] × operand → A[15:0]
- 16×16→32: A[15:0] × operand → A[31:0]
- 32×32→64: A × operand → T:A (T=high, A=low)

#### MULU - Unsigned Multiply
Same as MUL, but unsigned arithmetic.

#### DIV - Signed Divide
```
DIV dp          A = A / [dp], T = A % [dp]
DIV abs         A = A / [abs], T = A % [abs]
```
Quotient stored in A, remainder stored in T register.

#### DIVU - Unsigned Divide
Same as DIV, but unsigned arithmetic.

### 8.12 Extended: Atomic Operations

#### CAS - Compare and Swap
```
CAS dp          if [dp] == X then [dp] = A; Z=1 else X = [dp]; Z=0
CAS abs         (same for absolute)
```
Atomic test-and-set. Essential for locks. If comparison fails, X is loaded with the current memory value.

#### LLI - Load Linked
```
LLI dp          A = [dp]; set internal link flag for address
LLI abs
```
Marks the address for subsequent SCI instruction.

#### SCI - Store Conditional
```
SCI dp          if link valid then [dp] = A; Z=1 else Z=0
SCI abs
```
LL/SC pair for lock-free algorithms. Any intervening write to the linked address clears the link, causing SCI to fail (Z=0).

### 8.13 Extended: System Operations

#### SVBR - Set Virtual Base Register
```
SVBR #imm32     VBR = imm32 (supervisor only)
SVBR dp         VBR = [dp]
```

#### SB - Set Base Register
```
SB #imm32       B = imm32
SB dp           B = [dp]
```

#### SD - Set Direct Base
```
SD #imm32       D = imm32
SD dp           D = [dp]
```

#### RSET - Register Window Set
```
RSET            R = 1 (DP accesses register file)
```

#### RCLR - Register Window Clear
```
RCLR            R = 0 (DP accesses memory)
```

#### TRAP - System Call
```
TRAP #imm8      Trigger supervisor trap with code imm8
```
Used for system calls. Saves state, enters supervisor mode, vectors through SYSCALL vector ($0000FFD4).

#### WAI - Wait for Interrupt
```
WAI             Halt until interrupt
```

#### STP - Stop Processor
```
STP             Halt until reset
```

### 8.14 Extended: 64-bit Operations

#### LDQ - Load Quad (64-bit)
```
LDQ dp          Load 64-bit value: T = [dp+4], A = [dp]
LDQ abs         Load 64-bit value: T = [abs+4], A = [abs]
```
Loads a 64-bit value into the T:A register pair (T=high, A=low).

#### STQ - Store Quad (64-bit)
```
STQ dp          Store 64-bit value: [dp+4] = T, [dp] = A
STQ abs         Store 64-bit value: [abs+4] = T, [abs] = A
```
Stores the T:A register pair as a 64-bit value.

#### TTA - Transfer T to A
```
TTA             A = T (copy temp register to accumulator)
```

#### TAT - Transfer A to T
```
TAT             T = A (copy accumulator to temp register)
```

### 8.15 Extended: Address Operations

#### LEA - Load Effective Address
```
LEA dp          A = D + dp (effective address of direct page operand)
LEA dp,X        A = D + dp + X
LEA abs         A = B + abs (effective address of absolute operand)
LEA abs,X       A = B + abs + X
```
Computes the effective address without accessing memory. Useful for pointer arithmetic.

### 8.16 Extended: Memory Barriers

#### FENCE - Full Memory Fence
```
FENCE           Order all loads and stores
```
Ensures all previous memory operations complete before subsequent ones begin.

#### FENCER - Read Fence
```
FENCER          Order all loads
```

#### FENCEW - Write Fence
```
FENCEW          Order all stores
```

### 8.17 Extended: Status Operations

#### REPE - REP for Extended Flags
```
REPE #imm8      Clear bits in extended P where imm8 bit is 1
```
Affects bits M1, M0, X1, X0, E, S, R, K.

#### SEPE - SEP for Extended Flags
```
SEPE #imm8      Set bits in extended P where imm8 bit is 1
```
Affects bits M1, M0, X1, X0, E, S, R, K.

### 8.18 Extended: 32-bit Stack Operations

When using the extended opcode page ($02 prefix):

```
PHD             Push D (32-bit direct page base)
PLD             Pull D
PHB             Push B (32-bit absolute base)
PLB             Pull B
PHVBR           Push VBR (32-bit virtual base register)
PLVBR           Pull VBR
```

These always push/pull full 32-bit values regardless of width flags.

---

## 9. Exceptions and Interrupts

> **RTL Reference:** Vector constants in `m65832_pkg.vhd`

### 9.1 Exception Types

#### Native Mode Vectors (Bank 0)

| Vector | Exception | Description |
|--------|-----------|-------------|
| $0000_FFE4 | COP | Coprocessor instruction |
| $0000_FFE6 | BRK | Software breakpoint |
| $0000_FFE8 | ABORT | Abort signal |
| $0000_FFEA | NMI | Non-maskable interrupt |
| $0000_FFEE | IRQ | Maskable interrupt |

#### M65832 Extended Vectors

| Vector | Exception | Description |
|--------|-----------|-------------|
| $0000_FFD0 | Page Fault | MMU page fault |
| $0000_FFD4 | SYSCALL | System call (TRAP instruction) |
| $0000_FFF8 | Illegal Op | Invalid instruction |

#### Emulation Mode Vectors

| Vector | Exception | Description |
|--------|-----------|-------------|
| $0000_FFF4 | COP | Coprocessor instruction |
| $0000_FFF8 | ABORT | Abort signal |
| $0000_FFFA | NMI | Non-maskable interrupt |
| $0000_FFFC | RESET | Power-on/reset |
| $0000_FFFE | IRQ/BRK | Maskable interrupt or BRK |

### 9.2 Exception Processing

1. Complete current instruction (or abort for faults)
2. Push PC (32-bit)
3. Push P + extended P (16-bit total)
4. Set I=1, S=1 (supervisor mode)
5. Load PC from vector
6. Continue execution

### 9.3 Return from Exception

```asm
RTI             ; Pull P, Pull PC, return to user mode if S was 0
```

### 9.4 6502 Emulation Mode Vectors

When E=1, vectors are relative to VBR:
- IRQ/BRK: VBR + $FFFE
- NMI: VBR + $FFFA
- Reset: VBR + $FFFC

---

## 10. Memory Management Unit

> **RTL Reference:** `m65832_mmu.vhd`

### 10.1 Overview

The MMU translates 32-bit virtual addresses to 65-bit physical addresses using two-level page tables. The implementation features a 16-entry fully-associative TLB with ASID tagging for efficient context switching.

### 10.2 Address Translation

```
Virtual Address (32-bit):
┌──────────┬──────────┬────────────┐
│ L1 Index │ L2 Index │   Offset   │
│  10 bits │  10 bits │   12 bits  │
└──────────┴──────────┴────────────┘
     │           │           │
     │           │           └──────────────────────┐
     │           │                                  │
     ▼           ▼                                  │
┌─────────┐  ┌─────────┐                           │
│ L1 Table│─▶│ L2 Table│                           │
│ 1024 ent│  │ 1024 ent│                           │
└─────────┘  └────┬────┘                           │
                  │                                 │
                  ▼ PPN (53 bits)                   │
    ┌─────────────────────────────┬────────────────┤
    │    Physical Page Number     │     Offset     │
    │         53 bits             │    12 bits     │
    └─────────────────────────────┴────────────────┘
                Physical Address (65-bit)
```

### 10.3 Page Table Entry Format

Each PTE is 64 bits:

```
Bit  63      53-62     12-52        11-8      7-0
    ┌───┬───────────┬────────────┬─────────┬────────┐
    │ V │  Reserved │    PPN     │ Reserved│ Flags  │
    └───┴───────────┴────────────┴─────────┴────────┘

Flags (bits 7-0):
  Bit 0: Present (P)      - Page is valid
  Bit 1: Writable (W)     - Page is writable
  Bit 2: User (U)         - User-accessible
  Bit 3: Write-Through    - Cache write-through
  Bit 4: Cache Disable    - Uncached access
  Bit 5: Accessed (A)     - Page was read
  Bit 6: Dirty (D)        - Page was written
  Bit 7: Execute Disable  - No execute (NX)
```

### 10.4 MMU Control Registers

The MMU registers are memory-mapped at fixed addresses in the system register space:

| Address | Register | Bits | Description |
|---------|----------|------|-------------|
| $FFFFF000 | MMUCR | 32 | MMU Control (enable, fault info) |
| $FFFFF004 | TLBINVAL | 32 | TLB invalidate (write VA to flush) |
| $FFFFF008 | ASID | 8 | Address Space ID (TLB tag) |
| $FFFFF00C | ASIDINVAL | 8 | Invalidate entries with this ASID |
| $FFFFF010 | FAULTVA | 32 | Faulting virtual address |
| $FFFFF014 | PTBR_LO | 32 | Page Table Base low 32 bits |
| $FFFFF018 | PTBR_HI | 33 | Page Table Base high 33 bits |
| $FFFFF01C | TLBFLUSH | 1 | Write 1 to flush entire TLB |

#### Timer Registers (also MMIO)

| Address | Register | Bits | Description |
|---------|----------|------|-------------|
| $FFFFF040 | TIMER_CTRL | 8 | Timer control |
| $FFFFF044 | TIMER_CMP | 32 | Timer compare value |
| $FFFFF048 | TIMER_COUNT | 32 | Current timer count |

#### MMUCR Bits

| Bit | Name | Description |
|-----|------|-------------|
| 0 | PG | Paging enable |
| 1 | WP | Write-protect supervisor pages |
| 2 | NX | No-execute bit enabled |
| 4:3 | FAULTTYPE | Last fault type (00=read, 01=write, 10=exec) |
| 31:5 | Reserved | |

### 10.5 TLB

The current implementation provides:
- 16-entry fully-associative TLB
- 8-bit ASID tagging (no flush needed on context switch if ASID differs)
- Global bit support (entry not flushed on ASID change)
- Round-robin replacement policy
- Unified I/D TLB (no separate instruction and data TLBs)

#### TLB Entry Format (Internal)

```
┌─────────┬──────────┬─────────────┬────────┬──────────┬──────┬───────┬──────────┬────────┬──────────┐
│  valid  │   asid   │     vpn     │  ppn   │  global  │write │ user  │executable│ dirty  │ accessed │
│ (1 bit) │ (8 bits) │  (20 bits)  │(53 bit)│ (1 bit)  │(1 b) │(1 bit)│ (1 bit)  │(1 bit) │ (1 bit)  │
└─────────┴──────────┴─────────────┴────────┴──────────┴──────┴───────┴──────────┴────────┴──────────┘
```

### 10.6 Page Fault Handling

On page fault:
1. Save faulting address to FAULTVA
2. Save fault type to MMUCR
3. Push state
4. Vector to Page Fault handler
5. Handler can fix page table, then RTI

---

## 11. Atomic Operations

> **RTL Reference:** Atomic operation support in `m65832_core.vhd`, extended opcodes in `m65832_decoder.vhd`

### 11.1 Compare-and-Swap (CAS)

```asm
; Atomic increment of [counter]
retry:
    LDA counter         ; Load current value
    TAX                 ; X = expected
    INC                 ; A = new value
    CAS counter         ; If [counter]==X, [counter]=A
    BNE retry           ; Z=0 means failed, retry
```

The CAS instruction atomically compares the memory location with X and, if equal, stores A. The Z flag indicates success (Z=1) or failure (Z=0). On failure, X is loaded with the current memory value.

### 11.2 Load-Linked / Store-Conditional (LL/SC)

```asm
; Lock-free stack push
push_item:
    LLI stack_head      ; A = head, link address marked
    STA new_node+NEXT   ; new_node.next = head
    LDA #new_node       ; A = &new_node
    SCI stack_head      ; Try store (fails if link broken)
    BNE push_item       ; Retry if link broken (Z=0)
```

The LLI (Load Linked) instruction loads a value and sets an internal link flag for that address. The SCI (Store Conditional) instruction stores only if the link is still valid (no intervening write to the address). Z=1 indicates success.

### 11.3 Memory Barriers

```asm
FENCE           ; Full memory fence (order all loads/stores)
FENCER          ; Read fence (order loads)
FENCEW          ; Write fence (order stores)
```

These instructions ensure memory ordering for multiprocessor systems or when interacting with DMA/peripherals.

---

## 12. Privilege Model

> **RTL Reference:** S flag (bit 11) in status register, privilege checking in `m65832_core.vhd`

### 12.1 Privilege Levels

| S Flag | Level | Description |
|--------|-------|-------------|
| 1 | Supervisor | Full access, can modify system registers |
| 0 | User | Restricted, page permissions enforced |

### 12.2 Privileged Operations

Supervisor-only (privilege violation trap if S=0):
- Modify PTBR, MMUCR, ASID, or other MMU control registers
- Execute SVBR (Set VBR)
- Access system register MMIO space ($FFFFF000-$FFFFF0FF)
- Modify E, S bits directly via SEPE/REPE
- Execute STP (Stop Processor)
- Execute WAI (Wait for Interrupt) in some configurations

### 12.3 System Calls

```asm
; User program
    LDA #SYS_WRITE      ; System call number
    STA $00             ; R0 = syscall number (if R=1)
    LDA #fd
    STA $04             ; R1 = file descriptor
    LDA #buffer
    STA $08             ; R2 = buffer address
    LDA #count
    STA $0C             ; R3 = byte count
    TRAP #0             ; Enter supervisor mode

; Kernel trap handler (at vector $FFFF_FFF0)
trap_handler:
    ; S=1 here (supervisor)
    LDA $00             ; Get syscall number from R0
    ; ... dispatch to handler ...
    RTI                 ; Return to user mode
```

---

## 13. Linux ABI Considerations

### 13.1 Register Usage Convention

| Register | Linux ABI Use |
|----------|---------------|
| R0-R7 | Arguments / return values |
| R8-R15 | Caller-saved temporaries |
| R16-R23 | Callee-saved |
| R24-R27 | Reserved for kernel |
| R28 | Global pointer (GP) |
| R29 | Frame pointer (FP) |
| R30 | Link register (LR) - optional |
| R31 | Reserved |
| A | Accumulator (caller-saved) |
| X | Index/scratch (caller-saved) |
| Y | Index/scratch (caller-saved) |
| S | Stack pointer |
| D | Direct page base (points to register window) |
| B | Data segment base (usually 0) |

### 13.2 Function Calling Convention

```asm
; Call: foo(arg0, arg1, arg2)
    LDA arg0
    STA $00             ; R0 = arg0
    LDA arg1
    STA $04             ; R1 = arg1
    LDA arg2
    STA $08             ; R2 = arg2
    JSR foo
    ; Return value in R0 ($00)

foo:
    ; Prologue
    PHA                 ; Save A if needed
    LDA $00             ; arg0 in R0
    ; ... function body ...
    STA $00             ; Return value in R0
    PLA
    RTS
```

### 13.3 Stack Frame

```
High addresses
    ┌─────────────────┐
    │ Caller's frame  │
    ├─────────────────┤ ◀── Previous SP
    │ Return address  │
    ├─────────────────┤
    │ Saved FP (R29)  │
    ├─────────────────┤ ◀── FP (R29)
    │ Local variables │
    │       ...       │
    ├─────────────────┤
    │ Saved registers │
    ├─────────────────┤ ◀── SP
Low addresses
```

### 13.4 System Call Convention

- Syscall number in R0
- Arguments in R1-R6
- Use TRAP #0
- Return value in R0, error in R1

### 13.5 Required Linux Features Checklist

| Feature | M65832 Support |
|---------|----------------|
| Virtual memory / paging | ✅ 2-level page tables |
| User/Supervisor modes | ✅ S flag |
| Page fault handling | ✅ Exception vector |
| Timer interrupt | ✅ IRQ |
| Atomic operations | ✅ CAS, LL/SC |
| Memory barriers | ✅ FENCE |
| Context switch | ✅ Save/restore all regs |
| System calls | ✅ TRAP instruction |
| Little-endian | ✅ Native |

---

## 14. Virtual 6502 Mode

> **Note:** For dedicated 6502 coprocessor execution (with cycle-accurate timing), see [Classic Coprocessor Architecture](M65832_Classic_Coprocessor.md). This section describes the M65832 core's emulation mode.

### 14.1 Overview

The M65832 can run unmodified 6502 code by setting E=1 and configuring VBR to place the 64KB address space anywhere in virtual memory. This mode runs on the main M65832 core with 6502 semantics, but does not provide cycle-accurate timing for classic system emulation.

### 14.2 Setup

```asm
; Supervisor code to set up 6502 environment
    SVBR #$10000000     ; 6502 sees addresses $0000-$FFFF
                        ; mapped to $1000_0000 - $1000_FFFF
    
    ; Load 6502 program at physical location
    ; (Set up page tables so $1000_0000+ is accessible)
    
    ; Enter emulation mode
    SEC
    XCE                 ; E=1, now in 6502 mode
    
    ; Execution continues as if on a 6502
    JMP $C000           ; Actually jumps to $1000_C000
```

### 14.3 Memory Mapping

```
6502 Address    M65832 Virtual Address    Description
─────────────────────────────────────────────────────
$0000-$00FF     VBR + $0000               Zero Page
$0100-$01FF     VBR + $0100               Stack
$0200-$BFFF     VBR + $0200               RAM
$C000-$FFFF     VBR + $C000               ROM / Vectors
```

### 14.4 Interrupts in Emulation Mode

Vectors are VBR-relative:
- NMI: [VBR + $FFFA]
- Reset: [VBR + $FFFC]
- IRQ/BRK: [VBR + $FFFE]

### 14.5 Exiting Emulation Mode

The 6502 code can voluntarily exit via a designated "escape" pattern, or the supervisor can interrupt and switch modes:

```asm
; In 6502 code, use COP to escape to native
    COP #$01            ; Triggers COP handler
    
; COP handler (native mode)
cop_handler:
    CLC
    XCE                 ; Exit emulation mode
    ; Now in native mode, handle escape
```

### 14.6 Multiple 6502 Instances

Run multiple 6502 "virtual machines" simultaneously:

```asm
; Task switch: save 6502 state, load new VBR
task_switch:
    ; Save current 6502 state (A, X, Y, S, P, PC)
    ; ... (push to supervisor stack or task struct)
    
    ; Load new VBR
    SVBR #$20000000     ; Different 64KB window
    
    ; Restore new task's 6502 state
    ; ...
    RTI                 ; Return to 6502 execution
```

---

## 15. Assembly Language Guide

### 15.1 Assembler Directives

```asm
.ORG $1000          ; Set assembly origin
.BYTE $12, $34      ; Emit bytes
.WORD $1234         ; Emit 16-bit word (little-endian)
.LONG $12345678     ; Emit 32-bit word
.ALIGN 4            ; Align to 4-byte boundary
.EQU CONST, $100    ; Define constant
.INCLUDE "file.asm" ; Include another file
.SECTION .text      ; Switch to code section
.SECTION .data      ; Switch to data section
```

### 15.2 Width Suffixes

Explicit width override (optional, usually inferred from M/X flags):

```asm
LDA.B #$12          ; Force 8-bit immediate
LDA.W #$1234        ; Force 16-bit immediate
LDA.L #$12345678    ; Force 32-bit immediate
```

### 15.3 Addressing Mode Syntax

```asm
; Immediate
LDA #$XX            ; # prefix

; Direct Page
LDA $XX             ; 1-byte address

; Absolute
LDA $XXXX           ; 2-byte address

; Long (requires WID or explicit)
LDA $XXXXXXXX       ; 4-byte address (or use WID prefix)

; Indexed
LDA $XX,X           ; DP indexed
LDA $XXXX,X         ; Absolute indexed
LDA $XXXX,Y

; Indirect
LDA ($XX)           ; DP indirect
LDA ($XX,X)         ; Indexed indirect
LDA ($XX),Y         ; Indirect indexed

; Long indirect
LDA [$XX]           ; DP long indirect (32-bit pointer)
LDA [$XX],Y         ; Long indirect indexed
```

### 15.4 Example: Hello World (Native Mode)

```asm
; M65832 Hello World
; Assumes UART at $B0000000

.EQU UART_DATA, $0000   ; B + $0000
.EQU UART_STATUS, $0004 ; B + $0004

.SECTION .text
.ORG $00001000

start:
    ; Enter native-32 mode
    CLC
    XCE                 ; E=0
    REP #$30            ; M=01, X=01 (16-bit first)
    REPE #$A0           ; M=10, X=10 (32-bit)
    
    ; Set up base registers
    SB #$B0000000       ; UART base
    SD #$00010000       ; Direct page for locals
    
    ; Print message
    LDX #0
print_loop:
    LDA message,X
    BEQ done
    
wait_tx:
    LDA UART_STATUS
    AND #$01            ; TX ready bit
    BEQ wait_tx
    
    LDA message,X
    STA UART_DATA
    INX
    BRA print_loop

done:
    STP

message:
    .BYTE "Hello, M65832!", 13, 10, 0
```

### 15.5 Example: Spinlock (Atomic)

```asm
; Spinlock using CAS
.EQU lock, $00          ; Lock variable at DP

acquire_lock:
    LDX #0              ; Expected: 0 (unlocked)
    LDA #1              ; Desired: 1 (locked)
spin:
    CAS lock            ; If [lock]==0, [lock]=1
    BNE spin            ; Z=0 means failed
    ; Lock acquired
    RTS

release_lock:
    STZ lock            ; Store zero
    FENCE               ; Ensure visibility
    RTS
```

### 15.6 Example: Context Switch

```asm
; Save current task, load new task
; Input: R0 = pointer to new task struct
; Task struct: [PC, P, A, X, Y, S, D, B, VBR, R0-R63...]

context_switch:
    ; Save current registers to current task struct
    LDA current_task
    STA $00             ; R0 = current task pointer
    
    ; Save PC (return address is on stack)
    ; ... (complex, involves stack manipulation)
    
    ; Save registers
    LDA $04             ; Self-reference for saving
    ; ... save all registers ...
    
    ; Load new task
    LDA new_task_ptr
    STA current_task
    
    ; Restore new task's registers
    ; ... restore all ...
    
    ; Return to new task
    RTI
```

---

## Appendix A: Opcode Map (Summary)

### A.1 Standard 6502/65816 Opcodes (Preserved)

The base opcode map follows 65816 conventions. Key opcodes:

| Opcode | Mnemonic | Opcode | Mnemonic |
|--------|----------|--------|----------|
| $00 | BRK | $20 | JSR abs |
| $01 | ORA (dp,X) | $21 | AND (dp,X) |
| $05 | ORA dp | $25 | AND dp |
| $09 | ORA # | $29 | AND # |
| $0A | ASL A | $2A | ROL A |
| $0D | ORA abs | $2D | AND abs |
| ... | ... | ... | ... |
| $A9 | LDA # | $A5 | LDA dp |
| $AD | LDA abs | $8D | STA abs |

### A.2 Extension Prefix ($42 = WID)

```
$42 $A9 imm32    WID LDA #imm32    ; 32-bit immediate
$42 $AD abs32    WID LDA abs32     ; 32-bit absolute address
$42 $4C abs32    WID JMP abs32     ; Jump to 32-bit address
```

### A.3 Extended Opcode Page ($02 Prefix)

> **RTL Reference:** Extended opcode decoding in `m65832_decoder.vhd` (lines 210-303)

#### Multiply/Divide Operations
```
$02 $00          MUL dp            ; Signed multiply (dp)
$02 $01          MULU dp           ; Unsigned multiply (dp)
$02 $02          MUL abs           ; Signed multiply (abs)
$02 $03          MULU abs          ; Unsigned multiply (abs)
$02 $04          DIV dp            ; Signed divide (dp)
$02 $05          DIVU dp           ; Unsigned divide (dp)
$02 $06          DIV abs           ; Signed divide (abs)
$02 $07          DIVU abs          ; Unsigned divide (abs)
```

#### Atomic Operations
```
$02 $10          CAS dp            ; Compare and swap (dp)
$02 $11          CAS abs           ; Compare and swap (abs)
$02 $12          LLI dp            ; Load linked (dp)
$02 $13          LLI abs           ; Load linked (abs)
$02 $14          SCI dp            ; Store conditional (dp)
$02 $15          SCI abs           ; Store conditional (abs)
```

#### Base Register Operations
```
$02 $20          SVBR #imm32       ; Set VBR (imm32)
$02 $21          SVBR dp           ; Set VBR (dp)
$02 $22          SB #imm32         ; Set B (imm32)
$02 $23          SB dp             ; Set B (dp)
$02 $24          SD #imm32         ; Set D (imm32)
$02 $25          SD dp             ; Set D (dp)
```

#### Register Window Control
```
$02 $30          RSET              ; Enable register window (R=1)
$02 $31          RCLR              ; Disable register window (R=0)
```

#### System Operations
```
$02 $40          TRAP #imm8        ; System trap
$02 $50          FENCE             ; Full memory fence
$02 $51          FENCER            ; Read fence
$02 $52          FENCEW            ; Write fence
```

#### Extended Status Operations
```
$02 $60          REPE #imm8        ; REP for extended flags
$02 $61          SEPE #imm8        ; SEP for extended flags
```

#### 32-bit Stack Operations
```
$02 $70          PHD               ; Push D (32-bit)
$02 $71          PLD               ; Pull D (32-bit)
$02 $72          PHB               ; Push B (32-bit)
$02 $73          PLB               ; Pull B (32-bit)
$02 $74          PHVBR             ; Push VBR (32-bit)
$02 $75          PLVBR             ; Pull VBR (32-bit)
```

#### Temp Register Operations
```
$02 $86          TTA               ; A = T (temp to accumulator)
$02 $87          TAT               ; T = A (accumulator to temp)
```

#### 64-bit Load/Store
```
$02 $88          LDQ dp            ; Load 64-bit (T:A = [dp])
$02 $89          LDQ abs           ; Load 64-bit (T:A = [abs])
$02 $8A          STQ dp            ; Store 64-bit ([dp] = T:A)
$02 $8B          STQ abs           ; Store 64-bit ([abs] = T:A)
```

#### WAI/STP (Extended)
```
$02 $91          WAI               ; Wait for interrupt
$02 $92          STP               ; Stop processor
```

#### LEA (Load Effective Address)
```
$02 $A0          LEA dp            ; A = effective address of dp
$02 $A1          LEA dp,X          ; A = effective address of dp,X
$02 $A2          LEA abs           ; A = effective address of abs
$02 $A3          LEA abs,X         ; A = effective address of abs,X
```

#### FPU Operations (Reserved Range)
```
$02 $B0-$BB      LDF/STF           ; FPU load/store operations
$02 $C0-$E6      FPU ops           ; FPU arithmetic (reserved)
```

---

## Appendix B: Comparison with Other Architectures

| Feature | 6502 | 65816 | M65832 | ARM32 | RISC-V32 |
|---------|------|-------|--------|-------|----------|
| Data width | 8 | 8/16 | 8/16/32 | 32 | 32 |
| Address space | 64KB | 16MB | 4GB VA | 4GB | 4GB |
| Registers | 3 | 3 | 3 + 64 window | 16 | 32 |
| Load/Store | Memory-to-memory | Memory-to-memory | Memory-to-memory | Load/Store | Load/Store |
| Instruction size | 1-3 | 1-4 | 1-5 | 4 (fixed) | 2-4 |
| Paging | No | No | Yes (65-bit PA) | Yes | Yes |
| Privilege | No | No | Yes (2 levels) | Yes (7+ modes) | Yes (3 levels) |
| Atomics | No | No | CAS, LL/SC | LDREX/STREX | LR/SC, AMO |

---

## Appendix C: Implementation Notes (FPGA)

> **RTL Reference:** All components in `rtl/` directory

### C.1 Resource Estimates (Xilinx Artix-7)

| Component | LUTs | FFs | BRAMs |
|-----------|------|-----|-------|
| M65832 Core | ~5,000 | ~2,000 | 2 |
| Register window (64×32) | ~500 | ~2,048 | 0 |
| MMU + 16-entry TLB | ~2,000 | ~1,500 | 0 |
| 6502 Coprocessor | ~500 | ~100 | 0 |
| Shadow I/O + FIFO | ~200 | ~2,200 | 1 |
| Interleaver | ~100 | ~100 | 0 |
| **Total (with coprocessor)** | ~8,300 | ~8,000 | 3 |

Fits comfortably in XC7A35T with room for peripherals.

### C.2 Target Clock

- Conservative: 50 MHz (verified in simulation)
- Optimized: 100+ MHz (timing closure dependent on FPGA)

### C.3 Execution Model

The M65832 uses a multi-cycle state machine rather than a traditional pipeline. Key states:

```
ST_RESET → ST_FETCH → ST_DECODE → [address phases] → [read/write phases] → ST_EXECUTE → ...
```

| State | Description |
|-------|-------------|
| ST_FETCH | Read opcode byte from PC |
| ST_DECODE | Decode instruction, begin operand fetch |
| ST_ADDR1-4 | Address calculation phases (for indexed/indirect modes) |
| ST_READ1-4 | Memory read phases (width-dependent) |
| ST_EXECUTE | ALU operation, result computation |
| ST_WRITE1-4 | Memory write phases (for store/RMW) |
| ST_PUSH/PULL | Stack operations |
| ST_BRANCH | Branch target calculation |
| ST_VECTOR1-4 | Interrupt/exception vector fetch |
| ST_WAI/STOP | Wait for interrupt / stopped states |
| ST_BM_READ/WRITE | Block move (MVN/MVP) data phases |

### C.4 Module Hierarchy

```
m65832_coprocessor_top        ; Top-level SoC with coprocessor
├── m65832_core               ; Main 32-bit CPU core
│   ├── m65832_regfile        ; Register file (A,X,Y,SP,D,B,VBR,T + window)
│   ├── m65832_alu            ; 8/16/32-bit ALU with BCD
│   ├── m65832_addrgen        ; Address generator with base registers
│   ├── m65832_decoder        ; Instruction decoder
│   └── m65832_mmu            ; Memory management unit
├── m65832_6502_coprocessor   ; 6502 coprocessor wrapper
│   └── mx65                  ; External 6502 core (MX65)
├── m65832_interleave         ; Cycle-accurate interleaver
└── m65832_shadow_io          ; Shadow registers + write FIFO
```

### C.5 Testbenches

Available testbenches in `tb/` directory:

| Testbench | Description |
|-----------|-------------|
| `tb_m65832_core.vhd` | Main core functional tests |
| `tb_m65832_core_smoke.vhd` | Quick smoke test |
| `tb_m65832_mmu.vhd` | MMU and TLB tests |
| `tb_m65832_tlb_flush.vhd` | TLB flush operation tests |
| `tb_m65832_faultva.vhd` | Page fault VA capture tests |
| `tb_m65832_coprocessor.vhd` | Coprocessor integration tests |
| `tb_m65832_coprocessor_soak.vhd` | Long-running soak tests |
| `tb_m65832_interleave.vhd` | Interleaver timing tests |
| `tb_m65832_maincore_timeslice.vhd` | Time-slicing verification |

---

*Document Version: 0.2*  
*Last Updated: January 2026*  
*Status: RTL implemented, simulation verified*
