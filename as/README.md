# M65832 Assembler and Disassembler

A two-pass assembler and disassembler for the M65832 processor, written in portable C.

**Default Mode:** 32-bit native (M=32, X=32). Use `.m8`/`.m16` and `.x8`/`.x16` directives for legacy 6502/65816 code.

## Building

```bash
make
```

This builds both `m65832as` (assembler) and `m65832dis` (disassembler).

Or directly:

```bash
cc -O2 -o m65832as m65832as.c
cc -O2 -DM65832DIS_STANDALONE -o m65832dis m65832dis.c
```

## Usage

```bash
m65832as [options] input.asm
```

### Options

| Option | Description |
|--------|-------------|
| `-o FILE` | Output file (default: `a.out`) |
| `-I PATH` | Add include search path (can be used multiple times) |
| `-h`, `--hex` | Output Intel HEX format |
| `-l` | List symbols after assembly |
| `-v` | Verbose output |
| `--help` | Show help |

### Examples

```bash
# Assemble to binary
m65832as program.asm -o program.bin

# Assemble to Intel HEX
m65832as -h program.asm -o program.hex

# Verbose with symbol listing
m65832as -v -l program.asm -o program.bin
```

## Assembly Syntax

### Labels

Labels can end with a colon or stand alone:

```asm
start:          ; Label with colon
    LDA #$00
loop            ; Label without colon
    DEX
    BNE loop
```

### Comments

Semicolons start comments:

```asm
    LDA #$10    ; Load 16 into A
```

### Numbers

```asm
    LDA #$FF        ; Hexadecimal
    LDA #255        ; Decimal
    LDA #%11111111  ; Binary
    LDA #0xFF       ; C-style hex
    LDA #'A'        ; Character constant
```

### Expressions

```asm
    LDA #value + 1          ; Addition
    LDA #value - offset     ; Subtraction
    LDA #value * 2          ; Multiplication
    LDA #value / 4          ; Division
    LDA #value % 10         ; Modulo
    LDA #value & $FF        ; Bitwise AND
    LDA #value | $80        ; Bitwise OR
    LDA #value ^ $FF        ; Bitwise XOR
    LDA #<address           ; Low byte (bits 0-7)
    LDA #>address           ; High byte (bits 8-15)
    LDA #^address           ; Bank byte (bits 16-23)
    LDA #-value             ; Negation
    LDA #*                  ; Current PC
    LDA #(1 + 2) * 3        ; Parentheses for grouping
```

## Directives

### Origin

```asm
.ORG $1000          ; Set assembly origin
ORG $1000           ; Also valid
* = $1000           ; Also valid
```

### Data

```asm
.BYTE $12, $34, $56         ; Emit bytes
.DB "Hello", 0              ; Emit string with null
.WORD $1234, label          ; Emit 16-bit words
.DW $1234                   ; Same as .WORD
.LONG $123456               ; Emit 24-bit value
.DWORD $12345678            ; Emit 32-bit value
.DD $12345678               ; Same as .DWORD
```

### Symbols

```asm
VALUE = $10                 ; Define constant
VALUE .EQU $10              ; Same
.EQU VALUE, $10             ; Same
```

### Space and Alignment

```asm
.DS 256             ; Reserve 256 bytes (filled with $00)
.RES 256            ; Same
.ALIGN 4            ; Align to 4-byte boundary
```

### Include Files

```asm
.INCLUDE "filename.inc"     ; Include a file (quoted)
.INCLUDE <filename.inc>     ; Include a file (angle brackets)
.INC "filename.inc"         ; Shorter form
```

Include files are searched in this order:
1. Relative to the current file's directory
2. In directories specified with `-I` option
3. As an absolute or relative path

### Sections

```asm
.SECTION name       ; Switch to named section
.TEXT               ; Switch to TEXT (code) section
.CODE               ; Alias for .TEXT
.DATA               ; Switch to DATA section
.RODATA             ; Switch to read-only data section
.BSS                ; Switch to BSS (uninitialized) section
```

Each section maintains its own program counter. Use `.ORG` within a section to set its origin:

```asm
.SECTION TEXT
.ORG $1000          ; Code starts at $1000

START:
    LDA #0
    JMP DONE

.SECTION DATA
.ORG $2000          ; Data starts at $2000

TABLE:
    .BYTE 1, 2, 3, 4

.SECTION TEXT       ; Resume code section
DONE:
    RTS             ; Continues from where TEXT left off
```

### Width Hints

Tell the assembler what width to use for immediates:

```asm
.M8                 ; 8-bit accumulator
.M16                ; 16-bit accumulator
.M32                ; 32-bit accumulator
.X8                 ; 8-bit index registers
.X16                ; 16-bit index registers
.X32                ; 32-bit index registers
.A8 / .A16 / .A32   ; Aliases for .M8/.M16/.M32
.I8 / .I16 / .I32   ; Aliases for .X8/.X16/.X32
```

## Addressing Modes

### Standard 6502/65816 Modes

```asm
    NOP                 ; Implied
    ASL                 ; Accumulator (or ASL A)
    LDA #$12            ; Immediate
    LDA $20             ; Direct Page
    LDA $20,X           ; Direct Page Indexed X
    LDA $20,Y           ; Direct Page Indexed Y
    LDA $1234           ; Absolute
    LDA $1234,X         ; Absolute Indexed X
    LDA $1234,Y         ; Absolute Indexed Y
    LDA ($20)           ; Direct Page Indirect
    LDA ($20,X)         ; Indexed Indirect
    LDA ($20),Y         ; Indirect Indexed
    LDA [$20]           ; Direct Page Indirect Long
    LDA [$20],Y         ; Indirect Long Indexed
    LDA $123456         ; Absolute Long
    LDA $123456,X       ; Absolute Long Indexed X
    JMP ($1234)         ; Absolute Indirect
    JMP ($1234,X)       ; Absolute Indexed Indirect
    LDA $10,S           ; Stack Relative
    LDA ($10,S),Y       ; Stack Relative Indirect Indexed
    BEQ label           ; Relative
    BRL label           ; Relative Long
    MVP #$01,#$02       ; Block Move
```

### 32-bit Absolute (Extended ALU)

```asm
    LD R0, $12345678        ; 32-bit absolute (Extended ALU)
    LD.B A, $C0001000       ; 8-bit load from 32-bit address
```

## M65832 Extended Instructions

All extended instructions use the `$02` prefix byte internally.

### Multiply/Divide

```asm
    MUL $20             ; Signed multiply A * [DP]
    MULU $20            ; Unsigned multiply
    MUL $1234           ; Signed multiply A * [abs]
    MULU $1234          ; Unsigned multiply
    DIV $20             ; Signed divide A / [DP], remainder in T
    DIVU $20            ; Unsigned divide
    DIV $1234           ; Signed divide A / [abs]
    DIVU $1234          ; Unsigned divide
```

### Atomic Operations

```asm
    CAS $20             ; Compare and swap (DP)
    CAS $1234           ; Compare and swap (abs)
    LLI $20             ; Load linked (DP)
    LLI $1234           ; Load linked (abs)
    SCI $20             ; Store conditional (DP)
    SCI $1234           ; Store conditional (abs)
    FENCE               ; Full memory fence
    FENCER              ; Read fence
    FENCEW              ; Write fence
```

### Base Registers

```asm
    SVBR #$10000000     ; Set VBR (32-bit immediate)
    SVBR $20            ; Set VBR from DP
    SB #$00000000       ; Set B register
    SB $20              ; Set B from DP
    SD #$00010000       ; Set D register
    SD $20              ; Set D from DP
```

### Register Window

```asm
    RSET                ; Enable register window (R=1)
    RCLR                ; Disable register window (R=0)
```

### System

```asm
    TRAP #$00           ; System call trap
    REPE #$A0           ; Clear extended P bits
    SEPE #$A0           ; Set extended P bits
```

### Temp Register

```asm
    TTA                 ; Transfer T to A
    TAT                 ; Transfer A to T
```

### 64-bit Load/Store

```asm
    LDQ $20             ; Load 64-bit: T:A = [DP]
    LDQ $1234           ; Load 64-bit: T:A = [abs]
    STQ $20             ; Store 64-bit: [DP] = T:A
    STQ $1234           ; Store 64-bit: [abs] = T:A
```

### Load Effective Address

```asm
    LEA $20             ; A = D + $20
    LEA $20,X           ; A = D + $20 + X
    LEA $1234           ; A = B + $1234
    LEA $1234,X         ; A = B + $1234 + X
```

### FPU Operations

```asm
    LDF0 $20            ; Load F0 from DP
    LDF0 $1234          ; Load F0 from abs
    STF0 $20            ; Store F0 to DP
    STF0 $1234          ; Store F0 to abs
    ; (Same pattern for LDF1, LDF2, STF1, STF2)
    
    FADD.S              ; F0 = F1 + F2 (single)
    FSUB.S              ; F0 = F1 - F2
    FMUL.S              ; F0 = F1 * F2
    FDIV.S              ; F0 = F1 / F2
    FNEG.S              ; F0 = -F1
    FABS.S              ; F0 = |F1|
    FCMP.S              ; Compare F1 to F2
    F2I.S               ; A = (int)F1
    I2F.S               ; F0 = (float)A
    
    ; (Same pattern with .D for double precision)
    FADD.D
    FSUB.D
    ; ...
```

## Example Program

```asm
; M65832 Hello World
; Outputs to UART at $B0000000

.ORG $1000

UART_DATA   = $0000     ; B + offset
UART_STATUS = $0004

.M16                    ; 16-bit accumulator
.X16                    ; 16-bit index

start:
    ; Enter native mode
    CLC
    XCE

    ; Set up base register for UART
    SB #$B0000000

    ; Print message
    LDX #0
print_loop:
    LDA message,X
    BEQ done

wait_tx:
    LDA UART_STATUS
    AND #$01
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

## Output Formats

### Binary (default)

Raw binary output starting at the `.ORG` address. Suitable for loading into memory or burning to ROM.

### Intel HEX (`-h` option)

Standard Intel HEX format with extended address records for addresses above $FFFF. Compatible with most EPROM programmers and bootloaders.

## Disassembler

The disassembler can be used as a standalone tool or as a library.

### Standalone Usage

```bash
m65832dis [options] input.bin
```

### Disassembler Options

| Option | Description |
|--------|-------------|
| `-o ADDR` | Set origin/start address (default: 0) |
| `-l LENGTH` | Number of bytes to disassemble |
| `-s OFFSET` | Start offset in file (default: 0) |
| `-x` | Show hex bytes alongside disassembly |
| `-n` | Don't show addresses |
| `-m8/-m16/-m32` | Set accumulator width mode |
| `-x8/-x16/-x32` | Set index register width mode |
| `--help` | Show help |

### Disassembler Examples

```bash
# Basic disassembly
m65832dis program.bin

# With hex bytes and specific origin
m65832dis -x -o 0x8000 program.bin

# Disassemble a portion of a file
m65832dis -s 0x100 -l 256 -o 0x1000 rom.bin
```

### Library Usage

The disassembler can be used as a library in your own C programs:

```c
#define M65832DIS_IMPLEMENTATION
#include "m65832dis.c"

// Disassemble a single instruction
M65832DisCtx ctx;
m65832_dis_init(&ctx);

char output[128];
int len = m65832_disasm(buffer, buflen, pc, output, sizeof(output), &ctx);

// Disassemble a buffer with callback
void my_callback(uint32_t pc, const uint8_t *bytes, int bytelen,
                 const char *text, void *userdata) {
    printf("%08X: %s\n", pc, text);
}

m65832_disasm_buffer(buffer, buflen, start_pc, &ctx, my_callback, NULL);
```

## Limitations

- Maximum output size: 1MB
- Maximum symbols: 4096
- Maximum sections: 16
- Maximum include depth: 16
- Maximum include paths: 8
- Maximum line length: 1024 characters
- Maximum label length: 63 characters
- No macro support (planned for future version)
- Output is a flat binary spanning all sections (gaps filled with $FF)

## License

MIT License. See LICENSE.md in the project root.
