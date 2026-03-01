; XSBC is illegal: encode raw bytes for $42 $83 immediate mode
    .org $1000
    .M32

    .byte $42, $83, $98, $20, $00, $00, $00   ; would be XSBC #$00000020
    STP
