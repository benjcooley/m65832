; XINC: flagless INC A - result correct, flags unchanged
    .org $1000
    .M32

    LDA #$00000000
    CMP #$00000000        ; Z=1
    LDA #$7FFFFFFF
    XINC A                ; A = $80000000; Z must remain, N must NOT be set
    STP
