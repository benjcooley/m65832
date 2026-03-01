; Test LDQ/STQ (dp),Y with non-zero Y offset
    .org $1000
    .M32
    .X32
    SEPE #$03

    ; Source data at $2010 (offset $10 from base $2000)
    LDA #$DEADBEEF
    STA $00002010
    LDA #$CAFEBABE
    STA $00002014

    ; Pointer in R0 -> $2000
    LDA #$00002000
    STA R0
    ; Pointer in R1 -> $3000
    LDA #$00003000
    STA R1

    ; Y = $10
    LDY #$00000010
    LDQ (R0),Y         ; load from $2000+$10=$2010
    STQ (R1),Y         ; store to $3000+$10=$3010

    LDA $00003010      ; should be $DEADBEEF
    STP
