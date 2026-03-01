; Test LDQ/STQ (dp),Y indirect indexed
; Load 64-bit quad from pointer+Y, store to different pointer+Y
    .org $1000
    .M32
    .X32
    SEPE #$03         ; W=11 (32-bit)

    ; Set up source data at $2000
    LDA #$AABBCCDD
    STA $00002000
    LDA #$11223344
    STA $00002004

    ; Set up pointer in R0 -> $2000
    LDA #$00002000
    STA R0
    ; Set up pointer in R1 -> $3000
    LDA #$00003000
    STA R1

    ; Y = 0
    LDY #$00000000
    ; LDQ (R0),Y -> A:T = 64 bits at $2000
    LDQ (R0),Y
    ; STQ (R1),Y -> store to $3000
    STQ (R1),Y

    ; Verify: load back A from $3000
    LDA $00003000      ; should be $AABBCCDD
    STP
