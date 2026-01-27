; Basic 65816/16-bit mode assembly
    .org $8000
    .M16
    .X16

    LDA #$1234
    LDX #$5678
    LDY #$9ABC
    STA $1234
    STX $1234
    STY $1234
