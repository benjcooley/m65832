/*
 * M65832 Disassembler
 * 
 * A disassembler for the M65832 processor.
 * Can be used as a library or standalone tool.
 *
 * Library usage:
 *   #define M65832DIS_IMPLEMENTATION
 *   #include "m65832dis.c"
 *   
 *   int len = m65832_disasm(buf, buflen, pc, output, sizeof(output), &ctx);
 *
 * Standalone build:
 *   cc -O2 -DM65832DIS_STANDALONE -o m65832dis m65832dis.c
 *
 * Copyright (c) 2026. MIT License.
 */

#ifndef M65832DIS_H
#define M65832DIS_H

#include <stdint.h>
#include <stddef.h>

/* Disassembler context - tracks processor state */
typedef struct {
    int m_flag;     /* 0=8-bit A, 1=16-bit A, 2=32-bit A */
    int x_flag;     /* 0=8-bit X/Y, 1=16-bit X/Y, 2=32-bit X/Y */
    int emu_mode;   /* 1=emulation mode (6502 compatible) */
} M65832DisCtx;

/* Initialize context with default settings */
void m65832_dis_init(M65832DisCtx *ctx);

/*
 * Disassemble a single instruction.
 * 
 * Parameters:
 *   buf      - pointer to instruction bytes
 *   buflen   - number of bytes available in buffer
 *   pc       - program counter (for relative branch targets)
 *   out      - output buffer for disassembly text
 *   out_size - size of output buffer
 *   ctx      - disassembler context (may be NULL for defaults)
 *
 * Returns:
 *   Number of bytes consumed by the instruction, or 0 on error.
 *   The output buffer will contain the disassembled instruction.
 */
int m65832_disasm(const uint8_t *buf, size_t buflen, uint32_t pc,
                  char *out, size_t out_size, M65832DisCtx *ctx);

/*
 * Disassemble a buffer of code.
 * Calls the callback for each instruction.
 *
 * Parameters:
 *   buf      - pointer to code buffer
 *   buflen   - number of bytes in buffer
 *   start_pc - starting program counter
 *   ctx      - disassembler context (may be NULL)
 *   callback - function called for each instruction
 *   userdata - passed to callback
 *
 * Callback parameters:
 *   pc       - address of instruction
 *   bytes    - raw instruction bytes
 *   bytelen  - number of bytes in instruction
 *   text     - disassembled text
 *   userdata - user data pointer
 *
 * Returns:
 *   Number of bytes disassembled, or negative on error.
 */
typedef void (*m65832_dis_callback)(uint32_t pc, const uint8_t *bytes, int bytelen,
                                    const char *text, void *userdata);

int m65832_disasm_buffer(const uint8_t *buf, size_t buflen, uint32_t start_pc,
                         M65832DisCtx *ctx, m65832_dis_callback callback, void *userdata);

#endif /* M65832DIS_H */

/* ============================================================================ */
/* Implementation                                                               */
/* ============================================================================ */

#if defined(M65832DIS_IMPLEMENTATION) || defined(M65832DIS_STANDALONE)

#include <stdio.h>
#include <string.h>
#include <ctype.h>

/* Addressing modes */
typedef enum {
    AM_IMP,         /* Implied: NOP */
    AM_ACC,         /* Accumulator: ASL A */
    AM_IMM,         /* Immediate: LDA #$xx */
    AM_DP,          /* Direct Page: LDA $xx */
    AM_DPX,         /* DP Indexed X: LDA $xx,X */
    AM_DPY,         /* DP Indexed Y: LDA $xx,Y */
    AM_ABS,         /* Absolute: LDA $xxxx */
    AM_ABSX,        /* Abs Indexed X: LDA $xxxx,X */
    AM_ABSY,        /* Abs Indexed Y: LDA $xxxx,Y */
    AM_IND,         /* DP Indirect: LDA ($xx) */
    AM_INDX,        /* Indexed Indirect: LDA ($xx,X) */
    AM_INDY,        /* Indirect Indexed: LDA ($xx),Y */
    AM_INDL,        /* Indirect Long: LDA [$xx] */
    AM_INDLY,       /* Indirect Long Y: LDA [$xx],Y */
    AM_ABSL,        /* Absolute Long: LDA $xxxxxx */
    AM_ABSLX,       /* Abs Long X: LDA $xxxxxx,X */
    AM_REL,         /* Relative: BEQ $xx */
    AM_RELL,        /* Relative Long: BRL $xxxx */
    AM_SR,          /* Stack Relative: LDA $xx,S */
    AM_SRIY,        /* SR Indirect Y: LDA ($xx,S),Y */
    AM_MVP,         /* Block Move: MVP $xx,$xx */
    AM_ABSIND,      /* Abs Indirect: JMP ($xxxx) */
    AM_ABSINDX,     /* Abs Indexed Indirect: JMP ($xxxx,X) */
    AM_ABSLIND,     /* Abs Long Indirect: JML [$xxxx] */
    AM_IMM_M,       /* Immediate (M flag dependent) */
    AM_IMM_X,       /* Immediate (X flag dependent) */
    AM_FPU_REG2,    /* Two FP registers: FADD.S F0, F1 */
    AM_FPU_REG1,    /* One FP register: I2F.S F0 */
    AM_FPU_DP,      /* FP register + DP: LDF F0, $xx */
    AM_FPU_ABS,     /* FP register + Abs: LDF F0, $xxxx */
    AM_FPU_IND,     /* FP register + (Rm): LDF F0, (R1) */
    AM_FPU_ABS32,   /* FP register + Abs32: LDF F0, $xxxxxxxx */
    AM_UNKNOWN
} AddrMode;

/* Instruction entry */
typedef struct {
    const char *mnemonic;
    AddrMode mode;
} OpcodeEntry;

/* Standard 6502/65816 opcode table */
static const OpcodeEntry opcode_table[256] = {
    /* 0x00-0x0F */
    { "BRK", AM_IMP   }, { "ORA", AM_INDX  }, { "COP", AM_IMM   }, { "ORA", AM_SR    },
    { "TSB", AM_DP    }, { "ORA", AM_DP    }, { "ASL", AM_DP    }, { "ORA", AM_INDL  },
    { "PHP", AM_IMP   }, { "ORA", AM_IMM_M }, { "ASL", AM_ACC   }, { "PHD", AM_IMP   },
    { "TSB", AM_ABS   }, { "ORA", AM_ABS   }, { "ASL", AM_ABS   }, { "ORA", AM_ABSL  },
    /* 0x10-0x1F */
    { "BPL", AM_REL   }, { "ORA", AM_INDY  }, { "ORA", AM_IND   }, { "ORA", AM_SRIY  },
    { "TRB", AM_DP    }, { "ORA", AM_DPX   }, { "ASL", AM_DPX   }, { "ORA", AM_INDLY },
    { "CLC", AM_IMP   }, { "ORA", AM_ABSY  }, { "INC", AM_ACC   }, { "TCS", AM_IMP   },
    { "TRB", AM_ABS   }, { "ORA", AM_ABSX  }, { "ASL", AM_ABSX  }, { "ORA", AM_ABSLX },
    /* 0x20-0x2F */
    { "JSR", AM_ABS   }, { "AND", AM_INDX  }, { "JSL", AM_ABSL  }, { "AND", AM_SR    },
    { "BIT", AM_DP    }, { "AND", AM_DP    }, { "ROL", AM_DP    }, { "AND", AM_INDL  },
    { "PLP", AM_IMP   }, { "AND", AM_IMM_M }, { "ROL", AM_ACC   }, { "PLD", AM_IMP   },
    { "BIT", AM_ABS   }, { "AND", AM_ABS   }, { "ROL", AM_ABS   }, { "AND", AM_ABSL  },
    /* 0x30-0x3F */
    { "BMI", AM_REL   }, { "AND", AM_INDY  }, { "AND", AM_IND   }, { "AND", AM_SRIY  },
    { "BIT", AM_DPX   }, { "AND", AM_DPX   }, { "ROL", AM_DPX   }, { "AND", AM_INDLY },
    { "SEC", AM_IMP   }, { "AND", AM_ABSY  }, { "DEC", AM_ACC   }, { "TSC", AM_IMP   },
    { "BIT", AM_ABSX  }, { "AND", AM_ABSX  }, { "ROL", AM_ABSX  }, { "AND", AM_ABSLX },
    /* 0x40-0x4F */
    { "RTI", AM_IMP   }, { "EOR", AM_INDX  }, { "WDM", AM_IMM   }, { "EOR", AM_SR    },
    { "MVP", AM_MVP   }, { "EOR", AM_DP    }, { "LSR", AM_DP    }, { "EOR", AM_INDL  },
    { "PHA", AM_IMP   }, { "EOR", AM_IMM_M }, { "LSR", AM_ACC   }, { "PHK", AM_IMP   },
    { "JMP", AM_ABS   }, { "EOR", AM_ABS   }, { "LSR", AM_ABS   }, { "EOR", AM_ABSL  },
    /* 0x50-0x5F */
    { "BVC", AM_REL   }, { "EOR", AM_INDY  }, { "EOR", AM_IND   }, { "EOR", AM_SRIY  },
    { "MVN", AM_MVP   }, { "EOR", AM_DPX   }, { "LSR", AM_DPX   }, { "EOR", AM_INDLY },
    { "CLI", AM_IMP   }, { "EOR", AM_ABSY  }, { "PHY", AM_IMP   }, { "TCD", AM_IMP   },
    { "JML", AM_ABSL  }, { "EOR", AM_ABSX  }, { "LSR", AM_ABSX  }, { "EOR", AM_ABSLX },
    /* 0x60-0x6F */
    { "RTS", AM_IMP   }, { "ADC", AM_INDX  }, { "PER", AM_RELL  }, { "ADC", AM_SR    },
    { "STZ", AM_DP    }, { "ADC", AM_DP    }, { "ROR", AM_DP    }, { "ADC", AM_INDL  },
    { "PLA", AM_IMP   }, { "ADC", AM_IMM_M }, { "ROR", AM_ACC   }, { "RTL", AM_IMP   },
    { "JMP", AM_ABSIND}, { "ADC", AM_ABS   }, { "ROR", AM_ABS   }, { "ADC", AM_ABSL  },
    /* 0x70-0x7F */
    { "BVS", AM_REL   }, { "ADC", AM_INDY  }, { "ADC", AM_IND   }, { "ADC", AM_SRIY  },
    { "STZ", AM_DPX   }, { "ADC", AM_DPX   }, { "ROR", AM_DPX   }, { "ADC", AM_INDLY },
    { "SEI", AM_IMP   }, { "ADC", AM_ABSY  }, { "PLY", AM_IMP   }, { "TDC", AM_IMP   },
    { "JMP", AM_ABSINDX},{ "ADC", AM_ABSX  }, { "ROR", AM_ABSX  }, { "ADC", AM_ABSLX },
    /* 0x80-0x8F */
    { "BRA", AM_REL   }, { "STA", AM_INDX  }, { "BRL", AM_RELL  }, { "STA", AM_SR    },
    { "STY", AM_DP    }, { "STA", AM_DP    }, { "STX", AM_DP    }, { "STA", AM_INDL  },
    { "DEY", AM_IMP   }, { "BIT", AM_IMM_M }, { "TXA", AM_IMP   }, { "PHB", AM_IMP   },
    { "STY", AM_ABS   }, { "STA", AM_ABS   }, { "STX", AM_ABS   }, { "STA", AM_ABSL  },
    /* 0x90-0x9F */
    { "BCC", AM_REL   }, { "STA", AM_INDY  }, { "STA", AM_IND   }, { "STA", AM_SRIY  },
    { "STY", AM_DPX   }, { "STA", AM_DPX   }, { "STX", AM_DPY   }, { "STA", AM_INDLY },
    { "TYA", AM_IMP   }, { "STA", AM_ABSY  }, { "TXS", AM_IMP   }, { "TXY", AM_IMP   },
    { "STZ", AM_ABS   }, { "STA", AM_ABSX  }, { "STZ", AM_ABSX  }, { "STA", AM_ABSLX },
    /* 0xA0-0xAF */
    { "LDY", AM_IMM_X }, { "LDA", AM_INDX  }, { "LDX", AM_IMM_X }, { "LDA", AM_SR    },
    { "LDY", AM_DP    }, { "LDA", AM_DP    }, { "LDX", AM_DP    }, { "LDA", AM_INDL  },
    { "TAY", AM_IMP   }, { "LDA", AM_IMM_M }, { "TAX", AM_IMP   }, { "PLB", AM_IMP   },
    { "LDY", AM_ABS   }, { "LDA", AM_ABS   }, { "LDX", AM_ABS   }, { "LDA", AM_ABSL  },
    /* 0xB0-0xBF */
    { "BCS", AM_REL   }, { "LDA", AM_INDY  }, { "LDA", AM_IND   }, { "LDA", AM_SRIY  },
    { "LDY", AM_DPX   }, { "LDA", AM_DPX   }, { "LDX", AM_DPY   }, { "LDA", AM_INDLY },
    { "CLV", AM_IMP   }, { "LDA", AM_ABSY  }, { "TSX", AM_IMP   }, { "TYX", AM_IMP   },
    { "LDY", AM_ABSX  }, { "LDA", AM_ABSX  }, { "LDX", AM_ABSY  }, { "LDA", AM_ABSLX },
    /* 0xC0-0xCF */
    { "CPY", AM_IMM_X }, { "CMP", AM_INDX  }, { "REP", AM_IMM   }, { "CMP", AM_SR    },
    { "CPY", AM_DP    }, { "CMP", AM_DP    }, { "DEC", AM_DP    }, { "CMP", AM_INDL  },
    { "INY", AM_IMP   }, { "CMP", AM_IMM_M }, { "DEX", AM_IMP   }, { "WAI", AM_IMP   },
    { "CPY", AM_ABS   }, { "CMP", AM_ABS   }, { "DEC", AM_ABS   }, { "CMP", AM_ABSL  },
    /* 0xD0-0xDF */
    { "BNE", AM_REL   }, { "CMP", AM_INDY  }, { "CMP", AM_IND   }, { "CMP", AM_SRIY  },
    { "PEI", AM_IND   }, { "CMP", AM_DPX   }, { "DEC", AM_DPX   }, { "CMP", AM_INDLY },
    { "CLD", AM_IMP   }, { "CMP", AM_ABSY  }, { "PHX", AM_IMP   }, { "STP", AM_IMP   },
    { "JML", AM_ABSLIND},{ "CMP", AM_ABSX  }, { "DEC", AM_ABSX  }, { "CMP", AM_ABSLX },
    /* 0xE0-0xEF */
    { "CPX", AM_IMM_X }, { "SBC", AM_INDX  }, { "SEP", AM_IMM   }, { "SBC", AM_SR    },
    { "CPX", AM_DP    }, { "SBC", AM_DP    }, { "INC", AM_DP    }, { "SBC", AM_INDL  },
    { "INX", AM_IMP   }, { "SBC", AM_IMM_M }, { "NOP", AM_IMP   }, { "XBA", AM_IMP   },
    { "CPX", AM_ABS   }, { "SBC", AM_ABS   }, { "INC", AM_ABS   }, { "SBC", AM_ABSL  },
    /* 0xF0-0xFF */
    { "BEQ", AM_REL   }, { "SBC", AM_INDY  }, { "SBC", AM_IND   }, { "SBC", AM_SRIY  },
    { "PEA", AM_ABS   }, { "SBC", AM_DPX   }, { "INC", AM_DPX   }, { "SBC", AM_INDLY },
    { "SED", AM_IMP   }, { "SBC", AM_ABSY  }, { "PLX", AM_IMP   }, { "XCE", AM_IMP   },
    { "JSR", AM_ABSINDX},{ "SBC", AM_ABSX  }, { "INC", AM_ABSX  }, { "SBC", AM_ABSLX },
};

/* M65832 Extended opcode table ($02 prefix) */
typedef struct {
    const char *mnemonic;
    AddrMode mode;
} ExtOpcodeEntry;

static const ExtOpcodeEntry ext_opcode_table[256] = {
    /* 0x00-0x0F: Multiply/Divide */
    { "MUL",    AM_DP   }, { "MULU",   AM_DP   }, { "MUL",    AM_ABS  }, { "MULU",   AM_ABS  },
    { "DIV",    AM_DP   }, { "DIVU",   AM_DP   }, { "DIV",    AM_ABS  }, { "DIVU",   AM_ABS  },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x10-0x1F: Atomics */
    { "CAS",    AM_DP   }, { "CAS",    AM_ABS  }, { "LLI",    AM_DP   }, { "LLI",    AM_ABS  },
    { "SCI",    AM_DP   }, { "SCI",    AM_ABS  }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x20-0x2F: Base registers */
    { "SVBR",   AM_IMM  }, { "SVBR",   AM_DP   }, { "SB",     AM_IMM  }, { "SB",     AM_DP   },
    { "SD",     AM_IMM  }, { "SD",     AM_DP   }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x30-0x3F: Register Window */
    { "RSET",   AM_IMP  }, { "RCLR",   AM_IMP  }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x40-0x4F: System */
    { "TRAP",   AM_IMM  }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x50-0x5F: Fences */
    { "FENCE",  AM_IMP  }, { "FENCER", AM_IMP  }, { "FENCEW", AM_IMP  }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x60-0x6F: Extended flags */
    { "REPE",   AM_IMM  }, { "SEPE",   AM_IMM  }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x70-0x7F: 32-bit stack ops */
    { "PHD32",  AM_IMP  }, { "PLD32",  AM_IMP  }, { "PHB32",  AM_IMP  }, { "PLB32",  AM_IMP  },
    { "PHVBR",  AM_IMP  }, { "PLVBR",  AM_IMP  }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x80-0x8F: Extended ALU (handled separately) */
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0x90-0x9F: B register transfers, Temp register, 64-bit ops */
    { NULL,     AM_UNKNOWN }, { "TAB",    AM_IMP  }, { "TBA",    AM_IMP  }, { "TXB",    AM_IMP  },
    { "TBX",    AM_IMP  }, { "TYB",    AM_IMP  }, { "TBY",    AM_IMP  }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { "TTA",    AM_IMP  }, { "TAT",    AM_IMP  },
    { "LDQ",    AM_DP   }, { "LDQ",    AM_ABS  }, { "STQ",    AM_DP   }, { "STQ",    AM_ABS  },
    /* 0xA0-0xAF: LEA, TSPB */
    { "LEA",    AM_DP   }, { "LEA",    AM_DPX  }, { "LEA",    AM_ABS  }, { "LEA",    AM_ABSX },
    { "TSPB",   AM_IMP  }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0xB0-0xBF: FPU Load/Store (with register byte) */
    { "LDF",    AM_FPU_DP   }, { "LDF",    AM_FPU_ABS }, { "STF",    AM_FPU_DP   }, { "STF",    AM_FPU_ABS },
    { "LDF",    AM_FPU_IND  }, { "STF",    AM_FPU_IND }, { "LDF",    AM_FPU_ABS32 }, { "STF",    AM_FPU_ABS32 },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { "LDF.S", AM_FPU_IND }, { "STF.S", AM_FPU_IND },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0xC0-0xCF: FPU single-precision (with register byte) */
    { "FADD.S", AM_FPU_REG2 }, { "FSUB.S", AM_FPU_REG2 }, { "FMUL.S", AM_FPU_REG2 }, { "FDIV.S", AM_FPU_REG2 },
    { "FNEG.S", AM_FPU_REG2 }, { "FABS.S", AM_FPU_REG2 }, { "FCMP.S", AM_FPU_REG2 }, { "F2I.S",  AM_FPU_REG1 },
    { "I2F.S",  AM_FPU_REG1 }, { "FMOV.S", AM_FPU_REG2 }, { "FSQRT.S",AM_FPU_REG2 }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0xD0-0xDF: FPU double-precision (with register byte) */
    { "FADD.D", AM_FPU_REG2 }, { "FSUB.D", AM_FPU_REG2 }, { "FMUL.D", AM_FPU_REG2 }, { "FDIV.D", AM_FPU_REG2 },
    { "FNEG.D", AM_FPU_REG2 }, { "FABS.D", AM_FPU_REG2 }, { "FCMP.D", AM_FPU_REG2 }, { "F2I.D",  AM_FPU_REG1 },
    { "I2F.D",  AM_FPU_REG1 }, { "FMOV.D", AM_FPU_REG2 }, { "FSQRT.D",AM_FPU_REG2 }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0xE0-0xEF: FPU register transfers */
    { "FTOA",   AM_FPU_REG1 }, { "FTOT",   AM_FPU_REG1 }, { "ATOF",   AM_FPU_REG1 }, { "TTOF",   AM_FPU_REG1 },
    { "FCVT.DS",AM_FPU_REG2 }, { "FCVT.SD",AM_FPU_REG2 }, { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    /* 0xF0-0xFF: Reserved */
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
    { NULL,     AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN }, { NULL,  AM_UNKNOWN },
};

static const char *get_ext_alu_name(uint8_t opcode) {
    switch (opcode) {
        case 0x80: return "LD";
        case 0x81: return "ST";
        case 0x82: return "ADC";
        case 0x83: return "SBC";
        case 0x84: return "AND";
        case 0x85: return "ORA";
        case 0x86: return "EOR";
        case 0x87: return "CMP";
        case 0x88: return "BIT";
        case 0x89: return "TSB";
        case 0x8A: return "TRB";
        case 0x8B: return "INC";
        case 0x8C: return "DEC";
        case 0x8D: return "ASL";
        case 0x8E: return "LSR";
        case 0x8F: return "ROL";
        case 0x90: return "ROR";
        case 0x97: return "STZ";
        default: return NULL;
    }
}

static void format_dp_reg(char *out, size_t out_size, uint8_t dp) {
    if ((dp & 3) == 0) snprintf(out, out_size, "R%d", dp / 4);
    else snprintf(out, out_size, "$%02X", dp);
}

/* Get instruction size for addressing mode */
static int get_operand_size(AddrMode mode, int m_flag, int x_flag) {
    switch (mode) {
        case AM_IMP:
        case AM_ACC:
            return 0;
        case AM_IMM:
        case AM_DP:
        case AM_DPX:
        case AM_DPY:
        case AM_IND:
        case AM_INDX:
        case AM_INDY:
        case AM_INDL:
        case AM_INDLY:
        case AM_REL:
            return (m_flag == 2) ? 2 : 1;
        case AM_SR:
        case AM_SRIY:
            return 1;
        case AM_IMM_M:
            return (m_flag == 0) ? 1 : (m_flag == 1) ? 2 : 4;
        case AM_IMM_X:
            return (x_flag == 0) ? 1 : (x_flag == 1) ? 2 : 4;
        case AM_ABS:
        case AM_ABSX:
        case AM_ABSY:
        case AM_ABSIND:
        case AM_ABSINDX:
        case AM_RELL:
        case AM_MVP:
            return 2;
        case AM_ABSL:
        case AM_ABSLX:
        case AM_ABSLIND:
            return 3;
        case AM_FPU_REG2:
        case AM_FPU_REG1:
            return 1;   /* Register byte */
        case AM_FPU_DP:
            return 2;   /* Register byte + DP */
        case AM_FPU_ABS:
            return 3;   /* Register byte + ABS (16-bit) */
        case AM_FPU_IND:
            return 1;   /* Register byte (Fn, Rm) */
        case AM_FPU_ABS32:
            return 5;   /* Register byte + ABS32 */
        default:
            return 0;
    }
}

/* Format operand based on addressing mode */
static void format_operand(char *out, size_t out_size, AddrMode mode,
                           const uint8_t *operand, int opsize, uint32_t pc, int m_flag) {
    uint32_t val;
    int32_t rel;
    
    switch (mode) {
        case AM_IMP:
            out[0] = '\0';
            break;
        case AM_ACC:
            snprintf(out, out_size, "A");
            break;
        case AM_IMM:
        case AM_IMM_M:
        case AM_IMM_X:
            if (opsize == 1)
                snprintf(out, out_size, "#$%02X", operand[0]);
            else if (opsize == 2)
                snprintf(out, out_size, "#$%04X", operand[0] | (operand[1] << 8));
            else if (opsize == 4)
                snprintf(out, out_size, "#$%08X", 
                        operand[0] | (operand[1] << 8) | (operand[2] << 16) | (operand[3] << 24));
            break;
        case AM_DP:
            snprintf(out, out_size, "$%02X", operand[0]);
            break;
        case AM_DPX:
            snprintf(out, out_size, "$%02X,X", operand[0]);
            break;
        case AM_DPY:
            snprintf(out, out_size, "$%02X,Y", operand[0]);
            break;
        case AM_ABS:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "B+$%04X", val);
            else snprintf(out, out_size, "$%04X", val);
            break;
        case AM_ABSX:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "B+$%04X,X", val);
            else snprintf(out, out_size, "$%04X,X", val);
            break;
        case AM_ABSY:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "B+$%04X,Y", val);
            else snprintf(out, out_size, "$%04X,Y", val);
            break;
        case AM_IND:
            snprintf(out, out_size, "($%02X)", operand[0]);
            break;
        case AM_INDX:
            snprintf(out, out_size, "($%02X,X)", operand[0]);
            break;
        case AM_INDY:
            snprintf(out, out_size, "($%02X),Y", operand[0]);
            break;
        case AM_INDL:
            snprintf(out, out_size, "[$%02X]", operand[0]);
            break;
        case AM_INDLY:
            snprintf(out, out_size, "[$%02X],Y", operand[0]);
            break;
        case AM_ABSL:
            val = operand[0] | (operand[1] << 8) | (operand[2] << 16);
            snprintf(out, out_size, "$%06X", val);
            break;
        case AM_ABSLX:
            val = operand[0] | (operand[1] << 8) | (operand[2] << 16);
            snprintf(out, out_size, "$%06X,X", val);
            break;
        case AM_REL:
            if (opsize == 2) {
                rel = (int16_t)(operand[0] | (operand[1] << 8));
                val = pc + 3 + rel;  /* PC + instruction size + offset */
            } else {
                rel = (int8_t)operand[0];
                val = pc + 2 + rel;  /* PC + instruction size + offset */
            }
            snprintf(out, out_size, "$%04X", val & 0xFFFF);
            break;
        case AM_RELL:
            rel = (int16_t)(operand[0] | (operand[1] << 8));
            val = pc + 3 + rel;  /* PC + instruction size + offset */
            snprintf(out, out_size, "$%04X", val & 0xFFFF);
            break;
        case AM_SR:
            snprintf(out, out_size, "$%02X,S", operand[0]);
            break;
        case AM_SRIY:
            snprintf(out, out_size, "($%02X,S),Y", operand[0]);
            break;
        case AM_MVP:
            snprintf(out, out_size, "$%02X,$%02X", operand[1], operand[0]);
            break;
        case AM_ABSIND:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "(B+$%04X)", val);
            else snprintf(out, out_size, "($%04X)", val);
            break;
        case AM_ABSINDX:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "(B+$%04X,X)", val);
            else snprintf(out, out_size, "($%04X,X)", val);
            break;
        case AM_ABSLIND:
            val = operand[0] | (operand[1] << 8);
            if (m_flag == 2) snprintf(out, out_size, "[B+$%04X]", val);
            else snprintf(out, out_size, "[$%04X]", val);
            break;
        case AM_FPU_REG2:
            /* Two FP registers: Fd, Fs */
            snprintf(out, out_size, "F%d, F%d", 
                    (operand[0] >> 4) & 0x0F, operand[0] & 0x0F);
            break;
        case AM_FPU_REG1:
            /* Single FP register: Fd */
            snprintf(out, out_size, "F%d", (operand[0] >> 4) & 0x0F);
            break;
        case AM_FPU_DP:
            /* FP register + DP: Fn, $xx */
            snprintf(out, out_size, "F%d, $%02X", operand[0] & 0x0F, operand[1]);
            break;
        case AM_FPU_ABS:
            /* FP register + ABS: Fn, $xxxx */
            val = operand[1] | (operand[2] << 8);
            snprintf(out, out_size, "F%d, $%04X", operand[0] & 0x0F, val);
            break;
        case AM_FPU_IND:
            /* FP register + (Rm): Fn, (Rm) */
            snprintf(out, out_size, "F%d, (R%d)",
                    (operand[0] >> 4) & 0x0F, operand[0] & 0x0F);
            break;
        case AM_FPU_ABS32:
            /* FP register + ABS32: Fn, $xxxxxxxx */
            val = operand[1] | (operand[2] << 8) | (operand[3] << 16) | (operand[4] << 24);
            snprintf(out, out_size, "F%d, $%08X", operand[0] & 0x0F, val);
            break;
        default:
            snprintf(out, out_size, "???");
            break;
    }
}

void m65832_dis_init(M65832DisCtx *ctx) {
    ctx->m_flag = 1;    /* Default 16-bit */
    ctx->x_flag = 1;
    ctx->emu_mode = 0;
}

int m65832_disasm(const uint8_t *buf, size_t buflen, uint32_t pc,
                  char *out, size_t out_size, M65832DisCtx *ctx) {
    M65832DisCtx default_ctx;
    if (!ctx) {
        m65832_dis_init(&default_ctx);
        ctx = &default_ctx;
    }
    
    if (buflen == 0) {
        snprintf(out, out_size, "???");
        return 0;
    }
    
    uint8_t opcode = buf[0];
    const char *mnemonic;
    AddrMode mode;
    int prefix_len = 0;
    int is_ext = 0;
    int m_flag = ctx->m_flag;
    int x_flag = ctx->x_flag;
    
    if (m_flag == 2 || x_flag == 2) {
        m_flag = 2;
        x_flag = 2;
    }

    if (m_flag == 2 && opcode == 0x42) {
        snprintf(out, out_size, ".BYTE $42");
        return 1;
    }

    /* Check for extended prefix ($02) */
    if (opcode == 0x02 && buflen > 1) {
        is_ext = 1;
        prefix_len = 1;
        opcode = buf[1];
    }
    
    /* Look up instruction */
    if (is_ext) {
        const char *ext_alu = get_ext_alu_name(opcode);
        if (ext_alu) {
            if (buflen < 3) {
                snprintf(out, out_size, ".BYTE $02,$%02X", opcode);
                return 2;
            }
            uint8_t mode = buf[2];
            int size = (mode >> 6) & 0x03;
            int target = (mode >> 5) & 0x01;
            uint8_t addr_mode = mode & 0x1F;
            const char *suffix = (size == 0) ? ".B" : (size == 1) ? ".W" : (size == 2) ? "" : ".?";
            int index = 3;
            char dest_str[16];
            if (target) {
                if (buflen <= (size_t)index) {
                    snprintf(out, out_size, ".BYTE $02,$%02X", opcode);
                    return 2;
                }
                format_dp_reg(dest_str, sizeof(dest_str), buf[index++]);
            } else {
                snprintf(dest_str, sizeof(dest_str), "A");
            }

            char src_str[64];
            src_str[0] = '\0';
            int unary_no_src = (addr_mode == 0x00) &&
                               (opcode == 0x8B || opcode == 0x8C || opcode == 0x8D ||
                                opcode == 0x8E || opcode == 0x8F || opcode == 0x90 ||
                                (opcode == 0x97 && target == 1));
            if (!unary_no_src) {
                uint32_t val32;
                uint16_t val16;
                uint8_t val8;
                int need = 0;
                switch (addr_mode) {
                    case 0x00: need = 1; break;
                    case 0x01: need = 1; break;
                    case 0x02: need = 1; break;
                    case 0x03: need = 1; break;
                    case 0x04: need = 1; break;
                    case 0x05: need = 1; break;
                    case 0x06: need = 1; break;
                    case 0x07: need = 1; break;
                    case 0x08: need = 2; break;
                    case 0x09: need = 2; break;
                    case 0x0A: need = 2; break;
                    case 0x0B: need = 2; break;
                    case 0x0C: need = 2; break;
                    case 0x0D: need = 2; break;
                    case 0x10: need = 4; break;
                    case 0x11: need = 4; break;
                    case 0x12: need = 4; break;
                    case 0x13: need = 4; break;
                    case 0x14: need = 4; break;
                    case 0x15: need = 4; break;
                    case 0x18: need = (size == 0) ? 1 : (size == 1) ? 2 : 4; break;
                    case 0x19: need = 0; break;
                    case 0x1A: need = 0; break;
                    case 0x1B: need = 0; break;
                    case 0x1C: need = 1; break;
                    case 0x1D: need = 1; break;
                    default: need = 0; break;
                }
                if (buflen < (size_t)(index + need)) {
                    snprintf(out, out_size, ".BYTE $02,$%02X", opcode);
                    return 2;
                }
                switch (addr_mode) {
                    case 0x00:
                        val8 = buf[index++];
                        format_dp_reg(src_str, sizeof(src_str), val8);
                        break;
                    case 0x01:
                        val8 = buf[index++];
                        format_dp_reg(src_str, sizeof(src_str), val8);
                        snprintf(src_str + strlen(src_str), sizeof(src_str) - strlen(src_str), ",X");
                        break;
                    case 0x02:
                        val8 = buf[index++];
                        format_dp_reg(src_str, sizeof(src_str), val8);
                        snprintf(src_str + strlen(src_str), sizeof(src_str) - strlen(src_str), ",Y");
                        break;
                    case 0x03: {
                        char base[16];
                        val8 = buf[index++];
                        format_dp_reg(base, sizeof(base), val8);
                        snprintf(src_str, sizeof(src_str), "(%s,X)", base);
                        break;
                    }
                    case 0x04: {
                        char base[16];
                        val8 = buf[index++];
                        format_dp_reg(base, sizeof(base), val8);
                        snprintf(src_str, sizeof(src_str), "(%s),Y", base);
                        break;
                    }
                    case 0x05: {
                        char base[16];
                        val8 = buf[index++];
                        format_dp_reg(base, sizeof(base), val8);
                        snprintf(src_str, sizeof(src_str), "(%s)", base);
                        break;
                    }
                    case 0x06: {
                        char base[16];
                        val8 = buf[index++];
                        format_dp_reg(base, sizeof(base), val8);
                        snprintf(src_str, sizeof(src_str), "[%s]", base);
                        break;
                    }
                    case 0x07: {
                        char base[16];
                        val8 = buf[index++];
                        format_dp_reg(base, sizeof(base), val8);
                        snprintf(src_str, sizeof(src_str), "[%s],Y", base);
                        break;
                    }
                    case 0x08:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "B+$%04X" : "$%04X", val16);
                        break;
                    case 0x09:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "B+$%04X,X" : "$%04X,X", val16);
                        break;
                    case 0x0A:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "B+$%04X,Y" : "$%04X,Y", val16);
                        break;
                    case 0x0B:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "(B+$%04X)" : "($%04X)", val16);
                        break;
                    case 0x0C:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "(B+$%04X,X)" : "($%04X,X)", val16);
                        break;
                    case 0x0D:
                        val16 = buf[index] | (buf[index + 1] << 8);
                        index += 2;
                        snprintf(src_str, sizeof(src_str), m_flag == 2 ? "[B+$%04X]" : "[$%04X]", val16);
                        break;
                    case 0x10:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "$%08X", val32);
                        break;
                    case 0x11:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "$%08X,X", val32);
                        break;
                    case 0x12:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "$%08X,Y", val32);
                        break;
                    case 0x13:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "($%08X)", val32);
                        break;
                    case 0x14:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "($%08X,X)", val32);
                        break;
                    case 0x15:
                        val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                        index += 4;
                        snprintf(src_str, sizeof(src_str), "[$%08X]", val32);
                        break;
                    case 0x18:
                        if (size == 0) {
                            val8 = buf[index++];
                            snprintf(src_str, sizeof(src_str), "#$%02X", val8);
                        } else if (size == 1) {
                            val16 = buf[index] | (buf[index + 1] << 8);
                            index += 2;
                            snprintf(src_str, sizeof(src_str), "#$%04X", val16);
                        } else {
                            val32 = buf[index] | (buf[index + 1] << 8) | (buf[index + 2] << 16) | (buf[index + 3] << 24);
                            index += 4;
                            snprintf(src_str, sizeof(src_str), "#$%08X", val32);
                        }
                        break;
                    case 0x19:
                        snprintf(src_str, sizeof(src_str), "A");
                        break;
                    case 0x1A:
                        snprintf(src_str, sizeof(src_str), "X");
                        break;
                    case 0x1B:
                        snprintf(src_str, sizeof(src_str), "Y");
                        break;
                    case 0x1C:
                        val8 = buf[index++];
                        snprintf(src_str, sizeof(src_str), "$%02X,S", val8);
                        break;
                    case 0x1D:
                        val8 = buf[index++];
                        snprintf(src_str, sizeof(src_str), "($%02X,S),Y", val8);
                        break;
                    default:
                        snprintf(src_str, sizeof(src_str), "???");
                        break;
                }
            }

            if (unary_no_src) {
                snprintf(out, out_size, "%s%s %s", ext_alu, suffix, dest_str);
                return index;
            }
            if (opcode == 0x97 && target == 0 && addr_mode != 0x19 && addr_mode != 0x1A && addr_mode != 0x1B) {
                snprintf(out, out_size, "%s%s %s", ext_alu, suffix, src_str);
                return index;
            }
            snprintf(out, out_size, "%s%s %s,%s", ext_alu, suffix, dest_str, src_str);
            return index;
        }

        /* Special handling for shifter and extend instructions */
        if (opcode == 0x98 && buflen >= 5) {
            /* $02 $98 [op|cnt] [dest_dp] [src_dp] - Barrel shifter */
            static const char *shift_ops[] = {"SHL", "SHR", "SAR", "ROL", "ROR", "???", "???", "???"};
            uint8_t op_cnt = buf[2];
            uint8_t shift_op = (op_cnt >> 5) & 0x07;
            uint8_t count = op_cnt & 0x1F;
            uint8_t dest_dp = buf[3];
            uint8_t src_dp = buf[4];
            /* Format with R0-R63 if aligned */
            char dest_str[16], src_str[16];
            if ((dest_dp & 3) == 0) 
                snprintf(dest_str, sizeof(dest_str), "R%d", dest_dp / 4);
            else
                snprintf(dest_str, sizeof(dest_str), "$%02X", dest_dp);
            if ((src_dp & 3) == 0)
                snprintf(src_str, sizeof(src_str), "R%d", src_dp / 4);
            else
                snprintf(src_str, sizeof(src_str), "$%02X", src_dp);
            if (count == 0x1F) {
                snprintf(out, out_size, "%s %s,%s,A", shift_ops[shift_op], dest_str, src_str);
            } else {
                snprintf(out, out_size, "%s %s,%s,#%d", shift_ops[shift_op], dest_str, src_str, count);
            }
            return 5;
        }
        if (opcode == 0x99 && buflen >= 5) {
            /* $02 $99 [subop] [dest_dp] [src_dp] - Extend operations */
            static const char *ext_ops[] = {
                "SEXT8", "SEXT16", "ZEXT8", "ZEXT16", "CLZ", "CTZ", "POPCNT", "???"
            };
            uint8_t subop = buf[2];
            uint8_t dest_dp = buf[3];
            uint8_t src_dp = buf[4];
            /* Format with R0-R63 if aligned */
            char dest_str[16], src_str[16];
            if ((dest_dp & 3) == 0)
                snprintf(dest_str, sizeof(dest_str), "R%d", dest_dp / 4);
            else
                snprintf(dest_str, sizeof(dest_str), "$%02X", dest_dp);
            if ((src_dp & 3) == 0)
                snprintf(src_str, sizeof(src_str), "R%d", src_dp / 4);
            else
                snprintf(src_str, sizeof(src_str), "$%02X", src_dp);
            if (subop < 7) {
                snprintf(out, out_size, "%s %s,%s", ext_ops[subop], dest_str, src_str);
            } else {
                snprintf(out, out_size, ".BYTE $02,$99,$%02X,$%02X,$%02X", subop, dest_dp, src_dp);
            }
            return 5;
        }
        
        const ExtOpcodeEntry *entry = &ext_opcode_table[opcode];
        if (!entry->mnemonic) {
            snprintf(out, out_size, ".BYTE $02,$%02X", opcode);
            return 2;
        }
        mnemonic = entry->mnemonic;
        mode = entry->mode;
    } else {
        const OpcodeEntry *entry = &opcode_table[opcode];
        mnemonic = entry->mnemonic;
        mode = entry->mode;
    }
    
    /* Get operand size */
    int opsize = get_operand_size(mode, m_flag, x_flag);
    
    int total_len = 1 + prefix_len + opsize;
    
    if ((size_t)total_len > buflen) {
        snprintf(out, out_size, ".BYTE $%02X", buf[0]);
        return 1;
    }
    
    /* Format output */
    char operand_str[64];
    const uint8_t *operand_bytes = buf + 1 + prefix_len;
    
    format_operand(operand_str, sizeof(operand_str), mode, operand_bytes, opsize, pc, m_flag);
    
    /* Build output string */
    if (operand_str[0])
        snprintf(out, out_size, "%s %s", mnemonic, operand_str);
    else
        snprintf(out, out_size, "%s", mnemonic);
    
    /* Track state changes from REP/SEP */
    if (strcmp(mnemonic, "REP") == 0 && opsize >= 1) {
        uint8_t val = operand_bytes[0];
        if (val & 0x20) ctx->m_flag = 1;  /* M=1: 16-bit */
        if (val & 0x10) ctx->x_flag = 1;
    } else if (strcmp(mnemonic, "SEP") == 0 && opsize >= 1) {
        uint8_t val = operand_bytes[0];
        if (val & 0x20) ctx->m_flag = 0;  /* M=0: 8-bit */
        if (val & 0x10) ctx->x_flag = 0;
    }
    
    return total_len;
}

int m65832_disasm_buffer(const uint8_t *buf, size_t buflen, uint32_t start_pc,
                         M65832DisCtx *ctx, m65832_dis_callback callback, void *userdata) {
    M65832DisCtx default_ctx;
    if (!ctx) {
        m65832_dis_init(&default_ctx);
        ctx = &default_ctx;
    }
    
    size_t offset = 0;
    uint32_t pc = start_pc;
    char text[128];
    
    while (offset < buflen) {
        int len = m65832_disasm(buf + offset, buflen - offset, pc, text, sizeof(text), ctx);
        if (len == 0) {
            /* Invalid instruction, emit as byte */
            snprintf(text, sizeof(text), ".BYTE $%02X", buf[offset]);
            len = 1;
        }
        
        if (callback) {
            callback(pc, buf + offset, len, text, userdata);
        }
        
        offset += len;
        pc += len;
    }
    
    return (int)offset;
}

#endif /* M65832DIS_IMPLEMENTATION || M65832DIS_STANDALONE */

/* ============================================================================ */
/* Standalone Program                                                           */
/* ============================================================================ */

#ifdef M65832DIS_STANDALONE

#include <stdlib.h>
#include <errno.h>

#define VERSION "1.0.0"

static int show_hex = 0;
static int show_addr = 1;

static void print_instruction(uint32_t pc, const uint8_t *bytes, int bytelen,
                              const char *text, void *userdata) {
    (void)userdata;
    
    if (show_addr) {
        printf("%08X  ", pc);
    }
    
    if (show_hex) {
        for (int i = 0; i < bytelen && i < 6; i++) {
            printf("%02X ", bytes[i]);
        }
        /* Pad to 18 chars (6 bytes * 3) */
        for (int i = bytelen; i < 6; i++) {
            printf("   ");
        }
    }
    
    printf("%s\n", text);
}

static void print_usage(const char *prog) {
    fprintf(stderr, "M65832 Disassembler v%s\n", VERSION);
    fprintf(stderr, "Usage: %s [options] input.bin\n\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -o ADDR      Set origin/start address (default: 0)\n");
    fprintf(stderr, "  -l LENGTH    Number of bytes to disassemble\n");
    fprintf(stderr, "  -s OFFSET    Start offset in file (default: 0)\n");
    fprintf(stderr, "  -x           Show hex bytes\n");
    fprintf(stderr, "  -n           Don't show addresses\n");
    fprintf(stderr, "  -m8          Set 8-bit accumulator mode\n");
    fprintf(stderr, "  -m16         Set 16-bit accumulator mode (default)\n");
    fprintf(stderr, "  -m32         Set 32-bit accumulator mode\n");
    fprintf(stderr, "  -x8          Set 8-bit index mode\n");
    fprintf(stderr, "  -x16         Set 16-bit index mode (default)\n");
    fprintf(stderr, "  -x32         Set 32-bit index mode\n");
    fprintf(stderr, "  --help       Show this help\n");
}

int main(int argc, char **argv) {
    const char *input_file = NULL;
    uint32_t origin = 0;
    uint32_t length = 0;
    uint32_t start_offset = 0;
    M65832DisCtx ctx;
    
    m65832_dis_init(&ctx);
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            origin = strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "-l") == 0 && i + 1 < argc) {
            length = strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            start_offset = strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "-x") == 0) {
            show_hex = 1;
        } else if (strcmp(argv[i], "-n") == 0) {
            show_addr = 0;
        } else if (strcmp(argv[i], "-m8") == 0) {
            ctx.m_flag = 0;
        } else if (strcmp(argv[i], "-m16") == 0) {
            ctx.m_flag = 1;
        } else if (strcmp(argv[i], "-m32") == 0) {
            ctx.m_flag = 2;
        } else if (strcmp(argv[i], "-x8") == 0) {
            ctx.x_flag = 0;
        } else if (strcmp(argv[i], "-x16") == 0) {
            ctx.x_flag = 1;
        } else if (strcmp(argv[i], "-x32") == 0) {
            ctx.x_flag = 2;
        } else if (strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "error: unknown option '%s'\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        } else {
            input_file = argv[i];
        }
    }
    
    if (!input_file) {
        fprintf(stderr, "error: no input file\n");
        print_usage(argv[0]);
        return 1;
    }
    
    /* Read file */
    FILE *f = fopen(input_file, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s': %s\n", input_file, strerror(errno));
        return 1;
    }
    
    /* Get file size */
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if (start_offset >= (uint32_t)file_size) {
        fprintf(stderr, "error: start offset %u beyond file size %ld\n", start_offset, file_size);
        fclose(f);
        return 1;
    }
    
    /* Seek to start offset */
    if (start_offset > 0) {
        fseek(f, start_offset, SEEK_SET);
    }
    
    /* Determine length to read */
    uint32_t bytes_available = file_size - start_offset;
    if (length == 0 || length > bytes_available) {
        length = bytes_available;
    }
    
    /* Allocate and read buffer */
    uint8_t *buf = malloc(length);
    if (!buf) {
        fprintf(stderr, "error: out of memory\n");
        fclose(f);
        return 1;
    }
    
    if (fread(buf, 1, length, f) != length) {
        fprintf(stderr, "error: failed to read file\n");
        free(buf);
        fclose(f);
        return 1;
    }
    fclose(f);
    
    /* Disassemble */
    printf("; Disassembly of %s\n", input_file);
    printf("; Origin: $%08X, Length: %u bytes\n\n", origin, length);
    
    m65832_disasm_buffer(buf, length, origin, &ctx, print_instruction, NULL);
    
    free(buf);
    return 0;
}

#endif /* M65832DIS_STANDALONE */
