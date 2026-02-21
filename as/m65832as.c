/*
 * M65832 Assembler
 * 
 * A two-pass assembler for the M65832 processor.
 * Supports all 6502/65816 instructions plus M65832 extensions.
 *
 * Build: make (uses common library)
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

/* Include shared ISA definitions */
#include "m65832_isa.h"

/* Compatibility defines - map local names to shared library names */
#define AddrMode        M65_AddrMode
#define AM_IMP          M65_AM_IMP
#define AM_ACC          M65_AM_ACC
#define AM_IMM          M65_AM_IMM
#define AM_DP           M65_AM_DP
#define AM_DPX          M65_AM_DPX
#define AM_DPY          M65_AM_DPY
#define AM_ABS          M65_AM_ABS
#define AM_ABSX         M65_AM_ABSX
#define AM_ABSY         M65_AM_ABSY
#define AM_IND          M65_AM_IND
#define AM_INDX         M65_AM_INDX
#define AM_INDY         M65_AM_INDY
#define AM_INDL         M65_AM_INDL
#define AM_INDLY        M65_AM_INDLY
#define AM_ABSL         M65_AM_ABSL
#define AM_ABSLX        M65_AM_ABSLX
#define AM_REL          M65_AM_REL
#define AM_RELL         M65_AM_RELL
#define AM_SR           M65_AM_SR
#define AM_SRIY         M65_AM_SRIY
#define AM_MVP          M65_AM_MVP
#define AM_MVN          M65_AM_MVN
#define AM_ABSIND       M65_AM_ABSIND
#define AM_ABSINDX      M65_AM_ABSINDX
#define AM_ABSLIND      M65_AM_ABSLIND
#define AM_IMM32        M65_AM_IMM32
#define AM_ABS32        M65_AM_ABS32
#define AM_FPU_REG2     M65_AM_FPU_REG2
#define AM_FPU_REG1     M65_AM_FPU_REG1
#define AM_FPU_DP       M65_AM_FPU_DP
#define AM_FPU_ABS      M65_AM_FPU_ABS
#define AM_FPU_IND      M65_AM_FPU_IND
#define AM_FPU_LONG     M65_AM_FPU_LONG
#define AM_COUNT        M65_AM_COUNT

/* Map struct names - only for compatible types */
#define Instruction         M65_Instruction
#define ExtInstruction      M65_ExtInstruction
/* RegALUInstruction, ShifterInstruction, ExtendInstruction use local definitions
 * because they have different structures for encoding purposes */

/* Map table names - only for compatible tables */
#define instructions         m65_instructions
#define ext_instructions     m65_ext_instructions
/* regalu_instructions, shifter_instructions, extend_instructions use local tables
 * because they have different encoding schemes */

/* Invalid opcode marker */
#define __  M65_OP_INVALID

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

/* AddrMode, Instruction, and instruction tables now come from m65832_isa.h */

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
/* Instruction Tables                                                         */
/* ========================================================================== */

/* Standard and extended instruction tables come from shared library.
 * The compatibility #defines at the top map:
 *   instructions -> m65_instructions
 *   ext_instructions -> m65_ext_instructions
 */

/* Instruction lookup functions - use shared library */
static const Instruction *find_instruction(const char *mnemonic) {
    return m65_find_instruction(mnemonic);
}

static const ExtInstruction *find_ext_instruction(const char *mnemonic, AddrMode mode) {
    return m65_find_ext_instruction(mnemonic, mode);
}

/* ========================================================================== */
/* Register-targeted ALU Instructions ($02 $E8 prefix)                        */
/* ========================================================================== */
/* These use a different encoding scheme than the shared library's ExtALU,
 * so we keep local definitions for assembly purposes.
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

static const RegALUInstruction *find_regalu_instruction(const char *mnemonic) {
    for (int i = 0; regalu_instructions[i].name; i++) {
        if (strcmp(regalu_instructions[i].name, mnemonic) == 0)
            return &regalu_instructions[i];
    }
    return NULL;
}

/* ========================================================================== */
/* Shifter Instructions ($02 $98 prefix)                                      */
/* ========================================================================== */

typedef struct {
    const char *name;
    uint8_t op_code;  /* Bits 7-5 of op|cnt byte */
} ShifterInstruction;

static const ShifterInstruction shifter_instructions[] = {
    { "SHL",  0x00 },  /* Shift left logical */
    { "SHR",  0x20 },  /* Shift right logical */
    { "SAR",  0x40 },  /* Shift right arithmetic */
    { "ROL",  0x60 },  /* Rotate left */
    { "ROR",  0x80 },  /* Rotate right */
    { NULL, 0 }
};

static const ShifterInstruction *find_shifter_instruction(const char *mnemonic) {
    for (int i = 0; shifter_instructions[i].name; i++) {
        if (strcmp(shifter_instructions[i].name, mnemonic) == 0)
            return &shifter_instructions[i];
    }
    return NULL;
}

/* ========================================================================== */
/* Extend Instructions ($02 $99 prefix)                                       */
/* ========================================================================== */

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

static const ExtendInstruction *find_extend_instruction(const char *mnemonic) {
    for (int i = 0; extend_instructions[i].name; i++) {
        if (strcmp(extend_instructions[i].name, mnemonic) == 0)
            return &extend_instructions[i];
    }
    return NULL;
}

/* ========================================================================== */
/* Register Parsing                                                           */
/* ========================================================================== */

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
        if (defined && sym->defined && sym->value != value && as->pass == 1) {
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
    int b_relative;     /* Explicit B+offset syntax */
    int is_hex_literal; /* 1 if operand is a plain hex literal */
    int hex_digits;     /* Number of hex digits for plain literal */
} Operand;

static int hex_literal_digits(const char *s, int *digits) {
    const char *p = skip_whitespace((char *)s);
    int count = 0;
    if (*p == '$') {
        p++;
        if (!isxdigit((unsigned char)*p)) return 0;
        while (isxdigit((unsigned char)*p)) {
            count++;
            p++;
        }
    } else if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2;
        if (!isxdigit((unsigned char)*p)) return 0;
        while (isxdigit((unsigned char)*p)) {
            count++;
            p++;
        }
    } else {
        return 0;
    }
    p = skip_whitespace((char *)p);
    if (*p && *p != ',' && *p != ')' && *p != ']' && *p != ';') {
        return 0;
    }
    *digits = count;
    return 1;
}

static int parse_operand(Assembler *as, char *s, Operand *op) {
    char *p = skip_whitespace(s);
    op->mode = AM_IMP;
    op->value = 0;
    op->force_width = 0;
    op->mvp_dst = 0;
    op->b_relative = 0;
    op->is_hex_literal = 0;
    op->hex_digits = 0;
    
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
    if (hex_literal_digits(p, &op->hex_digits)) {
        op->is_hex_literal = 1;
    }
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

    if (as->m_flag == 2 && op->mode == AM_ABS32 && op->is_hex_literal && op->hex_digits != 8) {
        error(as, "32-bit absolute hex must use 8 digits");
        return 0;
    }
    
    return 1;
}

/* ========================================================================== */
/* Instruction Encoding                                                       */
/* ========================================================================== */

/* find_instruction and find_ext_instruction are now defined at the top
 * of the file as wrappers around the shared library functions. */

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

/* Extended ALU operations now use shared library m65_extalu_instructions table.
 * Access via m65_find_extalu_instruction() which is wrapped as find_regalu_instruction().
 * Fields: name, opcode, is_unary (1=unary like INC/DEC), allows_mem_dest */
typedef M65_ExtALUInstruction ExtALUOp;
#define ext_alu_ops m65_extalu_instructions

static const ExtALUOp *find_ext_alu_op(const char *mnemonic) {
    return m65_find_extalu_instruction(mnemonic);
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
    /* Format: FADD.S Fd, Fs  or  LDF Fn, addr  or  F2I.S Fd */
    if (strncmp(mnemonic, "FADD", 4) == 0 || strncmp(mnemonic, "FSUB", 4) == 0 ||
        strncmp(mnemonic, "FMUL", 4) == 0 || strncmp(mnemonic, "FDIV", 4) == 0 ||
        strncmp(mnemonic, "FNEG", 4) == 0 || strncmp(mnemonic, "FABS", 4) == 0 ||
        strncmp(mnemonic, "FCMP", 4) == 0 || strncmp(mnemonic, "FMOV", 4) == 0 ||
        strncmp(mnemonic, "FSQRT", 5) == 0 ||
        strncmp(mnemonic, "F2I", 3) == 0 || strncmp(mnemonic, "I2F", 3) == 0 ||
        strncmp(mnemonic, "FTOA", 4) == 0 || strncmp(mnemonic, "FTOT", 4) == 0 ||
        strncmp(mnemonic, "ATOF", 4) == 0 || strncmp(mnemonic, "TTOF", 4) == 0 ||
        strncmp(mnemonic, "FCVT", 4) == 0 ||
        strncmp(mnemonic, "LDF", 3) == 0 || strncmp(mnemonic, "STF", 3) == 0) {
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

        if (strncmp(mnemonic, "LDF", 3) == 0 || strncmp(mnemonic, "STF", 3) == 0) {
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
                ti = 0;
                while (p[ti] && p[ti] != ')' && !isspace((unsigned char)p[ti]) && ti < 15) {
                    token[ti] = p[ti];
                    ti++;
                }
                token[ti] = '\0';

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
                    uint8_t ind_opcode;
                    if (strcmp(mnemonic, "LDF.S") == 0) ind_opcode = 0xBA;
                    else if (strcmp(mnemonic, "STF.S") == 0) ind_opcode = 0xBB;
                    else ind_opcode = (strncmp(mnemonic, "LDF", 3) == 0) ? 0xB4 : 0xB5;
                    emit_byte(as, 0x02);
                    emit_byte(as, ind_opcode);
                    emit_byte(as, (uint8_t)((fd << 4) | rm));
                    return 1;
                }
                error(as, "register indirect mode requires R0-R15");
                return 0;
            }

            if (strcmp(mnemonic, "LDF.S") == 0 || strcmp(mnemonic, "STF.S") == 0) {
                error(as, "LDF.S/STF.S only support (Rm) addressing");
                return 0;
            }

            int addr_hex_digits = 0;
            int addr_is_hex = hex_literal_digits(p, &addr_hex_digits);
            uint32_t addr;
            if (!parse_expression(as, p, &addr, (const char**)&p)) {
                error(as, "expected address operand");
                return 0;
            }
            if (as->m_flag == 2 && addr > 0xFFFFFF && addr_is_hex && addr_hex_digits != 8) {
                error(as, "32-bit absolute hex must use 8 digits");
                return 0;
            }

            if (addr <= 0xFF) {
                emit_byte(as, 0x02);
                emit_byte(as, (strncmp(mnemonic, "LDF", 3) == 0) ? 0xB0 : 0xB2);
                emit_byte(as, (uint8_t)fd);
                emit_byte(as, addr & 0xFF);
                return 1;
            } else if (addr <= 0xFFFF) {
                emit_byte(as, 0x02);
                emit_byte(as, (strncmp(mnemonic, "LDF", 3) == 0) ? 0xB1 : 0xB3);
                emit_byte(as, (uint8_t)fd);
                emit_word(as, addr & 0xFFFF);
                return 1;
            } else {
                emit_byte(as, 0x02);
                emit_byte(as, (strncmp(mnemonic, "LDF", 3) == 0) ? 0xB6 : 0xB7);
                emit_byte(as, (uint8_t)fd);
                emit_quad(as, addr);
                return 1;
            }
        }

        const ExtInstruction *ext = NULL;
        for (int i = 0; ext_instructions[i].name; i++) {
            if (strcmp(ext_instructions[i].name, mnemonic) == 0) {
                ext = &ext_instructions[i];
                break;
            }
        }
        if (!ext) {
            error(as, "unknown FPU instruction");
            return 0;
        }

        if (ext->mode == AM_FPU_REG2) {
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
            emit_byte(as, 0x02);
            emit_byte(as, ext->ext_opcode);
            emit_byte(as, (uint8_t)((fd << 4) | fs));
            return 1;
        }

        if (ext->mode == AM_FPU_REG1) {
            emit_byte(as, 0x02);
            emit_byte(as, ext->ext_opcode);
            emit_byte(as, (uint8_t)(fd << 4));
            return 1;
        }
    }

    /* Extended ALU instructions ($02 $80-$97) */
    const ExtALUOp *ext_alu = find_ext_alu_op(mnemonic);
    if (ext_alu) {
        const char *p = skip_whitespace(operand);
        /* In 32-bit mode, traditional mnemonics (LDA, STA, etc.) with absolute addresses
         * must use Extended ALU since standard opcodes only support B-relative.
         * Immediate mode uses standard opcodes with 4-byte immediate values.
         * DP-based addressing modes (dp, (dp), (dp,X), (dp),Y, [dp], [dp],Y, sr, (sr,S),Y)
         * use standard opcodes -- the CPU just transfers wider data through the pointer. */
        int is_traditional_mnemonic = (strcmp(mnemonic, "LDA") == 0 || strcmp(mnemonic, "STA") == 0 ||
                                       strcmp(mnemonic, "ADC") == 0 || strcmp(mnemonic, "SBC") == 0 ||
                                       strcmp(mnemonic, "AND") == 0 || strcmp(mnemonic, "ORA") == 0 ||
                                       strcmp(mnemonic, "EOR") == 0 || strcmp(mnemonic, "CMP") == 0 ||
                                       strcmp(mnemonic, "BIT") == 0 || strcmp(mnemonic, "TSB") == 0 ||
                                       strcmp(mnemonic, "TRB") == 0 || strcmp(mnemonic, "STZ") == 0);
        /* dest_starts_reg only applies to LD/ST (register-targeted forms like "LD R4, src").
         * Traditional mnemonics (LDA, STA, etc.) always use A as implicit destination,
         * so "LDA R4" means load from DP address R4 into A — not register-targeted. */
        int dest_starts_reg = !is_traditional_mnemonic &&
                              (*p == 'A' || *p == 'a' || *p == 'R' || *p == 'r');
        int is_immediate = (*p == '#');
        /* Pre-parse operand to check addressing mode for 32-bit routing.
         * DP-based modes don't need extended ALU -- standard opcodes handle them. */
        int is_dp_mode = 0;
        if (as->m_flag == 2 && is_traditional_mnemonic && !is_immediate && !dest_starts_reg) {
            Operand pre_op;
            char *pre_operand = strdup(operand);
            if (pre_operand && parse_operand(as, pre_operand, &pre_op)) {
                if (pre_op.mode == AM_DP || pre_op.mode == AM_DPX || pre_op.mode == AM_DPY ||
                    pre_op.mode == AM_IND || pre_op.mode == AM_INDX || pre_op.mode == AM_INDY ||
                    pre_op.mode == AM_INDL || pre_op.mode == AM_INDLY ||
                    pre_op.mode == AM_SR || pre_op.mode == AM_SRIY) {
                    is_dp_mode = 1;
                }
            }
            free(pre_operand);
        }
        int use_ext_alu = (size_code >= 0 || dest_starts_reg ||
                           strcmp(mnemonic, "LD") == 0 || strcmp(mnemonic, "ST") == 0 ||
                           (as->m_flag == 2 && is_traditional_mnemonic && !is_immediate && !is_dp_mode));
        if (ext_alu->is_unary && !dest_starts_reg && size_code < 0 && !ext_alu->allows_mem_dest) {
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

            if (!ext_alu->is_unary) {
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
                    /* For store-type instructions (STA, STZ, TSB, TRB) without
                     * comma, the single operand is the memory destination and A
                     * is the implicit source.  The no-comma path above sets
                     * dest_str="A" / src_str=operand, but we need the operand
                     * as the memory destination here. */
                    if (!comma && (strcmp(mnemonic, "STA") == 0 ||
                                   strcmp(mnemonic, "STZ") == 0 ||
                                   strcmp(mnemonic, "TSB") == 0 ||
                                   strcmp(mnemonic, "TRB") == 0)) {
                        dest_str = src_str;
                        src_str = "A";
                    }
                    Operand mem_op;
                    if (!parse_operand(as, dest_str, &mem_op)) {
                        return 0;
                    }
                    /* In 32-bit mode: B+$XXXX for B-relative, otherwise 32-bit absolute */
                    int dest_is_32bit = (as->m_flag == 2 && !mem_op.b_relative);
                    /* Reject short hex literals in 32-bit mode - must use 8 digits for absolute */
                    if (as->m_flag == 2 &&
                        mem_op.is_hex_literal && mem_op.hex_digits < 8 &&
                        (mem_op.mode == AM_ABS || mem_op.mode == AM_ABSX || mem_op.mode == AM_ABSY)) {
                        error(as, "32-bit mode requires 8-digit hex for absolute address ($XXXXXXXX)");
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
                        case AM_ABSY:
                        case AM_ABS32: {
                            int use_32 = dest_is_32bit || (mem_op.mode == AM_ABS32);
                            if (mem_op.mode == AM_ABS || mem_op.mode == AM_ABS32) addr_mode = use_32 ? 0x10 : 0x08;
                            else if (mem_op.mode == AM_ABSX) addr_mode = use_32 ? 0x11 : 0x09;
                            else addr_mode = use_32 ? 0x12 : 0x0A;
                            if (use_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            int use_32 = dest_is_32bit || (mem_op.mode == AM_ABS32);
                            if (mem_op.mode == AM_ABSIND) addr_mode = use_32 ? 0x13 : 0x0B;
                            else if (mem_op.mode == AM_ABSINDX) addr_mode = use_32 ? 0x14 : 0x0C;
                            else addr_mode = use_32 ? 0x15 : 0x0D;
                            if (use_32) append_quad(operand_bytes, &operand_len, mem_op.value);
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
                /* LD/ST require a register destination (Rn), not A.
                 * Use LDA/STA for A-targeted operations. */
                if (is_ld_st && target == 0) {
                    error(as, "LD/ST require register destination (Rn), use LDA/STA for A");
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
                    /* In 32-bit mode: B+$XXXX for B-relative, otherwise 32-bit absolute */
                    int is_32bit_addr = (as->m_flag == 2 && !src_op.b_relative);
                    /* Reject short hex literals in 32-bit mode - must use 8 digits for absolute */
                    if (as->m_flag == 2 &&
                        src_op.is_hex_literal && src_op.hex_digits < 8 &&
                        (src_op.mode == AM_ABS || src_op.mode == AM_ABSX || src_op.mode == AM_ABSY)) {
                        error(as, "32-bit mode requires 8-digit hex for absolute address ($XXXXXXXX)");
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
                        case AM_ABSY:
                        case AM_ABS32: {
                            /* AM_ABS32 is always 32-bit absolute */
                            int use_32 = is_32bit_addr || (src_op.mode == AM_ABS32);
                            if (src_op.mode == AM_ABS || src_op.mode == AM_ABS32) addr_mode = use_32 ? 0x10 : 0x08;
                            else if (src_op.mode == AM_ABSX) addr_mode = use_32 ? 0x11 : 0x09;
                            else addr_mode = use_32 ? 0x12 : 0x0A;
                            if (use_32) append_quad(operand_bytes, &operand_len, src_op.value);
                            else append_word(operand_bytes, &operand_len, src_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            if (src_op.mode == AM_ABSIND) addr_mode = is_32bit_addr ? 0x13 : 0x0B;
                            else if (src_op.mode == AM_ABSINDX) addr_mode = is_32bit_addr ? 0x14 : 0x0C;
                            else addr_mode = is_32bit_addr ? 0x15 : 0x0D;
                            if (is_32bit_addr) append_quad(operand_bytes, &operand_len, src_op.value);
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
                    /* In 32-bit mode: B+$XXXX for B-relative, otherwise 32-bit absolute */
                    int mem_is_32bit = (as->m_flag == 2 && !mem_op.b_relative);
                    /* Reject short hex literals in 32-bit mode - must use 8 digits for absolute */
                    if (as->m_flag == 2 &&
                        mem_op.is_hex_literal && mem_op.hex_digits < 8 &&
                        (mem_op.mode == AM_ABS || mem_op.mode == AM_ABSX || mem_op.mode == AM_ABSY)) {
                        error(as, "32-bit mode requires 8-digit hex for absolute address ($XXXXXXXX)");
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
                        case AM_ABSY:
                        case AM_ABS32: {
                            int use_32 = mem_is_32bit || (mem_op.mode == AM_ABS32);
                            if (mem_op.mode == AM_ABS || mem_op.mode == AM_ABS32) addr_mode = use_32 ? 0x10 : 0x08;
                            else if (mem_op.mode == AM_ABSX) addr_mode = use_32 ? 0x11 : 0x09;
                            else addr_mode = use_32 ? 0x12 : 0x0A;
                            if (use_32) append_quad(operand_bytes, &operand_len, mem_op.value);
                            else append_word(operand_bytes, &operand_len, mem_op.value);
                            break;
                        }
                        case AM_ABSIND:
                        case AM_ABSINDX:
                        case AM_ABSLIND: {
                            int use_32 = mem_is_32bit || (mem_op.mode == AM_ABS32);
                            if (mem_op.mode == AM_ABSIND) addr_mode = use_32 ? 0x13 : 0x0B;
                            else if (mem_op.mode == AM_ABSINDX) addr_mode = use_32 ? 0x14 : 0x0C;
                            else addr_mode = use_32 ? 0x15 : 0x0D;
                            if (use_32) append_quad(operand_bytes, &operand_len, mem_op.value);
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
            case AM_IND:
                /* DP indirect - emit single byte */
                emit_byte(as, op.value & 0xFF);
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

    /* Handle branches specially.
     * In 32-bit mode, branch targets may be classified as AM_ABSL or AM_ABS32
     * because labels have 32-bit addresses, but branches use relative offsets. */
    if (op.mode == AM_DP || op.mode == AM_ABS ||
        (as->m_flag == 2 && (op.mode == AM_ABSL || op.mode == AM_ABS32))) {
        if (inst->opcodes[AM_REL] != 0xFF) {
            if (as->m_flag == 2) {
                /* 32-bit mode: use 16-bit relative offsets */
                int32_t offset = (int32_t)op.value - (int32_t)(as->output.pc + 3);
                if (offset < -32768 || offset > 32767) {
                    if (as->pass == 2) {
                        error(as, "branch target out of range (%d bytes)", offset);
                    }
                    /* Still emit placeholder bytes on pass 1 to keep PC in sync */
                    emit_byte(as, inst->opcodes[AM_REL]);
                    emit_word(as, 0);
                    return 1;
                }
                emit_byte(as, inst->opcodes[AM_REL]);
                emit_word(as, offset & 0xFFFF);
                return 1;
            }
            /* Convert to 8-bit relative */
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
    
    /* Check if this is a control flow instruction (uses absolute address, not B-relative) */
    int is_control_flow = (strcasecmp(mnemonic, "JSR") == 0 || strcasecmp(mnemonic, "JMP") == 0 ||
                           strcasecmp(mnemonic, "JSL") == 0 || strcasecmp(mnemonic, "JML") == 0);
    
    if (as->m_flag == 2) {
        if (mode != AM_IMM && op.value > 0xFFFF && !is_control_flow) {
            error(as, "32-bit absolute requires extended ALU");
            return 0;
        }
        /* Data access requires B+offset, but control flow uses absolute addresses */
        if (!is_control_flow &&
            (mode == AM_ABS || mode == AM_ABSX || mode == AM_ABSY ||
             mode == AM_ABSIND || mode == AM_ABSINDX || mode == AM_ABSLIND) &&
            op.value <= 0xFFFF && !op.b_relative) {
            error(as, "use B+$XXXX for 16-bit absolute in 32-bit mode");
            return 0;
        }
        if ((mode == AM_ABSL || mode == AM_ABSLX || mode == AM_ABSLIND) && !is_control_flow) {
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
    
    /* In 32-bit mode, JSR/JMP with 32-bit addresses use AM_ABS opcode
     * but emit 4-byte operand (handled in emit path below). Promote
     * AM_ABS32/AM_ABSL to AM_ABS for control flow instructions. */
    if (as->m_flag == 2 && is_control_flow &&
        (mode == AM_ABS32 || mode == AM_ABSL)) {
        mode = AM_ABS;
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
                if (size == 1 && op.value > 0xFF) {
                    error(as, "immediate too large for 8-bit");
                    return 0;
                }
                if (size == 2 && op.value > 0xFFFF) {
                    error(as, "immediate too large for 16-bit");
                    return 0;
                }
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
            /* Control flow in 32-bit mode uses 32-bit absolute addresses */
            if (is_control_flow && as->m_flag == 2) {
                emit_quad(as, op.value);
            } else {
                emit_word(as, op.value & 0xFFFF);
            }
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
        /* Check for address overlap - new org must not be less than current PC */
        uint32_t current = get_pc(as);
        if (value < current && as->pass == 2) {
            error(as, ".ORG $%04X overlaps with previous code ending at $%04X", value, current);
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
                emit_quad(as, value);
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
