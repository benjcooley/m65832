/*
 * system.h - M65832 Minimal System Emulation
 *
 * Wires together CPU, memory, and I/O devices into a complete system.
 * Provides boot support for loading kernels and initramfs.
 */

#ifndef SYSTEM_H
#define SYSTEM_H

#include "m65832emu.h"
#include "uart.h"
#include "blkdev.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct system_state;

/* ============================================================================
 * System Memory Map
 * ========================================================================= */

/*
 * Memory Map (for Linux-capable system):
 *
 *   0x00000000 - 0x00000FFF   Reserved (vectors, zero page)
 *   0x00001000 - 0x00001FFF   Boot parameters
 *   0x00002000 - 0x000FFFFF   Available RAM
 *   0x00100000 - 0x00FFFFFF   Kernel load area (1MB-16MB)
 *   0x01000000 - 0x0FFFFFFF   initrd / general RAM
 *   0xFFFF0000 - 0xFFFF0FFF   Boot ROM (4KB)
 *   0xFFFFF000 - 0xFFFFF0FF   System registers (MMU, timer)
 *   0xFFFFF100 - 0xFFFFF10F   UART
 *   0xFFFFF120 - 0xFFFFF13F   Block device
 */

#define SYSTEM_BOOT_PARAMS      0x00001000
#define SYSTEM_KERNEL_LOAD      0x00100000
#define SYSTEM_INITRD_LOAD      0x01000000
#define SYSTEM_BOOT_ROM         0xFFFF0000
#define SYSTEM_BOOT_ROM_SIZE    0x1000

/* ============================================================================
 * Boot Parameters Structure
 * ========================================================================= */

/*
 * Boot parameters passed to kernel at SYSTEM_BOOT_PARAMS.
 * This is a simple flat structure for early bringup.
 */
typedef struct {
    uint32_t magic;             /* 0x4D363538 = "M658" */
    uint32_t version;           /* Boot protocol version (1) */
    uint32_t mem_base;          /* Physical memory base */
    uint32_t mem_size;          /* Physical memory size */
    uint32_t kernel_start;      /* Kernel load address */
    uint32_t kernel_size;       /* Kernel size in bytes */
    uint32_t initrd_start;      /* initrd load address (0 if none) */
    uint32_t initrd_size;       /* initrd size in bytes */
    uint32_t cmdline_addr;      /* Command line address (0 if none) */
    uint32_t cmdline_size;      /* Command line length */
    uint32_t uart_base;         /* UART base address */
    uint32_t timer_base;        /* Timer base address */
    uint32_t reserved[20];      /* Reserved for future use */
} boot_params_t;

#define BOOT_PARAMS_MAGIC   0x4D363538  /* "M658" */
#define BOOT_PARAMS_VERSION 1

/* ============================================================================
 * System Configuration
 * ========================================================================= */

typedef struct {
    /* Memory configuration */
    size_t ram_size;            /* RAM size in bytes (default 256MB) */
    
    /* Boot configuration */
    const char *kernel_file;    /* Kernel binary to load (NULL = none) */
    const char *initrd_file;    /* initrd/initramfs to load (NULL = none) */
    const char *cmdline;        /* Kernel command line (NULL = none) */
    uint32_t entry_point;       /* Entry point override (0 = default) */
    
    /* Device configuration */
    bool enable_uart;           /* Enable UART device (default true) */
    bool uart_raw_mode;         /* Put terminal in raw mode */
    
    /* Block device */
    bool enable_blkdev;         /* Enable block device (default true) */
    const char *disk_file;      /* Disk image file (NULL = none) */
    bool disk_readonly;         /* Open disk read-only */
    
    /* Execution configuration */
    bool supervisor_mode;       /* Start in supervisor mode */
    bool native32_mode;         /* Start in native 32-bit mode */
    bool verbose;               /* Verbose output */

    /* Syscall handling */
    const char *sandbox_root;   /* Sandbox root for emulated filesystem */
    void *syscall_user;         /* User data passed to syscall handler */
    bool (*syscall_handler)(struct system_state *sys, uint8_t trap_code, void *user);
} system_config_t;

/* Default configuration values */
#define SYSTEM_DEFAULT_RAM_SIZE     (256 * 1024 * 1024)  /* 256 MB */

/* ============================================================================
 * System State
 * ========================================================================= */

typedef struct system_state {
    /* CPU */
    m65832_cpu_t *cpu;
    
    /* Devices */
    uart_state_t *uart;
    blkdev_state_t *blkdev;
    
    /* Boot parameters */
    boot_params_t boot_params;
    
    /* Configuration */
    system_config_t config;

    /* Syscall handler */
    bool (*syscall_handler)(struct system_state *sys, uint8_t trap_code, void *user);
    void *syscall_user;
    char *sandbox_root;

    /* Emulated file descriptors (guest fd -> host fd) */
    int host_fds[32];
    bool fd_used[32];
    
    /* ELF loading */
    uint32_t elf_entry;         /* Entry point from ELF (0 if raw binary) */
    
    /* State */
    bool running;
    uint64_t poll_interval;     /* Instructions between device polls */
    uint64_t poll_counter;
} system_state_t;

/* ============================================================================
 * System API
 * ========================================================================= */

/*
 * Initialize default system configuration.
 *
 * @param config    Configuration structure to initialize
 */
void system_config_init(system_config_t *config);

/*
 * Create and initialize a complete system.
 *
 * @param config    System configuration
 * @return          System state, or NULL on error
 */
system_state_t *system_init(const system_config_t *config);

/*
 * Destroy system and free all resources.
 *
 * @param sys       System state
 */
void system_destroy(system_state_t *sys);

/*
 * Reset the system (CPU and devices).
 *
 * @param sys       System state
 */
void system_reset(system_state_t *sys);

/*
 * Run the system for a number of cycles.
 *
 * @param sys       System state
 * @param cycles    Maximum cycles to execute (0 = until halt/interrupt)
 * @return          Actual cycles executed
 */
uint64_t system_run(system_state_t *sys, uint64_t cycles);

/*
 * Run the system until it halts or a trap occurs.
 *
 * @param sys       System state
 */
void system_run_until_halt(system_state_t *sys);

/*
 * Stop system execution (can be called from signal handler).
 *
 * @param sys       System state
 */
void system_stop(system_state_t *sys);

/*
 * Check if system is running.
 *
 * @param sys       System state
 * @return          true if running
 */
bool system_is_running(system_state_t *sys);

/*
 * Poll all devices for I/O events.
 * Called periodically during execution.
 *
 * @param sys       System state
 */
void system_poll_devices(system_state_t *sys);

/*
 * Load a kernel image into system memory.
 *
 * @param sys       System state
 * @param filename  Kernel file to load
 * @param addr      Load address (0 = default SYSTEM_KERNEL_LOAD)
 * @return          Bytes loaded, or -1 on error
 */
int system_load_kernel(system_state_t *sys, const char *filename, uint32_t addr);

/*
 * Load an initrd/initramfs into system memory.
 *
 * @param sys       System state
 * @param filename  initrd file to load
 * @param addr      Load address (0 = default SYSTEM_INITRD_LOAD)
 * @return          Bytes loaded, or -1 on error
 */
int system_load_initrd(system_state_t *sys, const char *filename, uint32_t addr);

/*
 * Write boot parameters to memory.
 *
 * @param sys       System state
 */
void system_write_boot_params(system_state_t *sys);

/*
 * Get the CPU instance for direct access.
 *
 * @param sys       System state
 * @return          CPU instance
 */
m65832_cpu_t *system_get_cpu(system_state_t *sys);

/*
 * Print system state summary.
 *
 * @param sys       System state
 */
void system_print_info(system_state_t *sys);

/*
 * Set a syscall handler callback.
 *
 * @param sys       System state
 * @param handler   Callback for TRAP syscalls (NULL disables handling)
 * @param user      User pointer passed to handler
 */
void system_set_syscall_handler(system_state_t *sys,
                                bool (*handler)(system_state_t *sys, uint8_t trap_code, void *user),
                                void *user);

#ifdef __cplusplus
}
#endif

#endif /* SYSTEM_H */
