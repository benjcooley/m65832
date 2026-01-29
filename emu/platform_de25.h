/*
 * platform_de25.h - DE2-115 Platform Definitions
 *
 * MMIO addresses and register definitions for Terasic DE2-115
 * (Altera/Intel Cyclone IV EP4CE115F29C7)
 *
 * This file defines the hardware interface that:
 *   - The emulator implements
 *   - The VHDL implements
 *   - Linux drivers use
 *
 * All three MUST match exactly.
 */

#ifndef PLATFORM_DE25_H
#define PLATFORM_DE25_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Memory Map
 * ========================================================================= */

#define DE25_BOOT_ROM_BASE      0x00000000
#define DE25_BOOT_ROM_SIZE      0x00010000      /* 64 KB */

#define DE25_RAM_BASE           0x00010000
#define DE25_RAM_SIZE           (128 * 1024 * 1024)  /* 128 MB SDRAM */

/* ============================================================================
 * Peripheral Base Addresses
 * ========================================================================= */

#define DE25_PERIPH_BASE        0x10000000

#define DE25_GPU_BASE           0x10000000
#define DE25_DMA_BASE           0x10001000
#define DE25_AUDIO_BASE         0x10002000
#define DE25_VIDEO_BASE         0x10003000
#define DE25_TIMER_BASE         0x10004000
#define DE25_INTC_BASE          0x10005000
#define DE25_UART_BASE          0x10006000
#define DE25_SPI_BASE           0x10007000
#define DE25_I2C_BASE           0x10008000
#define DE25_GPIO_BASE          0x10009000
#define DE25_SD_BASE            0x1000A000

#define DE25_PERIPH_SIZE        0x1000          /* 4 KB per peripheral */

/* ============================================================================
 * System Registers (bypass MMU)
 * ========================================================================= */

#define DE25_SYSREG_BASE        0xFFFFF000

#define DE25_MMUCR              0xFFFFF000
#define DE25_TLBINVAL           0xFFFFF004
#define DE25_ASID               0xFFFFF008
#define DE25_ASIDINVAL          0xFFFFF00C
#define DE25_FAULTVA            0xFFFFF010
#define DE25_PTBR_LO            0xFFFFF014
#define DE25_PTBR_HI            0xFFFFF018
#define DE25_TLBFLUSH           0xFFFFF01C

/* System timer */
#define DE25_SYSTIMER_CTRL      0xFFFFF040
#define DE25_SYSTIMER_CMP       0xFFFFF044
#define DE25_SYSTIMER_COUNT     0xFFFFF048

/* ============================================================================
 * Clock Frequencies
 * ========================================================================= */

#define DE25_CPU_FREQ           50000000        /* 50 MHz */
#define DE25_TIMER_FREQ         50000000
#define DE25_UART_FREQ          50000000

/* ============================================================================
 * UART Registers (at DE25_UART_BASE)
 * ========================================================================= */

#define DE25_UART_DATA          0x00    /* TX/RX data register */
#define DE25_UART_STATUS        0x04    /* Status register */
#define DE25_UART_CTRL          0x08    /* Control register */
#define DE25_UART_BAUD          0x0C    /* Baud rate divisor */

/* Status bits */
#define DE25_UART_STATUS_RXRDY      (1 << 0)
#define DE25_UART_STATUS_TXRDY      (1 << 1)
#define DE25_UART_STATUS_RXFULL     (1 << 2)
#define DE25_UART_STATUS_TXEMPTY    (1 << 3)
#define DE25_UART_STATUS_RXERR      (1 << 4)
#define DE25_UART_STATUS_TXBUSY     (1 << 5)

/* Control bits */
#define DE25_UART_CTRL_RXIE         (1 << 0)
#define DE25_UART_CTRL_TXIE         (1 << 1)
#define DE25_UART_CTRL_ENABLE       (1 << 2)
#define DE25_UART_CTRL_LOOPBACK     (1 << 3)

/* ============================================================================
 * Interrupt Controller Registers (at DE25_INTC_BASE)
 * ========================================================================= */

#define DE25_INTC_STATUS        0x00
#define DE25_INTC_ENABLE        0x04
#define DE25_INTC_PENDING       0x08
#define DE25_INTC_CLEAR         0x0C
#define DE25_INTC_PRIORITY      0x10

/* IRQ numbers */
#define DE25_IRQ_GPU_FRAME      0
#define DE25_IRQ_GPU_CMDBUF     1
#define DE25_IRQ_DMA            2
#define DE25_IRQ_AUDIO          3
#define DE25_IRQ_VSYNC          4
#define DE25_IRQ_TIMER0         5
#define DE25_IRQ_TIMER1         6
#define DE25_IRQ_UART           7
#define DE25_IRQ_SPI            8
#define DE25_IRQ_I2C            9
#define DE25_IRQ_GPIO           10
#define DE25_IRQ_SD             11

/* ============================================================================
 * SD Card Controller Registers (at DE25_SD_BASE)
 * ========================================================================= */

#define DE25_SD_CTRL            0x00
#define DE25_SD_STATUS          0x04
#define DE25_SD_CMD             0x08
#define DE25_SD_ARG             0x0C
#define DE25_SD_RESP0           0x10
#define DE25_SD_RESP1           0x14
#define DE25_SD_RESP2           0x18
#define DE25_SD_RESP3           0x1C
#define DE25_SD_DATA            0x20
#define DE25_SD_BLKSIZE         0x24
#define DE25_SD_BLKCNT          0x28
#define DE25_SD_TIMEOUT         0x2C
#define DE25_SD_CLKDIV          0x30
#define DE25_SD_FIFOCNT         0x34
#define DE25_SD_DMA_ADDR        0x38
#define DE25_SD_DMA_CTRL        0x3C

/* SD Control bits */
#define DE25_SD_CTRL_ENABLE         (1 << 0)
#define DE25_SD_CTRL_CARD_SEL       (1 << 1)
#define DE25_SD_CTRL_START_CMD      (1 << 2)
#define DE25_SD_CTRL_START_RD       (1 << 3)
#define DE25_SD_CTRL_START_WR       (1 << 4)
#define DE25_SD_CTRL_ABORT          (1 << 5)
#define DE25_SD_CTRL_RESET_FIFO     (1 << 6)
#define DE25_SD_CTRL_IRQ_EN         (1 << 7)
#define DE25_SD_CTRL_DMA_EN         (1 << 8)

/* SD Status bits */
#define DE25_SD_STATUS_PRESENT      (1 << 0)
#define DE25_SD_STATUS_READY        (1 << 1)
#define DE25_SD_STATUS_BUSY         (1 << 2)
#define DE25_SD_STATUS_ERROR        (1 << 3)
#define DE25_SD_STATUS_CRC_ERR      (1 << 4)
#define DE25_SD_STATUS_TIMEOUT      (1 << 5)
#define DE25_SD_STATUS_CMD_ERR      (1 << 6)
#define DE25_SD_STATUS_FIFO_ERR     (1 << 7)
#define DE25_SD_STATUS_COMPLETE     (1 << 8)

/* ============================================================================
 * Timer Registers (at DE25_SYSTIMER_CTRL)
 * ========================================================================= */

#define DE25_TIMER_CTRL         0x00
#define DE25_TIMER_CMP          0x04
#define DE25_TIMER_COUNT        0x08

/* Timer control bits */
#define DE25_TIMER_CTRL_EN          (1 << 0)
#define DE25_TIMER_CTRL_IE          (1 << 1)
#define DE25_TIMER_CTRL_IF          (1 << 2)
#define DE25_TIMER_CTRL_PERIODIC    (1 << 3)

#ifdef __cplusplus
}
#endif

#endif /* PLATFORM_DE25_H */
