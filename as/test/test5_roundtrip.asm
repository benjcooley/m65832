; Round-trip test - assemble, disassemble, reassemble

    .ORG $8000
    .M16
    .X16

; Standard instructions
    NOP
    LDA #$1234
    LDX #$5678
    STA $10
    STA $1000
    STA $1000,X
    JMP DONE

; Branches
    BEQ SKIP
    BNE SKIP
SKIP:
    BRA DONE

; Long addressing
    LDA $123456
    STA $234567,X
    JSL $345678

; Extended instructions (assembled as bytes)
    .BYTE $02, $00, $20     ; MUL $20
    .BYTE $02, $50          ; FENCE
    .BYTE $02, $C0          ; FADD.S

; WID prefix with 32-bit immediate (assembled as bytes)
    .BYTE $42, $A9, $78, $56, $34, $12  ; WID LDA #$12345678

DONE:
    RTS
