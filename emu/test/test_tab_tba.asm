; Test TAB (A to B) and TBA (B to A)
    .org $1000
    .M32
    
    LDA #$12345678   ; Load test value
    TAB              ; B = A ($12345678)
    LDA #$00000000   ; Clear A
    TBA              ; A = B ($12345678)
    STP
