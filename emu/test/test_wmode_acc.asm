; W_mode: LDA/STA round-trip through 32-bit absolute address
    .org $1000
    .M32

    LDA #$AABBCCDD   ; 32-bit immediate load
    STA $00002000     ; Extended ALU 32-bit absolute store
    LDA #$00000000   ; Clear A
    LDA $00002000     ; Extended ALU 32-bit absolute load
    STP
