; Common macros and constants for M65832

; System constants
SYS_WRITE = $01
SYS_READ  = $02
SYS_EXIT  = $60

; UART addresses (relative to B register)
UART_DATA   = $0000
UART_STATUS = $0004
UART_CTRL   = $0008

; Status bits
UART_TX_READY = $01
UART_RX_READY = $02
