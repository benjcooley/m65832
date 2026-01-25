# M65832 Assembler Reference

A complete reference for the M65832 two-pass assembler.

## Overview

The M65832 assembler (`m65832as`) is a portable, single-file assembler written in C that supports the full M65832 instruction set, including all 6502/65816 compatible instructions and M65832 extensions.

### Features

- Two-pass assembly for forward references
- Full 6502/65816 instruction set compatibility
- M65832 extended instructions (MUL, DIV, atomics, FPU, etc.)
- WID prefix for 32-bit operations
- Include file support with search paths
- Multiple section support
- Expression evaluation with operators
- Binary and Intel HEX output formats
- Case-insensitive mnemonics and labels

## Building

### Using Make

```bash
cd as
make
```

### Direct Compilation

```bash
cc -O2 -Wall -o m65832as m65832as.c
```

### Debug Build

```bash
make debug
```

## Command Line Usage

```
m65832as [options] input.asm
```

### Options

| Option | Description |
|--------|-------------|
| `-o FILE` | Specify output file (default: `a.out`) |
| `-I PATH` | Add include search path (can be specified multiple times) |
| `-h`, `--hex` | Output Intel HEX format instead of binary |
| `-l` | List symbol table after assembly |
| `-v` | Verbose output (show origin, size, sections) |
| `--help` | Display help message |

### Examples

```bash
# Basic assembly to binary
m65832as program.asm -o program.bin

# Assembly with include path
m65832as -I inc -I ../common program.asm -o program.bin

# Intel HEX output with symbol listing
m65832as -h -l -v program.asm -o program.hex

# Multiple include paths
m65832as -I./inc -I./lib -I../shared main.asm -o main.bin
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Assembly errors occurred |

## Source File Format

### Character Set

- Source files are ASCII text
- Lines may be terminated with LF (Unix) or CR+LF (Windows)
- Maximum line length: 1024 characters

### Line Structure

Each line may contain:
1. Optional label (at start of line or with colon)
2. Optional instruction or directive
3. Optional operand(s)
4. Optional comment (starting with `;`)

```asm
label:  LDA #$12    ; This is a comment
```

### Comments

Comments begin with a semicolon and extend to end of line:

```asm
; This is a full-line comment
    LDA #$00    ; This is an inline comment
```

### Labels

Labels identify memory locations. They can be defined with or without a trailing colon:

```asm
start:          ; Label with colon
    NOP
loop            ; Label without colon (must start at column 1)
    DEX
    BNE loop
```

**Label Rules:**
- Must start with a letter or underscore
- May contain letters, digits, underscores, and periods
- Maximum length: 63 characters
- Case-insensitive (`START` and `start` are the same)

### Local Labels

Labels starting with a period are local to the enclosing non-local label:

```asm
function1:
    LDA #0
.loop:              ; Local to function1
    DEX
    BNE .loop
    RTS

function2:
    LDX #10
.loop:              ; Different label, local to function2
    DEY
    BNE .loop
    RTS
```

## Numeric Formats

### Integer Literals

| Format | Example | Description |
|--------|---------|-------------|
| `$xx` | `$FF` | Hexadecimal |
| `0xNN` | `0xFF` | C-style hexadecimal |
| `NNN` | `255` | Decimal |
| `%bbbb` | `%11111111` | Binary |
| `'c'` | `'A'` | Character (ASCII value) |

### Special Values

| Symbol | Meaning |
|--------|---------|
| `*` | Current program counter |

## Expressions

Expressions can be used wherever a numeric value is expected.

### Operators

**Unary operators** (evaluated first):

| Operator | Description |
|----------|-------------|
| `-` | Negation |
| `<` | Low byte (bits 0-7) |
| `>` | High byte (bits 8-15) |
| `^` | Bank byte (bits 16-23) |

**Binary operators** (left-to-right, use parentheses for grouping):

| Operator | Description |
|----------|-------------|
| `+` | Addition |
| `-` | Subtraction |
| `*` | Multiplication |
| `/` | Division (integer, truncates toward zero) |
| `%` | Modulo |
| `&` | Bitwise AND |
| `\|` | Bitwise OR |
| `^` | Bitwise XOR |

**Grouping:**

| Operator | Description |
|----------|-------------|
| `( )` | Parentheses for grouping sub-expressions |

**Note:** Shift operators (`<<`, `>>`) are not currently supported. Use multiplication/division by powers of 2, or the `<`/`>` unary operators for byte extraction.

### Expression Examples

```asm
    LDA #<address       ; Low byte of address
    LDA #>address       ; High byte of address
    LDA #^address       ; Bank byte of address
    
    LDA #value + 1      ; Addition
    LDA #value * 2      ; Multiplication
    LDA #value / 4      ; Division
    LDA #value % 256    ; Modulo
    LDA #value & $FF    ; Bitwise AND
    LDA #value | $80    ; Bitwise OR
    
    LDA #(value + 1) * 2    ; Grouping
    
    .BYTE * - start     ; Current PC minus start
```

## Directives

### Origin Control

#### `.ORG` / `ORG` / `*=`

Set the assembly origin (program counter):

```asm
.ORG $8000          ; Set origin to $8000
ORG $8000           ; Alternative syntax
* = $8000           ; Alternative syntax
```

### Data Definition

#### `.BYTE` / `.DB` / `DB` / `.DCB`

Define byte values:

```asm
.BYTE $12, $34, $56     ; Multiple bytes
.BYTE "Hello", 0        ; String with null terminator
.DB 1, 2, 3             ; Alternative syntax
```

**String Escape Sequences:**
- `\n` - Newline (0x0A)
- `\r` - Carriage return (0x0D)
- `\t` - Tab (0x09)
- `\0` - Null (0x00)
- `\\` - Backslash
- `\"` - Double quote

#### `.WORD` / `.DW` / `DW` / `.DCW`

Define 16-bit words (little-endian):

```asm
.WORD $1234, $5678      ; Multiple words
.WORD label             ; Address of label
.DW table_end - table   ; Computed value
```

#### `.LONG` / `.DL` / `.DCL`

Define 24-bit values (little-endian):

```asm
.LONG $123456           ; 24-bit value
.LONG far_address       ; 24-bit address
```

#### `.DWORD` / `.DD` / `.DCD`

Define 32-bit values (little-endian):

```asm
.DWORD $12345678        ; 32-bit value
.DD address32           ; 32-bit address
```

### Space Reservation

#### `.DS` / `DS` / `.RES` / `.SPACE`

Reserve space (filled with zeros during assembly):

```asm
.DS 256                 ; Reserve 256 bytes
buffer: .RES 1024       ; Named buffer
```

#### `.ALIGN` / `ALIGN`

Align program counter to boundary:

```asm
.ALIGN 4                ; Align to 4-byte boundary
.ALIGN 256              ; Align to page boundary
```

### Symbol Definition

#### `.EQU` / `EQU` / `=`

Define a constant symbol:

```asm
VALUE = $10             ; Using =
VALUE .EQU $10          ; Using .EQU
VALUE EQU $10           ; Using EQU (no dot)
```

#### `.SET`

Define or redefine a symbol (allows redefinition):

```asm
COUNTER .SET 0
; ... code ...
COUNTER .SET COUNTER + 1
```

### Width Hints

These directives tell the assembler the current processor mode for proper immediate operand sizing:

#### Accumulator Width

```asm
.M8  / .A8              ; 8-bit accumulator
.M16 / .A16             ; 16-bit accumulator (default)
.M32 / .A32             ; 32-bit accumulator
```

#### Index Register Width

```asm
.X8  / .I8              ; 8-bit index registers
.X16 / .I16             ; 16-bit index registers (default)
.X32 / .I32             ; 32-bit index registers
```

### Include Files

#### `.INCLUDE` / `INCLUDE` / `.INC`

Include another source file:

```asm
.INCLUDE "macros.inc"       ; Quoted filename
.INCLUDE <system.inc>       ; Angle brackets
.INC "defs.asm"             ; Short form
```

**Search Order:**
1. Relative to current file's directory
2. Directories specified with `-I` option (in order)
3. As specified (absolute or relative to working directory)

**Limits:**
- Maximum include depth: 16 levels
- Maximum include paths: 8

### Sections

#### `.SECTION` / `SECTION`

Switch to a named section:

```asm
.SECTION TEXT           ; Switch to TEXT section
.SECTION DATA           ; Switch to DATA section
.SECTION MySection      ; Custom section name
```

#### Predefined Section Shortcuts

```asm
.TEXT / .CODE           ; Code section
.DATA                   ; Initialized data section
.RODATA                 ; Read-only data section
.BSS                    ; Uninitialized data section
```

**Section Behavior:**
- Each section maintains its own program counter
- Use `.ORG` within a section to set its origin
- Switching back to a section resumes at its previous PC
- Output is a flat binary spanning all sections (gaps filled with $FF)

```asm
.SECTION TEXT
.ORG $1000
    LDA #0
    JMP done

.SECTION DATA
.ORG $2000
table:
    .BYTE 1, 2, 3, 4

.SECTION TEXT           ; Resume TEXT section
done:
    RTS                 ; Continues at $1006
```

### End of File

#### `.END` / `END`

Mark end of assembly (optional, remaining content is ignored):

```asm
    RTS
.END
; This is ignored
```

## Addressing Modes

### Implied

No operand required:

```asm
    NOP                 ; $EA
    CLC                 ; $18
    RTS                 ; $60
```

### Accumulator

Operates on accumulator (A can be omitted):

```asm
    ASL                 ; $0A - Shift accumulator left
    ASL A               ; $0A - Explicit form
    ROL                 ; $2A
    ROR                 ; $6A
    LSR                 ; $4A
```

### Immediate

8/16/32-bit value depending on mode:

```asm
.M8
    LDA #$12            ; 8-bit: A9 12
.M16
    LDA #$1234          ; 16-bit: A9 34 12
.M32
    LDA #$12345678      ; 32-bit (with WID): 42 A9 78 56 34 12
```

### Direct Page

8-bit address in Direct Page:

```asm
    LDA $10             ; $A5 $10
    STA $20             ; $85 $20
```

### Direct Page Indexed

```asm
    LDA $10,X           ; $B5 $10 - DP + X
    LDA $10,Y           ; $B6 $10 - DP + Y (only LDX, STX)
```

### Absolute

16-bit address:

```asm
    LDA $1234           ; $AD $34 $12
    JMP $8000           ; $4C $00 $80
    JSR subroutine      ; $20 ...
```

### Absolute Indexed

```asm
    LDA $1234,X         ; $BD $34 $12
    LDA $1234,Y         ; $B9 $34 $12
    STA $1234,X         ; $9D $34 $12
```

### Absolute Long (24-bit)

```asm
    LDA $123456         ; $AF $56 $34 $12
    JML $123456         ; $5C $56 $34 $12
    JSL $123456         ; $22 $56 $34 $12
```

### Absolute Long Indexed

```asm
    LDA $123456,X       ; $BF $56 $34 $12
```

### Indirect

```asm
    LDA ($10)           ; $B2 $10 - DP indirect
    JMP ($1234)         ; $6C $34 $12 - Absolute indirect
```

### Indexed Indirect

```asm
    LDA ($10,X)         ; $A1 $10
```

### Indirect Indexed

```asm
    LDA ($10),Y         ; $B1 $10
```

### Indirect Long

```asm
    LDA [$10]           ; $A7 $10
    JML [$1234]         ; $DC $34 $12
```

### Indirect Long Indexed

```asm
    LDA [$10],Y         ; $B7 $10
```

### Stack Relative

```asm
    LDA $10,S           ; $A3 $10
```

### Stack Relative Indirect Indexed

```asm
    LDA ($10,S),Y       ; $B3 $10
```

### Relative (Branches)

8-bit signed offset from next instruction:

```asm
    BEQ label           ; $F0 offset
    BNE label           ; $D0 offset
    BCC label           ; $90 offset
    BCS label           ; $B0 offset
    BMI label           ; $30 offset
    BPL label           ; $10 offset
    BVC label           ; $50 offset
    BVS label           ; $70 offset
    BRA label           ; $80 offset
```

### Relative Long

16-bit signed offset:

```asm
    BRL label           ; $82 offset_lo offset_hi
    PER label           ; $62 offset_lo offset_hi
```

### Block Move

```asm
    MVP #$01,#$02       ; $44 $02 $01 - Move positive
    MVN #$01,#$02       ; $54 $02 $01 - Move negative
```

## M65832 Extended Instructions

All extended instructions are prefixed with opcode $02.

### Multiply and Divide

```asm
    MUL $20             ; Signed: A = A * [DP]
    MULU $20            ; Unsigned multiply
    MUL $1234           ; Absolute addressing
    MULU $1234
    
    DIV $20             ; Signed: A = A / [DP], T = remainder
    DIVU $20            ; Unsigned divide
    DIV $1234           ; Absolute addressing
    DIVU $1234
```

### Atomic Operations

```asm
    CAS $20             ; Compare and swap (DP)
    CAS $1234           ; Compare and swap (absolute)
    LLI $20             ; Load linked (DP)
    LLI $1234           ; Load linked (absolute)
    SCI $20             ; Store conditional (DP)
    SCI $1234           ; Store conditional (absolute)
```

### Memory Fences

```asm
    FENCE               ; Full memory fence
    FENCER              ; Read fence
    FENCEW              ; Write fence
```

### Base Register Operations

```asm
    SVBR #$10000000     ; Set Vector Base Register (32-bit)
    SVBR $20            ; Set VBR from DP
    SB #$B0000000       ; Set B register (32-bit)
    SB $20              ; Set B from DP
    SD #$00010000       ; Set D register (32-bit)
    SD $20              ; Set D from DP
```

### Register Window

```asm
    RSET                ; Enable register window (R=1)
    RCLR                ; Disable register window (R=0)
```

### System Operations

```asm
    TRAP #$10           ; System trap with 8-bit code
    REPE #$A0           ; Clear extended P bits
    SEPE #$A0           ; Set extended P bits
```

### Temp Register

```asm
    TTA                 ; Transfer T to A
    TAT                 ; Transfer A to T
```

### 64-bit Operations

```asm
    LDQ $20             ; Load 64-bit: T:A = [DP]
    LDQ $1234           ; Load 64-bit: T:A = [absolute]
    STQ $20             ; Store 64-bit: [DP] = T:A
    STQ $1234           ; Store 64-bit: [absolute] = T:A
```

### Load Effective Address

```asm
    LEA $20             ; A = D + $20
    LEA $20,X           ; A = D + $20 + X
    LEA $1234           ; A = B + $1234
    LEA $1234,X         ; A = B + $1234 + X
```

### FPU Load/Store

```asm
    LDF0 $20            ; Load F0 from DP
    LDF0 $1234          ; Load F0 from absolute
    STF0 $20            ; Store F0 to DP
    STF0 $1234          ; Store F0 to absolute
    LDF1 $20            ; Load F1
    STF1 $1234          ; Store F1
    LDF2 $20            ; Load F2
    STF2 $1234          ; Store F2
```

### FPU Arithmetic (Single Precision)

```asm
    FADD.S              ; F0 = F1 + F2
    FSUB.S              ; F0 = F1 - F2
    FMUL.S              ; F0 = F1 * F2
    FDIV.S              ; F0 = F1 / F2
    FNEG.S              ; F0 = -F1
    FABS.S              ; F0 = |F1|
    FSQRT.S             ; F0 = sqrt(F1)
    FSIN.S              ; F0 = sin(F1)
    FCOS.S              ; F0 = cos(F1)
    FTAN.S              ; F0 = tan(F1)
    FLOG.S              ; F0 = log(F1)
    FEXP.S              ; F0 = exp(F1)
    FCMP.S              ; Compare F1 to F2, set flags
    F2I.S               ; A = (int)F1
    I2F.S               ; F0 = (float)A
```

### FPU Arithmetic (Double Precision)

```asm
    FADD.D              ; F0 = F1 + F2
    FSUB.D              ; F0 = F1 - F2
    FMUL.D              ; F0 = F1 * F2
    FDIV.D              ; F0 = F1 / F2
    ; ... (same operations as single precision)
```

### FPU Register Moves

```asm
    FMV01               ; F0 = F1
    FMV10               ; F1 = F0
    FMV02               ; F0 = F2
    FMV20               ; F2 = F0
    FMV12               ; F1 = F2
    FMV21               ; F2 = F1
    S2D                 ; Convert single to double
    D2S                 ; Convert double to single
```

## WID Prefix

The WID prefix ($42) enables 32-bit operands:

```asm
    WID LDA #$12345678      ; 32-bit immediate load
    WID LDA $12345678       ; 32-bit absolute address
    WID STA $12345678       ; 32-bit absolute store
    WID JMP $C0001000       ; Jump to 32-bit address
```

## Output Formats

### Binary (Default)

Raw binary starting at the first `.ORG` address. Gaps between sections are filled with $FF.

### Intel HEX (`-h` option)

Standard Intel HEX format with:
- 16 bytes per data record
- Extended Linear Address records for addresses > $FFFF
- EOF record

Compatible with EPROM programmers and bootloaders.

## Error Messages

| Error | Cause |
|-------|-------|
| `cannot open 'file'` | Input file not found |
| `unknown instruction 'XXX'` | Unrecognized mnemonic |
| `invalid addressing mode` | Operand syntax doesn't match instruction |
| `undefined symbol 'XXX'` | Label referenced but never defined |
| `symbol 'XXX' already defined` | Duplicate label definition |
| `invalid expression` | Malformed numeric expression |
| `division by zero` | Division or modulo by zero in expression |
| `unterminated string` | String literal missing closing quote |
| `label too long` | Label exceeds 63 characters |
| `include nesting too deep` | More than 16 levels of includes |
| `cannot open include file` | Include file not found |

## Limits

| Resource | Limit |
|----------|-------|
| Output size | 1 MB |
| Symbols | 4,096 |
| Sections | 16 |
| Include depth | 16 |
| Include paths | 8 |
| Line length | 1,024 characters |
| Label length | 63 characters |

## See Also

- [M65832 Disassembler Reference](M65832_Disassembler_Reference.md)
- [M65832 Instruction Set](M65832_Instruction_Set.md)
- [M65832 Architecture Reference](M65832_Architecture_Reference.md)
- [M65832 Quick Reference](M65832_Quick_Reference.md)
