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
run_test "FPU load/store modes" "test/test9_fpu_loadstore.asm" 0
run_test "6502 mode (M8/X8)" "test/test9_6502_mode.asm" 0
run_test "65816 mode (M16/X16)" "test/test10_65816_mode.asm" 0

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

# Test .LONG emits 4 bytes
echo -n "Test: .LONG emits 4 bytes... "
if $ASSEMBLER test/test9_long.asm -o /tmp/test9_long.bin > /dev/null 2>&1; then
    bytes=$(wc -c < /tmp/test9_long.bin | tr -d ' ')
    if [ "$bytes" = "5" ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected 5 bytes, got $bytes)"
        FAIL=$((FAIL + 1))
    fi
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

# Assemble test11 for register name tests
echo -n "Test: Assemble 32-bit mode register names... "
if $ASSEMBLER test/test11_dis_regnames.asm -o test/test11_dis_regnames.bin > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble DP with register names (R=1)... "
if $DISASSEMBLER -m32 -x32 test/test11_dis_regnames.bin 2>&1 | grep -q "LDX R8,Y"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble DP without register names (-R)... "
if $DISASSEMBLER -m32 -x32 -R test/test11_dis_regnames.bin 2>&1 | grep -q 'LDX \$20,Y'; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble B+ addressing in 32-bit mode... "
if $DISASSEMBLER -m32 -x32 test/test11_dis_regnames.bin 2>&1 | grep -q 'B+\$'; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble extended ALU register names... "
if $DISASSEMBLER -m32 -x32 test/test11_dis_regnames.bin 2>&1 | grep -q "LD R5,(R4),Y"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "Test: Disassemble 32-bit branch offsets... "
if $DISASSEMBLER -m32 -x32 -x -o 0x8000 test/test11_dis_regnames.bin 2>&1 | grep -q "BEQ \$8044"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# Round-trip tests: assemble, disassemble, verify key patterns
echo
echo "--- Round-trip Tests ---"

run_roundtrip() {
    local name="$1"
    local asm="$2"
    local dis_flags="$3"
    shift 3

    echo -n "Test: $name... "

    if ! $ASSEMBLER "$asm" -o "${asm%.asm}.bin" > /dev/null 2>&1; then
        echo "FAIL (assembly failed)"
        FAIL=$((FAIL + 1))
        return
    fi

    local output
    output=$($DISASSEMBLER $dis_flags -x "${asm%.asm}.bin" 2>&1)

    local all_ok=1
    local missing=""
    for pattern in "$@"; do
        if ! echo "$output" | grep -qF "$pattern"; then
            all_ok=0
            missing="$missing [$pattern]"
        fi
    done

    if [ "$all_ok" -eq 1 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (missing:$missing)"
        FAIL=$((FAIL + 1))
    fi
}

# 8-bit round-trip: assemble with .M8/.X8, disassemble with -m8 -x8 -R
run_roundtrip "8-bit round-trip (implied)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    "NOP" "CLC" "SEC" "CLI" "SEI" "CLV" "CLD" "SED" \
    "INX" "INY" "DEX" "DEY" \
    "TAX" "TXA" "TAY" "TYA" "TSX" "TXS" \
    "PHA" "PLA" "PHP" "PLP" "PHX" "PLX" "PHY" "PLY" \
    "PHD" "PLD" "PHK" "RTL" "PHB" "PLB" "WAI" "XBA" \
    "TCD" "TDC" "TCS" "TSC" "TXY" "TYX" "XCE"

run_roundtrip "8-bit round-trip (immediates)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA #$42' 'LDX #$33' 'LDY #$55' \
    'ADC #$10' 'SBC #$20' 'AND #$0F' 'ORA #$F0' 'EOR #$AA' 'CMP #$77' \
    'CPX #$88' 'CPY #$99' 'BIT #$55' 'SEP #$30' 'REP #$20'

run_roundtrip "8-bit round-trip (DP/abs)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA $10' 'STA $40' 'LDX $20' 'STX $50' 'LDY $30' 'STY $60' 'STZ $70' \
    'LDA $1234' 'STA $4567' 'LDX $2345' 'LDY $3456' \
    'LDA $1234,X' 'STA $3456,X' 'LDA $1234,Y' 'STA $3456,Y'

run_roundtrip "8-bit round-trip (indirect)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA ($10,X)' 'STA ($20,X)' 'LDA ($10),Y' 'STA ($20),Y' \
    'LDA ($30)' 'STA ($40)'

run_roundtrip "8-bit round-trip (cc=11 [dp]/[dp],Y)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA [$10]' 'STA [$20]' 'ADC [$10]' 'SBC [$20]' 'AND [$30]' 'ORA [$40]' 'EOR [$50]' 'CMP [$60]' \
    'LDA [$10],Y' 'STA [$20],Y' 'ADC [$10],Y' 'SBC [$20],Y' 'AND [$30],Y' 'ORA [$40],Y' 'EOR [$50],Y' 'CMP [$60],Y'

run_roundtrip "8-bit round-trip (cc=11 sr,S / (sr,S),Y)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA $05,S' 'STA $06,S' 'ADC $07,S' 'SBC $08,S' 'AND $09,S' 'ORA $0A,S' 'EOR $0B,S' 'CMP $0C,S' \
    'LDA ($05,S),Y' 'STA ($06,S),Y' 'ADC ($07,S),Y' 'SBC ($08,S),Y' 'AND ($09,S),Y' 'ORA ($0A,S),Y' 'EOR ($0B,S),Y' 'CMP ($0C,S),Y'

run_roundtrip "8-bit round-trip (cc=11 long/long,X)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    'LDA $123456' 'STA $234567' 'LDA $345678,X' 'STA $456789,X' \
    'ADC $123456' 'SBC $234567' 'AND $345678' 'ORA $456789' 'EOR $123456' 'CMP $234567' \
    'ADC $123456,X' 'SBC $234567,X' 'AND $345678,X' 'ORA $456789,X' 'EOR $123456,X' 'CMP $234567,X'

run_roundtrip "8-bit round-trip (branches/jumps)" \
    "test/test_roundtrip_8bit.asm" "-m8 -x8 -R -o 0x8000" \
    "BEQ" "BNE" "BCS" "BCC" "BMI" "BPL" "BVS" "BVC" "BRA" \
    'JMP ($1234)' 'JMP ($1234,X)' 'JML $123456' 'JSL $234567' \
    "BRK" "RTS" "RTI" "STP"

# 16-bit round-trip
run_roundtrip "16-bit round-trip (immediates)" \
    "test/test_roundtrip_16bit.asm" "-m16 -x16 -R -o 0x8000" \
    'LDA #$1234' 'LDX #$5678' 'LDY #$9ABC' \
    'ADC #$1111' 'SBC #$2222' 'AND #$3333' 'ORA #$4444' 'EOR #$5555' 'CMP #$6666' \
    'CPX #$7777' 'CPY #$8888'

run_roundtrip "16-bit round-trip (cc=11 modes)" \
    "test/test_roundtrip_16bit.asm" "-m16 -x16 -R -o 0x8000" \
    'LDA [$10]' 'STA [$20]' 'LDA [$10],Y' 'STA [$20],Y' \
    'LDA $05,S' 'STA $06,S' 'LDA ($05,S),Y' 'STA ($06,S),Y' \
    'LDA $123456' 'STA $234567' 'LDA $345678,X' 'STA $456789,X'

run_roundtrip "16-bit round-trip (all ALU long)" \
    "test/test_roundtrip_16bit.asm" "-m16 -x16 -R -o 0x8000" \
    'ADC $123456' 'SBC $234567' 'AND $345678' 'ORA $456789' 'EOR $123456' 'CMP $234567' \
    'ADC $123456,X' 'SBC $234567,X' 'AND $345678,X' 'ORA $456789,X' 'EOR $123456,X' 'CMP $234567,X'

run_roundtrip "16-bit round-trip (all ALU (sr,S),Y / [dp],Y)" \
    "test/test_roundtrip_16bit.asm" "-m16 -x16 -R -o 0x8000" \
    'ADC ($07,S),Y' 'SBC ($08,S),Y' 'AND ($09,S),Y' 'ORA ($0A,S),Y' 'EOR ($0B,S),Y' 'CMP ($0C,S),Y' \
    'ADC [$10],Y' 'SBC [$20],Y' 'AND [$30],Y' 'ORA [$40],Y' 'EOR [$50],Y' 'CMP [$60],Y'

# 32-bit round-trip (register window names on by default)
run_roundtrip "32-bit round-trip (immediates)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDA #$12345678' 'LDX #$9ABCDEF0' 'LDY #$11223344' \
    'ADC #$AABBCCDD' 'SBC #$11111111' 'AND #$22222222' 'ORA #$33333333' 'EOR #$44444444' 'CMP #$55555555' \
    'CPX #$66666666' 'CPY #$77777777'

run_roundtrip "32-bit round-trip (DP with reg names)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDA R4' 'STA R8' 'LDX R12' 'LDY R16' 'STX R20' 'STY R24' 'STZ R28' \
    'ADC R4' 'SBC R8' 'AND R12' 'ORA R16' 'EOR R20' 'CMP R24'

run_roundtrip "32-bit round-trip (DP indexed)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDA R4,X' 'STA R8,X' 'LDX R4,Y' 'STX R8,Y'

run_roundtrip "32-bit round-trip (DP indirect)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDA (R4,X)' 'STA (R8,X)' 'LDA (R4),Y' 'STA (R8),Y' \
    'LDA (R12)' 'STA (R16)'

run_roundtrip "32-bit round-trip (cc=11 non-long)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDA [R4]' 'STA [R8]' 'LDA [R4],Y' 'STA [R8],Y' \
    'LDA $05,S' 'STA $06,S' 'LDA ($05,S),Y' 'STA ($06,S),Y'

run_roundtrip "32-bit round-trip (implied)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    "PHD" "PLD" "PHB" "PLB" "WAI" "XBA" \
    "TAX" "TXA" "TAY" "TYA" "TSX" "TXS" \
    "TCD" "TDC" "TCS" "TSC" "TXY" "TYX"

run_roundtrip "32-bit round-trip (extended: mul/div/atomics)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'MUL R8' 'MULU R12' 'DIV R16' 'DIVU R20' \
    'MUL B+$1234' 'MULU B+$2345' 'DIV B+$3456' 'DIVU B+$4567' \
    'CAS R8' 'LLI R12' 'SCI R16' \
    "FENCE" "FENCER" "FENCEW"

run_roundtrip "32-bit round-trip (extended: transfers/system)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    "TAB" "TBA" "TXB" "TBX" "TYB" "TBY" "TSPB" "TTA" "TAT" \
    "RSET" "RCLR" 'TRAP #$10' 'SEPE #$03' 'REPE #$03'

run_roundtrip "32-bit round-trip (FPU arithmetic)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'FADD.S F0, F1' 'FSUB.S F2, F3' 'FMUL.S F4, F5' 'FDIV.S F6, F7' \
    'FNEG.S F0, F1' 'FABS.S F2, F3' 'FCMP.S F4, F5' \
    'F2I.S F0' 'I2F.S F1' 'FMOV.S F8, F9' 'FSQRT.S F10, F11' \
    'FADD.D F0, F1' 'FSUB.D F2, F3' 'FMUL.D F4, F5' 'FDIV.D F6, F7' \
    'FMOV.D F12, F13' 'FSQRT.D F14, F15'

run_roundtrip "32-bit round-trip (FPU load/store)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDF F0, $20' 'LDF F5, $1234' 'STF F0, $30' 'STF F15, $2345'

run_roundtrip "32-bit round-trip (FPU transfers)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'FTOA F0' 'FTOT F1' 'ATOF F2' 'TTOF F3' \
    'FCVT.DS F4, F5' 'FCVT.SD F6, F7'

run_roundtrip "32-bit round-trip (extended: LDQ/STQ/LEA)" \
    "test/test_roundtrip_32bit.asm" "-m32 -x32 -o 0x8000" \
    'LDQ R8' 'LDQ B+$1234' 'STQ R12' 'STQ B+$2345' \
    'LEA R8' 'LEA R8,X' 'LEA B+$1234' 'LEA B+$1234,X'

# Extended ALU round-trip tests ($02 $80-$97)
run_roundtrip "ext ALU: LDA.B addressing modes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'LDA.B R0' 'LDA.B R4,X' 'LDA.B R4,Y' \
    'LDA.B (R4,X)' 'LDA.B (R4),Y' 'LDA.B (R4)' \
    'LDA.B [R4]' 'LDA.B [R4],Y' \
    'LDA.B B+$1000' 'LDA.B B+$1000,X' 'LDA.B B+$1000,Y' \
    'LDA.B $00002000' 'LDA.B $00002000,X' 'LDA.B $00002000,Y' \
    'LDA.B #$42' 'LDA.B $10,S' 'LDA.B ($10,S),Y'

run_roundtrip "ext ALU: LDA.W addressing modes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'LDA.W R0' 'LDA.W R4,X' 'LDA.W R4,Y' \
    'LDA.W (R4,X)' 'LDA.W (R4),Y' 'LDA.W (R4)' \
    'LDA.W [R4]' 'LDA.W [R4],Y' \
    'LDA.W B+$1000' 'LDA.W B+$1000,X' 'LDA.W B+$1000,Y' \
    'LDA.W $00002000' 'LDA.W $00002000,X' 'LDA.W $00002000,Y' \
    'LDA.W #$1234' 'LDA.W $10,S' 'LDA.W ($10,S),Y'

run_roundtrip "ext ALU: LDA (32-bit default)" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'LDA B+$1000' 'LDA $00002000'


run_roundtrip "ext ALU: LD register-targeted" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'LD.B R4,R0' 'LD.B R4,R8,X' 'LD.B R4,#$55' \
    'LD.B R4,B+$1000' 'LD.B R4,$00002000' \
    'LD.W R4,R0' 'LD.W R4,#$ABCD' 'LD.W R4,B+$1000'

run_roundtrip "ext ALU: STA.B addressing modes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'STA.B R0' 'STA.B R4,X' 'STA.B R4,Y' \
    'STA.B (R4,X)' 'STA.B (R4),Y' 'STA.B (R4)' \
    'STA.B [R4]' 'STA.B [R4],Y' \
    'STA.B B+$1000' 'STA.B B+$1000,X' 'STA.B B+$1000,Y' \
    'STA.B $00002000' 'STA.B $00002000,X' 'STA.B $00002000,Y' \
    'STA.B $10,S' 'STA.B ($10,S),Y'

run_roundtrip "ext ALU: STA.W / STA (default)" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'STA.W R0' 'STA.W R4,X' 'STA.W B+$1000' 'STA.W $00002000' \
    'STA B+$1000' 'STA $00002000'


run_roundtrip "ext ALU: ST register-targeted" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'ST.B R4,R0' 'ST.B R4,R8,X' 'ST.B R4,B+$1000' 'ST.B R4,$00002000' \
    'ST.W R4,R0' 'ST.W R4,B+$1000'

run_roundtrip "ext ALU: ADC all sizes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'ADC.B A,#$10' 'ADC.B A,R0' 'ADC.B A,R4,X' 'ADC.B A,(R4),Y' \
    'ADC.B A,B+$1000' 'ADC.B A,$00002000' 'ADC.B A,$10,S' 'ADC.B A,($10,S),Y' \
    'ADC.W A,#$0100' 'ADC.W A,R0' 'ADC.W A,B+$1000' 'ADC A,B+$1000'

run_roundtrip "ext ALU: SBC all sizes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'SBC.B A,#$05' 'SBC.B A,R0' 'SBC.B A,R4,X' 'SBC.B A,(R4),Y' \
    'SBC.B A,B+$1000' 'SBC.B A,$00002000' 'SBC.B A,$10,S' 'SBC.B A,($10,S),Y' \
    'SBC.W A,#$0050' 'SBC.W A,R0' 'SBC A,B+$1000'

run_roundtrip "ext ALU: AND/ORA/EOR/CMP all sizes" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'AND.B A,#$0F' 'AND.B A,R0' 'AND.B A,R4,X' 'AND.B A,(R4),Y' \
    'AND.B A,B+$1000' 'AND.B A,$00002000' 'AND.W A,#$00FF' 'AND.W A,R0' 'AND A,B+$1000' \
    'ORA.B A,#$F0' 'ORA.B A,R0' 'ORA.W A,#$FF00' 'ORA.W A,R0' 'ORA A,B+$1000' \
    'EOR.B A,#$AA' 'EOR.B A,R0' 'EOR.W A,#$5555' 'EOR.W A,R0' 'EOR A,B+$1000' \
    'CMP.B A,#$42' 'CMP.B A,R0' 'CMP.W A,#$1234' 'CMP.W A,R0' 'CMP A,B+$1000'

run_roundtrip "ext ALU: BIT/TSB/TRB" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'BIT.B A,#$80' 'BIT.B A,R0' 'BIT.W A,#$8000' 'BIT.W A,R0' \
    'TSB.B A,R0' 'TSB.W A,R0' 'TSB A,B+$1000' 'TSB A,$00002000' \
    'TRB.B A,R0' 'TRB.W A,R0' 'TRB A,B+$1000' 'TRB A,$00002000'

run_roundtrip "ext ALU: INC/DEC/shifts (unary)" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'INC.B A' 'INC.W A' 'DEC.B A' 'DEC.W A' \
    'ASL.B A' 'ASL.W A' 'LSR.B A' 'LSR.W A' \
    'ROL.B A' 'ROL.W A' 'ROR.B A' 'ROR.W A'

run_roundtrip "ext ALU: STZ" \
    "test/test_roundtrip_ext_alu.asm" "-m32 -x32 -o 0x8000" \
    'STZ.B R0' 'STZ.W R0' 'STZ B+$1000' 'STZ $00002000'

# Summary
echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
