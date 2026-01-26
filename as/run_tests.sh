#!/bin/bash
# M65832 Assembler/Disassembler Test Script

ASSEMBLER="./m65832as"
DISASSEMBLER="./m65832dis"

echo "=== M65832 Assembler/Disassembler Tests ==="
echo

# Build if needed
if [ ! -f "$ASSEMBLER" ] || [ ! -f "$DISASSEMBLER" ]; then
    echo "Building tools..."
    make
fi

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local input="$2"
    local expected_exit="$3"
    
    echo -n "Test: $name... "
    
    if $ASSEMBLER "$input" -o "${input%.asm}.bin" > /dev/null 2>&1; then
        actual_exit=0
    else
        actual_exit=1
    fi
    
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Assembler tests
echo "--- Assembler Tests ---"
run_test "Basic 6502/65816 instructions" "test/test1.asm" 0
run_test "M65832 extended instructions" "test/test2_ext.asm" 0
run_test "Include files" "test/test3_include.asm" 0
run_test "Sections" "test/test4_sections.asm" 0
run_test "Expressions" "test/test6_expressions.asm" 0
run_test "Shifter/extend instructions (R0-R63)" "test/test7_extended.asm" 0
run_test "Extended ALU ($02 $80-$97) instructions" "test/test8_ext_alu.asm" 0

# Test hex output
echo -n "Test: Intel HEX output... "
if $ASSEMBLER -h test/test1.asm -o test/test1.hex > /dev/null 2>&1; then
    if grep -q "^:10" test/test1.hex; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (invalid hex format)"
        FAIL=$((FAIL + 1))
    fi
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Test include path option
echo -n "Test: Include path (-I) option... "
if $ASSEMBLER -I test/inc test/test3_include.asm -o test/test3_include.bin > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Disassembler tests
echo
echo "--- Disassembler Tests ---"

echo -n "Test: Disassemble basic binary... "
if $DISASSEMBLER -o 0x1000 test/test1.bin > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble extended instructions... "
if $DISASSEMBLER -o 0x2000 test/test2_ext.bin > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble with hex output... "
if $DISASSEMBLER -x -o 0x1000 test/test1.bin 2>&1 | grep -q "^00001000.*EA.*NOP"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble extended prefix ($02)... "
if $DISASSEMBLER -x test/test2_ext.bin 2>&1 | grep -q "MUL"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble shifter/extend with R0-R63... "
if $DISASSEMBLER test/test7_extended.bin 2>&1 | grep -q "SHL R"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Summary
echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
