/*
 * m65832emu.c - M65832 CPU Emulator Core
 *
 * High-performance emulator for the M65832 processor.
 */

#include "m65832emu.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ============================================================================
 * Internal Macros
 * ========================================================================= */

/* Flag manipulation */
#define FLAG_SET(cpu, f)    ((cpu)->p |= (f))
#define FLAG_CLR(cpu, f)    ((cpu)->p &= ~(f))
#define FLAG_TST(cpu, f)    (((cpu)->p & (f)) != 0)
#define FLAG_PUT(cpu, f, v) do { if (v) FLAG_SET(cpu, f); else FLAG_CLR(cpu, f); } while(0)

/* Register width helpers */
#define WIDTH_M(cpu)    ((m65832_width_t)(((cpu)->p >> 6) & 3))
#define WIDTH_X(cpu)    ((m65832_width_t)(((cpu)->p >> 4) & 3))
#define SIZE_M(cpu)     (1 << WIDTH_M(cpu))
#define SIZE_X(cpu)     (1 << WIDTH_X(cpu))
#define MASK_M(cpu)     ((1ULL << (8 * SIZE_M(cpu))) - 1)
#define MASK_X(cpu)     ((1ULL << (8 * SIZE_X(cpu))) - 1)

/* Sign bit for given width */
#define SIGN_8          0x80
#define SIGN_16         0x8000
#define SIGN_32         0x80000000

/* Emulation mode check */
#define IS_EMU(cpu)     FLAG_TST(cpu, P_E)
#define IS_NATIVE(cpu)  (!IS_EMU(cpu))

/* ============================================================================
 * System Register Access (MMIO at $FFFFF0xx)
 * These bypass MMU translation (like in the RTL)
 * ========================================================================= */

static inline bool is_sysreg(uint32_t addr) {
    return (addr >= SYSREG_BASE && addr < SYSREG_BASE + 0x100);
}

/* Forward declarations for exception handling (defined after stack functions) */
static void exception_enter(m65832_cpu_t *cpu, uint32_t vector, uint32_t return_pc);
static void page_fault_exception(m65832_cpu_t *cpu, uint32_t fault_addr, uint8_t fault_type);
static void illegal_instruction(m65832_cpu_t *cpu);

/* TLB invalidation helpers */
static void tlb_invalidate_va(m65832_cpu_t *cpu, uint32_t va) {
    uint32_t vpn = va >> 12;
    for (int i = 0; i < M65832_TLB_ENTRIES; i++) {
        if (cpu->tlb[i].valid && cpu->tlb[i].vpn == vpn) {
            cpu->tlb[i].valid = false;
        }
    }
}

static void tlb_invalidate_asid(m65832_cpu_t *cpu, uint8_t asid) {
    for (int i = 0; i < M65832_TLB_ENTRIES; i++) {
        if (cpu->tlb[i].valid && cpu->tlb[i].asid == asid && 
            !(cpu->tlb[i].flags & TLB_PRESENT)) {  /* Not global */
            cpu->tlb[i].valid = false;
        }
    }
}

static void tlb_flush_all(m65832_cpu_t *cpu) {
    for (int i = 0; i < M65832_TLB_ENTRIES; i++) {
        cpu->tlb[i].valid = false;
    }
    cpu->tlb_next = 0;
}

/* Timer update - call every instruction */
static void timer_tick(m65832_cpu_t *cpu, int cycles) {
    if (!(cpu->timer_ctrl & TIMER_ENABLE)) return;
    
    cpu->timer_cnt += cycles;
    
    if (cpu->timer_cnt >= cpu->timer_cmp) {
        if (cpu->timer_ctrl & TIMER_IRQ_ENABLE) {
            cpu->timer_ctrl |= TIMER_IRQ_PENDING;
            cpu->timer_irq = true;
        }
        if (cpu->timer_ctrl & TIMER_AUTORESET) {
            cpu->timer_cnt = 0;
        }
    }
}

/* System register read */
static uint32_t sysreg_read(m65832_cpu_t *cpu, uint32_t addr) {
    /* System registers require supervisor mode for access */
    if (!FLAG_TST(cpu, P_S)) {
        cpu->trap = TRAP_PRIVILEGE;
        cpu->trap_addr = cpu->pc;
        return 0;
    }
    
    switch (addr & 0xFF) {
        case 0x00: return cpu->mmucr;                           /* MMUCR */
        case 0x04: return 0;                                    /* TLBINVAL (write-only) */
        case 0x08: return cpu->asid;                            /* ASID */
        case 0x0C: return 0;                                    /* ASIDINVAL (write-only) */
        case 0x10: return cpu->faultva;                         /* FAULTVA */
        case 0x14: return (uint32_t)(cpu->ptbr & 0xFFFFFFFF);   /* PTBR_LO */
        case 0x18: return (uint32_t)(cpu->ptbr >> 32);          /* PTBR_HI */
        case 0x1C: return 0;                                    /* TLBFLUSH (write-only) */
        case 0x40: return cpu->timer_ctrl;                      /* TIMER_CTRL */
        case 0x44: return cpu->timer_cmp;                       /* TIMER_CMP */
        case 0x48: return cpu->timer_cnt;                       /* TIMER_CNT */
        default:   return 0;
    }
}

/* System register write */
static void sysreg_write(m65832_cpu_t *cpu, uint32_t addr, uint32_t val) {
    /* System registers require supervisor mode */
    if (!FLAG_TST(cpu, P_S)) {
        cpu->trap = TRAP_PRIVILEGE;
        cpu->trap_addr = cpu->pc;
        cpu->running = false;
        return;
    }
    
    switch (addr & 0xFF) {
        case 0x00:  /* MMUCR */
            /* Preserve fault type bits (read-only), update control bits */
            cpu->mmucr = (cpu->mmucr & MMUCR_FTYPE_MASK) | (val & ~MMUCR_FTYPE_MASK);
            break;
            
        case 0x04:  /* TLBINVAL - invalidate by VA */
            tlb_invalidate_va(cpu, val);
            break;
            
        case 0x08:  /* ASID */
            cpu->asid = (uint8_t)val;
            break;
            
        case 0x0C:  /* ASIDINVAL - invalidate by ASID */
            tlb_invalidate_asid(cpu, (uint8_t)val);
            break;
            
        case 0x10:  /* FAULTVA - read only */
            break;
            
        case 0x14:  /* PTBR_LO */
            cpu->ptbr = (cpu->ptbr & 0xFFFFFFFF00000000ULL) | val;
            break;
            
        case 0x18:  /* PTBR_HI */
            cpu->ptbr = (cpu->ptbr & 0x00000000FFFFFFFFULL) | ((uint64_t)val << 32);
            break;
            
        case 0x1C:  /* TLBFLUSH - any write flushes all */
            tlb_flush_all(cpu);
            break;
            
        case 0x40:  /* TIMER_CTRL */
            if (val & TIMER_IRQ_CLEAR) {
                cpu->timer_ctrl &= ~TIMER_IRQ_PENDING;
                cpu->timer_irq = false;
            }
            cpu->timer_ctrl = (cpu->timer_ctrl & TIMER_IRQ_PENDING) | 
                              (val & ~(TIMER_IRQ_CLEAR | TIMER_IRQ_PENDING));
            break;
            
        case 0x44:  /* TIMER_CMP */
            cpu->timer_cmp = val;
            break;
            
        case 0x48:  /* TIMER_CNT */
            cpu->timer_cnt = val;
            break;
    }
}

/* ============================================================================
 * MMU - Page Table Walking (when MMUCR.PG = 1)
 * Two-level page tables: 10 bits L1 + 10 bits L2 + 12 bits offset
 * ========================================================================= */

/* TLB lookup - returns physical address or 0 on miss */
static bool tlb_lookup(m65832_cpu_t *cpu, uint32_t va, uint64_t *pa, uint8_t *flags) {
    uint32_t vpn = va >> 12;
    for (int i = 0; i < M65832_TLB_ENTRIES; i++) {
        m65832_tlb_entry_t *e = &cpu->tlb[i];
        if (e->valid && e->vpn == vpn && 
            (e->asid == cpu->asid || (e->flags & TLB_PRESENT))) {  /* Global check */
            *pa = (e->ppn << 12) | (va & 0xFFF);
            *flags = e->flags;
            return true;
        }
    }
    return false;
}

/* Insert TLB entry (round-robin replacement) */
static void tlb_insert(m65832_cpu_t *cpu, uint32_t vpn, uint64_t ppn, uint8_t flags) {
    m65832_tlb_entry_t *e = &cpu->tlb[cpu->tlb_next];
    e->vpn = vpn;
    e->ppn = ppn;
    e->asid = cpu->asid;
    e->flags = flags;
    e->valid = true;
    cpu->tlb_next = (cpu->tlb_next + 1) % M65832_TLB_ENTRIES;
}

/* Page table walk - returns physical address, sets fault info on error */
static bool mmu_translate(m65832_cpu_t *cpu, uint32_t va, uint64_t *pa, 
                          int access_type, bool is_user) {
    /* If paging disabled, identity mapping */
    if (!(cpu->mmucr & MMUCR_PG)) {
        *pa = va;
        return true;
    }
    
    /* TLB lookup first */
    uint8_t tlb_flags;
    if (tlb_lookup(cpu, va, pa, &tlb_flags)) {
        /* Check permissions */
        if (is_user && !(tlb_flags & TLB_USER)) {
            cpu->faultva = va;
            cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                         (FAULT_USER_SUPER << MMUCR_FTYPE_SHIFT);
            return false;
        }
        if (access_type == 1 && !(tlb_flags & TLB_WRITABLE)) {  /* Write */
            cpu->faultva = va;
            cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                         (FAULT_WRITE_PROTECT << MMUCR_FTYPE_SHIFT);
            return false;
        }
        if (access_type == 2 && !(tlb_flags & TLB_EXECUTABLE)) {  /* Execute */
            cpu->faultva = va;
            cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                         (FAULT_NO_EXECUTE << MMUCR_FTYPE_SHIFT);
            return false;
        }
        return true;
    }
    
    /* TLB miss - walk page tables */
    /* L1 index: bits 31:22 (10 bits) */
    uint32_t l1_idx = (va >> 22) & 0x3FF;
    uint64_t l1_pte_addr = cpu->ptbr + (l1_idx * 8);
    
    /* Read L1 PTE (need direct memory access, bypass MMU) */
    uint64_t l1_pte = 0;
    if (l1_pte_addr < cpu->memory_size - 7) {
        for (int i = 0; i < 8; i++) {
            l1_pte |= (uint64_t)cpu->memory[l1_pte_addr + i] << (i * 8);
        }
    }
    
    if (!(l1_pte & PTE_PRESENT)) {
        cpu->faultva = va;
        cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                     (FAULT_L1_NOT_PRESENT << MMUCR_FTYPE_SHIFT);
        return false;
    }
    
    /* L2 index: bits 21:12 (10 bits) */
    uint32_t l2_idx = (va >> 12) & 0x3FF;
    uint64_t l2_base = l1_pte & PTE_PPN_MASK;
    uint64_t l2_pte_addr = l2_base + (l2_idx * 8);
    
    /* Read L2 PTE */
    uint64_t l2_pte = 0;
    if (l2_pte_addr < cpu->memory_size - 7) {
        for (int i = 0; i < 8; i++) {
            l2_pte |= (uint64_t)cpu->memory[l2_pte_addr + i] << (i * 8);
        }
    }
    
    if (!(l2_pte & PTE_PRESENT)) {
        cpu->faultva = va;
        cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                     (FAULT_NOT_PRESENT << MMUCR_FTYPE_SHIFT);
        return false;
    }
    
    /* Check permissions */
    if (is_user && !(l2_pte & PTE_USER)) {
        cpu->faultva = va;
        cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                     (FAULT_USER_SUPER << MMUCR_FTYPE_SHIFT);
        return false;
    }
    if (access_type == 1 && !(l2_pte & PTE_WRITABLE)) {
        cpu->faultva = va;
        cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | 
                     (FAULT_WRITE_PROTECT << MMUCR_FTYPE_SHIFT);
        return false;
    }
    
    /* Compute physical address */
    uint64_t ppn = (l2_pte & PTE_PPN_MASK) >> 12;
    *pa = (ppn << 12) | (va & 0xFFF);
    
    /* Insert into TLB */
    uint8_t flags = 0;
    if (l2_pte & PTE_PRESENT) flags |= TLB_PRESENT;
    if (l2_pte & PTE_WRITABLE) flags |= TLB_WRITABLE;
    if (l2_pte & PTE_USER) flags |= TLB_USER;
    if (l2_pte & PTE_GLOBAL) flags |= TLB_EXECUTABLE;  /* Reuse for now */
    tlb_insert(cpu, va >> 12, ppn, flags);
    
    return true;
}

/* ============================================================================
 * MMIO Region Lookup (inline for performance)
 * ========================================================================= */

static inline m65832_mmio_region_t *mmio_find_region(m65832_cpu_t *cpu, uint32_t addr) {
    for (int i = 0; i < cpu->num_mmio; i++) {
        m65832_mmio_region_t *r = &cpu->mmio[i];
        if (r->active && addr >= r->base && addr < r->base + r->size) {
            return r;
        }
    }
    return NULL;
}

/* ============================================================================
 * Memory Access (with MMIO support)
 * ========================================================================= */

/* Check watchpoints for memory access */
static inline bool check_watchpoint(m65832_cpu_t *cpu, uint32_t addr, bool is_write) {
    for (int i = 0; i < cpu->num_watchpoints; i++) {
        uint32_t wp_start = cpu->watchpoints[i].addr;
        uint32_t wp_end = wp_start + cpu->watchpoints[i].size;
        if (addr >= wp_start && addr < wp_end) {
            if ((is_write && cpu->watchpoints[i].on_write) ||
                (!is_write && cpu->watchpoints[i].on_read)) {
                cpu->trap = TRAP_WATCHPOINT;
                cpu->trap_addr = addr;
                return true;
            }
        }
    }
    return false;
}

static inline uint8_t mem_read8(m65832_cpu_t *cpu, uint32_t addr) {
    /* Check read watchpoints */
    if (cpu->num_watchpoints > 0) {
        check_watchpoint(cpu, addr, false);
    }
    
    /* System registers bypass MMU */
    if (is_sysreg(addr)) {
        uint32_t reg_addr = addr & ~3;
        uint32_t val = sysreg_read(cpu, reg_addr);
        return (val >> ((addr & 3) * 8)) & 0xFF;
    }
    
    /* Check MMIO regions (also bypass MMU) */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->read) {
        return (uint8_t)r->read(cpu, addr, addr - r->base, 1, r->user);
    }
    
    /* MMU translation (if enabled) */
    uint64_t pa = addr;
    if (cpu->mmucr & MMUCR_PG) {
        if (!mmu_translate(cpu, addr, &pa, 0, !FLAG_TST(cpu, P_S))) {
            cpu->trap = TRAP_PAGE_FAULT;
            cpu->trap_addr = addr;
            return 0xFF;
        }
    }
    
    /* Custom memory callback */
    if (cpu->mem_read) {
        return (uint8_t)cpu->mem_read(cpu, (uint32_t)pa, 1, MEM_READ, cpu->mem_user);
    }
    
    /* Flat memory */
    if (cpu->memory && pa < cpu->memory_size) {
        return cpu->memory[pa];
    }
    return 0xFF;
}

static inline void mem_write8(m65832_cpu_t *cpu, uint32_t addr, uint8_t val) {
    /* Check write watchpoints */
    if (cpu->num_watchpoints > 0) {
        check_watchpoint(cpu, addr, true);
    }
    
    /* Invalidate LL/SC reservation if writing to linked address */
    if (cpu->ll_valid && addr == cpu->ll_addr) {
        cpu->ll_valid = false;
    }
    
    /* System registers bypass MMU */
    if (is_sysreg(addr)) {
        uint32_t reg_addr = addr & ~3;
        uint32_t old = sysreg_read(cpu, reg_addr);
        int shift = (addr & 3) * 8;
        uint32_t mask = 0xFF << shift;
        sysreg_write(cpu, reg_addr, (old & ~mask) | ((uint32_t)val << shift));
        return;
    }
    
    /* Check MMIO regions (also bypass MMU) */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->write) {
        r->write(cpu, addr, addr - r->base, val, 1, r->user);
        return;
    }
    
    /* MMU translation (if enabled) */
    uint64_t pa = addr;
    if (cpu->mmucr & MMUCR_PG) {
        if (!mmu_translate(cpu, addr, &pa, 1, !FLAG_TST(cpu, P_S))) {
            cpu->trap = TRAP_PAGE_FAULT;
            cpu->trap_addr = addr;
            return;
        }
    }
    
    /* Custom memory callback */
    if (cpu->mem_write) {
        cpu->mem_write(cpu, (uint32_t)pa, val, 1, cpu->mem_user);
        return;
    }
    
    /* Flat memory */
    if (cpu->memory && pa < cpu->memory_size) {
        cpu->memory[pa] = val;
    }
}

static inline uint16_t mem_read16(m65832_cpu_t *cpu, uint32_t addr) {
    /* Check MMIO regions first */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->read) {
        return (uint16_t)r->read(cpu, addr, addr - r->base, 2, r->user);
    }
    
    if (cpu->mem_read) {
        return (uint16_t)cpu->mem_read(cpu, addr, 2, MEM_READ, cpu->mem_user);
    }
    if (cpu->memory && addr + 1 < cpu->memory_size) {
        return cpu->memory[addr] | ((uint16_t)cpu->memory[addr + 1] << 8);
    }
    return 0xFFFF;
}

static inline void mem_write16(m65832_cpu_t *cpu, uint32_t addr, uint16_t val) {
    /* Check MMIO regions first */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->write) {
        r->write(cpu, addr, addr - r->base, val, 2, r->user);
        return;
    }
    
    if (cpu->mem_write) {
        cpu->mem_write(cpu, addr, val, 2, cpu->mem_user);
        return;
    }
    if (cpu->memory && addr + 1 < cpu->memory_size) {
        cpu->memory[addr] = val & 0xFF;
        cpu->memory[addr + 1] = (val >> 8) & 0xFF;
    }
}

static inline uint32_t mem_read32(m65832_cpu_t *cpu, uint32_t addr) {
    /* Check MMIO regions first */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->read) {
        return r->read(cpu, addr, addr - r->base, 4, r->user);
    }
    
    if (cpu->mem_read) {
        return cpu->mem_read(cpu, addr, 4, MEM_READ, cpu->mem_user);
    }
    if (cpu->memory && addr + 3 < cpu->memory_size) {
        return cpu->memory[addr] | 
               ((uint32_t)cpu->memory[addr + 1] << 8) |
               ((uint32_t)cpu->memory[addr + 2] << 16) |
               ((uint32_t)cpu->memory[addr + 3] << 24);
    }
    return 0xFFFFFFFF;
}

static inline void mem_write32(m65832_cpu_t *cpu, uint32_t addr, uint32_t val) {
    /* Check MMIO regions first */
    m65832_mmio_region_t *r = mmio_find_region(cpu, addr);
    if (r && r->write) {
        r->write(cpu, addr, addr - r->base, val, 4, r->user);
        return;
    }
    
    if (cpu->mem_write) {
        cpu->mem_write(cpu, addr, val, 4, cpu->mem_user);
        return;
    }
    if (cpu->memory && addr + 3 < cpu->memory_size) {
        cpu->memory[addr] = val & 0xFF;
        cpu->memory[addr + 1] = (val >> 8) & 0xFF;
        cpu->memory[addr + 2] = (val >> 16) & 0xFF;
        cpu->memory[addr + 3] = (val >> 24) & 0xFF;
    }
}

/* Fetch instruction byte */
static inline uint8_t fetch8(m65832_cpu_t *cpu) {
    uint8_t val;
    if (cpu->mem_read) {
        val = (uint8_t)cpu->mem_read(cpu, cpu->pc, 1, MEM_FETCH, cpu->mem_user);
    } else if (cpu->memory && cpu->pc < cpu->memory_size) {
        val = cpu->memory[cpu->pc];
    } else {
        val = 0;
    }
    cpu->pc++;
    return val;
}

static inline uint16_t fetch16(m65832_cpu_t *cpu) {
    uint16_t lo = fetch8(cpu);
    uint16_t hi = fetch8(cpu);
    return lo | (hi << 8);
}

static inline uint32_t fetch32(m65832_cpu_t *cpu) {
    uint32_t val = fetch8(cpu);
    val |= (uint32_t)fetch8(cpu) << 8;
    val |= (uint32_t)fetch8(cpu) << 16;
    val |= (uint32_t)fetch8(cpu) << 24;
    return val;
}

/* ============================================================================
 * Stack Operations
 * ========================================================================= */

static inline void push8(m65832_cpu_t *cpu, uint8_t val) {
    if (IS_EMU(cpu)) {
        cpu->memory[0x100 + (cpu->s & 0xFF)] = val;
        cpu->s = 0x100 | ((cpu->s - 1) & 0xFF);
    } else {
        mem_write8(cpu, cpu->s, val);
        cpu->s--;
    }
}

static inline uint8_t pull8(m65832_cpu_t *cpu) {
    if (IS_EMU(cpu)) {
        cpu->s = 0x100 | ((cpu->s + 1) & 0xFF);
        return cpu->memory[0x100 + (cpu->s & 0xFF)];
    } else {
        cpu->s++;
        return mem_read8(cpu, cpu->s);
    }
}

static inline void push16(m65832_cpu_t *cpu, uint16_t val) {
    push8(cpu, (val >> 8) & 0xFF);
    push8(cpu, val & 0xFF);
}

static inline uint16_t pull16(m65832_cpu_t *cpu) {
    uint16_t lo = pull8(cpu);
    uint16_t hi = pull8(cpu);
    return lo | (hi << 8);
}

static inline void push32(m65832_cpu_t *cpu, uint32_t val) {
    push8(cpu, (val >> 24) & 0xFF);
    push8(cpu, (val >> 16) & 0xFF);
    push8(cpu, (val >> 8) & 0xFF);
    push8(cpu, val & 0xFF);
}

static inline uint32_t pull32(m65832_cpu_t *cpu) {
    uint32_t val = pull8(cpu);
    val |= (uint32_t)pull8(cpu) << 8;
    val |= (uint32_t)pull8(cpu) << 16;
    val |= (uint32_t)pull8(cpu) << 24;
    return val;
}

/* ============================================================================
 * Flag Updates
 * ========================================================================= */

static inline void update_nz8(m65832_cpu_t *cpu, uint8_t val) {
    FLAG_PUT(cpu, P_Z, val == 0);
    FLAG_PUT(cpu, P_N, val & 0x80);
}

static inline void update_nz16(m65832_cpu_t *cpu, uint16_t val) {
    FLAG_PUT(cpu, P_Z, val == 0);
    FLAG_PUT(cpu, P_N, val & 0x8000);
}

static inline void update_nz32(m65832_cpu_t *cpu, uint32_t val) {
    FLAG_PUT(cpu, P_Z, val == 0);
    FLAG_PUT(cpu, P_N, val & 0x80000000);
}

static inline void update_nz(m65832_cpu_t *cpu, uint32_t val, int width) {
    switch (width) {
        case 1: update_nz8(cpu, (uint8_t)val); break;
        case 2: update_nz16(cpu, (uint16_t)val); break;
        case 4: update_nz32(cpu, val); break;
    }
}

/* ============================================================================
 * Addressing Modes
 * ========================================================================= */

/* Immediate - return address of next byte(s) */
static inline uint32_t addr_imm(m65832_cpu_t *cpu, int size) {
    uint32_t addr = cpu->pc;
    cpu->pc += size;
    return addr;
}

/* Direct Page */
static inline uint32_t addr_dp(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    if (FLAG_TST(cpu, P_R)) {
        /* Register window mode - map to register file */
        return 0xFFFFFF00 | offset;  /* Special marker for reg access */
    }
    return (cpu->d + offset) & 0xFFFFFFFF;
}

/* Direct Page, X */
static inline uint32_t addr_dpx(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    if (FLAG_TST(cpu, P_R)) {
        return 0xFFFFFF00 | ((offset + (cpu->x & 0xFF)) & 0xFF);
    }
    return (cpu->d + offset + cpu->x) & 0xFFFFFFFF;
}

/* Direct Page, Y */
static inline uint32_t addr_dpy(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    return (cpu->d + offset + cpu->y) & 0xFFFFFFFF;
}

/* Absolute */
static inline uint32_t addr_abs(m65832_cpu_t *cpu) {
    uint16_t offset = fetch16(cpu);
    return (cpu->b + offset) & 0xFFFFFFFF;
}

/* Absolute, X */
static inline uint32_t addr_absx(m65832_cpu_t *cpu) {
    uint16_t offset = fetch16(cpu);
    return (cpu->b + offset + cpu->x) & 0xFFFFFFFF;
}

/* Absolute, Y */
static inline uint32_t addr_absy(m65832_cpu_t *cpu) {
    uint16_t offset = fetch16(cpu);
    return (cpu->b + offset + cpu->y) & 0xFFFFFFFF;
}

/* Fetch 24-bit value (for long addressing) */
static inline uint32_t fetch24(m65832_cpu_t *cpu) {
    uint32_t low = fetch8(cpu);
    uint32_t mid = fetch8(cpu);
    uint32_t high = fetch8(cpu);
    return low | (mid << 8) | (high << 16);
}

/* Long (24-bit address) - 65816/M65832 long addressing mode */
static inline uint32_t addr_long(m65832_cpu_t *cpu) __attribute__((unused));
static inline uint32_t addr_long(m65832_cpu_t *cpu) {
    return fetch24(cpu);
}

/* Long, X */
static inline uint32_t addr_longx(m65832_cpu_t *cpu) __attribute__((unused));
static inline uint32_t addr_longx(m65832_cpu_t *cpu) {
    return fetch24(cpu) + cpu->x;
}

/* (Direct Page) - indirect */
static inline uint32_t addr_dpi(m65832_cpu_t *cpu) {
    uint32_t ptr = addr_dp(cpu);
    if (IS_EMU(cpu) || WIDTH_M(cpu) <= WIDTH_16) {
        return mem_read16(cpu, ptr);
    }
    return mem_read32(cpu, ptr);
}

/* (Direct Page, X) - indexed indirect */
static inline uint32_t addr_dpxi(m65832_cpu_t *cpu) {
    uint32_t ptr = addr_dpx(cpu);
    if (IS_EMU(cpu) || WIDTH_M(cpu) <= WIDTH_16) {
        return mem_read16(cpu, ptr);
    }
    return mem_read32(cpu, ptr);
}

/* (Direct Page), Y - indirect indexed */
static inline uint32_t addr_dpiy(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    uint32_t ptr = cpu->d + offset;
    uint32_t base;
    if (IS_EMU(cpu) || WIDTH_M(cpu) <= WIDTH_16) {
        base = mem_read16(cpu, ptr);
    } else {
        base = mem_read32(cpu, ptr);
    }
    return base + cpu->y;
}

/* [Direct Page] - indirect long */
static inline uint32_t addr_dpil(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    uint32_t ptr = cpu->d + offset;
    return mem_read32(cpu, ptr);
}

/* [Direct Page], Y - indirect long indexed */
static inline uint32_t addr_dpily(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    uint32_t ptr = cpu->d + offset;
    return mem_read32(cpu, ptr) + cpu->y;
}

/* Stack Relative */
static inline uint32_t addr_sr(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    return cpu->s + offset;
}

/* (Stack Relative), Y */
static inline uint32_t addr_sriy(m65832_cpu_t *cpu) {
    uint8_t offset = fetch8(cpu);
    uint32_t ptr = cpu->s + offset;
    uint32_t base;
    if (IS_EMU(cpu) || WIDTH_M(cpu) <= WIDTH_16) {
        base = mem_read16(cpu, ptr);
    } else {
        base = mem_read32(cpu, ptr);
    }
    return base + cpu->y;
}

/* ============================================================================
 * Exception Entry/Exit (Implementation - after stack/memory functions)
 * ========================================================================= */

/*
 * Enter exception handler.
 * Stack layout after entry (native mode):
 *   [SP+0] P_low (8 bits: C,Z,I,D,X0,X1,M0,M1)
 *   [SP+1] P_high (8 bits: V,N,E,S,R,K,0,0)
 *   [SP+2] PC byte 0
 *   [SP+3] PC byte 1
 *   [SP+4] PC byte 2
 *   [SP+5] PC byte 3
 */
static void exception_enter(m65832_cpu_t *cpu, uint32_t vector, uint32_t return_pc) {
    /* M65832: Exception entry ALWAYS pushes 32-bit PC and 16-bit P,
     * regardless of E mode. This matches the VHDL implementation.
     * RTI correspondingly always pulls 16-bit P and 32-bit PC. */
    push8(cpu, (uint8_t)(return_pc >> 24));
    push8(cpu, (uint8_t)(return_pc >> 16));
    push8(cpu, (uint8_t)(return_pc >> 8));
    push8(cpu, (uint8_t)return_pc);
    push8(cpu, (uint8_t)(cpu->p >> 8));  /* P_high */
    push8(cpu, (uint8_t)cpu->p);          /* P_low */
    FLAG_SET(cpu, P_I);                   /* Disable IRQ */
    FLAG_SET(cpu, P_S);                   /* Enter supervisor mode */
    
    /* Vector address depends on E mode: 16-bit read in emulation, 32-bit in native */
    if (IS_EMU(cpu)) {
        cpu->pc = mem_read16(cpu, vector & 0xFFFF);
    } else {
        cpu->pc = mem_read32(cpu, vector);
    }
}

/* Page fault exception entry */
static void page_fault_exception(m65832_cpu_t *cpu, uint32_t fault_addr, uint8_t fault_type) {
    cpu->faultva = fault_addr;
    cpu->mmucr = (cpu->mmucr & ~MMUCR_FTYPE_MASK) | (fault_type << MMUCR_FTYPE_SHIFT);
    exception_enter(cpu, VEC_PAGE_FAULT, cpu->pc);
    cpu->trap = TRAP_PAGE_FAULT;
    cpu->trap_addr = fault_addr;
}

/* Illegal instruction exception - vectors to handler like BRK/TRAP.
 * Does not set TRAP_ILLEGAL_OP since we have a valid handler.
 * The exception_enter will set up the return address so RTI returns
 * to the instruction after the illegal opcode. */
static void illegal_instruction(m65832_cpu_t *cpu) {
    exception_enter(cpu, VEC_ILLEGAL_OP, cpu->pc);
    /* Don't set TRAP_ILLEGAL_OP - let the handler run just like BRK */
}

/* ============================================================================
 * ALU Operations
 * ========================================================================= */

/* ADC - Add with Carry */
static void op_adc(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t a = cpu->a;
    uint32_t c = FLAG_TST(cpu, P_C) ? 1 : 0;
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t result;

    if (FLAG_TST(cpu, P_D) && width <= 2) {
        /* BCD mode (8 or 16 bit only) */
        uint32_t al, ah, rl, rh;
        if (width == 1) {
            al = (a & 0x0F) + (val & 0x0F) + c;
            if (al > 9) al += 6;
            ah = (a >> 4) + (val >> 4) + (al > 0x0F ? 1 : 0);
            if (ah > 9) ah += 6;
            result = (al & 0x0F) | ((ah & 0x0F) << 4);
            FLAG_PUT(cpu, P_C, ah > 0x0F);
        } else {
            /* 16-bit BCD */
            rl = (a & 0x000F) + (val & 0x000F) + c;
            if (rl > 9) rl += 6;
            rh = ((a >> 4) & 0x0F) + ((val >> 4) & 0x0F) + (rl > 0x0F ? 1 : 0);
            if (rh > 9) rh += 6;
            uint32_t r2 = ((a >> 8) & 0x0F) + ((val >> 8) & 0x0F) + (rh > 0x0F ? 1 : 0);
            if (r2 > 9) r2 += 6;
            uint32_t r3 = ((a >> 12) & 0x0F) + ((val >> 12) & 0x0F) + (r2 > 0x0F ? 1 : 0);
            if (r3 > 9) r3 += 6;
            result = (rl & 0x0F) | ((rh & 0x0F) << 4) | ((r2 & 0x0F) << 8) | ((r3 & 0x0F) << 12);
            FLAG_PUT(cpu, P_C, r3 > 0x0F);
        }
    } else {
        /* Binary mode */
        result = a + val + c;
        FLAG_PUT(cpu, P_C, result > mask);
        FLAG_PUT(cpu, P_V, (~(a ^ val) & (a ^ result) & sign) != 0);
    }

    result &= mask;
    cpu->a = (cpu->a & ~mask) | result;
    update_nz(cpu, result, width);
}

/* SBC - Subtract with Carry */
static void op_sbc(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t a = cpu->a;
    uint32_t c = FLAG_TST(cpu, P_C) ? 0 : 1;
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t result;

    if (FLAG_TST(cpu, P_D) && width <= 2) {
        /* BCD mode */
        int32_t al, ah;
        if (width == 1) {
            al = (a & 0x0F) - (val & 0x0F) - c;
            if (al < 0) al -= 6;
            ah = (a >> 4) - (val >> 4) - (al < 0 ? 1 : 0);
            if (ah < 0) ah -= 6;
            result = (al & 0x0F) | ((ah & 0x0F) << 4);
            FLAG_PUT(cpu, P_C, ah >= 0);
        } else {
            /* Simplified 16-bit BCD */
            result = a - val - c;
            FLAG_PUT(cpu, P_C, a >= val + c);
        }
    } else {
        result = a - val - c;
        FLAG_PUT(cpu, P_C, a >= val + c);
        FLAG_PUT(cpu, P_V, ((a ^ val) & (a ^ result) & sign) != 0);
    }

    result &= mask;
    cpu->a = (cpu->a & ~mask) | result;
    update_nz(cpu, result, width);
}

/* do_adc - ADC helper for register-targeted ALU */
static uint32_t do_adc(m65832_cpu_t *cpu, uint32_t dest, uint32_t val, int width) {
    uint32_t c = FLAG_TST(cpu, P_C) ? 1 : 0;
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t result;

    if (FLAG_TST(cpu, P_D) && width <= 2) {
        /* BCD mode (8 or 16 bit only) */
        uint32_t al, ah;
        if (width == 1) {
            al = (dest & 0x0F) + (val & 0x0F) + c;
            if (al > 9) al += 6;
            ah = (dest >> 4) + (val >> 4) + (al > 0x0F ? 1 : 0);
            if (ah > 9) ah += 6;
            result = (al & 0x0F) | ((ah & 0x0F) << 4);
            FLAG_PUT(cpu, P_C, ah > 0x0F);
        } else {
            /* 16-bit BCD (simplified) */
            result = dest + val + c;
            FLAG_PUT(cpu, P_C, result > mask);
        }
    } else {
        /* Binary mode */
        result = dest + val + c;
        FLAG_PUT(cpu, P_C, result > mask);
        FLAG_PUT(cpu, P_V, (~(dest ^ val) & (dest ^ result) & sign) != 0);
    }

    result &= mask;
    update_nz(cpu, result, width);
    return result;
}

/* do_sbc - SBC helper for register-targeted ALU */
static uint32_t do_sbc(m65832_cpu_t *cpu, uint32_t dest, uint32_t val, int width) {
    uint32_t c = FLAG_TST(cpu, P_C) ? 0 : 1;
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t result;

    if (FLAG_TST(cpu, P_D) && width <= 2) {
        /* BCD mode (simplified) */
        result = dest - val - c;
        FLAG_PUT(cpu, P_C, dest >= val + c);
    } else {
        result = dest - val - c;
        FLAG_PUT(cpu, P_C, dest >= val + c);
        FLAG_PUT(cpu, P_V, ((dest ^ val) & (dest ^ result) & sign) != 0);
    }

    result &= mask;
    update_nz(cpu, result, width);
    return result;
}

/* do_cmp - CMP helper for register-targeted ALU */
static void do_cmp(m65832_cpu_t *cpu, uint32_t dest, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t result = (dest - val) & mask;
    
    FLAG_PUT(cpu, P_C, dest >= val);
    FLAG_PUT(cpu, P_Z, result == 0);
    FLAG_PUT(cpu, P_N, (result & sign) != 0);
}

/* CMP - Compare */
static void op_cmp(m65832_cpu_t *cpu, uint32_t a, uint32_t b, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    a &= mask;
    b &= mask;
    uint32_t result = a - b;
    FLAG_PUT(cpu, P_C, a >= b);
    update_nz(cpu, result & mask, width);
}

/* AND */
static void op_and(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t result = cpu->a & val & mask;
    cpu->a = (cpu->a & ~mask) | result;
    update_nz(cpu, result, width);
}

/* ORA */
static void op_ora(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t result = (cpu->a | val) & mask;
    cpu->a = (cpu->a & ~mask) | result;
    update_nz(cpu, result, width);
}

/* EOR */
static void op_eor(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t result = (cpu->a ^ val) & mask;
    cpu->a = (cpu->a & ~mask) | result;
    update_nz(cpu, result, width);
}

/* ASL - Arithmetic Shift Left */
static uint32_t op_asl(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    FLAG_PUT(cpu, P_C, val & sign);
    val = (val << 1) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* LSR - Logical Shift Right */
static uint32_t op_lsr(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    FLAG_PUT(cpu, P_C, val & 1);
    val = (val >> 1) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* ROL - Rotate Left */
static uint32_t op_rol(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t c = FLAG_TST(cpu, P_C) ? 1 : 0;
    FLAG_PUT(cpu, P_C, val & sign);
    val = ((val << 1) | c) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* ROR - Rotate Right */
static uint32_t op_ror(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t c = FLAG_TST(cpu, P_C) ? sign : 0;
    FLAG_PUT(cpu, P_C, val & 1);
    val = ((val >> 1) | c) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* INC */
static uint32_t op_inc(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    val = (val + 1) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* DEC */
static uint32_t op_dec(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    val = (val - 1) & mask;
    update_nz(cpu, val, width);
    return val;
}

/* BIT */
static void op_bit(m65832_cpu_t *cpu, uint32_t val, int width) {
    uint32_t mask = (1ULL << (width * 8)) - 1;
    uint32_t sign = 1ULL << (width * 8 - 1);
    uint32_t ovf = 1ULL << (width * 8 - 2);
    FLAG_PUT(cpu, P_Z, (cpu->a & val & mask) == 0);
    FLAG_PUT(cpu, P_N, val & sign);
    FLAG_PUT(cpu, P_V, val & ovf);
}

/* ============================================================================
 * Read value by width helper
 * ========================================================================= */

static inline uint32_t read_val(m65832_cpu_t *cpu, uint32_t addr, int width) {
    switch (width) {
        case 1: return mem_read8(cpu, addr);
        case 2: return mem_read16(cpu, addr);
        case 4: return mem_read32(cpu, addr);
    }
    return 0;
}

static inline void write_val(m65832_cpu_t *cpu, uint32_t addr, uint32_t val, int width) {
    /* Invalidate any LL/SC reservation on any store (LL/SC semantics) */
    cpu->ll_valid = false;
    
    switch (width) {
        case 1: mem_write8(cpu, addr, (uint8_t)val); break;
        case 2: mem_write16(cpu, addr, (uint16_t)val); break;
        case 4: mem_write32(cpu, addr, val); break;
    }
}

/* ============================================================================
 * Instruction Execution - Main Dispatch
 * ========================================================================= */

/* Execute single instruction, return cycles */
static int execute_instruction(m65832_cpu_t *cpu) {
    uint8_t opcode = fetch8(cpu);
    int cycles = 2;  /* Base cycles */
    /* M65832: Width is controlled by M1:M0 and X1:X0 bits regardless of E mode */
    int width_m = SIZE_M(cpu);
    int width_x = SIZE_X(cpu);
    uint32_t addr, val;
    int8_t rel8;
    int16_t rel16;
    uint8_t ext_op;

    switch (opcode) {
        /* ============ LDA ============ */
        case 0xA9: /* LDA #imm */
            addr = addr_imm(cpu, width_m);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0xA5: /* LDA dp */
            addr = addr_dp(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 3;
            break;
        case 0xB5: /* LDA dp,X */
            addr = addr_dpx(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xAD: /* LDA abs */
            addr = addr_abs(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xBD: /* LDA abs,X */
            addr = addr_absx(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xB9: /* LDA abs,Y */
            addr = addr_absy(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xA1: /* LDA (dp,X) */
            addr = addr_dpxi(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 6;
            break;
        case 0xB1: /* LDA (dp),Y */
            addr = addr_dpiy(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 5;
            break;
        case 0xB2: /* LDA (dp) */
            addr = addr_dpi(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 5;
            break;
        case 0xA7: /* LDA [dp] */
            addr = addr_dpil(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 6;
            break;
        case 0xB7: /* LDA [dp],Y (65816 standard) */
            addr = addr_dpily(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 6;
            break;
        case 0xA3: /* LDA sr,S (M65832: cc=11, bbb=000) */
            addr = addr_sr(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xB3: /* LDA [dp],Y (M65832: cc=11, bbb=100) */
            addr = addr_dpily(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 6;
            break;
        case 0xAB: /* LDA long (M65832: cc=11, bbb=010) */
            addr = addr_long(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 5;
            break;
        case 0xAF: /* LDA (sr,S),Y - M65832 cc=11 bbb=011 */
            addr = addr_sriy(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 7;
            break;
        case 0xBF: /* LDA long,X - M65832 cc=11 bbb=111 */
            addr = addr_longx(cpu);
            cpu->a = read_val(cpu, addr, width_m);
            update_nz(cpu, cpu->a, width_m);
            cycles = 5;
            break;

        /* ============ LDX ============ */
        case 0xA2: /* LDX #imm */
            addr = addr_imm(cpu, width_x);
            cpu->x = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0xA6: /* LDX dp */
            addr = addr_dp(cpu);
            cpu->x = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->x, width_x);
            cycles = 3;
            break;
        case 0xB6: /* LDX dp,Y */
            addr = addr_dpy(cpu);
            cpu->x = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->x, width_x);
            cycles = 4;
            break;
        case 0xAE: /* LDX abs */
            addr = addr_abs(cpu);
            cpu->x = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->x, width_x);
            cycles = 4;
            break;
        case 0xBE: /* LDX abs,Y */
            addr = addr_absy(cpu);
            cpu->x = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->x, width_x);
            cycles = 4;
            break;

        /* ============ LDY ============ */
        case 0xA0: /* LDY #imm */
            addr = addr_imm(cpu, width_x);
            cpu->y = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->y, width_x);
            cycles = 2;
            break;
        case 0xA4: /* LDY dp */
            addr = addr_dp(cpu);
            cpu->y = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->y, width_x);
            cycles = 3;
            break;
        case 0xB4: /* LDY dp,X */
            addr = addr_dpx(cpu);
            cpu->y = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->y, width_x);
            cycles = 4;
            break;
        case 0xAC: /* LDY abs */
            addr = addr_abs(cpu);
            cpu->y = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->y, width_x);
            cycles = 4;
            break;
        case 0xBC: /* LDY abs,X */
            addr = addr_absx(cpu);
            cpu->y = read_val(cpu, addr, width_x);
            update_nz(cpu, cpu->y, width_x);
            cycles = 4;
            break;

        /* ============ STA ============ */
        case 0x85: /* STA dp */
            addr = addr_dp(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 3;
            break;
        case 0x95: /* STA dp,X */
            addr = addr_dpx(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 4;
            break;
        case 0x8D: /* STA abs */
            addr = addr_abs(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 4;
            break;
        case 0x9D: /* STA abs,X */
            addr = addr_absx(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 5;
            break;
        case 0x99: /* STA abs,Y */
            addr = addr_absy(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 5;
            break;
        case 0x81: /* STA (dp,X) */
            addr = addr_dpxi(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 6;
            break;
        case 0x91: /* STA (dp),Y */
            addr = addr_dpiy(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 6;
            break;
        case 0x92: /* STA (dp) */
            addr = addr_dpi(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 5;
            break;
        case 0x87: /* STA [dp] */
            addr = addr_dpil(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 6;
            break;
        case 0x97: /* STA [dp],Y */
            addr = addr_dpily(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 6;
            break;
        case 0x83: /* STA sr,S */
            addr = addr_sr(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 4;
            break;
        case 0x93: /* STA [dp],Y (M65832: cc=11, bbb=100) */
            addr = addr_dpily(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 6;
            break;
        case 0x8F: /* STA long (M65832 explicit) */
            addr = addr_long(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 5;
            break;
        case 0x9F: /* STA long,X (M65832 explicit) */
            addr = addr_longx(cpu);
            write_val(cpu, addr, cpu->a, width_m);
            cycles = 5;
            break;

        /* ============ STX ============ */
        case 0x86: /* STX dp */
            addr = addr_dp(cpu);
            write_val(cpu, addr, cpu->x, width_x);
            cycles = 3;
            break;
        case 0x96: /* STX dp,Y */
            addr = addr_dpy(cpu);
            write_val(cpu, addr, cpu->x, width_x);
            cycles = 4;
            break;
        case 0x8E: /* STX abs */
            addr = addr_abs(cpu);
            write_val(cpu, addr, cpu->x, width_x);
            cycles = 4;
            break;

        /* ============ STY ============ */
        case 0x84: /* STY dp */
            addr = addr_dp(cpu);
            write_val(cpu, addr, cpu->y, width_x);
            cycles = 3;
            break;
        case 0x94: /* STY dp,X */
            addr = addr_dpx(cpu);
            write_val(cpu, addr, cpu->y, width_x);
            cycles = 4;
            break;
        case 0x8C: /* STY abs */
            addr = addr_abs(cpu);
            write_val(cpu, addr, cpu->y, width_x);
            cycles = 4;
            break;

        /* ============ STZ ============ */
        case 0x64: /* STZ dp */
            addr = addr_dp(cpu);
            write_val(cpu, addr, 0, width_m);
            cycles = 3;
            break;
        case 0x74: /* STZ dp,X */
            addr = addr_dpx(cpu);
            write_val(cpu, addr, 0, width_m);
            cycles = 4;
            break;
        case 0x9C: /* STZ abs */
            addr = addr_abs(cpu);
            write_val(cpu, addr, 0, width_m);
            cycles = 4;
            break;
        case 0x9E: /* STZ abs,X */
            addr = addr_absx(cpu);
            write_val(cpu, addr, 0, width_m);
            cycles = 5;
            break;

        /* ============ ADC ============ */
        case 0x69: /* ADC #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 2;
            break;
        case 0x65: /* ADC dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 3;
            break;
        case 0x75: /* ADC dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x6D: /* ADC abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x7D: /* ADC abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x79: /* ADC abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x61: /* ADC (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x71: /* ADC (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x72: /* ADC (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x67: /* ADC [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x77: /* ADC [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x63: /* ADC sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x73: /* ADC (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_adc(cpu, val, width_m);
            cycles = 7;
            break;

        /* ============ SBC ============ */
        case 0xE9: /* SBC #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 2;
            break;
        case 0xE5: /* SBC dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 3;
            break;
        case 0xF5: /* SBC dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0xED: /* SBC abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0xFD: /* SBC abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0xF9: /* SBC abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0xE1: /* SBC (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0xF1: /* SBC (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 5;
            break;
        case 0xF2: /* SBC (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 5;
            break;
        case 0xE7: /* SBC [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0xF7: /* SBC [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 6;
            break;
        case 0xE3: /* SBC sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 4;
            break;
        case 0xF3: /* SBC (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_sbc(cpu, val, width_m);
            cycles = 7;
            break;

        /* ============ CMP ============ */
        case 0xC9: /* CMP #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 2;
            break;
        case 0xC5: /* CMP dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 3;
            break;
        case 0xD5: /* CMP dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 4;
            break;
        case 0xCD: /* CMP abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 4;
            break;
        case 0xDD: /* CMP abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 4;
            break;
        case 0xD9: /* CMP abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 4;
            break;
        case 0xC1: /* CMP (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 6;
            break;
        case 0xD1: /* CMP (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 5;
            break;
        case 0xD2: /* CMP (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 5;
            break;
        case 0xC7: /* CMP [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 6;
            break;
        case 0xD7: /* CMP [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 6;
            break;
        case 0xC3: /* CMP sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 4;
            break;
        case 0xD3: /* CMP (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_cmp(cpu, cpu->a, val, width_m);
            cycles = 7;
            break;

        /* ============ CPX ============ */
        case 0xE0: /* CPX #imm */
            addr = addr_imm(cpu, width_x);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->x, val, width_x);
            cycles = 2;
            break;
        case 0xE4: /* CPX dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->x, val, width_x);
            cycles = 3;
            break;
        case 0xEC: /* CPX abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->x, val, width_x);
            cycles = 4;
            break;

        /* ============ CPY ============ */
        case 0xC0: /* CPY #imm */
            addr = addr_imm(cpu, width_x);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->y, val, width_x);
            cycles = 2;
            break;
        case 0xC4: /* CPY dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->y, val, width_x);
            cycles = 3;
            break;
        case 0xCC: /* CPY abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_x);
            op_cmp(cpu, cpu->y, val, width_x);
            cycles = 4;
            break;

        /* ============ AND ============ */
        case 0x29: /* AND #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 2;
            break;
        case 0x25: /* AND dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 3;
            break;
        case 0x35: /* AND dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x2D: /* AND abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x3D: /* AND abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x39: /* AND abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x21: /* AND (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x31: /* AND (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x32: /* AND (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x27: /* AND [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x37: /* AND [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x23: /* AND sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x33: /* AND (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_and(cpu, val, width_m);
            cycles = 7;
            break;

        /* ============ ORA ============ */
        case 0x09: /* ORA #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 2;
            break;
        case 0x05: /* ORA dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 3;
            break;
        case 0x15: /* ORA dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x0D: /* ORA abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x1D: /* ORA abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x19: /* ORA abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x01: /* ORA (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x11: /* ORA (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x12: /* ORA (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x07: /* ORA [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x17: /* ORA [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x03: /* ORA sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x13: /* ORA (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_ora(cpu, val, width_m);
            cycles = 7;
            break;

        /* ============ EOR ============ */
        case 0x49: /* EOR #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 2;
            break;
        case 0x45: /* EOR dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 3;
            break;
        case 0x55: /* EOR dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x4D: /* EOR abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x5D: /* EOR abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x59: /* EOR abs,Y */
            addr = addr_absy(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x41: /* EOR (dp,X) */
            addr = addr_dpxi(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x51: /* EOR (dp),Y */
            addr = addr_dpiy(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x52: /* EOR (dp) */
            addr = addr_dpi(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 5;
            break;
        case 0x47: /* EOR [dp] */
            addr = addr_dpil(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x57: /* EOR [dp],Y */
            addr = addr_dpily(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 6;
            break;
        case 0x43: /* EOR sr,S */
            addr = addr_sr(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x53: /* EOR (sr,S),Y */
            addr = addr_sriy(cpu);
            val = read_val(cpu, addr, width_m);
            op_eor(cpu, val, width_m);
            cycles = 7;
            break;

        /* ============ BIT ============ */
        case 0x89: /* BIT #imm */
            addr = addr_imm(cpu, width_m);
            val = read_val(cpu, addr, width_m);
            FLAG_PUT(cpu, P_Z, (cpu->a & val) == 0);
            cycles = 2;
            break;
        case 0x24: /* BIT dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            op_bit(cpu, val, width_m);
            cycles = 3;
            break;
        case 0x34: /* BIT dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            op_bit(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x2C: /* BIT abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            op_bit(cpu, val, width_m);
            cycles = 4;
            break;
        case 0x3C: /* BIT abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            op_bit(cpu, val, width_m);
            cycles = 4;
            break;

        /* ============ ASL ============ */
        case 0x0A: /* ASL A */
            cpu->a = op_asl(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x06: /* ASL dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_asl(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0x16: /* ASL dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_asl(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x0E: /* ASL abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_asl(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x1E: /* ASL abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_asl(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ LSR ============ */
        case 0x4A: /* LSR A */
            cpu->a = op_lsr(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x46: /* LSR dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_lsr(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0x56: /* LSR dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_lsr(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x4E: /* LSR abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_lsr(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x5E: /* LSR abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_lsr(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ ROL ============ */
        case 0x2A: /* ROL A */
            cpu->a = op_rol(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x26: /* ROL dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_rol(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0x36: /* ROL dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_rol(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x2E: /* ROL abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_rol(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x3E: /* ROL abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_rol(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ ROR ============ */
        case 0x6A: /* ROR A */
            cpu->a = op_ror(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x66: /* ROR dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_ror(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0x76: /* ROR dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_ror(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x6E: /* ROR abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_ror(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0x7E: /* ROR abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_ror(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ INC ============ */
        case 0x1A: /* INC A */
            cpu->a = op_inc(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0xE6: /* INC dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_inc(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0xF6: /* INC dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_inc(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0xEE: /* INC abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_inc(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0xFE: /* INC abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_inc(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ DEC ============ */
        case 0x3A: /* DEC A */
            cpu->a = op_dec(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0xC6: /* DEC dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_dec(cpu, val, width_m), width_m);
            cycles = 5;
            break;
        case 0xD6: /* DEC dp,X */
            addr = addr_dpx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_dec(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0xCE: /* DEC abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_dec(cpu, val, width_m), width_m);
            cycles = 6;
            break;
        case 0xDE: /* DEC abs,X */
            addr = addr_absx(cpu);
            val = read_val(cpu, addr, width_m);
            write_val(cpu, addr, op_dec(cpu, val, width_m), width_m);
            cycles = 7;
            break;

        /* ============ INX/INY/DEX/DEY ============ */
        case 0xE8: /* INX */
            cpu->x = op_inc(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0xC8: /* INY */
            cpu->y = op_inc(cpu, cpu->y, width_x);
            cycles = 2;
            break;
        case 0xCA: /* DEX */
            cpu->x = op_dec(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0x88: /* DEY */
            cpu->y = op_dec(cpu, cpu->y, width_x);
            cycles = 2;
            break;

        /* ============ Transfers ============ */
        case 0xAA: /* TAX */
            cpu->x = cpu->a & MASK_X(cpu);
            update_nz(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0xA8: /* TAY */
            cpu->y = cpu->a & MASK_X(cpu);
            update_nz(cpu, cpu->y, width_x);
            cycles = 2;
            break;
        case 0x8A: /* TXA */
            cpu->a = cpu->x & MASK_M(cpu);
            update_nz(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x98: /* TYA */
            cpu->a = cpu->y & MASK_M(cpu);
            update_nz(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0xBA: /* TSX */
            cpu->x = cpu->s & MASK_X(cpu);
            update_nz(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0x9A: /* TXS */
            cpu->s = cpu->x;
            if (IS_EMU(cpu)) cpu->s = 0x100 | (cpu->s & 0xFF);
            cycles = 2;
            break;
        case 0x9B: /* TXY */
            cpu->y = cpu->x;
            update_nz(cpu, cpu->y, width_x);
            cycles = 2;
            break;
        case 0xBB: /* TYX */
            cpu->x = cpu->y;
            update_nz(cpu, cpu->x, width_x);
            cycles = 2;
            break;
        case 0x5B: /* TCD */
            cpu->d = cpu->a;
            update_nz16(cpu, (uint16_t)cpu->d);
            cycles = 2;
            break;
        case 0x7B: /* TDC */
            cpu->a = cpu->d & MASK_M(cpu);
            update_nz(cpu, cpu->a, width_m);
            cycles = 2;
            break;
        case 0x1B: /* TCS */
            cpu->s = cpu->a;
            if (IS_EMU(cpu)) cpu->s = 0x100 | (cpu->s & 0xFF);
            cycles = 2;
            break;
        case 0x3B: /* TSC */
            cpu->a = cpu->s;
            update_nz(cpu, cpu->a, width_m);
            cycles = 2;
            break;

        /* ============ Stack ============ */
        case 0x48: /* PHA */
            if (width_m == 4) push32(cpu, cpu->a);
            else if (width_m == 2) push16(cpu, (uint16_t)cpu->a);
            else push8(cpu, (uint8_t)cpu->a);
            cycles = 3;
            break;
        case 0x68: /* PLA */
            if (width_m == 4) cpu->a = pull32(cpu);
            else if (width_m == 2) cpu->a = pull16(cpu);
            else cpu->a = pull8(cpu);
            update_nz(cpu, cpu->a, width_m);
            cycles = 4;
            break;
        case 0xDA: /* PHX */
            if (width_x == 4) push32(cpu, cpu->x);
            else if (width_x == 2) push16(cpu, (uint16_t)cpu->x);
            else push8(cpu, (uint8_t)cpu->x);
            cycles = 3;
            break;
        case 0xFA: /* PLX */
            if (width_x == 4) cpu->x = pull32(cpu);
            else if (width_x == 2) cpu->x = pull16(cpu);
            else cpu->x = pull8(cpu);
            update_nz(cpu, cpu->x, width_x);
            cycles = 4;
            break;
        case 0x5A: /* PHY */
            if (width_x == 4) push32(cpu, cpu->y);
            else if (width_x == 2) push16(cpu, (uint16_t)cpu->y);
            else push8(cpu, (uint8_t)cpu->y);
            cycles = 3;
            break;
        case 0x7A: /* PLY */
            if (width_x == 4) cpu->y = pull32(cpu);
            else if (width_x == 2) cpu->y = pull16(cpu);
            else cpu->y = pull8(cpu);
            update_nz(cpu, cpu->y, width_x);
            cycles = 4;
            break;
        case 0x08: /* PHP */
            push8(cpu, (uint8_t)(cpu->p | 0x30));  /* B and unused set */
            cycles = 3;
            break;
        case 0x28: /* PLP */
            cpu->p = (cpu->p & 0xFF00) | pull8(cpu);
            cycles = 4;
            break;
        case 0x0B: /* PHD */
            push16(cpu, (uint16_t)cpu->d);
            cycles = 4;
            break;
        case 0x2B: /* PLD */
            cpu->d = pull16(cpu);
            update_nz16(cpu, (uint16_t)cpu->d);
            cycles = 5;
            break;
        case 0x8B: /* PHB */
            push8(cpu, (uint8_t)(cpu->b >> 16));
            cycles = 3;
            break;
        /* Note: $AB is LDA long in M65832 (see LDA section), not PLB */
        /* PLB is extended opcode $02 $73 in M65832 */
        case 0x4B: /* PHK */
            push8(cpu, (uint8_t)(cpu->pc >> 16));
            cycles = 3;
            break;
        case 0xF4: /* PEA abs */
            push16(cpu, fetch16(cpu));
            cycles = 5;
            break;
        case 0xD4: /* PEI (dp) */
            addr = addr_dp(cpu);
            push16(cpu, mem_read16(cpu, addr));
            cycles = 6;
            break;
        case 0x62: /* PER rel16 */
            rel16 = (int16_t)fetch16(cpu);
            push16(cpu, (uint16_t)(cpu->pc + rel16));
            cycles = 6;
            break;

        /* ============ Branches ============ */
        case 0x10: /* BPL */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (!FLAG_TST(cpu, P_N)) { cpu->pc += rel8; cycles++; }
            break;
        case 0x30: /* BMI */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (FLAG_TST(cpu, P_N)) { cpu->pc += rel8; cycles++; }
            break;
        case 0x50: /* BVC */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (!FLAG_TST(cpu, P_V)) { cpu->pc += rel8; cycles++; }
            break;
        case 0x70: /* BVS */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (FLAG_TST(cpu, P_V)) { cpu->pc += rel8; cycles++; }
            break;
        case 0x90: /* BCC */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (!FLAG_TST(cpu, P_C)) { cpu->pc += rel8; cycles++; }
            break;
        case 0xB0: /* BCS */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (FLAG_TST(cpu, P_C)) { cpu->pc += rel8; cycles++; }
            break;
        case 0xD0: /* BNE */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (!FLAG_TST(cpu, P_Z)) { cpu->pc += rel8; cycles++; }
            break;
        case 0xF0: /* BEQ */
            rel8 = (int8_t)fetch8(cpu);
            cycles = 2;
            if (FLAG_TST(cpu, P_Z)) { cpu->pc += rel8; cycles++; }
            break;
        case 0x80: /* BRA */
            rel8 = (int8_t)fetch8(cpu);
            cpu->pc += rel8;
            cycles = 3;
            break;
        case 0x82: /* BRL */
            rel16 = (int16_t)fetch16(cpu);
            cpu->pc += rel16;
            cycles = 4;
            break;

        /* ============ Jumps ============ */
        case 0x4C: /* JMP abs */
            cpu->pc = (cpu->pc & 0xFFFF0000) | fetch16(cpu);
            cycles = 3;
            break;
        case 0x5C: /* JMP long (24-bit, keeping for 65816 compat) */
            addr = fetch16(cpu);
            addr |= (uint32_t)fetch8(cpu) << 16;
            cpu->pc = addr;
            cycles = 4;
            break;
        case 0x6C: /* JMP (abs) */
            addr = addr_abs(cpu);
            cpu->pc = mem_read16(cpu, addr);
            cycles = 5;
            break;
        case 0x7C: /* JMP (abs,X) */
            addr = addr_absx(cpu);
            cpu->pc = mem_read16(cpu, addr);
            cycles = 6;
            break;
        case 0xDC: /* JML [abs] */
            addr = addr_abs(cpu);
            cpu->pc = mem_read32(cpu, addr);
            cycles = 6;
            break;

        /* ============ Subroutines ============ */
        case 0x20: /* JSR abs */
            addr = fetch16(cpu);
            push16(cpu, (uint16_t)(cpu->pc - 1));
            cpu->pc = (cpu->pc & 0xFFFF0000) | addr;
            cycles = 6;
            break;
        case 0x22: /* JSL long */
            addr = fetch16(cpu);
            addr |= (uint32_t)fetch8(cpu) << 16;
            push8(cpu, (uint8_t)(cpu->pc >> 16));
            push16(cpu, (uint16_t)(cpu->pc - 1));
            cpu->pc = addr;
            cycles = 8;
            break;
        case 0xFC: /* JSR (abs,X) */
            addr = addr_absx(cpu);
            push16(cpu, (uint16_t)(cpu->pc - 1));
            cpu->pc = mem_read16(cpu, addr);
            cycles = 8;
            break;
        case 0x60: /* RTS */
            cpu->pc = (pull16(cpu) + 1) & 0xFFFF;
            cycles = 6;
            break;
        case 0x6B: /* RTL */
            cpu->pc = pull16(cpu) + 1;
            cpu->pc |= (uint32_t)pull8(cpu) << 16;
            cycles = 6;
            break;

        /* ============ Interrupts ============ */
        case 0x00: /* BRK - Software break */
            /* M65832: BRK pushes PC (the address after the BRK opcode), not PC+1.
             * This differs from 65816 which pushes PC+2 to skip the signature byte.
             * After fetch, cpu->pc points to the byte after BRK, which is the return address. */
            exception_enter(cpu, IS_EMU(cpu) ? VEC_IRQ_EMU : VEC_BRK, cpu->pc);
            FLAG_CLR(cpu, P_D);  /* Clear decimal mode */
            cpu->trap = TRAP_BRK;
            cycles = 7;
            break;
        case 0x02: /* Extended prefix (M65832 allows in both modes) */
            /* Note: M65832 VHDL tests use $02 as EXT prefix even in emulation mode.
             * This differs from standard 65816 which has COP in emulation mode.
             * For M65832 compatibility, always treat $02 as extended prefix. */
            {
                ext_op = fetch8(cpu);
                cycles = 3;  /* Base for extended */
                switch (ext_op) {
                    case 0x00: /* MUL dp */
                        addr = addr_dp(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (width_m == 4) {
                            uint64_t result = (uint64_t)cpu->a * (uint64_t)val;
                            cpu->a = (uint32_t)result;
                            cpu->t = (uint32_t)(result >> 32);
                        } else if (width_m == 2) {
                            uint32_t result = (uint32_t)(cpu->a & 0xFFFF) * (uint32_t)(val & 0xFFFF);
                            cpu->a = result;
                        } else {
                            uint16_t result = (uint16_t)(cpu->a & 0xFF) * (uint16_t)(val & 0xFF);
                            cpu->a = result;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 8;
                        break;
                    case 0x01: /* MULU dp (unsigned) */
                        addr = addr_dp(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (width_m == 4) {
                            uint64_t result = (uint64_t)cpu->a * (uint64_t)val;
                            cpu->a = (uint32_t)result;
                            cpu->t = (uint32_t)(result >> 32);
                        } else if (width_m == 2) {
                            uint32_t result = (cpu->a & 0xFFFF) * (val & 0xFFFF);
                            cpu->a = result;
                        } else {
                            uint16_t result = (cpu->a & 0xFF) * (val & 0xFF);
                            cpu->a = result;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 8;
                        break;
                    case 0x02: /* MUL abs (signed) */
                        addr = addr_abs(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (width_m == 4) {
                            int64_t result = (int64_t)(int32_t)cpu->a * (int64_t)(int32_t)val;
                            cpu->a = (uint32_t)result;
                            cpu->t = (uint32_t)(result >> 32);
                        } else if (width_m == 2) {
                            int32_t result = (int32_t)(int16_t)(cpu->a & 0xFFFF) * (int32_t)(int16_t)(val & 0xFFFF);
                            cpu->a = (uint32_t)result;
                        } else {
                            int16_t result = (int16_t)(int8_t)(cpu->a & 0xFF) * (int16_t)(int8_t)(val & 0xFF);
                            cpu->a = (uint16_t)result;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 8;
                        break;
                    case 0x03: /* MULU abs (unsigned) */
                        addr = addr_abs(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (width_m == 4) {
                            uint64_t result = (uint64_t)cpu->a * (uint64_t)val;
                            cpu->a = (uint32_t)result;
                            cpu->t = (uint32_t)(result >> 32);
                        } else if (width_m == 2) {
                            uint32_t result = (cpu->a & 0xFFFF) * (val & 0xFFFF);
                            cpu->a = result;
                        } else {
                            uint16_t result = (cpu->a & 0xFF) * (val & 0xFF);
                            cpu->a = result;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 8;
                        break;
                    case 0x04: /* DIV dp */
                        addr = addr_dp(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val != 0) {
                            cpu->t = cpu->a % val;
                            cpu->a = cpu->a / val;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 16;
                        break;
                    case 0x05: /* DIVU dp */
                        addr = addr_dp(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val != 0) {
                            cpu->t = cpu->a % val;
                            cpu->a = cpu->a / val;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 16;
                        break;
                    case 0x06: /* DIV abs (signed) */
                        addr = addr_abs(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val != 0) {
                            int32_t dividend = (int32_t)cpu->a;
                            int32_t divisor = (int32_t)val;
                            cpu->t = (uint32_t)(dividend % divisor);
                            cpu->a = (uint32_t)(dividend / divisor);
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 16;
                        break;
                    case 0x07: /* DIVU abs (unsigned) */
                        addr = addr_abs(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val != 0) {
                            cpu->t = cpu->a % val;
                            cpu->a = cpu->a / val;
                        }
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 16;
                        break;
                    
                    /* === Atomic Operations === */
                    case 0x10: { /* CAS dp - Compare and Swap */
                        addr = addr_dp(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val == cpu->x) {
                            /* Match: store A, set Z */
                            write_val(cpu, addr, cpu->a, width_m);
                            FLAG_SET(cpu, P_Z);
                        } else {
                            /* No match: load current into X, clear Z */
                            cpu->x = val;
                            FLAG_CLR(cpu, P_Z);
                        }
                        cycles = 8;
                        break;
                    }
                    case 0x11: { /* CAS abs - Compare and Swap */
                        addr = addr_abs(cpu);
                        val = read_val(cpu, addr, width_m);
                        if (val == cpu->x) {
                            write_val(cpu, addr, cpu->a, width_m);
                            FLAG_SET(cpu, P_Z);
                        } else {
                            cpu->x = val;
                            FLAG_CLR(cpu, P_Z);
                        }
                        cycles = 9;
                        break;
                    }
                    case 0x12: { /* LLI dp - Load Linked */
                        addr = addr_dp(cpu);
                        cpu->a = read_val(cpu, addr, width_m);
                        cpu->ll_addr = addr;
                        cpu->ll_valid = true;
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 4;
                        break;
                    }
                    case 0x13: { /* LLI abs - Load Linked */
                        addr = addr_abs(cpu);
                        cpu->a = read_val(cpu, addr, width_m);
                        cpu->ll_addr = addr;
                        cpu->ll_valid = true;
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 5;
                        break;
                    }
                    case 0x14: { /* SCI dp - Store Conditional */
                        addr = addr_dp(cpu);
                        if (cpu->ll_valid && cpu->ll_addr == addr) {
                            write_val(cpu, addr, cpu->a, width_m);
                            FLAG_SET(cpu, P_Z);
                        } else {
                            FLAG_CLR(cpu, P_Z);
                        }
                        cpu->ll_valid = false;
                        cycles = 5;
                        break;
                    }
                    case 0x15: { /* SCI abs - Store Conditional */
                        addr = addr_abs(cpu);
                        if (cpu->ll_valid && cpu->ll_addr == addr) {
                            write_val(cpu, addr, cpu->a, width_m);
                            FLAG_SET(cpu, P_Z);
                        } else {
                            FLAG_CLR(cpu, P_Z);
                        }
                        cpu->ll_valid = false;
                        cycles = 6;
                        break;
                    }
                    
                    case 0x20: /* SD imm32 - Set D register from 32-bit immediate */
                        cpu->d = fetch32(cpu);
                        cycles = 4;
                        break;
                    case 0x21: /* SD dp - Set D register from dp memory */
                        addr = addr_dp(cpu);
                        cpu->d = mem_read32(cpu, addr);
                        cycles = 5;
                        break;
                    case 0x22: /* SB imm32 - Set B register from 32-bit immediate */
                        cpu->b = fetch32(cpu);
                        cycles = 4;
                        break;
                    case 0x23: /* SB dp - Set B register from dp memory */
                        addr = addr_dp(cpu);
                        cpu->b = mem_read32(cpu, addr);
                        cycles = 5;
                        break;
                    case 0x24: /* SD_X imm32 - Set D from immediate (alt) */
                        cpu->d = fetch32(cpu);
                        cycles = 4;
                        break;
                    case 0x25: /* SD_X dp - Set D from dp (alt) */
                        addr = addr_dp(cpu);
                        cpu->d = mem_read32(cpu, addr);
                        cycles = 5;
                        break;
                    
                    /* === LEA (Load Effective Address) === */
                    case 0xA0: /* LEA dp - Load dp address into A */
                        {
                            uint8_t dp_offset = fetch8(cpu);
                            cpu->a = cpu->d + dp_offset;
                            update_nz32(cpu, cpu->a);
                        }
                        cycles = 3;
                        break;
                    case 0xA1: /* LEA dp,X - Load dp+X address into A */
                        {
                            uint8_t dp_offset = fetch8(cpu);
                            cpu->a = cpu->d + dp_offset + cpu->x;
                            update_nz32(cpu, cpu->a);
                        }
                        cycles = 3;
                        break;
                    case 0xA2: /* LEA abs - Load abs address into A */
                        cpu->a = fetch16(cpu);
                        update_nz32(cpu, cpu->a);
                        cycles = 4;
                        break;
                    case 0xA3: /* LEA abs,X - Load abs+X address into A */
                        cpu->a = fetch16(cpu) + cpu->x;
                        update_nz32(cpu, cpu->a);
                        cycles = 4;
                        break;
                    case 0x30: /* ENR - Enable Register window */
                        FLAG_SET(cpu, P_R);
                        cycles = 2;
                        break;
                    case 0x31: /* DSR - Disable Register window */
                        FLAG_CLR(cpu, P_R);
                        cycles = 2;
                        break;
                    case 0x40: { /* TRAP #imm8 - System call */
                        uint8_t trap_code = fetch8(cpu);
                        uint32_t trap_vector = VEC_SYSCALL + (trap_code * 4);
                        exception_enter(cpu, trap_vector, cpu->pc);
                        cpu->trap = TRAP_SYSCALL;
                        cpu->trap_addr = trap_code;
                        cycles = 8;
                        break;
                    }
                    case 0x50: /* FENCE */
                        cycles = 2;
                        break;
                    case 0x51: /* FENCER */
                        cycles = 2;
                        break;
                    case 0x52: /* FENCEW */
                        cycles = 2;
                        break;
                    case 0x86: /* TTA - T to A */
                        cpu->a = cpu->t;
                        update_nz(cpu, cpu->a, width_m);
                        cycles = 2;
                        break;
                    case 0x87: /* TAT - A to T */
                        cpu->t = cpu->a;
                        cycles = 2;
                        break;
                    
                    /* === 64-bit Load/Store (LDQ/STQ) === */
                    case 0x88: /* LDQ dp - Load 64-bit (A=low, T=high) */
                        addr = addr_dp(cpu);
                        cpu->a = mem_read32(cpu, addr);
                        cpu->t = mem_read32(cpu, addr + 4);
                        update_nz32(cpu, cpu->a);
                        cycles = 6;
                        break;
                    case 0x89: /* LDQ abs - Load 64-bit */
                        addr = addr_abs(cpu);
                        cpu->a = mem_read32(cpu, addr);
                        cpu->t = mem_read32(cpu, addr + 4);
                        update_nz32(cpu, cpu->a);
                        cycles = 7;
                        break;
                    case 0x8A: /* STQ dp - Store 64-bit (A=low, T=high) */
                        addr = addr_dp(cpu);
                        mem_write32(cpu, addr, cpu->a);
                        mem_write32(cpu, addr + 4, cpu->t);
                        cycles = 6;
                        break;
                    case 0x8B: /* STQ abs - Store 64-bit */
                        addr = addr_abs(cpu);
                        mem_write32(cpu, addr, cpu->a);
                        mem_write32(cpu, addr + 4, cpu->t);
                        cycles = 7;
                        break;
                    
                    /* === Register-Targeted ALU ($E8) === */
                    case 0xE8: {
                        /* Format: $02 $E8 [op|mode] [dest_dp] [source_operand...] */
                        uint8_t op_mode = fetch8(cpu);
                        uint8_t op = (op_mode >> 4) & 0x0F;
                        uint8_t mode = op_mode & 0x0F;
                        uint8_t dest_dp = fetch8(cpu);
                        uint32_t dest_addr = cpu->d + dest_dp;
                        uint32_t src_val;
                        
                        /* Fetch source based on addressing mode */
                        switch (mode) {
                            case 0x0: /* (dp,X) */
                                addr = addr_dpxi(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x1: /* dp */
                                addr = addr_dp(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x2: /* #imm */
                                if (width_m == 4) src_val = fetch32(cpu);
                                else if (width_m == 2) src_val = fetch16(cpu);
                                else src_val = fetch8(cpu);
                                break;
                            case 0x3: /* A */
                                src_val = cpu->a;
                                break;
                            case 0x4: /* (dp),Y */
                                addr = addr_dpiy(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x5: /* dp,X */
                                addr = addr_dpx(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x6: /* abs */
                                addr = addr_abs(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x7: /* abs,X */
                                addr = addr_absx(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x8: /* abs,Y */
                                addr = addr_absy(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0x9: /* (dp) */
                                addr = addr_dpi(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0xA: /* [dp] */
                                addr = addr_dpil(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0xB: /* [dp],Y */
                                addr = addr_dpily(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0xC: /* sr,S */
                                addr = addr_sr(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            case 0xD: /* (sr,S),Y */
                                addr = addr_sriy(cpu);
                                src_val = read_val(cpu, addr, width_m);
                                break;
                            default:
                                src_val = 0;
                                break;
                        }
                        
                        /* Read destination value */
                        uint32_t dest_val = read_val(cpu, dest_addr, width_m);
                        uint32_t result;
                        
                        /* Perform operation */
                        switch (op) {
                            case 0: /* LD - just load source to dest */
                                result = src_val;
                                write_val(cpu, dest_addr, result, width_m);
                                update_nz(cpu, result, width_m);
                                break;
                            case 1: /* ADC */
                                result = do_adc(cpu, dest_val, src_val, width_m);
                                write_val(cpu, dest_addr, result, width_m);
                                break;
                            case 2: /* SBC */
                                result = do_sbc(cpu, dest_val, src_val, width_m);
                                write_val(cpu, dest_addr, result, width_m);
                                break;
                            case 3: /* AND */
                                result = dest_val & src_val;
                                write_val(cpu, dest_addr, result, width_m);
                                update_nz(cpu, result, width_m);
                                break;
                            case 4: /* ORA */
                                result = dest_val | src_val;
                                write_val(cpu, dest_addr, result, width_m);
                                update_nz(cpu, result, width_m);
                                break;
                            case 5: /* EOR */
                                result = dest_val ^ src_val;
                                write_val(cpu, dest_addr, result, width_m);
                                update_nz(cpu, result, width_m);
                                break;
                            case 6: /* CMP - compare only, don't write */
                                do_cmp(cpu, dest_val, src_val, width_m);
                                break;
                            default:
                                break;
                        }
                        cycles = 5;  /* Base cycles, varies by mode */
                        break;
                    }
                    
                    /* === Barrel Shifter ($E9) === */
                    case 0xE9: {
                        /* Format: $02 $E9 [op|cnt] [dest_dp] [src_dp] */
                        uint8_t op_cnt = fetch8(cpu);
                        uint8_t shift_op = (op_cnt >> 5) & 0x07;
                        uint8_t count = op_cnt & 0x1F;
                        uint8_t dest_dp = fetch8(cpu);
                        uint8_t src_dp = fetch8(cpu);
                        
                        uint32_t dest_addr = cpu->d + dest_dp;
                        uint32_t src_addr = cpu->d + src_dp;
                        uint32_t src_val = read_val(cpu, src_addr, width_m);
                        uint32_t result;
                        
                        /* If count is 31 ($1F), use A register for shift amount */
                        if (count == 0x1F) {
                            count = cpu->a & 0x1F;
                        }
                        
                        uint32_t mask = MASK_M(cpu);
                        int sign_bit = (width_m == 4) ? 31 : (width_m == 2) ? 15 : 7;
                        
                        switch (shift_op) {
                            case 0: /* SHL - Shift left logical */
                                result = (src_val << count) & mask;
                                FLAG_PUT(cpu, P_C, (count > 0) && ((src_val >> (sign_bit + 1 - count)) & 1));
                                break;
                            case 1: /* SHR - Shift right logical */
                                result = (src_val >> count) & mask;
                                FLAG_PUT(cpu, P_C, (count > 0) && ((src_val >> (count - 1)) & 1));
                                break;
                            case 2: /* SAR - Shift right arithmetic */
                                {
                                    int32_t signed_val;
                                    if (width_m == 1) signed_val = (int8_t)src_val;
                                    else if (width_m == 2) signed_val = (int16_t)src_val;
                                    else signed_val = (int32_t)src_val;
                                    result = ((uint32_t)(signed_val >> count)) & mask;
                                    FLAG_PUT(cpu, P_C, (count > 0) && ((src_val >> (count - 1)) & 1));
                                }
                                break;
                            case 3: /* ROL - Rotate left through carry */
                                {
                                    uint32_t c = FLAG_TST(cpu, P_C) ? 1 : 0;
                                    for (int i = 0; i < count; i++) {
                                        uint32_t new_c = (src_val >> sign_bit) & 1;
                                        src_val = ((src_val << 1) | c) & mask;
                                        c = new_c;
                                    }
                                    result = src_val;
                                    FLAG_PUT(cpu, P_C, c);
                                }
                                break;
                            case 4: /* ROR - Rotate right through carry */
                                {
                                    uint32_t c = FLAG_TST(cpu, P_C) ? 1 : 0;
                                    for (int i = 0; i < count; i++) {
                                        uint32_t new_c = src_val & 1;
                                        src_val = ((src_val >> 1) | (c << sign_bit)) & mask;
                                        c = new_c;
                                    }
                                    result = src_val;
                                    FLAG_PUT(cpu, P_C, c);
                                }
                                break;
                            default:
                                result = src_val;
                                break;
                        }
                        
                        write_val(cpu, dest_addr, result, width_m);
                        update_nz(cpu, result, width_m);
                        cycles = 3;  /* Single-cycle barrel shifter + overhead */
                        break;
                    }
                    
                    /* === Sign/Zero Extend ($EA) === */
                    case 0xEA: {
                        /* Format: $02 $EA [subop] [dest_dp] [src_dp] */
                        uint8_t subop = fetch8(cpu);
                        uint8_t dest_dp = fetch8(cpu);
                        uint8_t src_dp = fetch8(cpu);
                        
                        uint32_t dest_addr = cpu->d + dest_dp;
                        uint32_t src_addr = cpu->d + src_dp;
                        uint32_t src_val = read_val(cpu, src_addr, width_m);
                        uint32_t result;
                        
                        switch (subop) {
                            case 0x00: /* SEXT8 - Sign extend 8-bit to 32-bit */
                                result = (uint32_t)(int32_t)(int8_t)(src_val & 0xFF);
                                break;
                            case 0x01: /* SEXT16 - Sign extend 16-bit to 32-bit */
                                result = (uint32_t)(int32_t)(int16_t)(src_val & 0xFFFF);
                                break;
                            case 0x02: /* ZEXT8 - Zero extend 8-bit to 32-bit */
                                result = src_val & 0xFF;
                                break;
                            case 0x03: /* ZEXT16 - Zero extend 16-bit to 32-bit */
                                result = src_val & 0xFFFF;
                                break;
                            case 0x04: /* CLZ - Count leading zeros */
                                if (src_val == 0) {
                                    result = (width_m == 4) ? 32 : (width_m == 2) ? 16 : 8;
                                } else {
                                    result = 0;
                                    uint32_t mask_bit = 1u << ((width_m * 8) - 1);
                                    while (!(src_val & mask_bit)) {
                                        result++;
                                        mask_bit >>= 1;
                                    }
                                }
                                break;
                            case 0x05: /* CTZ - Count trailing zeros */
                                if (src_val == 0) {
                                    result = (width_m == 4) ? 32 : (width_m == 2) ? 16 : 8;
                                } else {
                                    result = 0;
                                    uint32_t v = src_val;
                                    while (!(v & 1)) {
                                        result++;
                                        v >>= 1;
                                    }
                                }
                                break;
                            case 0x06: /* POPCNT - Population count */
                                {
                                    result = 0;
                                    uint32_t v = src_val & MASK_M(cpu);
                                    while (v) {
                                        result += v & 1;
                                        v >>= 1;
                                    }
                                }
                                break;
                            default:
                                result = src_val;
                                break;
                        }
                        
                        write_val(cpu, dest_addr, result, width_m);
                        update_nz(cpu, result, width_m);
                        cycles = 3;
                        break;
                    }
                    
                    default:
                        /* Unknown extended opcode - check compatibility mode.
                         * compat_mode = 1 when M_width=32 OR K=1, per VHDL. */
                        if (SIZE_M(cpu) == 4 || FLAG_TST(cpu, P_K)) {
                            /* Compatibility mode - treat as NOP */
                            cycles = 2;
                        } else {
                            /* Strict mode - trap to illegal instruction handler */
                            illegal_instruction(cpu);
                            cycles = 7;
                        }
                        break;
                }
            }
            break;
        case 0x40: /* RTI - Return from Interrupt */
            /* M65832: RTI ALWAYS pulls 16-bit P and 32-bit PC regardless of E mode.
             * This allows switching from emulation to native mode via RTI. */
            {
                uint8_t p_lo = pull8(cpu);
                uint8_t p_hi = pull8(cpu);
                cpu->p = (uint16_t)p_lo | ((uint16_t)p_hi << 8);
                uint8_t pc0 = pull8(cpu);
                uint8_t pc1 = pull8(cpu);
                uint8_t pc2 = pull8(cpu);
                uint8_t pc3 = pull8(cpu);
                cpu->pc = (uint32_t)pc0 | ((uint32_t)pc1 << 8) |
                          ((uint32_t)pc2 << 16) | ((uint32_t)pc3 << 24);
            }
            cycles = 6;
            break;

        /* ============ WID prefix (0x42) ============ */
        case 0x42: /* WID - 32-bit operand prefix */
            opcode = fetch8(cpu);
            /* Execute instruction with 32-bit operand */
            switch (opcode) {
                case 0xA9: /* LDA #imm32 */
                    cpu->a = fetch32(cpu);
                    update_nz32(cpu, cpu->a);
                    cycles = 3;
                    break;
                case 0xA2: /* LDX #imm32 */
                    cpu->x = fetch32(cpu);
                    update_nz32(cpu, cpu->x);
                    cycles = 3;
                    break;
                case 0xA0: /* LDY #imm32 */
                    cpu->y = fetch32(cpu);
                    update_nz32(cpu, cpu->y);
                    cycles = 3;
                    break;
                case 0xAD: /* LDA long */
                    addr = fetch32(cpu);
                    cpu->a = read_val(cpu, addr, width_m);
                    update_nz(cpu, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0xBD: /* LDA long,X */
                    addr = fetch32(cpu) + cpu->x;
                    cpu->a = read_val(cpu, addr, width_m);
                    update_nz(cpu, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0xB9: /* LDA long,Y */
                    addr = fetch32(cpu) + cpu->y;
                    cpu->a = read_val(cpu, addr, width_m);
                    update_nz(cpu, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0x8D: /* STA long */
                    addr = fetch32(cpu);
                    write_val(cpu, addr, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0x9D: /* STA long,X */
                    addr = fetch32(cpu) + cpu->x;
                    write_val(cpu, addr, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0x99: /* STA long,Y */
                    addr = fetch32(cpu) + cpu->y;
                    write_val(cpu, addr, cpu->a, width_m);
                    cycles = 5;
                    break;
                case 0x4C: /* JMP long */
                    cpu->pc = fetch32(cpu);
                    cycles = 4;
                    break;
                case 0x20: /* JSR long */
                    addr = fetch32(cpu);
                    push32(cpu, cpu->pc);
                    cpu->pc = addr;
                    cycles = 8;
                    break;
                default:
                    /* Unknown WID instruction - check compatibility mode.
                     * compat_mode = 1 when M_width=32 OR K=1, per VHDL. */
                    if (SIZE_M(cpu) == 4 || FLAG_TST(cpu, P_K)) {
                        cycles = 2;
                    } else {
                        /* Strict mode - trap to illegal instruction handler */
                        illegal_instruction(cpu);
                        cycles = 7;
                    }
                    break;
            }
            break;

        /* ============ Flag instructions ============ */
        case 0x18: /* CLC */
            FLAG_CLR(cpu, P_C);
            cycles = 2;
            break;
        case 0x38: /* SEC */
            FLAG_SET(cpu, P_C);
            cycles = 2;
            break;
        case 0x58: /* CLI */
            FLAG_CLR(cpu, P_I);
            cycles = 2;
            break;
        case 0x78: /* SEI */
            FLAG_SET(cpu, P_I);
            cycles = 2;
            break;
        case 0xD8: /* CLD */
            FLAG_CLR(cpu, P_D);
            cycles = 2;
            break;
        case 0xF8: /* SED */
            FLAG_SET(cpu, P_D);
            cycles = 2;
            break;
        case 0xB8: /* CLV */
            FLAG_CLR(cpu, P_V);
            cycles = 2;
            break;
        case 0xC2: /* REP #imm */
            val = fetch8(cpu);
            /* User mode cannot modify S bit */
            if (!FLAG_TST(cpu, P_S)) {
                val &= ~P_S;  /* Mask out S bit for user mode */
            }
            cpu->p &= ~val;
            cycles = 3;
            break;
        case 0xE2: /* SEP #imm */
            val = fetch8(cpu);
            /* User mode cannot set S bit (privilege escalation) */
            if (!FLAG_TST(cpu, P_S)) {
                if (val & P_S) {
                    cpu->trap = TRAP_PRIVILEGE;
                    cpu->trap_addr = cpu->pc - 2;
                    cpu->running = false;
                    cycles = 3;
                    break;
                }
            }
            cpu->p |= val;
            /* Note: M65832 allows width changes in emulation mode (unlike 65816) */
            cycles = 3;
            break;
        case 0xFB: /* XCE - Exchange Carry and Emulation */
            {
                bool c = FLAG_TST(cpu, P_C);
                bool e = FLAG_TST(cpu, P_E);
                FLAG_PUT(cpu, P_C, e);
                FLAG_PUT(cpu, P_E, c);
                if (FLAG_TST(cpu, P_E)) {
                    /* Entering emulation mode - M65832 does NOT force 8-bit width */
                    cpu->s = 0x100 | (cpu->s & 0xFF);  /* Stack limited to page 1 */
                }
            }
            cycles = 2;
            break;

        /* ============ Miscellaneous ============ */
        case 0xEA: /* NOP */
            cycles = 2;
            break;
        case 0xDB: /* STP - Stop (privileged) */
            if (!FLAG_TST(cpu, P_S)) {
                /* User mode - privilege violation */
                cpu->trap = TRAP_PRIVILEGE;
                cpu->trap_addr = cpu->pc - 1;
                cpu->running = false;
            } else {
                cpu->stopped = true;
                cpu->running = false;
            }
            cycles = 3;
            break;
        case 0xCB: /* WAI - Wait for Interrupt */
            cpu->halted = true;
            cycles = 3;
            break;
        case 0xEB: /* XBA */
            cpu->a = ((cpu->a & 0xFF) << 8) | ((cpu->a >> 8) & 0xFF);
            update_nz8(cpu, (uint8_t)cpu->a);
            cycles = 3;
            break;
        case 0x44: /* MVN src,dst (M65832: increments X,Y) */
            {
                uint8_t dst = fetch8(cpu);
                uint8_t src = fetch8(cpu);
                (void)dst; (void)src;  /* Bank bytes ignored in flat model */
                mem_write8(cpu, cpu->y, mem_read8(cpu, cpu->x));
                cpu->x++;
                cpu->y++;
                cpu->a--;
                if ((cpu->a & MASK_M(cpu)) != MASK_M(cpu)) {
                    cpu->pc -= 3;  /* Repeat */
                }
            }
            cycles = 7;
            break;
        case 0x54: /* MVP src,dst (M65832: decrements X,Y) */
            {
                uint8_t dst = fetch8(cpu);
                uint8_t src = fetch8(cpu);
                (void)dst; (void)src;
                mem_write8(cpu, cpu->y, mem_read8(cpu, cpu->x));
                cpu->x--;
                cpu->y--;
                cpu->a--;
                if ((cpu->a & MASK_M(cpu)) != MASK_M(cpu)) {
                    cpu->pc -= 3;
                }
            }
            cycles = 7;
            break;
        case 0x14: /* TRB dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            FLAG_PUT(cpu, P_Z, (cpu->a & val) == 0);
            write_val(cpu, addr, val & ~cpu->a, width_m);
            cycles = 5;
            break;
        case 0x1C: /* TRB abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            FLAG_PUT(cpu, P_Z, (cpu->a & val) == 0);
            write_val(cpu, addr, val & ~cpu->a, width_m);
            cycles = 6;
            break;
        case 0x04: /* TSB dp */
            addr = addr_dp(cpu);
            val = read_val(cpu, addr, width_m);
            FLAG_PUT(cpu, P_Z, (cpu->a & val) == 0);
            write_val(cpu, addr, val | cpu->a, width_m);
            cycles = 5;
            break;
        case 0x0C: /* TSB abs */
            addr = addr_abs(cpu);
            val = read_val(cpu, addr, width_m);
            FLAG_PUT(cpu, P_Z, (cpu->a & val) == 0);
            write_val(cpu, addr, val | cpu->a, width_m);
            cycles = 6;
            break;

        default:
            /* Unknown opcode - check compatibility mode.
             * compat_mode = 1 when M_width=32 OR K=1, per VHDL. */
            if (SIZE_M(cpu) == 4 || FLAG_TST(cpu, P_K)) {
                /* Compatibility mode - NOP */
                cycles = 2;
            } else {
                /* Strict mode - trap to illegal instruction handler */
                illegal_instruction(cpu);
                cycles = 7;
            }
            break;
    }

    return cycles;
}

/* ============================================================================
 * Public API Implementation
 * ========================================================================= */

const char *m65832_version(void) {
    static char ver[32];
    snprintf(ver, sizeof(ver), "%d.%d.%d", 
             M65832EMU_VERSION_MAJOR, M65832EMU_VERSION_MINOR, M65832EMU_VERSION_PATCH);
    return ver;
}

/* ============================================================================
 * Primary Emulator API
 * ========================================================================= */

m65832_cpu_t *m65832_emu_init(size_t memory_size) {
    m65832_cpu_t *cpu = (m65832_cpu_t *)calloc(1, sizeof(m65832_cpu_t));
    if (!cpu) return NULL;
    
    /* Default to 64KB if not specified */
    if (memory_size == 0) memory_size = 65536;
    
    cpu->memory = (uint8_t *)calloc(memory_size, 1);
    if (!cpu->memory) {
        free(cpu);
        return NULL;
    }
    cpu->memory_size = memory_size;
    
    /* Initialize MMIO array */
    cpu->num_mmio = 0;
    memset(cpu->mmio, 0, sizeof(cpu->mmio));
    
    m65832_emu_reset(cpu);
    return cpu;
}

int m65832_emu_step(m65832_cpu_t *cpu) {
    return m65832_step(cpu);
}

uint64_t m65832_emu_run(m65832_cpu_t *cpu, uint64_t cycles) {
    return m65832_run_cycles(cpu, cycles);
}

void m65832_emu_close(m65832_cpu_t *cpu) {
    if (!cpu) return;
    if (cpu->coproc) {
        m65832_coproc_destroy(cpu);
    }
    if (cpu->memory && !cpu->mem_read) {
        free(cpu->memory);
    }
    free(cpu);
}

void m65832_emu_reset(m65832_cpu_t *cpu) {
    if (!cpu) return;
    
    /* Clear all registers (matches RTL regfile reset) */
    cpu->a = 0;
    cpu->x = 0;
    cpu->y = 0;
    cpu->d = 0;
    cpu->b = 0;
    cpu->t = 0;
    cpu->vbr = 0;
    
    /* RTL reset state: P = 0x300C
     * E=1 (emulation), S=1 (supervisor), I=1 (IRQ disabled), D=1 (decimal)
     * M=00 (8-bit in emu), X=00 (8-bit in emu) */
    cpu->p = P_E | P_S | P_I | P_D;
    cpu->s = 0x000001FF;  /* 6502-compatible stack pointer */
    
    /* MMU registers reset */
    cpu->mmucr = 0;       /* Paging disabled */
    cpu->asid = 0;
    cpu->ptbr = 0;
    cpu->faultva = 0;
    
    /* Timer reset */
    cpu->timer_ctrl = 0;
    cpu->timer_cmp = 0;
    cpu->timer_cnt = 0;
    cpu->timer_irq = false;
    
    /* LL/SC reset */
    cpu->ll_addr = 0;
    cpu->ll_valid = false;
    
    /* Fetch reset vector (16-bit in emulation mode) */
    cpu->pc = mem_read16(cpu, 0xFFFC);
    
    cpu->cycles = 0;
    cpu->inst_count = 0;
    cpu->running = true;
    cpu->halted = false;
    cpu->stopped = false;
    cpu->trap = TRAP_NONE;
    
    cpu->irq_pending = false;
    cpu->nmi_pending = false;
    cpu->abort_pending = false;
    
    /* Clear TLB */
    tlb_flush_all(cpu);
}

/*
 * Switch CPU to native 32-bit mode.
 * Call after reset for modern M65832 programs.
 */
void m65832_emu_enter_native32(m65832_cpu_t *cpu) {
    if (!cpu) return;
    
    /* Clear emulation flag, set 32-bit mode */
    cpu->p &= ~P_E;                    /* E=0: native mode */
    cpu->p &= ~(P_M0 | P_M1);          /* Clear M bits */
    cpu->p |= P_M1;                    /* M=10: 32-bit A */
    cpu->p &= ~(P_X0 | P_X1);          /* Clear X bits */
    cpu->p |= P_X1;                    /* X=10: 32-bit X/Y */
    cpu->p &= ~P_D;                    /* D=0: binary mode */
    cpu->s = 0x0000FFFF;               /* Full stack range */
}

bool m65832_emu_is_running(m65832_cpu_t *cpu) {
    return cpu && cpu->running && !cpu->stopped && !cpu->halted;
}

/* ============================================================================
 * Memory Management
 * ========================================================================= */

int m65832_emu_set_memory_size(m65832_cpu_t *cpu, size_t size) {
    if (!cpu || size == 0) return -1;
    
    uint8_t *new_mem = (uint8_t *)realloc(cpu->memory, size);
    if (!new_mem) return -1;
    
    /* Zero out any new memory */
    if (size > cpu->memory_size) {
        memset(new_mem + cpu->memory_size, 0, size - cpu->memory_size);
    }
    
    cpu->memory = new_mem;
    cpu->memory_size = size;
    return 0;
}

size_t m65832_emu_get_memory_size(m65832_cpu_t *cpu) {
    return cpu ? cpu->memory_size : 0;
}

uint8_t m65832_emu_read8(m65832_cpu_t *cpu, uint32_t addr) {
    if (!cpu || !cpu->memory || addr >= cpu->memory_size) return 0xFF;
    return cpu->memory[addr];
}

void m65832_emu_write8(m65832_cpu_t *cpu, uint32_t addr, uint8_t value) {
    if (!cpu || !cpu->memory || addr >= cpu->memory_size) return;
    cpu->memory[addr] = value;
}

uint16_t m65832_emu_read16(m65832_cpu_t *cpu, uint32_t addr) {
    return m65832_emu_read8(cpu, addr) | 
           ((uint16_t)m65832_emu_read8(cpu, addr + 1) << 8);
}

void m65832_emu_write16(m65832_cpu_t *cpu, uint32_t addr, uint16_t value) {
    m65832_emu_write8(cpu, addr, value & 0xFF);
    m65832_emu_write8(cpu, addr + 1, (value >> 8) & 0xFF);
}

uint32_t m65832_emu_read32(m65832_cpu_t *cpu, uint32_t addr) {
    return m65832_emu_read8(cpu, addr) |
           ((uint32_t)m65832_emu_read8(cpu, addr + 1) << 8) |
           ((uint32_t)m65832_emu_read8(cpu, addr + 2) << 16) |
           ((uint32_t)m65832_emu_read8(cpu, addr + 3) << 24);
}

void m65832_emu_write32(m65832_cpu_t *cpu, uint32_t addr, uint32_t value) {
    m65832_emu_write8(cpu, addr, value & 0xFF);
    m65832_emu_write8(cpu, addr + 1, (value >> 8) & 0xFF);
    m65832_emu_write8(cpu, addr + 2, (value >> 16) & 0xFF);
    m65832_emu_write8(cpu, addr + 3, (value >> 24) & 0xFF);
}

size_t m65832_emu_write_block(m65832_cpu_t *cpu, uint32_t addr,
                               const void *data, size_t size) {
    if (!cpu || !cpu->memory || !data) return 0;
    
    size_t avail = (addr < cpu->memory_size) ? cpu->memory_size - addr : 0;
    size_t to_copy = (size < avail) ? size : avail;
    
    if (to_copy > 0) {
        memcpy(cpu->memory + addr, data, to_copy);
    }
    return to_copy;
}

size_t m65832_emu_read_block(m65832_cpu_t *cpu, uint32_t addr,
                              void *data, size_t size) {
    if (!cpu || !cpu->memory || !data) return 0;
    
    size_t avail = (addr < cpu->memory_size) ? cpu->memory_size - addr : 0;
    size_t to_copy = (size < avail) ? size : avail;
    
    if (to_copy > 0) {
        memcpy(data, cpu->memory + addr, to_copy);
    }
    return to_copy;
}

uint8_t *m65832_emu_get_memory_ptr(m65832_cpu_t *cpu) {
    return cpu ? cpu->memory : NULL;
}

/* ============================================================================
 * MMIO API Implementation
 * ========================================================================= */

int m65832_mmio_register(m65832_cpu_t *cpu, uint32_t base, uint32_t size,
                          m65832_mmio_read_fn read_fn,
                          m65832_mmio_write_fn write_fn,
                          void *user, const char *name) {
    if (!cpu || size == 0) return -1;
    if (cpu->num_mmio >= M65832_MAX_MMIO_REGIONS) return -1;
    
    /* Find a free slot */
    int index = -1;
    for (int i = 0; i < M65832_MAX_MMIO_REGIONS; i++) {
        if (!cpu->mmio[i].active && cpu->mmio[i].size == 0) {
            index = i;
            break;
        }
    }
    
    if (index < 0) {
        /* Use next slot */
        if (cpu->num_mmio >= M65832_MAX_MMIO_REGIONS) return -1;
        index = cpu->num_mmio;
    }
    
    m65832_mmio_region_t *r = &cpu->mmio[index];
    r->base = base;
    r->size = size;
    r->read = read_fn;
    r->write = write_fn;
    r->user = user;
    r->name = name;
    r->active = true;
    
    if (index >= cpu->num_mmio) {
        cpu->num_mmio = index + 1;
    }
    
    return index;
}

int m65832_mmio_unregister(m65832_cpu_t *cpu, int index) {
    if (!cpu || index < 0 || index >= cpu->num_mmio) return -1;
    
    m65832_mmio_region_t *r = &cpu->mmio[index];
    r->active = false;
    r->base = 0;
    r->size = 0;
    r->read = NULL;
    r->write = NULL;
    r->user = NULL;
    r->name = NULL;
    
    /* Shrink num_mmio if this was the last one */
    while (cpu->num_mmio > 0 && !cpu->mmio[cpu->num_mmio - 1].active) {
        cpu->num_mmio--;
    }
    
    return 0;
}

int m65832_mmio_unregister_addr(m65832_cpu_t *cpu, uint32_t base) {
    if (!cpu) return -1;
    
    for (int i = 0; i < cpu->num_mmio; i++) {
        if (cpu->mmio[i].active && cpu->mmio[i].base == base) {
            return m65832_mmio_unregister(cpu, i);
        }
    }
    return -1;
}

void m65832_mmio_clear(m65832_cpu_t *cpu) {
    if (!cpu) return;
    
    for (int i = 0; i < cpu->num_mmio; i++) {
        cpu->mmio[i].active = false;
        cpu->mmio[i].base = 0;
        cpu->mmio[i].size = 0;
        cpu->mmio[i].read = NULL;
        cpu->mmio[i].write = NULL;
        cpu->mmio[i].user = NULL;
        cpu->mmio[i].name = NULL;
    }
    cpu->num_mmio = 0;
}

const m65832_mmio_region_t *m65832_mmio_get(m65832_cpu_t *cpu, int index) {
    if (!cpu || index < 0 || index >= cpu->num_mmio) return NULL;
    if (!cpu->mmio[index].active) return NULL;
    return &cpu->mmio[index];
}

int m65832_mmio_find(m65832_cpu_t *cpu, uint32_t addr) {
    if (!cpu) return -1;
    
    for (int i = 0; i < cpu->num_mmio; i++) {
        m65832_mmio_region_t *r = &cpu->mmio[i];
        if (r->active && addr >= r->base && addr < r->base + r->size) {
            return i;
        }
    }
    return -1;
}

int m65832_mmio_count(m65832_cpu_t *cpu) {
    if (!cpu) return 0;
    
    int count = 0;
    for (int i = 0; i < cpu->num_mmio; i++) {
        if (cpu->mmio[i].active) count++;
    }
    return count;
}

void m65832_mmio_set_active(m65832_cpu_t *cpu, int index, bool active) {
    if (!cpu || index < 0 || index >= cpu->num_mmio) return;
    cpu->mmio[index].active = active;
}

void m65832_mmio_print(m65832_cpu_t *cpu) {
    if (!cpu) {
        printf("MMIO: (no CPU)\n");
        return;
    }
    
    printf("MMIO Regions (%d registered):\n", m65832_mmio_count(cpu));
    for (int i = 0; i < cpu->num_mmio; i++) {
        m65832_mmio_region_t *r = &cpu->mmio[i];
        if (r->active) {
            printf("  [%d] %08X - %08X (%u bytes) %s%s %s\n",
                   i, r->base, r->base + r->size - 1, r->size,
                   r->read ? "R" : "-",
                   r->write ? "W" : "-",
                   r->name ? r->name : "");
        }
    }
}

/* ============================================================================
 * Legacy API (Aliases)
 * ========================================================================= */

m65832_cpu_t *m65832_create(void) {
    return m65832_emu_init(0);
}

void m65832_destroy(m65832_cpu_t *cpu) {
    m65832_emu_close(cpu);
}

void m65832_reset(m65832_cpu_t *cpu) {
    m65832_emu_reset(cpu);
}

void m65832_set_memory(m65832_cpu_t *cpu, uint8_t *memory, size_t size) {
    if (cpu->memory && !cpu->mem_read) {
        free(cpu->memory);
    }
    cpu->memory = memory;
    cpu->memory_size = size;
    cpu->mem_read = NULL;
    cpu->mem_write = NULL;
}

void m65832_set_memory_callbacks(m65832_cpu_t *cpu,
                                  m65832_mem_read_fn read_fn,
                                  m65832_mem_write_fn write_fn,
                                  void *user) {
    cpu->mem_read = read_fn;
    cpu->mem_write = write_fn;
    cpu->mem_user = user;
}

int m65832_load_binary(m65832_cpu_t *cpu, const char *filename, uint32_t addr) {
    FILE *f = fopen(filename, "rb");
    if (!f) return -1;
    
    fseek(f, 0, SEEK_END);
    size_t size = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if ((size_t)addr + size > cpu->memory_size) {
        /* Expand memory if needed */
        size_t new_size = (size_t)addr + size;
        uint8_t *new_mem = (uint8_t *)realloc(cpu->memory, new_size);
        if (!new_mem) {
            fclose(f);
            return -1;
        }
        memset(new_mem + cpu->memory_size, 0, new_size - cpu->memory_size);
        cpu->memory = new_mem;
        cpu->memory_size = new_size;
    }
    
    size_t read = fread(cpu->memory + addr, 1, size, f);
    fclose(f);
    
    return (int)read;
}

int m65832_load_hex(m65832_cpu_t *cpu, const char *filename) {
    FILE *f = fopen(filename, "r");
    if (!f) return -1;
    
    char line[256];
    int total = 0;
    uint32_t base_addr = 0;
    
    while (fgets(line, sizeof(line), f)) {
        if (line[0] != ':') continue;
        
        int len, addr, type;
        if (sscanf(line + 1, "%02x%04x%02x", &len, &addr, &type) != 3) continue;
        
        if (type == 0) {  /* Data record */
            uint32_t full_addr = base_addr + addr;
            for (int i = 0; i < len; i++) {
                int byte;
                if (sscanf(line + 9 + i*2, "%02x", &byte) == 1) {
                    if (full_addr + i < cpu->memory_size) {
                        cpu->memory[full_addr + i] = (uint8_t)byte;
                        total++;
                    }
                }
            }
        } else if (type == 2) {  /* Extended segment address */
            int seg;
            if (sscanf(line + 9, "%04x", &seg) == 1) {
                base_addr = seg << 4;
            }
        } else if (type == 4) {  /* Extended linear address */
            int hi;
            if (sscanf(line + 9, "%04x", &hi) == 1) {
                base_addr = (uint32_t)hi << 16;
            }
        } else if (type == 1) {  /* EOF */
            break;
        }
    }
    
    fclose(f);
    return total;
}

int m65832_step(m65832_cpu_t *cpu) {
    if (!cpu->running || cpu->stopped) return 0;
    
    /* Check for interrupts (ABORT > NMI > IRQ priority) */
    if (cpu->abort_pending) {
        cpu->abort_pending = false;
        exception_enter(cpu, IS_EMU(cpu) ? VEC_ABORT_EMU : VEC_ABORT, cpu->pc);
        cpu->halted = false;
        cpu->trap = TRAP_ABORT;
        return 7;
    }
    
    if (cpu->nmi_pending) {
        cpu->nmi_pending = false;
        exception_enter(cpu, IS_EMU(cpu) ? VEC_NMI_EMU : VEC_NMI, cpu->pc);
        cpu->halted = false;
        cpu->trap = TRAP_NMI;
        return 7;
    }
    
    if (cpu->irq_pending && !FLAG_TST(cpu, P_I)) {
        cpu->irq_pending = false;  /* Clear IRQ pending */
        exception_enter(cpu, IS_EMU(cpu) ? VEC_IRQ_EMU : VEC_IRQ, cpu->pc);
        cpu->halted = false;
        return 7;
    }
    
    if (cpu->halted) return 1;  /* WAI - just burn a cycle */
    
    /* Check breakpoints */
    for (int i = 0; i < cpu->num_breakpoints; i++) {
        if (cpu->breakpoints[i] == cpu->pc) {
            cpu->trap = TRAP_BREAKPOINT;
            cpu->trap_addr = cpu->pc;
            if (cpu->break_fn && !cpu->break_fn(cpu, cpu->pc, cpu->break_user)) {
                cpu->running = false;
                return 0;
            }
        }
    }
    
    /* Trace if enabled */
    if (cpu->tracing && cpu->trace_fn) {
        uint8_t buf[8];
        uint32_t pc = cpu->pc;
        for (int i = 0; i < 8 && pc + i < cpu->memory_size; i++) {
            buf[i] = cpu->memory[pc + i];
        }
        cpu->trace_fn(cpu, pc, buf, 1, cpu->trace_user);  /* Simplified */
    }
    
    int cycles = execute_instruction(cpu);
    cpu->cycles += cycles;
    cpu->inst_count++;
    
    /* Timer tick */
    timer_tick(cpu, cycles);
    
    /* Timer IRQ feeds into IRQ line */
    if (cpu->timer_irq && !cpu->irq_pending) {
        cpu->irq_pending = true;
    }
    
    return cycles;
}

uint64_t m65832_run(m65832_cpu_t *cpu, uint64_t count) {
    uint64_t executed = 0;
    while (executed < count && cpu->running && !cpu->stopped) {
        m65832_step(cpu);
        executed++;
        if (cpu->trap != TRAP_NONE && cpu->trap != TRAP_BRK && cpu->trap != TRAP_COP) {
            break;
        }
    }
    return executed;
}

uint64_t m65832_run_cycles(m65832_cpu_t *cpu, uint64_t cycles) {
    uint64_t start = cpu->cycles;
    while ((cpu->cycles - start) < cycles && cpu->running && !cpu->stopped) {
        m65832_step(cpu);
        /* Only stop on truly fatal traps (page fault, illegal op, privilege violation).
         * BRK, COP, and SYSCALL (TRAP) are normal software interrupts that continue
         * execution via their respective handlers. */
        if (cpu->trap == TRAP_PAGE_FAULT || cpu->trap == TRAP_ILLEGAL_OP || 
            cpu->trap == TRAP_PRIVILEGE || cpu->trap == TRAP_WATCHPOINT) {
            break;
        }
    }
    return cpu->cycles - start;
}

void m65832_run_until_halt(m65832_cpu_t *cpu) {
    while (cpu->running && !cpu->stopped && !cpu->halted) {
        m65832_step(cpu);
        if (cpu->cycle_limit && cpu->cycles >= cpu->cycle_limit) break;
    }
}

void m65832_stop(m65832_cpu_t *cpu) {
    cpu->running = false;
}

void m65832_irq(m65832_cpu_t *cpu, bool active) {
    cpu->irq_pending = active;
    if (active && cpu->halted) cpu->halted = false;
}

void m65832_nmi(m65832_cpu_t *cpu) {
    cpu->nmi_pending = true;
    if (cpu->halted) cpu->halted = false;
}

void m65832_abort(m65832_cpu_t *cpu) {
    cpu->abort_pending = true;
}

/* Register getters/setters */
uint32_t m65832_get_a(m65832_cpu_t *cpu) { return cpu->a; }
uint32_t m65832_get_x(m65832_cpu_t *cpu) { return cpu->x; }
uint32_t m65832_get_y(m65832_cpu_t *cpu) { return cpu->y; }
uint32_t m65832_get_s(m65832_cpu_t *cpu) { return cpu->s; }
uint32_t m65832_get_pc(m65832_cpu_t *cpu) { return cpu->pc; }
uint32_t m65832_get_d(m65832_cpu_t *cpu) { return cpu->d; }
uint32_t m65832_get_b(m65832_cpu_t *cpu) { return cpu->b; }
uint32_t m65832_get_t(m65832_cpu_t *cpu) { return cpu->t; }
uint16_t m65832_get_p(m65832_cpu_t *cpu) { return cpu->p; }

void m65832_set_a(m65832_cpu_t *cpu, uint32_t val) { cpu->a = val; }
void m65832_set_x(m65832_cpu_t *cpu, uint32_t val) { cpu->x = val; }
void m65832_set_y(m65832_cpu_t *cpu, uint32_t val) { cpu->y = val; }
void m65832_set_s(m65832_cpu_t *cpu, uint32_t val) { cpu->s = val; }
void m65832_set_pc(m65832_cpu_t *cpu, uint32_t val) { cpu->pc = val; }
void m65832_set_d(m65832_cpu_t *cpu, uint32_t val) { cpu->d = val; }
void m65832_set_b(m65832_cpu_t *cpu, uint32_t val) { cpu->b = val; }
void m65832_set_t(m65832_cpu_t *cpu, uint32_t val) { cpu->t = val; }
void m65832_set_p(m65832_cpu_t *cpu, uint16_t val) { cpu->p = val; }

uint32_t m65832_get_reg(m65832_cpu_t *cpu, int n) {
    if (n >= 0 && n < M65832_REG_WINDOW_SIZE) return cpu->regs[n];
    return 0;
}

void m65832_set_reg(m65832_cpu_t *cpu, int n, uint32_t val) {
    if (n >= 0 && n < M65832_REG_WINDOW_SIZE) cpu->regs[n] = val;
}

/* Flag helpers */
bool m65832_flag_c(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_C); }
bool m65832_flag_z(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_Z); }
bool m65832_flag_i(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_I); }
bool m65832_flag_d(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_D); }
bool m65832_flag_v(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_V); }
bool m65832_flag_n(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_N); }
bool m65832_flag_e(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_E); }
bool m65832_flag_s(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_S); }
bool m65832_flag_r(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_R); }
bool m65832_flag_k(m65832_cpu_t *cpu) { return FLAG_TST(cpu, P_K); }
m65832_width_t m65832_width_a(m65832_cpu_t *cpu) { return WIDTH_M(cpu); }
m65832_width_t m65832_width_x(m65832_cpu_t *cpu) { return WIDTH_X(cpu); }

/* Debugging */
void m65832_set_trace(m65832_cpu_t *cpu, bool enable,
                       m65832_trace_fn fn, void *user) {
    cpu->tracing = enable;
    cpu->trace_fn = fn;
    cpu->trace_user = user;
}

int m65832_add_breakpoint(m65832_cpu_t *cpu, uint32_t addr) {
    if (cpu->num_breakpoints >= 64) return -1;
    cpu->breakpoints[cpu->num_breakpoints++] = addr;
    return cpu->num_breakpoints - 1;
}

bool m65832_remove_breakpoint(m65832_cpu_t *cpu, uint32_t addr) {
    for (int i = 0; i < cpu->num_breakpoints; i++) {
        if (cpu->breakpoints[i] == addr) {
            memmove(&cpu->breakpoints[i], &cpu->breakpoints[i+1],
                    (cpu->num_breakpoints - i - 1) * sizeof(uint32_t));
            cpu->num_breakpoints--;
            return true;
        }
    }
    return false;
}

void m65832_clear_breakpoints(m65832_cpu_t *cpu) {
    cpu->num_breakpoints = 0;
}

int m65832_add_watchpoint(m65832_cpu_t *cpu, uint32_t addr, uint32_t size,
                           bool on_read, bool on_write) {
    if (cpu->num_watchpoints >= 16) return -1;
    int i = cpu->num_watchpoints++;
    cpu->watchpoints[i].addr = addr;
    cpu->watchpoints[i].size = size;
    cpu->watchpoints[i].on_read = on_read;
    cpu->watchpoints[i].on_write = on_write;
    return i;
}

bool m65832_remove_watchpoint(m65832_cpu_t *cpu, uint32_t addr) {
    for (int i = 0; i < cpu->num_watchpoints; i++) {
        if (cpu->watchpoints[i].addr == addr) {
            memmove(&cpu->watchpoints[i], &cpu->watchpoints[i+1],
                    (cpu->num_watchpoints - i - 1) * sizeof(cpu->watchpoints[0]));
            cpu->num_watchpoints--;
            return true;
        }
    }
    return false;
}

void m65832_print_state(m65832_cpu_t *cpu) {
    const char *mode = IS_EMU(cpu) ? "EMU" : "NAT";
    /* M65832: Width is controlled by M1:M0 and X1:X0 regardless of E mode */
    int width_a = SIZE_M(cpu);
    int width_x = SIZE_X(cpu);
    
    printf("M65832 CPU State (%s mode, A:%d-bit, X/Y:%d-bit)\n",
           mode, width_a * 8, width_x * 8);
    printf("  PC: %08X  A: %08X  X: %08X  Y: %08X\n",
           cpu->pc, cpu->a, cpu->x, cpu->y);
    printf("  SP: %08X  D: %08X  B: %08X  T: %08X\n",
           cpu->s, cpu->d, cpu->b, cpu->t);
    printf("  P:  %04X [%c%c%c%c%c%c%c%c%c%c%c%c]\n",
           cpu->p,
           FLAG_TST(cpu, P_N) ? 'N' : '-',
           FLAG_TST(cpu, P_V) ? 'V' : '-',
           FLAG_TST(cpu, P_K) ? 'K' : '-',
           FLAG_TST(cpu, P_R) ? 'R' : '-',
           FLAG_TST(cpu, P_S) ? 'S' : '-',
           FLAG_TST(cpu, P_E) ? 'E' : '-',
           FLAG_TST(cpu, P_D) ? 'D' : '-',
           FLAG_TST(cpu, P_I) ? 'I' : '-',
           FLAG_TST(cpu, P_Z) ? 'Z' : '-',
           FLAG_TST(cpu, P_C) ? 'C' : '-',
           'm', 'x');
    printf("  Cycles: %llu  Instructions: %llu\n",
           (unsigned long long)cpu->cycles, (unsigned long long)cpu->inst_count);
    if (cpu->trap != TRAP_NONE) {
        printf("  Trap: %s at %08X\n", m65832_trap_name(cpu->trap), cpu->trap_addr);
    }
}

/* Include the disassembler implementation */
#define M65832DIS_IMPLEMENTATION
#include "../as/m65832dis.c"

int m65832_disassemble(m65832_cpu_t *cpu, uint32_t addr, char *buf, size_t bufsize) {
    /* Read instruction bytes from memory */
    uint8_t instbuf[8];
    for (int i = 0; i < 8; i++) {
        instbuf[i] = (addr + i < cpu->memory_size) ? cpu->memory[addr + i] : 0;
    }
    
    /* Set up context based on CPU state */
    M65832DisCtx ctx;
    m65832_dis_init(&ctx);
    ctx.emu_mode = IS_EMU(cpu) ? 1 : 0;
    ctx.m_flag = WIDTH_M(cpu);
    ctx.x_flag = WIDTH_X(cpu);
    
    return m65832_disasm(instbuf, 8, addr, buf, bufsize, &ctx);
}

m65832_trap_t m65832_get_trap(m65832_cpu_t *cpu) {
    return cpu->trap;
}

const char *m65832_trap_name(m65832_trap_t trap) {
    switch (trap) {
        case TRAP_NONE: return "NONE";
        case TRAP_BRK: return "BRK";
        case TRAP_COP: return "COP";
        case TRAP_IRQ: return "IRQ";
        case TRAP_NMI: return "NMI";
        case TRAP_ABORT: return "ABORT";
        case TRAP_PAGE_FAULT: return "PAGE_FAULT";
        case TRAP_SYSCALL: return "SYSCALL";
        case TRAP_ILLEGAL_OP: return "ILLEGAL_OP";
        case TRAP_PRIVILEGE: return "PRIVILEGE";
        case TRAP_BREAKPOINT: return "BREAKPOINT";
        case TRAP_WATCHPOINT: return "WATCHPOINT";
        default: return "UNKNOWN";
    }
}

/* Memory access utilities */
uint8_t m65832_peek(m65832_cpu_t *cpu, uint32_t addr) {
    if (cpu->memory && addr < cpu->memory_size) {
        return cpu->memory[addr];
    }
    return 0;
}

void m65832_poke(m65832_cpu_t *cpu, uint32_t addr, uint8_t val) {
    if (cpu->memory && addr < cpu->memory_size) {
        cpu->memory[addr] = val;
    }
}

uint16_t m65832_peek16(m65832_cpu_t *cpu, uint32_t addr) {
    return m65832_peek(cpu, addr) | ((uint16_t)m65832_peek(cpu, addr + 1) << 8);
}

uint32_t m65832_peek32(m65832_cpu_t *cpu, uint32_t addr) {
    return m65832_peek(cpu, addr) |
           ((uint32_t)m65832_peek(cpu, addr + 1) << 8) |
           ((uint32_t)m65832_peek(cpu, addr + 2) << 16) |
           ((uint32_t)m65832_peek(cpu, addr + 3) << 24);
}

void m65832_poke16(m65832_cpu_t *cpu, uint32_t addr, uint16_t val) {
    m65832_poke(cpu, addr, val & 0xFF);
    m65832_poke(cpu, addr + 1, (val >> 8) & 0xFF);
}

void m65832_poke32(m65832_cpu_t *cpu, uint32_t addr, uint32_t val) {
    m65832_poke(cpu, addr, val & 0xFF);
    m65832_poke(cpu, addr + 1, (val >> 8) & 0xFF);
    m65832_poke(cpu, addr + 2, (val >> 16) & 0xFF);
    m65832_poke(cpu, addr + 3, (val >> 24) & 0xFF);
}
