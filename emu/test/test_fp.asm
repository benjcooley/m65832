; Test FPU: I2F, FADD.S, F2I with new two-operand format
    .org $1000
    
    LDA #$02
    I2F.S F0        ; F0 = 2.0
    LDA #$03
    I2F.S F1        ; F1 = 3.0
    FADD.S F0, F1   ; F0 = 2.0 + 3.0 = 5.0
    F2I.S F0        ; A = 5
    STP
