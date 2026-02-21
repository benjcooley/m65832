; Test 11: Disassembler register name display
; Tests that DP addressing modes show Rn names when R=1 (default)
; and raw $xx when R=0 (-R flag)

    .ORG $8000
    .M32
    .X32

; DP direct - should show Rn via standard opcodes
    LDX R8,Y            ; B6 20
    LDA (R4,X)           ; A1 10
    STA (R8,X)           ; 81 20
    LDA (R4),Y           ; B1 10
    STA (R8),Y           ; 91 20
    LDA (R2)             ; B2 08
    LDA [R4]             ; A7 10
    LDA R5               ; A5 14
    STA R3               ; 85 0C
    LDA R4,X             ; B5 10

; Stack relative (should NOT show Rn)
    LDA $04,S            ; A3 04
    STA $08,S            ; 83 08

; Branches (16-bit rel in 32-bit mode)
    BEQ DONE             ; F0 xx xx
    BNE DONE             ; D0 xx xx

; Extended ALU with register names
    LD R2, #$00000001    ; 02 80 B8 08 01 00 00 00
    LD R5, (R4),Y        ; 02 80 A4 14 10
    ST R5, (R4),Y        ; 02 81 A4 14 10

; Absolute (B-relative in 32-bit mode)
    LDA B+$0010          ; AD 10 00
    STA B+$0100          ; 8D 00 01
    LDA B+$0010,X        ; BD 10 00
    STA B+$0100,Y        ; 99 00 01

DONE:
    RTS
