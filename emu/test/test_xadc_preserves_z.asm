; XADC must preserve Z flag (not clear it even though result != 0)
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1
    CLC
    XADC #$00000042       ; A = $42, but Z must remain set
    STP
