/*
 * platform.h - M65832 Platform Configuration Interface
 *
 * Common interface for platform-specific MMIO addresses and settings.
 * Each platform (DE25, KV260, etc.) has its own implementation file.
 *
 * Canonical memory map from M65832_System_Bus.md:
 *   0x0000_0000 - 0x0000_FFFF : Boot ROM (64 KB)
 *   0x0001_0000 - 0x0FFF_FFFF : DDR RAM
 *   0x1000_0000 - 0x100F_FFFF : Peripheral registers (MMIO)
 *   0xFFFF_F000 - 0xFFFF_FFFF : System registers (MMU, Timer)
 */

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Platform Identifiers
 * ========================================================================= */

typedef enum {
    PLATFORM_DE25 = 0,      /* Terasic DE2-115 (Cyclone IV) - default */
    PLATFORM_KV260,         /* AMD/Xilinx KV260 (Zynq UltraScale+) */
    PLATFORM_COUNT
} platform_id_t;

/* ============================================================================
 * Platform Configuration Structure
 * ========================================================================= */

typedef struct {
    /* Platform identification */
    platform_id_t id;
    const char *name;
    const char *description;
    
    /* Memory configuration */
    uint32_t ram_base;
    uint32_t ram_size;
    uint32_t boot_rom_base;
    uint32_t boot_rom_size;
    
    /* Clock frequencies (Hz) */
    uint32_t cpu_freq;
    uint32_t timer_freq;
    uint32_t uart_freq;
    
    /* Peripheral base addresses */
    uint32_t uart_base;
    uint32_t sd_base;
    uint32_t intc_base;
    uint32_t timer_base;        /* System timer in SYSREG space */
    uint32_t gpio_base;
    uint32_t spi_base;
    uint32_t i2c_base;
    
    /* System register base (MMU control, etc.) */
    uint32_t sysreg_base;
    
    /* Platform-specific features */
    bool has_sd_card;
    bool has_ethernet;
    bool has_hdmi;
    bool has_vga;
    
} platform_config_t;

/* ============================================================================
 * Platform API
 * ========================================================================= */

/* Get configuration for a platform */
const platform_config_t *platform_get_config(platform_id_t id);

/* Get platform by name (case-insensitive) */
platform_id_t platform_get_by_name(const char *name);

/* Get default platform */
platform_id_t platform_get_default(void);

/* Print list of supported platforms */
void platform_list_all(void);

/* ============================================================================
 * Platform-specific initialization (implemented per-platform)
 * ========================================================================= */

/* Each platform provides its configuration */
extern const platform_config_t platform_de25_config;
extern const platform_config_t platform_kv260_config;

#ifdef __cplusplus
}
#endif

#endif /* PLATFORM_H */
