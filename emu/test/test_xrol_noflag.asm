; XROL: flagless ROL A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, C=1 (CMP sets C when A >= operand)
    LDA #$40000000
    XROL A                ; A = $80000000 (pure rotate, no carry-in); flags must NOT change
    STP
