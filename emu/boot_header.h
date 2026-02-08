/*
 * boot_header.h - M65832 Boot Image Header
 *
 * Defines the boot header structure written at sector 0 of a bootable
 * disk image. Shared between the emulator, mkbootimg script, and the
 * boot ROM assembly code.
 *
 * See docs/M65832_Boot_Process.md for full documentation.
 */

#ifndef BOOT_HEADER_H
#define BOOT_HEADER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Boot header magic: "M65B" in little-endian */
#define BOOT_HEADER_MAGIC       0x4236354D

/* Current boot header version */
#define BOOT_HEADER_VERSION     1

/*
 * Default kernel start sector.
 *
 * Sector 2048 (1MB) is the standard first partition start in MBR layouts.
 * Disk image layout:
 *   Sector 0:         MBR + boot header (first 32 bytes)
 *   Sectors 1-2047:   Reserved (MBR gap)
 *   Sector 2048+:     Partition 1 -- raw kernel image (vmlinux.bin)
 *   After kernel:     Partition 2 -- ext2 root filesystem
 */
#define BOOT_KERNEL_SECTOR      2048

/* Default kernel load address (physical) */
#define BOOT_KERNEL_LOAD_ADDR   0x00100000

/* Sector size in bytes */
#define BOOT_SECTOR_SIZE        512

/*
 * Boot header structure -- 32 bytes at the start of sector 0.
 *
 * Fits within the MBR bootstrap code area (bytes 0-445). The MBR
 * partition table starts at byte 446, so there is no conflict.
 *
 * The boot ROM reads this header to determine where the kernel is
 * on disk and where to load it in memory.
 */
typedef struct {
    uint32_t magic;                 /* BOOT_HEADER_MAGIC ("M65B") */
    uint32_t version;               /* Header version (currently 1) */
    uint32_t kernel_sector;         /* Kernel start sector on disk */
    uint32_t kernel_size;           /* Kernel size in bytes */
    uint32_t kernel_load_addr;      /* Physical RAM address to load kernel */
    uint32_t kernel_entry_offset;   /* Entry offset from load addr (usually 0) */
    uint32_t flags;                 /* Reserved flags */
    uint32_t reserved;              /* Reserved for future use */
} boot_header_t;

#ifdef __cplusplus
}
#endif

#endif /* BOOT_HEADER_H */
