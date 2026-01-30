; M65832 Extended Instructions Test

    .ORG $2000

    .M32                    ; 32-bit accumulator
    .X32                    ; 32-bit index

; === M65832 Extended Instructions ===
; All use $02 prefix

; Multiply/Divide
MUL_TEST:
    MUL $20             ; $02 $00 $20
    MULU $30            ; $02 $01 $30
    MUL $1234           ; $02 $02 $34 $12
    MULU $2345          ; $02 $03 $45 $23
    DIV $40             ; $02 $04 $40
    DIVU $50            ; $02 $05 $50
    DIV $3456           ; $02 $06 $56 $34
    DIVU $4567          ; $02 $07 $67 $45

; Atomics
ATOMIC_TEST:
    CAS $20             ; $02 $10 $20
    CAS $1234           ; $02 $11 $34 $12
    LLI $30             ; $02 $12 $30
    LLI $2345           ; $02 $13 $45 $23
    SCI $40             ; $02 $14 $40
    SCI $3456           ; $02 $15 $56 $34
    FENCE               ; $02 $50
    FENCER              ; $02 $51
    FENCEW              ; $02 $52

; Register Window
REGWIN_TEST:
    RSET                ; $02 $30
    RCLR                ; $02 $31

; System
SYS_TEST:
    TRAP #$10           ; $02 $40 $10

; Extended flags
FLAG_TEST:
    REPE #$A0           ; $02 $60 $A0
    SEPE #$50           ; $02 $61 $50

; B register transfers
BTRANS_TEST:
    TAB                 ; $02 $91
    TBA                 ; $02 $92

; Temp register transfers
TEMP_TEST:
    TTA                 ; $02 $9A
    TAT                 ; $02 $9B

; 64-bit load/store
QUAD_TEST:
    LDQ $20             ; $02 $9C $20
    LDQ $1234           ; $02 $9D $34 $12
    STQ $30             ; $02 $9E $30
    STQ $2345           ; $02 $9F $45 $23

; LEA
LEA_TEST:
    LEA $20             ; $02 $A0 $20
    LEA $20,X           ; $02 $A1 $20
    LEA $1234           ; $02 $A2 $34 $12
    LEA $1234,X         ; $02 $A3 $34 $12

; FPU Load/Store (16-register format with register byte)
FPU_TEST:
    LDF F0, $20         ; $02 $B0 $00 $20 (LDF dp)
    LDF F5, $1234       ; $02 $B1 $05 $34 $12 (LDF abs)
    STF F0, $30         ; $02 $B2 $00 $30 (STF dp)
    STF F15, $2345      ; $02 $B3 $0F $45 $23 (STF abs)

; FPU Arithmetic (two-operand destructive: Fd = Fd op Fs)
    FADD.S F0, F1       ; $02 $C0 $01
    FSUB.S F2, F3       ; $02 $C1 $23
    FMUL.S F4, F5       ; $02 $C2 $45
    FDIV.S F6, F7       ; $02 $C3 $67
    FNEG.S F0, F1       ; $02 $C4 $01
    FABS.S F2, F3       ; $02 $C5 $23
    FCMP.S F4, F5       ; $02 $C6 $45
    F2I.S F0            ; $02 $C7 $00
    I2F.S F1            ; $02 $C8 $10
    FMOV.S F8, F9       ; $02 $C9 $89
    FSQRT.S F10, F11    ; $02 $CA $AB
    
    FADD.D F0, F1       ; $02 $D0 $01
    FSUB.D F2, F3       ; $02 $D1 $23
    FMUL.D F4, F5       ; $02 $D2 $45
    FDIV.D F6, F7       ; $02 $D3 $67
    FMOV.D F12, F13     ; $02 $D9 $CD
    FSQRT.D F14, F15    ; $02 $DA $EF
    
; FPU Register transfers
    FTOA F0             ; $02 $E0 $00
    FTOT F1             ; $02 $E1 $10
    ATOF F2             ; $02 $E2 $20
    TTOF F3             ; $02 $E3 $30
    FCVT.DS F4, F5      ; $02 $E4 $45
    FCVT.SD F6, F7      ; $02 $E5 $67

END_TEST:
    NOP
    .BYTE 0
