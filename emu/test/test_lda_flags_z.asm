; Test LDA flags in 32-bit mode (Z should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    LDA #$00000001    ; should not clear Z in 32-bit mode
    STP
