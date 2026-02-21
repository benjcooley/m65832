; Round-trip test: 16-bit mode (65816 native)
; Assemble, disassemble with -m16 -x16 -R, verify mnemonics

    .ORG $8000
    .M16
    .X16

; === 16-bit Immediates ===
    LDA #$1234              ; $A9 $34 $12
    LDX #$5678              ; $A2 $78 $56
    LDY #$9ABC              ; $A0 $BC $9A
    ADC #$1111              ; $69 $11 $11
    SBC #$2222              ; $E9 $22 $22
    AND #$3333              ; $29 $33 $33
    ORA #$4444              ; $09 $44 $44
    EOR #$5555              ; $49 $55 $55
    CMP #$6666              ; $C9 $66 $66
    CPX #$7777              ; $E0 $77 $77
    CPY #$8888              ; $C0 $88 $88

; === DP (same as 8-bit encoding) ===
    LDA $10
    STA $20
    LDX $30
    STX $40

; === Absolute ===
    LDA $1234
    STA $5678
    LDX $9ABC
    LDY $DEF0

; === Absolute Indexed ===
    LDA $1234,X
    STA $5678,X
    LDA $1234,Y
    STA $5678,Y

; === DP Indirect ===
    LDA ($10,X)
    STA ($20,X)
    LDA ($10),Y
    STA ($20),Y
    LDA ($30)
    STA ($40)

; === cc=11: [dp] / [dp],Y / sr,S / (sr,S),Y / long / long,X ===
    LDA [$10]
    STA [$20]
    LDA [$10],Y
    STA [$20],Y
    LDA $05,S
    STA $06,S
    LDA ($05,S),Y
    STA ($06,S),Y
    LDA $123456
    STA $234567
    LDA $345678,X
    STA $456789,X

; === All 8 ALU ops with long addressing ===
    ADC $123456
    SBC $234567
    AND $345678
    ORA $456789
    EOR $123456
    CMP $234567
    ADC $123456,X
    .BYTE $FF, $67, $45, $23  ; SBC $234567,X
    AND $345678,X
    ORA $456789,X
    EOR $123456,X
    CMP $234567,X

; === All 8 ALU ops with (sr,S),Y ===
    ADC ($07,S),Y
    SBC ($08,S),Y
    AND ($09,S),Y
    ORA ($0A,S),Y
    EOR ($0B,S),Y
    CMP ($0C,S),Y

; === All 8 ALU ops with [dp],Y ===
    ADC [$10],Y
    SBC [$20],Y
    AND [$30],Y
    ORA [$40],Y
    EOR [$50],Y
    CMP [$60],Y

; === 65816 implied ===
    PHD
    PLD
    PHK
    RTL
    PHB
    PLB
    WAI
    XBA

; === Branches (16-bit mode = 8-bit offset) ===
    BEQ DONE
    BNE DONE
    BRA DONE

; === Jumps ===
    JMP $8000
    JSR $9000
    JML $123456
    JSL $234567

DONE:
    RTS
