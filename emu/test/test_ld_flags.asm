; Test extended LD flags in 32-bit mode (Z should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    LD R0, #$00000001 ; extended load should not clear Z
    STP
