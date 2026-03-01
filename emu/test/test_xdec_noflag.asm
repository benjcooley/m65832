; XDEC: flagless DEC A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000001
    CMP #$00000001        ; Z=1, C=1
    LDA #$00000001
    XDEC A                ; A = $00000000; Z must remain (from CMP), not re-evaluated
    STP
