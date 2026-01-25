; Test branches
    .org $1000
    
    LDA #$00
    BEQ zero        ; Should branch
    LDA #$FF        ; Should be skipped
zero:
    LDA #$AA        ; Should execute
    STP
