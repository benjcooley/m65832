; XORA: flagless ORA - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1
    LDA #$00FF0000
    XORA #$000000FF       ; A = $00FF00FF; Z must remain set
    STP
