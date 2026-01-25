; Test AND/ORA/EOR
    .org $1000
    
    LDA #$FF
    AND #$0F        ; 0x0F
    ORA #$A0        ; 0xAF
    EOR #$FF        ; 0x50
    STP
