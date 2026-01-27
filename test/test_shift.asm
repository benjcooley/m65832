; Test shifts
    .org $1000
    
    LDA #$40
    ASL A           ; 0x80
    LSR A           ; 0x40
    LSR A           ; 0x20
    STP
