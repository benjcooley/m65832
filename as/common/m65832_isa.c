/*
 * M65832 Instruction Set Architecture Implementation
 * 
 * Opcode tables and instruction lookup functions.
 *
 * Copyright (c) 2026. MIT License.
 */

#include "m65832_isa.h"
#include <string.h>
#include <ctype.h>

/* ========================================================================== */
/* Opcode Tables                                                              */
/* ========================================================================== */

#define __ M65_OP_INVALID

/* Standard 6502/65816 instructions */
const M65_Instruction m65_instructions[] = {
    /*                IMP   ACC   IMM   DP    DPX   DPY   ABS   ABSX  ABSY  IND   INDX  INDY  INDL  INDLY ABSL  ABSLX REL   RELL  SR    SRIY  MVP   MVN   AIND  AINDX ALIND IMM32 ABS32 */
    { "ADC",        { __,   __,   0x69, 0x65, 0x75, __,   0x6D, 0x7D, 0x79, 0x72, 0x61, 0x71, 0x67, 0x77, 0x6F, 0x7F, __,   __,   0x63, 0x73, __,   __,   __,   __,   __,   __,   __   }, 0 },
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
    { "LDA",        { __,   __,   0xA9, 0xA5, 0xB5, __,   0xAD, 0xBD, 0xB9, 0xB2, 0xA1, 0xB1, 0xA7, 0xB7, 0xAF, 0xBF, __,   __,   0xA3, 0xB3, __,   __,   __,   __,   __,   __,   __   }, 0 },
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
    { "STA",        { __,   __,   __,   0x85, 0x95, __,   0x8D, 0x9D, 0x99, 0x92, 0x81, 0x91, 0x87, 0x97, 0x8F, 0x9F, __,   __,   0x83, 0x93, __,   __,   __,   __,   __,   __,   __   }, 0 },
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

#undef __

/* M65832 Extended instructions ($02 prefix) */
const M65_ExtInstruction m65_ext_instructions[] = {
    /* Multiply/Divide */
    { "MUL",    0x00, M65_AM_DP   },
    { "MULU",   0x01, M65_AM_DP   },
    { "MUL",    0x02, M65_AM_ABS  },
    { "MULU",   0x03, M65_AM_ABS  },
    { "DIV",    0x04, M65_AM_DP   },
    { "DIVU",   0x05, M65_AM_DP   },
    { "DIV",    0x06, M65_AM_ABS  },
    { "DIVU",   0x07, M65_AM_ABS  },
    /* Atomics */
    { "CAS",    0x10, M65_AM_DP   },
    { "CAS",    0x11, M65_AM_ABS  },
    { "LLI",    0x12, M65_AM_DP   },
    { "LLI",    0x13, M65_AM_ABS  },
    { "SCI",    0x14, M65_AM_DP   },
    { "SCI",    0x15, M65_AM_ABS  },
    /* Base registers */
    { "SVBR",   0x20, M65_AM_IMM  },
    { "SVBR",   0x21, M65_AM_DP   },
    { "SB",     0x22, M65_AM_IMM  },
    { "SB",     0x23, M65_AM_DP   },
    { "SD",     0x24, M65_AM_IMM  },
    { "SD",     0x25, M65_AM_DP   },
    /* Register Window */
    { "RSET",   0x30, M65_AM_IMP  },
    { "RCLR",   0x31, M65_AM_IMP  },
    /* System */
    { "TRAP",   0x40, M65_AM_IMM  },
    { "FENCE",  0x50, M65_AM_IMP  },
    { "FENCER", 0x51, M65_AM_IMP  },
    { "FENCEW", 0x52, M65_AM_IMP  },
    /* Extended flags */
    { "REPE",   0x60, M65_AM_IMM  },
    { "SEPE",   0x61, M65_AM_IMM  },
    /* 32-bit stack ops */
    { "PHD32",  0x70, M65_AM_IMP  },
    { "PLD32",  0x71, M65_AM_IMP  },
    { "PHB32",  0x72, M65_AM_IMP  },
    { "PLB32",  0x73, M65_AM_IMP  },
    { "PHVBR",  0x74, M65_AM_IMP  },
    { "PLVBR",  0x75, M65_AM_IMP  },
    /* B register transfers */
    { "TAB",    0x91, M65_AM_IMP  },
    { "TBA",    0x92, M65_AM_IMP  },
    { "TXB",    0x93, M65_AM_IMP  },
    { "TBX",    0x94, M65_AM_IMP  },
    { "TYB",    0x95, M65_AM_IMP  },
    { "TBY",    0x96, M65_AM_IMP  },
    /* Stack pointer to B register transfer */
    { "TSPB",   0xA4, M65_AM_IMP  },
    { "TSPB",   0xA4, M65_AM_IMP  },  /* Transfer SP to B */
    { "TBSP",   0xA5, M65_AM_IMP  },  /* Transfer B to SP */
    /* Temp register transfers */
    { "TTA",    0x9A, M65_AM_IMP  },
    { "TAT",    0x9B, M65_AM_IMP  },
    /* 64-bit load/store */
    { "LDQ",    0x9C, M65_AM_DP   },
    { "LDQ",    0x9D, M65_AM_ABS  },
    { "STQ",    0x9E, M65_AM_DP   },
    { "STQ",    0x9F, M65_AM_ABS  },
    /* LEA */
    { "LEA",    0xA0, M65_AM_DP   },
    { "LEA",    0xA1, M65_AM_DPX  },
    { "LEA",    0xA2, M65_AM_ABS  },
    { "LEA",    0xA3, M65_AM_ABSX },
    /* FPU Load/Store */
    { "LDF",    0xB0, M65_AM_FPU_DP   },
    { "LDF",    0xB1, M65_AM_FPU_ABS  },
    { "STF",    0xB2, M65_AM_FPU_DP   },
    { "STF",    0xB3, M65_AM_FPU_ABS  },
    { "LDF",    0xB4, M65_AM_FPU_IND  },
    { "STF",    0xB5, M65_AM_FPU_IND  },
    { "LDF",    0xB6, M65_AM_FPU_LONG },
    { "STF",    0xB7, M65_AM_FPU_LONG },
    { "LDF.S",  0xBA, M65_AM_FPU_IND  },
    { "STF.S",  0xBB, M65_AM_FPU_IND  },
    /* FPU single-precision */
    { "FADD.S", 0xC0, M65_AM_FPU_REG2 },
    { "FSUB.S", 0xC1, M65_AM_FPU_REG2 },
    { "FMUL.S", 0xC2, M65_AM_FPU_REG2 },
    { "FDIV.S", 0xC3, M65_AM_FPU_REG2 },
    { "FNEG.S", 0xC4, M65_AM_FPU_REG2 },
    { "FABS.S", 0xC5, M65_AM_FPU_REG2 },
    { "FCMP.S", 0xC6, M65_AM_FPU_REG2 },
    { "F2I.S",  0xC7, M65_AM_FPU_REG1 },
    { "I2F.S",  0xC8, M65_AM_FPU_REG1 },
    { "FMOV.S", 0xC9, M65_AM_FPU_REG2 },
    { "FSQRT.S",0xCA, M65_AM_FPU_REG2 },
    /* FPU double-precision */
    { "FADD.D", 0xD0, M65_AM_FPU_REG2 },
    { "FSUB.D", 0xD1, M65_AM_FPU_REG2 },
    { "FMUL.D", 0xD2, M65_AM_FPU_REG2 },
    { "FDIV.D", 0xD3, M65_AM_FPU_REG2 },
    { "FNEG.D", 0xD4, M65_AM_FPU_REG2 },
    { "FABS.D", 0xD5, M65_AM_FPU_REG2 },
    { "FCMP.D", 0xD6, M65_AM_FPU_REG2 },
    { "F2I.D",  0xD7, M65_AM_FPU_REG1 },
    { "I2F.D",  0xD8, M65_AM_FPU_REG1 },
    { "FMOV.D", 0xD9, M65_AM_FPU_REG2 },
    { "FSQRT.D",0xDA, M65_AM_FPU_REG2 },
    /* FPU register transfers */
    { "FTOA",   0xE0, M65_AM_FPU_REG1 },
    { "FTOT",   0xE1, M65_AM_FPU_REG1 },
    { "ATOF",   0xE2, M65_AM_FPU_REG1 },
    { "TTOF",   0xE3, M65_AM_FPU_REG1 },
    { "FCVT.DS",0xE4, M65_AM_FPU_REG2 },
    { "FCVT.SD",0xE5, M65_AM_FPU_REG2 },
    { NULL, 0, 0 }
};

/* Extended ALU instructions ($02 $80-$97) */
const M65_ExtALUInstruction m65_extalu_instructions[] = {
    /* Register-targeted extended ALU */
    { "LD",   0x80, 0, 0 },
    { "ST",   0x81, 0, 1 },
    /* Traditional mnemonic aliases (for A-targeted with size suffix) */
    { "LDA",  0x80, 0, 0 },
    { "STA",  0x81, 0, 1 },
    /* Arithmetic/Logic */
    { "ADC",  0x82, 0, 0 },
    { "SBC",  0x83, 0, 0 },
    { "AND",  0x84, 0, 0 },
    { "ORA",  0x85, 0, 0 },
    { "EOR",  0x86, 0, 0 },
    { "CMP",  0x87, 0, 0 },
    { "BIT",  0x88, 0, 0 },
    { "TSB",  0x89, 0, 1 },
    { "TRB",  0x8A, 0, 1 },
    /* Unary operations */
    { "INC",  0x8B, 1, 0 },
    { "DEC",  0x8C, 1, 0 },
    { "ASL",  0x8D, 1, 0 },
    { "LSR",  0x8E, 1, 0 },
    { "ROL",  0x8F, 1, 0 },
    { "ROR",  0x90, 1, 0 },
    { "STZ",  0x97, 0, 1 },
    { NULL, 0, 0, 0 }
};

/* Shifter instructions ($02 $98 prefix) */
const M65_ShifterInstruction m65_shifter_instructions[] = {
    { "SHL",  0x00 },
    { "SHR",  0x20 },
    { "SAR",  0x40 },
    { "ROL",  0x60 },
    { "ROR",  0x80 },
    { NULL, 0 }
};

/* Extend instructions ($02 $99 prefix) */
const M65_ExtendInstruction m65_extend_instructions[] = {
    { "SEXT8",  0x00 },
    { "SEXT16", 0x01 },
    { "ZEXT8",  0x02 },
    { "ZEXT16", 0x03 },
    { "CLZ",    0x04 },
    { "CTZ",    0x05 },
    { "POPCNT", 0x06 },
    { NULL, 0 }
};

/* Count table entries */
static int count_instructions(void) {
    int n = 0;
    while (m65_instructions[n].name) n++;
    return n;
}

static int count_ext_instructions(void) {
    int n = 0;
    while (m65_ext_instructions[n].name) n++;
    return n;
}

static int count_extalu_instructions(void) {
    int n = 0;
    while (m65_extalu_instructions[n].name) n++;
    return n;
}

static int count_shifter_instructions(void) {
    int n = 0;
    while (m65_shifter_instructions[n].name) n++;
    return n;
}

static int count_extend_instructions(void) {
    int n = 0;
    while (m65_extend_instructions[n].name) n++;
    return n;
}

const int m65_num_instructions = -1;  /* Use count function */
const int m65_num_ext_instructions = -1;
const int m65_num_extalu_instructions = -1;
const int m65_num_shifter_instructions = -1;
const int m65_num_extend_instructions = -1;

/* ========================================================================== */
/* Lookup Functions                                                           */
/* ========================================================================== */

static int strcasecmp_local(const char *a, const char *b) {
    while (*a && *b) {
        int ca = toupper((unsigned char)*a);
        int cb = toupper((unsigned char)*b);
        if (ca != cb) return ca - cb;
        a++;
        b++;
    }
    return toupper((unsigned char)*a) - toupper((unsigned char)*b);
}

const M65_Instruction *m65_find_instruction(const char *mnemonic) {
    for (int i = 0; m65_instructions[i].name; i++) {
        if (strcasecmp_local(m65_instructions[i].name, mnemonic) == 0)
            return &m65_instructions[i];
    }
    return NULL;
}

const M65_ExtInstruction *m65_find_ext_instruction(const char *mnemonic, M65_AddrMode mode) {
    /* First try exact mode match */
    for (int i = 0; m65_ext_instructions[i].name; i++) {
        if (strcasecmp_local(m65_ext_instructions[i].name, mnemonic) == 0 &&
            m65_ext_instructions[i].mode == mode)
            return &m65_ext_instructions[i];
    }
    /* For implied instructions, just match name */
    for (int i = 0; m65_ext_instructions[i].name; i++) {
        if (strcasecmp_local(m65_ext_instructions[i].name, mnemonic) == 0)
            return &m65_ext_instructions[i];
    }
    return NULL;
}

const M65_ExtALUInstruction *m65_find_extalu_instruction(const char *mnemonic) {
    for (int i = 0; m65_extalu_instructions[i].name; i++) {
        if (strcasecmp_local(m65_extalu_instructions[i].name, mnemonic) == 0)
            return &m65_extalu_instructions[i];
    }
    return NULL;
}

const M65_ShifterInstruction *m65_find_shifter_instruction(const char *mnemonic) {
    for (int i = 0; m65_shifter_instructions[i].name; i++) {
        if (strcasecmp_local(m65_shifter_instructions[i].name, mnemonic) == 0)
            return &m65_shifter_instructions[i];
    }
    return NULL;
}

const M65_ExtendInstruction *m65_find_extend_instruction(const char *mnemonic) {
    for (int i = 0; m65_extend_instructions[i].name; i++) {
        if (strcasecmp_local(m65_extend_instructions[i].name, mnemonic) == 0)
            return &m65_extend_instructions[i];
    }
    return NULL;
}

/* ========================================================================== */
/* Register Parsing                                                           */
/* ========================================================================== */

int m65_parse_gpr(const char *name) {
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

int m65_parse_fpr(const char *name) {
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
/* Instruction Encoding Helpers                                               */
/* ========================================================================== */

int m65_get_operand_size(M65_AddrMode mode, int m_flag, int x_flag) {
    switch (mode) {
        case M65_AM_IMP:
        case M65_AM_ACC:
            return 0;
        case M65_AM_IMM:
            return (m_flag == 0) ? 1 : (m_flag == 1) ? 2 : 4;
        case M65_AM_DP:
        case M65_AM_DPX:
        case M65_AM_DPY:
        case M65_AM_IND:
        case M65_AM_INDX:
        case M65_AM_INDY:
        case M65_AM_INDL:
        case M65_AM_INDLY:
        case M65_AM_SR:
        case M65_AM_SRIY:
            return 1;
        case M65_AM_REL:
            return (m_flag == 2) ? 2 : 1;  /* 32-bit mode uses 16-bit relative */
        case M65_AM_ABS:
        case M65_AM_ABSX:
        case M65_AM_ABSY:
        case M65_AM_ABSIND:
        case M65_AM_ABSINDX:
        case M65_AM_RELL:
        case M65_AM_MVP:
        case M65_AM_MVN:
            return 2;
        case M65_AM_ABSL:
        case M65_AM_ABSLX:
        case M65_AM_ABSLIND:
            return 3;
        case M65_AM_IMM32:
        case M65_AM_ABS32:
            return 4;
        case M65_AM_FPU_REG2:
        case M65_AM_FPU_REG1:
            return 1;   /* Register byte */
        case M65_AM_FPU_DP:
            return 2;   /* Register byte + DP */
        case M65_AM_FPU_ABS:
            return 3;   /* Register byte + ABS */
        case M65_AM_FPU_IND:
            return 1;   /* Register byte (Fn, Rm) */
        case M65_AM_FPU_LONG:
            return 5;   /* Register byte + ABS32 */
        default:
            return 0;
    }
}

int m65_uses_m_flag(const char *mnemonic) {
    return strcasecmp_local(mnemonic, "LDA") == 0 ||
           strcasecmp_local(mnemonic, "STA") == 0 ||
           strcasecmp_local(mnemonic, "ADC") == 0 ||
           strcasecmp_local(mnemonic, "SBC") == 0 ||
           strcasecmp_local(mnemonic, "AND") == 0 ||
           strcasecmp_local(mnemonic, "ORA") == 0 ||
           strcasecmp_local(mnemonic, "EOR") == 0 ||
           strcasecmp_local(mnemonic, "CMP") == 0 ||
           strcasecmp_local(mnemonic, "BIT") == 0;
}

int m65_uses_x_flag(const char *mnemonic) {
    return strcasecmp_local(mnemonic, "LDX") == 0 ||
           strcasecmp_local(mnemonic, "LDY") == 0 ||
           strcasecmp_local(mnemonic, "CPX") == 0 ||
           strcasecmp_local(mnemonic, "CPY") == 0;
}

int m65_get_imm_size(const char *mnemonic, int m_flag, int x_flag, int data_override) {
    if (data_override == 1) return 1;
    if (data_override == 2) return 2;
    
    /* 32-bit mode uses 32-bit immediates for data instructions */
    if (m_flag == 2) {
        if (m65_uses_m_flag(mnemonic) || m65_uses_x_flag(mnemonic)) {
            return 4;
        }
    }
    
    if (m65_uses_m_flag(mnemonic)) {
        return m_flag == 0 ? 1 : (m_flag == 1 ? 2 : 4);
    }
    if (m65_uses_x_flag(mnemonic)) {
        return x_flag == 0 ? 1 : (x_flag == 1 ? 2 : 4);
    }
    
    /* Fixed 8-bit */
    if (strcasecmp_local(mnemonic, "REP") == 0 ||
        strcasecmp_local(mnemonic, "SEP") == 0 ||
        strcasecmp_local(mnemonic, "COP") == 0 ||
        strcasecmp_local(mnemonic, "REPE") == 0 ||
        strcasecmp_local(mnemonic, "SEPE") == 0 ||
        strcasecmp_local(mnemonic, "TRAP") == 0) {
        return 1;
    }
    
    /* Fixed 16-bit */
    if (strcasecmp_local(mnemonic, "PEA") == 0) {
        return 2;
    }
    
    return 1;  /* Default */
}

int m65_is_branch(const char *mnemonic) {
    return strcasecmp_local(mnemonic, "BCC") == 0 ||
           strcasecmp_local(mnemonic, "BCS") == 0 ||
           strcasecmp_local(mnemonic, "BEQ") == 0 ||
           strcasecmp_local(mnemonic, "BMI") == 0 ||
           strcasecmp_local(mnemonic, "BNE") == 0 ||
           strcasecmp_local(mnemonic, "BPL") == 0 ||
           strcasecmp_local(mnemonic, "BRA") == 0 ||
           strcasecmp_local(mnemonic, "BRL") == 0 ||
           strcasecmp_local(mnemonic, "BVC") == 0 ||
           strcasecmp_local(mnemonic, "BVS") == 0;
}
