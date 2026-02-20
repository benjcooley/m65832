; Switch from 32-bit to 16-bit index via REP/SEP
    .org $1000
    .M32

    ; Start in 32-bit (X = "10"), switch to 16-bit (X = "01")
    REP #$20        ; Clear X1
    SEP #$10        ; Set X0 -> X = "01" (16-bit)
    .X16            ; Tell assembler
    LDX #$ABCD      ; 16-bit X load
    TXA              ; A = X (should be $ABCD in lower 16 bits)
    STP
