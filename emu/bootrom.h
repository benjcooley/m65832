/*
 * bootrom.h - M65832 Boot ROM MMIO Module
 *
 * Loads a boot ROM binary and exposes it as a read-only MMIO region
 * at SYSTEM_BOOT_ROM (0xFFFF0000). Identical behavior to the VHDL
 * BRAM-as-ROM on hardware.
 */

#ifndef BOOTROM_H
#define BOOTROM_H

#include "m65832emu.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque boot ROM state */
typedef struct bootrom_state bootrom_state_t;

/*
 * Load a boot ROM binary and register it as MMIO.
 *
 * Reads the .bin file and registers a read-only MMIO region at
 * base_addr (typically SYSTEM_BOOT_ROM = 0xFFFF0000). The region
 * is SYSTEM_BOOT_ROM_SIZE (4KB). If the file is smaller, the
 * remainder is filled with 0xEA (NOP).
 *
 * @param cpu       CPU instance
 * @param filename  Path to boot ROM binary (.bin)
 * @param base_addr MMIO base address (e.g., SYSTEM_BOOT_ROM)
 * @param size      MMIO region size (e.g., SYSTEM_BOOT_ROM_SIZE)
 * @param verbose   Print status messages
 * @return          Boot ROM state, or NULL on error
 */
bootrom_state_t *bootrom_load(m65832_cpu_t *cpu, const char *filename,
                              uint32_t base_addr, uint32_t size, bool verbose);

/*
 * Destroy boot ROM and unregister MMIO.
 *
 * @param rom       Boot ROM state (NULL safe)
 */
void bootrom_destroy(bootrom_state_t *rom);

/*
 * Get the entry point from the boot ROM.
 *
 * Reads the reset vector at ROM offset 0xFFC (a 32-bit address).
 * Returns 0 if no valid vector is found.
 *
 * @param rom       Boot ROM state
 * @return          Entry point address from reset vector
 */
uint32_t bootrom_get_entry(bootrom_state_t *rom);

#ifdef __cplusplus
}
#endif

#endif /* BOOTROM_H */
