; Test FPU FMOV.S and FSUB.S
    .org $1000
    
    LDA #$0A
    I2F.S F0        ; F0 = 10.0
    FMOV.S F5, F0   ; F5 = F0 = 10.0
    LDA #$03
    I2F.S F1        ; F1 = 3.0
    FSUB.S F5, F1   ; F5 = 10.0 - 3.0 = 7.0
    F2I.S F5        ; A = 7
    STP
