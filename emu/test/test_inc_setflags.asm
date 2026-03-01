; Normal INC must still set flags (contrast with XINC)
    .org $1000
    .M32

    LDA #$FFFFFFFF
    INC A                 ; A = $00000000; should set Z, clear N
    STP
