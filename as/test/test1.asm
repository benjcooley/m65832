; M65832 Assembler Test 1 - Basic Instructions

    .ORG $1000

; Constants
CONST1 = $10
CONST2 EQU $20

    .M16                    ; 16-bit accumulator
    .X16                    ; 16-bit index

; === Implied/Accumulator ===
START:
    NOP                 ; $EA
    CLC                 ; $18
    SEC                 ; $38
    CLI                 ; $58
    SEI                 ; $78
    
    INX                 ; $E8
    INY                 ; $C8
    DEX                 ; $CA
    DEY                 ; $88
    
    TAX                 ; $AA
    TXA                 ; $8A
    TAY                 ; $A8
    TYA                 ; $98
    TSX                 ; $BA
    TXS                 ; $9A
    
    ASL                 ; $0A (accumulator)
    LSR                 ; $4A
    ROL                 ; $2A
    ROR                 ; $6A
    
    INC                 ; $1A (65C02+)
    DEC                 ; $3A
    
    PHA                 ; $48
    PLA                 ; $68
    PHP                 ; $08
    PLP                 ; $28

; === Immediate ===
IMM_TEST:
    LDA #$12            ; $A9 $12 $00 (16-bit)
    LDX #$34            ; $A2 $34 $00
    LDY #$56            ; $A0 $56 $00
    
    AND #$0F            ; $29 $0F $00
    ORA #$F0            ; $09 $F0 $00
    EOR #$AA            ; $49 $AA $00
    CMP #$00            ; $C9 $00 $00
    
    REP #$30            ; $C2 $30
    SEP #$20            ; $E2 $20

; === Direct Page ===
DP_TEST:
    LDA $10             ; $A5 $10
    LDX $20             ; $A6 $20
    LDY $30             ; $A4 $30
    STA $40             ; $85 $40
    STX $50             ; $86 $50
    STY $60             ; $84 $60
    STZ $70             ; $64 $70

; === Direct Page Indexed ===
DPX_TEST:
    LDA $10,X           ; $B5 $10
    LDY $20,X           ; $B4 $20
    STA $30,X           ; $95 $30
    
    LDX $10,Y           ; $B6 $10
    STX $20,Y           ; $96 $20

; === Absolute ===
ABS_TEST:
    LDA $1234           ; $AD $34 $12
    LDX $2345           ; $AE $45 $23
    LDY $3456           ; $AC $56 $34
    STA $4567           ; $8D $67 $45
    
    JMP $8000           ; $4C $00 $80
    JSR $9000           ; $20 $00 $90

; === Absolute Indexed ===
ABSX_TEST:
    LDA $1234,X         ; $BD $34 $12
    LDY $2345,X         ; $BC $45 $23
    STA $3456,X         ; $9D $56 $34
    
    LDA $1234,Y         ; $B9 $34 $12
    LDX $2345,Y         ; $BE $45 $23
    STA $3456,Y         ; $99 $56 $34

; === Indirect (DP) ===
IND_TEST:
    LDA ($10,X)         ; $A1 $10
    STA ($20,X)         ; $81 $20
    
    LDA ($10),Y         ; $B1 $10
    STA ($20),Y         ; $91 $20

; === Indirect Long ===
INDL_TEST:
    LDA [$10]           ; $A7 $10
    STA [$20]           ; $87 $20
    
    LDA [$10],Y         ; $B7 $10
    STA [$20],Y         ; $97 $20

; === Branches ===
BRANCH_TEST:
    BEQ BRANCH_TARGET   ; $F0 xx
    BNE BRANCH_TARGET   ; $D0 xx
    BCS BRANCH_TARGET   ; $B0 xx
    BCC BRANCH_TARGET   ; $90 xx
    BMI BRANCH_TARGET   ; $30 xx
    BPL BRANCH_TARGET   ; $10 xx
    BRA BRANCH_TARGET   ; $80 xx
BRANCH_TARGET:
    NOP

; === 65816 Special ===
SPECIAL_TEST:
    PHD                 ; $0B
    PLD                 ; $2B
    PHB                 ; $8B
    PLB                 ; $AB
    PHK                 ; $4B
    TCD                 ; $5B
    TDC                 ; $7B
    XBA                 ; $EB
    XCE                 ; $FB
    
    RTS                 ; $60
    RTL                 ; $6B
    RTI                 ; $40

; === Absolute Long ===
LONG_TEST:
    LDA $123456         ; $AF $56 $34 $12
    STA $234567         ; $8F $67 $45 $23
    LDA $345678,X       ; $BF $78 $56 $34
    JML $456789         ; $5C $89 $67 $45
    JSL $567890         ; $22 $90 $78 $56

; === Control ===
    BRK                 ; $00
    WAI                 ; $CB
    STP                 ; $DB

THE_END:
    .BYTE 0
