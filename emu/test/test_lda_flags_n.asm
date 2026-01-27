; Test LDA flags in 32-bit mode (N should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000001    ; sets N=1 (A - 1 = 0xFFFFFFFF)
    LDA #$00000000    ; should not clear N in 32-bit mode
    STP
