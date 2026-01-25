; Test include files

    .ORG $3000

; Include common definitions
    .INCLUDE "inc/macros.inc"
    .INCLUDE "inc/vectors.inc"

    .M16
    .X16

START:
    ; Test that included constants work
    LDA #SYS_WRITE      ; Should be $01
    LDA #UART_TX_READY  ; Should be $01
    
    LDA #<VEC_RESET     ; Low byte of reset vector
    LDA #>VEC_RESET     ; High byte
    
    ; Use UART constants
    LDA UART_STATUS
    AND #UART_TX_READY
    BEQ START
    
    STA UART_DATA
    
    RTS
