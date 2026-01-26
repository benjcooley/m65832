# M65832 Instruction Set Reference

A complete, verified reference for all M65832 instructions.

---

## Overview

The M65832 extends the WDC 65C816 instruction set with:
- **32-bit operations** in native-32 mode; 8/16 via Extended ALU
- **Extended ALU** ($02 $80-$97) with mode byte for 8/16/32-bit sized operations
- **New instructions** for multiply, divide, atomics, and system control
- **Extended opcode page ($02)** for new operations

### Compatibility Note

All standard 6502 and 65816 opcodes are preserved. The M65832 adds capabilities without changing existing instruction behavior. Differences from the 65816 are noted where applicable.

---

## Instruction Encoding

### Instruction Formats

| Format | Structure | Size |
|--------|-----------|------|
| Standard | `[opcode]` | 1 byte |
| Standard + imm | `[opcode] [imm8/16/32]` | 2-5 bytes |
| Standard + addr | `[opcode] [addr8/16/32]` | 2-5 bytes |
| Extended | `[$02] [ext-op] [mode] [operands...]` | 3+ bytes |

### Operand Width Rules

The M and X flags control operand widths in emulation/native-16 modes:

| Flag State | Accumulator Width | Index Width |
|------------|-------------------|-------------|
| M/X = 00 | 8-bit | 8-bit |
| M/X = 01 | 16-bit | 16-bit |
| M/X = 10 | 32-bit | 32-bit |
| M/X = 11 | Reserved | Reserved |

In **emulation mode** (E=1), all operations are 8-bit. In **native-32** (M/X=10), standard opcodes are fixed 32-bit; use Extended ALU for 8/16-bit sizing.

---

## Complete Opcode Map

### Standard Opcodes ($00-$FF)

```
     x0       x1       x2       x3       x4       x5       x6       x7
0x   BRK      ORA      EXT      ---      TSB      ORA      ASL      ---
     impl     (dp,X)   prefix   ---      dp       dp       dp       ---

1x   BPL      ORA      ORA      ---      TRB      ORA      ASL      ---
     rel      (dp),Y   (dp)     ---      dp       dp,X     dp,X     ---

2x   JSR      AND      JSL      ---      BIT      AND      ROL      ---
     abs      (dp,X)   long     ---      dp       dp       dp       ---

3x   BMI      AND      AND      ---      BIT      AND      ROL      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,X     ---

4x   RTI      EOR      (3)      ---      MVP      EOR      LSR      ---
     impl     (dp,X)   prefix   ---      src,dst  dp       dp       ---

5x   BVC      EOR      EOR      ---      MVN      EOR      LSR      ---
     rel      (dp),Y   (dp)     ---      src,dst  dp,X     dp,X     ---

6x   RTS      ADC      PER      ---      STZ      ADC      ROR      ---
     impl     (dp,X)   rel16    ---      dp       dp       dp       ---

7x   BVS      ADC      ADC      ---      STZ      ADC      ROR      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,X     ---

8x   BRA      STA      BRL      ---      STY      STA      STX      ---
     rel      (dp,X)   rel16    ---      dp       dp       dp       ---

9x   BCC      STA      STA      ---      STY      STA      STX      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,Y     ---

Ax   LDY      LDA      LDX      ---      LDY      LDA      LDX      ---
     #        (dp,X)   #        ---      dp       dp       dp       ---

Bx   BCS      LDA      LDA      ---      LDY      LDA      LDX      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,Y     ---

Cx   CPY      CMP      REP      ---      CPY      CMP      DEC      ---
     #        (dp,X)   #imm     ---      dp       dp       dp       ---

Dx   BNE      CMP      CMP      ---      PEI      CMP      DEC      ---
     rel      (dp),Y   (dp)     ---      (dp)     dp,X     dp,X     ---

Ex   CPX      SBC      SEP      ---      CPX      SBC      INC      ---
     #        (dp,X)   #imm     ---      dp       dp       dp       ---

Fx   BEQ      SBC      SBC      ---      PEA      SBC      INC      ---
     rel      (dp),Y   (dp)     ---      #imm16   dp,X     dp,X     ---
```

```
     x8       x9       xA       xB       xC       xD       xE       xF
0x   PHP      ORA      ASL      PHD      TSB      ORA      ASL      ORA
     impl     #        A        impl     abs      abs      abs      long

1x   CLC      ORA      INC      TCS      TRB      ORA      ASL      ORA
     impl     abs,Y    A        impl     abs      abs,X    abs,X    long,X

2x   PLP      AND      ROL      PLD      BIT      AND      ROL      AND
     impl     #        A        impl     abs      abs      abs      long

3x   SEC      AND      DEC      TSC      BIT      AND      ROL      AND
     impl     abs,Y    A        impl     abs,X    abs,X    abs,X    long,X

4x   PHA      EOR      LSR      PHK      JMP      EOR      LSR      EOR
     impl     #        A        impl     abs      abs      abs      long

5x   CLI      EOR      PHY      TCD      JML      EOR      LSR      EOR
     impl     abs,Y    impl     impl     long     abs,X    abs,X    long,X

6x   PLA      ADC      ROR      RTL      JMP      ADC      ROR      ADC
     impl     #        A        impl     (abs)    abs      abs      long

7x   SEI      ADC      PLY      TDC      JMP      ADC      ROR      ADC
     impl     abs,Y    impl     impl     (abs,X)  abs,X    abs,X    long,X

8x   DEY      BIT      TXA      PHB      STY      STA      STX      STA
     impl     #        impl     impl     abs      abs      abs      long

9x   TYA      STA      TXS      TXY      STZ      STA      STZ      STA
     impl     abs,Y    impl     impl     abs      abs,X    abs,X    long,X

Ax   TAY      LDA      TAX      PLB      LDY      LDA      LDX      LDA
     impl     #        impl     impl     abs      abs      abs      long

Bx   CLV      LDA      TSX      TYX      LDY      LDA      LDX      LDA
     impl     abs,Y    impl     impl     abs,X    abs,X    abs,Y    long,X

Cx   INY      CMP      DEX      (1)      CPY      CMP      DEC      CMP
     impl     #        impl     prefix   abs      abs      abs      long

Dx   CLD      CMP      PHX      (2)      ---      CMP      DEC      CMP
     impl     abs,Y    impl     prefix   ---      abs,X    abs,X    long,X

Ex   INX      SBC      NOP      ---      CPX      SBC      INC      SBC
     impl     #        impl     ---      abs      abs      abs      long

Fx   SED      SBC      PLX      XCE      ---      SBC      INC      SBC
     impl     abs,Y    impl     impl     ---      abs,X    abs,X    long,X
```


### Extended Opcodes ($02 Prefix)

After the `$02` prefix byte:

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| **Multiply/Divide** | | |
| $00 [dp] | MUL dp | Signed multiply A × [dp] |
| $01 [dp] | MULU dp | Unsigned multiply |
| $02 [abs16] | MUL abs | Signed multiply A × [abs] |
| $03 [abs16] | MULU abs | Unsigned multiply |
| $04 [dp] | DIV dp | Signed divide A / [dp] |
| $05 [dp] | DIVU dp | Unsigned divide |
| $06 [abs16] | DIV abs | Signed divide |
| $07 [abs16] | DIVU abs | Unsigned divide |
| **Atomics** | | |
| $10 [dp] | CAS dp | Compare and Swap |
| $11 [abs16] | CAS abs | Compare and Swap |
| $12 [dp] | LLI dp | Load Linked |
| $13 [abs16] | LLI abs | Load Linked |
| $14 [dp] | SCI dp | Store Conditional |
| $15 [abs16] | SCI abs | Store Conditional |
| **Base Registers** | | |
| $20 [imm32] | SVBR #imm32 | Set VBR immediate (supervisor) |
| $21 [dp] | SVBR dp | Set VBR from memory |
| $22 [imm32] | SB #imm32 | Set B register immediate |
| $23 [dp] | SB dp | Set B from memory |
| $24 [imm32] | SD #imm32 | Set D register immediate |
| $25 [dp] | SD dp | Set D from memory |
| **Register Window** | | |
| $30 | RSET | Enable register window (R=1) |
| $31 | RCLR | Disable register window (R=0) |
| **System** | | |
| $40 [imm8] | TRAP #imm8 | System call trap |
| $50 | FENCE | Full memory fence |
| $51 | FENCER | Read memory fence |
| $52 | FENCEW | Write memory fence |
| **Extended Flags** | | |
| $60 [imm8] | REPE #imm8 | Clear extended P bits |
| $61 [imm8] | SEPE #imm8 | Set extended P bits |
| **32-bit Stack Ops** | | |
| $70 | PHD | Push D (32-bit) |
| $71 | PLD | Pull D (32-bit) |
| $72 | PHB | Push B (32-bit) |
| $73 | PLB | Pull B (32-bit) |
| $74 | PHVBR | Push VBR (32-bit) |
| $75 | PLVBR | Pull VBR (32-bit) |
| **Extended ALU ($80-$97)** | | |
| $80 [mode] [dest?] [src...] | LD | Load with size/target/mode (see below) |
| $81 [mode] [dest?] [src...] | ST | Store with size/target/mode |
| $82 [mode] [dest?] [src...] | ADC | Add with carry |
| $83 [mode] [dest?] [src...] | SBC | Subtract with borrow |
| $84 [mode] [dest?] [src...] | AND | Logical AND |
| $85 [mode] [dest?] [src...] | ORA | Logical OR |
| $86 [mode] [dest?] [src...] | EOR | Exclusive OR |
| $87 [mode] [dest?] [src...] | CMP | Compare |
| $88 [mode] [dest?] [src...] | BIT | Bit test |
| $89 [mode] [dest?] [src...] | TSB | Test and set bits |
| $8A [mode] [dest?] [src...] | TRB | Test and reset bits |
| $8B [mode] [dest?] [src...] | INC | Increment |
| $8C [mode] [dest?] [src...] | DEC | Decrement |
| $8D [mode] [dest?] [src...] | ASL | Arithmetic shift left |
| $8E [mode] [dest?] [src...] | LSR | Logical shift right |
| $8F [mode] [dest?] [src...] | ROL | Rotate left |
| $90 [mode] [dest?] [src...] | ROR | Rotate right |
| $97 [mode] [dest?] [src...] | STZ | Store zero |
| **Barrel Shifter ($98)** | | |
| $98 [op\|cnt] [dest] [src] | SHL/SHR/SAR/ROL/ROR | Multi-bit shift (see below) |
| **Extend Operations ($99)** | | |
| $99 [subop] [dest] [src] | SEXT/ZEXT/CLZ/CTZ/POPCNT | Extend operations (see below) |
| **Temp Register ($9A-$9B)** | | |
| $9A | TTA | Transfer T to A |
| $9B | TAT | Transfer A to T |
| **64-bit Load/Store ($9C-$9F)** | | |
| $9C [dp] | LDQ dp | Load quad (A:T = [dp]) |
| $9D [abs16] | LDQ abs | Load quad |
| $9E [dp] | STQ dp | Store quad ([dp] = A:T) |
| $9F [abs16] | STQ abs | Store quad |
| **Load Effective Address ($A0-$A3)** | | |
| $A0 [dp] | LEA dp | A = D + dp |
| $A1 [dp] | LEA dp,X | A = D + dp + X |
| $A2 [abs16] | LEA abs | A = B + abs |
| $A3 [abs16] | LEA abs,X | A = B + abs + X |
| **FPU Load/Store** | | |
| $B0 [dp] | LDF0 dp | Load F0 from dp (64-bit) |
| $B1 [abs16] | LDF0 abs | Load F0 from abs |
| $B2 [dp] | STF0 dp | Store F0 to dp |
| $B3 [abs16] | STF0 abs | Store F0 to abs |
| $B4-$B7 | LDF1/STF1 | F1 load/store (same pattern) |
| $B8-$BB | LDF2/STF2 | F2 load/store (same pattern) |
| **FPU Single-Precision** | | |
| $C0 | FADD.S | F0 = F1 + F2 |
| $C1 | FSUB.S | F0 = F1 - F2 |
| $C2 | FMUL.S | F0 = F1 × F2 |
| $C3 | FDIV.S | F0 = F1 / F2 |
| $C4 | FNEG.S | F0 = -F1 |
| $C5 | FABS.S | F0 = |F1| |
| $C6 | FCMP.S | Compare F1 to F2 |
| $C7 | F2I.S | A = (int32)F1 |
| $C8 | I2F.S | F0 = (float32)A |
| **FPU Double-Precision** | | |
| $D0-$D8 | (same as above with .D suffix) | Double-precision operations |
| **Reserved FPU** | | |
| $D9-$DF | (reserved) | Trap to software emulation |
| $E0-$FF | (reserved) | Future expansion |

### Extended ALU Instructions ($02 $80-$97)

These instructions provide sized ALU operations with explicit data size, target selection, and full addressing modes. The mode byte encodes size, target, and addressing mode in a single byte.

**Encoding:** `$02 [op] [mode] [dest_dp if target=1] [source_operand...]`

**Mode Byte:** `[size:2][target:1][addr_mode:5]`

```
Bit:   7   6   5   4   3   2   1   0
      └───┬───┘   │   └───────┬───────┘
        SIZE    TARGET    ADDR_MODE
```

**Size (bits 7-6):**

| Value | Size | Immediate Bytes |
|-------|------|-----------------|
| 00 | BYTE (8-bit) | 1 |
| 01 | WORD (16-bit) | 2 |
| 10 | LONG (32-bit) | 4 |
| 11 | (reserved) | — |

**Target (bit 5):**

| Value | Target | Extra Byte |
|-------|--------|------------|
| 0 | Accumulator (A) | No dest_dp byte |
| 1 | Register (Rn) | dest_dp byte follows |

**Addressing Modes (bits 4-0):**

| Mode | Syntax | Description | Operand Bytes |
|------|--------|-------------|---------------|
| $00 | dp | Direct Page / Register | 1 |
| $01 | dp,X | DP Indexed X | 1 |
| $02 | dp,Y | DP Indexed Y | 1 |
| $03 | (dp,X) | Indexed Indirect | 1 |
| $04 | (dp),Y | Indirect Indexed | 1 |
| $05 | (dp) | DP Indirect | 1 |
| $06 | [dp] | DP Indirect Long | 1 |
| $07 | [dp],Y | DP Indirect Long Indexed | 1 |
| $08 | abs | Absolute (B+16) | 2 |
| $09 | abs,X | Absolute Indexed X | 2 |
| $0A | abs,Y | Absolute Indexed Y | 2 |
| $0B | (abs) | Absolute Indirect | 2 |
| $0C | (abs,X) | Absolute Indexed Indirect | 2 |
| $0D | [abs] | Absolute Indirect Long | 2 |
| $0E-$0F | (reserved) | | |
| $10 | abs32 | 32-bit Absolute | 4 |
| $11 | abs32,X | 32-bit Absolute Indexed X | 4 |
| $12 | abs32,Y | 32-bit Absolute Indexed Y | 4 |
| $13 | (abs32) | 32-bit Absolute Indirect | 4 |
| $14 | (abs32,X) | 32-bit Abs Indexed Indirect | 4 |
| $15 | [abs32] | 32-bit Absolute Indirect Long | 4 |
| $16-$17 | (reserved) | | |
| $18 | #imm | Immediate | 1-4 (per size) |
| $19 | A | Accumulator source | 0 |
| $1A | X | X register source | 0 |
| $1B | Y | Y register source | 0 |
| $1C | sr,S | Stack Relative | 1 |
| $1D | (sr,S),Y | Stack Relative Indirect Idx | 1 |
| $1E-$1F | (reserved) | | |

**Extended ALU Opcodes:**

| Opcode | Mnemonic | Operation | Flags |
|--------|----------|-----------|-------|
| $02 $80 | LD | dest = src | N, Z |
| $02 $81 | ST | [addr] = src | — |
| $02 $82 | ADC | dest = dest + src + C | N, V, Z, C |
| $02 $83 | SBC | dest = dest - src - !C | N, V, Z, C |
| $02 $84 | AND | dest = dest & src | N, Z |
| $02 $85 | ORA | dest = dest \| src | N, Z |
| $02 $86 | EOR | dest = dest ^ src | N, Z |
| $02 $87 | CMP | flags from dest - src | N, Z, C |
| $02 $88 | BIT | flags from dest & src | N, V, Z |
| $02 $89 | TSB | [addr] \|= src; Z from old | Z |
| $02 $8A | TRB | [addr] &= ~src; Z from old | Z |
| $02 $8B | INC | dest = dest + 1 | N, Z |
| $02 $8C | DEC | dest = dest - 1 | N, Z |
| $02 $8D | ASL | dest = dest << 1 | N, Z, C |
| $02 $8E | LSR | dest = dest >> 1 | N, Z, C |
| $02 $8F | ROL | dest = {dest, C} <<< 1 | N, Z, C |
| $02 $90 | ROR | dest = {C, dest} >>> 1 | N, Z, C |
| $02 $97 | STZ | [addr] = 0 | — |

**Instruction Length:**

| Target | Base Length | + Source Operand |
|--------|-------------|------------------|
| A (target=0) | 3 bytes | + 0-4 bytes |
| Rn (target=1) | 4 bytes | + 0-4 bytes |

**Assembly Syntax:**

```asm
; A-target operations (traditional style with explicit size)
    LD.B A, R1            ; A = R1 (8-bit)
    LD.W A, #$1234        ; A = $1234 (16-bit)
    ADC.B A, R0           ; A = A + R0 + C (8-bit)
    INC.W A               ; A = A + 1 (16-bit)

; Rn-target operations (register-targeted)
    LD.B R0, R1           ; R0 = R1 (8-bit)
    LD.W R0, #$1234       ; R0 = $1234 (16-bit)
    LD R0, $A0001234      ; R0 = [$A0001234] (32-bit, abs32)
    ADC.B R0, R1          ; R0 = R0 + R1 + C (8-bit)
    ADC R0, #$12345678    ; R0 = R0 + $12345678 + C (32-bit)
    INC.B R5              ; R5 = R5 + 1 (8-bit)
    
; Compare and logical
    CMP.W R0, R1          ; flags from R0 - R1 (16-bit)
    AND R2, #$FF          ; R2 = R2 & $FF (32-bit)
    ORA.B R3, R4          ; R3 = R3 | R4 (8-bit)
```

**Encoding Examples:**

```
; LD.B A, R1 (8-bit, A-target, dp mode)
  02 80 00 04             ; 4 bytes
        └─ size=00, target=0, mode=$00; dest implicit; src=$04

; LD.B R0, R1 (8-bit, Rn-target, dp mode)  
  02 80 20 00 04          ; 5 bytes
        │  │  └─ src=$04 (R1)
        │  └─ dest=$00 (R0)
        └─ size=00, target=1, mode=$00

; ADC.W R0, #$1234 (16-bit, Rn-target, immediate)
  02 82 78 00 34 12       ; 6 bytes
        │  │  └────── imm16 (little-endian)
        │  └─ dest=$00 (R0)
        └─ size=01, target=1, mode=$18

; LD R0, $A0001234 (32-bit, Rn-target, abs32)
  02 80 B0 00 34 12 00 A0 ; 8 bytes
        │  │  └────────── abs32 (little-endian)
        │  └─ dest=$00 (R0)
        └─ size=10, target=1, mode=$10

; INC.B A (8-bit, A-target, implied)
  02 8B 00                ; 3 bytes
        └─ size=00, target=0, mode=$00 (implied for INC)

; INC.B R5 (8-bit, Rn-target, implied)
  02 8B 20 14             ; 4 bytes
        │  └─ dest=$14 (R5)
        └─ size=00, target=1, mode=$00
```

### Barrel Shifter Instructions ($02 $98)

Single-cycle multi-bit shift and rotate operations between registers.

**Encoding:** `$02 $98 [op|cnt] [dest_dp] [src_dp]`

The `[op|cnt]` byte encodes:
- **Bits 7-5:** Operation (0=SHL, 1=SHR, 2=SAR, 3=ROL, 4=ROR)
- **Bits 4-0:** Shift count (0-31), or $1F for shift by A (low 5 bits)

| Op | Operation | Description |
|----|-----------|-------------|
| 0 | SHL | Shift left logical (fill with 0) |
| 1 | SHR | Shift right logical (fill with 0) |
| 2 | SAR | Shift right arithmetic (sign extend) |
| 3 | ROL | Rotate left through carry |
| 4 | ROR | Rotate right through carry |

**Flags Affected:** N, Z, C

**Assembly Syntax:**

```asm
; Fixed shift count:
    SHL R2, R1, #4        ; R2 = R1 << 4
    SHR R3, R1, #8        ; R3 = R1 >> 8
    SAR R4, R2, #4        ; R4 = R2 >>> 4 (arithmetic)
    ROL R5, R4, #1        ; R5 = R4 rotate left 1
    ROR R6, R5, #1        ; R6 = R5 rotate right 1

; Variable shift by A register:
    SHL R2, R1, A         ; R2 = R1 << (A & $1F)
    SHR R3, R1, A         ; R3 = R1 >> (A & $1F)
```

**Instruction Length:** 5 bytes ($02 $98 op|cnt dest src)

### Sign/Zero Extend Instructions ($02 $99)

Extend operations for converting between data sizes.

**Encoding:** `$02 $99 [subop] [dest_dp] [src_dp]`

| Subop | Operation | Description |
|-------|-----------|-------------|
| $00 | SEXT8 | Sign extend 8-bit to 32-bit |
| $01 | SEXT16 | Sign extend 16-bit to 32-bit |
| $02 | ZEXT8 | Zero extend 8-bit to 32-bit |
| $03 | ZEXT16 | Zero extend 16-bit to 32-bit |
| $04 | CLZ | Count leading zeros |
| $05 | CTZ | Count trailing zeros |
| $06 | POPCNT | Population count (count 1 bits) |

**Flags Affected:** N, Z

**Assembly Syntax:**

```asm
    SEXT8 R4, R3          ; R4 = sign_extend_8(R3)
    SEXT16 R5, R3         ; R5 = sign_extend_16(R3)
    ZEXT8 R6, R3          ; R6 = zero_extend_8(R3)
    ZEXT16 R7, R3         ; R7 = zero_extend_16(R3)
    CLZ R8, R1            ; R8 = count_leading_zeros(R1)
    CTZ R9, R1            ; R9 = count_trailing_zeros(R1)
    POPCNT R10, R1        ; R10 = popcount(R1)
```

**Instruction Length:** 5 bytes ($02 $99 subop dest src)

---

## Instruction Reference

Instructions are organized by category. Each entry shows syntax, opcodes, and flags affected.

### Load and Store Instructions

#### LDA - Load Accumulator

Loads a value into the accumulator.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | LDA #imm | $A9 | 2/3/5 | 2 |
| Direct Page | LDA dp | $A5 | 2 | 3 |
| DP Indexed X | LDA dp,X | $B5 | 2 | 4 |
| Absolute | LDA abs | $AD | 3 | 4 |
| Abs Indexed X | LDA abs,X | $BD | 3 | 4+ |
| Abs Indexed Y | LDA abs,Y | $B9 | 3 | 4+ |
| DP Indirect | LDA (dp) | $B2 | 2 | 5 |
| DP Indexed Indirect | LDA (dp,X) | $A1 | 2 | 6 |
| DP Indirect Indexed | LDA (dp),Y | $B1 | 2 | 5+ |
| DP Indirect Long | LDA [dp] | $A7 | 2 | 6 |
| DP Indirect Long Y | LDA [dp],Y | $B7 | 2 | 6+ |
| Absolute Long | LDA long | $AF | 4 | 5 |
| Abs Long Indexed X | LDA long,X | $BF | 4 | 5 |
| Stack Relative | LDA sr,S | $A3 | 2 | 4 |
| SR Indirect Indexed | LDA (sr,S),Y | $B3 | 2 | 7 |

**Flags Affected:** N, Z

**Notes:**
- Byte count for immediate depends on M flag: 2 (8-bit), 3 (16-bit), 5 (32-bit)
- "+1 cycle if page boundary crossed" for indexed modes

#### STA - Store Accumulator

Stores the accumulator to memory.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | STA dp | $85 | 2 |
| DP Indexed X | STA dp,X | $95 | 2 |
| Absolute | STA abs | $8D | 3 |
| Abs Indexed X | STA abs,X | $9D | 3 |
| Abs Indexed Y | STA abs,Y | $99 | 3 |
| DP Indirect | STA (dp) | $92 | 2 |
| DP Indexed Indirect | STA (dp,X) | $81 | 2 |
| DP Indirect Indexed | STA (dp),Y | $91 | 2 |
| DP Indirect Long | STA [dp] | $87 | 2 |
| DP Indirect Long Y | STA [dp],Y | $97 | 2 |
| Absolute Long | STA long | $8F | 4 |
| Abs Long Indexed X | STA long,X | $9F | 4 |
| Stack Relative | STA sr,S | $83 | 2 |
| SR Indirect Indexed | STA (sr,S),Y | $93 | 2 |

**Flags Affected:** None

#### LDX - Load X Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | LDX #imm | $A2 | 2/3/5 |
| Direct Page | LDX dp | $A6 | 2 |
| DP Indexed Y | LDX dp,Y | $B6 | 2 |
| Absolute | LDX abs | $AE | 3 |
| Abs Indexed Y | LDX abs,Y | $BE | 3 |

**Flags Affected:** N, Z

#### LDY - Load Y Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | LDY #imm | $A0 | 2/3/5 |
| Direct Page | LDY dp | $A4 | 2 |
| DP Indexed X | LDY dp,X | $B4 | 2 |
| Absolute | LDY abs | $AC | 3 |
| Abs Indexed X | LDY abs,X | $BC | 3 |

**Flags Affected:** N, Z

#### STX - Store X Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | STX dp | $86 | 2 |
| DP Indexed Y | STX dp,Y | $96 | 2 |
| Absolute | STX abs | $8E | 3 |

**Flags Affected:** None

#### STY - Store Y Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | STY dp | $84 | 2 |
| DP Indexed X | STY dp,X | $94 | 2 |
| Absolute | STY abs | $8C | 3 |

**Flags Affected:** None

#### STZ - Store Zero

Stores zero to memory. Useful for clearing memory without affecting accumulator.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | STZ dp | $64 | 2 |
| DP Indexed X | STZ dp,X | $74 | 2 |
| Absolute | STZ abs | $9C | 3 |
| Abs Indexed X | STZ abs,X | $9E | 3 |

**Flags Affected:** None

---

### Arithmetic Instructions

#### ADC - Add with Carry

Adds the operand and carry flag to the accumulator.

**Operation:** `A = A + M + C`

Uses all LDA addressing modes. **Flags Affected:** N, V, Z, C

```asm
; 32-bit addition example
    CLC                 ; Clear carry before add
    LDA num1
    ADC num2
    STA result
```

**Decimal Mode:** When D=1, performs BCD addition (8/16-bit only; 32-bit ignores D flag).

#### SBC - Subtract with Borrow

Subtracts the operand and inverse carry from the accumulator.

**Operation:** `A = A - M - (1 - C)`

Uses all LDA addressing modes. **Flags Affected:** N, V, Z, C

```asm
; Subtraction (set carry first)
    SEC
    LDA num1
    SBC num2
    STA result
```

#### INC - Increment

Increments memory or accumulator by one.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Accumulator | INC | $1A | 1 |
| Direct Page | INC dp | $E6 | 2 |
| DP Indexed X | INC dp,X | $F6 | 2 |
| Absolute | INC abs | $EE | 3 |
| Abs Indexed X | INC abs,X | $FE | 3 |

**Flags Affected:** N, Z

#### DEC - Decrement

Decrements memory or accumulator by one.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Accumulator | DEC | $3A | 1 |
| Direct Page | DEC dp | $C6 | 2 |
| DP Indexed X | DEC dp,X | $D6 | 2 |
| Absolute | DEC abs | $CE | 3 |
| Abs Indexed X | DEC abs,X | $DE | 3 |

**Flags Affected:** N, Z

#### INX / INY / DEX / DEY - Index Register Inc/Dec

| Instruction | Opcode | Operation |
|-------------|--------|-----------|
| INX | $E8 | X = X + 1 |
| INY | $C8 | Y = Y + 1 |
| DEX | $CA | X = X - 1 |
| DEY | $88 | Y = Y - 1 |

**Flags Affected:** N, Z

---

### Logic Instructions

#### AND - Logical AND

**Operation:** `A = A & M`

Uses all LDA addressing modes. **Flags Affected:** N, Z

#### ORA - Logical OR

**Operation:** `A = A | M`

Uses all LDA addressing modes. **Flags Affected:** N, Z

#### EOR - Exclusive OR

**Operation:** `A = A ^ M`

Uses all LDA addressing modes. **Flags Affected:** N, Z

#### BIT - Bit Test

Tests bits in memory against the accumulator.

**Operation:**
- Z = !(A & M)
- N = M[msb]
- V = M[msb-1]

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | BIT #imm | $89 | 2/3/5 |
| Direct Page | BIT dp | $24 | 2 |
| DP Indexed X | BIT dp,X | $34 | 2 |
| Absolute | BIT abs | $2C | 3 |
| Abs Indexed X | BIT abs,X | $3C | 3 |

**Flags Affected:** N, V, Z (immediate mode only affects Z)

#### TSB - Test and Set Bits

**Operation:** `M = M | A; Z = !(M_original & A)`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | TSB dp | $04 | 2 |
| Absolute | TSB abs | $0C | 3 |

**Flags Affected:** Z

#### TRB - Test and Reset Bits

**Operation:** `M = M & ~A; Z = !(M_original & A)`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | TRB dp | $14 | 2 |
| Absolute | TRB abs | $1C | 3 |

**Flags Affected:** Z

---

### Shift and Rotate Instructions

#### ASL - Arithmetic Shift Left

**Operation:** `C ← [msb] ← [bits] ← 0`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Accumulator | ASL | $0A | 1 |
| Direct Page | ASL dp | $06 | 2 |
| DP Indexed X | ASL dp,X | $16 | 2 |
| Absolute | ASL abs | $0E | 3 |
| Abs Indexed X | ASL abs,X | $1E | 3 |

**Flags Affected:** N, Z, C

#### LSR - Logical Shift Right

**Operation:** `0 → [msb] → [bits] → C`

Same addressing modes as ASL. **Flags Affected:** N (always 0), Z, C

#### ROL - Rotate Left through Carry

**Operation:** `C ← [msb] ← [bits] ← old_C`

Same addressing modes as ASL. **Flags Affected:** N, Z, C

#### ROR - Rotate Right through Carry

**Operation:** `old_C → [msb] → [bits] → C`

Same addressing modes as ASL. **Flags Affected:** N, Z, C

---

### Compare Instructions

#### CMP - Compare Accumulator

**Operation:** Sets flags from `A - M` (result discarded)

Uses all LDA addressing modes. **Flags Affected:** N, Z, C

```asm
; Compare and branch pattern
    LDA value
    CMP #100
    BCC less_than       ; Branch if A < 100
    BEQ equal           ; Branch if A == 100
    ; else A > 100
```

#### CPX - Compare X Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | CPX #imm | $E0 | 2/3/5 |
| Direct Page | CPX dp | $E4 | 2 |
| Absolute | CPX abs | $EC | 3 |

**Flags Affected:** N, Z, C

#### CPY - Compare Y Register

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | CPY #imm | $C0 | 2/3/5 |
| Direct Page | CPY dp | $C4 | 2 |
| Absolute | CPY abs | $CC | 3 |

**Flags Affected:** N, Z, C

---

### Branch Instructions

All branches use 8-bit signed relative addressing (range: -128 to +127 from PC+2).

| Mnemonic | Opcode | Condition | Flag Test |
|----------|--------|-----------|-----------|
| BPL | $10 | Plus | N = 0 |
| BMI | $30 | Minus | N = 1 |
| BVC | $50 | Overflow Clear | V = 0 |
| BVS | $70 | Overflow Set | V = 1 |
| BCC | $90 | Carry Clear | C = 0 |
| BCS | $B0 | Carry Set | C = 1 |
| BNE | $D0 | Not Equal | Z = 0 |
| BEQ | $F0 | Equal | Z = 1 |
| BRA | $80 | Always | — |

**Flags Affected:** None

**Cycles:** 2 (not taken), 3 (taken), +1 if page boundary crossed

#### BRL - Branch Long

16-bit signed relative offset (range: -32768 to +32767).

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BRL rel16 | $82 | 3 | 4 |

---

### Jump and Subroutine Instructions

#### JMP - Jump

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute | JMP abs | $4C | 3 | 3 |
| Indirect | JMP (abs) | $6C | 3 | 5 |
| Indexed Indirect | JMP (abs,X) | $7C | 3 | 6 |

#### JML - Jump Long

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute Long | JML long | $5C | 4 | 4 |
| Indirect Long | JML [abs] | $DC | 3 | 6 |

#### JSR - Jump to Subroutine

Pushes return address (PC-1) and jumps.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute | JSR abs | $20 | 3 | 6 |

#### JSL - Jump to Subroutine Long

Pushes full 24/32-bit return address.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute Long | JSL long | $22 | 4 | 8 |

#### RTS - Return from Subroutine

**Operation:** `PC = Pull + 1`

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RTS | $60 | 1 | 6 |

#### RTL - Return from Subroutine Long

Returns from JSL, pulling full return address.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RTL | $6B | 1 | 6 |

#### RTI - Return from Interrupt

**Operation:** `P = Pull; PC = Pull`

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RTI | $40 | 1 | 6-7 |

In native mode, also restores program bank.

---

### Stack Instructions

#### Push Instructions

| Instruction | Opcode | Description |
|-------------|--------|-------------|
| PHA | $48 | Push A (width per M flag) |
| PHX | $DA | Push X (width per X flag) |
| PHY | $5A | Push Y (width per X flag) |
| PHP | $08 | Push P (processor status) |
| PHD | $0B | Push D (16-bit in 65816 mode) |
| PHB | $8B | Push B (data bank in 65816, 32-bit in M65832) |
| PHK | $4B | Push program bank |

#### Pull Instructions

| Instruction | Opcode | Description | Flags |
|-------------|--------|-------------|-------|
| PLA | $68 | Pull A | N, Z |
| PLX | $FA | Pull X | N, Z |
| PLY | $7A | Pull Y | N, Z |
| PLP | $28 | Pull P | All |
| PLD | $2B | Pull D | N, Z |
| PLB | $AB | Pull B | N, Z |

#### Special Stack Instructions

| Instruction | Opcode | Bytes | Description |
|-------------|--------|-------|-------------|
| PEA #imm16 | $F4 | 3 | Push Effective Absolute |
| PEI (dp) | $D4 | 2 | Push Effective Indirect |
| PER rel16 | $62 | 3 | Push Effective Relative |

---

### Transfer Instructions

| Instruction | Opcode | Operation | Flags |
|-------------|--------|-----------|-------|
| TAX | $AA | X = A | N, Z |
| TXA | $8A | A = X | N, Z |
| TAY | $A8 | Y = A | N, Z |
| TYA | $98 | A = Y | N, Z |
| TSX | $BA | X = S | N, Z |
| TXS | $9A | S = X | — |
| TXY | $9B | Y = X | N, Z |
| TYX | $BB | X = Y | N, Z |
| TCD | $5B | D = A (16-bit C) | N, Z |
| TDC | $7B | A = D (16-bit C) | N, Z |
| TCS | $1B | S = A (16-bit C) | — |
| TSC | $3B | A = S (16-bit C) | N, Z |

---

### Status Flag Instructions

#### Clear/Set Single Flags

| Instruction | Opcode | Operation |
|-------------|--------|-----------|
| CLC | $18 | C = 0 |
| SEC | $38 | C = 1 |
| CLI | $58 | I = 0 (enable IRQ) |
| SEI | $78 | I = 1 (disable IRQ) |
| CLD | $D8 | D = 0 |
| SED | $F8 | D = 1 |
| CLV | $B8 | V = 0 |

#### REP - Reset Processor Status Bits

**Operation:** `P = P & ~imm`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | REP #imm8 | $C2 | 2 |

```asm
REP #$30        ; Clear M and X (enable 16-bit mode)
REP #$20        ; Clear M only (16-bit accumulator)
```

#### SEP - Set Processor Status Bits

**Operation:** `P = P | imm`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | SEP #imm8 | $E2 | 2 |

```asm
SEP #$30        ; Set M and X (enable 8-bit mode)
```

#### XCE - Exchange Carry with Emulation

**Operation:** Swap C flag with E flag

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Implied | XCE | $FB | 1 |

```asm
; Enter native mode
    CLC             ; C = 0
    XCE             ; E = 0 (native), C = old_E

; Enter emulation mode
    SEC             ; C = 1
    XCE             ; E = 1 (emulation), C = old_E
```

---

### Block Move Instructions

#### MVN - Move Negative (Decrementing)

Moves block of memory with decrementing addresses.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Block | MVN src,dst | $54 | 3 |

**Setup:** X = source addr, Y = dest addr, A = count - 1

#### MVP - Move Positive (Incrementing)

Moves block of memory with incrementing addresses.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Block | MVP src,dst | $44 | 3 |

**Setup:** X = source end addr, Y = dest end addr, A = count - 1

```asm
; Copy 256 bytes from $1000 to $2000
    LDX #$1000      ; Source start
    LDY #$2000      ; Dest start
    LDA #$FF        ; Count - 1
    MVN #$00,#$00   ; Source bank, dest bank
```

---

### Control Instructions

#### BRK - Software Break

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | BRK | $00 | 2 | 7 |

In native mode, sets S=1 (supervisor) and vectors through native break vector.

#### COP - Coprocessor

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | COP #sig | $02 | 2 | 7 |

In native mode on M65832, $02 is the extended opcode prefix instead.

#### NOP - No Operation

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | NOP | $EA | 1 | 2 |

#### WAI - Wait for Interrupt

Halts processor until interrupt received.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | WAI | $CB | 1 | 3+ |

#### STP - Stop Processor

Halts processor until hardware reset.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | STP | $DB | 1 | 2 |

---

## M65832 New Instructions

### Multiply Instructions

#### MUL - Signed Multiply

**Operation:** `A = A × M` (signed)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | MUL dp | $02 $00 | 3 | 8-16 |
| Absolute | MUL abs | $02 $02 | 4 | 8-16 |

**Flags Affected:** N, Z, V (overflow if result doesn't fit)

**Width Behavior:**
- 8-bit: A[7:0] × M[7:0] → A[15:0] (16-bit result)
- 16-bit: A[15:0] × M[15:0] → A[31:0] (32-bit result)
- 32-bit: A[31:0] × M[31:0] → T[31:0]:A[31:0] (64-bit result, high word in T)

```asm
; 32-bit multiply with 64-bit result
    LDA multiplier
    MUL multiplicand
    ; Low 32 bits in A, high 32 bits in T
    STA result_lo
    TTA                 ; Get T register
    STA result_hi
```

#### MULU - Unsigned Multiply

Same as MUL but treats operands as unsigned.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | MULU dp | $02 $01 | 3 |
| Absolute | MULU abs | $02 $03 | 4 |

### Divide Instructions

#### DIV - Signed Divide

**Operation:** `T = A % M; A = A / M` (signed)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | DIV dp | $02 $04 | 3 | 20-40 |
| Absolute | DIV abs | $02 $06 | 4 | 20-40 |

**Flags Affected:** N, Z, V (set on divide by zero)

```asm
; 32-bit division
    LDA dividend
    DIV divisor
    STA quotient
    TTA                 ; Get remainder from T
    STA remainder
```

#### DIVU - Unsigned Divide

Same as DIV but treats operands as unsigned.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | DIVU dp | $02 $05 | 3 |
| Absolute | DIVU abs | $02 $07 | 4 |

---

### Atomic Instructions

These instructions provide hardware support for lock-free programming.

#### CAS - Compare and Swap

**Operation:**
```
atomic {
    if [M] == X then
        [M] = A
        Z = 1
    else
        X = [M]
        Z = 0
}
```

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | CAS dp | $02 $10 | 3 | 8 |
| Absolute | CAS abs | $02 $11 | 4 | 9 |

**Flags Affected:** Z

```asm
; Spinlock acquisition
acquire_lock:
    LDX #0              ; Expected: 0 (unlocked)
    LDA #1              ; Desired: 1 (locked)
spin:
    CAS lock
    BNE spin            ; Retry if failed (Z=0)
    ; Lock acquired
    RTS

; Atomic increment
atomic_inc:
    LDA counter
retry:
    TAX                 ; X = expected value
    INC                 ; A = new value
    CAS counter
    BNE retry           ; Retry if CAS failed
    RTS
```

#### LLI - Load Linked

**Operation:** `A = [M]; set_link(address_of_M)`

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | LLI dp | $02 $12 | 3 | 4 |
| Absolute | LLI abs | $02 $13 | 4 | 5 |

**Flags Affected:** N, Z

Sets an internal "link" flag for the memory address. The link is cleared by any store to that address (by any core).

#### SCI - Store Conditional

**Operation:**
```
if link_valid then
    [M] = A
    Z = 1
else
    Z = 0
```

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | SCI dp | $02 $14 | 3 | 5 |
| Absolute | SCI abs | $02 $15 | 4 | 6 |

**Flags Affected:** Z

```asm
; Lock-free stack push using LL/SC
push_item:
    LLI stack_head      ; A = current head, link address
    STA new_node+NEXT   ; new_node.next = head
    LEA new_node        ; A = address of new_node
    SCI stack_head      ; Try to update head
    BNE push_item       ; Retry if link broken
    RTS
```

---

### Memory Fence Instructions

| Instruction | Opcode | Description |
|-------------|--------|-------------|
| FENCE | $02 $50 | Full memory fence - all loads/stores before complete before any after |
| FENCER | $02 $51 | Read fence - all reads before complete before any reads after |
| FENCEW | $02 $52 | Write fence - all writes before complete before any writes after |

```asm
; Release a lock with proper ordering
release_lock:
    FENCE               ; Ensure all critical section writes are visible
    STZ lock            ; Clear lock
    RTS
```

---

### Base Register Instructions

#### SVBR - Set Virtual Base Register

Sets the VBR register (supervisor only). Used to position the 6502 emulation window.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | SVBR #imm32 | $02 $20 | 6 |
| Direct Page | SVBR dp | $02 $21 | 3 |

```asm
; Set up 6502 emulation at $10000000
    SVBR #$10000000
```

#### SB - Set Base Register

Sets the B register (absolute addressing base).

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | SB #imm32 | $02 $22 | 6 |
| Direct Page | SB dp | $02 $23 | 3 |

```asm
; Set absolute base to I/O region
    SB #$B0000000
    LDA B+$1000         ; Accesses $B0001000 (B + $1000)
```

#### SD - Set Direct Base Register

Sets the D register (direct page base).

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | SD #imm32 | $02 $24 | 6 |
| Direct Page | SD dp | $02 $25 | 3 |

---

### Register Window Instructions

The register window provides 64 × 32-bit hardware registers accessible via direct page addressing when R=1.

#### RSET - Register Window Set

**Operation:** `R = 1`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Implied | RSET | $02 $30 | 2 |

Enables register window mode. Direct page accesses go to hardware registers:
- `$00-$03` = R0
- `$04-$07` = R1
- ...
- `$FC-$FF` = R63

```asm
    RSET                ; Enable register window
    LDA $00             ; A = R0
    STA $04             ; R1 = A
    INC $08             ; R2++
```

#### RCLR - Register Window Clear

**Operation:** `R = 0`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Implied | RCLR | $02 $31 | 2 |

Disables register window. Direct page accesses go to memory at D + offset.

---

### Extended Status Instructions

#### REPE - Reset Extended Processor Status

**Operation:** `ExtendedP = ExtendedP & ~imm`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | REPE #imm8 | $02 $60 | 3 |

Extended P bits:
- Bit 7: M1 (accumulator width high bit)
- Bit 6: M0 (accumulator width low bit)
- Bit 5: X1 (index width high bit)
- Bit 4: X0 (index width low bit)
- Bit 3: E (emulation mode - read-only here)
- Bit 2: S (supervisor mode)
- Bit 1: R (register window)
- Bit 0: K (compatibility mode)

```asm
; Switch to 32-bit mode (M=10, X=10)
    REP #$30            ; First set M=01, X=01 (16-bit)
    REPE #$A0           ; Then set M1 and X1 for 32-bit
```

#### SEPE - Set Extended Processor Status

**Operation:** `ExtendedP = ExtendedP | imm`

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Immediate | SEPE #imm8 | $02 $61 | 3 |

---

### System Instructions

#### TRAP - System Call Trap

Triggers a software interrupt for system calls.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | TRAP #imm8 | $02 $40 | 3 | 8 |

**Operation:**
1. Push PC (32-bit)
2. Push P (extended)
3. Set S=1 (supervisor mode), I=1 (disable IRQ)
4. PC = [TRAP_VECTOR + imm8 × 4]

```asm
; System call example
    LDA #SYS_WRITE
    STA R0              ; R0 = syscall number
    LDA #fd
    STA R1              ; R1 = file descriptor
    LDA #buffer
    STA R2              ; R2 = buffer address
    LDA #count
    STA R3              ; R3 = byte count
    TRAP #0             ; Invoke kernel
```

---

### Load Effective Address

#### LEA - Load Effective Address

Computes an effective address without accessing memory.

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | LEA dp | $02 $A0 | 3 | 2 |
| DP Indexed X | LEA dp,X | $02 $A1 | 3 | 2 |
| Absolute | LEA abs | $02 $A2 | 4 | 2 |
| Abs Indexed X | LEA abs,X | $02 $A3 | 4 | 2 |

**Flags Affected:** None

```asm
; Get address of array element
    SD #data_segment
    LEA array,X         ; A = D + array_offset + X
```

---

### Temporary Register Instructions

The T register holds the high word from 64-bit multiply results and the remainder from divide operations.

#### TTA - Transfer T to A

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Implied | TTA | $02 $9A | 2 |

#### TAT - Transfer A to T

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Implied | TAT | $02 $9B | 2 |

---

### 64-bit Load/Store

#### LDQ - Load Quad

Loads 64 bits into A (low) and T (high).

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | LDQ dp | $02 $9C | 3 |
| Absolute | LDQ abs | $02 $9D | 4 |

#### STQ - Store Quad

Stores A (low) and T (high) as 64 bits.

| Mode | Syntax | Opcode | Bytes |
|------|--------|--------|-------|
| Direct Page | STQ dp | $02 $9E | 3 |
| Absolute | STQ abs | $02 $9F | 4 |

---

### Data and Address Sizing (32-bit Mode)

In 32-bit mode, data and address sizing is handled differently for traditional vs. extended instructions:

**Traditional 6502/65816 Instructions:**
- Data size is **always 32-bit** in 32-bit mode
- Address size is determined by operand format:
  - `B+$XXXX` = B-relative 16-bit (default)
  - 32-bit absolute is **Extended ALU only**
- M/X width flags are ignored for sizing in 32-bit mode

**Extended ALU Instructions ($02 $80-$97):**
- Data size is encoded in the mode byte (bits 7-6): BYTE, WORD, or LONG
- Address mode is encoded in the mode byte (bits 4-0)
- Use `.B`, `.W`, `.L` suffixes in assembly
- `$42` is reserved/unused in 32-bit mode

**For sized operations, use Extended ALU:**
```asm
; 8-bit operations - use Extended ALU
    LD.B R0, #$12           ; $02 $80 $38 $00 $12

; 16-bit operations - use Extended ALU  
    LD.W R0, #$1234         ; $02 $80 $78 $00 $34 $12

; 32-bit operations - Extended ALU (default size)
    LD R0, #$12345678       ; $02 $80 $B8 $00 $78 $56 $34 $12
```

---

### Floating-Point Instructions

The M65832 includes optional FPU support with three 64-bit registers (F0, F1, F2).

#### FPU Load/Store

| Instruction | Opcode | Description |
|-------------|--------|-------------|
| LDF0 dp | $02 $B0 | F0 = [dp..dp+7] |
| LDF0 abs | $02 $B1 | F0 = [abs..abs+7] |
| STF0 dp | $02 $B2 | [dp..dp+7] = F0 |
| STF0 abs | $02 $B3 | [abs..abs+7] = F0 |
| LDF1 dp | $02 $B4 | F1 = [dp..dp+7] |
| LDF1 abs | $02 $B5 | F1 = [abs..abs+7] |
| STF1 dp | $02 $B6 | [dp..dp+7] = F1 |
| STF1 abs | $02 $B7 | [abs..abs+7] = F1 |
| LDF2 dp | $02 $B8 | F2 = [dp..dp+7] |
| LDF2 abs | $02 $B9 | F2 = [abs..abs+7] |
| STF2 dp | $02 $BA | [dp..dp+7] = F2 |
| STF2 abs | $02 $BB | [abs..abs+7] = F2 |

#### FPU Arithmetic

Single-precision operations (use low 32 bits):

| Instruction | Opcode | Operation |
|-------------|--------|-----------|
| FADD.S | $02 $C0 | F0 = F1 + F2 |
| FSUB.S | $02 $C1 | F0 = F1 - F2 |
| FMUL.S | $02 $C2 | F0 = F1 × F2 |
| FDIV.S | $02 $C3 | F0 = F1 / F2 |
| FNEG.S | $02 $C4 | F0 = -F1 |
| FABS.S | $02 $C5 | F0 = |F1| |
| FCMP.S | $02 $C6 | Compare F1 to F2 |
| F2I.S | $02 $C7 | A = (int32)F1 |
| I2F.S | $02 $C8 | F0 = (float32)A |

Double-precision operations (use full 64 bits):

| Instruction | Opcode | Operation |
|-------------|--------|-----------|
| FADD.D | $02 $D0 | F0 = F1 + F2 |
| FSUB.D | $02 $D1 | F0 = F1 - F2 |
| FMUL.D | $02 $D2 | F0 = F1 × F2 |
| FDIV.D | $02 $D3 | F0 = F1 / F2 |
| FNEG.D | $02 $D4 | F0 = -F1 |
| FABS.D | $02 $D5 | F0 = |F1| |
| FCMP.D | $02 $D6 | Compare F1 to F2 |
| F2I.D | $02 $D7 | A = (int64)F1 |
| I2F.D | $02 $D8 | F0 = (float64)A |

**FCMP Flags:**
- Z = 1 if F1 == F2
- C = 1 if F1 >= F2
- N = 1 if F1 < F2

**Reserved FPU opcodes** ($D9-$DF, $E0-$E6) trap to software emulation via the TRAP mechanism.

---

## MMIO Timer Registers

Timer registers are memory-mapped in the MMIO region (addresses shown are full 32-bit):

| Register | Address | Access | Description |
|----------|---------|--------|-------------|
| TIMER_CTRL  | $FFFFF040 | R/W | Control/status (bit 7 reflects pending) |
| TIMER_CMP   | $FFFFF044 | R/W | 32-bit compare value (little-endian) |
| TIMER_COUNT | $FFFFF048 | R/W | 32-bit count value (little-endian) |

### TIMER_CTRL Bits

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | ENABLE | Enable timer counting |
| 1 | PERIODIC | Auto-rearm: allow repeated compare without clearing latch |
| 2 | IRQ_EN | Enable timer IRQ generation |
| 3 | CLEAR | Clear pending; also resets COUNT to 0 |
| 7 | PENDING | Read-only: reflects pending interrupt state |

### Compare/Latch Behavior

- COUNT increments when ENABLE=1.
- When COUNT >= CMP and IRQ_EN=1, PENDING is set and COUNT is latched.
- Reading TIMER_COUNT returns the latched value if valid; otherwise the live COUNT.
- If PERIODIC=0, software must re-arm by writing TIMER_COUNT (clears the latch).
- If PERIODIC=1, compare can re-trigger without clearing the latch.

---

## Addressing Mode Summary

| Mode | Syntax | Calculation | Bytes |
|------|--------|-------------|-------|
| Implied | `INX` | — | 1 |
| Accumulator | `ASL` | — | 1 |
| Immediate | `LDA #$XX` | operand | 2-5 |
| Register (R=1) | `LDA Rn` | Register Rn | 2 |
| Direct Page | `LDA $XX` | D + offset (or Rn if R=1) | 2 |
| DP Indexed X | `LDA $XX,X` | D + offset + X | 2 |
| DP Indexed Y | `LDA $XX,Y` | D + offset + Y | 2 |
| Absolute | `LDA B+$XXXX` | B + addr16 | 3 |
| Abs Indexed X | `LDA B+$XXXX,X` | B + addr16 + X | 3 |
| Abs Indexed Y | `LDA B+$XXXX,Y` | B + addr16 + Y | 3 |
| DP Indirect | `LDA ($XX)` | [D + offset] | 2 |
| DP Indexed Indirect | `LDA ($XX,X)` | [D + offset + X] | 2 |
| DP Indirect Indexed | `LDA ($XX),Y` | [D + offset] + Y | 2 |
| DP Indirect Long | `LDA [$XX]` | 32-bit [D + offset] | 2 |
| DP Ind Long Indexed | `LDA [$XX],Y` | 32-bit [D + offset] + Y | 2 |
| Absolute Indirect | `JMP ($XXXX)` | [B + addr16] | 3 |
| Abs Indexed Indirect | `JMP ($XXXX,X)` | [B + addr16 + X] | 3 |
| Absolute Long | `LDA $XXXXXX` | addr24 (65816 mode only) | 4 |
| Abs Long Indexed | `LDA $XXXXXX,X` | addr24 + X (65816 mode only) | 4 |
| Stack Relative | `LDA $XX,S` | S + offset | 2 |
| SR Indirect Indexed | `LDA ($XX,S),Y` | [S + offset] + Y | 2 |
| Relative | `BEQ label` | PC + 2 + offset8 | 2 |
| Relative Long | `BRL label` | PC + 3 + offset16 | 3 |
| 32-bit Absolute | `LD R0, $XXXXXXXX` | addr32 (Extended ALU only) | 5+ |

**Note:** In 32-bit mode with R=1, Direct Page addresses $00-$FF map to hardware registers R0-R63. Use `Rn` notation (e.g., `LDA R4`) for clarity.

---

## Code Examples

### Mode Initialization

```asm
; Enter Native-32 mode from reset
reset:
    CLC                 ; C = 0
    XCE                 ; E = 0 (native mode)
    REP #$30            ; M = 01, X = 01 (16-bit)
    REPE #$A0           ; M = 10, X = 10 (32-bit)
    
    ; Set up base registers
    SD #$00010000       ; D = data segment base
    SB #$00000000       ; B = 0 (flat addressing)
    
    ; Set up stack
    LDX #$FFFFC000
    TXS
    
    ; Enable register window
    RSET
    ; Now $00-$FF accesses R0-R63
```

### Function Call Convention

```asm
; Call: result = add(a, b)
    LDA value_a
    STA R0              ; R0 = first argument
    LDA value_b
    STA R1              ; R1 = second argument
    JSR add_function
    LDA R0              ; Return value in R0
    STA result

add_function:
    LDA R0              ; A = R0
    ADC R1              ; A = A + R1
    STA R0              ; R0 = result
    RTS
```

### Spinlock with Memory Barriers

```asm
; Acquire spinlock
acquire:
    LDX #0              ; Expected value (unlocked)
    LDA #1              ; Desired value (locked)
.retry:
    CAS lock
    BNE .retry          ; Z=0 means failed
    FENCE               ; Ensure lock is visible
    RTS

; Release spinlock
release:
    FENCE               ; Ensure all writes complete
    STZ lock            ; Clear the lock
    RTS
```

### Array Sum with Loop

```asm
; Sum array of 32-bit integers
; Input: X = array address, Y = count
; Output: A = sum
sum_array:
    LDA #0              ; Initialize sum
    CPY #0
    BEQ .done
.loop:
    CLC
    ADC 0,X             ; Add array element
    INX
    INX
    INX
    INX                 ; X += 4 (next 32-bit element)
    DEY
    BNE .loop
.done:
    RTS
```

### System Call Wrapper

```asm
; write(fd, buffer, count)
; R0 = fd, R1 = buffer, R2 = count
; Returns bytes written in R0, -1 on error
sys_write:
    LDA #1              ; SYS_WRITE
    STA R4              ; R4 = syscall number (depends on ABI)
    TRAP #0
    ; Kernel returns result in R0
    RTS
```

---

## Flag Summary

| Flag | Bit | Set When |
|------|-----|----------|
| C | 0 | Carry out from MSB or borrow in |
| Z | 1 | Result is zero |
| I | 2 | IRQ interrupts disabled |
| D | 3 | BCD arithmetic enabled |
| X0 | 4 | Index width bit 0 |
| X1 | 5 | Index width bit 1 |
| M0 | 6 | Accumulator width bit 0 |
| M1 | 7 | Accumulator width bit 1 |
| V | 8 | Signed overflow |
| N | 9 | Result negative (MSB = 1) |
| E | 10 | Emulation mode (6502) |
| S | 11 | Supervisor mode |
| R | 12 | Register window enabled |
| K | 13 | Compatibility mode |

---

## See Also

- [M65832 Architecture Reference](M65832_Architecture_Reference.md) - Full architecture documentation
- [M65832 Quick Reference](M65832_Quick_Reference.md) - Concise reference card
- [M65832 Assembler Reference](M65832_Assembler_Reference.md) - Assembler usage and syntax
- [M65832 Disassembler Reference](M65832_Disassembler_Reference.md) - Disassembler usage and API
- [M65832 System Programming Guide](M65832_System_Programming_Guide.md) - OS and system development

---

*M65832 Instruction Set Reference - Verified against RTL implementation*
