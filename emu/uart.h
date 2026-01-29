/*
 * uart.h - M65832 UART Device Emulation
 *
 * Simple UART device connected to host terminal.
 * Provides serial I/O for console access.
 *
 * Register layout matches platform headers and Linux platform.h
 */

#ifndef UART_H
#define UART_H

#include "m65832emu.h"
#include "platform.h"
#include "platform_de25.h"      /* Default register definitions */
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * UART Register Definitions
 *
 * Base address comes from platform config (e.g., DE25_UART_BASE = 0x10006000)
 * Register offsets:
 *   DE25_UART_DATA   = 0x00  (TX/RX data)
 *   DE25_UART_STATUS = 0x04  (Status)
 *   DE25_UART_CTRL   = 0x08  (Control)
 *   DE25_UART_BAUD   = 0x0C  (Baud divisor)
 * ========================================================================= */

/* UART region size (4 KB) */
#define UART_SIZE               DE25_PERIPH_SIZE

/* Register offsets (use DE25 as canonical) */
#define UART_DATA               DE25_UART_DATA
#define UART_STATUS             DE25_UART_STATUS
#define UART_CTRL               DE25_UART_CTRL
#define UART_BAUD               DE25_UART_BAUD

/* Status register bits */
#define UART_STATUS_RX_AVAIL    DE25_UART_STATUS_RXRDY
#define UART_STATUS_TX_READY    DE25_UART_STATUS_TXRDY
#define UART_STATUS_TX_BUSY     DE25_UART_STATUS_TXBUSY
#define UART_STATUS_RX_OVERRUN  DE25_UART_STATUS_RXERR

/* Control register bits */
#define UART_CTRL_RX_IRQ_EN     DE25_UART_CTRL_RXIE
#define UART_CTRL_TX_IRQ_EN     DE25_UART_CTRL_TXIE
#define UART_CTRL_ENABLE        DE25_UART_CTRL_ENABLE
#define UART_CTRL_LOOPBACK      DE25_UART_CTRL_LOOPBACK

/* ============================================================================
 * UART State
 * ========================================================================= */

typedef struct uart_state {
    /* Receive buffer (simple single-byte buffer) */
    uint8_t rx_data;
    bool    rx_avail;
    bool    rx_overrun;
    
    /* Control */
    uint8_t ctrl;
    
    /* Configuration */
    uint32_t base_addr;         /* MMIO base address (from platform) */
    bool    loopback;           /* Loopback mode for testing */
    bool    raw_mode;           /* Terminal in raw mode */
    
    /* CPU reference for IRQ */
    m65832_cpu_t *cpu;
    
    /* MMIO region index */
    int mmio_index;
} uart_state_t;

/* ============================================================================
 * UART API
 * ========================================================================= */

/*
 * Initialize UART device and register with CPU at platform-specific address.
 *
 * @param cpu       CPU instance to attach to
 * @param platform  Platform configuration (determines base address)
 * @return          UART state, or NULL on error
 */
uart_state_t *uart_init(m65832_cpu_t *cpu, const platform_config_t *platform);

/*
 * Destroy UART device and unregister from CPU.
 *
 * @param uart      UART state
 */
void uart_destroy(uart_state_t *uart);

/*
 * Check for and process pending input from host terminal.
 * Should be called periodically (e.g., once per instruction batch).
 *
 * @param uart      UART state
 */
void uart_poll(uart_state_t *uart);

/*
 * Inject a character into the UART receive buffer.
 * Used for testing or scripted input.
 *
 * @param uart      UART state
 * @param c         Character to inject
 */
void uart_inject_char(uart_state_t *uart, uint8_t c);

/*
 * Enable/disable raw terminal mode.
 * In raw mode, input is not line-buffered.
 *
 * @param uart      UART state
 * @param enable    true to enable raw mode
 */
void uart_set_raw_mode(uart_state_t *uart, bool enable);

/*
 * Check if RX interrupt should be triggered.
 *
 * @param uart      UART state
 * @return          true if IRQ should be asserted
 */
bool uart_irq_pending(uart_state_t *uart);

#ifdef __cplusplus
}
#endif

#endif /* UART_H */
