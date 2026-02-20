; W_mode: LDX/STX should operate on full 32 bits
    .org $1000
    .M32

    LDX #$11223344   ; 32-bit index load
    TXA              ; A = X (should be full 32-bit value)
    STP
