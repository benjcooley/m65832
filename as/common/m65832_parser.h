/*
 * M65832 Instruction Parser
 * 
 * Shared operand and instruction parsing for assembler and LLVM backend.
 *
 * Copyright (c) 2026. MIT License.
 */

#ifndef M65832_PARSER_H
#define M65832_PARSER_H

#include "m65832_isa.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================== */
/* Parser Context                                                             */
/* ========================================================================== */

/* Callback for symbol lookup (returns 1 if found, 0 if not) */
typedef int (*M65_SymbolLookup)(const char *name, uint32_t *value, void *userdata);

/* Parser context */
typedef struct {
    int m_flag;              /* 0=8-bit, 1=16-bit, 2=32-bit accumulator */
    int x_flag;              /* 0=8-bit, 1=16-bit, 2=32-bit index */
    uint32_t pc;             /* Current program counter */
    M65_SymbolLookup lookup; /* Symbol lookup callback */
    void *lookup_userdata;   /* Userdata for callback */
    char error[256];         /* Error message buffer */
} M65_ParserCtx;

/* Initialize parser context with defaults */
void m65_parser_init(M65_ParserCtx *ctx);

/* ========================================================================== */
/* Parsed Operand                                                             */
/* ========================================================================== */

typedef struct {
    M65_AddrMode mode;       /* Addressing mode */
    uint32_t value;          /* Operand value */
    int force_width;         /* 0=auto, 1=byte, 2=word, 3=long, 4=quad */
    uint8_t mvp_dst;         /* For MVP/MVN destination bank */
    int b_relative;          /* 1 if B+offset syntax used (32-bit mode) */
    int fpu_reg_d;           /* FPU destination register (0-15, or -1) */
    int fpu_reg_s;           /* FPU source register (0-15, or -1) */
    int gpr_indirect;        /* GPR for indirect addressing (0-63, or -1) */
} M65_Operand;

/* ========================================================================== */
/* Parsed Instruction                                                         */
/* ========================================================================== */

typedef enum {
    M65_INSTR_NONE,          /* No instruction */
    M65_INSTR_STANDARD,      /* Standard 6502/65816 instruction */
    M65_INSTR_EXTENDED,      /* Extended instruction ($02 prefix) */
    M65_INSTR_EXTALU,        /* Extended ALU instruction ($02 $80-$97) */
    M65_INSTR_SHIFTER,       /* Shifter instruction ($02 $98) */
    M65_INSTR_EXTEND,        /* Extend instruction ($02 $99) */
} M65_InstrType;

typedef struct {
    M65_InstrType type;      /* Instruction type */
    char mnemonic[16];       /* Uppercase mnemonic */
    int size_suffix;         /* -1=none, 0=.B, 1=.W, 2=.L */
    M65_Operand operand;     /* Parsed operand */
    
    /* For extended ALU */
    uint8_t extalu_dest_dp;  /* Destination DP address */
    int extalu_dest_is_reg;  /* 1 if dest is register (vs A) */
    int extalu_size;         /* 0=byte, 1=word, 2=long */
    int extalu_src_mode;     /* Source addressing mode code */
    
    /* For shifter */
    uint8_t shift_dest_dp;   /* Destination DP address */
    uint8_t shift_src_dp;    /* Source DP address */
    int shift_count;         /* Shift count (0-31) or -1 for A */
    
    /* For extend operations */
    uint8_t extend_dest_dp;  /* Destination DP address */
    uint8_t extend_src_dp;   /* Source DP address */
    
    /* Encoding result */
    uint8_t opcode;          /* Primary opcode */
    uint8_t ext_opcode;      /* Extended opcode (after $02 prefix) */
    int needs_ext_prefix;    /* 1 if needs $02 prefix */
} M65_ParsedInstr;

/* ========================================================================== */
/* Parsing Functions                                                          */
/* ========================================================================== */

/*
 * Parse a numeric expression.
 * 
 * Parameters:
 *   ctx    - Parser context (for symbol lookup and PC)
 *   str    - Input string
 *   value  - Output value
 *   endptr - Output pointer to end of parsed expression
 *
 * Returns:
 *   1 on success, 0 on failure (check ctx->error)
 */
int m65_parse_expression(M65_ParserCtx *ctx, const char *str, 
                         uint32_t *value, const char **endptr);

/*
 * Parse an operand string.
 * 
 * Parameters:
 *   ctx     - Parser context
 *   str     - Input string (e.g., "#$1234", "$00,X", "($10),Y")
 *   operand - Output parsed operand
 *
 * Returns:
 *   1 on success, 0 on failure (check ctx->error)
 */
int m65_parse_operand(M65_ParserCtx *ctx, const char *str, M65_Operand *operand);

/*
 * Parse a complete instruction line.
 * 
 * Parameters:
 *   ctx       - Parser context
 *   mnemonic  - Instruction mnemonic (e.g., "LDA", "FADD.S")
 *   operands  - Operand string (may be NULL for implied instructions)
 *   instr     - Output parsed instruction
 *
 * Returns:
 *   1 on success, 0 on failure (check ctx->error)
 */
int m65_parse_instruction(M65_ParserCtx *ctx, const char *mnemonic,
                          const char *operands, M65_ParsedInstr *instr);

/*
 * Get the encoded size of an instruction (in bytes).
 */
int m65_instr_size(const M65_ParsedInstr *instr, M65_ParserCtx *ctx);

/*
 * Encode instruction to bytes.
 *
 * Parameters:
 *   instr  - Parsed instruction
 *   ctx    - Parser context
 *   buf    - Output buffer (must be at least m65_instr_size() bytes)
 *   buflen - Buffer length
 *
 * Returns:
 *   Number of bytes written, or -1 on error
 */
int m65_encode_instruction(const M65_ParsedInstr *instr, M65_ParserCtx *ctx,
                           uint8_t *buf, size_t buflen);

/* ========================================================================== */
/* Utility Functions                                                          */
/* ========================================================================== */

/* Skip whitespace, returns pointer to first non-whitespace */
const char *m65_skip_ws(const char *s);

/* Convert string to uppercase in-place */
void m65_str_upper(char *s);

/* Check if character is valid in a label/symbol name */
int m65_is_label_char(char c);

#ifdef __cplusplus
}
#endif

#endif /* M65832_PARSER_H */
