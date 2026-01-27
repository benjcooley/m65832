/*
 * M65832 Assembler
 * 
 * A two-pass assembler for the M65832 processor.
 * Supports all 6502/65816 instructions plus M65832 extensions.
 *
 * Build: cc -O2 -o m65832as m65832as.c
 * Usage: m65832as [options] input.asm -o output.bin
 *
 * Copyright (c) 2026. MIT License.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <stdarg.h>
#include <limits.h>

#define VERSION "1.1.0"
#define MAX_LINE 1024
#define MAX_SYMBOLS 4096
#define MAX_LABEL 64
#define MAX_OUTPUT (1024 * 1024)  /* 1MB max output */
#define MAX_SECTIONS 16
#define MAX_INCLUDE_DEPTH 16
#define MAX_INCLUDE_PATHS 8
#define MAX_PATH 512

/* ========================================================================== */
/* Types and Structures                                                       */
/* ========================================================================== */

typedef enum {
    AM_IMP,         /* Implied: NOP */
    AM_ACC,         /* Accumulator: ASL A (or just ASL) */
    AM_IMM,         /* Immediate: LDA #$xx */
    AM_DP,          /* Direct Page: LDA $xx */
    AM_DPX,         /* DP Indexed X: LDA $xx,X */
    AM_DPY,         /* DP Indexed Y: LDA $xx,Y */
    AM_ABS,         /* Absolute: LDA $xxxx */
    AM_ABSX,        /* Abs Indexed X: LDA $xxxx,X */
    AM_ABSY,        /* Abs Indexed Y: LDA $xxxx,Y */
    AM_IND,         /* Indirect: JMP ($xxxx) */
    AM_INDX,        /* Indexed Indirect: LDA ($xx,X) */
    AM_INDY,        /* Indirect Indexed: LDA ($xx),Y */
    AM_INDL,        /* Indirect Long: LDA [$xx] */
    AM_INDLY,       /* Indirect Long Y: LDA [$xx],Y */
    AM_ABSL,        /* Absolute Long: LDA $xxxxxx */
    AM_ABSLX,       /* Abs Long X: LDA $xxxxxx,X */
    AM_REL,         /* Relative: BEQ label */
    AM_RELL,        /* Relative Long: BRL label */
    AM_SR,          /* Stack Relative: LDA $xx,S */
    AM_SRIY,        /* SR Indirect Y: LDA ($xx,S),Y */
    AM_MVP,         /* Block Move: MVP src,dst */
    AM_MVN,         /* Block Move: MVN src,dst */
    AM_ABSIND,      /* Abs Indirect: JMP ($xxxx) */
    AM_ABSINDX,     /* Abs Indexed Indirect: JMP ($xxxx,X) */
    AM_ABSLIND,     /* Abs Long Indirect: JML [$xxxx] */
    /* Extended 32-bit modes (Extended ALU only) */
    AM_IMM32,       /* 32-bit Immediate */
    AM_ABS32,       /* 32-bit Absolute */
    /* FPU register modes */
    AM_FPU_REG2,    /* Two FP registers: FADD.S F0, F1 */
    AM_FPU_REG1,    /* One FP register: I2F.S F0 */
    AM_FPU_DP,      /* FP register + DP: LDF F0, $xx */
    AM_FPU_ABS,     /* FP register + Abs: LDF F0, $xxxx */
    AM_FPU_IND,     /* FP register + Reg Indirect: LDF F0, (R1) */
    AM_FPU_LONG,    /* FP register + 32-bit Abs: LDF F0, $xxxxxxxx */
    AM_FPU_IMM_S,   /* FP register + single imm: LDF.S F0, #1.5 */
    AM_FPU_IMM_D,   /* FP register + double imm: LDF.D F0, #1.5 */
    AM_COUNT
} AddrMode;

typedef struct {
    const char *name;
    uint8_t opcodes[AM_COUNT];  /* Opcode for each addressing mode, 0xFF = invalid */
    uint8_t ext_prefix;         /* 1 if needs $02 prefix */
} Instruction;

typedef struct {
    char name[MAX_LABEL];
    uint32_t value;
    int defined;
    int line_defined;
    int section_index;  /* Which section this symbol is in (-1 = none/absolute) */
} Symbol;

typedef struct {
    uint8_t *data;
    uint32_t org;
    uint32_t pc;
    uint32_t size;
    uint32_t capacity;
} Output;

typedef struct {
    char name[MAX_LABEL];
    uint32_t org;
    uint32_t pc;
    uint32_t size;
    uint8_t *data;
    uint32_t capacity;
    int org_set;        /* 1 if origin was explicitly set */
} Section;

/* File location for error messages */
typedef struct {
    char filename[MAX_PATH];
    int line_num;
} FileLocation;

/* CFI (Call Frame Information) state for DWARF debug info */
#define MAX_CFI_SAVED_REGS 128
#define MAX_CFI_STACK 8

typedef struct {
    int cfa_reg;                /* CFA register number */
    int cfa_offset;             /* CFA offset from register */
    int reg_offsets[MAX_CFI_SAVED_REGS]; /* Saved register offsets (INT_MIN = not saved) */
} CFIState;

typedef struct {
    FileLocation file_stack[MAX_INCLUDE_DEPTH];
    int file_depth;
    int pass;
    int errors;
    int warnings;
    Symbol symbols[MAX_SYMBOLS];
    int num_symbols;
    
    /* Sections */
    Section sections[MAX_SECTIONS];
    int num_sections;
    int current_section;
    
    /* Legacy output (for compatibility) */
    Output output;
    
    /* Include paths */
    char include_paths[MAX_INCLUDE_PATHS][MAX_PATH];
    int num_include_paths;
    
    int m_flag;     /* 0=8-bit, 1=16-bit, 2=32-bit */
    int x_flag;     /* 0=8-bit, 1=16-bit, 2=32-bit */
    int verbose;
    int output_hex;
    
    /* DWARF CFI state */
    int cfi_in_proc;            /* Currently inside .cfi_startproc */
    CFIState cfi_state;         /* Current CFI state */
    CFIState cfi_stack[MAX_CFI_STACK];  /* Stack for remember/restore */
    int cfi_stack_depth;
    int emit_dwarf;             /* Emit DWARF debug info (future) */
} Assembler;

/* ========================================================================== */
/* Instruction Table                                                          */
/* ========================================================================== */

/* Opcode 0xFF = not available for this addressing mode */
#define __ 0xFF

/* Standard 6502/65816 instructions */
static const Instruction instructions[] = {
    /*                IMP   ACC   IMM   DP    DPX   DPY   ABS   ABSX  ABSY  IND   INDX  INDY  INDL  INDLY ABSL  ABSLX REL   RELL  SR    SRIY  MVP   MVN   AIND  AINDX ALIND IMM32 ABS32 */
    { "ADC",        { __,   __,   0x69, 0x65, 0x75, __,   0x6D, 0x7D, 0x79, __,   0x61, 0x71, 0x67, 0x77, 0x6F, 0x7F, __,   __,   0x63, 0x73, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "AND",        { __,   __,   0x29, 0x25, 0x35, __,   0x2D, 0x3D, 0x39, __,   0x21, 0x31, 0x27, 0x37, 0x2F, 0x3F, __,   __,   0x23, 0x33, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "ASL",        { __,   0x0A, __,   0x06, 0x16, __,   0x0E, 0x1E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BCC",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x90, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BCS",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0xB0, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BEQ",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0xF0, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BIT",        { __,   __,   0x89, 0x24, 0x34, __,   0x2C, 0x3C, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BMI",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x30, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BNE",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0xD0, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BPL",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x10, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BRA",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x80, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BRK",        { 0x00, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BRL",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x82, __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BVC",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x50, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "BVS",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x70, __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CLC",        { 0x18, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CLD",        { 0xD8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CLI",        { 0x58, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CLV",        { 0xB8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CMP",        { __,   __,   0xC9, 0xC5, 0xD5, __,   0xCD, 0xDD, 0xD9, __,   0xC1, 0xD1, 0xC7, 0xD7, 0xCF, 0xDF, __,   __,   0xC3, 0xD3, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "COP",        { __,   __,   0x02, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CPX",        { __,   __,   0xE0, 0xE4, __,   __,   0xEC, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "CPY",        { __,   __,   0xC0, 0xC4, __,   __,   0xCC, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "DEC",        { __,   0x3A, __,   0xC6, 0xD6, __,   0xCE, 0xDE, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "DEX",        { 0xCA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "DEY",        { 0x88, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "EOR",        { __,   __,   0x49, 0x45, 0x55, __,   0x4D, 0x5D, 0x59, __,   0x41, 0x51, 0x47, 0x57, 0x4F, 0x5F, __,   __,   0x43, 0x53, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "INC",        { __,   0x1A, __,   0xE6, 0xF6, __,   0xEE, 0xFE, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "INX",        { 0xE8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "INY",        { 0xC8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "JML",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x5C, __,   __,   __,   __,   __,   __,   __,   __,   __,   0xDC, __,   __   }, 0 },
    { "JMP",        { __,   __,   __,   __,   __,   __,   0x4C, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x6C, 0x7C, __,   __,   __   }, 0 },
    { "JSL",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x22, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "JSR",        { __,   __,   __,   __,   __,   __,   0x20, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "LDA",        { __,   __,   0xA9, 0xA5, 0xB5, __,   0xAD, 0xBD, 0xB9, __,   0xA1, 0xB1, 0xA7, 0xB7, 0xAF, 0xBF, __,   __,   0xA3, 0xB3, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "LDX",        { __,   __,   0xA2, 0xA6, __,   0xB6, 0xAE, __,   0xBE, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "LDY",        { __,   __,   0xA0, 0xA4, 0xB4, __,   0xAC, 0xBC, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "LSR",        { __,   0x4A, __,   0x46, 0x56, __,   0x4E, 0x5E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "MVN",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x54, __,   __,   __,   __,   __   }, 0 },
    { "MVP",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x44, __,   __,   __,   __,   __,   __   }, 0 },
    { "NOP",        { 0xEA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "ORA",        { __,   __,   0x09, 0x05, 0x15, __,   0x0D, 0x1D, 0x19, __,   0x01, 0x11, 0x07, 0x17, 0x0F, 0x1F, __,   __,   0x03, 0x13, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PEA",        { __,   __,   0xF4, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PEI",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   0xD4, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PER",        { __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   0x62, __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHA",        { 0x48, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHB",        { 0x8B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHD",        { 0x0B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHK",        { 0x4B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHP",        { 0x08, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHX",        { 0xDA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PHY",        { 0x5A, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLA",        { 0x68, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLB",        { 0xAB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLD",        { 0x2B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLP",        { 0x28, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLX",        { 0xFA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "PLY",        { 0x7A, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "REP",        { __,   __,   0xC2, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "ROL",        { __,   0x2A, __,   0x26, 0x36, __,   0x2E, 0x3E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "ROR",        { __,   0x6A, __,   0x66, 0x76, __,   0x6E, 0x7E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "RTI",        { 0x40, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "RTL",        { 0x6B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "RTS",        { 0x60, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "SBC",        { __,   __,   0xE9, 0xE5, 0xF5, __,   0xED, 0xFD, 0xF9, __,   0xE1, 0xF1, 0xE7, 0xF7, 0xEF, 0xFF, __,   __,   0xE3, 0xF3, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "SEC",        { 0x38, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "SED",        { 0xF8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "SEI",        { 0x78, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "SEP",        { __,   __,   0xE2, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "STA",        { __,   __,   __,   0x85, 0x95, __,   0x8D, 0x9D, 0x99, __,   0x81, 0x91, 0x87, 0x97, 0x8F, 0x9F, __,   __,   0x83, 0x93, __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "STP",        { 0xDB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "STX",        { __,   __,   __,   0x86, __,   0x96, 0x8E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "STY",        { __,   __,   __,   0x84, 0x94, __,   0x8C, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "STZ",        { __,   __,   __,   0x64, 0x74, __,   0x9C, 0x9E, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TAX",        { 0xAA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TAY",        { 0xA8, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TCD",        { 0x5B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TCS",        { 0x1B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TDC",        { 0x7B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TRB",        { __,   __,   __,   0x14, __,   __,   0x1C, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TSB",        { __,   __,   __,   0x04, __,   __,   0x0C, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TSC",        { 0x3B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TSX",        { 0xBA, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TXA",        { 0x8A, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TXS",        { 0x9A, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TXY",        { 0x9B, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TYA",        { 0x98, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "TYX",        { 0xBB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "WAI",        { 0xCB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "WDM",        { __,   __,   0x42, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "XBA",        { 0xEB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { "XCE",        { 0xFB, __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __,   __   }, 0 },
    { NULL, { 0 }, 0 }
};

/* M65832 Extended instructions ($02 prefix) */
typedef struct {
    const char *name;
    uint8_t ext_opcode;
    AddrMode mode;
} ExtInstruction;

static const ExtInstruction ext_instructions[] = {
    /* Multiply/Divide */
    { "MUL",    0x00, AM_DP   },
    { "MULU",   0x01, AM_DP   },
    { "MUL",    0x02, AM_ABS  },
    { "MULU",   0x03, AM_ABS  },
    { "DIV",    0x04, AM_DP   },
    { "DIVU",   0x05, AM_DP   },
    { "DIV",    0x06, AM_ABS  },
    { "DIVU",   0x07, AM_ABS  },
    /* Atomics */
    { "CAS",    0x10, AM_DP   },
    { "CAS",    0x11, AM_ABS  },
    { "LLI",    0x12, AM_DP   },
    { "LLI",    0x13, AM_ABS  },
    { "SCI",    0x14, AM_DP   },
    { "SCI",    0x15, AM_ABS  },
    /* Base registers */
    { "SVBR",   0x20, AM_IMM  },  /* Actually imm32, handled specially */
    { "SVBR",   0x21, AM_DP   },
    { "SB",     0x22, AM_IMM  },
    { "SB",     0x23, AM_DP   },
    { "SD",     0x24, AM_IMM  },
    { "SD",     0x25, AM_DP   },
    /* Register Window */
    { "RSET",   0x30, AM_IMP  },
    { "RCLR",   0x31, AM_IMP  },
    /* System */
    { "TRAP",   0x40, AM_IMM  },  /* 8-bit immediate */
    { "FENCE",  0x50, AM_IMP  },
    { "FENCER", 0x51, AM_IMP  },
    { "FENCEW", 0x52, AM_IMP  },
    /* Extended flags */
    { "REPE",   0x60, AM_IMM  },
    { "SEPE",   0x61, AM_IMM  },
    /* 32-bit stack ops */
    { "PHD32",  0x70, AM_IMP  },
    { "PLD32",  0x71, AM_IMP  },
    { "PHB32",  0x72, AM_IMP  },
    { "PLB32",  0x73, AM_IMP  },
    { "PHVBR",  0x74, AM_IMP  },
    { "PLVBR",  0x75, AM_IMP  },
    /* Temp register */
    { "TTA",    0x9A, AM_IMP  },
    { "TAT",    0x9B, AM_IMP  },
    /* 64-bit load/store */
    { "LDQ",    0x9C, AM_DP   },
    { "LDQ",    0x9D, AM_ABS  },
    { "STQ",    0x9E, AM_DP   },
    { "STQ",    0x9F, AM_ABS  },
    /* LEA */
    { "LEA",    0xA0, AM_DP   },
    { "LEA",    0xA1, AM_DPX  },
    { "LEA",    0xA2, AM_ABS  },
    { "LEA",    0xA3, AM_ABSX },
    /* FPU Load/Store (with register byte) */
    { "LDF",    0xB0, AM_FPU_DP  },
    { "LDF",    0xB1, AM_FPU_ABS },
    { "STF",    0xB2, AM_FPU_DP  },
    { "STF",    0xB3, AM_FPU_ABS },
    { "LDF",    0xB4, AM_FPU_IND },
    { "STF",    0xB5, AM_FPU_IND },
    { "LDF",    0xB6, AM_FPU_LONG },
    { "STF",    0xB7, AM_FPU_LONG },
    { "LDF.S",  0xB8, AM_FPU_IMM_S },
    { "LDF.D",  0xB9, AM_FPU_IMM_D },
    /* FPU single-precision (two-operand) */
    { "FADD.S", 0xC0, AM_FPU_REG2 },
    { "FSUB.S", 0xC1, AM_FPU_REG2 },
    { "FMUL.S", 0xC2, AM_FPU_REG2 },
    { "FDIV.S", 0xC3, AM_FPU_REG2 },
    { "FNEG.S", 0xC4, AM_FPU_REG2 },
    { "FABS.S", 0xC5, AM_FPU_REG2 },
    { "FCMP.S", 0xC6, AM_FPU_REG2 },
    { "F2I.S",  0xC7, AM_FPU_REG1 },
    { "I2F.S",  0xC8, AM_FPU_REG1 },
    { "FMOV.S", 0xC9, AM_FPU_REG2 },
    { "FSQRT.S",0xCA, AM_FPU_REG2 },
    /* FPU double-precision (two-operand) */
    { "FADD.D", 0xD0, AM_FPU_REG2 },
    { "FSUB.D", 0xD1, AM_FPU_REG2 },
    { "FMUL.D", 0xD2, AM_FPU_REG2 },
    { "FDIV.D", 0xD3, AM_FPU_REG2 },
    { "FNEG.D", 0xD4, AM_FPU_REG2 },
    { "FABS.D", 0xD5, AM_FPU_REG2 },
    { "FCMP.D", 0xD6, AM_FPU_REG2 },
    { "F2I.D",  0xD7, AM_FPU_REG1 },
    { "I2F.D",  0xD8, AM_FPU_REG1 },
    { "FMOV.D", 0xD9, AM_FPU_REG2 },
    { "FSQRT.D",0xDA, AM_FPU_REG2 },
    /* FPU register transfers */
    { "FTOA",   0xE0, AM_FPU_REG1 },
    { "FTOT",   0xE1, AM_FPU_REG1 },
    { "ATOF",   0xE2, AM_FPU_REG1 },
    { "TTOF",   0xE3, AM_FPU_REG1 },
    { "FCVT.DS",0xE4, AM_FPU_REG2 },
    { "FCVT.SD",0xE5, AM_FPU_REG2 },
    { NULL, 0, 0 }
};

/* Register-targeted ALU instructions ($02 $E8 prefix)
 * Syntax: OP dest, source
 * Example: LD $04, $00 or ADC $08, A or ADC $08, #$1234
 */
typedef struct {
    const char *name;
    uint8_t op_code;  /* High nibble of op|mode byte */
} RegALUInstruction;

static const RegALUInstruction regalu_instructions[] = {
    { "LD",   0x00 },  /* Load: dest = src */
    { "ADC",  0x10 },  /* Add with carry: dest = dest + src + C */
    { "SBC",  0x20 },  /* Subtract with borrow: dest = dest - src - !C */
    { "AND",  0x30 },  /* Logical AND: dest = dest & src */
    { "ORA",  0x40 },  /* Logical OR: dest = dest | src */
    { "EOR",  0x50 },  /* Exclusive OR: dest = dest ^ src */
    { "CMP",  0x60 },  /* Compare: flags = dest - src (no store) */
    { NULL, 0 }
};

/* Register-targeted ALU source mode encoding */
#define REGALU_SRC_DPX_IND  0x00  /* (dp,X) */
#define REGALU_SRC_DP       0x01  /* dp */
#define REGALU_SRC_IMM      0x02  /* #imm */
#define REGALU_SRC_A        0x03  /* A */
#define REGALU_SRC_DP_Y     0x04  /* (dp),Y */
#define REGALU_SRC_DPX      0x05  /* dp,X */
#define REGALU_SRC_ABS      0x06  /* abs */
#define REGALU_SRC_ABSX     0x07  /* abs,X */
#define REGALU_SRC_ABSY     0x08  /* abs,Y */
#define REGALU_SRC_DP_IND   0x09  /* (dp) */

/* Shifter instructions ($02 $98 prefix)
 * Syntax: OP dest, src, #count  or  OP dest, src, A
 * Example: SHL $08, $04, #4  or  SHR R2, R1, A
 */
typedef struct {
    const char *name;
    uint8_t op_code;  /* Bits 7-5 of op|cnt byte */
} ShifterInstruction;

static const ShifterInstruction shifter_instructions[] = {
    { "SHL",  0x00 },  /* Shift left logical */
    { "SHR",  0x20 },  /* Shift right logical */
    { "SAR",  0x40 },  /* Shift right arithmetic */
    { "ROL",  0x60 },  /* Rotate left through carry */
    { "ROR",  0x80 },  /* Rotate right through carry */
    { NULL, 0 }
};

/* Extend instructions ($02 $99 prefix)
 * Syntax: OP dest, src
 * Example: SEXT8 $10, $0C  or  CLZ R4, R1
 */
typedef struct {
    const char *name;
    uint8_t subop;
} ExtendInstruction;

static const ExtendInstruction extend_instructions[] = {
    { "SEXT8",  0x00 },  /* Sign extend 8->32 */
    { "SEXT16", 0x01 },  /* Sign extend 16->32 */
    { "ZEXT8",  0x02 },  /* Zero extend 8->32 */
    { "ZEXT16", 0x03 },  /* Zero extend 16->32 */
    { "CLZ",    0x04 },  /* Count leading zeros */
    { "CTZ",    0x05 },  /* Count trailing zeros */
    { "POPCNT", 0x06 },  /* Population count */
    { NULL, 0 }
};

#undef __

/* Check if name is a register alias (R0-R63) and return DP address, or -1 */
static int parse_register_alias(const char *name) {
    if ((name[0] == 'R' || name[0] == 'r') && isdigit((unsigned char)name[1])) {
        int reg = 0;
        const char *p = name + 1;
        while (isdigit((unsigned char)*p)) {
            reg = reg * 10 + (*p - '0');
            p++;
        }
        if (*p == '\0' && reg >= 0 && reg <= 63) {
            return reg * 4;  /* R0=$00, R1=$04, R2=$08, etc. */
        }
    }
    return -1;
}

/* Check if name is a FP register alias (F0-F15) and return register number, or -1 */
static int parse_fp_register(const char *name) {
    if ((name[0] == 'F' || name[0] == 'f') && isdigit((unsigned char)name[1])) {
        int reg = 0;
        const char *p = name + 1;
        while (isdigit((unsigned char)*p)) {
            reg = reg * 10 + (*p - '0');
            p++;
        }
        if (*p == '\0' && reg >= 0 && reg <= 15) {
            return reg;
        }
    }
    return -1;
}

/* ========================================================================== */
/* Utility Functions                                                          */
/* ========================================================================== */

/* Get current filename for error messages */
static const char *current_filename(Assembler *as) {
    if (as->file_depth > 0)
        return as->file_stack[as->file_depth - 1].filename;
    return "<unknown>";
}

/* Get current line number for error messages */
static int current_line(Assembler *as) {
    if (as->file_depth > 0)
        return as->file_stack[as->file_depth - 1].line_num;
    return 0;
}

static void error(Assembler *as, const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: error: ", current_filename(as), current_line(as));
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    as->errors++;
}

static void warning(Assembler *as, const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: warning: ", current_filename(as), current_line(as));
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    as->warnings++;
}

/* Extract directory from a path */
static void get_directory(const char *path, char *dir, size_t dir_size) {
    const char *last_sep = strrchr(path, '/');
#ifdef _WIN32
    const char *last_sep2 = strrchr(path, '\\');
    if (last_sep2 > last_sep) last_sep = last_sep2;
#endif
    if (last_sep) {
        size_t len = last_sep - path;
        if (len >= dir_size) len = dir_size - 1;
        strncpy(dir, path, len);
        dir[len] = '\0';
    } else {
        dir[0] = '.';
        dir[1] = '\0';
    }
}

static char *skip_whitespace(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

static char *skip_to_whitespace(char *s) {
    while (*s && !isspace((unsigned char)*s)) s++;
    return s;
}

static void str_upper(char *s) {
    while (*s) {
        *s = toupper((unsigned char)*s);
        s++;
    }
}

static int is_label_char(char c) {
    return isalnum((unsigned char)c) || c == '_' || c == '.';
}

/* ========================================================================== */
/* Symbol Table                                                               */
/* ========================================================================== */

static Symbol *find_symbol(Assembler *as, const char *name) {
    for (int i = 0; i < as->num_symbols; i++) {
        if (strcmp(as->symbols[i].name, name) == 0)
            return &as->symbols[i];
    }
    return NULL;
}

static Symbol *add_symbol(Assembler *as, const char *name, uint32_t value, int defined) {
    Symbol *sym = find_symbol(as, name);
    if (sym) {
        /* Only error on pass 1 for genuine duplicates (same pass, different value) */
        /* Pass 2 redefinitions are expected in two-pass assembly */
        if (defined && sym->defined && sym->value != value && as->pass == 1) {
            error(as, "symbol '%s' already defined at line %d", name, sym->line_defined);
            return NULL;
        }
        if (defined) {
            sym->value = value;
            sym->defined = 1;
            sym->line_defined = current_line(as);
            sym->section_index = as->current_section;
        }
        return sym;
    }
    if (as->num_symbols >= MAX_SYMBOLS) {
        error(as, "too many symbols (max %d)", MAX_SYMBOLS);
        return NULL;
    }
    sym = &as->symbols[as->num_symbols++];
    strncpy(sym->name, name, MAX_LABEL - 1);
    sym->name[MAX_LABEL - 1] = '\0';
    sym->value = value;
    sym->defined = defined;
    sym->line_defined = current_line(as);
    sym->section_index = defined ? as->current_section : -1;
    return sym;
}

/* ========================================================================== */
/* Section Management                                                         */
/* ========================================================================== */

static int section_init(Section *sec, const char *name) {
    strncpy(sec->name, name, MAX_LABEL - 1);
    sec->name[MAX_LABEL - 1] = '\0';
    sec->org = 0;
    sec->pc = 0;
    sec->size = 0;
    sec->org_set = 0;
    sec->capacity = MAX_OUTPUT / MAX_SECTIONS;
    sec->data = malloc(sec->capacity);
    if (!sec->data) return 0;
    memset(sec->data, 0xFF, sec->capacity);
    return 1;
}

static void section_free(Section *sec) {
    free(sec->data);
    sec->data = NULL;
}

static Section *find_section(Assembler *as, const char *name) {
    for (int i = 0; i < as->num_sections; i++) {
        if (strcasecmp(as->sections[i].name, name) == 0)
            return &as->sections[i];
    }
    return NULL;
}

static Section *get_or_create_section(Assembler *as, const char *name) {
    Section *sec = find_section(as, name);
    if (sec) return sec;
    
    if (as->num_sections >= MAX_SECTIONS) {
        error(as, "too many sections (max %d)", MAX_SECTIONS);
        return NULL;
    }
    
    sec = &as->sections[as->num_sections++];
    if (!section_init(sec, name)) {
        error(as, "out of memory for section '%s'", name);
        return NULL;
    }
    return sec;
}

static Section *current_section(Assembler *as) {
    if (as->current_section >= 0 && as->current_section < as->num_sections)
        return &as->sections[as->current_section];
    return NULL;
}

static int switch_section(Assembler *as, const char *name) {
    Section *sec = get_or_create_section(as, name);
    if (!sec) return 0;
    
    /* Find index */
    for (int i = 0; i < as->num_sections; i++) {
        if (&as->sections[i] == sec) {
            as->current_section = i;
            return 1;
        }
    }
    return 0;
}

/* Get current PC (from current section or legacy output) */
static uint32_t get_pc(Assembler *as) {
    Section *sec = current_section(as);
    if (sec) return sec->pc;
    return as->output.pc;
}

/* Set current PC */
static void set_pc(Assembler *as, uint32_t pc) {
    Section *sec = current_section(as);
    if (sec) {
        sec->pc = pc;
        if (!sec->org_set) {
            sec->org = pc;
            sec->org_set = 1;
        }
    }
    as->output.pc = pc;
    if (as->output.org == 0) {
        as->output.org = pc;
    }
}

/* ========================================================================== */
/* Output Buffer                                                              */
/* ========================================================================== */

static int output_init(Output *out) {
    out->data = malloc(MAX_OUTPUT);
    if (!out->data) return 0;
    out->org = 0;
    out->pc = 0;
    out->size = 0;
    out->capacity = MAX_OUTPUT;
    memset(out->data, 0xFF, MAX_OUTPUT);  /* Fill with $FF (like ROM) */
    return 1;
}

static void output_free(Output *out) {
    free(out->data);
    out->data = NULL;
}

static void emit_byte(Assembler *as, uint8_t b) {
    Section *sec = current_section(as);
    if (sec) {
        uint32_t sec_offset = sec->pc - sec->org;
        /* Track size in both passes for section linking */
        if (sec_offset + 1 > sec->size)
            sec->size = sec_offset + 1;
        
        if (as->pass == 2) {
            /* Write to section data */
            if (sec_offset < sec->capacity) {
                sec->data[sec_offset] = b;
            }
            /* Write to legacy output buffer using section's absolute PC */
            uint32_t out_offset = sec->pc - as->output.org;
            if (out_offset < as->output.capacity) {
                as->output.data[out_offset] = b;
                if (out_offset + 1 > as->output.size)
                    as->output.size = out_offset + 1;
            }
        }
        sec->pc++;
    }
    as->output.pc++;
}

static void emit_word(Assembler *as, uint16_t w) {
    emit_byte(as, w & 0xFF);
    emit_byte(as, (w >> 8) & 0xFF);
}

static void emit_long(Assembler *as, uint32_t l) {
    emit_byte(as, l & 0xFF);
    emit_byte(as, (l >> 8) & 0xFF);
    emit_byte(as, (l >> 16) & 0xFF);
}

static void emit_quad(Assembler *as, uint32_t l) {
    emit_byte(as, l & 0xFF);
    emit_byte(as, (l >> 8) & 0xFF);
    emit_byte(as, (l >> 16) & 0xFF);
    emit_byte(as, (l >> 24) & 0xFF);
}

/* ========================================================================== */
/* Expression Evaluator                                                       */
/* ========================================================================== */

static int parse_number(const char *s, uint32_t *value, const char **end) {
    uint32_t v = 0;
    const char *p = s;
    
    if (*p == '$') {
        /* Hex */
        p++;
        if (!isxdigit((unsigned char)*p)) return 0;
        while (isxdigit((unsigned char)*p)) {
            v = v * 16;
            if (*p >= '0' && *p <= '9') v += *p - '0';
            else if (*p >= 'A' && *p <= 'F') v += *p - 'A' + 10;
            else if (*p >= 'a' && *p <= 'f') v += *p - 'a' + 10;
            p++;
        }
    } else if (*p == '%') {
        /* Binary */
        p++;
        if (*p != '0' && *p != '1') return 0;
        while (*p == '0' || *p == '1') {
            v = v * 2 + (*p - '0');
            p++;
        }
    } else if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) {
        /* C-style hex */
        p += 2;
        if (!isxdigit((unsigned char)*p)) return 0;
        while (isxdigit((unsigned char)*p)) {
            v = v * 16;
            if (*p >= '0' && *p <= '9') v += *p - '0';
            else if (*p >= 'A' && *p <= 'F') v += *p - 'A' + 10;
            else if (*p >= 'a' && *p <= 'f') v += *p - 'a' + 10;
            p++;
        }
    } else if (isdigit((unsigned char)*p)) {
        /* Decimal */
        while (isdigit((unsigned char)*p)) {
            v = v * 10 + (*p - '0');
            p++;
        }
    } else {
        return 0;
    }
    
    *value = v;
    *end = p;
    return 1;
}

static int parse_expression(Assembler *as, const char *s, uint32_t *value, const char **end) {
    const char *p = skip_whitespace((char*)s);
    uint32_t v = 0;
    int negate = 0;
    int have_value = 0;
    
    /* Handle leading operators */
    if (*p == '-') {
        negate = 1;
        p++;
        p = skip_whitespace((char*)p);
    } else if (*p == '+') {
        p++;
        p = skip_whitespace((char*)p);
    } else if (*p == '<') {
        /* Low byte operator */
        p++;
        if (!parse_expression(as, p, &v, &p)) return 0;
        *value = v & 0xFF;
        *end = p;
        return 1;
    } else if (*p == '>') {
        /* High byte operator */
        p++;
        if (!parse_expression(as, p, &v, &p)) return 0;
        *value = (v >> 8) & 0xFF;
        *end = p;
        return 1;
    } else if (*p == '^') {
        /* Bank byte operator */
        p++;
        if (!parse_expression(as, p, &v, &p)) return 0;
        *value = (v >> 16) & 0xFF;
        *end = p;
        return 1;
    }
    
    /* Parse primary value */
    if (*p == '(') {
        /* Parenthesized expression */
        p++;
        if (!parse_expression(as, p, &v, &p)) return 0;
        p = skip_whitespace((char*)p);
        if (*p != ')') {
            error(as, "expected ')'");
            return 0;
        }
        p++;
        have_value = 1;
    } else if (*p == '*') {
        /* Current PC */
        v = get_pc(as);
        p++;
        have_value = 1;
    } else if (*p == '\'') {
        /* Character constant */
        p++;
        if (*p == '\\') {
            p++;
            switch (*p) {
                case 'n': v = '\n'; break;
                case 'r': v = '\r'; break;
                case 't': v = '\t'; break;
                case '0': v = '\0'; break;
                case '\\': v = '\\'; break;
                case '\'': v = '\''; break;
                default: v = *p; break;
            }
            p++;
        } else {
            v = (unsigned char)*p++;
        }
        if (*p == '\'') p++;
        have_value = 1;
    } else if (parse_number(p, &v, &p)) {
        have_value = 1;
    } else if (is_label_char(*p) && !isdigit((unsigned char)*p)) {
        /* Symbol or register alias */
        char label[MAX_LABEL];
        int i = 0;
        while (is_label_char(*p) && i < MAX_LABEL - 1)
            label[i++] = *p++;
        label[i] = '\0';
        str_upper(label);  /* Case-insensitive symbol lookup */
        
        /* Check for register alias R0-R63 */
        int reg_addr = parse_register_alias(label);
        if (reg_addr >= 0) {
            v = reg_addr;
            have_value = 1;
        } else {
            Symbol *sym = find_symbol(as, label);
            if (!sym) {
                sym = add_symbol(as, label, 0, 0);
            }
            if (sym) {
                if (!sym->defined && as->pass == 2) {
                    error(as, "undefined symbol '%s'", label);
                    return 0;
                }
                v = sym->value;
                have_value = 1;
            }
        }
    }
    
    if (!have_value) {
        return 0;
    }
    
    if (negate) v = -v;
    
    /* Handle binary operators */
    p = skip_whitespace((char*)p);
    while (*p == '+' || *p == '-' || *p == '*' || *p == '/' || *p == '%' || *p == '&' || *p == '|' || *p == '^') {
        char op = *p++;
        p = skip_whitespace((char*)p);
        uint32_t v2;
        if (!parse_expression(as, p, &v2, &p)) return 0;
        switch (op) {
            case '+': v += v2; break;
            case '-': v -= v2; break;
            case '*': v *= v2; break;
            case '/': 
                if (v2 == 0) {
                    error(as, "division by zero");
                    return 0;
                }
                v /= v2;
                break;
            case '%':
                if (v2 == 0) {
                    error(as, "modulo by zero");
                    return 0;
                }
                v %= v2;
                break;
            case '&': v &= v2; break;
            case '|': v |= v2; break;
            case '^': v ^= v2; break;
        }
        p = skip_whitespace((char*)p);
    }
    
    *value = v;
    *end = p;
    return 1;
}

/* ========================================================================== */
/* Operand Parser                                                             */
/* ========================================================================== */

typedef struct {
    AddrMode mode;
    uint32_t value;
    int force_width;    /* 0=auto, 1=byte, 2=word, 3=long, 4=quad */
    uint8_t mvp_dst;    /* For MVP/MVN */
    int b_relative;     /* Explicit B+offset syntax */
} Operand;

static int parse_operand(Assembler *as, char *s, Operand *op) {
    char *p = skip_whitespace(s);
    op->mode = AM_IMP;
    op->value = 0;
    op->force_width = 0;
    op->mvp_dst = 0;
    op->b_relative = 0;
    
    if (!*p || *p == ';') {
        /* No operand = implied or accumulator */
        return 1;
    }
    
    /* Check for 'A' (accumulator) */
    if ((*p == 'A' || *p == 'a') && (!p[1] || isspace((unsigned char)p[1]) || p[1] == ';')) {
        op->mode = AM_ACC;
        return 1;
    }
    
    /* Immediate: #value */
    if (*p == '#') {
        p++;
        if (!parse_expression(as, p, &op->value, (const char**)&p)) {
            error(as, "invalid immediate value");
            return 0;
        }
        op->mode = AM_IMM;
        return 1;
    }
    
    /* Indirect modes: (xxx) or [xxx] */
    if (*p == '(' || *p == '[') {
        char bracket = *p++;
        char close_bracket = (bracket == '(') ? ')' : ']';
        int is_long = (bracket == '[');
        
        p = skip_whitespace(p);
        if ((p[0] == 'B' || p[0] == 'b') && p[1] == '+') {
            op->b_relative = 1;
            p += 2;
            p = skip_whitespace(p);
        }
        if (!parse_expression(as, p, &op->value, (const char**)&p)) {
            error(as, "invalid indirect address");
            return 0;
        }
        if (op->b_relative && op->value > 0xFFFF) {
            error(as, "B+offset must be 16-bit");
            return 0;
        }
        p = skip_whitespace(p);
        
        /* Check for ,X or ,S before closing bracket */
        if (*p == ',') {
            p++;
            p = skip_whitespace(p);
            if ((*p == 'X' || *p == 'x') && p[1] == close_bracket) {
                p += 2;
                if (is_long) {
                    error(as, "invalid addressing mode");
                    return 0;
                }
                /* Check for ),Y */
                p = skip_whitespace(p);
                if (*p == ',') {
                    error(as, "invalid addressing mode");
                    return 0;
                }
                op->mode = (op->value <= 0xFF) ? AM_INDX : AM_ABSINDX;
                return 1;
            }
            if ((*p == 'S' || *p == 's') && p[1] == close_bracket) {
                p += 2;
                /* Check for ),Y */
                p = skip_whitespace(p);
                if (*p == ',') {
                    p++;
                    p = skip_whitespace(p);
                    if (*p == 'Y' || *p == 'y') {
                        op->mode = AM_SRIY;
                        return 1;
                    }
                }
                op->mode = AM_SR;
                return 1;
            }
        }
        
        if (*p != close_bracket) {
            error(as, "expected '%c'", close_bracket);
            return 0;
        }
        p++;
        p = skip_whitespace(p);
        
        /* Check for ),Y or ],Y */
        if (*p == ',') {
            p++;
            p = skip_whitespace(p);
            if (*p == 'Y' || *p == 'y') {
                op->mode = is_long ? AM_INDLY : AM_INDY;
                return 1;
            }
            error(as, "expected Y index");
            return 0;
        }
        
        /* Plain indirect */
        if (is_long) {
            op->mode = (op->value <= 0xFF) ? AM_INDL : AM_ABSLIND;
        } else {
            op->mode = (op->value <= 0xFF) ? AM_IND : AM_ABSIND;
        }
        return 1;
    }
    
    /* Explicit B+offset (32-bit mode syntax) */
    if ((p[0] == 'B' || p[0] == 'b') && p[1] == '+') {
        p += 2;
        p = skip_whitespace(p);
        if (!parse_expression(as, p, &op->value, (const char**)&p)) {
            error(as, "invalid B+offset");
            return 0;
        }
        if (op->value > 0xFFFF) {
            error(as, "B+offset must be 16-bit");
            return 0;
        }
        op->b_relative = 1;
        p = skip_whitespace(p);
        if (*p == ',') {
            p++;
            p = skip_whitespace(p);
            if (*p == 'X' || *p == 'x') {
                op->mode = AM_ABSX;
                return 1;
            }
            if (*p == 'Y' || *p == 'y') {
                op->mode = AM_ABSY;
                return 1;
            }
            error(as, "expected X or Y index");
            return 0;
        }
        op->mode = AM_ABS;
        return 1;
    }

    /* Direct/Absolute addressing */
    if (!parse_expression(as, p, &op->value, (const char**)&p)) {
        error(as, "invalid operand");
        return 0;
    }
    p = skip_whitespace(p);
    
    /* Check for index or block move */
    if (*p == ',') {
        p++;
        p = skip_whitespace(p);
        
        if (*p == 'X' || *p == 'x') {
            p++;
            p = skip_whitespace(p);
            /* Determine mode based on value size */
            if (op->value <= 0xFF) op->mode = AM_DPX;
            else if (op->value <= 0xFFFF) op->mode = AM_ABSX;
            else op->mode = AM_ABSLX;
            return 1;
        }
        if (*p == 'Y' || *p == 'y') {
            p++;
            /* Determine mode based on value size */
            if (op->value <= 0xFF) op->mode = AM_DPY;
            else op->mode = AM_ABSY;
            return 1;
        }
        if (*p == 'S' || *p == 's') {
            op->mode = AM_SR;
            return 1;
        }
        
        /* MVP/MVN: src,dst */
        uint32_t dst;
        if (!parse_expression(as, p, &dst, (const char**)&p)) {
            error(as, "invalid block move destination");
            return 0;
        }
        op->mvp_dst = dst & 0xFF;
        op->mode = AM_MVP;  /* Parser must disambiguate MVP vs MVN by mnemonic */
        return 1;
    }
    
    /* Plain address - determine mode by size */
    if (op->value <= 0xFF) op->mode = AM_DP;
    else if (op->value <= 0xFFFF) op->mode = AM_ABS;
    else if (op->value <= 0xFFFFFF) op->mode = AM_ABSL;
    else op->mode = AM_ABS32;
    
    return 1;
}

/* ========================================================================== */
/* Instruction Encoding                                                       */
/* ========================================================================== */

static const Instruction *find_instruction(const char *mnemonic) {
    for (int i = 0; instructions[i].name; i++) {
        if (strcmp(instructions[i].name, mnemonic) == 0)
            return &instructions[i];
    }
    return NULL;
}

static const ExtInstruction *find_ext_instruction(const char *mnemonic, AddrMode mode) {
    for (int i = 0; ext_instructions[i].name; i++) {
        if (strcmp(ext_instructions[i].name, mnemonic) == 0 &&
            ext_instructions[i].mode == mode)
            return &ext_instructions[i];
    }
    /* Try without mode match for implied instructions */
    for (int i = 0; ext_instructions[i].name; i++) {
        if (strcmp(ext_instructions[i].name, mnemonic) == 0)
            return &ext_instructions[i];
    }
    return NULL;
}

static int get_imm_size(Assembler *as, const char *mnemonic, int data_override) {
    if (data_override == 1) return 1;
    if (data_override == 2) return 2;
    /* In 32-bit mode, M/X sizing is ignored */
    if (as->m_flag == 2) {
        if (strcmp(mnemonic, "LDA") == 0 || strcmp(mnemonic, "STA") == 0 ||
            strcmp(mnemonic, "ADC") == 0 || strcmp(mnemonic, "SBC") == 0 ||
            strcmp(mnemonic, "AND") == 0 || strcmp(mnemonic, "ORA") == 0 ||
            strcmp(mnemonic, "EOR") == 0 || strcmp(mnemonic, "CMP") == 0 ||
            strcmp(mnemonic, "BIT") == 0 ||
            strcmp(mnemonic, "LDX") == 0 || strcmp(mnemonic, "LDY") == 0 ||
            strcmp(mnemonic, "CPX") == 0 || strcmp(mnemonic, "CPY") == 0) {
            return 4;
        }
    }
    /* Instructions that use M flag for width */
    if (strcmp(mnemonic, "LDA") == 0 || strcmp(mnemonic, "STA") == 0 ||
        strcmp(mnemonic, "ADC") == 0 || strcmp(mnemonic, "SBC") == 0 ||
        strcmp(mnemonic, "AND") == 0 || strcmp(mnemonic, "ORA") == 0 ||
        strcmp(mnemonic, "EOR") == 0 || strcmp(mnemonic, "CMP") == 0 ||
        strcmp(mnemonic, "BIT") == 0) {
        return as->m_flag == 0 ? 1 : (as->m_flag == 1 ? 2 : 4);
    }
    /* Instructions that use X flag for width */
    if (strcmp(mnemonic, "LDX") == 0 || strcmp(mnemonic, "LDY") == 0 ||
        strcmp(mnemonic, "CPX") == 0 || strcmp(mnemonic, "CPY") == 0) {
        return as->x_flag == 0 ? 1 : (as->x_flag == 1 ? 2 : 4);
    }
    /* Fixed 8-bit */
    if (strcmp(mnemonic, "REP") == 0 || strcmp(mnemonic, "SEP") == 0 ||
        strcmp(mnemonic, "COP") == 0 || strcmp(mnemonic, "REPE") == 0 ||
        strcmp(mnemonic, "SEPE") == 0 || strcmp(mnemonic, "TRAP") == 0) {
        return 1;
    }
    /* Fixed 16-bit */
    if (strcmp(mnemonic, "PEA") == 0) {
        return 2;
    }
    return 1;  /* Default to 8-bit */
}

static int parse_next_mnemonic(char *mnemonic, char **operand) {
    char *next = skip_whitespace(*operand);
    char *end = skip_to_whitespace(next);
    if (end <= next) {
        return 0;
    }
    char saved = *end;
    *end = '\0';
    strcpy(mnemonic, next);
    *end = saved;
    str_upper(mnemonic);
    *operand = end;
    return 1;
}

static int strip_size_suffix(char *mnemonic, int *size_code) {
    char *dot = strrchr(mnemonic, '.');
    *size_code = -1;
    if (!dot) {
        return 1;
    }
    if (dot[1] == '\0' || dot[2] != '\0') {
        /* Not a single-char suffix - leave it alone */
        return 1;
    }
    /* Only strip .B, .W, .L size suffixes */
    switch (dot[1]) {
        case 'B':
            *size_code = 0;
            *dot = '\0';  /* Strip the suffix */
            break;
        case 'W':
            *size_code = 1;
            *dot = '\0';
            break;
        case 'L':
            *size_code = 2;
            *dot = '\0';
            break;
        default:
            /* Other suffixes (like .S, .D for FPU) - leave intact */
            return 1;
    }
    return 1;
}

typedef struct {
    const char *name;
    uint8_t opcode;
    int requires_src;
    int allows_mem_dest;
} ExtALUOp;

static const ExtALUOp ext_alu_ops[] = {
    /* LD/ST for register-targeted operations (R0-R63) */
    { "LD",  0x80, 1, 0 },
    { "ST",  0x81, 1, 1 },
    /* Traditional mnemonics with size suffix for A-targeted */
    { "LDA", 0x80, 1, 0 },
    { "STA", 0x81, 1, 1 },
    { "ADC", 0x82, 1, 0 },
    { "SBC", 0x83, 1, 0 },
    { "AND", 0x84, 1, 0 },
    { "ORA", 0x85, 1, 0 },
    { "EOR", 0x86, 1, 0 },
    { "CMP", 0x87, 1, 0 },
    { "BIT", 0x88, 1, 0 },
    { "TSB", 0x89, 1, 1 },
    { "TRB", 0x8A, 1, 1 },
    { "INC", 0x8B, 0, 0 },
    { "DEC", 0x8C, 0, 0 },
    { "ASL", 0x8D, 0, 0 },
    { "LSR", 0x8E, 0, 0 },
    { "ROL", 0x8F, 0, 0 },
    { "ROR", 0x90, 0, 0 },
    { "STZ", 0x97, 0, 1 },
    { NULL, 0, 0, 0 }
};

static const ExtALUOp *find_ext_alu_op(const char *mnemonic) {
    for (int i = 0; ext_alu_ops[i].name; i++) {
        if (strcmp(ext_alu_ops[i].name, mnemonic) == 0) {
            return &ext_alu_ops[i];
        }
    }
    return NULL;
}

static void append_byte(uint8_t *buf, int *len, uint32_t v) {
    buf[(*len)++] = (uint8_t)(v & 0xFF);
}

static void append_word(uint8_t *buf, int *len, uint32_t v) {
    append_byte(buf, len, v);
    append_byte(buf, len, v >> 8);
}

static void append_quad(uint8_t *buf, int *len, uint32_t v) {
    append_byte(buf, len, v);
    append_byte(buf, len, v >> 8);
    append_byte(buf, len, v >> 16);
    append_byte(buf, len, v >> 24);
}

static int parse_ext_alu_dest(Assembler *as, const char *s, int *target, uint8_t *dest_dp) {
    const char *p = skip_whitespace((char *)s);
    if ((*p == 'A' || *p == 'a') && (!p[1] || isspace((unsigned char)p[1]) || p[1] == ',')) {
        *target = 0;
        return 1;
    }
    char token[MAX_LABEL];
    int i = 0;
    while (p[i] && !isspace((unsigned char)p[i]) && p[i] != ',' && i < (MAX_LABEL - 1)) {
        token[i] = p[i];
        i++;
    }
    token[i] = '\0';
    if (token[0] == '\0') {
        return 0;
    }
    int reg_addr = parse_register_alias(token);
    if (reg_addr >= 0 && reg_addr <= 0xFF) {
        *target = 1;
        *dest_dp = (uint8_t)reg_addr;
        return 1;
    }
    error(as, "extended ALU dest must be A or Rn");
    return 0;
}

static int assemble_instruction(Assembler *as, char *mnemonic, char *operand) {
    Operand op;
    int size_code = -1;
    
    str_upper(mnemonic);
    
    if (!strip_size_suffix(mnemonic, &size_code)) {
        error(as, "invalid size suffix");
        return 0;
    }
    
    /* Check for shifter instructions ($02 $98): SHL, SHR, SAR, ROL, ROR
     * These require 3 operands separated by commas (dest, src, count)
     * Standard ROL/ROR with accumulator mode have no operands or just "A" */
    for (int i = 0; shifter_instructions[i].name; i++) {
        if (strcmp(mnemonic, shifter_instructions[i].name) == 0 &&
            strchr(operand, ',') != NULL) {  /* Must have comma to be extended form */
            /* Parse: dest, src, #count  or  dest, src, A */
            char *p = skip_whitespace(operand);
            uint32_t dest_dp, src_dp, count;
            
            /* Parse destination (DP address or register alias) */
            if (!parse_expression(as, p, &dest_dp, (const char**)&p)) {
                error(as, "expected destination for %s", mnemonic);
                return 0;
            }
            p = skip_whitespace(p);
            if (*p != ',') {
                error(as, "expected ',' after destination");
                return 0;
            }
            p++;
            
            /* Parse source (DP address or register alias) */
            p = skip_whitespace(p);
            if (!parse_expression(as, p, &src_dp, (const char**)&p)) {
                error(as, "expected source for %s", mnemonic);
                return 0;
            }
            p = skip_whitespace(p);
            if (*p != ',') {
                error(as, "expected ',' after source");
                return 0;
            }
            p++;
            
            /* Parse count: #imm or A */
            p = skip_whitespace(p);
            if (*p == '#') {
                p++;
                if (!parse_expression(as, p, &count, (const char**)&p)) {
                    error(as, "expected shift count");
                    return 0;
                }
                if (count > 31) {
                    error(as, "shift count must be 0-31");
                    return 0;
                }
            } else if ((*p == 'A' || *p == 'a') && (!p[1] || isspace((unsigned char)p[1]) || p[1] == ';')) {
                count = 0x1F;  /* A register flag */
            } else {
                error(as, "expected #count or A");
                return 0;
            }
            
            /* Emit: $02 $98 [op|cnt] [dest_dp] [src_dp] */
            emit_byte(as, 0x02);
            emit_byte(as, 0x98);
            emit_byte(as, shifter_instructions[i].op_code | (count & 0x1F));
            emit_byte(as, dest_dp & 0xFF);
            emit_byte(as, src_dp & 0xFF);
            return 1;
        }
    }
    
    /* Check for extend instructions ($02 $99): SEXT8, SEXT16, ZEXT8, ZEXT16, CLZ, CTZ, POPCNT */
    for (int i = 0; extend_instructions[i].name; i++) {
        if (strcmp(mnemonic, extend_instructions[i].name) == 0) {
            /* Parse: dest, src */
            char *p = skip_whitespace(operand);
            uint32_t dest_dp, src_dp;
            
            /* Parse destination (DP address or register alias) */
            if (!parse_expression(as, p, &dest_dp, (const char**)&p)) {
                error(as, "expected destination for %s", mnemonic);
                return 0;
            }
            p = skip_whitespace(p);
            if (*p != ',') {
                error(as, "expected ',' after destination");
                return 0;
            }
            p++;
            
            /* Parse source (DP address or register alias) */
            p = skip_whitespace(p);
            if (!parse_expression(as, p, &src_dp, (const char**)&p)) {
                error(as, "expected source for %s", mnemonic);
                return 0;
            }
            
            /* Emit: $02 $99 [subop] [dest_dp] [src_dp] */
            emit_byte(as, 0x02);
            emit_byte(as, 0x99);
            emit_byte(as, extend_instructions[i].subop);
            emit_byte(as, dest_dp & 0xFF);
            emit_byte(as, src_dp & 0xFF);
            return 1;
        }
    }
    
    /* FPU instructions with register operands */
    /* Format: FADD.S Fd, Fs  or  LDF Fn, addr  or  F2I.S Fd  or  LDF.S Fn, #imm */
    if (strncmp(mnemonic, "FADD", 4) == 0 || strncmp(mnemonic, "FSUB", 4) == 0 ||
        strncmp(mnemonic, "FMUL", 4) == 0 || strncmp(mnemonic, "FDIV", 4) == 0 ||
        strncmp(mnemonic, "FNEG", 4) == 0 || strncmp(mnemonic, "FABS", 4) == 0 ||
        strncmp(mnemonic, "FCMP", 4) == 0 || strncmp(mnemonic, "FMOV", 4) == 0 ||
        strncmp(mnemonic, "FSQRT", 5) == 0 ||
        strncmp(mnemonic, "F2I", 3) == 0 || strncmp(mnemonic, "I2F", 3) == 0 ||
        strncmp(mnemonic, "FTOA", 4) == 0 || strncmp(mnemonic, "FTOT", 4) == 0 ||
        strncmp(mnemonic, "ATOF", 4) == 0 || strncmp(mnemonic, "TTOF", 4) == 0 ||
        strncmp(mnemonic, "FCVT", 4) == 0 ||
        strncmp(mnemonic, "LDF", 3) == 0 || strcmp(mnemonic, "STF") == 0) {
        
        /* Look up the instruction in ext_instructions */
        const ExtInstruction *ext = NULL;
        for (int i = 0; ext_instructions[i].name; i++) {
            if (strcmp(ext_instructions[i].name, mnemonic) == 0) {
                ext = &ext_instructions[i];
                break;
            }
        }
        
        if (ext) {
            char *p = skip_whitespace(operand);
            int fd = -1, fs = -1;
            
            /* Parse first FP register */
            char token[16];
            int ti = 0;
            while (p[ti] && !isspace((unsigned char)p[ti]) && p[ti] != ',' && ti < 15) {
                token[ti] = p[ti];
                ti++;
            }
            token[ti] = '\0';
            fd = parse_fp_register(token);
            
            if (fd < 0) {
                error(as, "expected FP register (F0-F15)");
                return 0;
            }
            
            p += ti;
            p = skip_whitespace(p);
            
            /* Handle based on instruction type */
            if (strcmp(mnemonic, "LDF") == 0 || strcmp(mnemonic, "STF") == 0) {
                /* FP register + memory address: Fn, addr */
                if (*p != ',') {
                    error(as, "expected ',' after FP register");
                    return 0;
                }
                p++;
                p = skip_whitespace(p);

                /* Check for register indirect: (Rm) */
                if (*p == '(') {
                    p++;
                    p = skip_whitespace(p);
                    /* Parse register name */
                    ti = 0;
                    while (p[ti] && p[ti] != ')' && !isspace((unsigned char)p[ti]) && ti < 15) {
                        token[ti] = p[ti];
                        ti++;
                    }
                    token[ti] = '\0';

                    /* Check if it's a register (R0-R15) */
                    int rm = -1;
                    if ((token[0] == 'R' || token[0] == 'r') && isdigit((unsigned char)token[1])) {
                        rm = 0;
                        const char *rp = token + 1;
                        while (isdigit((unsigned char)*rp)) {
                            rm = rm * 10 + (*rp - '0');
                            rp++;
                        }
                        if (*rp != '\0' || rm > 15) {
                            rm = -1;  /* Only R0-R15 supported in indirect mode */
                        }
                    }

                    if (rm >= 0) {
                        p += ti;
                        p = skip_whitespace(p);
                        if (*p != ')') {
                            error(as, "expected ')' after register");
                            return 0;
                        }
                        /* Use the indirect mode opcode ($B4 for LDF, $B5 for STF) */
                        uint8_t ind_opcode = (strcmp(mnemonic, "LDF") == 0) ? 0xB4 : 0xB5;
                        /* Emit: $02 opcode reg_byte (Fn in high nibble, Rm in low nibble) */
                        emit_byte(as, 0x02);
                        emit_byte(as, ind_opcode);
                        emit_byte(as, (uint8_t)((fd << 4) | rm));
                        return 1;
                    } else {
                        error(as, "register indirect mode requires R0-R15");
                        return 0;
                    }
                }

                /* Parse the memory address */
                uint32_t addr;
                if (!parse_expression(as, p, &addr, (const char**)&p)) {
                    error(as, "expected address operand");
                    return 0;
                }

                if (addr <= 0xFF) {
                    /* DP form */
                    emit_byte(as, 0x02);
                    emit_byte(as, (strcmp(mnemonic, "LDF") == 0) ? 0xB0 : 0xB2);
                    emit_byte(as, (uint8_t)fd);  /* Low nibble = register */
                    emit_byte(as, addr & 0xFF);
                    return 1;
                } else if (addr <= 0xFFFF) {
                    /* ABS form */
                    emit_byte(as, 0x02);
                    emit_byte(as, (strcmp(mnemonic, "LDF") == 0) ? 0xB1 : 0xB3);
                    emit_byte(as, (uint8_t)fd);  /* Low nibble = register */
                    emit_word(as, addr & 0xFFFF);
                    return 1;
                } else {
                    /* ABS32 form */
                    emit_byte(as, 0x02);
                    emit_byte(as, (strcmp(mnemonic, "LDF") == 0) ? 0xB6 : 0xB7);
                    emit_byte(as, (uint8_t)fd);  /* Low nibble = register */
                    emit_quad(as, addr);
                    return 1;
                }
            }

            if (ext->mode == AM_FPU_REG2) {
                /* Two FP registers: Fd, Fs */
                if (*p != ',') {
                    error(as, "expected ',' after destination register");
                    return 0;
                }
                p++;
                p = skip_whitespace(p);
                
                ti = 0;
                while (p[ti] && !isspace((unsigned char)p[ti]) && p[ti] != ',' && ti < 15) {
                    token[ti] = p[ti];
                    ti++;
                }
                token[ti] = '\0';
                fs = parse_fp_register(token);
                
                if (fs < 0) {
                    error(as, "expected source FP register (F0-F15)");
                    return 0;
                }
                
                /* Emit: $02 opcode reg_byte */
                emit_byte(as, 0x02);
                emit_byte(as, ext->ext_opcode);
                emit_byte(as, (uint8_t)((fd << 4) | fs));
                return 1;
                
            } else if (ext->mode == AM_FPU_REG1) {
                /* Single FP register: Fd */
                /* Emit: $02 opcode reg_byte (src=0) */
                emit_byte(as, 0x02);
                emit_byte(as, ext->ext_opcode);
                emit_byte(as, (uint8_t)(fd << 4));
                return 1;
                
            } else if (ext->mode == AM_FPU_DP || ext->mode == AM_FPU_ABS) {
                /* FP register + memory address: Fn, addr */
                if (*p != ',') {
                    error(as, "expected ',' after FP register");
                    return 0;
                }
                p++;
                p = skip_whitespace(p);
                
                /* Check for register indirect: (Rm) */
                if (*p == '(') {
                    p++;
                    p = skip_whitespace(p);
                    /* Parse register name */
                    ti = 0;
                    while (p[ti] && p[ti] != ')' && !isspace((unsigned char)p[ti]) && ti < 15) {
                        token[ti] = p[ti];
                        ti++;
                    }
                    token[ti] = '\0';
                    
                    /* Check if it's a register (R0-R15) */
                    int rm = -1;
                    if ((token[0] == 'R' || token[0] == 'r') && isdigit((unsigned char)token[1])) {
                        rm = 0;
                        const char *rp = token + 1;
                        while (isdigit((unsigned char)*rp)) {
                            rm = rm * 10 + (*rp - '0');
                            rp++;
                        }
                        if (*rp != '\0' || rm > 15) {
                            rm = -1;  /* Only R0-R15 supported in indirect mode */
                        }
                    }
                    
                    if (rm >= 0) {
                        p += ti;
                        p = skip_whitespace(p);
                        if (*p != ')') {
                            error(as, "expected ')' after register");
                            return 0;
                        }
                        /* Use the indirect mode opcode ($B4 for LDF, $B5 for STF) */
                        uint8_t ind_opcode = (strcmp(mnemonic, "LDF") == 0) ? 0xB4 : 0xB5;
                        /* Emit: $02 opcode reg_byte (Fn in high nibble, Rm in low nibble) */
                        emit_byte(as, 0x02);
                        emit_byte(as, ind_opcode);
                        emit_byte(as, (uint8_t)((fd << 4) | rm));
                        return 1;
                    } else {
                        error(as, "register indirect mode requires R0-R15");
                        return 0;
                    }
                }
                
                /* Parse the memory address */
                uint32_t addr;
                if (!parse_expression(as, p, &addr, (const char**)&p)) {
                    error(as, "expected address operand");
                    return 0;
                }
                
                /* Determine if DP or ABS based on address size */
                if (addr <= 0xFF && ext->mode == AM_FPU_DP) {
                    /* DP form */
                    emit_byte(as, 0x02);
                    emit_byte(as, ext->ext_opcode);
                    emit_byte(as, (uint8_t)fd);  /* Low nibble = register */
                    emit_byte(as, addr & 0xFF);
                    return 1;
                } else {
                    /* ABS form - need to use the ABS opcode variant */
                    uint8_t abs_opcode = ext->ext_opcode;
                    if (ext->mode == AM_FPU_DP) {
                        /* Switch from DP to ABS opcode (+1) */
                        abs_opcode++;
                    }
                    emit_byte(as, 0x02);
                    emit_byte(as, abs_opcode);
                    emit_byte(as, (uint8_t)fd);  /* Low nibble = register */
                    emit_word(as, addr & 0xFFFF);
                    return 1;
                }
            }
        }
    }
    
    /* Extended ALU instructions ($02 $80-$97) */
    const ExtALUOp *ext_alu = find_ext_alu_op(mnemonic);
    if (ext_alu) {
        const char *p = skip_whitespace(operand);
        int dest_starts_reg = (*p == 'A' || *p == 'a' || *p == 'R' || *p == 'r');
        int use_ext_alu = (size_code >= 0 || dest_starts_reg ||
                           strcmp(mnemonic, "LD") == 0 || strcmp(mnemonic, "ST") == 0);
        if (!ext_alu->requires_src && !dest_starts_reg && size_code < 0 && !ext_alu->allows_mem_dest) {
            use_ext_alu = 0;
        }
        if (use_ext_alu) {
            int size = (size_code >= 0) ? size_code : 2;
            if (size < 0 || size > 2) {
                error(as, "invalid extended ALU size");
                return 0;
            }
            int target = 0;
            uint8_t dest_dp = 0;
            uint8_t addr_mode = 0x00;
            uint8_t operand_bytes[8];
            int operand_len = 0;

            if (ext_alu->requires_src) {
                /* Split dest,src at top-level comma, but not ,X ,Y ,S which are addressing mode suffixes */
                char *comma = NULL;
                int paren_depth = 0;
                int bracket_depth = 0;
                for (char *q = operand; *q; q++) {
                    if (*q == ';') break;
                    if (*q == '(') paren_depth++;
                    else if (*q == ')' && paren_depth > 0) paren_depth--;
                    else if (*q == '[') bracket_depth++;
                    else if (*q == ']' && bracket_depth > 0) bracket_depth--;
                    else if (*q == ',' && paren_depth == 0 && bracket_depth == 0) {
                        /* Check if this comma is followed by X, Y, or S (addressing mode suffix) */
                        char *after = skip_whitespace(q + 1);
                        char c = toupper((unsigned char)*after);
                        char c2 = after[1];
                        /* If followed by single X, Y, or S (and then nothing or whitespace/comment), 
                           it's an addressing mode suffix, not a separator */
                        if ((c == 'X' || c == 'Y' || c == 'S') && 
                            (!c2 || isspace((unsigned char)c2) || c2 == ';' || c2 == ')')) {
                            continue;  /* Skip this comma, it's part of addressing mode */
                        }
                        comma = q;
                        break;
                    }
                }
                /* For traditional mnemonics (LDA, STA, ADC, etc.) without comma,
                   the single operand is the source and A is implicit dest */
                int is_ld_st = (strcmp(mnemonic, "LD") == 0 || strcmp(mnemonic, "ST") == 0);
                if (!comma && is_ld_st) {
                    error(as, "LD/ST require dest,src format");
                    return 0;
                }
                
                char *dest_str;
                char *src_str;
                if (comma) {
                    *comma = '\0';
                    dest_str = operand;
                    src_str = comma + 1;
                } else {
                    /* Traditional mnemonic with implicit A destination */
                    dest_str = "A";
                    src_str = operand;
                    target = 0;  /* A is the destination */
                }

                int mem_dest_case = 0;
                if (!dest_starts_reg && ext_alu->allows_mem_dest) {
                    Operand mem_op;
                    if (!parse_operand(as, dest_str, &mem_op)) {
                        return 0;
                    }
                    if (as->m_flag == 2 && mem_op.value > 0xFFFF && mem_op.value <= 0xFFFFFF) {
                        error(as, "32-bit addresses must use 8 hex digits");
                        return 0;
                    }
                    /* DP addresses must be 4-byte aligned in 32-bit mode */
                    if (as->m_flag == 2 &&
                        (mem_op.mode == AM_DP || mem_op.mode == AM_DPX || mem_op.mode == AM_DPY ||
                         mem_op.mode == AM_IND || mem_op.mode == AM_INDX || mem_op.mode == AM_INDY ||
                         mem_op.mode == AM_INDL || mem_op.mode == AM_INDLY) &&
                        (mem_op.value & 3) != 0) {
                        error(as, "DP address must be 4-byte aligned in 32-bit mode (use R0-R63)");
                        return 0;
                    }
                    switch (mem_op.mode) {
                        case AM_DP:      addr_mode = 0x00; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_DPX:     addr_mode = 0x01; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_DPY:     addr_mode = 0x02; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDX:    addr_mode = 0x03; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDY:    addr_mode = 0x04; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_IND:     addr_mode = 0x05; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDL:    addr_mode = 0x06; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDLY:   addr_mode = 0x07; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_ABS:
                        case AM_ABSX:
                        case AM_ABSY: {
                            int is_32 = mem_op.value > 0xFFFF;
                            if (mem_op.mode == AM_ABS) addr_mode = is_32 ? 0x10 : 0x08;
                            else if (mem_op.mode == AM_ABSX) addr_mode = is_32 ? 0x11 : 0x09;
                            else addr_mode = is_32 ? 0x12 : 0x0A;
                            if (is_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            int is_32 = mem_op.value > 0xFFFF;
                            if (mem_op.mode == AM_ABSIND) addr_mode = is_32 ? 0x13 : 0x0B;
                            else if (mem_op.mode == AM_ABSINDX) addr_mode = is_32 ? 0x14 : 0x0C;
                            else addr_mode = is_32 ? 0x15 : 0x0D;
                            if (is_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_SR:
                            addr_mode = 0x1C;
                            append_byte(operand_bytes, &operand_len, mem_op.value);
                            break;
                        case AM_SRIY:
                            addr_mode = 0x1D;
                            append_byte(operand_bytes, &operand_len, mem_op.value);
                            break;
                        default:
                            error(as, "unsupported extended ALU addressing mode");
                            return 0;
                    }
                    if (!parse_ext_alu_dest(as, src_str, &target, &dest_dp)) {
                        return 0;
                    }
                    mem_dest_case = 1;
                }

                if (mem_dest_case) {
                    /* Memory destination path handled above */
                } else {
                if (!parse_ext_alu_dest(as, dest_str, &target, &dest_dp)) {
                    return 0;
                }

                char *src_p = skip_whitespace(src_str);
                if ((*src_p == 'A' || *src_p == 'a') && (!src_p[1] || isspace((unsigned char)src_p[1]) || src_p[1] == ';')) {
                    addr_mode = 0x19;
                } else if ((*src_p == 'X' || *src_p == 'x') && (!src_p[1] || isspace((unsigned char)src_p[1]) || src_p[1] == ';')) {
                    addr_mode = 0x1A;
                } else if ((*src_p == 'Y' || *src_p == 'y') && (!src_p[1] || isspace((unsigned char)src_p[1]) || src_p[1] == ';')) {
                    addr_mode = 0x1B;
                } else {
                    Operand src_op;
                    if (!parse_operand(as, src_str, &src_op)) {
                        return 0;
                    }
                    if (as->m_flag == 2 && src_op.value > 0xFFFF && src_op.value <= 0xFFFFFF) {
                        error(as, "32-bit addresses must use 8 hex digits");
                        return 0;
                    }
                    if (as->m_flag == 2 &&
                        (src_op.mode == AM_ABS || src_op.mode == AM_ABSX || src_op.mode == AM_ABSY ||
                         src_op.mode == AM_ABSIND || src_op.mode == AM_ABSINDX || src_op.mode == AM_ABSLIND) &&
                        src_op.value <= 0xFFFF && !src_op.b_relative) {
                        error(as, "use B+$XXXX for 16-bit absolute in 32-bit mode");
                        return 0;
                    }
                    /* DP addresses must be 4-byte aligned in 32-bit mode */
                    if (as->m_flag == 2 &&
                        (src_op.mode == AM_DP || src_op.mode == AM_DPX || src_op.mode == AM_DPY ||
                         src_op.mode == AM_IND || src_op.mode == AM_INDX || src_op.mode == AM_INDY ||
                         src_op.mode == AM_INDL || src_op.mode == AM_INDLY) &&
                        (src_op.value & 3) != 0) {
                        error(as, "DP address must be 4-byte aligned in 32-bit mode (use R0-R63)");
                        return 0;
                    }
                    switch (src_op.mode) {
                        case AM_DP:      addr_mode = 0x00; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_DPX:     addr_mode = 0x01; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_DPY:     addr_mode = 0x02; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_INDX:    addr_mode = 0x03; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_INDY:    addr_mode = 0x04; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_IND:     addr_mode = 0x05; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_INDL:    addr_mode = 0x06; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_INDLY:   addr_mode = 0x07; append_byte(operand_bytes, &operand_len, src_op.value); break;
                        case AM_ABS:
                        case AM_ABSX:
                        case AM_ABSY: {
                            int is_32 = src_op.value > 0xFFFF;
                            if (src_op.mode == AM_ABS) addr_mode = is_32 ? 0x10 : 0x08;
                            else if (src_op.mode == AM_ABSX) addr_mode = is_32 ? 0x11 : 0x09;
                            else addr_mode = is_32 ? 0x12 : 0x0A;
                            if (is_32) append_quad(operand_bytes, &operand_len, src_op.value);
                            else append_word(operand_bytes, &operand_len, src_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            int is_32 = src_op.value > 0xFFFF;
                            if (src_op.mode == AM_ABSIND) addr_mode = is_32 ? 0x13 : 0x0B;
                            else if (src_op.mode == AM_ABSINDX) addr_mode = is_32 ? 0x14 : 0x0C;
                            else addr_mode = is_32 ? 0x15 : 0x0D;
                            if (is_32) append_quad(operand_bytes, &operand_len, src_op.value);
                            else append_word(operand_bytes, &operand_len, src_op.value);
                            break;
                        }
                        case AM_IMM:
                            addr_mode = 0x18;
                            if (size == 0 && src_op.value > 0xFF) {
                                error(as, "immediate too large for .B");
                                return 0;
                            }
                            if (size == 1 && src_op.value > 0xFFFF) {
                                error(as, "immediate too large for .W");
                                return 0;
                            }
                            if (size == 0) append_byte(operand_bytes, &operand_len, src_op.value);
                            else if (size == 1) append_word(operand_bytes, &operand_len, src_op.value);
                            else append_quad(operand_bytes, &operand_len, src_op.value);
                            break;
                        case AM_ACC:
                            addr_mode = 0x19;
                            break;
                        case AM_SR:
                            addr_mode = 0x1C;
                            append_byte(operand_bytes, &operand_len, src_op.value);
                            break;
                        case AM_SRIY:
                            addr_mode = 0x1D;
                            append_byte(operand_bytes, &operand_len, src_op.value);
                            break;
                        default:
                            error(as, "unsupported extended ALU addressing mode");
                            return 0;
                    }
                }
                }
            } else {
                /* Unary ops / STZ */
                char *dest_str = operand;
                char *comma = strchr(dest_str, ',');
                if (comma) {
                    error(as, "unexpected source operand");
                    return 0;
                }
                if (dest_starts_reg && parse_ext_alu_dest(as, dest_str, &target, &dest_dp)) {
                    addr_mode = 0x00;
                } else if (ext_alu->allows_mem_dest) {
                    Operand mem_op;
                    if (!parse_operand(as, dest_str, &mem_op)) {
                        return 0;
                    }
                    if (as->m_flag == 2 && mem_op.value > 0xFFFF && mem_op.value <= 0xFFFFFF) {
                        error(as, "32-bit addresses must use 8 hex digits");
                        return 0;
                    }
                    if (as->m_flag == 2 &&
                        (mem_op.mode == AM_ABS || mem_op.mode == AM_ABSX || mem_op.mode == AM_ABSY ||
                         mem_op.mode == AM_ABSIND || mem_op.mode == AM_ABSINDX || mem_op.mode == AM_ABSLIND) &&
                        mem_op.value <= 0xFFFF && !mem_op.b_relative) {
                        error(as, "use B+$XXXX for 16-bit absolute in 32-bit mode");
                        return 0;
                    }
                    switch (mem_op.mode) {
                        case AM_DP:      addr_mode = 0x00; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_DPX:     addr_mode = 0x01; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_DPY:     addr_mode = 0x02; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDX:    addr_mode = 0x03; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDY:    addr_mode = 0x04; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_IND:     addr_mode = 0x05; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDL:    addr_mode = 0x06; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_INDLY:   addr_mode = 0x07; append_byte(operand_bytes, &operand_len, mem_op.value); break;
                        case AM_ABS:
                        case AM_ABSX:
                        case AM_ABSY: {
                            int is_32 = mem_op.value > 0xFFFF;
                            if (mem_op.mode == AM_ABS) addr_mode = is_32 ? 0x10 : 0x08;
                            else if (mem_op.mode == AM_ABSX) addr_mode = is_32 ? 0x11 : 0x09;
                            else addr_mode = is_32 ? 0x12 : 0x0A;
                            if (is_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            int is_32 = mem_op.value > 0xFFFF;
                            if (mem_op.mode == AM_ABSIND) addr_mode = is_32 ? 0x13 : 0x0B;
                            else if (mem_op.mode == AM_ABSINDX) addr_mode = is_32 ? 0x14 : 0x0C;
                            else addr_mode = is_32 ? 0x15 : 0x0D;
                            if (is_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_SR:
                            addr_mode = 0x1C;
                            append_byte(operand_bytes, &operand_len, mem_op.value);
                            break;
                        case AM_SRIY:
                            addr_mode = 0x1D;
                            append_byte(operand_bytes, &operand_len, mem_op.value);
                            break;
                        default:
                            error(as, "unsupported extended ALU addressing mode");
                            return 0;
                    }
                } else {
                    error(as, "extended ALU dest must be A or Rn");
                    return 0;
                }
            }

            emit_byte(as, 0x02);
            emit_byte(as, ext_alu->opcode);
            emit_byte(as, (uint8_t)((size << 6) | (target ? 0x20 : 0x00) | (addr_mode & 0x1F)));
            if (target) emit_byte(as, dest_dp);
            for (int i = 0; i < operand_len; i++) {
                emit_byte(as, operand_bytes[i]);
            }
            return 1;
        }
    }

    if (size_code >= 0) {
        error(as, "size suffix only valid for extended ALU");
        return 0;
    }

    /* Parse operand */
    if (!parse_operand(as, operand, &op)) {
        return 0;
    }

    /* Check for extended instructions first */
    const ExtInstruction *ext = find_ext_instruction(mnemonic, op.mode);
    if (ext) {
        /* Emit $02 prefix + ext opcode */
        emit_byte(as, 0x02);
        emit_byte(as, ext->ext_opcode);
        
        /* Emit operand based on mode */
        switch (ext->mode) {
            case AM_IMP:
                break;
            case AM_IMM:
                /* Special cases for 32-bit immediates */
                if (strcmp(mnemonic, "SVBR") == 0 || strcmp(mnemonic, "SB") == 0 ||
                    strcmp(mnemonic, "SD") == 0) {
                    emit_quad(as, op.value);
                } else {
                    emit_byte(as, op.value & 0xFF);
                }
                break;
            case AM_DP:
                emit_byte(as, op.value & 0xFF);
                break;
            case AM_DPX:
                emit_byte(as, op.value & 0xFF);
                break;
            case AM_ABS:
            case AM_ABSX:
                emit_word(as, op.value & 0xFFFF);
                break;
            default:
                error(as, "unsupported addressing mode for extended instruction");
                return 0;
        }
        return 1;
    }
    
    /* Look up standard instruction */
    const Instruction *inst = find_instruction(mnemonic);
    if (!inst) {
        error(as, "unknown instruction '%s'", mnemonic);
        return 0;
    }

    if (as->m_flag == 2 && strcmp(mnemonic, "WDM") == 0) {
        error(as, "$42 (WDM) is reserved in 32-bit mode");
        return 0;
    }

    /* Handle branches specially */
    if (op.mode == AM_DP || op.mode == AM_ABS) {
        if (inst->opcodes[AM_REL] != 0xFF) {
            /* Convert to relative */
            int32_t offset = (int32_t)op.value - (int32_t)(as->output.pc + 2);
            if (offset < -128 || offset > 127) {
                if (inst->opcodes[AM_RELL] != 0xFF) {
                    /* Use long branch */
                    offset = (int32_t)op.value - (int32_t)(as->output.pc + 3);
                    emit_byte(as, inst->opcodes[AM_RELL]);
                    emit_word(as, offset & 0xFFFF);
                    return 1;
                }
                if (as->pass == 2) {
                    error(as, "branch target out of range (%d bytes)", offset);
                }
            }
            emit_byte(as, inst->opcodes[AM_REL]);
            emit_byte(as, offset & 0xFF);
            return 1;
        }
        if (inst->opcodes[AM_RELL] != 0xFF && op.mode == AM_ABS) {
            /* BRL and PER use 16-bit relative */
            int32_t offset = (int32_t)op.value - (int32_t)(as->output.pc + 3);
            emit_byte(as, inst->opcodes[AM_RELL]);
            emit_word(as, offset & 0xFFFF);
            return 1;
        }
    }
    
    /* Try to optimize addressing mode */
    AddrMode mode = op.mode;
    
    /* For implied mode with no operand, try ACC or IMP */
    if (mode == AM_IMP) {
        if (inst->opcodes[AM_ACC] != 0xFF) {
            emit_byte(as, inst->opcodes[AM_ACC]);
            return 1;
        }
        if (inst->opcodes[AM_IMP] != 0xFF) {
            emit_byte(as, inst->opcodes[AM_IMP]);
            return 1;
        }
    }
    
    /* Handle MVP/MVN */
    if (mode == AM_MVP || mode == AM_MVN) {
        if (strcmp(mnemonic, "MVP") == 0) {
            emit_byte(as, 0x44);
        } else if (strcmp(mnemonic, "MVN") == 0) {
            emit_byte(as, 0x54);
        } else {
            error(as, "invalid block move instruction");
            return 0;
        }
        emit_byte(as, op.mvp_dst);
        emit_byte(as, op.value & 0xFF);
        return 1;
    }
    
    if (as->m_flag == 2) {
        if (op.value > 0xFFFF) {
            error(as, "32-bit absolute requires extended ALU");
            return 0;
        }
        if ((mode == AM_ABS || mode == AM_ABSX || mode == AM_ABSY ||
             mode == AM_ABSIND || mode == AM_ABSINDX || mode == AM_ABSLIND) &&
            op.value <= 0xFFFF && !op.b_relative) {
            error(as, "use B+$XXXX for 16-bit absolute in 32-bit mode");
            return 0;
        }
        if (mode == AM_ABSL || mode == AM_ABSLX || mode == AM_ABSLIND) {
            error(as, "24-bit long addressing not valid in 32-bit mode");
            return 0;
        }
        /* DP addresses must be 4-byte aligned in 32-bit mode (R0-R63) */
        if ((mode == AM_DP || mode == AM_DPX || mode == AM_DPY ||
             mode == AM_IND || mode == AM_INDX || mode == AM_INDY ||
             mode == AM_INDL || mode == AM_INDLY) &&
            (op.value & 3) != 0) {
            error(as, "DP address must be 4-byte aligned in 32-bit mode (use R0-R63)");
            return 0;
        }
    }
    
    /* Check if mode is valid for this instruction */
    if (inst->opcodes[mode] == 0xFF) {
        /* Try alternate modes */
        if (mode == AM_DP && inst->opcodes[AM_ABS] != 0xFF) {
            mode = AM_ABS;
        } else if (mode == AM_DPX && inst->opcodes[AM_ABSX] != 0xFF) {
            mode = AM_ABSX;
        } else if (mode == AM_DPY && inst->opcodes[AM_ABSY] != 0xFF) {
            mode = AM_ABSY;
        } else if (mode == AM_IND && inst->opcodes[AM_ABSIND] != 0xFF) {
            mode = AM_ABSIND;
        } else {
            error(as, "invalid addressing mode for '%s'", mnemonic);
            return 0;
        }
    }
    
    emit_byte(as, inst->opcodes[mode]);
    
    /* Emit operand */
    switch (mode) {
        case AM_IMP:
        case AM_ACC:
            break;
        case AM_IMM:
            {
                int size = get_imm_size(as, mnemonic, 0);
                if (size == 1) emit_byte(as, op.value & 0xFF);
                else if (size == 2) emit_word(as, op.value & 0xFFFF);
                else emit_quad(as, op.value);
            }
            break;
        case AM_DP:
        case AM_DPX:
        case AM_DPY:
        case AM_INDX:
        case AM_INDY:
        case AM_IND:
        case AM_INDL:
        case AM_INDLY:
        case AM_SR:
        case AM_SRIY:
            emit_byte(as, op.value & 0xFF);
            break;
        case AM_ABS:
        case AM_ABSX:
        case AM_ABSY:
        case AM_ABSIND:
        case AM_ABSINDX:
            emit_word(as, op.value & 0xFFFF);
            break;
        case AM_ABSL:
        case AM_ABSLX:
        case AM_ABSLIND:
            emit_long(as, op.value & 0xFFFFFF);
            break;
        case AM_REL:
            {
                int32_t offset = (int32_t)op.value - (int32_t)(as->output.pc + 1);
                if (offset < -128 || offset > 127) {
                    error(as, "branch target out of range");
                }
                emit_byte(as, offset & 0xFF);
            }
            break;
        case AM_RELL:
            {
                int32_t offset = (int32_t)op.value - (int32_t)(as->output.pc + 2);
                emit_word(as, offset & 0xFFFF);
            }
            break;
        default:
            error(as, "unhandled addressing mode");
            return 0;
    }
    
    return 1;
}

/* ========================================================================== */
/* Directive Processing                                                       */
/* ========================================================================== */

/* Forward declaration for include handling */
static int process_file(Assembler *as, const char *filename);

static int process_directive(Assembler *as, char *directive, char *operand) {
    str_upper(directive);
    
    if (strcmp(directive, ".ORG") == 0 || strcmp(directive, "ORG") == 0 ||
        strcmp(directive, "*=") == 0) {
        uint32_t value;
        const char *end;
        if (!parse_expression(as, operand, &value, &end)) {
            error(as, "invalid ORG value");
            return 0;
        }
        set_pc(as, value);
        return 1;
    }
    
    /* .ascii / .asciz - emit string (asciz adds null terminator) */
    if (strcmp(directive, ".ASCII") == 0 || strcmp(directive, ".ASCIZ") == 0 ||
        strcmp(directive, ".STRING") == 0) {
        int add_null = (strcmp(directive, ".ASCIZ") == 0 || strcmp(directive, ".STRING") == 0);
        char *p = skip_whitespace(operand);
        if (*p != '"') {
            error(as, "%s requires a quoted string", directive);
            return 0;
        }
        p++;  /* Skip opening quote */
        while (*p && *p != '"') {
            if (*p == '\\' && p[1]) {
                p++;
                switch (*p) {
                    case 'n': emit_byte(as, '\n'); break;
                    case 'r': emit_byte(as, '\r'); break;
                    case 't': emit_byte(as, '\t'); break;
                    case '0': emit_byte(as, '\0'); break;
                    case '\\': emit_byte(as, '\\'); break;
                    case '"': emit_byte(as, '"'); break;
                    default: emit_byte(as, *p); break;
                }
            } else {
                emit_byte(as, *p);
            }
            p++;
        }
        if (*p != '"') {
            error(as, "unterminated string");
            return 0;
        }
        if (add_null) {
            emit_byte(as, '\0');
        }
        return 1;
    }
    
    if (strcmp(directive, ".BYTE") == 0 || strcmp(directive, ".DB") == 0 ||
        strcmp(directive, "DB") == 0 || strcmp(directive, "DCB") == 0 ||
        strcmp(directive, ".DCB") == 0) {
        char *p = operand;
        while (*p) {
            p = skip_whitespace(p);
            if (*p == '"') {
                /* String */
                p++;
                while (*p && *p != '"') {
                    if (*p == '\\' && p[1]) {
                        p++;
                        switch (*p) {
                            case 'n': emit_byte(as, '\n'); break;
                            case 'r': emit_byte(as, '\r'); break;
                            case 't': emit_byte(as, '\t'); break;
                            case '0': emit_byte(as, '\0'); break;
                            case '\\': emit_byte(as, '\\'); break;
                            case '"': emit_byte(as, '"'); break;
                            default: emit_byte(as, *p); break;
                        }
                    } else {
                        emit_byte(as, *p);
                    }
                    p++;
                }
                if (*p == '"') {
                    p++;
                } else {
                    error(as, "unterminated string");
                    return 0;
                }
            } else if (*p && *p != ',' && *p != ';') {
                uint32_t value;
                if (!parse_expression(as, p, &value, (const char**)&p)) {
                    error(as, "invalid byte value");
                    return 0;
                }
                emit_byte(as, value & 0xFF);
            }
            p = skip_whitespace(p);
            if (*p == ',') p++;
            else if (*p == ';' || *p == '\0') break;  /* End on comment or EOL */
            else {
                error(as, "expected comma or end of line");
                return 0;
            }
        }
        return 1;
    }
    
    if (strcmp(directive, ".WORD") == 0 || strcmp(directive, ".DW") == 0 ||
        strcmp(directive, "DW") == 0 || strcmp(directive, ".DCW") == 0 ||
        strcmp(directive, "DCW") == 0) {
        char *p = operand;
        while (*p) {
            p = skip_whitespace(p);
            if (*p && *p != ',' && *p != ';') {
                uint32_t value;
                if (!parse_expression(as, p, &value, (const char**)&p)) {
                    error(as, "invalid word value");
                    return 0;
                }
                emit_word(as, value & 0xFFFF);
            }
            p = skip_whitespace(p);
            if (*p == ',') p++;
            else break;  /* End on comment, EOL, or anything else */
        }
        return 1;
    }
    
    if (strcmp(directive, ".LONG") == 0 || strcmp(directive, ".DL") == 0 ||
        strcmp(directive, ".DCL") == 0 || strcmp(directive, "DCL") == 0 ||
        strcmp(directive, ".DWORD") == 0 || strcmp(directive, ".DD") == 0) {
        /* Emit 32-bit values (4 bytes each) */
        char *p = operand;
        while (*p) {
            p = skip_whitespace(p);
            if (*p && *p != ',' && *p != ';') {
                uint32_t value;
                if (!parse_expression(as, p, &value, (const char**)&p)) {
                    error(as, "invalid 32-bit value");
                    return 0;
                }
                emit_quad(as, value);  /* Full 32-bit value */
            }
            p = skip_whitespace(p);
            if (*p == ',') p++;
            else break;  /* End on comment, EOL, or anything else */
        }
        return 1;
    }
    
    if (strcmp(directive, ".DWORD") == 0 || strcmp(directive, ".DD") == 0 ||
        strcmp(directive, ".DCD") == 0 || strcmp(directive, "DCD") == 0 ||
        strcmp(directive, ".QUAD") == 0) {
        char *p = operand;
        while (*p) {
            p = skip_whitespace(p);
            if (*p && *p != ',' && *p != ';') {
                uint32_t value;
                if (!parse_expression(as, p, &value, (const char**)&p)) {
                    error(as, "invalid dword value");
                    return 0;
                }
                emit_quad(as, value);
            }
            p = skip_whitespace(p);
            if (*p == ',') p++;
            else break;  /* End on comment, EOL, or anything else */
        }
        return 1;
    }
    
    if (strcmp(directive, ".EQU") == 0 || strcmp(directive, "EQU") == 0 ||
        strcmp(directive, ".SET") == 0 || strcmp(directive, "=") == 0) {
        /* Need label from before the directive */
        error(as, "EQU requires a label");
        return 0;
    }
    
    if (strcmp(directive, ".ALIGN") == 0 || strcmp(directive, "ALIGN") == 0) {
        uint32_t align;
        const char *end;
        if (!parse_expression(as, operand, &align, &end)) {
            error(as, "invalid alignment value");
            return 0;
        }
        if (align == 0) align = 1;
        while (get_pc(as) % align)
            emit_byte(as, 0x00);
        return 1;
    }
    
    if (strcmp(directive, ".DS") == 0 || strcmp(directive, "DS") == 0 ||
        strcmp(directive, ".RES") == 0 || strcmp(directive, ".SPACE") == 0 ||
        strcmp(directive, ".ZERO") == 0) {
        uint32_t count;
        const char *end;
        if (!parse_expression(as, operand, &count, &end)) {
            error(as, "invalid space count");
            return 0;
        }
        for (uint32_t i = 0; i < count; i++)
            emit_byte(as, 0x00);
        return 1;
    }
    
    if (strcmp(directive, ".M8") == 0 || strcmp(directive, ".A8") == 0) {
        as->m_flag = 0;
        return 1;
    }
    if (strcmp(directive, ".M16") == 0 || strcmp(directive, ".A16") == 0) {
        as->m_flag = 1;
        return 1;
    }
    if (strcmp(directive, ".M32") == 0 || strcmp(directive, ".A32") == 0) {
        as->m_flag = 2;
        return 1;
    }
    if (strcmp(directive, ".X8") == 0 || strcmp(directive, ".I8") == 0) {
        as->x_flag = 0;
        return 1;
    }
    if (strcmp(directive, ".X16") == 0 || strcmp(directive, ".I16") == 0) {
        as->x_flag = 1;
        return 1;
    }
    if (strcmp(directive, ".X32") == 0 || strcmp(directive, ".I32") == 0) {
        as->x_flag = 2;
        return 1;
    }
    
    /* Section directives */
    if (strcmp(directive, ".TEXT") == 0 || strcmp(directive, ".CODE") == 0) {
        switch_section(as, "TEXT");
        return 1;
    }
    if (strcmp(directive, ".DATA") == 0) {
        switch_section(as, "DATA");
        return 1;
    }
    if (strcmp(directive, ".BSS") == 0) {
        switch_section(as, "BSS");
        return 1;
    }
    if (strcmp(directive, ".RODATA") == 0) {
        switch_section(as, "RODATA");
        return 1;
    }
    if (strcmp(directive, ".SECTION") == 0 || strcmp(directive, "SECTION") == 0) {
        char *p = skip_whitespace(operand);
        char name[MAX_LABEL];
        int i = 0;
        
        /* Parse section name - may have leading dot or not */
        while (*p && !isspace((unsigned char)*p) && *p != ',' && i < MAX_LABEL - 1)
            name[i++] = *p++;
        name[i] = '\0';
        if (name[0] == '\0') {
            error(as, ".SECTION requires a name");
            return 0;
        }
        
        /* Skip any ELF section flags like ,"ax",@progbits */
        /* We just ignore these for now since we output flat binary */
        
        /* Map common ELF section names to our internal names */
        if (strcmp(name, ".text") == 0 || strcmp(name, ".TEXT") == 0) {
            switch_section(as, "TEXT");
        } else if (strcmp(name, ".data") == 0 || strcmp(name, ".DATA") == 0) {
            switch_section(as, "DATA");
        } else if (strcmp(name, ".bss") == 0 || strcmp(name, ".BSS") == 0) {
            switch_section(as, "BSS");
        } else if (strcmp(name, ".rodata") == 0 || strcmp(name, ".RODATA") == 0) {
            switch_section(as, "RODATA");
        } else {
            /* Use the name as-is (strip leading dot if present) */
            char *sect_name = name;
            if (sect_name[0] == '.')
                sect_name++;
            switch_section(as, sect_name);
        }
        return 1;
    }
    
    if (strcmp(directive, ".END") == 0 || strcmp(directive, "END") == 0) {
        return 1;  /* End of file */
    }
    
    /* Include file */
    /* =========================================================================
     * ELF/LLVM compatibility directives
     * ========================================================================= */
    
    /* .globl / .global - mark symbol as global (for ELF output) */
    if (strcmp(directive, ".GLOBL") == 0 || strcmp(directive, ".GLOBAL") == 0) {
        /* Currently just accept and ignore - could track for ELF output */
        /* The symbol name follows, but we don't need to do anything with it */
        return 1;
    }
    
    /* .file - source filename (debug info) */
    if (strcmp(directive, ".FILE") == 0) {
        /* Just ignore - this is debug metadata */
        return 1;
    }
    
    /* .type - symbol type (e.g., @function, @object) */
    if (strcmp(directive, ".TYPE") == 0) {
        /* Just ignore - this is ELF metadata */
        return 1;
    }
    
    /* .size - symbol size */
    if (strcmp(directive, ".SIZE") == 0) {
        /* Just ignore - this is ELF metadata */
        return 1;
    }
    
    /* .p2align - power-of-2 alignment (GNU as style) */
    if (strcmp(directive, ".P2ALIGN") == 0) {
        uint32_t power;
        const char *end;
        char *p = skip_whitespace(operand);
        if (!parse_expression(as, p, &power, &end)) {
            error(as, "invalid alignment power");
            return 0;
        }
        if (power > 16) {
            error(as, "alignment power too large (max 16)");
            return 0;
        }
        uint32_t align = 1U << power;  /* Convert power-of-2 to bytes */
        uint32_t pc = get_pc(as);
        uint32_t pad = (align - (pc & (align - 1))) & (align - 1);
        for (uint32_t i = 0; i < pad; i++) {
            emit_byte(as, 0x00);
        }
        return 1;
    }
    
    /* .ident - identification string (compiler version etc) */
    if (strcmp(directive, ".IDENT") == 0) {
        /* Just ignore - this is debug metadata */
        return 1;
    }
    
    /* .cfi_startproc - Start of a function's CFI information */
    if (strcmp(directive, ".CFI_STARTPROC") == 0) {
        if (as->cfi_in_proc) {
            error(as, ".cfi_startproc without matching .cfi_endproc");
            return 0;
        }
        as->cfi_in_proc = 1;
        /* Reset CFI state */
        as->cfi_state.cfa_reg = 67;  /* Default CFA is SP (register 67) */
        as->cfi_state.cfa_offset = 0;
        for (int i = 0; i < MAX_CFI_SAVED_REGS; i++) {
            as->cfi_state.reg_offsets[i] = INT_MIN;  /* Not saved */
        }
        as->cfi_stack_depth = 0;
        return 1;
    }
    
    /* .cfi_endproc - End of a function's CFI information */
    if (strcmp(directive, ".CFI_ENDPROC") == 0) {
        if (!as->cfi_in_proc) {
            error(as, ".cfi_endproc without matching .cfi_startproc");
            return 0;
        }
        as->cfi_in_proc = 0;
        return 1;
    }
    
    /* .cfi_def_cfa <reg>, <offset> - Define CFA as register + offset */
    if (strcmp(directive, ".CFI_DEF_CFA") == 0) {
        char *p = skip_whitespace(operand);
        uint32_t reg, offset;
        const char *end;
        if (!parse_expression(as, p, &reg, &end)) {
            error(as, "invalid register in .cfi_def_cfa");
            return 0;
        }
        p = skip_whitespace((char*)end);
        if (*p == ',') p++;
        p = skip_whitespace(p);
        if (!parse_expression(as, p, &offset, &end)) {
            error(as, "invalid offset in .cfi_def_cfa");
            return 0;
        }
        as->cfi_state.cfa_reg = (int)reg;
        as->cfi_state.cfa_offset = (int)offset;
        return 1;
    }
    
    /* .cfi_def_cfa_register <reg> - Change CFA register */
    if (strcmp(directive, ".CFI_DEF_CFA_REGISTER") == 0) {
        uint32_t reg;
        const char *end;
        if (!parse_expression(as, operand, &reg, &end)) {
            error(as, "invalid register in .cfi_def_cfa_register");
            return 0;
        }
        as->cfi_state.cfa_reg = (int)reg;
        return 1;
    }
    
    /* .cfi_def_cfa_offset <offset> - Change CFA offset */
    if (strcmp(directive, ".CFI_DEF_CFA_OFFSET") == 0) {
        uint32_t offset;
        const char *end;
        if (!parse_expression(as, operand, &offset, &end)) {
            error(as, "invalid offset in .cfi_def_cfa_offset");
            return 0;
        }
        as->cfi_state.cfa_offset = (int)offset;
        return 1;
    }
    
    /* .cfi_adjust_cfa_offset <offset> - Adjust CFA offset */
    if (strcmp(directive, ".CFI_ADJUST_CFA_OFFSET") == 0) {
        int32_t offset;
        const char *end;
        uint32_t uval;
        char *p = skip_whitespace(operand);
        int neg = 0;
        if (*p == '-') {
            neg = 1;
            p++;
        }
        if (!parse_expression(as, p, &uval, &end)) {
            error(as, "invalid offset in .cfi_adjust_cfa_offset");
            return 0;
        }
        offset = neg ? -(int32_t)uval : (int32_t)uval;
        as->cfi_state.cfa_offset += offset;
        return 1;
    }
    
    /* .cfi_offset <reg>, <offset> - Register saved at CFA + offset */
    if (strcmp(directive, ".CFI_OFFSET") == 0) {
        char *p = skip_whitespace(operand);
        uint32_t reg;
        int32_t offset;
        const char *end;
        if (!parse_expression(as, p, &reg, &end)) {
            error(as, "invalid register in .cfi_offset");
            return 0;
        }
        p = skip_whitespace((char*)end);
        if (*p == ',') p++;
        p = skip_whitespace(p);
        int neg = 0;
        if (*p == '-') {
            neg = 1;
            p++;
        }
        uint32_t uval;
        if (!parse_expression(as, p, &uval, &end)) {
            error(as, "invalid offset in .cfi_offset");
            return 0;
        }
        offset = neg ? -(int32_t)uval : (int32_t)uval;
        if (reg < MAX_CFI_SAVED_REGS) {
            as->cfi_state.reg_offsets[reg] = offset;
        }
        return 1;
    }
    
    /* .cfi_restore <reg> - Register restored */
    if (strcmp(directive, ".CFI_RESTORE") == 0) {
        uint32_t reg;
        const char *end;
        if (!parse_expression(as, operand, &reg, &end)) {
            error(as, "invalid register in .cfi_restore");
            return 0;
        }
        if (reg < MAX_CFI_SAVED_REGS) {
            as->cfi_state.reg_offsets[reg] = INT_MIN;  /* Mark as not saved */
        }
        return 1;
    }
    
    /* .cfi_remember_state - Push CFI state */
    if (strcmp(directive, ".CFI_REMEMBER_STATE") == 0) {
        if (as->cfi_stack_depth >= MAX_CFI_STACK) {
            error(as, "CFI state stack overflow");
            return 0;
        }
        as->cfi_stack[as->cfi_stack_depth++] = as->cfi_state;
        return 1;
    }
    
    /* .cfi_restore_state - Pop CFI state */
    if (strcmp(directive, ".CFI_RESTORE_STATE") == 0) {
        if (as->cfi_stack_depth <= 0) {
            error(as, "CFI state stack underflow");
            return 0;
        }
        as->cfi_state = as->cfi_stack[--as->cfi_stack_depth];
        return 1;
    }
    
    /* .cfi_undefined <reg> - Register has undefined value */
    if (strcmp(directive, ".CFI_UNDEFINED") == 0) {
        /* Just accept, we don't track this specially */
        return 1;
    }
    
    /* .cfi_same_value <reg> - Register has same value as in caller */
    if (strcmp(directive, ".CFI_SAME_VALUE") == 0) {
        /* Just accept, equivalent to not being saved */
        return 1;
    }
    
    /* .cfi_escape <bytes...> - Raw CFI bytes */
    if (strcmp(directive, ".CFI_ESCAPE") == 0) {
        /* Just accept - we'd need to emit these in DWARF output */
        return 1;
    }
    
    /* .cfi_signal_frame - Mark as signal frame */
    if (strcmp(directive, ".CFI_SIGNAL_FRAME") == 0) {
        /* Just accept */
        return 1;
    }
    
    /* .cfi_return_column <reg> - Set return address column */
    if (strcmp(directive, ".CFI_RETURN_COLUMN") == 0) {
        /* Just accept */
        return 1;
    }
    
    /* .cfi_personality - Personality routine (C++ exceptions) */
    if (strcmp(directive, ".CFI_PERSONALITY") == 0) {
        /* Just accept */
        return 1;
    }
    
    /* .cfi_lsda - Language-specific data area */
    if (strcmp(directive, ".CFI_LSDA") == 0) {
        /* Just accept */
        return 1;
    }
    
    /* Catch any other .cfi_* directives */
    if (strncmp(directive, ".CFI_", 5) == 0) {
        /* Accept unknown CFI directives with a warning in verbose mode */
        if (as->verbose) {
            warning(as, "unrecognized CFI directive '%s' ignored", directive);
        }
        return 1;
    }
    
    /* .addrsig / .addrsig_sym - address-significance directives */
    if (strcmp(directive, ".ADDRSIG") == 0 || strcmp(directive, ".ADDRSIG_SYM") == 0) {
        /* Just ignore */
        return 1;
    }
    
    /* =========================================================================
     * Include file
     * ========================================================================= */
    
    if (strcmp(directive, ".INCLUDE") == 0 || strcmp(directive, "INCLUDE") == 0 ||
        strcmp(directive, ".INC") == 0) {
        char *p = skip_whitespace(operand);
        char filename[MAX_PATH];
        int i = 0;
        
        /* Parse filename - may be quoted */
        if (*p == '"' || *p == '<') {
            char close = (*p == '"') ? '"' : '>';
            p++;
            while (*p && *p != close && i < MAX_PATH - 1)
                filename[i++] = *p++;
        } else {
            while (*p && !isspace((unsigned char)*p) && i < MAX_PATH - 1)
                filename[i++] = *p++;
        }
        filename[i] = '\0';
        
        if (filename[0] == '\0') {
            error(as, ".INCLUDE requires a filename");
            return 0;
        }
        
        /* Check include depth */
        if (as->file_depth >= MAX_INCLUDE_DEPTH) {
            error(as, "include nesting too deep (max %d)", MAX_INCLUDE_DEPTH);
            return 0;
        }
        
        /* Try to find the file */
        char fullpath[MAX_PATH];
        FILE *f = NULL;
        
        /* First try relative to current file's directory */
        if (as->file_depth > 0) {
            char dir[MAX_PATH];
            get_directory(as->file_stack[as->file_depth - 1].filename, dir, sizeof(dir));
            snprintf(fullpath, sizeof(fullpath), "%s/%s", dir, filename);
            f = fopen(fullpath, "r");
        }
        
        /* Then try include paths */
        if (!f) {
            for (int j = 0; j < as->num_include_paths && !f; j++) {
                snprintf(fullpath, sizeof(fullpath), "%s/%s", as->include_paths[j], filename);
                f = fopen(fullpath, "r");
            }
        }
        
        /* Finally try as-is */
        if (!f) {
            strncpy(fullpath, filename, sizeof(fullpath) - 1);
            f = fopen(fullpath, "r");
        }
        
        if (!f) {
            error(as, "cannot open include file '%s'", filename);
            return 0;
        }
        fclose(f);
        
        /* Process the included file */
        return process_file(as, fullpath);
    }
    
    error(as, "unknown directive '%s'", directive);
    return 0;
}

/* ========================================================================== */
/* Line Processing                                                            */
/* ========================================================================== */

/* Check if a word is a known mnemonic */
static int is_mnemonic(const char *word) {
    char upper[32];
    int i;
    for (i = 0; word[i] && i < 31; i++)
        upper[i] = toupper((unsigned char)word[i]);
    upper[i] = '\0';
    
    /* Check standard instructions */
    if (find_instruction(upper))
        return 1;
    
    /* Check extended instructions */
    for (i = 0; ext_instructions[i].name; i++) {
        if (strcmp(ext_instructions[i].name, upper) == 0)
            return 1;
    }
    
    return 0;
}

static int process_line(Assembler *as, char *line) {
    char *p = line;
    char label[MAX_LABEL] = {0};
    char mnemonic[32] = {0};
    char *operand = NULL;
    int had_leading_whitespace;
    
    /* Check for leading whitespace */
    had_leading_whitespace = isspace((unsigned char)*p);
    
    /* Skip leading whitespace */
    p = skip_whitespace(p);
    
    /* Skip empty lines and comments */
    if (!*p || *p == ';' || (*p == '*' && p[1] == '\0')) {
        return 1;
    }
    
    /* Check for local labels (.Lxxx:) first - these are LLVM-style local labels */
    if (*p == '.' && p[1] == 'L') {
        /* Check if this is a local label (has colon after the name) */
        char *wp = p;
        int i = 0;
        char first_word[MAX_LABEL];
        wp++;  /* Skip the dot */
        first_word[i++] = '.';
        while (is_label_char(*wp) && i < MAX_LABEL - 1)
            first_word[i++] = *wp++;
        first_word[i] = '\0';
        
        if (*wp == ':') {
            /* This is a local label like .Lfunc_end0: */
            strcpy(label, first_word);
            p = wp + 1;
            p = skip_whitespace(p);
            
            /* Handle label-only lines */
            if (!*p || *p == ';') {
                /* Don't uppercase local labels - preserve case */
                add_symbol(as, label, get_pc(as), 1);
                return 1;
            }
        }
    }
    
    /* Check for label - only if:
     * 1. Line starts with a word (letter/underscore, NOT a dot)
     * 2. AND either:
     *    a. Word is followed by ':', OR
     *    b. Word is followed by EQU or =, OR
     *    c. Word is NOT a known mnemonic (and no leading whitespace)
     */
    if (*p != '.' && is_label_char(*p) && !isdigit((unsigned char)*p)) {
        /* Peek at the first word */
        char first_word[MAX_LABEL];
        char *wp = p;
        int i = 0;
        while (is_label_char(*wp) && i < MAX_LABEL - 1)
            first_word[i++] = *wp++;
        first_word[i] = '\0';
        
        /* Check if label was truncated (more chars follow) */
        if (is_label_char(*wp)) {
            error(as, "label too long (max %d characters)", MAX_LABEL - 1);
            return 0;
        }
        
        /* Check what follows */
        char *after_word = wp;
        if (*after_word == ':') {
            /* Explicit label with colon */
            strcpy(label, first_word);
            p = after_word + 1;
            p = skip_whitespace(p);
        } else {
            /* Skip whitespace after word */
            char *next = skip_whitespace(after_word);
            
            /* Check for EQU or = */
            if (*next == '=' || 
                (strncasecmp(next, "EQU", 3) == 0 && !is_label_char(next[3])) ||
                (strncasecmp(next, ".EQU", 4) == 0 && !is_label_char(next[4]))) {
                /* This is an equate */
                strcpy(label, first_word);
                p = next;
            } else if (!had_leading_whitespace && !is_mnemonic(first_word)) {
                /* No leading whitespace and not a mnemonic = label */
                strcpy(label, first_word);
                p = skip_whitespace(after_word);
            }
            /* Otherwise, first_word is the mnemonic, not a label */
        }
    }
    
    /* Handle label-only lines */
    if (!*p || *p == ';') {
        if (label[0]) {
            str_upper(label);
            add_symbol(as, label, get_pc(as), 1);
        }
        return 1;
    }
    
    /* Check for directive or instruction */
    if (*p == '.' || (*p == '*' && p[1] == '=')) {
        /* Directive */
        char directive[32];
        int i = 0;
        
        if (*p == '*' && p[1] == '=') {
            strcpy(directive, "*=");
            p += 2;
        } else {
            while (*p && !isspace((unsigned char)*p) && i < 31)
                directive[i++] = *p++;
            directive[i] = '\0';
        }
        
        p = skip_whitespace(p);
        str_upper(directive);
        
        /* Handle label = value */
        if (label[0] && (strcmp(directive, ".EQU") == 0 || 
                        strcmp(directive, "EQU") == 0 ||
                        strcmp(directive, ".SET") == 0)) {
            uint32_t value;
            const char *end;
            if (!parse_expression(as, p, &value, &end)) {
                error(as, "invalid EQU value");
                return 0;
            }
            str_upper(label);
            add_symbol(as, label, value, 1);
            return 1;
        }
        
        /* Define label at current PC */
        if (label[0]) {
            str_upper(label);
            add_symbol(as, label, get_pc(as), 1);
        }
        
        return process_directive(as, directive, p);
    }
    
    /* Check for = equate (label = value) */
    if (*p == '=') {
        if (!label[0]) {
            error(as, "'=' requires a label");
            return 0;
        }
        p++;
        p = skip_whitespace(p);
        uint32_t value;
        const char *end;
        if (!parse_expression(as, p, &value, &end)) {
            error(as, "invalid value");
            return 0;
        }
        str_upper(label);
        add_symbol(as, label, value, 1);
        return 1;
    }
    
    /* Check for EQU without dot prefix */
    if (strncasecmp(p, "EQU", 3) == 0 && (isspace((unsigned char)p[3]) || p[3] == '\0')) {
        if (!label[0]) {
            error(as, "EQU requires a label");
            return 0;
        }
        p += 3;
        p = skip_whitespace(p);
        uint32_t value;
        const char *end;
        if (!parse_expression(as, p, &value, &end)) {
            error(as, "invalid EQU value");
            return 0;
        }
        str_upper(label);
        add_symbol(as, label, value, 1);
        return 1;
    }
    
    /* Must be an instruction */
    if (label[0]) {
        str_upper(label);
        add_symbol(as, label, get_pc(as), 1);
    }
    
    /* Get mnemonic */
    {
        int i = 0;
        while (*p && !isspace((unsigned char)*p) && i < 31)
            mnemonic[i++] = *p++;
        mnemonic[i] = '\0';
    }
    
    p = skip_whitespace(p);
    operand = p;
    
    /* Remove trailing comment */
    {
        char *comment = strchr(operand, ';');
        if (comment) {
            *comment = '\0';
            /* Trim trailing whitespace */
            comment--;
            while (comment >= operand && isspace((unsigned char)*comment))
                *comment-- = '\0';
        }
    }
    
    return assemble_instruction(as, mnemonic, operand);
}

/* ========================================================================== */
/* Output Writers                                                             */
/* ========================================================================== */

static int write_binary(Assembler *as, const char *filename) {
    FILE *f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s' for writing\n", filename);
        return 0;
    }
    fwrite(as->output.data, 1, as->output.size, f);
    fclose(f);
    return 1;
}

static int write_hex(Assembler *as, const char *filename) {
    FILE *f = fopen(filename, "w");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s' for writing\n", filename);
        return 0;
    }
    
    uint32_t addr = as->output.org;
    uint32_t remaining = as->output.size;
    uint8_t *data = as->output.data;
    
    /* Extended address record if needed */
    if (addr > 0xFFFF) {
        uint16_t ext = (addr >> 16) & 0xFFFF;
        uint8_t checksum = 2 + 0 + 4 + (ext >> 8) + (ext & 0xFF);
        checksum = (~checksum + 1) & 0xFF;
        fprintf(f, ":02000004%04X%02X\n", ext, checksum);
    }
    
    while (remaining > 0) {
        uint32_t count = remaining > 16 ? 16 : remaining;
        uint16_t addr16 = addr & 0xFFFF;
        uint8_t checksum = count + (addr16 >> 8) + (addr16 & 0xFF) + 0;
        
        fprintf(f, ":%02X%04X00", (unsigned)count, addr16);
        for (uint32_t i = 0; i < count; i++) {
            fprintf(f, "%02X", data[i]);
            checksum += data[i];
        }
        checksum = (~checksum + 1) & 0xFF;
        fprintf(f, "%02X\n", checksum);
        
        addr += count;
        data += count;
        remaining -= count;
    }
    
    /* End record */
    fprintf(f, ":00000001FF\n");
    fclose(f);
    return 1;
}

/* ========================================================================== */
/* Main Assembler                                                             */
/* ========================================================================== */

/* Process a single file (can be called recursively for includes) */
static int process_file(Assembler *as, const char *filename) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        error(as, "cannot open '%s'", filename);
        return 0;
    }
    
    /* Push file onto stack */
    if (as->file_depth >= MAX_INCLUDE_DEPTH) {
        fclose(f);
        error(as, "include nesting too deep");
        return 0;
    }
    strncpy(as->file_stack[as->file_depth].filename, filename, MAX_PATH - 1);
    as->file_stack[as->file_depth].filename[MAX_PATH - 1] = '\0';
    as->file_stack[as->file_depth].line_num = 0;
    as->file_depth++;
    
    char line[MAX_LINE];
    
    while (fgets(line, sizeof(line), f)) {
        as->file_stack[as->file_depth - 1].line_num++;
        
        /* Remove newline */
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') line[--len] = '\0';
        if (len > 0 && line[len-1] == '\r') line[--len] = '\0';
        
        process_line(as, line);
    }
    
    /* Pop file from stack */
    as->file_depth--;
    
    fclose(f);
    return 1;
}

/* Reset section PCs for a new pass */
static void reset_sections(Assembler *as) {
    for (int i = 0; i < as->num_sections; i++) {
        as->sections[i].pc = as->sections[i].org;
        as->sections[i].size = 0;
    }
    as->output.pc = as->output.org;
}

/* Link sections: place sections without explicit .org after TEXT */
static void link_sections(Assembler *as) {
    /* Find TEXT section and its end address */
    Section *text = find_section(as, "TEXT");
    if (!text) return;
    
    /* Store old org values for symbol adjustment */
    uint32_t old_orgs[MAX_SECTIONS];
    for (int i = 0; i < as->num_sections; i++) {
        old_orgs[i] = as->sections[i].org;
    }
    
    uint32_t next_addr = text->org + text->size;
    
    /* Align to 4-byte boundary */
    next_addr = (next_addr + 3) & ~3;
    
    /* Link order: RODATA, DATA, BSS, then any others */
    const char *link_order[] = { "RODATA", "DATA", "BSS", NULL };
    
    for (int i = 0; link_order[i]; i++) {
        Section *sec = find_section(as, link_order[i]);
        if (sec && !sec->org_set && sec->size > 0) {
            sec->org = next_addr;
            next_addr += sec->size;
            next_addr = (next_addr + 3) & ~3;  /* Align */
        }
    }
    
    /* Link any remaining sections */
    for (int i = 0; i < as->num_sections; i++) {
        Section *sec = &as->sections[i];
        if (!sec->org_set && sec->size > 0 &&
            strcmp(sec->name, "TEXT") != 0 &&
            strcmp(sec->name, "RODATA") != 0 &&
            strcmp(sec->name, "DATA") != 0 &&
            strcmp(sec->name, "BSS") != 0) {
            sec->org = next_addr;
            next_addr += sec->size;
            next_addr = (next_addr + 3) & ~3;
        }
    }
    
    /* Adjust symbol values for relocated sections */
    for (int i = 0; i < as->num_symbols; i++) {
        Symbol *sym = &as->symbols[i];
        if (sym->defined && sym->section_index >= 0 && sym->section_index < as->num_sections) {
            Section *sec = &as->sections[sym->section_index];
            uint32_t old_org = old_orgs[sym->section_index];
            if (sec->org != old_org) {
                /* Adjust symbol by the section relocation delta */
                sym->value = sym->value - old_org + sec->org;
            }
        }
    }
}

static int assemble_file(Assembler *as, const char *filename) {
    /* Initialize default section if none exist */
    if (as->num_sections == 0) {
        if (!get_or_create_section(as, "TEXT")) {
            fprintf(stderr, "error: cannot create default section\n");
            return 0;
        }
        as->current_section = 0;
    }
    
    /* Pass 1: collect symbols and determine section sizes */
    as->pass = 1;
    as->file_depth = 0;
    reset_sections(as);
    
    if (!process_file(as, filename)) {
        return 0;
    }
    
    /* Link sections: place DATA/BSS/etc after TEXT */
    link_sections(as);
    
    /* Pass 2: generate code with final addresses */
    as->pass = 2;
    as->file_depth = 0;
    reset_sections(as);
    
    if (!process_file(as, filename)) {
        return 0;
    }
    
    return as->errors == 0;
}

static void print_usage(const char *prog) {
    fprintf(stderr, "M65832 Assembler v%s\n", VERSION);
    fprintf(stderr, "Usage: %s [options] input.asm\n\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -o FILE      Output file (default: a.out)\n");
    fprintf(stderr, "  -m FILE      Output symbol map file (for debugger)\n");
    fprintf(stderr, "  -I PATH      Add include search path\n");
    fprintf(stderr, "  -h, --hex    Output Intel HEX format\n");
    fprintf(stderr, "  -l           List symbols after assembly\n");
    fprintf(stderr, "  -v           Verbose output\n");
    fprintf(stderr, "  --help       Show this help\n");
}

static void cleanup_assembler(Assembler *as) {
    output_free(&as->output);
    for (int i = 0; i < as->num_sections; i++) {
        section_free(&as->sections[i]);
    }
}

/* Write symbol map file for debugger support */
static int write_map_file(Assembler *as, const char *filename) {
    FILE *f = fopen(filename, "w");
    if (!f) {
        fprintf(stderr, "error: cannot create map file '%s'\n", filename);
        return 0;
    }
    
    fprintf(f, "# M65832 Symbol Map\n");
    fprintf(f, "# Generated by m65832as\n");
    fprintf(f, "# Format: ADDRESS TYPE NAME\n");
    fprintf(f, "#   TYPE: L=label, C=constant, S=section\n\n");
    
    /* Output sections first */
    for (int i = 0; i < as->num_sections; i++) {
        fprintf(f, "%08X S %s\n", as->sections[i].org, as->sections[i].name);
    }
    
    /* Output symbols sorted by address */
    /* Simple approach: just output in order, debugger can sort */
    for (int i = 0; i < as->num_symbols; i++) {
        if (as->symbols[i].defined) {
            char type = 'L';  /* Label by default */
            /* Could distinguish constants vs labels here if tracked */
            fprintf(f, "%08X %c %s\n", as->symbols[i].value, type, as->symbols[i].name);
        }
    }
    
    fclose(f);
    return 1;
}

int main(int argc, char **argv) {
    Assembler as = {0};
    const char *input_file = NULL;
    const char *output_file = "a.out";
    const char *map_file = NULL;
    int list_symbols = 0;
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_file = argv[++i];
        } else if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            map_file = argv[++i];
        } else if (strcmp(argv[i], "--map") == 0 && i + 1 < argc) {
            map_file = argv[++i];
        } else if (strcmp(argv[i], "-I") == 0 && i + 1 < argc) {
            if (as.num_include_paths < MAX_INCLUDE_PATHS) {
                strncpy(as.include_paths[as.num_include_paths], argv[++i], MAX_PATH - 1);
                as.include_paths[as.num_include_paths][MAX_PATH - 1] = '\0';
                as.num_include_paths++;
            } else {
                fprintf(stderr, "warning: too many include paths\n");
                i++;
            }
        } else if (strncmp(argv[i], "-I", 2) == 0 && argv[i][2]) {
            /* -Ipath format */
            if (as.num_include_paths < MAX_INCLUDE_PATHS) {
                strncpy(as.include_paths[as.num_include_paths], &argv[i][2], MAX_PATH - 1);
                as.include_paths[as.num_include_paths][MAX_PATH - 1] = '\0';
                as.num_include_paths++;
            }
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--hex") == 0) {
            as.output_hex = 1;
        } else if (strcmp(argv[i], "-l") == 0) {
            list_symbols = 1;
        } else if (strcmp(argv[i], "-v") == 0) {
            as.verbose = 1;
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
    
    /* Initialize */
    if (!output_init(&as.output)) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }
    
    as.m_flag = 2;  /* Default to 32-bit */
    as.x_flag = 2;
    
    /* Assemble */
    int success = assemble_file(&as, input_file);
    
    if (success) {
        /* Write output */
        if (as.output_hex) {
            success = write_hex(&as, output_file);
        } else {
            success = write_binary(&as, output_file);
        }
        
        /* Write map file if requested */
        if (success && map_file) {
            if (write_map_file(&as, map_file)) {
                if (as.verbose) {
                    printf("Symbol map: %s (%d symbols)\n", map_file, as.num_symbols);
                }
            } else {
                success = 0;
            }
        }
        
        if (success && as.verbose) {
            printf("Assembled %s -> %s\n", input_file, output_file);
            printf("  Origin: $%08X\n", as.output.org);
            printf("  Size: %u bytes\n", as.output.size);
            printf("  Symbols: %d\n", as.num_symbols);
            if (as.num_sections > 0) {
                printf("  Sections:\n");
                for (int i = 0; i < as.num_sections; i++) {
                    printf("    %-12s org=$%08X size=%u\n", 
                           as.sections[i].name, as.sections[i].org, as.sections[i].size);
                }
            }
        }
    }
    
    if (list_symbols) {
        printf("\nSymbol table:\n");
        for (int i = 0; i < as.num_symbols; i++) {
            if (as.symbols[i].defined) {
                printf("  %-20s = $%08X\n", as.symbols[i].name, as.symbols[i].value);
            }
        }
    }
    
    if (as.errors > 0) {
        fprintf(stderr, "\n%d error(s), %d warning(s)\n", as.errors, as.warnings);
    } else if (as.warnings > 0) {
        fprintf(stderr, "%d warning(s)\n", as.warnings);
    }
    
    cleanup_assembler(&as);
    return as.errors > 0 ? 1 : 0;
}
