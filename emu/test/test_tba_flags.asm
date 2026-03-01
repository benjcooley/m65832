; Test TBA does NOT set N flag in 32-bit mode
; Transfers are flagless in 32-bit mode (OoO pipeline friendly)
    .org $1000
    .M32

    CLC                   ; Clear carry, leaves N=0
    LDA #$00000000
    CMP #$00000000        ; Z=1, N=0
    SB #$80000000         ; B = $80000000 (negative)
    TBA                   ; A = B, should NOT set N flag in 32-bit mode
    STP
