; XADC is illegal: encode raw bytes for $42 $82 immediate mode
    .org $1000
    .M32

    .byte $42, $82, $98, $05, $00, $00, $00   ; would be XADC #$00000005
    STP
