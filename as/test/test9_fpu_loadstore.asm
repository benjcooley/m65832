; Test FPU load/store addressing modes
    .org $1000

    LDF F0, $20         ; dp
    STF F1, $1234       ; abs16
    LDF F2, (R0)        ; register indirect
    STF F3, (R1)        ; register indirect
    LDF.S F6, (R2)      ; single-precision register indirect
    STF.S F7, (R3)      ; single-precision register indirect
    LDF F4, $00123456   ; abs32
    STF F5, $00ABCDEF   ; abs32

    STP
