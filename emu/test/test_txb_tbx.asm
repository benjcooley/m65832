; Test TXB and TBX
    .org $1000
    .M32
    
    LDX #$DEADBEEF   ; Load X with test value
    TXB              ; B = X
    LDX #$00000000   ; Clear X
    TBX              ; X = B (should be $DEADBEEF)
    TXA              ; A = X (to verify)
    STP
