; test_stack32.asm - Comprehensive 32-bit stack operations test
;
; Tests all push/pop instructions in 32-bit native mode to verify
; they push/pull 32-bit values (4 bytes each).
;
; Expected behavior in 32-bit mode:
;   PHA/PLA     - 32-bit (4 bytes)
;   PHX/PLX     - 32-bit (4 bytes)
;   PHY/PLY     - 32-bit (4 bytes)
;   PHD/PLD     - 32-bit (4 bytes)
;   PHB/PLB     - 32-bit (4 bytes)
;   PHP/PLP     - 8-bit  (1 byte, P register)

    .org $1000

start:
    ; Enter native 32-bit mode
    CLC
    XCE                 ; Clear emulation mode
    REP #$30            ; Clear M and X flags (but we're in 32-bit mode now)
    
    ; Set B=0 for absolute addressing (B+$addr)
    .byte $02, $22      ; SB #imm32
    .dword $00000000
    
    ; Set up known stack pointer
    LDA #$0000FFFC      ; Stack at top of first 64KB
    TCS                 ; Transfer A to SP
    
    ; =========================================================================
    ; Test 1: PHA/PLA (32-bit A register)
    ; =========================================================================
test_pha_pla:
    LDA #$DEADBEEF      ; Load 32-bit value
    PHA                 ; Push 32-bit A (should use 4 bytes on stack)
    LDA #$00000000      ; Clear A
    PLA                 ; Pull 32-bit A
    CMP #$DEADBEEF      ; Verify
    BNE fail
    
    ; =========================================================================
    ; Test 2: PHX/PLX (32-bit X register)
    ; =========================================================================
test_phx_plx:
    LDX #$12345678      ; Load 32-bit value
    PHX                 ; Push 32-bit X
    LDX #$00000000      ; Clear X
    PLX                 ; Pull 32-bit X
    CPX #$12345678      ; Verify
    BNE fail
    
    ; =========================================================================
    ; Test 3: PHY/PLY (32-bit Y register)
    ; =========================================================================
test_phy_ply:
    LDY #$CAFEBABE      ; Load 32-bit value
    PHY                 ; Push 32-bit Y
    LDY #$00000000      ; Clear Y
    PLY                 ; Pull 32-bit Y
    CPY #$CAFEBABE      ; Verify
    BNE fail
    
    ; =========================================================================
    ; Test 4: PHD/PLD (32-bit D register)
    ; =========================================================================
test_phd_pld:
    LDA #$00002000      ; Direct page at $2000
    TCD                 ; Transfer A to D
    PHD                 ; Push 32-bit D
    LDA #$00000000
    TCD                 ; Clear D
    PLD                 ; Pull 32-bit D
    TDC                 ; Transfer D back to A
    CMP #$00002000      ; Verify
    BNE fail
    
    ; Reset D to 0
    LDA #$00000000
    TCD
    
    ; =========================================================================
    ; Test 5: PHB/PLB (32-bit B register) - M65832 extension
    ; Note: B affects absolute addressing, so we must be careful!
    ; =========================================================================
test_phb_plb:
    ; First, ensure B=0 and save the initial SP to memory
    .byte $02, $22      ; SB #imm32
    .dword $00000000    ; B = 0
    
    TSC
    STA B+$3020         ; Save initial SP (with B=0, stores to $3020)
    
    ; Now set B to test value
    .byte $02, $22
    .dword $00010000    ; B = $00010000
    
    PHB                 ; Push 32-bit B (should push $00010000, 4 bytes)
    
    ; B is still $10000 here, save SP to same B-relative offset
    ; Actually we want to read/compare without B affecting things
    ; So first save new SP, then reset B to compare
    TSC                 ; A = new SP
    PHA                 ; Save new SP on stack
    
    ; Reset B for consistent addressing
    .byte $02, $22
    .dword $00000000    ; B = 0
    
    ; Get the saved new SP
    PLA                 ; A = new SP  
    STA B+$3024         ; Store it (with B=0)
    
    ; Verify SP moved by 4 bytes (32-bit PHB)
    LDA B+$3020         ; Initial SP (stored when B=0)
    SEC
    SBC B+$3024         ; New SP (also stored when B=0)
    CMP #$00000004      ; Should be 4 bytes
    BNE fail
    
    ; Now test PLB - the stack still has $00010000 from our PHB
    PLB                 ; Pull 32-bit B (should restore $00010000)
    
    ; Verify B was restored by pushing it again and checking
    PHB                 ; Push B again
    
    ; Reset B to 0 for addressing
    .byte $02, $22
    .dword $00000000
    
    PLA                 ; A = what was in B
    CMP #$00010000      ; Should be $00010000
    BNE fail
    
    ; =========================================================================
    ; Test 6: Stack depth verification
    ; Each 32-bit push should move SP by 4 bytes
    ; =========================================================================
test_stack_depth:
    ; Reset stack
    LDA #$0000FFFC
    TCS
    TSC                 ; Get SP
    STA B+$3000         ; Save initial SP
    
    LDA #$11111111
    PHA                 ; Push 4 bytes
    TSC
    STA B+$3004         ; Save SP after 1 push
    
    LDA #$22222222
    PHA                 ; Push 4 more bytes
    TSC
    STA B+$3008         ; Save SP after 2 pushes
    
    ; Verify SP moved by 4 for each push
    LDA B+$3000         ; Initial SP
    SEC
    SBC B+$3004         ; SP after 1 push
    CMP #$00000004      ; Should be 4
    BNE fail
    
    LDA B+$3004         ; SP after 1 push
    SEC
    SBC B+$3008         ; SP after 2 pushes
    CMP #$00000004      ; Should be 4
    BNE fail
    
    ; Clean up stack
    PLA
    PLA
    
    ; =========================================================================
    ; Test 7: PHP/PLP should remain 8-bit
    ; =========================================================================
test_php_plp:
    LDA #$0000FFFC
    TCS                 ; Reset stack
    TSC
    STA B+$3010         ; Save initial SP
    
    SEC                 ; Set carry
    PHP                 ; Push P (should be 1 byte only)
    TSC
    STA B+$3014         ; Save SP after PHP
    
    ; Verify SP moved by only 1 byte
    LDA B+$3010
    SEC
    SBC B+$3014
    CMP #$00000001      ; Should be 1 (P is 8-bit)
    BNE fail
    
    CLC                 ; Clear carry
    PLP                 ; Pull P (should restore carry)
    BCC fail            ; Carry should be set
    
    ; =========================================================================
    ; Test 8: Cross-register push/pull order (LIFO)
    ; =========================================================================
test_lifo:
    LDA #$0000FFFC
    TCS                 ; Reset stack
    
    LDA #$AAAAAAAA
    LDX #$BBBBBBBB
    LDY #$CCCCCCCC
    
    PHA                 ; Push A
    PHX                 ; Push X
    PHY                 ; Push Y
    
    ; Clear all
    LDA #$00000000
    LDX #$00000000
    LDY #$00000000
    
    ; Pull in reverse order (LIFO)
    PLY                 ; Should get $CCCCCCCC
    PLX                 ; Should get $BBBBBBBB
    PLA                 ; Should get $AAAAAAAA
    
    CPY #$CCCCCCCC
    BNE fail
    CPX #$BBBBBBBB
    BNE fail
    CMP #$AAAAAAAA
    BNE fail
    
    ; =========================================================================
    ; All tests passed
    ; =========================================================================
pass:
    LDA #$00000001      ; Success code
    STA B+$00           ; Store result at $0000
    STP                 ; Stop
    
fail:
    LDA #$00000000      ; Failure code
    STA B+$00           ; Store result at $0000
    STP                 ; Stop
