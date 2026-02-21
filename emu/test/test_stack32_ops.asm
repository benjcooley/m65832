; Test 32-bit stack operations in M65832 32-bit mode
; Tests: PHA/PLA, PHX/PLX, PHY/PLY, PHP/PLP, PHD/PLD, PHB, JSR/RTS
;
; All stack ops should push/pull 4 bytes in 32-bit mode

    .org $1000

start:
    ; Enter 32-bit native mode
    ; Enter 32-bit mode (W=00 → W=11)
    .byte $02, $61, $03     ; SEPE #$03 - set W1+W0 (enter 32-bit mode)
    
    ; Initialize stack pointer to a known location
    lda #$0000FFFC
    tcs
    
    ; Also set B=0 for consistent memory addressing
    .byte $02, $22          ; SB #imm32
    .dword $00000000

    ; =========================================
    ; Test 1: PHA/PLA - should push/pull 4 bytes
    ; =========================================
test_pha_pla:
    tsc                     ; A = SP (should be $FFFC)
    sta B+$3000             ; Save initial SP
    
    lda #$DEADBEEF          ; Test value
    pha                     ; Push 4 bytes
    
    tsc                     ; A = SP (should be $FFF8)
    sta B+$3004             ; Save SP after push
    
    lda #$00000000          ; Clear A
    pla                     ; Pull 4 bytes
    
    tsc                     ; A = SP (should be back to $FFFC)
    sta B+$3008             ; Save SP after pull
    
    ; Verify SP moved by 4
    lda B+$3000
    sec
    sbc B+$3004
    cmp #$00000004
    bne fail
    
    ; Verify SP restored
    lda B+$3000
    cmp B+$3008
    bne fail
    
    ; =========================================
    ; Test 2: PHX/PLX - should push/pull 4 bytes
    ; =========================================
test_phx_plx:
    ldx #$12345678
    tsc
    sta B+$3010             ; Save initial SP
    
    phx                     ; Push 4 bytes
    
    tsc
    sta B+$3014             ; Save SP after push
    
    ldx #$00000000          ; Clear X
    plx                     ; Pull 4 bytes
    
    tsc
    sta B+$3018             ; Save SP after pull
    
    ; Verify X was restored
    cpx #$12345678
    bne fail
    
    ; Verify SP moved by 4
    lda B+$3010
    sec
    sbc B+$3014
    cmp #$00000004
    bne fail

    ; =========================================
    ; Test 3: PHY/PLY - should push/pull 4 bytes
    ; =========================================
test_phy_ply:
    ldy #$AABBCCDD
    tsc
    sta B+$3020             ; Save initial SP
    
    phy                     ; Push 4 bytes
    
    tsc
    sta B+$3024             ; Save SP after push
    
    ldy #$00000000          ; Clear Y
    ply                     ; Pull 4 bytes
    
    ; Verify Y was restored
    cpy #$AABBCCDD
    bne fail
    
    ; Verify SP moved by 4
    lda B+$3020
    sec
    sbc B+$3024
    cmp #$00000004
    bne fail
    
    ; =========================================
    ; Test 4: PHP/PLP - should push/pull 4 bytes
    ; =========================================
test_php_plp:
    tsc
    sta B+$3030             ; Save initial SP
    
    php                     ; Push P (4 bytes in 32-bit mode)
    
    tsc
    sta B+$3034             ; Save SP after push
    
    plp                     ; Pull P (4 bytes)
    
    ; Verify SP moved by 4
    lda B+$3030
    sec
    sbc B+$3034
    cmp #$00000004
    bne fail

    ; =========================================
    ; Test 5: PHD/PLD - should push/pull 4 bytes
    ; =========================================
test_phd_pld:
    ; Set D to a test value
    lda #$11223344
    tcd                     ; D = $11223344
    
    tsc
    sta B+$3040             ; Save initial SP
    
    phd                     ; Push D (4 bytes)
    
    tsc
    sta B+$3044             ; Save SP after push
    
    lda #$00000000
    tcd                     ; Clear D
    
    pld                     ; Pull D (4 bytes)
    
    ; Verify D was restored - transfer to A to check
    tdc
    cmp #$11223344
    bne fail
    
    ; Verify SP moved by 4
    lda B+$3040
    sec
    sbc B+$3044
    cmp #$00000004
    bne fail

    ; =========================================
    ; Test 6: PHB/PLB - should push/pull 4 bytes (full 32-bit B)
    ; Keep B=0 throughout for consistent memory addressing
    ; =========================================
test_phb_plb:
    ; Save initial SP (B=0)
    tsc
    sta B+$3060
    
    ; Set B to test value and push it
    .byte $02, $22          ; SB #imm32
    .dword $CAFEBABE
    
    phb                     ; Push B ($CAFEBABE) - 4 bytes
    
    ; Reset B to 0 immediately for consistent addressing
    .byte $02, $22
    .dword $00000000
    
    tsc
    sta B+$3064             ; Save SP after push
    
    ; Verify SP moved by 4 bytes
    lda B+$3060
    sec
    sbc B+$3064
    cmp #$00000004
    bne fail
    
    ; Now test PLB - pull the value back
    plb                     ; Pull 4 bytes into B (should be $CAFEBABE)
    
    ; Push it again so we can verify via PLA
    phb
    
    ; Reset B to 0 for PLA
    .byte $02, $22
    .dword $00000000
    
    pla                     ; A = value that was in B
    cmp #$CAFEBABE
    bne fail

    ; =========================================
    ; Test 7: JSR/RTS - should push/pull 4 bytes (32-bit call/return)
    ; In 32-bit mode, JSR pushes 32-bit return address
    ; Note: JSL is illegal in 32-bit mode
    ; =========================================
test_jsr_rts:
    tsc
    sta B+$3050             ; Save SP before JSR
    
    ; JSR B+$1200 (subroutine) - JSR uses B-relative addressing in 32-bit mode
    ; Manual encoding: JSR $1200 = $20 $00 $12
    .byte $20               ; JSR opcode
    .byte $00, $12          ; Address: $1200 (B-relative, 16-bit)
    
    tsc
    sta B+$3058             ; Save SP after RTS
    
    ; Verify SP returned to same value
    lda B+$3050
    cmp B+$3058
    bne fail
    
    ; Check stored values match
    lda B+$3050
    sec
    sbc B+$3054
    cmp #$00000004          ; JSR should have pushed 4 bytes in 32-bit mode
    bne fail
    
    ; =========================================
    ; All tests passed!
    ; =========================================
pass:
    lda #$00000001
    sta B+$0200             ; Success marker
    stp

fail:
    lda #$FFFFFFFF
    sta B+$0200             ; Failure marker
    stp

    ; Subroutine at $1200 (well past the main code)
    .org $1200
subroutine:
    tsc
    sta B+$3054             ; Save SP inside subroutine (after JSR)
    rts                     ; Return from subroutine (32-bit pull in 32-bit mode)
