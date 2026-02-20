; Test TSPB (SP to B)
    .org $1000
    .M32
    
    LDX #$0000ABCD   ; Set up stack pointer
    TXS              ; SP = X
    TSPB             ; B = SP ($0000ABCD)
    TBA              ; A = B (to verify)
    STP
