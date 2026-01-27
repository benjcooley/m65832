# M65832 Quick Reference Card

A concise reference for M65832 programming. For detailed information, see the [Instruction Set Reference](M65832_Instruction_Set.md).

---

## Registers

| Register | Size | Description |
|----------|------|-------------|
| A | 8/16/32 | Accumulator (width per M flag) |
| X | 8/16/32 | Index X (width per X flag) |
| Y | 8/16/32 | Index Y (width per X flag) |
| S | 16/32 | Stack Pointer |
| PC | 16/32 | Program Counter |
| D | 32 | Direct Page Base |
| B | 32 | Absolute Base |
| VBR | 32 | Virtual 6502 Base (supervisor) |
| T | 32 | Temp (MUL high / DIV remainder) |
| R0-R63 | 32 | Register Window (via DP when R=1) |
| F0-F15 | 64 | FPU Registers (optional, 16 regs) |

---

## Status Flags

### Standard P (Byte 0)
```
Bit:  7   6   5   4   3   2   1   0
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
Bit:  7   6   5   4   3   2   1   0
      M1  M0  X1  X0  E   S   R   K
      │   │   │   │   │   │   │   └── Compat (illegal→NOP)
      │   │   │   │   │   │   └────── Register Window
      │   │   │   │   │   └────────── Supervisor Mode
      │   │   │   │   └────────────── Emulation Mode
      │   │   └───┴────────────────── Index Width (X1:X0)
      └───┴────────────────────────── Accumulator Width (M1:M0)

Width encoding: 00=8-bit, 01=16-bit, 10=32-bit, 11=reserved
```

---

## Processor Modes

| Mode | E | M1:M0 | X1:X0 | Description |
|------|---|-------|-------|-------------|
| Emulation | 1 | — | — | 6502 compatible (VBR-relative) |
| Native-16 | 0 | 01 | 01 | 65816 compatible |
| Native-32 | 0 | 10 | 10 | Full 32-bit mode |

In Native-32, standard opcodes are fixed 32-bit; use Extended ALU for 8/16-bit sizing.

### Mode Switching
```asm
; Enter Native Mode (from emulation)
    CLC
    XCE                 ; E=0

; Enter Emulation Mode
    SEC
    XCE                 ; E=1

; Enter 32-bit Mode (from native)
    REP #$30            ; M=01, X=01 (16-bit first)
    REPE #$A0           ; M=10, X=10 (32-bit)

; Temporarily use 8-bit A
    SEP #$20            ; M=00
    ; ... 8-bit ops ...
    REP #$20            ; M=01 (back to 16-bit)
```

---

## Addressing Modes

| Mode | Syntax | Effective Address | Bytes |
|------|--------|-------------------|-------|
| Immediate | `#$XX` | operand | 2-5 |
| Register (R=1) | `Rn` | Register Rn | 2 |
| Direct Page | `$XX` | D + XX (or Rn if R=1) | 2 |
| DP Indexed X | `$XX,X` | D + XX + X | 2 |
| DP Indexed Y | `$XX,Y` | D + XX + Y | 2 |
| DP Indirect | `($XX)` or `(Rn)` | [D + XX] | 2 |
| DP Indexed Indirect | `($XX,X)` | [D + XX + X] | 2 |
| DP Indirect Indexed | `($XX),Y` or `(Rn),Y` | [D + XX] + Y | 2 |
| DP Indirect Long | `[$XX]` or `[Rn]` | 32-bit [D + XX] | 2 |
| DP Ind Long Indexed | `[$XX],Y` | 32-bit [D + XX] + Y | 2 |
| Absolute | `B+$XXXX` | B + XXXX | 3 |
| Abs Indexed X | `B+$XXXX,X` | B + XXXX + X | 3 |
| Abs Indexed Y | `B+$XXXX,Y` | B + XXXX + Y | 3 |
| Abs Indirect | `($XXXX)` | [B + XXXX] | 3 |
| Abs Indexed Indirect | `($XXXX,X)` | [B + XXXX + X] | 3 |
| 32-bit Absolute | `LD Rn, $XXXXXXXX` | Extended ALU only |
| Stack Relative | `$XX,S` | S + XX | 2 |
| SR Indirect Indexed | `($XX,S),Y` | [S + XX] + Y | 2 |
| Relative | `label` | PC + 2 + offset8 | 2 |
| Relative Long | `label` | PC + 3 + offset16 | 3 |

**32-bit mode:** Use `Rn` for registers, `B+$XXXX` for B-relative; 32-bit absolute (`$XXXXXXXX`) is Extended ALU only.

---

## Instruction Summary

### Load/Store
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| LDA src | A = src | NZ |
| LDX src | X = src | NZ |
| LDY src | Y = src | NZ |
| STA dst | [dst] = A | — |
| STX dst | [dst] = X | — |
| STY dst | [dst] = Y | — |
| STZ dst | [dst] = 0 | — |

### Arithmetic
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| ADC src | A = A + src + C | NVZC |
| SBC src | A = A - src - !C | NVZC |
| INC dst | dst = dst + 1 | NZ |
| DEC dst | dst = dst - 1 | NZ |
| INX / INY | X/Y = X/Y + 1 | NZ |
| DEX / DEY | X/Y = X/Y - 1 | NZ |

### Logic
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| AND src | A = A & src | NZ |
| ORA src | A = A \| src | NZ |
| EOR src | A = A ^ src | NZ |
| BIT src | test A & src | NVZ |
| TSB dst | [dst] \|= A | Z |
| TRB dst | [dst] &= ~A | Z |

### Shifts
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| ASL dst | C ← dst ← 0 | NZC |
| LSR dst | 0 → dst → C | NZC |
| ROL dst | C ← dst ← C | NZC |
| ROR dst | C → dst → C | NZC |

### Compare
| Instruction | Operation | Flags |
|-------------|-----------|-------|
| CMP src | A - src (discard) | NZC |
| CPX src | X - src (discard) | NZC |
| CPY src | Y - src (discard) | NZC |

### Branches (relative)
8-bit relative in 8/16-bit modes, 16-bit relative in 32-bit mode.
| Instruction | Condition | Opcode |
|-------------|-----------|--------|
| BPL rel | N = 0 | $10 |
| BMI rel | N = 1 | $30 |
| BVC rel | V = 0 | $50 |
| BVS rel | V = 1 | $70 |
| BCC rel | C = 0 | $90 |
| BCS rel | C = 1 | $B0 |
| BNE rel | Z = 0 | $D0 |
| BEQ rel | Z = 1 | $F0 |
| BRA rel | Always | $80 |
| BRL rel16 | Always (16-bit) | $82 |

### Jump/Call
| Instruction | Operation | Opcode |
|-------------|-----------|--------|
| JMP abs | PC = B + abs | $4C |
| JMP (abs) | PC = [B + abs] | $6C |
| JMP (abs,X) | PC = [B + abs + X] | $7C |
| JML long | PC = long | $5C |
| JSR abs | push PC-1; PC = abs | $20 |
| JSL long | push PC; PC = long | $22 |
| RTS | PC = pull + 1 | $60 |
| RTL | PC = pull (long) | $6B |
| RTI | P = pull; PC = pull | $40 |

### Stack
| Instruction | Operation | Opcode |
|-------------|-----------|--------|
| PHA / PLA | Push/Pull A | $48/$68 |
| PHX / PLX | Push/Pull X | $DA/$FA |
| PHY / PLY | Push/Pull Y | $5A/$7A |
| PHP / PLP | Push/Pull P | $08/$28 |
| PHD / PLD | Push/Pull D | $0B/$2B |
| PHB / PLB | Push/Pull B | $8B/$AB |
| PHK | Push program bank | $4B |
| PEA #imm16 | Push imm16 | $F4 |
| PEI (dp) | Push [dp] | $D4 |
| PER rel16 | Push PC + rel | $62 |

### Transfers
| Instruction | Operation | Opcode | Flags |
|-------------|-----------|--------|-------|
| TAX / TXA | A ↔ X | $AA/$8A | NZ |
| TAY / TYA | A ↔ Y | $A8/$98 | NZ |
| TXY / TYX | X ↔ Y | $9B/$BB | NZ |
| TSX / TXS | S → X / X → S | $BA/$9A | NZ/— |
| TCD / TDC | A → D / D → A | $5B/$7B | NZ |
| TCS / TSC | A → S / S → A | $1B/$3B | —/NZ |

### Status Flags
| Instruction | Operation | Opcode |
|-------------|-----------|--------|
| CLC / SEC | C = 0 / 1 | $18/$38 |
| CLI / SEI | I = 0 / 1 | $58/$78 |
| CLD / SED | D = 0 / 1 | $D8/$F8 |
| CLV | V = 0 | $B8 |
| REP #imm | P &= ~imm | $C2 |
| SEP #imm | P \|= imm | $E2 |
| XCE | swap C ↔ E | $FB |

### Block Move
| Instruction | Operation | Opcode |
|-------------|-----------|--------|
| MVN src,dst | Move block (dec) | $54 |
| MVP src,dst | Move block (inc) | $44 |

Setup: X=src, Y=dst, A=count-1

### Control
| Instruction | Operation | Opcode |
|-------------|-----------|--------|
| NOP | No operation | $EA |
| BRK | Software break | $00 |
| COP #sig | Coprocessor | $02 (6502/65816) |
| WAI | Wait for IRQ | $CB |
| STP | Stop until reset | $DB |

---

## M65832 Extended Instructions

All extended instructions use the `$02` prefix.

### Multiply/Divide
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| MUL dp | $02 $00 | A = A × [dp] (signed) |
| MULU dp | $02 $01 | A = A × [dp] (unsigned) |
| MUL abs | $02 $02 | A = A × [abs] (signed) |
| MULU abs | $02 $03 | A = A × [abs] (unsigned) |
| DIV dp | $02 $04 | A = A / [dp]; T = remainder |
| DIVU dp | $02 $05 | (unsigned) |
| DIV abs | $02 $06 | A = A / [abs]; T = remainder |
| DIVU abs | $02 $07 | (unsigned) |

**32-bit multiply:** Result high word stored in T register.

### Atomics
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| CAS dp | $02 $10 | if [dp]==X: [dp]=A, Z=1; else X=[dp], Z=0 |
| CAS abs | $02 $11 | (absolute addressing) |
| LLI dp | $02 $12 | A = [dp], set link |
| LLI abs | $02 $13 | (absolute addressing) |
| SCI dp | $02 $14 | if link valid: [dp]=A, Z=1; else Z=0 |
| SCI abs | $02 $15 | (absolute addressing) |
| FENCE | $02 $50 | Full memory barrier |
| FENCER | $02 $51 | Read barrier |
| FENCEW | $02 $52 | Write barrier |

### Base Registers
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| SVBR #imm32 | $02 $20 | VBR = imm32 (supervisor) |
| SVBR dp | $02 $21 | VBR = [dp] |
| SB #imm32 | $02 $22 | B = imm32 |
| SB dp | $02 $23 | B = [dp] |
| SD #imm32 | $02 $24 | D = imm32 |
| SD dp | $02 $25 | D = [dp] |

### Register Window
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| RSET | $02 $30 | R = 1 (DP → registers) |
| RCLR | $02 $31 | R = 0 (DP → memory) |

### System
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| TRAP #n | $02 $40 | System call #n |
| REPE #imm | $02 $60 | ExtP &= ~imm |
| SEPE #imm | $02 $61 | ExtP \|= imm |
| WAI | $CB | Wait for interrupt |
| STP | $DB | Stop processor |

### Temp Register
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| TTA | $02 $9A | A = T |
| TAT | $02 $9B | T = A |

### 64-bit Load/Store
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| LDQ dp | $02 $9C | A:T = [dp] (64-bit) |
| LDQ abs | $02 $9D | A:T = [abs] |
| STQ dp | $02 $9E | [dp] = A:T |
| STQ abs | $02 $9F | [abs] = A:T |

### Extended ALU ($80-$97)

Extended ALU with explicit size/target/mode in a single mode byte.

**Encoding:** `$02 [op] [mode] [dest_dp?] [src...]`

**Mode byte:** `[size:2][target:1][addr_mode:5]`
- Size: 00=BYTE, 01=WORD, 10=LONG
- Target: 0=A, 1=Rn
- addr_mode: 32 addressing options

| Op | Mnemonic | Operation |
|----|----------|-----------|
| $80 | LD | dest = src |
| $81 | ST | [addr] = src |
| $82 | ADC | dest += src + C |
| $83 | SBC | dest -= src + !C |
| $84 | AND | dest &= src |
| $85 | ORA | dest \|= src |
| $86 | EOR | dest ^= src |
| $87 | CMP | flags = dest - src |
| $88 | BIT | flags = dest & src |
| $89 | TSB | [addr] \|= src |
| $8A | TRB | [addr] &= ~src |
| $8B | INC | dest++ |
| $8C | DEC | dest-- |
| $8D | ASL | dest <<= 1 |
| $8E | LSR | dest >>= 1 |
| $8F | ROL | rotate left |
| $90 | ROR | rotate right |
| $97 | STZ | [addr] = 0 |

**Addressing modes (5 bits):**
```
$00 dp          $10 abs32
$01 dp,X        $11 abs32,X
$02 dp,Y        $12 abs32,Y
$08 abs         $18 #imm
$09 abs,X       $19 A
$0A abs,Y       $1A X
                $1B Y
                $1C sr,S
                $1D (sr,S),Y
```

**Examples:**
```asm
LD.B R0, R1      ; 02 80 20 00 04  (5 bytes)
ADC.W R0, #$1234 ; 02 82 78 00 34 12  (6 bytes)
INC.B A          ; 02 8B 00  (3 bytes)
```

### Barrel Shifter ($98)

**Encoding:** `$02 $98 [op|cnt] [dest] [src]` (5 bytes)

| Op (bits 7-5) | Operation |
|---------------|-----------|
| 0 | SHL (logical left) |
| 1 | SHR (logical right) |
| 2 | SAR (arithmetic right) |
| 3 | ROL (rotate left) |
| 4 | ROR (rotate right) |

Bits 4-0: count (0-31), or $1F for shift by A.

### Sign/Zero Extend ($99)

**Encoding:** `$02 $99 [subop] [dest] [src]` (5 bytes)

| Subop | Operation |
|-------|-----------|
| $00 | SEXT8 (sign extend 8→32) |
| $01 | SEXT16 (sign extend 16→32) |
| $02 | ZEXT8 (zero extend 8→32) |
| $03 | ZEXT16 (zero extend 16→32) |
| $04 | CLZ (count leading zeros) |
| $05 | CTZ (count trailing zeros) |
| $06 | POPCNT (population count) |

### Load Effective Address
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| LEA dp | $02 $A0 | A = D + dp |
| LEA dp,X | $02 $A1 | A = D + dp + X |
| LEA abs | $02 $A2 | A = B + abs |
| LEA abs,X | $02 $A3 | A = B + abs + X |

### 32-bit Stack (Extended)
| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| PHD | $02 $70 | Push D (32-bit) |
| PLD | $02 $71 | Pull D (32-bit) |
| PHB | $02 $72 | Push B (32-bit) |
| PLB | $02 $73 | Pull B (32-bit) |
| PHVBR | $02 $74 | Push VBR |
| PLVBR | $02 $75 | Pull VBR |

### Floating Point (16 registers: F0-F15)

All FPU instructions: `$02 [opcode] [reg-byte] [operand...]`
Register byte: `DDDD SSSS` (dest << 4 | src). Load/store uses low nibble for `Fn`,
except `(Rm)` which uses high nibble for `Fn` and low nibble for `Rm`.

| Instruction | Encoding | Description |
|-------------|----------|-------------|
| LDF Fn, dp | $02 $B0 $0n dp | Fn = [D+dp] (64-bit) |
| LDF Fn, abs | $02 $B1 $0n abs | Fn = [B+abs] (64-bit) |
| STF Fn, dp | $02 $B2 $0n dp | [D+dp] = Fn |
| STF Fn, abs | $02 $B3 $0n abs | [B+abs] = Fn |
| LDF Fn, (Rm) | $02 $B4 $nm | Fn = [[Rm]] (64-bit) |
| STF Fn, (Rm) | $02 $B5 $nm | [[Rm]] = Fn |
| LDF Fn, abs32 | $02 $B6 $0n abs32 | Fn = [abs32] (64-bit) |
| STF Fn, abs32 | $02 $B7 $0n abs32 | [abs32] = Fn |
| LDF.S Fn, (Rm) | $02 $BA $nm | Fn[31:0] = [[Rm]] (32-bit) |
| STF.S Fn, (Rm) | $02 $BB $nm | [[Rm]] = Fn[31:0] |

| Instruction | Encoding | Operation |
|-------------|----------|-----------|
| FADD.S Fd, Fs | $02 $C0 $ds | Fd = Fd + Fs (single) |
| FSUB.S Fd, Fs | $02 $C1 $ds | Fd = Fd - Fs |
| FMUL.S Fd, Fs | $02 $C2 $ds | Fd = Fd × Fs |
| FDIV.S Fd, Fs | $02 $C3 $ds | Fd = Fd / Fs |
| FNEG.S Fd, Fs | $02 $C4 $ds | Fd = -Fs |
| FABS.S Fd, Fs | $02 $C5 $ds | Fd = \|Fs\| |
| FCMP.S Fd, Fs | $02 $C6 $ds | Compare Fd, Fs |
| F2I.S Fd | $02 $C7 $d0 | A = (int32)Fd |
| I2F.S Fd | $02 $C8 $d0 | Fd = (float32)A |
| FMOV.S Fd, Fs | $02 $C9 $ds | Fd = Fs (copy) |
| FSQRT.S Fd, Fs | $02 $CA $ds | Fd = √Fs |
| FADD.D ... | $02 $D0-$DA | (same pattern, double) |

**Example:** `FADD.S F3, F7` → `$02 $C0 $37` (F3 = F3 + F7)

| Transfers | Encoding | Operation |
|-----------|----------|-----------|
| FTOA Fd | $02 $E0 $d0 | A = Fd[31:0] |
| FTOT Fd | $02 $E1 $d0 | T = Fd[63:32] |
| ATOF Fd | $02 $E2 $d0 | Fd[31:0] = A |
| TTOF Fd | $02 $E3 $d0 | Fd[63:32] = T |
| FCVT.DS Fd, Fs | $02 $E4 $ds | Fd = (double)Fs |
| FCVT.SD Fd, Fs | $02 $E5 $ds | Fd = (single)Fs |

**FCMP flags:** Z=1 if equal, C=1 if Fd≥Fs, N=1 if Fd<Fs

Reserved FPU opcodes $CB-$CF and $DB-$DF trap to software emulation; $E6-$FF are illegal.

---

## Data Sizing (32-bit Mode)

In 32-bit mode:
- **Traditional instructions** operate on 32-bit data
- **Extended ALU** ($02 $80-$97) supports 8/16/32-bit via mode byte
- M/X width flags are ignored for sizing in 32-bit mode

```asm
; Traditional instructions - always 32-bit data
LDA #$12345678          ; 32-bit immediate
LDA B+$1234             ; B-relative addressing

; 32-bit absolute - Extended ALU only:
LD R0, $A0001234        ; Extended ALU with 32-bit address

; For 8-bit/16-bit ops, use Extended ALU:
LD.B R0, #$12           ; 8-bit immediate to R0
LD.W R0, #$1234         ; 16-bit immediate to R0
ADC.B A, R1             ; 8-bit add

; WAI/STP (standard 65816)
WAI                     ; $CB
STP                     ; $DB
; $42 is reserved/unused in 32-bit mode
```

---

## Register Window (R=1)

When R=1, Direct Page accesses map to 64 hardware registers (not memory):

```
Offset    Register        Offset    Register
$00-$03   R0              $80-$83   R32
$04-$07   R1              $84-$87   R33
$08-$0B   R2              ...
...                       $FC-$FF   R63
$7C-$7F   R31
```

Each register is 32-bit. **Use `Rn` notation in 32-bit mode:**

```asm
LDA R0              ; Preferred (same as LDA $00)
STA R15             ; Preferred (same as STA $3C)
LDA R4,X            ; Register indexed
LDA (R0),Y          ; Register indirect indexed
```

Byte access within registers: `LDA.B R4` or `LDA.B $10`

---

## Exception Vectors (Native Mode)

| Address | Exception | Priority |
|---------|-----------|----------|
| $FFFF_FFE0 | Reset | 1 (highest) |
| $FFFF_FFE4 | NMI | 2 |
| $FFFF_FFE8 | IRQ | 5 |
| $FFFF_FFEC | BRK | 6 |
| $FFFF_FFF0 | TRAP | 4 |
| $FFFF_FFF4 | Page Fault | 3 |
| $FFFF_FFF8 | Illegal Op | 3 |
| $FFFF_FFFC | Alignment | 3 |

### Emulation Mode Vectors (VBR-relative)
| Offset | Exception |
|--------|-----------|
| $FFFA | NMI |
| $FFFC | Reset |
| $FFFE | IRQ/BRK |

---

## Memory Map (Typical Linux)

```
$0000_0000 - $0000_FFFF   6502 compatibility zone
$0001_0000 - $7FFF_FFFF   User space
$8000_0000 - $BFFF_FFFF   Kernel direct-mapped / I/O
$C000_0000 - $FFFF_EFFF   Kernel vmalloc
$FFFF_F000 - $FFFF_FFFF   System registers / Vectors
```

---

## Common Code Patterns

### Initialization (Reset Handler)
```asm
reset:
    CLC
    XCE                     ; E=0 (native mode)
    REP #$30                ; 16-bit A/X/Y
    REPE #$A0               ; 32-bit A/X/Y
    SD #$00010000           ; D = data segment
    SB #$00000000           ; B = 0 (flat)
    LDX #$FFFFC000
    TXS                     ; Set up stack
    RSET                    ; Enable register window
```

### 32-bit Addition
```asm
    CLC
    LDA num1
    ADC num2
    STA result
```

### Loop Counter
```asm
        LDX #100
loop:   ; ... body ...
        DEX
        BNE loop
```

### Function Call (Register ABI)
```asm
    ; Call: result = func(a, b)
    LDA arg_a
    STA R0                  ; R0 = first arg
    LDA arg_b
    STA R1                  ; R1 = second arg
    JSR function
    LDA R0                  ; Return value in R0
    STA result
```

### Spinlock Acquire
```asm
acquire:
    LDX #0                  ; Expected: unlocked
    LDA #1                  ; Desired: locked
.spin:
    CAS lock
    BNE .spin               ; Retry if Z=0
    FENCE                   ; Memory barrier
    RTS
```

### Spinlock Release
```asm
release:
    FENCE                   ; Ensure writes visible
    STZ lock                ; Clear lock
    RTS
```

### Atomic Increment
```asm
atomic_inc:
    LDA counter
.retry:
    TAX                     ; X = expected
    INC                     ; A = new value
    CAS counter
    BNE .retry              ; Retry on failure
    RTS
```

### System Call
```asm
    LDA #SYS_WRITE
    STA R0                  ; R0 = syscall number
    LDA #fd
    STA R1                  ; R1 = fd
    LDA #buffer
    STA R2                  ; R2 = buffer
    LDA #count
    STA R3                  ; R3 = count
    TRAP #0
    ; Return in R0
```

### 64-bit Multiply Result
```asm
    LDA multiplicand
    MUL multiplier          ; 32×32 → 64-bit result
    STA result_lo           ; Low 32 bits in A
    TTA                     ; Get high 32 bits from T
    STA result_hi
```

### Compare and Branch
```asm
    LDA value
    CMP #100
    BCC less_than           ; value < 100
    BEQ equal               ; value == 100
    ; else value > 100
```

---

## Quick Opcode Reference

### Special Bytes (32-bit Mode)
| Byte(s) | Meaning | Notes |
|---------|---------|-------|
| $02 | Extended opcode follows | M65832 new instructions |
| $CB | WAI | Wait for Interrupt (65816) |
| $DB | STP | Stop Processor (65816) |

### Common Opcodes
| Op | Instruction | Op | Instruction |
|----|-------------|----|--------------| 
| $00 | BRK | $60 | RTS |
| $18 | CLC | $78 | SEI |
| $20 | JSR abs | $A9 | LDA # |
| $38 | SEC | $AD | LDA abs |
| $4C | JMP abs | $8D | STA abs |
| $58 | CLI | $C2 | REP # |
| $40 | RTI | $E2 | SEP # |
| $EA | NOP | $FB | XCE |

---

## See Also

- [M65832 Instruction Set](M65832_Instruction_Set.md) - Complete instruction reference
- [M65832 Architecture Reference](M65832_Architecture_Reference.md) - Full architecture documentation
- [M65832 Assembler Reference](M65832_Assembler_Reference.md) - Assembler usage and syntax
- [M65832 Disassembler Reference](M65832_Disassembler_Reference.md) - Disassembler usage and API

---

*M65832 Quick Reference - Verified against RTL*
