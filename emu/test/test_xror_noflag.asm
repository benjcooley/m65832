; XROR: flagless ROR A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, C=1
    LDA #$00000002
    XROR A                ; A = $80000001 (C was 1, rotated in to MSB); C must NOT change
    STP
