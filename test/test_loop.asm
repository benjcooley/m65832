; Test loop
    .org $1000
    
    LDX #$05        ; Counter
    LDA #$00        ; Accumulator
loop:
    CLC
    ADC #$01        ; Add 1 each iteration
    DEX
    BNE loop        ; Loop 5 times
    STP             ; A should be 5
