/*
 * blkdev.c - M65832 Block Device Emulation
 *
 * Simple block device backed by a disk image file.
 * Supports sector-based read/write with DMA transfers.
 */

#include "blkdev.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

/* ============================================================================
 * Internal Helpers
 * ========================================================================= */

static void blkdev_set_error(blkdev_state_t *blk, uint8_t error) {
    blk->error = error;
    if (error != BLKDEV_ERR_NONE) {
        blk->status |= BLKDEV_STATUS_ERROR;
    }
}

static void blkdev_clear_error(blkdev_state_t *blk) {
    blk->error = BLKDEV_ERR_NONE;
    blk->status &= ~BLKDEV_STATUS_ERROR;
}

static void blkdev_complete_operation(blkdev_state_t *blk) {
    /* Clear busy, set ready */
    blk->status &= ~BLKDEV_STATUS_BUSY;
    blk->status |= BLKDEV_STATUS_READY;
    
    /* Set IRQ if enabled */
    if (blk->irq_enable) {
        blk->status |= BLKDEV_STATUS_IRQ;
        blk->irq_pending = true;
    }
}

static void blkdev_update_status(blkdev_state_t *blk) {
    blk->status &= ~(BLKDEV_STATUS_PRESENT | BLKDEV_STATUS_WRITABLE);
    
    if (blk->file) {
        blk->status |= BLKDEV_STATUS_PRESENT;
        if (blk->writable) {
            blk->status |= BLKDEV_STATUS_WRITABLE;
        }
    }
}

/* ============================================================================
 * DMA Operations
 * ========================================================================= */

/*
 * Read sectors from disk to memory via DMA.
 */
static void blkdev_do_read(blkdev_state_t *blk) {
    if (!blk->file) {
        blkdev_set_error(blk, BLKDEV_ERR_NO_MEDIA);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Validate sector range */
    if (blk->sector + blk->count > blk->capacity) {
        blkdev_set_error(blk, BLKDEV_ERR_BAD_SECTOR);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Validate DMA address */
    size_t mem_size = m65832_emu_get_memory_size(blk->cpu);
    size_t xfer_size = (size_t)blk->count * BLKDEV_SECTOR_SIZE;
    if (blk->dma_addr + xfer_size > mem_size) {
        blkdev_set_error(blk, BLKDEV_ERR_DMA);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Seek to sector */
    uint64_t offset = blk->sector * BLKDEV_SECTOR_SIZE;
    if (fseeko(blk->file, (off_t)offset, SEEK_SET) != 0) {
        blkdev_set_error(blk, BLKDEV_ERR_IO);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Read sectors into memory */
    uint8_t *mem = m65832_emu_get_memory_ptr(blk->cpu);
    if (!mem) {
        blkdev_set_error(blk, BLKDEV_ERR_DMA);
        blkdev_complete_operation(blk);
        return;
    }
    
    size_t read = fread(mem + blk->dma_addr, 1, xfer_size, blk->file);
    if (read != xfer_size) {
        /* Partial read - might be end of file, zero-fill rest */
        if (read < xfer_size) {
            memset(mem + blk->dma_addr + read, 0, xfer_size - read);
        }
    }
    
    blkdev_clear_error(blk);
    blkdev_complete_operation(blk);
}

/*
 * Write sectors from memory to disk via DMA.
 */
static void blkdev_do_write(blkdev_state_t *blk) {
    if (!blk->file) {
        blkdev_set_error(blk, BLKDEV_ERR_NO_MEDIA);
        blkdev_complete_operation(blk);
        return;
    }
    
    if (!blk->writable) {
        blkdev_set_error(blk, BLKDEV_ERR_WRITE_PROT);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Validate sector range */
    if (blk->sector + blk->count > blk->capacity) {
        blkdev_set_error(blk, BLKDEV_ERR_BAD_SECTOR);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Validate DMA address */
    size_t mem_size = m65832_emu_get_memory_size(blk->cpu);
    size_t xfer_size = (size_t)blk->count * BLKDEV_SECTOR_SIZE;
    if (blk->dma_addr + xfer_size > mem_size) {
        blkdev_set_error(blk, BLKDEV_ERR_DMA);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Seek to sector */
    uint64_t offset = blk->sector * BLKDEV_SECTOR_SIZE;
    if (fseeko(blk->file, (off_t)offset, SEEK_SET) != 0) {
        blkdev_set_error(blk, BLKDEV_ERR_IO);
        blkdev_complete_operation(blk);
        return;
    }
    
    /* Write sectors from memory */
    uint8_t *mem = m65832_emu_get_memory_ptr(blk->cpu);
    if (!mem) {
        blkdev_set_error(blk, BLKDEV_ERR_DMA);
        blkdev_complete_operation(blk);
        return;
    }
    
    size_t written = fwrite(mem + blk->dma_addr, 1, xfer_size, blk->file);
    if (written != xfer_size) {
        blkdev_set_error(blk, BLKDEV_ERR_IO);
        blkdev_complete_operation(blk);
        return;
    }
    
    blk->dirty = true;
    blkdev_clear_error(blk);
    blkdev_complete_operation(blk);
}

/*
 * Flush write cache to disk.
 */
static void blkdev_do_flush(blkdev_state_t *blk) {
    if (!blk->file) {
        blkdev_set_error(blk, BLKDEV_ERR_NO_MEDIA);
        blkdev_complete_operation(blk);
        return;
    }
    
    if (blk->dirty && blk->writable) {
        if (fflush(blk->file) != 0) {
            blkdev_set_error(blk, BLKDEV_ERR_IO);
            blkdev_complete_operation(blk);
            return;
        }
        blk->dirty = false;
    }
    
    blkdev_clear_error(blk);
    blkdev_complete_operation(blk);
}

/*
 * Reset device to initial state.
 */
static void blkdev_do_reset(blkdev_state_t *blk) {
    blk->sector = 0;
    blk->dma_addr = 0;
    blk->count = 1;
    blkdev_clear_error(blk);
    blk->irq_pending = false;
    blk->status &= ~BLKDEV_STATUS_IRQ;
    blkdev_update_status(blk);
    blkdev_complete_operation(blk);
}

/*
 * Execute a command.
 */
static void blkdev_execute_command(blkdev_state_t *blk, uint32_t cmd) {
    /* Set busy, clear ready */
    blk->status |= BLKDEV_STATUS_BUSY;
    blk->status &= ~BLKDEV_STATUS_READY;
    blkdev_clear_error(blk);
    
    switch (cmd & 0xFF) {
        case BLKDEV_CMD_NOP:
            blkdev_complete_operation(blk);
            break;
            
        case BLKDEV_CMD_READ:
            blkdev_do_read(blk);
            break;
            
        case BLKDEV_CMD_WRITE:
            blkdev_do_write(blk);
            break;
            
        case BLKDEV_CMD_FLUSH:
            blkdev_do_flush(blk);
            break;
            
        case BLKDEV_CMD_IDENTIFY:
            /* For now, just complete successfully - device info is in registers */
            blkdev_complete_operation(blk);
            break;
            
        case BLKDEV_CMD_RESET:
            blkdev_do_reset(blk);
            break;
            
        case BLKDEV_CMD_ACK_IRQ:
            blk->status &= ~BLKDEV_STATUS_IRQ;
            blk->irq_pending = false;
            blkdev_complete_operation(blk);
            break;
            
        default:
            blkdev_set_error(blk, BLKDEV_ERR_BAD_CMD);
            blkdev_complete_operation(blk);
            break;
    }
}

/* ============================================================================
 * MMIO Handlers
 * ========================================================================= */

static uint32_t blkdev_mmio_read(m65832_cpu_t *cpu, uint32_t addr,
                                  uint32_t offset, int width, void *user) {
    (void)cpu;
    (void)addr;
    (void)width;
    
    blkdev_state_t *blk = (blkdev_state_t *)user;
    uint32_t value = 0;
    
    switch (offset) {
        case BLKDEV_STATUS:
            /* Status in low byte, error code in high byte */
            value = (blk->status & 0xFF) | ((uint32_t)blk->error << 8);
            break;
            
        case BLKDEV_COMMAND:
            /* Command register is write-only */
            value = 0;
            break;
            
        case BLKDEV_SECTOR_LO:
            value = (uint32_t)(blk->sector & 0xFFFFFFFF);
            break;
            
        case BLKDEV_SECTOR_HI:
            value = (uint32_t)(blk->sector >> 32);
            break;
            
        case BLKDEV_DMA_ADDR:
            value = blk->dma_addr;
            break;
            
        case BLKDEV_COUNT:
            value = blk->count;
            break;
            
        case BLKDEV_CAPACITY_LO:
            value = (uint32_t)(blk->capacity & 0xFFFFFFFF);
            break;
            
        case BLKDEV_CAPACITY_HI:
            value = (uint32_t)(blk->capacity >> 32);
            break;
            
        default:
            value = 0;
            break;
    }
    
    return value;
}

static void blkdev_mmio_write(m65832_cpu_t *cpu, uint32_t addr,
                               uint32_t offset, uint32_t value,
                               int width, void *user) {
    (void)cpu;
    (void)addr;
    (void)width;
    
    blkdev_state_t *blk = (blkdev_state_t *)user;
    
    switch (offset) {
        case BLKDEV_STATUS:
            /* Status is read-only, but writing can enable/disable IRQs */
            /* Bit 6 (IRQ) written as 1 = enable IRQs, 0 = disable */
            blk->irq_enable = (value & BLKDEV_STATUS_IRQ) != 0;
            break;
            
        case BLKDEV_COMMAND:
            /* Execute command (only if device is ready) */
            if (blk->status & BLKDEV_STATUS_READY) {
                blkdev_execute_command(blk, value);
            }
            break;
            
        case BLKDEV_SECTOR_LO:
            blk->sector = (blk->sector & 0xFFFFFFFF00000000ULL) | value;
            break;
            
        case BLKDEV_SECTOR_HI:
            blk->sector = (blk->sector & 0x00000000FFFFFFFFULL) | ((uint64_t)value << 32);
            break;
            
        case BLKDEV_DMA_ADDR:
            blk->dma_addr = value;
            break;
            
        case BLKDEV_COUNT:
            /* Limit to reasonable value to prevent huge transfers */
            blk->count = (value > 0 && value <= 256) ? value : 1;
            break;
            
        case BLKDEV_CAPACITY_LO:
        case BLKDEV_CAPACITY_HI:
            /* Capacity is read-only */
            break;
            
        default:
            break;
    }
}

/* ============================================================================
 * Public API
 * ========================================================================= */

blkdev_state_t *blkdev_init(m65832_cpu_t *cpu, const platform_config_t *platform,
                            const char *filename, bool read_only) {
    if (!cpu || !platform) return NULL;
    
    blkdev_state_t *blk = calloc(1, sizeof(blkdev_state_t));
    if (!blk) return NULL;
    
    blk->cpu = cpu;
    blk->base_addr = platform->sd_base;
    blk->file = NULL;
    blk->filename = NULL;
    blk->capacity = 0;
    blk->writable = false;
    blk->dirty = false;
    
    /* Initialize registers */
    blk->status = BLKDEV_STATUS_READY;
    blk->sector = 0;
    blk->dma_addr = 0;
    blk->count = 1;
    blk->error = BLKDEV_ERR_NONE;
    blk->irq_enable = false;
    blk->irq_pending = false;
    
    /* Register MMIO region at platform-specified address */
    blk->mmio_index = m65832_mmio_register(
        cpu,
        platform->sd_base,
        BLKDEV_SIZE,
        blkdev_mmio_read,
        blkdev_mmio_write,
        blk,
        "SD/BLKDEV"
    );
    
    if (blk->mmio_index < 0) {
        free(blk);
        return NULL;
    }
    
    /* Attach disk image if specified */
    if (filename) {
        if (!blkdev_attach(blk, filename, read_only)) {
            /* Not fatal - device exists but no media */
        }
    }
    
    blkdev_update_status(blk);
    return blk;
}

void blkdev_destroy(blkdev_state_t *blk) {
    if (!blk) return;
    
    /* Flush and close file */
    if (blk->file) {
        if (blk->dirty && blk->writable) {
            fflush(blk->file);
        }
        fclose(blk->file);
    }
    
    /* Free filename */
    if (blk->filename) {
        free(blk->filename);
    }
    
    /* Unregister MMIO */
    if (blk->cpu && blk->mmio_index >= 0) {
        m65832_mmio_unregister(blk->cpu, blk->mmio_index);
    }
    
    free(blk);
}

bool blkdev_attach(blkdev_state_t *blk, const char *filename, bool read_only) {
    if (!blk) return false;
    
    /* Close existing file */
    blkdev_eject(blk);
    
    if (!filename) {
        return true;  /* Just eject, which succeeded */
    }
    
    /* Try to open file */
    const char *mode = read_only ? "rb" : "r+b";
    blk->file = fopen(filename, mode);
    
    if (!blk->file && !read_only) {
        /* Try read-only if read-write failed */
        blk->file = fopen(filename, "rb");
        if (blk->file) {
            read_only = true;
        }
    }
    
    if (!blk->file) {
        fprintf(stderr, "blkdev: cannot open '%s': %s\n", filename, strerror(errno));
        return false;
    }
    
    /* Get file size */
    fseeko(blk->file, 0, SEEK_END);
    off_t size = ftello(blk->file);
    fseeko(blk->file, 0, SEEK_SET);
    
    if (size <= 0) {
        fprintf(stderr, "blkdev: empty file '%s'\n", filename);
        fclose(blk->file);
        blk->file = NULL;
        return false;
    }
    
    /* Calculate capacity */
    blk->capacity = (uint64_t)size / BLKDEV_SECTOR_SIZE;
    blk->writable = !read_only;
    blk->dirty = false;
    
    /* Save filename */
    blk->filename = strdup(filename);
    
    blkdev_update_status(blk);
    return true;
}

void blkdev_eject(blkdev_state_t *blk) {
    if (!blk) return;
    
    if (blk->file) {
        /* Flush pending writes */
        if (blk->dirty && blk->writable) {
            fflush(blk->file);
        }
        fclose(blk->file);
        blk->file = NULL;
    }
    
    if (blk->filename) {
        free(blk->filename);
        blk->filename = NULL;
    }
    
    blk->capacity = 0;
    blk->writable = false;
    blk->dirty = false;
    
    blkdev_update_status(blk);
}

bool blkdev_create_image(const char *filename, uint64_t sectors) {
    if (!filename || sectors == 0) return false;
    
    FILE *f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "blkdev: cannot create '%s': %s\n", filename, strerror(errno));
        return false;
    }
    
    /* Create sparse file by seeking to end and writing one byte */
    uint64_t size = sectors * BLKDEV_SECTOR_SIZE;
    if (fseeko(f, (off_t)(size - 1), SEEK_SET) != 0) {
        fprintf(stderr, "blkdev: cannot seek in '%s': %s\n", filename, strerror(errno));
        fclose(f);
        return false;
    }
    
    uint8_t zero = 0;
    if (fwrite(&zero, 1, 1, f) != 1) {
        fprintf(stderr, "blkdev: cannot write to '%s': %s\n", filename, strerror(errno));
        fclose(f);
        return false;
    }
    
    fclose(f);
    return true;
}

bool blkdev_irq_pending(blkdev_state_t *blk) {
    return blk && blk->irq_pending;
}

uint64_t blkdev_get_capacity(blkdev_state_t *blk) {
    return blk ? blk->capacity : 0;
}

uint64_t blkdev_get_capacity_bytes(blkdev_state_t *blk) {
    return blk ? blk->capacity * BLKDEV_SECTOR_SIZE : 0;
}
