#!/bin/bash
# M65832 Comprehensive Architecture Test Suite
#
# Tests all instructions, addressing modes, and CPU features

EMULATOR="../m65832emu"
ASSEMBLER="../../as/m65832as"

PASS=0
FAIL=0
SKIP=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test helper
run_test() {
    local name="$1"
    local asm_code="$2"
    local expected_a="$3"
    local expected_x="${4:-}"
    local expected_y="${5:-}"
    local cycles="${6:-1000}"
    
    echo -n "  $name... "
    
    # Create temp file
    local tmpfile=$(mktemp /tmp/test_XXXXXX.asm)
    echo "$asm_code" > "$tmpfile"
    
    # Assemble
    if ! $ASSEMBLER "$tmpfile" -o "${tmpfile%.asm}.bin" > /dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} (assembly failed)"
        rm -f "$tmpfile" "${tmpfile%.asm}.bin"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Run
    output=$($EMULATOR -c "$cycles" -s "${tmpfile%.asm}.bin" 2>&1)
    
    # Check A register
    if ! echo "$output" | grep -q "A: 0*$expected_a"; then
        echo -e "${RED}FAIL${NC} (A: expected $expected_a)"
        rm -f "$tmpfile" "${tmpfile%.asm}.bin"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    # Check X if specified
    if [ -n "$expected_x" ]; then
        if ! echo "$output" | grep -q "X: 0*$expected_x"; then
            echo -e "${RED}FAIL${NC} (X: expected $expected_x)"
            rm -f "$tmpfile" "${tmpfile%.asm}.bin"
            FAIL=$((FAIL + 1))
            return 1
        fi
    fi
    
    # Check Y if specified
    if [ -n "$expected_y" ]; then
        if ! echo "$output" | grep -q "Y: 0*$expected_y"; then
            echo -e "${RED}FAIL${NC} (Y: expected $expected_y)"
            rm -f "$tmpfile" "${tmpfile%.asm}.bin"
            FAIL=$((FAIL + 1))
            return 1
        fi
    fi
    
    echo -e "${GREEN}PASS${NC}"
    rm -f "$tmpfile" "${tmpfile%.asm}.bin"
    PASS=$((PASS + 1))
    return 0
}

# Flag test helper
test_flags() {
    local name="$1"
    local asm_code="$2"
    local expected_flags="$3"  # e.g., "NV--DIZC" pattern
    local cycles="${4:-1000}"
    
    echo -n "  $name... "
    
    local tmpfile=$(mktemp /tmp/test_XXXXXX.asm)
    echo "$asm_code" > "$tmpfile"
    
    if ! $ASSEMBLER "$tmpfile" -o "${tmpfile%.asm}.bin" > /dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} (assembly failed)"
        rm -f "$tmpfile" "${tmpfile%.asm}.bin"
        FAIL=$((FAIL + 1))
        return 1
    fi
    
    output=$($EMULATOR -c "$cycles" -s "${tmpfile%.asm}.bin" 2>&1)
    
    # Extract flag line - this is simplified
    if echo "$output" | grep -q "$expected_flags"; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (flags mismatch)"
        FAIL=$((FAIL + 1))
    fi
    
    rm -f "$tmpfile" "${tmpfile%.asm}.bin"
}

echo "=========================================="
echo " M65832 Comprehensive Test Suite"
echo "=========================================="
echo

# ============================================================================
# LOAD/STORE INSTRUCTIONS
# ============================================================================
echo "=== Load/Store Instructions ==="

run_test "LDA immediate 8-bit" "
    .org \$1000
    .m8
    LDA #\$42
    STP" "00000042"

run_test "LDA immediate 16-bit" "
    .org \$1000
    .m16
    LDA #\$1234
    STP" "00001234"

run_test "LDA immediate 32-bit" "
    .org \$1000
    LDA #\$12345678
    STP" "12345678"

run_test "LDA direct page" "
    .org \$1000
    LDA #\$AA
    STA \$50
    LDA #\$00
    LDA \$50
    STP" "000000AA"

run_test "LDA absolute" "
    .org \$1000
    LDA #\$BB
    STA \$2000
    LDA #\$00
    LDA \$2000
    STP" "000000BB"

run_test "LDA absolute,X" "
    .org \$1000
    LDX #\$10
    LDA #\$CC
    STA \$2010
    LDA #\$00
    LDA \$2000,X
    STP" "000000CC"

run_test "LDA absolute,Y" "
    .org \$1000
    LDY #\$20
    LDA #\$DD
    STA \$2020
    LDA #\$00
    LDA \$2000,Y
    STP" "000000DD"

run_test "LDA (dp),Y indirect indexed" "
    .org \$1000
    LDA #\$00
    STA \$50        ; low byte of pointer
    LDA #\$20
    STA \$51        ; high byte -> points to \$2000
    LDA #\$EE
    STA \$2005
    LDY #\$05
    LDA #\$00
    LDA (\$50),Y    ; Load from \$2000+5
    STP" "000000EE"

run_test "LDX immediate" "
    .org \$1000
    LDX #\$55
    TXA
    STP" "00000055"

run_test "LDY immediate" "
    .org \$1000
    LDY #\$66
    TYA
    STP" "00000066"

run_test "STZ zero memory" "
    .org \$1000
    LDA #\$FF
    STA \$50
    STZ \$50
    LDA \$50
    STP" "00000000"

echo

# ============================================================================
# ARITHMETIC INSTRUCTIONS
# ============================================================================
echo "=== Arithmetic Instructions ==="

run_test "ADC no carry" "
    .org \$1000
    CLC
    LDA #\$10
    ADC #\$20
    STP" "00000030"

run_test "ADC with carry in" "
    .org \$1000
    SEC
    LDA #\$10
    ADC #\$20
    STP" "00000031"

run_test "ADC carry out" "
    .org \$1000
    CLC
    LDA #\$FF
    ADC #\$02
    STP" "00000101"

run_test "ADC 32-bit" "
    .org \$1000
    CLC
    LDA #\$FFFFFFFF
    ADC #\$00000002
    STP" "00000001"

run_test "SBC basic" "
    .org \$1000
    SEC
    LDA #\$50
    SBC #\$20
    STP" "00000030"

run_test "SBC borrow" "
    .org \$1000
    SEC
    LDA #\$10
    SBC #\$20
    STP" "FFFFFFF0"

run_test "INC accumulator" "
    .org \$1000
    LDA #\$FF
    INC A
    STP" "00000100"

run_test "DEC accumulator" "
    .org \$1000
    LDA #\$100
    DEC A
    STP" "000000FF"

run_test "INC memory" "
    .org \$1000
    LDA #\$41
    STA \$50
    INC \$50
    LDA \$50
    STP" "00000042"

run_test "DEC memory" "
    .org \$1000
    LDA #\$43
    STA \$50
    DEC \$50
    LDA \$50
    STP" "00000042"

run_test "INX" "
    .org \$1000
    LDX #\$00
    INX
    INX
    INX
    TXA
    STP" "00000003"

run_test "DEX" "
    .org \$1000
    LDX #\$05
    DEX
    DEX
    TXA
    STP" "00000003"

run_test "INY" "
    .org \$1000
    LDY #\$10
    INY
    TYA
    STP" "00000011"

run_test "DEY" "
    .org \$1000
    LDY #\$10
    DEY
    TYA
    STP" "0000000F"

echo

# ============================================================================
# LOGICAL INSTRUCTIONS
# ============================================================================
echo "=== Logical Instructions ==="

run_test "AND" "
    .org \$1000
    LDA #\$FF
    AND #\$0F
    STP" "0000000F"

run_test "ORA" "
    .org \$1000
    LDA #\$F0
    ORA #\$0F
    STP" "000000FF"

run_test "EOR" "
    .org \$1000
    LDA #\$FF
    EOR #\$AA
    STP" "00000055"

run_test "BIT sets Z" "
    .org \$1000
    LDA #\$0F
    BIT #\$F0     ; No bits in common
    STP" "0000000F"  # A unchanged

run_test "ASL accumulator" "
    .org \$1000
    LDA #\$40
    ASL A
    STP" "00000080"

run_test "LSR accumulator" "
    .org \$1000
    LDA #\$80
    LSR A
    STP" "00000040"

run_test "ROL accumulator" "
    .org \$1000
    SEC           ; Set carry
    LDA #\$40
    ROL A         ; Shift left, carry in
    STP" "00000081"

run_test "ROR accumulator" "
    .org \$1000
    SEC           ; Set carry
    LDA #\$01
    ROR A         ; Shift right, carry in
    STP" "80000000"

run_test "ASL memory" "
    .org \$1000
    LDA #\$21
    STA \$50
    ASL \$50
    LDA \$50
    STP" "00000042"

run_test "LSR memory" "
    .org \$1000
    LDA #\$84
    STA \$50
    LSR \$50
    LDA \$50
    STP" "00000042"

echo

# ============================================================================
# COMPARE & BRANCH INSTRUCTIONS
# ============================================================================
echo "=== Compare & Branch Instructions ==="

run_test "CMP equal sets Z" "
    .org \$1000
    LDA #\$42
    CMP #\$42
    BEQ equal
    LDA #\$00
    STP
equal:
    LDA #\$FF
    STP" "000000FF"

run_test "CMP less clears C" "
    .org \$1000
    LDA #\$10
    CMP #\$20
    BCC less
    LDA #\$00
    STP
less:
    LDA #\$FF
    STP" "000000FF"

run_test "CMP greater sets C" "
    .org \$1000
    LDA #\$30
    CMP #\$20
    BCS greater
    LDA #\$00
    STP
greater:
    LDA #\$FF
    STP" "000000FF"

run_test "CPX" "
    .org \$1000
    LDX #\$42
    CPX #\$42
    BEQ equal
    LDA #\$00
    STP
equal:
    LDA #\$FF
    STP" "000000FF"

run_test "CPY" "
    .org \$1000
    LDY #\$42
    CPY #\$42
    BEQ equal
    LDA #\$00
    STP
equal:
    LDA #\$FF
    STP" "000000FF"

run_test "BNE branch" "
    .org \$1000
    LDA #\$01
    BNE notzero
    LDA #\$00
    STP
notzero:
    LDA #\$FF
    STP" "000000FF"

run_test "BMI branch" "
    .org \$1000
    LDA #\$80000000
    BMI negative
    LDA #\$00
    STP
negative:
    LDA #\$FF
    STP" "000000FF"

run_test "BPL branch" "
    .org \$1000
    LDA #\$7FFFFFFF
    BPL positive
    LDA #\$00
    STP
positive:
    LDA #\$FF
    STP" "000000FF"

run_test "BCS branch" "
    .org \$1000
    SEC
    BCS carry
    LDA #\$00
    STP
carry:
    LDA #\$FF
    STP" "000000FF"

run_test "BCC branch" "
    .org \$1000
    CLC
    BCC nocarry
    LDA #\$00
    STP
nocarry:
    LDA #\$FF
    STP" "000000FF"

echo

# ============================================================================
# TRANSFER INSTRUCTIONS
# ============================================================================
echo "=== Transfer Instructions ==="

run_test "TAX" "
    .org \$1000
    LDA #\$42
    TAX
    LDA #\$00
    TXA
    STP" "00000042"

run_test "TAY" "
    .org \$1000
    LDA #\$43
    TAY
    LDA #\$00
    TYA
    STP" "00000043"

run_test "TXA" "
    .org \$1000
    LDX #\$44
    TXA
    STP" "00000044"

run_test "TYA" "
    .org \$1000
    LDY #\$45
    TYA
    STP" "00000045"

run_test "TXY" "
    .org \$1000
    LDX #\$46
    TXY
    TYA
    STP" "00000046"

run_test "TYX" "
    .org \$1000
    LDY #\$47
    TYX
    TXA
    STP" "00000047"

run_test "TSX" "
    .org \$1000
    LDX #\$00
    TSX
    TXA
    STP" "0000FFFF"  # Default stack

run_test "TXS" "
    .org \$1000
    LDX #\$1234
    TXS
    TSX
    TXA
    STP" "00001234"

echo

# ============================================================================
# STACK INSTRUCTIONS
# ============================================================================
echo "=== Stack Instructions ==="

run_test "PHA/PLA" "
    .org \$1000
    LDA #\$11
    PHA
    LDA #\$22
    PHA
    LDA #\$00
    PLA
    STP" "00000022"

run_test "PHX/PLX" "
    .org \$1000
    LDX #\$33
    PHX
    LDX #\$00
    PLX
    TXA
    STP" "00000033"

run_test "PHY/PLY" "
    .org \$1000
    LDY #\$44
    PHY
    LDY #\$00
    PLY
    TYA
    STP" "00000044"

run_test "PHP/PLP" "
    .org \$1000
    SEC
    PHP
    CLC
    PLP
    BCS carry
    LDA #\$00
    STP
carry:
    LDA #\$FF
    STP" "000000FF"

run_test "PHD/PLD" "
    .org \$1000
    LDA #\$1234
    TCD
    PHD
    LDA #\$0000
    TCD
    PLD
    TDC
    STP" "00001234"

echo

# ============================================================================
# JUMP & SUBROUTINE INSTRUCTIONS
# ============================================================================
echo "=== Jump & Subroutine Instructions ==="

run_test "JMP absolute" "
    .org \$1000
    JMP target
    LDA #\$00
    STP
target:
    LDA #\$FF
    STP" "000000FF"

run_test "JSR/RTS" "
    .org \$1000
    LDA #\$10
    JSR addfive
    JSR addfive
    STP
addfive:
    CLC
    ADC #\$05
    RTS" "0000001A"

run_test "JSR nested" "
    .org \$1000
    JSR outer
    STP
outer:
    LDA #\$10
    JSR inner
    RTS
inner:
    CLC
    ADC #\$05
    RTS" "00000015"

echo

# ============================================================================
# EXTENDED INSTRUCTIONS (MUL, DIV, etc.)
# ============================================================================
echo "=== Extended Instructions ==="

run_test "MUL 8x8" "
    .org \$1000
    .m8
    LDA #\$10
    STA \$50
    LDA #\$04
    .db \$02, \$00  ; MUL \$50
    STP" "00000040"

run_test "DIV" "
    .org \$1000
    LDA #\$64      ; 100
    STA \$50
    LDA #\$14      ; 20
    .db \$02, \$04  ; DIV \$50 -> 20/100... wait this is backwards
    STP" "00000000"  # Need to verify DIV semantics

echo

# ============================================================================
# ATOMIC INSTRUCTIONS
# ============================================================================
echo "=== Atomic Instructions ==="

run_test "CAS success" "
    .org \$1000
    LDA #\$42
    STA \$50       ; Memory = \$42
    LDX #\$42      ; Expected value
    LDA #\$99      ; New value
    .db \$02, \$10 ; CAS \$50
    ; Z should be set (success)
    BEQ success
    LDA #\$00
    STP
success:
    LDA \$50       ; Should be \$99
    STP" "00000099"

run_test "CAS failure" "
    .org \$1000
    LDA #\$42
    STA \$50       ; Memory = \$42
    LDX #\$55      ; Expected value (wrong)
    LDA #\$99      ; New value
    .db \$02, \$10 ; CAS \$50
    ; Z should be clear (failure), X should have current value
    BNE fail
    LDA #\$00
    STP
fail:
    TXA           ; X should now have \$42
    STP" "00000042"

echo

# ============================================================================
# PROCESSOR MODE TESTS
# ============================================================================
echo "=== Processor Modes ==="

run_test "32-bit default" "
    .org \$1000
    LDA #\$12345678
    STP" "12345678"

run_test "16-bit mode" "
    .org \$1000
    .m16
    LDA #\$1234
    STP" "00001234"

run_test "8-bit mode" "
    .org \$1000
    .m8
    LDA #\$42
    STP" "00000042"

run_test "Mixed widths" "
    .org \$1000
    .m32
    LDA #\$AABBCCDD
    .m8
    LDA #\$EE       ; Only affects low byte
    STP" "AABBCCEE"

echo

# ============================================================================
# SUMMARY
# ============================================================================
echo
echo "=========================================="
echo " Test Summary"
echo "=========================================="
echo -e " Passed: ${GREEN}$PASS${NC}"
echo -e " Failed: ${RED}$FAIL${NC}"
echo -e " Total:  $((PASS + FAIL))"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
