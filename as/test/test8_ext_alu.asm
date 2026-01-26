; Test 8: Extended ALU Instructions ($02 $80-$97)
; Tests the new extended ALU opcode system with mode byte encoding
; Format: $02 [opcode] [mode] [dest_dp?] [operand...]
; Mode byte: [size:2][target:1][addr_mode:5]
;
; Syntax:
;   LDA.B/W src    - Traditional mnemonic with size suffix (A-targeted)
;   LD.B/W Rn, src - LD/ST for register-targeted (R0-R63)

    .org $8000

    .M32                    ; 32-bit mode
    .X32

; ==== Extended ALU - BYTE operations (.B suffix) ====
; Size = 00 (BYTE)
byte_ops:
    ; LDA.B - Load byte into A (opcode $80)
    LDA.B #$42             ; $02 $80 [mode=00|0|11000] [imm8]
    LDA.B R0               ; $02 $80 [mode=00|0|00000] [dp=$00]
    
    ; LD.B - Load byte into Rn (opcode $80 with target=1)
    LD.B R4, #$55          ; $02 $80 [mode=00|1|11000] [$10] [imm8]
    LD.B R4, R0            ; $02 $80 [mode=00|1|00000] [$10] [dp=$00]
    
    ; STA.B - Store byte from A (opcode $81)
    STA.B R8               ; $02 $81 [mode=00|0|00000] [dp=$20]
    
    ; ADC.B - Add with carry byte (opcode $82)
    ADC.B #$10             ; $02 $82 [mode=00|0|11000] [imm8]
    ADC.B R0               ; $02 $82 [mode=00|0|00000] [dp]
    
    ; SBC.B - Subtract with carry byte (opcode $83)
    SBC.B #$05             ; $02 $83 [mode=00|0|11000] [imm8]
    SBC.B R0               ; $02 $83 [mode=00|0|00000] [dp]
    
    ; AND.B - Logical AND byte (opcode $84)
    AND.B #$0F             ; $02 $84 [mode=00|0|11000] [imm8]
    AND.B R0               ; $02 $84 [mode=00|0|00000] [dp]
    
    ; ORA.B - Logical OR byte (opcode $85)
    ORA.B #$F0             ; $02 $85 [mode=00|0|11000] [imm8]
    ORA.B R0               ; $02 $85 [mode=00|0|00000] [dp]
    
    ; EOR.B - Exclusive OR byte (opcode $86)
    EOR.B #$AA             ; $02 $86 [mode=00|0|11000] [imm8]
    EOR.B R0               ; $02 $86 [mode=00|0|00000] [dp]
    
    ; CMP.B - Compare byte (opcode $87)
    CMP.B #$42             ; $02 $87 [mode=00|0|11000] [imm8]
    CMP.B R0               ; $02 $87 [mode=00|0|00000] [dp]

; ==== Extended ALU - WORD operations (.W suffix) ====
; Size = 01 (WORD)
word_ops:
    ; LDA.W - Load word into A (opcode $80)
    LDA.W #$1234           ; $02 $80 [mode=01|0|11000] [imm16]
    LDA.W R0               ; $02 $80 [mode=01|0|00000] [dp]
    
    ; LD.W - Load word into Rn (opcode $80 with target=1)
    LD.W R4, #$ABCD        ; $02 $80 [mode=01|1|11000] [$10] [imm16]
    
    ; STA.W - Store word from A (opcode $81)
    STA.W R8               ; $02 $81 [mode=01|0|00000] [dp]
    
    ; ADC.W - Add with carry word (opcode $82)
    ADC.W #$0100           ; $02 $82 [mode=01|0|11000] [imm16]
    ADC.W R0               ; $02 $82 [mode=01|0|00000] [dp]
    
    ; SBC.W - Subtract with carry word (opcode $83)
    SBC.W #$0050           ; $02 $83 [mode=01|0|11000] [imm16]
    
    ; AND.W - Logical AND word (opcode $84)
    AND.W #$00FF           ; $02 $84 [mode=01|0|11000] [imm16]
    
    ; ORA.W - Logical OR word (opcode $85)
    ORA.W #$FF00           ; $02 $85 [mode=01|0|11000] [imm16]
    
    ; EOR.W - Exclusive OR word (opcode $86)
    EOR.W #$5555           ; $02 $86 [mode=01|0|11000] [imm16]
    
    ; CMP.W - Compare word (opcode $87)
    CMP.W #$1234           ; $02 $87 [mode=01|0|11000] [imm16]

; ==== Extended ALU - BIT/TSB/TRB (opcode $88-$8A) ====
bit_ops:
    BIT.B #$80             ; $02 $88 - BIT byte immediate
    BIT.W #$8000           ; $02 $88 - BIT word immediate
    TSB.B R0               ; $02 $89 - Test and Set Bits byte
    TSB.W R0               ; $02 $89 - Test and Set Bits word
    TRB.B R0               ; $02 $8A - Test and Reset Bits byte
    TRB.W R0               ; $02 $8A - Test and Reset Bits word

; ==== Extended ALU - INC/DEC (opcode $8B-$8C) ====
incdec_ops:
    INC.B A                ; $02 $8B - Increment byte accumulator
    INC.W A                ; $02 $8B - Increment word accumulator
    DEC.B A                ; $02 $8C - Decrement byte accumulator
    DEC.W A                ; $02 $8C - Decrement word accumulator

; ==== Extended ALU - Shifts/Rotates (opcode $8D-$90) ====
shift_ops:
    ASL.B A                ; $02 $8D - Arithmetic shift left byte
    ASL.W A                ; $02 $8D - Arithmetic shift left word
    LSR.B A                ; $02 $8E - Logical shift right byte
    LSR.W A                ; $02 $8E - Logical shift right word
    ROL.B A                ; $02 $8F - Rotate left byte
    ROL.W A                ; $02 $8F - Rotate left word
    ROR.B A                ; $02 $90 - Rotate right byte
    ROR.W A                ; $02 $90 - Rotate right word

; ==== Extended ALU - STZ (opcode $97) ====
stz_ops:
    STZ.B R0               ; $02 $97 - Store zero byte to DP
    STZ.W R0               ; $02 $97 - Store zero word to DP

; ==== Register-targeted operations with LD/ST ====
reg_target:
    LD.B R0, #$11          ; Register R0 target, byte immediate
    LD.B R1, #$22          ; Register R1 target, byte immediate
    LD.W R2, #$3344        ; Register R2 target, word immediate
    LD.B R63, #$FF         ; Register R63 target, byte (max register)
    
    ; Register-targeted ALU ops
    LD.B R4, R0            ; Load R0 into R4 (byte)
    LD.W R8, R4            ; Load R4 into R8 (word)
    
    ; Store register to DP
    ST.B R4, R0            ; Store R4 to R0 location (byte)
    ST.W R8, R4            ; Store R8 to R4 location (word)

; ==== Various addressing modes ====
addr_modes:
    ; DP indexed
    LDA.B R0,X             ; DP,X
    LDA.W R0,Y             ; DP,Y
    
    ; DP indirect
    LDA.B (R8)             ; (DP)
    LDA.W (R8),Y           ; (DP),Y
    LDA.B (R8,X)           ; (DP,X)
    
    ; Stack relative
    LDA.B $10,S            ; SR (not 4-byte aligned OK for SR)
    LDA.W ($10,S),Y        ; (SR),Y

done:
    NOP
    STP

; Expected encodings (partial):
; LDA.B #$42    -> $02 $80 $18 $42         (mode=$18: size=00, target=0, addr=11000)
; LD.B R4, #$55 -> $02 $80 $38 $10 $55     (mode=$38: size=00, target=1, addr=11000, dest=$10)
; LDA.W #$1234  -> $02 $80 $58 $34 $12     (mode=$58: size=01, target=0, addr=11000)
; ADC.B #$10    -> $02 $82 $18 $10         (mode=$18)
; INC.B A       -> $02 $8B $00             (mode=$00: size=00, unary op on A)
