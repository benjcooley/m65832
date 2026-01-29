// Test inline assembly with practical use cases (no branching)

int main(void) {
    int failures = 0;
    
    // Test 1: Multiply by 2 using shift
    {
        int val = 25;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 50) failures++;
    }
    
    // Test 2: Multiply by 4 using shifts
    {
        int val = 10;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"
            "ASL A\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 40) failures++;
    }
    
    // Test 3: Multiply by 3 using shift and add
    {
        int val = 7;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // *2
            "CLC\n"
            "ADC %1\n"       // *2 + *1 = *3
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 21) failures++;
    }
    
    // Test 4: Multiply by 5 using shifts and add
    {
        int val = 6;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // *2
            "ASL A\n"        // *4
            "CLC\n"
            "ADC %1\n"       // *4 + *1 = *5
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 30) failures++;
    }
    
    // Test 5: Multiply by 10 using shifts and adds
    {
        int val = 7;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // *2
            "ASL A\n"        // *4
            "CLC\n"
            "ADC %1\n"       // *4 + *1 = *5
            "ASL A\n"        // *10
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 70) failures++;
    }
    
    // Test 6: Divide by 2 using shift
    {
        int val = 50;
        int result;
        asm volatile(
            "LDA %1\n"
            "LSR A\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 25) failures++;
    }
    
    // Test 7: Divide by 4 using shifts
    {
        int val = 100;
        int result;
        asm volatile(
            "LDA %1\n"
            "LSR A\n"
            "LSR A\n"
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 25) failures++;
    }
    
    // Test 8: Mask low nibble
    {
        int val = 0xABCD;
        int result;
        asm volatile(
            "LDA %1\n"
            "AND #15\n"      // Keep low 4 bits
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 0x0D) failures++;
    }
    
    // Test 9: Mask high nibble of byte
    {
        int val = 0xABCD;
        int result;
        asm volatile(
            "LDA %1\n"
            "AND #240\n"     // Keep high 4 bits of low byte
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 0xC0) failures++;
    }
    
    // Test 10: Combine nibbles
    {
        int a = 0x05;        // Low nibble
        int b = 0x30;        // High nibble
        int result;
        asm volatile(
            "LDA %1\n"
            "ORA %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"
        );
        if (result != 0x35) failures++;
    }
    
    return failures;
}
