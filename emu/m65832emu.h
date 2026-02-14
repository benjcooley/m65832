/*
 * m65832emu.h - M65832 CPU Emulator Library
 *
 * High-performance emulator for the M65832 processor architecture.
 * Includes support for the 6502 coprocessor subsystem.
 *
 * This file is the public API header for both library and embedded use.
 */

#ifndef M65832EMU_H
#define M65832EMU_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version and Configuration
 * ========================================================================= */

#define M65832EMU_VERSION_MAJOR 1
#define M65832EMU_VERSION_MINOR 0
#define M65832EMU_VERSION_PATCH 0

/* Memory size constants */
#define M65832_MAX_MEMORY       (1ULL << 32)    /* 4 GB virtual address space */
#define M65832_PAGE_SIZE        4096            /* 4 KB pages */
#define M65832_TLB_ENTRIES      16              /* TLB entries */
#define M65832_REG_WINDOW_SIZE  64              /* R0-R63 */

/* System register addresses (MMIO at $00FFF0xx - 24-bit addressable) */
#define SYSREG_BASE       0xFFFFF000  /* DE25: system regs at 0xFFFFF000 */
#define SYSREG_MMUCR      0xFFFFF000  /* MMU Control Register */
#define SYSREG_TLBINVAL   0x00FFF004  /* TLB Invalidate (by VA) */
#define SYSREG_ASID       0x00FFF008  /* Address Space ID */
#define SYSREG_ASIDINVAL  0x00FFF00C  /* TLB Invalidate (by ASID) */
#define SYSREG_FAULTVA    0x00FFF010  /* Faulting Virtual Address */
#define SYSREG_PTBR_LO    0x00FFF014  /* Page Table Base Register (low 32) */
#define SYSREG_PTBR_HI    0x00FFF018  /* Page Table Base Register (high 32) */
#define SYSREG_TLBFLUSH   0x00FFF01C  /* Full TLB Flush */
#define SYSREG_TIMER_CTRL 0x00FFF040  /* Timer Control */
#define SYSREG_TIMER_CMP  0x00FFF044  /* Timer Compare Value */
#define SYSREG_TIMER_CNT  0x00FFF048  /* Timer Counter */

/* MMUCR bits */
#define MMUCR_PG          0x01        /* Paging enable */
#define MMUCR_WP          0x02        /* Write-protect supervisor pages */
#define MMUCR_FTYPE_MASK  0x1C        /* Fault type (bits 4:2) */
#define MMUCR_FTYPE_SHIFT 2

/* Fault types (in MMUCR bits 4:2) */
#define FAULT_NOT_PRESENT   0   /* Page not present */
#define FAULT_WRITE_PROTECT 1   /* Write to read-only */
#define FAULT_USER_SUPER    2   /* User access to supervisor page */
#define FAULT_NO_EXECUTE    3   /* Execute on non-executable */
#define FAULT_L1_NOT_PRESENT 4  /* L1 page table not present */
#define FAULT_L2_NOT_PRESENT 5  /* L2 page table not present */

/* Timer control bits */
#define TIMER_ENABLE      0x01
#define TIMER_AUTORESET   0x02
#define TIMER_IRQ_ENABLE  0x04
#define TIMER_IRQ_CLEAR   0x08
#define TIMER_IRQ_PENDING 0x80

/* Page table entry bits (64-bit PTE) */
#define PTE_PRESENT       (1ULL << 0)
#define PTE_WRITABLE      (1ULL << 1)
#define PTE_USER          (1ULL << 2)
#define PTE_PWT           (1ULL << 3)
#define PTE_PCD           (1ULL << 4)
#define PTE_ACCESSED      (1ULL << 9)
#define PTE_DIRTY         (1ULL << 10)
#define PTE_GLOBAL        (1ULL << 11)
#define PTE_NO_EXEC       (1ULL << 63)   /* Page is NOT executable */
#define PTE_PPN_SHIFT     12
#define PTE_PPN_MASK      0xFFFFFFFFFFFFF000ULL

/* 6502 coprocessor constants */
#define M6502_ADDR_SPACE        65536           /* 64 KB */
#define M6502_SHADOW_BANKS      4               /* Shadow I/O banks */
#define M6502_SHADOW_REGS       64              /* Registers per bank */
#define M6502_WRITE_FIFO_SIZE   256             /* Write FIFO entries */

/* ============================================================================
 * Type Definitions
 * ========================================================================= */

/* Forward declarations */
typedef struct m65832_cpu m65832_cpu_t;
typedef struct m6502_cpu m6502_cpu_t;

/* Register width modes (from M1:M0 and X1:X0 flags) */
typedef enum {
    WIDTH_8  = 0,   /* 8-bit */
    WIDTH_16 = 1,   /* 16-bit */
    WIDTH_32 = 2,   /* 32-bit */
} m65832_width_t;

/* Status Register (P) flags */
typedef enum {
    /* Standard 6502 flags (byte 0) */
    P_C = 0x0001,   /* Carry */
    P_Z = 0x0002,   /* Zero */
    P_I = 0x0004,   /* IRQ Disable */
    P_D = 0x0008,   /* Decimal (BCD) mode */
    /* Bits 4-5 unused in byte 0 */
    
    /* Extended flags (byte 1) */
    P_X0 = 0x0010,  /* Index width bit 0 */
    P_X1 = 0x0020,  /* Index width bit 1 */
    P_M0 = 0x0040,  /* Accumulator width bit 0 */
    P_M1 = 0x0080,  /* Accumulator width bit 1 */
    P_V  = 0x0100,  /* Overflow */
    P_N  = 0x0200,  /* Negative */
    P_E  = 0x0400,  /* Emulation mode */
    P_S  = 0x0800,  /* Supervisor mode */
    P_R  = 0x1000,  /* Register window enabled */
    P_K  = 0x2000,  /* Compatibility mode (illegal ops = NOP) */
} m65832_flags_t;

/* Memory access type (for callbacks) */
typedef enum {
    MEM_READ,
    MEM_WRITE,
    MEM_FETCH,      /* Instruction fetch */
} m65832_mem_access_t;

/* Maximum number of MMIO regions */
#define M65832_MAX_MMIO_REGIONS 32

/* Exception/interrupt vectors */
typedef enum {
    VEC_RESET       = 0xFFFC,   /* Reset vector (emulation mode) */
    VEC_IRQ_EMU     = 0xFFFE,   /* IRQ/BRK (emulation mode) */
    VEC_NMI_EMU     = 0xFFFA,   /* NMI (emulation mode) */
    VEC_ABORT_EMU   = 0xFFF8,   /* ABORT (emulation mode) */
    
    /* Native mode vectors (32-bit addresses) */
    VEC_COP         = 0x0000FFE4,
    VEC_BRK         = 0x0000FFE6,
    VEC_ABORT       = 0x0000FFE8,
    VEC_NMI         = 0x0000FFEA,
    VEC_IRQ         = 0x0000FFEE,
    VEC_PAGE_FAULT  = 0x0000FFD0,
    VEC_SYSCALL     = 0x0000FFD4,
    VEC_ILLEGAL_OP  = 0x0000FFF8,
} m65832_vector_t;

/* Trap/exception codes */
typedef enum {
    TRAP_NONE = 0,
    TRAP_BRK,
    TRAP_COP,
    TRAP_IRQ,
    TRAP_NMI,
    TRAP_ABORT,
    TRAP_PAGE_FAULT,
    TRAP_SYSCALL,
    TRAP_ILLEGAL_OP,
    TRAP_PRIVILEGE,
    TRAP_BREAKPOINT,    /* Debugger breakpoint */
    TRAP_WATCHPOINT,    /* Debugger watchpoint */
    TRAP_ALIGNMENT,     /* RSET alignment error (already handled) */
} m65832_trap_t;

/* ============================================================================
 * Memory Callbacks
 * ========================================================================= */

/*
 * Memory read callback.
 * Called for all memory reads. Return the value at the address.
 * 
 * @param cpu       CPU context
 * @param addr      Virtual address
 * @param width     Access width (1, 2, or 4 bytes)
 * @param access    Access type (read, write, fetch)
 * @param user      User data pointer
 * @return          Value read from memory
 */
typedef uint32_t (*m65832_mem_read_fn)(m65832_cpu_t *cpu, uint32_t addr, 
                                        int width, m65832_mem_access_t access,
                                        void *user);

/*
 * Memory write callback.
 * Called for all memory writes.
 *
 * @param cpu       CPU context
 * @param addr      Virtual address
 * @param value     Value to write
 * @param width     Access width (1, 2, or 4 bytes)
 * @param user      User data pointer
 */
typedef void (*m65832_mem_write_fn)(m65832_cpu_t *cpu, uint32_t addr,
                                     uint32_t value, int width, void *user);

/* ============================================================================
 * MMIO Handler Types
 * ========================================================================= */

/*
 * MMIO read handler.
 * Called when the CPU reads from a registered MMIO region.
 *
 * @param cpu       CPU context
 * @param addr      Address being read (absolute)
 * @param offset    Offset within the MMIO region
 * @param width     Access width (1, 2, or 4 bytes)
 * @param user      User data pointer
 * @return          Value to return to CPU
 */
typedef uint32_t (*m65832_mmio_read_fn)(m65832_cpu_t *cpu, uint32_t addr,
                                         uint32_t offset, int width, void *user);

/*
 * MMIO write handler.
 * Called when the CPU writes to a registered MMIO region.
 *
 * @param cpu       CPU context
 * @param addr      Address being written (absolute)
 * @param offset    Offset within the MMIO region
 * @param value     Value being written
 * @param width     Access width (1, 2, or 4 bytes)
 * @param user      User data pointer
 */
typedef void (*m65832_mmio_write_fn)(m65832_cpu_t *cpu, uint32_t addr,
                                      uint32_t offset, uint32_t value,
                                      int width, void *user);

/* MMIO region descriptor */
typedef struct {
    uint32_t base;              /* Base address */
    uint32_t size;              /* Region size in bytes */
    m65832_mmio_read_fn read;   /* Read handler (NULL for write-only) */
    m65832_mmio_write_fn write; /* Write handler (NULL for read-only) */
    void *user;                 /* User data for callbacks */
    const char *name;           /* Optional region name (for debugging) */
    bool active;                /* Region is active */
} m65832_mmio_region_t;

/* ============================================================================
 * Debugging Callbacks
 * ========================================================================= */

/*
 * Instruction trace callback.
 * Called before each instruction executes (if tracing enabled).
 *
 * @param cpu       CPU context
 * @param pc        Program counter
 * @param opcode    Opcode byte(s) - up to 6 bytes
 * @param len       Instruction length in bytes
 * @param user      User data pointer
 */
typedef void (*m65832_trace_fn)(m65832_cpu_t *cpu, uint32_t pc,
                                 const uint8_t *opcode, int len, void *user);

/*
 * Breakpoint callback.
 * Called when a breakpoint is hit.
 *
 * @param cpu       CPU context
 * @param addr      Address that triggered the breakpoint
 * @param user      User data pointer
 * @return          true to continue, false to stop execution
 */
typedef bool (*m65832_breakpoint_fn)(m65832_cpu_t *cpu, uint32_t addr, void *user);

/* ============================================================================
 * TLB Entry
 * ========================================================================= */

typedef struct {
    uint32_t vpn;           /* Virtual page number */
    uint64_t ppn;           /* Physical page number (53-bit) */
    uint8_t  asid;          /* Address space ID */
    uint8_t  flags;         /* Permission flags */
    bool     valid;         /* Entry valid */
} m65832_tlb_entry_t;

/* TLB flags */
#define TLB_PRESENT     0x01
#define TLB_WRITABLE    0x02
#define TLB_USER        0x04
#define TLB_EXECUTABLE  0x08
#define TLB_DIRTY       0x10
#define TLB_ACCESSED    0x20

/* ============================================================================
 * 6502 Coprocessor State
 * ========================================================================= */

/* 6502 compatibility flags */
#define COMPAT_DECIMAL_EN    0x01   /* BCD mode enabled */
#define COMPAT_CMOS65C02_EN  0x02   /* 65C02 extensions */
#define COMPAT_NMOS_ILLEGAL  0x04   /* NMOS illegal opcodes */

/* Shadow I/O write FIFO entry */
typedef struct {
    uint32_t frame;         /* Frame number */
    uint32_t cycle;         /* Cycle within frame */
    uint8_t  bank;          /* I/O bank (0-3) */
    uint8_t  reg;           /* Register (0-63) */
    uint8_t  value;         /* Written value */
} m6502_fifo_entry_t;

/* 6502 coprocessor state */
struct m6502_cpu {
    /* Registers */
    uint8_t  a;             /* Accumulator */
    uint8_t  x;             /* X index */
    uint8_t  y;             /* Y index */
    uint8_t  s;             /* Stack pointer */
    uint8_t  p;             /* Status register (NV-BDIZC) */
    uint16_t pc;            /* Program counter (relative to VBR) */
    
    /* Timing */
    uint32_t target_freq;   /* Target CPU frequency in Hz */
    uint32_t master_freq;   /* Master clock frequency */
    uint64_t cycles;        /* Total cycles executed */
    uint32_t frame_cycles;  /* Cycles in current frame */
    uint32_t scanline;      /* Current scanline */
    uint32_t cycles_per_line; /* Cycles per scanline */
    uint32_t lines_per_frame; /* Scanlines per frame */
    
    /* Configuration */
    uint8_t  compat;        /* Compatibility flags */
    uint32_t vbr;           /* Virtual Base Register */
    
    /* Shadow I/O */
    uint32_t bank_base[M6502_SHADOW_BANKS];     /* Bank base addresses */
    uint8_t  shadow_regs[M6502_SHADOW_BANKS][M6502_SHADOW_REGS];
    
    /* Write FIFO */
    m6502_fifo_entry_t fifo[M6502_WRITE_FIFO_SIZE];
    int fifo_head;
    int fifo_tail;
    int fifo_count;
    
    /* Memory (64KB window) */
    uint8_t *memory;        /* Points into main memory at VBR offset */
    
    /* State */
    bool     running;       /* CPU running */
    bool     irq_pending;   /* IRQ line asserted */
    bool     nmi_pending;   /* NMI edge detected */
    bool     nmi_prev;      /* Previous NMI state (for edge detection) */
    
    /* Cycle counting */
    int      pending_cycles;/* Cycles remaining for current instruction */
    
    /* Parent CPU reference */
    m65832_cpu_t *main_cpu;
};

/* ============================================================================
 * M65832 CPU State
 * ========================================================================= */

struct m65832_cpu {
    /* Main registers */
    uint32_t a;             /* Accumulator (8/16/32-bit) */
    uint32_t x;             /* X index (8/16/32-bit) */
    uint32_t y;             /* Y index (8/16/32-bit) */
    uint32_t s;             /* Stack pointer (16/32-bit) */
    uint32_t pc;            /* Program counter (16/32-bit) */
    uint32_t inst_pc;       /* PC at start of current instruction (for faults) */
    
    /* Base registers */
    uint32_t d;             /* Direct page base */
    uint32_t b;             /* Absolute base */
    uint32_t vbr;           /* Virtual base register (supervisor) */
    uint32_t t;             /* Temp register (high word of MUL, remainder of DIV) */
    
    /* Status register */
    uint16_t p;             /* Processor status (14-bit) */
    
    /* Register window (R0-R63) */
    uint32_t regs[M65832_REG_WINDOW_SIZE];
    
    /* FPU registers (optional) - 16 x 64-bit */
    double   f[16];         /* F0-F15 */
    
    /* MMU */
    uint64_t ptbr;          /* Page table base register (65-bit, but we use 64) */
    uint8_t  asid;          /* Address space ID */
    uint32_t mmucr;         /* MMU control register */
    uint32_t faultva;       /* Faulting virtual address */
    m65832_tlb_entry_t tlb[M65832_TLB_ENTRIES];
    int      tlb_next;      /* Next TLB entry to replace (round-robin) */
    
    /* Timer */
    uint8_t  timer_ctrl;    /* Timer control register */
    uint32_t timer_cmp;     /* Timer compare value */
    uint32_t timer_cnt;     /* Timer counter */
    uint32_t timer_latch;   /* Timer latched value at IRQ */
    bool     timer_irq;     /* Timer IRQ pending */
    bool     timer_latched; /* True if timer_latch is valid */
    
    /* LL/SC atomics */
    uint32_t ll_addr;       /* Load-linked address */
    bool     ll_valid;      /* Link reservation valid */
    
    /* Cycle counting */
    uint64_t cycles;        /* Total cycles executed */
    uint64_t cycle_limit;   /* Stop after this many cycles (0 = unlimited) */

    /* Program exit status (written by _exit) */
    uint32_t exit_code;
    
    /* Interrupts */
    bool     irq_pending;
    bool     nmi_pending;
    bool     abort_pending;
    
    /* Trap/exception state */
    m65832_trap_t trap;
    uint32_t      trap_addr;
    
    /* Memory interface */
    uint8_t *memory;        /* Flat memory array (simple mode) */
    size_t   memory_size;   /* Size of flat memory */
    m65832_mem_read_fn  mem_read;   /* Custom read callback */
    m65832_mem_write_fn mem_write;  /* Custom write callback */
    void    *mem_user;      /* User data for memory callbacks */
    
    /* MMIO regions */
    m65832_mmio_region_t mmio[M65832_MAX_MMIO_REGIONS];
    int      num_mmio;      /* Number of registered MMIO regions */
    
    /* Debugging */
    bool     tracing;
    m65832_trace_fn      trace_fn;
    void                *trace_user;
    m65832_breakpoint_fn break_fn;
    void                *break_user;
    
    /* Breakpoints (simple linear list for now) */
    uint32_t breakpoints[64];
    int      num_breakpoints;
    
    /* Watchpoints */
    struct {
        uint32_t addr;
        uint32_t size;
        bool     on_read;
        bool     on_write;
    } watchpoints[16];
    int      num_watchpoints;

    /* 6502 coprocessor */
    m6502_cpu_t *coproc;    /* NULL if not configured */
    
    /* Execution state */
    bool     running;
    bool     halted;        /* WAI instruction */
    bool     stopped;       /* STP instruction */
    volatile int *dbg_irq;     /* BRK sets *dbg_irq=1 to interrupt main loop */
    volatile int *dbg_hit_bp;  /* BRK sets *dbg_hit_bp=1 to signal BP hit  */
    volatile int *dbg_hit_wp;  /* Watchpoint sets this to signal WP hit    */
    volatile int *dbg_kernel_ready; /* WDM #$01 sets this to re-insert BPs */
    
    /* Statistics */
    uint64_t inst_count;    /* Instructions executed */
};

/* ============================================================================
 * Emulator Lifecycle Functions (Primary API)
 * ========================================================================= */

/*
 * Initialize a new M65832 emulator instance.
 * The CPU starts in emulation mode (E=1) after reset.
 *
 * @param memory_size   Size of memory to allocate (0 for default 64KB)
 * @return              New emulator instance, or NULL on allocation failure
 */
m65832_cpu_t *m65832_emu_init(size_t memory_size);

/*
 * Execute a single instruction.
 *
 * @param cpu       Emulator instance
 * @return          Number of cycles taken, or negative on trap/error
 */
int m65832_emu_step(m65832_cpu_t *cpu);

/*
 * Execute for a specified number of cycles.
 *
 * @param cpu       Emulator instance
 * @param cycles    Maximum cycles to execute
 * @return          Actual cycles executed
 */
uint64_t m65832_emu_run(m65832_cpu_t *cpu, uint64_t cycles);

/*
 * Close and free all emulator resources.
 *
 * @param cpu   Emulator instance to close
 */
void m65832_emu_close(m65832_cpu_t *cpu);

/*
 * Reset the CPU to initial state.
 * Sets E=1, I=1, D=0, and fetches the reset vector.
 *
 * @param cpu   Emulator instance
 */
void m65832_emu_reset(m65832_cpu_t *cpu);

/*
 * Check if the emulator is running.
 *
 * @param cpu   Emulator instance
 * @return      true if running, false if halted/stopped
 */
bool m65832_emu_is_running(m65832_cpu_t *cpu);

/*
 * Switch CPU to native 32-bit mode.
 * The RTL resets to emulation mode (6502-compatible).
 * Call this after reset for modern M65832 programs.
 *
 * @param cpu   Emulator instance
 */
void m65832_emu_enter_native32(m65832_cpu_t *cpu);

/* ============================================================================
 * Memory Management
 * ========================================================================= */

/*
 * Set or resize emulator memory.
 *
 * @param cpu       Emulator instance
 * @param size      New memory size in bytes
 * @return          0 on success, -1 on error
 */
int m65832_emu_set_memory_size(m65832_cpu_t *cpu, size_t size);

/*
 * Get current memory size.
 *
 * @param cpu       Emulator instance
 * @return          Memory size in bytes
 */
size_t m65832_emu_get_memory_size(m65832_cpu_t *cpu);

/*
 * Read a byte from emulator memory.
 *
 * @param cpu       Emulator instance
 * @param addr      Address to read
 * @return          Byte value at address
 */
uint8_t m65832_emu_read8(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Write a byte to emulator memory.
 *
 * @param cpu       Emulator instance
 * @param addr      Address to write
 * @param value     Value to write
 */
void m65832_emu_write8(m65832_cpu_t *cpu, uint32_t addr, uint8_t value);

/*
 * Read a 16-bit value from emulator memory (little-endian).
 */
uint16_t m65832_emu_read16(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Write a 16-bit value to emulator memory (little-endian).
 */
void m65832_emu_write16(m65832_cpu_t *cpu, uint32_t addr, uint16_t value);

/*
 * Read a 32-bit value from emulator memory (little-endian).
 */
uint32_t m65832_emu_read32(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Write a 32-bit value to emulator memory (little-endian).
 */
void m65832_emu_write32(m65832_cpu_t *cpu, uint32_t addr, uint32_t value);

/*
 * Translate virtual address to physical using current MMU state.
 * Returns (uint64_t)-1 on translation failure.
 * Does not modify CPU fault state.
 */
uint64_t m65832_virt_to_phys(m65832_cpu_t *cpu, uint32_t va);

/*
 * Copy data into emulator memory.
 *
 * @param cpu       Emulator instance
 * @param addr      Destination address in emulator memory
 * @param data      Source data
 * @param size      Number of bytes to copy
 * @return          Number of bytes copied
 */
size_t m65832_emu_write_block(m65832_cpu_t *cpu, uint32_t addr, 
                               const void *data, size_t size);

/*
 * Copy data from emulator memory.
 *
 * @param cpu       Emulator instance
 * @param addr      Source address in emulator memory
 * @param data      Destination buffer
 * @param size      Number of bytes to copy
 * @return          Number of bytes copied
 */
size_t m65832_emu_read_block(m65832_cpu_t *cpu, uint32_t addr,
                              void *data, size_t size);

/*
 * Get direct pointer to emulator memory (for fast access).
 * WARNING: Pointer may be invalidated by memory resize operations.
 *
 * @param cpu       Emulator instance
 * @return          Pointer to memory array, or NULL
 */
uint8_t *m65832_emu_get_memory_ptr(m65832_cpu_t *cpu);

/* ============================================================================
 * MMIO (Memory-Mapped I/O) Functions
 * ========================================================================= */

/*
 * Register an MMIO region.
 * When the CPU accesses addresses in this region, the handlers are called
 * instead of accessing flat memory.
 *
 * @param cpu       Emulator instance
 * @param base      Base address of the MMIO region
 * @param size      Size of the region in bytes
 * @param read_fn   Read handler (NULL for write-only)
 * @param write_fn  Write handler (NULL for read-only)
 * @param user      User data passed to handlers
 * @param name      Optional name for debugging (can be NULL)
 * @return          Region index (>=0) on success, -1 on error
 */
int m65832_mmio_register(m65832_cpu_t *cpu, uint32_t base, uint32_t size,
                          m65832_mmio_read_fn read_fn,
                          m65832_mmio_write_fn write_fn,
                          void *user, const char *name);

/*
 * Unregister an MMIO region by index.
 *
 * @param cpu       Emulator instance
 * @param index     Region index returned by m65832_mmio_register
 * @return          0 on success, -1 on error
 */
int m65832_mmio_unregister(m65832_cpu_t *cpu, int index);

/*
 * Unregister an MMIO region by base address.
 *
 * @param cpu       Emulator instance
 * @param base      Base address of the region
 * @return          0 on success, -1 if not found
 */
int m65832_mmio_unregister_addr(m65832_cpu_t *cpu, uint32_t base);

/*
 * Unregister all MMIO regions.
 *
 * @param cpu       Emulator instance
 */
void m65832_mmio_clear(m65832_cpu_t *cpu);

/*
 * Get MMIO region info.
 *
 * @param cpu       Emulator instance
 * @param index     Region index
 * @return          Pointer to region info, or NULL if invalid
 */
const m65832_mmio_region_t *m65832_mmio_get(m65832_cpu_t *cpu, int index);

/*
 * Find MMIO region containing an address.
 *
 * @param cpu       Emulator instance
 * @param addr      Address to check
 * @return          Region index if found, -1 if not in any MMIO region
 */
int m65832_mmio_find(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Get number of registered MMIO regions.
 *
 * @param cpu       Emulator instance
 * @return          Number of active MMIO regions
 */
int m65832_mmio_count(m65832_cpu_t *cpu);

/*
 * Enable or disable an MMIO region.
 *
 * @param cpu       Emulator instance
 * @param index     Region index
 * @param active    true to enable, false to disable
 */
void m65832_mmio_set_active(m65832_cpu_t *cpu, int index, bool active);

/*
 * Print all registered MMIO regions (for debugging).
 *
 * @param cpu       Emulator instance
 */
void m65832_mmio_print(m65832_cpu_t *cpu);

/* ============================================================================
 * Legacy Lifecycle Functions (Aliases for compatibility)
 * ========================================================================= */

/*
 * Create a new M65832 CPU instance (alias for m65832_emu_init).
 */
m65832_cpu_t *m65832_create(void);

/*
 * Destroy a CPU instance (alias for m65832_emu_close).
 */
void m65832_destroy(m65832_cpu_t *cpu);

/*
 * Reset the CPU (alias for m65832_emu_reset).
 */
void m65832_reset(m65832_cpu_t *cpu);

/* ============================================================================
 * Memory Configuration
 * ========================================================================= */

/*
 * Configure simple flat memory.
 * The emulator will use this memory directly for all accesses.
 *
 * @param cpu       CPU instance
 * @param memory    Memory buffer (must remain valid)
 * @param size      Size of memory buffer
 */
void m65832_set_memory(m65832_cpu_t *cpu, uint8_t *memory, size_t size);

/*
 * Configure memory callbacks for custom memory mapping.
 * When set, these override the flat memory interface.
 *
 * @param cpu       CPU instance
 * @param read_fn   Read callback
 * @param write_fn  Write callback
 * @param user      User data passed to callbacks
 */
void m65832_set_memory_callbacks(m65832_cpu_t *cpu,
                                  m65832_mem_read_fn read_fn,
                                  m65832_mem_write_fn write_fn,
                                  void *user);

/*
 * Load a binary file into memory.
 *
 * @param cpu       CPU instance
 * @param filename  File to load
 * @param addr      Address to load at
 * @return          Number of bytes loaded, or -1 on error
 */
int m65832_load_binary(m65832_cpu_t *cpu, const char *filename, uint32_t addr);

/*
 * Load an Intel HEX file into memory.
 *
 * @param cpu       CPU instance
 * @param filename  File to load
 * @return          Number of bytes loaded, or -1 on error
 */
int m65832_load_hex(m65832_cpu_t *cpu, const char *filename);

/* ============================================================================
 * Execution Functions
 * ========================================================================= */

/*
 * Execute a single instruction.
 *
 * @param cpu       CPU instance
 * @return          Number of cycles taken, or negative on trap/exception
 */
int m65832_step(m65832_cpu_t *cpu);

/*
 * Execute multiple instructions.
 *
 * @param cpu       CPU instance
 * @param count     Maximum instructions to execute
 * @return          Number of instructions executed
 */
uint64_t m65832_run(m65832_cpu_t *cpu, uint64_t count);

/*
 * Execute for a number of cycles.
 *
 * @param cpu       CPU instance
 * @param cycles    Maximum cycles to execute
 * @return          Actual cycles executed
 */
uint64_t m65832_run_cycles(m65832_cpu_t *cpu, uint64_t cycles);

/*
 * Run until the CPU halts, traps, or cycle limit reached.
 *
 * @param cpu       CPU instance
 */
void m65832_run_until_halt(m65832_cpu_t *cpu);

/*
 * Stop execution (can be called from callbacks).
 *
 * @param cpu       CPU instance
 */
void m65832_stop(m65832_cpu_t *cpu);

/* ============================================================================
 * Interrupt Interface
 * ========================================================================= */

/*
 * Assert or deassert the IRQ line.
 *
 * @param cpu       CPU instance
 * @param active    true to assert, false to deassert
 */
void m65832_irq(m65832_cpu_t *cpu, bool active);

/*
 * Trigger an NMI (edge-triggered).
 *
 * @param cpu       CPU instance
 */
void m65832_nmi(m65832_cpu_t *cpu);

/*
 * Trigger an ABORT.
 *
 * @param cpu       CPU instance
 */
void m65832_abort(m65832_cpu_t *cpu);

/* ============================================================================
 * Register Access
 * ========================================================================= */

/* Get/set main registers */
uint32_t m65832_get_a(m65832_cpu_t *cpu);
uint32_t m65832_get_x(m65832_cpu_t *cpu);
uint32_t m65832_get_y(m65832_cpu_t *cpu);
uint32_t m65832_get_s(m65832_cpu_t *cpu);
uint32_t m65832_get_pc(m65832_cpu_t *cpu);
uint32_t m65832_get_d(m65832_cpu_t *cpu);
uint32_t m65832_get_b(m65832_cpu_t *cpu);
uint32_t m65832_get_t(m65832_cpu_t *cpu);
uint16_t m65832_get_p(m65832_cpu_t *cpu);

void m65832_set_a(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_x(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_y(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_s(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_pc(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_d(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_b(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_t(m65832_cpu_t *cpu, uint32_t val);
void m65832_set_p(m65832_cpu_t *cpu, uint16_t val);

/* Register window access */
uint32_t m65832_get_reg(m65832_cpu_t *cpu, int n);
void     m65832_set_reg(m65832_cpu_t *cpu, int n, uint32_t val);

/* Helper functions for status flags */
bool m65832_flag_c(m65832_cpu_t *cpu);
bool m65832_flag_z(m65832_cpu_t *cpu);
bool m65832_flag_i(m65832_cpu_t *cpu);
bool m65832_flag_d(m65832_cpu_t *cpu);
bool m65832_flag_v(m65832_cpu_t *cpu);
bool m65832_flag_n(m65832_cpu_t *cpu);
bool m65832_flag_e(m65832_cpu_t *cpu);
bool m65832_flag_s(m65832_cpu_t *cpu);
bool m65832_flag_r(m65832_cpu_t *cpu);
bool m65832_flag_k(m65832_cpu_t *cpu);
m65832_width_t m65832_width_a(m65832_cpu_t *cpu);
m65832_width_t m65832_width_x(m65832_cpu_t *cpu);

/* ============================================================================
 * Debugging Functions
 * ========================================================================= */

/*
 * Enable/disable instruction tracing.
 *
 * @param cpu       CPU instance
 * @param enable    true to enable tracing
 * @param fn        Trace callback (optional, uses default if NULL)
 * @param user      User data for callback
 */
void m65832_set_trace(m65832_cpu_t *cpu, bool enable,
                       m65832_trace_fn fn, void *user);

/*
 * Add an execution breakpoint.
 *
 * @param cpu       CPU instance
 * @param addr      Address to break at
 * @return          Breakpoint index, or -1 if full
 */
int m65832_add_breakpoint(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Remove a breakpoint.
 *
 * @param cpu       CPU instance
 * @param addr      Address to remove
 * @return          true if removed, false if not found
 */
bool m65832_remove_breakpoint(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Clear all breakpoints.
 *
 * @param cpu       CPU instance
 */
void m65832_clear_breakpoints(m65832_cpu_t *cpu);

/*
 * Add a memory watchpoint.
 *
 * @param cpu       CPU instance
 * @param addr      Start address
 * @param size      Size of region
 * @param on_read   Break on read
 * @param on_write  Break on write
 * @return          Watchpoint index, or -1 if full
 */
int m65832_add_watchpoint(m65832_cpu_t *cpu, uint32_t addr, uint32_t size,
                           bool on_read, bool on_write);

/*
 * Remove a watchpoint.
 *
 * @param cpu       CPU instance
 * @param addr      Address to remove
 * @return          true if removed, false if not found
 */
bool m65832_remove_watchpoint(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Print current CPU state to stdout.
 *
 * @param cpu       CPU instance
 */
void m65832_print_state(m65832_cpu_t *cpu);

/*
 * Disassemble an instruction at an address.
 *
 * @param cpu       CPU instance
 * @param addr      Address to disassemble
 * @param buf       Output buffer
 * @param bufsize   Buffer size
 * @return          Instruction length in bytes
 */
int m65832_disassemble(m65832_cpu_t *cpu, uint32_t addr, char *buf, size_t bufsize);

/*
 * Get the last trap/exception that occurred.
 *
 * @param cpu       CPU instance
 * @return          Trap code
 */
m65832_trap_t m65832_get_trap(m65832_cpu_t *cpu);

/*
 * Get trap name as string.
 *
 * @param trap      Trap code
 * @return          Name string
 */
const char *m65832_trap_name(m65832_trap_t trap);

/* ============================================================================
 * 6502 Coprocessor Functions
 * ========================================================================= */

/*
 * Configure the 6502 coprocessor.
 *
 * @param cpu           Main CPU instance
 * @param target_freq   Target 6502 frequency in Hz (e.g., 1022727 for C64)
 * @param master_freq   Master clock frequency
 * @param compat        Compatibility flags
 * @return              0 on success, -1 on error
 */
int m65832_coproc_init(m65832_cpu_t *cpu, uint32_t target_freq,
                        uint32_t master_freq, uint8_t compat);

/*
 * Destroy the 6502 coprocessor.
 *
 * @param cpu       Main CPU instance
 */
void m65832_coproc_destroy(m65832_cpu_t *cpu);

/*
 * Reset the 6502 coprocessor.
 *
 * @param cpu       Main CPU instance
 */
void m65832_coproc_reset(m65832_cpu_t *cpu);

/*
 * Set the Virtual Base Register for 6502 address translation.
 *
 * @param cpu       Main CPU instance
 * @param vbr       VBR value (6502 addresses map to VBR + addr)
 */
void m65832_coproc_set_vbr(m65832_cpu_t *cpu, uint32_t vbr);

/*
 * Configure shadow I/O bank.
 *
 * @param cpu       Main CPU instance
 * @param bank      Bank number (0-3)
 * @param base      Base address in 6502 space
 */
void m65832_coproc_set_shadow_bank(m65832_cpu_t *cpu, int bank, uint32_t base);

/*
 * Configure video timing.
 *
 * @param cpu               Main CPU instance
 * @param cycles_per_line   Cycles per scanline
 * @param lines_per_frame   Scanlines per frame
 */
void m65832_coproc_set_timing(m65832_cpu_t *cpu, uint32_t cycles_per_line,
                               uint32_t lines_per_frame);

/*
 * Execute 6502 coprocessor for a number of cycles.
 *
 * @param cpu       Main CPU instance
 * @param cycles    Cycles to execute
 * @return          Actual cycles executed
 */
int m65832_coproc_run(m65832_cpu_t *cpu, int cycles);

/*
 * Assert IRQ on 6502 coprocessor.
 *
 * @param cpu       Main CPU instance
 * @param active    true to assert, false to deassert
 */
void m65832_coproc_irq(m65832_cpu_t *cpu, bool active);

/*
 * Trigger NMI on 6502 coprocessor.
 *
 * @param cpu       Main CPU instance
 */
void m65832_coproc_nmi(m65832_cpu_t *cpu);

/*
 * Get 6502 coprocessor state.
 *
 * @param cpu       Main CPU instance
 * @return          6502 state, or NULL if not configured
 */
m6502_cpu_t *m65832_coproc_get(m65832_cpu_t *cpu);

/*
 * Read from shadow I/O register.
 *
 * @param cpu       Main CPU instance
 * @param bank      Bank number (0-3)
 * @param reg       Register number (0-63)
 * @return          Register value
 */
uint8_t m65832_coproc_shadow_read(m65832_cpu_t *cpu, int bank, int reg);

/*
 * Pop an entry from the shadow write FIFO.
 *
 * @param cpu       Main CPU instance
 * @param entry     Output entry
 * @return          true if entry popped, false if FIFO empty
 */
bool m65832_coproc_fifo_pop(m65832_cpu_t *cpu, m6502_fifo_entry_t *entry);

/*
 * Get FIFO entry count.
 *
 * @param cpu       Main CPU instance
 * @return          Number of entries in FIFO
 */
int m65832_coproc_fifo_count(m65832_cpu_t *cpu);

/*
 * Print 6502 coprocessor state.
 *
 * @param cpu       Main CPU instance
 */
void m65832_coproc_print_state(m65832_cpu_t *cpu);

/* ============================================================================
 * Utility Functions
 * ========================================================================= */

/*
 * Get library version string.
 *
 * @return  Version string (e.g., "1.0.0")
 */
const char *m65832_version(void);

/*
 * Direct memory read (bypasses callbacks).
 *
 * @param cpu       CPU instance
 * @param addr      Address
 * @return          Byte at address
 */
uint8_t m65832_peek(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Direct memory write (bypasses callbacks).
 *
 * @param cpu       CPU instance
 * @param addr      Address
 * @param val       Value to write
 */
void m65832_poke(m65832_cpu_t *cpu, uint32_t addr, uint8_t val);

/*
 * Read 16-bit value (little-endian).
 */
uint16_t m65832_peek16(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Read 32-bit value (little-endian).
 */
uint32_t m65832_peek32(m65832_cpu_t *cpu, uint32_t addr);

/*
 * Write 16-bit value (little-endian).
 */
void m65832_poke16(m65832_cpu_t *cpu, uint32_t addr, uint16_t val);

/*
 * Write 32-bit value (little-endian).
 */
void m65832_poke32(m65832_cpu_t *cpu, uint32_t addr, uint32_t val);

#ifdef __cplusplus
}
#endif

#endif /* M65832EMU_H */
