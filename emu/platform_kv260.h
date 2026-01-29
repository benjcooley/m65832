/*
 * platform_kv260.h - KV260 Platform Definitions
 *
 * MMIO addresses and register definitions for AMD/Xilinx Kria KV260
 * (Zynq UltraScale+ MPSoC)
 *
 * This file defines the hardware interface that:
 *   - The emulator implements
 *   - The VHDL implements
 *   - Linux drivers use
 *
 * All three MUST match exactly.
 *
 * Note: KV260 has both PS (Processing System - ARM cores) and PL
 * (Programmable Logic). The M65832 runs in PL with its own memory map.
 */

#ifndef PLATFORM_KV260_H
#define PLATFORM_KV260_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Memory Map
 *
 * The KV260's PL gets a portion of DDR allocated by the PS/Linux.
 * We use the same logical memory map as DE25 for software compatibility.
 * ========================================================================= */

#define KV260_BOOT_ROM_BASE     0x00000000
#define KV260_BOOT_ROM_SIZE     0x00010000      /* 64 KB */

#define KV260_RAM_BASE          0x00010000
#define KV260_RAM_SIZE          (256 * 1024 * 1024)  /* 256 MB allocated to PL */

/* ============================================================================
 * Peripheral Base Addresses
 *
 * Same addresses as DE25 for software compatibility.
 * The difference is clock speeds and available features.
 * ========================================================================= */

#define KV260_PERIPH_BASE       0x10000000

#define KV260_GPU_BASE          0x10000000
#define KV260_DMA_BASE          0x10001000
#define KV260_AUDIO_BASE        0x10002000
#define KV260_VIDEO_BASE        0x10003000
#define KV260_TIMER_BASE        0x10004000
#define KV260_INTC_BASE         0x10005000
#define KV260_UART_BASE         0x10006000
#define KV260_SPI_BASE          0x10007000
#define KV260_I2C_BASE          0x10008000
#define KV260_GPIO_BASE         0x10009000
#define KV260_SD_BASE           0x1000A000

#define KV260_PERIPH_SIZE       0x1000          /* 4 KB per peripheral */

/* ============================================================================
 * System Registers (bypass MMU)
 * ========================================================================= */

#define KV260_SYSREG_BASE       0xFFFFF000

#define KV260_MMUCR             0xFFFFF000
#define KV260_TLBINVAL          0xFFFFF004
#define KV260_ASID              0xFFFFF008
#define KV260_ASIDINVAL         0xFFFFF00C
#define KV260_FAULTVA           0xFFFFF010
#define KV260_PTBR_LO           0xFFFFF014
#define KV260_PTBR_HI           0xFFFFF018
#define KV260_TLBFLUSH          0xFFFFF01C

/* System timer */
#define KV260_SYSTIMER_CTRL     0xFFFFF040
#define KV260_SYSTIMER_CMP      0xFFFFF044
#define KV260_SYSTIMER_COUNT    0xFFFFF048

/* ============================================================================
 * Clock Frequencies
 *
 * KV260 can run faster than DE25 due to better FPGA fabric.
 * ========================================================================= */

#define KV260_CPU_FREQ          100000000       /* 100 MHz PL clock */
#define KV260_TIMER_FREQ        100000000
#define KV260_UART_FREQ         100000000

/* ============================================================================
 * UART Registers (at KV260_UART_BASE)
 *
 * Same register layout as DE25.
 * ========================================================================= */

#define KV260_UART_DATA         0x00
#define KV260_UART_STATUS       0x04
#define KV260_UART_CTRL         0x08
#define KV260_UART_BAUD         0x0C

/* Status bits - same as DE25 */
#define KV260_UART_STATUS_RXRDY     (1 << 0)
#define KV260_UART_STATUS_TXRDY     (1 << 1)
#define KV260_UART_STATUS_RXFULL    (1 << 2)
#define KV260_UART_STATUS_TXEMPTY   (1 << 3)
#define KV260_UART_STATUS_RXERR     (1 << 4)
#define KV260_UART_STATUS_TXBUSY    (1 << 5)

/* Control bits - same as DE25 */
#define KV260_UART_CTRL_RXIE        (1 << 0)
#define KV260_UART_CTRL_TXIE        (1 << 1)
#define KV260_UART_CTRL_ENABLE      (1 << 2)
#define KV260_UART_CTRL_LOOPBACK    (1 << 3)

/* ============================================================================
 * Interrupt Controller Registers (at KV260_INTC_BASE)
 * ========================================================================= */

#define KV260_INTC_STATUS       0x00
#define KV260_INTC_ENABLE       0x04
#define KV260_INTC_PENDING      0x08
#define KV260_INTC_CLEAR        0x0C
#define KV260_INTC_PRIORITY     0x10

/* IRQ numbers - same as DE25 */
#define KV260_IRQ_GPU_FRAME     0
#define KV260_IRQ_GPU_CMDBUF    1
#define KV260_IRQ_DMA           2
#define KV260_IRQ_AUDIO         3
#define KV260_IRQ_VSYNC         4
#define KV260_IRQ_TIMER0        5
#define KV260_IRQ_TIMER1        6
#define KV260_IRQ_UART          7
#define KV260_IRQ_SPI           8
#define KV260_IRQ_I2C           9
#define KV260_IRQ_GPIO          10
#define KV260_IRQ_SD            11

/* ============================================================================
 * SD Card Controller Registers (at KV260_SD_BASE)
 * ========================================================================= */

#define KV260_SD_CTRL           0x00
#define KV260_SD_STATUS         0x04
#define KV260_SD_CMD            0x08
#define KV260_SD_ARG            0x0C
#define KV260_SD_RESP0          0x10
#define KV260_SD_RESP1          0x14
#define KV260_SD_RESP2          0x18
#define KV260_SD_RESP3          0x1C
#define KV260_SD_DATA           0x20
#define KV260_SD_BLKSIZE        0x24
#define KV260_SD_BLKCNT         0x28
#define KV260_SD_TIMEOUT        0x2C
#define KV260_SD_CLKDIV         0x30
#define KV260_SD_FIFOCNT        0x34
#define KV260_SD_DMA_ADDR       0x38
#define KV260_SD_DMA_CTRL       0x3C

/* SD Control bits - same as DE25 */
#define KV260_SD_CTRL_ENABLE        (1 << 0)
#define KV260_SD_CTRL_CARD_SEL      (1 << 1)
#define KV260_SD_CTRL_START_CMD     (1 << 2)
#define KV260_SD_CTRL_START_RD      (1 << 3)
#define KV260_SD_CTRL_START_WR      (1 << 4)
#define KV260_SD_CTRL_ABORT         (1 << 5)
#define KV260_SD_CTRL_RESET_FIFO    (1 << 6)
#define KV260_SD_CTRL_IRQ_EN        (1 << 7)
#define KV260_SD_CTRL_DMA_EN        (1 << 8)

/* SD Status bits - same as DE25 */
#define KV260_SD_STATUS_PRESENT     (1 << 0)
#define KV260_SD_STATUS_READY       (1 << 1)
#define KV260_SD_STATUS_BUSY        (1 << 2)
#define KV260_SD_STATUS_ERROR       (1 << 3)
#define KV260_SD_STATUS_CRC_ERR     (1 << 4)
#define KV260_SD_STATUS_TIMEOUT     (1 << 5)
#define KV260_SD_STATUS_CMD_ERR     (1 << 6)
#define KV260_SD_STATUS_FIFO_ERR    (1 << 7)
#define KV260_SD_STATUS_COMPLETE    (1 << 8)

/* ============================================================================
 * Timer Registers (at KV260_SYSTIMER_CTRL)
 * ========================================================================= */

#define KV260_TIMER_CTRL        0x00
#define KV260_TIMER_CMP         0x04
#define KV260_TIMER_COUNT       0x08

/* Timer control bits - same as DE25 */
#define KV260_TIMER_CTRL_EN         (1 << 0)
#define KV260_TIMER_CTRL_IE         (1 << 1)
#define KV260_TIMER_CTRL_IF         (1 << 2)
#define KV260_TIMER_CTRL_PERIODIC   (1 << 3)

#ifdef __cplusplus
}
#endif

#endif /* PLATFORM_KV260_H */
