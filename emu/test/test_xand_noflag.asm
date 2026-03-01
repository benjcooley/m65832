; XAND: flagless AND - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1
    LDA #$FF00FF00
    XAND #$0F0F0F0F       ; A = $0F000F00; Z must remain set
    STP
