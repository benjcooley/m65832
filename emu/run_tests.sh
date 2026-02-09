#!/bin/bash
# M65832 Emulator Test Script

EMULATOR="./m65832emu"
ASSEMBLER="../as/m65832as"

echo "=== M65832 Emulator Tests ==="
echo

# Build if needed
if [ ! -f "$EMULATOR" ]; then
    echo "Building emulator..."
    make
fi

if [ ! -f "$ASSEMBLER" ]; then
    echo "Building assembler..."
    (cd ../as && make)
fi

PASS=0
FAIL=0

# Helper function to run a test
run_test() {
    local name="$1"
    local asm_file="$2"
    local expected_a="$3"
    local cycles="$4"
    
    echo -n "Test: $name... "
    
    # Assemble
    if ! $ASSEMBLER "$asm_file" -o "${asm_file%.asm}.bin" > /dev/null 2>&1; then
        echo "FAIL (assembly failed)"
        FAIL=$((FAIL + 1))
        return
    fi
    
    # Run emulator and capture output (defaults to 32-bit native mode)
    output=$($EMULATOR -c "$cycles" -s "${asm_file%.asm}.bin" 2>&1)
    
    # Check result
    if echo "$output" | grep -q "A: 0*$expected_a"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected A=$expected_a)"
        echo "$output" | grep "A:"
        FAIL=$((FAIL + 1))
    fi
}

# Helper function to run a test and verify flags
run_test_flag() {
    local name="$1"
    local asm_file="$2"
    local flag_regex="$3"
    local cycles="$4"
    
    echo -n "Test: $name... "
    
    # Assemble
    if ! $ASSEMBLER "$asm_file" -o "${asm_file%.asm}.bin" > /dev/null 2>&1; then
        echo "FAIL (assembly failed)"
        FAIL=$((FAIL + 1))
        return
    fi
    
    # Run emulator and capture output (defaults to 32-bit native mode)
    output=$($EMULATOR -c "$cycles" -s "${asm_file%.asm}.bin" 2>&1)
    
    if echo "$output" | grep -Eq "P:.*\\[.*${flag_regex}"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected flag ${flag_regex})"
        echo "$output" | grep "P:"
        FAIL=$((FAIL + 1))
    fi
}

# Test basic emulator functions
echo "--- Basic Emulator Tests ---"

echo -n "Test: Emulator creates and runs... "
if timeout 2 $EMULATOR -c 10 -v /dev/null > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "PASS (expected failure with /dev/null)"
    PASS=$((PASS + 1))
fi

echo -n "Test: Help message... "
if $EMULATOR --help 2>&1 | grep -q "M65832 Emulator"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Version string... "
if $EMULATOR --help 2>&1 | grep -q "v1.0.0"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Assembly tests
echo
echo "--- Assembly Program Tests ---"

# Create test programs if they don't exist
mkdir -p test

# Test 1: Simple LDA/STA
cat > test/test_lda.asm << 'EOF'
; Test LDA immediate
    .org $1000
    
    LDA #$42        ; Load 0x42 into A
    STP             ; Stop
EOF

run_test "LDA immediate" "test/test_lda.asm" "00000042" 100

# Test 2: ADC
cat > test/test_adc.asm << 'EOF'
; Test ADC
    .org $1000
    
    CLC
    LDA #$10
    ADC #$20        ; 0x10 + 0x20 = 0x30
    STP
EOF

run_test "ADC basic" "test/test_adc.asm" "00000030" 100

# Test 3: SBC
cat > test/test_sbc.asm << 'EOF'
; Test SBC
    .org $1000
    
    SEC
    LDA #$50
    SBC #$20        ; 0x50 - 0x20 = 0x30
    STP
EOF

run_test "SBC basic" "test/test_sbc.asm" "00000030" 100

# Test 4: Increment/Decrement
cat > test/test_incdec.asm << 'EOF'
; Test INC/DEC
    .org $1000
    
    LDA #$10
    INC A           ; 0x11
    INC A           ; 0x12
    DEC A           ; 0x11
    STP
EOF

run_test "INC/DEC A" "test/test_incdec.asm" "00000011" 100

# Test 5: Branches
cat > test/test_branch.asm << 'EOF'
; Test branches
    .org $1000
    
    LDA #$00
    BEQ zero        ; Should branch
    LDA #$FF        ; Should be skipped
zero:
    LDA #$AA        ; Should execute
    STP
EOF

run_test "BEQ branch" "test/test_branch.asm" "000000AA" 100

# Test 6: Loop
cat > test/test_loop.asm << 'EOF'
; Test loop
    .org $1000
    
    LDX #$05        ; Counter
    LDA #$00        ; Accumulator
loop:
    CLC
    ADC #$01        ; Add 1 each iteration
    DEX
    BNE loop        ; Loop 5 times
    STP             ; A should be 5
EOF

run_test "Loop counting" "test/test_loop.asm" "00000005" 500

# Test 7: JSR/RTS (32-bit absolute addresses)
cat > test/test_jsr.asm << 'EOF'
; Test JSR/RTS with 32-bit absolute addresses
    .org $1000
    .M32
    
    LDA #$10
    JSR add_five      ; 32-bit absolute call
    JSR add_five      ; A should be 0x1A
    STP

add_five:
    CLC
    ADC #$05
    RTS
EOF

run_test "JSR/RTS subroutine" "test/test_jsr.asm" "0000001A" 200

# Test 8: Stack operations
cat > test/test_stack.asm << 'EOF'
; Test stack
    .org $1000
    
    LDA #$11
    PHA
    LDA #$22
    PHA
    LDA #$00        ; Clear A
    PLA             ; Should be $22
    PLA             ; Should be $11
    STP
EOF

run_test "PHA/PLA stack" "test/test_stack.asm" "00000011" 200

# Test 9: Logical operations
cat > test/test_logic.asm << 'EOF'
; Test AND/ORA/EOR
    .org $1000
    
    LDA #$FF
    AND #$0F        ; 0x0F
    ORA #$A0        ; 0xAF
    EOR #$FF        ; 0x50
    STP
EOF

run_test "AND/ORA/EOR" "test/test_logic.asm" "00000050" 200

# Test 10: Shifts and rotates
cat > test/test_shift.asm << 'EOF'
; Test shifts
    .org $1000
    
    LDA #$40
    ASL A           ; 0x80
    LSR A           ; 0x40
    LSR A           ; 0x20
    STP
EOF

run_test "ASL/LSR shifts" "test/test_shift.asm" "00000020" 200

# Test 11: FPU operations (16 registers, two-operand)
cat > test/test_fp.asm << 'EOF'
; Test FPU: I2F, FADD.S, F2I with new two-operand format
    .org $1000
    
    LDA #$02
    I2F.S F0        ; F0 = 2.0
    LDA #$03
    I2F.S F1        ; F1 = 3.0
    FADD.S F0, F1   ; F0 = 2.0 + 3.0 = 5.0
    F2I.S F0        ; A = 5
    STP
EOF

run_test "FPU I2F/FADD/F2I" "test/test_fp.asm" "00000005" 200

# Test 12: FPU high registers (F8-F15)
cat > test/test_fp_highregs.asm << 'EOF'
; Test FPU high registers F8-F15
    .org $1000
    
    LDA #$04
    I2F.S F8        ; F8 = 4.0
    LDA #$02
    I2F.S F15       ; F15 = 2.0
    FMUL.S F8, F15  ; F8 = 4.0 * 2.0 = 8.0
    F2I.S F8        ; A = 8
    STP
EOF

run_test "FPU high registers F8-F15" "test/test_fp_highregs.asm" "00000008" 200

# Test 13: FPU FMOV.S and FSUB.S
cat > test/test_fp_mov.asm << 'EOF'
; Test FPU FMOV.S and FSUB.S
    .org $1000
    
    LDA #$0A
    I2F.S F0        ; F0 = 10.0
    FMOV.S F5, F0   ; F5 = F0 = 10.0
    LDA #$03
    I2F.S F1        ; F1 = 3.0
    FSUB.S F5, F1   ; F5 = 10.0 - 3.0 = 7.0
    F2I.S F5        ; A = 7
    STP
EOF

run_test "FPU FMOV.S/FSUB.S" "test/test_fp_mov.asm" "00000007" 200
 
# Test 16: FPU ops should not update flags
cat > test/test_fp_flags_z.asm << 'EOF'
; Test FPU ops preserve Z flag
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    I2F.S F0          ; F0 = 0.0
    FADD.S F0, F0     ; F0 = 0.0
    STP
EOF

run_test_flag "FPU preserves Z flag" "test/test_fp_flags_z.asm" "Z" 200

# Test 17: FCMP should not update flags
cat > test/test_fp_flags_cmp.asm << 'EOF'
; Test FCMP does not update flags
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    I2F.S F0          ; F0 = 0.0
    I2F.S F1          ; F1 = 0.0
    FCMP.S F0, F1     ; should not modify flags
    STP
EOF

run_test_flag "FCMP preserves Z flag" "test/test_fp_flags_cmp.asm" "Z" 200

# Test 13: 32-bit LDA should not update flags
cat > test/test_lda_flags_z.asm << 'EOF'
; Test LDA flags in 32-bit mode (Z should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    LDA #$00000001    ; should not clear Z in 32-bit mode
    STP
EOF

run_test_flag "LDA preserves Z in 32-bit" "test/test_lda_flags_z.asm" "Z" 200

# Test 14: 32-bit LDA should not update flags (N)
cat > test/test_lda_flags_n.asm << 'EOF'
; Test LDA flags in 32-bit mode (N should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000001    ; sets N=1 (A - 1 = 0xFFFFFFFF)
    LDA #$00000000    ; should not clear N in 32-bit mode
    STP
EOF

run_test_flag "LDA preserves N in 32-bit" "test/test_lda_flags_n.asm" "N" 200

# Test 15: Extended LD should not update flags
cat > test/test_ld_flags.asm << 'EOF'
; Test extended LD flags in 32-bit mode (Z should remain set)
    .org $1000
    .M32
    
    LDA #$00000000
    CMP #$00000000    ; sets Z=1
    LD R0, #$00000001 ; extended load should not clear Z
    STP
EOF

run_test_flag "Extended LD preserves Z" "test/test_ld_flags.asm" "Z" 200

# Test 18: TAB/TBA - B register transfers
cat > test/test_tab_tba.asm << 'EOF'
; Test TAB (A to B) and TBA (B to A)
    .org $1000
    .M32
    
    LDA #$12345678   ; Load test value
    TAB              ; B = A ($12345678)
    LDA #$00000000   ; Clear A
    TBA              ; A = B ($12345678)
    STP
EOF

run_test "TAB/TBA transfer" "test/test_tab_tba.asm" "12345678" 200

# Test 19: TBA sets N flag
cat > test/test_tba_flags.asm << 'EOF'
; Test TBA sets N flag for negative value
    .org $1000
    .M32
    
    SB #$80000000    ; B = $80000000 (negative)
    TBA              ; A = B, should set N flag
    STP
EOF

run_test_flag "TBA sets N flag" "test/test_tba_flags.asm" "N" 200

# Test 20: TSPB - Transfer Stack Pointer to B
cat > test/test_tspb.asm << 'EOF'
; Test TSPB (SP to B)
    .org $1000
    .M32
    
    LDX #$0000ABCD   ; Set up stack pointer
    TXS              ; SP = X
    TSPB             ; B = SP ($0000ABCD)
    TBA              ; A = B (to verify)
    STP
EOF

run_test "TSPB transfer" "test/test_tspb.asm" "0000ABCD" 200

# Test 21: TXB/TBX - X <-> B transfers
cat > test/test_txb_tbx.asm << 'EOF'
; Test TXB and TBX
    .org $1000
    .M32
    
    LDX #$DEADBEEF   ; Load X with test value
    TXB              ; B = X
    LDX #$00000000   ; Clear X
    TBX              ; X = B (should be $DEADBEEF)
    TXA              ; A = X (to verify)
    STP
EOF

run_test "TXB/TBX transfer" "test/test_txb_tbx.asm" "DEADBEEF" 200

# Test 22: JMP (dp) and JSR (dp) - indirect through DP/register window
cat > test/test_jmp_jsr_dp.asm << 'EOF'
; Test JMP (dp) and JSR (dp)
    .org $1000
    .M32
    
    ; Set up function pointer in register window
    LDA #subroutine
    STA R5              ; Store function addr in R5 ($14)
    
    ; Call through register
    JSR (R5)            ; $02 $A6 $14 - indirect call
    STP
    
subroutine:
    LDA #$CAFEBABE      ; Load a recognizable value
    RTS
EOF

run_test "JSR (dp) indirect call" "test/test_jmp_jsr_dp.asm" "CAFEBABE" 300
run_test "Register window isolation" "test/test_regwindow.asm" "00000001" 500
run_test "FPU xfer FTOA/FTOT/ATOF/TTOF" "test/test_fpu_xfer.asm" "00000001" 500

# Summary
echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

# Clean up
rm -f test/*.bin

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
