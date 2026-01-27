/*
 * M65832 Instruction Set Architecture Definitions
 * 
 * Shared definitions for assembler, disassembler, and LLVM backend.
 * This file defines addressing modes, opcode tables, and instruction encodings.
 *
 * Copyright (c) 2026. MIT License.
 */

#ifndef M65832_ISA_H
#define M65832_ISA_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================== */
/* Addressing Modes                                                           */
/* ========================================================================== */

typedef enum {
    M65_AM_IMP,         /* Implied: NOP */
    M65_AM_ACC,         /* Accumulator: ASL A (or just ASL) */
    M65_AM_IMM,         /* Immediate: LDA #$xx */
    M65_AM_DP,          /* Direct Page: LDA $xx */
    M65_AM_DPX,         /* DP Indexed X: LDA $xx,X */
    M65_AM_DPY,         /* DP Indexed Y: LDA $xx,Y */
    M65_AM_ABS,         /* Absolute: LDA $xxxx */
    M65_AM_ABSX,        /* Abs Indexed X: LDA $xxxx,X */
    M65_AM_ABSY,        /* Abs Indexed Y: LDA $xxxx,Y */
    M65_AM_IND,         /* Indirect: JMP ($xxxx) */
    M65_AM_INDX,        /* Indexed Indirect: LDA ($xx,X) */
    M65_AM_INDY,        /* Indirect Indexed: LDA ($xx),Y */
    M65_AM_INDL,        /* Indirect Long: LDA [$xx] */
    M65_AM_INDLY,       /* Indirect Long Y: LDA [$xx],Y */
    M65_AM_ABSL,        /* Absolute Long: LDA $xxxxxx */
    M65_AM_ABSLX,       /* Abs Long X: LDA $xxxxxx,X */
    M65_AM_REL,         /* Relative: BEQ label */
    M65_AM_RELL,        /* Relative Long: BRL label */
    M65_AM_SR,          /* Stack Relative: LDA $xx,S */
    M65_AM_SRIY,        /* SR Indirect Y: LDA ($xx,S),Y */
    M65_AM_MVP,         /* Block Move: MVP src,dst */
    M65_AM_MVN,         /* Block Move: MVN src,dst */
    M65_AM_ABSIND,      /* Abs Indirect: JMP ($xxxx) */
    M65_AM_ABSINDX,     /* Abs Indexed Indirect: JMP ($xxxx,X) */
    M65_AM_ABSLIND,     /* Abs Long Indirect: JML [$xxxx] */
    /* Extended 32-bit modes (Extended ALU only) */
    M65_AM_IMM32,       /* 32-bit Immediate */
    M65_AM_ABS32,       /* 32-bit Absolute */
    /* FPU register modes */
    M65_AM_FPU_REG2,    /* Two FP registers: FADD.S F0, F1 */
    M65_AM_FPU_REG1,    /* One FP register: F2I.S F0 */
    M65_AM_FPU_DP,      /* FP register + DP: LDF F0, $xx */
    M65_AM_FPU_ABS,     /* FP register + Abs: LDF F0, $xxxx */
    M65_AM_FPU_IND,     /* FP register + GPR indirect: LDF F0, (R0) */
    M65_AM_FPU_LONG,    /* FP register + 32-bit Abs: LDF F0, $xxxxxxxx */
    M65_AM_COUNT
} M65_AddrMode;

/* ========================================================================== */
/* Instruction Definitions                                                    */
/* ========================================================================== */

/* Opcode 0xFF = not available for this addressing mode */
#define M65_OP_INVALID 0xFF

/* Standard 6502/65816 instruction entry */
typedef struct {
    const char *name;
    uint8_t opcodes[M65_AM_COUNT];  /* Opcode for each addressing mode */
    uint8_t ext_prefix;             /* 1 if needs $02 prefix */
} M65_Instruction;

/* M65832 Extended instruction entry */
typedef struct {
    const char *name;
    uint8_t ext_opcode;
    M65_AddrMode mode;
} M65_ExtInstruction;

/* Extended ALU instruction ($02 $80-$97 range) */
typedef struct {
    const char *name;
    uint8_t opcode;       /* Base opcode ($80=LD, $81=ST, etc.) */
    int is_unary;         /* 1 for INC/DEC/ASL/LSR/ROL/ROR/STZ */
    int allows_mem_dest;  /* 1 if destination can be memory */
} M65_ExtALUInstruction;

/* Shifter instruction ($02 $98 prefix) */
typedef struct {
    const char *name;
    uint8_t op_code;  /* Bits 7-5 of op|cnt byte */
} M65_ShifterInstruction;

/* Extend instruction ($02 $99 prefix) */
typedef struct {
    const char *name;
    uint8_t subop;
} M65_ExtendInstruction;

/* ========================================================================== */
/* Opcode Tables (extern declarations)                                        */
/* ========================================================================== */

extern const M65_Instruction m65_instructions[];
extern const M65_ExtInstruction m65_ext_instructions[];
extern const M65_ExtALUInstruction m65_extalu_instructions[];
extern const M65_ShifterInstruction m65_shifter_instructions[];
extern const M65_ExtendInstruction m65_extend_instructions[];

/* Number of entries in tables (excluding NULL terminator) */
extern const int m65_num_instructions;
extern const int m65_num_ext_instructions;
extern const int m65_num_extalu_instructions;
extern const int m65_num_shifter_instructions;
extern const int m65_num_extend_instructions;

/* ========================================================================== */
/* Instruction Lookup Functions                                               */
/* ========================================================================== */

/* Find standard instruction by mnemonic (case-insensitive) */
const M65_Instruction *m65_find_instruction(const char *mnemonic);

/* Find extended instruction by mnemonic and addressing mode */
const M65_ExtInstruction *m65_find_ext_instruction(const char *mnemonic, M65_AddrMode mode);

/* Find extended ALU instruction by mnemonic */
const M65_ExtALUInstruction *m65_find_extalu_instruction(const char *mnemonic);

/* Find shifter instruction by mnemonic */
const M65_ShifterInstruction *m65_find_shifter_instruction(const char *mnemonic);

/* Find extend instruction by mnemonic */
const M65_ExtendInstruction *m65_find_extend_instruction(const char *mnemonic);

/* ========================================================================== */
/* Register Parsing                                                           */
/* ========================================================================== */

/* Parse GPR register R0-R63, returns DP address (0, 4, 8, ...) or -1 */
int m65_parse_gpr(const char *name);

/* Parse FPU register F0-F15, returns register number or -1 */
int m65_parse_fpr(const char *name);

/* ========================================================================== */
/* Instruction Encoding Helpers                                               */
/* ========================================================================== */

/* Get operand size for addressing mode (not counting opcode) */
int m65_get_operand_size(M65_AddrMode mode, int m_flag, int x_flag);

/* Get immediate size based on instruction and processor flags */
int m65_get_imm_size(const char *mnemonic, int m_flag, int x_flag, int data_override);

/* Check if mnemonic uses M flag for width */
int m65_uses_m_flag(const char *mnemonic);

/* Check if mnemonic uses X flag for width */
int m65_uses_x_flag(const char *mnemonic);

/* Check if mnemonic is a branch instruction */
int m65_is_branch(const char *mnemonic);

/* ========================================================================== */
/* Extended ALU Addressing Mode Encoding                                      */
/* ========================================================================== */

/* Extended ALU source addressing mode codes */
#define M65_EXTALU_SRC_DP        0x00  /* dp (Rn) */
#define M65_EXTALU_SRC_DPX       0x01  /* dp,X */
#define M65_EXTALU_SRC_DPY       0x02  /* dp,Y */
#define M65_EXTALU_SRC_DPX_IND   0x03  /* (dp,X) */
#define M65_EXTALU_SRC_DP_INDY   0x04  /* (dp),Y */
#define M65_EXTALU_SRC_DP_IND    0x05  /* (dp) */
#define M65_EXTALU_SRC_DP_INDL   0x06  /* [dp] */
#define M65_EXTALU_SRC_DP_INDLY  0x07  /* [dp],Y */
#define M65_EXTALU_SRC_ABS       0x08  /* abs */
#define M65_EXTALU_SRC_ABSX      0x09  /* abs,X */
#define M65_EXTALU_SRC_ABSY      0x0A  /* abs,Y */
#define M65_EXTALU_SRC_ABS_IND   0x0B  /* (abs) */
#define M65_EXTALU_SRC_ABS_INDX  0x0C  /* (abs,X) */
#define M65_EXTALU_SRC_ABS_INDL  0x0D  /* [abs] */
#define M65_EXTALU_SRC_ABS32     0x10  /* abs32 */
#define M65_EXTALU_SRC_ABS32X    0x11  /* abs32,X */
#define M65_EXTALU_SRC_ABS32Y    0x12  /* abs32,Y */
#define M65_EXTALU_SRC_ABS32_IND 0x13  /* (abs32) */
#define M65_EXTALU_SRC_ABS32_INDX 0x14 /* (abs32,X) */
#define M65_EXTALU_SRC_ABS32_INDL 0x15 /* [abs32] */
#define M65_EXTALU_SRC_IMM       0x18  /* #imm */
#define M65_EXTALU_SRC_A         0x19  /* A */
#define M65_EXTALU_SRC_X         0x1A  /* X */
#define M65_EXTALU_SRC_Y         0x1B  /* Y */
#define M65_EXTALU_SRC_SR        0x1C  /* $xx,S */
#define M65_EXTALU_SRC_SRIY      0x1D  /* ($xx,S),Y */

#ifdef __cplusplus
}
#endif

#endif /* M65832_ISA_H */
