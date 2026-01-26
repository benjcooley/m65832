/*
 * blkdev.h - M65832 Block Device Emulation
 *
 * Simple block device for disk/storage access.
 * Supports sector-based read/write with DMA transfers.
 */

#ifndef BLKDEV_H
#define BLKDEV_H

#include "m65832emu.h"
#include <stdbool.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Block Device Register Definitions
 * ========================================================================= */

/* Block device base address (in MMIO space - 24-bit addressable) */
#define BLKDEV_BASE         0x00FFF120

/* Block device register offsets (32 bytes total) */
#define BLKDEV_STATUS       0x00    /* Status register (R) */
#define BLKDEV_COMMAND      0x04    /* Command register (W) */
#define BLKDEV_SECTOR_LO    0x08    /* Sector number low 32 bits (R/W) */
#define BLKDEV_SECTOR_HI    0x0C    /* Sector number high 32 bits (R/W) */
#define BLKDEV_DMA_ADDR     0x10    /* DMA address for data transfer (R/W) */
#define BLKDEV_COUNT        0x14    /* Sector count for multi-sector ops (R/W) */
#define BLKDEV_CAPACITY_LO  0x18    /* Disk capacity in sectors - low (R) */
#define BLKDEV_CAPACITY_HI  0x1C    /* Disk capacity in sectors - high (R) */

/* Block device region size */
#define BLKDEV_SIZE         0x20

/* Sector size (standard 512 bytes) */
#define BLKDEV_SECTOR_SIZE  512

/* Status register bits */
#define BLKDEV_STATUS_READY     0x01    /* Device ready for commands */
#define BLKDEV_STATUS_BUSY      0x02    /* Operation in progress */
#define BLKDEV_STATUS_ERROR     0x04    /* Error occurred */
#define BLKDEV_STATUS_DRQ       0x08    /* Data request (for PIO mode) */
#define BLKDEV_STATUS_PRESENT   0x10    /* Media present */
#define BLKDEV_STATUS_WRITABLE  0x20    /* Media is writable */
#define BLKDEV_STATUS_IRQ       0x40    /* IRQ pending (operation complete) */

/* Error codes (in high byte of status when ERROR is set) */
#define BLKDEV_ERR_NONE         0x00    /* No error */
#define BLKDEV_ERR_NOT_READY    0x01    /* Device not ready */
#define BLKDEV_ERR_NO_MEDIA     0x02    /* No media present */
#define BLKDEV_ERR_WRITE_PROT   0x03    /* Write protected */
#define BLKDEV_ERR_BAD_SECTOR   0x04    /* Invalid sector number */
#define BLKDEV_ERR_IO           0x05    /* I/O error */
#define BLKDEV_ERR_BAD_CMD      0x06    /* Invalid command */
#define BLKDEV_ERR_DMA          0x07    /* DMA address error */

/* Command codes */
#define BLKDEV_CMD_NOP          0x00    /* No operation */
#define BLKDEV_CMD_READ         0x01    /* Read sector(s) via DMA */
#define BLKDEV_CMD_WRITE        0x02    /* Write sector(s) via DMA */
#define BLKDEV_CMD_FLUSH        0x03    /* Flush write cache */
#define BLKDEV_CMD_IDENTIFY     0x04    /* Identify device (read info) */
#define BLKDEV_CMD_RESET        0x05    /* Reset device */
#define BLKDEV_CMD_ACK_IRQ      0x06    /* Acknowledge interrupt */

/* ============================================================================
 * Block Device State
 * ========================================================================= */

typedef struct blkdev_state {
    /* Backing storage */
    FILE       *file;               /* Disk image file */
    char       *filename;           /* Filename for reopening */
    uint64_t    capacity;           /* Capacity in sectors */
    bool        writable;           /* File opened for writing */
    bool        dirty;              /* Unflushed writes pending */
    
    /* Registers */
    uint32_t    status;             /* Status register */
    uint64_t    sector;             /* Current sector number */
    uint32_t    dma_addr;           /* DMA address */
    uint32_t    count;              /* Sector count */
    uint8_t     error;              /* Error code */
    
    /* Configuration */
    bool        irq_enable;         /* IRQ enabled */
    bool        irq_pending;        /* IRQ waiting to be acknowledged */
    
    /* CPU reference */
    m65832_cpu_t *cpu;
    
    /* MMIO region index */
    int         mmio_index;
} blkdev_state_t;

/* ============================================================================
 * Block Device API
 * ========================================================================= */

/*
 * Initialize block device with a disk image file.
 *
 * @param cpu           CPU instance to attach to
 * @param filename      Path to disk image file (NULL = no disk)
 * @param read_only     Open file read-only
 * @return              Block device state, or NULL on error
 */
blkdev_state_t *blkdev_init(m65832_cpu_t *cpu, const char *filename, bool read_only);

/*
 * Destroy block device and close file.
 *
 * @param blk           Block device state
 */
void blkdev_destroy(blkdev_state_t *blk);

/*
 * Attach or change disk image.
 *
 * @param blk           Block device state
 * @param filename      Path to disk image (NULL to eject)
 * @param read_only     Open file read-only
 * @return              true on success
 */
bool blkdev_attach(blkdev_state_t *blk, const char *filename, bool read_only);

/*
 * Eject current disk image.
 *
 * @param blk           Block device state
 */
void blkdev_eject(blkdev_state_t *blk);

/*
 * Create a new disk image file.
 *
 * @param filename      Path to create
 * @param sectors       Size in sectors
 * @return              true on success
 */
bool blkdev_create_image(const char *filename, uint64_t sectors);

/*
 * Check if IRQ should be triggered.
 *
 * @param blk           Block device state
 * @return              true if IRQ should be asserted
 */
bool blkdev_irq_pending(blkdev_state_t *blk);

/*
 * Get disk capacity in sectors.
 *
 * @param blk           Block device state
 * @return              Capacity in sectors (0 if no media)
 */
uint64_t blkdev_get_capacity(blkdev_state_t *blk);

/*
 * Get disk capacity in bytes.
 *
 * @param blk           Block device state
 * @return              Capacity in bytes (0 if no media)
 */
uint64_t blkdev_get_capacity_bytes(blkdev_state_t *blk);

#ifdef __cplusplus
}
#endif

#endif /* BLKDEV_H */
