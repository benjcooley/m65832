/* hw.h - M65832 Hardware Register Definitions
 *
 * Pure hardware definitions, no LLVM dependencies.
 * Used by platform I/O code.
 */

#ifndef M65832_PLATFORM_HW_H
#define M65832_PLATFORM_HW_H

#include <stdint.h>

/* ============================================================================
 * MMIO Access Macros
 * ========================================================================= */

#define MMIO_READ8(addr)        (*(volatile uint8_t *)(addr))
#define MMIO_WRITE8(addr, val)  (*(volatile uint8_t *)(addr) = (val))
#define MMIO_READ32(addr)       (*(volatile uint32_t *)(addr))
#define MMIO_WRITE32(addr, val) (*(volatile uint32_t *)(addr) = (val))

/* ============================================================================
 * UART Registers (0x00FFF100)
 * ========================================================================= */

#define UART_BASE         0x00FFF100
#define UART_STATUS       0x00FFF100
#define UART_TX_DATA      0x00FFF104
#define UART_RX_DATA      0x00FFF108
#define UART_CTRL         0x00FFF10C

#define UART_STATUS_TX_READY    0x01
#define UART_STATUS_RX_AVAIL    0x02
#define UART_STATUS_TX_BUSY     0x04
#define UART_STATUS_RX_OVERRUN  0x08

#define UART_CTRL_RX_IRQ_EN     0x01
#define UART_CTRL_TX_IRQ_EN     0x02

/* ============================================================================
 * Block Device Registers (0x00FFF120)
 * ========================================================================= */

#define BLKDEV_BASE       0x00FFF120
#define BLKDEV_STATUS     0x00FFF120
#define BLKDEV_COMMAND    0x00FFF124
#define BLKDEV_SECTOR_LO  0x00FFF128
#define BLKDEV_SECTOR_HI  0x00FFF12C
#define BLKDEV_DMA_ADDR   0x00FFF130
#define BLKDEV_COUNT      0x00FFF134
#define BLKDEV_CAPACITY_LO 0x00FFF138
#define BLKDEV_CAPACITY_HI 0x00FFF13C

#define BLKDEV_SECTOR_SIZE 512

#define BLKDEV_STATUS_READY     0x01
#define BLKDEV_STATUS_BUSY      0x02
#define BLKDEV_STATUS_ERROR     0x04
#define BLKDEV_STATUS_DRQ       0x08
#define BLKDEV_STATUS_PRESENT   0x10
#define BLKDEV_STATUS_WRITABLE  0x20
#define BLKDEV_STATUS_IRQ       0x40

#define BLKDEV_CMD_NOP          0x00
#define BLKDEV_CMD_READ         0x01
#define BLKDEV_CMD_WRITE        0x02
#define BLKDEV_CMD_FLUSH        0x03
#define BLKDEV_CMD_RESET        0x05
#define BLKDEV_CMD_ACK_IRQ      0x06

/* ============================================================================
 * Timer Registers (0x00FFF040)
 * ========================================================================= */

#define TIMER_CTRL        0x00FFF040
#define TIMER_CMP         0x00FFF044
#define TIMER_CNT         0x00FFF048

#define TIMER_ENABLE      0x01
#define TIMER_AUTORESET   0x02
#define TIMER_IRQ_ENABLE  0x04
#define TIMER_IRQ_CLEAR   0x08
#define TIMER_IRQ_PENDING 0x80

#endif /* M65832_PLATFORM_HW_H */
