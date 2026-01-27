; Test stack
    .org $1000
    
    LDA #$11
    PHA
    LDA #$22
    PHA
    LDA #$00        ; Clear A
    PLA             ; Should be $22
    PLA             ; Should be $11
    STP
