# M65832 Instruction Set Reference

**Complete Opcode Encoding and Instruction Details**

---

## 1. Opcode Encoding Philosophy

The M65832 instruction encoding follows these principles:

1. **6502/65816 base layer**: Standard opcodes unchanged
2. **Width from flags**: M and X flags determine operand sizes
3. **WID prefix ($42)**: Enables 32-bit literals when needed
4. **Extended page ($02)**: New instructions for modern features

### 1.1 Instruction Format Overview

```
Standard:       [opcode]                           1 byte
Standard+imm:   [opcode] [imm8/16/32]              2-5 bytes
Standard+addr:  [opcode] [addr8/16]                2-3 bytes
WID prefix:     [$42] [opcode] [imm32 or addr32]   5-6 bytes
Extended:       [$02] [ext-op] [operands...]       3+ bytes
```

### 1.2 Operand Size Rules

| Context | M/X State | Immediate Size | Memory Access Size |
|---------|-----------|----------------|-------------------|
| Accumulator ops | M=00 | 8-bit | 8-bit |
| Accumulator ops | M=01 | 16-bit | 16-bit |
| Accumulator ops | M=10 | 32-bit | 32-bit |
| Index ops | X=00 | 8-bit | 8-bit |
| Index ops | X=01 | 16-bit | 16-bit |
| Index ops | X=10 | 32-bit | 32-bit |

---

## 2. Complete Opcode Map

### 2.1 Standard Opcode Table (00-FF)

```
     x0       x1       x2       x3       x4       x5       x6       x7
0x   BRK      ORA      *EXT*    ---      TSB      ORA      ASL      ---
     impl     (dp,X)   prefix   ---      dp       dp       dp       ---

1x   BPL      ORA      ORA      ---      TRB      ORA      ASL      ---
     rel      (dp),Y   (dp)     ---      dp       dp,X     dp,X     ---

2x   JSR      AND      ---      ---      BIT      AND      ROL      ---
     abs      (dp,X)   ---      ---      dp       dp       dp       ---

3x   BMI      AND      AND      ---      BIT      AND      ROL      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,X     ---

4x   RTI      EOR      *WID*    ---      ---      EOR      LSR      ---
     impl     (dp,X)   prefix   ---      ---      dp       dp       ---

5x   BVC      EOR      EOR      ---      ---      EOR      LSR      ---
     rel      (dp),Y   (dp)     ---      ---      dp,X     dp,X     ---

6x   RTS      ADC      ---      ---      STZ      ADC      ROR      ---
     impl     (dp,X)   ---      ---      dp       dp       dp       ---

7x   BVS      ADC      ADC      ---      STZ      ADC      ROR      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,X     ---

8x   BRA      STA      ---      ---      STY      STA      STX      ---
     rel      (dp,X)   ---      ---      dp       dp       dp       ---

9x   BCC      STA      STA      ---      STY      STA      STX      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,Y     ---

Ax   LDY      LDA      LDX      ---      LDY      LDA      LDX      ---
     #        (dp,X)   #        ---      dp       dp       dp       ---

Bx   BCS      LDA      LDA      ---      LDY      LDA      LDX      ---
     rel      (dp),Y   (dp)     ---      dp,X     dp,X     dp,Y     ---

Cx   CPY      CMP      ---      ---      CPY      CMP      DEC      ---
     #        (dp,X)   ---      ---      dp       dp       dp       ---

Dx   BNE      CMP      CMP      ---      ---      CMP      DEC      ---
     rel      (dp),Y   (dp)     ---      ---      dp,X     dp,X     ---

Ex   CPX      SBC      ---      ---      CPX      SBC      INC      ---
     #        (dp,X)   ---      ---      dp       dp       dp       ---

Fx   BEQ      SBC      SBC      ---      ---      SBC      INC      ---
     rel      (dp),Y   (dp)     ---      ---      dp,X     dp,X     ---
```

```
     x8       x9       xA       xB       xC       xD       xE       xF
0x   PHP      ORA      ASL      ---      TSB      ORA      ASL      ---
     impl     #        A        ---      abs      abs      abs      ---

1x   CLC      ORA      INC      ---      TRB      ORA      ASL      ---
     impl     abs,Y    A        ---      abs      abs,X    abs,X    ---

2x   PLP      AND      ROL      ---      BIT      AND      ROL      ---
     impl     #        A        ---      abs      abs      abs      ---

3x   SEC      AND      DEC      ---      BIT      AND      ROL      ---
     impl     abs,Y    A        ---      abs,X    abs,X    abs,X    ---

4x   PHA      EOR      LSR      ---      JMP      EOR      LSR      ---
     impl     #        A        ---      abs      abs      abs      ---

5x   CLI      EOR      PHY      ---      ---      EOR      LSR      ---
     impl     abs,Y    impl     ---      ---      abs,X    abs,X    ---

6x   PLA      ADC      ROR      ---      JMP      ADC      ROR      ---
     impl     #        A        ---      (abs)    abs      abs      ---

7x   SEI      ADC      PLY      ---      JMP      ADC      ROR      ---
     impl     abs,Y    impl     ---      (abs,X)  abs,X    abs,X    ---

8x   DEY      BIT      TXA      ---      STY      STA      STX      ---
     impl     #        impl     ---      abs      abs      abs      ---

9x   TYA      STA      TXS      ---      STZ      STA      STZ      ---
     impl     abs,Y    impl     ---      abs      abs,X    abs,X    ---

Ax   TAY      LDA      TAX      ---      LDY      LDA      LDX      ---
     impl     #        impl     ---      abs      abs      abs      ---

Bx   CLV      LDA      TSX      ---      LDY      LDA      LDX      ---
     impl     abs,Y    impl     ---      abs,X    abs,X    abs,Y    ---

Cx   INY      CMP      DEX      ---      CPY      CMP      DEC      ---
     impl     #        impl     ---      abs      abs      abs      ---

Dx   CLD      CMP      PHX      ---      ---      CMP      DEC      ---
     impl     abs,Y    impl     ---      ---      abs,X    abs,X    ---

Ex   INX      SBC      NOP      ---      CPX      SBC      INC      ---
     impl     #        impl     ---      abs      abs      abs      ---

Fx   SED      SBC      PLX      ---      ---      SBC      INC      ---
     impl     abs,Y    impl     ---      ---      abs,X    abs,X    ---
```

### 2.2 Extended Opcode Table ($02 Prefix)

After $02 prefix, the following opcodes are recognized:

```
$02 $00 [dp]       MUL dp         Signed multiply A *= [dp]
$02 $01 [dp]       MULU dp        Unsigned multiply
$02 $02 [abs16]    MUL abs        Signed multiply A *= [abs]
$02 $03 [abs16]    MULU abs       Unsigned multiply
$02 $04 [dp]       DIV dp         Signed divide A /= [dp], R0 = remainder
$02 $05 [dp]       DIVU dp        Unsigned divide
$02 $06 [abs16]    DIV abs        Signed divide
$02 $07 [abs16]    DIVU abs       Unsigned divide

$02 $10 [dp]       CAS dp         Compare and Swap at dp
$02 $11 [abs16]    CAS abs        Compare and Swap at abs
$02 $12 [dp]       LLI dp         Load Linked from dp
$02 $13 [abs16]    LLI abs        Load Linked from abs
$02 $14 [dp]       SCI dp         Store Conditional to dp
$02 $15 [abs16]    SCI abs        Store Conditional to abs

$02 $20 [imm32]    SVBR #imm32    Set VBR immediate
$02 $21 [dp]       SVBR dp        Set VBR from dp
$02 $22 [imm32]    SB #imm32      Set B immediate
$02 $23 [dp]       SB dp          Set B from dp
$02 $24 [imm32]    SD #imm32      Set D immediate
$02 $25 [dp]       SD dp          Set D from dp

$02 $30            RSET           R = 1 (enable register window)
$02 $31            RCLR           R = 0 (disable register window)

$02 $40 [imm8]     TRAP #imm8     System call / trap

$02 $50            FENCE          Full memory fence
$02 $51            FENCER         Read memory fence
$02 $52            FENCEW         Write memory fence

$02 $60 [imm8]     REPE #imm8     REP for extended P flags
$02 $61 [imm8]     SEPE #imm8     SEP for extended P flags

$02 $70            PHD            Push D (32-bit)
$02 $71            PLD            Pull D (32-bit)
$02 $72            PHB            Push B (32-bit)
$02 $73            PLB            Pull B (32-bit)
$02 $74            PHVBR          Push VBR (32-bit)
$02 $75            PLVBR          Pull VBR (32-bit)

$02 $80            TDA            A = D
$02 $81            TAD            D = A
$02 $82            TBA            A = B
$02 $83            TAB            B = A
$02 $84            TVA            A = VBR
$02 $85            TAV            VBR = A (supervisor only)

$02 $90            XCE            Exchange Carry with E flag
$02 $91            WAI            Wait for Interrupt
$02 $92            STP            Stop processor

$02 $A0 [dp]       LEA dp         Load Effective Address: A = D + dp
$02 $A1 [dp]       LEA dp,X       A = D + dp + X
$02 $A2 [abs16]    LEA abs        A = B + abs16
$02 $A3 [abs16]    LEA abs,X      A = B + abs16 + X
```

### 2.3 WID Prefix ($42) Usage

The WID prefix extends the following operand to 32-bits:

```
$42 $A9 [imm32]    WID LDA #imm   Load A with 32-bit immediate
$42 $A2 [imm32]    WID LDX #imm   Load X with 32-bit immediate  
$42 $A0 [imm32]    WID LDY #imm   Load Y with 32-bit immediate

$42 $AD [addr32]   WID LDA addr   Load A from 32-bit address
$42 $AE [addr32]   WID LDX addr   Load X from 32-bit address
$42 $AC [addr32]   WID LDY addr   Load Y from 32-bit address

$42 $8D [addr32]   WID STA addr   Store A to 32-bit address
$42 $8E [addr32]   WID STX addr   Store X to 32-bit address
$42 $8C [addr32]   WID STY addr   Store Y to 32-bit address

$42 $4C [addr32]   WID JMP addr   Jump to 32-bit address
$42 $20 [addr32]   WID JSR addr   Jump subroutine to 32-bit address

$42 $6C [addr32]   WID JMP (addr) Jump indirect through 32-bit ptr address
```

---

## 3. Instruction Details

### 3.1 ADC - Add with Carry

**Operation**: A = A + M + C

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | ADC #imm | $69 | 2/3/5 | 2 |
| Direct Page | ADC dp | $65 | 2 | 3 |
| DP Indexed X | ADC dp,X | $75 | 2 | 4 |
| Absolute | ADC abs | $6D | 3 | 4 |
| Abs Indexed X | ADC abs,X | $7D | 3 | 4+ |
| Abs Indexed Y | ADC abs,Y | $79 | 3 | 4+ |
| DP Indirect | ADC (dp) | $72 | 2 | 5 |
| DP Ind Indexed X | ADC (dp,X) | $61 | 2 | 6 |
| DP Indirect Indexed Y | ADC (dp),Y | $71 | 2 | 5+ |

**Flags Affected**: N, V, Z, C

**Description**: Adds the operand and the carry flag to the accumulator. In decimal mode (D=1), performs BCD addition.

```asm
; 32-bit addition example (M=10)
CLC
LDA num1        ; A = first 32-bit number
ADC num2        ; A = A + num2 + 0
STA result      ; Store result
```

### 3.2 AND - Logical AND

**Operation**: A = A & M

**Addressing Modes**: Same as ADC

**Flags Affected**: N, Z

### 3.3 ASL - Arithmetic Shift Left

**Operation**: C ← [7] ← [6..0] ← 0

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Accumulator | ASL | $0A | 1 | 2 |
| Direct Page | ASL dp | $06 | 2 | 5 |
| DP Indexed X | ASL dp,X | $16 | 2 | 6 |
| Absolute | ASL abs | $0E | 3 | 6 |
| Abs Indexed X | ASL abs,X | $1E | 3 | 7 |

**Flags Affected**: N, Z, C

### 3.4 BCC - Branch if Carry Clear

**Operation**: if C=0: PC = PC + offset

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BCC rel8 | $90 | 2 | 2/3 |

**Flags Affected**: None

### 3.5 BCS - Branch if Carry Set

**Operation**: if C=1: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BCS rel8 | $B0 | 2 | 2/3 |

### 3.6 BEQ - Branch if Equal (Zero Set)

**Operation**: if Z=1: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BEQ rel8 | $F0 | 2 | 2/3 |

### 3.7 BIT - Bit Test

**Operation**: 
- Z = !(A & M)
- N = M[msb]
- V = M[msb-1]

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | BIT #imm | $89 | 2/3/5 | 2 |
| Direct Page | BIT dp | $24 | 2 | 3 |
| DP Indexed X | BIT dp,X | $34 | 2 | 4 |
| Absolute | BIT abs | $2C | 3 | 4 |
| Abs Indexed X | BIT abs,X | $3C | 3 | 4+ |

**Note**: Immediate mode only affects Z flag.

### 3.8 BMI - Branch if Minus

**Operation**: if N=1: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BMI rel8 | $30 | 2 | 2/3 |

### 3.9 BNE - Branch if Not Equal

**Operation**: if Z=0: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BNE rel8 | $D0 | 2 | 2/3 |

### 3.10 BPL - Branch if Plus

**Operation**: if N=0: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BPL rel8 | $10 | 2 | 2/3 |

### 3.11 BRA - Branch Always

**Operation**: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BRA rel8 | $80 | 2 | 3 |

### 3.12 BRK - Software Break

**Operation**: Push PC+2, Push P, PC = [IRQ vector], I=1, B=1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | BRK | $00 | 2 | 7 |

**Note**: In native mode, also sets S=1 (supervisor) and vectors through native break vector.

### 3.13 BVC - Branch if Overflow Clear

**Operation**: if V=0: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BVC rel8 | $50 | 2 | 2/3 |

### 3.14 BVS - Branch if Overflow Set

**Operation**: if V=1: PC = PC + offset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Relative | BVS rel8 | $70 | 2 | 2/3 |

### 3.15 CAS - Compare and Swap (NEW)

**Operation**: 
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

**Flags Affected**: Z

**Description**: Atomic compare-and-swap. Compares memory with X register. If equal, stores A to memory and sets Z. If not equal, loads memory into X and clears Z.

```asm
; Acquire spinlock
acquire:
    LDX #0          ; Expected: unlocked
    LDA #1          ; Desired: locked
spin:
    CAS lock
    BNE spin        ; Retry if failed
    RTS
```

### 3.16 CLC - Clear Carry

**Operation**: C = 0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | CLC | $18 | 1 | 2 |

### 3.17 CLD - Clear Decimal

**Operation**: D = 0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | CLD | $D8 | 1 | 2 |

### 3.18 CLI - Clear Interrupt Disable

**Operation**: I = 0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | CLI | $58 | 1 | 2 |

### 3.19 CLV - Clear Overflow

**Operation**: V = 0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | CLV | $B8 | 1 | 2 |

### 3.20 CMP - Compare Accumulator

**Operation**: Flags from A - M (result discarded)

**Addressing Modes**: Same as ADC

**Flags Affected**: N, Z, C

### 3.21 CPX - Compare X Register

**Operation**: Flags from X - M

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | CPX #imm | $E0 | 2/3/5 | 2 |
| Direct Page | CPX dp | $E4 | 2 | 3 |
| Absolute | CPX abs | $EC | 3 | 4 |

**Flags Affected**: N, Z, C

### 3.22 CPY - Compare Y Register

**Operation**: Flags from Y - M

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | CPY #imm | $C0 | 2/3/5 | 2 |
| Direct Page | CPY dp | $C4 | 2 | 3 |
| Absolute | CPY abs | $CC | 3 | 4 |

**Flags Affected**: N, Z, C

### 3.23 DEC - Decrement

**Operation**: M = M - 1 (or A = A - 1)

**Addressing Modes**:
| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Accumulator | DEC | $3A | 1 | 2 |
| Direct Page | DEC dp | $C6 | 2 | 5 |
| DP Indexed X | DEC dp,X | $D6 | 2 | 6 |
| Absolute | DEC abs | $CE | 3 | 6 |
| Abs Indexed X | DEC abs,X | $DE | 3 | 7 |

**Flags Affected**: N, Z

### 3.24 DEX - Decrement X

**Operation**: X = X - 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | DEX | $CA | 1 | 2 |

**Flags Affected**: N, Z

### 3.25 DEY - Decrement Y

**Operation**: Y = Y - 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | DEY | $88 | 1 | 2 |

**Flags Affected**: N, Z

### 3.26 DIV - Signed Divide (NEW)

**Operation**: R0 = A % M; A = A / M (signed)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | DIV dp | $02 $04 | 3 | 20-40 |
| Absolute | DIV abs | $02 $06 | 4 | 20-40 |

**Flags Affected**: N, Z, V (overflow if divide by zero)

### 3.27 DIVU - Unsigned Divide (NEW)

**Operation**: R0 = A % M; A = A / M (unsigned)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | DIVU dp | $02 $05 | 3 | 20-40 |
| Absolute | DIVU abs | $02 $07 | 4 | 20-40 |

**Flags Affected**: N, Z, V

### 3.28 EOR - Exclusive OR

**Operation**: A = A ^ M

**Addressing Modes**: Same as ADC

**Flags Affected**: N, Z

### 3.29 FENCE - Memory Fence (NEW)

**Operation**: All memory operations before fence complete before any after fence begin

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | FENCE | $02 $50 | 2 | 3+ |
| Implied | FENCER | $02 $51 | 2 | 2+ |
| Implied | FENCEW | $02 $52 | 2 | 2+ |

### 3.30 INC - Increment

**Operation**: M = M + 1 (or A = A + 1)

**Addressing Modes**: Same as DEC

**Flags Affected**: N, Z

### 3.31 INX - Increment X

**Operation**: X = X + 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | INX | $E8 | 1 | 2 |

**Flags Affected**: N, Z

### 3.32 INY - Increment Y

**Operation**: Y = Y + 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | INY | $C8 | 1 | 2 |

**Flags Affected**: N, Z

### 3.33 JMP - Jump

**Operation**: PC = address

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute | JMP abs | $4C | 3 | 3 |
| Indirect | JMP (abs) | $6C | 3 | 5 |
| Indexed Indirect | JMP (abs,X) | $7C | 3 | 6 |
| Long | WID JMP long | $42 $4C | 6 | 4 |

### 3.34 JSR - Jump to Subroutine

**Operation**: Push PC-1; PC = address

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Absolute | JSR abs | $20 | 3 | 6 |
| Long | WID JSR long | $42 $20 | 6 | 7 |

### 3.35 LDA - Load Accumulator

**Operation**: A = M

**Addressing Modes**: Same as ADC

**Flags Affected**: N, Z

### 3.36 LDX - Load X Register

**Operation**: X = M

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | LDX #imm | $A2 | 2/3/5 | 2 |
| Direct Page | LDX dp | $A6 | 2 | 3 |
| DP Indexed Y | LDX dp,Y | $B6 | 2 | 4 |
| Absolute | LDX abs | $AE | 3 | 4 |
| Abs Indexed Y | LDX abs,Y | $BE | 3 | 4+ |

**Flags Affected**: N, Z

### 3.37 LDY - Load Y Register

**Operation**: Y = M

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | LDY #imm | $A0 | 2/3/5 | 2 |
| Direct Page | LDY dp | $A4 | 2 | 3 |
| DP Indexed X | LDY dp,X | $B4 | 2 | 4 |
| Absolute | LDY abs | $AC | 3 | 4 |
| Abs Indexed X | LDY abs,X | $BC | 3 | 4+ |

**Flags Affected**: N, Z

### 3.38 LEA - Load Effective Address (NEW)

**Operation**: A = effective address (does not access memory)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | LEA dp | $02 $A0 | 3 | 2 |
| DP Indexed X | LEA dp,X | $02 $A1 | 3 | 2 |
| Absolute | LEA abs | $02 $A2 | 4 | 2 |
| Abs Indexed X | LEA abs,X | $02 $A3 | 4 | 2 |

**Flags Affected**: None

**Description**: Computes the effective address but doesn't load from it. Useful for pointer arithmetic.

```asm
; Get address of array[X]
SD #$00010000       ; D = data segment
LEA array,X         ; A = D + array_offset + X
```

### 3.39 LLI - Load Linked (NEW)

**Operation**: A = [M]; set link for address M

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | LLI dp | $02 $12 | 3 | 4 |
| Absolute | LLI abs | $02 $13 | 4 | 5 |

**Flags Affected**: N, Z

**Description**: Loads from memory and sets an internal "link" flag. The link is cleared if any store occurs to that address.

### 3.40 LSR - Logical Shift Right

**Operation**: 0 → [msb..1] → [0] → C

**Addressing Modes**: Same as ASL

**Flags Affected**: N (always 0), Z, C

### 3.41 MUL - Signed Multiply (NEW)

**Operation**: A = A × M (signed), high word to R0 for 32×32

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | MUL dp | $02 $00 | 3 | 8-16 |
| Absolute | MUL abs | $02 $02 | 4 | 8-16 |

**Flags Affected**: N, Z, V (overflow)

**Width Behavior**:
- M=00 (8-bit): A[7:0] × M[7:0] → A[15:0]
- M=01 (16-bit): A[15:0] × M[15:0] → A[31:0]
- M=10 (32-bit): A[31:0] × M[31:0] → R0[31:0]:A[31:0] (64-bit result)

### 3.42 MULU - Unsigned Multiply (NEW)

**Operation**: A = A × M (unsigned)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | MULU dp | $02 $01 | 3 | 8-16 |
| Absolute | MULU abs | $02 $03 | 4 | 8-16 |

### 3.43 NOP - No Operation

**Operation**: None

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | NOP | $EA | 1 | 2 |

### 3.44 ORA - Logical OR

**Operation**: A = A | M

**Addressing Modes**: Same as ADC

**Flags Affected**: N, Z

### 3.45 PHA - Push Accumulator

**Operation**: [S] = A; S = S - width

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PHA | $48 | 1 | 3 |

### 3.46 PHP - Push Processor Status

**Operation**: [S] = P; S = S - 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PHP | $08 | 1 | 3 |

### 3.47 PHX - Push X Register

**Operation**: [S] = X; S = S - width

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PHX | $DA | 1 | 3 |

### 3.48 PHY - Push Y Register

**Operation**: [S] = Y; S = S - width

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PHY | $5A | 1 | 3 |

### 3.49 PLA - Pull Accumulator

**Operation**: S = S + width; A = [S]

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PLA | $68 | 1 | 4 |

**Flags Affected**: N, Z

### 3.50 PLP - Pull Processor Status

**Operation**: S = S + 1; P = [S]

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PLP | $28 | 1 | 4 |

**Flags Affected**: All

### 3.51 PLX - Pull X Register

**Operation**: S = S + width; X = [S]

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PLX | $FA | 1 | 4 |

**Flags Affected**: N, Z

### 3.52 PLY - Pull Y Register

**Operation**: S = S + width; Y = [S]

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | PLY | $7A | 1 | 4 |

**Flags Affected**: N, Z

### 3.53 RCLR - Register Window Clear (NEW)

**Operation**: R = 0 (DP accesses memory)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RCLR | $02 $31 | 2 | 2 |

### 3.54 REP - Reset Processor Status Bits

**Operation**: P = P & ~imm

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | REP #imm8 | $C2 | 2 | 3 |

**Description**: Clears bits in P where the corresponding bit in imm is 1.

```asm
REP #$30        ; Clear M and X bits (16-bit mode)
REP #$20        ; Clear M bit only (16-bit A)
```

### 3.55 REPE - Reset Extended Status Bits (NEW)

**Operation**: Extended P = Extended P & ~imm

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | REPE #imm8 | $02 $60 | 3 | 3 |

```asm
REPE #$A0       ; Set M1 and X1 (32-bit mode)
```

### 3.56 ROL - Rotate Left

**Operation**: C ← [msb] ← [msb-1..0] ← old C

**Addressing Modes**: Same as ASL

**Flags Affected**: N, Z, C

### 3.57 ROR - Rotate Right

**Operation**: old C → [msb] → [msb-1..0] → C

**Addressing Modes**: Same as ASL

**Flags Affected**: N, Z, C

### 3.58 RSET - Register Window Set (NEW)

**Operation**: R = 1 (DP accesses register file)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RSET | $02 $30 | 2 | 2 |

### 3.59 RTI - Return from Interrupt

**Operation**: P = Pull; PC = Pull

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RTI | $40 | 1 | 6-7 |

### 3.60 RTS - Return from Subroutine

**Operation**: PC = Pull + 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | RTS | $60 | 1 | 6 |

### 3.61 SB - Set Base Register (NEW)

**Operation**: B = operand

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | SB #imm32 | $02 $22 | 6 | 3 |
| Direct Page | SB dp | $02 $23 | 3 | 4 |

### 3.62 SBC - Subtract with Carry

**Operation**: A = A - M - ~C

**Addressing Modes**: Same as ADC

**Flags Affected**: N, V, Z, C

### 3.63 SCI - Store Conditional (NEW)

**Operation**: if link valid: [M] = A, Z=1; else Z=0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | SCI dp | $02 $14 | 3 | 5 |
| Absolute | SCI abs | $02 $15 | 4 | 6 |

**Flags Affected**: Z

**Description**: Conditionally stores A to memory if the link (from prior LLI) is still valid. Link is invalidated by any intervening store to the linked address.

### 3.64 SD - Set Direct Base (NEW)

**Operation**: D = operand

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | SD #imm32 | $02 $24 | 6 | 3 |
| Direct Page | SD dp | $02 $25 | 3 | 4 |

### 3.65 SEC - Set Carry

**Operation**: C = 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | SEC | $38 | 1 | 2 |

### 3.66 SED - Set Decimal

**Operation**: D = 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | SED | $F8 | 1 | 2 |

### 3.67 SEI - Set Interrupt Disable

**Operation**: I = 1

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | SEI | $78 | 1 | 2 |

### 3.68 SEP - Set Processor Status Bits

**Operation**: P = P | imm

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | SEP #imm8 | $E2 | 2 | 3 |

```asm
SEP #$30        ; Set M and X bits (8-bit mode)
```

### 3.69 SEPE - Set Extended Status Bits (NEW)

**Operation**: Extended P = Extended P | imm

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | SEPE #imm8 | $02 $61 | 3 | 3 |

### 3.70 STA - Store Accumulator

**Operation**: M = A

**Addressing Modes**: Same as LDA (except no immediate)

### 3.71 STP - Stop Processor (NEW)

**Operation**: Halt until reset

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | STP | $02 $92 | 2 | 2 |

### 3.72 STX - Store X Register

**Operation**: M = X

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | STX dp | $86 | 2 | 3 |
| DP Indexed Y | STX dp,Y | $96 | 2 | 4 |
| Absolute | STX abs | $8E | 3 | 4 |

### 3.73 STY - Store Y Register

**Operation**: M = Y

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | STY dp | $84 | 2 | 3 |
| DP Indexed X | STY dp,X | $94 | 2 | 4 |
| Absolute | STY abs | $8C | 3 | 4 |

### 3.74 STZ - Store Zero

**Operation**: M = 0

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | STZ dp | $64 | 2 | 3 |
| DP Indexed X | STZ dp,X | $74 | 2 | 4 |
| Absolute | STZ abs | $9C | 3 | 4 |
| Abs Indexed X | STZ abs,X | $9E | 3 | 5 |

### 3.75 SVBR - Set Virtual Base Register (NEW)

**Operation**: VBR = operand (supervisor only)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | SVBR #imm32 | $02 $20 | 6 | 3 |
| Direct Page | SVBR dp | $02 $21 | 3 | 4 |

### 3.76 TAX - Transfer A to X

**Operation**: X = A

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TAX | $AA | 1 | 2 |

**Flags Affected**: N, Z

### 3.77 TAY - Transfer A to Y

**Operation**: Y = A

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TAY | $A8 | 1 | 2 |

**Flags Affected**: N, Z

### 3.78 TRAP - System Trap (NEW)

**Operation**: Push PC, Push P; S=1, I=1; PC = [TRAP vector + imm8*4]

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Immediate | TRAP #imm8 | $02 $40 | 3 | 8 |

**Description**: System call mechanism. Switches to supervisor mode and vectors through trap table indexed by immediate value.

### 3.79 TRB - Test and Reset Bits

**Operation**: M = M & ~A; Z = !(M & A)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | TRB dp | $14 | 2 | 5 |
| Absolute | TRB abs | $1C | 3 | 6 |

**Flags Affected**: Z

### 3.80 TSB - Test and Set Bits

**Operation**: M = M | A; Z = !(M & A)

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Direct Page | TSB dp | $04 | 2 | 5 |
| Absolute | TSB abs | $0C | 3 | 6 |

**Flags Affected**: Z

### 3.81 TSX - Transfer S to X

**Operation**: X = S

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TSX | $BA | 1 | 2 |

**Flags Affected**: N, Z

### 3.82 TXA - Transfer X to A

**Operation**: A = X

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TXA | $8A | 1 | 2 |

**Flags Affected**: N, Z

### 3.83 TXS - Transfer X to S

**Operation**: S = X

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TXS | $9A | 1 | 2 |

### 3.84 TYA - Transfer Y to A

**Operation**: A = Y

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | TYA | $98 | 1 | 2 |

**Flags Affected**: N, Z

### 3.85 WAI - Wait for Interrupt (NEW)

**Operation**: Halt until interrupt received

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | WAI | $02 $91 | 2 | 3+ |

### 3.86 XCE - Exchange Carry with Emulation (NEW)

**Operation**: Swap C flag with E flag

| Mode | Syntax | Opcode | Bytes | Cycles |
|------|--------|--------|-------|--------|
| Implied | XCE | $02 $90 | 2 | 2 |

**Description**: Used to switch between emulation and native modes.

```asm
; Enter native mode
CLC             ; C = 0
XCE             ; E = 0 (native), C = old E

; Enter emulation mode  
SEC             ; C = 1
XCE             ; E = 1 (emulation), C = old E
```

---

## 4. Instruction Timing Details

### 4.1 Cycle Counting Rules

Base cycles are modified by:

1. **+1 if DP low byte is non-zero** (misaligned D register)
2. **+1 if page boundary crossed** (indexed modes)
3. **Width multiplier**: 32-bit ops may take longer for memory access
4. **Wait states**: Memory speed dependent

### 4.2 Memory Access Patterns

| Width | Bytes Transferred | Typical Cycles |
|-------|-------------------|----------------|
| 8-bit | 1 | 1 |
| 16-bit | 2 | 1-2 |
| 32-bit | 4 | 2-4 |

---

## 5. Programmer's Quick Reference

### 5.1 Common Patterns

```asm
; 32-bit add
CLC
LDA num1
ADC num2
STA result

; 32-bit compare
LDA val1
CMP val2
BCC less        ; val1 < val2
BEQ equal       ; val1 == val2
                ; fall through: val1 > val2

; Loop with counter
    LDX #100
loop:
    ; ... loop body ...
    DEX
    BNE loop

; Indirect pointer access
    LDA ($20)       ; A = *ptr (ptr at DP+$20)
    LDA ($20),Y     ; A = ptr[Y]

; Array indexing
    LDX #4          ; index * 4 for 32-bit elements
    LDA array,X     ; A = array[1]
```

### 5.2 Mode Switching

```asm
; To Native-32 from reset
    CLC
    XCE             ; E=0
    REP #$30        ; M=01, X=01 (16-bit)
    REPE #$A0       ; M=10, X=10 (32-bit)

; To 8-bit accumulator temporarily
    SEP #$20        ; M=00 (8-bit A)
    ; ... 8-bit ops ...
    REP #$20        ; Back to 16-bit
```

### 5.3 Register Window Usage

```asm
; Enable register file
    RSET
    
; Now DP offsets are registers:
    LDA $00         ; A = R0
    STA $04         ; R1 = A
    INC $08         ; R2++
    
; Disable for legacy code
    RCLR
```

---

*End of Instruction Set Reference*
