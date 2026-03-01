; TAY MUST set Z flag in 16-bit mode (65816 compat)
    .org $1000
    .M32

    REPE #$02
    SEPE #$01
    REP #$30
    .M16
    .X16

    SEC                   ; C=1 to set known flag state
    LDA #$0000            ; A = 0
    TAY                   ; Y = 0; should set Z
    STP
