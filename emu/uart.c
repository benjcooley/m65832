/*
 * uart.c - M65832 UART Device Emulation
 *
 * Simple UART device connected to host terminal via stdin/stdout.
 */

#include "uart.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/select.h>

/* ============================================================================
 * Terminal Mode Management
 * ========================================================================= */

static struct termios g_orig_termios;
static bool g_termios_saved = false;

static void restore_terminal(void) {
    if (g_termios_saved) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
        g_termios_saved = false;
    }
}

static void set_terminal_raw(bool enable) {
    if (enable) {
        if (!g_termios_saved) {
            if (tcgetattr(STDIN_FILENO, &g_orig_termios) == 0) {
                g_termios_saved = true;
                atexit(restore_terminal);
            }
        }
        
        struct termios raw = g_orig_termios;
        /* Disable canonical mode and echo */
        raw.c_lflag &= ~(ICANON | ECHO | ISIG);
        /* Disable input processing */
        raw.c_iflag &= ~(IXON | ICRNL | BRKINT | INPCK | ISTRIP);
        /* Set 8-bit characters */
        raw.c_cflag |= CS8;
        /* Minimum 0 chars, no timeout */
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 0;
        
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    } else {
        restore_terminal();
    }
}

/* ============================================================================
 * Non-blocking stdin check
 * ========================================================================= */

static int stdin_available(void) {
    fd_set fds;
    struct timeval tv = {0, 0};  /* No wait */
    
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    
    return select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0;
}

/* ============================================================================
 * MMIO Handlers
 * ========================================================================= */

static uint32_t uart_mmio_read(m65832_cpu_t *cpu, uint32_t addr,
                                uint32_t offset, int width, void *user) {
    (void)cpu;
    (void)addr;
    (void)width;
    
    uart_state_t *uart = (uart_state_t *)user;
    uint32_t value = 0;
    
    switch (offset) {
        case UART_STATUS:
            /* Build status register */
            value = UART_STATUS_TX_READY;  /* TX always ready */
            if (uart->rx_avail) {
                value |= UART_STATUS_RX_AVAIL;
            }
            if (uart->rx_overrun) {
                value |= UART_STATUS_RX_OVERRUN;
            }
            break;
            
        case UART_RX_DATA:
            /* Return received byte and clear flags */
            value = uart->rx_data;
            uart->rx_avail = false;
            uart->rx_overrun = false;
            break;
            
        case UART_CTRL:
            value = uart->ctrl;
            break;
            
        case UART_TX_DATA:
            /* TX register is write-only, return 0 */
            value = 0;
            break;
            
        default:
            /* Unmapped register */
            value = 0;
            break;
    }
    
    return value;
}

static void uart_mmio_write(m65832_cpu_t *cpu, uint32_t addr,
                             uint32_t offset, uint32_t value,
                             int width, void *user) {
    (void)cpu;
    (void)addr;
    (void)width;
    
    uart_state_t *uart = (uart_state_t *)user;
    
    switch (offset) {
        case UART_TX_DATA:
            /* Transmit byte to stdout */
            if (uart->loopback) {
                /* Loopback mode: send to RX */
                uart_inject_char(uart, (uint8_t)value);
            } else {
                /* Normal mode: send to terminal */
                putchar((int)(value & 0xFF));
                fflush(stdout);
            }
            break;
            
        case UART_CTRL:
            uart->ctrl = (uint8_t)value;
            uart->loopback = (value & UART_CTRL_LOOPBACK) != 0;
            break;
            
        case UART_STATUS:
        case UART_RX_DATA:
            /* Read-only registers, ignore writes */
            break;
            
        default:
            /* Unmapped register */
            break;
    }
}

/* ============================================================================
 * Public API
 * ========================================================================= */

uart_state_t *uart_init(m65832_cpu_t *cpu) {
    if (!cpu) return NULL;
    
    uart_state_t *uart = calloc(1, sizeof(uart_state_t));
    if (!uart) return NULL;
    
    uart->cpu = cpu;
    uart->rx_avail = false;
    uart->rx_overrun = false;
    uart->ctrl = 0;
    uart->loopback = false;
    uart->raw_mode = false;
    
    /* Register MMIO region */
    uart->mmio_index = m65832_mmio_register(
        cpu,
        UART_BASE,
        UART_SIZE,
        uart_mmio_read,
        uart_mmio_write,
        uart,
        "UART"
    );
    
    if (uart->mmio_index < 0) {
        free(uart);
        return NULL;
    }
    
    return uart;
}

void uart_destroy(uart_state_t *uart) {
    if (!uart) return;
    
    /* Restore terminal mode */
    if (uart->raw_mode) {
        set_terminal_raw(false);
    }
    
    /* Unregister MMIO */
    if (uart->cpu && uart->mmio_index >= 0) {
        m65832_mmio_unregister(uart->cpu, uart->mmio_index);
    }
    
    free(uart);
}

void uart_poll(uart_state_t *uart) {
    if (!uart || uart->loopback) return;
    
    /* Check if input is available and we have room */
    if (!uart->rx_avail && stdin_available()) {
        int c = getchar();
        if (c != EOF) {
            uart->rx_data = (uint8_t)c;
            uart->rx_avail = true;
        }
    } else if (uart->rx_avail && stdin_available()) {
        /* Input available but buffer full - overrun */
        uart->rx_overrun = true;
        /* Discard the character */
        (void)getchar();
    }
}

void uart_inject_char(uart_state_t *uart, uint8_t c) {
    if (!uart) return;
    
    if (uart->rx_avail) {
        /* Buffer already has data - overrun */
        uart->rx_overrun = true;
    }
    
    uart->rx_data = c;
    uart->rx_avail = true;
}

void uart_set_raw_mode(uart_state_t *uart, bool enable) {
    if (!uart) return;
    
    if (enable != uart->raw_mode) {
        set_terminal_raw(enable);
        uart->raw_mode = enable;
    }
}

bool uart_irq_pending(uart_state_t *uart) {
    if (!uart) return false;
    
    /* RX IRQ enabled and data available? */
    if ((uart->ctrl & UART_CTRL_RX_IRQ_EN) && uart->rx_avail) {
        return true;
    }
    
    return false;
}
