; TXA MUST set N flag in 16-bit mode (65816 compat)
    .org $1000
    .M32

    ; Switch to 65816 native 16-bit mode
    REPE #$02             ; Clear W1 -> W=00
    SEPE #$01             ; Set W0 -> W=01 (65816 native)
    REP #$30              ; M=0, X=0 -> 16-bit A and X/Y
    .M16
    .X16

    LDA #$0000
    CMP #$0000            ; Z=1, N=0
    LDX #$8000            ; X = negative (16-bit)
    TXA                   ; A = X; should set N, clear Z
    STP
