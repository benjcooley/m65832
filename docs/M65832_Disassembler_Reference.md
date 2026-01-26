# M65832 Disassembler Reference

A complete reference for the M65832 disassembler.

## Overview

The M65832 disassembler (`m65832dis`) is a portable disassembler that can decode M65832 machine code back into assembly language. It supports both standalone command-line usage and library integration.

### Features

- Full 6502/65816 instruction set support
- M65832 extended instructions ($02 prefix) with mode byte decoding
- Configurable accumulator and index register widths
- Hex byte display option
- File offset and length control
- Library API for integration

## Building

### Standalone Tool

```bash
cd as
make
```

Or directly:

```bash
cc -O2 -DM65832DIS_STANDALONE -o m65832dis m65832dis.c
```

### As a Library

Include the source file with the implementation define:

```c
#define M65832DIS_IMPLEMENTATION
#include "m65832dis.c"
```

## Command Line Usage

```
m65832dis [options] input.bin
```

### Options

| Option | Description |
|--------|-------------|
| `-o ADDR` | Set origin/start address (default: 0) |
| `-l LENGTH` | Number of bytes to disassemble |
| `-s OFFSET` | Start offset in file (default: 0) |
| `-x` | Show hex bytes alongside disassembly |
| `-n` | Don't show addresses |
| `-m8` | Set 8-bit accumulator mode |
| `-m16` | Set 16-bit accumulator mode (default) |
| `-m32` | Set 32-bit accumulator mode |
| `-x8` | Set 8-bit index register mode |
| `-x16` | Set 16-bit index register mode (default) |
| `-x32` | Set 32-bit index register mode |
| `--help` | Display help message |

### Examples

```bash
# Basic disassembly
m65832dis program.bin

# With hex bytes and origin
m65832dis -x -o 0x8000 program.bin

# Disassemble specific range
m65832dis -s 0x100 -l 256 -o 0x1000 rom.bin

# No addresses, just instructions
m65832dis -n program.bin

# 8-bit mode (6502 compatible)
m65832dis -m8 -x8 program.bin

# 32-bit native mode
m65832dis -m32 -x32 program.bin
```

### Output Format

Default output shows address and instruction:

```
00008000  NOP
00008001  LDA #$1234
00008004  JMP $8010
```

With `-x` flag, hex bytes are included:

```
00008000  EA                NOP
00008001  A9 34 12          LDA #$1234
00008004  4C 10 80          JMP $8010
```

Without addresses (`-n`):

```
NOP
LDA #$1234
JMP $8010
```

## Library API

### Header

```c
#include "m65832dis.c"  // After #define M65832DIS_IMPLEMENTATION
```

Or just include the header portion:

```c
#ifndef M65832DIS_H
#define M65832DIS_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int m_flag;     /* 0=8-bit A, 1=16-bit A, 2=32-bit A */
    int x_flag;     /* 0=8-bit X/Y, 1=16-bit X/Y, 2=32-bit X/Y */
    int emu_mode;   /* 1=emulation mode (6502 compatible) */
} M65832DisCtx;

void m65832_dis_init(M65832DisCtx *ctx);

int m65832_disasm(const uint8_t *buf, size_t buflen, uint32_t pc,
                  char *out, size_t out_size, M65832DisCtx *ctx);

typedef void (*m65832_dis_callback)(uint32_t pc, const uint8_t *bytes, 
                                    int bytelen, const char *text, 
                                    void *userdata);

int m65832_disasm_buffer(const uint8_t *buf, size_t buflen, uint32_t start_pc,
                         M65832DisCtx *ctx, m65832_dis_callback callback, 
                         void *userdata);

#endif
```

### Functions

#### `m65832_dis_init`

Initialize a disassembler context with default settings.

```c
void m65832_dis_init(M65832DisCtx *ctx);
```

**Parameters:**
- `ctx` - Pointer to context structure to initialize

**Default Settings:**
- 16-bit accumulator mode (`m_flag = 1`)
- 16-bit index register mode (`x_flag = 1`)
- Native mode (`emu_mode = 0`)

#### `m65832_disasm`

Disassemble a single instruction.

```c
int m65832_disasm(const uint8_t *buf, size_t buflen, uint32_t pc,
                  char *out, size_t out_size, M65832DisCtx *ctx);
```

**Parameters:**
- `buf` - Pointer to instruction bytes
- `buflen` - Number of bytes available in buffer
- `pc` - Program counter (used for relative branch targets)
- `out` - Output buffer for disassembly text
- `out_size` - Size of output buffer
- `ctx` - Disassembler context (may be NULL for defaults)

**Returns:**
- Number of bytes consumed by the instruction
- 0 on error (buffer too small, invalid instruction)

**Notes:**
- The context is updated if REP/SEP instructions are encountered
- Output is null-terminated
- Minimum recommended output buffer: 64 bytes

#### `m65832_disasm_buffer`

Disassemble a buffer of code, calling a callback for each instruction.

```c
int m65832_disasm_buffer(const uint8_t *buf, size_t buflen, uint32_t start_pc,
                         M65832DisCtx *ctx, m65832_dis_callback callback, 
                         void *userdata);
```

**Parameters:**
- `buf` - Pointer to code buffer
- `buflen` - Number of bytes in buffer
- `start_pc` - Starting program counter
- `ctx` - Disassembler context (may be NULL for defaults)
- `callback` - Function called for each instruction
- `userdata` - User data passed to callback

**Returns:**
- Total number of bytes disassembled

**Callback Signature:**
```c
void callback(uint32_t pc,           // Address of instruction
              const uint8_t *bytes,  // Raw instruction bytes
              int bytelen,           // Number of bytes in instruction
              const char *text,      // Disassembled text
              void *userdata);       // User data
```

### Context Structure

```c
typedef struct {
    int m_flag;     /* Accumulator width: 0=8-bit, 1=16-bit, 2=32-bit */
    int x_flag;     /* Index width: 0=8-bit, 1=16-bit, 2=32-bit */
    int emu_mode;   /* 1=emulation mode */
} M65832DisCtx;
```

The context tracks processor state that affects instruction decoding:
- **m_flag**: Determines immediate operand size for A register operations
- **x_flag**: Determines immediate operand size for X/Y register operations
- **emu_mode**: Reserved for future emulation mode support

### Example: Single Instruction

```c
#define M65832DIS_IMPLEMENTATION
#include "m65832dis.c"

int main() {
    M65832DisCtx ctx;
    m65832_dis_init(&ctx);
    
    uint8_t code[] = { 0xA9, 0x34, 0x12 };  // LDA #$1234
    char output[64];
    
    int len = m65832_disasm(code, sizeof(code), 0x8000, 
                            output, sizeof(output), &ctx);
    
    printf("Length: %d, Instruction: %s\n", len, output);
    // Output: Length: 3, Instruction: LDA #$1234
    
    return 0;
}
```

### Example: Buffer with Callback

```c
#define M65832DIS_IMPLEMENTATION
#include "m65832dis.c"

void print_instruction(uint32_t pc, const uint8_t *bytes, int bytelen,
                       const char *text, void *userdata) {
    printf("%08X  ", pc);
    
    // Print hex bytes
    for (int i = 0; i < bytelen && i < 6; i++) {
        printf("%02X ", bytes[i]);
    }
    for (int i = bytelen; i < 6; i++) {
        printf("   ");
    }
    
    printf("%s\n", text);
}

int main() {
    M65832DisCtx ctx;
    m65832_dis_init(&ctx);
    
    uint8_t code[] = {
        0xEA,                   // NOP
        0xA9, 0x34, 0x12,       // LDA #$1234
        0x4C, 0x00, 0x80        // JMP $8000
    };
    
    m65832_disasm_buffer(code, sizeof(code), 0x8000, 
                         &ctx, print_instruction, NULL);
    
    return 0;
}
```

### Example: Tracking Mode Changes

```c
#define M65832DIS_IMPLEMENTATION
#include "m65832dis.c"

int main() {
    M65832DisCtx ctx;
    m65832_dis_init(&ctx);  // Default: 16-bit mode
    
    uint8_t code[] = {
        0xE2, 0x20,             // SEP #$20 - Switch to 8-bit A
        0xA9, 0x12,             // LDA #$12 (now 8-bit)
        0xC2, 0x20,             // REP #$20 - Switch to 16-bit A  
        0xA9, 0x34, 0x12        // LDA #$1234 (now 16-bit)
    };
    
    size_t offset = 0;
    uint32_t pc = 0x8000;
    char output[64];
    
    while (offset < sizeof(code)) {
        int len = m65832_disasm(code + offset, sizeof(code) - offset,
                                pc, output, sizeof(output), &ctx);
        if (len == 0) break;
        
        printf("%08X  %s (m_flag=%d)\n", pc, output, ctx.m_flag);
        offset += len;
        pc += len;
    }
    
    return 0;
}
```

Output:
```
00008000  SEP #$20 (m_flag=1)
00008002  LDA #$12 (m_flag=0)
00008004  REP #$20 (m_flag=0)
00008006  LDA #$1234 (m_flag=1)
```

## Instruction Decoding

### Standard Opcodes

The disassembler uses a 256-entry lookup table for standard 6502/65816 opcodes, with each entry specifying:
- Mnemonic
- Addressing mode
- Operand size (may depend on M/X flags)

### Extended Opcodes ($02 Prefix)

When opcode $02 is encountered, the next byte is looked up in a separate extended opcode table for M65832 instructions:
- MUL, DIV operations ($00-$07)
- Atomic instructions ($10-$15): CAS, LLI, SCI
- Memory fences ($50-$52)
- FPU operations ($B0-$D8)
- System instructions ($40, $60-$61)
- **Extended ALU ($80-$97)**: LD, ST, ADC, SBC, AND, ORA, EOR, CMP, BIT, TSB, TRB, INC, DEC, ASL, LSR, ROL, ROR, STZ
- Barrel shifter ($98): SHL, SHR, SAR, ROL, ROR
- Extend instructions ($99): SEXT8, SEXT16, ZEXT8, ZEXT16, CLZ, CTZ, POPCNT
- Temp register ($9A-$9B): TTA, TAT
- 64-bit load/store ($9C-$9F): LDQ, STQ

### Extended ALU Decoding ($80-$97)

Extended ALU instructions have a mode byte following the opcode:

**Format:** `$02 [op] [mode] [dest_dp?] [src...]`

**Mode byte:** `[size:2][target:1][addr_mode:5]`

| Field | Bits | Values |
|-------|------|--------|
| size | 7-6 | 00=.B, 01=.W, 10=(none) |
| target | 5 | 0=A, 1=Rn |
| addr_mode | 4-0 | 32 modes |

**Disassembly output:**

```
00000000  LD.B A,R1           ; $02 $80 $00 $04 - A-target, dp mode
00000004  LD.B R0,R1          ; $02 $80 $20 $00 $04 - Rn-target
00000009  ADC.W R0,#$1234     ; $02 $82 $78 $00 $34 $12 - imm16
```

### Register Aliases (R0-R63)

For Direct Page addresses that are 4-byte aligned (multiples of 4), the disassembler outputs register alias notation:

```
00000000  SHL R4,R1,#4        ; $02 $98 $04 $10 $04 - dest=$10=R4, src=$04=R1
00000005  CLZ R8,R5           ; $02 $99 $04 $20 $14 - dest=$20=R8, src=$14=R5
0000000A  SHL $01,$02,#4      ; Non-aligned addresses shown as hex
```

| Register | DP Address | Register | DP Address |
|----------|------------|----------|------------|
| R0 | $00 | R32 | $80 |
| R1 | $04 | R33 | $84 |
| R2 | $08 | ... | ... |
| ... | ... | R63 | $FC |

### Extended ALU Size Suffixes

Extended ALU instructions ($02 $80-$97) encode size in the mode byte:

| Size bits | Suffix | Example |
|-----------|--------|---------|
| 00 | `.B` | `LD.B R0, R1` |
| 01 | `.W` | `LD.W R0, #$1234` |
| 10 | (none) | `LD R0, #$12345678` |

### Undefined Opcodes

Undefined opcodes are output as `.BYTE $XX` directives:

```
00008000  .BYTE $02,$FF
```

## Output Syntax

### Addressing Mode Format

**65816 Mode Output:**

| Mode | Format | Example |
|------|--------|---------|
| Implied | (none) | `NOP` |
| Accumulator | `A` | `ASL A` |
| Immediate | `#$xx` | `LDA #$12` |
| Direct Page | `$xx` | `LDA $10` |
| DP Indexed X | `$xx,X` | `LDA $10,X` |
| DP Indexed Y | `$xx,Y` | `LDX $10,Y` |
| Absolute | `$xxxx` | `LDA $1234` |
| Absolute X | `$xxxx,X` | `LDA $1234,X` |
| Absolute Y | `$xxxx,Y` | `LDA $1234,Y` |
| Absolute Long | `$xxxxxx` | `LDA $123456` |
| Absolute Long X | `$xxxxxx,X` | `LDA $123456,X` |
| Indirect | `($xx)` | `LDA ($10)` |
| Indexed Indirect | `($xx,X)` | `LDA ($10,X)` |
| Indirect Indexed | `($xx),Y` | `LDA ($10),Y` |
| Indirect Long | `[$xx]` | `LDA [$10]` |
| Indirect Long Y | `[$xx],Y` | `LDA [$10],Y` |
| Absolute Indirect | `($xxxx)` | `JMP ($1234)` |
| Abs Indexed Indirect | `($xxxx,X)` | `JMP ($1234,X)` |
| Abs Long Indirect | `[$xxxx]` | `JML [$1234]` |
| Stack Relative | `$xx,S` | `LDA $10,S` |
| SR Indirect Indexed | `($xx,S),Y` | `LDA ($10,S),Y` |
| Relative | `$xxxx` | `BEQ $8010` |
| Relative Long | `$xxxx` | `BRL $8100` |
| Block Move | `$xx,$xx` | `MVP $01,$02` |

**32-bit Mode Output (with `-m32` flag):**

| Mode | Format | Example |
|------|--------|---------|
| Register (R=1) | `Rn` | `LDA R4` |
| Direct Page | `$xx` or `Rn` | `LDA R0` |
| Absolute | `B+$xxxx` | `LDA B+$1234` |
| Absolute X | `B+$xxxx,X` | `LDA B+$1234,X` |
| 32-bit Absolute | `$xxxxxxxx` | `LD R0,$A0001234` (Extended ALU) |

### Branch Targets

Branch instructions show the computed target address:

```
00008000  BEQ $8010       ; Branch to $8010 if equal
00008002  BRL $8100       ; Long branch to $8100
```

### 32-bit Mode Instructions

Instructions with data/address prefixes show the size suffix and full addresses:

```
0000800C  LDA #$12345678       ; 32-bit data (always in 32-bit mode)
00008011  LDA B+$1234          ; B-relative addressing
00008014  LD R0,$C0001000      ; Extended ALU 32-bit absolute
0000801C  LD.B R0,#$12         ; Extended ALU 8-bit
0000801E  LD.W R0,#$1234       ; Extended ALU 16-bit
00008024  WAI                  ; $CB (standard 65816)
00008025  STP                  ; $DB (standard 65816)
```

## Limitations

- No label generation (outputs raw addresses)
- No automatic mode tracking across files
- Single-pass disassembly (no multi-pass analysis)
- Cannot distinguish code from data

## Integration Tips

### Disassembly for Debugging

```c
// Print current instruction at PC
void debug_print_instruction(CPU *cpu) {
    M65832DisCtx ctx = {
        .m_flag = (cpu->p & 0x20) ? 0 : 1,  // M flag
        .x_flag = (cpu->p & 0x10) ? 0 : 1,  // X flag
    };
    
    char output[64];
    m65832_disasm(cpu->memory + cpu->pc, 16, cpu->pc, 
                  output, sizeof(output), &ctx);
    printf("PC=%08X: %s\n", cpu->pc, output);
}
```

### Trace Logging

```c
void trace_callback(uint32_t pc, const uint8_t *bytes, int bytelen,
                    const char *text, void *userdata) {
    FILE *log = (FILE *)userdata;
    fprintf(log, "%08X: %s\n", pc, text);
}

// Disassemble ROM section to log file
FILE *log = fopen("trace.log", "w");
m65832_disasm_buffer(rom, rom_size, 0x8000, NULL, trace_callback, log);
fclose(log);
```

### IDE Integration

```c
// Get disassembly for a memory range
char* get_disassembly(uint8_t *memory, uint32_t start, uint32_t end) {
    size_t bufsize = (end - start) * 32;  // Estimate
    char *result = malloc(bufsize);
    char *p = result;
    
    M65832DisCtx ctx;
    m65832_dis_init(&ctx);
    
    uint32_t pc = start;
    while (pc < end) {
        char line[64];
        int len = m65832_disasm(memory + pc, end - pc, pc,
                                line, sizeof(line), &ctx);
        if (len == 0) break;
        
        p += sprintf(p, "%08X  %s\n", pc, line);
        pc += len;
    }
    
    return result;
}
```

## See Also

- [M65832 Assembler Reference](M65832_Assembler_Reference.md)
- [M65832 Instruction Set](M65832_Instruction_Set.md)
- [M65832 Architecture Reference](M65832_Architecture_Reference.md)
- [M65832 Quick Reference](M65832_Quick_Reference.md)
