; Verify E=0 when W=11 (32-bit mode)
; Default startup is 32-bit mode (W=11). Read E via XCE.
    .org $1000
    .M32

    ; In 32-bit mode (W=11). E should be 0 (W != 00).
    ; XCE to read E: swaps C and derived E
    SEC             ; C=1
    XCE             ; C gets old E (should be 0), W=00 (C was 1)
    ; C should be 0 (E was 0 in 32-bit mode)
    ; Return to 32-bit mode
    SEPE #$03       ; W=00 -> W=11
    LDA #$00000000
    BCS bit32_wasset
    LDA #$00000001  ; C=0 means E was 0 - correct!
    BRA bit32_done
bit32_wasset:
    LDA #$000000FF  ; C=1 means E was 1 - wrong!
bit32_done:
    STP
