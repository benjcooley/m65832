; Test ADC
    .org $1000
    
    CLC
    LDA #$10
    ADC #$20        ; 0x10 + 0x20 = 0x30
    STP
