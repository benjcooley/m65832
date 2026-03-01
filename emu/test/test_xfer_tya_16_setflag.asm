; TYA MUST set N flag in 16-bit mode
    .org $1000
    .M32

    REPE #$02
    SEPE #$01
    REP #$30
    .M16
    .X16

    LDA #$0000
    CMP #$0000            ; Z=1, N=0
    LDY #$FFFF            ; Y = negative (16-bit)
    TYA                   ; A = Y; should set N, clear Z
    STP
