; XSBC: flagless SBC - result correct, flags unchanged
    .org $1000
    .M32

    SEC
    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0, C=1
    LDA #$00000050
    XSBC #$00000020       ; A = $50 - $20 = $30; flags must NOT change (Z stays from CMP)
    STP
