; TYX should NOT modify flags in 32-bit mode
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0
    LDY #$CAFEBABE
    TYX                   ; X = Y; flags must NOT change
    STP
