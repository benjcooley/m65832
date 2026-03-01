; test_psh32_pul32.asm - Test PSH32/PUL32 (always 32-bit push/pull)
; Load a known value into A, push it with PSH32, clear A, pull with PUL32.
; A should be restored to the original value.
    .org $1000
    .M32
    LDA #$DEADBEEF
    PSH32 A
    LDA #$00000000
    PUL32 A               ; Should restore $DEADBEEF
    STP
