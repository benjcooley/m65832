; XEOR: flagless EOR - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1
    LDA #$AAAAAAAA
    XEOR #$55555555       ; A = $FFFFFFFF; Z must remain, N must NOT be set
    STP
