/*
 * uart.h - M65832 UART Device Emulation
 *
 * Simple UART device connected to host terminal.
 * Provides serial I/O for console access.
 */

#ifndef UART_H
#define UART_H

#include "m65832emu.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * UART Register Definitions
 * ========================================================================= */

/* UART base address (in MMIO space - 24-bit addressable) */
#define UART_BASE       0x00FFF100

/* UART register offsets */
#define UART_STATUS     0x00    /* Status register (R) */
#define UART_TX_DATA    0x04    /* Transmit data (W) */
#define UART_RX_DATA    0x08    /* Receive data (R) */
#define UART_CTRL       0x0C    /* Control register (R/W) */

/* UART region size */
#define UART_SIZE       0x10

/* Status register bits */
#define UART_STATUS_TX_READY    0x01    /* TX buffer empty, ready to send */
#define UART_STATUS_RX_AVAIL    0x02    /* RX data available */
#define UART_STATUS_TX_BUSY     0x04    /* TX in progress (always 0 for us) */
#define UART_STATUS_RX_OVERRUN  0x08    /* RX buffer overrun */

/* Control register bits */
#define UART_CTRL_RX_IRQ_EN     0x01    /* Enable RX interrupt */
#define UART_CTRL_TX_IRQ_EN     0x02    /* Enable TX interrupt (not used) */
#define UART_CTRL_LOOPBACK      0x04    /* Loopback mode (for testing) */

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
 * Initialize UART device and register with CPU.
 *
 * @param cpu       CPU instance to attach to
 * @return          UART state, or NULL on error
 */
uart_state_t *uart_init(m65832_cpu_t *cpu);

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
