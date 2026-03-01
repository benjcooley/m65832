; XADC must not set N even on negative result
    .org $1000
    .M32

    LDA #$00000001
    CMP #$00000001        ; Z=1, N=0, C=1
    SEC                   ; C=1 for known state
    XADC #$7FFFFFFF       ; A = 1 + $7FFFFFFF + 1 = $80000001; N must NOT be set
    STP
