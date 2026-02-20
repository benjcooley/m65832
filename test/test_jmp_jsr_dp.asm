; Test JMP (dp) and JSR (dp)
    .org $1000
    .M32
    
    ; Set up function pointer in register window
    LDA #subroutine
    STA R5              ; Store function addr in R5 ($14)
    
    ; Call through register
    JSR (R5)            ; $02 $A6 $14 - indirect call
    STP
    
subroutine:
    LDA #$CAFEBABE      ; Load a recognizable value
    RTS
