; Test: FTOA / FTOT / ATOF / TTOF (FPU register transfer instructions)
;
; Mirrors VHDL TEST 100V.
; Tests round-trip: A/T -> FPU -> A/T with known bit patterns.

    .ORG $1000
    .M32
    .X32

    ; Enter 32-bit native mode (W=00 → W=11)
    SEPE #$03

    ; ----- Step 1: Load F0 via ATOF/TTOF with known 64-bit pattern -----
    ; Target: F0 = 0x4002000000000000 (double 2.25)
    ; Low 32 bits: $00000000, High 32 bits: $40020000

    ; Set F0[31:0] = $AABBCCDD via ATOF
    LDA #$AABBCCDD
    ATOF F0             ; F0[31:0] = $AABBCCDD

    ; Set T = $11223344 via TAT ($02 $9B)
    LDA #$11223344
    .BYTE $02, $9B      ; TAT: T = A

    ; Set F0[63:32] = T via TTOF
    TTOF F0             ; F0[63:32] = $11223344

    ; ----- Step 2: Read back via FTOA, verify low half -----
    FTOA F0             ; A = F0[31:0]
    CMP #$AABBCCDD
    BNE fail

    ; ----- Step 3: Read back via FTOT, verify high half -----
    FTOT F0             ; T = F0[63:32]
    .BYTE $02, $9A      ; TTA: A = T
    CMP #$11223344
    BNE fail

    ; ----- Step 4: Test with different register (F5) -----
    LDA #$DEADBEEF
    ATOF F5             ; F5[31:0] = $DEADBEEF

    LDA #$CAFEBABE
    .BYTE $02, $9B      ; TAT: T = A = $CAFEBABE
    TTOF F5             ; F5[63:32] = $CAFEBABE

    ; Verify F5 low
    FTOA F5
    CMP #$DEADBEEF
    BNE fail

    ; Verify F5 high
    FTOT F5
    .BYTE $02, $9A      ; TTA: A = T
    CMP #$CAFEBABE
    BNE fail

    ; ----- PASS -----
    LDA #$00000001
    STP

fail:
    LDA #$DEADBEEF
    STP
