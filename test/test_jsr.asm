; Test JSR/RTS
    .org $1000
    
    LDA #$10
    JSR B+add_five
    JSR B+add_five    ; A should be 0x1A
    STP

add_five:
    CLC
    ADC #$05
    RTS
