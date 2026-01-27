; Basic 6502/8-bit mode assembly
    .org $8000
    .M8
    .X8

    LDA #$7F
    LDX #$80
    LDY #$01
    STA $20
    STX $21
    STY $22
    SEP #$30
    REP #$10
    NOP
