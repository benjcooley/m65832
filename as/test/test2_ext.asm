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

; Temp register
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

; FPU Load/Store
FPU_TEST:
    LDF0 $20            ; $02 $B0 $20
    LDF0 $1234          ; $02 $B1 $34 $12
    STF0 $30            ; $02 $B2 $30
    STF0 $2345          ; $02 $B3 $45 $23

; FPU Arithmetic
    FADD.S              ; $02 $C0
    FSUB.S              ; $02 $C1
    FMUL.S              ; $02 $C2
    FDIV.S              ; $02 $C3
    FNEG.S              ; $02 $C4
    FABS.S              ; $02 $C5
    FCMP.S              ; $02 $C6
    F2I.S               ; $02 $C7
    I2F.S               ; $02 $C8
    
    FADD.D              ; $02 $D0
    FSUB.D              ; $02 $D1
    FMUL.D              ; $02 $D2
    FDIV.D              ; $02 $D3

END_TEST:
    NOP
    .BYTE 0
