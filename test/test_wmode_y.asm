; W_mode: LDY should also be 32-bit (X width forced)
    .org $1000
    .M32

    LDY #$DEADBEEF   ; 32-bit Y load
    TYA              ; A = Y
    STP
