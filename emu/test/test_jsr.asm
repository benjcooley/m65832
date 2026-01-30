; Test JSR/RTS with 32-bit absolute addresses
    .org $1000
    .M32
    
    LDA #$10
    JSR add_five      ; 32-bit absolute call
    JSR add_five      ; A should be 0x1A
    STP

add_five:
    CLC
    ADC #$05
    RTS
