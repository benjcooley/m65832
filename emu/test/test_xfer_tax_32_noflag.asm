; TAX should NOT modify flags in 32-bit mode
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0
    LDA #$80000000        ; A = negative value
    TAX                   ; X = A; flags must NOT change
    STP
