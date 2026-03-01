// Test inline assembly with stack-relative addressing
// Verifies that ,S suffix generates correct stack-relative opcodes:
//   STA offset,S -> opcode 0x83 (not 0x8D absolute)
//   LDA offset,S -> opcode 0xA3 (not 0xAD absolute)
//   CMP offset,S -> opcode 0xC3
//   ADC/SBC/AND/ORA/EOR offset,S -> 0x63/0xE3/0x23/0x03/0x43

int main(void) {
    int failures = 0;

    // Test 1: STA/LDA round-trip via stack-relative addressing
    // Push a value, store another via ,S, load it back
    {
        int result;
        asm volatile(
            "LDA #42\n"
            "PHA\n"              // Push 42 onto stack (SP decrements by 4)
            "LDA #99\n"
            "STA 1,S\n"         // Overwrite the value at SP+1 with 99
            "LDA 1,S\n"         // Load it back
            "STA %0\n"
            "PLA"                // Clean up stack
            : "=r"(result)
            :
            : "a"
        );
        if (result != 99) failures++;
    }

    // Test 2: Store and load multiple values via stack-relative
    {
        int val1, val2;
        asm volatile(
            "LDA #0\n"
            "PHA\n"              // Reserve slot 2 (SP+5..SP+8)
            "PHA\n"              // Reserve slot 1 (SP+1..SP+4)
            "LDA #100\n"
            "STA 1,S\n"         // Store 100 at slot 1
            "LDA #200\n"
            "STA 5,S\n"         // Store 200 at slot 2
            "LDA 1,S\n"         // Load slot 1
            "STA %0\n"
            "LDA 5,S\n"         // Load slot 2
            "STA %1\n"
            "PLA\n"              // Clean up slot 1
            "PLA"                // Clean up slot 2
            : "=r"(val1), "=r"(val2)
            :
            : "a"
        );
        if (val1 != 100) failures++;
        if (val2 != 200) failures++;
    }

    // Test 3: ADC with stack-relative operand
    {
        int result;
        asm volatile(
            "LDA #50\n"
            "PHA\n"              // Push 50
            "LDA #25\n"
            "CLC\n"
            "ADC 1,S\n"         // Add stack value (50) to A (25) = 75
            "STA %0\n"
            "PLA"                // Clean up
            : "=r"(result)
            :
            : "a"
        );
        if (result != 75) failures++;
    }

    // Test 4: AND with stack-relative operand
    {
        int result;
        asm volatile(
            "LDA #255\n"        // 0xFF
            "PHA\n"
            "LDA #170\n"        // 0xAA
            "AND 1,S\n"         // 0xAA & 0xFF = 0xAA
            "STA %0\n"
            "PLA"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 170) failures++;  // 0xAA = 170
    }

    // Test 5: ORA with stack-relative operand
    {
        int result;
        asm volatile(
            "LDA #170\n"        // 0xAA
            "PHA\n"
            "LDA #85\n"         // 0x55
            "ORA 1,S\n"         // 0x55 | 0xAA = 0xFF
            "STA %0\n"
            "PLA"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 255) failures++;  // 0xFF = 255
    }

    // Test 6: EOR with stack-relative operand
    {
        int result;
        asm volatile(
            "LDA #255\n"        // 0xFF
            "PHA\n"
            "LDA #170\n"        // 0xAA
            "EOR 1,S\n"         // 0xAA ^ 0xFF = 0x55
            "STA %0\n"
            "PLA"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 85) failures++;   // 0x55 = 85
    }

    // Test 7: CMP with stack-relative operand (equal case)
    {
        int result;
        asm volatile(
            "LDA #42\n"
            "PHA\n"
            "LDA #42\n"
            "CMP 1,S\n"         // Compare A(42) with stack(42) -> Z=1
            "LDA #0\n"
            "ADC #0\n"          // If carry set (A >= mem), adds 1
            "STA %0\n"
            "PLA"
            : "=r"(result)
            :
            : "a"
        );
        // CMP sets carry if A >= operand, so result should be 1
        if (result != 1) failures++;
    }

    // Test 8: SBC with stack-relative operand
    {
        int result;
        asm volatile(
            "LDA #10\n"
            "PHA\n"
            "LDA #50\n"
            "SEC\n"
            "SBC 1,S\n"         // 50 - 10 = 40
            "STA %0\n"
            "PLA"
            : "=r"(result)
            :
            : "a"
        );
        if (result != 40) failures++;
    }

    return failures;
}
