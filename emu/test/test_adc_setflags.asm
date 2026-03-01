; Normal ADC must still set flags
    .org $1000
    .M32

    CLC
    LDA #$7FFFFFFF
    ADC #$00000001        ; A = $80000000; should set N, clear Z
    STP
