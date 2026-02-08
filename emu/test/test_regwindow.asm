; Test: Register window (R=1) does NOT touch physical RAM
;
; Strategy:
;   1. Write sentinel values to RAM at DP $00-$3C (R0-R15 region)
;   2. Enable register window (RSET)
;   3. Write different values to R0-R15 via DP
;   4. Read R0-R15 back, verify they hold the NEW values (not RAM sentinels)
;   5. Disable register window (RCLR)
;   6. Read RAM at $00-$3C, verify sentinels are UNCHANGED
;   7. If all checks pass, A = $00000001 (PASS)
;      If any check fails, A = $DEADBEEF (FAIL)
;
; Runs in 32-bit native mode. Uses --stop-on-brk.

    .ORG $1000
    .M32
    .X32

    ; Enter 32-bit native mode
    CLC
    XCE
    REP #$30
    SEPE #$A0

    ; Set D=0 so DP addresses map to $0000+
    LDA #0
    TCD

    ; ----- Step 1: Write sentinels to RAM $00-$3C -----
    ; (R flag is OFF, so DP accesses go to RAM)
    LDA #$AA000000
    STA $00             ; RAM[$00] = $AA000000
    LDA #$AA000001
    STA $04             ; RAM[$04] = $AA000001
    LDA #$AA000002
    STA $08             ; RAM[$08] = $AA000002
    LDA #$AA000003
    STA $0C             ; RAM[$0C] = $AA000003
    LDA #$AA000004
    STA $10             ; RAM[$10] = $AA000004
    LDA #$AA000005
    STA $14             ; RAM[$14] = $AA000005
    LDA #$AA000006
    STA $18             ; RAM[$18] = $AA000006
    LDA #$AA000007
    STA $1C             ; RAM[$1C] = $AA000007

    ; ----- Step 2: Enable register window -----
    RSET

    ; ----- Step 3: Write different values to R0-R7 via DP -----
    ; (R=1, so these should go to registers, NOT RAM)
    LDA #$BB000000
    STA $00             ; R0 = $BB000000
    LDA #$BB000001
    STA $04             ; R1 = $BB000001
    LDA #$BB000002
    STA $08             ; R2 = $BB000002
    LDA #$BB000003
    STA $0C             ; R3 = $BB000003
    LDA #$BB000004
    STA $10             ; R4 = $BB000004
    LDA #$BB000005
    STA $14             ; R5 = $BB000005
    LDA #$BB000006
    STA $18             ; R6 = $BB000006
    LDA #$BB000007
    STA $1C             ; R7 = $BB000007

    ; ----- Step 4: Read registers back, verify -----
    LDA $00
    CMP #$BB000000
    BNE fail
    LDA $04
    CMP #$BB000001
    BNE fail
    LDA $08
    CMP #$BB000002
    BNE fail
    LDA $0C
    CMP #$BB000003
    BNE fail
    LDA $10
    CMP #$BB000004
    BNE fail
    LDA $14
    CMP #$BB000005
    BNE fail
    LDA $18
    CMP #$BB000006
    BNE fail
    LDA $1C
    CMP #$BB000007
    BNE fail

    ; ----- Step 5: Disable register window -----
    RCLR

    ; ----- Step 6: Read RAM, verify sentinels unchanged -----
    ; (R=0, so DP accesses go to RAM again)
    LDA $00
    CMP #$AA000000
    BNE fail
    LDA $04
    CMP #$AA000001
    BNE fail
    LDA $08
    CMP #$AA000002
    BNE fail
    LDA $0C
    CMP #$AA000003
    BNE fail
    LDA $10
    CMP #$AA000004
    BNE fail
    LDA $14
    CMP #$AA000005
    BNE fail
    LDA $18
    CMP #$AA000006
    BNE fail
    LDA $1C
    CMP #$AA000007
    BNE fail

    ; ----- PASS -----
    LDA #$00000001
    STP

fail:
    LDA #$DEADBEEF
    STP
