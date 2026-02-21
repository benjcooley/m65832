; Test: Long addressing opcodes must trap as ILLEGAL_OP in W=11 (32-bit mode)
; In 32-bit mode, the cc=11 bbb=011 and bbb=111 long addressing modes
; are reserved (replaced by extended ALU). They must trap as illegal.
;
; We test LDA long ($AF) - if it traps, the emulator will stop
; before reaching the STP, and A will still hold the sentinel value.
    .org $1000
    .M32

    LDA #$BAADF00D          ; Sentinel - should remain if trap fires
    .byte $AF               ; LDA long opcode
    .byte $00, $20, $00     ; 3-byte long address (won't be used)
    ; If we get here, the long opcode didn't trap - FAIL
    LDA #$00000000
    STP
