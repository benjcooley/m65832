; Test SBC
    .org $1000
    
    SEC
    LDA #$50
    SBC #$20        ; 0x50 - 0x20 = 0x30
    STP
