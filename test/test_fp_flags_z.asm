; Test FPU ops preserve Z flag
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    I2F.S F0          ; F0 = 0.0
    FADD.S F0, F0     ; F0 = 0.0
    STP
