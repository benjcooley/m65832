; Switch from 32-bit to 16-bit accumulator via REP/SEP
    .org $1000
    .M32

    ; Start in 32-bit mode (M = "10")
    ; To get 16-bit (M = "01"), clear M1 and set M0
    REP #$80        ; Clear M1
    SEP #$40        ; Set M0 -> M = "01" (16-bit)
    .M16            ; Tell assembler
    LDA #$1234      ; 16-bit immediate load
    STP
