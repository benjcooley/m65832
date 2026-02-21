; Round-trip test: 8-bit mode (6502 compatible)
; Assemble, disassemble, verify mnemonics match

    .ORG $8000
    .M8
    .X8

; === Implied / Accumulator ===
    NOP                     ; $EA
    CLC                     ; $18
    SEC                     ; $38
    CLI                     ; $58
    SEI                     ; $78
    CLV                     ; $B8
    CLD                     ; $D8
    SED                     ; $F8
    INX                     ; $E8
    INY                     ; $C8
    DEX                     ; $CA
    DEY                     ; $88
    TAX                     ; $AA
    TXA                     ; $8A
    TAY                     ; $A8
    TYA                     ; $98
    TSX                     ; $BA
    TXS                     ; $9A
    ASL                     ; $0A
    LSR                     ; $4A
    ROL                     ; $2A
    ROR                     ; $6A
    INC                     ; $1A
    DEC                     ; $3A
    PHA                     ; $48
    PLA                     ; $68
    PHP                     ; $08
    PLP                     ; $28
    PHX                     ; $DA
    PLX                     ; $FA
    PHY                     ; $5A
    PLY                     ; $7A

; === 65816 Implied (cc=11 bbb=010) ===
    PHD                     ; $0B
    PLD                     ; $2B
    PHK                     ; $4B
    RTL                     ; $6B
    PHB                     ; $8B
    PLB                     ; $AB
    WAI                     ; $CB
    XBA                     ; $EB

; === 65816 Transfers ===
    TCD                     ; $5B
    TDC                     ; $7B
    TCS                     ; $1B
    TSC                     ; $3B
    TXY                     ; $9B
    TYX                     ; $BB
    XCE                     ; $FB

; === Immediate ===
    LDA #$42                ; $A9 $42
    LDX #$33                ; $A2 $33
    LDY #$55                ; $A0 $55
    ADC #$10                ; $69 $10
    SBC #$20                ; $E9 $20
    AND #$0F                ; $29 $0F
    ORA #$F0                ; $09 $F0
    EOR #$AA                ; $49 $AA
    CMP #$77                ; $C9 $77
    CPX #$88                ; $E0 $88
    CPY #$99                ; $C0 $99
    BIT #$55                ; $89 $55
    SEP #$30                ; $E2 $30
    REP #$20                ; $C2 $20

; === Direct Page ===
    LDA $10                 ; $A5 $10
    LDX $20                 ; $A6 $20
    LDY $30                 ; $A4 $30
    STA $40                 ; $85 $40
    STX $50                 ; $86 $50
    STY $60                 ; $84 $60
    STZ $70                 ; $64 $70
    ADC $10                 ; $65 $10
    SBC $20                 ; $E5 $20
    AND $30                 ; $25 $30
    ORA $40                 ; $05 $40
    EOR $50                 ; $45 $50
    CMP $60                 ; $C5 $60
    BIT $70                 ; $24 $70
    ASL $80                 ; $06 $80
    LSR $80                 ; $46 $80
    ROL $80                 ; $26 $80
    ROR $80                 ; $66 $80
    INC $80                 ; $E6 $80
    DEC $80                 ; $C6 $80
    TSB $80                 ; $04 $80
    TRB $80                 ; $14 $80

; === Direct Page Indexed ===
    LDA $10,X               ; $B5 $10
    LDY $20,X               ; $B4 $20
    STA $30,X               ; $95 $30
    STZ $40,X               ; $74 $40
    LDX $10,Y               ; $B6 $10
    STX $20,Y               ; $96 $20
    ADC $10,X               ; $75 $10
    SBC $20,X               ; $F5 $20
    AND $30,X               ; $35 $30
    ORA $40,X               ; $15 $40
    EOR $50,X               ; $55 $50
    CMP $60,X               ; $D5 $60

; === Absolute ===
    LDA $1234               ; $AD $34 $12
    LDX $2345               ; $AE $45 $23
    LDY $3456               ; $AC $56 $34
    STA $4567               ; $8D $67 $45
    STX $5678               ; $8E $78 $56
    STY $6789               ; $8C $89 $67
    STZ $789A               ; $9C $9A $78
    ADC $1234               ; $6D $34 $12
    SBC $2345               ; $ED $45 $23
    AND $3456               ; $2D $56 $34
    ORA $4567               ; $0D $67 $45
    EOR $5678               ; $4D $78 $56
    CMP $6789               ; $CD $89 $67
    BIT $1234               ; $2C $34 $12
    CPX $2345               ; $EC $45 $23
    CPY $3456               ; $CC $56 $34
    JMP $8000               ; $4C $00 $80
    JSR $9000               ; $20 $00 $90

; === Absolute Indexed ===
    LDA $1234,X             ; $BD $34 $12
    LDY $2345,X             ; $BC $45 $23
    STA $3456,X             ; $9D $56 $34
    LDA $1234,Y             ; $B9 $34 $12
    LDX $2345,Y             ; $BE $45 $23
    STA $3456,Y             ; $99 $56 $34
    ADC $1234,X             ; $7D $34 $12
    SBC $2345,X             ; $FD $45 $23
    AND $3456,X             ; $3D $56 $34
    ORA $4567,X             ; $1D $67 $45
    EOR $5678,X             ; $5D $78 $56
    CMP $6789,X             ; $DD $89 $67
    ADC $1234,Y             ; $79 $34 $12
    SBC $2345,Y             ; $F9 $45 $23
    AND $3456,Y             ; $39 $56 $34
    ORA $4567,Y             ; $19 $67 $45
    EOR $5678,Y             ; $59 $78 $56
    CMP $6789,Y             ; $D9 $89 $67

; === DP Indirect ===
    LDA ($10,X)             ; $A1 $10
    STA ($20,X)             ; $81 $20
    LDA ($10),Y             ; $B1 $10
    STA ($20),Y             ; $91 $20
    LDA ($30)               ; $B2 $30
    STA ($40)               ; $92 $40
    ADC ($10,X)             ; $61 $10
    SBC ($20,X)             ; $E1 $20
    AND ($10,X)             ; $21 $10
    ORA ($20,X)             ; $01 $20
    EOR ($30,X)             ; $41 $30
    CMP ($40,X)             ; $C1 $40
    ADC ($10),Y             ; $71 $10
    SBC ($20),Y             ; $F1 $20
    AND ($30),Y             ; $31 $30
    ORA ($40),Y             ; $11 $40
    EOR ($50),Y             ; $51 $50
    CMP ($60),Y             ; $D1 $60

; === cc=11: [dp] indirect long ===
    LDA [$10]               ; $A7 $10
    STA [$20]               ; $87 $20
    ADC [$10]               ; $67 $10
    SBC [$20]               ; $E7 $20
    AND [$30]               ; $27 $30
    ORA [$40]               ; $07 $40
    EOR [$50]               ; $47 $50
    CMP [$60]               ; $C7 $60

; === cc=11: [dp],Y indirect long indexed ===
    LDA [$10],Y             ; $B7 $10
    STA [$20],Y             ; $97 $20
    ADC [$10],Y             ; $77 $10
    SBC [$20],Y             ; $F7 $20
    AND [$30],Y             ; $37 $30
    ORA [$40],Y             ; $17 $40
    EOR [$50],Y             ; $57 $50
    CMP [$60],Y             ; $D7 $60

; === cc=11: sr,S stack relative ===
    LDA $05,S               ; $A3 $05
    STA $06,S               ; $83 $06
    ADC $07,S               ; $63 $07
    SBC $08,S               ; $E3 $08
    AND $09,S               ; $23 $09
    ORA $0A,S               ; $03 $0A
    EOR $0B,S               ; $43 $0B
    CMP $0C,S               ; $C3 $0C

; === cc=11: (sr,S),Y stack relative indirect indexed ===
    LDA ($05,S),Y           ; $B3 $05
    STA ($06,S),Y           ; $93 $06
    ADC ($07,S),Y           ; $73 $07
    SBC ($08,S),Y           ; $F3 $08
    AND ($09,S),Y           ; $33 $09
    ORA ($0A,S),Y           ; $13 $0A
    EOR ($0B,S),Y           ; $53 $0B
    CMP ($0C,S),Y           ; $D3 $0C

; === cc=11: long addressing (24-bit) ===
    LDA $123456             ; $AF $56 $34 $12
    STA $234567             ; $8F $67 $45 $23
    LDA $345678,X           ; $BF $78 $56 $34
    STA $456789,X           ; $9F $89 $67 $45
    ADC $123456             ; $6F $56 $34 $12
    SBC $234567             ; $EF $67 $45 $23
    AND $345678             ; $2F $78 $56 $34
    ORA $456789             ; $0F $89 $67 $45
    EOR $123456             ; $4F $56 $34 $12
    CMP $234567             ; $CF $67 $45 $23
    ADC $123456,X           ; $7F $56 $34 $12
    ; SBC long,X = $FF - may conflict with assembler parser
    .BYTE $FF, $67, $45, $23  ; SBC $234567,X
    AND $345678,X           ; $3F $78 $56 $34
    ORA $456789,X           ; $1F $89 $67 $45
    EOR $123456,X           ; $5F $56 $34 $12
    CMP $234567,X           ; $DF $67 $45 $23

; === Branches ===
    BEQ BRTARGET            ; $F0 xx
    BNE BRTARGET            ; $D0 xx
    BCS BRTARGET            ; $B0 xx
    BCC BRTARGET            ; $90 xx
    BMI BRTARGET            ; $30 xx
    BPL BRTARGET            ; $10 xx
    BVS BRTARGET            ; $70 xx
    BVC BRTARGET            ; $50 xx
    BRA BRTARGET            ; $80 xx
BRTARGET:

; === Jumps ===
    JMP ($1234)             ; $6C $34 $12
    JMP ($1234,X)           ; $7C $34 $12
    JML $123456             ; $5C $56 $34 $12
    JSL $234567             ; $22 $67 $45 $23
    JML [$1234]             ; $DC $34 $12

; === Misc ===
    BRK                     ; $00
    RTS                     ; $60
    RTI                     ; $40
    STP                     ; $DB
    .BYTE $54, $34, $12    ; MVN $12,$34
    .BYTE $44, $78, $56    ; MVP $56,$78
    .BYTE $F4, $34, $12    ; PEA $1234
    .BYTE $D4, $10         ; PEI ($10)
END:
    NOP
