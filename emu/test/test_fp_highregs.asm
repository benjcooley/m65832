; Test FPU high registers F8-F15
    .org $1000
    
    LDA #$04
    I2F.S F8        ; F8 = 4.0
    LDA #$02
    I2F.S F15       ; F15 = 2.0
    FMUL.S F8, F15  ; F8 = 4.0 * 2.0 = 8.0
    F2I.S F8        ; A = 8
    STP
