; Round-trip test: Extended ALU instructions ($02 $80-$97)
; Assemble, disassemble with -m32 -x32, verify mnemonics
; Tests all opcodes x all addressing modes x all sizes

    .ORG $8000
    .M32
    .X32

; =============================================================
; LDA/LD ($80) — all addressing modes, all sizes
; Disassembler outputs LD (not LDA) for extended ALU
; =============================================================

; --- LDA.B (byte, A-targeted) across addressing modes ---
    LDA.B R0                ; dp
    LDA.B R4,X              ; dp,X
    LDA.B R4,Y              ; dp,Y
    LDA.B (R4,X)            ; (dp,X)
    LDA.B (R4),Y            ; (dp),Y
    LDA.B (R4)              ; (dp)
    LDA.B [R4]              ; [dp]
    LDA.B [R4],Y            ; [dp],Y
    LDA.B B+$1000           ; abs (B-relative)
    LDA.B B+$1000,X         ; abs,X
    LDA.B B+$1000,Y         ; abs,Y
    LDA.B $00002000          ; abs32
    LDA.B $00002000,X        ; abs32,X
    LDA.B $00002000,Y        ; abs32,Y
    LDA.B #$42              ; imm
    LDA.B $10,S             ; sr,S
    LDA.B ($10,S),Y         ; (sr,S),Y

; --- LDA.W (word, A-targeted) ---
    LDA.W R0
    LDA.W R4,X
    LDA.W R4,Y
    LDA.W (R4,X)
    LDA.W (R4),Y
    LDA.W (R4)
    LDA.W [R4]
    LDA.W [R4],Y
    LDA.W B+$1000
    LDA.W B+$1000,X
    LDA.W B+$1000,Y
    LDA.W $00002000
    LDA.W $00002000,X
    LDA.W $00002000,Y
    LDA.W #$1234
    LDA.W $10,S
    LDA.W ($10,S),Y

; --- LDA default size (32-bit default, uses standard opcodes for DP) ---
; LDA R0 uses standard $A5, not ext ALU — tested in test_roundtrip_32bit.asm
; LDA B+$1000 and LDA $00002000 go through ext ALU automatically
    LDA B+$1000             ; abs (ext ALU because B-relative)
    LDA $00002000            ; abs32 (ext ALU because 32-bit address)

; --- LD.B (byte, register-targeted) ---
    LD.B R4, R0             ; dp
    LD.B R4, R8,X           ; dp,X
    LD.B R4, #$55           ; imm
    LD.B R4, B+$1000        ; abs
    LD.B R4, $00002000       ; abs32

; --- LD.W (word, register-targeted) ---
    LD.W R4, R0
    LD.W R4, #$ABCD
    LD.W R4, B+$1000

; =============================================================
; STA/ST ($81) — all addressing modes, all sizes
; =============================================================

; --- STA.B (byte, A to memory) ---
    STA.B R0
    STA.B R4,X
    STA.B R4,Y
    STA.B (R4,X)
    STA.B (R4),Y
    STA.B (R4)
    STA.B [R4]
    STA.B [R4],Y
    STA.B B+$1000
    STA.B B+$1000,X
    STA.B B+$1000,Y
    STA.B $00002000
    STA.B $00002000,X
    STA.B $00002000,Y
    STA.B $10,S
    STA.B ($10,S),Y

; --- STA.W ---
    STA.W R0
    STA.W R4,X
    STA.W B+$1000
    STA.W $00002000

; --- STA default size (32-bit default) ---
; STA R0 uses standard $85, not ext ALU
    STA B+$1000             ; abs (ext ALU)
    STA $00002000            ; abs32 (ext ALU)

; --- ST.B (byte, register-targeted) ---
    ST.B R4, R0
    ST.B R4, R8,X
    ST.B R4, B+$1000
    ST.B R4, $00002000

; --- ST.W ---
    ST.W R4, R0
    ST.W R4, B+$1000

; =============================================================
; ADC ($82) — byte/word/default x addressing modes
; =============================================================
    ADC.B #$10
    ADC.B R0
    ADC.B R4,X
    ADC.B (R4),Y
    ADC.B B+$1000
    ADC.B $00002000
    ADC.B $10,S
    ADC.B ($10,S),Y
    ADC.W #$0100
    ADC.W R0
    ADC.W B+$1000
    ADC B+$1000
    ADC #$12345678

; =============================================================
; SBC ($83) — byte/word/default x addressing modes
; =============================================================
    SBC.B #$05
    SBC.B R0
    SBC.B R4,X
    SBC.B (R4),Y
    SBC.B B+$1000
    SBC.B $00002000
    SBC.B $10,S
    SBC.B ($10,S),Y
    SBC.W #$0050
    SBC.W R0
    SBC B+$1000
    SBC #$11111111

; =============================================================
; AND ($84) — byte/word/default x addressing modes
; =============================================================
    AND.B #$0F
    AND.B R0
    AND.B R4,X
    AND.B (R4),Y
    AND.B B+$1000
    AND.B $00002000
    AND.W #$00FF
    AND.W R0
    AND B+$1000
    AND #$22222222

; =============================================================
; ORA ($85) — byte/word/default x addressing modes
; =============================================================
    ORA.B #$F0
    ORA.B R0
    ORA.B R4,X
    ORA.B (R4),Y
    ORA.B B+$1000
    ORA.B $00002000
    ORA.W #$FF00
    ORA.W R0
    ORA B+$1000
    ORA #$33333333

; =============================================================
; EOR ($86) — byte/word/default x addressing modes
; =============================================================
    EOR.B #$AA
    EOR.B R0
    EOR.B R4,X
    EOR.B (R4),Y
    EOR.B B+$1000
    EOR.B $00002000
    EOR.W #$5555
    EOR.W R0
    EOR B+$1000
    EOR #$44444444

; =============================================================
; CMP ($87) — byte/word/default x addressing modes
; =============================================================
    CMP.B #$42
    CMP.B R0
    CMP.B R4,X
    CMP.B (R4),Y
    CMP.B B+$1000
    CMP.B $00002000
    CMP.W #$1234
    CMP.W R0
    CMP B+$1000
    CMP #$55555555

; =============================================================
; BIT ($88) — byte/word
; =============================================================
    BIT.B #$80
    BIT.B R0
    BIT.W #$8000
    BIT.W R0

; =============================================================
; TSB ($89) / TRB ($8A) — byte/word
; =============================================================
    TSB.B R0
    TSB.W R0
    TSB B+$1000
    TSB $00002000
    TRB.B R0
    TRB.W R0
    TRB B+$1000
    TRB $00002000

; =============================================================
; INC ($8B) / DEC ($8C) — unary, byte/word
; =============================================================
    INC.B A
    INC.W A
    DEC.B A
    DEC.W A

; =============================================================
; ASL ($8D) / LSR ($8E) / ROL ($8F) / ROR ($90) — unary
; =============================================================
    ASL.B A
    ASL.W A
    LSR.B A
    LSR.W A
    ROL.B A
    ROL.W A
    ROR.B A
    ROR.W A

; =============================================================
; STZ ($97) — store zero to memory
; =============================================================
    STZ.B R0
    STZ.W R0
    STZ B+$1000
    STZ $00002000

DONE:
    RTS
