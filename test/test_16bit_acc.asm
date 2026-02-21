; 16-bit accumulator in 65816 native mode
    .org $1000
    .M32

    ; Start in 32-bit mode (W=11). Switch to 65816 native (W=01).
    ; REPE #$02 clears W1 -> W=11->W=00, then SEPE #$01 sets W0 -> W=00->W=01
    REPE #$02       ; Clear W1 -> W=00
    SEPE #$01       ; Set W0 -> W=01 (65816 native)
    REP #$20        ; Clear M flag -> M=0 (16-bit)
    .M16            ; Tell assembler
    LDA #$1234      ; 16-bit immediate load
    STP
