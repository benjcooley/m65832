; test_echo.asm - Minimal UART echo test
; Uses B register for I/O addressing
;
; Build: ../../as/m65832as test_echo.asm -o test_echo.bin
; Run:   echo "helloq" | ../m65832emu --system -o 0x1000 test_echo.bin

        .org $00100000      ; System mode kernel load address
        .m8

; UART register offsets (relative to B base)
UART_STATUS = $100      ; B + $100 = $00FFF100
UART_TX     = $104      ; B + $104 = $00FFF104
UART_RX     = $108      ; B + $108 = $00FFF108
TX_READY    = $01
RX_AVAIL    = $02

; I/O base address
IO_BASE     = $00FFF000

start:
        ; Set B register to I/O base
        SB #IO_BASE

main_loop:
        ; Wait for RX data available
rx_wait:
        LDA UART_STATUS     ; B + $100
        AND #RX_AVAIL
        BEQ rx_wait
        
        ; Read character
        LDA UART_RX         ; B + $108
        
        ; Check for 'q' to quit
        CMP #'q'
        BEQ quit
        
        ; Wait for TX ready
tx_wait:
        PHA
        LDA UART_STATUS
        AND #TX_READY
        BEQ tx_wait
        PLA
        
        ; Send character
        STA UART_TX         ; B + $104
        
        ; Loop back
        BRA main_loop

quit:
        ; Print newline before exit
        LDA #$0A
        STA UART_TX
        STP

        .end
