; Test FCMP does not update flags
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    I2F.S F0          ; F0 = 0.0
    I2F.S F1          ; F1 = 0.0
    FCMP.S F0, F1     ; should not modify flags
    STP
