// Test inline assembly with shift and logic operations

int _c_main(void) {
    int failures = 0;
    
    // Test 1: ASL (arithmetic shift left) on accumulator
    {
        int val = 5;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // val * 2
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 10) failures++;
    }
    
    // Test 2: Multiple shifts (multiply by 8)
    {
        int val = 3;
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // *2 = 6
            "ASL A\n"        // *4 = 12
            "ASL A\n"        // *8 = 24
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 24) failures++;
    }
    
    // Test 3: LSR (logical shift right)
    {
        int val = 32;
        int result;
        asm volatile(
            "LDA %1\n"
            "LSR A\n"        // val / 2 = 16
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 16) failures++;
    }
    
    // Test 4: AND operation
    {
        int a = 0xFF;
        int b = 0x0F;
        int result;
        asm volatile(
            "LDA %1\n"
            "AND %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"
        );
        if (result != 0x0F) failures++;
    }
    
    // Test 5: ORA operation
    {
        int a = 0xF0;
        int b = 0x0F;
        int result;
        asm volatile(
            "LDA %1\n"
            "ORA %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"
        );
        if (result != 0xFF) failures++;
    }
    
    // Test 6: EOR operation
    {
        int a = 0xFF;
        int b = 0x0F;
        int result;
        asm volatile(
            "LDA %1\n"
            "EOR %2\n"
            "STA %0"
            : "=r"(result)
            : "r"(a), "r"(b)
            : "a"
        );
        if (result != 0xF0) failures++;
    }
    
    // Test 7: Combined shift and mask
    {
        int val = 0x12;  // 0001 0010
        int result;
        asm volatile(
            "LDA %1\n"
            "ASL A\n"        // 0010 0100 = 0x24
            "AND #$F0\n"     // 0010 0000 = 0x20
            "STA %0"
            : "=r"(result)
            : "r"(val)
            : "a"
        );
        if (result != 0x20) failures++;
    }
    
    return failures;
}
