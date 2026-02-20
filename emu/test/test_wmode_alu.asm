; W_mode: ALU operations should use 32-bit width
    .org $1000
    .M32

    CLC
    LDA #$0000FFFF
    ADC #$00000001   ; Should produce $00010000 (32-bit carry propagation)
    STP
