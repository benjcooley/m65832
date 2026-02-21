; Verify E=0 when W=01 (native mode)
; Start 32-bit. XCE C=1 -> emu (W=00). CLC, XCE -> native (W=01).
; Then XCE again to read E (should be 0).
    .org $1000
    .M32

    ; Enter emulation mode first
    SEC             ; C=1
    XCE             ; W=11->W=00, C=0 (old E=0)
    ; Now in emulation (W=00). Enter native:
    CLC             ; C=0
    XCE             ; C gets old E (1, since W=00), W becomes 01 (native)
    ; Now in native mode (W=01, E=0). C=1 (old E was 1).
    ; Read E by doing another XCE:
    SEC             ; C=1
    XCE             ; C gets old E (should be 0 since W=01), W=00 (C was 1)
    ; C should be 0 (E was 0 in native mode)
    ; Return to 32-bit mode for result reporting
    SEPE #$03       ; W=00 -> W=11
    LDA #$00000000
    BCS nat_wasset
    LDA #$00000001  ; C=0 means E was 0 - correct!
    BRA nat_done
nat_wasset:
    LDA #$000000FF  ; C=1 means E was 1 - wrong!
nat_done:
    STP
