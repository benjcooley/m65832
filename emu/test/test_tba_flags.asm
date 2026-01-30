; Test TBA sets N flag for negative value
    .org $1000
    .M32
    
    SB #$80000000    ; B = $80000000 (negative)
    TBA              ; A = B, should set N flag
    STP
