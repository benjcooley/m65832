; Verify E=1 when W=00 (emulation mode)
; Start in 32-bit mode. XCE with C=1 enters emulation (W=00).
; Then XCE again to read back E (should be 1).
    .org $1000
    .M32

    SEC             ; C=1
    XCE             ; C gets old E (0, since W=11), W becomes 00 (C was 1)
    ; Now in emulation mode (W=00, E=1). C=0 (old E was 0).
    ; Read E by doing another XCE:
    SEC             ; C=1
    XCE             ; C gets old E (should be 1 since W=00), W=00 again (C was 1)
    ; C should be 1 (E was 1 in emulation mode)
    ; Return to 32-bit mode for result reporting
    SEPE #$03       ; W=00 -> W=11
    LDA #$00000000
    BCC emu_notset
    LDA #$00000001  ; C=1 means E was 1 - correct!
emu_notset:
    STP
