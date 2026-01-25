; Test INC/DEC
    .org $1000
    
    LDA #$10
    INC A           ; 0x11
    INC A           ; 0x12
    DEC A           ; 0x11
    STP
