; TAY should NOT modify flags in 32-bit mode
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0, C=1
    LDA #$FFFFFFFF        ; A = negative (flags unchanged, LDA no flags in 32-bit)
    TAY                   ; Y = A; flags must NOT change
    STP
