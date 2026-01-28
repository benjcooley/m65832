/* uart.h - M65832 UART Platform API
 *
 * Pure hardware UART interface, no LLVM dependencies.
 */

#ifndef M65832_PLATFORM_UART_H
#define M65832_PLATFORM_UART_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Write bytes to UART (blocking)
 * Returns number of bytes written */
size_t uart_write(const char *buf, size_t len);

/* Read bytes from UART (blocking)
 * Returns number of bytes read */
size_t uart_read(char *buf, size_t len);

/* Write single character */
void uart_putc(int c);

/* Read single character (blocking) */
int uart_getc(void);

/* Check if data available (non-blocking) */
int uart_rx_ready(void);

/* Check if TX ready */
int uart_tx_ready(void);

#ifdef __cplusplus
}
#endif

#endif /* M65832_PLATFORM_UART_H */
