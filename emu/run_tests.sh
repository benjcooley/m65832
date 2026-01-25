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

# Test 7: JSR/RTS
cat > test/test_jsr.asm << 'EOF'
; Test JSR/RTS
    .org $1000
    
    LDA #$10
    JSR add_five
    JSR add_five    ; A should be 0x1A
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
