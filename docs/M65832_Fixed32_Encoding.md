# M65832 Fixed-Width 32-bit Instruction Encoding

**Version:** 1.2
**Status:** Official
**Scope:** 32-bit native mode (W=11) only

## Overview

This document specifies the fixed-width 32-bit instruction encoding for the
m65832 processor in 32-bit native mode (W=11). This encoding replaces the
variable-length byte-stream encoding used in legacy modes with a uniform
32-bit instruction word designed for pipelined and out-of-order execution.

Legacy modes (6502 emulation W=00, 65816 native W=01) retain the existing
variable-length encoding unchanged and are handled by separate compatibility
cores.

### Transition Context

The m65832 project maintains two processor implementations in parallel:

- **Existing VHDL core** (`rtl/m65832_core.vhd`): Multi-cycle FSM supporting
  all three modes (W=00/01/11) with variable-length encoding. This core
  continues to serve as the platform for Linux bring-up, LLVM compiler
  development, emulator validation, and the existing test suites (383+
  assembly tests, 164 C compiler tests, picolibc). It is the reference
  implementation for architectural correctness.

- **vcore** (`vcore/`): Modern pipelined processor targeting fixed-width
  32-bit encoding in W=11 mode only. Designed for high-frequency FPGA
  operation with branch prediction, caches, and potential out-of-order
  execution (via RSD fork or custom pipeline). The first hardware target.

Both cores execute the same m65832 architecture. The fixed-width encoding
is a re-encoding of the 32-bit native mode instruction set, not a new ISA.
Programs compiled for one encoding are semantically equivalent; only the
binary representation differs.

### Compatibility Strategy

The vcore handles W=11 (fixed-width) exclusively. Legacy modes are supported
by interleaving dedicated 8-bit and 16-bit compatibility cores using the
existing coprocessor interleaving mechanism (`m65832_interleave.vhd`):

- W=00 (6502 emulation): Handled by MX65 or equivalent 8-bit core
- W=01 (65816 native): Handled by P65816 or equivalent 16-bit core
- W=11 (32-bit native): Handled by vcore (fixed-width)

Mode switches (SEPE/REPE/XCE) trigger context transfer between cores.
If the vcore runs at higher frequency than the legacy cores require, legacy
execution can be interleaved via cycle-stealing with negligible impact.

Long-term, a microcode compatibility frontend may replace the separate
legacy cores, allowing the vcore backend to execute all modes.

---

## Architectural Changes

The fixed-width encoding preserves the m65832 architecture (registers,
operations, flag behavior, memory model) but introduces the following
changes to the 32-bit native mode programming model.

### Register File

All registers are addressed by a 6-bit register ID (R0-R63). The named
architectural registers are mapped to the top of the register space,
leaving the bottom as a contiguous block for general-purpose use.

```text
R0       = ZERO   (hardwired to zero; writes are discarded)
R1-R55   = General purpose (compiler register allocation pool)
R56      = A      (accumulator)
R57      = X      (index X)
R58      = Y      (index Y)
R59      = SP     (stack pointer)
R60      = D      (direct page base)
R61      = B      (absolute base)
R62      = VBR    (vector base register, supervisor)
R63      = T      (temp / MUL high word / DIV remainder)
```

**R0 = Zero register.** Reads always return 0. Writes are silently
discarded. This enables result discard (`ADD R0, R5, R6` for flag-only
computation), free zero constant, NOP encoding (`ADD R0, R0, R0`), and
simplified pipeline writeback gating.

**R56-R63 = Architectural registers.** The assembler accepts traditional
mnemonics as aliases: `LDA` = `LD R56`, `TAX` = `MOV R57, R56`,
`PHA` = `PUSH R56`.

**R1-R55 = General purpose (55 registers).** These correspond to the
register window (R0-R63 in the variable-length architecture when R=1).
The fixed-width encoding makes them first-class registers addressable
in every instruction format.

### Compiler vs Assembly Programming Models

**Compiler (LLVM) model:** R1-R55 are the register allocation pool.
R56-R63 are reserved and excluded from the allocator. The compiler
works entirely in R1-R55 and only touches architectural registers at
ABI boundaries (syscalls, interrupt entry/exit, hardware-mandated
operations like MUL high result to T). With 55 GPRs, spilling is rare.

**Assembly model:** Hand-written assembly uses traditional mnemonics
(LDA, LDX, TAX, etc.) mapped to R56-R63. The disassembler can
pattern-match instruction sequences involving R56-R63 back to
traditional 65xx addressing modes because the register assignments
are fixed and known. This enables forward translation (assembler)
and backward recognition (disassembler) of traditional instruction
patterns.

### Generalized ALU Operations

All ALU instructions have explicit `rd`, `rs1`, `rs2`/`imm` fields.
Any register can be a source or destination. The variable-length
encoding's accumulator-centric operations (`ADC` always targeting A)
become assembler aliases: `ADC src` = `ADC R56, R56, src`.

### Complex Addressing Modes Decomposed

Variable-length instructions with complex addressing modes (DP indirect,
indirect indexed, etc.) are decomposed into explicit instruction
sequences in fixed-width code:

```asm
; Variable-length:  LDA ($10),Y   (one instruction, 2-3 micro-ops)
; Fixed-width equivalent:
LD   R8, [R60 + 16]     ; load pointer from D+$10
ADD  R8, R8, R58        ; add Y index
LD   R56, [R8 + 0]      ; load through pointer into A
```

Each fixed-width instruction maps to exactly one pipeline operation.
No micro-op cracking is required.

### Implicit Register Conventions

- **MUL Rd, Rs1, Rs2**: low result in Rd, high word in T (R63)
- **DIV Rd, Rs1, Rs2**: quotient in Rd, remainder in T (R63)
- **PUSH/POP**: use SP (R59) implicitly
- **MVN/MVP**: A (R56) = count, X (R57) = source, Y (R58) = dest
- **Interrupts/exceptions**: hardware pushes PC and P via SP (R59)
- **LDQ/STQ**: 64-bit pair uses A:T (R56:R63)

### Floating-Point Register File

FP registers are a separate 16-entry file addressed by 4-bit fields:

```text
F0-F15   = 64-bit FP registers (IEEE 754 single/double)
```

FP registers do not share the R0-R63 integer register space.

### Flag Behavior

- **Flagless by default**: loads, stores, transfers, stack ops, control
  flow, and ALU with F=0 do not modify NZVC flags.
- **Explicit flag-setting**: ALU ops with F=1 update NZVC per instruction.
- **F bit (bit 0)**: in R3 and I13F formats, F=0 is flagless (compiler
  default), F=1 is flag-setting.

### System Register Access

System/MMU/timer/interrupt control registers are accessed via MMIO using
normal LD/ST to architecturally defined addresses. No dedicated CSR
instructions are required.

---

## Instruction Formats

All instructions are exactly 32 bits. Register fields occupy fixed
positions across formats for pipeline-friendly early register read:
`rd` at [25:20], `rs1`/`base` at [19:14].

### R3 (3-register)

```text
31      26 25    20 19    14 13     8 7      1 0
+---------+--------+--------+--------+---------+-+
| opcode  |   rd   |  rs1   |  rs2   |  func7  |F|
+---------+--------+--------+--------+---------+-+
```

Used for: ALU reg-reg, compare, shifts, bitmanip, mul/div, CAS, XFER.

### I13F (register + immediate)

```text
31      26 25    20 19    14 13                1 0
+---------+--------+--------+-------------------+-+
| opcode  |   rd   |  rs1   |      imm13        |F|
+---------+--------+--------+-------------------+-+
```

- Signed: [-4096, 4095]. Unsigned: [0, 8191].

Used for: ALU immediate, compare immediate, shift immediate.

### M14 (load/store)

```text
31      26 25    20 19    14 13               0
+---------+--------+--------+------------------+
| opcode  | rt/rs2 |  base  |      off14       |
+---------+--------+--------+------------------+
```

- `off14` signed byte offset: [-8192, 8191].

### U20 (upper immediate)

```text
31      26 25    20 19                         0
+---------+--------+----------------------------+
| opcode  |   rd   |           imm20            |
+---------+--------+----------------------------+
```

- `LUI`: rd = imm20 << 12.
- `AUIPC`: rd = PC + (imm20 << 12).

### B21 (branch)

```text
31      26 25   22 21 20                      0
+---------+-------+--+-------------------------+
| opcode  | cond4 |L |         off21           |
+---------+-------+--+-------------------------+
```

- target = PC + 4 + (signext(off21) << 2).
- Range: approximately +/-4 MiB.
- L=1: link (save PC+4 to link register for BSR).

#### Branch Conditions (cond4)

| cond4 | Mnemonic | Condition |
|------:|----------|-----------|
| 0x0   | BEQ      | Z=1       |
| 0x1   | BNE      | Z=0       |
| 0x2   | BCS      | C=1       |
| 0x3   | BCC      | C=0       |
| 0x4   | BMI      | N=1       |
| 0x5   | BPL      | N=0       |
| 0x6   | BVS      | V=1       |
| 0x7   | BVC      | V=0       |
| 0x8   | BRA      | always    |
| 0x9-F | reserved | signed/unsigned comparisons |

### J26 (absolute region jump/call)

```text
31      26 25                                0
+---------+-----------------------------------+
| opcode  |             target26              |
+---------+-----------------------------------+
```

- Target: {PC[31:28], target26, 2'b00} (256 MiB region).

### JR (register jump/call)

```text
31      26 25    20 19    14 13              0
+---------+--------+--------+-----------------+
| opcode  |   rd   |  rs1   |      zero       |
+---------+--------+--------+-----------------+
```

### Q20 (64-bit A:T pair load/store)

```text
31      26 25    20 19                      0
+---------+--------+-------------------------+
| opcode  |  base  |          off20          |
+---------+--------+-------------------------+
```

### STACK (single register push/pull)

```text
31      26 25 24    19 18                   0
+---------+--+--------+----------------------+
| opcode  |P |  reg6  |        zero          |
+---------+--+--------+----------------------+
```

- P=0: push. P=1: pull.
- PHA/PLA/PHX/PLX etc. are aliases.

### FP3 (FP register-register)

```text
31      26 25    22 21    18 17    14 13          1 0
+---------+--------+--------+--------+-------------+-+
| opcode  |   fd   |  fs1   |  fs2   |   func9     |R|
+---------+--------+--------+--------+-------------+-+
```

- fd/fs1/fs2: 4-bit FP register IDs (F0-F15).
- func9: FP operation selector.
- R: rounding mode override (0=FPCR default, 1=round-to-nearest).

### FPM (FP load/store)

```text
31      26 25    22 21 20    14 13               0
+---------+--------+--+--------+-----------------+
| opcode  | ft/fs  |D |  base  |     off14       |
+---------+--------+--+--------+-----------------+
```

- D: 0=single (32-bit), 1=double (64-bit).
- base: 6-bit integer register.

### FPI (FP-integer transfer)

```text
31      26 25    22 21    20 19    14 13          0
+---------+--------+--------+--------+------------+
| opcode  |   fd   | subop  |  rs1   |    zero    |
+---------+--------+--------+--------+------------+
```

- subop: F2I, I2F, FMOV_TO_INT, FMOV_FROM_INT.

---

## Operations

### Shift Encoding

Shifts use two opcodes with kind encoded in subfields:

- **SHIFT_R** (R3): func7 encodes kind (0=SHL, 1=SHR, 2=SAR, 3=ROL, 4=ROR)
- **SHIFT_I** (I13F): imm13[12:10]=kind, imm13[4:0]=shamt (0-31)

### Transfers (XFER)

XFER uses R3 format with func7=0 (MOV). Traditional mnemonics are aliases:

| Mnemonic | Fixed-width encoding |
|----------|---------------------|
| TAX      | MOV R57, R56        |
| TXA      | MOV R56, R57        |
| TAY      | MOV R58, R56        |
| TYA      | MOV R56, R58        |
| TAB      | MOV R61, R56        |
| TBA      | MOV R56, R61        |
| TCD      | MOV R60, R56        |
| TDC      | MOV R56, R60        |
| TSX      | MOV R57, R59        |
| TXS      | MOV R59, R57        |

F=1 updates NZ flags. F=0 (default) is flagless.

### CAS (Compare-and-Swap)

R3 format with fixed operand roles:

- rd: expected value (input); overwritten with old memory value (output)
- rs1: address
- rs2: new value (written on match)

```text
old = MEM[rs1]
if old == rd_in: MEM[rs1] = rs2
rd_out = old
```

### FP Operations

| func9 | Mnemonic | Operation |
|-------|----------|-----------|
| 0x00  | FADD.S   | fd = fs1 + fs2 (single) |
| 0x01  | FSUB.S   | fd = fs1 - fs2 (single) |
| 0x02  | FMUL.S   | fd = fs1 * fs2 (single) |
| 0x03  | FDIV.S   | fd = fs1 / fs2 (single) |
| 0x04  | FNEG.S   | fd = -fs1 (single) |
| 0x05  | FABS.S   | fd = abs(fs1) (single) |
| 0x06  | FSQRT.S  | fd = sqrt(fs1) (single) |
| 0x08  | FCMP.S   | NZVC = fs1 <=> fs2 (single) |
| 0x10  | FADD.D   | fd = fs1 + fs2 (double) |
| 0x11  | FSUB.D   | fd = fs1 - fs2 (double) |
| 0x12  | FMUL.D   | fd = fs1 * fs2 (double) |
| 0x13  | FDIV.D   | fd = fs1 / fs2 (double) |
| 0x14  | FNEG.D   | fd = -fs1 (double) |
| 0x15  | FABS.D   | fd = abs(fs1) (double) |
| 0x16  | FSQRT.D  | fd = sqrt(fs1) (double) |
| 0x18  | FCMP.D   | NZVC = fs1 <=> fs2 (double) |
| 0x20  | FCVT.S.D | fd = (single)fs1 |
| 0x21  | FCVT.D.S | fd = (double)fs1 |

### System Operations (SYS sub-opcodes)

| subop | Mnemonic | Operation |
|-------|----------|-----------|
| 0     | TRAP #n  | System call with 20-bit immediate |
| 1     | FENCE    | Full memory barrier |
| 2     | FENCER   | Read barrier |
| 3     | FENCEW   | Write barrier |
| 4     | WAI      | Wait for interrupt |
| 5     | STP      | Stop processor |

---

## Opcode Map

| Range       | Assignment |
|-------------|-----------|
| 0x00-0x0F   | Core ALU + compare (integer), AUIPC |
| 0x10        | SHIFT_R |
| 0x11        | SHIFT_I |
| 0x12        | XFER |
| 0x13-0x16   | FP (FP_RR, FP_LD, FP_ST, FP_CVT) |
| 0x17-0x19   | FP reserved (FMA, etc.) |
| 0x1A-0x24   | MUL/DIV, LD, ST, LUI, AUIPC, LDQ, STQ, CAS, LLI, SCI, bitmanip |
| 0x25        | Branch (B21) |
| 0x26-0x2A   | JMP_ABS, JMP_REG, JSR_ABS, JSR_REG, RTS |
| 0x2B        | STACK |
| 0x2C        | MODE (REP/SEP/REPE/SEPE/RSET/RCLR) |
| 0x2D        | SYS (TRAP/FENCE/WAI/STP) |
| 0x2E        | Block move (MVN/MVP) |
| 0x2F-0x37   | Reserved (future extensions) |
| 0x38-0x3B   | EXT0 (reserved for m65864) |
| 0x3C-0x3D   | EXT1 (reserved for m65864) |
| 0x3E-0x3F   | ESC (experimental/escape) |

---

## Constant Construction

Full 32-bit constants use a two-instruction sequence:

```asm
LUI   R10, 0xABCDE       ; R10 = 0xABCDE000
ORI   R10, R10, 0x123    ; R10 = 0xABCDE123
```

Small constants use the zero register:

```asm
ADD   R5, R0, #42        ; R5 = 42 (single instruction)
```

PC-relative addresses use AUIPC:

```asm
AUIPC R10, 0x00001       ; R10 = PC + 0x1000
ADD   R10, R10, #offset  ; R10 = PC + 0x1000 + offset
```

---

## Immediate and Offset Ranges

| Field | Range | Typical use |
|-------|-------|-------------|
| imm13 signed | -4096 to 4095 | ALU immediate |
| imm13 unsigned | 0 to 8191 | Logic immediate, shift subfields |
| off14 | -8192 to 8191 | Load/store byte offset |
| off20 | -524288 to 524287 | LDQ/STQ offset |
| off21 << 2 | ~+/-4 MiB | Branch range |
| target26 << 2 | 256 MiB | Regional jump/call |
| imm20 << 12 | upper 20 bits | LUI/AUIPC |

---

## Forward Extension Contract (m65864)

Opcode banks 0x38-0x3F are reserved for a future 64-bit ISA extension.

- Base ISA MUST NOT allocate opcodes in 0x38-0x3F.
- Extension ISA SHOULD use EXT0/EXT1 for width-specialized encodings.
- rd/rs1/rs2 bit positions remain invariant across all extensions.

EXT0 example (multi-width ALU): R3 format with func7[6:5] = width class
(00=8, 01=16, 10=32, 11=64), func7[4:0] = ALU op selector. F bit retains
flag policy.

---

## Deferred

- Register-list stack ops (PUSHM/POPM) for prologue density
- Branch hint/likely semantics
- FP fused multiply-add (FMADD, FMSUB, FNMADD, FNMSUB)
- FP min/max, sign-injection, classify
- Signed comparison branch conditions (BLT, BGE, BLE, BGT, BHI, BLS)

---

## Validation

Encoding validated by `vcode/instr32/optb/prove_fixed32_encoding.py`:

- 60 representative encodings verified to fit in 32 bits
- 428 boundary edge cases validated
- Out-of-range values correctly rejected
- Forward extension banks verified free
- Traditional mnemonic aliases round-trip correctly
- Branch condition encoding verified
