; Test 7: Extended Instructions ($E9 shifter, $EA extend)
; Tests the new shifter/rotate and sign/zero extend instructions
; Also tests R0-R63 register alias syntax

    .org $8000

; ==== Test Shifter Instructions ($E9) ====
start:
    ; Using DP address syntax
    SHL $10, $04, #4      ; Shift left R4 by 4, result in $10 (R4)
    SHR $14, $08, #8      ; Shift right R5 by 8, result in $14 (R5)
    SAR $18, $0C, #16     ; Arithmetic shift right R6 by 16, result in $18 (R6)
    ROL $1C, $10, #1      ; Rotate left R7 by 1, result in $1C (R7)
    ROR $20, $14, #2      ; Rotate right R8 by 2, result in $20 (R8)
    
    ; Using register alias syntax
    SHL R10, R1, #4       ; Same instruction, different syntax
    SHR R11, R2, #8
    SAR R12, R3, #16
    ROL R13, R4, #1
    ROR R14, R5, #2
    
    ; Variable shift from A register
    SHL R20, R10, A       ; Shift by value in A
    SHR R21, R11, A
    SAR R22, R12, A
    ROL R23, R13, A
    ROR R24, R14, A
    
    ; Edge cases
    SHL R0, R0, #0        ; Shift by 0 (no change)
    SHR R63, R63, #31     ; Shift by 31 (max constant)

; ==== Test Extend Instructions ($EA) ====
extend_tests:
    ; Sign extend (DP syntax)
    SEXT8 $30, $04        ; Sign extend byte at $04 to $30
    SEXT16 $34, $08       ; Sign extend word at $08 to $34
    
    ; Zero extend (DP syntax)
    ZEXT8 $38, $0C        ; Zero extend byte at $0C to $38
    ZEXT16 $3C, $10       ; Zero extend word at $10 to $3C
    
    ; Bit counting (DP syntax)
    CLZ $40, $14          ; Count leading zeros
    CTZ $44, $18          ; Count trailing zeros
    POPCNT $48, $1C       ; Population count
    
    ; Using register alias syntax
    SEXT8 R20, R1         ; Sign extend byte
    SEXT16 R21, R2        ; Sign extend word
    ZEXT8 R22, R3         ; Zero extend byte
    ZEXT16 R23, R4        ; Zero extend word
    CLZ R24, R5           ; Count leading zeros
    CTZ R25, R6           ; Count trailing zeros
    POPCNT R26, R7        ; Population count

; ==== Mixed syntax to verify equivalence ====
mixed_tests:
    SHL $28, R1, #4       ; Mix DP and register syntax
    SHR R11, $08, #8      ; Mix register and DP syntax
    SEXT8 $50, R3         ; Mix extend with register
    CLZ R20, $14          ; Mix CLZ with DP
    
    ; Register expressions
    SHL R0+1, R0+2, #4    ; R1 ($04) and R2 ($08) via expression
    
done:
    STP                   ; Stop processor

; Expected byte sequences for verification:
; SHL $10, $04, #4    -> $02 $98 $04 $10 $04  (op=0, count=4, dest=$10, src=$04)
; SHR $14, $08, #8    -> $02 $98 $28 $14 $08  (op=1, count=8, dest=$14, src=$08)
; SAR $18, $0C, #16   -> $02 $98 $50 $18 $0C  (op=2, count=16, dest=$18, src=$0C)
; ROL $1C, $10, #1    -> $02 $98 $61 $1C $10  (op=3, count=1, dest=$1C, src=$10)
; ROR $20, $14, #2    -> $02 $98 $82 $20 $14  (op=4, count=2, dest=$20, src=$14)
; SHL R20, R10, A     -> $02 $98 $1F $50 $28  (op=0, count=31/A, dest=R20=$50, src=R10=$28)
; SEXT8 $30, $04      -> $02 $99 $00 $30 $04  (subop=0, dest=$30, src=$04)
; CLZ $40, $14        -> $02 $99 $04 $40 $14  (subop=4, dest=$40, src=$14)
; POPCNT $48, $1C     -> $02 $99 $06 $48 $1C  (subop=6, dest=$48, src=$1C)
