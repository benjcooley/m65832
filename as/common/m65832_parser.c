/*
 * M65832 Instruction Parser Implementation
 * 
 * Shared operand and instruction parsing for assembler and LLVM backend.
 *
 * Copyright (c) 2026. MIT License.
 */

#include "m65832_parser.h"
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <stdarg.h>

/* ========================================================================== */
/* Utility Functions                                                          */
/* ========================================================================== */

const char *m65_skip_ws(const char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

void m65_str_upper(char *s) {
    while (*s) {
        *s = toupper((unsigned char)*s);
        s++;
    }
}

int m65_is_label_char(char c) {
    return isalnum((unsigned char)c) || c == '_' || c == '.';
}

/* ========================================================================== */
/* Parser Context                                                             */
/* ========================================================================== */

void m65_parser_init(M65_ParserCtx *ctx) {
    ctx->m_flag = 2;     /* Default to 32-bit mode */
    ctx->x_flag = 2;
    ctx->pc = 0;
    ctx->lookup = NULL;
    ctx->lookup_userdata = NULL;
    ctx->error[0] = '\0';
}

static void set_error(M65_ParserCtx *ctx, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(ctx->error, sizeof(ctx->error), fmt, ap);
    va_end(ap);
}

/* ========================================================================== */
/* Number Parsing                                                             */
/* ========================================================================== */

static int parse_number(const char *s, uint32_t *value, const char **end) {
    uint32_t v = 0;
    const char *p = s;
    
    if (*p == '$') {
        /* Hex: $xxxx */
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
        /* Binary: %nnnn */
        p++;
        if (*p != '0' && *p != '1') return 0;
        while (*p == '0' || *p == '1') {
            v = v * 2 + (*p - '0');
            p++;
        }
    } else if (*p == '0' && (p[1] == 'x' || p[1] == 'X')) {
        /* C-style hex: 0xnnnn */
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

/* ========================================================================== */
/* Expression Parsing                                                         */
/* ========================================================================== */

int m65_parse_expression(M65_ParserCtx *ctx, const char *s, 
                         uint32_t *value, const char **endptr) {
    const char *p = m65_skip_ws(s);
    uint32_t v = 0;
    int negate = 0;
    int have_value = 0;
    
    /* Handle leading operators */
    if (*p == '-') {
        negate = 1;
        p++;
        p = m65_skip_ws(p);
    } else if (*p == '+') {
        p++;
        p = m65_skip_ws(p);
    } else if (*p == '<') {
        /* Low byte operator */
        p++;
        if (!m65_parse_expression(ctx, p, &v, &p)) return 0;
        *value = v & 0xFF;
        *endptr = p;
        return 1;
    } else if (*p == '>') {
        /* High byte operator */
        p++;
        if (!m65_parse_expression(ctx, p, &v, &p)) return 0;
        *value = (v >> 8) & 0xFF;
        *endptr = p;
        return 1;
    } else if (*p == '^') {
        /* Bank byte operator */
        p++;
        if (!m65_parse_expression(ctx, p, &v, &p)) return 0;
        *value = (v >> 16) & 0xFF;
        *endptr = p;
        return 1;
    }
    
    /* Parse primary value */
    if (*p == '(') {
        /* Parenthesized expression */
        p++;
        if (!m65_parse_expression(ctx, p, &v, &p)) return 0;
        p = m65_skip_ws(p);
        if (*p != ')') {
            set_error(ctx, "expected ')'");
            return 0;
        }
        p++;
        have_value = 1;
    } else if (*p == '*') {
        /* Current PC */
        v = ctx->pc;
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
    } else if (m65_is_label_char(*p) && !isdigit((unsigned char)*p)) {
        /* Symbol or register alias */
        char label[64];
        int i = 0;
        while (m65_is_label_char(*p) && i < 63)
            label[i++] = *p++;
        label[i] = '\0';
        
        /* Check for register alias R0-R63 */
        int reg_addr = m65_parse_gpr(label);
        if (reg_addr >= 0) {
            v = reg_addr;
            have_value = 1;
        } else if (ctx->lookup) {
            /* Try symbol lookup */
            char upper_label[64];
            strncpy(upper_label, label, sizeof(upper_label) - 1);
            upper_label[sizeof(upper_label) - 1] = '\0';
            m65_str_upper(upper_label);
            
            if (ctx->lookup(upper_label, &v, ctx->lookup_userdata)) {
                have_value = 1;
            } else {
                set_error(ctx, "undefined symbol '%s'", label);
                return 0;
            }
        } else {
            set_error(ctx, "undefined symbol '%s'", label);
            return 0;
        }
    }
    
    if (!have_value) {
        return 0;
    }
    
    if (negate) v = -v;
    
    /* Handle binary operators (simple left-to-right) */
    p = m65_skip_ws(p);
    while (*p == '+' || *p == '-' || *p == '*' || *p == '/' || 
           *p == '%' || *p == '&' || *p == '|' || *p == '^') {
        char op = *p++;
        p = m65_skip_ws(p);
        uint32_t v2;
        if (!m65_parse_expression(ctx, p, &v2, &p)) return 0;
        switch (op) {
            case '+': v += v2; break;
            case '-': v -= v2; break;
            case '*': v *= v2; break;
            case '/': 
                if (v2 == 0) {
                    set_error(ctx, "division by zero");
                    return 0;
                }
                v /= v2;
                break;
            case '%':
                if (v2 == 0) {
                    set_error(ctx, "modulo by zero");
                    return 0;
                }
                v %= v2;
                break;
            case '&': v &= v2; break;
            case '|': v |= v2; break;
            case '^': v ^= v2; break;
        }
        p = m65_skip_ws(p);
    }
    
    *value = v;
    *endptr = p;
    return 1;
}

/* ========================================================================== */
/* Operand Parsing                                                            */
/* ========================================================================== */

int m65_parse_operand(M65_ParserCtx *ctx, const char *str, M65_Operand *op) {
    const char *p = m65_skip_ws(str);
    
    /* Initialize operand */
    op->mode = M65_AM_IMP;
    op->value = 0;
    op->force_width = 0;
    op->mvp_dst = 0;
    op->b_relative = 0;
    op->fpu_reg_d = -1;
    op->fpu_reg_s = -1;
    op->gpr_indirect = -1;
    
    if (!*p || *p == ';') {
        /* No operand = implied or accumulator */
        return 1;
    }
    
    /* Check for 'A' (accumulator) */
    if ((*p == 'A' || *p == 'a') && (!p[1] || isspace((unsigned char)p[1]) || p[1] == ';')) {
        op->mode = M65_AM_ACC;
        return 1;
    }
    
    /* Immediate: #value */
    if (*p == '#') {
        p++;
        if (!m65_parse_expression(ctx, p, &op->value, &p)) {
            set_error(ctx, "invalid immediate value");
            return 0;
        }
        op->mode = M65_AM_IMM;
        return 1;
    }
    
    /* Indirect modes: (xxx) or [xxx] */
    if (*p == '(' || *p == '[') {
        char bracket = *p++;
        char close_bracket = (bracket == '(') ? ')' : ']';
        int is_long = (bracket == '[');
        
        p = m65_skip_ws(p);
        
        /* Check for B+offset syntax */
        if ((*p == 'B' || *p == 'b') && p[1] == '+') {
            op->b_relative = 1;
            p += 2;
            p = m65_skip_ws(p);
        }
        
        if (!m65_parse_expression(ctx, p, &op->value, &p)) {
            set_error(ctx, "invalid indirect address");
            return 0;
        }
        
        if (op->b_relative && op->value > 0xFFFF) {
            set_error(ctx, "B+offset must be 16-bit");
            return 0;
        }
        
        p = m65_skip_ws(p);
        
        /* Check for ,X or ,S before closing bracket */
        if (*p == ',') {
            p++;
            p = m65_skip_ws(p);
            if ((*p == 'X' || *p == 'x') && p[1] == close_bracket) {
                p += 2;
                if (is_long) {
                    set_error(ctx, "invalid addressing mode");
                    return 0;
                }
                op->mode = (op->value <= 0xFF) ? M65_AM_INDX : M65_AM_ABSINDX;
                return 1;
            }
            if ((*p == 'S' || *p == 's') && p[1] == close_bracket) {
                p += 2;
                /* Check for ),Y */
                p = m65_skip_ws(p);
                if (*p == ',') {
                    p++;
                    p = m65_skip_ws(p);
                    if (*p == 'Y' || *p == 'y') {
                        op->mode = M65_AM_SRIY;
                        return 1;
                    }
                }
                op->mode = M65_AM_SR;
                return 1;
            }
        }
        
        if (*p != close_bracket) {
            set_error(ctx, "expected '%c'", close_bracket);
            return 0;
        }
        p++;
        p = m65_skip_ws(p);
        
        /* Check for ),Y or ],Y */
        if (*p == ',') {
            p++;
            p = m65_skip_ws(p);
            if (*p == 'Y' || *p == 'y') {
                op->mode = is_long ? M65_AM_INDLY : M65_AM_INDY;
                return 1;
            }
            set_error(ctx, "expected Y index");
            return 0;
        }
        
        /* Plain indirect */
        if (is_long) {
            op->mode = (op->value <= 0xFF) ? M65_AM_INDL : M65_AM_ABSLIND;
        } else {
            op->mode = (op->value <= 0xFF) ? M65_AM_IND : M65_AM_ABSIND;
        }
        return 1;
    }
    
    /* Explicit B+offset syntax */
    if ((*p == 'B' || *p == 'b') && p[1] == '+') {
        p += 2;
        p = m65_skip_ws(p);
        if (!m65_parse_expression(ctx, p, &op->value, &p)) {
            set_error(ctx, "invalid B+offset");
            return 0;
        }
        if (op->value > 0xFFFF) {
            set_error(ctx, "B+offset must be 16-bit");
            return 0;
        }
        op->b_relative = 1;
        p = m65_skip_ws(p);
        if (*p == ',') {
            p++;
            p = m65_skip_ws(p);
            if (*p == 'X' || *p == 'x') {
                op->mode = M65_AM_ABSX;
                return 1;
            }
            if (*p == 'Y' || *p == 'y') {
                op->mode = M65_AM_ABSY;
                return 1;
            }
            set_error(ctx, "expected X or Y index");
            return 0;
        }
        op->mode = M65_AM_ABS;
        return 1;
    }
    
    /* Direct/Absolute addressing */
    if (!m65_parse_expression(ctx, p, &op->value, &p)) {
        set_error(ctx, "invalid operand");
        return 0;
    }
    p = m65_skip_ws(p);
    
    /* Check for index or block move */
    if (*p == ',') {
        p++;
        p = m65_skip_ws(p);
        
        if (*p == 'X' || *p == 'x') {
            p++;
            if (op->value <= 0xFF) op->mode = M65_AM_DPX;
            else if (op->value <= 0xFFFF) op->mode = M65_AM_ABSX;
            else op->mode = M65_AM_ABSLX;
            return 1;
        }
        if (*p == 'Y' || *p == 'y') {
            p++;
            if (op->value <= 0xFF) op->mode = M65_AM_DPY;
            else op->mode = M65_AM_ABSY;
            return 1;
        }
        if (*p == 'S' || *p == 's') {
            op->mode = M65_AM_SR;
            return 1;
        }
        
        /* MVP/MVN: src,dst */
        uint32_t dst;
        if (!m65_parse_expression(ctx, p, &dst, &p)) {
            set_error(ctx, "invalid block move destination");
            return 0;
        }
        op->mvp_dst = dst & 0xFF;
        op->mode = M65_AM_MVP;
        return 1;
    }
    
    /* Plain address - determine mode by size */
    if (op->value <= 0xFF) op->mode = M65_AM_DP;
    else if (op->value <= 0xFFFF) op->mode = M65_AM_ABS;
    else if (op->value <= 0xFFFFFF) op->mode = M65_AM_ABSL;
    else op->mode = M65_AM_ABS32;
    
    return 1;
}

/* ========================================================================== */
/* Instruction Parsing                                                        */
/* ========================================================================== */

static int strip_size_suffix(char *mnemonic, int *size_code) {
    *size_code = -1;
    char *dot = strrchr(mnemonic, '.');
    if (!dot) return 1;
    
    if (dot[1] == '\0' || dot[2] != '\0') {
        /* Not a single-char suffix */
        return 1;
    }
    
    switch (dot[1]) {
        case 'B': case 'b':
            *size_code = 0;
            *dot = '\0';
            break;
        case 'W': case 'w':
            *size_code = 1;
            *dot = '\0';
            break;
        case 'L': case 'l':
            *size_code = 2;
            *dot = '\0';
            break;
        case 'S': case 's':  /* FPU single */
        case 'D': case 'd':  /* FPU double */
            /* Leave FPU suffixes intact */
            break;
        default:
            break;
    }
    return 1;
}

int m65_parse_instruction(M65_ParserCtx *ctx, const char *mnemonic,
                          const char *operands, M65_ParsedInstr *instr) {
    /* Initialize instruction */
    memset(instr, 0, sizeof(*instr));
    instr->type = M65_INSTR_NONE;
    instr->size_suffix = -1;
    instr->operand.fpu_reg_d = -1;
    instr->operand.fpu_reg_s = -1;
    instr->operand.gpr_indirect = -1;
    
    /* Copy and uppercase mnemonic */
    strncpy(instr->mnemonic, mnemonic, sizeof(instr->mnemonic) - 1);
    instr->mnemonic[sizeof(instr->mnemonic) - 1] = '\0';
    m65_str_upper(instr->mnemonic);
    
    /* Strip and record size suffix */
    strip_size_suffix(instr->mnemonic, &instr->size_suffix);
    
    /* Parse operand if provided */
    if (operands && *operands) {
        if (!m65_parse_operand(ctx, operands, &instr->operand)) {
            return 0;
        }
    }
    
    /* Try standard instruction first */
    const M65_Instruction *std = m65_find_instruction(instr->mnemonic);
    if (std) {
        uint8_t opcode = std->opcodes[instr->operand.mode];
        if (opcode != M65_OP_INVALID) {
            instr->type = M65_INSTR_STANDARD;
            instr->opcode = opcode;
            instr->needs_ext_prefix = std->ext_prefix;
            return 1;
        }
        /* Try mode promotion (DP -> ABS, etc.) */
        if (instr->operand.mode == M65_AM_DP) {
            opcode = std->opcodes[M65_AM_ABS];
            if (opcode != M65_OP_INVALID) {
                instr->operand.mode = M65_AM_ABS;
                instr->type = M65_INSTR_STANDARD;
                instr->opcode = opcode;
                return 1;
            }
        }
    }
    
    /* Try extended instruction */
    const M65_ExtInstruction *ext = m65_find_ext_instruction(instr->mnemonic, 
                                                             instr->operand.mode);
    if (ext) {
        instr->type = M65_INSTR_EXTENDED;
        instr->ext_opcode = ext->ext_opcode;
        instr->needs_ext_prefix = 1;
        return 1;
    }
    
    /* Try shifter instruction */
    const M65_ShifterInstruction *shifter = m65_find_shifter_instruction(instr->mnemonic);
    if (shifter) {
        instr->type = M65_INSTR_SHIFTER;
        instr->ext_opcode = 0x98;
        instr->needs_ext_prefix = 1;
        /* Additional parsing would be needed for shift operands */
        return 1;
    }
    
    /* Try extend instruction */
    const M65_ExtendInstruction *extend = m65_find_extend_instruction(instr->mnemonic);
    if (extend) {
        instr->type = M65_INSTR_EXTEND;
        instr->ext_opcode = 0x99;
        instr->needs_ext_prefix = 1;
        /* Additional parsing would be needed for extend operands */
        return 1;
    }
    
    set_error(ctx, "unknown instruction '%s'", mnemonic);
    return 0;
}

/* ========================================================================== */
/* Instruction Encoding                                                       */
/* ========================================================================== */

int m65_instr_size(const M65_ParsedInstr *instr, M65_ParserCtx *ctx) {
    int size = 1;  /* Opcode */
    
    if (instr->needs_ext_prefix) {
        size++;  /* $02 prefix */
    }
    
    size += m65_get_operand_size(instr->operand.mode, ctx->m_flag, ctx->x_flag);
    
    return size;
}

int m65_encode_instruction(const M65_ParsedInstr *instr, M65_ParserCtx *ctx,
                           uint8_t *buf, size_t buflen) {
    int idx = 0;
    
    /* Emit prefix if needed */
    if (instr->needs_ext_prefix) {
        if (idx >= (int)buflen) return -1;
        buf[idx++] = 0x02;
    }
    
    /* Emit opcode */
    if (idx >= (int)buflen) return -1;
    if (instr->type == M65_INSTR_STANDARD) {
        buf[idx++] = instr->opcode;
    } else {
        buf[idx++] = instr->ext_opcode;
    }
    
    /* Emit operand bytes */
    int opsize = m65_get_operand_size(instr->operand.mode, ctx->m_flag, ctx->x_flag);
    uint32_t val = instr->operand.value;
    
    for (int i = 0; i < opsize && idx < (int)buflen; i++) {
        buf[idx++] = val & 0xFF;
        val >>= 8;
    }
    
    return idx;
}
