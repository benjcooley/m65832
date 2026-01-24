# M65832 Quick Reference Card

## Registers

| Register | Size | Description |
|----------|------|-------------|
| A | 8/16/32 | Accumulator |
| X | 8/16/32 | Index X |
| Y | 8/16/32 | Index Y |
| S | 16/32 | Stack Pointer |
| PC | 16/32 | Program Counter |
| D | 32 | Direct Page Base |
| B | 32 | Absolute Base |
| VBR | 32 | Virtual 6502 Base |
| R0-R63 | 32 | Register Window (via DP when R=1) |

## Status Flags

### Standard P (Byte 0)
```
7   6   5   4   3   2   1   0
N   V   -   B   D   I   Z   C
│   │       │   │   │   │   └── Carry
│   │       │   │   │   └────── Zero
│   │       │   │   └────────── IRQ Disable
│   │       │   └────────────── Decimal Mode
│   │       └────────────────── Break
│   └────────────────────────── Overflow
└────────────────────────────── Negative
```

### Extended P (Byte 1)
```
7   6   5   4   3   2   1   0
M1  M0  X1  X0  E   S   R   W
│   │   │   │   │   │   │   └── Wide Stack (32-bit S)
│   │   │   │   │   │   └────── Register Window
│   │   │   │   │   └────────── Supervisor Mode
│   │   │   │   └────────────── Emulation Mode
│   │   └───┴────────────────── Index Width
└───┴────────────────────────── Accumulator Width

Width: 00=8-bit, 01=16-bit, 10=32-bit
```

## Processor Modes

| Mode | E | M | X | Description |
|------|---|---|---|-------------|
| Emulation | 1 | - | - | 6502 compatible (VBR-relative) |
| Native-16 | 0 | 01 | 01 | 65816 compatible |
| Native-32 | 0 | 10 | 10 | Full 32-bit |

## Mode Switching

```asm
; To Native Mode (from emulation)
CLC
XCE

; To Emulation Mode
SEC
XCE

; To 32-bit registers
REP #$30        ; 16-bit first
REPE #$A0       ; Then 32-bit

; To 8-bit A only
SEP #$20
```

## Addressing Modes

| Mode | Syntax | Effective Address |
|------|--------|-------------------|
| Immediate | `#$XX` | Value in instruction |
| Direct Page | `$XX` | D + XX |
| DP Indexed X | `$XX,X` | D + XX + X |
| DP Indexed Y | `$XX,Y` | D + XX + Y |
| DP Indirect | `($XX)` | [D + XX] |
| DP Ind Idx X | `($XX,X)` | [D + XX + X] |
| DP Ind Idx Y | `($XX),Y` | [D + XX] + Y |
| Absolute | `$XXXX` | B + XXXX |
| Abs Indexed X | `$XXXX,X` | B + XXXX + X |
| Abs Indexed Y | `$XXXX,Y` | B + XXXX + Y |
| Abs Indirect | `($XXXX)` | [B + XXXX] |
| Long | `$XXXXXXXX` | XXXXXXXX (WID prefix) |

## Common Instructions

### Load/Store
| Instruction | Description |
|-------------|-------------|
| LDA src | Load A |
| LDX src | Load X |
| LDY src | Load Y |
| STA dst | Store A |
| STX dst | Store X |
| STY dst | Store Y |
| STZ dst | Store Zero |

### Arithmetic
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| ADC src | A = A + src + C | NVZC |
| SBC src | A = A - src - !C | NVZC |
| INC dst | dst = dst + 1 | NZ |
| DEC dst | dst = dst - 1 | NZ |
| INX | X = X + 1 | NZ |
| INY | Y = Y + 1 | NZ |
| DEX | X = X - 1 | NZ |
| DEY | Y = Y - 1 | NZ |

### Logic
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| AND src | A = A & src | NZ |
| ORA src | A = A \| src | NZ |
| EOR src | A = A ^ src | NZ |
| BIT src | test A & src | NVZ |

### Shifts
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| ASL dst | dst << 1 | NZC |
| LSR dst | dst >> 1 | NZC |
| ROL dst | rotate left | NZC |
| ROR dst | rotate right | NZC |

### Compare
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| CMP src | A - src | NZC |
| CPX src | X - src | NZC |
| CPY src | Y - src | NZC |

### Branches
| Instruction | Condition |
|-------------|-----------|
| BEQ rel | Z = 1 |
| BNE rel | Z = 0 |
| BCS rel | C = 1 |
| BCC rel | C = 0 |
| BMI rel | N = 1 |
| BPL rel | N = 0 |
| BVS rel | V = 1 |
| BVC rel | V = 0 |
| BRA rel | Always |

### Jump/Call
| Instruction | Description |
|-------------|-------------|
| JMP addr | PC = addr |
| JMP (addr) | PC = [addr] |
| JSR addr | Push PC; PC = addr |
| RTS | PC = Pull + 1 |
| RTI | P = Pull; PC = Pull |

### Stack
| Instruction | Description |
|-------------|-------------|
| PHA / PLA | Push/Pull A |
| PHX / PLX | Push/Pull X |
| PHY / PLY | Push/Pull Y |
| PHP / PLP | Push/Pull P |
| PHD / PLD | Push/Pull D |
| PHB / PLB | Push/Pull B |

### Transfers
| Instruction | Operation |
|-------------|-----------|
| TAX / TXA | A ↔ X |
| TAY / TYA | A ↔ Y |
| TSX / TXS | S ↔ X |
| TDA / TAD | D ↔ A |
| TBA / TAB | B ↔ A |

### Status Flags
| Instruction | Operation |
|-------------|-----------|
| CLC / SEC | C = 0 / 1 |
| CLD / SED | D = 0 / 1 |
| CLI / SEI | I = 0 / 1 |
| CLV | V = 0 |
| REP #xx | P &= ~xx |
| SEP #xx | P |= xx |
| REPE #xx | ExtP &= ~xx |
| SEPE #xx | ExtP |= xx |

## New Instructions (M65832)

### Multiply/Divide
| Instruction | Operation |
|-------------|-----------|
| MUL dp | A = A × [dp] (signed) |
| MULU dp | A = A × [dp] (unsigned) |
| DIV dp | A = A / [dp], R0 = A % [dp] |
| DIVU dp | (unsigned) |

### Atomics
| Instruction | Operation |
|-------------|-----------|
| CAS dp | if [dp]==X then [dp]=A, Z=1 else X=[dp], Z=0 |
| LLI dp | A = [dp], link address |
| SCI dp | if link valid: [dp]=A, Z=1 else Z=0 |
| FENCE | Full memory barrier |

### System
| Instruction | Operation |
|-------------|-----------|
| SVBR #imm32 | VBR = imm32 (supervisor) |
| SB #imm32 | B = imm32 |
| SD #imm32 | D = imm32 |
| RSET / RCLR | R = 1 / 0 |
| TRAP #n | System call #n |
| WAI | Wait for interrupt |
| STP | Stop processor |
| XCE | Exchange C with E |
| LEA dp | A = D + dp (load effective address) |

### Floating Point
| Instruction | Operation |
|-------------|-----------|
| LDF0/1/2 dp | Load F0/F1/F2 from dp (64-bit) |
| STF0/1/2 dp | Store F0/F1/F2 to dp (64-bit) |
| FADD.S/D | F0 = F1 + F2 |
| FSUB.S/D | F0 = F1 - F2 |
| FMUL.S/D | F0 = F1 * F2 |
| FDIV.S/D | F0 = F1 / F2 |
| FNEG.S/D | F0 = -F1 |
| FABS.S/D | F0 = abs(F1) |
| FCMP.S/D | Set Z/N/C from F1 ? F2 |
| F2I.S/D | A = (int32)F1 |
| I2F.S/D | F0 = (float)A |

Note: reserved FP opcodes trap via `TRAP` using the opcode byte as the vector index.

### WID Prefix ($42)
```asm
WID LDA #$12345678    ; 32-bit immediate
WID LDA $12345678     ; 32-bit address
WID JMP $DEADBEEF     ; Jump to 32-bit address
```

## Register Window (R=1)

When R=1, Direct Page accesses hardware registers:
```
$00-$03 = R0    $40-$43 = R16
$04-$07 = R1    $44-$47 = R17
$08-$0B = R2    ...
...             $FC-$FF = R63
```

## Memory Map (Typical Linux)

```
$0000_0000 - $0000_FFFF   6502 compatibility zone
$0001_0000 - $7FFF_FFFF   User space
$8000_0000 - $BFFF_FFFF   Kernel direct-mapped
$C000_0000 - $FFFF_EFFF   Kernel vmalloc
$FFFF_F000 - $FFFF_FFFF   Vectors/System
```

## Exception Vectors

| Address | Exception |
|---------|-----------|
| $FFFF_FFE0 | Reset |
| $FFFF_FFE4 | NMI |
| $FFFF_FFE8 | IRQ |
| $FFFF_FFEC | BRK |
| $FFFF_FFF0 | TRAP |
| $FFFF_FFF4 | Page Fault |
| $FFFF_FFF8 | Illegal Op |
| $FFFF_FFFC | Alignment |

## Opcode Prefixes

| Prefix | Purpose |
|--------|---------|
| $02 | Extended opcode page |
| $42 | WID - 32-bit operand |

## Common Code Patterns

### 32-bit Add
```asm
CLC
LDA num1
ADC num2
STA result
```

### Loop
```asm
    LDX #100
loop:
    ; body
    DEX
    BNE loop
```

### Function Call (Register ABI)
```asm
    LDA arg1
    STA $00         ; R0
    LDA arg2
    STA $04         ; R1
    JSR function
    LDA $00         ; return in R0
```

### Spinlock
```asm
acquire:
    LDX #0          ; expected
    LDA #1          ; desired
    CAS lock
    BNE acquire
    FENCE
```

### System Call
```asm
    LDA #SYSCALL_NUM
    STA $00
    ; args in R1-R6
    TRAP #0
    ; return in R0
```
