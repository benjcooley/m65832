/*
 * bootrom.c - M65832 Boot ROM MMIO Module
 *
 * Loads a boot ROM binary and exposes it as a read-only MMIO region.
 * Writes are silently ignored (true ROM behavior).
 */

#include "bootrom.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct bootrom_state {
    uint8_t    *data;           /* ROM contents */
    uint32_t    size;           /* ROM size in bytes */
    uint32_t    base_addr;      /* MMIO base address */
    m65832_cpu_t *cpu;          /* CPU reference */
    int         mmio_index;     /* MMIO registration index */
};

/* MMIO read handler -- returns ROM byte at offset */
static uint32_t bootrom_mmio_read(m65832_cpu_t *cpu, uint32_t addr,
                                   uint32_t offset, int width, void *user) {
    (void)cpu;
    (void)addr;
    
    bootrom_state_t *rom = (bootrom_state_t *)user;
    
    if (offset >= rom->size) return 0;
    
    /* Support different access widths */
    uint32_t value = 0;
    switch (width) {
        case 1:
            value = rom->data[offset];
            break;
        case 2:
            if (offset + 1 < rom->size) {
                value = (uint32_t)rom->data[offset] |
                        ((uint32_t)rom->data[offset + 1] << 8);
            }
            break;
        case 4:
            if (offset + 3 < rom->size) {
                value = (uint32_t)rom->data[offset] |
                        ((uint32_t)rom->data[offset + 1] << 8) |
                        ((uint32_t)rom->data[offset + 2] << 16) |
                        ((uint32_t)rom->data[offset + 3] << 24);
            }
            break;
        default:
            value = rom->data[offset];
            break;
    }
    
    return value;
}

/* MMIO write handler -- silently ignored (ROM is read-only) */
static void bootrom_mmio_write(m65832_cpu_t *cpu, uint32_t addr,
                                uint32_t offset, uint32_t value,
                                int width, void *user) {
    (void)cpu;
    (void)addr;
    (void)offset;
    (void)value;
    (void)width;
    (void)user;
    /* ROM is read-only -- writes are silently ignored */
}

bootrom_state_t *bootrom_load(m65832_cpu_t *cpu, const char *filename,
                              uint32_t base_addr, uint32_t size, bool verbose) {
    if (!cpu || !filename) return NULL;
    
    bootrom_state_t *rom = calloc(1, sizeof(bootrom_state_t));
    if (!rom) {
        fprintf(stderr, "bootrom: cannot allocate state\n");
        return NULL;
    }
    
    rom->cpu = cpu;
    rom->base_addr = base_addr;
    rom->size = size;
    rom->mmio_index = -1;
    
    /* Allocate ROM buffer, fill with NOP (0xEA) */
    rom->data = malloc(size);
    if (!rom->data) {
        fprintf(stderr, "bootrom: cannot allocate %u bytes\n", size);
        free(rom);
        return NULL;
    }
    memset(rom->data, 0xEA, size);  /* Fill with NOP */
    
    /* Read ROM binary file */
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "bootrom: cannot open '%s'\n", filename);
        free(rom->data);
        free(rom);
        return NULL;
    }
    
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if (file_size <= 0) {
        fprintf(stderr, "bootrom: empty file '%s'\n", filename);
        fclose(f);
        free(rom->data);
        free(rom);
        return NULL;
    }
    
    /* Read up to ROM size */
    size_t read_size = (size_t)file_size;
    if (read_size > size) {
        fprintf(stderr, "bootrom: warning: file is %ld bytes, ROM is %u bytes (truncated)\n",
                file_size, size);
        read_size = size;
    }
    
    size_t nread = fread(rom->data, 1, read_size, f);
    fclose(f);
    
    if (nread != read_size) {
        fprintf(stderr, "bootrom: short read from '%s'\n", filename);
        free(rom->data);
        free(rom);
        return NULL;
    }
    
    /* Register MMIO region */
    rom->mmio_index = m65832_mmio_register(
        cpu,
        base_addr,
        size,
        bootrom_mmio_read,
        bootrom_mmio_write,
        rom,
        "BootROM"
    );
    
    if (rom->mmio_index < 0) {
        fprintf(stderr, "bootrom: cannot register MMIO at 0x%08X\n", base_addr);
        free(rom->data);
        free(rom);
        return NULL;
    }
    
    if (verbose) {
        printf("Boot ROM: %zu bytes loaded from '%s' at 0x%08X\n",
               nread, filename, base_addr);
    }
    
    return rom;
}

void bootrom_destroy(bootrom_state_t *rom) {
    if (!rom) return;
    
    if (rom->cpu && rom->mmio_index >= 0) {
        m65832_mmio_unregister(rom->cpu, rom->mmio_index);
    }
    
    free(rom->data);
    free(rom);
}

uint32_t bootrom_get_entry(bootrom_state_t *rom) {
    if (!rom || !rom->data || rom->size < 0x1000) return 0;
    
    /* Reset vector is at ROM offset 0xFFC (4 bytes, little-endian) */
    uint32_t offset = 0xFFC;
    if (offset + 3 >= rom->size) return 0;
    
    uint32_t entry = (uint32_t)rom->data[offset] |
                     ((uint32_t)rom->data[offset + 1] << 8) |
                     ((uint32_t)rom->data[offset + 2] << 16) |
                     ((uint32_t)rom->data[offset + 3] << 24);
    
    /* Sanity check: entry should be in the ROM range */
    if (entry >= rom->base_addr && entry < rom->base_addr + rom->size) {
        return entry;
    }
    
    /* If no valid vector, default to ROM base */
    return rom->base_addr;
}
