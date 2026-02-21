; Round-trip test: 32-bit mode
; Assemble, disassemble with -m32 -x32 -R, verify mnemonics
; Long addressing is ILLEGAL in 32-bit mode — not tested here

    .ORG $8000
    .M32
    .X32

; === 32-bit Immediates ===
    LDA #$12345678          ; $A9 + 4 bytes
    LDX #$9ABCDEF0          ; $A2 + 4 bytes
    LDY #$11223344          ; $A0 + 4 bytes
    ADC #$AABBCCDD          ; $69 + 4 bytes
    SBC #$11111111          ; $E9 + 4 bytes
    AND #$22222222          ; $29 + 4 bytes
    ORA #$33333333          ; $09 + 4 bytes
    EOR #$44444444          ; $49 + 4 bytes
    CMP #$55555555          ; $C9 + 4 bytes
    CPX #$66666666          ; $E0 + 4 bytes
    CPY #$77777777          ; $C0 + 4 bytes

; === DP (register names in 32-bit mode) ===
    LDA R4
    STA R8
    LDX R12
    LDY R16
    STX R20
    STY R24
    STZ R28
    ADC R4
    SBC R8
    AND R12
    ORA R16
    EOR R20
    CMP R24

; === DP Indexed ===
    LDA R4,X
    STA R8,X
    LDX R4,Y
    STX R8,Y

; === Absolute (B-relative in 32-bit mode) ===
    LDA B+$1234
    STA B+$5678
    LDX B+$9ABC
    LDY B+$DEF0

; === Absolute Indexed (B-relative) ===
    LDA B+$1234,X
    STA B+$5678,X
    LDA B+$1234,Y
    STA B+$5678,Y

; === DP Indirect ===
    LDA (R4,X)
    STA (R8,X)
    LDA (R4),Y
    STA (R8),Y
    LDA (R12)
    STA (R16)

; === cc=11 non-long modes (still valid in 32-bit) ===
    LDA [R4]
    STA [R8]
    LDA [R4],Y
    STA [R8],Y
    LDA $05,S
    STA $06,S
    LDA ($05,S),Y
    STA ($06,S),Y

; === 65816 implied ===
    PHD
    PLD
    PHB
    PLB
    WAI
    XBA

; === Branches (32-bit mode = 16-bit offset) ===
    BEQ DONE
    BNE DONE
    BRA DONE

; === Transfers ===
    TAX
    TXA
    TAY
    TYA
    TSX
    TXS
    TCD
    TDC
    TCS
    TSC
    TXY
    TYX

; === Extended instructions ($02 prefix) ===
; Multiply/Divide
    MUL R8
    MULU R12
    DIV R16
    DIVU R20
    MUL B+$1234
    MULU B+$2345
    DIV B+$3456
    DIVU B+$4567

; Atomics
    CAS R8
    CAS B+$1234
    LLI R12
    LLI B+$2345
    SCI R16
    SCI B+$3456
    FENCE
    FENCER
    FENCEW

; Register window
    RSET
    RCLR

; System
    TRAP #$10

; Extended flags
    SEPE #$03
    REPE #$03

; B register transfers
    TAB
    TBA
    TXB
    TBX
    TYB
    TBY
    TSPB

; Temp register
    TTA
    TAT

; 64-bit load/store
    LDQ R8
    LDQ B+$1234
    STQ R12
    STQ B+$2345

; LEA
    LEA R8
    LEA R8,X
    LEA B+$1234
    LEA B+$1234,X

; FPU Load/Store
    LDF F0, $20
    LDF F5, $1234
    STF F0, $30
    STF F15, $2345

; FPU Arithmetic
    FADD.S F0, F1
    FSUB.S F2, F3
    FMUL.S F4, F5
    FDIV.S F6, F7
    FNEG.S F0, F1
    FABS.S F2, F3
    FCMP.S F4, F5
    F2I.S F0
    I2F.S F1
    FMOV.S F8, F9
    FSQRT.S F10, F11

    FADD.D F0, F1
    FSUB.D F2, F3
    FMUL.D F4, F5
    FDIV.D F6, F7
    FMOV.D F12, F13
    FSQRT.D F14, F15

; FPU Transfers
    FTOA F0
    FTOT F1
    ATOF F2
    TTOF F3
    FCVT.DS F4, F5
    FCVT.SD F6, F7

DONE:
    RTS
