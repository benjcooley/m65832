; XLSR: flagless LSR A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, C=1
    LDA #$00000002
    XLSR A                ; A = $00000001; flags must NOT change
    STP
