/* uart.c - M65832 UART Platform Implementation
 *
 * Pure hardware UART access, no LLVM dependencies.
 */

#include "uart.h"
#include "hw.h"

void uart_putc(int c) {
    while (!(MMIO_READ32(UART_STATUS) & UART_STATUS_TX_READY)) {
        /* Wait for TX ready */
    }
    MMIO_WRITE32(UART_TX_DATA, (uint32_t)c);
}

int uart_getc(void) {
    while (!(MMIO_READ32(UART_STATUS) & UART_STATUS_RX_AVAIL)) {
        /* Wait for RX available */
    }
    return (int)MMIO_READ32(UART_RX_DATA);
}

int uart_rx_ready(void) {
    return (MMIO_READ32(UART_STATUS) & UART_STATUS_RX_AVAIL) ? 1 : 0;
}

int uart_tx_ready(void) {
    return (MMIO_READ32(UART_STATUS) & UART_STATUS_TX_READY) ? 1 : 0;
}

size_t uart_write(const char *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        uart_putc(buf[i]);
    }
    return len;
}

size_t uart_read(char *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        buf[i] = (char)uart_getc();
    }
    return len;
}
