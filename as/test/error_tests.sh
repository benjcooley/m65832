#!/bin/bash
# Test error handling in the assembler
# These tests verify the assembler handles malformed input gracefully

ASSEMBLER="../m65832as"
PASS=0
FAIL=0
TIMEOUT_SEC=2

cd "$(dirname "$0")"

echo "=== Error Handling Tests ==="
echo

# Run assembler with timeout (macOS compatible)
run_with_timeout() {
    local input="$1"
    local output="$2"
    local logfile="$3"
    
    # Start assembler in background
    $ASSEMBLER "$input" -o "$output" > "$logfile" 2>&1 &
    local pid=$!
    
    # Wait with timeout
    local count=0
    while [ $count -lt $TIMEOUT_SEC ]; do
        if ! kill -0 $pid 2>/dev/null; then
            # Process finished
            wait $pid
            return $?
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # Timeout - kill the process
    kill -9 $pid 2>/dev/null
    wait $pid 2>/dev/null
    return 124  # Timeout exit code
}

# Test function - expects assembler to fail (exit non-zero) without hanging
test_error() {
    local name="$1"
    local code="$2"
    
    echo -n "Test: $name... "
    
    echo "$code" > /tmp/error_test.asm
    
    run_with_timeout /tmp/error_test.asm /tmp/error_test.bin /tmp/error_test.out
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo "FAIL (timeout - infinite loop?)"
        FAIL=$((FAIL + 1))
    elif [ $exit_code -ne 0 ]; then
        echo "PASS (error detected)"
        PASS=$((PASS + 1))
    else
        echo "FAIL (should have failed but didn't)"
        FAIL=$((FAIL + 1))
    fi
}

# Test function - expects assembler to succeed
test_success() {
    local name="$1"
    local code="$2"
    
    echo -n "Test: $name... "
    
    echo "$code" > /tmp/success_test.asm
    
    run_with_timeout /tmp/success_test.asm /tmp/success_test.bin /tmp/success_test.out
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo "FAIL (timeout)"
        FAIL=$((FAIL + 1))
    elif [ $exit_code -eq 0 ]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (exit code $exit_code)"
        cat /tmp/success_test.out
        FAIL=$((FAIL + 1))
    fi
}

echo "--- Syntax Errors ---"
test_error "Unknown instruction" "    FOOBAR"
test_error "Invalid operand" "    LDA ####"
test_error "Missing operand" "    LDA"
test_error "Unclosed string" '    .BYTE "hello'
test_error "Invalid number" "    LDA #\$GGGG"
test_error "Undefined symbol" "    JMP NOWHERE"

echo
echo "--- Edge Cases (should succeed) ---"
test_success "Empty file" ""
test_success "Only comments" "; This is a comment
; Another comment"
test_success "Comment after .BYTE" "    .BYTE \$01, \$02  ; comment"
test_success "Comment after .WORD" "    .WORD \$1234  ; comment"
test_success "Comment after .LONG" "    .LONG \$123456  ; comment"
test_success "Comment after .DWORD" "    .DWORD \$12345678  ; comment"
test_success "Trailing whitespace" "    NOP    "
test_success "Mixed case mnemonics" "    nop
    Lda #\$12
    JMP start
start:
    rts"

echo
echo "--- Boundary Cases ---"
# MAX_LABEL is 64, so 64+ chars should fail (need more than 63 chars)
test_error "Label too long" "LABEL_THAT_IS_WAY_TOO_LONG_FOR_THE_ASSEMBLER_TO_HANDLE_PROPERLY_HERE: NOP"
# 63 chars is the max allowed
test_success "Max valid label" "LABEL_567890123456789012345678901234567890123456789012345678901: NOP"

echo
echo "--- Include Errors ---"
test_error "Missing include file" '    .INCLUDE "nonexistent.inc"'
test_error "Empty include filename" '    .INCLUDE ""'

echo
echo "--- Expression Errors ---"
test_error "Division by zero" "X = 10 / 0"
test_error "Unmatched parens" "    LDA #(1+2"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

# Cleanup
rm -f /tmp/error_test.asm /tmp/error_test.bin /tmp/error_test.out
rm -f /tmp/success_test.asm /tmp/success_test.bin /tmp/success_test.out

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
