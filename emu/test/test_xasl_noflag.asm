; XASL: flagless ASL A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1, C=1
    LDA #$40000000
    XASL A                ; A = $80000000; C must NOT be modified, N must NOT be set
    STP
