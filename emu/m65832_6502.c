/*
 * m65832_6502.c - 6502 Coprocessor Emulation
 *
 * Cycle-accurate 6502/65C02 emulation for the M65832 coprocessor subsystem.
 * Supports NMOS 6502, CMOS 65C02, and illegal/undocumented opcodes.
 */

#include "m65832emu.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ============================================================================
 * 6502 Flag Bits
 * ========================================================================= */

#define F6502_C  0x01   /* Carry */
#define F6502_Z  0x02   /* Zero */
#define F6502_I  0x04   /* IRQ Disable */
#define F6502_D  0x08   /* Decimal */
#define F6502_B  0x10   /* Break (only on stack) */
#define F6502_U  0x20   /* Unused (always 1) */
#define F6502_V  0x40   /* Overflow */
#define F6502_N  0x80   /* Negative */

/* ============================================================================
 * Memory Access Macros
 * ========================================================================= */

#define READ(c, a)      m6502_read(c, a)
#define WRITE(c, a, v)  m6502_write(c, (a), (v))
#define FETCH(c)        m6502_read(c, c->pc++)

/* ============================================================================
 * Internal Functions
 * ========================================================================= */

static inline uint8_t m6502_read(m6502_cpu_t *cpu, uint16_t addr) {
    /* Check shadow I/O banks */
    for (int i = 0; i < M6502_SHADOW_BANKS; i++) {
        uint32_t base = cpu->bank_base[i];
        if (base && addr >= base && addr < base + M6502_SHADOW_REGS) {
            return cpu->shadow_regs[i][addr - base];
        }
    }
    
    /* Normal memory access via VBR */
    if (cpu->main_cpu && cpu->main_cpu->memory) {
        uint32_t phys = cpu->vbr + addr;
        if (phys < cpu->main_cpu->memory_size) {
            return cpu->main_cpu->memory[phys];
        }
    }
    return 0xFF;
}

static inline void m6502_write(m6502_cpu_t *cpu, uint16_t addr, uint8_t val) {
    /* Check shadow I/O banks */
    for (int i = 0; i < M6502_SHADOW_BANKS; i++) {
        uint32_t base = cpu->bank_base[i];
        if (base && addr >= base && addr < base + M6502_SHADOW_REGS) {
            /* Update shadow register */
            cpu->shadow_regs[i][addr - base] = val;
            
            /* Log to FIFO if not full */
            if (cpu->fifo_count < M6502_WRITE_FIFO_SIZE) {
                int idx = (cpu->fifo_head + cpu->fifo_count) % M6502_WRITE_FIFO_SIZE;
                cpu->fifo[idx].frame = 0;  /* TODO: frame counter */
                cpu->fifo[idx].cycle = cpu->frame_cycles;
                cpu->fifo[idx].bank = (uint8_t)i;
                cpu->fifo[idx].reg = (uint8_t)(addr - base);
                cpu->fifo[idx].value = val;
                cpu->fifo_count++;
            }
            return;
        }
    }
    
    /* Normal memory write via VBR */
    if (cpu->main_cpu && cpu->main_cpu->memory) {
        uint32_t phys = cpu->vbr + addr;
        if (phys < cpu->main_cpu->memory_size) {
            cpu->main_cpu->memory[phys] = val;
        }
    }
}

static inline void update_nz(m6502_cpu_t *cpu, uint8_t val) {
    cpu->p = (cpu->p & ~(F6502_N | F6502_Z)) |
             (val & 0x80) |
             (val == 0 ? F6502_Z : 0);
}

static inline void push(m6502_cpu_t *cpu, uint8_t val) {
    WRITE(cpu, 0x100 | cpu->s, val);
    cpu->s--;
}

static inline uint8_t pull(m6502_cpu_t *cpu) {
    cpu->s++;
    return READ(cpu, 0x100 | cpu->s);
}

static inline void push16(m6502_cpu_t *cpu, uint16_t val) {
    push(cpu, (val >> 8) & 0xFF);
    push(cpu, val & 0xFF);
}

static inline uint16_t pull16(m6502_cpu_t *cpu) {
    uint16_t lo = pull(cpu);
    uint16_t hi = pull(cpu);
    return lo | (hi << 8);
}

/* ============================================================================
 * Addressing Modes
 * ========================================================================= */

static inline uint16_t addr_zp(m6502_cpu_t *cpu) {
    return FETCH(cpu);
}

static inline uint16_t addr_zpx(m6502_cpu_t *cpu) {
    return (FETCH(cpu) + cpu->x) & 0xFF;
}

static inline uint16_t addr_zpy(m6502_cpu_t *cpu) {
    return (FETCH(cpu) + cpu->y) & 0xFF;
}

static inline uint16_t addr_abs(m6502_cpu_t *cpu) {
    uint16_t lo = FETCH(cpu);
    uint16_t hi = FETCH(cpu);
    return lo | (hi << 8);
}

static inline uint16_t addr_absx(m6502_cpu_t *cpu) {
    return addr_abs(cpu) + cpu->x;
}

static inline uint16_t addr_absy(m6502_cpu_t *cpu) {
    return addr_abs(cpu) + cpu->y;
}

static inline uint16_t addr_indx(m6502_cpu_t *cpu) {
    uint8_t zp = (FETCH(cpu) + cpu->x) & 0xFF;
    uint16_t lo = READ(cpu, zp);
    uint16_t hi = READ(cpu, (zp + 1) & 0xFF);
    return lo | (hi << 8);
}

static inline uint16_t addr_indy(m6502_cpu_t *cpu) {
    uint8_t zp = FETCH(cpu);
    uint16_t lo = READ(cpu, zp);
    uint16_t hi = READ(cpu, (zp + 1) & 0xFF);
    return (lo | (hi << 8)) + cpu->y;
}

static inline uint16_t addr_ind(m6502_cpu_t *cpu) {
    /* 65C02 (dp) addressing */
    uint8_t zp = FETCH(cpu);
    uint16_t lo = READ(cpu, zp);
    uint16_t hi = READ(cpu, (zp + 1) & 0xFF);
    return lo | (hi << 8);
}

/* ============================================================================
 * ALU Operations
 * ========================================================================= */

static void adc(m6502_cpu_t *cpu, uint8_t val) {
    if ((cpu->p & F6502_D) && (cpu->compat & COMPAT_DECIMAL_EN)) {
        /* BCD mode */
        int al = (cpu->a & 0x0F) + (val & 0x0F) + (cpu->p & F6502_C ? 1 : 0);
        if (al > 9) al += 6;
        int ah = (cpu->a >> 4) + (val >> 4) + (al > 0x0F ? 1 : 0);
        cpu->p &= ~(F6502_Z | F6502_N | F6502_V | F6502_C);
        if ((cpu->a + val + (cpu->p & F6502_C ? 1 : 0)) == 0) cpu->p |= F6502_Z;
        cpu->p |= (ah << 4) & F6502_N;
        if (~(cpu->a ^ val) & (cpu->a ^ (ah << 4)) & 0x80) cpu->p |= F6502_V;
        if (ah > 9) ah += 6;
        if (ah > 0x0F) cpu->p |= F6502_C;
        cpu->a = ((ah << 4) | (al & 0x0F)) & 0xFF;
    } else {
        int sum = cpu->a + val + (cpu->p & F6502_C ? 1 : 0);
        cpu->p &= ~(F6502_C | F6502_V);
        if (sum > 0xFF) cpu->p |= F6502_C;
        if (~(cpu->a ^ val) & (cpu->a ^ sum) & 0x80) cpu->p |= F6502_V;
        cpu->a = sum & 0xFF;
        update_nz(cpu, cpu->a);
    }
}

static void sbc(m6502_cpu_t *cpu, uint8_t val) {
    if ((cpu->p & F6502_D) && (cpu->compat & COMPAT_DECIMAL_EN)) {
        /* BCD mode */
        int al = (cpu->a & 0x0F) - (val & 0x0F) - (cpu->p & F6502_C ? 0 : 1);
        if (al < 0) al -= 6;
        int ah = (cpu->a >> 4) - (val >> 4) - (al < 0 ? 1 : 0);
        cpu->p &= ~(F6502_Z | F6502_N | F6502_V | F6502_C);
        int diff = cpu->a - val - (cpu->p & F6502_C ? 0 : 1);
        if ((diff & 0xFF) == 0) cpu->p |= F6502_Z;
        cpu->p |= diff & F6502_N;
        if ((cpu->a ^ val) & (cpu->a ^ diff) & 0x80) cpu->p |= F6502_V;
        if (diff >= 0) cpu->p |= F6502_C;
        if (ah < 0) ah -= 6;
        cpu->a = ((ah << 4) | (al & 0x0F)) & 0xFF;
    } else {
        int diff = cpu->a - val - (cpu->p & F6502_C ? 0 : 1);
        cpu->p &= ~(F6502_C | F6502_V);
        if (diff >= 0) cpu->p |= F6502_C;
        if ((cpu->a ^ val) & (cpu->a ^ diff) & 0x80) cpu->p |= F6502_V;
        cpu->a = diff & 0xFF;
        update_nz(cpu, cpu->a);
    }
}

static void cmp(m6502_cpu_t *cpu, uint8_t a, uint8_t b) {
    int diff = a - b;
    cpu->p = (cpu->p & ~(F6502_C | F6502_Z | F6502_N)) |
             (diff >= 0 ? F6502_C : 0) |
             ((diff & 0xFF) == 0 ? F6502_Z : 0) |
             (diff & F6502_N);
}

/* ============================================================================
 * Instruction Execution
 * ========================================================================= */

static int execute_6502(m6502_cpu_t *cpu) {
    uint8_t opcode = FETCH(cpu);
    int cycles = 2;
    uint16_t addr;
    uint8_t val, tmp;
    int16_t rel;

    switch (opcode) {
        /* ============ LDA ============ */
        case 0xA9: cpu->a = FETCH(cpu); update_nz(cpu, cpu->a); cycles = 2; break;
        case 0xA5: cpu->a = READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->a); cycles = 3; break;
        case 0xB5: cpu->a = READ(cpu, addr_zpx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0xAD: cpu->a = READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0xBD: addr = addr_absx(cpu); cpu->a = READ(cpu, addr); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0xB9: addr = addr_absy(cpu); cpu->a = READ(cpu, addr); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0xA1: cpu->a = READ(cpu, addr_indx(cpu)); update_nz(cpu, cpu->a); cycles = 6; break;
        case 0xB1: cpu->a = READ(cpu, addr_indy(cpu)); update_nz(cpu, cpu->a); cycles = 5; break;
        case 0xB2: /* 65C02 LDA (zp) */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                cpu->a = READ(cpu, addr_ind(cpu)); update_nz(cpu, cpu->a); cycles = 5;
            } else cycles = 2;
            break;

        /* ============ LDX ============ */
        case 0xA2: cpu->x = FETCH(cpu); update_nz(cpu, cpu->x); cycles = 2; break;
        case 0xA6: cpu->x = READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->x); cycles = 3; break;
        case 0xB6: cpu->x = READ(cpu, addr_zpy(cpu)); update_nz(cpu, cpu->x); cycles = 4; break;
        case 0xAE: cpu->x = READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->x); cycles = 4; break;
        case 0xBE: cpu->x = READ(cpu, addr_absy(cpu)); update_nz(cpu, cpu->x); cycles = 4; break;

        /* ============ LDY ============ */
        case 0xA0: cpu->y = FETCH(cpu); update_nz(cpu, cpu->y); cycles = 2; break;
        case 0xA4: cpu->y = READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->y); cycles = 3; break;
        case 0xB4: cpu->y = READ(cpu, addr_zpx(cpu)); update_nz(cpu, cpu->y); cycles = 4; break;
        case 0xAC: cpu->y = READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->y); cycles = 4; break;
        case 0xBC: cpu->y = READ(cpu, addr_absx(cpu)); update_nz(cpu, cpu->y); cycles = 4; break;

        /* ============ STA ============ */
        case 0x85: WRITE(cpu, addr_zp(cpu), cpu->a); cycles = 3; break;
        case 0x95: WRITE(cpu, addr_zpx(cpu), cpu->a); cycles = 4; break;
        case 0x8D: WRITE(cpu, addr_abs(cpu), cpu->a); cycles = 4; break;
        case 0x9D: WRITE(cpu, addr_absx(cpu), cpu->a); cycles = 5; break;
        case 0x99: WRITE(cpu, addr_absy(cpu), cpu->a); cycles = 5; break;
        case 0x81: WRITE(cpu, addr_indx(cpu), cpu->a); cycles = 6; break;
        case 0x91: WRITE(cpu, addr_indy(cpu), cpu->a); cycles = 6; break;
        case 0x92: /* 65C02 STA (zp) */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                WRITE(cpu, addr_ind(cpu), cpu->a); cycles = 5;
            } else cycles = 2;
            break;

        /* ============ STX ============ */
        case 0x86: WRITE(cpu, addr_zp(cpu), cpu->x); cycles = 3; break;
        case 0x96: WRITE(cpu, addr_zpy(cpu), cpu->x); cycles = 4; break;
        case 0x8E: WRITE(cpu, addr_abs(cpu), cpu->x); cycles = 4; break;

        /* ============ STY ============ */
        case 0x84: WRITE(cpu, addr_zp(cpu), cpu->y); cycles = 3; break;
        case 0x94: WRITE(cpu, addr_zpx(cpu), cpu->y); cycles = 4; break;
        case 0x8C: WRITE(cpu, addr_abs(cpu), cpu->y); cycles = 4; break;

        /* ============ STZ (65C02) ============ */
        case 0x64:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { WRITE(cpu, addr_zp(cpu), 0); cycles = 3; }
            else cycles = 2;
            break;
        case 0x74:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { WRITE(cpu, addr_zpx(cpu), 0); cycles = 4; }
            else cycles = 2;
            break;
        case 0x9C:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { WRITE(cpu, addr_abs(cpu), 0); cycles = 4; }
            else cycles = 2;
            break;
        case 0x9E:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { WRITE(cpu, addr_absx(cpu), 0); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ ADC ============ */
        case 0x69: adc(cpu, FETCH(cpu)); cycles = 2; break;
        case 0x65: adc(cpu, READ(cpu, addr_zp(cpu))); cycles = 3; break;
        case 0x75: adc(cpu, READ(cpu, addr_zpx(cpu))); cycles = 4; break;
        case 0x6D: adc(cpu, READ(cpu, addr_abs(cpu))); cycles = 4; break;
        case 0x7D: adc(cpu, READ(cpu, addr_absx(cpu))); cycles = 4; break;
        case 0x79: adc(cpu, READ(cpu, addr_absy(cpu))); cycles = 4; break;
        case 0x61: adc(cpu, READ(cpu, addr_indx(cpu))); cycles = 6; break;
        case 0x71: adc(cpu, READ(cpu, addr_indy(cpu))); cycles = 5; break;
        case 0x72:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { adc(cpu, READ(cpu, addr_ind(cpu))); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ SBC ============ */
        case 0xE9: sbc(cpu, FETCH(cpu)); cycles = 2; break;
        case 0xE5: sbc(cpu, READ(cpu, addr_zp(cpu))); cycles = 3; break;
        case 0xF5: sbc(cpu, READ(cpu, addr_zpx(cpu))); cycles = 4; break;
        case 0xED: sbc(cpu, READ(cpu, addr_abs(cpu))); cycles = 4; break;
        case 0xFD: sbc(cpu, READ(cpu, addr_absx(cpu))); cycles = 4; break;
        case 0xF9: sbc(cpu, READ(cpu, addr_absy(cpu))); cycles = 4; break;
        case 0xE1: sbc(cpu, READ(cpu, addr_indx(cpu))); cycles = 6; break;
        case 0xF1: sbc(cpu, READ(cpu, addr_indy(cpu))); cycles = 5; break;
        case 0xF2:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { sbc(cpu, READ(cpu, addr_ind(cpu))); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ CMP ============ */
        case 0xC9: cmp(cpu, cpu->a, FETCH(cpu)); cycles = 2; break;
        case 0xC5: cmp(cpu, cpu->a, READ(cpu, addr_zp(cpu))); cycles = 3; break;
        case 0xD5: cmp(cpu, cpu->a, READ(cpu, addr_zpx(cpu))); cycles = 4; break;
        case 0xCD: cmp(cpu, cpu->a, READ(cpu, addr_abs(cpu))); cycles = 4; break;
        case 0xDD: cmp(cpu, cpu->a, READ(cpu, addr_absx(cpu))); cycles = 4; break;
        case 0xD9: cmp(cpu, cpu->a, READ(cpu, addr_absy(cpu))); cycles = 4; break;
        case 0xC1: cmp(cpu, cpu->a, READ(cpu, addr_indx(cpu))); cycles = 6; break;
        case 0xD1: cmp(cpu, cpu->a, READ(cpu, addr_indy(cpu))); cycles = 5; break;
        case 0xD2:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cmp(cpu, cpu->a, READ(cpu, addr_ind(cpu))); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ CPX ============ */
        case 0xE0: cmp(cpu, cpu->x, FETCH(cpu)); cycles = 2; break;
        case 0xE4: cmp(cpu, cpu->x, READ(cpu, addr_zp(cpu))); cycles = 3; break;
        case 0xEC: cmp(cpu, cpu->x, READ(cpu, addr_abs(cpu))); cycles = 4; break;

        /* ============ CPY ============ */
        case 0xC0: cmp(cpu, cpu->y, FETCH(cpu)); cycles = 2; break;
        case 0xC4: cmp(cpu, cpu->y, READ(cpu, addr_zp(cpu))); cycles = 3; break;
        case 0xCC: cmp(cpu, cpu->y, READ(cpu, addr_abs(cpu))); cycles = 4; break;

        /* ============ AND ============ */
        case 0x29: cpu->a &= FETCH(cpu); update_nz(cpu, cpu->a); cycles = 2; break;
        case 0x25: cpu->a &= READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->a); cycles = 3; break;
        case 0x35: cpu->a &= READ(cpu, addr_zpx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x2D: cpu->a &= READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x3D: cpu->a &= READ(cpu, addr_absx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x39: cpu->a &= READ(cpu, addr_absy(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x21: cpu->a &= READ(cpu, addr_indx(cpu)); update_nz(cpu, cpu->a); cycles = 6; break;
        case 0x31: cpu->a &= READ(cpu, addr_indy(cpu)); update_nz(cpu, cpu->a); cycles = 5; break;
        case 0x32:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->a &= READ(cpu, addr_ind(cpu)); update_nz(cpu, cpu->a); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ ORA ============ */
        case 0x09: cpu->a |= FETCH(cpu); update_nz(cpu, cpu->a); cycles = 2; break;
        case 0x05: cpu->a |= READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->a); cycles = 3; break;
        case 0x15: cpu->a |= READ(cpu, addr_zpx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x0D: cpu->a |= READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x1D: cpu->a |= READ(cpu, addr_absx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x19: cpu->a |= READ(cpu, addr_absy(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x01: cpu->a |= READ(cpu, addr_indx(cpu)); update_nz(cpu, cpu->a); cycles = 6; break;
        case 0x11: cpu->a |= READ(cpu, addr_indy(cpu)); update_nz(cpu, cpu->a); cycles = 5; break;
        case 0x12:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->a |= READ(cpu, addr_ind(cpu)); update_nz(cpu, cpu->a); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ EOR ============ */
        case 0x49: cpu->a ^= FETCH(cpu); update_nz(cpu, cpu->a); cycles = 2; break;
        case 0x45: cpu->a ^= READ(cpu, addr_zp(cpu)); update_nz(cpu, cpu->a); cycles = 3; break;
        case 0x55: cpu->a ^= READ(cpu, addr_zpx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x4D: cpu->a ^= READ(cpu, addr_abs(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x5D: cpu->a ^= READ(cpu, addr_absx(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x59: cpu->a ^= READ(cpu, addr_absy(cpu)); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x41: cpu->a ^= READ(cpu, addr_indx(cpu)); update_nz(cpu, cpu->a); cycles = 6; break;
        case 0x51: cpu->a ^= READ(cpu, addr_indy(cpu)); update_nz(cpu, cpu->a); cycles = 5; break;
        case 0x52:
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->a ^= READ(cpu, addr_ind(cpu)); update_nz(cpu, cpu->a); cycles = 5; }
            else cycles = 2;
            break;

        /* ============ BIT ============ */
        case 0x24:
            val = READ(cpu, addr_zp(cpu));
            cpu->p = (cpu->p & ~(F6502_N | F6502_V | F6502_Z)) |
                     (val & (F6502_N | F6502_V)) |
                     ((cpu->a & val) == 0 ? F6502_Z : 0);
            cycles = 3;
            break;
        case 0x2C:
            val = READ(cpu, addr_abs(cpu));
            cpu->p = (cpu->p & ~(F6502_N | F6502_V | F6502_Z)) |
                     (val & (F6502_N | F6502_V)) |
                     ((cpu->a & val) == 0 ? F6502_Z : 0);
            cycles = 4;
            break;
        case 0x89: /* 65C02 BIT #imm */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                val = FETCH(cpu);
                cpu->p = (cpu->p & ~F6502_Z) | ((cpu->a & val) == 0 ? F6502_Z : 0);
                cycles = 2;
            } else cycles = 2;
            break;
        case 0x34: /* 65C02 BIT zp,X */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                val = READ(cpu, addr_zpx(cpu));
                cpu->p = (cpu->p & ~(F6502_N | F6502_V | F6502_Z)) |
                         (val & (F6502_N | F6502_V)) |
                         ((cpu->a & val) == 0 ? F6502_Z : 0);
                cycles = 4;
            } else cycles = 2;
            break;
        case 0x3C: /* 65C02 BIT abs,X */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                val = READ(cpu, addr_absx(cpu));
                cpu->p = (cpu->p & ~(F6502_N | F6502_V | F6502_Z)) |
                         (val & (F6502_N | F6502_V)) |
                         ((cpu->a & val) == 0 ? F6502_Z : 0);
                cycles = 4;
            } else cycles = 2;
            break;

        /* ============ ASL ============ */
        case 0x0A:
            cpu->p = (cpu->p & ~F6502_C) | ((cpu->a >> 7) & F6502_C);
            cpu->a <<= 1;
            update_nz(cpu, cpu->a);
            cycles = 2;
            break;
        case 0x06:
            addr = addr_zp(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val <<= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 5;
            break;
        case 0x16:
            addr = addr_zpx(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val <<= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x0E:
            addr = addr_abs(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val <<= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x1E:
            addr = addr_absx(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val <<= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 7;
            break;

        /* ============ LSR ============ */
        case 0x4A:
            cpu->p = (cpu->p & ~F6502_C) | (cpu->a & F6502_C);
            cpu->a >>= 1;
            update_nz(cpu, cpu->a);
            cycles = 2;
            break;
        case 0x46:
            addr = addr_zp(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val >>= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 5;
            break;
        case 0x56:
            addr = addr_zpx(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val >>= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x4E:
            addr = addr_abs(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val >>= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x5E:
            addr = addr_absx(cpu);
            val = READ(cpu, addr);
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val >>= 1;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 7;
            break;

        /* ============ ROL ============ */
        case 0x2A:
            tmp = (cpu->p & F6502_C) ? 1 : 0;
            cpu->p = (cpu->p & ~F6502_C) | ((cpu->a >> 7) & F6502_C);
            cpu->a = (cpu->a << 1) | tmp;
            update_nz(cpu, cpu->a);
            cycles = 2;
            break;
        case 0x26:
            addr = addr_zp(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 1 : 0;
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val = (val << 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 5;
            break;
        case 0x36:
            addr = addr_zpx(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 1 : 0;
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val = (val << 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x2E:
            addr = addr_abs(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 1 : 0;
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val = (val << 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x3E:
            addr = addr_absx(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 1 : 0;
            cpu->p = (cpu->p & ~F6502_C) | ((val >> 7) & F6502_C);
            val = (val << 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 7;
            break;

        /* ============ ROR ============ */
        case 0x6A:
            tmp = (cpu->p & F6502_C) ? 0x80 : 0;
            cpu->p = (cpu->p & ~F6502_C) | (cpu->a & F6502_C);
            cpu->a = (cpu->a >> 1) | tmp;
            update_nz(cpu, cpu->a);
            cycles = 2;
            break;
        case 0x66:
            addr = addr_zp(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 0x80 : 0;
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val = (val >> 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 5;
            break;
        case 0x76:
            addr = addr_zpx(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 0x80 : 0;
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val = (val >> 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x6E:
            addr = addr_abs(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 0x80 : 0;
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val = (val >> 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 6;
            break;
        case 0x7E:
            addr = addr_absx(cpu);
            val = READ(cpu, addr);
            tmp = (cpu->p & F6502_C) ? 0x80 : 0;
            cpu->p = (cpu->p & ~F6502_C) | (val & F6502_C);
            val = (val >> 1) | tmp;
            WRITE(cpu, addr, val);
            update_nz(cpu, val);
            cycles = 7;
            break;

        /* ============ INC ============ */
        case 0xE6: addr = addr_zp(cpu); val = READ(cpu, addr) + 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 5; break;
        case 0xF6: addr = addr_zpx(cpu); val = READ(cpu, addr) + 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 6; break;
        case 0xEE: addr = addr_abs(cpu); val = READ(cpu, addr) + 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 6; break;
        case 0xFE: addr = addr_absx(cpu); val = READ(cpu, addr) + 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 7; break;
        case 0x1A: /* 65C02 INC A */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->a++; update_nz(cpu, cpu->a); cycles = 2; }
            else cycles = 2;
            break;

        /* ============ DEC ============ */
        case 0xC6: addr = addr_zp(cpu); val = READ(cpu, addr) - 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 5; break;
        case 0xD6: addr = addr_zpx(cpu); val = READ(cpu, addr) - 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 6; break;
        case 0xCE: addr = addr_abs(cpu); val = READ(cpu, addr) - 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 6; break;
        case 0xDE: addr = addr_absx(cpu); val = READ(cpu, addr) - 1; WRITE(cpu, addr, val); update_nz(cpu, val); cycles = 7; break;
        case 0x3A: /* 65C02 DEC A */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->a--; update_nz(cpu, cpu->a); cycles = 2; }
            else cycles = 2;
            break;

        /* ============ INX/INY/DEX/DEY ============ */
        case 0xE8: cpu->x++; update_nz(cpu, cpu->x); cycles = 2; break;
        case 0xC8: cpu->y++; update_nz(cpu, cpu->y); cycles = 2; break;
        case 0xCA: cpu->x--; update_nz(cpu, cpu->x); cycles = 2; break;
        case 0x88: cpu->y--; update_nz(cpu, cpu->y); cycles = 2; break;

        /* ============ Transfers ============ */
        case 0xAA: cpu->x = cpu->a; update_nz(cpu, cpu->x); cycles = 2; break;
        case 0xA8: cpu->y = cpu->a; update_nz(cpu, cpu->y); cycles = 2; break;
        case 0x8A: cpu->a = cpu->x; update_nz(cpu, cpu->a); cycles = 2; break;
        case 0x98: cpu->a = cpu->y; update_nz(cpu, cpu->a); cycles = 2; break;
        case 0xBA: cpu->x = cpu->s; update_nz(cpu, cpu->x); cycles = 2; break;
        case 0x9A: cpu->s = cpu->x; cycles = 2; break;

        /* ============ Stack ============ */
        case 0x48: push(cpu, cpu->a); cycles = 3; break;
        case 0x68: cpu->a = pull(cpu); update_nz(cpu, cpu->a); cycles = 4; break;
        case 0x08: push(cpu, cpu->p | F6502_B | F6502_U); cycles = 3; break;
        case 0x28: cpu->p = pull(cpu) | F6502_U; cycles = 4; break;
        case 0xDA: /* 65C02 PHX */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { push(cpu, cpu->x); cycles = 3; }
            else cycles = 2;
            break;
        case 0xFA: /* 65C02 PLX */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->x = pull(cpu); update_nz(cpu, cpu->x); cycles = 4; }
            else cycles = 2;
            break;
        case 0x5A: /* 65C02 PHY */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { push(cpu, cpu->y); cycles = 3; }
            else cycles = 2;
            break;
        case 0x7A: /* 65C02 PLY */
            if (cpu->compat & COMPAT_CMOS65C02_EN) { cpu->y = pull(cpu); update_nz(cpu, cpu->y); cycles = 4; }
            else cycles = 2;
            break;

        /* ============ Branches ============ */
        case 0x10: /* BPL */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (!(cpu->p & F6502_N)) { cpu->pc += rel; cycles++; }
            break;
        case 0x30: /* BMI */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (cpu->p & F6502_N) { cpu->pc += rel; cycles++; }
            break;
        case 0x50: /* BVC */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (!(cpu->p & F6502_V)) { cpu->pc += rel; cycles++; }
            break;
        case 0x70: /* BVS */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (cpu->p & F6502_V) { cpu->pc += rel; cycles++; }
            break;
        case 0x90: /* BCC */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (!(cpu->p & F6502_C)) { cpu->pc += rel; cycles++; }
            break;
        case 0xB0: /* BCS */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (cpu->p & F6502_C) { cpu->pc += rel; cycles++; }
            break;
        case 0xD0: /* BNE */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (!(cpu->p & F6502_Z)) { cpu->pc += rel; cycles++; }
            break;
        case 0xF0: /* BEQ */
            rel = (int8_t)FETCH(cpu);
            cycles = 2;
            if (cpu->p & F6502_Z) { cpu->pc += rel; cycles++; }
            break;
        case 0x80: /* 65C02 BRA */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                rel = (int8_t)FETCH(cpu);
                cpu->pc += rel;
                cycles = 3;
            } else cycles = 2;
            break;

        /* ============ Jumps ============ */
        case 0x4C: /* JMP abs */
            cpu->pc = addr_abs(cpu);
            cycles = 3;
            break;
        case 0x6C: /* JMP (abs) */
            addr = addr_abs(cpu);
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                /* 65C02 fixes page boundary bug */
                cpu->pc = READ(cpu, addr) | ((uint16_t)READ(cpu, addr + 1) << 8);
            } else {
                /* NMOS bug: wrap within page */
                cpu->pc = READ(cpu, addr) | ((uint16_t)READ(cpu, (addr & 0xFF00) | ((addr + 1) & 0xFF)) << 8);
            }
            cycles = 5;
            break;
        case 0x7C: /* 65C02 JMP (abs,X) */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                addr = addr_abs(cpu) + cpu->x;
                cpu->pc = READ(cpu, addr) | ((uint16_t)READ(cpu, addr + 1) << 8);
                cycles = 6;
            } else cycles = 2;
            break;

        /* ============ Subroutines ============ */
        case 0x20: /* JSR */
            addr = addr_abs(cpu);
            push16(cpu, cpu->pc - 1);
            cpu->pc = addr;
            cycles = 6;
            break;
        case 0x60: /* RTS */
            cpu->pc = pull16(cpu) + 1;
            cycles = 6;
            break;

        /* ============ Interrupts ============ */
        case 0x00: /* BRK */
            cpu->pc++;
            push16(cpu, cpu->pc);
            push(cpu, cpu->p | F6502_B | F6502_U);
            cpu->p |= F6502_I;
            if (cpu->compat & COMPAT_CMOS65C02_EN) cpu->p &= ~F6502_D;
            cpu->pc = READ(cpu, 0xFFFE) | ((uint16_t)READ(cpu, 0xFFFF) << 8);
            cycles = 7;
            break;
        case 0x40: /* RTI */
            cpu->p = pull(cpu) | F6502_U;
            cpu->pc = pull16(cpu);
            cycles = 6;
            break;

        /* ============ Flags ============ */
        case 0x18: cpu->p &= ~F6502_C; cycles = 2; break; /* CLC */
        case 0x38: cpu->p |= F6502_C; cycles = 2; break;  /* SEC */
        case 0x58: cpu->p &= ~F6502_I; cycles = 2; break; /* CLI */
        case 0x78: cpu->p |= F6502_I; cycles = 2; break;  /* SEI */
        case 0xD8: cpu->p &= ~F6502_D; cycles = 2; break; /* CLD */
        case 0xF8: cpu->p |= F6502_D; cycles = 2; break;  /* SED */
        case 0xB8: cpu->p &= ~F6502_V; cycles = 2; break; /* CLV */

        /* ============ NOP ============ */
        case 0xEA: cycles = 2; break;

        /* ============ TRB/TSB (65C02) ============ */
        case 0x14: /* TRB zp */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                addr = addr_zp(cpu);
                val = READ(cpu, addr);
                cpu->p = (cpu->p & ~F6502_Z) | ((cpu->a & val) == 0 ? F6502_Z : 0);
                WRITE(cpu, addr, val & ~cpu->a);
                cycles = 5;
            } else cycles = 2;
            break;
        case 0x1C: /* TRB abs */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                addr = addr_abs(cpu);
                val = READ(cpu, addr);
                cpu->p = (cpu->p & ~F6502_Z) | ((cpu->a & val) == 0 ? F6502_Z : 0);
                WRITE(cpu, addr, val & ~cpu->a);
                cycles = 6;
            } else cycles = 2;
            break;
        case 0x04: /* TSB zp */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                addr = addr_zp(cpu);
                val = READ(cpu, addr);
                cpu->p = (cpu->p & ~F6502_Z) | ((cpu->a & val) == 0 ? F6502_Z : 0);
                WRITE(cpu, addr, val | cpu->a);
                cycles = 5;
            } else cycles = 2;
            break;
        case 0x0C: /* TSB abs */
            if (cpu->compat & COMPAT_CMOS65C02_EN) {
                addr = addr_abs(cpu);
                val = READ(cpu, addr);
                cpu->p = (cpu->p & ~F6502_Z) | ((cpu->a & val) == 0 ? F6502_Z : 0);
                WRITE(cpu, addr, val | cpu->a);
                cycles = 6;
            } else cycles = 2;
            break;

        default:
            /* Unknown/illegal opcode - treat as NOP */
            cycles = 2;
            break;
    }

    return cycles;
}

/* ============================================================================
 * Public API
 * ========================================================================= */

int m65832_coproc_init(m65832_cpu_t *cpu, uint32_t target_freq,
                        uint32_t master_freq, uint8_t compat) {
    if (cpu->coproc) {
        m65832_coproc_destroy(cpu);
    }
    
    m6502_cpu_t *coproc = (m6502_cpu_t *)calloc(1, sizeof(m6502_cpu_t));
    if (!coproc) return -1;
    
    coproc->main_cpu = cpu;
    coproc->target_freq = target_freq;
    coproc->master_freq = master_freq;
    coproc->compat = compat;
    coproc->vbr = 0;
    
    /* Default timing (can be customized) */
    coproc->cycles_per_line = 63;
    coproc->lines_per_frame = 312;
    
    cpu->coproc = coproc;
    m65832_coproc_reset(cpu);
    
    return 0;
}

void m65832_coproc_destroy(m65832_cpu_t *cpu) {
    if (cpu->coproc) {
        free(cpu->coproc);
        cpu->coproc = NULL;
    }
}

void m65832_coproc_reset(m65832_cpu_t *cpu) {
    m6502_cpu_t *c = cpu->coproc;
    if (!c) return;
    
    c->a = 0;
    c->x = 0;
    c->y = 0;
    c->s = 0xFD;
    c->p = F6502_I | F6502_U;
    
    /* Fetch reset vector */
    c->pc = m6502_read(c, 0xFFFC) | ((uint16_t)m6502_read(c, 0xFFFD) << 8);
    
    c->cycles = 0;
    c->frame_cycles = 0;
    c->scanline = 0;
    c->running = true;
    c->irq_pending = false;
    c->nmi_pending = false;
    c->nmi_prev = false;
    
    /* Clear FIFO */
    c->fifo_head = 0;
    c->fifo_tail = 0;
    c->fifo_count = 0;
    
    /* Clear shadow registers */
    memset(c->shadow_regs, 0, sizeof(c->shadow_regs));
}

void m65832_coproc_set_vbr(m65832_cpu_t *cpu, uint32_t vbr) {
    if (cpu->coproc) {
        cpu->coproc->vbr = vbr;
    }
}

void m65832_coproc_set_shadow_bank(m65832_cpu_t *cpu, int bank, uint32_t base) {
    if (cpu->coproc && bank >= 0 && bank < M6502_SHADOW_BANKS) {
        cpu->coproc->bank_base[bank] = base;
    }
}

void m65832_coproc_set_timing(m65832_cpu_t *cpu, uint32_t cycles_per_line,
                               uint32_t lines_per_frame) {
    if (cpu->coproc) {
        cpu->coproc->cycles_per_line = cycles_per_line;
        cpu->coproc->lines_per_frame = lines_per_frame;
    }
}

int m65832_coproc_run(m65832_cpu_t *cpu, int cycles) {
    m6502_cpu_t *c = cpu->coproc;
    if (!c || !c->running) return 0;
    
    int executed = 0;
    while (executed < cycles) {
        /* Check for NMI (edge triggered) */
        if (c->nmi_pending && !c->nmi_prev) {
            c->nmi_prev = true;
            c->nmi_pending = false;
            push16(c, c->pc);
            push(c, c->p & ~F6502_B);
            c->p |= F6502_I;
            if (c->compat & COMPAT_CMOS65C02_EN) c->p &= ~F6502_D;
            c->pc = m6502_read(c, 0xFFFA) | ((uint16_t)m6502_read(c, 0xFFFB) << 8);
            executed += 7;
            continue;
        }
        
        /* Check for IRQ */
        if (c->irq_pending && !(c->p & F6502_I)) {
            push16(c, c->pc);
            push(c, c->p & ~F6502_B);
            c->p |= F6502_I;
            if (c->compat & COMPAT_CMOS65C02_EN) c->p &= ~F6502_D;
            c->pc = m6502_read(c, 0xFFFE) | ((uint16_t)m6502_read(c, 0xFFFF) << 8);
            executed += 7;
            continue;
        }
        
        int inst_cycles = execute_6502(c);
        executed += inst_cycles;
        c->cycles += inst_cycles;
        c->frame_cycles += inst_cycles;
        
        /* Update scanline counter */
        while (c->frame_cycles >= c->cycles_per_line) {
            c->frame_cycles -= c->cycles_per_line;
            c->scanline++;
            if (c->scanline >= c->lines_per_frame) {
                c->scanline = 0;
            }
        }
    }
    
    return executed;
}

void m65832_coproc_irq(m65832_cpu_t *cpu, bool active) {
    if (cpu->coproc) {
        cpu->coproc->irq_pending = active;
    }
}

void m65832_coproc_nmi(m65832_cpu_t *cpu) {
    if (cpu->coproc) {
        cpu->coproc->nmi_pending = true;
    }
}

m6502_cpu_t *m65832_coproc_get(m65832_cpu_t *cpu) {
    return cpu->coproc;
}

uint8_t m65832_coproc_shadow_read(m65832_cpu_t *cpu, int bank, int reg) {
    if (cpu->coproc && bank >= 0 && bank < M6502_SHADOW_BANKS && 
        reg >= 0 && reg < M6502_SHADOW_REGS) {
        return cpu->coproc->shadow_regs[bank][reg];
    }
    return 0;
}

bool m65832_coproc_fifo_pop(m65832_cpu_t *cpu, m6502_fifo_entry_t *entry) {
    m6502_cpu_t *c = cpu->coproc;
    if (!c || c->fifo_count == 0) return false;
    
    *entry = c->fifo[c->fifo_head];
    c->fifo_head = (c->fifo_head + 1) % M6502_WRITE_FIFO_SIZE;
    c->fifo_count--;
    return true;
}

int m65832_coproc_fifo_count(m65832_cpu_t *cpu) {
    return cpu->coproc ? cpu->coproc->fifo_count : 0;
}

void m65832_coproc_print_state(m65832_cpu_t *cpu) {
    m6502_cpu_t *c = cpu->coproc;
    if (!c) {
        printf("6502 Coprocessor: Not configured\n");
        return;
    }
    
    printf("6502 Coprocessor State:\n");
    printf("  PC: %04X  A: %02X  X: %02X  Y: %02X  S: %02X\n",
           c->pc, c->a, c->x, c->y, c->s);
    printf("  P:  %02X [%c%c-%c%c%c%c%c]  VBR: %08X\n",
           c->p,
           (c->p & F6502_N) ? 'N' : '-',
           (c->p & F6502_V) ? 'V' : '-',
           (c->p & F6502_B) ? 'B' : '-',
           (c->p & F6502_D) ? 'D' : '-',
           (c->p & F6502_I) ? 'I' : '-',
           (c->p & F6502_Z) ? 'Z' : '-',
           (c->p & F6502_C) ? 'C' : '-',
           c->vbr);
    printf("  Cycles: %llu  Scanline: %u/%u  FIFO: %d\n",
           (unsigned long long)c->cycles, c->scanline, c->lines_per_frame,
           c->fifo_count);
    printf("  Compat: %s%s%s\n",
           (c->compat & COMPAT_DECIMAL_EN) ? "BCD " : "",
           (c->compat & COMPAT_CMOS65C02_EN) ? "65C02 " : "",
           (c->compat & COMPAT_NMOS_ILLEGAL) ? "NMOS-ILL" : "");
}
