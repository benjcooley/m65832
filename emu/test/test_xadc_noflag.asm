; XADC: flagless ADC - result correct, flags unchanged
    .org $1000
    .M32

    CLC
    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0, C=1
    CLC                   ; C=0 (needed for ADC), Z still from CMP
    XADC #$00000005       ; A = 0 + 5 = 5; flags must NOT change
    STP
