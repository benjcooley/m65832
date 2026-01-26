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
    /* WID-prefixed modes */
    AM_IMM32,       /* 32-bit Immediate: WID LDA #$xxxxxxxx */
    AM_ABS32,       /* 32-bit Absolute (legacy WID, now via ADDR32 prefix) */
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
    { "TTA",    0x86, AM_IMP  },
    { "TAT",    0x87, AM_IMP  },
    /* 64-bit load/store */
    { "LDQ",    0x88, AM_DP   },
    { "LDQ",    0x89, AM_ABS  },
    { "STQ",    0x8A, AM_DP   },
    { "STQ",    0x8B, AM_ABS  },
    /* WAI/STP extended */
    { "WAI32",  0x91, AM_IMP  },
    { "STP32",  0x92, AM_IMP  },
    /* LEA */
    { "LEA",    0xA0, AM_DP   },
    { "LEA",    0xA1, AM_DPX  },
    { "LEA",    0xA2, AM_ABS  },
    { "LEA",    0xA3, AM_ABSX },
    /* FPU Load/Store */
    { "LDF0",   0xB0, AM_DP   },
    { "LDF0",   0xB1, AM_ABS  },
    { "STF0",   0xB2, AM_DP   },
    { "STF0",   0xB3, AM_ABS  },
    { "LDF1",   0xB4, AM_DP   },
    { "LDF1",   0xB5, AM_ABS  },
    { "STF1",   0xB6, AM_DP   },
    { "STF1",   0xB7, AM_ABS  },
    { "LDF2",   0xB8, AM_DP   },
    { "LDF2",   0xB9, AM_ABS  },
    { "STF2",   0xBA, AM_DP   },
    { "STF2",   0xBB, AM_ABS  },
    /* FPU single-precision */
    { "FADD.S", 0xC0, AM_IMP  },
    { "FSUB.S", 0xC1, AM_IMP  },
    { "FMUL.S", 0xC2, AM_IMP  },
    { "FDIV.S", 0xC3, AM_IMP  },
    { "FNEG.S", 0xC4, AM_IMP  },
    { "FABS.S", 0xC5, AM_IMP  },
    { "FCMP.S", 0xC6, AM_IMP  },
    { "F2I.S",  0xC7, AM_IMP  },
    { "I2F.S",  0xC8, AM_IMP  },
    /* FPU double-precision */
    { "FADD.D", 0xD0, AM_IMP  },
    { "FSUB.D", 0xD1, AM_IMP  },
    { "FMUL.D", 0xD2, AM_IMP  },
    { "FDIV.D", 0xD3, AM_IMP  },
    { "FNEG.D", 0xD4, AM_IMP  },
    { "FABS.D", 0xD5, AM_IMP  },
    { "FCMP.D", 0xD6, AM_IMP  },
    { "F2I.D",  0xD7, AM_IMP  },
    { "I2F.D",  0xD8, AM_IMP  },
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

/* Shifter instructions ($02 $E9 prefix)
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

/* Extend instructions ($02 $EA prefix)
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
        if (defined && sym->defined && sym->value != value) {
            error(as, "symbol '%s' already defined at line %d", name, sym->line_defined);
            return NULL;
        }
        if (defined) {
            sym->value = value;
            sym->defined = 1;
            sym->line_defined = current_line(as);
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
    if (as->pass == 2) {
        Section *sec = current_section(as);
        if (sec) {
            uint32_t offset = sec->pc - sec->org;
            if (offset < sec->capacity) {
                sec->data[offset] = b;
                if (offset + 1 > sec->size)
                    sec->size = offset + 1;
            }
            sec->pc++;
        }
        /* Also write to legacy output for compatibility */
        uint32_t offset = as->output.pc - as->output.org;
        if (offset < as->output.capacity) {
            as->output.data[offset] = b;
            if (offset + 1 > as->output.size)
                as->output.size = offset + 1;
        }
    }
    as->output.pc++;
    Section *sec = current_section(as);
    if (sec && as->pass == 1) sec->pc++;
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
} Operand;

static int parse_operand(Assembler *as, char *s, Operand *op) {
    char *p = skip_whitespace(s);
    op->mode = AM_IMP;
    op->value = 0;
    op->force_width = 0;
    op->mvp_dst = 0;
    
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
        if (!parse_expression(as, p, &op->value, (const char**)&p)) {
            error(as, "invalid indirect address");
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

static int is_prefix_mnemonic(const char *mnemonic) {
    return strcmp(mnemonic, "BYTE") == 0 ||
           strcmp(mnemonic, "WORD") == 0 ||
           strcmp(mnemonic, "ADDR32") == 0 ||
           strcmp(mnemonic, "WID.B") == 0 ||
           strcmp(mnemonic, "WID.W") == 0 ||
           strcmp(mnemonic, "WID.A32") == 0;
}

static int assemble_instruction(Assembler *as, char *mnemonic, char *operand) {
    Operand op;
    uint8_t prefix_bytes[8];
    int prefix_count = 0;
    int data_override = 0; /* 0=default, 1=byte, 2=word */
    int addr32_prefix = 0;
    int saw_data_prefix = 0;
    int saw_addr_prefix = 0;
    
    str_upper(mnemonic);
    
    /* Parse one-shot prefixes (32-bit mode only) */
    while (is_prefix_mnemonic(mnemonic)) {
        if (as->m_flag != 2) {
            error(as, "prefixes only valid in 32-bit mode");
            return 0;
        }
        if (strcmp(mnemonic, "BYTE") == 0 || strcmp(mnemonic, "WID.B") == 0) {
            if (saw_data_prefix || saw_addr_prefix) {
                error(as, "DATA prefix must appear once, before ADDR32");
                return 0;
            }
            data_override = 1;
            prefix_bytes[prefix_count++] = 0xCB;
            saw_data_prefix = 1;
        } else if (strcmp(mnemonic, "WORD") == 0 || strcmp(mnemonic, "WID.W") == 0) {
            if (saw_data_prefix || saw_addr_prefix) {
                error(as, "DATA prefix must appear once, before ADDR32");
                return 0;
            }
            data_override = 2;
            prefix_bytes[prefix_count++] = 0xDB;
            saw_data_prefix = 1;
        } else if (strcmp(mnemonic, "ADDR32") == 0 || strcmp(mnemonic, "WID.A32") == 0) {
            if (saw_addr_prefix) {
                error(as, "ADDR32 prefix appears multiple times");
                return 0;
            }
            addr32_prefix = 1;
            prefix_bytes[prefix_count++] = 0x42;
            saw_addr_prefix = 1;
        }
        if (!parse_next_mnemonic(mnemonic, &operand)) {
            error(as, "prefix requires instruction");
            return 0;
        }
    }
    
    /* Parse operand */
    if (!parse_operand(as, operand, &op)) {
        return 0;
    }
    
    /* Check for shifter instructions ($02 $E9): SHL, SHR, SAR, ROL, ROR
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
            
            /* Emit: $02 $E9 [op|cnt] [dest_dp] [src_dp] */
            emit_byte(as, 0x02);
            emit_byte(as, 0xE9);
            emit_byte(as, shifter_instructions[i].op_code | (count & 0x1F));
            emit_byte(as, dest_dp & 0xFF);
            emit_byte(as, src_dp & 0xFF);
            return 1;
        }
    }
    
    /* Check for extend instructions ($02 $EA): SEXT8, SEXT16, ZEXT8, ZEXT16, CLZ, CTZ, POPCNT */
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
            
            /* Emit: $02 $EA [subop] [dest_dp] [src_dp] */
            emit_byte(as, 0x02);
            emit_byte(as, 0xEA);
            emit_byte(as, extend_instructions[i].subop);
            emit_byte(as, dest_dp & 0xFF);
            emit_byte(as, src_dp & 0xFF);
            return 1;
        }
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

    /* WAI/STP escape in 32-bit mode */
    if (as->m_flag == 2 && (strcmp(mnemonic, "WAI") == 0 || strcmp(mnemonic, "STP") == 0)) {
        if (prefix_count != 0) {
            error(as, "WAI/STP cannot be prefixed in 32-bit mode");
            return 0;
        }
        if (strcmp(mnemonic, "WAI") == 0) {
            emit_byte(as, 0x42);
            emit_byte(as, 0xCB);
            return 1;
        }
        if (strcmp(mnemonic, "STP") == 0) {
            emit_byte(as, 0x42);
            emit_byte(as, 0xDB);
            return 1;
        }
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
    
    /* Enforce ADDR32 prefix usage for 32-bit absolute addresses */
    if (as->m_flag == 2 && !addr32_prefix && op.value > 0xFFFF) {
        error(as, "ADDR32 prefix required for 32-bit address");
        return 0;
    }
    
    /* Map 32-bit absolute variants when ADDR32 prefix is present */
    if (addr32_prefix) {
        if (mode == AM_ABSL) mode = AM_ABS;
        else if (mode == AM_ABSLX) mode = AM_ABSX;
        else if (mode == AM_ABSLIND) mode = AM_ABSIND;
        else if (mode != AM_ABS && mode != AM_ABSX && mode != AM_ABSY &&
                 mode != AM_ABSIND && mode != AM_ABSINDX) {
            error(as, "ADDR32 prefix only valid with absolute addressing");
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
    
    /* Emit prefixes, then opcode */
    for (int i = 0; i < prefix_count; i++) {
        emit_byte(as, prefix_bytes[i]);
    }
    emit_byte(as, inst->opcodes[mode]);
    
    /* Emit operand */
    switch (mode) {
        case AM_IMP:
        case AM_ACC:
            break;
        case AM_IMM:
            {
                int size = get_imm_size(as, mnemonic, data_override);
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
            if (addr32_prefix) emit_quad(as, op.value);
            else emit_word(as, op.value & 0xFFFF);
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
        strcmp(directive, ".DCL") == 0 || strcmp(directive, "DCL") == 0) {
        char *p = operand;
        while (*p) {
            p = skip_whitespace(p);
            if (*p && *p != ',' && *p != ';') {
                uint32_t value;
                if (!parse_expression(as, p, &value, (const char**)&p)) {
                    error(as, "invalid long value");
                    return 0;
                }
                emit_long(as, value & 0xFFFFFF);
            }
            p = skip_whitespace(p);
            if (*p == ',') p++;
            else break;  /* End on comment, EOL, or anything else */
        }
        return 1;
    }
    
    if (strcmp(directive, ".DWORD") == 0 || strcmp(directive, ".DD") == 0 ||
        strcmp(directive, ".DCD") == 0 || strcmp(directive, "DCD") == 0) {
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
        strcmp(directive, ".RES") == 0 || strcmp(directive, ".SPACE") == 0) {
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
        while (*p && !isspace((unsigned char)*p) && *p != ',' && i < MAX_LABEL - 1)
            name[i++] = *p++;
        name[i] = '\0';
        if (name[0] == '\0') {
            error(as, ".SECTION requires a name");
            return 0;
        }
        switch_section(as, name);
        return 1;
    }
    
    if (strcmp(directive, ".END") == 0 || strcmp(directive, "END") == 0) {
        return 1;  /* End of file */
    }
    
    /* Include file */
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
    
    /* Check WID prefix */
    if (strcmp(upper, "WID") == 0)
        return 1;
    
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

static int assemble_file(Assembler *as, const char *filename) {
    /* Initialize default section if none exist */
    if (as->num_sections == 0) {
        if (!get_or_create_section(as, "TEXT")) {
            fprintf(stderr, "error: cannot create default section\n");
            return 0;
        }
        as->current_section = 0;
    }
    
    /* Pass 1: collect symbols */
    as->pass = 1;
    as->file_depth = 0;
    reset_sections(as);
    
    if (!process_file(as, filename)) {
        return 0;
    }
    
    /* Pass 2: generate code */
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
