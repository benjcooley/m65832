; 16-bit index in 65816 native mode
    .org $1000
    .M32

    ; Start in 32-bit mode (W=11). Switch to 65816 native (W=01).
    REPE #$02       ; Clear W1 -> W=00
    SEPE #$01       ; Set W0 -> W=01 (65816 native)
    REP #$30        ; Clear M and X flags -> M=0 (16-bit A), X=0 (16-bit X/Y)
    .M16
    .X16            ; Tell assembler
    LDX #$ABCD      ; 16-bit X load
    TXA              ; A = X (should be $ABCD in lower 16 bits)
    STP
